import AppKit
import SwiftUI
import KuBoringCore

@MainActor
public final class TimerFeature: NotchFeature {
    public let id = "timer"
    public let title = "Таймер"
    public let symbol = "timer"
    public let summary = "Таймер с пресетами и режим «помидор»; кольцо прогресса в закрытой шторке."
    public let kind: FeatureKind = .tab
    public let enabledByDefault = true

    private let model = TimerModel()

    public init() {}

    public func start(_ context: FeatureContext) {
        model.attach(context)
    }

    public func stop() {
        model.shutdown()
    }

    public func makeTabView() -> AnyView? {
        AnyView(TimerView(model: model))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(TimerSettingsView(model: model))
    }
}

struct TimerSettingsView: View {
    let model: TimerModel

    @State private var newMinutes = 30

    private static let sounds = ["Glass", "Hero", "Ping", "Submarine", "Funk"]

    var body: some View {
        if let settings = model.settings {
            Group {
                SettingsSection(
                    "Пресеты",
                    footer: "Эти кнопки появятся во вкладке таймера. Максимум \(TimerModel.maxPresets)."
                ) {
                    ForEach(model.presets, id: \.self) { minutes in
                        HStack {
                            Text("\(minutes) мин")
                                .monospacedDigit()
                            Spacer()
                            Button {
                                remove(minutes, settings)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.presets.count <= 1)
                            .help("Удалить пресет")
                        }
                    }
                    HStack(spacing: 8) {
                        Stepper("", value: $newMinutes, in: 1...600)
                            .labelsHidden()
                        TextField("", value: $newMinutes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("мин")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Добавить") { add(settings) }
                            .disabled(!canAdd)
                    }
                    HStack {
                        Spacer()
                        Button("Вернуть стандартные (5/15/25/50)") {
                            settings[TimerKeys.presets] = TimerModel.defaultPresets
                        }
                    }
                }
                SettingsSection(
                    "Помидор",
                    footer:
                        "Кнопка «🍅 Помидор» во вкладке: работа и перерывы идут по очереди сами, после 4 рабочих отрезков — длинный перерыв."
                ) {
                    SettingsPicker(
                        "Работа", selection: settings.binding(TimerKeys.pomodoroWork),
                        options: [15, 20, 25, 30, 45, 50, 60].map { ($0, "\($0) мин") })
                    SettingsPicker(
                        "Перерыв", selection: settings.binding(TimerKeys.pomodoroBreak),
                        options: [3, 5, 10, 15].map { ($0, "\($0) мин") })
                    SettingsPicker(
                        "Длинный перерыв", selection: settings.binding(TimerKeys.pomodoroLongBreak),
                        options: [10, 15, 20, 30].map { ($0, "\($0) мин") })
                }
                SettingsSection("По окончании") {
                    SettingsPicker(
                        "Звук", selection: settings.binding(TimerKeys.sound),
                        options: Self.sounds.map { ($0, $0) })
                    SettingsToggle(
                        "Открывать шторку по окончании",
                        hint: "Шторка раскроется на вкладке таймера, когда время выйдет.",
                        isOn: settings.binding(TimerKeys.openOnFinish))
                }
            }
        } else {
            Text("Включите функцию, чтобы изменить настройки.")
                .foregroundStyle(.secondary)
        }
    }

    private var clampedMinutes: Int { min(600, max(1, newMinutes)) }

    private var canAdd: Bool {
        model.presets.count < TimerModel.maxPresets && !model.presets.contains(clampedMinutes)
    }

    private func add(_ settings: SettingsStore) {
        guard canAdd else { return }
        newMinutes = clampedMinutes
        settings[TimerKeys.presets] = (model.presets + [clampedMinutes]).sorted()
    }

    private func remove(_ minutes: Int, _ settings: SettingsStore) {
        let rest = model.presets.filter { $0 != minutes }
        guard !rest.isEmpty else { return }
        settings[TimerKeys.presets] = rest
    }
}
