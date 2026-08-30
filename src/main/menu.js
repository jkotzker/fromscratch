import { Menu, shell } from 'electron';

const REPO_URL = 'https://github.com/jkotzker/fromscratch';

// Accelerators live on the menu (and, for editor commands, in the CodeMirror keymap). The app
// used to grab Esc, F1, F11 and Cmd+W/Q/R with globalShortcut, which registers them OS-wide.
export function buildMenu({ appName, version, platform, dispatch, toggleFullscreen, quit }) {
  const viewSubmenu = [
    {
      label: 'Toggle theme',
      accelerator: 'CmdOrCtrl+I',
      click: () => dispatch('toggle-theme'),
    },
    { type: 'separator' },
    {
      label: 'Increase font size',
      accelerator: 'CmdOrCtrl+Plus',
      click: () => dispatch('increase-font'),
    },
    {
      // Same command on the unshifted key, which is what people actually press.
      label: 'Increase font size',
      accelerator: 'CmdOrCtrl+=',
      visible: false,
      click: () => dispatch('increase-font'),
    },
    {
      label: 'Decrease font size',
      accelerator: 'CmdOrCtrl+-',
      click: () => dispatch('decrease-font'),
    },
    {
      label: 'Reset font size',
      accelerator: 'CmdOrCtrl+0',
      click: () => dispatch('reset-font'),
    },
    { type: 'separator' },
    {
      label: 'Toggle fullscreen',
      accelerator: 'F11',
      click: toggleFullscreen,
    },
    {
      label: 'Show all shortcuts',
      accelerator: 'F1',
      click: () => dispatch('toggle-shortcuts'),
    },
  ];

  const openWebsite = () => shell.openExternal('https://fromscratch.rocks');

  const aboutItems = [
    {
      label: 'Website',
      click: openWebsite,
    },
    {
      label: 'Support',
      click: () => shell.openExternal(`${REPO_URL}/issues`),
    },
    {
      label: `Check for updates (current: ${version})`,
      click: () => shell.openExternal(`${REPO_URL}/releases`),
    },
  ];

  // Undo/redo are dispatched to CodeMirror instead of using the native roles: CodeMirror keeps
  // its own history, so webContents.undo() would desync the document.
  const editSubmenu = [
    { label: 'Undo', accelerator: 'CmdOrCtrl+Z', click: () => dispatch('undo') },
    { label: 'Redo', accelerator: 'Shift+CmdOrCtrl+Z', click: () => dispatch('redo') },
    { type: 'separator' },
    { label: 'Cut', accelerator: 'CmdOrCtrl+X', role: 'cut' },
    { label: 'Copy', accelerator: 'CmdOrCtrl+C', role: 'copy' },
    { label: 'Paste', accelerator: 'CmdOrCtrl+V', role: 'paste' },
    { label: 'Select All', accelerator: 'CmdOrCtrl+A', role: 'selectAll' },
  ];

  const template =
    platform === 'darwin'
      ? [
          {
            label: appName,
            submenu: [
              { label: `About ${appName}`, click: openWebsite },
              ...aboutItems.slice(1),
              { type: 'separator' },
              { label: `Hide ${appName}`, accelerator: 'Command+H', role: 'hide' },
              { label: 'Hide Others', accelerator: 'Command+Alt+H', role: 'hideOthers' },
              { label: 'Show All', role: 'unhide' },
              { type: 'separator' },
              { label: 'Close', accelerator: 'Command+W', click: quit },
              { label: 'Quit', accelerator: 'Command+Q', click: quit },
            ],
          },
          { label: 'Edit', submenu: editSubmenu },
          { label: 'View', submenu: viewSubmenu },
        ]
      : [
          {
            label: appName,
            submenu: [
              ...aboutItems,
              { type: 'separator' },
              { label: 'Quit', accelerator: 'CmdOrCtrl+Q', click: quit },
              { label: 'Close', accelerator: 'CmdOrCtrl+W', visible: false, click: quit },
            ],
          },
          { label: 'Edit', submenu: editSubmenu },
          { label: 'View', submenu: viewSubmenu },
        ];

  return Menu.buildFromTemplate(template);
}
