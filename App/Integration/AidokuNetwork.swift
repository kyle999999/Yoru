// Yoru integration, 2026-11-05. Isolated network cache and cookie persistence.
// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public final class EmbeddedNetwork: @unchecked Sendable {
    public static let shared = EmbeddedNetwork()
    public let cache: URLCache
    public let cookieStorage: HTTPCookieStorage
    public let session: URLSession
    private let cookieFile: URL
    private var observer: NSObjectProtocol?

    private init() {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aidoku", isDirectory: true)
        let cacheURL = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Aidoku/Network", isDirectory: true)
        try? manager.createDirectory(at: support, withIntermediateDirectories: true)
        try? manager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        cookieFile = support.appendingPathComponent("NetworkCookies.plist")
        cache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024, directory: cacheURL)
        let config = URLSessionConfiguration.ephemeral
        cookieStorage = config.httpCookieStorage!
        if let data = try? Data(contentsOf: cookieFile), let values = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]] {
            for value in values {
                let properties = Dictionary(uniqueKeysWithValues: value.map { (HTTPCookiePropertyKey($0.key), $0.value) })
                if let cookie = HTTPCookie(properties: properties) { cookieStorage.setCookie(cookie) }
            }
        }
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.protocolClasses = [ModernPageProtocol.self] + (config.protocolClasses ?? [])
        config.urlCache = cache
        config.httpCookieStorage = cookieStorage
        session = URLSession(configuration: config)
        observer = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSHTTPCookieManagerCookiesChanged, object: cookieStorage, queue: nil) { [weak self] _ in self?.saveCookies() }
    }
    public func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.protocolClasses = [ModernPageProtocol.self] + (config.protocolClasses ?? [])
        config.urlCache = cache
        config.httpCookieStorage = cookieStorage
        return config
    }
    public func saveCookies() {
        let values = (cookieStorage.cookies ?? []).compactMap(\.properties).map { properties in
            Dictionary(uniqueKeysWithValues: properties.map { key, value in
                (key.rawValue, (value as? URL)?.absoluteString as Any? ?? value)
            })
        }
        if let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) { try? data.write(to: cookieFile, options: .atomic) }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
