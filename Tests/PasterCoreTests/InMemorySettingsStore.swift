import Foundation
@testable import PasterCore

/// 테스트용 메모리 저장소. 실제 환경설정 파일을 건드리지 않는다.
final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? { value(forKey: key) as? Data }
    func stringArray(forKey key: String) -> [String]? { value(forKey: key) as? [String] }
    func string(forKey key: String) -> String? { value(forKey: key) as? String }

    func set(_ value: Any?, forKey key: String) {
        lock.withLock { values[key] = value }
    }

    private func value(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }
}
