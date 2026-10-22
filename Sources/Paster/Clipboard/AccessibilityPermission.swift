import AppKit
import ApplicationServices

/// 손쉬운 사용 권한 (CGEvent 로 ⌘V 를 보내려면 필요).
@MainActor
enum AccessibilityPermission {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private static let requestedKey = "didRequestAccessibility"

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 첫 실행 때 한 번만 시스템 권한 요청 창을 띄운다.
    static func requestOnFirstLaunch(defaults: UserDefaults = .standard) {
        guard !isTrusted, !defaults.bool(forKey: requestedKey) else { return }
        defaults.set(true, forKey: requestedKey)
        // kAXTrustedCheckOptionPrompt 의 값. 전역 var 라 Swift 6 에서 직접 참조하지 않는다.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
