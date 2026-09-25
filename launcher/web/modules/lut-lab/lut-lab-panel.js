/**
 * LUT 实验室 v2（dev 面板）
 * ------------------------------------------------------------------
 * 核心交互：以「LUT 集合」（某模式 光照/夜视 下 0–9 整数级各一个 LUT 的有序组）为单位，
 * 对照一套光照配置在 10 个光照等级下的表现：底部等级胶片条同帧十格看 ramp 连续性，
 * 主预览 16:9 尽量大，A/B 双集合 peek（按住）/锁定/分屏/差值对照，0–10 连续滑杆
 * 相邻档双纹理 mix（生产 350ms 过渡的语义预览），昼夜扫动动画，A|B 联动检视。
 *
 * 数据来源：
 *  - XML 当前预设集合：桥命令 lutlab.bakeXmlSet {mode} → 0–9 十档 32³ RGBA8；
 *    桥不可用时降级为 vhost 预烘焙 samples/xml-regression/{光照|夜视}-N.cube。
 *  - vhost 集合：sets/manifest.sets.json + sets/<dir>/<file>（无 manifest 不可枚举目录，
 *    回退 XML 集合 + fixture 退化集合）。
 *  - 退化集合：任意单一样品/内置 fixture 作为「全等级同款」集合参与 A/B。
 *  - 抓帧：lutlab.grabFrame（无调色 BGRA → PNG → cf7-lutlab vhost）；入场帧由 Host 在
 *    LUT_LAB_TEST 分发时预抓（initData.entryFrameUrl）。面板打开期间世界捕获按生产遮挡
 *    策略挂起（合成器 Active(false)，捕获会话关闭），面板内手动抓帧只会得 no_frame。
 *
 * 渲染：WebGL2 3D 纹理硬件三线性（lut-lab-renderer.js，v2 双集合双档 + 视图模式）；
 * WebGL2 不可用 → 明确错误，不静默回退。点主预览进 A|B 联动检视（共享 pan/zoom，
 * 高倍最近邻查 banding；自写联动版，不套 workbench-inspection-viewport 单视图状态机）。
 * 所有桥/vhost 调用集中在 lut-lab-bridge.js，信封差异只在它内部适配。
 *
 * 生命周期（Panels 框架契约）：create 只在首次 open 跑一次，panel._el 跨 close 保留；
 * cleanup 复位全部会话字段 + lose GL context + 停扫动计时器，onOpen 幂等重建
 * （2026-09-24 修重开黑死：旧实现 cleanup 置 state=null，二次 open 跳过 create 直跑
 * onOpen → null 解引用 → mount 被拒且 Host 无通知 → 黑壳死按钮）。
 */
