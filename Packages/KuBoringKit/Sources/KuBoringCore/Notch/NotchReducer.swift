import Foundation

public enum NotchPhase: Equatable, Sendable { case closed, peeking, open, dragging }

public enum NotchEvent: Equatable, Sendable {
    case pointerEntered, pointerExited
    case openDelayElapsed, closeDelayElapsed
    case clicked, clickedOutside
    case dragEntered, dragExited, dropped
    case requestOpen(tab: String?)
    case requestClose
    case selectTab(String)
}

public struct NotchState: Equatable, Sendable {
    public var phase: NotchPhase
    public var selectedTab: String?
    public var holdOpen: Set<String>
    public var openedByDrag: Bool

    public init(phase: NotchPhase = .closed, selectedTab: String? = nil,
                holdOpen: Set<String> = [], openedByDrag: Bool = false) {
        self.phase = phase
        self.selectedTab = selectedTab
        self.holdOpen = holdOpen
        self.openedByDrag = openedByDrag
    }
}

public enum NotchEffect: Equatable, Sendable { case scheduleOpen, scheduleClose, cancelTimers }

/// Чистая функция переходов состояния шторки.
public enum NotchReducer {
    public static func reduce(_ state: inout NotchState, _ event: NotchEvent,
                              openOnHover: Bool, dropTab: String?) -> [NotchEffect] {
        switch event {
        case .pointerEntered:
            switch state.phase {
            case .closed:
                guard openOnHover else { return [] }
                state.phase = .peeking
                return [.scheduleOpen]
            case .open:
                return [.cancelTimers]   // вернулись, пока ждали закрытия
            case .peeking, .dragging:
                return []
            }

        case .pointerExited:
            switch state.phase {
            case .peeking:
                state.phase = .closed
                return [.cancelTimers]
            case .open:
                return state.holdOpen.isEmpty ? [.scheduleClose] : []
            case .closed, .dragging:
                return []
            }

        case .openDelayElapsed:
            guard state.phase == .peeking else { return [] }
            state.phase = .open
            return []

        case .closeDelayElapsed:
            // Причина удержания могла появиться, пока шёл таймер.
            guard state.phase == .open, state.holdOpen.isEmpty else { return [] }
            close(&state)
            return []

        case .clicked:
            guard state.phase == .closed || state.phase == .peeking else { return [] }
            state.phase = .open
            return [.cancelTimers]

        case .clickedOutside:
            guard state.phase == .open else { return [] }
            close(&state)
            return [.cancelTimers]

        case .dragEntered:
            switch state.phase {
            case .closed, .peeking:
                state.phase = .dragging
                state.openedByDrag = true
                if let dropTab { state.selectedTab = dropTab }
                return [.cancelTimers]
            case .open:
                return [.cancelTimers]   // вкладка не меняется
            case .dragging:
                return []
            }

        case .dragExited:
            guard state.phase == .dragging else { return [] }
            close(&state)
            return [.cancelTimers]

        case .dropped:
            guard state.phase == .dragging else { return [] }
            state.phase = .open
            if let dropTab { state.selectedTab = dropTab }
            return [.cancelTimers]

        case .requestOpen(let tab):
            state.phase = .open
            if let tab { state.selectedTab = tab }
            return [.cancelTimers]

        case .requestClose:
            close(&state)
            return [.cancelTimers]

        case .selectTab(let id):
            state.selectedTab = id
            return []
        }
    }

    private static func close(_ state: inout NotchState) {
        state.phase = .closed
        state.openedByDrag = false
    }
}
