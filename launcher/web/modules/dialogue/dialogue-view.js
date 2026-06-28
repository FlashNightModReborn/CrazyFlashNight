/*
 * Reusable Web dialogue replay view.
 * Text remains AS2-authored; portrait lookup is driven by the baked
 * dialogue-portraits manifest and, for the protagonist, the dressup renderer.
 */
(function(global) {
    'use strict';

    var PORTRAIT_MANIFEST_URL = 'assets/dialogue-portraits/manifest.json';
    var DRESSUP_MANIFEST_URL = 'assets/dressup/manifest.json';
    var PORTRAIT_SLOT_W = 268;
    var PORTRAIT_SLOT_H = 153;
    // 复刻原版对话框取景：外部立绘透过 flashswf/UI/对话框界面 元件的固定遮罩窗口显示（外部 SWF 在
    // 「外部立绘层」原点、100% 放置，遮罩与 SWF 同坐标系），所以该窗口直接是 1024×576 PNG 上的裁剪框。
    // 关键：所有 pose 共用同一窗口 + 同一缩放 → 不再按各自包围盒 fit，消除「一张铺满一张很扁」。
    // 优先用 manifest.portraitWindow（烘焙脚本解析自 mask 层），缺失时退回此常量。
    var EXTERNAL_PORTRAIT_WINDOW = { x: 30, y: 30, width: 880, height: 375 };
    // 统一缩放系数。=1 时窗口 [y:30..405] 精确映射满槽高 → 底边恰为原版遮罩底边（裁掉美术在
    // 遮罩下方留的“红色废墟基座”等未精修背景，y≈405..423）。**勿 <1**：那会让槽显示到窗口下方、
    // 把被原版盖住的背景基座露出来。>1 则向胸像内裁得更紧。群像宽度靠 PORTRAIT_SLOT_W 适配，不靠降此值。
    var PORTRAIT_ZOOM = 1.0;
    var DEFAULT_EXPRESSION = '普通';
    // 主角 key 的权威来源有二：① AS2 运行时下发的 line.portraitType==='hero'（主路径）；
    // ② 烘焙脚本 tools/bake-dialogue-portraits.py 写入 manifest.heroKeys（本模块据此判定，见 heroKeySet）。
    // 这里只保留兜底常量，供 manifest 缺 heroKeys 时使用——不再做第三处硬编码，避免与上面两处漂移。
    // 同名清单亦见 AS2 TaskPanelService.buildHeroPortraitState 的 portraitType 判定。
    var HERO_KEYS_FALLBACK = ['$PC_CHAR', '玩家', '主角模板'];
    // 主角对话立绘用「战斗 rig」渲染，而非对话框 man pose——经实机核对：原版对话框的 man pose 主角
    // 其实不显示武器（rig 里有 _装扮 武器 holder 但原版从不填充），而玩家模板做的 NPC 立绘统一是
    // 战斗形态带武器（背后收纳）。为对齐 NPC 立绘标准、且不去碰几年没动、负债重的对话框 rig 数据，
    // 主角直接走 battle rig。空手站立=武器收纳背后的站姿，最接近 NPC 立绘；战斗 rig 武器 holder 字段
    // 同为 _装扮，正好被 equipment→fieldsByGender 产出的 keyMap 命中（无需 AS2 改动）。
    var HERO_BATTLE_STATE = '空手站立';
    // 胸像取景：仅以「头+躯干+上臂」定缩放（战斗 rig 同名 holder），头大、腿向下溢出由画布裁切。
    // 不传 drawFields → 画战斗 rig 全身（含背后武器）。
    var PORTRAIT_FIT_FIELDS = [
        '脸型', '发型', '面具', '身体', '上臂'
    ];

    var _portraitManifestPromise = null;
    var _dressupManifestPromise = null;
    var _renderSeq = 0;
    var STAGED_LINE_DELAY_MS = 320;

    function fetchJson(url) {
        return fetch(url, { cache: 'no-cache' }).then(function(resp) {
            if (!resp.ok) throw new Error('failed to load ' + url + ': ' + resp.status);
            return resp.json();
        });
    }

    function baseUrl(url) {
        var idx = url.lastIndexOf('/');
        return idx >= 0 ? url.slice(0, idx + 1) : '';
    }

    function loadPortraitManifest(url) {
        url = url || PORTRAIT_MANIFEST_URL;
        if (!_portraitManifestPromise) {
            _portraitManifestPromise = fetchJson(url).then(function(manifest) {
                manifest.__baseUrl = baseUrl(url);
                manifest.__index = buildIndex(manifest);
                return manifest;
            }).catch(function(err) {
                _portraitManifestPromise = null; // 失败不毒化会话：瞬时 fetch 失败后下次渲染可重试
                throw err;
            });
        }
        return _portraitManifestPromise;
    }

    function loadDressupManifest() {
        if (!_dressupManifestPromise) {
            if (!global.DressupDollRenderer || !global.DressupDollRenderer.loadManifest) {
                _dressupManifestPromise = Promise.resolve(null);
            } else {
                _dressupManifestPromise = global.DressupDollRenderer.loadManifest(DRESSUP_MANIFEST_URL)
                    .catch(function(err) {
                        _dressupManifestPromise = null; // 同上：失败不永久退化为占位，下次主角立绘可重试
                        throw err;
                    });
            }
        }
        return _dressupManifestPromise;
    }

    function buildIndex(manifest) {
        var index = {};
        function add(key, entry) {
            if (!key) return;
            index[key] = entry;
            index[String(key).toLowerCase()] = entry;
            index[String(key).replace(/\s+/g, '').toLowerCase()] = entry;
        }
        var entries = manifest.entries || {};
        Object.keys(entries).forEach(function(key) {
            var entry = entries[key];
            add(key, entry);
            (entry.aliases || []).forEach(function(alias) { add(alias, entry); });
        });
        var aliases = manifest.aliases || {};
        Object.keys(aliases).forEach(function(alias) {
            var target = aliases[alias];
            if (entries[target]) add(alias, entries[target]);
        });
        return index;
    }

    function escHtml(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function setHtml(el, value, renderHtml) {
        el.innerHTML = renderHtml ? renderHtml(value || '') : escHtml(value || '');
    }

    function splitPortrait(line) {
        line = line || {};
        var raw = line.charBase || line.portraitKey || line.char || '';
        var expression = line.expression || '';
        if (raw && raw.indexOf('#') >= 0) {
            var parts = raw.split('#');
            raw = parts[0];
            if (!expression) expression = parts.slice(1).join('#');
        }
        if (!raw && line.speaker) raw = line.speaker;
        return {
            key: String(raw || '').trim(),
            expression: String(expression || DEFAULT_EXPRESSION).trim() || DEFAULT_EXPRESSION
        };
    }

    function heroKeySet(manifest) {
        var src = (manifest && manifest.heroKeys && manifest.heroKeys.length) ? manifest.heroKeys : HERO_KEYS_FALLBACK;
        var set = {};
        for (var i = 0; i < src.length; i++) set[src[i]] = true;
        return set;
    }

    function lookupEntry(manifest, key) {
        if (!manifest || !manifest.__index || !key) return null;
        return manifest.__index[key] ||
            manifest.__index[String(key).toLowerCase()] ||
            manifest.__index[String(key).replace(/\s+/g, '').toLowerCase()] ||
            null;
    }

    function resolveExpression(entry, expression) {
        if (!entry || !entry.expressions) return null;
        return entry.expressions[expression] ||
            entry.expressions[DEFAULT_EXPRESSION] ||
            entry.expressions[entry.defaultExpression] ||
            entry.expressions[Object.keys(entry.expressions)[0]] ||
            null;
    }

    function assetUrl(manifest, asset) {
        if (!asset || !asset.uri) return '';
        return (manifest.__baseUrl || '') + asset.uri;
    }

    function positiveNumber(value, fallback) {
        value = Number(value);
        return isFinite(value) && value > 0 ? value : fallback;
    }

    function assetBounds(asset) {
        if (!asset || !asset.bounds) return null;
        var b = asset.bounds;
        var width = positiveNumber(b.width, 0);
        var height = positiveNumber(b.height, 0);
        if (!width || !height) return null;
        return {
            x: positiveNumber(b.x, 0),
            y: positiveNumber(b.y, 0),
            width: width,
            height: height
        };
    }

    function portraitWindowFor(manifest, entry) {
        var source = entry && entry.source;
        var fromManifest = manifest && manifest.portraitWindow;
        if (fromManifest && source && fromManifest[source]) return fromManifest[source];
        if (source === 'external-swf') return EXTERNAL_PORTRAIT_WINDOW;
        return null; // 内置 sprite 等：无固定窗口，退回包围盒兜底
    }

    function applyStagePortraitFit(img, asset, entry, manifest) {
        var bounds = assetBounds(asset);
        var imageW = positiveNumber(asset && asset.width, 0);
        var imageH = positiveNumber(asset && asset.height, 0);
        if (!bounds || !imageW || !imageH) {
            img.classList.add('cf-dialogue-portrait-img-contain');
            return;
        }
        var win = portraitWindowFor(manifest, entry);
        img.classList.add('cf-dialogue-portrait-img-stage');
        var update = function() {
            var slot = img.parentNode;
            if (!slot) return;
            var slotW = slot.clientWidth || PORTRAIT_SLOT_W;
            var slotH = slot.clientHeight || PORTRAIT_SLOT_H;
            if (win && win.height > 0) {
                // 固定窗口 + 统一缩放：纵向取景由窗口高度决定（所有 pose 共用同一 scale，
                // 不再让宽度驱动缩放）→ 群像与胸像等高，槽变宽变窄都不破。横向把人物包围盒
                // 中心居中到槽内，溢出由 slot 的 overflow:hidden 裁切（cover 语义，复刻原版）。
                var scale = (slotH / win.height) * PORTRAIT_ZOOM;
                var anchorX = bounds.x + bounds.width * 0.5;
                img.style.width = (imageW * scale).toFixed(2) + 'px';
                img.style.height = (imageH * scale).toFixed(2) + 'px';
                img.style.left = (slotW * 0.5 - anchorX * scale).toFixed(2) + 'px';
                img.style.top = (-win.y * scale).toFixed(2) + 'px';
                return;
            }
            // 兜底（内置 sprite / 无窗口）：底部锚定的包围盒贴合，行为同迁移前。
            var fbScale = Math.max(1, slotH) / bounds.height;
            var maxVisualW = slotW * 1.20;
            if (bounds.width * fbScale > maxVisualW) fbScale = maxVisualW / bounds.width;
            var anchorBX = bounds.x + bounds.width * 0.5;
            var anchorBY = bounds.y + bounds.height;
            img.style.width = (imageW * fbScale).toFixed(2) + 'px';
            img.style.height = (imageH * fbScale).toFixed(2) + 'px';
            img.style.left = (slotW * 0.5 - anchorBX * fbScale).toFixed(2) + 'px';
            img.style.top = (slotH - anchorBY * fbScale).toFixed(2) + 'px';
        };
        update();
        if (typeof requestAnimationFrame === 'function') requestAnimationFrame(update);
    }

    function clearNode(node) {
        while (node.firstChild) node.removeChild(node.firstChild);
    }

    function clearTimers(container) {
        if (!container || !container.__dialogueTimers) return;
        for (var i = 0; i < container.__dialogueTimers.length; i++) {
            clearTimeout(container.__dialogueTimers[i]);
        }
        container.__dialogueTimers = [];
    }

    function showPlaceholder(slot, label) {
        clearNode(slot);
        var mark = document.createElement('div');
        mark.className = 'cf-dialogue-portrait-placeholder';
        mark.textContent = label || '';
        slot.appendChild(mark);
    }

    function renderImagePortrait(slot, manifest, entry, expression) {
        var asset = resolveExpression(entry, expression);
        if (!asset) {
            showPlaceholder(slot, entry ? entry.key : '');
            return;
        }
        clearNode(slot);
        var img = document.createElement('img');
        img.className = 'cf-dialogue-portrait-img';
        img.alt = '';
        img.decoding = 'async';
        img.loading = 'lazy';
        img.src = assetUrl(manifest, asset);
        img.onerror = function() {
            showPlaceholder(slot, entry.key || '');
        };
        slot.appendChild(img);
        applyStagePortraitFit(img, asset, entry, manifest);
    }

    function normalizeAppearance(raw, manifest, equipment) {
        raw = raw || {};
        var appearanceMeta = manifest && manifest.appearance || {};
        var result = {};
        var face = raw['脸型'] || raw.face || raw.faceId;
        var hair = raw['发型'] || raw.hair || raw.hairId;
        if (face != null && face !== '') {
            result['脸型'] = (appearanceMeta.faceById && appearanceMeta.faceById[face]) || face;
        }
        var headName = equipment && equipment['头部装备'];
        var head = manifest && manifest.items && headName ? manifest.items[headName] : null;
        var helmetSuppressesHair = !!(head && head.helmet === true);
        if (hair != null && hair !== '' && hair !== '光头' && !helmetSuppressesHair) {
            result['发型'] = (appearanceMeta.hairById && appearanceMeta.hairById[hair]) || hair;
        }
        return result;
    }

    function heroState(heroPortrait, dressupManifest) {
        heroPortrait = heroPortrait || {};
        var equipment = heroPortrait.equipment || {};
        var appearance = normalizeAppearance(heroPortrait.appearance || heroPortrait, dressupManifest, equipment);
        var st = global.DressupDollRenderer.buildStateFromEquipment(dressupManifest, {
            gender: heroPortrait.gender || heroPortrait['性别'] || '男',
            equipment: equipment,
            appearance: appearance,
            keyMap: heroPortrait.keyMap || null,
            fitFields: PORTRAIT_FIT_FIELDS,   // 以「头+躯干」上半身定缩放 = 胸像高度
            // 不传 drawFields：画战斗 rig 全身（含背后收纳武器），腿向下溢出由画布裁切
            rig: 'battle',
            stateLabel: HERO_BATTLE_STATE,    // 空手站立：武器收纳背后，对齐 NPC 立绘
            zoom: 1.05,
            margin: 6
        });
        // 与 NPC 立绘的固定窗口取景对齐：头部齐顶、身体下溢裁切（而非整体居中显示成小全身）。
        st.vAlign = 'top';
        return st;
    }

    function isBriefSlot(slot) {
        var container = slot && slot.closest ? slot.closest('.cf-dialogue') : null;
        return !!(container && container.getAttribute('data-dialogue-mode') === 'brief');
    }

    function renderHeroPortrait(slot, heroPortrait) {
        // 记下主角快照，供 setMode 在 rich/brief 间切换时重建（简略态销毁了 Canvas）。
        slot.__heroPortrait = heroPortrait || null;
        // 简略模式立绘被 CSS 隐藏：不创建 Canvas，避免隐藏画布的 24fps rAF 空转（仅动图主角才会持续空转，
        // 但静态主角也省掉一次无谓绘制）。切回 rich 时由 setMode 按 __heroPortrait 重建。createLine 已放占位。
        if (isBriefSlot(slot)) return Promise.resolve();
        if (!global.DressupDollRenderer || !global.AssetTimeline) {
            showPlaceholder(slot, 'PC');
            return Promise.resolve();
        }
        return loadDressupManifest().then(function(manifest) {
            // manifest 异步期间可能已切回 brief（快速来回切）：勿在隐藏槽建 Canvas，免得又起 rAF 空转。
            if (isBriefSlot(slot)) return;
            if (!manifest) {
                showPlaceholder(slot, 'PC');
                return;
            }
            clearNode(slot);
            var canvas = document.createElement('canvas');
            canvas.width = 220;
            canvas.height = 220;
            canvas.className = 'cf-dialogue-portrait-canvas';
            slot.appendChild(canvas);
            var renderer = global.DressupDollRenderer.create(canvas, {
                manifest: manifest,
                width: 220,
                height: 220,
                autoAnimate: true,
                fps: 24
            });
            renderer.render(heroState(heroPortrait, manifest));
            slot.__dialogueRenderer = renderer;
        }).catch(function() {
            showPlaceholder(slot, 'PC');
        });
    }

    // 简略模式：在对话容器上打标，CSS 据此切换信息密度（隐藏立绘、压缩为单列密排）。NPC 立绘是
    // 静态 <img>，仅切 class、保留 DOM（槽尺寸变化时 applyStagePortraitFit 已读 clientWidth 自适应）。
    // 主角是 Canvas renderer，简略态会销毁以停掉隐藏画布的 rAF 空转，切回 rich 时按 __heroPortrait 重建。
    function setMode(container, mode) {
        if (!container) return;
        var brief = mode === 'brief';
        container.setAttribute('data-dialogue-mode', brief ? 'brief' : 'rich');
        var slots = container.querySelectorAll('.cf-dialogue-portrait-slot');
        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            if (!('__heroPortrait' in slot)) continue; // 仅主角槽参与（NPC 槽无此字段）
            if (brief) {
                if (slot.__dialogueRenderer) {
                    if (slot.__dialogueRenderer.destroy) slot.__dialogueRenderer.destroy();
                    slot.__dialogueRenderer = null;
                }
            } else if (!slot.__dialogueRenderer && slot.__heroPortrait) {
                renderHeroPortrait(slot, slot.__heroPortrait);
            }
        }
    }

    function dispose(container) {
        clearTimers(container);
        var renderers = container.querySelectorAll('.cf-dialogue-portrait-slot');
        for (var i = 0; i < renderers.length; i++) {
            var renderer = renderers[i].__dialogueRenderer;
            if (renderer && renderer.destroy) renderer.destroy();
            renderers[i].__dialogueRenderer = null;
        }
    }

    function createLine(line, options) {
        var row = document.createElement('div');
        row.className = 'tlv-dia-line cf-dialogue-line';
        if (options && options.staged) row.classList.add('cf-dialogue-line-staged');
        var portrait = splitPortrait(line);
        row.setAttribute('data-char', portrait.key);
        row.setAttribute('data-expression', portrait.expression);

        var slot = document.createElement('div');
        slot.className = 'cf-dialogue-portrait-slot';
        showPlaceholder(slot, portrait.key);

        var body = document.createElement('div');
        body.className = 'cf-dialogue-body';

        var head = document.createElement('div');
        head.className = 'tlv-dia-head cf-dialogue-head';
        var speaker = document.createElement('span');
        speaker.className = 'tlv-dia-speaker';
        setHtml(speaker, line && line.speaker, options.renderHtml);
        head.appendChild(speaker);
        if (line && line.sub) {
            var sub = document.createElement('span');
            sub.className = 'tlv-dia-sub';
            setHtml(sub, line.sub, options.renderHtml);
            head.appendChild(sub);
        }
        var text = document.createElement('div');
        text.className = 'tlv-dia-text';
        setHtml(text, line && line.text, options.renderHtml);

        body.appendChild(head);
        body.appendChild(text);
        row.appendChild(slot);
        row.appendChild(body);
        return { row: row, slot: slot, line: line || {}, portrait: portrait };
    }

    function nonNegativeNumber(value, fallback) {
        value = Number(value);
        return isFinite(value) && value >= 0 ? value : fallback;
    }

    function prefersReducedMotion() {
        return !!(global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches);
    }

    function scrollParentOf(node) {
        var cur = node && node.parentElement;
        while (cur && cur !== document.body && cur !== document.documentElement) {
            var style = global.getComputedStyle ? global.getComputedStyle(cur) : null;
            var overflowY = style ? style.overflowY : '';
            if ((overflowY === 'auto' || overflowY === 'scroll') && cur.scrollHeight > cur.clientHeight + 1) return cur;
            cur = cur.parentElement;
        }
        return null;
    }

    function scrollLineIntoView(row) {
        var scroller = scrollParentOf(row);
        if (!scroller || !row.getBoundingClientRect || !scroller.getBoundingClientRect) return;
        var sr = scroller.getBoundingClientRect();
        var rr = row.getBoundingClientRect();
        var margin = 12;
        var delta = 0;
        if (rr.bottom > sr.bottom - margin) delta = rr.bottom - (sr.bottom - margin);
        else if (rr.top < sr.top + margin) delta = rr.top - (sr.top + margin);
        if (!delta) return;
        var nextTop = scroller.scrollTop + delta;
        if (scroller.scrollTo) {
            scroller.scrollTo({ top: nextTop, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
        } else {
            scroller.scrollTop = nextTop;
        }
    }

    function render(container, lines, options) {
        options = options || {};
        lines = lines || [];
        dispose(container);
        clearNode(container);
        container.classList.add('cf-dialogue');
        setMode(container, options.mode);
        var token = String(++_renderSeq);
        container.setAttribute('data-dialogue-render', token);
        var list = document.createElement('div');
        list.className = 'cf-dialogue-list';
        if (options.staged) list.classList.add('cf-dialogue-list-staged');
        var rows = [];

        var loadedManifest = null;
        var loadedHeroKeys = null;
        var manifestFailed = false;

        function renderPortraitFor(item) {
            if (!item || !loadedManifest) return;
            var key = item.portrait.key;
            if (loadedHeroKeys[key] || item.line.portraitType === 'hero') {
                renderHeroPortrait(item.slot, options.heroPortrait || item.line.heroPortrait || null);
                return;
            }
            var entry = lookupEntry(loadedManifest, key);
            if (!entry) {
                showPlaceholder(item.slot, key);
                return;
            }
            renderImagePortrait(item.slot, loadedManifest, entry, item.portrait.expression);
        }

        function appendLineAt(index) {
            if (container.getAttribute('data-dialogue-render') !== token) return;
            var item = createLine(lines[index], options);
            rows.push(item);
            list.appendChild(item.row);
            if (loadedManifest) renderPortraitFor(item);
            else if (manifestFailed) showPlaceholder(item.slot, item.portrait.key);
            if (options.autoScroll) {
                if (typeof requestAnimationFrame === 'function') requestAnimationFrame(function() { scrollLineIntoView(item.row); });
                else scrollLineIntoView(item.row);
            }
        }

        container.appendChild(list);

        if (options.staged) {
            container.__dialogueTimers = [];
            var delay = nonNegativeNumber(options.stagedDelayMs, STAGED_LINE_DELAY_MS);
            var initialDelay = nonNegativeNumber(options.stagedInitialDelayMs, 0);
            for (var s = 0; s < lines.length; s++) {
                (function(index) {
                    var timer = setTimeout(function() { appendLineAt(index); }, initialDelay + index * delay);
                    container.__dialogueTimers.push(timer);
                })(s);
            }
        } else {
            for (var i = 0; i < lines.length; i++) appendLineAt(i);
        }

        return loadPortraitManifest(options.manifestUrl).then(function(manifest) {
            if (container.getAttribute('data-dialogue-render') !== token) return;
            loadedManifest = manifest;
            loadedHeroKeys = heroKeySet(manifest);
            rows.forEach(renderPortraitFor);
        }).catch(function() {
            manifestFailed = true;
            rows.forEach(function(item) { showPlaceholder(item.slot, item.portrait.key); });
        });
    }

    global.DialogueView = {
        loadPortraitManifest: loadPortraitManifest,
        render: render,
        dispose: dispose,
        setMode: setMode,
        splitPortrait: splitPortrait
    };
})(window);
