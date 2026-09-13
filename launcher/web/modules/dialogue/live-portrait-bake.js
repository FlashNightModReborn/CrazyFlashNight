/* 原生剧情大立绘的后台像素通道，保持战利品 256px 协议独立。 */
var LiveDialogueBake = (function () {
    'use strict';
    var scripts = [
        'modules/asset-timeline.js',
        'modules/dressup-doll-renderer.js',
        'modules/merc-data.js',
        'modules/dialogue/live-portrait.js'
    ];
    var loading = null;
    var tail = Promise.resolve();
    var queued = 0;

    function load() {
        if (!loading) loading = LazyLoader.load(scripts).catch(function (error) {
            loading = null;
            throw error;
        });
        return loading;
    }

    function valid(message) {
        return message && /^[0-9a-f]{64}$/.test(message.key || '')
            && /^[0-9a-f]{32}$/.test(message.requestId || '')
            && message.size === 768 && message.rig === 'dialogue'
            && typeof message.expression === 'string' && message.expression.length <= 80
            && typeof message.assetVersion === 'string' && message.assetVersion.length <= 128
            && message.appearance && typeof message.appearance === 'object'
            && !Array.isArray(message.appearance);
    }

    function send(message, value) {
        value.key = message.key;
        value.requestId = message.requestId;
        Bridge.task('dialogue_portrait_result', value);
    }

    function bounded(promise, milliseconds) {
        return new Promise(function (resolve, reject) {
            var timer = setTimeout(function () { reject(new Error('portrait deadline')); }, Math.max(1, milliseconds));
            promise.then(function (value) { clearTimeout(timer); resolve(value); },
                function (error) { clearTimeout(timer); reject(error); });
        });
    }

    function handleMessage(message) {
        if (!valid(message)) return Promise.resolve(false);
        if (queued >= 4) {
            send(message, { error: 'portrait queue full' });
            return Promise.resolve(false);
        }
        queued++;
        var deadline = Date.now() + 13000;
        var job = tail.then(function () {
            if (Date.now() >= deadline) {
                send(message, { error: 'portrait deadline' });
                return false;
            }
            return bounded(load().then(function () {
                return LiveDialoguePortraits.renderDataUrl(message.appearance, {
                    size: 768, width: 768, height: 768, pixelRatio: 1,
                    expression: message.expression, rig: 'dialogue',
                    // XFL 内部窗 (29.55,40.95)，肖像实例原点 (164.55,298.25)。
                    // 骨架已含作者矩阵；固定方形取景保留其坐标，不能按胸像再次放大。
                    margin: 0, fitEnvelope: {
                        minX: -135, minY: -257.3, maxX: 290.2, maxY: 167.9
                    },
                    assetVersion: message.assetVersion, animationEnabled: false
                });
            }), deadline - Date.now()).then(function (dataUrl) {
                var prefix = 'data:image/png;base64,';
                if (typeof dataUrl !== 'string' || dataUrl.indexOf(prefix) !== 0 || dataUrl.length <= prefix.length)
                    throw new Error('invalid portrait pixels');
                send(message, { pngBase64: dataUrl.slice(prefix.length) });
                return true;
            }).catch(function (error) {
                send(message, { error: String(error && error.message || error).slice(0, 240) });
                return false;
            });
        });
        tail = job.then(function () { queued--; }, function () { queued--; });
        return job;
    }

    if (typeof Bridge !== 'undefined' && Bridge && typeof Bridge.on === 'function')
        Bridge.on('dialoguePortraitBake', handleMessage);
    return { handleMessage: handleMessage, valid: valid };
})();
if (typeof window !== 'undefined') window.LiveDialogueBake = LiveDialogueBake;
