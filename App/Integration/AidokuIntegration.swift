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
    #if targetEnvironment(macCatalyst)
    private static var macHostController: UIViewController?
    private static var macMangaController: MacAidokuTabs?
    #endif
    static var isOpen: Bool { wantsOpen && window?.isHidden == false }
    static var activeWindow: UIWindow? { isOpen ? window : hostWindow }
    static func present(url: URL? = nil) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        wantsOpen = true
        HostLifecycle.shared.phase = .inactive
        #if targetEnvironment(macCatalyst)
        guard let nativeWindow = hostWindow ?? scene.keyWindow else { return }
        if macHostController == nil { macHostController = nativeWindow.rootViewController }
        if macMangaController == nil { macMangaController = MacAidokuTabs() }
        window = nativeWindow
        nativeWindow.rootViewController = macMangaController
        #else
        if window == nil {
            hostWindow = scene.keyWindow
            let nativeWindow = UIWindow(windowScene: scene)
            nativeWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            nativeWindow.rootViewController = AidokuModernTabs()
            nativeWindow.tintColor = .systemPink
            window = nativeWindow
        }
        #endif
        window?.overrideUserInterfaceStyle = AidokuStorage.defaults.bool(forKey: "General.useSystemAppearance") ? .unspecified : AidokuStorage.defaults.integer(forKey: "General.appearance") == 0 ? .light : .dark
        window?.makeKeyAndVisible()
        if let url { (UIApplication.shared.delegate as? AppDelegate)?.handleUrl(url: url) }
    }
    static func dismiss() {
        EmbeddedNetwork.shared.saveCookies()
        wantsOpen = false
        #if targetEnvironment(macCatalyst)
        macMangaController?.dismiss(animated: false)
        window?.rootViewController = macHostController
        window?.overrideUserInterfaceStyle = .unspecified
        window = nil
        #else
        window?.isHidden = true
        #endif
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

#if targetEnvironment(macCatalyst)
// Catalyst moves tab bars into the window toolbar. A persistent in-content
// selector prevents the host SwiftUI toolbar from hiding manga navigation.
private final class MacAidokuTabs: UITabBarController {
    private let selector = UISegmentedControl(items: ["Library", "Browse", "History", "Search", "Settings"])
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        viewControllers = [
            SwiftUINavigationController(rootViewController: LibraryViewController()),
            UINavigationController(rootViewController: BrowseViewController()),
            UINavigationController(rootViewController: HistoryViewController()),
            UINavigationController(rootViewController: SearchViewController()),
            UINavigationController(rootViewController: SettingsViewController())
        ]
        mode = .tabBar
        tabBar.isHidden = true
        additionalSafeAreaInsets.top = 52
        selector.selectedSegmentIndex = 0
        selector.accessibilityLabel = "Aidoku navigation"
        selector.addTarget(self, action: #selector(selectSection), for: .valueChanged)
        let back = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "Back to Yoru"; config.image = UIImage(systemName: "chevron.left"); config.imagePadding = 6
        back.configuration = config
        back.accessibilityIdentifier = "aidoku.backToYoru"
        back.addTarget(self, action: #selector(returnToYoru), for: .touchUpInside)
        let bar = UIStackView(arrangedSubviews: [back, selector])
        bar.axis = .horizontal; bar.spacing = 16; bar.alignment = .center
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            back.widthAnchor.constraint(equalToConstant: 155),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    @objc private func selectSection() { selectedIndex = selector.selectedSegmentIndex }
    @objc private func returnToYoru() { AidokuIntegration.dismiss() }
}
#endif
