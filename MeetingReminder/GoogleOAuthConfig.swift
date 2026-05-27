import Foundation

struct GoogleOAuthClientCredentials {
    let clientID: String
    let clientSecret: String?
}

enum GoogleOAuthConfig {
    private static let bundledCredentialName = "GoogleOAuthCredentials"

    static var credentials: GoogleOAuthClientCredentials? {
        guard let installed = credential?.installed,
              let clientID = installed.clientID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        return GoogleOAuthClientCredentials(
            clientID: clientID,
            clientSecret: installed.clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    static var configuredClientID: String? {
        credentials?.clientID
    }

    static var configuredClientSecret: String? {
        credentials?.clientSecret
    }

    private static var credential: GoogleOAuthCredentialFile? {
        guard let url = Bundle.main.url(forResource: bundledCredentialName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(GoogleOAuthCredentialFile.self, from: data)
    }
}

private struct GoogleOAuthCredentialFile: Decodable {
    let installed: InstalledCredential
}

private struct InstalledCredential: Decodable {
    let clientID: String
    let clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
