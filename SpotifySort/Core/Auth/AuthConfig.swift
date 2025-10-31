import Foundation

public struct AuthConfig {
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]

    public init(clientID: String, redirectURI: String, scopes: [String]) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }
}

public extension AuthConfig {
    static let spotifyDefault = AuthConfig(
        clientID: "0473bcc9a68e491e9b5882ec8ec335ac",
        redirectURI: "spotifysort://callback",
        scopes: [
            "playlist-read-private",
            "playlist-modify-public",
            "playlist-modify-private",
            "user-read-email",
            "user-library-read",
            "user-library-modify"
        ]
    )
}
