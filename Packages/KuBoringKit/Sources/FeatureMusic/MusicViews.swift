import SwiftUI
import AppKit
import KuBoringCore

func musicFormatTime(_ seconds: Double) -> String {
    let t = Int(max(0, seconds.isFinite ? seconds : 0))
    let h = t / 3600, m = (t % 3600) / 60, s = t % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

// MARK: Вкладка

struct MusicTabView: View {
    let model: MusicModel

    var body: some View {
        Group {
            if let track = model.track {
                NowPlayingView(model: model, track: track)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(model.sourceHidden ? "Сейчас ничего не играет" : (model.unavailableReason ?? "Ничего не играет"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    if model.sourceHidden {
                        Text("Источник скрыт в настройках")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NowPlayingView: View {
    let model: MusicModel
    let track: MusicTrack

    private enum LayoutMode: Equatable { case compact, regular, tall }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let k = AdaptiveMetrics(size: geo.size).scale
            let mode: LayoutMode = h < 110 ? .compact : (h > w * 0.7 ? .tall : .regular)
            let hPad = adaptiveClamp(16 * k, 8, 32)
            let vPad: CGFloat = mode == .compact ? 4 : adaptiveClamp(10 * k, 6, 24)
            let availH = max(40, h - 2 * vPad)
            let coverBase: CGFloat = mode == .tall ? min(h * 0.4, w * 0.5) : min(h * 0.85, w * 0.35)
            let cover = adaptiveClamp(min(coverBase, availH), 48, 260)
            let side: CGFloat = mode == .compact ? adaptiveClamp(h * 0.3, 22, 32) : adaptiveClamp(26 * k, 22, 44)
            let play = adaptiveClamp(side * 1.35, 30, 60)
            let gap = adaptiveClamp(cover * 0.16, 10, 32)
            let layout = mode == .tall
                ? AnyLayout(VStackLayout(alignment: .center, spacing: adaptiveClamp(8 * k, 6, 16)))
                : AnyLayout(HStackLayout(alignment: .center, spacing: gap))

            layout {
                coverView(size: cover)
                info(mode: mode, k: k, side: side, play: play, h: h)
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .frame(width: w, height: h)
            .animation(.smooth(duration: 0.3), value: mode)
        }
    }

    // MARK: Правая / нижняя часть

    @ViewBuilder
    private func info(mode: LayoutMode, k: CGFloat, side: CGFloat, play: CGFloat, h: CGFloat) -> some View {
        switch mode {
        case .compact:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: adaptiveClamp(h * 0.14, 12, 15), weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: adaptiveClamp(h * 0.12, 11, 13)))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    controls(side: side, play: play, spacing: side * 0.5)
                }
                MusicSeekBar(model: model, track: track, barHeight: 3, showTimes: false)
            }
            .frame(maxWidth: .infinity)
        case .regular:
            VStack(alignment: .leading, spacing: adaptiveClamp(8 * k, 6, 18)) {
                topBlock(k: k, centered: false)
                MusicSeekBar(model: model, track: track,
                             barHeight: adaptiveClamp(5 * k, 4, 8),
                             fontSize: adaptiveClamp(10 * k, 9, 14))
                controls(side: side, play: play, spacing: side * 0.9)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        case .tall:
            VStack(alignment: .center, spacing: adaptiveClamp(8 * k, 6, 18)) {
                topBlock(k: k, centered: true)
                MusicSeekBar(model: model, track: track,
                             barHeight: adaptiveClamp(5 * k, 4, 8),
                             fontSize: adaptiveClamp(10 * k, 9, 14))
                controls(side: side, play: play, spacing: side * 0.9)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var lyricsAvailable: Bool { model.settings?[MusicKeys.lyricsEnabled] ?? true }
    private var lyricsShown: Bool { lyricsAvailable && (model.settings?[MusicKeys.lyricsShown] ?? false) }

    /// Название и исполнитель — или текст песни, если он включён кнопкой.
    @ViewBuilder
    private func topBlock(k: CGFloat, centered: Bool) -> some View {
        if lyricsShown {
            LyricsBlock(model: model, track: track, k: k, centered: centered)
                .transition(.opacity)
        } else {
            titleBlock(k: k, centered: centered)
                .transition(.opacity)
        }
    }

    private func titleBlock(k: CGFloat, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: adaptiveClamp(2 * k, 2, 5)) {
            Text(track.title)
                .font(.system(size: adaptiveClamp(16 * k, 13, 30), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: adaptiveClamp(13 * k, 11, 24)))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    // MARK: Обложка

    private func coverView(size: CGFloat) -> some View {
        let radius = adaptiveClamp(size * 0.13, 6, 24)
        let badge = adaptiveClamp(size * 0.22, 16, 32)
        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let art = model.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.white.opacity(0.1))
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: size * 0.1, x: 0, y: size * 0.05)

            if let icon = model.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: badge, height: badge)
                    .offset(x: badge * 0.25, y: badge * 0.25)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Кнопки

    private func controls(side: CGFloat, play: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Button { model.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: side * 0.5, weight: .semibold))
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
            }
            Button { model.togglePlayPause() } label: {
                Image(systemName: track.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: play * 0.55, weight: .semibold))
                    .frame(width: play, height: play)
                    .contentShape(Rectangle())
            }
            Button { model.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: side * 0.5, weight: .semibold))
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .overlay(alignment: .trailing) {
            if lyricsAvailable && spacing > side * 0.6 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.settings?[MusicKeys.lyricsShown] = !lyricsShown
                    }
                } label: {
                    Image(systemName: lyricsShown ? "quote.bubble.fill" : "quote.bubble")
                        .font(.system(size: side * 0.45, weight: .semibold))
                        .foregroundStyle(lyricsShown ? Color.white : Color.white.opacity(0.55))
                        .frame(width: side, height: side)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(lyricsShown ? "Показать название" : "Текст песни")
                // За пределами тройки кнопок, чтобы не сдвигать её центр.
                .offset(x: side + spacing)
            }
        }
    }
}

