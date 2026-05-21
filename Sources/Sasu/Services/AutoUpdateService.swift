import Foundation
import Sparkle

@MainActor
final class AutoUpdateService: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var canCheckForUpdatesObservation: NSKeyValueObservation?

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        canCheckForUpdatesObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
