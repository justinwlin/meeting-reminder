import Foundation
import Network

final class LocalOAuthRedirectServer {
    private let queue = DispatchQueue(label: "MeetingReminder.OAuthRedirectServer")
    private var listener: NWListener?
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var callbackContinuation: CheckedContinuation<[String: String], Error>?
    private var pendingCallbackResult: Result<[String: String], Error>?

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation

            do {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleState(state)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: queue)
                self.listener = listener
            } catch {
                readyContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func waitForCallback() async throws -> [String: String] {
        if let pendingCallbackResult {
            self.pendingCallbackResult = nil
            return try pendingCallbackResult.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        readyContinuation = nil
        callbackContinuation = nil
        pendingCallbackResult = nil
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue,
                  let url = URL(string: "http://localhost:\(port)") else {
                readyContinuation?.resume(throwing: OAuthRedirectServerError.missingPort)
                readyContinuation = nil
                return
            }
            readyContinuation?.resume(returning: url)
            readyContinuation = nil
        case .failed(let error):
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
            finish(.failure(error))
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.finish(.failure(error))
                connection.cancel()
                return
            }

            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first,
                  let target = firstLine.split(separator: " ").dropFirst().first,
                  let components = URLComponents(string: "http://127.0.0.1\(target)") else {
                self.sendResponse(on: connection, status: "400 Bad Request", body: "Missing OAuth callback.")
                self.finish(.failure(OAuthRedirectServerError.invalidRequest))
                return
            }

            let pairs: [(String, String)] = (components.queryItems ?? []).compactMap { item in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
            let params = Dictionary(uniqueKeysWithValues: pairs)

            self.sendResponse(
                on: connection,
                status: "200 OK",
                body: "Google Calendar is connected. You can close this tab and return to MeetingReminder."
            )
            self.finish(.success(params))
        }
    }

    private func sendResponse(on connection: NWConnection, status: String, body: String) {
        let html = """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>MeetingReminder</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:3rem;">
        <h1>MeetingReminder</h1>
        <p>\(body)</p>
        </body>
        </html>
        """
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<[String: String], Error>) {
        if let callbackContinuation {
            self.callbackContinuation = nil
            callbackContinuation.resume(with: result)
        } else {
            pendingCallbackResult = result
        }
        listener?.cancel()
        listener = nil
    }
}

enum OAuthRedirectServerError: LocalizedError {
    case missingPort
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .missingPort:
            return "Could not start the local OAuth callback server."
        case .invalidRequest:
            return "The OAuth callback was not a valid HTTP request."
        }
    }
}
