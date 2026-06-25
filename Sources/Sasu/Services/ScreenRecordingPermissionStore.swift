import CoreGraphics
import Foundation

enum ScreenRecordingPermissionStore {
    private static let hasStartedSetupKey = "hasStartedScreenRecordingSetup"
    private static let legacyHasRequestedAccessKey = "hasRequestedScreenRecordingAccess"
    private static let legacyHasPresentedPrimerKey = "hasPresentedScreenRecordingPrimer"
    private static let hasConfirmedGrantKey = "screenRecordingPermissionGranted"

    static var hasStartedSetup: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hasStartedSetupKey) {
            return true
        }

        if defaults.bool(forKey: legacyHasRequestedAccessKey)
            || defaults.bool(forKey: legacyHasPresentedPrimerKey) {
            return true
        }

        return false
    }

    static var hasConfirmedGrant: Bool {
        UserDefaults.standard.bool(forKey: hasConfirmedGrantKey)
    }

    static func markSetupStarted() {
        UserDefaults.standard.set(true, forKey: hasStartedSetupKey)
    }

    static func markAccessRequested() {
        markSetupStarted()
    }

    static func markGrantConfirmedIfGranted() -> Bool {
        guard CGPreflightScreenCaptureAccess() else { return false }

        UserDefaults.standard.set(true, forKey: hasConfirmedGrantKey)
        return true
    }

    static var needsRelaunchForGrantedAccess: Bool {
        hasStartedSetup && !CGPreflightScreenCaptureAccess()
    }
}
