//
//  SourceActor.swift
//  Aidoku
//
//  Created by Skitty on 2/21/22.
//

import Foundation

actor SourceActor {

    var source: Source

    enum SourceError: Error {
        case vmNotLoaded
        case missingValue
        case extensionFailure(function: String, code: Int32)
    }

    init(source: Source) {
        self.source = source
    }

    private var initialized = false
    func initialize() throws {
        guard !initialized else { return }
        // Legacy SDK initialization is optional (e.g. Komga, WEBTOON, xkcd).
        if (try? source.globalStore.vm.function(named: "initialize")) != nil {
            try source.globalStore.vm.call("initialize")
        }
        initialized = true
    }

    private func call(_ name: String, _ args: Int32...) throws -> Int32 {
        try initialize()
        do {
            // WasmInterpreter exposes typed overloads, not an array argument.
            let result: Int32
            switch args.count {
            case 1: result = try source.globalStore.vm.call(name, args[0])
            case 2: result = try source.globalStore.vm.call(name, args[0], args[1])
            default: throw SourceError.missingValue
            }
            guard result >= 0 else { throw SourceError.extensionFailure(function: name, code: result) }
            return result
        } catch {
            LogManager.logger.error("[\(source.id)] \(name): \(error)")
            throw error
        }
    }

    func getMangaList(filters: [FilterBase], page: Int = 1) throws -> MangaPageResult {
        let filterDescriptor = source.globalStore.storeStdValue(filters)
        defer { source.globalStore.removeStdValue(filterDescriptor) }

        let pageResultDescriptor: Int32 = (try call("get_manga_list", filterDescriptor, Int32(page)))

        let result = source.globalStore.readStdValue(pageResultDescriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(pageResultDescriptor)

        return result
    }

    func getMangaListing(listing: Listing, page: Int = 1) throws -> MangaPageResult {
        let listingDescriptor = source.globalStore.storeStdValue(listing)
        defer { source.globalStore.removeStdValue(listingDescriptor) }

        let pageResultDescriptor: Int32 = (try call("get_manga_listing", listingDescriptor, Int32(page)))

        let result = source.globalStore.readStdValue(pageResultDescriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(pageResultDescriptor)

        return result
    }

    func getMangaDetails(manga: Manga) throws -> Manga {
        let mangaDescriptor = source.globalStore.storeStdValue(manga)
        defer { source.globalStore.removeStdValue(mangaDescriptor) }

        let resultMangaDescriptor: Int32 = (try call("get_manga_details", mangaDescriptor))

        let manga = source.globalStore.readStdValue(resultMangaDescriptor) as? Manga
        source.globalStore.removeStdValue(resultMangaDescriptor)

        guard let manga = manga else { throw SourceError.missingValue }

        return manga
    }

    func getChapterList(manga: Manga) throws -> [Chapter] {
        let mangaDescriptor = source.globalStore.storeStdValue(manga)
        defer { source.globalStore.removeStdValue(mangaDescriptor) }

        source.globalStore.chapterCounter = 0
        source.globalStore.currentManga = manga.id

        let chapterListDescriptor: Int32 = (try call("get_chapter_list", mangaDescriptor))

        source.globalStore.chapterCounter = 0

        let chapters = source.globalStore.readStdValue(chapterListDescriptor) as? [Chapter] ?? []
        source.globalStore.removeStdValue(chapterListDescriptor)

        for i in 0..<chapters.count {
            chapters[i].mangaId = manga.id
        }

        return chapters
    }

    func getPageList(chapter: Chapter) throws -> [Page] {
        let chapterDescriptor = source.globalStore.storeStdValue(chapter)
        defer { source.globalStore.removeStdValue(chapterDescriptor) }

        let pageListDescriptor: Int32 = (try call("get_page_list", chapterDescriptor))

        var pages = source.globalStore.readStdValue(pageListDescriptor) as? [Page] ?? []
        source.globalStore.removeStdValue(pageListDescriptor)

        for i in 0..<pages.count {
            pages[i].chapterId = chapter.id
        }

        return pages
    }

    func getImageRequest(url: String) async throws -> WasmRequestObject {
        source.globalStore.requestsPointer += 1
        var request = WasmRequestObject(id: source.globalStore.requestsPointer)
        guard !url.isEmpty else { return request }

        request.URL = url

        // add cloudflare headers
        request.headers["User-Agent"] = await UserAgentProvider.shared.getUserAgent()
        if let url = URL(string: url),
           let cookies = HTTPCookie.requestHeaderFields(with: EmbeddedNetwork.shared.cookieStorage.cookies(for: url) ?? [])["Cookie"] {
            request.headers["Cookie"] = cookies
        }
        source.globalStore.requests[source.globalStore.requestsPointer] = request

        try? source.globalStore.vm.call("modify_image_request", Int32(request.id))

        guard let request = source.globalStore.requests[request.id] else { throw SourceError.missingValue }

        source.globalStore.requests.removeValue(forKey: request.id)

        return request
    }

    func handleUrl(url: String) throws -> DeepLink {
        let urlDescriptor = source.globalStore.storeStdValue(url)
        defer { source.globalStore.removeStdValue(urlDescriptor) }

        let deepLinkDescriptor: Int32 = (try call("handle_url", urlDescriptor))

        let deepLink = source.globalStore.readStdValue(deepLinkDescriptor) as? DeepLink
        source.globalStore.removeStdValue(deepLinkDescriptor)

        guard let deepLink = deepLink else { throw SourceError.missingValue }

        if let manga = deepLink.manga {
            deepLink.chapter?.mangaId = manga.id
        }

        return deepLink
    }

    func handleNotification(notification: String) {
        let notificationDescriptor = source.globalStore.storeStdValue(notification)

        try? source.globalStore.vm.call("handle_notification", notificationDescriptor)

        source.globalStore.removeStdValue(notificationDescriptor)
    }
}
