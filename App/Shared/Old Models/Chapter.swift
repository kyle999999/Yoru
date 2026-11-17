//
//  Chapter.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation

class Chapter: Codable, Identifiable {

    let sourceId: String
    let id: String
    var mangaId: String
    var title: String?
    var scanlator: String?
    var url: String?
    var lang: String
    var chapterNum: Float?
    var volumeNum: Float?
    var dateUploaded: Date?
    var sourceOrder: Int

    init(
        sourceId: String,
        id: String,
        mangaId: String,
        title: String?,
        scanlator: String? = nil,
        url: String? = nil,
        lang: String = "en",
        chapterNum: Float? = nil,
        volumeNum: Float? = nil,
        dateUploaded: Date? = nil,
        sourceOrder: Int
    ) {
        self.sourceId = sourceId
        self.id = id
        self.mangaId = mangaId
        self.title = title == "" ? nil : title
        self.scanlator = scanlator == "" ? nil : scanlator
        self.url = url == "" ? nil : url
        self.lang = lang
        self.chapterNum = chapterNum
        self.volumeNum = volumeNum
        self.dateUploaded = dateUploaded
        self.sourceOrder = sourceOrder
    }
}

extension Chapter: KVCObject {
    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "id": return id
        case "mangaId": return mangaId
        case "title": return title
        case "scanlator": return scanlator
        case "chapterNum": return chapterNum
        case "volumeNum": return volumeNum
        default: return nil
        }
    }
}

extension Chapter: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(sourceId)
        hasher.combine(mangaId)
        hasher.combine(id)
    }
}

extension Chapter: Equatable {
    static func == (lhs: Chapter, rhs: Chapter) -> Bool {
        lhs.sourceId == rhs.sourceId && lhs.mangaId == rhs.mangaId && lhs.id == rhs.id
    }
}

extension Chapter {
    /// Sources can assign extras the same numeric chapter as the main release.
    /// Only suppress a duplicate when its number and title both identify the
    /// same release. Unnumbered and explicitly labelled extras stay navigable.
    func isDuplicateRelease(of other: Chapter) -> Bool {
        if self == other { return true }
        guard chapterNum != nil, chapterNum == other.chapterNum, volumeNum == other.volumeNum else { return false }
        func label(_ value: String?) -> String {
            (value ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        }
        let ownTitle = label(title), otherTitle = label(other.title)
        let extras = #"[+＋]|\b(extra|special|bonus|omake|side[ -]?story)\b"#
        guard ownTitle.range(of: extras, options: .regularExpression) == nil,
              otherTitle.range(of: extras, options: .regularExpression) == nil else { return false }
        return ownTitle == otherTitle
    }

    /// Resume the latest reading session before offering older unread gaps.
    static func nextReadingChapter(newestFirst: [Chapter], history: [String: (page: Int, date: Int)]) -> Chapter? {
        let ordered = Array(newestFirst.reversed())
        let recent = ordered.enumerated().filter { history[$0.element.id]?.date ?? -1 > 0 }.max {
            let left = history[$0.element.id]!.date, right = history[$1.element.id]!.date
            return left == right ? $0.offset < $1.offset : left < right
        }
        if let recent {
            if history[recent.element.id]?.page != -1 { return recent.element }
            if let next = ordered.dropFirst(recent.offset + 1).first(where: { history[$0.id]?.page != -1 }) { return next }
        }
        return ordered.first { history[$0.id]?.page != -1 }
    }

    /// Keep automatic navigation in the selected translation stream.
    /// An explicit title filter takes priority; otherwise keep the language
    /// the reader opened. Empty tags remain a separate, unknown-language stream.
    func matchesReadingLanguage(of current: Chapter, preferredLanguage: String?, availableChapters: [Chapter] = []) -> Bool {
        func normalized(_ language: String) -> String {
            language.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
        }
        let preferred = normalized(preferredLanguage ?? "")
        let known = Set((availableChapters.map(\.lang) + [current.lang]).map(normalized).filter { !$0.isEmpty })
        let currentLanguage = normalized(current.lang)
        let language = !preferred.isEmpty ? preferred : !currentLanguage.isEmpty ? currentLanguage : known.count == 1 ? known.first! : ""
        let candidate = normalized(lang)
        // Untagged extras belong to a single-language stream, but must not be
        // guessed into a selected language in a genuinely multilingual list.
        if candidate.isEmpty { return language.isEmpty || known.isEmpty || known == [language] }
        return candidate == language
    }

    /// Returns a formatted title for this chapter.
    /// `Vol.X Ch.X - Title`
    func makeTitle() -> String {
        if volumeNum == nil && title == nil, let chapterNum = chapterNum {
            // Chapter X
            return String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
        } else {
            var components: [String] = []
            // Vol.X
            if let volumeNum = volumeNum {
                components.append(
                    String(format: NSLocalizedString("VOL_X", comment: ""), volumeNum)
                )
            }
            // Ch.X
            if let chapterNum = chapterNum {
                components.append(
                    String(format: NSLocalizedString("CH_X", comment: ""), chapterNum)
                )
            }
            // title
            if let title = title {
                if !components.isEmpty {
                    components.append("-")
                }
                components.append(title)
            }
            return components.joined(separator: " ")
        }
    }
}
