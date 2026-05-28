import Foundation

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let accountID: String?
    let accountEmail: String?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        accountID: String? = nil,
        accountEmail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.accountID = accountID
        self.accountEmail = accountEmail
    }
}

protocol CalendarSourceProvider: AnyObject {
    func fetchUpcomingEvents() async throws -> [CalendarEvent]
}
