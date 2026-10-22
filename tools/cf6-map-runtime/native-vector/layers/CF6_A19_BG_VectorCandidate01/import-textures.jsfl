// Generated recipe. Run only in the root-owned CS6 session.
(function () {
function canonicalDocumentURI(value) {
  try { return encodeURI(decodeURI(value)); } catch (uriError) { return value; }
}
// Convert only our known absolute paths, never arbitrary open documents.
var target = FLfile.platformPathToURI("C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\flashswf\\backgrounds\\cf6\\CF6_A19_BG_VectorCandidate01\\CF6_A19_BG_VectorCandidate01.xfl");
var receipt = FLfile.platformPathToURI("C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tmp\\cf6-map-runtime\\native-import\\CF6_A19_BG_VectorCandidate01-" + String(new Date().getTime()) + ".txt");
if (!FLfile.write(receipt, "CF6_NATIVE_IMPORT_STARTED\n" + target + "\n"))
  throw new Error("Cannot write native import receipt before creating document");
var assets = [{"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-96c44bc08121cad6ebb3861f.png", "id": "texture-0", "x": 0, "y": 0, "width": 1928, "height": 664}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-c015876b695754db68bb11b9.png", "id": "texture-1", "x": 0, "y": 0, "width": 256, "height": 664}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-25c98ecabc10ce7141c2780d.png", "id": "texture-2", "x": 0, "y": 0, "width": 96, "height": 484}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-7be9af367109c0913fbfa112.png", "id": "texture-3", "x": 0, "y": 0, "width": 828, "height": 512}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-3836de63b32bea5064149496.png", "id": "texture-4", "x": 0, "y": 0, "width": 532, "height": 648}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-84a06159f67e42f946b9c8a9.png", "id": "texture-5", "x": 0, "y": 0, "width": 192, "height": 120}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-47b5d7e8fa3ea02bf4a50a08.png", "id": "texture-6", "x": 0, "y": 0, "width": 152, "height": 128}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-c46c43e5011a1acbe0176f7b.png", "id": "texture-7", "x": 0, "y": 0, "width": 164, "height": 104}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-b0cd38be1e80051ec5eac717.png", "id": "texture-8", "x": 0, "y": 0, "width": 124, "height": 108}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-f3a8c21228ae0a9ab8450242.png", "id": "texture-9", "x": 0, "y": 0, "width": 189, "height": 81}];
var doc = null;
try {
if (FLfile.exists(target)) throw new Error("Refusing to overwrite existing XFL: " + target);
doc = fl.createDocument();
if (!doc) throw new Error("Native document creation failed");
doc.asVersion = 2;
doc.frameRate = 30;
doc.width = 1627; doc.height = 529;
var timeline = doc.getTimeline();
for (var i=0; i<assets.length; i++) {
  var a=assets[i];
  if (i>0) timeline.addNewLayer(a.id, "normal", true);
  timeline.layers[timeline.currentLayer].name=a.id;
  var sourceURI=FLfile.platformPathToURI(a.path);
  if (!FLfile.exists(sourceURI)) throw new Error("Missing PNG: " + a.path);
  doc.importFile(canonicalDocumentURI(sourceURI), false);
  if (doc.selection.length !== 1) throw new Error("Expected one PNG instance: " + a.id);
  var item=doc.selection[0];
  item.libraryItem.compressionType="lossless";
  item.libraryItem.useImportedJPEGData=false;
  item.libraryItem.allowSmoothing=true;
  item.width=a.width; item.height=a.height; item.x=a.x; item.y=a.y;
  doc.selectNone();
}
timeline.addNewLayer("stop", "normal", true);
timeline.layers[timeline.currentLayer].frames[0].actionScript="stop();";
if (!fl.saveDocument(doc,canonicalDocumentURI(target))) throw new Error("XFL save failed");
if (!FLfile.write(receipt,"CF6_NATIVE_IMPORT_SAVED\n"+target+"\n","append"))
  throw new Error("Native XFL saved but receipt append failed");
fl.trace("CF6_NATIVE_IMPORT_READY CF6_A19_BG_VectorCandidate01 " + target);
} catch (importError) {
  FLfile.write(receipt,"CF6_NATIVE_IMPORT_ERROR\n"+String(importError)+"\n","append");
  throw importError;
} finally {
  // This handle is assigned only by our createDocument; never use active document.
  if (doc) fl.closeDocument(doc, false);
}
})();
