import SwiftUI

struct JournalCard: View {
    var item: JournalItem
    var open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Poster(anime: item.anime).frame(width: 37, height: 51).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.anime.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(item.entry.watchedOn.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10, design: .monospaced)).foregroundStyle(YoruTheme.muted)
                    }
                    Spacer()
                    if let mood = item.entry.mood { Image(systemName: mood.symbol).foregroundStyle(YoruTheme.violet) }
                }
                Text(item.entry.displayTitle).font(.system(size: 21, weight: .medium, design: .serif)).tracking(-0.4).lineLimit(2)
                if item.entry.containsSpoilers {
                    Label("Spoilers tucked away · tap to open", systemImage: "eye.slash").font(.system(size: 11)).foregroundStyle(YoruTheme.muted)
                } else if !item.entry.body.isEmpty {
                    Text(item.entry.body).font(.system(size: 13)).lineSpacing(4).foregroundStyle(.white.opacity(0.6)).lineLimit(3)
                }
                HStack(spacing: 12) {
                    if let episode = item.entry.episode { Text("EP \(episode)") }
                    if let rating = item.entry.rating { Label("\(rating)/10", systemImage: "star.fill") }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(YoruTheme.violet)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.08), lineWidth: 0.7))
        }.buttonStyle(.plain).foregroundStyle(.white)
    }
}

struct JournalReader: View {
    var anime: Anime
    var entryID: UUID
    var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var reveal = false
    @State private var deleting = false
    private var entry: JournalEntry? { library.journal(for: anime).first { $0.id == entryID } }
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    if let entry {
                        VStack(alignment: .leading, spacing: 22) {
                            Poster(anime: anime).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 26))
                            Eyebrow(text: "A PAGE IN YOUR STORY")
                            Text(entry.displayTitle).font(.system(size: 34, weight: .medium, design: .serif)).tracking(-1)
                            Text(anime.displayTitle).font(.system(size: 15, weight: .medium)).foregroundStyle(YoruTheme.violet)
                            Text(entry.watchedOn.formatted(date: .long, time: .omitted)).font(.system(size: 12, design: .monospaced)).foregroundStyle(YoruTheme.muted)
                            HStack(spacing: 14) {
                                if let mood = entry.mood { Label(mood.rawValue, systemImage: mood.symbol) }
                                if let rating = entry.rating { Label("\(rating)/10", systemImage: "star.fill") }
                                if let episode = entry.episode { Text("Episode \(episode)") }
                            }.font(.system(size: 11)).foregroundStyle(YoruTheme.mint)
                            if entry.containsSpoilers && !reveal {
                                VStack(alignment: .leading, spacing: 15) {
                                    Label("A little spoiler warning", systemImage: "eye.slash").font(.system(size: 17, weight: .medium))
                                    Text("You marked this entry as containing spoilers.").font(.system(size: 13)).foregroundStyle(YoruTheme.muted)
                                    Button("Reveal entry") { reveal = true }.buttonStyle(.glass)
                                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
                            } else { Text(entry.body).font(.system(size: 17, design: .serif)).lineSpacing(8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            Text("Edited \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(YoruTheme.muted)
                            Button("Delete entry", role: .destructive) { deleting = true }.font(.system(size: 12)).padding(.top, 20)
                        }.padding(24)
                    }
                }
            }.toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { editing = true } label: { Image(systemName: "pencil") }.accessibilityLabel("Edit journal entry") }
            }.sheet(isPresented: $editing) { if let entry { JournalEditor(anime: anime, library: library, entry: entry) } }
                .confirmationDialog("Delete this journal entry?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete entry", role: .destructive) { library.deleteJournal(entryID, animeID: anime.id); dismiss() }
                } message: { Text("The note will be removed. Any streak credit earned only from this entry will also be removed.") }
        }.preferredColorScheme(.dark)
    }
}

