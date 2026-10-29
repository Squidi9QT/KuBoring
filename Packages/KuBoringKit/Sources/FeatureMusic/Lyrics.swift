import Foundation

/// Строка синхронного текста: время начала (с) и текст.
struct LyricLine: Equatable {
    let time: Double
    let text: String
}

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    /// Текст без таймингов — показываем первые строки без подсветки.
    case plain([String])
    case instrumental
    case notFound
}

/// Тексты песен с lrclib.net (бесплатно, без ключа). Кэш в памяти на время работы приложения.
@MainActor
final class LyricsService {
    private var cache: [String: LyricsState] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "KuBoring (macOS notch app)"]
        return URLSession(configuration: config)
    }()

    static func key(title: String, artist: String) -> String {
        "\(artist.lowercased())|\(title.lowercased())"
    }

    func cached(title: String, artist: String) -> LyricsState? {
        cache[Self.key(title: title, artist: artist)]
    }

    func fetch(title: String, artist: String, album: String, duration: Double) async -> LyricsState {
        let key = Self.key(title: title, artist: artist)
        if let hit = cache[key] { return hit }
        var result = await get(title: title, artist: artist, album: album, duration: duration)
        if result == nil {
            result = await search(title: title, artist: artist)
        }
        let state = result ?? .notFound
        // Отменённый запрос (трек сменился) не кэшируем — для него результата нет.
        if !Task.isCancelled { cache[key] = state }
        return state
    }

    // MARK: Запросы

    private func get(title: String, artist: String, album: String, duration: Double) async -> LyricsState? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [URLQueryItem(name: "track_name", value: title),
                     URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        c.queryItems = items
        guard let url = c.url, let obj = await json(url) as? [String: Any] else { return nil }
        return Self.state(from: obj)
    }

    private func search(title: String, artist: String) async -> LyricsState? {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [URLQueryItem(name: "track_name", value: title),
                        URLQueryItem(name: "artist_name", value: artist)]
        guard let url = c.url, let list = await json(url) as? [[String: Any]], !list.isEmpty else { return nil }
        // Сначала — с таймингами.
        let best = list.first { ($0["syncedLyrics"] as? String)?.isEmpty == false } ?? list[0]
        return Self.state(from: best)
    }

    private func json(_ url: URL) async -> Any? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func state(from obj: [String: Any]) -> LyricsState? {
        if (obj["instrumental"] as? Bool) == true { return .instrumental }
        if let synced = obj["syncedLyrics"] as? String {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = obj["plainLyrics"] as? String {
            let lines = plain.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty { return .plain(lines) }
        }
        return nil
    }

    /// Разбор LRC: «[мм:сс.хх] текст»; у одной строки может быть несколько меток.
    static func parseLRC(_ text: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for raw in text.split(separator: "\n") {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = parseTime(tag) { times.append(t) }
                rest = rest[rest.index(after: close)...]
            }
            let line = rest.trimmingCharacters(in: .whitespaces)
            for t in times { result.append(LyricLine(time: t, text: line)) }
        }
        return result.sorted { $0.time < $1.time }
    }

    private static func parseTime(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        return m * 60 + s
    }

    /// Индекс текущей строки для позиции (последняя, чьё время уже наступило).
    static func currentIndex(_ lines: [LyricLine], at position: Double) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= position + 0.15 {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }
}
