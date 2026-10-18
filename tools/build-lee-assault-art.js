'use strict';
// Imported PNG bytes are the raster authority; the AI prompt is provenance, not a rebuild recipe.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = process.env.CF7_ART_ROOT || path.resolve(__dirname, '..');
const sourceRel = 'data/books/lee-assault-art-source.json';
const dest = path.join(root, 'launcher/web/assets/book-comic/lee');
const manifestPath = path.join(dest, 'manifest.json');
const ids = ['lee-ambush', 'lee-breakout', 'lee-ending-normal', 'lee-ending-hidden'];
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

function readSource() {
  const bytes = fs.readFileSync(path.join(root, sourceRel));
  const source = JSON.parse(bytes);
  if (source.schema !== 'lee-assault-comic-source.v2' || source.mode !== 'built-in image_gen'
      || !Array.isArray(source.files) || source.files.length !== ids.length
      || !Array.isArray(source.prompts) || source.prompts.length < 4) throw Error('Invalid Lee art provenance');
  if (new Set(source.files.map(row => row.file)).size !== ids.length) throw Error('Duplicate Lee image');
  source.files.forEach((row, index) => {
    if (row.pageId !== ids[index] || !/^[a-z0-9-]+\.png$/.test(row.file)
        || !/^[a-f0-9]{64}$/.test(row.sha256) || !Number.isSafeInteger(row.bytes)
        || row.bytes <= 0 || row.bytes > 8 * 1024 * 1024
        || row.width !== 1024 || row.height !== 1536) throw Error('Invalid Lee image record');
  });
  return {source, sourceHash:digest(Buffer.from(JSON.stringify(source)))};
}

function checkBytes(row, bytes) {
  if (bytes.length !== row.bytes || digest(bytes) !== row.sha256) throw Error('Lee image digest mismatch: ' + row.file);
  if (!bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))
      || bytes.toString('ascii', 12, 16) !== 'IHDR'
      || bytes.readUInt32BE(16) !== row.width || bytes.readUInt32BE(20) !== row.height)
    throw Error('Lee image format/dimensions mismatch: ' + row.file);
}

function expectedManifest(source, sourceHash) {
  return JSON.stringify({schema:'lee-assault-comic-art.v2', generator:'tools/build-lee-assault-art.js',
    nativeVectors:false, source:sourceRel, sourceSha256:sourceHash,
    totalImageBytes:source.files.reduce((sum, row) => sum + row.bytes, 0), files:source.files}, null, 2) + '\n';
}

function verify() {
  const {source, sourceHash} = readSource();
  const comic = JSON.parse(fs.readFileSync(path.join(root, 'data/books/lee-assault-comic.json')));
  if (comic.pages.length !== ids.length) throw Error('Unexpected Lee page count');
  for (const row of source.files) {
    checkBytes(row, fs.readFileSync(path.join(dest, row.file)));
    const page = comic.pages.find(item => item.id === row.pageId);
    if (!page || page.image !== 'assets/book-comic/lee/' + row.file) throw Error('Lee comic image routing mismatch');
  }
  if (fs.readFileSync(manifestPath, 'utf8').replace(/\r\n/g, '\n') !== expectedManifest(source, sourceHash))
    throw Error('Lee art manifest is stale; run tools/build-lee-assault-art.js');
  console.log('Lee comic: 4 raster originals, provenance and exact-byte manifest verified ('
    + source.files.reduce((sum, row) => sum + row.bytes, 0) + ' bytes)');
}

function build() {
  const {source, sourceHash} = readSource();
  const imports = process.argv.find(arg => arg.startsWith('--imports-dir='));
  // Validate the complete import before changing any existing image.
  const loaded = source.files.map(row => {
    const file = path.join(imports ? path.resolve(imports.slice(14)) : dest, row.file);
    const bytes = fs.readFileSync(file); checkBytes(row, bytes); return {row, bytes};
  });
  fs.mkdirSync(dest, {recursive:true});
  if (imports) for (const {row, bytes} of loaded) fs.writeFileSync(path.join(dest, row.file), bytes);
  fs.writeFileSync(manifestPath, expectedManifest(source, sourceHash));
  verify();
}

module.exports = {verify};
if (require.main === module) {
  try { if (process.argv.includes('--check')) verify(); else build(); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
