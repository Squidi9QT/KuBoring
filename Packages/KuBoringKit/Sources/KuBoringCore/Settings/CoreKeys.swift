import Foundation

/// Геометрия шторки (редактируется в настройках, есть живое превью).
public struct NotchGeometry: Codable, Sendable, Equatable {
    public var openWidth: Double = 640
    public var openHeight: Double = 190
    public var closedWidthAuto: Bool = true
    public var closedWidth: Double = 185
    public var closedHeightAuto: Bool = true
    public var closedHeight: Double = 32
    public var cornerRadius: Double = 24
    public var hoverPaddingX: Double = 20
    public var hoverPaddingY: Double = 8
    public var openDelay: Double = 0.15
    public var closeDelay: Double = 0.3
    public var animationSpeed: Double = 1.0
    public var openOnHover: Bool = true

    public init() {}

    public static let `default` = NotchGeometry()
}

public enum CoreKeys {
    public static let geometry = SettingKey<NotchGeometry>("core.geometry", default: .default)
    public static let tabOrder = SettingKey<[String]>("core.tabOrder", default: [])
    public static let rememberLastTab = SettingKey<Bool>("core.rememberLastTab", default: true)
    public static let lastTab = SettingKey<String>("core.lastTab", default: "")
    public static let launchAtLogin = SettingKey<Bool>("core.launchAtLogin", default: false)
    public static let showOnAllScreens = SettingKey<Bool>("core.allScreens", default: false)
    public static let hideInFullscreen = SettingKey<Bool>("core.hideInFullscreen", default: false)
    public static let showBattery = SettingKey<Bool>("core.showBattery", default: true)
    /// Окно приветствия уже показано.
    public static let onboardingShown = SettingKey<Bool>("core.onboardingShown", default: false)
    /// «Не спать с закрытой крышкой» включил KuBoring (значит, при выходе его надо выключить).
    public static let lidAwakeByApp = SettingKey<Bool>("core.lidAwakeByApp", default: false)
}
