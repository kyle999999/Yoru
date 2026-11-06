// SPDX-License-Identifier: GPL-3.0-only
#if DEBUG
import Foundation
import UIKit

// Opt-in live integration probe. Never runs in release builds or normal launches.
enum SourceCompatibilityProbe {
    static func run() async {
        var rows: [[String: Any]] = []
        func record(_ source: String, _ stage: String, _ result: String) {
            rows.append(["source": source, "stage": stage, "result": result])
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("source-probe.json")
            if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
        }
        // Present the actual section so verification web views have their normal host.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await AidokuIntegration.present()
        let manager = SourceManager.shared
        let base = URL(string: "https://raw.githubusercontent.com/Skittyblock/aidoku-community-sources/gh-pages/")!
        guard let list = await manager.loadSourceList(url: base) else { record("repository", "load", "failed"); return }
        record("repository", "load", "\(list.count) entries")
        for id in ["multi.komga", "multi.xkcd", "multi.webtoon", "multi.mangadex"] {
            guard let info = list.first(where: { $0.id == id }) else { continue }
            record(id, "install", "starting")
            guard let source = await manager.importSource(from: base.appendingPathComponent("sources/" + info.file)) else { record(id, "install", "failed"); continue }
            record(id, "install", "installed v\(info.version)")
            if id == "multi.komga" {
                // Exercise the real ABI import with multiple reads, not a parallel mock.
                let original = source.globalStore.readBytes(offset: 0, length: 8)!
                let descriptor: Int32 = 123456
                var request = WasmRequestObject(id: descriptor)
                request.response = WasmResponseObject(data: Data(0..<8))
                source.globalStore.requests[descriptor] = request
                source.netModule.get_data(descriptor, 0, 3)
                let first = source.globalStore.readBytes(offset: 0, length: 3)
                source.netModule.get_data(descriptor, 0, 3)
                let second = source.globalStore.readBytes(offset: 0, length: 3)
                source.netModule.get_data(descriptor, 0, 2)
                let third = source.globalStore.readBytes(offset: 0, length: 2)
                record("runtime", "chunked response regression", "\(first == [0,1,2] && second == [3,4,5] && third == [6,7] && source.netModule.get_data_size(descriptor) == 0)")
                source.globalStore.write(bytes: original, offset: 0)
                source.globalStore.requests.removeValue(forKey: descriptor)
            }
            do {
                _ = try await source.getFilters()
                var browseManga: [Manga] = []
                var searchManga: [Manga] = []
                do {
                    let browse = try await source.getMangaList(filters: source.getDefaultFilters())
                    browseManga = browse.manga
                    record(id, "browse", "\(browse.manga.count) manga")
                } catch { record(id, "browse", "\(error); \(source.netModule.lastResponseSummary ?? "no HTTP response")") }
                if source.titleSearchable {
                    do {
                        let query = id == "multi.komga" ? "Space" : "Alice"
                        let search = try await source.fetchSearchManga(query: query)
                        searchManga = search.manga
                        record(id, "search", "\(search.manga.count) manga")
                    } catch { record(id, "search", "\(error); \(source.netModule.lastResponseSummary ?? "no HTTP response")") }
                } else { record(id, "search", "not offered by this extension") }
                guard let manga = (id == "multi.komga" ? searchManga.first : browseManga.first) ?? searchManga.first else {
                    record(id, "details/chapters/pages/image", "blocked: no manga returned")
                    continue
                }
                let details = try await source.getMangaDetails(manga: manga)
                record(id, "details", details.title ?? "missing title")
                let chapters = try await source.getChapterList(manga: details)
                record(id, "chapters", "\(chapters.count) chapters")
                guard let chapter = chapters.first else { continue }
                let pages = try await source.getPageList(chapter: chapter, skipDownloadedCheck: true)
                record(id, "pages", "\(pages.count) pages")
                guard let page = pages.first, let image = page.imageURL, let url = URL(string: image) else { continue }
                let modified = try await source.getImageRequest(url: image)
                var request = URLRequest(url: URL(string: modified.url ?? image) ?? url)
                for (key, value) in modified.headers { request.setValue(value, forHTTPHeaderField: key) }
                let (data, response) = try await EmbeddedNetwork.shared.session.data(for: request)
                record(id, "image", "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1), \(data.count) bytes, decoded=\(UIImage(data: data) != nil)")
            } catch { record(id, "error", String(describing: error)) }
        }
        _ = LogManager.export(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("source-probe-log.txt"))
        if let installed = manager.source(for: "multi.webtoon") {
            let original = try? Data(contentsOf: installed.url.appendingPathComponent("main.wasm"))
            let rejected = await manager.importSource(from: URL(string: "https://aidoku-community.github.io/sources/sources/multi.webtoon-v5.aix")!)
            let preserved = try? Data(contentsOf: installed.url.appendingPathComponent("main.wasm"))
            record("multi.webtoon", "incompatible update rollback", "rejected=\(rejected == nil), original preserved=\(original != nil && original == preserved), installed version=\(manager.source(for: "multi.webtoon")?.manifest.info.version ?? -1)")
        }
        _ = LogManager.export(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("source-probe-log.txt"))
        record("probe", "complete", "finished")
    }
}
#endif
