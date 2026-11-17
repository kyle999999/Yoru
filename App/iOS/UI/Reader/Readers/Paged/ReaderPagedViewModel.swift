//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation

@MainActor
class ReaderPagedViewModel {

    var chapter: Chapter?
    var pages: [Page] = []

    var preloadedChapter: Chapter?
    var preloadedPages: [Page] = []
    private var loadGeneration = UUID()
    private var preloadGeneration = UUID()

    class var settings: SettingItem {
        SettingItem(type: "group", title: NSLocalizedString("PAGED", comment: ""), items: [
            SettingItem(
                type: "stepper",
                key: "Reader.pagesToPreload",
                title: NSLocalizedString("PAGES_TO_PRELOAD", comment: ""),
                minimumValue: 1,
                maximumValue: 10
            ),
            SettingItem(
                type: "select",
                key: "Reader.pagedPageLayout",
                title: NSLocalizedString("PAGE_LAYOUT", comment: ""),
                values: ["single", "double", "auto"],
                titles: [
                    NSLocalizedString("SINGLE_PAGE", comment: ""),
                    NSLocalizedString("DOUBLE_PAGE", comment: ""),
                    NSLocalizedString("AUTOMATIC", comment: "")
                ]
            )
        ])
    }

    func loadPages(chapter: Chapter) async {
        let generation = UUID()
        loadGeneration = generation
        preloadGeneration = UUID()
        if preloadedChapter == chapter {
            let previousChapter = self.chapter
            let previousPages = pages
            self.chapter = chapter
            pages = preloadedPages
            preloadedChapter = previousChapter
            preloadedPages = previousPages
        } else {
            let loaded = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageListWithoutContents(chapter: chapter)) ?? []
            guard loadGeneration == generation, !Task.isCancelled else { return }
            let previousChapter = self.chapter
            let previousPages = pages
            self.chapter = chapter
            pages = loaded
            preloadedChapter = previousChapter
            preloadedPages = previousPages
        }
    }

    func preload(chapter: Chapter) async {
        guard preloadedChapter != chapter else { return }
        let generation = UUID()
        preloadGeneration = generation
        let loaded = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageListWithoutContents(chapter: chapter)) ?? []
        guard preloadGeneration == generation, self.chapter != chapter, !Task.isCancelled else { return }
        preloadedPages = loaded
        preloadedChapter = chapter
    }
}
