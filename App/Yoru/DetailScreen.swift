import SwiftUI

struct DetailScreen: View {
    let initial: Anime
    var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var detail: Anime?
    @State private var isLoading = true
    @State private var error: String?
    @State private var fetchedAt: Date?
    @State private var stale = false
    @State private var showSources = false
    @State private var organizing = false
    private var anime: Anime { detail ?? initial }
    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        posterHeader
                        VStack(alignment: .leading, spacing: 13) {
                            Eyebrow(text: [anime.seasonLabel, anime.type].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            Text(anime.displayTitle).font(.system(size: 33, weight: .semibold, design: .rounded)).tracking(-1).fixedSize(horizontal: false, vertical: true)
                            if let japanese = anime.titleJapanese { Text(japanese).font(.system(size: 14)).foregroundStyle(YoruTheme.muted) }
                            HStack(spacing: 14) {
                                if let score = anime.score, score > 0 { Label(score.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill").foregroundStyle(YoruTheme.mint) }
                                Text(anime.episodeLabel).foregroundStyle(YoruTheme.muted)
                            }.font(.system(size: 12, weight: .medium))
                        }
                        watchProgress
                        AnimeJournalSection(anime: anime, library: library)
                        streamingSources
                        if let synopsis = anime.synopsis, !synopsis.isEmpty {
                            VStack(alignment: .leading, spacing: 13) {
                                SectionHeading(title: "The story")
                                Text(synopsis).font(.system(size: 14)).lineSpacing(6).foregroundStyle(.white.opacity(0.72)).textSelection(.enabled)
                            }
                        }
                        if let genres = anime.genres, !genres.isEmpty {
                            Text(genres.map(\.name).joined(separator: "  ·  ")).font(.system(size: 11, weight: .medium)).foregroundStyle(YoruTheme.violet)
                        }
                        if let studios = anime.studios, !studios.isEmpty {
                            VStack(alignment: .leading, spacing: 7) { Eyebrow(text: "ANIMATION"); Text(studios.map(\.name).joined(separator: ", ")).font(.system(size: 14)) }
                        }
                        if let broadcast = anime.broadcast, let schedule = broadcast.string {
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: anime.nextRelease == nil ? "WEEKLY BROADCAST GUIDE" : "NEXT LISTED RELEASE")
                                Text(schedule).font(.system(size: 14))
                                if anime.airing == true, let next = anime.nextRelease {
                                    Text("Listed next release: \(next.formatted(date: .abbreviated, time: .shortened)) in your time zone.").font(.system(size: 12)).foregroundStyle(YoruTheme.muted)
                                }
                                Text("Streaming release times may differ.").font(.system(size: 11)).foregroundStyle(YoruTheme.muted)
                            }
                        }
                        if let url = URL(string: anime.url ?? ""), url.scheme == "https" {
                            Link(destination: url) { Label("View source on \(anime.sourceName ?? "Kitsu")", systemImage: "arrow.up.right") }.buttonStyle(.glass).font(.system(size: 13))
                        }
                        Button("About sources & availability") { showSources = true }.font(.system(size: 12))
                        SourceFooter(date: fetchedAt)
                    }.padding(.horizontal, 22).padding(.bottom, 24)
                }.refreshable { await load(refresh: true) }
            }.toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { organizing = true } label: { Image(systemName: "folder.badge.plus") }.accessibilityLabel("Organize into collections") }
                ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close anime details") }
            }.task { await load() }
                .sheet(isPresented: $showSources) { SourcesScreen() }
                .sheet(isPresented: $organizing) { CollectionMembershipScreen(anime: anime, library: library) }
        }.presentationDragIndicator(.visible).preferredColorScheme(.dark)
    }
    private var posterHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Poster(anime: anime).frame(height: 340)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            HStack {
                StatusPill(title: anime.statusLabel, live: anime.airing == true)
                Spacer()
                Button { withAnimation(.snappy) { library.toggle(anime) } } label: {
                    Label(library.isSaved(anime) ? "Saved" : "Save", systemImage: library.isSaved(anime) ? "bookmark.fill" : "bookmark").font(.system(size: 12, weight: .semibold))
                }.buttonStyle(.glass)
            }.padding(18)
        }.frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 28))
    }
    private var watchProgress: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Eyebrow(text: "YOUR JOURNEY")
                Spacer()
                Text("\(library.watched(anime)) / \(anime.episodes.map(String.init) ?? "?")").font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            if let count = anime.episodes, count > 0 {
                ProgressView(value: Double(library.watched(anime)), total: Double(count)).tint(YoruTheme.violet)
            }
            HStack {
                Button { library.log(anime, delta: -1) } label: { Image(systemName: "minus").frame(width: 28, height: 30) }.buttonStyle(.glass).disabled(library.watched(anime) == 0).accessibilityLabel("Undo last episode")
                Button { withAnimation(.snappy) { library.log(anime) } } label: {
                    Label(anime.episodes.map { library.watched(anime) >= $0 } == true ? "Completed" : "Log an episode", systemImage: "checkmark").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.glassProminent).disabled(anime.episodes.map { library.watched(anime) >= $0 } == true)
            }
            if let error = library.saveError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
        }.padding(20).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 25))
    }
    private var streamingSources: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Where to watch", trailing: "STREAMING SOURCES")
            if isLoading { HStack { ProgressView().controlSize(.small); Text("Checking listed providers…").font(.system(size: 12)).foregroundStyle(YoruTheme.muted) } }
            if let error {
                Text("Streaming sources couldn’t be checked. \(error)").font(.system(size: 12)).foregroundStyle(YoruTheme.muted)
                Button("Retry sources") { Task { await load(refresh: true) } }.buttonStyle(.glass)
            } else if !isLoading, anime.safeStreaming.isEmpty {
                Label("No streaming links listed yet", systemImage: "play.rectangle.on.rectangle").font(.system(size: 14, weight: .medium))
                Text("This does not mean the anime is unavailable. Check Kitsu or your local streaming services.").font(.system(size: 12)).foregroundStyle(YoruTheme.muted)
            }
            ForEach(anime.safeStreaming) { provider in
                if let url = provider.safeURL {
                    Link(destination: url) {
                        HStack(spacing: 13) {
                            Image(systemName: "play.fill").font(.system(size: 11)).frame(width: 32, height: 32).background(providerColor(provider.name).opacity(0.2), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.name).font(.system(size: 16, weight: .semibold, design: .rounded))
                                Text("Open streaming source").font(.system(size: 10)).foregroundStyle(YoruTheme.muted)
                                if let regions = provider.regions, !regions.isEmpty { Text("Listed regions: " + regions.joined(separator: ", ")).font(.system(size: 9)).foregroundStyle(YoruTheme.muted).lineLimit(2) }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 13))
                        }.foregroundStyle(providerColor(provider.name)).padding(15)
                    }.buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 20))
                }
            }
            if stale { Label("Cached source information", systemImage: "clock.arrow.circlepath").font(.system(size: 11)).foregroundStyle(YoruTheme.violet) }
            Text("Links supplied by Kitsu. Availability and languages vary by region; subscriptions may be required.").font(.system(size: 10)).foregroundStyle(YoruTheme.muted).lineSpacing(3)
        }
    }
    private func providerColor(_ name: String) -> Color {
        let text = name.lowercased()
        if text.contains("crunchyroll") { return .orange }
        if text.contains("hidive") { return .cyan }
        if text.contains("netflix") { return Color(red: 1, green: 0.28, blue: 0.38) }
        if text.contains("hulu") { return .green }
        if text.contains("disney") { return .blue }
        if text.contains("amazon") || text.contains("prime") { return .cyan }
        return YoruTheme.violet
    }
    private func load(refresh: Bool = false) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let result = try await AnimeAPI.shared.detail(anime: initial, refresh: refresh)
            try Task.checkCancellation()
            detail = result.value.data; fetchedAt = result.fetchedAt; stale = result.isStale
            library.update(result.value.data)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
