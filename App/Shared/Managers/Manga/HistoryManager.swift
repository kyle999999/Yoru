//
//  HistoryManager.swift
//  Aidoku
//
//  Created by Skitty on 1/9/23.
//

import CoreData

// The private context is only accessed through perform, which serializes writes.
final class HistoryManager: @unchecked Sendable {
    static let shared = HistoryManager()
    private let writingContext: NSManagedObjectContext
    private init() {
        writingContext = CoreDataManager.shared.container.newBackgroundContext()
        writingContext.automaticallyMergesChangesFromParent = true
        writingContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

extension HistoryManager {

    @discardableResult
    func setProgress(chapter: Chapter, progress: Int, totalPages: Int? = nil, completed: Bool = false, manga: Manga? = nil) async -> Bool {
        guard progress > 0 else { return false }
        let result = await writingContext.perform { () -> (saved: Bool, newlyCompleted: Bool, completed: Bool) in
            let manager = CoreDataManager.shared
            // Retain display metadata so History works offline, even for titles
            // read without first adding them to the library.
            let storedManga = manager.getManga(sourceId: chapter.sourceId, mangaId: chapter.mangaId, context: self.writingContext)
                ?? manager.getOrCreateManga(manga ?? Manga(sourceId: chapter.sourceId, id: chapter.mangaId), context: self.writingContext)
            if !manager.hasChapter(sourceId: chapter.sourceId, mangaId: chapter.mangaId, chapterId: chapter.id, context: self.writingContext) {
                manager.createChapter(chapter, mangaObject: storedManga, context: self.writingContext)
            }
            let history = manager.getOrCreateHistory(sourceId: chapter.sourceId, mangaId: chapter.mangaId, chapterId: chapter.id, context: self.writingContext)
            let wasCompleted = history.completed
            manager.setRead(sourceId: chapter.sourceId, mangaId: chapter.mangaId, context: self.writingContext)
            manager.setProgress(progress, sourceId: chapter.sourceId, mangaId: chapter.mangaId, chapterId: chapter.id, totalPages: totalPages, context: self.writingContext)
            if completed || (totalPages.map { $0 > 0 && progress >= $0 } ?? false) { history.completed = true }
            do {
                try self.writingContext.save()
                return (true, !wasCompleted && history.completed, history.completed)
            } catch {
                self.writingContext.rollback()
                LogManager.logger.error("HistoryManager.setProgress: \(error.localizedDescription)")
                return (false, false, false)
            }
        }
        guard result.saved else { return false }
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("historySet"), object: (chapter: chapter, page: result.completed ? -1 : progress))
        }
        if result.newlyCompleted {
            Task { await TrackerManager.shared.setCompleted(chapter: chapter) }
        }
        return true
    }

    func addHistory(chapters: [Chapter], date: Date = Date()) async {
        // get unique set of manga ids from chapters array
        let mangaItems = Set(chapters.map { MangaInfo(mangaId: $0.mangaId, sourceId: $0.sourceId) })
        // mark each manga as read
        let saved = await writingContext.perform { () -> Bool in
            let context = self.writingContext
            for item in mangaItems {
                CoreDataManager.shared.setRead(
                    sourceId: item.sourceId,
                    mangaId: item.mangaId,
                    context: context
                )
            }
            // mark chapters as read
            CoreDataManager.shared.setCompleted(chapters: chapters, date: date, context: context)
            do {
                try context.save()
                return true
            } catch {
                context.rollback()
                LogManager.logger.error("HistoryManager.addHistory: \(error.localizedDescription)")
                return false
            }
        }
        guard saved else { return }
        // update tracker with chapter with largest number
        if let maxChapter = chapters.max(by: { $0.chapterNum ?? 0 < $1.chapterNum ?? 0 }) {
            await TrackerManager.shared.setCompleted(chapter: maxChapter)
        }
        await MainActor.run { NotificationCenter.default.post(name: NSNotification.Name("historyAdded"), object: chapters) }
    }

    func removeHistory(chapters: [Chapter]) async {
        let saved = await writingContext.perform { () -> Bool in
            let context = self.writingContext
            for chapter in chapters {
                if let history = CoreDataManager.shared.getHistory(sourceId: chapter.sourceId, mangaId: chapter.mangaId, chapterId: chapter.id, context: context) { context.delete(history) }
            }
            do { try context.save(); return true }
            catch { context.rollback(); LogManager.logger.error("HistoryManager.removeHistory: \(error.localizedDescription)"); return false }
        }
        guard saved else { return }
        await MainActor.run { NotificationCenter.default.post(name: NSNotification.Name("historyRemoved"), object: chapters) }
    }

    func removeHistory(manga: Manga) async {
        let saved = await writingContext.perform { () -> Bool in
            let context = self.writingContext
            CoreDataManager.shared.removeHistory(sourceId: manga.sourceId, mangaId: manga.id, context: context)
            do { try context.save(); return true }
            catch { context.rollback(); LogManager.logger.error("HistoryManager.removeHistory: \(error.localizedDescription)"); return false }
        }
        guard saved else { return }
        await MainActor.run { NotificationCenter.default.post(name: NSNotification.Name("historyRemoved"), object: manga) }
    }
}
