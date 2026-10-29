import SwiftUI
import KuBoringCore

/// Фоновая фича: HUD громкости и яркости, зарядка, «не спать». Управление — только в настройках.
@MainActor
public final class SystemFeature: NotchFeature {
    public let id = "system"
    public let title = "Система"
    public let symbol = "gearshape.2"
    public let summary = "Индикаторы громкости и яркости, зарядка, «не спать»"
    public let kind: FeatureKind = .background
    public let enabledByDefault = false

    private var model: SystemModel?

    public init() {}

    public func start(_ context: FeatureContext) {
        model?.shutdown()
        let m = SystemModel(context: context)
        model = m
        m.settingsChanged()
    }

    public func stop() {
        model?.shutdown()
        model = nil
    }

    public func makeTabView() -> AnyView? { nil }

    public func makeSettingsView() -> AnyView? {
        guard let model else {
            return AnyView(Text("Включите функцию «Система», чтобы настроить её.").foregroundStyle(.secondary))
        }
        return AnyView(SystemSettingsView(model: model))
    }
}
