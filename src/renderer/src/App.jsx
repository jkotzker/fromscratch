import { useCallback, useEffect, useRef, useState } from 'react';
import Editor from './components/Editor';
import Shortcuts from './components/Shortcuts';

const { api } = window;

const RELEASES_URL = 'https://github.com/jkotzker/fromscratch/releases';

const DEFAULT_CONTENT =
  '|> Welcome to FromScratch.\n';

// Font size is an absolute pixel value now, not the old 0.5-2.5 rem multiplier. Settings
// migration converts the old value using a 16px rem base.
const DEFAULT_FONT_SIZE = 16;
const clampFontSize = size => Math.min(Math.max(Math.round(size), 8), 72);

export default function App() {
  const [initial, setInitial] = useState(null);
  const [fontSize, setFontSize] = useState(DEFAULT_FONT_SIZE);
  const [scheme, setScheme] = useState(null);
  const [saveHintVisible, setSaveHintVisible] = useState(false);
  const [updateVersion, setUpdateVersion] = useState(null);
  const [shortcutsVisible, setShortcutsVisible] = useState(false);

  const editor = useRef(null);
  const saveHintTimer = useRef(null);
  const schemes = useRef([]);

  useEffect(() => {
    let cancelled = false;

    api.init().then(({ platform, content, settings, scheme: active, schemes: available }) => {
      if (cancelled) return;

      document.body.dataset.platform = platform;
      schemes.current = available || [];
      setFontSize(clampFontSize(settings.font?.size || DEFAULT_FONT_SIZE));
      setScheme(active);
      setInitial({
        content: content === null ? DEFAULT_CONTENT : content,
        folds: settings.folds || [],
      });
    });

    return () => {
      cancelled = true;
    };
  }, []);

  // Persist whatever changed, but only once the stored values have been loaded.
  useEffect(() => {
    if (initial) api.setSetting('font', { family: null, size: fontSize });
  }, [initial, fontSize]);

  // The whole stylesheet reads its colours from custom properties, so applying a scheme is just
  // setting them on the root element -- no CSS rules change.
  useEffect(() => {
    if (!scheme?.palette) return;
    const root = document.documentElement;
    for (const [name, value] of Object.entries(scheme.palette)) root.style.setProperty(name, value);
  }, [scheme]);

  const showSaveHint = useCallback(() => {
    clearTimeout(saveHintTimer.current);
    setSaveHintVisible(true);
    saveHintTimer.current = setTimeout(() => setSaveHintVisible(false), 1000);
  }, []);

  useEffect(() => {
    // Every handler uses functional updates, so this only ever needs to be wired up once.
    const offShortcut = api.onShortcut(shortcut => {
      switch (shortcut) {
        case 'save':
          showSaveHint();
          break;
        case 'reset-font':
          setFontSize(DEFAULT_FONT_SIZE);
          break;
        case 'increase-font':
          setFontSize(size => clampFontSize(size + 1));
          break;
        case 'decrease-font':
          setFontSize(size => clampFontSize(size - 1));
          break;
        case 'toggle-theme':
          // Flip to a scheme of the opposite lightness rather than toggling a boolean.
          setScheme(current => {
            const target = schemes.current.find(s => s.dark !== current?.dark);
            if (target) api.setScheme(target.id).then(setScheme);
            return current;
          });
          break;
        case 'toggle-shortcuts':
          setShortcutsVisible(visible => !visible);
          break;
        case 'undo':
          editor.current?.undo();
          break;
        case 'redo':
          editor.current?.redo();
          break;
        default:
          break;
      }
    });

    const offUpdate = api.onUpdateAvailable(setUpdateVersion);

    return () => {
      offShortcut();
      offUpdate();
      clearTimeout(saveHintTimer.current);
    };
  }, [showSaveHint]);

  useEffect(() => {
    const preventDefault = event => event.preventDefault();
    document.addEventListener('dragover', preventDefault);
    document.addEventListener('drop', preventDefault);

    return () => {
      document.removeEventListener('dragover', preventDefault);
      document.removeEventListener('drop', preventDefault);
    };
  }, []);

  const handleChange = useCallback(content => api.writeContent(content), []);
  const handleFoldsChange = useCallback(folds => api.setSetting('folds2', folds), []);

  const openReleases = () => {
    api.openExternal(RELEASES_URL);
    setUpdateVersion(null);
  };

  const dismissUpdate = event => {
    event.stopPropagation();
    api.dismissUpdate(updateVersion);
    setUpdateVersion(null);
  };

  if (!initial) return null;

  const style = { fontSize: `${fontSize}px` };

  return (
    <div className="app" style={style} data-platform={api.platform}>
      <Editor
        ref={editor}
        initialContent={initial.content}
        initialFolds={initial.folds}
        onChange={handleChange}
        onFoldsChange={handleFoldsChange}
        onSave={showSaveHint}
      />

      <div className={saveHintVisible ? 'nosave active' : 'nosave'}>Already saved! ;)</div>

      <div className={updateVersion ? 'updater active' : 'updater'} onClick={openReleases}>
        {`There's an update available! Get version ${updateVersion || ''}`}
        <span title="Don't show this again until next available update" onClick={dismissUpdate}>
          ×
        </span>
      </div>

      <div className="titlebar" />

      <Shortcuts visible={shortcutsVisible} platform={api.platform} onClose={() => setShortcutsVisible(false)} />
    </div>
  );
}
