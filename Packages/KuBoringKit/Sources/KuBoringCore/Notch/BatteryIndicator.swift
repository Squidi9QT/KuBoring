import SwiftUI
import AppKit
import IOKit.ps
import Observation

/// Когда включать режим энергосбережения (как в Системных настройках → Аккумулятор).
enum LowPowerSchedule: String, CaseIterable, Identifiable {
    case never, always, onBattery, onAdapter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Выкл"
        case .always: return "Всегда"
        case .onBattery: return "От батареи"
        case .onAdapter: return "От сети"
        }
    }

    /// Значения lowpowermode для питания от батареи (-b) и от сети (-c).
    var values: (battery: Int, adapter: Int) {
        switch self {
        case .never: return (0, 0)
        case .always: return (1, 1)
        case .onBattery: return (1, 0)
        case .onAdapter: return (0, 1)
        }
    }

    init?(battery: Int, adapter: Int) {
        guard let match = Self.allCases.first(where: { $0.values == (battery, adapter) }) else { return nil }
        self = match
    }
}

/// C-колбэк источников питания (без захвата): context = unretained BatteryMonitor.
private func batteryPowerCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.refresh() }
}

/// Состояние встроенного аккумулятора. Заряд обновляется по системному уведомлению IOKit (без опроса).
/// Один на приложение: создаёт NotchWindowManager и передаёт в окна шторки.
@MainActor @Observable
final class BatteryMonitor {
    /// 0...100; nil — аккумулятора нет (Mac mini, iMac и т.п.).
    private(set) var level: Int?
    private(set) var charging = false
    private(set) var pluggedIn = false
    private(set) var fullyCharged = false
    /// Минуты до полной зарядки / до разрядки; nil — macOS ещё считает или неприменимо.
    private(set) var minutesToFull: Int?
    private(set) var minutesToEmpty: Int?
    private(set) var adapterWatts: Int?
    /// Режим энергосбережения включён прямо сейчас.
    private(set) var lowPowerActive = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Расписание режима; nil — ещё не прочитано.
    private(set) var schedule: LowPowerSchedule?
    private(set) var changingSchedule = false
    private(set) var scheduleError: String?

    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var lowPowerObserver: NSObjectProtocol?
    /// Вызывается после каждого обновления заряда: (процент, от сети).
    @ObservationIgnored var onUpdate: ((Int, Bool) -> Void)?
    /// Идёт смена режима (может появиться окно пароля) — шторка не должна закрываться.
    @ObservationIgnored var onBusyChange: ((Bool) -> Void)?

    init() {
        refresh()
        // Монитор живёт всё время работы приложения (его держит NotchWindowManager).
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource(batteryPowerCallback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            source = src
        }
        // Системное уведомление: режим энергосбережения включили/выключили.
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lowPowerActive = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.refreshSchedule()
            }
        }
    }

    /// Снять подписки (при остановке окон шторки).
    func invalidate() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            level = nil
            return
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let newLevel = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
            let newCharging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let newPlugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if level != newLevel { level = newLevel }
            if charging != newCharging { charging = newCharging }
            if pluggedIn != newPlugged { pluggedIn = newPlugged }
            defer { onUpdate?(newLevel, newPlugged) }
            fullyCharged = (d[kIOPSIsChargedKey] as? Bool) ?? (newLevel >= 100)
            minutesToFull = Self.minutes(d[kIOPSTimeToFullChargeKey])
            minutesToEmpty = Self.minutes(d[kIOPSTimeToEmptyKey])
            adapterWatts = newPlugged
                ? (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any])?[kIOPSPowerAdapterWattsKey] as? Int
                : nil
            return
        }
        level = nil
    }

    /// -1 и 0 у IOKit значат «ещё считается».
    private static func minutes(_ value: Any?) -> Int? {
        guard let m = value as? Int, m > 0 else { return nil }
        return m
    }

    // MARK: Режим энергосбережения

    /// Читает расписание из `pmset -g custom` (без прав администратора).
    func refreshSchedule() {
        Task {
            let output = await PrivilegedPmset.exec("/usr/bin/pmset", ["-g", "custom"]).output
            if let parsed = Self.parseSchedule(output) { schedule = parsed }
        }
    }

    /// Разовый доступ уже выдан — смена режима не спрашивает пароль.
    var passwordless: Bool { PrivilegedPmset.ruleInstalled }

    /// Меняет расписание через pmset: без пароля, если разовый доступ выдан; иначе macOS один раз спросит пароль.
    func setSchedule(_ new: LowPowerSchedule) {
        guard !changingSchedule, new != schedule else { return }
        changingSchedule = true
        onBusyChange?(true)
        scheduleError = nil
        let v = new.values
        Task {
            let outcome = await PrivilegedPmset.run(
                [.lowPowerOnBattery(v.battery == 1), .lowPowerOnAdapter(v.adapter == 1)],
                prompt: "KuBoring меняет режим энергосбережения. Пароль нужен один раз.")
            if outcome == .failed { scheduleError = "Не удалось изменить режим" }
            changingSchedule = false
            onBusyChange?(false)
            lowPowerActive = ProcessInfo.processInfo.isLowPowerModeEnabled
            refreshSchedule()
        }
    }

    static func parseSchedule(_ text: String) -> LowPowerSchedule? {
        var battery: Int?, adapter: Int?
        var section = ""
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasSuffix(":") { section = s; continue }
            let parts = s.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, parts[0] == "lowpowermode", let value = Int(parts[1]) else { continue }
            if section.hasPrefix("Battery") { battery = value } else if section.hasPrefix("AC") { adapter = value }
        }
        // На Mac без батареи есть только секция AC. Значение 2 на некоторых MacBook Pro — «высокая мощность»,
        // это не энергосбережение.
        let b = battery ?? adapter ?? 0, a = adapter ?? battery ?? 0
        return LowPowerSchedule(battery: b == 1 ? 1 : 0, adapter: a == 1 ? 1 : 0)
    }
}

