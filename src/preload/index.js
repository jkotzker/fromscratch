import { contextBridge, ipcRenderer } from 'electron';

// The renderer runs sandboxed with context isolation, so everything it needs from Node/Electron
// (including process.platform) comes through this bridge.
contextBridge.exposeInMainWorld('api', {
  platform: process.platform,

  init: () => ipcRenderer.invoke('app:init'),

  writeContent: content => ipcRenderer.send('content:write', content),

  setSetting: (key, value) => ipcRenderer.send('settings:set', key, value),

  // Resolves to the applied scheme, so the renderer never has to derive a palette itself.
  setScheme: id => ipcRenderer.invoke('scheme:set', id),

  dismissUpdate: version => ipcRenderer.send('update:dismiss', version),

  openExternal: url => ipcRenderer.send('shell:open-external', url),

  onShortcut: callback => {
    const listener = (_event, shortcut) => callback(shortcut);
    ipcRenderer.on('shortcut', listener);
    return () => ipcRenderer.removeListener('shortcut', listener);
  },

  onUpdateAvailable: callback => {
    const listener = (_event, version) => callback(version);
    ipcRenderer.on('update-available', listener);
    return () => ipcRenderer.removeListener('update-available', listener);
  },

  // The scheme can also be changed from the menu, which the renderer never sees directly.
  onSchemeChanged: callback => {
    const listener = (_event, scheme) => callback(scheme);
    ipcRenderer.on('scheme-changed', listener);
    return () => ipcRenderer.removeListener('scheme-changed', listener);
  },

  // Settings that the menu can change on its own -- the renderer would otherwise keep rendering
  // the old value until a restart.
  onSettingChanged: callback => {
    const listener = (_event, key, value) => callback(key, value);
    ipcRenderer.on('setting-changed', listener);
    return () => ipcRenderer.removeListener('setting-changed', listener);
  },

  onSchemesChanged: callback => {
    const listener = (_event, schemes) => callback(schemes);
    ipcRenderer.on('schemes-changed', listener);
    return () => ipcRenderer.removeListener('schemes-changed', listener);
  },
});
