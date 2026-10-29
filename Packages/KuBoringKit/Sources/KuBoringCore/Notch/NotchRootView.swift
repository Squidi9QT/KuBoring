import SwiftUI
import Observation

/// Кто из экранов сейчас «хозяин» шторки (при нескольких мониторах состояние общее).
@MainActor @Observable
final class NotchScreenArbiter {
    var activeID: CGDirectDisplayID?
    init(activeID: CGDirectDisplayID? = nil) { self.activeID = activeID }
}

/// Размытие для перехода появления контента.
private struct BlurModifier: ViewModifier {
    let radius: Double
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

/// Направление перехода между вкладками. Класс-коробка: transition читает направление в момент
/// отрисовки, поэтому оно верно и для уходящей, и для приходящей вкладки.
@MainActor
final class TabNav {
    var index: Int?
    /// +1 — новая вкладка правее в списке (контент въезжает справа), -1 — левее.
    var direction: Double = 1
    var wasExpanded = false

    func update(index new: Int?) {
        guard new != index else { return }
        if let old = index, let new { direction = new >= old ? 1 : -1 }
        index = new
    }
}

/// Смещение + прозрачность + масштаб + размытие для перехода вкладок.
private struct TabSlideModifier: ViewModifier {
    let nav: TabNav
    let active: Bool
    let incoming: Bool

    func body(content: Content) -> some View {
        // Приходящая стартует со стороны направления, уходящая уезжает в противоположную.
        let sign = incoming ? nav.direction : -nav.direction
        content
            .offset(x: active ? sign * 24 : 0)
            .opacity(active ? 0 : 1)
            .scaleEffect(active && incoming ? 0.97 : 1, anchor: .top)
            .blur(radius: active ? 4 : 0)
    }
}

/// Ключ анимации формы: одна пружина на размер и состояние.
private struct ShapeKey: Equatable {
    let width: Double
    let height: Double
    let expanded: Bool
}

/// Корневая вьюха окна шторки.
struct NotchRootView: View {
    let displayID: CGDirectDisplayID
    let physicalNotch: CGSize
    let hasNotch: Bool
    let settings: SettingsStore
    let notch: NotchController
    let activities: ActivityCenter
    let registry: FeatureRegistry
    let arbiter: NotchScreenArbiter
    let battery: BatteryMonitor
    let controls: QuickControls
    var onOpenSettings: (() -> Void)? = nil

    @Namespace private var tabNamespace
    @State private var nav = TabNav()

    /// Одинаковый отступ области контента от боков и низа тела шторки (от него считается концентричная рамка drop-зоны).
    private static let contentInset: Double = 12

    private var isActiveScreen: Bool { arbiter.activeID == nil || arbiter.activeID == displayID }

