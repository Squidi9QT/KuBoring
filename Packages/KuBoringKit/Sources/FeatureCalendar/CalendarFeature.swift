import SwiftUI
import KuBoringCore

@MainActor
public final class CalendarFeature: NotchFeature {
    public let id = "calendar"
    public let title = "Календарь"
    public let symbol = "calendar"
    public let summary = "События на сегодня и завтра, отсчёт до созвона и кнопка «Войти»"
    public let kind: FeatureKind = .tab
    public let enabledByDefault = false

    private var model: CalendarModel?

    public init() {}

    public func start(_ context: FeatureContext) {
        model?.shutdown()
        let m = CalendarModel(settings: context.settings, activities: context.activities, notch: context.notch)
        model = m
        m.start()
    }

    public func stop() {
        model?.shutdown()
        model = nil
    }

    public func makeTabView() -> AnyView? {
        guard let model else { return nil }
        return AnyView(CalendarTabView(model: model))
    }

    public func makeSettingsView() -> AnyView? {
        guard let model else {
            return AnyView(Text("Включите «Календарь», чтобы настроить его.").foregroundStyle(.secondary))
        }
        return AnyView(CalendarSettingsView(model: model))
    }
}
