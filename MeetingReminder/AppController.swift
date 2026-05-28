import Foundation
import AppKit
import Combine
import SwiftUI

struct ReminderAlarm: Identifiable {
    let event: CalendarEvent
    let triggerDate: Date

    var id: String { event.id }
}

// Central coordinator: owns Google OAuth + calendar polling, and triggers the airplane.
@MainActor
final class AppController: ObservableObject {
    private static let disabledReminderEventIDsKey = "disabledReminderEventIDs"
    private static let reminderLeadMinutesKey = "reminderLeadMinutes"
    static let calendarRefreshInterval: TimeInterval = 600
    static let reminderLeadMinuteOptions = [1, 3, 5, 10, 15, 30]
    private static let upcomingEventWindow: TimeInterval = 7 * 86_400
    private static let reminderTriggerGraceInterval: TimeInterval = 60

    var hasGoogleAccess: Bool { !googleAccounts.isEmpty }

    @Published private(set) var googleAccounts: [ConnectedGoogleAccount] = []
    @Published var isConnectingGoogle: Bool = false
    @Published var authError: String?
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var isRefreshingCalendar: Bool = false
    @Published private(set) var calendarRefreshError: String?
    @Published private(set) var lastCalendarRefreshDate: Date?
    @Published var plannerDate: Date
    @Published var plannerEvents: [CalendarEvent] = []
    @Published var isLoadingPlannerEvents: Bool = false
    @Published var plannerError: String?
    @Published private(set) var disabledReminderEventIDs: Set<String>
    @Published var reminderLeadMinutes: Int {
        didSet {
            UserDefaults.standard.set(reminderLeadMinutes, forKey: Self.reminderLeadMinutesKey)
            poller?.checkNow()
        }
    }
    @Published var flightDuration: Double {
        didSet { UserDefaults.standard.set(flightDuration, forKey: "flightDuration") }
    }

    /// Preset speeds (seconds for the plane to cross the screen).
    static let slowSpeed:   Double = 22
    static let normalSpeed: Double = 14
    static let fastSpeed:   Double = 8

    private let googleOAuthService: GoogleOAuthService
    private let googleCalendarService: GoogleCalendarService
    private var poller: CalendarPoller?
    private var calendarRefreshTimer: Timer?
    private var overlayWindows: [AirplaneOverlayWindow] = []
    private var plannerWindow: NSWindow?
    private var plannerWindowDelegate: PlannerWindowDelegate?
    private var calendarRefreshGeneration = 0
    private var plannerRefreshGeneration = 0

    init() {
        let oauthService = GoogleOAuthService()
        self.googleOAuthService = oauthService
        self.googleCalendarService = GoogleCalendarService(oauthService: oauthService) {
            GoogleOAuthConfig.credentials
        }
        self.plannerDate = Calendar.current.startOfDay(for: Date())
        self.disabledReminderEventIDs = Set(UserDefaults.standard.stringArray(forKey: Self.disabledReminderEventIDsKey) ?? [])

        let savedLead = UserDefaults.standard.object(forKey: Self.reminderLeadMinutesKey) as? Int
        self.reminderLeadMinutes = max(1, savedLead ?? CalendarPoller.defaultAlertMinutesBefore)

        let saved = UserDefaults.standard.double(forKey: "flightDuration")
        self.flightDuration = saved > 0 ? saved : Self.normalSpeed

        googleAccounts = oauthService.connectedAccounts
        startPollingIfReady()
    }

    // MARK: Public

    func connectGoogle() {
        guard let credentials = GoogleOAuthConfig.credentials else {
            updateUI {
                self.authError = "Google OAuth credentials are not bundled with the app."
            }
            return
        }

        Task {
            updateUI {
                self.isConnectingGoogle = true
                self.authError = nil
            }

            do {
                _ = try await googleOAuthService.signIn(credentials: credentials)
                updateUI {
                    self.reloadGoogleAccounts()
                    self.resetCalendarData()
                    self.startPollingIfReady()
                    self.refreshPlannerEvents()
                }
            } catch {
                updateUI {
                    self.authError = error.localizedDescription
                }
            }

            updateUI {
                self.isConnectingGoogle = false
            }
        }
    }

