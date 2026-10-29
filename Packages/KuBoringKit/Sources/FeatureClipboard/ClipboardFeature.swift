import SwiftUI
import KuBoringCore

/// Фича «Буфер»: история скопированного текста.
@MainActor
public final class ClipboardFeature: NotchFeature {
    public let id = "clipboard"
    public let title = "Буфер"
    public let symbol = "doc.on.clipboard"
    public let summary = "История скопированного: текст и картинки, закрепление, поиск, вызов по ⌘⇧V."
    public let kind: FeatureKind = .tab
    public let enabledByDefault = true

    private let model = ClipboardModel()

    public init() {}

    public func start(_ context: FeatureContext) {
        model.start(context)
    }

    public func stop() {
        model.stop()
    }

    public func makeTabView() -> AnyView? {
        AnyView(ClipboardView(model: model))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ClipboardSettingsView(model: model))
    }
}

struct ClipboardSettingsView: View {
    let model: ClipboardModel

    var body: some View {
        if let settings = model.settings {
            let limit = Binding<Double>(
                get: { Double(settings[ClipboardKeys.limit]) },
                set: { settings[ClipboardKeys.limit] = Int($0) }
            )
            Group {
                SettingsSection("История") {
                    SettingsSlider("Размер истории", hint: "Сколько последних записей помнить.",
                                   value: limit, in: 10...200, step: 10, unit: " шт.")
                    SettingsToggle("Хранить между запусками",
                                   hint: "Записи сохраняются на диск. По умолчанию выключено: история живёт только в памяти.",
                                   isOn: settings.binding(ClipboardKeys.persist))
                }
                SettingsSection("Горячая клавиша",
                                footer: "⌘⇧V открывает историю в любом приложении: ↑↓ — выбор, ⏎ — вставить, esc — закрыть. Закреплённые записи (значок булавки) не удаляются при очистке и не вытесняются лимитом.") {
                    SettingsToggle("Открывать историю по ⌘⇧V",
                                   hint: "Выключено — всё как раньше: историю открываешь наведением на шторку.",
                                   isOn: Binding(get: { settings[ClipboardKeys.hotkey] },
                                                 set: { settings[ClipboardKeys.hotkey] = $0; model.applyHotKey() }))
                    SettingsToggle("Сразу вставлять выбранное",
                                   hint: "После ⏎ запись вставится туда, где стоял курсор. Нужен доступ «Универсальный доступ» — macOS спросит один раз. Без него запись просто копируется.",
                                   isOn: Binding(get: { settings[ClipboardKeys.autoPaste] },
                                                 set: { on in
                                                     settings[ClipboardKeys.autoPaste] = on
                                                     if on { ClipboardModel.requestAccessibility() }
                                                 }))
                        .disabled(!settings[ClipboardKeys.hotkey])
                }
                SettingsSection("Картинки") {
                    SettingsToggle("Сохранять скопированные картинки",
                                   hint: "Последние 15 картинок, только в памяти: на диск не пишутся.",
                                   isOn: settings.binding(ClipboardKeys.images))
                }
                SettingsSection("Приватность") {
                    SettingsToggle("Пропускать пароли из менеджеров паролей",
                                   hint: "Не сохранять то, что помечено как секретное (1Password, Bitwarden и др.).",
                                   isOn: settings.binding(ClipboardKeys.skipSecrets))
                }
            }
        } else {
            Text("Включите функцию, чтобы изменить настройки.")
                .foregroundStyle(.secondary)
        }
    }
}
