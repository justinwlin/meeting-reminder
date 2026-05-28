import Combine
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if controller.hasGoogleAccess {
                    Label(controller.googleEmail ?? "Google Calendar connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Google Calendar not connected", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }

                if let authError = controller.authError {
                    Text(authError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if controller.hasGoogleAccess {
                Button {
                    controller.disconnectGoogle()
                } label: {
                    Label("Disconnect Google", systemImage: "person.crop.circle.badge.minus")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    controller.connectGoogle()
                } label: {
                    Label(controller.isConnectingGoogle ? "Connecting..." : "Connect Google", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isConnectingGoogle)
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
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit MeetingReminder", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 260)
    }
}

struct DayPlannerView: View {
    @EnvironmentObject var controller: AppController

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
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
        return "\(start) - \(end)"
    }
}

#Preview {
    DayPlannerView()
        .environmentObject(AppController())
}
