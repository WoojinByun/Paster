import Foundation

/// UserDefaults 에 저장하는 설정.
/// UserDefaults 는 문서상 스레드 안전하지만 Sendable 로 표시돼 있지 않아 @unchecked 로 둔다.
public struct PasterSettings: @unchecked Sendable {
    public enum Key {
        public static let retention = "retention"
        public static let excludedBundleIDs = "excludedBundleIDs"
        public static let lastPurgeDay = "lastPurgeDay"
    }

    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var retention: RetentionSettings {
        get {
            guard let data = defaults.data(forKey: Key.retention),
                  let settings = try? JSONDecoder().decode(RetentionSettings.self, from: data)
            else { return .default }
            return settings
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.retention)
        }
    }

    /// 캡처하지 않을 앱의 bundle id. 정렬해서 저장한다.
    public var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.excludedBundleIDs) ?? [] }
        nonmutating set { defaults.set(Array(Set(newValue)).sorted(), forKey: Key.excludedBundleIDs) }
    }

    /// 마지막으로 정리한 로컬 날짜 (`yyyy-MM-dd`).
    public var lastPurgeDay: String? {
        get { defaults.string(forKey: Key.lastPurgeDay) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastPurgeDay) }
    }

    /// 현재 설정으로 만든 캡처 규칙.
    public func makeCapture() -> ClipCapture {
        ClipCapture(excludedBundleIDs: Set(excludedBundleIDs), enabledKinds: retention.enabledKinds)
    }
}
