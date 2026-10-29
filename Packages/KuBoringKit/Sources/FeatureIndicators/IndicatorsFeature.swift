import SwiftUI
import KuBoringCore

/// Ключи подфункций «Индикаторов».
enum IndicatorsKeys {
    static let headphones = SettingKey<Bool>("feature.indicators.headphones", default: true)
    static let capture = SettingKey<Bool>("feature.indicators.capture", default: true)
    static let charging = SettingKey<Bool>("feature.indicators.charging", default: true)
    /// Нужен доступ к папке «Загрузки» — выключено по умолчанию.
    static let downloads = SettingKey<Bool>("feature.indicators.downloads", default: false)
}

/// Фоновая фича: живые индикаторы в закрытой шторке — наушники, камера/микрофон, загрузки, зарядка.
@MainActor
public final class IndicatorsFeature: NotchFeature {
    public let id = "indicators"
    public let title = "Индикаторы"
    public let symbol = "dot.radiowaves.left.and.right"
    public let summary = "Заряд AirPods при подключении, камера и микрофон, загрузки, анимация зарядки"
    public let kind: FeatureKind = .background
    public let enabledByDefault = true

    private var settings: SettingsStore?
    private var headphones: HeadphonesWatcher?
    private var capture: CaptureWatcher?
    private var downloads: DownloadsWatcher?
    private var charging: ChargingWatcher?

    public init() {}

    public func start(_ context: FeatureContext) {
        stop()
        settings = context.settings
        headphones = HeadphonesWatcher(activities: context.activities)
        capture = CaptureWatcher(activities: context.activities)
        downloads = DownloadsWatcher(activities: context.activities)
        charging = ChargingWatcher(activities: context.activities)
        apply()
    }

    public func stop() {
        headphones?.stop()
        capture?.stop()
        downloads?.stop()
        charging?.stop()
        headphones = nil
        capture = nil
        downloads = nil
        charging = nil
        settings = nil
    }

    /// Включить/выключить подфункции по настройкам.
    func apply() {
        guard let settings else { return }
        settings[IndicatorsKeys.headphones] ? headphones?.start() : headphones?.stop()
        settings[IndicatorsKeys.capture] ? capture?.start() : capture?.stop()
        settings[IndicatorsKeys.downloads] ? downloads?.start() : downloads?.stop()
        settings[IndicatorsKeys.charging] ? charging?.start() : charging?.stop()
    }

    public func makeTabView() -> AnyView? { nil }

    public func makeSettingsView() -> AnyView? {
        guard let settings else {
            return AnyView(Text("Включите «Индикаторы», чтобы настроить их.").foregroundStyle(.secondary))
        }
        return AnyView(IndicatorsSettingsView(settings: settings, onChange: { [weak self] in self?.apply() }))
    }
}

struct IndicatorsSettingsView: View {
    let settings: SettingsStore
    let onChange: () -> Void

    private func flag(_ key: SettingKey<Bool>) -> Binding<Bool> {
        Binding(get: { settings[key] }, set: { settings[key] = $0; onChange() })
    }

    var body: some View {
        Group {
            SettingsSection("Наушники") {
                SettingsToggle("Заряд при подключении",
                               hint: "Когда подключаются AirPods или другие Bluetooth-наушники, шторка покажет заряд левого, правого и кейса.",
                               isOn: flag(IndicatorsKeys.headphones))
            }
            SettingsSection("Конфиденциальность") {
                SettingsToggle("Камера и микрофон",
                               hint: "Зелёная камера или оранжевый микрофон в закрытой шторке, пока их использует любое приложение.",
                               isOn: flag(IndicatorsKeys.capture))
            }
            SettingsSection("Загрузки", footer: "При включении macOS один раз спросит доступ к папке «Загрузки».") {
                SettingsToggle("Прогресс загрузок",
                               hint: "Safari, Chrome, Firefox и другие браузеры: процент или размер скачанного в закрытой шторке.",
                               isOn: flag(IndicatorsKeys.downloads))
            }
            SettingsSection("Зарядка") {
                SettingsToggle("Анимация подключения зарядки",
                               hint: "Короткая анимация молнии с процентом заряда, когда подключаешь зарядку.",
                               isOn: flag(IndicatorsKeys.charging))
            }
            SettingsSection("Сброс") {
                SettingsResetButton {
                    settings.reset(prefix: "feature.indicators.")
                    onChange()
                }
            }
        }
    }
}
