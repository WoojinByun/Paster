/// 수정 키. 앱은 NSEvent.ModifierFlags 에서 이 네 개만 옮겨 담는다.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// keyDown (가상 키 코드 + 수정 키 + 글자) → PanelKey. nil 이면 패널이 관여하지 않는 키다.
public enum PanelKeyMapper {
    /// Carbon kVK_* 값
    public enum KeyCode {
        public static let returnKey: UInt16 = 36
        public static let keypadEnter: UInt16 = 76
        public static let tab: UInt16 = 48
        public static let delete: UInt16 = 51
        public static let escape: UInt16 = 53
        public static let leftArrow: UInt16 = 123
        public static let rightArrow: UInt16 = 124
        public static let downArrow: UInt16 = 125
        public static let upArrow: UInt16 = 126
        /// 숫자 줄 1~9 (자판 배열과 무관한 물리 키)
        public static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    /// - Parameter characters: `charactersIgnoringModifiers` (⌘P 판별용)
    public static func key(keyCode: UInt16, modifiers: KeyModifiers, characters: String?) -> PanelKey? {
        switch keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter:
            switch modifiers {
            case []: return .enter
            case .shift: return .shiftEnter
            case .command: return .cmdEnter
            default: return nil
            }
        case KeyCode.escape:
            return modifiers.isEmpty ? .escape : nil
        case KeyCode.upArrow:
            if modifiers == [.command, .option] { return .optCmdUp }
            return modifiers.isEmpty ? .up : nil
        case KeyCode.downArrow:
            if modifiers == [.command, .option] { return .optCmdDown }
            return modifiers.isEmpty ? .down : nil
        case KeyCode.leftArrow:
            return modifiers.isEmpty ? .left : nil
        case KeyCode.rightArrow:
            return modifiers.isEmpty ? .right : nil
        case KeyCode.delete:
            if modifiers == .command { return .cmdDelete }
            return modifiers.isDisjoint(with: [.command, .control]) ? .textInput : nil
        case KeyCode.tab:
            return nil
        default:
            break
        }

        if modifiers == .command {
            if let digit = KeyCode.digits.firstIndex(of: keyCode) { return .cmdNumber(digit + 1) }
            if characters?.lowercased() == "p" { return .cmdP }
            return nil
        }
        // ⌘/⌃ 없이 글자를 만드는 키는 검색창 입력이다
        if modifiers.isDisjoint(with: [.command, .control]),
           let characters, let scalar = characters.unicodeScalars.first,
           !isControl(scalar) {
            return .textInput
        }
        return nil
    }

    /// C0/C1 제어 문자와 기능 키 영역(U+F700~U+F8FF)
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) || (0xF700...0xF8FF).contains(scalar.value)
    }
}
