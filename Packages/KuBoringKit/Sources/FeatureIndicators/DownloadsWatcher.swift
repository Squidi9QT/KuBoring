import SwiftUI
import KuBoringCore

/// Состояние текущих загрузок браузеров.
struct DownloadsProgress: Equatable {
    var count: Int
    var bytes: Int64
    /// Известен общий размер хотя бы части загрузок (Safari) — тогда есть процент.
    var total: Int64?

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(bytes) / Double(total))
    }
}

/// Следит за папкой «Загрузки»: недокачанные файлы браузеров (.download, .crdownload, .part, .opdownload).
/// Событие папки будит проверку; опрос раз в секунду — только пока что-то качается.
@MainActor
final class DownloadsWatcher {
    private let activities: ActivityCenter
    private var source: DispatchSourceFileSystemObject?
    private var pollTask: Task<Void, Never>?
    private var lastNames: [String] = []

    private static let activityID = "indicators.downloads"
    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "opdownload"]

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    private var folder: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func start() {
        guard source == nil, let folder else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        check()
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTask?.cancel()
        pollTask = nil
        lastNames = []
        activities.remove(id: Self.activityID)
    }

    /// Есть недокачанные — запускаем опрос (если ещё не идёт).
    private func check() {
        guard source != nil, pollTask == nil else { return }
        guard let progress = scan(), progress.count > 0 else { return }
        post(progress)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if let p = self.scan(), p.count > 0 {
                    self.post(p)
                } else {
                    self.finished()
                    return
                }
            }
        }
    }

    private func finished() {
        pollTask = nil
        let name = lastNames.count == 1 ? lastNames[0] : nil
        lastNames = []
        activities.post(LiveActivity(
            id: Self.activityID,
            priority: 65,
            expiresAt: Date().addingTimeInterval(2.5),
            extraWidth: 40,
            leading: AnyView(
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            ),
            trailing: AnyView(
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .help(name ?? "Загрузки завершены")
            )
        ))
    }

    private func post(_ progress: DownloadsProgress) {
        activities.post(LiveActivity(
            id: Self.activityID,
            priority: 65,
            extraWidth: 52,
            leading: AnyView(DownloadRing(fraction: progress.fraction)),
            trailing: AnyView(DownloadLabel(progress: progress))
        ))
    }

    /// Недокачанные файлы и их прогресс.
    private func scan() -> DownloadsProgress? {
        guard let folder,
              let items = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey],
                  options: [.skipsHiddenFiles]) else { return nil }
        var progress = DownloadsProgress(count: 0, bytes: 0, total: nil)
        var names: [String] = []
        for url in items where Self.partialExtensions.contains(url.pathExtension.lowercased()) {
            progress.count += 1
            names.append(url.deletingPathExtension().lastPathComponent)
            if url.pathExtension.lowercased() == "download" {
                // Safari: пакет .download с Info.plist внутри.
                let plist = url.appendingPathComponent("Info.plist")
                if let dict = NSDictionary(contentsOf: plist) as? [String: Any] {
                    let done = (dict["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                    let total = (dict["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value ?? 0
                    progress.bytes += done
                    if total > 0 { progress.total = (progress.total ?? 0) + total }
                }
            } else {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                progress.bytes += Int64(size)
            }
        }
        lastNames = names
        return progress
    }
}

/// Кольцо прогресса (или вращающееся, если общий размер неизвестен).
struct DownloadRing: View {
    let fraction: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            }
            Image(systemName: "arrow.down")
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(Color.white)
        }
        .frame(width: 15, height: 15)
    }
}

struct DownloadLabel: View {
    let progress: DownloadsProgress

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
    }

    private var text: String {
        if let f = progress.fraction { return "\(Int((f * 100).rounded()))%" }
        return ByteCountFormatter.string(fromByteCount: progress.bytes, countStyle: .file)
    }
}
