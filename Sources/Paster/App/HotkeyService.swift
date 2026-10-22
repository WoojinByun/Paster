import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 패널 열기 / 닫기. 기본 ⌃⌥⌘V.
    static let togglePanel = Self("togglePanel", initial: .init(.v, modifiers: [.control, .option, .command]))
}

@MainActor
enum HotkeyService {
    static func register(_ action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            MainActor.assumeIsolated { action() }
        }
    }
}
