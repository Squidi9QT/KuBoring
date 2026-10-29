import SwiftUI

public enum FeatureKind: Sendable { case tab, background }

@MainActor
public struct FeatureContext {
    public let settings: SettingsStore
    public let notch: NotchController
    public let activities: ActivityCenter

    public init(settings: SettingsStore, notch: NotchController, activities: ActivityCenter) {
        self.settings = settings
        self.notch = notch
        self.activities = activities
    }
}

@MainActor
public protocol NotchFeature: AnyObject {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    var summary: String { get }
    var kind: FeatureKind { get }
    var enabledByDefault: Bool { get }
    /// Если не nil — пока открыта вкладка, шторка принимает этот размер.
    var preferredOpenSize: CGSize? { get }
    /// true — вкладка сама принимает перетаскивание (веб-страница): шторка не перехватывает файлы.
    var acceptsDropsItself: Bool { get }
    /// true — пока вкладка выбрана, уход курсора не закрывает шторку (закрывается кликом вне неё).
    var staysOpenOnPointerExit: Bool { get }
    func start(_ context: FeatureContext)
    func stop()
    func makeTabView() -> AnyView?
    func makeSettingsView() -> AnyView?
}

public extension NotchFeature {
    var summary: String { "" }
    var enabledByDefault: Bool { true }
    var preferredOpenSize: CGSize? { nil }
    var acceptsDropsItself: Bool { false }
    var staysOpenOnPointerExit: Bool { acceptsDropsItself }
    func makeSettingsView() -> AnyView? { nil }
}
