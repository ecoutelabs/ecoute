import Foundation

/// Fetches genre data for albums from MusicBrainz (preferred) with a Last.fm fallback.
/// Results are persisted to a local cache so network requests only happen once per album.
struct GenreFetcher {
    let lastFMAPIKey: String
    private let session: URLSession

    private static let userAgent = "LocalAlbumPlayer/1.0 (macOS; scrobbler)"

    init(lastFMAPIKey: String, session: URLSession = .shared) {
        self.lastFMAPIKey = lastFMAPIKey
        self.session = session
    }

    /// Returns a map of album ID → genres for all provided albums.
    /// MusicBrainz requests are serialised at 1/sec; Last.fm fallbacks run concurrently.
    func fetchGenres(for albums: [Album]) async -> [UUID: [String]] {
        var cache = loadCache()
        var result: [UUID: [String]] = [:]
        var needsMusicBrainz: [Album] = []
        var needsLastFM: [Album] = []

        for album in albums {
            let lfmKey = lastFMCacheKey(for: album)
            if let mbid = album.musicBrainzReleaseGroupID {
                let mbKey = "mb:\(mbid)"
                if let cached = cache[mbKey] {
                    // MB result cached (may be empty — fall through to cached LFM result)
                    if !cached.isEmpty {
                        result[album.id] = cached
                    } else if let lfm = cache[lfmKey], !lfm.isEmpty {
                        result[album.id] = lfm
                    }
                } else {
                    needsMusicBrainz.append(album)
                }
            } else {
                if let cached = cache[lfmKey] {
                    if !cached.isEmpty { result[album.id] = cached }
                } else {
                    needsLastFM.append(album)
                }
            }
        }

        print("[GenreFetcher] \(albums.count) albums: \(needsMusicBrainz.count) via MusicBrainz, \(needsLastFM.count) via Last.fm, \(result.count) from cache")

        // MusicBrainz: serial with 1.1s delay between requests
        var mbFound = 0
        for (i, album) in needsMusicBrainz.enumerated() {
            if i > 0 {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
            }
            guard let mbid = album.musicBrainzReleaseGroupID else { continue }
            let mbKey = "mb:\(mbid)"
            if let genres = await fetchMusicBrainzGenres(mbid: mbid) {
                cache[mbKey] = genres
                if !genres.isEmpty {
                    result[album.id] = genres
                    mbFound += 1
                }
                // MB returned empty — leave album ungenred, skip Last.fm
            }
            // Network/parse failure — don't cache, skip Last.fm
        }
        if !needsMusicBrainz.isEmpty {
            print("[GenreFetcher] MusicBrainz done: \(mbFound)/\(needsMusicBrainz.count) had genres")
        }

        // Last.fm: concurrent
        var lfmFound = 0
        await withTaskGroup(of: (UUID, [String], String)?.self) { group in
            for album in needsLastFM {
                let key = lastFMCacheKey(for: album)
                group.addTask {
                    let genres = await self.fetchLastFMTags(artist: album.artist, album: album.title) ?? []
                    return (album.id, genres, key)
                }
            }
            for await item in group {
                guard let (id, genres, key) = item else { continue }
                cache[key] = genres  // cache even if empty to avoid retrying
                if !genres.isEmpty {
                    result[id] = genres
                    lfmFound += 1
                }
            }
        }
        if !needsLastFM.isEmpty {
            print("[GenreFetcher] Last.fm done: \(lfmFound)/\(needsLastFM.count) had genres")
        }

        print("[GenreFetcher] Total albums with genres: \(result.count)/\(albums.count)")
        saveCache(cache)
        return result
    }

    // MARK: - MusicBrainz

    private func fetchMusicBrainzGenres(mbid: String) async -> [String]? {
        guard let url = URL(string: "https://musicbrainz.org/ws/2/release-group/\(mbid)?inc=genres&fmt=json") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("[GenreFetcher] MusicBrainz HTTP \(http.statusCode) for mbid \(mbid)")
                return nil
            }
            let decoded = try JSONDecoder().decode(MusicBrainzResponse.self, from: data)
            return (decoded.genres ?? [])
                .sorted { $0.count > $1.count }
                .map { $0.name.lowercased() }
        } catch {
            print("[GenreFetcher] MusicBrainz error for \(mbid): \(error)")
            return nil
        }
    }

    private struct MusicBrainzResponse: Decodable {
        struct Genre: Decodable {
            let name: String
            let count: Int
        }
        let genres: [Genre]?
    }

    // MARK: - Last.fm

    private func fetchLastFMTags(artist: String, album: String) async -> [String]? {
        guard !lastFMAPIKey.isEmpty else { return nil }
        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")
        components?.queryItems = [
            URLQueryItem(name: "method", value: "album.getTopTags"),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "album", value: album),
            URLQueryItem(name: "api_key", value: lastFMAPIKey),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("[GenreFetcher] Last.fm HTTP \(http.statusCode) for \(artist) — \(album)")
                return nil
            }
            // Last.fm returns {"error": N, "message": "..."} when album is not found — treat as a miss, not an error.
            if let apiError = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data), apiError.error > 0 {
                return nil
            }
            let decoded = try JSONDecoder().decode(LastFMTagsResponse.self, from: data)
            return decoded.toptags.tag.prefix(3).map { $0.name.lowercased() }
        } catch {
            print("[GenreFetcher] Last.fm decode error for \(artist) — \(album): \(error)")
            return nil
        }
    }

    private struct LastFMErrorResponse: Decodable {
        let error: Int
    }

    private struct LastFMTagsResponse: Decodable {
        struct TopTags: Decodable {
            // Last.fm returns a single object instead of a 1-element array when there is only one tag.
            let tag: [Tag]

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let tags = try? container.decode([Tag].self, forKey: .tag) {
                    tag = tags
                } else if let single = try? container.decode(Tag.self, forKey: .tag) {
                    tag = [single]
                } else {
                    tag = []
                }
            }

            private enum CodingKeys: String, CodingKey { case tag }
        }
        struct Tag: Decodable {
            let name: String
            let count: Int
        }
        let toptags: TopTags
    }

    // MARK: - Cache

    private func lastFMCacheKey(for album: Album) -> String {
        "lfm:\(album.artist):\(album.title)"
    }

    private func cacheFileURL() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("LocalAlbumLibraryCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("genres.json")
    }

    private func loadCache() -> [String: [String]] {
        guard let url = cacheFileURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveCache(_ cache: [String: [String]]) {
        guard let url = cacheFileURL(),
              let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url)
    }
}
