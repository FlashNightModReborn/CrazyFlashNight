// cf7-animate-kit JSFL host
// =========================
// Loaded inside Adobe Animate by the CEP panel via manifest <ScriptPath>.
// This is the ONLY code that touches the live FLA document DOM. The panel calls
// the named functions through the bridge:
//
//   CSInterface.evalScript("cf7ak('scanLinkage', " + JSON.stringify(argJson) + ")", cb)
//
// where argJson is a JSON *string* (panel double-encodes; see cep-panel/bridge).
// Every function returns a JSON string { ok, data } or { ok:false, error }.
//
// Compatibility: written in ES3-style (var, no const/let) for older JSFL
// engines. Includes a minimal JSON fallback for engines without a JSON global.
// API signatures (SpriteSheetExporter, exportSpriteSheet) should be smoke-tested
// against the installed Animate version (see README) — they vary by build.

// ---- minimal JSON fallback (CS6-era JSFL may lack JSON) --------------------
if (typeof JSON === "undefined" || !JSON.stringify) {
  JSON = {
    parse: function (s) { return eval("(" + s + ")"); },
    stringify: function (v) { return cf7akStringify(v); }
  };
}
function cf7akStringify(v) {
  if (v === null || v === undefined) return "null";
  var t = typeof v;
  if (t === "number") return isFinite(v) ? String(v) : "null";
  if (t === "boolean") return v ? "true" : "false";
  if (t === "string") return cf7akQuote(v);
  if (v instanceof Array) {
    var a = [];
    for (var i = 0; i < v.length; i++) a.push(cf7akStringify(v[i]));
    return "[" + a.join(",") + "]";
  }
  var pairs = [];
  for (var k in v) {
    if (v.hasOwnProperty(k) && typeof v[k] !== "function") {
      pairs.push(cf7akQuote(k) + ":" + cf7akStringify(v[k]));
    }
  }
  return "{" + pairs.join(",") + "}";
}
function cf7akQuote(s) {
  s = String(s);
  var out = '"';
  for (var i = 0; i < s.length; i++) {
    var c = s.charAt(i);
    var code = s.charCodeAt(i);
    if (c === '"') out += '\\"';
    else if (c === "\\") out += "\\\\";
    else if (c === "\n") out += "\\n";
    else if (c === "\r") out += "\\r";
    else if (c === "\t") out += "\\t";
    else if (code < 0x20) out += "\\u" + cf7akPad(code.toString(16));
    else out += c;
  }
  return out + '"';
}
function cf7akPad(h) { while (h.length < 4) h = "0" + h; return h; }

// ---- result helpers -------------------------------------------------------
function cf7akOk(data) { return JSON.stringify({ ok: true, data: data }); }
function cf7akErr(msg) { return JSON.stringify({ ok: false, error: String(msg) }); }
function cf7akSafeName(name) { return String(name).replace(/[\\\/:*?"<>|]+/g, "_"); }

// ---- named functions ------------------------------------------------------

function cf7akPing() {
  return cf7akOk({ pong: true, flVersion: fl.version });
}

function cf7akCapabilityProbe() {
  return cf7akOk({
    flVersion: fl.version,
    hasDocument: !!fl.getDocumentDOM(),
    hasSpriteSheetExporter: (typeof SpriteSheetExporter !== "undefined"),
    hasFLfile: (typeof FLfile !== "undefined"),
    hasJSON: (typeof JSON !== "undefined")
  });
}

// Enumerate the active document's library, returning linkage info per item.
function cf7akScanLibraryLinkage() {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  var items = dom.library.items;
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var it = items[i];
    var rec = { name: it.name, itemType: it.itemType, linkageExportForAS: !!it.linkageExportForAS };
    if (it.linkageExportForAS) {
      rec.linkageIdentifier = it.linkageIdentifier || "";
      rec.linkageClassName = it.linkageClassName || "";
    }
    out.push(rec);
  }
  return cf7akOk({ count: out.length, items: out });
}

// Assign linkage from a list of { name, linkageIdentifier, exportForAS, className }.
function cf7akApplyLinkage(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  var lib = dom.library;
  var asg = (args && args.assignments) ? args.assignments : [];
  var applied = [];
  for (var i = 0; i < asg.length; i++) {
    var a = asg[i];
    if (!lib.itemExists(a.name)) { applied.push({ name: a.name, ok: false, error: "not found" }); continue; }
    lib.selectItem(a.name, true, true);
    var sel = lib.getSelectedItems();
    var it = sel[0];
    if (!it) { applied.push({ name: a.name, ok: false, error: "select failed" }); continue; }
    it.linkageExportForAS = (a.exportForAS !== false);
    if (it.linkageExportForAS) {
      it.linkageIdentifier = a.linkageIdentifier || a.name;
      if (a.className) it.linkageClassName = a.className;
    }
    applied.push({ name: a.name, ok: true, linkageIdentifier: it.linkageExportForAS ? it.linkageIdentifier : null });
  }
  return cf7akOk({ count: applied.length, applied: applied });
}

// List named frame labels of the current timeline (or a named symbol's timeline).
function cf7akListFrameLabels(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (args && args.symbolName && dom.library.itemExists(args.symbolName)) {
    dom.library.editItem(args.symbolName);
  }
  var tl = dom.getTimeline();
  var labels = [];
  var layers = tl.layers;
  for (var li = 0; li < layers.length; li++) {
    var frames = layers[li].frames;
    for (var fi = 0; fi < frames.length; fi++) {
      var fr = frames[fi];
      if (fr.startFrame === fi && fr.name && String(fr.name).length > 0) {
        labels.push({ layer: layers[li].name, index: fi, name: fr.name, labelType: fr.labelType, duration: fr.duration });
      }
    }
  }
  return cf7akOk({ timeline: tl.name, count: labels.length, labels: labels });
}

// Export the selected library symbols to PNG + atlas data via SpriteSheetExporter.
// args: { outDir, layoutFormat?, algorithm?, trim?, borderPadding?, shapePadding? }
function cf7akExportSelectedSymbols(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || !args.outDir) return cf7akErr("args.outDir required");
  if (typeof SpriteSheetExporter === "undefined") return cf7akErr("SpriteSheetExporter not available in this Animate build");
  var items = dom.library.getSelectedItems();
  if (!items || items.length === 0) return cf7akErr("no library items selected");

  var outURI = FLfile.platformPathToURI(args.outDir);
  if (!FLfile.exists(outURI)) FLfile.createFolder(outURI);

  var results = [];
  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    if (item.itemType !== "movie clip" && item.itemType !== "graphic" && item.itemType !== "button") {
      results.push({ name: item.name, ok: false, skipped: true, reason: "not a symbol (" + item.itemType + ")" });
      continue;
    }
    var base = String(args.outDir).replace(/[\\\/]+$/, "") + "/" + cf7akSafeName(item.name);
    try {
      var sse = new SpriteSheetExporter();
      sse.layoutFormat = args.layoutFormat || "JSON";
      sse.algorithm = args.algorithm || "maxRects";
      sse.allowRotate = false;
      sse.allowTrimming = (args.trim !== false);
      sse.borderPadding = (args.borderPadding != null) ? args.borderPadding : 0;
      sse.shapePadding = (args.shapePadding != null) ? args.shapePadding : 0;
      sse.addSymbol(item);
      sse.exportSpriteSheet(base, { format: "png", bitDepth: 32, backgroundColor: "#00000000" });
      results.push({ name: item.name, ok: true, png: base + ".png" });
    } catch (e) {
      results.push({ name: item.name, ok: false, error: String(e) });
    }
  }
  return cf7akOk({ outDir: args.outDir, count: results.length, results: results });
}

