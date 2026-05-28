import Foundation

@MainActor
final class CalendarPoller {
    /// How many minutes before a meeting to fire the alert.
    static let alertMinutesBefore = 5
    /// Trigger when remaining minutes fall in [alertMinutesBefore - 1, alertMinutesBefore + 1].
    private static let alertWindowLow  = TimeInterval((alertMinutesBefore - 1) * 60)
    private static let alertWindowHigh = TimeInterval((alertMinutesBefore + 1) * 60)

    var onMeetingSoon: ((CalendarEvent, Int) -> Void)?
    var shouldNotify: (CalendarEvent) -> Bool = { _ in true }

    private let eventsProvider: () -> [CalendarEvent]
    private var timer: Timer?
    // Persists across poll cycles so we don't fire the same alert twice
    private var notifiedIDs: Set<String> = []

    init(eventsProvider: @escaping () -> [CalendarEvent]) {
        self.eventsProvider = eventsProvider
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

        for event in events {
            let secondsUntilStart = event.startDate.timeIntervalSince(now)
            guard secondsUntilStart >= Self.alertWindowLow,
                  secondsUntilStart <= Self.alertWindowHigh,
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
