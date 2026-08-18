/**
 * DollBake — 常驻后台纸娃娃胸像烘焙模块（loot feed 击杀播报头像的运行时来源）。
 *
 * 链路：C# DollPortraitBakeService 经 TryPostToWeb 发来
 *   { type:'dollBake', requestId, key:'纸娃娃-<hex>', tuple:{face,hair,mask,head,body,leg,hand,foot,neck,gender} }
 * 本模块按需 LazyLoader 注入 dressup 渲染闭包（boot 不背 renderer 体积），
 * 复用 MercPortraits 的 merc 归一化 + 胸像裁剪渲染 256×256 → PNG dataURL，
 * 再经 Web→C# task 桥回传：
 *   Bridge.task('doll_bake_result', { key, requestId, pngBase64 })
 * 失败一律回传 { key, requestId, error } 并 console.error，绝不抛出
 * （C# 侧 DollBakeTask 校验落盘；超时/失败由 DollPortraitBakeService 静默降级）。
 *
 * C# 单点算键与单飞去重；本模块不重算键、不去重，只做"渲染+回传"。
 */
var DollBake = (function() {
    'use strict';

    var TASK_RESULT = 'doll_bake_result';
    var RENDER_SIZE = 256;
    // 注入顺序对齐 team/arena harness：renderer → merc-data（槽位常量）→ portrait 归一化层
    var SCRIPTS = [
        'modules/dressup-doll-renderer.js',
        'modules/merc-data.js',
        'modules/merc-portrait-renderer.js'
    ];
    var DATA_URL_PREFIX = 'data:image/png;base64,';
    // tuple 白名单字段（与 C# DollPortraitKey.Fields 同序；mask 只进键不进渲染，
    // 面具视觉由头部装备条目在 dressup manifest 中贡献，与 AS2 DressupInitializer 同源）
    var TUPLE_FIELDS = ['face', 'hair', 'mask', 'head', 'body', 'leg', 'hand', 'foot', 'neck', 'gender'];
    var EQUIPMENT_SLOTS = ['head', 'body', 'hand', 'leg', 'foot', 'neck'];

    var _scriptsPromise = null;

    function ensureRenderers() {
        if (_scriptsPromise) return _scriptsPromise;
        if (typeof LazyLoader === 'undefined' || !LazyLoader) {
            return Promise.reject(new Error('LazyLoader is not loaded'));
        }
        _scriptsPromise = LazyLoader.load(SCRIPTS).catch(function(error) {
            _scriptsPromise = null; // 允许下次请求重试
            throw error;
        });
        return _scriptsPromise;
    }

    function normalizeTuple(tuple) {
        var result = {};
        for (var i = 0; i < TUPLE_FIELDS.length; i++) {
            var field = TUPLE_FIELDS[i];
            var value = tuple ? tuple[field] : null;
            result[field] = value === undefined || value === null ? '' : String(value);
        }
        return result;
    }

    /** tuple → MercPortraits 归一化输入（merc.face/hair/gender + equipment 槽位字典）。 */
    function mercFromTuple(tuple) {
        var t = normalizeTuple(tuple);
        var merc = { face: t.face, hair: t.hair, gender: t.gender, equipment: {} };
        for (var i = 0; i < EQUIPMENT_SLOTS.length; i++) {
            var slot = EQUIPMENT_SLOTS[i];
            if (t[slot]) merc.equipment[slot] = t[slot];
        }
        return merc;
    }

    function sendResult(key, requestId, payload) {
        payload = payload || {};
        payload.key = key;
        payload.requestId = requestId;
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.task !== 'function') return false;
        Bridge.task(TASK_RESULT, payload);
        return true;
    }

    function handleMessage(message) {
        if (!message || typeof message.key !== 'string' || message.key.indexOf('纸娃娃-') !== 0) {
            return Promise.resolve(false);
        }
        var key = message.key;
        var requestId = message.requestId || null;
        var merc = mercFromTuple(message.tuple);
        return ensureRenderers().then(function() {
            if (typeof MercPortraits === 'undefined' || !MercPortraits
                    || typeof MercPortraits.renderDataUrl !== 'function') {
                throw new Error('MercPortraits.renderDataUrl is not available');
            }
            return MercPortraits.renderDataUrl(merc, { size: RENDER_SIZE });
        }).then(function(dataUrl) {
            var base64 = (typeof dataUrl === 'string' && dataUrl.indexOf(DATA_URL_PREFIX) === 0)
                ? dataUrl.substring(DATA_URL_PREFIX.length) : '';
            if (!base64) throw new Error('empty render for ' + key);
            sendResult(key, requestId, { pngBase64: base64 });
            return true;
        }).catch(function(error) {
            var reason = error && error.message ? error.message : String(error);
            if (typeof console !== 'undefined' && console.error) {
                console.error('[DollBake] bake failed for ' + key + ': ' + reason);
            }
            sendResult(key, requestId, { error: reason });
            return false;
        });
    }

    // 生产环境挂桥；harness（node vm / 浏览器无 webview）只取 API，不注册监听
    if (typeof Bridge !== 'undefined' && Bridge && typeof Bridge.on === 'function') {
        Bridge.on('dollBake', function(message) { handleMessage(message); });
    }

    return {
        SCRIPTS: SCRIPTS.slice(),
        RENDER_SIZE: RENDER_SIZE,
        normalizeTuple: normalizeTuple,
        mercFromTuple: mercFromTuple,
        handleMessage: handleMessage
    };
})();

if (typeof window !== 'undefined') window.DollBake = DollBake;
