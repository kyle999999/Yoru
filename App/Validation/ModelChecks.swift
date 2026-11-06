import Foundation

final class StubProtocol: URLProtocol, @unchecked Sendable {
    static var payload = Data()
    static var offline = false
    static var requests: [URL] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request.url!)
        if Self.offline { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Checks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detailData = try Data(contentsOf: root.appendingPathComponent("Fixtures/detail.json"))
        let detail = try decoder.decode(KitsuDocument.self, from: detailData)
        let bebop = detail.anime[0]
        expect(bebop.id == 1 && bebop.kitsuId == "1", "Kitsu/MAL identity mapping")
        expect(bebop.safeStreaming.contains { $0.name == "Crunchyroll" }, "Streaming provider relationship resolution")
        expect(bebop.safeStreaming.allSatisfy { $0.safeURL?.scheme == "https" }, "Secure links including legacy HTTP normalization")
        expect(StreamLink(name: "Unsafe", url: "javascript:alert(1)").safeURL == nil, "Reject non-web streaming links")
        let seasonal = try decoder.decode(KitsuDocument.self, from: Data(contentsOf: root.appendingPathComponent("Fixtures/season.json")))
        expect(seasonal.anime.count == 2 && seasonal.links?["next"] != nil, "Seasonal response and pagination")
        expect(Season.current(date: Date(timeIntervalSince1970: 1793664000)).name == "fall", "Season selection follows date")
        let timestamp = KitsuDocument.parseDate("2026-11-08T09:30:00.000+09:00")!
        let broadcast = KitsuDocument.broadcast(date: timestamp)
        expect(broadcast.day == "Sundays" && broadcast.time == "09:30", "Schedule grouped in Japan time")
        let suite = "yoru.validation." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = #"[{"id":"frieren","title":"Frieren","episodes":28,"watched":6,"saved":true}]"#
        defaults.set(Data(old.utf8), forKey: "yoru.library")
        let library = Library(defaults: defaults)
        let frieren = library.saved[0]
        expect(frieren.id == 52991 && library.watched(frieren) == 6, "Migrate v1 watchlist without losing progress")
        library.log(frieren, delta: -1)
        library.toggle(frieren)
        let restored = Library(defaults: defaults)
        expect(restored.saved.isEmpty && restored.watched(frieren) == 5, "Persist undo and unsave")
        var unknown = bebop; unknown.malId = 999999; unknown.episodes = nil
        library.log(unknown)
        expect(library.watched(unknown) == 1, "Unknown episode totals can be tracked")
        var finished = bebop; finished.episodes = 1
        library.log(finished); library.log(finished)
        expect(library.watched(finished) == 1, "Episode count cannot exceed total")
        library.log(finished, delta: -10)
        expect(library.watched(finished) == 0, "Undo cannot go below zero")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let api = AnimeAPI(session: URLSession(configuration: config), cacheDirectory: cache)
        StubProtocol.payload = detailData
        let first = try await api.detail(anime: bebop)
        expect(!first.isStale && first.value.data.id == 1, "Successful network detail decoding")
        StubProtocol.offline = true
        let cached = try await api.detail(anime: bebop)
        expect(!cached.isStale && StubProtocol.requests.count == 1, "Fresh cache avoids redundant requests")
        let fallback = try await api.detail(anime: bebop, refresh: true)
        expect(fallback.isStale && fallback.fetchedAt == first.fetchedAt, "Offline fallback preserves retrieval date and marks stale")
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        expect(files.count == 1 && files[0].count == 69, "Cache keys remain within filesystem limits")
        StubProtocol.offline = false
        StubProtocol.payload = try Data(contentsOf: root.appendingPathComponent("Fixtures/season.json"))
        _ = try await api.page(path: "seasons/2026/fall", parameters: ["provider": "HIDIVE"], page: 3)
        let query = URLComponents(url: StubProtocol.requests.last!, resolvingAgainstBaseURL: false)!.queryItems!
        expect(query.contains { $0.name == "page[offset]" && $0.value == "40" }, "Correct offset for page three")
        expect(query.contains { $0.name == "filter[seasonYear]" && $0.value == "2026" }, "Season year query")
        expect(query.contains { $0.name == "filter[streamers]" && $0.value == "HIDIVE" }, "Provider filter query")
        if CommandLine.arguments.contains("--live") {
            let season = Season.current()
            var ids = Set<Int>(); var page = 1; var more = true
            while more {
                let response = try await AnimeAPI.shared.page(path: "seasons/\(season.year)/\(season.name)", parameters: [:], page: page, refresh: true)
                for anime in response.value.data { ids.insert(anime.id) }
                more = response.value.pagination.hasNextPage; page += 1
                expect(page < 100, "Bounded live season pagination")
            }
            expect(ids.count > 25, "Live season loads beyond a single page")
            print("LIVE: \(ids.count) non-explicit titles across \(page - 1) pages for \(season.label)")
            let result = try await AnimeAPI.shared.page(path: "anime", parameters: ["q": "Cowboy Bebop"], page: 1, refresh: true)
            expect(result.value.data.contains { $0.displayTitle.localizedCaseInsensitiveContains("Bebop") }, "Live global search finds an older title")
            let providers = try await AnimeAPI.shared.page(path: "anime", parameters: ["provider": "HIDIVE"], page: 1, refresh: true)
            expect(!providers.value.data.isEmpty && providers.value.data.allSatisfy { $0.safeStreaming.contains { $0.name == "HIDIVE" } }, "Live provider filter returns source-linked shows")
        }
        print("All model, migration, cache, schedule, and query checks passed.")
    }
    static func expect(_ condition: Bool, _ label: String) {
        guard condition else { fatalError("FAIL: \(label)") }
        print("PASS: \(label)")
    }
}
