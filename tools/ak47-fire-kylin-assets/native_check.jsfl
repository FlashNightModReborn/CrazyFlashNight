(function () {
    var report = projectURI + "/tmp/ak47-fire-kylin/native-save.txt";
    var log = [];
    function normalize(uri) {
        return decodeURI(String(uri)).replace(/\\/g, "/")
            .replace(/^file:\/\/\/([a-zA-Z])\|/, "file:///$1:").toLowerCase();
    }
    try {
        var cfg = eval("(" + FLfile.read(projectURI + "/tools/ak47-fire-kylin-assets/assembly.json") + ")");
        var cycleFrames = cfg.cycleFrames;
        if (cycleFrames !== 8) throw new Error("Expected approved 8-frame eye loop");
        var doc = fl.getDocumentDOM();
        if (!doc || normalize(doc.pathURI) !== normalize(targetURI)) throw new Error("Wrong asset document");
        if (!doc.library.editItem("Codex/AK47火麒麟/眼焰循环")) throw new Error("Missing eye loop");
        var timeline = doc.getTimeline();
        if (timeline.frameCount !== cycleFrames || timeline.layers.length !== 5) throw new Error("Eye timeline mismatch");
        var checked = 0;
        for (var layerIndex = 0; layerIndex < timeline.layers.length; layerIndex++) {
            var layer = timeline.layers[layerIndex];
            for (var frameIndex = 0; frameIndex < cycleFrames; frameIndex++) {
                var frame = layer.frames[frameIndex];
                if (!frame || frame.elements.length !== 1) throw new Error("Missing eye phase");
                var element = frame.elements[0];
                if (!element.libraryItem || element.libraryItem.name !== "Codex/AK47火麒麟/分件/" + layer.name) {
                    throw new Error("Eye component mismatch");
                }
                checked++;
            }
        }
        timeline.currentFrame = 0;
        doc.exitEditMode();
        if (!doc.library.editItem("Codex/AK47火麒麟/图标眼焰")) throw new Error("Missing direct icon eye loop");
        timeline = doc.getTimeline();
        if (timeline.frameCount !== cycleFrames || timeline.layers.length !== 6) throw new Error("Icon eye timeline mismatch");
        var iconChecked = 0;
        for (var iconLayerIndex = 1; iconLayerIndex < timeline.layers.length; iconLayerIndex++) {
            var iconLayer = timeline.layers[iconLayerIndex];
            for (var iconFrameIndex = 0; iconFrameIndex < cycleFrames; iconFrameIndex++) {
                var iconFrame = iconLayer.frames[iconFrameIndex];
                if (iconFrame.elements.length !== 1 || iconFrame.elements[0].libraryItem.name !== "Codex/AK47火麒麟/分件/" + iconLayer.name) throw new Error("Icon eye component mismatch");
                iconChecked++;
            }
        }
        timeline.currentFrame = 0;
        doc.exitEditMode();
        doc.selectNone();
        if (!fl.saveDocument(doc)) throw new Error("Native XFL save failed");
        log.push("SAVED " + doc.pathURI);
        log.push("EYE_FRAMES " + cycleFrames);
        log.push("EYE_SECONDS " + cycleFrames / cfg.fps);
        log.push("EYE_LAYERS 5");
        log.push("CHECKED_PLACEMENTS " + checked);
        log.push("ICON_CHECKED_PLACEMENTS " + iconChecked);
        log.push("COMPLETE");
        FLfile.write(report, log.join("\n"));
        fl.trace(log.join("\n"));
    } catch (error) {
        log.push("ERROR " + error);
        FLfile.write(report, log.join("\n"));
        throw error;
    }
}());
