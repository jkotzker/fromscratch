import { foldService } from '@codemirror/language';

const indentColumn = (text, tabSize) => {
  let column = 0;
  for (const char of text) {
    if (char === '\t') column += tabSize - (column % tabSize);
    else if (char === ' ') column += 1;
    else break;
  }
  return column;
};

const isBlank = text => text.trim() === '';

/**
 * Indentation based folding, the CodeMirror 5 `indent-fold` addon rewritten as a CM6 fold
 * service: a line can be folded when the lines below it are indented deeper. Blank lines are
 * swallowed by the block unless they trail it.
 */
export const indentFold = foldService.of((state, lineStart, lineEnd) => {
  const startLine = state.doc.lineAt(lineStart);
  if (isBlank(startLine.text)) return null;

  const startIndent = indentColumn(startLine.text, state.tabSize);
  let end = null;

  for (let number = startLine.number + 1; number <= state.doc.lines; number += 1) {
    const line = state.doc.line(number);
    if (isBlank(line.text)) continue;
    if (indentColumn(line.text, state.tabSize) <= startIndent) break;
    end = line.to;
  }

  return end === null ? null : { from: lineEnd, to: end };
});
