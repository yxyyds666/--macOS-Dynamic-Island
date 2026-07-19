import Foundation

/// Result of a lyrics lookup. Providers are tried in order; synced lyrics win,
/// while plain lyrics are retained as a last-resort fallback.
enum LyricsFetchResult: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case notFound
    case failed
}

private protocol LyricsProvider: Sendable {
    func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsFetchResult
}

/// Aggregates Chinese music providers before falling back to LRCLIB. The
/// providers use public client endpoints and never send account credentials.
actor LyricsService {
    static let shared = LyricsService()
    private init() {}

    private var cache: [String: LyricsFetchResult] = [:]
    private var inFlight: Task<LyricsFetchResult, Never>?
    private var inFlightKey: String?

    func fetch(title: String, artist: String, album: String, duration: TimeInterval, forceRefresh: Bool = false) async -> LyricsFetchResult {
        let title = clean(title)
        let artist = clean(artist)
        let album = clean(album)
        guard !title.isEmpty else { return .notFound }

        let key = "\(normalize(title))|\(normalize(artist))|\(normalize(album))|\(duration > 0 ? Int(duration.rounded()) / 5 : 0)"
        if !forceRefresh, let cached = cache[key] { return cached }
        if !forceRefresh, inFlightKey == key, let inFlight { return await inFlight.value }

        inFlight?.cancel()
        let task = Task<LyricsFetchResult, Never> {
            await Self.lookup(title: title, artist: artist, album: album, duration: duration)
        }
        inFlight = task
        inFlightKey = key
        let result = await task.value
        if inFlightKey == key {
            inFlight = nil
            inFlightKey = nil
        }
        if !isTransientFailure(result) { cache[key] = result }
        return result
    }

    private static func lookup(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsFetchResult {
        let providers: [any LyricsProvider] = [
            NetEaseLyricsProvider(),
            QQMusicLyricsProvider(),
            KugouLyricsProvider(),
            LRCLIBLyricsProvider()
        ]
        var plain: String?
        var hadFailure = false
        for provider in providers {
            switch await provider.fetch(title: title, artist: artist, album: album, duration: duration) {
            case .synced(let lines) where !lines.isEmpty: return .synced(lines)
            case .plain(let text) where plain == nil: plain = text
            case .failed: hadFailure = true
            default: break
            }
        }
        if let plain { return .plain(plain) }
        return hadFailure ? .failed : .notFound
    }

    private func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ value: String) -> String { clean(value).lowercased() }
    private func isTransientFailure(_ result: LyricsFetchResult) -> Bool { if case .failed = result { return true }; return false }
}

private struct NetEaseLyricsProvider: LyricsProvider {
    private struct SearchResponse: Decodable { let result: SearchResult? }
    private struct SearchResult: Decodable { let songs: [Song]? }
    private struct Song: Decodable { let id: Int; let name: String; let artists: [Artist]?; let duration: Int? }
    private struct Artist: Decodable { let name: String }
    private struct LyricResponse: Decodable { let lrc: LyricText?; let tlyric: LyricText? }
    private struct LyricText: Decodable { let lyric: String? }

    func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsFetchResult {
        var components = URLComponents(string: "https://music.163.com/api/cloudsearch/pc")!
        components.queryItems = [URLQueryItem(name: "s", value: "\(title) \(artist)"), URLQueryItem(name: "type", value: "1"), URLQueryItem(name: "limit", value: "8")]
        guard let url = components.url, let data = await LyricsHTTP.get(url), let search = try? JSONDecoder().decode(SearchResponse.self, from: data), let songs = search.result?.songs else { return .notFound }
        let song = songs.min { score($0, title: title, artist: artist, duration: duration) > score($1, title: title, artist: artist, duration: duration) }
        guard let song else { return .notFound }
        var lyricURL = URLComponents(string: "https://music.163.com/api/song/lyric")!
        lyricURL.queryItems = [URLQueryItem(name: "id", value: String(song.id)), URLQueryItem(name: "lv", value: "1"), URLQueryItem(name: "kv", value: "1"), URLQueryItem(name: "tv", value: "1")]
        guard let url = lyricURL.url, let data = await LyricsHTTP.get(url), let response = try? JSONDecoder().decode(LyricResponse.self, from: data) else { return .notFound }
        return LyricsHTTP.result(synced: response.lrc?.lyric, plain: response.tlyric?.lyric)
    }

    private func score(_ song: Song, title: String, artist: String, duration: TimeInterval) -> Double {
        let name = song.name.lowercased(); let target = title.lowercased(); let names = song.artists?.map { $0.name.lowercased() } ?? []
        var score = name == target ? 4.0 : (name.contains(target) || target.contains(name) ? 2 : 0)
        if names.contains(artist.lowercased()) { score += 3 }
        if let d = song.duration, duration > 0 { score += max(0, 2 - abs(Double(d) / 1000 - duration) / 30) }
        return score
    }
}