// Publish the active document using its (or a named) publish profile.
function cf7akPublishDoc(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  try {
    if (args && args.profile) dom.publishProfileName = args.profile;
    dom.publish();
    return cf7akOk({ published: true, doc: dom.name, profile: dom.publishProfileName });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// ---- wave 1: 醉尘仙 high-阶 host functions ---------------------------------

// Small shared helpers (var-only, ES3).
function cf7akIsSymbol(itemType) {
  return itemType === "movie clip" || itemType === "graphic" || itemType === "button";
}
function cf7akTrimDir(p) {
  return String(p).replace(/[\\\/]+$/, "");
}
function cf7akPadNum(n, width) {
  var s = String(n);
  while (s.length < width) s = "0" + s;
  return s;
}
// Ensure a platform-dir exists; returns its file:// URI.
function cf7akEnsureDir(dirPath) {
  var uri = FLfile.platformPathToURI(dirPath);
  if (!FLfile.exists(uri)) FLfile.createFolder(uri);
  return uri;
}
// Resolve a list of library items from args.names, else current selection.
// Returns { items:[...], error?:String }.
function cf7akResolveItems(dom, names, allowAll) {
  var lib = dom.library;
  var out = [];
  var i;
  if (names && names.length > 0) {
    for (i = 0; i < names.length; i++) {
      if (lib.itemExists(names[i])) {
        lib.selectItem(names[i], true, true);
        var sel = lib.getSelectedItems();
        if (sel && sel[0]) out.push(sel[0]);
        else out.push({ name: names[i], itemType: "__missing__" });
      } else {
        out.push({ name: names[i], itemType: "__missing__" });
      }
    }
    return { items: out };
  }
  var selected = lib.getSelectedItems();
  if (selected && selected.length > 0) return { items: selected };
  if (allowAll) {
    var all = lib.items;
    for (i = 0; i < all.length; i++) out.push(all[i]);
    return { items: out };
  }
  return { items: [], error: "no library items selected (and no names given)" };
}

// 1) listLibrary — enumerate every library item with type + linkage info.
function cf7akListLibrary() {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  var items = dom.library.items;
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var it = items[i];
    var rec = {
      name: it.name,
      itemType: it.itemType,
      exportForAS: !!it.linkageExportForAS,
      linkageIdentifier: (it.linkageExportForAS && it.linkageIdentifier) ? it.linkageIdentifier : ""
    };
    if (cf7akIsSymbol(it.itemType) && it.symbolType) rec.symbolType = it.symbolType;
    out.push(rec);
  }
  return cf7akOk({ count: out.length, items: out });
}

// 2) exportStagePNG — export the current stage to a single PNG.
function cf7akExportStagePNG(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || !args.outFile) return cf7akErr("args.outFile required");
  try {
    var uri = FLfile.platformPathToURI(args.outFile);
    var curOnly = (args.currentFrameOnly !== false);
    var exact = (args.exactBounds !== false);
    dom.exportPNG(uri, curOnly, exact);
    return cf7akOk({ file: args.outFile });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// 3) exportFrameSequence — export each timeline frame to a numbered PNG.
function cf7akExportFrameSequence(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || !args.outDir) return cf7akErr("args.outDir required");
  try {
    var dir = cf7akTrimDir(args.outDir);
    cf7akEnsureDir(dir);
    var prefix = (args.prefix != null) ? String(args.prefix) : "frame_";
    var tl = dom.getTimeline();
    var total = tl.frameCount;
    var from = (args.from != null) ? Number(args.from) : 0;
    var to = (args.to != null) ? Number(args.to) : (total - 1);
    if (from < 0) from = 0;
    if (to > total - 1) to = total - 1;
    var files = [];
    var savedFrame = tl.currentFrame;
    for (var f = from; f <= to; f++) {
      tl.currentFrame = f;
      var path = dir + "/" + prefix + cf7akPadNum(f, 4) + ".png";
      var uri = FLfile.platformPathToURI(path);
      dom.exportPNG(uri, true, true);
      files.push(path);
    }
    tl.currentFrame = savedFrame;
    return cf7akOk({ outDir: dir, count: files.length, files: files });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// 4) batchExportSymbols — one PNG (+data) per named/selected symbol via SpriteSheetExporter.
function cf7akBatchExportSymbols(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || !args.outDir) return cf7akErr("args.outDir required");
  if (typeof SpriteSheetExporter === "undefined") return cf7akErr("SpriteSheetExporter not available in this Animate build");
  var dir = cf7akTrimDir(args.outDir);
  cf7akEnsureDir(dir);
  var resolved = cf7akResolveItems(dom, args.names, false);
  if (resolved.error) return cf7akErr(resolved.error);
  var items = resolved.items;
  var results = [];
  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    if (item.itemType === "__missing__") {
      results.push({ name: item.name, ok: false, error: "not found" });
      continue;
    }
    if (!cf7akIsSymbol(item.itemType)) {
      results.push({ name: item.name, ok: false, error: "not a symbol (" + item.itemType + ")" });
      continue;
    }
    var base = dir + "/" + cf7akSafeName(item.name);
    try {
      var sse = new SpriteSheetExporter();
      sse.layoutFormat = args.layoutFormat || "JSON";
      sse.algorithm = args.algorithm || "maxRects";
      sse.allowRotate = false;
      sse.allowTrimming = true;
      sse.borderPadding = 0;
      sse.shapePadding = 0;
      sse.addSymbol(item);
      sse.exportSpriteSheet(base, { format: "png", bitDepth: 32, backgroundColor: "#00000000" });
      results.push({ name: item.name, ok: true, png: base + ".png" });
    } catch (e) {
      results.push({ name: item.name, ok: false, error: String(e) });
    }
  }
  return cf7akOk({ outDir: dir, count: results.length, results: results });
}

// 5) exportLibraryBitmaps — export each BitmapItem to a PNG file; skip non-bitmaps.
function cf7akExportLibraryBitmaps(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || !args.outDir) return cf7akErr("args.outDir required");
  var dir = cf7akTrimDir(args.outDir);
  cf7akEnsureDir(dir);
  var resolved = cf7akResolveItems(dom, args.names, true);
  if (resolved.error) return cf7akErr(resolved.error);
  var items = resolved.items;
  var results = [];
  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    if (item.itemType === "__missing__") {
      results.push({ name: item.name, ok: false, error: "not found" });
      continue;
    }
    if (item.itemType !== "bitmap") {
      results.push({ name: item.name, ok: false, skipped: true, reason: "not a bitmap (" + item.itemType + ")" });
      continue;
    }
    var path = dir + "/" + cf7akSafeName(item.name) + ".png";
    try {
      var uri = FLfile.platformPathToURI(path);
      var done = item.exportToFile(uri);
      if (done === false) {
        results.push({ name: item.name, ok: false, error: "exportToFile returned false" });
      } else {
        results.push({ name: item.name, ok: true, file: path });
      }
    } catch (e) {
      results.push({ name: item.name, ok: false, error: String(e) });
    }
  }
  return cf7akOk({ outDir: dir, count: results.length, results: results });
}

