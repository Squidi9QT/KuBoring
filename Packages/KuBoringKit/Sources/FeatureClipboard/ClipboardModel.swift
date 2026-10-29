import AppKit
import Observation
import KuBoringCore

struct ClipItem: Identifiable, Equatable, Codable {
    var id = UUID()
    /// Для картинки — пустая строка.
    var text: String
    var pinned = false
    /// PNG/TIFF скопированной картинки. Картинки живут только в памяти (на диск не пишутся).
    var image: Data?

    var isImage: Bool { image != nil }

    init(text: String, pinned: Bool = false, image: Data? = nil) {
        self.text = text
        self.pinned = pinned
        self.image = image
    }

    private enum CodingKeys: String, CodingKey { case id, text, pinned }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(pinned, forKey: .pinned)
    }
}

enum ClipboardKeys {
    static let limit = SettingKey<Int>("feature.clipboard.limit", default: 50)
    static let persist = SettingKey<Bool>("feature.clipboard.persist", default: false)
    static let skipSecrets = SettingKey<Bool>("feature.clipboard.skipSecrets", default: true)
    /// ⌘⇧V открывает историю (по умолчанию выключено — как раньше).
    static let hotkey = SettingKey<Bool>("feature.clipboard.hotkey", default: false)
    /// После выбора сразу вставлять (⌘V в прежнее приложение; нужен «Универсальный доступ»).
    static let autoPaste = SettingKey<Bool>("feature.clipboard.autoPaste", default: true)
    static let images = SettingKey<Bool>("feature.clipboard.images", default: true)
}

/// История буфера обмена: текст и картинки, закреплённые записи, вызов горячей клавишей.
/// Опрос changeCount в Task-цикле.
@MainActor @Observable
final class ClipboardModel {
    private(set) var items: [ClipItem] = []
    private(set) var justCopiedID: UUID?

    /// Открыто горячей клавишей: стрелки выбирают, Enter вставляет, Esc закрывает.
    private(set) var keyboardMode = false
    var selectedID: UUID?
    /// Поиск — в модели, чтобы клавиатурный режим видел тот же отфильтрованный список.
    var query = ""

    private(set) var settings: SettingsStore?
    @ObservationIgnored private(set) var notch: NotchController?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var pasteTask: Task<Void, Never>?
    @ObservationIgnored private var lastChange = 0
    @ObservationIgnored private var lastPersist = false
    @ObservationIgnored private var activateObserver: NSObjectProtocol?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var thumbnailCache: [UUID: NSImage] = [:]
    // Кэш настроек: читаем раз в несколько секунд, а не на каждом тике
    @ObservationIgnored private var cachedLimit = 50
    @ObservationIgnored private var cachedSkipSecrets = true
    @ObservationIgnored private var cachedImages = true
    @ObservationIgnored private var settingsRefreshedAt = Date.distantPast

    private static let storageKey = "data.clipboard.history"
    /// Картинок в памяти не больше этого (они тяжёлые).
    private static let maxImages = 15
    /// Картинки крупнее не сохраняем.
    private static let maxImageBytes = 20 * 1024 * 1024

    /// Метки менеджеров паролей (nspasteboard.org).
    private static let secretTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    /// Из этих приложений ничего не сохраняем.
    private static let ignoredApps: Set<String> = [
        "com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password",
        "com.agilebits.onepassword7", "com.bitwarden.desktop",
    ]

