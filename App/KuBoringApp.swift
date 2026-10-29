import SwiftUI
import AppKit

@main
struct KuBoringApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // Своих окон нет: шторка и окно настроек создаются в Composition.
    // Пустая сцена Settings нужна только потому, что App требует хотя бы одну сцену (окно она не открывает).
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: Composition?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let composition = Composition()
        composition.start()
        self.composition = composition
    }

    func applicationWillTerminate(_ notification: Notification) {
        composition?.stop()
    }

    // Повторный запуск приложения из Finder открывает настройки.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        composition?.showSettings()
        return true
    }
}
