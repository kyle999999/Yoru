import Foundation

@main struct JournalChecks {
    @MainActor static func main() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ key: String) -> Date { StreakSnapshot.date(key, calendar: calendar)!.addingTimeInterval(12 * 3600) }
        let now = date("2026-11-04")
        func event(_ key: String, count: Int = 1) -> ActivityEvent { ActivityEvent(kind: .episode, animeID: 1, count: count, date: date(key), dayKey: key) }
        let suite = "yoru.journal.validation." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = #"{"1":{"anime":{"malId":1,"title":"Cowboy Bebop","episodes":26},"watched":6,"saved":true}}"#
        defaults.set(Data(legacy.utf8), forKey: "yoru.library.v2")
        let library = Library(defaults: defaults)
        let anime = library.saved[0]
        expect(library.watched(anime) == 6 && library.streak(now: now, calendar: calendar).current == 0, "v2 watch counts migrate without invented past activity")
        try library.setMetadata(anime, first: date("2025-03-02"), finished: date("2025-04-01"), rating: 9, status: .completed, now: now)
        expect(library.streak(now: now, calendar: calendar).totalDays == 0, "Historical watch dates do not earn streaks")
        do { try library.setMetadata(anime, first: date("2025-04-02"), finished: date("2025-04-01"), rating: nil, status: nil, now: now); fatalError("Expected validation") } catch LibraryValidation.invalidDates {}
        var note = JournalEntry(); note.title = "See you, space cowboy"; note.body = "A quiet ending that stayed with me."; note.watchedOn = date("2025-04-01"); note.mood = .emotional; note.rating = 10; note.containsSpoilers = true
        try library.saveJournal(note, for: anime, now: now, calendar: calendar)
        expect(library.journals.count == 1 && library.streak(now: now, calendar: calendar).current == 1, "Backdated entry earns today, not its historical watch date")
        expect(library.entries[anime.id]?.personalRating == 9 && library.journals[0].entry.rating == 10, "Series rating and journal rating remain independent")
        try library.saveJournal(library.journals[0].entry, for: anime, now: date("2026-11-05"), calendar: calendar)
        expect(library.streak(now: date("2026-11-05"), calendar: calendar).activeToday == false, "Saving an unchanged entry does not manufacture a new active day")
        note.body += " A new thought."; try library.saveJournal(note, for: anime, now: date("2026-11-05"), calendar: calendar)
        expect(library.journals.count == 1 && library.streak(now: date("2026-11-05"), calendar: calendar).current == 2, "Editing on a new day earns activity without duplicating the entry")
        let created = library.journals[0].entry.createdAt
        note.body += " Another thought."; try library.saveJournal(note, for: anime, now: date("2026-11-05"), calendar: calendar)
        expect(library.journals[0].entry.createdAt == created, "Edits preserve original creation time")
        do { try library.saveJournal(JournalEntry(), for: anime, now: .now); fatalError("Expected empty-note validation") } catch LibraryValidation.emptyEntry {}
        var invalid = note; invalid.watchedOn = date("2026-11-07")
        do { try library.saveJournal(invalid, for: anime, now: now, calendar: calendar); fatalError("Expected future-date validation") } catch LibraryValidation.futureDate {}
        invalid = note; invalid.rating = 11
        do { try library.saveJournal(invalid, for: anime, now: now, calendar: calendar); fatalError("Expected rating validation") } catch LibraryValidation.invalidRating {}
        invalid = note; invalid.episode = 27
        do { try library.saveJournal(invalid, for: anime, now: now, calendar: calendar); fatalError("Expected episode validation") } catch LibraryValidation.invalidEpisode {}
        var cozy = LibraryCollection(name: "Cozy nights", symbol: "moon.stars", color: "mint")
        let favorites = LibraryCollection(name: "Favorites", symbol: "heart", color: "rose")
        try library.saveCollection(cozy); try library.saveCollection(favorites)
        library.setMembership(anime, collectionID: cozy.id, included: true); library.setMembership(anime, collectionID: favorites.id, included: true)
        expect(library.collections.allSatisfy { $0.animeIDs.contains(anime.id) }, "A show can belong to multiple collections")
        cozy.name = "Quiet nights"; try library.saveCollection(cozy)
        expect(library.collections[0].animeIDs.contains(anime.id), "Renaming a collection preserves memberships")
        do { try library.saveCollection(LibraryCollection(name: "  QUIET NIGHTS  ")); fatalError("Expected duplicate-name validation") } catch LibraryValidation.duplicateName {}
        let restored = Library(defaults: defaults)
        expect(restored.collections.count == 2 && restored.journals.count == 1 && restored.watched(anime) == 6, "Journal, collection, and progress survive relaunch")
        expect(defaults.data(forKey: "yoru.library.v2") == Data(legacy.utf8), "v2 migration backup stays unchanged")
        library.deleteCollection(cozy.id)
        expect(library.isSaved(anime) && library.journals.count == 1 && library.watched(anime) == 6, "Deleting a collection preserves shows, notes, and progress")
        library.log(anime, now: now, calendar: calendar)
        library.log(anime, delta: -1, now: now, calendar: calendar)
        expect(library.streak(now: now, calendar: calendar).activeToday, "Undoing an episode keeps journal-earned activity")
        library.deleteJournal(note.id, animeID: anime.id)
        expect(library.journals.isEmpty && library.streak(now: now, calendar: calendar).totalDays == 0, "Deleting the only journal removes its activity credits")
        let multi = [event("2026-11-01"),event("2026-11-01"),event("2026-11-02"),event("2026-11-03"),event("2026-11-04")]
        let streak = StreakSnapshot.calculate(multi, now: now, calendar: calendar)
        expect(streak.current == 4 && streak.longest == 4 && streak.totalDays == 4, "Consecutive days across autumn DST count once each")
        let grace = StreakSnapshot.calculate([event("2026-11-02"),event("2026-11-03")], now: now, calendar: calendar)
        expect(grace.current == 2 && !grace.activeToday, "Yesterday-ending streak remains active for today")
        let broken = StreakSnapshot.calculate([event("2026-10-30"),event("2026-10-31"),event("2026-11-01"),event("2026-11-04"),event("2026-11-05")], now: now, calendar: calendar)
        expect(broken.current == 1 && broken.longest == 3 && broken.totalDays == 4, "Gaps reset current streak while preserving best; future events are ignored")
        expect(streak.week.count == 7 && streak.month.count == 28 && streak.week.last?.key == "2026-11-04", "Heatmap ends at today and has correct dimensions")
        let spring = [event("2026-03-07"),event("2026-03-08"),event("2026-03-09")]
        expect(StreakSnapshot.calculate(spring, now: date("2026-03-09"), calendar: calendar).current == 3, "Spring DST does not split a streak")
        let bad = UserDefaults(suiteName: suite + ".corrupt")!; defer { bad.removePersistentDomain(forName: suite + ".corrupt") }
        bad.set(Data("broken".utf8), forKey: "yoru.library.v3")
        let blocked = Library(defaults: bad); blocked.toggle(anime)
        expect(blocked.saveError != nil && bad.data(forKey: "yoru.library.v3") == Data("broken".utf8), "Corrupt storage is protected from accidental overwrite")
        let badV2 = UserDefaults(suiteName: suite + ".corruptv2")!; defer { badV2.removePersistentDomain(forName: suite + ".corruptv2") }
        badV2.set(Data("broken-v2".utf8), forKey: "yoru.library.v2")
        let blockedV2 = Library(defaults: badV2); blockedV2.toggle(anime)
        expect(blockedV2.saveError != nil && badV2.data(forKey: "yoru.library.v3") == nil, "Corrupt v2 backup does not create a replacement library")
        print("All journal, collection, migration, and streak checks passed.")
    }
    static func expect(_ value: Bool, _ label: String) { guard value else { fatalError("FAIL: " + label) }; print("PASS: " + label) }
}
