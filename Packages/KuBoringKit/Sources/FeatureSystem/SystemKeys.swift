import KuBoringCore

/// Ключи настроек подфункций. Все по умолчанию выключены.
enum SystemKeys {
    static let hudVolume = SettingKey<Bool>("feature.system.hudVolume", default: false)
    static let hudBrightness = SettingKey<Bool>("feature.system.hudBrightness", default: false)
    static let battery = SettingKey<Bool>("feature.system.battery", default: false)
    static let batteryLow = SettingKey<Bool>("feature.system.batteryLow", default: false)
    static let keepAwake = SettingKey<Bool>("feature.system.keepAwake", default: false)
    static let keepAwakeBadge = SettingKey<Bool>("feature.system.keepAwakeBadge", default: false)
}
