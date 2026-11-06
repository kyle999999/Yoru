// SPDX-License-Identifier: GPL-3.0-only
// Native adapter for the independent GPL Go backend. No AidokuRunner implementation is bundled.
import Foundation
import CryptoKit

@_silgen_name("YoruModernCall") private func engineCall(_ input: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("YoruModernFree") private func engineFree(_ pointer: UnsafeMutableRawPointer)
@_silgen_name("YoruModernSetHost") private func engineSetHost(_ pointer: UInt)

final class ModernSourceBridge {
    static let supportedSourceAPIVersion = SemanticVersion("0.9.0")
    let id: String
    var url: URL
    var listings: [Listing] = []
    private var features: [String: Bool] = [:]
    private var listingIDs: [String: String] = [:]
    private var mangaRecords: [String: [String: Any]] = [:]
    private var chapterRecords: [String: [String: Any]] = [:]
    private var filterRecords: [String: [String: Any]] = [:]
    init(id: String, url: URL) { self.id = id; self.url = url }
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    static func installHost() {
        let callback: @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = modernNativeHost
        engineSetHost(unsafeBitCast(callback, to: UInt.self))
    }
    func call(_ op: String, _ parameters: [String: Any] = [:]) throws -> Any {
        var args = parameters; args["Op"] = op; args["ID"] = id; args["Path"] = url.path
        let input = String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)
        let result = try input.withCString { input -> [String: Any] in
            guard let output = engineCall(input) else { throw Failure(message: "Source runtime returned no response") }
            defer { engineFree(UnsafeMutableRawPointer(output)) }
            let data = Data(String(cString: output).utf8)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(message: "Invalid source runtime response") }
            return result
        }
        if let error = result["error"] as? String { LogManager.logger.error("[\(id)] \(op): " + error.replacingOccurrences(of: #"(https?://[^/\s\"]+)[^\s\"]*"#, with: "$1/…", options: .regularExpression)); throw Failure(message: error) }
        return result["value"] ?? NSNull()
    }
    func initialize() throws {
        let result = try call("load") as? [String: Any] ?? [:]
        features = result["features"] as? [String: Bool] ?? [:]
    }
    func loadMetadata() throws -> [FilterBase] {
        try initialize()
        let values = try call("listings") as? [[String: Any]] ?? []
        listings = values.compactMap { value in
            guard let key = value["id"] as? String ?? value["ID"] as? String,
                  let name = value["name"] as? String ?? value["Name"] as? String ?? Optional(key) else { return nil }
            listingIDs[name] = key
            return try? JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: ["name": name]))
        }
        var filters: [FilterBase] = [TitleFilter()]
        for record in try call("filters") as? [[String: Any]] ?? [] {
            let name = record["Title"] as? String ?? record["ID"] as? String ?? "Filter"
            filterRecords[name] = record
            switch record["Kind"] as? String {
            case "text": filters.append(TextFilter(name: name))
            case "sort":
                let defaults = record["SortDefault"] as? [String: Any] ?? [:]
                filters.append(SortFilter(name: name, options: record["SortOptions"] as? [String] ?? [], canAscend: record["CanAscend"] as? Bool ?? false, value: SortSelection(index: defaults["Index"] as? Int ?? 0, ascending: defaults["Ascending"] as? Bool ?? false)))
            case "check": filters.append(CheckFilter(name: name, canExclude: record["CheckCanExclude"] as? Bool ?? false, value: record["CheckDefaultValue"] as? Bool))
            case "select":
                let info = record["Select"] as? [String: Any] ?? [:]
                let titles = info["Options"] as? [String] ?? []
                let values = info["IDs"] as? [String] ?? []
                let index = values.firstIndex(of: info["DefaultValue"] as? String ?? "") ?? 0
                filters.append(SelectFilter(name: name, options: titles, value: index))
            case "multi-select":
                let info = record["MultiSelect"] as? [String: Any] ?? [:]
                let options = info["Options"] as? [String] ?? []
                let ids = info["IDs"] as? [String] ?? options
                let included = Set(info["DefaultIncluded"] as? [String] ?? [])
                let excluded = Set(info["DefaultExcluded"] as? [String] ?? [])
                let choices = options.enumerated().map { index, title -> FilterBase in
                    let key = ids.indices.contains(index) ? ids[index] : title
                    return CheckFilter(name: title, canExclude: info["CanExclude"] as? Bool ?? false, value: included.contains(key) ? true : excluded.contains(key) ? false : nil)
                }
                filters.append(GroupFilter(name: name, filters: choices))
            case "range": filters.append(TextFilter(name: name, value: ""))
            default: break
            }
        }
        return filters
    }
    func settings() throws -> [SettingItem] {
        func flatten(_ record: [String: Any]) -> [String: Any] {
            var output: [String: Any] = [:]
            for key in ["Key", "Title", "Notification", "Requires", "RequiresFalse", "Type"] {
                if let value = record[key], !(value is NSNull) {
                    let lower = key.prefix(1).lowercased() + key.dropFirst()
                    output[lower] = value
                }
            }
            for kind in ["Group", "Select", "Multiselect", "Toggle", "Stepper", "Segment", "Text", "Button", "Link", "Login", "Page", "EditableList", "Picker"] {
                guard let fields = record[kind] as? [String: Any] else { continue }
                for (key, value) in fields where !(value is NSNull) {
                    if key == "Items", let items = value as? [[String: Any]] { output["items"] = items.map(flatten) }
                    else if key == "DefaultValue" { output["default"] = value }
                    else { output[key.prefix(1).lowercased() + key.dropFirst()] = value }
                }
            }
            if let key = output["key"] as? String, !key.isEmpty { output["key"] = id + "." + key }
            for key in ["requires", "requiresFalse", "urlKey"] { if let value = output[key] as? String { output[key] = id + "." + value } }
            if output["notification"] == nil, let refreshes = record["Refreshes"] as? [String], !refreshes.isEmpty {
                output["notification"] = id + ".refreshMetadata"
            }
            if let action = output["notification"] as? String { output["action"] = action }
            return output
        }
        let items = try call("settings") as? [[String: Any]] ?? []
        return try JSONDecoder().decode([SettingItem].self, from: JSONSerialization.data(withJSONObject: items.map(flatten)))
    }

    private func encodeFilters(_ values: [FilterBase]) -> [[String: Any]] {
        var results: [[String: Any]] = []
        for (name, record) in filterRecords where record["Kind"] as? String == "multi-select" {
            let info = record["MultiSelect"] as? [String: Any] ?? [:]
            let options = info["Options"] as? [String] ?? []
            let ids = info["IDs"] as? [String] ?? options
            var included: [String] = []; var excluded: [String] = []
            let checks = values.flatMap { ($0 as? GroupFilter)?.filters ?? [$0] }
            for value in checks.compactMap({ $0 as? CheckFilter }) {
                if let index = options.firstIndex(of: value.name), ids.indices.contains(index), let state = value.value {
                    if state { included.append(ids[index]) } else { excluded.append(ids[index]) }
                }
            }
            _ = name
            results.append(["id": record["ID"] as? String ?? "", "type": "multi-select", "included": included, "excluded": excluded])
        }
        return results + values.compactMap { filter in
            guard let record = filterRecords[filter.name], let key = record["ID"] as? String else { return nil }
            var result: [String: Any] = ["id": key]
            if let value = filter as? SortFilter { result["type"] = "sort"; result["sortIndex"] = value.value.index; result["sortAscending"] = value.value.ascending }
            else if let value = filter as? CheckFilter { result["type"] = "check"; result["checkValue"] = value.value.map { $0 ? 1 : 0 } ?? -1 }
            else if let value = filter as? SelectFilter {
                let info = record["Select"] as? [String: Any] ?? [:]; let options = info["IDs"] as? [String] ?? []
                guard options.indices.contains(value.value) else { return nil }
                result["type"] = "select"; result["value"] = options[value.value]
            } else if let value = filter as? TextFilter {
                guard !value.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                if record["Kind"] as? String == "range" {
                    let parts = value.value.split(separator: ",", omittingEmptySubsequences: false)
                    result["type"] = "range"
                    if let first = parts.first, let from = Float(first.trimmingCharacters(in: .whitespaces)) { result["from"] = from }
                    if parts.count > 1, let to = Float(parts[1].trimmingCharacters(in: .whitespaces)) { result["to"] = to }
                } else { result["type"] = "text"; result["value"] = value.value }
            }
            else { return nil }
            return result
        }
    }
    func browse(filters: [FilterBase], page: Int, listing: Listing? = nil) throws -> MangaPageResult {
        let query = (filters.first { $0 is TitleFilter } as? TitleFilter)?.value
        var args: [String: Any] = ["Page": page, "Filters": encodeFilters(filters)]
        if let query, !query.isEmpty { args["Query"] = query }
        if let listing { args["Listing"] = ["ID": listingIDs[listing.name] ?? listing.name, "Name": listing.name] }
        let result = try call(query?.isEmpty == false ? "search" : "browse", args) as? [String: Any] ?? [:]
        return MangaPageResult(manga: (result["Entries"] as? [[String: Any]] ?? []).map(manga), hasNextPage: result["HasNextPage"] as? Bool ?? false)
    }
    private func manga(_ value: [String: Any]) -> Manga {
        let key = value["Key"] as? String ?? ""; mangaRecords[key] = value
        return Manga(sourceId: id, id: key, title: value["Title"] as? String,
                     author: (value["Authors"] as? [String])?.joined(separator: ", "), artist: (value["Artists"] as? [String])?.joined(separator: ", "),
                     description: value["Description"] as? String, tags: value["Tags"] as? [String],
                     coverUrl: (value["Cover"] as? String).flatMap { address in
                        ModernPageProtocol.register(source: self, chapter: "cover:" + key, index: 0, content: ["URL": address, "Cover": true])
                     }, url: (value["URL"] as? String).flatMap(URL.init(string:)),
                     status: PublishingStatus(rawValue: value["Status"] as? Int ?? 0) ?? .unknown,
                     nsfw: MangaContentRating(rawValue: max(0, (value["ContentRating"] as? Int ?? 1) - 1)) ?? .safe,
                     viewer: MangaViewer(rawValue: [0, 2, 1, 3, 4][min(4, max(0, value["Viewer"] as? Int ?? 0))]) ?? .defaultViewer)
    }
    private func record(_ value: Manga) -> [String: Any] { mangaRecords[value.id] ?? ["Key": value.id, "Title": value.title ?? ""] }
    func update(_ value: Manga) throws -> Manga {
        let result = try call("update", ["Manga": record(value)]) as? [String: Any] ?? [:]
        return manga(result)
    }
    func chapters(_ value: Manga) throws -> [Chapter] {
        let updated = try update(value)
        return (mangaRecords[updated.id]?["Chapters"] as? [[String: Any]] ?? []).enumerated().map { index, item in
            let key = item["Key"] as? String ?? ""; chapterRecords[key] = item
            let date = (item["DateUploaded"] as? String).flatMap { text -> Date? in
                let formatter = ISO8601DateFormatter()
                if let value = formatter.date(from: text) { return value }
                formatter.formatOptions.insert(.withFractionalSeconds)
                return formatter.date(from: text)
            }
            return Chapter(sourceId: id, id: key, mangaId: value.id, title: item["Title"] as? String,
                           scanlator: (item["Scanlators"] as? [String])?.joined(separator: ", "), url: item["URL"] as? String,
                           lang: item["Language"] as? String ?? "", chapterNum: (item["ChapterNumber"] as? NSNumber)?.floatValue,
                           volumeNum: (item["VolumeNumber"] as? NSNumber)?.floatValue, dateUploaded: date, sourceOrder: index)
        }
    }
    func pages(_ chapter: Chapter) throws -> [Page] {
        let m = mangaRecords[chapter.mangaId] ?? ["Key": chapter.mangaId, "Title": ""]
        let c = chapterRecords[chapter.id] ?? ["Key": chapter.id]
        let items = try call("pages", ["Manga": m, "Chapter": c]) as? [[String: Any]] ?? []
        return try items.enumerated().map { index, item in
            let content = item["Content"] as? [String: Any] ?? [:]
            switch content["Kind"] as? Int ?? 0 {
            case 1: return Page(sourceId: id, chapterId: chapter.id, index: index, text: content["Text"] as? String)
            case 2:
                let data = try call("inlineImage", ["Key": String(content["ImageRef"] as? Int ?? -1)]) as? String
                return Page(sourceId: id, chapterId: chapter.id, index: index, base64: data)
            default:
                let address = ModernPageProtocol.register(source: self, chapter: chapter.id, index: index, content: content)
                return Page(sourceId: id, chapterId: chapter.id, index: index, imageURL: address.absoluteString)
            }
        }
    }
    func image(content: [String: Any]) throws -> Data {
        var args: [String: Any] = ["URL": content["URL"] as? String ?? ""]
        if content["Cover"] as? Bool == true { args["Cover"] = true }
        if let context = content["Context"] as? [String: String] { args["Context"] = context }
        if (content["Kind"] as? Int) == 3 { args["Key"] = content["FilePath"] as? String ?? "" }
        guard let encoded = try call("image", args) as? String, let data = Data(base64Encoded: encoded) else { throw Failure(message: "Source returned invalid image data") }
        return data
    }
}

