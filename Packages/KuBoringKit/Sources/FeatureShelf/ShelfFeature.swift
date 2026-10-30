import SwiftUI
import AppKit
import KuBoringCore

@MainActor
public final class ShelfFeature: NotchFeature, NotchDropHandler {
    public let id = "shelf"
    public let title = "Полка"
    public let symbol = "tray"
    public let summary = "Временное хранилище файлов: перетащи в шторку и забери позже"
    public var kind: FeatureKind { .tab }
    public var enabledByDefault: Bool { true }

    private let model = ShelfModel()
    private var context: FeatureContext?
    private var quitObserver: NSObjectProtocol?

    public init() {}

    public func start(_ context: FeatureContext) {
        self.context = context
        model.settings = context.settings
        model.notch = context.notch
        model.load()
        context.notch.dropHandler = self
        context.notch.dropTabID = "shelf"
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let settings = self.model.settings else { return }
                if settings[ShelfKeys.clearOnQuit] { self.model.clear() }
            }
        }
    }

    public func stop() {
        if let obs = quitObserver {
            NotificationCenter.default.removeObserver(obs)
            quitObserver = nil
        }
        model.releaseHold()
        if let notch = context?.notch {
            if notch.dropHandler === self { notch.dropHandler = nil }
            if notch.dropTabID == "shelf" { notch.dropTabID = nil }
        }
        context = nil
    }

    public func handleDrop(_ urls: [URL]) {
        model.add(urls)
    }

    public func makeTabView() -> AnyView? {
        AnyView(ShelfTabView(model: model))
    }

    public func makeSettingsView() -> AnyView? {
        let settings = context?.settings ?? SettingsStore()
        return AnyView(ShelfSettingsView(settings: settings, model: model))
    }
}
