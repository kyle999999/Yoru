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
            guard let match = matches(pattern, text).first, let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }
        let markers = matches(#"<div class="anime-header">(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Other|Unknown)</div>|<div class="js-anime-category-producer seasonal-anime[^>]*>"#, html)
        var day: String?; var days: [String: [Anime]] = [:]; var parsedCards = 0
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
            let image = capture(#"<img[^>]*data-src="([^"]+)""#, block)
            let episodes = capture(#"<span>(\d+) eps</span>"#, block).flatMap(Int.init)
            let score = capture(#"class="js-score">([\d.]+)</span>"#, block).flatMap(Double.init)
            let broadcast = day == "unknown" || day == "other" ? nil : Broadcast(day: day.capitalized + "s", time: nil, timezone: "Asia/Tokyo", string: day.capitalized + " · time not supplied")
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
        self.cacheFile = cacheFile ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("yoru-weekly-schedule-v1.json")
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
