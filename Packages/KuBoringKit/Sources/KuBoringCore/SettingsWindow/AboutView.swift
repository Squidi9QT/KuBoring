import SwiftUI
import AppKit

struct AboutView: View {
    let settings: SettingsStore
    let registry: FeatureRegistry
    @State private var confirmReset = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Версия \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 80, height: 80)
                    Text("KuBoring").font(.title2.bold())
                    Text(version).font(.callout).foregroundStyle(.secondary)
                    Text("Шторка для вашего Mac: музыка, файлы, буфер обмена, таймер и ИИ прямо у выреза.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            SettingsSection("Лицензии",
                            footer: "Вдохновлено Boring Notch. Код написан с нуля. Для управления музыкой используется MediaRemoteAdapter (BSD-3).") {
                LabeledContent("KuBoring", value: "MIT")
                LabeledContent("MediaRemoteAdapter", value: "BSD-3-Clause")
            }
            SettingsSection("Сброс") {
                SettingsResetButton("Сбросить все настройки") { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("О программе")
        .confirmationDialog("Сбросить все настройки KuBoring?", isPresented: $confirmReset) {
            Button("Сбросить", role: .destructive) {
                settings.reset(prefix: "core.")
                settings.reset(prefix: "feature.")
                registry.startEnabled()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все параметры вернутся к значениям по умолчанию.")
        }
    }
}
