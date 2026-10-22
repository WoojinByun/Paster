import Foundation

/// 설정이 쓰는 키-값 저장소. 앱은 UserDefaults, 테스트는 메모리 저장소를 쓴다.
public protocol SettingsStore: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func stringArray(forKey key: String) -> [String]?
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}

/// 저장소(기본값은 UserDefaults)에 저장하는 설정.
public struct PasterSettings: Sendable {
    public enum Key {
        public static let retention = "retention"
        public static let excludedBundleIDs = "excludedBundleIDs"
        public static let lastPurgeDay = "lastPurgeDay"
    }

    private let store: any SettingsStore

    public init(store: any SettingsStore = UserDefaults.standard) {
        self.store = store
    }

    public var retention: RetentionSettings {
        get {
            guard let data = store.data(forKey: Key.retention),
                  let settings = try? JSONDecoder().decode(RetentionSettings.self, from: data)
            else { return .default }
            return settings
        }
        nonmutating set {
            store.set(try? JSONEncoder().encode(newValue), forKey: Key.retention)
        }
    }

    /// 캡처하지 않을 앱의 bundle id. 정렬해서 저장한다.
    public var excludedBundleIDs: [String] {
        get { store.stringArray(forKey: Key.excludedBundleIDs) ?? [] }
        nonmutating set { store.set(Array(Set(newValue)).sorted(), forKey: Key.excludedBundleIDs) }
    }

    /// 마지막으로 정리한 로컬 날짜 (`yyyy-MM-dd`).
    public var lastPurgeDay: String? {
        get { store.string(forKey: Key.lastPurgeDay) }
        nonmutating set { store.set(newValue, forKey: Key.lastPurgeDay) }
    }

    /// 현재 설정으로 만든 캡처 규칙.
    public func makeCapture() -> ClipCapture {
        ClipCapture(excludedBundleIDs: Set(excludedBundleIDs), enabledKinds: retention.enabledKinds)
    }
}
