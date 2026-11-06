//
//  WasmNetWebViewHandler.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/23.
//

import WebKit

class WasmNetWebViewHandler: NSObject, WKNavigationDelegate {

    var netModule: WasmNet
    var request: URLRequest
    let browserVerification: Bool

    lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "8E8834F8-18A8-4EC8-B965-ED03751F2446")!)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.customUserAgent = request.value(forHTTPHeaderField: "User-Agent")
        webView.load(request)
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

    #if !os(macOS)
    var popup: WebViewViewController?
    #endif

    var done = false

    var popupShown: Bool {
        popup?.presentingViewController != nil
    }

    init(netModule: WasmNet, request: URLRequest, browserVerification: Bool = false) {
        self.netModule = netModule
        self.request = request
        self.browserVerification = browserVerification
    }

    func load() {
        #if os(OSX)
        let view = NSApplication.shared.windows.first?.contentView
        #else
        let view = (UIApplication.shared.delegate as? AppDelegate)?.visibleViewController?.view
        #endif
        guard let view = view else {
            netModule.semaphore.signal()
            return
        }
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: 0),
            webView.heightAnchor.constraint(equalToConstant: 0),
            webView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // timeout after 12s if bypass doesn't work
        perform(#selector(timeout), with: nil, afterDelay: browserVerification ? 30 : 12)
    }

    func openWebViewPopup() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(timeout), with: nil, afterDelay: 90)
        webView.removeFromSuperview()
        popup?.dismiss(animated: true)

        #if os(OSX)
        // todo
        timeout()
        return
        #else
        popup = WebViewViewController()
        popup!.handler = self
        popup!.view.addSubview(webView)
        webView.navigationDelegate = popup

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalTo: popup!.view.widthAnchor),
            webView.heightAnchor.constraint(equalTo: popup!.view.heightAnchor),
            webView.centerXAnchor.constraint(equalTo: popup!.view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: popup!.view.centerYAnchor)
        ])

        let vc = (UIApplication.shared.delegate as? AppDelegate)?.visibleViewController
        vc?.present(popup!, animated: true)
        #endif
    }

    @objc func timeout() {
        if !done {
            done = true
            webView.removeFromSuperview()
            popup?.dismiss(animated: true)
            LogManager.logger.error("[\(netModule.globalStore.id)] website challenge timed out; original HTTP response retained")
            netModule.semaphore.signal()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !done else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { webViewCookies in
            guard !self.done else { return }
            guard let url = self.request.url else { return }

            // check for old (expired) clearance cookie
            let oldCookie = EmbeddedNetwork.shared.cookieStorage.cookies(for: url)?.first { $0.name == "cf_clearance" }
            if let oldCookie {
                EmbeddedNetwork.shared.cookieStorage.deleteCookie(oldCookie)
            }

            // delay captcha check by 3s (so it loads in)
            #if !os(OSX)
            if self.popup == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.checkForCaptcha()
                }
                // try again in 5s if the first check didn't catch the captcha (dumb hack)
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    self.checkForCaptcha()
                }
            }
            #endif

            // check for clearance cookie
            let browserVerified = self.browserVerification
                && webView.url?.host == url.host
                && webView.url?.path != "/edge/challenge"
            guard browserVerified || (!self.browserVerification && webViewCookies.contains(where: {
                $0.name == "cf_clearance" &&
                $0.value != oldCookie?.value ?? "" &&
                ($0.domain.contains(url.host ?? "") || (url.host?.contains($0.domain) ?? false))
            })) else {
                return
            }

            webView.removeFromSuperview()
            self.done = true
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            #if !os(OSX)
            self.popup?.dismiss(animated: true)
            #endif

            // save cookies for future requests
            EmbeddedNetwork.shared.cookieStorage.setCookies(webViewCookies, for: url, mainDocumentURL: url)
            if let cookies = HTTPCookie.requestHeaderFields(with: webViewCookies)["Cookie"] {
                self.request.addValue(cookies, forHTTPHeaderField: "Cookie")
            }

            // re-send request
            EmbeddedNetwork.shared.session.dataTask(with: self.request) { data, response, error in
                self.netModule.lastResponseSummary = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1), \(data?.count ?? 0) bytes, \((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "unknown type") from \(response?.url?.host ?? "unknown")"
                self.netModule.storedResponse = WasmResponseObject(data: data, response: response, error: error)
                self.netModule.incrementRequest()
                self.netModule.semaphore.signal()
            }.resume()
        }
    }

    @MainActor
    func checkForCaptcha() {
        guard !done, !popupShown else { return }
        // check if captcha or verify button is shown
        webView.evaluateJavaScript("""
        document.querySelector('#challenge-stage iframe') !== null
            || document.querySelector('.hcaptcha-box iframe') !== null
            || document.querySelector('#challenge-stage input[type=button]') !== null
            || document.body.textContent.includes('Verify you are human by completing')
        """
        ) { html, _ in
            if html as? Int == 1 {
                if !self.popupShown {
                    self.openWebViewPopup()
                }
            }
        }
    }
}
