import CoreGraphics
import Foundation

enum ScreenRecordingPermissionStore {
    private static let hasRequestedAccessKey = "hasRequestedScreenRecordingAccess"
    private static let hasConfirmedGrantKey = "screenRecordingPermissionGranted"

    static var hasRequestedAccess: Bool {
        UserDefaults.standard.bool(forKey: hasRequestedAccessKey)
    }

    static var hasConfirmedGrant: Bool {
        UserDefaults.standard.bool(forKey: hasConfirmedGrantKey)
    }

    static func markAccessRequested() {
        UserDefaults.standard.set(true, forKey: hasRequestedAccessKey)
    }

    static func markGrantConfirmedIfGranted() -> Bool {
        guard CGPreflightScreenCaptureAccess() else { return false }

        UserDefaults.standard.set(true, forKey: hasConfirmedGrantKey)
        return true
    }

    static var needsRelaunchForGrantedAccess: Bool {
        hasRequestedAccess && !CGPreflightScreenCaptureAccess()
    }
}
