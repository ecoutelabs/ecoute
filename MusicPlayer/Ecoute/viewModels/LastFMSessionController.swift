import Foundation
import Combine

@MainActor
final class LastFMSessionController: ObservableObject {
    @Published private(set) var username: String?
    @Published private(set) var status: String = "Not linked"
    @Published private(set) var isPending: Bool = false

    private let client: LastFMClient
    private var sessionKey: String?
    private var pendingToken: String? {
        didSet { isPending = pendingToken != nil }
    }

    init(client: LastFMClient) {
        self.client = client
    }

    func loadSession() {
        if let session = KeychainHelper.load(key: "lastfm_session") {
            sessionKey = session
            username = UserDefaults.standard.string(forKey: "lastfm_username")
            if let user = username {
                status = "Linked as \(user)"
            } else {
                status = "Linked"
            }
        }
    }

    func startAuth() {
        Task {
            do {
                let token = try await client.beginAuthFlow()
                await MainActor.run {
                    self.pendingToken = token
                    self.status = "Authorize in browser, then click Complete."
                }
            } catch {
                await MainActor.run {
                    self.status = "Auth failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func completeAuth() {
        guard let token = pendingToken else {
            status = "No pending token. Start link again."
            return
        }
        Task {
            do {
                let session = try await client.completeAuth(token: token)
                store(sessionKey: session.key, username: session.username)
                await MainActor.run {
                    self.username = session.username
                    self.status = "Linked as \(session.username)"
                    self.pendingToken = nil
                }
            } catch {
                await MainActor.run {
                    self.status = "Link failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func unlink() {
        deleteSession()
        username = nil
        sessionKey = nil
        status = "Not linked"
        pendingToken = nil
    }

    func currentSessionKey() -> String? {
        sessionKey
    }

    func _testSetSessionKey(_ key: String?) {
        sessionKey = key
    }

    // MARK: - Persistence

    private func store(sessionKey: String, username: String) {
        self.sessionKey = sessionKey
        self.username = username
        status = "Linked as \(username)"
        KeychainHelper.save(key: "lastfm_session", value: sessionKey)
        UserDefaults.standard.set(username, forKey: "lastfm_username")
    }

    private func deleteSession() {
        KeychainHelper.delete(key: "lastfm_session")
        UserDefaults.standard.removeObject(forKey: "lastfm_username")
    }
}
