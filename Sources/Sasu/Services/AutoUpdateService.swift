import Foundation
import Sparkle

final class SasuSparkleUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    weak var appModel: AppModel?

    func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            appModel?.beginUpdatePresentation()
        }
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }

        Task { @MainActor in
            appModel?.beginUpdatePresentation()
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            appModel?.endUpdatePresentation()
        }
    }
}

@MainActor
final class AutoUpdateService: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private let userDriverDelegate: SasuSparkleUserDriverDelegate
    private var canCheckForUpdatesObservation: NSKeyValueObservation?

    init(appModel: AppModel, startingUpdater: Bool = true) {
        let userDriverDelegate = SasuSparkleUserDriverDelegate()
        userDriverDelegate.appModel = appModel
        self.userDriverDelegate = userDriverDelegate

        DiagnosticLogger.log("Initializing Sparkle updater. startingUpdater=\(startingUpdater)", category: "Updater")
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
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
