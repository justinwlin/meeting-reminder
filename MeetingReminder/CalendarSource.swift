import Foundation

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let accountID: String?
    let accountEmail: String?
    /// Google Meet (or other video) link for the event, if it has one.
    let meetURL: URL?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        accountID: String? = nil,
        accountEmail: String? = nil,
        meetURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.accountID = accountID
        self.accountEmail = accountEmail
        self.meetURL = meetURL
    }

    /// True when the event's link is a Google Meet room (as opposed to another video provider).
    var hasGoogleMeetLink: Bool {
        meetURL.map(CalendarEvent.isGoogleMeetURL) ?? false
    }

    static func isGoogleMeetURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "meet.google.com"
    }
}

protocol CalendarSourceProvider: AnyObject {
    func fetchUpcomingEvents() async throws -> [CalendarEvent]
}
