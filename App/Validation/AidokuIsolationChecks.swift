import Foundation
@main struct AidokuIsolationChecks {
    static func main() throws {
        let host = UserDefaults.standard
        let sentinel = Data("host-library-must-survive".utf8)
        let key = "yoru.library.v3"
        let previous = host.object(forKey: key)
        defer { host.set(previous, forKey: key); AidokuStorage.defaults.removePersistentDomain(forName: AidokuStorage.domain) }
        host.set(sentinel, forKey: key)
        AidokuStorage.defaults.set("light", forKey: "Appearance.appearance")
        AidokuStorage.defaults.set("local-test", forKey: "Browse.sourceLists")
        assert(host.data(forKey: key) == sentinel)
        assert(host.string(forKey: "Appearance.appearance") == nil)
        AidokuStorage.defaults.removePersistentDomain(forName: AidokuStorage.domain)
        assert(host.data(forKey: key) == sentinel, "Aidoku reset must not erase Yoru")
        assert(AidokuStorage.defaults.string(forKey: "Browse.sourceLists") == nil)
        print("PASS: Aidoku preferences, source settings, and reset are isolated from host library")
    }
}
