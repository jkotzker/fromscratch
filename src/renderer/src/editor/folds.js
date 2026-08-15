import { foldedRanges, foldEffect, unfoldEffect } from '@codemirror/language';

/** The folded ranges of a state, as plain document offsets, ready to be persisted. */
export const collectFolds = state => {
  const folds = [];
  foldedRanges(state).between(0, state.doc.length, (from, to) => {
    folds.push({ from, to });
  });
  return folds;
};

/** Restores persisted folds, skipping anything that no longer fits the document. */
export const applyFolds = (view, folds) => {
  if (!Array.isArray(folds) || !folds.length) return;

  const max = view.state.doc.length;
  const effects = folds
    .filter(fold => fold && Number.isInteger(fold.from) && Number.isInteger(fold.to))
    .filter(fold => fold.from < fold.to && fold.to <= max)
    .map(fold => foldEffect.of({ from: fold.from, to: fold.to }));

  if (effects.length) view.dispatch({ effects });
};

export const hasFoldEffect = transactions =>
  transactions.some(transaction =>
    transaction.effects.some(effect => effect.is(foldEffect) || effect.is(unfoldEffect))
  );
