'use strict';
// Exercises the production creation snapshot normalizer and TooltipDocument
// consumer. This is a protocol fixture; it is not a Flash or visual acceptance.
const assert = require('node:assert/strict');
const Runtime = require('../launcher/web/modules/bootstrap-character-create-runtime.js');
const Doc = require('../launcher/web/modules/tooltip-document.js');
const document = {version:1, title:'测试上装', profile:'dense', sections:[
    {role:'description', runs:[{text:'新引擎内容 <script>', color:'#FFCC00'}]}
]};
const row = {identifier:'coat', name:'测试上装', iconName:'coat', itemType:'防具',
    introHTML:'兼容标题', descHTML:'兼容说明', document};
const faces = {male:{identifier:'m',name:'男'},female:{identifier:'f',name:'女'}};
const defaults = {};
for (const gender of ['male','female']) defaults[gender] = {height:175,
    faceIdentifier:faces[gender].identifier,hairIdentifier:'hair',upperIdentifier:'coat',
    lowerIdentifier:'coat',footwearIdentifier:'coat',difficulty:'normal'};
const pair = () => ({male:[{...row}], female:[{...row}]});
const snapshot = {cmd:'character_create_snapshot',openRequestId:'o',attemptId:'a',slotKey:'slot',
    constraints:{displayNameMin:1,displayNameMax:32,characterNameMin:1,characterNameMax:15,heightMin:150,heightMax:200},
    hairCatalog:[{identifier:'hair',name:'发型'}],appearanceCatalog:{faces,upper:pair(),lower:pair(),footwear:pair()},
    defaults,difficulties:['easy','normal','hard'].map(identifier=>({identifier,name:identifier,description:''}))};
const normalized = Runtime.normalizeSnapshot(snapshot);
assert(normalized, 'creation catalog with document must be accepted');
const projected = normalized.appearanceCatalog.upper.male[0];
assert.deepEqual(projected.document, document, 'normalizer must preserve the document');
assert(Doc.normalize(projected), 'production document consumer accepts projection');
snapshot.appearanceCatalog.upper.male[0].document = ['invalid'];
assert.equal(Runtime.normalizeSnapshot(snapshot).appearanceCatalog.upper.male[0].document, null);
delete snapshot.appearanceCatalog.upper.male[0].document;
assert.equal(Runtime.normalizeSnapshot(snapshot).appearanceCatalog.upper.male[0].document, null);
snapshot.appearanceCatalog.upper.male[0].identifier = 'foreign';
assert.equal(Runtime.normalizeSnapshot(snapshot), null, 'document does not bypass appearance identity');
console.log('PASS: creation document transport, malformed value, legacy value and exact identity');
