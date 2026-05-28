import Combine
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var controller: AppController
    @State private var now = Date()

    private let menuClock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            accountSection

            if controller.hasGoogleAccess {
                Divider()
                nextAlarmsSection
            }

            Divider()

            Button {
                controller.openPlanner()
            } label: {
                Label("Day planner", systemImage: "calendar")
            }
            .buttonStyle(.plain)
            .disabled(!controller.hasGoogleAccess)

            Divider()

            reminderLeadSection

            Divider()

            // Speed picker — how long the plane takes to cross the screen
            VStack(alignment: .leading, spacing: 4) {
                Text("Plane speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("Plane speed", selection: $controller.flightDuration) {
                    Text("Slow").tag(AppController.slowSpeed)
                    Text("Normal").tag(AppController.normalSpeed)
                    Text("Fast").tag(AppController.fastSpeed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            Button {
                controller.testAirplane()
            } label: {
                Label("Test airplane", systemImage: "airplane")
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                controller.deleteAllLocalData()
            } label: {
                Label("Delete all local data", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit MeetingReminder", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 320)
        .onReceive(menuClock) { tick in
            now = tick
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.hasGoogleAccess {
                Label(accountSummary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Google Calendar not connected", systemImage: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }

            if controller.googleAccounts.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(controller.googleAccounts) { account in
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                            Text(account.displayName)
                                .font(.system(size: 12))
                                .lineLimit(1)

                            Spacer(minLength: 6)

                            Button {
                                controller.removeGoogleAccount(account)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Remove account")
                        }
                    }
                }
            }

            Button {
                controller.connectGoogle()
            } label: {
                Label(connectButtonTitle, systemImage: "person.crop.circle.badge.plus")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isConnectingGoogle)

            if controller.googleAccounts.count > 1 {
                Button {
                    controller.disconnectAllGoogleAccounts()
                } label: {
                    Label("Remove all accounts", systemImage: "person.crop.circle.badge.minus")
                }
                .buttonStyle(.plain)
            }

            if let authError = controller.authError {
                Text(authError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reminderLeadSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reminder lead time")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Picker("Reminder lead time", selection: $controller.reminderLeadMinutes) {
                ForEach(AppController.reminderLeadMinuteOptions, id: \.self) { minutes in
                    Text("\(minutes)m").tag(minutes)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var accountSummary: String {
        let count = controller.googleAccounts.count
        return count == 1 ? "1 Google account connected" : "\(count) Google accounts connected"
    }

    private var connectButtonTitle: String {
        if controller.isConnectingGoogle { return "Connecting..." }
        return controller.hasGoogleAccess ? "Connect another account" : "Connect Google"
    }

    private var nextAlarmsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Next alarms")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Button {
                    controller.refreshCalendarData()
                } label: {
                    Label(controller.isRefreshingCalendar ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(controller.isRefreshingCalendar)
            }

            let alarms = controller.nextReminderAlarms(now: now)
            if alarms.isEmpty {
                Label(controller.isRefreshingCalendar ? "Refreshing calendar" : "No upcoming enabled alarms", systemImage: controller.isRefreshingCalendar ? "arrow.clockwise" : "bell.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(alarms) { alarm in
                        NextAlarmRow(alarm: alarm, now: now)
                    }
                }
            }

            if let error = controller.calendarRefreshError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(refreshStatusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var refreshStatusText: String {
        let intervalMinutes = Int(AppController.calendarRefreshInterval / 60)
        if controller.isRefreshingCalendar {
            return "Refreshing calendar now"
        }
        if let date = controller.lastCalendarRefreshDate {
            return "Last refreshed \(date.formatted(.dateTime.hour().minute())) · every \(intervalMinutes) min"
        }
        return "Refreshes on launch and every \(intervalMinutes) min"
    }
}

private struct NextAlarmRow: View {
    let alarm: ReminderAlarm
    let now: Date

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(triggerSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var triggerSummary: String {
        var parts = [relativeTriggerText, "starts \(timeText(for: alarm.event.startDate))"]
        if let accountEmail = alarm.event.accountEmail, accountEmail.isEmpty == false {
            parts.append(accountEmail)
        }
        return parts.joined(separator: " · ")
    }

    private var relativeTriggerText: String {
        let seconds = alarm.triggerDate.timeIntervalSince(now)
        if seconds <= 0 {
            return "Triggering now"
        }

        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 {
            return "In \(minutes) min"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "In \(hours) hr"
        }

        return alarm.triggerDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func timeText(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

struct DayPlannerView: View {
    @EnvironmentObject var controller: AppController

    private let refreshTimer = Timer.publish(every: AppController.calendarRefreshInterval, on: .main, in: .common).autoconnect()
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            weekStrip
            Divider()
            content
        }
        .frame(minWidth: 560, minHeight: 460)
        .onAppear {
            controller.refreshPlannerEvents()
        }
        .onReceive(refreshTimer) { _ in
            controller.refreshPlannerEvents()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                controller.movePlannerDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous day")

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.plannerDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.system(size: 18, weight: .semibold))
                Text(lastUpdatedLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                controller.refreshPlannerEvents()
            } label: {
                Image(systemName: controller.isLoadingPlannerEvents ? "arrow.clockwise.circle" : "arrow.clockwise")
            }
            .disabled(controller.isLoadingPlannerEvents || !controller.hasGoogleAccess)
            .help("Refresh")

            Button("Today") {
                controller.showTodayInPlanner()
            }
            .disabled(calendar.isDateInToday(controller.plannerDate))

            Button {
                controller.movePlannerDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next day")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { day in
                Button {
                    controller.showPlannerDate(day)
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(calendar.isDate(day, inSameDayAs: controller.plannerDate) ? .primary : .secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(dayBackground(for: day))
                }
                .buttonStyle(.plain)
                .help(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if !controller.hasGoogleAccess {
            emptyState(systemImage: "person.crop.circle.badge.exclamationmark", title: "Google Calendar not connected")
        } else if controller.isLoadingPlannerEvents && controller.plannerEvents.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading events")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = controller.plannerError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                Button("Retry") {
                    controller.refreshPlannerEvents()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.plannerEvents.isEmpty {
            emptyState(systemImage: "calendar", title: "No timed events")
        } else {
            List(controller.plannerEvents) { event in
                DayPlannerEventRow(event: event)
                    .environmentObject(controller)
            }
            .listStyle(.inset)
        }
    }

    private var weekDates: [Date] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: controller.plannerDate)
        let start = interval?.start ?? controller.plannerDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var lastUpdatedLabel: String {
        if controller.isLoadingPlannerEvents { return "Refreshing" }
        let count = controller.plannerEvents.count
        return count == 1 ? "1 event" : "\(count) events"
    }

    private func dayBackground(for day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: controller.plannerDate)
        let today = calendar.isDateInToday(day)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(today ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
    }

    private func emptyState(systemImage: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DayPlannerEventRow: View {
    @EnvironmentObject var controller: AppController
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: reminderBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(timeRange)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 5)
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { controller.isReminderEnabled(for: event) },
            set: { controller.setReminderEnabled($0, for: event) }
        )
    }

    private var timeRange: String {
        let start = event.startDate.formatted(.dateTime.hour().minute())
        let end = event.endDate.formatted(.dateTime.hour().minute())
        if let accountEmail = event.accountEmail, accountEmail.isEmpty == false {
            return "\(start) - \(end) · \(accountEmail)"
        }
        return "\(start) - \(end)"
    }
}

#Preview {
    DayPlannerView()
        .environmentObject(AppController())
}
