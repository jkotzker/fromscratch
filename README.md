<img src="https://fromscratch.rocks/assets/img/icon.png?">

FromScratch
===========

## A simple but smart note-taking app

FromScratch is a little app that you can use as a quick note taking or todo app.

* Small and simple, the only UI is the text you type
* Saves on-the-fly, no need to manually save
* Automatic indenting
* Note-folding
* Use checkboxes to keep track of your TODO's
* Powerful keyboard control
* Replaces common syntax with symbols, such as arrows
* Dark and Light theme
* Portable mode support
* Free

> This is a fork of [Kilian/fromscratch](https://github.com/Kilian/fromscratch), kept building and
> running on current macOS. See [Fork notes](#fork-notes) for what changed.

### Shortcuts

* `f1` - show/hide shortcut overview
* `cmd/ctrl+up` - move current line up
* `cmd/ctrl+down` - move current line down
* `cmd/ctrl+d` - delete current line
* `cmd/ctrl+z` / `shift+cmd/ctrl+z` - undo / redo
* `cmd/ctrl+w/q` - close application
* `cmd/ctrl +/=` - zoom text in
* `cmd/ctrl -` - zoom text out
* `cmd/ctrl+0` - reset text size
* `cmd/ctrl+]/[/k` - fold note collapsing
* `cmd/ctrl+f` - search (toggle `.*` in the search panel for regular expressions)
* `shift+cmd/ctrl+f` - replace
* `shift+cmd/ctrl+r` - replace all
* `cmd/ctrl+g` - jump to line (you can also use `line:character` notation)
* `cmd/ctrl+/` or `cmd/ctrl+l` - Add or toggle a checkbox
* `f11` - Toggle fullscreen
* `cmd/ctrl+i` - Toggle between light and dark theme
* `alt` - show or hide menu (Windows only)
* `cmd/ctrl+s` - ...this does nothing.

## Development

Requires Node 20.19+ (see `.nvmrc`).

```sh
# Install dependencies
npm install

# Run in development (hot reloading renderer, devtools open)
npm run dev

# Build without packaging
npm run build

# Build and package a macOS arm64 .dmg into release/
npm run package:mac

# Lint / format
npm run lint
npm run format
```

`npm run dev` stores its data in `~/.fromscratch/dev`, so development never touches real notes.

### Installing your build

`npm run dev` runs from source; the app in `/Applications` is a frozen bundle. To pick up source
changes there, repackage and copy it over:

```sh
npm run package:mac
cp -R release/mac-arm64/FromScratch.app /Applications/
```

Quit the app first, and don't run it alongside `npm run dev` — both write the same
`~/.fromscratch/content.txt`. If the upstream Homebrew cask is still installed, remove it first, or
the two bundles collide on the same file name:

```sh
brew uninstall --cask fromscratch
```

Builds are **unsigned**: they run fine when built and used locally. If a build ever gets
quarantined (for instance after being downloaded), clear it with:

```sh
xattr -dr com.apple.quarantine /Applications/FromScratch.app
```

Signing and notarizing would need an Apple Developer account, `mac.identity` in
`electron-builder.yml`, and an `@electron/notarize` afterSign hook.

### Command Line Arguments
**Portable Mode**
`--portable`

Lets you store all the files FromScratch generates in a specified location, such as a USB-stick or
other portable storage device. In this mode both the configuration files as well as your text content will be stored in
a "userdata" directory alongside the FromScratch executable, or when given a directory as an argument, will store
the files there.

You can also use this to store the FromScratch configuration files, and the text content, in a synced cloud storage
folder.

```
# run FromScratch in portable mode, saving data in application directory.
fromscratch --portable
```

```
# run FromScratch in portable mode, saving data in custom directory.
fromscratch --portable ~/fromscratch_data
```
**help**
`-h, --help`

Prints help information

### FAQ
*Where is my data saved?*

Your data is saved in a plain text file content.txt. On Mac and Linux, this file is saved in ~/.fromscratch. On Windows
this file is saved in a directory called ".fromscratch" in your userprofile directory.

*Can my data be saved in an alternate directory?*

Yes! See the **portable mode** section under the **Command Line Arguments** heading above.

## Fork notes

The upstream project stopped at Electron 4 / webpack 4 / Babel 6 / node-sass, which no longer
installs or builds on current Node and macOS. This fork keeps the app and its data format
identical while replacing everything underneath:

* **electron-vite + Vite** instead of webpack, Babel and the DLL build
* **Electron 43**, built for Apple Silicon, with `contextIsolation`, `sandbox` and a preload
  bridge instead of the removed `remote` module
* **React 19** function components
* **CodeMirror 6** instead of CodeMirror 5 and the unmaintained `react-codemirror`. Indentation
  folding, checkbox toggling and the fold persistence are reimplemented in `src/renderer/src/editor`
* **Plain CSS** with custom properties instead of Sass
* macOS vibrancy uses `under-window` driven by `nativeTheme` (`ultra-dark`/`medium-light` were
  removed in Electron 27)
* Shortcuts come from the menu and the editor keymap instead of OS-wide `globalShortcut`
  registrations
* Content is written to disk debounced instead of on every keystroke
* The update check looks at this fork's GitHub releases

The on-disk format is unchanged: `~/.fromscratch/content.txt` plus the settings files next to it.
Folds are stored under a new `folds2` key, so the old `folds` file is simply ignored.

### Credits

FromScratch is built upon these open source projects:
	<a href="https://electronjs.org">Electron</a>,
	<a href="https://react.dev">React</a>,
	<a href="https://github.com/tonsky/FiraCode">Fira Code</a>,
	<a href="https://codemirror.net">CodeMirror</a> and
	<a href="https://github.com/chentsulin/electron-react-boilerplate">Electron-react-boilerplate</a>.

Original app by [@kilianvalkhof](https://kilianvalkhof.com). Thanks to @bittersweet for helping set
up IPC to work around a particularly nasty bug, @chentsulin for the electron-react-boilerplate, and
@ctrauma for the portable bits.
