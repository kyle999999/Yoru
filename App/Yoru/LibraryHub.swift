import SwiftUI

extension LibraryCollection {
    var tint: Color {
        switch color { case "mint": YoruTheme.mint; case "rose": .pink; case "amber": .orange; case "blue": .cyan; default: YoruTheme.violet }
    }
}

struct LibraryScreen: View {
    enum Shelf: String, CaseIterable { case shows = "Shows", journal = "Journal", collections = "Collections" }
    var library: Library
    @State private var search = ""
    @State private var statusFilter: WatchStatus?
    @State private var shelf = Shelf.shows
    @State private var collectionID: UUID?
    @State private var selection: Anime?
    @State private var writing: Anime?
    @State private var history: Anime?
    @State private var organizing: Anime?
    @State private var reading: JournalItem?
    @State private var editingCollection: LibraryCollection?
    @State private var picking = false
    @State private var pendingWrite: Anime?
    @State private var showingStreak = false
    @State private var writeAfterStreak = false
    private var selectedCollection: LibraryCollection? { library.collections.first { $0.id == collectionID } }
    private var shows: [Anime] {
        (selectedCollection.map { library.collectionAnime($0) } ?? library.saved).filter {
            (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines)) || $0.title.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines))) &&
            (statusFilter == nil || library.entries[$0.id]?.watchStatus == statusFilter)
        }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        PageHeader(eyebrow: "COLLECT STORIES. KEEP THE FEELING.", title: "A world\nof your own.", subtitle: "Your shows, your shelves, your little midnight journal.")
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            let streak = library.streak(now: context.date)
                            Button { showingStreak = true } label: {
                                HStack(spacing: 17) {
                                    ZStack {
                                        Circle().fill(YoruTheme.violet.opacity(0.16)).frame(width: 59, height: 59)
                                        Image(systemName: streak.activeToday ? "flame.fill" : "moon.stars.fill").font(.system(size: 26, weight: .light)).foregroundStyle(streak.activeToday ? YoruTheme.mint : YoruTheme.violet)
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(streak.current == 0 ? "A little every day." : "\(streak.current)-day glow").font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(-0.5)
                                        Text(streak.activeToday ? "Today’s story is part of your streak." : "Tap to check in and light up today.").font(.system(size: 11)).foregroundStyle(YoruTheme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").font(.system(size: 13))
                                }.padding(19).frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).foregroundStyle(.white).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
                        }
                        HStack(spacing: 0) {
                            tinyStat(library.saved.count, "SHOWS")
                            tinyStat(library.journals.count, "PAGES")
                            tinyStat(library.episodeCount, "EPISODES")
                        }.padding(.vertical, 4)
                        Picker("Library section", selection: $shelf) { ForEach(Shelf.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        if let error = library.saveError { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
                        switch shelf {
                        case .shows: showShelf
                        case .journal: journalShelf
                        case .collections: collectionShelf
                        }
                        Text("YOUR STORIES STAY ON THIS DEVICE").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.7).foregroundStyle(YoruTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
                    }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 24)
                }
            }.toolbar(.hidden, for: .navigationBar)
                .sheet(item: $selection) { DetailScreen(initial: $0, library: library) }
                .sheet(item: $writing) { JournalEditor(anime: $0, library: library) }
                .sheet(item: $history) { WatchMetadataEditor(anime: $0, library: library) }
                .sheet(item: $organizing) { CollectionMembershipScreen(anime: $0, library: library) }
                .sheet(item: $reading) { JournalReader(anime: $0.anime, entryID: $0.entry.id, library: library) }
                .sheet(item: $editingCollection) { CollectionEditor(library: library, collection: $0) }
                .sheet(isPresented: $picking, onDismiss: { if let pendingWrite { writing = pendingWrite; self.pendingWrite = nil } }) {
                    JournalAnimePicker(library: library) { anime in pendingWrite = anime; picking = false }
                }
                .sheet(isPresented: $showingStreak, onDismiss: { if writeAfterStreak { shelf = .journal; picking = true; writeAfterStreak = false } }) {
                    StreakScreen(library: library) { writeAfterStreak = true; showingStreak = false }
                }
        }
    }
    private var showShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !library.collections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        Button { collectionID = nil } label: { Text("All saved").font(.system(size: 12, weight: .semibold)).padding(.vertical, 6) }.buttonStyle(.glass).tint(collectionID == nil ? YoruTheme.violet : .white)
                        ForEach(library.collections) { collection in
                            Button { collectionID = collection.id } label: { Label(collection.name, systemImage: collection.symbol).font(.system(size: 12)).padding(.vertical, 6) }.buttonStyle(.glass).tint(collectionID == collection.id ? collection.tint : .white)
                        }
                    }.padding(.vertical, 5)
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(YoruTheme.violet)
                TextField("Search your library", text: $search).autocorrectionDisabled()
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear library search") }
                Menu {
                    Button("All statuses") { statusFilter = nil }
                    ForEach(WatchStatus.allCases) { status in Button(status.rawValue) { statusFilter = status } }
                } label: { Label(statusFilter?.rawValue ?? "Status", systemImage: "line.3.horizontal.decrease") }
            }.font(.system(size: 13)).padding(15).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            SectionHeading(title: selectedCollection?.name ?? "Your watchlist", trailing: "\(shows.count) STORIES")
            if shows.isEmpty {
                ContentUnavailableView(!search.isEmpty || statusFilter != nil ? "No matching stories" : selectedCollection == nil ? "Your story starts here" : "An empty shelf, for now", systemImage: "bookmark", description: Text(!search.isEmpty || statusFilter != nil ? "Try another search or select All statuses." : "Save an anime from Explore, then use Organize to place it in a collection."))
            }
            ForEach(shows) { anime in
                VStack(spacing: 10) {
                    AnimeRow(anime: anime, library: library, showProgress: true) { selection = anime }
                    HStack(spacing: 10) {
                        Button { writing = anime } label: { Label("Journal", systemImage: "square.and.pencil") }
                        Button { history = anime } label: { Label("Dates", systemImage: "calendar") }
                        Button { organizing = anime } label: { Label("Organize", systemImage: "folder") }
                        Spacer(minLength: 0)
                    }.font(.system(size: 10, weight: .medium)).buttonStyle(.glass).padding(.horizontal, 3)
                }
            }
        }
    }
    private var journalShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { SectionHeading(title: "A few words, forever."); Button { picking = true } label: { Image(systemName: "plus") }.buttonStyle(.glass).accessibilityLabel("New journal entry") }
            if library.journals.isEmpty {
                ContentUnavailableView("Keep the feeling", systemImage: "book.closed", description: Text("Write about an episode, a character, or the scene that stayed with you."))
                Button { picking = true } label: { Label("Write your first page", systemImage: "square.and.pencil") }.buttonStyle(.glassProminent).frame(maxWidth: .infinity)
            }
            ForEach(library.journals) { item in JournalCard(item: item) { reading = item } }
        }
    }
    private var collectionShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeading(title: "Make a little space.")
                Button { editingCollection = LibraryCollection(name: "") } label: { Image(systemName: "plus") }.buttonStyle(.glass).accessibilityLabel("New collection")
            }
            if library.collections.isEmpty {
                ContentUnavailableView("A shelf for every mood", systemImage: "square.stack.3d.up", description: Text("Create playlists like Cozy nights, Next up, or All-time favorites. A show can belong to more than one."))
                Button("Create a collection") { editingCollection = LibraryCollection(name: "") }.buttonStyle(.glassProminent).frame(maxWidth: .infinity)
            }
            ForEach(library.collections) { collection in
                HStack(spacing: 14) {
                    Button {
                        collectionID = collection.id; shelf = .shows
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: collection.symbol).font(.system(size: 22, weight: .light)).foregroundStyle(collection.tint).frame(width: 53, height: 60).background(collection.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 7) { Text(collection.name).font(.system(size: 20, weight: .medium, design: .rounded)); Text("\(collection.animeIDs.count) stories").font(.system(size: 11)).foregroundStyle(YoruTheme.muted) }
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.white)
                    Button { editingCollection = collection } label: { Image(systemName: "ellipsis") }.buttonStyle(.glass).accessibilityLabel("Edit \(collection.name)")
                }.padding(17).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 25))
            }
        }
    }
    private func tinyStat(_ count: Int, _ label: String) -> some View {
        VStack(spacing: 7) { Text(String(count)).font(.system(size: 25, weight: .medium, design: .rounded)); Text(label).font(.system(size: 8, design: .monospaced)).tracking(1.5).foregroundStyle(YoruTheme.muted) }.frame(maxWidth: .infinity)
    }
}

