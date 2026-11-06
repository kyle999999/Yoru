//
//  SourceManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import ZIPFoundation

class SourceManager {

    static let shared = SourceManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Sources", isDirectory: true)

    var sources: [Source] = []
    var sourceLists: [URL] = []

    static let languageCodes = [
        "multi", "en", "ca", "de", "es", "fr", "id", "it", "pl", "pt-br", "vi", "tr", "ru", "ar", "zh", "zh-hans", "ja", "ko"
    ]

    private var sourceListsStrings: [String] {
        sourceLists.map { $0.absoluteString }
    }

    init() {
        CoreDataManager.shared.context.performAndWait {
            // fetch sources from db
            let dbSources = CoreDataManager.shared.getSources()
            var sources: [Source] = []
            for dbSource in dbSources {
                if let source = dbSource.toSource(), !sources.contains(where: { $0.id == source.id }) {
                    sources.append(source)
                } else {
                    // strip duplicate and dead sources
                    CoreDataManager.shared.remove(dbSource)
                }
            }
            CoreDataManager.shared.saveIfNeeded()

            // sort and store sources
            self.sources = sources
                .sorted { $0.manifest.info.name < $1.manifest.info.name }
                .sorted {
                    let lhs = Self.languageCodes.firstIndex(of: $0.manifest.info.lang) ?? 0
                    let rhs = Self.languageCodes.firstIndex(of: $1.manifest.info.lang) ?? 0
                    return lhs < rhs
                }
        }
        sourceLists = (AidokuStorage.defaults.array(forKey: "Browse.sourceLists") as? [String] ?? []).compactMap { URL(string: $0) }

        // load source filters
        Task {
            await withTaskGroup(of: Void.self) { group in
                for source in sources {
                    group.addTask {
                        _ = try? await source.getFilters()
                    }
                }
            }
            NotificationCenter.default.post(name: Notification.Name("loadedSourceFilters"), object: nil)
        }
    }
}

// MARK: - Source Management
extension SourceManager {

    func source(for id: String) -> Source? {
        sources.first { $0.id == id }
    }

    func hasSourceInstalled(id: String) -> Bool {
        sources.contains { $0.id == id }
    }

    func importSource(from url: URL) async -> Source? {
        Self.directory.createDirectory()

        var fileUrl = url

        if let temporaryDirectory = FileManager.default.temporaryDirectory {
            if fileUrl.scheme != "file" {
                do {
                    let location = try await EmbeddedNetwork.shared.session.download(for: URLRequest.from(url))
                    fileUrl = location
                } catch {
                    return nil
                }
            }
            // Preserve the user's original .aix when importing from Files.
            if url.isFileURL {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let importedCopy = temporaryDirectory.appendingPathComponent("import.aix")
                do { try FileManager.default.copyItem(at: url, to: importedCopy); fileUrl = importedCopy }
                catch { return nil }
            }
            do { try FileManager.default.unzipItem(at: fileUrl, to: temporaryDirectory) }
            catch { try? FileManager.default.removeItem(at: temporaryDirectory); return nil }
            try? FileManager.default.removeItem(at: fileUrl)

            let payload = temporaryDirectory.appendingPathComponent("Payload")
            let source = try? Source(from: payload)
            if let source = source {
                let destination = Self.directory.appendingPathComponent(source.id)
                if destination.exists {
                    try? FileManager.default.removeItem(at: destination)
                    sources.removeAll { $0.id == source.id }
                }
                try? FileManager.default.moveItem(at: payload, to: destination)
                try? FileManager.default.removeItem(at: temporaryDirectory)

                source.url = destination

                await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.createSource(source: source, context: context)
                    try? context.save()
                }
                sources.append(source)
                sources.sort { $0.manifest.info.name < $1.manifest.info.name }
                sources.sort {
                    let lhs = Self.languageCodes.firstIndex(of: $0.manifest.info.lang) ?? 0
                    let rhs = Self.languageCodes.firstIndex(of: $1.manifest.info.lang) ?? 0
                    return lhs < rhs
                }

                NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)

                Task {
                    _ = try? await source.getFilters()
                }

                return source
            }
        }

        return nil
    }

    func clearSources() {
        for source in sources {
            try? FileManager.default.removeItem(at: source.url)
        }
        sources = []
        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.clearSources(context: context)
                try? context.save()
            }
            NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
        }
    }

    func remove(source: Source) {
        try? FileManager.default.removeItem(at: source.url)
        sources.removeAll { $0.id == source.id }
        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.removeSource(id: source.id, context: context)
                try? context.save()
            }
            NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
        }
    }

    // Pin a source in browse tab.
    func pin(source: Source) {
        let key = "Browse.pinnedList"
        var pinnedList = AidokuStorage.defaults.stringArray(forKey: key) ?? []
        if !pinnedList.contains(source.id) {
            pinnedList.append(source.id)
            AidokuStorage.defaults.set(pinnedList, forKey: key)
        }
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }

    // Unpin a source in browse tab.
    func unpin(source: Source) {
        let key = "Browse.pinnedList"
        var pinnedList = AidokuStorage.defaults.stringArray(forKey: key) ?? []
        if let index = pinnedList.firstIndex(of: source.id) {
            pinnedList.remove(at: index)
            AidokuStorage.defaults.set(pinnedList, forKey: key)
        }
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }
}

// MARK: - Source List Management
extension SourceManager {

    func addSourceList(url: URL) async -> Bool {
        guard !sourceLists.contains(url) else { return false }

        if await loadSourceList(url: url) == nil {
            return false
        }

        sourceLists.append(url)
        AidokuStorage.defaults.set(sourceListsStrings, forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: Notification.Name("updateSourceLists"), object: nil)
        return true
    }

    func removeSourceList(url: URL) {
        sourceLists.removeAll { $0 == url }
        AidokuStorage.defaults.set(sourceListsStrings, forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: Notification.Name("updateSourceLists"), object: nil)
    }

    func clearSourceLists() {
        sourceLists = []
        AidokuStorage.defaults.set([URL](), forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: Notification.Name("updateSourceLists"), object: nil)
    }

    func loadSourceList(url: URL) async -> [ExternalSourceInfo]? {
        if !url.pathExtension.isEmpty {
            return try? await EmbeddedNetwork.shared.session.object(
                from: url
            ) as [ExternalSourceInfo]
        } else {
            if let sources = try? await EmbeddedNetwork.shared.session.object(
                from: url.appendingPathComponent("index.min.json")
            ) as [ExternalSourceInfo] {
                return sources
            } else {
                return nil
            }
        }
    }
}