// MARK: Общие подписи

@MainActor
enum BatteryText {
    static func symbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// Цвет значка батареи: белый, красный — только при низком заряде без зарядки. Зарядку показывает молния.
    static func color(_ b: BatteryMonitor, level: Int) -> Color {
        if level <= 20 && !b.pluggedIn { return .red }
        return Color.white.opacity(0.85)
    }

    static func status(_ b: BatteryMonitor) -> String {
        if b.charging { return "Заряжается" }
        if b.pluggedIn { return b.fullyCharged ? "Заряжен, от сети" : "Подключено, не заряжается" }
        return "От аккумулятора"
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) мин" }
        return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
    }
}

/// Мини-индикатор аккумулятора для шапки открытой шторки: процент + значок. Клик открывает панель.
struct BatteryIndicator: View {
    let battery: BatteryMonitor
    var active = false
    var action: () -> Void = {}

    var body: some View {
        if let level = battery.level {
            Button(action: action) {
                HStack(spacing: 4) {
                    if battery.pluggedIn && !battery.charging {
                        Image(systemName: "powerplug.fill")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text("\(level)%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                    Image(systemName: BatteryText.symbol(level: level, charging: battery.charging))
                        .font(.system(size: 14, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(active ? 0.18 : 0)))
                .foregroundStyle(BatteryText.color(battery, level: level))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Аккумулятор: \(level)%, \(BatteryText.status(battery).lowercased())")
            .accessibilityLabel("Аккумулятор \(level)%, \(BatteryText.status(battery))")
        }
    }
}

/// Панель аккумулятора поверх вкладки: заряд, состояние, время, адаптер и режим энергосбережения.
struct BatteryPanel: View {
    let battery: BatteryMonitor
    let controls: QuickControls
    var cornerRadius: Double = 14
    let onClose: () -> Void

    var body: some View {
        let level = battery.level ?? 0
        VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 18) {
            // Слева — заряд и состояние.
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: BatteryText.symbol(level: level, charging: battery.charging))
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BatteryText.color(battery, level: level))
                    Text("\(level)%")
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Text(BatteryText.status(battery))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(battery.charging ? Color.green : Color.white.opacity(0.9))
                Group {
                    if let detail {
                        Text(detail)
                    }
                    if let watts = battery.adapterWatts {
                        Text("Адаптер: \(watts) Вт")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Справа — режим энергосбережения.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: battery.lowPowerActive ? "leaf.fill" : "leaf")
                        .foregroundStyle(battery.lowPowerActive ? Color.yellow : Color.white.opacity(0.6))
                    Text("Энергосбережение")
                        .font(.system(size: 12, weight: .semibold))
                    Text(battery.lowPowerActive ? "вкл" : "выкл")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                    if battery.changingSchedule {
                        ProgressView().controlSize(.mini)
                    }
                }
                Picker("", selection: Binding(
                    get: { battery.schedule ?? .never },
                    set: { battery.setSchedule($0) }
                )) {
                    ForEach(LowPowerSchedule.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(battery.schedule == nil || battery.changingSchedule)
                .frame(width: 260)
                HStack(spacing: 10) {
                    if let error = battery.scheduleError {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text(battery.passwordless ? "Без пароля" : "Пароль спросят один раз")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Button("Настройки…") { openBatterySettings() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 11))
                .frame(width: 260)
            }
        }
            QuickControlsRow(controls: controls)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(white: 0.09))
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("Закрыть")
        }
        .foregroundStyle(.white)
        .onAppear {
            battery.refresh()
            battery.refreshSchedule()
        }
    }

    private var detail: String? {
        if battery.charging {
            return battery.minutesToFull.map { "До полной: \(BatteryText.duration($0))" } ?? "Считаем время до полной…"
        }
        if battery.pluggedIn {
            return battery.fullyCharged ? nil : "macOS приостановила зарядку (оптимизация или лимит)"
        }
        return battery.minutesToEmpty.map { "Хватит на \(BatteryText.duration($0))" } ?? "Считаем оставшееся время…"
    }

    private func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
