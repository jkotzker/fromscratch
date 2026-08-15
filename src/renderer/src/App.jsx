import { useCallback, useEffect, useRef, useState } from 'react';
import Editor from './components/Editor';
import Shortcuts from './components/Shortcuts';

const { api } = window;

const RELEASES_URL = 'https://github.com/buzkall/fromscratch/releases';

const LIGHT_THEME_FILTER = 'invert(100%) hue-rotate(20deg) brightness(1.1) contrast(1.4) grayscale(20%)';

const DEFAULT_CONTENT =
  '|> Welcome to FromScratch.\n';

const clampFontSize = size => Math.min(Math.max(size, 0.5), 2.5);

export default function App() {
  const [initial, setInitial] = useState(null);
  const [fontSize, setFontSize] = useState(1);
  const [lightTheme, setLightTheme] = useState(false);
  const [saveHintVisible, setSaveHintVisible] = useState(false);
  const [updateVersion, setUpdateVersion] = useState(null);
  const [shortcutsVisible, setShortcutsVisible] = useState(false);

  const editor = useRef(null);
  const saveHintTimer = useRef(null);

  useEffect(() => {
    let cancelled = false;

    api.init().then(({ platform, content, settings }) => {
      if (cancelled) return;

      document.body.dataset.platform = platform;
      setFontSize(clampFontSize(settings.fontSize || 1));
      setLightTheme(Boolean(settings.lightTheme));
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
    if (initial) api.setSetting('fontSize', fontSize);
  }, [initial, fontSize]);

  useEffect(() => {
    if (initial) api.setTheme(lightTheme);
  }, [initial, lightTheme]);

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
          setFontSize(1);
          break;
        case 'increase-font':
          setFontSize(size => clampFontSize(size + 0.1));
          break;
        case 'decrease-font':
          setFontSize(size => clampFontSize(size - 0.1));
          break;
        case 'toggle-theme':
          setLightTheme(light => !light);
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

  const style = {
    fontSize: `${fontSize}rem`,
    ...(lightTheme ? { filter: LIGHT_THEME_FILTER } : {}),
  };

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
