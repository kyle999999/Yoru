// SPDX-License-Identifier: GPL-3.0-only
import UIKit
import WebKit

@MainActor enum ModernSourceLogin {
    static func present(item: SettingItem, source: Source, from controller: UIViewController) {
        guard let storedKey = item.key else { return }
        let prefix = source.id + "."
        let key = storedKey.hasPrefix(prefix) ? String(storedKey.dropFirst(prefix.count)) : storedKey
        if item.method == "web" {
            let address = item.urlKey.flatMap { AidokuStorage.defaults.string(forKey: $0) } ?? item.url ?? source.manifest.info.urls?.first ?? source.manifest.info.url ?? ""
            guard let url = URL(string: address) else { return }
            let login = SourceWebLogin(url: url) { cookies in
                Task {
                    do {
                        let accepted = try await source.actor.modernOperation("webLogin", parameters: ["Key": key, "Cookies": cookies]) as? Bool ?? false
                        if !accepted { showError("The source did not accept this login.", from: controller) }
                    } catch { showError(error.localizedDescription, from: controller) }
                }
            }
            controller.present(UINavigationController(rootViewController: login), animated: true)
            return
        }
        let alert = UIAlertController(title: item.title ?? "Sign in", message: source.manifest.info.name, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Username or email"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no; $0.textContentType = .username }
        alert.addTextField { $0.placeholder = "Password"; $0.isSecureTextEntry = true; $0.textContentType = .password }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign in", style: .default) { _ in
            let username = alert.textFields?.first?.text ?? ""
            let password = alert.textFields?.last?.text ?? ""
            Task {
                do {
                    let accepted = try await source.actor.modernOperation("basicLogin", parameters: ["Key": key, "Username": username, "Password": password]) as? Bool ?? false
                    if !accepted { showError("The source did not accept this login.", from: controller) }
                } catch { showError(error.localizedDescription, from: controller) }
            }
        })
        controller.present(alert, animated: true)
    }
    static func showError(_ message: String, from controller: UIViewController) {
        let alert = UIAlertController(title: "Sign-in failed", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel)); controller.present(alert, animated: true)
    }
}

@MainActor private final class SourceWebLogin: UIViewController {
    let url: URL
    let complete: ([String: String]) -> Void
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "8E8834F8-18A8-4EC8-B965-ED03751F2446")!)
        return WKWebView(frame: .zero, configuration: config)
    }()
    init(url: URL, complete: @escaping ([String: String]) -> Void) { self.url = url; self.complete = complete; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { view = webView }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Sign in"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.finish() })
        webView.load(URLRequest(url: url))
    }
    private func finish() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            var values: [String: String] = [:]
            for cookie in cookies {
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                guard self.url.host == domain || (self.url.host?.hasSuffix("." + domain) ?? false) else { continue }
                values[cookie.name] = cookie.value; EmbeddedNetwork.shared.cookieStorage.setCookie(cookie)
            }
            self.dismiss(animated: true) { self.complete(values) }
        }
    }
}
