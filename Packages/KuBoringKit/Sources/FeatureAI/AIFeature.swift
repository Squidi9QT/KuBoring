import SwiftUI
import KuBoringCore

/// Фича «ИИ»: Claude, ChatGPT, Perplexity, Gemini, Qwen, DeepSeek и браузер в веб-окне внутри шторки.
@MainActor
public final class AIFeature: NotchFeature {
    public let id = "ai"
    public let title = "ИИ"
    public let symbol = "sparkles"
    public let summary = "ИИ-сервисы и браузер прямо в шторке; вход сохраняется."
    public let kind: FeatureKind = .tab
    public let enabledByDefault = true

    private let model = AIModel()

    public init() {}

    /// Размер шторки на этой вкладке (настраивается).
    public var preferredOpenSize: CGSize? { model.openSize }

    /// Веб-страница сама принимает файлы (как в Safari).
    public var acceptsDropsItself: Bool { true }

    public func start(_ context: FeatureContext) {
        model.attach(context)
    }

    public func stop() {
        model.shutdown()
    }

    public func makeTabView() -> AnyView? {
        AnyView(AIView(model: model))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(AISettingsView(model: model))
    }
}

struct AISettingsView: View {
    let model: AIModel

    var body: some View {
        if let settings = model.settings {
            Group {
                SettingsSection("Сервисы", footer: "Сервисы открываются как сайты. Вход сохраняется. Google (Gemini) может попросить войти через браузер — это нормально.") {
                    ForEach(model.settingsOrderedServices) { service in
                        AIServiceRow(model: model, service: service)
                    }
                    SettingsPicker("Сервис по умолчанию",
                                   selection: Binding(
                                       get: { model.defaultVisibleService.rawValue },
                                       set: { settings[AIKeys.defaultService] = $0 }
                                   ),
                                   options: model.visibleServices.map { ($0.rawValue, $0.name) })
                }
                SettingsSection("Браузер") {
                    TextField("Домашняя страница", text: settings.binding(AIKeys.browserHome),
                              prompt: Text("https://www.google.com"))
                    SettingsPicker("Поисковик для адресной строки",
                                   selection: settings.binding(AIKeys.searchEngine),
                                   options: SearchEngine.allCases.map { ($0.rawValue, $0.name) })
                }
                SettingsSection("Размер окна") {
                    SettingsSlider("Ширина", value: settings.binding(AIKeys.width), in: 560...1000, step: 20, unit: " pt")
                    SettingsSlider("Высота", value: settings.binding(AIKeys.height), in: 360...800, step: 20, unit: " pt")
                }
                SettingsSection("Память", footer: "Выгруженная страница откроется заново за 1–2 секунды. Вход сохраняется.") {
                    SettingsPicker("Держать в памяти",
                                   hint: "Сколько страниц сервисов остаются загруженными; самая давняя выгружается.",
                                   selection: settings.binding(AIKeys.keepAlive),
                                   options: [(1, "1 сервис"), (2, "2 сервиса"), (3, "3 сервиса"), (0, "Все сервисы")])
                    SettingsPicker("Выгружать после закрытия шторки",
                                   hint: "Страница, где вы недавно печатали (до 30 мин), остаётся.",
                                   selection: settings.binding(AIKeys.unloadMinutes),
                                   options: [(0, "Никогда"), (5, "Через 5 мин"), (10, "Через 10 мин"), (30, "Через 30 мин")])
                }
                SettingsSection("Аккаунты", footer: "Удалит cookie и другие данные сайтов во всех сервисах и в браузере. Потом нужно будет войти заново.") {
                    Button("Выйти из аккаунтов (очистить данные сайтов)") {
                        Task { await model.signOut() }
                    }
                    if let message = model.statusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text("Включите функцию, чтобы изменить настройки.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Строка сервиса: иконка, название, домен, порядок (вверх/вниз) и тумблер.
private struct AIServiceRow: View {
    let model: AIModel
    let service: AIService

    var body: some View {
        let enabled = model.isEnabled(service)
        HStack(spacing: 10) {
            Image(systemName: service.symbol)
                .foregroundStyle(service.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.name)
                Text(service.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if enabled {
                Button {
                    model.move(service, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canMove(service, by: -1))
                .help("Выше")
                Button {
                    model.move(service, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canMove(service, by: 1))
                .help("Ниже")
            }
            Toggle("", isOn: Binding(
                get: { model.isEnabled(service) },
                set: { model.setEnabled(service, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!model.canToggle(service))
        }
    }
}
