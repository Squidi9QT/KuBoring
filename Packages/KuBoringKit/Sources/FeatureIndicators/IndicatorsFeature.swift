import SwiftUI
import KuBoringCore

/// Ключи подфункций «Индикаторов».
enum IndicatorsKeys {
    static let charging = SettingKey<Bool>("feature.indicators.charging", default: true)
    /// Нужен доступ к папке «Загрузки» — выключено по умолчанию.
    static let downloads = SettingKey<Bool>("feature.indicators.downloads", default: false)
}

/// Фоновая фича: живые индикаторы в закрытой шторке — загрузки и зарядка.
@MainActor
public final class IndicatorsFeature: NotchFeature {
    public let id = "indicators"
    public let title = "Индикаторы"
    public let symbol = "dot.radiowaves.left.and.right"
    public let summary = "Прогресс загрузок и анимация подключения зарядки"
    public let kind: FeatureKind = .background
    public let enabledByDefault = true

    private var settings: SettingsStore?
    private var downloads: DownloadsWatcher?
    private var charging: ChargingWatcher?

    public init() {}

    public func start(_ context: FeatureContext) {
        stop()
        settings = context.settings
        downloads = DownloadsWatcher(activities: context.activities)
        charging = ChargingWatcher(activities: context.activities)
        apply()
    }

    public func stop() {
        downloads?.stop()
        charging?.stop()
        downloads = nil
        charging = nil
        settings = nil
    }

    /// Включить/выключить подфункции по настройкам.
    func apply() {
        guard let settings else { return }
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
            SettingsSection("Загрузки", footer: "При включении macOS один раз спросит доступ к папке «Загрузки».") {
                SettingsToggle("Прогресс загрузок",
                               hint: "Safari, Chrome, Firefox и другие браузеры: процент или размер скачанного в закрытой шторке.",
                               isOn: flag(IndicatorsKeys.downloads))
            }
            SettingsSection("Зарядка") {
                SettingsToggle("Анимация подключения зарядки",
                               hint: "Короткая анимация молнии у выреза, когда подключаешь зарядку.",
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
