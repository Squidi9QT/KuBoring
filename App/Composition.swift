import AppKit
import KuBoringCore
import FeatureMusic
import FeatureShelf
import FeatureClipboard
import FeatureTimer
import FeatureAI
import FeatureScreenText
import FeatureSystem
import FeatureCalendar
import FeatureIndicators

/// Точка сборки: создаёт ядро и регистрирует фичи.
@MainActor
final class Composition {
    let settings: SettingsStore
    let notch: NotchController
    let activities: ActivityCenter
    let registry: FeatureRegistry
    let windows: NotchWindowManager
    let settingsWindow: SettingsWindowController
    let statusItem: StatusItemController
    let onboarding: OnboardingWindowController

    init() {
        let settings = SettingsStore()
        let notch = NotchController(settings: settings)
        let activities = ActivityCenter()
        let context = FeatureContext(settings: settings, notch: notch, activities: activities)
        let registry = FeatureRegistry(context: context)

        // Порядок регистрации = порядок вкладок по умолчанию.
        registry.register(MusicFeature(
            adapterScriptURL: Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            frameworkURL: Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")))
        registry.register(ShelfFeature())
        registry.register(ClipboardFeature())
        registry.register(TimerFeature())
        registry.register(AIFeature())
        registry.register(ScreenTextFeature())
        registry.register(SystemFeature())
        registry.register(CalendarFeature())
        registry.register(IndicatorsFeature())

        let settingsWindow = SettingsWindowController(settings: settings, registry: registry)

        self.settings = settings
        self.notch = notch
        self.activities = activities
        self.registry = registry
        self.settingsWindow = settingsWindow
        self.windows = NotchWindowManager(settings: settings, notch: notch,
                                          activities: activities, registry: registry,
                                          onOpenSettings: { [settingsWindow] in settingsWindow.show() })
        let onboarding = OnboardingWindowController(settings: settings, onOpenSettings: { [settingsWindow] in
            settingsWindow.show()
        })
        self.onboarding = onboarding
        self.statusItem = StatusItemController(onOpenSettings: { [settingsWindow] in
            settingsWindow.show()
        }, onShowWelcome: { [onboarding] in
            onboarding.show()
        })
    }

    func start() {
        registry.startEnabled()
        windows.start()
        statusItem.install()
        onboarding.showIfNeeded()
    }

    func stop() {
        windows.stop()
        statusItem.remove()
    }

    func showSettings() {
        settingsWindow.show()
    }
}