struct JournalEditor: View {
    var anime: Anime
    var library: Library
    private let original: JournalEntry
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JournalEntry
    @State private var error: String?
    @State private var discard = false
    init(anime: Anime, library: Library, entry: JournalEntry? = nil) {
        self.anime = anime; self.library = library
        let value = entry ?? JournalEntry(); original = value; _draft = State(initialValue: value)
    }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                Form {
                    Section {
                        HStack(spacing: 13) {
                            Poster(anime: anime).frame(width: 43, height: 62).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 7) { Eyebrow(text: "YOUR ANIME JOURNAL"); Text(anime.displayTitle).font(.system(size: 15, weight: .semibold)) }
                        }.padding(.vertical, 5)
                        TextField("Give this moment a title", text: $draft.title).font(.system(size: 23, design: .serif))
                        ZStack(alignment: .topLeading) {
                            if draft.body.isEmpty { Text("The scene you can’t forget. How it made you feel. A theory for the next episode…").foregroundStyle(YoruTheme.muted).padding(.top, 9).padding(.leading, 5).allowsHitTesting(false) }
                            TextEditor(text: $draft.body).scrollContentBackground(.hidden).frame(minHeight: 200).font(.system(size: 16)).lineSpacing(5).accessibilityLabel("Journal text")
                        }
                    }.listRowBackground(Color.white.opacity(0.04))
                    Section("The moment") {
                        DatePicker("Watched on", selection: $draft.watchedOn, in: ...Date.now, displayedComponents: .date)
                        Toggle("Add an episode", isOn: Binding(get: { draft.episode != nil }, set: { draft.episode = $0 ? 1 : nil }))
                        if draft.episode != nil {
                            Stepper("Episode \(draft.episode ?? 1)", value: Binding(get: { draft.episode ?? 1 }, set: { draft.episode = $0 }), in: 1...max(1, anime.episodes ?? 9999))
                        }
                        Toggle("Contains spoilers", isOn: $draft.containsSpoilers)
                    }.listRowBackground(Color.white.opacity(0.04))
                    Section("How did it feel?") {
                        Picker("Mood", selection: $draft.mood) {
                            Text("No mood").tag(Optional<JournalMood>.none)
                            ForEach(JournalMood.allCases) { mood in Label(mood.rawValue, systemImage: mood.symbol).tag(Optional(mood)) }
                        }
                        Toggle("Rate this moment", isOn: Binding(get: { draft.rating != nil }, set: { draft.rating = $0 ? 8 : nil }))
                        if draft.rating != nil {
                            Stepper("\(draft.rating ?? 8) / 10", value: Binding(get: { draft.rating ?? 8 }, set: { draft.rating = $0 }), in: 1...10)
                        }
                    }.listRowBackground(Color.white.opacity(0.04))
                    if let error { Section { Text(error).foregroundStyle(.orange) }.listRowBackground(Color.white.opacity(0.04)) }
                    Section { Text("Private, on this device. Saving a new or changed entry counts toward today’s streak, even if you write about an earlier watch date.").font(.system(size: 11)).foregroundStyle(YoruTheme.muted) }.listRowBackground(Color.clear)
                }.scrollContentBackground(.hidden)
            }.navigationTitle("Write a little.").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if draft != original { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try library.saveJournal(draft, for: anime); if let issue = library.saveError { error = issue } else { dismiss() } }
                            catch { self.error = error.localizedDescription }
                        }.disabled(!canSave)
                    }
                }.interactiveDismissDisabled(draft != original)
                .confirmationDialog("Discard your unsaved changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
        }.preferredColorScheme(.dark)
    }
}

struct WatchMetadataEditor: View {
    var anime: Anime
    var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var first: Date
    @State private var finished: Date
    @State private var hasFirst: Bool
    @State private var hasFinished: Bool
    @State private var rating: Int
    @State private var hasRating: Bool
    @State private var status: WatchStatus?
    @State private var error: String?
    init(anime: Anime, library: Library) {
        self.anime = anime; self.library = library
        let entry = library.entries[anime.id]
        _first = State(initialValue: entry?.firstWatched ?? .now); _finished = State(initialValue: entry?.finishedWatched ?? .now)
        _hasFirst = State(initialValue: entry?.firstWatched != nil); _hasFinished = State(initialValue: entry?.finishedWatched != nil)
        _rating = State(initialValue: entry?.personalRating ?? 8); _hasRating = State(initialValue: entry?.personalRating != nil)
        _status = State(initialValue: entry?.watchStatus)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(anime.displayTitle) {
                    Picker("My status", selection: $status) {
                        Text("Not set").tag(Optional<WatchStatus>.none)
                        ForEach(WatchStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Toggle("First watched", isOn: $hasFirst)
                    if hasFirst { DatePicker("First-watched date", selection: $first, in: ...Date.now, displayedComponents: .date) }
                    Toggle("Finished watching", isOn: $hasFinished)
                    if hasFinished { DatePicker("Finished date", selection: $finished, in: ...Date.now, displayedComponents: .date) }
                    Toggle("My rating", isOn: $hasRating)
                    if hasRating { Stepper("\(rating) / 10", value: $rating, in: 1...10) }
                }
                if let error { Text(error).foregroundStyle(.orange) }
                Text("You can record an earlier watch date. Dates and ratings do not add days to your streak.").font(.system(size: 12)).foregroundStyle(.secondary)
            }.navigationTitle("Your watch history").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                try library.setMetadata(anime, first: hasFirst ? first : nil, finished: hasFinished ? finished : nil, rating: hasRating ? rating : nil, status: status)
                                if let issue = library.saveError { error = issue } else { dismiss() }
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
        }.preferredColorScheme(.dark)
    }
}

struct AnimeJournalSection: View {
    var anime: Anime
    var library: Library
    @State private var writing = false
    @State private var metadata = false
    @State private var reading: JournalItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Your journal", trailing: "\(library.journal(for: anime).count) PAGES")
            if let record = library.entries[anime.id] {
                HStack(spacing: 12) {
                    if let first = record.firstWatched { Label(first.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar") }
                    if let rating = record.personalRating { Label("\(rating)/10", systemImage: "star.fill") }
                }.font(.system(size: 11)).foregroundStyle(YoruTheme.mint)
            }
            HStack {
                Button { writing = true } label: { Label("Write an entry", systemImage: "square.and.pencil") }.buttonStyle(.glassProminent)
                Button { metadata = true } label: { Image(systemName: "calendar.badge.clock") }.buttonStyle(.glass).accessibilityLabel("Edit first-watched date, status, and rating")
            }.font(.system(size: 12, weight: .semibold))
            ForEach(library.journal(for: anime).prefix(3)) { entry in
                let item = JournalItem(anime: anime, entry: entry)
                JournalCard(item: item) { reading = item }
            }
            if library.journal(for: anime).isEmpty { Text("Keep the moments that stay with you.").font(.system(size: 12)).foregroundStyle(YoruTheme.muted) }
        }.sheet(isPresented: $writing) { JournalEditor(anime: anime, library: library) }
            .sheet(isPresented: $metadata) { WatchMetadataEditor(anime: anime, library: library) }
            .sheet(item: $reading) { JournalReader(anime: $0.anime, entryID: $0.entry.id, library: library) }
    }
}
