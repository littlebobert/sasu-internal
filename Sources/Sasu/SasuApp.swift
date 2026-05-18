import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.saveWindowStateForNextLaunch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }

        appModel?.showWindowForReopen()
        return true
    }
}

@main
@MainActor
struct SasuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel
    private let aboutWindowController = AboutWindowController()

    init() {
        let appModel = AppModel()
        _appModel = StateObject(wrappedValue: appModel)
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
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appModel.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Sasu") {
                Button("Capture Screen") {
                    appModel.captureAndAsk()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
