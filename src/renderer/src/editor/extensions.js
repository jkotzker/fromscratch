import {
  defaultKeymap,
  deleteLine,
  history,
  historyKeymap,
  indentLess,
  insertTab,
  moveLineDown,
  moveLineUp,
} from '@codemirror/commands';
import {
  codeFolding,
  foldable,
  foldCode,
  foldEffect,
  foldGutter,
  indentService,
  indentUnit,
  unfoldCode,
} from '@codemirror/language';
import {
  gotoLine,
  highlightSelectionMatches,
  openSearchPanel,
  replaceAll,
  search,
  searchKeymap,
} from '@codemirror/search';
import { EditorState, Prec } from '@codemirror/state';
import { drawSelection, EditorView, highlightActiveLine, keymap, scrollPastEnd } from '@codemirror/view';
import { toggleCheckbox } from './checkbox';
import { collectFolds, hasFoldEffect } from './folds';
import { indentFold } from './indentFold';

/**
 * Folds or unfolds around the cursor. Like the CM5 `scanUp` option, when the cursor line itself
 * is not foldable this walks up to the closest enclosing block.
 */
const toggleFold = view => {
  if (unfoldCode(view)) return true;
  if (foldCode(view)) return true;

  const { state } = view;
  const cursorLine = state.doc.lineAt(state.selection.main.head);

  for (let number = cursorLine.number - 1; number >= 1; number -= 1) {
    const line = state.doc.line(number);
    const range = foldable(state, line.from, line.to);

    if (range && range.to >= cursorLine.from) {
      view.dispatch({ effects: foldEffect.of(range), selection: { anchor: line.to } });
      return true;
    }
  }

  return false;
};

export const createExtensions = ({ onChange, onFoldsChange, onSave }) => [
  history(),
  drawSelection(),
  highlightActiveLine(),
  highlightSelectionMatches(),
  search({ top: true }),
  codeFolding({ placeholderText: ' … ' }),
  foldGutter({
    // Own marker so the CSS can keep it invisible until the gutter is hovered or the line folded.
    markerDOM: open => {
      const marker = document.createElement('span');
      marker.className = `fold-marker ${open ? 'open' : 'closed'}`;
      marker.textContent = open ? '⌄' : '›';
      return marker;
    },
  }),
  indentFold,
  scrollPastEnd(),
  EditorView.lineWrapping,
  EditorView.scrollMargins.of(() => ({ top: 40, bottom: 40 })),
  EditorState.tabSize.of(4),
  indentUnit.of('\t'),
  // No language is loaded, so a new line simply inherits the indentation of the line above.
  indentService.of(() => null),

  Prec.highest(
    keymap.of([
      { key: 'Mod-ArrowUp', run: moveLineUp },
      { key: 'Mod-ArrowDown', run: moveLineDown },
      { key: 'Mod-d', run: deleteLine },
      { key: 'Mod-k', run: toggleFold },
      { key: 'Mod-[', run: toggleFold },
      { key: 'Mod-]', run: toggleFold },
      { key: 'Mod-f', run: openSearchPanel },
      { key: 'Shift-Mod-f', run: openSearchPanel },
      { key: 'Shift-Mod-r', run: replaceAll },
      { key: 'Mod-g', run: gotoLine },
      { key: 'Mod-l', run: toggleCheckbox },
      { key: 'Mod-/', run: toggleCheckbox },
      { key: 'Tab', run: insertTab, shift: indentLess },
      {
        key: 'Mod-s',
        run: () => {
          onSave();
          return true;
        },
      },
    ])
  ),
  keymap.of([...defaultKeymap, ...searchKeymap, ...historyKeymap]),

  EditorView.updateListener.of(update => {
    if (update.docChanged) onChange(update.state.doc.toString());
    if (update.docChanged || hasFoldEffect(update.transactions)) {
      onFoldsChange(collectFolds(update.state));
    }
  }),
];
