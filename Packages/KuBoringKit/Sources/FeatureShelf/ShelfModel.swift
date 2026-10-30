import Foundation
import AppKit
import QuickLookThumbnailing
import Observation
import KuBoringCore

enum ShelfKeys {
    static let items = SettingKey<[ShelfItem]>("data.shelf.items", default: [])
    static let maxCount = SettingKey<Int>("feature.shelf.maxCount", default: 20)
    static let remember = SettingKey<Bool>("feature.shelf.remember", default: true)
    static let clearOnQuit = SettingKey<Bool>("feature.shelf.clearOnQuit", default: false)
}

struct ShelfItem: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var bookmark: Data
    var name: String
    var addedAt: Date
}

@MainActor @Observable
final class ShelfModel {
    private(set) var items: [ShelfItem] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]

    @ObservationIgnored private var urls: [UUID: URL] = [:]
    @ObservationIgnored var settings: SettingsStore?
    @ObservationIgnored var notch: NotchController?
    @ObservationIgnored private var holdTask: Task<Void, Never>?

    init() {}

    // MARK: Загрузка и сохранение

    func load() {
        guard let settings else { return }
        items = []
        urls = [:]
        thumbnails = [:]
        guard settings[ShelfKeys.remember] else { persist(); return }
        var result: [ShelfItem] = []
        for var item in settings[ShelfKeys.items] {
            var stale = false
            guard let url = try? URL(
                    resolvingBookmarkData: item.bookmark, options: [.withoutUI],
                    relativeTo: nil, bookmarkDataIsStale: &stale),
                FileManager.default.fileExists(atPath: url.path)
            else { continue }
            if stale,
                let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                item.bookmark = fresh
            }
            item.name = url.lastPathComponent
            urls[item.id] = url
            result.append(item)
        }
        items = result
        persist()
    }

    func persist() {
        guard let settings else { return }
        settings[ShelfKeys.items] = settings[ShelfKeys.remember] ? items : []
    }

    // MARK: Изменения

    func add(_ newURLs: [URL]) {
        var idByPath: [String: UUID] = [:]
        for (id, url) in urls { idByPath[url.standardizedFileURL.path] = id }
        var batch: [ShelfItem] = []
        var batchPaths: Set<String> = []
        for url in newURLs where url.isFileURL {
            let path = url.standardizedFileURL.path
            if batchPaths.contains(path) { continue }
            if let id = idByPath[path], let existing = items.first(where: { $0.id == id }) {
                batch.append(existing)
                batchPaths.insert(path)
                continue
            }
            guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            else { continue }
            let item = ShelfItem(id: UUID(), bookmark: bookmark, name: url.lastPathComponent, addedAt: Date())
            urls[item.id] = url
            batch.append(item)
            batchPaths.insert(path)
        }
        guard !batch.isEmpty else { return }
        let moved = Set(batch.map(\.id))
        items.removeAll { moved.contains($0.id) }
        items.insert(contentsOf: batch, at: 0)
        trimToMax()
    }

    func trimToMax() {
        let maxCount = max(1, settings?[ShelfKeys.maxCount] ?? 20)
        while items.count > maxCount, let last = items.last {
            items.removeLast()
            urls[last.id] = nil
            thumbnails[last.id] = nil
        }
        persist()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        urls[item.id] = nil
        thumbnails[item.id] = nil
        persist()
    }

    func removeItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        for id in ids {
            urls[id] = nil
            thumbnails[id] = nil
        }
        persist()
    }

    func clear() {
        items = []
        urls = [:]
        thumbnails = [:]
        persist()
    }

    // MARK: Действия

    func url(for item: ShelfItem) -> URL? {
        guard let url = urls[item.id] else { return nil }
        if !FileManager.default.fileExists(atPath: url.path) {
            remove(item)
            return nil
        }
        return url
    }

    func open(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func airDrop(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        holdNotch()
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url])
    }

    func holdNotch() {
        holdTask?.cancel()
        notch?.hold("shelf.share", true)
        holdTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled { return }
            self?.notch?.hold("shelf.share", false)
        }
    }

    func releaseHold() {
        holdTask?.cancel()
        holdTask = nil
        notch?.hold("shelf.share", false)
    }

    // MARK: Быстрые действия

    private(set) var busy = false
    private(set) var message: String?
    @ObservationIgnored private var messageTask: Task<Void, Never>?

    enum Action { case compress, jpeg, zip }

    func perform(_ action: Action, on targets: [ShelfItem]) {
        let sources = targets.compactMap { url(for: $0) }
        guard !sources.isEmpty, !busy else { return }
        busy = true
        Task {
            let result: Result<[URL], Error> = await Task.detached {
                do {
                    switch action {
                    case .compress: return .success(try sources.map { try ShelfActions.compress($0) })
                    case .jpeg: return .success(try sources.map { try ShelfActions.convertToJPEG($0) })
                    case .zip: return .success([try ShelfActions.zip(sources)])
                    }
                } catch {
                    return .failure(error)
                }
            }.value
            busy = false
            switch result {
            case .success(let urls):
                add(urls)
                show(urls.count == 1 ? "Готово: \(urls[0].lastPathComponent)" : "Готово: \(urls.count) файла")
            case .failure(let error):
                show(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func rename(_ item: ShelfItem, to name: String) -> Bool {
        guard let old = url(for: item) else { return false }
        do {
            let new = try ShelfActions.rename(old, to: name)
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return true }
            if let bookmark = try? new.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                items[index].bookmark = bookmark
            }
            items[index].name = new.lastPathComponent
            urls[item.id] = new
            thumbnails[item.id] = nil
            persist()
            return true
        } catch {
            show(error.localizedDescription)
            return false
        }
    }

    func isImage(_ item: ShelfItem) -> Bool {
        guard let url = urls[item.id] else { return false }
        return ShelfActions.isImage(url)
    }

    private func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    // MARK: Миниатюры

    func loadThumbnail(for item: ShelfItem) async {
        guard thumbnails[item.id] == nil, let url = urls[item.id] else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 128, height: 128),
            scale: scale, representationTypes: .all)
        let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        guard urls[item.id] != nil else { return }
        if let rep {
            thumbnails[item.id] = NSImage(cgImage: rep.cgImage, size: .zero)
        } else {
            thumbnails[item.id] = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}
