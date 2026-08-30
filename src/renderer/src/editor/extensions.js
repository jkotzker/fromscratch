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
import { Decoration, drawSelection, EditorView, keymap, scrollPastEnd, ViewPlugin } from '@codemirror/view';
import { toggleCheckbox } from './checkbox';
import { collectFolds, hasFoldEffect } from './folds';
import { indentFold } from './indentFold';

const activeLineDeco = Decoration.line({ class: 'cm-activeLine' });

/**
 * Marks the cursor's line, but only while nothing is selected.
 *
 * CodeMirror's own `highlightActiveLine` marks the line whenever a cursor is on it, selection or
 * not. That collides with how selection is drawn: the selection layer carries no z-index and
 * `.cm-content` comes later in the DOM, so line backgrounds paint *over* the selection. With an
 * active-line highlight solid enough to see, a selection on that line disappears underneath it --
 * only the first few characters showed, in the sliver where this app's gradient is still
 * transparent. (CodeMirror's default active line dodges this by being 27% alpha.)
 *
 * Skipping the highlight while a selection exists resolves it without weakening either one, and
 * matches what the highlight is for: showing where the cursor is when you are not selecting.
 */
const highlightCursorLine = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = this.build(view.state);
    }

    update(update) {
      if (update.docChanged || update.selectionSet) this.decorations = this.build(update.state);
    }

    build(state) {
      if (!state.selection.ranges.every(range => range.empty)) return Decoration.none;

      const seen = new Set();
      const deco = [];
      for (const range of state.selection.ranges) {
        const line = state.doc.lineAt(range.head);
        if (seen.has(line.from)) continue;
        seen.add(line.from);
        deco.push(activeLineDeco.range(line.from));
      }
      return Decoration.set(deco);
    }
  },
  { decorations: plugin => plugin.decorations }
);

const selectedTextDeco = Decoration.mark({ class: 'cm-selectedText' });

/**
 * Recolours selected text, so a scheme's Selected Text Color has an effect.
 *
 * `drawSelection` paints the selection into a layer behind the text and leaves the glyphs alone,
 * so there is otherwise nowhere for that colour to land. Several schemes rely on it: GitHub Dark
 * selects with a dark blue and brightens the text from #8b949e to #ffffff to stay readable.
 */
const highlightSelectedText = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = this.build(view.state);
    }

    update(update) {
      if (update.docChanged || update.selectionSet) this.decorations = this.build(update.state);
    }

    build(state) {
      const deco = state.selection.ranges
        .filter(range => !range.empty)
        .map(range => selectedTextDeco.range(range.from, range.to));
      return deco.length ? Decoration.set(deco, true) : Decoration.none;
    }
  },
  { decorations: plugin => plugin.decorations }
);

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

export const createExtensions = ({ onChange, onFoldsChange, onSave, onToggleTheme }) => [
  history(),
  drawSelection(),
  highlightCursorLine,
  highlightSelectedText,
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
      {
        // CodeMirror's defaultKeymap binds Mod-i to selectParentSyntax with preventDefault, which
        // swallowed the key before the menu accelerator ever saw it -- so the advertised
        // light/dark shortcut did nothing. There is no language mode loaded here, so that command
        // has nothing to select anyway.
        key: 'Mod-i',
        run: () => {
          onToggleTheme();
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
