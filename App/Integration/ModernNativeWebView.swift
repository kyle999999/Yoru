// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import WebKit
import UIKit

@MainActor private final class ModernBrowser: NSObject, WKNavigationDelegate {
    let view: WKWebView
    var loaded = false
    var failure: Error?
    init(id: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "8E8834F8-18A8-4EC8-B965-ED03751F2446")!)
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init(); view.navigationDelegate = self; view.alpha = 0.01
        AidokuIntegration.activeWindow?.rootViewController?.view.addSubview(view)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loaded = true; failure = error }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loaded = true; failure = error }
    func wait() async throws {
        let deadline = Date().addingTimeInterval(40)
        while !loaded {
            if Date() > deadline { throw URLError(.timedOut) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if let failure { throw failure }
    }
}

enum ModernNativeWebView {
    @MainActor private static var browsers: [String: ModernBrowser] = [:]
    static func perform(_ input: [String: Any]) -> [String: Any] {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Task { @MainActor in
            do { box.value = try await execute(input) }
            catch { box.value = ["error": error.localizedDescription] }
            semaphore.signal()
        }
        semaphore.wait(); return box.value
    }
    private final class ResultBox: @unchecked Sendable { var value: [String: Any] = [:] }
    @MainActor private static func execute(_ input: [String: Any]) async throws -> [String: Any] {
        let action = input["action"] as? String ?? ""
        if action == "create" { let id = UUID().uuidString; browsers[id] = ModernBrowser(id: id); return ["id": id] }
        guard let id = input["id"] as? String, let browser = browsers[id] else { throw URLError(.resourceUnavailable) }
        switch action {
        case "close": browser.view.stopLoading(); browser.view.removeFromSuperview(); browsers.removeValue(forKey: id)
        case "load":
            guard let url = (input["url"] as? String).flatMap(URL.init(string:)) else { throw URLError(.badURL) }
            for cookie in EmbeddedNetwork.shared.cookieStorage.cookies(for: url) ?? [] { await browser.view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) }
            var request = URLRequest(url: url)
            request.httpMethod = input["method"] as? String ?? "GET"
            for (key, values) in input["headers"] as? [String: [String]] ?? [:] { request.setValue(values.joined(separator: ", "), forHTTPHeaderField: key) }
            if let body = input["body"] as? String { request.httpBody = Data(base64Encoded: body) }
            browser.loaded = false; browser.failure = nil; browser.view.load(request)
        case "html":
            browser.loaded = false; browser.failure = nil
            browser.view.loadHTMLString(input["html"] as? String ?? "", baseURL: (input["url"] as? String).flatMap(URL.init(string:)))
        case "wait": try await browser.wait()
        case "eval":
            try await browser.wait()
            let script = input["script"] as? String ?? ""
            let value: Any?
            if input["async"] as? Bool == true {
                value = try await browser.view.callAsyncJavaScript("return await (\(script));", arguments: [:], in: nil, contentWorld: .page)
            } else { value = try await browser.view.evaluateJavaScript(script) }
            return ["value": value ?? NSNull()]
        case "script":
            browser.view.configuration.userContentController.addUserScript(WKUserScript(source: input["script"] as? String ?? "", injectionTime: input["end"] as? Bool == true ? .atDocumentEnd : .atDocumentStart, forMainFrameOnly: input["main"] as? Bool ?? true))
        case "rules":
            let rules = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: id, encodedContentRuleList: input["rules"] as? String ?? "[]")
            if let rules { browser.view.configuration.userContentController.add(rules) }
        case "cookies":
            let cookies = await browser.view.configuration.websiteDataStore.httpCookieStore.allCookies()
            for cookie in cookies { EmbeddedNetwork.shared.cookieStorage.setCookie(cookie) }
            return ["value": cookies.map { ["name": $0.name, "value": $0.value, "domain": $0.domain] }]
        case "deleteCookie":
            for cookie in await browser.view.configuration.websiteDataStore.httpCookieStore.allCookies() where cookie.name == input["name"] as? String && cookie.domain == input["domain"] as? String { await browser.view.configuration.websiteDataStore.httpCookieStore.delete(cookie) }
        default: throw URLError(.unsupportedURL)
        }
        return [:]
    }
}
