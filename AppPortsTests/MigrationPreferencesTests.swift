import Foundation
import Testing
@testable import AppPorts

@Suite("Migration preferences", .serialized)
struct MigrationPreferencesTests {
    @Test("Classic mode is active only when the user opted in")
    func classicModeGate() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: MigrationPreferences.classicDataMigrationKey)
        defer {
            if let previous { defaults.set(previous, forKey: MigrationPreferences.classicDataMigrationKey) }
            else { defaults.removeObject(forKey: MigrationPreferences.classicDataMigrationKey) }
        }

        defaults.set(false, forKey: MigrationPreferences.classicDataMigrationKey)
        #expect(MigrationPreferences.isClassicDataMigrationActive == false)

        defaults.set(true, forKey: MigrationPreferences.classicDataMigrationKey)
        #expect(MigrationPreferences.isClassicDataMigrationActive)
        #expect(MigrationPreferences.isMacOS27OrLater == (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27))
    }

    @Test("Dismissed repair reminders round-trip through UserDefaults")
    func dismissedApps() {
        let defaults = UserDefaults.standard
        let previous = defaults.stringArray(forKey: MigrationPreferences.dismissedSignatureRepairKey)
        defer {
            if let previous { defaults.set(previous, forKey: MigrationPreferences.dismissedSignatureRepairKey) }
            else { defaults.removeObject(forKey: MigrationPreferences.dismissedSignatureRepairKey) }
        }

        MigrationPreferences.dismissedSignatureRepairApps = ["/Applications/B.app", "/Applications/A.app"]
        #expect(MigrationPreferences.dismissedSignatureRepairApps == ["/Applications/A.app", "/Applications/B.app"])
        #expect(defaults.stringArray(forKey: MigrationPreferences.dismissedSignatureRepairKey) == ["/Applications/A.app", "/Applications/B.app"])
    }
}
