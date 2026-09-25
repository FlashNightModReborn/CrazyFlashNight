/**
 * LUT 实验室 · 桥封装（所有 web↔Host 调用与 vhost 访问只进这一个文件）
 *
 * 跨流契约（已与 Host 实现 launcher/src/Tasks/LutLabTask.cs 核对，2026-09-24）：
 * 两条独立 task 名（Bridge.task 惯例：{type:'task', task, callId, payload} → taskResult）：
 *  - Bridge.task('lutlab.grabFrame', {}) → {ok/success:true, url, width, height}
 *    （C# 抓原生回读 BGRA 编码 PNG 写 tmp/lut-lab/frames/，url 走 cf7-lutlab vhost）
 *  - Bridge.task('lutlab.bakeXml', {level:0..10, mode:'光照'|'夜视'})
 *    → {ok/success:true, size:32, rgbaBase64}（RGBA8 共 32768*4 字节，R 最快）；
 *    Host 侧 '夜视' 自动别名到 XML PresetSet '夜视仪'。
 *  失败回包 {ok:false, success:false, error:string}。
 *  - vhost：https://cf7-lutlab/ → tmp/lut-lab/（dev 面板配套，Host 无条件映射）；
 *    样品 manifest 在其 /samples/ 下。
 *
 * 信封适配集中于此：宿主回包若再漂移，只改本文件。
 * 降级策略：无 WebView2（纯浏览器/harness）→ 立即 unavailable；
 * 命令超时 / 明确失败回包 → unavailable，面板禁用对应区并给可读原因。
 */
