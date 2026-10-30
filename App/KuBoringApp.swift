import SwiftUI
import AppKit

@main
struct KuBoringApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        composition?.showSettings()
        return true
    }
}
