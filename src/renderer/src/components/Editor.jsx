import { redo, undo } from '@codemirror/commands';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { useEffect, useImperativeHandle, useRef } from 'react';
import { createExtensions } from '../editor/extensions';
import { applyFolds } from '../editor/folds';

/**
 * Thin React wrapper around a single CodeMirror 6 view. The document is uncontrolled: the editor
 * owns it after mount and reports changes upwards, which is what the autosave expects.
 */
export default function Editor({ ref, initialContent, initialFolds, onChange, onFoldsChange, onSave }) {
  const parent = useRef(null);
  const view = useRef(null);
  const callbacks = useRef({ onChange, onFoldsChange, onSave });

  useEffect(() => {
    callbacks.current = { onChange, onFoldsChange, onSave };
  }, [onChange, onFoldsChange, onSave]);

  useImperativeHandle(ref, () => ({
    focus: () => view.current?.focus(),
    undo: () => view.current && undo(view.current),
    redo: () => view.current && redo(view.current),
  }));

  useEffect(() => {
    const instance = new EditorView({
      parent: parent.current,
      state: EditorState.create({
        doc: initialContent,
        extensions: createExtensions({
          onChange: content => callbacks.current.onChange(content),
          onFoldsChange: folds => callbacks.current.onFoldsChange(folds),
          onSave: () => callbacks.current.onSave(),
        }),
      }),
    });

    view.current = instance;
    applyFolds(instance, initialFolds);
    instance.focus();

    // Handy from the devtools console while developing.
    if (import.meta.env.DEV) window.__editor = instance;

    return () => {
      instance.destroy();
      view.current = null;
    };
    // Mount only: re-creating the view on prop changes would throw away undo history.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return <div className="editor" ref={parent} />;
}
