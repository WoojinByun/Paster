import Foundation
import PasterCore

/// 앱 전체가 공유하는 저장소 · 설정.
@MainActor
final class AppEnvironment {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paster", isDirectory: true)
    }

    let settings: PasterSettings
    let store: ClipStore
    let retention: RetentionService
    /// 앱이 도는 동안 쥐고 있는 단일 인스턴스 잠금
    private let instanceLock: InstanceLock

    /// 다른 Paster 가 실행 중이면 `InstanceLock.Failure.alreadyRunning`, 잠금 파일을 쓸 수 없으면
    /// `InstanceLock.Failure.unavailable` 을 던진다. 그 밖의 오류는 저장소를 열다 난 것이다.
    init() throws {
        // 두 인스턴스가 같은 저장소를 쓰지 않도록 저장소를 열기 전에 잠근다
        instanceLock = try InstanceLock(directory: Self.supportDirectory)
        settings = PasterSettings()
        store = try ClipStore.open(directory: Self.supportDirectory)
        // 시간대가 바뀌어도 따라가도록 autoupdatingCurrent 를 쓴다
        retention = RetentionService(store: store, calendar: .autoupdatingCurrent)
    }
}
