import SwiftUI

struct ContentView: View {
    @State private var library = Library()
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCheckIn = false
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Tonight", systemImage: "moon.stars", value: 0) { TonightScreen(library: library) }
            Tab("Calendar", systemImage: "calendar", value: 1) { CalendarScreen(library: library) }
            Tab("Explore", systemImage: "sparkle.magnifyingglass", value: 2) { ExploreScreen(library: library) }
            Tab("Library", systemImage: "square.stack", value: 3) { LibraryScreen(library: library) }
            Tab("aidoku", systemImage: "books.vertical", value: 4) { Color.clear }
        }.onChange(of: selectedTab) { old, value in
            if value == 4 { selectedTab = old; AidokuIntegration.present() }
        }.tint(YoruTheme.violet).preferredColorScheme(.dark)
            .tabBarMinimizeBehavior(.onScrollDown)
            .sheet(isPresented: $showCheckIn) { DailyCheckInScreen(library: library) }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                repeat {
                    if !showCheckIn, library.claimDailyPrompt() { showCheckIn = true }
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                } while !Task.isCancelled
            }
    }
}

struct TonightScreen: View {
    var library: Library
    @State private var store = CatalogStore()
    @State private var selection: Anime?
    @State private var showSources = false
    private var season: Season { .current() }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 16)] }
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        PageHeader(eyebrow: "\(season.label) · ON YOUR RADAR", title: "Your night.\nA whole new world.", subtitle: "This season’s stories, all in one place.")
                        if let featured = store.items.first(where: { $0.airing == true && $0.type == "TV" }) ?? store.items.first { hero(featured) }
                        if !library.saved.isEmpty {
                            SectionHeading(title: "Continue your story", trailing: "YOUR LIBRARY")
                            ForEach(library.saved.prefix(2)) { anime in AnimeRow(anime: anime, library: library, showProgress: true) { selection = anime } }
                        }
                        HStack {
                            SectionHeading(title: "The season, in full", trailing: "\(store.items.count) TITLES")
                            Button { showSources = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About catalog sources")
                        }
                        Text("Includes TV, streaming originals, films, and specials debuting this season. See Calendar for continuing broadcasts.")
                            .font(.system(size: 12)).foregroundStyle(YoruTheme.muted)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(store.items) { anime in AnimeCard(anime: anime, library: library) { selection = anime } }
                        }
                        CatalogStatus(store: store) { await load(refresh: true) }
                        SourceFooter(date: store.fetchedAt)
                    }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 20)
                }.refreshable { await load(refresh: true) }
            }.toolbar(.hidden, for: .navigationBar)
                .task { if store.items.isEmpty { await load() } }
                .sheet(item: $selection) { DetailScreen(initial: $0, library: library) }
                .sheet(isPresented: $showSources) { SourcesScreen() }
        }
    }
    private func load(refresh: Bool = false) async {
        await store.load(path: "seasons/\(season.year)/\(season.name)", allPages: true, refresh: refresh)
    }
    private func hero(_ anime: Anime) -> some View {
        Button { selection = anime } label: {
            ZStack(alignment: .bottomLeading) {
                Poster(anime: anime).frame(height: 390)
                LinearGradient(stops: [.init(color: .clear, location: 0.1), .init(color: .black.opacity(0.25), location: 0.4), .init(color: .black.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 14) {
                    HStack { StatusPill(title: anime.statusLabel, live: anime.airing == true); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 15)).padding(12).glassEffect(.regular, in: .circle) }
                    Spacer()
                    Eyebrow(text: "THE SEASON’S SPOTLIGHT", color: YoruTheme.mint)
                    Text(anime.displayTitle).font(.system(size: 33, weight: .semibold, design: .rounded)).tracking(-1).lineLimit(3).multilineTextAlignment(.leading)
                    HStack { Text("\(anime.type ?? "Anime") · \(anime.episodeLabel)").font(.system(size: 12)); Spacer(); Text("EXPLORE STORY").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4) }.foregroundStyle(.white.opacity(0.7))
                }.padding(23)
            }.frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 31))
                .overlay(RoundedRectangle(cornerRadius: 31).stroke(.white.opacity(0.15), lineWidth: 0.8))
        }.buttonStyle(.plain).foregroundStyle(.white).accessibilityLabel("Featured: \(anime.displayTitle). Open details")
    }
}