    func removeGoogleAccount(_ account: ConnectedGoogleAccount) {
        updateUI {
            self.googleOAuthService.signOut(accountID: account.id)
            self.reloadGoogleAccounts()
            self.resetCalendarData()
            self.authError = nil
            if self.hasGoogleAccess {
                self.startPollingIfReady()
                self.refreshPlannerEvents()
            } else {
                self.stopPolling()
            }
        }
    }

    func disconnectAllGoogleAccounts() {
        updateUI {
            self.googleOAuthService.signOutAll()
            self.reloadGoogleAccounts()
            self.stopPolling()
            self.resetCalendarData()
            self.authError = nil
        }
    }

    func openPlanner() {
        if let plannerWindow {
            plannerWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            refreshPlannerEvents()
            return
        }

        let view = DayPlannerView()
            .environmentObject(self)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MeetingReminder"
        window.contentView = hostingView
        window.minSize = NSSize(width: 560, height: 460)
        window.isReleasedWhenClosed = false
        let delegate = PlannerWindowDelegate { [weak self] in
            self?.plannerWindow = nil
            self?.plannerWindowDelegate = nil
        }
        window.delegate = delegate
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        plannerWindow = window
        plannerWindowDelegate = delegate
        refreshPlannerEvents()
    }

    func showPlannerDate(_ date: Date) {
        updateUI {
            let nextDate = Calendar.current.startOfDay(for: date)
            let didChangeDay = !Calendar.current.isDate(self.plannerDate, inSameDayAs: nextDate)
            self.plannerDate = nextDate
            if didChangeDay {
                self.plannerRefreshGeneration += 1
                self.plannerEvents = []
                self.plannerError = nil
                self.isLoadingPlannerEvents = self.hasGoogleAccess
            }
            self.refreshPlannerEvents()
        }
    }

    func movePlannerDate(by days: Int) {
        let nextDate = Calendar.current.date(byAdding: .day, value: days, to: plannerDate) ?? plannerDate
        showPlannerDate(nextDate)
    }

    func showTodayInPlanner() {
        showPlannerDate(Date())
    }

    func refreshCalendarData() {
        refreshCalendarEvents()
        if plannerWindow != nil {
            refreshPlannerEvents()
        }
    }

    func refreshCalendarEvents() {
        guard hasGoogleAccess, !isRefreshingCalendar else { return }

        let start = Date()
        let end = start.addingTimeInterval(Self.upcomingEventWindow)
        let generation = calendarRefreshGeneration
        updateUI {
            self.isRefreshingCalendar = true
            self.calendarRefreshError = nil
        }

        Task {
            do {
                let events = try await googleCalendarService.fetchEvents(start: start, end: end)
                updateUI {
                    guard self.hasGoogleAccess, generation == self.calendarRefreshGeneration else { return }
                    self.upcomingEvents = events
                    self.lastCalendarRefreshDate = Date()
                    self.calendarRefreshError = nil
                    self.isRefreshingCalendar = false
                    self.poller?.checkNow()
                }
            } catch {
                updateUI {
                    guard self.hasGoogleAccess, generation == self.calendarRefreshGeneration else { return }
                    self.calendarRefreshError = error.localizedDescription
                    self.isRefreshingCalendar = false
                }
            }
        }
    }

    func refreshPlannerEvents() {
        guard hasGoogleAccess else { return }
        let date = plannerDate
        let generation = plannerRefreshGeneration
        updateUI {
            self.isLoadingPlannerEvents = true
            self.plannerError = nil
        }

        Task {
            do {
                let events = try await googleCalendarService.fetchEvents(on: date)
                updateUI {
                    guard generation == self.plannerRefreshGeneration,
                          Calendar.current.isDate(self.plannerDate, inSameDayAs: date) else { return }
                    self.plannerEvents = events
                    self.isLoadingPlannerEvents = false
                }
            } catch {
                updateUI {
                    guard generation == self.plannerRefreshGeneration,
                          Calendar.current.isDate(self.plannerDate, inSameDayAs: date) else { return }
                    self.plannerEvents = []
                    self.plannerError = error.localizedDescription
                    self.isLoadingPlannerEvents = false
                }
            }
        }
    }

