// Generated recipe. Run only in the root-owned CS6 session.
// Deterministic native import for CF6_A01_Turret: 3 PNG + 1 MP3, nothing else.
(function () {
function canonicalDocumentURI(value) {
  try { return encodeURI(decodeURI(value)); } catch (uriError) { return value; }
}
function uri(p) { return FLfile.platformPathToURI(p); }
var target = uri("C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\flashswf\\backgrounds\\cf6\\CF6_A01_Turret\\CF6_A01_Turret.xfl");
var stamp = String(new Date().getTime());
var receipt = uri("C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tmp\\cf6-roguelike-20261021\\validation\\turret-native-import-" + stamp + ".txt");
if (!FLfile.write(receipt, "CF6_TURRET_NATIVE_IMPORT_STARTED\n" + target + "\n"))
  throw new Error("Cannot write native import receipt before creating document");
var assets = [
  {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\flashswf\\arts\\new\\Codex素材源稿\\CF6教学炮塔\\bitmaps\\turret-body-1588.png", "item": "CF6Turret/turret-body-1588.png", "kind": "bitmap"},
  {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\flashswf\\arts\\new\\Codex素材源稿\\CF6教学炮塔\\bitmaps\\muzzle-flash-502.png", "item": "CF6Turret/muzzle-flash-502.png", "kind": "bitmap"},
  {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\flashswf\\arts\\new\\Codex素材源稿\\CF6教学炮塔\\bitmaps\\turret-detail-927.png", "item": "CF6Turret/turret-detail-927.png", "kind": "bitmap"},
  {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\flashswf\\arts\\new\\Codex素材源稿\\CF6教学炮塔\\bitmaps\\fire-sound-1169.import.mp3", "item": "CF6Turret/fire-sound-1169.import.mp3", "kind": "sound"}
];
var doc = null;
try {
if (FLfile.exists(target)) throw new Error("Refusing to overwrite existing XFL: " + target);
doc = fl.createDocument();
if (!doc) throw new Error("Native document creation failed");
doc.asVersion = 2;
doc.frameRate = 30;
doc.width = 200; doc.height = 120;
if (!doc.library.itemExists("CF6Turret") && doc.library.newFolder("CF6Turret") === false)
  throw new Error("Cannot create owned CF6Turret library folder");
for (var i=0; i<assets.length; i++) {
  var a=assets[i];
  FLfile.write(receipt,"ASSET_BEGIN "+a.item+"\n","append");
  var sourceURI=uri(a.path);
  if (!FLfile.exists(sourceURI)) throw new Error("Missing asset: " + a.path);
  doc.importFile(canonicalDocumentURI(sourceURI), false);
  var item=null;
  if (a.kind==="bitmap") {
    if (doc.selection.length !== 1) throw new Error("Expected one PNG instance: " + a.item);
    item=doc.selection[0].libraryItem;
    item.compressionType="lossless";
    item.useImportedJPEGData=false;
    item.allowSmoothing=false;
    doc.deleteSelection();
  } else {
    var before=doc.library.items.length;
    for (var k=0;k<doc.library.items.length;k++) {
      var it=doc.library.items[k];
      if (it.itemType==="sound" && it.name.indexOf("fire-sound-1169")>=0) { item=it; break; }
    }
    if (!item) throw new Error("Sound import missing from library: " + a.item);
  }
  var leaf=a.item.substring(a.item.lastIndexOf("/")+1);
  doc.library.selectItem(item.name,true,true);
  if (item.name !== leaf && doc.library.renameItem(leaf) === false)
    throw new Error("Cannot name imported item: " + a.item);
  if (doc.library.moveToFolder("CF6Turret") === false || !doc.library.itemExists(a.item))
    throw new Error("Cannot verify imported library path: " + a.item);
  FLfile.write(receipt,"ASSET_IMPORTED "+a.item+"\n","append");
}
var timeline = doc.getTimeline();
timeline.layers[timeline.currentLayer].name="empty";
timeline.layers[timeline.currentLayer].frames[0].actionScript="stop();";
if (!fl.saveDocument(doc,canonicalDocumentURI(target))) throw new Error("XFL save failed");
if (!FLfile.write(receipt,"CF6_TURRET_NATIVE_IMPORT_SAVED\n"+target+"\n","append"))
  throw new Error("Native XFL saved but receipt append failed");
fl.trace("CF6_TURRET_NATIVE_IMPORT_READY CF6_A01_Turret " + target);
} catch (importError) {
  FLfile.write(receipt,"CF6_TURRET_NATIVE_IMPORT_ERROR\n"+String(importError)+"\n","append");
  throw importError;
} finally {
  if (doc) fl.closeDocument(doc, false);
}
})();
