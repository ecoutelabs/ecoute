import Foundation

protocol ScrobbleClient {
    func scrobble(sessionKey: String, track: Track, album: Album, startDate: Date) async
}

extension LastFMClient: ScrobbleClient {}

struct ScrobbleService {
    let client: ScrobbleClient

    func scrobbleIfNeeded(sessionKey: String?, track: Track, album: Album, startDate: Date, elapsed: TimeInterval, listenedTime: TimeInterval) -> Bool {
        guard track.duration > 30 else { return false }
        guard let sessionKey else { return false }

        let threshold = min(track.duration * 0.5, 240)
        guard listenedTime >= threshold else { return false }

        Task {
            await client.scrobble(sessionKey: sessionKey, track: track, album: album, startDate: startDate)
        }
        return true
    }
}