    var body: some View {
        // Геометрия и состояние читаются один раз за проход body.
        let g = settings[CoreKeys.geometry].clamped()
        let phase: NotchPhase = isActiveScreen ? notch.state.phase : .closed
        let isExpanded = phase == .open || phase == .dragging
        let tab = registry.resolvedTab(notch.state.selectedTab)
        // Панель аккумулятора — базового размера, даже поверх большой вкладки (ИИ).
        let openSize = NotchLayout.openSize(g, preferred: notch.batteryPanelOpen ? nil : tab?.preferredOpenSize)
        let activity = activities.current

        let closed = NotchLayout.closedSize(g, physical: physicalNotch, extraWidth: activity?.extraWidth ?? 0)
        let peek = phase == .peeking
        let size = isExpanded
            ? openSize
            : CGSize(width: closed.width + (peek ? 8 : 0), height: closed.height + (peek ? 3 : 0))
        let ear = NotchLayout.ear(open: isExpanded, cornerRadius: g.cornerRadius)
        let bottom = NotchLayout.bottomRadius(open: isExpanded, cornerRadius: g.cornerRadius,
                                              height: size.height)
        let openEar = NotchLayout.maxEar(g)
        let spring = Animation.interactiveSpring(response: 0.38 / g.animationSpeed,
                                                 dampingFraction: 0.8, blendDuration: 0)
        let key = ShapeKey(width: size.width, height: size.height, expanded: isExpanded)
        // Смена вкладки при открытой шторке (размер ИИ больше) идёт той же пружиной, что и контент.
        let tabSpring = Animation.interactiveSpring(response: 0.35 / g.animationSpeed,
                                                    dampingFraction: 0.86, blendDuration: 0)
        let shapeSpring = (isExpanded && nav.wasExpanded) ? tabSpring : spring
        let _ = (nav.wasExpanded = isExpanded)

        ZStack(alignment: .top) {
            Color.clear
            ZStack(alignment: .top) {
                NotchShape(topRadius: ear, bottomRadius: bottom)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(isExpanded ? 0.35 : 0), radius: 10, y: 4)
                    .contentShape(NotchShape(topRadius: ear, bottomRadius: bottom))
                    .onTapGesture {
                        if !isExpanded { notch.send(.clicked) }
                    }

                // Контент рисуется в конечном размере, форма-маска раскрывается поверх.
                ZStack(alignment: .top) {
                    if isExpanded {
                        openContent(tab: tab, phase: phase, tabSpring: tabSpring, bottomRadius: bottom)
                            .padding(.horizontal, openEar)
                            .frame(width: openSize.width + 2 * openEar, height: openSize.height,
                                   alignment: .top)
                            .overlay(alignment: .top) { batteryOverlay(openEar: openEar, bottomRadius: bottom) }
                            .transition(.asymmetric(
                                insertion: AnyTransition.opacity
                                    .combined(with: .scale(scale: 0.9, anchor: .top))
                                    .combined(with: .modifier(active: BlurModifier(radius: 8),
                                                              identity: BlurModifier(radius: 0)))
                                    .animation(spring.delay(0.06)),
                                removal: AnyTransition.opacity.animation(.easeOut(duration: 0.12))))
                    } else {
                        closedContent(activity: activity, size: size)
                            .padding(.horizontal, ear)
                            .frame(width: size.width + 2 * ear, height: size.height)
                            .transition(.opacity)
                    }
                }
                .frame(width: size.width + 2 * ear, height: size.height, alignment: .top)
                .clipShape(NotchShape(topRadius: ear, bottomRadius: bottom))
            }
            .frame(width: size.width + 2 * ear, height: size.height, alignment: .top)
            .environment(\.colorScheme, .dark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(shapeSpring, value: key)
        .animation(.easeInOut(duration: 0.2), value: activity?.id)
        .animation(.easeOut(duration: 0.18), value: notch.batteryPanelOpen)
    }

    // MARK: Закрытое состояние

    @ViewBuilder
    private func closedContent(activity: LiveActivity?, size: CGSize) -> some View {
        if let activity {
            let base = NotchLayout.closedBase(settings[CoreKeys.geometry].clamped(), physical: physicalNotch)
            HStack(spacing: 0) {
                activity.leading
                    .frame(width: activity.extraWidth, height: size.height)
                    .clipped()
                Color.clear.frame(width: base.width, height: size.height)
                activity.trailing
                    .frame(width: activity.extraWidth, height: size.height)
                    .clipped()
            }
            .frame(maxWidth: .infinity)
            .id(activity.id)
        } else {
            Color.clear
        }
    }

    // MARK: Открытое состояние

    private func openContent(tab: NotchFeature?, phase: NotchPhase, tabSpring: Animation,
                             bottomRadius: Double) -> some View {
        let tabs = registry.enabledTabs
        nav.update(index: tabs.firstIndex(where: { $0.id == tab?.id }))
        let navBox = nav
        let headerHeight = max(28, physicalNotch.height)
        return VStack(spacing: 0) {
            header(tabs: tabs, selectedID: tab?.id, height: headerHeight, spring: tabSpring)
            ZStack {
                if let tab, let view = registry.tabView(for: tab) {
                    view
                        .id(tab.id)
                        .transition(.asymmetric(
                            insertion: .modifier(
                                active: TabSlideModifier(nav: navBox, active: true, incoming: true),
                                identity: TabSlideModifier(nav: navBox, active: false, incoming: true)),
                            removal: .modifier(
                                active: TabSlideModifier(nav: navBox, active: true, incoming: false),
                                identity: TabSlideModifier(nav: navBox, active: false, incoming: false))))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "square.dashed").font(.title2)
                        Text("Нет включённых вкладок").font(.callout)
                        Text("Включите функции в настройках KuBoring")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // Под панелью аккумулятора вкладку не показываем (вкладка ИИ шире — выглядывала бы по краям).
            .opacity(notch.batteryPanelOpen ? 0 : 1)
            .padding(.horizontal, Self.contentInset)
            .padding(.bottom, Self.contentInset)
            .animation(tabSpring, value: tab?.id)
        }
        .foregroundStyle(.white)
    }

    /// Панель аккумулятора ровно на месте области контента: те же отступы, что у вкладок,
    /// углы концентричны нижним углам шторки. Не зависит от размера текущей вкладки.
    @ViewBuilder
    private func batteryOverlay(openEar: Double, bottomRadius: Double) -> some View {
        if notch.batteryPanelOpen && settings[CoreKeys.showBattery] {
            BatteryPanel(battery: battery, controls: controls,
                         cornerRadius: max(10, bottomRadius - Self.contentInset)) {
                notch.batteryPanelOpen = false
            }
            .padding(.top, max(28, physicalNotch.height))
            .padding(.horizontal, openEar + Self.contentInset)
            .padding(.bottom, Self.contentInset)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    private func header(tabs: [NotchFeature], selectedID: String?, height: Double,
                        spring: Animation) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.id) { tabButton($0, selected: $0.id == selectedID) }
            }
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasNotch {
                Color.clear.frame(width: physicalNotch.width, height: 1)
            }

            HStack(spacing: 8) {
                if settings[CoreKeys.showBattery] {
                    BatteryIndicator(battery: battery, active: notch.batteryPanelOpen) {
                        notch.batteryPanelOpen.toggle()
                    }
                }
                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gear")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Настройки")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .animation(spring, value: selectedID)
    }

    private func tabButton(_ feature: NotchFeature, selected: Bool) -> some View {
        Button {
            notch.send(.selectTab(feature.id))
        } label: {
            Image(systemName: feature.symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .matchedGeometryEffect(id: "tabBackground", in: tabNamespace)
                    }
                }
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(feature.title)
    }
}
