import SwiftUI
import IOKit.ps
import KuBoringCore

/// C-колбэк источников питания (без захвата): context = unretained ChargingWatcher.
private func chargingPowerCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let watcher = Unmanaged<ChargingWatcher>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { watcher.powerChanged() }
}

/// Подключили зарядку — короткая анимация молнии у выреза.
@MainActor
final class ChargingWatcher {
    private let activities: ActivityCenter
    private var source: CFRunLoopSource?
    private var lastOnAC: Bool?

    private static let activityID = "indicators.charging"

    init(activities: ActivityCenter) {
        self.activities = activities
    }

    func start() {
        guard source == nil else { return }
        lastOnAC = Self.read()?.onAC
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource(chargingPowerCallback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        source = src
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
        lastOnAC = nil
        activities.remove(id: Self.activityID)
    }

    func powerChanged() {
        guard source != nil, let info = Self.read() else { return }
        let previous = lastOnAC
        lastOnAC = info.onAC
        // Анимация только на подключение (не при каждом изменении процента).
        guard previous == false, info.onAC else { return }
        activities.post(LiveActivity(
            id: Self.activityID,
            priority: 75,
            expiresAt: Date().addingTimeInterval(3),
            extraWidth: 30,
            leading: AnyView(ChargingBolt()),
            // Справа ничего: только молния слева.
            trailing: AnyView(Color.clear.frame(width: 1, height: 1))
        ))
    }

    private static func read() -> (percent: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let percent = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
            return (percent, (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }
}

/// Молния «вспыхивает»: появляется с пружиной и пару раз пульсирует.
struct ChargingBolt: View {
    @State private var shown = false
    @State private var pulse = false

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.white)
            .scaleEffect(shown ? (pulse ? 1.15 : 1) : 0.2)
            .opacity(shown ? 1 : 0)
            .shadow(color: .white.opacity(pulse ? 0.8 : 0), radius: 6)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { shown = true }
                withAnimation(.easeInOut(duration: 0.45).repeatCount(4, autoreverses: true).delay(0.3)) { pulse = true }
            }
    }
}
