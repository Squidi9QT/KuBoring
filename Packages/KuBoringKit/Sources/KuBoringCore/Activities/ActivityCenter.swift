import SwiftUI
import Observation

public struct LiveActivity: Identifiable {
    public let id: String
    public var priority: Int
    public var expiresAt: Date?
    public var leading: AnyView
    public var trailing: AnyView
    public var extraWidth: Double

    public init(
        id: String, priority: Int, expiresAt: Date? = nil, extraWidth: Double = 40,
        leading: AnyView, trailing: AnyView
    ) {
        self.id = id
        self.priority = priority
        self.expiresAt = expiresAt
        self.extraWidth = extraWidth
        self.leading = leading
        self.trailing = trailing
    }
}

@MainActor @Observable
public final class ActivityCenter {
    private var activities: [String: LiveActivity] = [:]
    @ObservationIgnored private var expiryTasks: [String: Task<Void, Never>] = [:]

    public init() {}

    public func post(_ activity: LiveActivity) {
        activities[activity.id] = activity
        expiryTasks[activity.id]?.cancel()
        expiryTasks[activity.id] = nil
        guard let expiresAt = activity.expiresAt else { return }
        let id = activity.id
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        expiryTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expire(id: id, expectedDate: expiresAt)
        }
    }

    public func remove(id: String) {
        activities[id] = nil
        expiryTasks[id]?.cancel()
        expiryTasks[id] = nil
    }

    public var current: LiveActivity? {
        let now = Date()
        return activities.values
            .filter { ($0.expiresAt ?? .distantFuture) > now }
            .max { $0.priority < $1.priority }
    }

    private func expire(id: String, expectedDate: Date) {
        guard let a = activities[id], a.expiresAt == expectedDate else { return }
        remove(id: id)
    }
}
