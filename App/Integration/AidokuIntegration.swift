// Yoru integration and iOS 26 navigation modernization. GPL-3.0-only.
import SwiftUI
import UIKit

private struct DownloadStatusBar: View {
    @State private var minimized = false
    @State private var download: Download?
    @State private var bytes = 0
    @State private var started = Date()
    @State private var paused = false
    @State private var visible = false
    private var elapsed: TimeInterval { max(0.1, Date().timeIntervalSince(started)) }
    private var speed: Double { Double(bytes) / elapsed }
    private var estimate: String {
        guard let download, download.progress > 0, download.total > download.progress, !paused else { return "ETA —" }
        let seconds = Int(elapsed * Double(download.total - download.progress) / Double(download.progress))
        return seconds >= 60 ? "~\(seconds / 60)m \(seconds % 60)s" : "~\(seconds)s"
    }
    var body: some View {
        Group {
            if visible, let download {
                HStack(spacing: 10) {
                    if !minimized {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paused ? "Downloads paused" : "Downloading · \(download.progress)/\(download.total) pages")
                                .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            ProgressView(value: Double(download.progress), total: Double(max(1, download.total))).tint(.green)
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · \(String(format: "%.2f", paused ? 0 : speed / 1_000_000)) MB/s · \(estimate)")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else { Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green) }
                    Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); withAnimation(.easeInOut(duration: 0.2)) { minimized.toggle() } } label: {
                        Image(systemName: minimized ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .bold)).padding(8)
                    }.accessibilityLabel(minimized ? "Expand download progress" : "Minimize download progress")
                }.padding(.horizontal, 15).padding(.vertical, 10).frame(maxWidth: minimized ? 65 : 340)
                    .glassEffect(.regular, in: .capsule).padding(.bottom, 8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("downloadProgressed")).receive(on: RunLoop.main)) { note in
            guard let next = note.object as? Download else { return }
            Task { @MainActor in
                let queue = await DownloadManager.shared.getDownloadQueue()
                guard queue[next.sourceId]?.contains(next) == true else { return }
                if download != next { bytes = 0; started = Date() }
                download = next; paused = DownloadManager.shared.downloadsPaused; visible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("yoruDownloadBytes")).receive(on: RunLoop.main)) { note in bytes += note.object as? Int ?? 0 }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("downloadsPaused")).receive(on: RunLoop.main)) { _ in paused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("downloadsResumed")).receive(on: RunLoop.main)) { _ in paused = false; started = Date(); bytes = 0 }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("downloadFinished")).receive(on: RunLoop.main)) { _ in
            Task { try? await Task.sleep(for: .seconds(1)); if !(await DownloadManager.shared.hasQueuedDownloads()) { visible = false } }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("downloadsCancelled")).receive(on: RunLoop.main)) { _ in
            Task { await refreshAfterCancellation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("downloadCancelled")).receive(on: RunLoop.main)) { _ in
            Task { await refreshAfterCancellation() }
        }
    }
    @MainActor private func refreshAfterCancellation() async {
        let remaining = await DownloadManager.shared.getDownloadQueue().values.flatMap { $0 }
        guard let current = download, remaining.contains(current) else {
            visible = false; download = nil; bytes = 0
            return
        }
    }
}

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
        let previous = (hostWindow ?? scene.keyWindow)?.snapshotView(afterScreenUpdates: false)
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
        crossfade(previous, into: window)
        if let url { (UIApplication.shared.delegate as? AppDelegate)?.handleUrl(url: url) }
    }
    static func dismiss() {
        NotificationCenter.default.post(name: Notification.Name("Yoru.flushReadingProgress"), object: nil)
        CoreDataManager.shared.saveIfNeeded()
        let previous = window?.snapshotView(afterScreenUpdates: false)
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
        crossfade(previous, into: hostWindow)
    }
    private static func crossfade(_ snapshot: UIView?, into destination: UIWindow?) {
        guard let snapshot, let destination else { return }
        snapshot.frame = destination.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.isUserInteractionEnabled = false
        destination.addSubview(snapshot)
        destination.layoutIfNeeded()
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.3,
                       delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            snapshot.alpha = 0
        } completion: { _ in snapshot.removeFromSuperview() }
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
        var configuration = UIButton.Configuration.glass()
        configuration.title = "Back to Yoru"
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.imagePadding = 6
        back.configuration = configuration
        back.accessibilityIdentifier = "aidoku.backToYoru"
        back.addTarget(self, action: #selector(returnToYoru), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(back)
        let downloadBar = UIHostingController(rootView: DownloadStatusBar())
        downloadBar.sizingOptions = .intrinsicContentSize
        addChild(downloadBar)
        downloadBar.view.backgroundColor = .clear
        downloadBar.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(downloadBar.view)
        downloadBar.didMove(toParent: self)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            back.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            back.heightAnchor.constraint(equalToConstant: 34),
            downloadBar.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            downloadBar.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -55),
            downloadBar.view.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -24)
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
        var config = UIButton.Configuration.glass()
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
