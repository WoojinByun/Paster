import AppKit
import PasterCore

extension KeyModifiers {
    /// ⌘⌥⌃⇧ 네 개만 옮긴다. 화살표 키의 .numericPad / .function 이 섞이면 정확 일치 비교가 깨진다.
    init(_ flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.control) { insert(.control) }
    }
}
