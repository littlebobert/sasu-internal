import Foundation
import Sparkle

@MainActor
final class AutoUpdateService: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var canCheckForUpdatesObservation: NSKeyValueObservation?

    init(startingUpdater: Bool = true) {
        DiagnosticLogger.log("Initializing Sparkle updater. startingUpdater=\(startingUpdater)", category: "Updater")
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
                DiagnosticLogger.log("Sparkle canCheckForUpdates=\(updater.canCheckForUpdates)", category: "Updater")
            }
        }
    }

    func checkForUpdates() {
        DiagnosticLogger.log("User requested update check. canCheckForUpdates=\(canCheckForUpdates)", category: "Updater")
        updaterController.checkForUpdates(nil)
    }
}
