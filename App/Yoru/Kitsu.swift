import Foundation

struct KitsuDocument: Decodable, Sendable {
    var data: [Resource]
    var included: [Resource]?
    var links: [String: String?]?
    var meta: Meta?
    struct Meta: Decodable, Sendable { var count: Int? }
    enum CodingKeys: String, CodingKey { case data, included, links, meta }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let many = try? c.decode([Resource].self, forKey: .data) { data = many }
        else { data = [try c.decode(Resource.self, forKey: .data)] }
        included = try c.decodeIfPresent([Resource].self, forKey: .included)
        links = try c.decodeIfPresent([String: String?].self, forKey: .links)
        meta = try c.decodeIfPresent(Meta.self, forKey: .meta)
    }
    struct Reference: Decodable, Sendable { var id: String; var type: String }
    struct Relation: Decodable, Sendable {
        var refs: [Reference]
        enum CodingKeys: String, CodingKey { case data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let many = try? c.decode([Reference].self, forKey: .data) { refs = many }
            else if let one = try? c.decode(Reference.self, forKey: .data) { refs = [one] }
            else { refs = [] }
        }
    }
    struct Resource: Decodable, Sendable {
        var id: String
        var type: String
        var attributes: Attributes?
        var relationships: [String: Relation]?
    }
    struct Attributes: Decodable, Sendable {
        var canonicalTitle: String?
        var titles: [String: String]?
        var slug: String?
        var synopsis: String?
        var posterImage: PosterImage?
        var episodeCount: Int?
        var status: String?
        var subtype: String?
        var startDate: String?
        var nextRelease: String?
        var averageRating: String?
        var nsfw: Bool?
        var siteName: String?
        var externalSite: String?
        var externalId: String?
        var url: String?
        var regions: [String]?
        var title: String?
    }
    struct PosterImage: Decodable, Sendable { var large: String?; var original: String?; var medium: String? }

    var anime: [Anime] {
        let resources = (included ?? []) + data
        let index = Dictionary(resources.map { ($0.type + "/" + $0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func related(_ resource: Resource, _ relation: String) -> [Resource] {
            (resource.relationships?[relation]?.refs ?? []).compactMap { index[$0.type + "/" + $0.id] }
        }
        return data.filter { $0.type == "anime" && $0.attributes?.nsfw != true }.compactMap { resource in
            guard let a = resource.attributes, let kitsuId = Int(resource.id), let title = a.canonicalTitle else { return nil }
            let mapping = related(resource, "mappings").first { $0.attributes?.externalSite == "myanimelist/anime" }
            let id = mapping?.attributes?.externalId.flatMap(Int.init) ?? -kitsuId
            let state: String
            switch a.status { case "current": state = "Currently Airing"; case "finished": state = "Finished Airing"; case "upcoming", "tba", "unreleased": state = "Not yet aired"; default: state = "Unknown" }
            let streams: [StreamLink] = related(resource, "streamingLinks").compactMap { link in
                guard var url = link.attributes?.url, let streamer = related(link, "streamer").first?.attributes?.siteName else { return nil }
                if url.hasPrefix("http://") { url = "https://" + url.dropFirst(7) }
                return StreamLink(name: streamer, url: url, regions: link.attributes?.regions)
            }
            let date = a.startDate.flatMap { String($0.prefix(10)) }
            let parts = date?.split(separator: "-").compactMap { Int($0) }
            let month = parts?.count == 3 ? parts?[1] : nil
            let season = month.flatMap { (1...12).contains($0) ? Season.names[($0 - 1) / 3] : nil }
            let next = a.nextRelease.flatMap(Self.parseDate)
            return Anime(malId: id, title: title, titleEnglish: a.titles?["en"], titleJapanese: a.titles?["ja_jp"],
                         images: .init(jpg: .init(imageUrl: a.posterImage?.medium, largeImageUrl: a.posterImage?.large ?? a.posterImage?.original)),
                         synopsis: a.synopsis, episodes: a.episodeCount, status: state, airing: a.status == "current",
                         score: a.averageRating.flatMap(Double.init).map { $0 / 10 }, type: a.subtype?.uppercased(), season: season,
                         year: parts?.first, broadcast: next.map { Self.broadcast(date: $0) },
                         genres: related(resource, "categories").compactMap { $0.attributes?.title.map { Anime.NamedItem(name: $0) } }, streaming: streams,
                         url: "https://kitsu.app/anime/\(a.slug ?? resource.id)", kitsuId: resource.id, sourceName: "Kitsu", nextRelease: next)
        }
    }
    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func broadcast(date: Date) -> Broadcast {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let names = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
        let time = String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        return Broadcast(day: names[calendar.component(.weekday, from: date) - 1], time: time, timezone: "Asia/Tokyo", string: "\(names[calendar.component(.weekday, from: date) - 1]) at \(time) JST")
    }
}
