import AppKit
import SwiftUI
import Observation

/// Панель без рамки: может принимать ввод (поля в вкладках), но не активирует приложение.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Клик по шторке делает её key (для ввода текста), не активируя чужие окна и само приложение.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}

/// Контейнер, принимающий перетаскивание файлов и передающий его в контроллер окна.
@MainActor
final class NotchDropView: NSView {
    weak var owner: NotchWindowController?

    private var registered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAcceptsDrags(true)
    }

    /// false — не быть приёмником (веб-страница вкладки сама принимает файлы).
    func setAcceptsDrags(_ on: Bool) {
        guard on != registered else { return }
        registered = on
        if on {
            // Файлы-«обещания» (Фото, Почта, превью скриншота, часть браузеров) приходят без fileURL.
            let promised = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
            registerForDraggedTypes([.fileURL] + promised)
        } else {
            unregisterDraggedTypes()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Перетаскивание начато в самом приложении (файл тянут с полки наружу) — это не приём файла.
    private func isOwnDrag(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingSource != nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NSLog("[KuDrag] draggingEntered, registered=\(registeredDraggedTypes)")
        guard !isOwnDrag(sender) else { return [] }
        guard let owner, owner.dragEntered() else { NSLog("[KuDrag] dragEntered -> false"); return [] }
        owner.dragMoved(to: topLeftPoint(sender.draggingLocation))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let owner, !isOwnDrag(sender) else { return [] }
        owner.dragMoved(to: topLeftPoint(sender.draggingLocation))
        return .copy
    }

    /// Точка из координат окна (начало снизу-слева) в координаты с началом сверху-слева (как SwiftUI .global).
    private func topLeftPoint(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x, y: bounds.height - p.y)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        owner?.clearDragLocation()
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        owner?.dragExited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !isOwnDrag(sender) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        NSLog("[KuDrag] performDragOperation")
        guard !isOwnDrag(sender) else { return false }
        let pasteboard = sender.draggingPasteboard
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        // Обещания читаем, только если обычных файлов нет: многие источники кладут и то и другое.
        let promises = objects.isEmpty
            ? (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
                as? [NSFilePromiseReceiver] ?? [])
            : []
        owner?.dropped(objects)
        if !promises.isEmpty { receive(promises) }
        return !objects.isEmpty || !promises.isEmpty
    }

    /// Сохраняет файлы-обещания в папку приложения и отдаёт их на полку, когда они записаны.
    private func receive(_ promises: [NSFilePromiseReceiver]) {
        guard let destination = Self.makePromiseDirectory() else { return }
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        for promise in promises {
            promise.receivePromisedFiles(atDestination: destination, options: [:],
                                         operationQueue: queue) { [weak self] url, error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.owner?.droppedPromised([url]) }
                }
            }
        }
    }

    /// ~/Library/Application Support/<приложение>/Dropped/<uuid> — своя папка на каждый drop, без конфликтов имён.
    private static func makePromiseDirectory() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let app = Bundle.main.bundleIdentifier ?? "KuBoring"
        let dir = support.appendingPathComponent(app, isDirectory: true)
            .appendingPathComponent("Dropped", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }
}

/// Окно шторки для одного экрана.
@MainActor
final class NotchWindowController {
    let screen: NSScreen
    let displayID: CGDirectDisplayID

    private let settings: SettingsStore
    private let notch: NotchController
    private let activities: ActivityCenter
    private let registry: FeatureRegistry
    private let arbiter: NotchScreenArbiter
    private let onOpenSettings: (() -> Void)?

    private let physicalNotch: CGSize
    private let hasNotch: Bool
    private let panel: NotchPanel
    private let dropView: NotchDropView
    private let hostingView: NSView

    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var inside = false
    private var dragActive = false
    /// Опрос курсора, пока зажата кнопка мыши: во время системного перетаскивания
    /// мониторы почти не получают событий, и окно иначе осталось бы «сквозным».
    private var pressPoll: Task<Void, Never>?
    private var pressDragCount = 0
    private var tornDown = false
    /// Нажатие снаружи открытой шторки: засчитывается кликом только на отпускании без перетаскивания.
    private var pendingOutsideClick: NSPoint?
    private var pendingMoved = false
    private var pendingPasteboardCount = 0
    private var stayOpenApplied = false
    private var handledFocusRequest = 0

