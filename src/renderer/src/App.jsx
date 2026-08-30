import { useCallback, useEffect, useRef, useState } from 'react';
import Editor from './components/Editor';
import FontPicker from './components/FontPicker';
import Shortcuts from './components/Shortcuts';
import { fontStack, listFontFamilies } from './fonts';

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
  const [fontFamily, setFontFamily] = useState(null);
  const [families, setFamilies] = useState([]);
  const [scheme, setScheme] = useState(null);
  const [saveHintVisible, setSaveHintVisible] = useState(false);
  const [updateVersion, setUpdateVersion] = useState(null);
  const [shortcutsVisible, setShortcutsVisible] = useState(false);
  const [fontPickerVisible, setFontPickerVisible] = useState(false);

  const editor = useRef(null);
  const saveHintTimer = useRef(null);
  const schemes = useRef([]);
  const activeScheme = useRef(null);

  useEffect(() => {
    let cancelled = false;

    api.init().then(({ platform, content, settings, scheme: active, schemes: available }) => {
      if (cancelled) return;

      document.body.dataset.platform = platform;
      schemes.current = available || [];
      setFontSize(clampFontSize(settings.font?.size || DEFAULT_FONT_SIZE));
      setFontFamily(settings.font?.family || null);
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
    if (initial) api.setSetting('font', { family: fontFamily, size: fontSize });
  }, [initial, fontFamily, fontSize]);

  // Only set the property for a custom choice; leaving it unset lets each platform keep its own
  // bundled default from the stylesheet.
  useEffect(() => {
    const stack = fontStack(fontFamily);
    if (stack) document.documentElement.style.setProperty('--font-family', stack);
    else document.documentElement.style.removeProperty('--font-family');
  }, [fontFamily]);

  // Enumerating is a one-off; the list is only needed once the picker opens.
  useEffect(() => {
    let cancelled = false;
    listFontFamilies().then(list => {
      if (!cancelled) setFamilies(list);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  // The whole stylesheet reads its colours from custom properties, so applying a scheme is just
  // setting them on the root element -- no CSS rules change.
  useEffect(() => {
    activeScheme.current = scheme;
    if (!scheme?.palette) return;
    const root = document.documentElement;
    for (const [name, value] of Object.entries(scheme.palette)) root.style.setProperty(name, value);
  }, [scheme]);

  // Shared by the menu accelerator and the editor keymap.
  const toggleScheme = useCallback(() => {
    const current = activeScheme.current;
    const target = schemes.current.find(s => s.dark !== current?.dark);
    if (target) api.setScheme(target.id).then(setScheme);
  }, []);

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
          toggleScheme();
          break;
        case 'toggle-shortcuts':
          setShortcutsVisible(visible => !visible);
          break;
        case 'toggle-font-picker':
          setFontPickerVisible(visible => !visible);
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

    // Selecting a scheme from the menu happens entirely in the main process; without these the
    // setting would change but the window would keep its old colours until a restart.
    const offScheme = api.onSchemeChanged(setScheme);
    const offSchemes = api.onSchemesChanged(list => {
      schemes.current = list || [];
    });

    return () => {
      offShortcut();
      offUpdate();
      offScheme();
      offSchemes();
      clearTimeout(saveHintTimer.current);
    };
  }, [showSaveHint, toggleScheme]);

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
        onToggleTheme={toggleScheme}
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

      <FontPicker
        key={fontPickerVisible ? 'open' : 'closed'}
        visible={fontPickerVisible}
        families={families}
        family={fontFamily}
        size={fontSize}
        onChangeFamily={setFontFamily}
        onChangeSize={setFontSize}
        onClose={() => setFontPickerVisible(false)}
      />
    </div>
  );
}
