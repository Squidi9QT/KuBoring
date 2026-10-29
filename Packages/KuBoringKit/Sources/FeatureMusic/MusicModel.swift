import Foundation
import KuBoringCore
import AppKit
import Observation

/// Ключи настроек раздела «Музыка».
enum MusicKeys {
    static let showInClosed = SettingKey<Bool>("feature.music.showInClosed", default: true)
    static let animateBars = SettingKey<Bool>("feature.music.animateBars", default: true)
    /// "all" | "music" | "manual"
    static let sourceMode = SettingKey<String>("feature.music.sourceMode", default: MusicSourceMode.all)
    static let seenSources = SettingKey<[String]>("feature.music.seenSources", default: [])
    static let blockedSources = SettingKey<[String]>("feature.music.blockedSources", default: [])
    /// Кнопка «Текст песни» во вкладке (тексты с lrclib.net).
    static let lyricsEnabled = SettingKey<Bool>("feature.music.lyrics", default: true)
    /// Вкладка сейчас показывает текст вместо названия (запоминается).
    static let lyricsShown = SettingKey<Bool>("feature.music.lyricsShown", default: false)
}

/// Снимок состояния трека (позиция считается от timestamp).
struct MusicTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var playing: Bool
    var bundleID: String?

    /// Текущая позиция в секундах на момент `date`.
    func position(at date: Date) -> Double {
        var p = elapsed
        if playing {
            p += date.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1)
        }
        if duration > 0 { p = min(p, duration) }
        return max(0, p)
    }
}

@MainActor @Observable
final class MusicModel {
    private(set) var rawTrack: MusicTrack?
    private(set) var rawArtwork: NSImage?
    private(set) var rawAppIcon: NSImage?

    /// Хранилище настроек (для фильтра источников); задаётся фичей до start().
    @ObservationIgnored var settings: SettingsStore?

    /// Виден ли экран (пауза анимаций и таймлайнов) — один на модель, его читают все вьюхи музыки.
    let display = MusicDisplayState()

    /// Текст текущего трека.
    private(set) var lyrics: LyricsState = .idle
    @ObservationIgnored private let lyricsService = LyricsService()
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsKey: String?

    /// Загрузить текст для текущего трека, если ещё не загружен (вызывается, когда текст показан).
    func loadLyricsIfNeeded() {
        guard let t = track, settings?[MusicKeys.lyricsEnabled] ?? true else { return }
        let key = LyricsService.key(title: t.title, artist: t.artist)
        guard key != lyricsKey else { return }
        lyricsKey = key
        lyricsTask?.cancel()
        if let hit = lyricsService.cached(title: t.title, artist: t.artist) {
            lyrics = hit
            return
        }
        lyrics = .loading
        let service = lyricsService
        lyricsTask = Task { [weak self] in
            let state = await service.fetch(title: t.title, artist: t.artist, album: t.album, duration: t.duration)
            guard !Task.isCancelled, let self, self.lyricsKey == key else { return }
            self.lyrics = state
        }
    }

    /// Трек с учётом фильтра источников: запрещённый источник = «ничего не играет».
    var track: MusicTrack? {
        guard let t = rawTrack, isAllowed(bundleID: t.bundleID) else { return nil }
        return t
    }
    var artwork: NSImage? { track == nil ? nil : rawArtwork }
    var appIcon: NSImage? { track == nil ? nil : rawAppIcon }
    /// Что-то играет, но источник скрыт настройками.
    var sourceHidden: Bool { rawTrack != nil && track == nil }

    func isAllowed(bundleID: String?) -> Bool {
        guard let settings else { return true }
        switch settings[MusicKeys.sourceMode] {
        case MusicSourceMode.musicOnly:
            guard let id = bundleID else { return false }
            return MusicSources.musicApps.contains(id)
        case MusicSourceMode.manual:
            guard let id = bundleID else { return true }
            return !settings[MusicKeys.blockedSources].contains(id)
        default:
            return true
        }
    }

