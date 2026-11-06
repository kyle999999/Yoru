//
//  ExternalSourceInfo.swift
//  Aidoku
//
//  Created by Skitty on 1/16/22.
//

import Foundation

struct ExternalSourceInfo: Codable, Hashable {
    let id: String
    let name: String
    let file: String
    let icon: String
    let lang: String
    let version: Int
    let nsfw: Int?
    let minAppVersion: String?
    let maxAppVersion: String?

    var sourceUrl: URL?
    let downloadURL: String?
    let iconURL: String?
    let modernABI: Bool
    var fileURL: URL? {
        guard let sourceUrl else { return nil }
        return downloadURL.flatMap { URL(string: $0, relativeTo: sourceUrl) } ?? sourceUrl.appendingPathComponent("sources/" + file)
    }
    var imageURL: URL? {
        guard let sourceUrl else { return nil }
        return iconURL.flatMap { URL(string: $0, relativeTo: sourceUrl) } ?? sourceUrl.appendingPathComponent("icons/" + icon)
    }
    enum CodingKeys: String, CodingKey { case id, name, file, icon, lang, version, nsfw, minAppVersion, maxAppVersion, sourceUrl, downloadURL, iconURL, languages, contentRating }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); version = try c.decode(Int.self, forKey: .version)
        downloadURL = try c.decodeIfPresent(String.self, forKey: .downloadURL); iconURL = try c.decodeIfPresent(String.self, forKey: .iconURL)
        modernABI = c.contains(.languages) || downloadURL != nil
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        let languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? []
        lang = try c.decodeIfPresent(String.self, forKey: .lang) ?? (languages.count == 1 ? languages[0].lowercased() : "multi")
        nsfw = try c.decodeIfPresent(Int.self, forKey: .contentRating) ?? c.decodeIfPresent(Int.self, forKey: .nsfw)
        minAppVersion = try c.decodeIfPresent(String.self, forKey: .minAppVersion); maxAppVersion = try c.decodeIfPresent(String.self, forKey: .maxAppVersion)
        sourceUrl = try c.decodeIfPresent(URL.self, forKey: .sourceUrl)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(version, forKey: .version)
        try c.encode(file, forKey: .file); try c.encode(icon, forKey: .icon); try c.encode(lang, forKey: .lang)
        try c.encodeIfPresent(downloadURL, forKey: .downloadURL); try c.encodeIfPresent(iconURL, forKey: .iconURL)
        try c.encodeIfPresent(nsfw, forKey: .nsfw); try c.encodeIfPresent(minAppVersion, forKey: .minAppVersion); try c.encodeIfPresent(maxAppVersion, forKey: .maxAppVersion)
    }
}

// Repository completion order must not let an old legacy package hide a modern update.
extension ExternalSourceInfo {
    static func preferred(_ entries: [ExternalSourceInfo]) -> [ExternalSourceInfo] {
        var result: [String: ExternalSourceInfo] = [:]
        for entry in entries {
            if let previous = result[entry.id] {
                if entry.version < previous.version { continue }
                if entry.version == previous.version && (!entry.modernABI || previous.modernABI) { continue }
            }
            result[entry.id] = entry
        }
        return result.values.sorted { $0.id < $1.id }
    }
}
