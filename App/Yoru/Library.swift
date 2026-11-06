import Foundation
import Observation

@Observable @MainActor final class Library {
    struct Entry: Codable {
        var anime: Anime; var watched: Int; var saved: Bool
        var firstWatched: Date?
        var finishedWatched: Date?
        var personalRating: Int?
        var watchStatus: WatchStatus?
        var journal: [JournalEntry]?
    }
    private struct Stored: Codable { var entries: [Int: Entry]; var collections: [LibraryCollection]; var activity: [ActivityEvent] }
    private(set) var entries: [Int: Entry] = [:]
    private(set) var collections: [LibraryCollection] = []
    private(set) var activity: [ActivityEvent] = []
    private(set) var saveError: String?
    private let defaults: UserDefaults
    private var persistenceBlocked = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "yoru.library.v3") {
            if let saved = try? JSONDecoder().decode(Stored.self, from: data) {
                entries = saved.entries; collections = saved.collections; activity = saved.activity
            } else {
                persistenceBlocked = true
                saveError = "Your saved library couldn’t be opened. Its data has been kept unchanged."
            }
        } else if let data = defaults.data(forKey: "yoru.library.v2") {
            if let saved = try? JSONDecoder().decode([Int: Entry].self, from: data) { entries = saved }
            else { persistenceBlocked = true; saveError = "Your previous library couldn’t be opened. Its data has been kept unchanged." }
        } else { migrateLegacy() }
    }
    var saved: [Anime] { entries.values.filter(\.saved).map(\.anime).sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending } }
    var episodeCount: Int { entries.values.reduce(0) { $0 + $1.watched } }
    var journals: [JournalItem] {
        var items: [JournalItem] = []
        for record in entries.values {
            for note in record.journal ?? [] { items.append(JournalItem(anime: record.anime, entry: note)) }
        }
        return items.sorted { lhs, rhs in
            if lhs.entry.watchedOn == rhs.entry.watchedOn { return lhs.entry.updatedAt > rhs.entry.updatedAt }
            return lhs.entry.watchedOn > rhs.entry.watchedOn
        }
    }

    func journal(for anime: Anime) -> [JournalEntry] { (entries[anime.id]?.journal ?? []).sorted { $0.watchedOn > $1.watchedOn } }
    func collectionAnime(_ collection: LibraryCollection) -> [Anime] {
        collection.animeIDs.compactMap { entries[$0]?.anime }.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }
    func streak(now: Date = .now, calendar: Calendar = StreakSnapshot.localCalendar) -> StreakSnapshot { .calculate(activity, now: now, calendar: calendar) }
    @discardableResult func checkIn(now: Date = .now, calendar: Calendar = StreakSnapshot.localCalendar) -> Bool {
        guard !persistenceBlocked else { return false }
        let key = StreakSnapshot.dayKey(now, calendar: calendar)
        guard !activity.contains(where: { $0.kind == .checkIn && $0.dayKey == key }) else { return false }
        activity.append(ActivityEvent(kind: .checkIn, animeID: 0, date: now, dayKey: key))
        persist(); return saveError == nil
    }
    func claimDailyPrompt(now: Date = .now) -> Bool {
        let key = StreakSnapshot.dayKey(now, calendar: StreakSnapshot.localCalendar)
        guard !persistenceBlocked, !streak(now: now).activeToday, defaults.string(forKey: "yoru.checkInPromptDay") != key else { return false }
        defaults.set(key, forKey: "yoru.checkInPromptDay"); return true
    }
    func isSaved(_ anime: Anime) -> Bool { entries[anime.id]?.saved ?? false }
    func watched(_ anime: Anime) -> Int { entries[anime.id]?.watched ?? 0 }
    func toggle(_ anime: Anime) {
        var entry = entries[anime.id] ?? Entry(anime: anime, watched: 0, saved: false)
        entry.saved.toggle(); entry.anime = anime; entries[anime.id] = entry; persist()
    }
    func log(_ anime: Anime, delta: Int = 1, now: Date = .now, calendar: Calendar = StreakSnapshot.localCalendar) {
        var entry = entries[anime.id] ?? Entry(anime: anime, watched: 0, saved: true)
        let next = max(0, entry.watched + delta)
        let oldCount = entry.watched
        entry.watched = anime.episodes.map { min($0, next) } ?? next
        let change = entry.watched - oldCount
        if change > 0 {
            if entry.firstWatched == nil { entry.firstWatched = now }
            if entry.watchStatus == nil || entry.watchStatus == .planning { entry.watchStatus = .watching }
            if let total = anime.episodes, total > 0, entry.watched >= total { entry.watchStatus = .completed; entry.finishedWatched = now }
            activity.append(ActivityEvent(kind: .episode, animeID: anime.id, count: change, date: now, dayKey: StreakSnapshot.dayKey(now, calendar: calendar)))
        } else if change < 0 {
            var remaining = -change
            for index in activity.indices.reversed() where activity[index].animeID == anime.id && activity[index].kind == .episode {
                let removed = min(remaining, activity[index].count); activity[index].count -= removed; remaining -= removed
                if remaining == 0 { break }
            }
            activity.removeAll { $0.count <= 0 }
            if entry.watchStatus == .completed { entry.watchStatus = .watching; entry.finishedWatched = nil }
        }
        entry.saved = true; entry.anime = anime; entries[anime.id] = entry; persist()
    }
    func setMetadata(_ anime: Anime, first: Date?, finished: Date?, rating: Int?, status: WatchStatus?, now: Date = .now) throws {
        let calendar = StreakSnapshot.localCalendar
        let today = calendar.startOfDay(for: now)
        guard first.map({ calendar.startOfDay(for: $0) <= today }) ?? true, finished.map({ calendar.startOfDay(for: $0) <= today }) ?? true else { throw LibraryValidation.futureDate }
        if let first, let finished, calendar.startOfDay(for: finished) < calendar.startOfDay(for: first) { throw LibraryValidation.invalidDates }
        if let rating, !(1...10).contains(rating) { throw LibraryValidation.invalidRating }
        var entry = entries[anime.id] ?? Entry(anime: anime, watched: 0, saved: true)
        entry.firstWatched = first; entry.finishedWatched = finished; entry.personalRating = rating; entry.watchStatus = status
        entry.saved = true; entry.anime = anime; entries[anime.id] = entry; persist()
    }
    func saveJournal(_ draft: JournalEntry, for anime: Anime, now: Date = .now, calendar: Calendar = StreakSnapshot.localCalendar) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryValidation.emptyEntry }
        guard calendar.startOfDay(for: draft.watchedOn) <= calendar.startOfDay(for: now) else { throw LibraryValidation.futureDate }
        if let rating = draft.rating, !(1...10).contains(rating) { throw LibraryValidation.invalidRating }
        if let number = draft.episode, number < 1 || anime.episodes.map({ number > $0 }) == true { throw LibraryValidation.invalidEpisode }
        var entry = entries[anime.id] ?? Entry(anime: anime, watched: 0, saved: true)
        var notes = entry.journal ?? []; var note = draft; note.updatedAt = now
        if let index = notes.firstIndex(where: { $0.id == draft.id }) {
            let previous = notes[index]
            guard previous.title != draft.title || previous.body != draft.body || previous.watchedOn != draft.watchedOn || previous.episode != draft.episode || previous.rating != draft.rating || previous.mood != draft.mood || previous.containsSpoilers != draft.containsSpoilers else { return }
            note.createdAt = previous.createdAt; notes[index] = note
        } else { note.createdAt = now; notes.append(note) }
        entry.journal = notes; entry.anime = anime; entry.saved = true; entries[anime.id] = entry
        let key = StreakSnapshot.dayKey(now, calendar: calendar)
        if !activity.contains(where: { $0.kind == .journal && $0.journalID == note.id && $0.dayKey == key }) {
            activity.append(ActivityEvent(kind: .journal, animeID: anime.id, journalID: note.id, date: now, dayKey: key))
        }
        persist()
    }
    func deleteJournal(_ id: UUID, animeID: Int) {
        guard var entry = entries[animeID] else { return }
        entry.journal?.removeAll { $0.id == id }; entries[animeID] = entry
        activity.removeAll { $0.kind == .journal && $0.journalID == id }; persist()
    }
    func saveCollection(_ collection: LibraryCollection) throws {
        let name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryValidation.emptyName }
        guard !collections.contains(where: { $0.id != collection.id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { throw LibraryValidation.duplicateName }
        var updated = collection; updated.name = name
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            updated.animeIDs = collections[index].animeIDs; updated.createdAt = collections[index].createdAt; collections[index] = updated
        } else { collections.append(updated) }
        persist()
    }
    func setMembership(_ anime: Anime, collectionID: UUID, included: Bool) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if included {
            collections[index].animeIDs.insert(anime.id)
            var entry = entries[anime.id] ?? Entry(anime: anime, watched: 0, saved: true)
            entry.saved = true; entry.anime = anime; entries[anime.id] = entry
        } else { collections[index].animeIDs.remove(anime.id) }
        persist()
    }
    func deleteCollection(_ id: UUID) { collections.removeAll { $0.id == id }; persist() }
    func update(_ anime: Anime) {
        guard var entry = entries[anime.id] else { return }
        entry.anime = anime; entries[anime.id] = entry; persist()
    }
    private func persist() {
        guard !persistenceBlocked else { return }
        do { defaults.set(try JSONEncoder().encode(Stored(entries: entries, collections: collections, activity: activity)), forKey: "yoru.library.v3"); saveError = nil }
        catch { saveError = "Your progress couldn’t be saved. Please try again." }
    }
    private func migrateLegacy() {
        struct Old: Decodable { var id: String; var title: String; var episodes: Int; var watched: Int; var saved: Bool }
        let ids = ["frieren": 52991, "bebop": 1, "violet": 33352, "mob": 32182, "champloo": 205]
        guard let data = defaults.data(forKey: "yoru.library"), let old = try? JSONDecoder().decode([Old].self, from: data) else { return }
        for show in old {
            guard let id = ids[show.id], show.saved || show.watched > 0 else { continue }
            entries[id] = Entry(anime: Anime(malId: id, title: show.title, episodes: show.episodes), watched: show.watched, saved: show.saved)
        }
        persist()
    }
}