    init(screen: NSScreen, settings: SettingsStore, notch: NotchController,
         activities: ActivityCenter, registry: FeatureRegistry, arbiter: NotchScreenArbiter,
         battery: BatteryMonitor, controls: QuickControls,
         onOpenSettings: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
        self.screen = screen
        self.displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        self.settings = settings
        self.notch = notch
        self.activities = activities
        self.registry = registry
        self.arbiter = arbiter
        self.physicalNotch = ScreenMetrics.notchSize(for: screen)
        self.hasNotch = ScreenMetrics.hasNotch(screen)

        panel = NotchPanel(contentRect: .zero,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true

        let container = NotchDropView(frame: .zero)
        dropView = container
        let root = NotchRootView(displayID: displayID, physicalNotch: physicalNotch, hasNotch: hasNotch,
                                 settings: settings, notch: notch, activities: activities,
                                 registry: registry, arbiter: arbiter,
                                 battery: battery, controls: controls,
                                 onOpenSettings: onOpenSettings)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        hostingView = hosting
        container.owner = self
        panel.contentView = container
        updateDropRegistration()
    }

    // MARK: Жизненный цикл

    func show() {
        updateFrame()
        updateDropRegistration()
        syncStayOpen()
        installMonitors()
        trackChanges()
        updateVisibility()
    }

    func tearDown() {
        tornDown = true
        // Снять удержание вкладки: новый контроллер выставит его заново, а старое не залипнет.
        if stayOpenApplied {
            stayOpenApplied = false
            notch.hold("tab.stayOpen", false)
        }
        pressPoll?.cancel()
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        for o in observers {
            NotificationCenter.default.removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observers.removeAll()
        panel.orderOut(nil)
    }

    // MARK: Размеры и зоны

    /// Кэш геометрии: обновляется при изменении настроек (trackChanges), а не на каждое движение мыши.
    private var geometryCache: NotchGeometry?
    private var geometry: NotchGeometry { geometryCache ?? settings[CoreKeys.geometry].clamped() }
    private var isActive: Bool { arbiter.activeID == displayID }

    /// Окно большое и прозрачное: вмещает самую большую шторку.
    private func panelSize() -> CGSize {
        let g = geometry
        var w = max(g.openWidth, 900)
        var h = max(g.openHeight, 600)
        for f in registry.all {
            if let s = f.preferredOpenSize {
                w = max(w, s.width)
                h = max(h, s.height)
            }
        }
        return CGSize(width: w + 120, height: h + 60)
    }

    private func updateFrame() {
        geometryCache = settings[CoreKeys.geometry].clamped()
        let size = panelSize()
        let f = screen.frame
        let frame = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private var expanded: Bool {
        isActive && (notch.state.phase == .open || notch.state.phase == .dragging)
    }

    /// Прямоугольник видимой формы шторки в координатах экрана (с запасом по бокам и сверху).
    private func shapeRect() -> NSRect {
        let g = geometry
        var size: CGSize
        var ear: Double
        if expanded {
            let preferred = notch.batteryPanelOpen ? nil : registry.resolvedTab(notch.state.selectedTab)?.preferredOpenSize
            size = NotchLayout.openSize(g, preferred: preferred)
            ear = NotchLayout.maxEar(g)
        } else {
            size = NotchLayout.closedSize(g, physical: physicalNotch,
                                          extraWidth: activities.current?.extraWidth ?? 0)
            ear = 6
            if isActive && notch.state.phase == .peeking { size.width += 8; size.height += 3 }
        }
        let w = size.width + 2 * ear + 4
        let f = screen.frame
        return NSRect(x: f.midX - w / 2, y: f.maxY - size.height - 2, width: w, height: size.height + 12)
    }

    /// Зона, в которой курсор считается «у шторки» (для событий входа/выхода).
    private func hoverZone(shape: NSRect? = nil) -> NSRect {
        if expanded { return shape ?? shapeRect() }
        let g = geometry
        var r = shape ?? shapeRect()
        r.origin.x -= g.hoverPaddingX
        r.size.width += 2 * g.hoverPaddingX
        r.origin.y -= g.hoverPaddingY
        r.size.height += g.hoverPaddingY
        return r
    }

    // MARK: Мышь

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type, inOwnWindow: false) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            let own = event.window === self?.panel
            MainActor.assumeIsolated { self?.handle(type, inOwnWindow: own) }
            return event
        }) { monitors.append(local) }
        // Жесты трекпадом над шторкой (только события своего окна).
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let consumed = MainActor.assumeIsolated { self.handleScroll(event) }
            return consumed ? nil : event
        }) { monitors.append(scroll) }
    }

    // MARK: Жесты

    private var gestureDX: CGFloat = 0
    private var gestureDY: CGFloat = 0
    private var gestureDone = false

    /// Двумя пальцами: влево/вправо по шапке — соседняя вкладка, вверх по шапке — закрыть,
    /// вниз по закрытой шторке — открыть. Прокрутка внутри вкладок не трогается.
    /// true — событие обработано и дальше не идёт.
    private func handleScroll(_ event: NSEvent) -> Bool {
        // Только трекпад (у колёсика мыши нет фаз) и только жест, а не инерция.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return false }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            gestureDX = 0
            gestureDY = 0
            gestureDone = false
        }
        guard !gestureDone, isActive || arbiter.activeID == nil else { return false }
        let p = NSEvent.mouseLocation
        // Направление пальцев (с учётом «естественной» прокрутки): +x — вправо, +y — вверх.
        let inverted = event.isDirectionInvertedFromDevice
        gestureDX += inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        gestureDY += inverted ? -event.scrollingDeltaY : event.scrollingDeltaY

        let phase = notch.state.phase
        if phase == .open {
            let headerBottom = screen.frame.maxY - (max(28, physicalNotch.height) + 8)
            guard p.y >= headerBottom, shapeRect().contains(p) else { return false }
            if abs(gestureDX) > 50, abs(gestureDX) > abs(gestureDY) * 1.5 {
                gestureDone = true
                switchTab(by: gestureDX < 0 ? 1 : -1)
                return true
            }
            if gestureDY > 40, gestureDY > abs(gestureDX) * 1.5 {
                gestureDone = true
                notch.send(.requestClose)
                return true
            }
            return true   // над шапкой прокручивать нечего — не отдаём дальше
        }
        if phase == .closed || phase == .peeking {
            guard shapeRect().contains(p) else { return false }
            if -gestureDY > 30, abs(gestureDY) > abs(gestureDX) {
                gestureDone = true
                notch.send(.clicked)
            }
            return true
        }
        return false
    }

    private func switchTab(by step: Int) {
        let tabs = registry.enabledTabs
        guard tabs.count > 1 else { return }
        let current = tabs.firstIndex { $0.id == registry.resolvedTab(notch.state.selectedTab)?.id } ?? 0
        let next = (current + step + tabs.count) % tabs.count
        notch.send(.selectTab(tabs[next].id))
    }

    private func handle(_ type: NSEvent.EventType, inOwnWindow: Bool) {
        guard !tornDown else { return }
        let p = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown:
            startPressPolling()
            // Клик вне открытой шторки закрывает её (даже при holdOpen) — но решаем на отпускании.
            if isActive, notch.state.phase == .open, !inOwnWindow, !shapeRect().contains(p) {
                pendingOutsideClick = p
                pendingMoved = false
                pendingPasteboardCount = NSPasteboard(name: .drag).changeCount
            } else {
                pendingOutsideClick = nil
            }
            updatePointer(p)
        case .leftMouseDragged:
            dragActive = true
            if let start = pendingOutsideClick, hypot(p.x - start.x, p.y - start.y) > 4 {
                pendingMoved = true
            }
            updatePointer(p)
        case .leftMouseUp:
            dragActive = false
            if pendingOutsideClick != nil {
                let dragged = pendingMoved
                    || NSPasteboard(name: .drag).changeCount != pendingPasteboardCount
                pendingOutsideClick = nil
                // Если снаружи начали перетаскивание (файл из Finder) — шторку не закрываем.
                // Причина удержания «modal.*» — открыто системное окно (пароль администратора):
                // клик по нему не должен закрывать шторку.
                let modal = notch.state.holdOpen.contains { $0.hasPrefix("modal.") }
                if !dragged, !modal, isActive, notch.state.phase == .open {
                    notch.send(.clickedOutside)
                }
            }
            updatePointer(p)
        default:
            updatePointer(p)
        }
    }

    private func updatePointer(_ p: NSPoint) {
        guard panel.isVisible else { return }
        // Ранний выход: шторка закрыта, курсор далеко от неё и не был внутри — ничего считать не нужно.
        if !inside, !dragActive, notch.state.phase == .closed {
            let f = screen.frame
            if p.y < f.maxY - 150 || p.x < f.minX - 300 || p.x > f.maxX + 300 { return }
        }
        let shape = shapeRect()
        let zone = hoverZone(shape: shape)
        let nowInside = zone.contains(p)
        refreshMouseIgnoring(p, shape: shape, zone: zone)
        guard nowInside != inside else { return }
        inside = nowInside
        if nowInside {
            if !isActive {
                // Перехватить шторку можно только пока она закрыта.
                guard notch.state.phase == .closed else { return }
                arbiter.activeID = displayID
            }
            notch.send(.pointerEntered)
        } else if isActive {
            notch.send(.pointerExited)
        }
    }

    /// Окно ловит мышь только над самой формой (или в зоне наведения во время перетаскивания файла).
    private func refreshMouseIgnoring(_ p: NSPoint, shape: NSRect? = nil, zone: NSRect? = nil) {
        let accept: Bool
        let shapeR = shape ?? shapeRect()
        if expanded {
            accept = shapeR.contains(p)
        } else {
            accept = shapeR.contains(p) || (dragActive && (zone ?? hoverZone(shape: shapeR)).contains(p))
        }
        if panel.ignoresMouseEvents == accept {
            panel.ignoresMouseEvents = !accept
            NSLog("[KuDrag] acceptMouse=\(accept) expanded=\(expanded) dragActive=\(dragActive) phase=\(notch.state.phase)")
        }
    }

    private func startPressPolling() {
        pressPoll?.cancel()
        pressDragCount = NSPasteboard(name: .drag).changeCount
        pressPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !self.tornDown else { return }
                let p = NSEvent.mouseLocation
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.dragActive = false
                    self.updatePointer(p)
                    return
                }
                // Finder пишет в drag-буфер в момент начала перетаскивания.
                if NSPasteboard(name: .drag).changeCount != self.pressDragCount {
                    if !self.dragActive { NSLog("[KuDrag] drag detected via pasteboard") }
                    self.dragActive = true
                }
                self.refreshMouseIgnoring(p)
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    // MARK: Перетаскивание файлов

    /// Открытая шторка с вкладкой, которая сама принимает файлы (ИИ): наша вью не перехватывает drag,
    /// события доходят до WKWebView. Закрытая шторка и остальные вкладки — принимаем сами.
    private func updateDropRegistration() {
        let selfAccepting = notch.state.phase == .open && selectedTabAcceptsDropsItself
        if dropView.registeredDraggedTypes.isEmpty == !selfAccepting {
            NSLog("[KuDrag] registration -> \(!selfAccepting) tab=\(notch.state.selectedTab ?? "nil")")
        }
        dropView.setAcceptsDrags(!selfAccepting)
        // NSHostingView тоже может быть зарегистрирован как приёмник — тогда он перехватил бы файл.
        if selfAccepting, !hostingView.registeredDraggedTypes.isEmpty {
            hostingView.unregisterDraggedTypes()
        }
    }

    private var selectedTabAcceptsDropsItself: Bool {
        registry.resolvedTab(notch.state.selectedTab)?.acceptsDropsItself ?? false
    }

    /// Пока открыта вкладка со staysOpenOnPointerExit (ИИ), уход курсора шторку не закрывает.
    private func syncStayOpen() {
        let want = notch.state.phase == .open
            && (registry.resolvedTab(notch.state.selectedTab)?.staysOpenOnPointerExit ?? false)
        guard want != stayOpenApplied else { return }
        stayOpenApplied = want
        notch.hold("tab.stayOpen", want)
        // Удержание снято, а курсор уже вне шторки — закрыться как обычно.
        if !want, isActive, notch.state.phase == .open, !hoverZone().contains(NSEvent.mouseLocation) {
            inside = false
            notch.send(.pointerExited)
        }
    }

    /// Курсор с файлом: точка в координатах окна с началом сверху-слева (подсветку считают вьюхи).
    func dragMoved(to topLeftPoint: CGPoint) {
        guard isActive else { return }
        if notch.dragLocation != topLeftPoint { notch.dragLocation = topLeftPoint }
    }

    func clearDragLocation() {
        if notch.dragLocation != nil { notch.dragLocation = nil }
    }

    private func resetDragFlags() {
        if notch.dragInside { notch.dragInside = false }
        if notch.dropHover { notch.dropHover = false }
        if notch.dragLocation != nil { notch.dragLocation = nil }
    }

    func dragEntered() -> Bool {
        if !isActive {
            guard notch.state.phase == .closed else { return false }
            arbiter.activeID = displayID
        }
        inside = true
        let phase = notch.state.phase
        // Страховка: только что закрылась вкладка, сама принимающая файлы (ИИ) — вернём её, а не полку.
        if phase == .closed || phase == .peeking, selectedTabAcceptsDropsItself,
           let closedAt = notch.lastClosedAt, Date().timeIntervalSince(closedAt) < 2 {
            notch.send(.requestOpen(tab: nil))
            updateDropRegistration()
            syncStayOpen()
            return false
        }
        notch.dragInside = true
        notch.send(.dragEntered)
        // Открытая шторка на другой вкладке: сразу показать вкладку-приёмник (полку).
        // Открытая вкладка, сама принимающая файлы (ИИ), не переключается.
        if notch.state.phase == .open, !selectedTabAcceptsDropsItself,
           let dropID = notch.dropTabID,
           registry.resolvedTab(notch.state.selectedTab)?.id != dropID {
            notch.send(.selectTab(dropID))
        }
        updateDropRegistration()
        return true
    }

    func dragExited() {
        resetDragFlags()
        guard isActive else { return }
        notch.send(.dragExited)
    }

    func dropped(_ urls: [URL]) {
        resetDragFlags()
        guard isActive else { return }
        dragActive = false
        // Открыта вкладка, сама принимающая файлы: это не наш drop.
        if notch.state.phase == .open, selectedTabAcceptsDropsItself { return }
        notch.send(.dropped)
        if !urls.isEmpty { notch.dropHandler?.handleDrop(urls) }
    }

    /// Файлы-обещания дописались уже после drop — просто кладём их в приёмник.
    func droppedPromised(_ urls: [URL]) {
        guard !tornDown, !urls.isEmpty else { return }
        notch.dropHandler?.handleDrop(urls)
    }

    // MARK: Наблюдение за состоянием

    /// Перерисовывает окно при изменении геометрии/состояния; события при этом не шлёт.
    private func trackChanges() {
        guard !tornDown else { return }
        withObservationTracking {
            _ = settings[CoreKeys.geometry]
            _ = panelSize()
            _ = notch.state
            _ = activities.current?.extraWidth
            _ = arbiter.activeID
            _ = settings[CoreKeys.hideInFullscreen]
            _ = registry.resolvedTab(notch.state.selectedTab)?.acceptsDropsItself
            _ = notch.keyboardFocusRequest
            _ = notch.batteryPanelOpen
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.tornDown else { return }
                self.applyKeyboardFocusRequest()
                self.updateFrame()
                self.updateDropRegistration()
                self.syncStayOpen()
                self.refreshMouseIgnoring(NSEvent.mouseLocation)
                self.updateVisibility()
                self.trackChanges()
            }
        }
    }

    /// Новый запрос фокуса — делаем панель key (без активации приложения: панель non-activating).
    private func applyKeyboardFocusRequest() {
        guard notch.keyboardFocusRequest != handledFocusRequest else { return }
        handledFocusRequest = notch.keyboardFocusRequest
        guard arbiter.activeID == nil || isActive else { return }
        if !panel.isVisible { panel.orderFrontRegardless() }
        panel.makeKey()
    }

    // MARK: Видимость (полноэкранные приложения)

    private func updateVisibility() {
        guard !tornDown else { return }
        installVisibilityObserversIfNeeded()
        let hide = settings[CoreKeys.hideInFullscreen] && fullscreenAppCoversScreen()
        if hide {
            if panel.isVisible { panel.orderOut(nil) }
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func installVisibilityObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.activeSpaceDidChangeNotification,
                                          NSWorkspace.didActivateApplicationNotification]
        for name in names {
            let token = ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
            observers.append(token)
        }
    }

    /// Есть ли чужое окно на весь экран (полноэкранный режим) — приблизительная проверка.
    private func fullscreenAppCoversScreen() -> Bool {
        let bounds = CGDisplayBounds(displayID)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            if rect == bounds { return true }
        }
        return false
    }
}
