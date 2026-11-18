import UIKit

/// Give a queued database save time to finish when the reader/app is hidden.
@MainActor final class ReadingSaveBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save reading progress") { [weak self] in
            Task { @MainActor in self?.finish() }
        }
    }
    func finish() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
