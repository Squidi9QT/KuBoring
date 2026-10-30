import AppKit

@MainActor
public final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let onOpenSettings: () -> Void
    private let onShowWelcome: (() -> Void)?

    public init(onOpenSettings: @escaping () -> Void, onShowWelcome: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
        self.onShowWelcome = onShowWelcome
        super.init()
    }

    public func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "KuBoring")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "KuBoring"
        }
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        if onShowWelcome != nil {
            let welcomeItem = NSMenuItem(title: "Что умеет KuBoring", action: #selector(showWelcome), keyEquivalent: "")
            welcomeItem.target = self
            menu.addItem(welcomeItem)
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Выйти из KuBoring", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    public func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func showWelcome() { onShowWelcome?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
