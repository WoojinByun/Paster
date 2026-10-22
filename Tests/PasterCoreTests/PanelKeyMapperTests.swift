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
        #expect(key(18, .command, "1") == .cmdNumber(1))
        #expect(key(25, .command, "9") == .cmdNumber(9))
        #expect(key(35, .command, "p") == .cmdP)
        #expect(key(Code.delete, .command) == .cmdDelete)
        #expect(key(8, .command, "c") == nil)
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
