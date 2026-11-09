import Foundation

enum WatchStatus: String, Codable, CaseIterable, Identifiable {
    case planning = "Plan to watch", watching = "Watching", completed = "Completed", paused = "Paused", dropped = "Dropped"
    var id: String { rawValue }
}

enum JournalMood: String, Codable, CaseIterable, Identifiable {
    case amazed = "Amazed", happy = "Happy", emotional = "Emotional", thoughtful = "Thoughtful", cozy = "Cozy", mixed = "Mixed"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .amazed: "sparkles"; case .happy: "sun.max"; case .emotional: "heart"; case .thoughtful: "cloud"; case .cozy: "cup.and.saucer"; case .mixed: "circle.lefthalf.filled" }
    }
}

struct JournalEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var body = ""
    var watchedOn = Date.now
    var episode: Int?
    var rating: Int?
    var mood: JournalMood?
    var containsSpoilers = false
    var createdAt = Date.now
    var updatedAt = Date.now
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? episode.map { "Episode \($0)" } ?? "A moment in the story" : title }
}

struct JournalItem: Identifiable {
    var anime: Anime
    var entry: JournalEntry
    var id: UUID { entry.id }
}

struct LibraryCollection: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String = "sparkles"
    var color: String = "violet"
    var animeIDs: Set<Int> = []
    var createdAt = Date.now
    static let symbols = ["sparkles", "moon.stars", "heart", "flame", "leaf", "bolt", "popcorn", "cloud"]
    static let colors = ["violet", "mint", "rose", "amber", "blue"]
}

struct ActivityEvent: Codable, Identifiable {
    enum Kind: String, Codable { case episode, journal, checkIn }
    var id = UUID()
    var kind: Kind
    var animeID: Int
    var journalID: UUID?
    var count: Int = 1
    var date: Date
    var dayKey: String
}

struct ActivityDay: Identifiable {
    var date: Date
    var key: String
    var active: Bool
    var id: String { key }
}

struct StreakSnapshot {
    static var localCalendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = .current; return value }
    var current = 0
    var longest = 0
    var totalDays = 0
    var activeToday = false
    var week: [ActivityDay] = []
    var month: [ActivityDay] = []
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components), dayKey(date, calendar: calendar) == key else { return nil }
        return calendar.startOfDay(for: date)
    }
    static func calculate(_ events: [ActivityEvent], now: Date = .now, calendar: Calendar = localCalendar) -> StreakSnapshot {
        let today = calendar.startOfDay(for: now)
        let dates = Set(events.filter { $0.count > 0 }.compactMap { date($0.dayKey, calendar: calendar) }).filter { $0 <= today }.sorted()
        let keys = Set(dates.map { dayKey($0, calendar: calendar) })
        let metrics = RustCore.streak(Array(dates), today: today, calendar: calendar)
        var result = StreakSnapshot()
        result.current = Int(metrics[0]); result.longest = Int(metrics[1])
        result.totalDays = Int(metrics[2]); result.activeToday = metrics[3] != 0
        func days(_ count: Int) -> [ActivityDay] {
            (0..<count).reversed().map { offset in
                let date = calendar.date(byAdding: .day, value: -offset, to: today)!
                let key = dayKey(date, calendar: calendar)
                return ActivityDay(date: date, key: key, active: keys.contains(key))
            }
        }
        result.week = days(7); result.month = days(28)
        return result
    }
}

enum LibraryValidation: LocalizedError {
    case emptyEntry, futureDate, invalidRating, invalidEpisode, invalidDates, emptyName, duplicateName
    var errorDescription: String? {
        switch self {
        case .emptyEntry: "Add a title or a few words before saving."
        case .futureDate: "Choose today or an earlier date."
        case .invalidRating: "Ratings must be between 1 and 10."
        case .invalidEpisode: "Choose a valid episode number."
        case .invalidDates: "The finish date must be on or after the first-watched date."
        case .emptyName: "Give your collection a name."
        case .duplicateName: "A collection with that name already exists."
        }
    }
}
