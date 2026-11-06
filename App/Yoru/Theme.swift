import SwiftUI

enum YoruTheme {
    static let ink = Color(red: 0.025, green: 0.025, blue: 0.055)
    static let violet = Color(red: 0.76, green: 0.68, blue: 1)
    static let mint = Color(red: 0.65, green: 0.98, blue: 0.85)
    static let muted = Color(red: 0.59, green: 0.59, blue: 0.68)
}

struct NightBackground: View {
    var body: some View {
        ZStack {
            YoruTheme.ink
            RadialGradient(colors: [Color.purple.opacity(0.20), .clear], center: .topTrailing, startRadius: 10, endRadius: 450)
            RadialGradient(colors: [Color.teal.opacity(0.10), .clear], center: .bottomLeading, startRadius: 20, endRadius: 450)
        }.ignoresSafeArea()
    }
}

struct Eyebrow: View {
    var text: String
    var color: Color = YoruTheme.violet
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2.3).foregroundStyle(color) }
}

struct PageHeader: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "moon.fill").font(.system(size: 18)).foregroundStyle(YoruTheme.violet)
                    Text("yoru").font(.system(size: 26, weight: .semibold, design: .rounded)).tracking(-1.3)
                }
                Spacer()
                Text("夜 / ANIME JOURNAL").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.2).foregroundStyle(YoruTheme.muted)
            }.padding(.bottom, 16)
            Eyebrow(text: eyebrow)
            Text(title).font(.system(size: 42, weight: .semibold, design: .rounded)).tracking(-2).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(YoruTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Poster: View {
    let anime: Anime
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: anime.posterURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [.indigo.opacity(0.65), .purple.opacity(0.25), YoruTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "moon.stars").font(.system(size: 35, weight: .ultraLight)).foregroundStyle(.white.opacity(0.35))
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
    }
}

struct StatusPill: View {
    var title: String
    var live = false
    var body: some View {
        HStack(spacing: 6) {
            if live { Circle().fill(YoruTheme.mint).frame(width: 5, height: 5) }
            Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }.padding(.horizontal, 11).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }
}

struct SectionHeading: View {
    var title: String
    var trailing: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.7)
            Spacer()
            Text(trailing).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(YoruTheme.muted)
        }
    }
}

struct AnimeCard: View {
    var anime: Anime
    var library: Library
    var open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack(alignment: .topTrailing) {
                Button(action: open) {
                    Poster(anime: anime).frame(height: 222).clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(alignment: .bottomLeading) {
                            if let score = anime.score, score > 0 {
                                Label(score.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                                    .font(.system(size: 10, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(.black.opacity(0.65), in: Capsule()).padding(10)
                            }
                        }
                }.buttonStyle(.plain).accessibilityLabel("Details for \(anime.displayTitle)")
                Button { withAnimation(.snappy) { library.toggle(anime) } } label: {
                    Image(systemName: library.isSaved(anime) ? "bookmark.fill" : "plus").font(.system(size: 12, weight: .semibold)).frame(width: 32, height: 32)
                }.buttonStyle(.glass).buttonBorderShape(.circle).padding(10)
                    .accessibilityLabel(library.isSaved(anime) ? "Unsave \(anime.displayTitle)" : "Save \(anime.displayTitle)")
            }
            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(anime.displayTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(2).frame(height: 36, alignment: .top)
                    Text("\(anime.type ?? "Anime") · \(anime.episodeLabel)").font(.system(size: 10)).foregroundStyle(YoruTheme.muted).lineLimit(1)
                    if let provider = anime.safeStreaming.first {
                        Text(provider.name + (anime.safeStreaming.count > 1 ? " +\(anime.safeStreaming.count - 1)" : ""))
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(YoruTheme.violet).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }
    }
}

struct AnimeRow: View {
    var anime: Anime
    var library: Library
    var showProgress = false
    var open: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) { Poster(anime: anime).frame(width: 70, height: 100).clipShape(RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(anime.displayTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                    Text(showProgress ? "\(library.watched(anime)) / \(anime.episodes.map(String.init) ?? "?") episodes" : anime.statusLabel)
                        .font(.system(size: 11)).foregroundStyle(YoruTheme.muted)
                    if showProgress, let count = anime.episodes, count > 0 {
                        ProgressView(value: Double(library.watched(anime)), total: Double(count)).tint(YoruTheme.violet)
                    } else if let broadcast = anime.broadcast, anime.airing == true {
                        Text(broadcast.string ?? broadcast.shortTime).font(.system(size: 10, design: .monospaced)).foregroundStyle(YoruTheme.violet).lineLimit(1)
                    }
                    if !showProgress, !anime.safeStreaming.isEmpty {
                        Text(anime.safeStreaming.prefix(2).map(\.name).joined(separator: " · ")).font(.system(size: 10, weight: .medium)).foregroundStyle(YoruTheme.violet).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button {
                if showProgress { library.log(anime) } else { library.toggle(anime) }
            } label: {
                Image(systemName: showProgress ? "checkmark" : library.isSaved(anime) ? "bookmark.fill" : "plus")
                    .frame(width: 35, height: 35)
            }.buttonStyle(.glass).buttonBorderShape(.circle)
                .disabled(showProgress && anime.episodes.map { library.watched(anime) >= $0 } == true)
                .accessibilityLabel(showProgress ? "Log episode of \(anime.displayTitle)" : "Toggle saved \(anime.displayTitle)")
        }.padding(14).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 23))
    }
}

struct CatalogStatus: View {
    var store: CatalogStore
    var retry: () async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.error {
                Label(store.items.isEmpty ? "Couldn’t load anime" : "Some titles couldn’t load", systemImage: "wifi.exclamationmark").font(.system(size: 15, weight: .semibold))
                Text(error).font(.system(size: 12)).foregroundStyle(YoruTheme.muted)
                Button("Try again") { Task { await retry() } }.buttonStyle(.glass)
            }
            if store.isStale {
                Label("Offline · showing cached listings", systemImage: "clock.arrow.circlepath").font(.system(size: 12)).foregroundStyle(YoruTheme.violet)
            }
            if store.isLoading {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(store.items.isEmpty ? "Finding your next story…" : "\(store.items.count) titles · fetching more…").font(.system(size: 12)).foregroundStyle(YoruTheme.muted) }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SourceFooter: View {
    var date: Date?
    var body: some View {
        VStack(spacing: 8) {
            Link("Catalog & streaming links · Kitsu ↗", destination: URL(string: "https://kitsu.app")!)
            if let date { Text("Retrieved \(date.formatted(date: .abbreviated, time: .shortened))") }
        }.font(.system(size: 10)).foregroundStyle(YoruTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}
