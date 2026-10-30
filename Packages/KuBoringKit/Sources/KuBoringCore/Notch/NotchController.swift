import SwiftUI
import Observation

@MainActor public protocol NotchDropHandler: AnyObject {
    func handleDrop(_ urls: [URL])
}

@MainActor @Observable
public final class NotchController {
    public private(set) var state: NotchState
    public var dropTabID: String?
    public var dragInside = false
    public var dropHover = false
    public var dragLocation: CGPoint?
    public private(set) var keyboardFocusRequest = 0
    public var batteryPanelOpen = false
    @ObservationIgnored public private(set) var lastClosedAt: Date?
    @ObservationIgnored public weak var dropHandler: NotchDropHandler?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?

    public init(settings: SettingsStore) {
        self.settings = settings
        var initial = NotchState()
        if settings[CoreKeys.rememberLastTab] {
            let last = settings[CoreKeys.lastTab]
            if !last.isEmpty { initial.selectedTab = last }
        }
        self.state = initial
    }

    public func send(_ event: NotchEvent) {
        let geometry = settings[CoreKeys.geometry]
        var next = state
        let effects = NotchReducer.reduce(
            &next, event,
            openOnHover: geometry.openOnHover,
            dropTab: dropTabID)
        if state.phase == .open, next.phase != .open { lastClosedAt = Date() }
        if batteryPanelOpen, next.phase != .open || next.selectedTab != state.selectedTab {
            batteryPanelOpen = false
        }
        if next != state { state = next }
        if settings[CoreKeys.rememberLastTab], let tab = next.selectedTab,
            settings[CoreKeys.lastTab] != tab {
            settings[CoreKeys.lastTab] = tab
        }
        for effect in effects { perform(effect, geometry: geometry) }
    }

    public func requestKeyboardFocus() {
        keyboardFocusRequest &+= 1
    }

    public func hold(_ reason: String, _ on: Bool) {
        var next = state
        if on { next.holdOpen.insert(reason) } else { next.holdOpen.remove(reason) }
        if next != state { state = next }
    }

    private func perform(_ effect: NotchEffect, geometry: NotchGeometry) {
        switch effect {
        case .scheduleOpen:
            openTask?.cancel()
            let delay = max(0, geometry.openDelay)
            openTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.send(.openDelayElapsed)
            }
        case .scheduleClose:
            closeTask?.cancel()
            let delay = max(0, geometry.closeDelay)
            closeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.send(.closeDelayElapsed)
            }
        case .cancelTimers:
            openTask?.cancel()
            closeTask?.cancel()
            openTask = nil
            closeTask = nil
        }
    }
}