struct ExploreScreen: View {
    var library: Library
    @State private var store = CatalogStore()
    @State private var scope = CatalogScope.season
    @State private var season = Season.current()
    @State private var query = ""
    @State private var provider = ""
    @State private var selection: Anime?
    private var requestKey: String { "\(scope.rawValue)-\(season.label)-\(provider)-\(query.trimmingCharacters(in: .whitespacesAndNewlines))" }
    private var currentYear: Int { Season.current().year }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 16)] }
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        PageHeader(eyebrow: "BEYOND THE WATCHLIST", title: "Find your\nnext obsession.", subtitle: "Seasonal discoveries. Old favorites. Endless stories.")
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").foregroundStyle(YoruTheme.violet)
                            TextField("Search the anime catalog", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.search)
                            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                        }.padding(17).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                        Picker("Browse", selection: $scope) { ForEach(CatalogScope.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        Menu {
                            Picker("Streaming provider", selection: $provider) {
                                Text("All providers").tag("")
                                ForEach(["Crunchyroll", "HIDIVE", "Netflix", "Hulu", "Amazon", "YouTube", "TubiTV"], id: \.self) { Text($0).tag($0) }
                            }
                        } label: { Label(provider.isEmpty ? "All streaming sources" : provider, systemImage: "play.rectangle.on.rectangle").font(.system(size: 13, weight: .medium)) }.buttonStyle(.glass)
                        if !provider.isEmpty { Text("Showing titles linked to \(provider) by Kitsu. Links can be outdated or region-specific.").font(.system(size: 11)).foregroundStyle(YoruTheme.muted) }
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, scope == .season {
                            HStack {
                                Menu {
                                    Picker("Season", selection: $season.name) { ForEach(Season.names, id: \.self) { Text($0.capitalized).tag($0) } }
                                } label: { Label(season.name.capitalized, systemImage: "sparkles").font(.system(size: 13, weight: .semibold)) }.buttonStyle(.glass)
                                Spacer()
                                Stepper(value: $season.year, in: 1960...(currentYear + 1)) { Text(String(season.year)).font(.system(size: 15, weight: .semibold, design: .monospaced)) }.fixedSize()
                            }
                        }
                        SectionHeading(title: query.isEmpty ? (scope == .season ? season.label : scope == .airing ? "On air, everywhere" : "Already unforgettable") : "Search results", trailing: "\(store.items.count)\(store.hasMore ? "+" : "") TITLES")
                        if !query.isEmpty { Text("Search spans the full catalog, including earlier seasons and upcoming titles.").font(.system(size: 12)).foregroundStyle(YoruTheme.muted) }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(store.items) { anime in AnimeCard(anime: anime, library: library) { selection = anime } }
                        }
                        CatalogStatus(store: store) { await load(refresh: true) }
                        if !store.isLoading, store.error == nil, store.items.isEmpty {
                            ContentUnavailableView("No stories found", systemImage: "sparkle.magnifyingglass", description: Text("Try another title or season."))
                        }
                        if store.hasMore, !store.isLoading {
                            Button("Load more anime") { Task { await store.loadMore() } }.buttonStyle(.glass).frame(maxWidth: .infinity)
                        }
                        SourceFooter(date: store.fetchedAt)
                    }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 20)
                }.refreshable { await load(refresh: true) }
            }.toolbar(.hidden, for: .navigationBar)
                .task(id: requestKey) {
                    if !query.isEmpty {
                        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                    }
                    await load()
                }
                .sheet(item: $selection) { DetailScreen(initial: $0, library: library) }
        }
    }
    private func load(refresh: Bool = false) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { await store.load(path: "anime", parameters: ["q": text, "provider": provider], refresh: refresh) }
        else {
            switch scope {
            case .season: await store.load(path: "seasons/\(season.year)/\(season.name)", parameters: ["provider": provider], allPages: true, refresh: refresh)
            case .airing: await store.load(path: "anime", parameters: ["status": "airing", "provider": provider], allPages: true, refresh: refresh)
            case .archive: await store.load(path: "anime", parameters: ["status": "complete", "provider": provider], refresh: refresh)
            }
        }
    }
}