    func isReminderEnabled(for event: CalendarEvent) -> Bool {
        !disabledReminderEventIDs.contains(event.id)
    }

    func setReminderEnabled(_ enabled: Bool, for event: CalendarEvent) {
        updateUI {
            if enabled {
                self.disabledReminderEventIDs.remove(event.id)
            } else {
                self.disabledReminderEventIDs.insert(event.id)
            }
            self.persistDisabledReminderEventIDs()
        }
    }

    func nextReminderAlarms(now: Date = Date(), limit: Int = 3) -> [ReminderAlarm] {
        let earliestVisibleTrigger = now.addingTimeInterval(-Self.reminderTriggerGraceInterval)
        return Array(upcomingEvents.compactMap { event in
            guard isReminderEnabled(for: event),
                  event.endDate > now,
                  poller?.hasNotified(eventID: event.id) != true else {
                return nil
            }

            let triggerDate = event.startDate.addingTimeInterval(TimeInterval(-reminderLeadMinutes * 60))
            guard triggerDate >= earliestVisibleTrigger else { return nil }
            return ReminderAlarm(event: event, triggerDate: triggerDate)
        }
        .sorted { $0.triggerDate < $1.triggerDate }
        .prefix(limit))
    }

    /// Manual trigger — shows the airplane immediately with a fake meeting.
    func testAirplane() {
        let fake = CalendarEvent(
            id:        UUID().uuidString,
            title:     "Test Meeting",
            startDate: Date().addingTimeInterval(TimeInterval(reminderLeadMinutes * 60)),
            endDate:   Date().addingTimeInterval(1800)
        )
        showAirplane(for: fake, minutesUntil: reminderLeadMinutes)
    }

    // MARK: Private

    private func reloadGoogleAccounts() {
        googleAccounts = googleOAuthService.connectedAccounts
    }

    private func resetCalendarData() {
        calendarRefreshGeneration += 1
        plannerRefreshGeneration += 1
        upcomingEvents = []
        calendarRefreshError = nil
        lastCalendarRefreshDate = nil
        isRefreshingCalendar = false
        plannerEvents = []
        plannerError = nil
        isLoadingPlannerEvents = false
    }

    private func stopPolling() {
        poller?.stop()
        poller = nil
        calendarRefreshTimer?.invalidate()
        calendarRefreshTimer = nil
    }

    private func startPollingIfReady() {
        stopPolling()
        guard hasGoogleAccess else { return }

        let p = CalendarPoller(
            eventsProvider: { [weak self] in
                self?.upcomingEvents ?? []
            },
            alertMinutesBeforeProvider: { [weak self] in
                self?.reminderLeadMinutes ?? CalendarPoller.defaultAlertMinutesBefore
            }
        )
        p.onMeetingSoon = { [weak self] event, minutes in
            self?.showAirplane(for: event, minutesUntil: minutes)
        }
        p.shouldNotify = { [weak self] event in
            self?.isReminderEnabled(for: event) ?? true
        }
        p.start()
        poller = p

        refreshCalendarEvents()
        calendarRefreshTimer = Timer.scheduledTimer(withTimeInterval: Self.calendarRefreshInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshCalendarEvents()
            }
        }
    }

    private func showAirplane(for event: CalendarEvent, minutesUntil: Int) {
        let duration = flightDuration
        DispatchQueue.main.async {
            let window = AirplaneOverlayWindow(
                meetingTitle:   event.title,
                minutesUntil:   minutesUntil,
                flightDuration: duration
            )
            window.orderFrontRegardless()
            self.overlayWindows.append(window)

            // Release shortly after the animation finishes (fade-out is 0.6s)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.5) {
                self.overlayWindows.removeAll { $0 === window }
                window.close()
            }
        }
    }

    private func updateUI(_ updates: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            updates()
        }
    }

    private func persistDisabledReminderEventIDs() {
        UserDefaults.standard.set(Array(disabledReminderEventIDs), forKey: Self.disabledReminderEventIDsKey)
    }
}

private final class PlannerWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            onClose()
        }
    }
}
