import Foundation

@MainActor
final class CalendarPoller {
    /// How many minutes before a meeting to fire the alert.
    static let defaultAlertMinutesBefore = 5

    var onMeetingSoon: ((CalendarEvent, Int) -> Void)?
    var shouldNotify: (CalendarEvent) -> Bool = { _ in true }

    private let eventsProvider: () -> [CalendarEvent]
    private let alertMinutesBeforeProvider: () -> Int
    private var timer: Timer?
    // Persists across poll cycles so we don't fire the same alert twice
    private var notifiedIDs: Set<String> = []

    init(
        eventsProvider: @escaping () -> [CalendarEvent],
        alertMinutesBeforeProvider: @escaping () -> Int
    ) {
        self.eventsProvider = eventsProvider
        self.alertMinutesBeforeProvider = alertMinutesBeforeProvider
    }

    func start() {
        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            DispatchQueue.main.async { [weak self] in self?.checkNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func checkNow() {
        let events = eventsProvider()
        let now = Date()
        let alertMinutesBefore = max(0, alertMinutesBeforeProvider())
        let alertSecondsBefore = TimeInterval(alertMinutesBefore * 60)
        let alertWindowLow = max(0, alertSecondsBefore - 60)
        let alertWindowHigh = alertSecondsBefore + 60

        for event in events {
            let secondsUntilStart = event.startDate.timeIntervalSince(now)
            guard secondsUntilStart >= alertWindowLow,
                  secondsUntilStart <= alertWindowHigh,
                  shouldNotify(event),
                  !notifiedIDs.contains(event.id) else { continue }

            notifiedIDs.insert(event.id)
            let minutes = max(0, Int((secondsUntilStart / 60).rounded()))
            onMeetingSoon?(event, minutes)
        }
    }

    func hasNotified(eventID: String) -> Bool {
        notifiedIDs.contains(eventID)
    }
}