struct CalendarScreen: View {
    var library: Library
    @State private var store = ScheduleStore()
    @State private var onlySaved = false
    @State private var day = BroadcastDay.todayInJapan
    @State private var selection: Anime?
    @State private var sources = false
    private var titles: [Anime] { (store.week?.titles(for: day) ?? []).filter { !onlySaved || library.isSaved($0) } }
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        PageHeader(eyebrow: "A WEEK OF NEW WORLDS", title: "Make room\nfor one more.", subtitle: "Your weekly broadcast guide. Find a story for every night.")
                        GlassEffectContainer(spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(BroadcastDay.allCases) { value in
                                        Button { withAnimation(.snappy) { day = value } } label: {
                                            VStack(spacing: 8) {
                                                Text(value.label).font(.system(size: 12, weight: .semibold))
                                                Circle().fill(day == value ? YoruTheme.mint : .clear).frame(width: 4, height: 4)
                                            }.frame(width: 40, height: 47)
                                        }.buttonStyle(.glass).tint(day == value ? YoruTheme.violet : .white).accessibilityLabel(value.rawValue.capitalized)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionHeading(title: day.rawValue == "unknown" ? "Time to be announced" : day.rawValue == "other" ? "All ongoing broadcasts" : day.rawValue.capitalized)
                                Text("MyAnimeList weekly schedule · Japan broadcast days").font(.system(size: 11)).foregroundStyle(YoruTheme.muted)
                            }
                            Button { sources = true } label: { Image(systemName: "info.circle") }.buttonStyle(.glass).accessibilityLabel("Schedule sources and time zones")
                        }
                        HStack {
                            Toggle("My library", isOn: $onlySaved).toggleStyle(.button).buttonStyle(.glass)
                            Spacer()
                            Button("Today") { day = .todayInJapan }.buttonStyle(.glass)
                            Button { Task { await load(refresh: true) } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.glass).disabled(store.isLoading).accessibilityLabel("Refresh weekly schedule")
                            Text("\(titles.count) SHOWS").font(.system(size: 10, design: .monospaced)).foregroundStyle(YoruTheme.muted)
                        }
                        ForEach(titles) { anime in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(spacing: 8) {
                                    Circle().fill(YoruTheme.mint).frame(width: 5, height: 5)
                                    Text(anime.broadcast?.day ?? "DAY TBA").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(YoruTheme.mint)
                                    if let next = anime.nextRelease {
                                        Text("· \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute())) locally").font(.system(size: 10)).foregroundStyle(YoruTheme.muted)
                                    }
                                }.padding(.leading, 8)
                                AnimeRow(anime: anime, library: library) { selection = anime }
                            }
                        }
                        if store.isLoading { HStack { ProgressView(); Text(store.week == nil ? "Loading this week’s schedule…" : "Refreshing this week…").font(.system(size: 12)) }.padding(.vertical) }
                        if let error = store.error {
                            Label("Schedule unavailable", systemImage: "wifi.exclamationmark").font(.headline)
                            Text(error).font(.caption).foregroundStyle(YoruTheme.muted)
                            Button("Retry schedule") { Task { await load(refresh: true) } }.buttonStyle(.glass)
                        }
                        if store.isStale { Label("Offline · showing the last saved week", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(YoruTheme.violet) }
                        if !store.isLoading, store.error == nil, store.week != nil, titles.isEmpty {
                            ContentUnavailableView(onlySaved ? "No saved shows on this day" : "No listings supplied", systemImage: "calendar", description: Text(onlySaved ? "Turn off My library to see all broadcasts." : "This source has no entries in this group. Streaming premieres can differ; check the official calendars below."))
                        }
                        if let date = store.week?.fetchedAt { Text("Week retrieved \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(YoruTheme.muted) }
                        officialCalendars
                    }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 20)
                }.refreshable { await load(refresh: true) }
            }.toolbar(.hidden, for: .navigationBar)
                .task { if store.week == nil { await load() } }
                .sheet(item: $selection) { DetailScreen(initial: $0, library: library) }
                .sheet(isPresented: $sources) { SourcesScreen() }
        }
    }
    private var officialCalendars: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Straight from the source")
            Text("For exact subtitled and dubbed release times in your region, check the streaming service.")
                .font(.system(size: 12)).foregroundStyle(YoruTheme.muted)
            Link(destination: URL(string: "https://www.crunchyroll.com/simulcastcalendar")!) {
                HStack { Text("Crunchyroll").font(.system(size: 17, weight: .bold, design: .rounded)); Spacer(); Text("Release calendar").font(.system(size: 11)); Image(systemName: "arrow.up.right") }.foregroundStyle(.orange).padding(18)
            }.buttonStyle(.glass)
            Link("Weekly schedule · MyAnimeList ↗", destination: URL(string: "https://myanimelist.net/anime/season/schedule")!).font(.system(size: 13)).buttonStyle(.glass)
            HStack(spacing: 10) {
                Link("HIDIVE ↗", destination: URL(string: "https://www.hidive.com")!).buttonStyle(.glass)
                Link("Netflix ↗", destination: URL(string: "https://www.netflix.com/browse/genre/7424")!).buttonStyle(.glass)
            }.font(.system(size: 13, weight: .semibold))
        }.padding(.top, 16)
    }
    private func load(refresh: Bool = false) async { await store.load(refresh: refresh) }
}

struct SourcesScreen: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Eyebrow(text: "OPEN WORLDS, HONEST SOURCES")
                        Text("A little context.").font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-1)
                        Text("Yoru uses Kitsu’s public anime catalog and streaming-link data. Explicit adult entries are excluded. Seasonal catalogs load every available page. The archive and global search load more results as you browse.")
                        Text("The calendar reads MyAnimeList’s public weekly broadcast schedule in a single request and caches the week for six hours. Days follow Japan’s broadcast week, not your local day. Exact times are not supplied here. All includes other and unknown-day listings. This is not a guarantee of streaming premieres: delays, batch releases, dubs, and regional differences may apply.")
                        Text("Streaming links are listed only when Kitsu provides them for that title. A missing provider means the data is unknown, not that the title is unavailable. Availability, subscription requirements, and languages depend on your region.")
                        Text("Cached results can be shown offline and are labeled. Pull down to refresh. Catalog responses are refreshed after six hours or when you pull to refresh.")
                        Link("About Kitsu ↗", destination: URL(string: "https://kitsu.app")!)
                        Link("MyAnimeList ↗", destination: URL(string: "https://myanimelist.net")!)
                        Text("Your watchlist and progress are stored locally. Search terms and catalog requests are sent to Kitsu. Weekly schedule requests and some cover artwork load from MyAnimeList. Check-ins stay on this device.").font(.system(size: 12)).foregroundStyle(YoruTheme.muted)
                    }.font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)).padding(24)
                }
            }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.presentationDragIndicator(.visible).preferredColorScheme(.dark)
    }
}
