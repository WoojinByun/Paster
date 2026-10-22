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

    init() throws {
        settings = PasterSettings()
        store = try ClipStore.open(directory: Self.supportDirectory)
        // 시간대가 바뀌어도 따라가도록 autoupdatingCurrent 를 쓴다
        retention = RetentionService(store: store, calendar: .autoupdatingCurrent)
    }
}
