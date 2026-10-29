import SwiftUI
import AppKit
import IOKit.pwr_mgt
import Observation

/// Быстрые переключатели в панели аккумулятора: «не спать с крышкой», тёмная тема, «не засыпать».
/// Один на приложение: создаёт NotchWindowManager.
@MainActor @Observable
final class QuickControls {
    private(set) var darkMode = false
    private(set) var keepAwake = false
    private(set) var error: String?
    /// Сон запрещён системно — Mac не уснёт даже с закрытой крышкой.
    private(set) var lidAwake = false
    private(set) var lidChanging = false

    /// Идёт смена режима сна (может появиться окно пароля) — шторка не должна закрываться.
    @ObservationIgnored var onBusyChange: ((Bool) -> Void)?
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var themeObserver: NSObjectProtocol?
    @ObservationIgnored private var errorTask: Task<Void, Never>?

    static let lidActivityID = "core.lidAwake"

    init(settings: SettingsStore, activities: ActivityCenter) {
        self.settings = settings
        self.activities = activities
        refresh()
        refreshLid()
        // Системное уведомление: тему поменяли (здесь или в Настройках).
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.darkMode = Self.readDarkMode() }
        }
    }

    func invalidate() {
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
        themeObserver = nil
        if keepAwake { IOPMAssertionRelease(assertionID) }
        keepAwake = false
        // Выход из приложения: вернуть обычный сон, если запрещали мы. Синхронно — процесс вот-вот завершится.
        if settings[CoreKeys.lidAwakeByApp] {
            if Self.runSync("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + PrivilegedPmset.Command.disableSleep(false).arguments) {
                settings[CoreKeys.lidAwakeByApp] = false
            }
        }
    }

    // MARK: Не спать с закрытой крышкой

    /// Перечитать системное состояние (SleepDisabled).
    func refreshLid() {
        Task {
            lidAwake = await PrivilegedPmset.sleepDisabled()
            if !lidAwake, settings[CoreKeys.lidAwakeByApp] { settings[CoreKeys.lidAwakeByApp] = false }
            updateLidBadge()
        }
    }

    func toggleLidAwake() {
        setLidAwake(!lidAwake, reason: nil)
    }

    /// Включить/выключить. Права администратора: пароль спросят один раз, дальше — без пароля.
    private func setLidAwake(_ on: Bool, reason: String?) {
        guard !lidChanging else { return }
        lidChanging = true
        onBusyChange?(true)
        Task {
            let outcome = await PrivilegedPmset.run(
                [.disableSleep(on)],
                prompt: on ? "KuBoring запрещает сон, чтобы Mac работал с закрытой крышкой. Пароль нужен один раз."
                           : "KuBoring возвращает обычный сон.")
            lidChanging = false
            onBusyChange?(false)
            if outcome == .failed { show("Не удалось изменить режим сна") }
            lidAwake = await PrivilegedPmset.sleepDisabled()
            if settings[CoreKeys.lidAwakeByApp] != lidAwake { settings[CoreKeys.lidAwakeByApp] = lidAwake }
            updateLidBadge()
            if let reason, !lidAwake { show(reason) }
        }
    }

    /// Заряд изменился: от батареи и ≤10% — снимаем запрет сна, чтобы Mac не разрядился в ноль в сумке.
    func batteryChanged(level: Int, pluggedIn: Bool) {
        guard lidAwake, !pluggedIn, level <= 10, !lidChanging, PrivilegedPmset.ruleInstalled else { return }
        setLidAwake(false, reason: "Заряд \(level)% — сон снова разрешён")
    }

    /// Пока сон запрещён — значок ноутбука в закрытой шторке, чтобы не забыть.
    private func updateLidBadge() {
        if lidAwake {
            activities.post(LiveActivity(
                id: Self.lidActivityID,
                priority: 15,
                extraWidth: 24,
                leading: AnyView(
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.yellow)
                        .help("Mac не уснёт даже с закрытой крышкой")
                ),
                trailing: AnyView(Color.clear.frame(width: 1, height: 1))
            ))
        } else {
            activities.remove(id: Self.lidActivityID)
        }
    }

    private static func runSync(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Перечитать состояние (при открытии панели).
    func refresh() {
        darkMode = Self.readDarkMode()
    }

    // MARK: Тёмная тема

    /// Через System Events (macOS один раз спросит разрешение на управление).
    func toggleDarkMode() {
        let target = !darkMode
        darkMode = target
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(target)"
        Task {
            let ok = await Self.run("/usr/bin/osascript", ["-e", script])
            darkMode = Self.readDarkMode()
            if !ok { show("Разреши KuBoring управлять «System Events» в Настройках → Конфиденциальность → Автоматизация") }
        }
    }

    private static func readDarkMode() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    // MARK: Не засыпать

    func toggleKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            keepAwake = false
        } else {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "KuBoring: «Не засыпать» из шторки" as CFString, &id)
            if result == kIOReturnSuccess {
                assertionID = id
                keepAwake = true
            }
        }
    }

    // MARK: Вспомогательное

    private func show(_ text: String) {
        error = text
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.error = nil
        }
    }

    private static func run(_ tool: String, _ args: [String]) async -> Bool {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }.value
    }
}

/// Ряд кнопок-переключателей под состоянием аккумулятора.
struct QuickControlsRow: View {
    let controls: QuickControls

    var body: some View {
        // Не влезает с подписями — второстепенные кнопки сжимаются до значков (подпись во всплывающей подсказке).
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
        .onAppear {
            controls.refresh()
            controls.refreshLid()
        }
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: 8) {
            toggle("Не спать с крышкой",
                   symbol: controls.lidAwake ? "checkmark.square.fill" : "square",
                   on: controls.lidAwake, compact: false, busy: controls.lidChanging,
                   help: "Mac продолжит работать (например, нейронка) даже с закрытой крышкой. "
                       + "Выключится сам при выходе из KuBoring и при заряде 10% без зарядки.",
                   action: controls.toggleLidAwake)
            toggle("Тёмная тема", symbol: controls.darkMode ? "moon.fill" : "moon", on: controls.darkMode,
                   compact: compact, action: controls.toggleDarkMode)
            toggle("Не засыпать", symbol: controls.keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer",
                   on: controls.keepAwake, compact: compact,
                   help: "Экран не гаснет, пока крышка открыта", action: controls.toggleKeepAwake)
            if let error = controls.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ title: String, symbol: String, on: Bool, compact: Bool, busy: Bool = false,
                        help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                if !compact {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(on ? Color.black : Color.white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(help ?? title)
    }
}
