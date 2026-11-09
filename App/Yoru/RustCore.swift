import Foundation

// C ABI bridge: borrowed buffers, fixed-width integers, no shared allocators.
@_silgen_name("yoru_rust_streak")
private func rustStreak(_ days: UnsafePointer<Int64>?, _ count: UInt, _ today: Int64, _ output: UnsafeMutablePointer<Int64>) -> Int32
@_silgen_name("yoru_rust_progress")
private func rustProgress(_ watched: Int64, _ delta: Int64, _ total: Int64, _ hasTotal: Int32) -> Int64
@_silgen_name("yoru_rust_validate_journal")
private func rustValidateJournal(_ hasText: Int32, _ future: Int32, _ rating: Int64, _ hasRating: Int32, _ episode: Int64, _ hasEpisode: Int32, _ total: Int64, _ hasTotal: Int32) -> Int32

enum RustCore {
    static func streak(_ dates: [Date], today: Date, calendar: Calendar) -> [Int64] {
        let days = dates.map { Int64(calendar.dateComponents([.day], from: today, to: $0).day!) }
        var result = [Int64](repeating: 0, count: 4)
        let valid = days.withUnsafeBufferPointer { input in
            result.withUnsafeMutableBufferPointer { output in
                rustStreak(input.baseAddress, UInt(input.count), 0, output.baseAddress!)
            }
        }
        precondition(valid == 1, "Invalid Rust streak buffer")
        return result
    }
    static func progress(_ watched: Int, delta: Int, total: Int?) -> Int {
        Int(rustProgress(Int64(watched), Int64(delta), Int64(total ?? 0), total == nil ? 0 : 1))
    }
    static func validate(_ draft: JournalEntry, total: Int?, now: Date, calendar: Calendar) throws {
        let hasText = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let future = calendar.startOfDay(for: draft.watchedOn) > calendar.startOfDay(for: now)
        switch rustValidateJournal(hasText ? 1 : 0, future ? 1 : 0, Int64(draft.rating ?? 0), draft.rating == nil ? 0 : 1, Int64(draft.episode ?? 0), draft.episode == nil ? 0 : 1, Int64(total ?? 0), total == nil ? 0 : 1) {
        case 0: return
        case 1: throw LibraryValidation.emptyEntry
        case 2: throw LibraryValidation.futureDate
        case 3: throw LibraryValidation.invalidRating
        case 4: throw LibraryValidation.invalidEpisode
        default: preconditionFailure("Unknown Rust validation code")
        }
    }
}
