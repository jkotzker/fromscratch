import { useEffect, useMemo, useRef, useState } from 'react';
import { BUNDLED_FAMILY } from '../fonts';

const MIN_SIZE = 8;
const MAX_SIZE = 72;

/**
 * Picks the editor font.
 *
 * macOS has a native font panel, but Electron exposes no binding for it and reaching NSFontPanel
 * would mean a native addon in a project that has none. This follows the shortcuts overlay
 * instead: same panel treatment, themed by whatever colour scheme is active.
 *
 * Monospace-only by default -- 54 of the 304 families on a typical machine -- because the rest are
 * not useful in an editor and a flat list of 304 is not browsable.
 */
export default function FontPicker({ visible, families, family, size, onChangeFamily, onChangeSize, onClose }) {
  const [query, setQuery] = useState('');
  const [showAll, setShowAll] = useState(false);
  const search = useRef(null);
  const selected = useRef(null);

  // The parent remounts this on each open (via key), so the query starts empty without resetting
  // state from an effect; this only has to move focus.
  useEffect(() => {
    if (!visible) return undefined;
    const id = requestAnimationFrame(() => search.current?.focus());
    return () => cancelAnimationFrame(id);
  }, [visible]);

  // Bring the current font into view when the list appears.
  useEffect(() => {
    if (visible) selected.current?.scrollIntoView({ block: 'center' });
  }, [visible, showAll]);

  const shown = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return families.filter(entry => {
      if (!showAll && !entry.monospace) return false;
      return !needle || entry.family.toLowerCase().includes(needle);
    });
  }, [families, query, showAll]);

  const current = family || BUNDLED_FAMILY;
  const monospaceCount = families.filter(entry => entry.monospace).length;

  const handleKeyDown = event => {
    if (event.key === 'Escape') {
      event.stopPropagation();
      onClose();
    }
  };

  return (
    <div className={`fontpicker ${visible ? 'visible' : ''}`} onKeyDown={handleKeyDown}>
      <h3>Font</h3>

      <button type="button" title="Close font picker" onClick={onClose}>
        <span>×</span>
      </button>

      <div className="fontpicker-controls">
        <input
          ref={search}
          type="text"
          value={query}
          placeholder={showAll ? `Search ${families.length} fonts` : `Search ${monospaceCount} monospace fonts`}
          onChange={event => setQuery(event.target.value)}
        />

        <label>
          Size
          <input
            type="number"
            min={MIN_SIZE}
            max={MAX_SIZE}
            value={size}
            onChange={event => {
              const next = Number(event.target.value);
              if (Number.isFinite(next)) onChangeSize(Math.min(Math.max(next, MIN_SIZE), MAX_SIZE));
            }}
          />
          px
        </label>

        <label>
          <input type="checkbox" checked={showAll} onChange={event => setShowAll(event.target.checked)} />
          Show all fonts
        </label>
      </div>

      <ul className="fontpicker-list">
        {shown.map(entry => (
          <li key={entry.family}>
            <button
              type="button"
              ref={entry.family === current ? selected : null}
              className={entry.family === current ? 'current' : ''}
              onClick={() => onChangeFamily(entry.bundled ? null : entry.family)}
            >
              {/*
                The name is the preview: rendered in its own face, at the chosen size. The panel's
                own chrome is pinned to a fixed size in CSS, so changing the size here moves these
                rows and nothing else.
              */}
              <span
                className="fontpicker-name"
                style={{ fontFamily: `"${entry.family}", monospace`, fontSize: `${size}px` }}
              >
                {entry.family}
              </span>
            </button>
          </li>
        ))}

        {!shown.length && <li className="fontpicker-empty">No fonts match “{query}”.</li>}
      </ul>
    </div>
  );
}
