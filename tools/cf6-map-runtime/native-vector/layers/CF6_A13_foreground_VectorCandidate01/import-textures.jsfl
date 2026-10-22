// Generated recipe. Run only in the root-owned CS6 session.
(function () {
function canonicalDocumentURI(value) {
  try { return encodeURI(decodeURI(value)); } catch (uriError) { return value; }
}
// Convert only our known absolute paths, never arbitrary open documents.
var target = FLfile.platformPathToURI("C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\flashswf\\backgrounds\\cf6\\CF6_A13_foreground_VectorCandidate01\\CF6_A13_foreground_VectorCandidate01.xfl");
var receipt = FLfile.platformPathToURI("C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tmp\\cf6-map-runtime\\native-import\\CF6_A13_foreground_VectorCandidate01-" + String(new Date().getTime()) + ".txt");
if (!FLfile.write(receipt, "CF6_NATIVE_IMPORT_STARTED\n" + target + "\n"))
  throw new Error("Cannot write native import receipt before creating document");
var assets = [{"path": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\CRAZYFLASHER7StandAloneStarter\\CrazyFlashNight\\tools\\cf6-map-runtime\\native-vector\\batch\\assets\\intrinsic-83614aa0c319c35d1bff6907.png", "id": "texture-0", "x": 0, "y": 0, "width": 1440, "height": 1164}];
var doc = null;
try {
if (FLfile.exists(target)) throw new Error("Refusing to overwrite existing XFL: " + target);
doc = fl.createDocument();
if (!doc) throw new Error("Native document creation failed");
doc.asVersion = 2;
doc.frameRate = 30;
doc.width = 480; doc.height = 388;
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
fl.trace("CF6_NATIVE_IMPORT_READY CF6_A13_foreground_VectorCandidate01 " + target);
} catch (importError) {
  FLfile.write(receipt,"CF6_NATIVE_IMPORT_ERROR\n"+String(importError)+"\n","append");
  throw importError;
} finally {
  // This handle is assigned only by our createDocument; never use active document.
  if (doc) fl.closeDocument(doc, false);
}
})();