(function() {
    'use strict';

    var VHOST_BASE = 'https://cf7-lutlab';
    var MANIFEST_GROUPS = ['generated', 'free', 'xml-regression'];
    var TASK_TIMEOUT_MS = 10000;

    function vhostBase() {
        // dev/QA 覆盖口（harness 用本地静态服务器模拟 vhost）；生产恒定 https://cf7-lutlab
        var override = typeof window !== 'undefined' && window.CF7_LUTLAB_VHOST_BASE;
        return (typeof override === 'string' && override) ? override.replace(/\/+$/, '') : VHOST_BASE;
    }

    function hasWebView() {
        return typeof Bridge !== 'undefined' && Bridge && typeof Bridge.task === 'function'
            && typeof window !== 'undefined' && !!(window.chrome && window.chrome.webview);
    }

    // 统一 task 调用：超时 / cb(null) / success:false 都归一为 reject(Error)。
    function callTask(taskName, payload) {
        return new Promise(function(resolve, reject) {
            if (!hasWebView()) {
                reject(new Error('无 WebView2 宿主（桥命令需要在游戏内面板环境运行）'));
                return;
            }
            var settled = false;
            var timer = setTimeout(function() {
                if (settled) return;
                settled = true;
                reject(new Error('桥命令超时（' + taskName + '，' + TASK_TIMEOUT_MS + 'ms 无回包；Host 侧桥命令未注册或尚未响应）'));
            }, TASK_TIMEOUT_MS);
            Bridge.task(taskName, payload || {}, function(resp) {
                if (settled) return;
                settled = true;
                clearTimeout(timer);
                if (!resp) { reject(new Error('桥传输不可用（' + taskName + ' 无回包）')); return; }
                // 信封适配：契约字段 ok；宿主通用层可能只给 success
                var ok = resp.ok === true || (resp.ok == null && resp.success === true);
                if (!ok) {
                    reject(new Error('桥命令被拒绝：' + (resp.error || resp.message || resp.reason || '未知原因')));
                    return;
                }
                resolve(resp);
            });
        });
    }

    function grabFrame() {
        return callTask('lutlab.grabFrame', {}).then(function(resp) {
            if (!resp.url || !resp.width || !resp.height) throw new Error('grabFrame 回包缺字段（需要 url/width/height）');
            return { url: resp.url, width: resp.width, height: resp.height };
        });
    }

    function bakeXml(level, mode) {
        return callTask('lutlab.bakeXml', { level: level, mode: mode }).then(function(resp) {
            if (resp.size !== 32 || typeof resp.rgbaBase64 !== 'string') {
                throw new Error('bakeXml 回包缺字段（需要 size:32 与 rgbaBase64）');
            }
            var bin = atob(resp.rgbaBase64);
            var rgba = new Uint8Array(bin.length);
            for (var i = 0; i < bin.length; i++) rgba[i] = bin.charCodeAt(i);
            if (rgba.length !== 32 * 32 * 32 * 4) {
                throw new Error('bakeXml 字节数不符：期望 131072 实际 ' + rgba.length);
            }
            return { size: 32, rgba: rgba };
        });
    }

    function decodeLevels(levels) {
        return levels.map(function(entry) {
            var bin = atob(entry.rgbaBase64);
            var rgba = new Uint8Array(bin.length);
            for (var i = 0; i < bin.length; i++) rgba[i] = bin.charCodeAt(i);
            if (rgba.length !== 32 * 32 * 32 * 4) {
                throw new Error('bakeXmlSet 字节数不符：期望 131072 实际 ' + rgba.length);
            }
            return { level: entry.level, rgba: rgba, domainMin: [0, 0, 0], domainMax: [1, 1, 1] };
        });
    }

    // v2 集合烘焙：一次返回某模式 0–9 共 10 档（lutlab.bakeXmlSet，Host 侧 WorldLutBaker）。
    function bakeXmlSet(mode) {
        return callTask('lutlab.bakeXmlSet', { mode: mode }).then(function(resp) {
            if (resp.size !== 32 || !Array.isArray(resp.levels) || resp.levels.length !== 10) {
                throw new Error('bakeXmlSet 回包缺字段（需要 size:32 与 levels[10]）');
            }
            return decodeLevels(resp.levels);
        });
    }

    function fetchJson(url) {
        return fetch(url, { cache: 'no-store' }).then(function(r) {
            if (!r.ok) throw new Error('HTTP ' + r.status);
            return r.json();
        });
    }

    // 合并三组 manifest；单组失败只记错误不拖垮整表。全部失败 → reject（走 fixture 降级）。
    function loadManifests() {
        var base = vhostBase() + '/samples';
        var errors = [];
        return Promise.all(MANIFEST_GROUPS.map(function(group) {
            return fetchJson(base + '/manifest.' + group + '.json').then(function(list) {
                if (!Array.isArray(list)) throw new Error('manifest.' + group + '.json 不是数组');
                return list.map(function(entry) {
                    return {
                        group: group,
                        name: String(entry.name || entry.file || '(未命名)'),
                        file: String(entry.file || ''),
                        source: String(entry.source || ''),
                        license: String(entry.license || ''),
                        notes: String(entry.notes || ''),
                        url: base + '/' + group + '/' + String(entry.file || '').split('/').pop()
                    };
                }).filter(function(entry) { return !!entry.file; });
            }).catch(function(e) {
                errors.push(group + ': ' + e.message);
                return [];
            });
        })).then(function(groups) {
            var entries = [];
            groups.forEach(function(g) { entries = entries.concat(g); });
            if (!entries.length) throw new Error('vhost 样品清单不可达：' + errors.join('；'));
            return { entries: entries, errors: errors, base: base };
        });
    }

    function fetchCubeText(url) {
        return fetch(url, { cache: 'no-store' }).then(function(r) {
            if (!r.ok) throw new Error('HTTP ' + r.status + '：' + url);
            return r.text();
        });
    }

    // v2 集合清单与集合文件（tmp/lut-lab/sets/）。manifest 缺失/畸形即视为无 vhost 集合
    //（vhost 无目录枚举能力，扫描推导不可行，由面板回退到 XML 集合 + fixture 退化集合）。
    function loadSetsManifest() {
        return fetchJson(vhostBase() + '/sets/manifest.sets.json').then(function(list) {
            if (!Array.isArray(list)) throw new Error('manifest.sets.json 不是数组');
            return list.filter(function(entry) {
                return entry && typeof entry.dir === 'string'
                    && Array.isArray(entry.files) && entry.files.length === 10
                    && (entry.mode === '光照' || entry.mode === '夜视');
            });
        });
    }

    function fetchSetCubeText(dir, file) {
        var segments = String(dir).split('/').map(function(seg) { return encodeURIComponent(seg); });
        return fetchCubeText(vhostBase() + '/sets/' + segments.join('/') + '/' + encodeURIComponent(file));
    }

    // 预设保存（三段式工作流③）：Host 写 tmp/lut-lab/presets/<name>/ + 原子更新 manifest.sets.json
    // + 重读字节自检。回包 levels 即自检通过的内容，面板据此把新集合挂进选择器。
    function savePreset(name, mode, preset, levels) {
        return callTask('lutlab.savePreset', {
            name: name, mode: mode, preset: preset, levels: levels
        }).then(function(resp) {
            if (!resp.dir || !Array.isArray(resp.files) || resp.files.length !== 10
                || !Array.isArray(resp.levels) || resp.levels.length !== 10
                || !resp.manifestEntry) {
                throw new Error('savePreset 回包缺字段（需要 dir/files/manifestEntry/levels[10]）');
            }
            return resp;
        });
    }

    window.CF7 = window.CF7 || {};
    window.CF7.LutLabBridge = {
        VHOST_BASE: VHOST_BASE,
        MANIFEST_GROUPS: MANIFEST_GROUPS,
        vhostBase: vhostBase,
        hasWebView: hasWebView,
        grabFrame: grabFrame,
        bakeXml: bakeXml,
        bakeXmlSet: bakeXmlSet,
        savePreset: savePreset,
        loadManifests: loadManifests,
        loadSetsManifest: loadSetsManifest,
        fetchSetCubeText: fetchSetCubeText,
        fetchCubeText: fetchCubeText
    };
})();