private struct QQMusicLyricsProvider: LyricsProvider {
    private struct SearchResponse: Decodable { let data: SearchData? }
    private struct SearchData: Decodable { let song: Songs? }
    private struct Songs: Decodable { let list: [Song]? }
    private struct Song: Decodable { let songmid: String?; let songname: String?; let singer: [Singer]?; let interval: Int? }
    private struct Singer: Decodable { let name: String? }
    private struct LyricResponse: Decodable { let lyric: String? }

    func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsFetchResult {
        var search = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
        search.queryItems = [URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "p", value: "1"), URLQueryItem(name: "n", value: "8"), URLQueryItem(name: "w", value: "\(title) \(artist)")]
        guard let url = search.url, let data = await LyricsHTTP.get(url), let response = try? JSONDecoder().decode(SearchResponse.self, from: data), let songs = response.data?.song?.list else { return .notFound }
        let song = songs.min { score($0, title: title, artist: artist, duration: duration) > score($1, title: title, artist: artist, duration: duration) }
        guard let mid = song?.songmid else { return .notFound }
        var lyric = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        lyric.queryItems = [URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "songmid", value: mid), URLQueryItem(name: "nobase64", value: "1")]
        guard let lyricURL = lyric.url, let data = await LyricsHTTP.get(lyricURL), let response = LyricsHTTP.decodeJSONP(LyricResponse.self, data: data) else { return .notFound }
        return LyricsHTTP.result(synced: response.lyric, plain: response.lyric)
    }

    private func score(_ song: Song, title: String, artist: String, duration: TimeInterval) -> Double {
        var score = song.songname?.lowercased() == title.lowercased() ? 4.0 : 1.0
        if song.singer?.contains(where: { $0.name?.lowercased() == artist.lowercased() }) == true { score += 3 }
        if let interval = song.interval, duration > 0 { score += max(0, 2 - abs(Double(interval) - duration) / 30) }
        return score
    }
}

private struct KugouLyricsProvider: LyricsProvider {
    private struct SearchResponse: Decodable { let data: SearchData? }
    private struct SearchData: Decodable { let info: [Song]? }
    private struct Song: Decodable { let songname: String?; let singername: String?; let duration: Int?; let hash: String? }
    private struct LyricResponse: Decodable { let data: LyricData? }
    private struct LyricData: Decodable { let lyrics: String?; let lyricsContent: String? }

    func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsFetchResult {
        var search = URLComponents(string: "https://songsearch.kugou.com/song_search_v2")!
        search.queryItems = [URLQueryItem(name: "keyword", value: "\(title) \(artist)"), URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "pagesize", value: "8")]
        guard let url = search.url, let data = await LyricsHTTP.get(url), let response = try? JSONDecoder().decode(SearchResponse.self, from: data), let songs = response.data?.info else { return .notFound }
        let song = songs.min { score($0, title: title, artist: artist, duration: duration) > score($1, title: title, artist: artist, duration: duration) }
        guard let hash = song?.hash else { return .notFound }
        var lyric = URLComponents(string: "https://www.kugou.com/yy/index.php?r=play/getdata")!
        lyric.queryItems = [URLQueryItem(name: "hash", value: hash)]
        guard let lyricURL = lyric.url, let data = await LyricsHTTP.get(lyricURL), let response = try? JSONDecoder().decode(LyricResponse.self, from: data), let text = response.data?.lyrics ?? response.data?.lyricsContent else { return .notFound }
        return LyricsHTTP.result(synced: text, plain: text)
    }

    private func score(_ song: Song, title: String, artist: String, duration: TimeInterval) -> Double {
        var score = song.songname?.lowercased() == title.lowercased() ? 4.0 : 1.0
        if song.singername?.lowercased().contains(artist.lowercased()) == true { score += 3 }
        if let d = song.duration, duration > 0 { score += max(0, 2 - abs(Double(d) - duration) / 30) }
        return score
    }
}

private struct LRCLIBLyricsProvider: LyricsProvider {
    func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> LyricsFetchResult {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if (1...3600).contains(duration) { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        get.queryItems = items
        if let url = get.url,
           let data = await LyricsHTTP.get(url),
           let response = try? JSONDecoder().decode(LRCLIBResponse.self, from: data) {
            return LyricsHTTP.result(synced: response.syncedLyrics, plain: response.plainLyrics)
        }
        return .notFound
    }
    private struct LRCLIBResponse: Decodable { let syncedLyrics: String?; let plainLyrics: String? }
}

private enum LyricsHTTP {
    static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url); request.timeoutInterval = 8; request.setValue("YuLingDongDao/1.0", forHTTPHeaderField: "User-Agent")
        do { let (data, response) = try await URLSession.shared.data(for: request); guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else { return nil }; return data } catch { return nil }
    }

    static func decodeJSONP<T: Decodable>(_ type: T.Type, data: Data) -> T? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let json = text.replacingOccurrences(of: #"^\w+\("#, with: "", options: .regularExpression).replacingOccurrences(of: #"\);?$"#, with: "", options: .regularExpression)
        guard let jsonData = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: jsonData)
    }

    static func result(synced: String?, plain: String?) -> LyricsFetchResult {
        if let synced, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = LRCParser.parse(synced); if !lines.isEmpty { return .synced(lines) }
        }
        if let plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(plain) }
        return .notFound
    }
}
