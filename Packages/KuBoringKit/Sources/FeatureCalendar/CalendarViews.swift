import SwiftUI
import AppKit
import KuBoringCore

private let ruLocale = Locale(identifier: "ru_RU")

struct CalendarTabView: View {
    let model: CalendarModel

    var body: some View {
        GeometryReader { geo in
            let k = AdaptiveMetrics(size: geo.size).scale
            layout(k: k)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .environment(\.locale, ruLocale)
        .onAppear { model.reload() }
    }

    private func layout(k: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 18 * k) {
            VStack(alignment: .leading, spacing: 2 * k) {
                Text(Date(), format: .dateTime.weekday(.wide))
                    .font(.system(size: 12 * k, weight: .semibold))
                    .foregroundStyle(.red)
                    .textCase(.uppercase)
                Text(Date(), format: .dateTime.day())
                    .font(.system(size: 44 * k, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                Text(Date(), format: .dateTime.month(.wide))
                    .font(.system(size: 13 * k))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 110 * k, alignment: .leading)

            content(k: k)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16 * k)
    }

    @ViewBuilder private func content(k: CGFloat) -> some View {
        switch model.access {
        case .notDetermined:
            message(
                "Нужен доступ к календарю, чтобы показывать события.", k: k,
                button: "Разрешить доступ"
            ) { model.requestAccess() }
        case .denied:
            message(
                "Доступ к календарю запрещён. Разрешите его в Системных настройках → Конфиденциальность → Календари.",
                k: k,
                button: "Открыть настройки"
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .granted:
            if model.today.isEmpty && model.tomorrow.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 26 * k))
                    Text("На сегодня и завтра событий нет")
                        .font(.system(size: 13 * k))
                }
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10 * k) {
                        section("Сегодня", model.today, k: k)
                        section("Завтра", model.tomorrow, k: k)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func message(_ text: String, k: CGFloat, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10 * k) {
            Text(text)
                .font(.system(size: 13 * k))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            Button(button, action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func section(_ title: String, _ items: [CalendarItem], k: CGFloat) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5 * k) {
                Text(title)
                    .font(.system(size: 11 * k, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                ForEach(items) { item in
                    CalendarRow(item: item, k: k)
                }
            }
        }
    }
}

struct CalendarRow: View {
    let item: CalendarItem
    var k: CGFloat = 1

    var body: some View {
        HStack(spacing: 8 * k) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.color)
                .frame(width: 4 * k, height: 28 * k)
            VStack(alignment: .leading, spacing: 1 * k) {
                Text(item.title)
                    .font(.system(size: 13 * k, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                timeText
                    .font(.system(size: 11 * k))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            if let url = item.meetingURL, item.end > Date() {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Войти", systemImage: "video.fill")
                        .font(.system(size: 11 * k, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9 * k)
                        .padding(.vertical, 4 * k)
                        .background(Capsule().fill(soon ? Color.accentColor : Color.white.opacity(0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(url.host ?? "Открыть созвон")
            }
        }
    }

    private var soon: Bool {
        let now = Date()
        return item.start.timeIntervalSince(now) < 10 * 60 && item.end > now
    }

    private var timeText: Text {
        if item.isAllDay {
            return Text("Весь день")
        }
        return Text(item.start, format: .dateTime.hour().minute())
            + Text(" – ")
            + Text(item.end, format: .dateTime.hour().minute())
    }
}

struct CalendarSettingsView: View {
    let model: CalendarModel

    var body: some View {
        Group {
            SettingsSection("События") {
                SettingsToggle(
                    "Показывать события на весь день",
                    hint: "Дни рождения, праздники и другие события без времени.",
                    isOn: Binding(
                        get: { model.settings[CalendarKeys.showAllDay] },
                        set: {
                            model.settings[CalendarKeys.showAllDay] = $0; model.reload()
                        }))
            }

            SettingsSection(
                "Созвоны",
                footer:
                    "Ссылки Zoom, Google Meet, Teams, Телемоста, Webex и др. ищутся в адресе, месте и заметках события."
            ) {
                SettingsToggle(
                    "Отсчёт до созвона в закрытой шторке",
                    hint: "Камера и «через 4 мин» рядом с вырезом; по клику откроется календарь с кнопкой «Войти».",
                    isOn: Binding(
                        get: { model.settings[CalendarKeys.meetingCountdown] },
                        set: {
                            model.settings[CalendarKeys.meetingCountdown] = $0; model.restartMeetingWatch()
                        }))
                SettingsPicker(
                    "Показывать за",
                    selection: Binding(
                        get: { model.settings[CalendarKeys.meetingLead] },
                        set: {
                            model.settings[CalendarKeys.meetingLead] = $0; model.restartMeetingWatch()
                        }),
                    options: [(1, "1 мин"), (5, "5 мин"), (10, "10 мин"), (15, "15 мин")]
                )
                .disabled(!model.settings[CalendarKeys.meetingCountdown])
            }

            SettingsSection("Календари", footer: "Отключите календари, события которых не нужны во вкладке.") {
                switch model.access {
                case .granted:
                    if model.calendars.isEmpty {
                        Text("Календари не найдены.").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.calendars) { info in
                            SettingsToggle(
                                info.title,
                                hint: info.source.isEmpty ? nil : info.source,
                                isOn: Binding(
                                    get: { model.isVisible(info.id) },
                                    set: { model.setVisible(info.id, $0) }))
                        }
                    }
                case .notDetermined:
                    HStack {
                        Text("Доступ к календарю ещё не выдан.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Разрешить доступ") { model.requestAccess() }
                    }
                case .denied:
                    Text("Доступ запрещён. Разрешите его в Системных настройках → Конфиденциальность → Календари.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
