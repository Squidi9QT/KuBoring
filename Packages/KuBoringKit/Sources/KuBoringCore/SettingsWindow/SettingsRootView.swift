import SwiftUI

/// Пункт бокового меню настроек.
private struct SidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    var keywords: [String] = []

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return title.lowercased().contains(q) || keywords.contains { $0.lowercased().contains(q) }
    }
}

struct SettingsRootView: View {
    let settings: SettingsStore
    let registry: FeatureRegistry

    @State private var selection: String? = "general"
    @State private var query = ""

    private let general = SidebarItem(id: "general", title: "Общие", symbol: "gearshape",
                                      keywords: ["автозапуск", "экраны", "полноэкранный"])
    private let notchItem = SidebarItem(id: "notch", title: "Шторка", symbol: "rectangle.topthird.inset.filled",
                                        keywords: ["размер", "анимация", "задержка", "радиус", "наведение", "геометрия"])
    private let features = SidebarItem(id: "features", title: "Вкладки и функции", symbol: "square.grid.2x2",
                                       keywords: ["порядок", "включить", "выключить"])
    private let about = SidebarItem(id: "about", title: "О программе", symbol: "info.circle",
                                    keywords: ["версия", "лицензия"])

    /// Разделы включённых фич, у которых есть свои настройки.
    private var featureItems: [SidebarItem] {
        registry.all.compactMap { f in
            guard registry.isEnabled(f), f.makeSettingsView() != nil else { return nil }
            return SidebarItem(id: "feature.\(f.id)", title: f.title, symbol: f.symbol)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach([general, notchItem, features].filter { $0.matches(query) }) { item in
                Label(item.title, systemImage: item.symbol).tag(item.id)
            }
            let fItems = featureItems.filter { $0.matches(query) }
            if !fItems.isEmpty {
                Section("Функции") {
                    ForEach(fItems) { item in
                        Label(item.title, systemImage: item.symbol).tag(item.id)
                    }
                }
            }
            if about.matches(query) {
                Label(about.title, systemImage: about.symbol).tag(about.id)
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Поиск")
    }

    @ViewBuilder
    private var detail: some View {
        let current = selection ?? "general"
        if current == "notch" {
            NotchSettingsView(settings: settings)
        } else if current == "features" {
            FeaturesSettingsView(settings: settings, registry: registry)
        } else if current == "about" {
            AboutView(settings: settings, registry: registry)
        } else if current.hasPrefix("feature."),
                  let feature = registry.all.first(where: { "feature.\($0.id)" == current }) {
            FeatureSettingsView(settings: settings, feature: feature)
        } else {
            GeneralSettingsView(settings: settings)
        }
    }
}

/// Раздел настроек конкретной фичи.
struct FeatureSettingsView: View {
    let settings: SettingsStore
    let feature: NotchFeature

    var body: some View {
        Form {
            if let view = feature.makeSettingsView() {
                view
            }
            SettingsSection("Сброс") {
                SettingsResetButton {
                    // Сбрасываем настройки фичи, но не её включённость.
                    let key = featureEnabledKey(feature.id, default: feature.enabledByDefault)
                    let wasEnabled = settings[key]
                    settings.reset(prefix: "feature.\(feature.id).")
                    settings[key] = wasEnabled
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(feature.title)
    }
}
