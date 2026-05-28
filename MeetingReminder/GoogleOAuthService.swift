import AppKit
import CryptoKit
import Foundation
import Security

struct GoogleOAuthCredential: Codable {
    var accountID: String?
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var tokenType: String
    var scope: String?
    var idToken: String?
    var email: String?

    var isAccessTokenFresh: Bool {
        expiresAt > Date().addingTimeInterval(90)
    }
}

struct ConnectedGoogleAccount: Identifiable, Equatable {
    let id: String
    let email: String

    var displayName: String {
        email.isEmpty ? "Google Account" : email
    }
}

private protocol GoogleOAuthCredentialStoring {
    func saveAll(_ credentials: [GoogleOAuthCredential]) throws
    func loadAll() throws -> [GoogleOAuthCredential]
    func delete(accountID: String) throws
    func deleteAll() throws
}

final class GoogleOAuthService {
    private let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
    private let credentialStore: any GoogleOAuthCredentialStoring

    init() {
        self.credentialStore = FileGoogleOAuthCredentialStore()
    }

    var hasCredential: Bool {
        ((try? credentialStore.loadAll()) ?? []).isEmpty == false
    }

    var connectedAccounts: [ConnectedGoogleAccount] {
        ((try? credentialStore.loadAll()) ?? [])
            .map(Self.account(from:))
            .sorted { $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending }
    }

    func signIn(credentials: GoogleOAuthClientCredentials) async throws -> GoogleOAuthCredential {
        let cleanClientID = credentials.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanClientID.isEmpty else {
            throw GoogleOAuthError.missingClientID
        }

        let verifier = try Self.randomURLSafeString(byteCount: 32)
        let challenge = Self.codeChallenge(for: verifier)
        let state = try Self.randomURLSafeString(byteCount: 16)

        let redirectServer = LocalOAuthRedirectServer()
        let redirectURI = try await redirectServer.start()
        defer { redirectServer.stop() }

        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: cleanClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authorizationURL = components.url else {
            throw GoogleOAuthError.invalidAuthorizationURL
        }

        await MainActor.run {
            _ = NSWorkspace.shared.open(authorizationURL)
        }

        let callbackParams = try await redirectServer.waitForCallback()
        if let error = callbackParams["error"] {
            throw GoogleOAuthError.authorizationDenied(error)
        }
        guard callbackParams["state"] == state else {
            throw GoogleOAuthError.stateMismatch
        }
        guard let code = callbackParams["code"] else {
            throw GoogleOAuthError.missingAuthorizationCode
        }

        var credential = try await exchangeAuthorizationCode(
            code,
            credentials: credentials,
            codeVerifier: verifier,
            redirectURI: redirectURI.absoluteString
        )
        if let userInfo = try? await fetchUserInfo(accessToken: credential.accessToken) {
            credential.accountID = userInfo.sub ?? userInfo.email
            credential.email = userInfo.email
        }
        if credential.accountID == nil {
            credential.accountID = credential.email ?? UUID().uuidString
        }
        try storeAccount(credential)
        return credential
    }

    func accessToken(credentials: GoogleOAuthClientCredentials, accountID: String) async throws -> String {
        guard var credential = try credentialStore.loadAll().first(where: { Self.accountID(for: $0) == accountID }) else {
            throw GoogleOAuthError.notSignedIn
        }

        if credential.isAccessTokenFresh {
            return credential.accessToken
        }

        guard let refreshToken = credential.refreshToken else {
            throw GoogleOAuthError.missingRefreshToken
        }

        let refreshed = try await refreshAccessToken(
            credentials: credentials,
            refreshToken: refreshToken
        )
        credential.accessToken = refreshed.accessToken
        credential.expiresAt = refreshed.expiresAt
        credential.tokenType = refreshed.tokenType
        credential.scope = refreshed.scope ?? credential.scope
        credential.idToken = refreshed.idToken ?? credential.idToken
        if let newRefreshToken = refreshed.refreshToken {
            credential.refreshToken = newRefreshToken
        }

        try storeAccount(credential)
        return credential.accessToken
    }

    func signOut(accountID: String) {
        try? credentialStore.delete(accountID: accountID)
    }