// 6) exportLibrarySounds — EXPERIMENTAL: try item.exportToFile per SoundItem.
// Many Animate builds do not support sound re-export; report support per item, never throw.
function cf7akExportLibrarySounds(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || !args.outDir) return cf7akErr("args.outDir required");
  var dir = cf7akTrimDir(args.outDir);
  cf7akEnsureDir(dir);
  var resolved = cf7akResolveItems(dom, args.names, true);
  if (resolved.error) return cf7akErr(resolved.error);
  var items = resolved.items;
  var results = [];
  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    if (item.itemType === "__missing__") {
      results.push({ name: item.name, ok: false, error: "not found" });
      continue;
    }
    if (item.itemType !== "sound") {
      results.push({ name: item.name, ok: false, skipped: true, reason: "not a sound (" + item.itemType + ")" });
      continue;
    }
    var path = dir + "/" + cf7akSafeName(item.name);
    try {
      if (typeof item.exportToFile !== "function") {
        results.push({ name: item.name, ok: false, skipped: true, reason: "exportToFile not supported for sounds in this build" });
        continue;
      }
      var uri = FLfile.platformPathToURI(path);
      var done = item.exportToFile(uri);
      if (done === false) {
        results.push({ name: item.name, ok: false, error: "exportToFile returned false (sound re-export likely unsupported)" });
      } else {
        results.push({ name: item.name, ok: true, file: path });
      }
    } catch (e) {
      results.push({ name: item.name, ok: false, error: String(e) });
    }
  }
  return cf7akOk({ outDir: dir, count: results.length, results: results });
}

