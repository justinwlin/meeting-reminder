import Foundation

final class GoogleCalendarService: CalendarSourceProvider {
    private let oauthService: GoogleOAuthService
    private let credentialsProvider: () -> GoogleOAuthClientCredentials?
    private let isoFormatter = ISO8601DateFormatter()

    init(oauthService: GoogleOAuthService, credentialsProvider: @escaping () -> GoogleOAuthClientCredentials?) {
        self.oauthService = oauthService
        self.credentialsProvider = credentialsProvider
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func fetchUpcomingEvents() async throws -> [CalendarEvent] {
        guard let credentials = credentialsProvider() else {
            throw GoogleOAuthError.missingClientID
        }

        let accessToken = try await oauthService.accessToken(credentials: credentials)
        let calendars = try await fetchCalendars(accessToken: accessToken)
        let now = Date()
        let oneHourLater = now.addingTimeInterval(3_600)

        var events: [CalendarEvent] = []
        for calendar in calendars {
            let calendarEvents = try await fetchEvents(
                calendarID: calendar.id,
                calendarSummary: calendar.summary,
                accessToken: accessToken,
                start: now,
                end: oneHourLater
            )
            events.append(contentsOf: calendarEvents)
        }

        return events.sorted { $0.startDate < $1.startDate }
    }

    private func fetchCalendars(accessToken: String) async throws -> [GoogleCalendarListEntry] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        components.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "showHidden", value: "false")
        ]

        let response = try await authorizedGET(GoogleCalendarListResponse.self, url: components.url!, accessToken: accessToken)
        let visibleCalendars = response.items.filter { entry in
            entry.hidden != true && (entry.selected == true || entry.primary == true)
        }

        return visibleCalendars.isEmpty ? response.items.filter { $0.primary == true } : visibleCalendars
    }

    private func fetchEvents(
        calendarID: String,
        calendarSummary: String,
        accessToken: String,
        start: Date,
        end: Date
    ) async throws -> [CalendarEvent] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = "/calendar/v3/calendars/\(Self.pathEscaped(calendarID))/events"
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: Self.rfc3339String(from: start)),
            URLQueryItem(name: "timeMax", value: Self.rfc3339String(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "showDeleted", value: "false")
        ]

        let response = try await authorizedGET(GoogleEventsResponse.self, url: components.url!, accessToken: accessToken)
        return response.items.compactMap { event in
            guard event.status != "cancelled",
                  event.transparency != "transparent",
                  event.selfAttendeeResponseStatus != "declined",
                  let startDate = event.start.dateTimeValue(using: isoFormatter),
                  let endDate = event.end.dateTimeValue(using: isoFormatter) else {
                return nil
            }

            return CalendarEvent(
                id: "\(calendarID):\(event.id)",
                title: bannerTitle(for: event, fallbackCalendarName: calendarSummary),
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    private func authorizedGET<T: Decodable>(_ type: T.Type, url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw GoogleCalendarError.httpError(status: status, body: body)
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func bannerTitle(for event: GoogleEvent, fallbackCalendarName: String) -> String {
        if let summary = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        return fallbackCalendarName.isEmpty ? "Untitled Meeting" : fallbackCalendarName
    }

    private static func rfc3339String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func pathEscaped(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendarListEntry]
}

private struct GoogleCalendarListEntry: Decodable {
    let id: String
    let summary: String
    let selected: Bool?
    let primary: Bool?
    let hidden: Bool?
}

private struct GoogleEventsResponse: Decodable {
    let items: [GoogleEvent]
}

private struct GoogleEvent: Decodable {
    let id: String
    let summary: String?
    let status: String?
    let transparency: String?
    let start: GoogleEventDate
    let end: GoogleEventDate
    let attendees: [GoogleEventAttendee]?

    var selfAttendeeResponseStatus: String? {
        attendees?.first(where: { $0.selfAttendee == true })?.responseStatus
    }
}

private struct GoogleEventDate: Decodable {
    let dateTime: String?
    let date: String?

    func dateTimeValue(using formatter: ISO8601DateFormatter) -> Date? {
        guard let dateTime else { return nil }
        return formatter.date(from: dateTime) ?? ISO8601DateFormatter().date(from: dateTime)
    }
}

private struct GoogleEventAttendee: Decodable {
    let responseStatus: String?
    let selfAttendee: Bool?

    enum CodingKeys: String, CodingKey {
        case responseStatus
        case selfAttendee = "self"
    }
}

enum GoogleCalendarError: LocalizedError {
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let status, let body):
            return "Google Calendar returned HTTP \(status): \(body)"
        }
    }
}
