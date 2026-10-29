import SwiftUI

struct FeaturesSettingsView: View {
    let settings: SettingsStore
    let registry: FeatureRegistry

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(registry.orderedTabFeatures, id: \.id) { feature in
                        row(feature)
                    }
                    .onMove { source, destination in
                        registry.moveTabs(from: source, to: destination)
                    }
                } header: {
                    Text("Вкладки")
                } footer: {
                    Text("Перетащите строку, чтобы изменить порядок вкладок в шторке.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !registry.backgroundFeatures.isEmpty {
                    Section {
                        ForEach(registry.backgroundFeatures, id: \.id) { feature in
                            row(feature)
                        }
                    } header: {
                        Text("Фоновые функции")
                    } footer: {
                        Text("Работают без вкладки: показывают всплывашки вокруг выреза.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                SettingsResetButton {
                    settings.reset(CoreKeys.tabOrder)
                    for feature in registry.all {
                        settings.reset(featureEnabledKey(feature.id, default: feature.enabledByDefault))
                    }
                    registry.startEnabled()
                }
            }
            .padding(12)
        }
        .navigationTitle("Вкладки и функции")
    }

    private func row(_ feature: NotchFeature) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                if !feature.summary.isEmpty {
                    Text(feature.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { registry.isEnabled(feature) },
                set: { registry.setEnabled(feature.id, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 3)
    }
}
