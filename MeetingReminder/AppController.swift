import Foundation
import AppKit
import Combine

// Central coordinator: owns Google OAuth + calendar polling, and triggers the airplane.
@MainActor
final class AppController: ObservableObject {
    @Published var hasGoogleAccess: Bool = false
    @Published var googleEmail: String?
    @Published var isConnectingGoogle: Bool = false
    @Published var authError: String?
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

    init() {
        let oauthService = GoogleOAuthService()
        self.googleOAuthService = oauthService
        self.googleCalendarService = GoogleCalendarService(oauthService: oauthService) {
            GoogleOAuthConfig.credentials
        }

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
}
