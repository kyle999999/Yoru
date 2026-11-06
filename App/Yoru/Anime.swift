import Foundation

struct Anime: Codable, Identifiable, Hashable, Sendable {
    var malId: Int
    var title: String
    var titleEnglish: String?
    var titleJapanese: String?
    var images: Images?
    var synopsis: String?
    var episodes: Int?
    var status: String?
    var airing: Bool?
    var score: Double?
    var type: String?
    var season: String?
    var year: Int?
    var broadcast: Broadcast?
    var genres: [NamedItem]?
    var studios: [NamedItem]?
    var streaming: [StreamLink]?
    var url: String?
    var kitsuId: String?
    var sourceName: String?
    var nextRelease: Date?
    var id: Int { malId }
    var displayTitle: String { titleEnglish.flatMap { $0.isEmpty ? nil : $0 } ?? title }
    var posterURL: URL? { URL(string: images?.jpg?.largeImageUrl ?? images?.jpg?.imageUrl ?? "") }
    var episodeLabel: String { episodes.map { "\($0) \($0 == 1 ? "episode" : "episodes")" } ?? "Episodes TBA" }
    var statusLabel: String {
        switch status { case "Currently Airing": "Airing now"; case "Finished Airing": "Completed"; case "Not yet aired": "Upcoming"; default: "Status unknown" }
    }
    var seasonLabel: String { [season?.capitalized, year.map(String.init)].compactMap { $0 }.joined(separator: " ") }
    var safeStreaming: [StreamLink] {
        var seen = Set<String>()
        return (streaming ?? []).filter { $0.safeURL != nil && seen.insert($0.name.lowercased()).inserted }
    }
    struct Images: Codable, Hashable, Sendable { var jpg: ImageSet? }
    struct ImageSet: Codable, Hashable, Sendable { var imageUrl: String?; var largeImageUrl: String? }
    struct NamedItem: Codable, Hashable, Sendable { var name: String }
}

struct StreamLink: Codable, Identifiable, Hashable, Sendable {
    var name: String
    var url: String
    var regions: [String]?
    var id: String { name + url }
    var safeURL: URL? {
        guard let value = URL(string: url), value.scheme?.lowercased() == "https", value.host != nil else { return nil }
        return value
    }
}

struct Broadcast: Codable, Hashable, Sendable {
    var day: String?
    var time: String?
    var timezone: String?
    var string: String?
    var shortTime: String { time.map { "\($0) JST" } ?? "Time TBA" }
    func nextDate(after now: Date = .now) -> Date? {
        let names = ["sundays", "mondays", "tuesdays", "wednesdays", "thursdays", "fridays", "saturdays"]
        guard let day, let weekday = names.firstIndex(of: day.lowercased()), let time,
              let zone = TimeZone(identifier: timezone ?? "Asia/Tokyo") else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.nextDate(after: now, matching: DateComponents(hour: parts[0], minute: parts[1], weekday: weekday + 1), matchingPolicy: .nextTime)
    }
}

struct AnimePage: Decodable, Sendable {
    let data: [Anime]
    let pagination: Pagination
    struct Pagination: Decodable, Sendable { let hasNextPage: Bool; var lastVisiblePage: Int? }
}
struct AnimeDetail: Decodable, Sendable { let data: Anime }

struct Season: Hashable, Sendable {
    var year: Int
    var name: String
    static let names = ["winter", "spring", "summer", "fall"]
    static func current(date: Date = .now) -> Season {
        let c = Calendar(identifier: .gregorian)
        return Season(year: c.component(.year, from: date), name: names[(c.component(.month, from: date) - 1) / 3])
    }
    var label: String { "\(name.capitalized) \(year)" }
}

enum CatalogScope: String, CaseIterable, Identifiable { case season = "Season", airing = "All airing", archive = "Archive"; var id: String { rawValue } }

enum BroadcastDay: String, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday, unknown, other
    var id: String { rawValue }
    var label: String { rawValue == "unknown" ? "TBA" : rawValue == "other" ? "All" : String(rawValue.prefix(3)).capitalized }
    static var todayInJapan: BroadcastDay {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday][c.component(.weekday, from: .now) - 1]
    }
}