    private func recordSeen(_ id: String?) {
        guard let id, !id.isEmpty, let settings else { return }
        var seen = settings[MusicKeys.seenSources]
        guard !seen.contains(id) else { return }
        seen.append(id)
        if seen.count > 30 { seen.removeFirst(seen.count - 30) }
        settings[MusicKeys.seenSources] = seen
    }
    private(set) var unavailableReason: String?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var lastArtworkString: String?
    @ObservationIgnored private var iconBundleID: String?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var process: Process?
    /// После перемотки адаптер ещё какое-то время присылает старую позицию — до этого момента не верим ей.
    @ObservationIgnored private var seekGuardUntil: Date?
    @ObservationIgnored private var scriptPath: String?
    @ObservationIgnored private var frameworkPath: String?
    @ObservationIgnored private let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    @ObservationIgnored private let isoPlain = ISO8601DateFormatter()

    init() {}

    // MARK: Жизненный цикл

    func start(script: URL?, framework: URL?) {
        guard streamTask == nil else { return }
        guard let script, let framework else {
            unavailableReason = "Не найден адаптер MediaRemote"
            onChange?()
            return
        }
        unavailableReason = nil
        scriptPath = script.path
        frameworkPath = framework.path
        streamTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        rawTrack = nil
        rawArtwork = nil
        rawAppIcon = nil
        lastArtworkString = nil
        iconBundleID = nil
        lyricsTask?.cancel()
        lyricsTask = nil
        lyricsKey = nil
        lyrics = .idle
        onChange?()
    }

    // MARK: Поток

    private func runLoop() async {
        while !Task.isCancelled {
            let started = Date()
            await runOnce()
            if Task.isCancelled { break }
            // Если процесс падает сразу (нет прав и т.п.) — ждём дольше.
            let lived = Date().timeIntervalSince(started)
            let pause: UInt64 = lived < 3 ? 15_000_000_000 : 3_000_000_000
            try? await Task.sleep(nanoseconds: pause)
        }
    }

