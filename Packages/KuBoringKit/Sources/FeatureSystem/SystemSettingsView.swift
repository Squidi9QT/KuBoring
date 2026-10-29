import SwiftUI
import KuBoringCore

struct SystemSettingsView: View {
    let model: SystemModel

    /// Привязка к булевой настройке; после записи применяем изменения.
    private func flag(_ key: SettingKey<Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[key] },
            set: { newValue in
                model.settings[key] = newValue
                model.settingsChanged()
            }
        )
    }

    var body: some View {
        Group {
            SettingsSection("Громкость и яркость",
                            footer: "Индикатор появляется в закрытой шторке на полторы секунды. Системный индикатор macOS при этом остаётся.") {
                SettingsToggle("Индикатор громкости",
                               hint: "Показывать уровень звука при изменении громкости или отключении звука.",
                               isOn: flag(SystemKeys.hudVolume))
                SettingsToggle("Индикатор яркости",
                               hint: model.brightnessAvailable
                                   ? "Показывать уровень яркости встроенного экрана."
                                       + (model.brightnessMode.map { " Слежение: \($0.label)." } ?? "")
                                   : "Недоступно на этом Mac.",
                               isOn: flag(SystemKeys.hudBrightness))
                    .disabled(!model.brightnessAvailable)
            }

            SettingsSection("Зарядка") {
                SettingsToggle("Показывать подключение зарядки",
                               hint: "Всплывашка с процентом заряда, когда зарядку подключили или отключили.",
                               isOn: flag(SystemKeys.battery))
                SettingsToggle("Показывать процент при низком заряде (<20%)",
                               hint: "Предупреждение, когда заряд падает ниже 20% при работе от батареи.",
                               isOn: flag(SystemKeys.batteryLow))
                    .disabled(!model.settings[SystemKeys.battery])
            }

            SettingsSection("Не спать",
                            footer: "Пока включено, экран и Mac не будут засыпать по бездействию. При выключении функции «Система» режим снимается.") {
                SettingsToggle("Не давать Mac засыпать",
                               hint: "Удерживает экран включённым.",
                               isOn: flag(SystemKeys.keepAwake))
                SettingsToggle("Показывать значок в шторке",
                               hint: "Маленькая чашка кофе в закрытой шторке, пока режим включён.",
                               isOn: flag(SystemKeys.keepAwakeBadge))
                    .disabled(!model.settings[SystemKeys.keepAwake])
            }
        }
    }
}
