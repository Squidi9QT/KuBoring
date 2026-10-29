import SwiftUI
import KuBoringCore

/// Вкладка «Зеркало»: превью с фронтальной камеры. Камера работает только пока вкладка видна.
@MainActor
public final class CameraFeature: NotchFeature {
    public let id = "camera"
    public let title = "Зеркало"
    public let symbol = "camera"
    public let summary = "Зеркало: превью с камеры, пока вкладка открыта"
    public let kind: FeatureKind = .tab
    public let enabledByDefault = false

    private var model: CameraModel?

    public init() {}

    public func start(_ context: FeatureContext) {
        model?.shutdown()
        model = CameraModel(settings: context.settings)
    }

    public func stop() {
        model?.shutdown()
        model = nil
    }

    public func makeTabView() -> AnyView? {
        guard let model else { return nil }
        return AnyView(CameraTabView(model: model))
    }

    public func makeSettingsView() -> AnyView? {
        guard let model else {
            return AnyView(Text("Включите «Зеркало», чтобы настроить его.").foregroundStyle(.secondary))
        }
        return AnyView(CameraSettingsView(model: model))
    }
}