// 7) safeSave — backup the .fla (FLfile.copy) BEFORE document.save().
function cf7akSafeSave(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  var srcURI = dom.pathURI;
  if (!srcURI) return cf7akErr("document has no path; use Save As first");
  try {
    // Derive the file name (without dir) from the pathURI.
    var lastSlash = String(srcURI).lastIndexOf("/");
    var fileName = (lastSlash >= 0) ? String(srcURI).substring(lastSlash + 1) : String(srcURI);
    var srcDirURI = (lastSlash >= 0) ? String(srcURI).substring(0, lastSlash) : "";

    var backupDirURI;
    if (args && args.backupDir) {
      backupDirURI = FLfile.platformPathToURI(cf7akTrimDir(args.backupDir));
    } else {
      backupDirURI = srcDirURI + "/cf7ak-backup";
    }
    if (!FLfile.exists(backupDirURI)) FLfile.createFolder(backupDirURI);

    // Find a non-colliding backup name: <name>.<n>.fla
    var dot = fileName.lastIndexOf(".");
    var stem = (dot >= 0) ? fileName.substring(0, dot) : fileName;
    var ext = (dot >= 0) ? fileName.substring(dot) : "";
    var n = 1;
    var backupURI = backupDirURI + "/" + stem + "." + n + ext;
    while (FLfile.exists(backupURI)) {
      n++;
      backupURI = backupDirURI + "/" + stem + "." + n + ext;
    }

    var copied = FLfile.copy(srcURI, backupURI);
    if (copied === false) return cf7akErr("backup copy failed (FLfile.copy returned false)");

    dom.save();
    return cf7akOk({ saved: true, backupFile: backupURI });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// 8) openDocument — open a .fla/.xfl by platform path.
function cf7akOpenDocument(args) {
  if (!args || !args.file) return cf7akErr("args.file required");
  try {
    var uri = FLfile.platformPathToURI(args.file);
    var doc = fl.openDocument(uri);
    if (!doc) return cf7akErr("failed to open document: " + args.file);
    return cf7akOk({ opened: true, name: doc.name });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// ---- wave 2: library / frame / filter ops ---------------------------------

// Shared: extract the leaf (last path segment) of a library item name.
function cf7akLeafName(name) {
  var s = String(name);
  var slash = s.lastIndexOf("/");
  return (slash >= 0) ? s.substring(slash + 1) : s;
}
// Shared: parent folder path of a library item name ("" if at root).
function cf7akParentPath(name) {
  var s = String(name);
  var slash = s.lastIndexOf("/");
  return (slash >= 0) ? s.substring(0, slash) : "";
}

// L1) libBatchRename — rename library items whose leaf matches find -> replace.
// args: { find, replace, useRegex?, names? }
// renameItem renames the SELECTED item to a NEW LEAF (not a full path), so we
// compute the new leaf from the item's own leaf name.
function cf7akLibBatchRename(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || args.find == null) return cf7akErr("args.find required");
  if (args.replace == null) return cf7akErr("args.replace required");
  var lib = dom.library;
  var find = String(args.find);
  var replace = String(args.replace);
  var useRegex = (args.useRegex === true);
  var re = null;
  if (useRegex) {
    try { re = new RegExp(find); } catch (eRe) { return cf7akErr("invalid regex: " + String(eRe)); }
  }

  // Build the candidate name list (full paths).
  var targets = [];
  var i;
  if (args.names && args.names.length > 0) {
    for (i = 0; i < args.names.length; i++) targets.push(String(args.names[i]));
  } else {
    var items = lib.items;
    for (i = 0; i < items.length; i++) {
      var leaf = cf7akLeafName(items[i].name);
      var hit = useRegex ? re.test(leaf) : (leaf.indexOf(find) >= 0);
      if (hit) targets.push(items[i].name);
    }
  }

  var renamed = [];
  for (i = 0; i < targets.length; i++) {
    var fullName = targets[i];
    try {
      if (!lib.itemExists(fullName)) { renamed.push({ from: fullName, to: "", ok: false, error: "not found" }); continue; }
      var oldLeaf = cf7akLeafName(fullName);
      var newLeaf;
      if (useRegex) {
        // reset regex (in case of /g semantics) then replace within the leaf only
        newLeaf = oldLeaf.replace(new RegExp(find), replace);
      } else {
        // global literal replace within the leaf
        newLeaf = oldLeaf.split(find).join(replace);
      }
      if (newLeaf === oldLeaf) { renamed.push({ from: fullName, to: fullName, ok: true, skipped: true, reason: "no change" }); continue; }
      var parent = cf7akParentPath(fullName);
      var newFull = (parent.length > 0) ? (parent + "/" + newLeaf) : newLeaf;
      lib.selectItem(fullName, true, true);
      var done = lib.renameItem(newLeaf);
      if (done === false) {
        renamed.push({ from: fullName, to: newFull, ok: false, error: "renameItem returned false (name collision?)" });
      } else {
        renamed.push({ from: fullName, to: newFull, ok: true });
      }
    } catch (e) {
      renamed.push({ from: fullName, to: "", ok: false, error: String(e) });
    }
  }
  return cf7akOk({ count: renamed.length, renamed: renamed });
}

// L2) libNewFolder — create a (possibly nested) library folder.
// args: { path }  -> { created, path }
function cf7akLibNewFolder(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || args.path == null || String(args.path).length === 0) return cf7akErr("args.path required");
  var lib = dom.library;
  var path = String(args.path);
  try {
    if (lib.itemExists(path)) return cf7akOk({ created: false, path: path, reason: "already exists" });
    var created = lib.newFolder(path);
    if (created === false) return cf7akErr("newFolder returned false");
    return cf7akOk({ created: true, path: path });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// L3) libMoveToFolder — move named (or selected) items into a folder.
// args: { folder, names? }  -> { count, moved:[{name,ok,error?}] }
function cf7akLibMoveToFolder(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || args.folder == null) return cf7akErr("args.folder required");
  var lib = dom.library;
  var folder = String(args.folder);

  // Resolve target names: explicit names, else current library selection.
  var names = [];
  var i;
  if (args.names && args.names.length > 0) {
    for (i = 0; i < args.names.length; i++) names.push(String(args.names[i]));
  } else {
    var sel = lib.getSelectedItems();
    if (!sel || sel.length === 0) return cf7akErr("no library items selected (and no names given)");
    for (i = 0; i < sel.length; i++) names.push(sel[i].name);
  }

  var moved = [];
  for (i = 0; i < names.length; i++) {
    var name = names[i];
    try {
      if (!lib.itemExists(name)) { moved.push({ name: name, ok: false, error: "not found" }); continue; }
      lib.selectItem(name, true, true);
      var done = lib.moveToFolder(folder);
      if (done === false) {
        moved.push({ name: name, ok: false, error: "moveToFolder returned false" });
      } else {
        moved.push({ name: name, ok: true });
      }
    } catch (e) {
      moved.push({ name: name, ok: false, error: String(e) });
    }
  }
  return cf7akOk({ count: moved.length, moved: moved });
}

// L4) libDeleteItems — delete named library items.
// args: { names }  -> { count, deleted:[{name,ok,error?}] }
function cf7akLibDeleteItems(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || !args.names || args.names.length === 0) return cf7akErr("args.names required (non-empty array)");
  var lib = dom.library;
  var deleted = [];
  for (var i = 0; i < args.names.length; i++) {
    var name = String(args.names[i]);
    try {
      if (!lib.itemExists(name)) { deleted.push({ name: name, ok: false, error: "not found" }); continue; }
      var done = lib.deleteItem(name);
      if (done === false) {
        deleted.push({ name: name, ok: false, error: "deleteItem returned false" });
      } else {
        deleted.push({ name: name, ok: true });
      }
    } catch (e) {
      deleted.push({ name: name, ok: false, error: String(e) });
    }
  }
  return cf7akOk({ count: deleted.length, deleted: deleted });
}

// F1) framesInsert — insert frames on the current timeline.
// args: { count?, atEnd? }  -> { ok, frameCount }
function cf7akFramesInsert(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  try {
    var tl = dom.getTimeline();
    var n = (args && args.count != null) ? Number(args.count) : 1;
    var atEnd = (args && args.atEnd === true);
    tl.insertFrames(n, atEnd);
    return cf7akOk({ ok: true, frameCount: tl.frameCount });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// F2) framesRemove — remove frames from the current selection on the timeline.
// args: { count? }  -> { ok, frameCount }
function cf7akFramesRemove(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  try {
    var tl = dom.getTimeline();
    var n = (args && args.count != null) ? Number(args.count) : 1;
    if (typeof tl.removeFrames !== "function") {
      return cf7akErr("removeFrames not supported in this build");
    }
    tl.removeFrames(n);
    return cf7akOk({ ok: true, frameCount: tl.frameCount });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// F3) framesReverse — reverse the frames in the current selection.
// args: {}  -> { ok }
function cf7akFramesReverse() {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  try {
    var tl = dom.getTimeline();
    if (typeof tl.reverseFrames !== "function") {
      return cf7akErr("reverseFrames not supported in this build");
    }
    tl.reverseFrames();
    return cf7akOk({ ok: true });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// F4) framesConvertToKeyframes — convert the current frame selection to keyframes.
// args: {}  -> { ok }
function cf7akFramesConvertToKeyframes() {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  try {
    var tl = dom.getTimeline();
    if (typeof tl.convertToKeyframes !== "function") {
      return cf7akErr("convertToKeyframes not supported in this build");
    }
    tl.convertToKeyframes();
    return cf7akOk({ ok: true });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// F5) framesClearKeyframes — clear keyframes in the current frame selection.
// args: {}  -> { ok }
function cf7akFramesClearKeyframes() {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  try {
    var tl = dom.getTimeline();
    if (typeof tl.clearKeyframes !== "function") {
      return cf7akErr("clearKeyframes not supported in this build");
    }
    tl.clearKeyframes();
    return cf7akOk({ ok: true });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// ---- filter helpers (X1/X2) -----------------------------------------------
// JSFL filter objects are plain objects with a 'name' field. Field names are
// confirmed against the Animate JSFL Filter object reference (glow/dropShadow/
// blur are the best-documented; bevel/gradientGlow defaults are best-effort).
function cf7akFilterIsFilterable(el) {
  if (!el || el.elementType !== "instance") return false;
  // movie clip / button / (symbol) instances + text fields support filters.
  if (el.instanceType === "symbol") {
    return (el.symbolType === "movie clip" || el.symbolType === "button" || el.symbolType === "graphic");
  }
  return (el.elementType === "text");
}
// Build a default filter object for the requested type (null if unsupported).
function cf7akMakeFilter(type) {
  if (type === "glow") {
    return { name: "glowFilter", blurX: 8, blurY: 8, color: "#ffffff", alpha: 1,
             strength: 1, quality: 1, inner: false, knockout: false };
  }
  if (type === "dropShadow") {
    return { name: "dropShadowFilter", blurX: 8, blurY: 8, color: "#000000", alpha: 1,
             angle: 45, distance: 5, strength: 1, quality: 1,
             inner: false, knockout: false, hideObject: false };
  }
  if (type === "blur") {
    return { name: "blurFilter", blurX: 8, blurY: 8, quality: 1 };
  }
  if (type === "bevel") {
    return { name: "bevelFilter", blurX: 8, blurY: 8, highlightColor: "#ffffff", highlightAlpha: 1,
             shadowColor: "#000000", shadowAlpha: 1, angle: 45, distance: 5,
             strength: 1, quality: 1, type: "inner", knockout: false };
  }
  if (type === "gradientGlow") {
    return { name: "gradientGlowFilter", blurX: 8, blurY: 8, angle: 45, distance: 0,
             strength: 1, quality: 1, type: "outer", knockout: false };
  }
  return null;
}
// Shallow-merge user params into a filter object (only sane scalar keys).
function cf7akMergeFilterParams(filter, params) {
  if (!params) return filter;
  for (var k in params) {
    if (params.hasOwnProperty(k) && k !== "name") filter[k] = params[k];
  }
  return filter;
}

// X1) applyFilter — append a filter to each selected filterable stage element.
// args: { type, params? }  -> { count, applied:[{name?,ok,error?}] }
function cf7akApplyFilter(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  if (!args || !args.type) return cf7akErr("args.type required");
  var type = String(args.type);
  if (type !== "glow" && type !== "dropShadow" && type !== "blur" && type !== "bevel" && type !== "gradientGlow") {
    return cf7akErr("unsupported filter type: " + type);
  }
  var sel = dom.selection;
  if (!sel || sel.length === 0) return cf7akErr("no stage selection");
  var applied = [];
  for (var i = 0; i < sel.length; i++) {
    var el = sel[i];
    var nm = (el && el.name) ? el.name : null;
    try {
      if (!cf7akFilterIsFilterable(el)) {
        applied.push({ name: nm, ok: false, skipped: true, reason: "element does not support filters" });
        continue;
      }
      var base = cf7akMakeFilter(type);
      if (!base) { applied.push({ name: nm, ok: false, error: "unsupported filter type: " + type }); continue; }
      cf7akMergeFilterParams(base, args.params);
      // Read current filters, append, and reassign (filters is a copy-on-read array).
      var arr = el.filters;
      if (!arr) arr = [];
      var copy = [];
      for (var j = 0; j < arr.length; j++) copy.push(arr[j]);
      copy.push(base);
      el.filters = copy;
      applied.push({ name: nm, ok: true });
    } catch (e) {
      applied.push({ name: nm, ok: false, error: String(e) });
    }
  }
  return cf7akOk({ count: applied.length, applied: applied });
}

// X2) clearFilters — remove all filters from each selected filterable element.
// args: {}  -> { count }
function cf7akClearFilters() {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  var sel = dom.selection;
  if (!sel || sel.length === 0) return cf7akErr("no stage selection");
  var count = 0;
  for (var i = 0; i < sel.length; i++) {
    var el = sel[i];
    try {
      if (!cf7akFilterIsFilterable(el)) continue;
      el.filters = [];
      count++;
    } catch (e) {
      // never throw out of the function; skip this element
    }
  }
  return cf7akOk({ count: count });
}

// ---- wave 3: presets / bitmap / diagnostics -------------------------------

// ---- preset storage helpers -----------------------------------------------
// Presets are file-backed JSON at <Configuration>/Commands/cf7ak/presets.json.
// A preset is { name, fn, args }. Both the panel and the runner agree on this
// path. CRUD does NOT require an open document (presetApply may, via its fn).
function cf7akPresetsDirURI() {
  return String(fl.configURI) + "Commands/cf7ak";
}
function cf7akPresetsURI() {
  return cf7akPresetsDirURI() + "/presets.json";
}
// Read presets.json; returns an Array (empty on absent/malformed/empty file).
function cf7akReadPresets() {
  var uri = cf7akPresetsURI();
  try {
    if (typeof FLfile === "undefined" || !FLfile.exists(uri)) return [];
    var raw = FLfile.read(uri);
    if (raw == null || String(raw).length === 0) return [];
    var parsed = JSON.parse(String(raw));
    if (parsed instanceof Array) return parsed;
    // Tolerate a wrapped { presets:[...] } shape too.
    if (parsed && parsed.presets instanceof Array) return parsed.presets;
    return [];
  } catch (e) {
    return [];
  }
}
// Write the presets Array back; creates the dir if missing. Returns bool.
function cf7akWritePresets(arr) {
  if (typeof FLfile === "undefined") return false;
  var dirURI = cf7akPresetsDirURI();
  if (!FLfile.exists(dirURI)) FLfile.createFolder(dirURI);
  var ok = FLfile.write(cf7akPresetsURI(), JSON.stringify(arr instanceof Array ? arr : []));
  return (ok !== false);
}

// P1) presetSave — upsert a preset by name. args: { name, fn, args }.
function cf7akPresetSave(args) {
  if (!args || args.name == null || String(args.name).length === 0) return cf7akErr("args.name required");
  if (args.fn == null || String(args.fn).length === 0) return cf7akErr("args.fn required");
  var name = String(args.name);
  var preset = { name: name, fn: String(args.fn), args: (args.args != null) ? args.args : {} };
  try {
    var list = cf7akReadPresets();
    var found = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].name === name) { list[i] = preset; found = true; break; }
    }
    if (!found) list.push(preset);
    if (!cf7akWritePresets(list)) return cf7akErr("failed to write presets.json (FLfile.write returned false)");
    return cf7akOk({ ok: true, count: list.length, upserted: name, replaced: found });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// P2) presetList — list all presets. args: {}.
function cf7akPresetList() {
  try {
    var list = cf7akReadPresets();
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var p = list[i];
      if (!p || p.name == null) continue;
      out.push({ name: p.name, fn: (p.fn != null ? p.fn : ""), args: (p.args != null ? p.args : {}) });
    }
    return cf7akOk({ count: out.length, presets: out });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// P3) presetApply — find a preset by name and re-dispatch its fn+args.
// args: { name }  -> { applied, result }.
function cf7akPresetApply(args) {
  if (!args || args.name == null || String(args.name).length === 0) return cf7akErr("args.name required");
  var name = String(args.name);
  try {
    var list = cf7akReadPresets();
    var preset = null;
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].name === name) { preset = list[i]; break; }
    }
    if (!preset) return cf7akErr("preset not found: " + name);
    if (preset.fn == null || String(preset.fn).length === 0) return cf7akErr("preset has no fn: " + name);
    // Re-dispatch through the same dispatcher; cf7ak returns a JSON string.
    var raw = cf7ak(String(preset.fn), JSON.stringify(preset.args != null ? preset.args : {}));
    var result;
    try { result = JSON.parse(String(raw)); } catch (eParse) { result = { ok: false, error: "could not parse applied result", raw: String(raw) }; }
    return cf7akOk({ applied: name, fn: String(preset.fn), result: result });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// P4) presetDelete — remove a preset by name. args: { name }.
function cf7akPresetDelete(args) {
  if (!args || args.name == null || String(args.name).length === 0) return cf7akErr("args.name required");
  var name = String(args.name);
  try {
    var list = cf7akReadPresets();
    var kept = [];
    var deleted = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].name === name) { deleted = true; continue; }
      kept.push(list[i]);
    }
    if (deleted) {
      if (!cf7akWritePresets(kept)) return cf7akErr("failed to write presets.json (FLfile.write returned false)");
    }
    return cf7akOk({ deleted: deleted, count: kept.length });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// ---- bitmap ops (B1/B2) ---------------------------------------------------

// B1) bitmapTrace — traceBitmap on the current stage selection (a bitmap).
// args: { threshold?, minArea?, curveFit?, cornerThreshold? }  -> { ok }
function cf7akBitmapTrace(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  try {
    var sel = dom.selection;
    if (!sel || sel.length === 0) return cf7akErr("no stage selection (select a bitmap on stage)");
    // Guard: at least one selected element must be a bitmap instance.
    var hasBitmap = false;
    for (var i = 0; i < sel.length; i++) {
      var el = sel[i];
      if (el && (el.elementType === "instance" && el.instanceType === "bitmap")) { hasBitmap = true; break; }
      if (el && el.elementType === "bitmap") { hasBitmap = true; break; }
    }
    if (!hasBitmap) return cf7akErr("selection is not a bitmap (select a bitmap on stage before tracing)");
    if (typeof dom.traceBitmap !== "function") return cf7akErr("traceBitmap not supported in this build");
    var threshold = (args && args.threshold != null) ? Number(args.threshold) : 100;
    var minArea = (args && args.minArea != null) ? Number(args.minArea) : 8;
    var curveFit = (args && args.curveFit != null) ? String(args.curveFit) : "normal";
    var cornerThreshold = (args && args.cornerThreshold != null) ? String(args.cornerThreshold) : "normal";
    dom.traceBitmap(threshold, minArea, curveFit, cornerThreshold);
    return cf7akOk({ ok: true, threshold: threshold, minArea: minArea, curveFit: curveFit, cornerThreshold: cornerThreshold });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// B2) bitmapSetCompression — set compression on BitmapItems.
// args: { names?, compressionType?, quality?, allowSmoothing? }
//   -> { count, applied:[{name,ok,error?,skipped?}] }
function cf7akBitmapSetCompression(args) {
  var dom = fl.getDocumentDOM();
  if (!dom) return cf7akErr("no open document");
  var resolved = cf7akResolveItems(dom, (args && args.names) ? args.names : null, true);
  if (resolved.error) return cf7akErr(resolved.error);
  var items = resolved.items;
  var compressionType = (args && args.compressionType != null) ? String(args.compressionType) : null;
  var hasQuality = (args && args.quality != null);
  var quality = hasQuality ? Number(args.quality) : null;
  var hasSmoothing = (args && args.allowSmoothing != null);
  var allowSmoothing = hasSmoothing ? (args.allowSmoothing === true) : null;
  var applied = [];
  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    if (item.itemType === "__missing__") { applied.push({ name: item.name, ok: false, error: "not found" }); continue; }
    if (item.itemType !== "bitmap") {
      applied.push({ name: item.name, ok: false, skipped: true, error: "not a bitmap (" + item.itemType + ")" });
      continue;
    }
    try {
      if (compressionType != null) item.compressionType = compressionType;
      // 'photo' (JPEG) honors quality; 'lossless' (PNG/GIF) ignores it.
      if (hasQuality && (compressionType === "photo" || item.compressionType === "photo")) {
        // Disable "use imported JPEG quality" so our explicit quality applies.
        try { item.useImportedJPEGQuality = false; } catch (eq) { /* property may not exist on some builds */ }
        item.quality = quality;
      }
      if (hasSmoothing) item.allowSmoothing = allowSmoothing;
      applied.push({ name: item.name, ok: true, compressionType: (item.compressionType != null ? item.compressionType : null) });
    } catch (e) {
      applied.push({ name: item.name, ok: false, error: String(e) });
    }
  }
  return cf7akOk({ count: applied.length, applied: applied });
}

// ---- diagnostics (D1) -----------------------------------------------------

// D1) crashDiagnostics — read-only environment dump. args: {}.
function cf7akCrashDiagnostics() {
  try {
    var platform = "";
    try {
      if (typeof fl.getPlatform === "function") platform = String(fl.getPlatform());
      else if (fl.platform != null) platform = String(fl.platform);
    } catch (ep) { platform = ""; }

    var docs = (fl.documents && fl.documents.length != null) ? fl.documents.length : 0;
    var dom = fl.getDocumentDOM();
    var activeDoc = null;
    if (dom) {
      var sceneCount = 0;
      try { sceneCount = (dom.timelines && dom.timelines.length != null) ? dom.timelines.length : 0; } catch (es) { sceneCount = 0; }
      var libCount = 0;
      try { libCount = (dom.library && dom.library.items && dom.library.items.length != null) ? dom.library.items.length : 0; } catch (el) { libCount = 0; }
      var tlFrames = 0;
      try { var tl = dom.getTimeline(); tlFrames = (tl && tl.frameCount != null) ? tl.frameCount : 0; } catch (et) { tlFrames = 0; }
      var pathURI = null;
      try { pathURI = dom.pathURI ? String(dom.pathURI) : null; } catch (epu) { pathURI = null; }
      activeDoc = {
        name: (dom.name != null ? String(dom.name) : ""),
        pathURI: pathURI,
        sceneCount: sceneCount,
        libraryItemCount: libCount,
        timelineFrameCount: tlFrames
      };
    }

    var report = {
      flVersion: (fl.version != null ? String(fl.version) : ""),
      platform: platform,
      openDocCount: docs,
      activeDoc: activeDoc,
      configURI: (fl.configURI != null ? String(fl.configURI) : ""),
      hasSpriteSheetExporter: (typeof SpriteSheetExporter !== "undefined"),
      hasFLfile: (typeof FLfile !== "undefined")
    };
    return cf7akOk({ report: report });
  } catch (e) {
    return cf7akErr(String(e));
  }
}

// ---- dispatcher (the single entry the panel calls) ------------------------
function cf7ak(fnName, argJson) {
  try {
    var args = {};
    if (argJson && String(argJson).length > 0) args = JSON.parse(argJson);
    switch (fnName) {
      case "ping": return cf7akPing();
      case "probe": return cf7akCapabilityProbe();
      case "scanLinkage": return cf7akScanLibraryLinkage();
      case "applyLinkage": return cf7akApplyLinkage(args);
      case "listFrameLabels": return cf7akListFrameLabels(args);
      case "exportSelected": return cf7akExportSelectedSymbols(args);
      case "publish": return cf7akPublishDoc(args);
      case "listLibrary": return cf7akListLibrary();
      case "exportStagePNG": return cf7akExportStagePNG(args);
      case "exportFrameSequence": return cf7akExportFrameSequence(args);
      case "batchExportSymbols": return cf7akBatchExportSymbols(args);
      case "exportLibraryBitmaps": return cf7akExportLibraryBitmaps(args);
      case "exportLibrarySounds": return cf7akExportLibrarySounds(args);
      case "safeSave": return cf7akSafeSave(args);
      case "openDocument": return cf7akOpenDocument(args);
      case "libBatchRename": return cf7akLibBatchRename(args);
      case "libNewFolder": return cf7akLibNewFolder(args);
      case "libMoveToFolder": return cf7akLibMoveToFolder(args);
      case "libDeleteItems": return cf7akLibDeleteItems(args);
      case "framesInsert": return cf7akFramesInsert(args);
      case "framesRemove": return cf7akFramesRemove(args);
      case "framesReverse": return cf7akFramesReverse();
      case "framesConvertToKeyframes": return cf7akFramesConvertToKeyframes();
      case "framesClearKeyframes": return cf7akFramesClearKeyframes();
      case "applyFilter": return cf7akApplyFilter(args);
      case "clearFilters": return cf7akClearFilters();
      case "presetSave": return cf7akPresetSave(args);
      case "presetList": return cf7akPresetList();
      case "presetApply": return cf7akPresetApply(args);
      case "presetDelete": return cf7akPresetDelete(args);
      case "bitmapTrace": return cf7akBitmapTrace(args);
      case "bitmapSetCompression": return cf7akBitmapSetCompression(args);
      case "crashDiagnostics": return cf7akCrashDiagnostics();
      default: return cf7akErr("unknown function: " + fnName);
    }
  } catch (e) {
    return cf7akErr("dispatch error: " + String(e));
  }
}
