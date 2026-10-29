import AppKit
import SwiftUI

/// Собственное окно настроек (сцена Settings не используется).
@MainActor
public final class SettingsWindowController {
    private let settings: SettingsStore
    private let registry: FeatureRegistry
    private var window: NSWindow?

    public init(settings: SettingsStore, registry: FeatureRegistry) {
        self.settings = settings
        self.registry = registry
    }

    /// Показать окно (создаётся при первом вызове) и вывести приложение вперёд.
    public func show() {
        if window == nil {
            let root = SettingsRootView(settings: settings, registry: registry)
            let controller = NSHostingController(rootView: root)
            let w = NSWindow(contentViewController: controller)
            w.title = "Настройки KuBoring"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 860, height: 600))
            w.contentMinSize = NSSize(width: 760, height: 480)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("KuBoringSettingsWindow")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