struct JournalAnimePicker: View {
    var library: Library
    var choose: (Anime) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                if library.saved.isEmpty { ContentUnavailableView("Choose a story first", systemImage: "bookmark", description: Text("Save an anime in Explore, or open any title’s details and tap Write an entry.")) }
                ForEach(library.saved.filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) }) { anime in
                    Button { choose(anime) } label: {
                        HStack(spacing: 12) { Poster(anime: anime).frame(width: 39, height: 55).clipShape(RoundedRectangle(cornerRadius: 8)); Text(anime.displayTitle).font(.system(size: 15, weight: .medium)).foregroundStyle(.white) }
                    }
                }
            }.searchable(text: $query, prompt: "Find a saved story").navigationTitle("What are we writing about?").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct CollectionMembershipScreen: View {
    var anime: Anime
    var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    var body: some View {
        NavigationStack {
            List {
                Section(anime.displayTitle) {
                    if library.collections.isEmpty { Text("Create your first collection below.").foregroundStyle(.secondary) }
                    ForEach(library.collections) { collection in
                        Toggle(isOn: Binding(get: { library.collections.first { $0.id == collection.id }?.animeIDs.contains(anime.id) ?? false }, set: { library.setMembership(anime, collectionID: collection.id, included: $0) })) {
                            Label(collection.name, systemImage: collection.symbol).foregroundStyle(collection.tint)
                        }
                    }
                    Button { creating = true } label: { Label("New collection", systemImage: "plus") }
                }
                if let error = library.saveError { Text(error).foregroundStyle(.orange) }
                Text("A story can live on several shelves. Changes save immediately.").font(.system(size: 12)).foregroundStyle(.secondary)
            }.navigationTitle("Organize your story").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $creating) { CollectionEditor(library: library, collection: LibraryCollection(name: "")) }
        }.preferredColorScheme(.dark)
    }
}

