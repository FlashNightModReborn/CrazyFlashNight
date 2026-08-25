import assert from 'node:assert/strict';
import test from 'node:test';
import { DisposableBag, GenerationFence, isEditableKeyboardTarget } from '../src/app/lifecycle.js';

test('PHASE-A-LIFECYCLE generation fence rejects late async work after invalidate and dispose', () => {
  const fence = new GenerationFence();
  const first = fence.next();
  assert.equal(fence.isCurrent(first), true);
  fence.invalidate();
  assert.equal(fence.isCurrent(first), false);
  const second = fence.next();
  assert.equal(fence.isCurrent(second), true);
  fence.dispose();
  assert.equal(fence.isCurrent(second), false);
  assert.equal(fence.next(), fence.current());
});

test('PHASE-A-LIFECYCLE disposable bag tears down once in reverse ownership order', () => {
  const calls: string[] = [];
  const bag = new DisposableBag();
  bag.add(() => calls.push('listener'));
  bag.add(() => calls.push('renderer'));
  bag.dispose();
  bag.dispose();
  bag.add(() => calls.push('late'));
  assert.deepEqual(calls, ['renderer', 'listener', 'late']);
});

test('PHASE-A-INPUT shortcuts ignore form controls and editable descendants', () => {
  assert.equal(isEditableKeyboardTarget({ tagName: 'input' }), true);
  assert.equal(isEditableKeyboardTarget({ tagName: 'SELECT' }), true);
  assert.equal(isEditableKeyboardTarget({ tagName: 'button' }), true);
  assert.equal(isEditableKeyboardTarget({ tagName: 'div', isContentEditable: true }), true);
  assert.equal(isEditableKeyboardTarget({ tagName: 'span', closest: () => ({ tagName: 'BUTTON' }) }), true);
  assert.equal(isEditableKeyboardTarget({ tagName: 'div', getAttribute: () => 'plaintext-only' }), true);
  assert.equal(isEditableKeyboardTarget({ tagName: 'div', getAttribute: () => 'false', closest: () => null }), false);
  assert.equal(isEditableKeyboardTarget(null), false);
});
