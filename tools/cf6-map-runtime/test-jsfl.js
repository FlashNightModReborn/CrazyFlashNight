// Control-flow reference tests only; these do not execute or validate CS6 APIs.
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const assert = require('assert');
const source = fs.readFileSync(path.join(__dirname, 'generated/CF6_A01_BG.jsfl'), 'utf8');
function run(mode) {
  const receipts = [], closed = [], imported = [];
  let created = 0;
  const timeline = { currentLayer: 0, layers: [{ frames: [{}] }], addNewLayer() {} };
  const doc = {
    getTimeline() { return timeline; },
    importFile(uri) { this.selection = [{ libraryItem: {} }]; imported.push(this.selection[0]); },
    selectNone() { this.selection = []; }
  };
  const context = {
    FLfile: {
      platformPathToURI(value) { return value; },
      exists(value) { return value.endsWith('.xfl') ? mode === 'existing' : mode !== 'missing'; },
      write(uri, value) { receipts.push(value); return mode === 'start-receipt' ? false : !(mode === 'saved-receipt' && value.includes('_SAVED')); }
    },
    fl: {
      createDocument() { created++; return mode === 'no-document' ? null : doc; },
      saveDocument(value) { assert.strictEqual(value, doc); return mode !== 'save'; },
      closeDocument(value, save) { assert.strictEqual(save, false); closed.push(value); },
      trace() {}
    }
  };
  let error;
  try { vm.runInNewContext(source, context); } catch (e) { error = e; }
  if (mode === 'success') {
    assert(!error);
    assert(imported.length > 0);
    for (const item of imported) {
      assert.strictEqual(item.libraryItem.compressionType, 'lossless');
      assert.strictEqual(item.libraryItem.useImportedJPEGData, false);
      assert.strictEqual(item.libraryItem.allowSmoothing, true);
    }
  } else {
    assert(error, mode);
    if (mode !== 'start-receipt') assert(receipts.some(x => x.includes('_ERROR')), mode);
  }
  const ownsDoc = !['existing', 'start-receipt', 'no-document'].includes(mode);
  assert.strictEqual(closed.length, ownsDoc ? 1 : 0, mode);
  if (ownsDoc) assert.strictEqual(closed[0], doc);
  if (['existing', 'start-receipt'].includes(mode)) assert.strictEqual(created, 0);
}
for (const mode of ['success', 'existing', 'missing', 'save', 'no-document', 'start-receipt', 'saved-receipt']) run(mode);
console.log('7 JSFL control-flow reference cases passed; actual CS6 API behavior remains separate');
