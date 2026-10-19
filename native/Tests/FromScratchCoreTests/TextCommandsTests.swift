import Foundation
import Testing
@testable import FromScratchCore

/// Applies a result the way the editor will: edits in the order given, so descending order is
/// part of what these tests verify.
private func apply(_ result: EditResult?, to text: String) -> (text: String, selection: [NSRange])? {
    guard let result else { return nil }
    var ns = text as NSString
    for edit in result.edits { ns = ns.replacingCharacters(in: edit.range, with: edit.replacement) as NSString }
    return (ns as String, result.selection)
}

private func caret(_ n: Int) -> [NSRange] { [NSRange(location: n, length: 0)] }

struct CheckboxCommandTests {
    @Test func addsMarkerAfterPadding() {
        #expect(apply(TextCommands.toggleCheckbox(text: "buy milk", selection: caret(0)), to: "buy milk")?.text == "[ ] buy milk")
        #expect(apply(TextCommands.toggleCheckbox(text: "\t[ ] x", selection: caret(0)), to: "\t[ ] x")?.text == "\t[✓] x")
        #expect(apply(TextCommands.toggleCheckbox(text: "[✓] x", selection: caret(2)), to: "[✓] x")?.text == "[ ] x")
    }

    @Test func blankLineGetsMarkerAtEnd() {
        #expect(apply(TextCommands.toggleCheckbox(text: "  ", selection: caret(0)), to: "  ")?.text == "  [ ] ")
        #expect(apply(TextCommands.toggleCheckbox(text: "a\n\nb", selection: caret(2)), to: "a\n\nb")?.text == "a\n[ ] \nb")
    }

    @Test func eachTouchedLineTogglesOnce() {
        let text = "a\nb\nc\nd"
        let r = apply(TextCommands.toggleCheckbox(text: text, selection: [NSRange(location: 0, length: 5)]), to: text)
        #expect(r?.text == "[ ] a\n[ ] b\n[ ] c\nd")
        let two = apply(TextCommands.toggleCheckbox(text: "ab", selection: [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)]), to: "ab")
        #expect(two?.text == "[ ] ab")
    }

    @Test func utf16OffsetsWithEmoji() {
        let text = "😀 a\nb"  // emoji is 2 UTF-16 units
        let r = apply(TextCommands.toggleCheckbox(text: text, selection: caret(4)), to: text)
        #expect(r?.text == "[ ] 😀 a\nb")
        #expect(r?.selection == caret(8))
    }
}

struct MoveLinesTests {
    @Test func upKeepsCaretOnMovedLine() {
        let r = apply(TextCommands.moveLines(text: "a\nb\nc", selection: caret(2), direction: .up), to: "a\nb\nc")
        #expect(r?.text == "b\na\nc")
        #expect(r?.selection == caret(0))
    }

    @Test func downOnLastLineIsNil() {
        #expect(TextCommands.moveLines(text: "a\nb\nc", selection: caret(4), direction: .down) == nil)
        #expect(TextCommands.moveLines(text: "a\nb", selection: caret(0), direction: .up) == nil)
    }

    @Test func unterminatedLastLineMovesUpWithoutGluing() {
        let r = apply(TextCommands.moveLines(text: "a\nb\nc", selection: caret(5), direction: .up), to: "a\nb\nc")
        #expect(r?.text == "a\nc\nb")
        #expect(r?.selection == caret(3))
    }

    @Test func movingDownIntoUnterminatedLast() {
        let r = apply(TextCommands.moveLines(text: "a\nb\nc", selection: caret(2), direction: .down), to: "a\nb\nc")
        #expect(r?.text == "a\nc\nb")
        #expect(r?.selection == caret(4))
    }

    @Test func multiLineSelectionMovesAsBlock() {
        let text = "a\nb\nc\nd"
        let r = apply(TextCommands.moveLines(text: text, selection: [NSRange(location: 2, length: 3)], direction: .up), to: text)
        #expect(r?.text == "b\nc\na\nd")
        #expect(r?.selection == [NSRange(location: 0, length: 3)])
        let d = apply(TextCommands.moveLines(text: text, selection: [NSRange(location: 2, length: 3)], direction: .down), to: text)
        #expect(d?.text == "a\nd\nb\nc")
        #expect(d?.selection == [NSRange(location: 4, length: 3)])
    }

