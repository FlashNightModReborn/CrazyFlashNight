// Sample 特种兵alter.rar timelines via Adobe Animate 2024 native tween & parenting engine.
// The Python driver substitutes __PROJECT_URI__, __RESULT_URI__, and __PROGRESS_URI__ on a scratch copy.
(function () {
    if (typeof fl.showIdleMessage === "function") fl.showIdleMessage(false);
    var projectURI = __PROJECT_URI__;
    var resultURI = __RESULT_URI__;
    var progressURI = __PROGRESS_URI__;
    var doc = null;
    var base = "Codex2/特种兵/";
    var actions = ["持盾点射与装填", "长枪点射与装填"];

    function logProgress(msg) {
        if (progressURI) FLfile.write(progressURI, msg);
    }
    function numberOr(element, key, fallback) {
        return typeof element[key] === "number" ? element[key] : fallback;
    }
    function colors(element, suffix, fallback) {
        var channels = ["Red", "Green", "Blue", "Alpha"], values = [];
        for (var c = 0; c < channels.length; c++)
            values.push(numberOr(element, "color" + channels[c] + suffix, fallback));
        return values;
    }
    function world(parent, m) {
        return [
            parent.a * m.a + parent.c * m.b,
            parent.b * m.a + parent.d * m.b,
            parent.a * m.c + parent.c * m.d,
            parent.b * m.c + parent.d * m.d,
            parent.a * m.tx + parent.c * m.ty + parent.tx,
            parent.b * m.tx + parent.d * m.ty + parent.ty
        ];
    }
    function json(v) {
        if (v === null || v === undefined) return "null";
        if (typeof v === "number" || typeof v === "boolean") return String(v);
        if (typeof v === "string") {
            return '"' + v.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
                .replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t") + '"';
        }
        var items = [], k;
        if (v instanceof Array) {
            for (k = 0; k < v.length; k++) items.push(json(v[k]));
            return "[" + items.join(",") + "]";
        }
        for (k in v) {
            if (v.hasOwnProperty(k)) items.push(json(k) + ":" + json(v[k]));
        }
        return "{" + items.join(",") + "}";
    }
    function isTrackedPart(part) {
        if (part.indexOf(base + "分件/") === 0) return true;
        if (part === base + "武器/可配置长枪") return true;
        if (part === "Codex/教官/精英/武器/教官_可配置副手枪") return true;
        if (part === "smoke17" || part === "速度线") return true;
        return false;
    }
    function layerHasTweenOrElements(layer) {
        for (var f = 0; f < layer.frames.length; f++) {
            var fr = layer.frames[f];
            if (!fr || fr.startFrame !== f) continue;
            if (fr.tweenType && fr.tweenType !== "none") return true;
            for (var e = 0; e < fr.elements.length; e++) {
                var el = fr.elements[e];
                if (el.elementType === "instance" && el.libraryItem && isTrackedPart(el.libraryItem.name)) {
                    return true;
                }
            }
        }
        return false;
    }
    function sampleAction(name) {
        if (!doc.library.editItem(base + "动作/" + name)) throw Error("Missing action " + name);
        var tl = doc.getTimeline();
        var total = tl.frameCount;
        var layerNames = [];
        var labels = [];
        var origEnd = [];
        var i, f, e, layer;
        for (i = 0; i < tl.layers.length; i++) {
            layer = tl.layers[i];
            layerNames.push(layer.name);
            origEnd.push(layer.frameCount);
            for (f = 0; f < layer.frames.length; f++) {
                var fr = layer.frames[f];
                if (fr && fr.startFrame === f && fr.name) {
                    labels.push({frame: f + 1, layer: layer.name, name: fr.name});
                }
            }
            layer.locked = false;
            if (layer.layerType === "folder") continue;
            if (!layerHasTweenOrElements(layer)) continue;
            var convEnd = origEnd[i];
            if (convEnd <= 0) continue;
            logProgress("conv:" + name + " L" + i + "/" + tl.layers.length + " " + layer.name);
            tl.setSelectedLayers(i, true);
            tl.convertToKeyframes(0, convEnd);
        }
        logProgress("sampling:" + name + " frames=" + total);
        var poses = [];
        for (f = 0; f < total; f++) {
            tl.currentFrame = f;
            var pose = [];
            for (i = 0; i < tl.layers.length; i++) {
                if (f >= origEnd[i]) continue;
                layer = tl.layers[i];
                var frame = layer.frames[f];
                if (!frame || !frame.elements.length) continue;
                var rig = layer.getRigMatrixAtFrame(f) || {a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0};
                for (e = 0; e < frame.elements.length; e++) {
                    var el = frame.elements[e];
                    if (el.elementType !== "instance" || !el.libraryItem) continue;
                    var part = el.libraryItem.name;
                    if (!isTrackedPart(part)) continue;
                    pose.push({
                        depth: tl.layers.length - i,
                        layerIndex: i,
                        layer: layer.name,
                        part: part,
                        matrix: world(rig, el.matrix),
                        firstFrame: numberOr(el, "firstFrame", 0),
                        loop: el.loop || "",
                        colorMult: colors(el, "Percent", 100),
                        colorAdd: colors(el, "Amount", 0)
                    });
                }
            }
            poses.push(pose);
            if ((f % 40) === 0) logProgress("pose:" + name + " " + (f + 1) + "/" + total);
        }
        return {frameCount: total, layers: layerNames, labels: labels, poses: poses};
    }
    try {
        doc = fl.openDocument(projectURI);
        if (!doc) throw Error("Animate could not open scratch XFL");
        var result = {animate: fl.version, frameRate: doc.frameRate, actions: {}};
        for (var ai = 0; ai < actions.length; ai++) {
            result.actions[actions[ai]] = sampleAction(actions[ai]);
        }
        fl.closeDocument(doc, false);
        doc = null;
        logProgress("writing_result");
        FLfile.write(resultURI, json(result));
        logProgress("done");
    } catch (error) {
        if (doc) fl.closeDocument(doc, false);
        FLfile.write(resultURI, json({error: String(error), line: error.lineNumber || 0}));
    }
}());
