// Yoru integration, 2026-11-06. GPL-3.0-only.
import UIKit
import SwiftUI
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: YoruHostRoot())
        window.tintColor = UIColor(YoruTheme.violet)
        self.window = window
        window.makeKeyAndVisible()
        AidokuIntegration.hostWindow = window
        if let url = connectionOptions.urlContexts.first?.url { DispatchQueue.main.async { AidokuIntegration.present(url: url) } }
    }
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        if let url = contexts.first?.url { DispatchQueue.main.async { AidokuIntegration.present(url: url) } }
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        if AidokuIntegration.wantsOpen { AidokuIntegration.window?.makeKeyAndVisible() }
        HostLifecycle.shared.phase = AidokuIntegration.wantsOpen ? .inactive : .active
    }
    func sceneWillResignActive(_ scene: UIScene) { HostLifecycle.shared.phase = .inactive }
    func sceneDidEnterBackground(_ scene: UIScene) { HostLifecycle.shared.phase = .background; EmbeddedNetwork.shared.saveCookies() }
}
