// 由 publish.ps1 在已有编译互斥锁内调用，输入由 xfl_recoil.py 从 profile 生成。
(function () {
    var cfg = __weaponAnimationProbe;
    var doc = fl.getDocumentDOM();
    var log = ["FLASH_VERSION " + fl.version], checked = 0, maxTranslationResidual = 0;
    function normalize(uri) {
        return decodeURI(String(uri)).replace(/\\/g, "/")
            .replace(/^file:\/\/\/([a-zA-Z])\|/, "file:///$1:").toLowerCase();
    }
    try {
        if (!doc || normalize(doc.pathURI) !== normalize(cfg.entryUri)) throw new Error("目标文档不符");
        if (!doc.library.editItem(cfg.symbol)) throw new Error("无法编辑动画元件 " + cfg.symbol);
        var timeline = doc.getTimeline();
        if (timeline.frameCount !== cfg.frameCount) throw new Error("原生时间轴帧数不符");
        var keys = ["a", "b", "c", "d", "tx", "ty"];
        for (var frameIndex = 0; frameIndex < cfg.frameCount; frameIndex++) {
            timeline.currentFrame = frameIndex;
            var expected = cfg.frames[frameIndex], seen = {};
            for (var layerIndex = 0; layerIndex < timeline.layers.length; layerIndex++) {
                var elements = timeline.layers[layerIndex].frames[frameIndex].elements;
                for (var elementIndex = 0; elementIndex < elements.length; elementIndex++) {
                    var element = elements[elementIndex];
                    if (element.elementType !== "instance") throw new Error("动画含意外的非实例元素");
                    var name = element.libraryItem.name;
                    if (!expected[name] || seen[name]) throw new Error("分件不符或重复 " + name);
                    seen[name] = true;
                    var matrix = element.matrix;
                    for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
                        var key = keys[keyIndex];
                        // CS6 的 JSFL 读数可能把 -94.5 暴露为 -94.499；按 SWF 可存储网格比较。
                        // 保存后的 XML 仍由 Python 严格比较，不能凭这个读数检查替代写回复核。
                        var translation = key == "tx" || key == "ty";
                        var grid = translation ? 20 : 65536;
                        if (translation) maxTranslationResidual = Math.max(maxTranslationResidual, Math.abs(matrix[key] - expected[name][key]));
                        if (!isFinite(matrix[key]) || Math.round(matrix[key] * grid) !== Math.round(expected[name][key] * grid)) {
                            throw new Error("矩阵不符 frame=" + (frameIndex + 1) + " part=" + name + " field=" + key
                                + " actual=" + matrix[key] + " expected=" + expected[name][key]);
                        }
                    }
                    checked++;
                }
            }
            for (var part in expected) if (!seen[part]) throw new Error("原生时间轴缺少分件 " + part);
        }
        timeline.currentFrame = 0;
        doc.exitEditMode();
        doc.selectNone();
        if (!fl.saveDocument(doc)) throw new Error("原生 XFL 保存失败");
        log.push("FRAMES " + cfg.frameCount);
        log.push("PART_MATRICES " + checked);
        log.push("MAX_JSFL_TRANSLATION_RESIDUAL " + maxTranslationResidual);
        log.push("SAVED " + doc.pathURI);
        log.push("COMPLETE");
        FLfile.write(cfg.reportUri, log.join("\n"));
        fl.trace(log.join("\n"));
    } catch (error) {
        log.push("ERROR " + error);
        FLfile.write(cfg.reportUri, log.join("\n"));
        throw error;
    }
}());
