import Foundation
import Observation

// Read one public weekly document rather than guessing weekdays from sparse next-release dates.
struct WeeklySchedule: Codable, Sendable {
    var days: [String: [Anime]]
    var fetchedAt: Date
    func titles(for day: BroadcastDay) -> [Anime] {
        let values = day == .other ? days.values.flatMap { $0 } : days[day.rawValue] ?? []
        var seen = Set<Int>()
        return values.filter { seen.insert($0.id).inserted }.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }
    static func parse(_ html: String, now: Date = .now) throws -> WeeklySchedule {
        func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
            (try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]).matches(in: text, range: NSRange(text.startIndex..., in: text))) ?? []
        }
        func capture(_ pattern: String, _ text: String, group: Int = 1) -> String? {
            // A pattern without the requested group makes range(at:) throw an
            // Objective-C exception (and terminates the app). Keep malformed or
            // intentionally whole-match patterns safe on iOS.
            guard let match = matches(pattern, text).first,
                  group >= 0, group < match.numberOfRanges,
                  match.range(at: group).location != NSNotFound,
                  let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }
        let markers = matches(#"<div class="anime-header">(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Other|Unknown)</div>|<div class="js-anime-category-producer seasonal-anime[^>]*>"#, html)
        var day: String?; var days: [String: [Anime]] = [:]; var parsedCards = 0
        var assignedAnime = Set<Int>()
        for (index, marker) in markers.enumerated() {
            let start = marker.range.location
            let end = index + 1 < markers.count ? markers[index + 1].range.location : (html as NSString).length
            let block = (html as NSString).substring(with: NSRange(location: start, length: end - start))
            if marker.range(at: 1).location != NSNotFound {
                day = (html as NSString).substring(with: marker.range(at: 1)).lowercased(); days[day!] = []; continue
            }
            guard let day else { continue }
            let genres = capture(#"data-genre="([^"]*)""#, block)?.split(separator: ",").compactMap { Int($0) } ?? []
            if genres.contains(12) || genres.contains(49) { continue }
            guard let idText = capture(#"class="genres js-genre" id="(\d+)""#, block), let id = Int(idText),
                  let title = capture(#"class="link-title">(.*?)</a>"#, block) else { throw ScheduleError.changedFormat }
            parsedCards += 1
            // MAL currently serves regular `src` attributes, but some cached or
            // lazy-loaded responses use data-src/data-original instead.
            // Provider icons precede the poster in current schedule cards.
            // Only accept an image whose URL points to MAL anime artwork.
            let imageTag = matches(#"<img\b[^>]*>"#, block).compactMap { match -> String? in
                guard let range = Range(match.range, in: block) else { return nil }
                let tag = String(block[range])
                return tag.contains("myanimelist.net/images/anime/") ? tag : nil
            }.first ?? ""
            let image = capture(#"data-src="([^"]+)""#, imageTag)
                ?? capture(#"data-original="([^"]+)""#, imageTag)
                ?? capture(#"src="([^"]+)""#, imageTag)
                ?? capture(#"srcset="([^"]+)""#, imageTag)?.split(separator: ",").first.map { String($0.split(separator: " ").first ?? "") }
            let episodes = capture(#"<span>(\d+) eps</span>"#, block).flatMap(Int.init)
            let score = capture(#"class="js-score">([\d.]+)</span>"#, block).flatMap(Double.init)
            let broadcast = day == "unknown" || day == "other" ? nil : Broadcast(day: day.capitalized + "s", time: nil, timezone: "Asia/Tokyo", string: day.capitalized + " · time not supplied")
            // Keep one canonical weekday per title if upstream repeats a card.
            guard assignedAnime.insert(id).inserted else { continue }
            days[day, default: []].append(Anime(malId: id, title: decodeEntities(title), images: .init(jpg: .init(imageUrl: image, largeImageUrl: image)), episodes: episodes, status: "Currently Airing", airing: true, score: score, broadcast: broadcast, url: "https://myanimelist.net/anime/\(id)", sourceName: "MyAnimeList"))
        }
        guard parsedCards > 0, ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].allSatisfy({ days[$0] != nil }) else { throw ScheduleError.changedFormat }
        return WeeklySchedule(days: days, fetchedAt: now)
    }
    static func decodeEntities(_ text: String) -> String {
        var value = text
        if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|\d+);"#) {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range(at: 1), in: value), let full = Range(match.range, in: value) else { continue }
                let code = String(value[range]); let number = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
                if let number, let scalar = UnicodeScalar(number) { value.replaceSubrange(full, with: String(scalar)) }
            }
        }
        for (entity, replacement) in [("&quot;", "\""), ("&#039;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] { value = value.replacingOccurrences(of: entity, with: replacement) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ScheduleError: LocalizedError {
    case changedFormat
    var errorDescription: String? { "The weekly schedule couldn’t be verified. Please retry or open an official calendar below." }
}

actor ScheduleAPI {
    static let shared = ScheduleAPI()
    private let session: URLSession
    private let cacheFile: URL
    init(session: URLSession = .shared, cacheFile: URL? = nil) {
        self.session = session
        self.cacheFile = cacheFile ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("yoru-weekly-schedule-v3.json")
    }
    func week(refresh: Bool = false) async throws -> APIResponse<WeeklySchedule> {
        let cached = (try? Data(contentsOf: cacheFile)).flatMap { try? JSONDecoder().decode(WeeklySchedule.self, from: $0) }
        if !refresh, let cached, Date.now.timeIntervalSince(cached.fetchedAt) < 6 * 3600 {
            return .init(value: cached, fetchedAt: cached.fetchedAt, isStale: false)
        }
        do {
            var request = URLRequest(url: URL(string: "https://myanimelist.net/anime/season/schedule")!)
            request.timeoutInterval = 12
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let html = String(data: data, encoding: .utf8) else { throw ScheduleError.changedFormat }
            let week = try WeeklySchedule.parse(html)
            try? JSONEncoder().encode(week).write(to: cacheFile, options: .atomic)
            return .init(value: week, fetchedAt: week.fetchedAt, isStale: false)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let cached { return .init(value: cached, fetchedAt: cached.fetchedAt, isStale: true) }
            throw error
        }
    }
}

@Observable @MainActor final class ScheduleStore {
    private(set) var week: WeeklySchedule?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var isStale = false
    func load(refresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let result = try await ScheduleAPI.shared.week(refresh: refresh)
            week = result.value; isStale = result.isStale
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

// Jikan exposes MAL's broadcast metadata, including the clock time omitted
// from the public weekly HTML. Keep this supplemental lookup independent.
actor BroadcastTimeAPI {
    static let shared = BroadcastTimeAPI()
    private struct Page: Decodable {
        struct Item: Decodable { let mal_id: Int; let broadcast: Broadcast? }
        struct Pagination: Decodable { let has_next_page: Bool }
        let data: [Item]
        let pagination: Pagination
    }
    private var cache: [String: (Date, [Int: Broadcast])] = [:]
    private var nextSlot = Date.distantPast
    private struct SavedTimes: Codable { let fetchedAt: Date; let times: [Int: Broadcast] }
    private func cacheURL(_ day: BroadcastDay) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("yoru-broadcast-times-\(day.rawValue).json")
    }
    func times(for day: BroadcastDay) async -> [Int: Broadcast] {
        guard day != .other, day != .unknown else { return [:] }
        if let cached = cache[day.rawValue], Date().timeIntervalSince(cached.0) < 21600 { return cached.1 }
        let disk = (try? Data(contentsOf: cacheURL(day))).flatMap { try? JSONDecoder().decode(SavedTimes.self, from: $0) }
        if let disk, Date().timeIntervalSince(disk.fetchedAt) < 21600 { return disk.times }
        let fallback = disk?.times ?? cache[day.rawValue]?.1 ?? [:]
        var result: [Int: Broadcast] = [:]
        do {
            for page in 1...10 {
                try Task.checkCancellation()
                let slot = max(Date(), nextSlot); nextSlot = slot.addingTimeInterval(1.1)
                if slot > Date() { try await Task.sleep(for: .seconds(slot.timeIntervalSinceNow)) }
                let url = URL(string: "https://api.jikan.moe/v4/schedules?filter=\(day.rawValue)&sfw=true&limit=25&page=\(page)")!
                var request = URLRequest(url: url); request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { return result.isEmpty ? fallback : result }
                let decoded = try JSONDecoder().decode(Page.self, from: data)
                for item in decoded.data {
                    if let broadcast = item.broadcast, broadcast.nextDate() != nil { result[item.mal_id] = broadcast }
                }
                if !decoded.pagination.has_next_page {
                    cache[day.rawValue] = (Date(), result)
                    let saved = SavedTimes(fetchedAt: Date(), times: result)
                    if let encoded = try? JSONEncoder().encode(saved) { try? encoded.write(to: cacheURL(day), options: .atomic) }
                    return result
                }
            }
        } catch { return result.isEmpty ? fallback : result }
        return result.isEmpty ? fallback : result
    }
}

actor TitleMetadataAPI {
    static let shared = TitleMetadataAPI()
    struct Metadata: Codable, Sendable { var broadcast: Broadcast?; var synopsis: String?; var episodes: Int? }
    private var cache: [Int: Metadata] = [:]
    private var nextRequest = Date.distantPast
    func metadata(for id: Int) async -> Metadata? {
        guard id > 0 else { return nil }
        if let value = cache[id] { return value }
        do {
            let slot = max(Date(), nextRequest); nextRequest = slot.addingTimeInterval(1)
            if slot > Date() { try await Task.sleep(for: .seconds(slot.timeIntervalSinceNow)) }
            try Task.checkCancellation()
            var request = URLRequest(url: URL(string: "https://myanimelist.net/anime/\(id)")!)
            request.timeoutInterval = 12
            request.setValue("Mozilla/5.0 Yoru", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let html = String(data: data, encoding: .utf8) else { return nil }
            let value = Self.parse(html)
            cache[id] = value
            return value
        } catch { return nil }
    }
    static func parse(_ html: String) -> Metadata {
        func groups(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { return nil }
            return (1..<match.numberOfRanges).map { i in Range(match.range(at: i), in: html).map { String(html[$0]) } ?? "" }
        }
        var broadcast: Broadcast?
        if let values = groups(#"Broadcast:</span>\s*(\w+) at (\d{2}:\d{2}) \(JST\)"#) {
            let candidate = Broadcast(day: values[0], time: values[1], timezone: "Asia/Tokyo", string: "\(values[0]) at \(values[1]) JST")
            if candidate.nextDate() != nil { broadcast = candidate }
        }
        let synopsis = groups(#"<p\b[^>]*itemprop="description"[^>]*>(.*?)</p>"#)?.first.map {
            WeeklySchedule.decodeEntities($0.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
        }
        let episodes = groups(#"Episodes:</span>\s*(\d+)\s*<"#)?.first.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        return Metadata(broadcast: broadcast, synopsis: synopsis, episodes: episodes)
    }
}

actor EpisodeReleaseAPI {
    static let shared = EpisodeReleaseAPI()
    struct Episode: Decodable {
        let mal_id: Int
        let aired: String?
    }
    private struct Response: Decodable {
        struct Pagination: Decodable { let last_visible_page: Int }
        let data: [Episode]
        let pagination: Pagination
    }
    private var cache: [Int: (Date, Int)] = [:]
    private var nextSlot = Date.distantPast
    func latestAired(for id: Int) async -> Int? {
        guard id > 0 else { return nil }
        if let cached = cache[id], Date().timeIntervalSince(cached.0) < 1800 { return cached.1 }
        do {
            let first = try await page(id: id, number: 1)
            var latest = Self.latestAired(in: first.data)
            if first.pagination.last_visible_page > 1 {
                let last = try await page(id: id, number: first.pagination.last_visible_page)
                if let number = Self.latestAired(in: last.data) { latest = max(latest ?? 0, number) }
            }
            if let latest { cache[id] = (Date(), latest) }
            return latest
        } catch { return nil }
    }
    static func latestAired(in episodes: [Episode], now: Date = .now) -> Int? {
        episodes.filter { episode in
            guard episode.mal_id > 0, let value = episode.aired, let date = KitsuDocument.parseDate(value) else { return false }
            return date <= now
        }.map(\.mal_id).max()
    }
    private func page(id: Int, number: Int) async throws -> Response {
        let slot = max(Date(), nextSlot); nextSlot = slot.addingTimeInterval(1.1)
        if slot > Date() { try await Task.sleep(for: .seconds(slot.timeIntervalSinceNow)) }
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.jikan.moe/v4/anime/\(id)/episodes?page=\(number)")!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ScheduleError.changedFormat }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