/// Прогресс-бар: позиция интерполируется по времени, перетаскивание = перемотка.
struct MusicSeekBar: View {
    let model: MusicModel
    let track: MusicTrack
    var barHeight: CGFloat = 5
    var showTimes = true
    var fontSize: CGFloat = 10
    @State private var dragFraction: Double?
    private var display: MusicDisplayState { model.display }

    /// Шаг обновления; ширина полоски между шагами доезжает линейной анимацией, без рывков.
    private static let tick: Double = 0.25

    var body: some View {
        // Один и тот же TimelineView всегда (вид не пересоздаётся на паузе — жест не срывается);
        // тикает только пока трек играет и экран виден.
        TimelineView(.animation(minimumInterval: Self.tick, paused: !(track.playing && display.visible))) { ctx in
            content(at: ctx.date)
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
            let pos = track.position(at: date)
            let frac = track.duration > 0 ? min(1, pos / track.duration) : 0
            let shown = dragFraction ?? frac
            // Плавно — только при обычном ходе трека; при перетаскивании и на паузе полоска стоит под пальцем.
            let smooth: Animation? = (dragFraction == nil && track.playing) ? .linear(duration: Self.tick) : nil
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let width = max(1, geo.size.width)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(track.duration > 0 ? 0.2 : 0.1))
                            .frame(height: dragFraction == nil ? barHeight : barHeight + 3)
                        Capsule().fill(.white)
                            .frame(width: width * shown, height: dragFraction == nil ? barHeight : barHeight + 3)
                            .animation(smooth, value: shown)
                    }
                    .frame(width: width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard track.duration > 0 else { return }
                                dragFraction = min(1, max(0, value.location.x / width))
                            }
                            .onEnded { value in
                                guard track.duration > 0 else { dragFraction = nil; return }
                                let f = min(1, max(0, value.location.x / width))
                                model.seek(to: f * track.duration)
                                dragFraction = nil
                            }
                    )
                }
                // Зона нажатия заметно выше самой полоски, чтобы в тонкую полоску было легко попасть.
                .frame(height: max(16, barHeight + 10))
                .animation(.easeOut(duration: 0.12), value: dragFraction == nil)

                if showTimes {
                    HStack {
                        // Без длительности (эфир, часть браузеров) показываем просто прошедшее время.
                        Text(musicFormatTime(track.duration > 0 ? shown * track.duration : pos))
                        Spacer()
                        Text(track.duration > 0 ? musicFormatTime(track.duration) : "--:--")
                    }
                    .font(.system(size: fontSize).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
    }
}

