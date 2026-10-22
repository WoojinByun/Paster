import Testing
@testable import PasterCore

struct PanelKeyMapperTests {
    typealias Code = PanelKeyMapper.KeyCode

    func key(_ code: UInt16, _ modifiers: KeyModifiers = [], _ characters: String? = nil) -> PanelKey? {
        PanelKeyMapper.key(keyCode: code, modifiers: modifiers, characters: characters)
    }

    @Test func returnVariants() {
        #expect(key(Code.returnKey) == .enter)
        #expect(key(Code.keypadEnter) == .enter)
        #expect(key(Code.returnKey, .shift) == .shiftEnter)
        #expect(key(Code.returnKey, .command) == .cmdEnter)
        #expect(key(Code.returnKey, .control) == nil)
    }

    @Test func arrows() {
        #expect(key(Code.upArrow) == .up)
        #expect(key(Code.downArrow) == .down)
        #expect(key(Code.leftArrow) == .left)
        #expect(key(Code.rightArrow) == .right)
        #expect(key(Code.upArrow, [.command, .option]) == .optCmdUp)
        #expect(key(Code.downArrow, [.command, .option]) == .optCmdDown)
        #expect(key(Code.leftArrow, .shift) == nil)
    }

    @Test func commandShortcuts() {
        #expect(key(35, .command, "p") == .cmdP)
        #expect(key(Code.delete, .command) == .cmdDelete)
        #expect(key(8, .command, "c") == nil)
    }

    @Test(arguments: [(18, 1), (19, 2), (20, 3), (21, 4), (23, 5), (22, 6), (26, 7), (28, 8), (25, 9)] as [(UInt16, Int)])
    func commandNumberByKeyCode(code: UInt16, number: Int) {
        #expect(key(code, .command, String(number)) == .cmdNumber(number))
        // 한글 등 다른 입력 소스에서도 물리 키 코드로 판별한다
        #expect(key(code, .command, "ㅁ") == .cmdNumber(number))
    }

    @Test func commandPMatchesKeyCodeUnderNonLatinInput() {
        #expect(key(35, .command, "ㅔ") == .cmdP)
        #expect(key(35, .command, nil) == .cmdP)
        #expect(key(35, .command, "P") == .cmdP)
    }

    @Test func modifiersMustMatchExactly() {
        #expect(key(Code.returnKey, [.shift, .command]) == nil)
        #expect(key(Code.returnKey, .option) == nil)
        #expect(key(18, [.shift, .command], "!") == nil)
        #expect(key(35, [.shift, .command], "p") == nil)
    }

    @Test func escape() {
        #expect(key(Code.escape) == .escape)
    }

    @Test func typingIsTextInput() {
        #expect(key(0, [], "a") == .textInput)
        #expect(key(0, .shift, "A") == .textInput)
        #expect(key(49, [], " ") == .textInput)
        #expect(key(Code.delete, [], "\u{7F}") == .textInput)
        #expect(key(18, [], "1") == .textInput)
    }

    @Test func controlAndFunctionKeysAreIgnored() {
        #expect(key(Code.tab, [], "\t") == nil)
        #expect(key(0, .control, "a") == nil)
        #expect(key(122, [], "\u{F704}") == nil) // F1
    }
}
