import Testing
import Foundation
@testable import RoomCore

@Suite("Settings survive upgrades") struct SettingsCompatTests {
    func load(_ json: String) throws -> AppSettings {
        let sb = try Sandbox()
        try FileManager.default.createDirectory(at: sb.appRoot, withIntermediateDirectories: true)
        try json.write(to: sb.paths.settings, atomically: true, encoding: .utf8)
        return SettingsStore(paths: sb.paths).load()
    }

    @Test func anOldFileMissingNewKeysKeepsWhatItHasAndDefaultsTheRest() throws {
        let s = try load(#"{"learningOptIn": true, "staleProjectDays": 90, "advisorMode": "claude"}"#)
        #expect(s.learningOptIn == true); #expect(s.staleProjectDays == 90); #expect(s.advisorMode == .claude)
        #expect(s.hapticLevel == .standard); #expect(s.tiltEnabled); #expect(s.appearance == .system); #expect(s.lowSpaceAlertGB == 15)
    }

    @Test func theCalibrationSurvivesWhenALaterVersionAddsSettings() throws {
        let s = try load(#"{"tilt": {"axis": 1, "sign": -1, "isCalibrated": true}, "appearance": "dark"}"#)
        #expect(s.tilt == TiltCalibration(axis: 1, sign: -1, isCalibrated: true), "this used to be silently reset to uncalibrated")
        #expect(s.appearance == .dark)
    }

    @Test func theOldOnOffHapticSwitchMigrates() throws {
        #expect(try load(#"{"haptics": false}"#).hapticLevel == .off)
        #expect(try load(#"{"haptics": true}"#).hapticLevel == .standard)
        #expect(try load(#"{"haptics": false, "hapticLevel": "full"}"#).hapticLevel == .full, "the new setting wins")
    }

    @Test func garbageOrEmptyFilesFallBackToDefaultsWithoutCrashing() throws {
        #expect(try load("not json") == AppSettings()); #expect(try load("{}") == AppSettings()); #expect(try load("") == AppSettings())
    }

    @Test func everythingRoundTrips() throws {
        let sb = try Sandbox(); let store = SettingsStore(paths: sb.paths)
        var s = AppSettings(); s.hapticLevel = .full; s.appearance = .light; s.learningOptIn = true; s.learningConsentDate = Date(timeIntervalSince1970: 1_700_000_000)
        s.tilt = TiltCalibration(axis: 0, sign: -1, isCalibrated: true); s.staleProjectDays = 30; s.advisorMode = .off
        store.save(s)
        #expect(store.load() == s)
    }

    @Test func hapticLevelsGateWhatPlays() {
        #expect(!HapticLevel.off.permits(.standard)); #expect(!HapticLevel.off.permits(.full))
        #expect(HapticLevel.standard.permits(.standard)); #expect(!HapticLevel.standard.permits(.full))
        #expect(HapticLevel.full.permits(.standard)); #expect(HapticLevel.full.permits(.full))
    }
}
