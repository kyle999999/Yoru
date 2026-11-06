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
        let base = URL(string: "https://aidoku-community.github.io/sources/")!
        guard let list = await manager.loadSourceList(url: base) else { record("repository", "load", "failed"); return }
        record("repository", "load", "\(list.count) entries")
        let manifestsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("source-manifests.json")
        if let data = try? Data(contentsOf: manifestsURL), let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let scratch = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SourceManifestProbe")
            try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            var passed = 0
            for record in records {
                do {
                    let bytes = try JSONSerialization.data(withJSONObject: record)
                    try bytes.write(to: scratch.appendingPathComponent("source.json"))
                    _ = try Source(from: scratch)
                    passed += 1
                } catch { selfRecordFailure(record, error: error) }
            }
            record("repository", "native manifest decoding", "\(passed)/\(records.count)")
            func selfRecordFailure(_ manifest: [String: Any], error: Error) {
                let name = (manifest["info"] as? [String: Any])?["id"] as? String ?? "unknown"
                record(name, "native manifest failure", String(describing: error))
            }
        }
        let only = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--probe-source=") }.map { String($0.dropFirst("--probe-source=".count)) }
        for id in ["multi.webtoon", "multi.mangadex", "en.weebcentral", "multi.mangafire", "multi.mangaplus"] where only == nil || only == id {
            guard let info = list.first(where: { $0.id == id }) else { continue }
            record(id, "install", "starting")
            guard let source = await manager.importSource(from: URL(string: info.downloadURL ?? "", relativeTo: base)!) else { record(id, "install", "failed"); continue }
            record(id, "install", "installed v\(info.version)")
            do {
                _ = try await source.getFilters()
                var browseManga: [Manga] = []
                var searchManga: [Manga] = []
                do {
                    let browse = try await source.getMangaList(filters: source.getDefaultFilters())
                    browseManga = browse.manga
                    record(id, "browse", "\(browse.manga.count) manga")
                } catch { record(id, "browse", "\(error); \(source.netModule?.lastResponseSummary ?? "modern runtime")") }
                if source.titleSearchable {
                    do {
                        let query = id == "multi.komga" ? "Space" : "Alice"
                        let search = try await source.fetchSearchManga(query: query)
                        searchManga = search.manga
                        record(id, "search", "\(search.manga.count) manga")
                    } catch { record(id, "search", "\(error); \(source.netModule?.lastResponseSummary ?? "modern runtime")") }
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
                record(id, "image", "\(data.count) bytes, decoded=\(UIImage(data: data) != nil), transport=\(response.url?.scheme ?? "unknown")")
                if id == "multi.mangaplus" {
                    let view = await MainActor.run { ReaderPageView() }
                    let loaded = await view.setPage(page, sourceId: source.id)
                    record(id, "existing reader image pipeline", String(loaded))
                    if ProcessInfo.processInfo.arguments.contains("--open-reader") {
                        await MainActor.run {
                            let reader = ReaderViewController(chapter: chapter, chapterList: chapters)
                            let navigation = UINavigationController(rootViewController: reader)
                            navigation.modalPresentationStyle = .fullScreen
                            AidokuIntegration.activeWindow?.rootViewController?.present(navigation, animated: false)
                        }
                    }
                }
            } catch { record(id, "error", String(describing: error)) }
        }
        _ = LogManager.export(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("source-probe-log.txt"))
        _ = LogManager.export(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("source-probe-log.txt"))
        record("probe", "complete", "finished")
    }
}
#endif
