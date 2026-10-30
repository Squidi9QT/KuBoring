import AppKit
import SwiftUI
import Observation
import KuBoringCore

enum TimerKeys {
    static let presets = SettingKey<[Int]>("feature.timer.presets", default: [5, 15, 25, 50])
    static let sound = SettingKey<String>("feature.timer.sound", default: "Glass")
    static let openOnFinish = SettingKey<Bool>("feature.timer.openOnFinish", default: true)
    static let pomodoroWork = SettingKey<Int>("feature.timer.pomodoroWork", default: 25)
    static let pomodoroBreak = SettingKey<Int>("feature.timer.pomodoroBreak", default: 5)
    static let pomodoroLongBreak = SettingKey<Int>("feature.timer.pomodoroLongBreak", default: 15)
}

enum PomodoroPhase: Equatable {
    case work, shortBreak, longBreak

    var title: String {
        switch self {
        case .work: return "Работа"
        case .shortBreak: return "Перерыв"
        case .longBreak: return "Длинный перерыв"
        }
    }

    var isBreak: Bool { self != .work }
}

@MainActor @Observable
final class TimerModel {
    var total: TimeInterval = 25 * 60
    var remaining: TimeInterval = 25 * 60
    var isRunning = false
    var finished = false
    private(set) var pomodoro = false
    private(set) var phase: PomodoroPhase = .work
    private(set) var completedWork = 0

    private(set) var settings: SettingsStore?
    @ObservationIgnored private var notch: NotchController?
    @ObservationIgnored private var activities: ActivityCenter?
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    static let activityID = "timer"

    var progress: Double { total > 0 ? max(0, min(1, remaining / total)) : 0 }
    var isPaused: Bool { !isRunning && remaining > 0 && remaining < total }

    static let defaultPresets = [5, 15, 25, 50]
    static let maxPresets = 8

    var presets: [Int] {
        let saved = (settings?[TimerKeys.presets] ?? Self.defaultPresets).filter { $0 > 0 }
        return saved.isEmpty ? Self.defaultPresets : saved.sorted()
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }

    func attach(_ context: FeatureContext) {
        settings = context.settings
        notch = context.notch
        activities = context.activities
        if isRunning { postActivity() }
    }

    func shutdown() {
        tickTask?.cancel()
        tickTask = nil
        if isRunning, let end = endDate { remaining = max(0, end.timeIntervalSinceNow) }
        isRunning = false
        activities?.remove(id: Self.activityID)
    }

    func setPomodoro(_ on: Bool) {
        pomodoro = on
        phase = .work
        completedWork = 0
        set(minutes: on ? minutes(for: .work) : (presets.first(where: { $0 == 25 }) ?? presets[0]))
    }

    private func minutes(for phase: PomodoroPhase) -> Int {
        let key: SettingKey<Int>
        switch phase {
        case .work: key = TimerKeys.pomodoroWork
        case .shortBreak: key = TimerKeys.pomodoroBreak
        case .longBreak: key = TimerKeys.pomodoroLongBreak
        }
        return max(1, min(180, settings?[key] ?? key.defaultValue))
    }

    var cycleNumber: Int {
        phase == .work ? completedWork % 4 + 1 : (max(1, completedWork) - 1) % 4 + 1
    }

    var tint: Color { pomodoro && phase.isBreak ? Palette.pause : Palette.timer }

    func set(minutes: Int) {
        stopTicker()
        isRunning = false
        finished = false
        total = TimeInterval(minutes * 60)
        remaining = total
        activities?.remove(id: Self.activityID)
    }

    func adjust(minutes: Int) {
        let delta = TimeInterval(minutes * 60)
        if isRunning, let end = endDate {
            let newEnd = end.addingTimeInterval(delta)
            guard newEnd.timeIntervalSinceNow > 1 else { return }
            endDate = newEnd
            total = max(60, total + delta)
            remaining = newEnd.timeIntervalSinceNow
        } else {
            let value = max(60, min(5 * 3600, remaining + delta))
            total = value
            remaining = value
            finished = false
        }
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        if remaining <= 0 { remaining = total }
        finished = false
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        postActivity()
        stopTicker()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func pause() {
        if let end = endDate { remaining = max(0, end.timeIntervalSinceNow) }
        isRunning = false
        stopTicker()
        activities?.remove(id: Self.activityID)
    }

    func reset() {
        stopTicker()
        isRunning = false
        finished = false
        remaining = total
        activities?.remove(id: Self.activityID)
    }

    private func tick() {
        guard isRunning, let end = endDate else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0, pomodoro {
            nextPomodoroPhase()
        } else if left <= 0 {
            remaining = 0
            isRunning = false
            finished = true
            stopTicker()
            activities?.remove(id: Self.activityID)
            let soundName = settings?[TimerKeys.sound] ?? "Glass"
            NSSound(named: NSSound.Name(soundName))?.play()
            if settings?[TimerKeys.openOnFinish] ?? true {
                notch?.send(.requestOpen(tab: "timer"))
            }
        } else {
            remaining = left
        }
    }

    private func nextPomodoroPhase() {
        let soundName = settings?[TimerKeys.sound] ?? "Glass"
        NSSound(named: NSSound.Name(soundName))?.play()
        if phase == .work {
            completedWork += 1
            phase = completedWork % 4 == 0 ? .longBreak : .shortBreak
        } else {
            if phase == .longBreak { completedWork = 0 }
            phase = .work
        }
        total = TimeInterval(minutes(for: phase) * 60)
        remaining = total
        finished = false
        start()
        if settings?[TimerKeys.openOnFinish] ?? true {
            notch?.send(.requestOpen(tab: "timer"))
        }
    }

    private func stopTicker() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func postActivity() {
        let leading = AnyView(TimerActivityRing(model: self))
        let trailing = AnyView(TimerActivityText(model: self))
        activities?.post(
            LiveActivity(
                id: Self.activityID, priority: 80, expiresAt: nil,
                extraWidth: 40, leading: leading, trailing: trailing))
    }
}

struct TimerActivityText: View {
    let model: TimerModel

    var body: some View {
        Text(TimerModel.format(model.remaining))
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(model.tint)
            .contentTransition(.numericText(countsDown: true))
            .lineLimit(1)
    }
}

struct TimerActivityRing: View {
    let model: TimerModel

    var body: some View {
        ZStack {
            Circle().stroke(model.tint.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(model.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: model.progress)
            if model.pomodoro && model.phase.isBreak {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(model.tint)
            }
        }
        .frame(width: 15, height: 15)
    }
}
