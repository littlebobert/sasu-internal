import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.saveWindowStateForNextLaunch()
        appModel?.performRelaunchIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }

        appModel?.showWindowForReopen()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            appModel?.handleOpenedURL(url)
        }
    }
}

@main
@MainActor
struct SasuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel
    @StateObject private var autoUpdateService: AutoUpdateService
    private let aboutWindowController = AboutWindowController()

    init() {
        DiagnosticLogger.log("App init. version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")", category: "Lifecycle")
        let appModel = AppModel()
        _appModel = StateObject(wrappedValue: appModel)
        _autoUpdateService = StateObject(wrappedValue: AutoUpdateService(appModel: appModel))
        appDelegate.appModel = appModel

        Task { @MainActor in
            NSApp.setActivationPolicy(.regular)
            appModel.start()
            appModel.showLaunchWindowIfNeeded()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Sasu") {
                    appModel.beginAboutWindowPresentation()
                    aboutWindowController.show {
                        appModel.endAboutWindowPresentation()
                    }
                }

                Divider()

                Button("Check for Updates…") {
                    appModel.prepareForUpdatePresentation()
                    autoUpdateService.checkForUpdates()
                }
                .disabled(!autoUpdateService.canCheckForUpdates)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appModel.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Sasu") {
                Button("Show Transcript") {
                    appModel.showTranscriptWindow()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Divider()

                Button("Capture Screen") {
                    appModel.captureAndAsk()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Translate Clipboard") {
                    appModel.translateClipboard()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])

                Button("Translate Selection") {
                    appModel.translateSelection()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}
