import Foundation
import AppKit
import Combine
import SwiftUI

// Central coordinator: owns Google OAuth + calendar polling, and triggers the airplane.
@MainActor
final class AppController: ObservableObject {
    private static let disabledReminderEventIDsKey = "disabledReminderEventIDs"

    @Published var hasGoogleAccess: Bool = false
    @Published var googleEmail: String?
    @Published var isConnectingGoogle: Bool = false
    @Published var authError: String?
    @Published var plannerDate: Date
    @Published var plannerEvents: [CalendarEvent] = []
    @Published var isLoadingPlannerEvents: Bool = false
    @Published var plannerError: String?
    @Published private(set) var disabledReminderEventIDs: Set<String>
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
    private var overlayWindows: [AirplaneOverlayWindow] = []
    private var plannerWindow: NSWindow?
    private var plannerWindowDelegate: PlannerWindowDelegate?

    init() {
        let oauthService = GoogleOAuthService()
        self.googleOAuthService = oauthService
        self.googleCalendarService = GoogleCalendarService(oauthService: oauthService) {
            GoogleOAuthConfig.credentials
        }
        self.plannerDate = Calendar.current.startOfDay(for: Date())
        self.disabledReminderEventIDs = Set(UserDefaults.standard.stringArray(forKey: Self.disabledReminderEventIDsKey) ?? [])

        let saved = UserDefaults.standard.double(forKey: "flightDuration")
        self.flightDuration = saved > 0 ? saved : Self.normalSpeed

        hasGoogleAccess = oauthService.hasCredential
        googleEmail = oauthService.currentEmail
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
                let credential = try await googleOAuthService.signIn(credentials: credentials)
                updateUI {
                    self.googleEmail = credential.email
                    self.hasGoogleAccess = true
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

    func disconnectGoogle() {
        updateUI {
            self.poller?.stop()
            self.poller = nil
            self.googleOAuthService.signOut()
            self.hasGoogleAccess = false
            self.googleEmail = nil
            self.authError = nil
            self.plannerEvents = []
            self.plannerError = nil
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
            self.plannerDate = Calendar.current.startOfDay(for: date)
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

    func refreshPlannerEvents() {
        guard hasGoogleAccess else { return }
        let date = plannerDate
        updateUI {
            self.isLoadingPlannerEvents = true
            self.plannerError = nil
        }

        Task {
            do {
                let events = try await googleCalendarService.fetchEvents(on: date)
                updateUI {
                    guard Calendar.current.isDate(self.plannerDate, inSameDayAs: date) else { return }
                    self.plannerEvents = events
                    self.isLoadingPlannerEvents = false
                }
            } catch {
                updateUI {
                    guard Calendar.current.isDate(self.plannerDate, inSameDayAs: date) else { return }
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

    /// Manual trigger — shows the airplane immediately with a fake meeting.
    func testAirplane() {
        let fake = CalendarEvent(
            id:        UUID().uuidString,
            title:     "Test Meeting",
            startDate: Date().addingTimeInterval(300),
            endDate:   Date().addingTimeInterval(1800)
        )
        showAirplane(for: fake, minutesUntil: 5)
    }

    // MARK: Private

    private func startPollingIfReady() {
        poller?.stop()
        poller = nil
        guard hasGoogleAccess else { return }

        let p = CalendarPoller(service: googleCalendarService)
        p.onMeetingSoon = { [weak self] event, minutes in
            self?.showAirplane(for: event, minutesUntil: minutes)
        }
        p.shouldNotify = { [weak self] event in
            self?.isReminderEnabled(for: event) ?? true
        }
        p.start()
        poller = p
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
