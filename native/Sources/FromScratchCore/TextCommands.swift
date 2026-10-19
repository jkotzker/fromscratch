import Foundation

/// One replacement in UTF-16 coordinates of the text it was computed against.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

/// The outcome of a command: edits in descending range order (so they can be applied one after
/// another without re-mapping) plus the selection to set afterwards. A caller applies the whole
/// result as a single undo group.
public struct EditResult: Equatable, Sendable {
    public var edits: [TextEdit]
    public var selection: [NSRange]

    public init(edits: [TextEdit], selection: [NSRange]) {
        self.edits = edits
        self.selection = selection
    }
}

public enum MoveDirection: Sendable { case up, down }

/// Editing commands as pure functions of (text, selection). They work on UTF-16 offsets because
/// the caller is an NSTextView; a "line" is whatever `NSString.lineRange` considers one
/// (`\n`, `\r\n` or `\r`), so documents with other terminators keep them.
public enum TextCommands {
    // Byte-for-byte the v2 markers, so existing notes keep working.
    public static let checked = "[✓] "
    public static let unchecked = "[ ] "

    // MARK: Line geometry

    private struct Line {
        var start: Int
        var contentsEnd: Int
        var end: Int
    }

    private static func line(at position: Int, in ns: NSString) -> Line {
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(max(position, 0), ns.length), length: 0))
        return Line(start: start, contentsEnd: contentsEnd, end: end)
    }

    private static func lines(from start: Int, to end: Int, in ns: NSString) -> [Line] {
        var result: [Line] = []
        var position = start
        repeat {
            let current = line(at: position, in: ns)
            result.append(current)
            if current.end <= position { break }
            position = current.end
        } while position < end
        return result
    }

    /// First and last line touched by a range. When `excludingTrailingStart` is set, a non-empty
    /// range that ends exactly at the start of a line does not touch that line (the usual rule for
    /// block commands). The checkbox command deliberately does not use it: v2 includes that line.
    private static func touchedLines(_ range: NSRange, in ns: NSString, excludingTrailingStart: Bool) -> (Line, Line) {
        let first = line(at: range.location, in: ns)
        let to = range.location + range.length
        var last = line(at: to, in: ns)
        if excludingTrailingStart, range.length > 0, to == last.start, to > first.start {
            last = line(at: to - 1, in: ns)
        }
        return (first, last)
    }

    /// Merged, ordered runs of whole lines covered by the selection, as (start, end-including-terminator).
    private static func blocks(_ selection: [NSRange], in ns: NSString, mergeGapOfOneLine: Bool) -> [(start: Int, end: Int)] {
        var raw: [(start: Int, end: Int)] = selection.map {
            let (first, last) = touchedLines($0, in: ns, excludingTrailingStart: true)
            return (first.start, last.end)
        }
        raw.sort { $0.start < $1.start }
        var merged: [(start: Int, end: Int)] = []
        for block in raw {
            if var current = merged.last {
                let adjacent = block.start <= current.end
                // Two blocks one line apart would both want to swap with that line.
                let oneApart = mergeGapOfOneLine && current.end < ns.length && block.start == line(at: current.end, in: ns).end
                if adjacent || oneApart {
                    current.end = max(current.end, block.end)
                    merged[merged.count - 1] = current
                    continue
                }
            }
            merged.append(block)
        }
        return merged
    }

    /// Maps a position through edits (all expressed against the original text). A position at the
    /// start of an insertion moves after it, which keeps a caret after text it just typed.
    private static func map(_ position: Int, through edits: [TextEdit]) -> Int {
        var result = position
        for edit in edits {
            let a = edit.range.location, b = a + edit.range.length
            let replacementLength = (edit.replacement as NSString).length
            if edit.range.length == 0 {
                if position >= a { result += replacementLength }
            } else if position >= b {
                result += replacementLength - edit.range.length
            } else if position > a {
                result += min(position - a, replacementLength) - (position - a)
            }
        }
        return result
    }

    private static func descending(_ edits: [TextEdit]) -> [TextEdit] {
        edits.sorted { $0.range.location > $1.range.location }
    }

    private static func mapSelection(_ selection: [NSRange], through edits: [TextEdit]) -> [NSRange] {
        selection.map {
            let from = map($0.location, through: edits)
            let to = map($0.location + $0.length, through: edits)
            return NSRange(location: from, length: max(to - from, 0))
        }
    }

    // MARK: Checkbox

    /// Port of `checkbox.js`: toggles a checkbox on every line touched by any selection range, each
    /// line once. The marker goes after the leading whitespace; a blank line gets an unchecked
    /// marker at its end.
    public static func toggleCheckbox(text: String, selection: [NSRange]) -> EditResult? {
        let ns = text as NSString
        var handled = Set<Int>()
        var edits: [TextEdit] = []

        for range in selection {
            let (first, last) = touchedLines(range, in: ns, excludingTrailingStart: false)
            var current = first
            while true {
                if handled.insert(current.start).inserted {
                    if let edit = checkboxEdit(for: current, in: ns) { edits.append(edit) }
                }
                if current.start >= last.start || current.end >= ns.length && current.end == current.contentsEnd { break }
                current = line(at: current.end, in: ns)
            }
        }

        guard !edits.isEmpty else { return nil }
        let ordered = descending(edits)
        return EditResult(edits: ordered, selection: mapSelection(selection, through: ordered))
    }

    private static func checkboxEdit(for line: Line, in ns: NSString) -> TextEdit? {
        var padding = line.start
        while padding < line.contentsEnd, isWhitespace(ns.character(at: padding)) { padding += 1 }
        if padding == line.contentsEnd {
            return TextEdit(range: NSRange(location: line.contentsEnd, length: 0), replacement: unchecked)
        }
        let rest = ns.substring(with: NSRange(location: padding, length: line.contentsEnd - padding))
        if rest.hasPrefix(checked) {
            return TextEdit(range: NSRange(location: padding, length: (checked as NSString).length), replacement: unchecked)
        }
        if rest.hasPrefix(unchecked) {
            return TextEdit(range: NSRange(location: padding, length: (unchecked as NSString).length), replacement: checked)
        }
        return TextEdit(range: NSRange(location: padding, length: 0), replacement: unchecked)
    }

    // Matches JavaScript's `\s` closely enough for line padding (BMP code units only).
    private static func isWhitespace(_ unit: unichar) -> Bool {
        if unit == 0xFEFF { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    // MARK: Moving and deleting lines

    private struct LinePair {
        var content: String
        var terminator: String
    }

    public static func moveLines(text: String, selection: [NSRange], direction: MoveDirection) -> EditResult? {
        let ns = text as NSString
        var edits: [TextEdit] = []
        var moved: [(blockStart: Int, blockEnd: Int, lines: [Line], newStarts: [Int], newLengths: [Int], regionStart: Int)] = []

        for block in blocks(selection, in: ns, mergeGapOfOneLine: true) {
            let blockLines = lines(from: block.start, to: block.end, in: ns)
            guard let lastBlockLine = blockLines.last else { continue }
            let neighbour: Line
            switch direction {
            case .up:
                guard block.start > 0 else { continue }
                neighbour = line(at: block.start - 1, in: ns)
            case .down:
                // The last line of the block must be terminated for there to be a line after it.
                guard lastBlockLine.end > lastBlockLine.contentsEnd else { continue }
                neighbour = line(at: block.end, in: ns)
            }

            let regionLines = direction == .up ? [neighbour] + blockLines : blockLines + [neighbour]
            let regionStart = regionLines[0].start
            let regionEnd = regionLines[regionLines.count - 1].end
            var pairs = regionLines.map { l in
                LinePair(
                    content: ns.substring(with: NSRange(location: l.start, length: l.contentsEnd - l.start)),
                    terminator: ns.substring(with: NSRange(location: l.contentsEnd, length: l.end - l.contentsEnd)))
            }
            // Order in which the original lines appear afterwards.
            let order: [Int] = direction == .up
                ? Array(1..<regionLines.count) + [0]
                : [regionLines.count - 1] + Array(0..<(regionLines.count - 1))
            var reordered = order.map { pairs[$0] }
            // Only the document's final line can lack a terminator; it must stay last, so it takes
            // over the terminator of the line that now sits last (keeps newline count and style).
            if let missing = reordered.firstIndex(where: { $0.terminator.isEmpty }), missing != reordered.count - 1 {
                reordered[missing].terminator = reordered[reordered.count - 1].terminator
                reordered[reordered.count - 1].terminator = ""
            }
            pairs = reordered

            var replacement = ""
            var newStarts = [Int](repeating: 0, count: regionLines.count)
            var newLengths = [Int](repeating: 0, count: regionLines.count)
            var offset = regionStart
            for (slot, original) in order.enumerated() {
                let piece = pairs[slot].content + pairs[slot].terminator
                newStarts[original] = offset
                newLengths[original] = (piece as NSString).length
                offset += newLengths[original]
                replacement += piece
            }
            edits.append(TextEdit(range: NSRange(location: regionStart, length: regionEnd - regionStart), replacement: replacement))

            // Only the block's own lines matter for mapping the selection.
            let blockIndexes = direction == .up ? Array(1..<regionLines.count) : Array(0..<blockLines.count)
            moved.append((
                block.start, block.end, blockIndexes.map { regionLines[$0] },
                blockIndexes.map { newStarts[$0] }, blockIndexes.map { newLengths[$0] }, regionStart))
        }

        guard !edits.isEmpty else { return nil }

        func mapEndpoint(_ position: Int, isNonEmptyEnd: Bool) -> Int {
            for block in moved {
                if isNonEmptyEnd, position == block.blockEnd, position < ns.length || block.lines.last!.end > block.lines.last!.contentsEnd {
                    return block.newStarts.last! + block.newLengths.last!
                }
                for (index, l) in block.lines.enumerated()
                where (position >= l.start && position < l.end) || (position == l.end && position == ns.length) {
                    return block.newStarts[index] + min(position - l.start, block.newLengths[index])
                }
            }
            return position
        }

        let newSelection = selection.map { range -> NSRange in
            let from = mapEndpoint(range.location, isNonEmptyEnd: false)
            let to = range.length > 0 ? mapEndpoint(range.location + range.length, isNonEmptyEnd: true) : from
            return NSRange(location: from, length: max(to - from, 0))
        }
        return EditResult(edits: descending(edits), selection: newSelection)
    }

    public static func deleteLines(text: String, selection: [NSRange]) -> EditResult {
        let ns = text as NSString
        var edits: [TextEdit] = []
        var carets: [Int] = []
        var removedBefore = 0

        for block in blocks(selection, in: ns, mergeGapOfOneLine: false) {
            var start = block.start
            // Deleting the unterminated final line would leave the previous line's terminator
            // dangling, so take it too.
            if block.end == ns.length, start > 0 {
                let lastLine = line(at: max(block.end - 1, 0), in: ns)
                if block.end == block.start || lastLine.end == lastLine.contentsEnd {
                    start = line(at: start - 1, in: ns).contentsEnd
                }
            }
            edits.append(TextEdit(range: NSRange(location: start, length: block.end - start), replacement: ""))
            carets.append(start - removedBefore)
            removedBefore += block.end - start
        }
        return EditResult(edits: descending(edits), selection: carets.map { NSRange(location: $0, length: 0) })
    }

    // MARK: Indent

    public static func indent(text: String, selection: [NSRange]) -> EditResult {
        let ns = text as NSString
        var edits: [TextEdit] = []
        var handled = Set<Int>()

        for range in selection {
            if range.length == 0 {
                if handled.insert(-range.location - 1).inserted {
                    edits.append(TextEdit(range: NSRange(location: range.location, length: 0), replacement: "\t"))
                }
                continue
            }
            for l in touchedRun(range, in: ns) where handled.insert(l.start).inserted {
                edits.append(TextEdit(range: NSRange(location: l.start, length: 0), replacement: "\t"))
            }
        }
        let ordered = descending(edits)
        return EditResult(edits: ordered, selection: mapSelection(selection, through: ordered))
    }

    /// Removes one leading tab, or else up to four leading spaces, from every touched line.
    public static func outdent(text: String, selection: [NSRange]) -> EditResult? {
        let ns = text as NSString
        var edits: [TextEdit] = []
        var handled = Set<Int>()

        for range in selection {
            for l in touchedRun(range, in: ns) where handled.insert(l.start).inserted {
                var length = 0
                if l.start < l.contentsEnd, ns.character(at: l.start) == 0x09 {
                    length = 1
                } else {
                    while length < 4, l.start + length < l.contentsEnd, ns.character(at: l.start + length) == 0x20 { length += 1 }
                }
                if length > 0 { edits.append(TextEdit(range: NSRange(location: l.start, length: length), replacement: "")) }
            }
        }
        guard !edits.isEmpty else { return nil }
        let ordered = descending(edits)
        return EditResult(edits: ordered, selection: mapSelection(selection, through: ordered))
    }

    private static func touchedRun(_ range: NSRange, in ns: NSString) -> [Line] {
        let (first, last) = touchedLines(range, in: ns, excludingTrailingStart: true)
        return lines(from: first.start, to: last.start + 1, in: ns).filter { $0.start <= last.start }
    }

    // MARK: Newline and go to line

    /// The text to insert for Enter at `at`: a newline plus the line's leading whitespace (only the
    /// part before the caret, so Enter inside the indent does not duplicate what follows).
    public static func newlineIndent(text: String, at: Int) -> String {
        let ns = text as NSString
        let l = line(at: at, in: ns)
        var end = l.start
        while end < min(l.contentsEnd, at), ns.character(at: end) == 0x20 || ns.character(at: end) == 0x09 { end += 1 }
        return "\n" + ns.substring(with: NSRange(location: l.start, length: end - l.start))
    }

    /// `N` or `N:C` (1-based, clamped), as CodeMirror's go-to-line accepts them; anything else is nil.
    public static func parseGoToLine(_ input: String, text: String) -> NSRange? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let lineNumber = Optional(Int(parts[0]) ?? Int.max), lineNumber != 0 else { return nil }
        let column = parts.count == 2 ? (Int(parts[1]) ?? Int.max) : 1

        let ns = text as NSString
        var current = line(at: 0, in: ns)
        var number = 1
        // A terminated line always has a successor, which is empty at the very end (as in CodeMirror).
        while number < lineNumber, current.end > current.contentsEnd {
            current = line(at: current.end, in: ns)
            number += 1
        }
        let offset = min(max(column - 1, 0), current.contentsEnd - current.start)
        return NSRange(location: current.start + offset, length: 0)
    }
}
