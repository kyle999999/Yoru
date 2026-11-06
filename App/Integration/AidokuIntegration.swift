// Yoru integration and iOS 26 navigation modernization. GPL-3.0-only.
import SwiftUI
import UIKit

@MainActor final class HostLifecycle: ObservableObject {
    static let shared = HostLifecycle()
    @Published var phase: ScenePhase = .inactive
}
struct YoruHostRoot: View {
    @ObservedObject private var lifecycle = HostLifecycle.shared
    var body: some View { ContentView().environment(\.scenePhase, lifecycle.phase) }
}

@MainActor enum AidokuIntegration {
    static var wantsOpen = false
    static var window: UIWindow?
    static weak var hostWindow: UIWindow?
    static var isOpen: Bool { wantsOpen && window?.isHidden == false }
    static var activeWindow: UIWindow? { isOpen ? window : hostWindow }
    static func present(url: URL? = nil) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        wantsOpen = true
        HostLifecycle.shared.phase = .inactive
        if window == nil {
            hostWindow = scene.keyWindow
            let nativeWindow = UIWindow(windowScene: scene)
            nativeWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            nativeWindow.rootViewController = AidokuModernTabs()
            nativeWindow.tintColor = .systemPink
            window = nativeWindow
        }
        window?.overrideUserInterfaceStyle = AidokuStorage.defaults.bool(forKey: "General.useSystemAppearance") ? .unspecified : AidokuStorage.defaults.integer(forKey: "General.appearance") == 0 ? .light : .dark
        window?.makeKeyAndVisible()
        if let url { (UIApplication.shared.delegate as? AppDelegate)?.handleUrl(url: url) }
    }
    static func dismiss() {
        EmbeddedNetwork.shared.saveCookies()
        wantsOpen = false
        window?.isHidden = true
        HostLifecycle.shared.phase = .active
        hostWindow?.makeKeyAndVisible()
    }
}

private final class AidokuModernTabs: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let library = SwiftUINavigationController(rootViewController: LibraryViewController())
        let browse = UINavigationController(rootViewController: BrowseViewController())
        let history = UINavigationController(rootViewController: HistoryViewController())
        let search = UINavigationController(rootViewController: SearchViewController())
        let settings = UINavigationController(rootViewController: SettingsViewController())
        for navigation in [library, browse, history, search, settings] { navigation.navigationBar.prefersLargeTitles = true }
        let searchTab = UISearchTab { _ in search }
        searchTab.automaticallyActivatesSearch = true
        tabs = [
            UITab(title: NSLocalizedString("LIBRARY", comment: ""), image: UIImage(systemName: "books.vertical.fill"), identifier: "library") { _ in library },
            UITab(title: NSLocalizedString("BROWSE", comment: ""), image: UIImage(systemName: "globe"), identifier: "browse") { _ in browse },
            UITab(title: NSLocalizedString("HISTORY", comment: ""), image: UIImage(systemName: "clock.fill"), identifier: "history") { _ in history },
            UITab(title: NSLocalizedString("SETTINGS", comment: ""), image: UIImage(systemName: "gear"), identifier: "settings") { _ in settings },
            searchTab
        ]
        tabBarMinimizeBehavior = .onScrollDown
        let count = AidokuStorage.defaults.integer(forKey: "Browse.updateCount")
        browse.tabBarItem.badgeValue = count > 0 ? String(count) : nil
        additionalSafeAreaInsets.top = 34
        let back = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Back to Yoru"
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.imagePadding = 6
        back.configuration = configuration
        back.accessibilityIdentifier = "aidoku.backToYoru"
        back.addTarget(self, action: #selector(returnToYoru), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(back)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            back.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            back.heightAnchor.constraint(equalToConstant: 34)
        ])
    }
    @objc private func returnToYoru() { AidokuIntegration.dismiss() }
}
