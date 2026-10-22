import AppKit

/// bundle id → 앱 아이콘. 행마다 NSWorkspace 를 부르지 않도록 캐시한다.
@MainActor
enum AppIconCache {
    /// 앱을 못 찾은 경우(nil)도 캐시한다
    private static var cache: [String: NSImage?] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleID] = icon
        return icon
    }
}
