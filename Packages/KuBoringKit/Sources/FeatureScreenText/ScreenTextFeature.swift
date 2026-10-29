import SwiftUI
import KuBoringCore

/// Фича «Текст с экрана»: выделить область, распознать (Vision), скопировать.
@MainActor
public final class ScreenTextFeature: NotchFeature {
    public let id = "screentext"
    public let title = "Текст с экрана"
    public let symbol = "text.viewfinder"
    public let summary = "Выделите область экрана — текст распознаётся и скопируется."
    public let kind: FeatureKind = .tab
    public let enabledByDefault = false

    private let model = ScreenTextModel()

    public init() {}

    public func start(_ context: FeatureContext) {
        model.attach(context)
    }

    public func stop() {
        model.shutdown()
    }

    public func makeTabView() -> AnyView? {
        AnyView(ScreenTextView(model: model))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ScreenTextSettingsView(model: model))
    }
}

struct ScreenTextSettingsView: View {
    let model: ScreenTextModel

    var body: some View {
        if let settings = model.settings {
            Group {
                SettingsSection("Распознавание",
                                footer: "Для выделения области macOS потребует разрешение «Запись экрана».") {
                    SettingsToggle("Копировать сразу после распознавания",
                                   hint: "Текст попадёт в буфер обмена без нажатия кнопки.",
                                   isOn: settings.binding(ScreenTextKeys.copyImmediately))
                }
            }
        } else {
            Text("Включите функцию, чтобы изменить настройки.")
                .foregroundStyle(.secondary)
        }
    }
}
