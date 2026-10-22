/// 폴링 한 번 사이에 앞에 있었던 앱들.
///
/// 복사 시점의 앱을 알 수 없어, 복사가 일어났을 수 있는 구간(직전 폴링 ~ 이번 폴링)에
/// 앞에 있었던 앱 중 하나라도 제외 앱이면 그 복사를 제외 앱의 것으로 본다.
public struct RecentAppsWindow: Equatable, Sendable {
    public private(set) var bundleIDs: Set<String> = []

    public init(frontmost: String?) {
        reset(frontmost: frontmost)
    }

    /// 앱이 앞으로 나왔을 때.
    public mutating func activated(_ bundleID: String?) {
        if let bundleID { bundleIDs.insert(bundleID) }
    }

    /// 변화 없는 폴링이나 처리를 마친 폴링 뒤에 지금 앞의 앱만 남긴다.
    public mutating func reset(frontmost: String?) {
        bundleIDs = []
        activated(frontmost)
    }

    /// 구간 안의 앱(지금 앞의 앱 포함) 중 제외 앱. 여럿이면 정렬 순서로 첫 번째.
    public func excludedApp(frontmost: String?, excluded: Set<String>) -> String? {
        var candidates = bundleIDs
        if let frontmost { candidates.insert(frontmost) }
        return candidates.sorted().first(where: excluded.contains)
    }
}