@_cdecl("yoru_modern_native_host")
private func modernNativeHost(_ pointer: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let pointer, let data = String(cString: pointer).data(using: .utf8), let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return strdup("{\"error\":\"Invalid host request\"}") }
    var result: [String: Any] = [:]
    let defaults = AidokuStorage.defaults
    var settingValue = input["value"]
    if input["type"] as? String == "float", let number = settingValue as? NSNumber { settingValue = NSNumber(value: Float(number.doubleValue)) }
    if input["type"] as? String == "data", let encoded = settingValue as? String { settingValue = Data(base64Encoded: encoded) }
    switch input["op"] as? String {
    case "getSetting":
        if let value = defaults.object(forKey: input["key"] as? String ?? "") {
            if let data = value as? Data { result = ["value": data.base64EncodedString(), "type": "data"] }
            else if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { result["value"] = number.boolValue }
                else { result = ["value": number, "type": ["f", "d"].contains(String(cString: number.objCType)) ? "float" : "int"] }
            } else { result["value"] = value }
        }
    case "setSetting":
        if let key = input["key"] as? String { if input["value"] is NSNull { defaults.removeObject(forKey: key) } else if input["type"] as? String == "data", let encoded = input["value"] as? String { defaults.set(Data(base64Encoded: encoded), forKey: key) }
            else { defaults.set(settingValue, forKey: key) } }
    case "registerSetting":
        if let key = input["key"] as? String, let value = settingValue, !(value is NSNull) { defaults.register(defaults: [key: value]) }
    case "log": break // Source print output may contain credentials; do not persist it automatically.
    case "available": break
    case "webview": result = ModernNativeWebView.perform(input)
    case "http": result = ModernNativeHTTP.perform(input)
    default: result = ["error": "Unknown native host operation"]
    }
    let output = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
    return strdup(String(decoding: output, as: UTF8.self))
}

