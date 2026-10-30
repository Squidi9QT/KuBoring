import AppKit
import Observation

@MainActor
public final class NotchWindowManager {
    private let settings: SettingsStore
    private let notch: NotchController
    private let activities: ActivityCenter
    private let registry: FeatureRegistry
    private let arbiter = NotchScreenArbiter()
    private let battery = BatteryMonitor()
    private let controls: QuickControls
    private let onOpenSettings: (() -> Void)?

    private var controllers: [NotchWindowController] = []
    private var screenObserver: NSObjectProtocol?
    private var started = false

    public init(
        settings: SettingsStore, notch: NotchController,
        activities: ActivityCenter, registry: FeatureRegistry,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.onOpenSettings = onOpenSettings
        self.settings = settings
        self.notch = notch
        self.activities = activities
        self.registry = registry
        let controls = QuickControls(settings: settings, activities: activities)
        self.controls = controls
        battery.onUpdate = { [weak controls] level, plugged in
            controls?.batteryChanged(level: level, pluggedIn: plugged)
        }
        battery.onBusyChange = { [weak notch] busy in notch?.hold("modal.power.schedule", busy) }
        controls.onBusyChange = { [weak notch] busy in notch?.hold("modal.power.lid", busy) }
    }

    public func start() {
        guard !started else { return }
        started = true
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        rebuild()
        trackSettings()
    }

    public func stop() {
        started = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        controllers.forEach { $0.tearDown() }
        controllers.removeAll()
        controls.invalidate()
    }

    public func rebuild() {
        controllers.forEach { $0.tearDown() }
        controllers.removeAll()

        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let targets = settings[CoreKeys.showOnAllScreens] ? screens : [primary]

        let primaryID = screenID(primary)
        if arbiter.activeID == nil || !targets.contains(where: { screenID($0) == arbiter.activeID }) {
            arbiter.activeID = primaryID
        }
        for screen in targets {
            let c = NotchWindowController(
                screen: screen, settings: settings, notch: notch,
                activities: activities, registry: registry, arbiter: arbiter,
                battery: battery, controls: controls,
                onOpenSettings: onOpenSettings)
            controllers.append(c)
            c.show()
        }
    }

    private func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func trackSettings() {
        guard started else { return }
        let allScreens = settings[CoreKeys.showOnAllScreens]
        withObservationTracking {
            _ = settings[CoreKeys.showOnAllScreens]
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.started else { return }
                if self.settings[CoreKeys.showOnAllScreens] != allScreens { self.rebuild() }
                self.trackSettings()
            }
        }
    }
}