    /// Закреплённые сверху, затем остальные по свежести; с учётом поиска.
    var visibleItems: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? items : items.filter { $0.text.localizedCaseInsensitiveContains(q) }
        return list.filter(\.pinned) + list.filter { !$0.pinned }
    }

    func start(_ context: FeatureContext) {
        stop()
        settings = context.settings
        notch = context.notch
        lastChange = NSPasteboard.general.changeCount
        lastPersist = context.settings[ClipboardKeys.persist]
        if lastPersist { load() }
        refreshSettings(force: true)
        applyHotKey()
        // Мгновенная проверка при смене активного приложения
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: self.pollInterval())
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        flashTask?.cancel()
        flashTask = nil
        pasteTask?.cancel()
        pasteTask = nil
        if let activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateObserver)
        }
        activateObserver = nil
        hotKey?.invalidate()
        hotKey = nil
        endKeyboardMode()
    }

    /// Включить/выключить ⌘⇧V по настройке.
    func applyHotKey() {
        let want = settings?[ClipboardKeys.hotkey] ?? false
        if want, hotKey == nil {
            hotKey = GlobalHotKey { [weak self] in self?.hotKeyPressed() }
        } else if !want, let hotKey {
            hotKey.invalidate()
            self.hotKey = nil
        }
    }

    /// 0.5 с, пока пользователь активен; 2.5 с, если нет ввода больше минуты.
    private func pollInterval() -> Duration {
        guard let anyEvent = CGEventType(rawValue: UInt32.max) else { return .milliseconds(500) }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
        return idle < 60 ? .milliseconds(500) : .milliseconds(2500)
    }

    private func refreshSettings(force: Bool = false) {
        guard let settings else { return }
        if !force, Date().timeIntervalSince(settingsRefreshedAt) < 3 { return }
        settingsRefreshedAt = Date()
        cachedLimit = settings[ClipboardKeys.limit]
        cachedSkipSecrets = settings[ClipboardKeys.skipSecrets]
        cachedImages = settings[ClipboardKeys.images]
        if !cachedImages, items.contains(where: \.isImage) {
            items.removeAll(where: \.isImage)
        }
        let persist = settings[ClipboardKeys.persist]
        if persist != lastPersist {
            lastPersist = persist
            save()
        }
        trim()
    }

    /// Лимит касается только незакреплённых записей.
    private func trim() {
        var unpinned = 0, images = 0
        var removed = false
        items.removeAll { item in
            if item.isImage {
                images += 1
                if images > Self.maxImages && !item.pinned { removed = true; return true }
            }
            guard !item.pinned else { return false }
            unpinned += 1
            if unpinned > cachedLimit { removed = true; return true }
            return false
        }
        if removed {
            let ids = Set(items.map(\.id))
            thumbnailCache = thumbnailCache.filter { ids.contains($0.key) }
            save()
        }
    }

    private func tick() {
        guard settings != nil else { return }
        refreshSettings()

        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        refreshSettings(force: true)

        let front = NSWorkspace.shared.frontmostApplication
        let types = pb.types ?? []
        if cachedSkipSecrets {
            if types.contains(where: { Self.secretTypes.contains($0) }) { return }
            if let id = front?.bundleIdentifier, Self.ignoredApps.contains(id) { return }
        }

        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(ClipItem(text: text)) { $0.text == text && !$0.isImage }
        } else if cachedImages, !types.contains(.fileURL),
                  let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
                  data.count <= Self.maxImageBytes {
            insert(ClipItem(text: "", image: data)) { $0.image == data }
        }
    }

    /// Новая запись наверх; такая же старая — убирается (закрепление сохраняется).
    private func insert(_ item: ClipItem, sameAs: (ClipItem) -> Bool) {
        var new = item
        if let old = items.first(where: sameAs) {
            if items.first?.id == old.id { return }
            new.pinned = old.pinned
            items.removeAll { $0.id == old.id }
            thumbnailCache[old.id] = nil
        }
        items.insert(new, at: 0)
        trim()
        save()
    }

    /// Скопировать запись снова: без нового добавления, запись поднимается наверх.
    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = item.image {
            if let image = NSImage(data: data) {
                pb.writeObjects([image])
            } else {
                pb.setData(data, forType: .tiff)
            }
        } else {
            pb.setString(item.text, forType: .string)
        }
        lastChange = pb.changeCount

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.insert(items.remove(at: index), at: 0)
        }
        save()

        justCopiedID = item.id
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.justCopiedID = nil
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        save()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        thumbnailCache[item.id] = nil
        save()
    }

    /// Очищает историю; закреплённые остаются.
    func clear() {
        items.removeAll { !$0.pinned }
        let ids = Set(items.map(\.id))
        thumbnailCache = thumbnailCache.filter { ids.contains($0.key) }
        save()
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let data = item.image else { return nil }
        if let cached = thumbnailCache[item.id] { return cached }
        guard let image = NSImage(data: data) else { return nil }
        thumbnailCache[item.id] = image
        return image
    }

    // MARK: - Горячая клавиша и клавиатура

    private func hotKeyPressed() {
        guard let notch else { return }
        if keyboardMode {
            // Повторное нажатие — закрыть.
            cancelKeyboard()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
        query = ""
        selectedID = visibleItems.first?.id
        keyboardMode = true
        notch.hold("clipboard.keyboard", true)
        notch.send(.requestOpen(tab: "clipboard"))
        notch.requestKeyboardFocus()
        installKeyMonitor()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode)
            let handled = MainActor.assumeIsolated { self?.handleKey(code) ?? false }
            return handled ? nil : event
        }
    }

    /// Стрелки, Enter, Esc; остальное уходит в поле поиска.
    private func handleKey(_ code: Int) -> Bool {
        guard keyboardMode else { return false }
        let list = visibleItems
        switch code {
        case 125, 126: // вниз, вверх
            guard !list.isEmpty else { return true }
            let current = list.firstIndex { $0.id == selectedID } ?? -1
            let next = code == 125 ? min(list.count - 1, current + 1) : max(0, current - 1)
            selectedID = list[next].id
            return true
        case 36, 76: // Return, Enter
            if let item = list.first(where: { $0.id == selectedID }) ?? list.first {
                choose(item)
            }
            return true
        case 53: // Esc
            cancelKeyboard()
            return true
        default:
            return false
        }
    }

    /// Выбрать запись: в буфер, закрыть шторку, вернуть фокус прежнему приложению и вставить.
    func choose(_ item: ClipItem) {
        copy(item)
        let app = previousApp
        let paste = keyboardMode && (settings?[ClipboardKeys.autoPaste] ?? true) && AXIsProcessTrusted()
        finishKeyboard()
        app?.activate()
        guard paste else { return }
        pasteTask?.cancel()
        pasteTask = Task {
            // Дать прежнему окну снова стать активным.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            Self.postPaste()
        }
    }

    func cancelKeyboard() {
        let app = previousApp
        finishKeyboard()
        app?.activate()
    }

    private func finishKeyboard() {
        endKeyboardMode()
        notch?.send(.requestClose)
    }

    private func endKeyboardMode() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if keyboardMode { notch?.hold("clipboard.keyboard", false) }
        keyboardMode = false
        previousApp = nil
        query = ""
    }

    /// Шторку закрыли (уход курсора, клик снаружи) во время клавиатурного режима.
    func notchClosed() {
        if keyboardMode { endKeyboardMode() }
    }

    /// ⌘V в активное приложение.
    private static func postPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Запросить «Универсальный доступ» (системное окно), если ещё не выдан.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: - Хранение между запусками

    /// На диск — только текст (картинки тяжёлые и могут быть приватными).
    private func save() {
        let defaults = UserDefaults.standard
        guard lastPersist else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(items.filter { !$0.isImage }) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = saved
    }
}
