import Foundation

struct TimedLyric: Codable, Sendable {
    let time: Double
    let text: String
}

enum LyricsService {
    static func fetch(
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) async -> [TimedLyric] {
        if let result: LRCLIBResult = await request(
            path: "/api/get",
            query: query(title: title, artist: artist, album: album, duration: duration)
        ), let synced = result.syncedLyrics {
            return parse(synced)
        }

        if let result: LRCLIBResult = await request(
            path: "/api/get",
            query: query(title: title, artist: artist, album: "", duration: duration)
        ), let synced = result.syncedLyrics {
            return parse(synced)
        }

        let searchQuery = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let results: [LRCLIBResult] = await request(path: "/api/search", query: searchQuery) else { return [] }
        let normalizedTitle = normalize(title)
        let normalizedArtist = normalize(artist)
        let syncedResults = results.filter { $0.syncedLyrics != nil }
        let exactMatches = syncedResults.filter {
            normalize($0.trackName ?? $0.name ?? "") == normalizedTitle &&
            normalize($0.artistName ?? "") == normalizedArtist
        }
        let matches = exactMatches.isEmpty ? syncedResults : exactMatches
        let best = matches.min {
            abs(($0.duration ?? duration) - duration) < abs(($1.duration ?? duration) - duration)
        }
        return best?.syncedLyrics.map(parse) ?? []
    }

    static func parse(_ value: String) -> [TimedLyric] {
        let pattern = #"\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var lyrics: [TimedLyric] = []

        for line in value.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = expression.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            let text = expression.stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minuteRange]),
                      let seconds = Double(line[secondRange]) else { continue }
                lyrics.append(TimedLyric(time: minutes * 60 + seconds, text: text))
            }
        }
        return lyrics.sorted { $0.time < $1.time }
    }

    private static func query(
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        return items
    }

    private static func request<T: Decodable>(path: String, query: [URLQueryItem]) async -> T? {
        var components = URLComponents(string: "https://lrclib.net")
        components?.path = path
        components?.queryItems = query
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Dynamix/1.0 (https://github.com/stawan15/Dynamic)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}

private struct LRCLIBResult: Decodable {
    let name: String?
    let trackName: String?
    let artistName: String?
    let duration: Double?
    let syncedLyrics: String?
}