    @Test func crlfTerminatorsSurvive() {
        let text = "a\r\nb\r\nc"
        let up = apply(TextCommands.moveLines(text: text, selection: caret(6), direction: .up), to: text)
        #expect(up?.text == "a\r\nc\r\nb")
        let mid = apply(TextCommands.moveLines(text: text, selection: caret(3), direction: .up), to: text)
        #expect(mid?.text == "b\r\na\r\nc")
        #expect(mid?.selection == caret(0))
        let down = apply(TextCommands.moveLines(text: text, selection: caret(0), direction: .down), to: text)
        #expect(down?.text == "b\r\na\r\nc")
        #expect(down?.selection == caret(3))
    }

    @Test func emojiBeforeCaretUsesUTF16() {
        let text = "😀\nb"
        let r = apply(TextCommands.moveLines(text: text, selection: caret(4), direction: .up), to: text)
        #expect(r?.text == "b\n😀")
        #expect(r?.selection == caret(1))
    }
}

struct DeleteLinesTests {
    @Test func deletesMiddleLine() {
        let r = apply(TextCommands.deleteLines(text: "a\nb\nc", selection: caret(2)), to: "a\nb\nc")
        #expect(r?.text == "a\nc")
        #expect(r?.selection == caret(2))
    }

    @Test func deletingOnlyLineLeavesEmpty() {
        let r = apply(TextCommands.deleteLines(text: "abc", selection: caret(1)), to: "abc")
        #expect(r?.text == "")
        #expect(r?.selection == caret(0))
    }

    @Test func deletingUnterminatedLastLineDropsPreviousTerminator() {
        let r = apply(TextCommands.deleteLines(text: "a\r\nb", selection: caret(4)), to: "a\r\nb")
        #expect(r?.text == "a")
        #expect(r?.selection == caret(1))
    }

    @Test func selectionAcrossLinesAndTwoCursors() {
        let text = "a\nb\nc\nd"
        let r = apply(TextCommands.deleteLines(text: text, selection: [NSRange(location: 0, length: 3)]), to: text)
        #expect(r?.text == "c\nd")
        let two = apply(TextCommands.deleteLines(text: text, selection: [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)]), to: text)
        #expect(two?.text == "b\nd")
        #expect(two?.selection == [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)])
    }
}

struct IndentTests {
    @Test func emptySelectionInsertsTab() {
        let r = apply(TextCommands.indent(text: "ab", selection: caret(1)), to: "ab")
        #expect(r?.text == "a\tb")
        #expect(r?.selection == caret(2))
    }

    @Test func multiLineSelectionPrefixesEachLine() {
        let text = "a\nb\nc"
        let r = apply(TextCommands.indent(text: text, selection: [NSRange(location: 0, length: 3)]), to: text)
        #expect(r?.text == "\ta\n\tb\nc")
    }

    @Test func outdentRemovesTabOrUpToFourSpaces() {
        let text = "\ta\n      b\n  c\nd"
        let r = apply(TextCommands.outdent(text: text, selection: [NSRange(location: 0, length: text.utf16.count)]), to: text)
        #expect(r?.text == "a\n  b\nc\nd")
    }

    @Test func outdentWithNothingToRemoveIsNil() {
        #expect(TextCommands.outdent(text: "a\nb", selection: [NSRange(location: 0, length: 3)]) == nil)
    }
}

struct NewlineAndGoToLineTests {
    @Test func newlineCopiesIndent() {
        #expect(TextCommands.newlineIndent(text: "\t  x", at: 4) == "\n\t  ")
        #expect(TextCommands.newlineIndent(text: "a\n  b", at: 5) == "\n  ")
        #expect(TextCommands.newlineIndent(text: "x", at: 1) == "\n")
    }

    @Test func goToLine() {
        let text = "ab\ncde\nf"
        #expect(TextCommands.parseGoToLine("3", text: text) == NSRange(location: 7, length: 0))
        #expect(TextCommands.parseGoToLine("2:2", text: text) == NSRange(location: 4, length: 0))
        #expect(TextCommands.parseGoToLine(" 2:2 ", text: text) == NSRange(location: 4, length: 0))
        #expect(TextCommands.parseGoToLine("99", text: text) == NSRange(location: 7, length: 0))
        #expect(TextCommands.parseGoToLine("2:999", text: text) == NSRange(location: 6, length: 0))
        #expect(TextCommands.parseGoToLine("1", text: "") == NSRange(location: 0, length: 0))
        #expect(TextCommands.parseGoToLine("99", text: "a\n") == NSRange(location: 2, length: 0))
        for bad in ["x", "", "0", "1:", ":2", "1:2:3", "-1", "1.5"] {
            #expect(TextCommands.parseGoToLine(bad, text: text) == nil, "\(bad)")
        }
    }
}
