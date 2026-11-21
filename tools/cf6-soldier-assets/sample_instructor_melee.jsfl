// The Python entry point substitutes local scratch URIs for these two tokens.
(function () {
    var projectURI = __PROJECT_URI__;
    var resultURI = __RESULT_URI__;
    var doc = null;
    var base = "Codex2/特种兵/";
    var actions = ["匕首刺击", "持盾匕首刺击"];

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
        return [parent.a*m.a+parent.c*m.b, parent.b*m.a+parent.d*m.b,
                parent.a*m.c+parent.c*m.d, parent.b*m.c+parent.d*m.d,
                parent.a*m.tx+parent.c*m.ty+parent.tx, parent.b*m.tx+parent.d*m.ty+parent.ty];
    }
    // JSFL hosts do not all supply a JSON global.
    function json(v) {
        if (v === null) return "null";
        if (typeof v === "number" || typeof v === "boolean") return String(v);
        if (typeof v === "string") return '"' + v.replace(/\\/g,"\\\\").replace(/"/g,'\\"')
            .replace(/\n/g,"\\n").replace(/\r/g,"\\r").replace(/\t/g,"\\t") + '"';
        var items = [], k;
        if (v instanceof Array) {
            for (k = 0; k < v.length; k++) items.push(json(v[k]));
            return "[" + items.join(",") + "]";
        }
        for (k in v) if (v.hasOwnProperty(k)) items.push(json(k) + ":" + json(v[k]));
        return "{" + items.join(",") + "}";
    }
    function sampleAction(name) {
        if (!doc.library.editItem(base + "动作/" + name)) throw Error("Missing action " + name);
        var timeline = doc.getTimeline(), total = timeline.frameCount, names = {}, poses = [], marks = [];
        var i, f, e, layer;
        for (i = 0; i < timeline.layers.length; i++) {
            layer = timeline.layers[i];
            names[String(timeline.layers.length - i)] = layer.name;
            layer.locked = false;
            if (layer.layerType === "folder") continue;
            timeline.setSelectedLayers(i, true);
            timeline.convertToKeyframes(0, total);
        }
        for (f = 0; f < total; f++) {
            timeline.currentFrame = f;
            var pose = [];
            for (i = 0; i < timeline.layers.length; i++) {
                layer = timeline.layers[i];
                var frame = layer.frames[f];
                if (!frame || !frame.elements.length) continue;
                var rig = layer.getRigMatrixAtFrame(f) || {a:1,b:0,c:0,d:1,tx:0,ty:0};
                for (e = 0; e < frame.elements.length; e++) {
                    var el = frame.elements[e];
                    if (el.elementType !== "instance" || !el.libraryItem)
                        throw Error(name + " / " + layer.name + " / frame " + (f+1) + ": expected a library instance");
                    var part = el.libraryItem.name, depth = timeline.layers.length - i;
                    if (part === base + "CF7/Symbol 195") {
                        marks.push({frame:f+1, matrix:world(rig, el.matrix)});
                        continue;
                    }
                    var id;
                    if (part === base + "武器/可配置长枪") id = 492;
                    else if (part.indexOf(base + "分件/") === 0 && /^\d+$/.test(part.split("/").pop()))
                        id = Number(part.split("/").pop());
                    else throw Error(name + " / " + layer.name + ": unmapped library symbol " + part);
                    if (pose.length && pose[pose.length-1][0] === depth)
                        throw Error(name + " / " + layer.name + ": put each body part on a separate layer");
                    pose.push([depth,id,world(rig,el.matrix),colors(el,"Percent",100),colors(el,"Amount",0)]);
                }
            }
            poses.push(pose);
        }
        return {layers:names, poses:poses, hitMarkers:marks};
    }
    try {
        doc = fl.openDocument(projectURI);
        if (!doc) throw Error("Animate could not open the scratch XFL");
        var result = {animate:fl.version, frameRate:doc.frameRate, actions:{}};
        for (var i=0; i<actions.length; i++) result.actions[actions[i]] = sampleAction(actions[i]);
        fl.closeDocument(doc, false);
        doc = null;
        FLfile.write(resultURI, json(result));
    } catch (error) {
        if (doc) fl.closeDocument(doc, false);
        FLfile.write(resultURI,json({error:String(error), line:error.lineNumber || 0}));
    }
}());
