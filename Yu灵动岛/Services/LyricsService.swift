import Foundation

/// Result of a lyrics lookup. Loading is represented by AppState before the
/// request starts; this result describes the finished lookup.
enum LyricsFetchResult: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case notFound
    case failed
}

/// Fetches lyrics from LRCLIB (https://lrclib.net) — a free, no-key, no-login
/// community lyrics database. It works for streaming (Apple Music, Spotify) as
/// well as local files because it matches on track/artist/album/duration rather
/// than needing a local .lrc file.
///
/// Privacy: only the track title, artist, album, and duration are sent — never
/// any user identity or local data. Results are cached in-memory per track.
actor LyricsService {
    static let shared = LyricsService()
    private init() {}

    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    /// Cache keyed by the normalized track identity so re-hovering the same song
    /// doesn't re-hit the network.
    private var cache: [String: LyricsFetchResult] = [:]
    private var inFlight: Task<LyricsFetchResult, Never>?
    private var inFlightKey: String?

    private func key(title: String, artist: String) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// Fetches lyrics for a track. Returns synced lines when available, then
    /// plain lyrics as fallback, then notFound/failed for empty/error states.
    func fetch(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        forceRefresh: Bool = false
    ) async -> LyricsFetchResult {
        guard !title.isEmpty else { return .notFound }

        let cacheKey = key(title: title, artist: artist)
        if !forceRefresh, let cached = cache[cacheKey] { return cached }

        inFlight?.cancel()
        let task = Task<LyricsFetchResult, Never> {
            await Self.requestLyrics(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
        }
        inFlight = task
        inFlightKey = cacheKey
        let result = await task.value
        cache[cacheKey] = result
        if inFlightKey == cacheKey {
            inFlight = nil
            inFlightKey = nil
        }
        return result
    }

    private static func requestLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> LyricsFetchResult {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        guard let url = components.url else { return .failed }

        var request = URLRequest(url: url)
        // LRCLIB asks clients to identify themselves via User-Agent.
        request.setValue(
            "YuLingDongDao (https://github.com/yuxi/YuLingDongDao)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .notFound
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed
            }
            let resp = try JSONDecoder().decode(Response.self, from: data)
            if let synced = resp.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lines = LRCParser.parse(synced)
                return lines.isEmpty ? .notFound : .synced(lines)
            }
            if let plain = resp.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .plain(plain)
            }
            return .notFound
        } catch is CancellationError {
            return .failed
        } catch {
            return .failed
        }
    }
}