// MARK: Текст песни

/// Текущая строка крупно, следующая — бледнее. Строка меняется в такт треку.
struct LyricsBlock: View {
    let model: MusicModel
    let track: MusicTrack
    let k: CGFloat
    let centered: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !(track.playing && model.display.visible))) { ctx in
            content(position: track.position(at: ctx.date))
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .onAppear { model.loadLyricsIfNeeded() }
        .onChange(of: LyricsService.key(title: track.title, artist: track.artist)) { _, _ in
            model.loadLyricsIfNeeded()
        }
    }

    @ViewBuilder
    private func content(position: Double) -> some View {
        switch model.lyrics {
        case .idle, .loading:
            lines("Ищем текст…", track.title, dimFirst: true)
        case .notFound:
            lines("Текст не найден", "\(track.title) — \(track.artist)", dimFirst: true)
        case .instrumental:
            lines("♪ Инструментал", track.title, dimFirst: true)
        case .plain(let text):
            lines(text.first ?? "", text.dropFirst().first ?? "Текст без таймингов", dimFirst: false)
        case .synced(let all):
            let index = LyricsService.currentIndex(all, at: position)
            let current = index.map { all[$0].text } ?? ""
            let next = all[(index.map { $0 + 1 } ?? 0)...].first { !$0.text.isEmpty }?.text ?? ""
            lines(current.isEmpty ? "♪" : current, next, dimFirst: false)
                .id(index ?? -1)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
                .animation(.easeOut(duration: 0.3), value: index)
        }
    }

    private func lines(_ first: String, _ second: String, dimFirst: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: adaptiveClamp(2 * k, 2, 5)) {
            Text(first)
                .font(.system(size: adaptiveClamp(16 * k, 13, 30), weight: .semibold))
                .foregroundStyle(dimFirst ? Color.white.opacity(0.6) : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(second)
                .font(.system(size: adaptiveClamp(13 * k, 11, 24)))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .clipped()
    }
}

// MARK: Активность в закрытой шторке

struct MusicMiniCover: View {
    let model: MusicModel

    var body: some View {
        Group {
            if let art = model.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.white.opacity(0.15))
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Видимость экрана: пауза анимаций, когда экран спит или приложение полностью перекрыто.
@MainActor @Observable
final class MusicDisplayState {
    private(set) var screenAsleep = false
    private(set) var occluded = false
    var visible: Bool { !screenAsleep && !occluded }

    @ObservationIgnored nonisolated(unsafe) private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        tokens.append((ws, ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screenAsleep = true }
        }))
        tokens.append((ws, ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screenAsleep = false }
        }))
        tokens.append((nc, nc.addObserver(forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.occluded = !NSApp.occlusionState.contains(.visible)
            }
        }))
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }
}

/// Эквалайзер: у каждой полоски своя бесконечная анимация масштаба (без покадровой перерисовки).
struct MusicEqualizer: View {
    let model: MusicModel
    let settings: SettingsStore
    private var display: MusicDisplayState { model.display }

    var body: some View {
        let running = settings[MusicKeys.animateBars] && (model.track?.playing ?? false) && display.visible
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                MusicEqualizerBar(index: i, running: running)
            }
        }
        .frame(height: 18)
    }
}

private struct MusicEqualizerBar: View {
    let index: Int
    let running: Bool
    @State private var up = false
    @State private var duration = Double.random(in: 0.35...0.6)
    @State private var peak = Double.random(in: 0.7...1.0)

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 3, height: 18)
            .scaleEffect(x: 1, y: up ? peak : 0.25, anchor: .bottom)
            .animation(
                running
                    ? .easeInOut(duration: duration).repeatForever(autoreverses: true).delay(Double(index) * 0.07)
                    : .easeOut(duration: 0.2),
                value: up)
            .onAppear { up = running }
            .onChange(of: running) { _, now in up = now }
    }
}