    private func runOnce() async {
        guard let script = scriptPath, let framework = frameworkPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script, framework, "stream", "--no-diff", "--debounce=100"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            unavailableReason = "Не удалось запустить адаптер"
            onChange?()
            return
        }
        process = p
        do {
            for try await line in out.fileHandleForReading.bytes.lines {
                handle(line: line)
            }
        } catch {
            // поток оборвался — перезапустим снаружи
        }
        if p.isRunning { p.terminate() }
        // Не затираем ссылку на более новый процесс (stop() + start() во время разбора старого).
        if process === p { process = nil }
        let proc = p
        await Task.detached { proc.waitUntilExit() }.value
    }

    // MARK: Разбор JSON

    private func parseDate(_ s: String) -> Date? {
        isoFrac.date(from: s) ?? isoPlain.date(from: s)
    }

    private func handle(line: String) {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let payload = (obj["payload"] as? [String: Any]) ?? obj

        let title = (payload["title"] as? String) ?? ""
        let bundle = (payload["parentApplicationBundleIdentifier"] as? String)
            ?? (payload["bundleIdentifier"] as? String)
        if title.isEmpty {
            if rawTrack != nil || rawArtwork != nil {
                rawTrack = nil
                rawArtwork = nil
                lastArtworkString = nil
                onChange?()
            }
            return
        }

        recordSeen(bundle)

        let timestamp: Date
        if let ts = payload["timestamp"] as? String, let d = parseDate(ts) {
            timestamp = d
        } else {
            timestamp = Date()
        }
        var newTrack = MusicTrack(
            title: title,
            artist: (payload["artist"] as? String) ?? "",
            album: (payload["album"] as? String) ?? "",
            duration: (payload["duration"] as? Double) ?? 0,
            elapsed: (payload["elapsedTime"] as? Double) ?? 0,
            timestamp: timestamp,
            rate: (payload["playbackRate"] as? Double) ?? 1,
            playing: (payload["playing"] as? Bool) ?? false,
            bundleID: bundle
        )
        applySeekGuard(to: &newTrack)

        // Обложка: декодируем только если строка изменилась.
        if let s = payload["artworkData"] as? String, !s.isEmpty {
            if s != lastArtworkString {
                lastArtworkString = s
                if let d = Data(base64Encoded: s, options: .ignoreUnknownCharacters) {
                    rawArtwork = NSImage(data: d)
                } else {
                    rawArtwork = nil
                }
            }
        } else {
            lastArtworkString = nil
            rawArtwork = nil
        }

        if bundle != iconBundleID {
            iconBundleID = bundle
            rawAppIcon = Self.icon(forBundleID: bundle)
        }
        if rawTrack != newTrack { rawTrack = newTrack }
        onChange?()
    }

    /// Пока плеер не применил перемотку, оставляем позицию, выставленную в seek(to:).
    /// Как только пришла позиция рядом с ожидаемой (или прошло 2 с, или сменился трек) — снова верим адаптеру.
    private func applySeekGuard(to track: inout MusicTrack) {
        guard let until = seekGuardUntil else { return }
        let now = Date()
        guard now < until, let current = rawTrack,
              current.title == track.title, current.bundleID == track.bundleID else {
            seekGuardUntil = nil
            return
        }
        if abs(track.position(at: now) - current.position(at: now)) < 1.5 {
            seekGuardUntil = nil
        } else {
            // От «сейчас», чтобы пауза во время ожидания не откатила позицию назад.
            track.elapsed = current.position(at: now)
            track.timestamp = now
        }
    }

    private static func icon(forBundleID id: String?) -> NSImage? {
        guard let id, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Команды

    /// Коды MRCommand: 2 — play/pause, 4 — следующий, 5 — предыдущий.
    func togglePlayPause() {
        if var t = rawTrack {
            let now = Date()
            t.elapsed = t.position(at: now)
            t.timestamp = now
            t.playing.toggle()
            rawTrack = t
            onChange?()
        }
        runAdapter(["send", "2"])
    }

    func next() { runAdapter(["send", "4"]) }
    func previous() { runAdapter(["send", "5"]) }

    /// Перемотка (секунды). Music и Spotify перематываем их собственной AppleScript-командой:
    /// MRMediaRemoteSetElapsedTime, через который перематывает адаптер, на macOS 26 всегда отвечает отказом.
    /// Остальные приложения — через адаптер (он принимает микросекунды).
    func seek(to seconds: Double) {
        var s = max(0, seconds)
        let before = rawTrack
        if var t = rawTrack {
            if t.duration > 0 { s = min(s, t.duration) }
            t.elapsed = s
            t.timestamp = Date()
            rawTrack = t
            seekGuardUntil = Date().addingTimeInterval(2)
            onChange?()
        }
        let onFailure: @MainActor () -> Void = { [weak self] in self?.seekFailed(restoring: before) }
        if let script = Self.seekScript(bundleID: before?.bundleID, seconds: s) {
            run("/usr/bin/osascript", ["-e", script], onFailure: onFailure)
        } else {
            runAdapter(["seek", String(Int(s * 1_000_000))], onFailure: onFailure)
        }
    }

    /// Плеер перемотку не принял — сразу возвращаем полоску на реальную позицию, а не держим «фальшивую» 2 с.
    private func seekFailed(restoring before: MusicTrack?) {
        seekGuardUntil = nil
        guard let before, let current = rawTrack,
              current.title == before.title, current.bundleID == before.bundleID else { return }
        var t = current
        let now = Date()
        t.elapsed = before.position(at: now)
        t.timestamp = now
        rawTrack = t
        onChange?()
    }

    /// AppleScript перемотки для плееров, которые его поддерживают; nil — перематывать через адаптер.
    private static func seekScript(bundleID: String?, seconds: Double) -> String? {
        guard let id = bundleID, ["com.apple.Music", "com.spotify.client"].contains(id) else { return nil }
        // String(format:) не зависит от локали: десятичная точка, как ждёт AppleScript.
        let position = String(format: "%.3f", seconds)
        return "tell application id \"\(id)\" to if it is running then set player position to \(position)"
    }

    private func runAdapter(_ args: [String], onFailure: (@MainActor () -> Void)? = nil) {
        guard let script = scriptPath, let framework = frameworkPath else { return }
        run("/usr/bin/perl", [script, framework] + args, onFailure: onFailure)
    }

    private func run(_ executable: String, _ args: [String], onFailure: (@MainActor () -> Void)? = nil) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        if let onFailure {
            p.terminationHandler = { proc in
                guard proc.terminationStatus != 0 else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { onFailure() } }
            }
        }
        do {
            try p.run()
        } catch {
            onFailure?()
        }
    }
}