final class ModernPageProtocol: URLProtocol {
    private struct Entry { let source: ModernSourceBridge; let content: [String: Any] }
    private static let lock = NSLock()
    private static var entries: [String: Entry] = [:]
    private var operationTask: Task<Void, Never>?
    static func register(source: ModernSourceBridge, chapter: String, index: Int, content: [String: Any]) -> URL {
        let input = source.id + chapter + String(index) + String(describing: content["URL"])
        let key = SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        lock.lock(); entries[key] = Entry(source: source, content: content); lock.unlock()
        var address = URLComponents(string: "yoru-page://image/\(key)")!
        if content["Cover"] as? Bool == true, let original = content["URL"] as? String {
            // Covers are persisted in the manga database and backups. Their route must
            // remain reconstructible after this process's in-memory registry is gone.
            address.queryItems = [URLQueryItem(name: "source", value: source.id), URLQueryItem(name: "image", value: original)]
        }
        return address.url!
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "yoru-page" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock(); var entry = Self.entries[url.lastPathComponent]; Self.lock.unlock()
        if entry == nil {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let sourceID = query.first(where: { $0.name == "source" })?.value,
               let original = query.first(where: { $0.name == "image" })?.value,
               let scheme = URL(string: original)?.scheme, ["https", "http"].contains(scheme),
               let source = SourceManager.shared.source(for: sourceID)?.modern {
                entry = Entry(source: source, content: ["URL": original, "Cover": true])
            }
        }
        guard let entry else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        operationTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                let data = try entry.source.image(content: entry.content)
                guard !Task.isCancelled else { return }
                let mime = data.starts(with: [0xFF, 0xD8]) ? "image/jpeg" : data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "application/octet-stream"
                self.client?.urlProtocol(self, didReceive: URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil), cacheStoragePolicy: .allowed)
                self.client?.urlProtocol(self, didLoad: data); self.client?.urlProtocolDidFinishLoading(self)
            } catch { if !Task.isCancelled { self.client?.urlProtocol(self, didFailWithError: error) } }
        }
    }
    override func stopLoading() { operationTask?.cancel() }
}
