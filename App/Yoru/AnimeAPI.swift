import Foundation
import CryptoKit

struct APIResponse<Value: Sendable>: Sendable {
    var value: Value
    var fetchedAt: Date
    var isStale: Bool
}

actor AnimeAPI {
    static let shared = AnimeAPI()
    private var nextSlot = Date.distantPast
    private let session: URLSession
    private let cacheDirectory: URL
    private let freshness: TimeInterval = 6 * 60 * 60
    private struct Cached: Codable { var data: Data; var fetchedAt: Date }

    init(session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.session = session
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("YoruCatalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    func page(path: String, parameters: [String: String], page: Int, refresh: Bool = false) async throws -> APIResponse<AnimePage> {
        // Calendar has its own single-document schedule API. Never scan this catalog for weekdays.
        if path == "schedules" { throw ScheduleError.changedFormat }
        var query = ["page[limit]": "20", "page[offset]": String((page - 1) * 20),
                     "include": "mappings,streamingLinks.streamer", "sort": "popularityRank"]
        let components = path.split(separator: "/")
        if components.first == "seasons", components.count == 3 {
            query["filter[seasonYear]"] = String(components[1]); query["filter[season]"] = String(components[2])
        }
        if let search = parameters["q"] { query["filter[text]"] = search; query["sort"] = nil }
        if let status = parameters["status"] { query["filter[status]"] = status == "airing" ? "current" : "finished" }
        if let provider = parameters["provider"], !provider.isEmpty { query["filter[streamers]"] = provider }
        let response: APIResponse<KitsuDocument> = try await request(path: "anime", parameters: query, refresh: refresh)
        let anime = response.value.anime
        let hasMore = (response.value.links?["next"] ?? nil) != nil
        return APIResponse(value: AnimePage(data: anime, pagination: .init(hasNextPage: hasMore)), fetchedAt: response.fetchedAt, isStale: response.isStale)
    }
    func detail(anime: Anime, refresh: Bool = false) async throws -> APIResponse<AnimeDetail> {
        var kitsuId = anime.kitsuId
        if kitsuId == nil, anime.id > 0 {
            let mapping: APIResponse<KitsuDocument> = try await request(path: "mappings", parameters: ["filter[externalSite]": "myanimelist/anime", "filter[externalId]": String(anime.id), "include": "item"], refresh: refresh)
            kitsuId = mapping.value.data.first?.relationships?["item"]?.refs.first?.id
        }
        guard let kitsuId else { throw APIError.unavailable }
        let response: APIResponse<KitsuDocument> = try await request(path: "anime/\(kitsuId)", parameters: ["include": "mappings,streamingLinks.streamer,categories"], refresh: refresh)
        guard var full = response.value.anime.first else { throw APIError.unavailable }
        full.malId = anime.id
        full.broadcast = full.broadcast ?? anime.broadcast
        return APIResponse(value: AnimeDetail(data: full), fetchedAt: response.fetchedAt, isStale: response.isStale)
    }

    private func request<T: Decodable & Sendable>(path: String, parameters: [String: String], refresh: Bool) async throws -> APIResponse<T> {
        var components = URLComponents(string: "https://kitsu.io/api/edge/\(path)")!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let url = components.url!
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = cacheDirectory.appendingPathComponent(key + ".json")
        let cached = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        if !refresh, let cached, Date.now.timeIntervalSince(cached.fetchedAt) < freshness,
           let value = try? decoder.decode(T.self, from: cached.data) {
            return APIResponse(value: value, fetchedAt: cached.fetchedAt, isStale: false)
        }
        do {
            for attempt in 0..<3 {
                try Task.checkCancellation()
                // Reserve slots before suspension, including concurrent detail and calendar calls.
                let slot = max(Date.now, nextSlot); nextSlot = slot.addingTimeInterval(1.15)
                let delay = slot.timeIntervalSinceNow
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                var request = URLRequest(url: url); request.timeoutInterval = 25
                request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.unavailable }
                if http.statusCode == 429, attempt < 2 {
                    let retry = min(60, max(2, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(3 * (attempt + 1))))
                    nextSlot = max(nextSlot, .now.addingTimeInterval(retry))
                    continue
                }
                guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
                let value = try decoder.decode(T.self, from: data)
                let record = Cached(data: data, fetchedAt: .now)
                if let encoded = try? JSONEncoder().encode(record) { try? encoded.write(to: file, options: .atomic) }
                return APIResponse(value: value, fetchedAt: record.fetchedAt, isStale: false)
            }
            throw APIError.unavailable
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let cached, let value = try? decoder.decode(T.self, from: cached.data) {
                return APIResponse(value: value, fetchedAt: cached.fetchedAt, isStale: true)
            }
            throw error
        }
    }
}

enum APIError: LocalizedError {
    case unavailable, http(Int)
    var errorDescription: String? {
        switch self {
        case .http(429): "The anime catalog is busy. Please try again in a moment."
        case .http(let code): "The catalog couldn’t respond (\(code)). Please try again."
        case .unavailable: "The catalog is temporarily unavailable. Please try again."
        }
    }
}
