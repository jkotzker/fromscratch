const shortcutList = mod => [
  [[`${mod}+up`], 'move current line up'],
  [[`${mod}+down`], 'move current line down'],
  [[`${mod}+d`], 'delete current line'],
  [[`${mod}+w/q`], 'close application'],
  [[`${mod} +/=`], 'zoom text in'],
  [[`${mod} -`], 'zoom text out'],
  [[`${mod}+0`], 'reset text size'],
  [[`${mod}+]/[/k`], 'fold note collapsing'],
  [[`${mod}+f`], 'search (toggle .* in the search panel for regular expressions)'],
  [[`shift+${mod}+f`], 'replace'],
  [[`shift+${mod}+r`], 'replace all'],
  [[`${mod}+g`], 'jump to line (you can also use line:character notation)'],
  [[`${mod}+/`, `${mod}+l`], 'add or toggle a checkbox'],
  [[`${mod}+z`, `shift+${mod}+z`], 'undo / redo'],
  [['f11'], 'toggle fullscreen'],
  [[`${mod}+i`], 'toggle between light and dark theme'],
  [['alt'], 'show or hide menu (Windows only)'],
  [[`${mod}+s`], '...this does nothing.'],
];

export default function Shortcuts({ visible, platform, onClose }) {
  const mod = platform === 'darwin' ? 'Cmd' : 'Ctrl';

  return (
    <div className={`shortcuts ${visible ? 'visible' : ''}`}>
      <h3>Shortcuts</h3>

      <button type="button" title="Close shortcuts" onClick={onClose}>
        <span>×</span>
      </button>

      <ul>
        {shortcutList(mod).map(([keys, description]) => (
          <li key={description}>
            <span>
              {keys.map((key, index) => (
                <span key={key}>
                  {index > 0 ? ' or ' : ''}
                  <kbd>{key}</kbd>
                </span>
              ))}
            </span>
            <span>{description}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
