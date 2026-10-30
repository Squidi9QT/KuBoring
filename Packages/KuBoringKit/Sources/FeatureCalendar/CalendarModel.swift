import SwiftUI
import Observation
import EventKit
import KuBoringCore

enum CalendarKeys {
    static let hidden = SettingKey<[String]>("feature.calendar.hidden", default: [])
    static let showAllDay = SettingKey<Bool>("feature.calendar.showAllDay", default: true)
    static let meetingCountdown = SettingKey<Bool>("feature.calendar.meetingCountdown", default: true)
    static let meetingLead = SettingKey<Int>("feature.calendar.meetingLead", default: 5)
}

struct CalendarItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let meetingURL: URL?
}

enum MeetingLink {
    private static let hosts = [
        "zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "telemost.yandex.ru", "telemost.360.yandex.ru", "webex.com", "whereby.com", "meet.jit.si",
        "facetime.apple.com", "discord.gg", "discord.com", "skype.com", "around.co", "gotomeeting.com",
        "bluejeans.com", "ktalk.ru", "salutejazz.ru", "jazz.sber.ru",
    ]

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func find(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isMeeting(url) { return url }
        for text in [location, notes].compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                if let link = match.url, isMeeting(link) { return link }
            }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let source: String
    let color: Color
}

enum CalendarAccess {
    case notDetermined, granted, denied
}

@MainActor @Observable
final class CalendarModel {
    let settings: SettingsStore

    private(set) var access: CalendarAccess = .notDetermined
    private(set) var today: [CalendarItem] = []
    private(set) var tomorrow: [CalendarItem] = []
    private(set) var calendars: [CalendarInfo] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let activities: ActivityCenter?
    @ObservationIgnored private let notch: NotchController?
    @ObservationIgnored private var meetingTask: Task<Void, Never>?
    @ObservationIgnored private var loadedDay = Calendar.current.startOfDay(for: Date())
    @ObservationIgnored private var postedMeetingID: String?

    static let meetingActivityID = "calendar.meeting"

    init(settings: SettingsStore, activities: ActivityCenter? = nil, notch: NotchController? = nil) {
        self.settings = settings
        self.activities = activities
        self.notch = notch
    }

    func start() {
        refreshAccess()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    func shutdown() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        meetingTask?.cancel()
        meetingTask = nil
        clearMeetingActivity()
    }

    // MARK: Отсчёт до созвона

    private func nextMeeting(now: Date) -> CalendarItem? {
        (today + tomorrow)
            .filter { $0.meetingURL != nil && !$0.isAllDay && $0.end > now }
            .min { $0.start < $1.start }
    }

    func restartMeetingWatch() {
        meetingTask?.cancel()
        meetingTask = nil
        guard activities != nil, access == .granted, settings[CalendarKeys.meetingCountdown] else {
            clearMeetingActivity()
            return
        }
        meetingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                if Calendar.current.startOfDay(for: now) != self.loadedDay {
                    self.reload()
                    return
                }
                let lead = TimeInterval(max(1, self.settings[CalendarKeys.meetingLead]) * 60)
                let wait: TimeInterval
                if let meeting = self.nextMeeting(now: now) {
                    let showFrom = meeting.start.addingTimeInterval(-lead)
                    let showUntil = min(meeting.end, meeting.start.addingTimeInterval(5 * 60))
                    if now >= showFrom && now < showUntil {
                        self.postMeeting(meeting)
                        wait = showUntil.timeIntervalSince(now)
                    } else {
                        self.clearMeetingActivity()
                        wait = now < showFrom ? showFrom.timeIntervalSince(now) : 60
                    }
                } else {
                    self.clearMeetingActivity()
                    wait = 15 * 60
                }
                try? await Task.sleep(for: .seconds(min(max(1, wait), 15 * 60)))
            }
        }
    }

    private func postMeeting(_ meeting: CalendarItem) {
        guard let activities, postedMeetingID != meeting.id else { return }
        postedMeetingID = meeting.id
        let open: () -> Void = { [weak self] in self?.notch?.send(.requestOpen(tab: "calendar")) }
        activities.post(
            LiveActivity(
                id: Self.meetingActivityID,
                priority: 85,
                extraWidth: 58,
                leading: AnyView(
                    Image(systemName: "video.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: open)
                        .help(meeting.title)
                ),
                trailing: AnyView(MeetingCountdown(start: meeting.start).onTapGesture(perform: open))
            ))
    }

    private func clearMeetingActivity() {
        guard postedMeetingID != nil else { return }
        postedMeetingID = nil
        activities?.remove(id: Self.meetingActivityID)
    }

    private func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            access = .granted
        case .notDetermined:
            access = .notDetermined
        case .denied, .restricted, .writeOnly:
            access = .denied
        @unknown default:
            access = .denied
        }
    }

    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            refreshAccess()
            if granted { reload() }
        }
    }

    func isVisible(_ calendarID: String) -> Bool {
        !settings[CalendarKeys.hidden].contains(calendarID)
    }

    func setVisible(_ calendarID: String, _ visible: Bool) {
        var hidden = settings[CalendarKeys.hidden]
        hidden.removeAll { $0 == calendarID }
        if !visible { hidden.append(calendarID) }
        settings[CalendarKeys.hidden] = hidden
        reload()
    }

    func reload() {
        refreshAccess()
        guard access == .granted else {
            today = []
            tomorrow = []
            calendars = []
            restartMeetingWatch()
            return
        }
        let all = store.calendars(for: .event)
        calendars =
            all
            .map {
                CalendarInfo(
                    id: $0.calendarIdentifier, title: $0.title,
                    source: $0.source?.title ?? "", color: Color(cgColor: $0.cgColor))
            }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }

        let hidden = Set(settings[CalendarKeys.hidden])
        let visible = all.filter { !hidden.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else {
            today = []
            tomorrow = []
            restartMeetingWatch()
            return
        }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        guard let dayMid = cal.date(byAdding: .day, value: 1, to: dayStart),
            let dayEnd = cal.date(byAdding: .day, value: 2, to: dayStart)
        else { return }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: visible)
        let showAllDay = settings[CalendarKeys.showAllDay]
        let events = store.events(matching: predicate)
            .filter { showAllDay || !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        func items(_ lo: Date, _ hi: Date, _ tag: String) -> [CalendarItem] {
            events
                .filter { $0.startDate < hi && $0.endDate > lo }
                .map { event in
                    CalendarItem(
                        id:
                            "\(event.eventIdentifier ?? event.title ?? "e")-\(event.startDate.timeIntervalSince1970)-\(tag)",
                        title: (event.title?.isEmpty == false ? event.title : nil) ?? "Без названия",
                        start: event.startDate,
                        end: event.endDate,
                        isAllDay: event.isAllDay,
                        color: Color(cgColor: event.calendar.cgColor),
                        meetingURL: event.isAllDay
                            ? nil
                            : MeetingLink.find(url: event.url, location: event.location, notes: event.notes))
                }
        }
        today = items(dayStart, dayMid, "t")
        tomorrow = items(dayMid, dayEnd, "n")
        loadedDay = dayStart
        restartMeetingWatch()
    }
}

struct MeetingCountdown: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            Text(label(now: ctx.date))
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func label(now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? "сейчас" : "\(minutes) мин"
    }
}
