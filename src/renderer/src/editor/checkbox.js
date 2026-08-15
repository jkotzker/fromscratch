const CHECKED = '[✓] ';
const UNCHECKED = '[ ] ';

/**
 * Adds, checks or unchecks a checkbox on every line touched by the selection. The markers are
 * kept byte-for-byte identical to the CodeMirror 5 version so existing notes keep working.
 */
export const toggleCheckbox = view => {
  const { state } = view;
  const changes = [];
  const handled = new Set();

  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;

    for (let number = first; number <= last; number += 1) {
      if (handled.has(number)) continue;
      handled.add(number);

      const line = state.doc.line(number);
      const padding = Math.max(line.text.search(/\S/), 0);
      const trimmed = line.text.slice(padding);
      const markerFrom = line.from + padding;

      if (trimmed.trim() === '') {
        changes.push({ from: line.to, insert: UNCHECKED });
      } else if (trimmed.startsWith(CHECKED)) {
        changes.push({ from: markerFrom, to: markerFrom + CHECKED.length, insert: UNCHECKED });
      } else if (trimmed.startsWith(UNCHECKED)) {
        changes.push({ from: markerFrom, to: markerFrom + UNCHECKED.length, insert: CHECKED });
      } else {
        changes.push({ from: markerFrom, insert: UNCHECKED });
      }
    }
  }

  if (!changes.length) return false;

  view.dispatch(state.update({ changes, userEvent: 'input.checkbox' }));
  return true;
};