@Observable @MainActor final class CatalogStore {
    var items: [Anime] = []
    var isLoading = false
    var error: String?
    var isStale = false
    var fetchedAt: Date?
    var hasMore = false
    var pageNumber = 0
    private var generation = UUID()
    private var path = ""
    private var parameters: [String: String] = [:]

    func load(path: String, parameters: [String: String] = [:], allPages: Bool = false, refresh: Bool = false) async {
        let requestID = UUID(); generation = requestID
        self.path = path; self.parameters = parameters
        isLoading = true; error = nil; isStale = false
        items = []; hasMore = false; pageNumber = 0; fetchedAt = nil
        defer { if generation == requestID { isLoading = false } }
        repeat {
            do {
                let result = try await AnimeAPI.shared.page(path: path, parameters: parameters, page: pageNumber + 1, refresh: refresh)
                try Task.checkCancellation()
                guard generation == requestID else { return }
                append(result); pageNumber += 1
            } catch is CancellationError { return }
            catch {
                guard generation == requestID else { return }
                self.error = error.localizedDescription; return
            }
        } while allPages && hasMore
    }
    func loadMore() async {
        guard hasMore, !isLoading else { return }
        let requestID = generation; isLoading = true; error = nil
        defer { if generation == requestID { isLoading = false } }
        do {
            let result = try await AnimeAPI.shared.page(path: path, parameters: parameters, page: pageNumber + 1)
            try Task.checkCancellation()
            guard generation == requestID else { return }
            append(result); pageNumber += 1
        } catch is CancellationError {} catch { if generation == requestID { self.error = error.localizedDescription } }
    }
    private func append(_ result: APIResponse<AnimePage>) {
        var seen = Set(items.map(\.id))
        items.append(contentsOf: result.value.data.filter { seen.insert($0.id).inserted })
        hasMore = result.value.pagination.hasNextPage
        isStale = isStale || result.isStale
        fetchedAt = min(fetchedAt ?? result.fetchedAt, result.fetchedAt)
    }
}
