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
                if let source = dbSource.toSource() {
                    if !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
                } else {
                    // A transient runtime/file failure must not erase the user's source record.
                    LogManager.logger.error("An installed source could not be loaded; its record was preserved.")
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
        guard let temporaryDirectory = FileManager.default.temporaryDirectory else { return nil }
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        do {
            let fileUrl: URL
            if url.isFileURL {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                fileUrl = temporaryDirectory.appendingPathComponent("import.aix")
                try FileManager.default.copyItem(at: url, to: fileUrl)
            } else {
                fileUrl = try await EmbeddedNetwork.shared.session.download(for: URLRequest.from(url))
            }
            defer { if !url.isFileURL { try? FileManager.default.removeItem(at: fileUrl) } }
            try FileManager.default.unzipItem(at: fileUrl, to: temporaryDirectory)
            let payload = temporaryDirectory.appendingPathComponent("Payload")
            let source = try Source(from: payload)
            // Validate the ABI before replacing a working installation. No version bypass.
            for function in ["get_manga_list", "get_manga_details", "get_chapter_list", "get_page_list"] {
                _ = try source.globalStore.vm.function(named: function)
            }
            try await source.actor.initialize()
            guard !source.id.isEmpty, !source.id.contains("/"), source.id != ".", source.id != ".." else {
                throw SourceInstallError.invalidIdentifier
            }
            let destination = Self.directory.appendingPathComponent(source.id)
            let backup = temporaryDirectory.appendingPathComponent("PreviousSource")
            let hadPrevious = destination.exists
            if hadPrevious { try FileManager.default.moveItem(at: destination, to: backup) }
            do { try FileManager.default.moveItem(at: payload, to: destination) }
            catch {
                if hadPrevious { try? FileManager.default.moveItem(at: backup, to: destination) }
                throw error
            }
            source.url = destination
            do {
                try await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.createSource(source: source, context: context)
                    do { try context.save() }
                    catch { context.rollback(); throw error }
                }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if hadPrevious { try? FileManager.default.moveItem(at: backup, to: destination) }
                throw error
            }
            sources.removeAll { $0.id == source.id }
            sources.append(source)
            sources.sort {
                let lhs = Self.languageCodes.firstIndex(of: $0.manifest.info.lang) ?? 0
                let rhs = Self.languageCodes.firstIndex(of: $1.manifest.info.lang) ?? 0
                return lhs == rhs ? $0.manifest.info.name < $1.manifest.info.name : lhs < rhs
            }
            NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
            _ = try await source.getFilters()
            return source
        } catch {
            LogManager.logger.error("Source installation failed (\(url.isFileURL ? "local file" : url.host ?? "unknown host")): \(error.localizedDescription)")
            return nil
        }
    }

    enum SourceInstallError: Error { case invalidIdentifier }

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

    enum RepositoryError: LocalizedError {
        case modernABI
        var errorDescription: String? {
            "This is a modern Aidoku repository requiring the 0.7+ source ABI; use a legacy source list with the integrated runtime."
        }
    }

    static func repositoryIndexURL(_ url: URL) -> URL {
        url.pathExtension.lowercased() == "json" ? url : url.appendingPathComponent("index.min.json")
    }

    static func repositoryBaseURL(_ url: URL) -> URL {
        let index = repositoryIndexURL(url)
        return index.deletingLastPathComponent().appendingPathComponent("")
    }

    func loadSourceList(url: URL) async -> [ExternalSourceInfo]? {
        do {
            let indexURL = Self.repositoryIndexURL(url)
            let (data, response) = try await EmbeddedNetwork.shared.session.data(for: URLRequest(url: indexURL))
            try SourceHTTPValidation.validate(response)
            // A modern repository envelope is not proof of a compatible source ABI.
            // Decode legacy entries only; reject newer schemas rather than hiding all failures.
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["sources"] != nil {
                throw RepositoryError.modernABI
            }
            let sources = try JSONDecoder().decode([ExternalSourceInfo].self, from: data)
            return sources
        } catch {
            LogManager.logger.error("Repository load failed (\(url.host ?? "unknown")): \(error.localizedDescription)")
            return nil
        }
    }
}
