import SwiftUI

struct GeneralSettingsView: View {
    let settings: SettingsStore
    @State private var launchError: String?

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { settings[CoreKeys.launchAtLogin] },
            set: { on in
                settings[CoreKeys.launchAtLogin] = on
                do {
                    try LaunchAtLogin.set(on)
                    launchError = nil
                } catch {
                    launchError = "Не удалось изменить автозапуск: \(error.localizedDescription)"
                    settings[CoreKeys.launchAtLogin] = LaunchAtLogin.isEnabled
                }
            }
        )
    }

    var body: some View {
        Form {
            SettingsSection("Запуск", footer: launchError) {
                SettingsToggle(
                    "Запускать при входе в систему",
                    hint: "KuBoring будет открываться автоматически вместе с macOS.",
                    isOn: launchBinding)
            }
            SettingsSection("Экраны") {
                SettingsToggle(
                    "Показывать на всех экранах",
                    hint: "Выключено: шторка только на главном экране (с меню-баром).",
                    isOn: settings.binding(CoreKeys.showOnAllScreens))
                SettingsToggle(
                    "Скрывать в полноэкранных приложениях",
                    hint: "Шторка не будет мешать видео и играм на весь экран.",
                    isOn: settings.binding(CoreKeys.hideInFullscreen))
            }
            SettingsSection("Вкладки") {
                SettingsToggle(
                    "Помнить последнюю вкладку",
                    hint: "При открытии шторки показывается вкладка, на которой вы закончили.",
                    isOn: settings.binding(CoreKeys.rememberLastTab))
                SettingsToggle(
                    "Показывать заряд аккумулятора",
                    hint:
                        "Процент и значок батареи рядом с кнопкой настроек; по клику — панель с состоянием зарядки и режимом энергосбережения.",
                    isOn: settings.binding(CoreKeys.showBattery))
            }
            SettingsSection("Сброс") {
                SettingsResetButton {
                    settings.reset(CoreKeys.showOnAllScreens)
                    settings.reset(CoreKeys.hideInFullscreen)
                    settings.reset(CoreKeys.rememberLastTab)
                    settings.reset(CoreKeys.lastTab)
                    settings.reset(CoreKeys.showBattery)
                    settings.reset(CoreKeys.launchAtLogin)
                    try? LaunchAtLogin.set(false)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Общие")
        .onAppear {
            let actual = LaunchAtLogin.isEnabled
            if settings[CoreKeys.launchAtLogin] != actual { settings[CoreKeys.launchAtLogin] = actual }
        }
    }
}
