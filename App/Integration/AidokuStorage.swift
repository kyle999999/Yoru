// Yoru integration, 2026-11-05. GPL-3.0.
import Foundation

/// Never use the host app's defaults or top-level data directories for Aidoku.
enum AidokuStorage {
    #if AIDOKU_ISOLATION_CHECKS
    static let domain = "yoru.aidoku.isolation-checks." + UUID().uuidString
    #else
    static let domain = "studio.yoru.embedded-aidoku"
    #endif
    static let defaults = UserDefaults(suiteName: domain)!
    static func directory(_ kind: FileManager.SearchPathDirectory) -> URL {
        #if targetEnvironment(macCatalyst)
        let folder = "Yoru/Aidoku"
        #else
        let folder = "Aidoku"
        #endif
        let directory = FileManager.default.urls(for: kind, in: .userDomainMask)[0]
            .appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

