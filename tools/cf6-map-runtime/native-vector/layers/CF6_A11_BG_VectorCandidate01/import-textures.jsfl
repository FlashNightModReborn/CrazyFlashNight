// Generated recipe. Run only in the root-owned CS6 session.
(function () {
function canonicalDocumentURI(value) {
  try { return encodeURI(decodeURI(value)); } catch (uriError) { return value; }
}
// Convert only our known absolute paths, never arbitrary open documents.
var target = FLfile.platformPathToURI("C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\flashswf\\backgrounds\\cf6\\CF6_A11_BG_VectorCandidate01\\CF6_A11_BG_VectorCandidate01.xfl");
var receipt = FLfile.platformPathToURI("C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tmp\\cf6-map-runtime\\native-import\\CF6_A11_BG_VectorCandidate01-" + String(new Date().getTime()) + ".txt");
if (!FLfile.write(receipt, "CF6_NATIVE_IMPORT_STARTED\n" + target + "\n"))
  throw new Error("Cannot write native import receipt before creating document");
var assets = [{"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-7306457526928ec9a3ea3e4a.png", "id": "texture-0", "x": 0, "y": 0, "width": 2400, "height": 900}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-d453200c45c400bc8c656872.png", "id": "texture-1", "x": 0, "y": 0, "width": 693, "height": 210}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-3836de63b32bea5064149496.png", "id": "texture-2", "x": 0, "y": 0, "width": 532, "height": 648}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-f3a8c21228ae0a9ab8450242.png", "id": "texture-3", "x": 0, "y": 0, "width": 189, "height": 81}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-9edb117c5bad8a9942697b57.png", "id": "texture-4", "x": 0, "y": 0, "width": 340, "height": 200}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-fdcdcdef41face8ac7bd71ba.png", "id": "texture-5", "x": 0, "y": 0, "width": 228, "height": 684}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-51b11bf2ce2d5077dbc21848.png", "id": "texture-6", "x": 0, "y": 0, "width": 52, "height": 89}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-9579f1a200075776adefc639.png", "id": "texture-7", "x": 0, "y": 0, "width": 156, "height": 267}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-21bf95049e7f77ed8869f22c.png", "id": "texture-8", "x": 0, "y": 0, "width": 472, "height": 536}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-9b9c1497bee995524be11b65.png", "id": "texture-9", "x": 0, "y": 0, "width": 68, "height": 63}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-785e044604178bfb67bed99b.png", "id": "texture-10", "x": 0, "y": 0, "width": 296, "height": 364}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-b2fb7d7f5070acd7093c768b.png", "id": "texture-11", "x": 0, "y": 0, "width": 1440, "height": 1359}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-f73320ef971862e5120db0e9.png", "id": "texture-12", "x": 0, "y": 0, "width": 114, "height": 156}, {"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-83614aa0c319c35d1bff6907.png", "id": "texture-13", "x": 0, "y": 0, "width": 1440, "height": 1164}];
var doc = null;
try {
if (FLfile.exists(target)) throw new Error("Refusing to overwrite existing XFL: " + target);
doc = fl.createDocument();
if (!doc) throw new Error("Native document creation failed");
doc.asVersion = 2;
doc.frameRate = 30;
doc.width = 1573; doc.height = 599;
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
fl.trace("CF6_NATIVE_IMPORT_READY CF6_A11_BG_VectorCandidate01 " + target);
} catch (importError) {
  FLfile.write(receipt,"CF6_NATIVE_IMPORT_ERROR\n"+String(importError)+"\n","append");
  throw importError;
} finally {
  // This handle is assigned only by our createDocument; never use active document.
  if (doc) fl.closeDocument(doc, false);
}
})();