    func signOutAll() {
        try? credentialStore.deleteAll()
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        credentials: GoogleOAuthClientCredentials,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> GoogleOAuthCredential {
        var items = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        if let clientSecret = credentials.clientSecret {
            items.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        return try await postTokenRequest(items)
    }

    private func refreshAccessToken(credentials: GoogleOAuthClientCredentials, refreshToken: String) async throws -> GoogleOAuthCredential {
        guard !credentials.clientID.isEmpty else {
            throw GoogleOAuthError.missingClientID
        }

        var items = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        if let clientSecret = credentials.clientSecret {
            items.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        return try await postTokenRequest(items)
    }

    private func postTokenRequest(_ items: [URLQueryItem]) async throws -> GoogleOAuthCredential {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(items)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        return GoogleOAuthCredential(
            accountID: nil,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3_600)),
            tokenType: tokenResponse.tokenType,
            scope: tokenResponse.scope,
            idToken: tokenResponse.idToken,
            email: nil
        )
    }

    private func fetchUserInfo(accessToken: String) async throws -> GoogleUserInfo {
        var request = URLRequest(url: userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)

        return try JSONDecoder().decode(GoogleUserInfo.self, from: data)
    }

    private func storeAccount(_ credential: GoogleOAuthCredential) throws {
        let accountID = Self.accountID(for: credential)
        var credentials = try credentialStore.loadAll()
        let matchingIndex = credentials.firstIndex(where: { Self.accountID(for: $0) == accountID })
            ?? credentials.firstIndex(where: { existing in
                guard let email = credential.email else { return false }
                return existing.email == email
            })

        if let index = matchingIndex {
            var updated = credential
            if updated.refreshToken == nil {
                updated.refreshToken = credentials[index].refreshToken
            }
            credentials[index] = updated
        } else {
            credentials.append(credential)
        }
        try credentialStore.saveAll(credentials)
    }

    private static func account(from credential: GoogleOAuthCredential) -> ConnectedGoogleAccount {
        ConnectedGoogleAccount(
            id: accountID(for: credential),
            email: credential.email ?? "Google Account"
        )
    }

    private static func accountID(for credential: GoogleOAuthCredential) -> String {
        credential.accountID ?? credential.email ?? "default"
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw GoogleOAuthError.randomGenerationFailed(status)
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formEncoded(_ items: [URLQueryItem]) -> Data {
        var components = URLComponents()
        components.queryItems = items
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw GoogleOAuthError.httpError(status: http.statusCode, body: body)
        }
    }
}

private struct FileGoogleOAuthCredentialStore: GoogleOAuthCredentialStoring {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func saveAll(_ credentials: [GoogleOAuthCredential]) throws {
        try createCredentialDirectory()
        let stored = StoredGoogleOAuthCredentials(version: 1, credentials: credentials)
        let data = try JSONEncoder().encode(stored)
        try data.write(to: credentialURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialURL.path
        )
    }

    func loadAll() throws -> [GoogleOAuthCredential] {
        guard fileManager.fileExists(atPath: credentialURL.path) else {
            return []
        }

        let data = try Data(contentsOf: credentialURL)
        if let stored = try? JSONDecoder().decode(StoredGoogleOAuthCredentials.self, from: data) {
            return stored.credentials.map(normalizedCredential)
        }

        let legacyCredential = try JSONDecoder().decode(GoogleOAuthCredential.self, from: data)
        return [normalizedCredential(legacyCredential)]
    }

    func delete(accountID: String) throws {
        var credentials = try loadAll()
        credentials.removeAll { normalizedAccountID(for: $0) == accountID }
        if credentials.isEmpty {
            try deleteAll()
        } else {
            try saveAll(credentials)
        }
    }

    func deleteAll() throws {
        guard fileManager.fileExists(atPath: credentialURL.path) else {
            return
        }

        try fileManager.removeItem(at: credentialURL)
    }

    private var credentialURL: URL {
        credentialDirectoryURL.appendingPathComponent("GoogleOAuthCredential.json")
    }

    private var credentialDirectoryURL: URL {
        if let appSupportURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return appSupportURL.appendingPathComponent("MeetingReminder", isDirectory: true)
        }

        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MeetingReminder", isDirectory: true)
    }

    private func createCredentialDirectory() throws {
        try fileManager.createDirectory(
            at: credentialDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func normalizedCredential(_ credential: GoogleOAuthCredential) -> GoogleOAuthCredential {
        var credential = credential
        if credential.accountID == nil {
            credential.accountID = credential.email ?? "default"
        }
        return credential
    }

    private func normalizedAccountID(for credential: GoogleOAuthCredential) -> String {
        credential.accountID ?? credential.email ?? "default"
    }
}

private struct StoredGoogleOAuthCredentials: Codable {
    let version: Int
    let credentials: [GoogleOAuthCredential]
}

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String
    let scope: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
        case idToken = "id_token"
    }
}

private struct GoogleUserInfo: Decodable {
    let sub: String?
    let email: String?
}

enum GoogleOAuthError: LocalizedError {
    case missingClientID
    case invalidAuthorizationURL
    case authorizationDenied(String)
    case stateMismatch
    case missingAuthorizationCode
    case missingRefreshToken
    case notSignedIn
    case randomGenerationFailed(OSStatus)
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Google OAuth desktop credentials are not configured."
        case .invalidAuthorizationURL:
            return "Could not build the Google authorization URL."
        case .authorizationDenied(let error):
            return "Google authorization failed: \(error)."
        case .stateMismatch:
            return "Google authorization returned an unexpected state value."
        case .missingAuthorizationCode:
            return "Google did not return an authorization code."
        case .missingRefreshToken:
            return "Google did not return a refresh token. Remove and reconnect this account."
        case .notSignedIn:
            return "Google Calendar is not connected."
        case .randomGenerationFailed(let status):
            return "Could not generate OAuth security bytes. Status: \(status)."
        case .httpError(let status, let body):
            return "Google returned HTTP \(status): \(body)"
        }
    }
}
