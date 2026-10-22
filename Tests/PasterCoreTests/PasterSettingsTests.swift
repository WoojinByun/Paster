import Foundation
import Testing
@testable import PasterCore

final class PasterSettingsTests {
    let suite: String
    let defaults: UserDefaults
    let settings: PasterSettings

    init() {
        suite = "PasterSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        settings = PasterSettings(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func defaultsWhenEmpty() {
        #expect(settings.retention == .default)
        #expect(settings.excludedBundleIDs.isEmpty)
        #expect(settings.lastPurgeDay == nil)
    }

    @Test func retentionPersists() {
        var retention = RetentionSettings.default
        retention.image = KindRetention(isEnabled: false, period: .day)
        settings.retention = retention
        #expect(settings.retention == retention)
    }

    @Test func retentionFallsBackToDefaultOnGarbageData() {
        defaults.set(Data("not json".utf8), forKey: PasterSettings.Key.retention)
        #expect(settings.retention == .default)
    }

    @Test func retentionFallsBackToDefaultOnMissingKey() {
        // 타입이 하나 빠진 JSON (예: 이후 버전에서 kind 가 추가/제거된 경우)
        let json = #"{"text":{"isEnabled":false,"period":"24h"},"image":{"isEnabled":false,"period":"24h"}}"#
        defaults.set(Data(json.utf8), forKey: PasterSettings.Key.retention)
        #expect(settings.retention == .default)
    }

    @Test func retentionFallsBackToDefaultOnUnknownPeriod() {
        let entry = #"{"isEnabled":false,"period":"1y"}"#
        let json = #"{"text":\#(entry),"image":\#(entry),"files":\#(entry)}"#
        defaults.set(Data(json.utf8), forKey: PasterSettings.Key.retention)
        #expect(settings.retention == .default)
    }

    @Test func excludedBundleIDsAreDedupedAndSorted() {
        settings.excludedBundleIDs = ["com.b", "com.a", "com.b"]
        #expect(settings.excludedBundleIDs == ["com.a", "com.b"])
    }

    @Test func makeCaptureReflectsSettings() {
        var retention = RetentionSettings.default
        retention.files.isEnabled = false
        settings.retention = retention
        settings.excludedBundleIDs = ["com.agilebits.onepassword7"]
        let capture = settings.makeCapture()
        #expect(capture.enabledKinds == [.text, .image])
        #expect(capture.excludedBundleIDs == ["com.agilebits.onepassword7"])
    }

    @Test func lastPurgeDayPersists() {
        settings.lastPurgeDay = "2027-01-15"
        #expect(settings.lastPurgeDay == "2027-01-15")
    }
}