(function() {
    'use strict';

    if (typeof Panels === 'undefined') return;

    var state = null;

    function freshState() {
        return {
            root: null,
            renderer: null,
            rendererError: null,
            // 源图
            sourceCanvas: null,
            sourceLabel: '',
            // 集合模型
            sets: [],              // {id,title,mode,origin,levels[10],loaded,loading,license,notes,source}
            setAId: null,
            setBId: null,
            mode: '光照',
            level: 7,
            view: 'single',        // single | split | diff
            locked: 'A',           // 主预览/胶片条跟随的集合
            peekB: false,
            splitX: 0.5,
            sweeping: false,
            sweepTimer: null,
            sweepDir: 1,
            // 抽屉样品库
            samples: [],           // manifest 合并条目 + fixture（退化集合来源）
            drawerOpen: false,
            helpOpen: false,
            inspectOpen: false,
            inspectCam: null,      // {zoom, tx, ty}
            vhostState: 'unknown', // ok | degraded
            bridgeState: null,     // ok | unavailable | unknown
            bridgeReason: '',
            xmlSetState: 'unknown',// ok | unavailable
            filmKey: '',           // 胶片条内容指纹（集合+源图+尺寸）
            manifestErrors: [],    // 样品清单部分失败明细（QA 断言用稳定钩子）
            // 三段式预设工作流：①选择/新增预设 → ②锚点指派 + 相邻锚点自动插帧 → ③保存入集合
            preset: null,          // null | {name, mode, anchors:Array(10 of lut|null), base, rev}
            anchorPickLevel: -1,   // ≥0 时抽屉进入「为该级指派锚点」武装态
            pixelScaling: false,   // 主预览缩放显示：false=平滑 true=最近邻（320×180 测试图放大用）
            lastFrameUrl: null,    // 最近一次成功抓帧的 cf7-lutlab url（持久化到 localStorage）
            lastFrameLabel: '',    // 抓帧标签（含抓取时间戳）
            restoredSession: -1,   // 集合选择恢复完成的会话代际（QA 断言恢复时序用）
            sessionActive: false,
            session: 0,            // 会话代际：cleanup 递增，在途异步回调据此失效
            filmSeq: 0,            // 胶片条/主渲染代际
            manifestSeq: 0         // 样品/集合清单加载代际
        };
    }

    function el(tag, cls, text) {
        var node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text != null) node.textContent = text;
        return node;
    }

    // ---------- 状态徽标 / 提示 ----------

    function setBadge(id, text, tone) {
        var node = state.root.querySelector('#' + id);
        if (!node) return;
        node.textContent = text || '';
        node.setAttribute('data-tone', tone || 'muted');
    }

    function setStatus(text, tone) {
        var bar = state.root.querySelector('.lut-lab-statusbar');
        if (bar) {
            bar.textContent = text || '';
            bar.setAttribute('data-tone', tone || 'muted');
        }
    }

    // ---------- 渲染器 ----------

    function ensureRenderer() {
        if (state.renderer) return state.renderer;
        if (state.rendererError) throw state.rendererError;
        try {
            state.renderer = CF7.LutLabRenderer.create();
        } catch (e) {
            state.rendererError = e;
        }
        if (state.rendererError) {
            var stage = state.root.querySelector('.lut-lab-stage');
            if (stage) {
                stage.innerHTML = '';
                stage.appendChild(el('div', 'lut-lab-fatal',
                    'WebGL2 不可用，LUT 预览已停止：' + state.rendererError.message
                    + '。本面板不做 CPU 静默回退，请在支持 WebGL2 的环境（游戏内 WebView2 / 现代浏览器）打开。'));
            }
            state.root.setAttribute('data-webgl', 'error');
            setBadge('lut-lab-badge-webgl', 'WebGL2 ✗', 'error');
            throw state.rendererError;
        }
        // 渲染器画布直接进 DOM（主预览），CSS 负责 16:9 适配缩放
        state.renderer.canvas.classList.add('lut-lab-view-canvas');
        var host = state.root.querySelector('.lut-lab-stage');
        if (host && !state.renderer.canvas.parentNode) host.appendChild(state.renderer.canvas);
        state.root.setAttribute('data-webgl', 'ok');
        setBadge('lut-lab-badge-webgl', 'WebGL2 ✓', 'ok');
        return state.renderer;
    }

    // ---------- 工作台状态持久化（localStorage） ----------
    // 通道结论：overlay WebView2 的 userDataDir 是固定目录 launcher/webview2_overlay_userdata
    // （WebOverlayForm.cs InitWebView2Async，非临时 profile），localStorage 跨重启持久；
    // 先例：cf7.arena.custom.savedRosters.v1（arena 自定义阵容）、fontpack suppress key、
    // itemgrid mode 偏好均走 localStorage——本面板沿用同一惯例，零 C# 改动。
    // 恢复语义：打开面板时恢复全部状态；失效引用（集合/样品已删）优雅回退默认并提示；
    // 上次抓帧直接载入显示（含时间戳），即使本次入场预抓失败也有上一帧可看。

    var STATE_KEY = 'cf7.lutlab.workbench.v1';

    function storageAvailable() {
        try {
            if (typeof localStorage === 'undefined' || !localStorage) return false;
            var probe = '__lutlab_probe__';
            localStorage.setItem(probe, '1');
            localStorage.removeItem(probe);
            return true;
        } catch (e) {
            return false;
        }
    }

    function currentPresetName() {
        if (state.preset) return state.preset.name;
        var input = state.root && state.root.querySelector('#lut-lab-preset-name');
        return input ? String(input.value || '').trim() : '';
    }

    function saveState() {
        if (!storageAvailable() || !state || !state.sessionActive) return;
        try {
            localStorage.setItem(STATE_KEY, JSON.stringify({
                schemaVersion: 1,
                setAId: state.setAId,
                setBId: state.setBId,
                mode: state.mode,
                level: state.level,
                view: state.view,
                drawerOpen: state.drawerOpen,
                presetName: currentPresetName(),
                lastFrameUrl: state.lastFrameUrl || null,
                lastFrameLabel: state.lastFrameLabel || ''
            }));
        } catch (e) { /* localStorage 不可用时静默降级（无持久化） */ }
    }

    function readPersistedState() {
        if (!storageAvailable()) return null;
        try {
            var raw = localStorage.getItem(STATE_KEY);
            if (!raw) return null;
            var parsed = JSON.parse(raw);
            return parsed && parsed.schemaVersion === 1 ? parsed : null;
        } catch (e) {
            return null;
        }
    }

    // 标量字段恢复（集合选择待集合加载完成后由 restoreSetSelection 处理）
    function restoreScalarFields(persisted) {
        if (!persisted) return;
        if (persisted.mode === '光照' || persisted.mode === '夜视') state.mode = persisted.mode;
        if (typeof persisted.level === 'number' && isFinite(persisted.level)) {
            state.level = Math.max(0, Math.min(10, persisted.level));
        }
        if (persisted.view === 'single' || persisted.view === 'split' || persisted.view === 'diff') {
            state.view = persisted.view;
        }
        if (persisted.drawerOpen === true && !state.drawerOpen) toggleDrawer();
        if (typeof persisted.presetName === 'string' && persisted.presetName) {
            var input = state.root.querySelector('#lut-lab-preset-name');
            if (input) input.value = persisted.presetName;
        }
    }

    // 集合选择恢复：逐个校验引用存在性，失效则回退默认并提示（集合清单加载完成后调用）
    function restoreSetSelection(persisted) {
        state.restoredSession = state.session;
        if (!persisted) return;
        var missing = [];
        function resolveSetId(id) {
            if (findSet(id)) return id;
            // 样品退化集合是懒创建条目（'sample:<group>::<file>'）：
            // 跨关闭后从 samples 清单按 id 重建，恢复引用而非误报失效
            if (id.indexOf('sample:') === 0) {
                var rest = id.slice('sample:'.length);
                var sep = rest.indexOf('::');
                var group = rest.slice(0, sep);
                var file = rest.slice(sep + 2);
                var entry = null;
                for (var i = 0; i < state.samples.length; i++) {
                    var e = state.samples[i];
                    if (e.group === group && (e.file === file || e.name === file)) { entry = e; break; }
                }
                if (entry) return makeDegenerateSet(entry).id;
            }
            return null;
        }
        if (typeof persisted.setAId === 'string' && persisted.setAId) {
            var resolvedA = resolveSetId(persisted.setAId);
            if (resolvedA) state.setAId = resolvedA;
            else missing.push(persisted.setAId);
        }
        if (typeof persisted.setBId === 'string' && persisted.setBId) {
            var resolvedB = resolveSetId(persisted.setBId);
            if (resolvedB) state.setBId = resolvedB;
            else if (missing.indexOf(persisted.setBId) < 0) missing.push(persisted.setBId);
        }
        pickDefaultSets();
        refreshSetSelectors();
        if (missing.length) {
            setStatus('上次的集合引用已删除，已回退默认：' + missing.join('、'), 'warning');
        } else if (persisted.setAId || persisted.setBId) {
            setStatus('已恢复上次的工作台配置（集合/模式/等级/视图/抽屉）。');
        }
        var setA = currentSet('A');
        if (setA) ensureSetLoaded(setA);
        var setB = currentSet('B');
        if (setB) ensureSetLoaded(setB);
    }


    function findSet(id) {
        for (var i = 0; i < state.sets.length; i++) if (state.sets[i].id === id) return state.sets[i];
        return null;
    }

    function levelPair(set, level) {
        var t = Math.max(0, Math.min(10, level));
        var i = Math.min(9, Math.floor(t));
        var j = Math.min(9, i + 1);
        // L10 为生产外推档，集合模型 0–9：9 以上区间钉在 L9（帮助界面有注明）
        var frac = t > 9 ? 0 : t - i;
        return [set.levels[i] || null, set.levels[j] || null, frac];
    }

    function parseCubeLut(text) {
        return CF7.LutLabCube.toRgba8(text); // {rgba,domainMin,domainMax,srcSize,title}
    }

    // 集合等级文件全部就绪才算 loaded；async 完成时按 session/指纹决定是否刷新视图
    function ensureSetLoaded(set) {
        if (set.loaded) return Promise.resolve(set);
        if (set.loading) return set.loading;
        var session = state.session;
        set.loading = set.loader().then(function(levels) {
            set.loading = null;
            if (state.session !== session) return set; // 会话已关闭，丢弃
            set.levels = levels;
            set.loaded = true;
            refreshSetSelectors();
            renderAll();
            return set;
        }).catch(function(e) {
            set.loading = null;
            set.loadError = e && e.message ? e.message : String(e);
            if (state.session === session) {
                refreshSetSelectors();
                setStatus('集合「' + set.title + '」加载失败：' + set.loadError, 'error');
            }
            return set;
        });
        return set.loading;
    }

    // XML 当前预设集合：桥 bakeXmlSet → 降级 vhost samples/xml-regression/{mode}-N.cube
    function loadXmlSet(mode) {
        var id = 'xml:' + mode;
        var existing = findSet(id);
        if (existing) return existing;
        var set = {
            id: id,
            title: 'XML 当前预设 · ' + mode,
            mode: mode,
            origin: 'xml',
            levels: new Array(10).fill(null),
            loaded: false,
            loading: null,
            license: '项目内部数据派生',
            source: 'data/environment/color_engine_preset.xml',
            notes: 'lutlab.bakeXmlSet 实时烘焙；桥不可用时回退 vhost 预烘焙 xml-regression',
            loader: function() {
                return CF7.LutLabBridge.bakeXmlSet(mode).catch(function() {
                    // 桥不可用 → vhost 预烘焙文件组
                    var loads = [];
                    for (var i = 0; i <= 9; i++) {
                        loads.push(CF7.LutLabBridge.fetchCubeText(
                            CF7.LutLabBridge.vhostBase() + '/samples/xml-regression/'
                            + encodeURIComponent(mode + '-' + i + '.cube')));
                    }
                    return Promise.all(loads).then(function(texts) {
                        return texts.map(function(text, i) {
                            var lut = parseCubeLut(text);
                            return { level: i, rgba: lut.rgba, domainMin: lut.domainMin, domainMax: lut.domainMax };
                        });
                    });
                });
            }
        };
        state.sets.push(set);
        // 跟踪 XML 集合可用性（供状态栏/降级提示）；成功失败都在 ensureSetLoaded 汇总
        var session = state.session;
        set.loading = ensureSetLoaded(set);
        set.loading.then(function() {
            if (state.session !== session) return;
            state.xmlSetState = set.loaded ? 'ok' : 'unavailable';
            if (!set.loaded) {
                setStatus('XML 当前预设集合不可用（桥与 vhost 预烘焙均失败：' + (set.loadError || '未知')
                    + '），A/B 退回 fixture 退化集合。', 'warning');
                pickDefaultSets();
                refreshSetSelectors();
                renderAll();
            }
        });
        return set;
    }

    // vhost 集合清单：只登记，文件在选中时加载
    function loadVhostSets() {
        var session = state.session;
        return CF7.LutLabBridge.loadSetsManifest().then(function(list) {
            if (state.session !== session) return;
            list.forEach(function(entry) {
                if (findSet('set:' + entry.name)) return;
                state.sets.push({
                    id: 'set:' + entry.name,
                    title: entry.title || entry.name,
                    mode: entry.mode,
                    origin: 'vhost-set',
                    levels: new Array(10).fill(null),
                    loaded: false,
                    loading: null,
                    license: entry.license || '—',
                    source: entry.source || '',
                    notes: entry.notes || '',
                    loader: function() {
                        var loads = entry.files.map(function(file) {
                            return CF7.LutLabBridge.fetchSetCubeText(entry.dir, file);
                        });
                        return Promise.all(loads).then(function(texts) {
                            return texts.map(function(text, i) {
                                var lut = parseCubeLut(text);
                                return { level: i, rgba: lut.rgba, domainMin: lut.domainMin, domainMax: lut.domainMax };
                            });
                        });
                    }
                });
            });
            refreshSetSelectors();
            pickDefaultSets();
            renderAll();
        }).catch(function() { /* 无 vhost 集合属正常（manifest 缺失） */ });
    }

    // 退化集合：单 LUT ×10 全等级同款
    function makeDegenerateSet(entry) {
        var id = 'sample:' + entry.group + '::' + (entry.file || entry.name);
        var existing = findSet(id);
        if (existing) return existing;
        var set = {
            id: id,
            title: entry.name + '（全等级同款）',
            mode: 'any',
            origin: entry.group === 'fixture' ? 'fixture' : 'sample',
            levels: new Array(10).fill(null),
            loaded: false,
            loading: null,
            license: entry.license || '—',
            source: entry.source || '',
            notes: entry.notes || '',
            loader: function() {
                var textPromise = entry.cubeText != null
                    ? Promise.resolve(entry.cubeText)
                    : CF7.LutLabBridge.fetchCubeText(entry.url);
                return textPromise.then(function(text) {
                    var lut = parseCubeLut(text);
                    var levels = [];
                    for (var i = 0; i < 10; i++) {
                        levels.push({ level: i, rgba: lut.rgba, domainMin: lut.domainMin, domainMax: lut.domainMax });
                    }
                    return levels;
                });
            }
        };
        state.sets.push(set);
        return set;
    }

    // 抽屉样品库：manifest 合并（generated/free/xml-regression）+ fixtures 末尾
    function loadSamples() {
        var seq = ++state.manifestSeq;
        var session = state.session;
        return CF7.LutLabBridge.loadManifests().then(function(result) {
            if (state.session !== session || seq !== state.manifestSeq) return;
            state.samples = result.entries;
            state.manifestErrors = result.errors.slice();
            state.vhostState = 'ok';
            state.root.setAttribute('data-vhost', 'ok');
            setBadge('lut-lab-badge-vhost', 'vhost ✓', 'ok');
            appendFixtureSamples();
            renderDrawer();
            if (result.errors.length) {
                setStatus('样品清单部分失败：' + result.errors.join('；'), 'warning');
            }
        }).catch(function(e) {
            if (state.session !== session || seq !== state.manifestSeq) return;
            state.samples = [];
            state.vhostState = 'degraded';
            state.root.setAttribute('data-vhost', 'degraded');
            setBadge('lut-lab-badge-vhost', 'vhost ✗ 降级', 'warning');
            appendFixtureSamples();
            renderDrawer();
            setStatus('vhost 样品清单不可达（' + e.message + '），样品库仅剩内置 fixture。', 'warning');
        });
    }

    function appendFixtureSamples() {
        CF7.LutLabFixtures.list.forEach(function(f) {
            state.samples.push({
                group: 'fixture', name: f.name, file: '', source: f.source,
                license: f.license, notes: f.notes, cubeText: f.cubeText
            });
        });
    }

    function usableSets() {
        return state.sets.filter(function(set) {
            if (set.loadError) return false;
            if (set.mode === 'any') return true;
            return set.mode === state.mode;
        });
    }

    function pickDefaultSets() {
        var usable = usableSets();
        var a = findSet(state.setAId);
        if (!a || usable.indexOf(a) < 0) {
            var xml = findSet('xml:' + state.mode);
            state.setAId = (xml && !xml.loadError) ? xml.id : (usable[0] ? usable[0].id : null);
        }
        var b = findSet(state.setBId);
        if (!b || usable.indexOf(b) < 0 || state.setBId === state.setAId) {
            var demo = state.mode === '夜视' ? findSet('set:nightvision-green-ramp') : null;
            var fallback = null;
            for (var i = 0; i < usable.length; i++) {
                if (usable[i].id !== state.setAId) { fallback = usable[i]; break; }
            }
            var pick = (demo && usable.indexOf(demo) >= 0) ? demo : fallback;
            state.setBId = pick ? pick.id : state.setAId;
        }
    }

    // ---------- 三段式预设工作流 ----------
    // ①选择/新增预设（从XML复制 / 从集合复制 / 空白）；
    // ②对预设内特定等级指派 LUT（锚点），未指派等级在相邻锚点间线性插帧（两端之外 hold 最近锚点）；
    // ③保存：Host 写 tmp/lut-lab/presets/<name>/ + 原子更新 manifest.sets.json + 重读自检。
    // 混合语义：CPU 节点线性混合 + 8bit 量化（与预览共用同一结果 → 保存→重载与预览逐像素一致）。
    // 主预览等级滑杆的连续 mix 仍走 shader 双 LUT mix（生产 350ms 过渡语义，两者同源不同路径已注明）。

    var PRESET_EDIT_ID = 'preset:edit';

    function blendRgba(a, b, t) {
        var out = new Uint8Array(a.rgba.length);
        for (var i = 0; i < out.length; i += 4) {
            out[i] = Math.round(a.rgba[i] * (1 - t) + b.rgba[i] * t);
            out[i + 1] = Math.round(a.rgba[i + 1] * (1 - t) + b.rgba[i + 1] * t);
            out[i + 2] = Math.round(a.rgba[i + 2] * (1 - t) + b.rgba[i + 2] * t);
            out[i + 3] = 255;
        }
        return {
            rgba: out,
            domainMin: (a.domainMin || [0, 0, 0]).slice(),
            domainMax: (a.domainMax || [1, 1, 1]).slice()
        };
    }

    function identityAnchor() {
        return {
            rgba: CF7.LutLabRenderer.identityRgba8(),
            domainMin: [0, 0, 0], domainMax: [1, 1, 1],
            anchorRef: { kind: 'identity' }
        };
    }

    function computePresetLevels() {
        var anchors = state.preset.anchors;
        var levels = [];
        for (var i = 0; i < 10; i++) {
            if (anchors[i]) { levels.push(anchors[i]); continue; }
            var left = -1, right = -1;
            for (var l = i - 1; l >= 0; l--) if (anchors[l]) { left = l; break; }
            for (var r = i + 1; r < 10; r++) if (anchors[r]) { right = r; break; }
            if (left >= 0 && right >= 0) {
                var t = (i - left) / (right - left);
                levels.push(blendRgba(anchors[left], anchors[right], t));
            } else if (left >= 0) {
                levels.push(anchors[left]);          // 右端之外 hold 最近锚点
            } else if (right >= 0) {
                levels.push(anchors[right]);         // 左端之外 hold 最近锚点
            } else {
                levels.push(identityAnchor());       // 空白预设：全 identity
            }
        }
        return levels;
    }

    // 编辑中预设挂进 sets（id=preset:edit），levels = 混合结果；预览/胶片条与其他集合同管线
    function refreshPresetSet() {
        var set = findSet(PRESET_EDIT_ID);
        if (!state.preset) {
            if (set) state.sets.splice(state.sets.indexOf(set), 1);
            return;
        }
        state.preset.rev = (state.preset.rev || 0) + 1;
        var levels = computePresetLevels().map(function(lut, i) {
            return {
                level: i, rgba: lut.rgba,
                domainMin: lut.domainMin || [0, 0, 0],
                domainMax: lut.domainMax || [1, 1, 1]
            };
        });
        if (!set) {
            set = {
                id: PRESET_EDIT_ID,
                title: '预设编辑 · ' + state.preset.name,
                mode: state.preset.mode,
                origin: 'preset',
                levels: levels,
                loaded: true,
                loading: null,
                license: '项目内部生成',
                source: 'lut-lab 预设工作流',
                notes: '编辑中预设（未保存）；锚点 ' + countAnchors() + '/10'
            };
            state.sets.push(set);
        } else {
            set.levels = levels;
            set.mode = state.preset.mode;
            set.title = '预设编辑 · ' + state.preset.name;
            set.notes = '编辑中预设（未保存）；锚点 ' + countAnchors() + '/10';
            set.rev = (set.rev || 0) + 1;
        }
        refreshSetSelectors();
    }

    function countAnchors() {
        if (!state.preset) return 0;
        return state.preset.anchors.filter(function(a) { return !!a; }).length;
    }

    function startPreset(name, mode, anchors, base) {
        state.preset = { name: name, mode: mode, anchors: anchors, base: base, rev: 0 };
        refreshPresetSet();
        state.setAId = PRESET_EDIT_ID;
        state.locked = 'A';
        state.filmKey = '';
        syncPresetBar();
        renderAll();
        setStatus('预设「' + name + '」编辑中：' + base + '；锚点 ' + countAnchors() + '/10'
            + '（胶片格 [≡] 恒等锚 / [⚓] 从样品库指派 / [×] 清除）', 'ok');
        saveState();
    }

    function cloneLevelLuts(set) {
        return set.levels.map(function(l) {
            return l ? {
                rgba: l.rgba, domainMin: l.domainMin || [0, 0, 0], domainMax: l.domainMax || [1, 1, 1],
                anchorRef: { kind: 'set', set: set.id, level: l.level }
            } : null;
        });
    }

    function startPresetFromXml() {
        var xml = findSet('xml:' + state.mode);
        if (!xml || !xml.loaded) {
            setStatus('XML 当前预设集合未就绪，无法复制。', 'warning');
            return;
        }
        startPreset('xml-复制', state.mode, cloneLevelLuts(xml), '从 XML 当前预设复制');
    }

    function startPresetFromSet() {
        var set = currentSet(state.locked);
        if (!set || !set.loaded || set.id === PRESET_EDIT_ID) {
            setStatus('当前锁定集合未就绪（先选一个已加载集合再复制）。', 'warning');
            return;
        }
        startPreset(set.title.replace(/（.*）/, '') + '-复制', set.mode === 'any' ? state.mode : set.mode,
            cloneLevelLuts(set), '从集合「' + set.title + '」复制');
    }

    function startPresetBlank() {
        var anchors = new Array(10).fill(null);
        anchors[0] = identityAnchor();
        startPreset('新预设', state.mode, anchors, '空白（全 identity，L0 恒等锚点）');
    }

    function assignAnchor(level, lut, ref) {
        if (!state.preset || level < 0 || level > 9) return;
        state.preset.anchors[level] = {
            rgba: lut.rgba,
            domainMin: lut.domainMin || [0, 0, 0],
            domainMax: lut.domainMax || [1, 1, 1],
            anchorRef: ref || { kind: 'sample' }
        };
        state.anchorPickLevel = -1;
        refreshPresetSet();
        renderDrawer();
        renderAll();
        setStatus('L' + level + ' 锚点已指派；相邻等级自动插帧。', 'ok');
    }

    function clearAnchor(level) {
        if (!state.preset || !state.preset.anchors[level]) return;
        state.preset.anchors[level] = null;
        refreshPresetSet();
        renderAll();
    }

    function setIdentityAnchor(level) {
        if (!state.preset) return;
        assignAnchor(level, identityAnchor(), { kind: 'identity' });
    }

    function armAnchorPick(level) {
        if (!state.preset) return;
        state.anchorPickLevel = level;
        if (!state.drawerOpen) toggleDrawer();
        renderDrawer();
        setStatus('从样品库选一个 LUT 指派为 L' + level + ' 锚点（[⚓L' + level + ']），'
            + '或点其他格的 [⚓] 改选等级；再次点 [⚓] 取消。');
    }

    function togglePixelScaling() {
        state.pixelScaling = !state.pixelScaling;
        var canvas = state.renderer && state.renderer.canvas;
        if (canvas) canvas.classList.toggle('pixelated', state.pixelScaling);
        var btn = state.root.querySelector('#lut-lab-pixel-toggle');
        if (btn) {
            btn.textContent = state.pixelScaling ? '缩放:最近邻' : '缩放:平滑';
            btn.setAttribute('aria-pressed', state.pixelScaling ? 'true' : 'false');
        }
    }

    // 保存：校验名称 → bridge.savePreset → 回包自检内容挂进集合选择器
    function savePresetFlow() {
        if (!state.preset) { setStatus('没有编辑中的预设。', 'warning'); return; }
        var input = state.root.querySelector('#lut-lab-preset-name');
        var name = (input ? input.value : '').trim();
        if (!name) { setStatus('预设名称不能为空（单路径段，不含 / \\）。', 'error'); return; }
        if (/[/\\]/.test(name) || name === '.' || name === '..' || name.length > 64) {
            setStatus('预设名称必须是单路径段（不含 / \\，≤64 字符）。', 'error');
            return;
        }
        var saveSession = state.session;
        setStatus('保存预设「' + name + '」…');
        var presetJson = {
            schemaVersion: 1,
            name: name,
            mode: state.preset.mode,
            edgePolicy: 'hold',
            anchors: state.preset.anchors.map(function(a, i) {
                return a ? { level: i, ref: a.anchorRef || { kind: 'unknown' } } : null;
            }),
            notes: 'lut-lab 三段式预设工作流保存；锚点 ' + countAnchors() + '/10'
        };
        var levels = computePresetLevels().map(function(lut, i) {
            var bin = '';
            for (var p = 0; p < lut.rgba.length; p++) bin += String.fromCharCode(lut.rgba[p]);
            return { level: i, rgbaBase64: btoa(bin) };
        });
        CF7.LutLabBridge.savePreset(name, state.preset.mode, presetJson, levels).then(function(resp) {
            if (state.session !== saveSession) return;
            // 回包 levels 即 Host 重读自检通过的内容；据此把新集合挂进选择器
            var set = findSet('set:' + name);
            if (!set) {
                set = {
                    id: 'set:' + name,
                    title: (resp.manifestEntry && resp.manifestEntry.title) || ('预设 · ' + name),
                    mode: state.preset.mode,
                    origin: 'vhost-set',
                    levels: new Array(10).fill(null),
                    loaded: false,
                    loading: null,
                    license: '项目内部生成，随仓库',
                    source: 'lut-lab 预设工作流',
                    notes: presetJson.notes,
                    loader: function() {
                        var loads = resp.files.map(function(file) {
                            return CF7.LutLabBridge.fetchSetCubeText(resp.dir, file);
                        });
                        return Promise.all(loads).then(function(texts) {
                            return texts.map(function(text, i) {
                                var lut = parseCubeLut(text);
                                return { level: i, rgba: lut.rgba, domainMin: lut.domainMin, domainMax: lut.domainMax };
                            });
                        });
                    }
                };
                state.sets.push(set);
            }
            // 用回包字节直接装载（与预览共用同一混合结果 → 保存→重载与预览逐像素一致）
            var decoded = [];
            resp.levels.forEach(function(entry) {
                var bin = atob(entry.rgbaBase64);
                var rgba = new Uint8Array(bin.length);
                for (var i = 0; i < bin.length; i++) rgba[i] = bin.charCodeAt(i);
                decoded.push({ level: entry.level, rgba: rgba, domainMin: [0, 0, 0], domainMax: [1, 1, 1] });
            });
            set.levels = decoded;
            set.loaded = true;
            refreshSetSelectors();
            renderAll();
            saveState();
            setStatus('预设「' + name + '」已保存并进入集合选择器（' + resp.dir + '）；'
                + 'manifest.sets.json 已原子更新，重读自检通过。生产导入是后续人工步骤，本保存只写 tmp/lut-lab/。', 'ok');
        }).catch(function(e) {
            if (state.session !== saveSession) return;
            setStatus('保存失败：' + e.message, 'error');
        });
    }


    // ---------- 源图像 ----------

    function setSourceFromCanvas(canvas, label) {
        state.sourceCanvas = canvas;
        state.sourceLabel = label;
        var info = state.root.querySelector('.lut-lab-source-info');
        if (info) info.textContent = '源图：' + label + '（' + canvas.width + '×' + canvas.height + '）';
        state.filmKey = '';
        renderAll();
    }

    function makeTestImage() {
        // 暗部渐变为主 + 右侧全量程条带 + 底部纯色块，供暗部 banding 检查
        var w = 320, h = 180;
        var canvas = document.createElement('canvas');
        canvas.width = w; canvas.height = h;
        var ctx = canvas.getContext('2d');
        var img = ctx.createImageData(w, h);
        for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
            var i = (y * w + x) * 4;
            var r, g, b;
            if (x < w * 0.7) {
                var v = Math.round(x / (w * 0.7 - 1) * 72);
                r = Math.max(0, Math.min(255, v + (y % 3) - 1));
                g = v;
                b = Math.max(0, Math.min(255, v + (y % 2)));
            } else {
                var t = Math.round(y / (h - 1) * 255);
                r = t; g = t; b = t;
            }
            img.data[i] = r; img.data[i + 1] = g; img.data[i + 2] = b; img.data[i + 3] = 255;
        }
        var chips = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255], [8, 8, 8], [128, 128, 128]];
        chips.forEach(function(chip, k) {
            for (var cy = h - 16; cy < h; cy++) for (var cx = k * 24 + 4; cx < k * 24 + 24; cx++) {
                var j = (cy * w + cx) * 4;
                img.data[j] = chip[0]; img.data[j + 1] = chip[1]; img.data[j + 2] = chip[2]; img.data[j + 3] = 255;
            }
        });
        ctx.putImageData(img, 0, 0);
        return canvas;
    }

    // ---------- 入场帧（Host 在打开面板前预抓） ----------

    function formatEntryFrameTime(url) {
        var m = /frame-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})/.exec(url || '');
        if (!m) return '';
        return m[1] + '-' + m[2] + '-' + m[3] + ' ' + m[4] + ':' + m[5] + ':' + m[6];
    }

    function loadEntryFrame(url, labelPrefix) {
        var session = state.session;
        var prefix = labelPrefix || '入场抓帧';
        var img = new Image();
        img.onload = function() {
            if (state.session !== session) return;
            var w = img.naturalWidth || img.width;
            var h = img.naturalHeight || img.height;
            if (!w || !h) return;
            var canvas = document.createElement('canvas');
            canvas.width = w;
            canvas.height = h;
            canvas.getContext('2d').drawImage(img, 0, 0, w, h);
            var ts = formatEntryFrameTime(url);
            var label = prefix + (ts ? '（' + ts + ' 抓取）' : '');
            setSourceFromCanvas(canvas, label);
            // 最近一帧入库（持久化）：即使下次入场预抓失败也有上一帧可看
            state.lastFrameUrl = url;
            state.lastFrameLabel = label;
            saveState();
            setStatus('已载入' + prefix + (ts ? '（抓取于 ' + ts + '）' : '')
                + '；面板打开期间捕获挂起，需更新帧请关闭后重进。', 'ok');
        };
        img.onerror = function() {
            if (state.session !== session) return;
            setStatus('入场帧加载失败（' + url + '），已保留内置测试图。', 'warning');
        };
        img.src = url;
    }

    // ---------- 渲染 ----------

    function effectiveView() {
        if (state.view === 'single') return state.peekB ? (state.locked === 'A' ? 'B' : 'A') : state.locked;
        return state.view; // split | diff
    }

    function currentSet(side) {
        return findSet(side === 'A' ? state.setAId : state.setBId);
    }

    function renderMain() {
        if (!state || !state.sourceCanvas || !state.root) return;
        var renderer;
        try { renderer = ensureRenderer(); } catch (e) { return; }
        var setA = currentSet('A');
        var setB = currentSet('B');
        var pa = setA && setA.loaded ? levelPair(setA, state.level) : null;
        var pb = setB && setB.loaded ? levelPair(setB, state.level) : null;
        renderer.setSource(state.sourceCanvas);
        renderer.setDualLut(pa && pa[0], pa && pa[1], pb && pb[0], pb && pb[1]);
        renderer.setLevelMix(pa ? pa[2] : 0);
        renderer.setView(effectiveView(), state.splitX);
        renderer.render();
        syncLevelReadout();
        syncViewButtons();
        syncLockButton();
        syncFilmstripHighlight();
        var splitBar = state.root.querySelector('.lut-lab-split-bar');
        if (splitBar) splitBar.style.left = (state.splitX * 100) + '%';
        if (splitBar) splitBar.style.display = state.view === 'split' ? '' : 'none';
    }

    function renderAll() {
        renderMain();
        renderFilmstrip();
    }

    // ---------- 等级胶片条 ----------

    function filmFingerprint() {
        var set = currentSet(state.locked);
        return (set ? set.id + ':' + set.loaded + ':' + (set.rev || 0) : 'none')
            + '|' + (state.sourceCanvas ? state.sourceCanvas.width + 'x' + state.sourceCanvas.height + ':' + state.sourceLabel : 'nosrc');
    }

    function renderFilmstrip() {
        var strip = state.root.querySelector('.lut-lab-filmstrip');
        if (!strip) return;
        var key = filmFingerprint();
        if (key === state.filmKey) { syncFilmstripHighlight(); return; }
        state.filmKey = key;
        var seq = ++state.filmSeq;
        strip.innerHTML = '';
        var set = currentSet(state.locked);
        if (!state.sourceCanvas) return;
        if (!set || !set.loaded) {
            strip.appendChild(el('div', 'lut-lab-film-empty',
                set ? '集合「' + set.title + '」加载中…' : '无可用集合'));
            return;
        }
        var renderer;
        try { renderer = ensureRenderer(); } catch (e) { return; }
        var source = state.sourceCanvas;
        var w = source.width, h = source.height;
        for (var i = 0; i <= 9; i++) (function(level) {
            var cell = el('div', 'lut-lab-film-cell');
            cell.setAttribute('data-level', String(level));
            cell.setAttribute('role', 'button');
            cell.tabIndex = 0;
            cell.setAttribute('aria-label', '钉到等级 ' + level);
            var levelLabel = el('div', 'lut-lab-film-level', 'L' + level);
            cell.appendChild(levelLabel);
            // 预设编辑态：锚点格打标记，非锚点格标「插值」，附指派/恒等/清除按钮
            if (state.preset && set.id === PRESET_EDIT_ID) {
                var isAnchor = !!state.preset.anchors[level];
                cell.setAttribute('data-anchor', isAnchor ? 'true' : 'false');
                if (isAnchor) levelLabel.appendChild(el('span', 'lut-lab-anchor-mark', ' ⚓'));
                else levelLabel.appendChild(el('span', 'lut-lab-interp-mark', ' 插值'));
                var ops = el('span', 'lut-lab-film-ops');
                var btnIdentity = el('button', 'lut-lab-btn lut-lab-btn-mini', '≡');
                btnIdentity.type = 'button';
                btnIdentity.setAttribute('aria-label', 'L' + level + ' 设恒等锚点');
                btnIdentity.addEventListener('click', function(ev) {
                    ev.stopPropagation();
                    setIdentityAnchor(level);
                });
                ops.appendChild(btnIdentity);
                var btnPick = el('button', 'lut-lab-btn lut-lab-btn-mini', '⚓');
                btnPick.type = 'button';
                btnPick.setAttribute('aria-label', 'L' + level + ' 从样品库指派锚点');
                btnPick.addEventListener('click', function(ev) {
                    ev.stopPropagation();
                    if (state.anchorPickLevel === level) { state.anchorPickLevel = -1; renderDrawer(); }
                    else armAnchorPick(level);
                });
                ops.appendChild(btnPick);
                if (isAnchor) {
                    var btnClear = el('button', 'lut-lab-btn lut-lab-btn-mini', '×');
                    btnClear.type = 'button';
                    btnClear.setAttribute('aria-label', 'L' + level + ' 清除锚点');
                    btnClear.addEventListener('click', function(ev) {
                        ev.stopPropagation();
                        clearAnchor(level);
                    });
                    ops.appendChild(btnClear);
                }
                levelLabel.appendChild(ops);
            }
            cell.appendChild(el('div', 'lut-lab-film-canvas'));
            var holder = cell.lastChild;
            cell.addEventListener('click', function() { setLevel(level); });
            cell.addEventListener('keydown', function(ev) {
                if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); setLevel(level); }
            });
            strip.appendChild(cell);
            // 逐格整档渲染（单 LUT 路径），与主预览共用离屏渲染器
            Promise.resolve().then(function() {
                if (state.filmSeq !== seq) return;
                renderer.setSource(source);
                renderer.setLut(set.levels[level]);
                renderer.setView('A');
                renderer.render();
                var out = document.createElement('canvas');
                out.width = w; out.height = h;
                out.getContext('2d').drawImage(renderer.canvas, 0, 0);
                if (state.filmSeq !== seq) return;
                holder.innerHTML = '';
                holder.appendChild(out);
            }).catch(function() { /* 单格失败不拖垮整排 */ });
        })(i);
        syncFilmstripHighlight();
    }

    function syncFilmstripHighlight() {
        var strip = state.root.querySelector('.lut-lab-filmstrip');
        if (!strip) return;
        var current = Math.min(9, Math.floor(Math.max(0, state.level)));
        strip.querySelectorAll('.lut-lab-film-cell').forEach(function(cell) {
            var isCurrent = Number(cell.getAttribute('data-level')) === current;
            cell.classList.toggle('current', isCurrent);
            cell.setAttribute('aria-pressed', isCurrent ? 'true' : 'false');
        });
    }

    function setLevel(level) {
        state.level = Math.max(0, Math.min(10, level));
        var slider = state.root.querySelector('#lut-lab-level');
        if (slider) slider.value = String(state.level);
        renderMain();
        saveState();
    }

    // ---------- 昼夜扫动 ----------

    function toggleSweep() {
        if (state.sweeping) { stopSweep(); return; }
        state.sweeping = true;
        state.sweepDir = 1;
        syncSweepButton();
        // 约 1s/级：100ms × 0.1 步进
        state.sweepTimer = setInterval(function() {
            if (!state.sessionActive) { stopSweep(); return; }
            var next = state.level + 0.1 * state.sweepDir;
            if (next >= 10) { next = 10; state.sweepDir = -1; }
            else if (next <= 0) { next = 0; state.sweepDir = 1; }
            setLevel(Math.round(next * 10) / 10);
        }, 100);
    }

    function stopSweep() {
        state.sweeping = false;
        if (state.sweepTimer) { clearInterval(state.sweepTimer); state.sweepTimer = null; }
        syncSweepButton();
    }

    function syncSweepButton() {
        var btn = state.root.querySelector('#lut-lab-sweep');
        if (btn) {
            btn.textContent = state.sweeping ? '■ 停止扫动' : '▶ 播放昼夜扫动';
            btn.setAttribute('aria-pressed', state.sweeping ? 'true' : 'false');
        }
    }

    function syncLevelReadout() {
        var readout = state.root.querySelector('#lut-lab-level-value');
        if (readout) readout.textContent = state.level.toFixed(1);
    }

    function syncViewButtons() {
        state.root.querySelectorAll('.lut-lab-view button').forEach(function(btn) {
            btn.setAttribute('aria-pressed',
                btn.getAttribute('data-view') === state.view ? 'true' : 'false');
        });
    }

    function syncLockButton() {
        var btn = state.root.querySelector('#lut-lab-lock');
        if (btn) btn.textContent = '主显：' + state.locked + '（点击切 ' + (state.locked === 'A' ? 'B' : 'A') + '）';
    }

    function syncPresetBar() {
        var bar = state.root && state.root.querySelector('.lut-lab-preset-bar');
        if (!bar) return;
        bar.setAttribute('data-active', state.preset ? 'true' : 'false');
        var label = bar.querySelector('#lut-lab-preset-current');
        if (label) {
            label.textContent = state.preset
                ? '预设编辑：' + state.preset.name + '（锚点 ' + countAnchors() + '/10，模式 ' + state.preset.mode + '）'
                : '预设编辑：无';
        }
        var input = bar.querySelector('#lut-lab-preset-name');
        if (input && state.preset) input.value = state.preset.name;
    }

    // ---------- 集合选择器 / 模式 / 视图 ----------

    function refreshSetSelectors() {
        ['A', 'B'].forEach(function(side) {
            var select = state.root.querySelector(side === 'A' ? '#lut-lab-set-a' : '#lut-lab-set-b');
            if (!select) return;
            var currentId = side === 'A' ? state.setAId : state.setBId;
            select.innerHTML = '';
            usableSets().forEach(function(set) {
                var option = el('option', '', set.title + (set.loaded ? '' : set.loadError ? '（不可用）' : '（待加载）'));
                option.value = set.id;
                if (set.loadError) option.disabled = true;
                select.appendChild(option);
            });
            if (currentId) select.value = currentId;
        });
    }

    function onSetSelected(side, id) {
        var set = findSet(id);
        if (!set) return;
        if (side === 'A') state.setAId = id; else state.setBId = id;
        if (side === state.locked) state.filmKey = '';
        ensureSetLoaded(set);
        renderAll();
        saveState();
    }

    function setMode(mode) {
        if (state.mode === mode) return;
        state.mode = mode;
        loadXmlSet(mode);
        pickDefaultSets();
        refreshSetSelectors();
        state.filmKey = '';
        state.root.querySelectorAll('.lut-lab-mode button').forEach(function(btn) {
            btn.setAttribute('aria-pressed',
                btn.getAttribute('data-mode') === mode ? 'true' : 'false');
        });
        renderAll();
        saveState();
    }

    function setView(view) {
        state.view = view;
        state.peekB = false;
        renderMain();
        saveState();
    }

    // ---------- 抽屉样品库 ----------

    function renderDrawer() {
        var listEl = state.root.querySelector('.lut-lab-drawer-list');
        if (!listEl) return;
        listEl.innerHTML = '';
        var groups = {};
        state.samples.forEach(function(entry) {
            (groups[entry.group] = groups[entry.group] || []).push(entry);
        });
        Object.keys(groups).forEach(function(group) {
            listEl.appendChild(el('div', 'lut-lab-group-title', group + '（' + groups[group].length + '）'));
            groups[group].forEach(function(entry) {
                var row = el('div', 'lut-lab-sample');
                var name = el('span', 'lut-lab-sample-name', entry.name);
                // 许可证/备注长文本收进 tooltip 与展开详情，不再撑开侧栏
                var detail = [entry.license, entry.notes].filter(Boolean).join('\n');
                if (detail) name.title = detail;
                row.appendChild(name);
                var actions = el('span', 'lut-lab-sample-actions');
                if (state.anchorPickLevel >= 0) {
                    // 锚点指派武装态：行为 L<level> 指派锚点（取该样品的 LUT）
                    var pickLevel = state.anchorPickLevel;
                    var pickBtn = el('button', 'lut-lab-btn lut-lab-btn-mini', '⚓L' + pickLevel);
                    pickBtn.type = 'button';
                    pickBtn.setAttribute('aria-label', '把「' + entry.name + '」指派为 L' + pickLevel + ' 锚点');
                    pickBtn.addEventListener('click', function() {
                        var set = makeDegenerateSet(entry);
                        ensureSetLoaded(set).then(function(loaded) {
                            if (!loaded || !loaded.loaded || !loaded.levels[0]) {
                                setStatus('样品「' + entry.name + '」加载失败，无法指派锚点。', 'error');
                                return;
                            }
                            assignAnchor(pickLevel, loaded.levels[0],
                                { kind: 'sample', group: entry.group, file: entry.file || '', name: entry.name });
                        });
                    });
                    actions.appendChild(pickBtn);
                } else {
                    ['A', 'B'].forEach(function(side) {
                        var btn = el('button', 'lut-lab-btn lut-lab-btn-mini', '→' + side);
                        btn.type = 'button';
                        btn.setAttribute('aria-label', '作为全等级同款集合载入 ' + side + '：' + entry.name);
                        btn.addEventListener('click', function() {
                            var set = makeDegenerateSet(entry);
                            refreshSetSelectors();
                            onSetSelected(side, set.id);
                        });
                        actions.appendChild(btn);
                    });
                }
                row.appendChild(actions);
                listEl.appendChild(row);
            });
        });
    }

    function toggleDrawer() {
        state.drawerOpen = !state.drawerOpen;
        var drawer = state.root.querySelector('.lut-lab-drawer');
        if (drawer) drawer.setAttribute('data-open', state.drawerOpen ? 'true' : 'false');
        var btn = state.root.querySelector('#lut-lab-drawer-toggle');
        if (btn) {
            btn.textContent = state.drawerOpen ? '样品库 ◂' : '样品库 ▸';
            btn.setAttribute('aria-expanded', state.drawerOpen ? 'true' : 'false');
        }
        saveState();
    }

    // ---------- 帮助 ----------

    function setHelpOpen(open) {
        state.helpOpen = open;
        var overlay = state.root.querySelector('.lut-lab-help');
        if (overlay) overlay.style.display = open ? '' : 'none';
        if (open) {
            var closeBtn = overlay && overlay.querySelector('.lut-lab-overlay-close');
            if (closeBtn) closeBtn.focus();
        }
    }

    // ---------- A|B 联动检视 ----------
    // 自写联动版：两个视图共享 {zoom,tx,ty}；不套 workbench-inspection-viewport
    //（其单视图状态机不天然支持双视图联动，硬套反而更绕）。

    function renderInspectSurfaces() {
        var renderer;
        try { renderer = ensureRenderer(); } catch (e) { return null; }
        var setA = currentSet('A');
        var setB = currentSet('B');
        var pa = setA && setA.loaded ? levelPair(setA, state.level) : null;
        var pb = setB && setB.loaded ? levelPair(setB, state.level) : null;
        renderer.setSource(state.sourceCanvas);
        function bake(p0, p1) {
            renderer.setDualLut(p0, p1, null, null);
            renderer.setLevelMix(pa ? pa[2] : 0);
            renderer.setView('A');
            renderer.render();
            var out = document.createElement('canvas');
            out.width = state.sourceCanvas.width;
            out.height = state.sourceCanvas.height;
            out.getContext('2d').drawImage(renderer.canvas, 0, 0);
            return out;
        }
        return { a: bake(pa && pa[0], pa && pa[1]), b: bake(pb && pb[0], pb && pb[1]) };
    }

    function applyInspectCam() {
        var cam = state.inspectCam;
        state.root.querySelectorAll('.lut-lab-inspect-target').forEach(function(target) {
            target.style.transform = 'translate(' + cam.tx + 'px, ' + cam.ty + 'px) scale(' + cam.zoom + ')';
            target.classList.toggle('pixelated', cam.zoom > 1);
        });
        var status = state.root.querySelector('.lut-lab-inspect-status');
        if (status) status.textContent = '缩放 ' + Math.round(cam.zoom * 100) + '%（同一视角驱动 A|B）';
    }

    function openInspect() {
        if (!state.sourceCanvas || state.inspectOpen) return;
        var surfaces = renderInspectSurfaces();
        if (!surfaces) return;
        state.inspectOpen = true;
        var overlay = state.root.querySelector('.lut-lab-inspect');
        var paneA = overlay.querySelector('.lut-lab-inspect-pane[data-side="A"] .lut-lab-inspect-viewport');
        var paneB = overlay.querySelector('.lut-lab-inspect-pane[data-side="B"] .lut-lab-inspect-viewport');
        [paneA, paneB].forEach(function(pane, idx) {
            var surface = idx === 0 ? surfaces.a : surfaces.b;
            var target = pane.querySelector('.lut-lab-inspect-target');
            target.innerHTML = '';
            target.appendChild(surface);
        });
        var fit = Math.min(
            (paneA.clientWidth || 640) / state.sourceCanvas.width,
            (paneA.clientHeight || 360) / state.sourceCanvas.height);
        fit = Math.max(0.1, Math.min(4, fit));
        state.inspectCam = { zoom: fit, tx: 0, ty: 0, min: Math.min(0.25, fit), max: 32 };
        applyInspectCam();
        overlay.style.display = '';
        var vp = overlay.querySelector('.lut-lab-inspect-pane[data-side="A"] .lut-lab-inspect-viewport');
        if (vp) vp.focus();
    }

    function closeInspect() {
        if (!state.inspectOpen) return;
        state.inspectOpen = false;
        state.inspectCam = null;
        var overlay = state.root && state.root.querySelector('.lut-lab-inspect');
        if (overlay) overlay.style.display = 'none';
    }

    function wireInspect(overlay) {
        var viewports = overlay.querySelectorAll('.lut-lab-inspect-viewport');
        viewports.forEach(function(vp) {
            vp.addEventListener('wheel', function(ev) {
                if (!state.inspectCam) return;
                ev.preventDefault();
                var cam = state.inspectCam;
                var rect = vp.getBoundingClientRect();
                var mx = ev.clientX - rect.left;
                var my = ev.clientY - rect.top;
                var scale = ev.deltaY < 0 ? 1.25 : 1 / 1.25;
                var nz = Math.max(cam.min, Math.min(cam.max, cam.zoom * scale));
                // 光标锚定缩放：保持指针下的像素不动
                cam.tx = mx - (mx - cam.tx) * (nz / cam.zoom);
                cam.ty = my - (my - cam.ty) * (nz / cam.zoom);
                cam.zoom = nz;
                applyInspectCam();
            }, { passive: false });
            vp.addEventListener('mousedown', function(ev) {
                if (!state.inspectCam) return;
                ev.preventDefault();
                var cam = state.inspectCam;
                var startX = ev.clientX, startY = ev.clientY;
                var startTx = cam.tx, startTy = cam.ty;
                function move(e2) {
                    cam.tx = startTx + (e2.clientX - startX);
                    cam.ty = startTy + (e2.clientY - startY);
                    applyInspectCam();
                }
                function up() {
                    window.removeEventListener('mousemove', move, true);
                    window.removeEventListener('mouseup', up, true);
                }
                window.addEventListener('mousemove', move, true);
                window.addEventListener('mouseup', up, true);
            });
        });
        overlay.addEventListener('keydown', function(ev) {
            if (ev.key === 'Escape') { ev.stopPropagation(); closeInspect(); }
        });
        overlay.querySelector('.lut-lab-overlay-close').addEventListener('click', closeInspect);
    }

    // ---------- 键盘（peek 空格） ----------

    function isEditableTarget(target) {
        return target && (target.tagName === 'INPUT' || target.tagName === 'SELECT'
            || target.tagName === 'TEXTAREA' || target.tagName === 'BUTTON');
    }

    function onKeyDown(ev) {
        if (!state.sessionActive || state.helpOpen || state.inspectOpen) return;
        if (ev.key !== ' ' || ev.repeat || isEditableTarget(ev.target)) return;
        if (state.view !== 'single') return;
        ev.preventDefault();
        if (!state.peekB) { state.peekB = true; renderMain(); }
    }

    function onKeyUp(ev) {
        if (ev.key !== ' ' || !state.peekB) return;
        state.peekB = false;
        renderMain();
    }

    // ---------- 桥区（抓帧） ----------

    function markBridgeUnavailable(reason) {
        state.bridgeState = 'unavailable';
        state.bridgeReason = reason;
        state.root.setAttribute('data-bridge', 'unavailable');
        setBadge('lut-lab-badge-bridge', '桥 ✗', 'error');
        syncBridgeControls();
    }

    function syncBridgeControls() {
        var unavailable = state.bridgeState === 'unavailable';
        var grab = state.root.querySelector('#lut-lab-grab');
        if (grab) grab.disabled = unavailable;
        var hint = state.root.querySelector('#lut-lab-grab-hint');
        if (hint) hint.textContent = unavailable ? 'lutlab.grabFrame 不可用：' + state.bridgeReason : '';
    }

    function initBridgeState() {
        if (CF7.LutLabBridge.hasWebView()) {
            state.bridgeState = 'unknown';
            state.root.setAttribute('data-bridge', 'unknown');
            setBadge('lut-lab-badge-bridge', '桥 待验证', 'muted');
        } else {
            markBridgeUnavailable('无 WebView2 宿主（纯浏览器环境）');
        }
    }

    function wireGrab() {
        state.root.querySelector('#lut-lab-grab').addEventListener('click', function() {
            setStatus('抓取游戏画面…');
            var grabSession = state.session;
            CF7.LutLabBridge.grabFrame().then(function(frame) {
                if (state.session !== grabSession) throw new Error('会话已关闭');
                return new Promise(function(resolve, reject) {
                    var img = new Image();
                    img.onload = function() {
                        var canvas = document.createElement('canvas');
                        canvas.width = frame.width;
                        canvas.height = frame.height;
                        canvas.getContext('2d').drawImage(img, 0, 0, frame.width, frame.height);
                        resolve({ canvas: canvas, url: frame.url });
                    };
                    img.onerror = function() { reject(new Error('抓帧图加载失败：' + frame.url)); };
                    img.src = frame.url;
                });
            }).then(function(loaded) {
                if (state.session !== grabSession) return;
                setSourceFromCanvas(loaded.canvas, '游戏抓帧');
                // 手动抓帧同样入库为最近一帧（跨关闭/跨场景恢复显示）
                state.lastFrameUrl = loaded.url;
                state.lastFrameLabel = '游戏抓帧';
                saveState();
                setStatus('抓帧成功，已载入预览。', 'ok');
                state.bridgeState = 'ok';
                state.root.setAttribute('data-bridge', 'ok');
                setBadge('lut-lab-badge-bridge', '桥 ✓', 'ok');
            }).catch(function(e) {
                if (state.session !== grabSession) return;
                markBridgeUnavailable(e.message);
                setStatus('抓帧失败：' + e.message, 'error');
            });
        });
    }

    // ---------- DOM 装配 ----------

    function buildHelpSection(title, lines) {
        var section = el('section', 'lut-lab-help-section');
        section.appendChild(el('h3', '', title));
        lines.forEach(function(line) { section.appendChild(el('p', '', line)); });
        return section;
    }

    function createDOM() {
        state = freshState();
        var root = el('div', 'lut-lab-panel');
        root.id = 'lut-lab-panel';
        root.setAttribute('data-webgl', 'unknown');
        root.setAttribute('data-vhost', 'unknown');

        // header：标题 + 徽标 + 帮助 + 关闭
        var header = el('header', 'lut-lab-header');
        var title = el('span', 'lut-lab-title', 'LUT 实验室 ');
        title.appendChild(el('span', 'lut-lab-version', 'v2 · dev'));
        header.appendChild(title);
        var badges = el('span', 'lut-lab-badges');
        ['lut-lab-badge-webgl', 'lut-lab-badge-vhost', 'lut-lab-badge-bridge'].forEach(function(id) {
            var b = el('span', 'lut-lab-badge', '');
            b.id = id;
            badges.appendChild(b);
        });
        header.appendChild(badges);
        var helpBtn = el('button', 'lut-lab-help-btn', '?');
        helpBtn.type = 'button';
        helpBtn.setAttribute('aria-label', '帮助');
        helpBtn.addEventListener('click', function() { setHelpOpen(true); });
        header.appendChild(helpBtn);
        var closeBtn = el('button', 'lut-lab-close', '×');
        closeBtn.type = 'button';
        closeBtn.setAttribute('aria-label', '关闭 LUT 实验室');
        closeBtn.addEventListener('click', closeLocally);
        header.appendChild(closeBtn);
        root.appendChild(header);

        // 工具条：源图 / 集合 A/B / 模式 / 视图 / 扫动 / 等级 / 主显锁定 / 手动抓帧 / 抽屉
        var toolbar = el('div', 'lut-lab-toolbar');
        var srcInfo = el('span', 'lut-lab-source-info', '源图：—');
        toolbar.appendChild(srcInfo);

        toolbar.appendChild(el('span', 'lut-lab-label', '集合A'));
        var selectA = document.createElement('select');
        selectA.id = 'lut-lab-set-a';
        selectA.setAttribute('aria-label', '集合 A');
        toolbar.appendChild(selectA);
        toolbar.appendChild(el('span', 'lut-lab-label', '集合B'));
        var selectB = document.createElement('select');
        selectB.id = 'lut-lab-set-b';
        selectB.setAttribute('aria-label', '集合 B');
        toolbar.appendChild(selectB);

        var modeWrap = el('span', 'lut-lab-mode');
        modeWrap.setAttribute('role', 'group');
        modeWrap.setAttribute('aria-label', '模式');
        ['光照', '夜视'].forEach(function(modeName, idx) {
            var b = el('button', 'lut-lab-btn', modeName);
            b.type = 'button';
            b.setAttribute('data-mode', modeName);
            b.setAttribute('aria-pressed', idx === 0 ? 'true' : 'false');
            modeWrap.appendChild(b);
        });
        toolbar.appendChild(modeWrap);

        var viewWrap = el('span', 'lut-lab-view');
        viewWrap.setAttribute('role', 'group');
        viewWrap.setAttribute('aria-label', '视图');
        [['single', '单图'], ['split', 'AB分屏'], ['diff', '差值×4']].forEach(function(pair, idx) {
            var b = el('button', 'lut-lab-btn', pair[1]);
            b.type = 'button';
            b.setAttribute('data-view', pair[0]);
            b.setAttribute('aria-pressed', idx === 0 ? 'true' : 'false');
            viewWrap.appendChild(b);
        });
        toolbar.appendChild(viewWrap);

        var sweep = el('button', 'lut-lab-btn', '▶ 播放昼夜扫动');
        sweep.id = 'lut-lab-sweep';
        sweep.type = 'button';
        sweep.setAttribute('aria-pressed', 'false');
        toolbar.appendChild(sweep);

        toolbar.appendChild(el('span', 'lut-lab-label', '等级'));
        var slider = document.createElement('input');
        slider.type = 'range';
        slider.id = 'lut-lab-level';
        slider.min = '0'; slider.max = '10'; slider.step = '0.1'; slider.value = '7';
        slider.setAttribute('aria-label', '光照等级 0 到 10（0.1 步进，相邻档 mix）');
        toolbar.appendChild(slider);
        var levelValue = el('span', 'lut-lab-level-value', '7.0');
        levelValue.id = 'lut-lab-level-value';
        toolbar.appendChild(levelValue);

        var lock = el('button', 'lut-lab-btn', '主显：A（点击切 B）');
        lock.id = 'lut-lab-lock';
        lock.type = 'button';
        toolbar.appendChild(lock);

        var grab = el('button', 'lut-lab-btn', '抓取游戏画面');
        grab.id = 'lut-lab-grab';
        grab.type = 'button';
        toolbar.appendChild(grab);
        var grabHint = el('span', 'lut-lab-hint');
        grabHint.id = 'lut-lab-grab-hint';
        toolbar.appendChild(grabHint);

        var drawerToggle = el('button', 'lut-lab-btn', '样品库 ▸');
        drawerToggle.id = 'lut-lab-drawer-toggle';
        drawerToggle.type = 'button';
        drawerToggle.setAttribute('aria-expanded', 'false');
        toolbar.appendChild(drawerToggle);
        root.appendChild(toolbar);

        // 预设工作流条（三段式：新增/复制 → 锚点编辑 → 保存）
        var presetBar = el('div', 'lut-lab-preset-bar');
        presetBar.setAttribute('data-active', 'false');
        var presetLabel = el('span', 'lut-lab-preset-current', '预设编辑：无');
        presetLabel.id = 'lut-lab-preset-current';
        presetBar.appendChild(presetLabel);
        var btnNewXml = el('button', 'lut-lab-btn lut-lab-btn-mini', '新增:从XML复制');
        btnNewXml.type = 'button';
        btnNewXml.id = 'lut-lab-preset-new-xml';
        presetBar.appendChild(btnNewXml);
        var btnNewSet = el('button', 'lut-lab-btn lut-lab-btn-mini', '新增:从集合复制');
        btnNewSet.type = 'button';
        btnNewSet.id = 'lut-lab-preset-new-set';
        presetBar.appendChild(btnNewSet);
        var btnNewBlank = el('button', 'lut-lab-btn lut-lab-btn-mini', '新增:空白');
        btnNewBlank.type = 'button';
        btnNewBlank.id = 'lut-lab-preset-new-blank';
        presetBar.appendChild(btnNewBlank);
        presetBar.appendChild(el('span', 'lut-lab-label', '名称'));
        var nameInput = document.createElement('input');
        nameInput.type = 'text';
        nameInput.id = 'lut-lab-preset-name';
        nameInput.setAttribute('aria-label', '预设名称（单路径段）');
        nameInput.placeholder = '预设名称';
        presetBar.appendChild(nameInput);
        var btnSave = el('button', 'lut-lab-btn lut-lab-btn-mini', '保存预设');
        btnSave.type = 'button';
        btnSave.id = 'lut-lab-preset-save';
        presetBar.appendChild(btnSave);
        var pixelToggle = el('button', 'lut-lab-btn lut-lab-btn-mini', '缩放:平滑');
        pixelToggle.type = 'button';
        pixelToggle.id = 'lut-lab-pixel-toggle';
        pixelToggle.setAttribute('aria-pressed', 'false');
        pixelToggle.setAttribute('aria-label', '主预览缩放显示切换（平滑/最近邻）');
        presetBar.appendChild(pixelToggle);
        root.appendChild(presetBar);

        // 一行短提示（遮挡策略细节在帮助界面）
        root.appendChild(el('div', 'lut-lab-capture-note',
            '遮挡策略：面板打开期间世界捕获挂起，手动抓帧只会得 no_frame；入场帧 = 打开前最后一帧。详见 ?'));

        // 主区：抽屉 + 舞台
        var main = el('div', 'lut-lab-main');
        var drawer = el('aside', 'lut-lab-drawer');
        drawer.setAttribute('data-open', 'false');
        drawer.appendChild(el('div', 'lut-lab-drawer-title',
            '样品库（→A / →B 作为全等级同款集合载入；许可证与备注见悬停提示）'));
        var drawerList = el('div', 'lut-lab-drawer-list');
        drawer.appendChild(drawerList);
        main.appendChild(drawer);

        var stage = el('div', 'lut-lab-stage');
        stage.setAttribute('role', 'button');
        stage.setAttribute('aria-label', '主预览（点击进 A|B 联动检视；按住 = 临时看另一集合）');
        stage.tabIndex = 0;
        var splitBar = el('div', 'lut-lab-split-bar');
        splitBar.style.display = 'none';
        stage.appendChild(splitBar);
        main.appendChild(stage);
        root.appendChild(main);

        // 底部等级胶片条（0–9 十格同帧并排）
        var strip = el('div', 'lut-lab-filmstrip');
        strip.setAttribute('role', 'group');
        strip.setAttribute('aria-label', '等级胶片条 0 到 9');
        root.appendChild(strip);

        var statusbar = el('div', 'lut-lab-statusbar');
        statusbar.setAttribute('role', 'status');
        statusbar.setAttribute('aria-live', 'polite');
        root.appendChild(statusbar);

        root.appendChild(buildHelpOverlay());
        root.appendChild(buildInspectOverlay());

        state.root = root;
        wireEvents();
        return root;
    }

    function buildHelpOverlay() {
        var overlay = el('div', 'lut-lab-help');
        overlay.style.display = 'none';
        overlay.setAttribute('role', 'dialog');
        overlay.setAttribute('aria-label', 'LUT 实验室帮助');
        var box = el('div', 'lut-lab-overlay-box');
        var bar = el('div', 'lut-lab-overlay-bar');
        bar.appendChild(el('span', 'lut-lab-overlay-title', 'LUT 实验室 · 帮助'));
        var closeBtn = el('button', 'lut-lab-overlay-close', '×');
        closeBtn.type = 'button';
        closeBtn.setAttribute('aria-label', '关闭帮助');
        closeBtn.addEventListener('click', function() { setHelpOpen(false); });
        bar.appendChild(closeBtn);
        box.appendChild(bar);
        overlay.appendChild(box);
        overlay.addEventListener('keydown', function(ev) {
            if (ev.key === 'Escape') { ev.stopPropagation(); setHelpOpen(false); }
        });

        box.appendChild(buildHelpSection('工作流', [
            '集合（set）= 某模式（光照/夜视）下 0–9 整数级各一个 LUT 的有序组。选集合 A 与集合 B，',
            '底部胶片条同帧十格看 ramp 连续性；主预览看当前等级；A/B 对照两套谁更好。',
            '集合 A 默认「XML 当前预设」（lutlab.bakeXmlSet 实时烘焙 color_engine_preset.xml；',
            '桥不可用时回退 vhost 预烘焙 xml-regression 文件组）。样品库里任意单 LUT 可作为',
            '「全等级同款」退化集合载入 A/B，用于 free 组风格初筛。'
        ]));
        box.appendChild(buildHelpSection('快捷键与交互', [
            '按住主预览画面或按住空格 = 临时看另一集合（peek，松开即回）；',
            '「主显」按钮 = 锁定切换 A/B；点胶片格 = 钉到该等级；',
            '「AB分屏」中间线可拖动；「差值×4」下 A==B 时必须纯黑；',
            '点主预览 = A|B 联动检视（滚轮缩放、拖拽平移、高倍最近邻查 banding，Esc/× 退出）。'
        ]));
        box.appendChild(buildHelpSection('预设工作流（三段式）', [
            '①新增：「从XML复制 / 从集合复制 / 空白」开编辑中预设（工具条第二行）。',
            '②锚点：胶片格 [⚓] 从样品库为该级指派 LUT、[≡] 一键恒等锚、[×] 清除；',
            '   未指派等级自动在相邻锚点间线性插帧（标「插值」；两端之外 hold 最近锚点）。',
            '   混合语义：CPU 节点线性混合 + 8bit 量化，预览与保存共用同一结果（保存→重载与预览逐像素一致）。',
            '③保存：填名称（单路径段）→ Host 写 tmp/lut-lab/presets/<名称>/（preset.json + 10 个 .cube）',
            '   并原子更新 manifest.sets.json、重读字节自检；新预设立即出现在集合 A/B 选择器。',
            '   保存只写 tmp/lut-lab/，不碰 data/ 与生产配置——生产导入是后续人工步骤。'
        ]));
        box.appendChild(buildHelpSection('入场帧与捕获遮挡策略', [
            '入场帧由 Host 在打开面板前自动抓取（ LutLabTask.TryGrabEntryFrameUrl ），源图标签含抓取时间戳。',
            '面板打开期间世界捕获按生产遮挡策略挂起（合成器 Active(false)，捕获会话关闭）：',
            '面板内「抓取游戏画面」只会得到 no_frame——这不是故障。需要更新的帧：关闭面板后重新进入。',
            '抓帧只含世界视口像素（裁剪区域）；若世界视口尚未建立（未进世界/合成器未呈现）则拒绝抓取',
            '（no_world_viewport），不会把含标题栏的整窗画面当作世界帧（2026-09-24 缺陷 X 修复）。'
        ]));
        box.appendChild(buildHelpSection('样品来源与许可证', [
            'generated 组：tools/lut-lab 本地生成；xml-regression 组：XML 预设离线烘焙真值。',
            'free 组 7 款为外部免费 LUT，仅内部验收样品，许可证未审前不得进入任何发行闭包',
            '（明细：tmp/lut-lab/samples/free/LICENSES.md）。'
        ]));
        box.appendChild(buildHelpSection('工作台持久化', [
            '集合 A/B、模式、等级、视图、抽屉开合、编辑中的预设名、最近一次抓帧（含时间戳）自动保存到',
            '本机 localStorage（cf7.lutlab.workbench.v1）；关闭面板/换场景/重启后自动恢复。',
            '失效引用（集合被删）回退默认并提示；上次抓帧直接载入显示，即使本次入场预抓失败也有上一帧可看。'
        ]));
        box.appendChild(buildHelpSection('离线工具与 QA', [
            'node tools/lut-lab/cli.js generate/apply/gen-image/inspect/make-set（生成与集合组装）',
            'node --experimental-websocket launcher/web/modules/lut-lab/tools/run-lut-lab-qa.mjs（Edge/CDP QA）',
            '浏览器 harness：launcher/web/modules/lut-lab/dev/server.mjs'
        ]));
        return overlay;
    }

    function buildInspectOverlay() {
        var overlay = el('div', 'lut-lab-inspect');
        overlay.style.display = 'none';
        overlay.setAttribute('role', 'dialog');
        overlay.setAttribute('aria-label', 'A|B 联动检视');
        var bar = el('div', 'lut-lab-overlay-bar');
        bar.appendChild(el('span', 'lut-lab-overlay-title', '联动检视 — 拖拽平移 / 滚轮缩放（同一视角驱动 A|B）'));
        var status = el('span', 'lut-lab-inspect-status', '');
        bar.appendChild(status);
        var closeBtn = el('button', 'lut-lab-overlay-close', '×');
        closeBtn.type = 'button';
        closeBtn.setAttribute('aria-label', '关闭检视');
        bar.appendChild(closeBtn);
        overlay.appendChild(bar);
        var panes = el('div', 'lut-lab-inspect-panes');
        ['A', 'B'].forEach(function(side) {
            var pane = el('div', 'lut-lab-inspect-pane');
            pane.setAttribute('data-side', side);
            pane.appendChild(el('div', 'lut-lab-inspect-side', side));
            var vp = el('div', 'lut-lab-inspect-viewport');
            vp.tabIndex = 0;
            var target = el('div', 'lut-lab-inspect-target');
            vp.appendChild(target);
            pane.appendChild(vp);
            panes.appendChild(pane);
        });
        overlay.appendChild(panes);
        wireInspect(overlay);
        return overlay;
    }

    // ---------- 事件接线 ----------

    function wireEvents() {
        var slider = state.root.querySelector('#lut-lab-level');
        slider.addEventListener('input', function() {
            setLevel(parseFloat(slider.value) || 0);
        });

        state.root.querySelectorAll('.lut-lab-mode button').forEach(function(btn) {
            btn.addEventListener('click', function() { setMode(btn.getAttribute('data-mode')); });
        });
        state.root.querySelectorAll('.lut-lab-view button').forEach(function(btn) {
            btn.addEventListener('click', function() { setView(btn.getAttribute('data-view')); });
        });
        state.root.querySelector('#lut-lab-set-a').addEventListener('change', function(ev) {
            onSetSelected('A', ev.target.value);
        });
        state.root.querySelector('#lut-lab-set-b').addEventListener('change', function(ev) {
            onSetSelected('B', ev.target.value);
        });
        state.root.querySelector('#lut-lab-lock').addEventListener('click', function() {
            state.locked = state.locked === 'A' ? 'B' : 'A';
            state.filmKey = '';
            renderAll();
        });
        state.root.querySelector('#lut-lab-sweep').addEventListener('click', toggleSweep);
        state.root.querySelector('#lut-lab-drawer-toggle').addEventListener('click', toggleDrawer);
        state.root.querySelector('#lut-lab-preset-new-xml').addEventListener('click', startPresetFromXml);
        state.root.querySelector('#lut-lab-preset-new-set').addEventListener('click', startPresetFromSet);
        state.root.querySelector('#lut-lab-preset-new-blank').addEventListener('click', startPresetBlank);
        state.root.querySelector('#lut-lab-preset-save').addEventListener('click', savePresetFlow);
        state.root.querySelector('#lut-lab-pixel-toggle').addEventListener('click', togglePixelScaling);
        wireGrab();

        // 主预览：按住 = peek 另一集合；点击（未拖动）= 联动检视
        var stage = state.root.querySelector('.lut-lab-stage');
        var downAt = null;
        stage.addEventListener('mousedown', function(ev) {
            if (state.view !== 'single' || state.helpOpen || state.inspectOpen) return;
            downAt = { x: ev.clientX, y: ev.clientY };
            state.peekB = true;
            renderMain();
            ev.preventDefault();
        });
        stage.addEventListener('mouseup', function(ev) {
            if (state.peekB) { state.peekB = false; renderMain(); }
            if (downAt && Math.abs(ev.clientX - downAt.x) + Math.abs(ev.clientY - downAt.y) < 6) {
                openInspect();
            }
            downAt = null;
        });
        stage.addEventListener('mouseleave', function() {
            if (state.peekB) { state.peekB = false; renderMain(); }
            downAt = null;
        });
        // 分屏分割线拖动
        var splitBar = state.root.querySelector('.lut-lab-split-bar');
        splitBar.addEventListener('mousedown', function(ev) {
            ev.preventDefault();
            ev.stopPropagation();
            var rect = stage.getBoundingClientRect();
            function move(e2) {
                state.splitX = Math.max(0.05, Math.min(0.95, (e2.clientX - rect.left) / rect.width));
                renderMain();
            }
            function up() {
                window.removeEventListener('mousemove', move, true);
                window.removeEventListener('mouseup', up, true);
            }
            window.addEventListener('mousemove', move, true);
            window.addEventListener('mouseup', up, true);
        });

        window.addEventListener('keydown', onKeyDown);
        window.addEventListener('keyup', onKeyUp);
    }

    function unwireEvents() {
        window.removeEventListener('keydown', onKeyDown);
        window.removeEventListener('keyup', onKeyUp);
    }

    // ---------- 生命周期 ----------

    function closeLocally() {
        try { Panels.close(); } catch (e) {}
        if (typeof Bridge !== 'undefined') Bridge.send({ type: 'panel', cmd: 'close', panel: 'lut-lab' });
    }

    function onOpen(el, initData) {
        // Panels 契约：create 只在首次 open 跑一次（panel._el 保留），onOpen 每次打开都跑。
        // cleanup 已复位会话字段并 lose GL；这里按新会话完整重建内容（幂等、可重入）。
        state.root = el || state.root;
        state.sessionActive = true;
        state.root.setAttribute('data-webgl', 'unknown');
        state.root.setAttribute('data-vhost', 'unknown');
        setBadge('lut-lab-badge-webgl', '', 'muted');
        setBadge('lut-lab-badge-vhost', '', 'muted');
        state.root.querySelector('.lut-lab-mode').querySelectorAll('button').forEach(function(btn) {
            btn.setAttribute('aria-pressed', btn.getAttribute('data-mode') === state.mode ? 'true' : 'false');
        });
        var slider = state.root.querySelector('#lut-lab-level');
        if (slider) slider.value = String(state.level);
        var strip = state.root.querySelector('.lut-lab-filmstrip');
        if (strip) strip.innerHTML = '';
        // 工作台状态恢复（localStorage）：先恢复标量（模式/等级/视图/抽屉/预设名），
        // 集合选择在清单加载完成后校验恢复；上次抓帧在无本次入场帧时兜底显示。
        var persisted = readPersistedState();
        restoreScalarFields(persisted);
        if (slider) slider.value = String(state.level);
        initBridgeState();
        syncBridgeControls();
        syncSweepButton();
        syncLockButton();
        syncPresetBar();
        // 入场帧优先（Host 预抓）；先铺内置测试图保证立即可渲染，入场帧到达后替换。
        setSourceFromCanvas(makeTestImage(), '内置测试图');
        var entryUrl = initData && typeof initData.entryFrameUrl === 'string' ? initData.entryFrameUrl : '';
        if (entryUrl) {
            loadEntryFrame(entryUrl, '入场抓帧');
        } else if (persisted && typeof persisted.lastFrameUrl === 'string' && persisted.lastFrameUrl) {
            // 上次抓帧兜底：即使本次入场预抓失败，也有上一帧可看（标签含抓取时间戳）
            loadEntryFrame(persisted.lastFrameUrl, '上次抓帧');
        }
        // 集合与样品：XML 集合（桥/回退）+ vhost 集合清单 + 样品清单（含 fixture 退化集合）
        loadXmlSet(state.mode);
        ensureFixtureDegenerateSets();
        refreshSetSelectors();
        pickDefaultSets();
        refreshSetSelectors();
        var setA = currentSet('A');
        if (setA) ensureSetLoaded(setA);
        var setB = currentSet('B');
        if (setB) ensureSetLoaded(setB);
        var openSession = state.session;
        // 集合清单（vhost sets + samples）双就绪后再恢复集合选择（含失效引用回退与样品引用重建）
        Promise.all([loadVhostSets(), loadSamples()]).then(function() {
            if (state.session !== openSession) return;
            restoreSetSelection(persisted);
            renderAll();
        });
        renderAll();
    }

    // fixture 退化集合即刻可用（cubeText 内置），保证无桥无 vhost 也有 A/B 可对
    function ensureFixtureDegenerateSets() {
        CF7.LutLabFixtures.list.forEach(function(f) {
            makeDegenerateSet({
                group: 'fixture', name: f.name, file: '', source: f.source,
                license: f.license, notes: f.notes, cubeText: f.cubeText
            });
        });
    }

    function cleanup() {
        state.sessionActive = false;
        stopSweep();
        closeInspect();
        if (state && state.renderer) {
            try {
                var ext = state.renderer.gl.getExtension('WEBGL_lose_context');
                if (ext) ext.loseContext();
            } catch (e) {}
            // 渲染器画布从舞台摘除（GL 已死），下次 open 由 ensureRenderer 重建并重新挂载
            if (state.renderer.canvas && state.renderer.canvas.parentNode) {
                state.renderer.canvas.parentNode.removeChild(state.renderer.canvas);
            }
        }
        if (!state) return;
        // 框架契约：DOM（panel._el）与模块 state 跨 close 保留，reopen 不再跑 create；
        // 复位全部会话字段并使在途异步失效，onOpen 据此完整重建（修重开黑死）。
        state.renderer = null;
        state.rendererError = null;
        state.session++;
        state.filmSeq++;
        state.manifestSeq++;
        state.sets = [];
        state.setAId = null;
        state.setBId = null;
        state.samples = [];
        state.sourceCanvas = null;
        state.sourceLabel = '';
        state.vhostState = 'unknown';
        state.bridgeState = null;
        state.bridgeReason = '';
        state.xmlSetState = 'unknown';
        state.filmKey = '';
        state.peekB = false;
        state.view = 'single';
        state.locked = 'A';
        state.level = 7;
        state.mode = '光照';
        state.drawerOpen = false;
        state.helpOpen = false;
        state.preset = null;
        state.anchorPickLevel = -1;
        state.pixelScaling = false;
        state.restoredSession = -1;
        var presetNameInput = state.root && state.root.querySelector('#lut-lab-preset-name');
        if (presetNameInput) presetNameInput.value = '';
        var drawer = state.root && state.root.querySelector('.lut-lab-drawer');
        if (drawer) drawer.setAttribute('data-open', 'false');
        var help = state.root && state.root.querySelector('.lut-lab-help');
        if (help) help.style.display = 'none';
    }

    Panels.register('lut-lab', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: closeLocally,
        onClose: cleanup,
        onForceClose: cleanup,
        // QA / 诊断用只读探针（不暴露写路径）
        _debugState: function() {
            if (!state) return null;
            return {
                sets: state.sets.map(function(s) {
                    return {
                        id: s.id, title: s.title, mode: s.mode, origin: s.origin,
                        loaded: s.loaded, loadError: s.loadError || null,
                        levelsReady: s.levels.filter(function(l) { return !!l; }).length
                    };
                }),
                setA: state.setAId,
                setB: state.setBId,
                mode: state.mode,
                level: state.level,
                view: state.view,
                locked: state.locked,
                peekB: state.peekB,
                sweeping: state.sweeping,
                vhost: state.vhostState,
                bridge: state.bridgeState,
                xmlSet: state.xmlSetState,
                helpOpen: state.helpOpen,
                drawerOpen: state.drawerOpen,
                inspectOpen: state.inspectOpen,
                samples: state.samples.length,
                manifestErrors: state.manifestErrors.slice(),
                preset: state.preset
                    ? {
                        name: state.preset.name,
                        mode: state.preset.mode,
                        base: state.preset.base,
                        anchors: state.preset.anchors.map(function(a) { return !!a; }),
                        rev: state.preset.rev
                    }
                    : null,
                anchorPickLevel: state.anchorPickLevel,
                pixelScaling: state.pixelScaling,
                persistedAvailable: storageAvailable(),
                lastFrameUrl: state.lastFrameUrl || null,
                restoredSelection: state.restoredSession === state.session,
                source: state.sourceCanvas
                    ? { width: state.sourceCanvas.width, height: state.sourceCanvas.height, label: state.sourceLabel }
                    : null
            };
        },
        // QA 用只读像素探针：主预览当前渲染结果 / 当前源图
        _debugReadMain: function() {
            if (!state || !state.renderer) return null;
            return state.renderer.readPixels();
        },
        _debugReadSource: function() {
            if (!state || !state.sourceCanvas) return null;
            var c = state.sourceCanvas;
            return c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
        }
    });
})();