struct CollectionEditor: View {
    var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LibraryCollection
    @State private var error: String?
    @State private var deleting = false
    private var existing: Bool { library.collections.contains { $0.id == draft.id } }
    init(library: Library, collection: LibraryCollection) { self.library = library; _draft = State(initialValue: collection) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); Image(systemName: draft.symbol).font(.system(size: 40, weight: .light)).foregroundStyle(draft.tint).frame(height: 90); Spacer() }
                    TextField("Collection name", text: $draft.name)
                }
                Section("Make it yours") {
                    Picker("Symbol", selection: $draft.symbol) { ForEach(LibraryCollection.symbols, id: \.self) { Image(systemName: $0).tag($0) } }
                    Picker("Color", selection: $draft.color) { ForEach(LibraryCollection.colors, id: \.self) { Text($0.capitalized).tag($0) } }
                }
                if let error { Text(error).foregroundStyle(.orange) }
                if existing { Button("Delete collection", role: .destructive) { deleting = true } }
            }.navigationTitle(existing ? "Your collection" : "A new little shelf").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { do { try library.saveCollection(draft); if let issue = library.saveError { error = issue } else { dismiss() } } catch { self.error = error.localizedDescription } }.disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.confirmationDialog("Delete this collection?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete collection", role: .destructive) { library.deleteCollection(draft.id); dismiss() } } message: { Text("Your shows, journal entries, and progress will stay in your library.") }
        }.preferredColorScheme(.dark)
    }
}
