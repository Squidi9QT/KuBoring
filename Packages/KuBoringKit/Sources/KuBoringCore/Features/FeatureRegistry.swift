import SwiftUI
import Observation

@MainActor @Observable
public final class FeatureRegistry {
    @ObservationIgnored private let context: FeatureContext
    @ObservationIgnored private var running: Set<String> = []
    @ObservationIgnored private var tabViewCache: [String: AnyView] = [:]
    private var features: [NotchFeature] = []

    public init(context: FeatureContext) {
        self.context = context
    }

    public func register(_ feature: NotchFeature) {
        if let index = features.firstIndex(where: { $0.id == feature.id }) {
            features[index] = feature
        } else {
            features.append(feature)
        }
    }

    public var all: [NotchFeature] { features }

    public func isEnabled(_ feature: NotchFeature) -> Bool {
        context.settings[featureEnabledKey(feature.id, default: feature.enabledByDefault)]
    }

    public var orderedTabFeatures: [NotchFeature] {
        let tabs = features.filter { $0.kind == .tab }
        let order = context.settings[CoreKeys.tabOrder]
        var result: [NotchFeature] = []
        for id in order {
            if let f = tabs.first(where: { $0.id == id }), !result.contains(where: { $0.id == id }) {
                result.append(f)
            }
        }
        for f in tabs where !result.contains(where: { $0.id == f.id }) { result.append(f) }
        return result
    }

    public var enabledTabs: [NotchFeature] {
        orderedTabFeatures.filter { isEnabled($0) }
    }

    public func resolvedTab(_ selected: String?) -> NotchFeature? {
        let tabs = enabledTabs
        return tabs.first(where: { $0.id == selected }) ?? tabs.first
    }

    public func tabView(for feature: NotchFeature) -> AnyView? {
        if let cached = tabViewCache[feature.id] { return cached }
        guard let view = feature.makeTabView() else { return nil }
        tabViewCache[feature.id] = view
        return view
    }

    public var backgroundFeatures: [NotchFeature] {
        features.filter { $0.kind == .background }
    }

    public func moveTabs(from source: IndexSet, to destination: Int) {
        var ids = orderedTabFeatures.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        context.settings[CoreKeys.tabOrder] = ids
    }

    public func setEnabled(_ id: String, _ on: Bool) {
        guard let feature = features.first(where: { $0.id == id }) else { return }
        context.settings[featureEnabledKey(id, default: feature.enabledByDefault)] = on
        sync(feature)
    }

    public func startEnabled() {
        for feature in features { sync(feature) }
    }

    private func sync(_ feature: NotchFeature) {
        let enabled = isEnabled(feature)
        if enabled && !running.contains(feature.id) {
            running.insert(feature.id)
            feature.start(context)
        } else if !enabled && running.contains(feature.id) {
            running.remove(feature.id)
            tabViewCache[feature.id] = nil
            feature.stop()
        }
    }
}
