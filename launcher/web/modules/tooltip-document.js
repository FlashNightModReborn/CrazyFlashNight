/**
 * PanelTooltipDocument — COMMON native_interaction tooltip document 的 Web 适配层
 *
 * 线格式（COMMON 桥协议 v1，与 AS2 org.flashNight.gesh.tooltip.NativeTooltipDocument
 * 产出、C# CF7Launcher.Guardian.Hud.Tooltip.NativeTooltipDocument 解析逐项对齐）：
 *
 *   payload  = {version:1, requestId, sceneId, x, y, owner?, revision?, document:{...}}
 *   document = {version:1, title?, icon:{kind?,name}, profile?, layoutType?, sections:[{role,runs:[{text,color?,bold?,italic?,underline?,fontSize?,fontFace?}]}]}
 *   run 扩展样式（document v1 可选字段，缺省即无样式）：italic/underline 布尔、
 *   fontSize 1..96 整数、fontFace 受限字体名（渲染期经 CF7FontCatalog.legacyFamily
 *   映射，未命中不输出）——与 legacy convertAS2Html 的 <I>/<U>/<FONT SIZE/FACE>
 *   支持面逐项对齐；样式不是主题，按既有 Web 级联渲。
 *
 * 纯文本契约（COMMON/INTEGRATION 冻结语义）：document.title 与 runs[].text 是
 * 已经聚合完成的【纯文本】——含 HTML 形态的字符（"<b>"、"&amp;"）一律按字面保留，
 * 这里【不】再解析标签或解码实体。旧 HTML 注释标记（font color/b/br/p/实体）只在
 * AS2 聚合边界或显式 flattenMarkup() 适配出口解析一次。
 *
 * 归一化容错原则（镜像 C# 实现）：字段缺失/类型异常只降级不抛；payload.version 与
 * document.version 任一层显式非 1 即拒绝；未知 section.role 归入 body 不丢内容；
 * run 可为裸字符串；'\n' 保留为 run 内硬换行；超长内容截断标记 truncated。
 * normalize() 对输入始终重新校验——不存在可绕过的 normalized 直通标记。
 *
 * 渲染产出复用 .flash-tt-rich / .flash-tt-intro-panel / .flash-tt-desc 骨架与
 * legacy buildItemRichHtml 完全同款的 kshop-tt-* 别名类——tooltip.js 的分栏、
 * 滚动、applyDescWidth、定位与 #panel-tooltip:has() 透明化全部零改动接管。
 * 视觉权威 = 迁移前 Web：#panel-tooltip 的 --tt-* token（Symbol 274 灰渐变
 * / 白字 / overlay 图标混合 / 默认字体继承）原样生效；ntt-* 仅为语义标记类，
 * 不产生任何视觉差异（css/panels/tooltip-document.css 只写这一约束，不改主题）。
 *
 * UMD：浏览器挂 window.PanelTooltipDocument（亦 CF7.PanelTooltipDocument），
 * Node 可 require 做定向测试。全部 API 为纯函数，不突变输入。
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.PanelTooltipDocument = api;
        root.CF7 = root.CF7 || {};
        root.CF7.PanelTooltipDocument = api;
    }
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this), function() {
    'use strict';

    var SUPPORTED_VERSION = 1;

    // 防御性容量上限（跨桥数据，对齐 C# 侧 descHTML 131072 上界量级）：
    // 超限只截断不拒绝——丢尾部内容好过整 tooltip 消失。
    var MAX_SECTIONS = 64;
    var MAX_RUNS_PER_SECTION = 256;
    var MAX_RUN_TEXT = 32768;
    var MAX_TOTAL_CHARS = 131072;
    var MAX_TITLE = 512;

    // ── 容错 JSON 读取（对齐 C# ReadString/ReadBool/ReadLong/ReadDouble）──

    function readString(node, name) {
        var v = node != null ? node[name] : null;
        if (v == null) return null;
        if (typeof v === 'string') return v;
        if (typeof v === 'number' || typeof v === 'boolean') return String(v);
        try { return String(v); } catch (e) { return null; }
    }

    function readBool(node, name, fallback) {
        var v = node != null ? node[name] : null;
        if (v == null) return fallback;
        if (v === true || v === false) return v;
        if (typeof v === 'number') return v !== 0;
        if (v === 'true') return true;
        if (v === 'false') return false;
        return fallback;
    }

    function readLong(node, name, fallback) {
        var v = node != null ? node[name] : null;
        if (v == null) return fallback;
        var n = (typeof v === 'number') ? v : parseInt(v, 10);
        return isFinite(n) ? Math.floor(n) : fallback;
    }

    function readDouble(node, name, fallback) {
        var v = node != null ? node[name] : null;
        if (v == null) return fallback;
        var n = (typeof v === 'number') ? v : parseFloat(v);
        return isFinite(n) ? n : fallback;
    }

    // '#RRGGBB' / 'RRGGBB' / '0xRRGGBB' → '#RRGGBB'（大写归一）；失败返回 null。
    // 3 位 hex（'#ABC'）按 Web legacy as2FontStyle 支持面规范化为 '#AABBCC'。
    function parseColor(value) {
        if (value == null) return null;
        var s = String(value).replace(/^\s+|\s+$/g, '');
        if (s.charAt(0) === '#') s = s.substring(1);
        else if (/^0[xX]/.test(s)) s = s.substring(2);
        if (/^[0-9a-fA-F]{3}$/.test(s)) {
            s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1)
                + s.charAt(2) + s.charAt(2);
        }
        if (!/^[0-9a-fA-F]{6}$/.test(s)) return null;
        return '#' + s.toUpperCase();
    }

    // fontSize：整数 1..96（legacy as2FontStyle 同款 parseInt+范围校验）。
    // '15px'/15/'15.9' → 15；越界/非数 → null 丢弃。
    function parseFontSize(value) {
        var px = parseInt(value, 10);
        return (isFinite(px) && px >= 1 && px <= 96) ? px : null;
    }

    // fontFace：受限字符集（\w / 中文 / 空格 / 连字符，legacy as2FontStyle
    // 同一白名单 + wire 合同 64 字符上限），值本身保留，渲染期才经 font
    // catalog 映射——杜绝任意 CSS。
    function sanitizeFontFace(value) {
        if (value == null) return null;
        var s = String(value)
            .replace(/[^\w一-龥 \-]/g, '')
            .replace(/\s+/g, ' ')
            .replace(/^\s+|\s+$/g, '');
        if (s.length > 64) s = s.substring(0, 64);
        return s || null;
    }

    // 渲染期 font catalog 映射：legacyFamily(face) → CSS family 串；未映射/无
    // catalog → null（不输出 font-family，与 legacy 未命中行为一致）。
    function mapFontFace(face) {
        if (face == null) return null;
        var rt = (typeof window !== 'undefined') ? window
            : (typeof globalThis !== 'undefined' ? globalThis : null);
        var cat = rt && rt.CF7FontCatalog;
        if (!cat || typeof cat.legacyFamily !== 'function') return null;
        var mapped = null;
        try { mapped = cat.legacyFamily(face); } catch (e) { mapped = null; }
        return (typeof mapped === 'string' && mapped.length) ? mapped : null;
    }

    // ── 受限内联标记展开器（NativeTooltipMarkup.FlattenInto 移植）──
    //
    // ⚠ 仅作显式旧 HTML 适配出口：供调用方把 AS2 htmlText 片段转成 runs 后组装
    // document。normalize() 的 title/runs.text 路径【不】经过这里——document 线格式
    // 是纯文本，二次解析会破坏字面量 <b>/&amp;（INTEGRATION.md §1）。
    //
    // 标签分类：br→换行；p(开)→段落换行（仅已产出内容时，避免头部空行），p(闭)→剥离；
    // font(开)→样式栈帧（font:true 标记 + color/size/face 各自可空）；font(闭)→弹到
    // 最近 font 帧（含其上所有帧），无匹配则弹末帧（沿用旧容错）；b/strong/i/em/u
    // 开闭→对应栈帧 / 弹到最近同族帧（无匹配容错忽略）；strong 归入 b、em 归入 i。
    // 其余一切标签剥离。
    // 实体：&lt; &gt; &amp; &quot; &apos; &nbsp; &#NN; &#xHH;；未知实体字面保留。

    var TAG_STRIP = 0, TAG_BR = 1, TAG_P = 2, TAG_FONT_OPEN = 3,
        TAG_FONT_CLOSE = 4, TAG_BOLD_OPEN = 5, TAG_BOLD_CLOSE = 6,
        TAG_ITALIC_OPEN = 7, TAG_ITALIC_CLOSE = 8,
        TAG_UNDERLINE_OPEN = 9, TAG_UNDERLINE_CLOSE = 10;

    function classifyTag(tagBody) {
        if (tagBody == null) return TAG_STRIP;
        var t = String(tagBody).replace(/^\s+|\s+$/g, '');
        if (!t.length) return TAG_STRIP;
        var closing = t.charAt(0) === '/';
        var name = closing ? t.substring(1) : t;
        var space = name.indexOf(' ');
        var slash = name.indexOf('/');
        var end = name.length;
        if (space >= 0 && space < end) end = space;
        if (slash >= 0 && slash < end) end = slash;
        name = name.substring(0, end).toLowerCase();
        if (name === 'br') return TAG_BR;
        if (name === 'p') return closing ? TAG_STRIP : TAG_P;
        if (name === 'font') return closing ? TAG_FONT_CLOSE : TAG_FONT_OPEN;
        if (name === 'b' || name === 'strong')
            return closing ? TAG_BOLD_CLOSE : TAG_BOLD_OPEN;
        if (name === 'i' || name === 'em')
            return closing ? TAG_ITALIC_CLOSE : TAG_ITALIC_OPEN;
        if (name === 'u') return closing ? TAG_UNDERLINE_CLOSE : TAG_UNDERLINE_OPEN;
        return TAG_STRIP;
    }

    // font 标签属性取值：属性名按 token 边界匹配（不命中引号值内部的同名片段），
    // 引号包裹值取到配对引号（face='ms mincho' 多空格名），裸值取首个 token——
    // 与 root 修过的 parseFontColor 多属性语义一致，不把后续属性吃进当前值。
    function fontAttrValue(tagBody, name) {
        var body = String(tagBody);
        var m = new RegExp('(?:^|[\\s/])' + name + '\\s*=', 'i').exec(body);
        if (!m) return null;   // 无 '=' 的裸属性 → legacy getAttribute 得 '' → 无样式
        var tail = body.substring(m.index + m[0].length).replace(/^\s+/, '');
        var q = tail.charAt(0);
        if (q === "'" || q === '"') {
            var e = tail.indexOf(q, 1);
            if (e < 0) return null;
            return tail.substring(1, e);
        }
        var v = /^[^\s'">]+/.exec(tail);
        return v ? v[0] : null;
    }

    function parseFontColor(tagBody) {
        return parseColor(fontAttrValue(tagBody, 'color'));
    }

    // family ∈ 'font'|'bold'|'italic'|'underline'：弹到最近同族帧（含其上所有帧）。
    // font 帧以 font:true 标记（可全空仅占样式边界）：无匹配仍弹末帧；
    // 其余族无匹配容错忽略。
    function popStyle(stack, family) {
        for (var i = stack.length - 1; i >= 0; i--) {
            var hit = (family === 'font')
                ? stack[i].font === true : stack[i][family] === true;
            if (hit) {
                stack.splice(i, stack.length - i);
                return;
            }
        }
        if (family === 'font' && stack.length) stack.pop();
    }

    function currentColor(state) {
        for (var i = state.stack.length - 1; i >= 0; i--) {
            if (state.stack[i].color != null) return state.stack[i].color;
        }
        return state.baseColor;
    }

    function currentBold(state) {
        for (var i = state.stack.length - 1; i >= 0; i--) {
            if (state.stack[i].bold) return true;
        }
        return state.baseBold;
    }

    function currentFlag(state, flag) {
        for (var i = state.stack.length - 1; i >= 0; i--) {
            if (state.stack[i][flag] === true) return true;
        }
        return false;
    }

    function currentFontAttr(state, name) {
        for (var i = state.stack.length - 1; i >= 0; i--) {
            if (state.stack[i][name] != null) return state.stack[i][name];
        }
        return null;
    }

    var ENTITIES = {
        'lt':'<', 'gt':'>', 'amp':'&', 'quot':'"', 'apos':'\'', 'nbsp':' '
    };

    function decodeEntity(entity) {
        if (!entity) return null;
        if (Object.prototype.hasOwnProperty.call(ENTITIES, entity)) return ENTITIES[entity];
        if (entity.charAt(0) === '#') {
            var hex = entity.length > 1 && (entity.charAt(1) === 'x' || entity.charAt(1) === 'X');
            var code = parseInt(entity.substring(hex ? 2 : 1), hex ? 16 : 10);
            if (isFinite(code) && code >= 0 && code <= 0x10FFFF) {
                try { return String.fromCodePoint(code); } catch (e) { return null; }
            }
        }
        return null;
    }

    // state: {stack:[{color,bold}], baseColor, baseBold, producedAnyText}
    // producedAnyText 在 section 内跨 run 携带（<p> 首段抑制用）；stack/base 由调用方
    // 在每个 JSON run 边界复位。
    function flattenInto(text, output, state) {
        if (text == null || text === '') return;
        text = String(text);
        var pos = 0, n = text.length, pending = '';

        function flush() {
            if (!pending.length) return;
            var run = { text: pending,
                color: currentColor(state), bold: currentBold(state) };
            if (currentFlag(state, 'italic')) run.italic = true;
            if (currentFlag(state, 'underline')) run.underline = true;
            var fs = currentFontAttr(state, 'fontSize');
            if (fs != null) run.fontSize = fs;
            var ff = currentFontAttr(state, 'fontFace');
            if (ff != null) run.fontFace = ff;
            output.push(run);
            pending = '';
            state.producedAnyText = true;
        }

        while (pos < n) {
            var c = text.charAt(pos);
            if (c === '<') {
                var gt = text.indexOf('>', pos + 1);
                if (gt < 0) { pending += c; pos++; continue; }   // 孤立 '<'：字面保留
                var kind = classifyTag(text.substring(pos + 1, gt));
                if (kind === TAG_BR) {
                    flush();
                    output.push({text: '\n', color: null, bold: false});
                    state.producedAnyText = true;
                } else if (kind === TAG_P) {
                    flush();
                    if (state.producedAnyText) {
                        output.push({text: '\n', color: null, bold: false});
                    }
                } else if (kind === TAG_FONT_OPEN) {
                    flush();
                    var tagBody = text.substring(pos + 1, gt);
                    state.stack.push({
                        font: true,
                        color: parseFontColor(tagBody),
                        fontSize: parseFontSize(fontAttrValue(tagBody, 'size')),
                        fontFace: sanitizeFontFace(fontAttrValue(tagBody, 'face'))
                    });
                } else if (kind === TAG_FONT_CLOSE) {
                    flush();
                    popStyle(state.stack, 'font');
                } else if (kind === TAG_BOLD_CLOSE) {
                    flush();
                    popStyle(state.stack, 'bold');
                } else if (kind === TAG_ITALIC_CLOSE) {
                    flush();
                    popStyle(state.stack, 'italic');
                } else if (kind === TAG_UNDERLINE_CLOSE) {
                    flush();
                    popStyle(state.stack, 'underline');
                } else if (kind === TAG_BOLD_OPEN) {
                    flush();
                    state.stack.push({bold: true});
                } else if (kind === TAG_ITALIC_OPEN) {
                    flush();
                    state.stack.push({italic: true});
                } else if (kind === TAG_UNDERLINE_OPEN) {
                    flush();
                    state.stack.push({underline: true});
                }
                // TAG_STRIP：静默剥离
                pos = gt + 1;
                continue;
            }
            if (c === '&') {
                var semi = text.indexOf(';', pos + 1);
                if (semi > pos && semi - pos <= 10) {
                    var decoded = decodeEntity(text.substring(pos + 1, semi));
                    if (decoded != null) { pending += decoded; pos = semi + 1; continue; }
                }
                pending += c; pos++;
                continue;
            }
            pending += c; pos++;
        }
        flush();
    }

    /** 一段 text → styled runs（'\n' 保留在 run.text 内）。 */
    function flattenMarkup(text, baseColor, baseBold) {
        var output = [];
        var state = {
            stack: [],
            baseColor: baseColor != null ? parseColor(baseColor) : null,
            baseBold: !!baseBold,
            producedAnyText: false
        };
        flattenInto(text, output, state);
        return output;
    }

    // ── document 归一化 ──

    function parseRole(role) {
        var r = role == null ? '' : String(role).toLowerCase();
        if (r === 'intro') return 'intro';
        if (r === 'description') return 'description';
        return 'body';   // 未知 role 归入 body，不丢内容
    }

    function parseProfile(profile) {
        var p = profile == null ? '' : String(profile).toLowerCase();
        if (p === 'dense') return 'dense';
        if (p === 'pinned') return 'pinned';
        return 'simple';
    }

    function plainTextOf(runs) {
        var s = '';
        for (var i = 0; i < runs.length; i++) s += runs[i].text;
        return s;
    }

    /**
     * COMMON document/payload → 归一化 doc 或 null。
     * 接受完整 payload（读 document 子对象 + 桥身份）或裸 document 节点。
     * payload.version 与 document.version 任一层显式非 1、document 缺失、
     * 无可渲染内容 → null（拒绝，不抛）。
     *
     * 始终从头校验+重建：输入里的 normalized/titleRuns 等字段不被采信，
     * 不可信输入无法伪造归一化结果绕过校验或 HTML escaping。
     */
    function normalize(input) {
        if (!input || typeof input !== 'object') return null;

        var payload = input;
        var docNode = (input.document && typeof input.document === 'object')
            ? input.document : null;
        if (docNode == null) {
            // payload 即 document 的退化形态：要求至少带 sections/title 其一
            if (input.sections != null || input.title != null) docNode = input;
        }
        if (docNode == null) return null;
        // version 两层独立校验（INTEGRATION §17）：payload 形态 payload.version 显式
        // 非 1 拒绝；document 节点自身显式 version 非 1 同样拒绝——外层 v1 不能掩盖
        // 内层 v2。裸 document 形态读节点自身 version。缺省一律按 1。
        if (docNode !== payload) {
            if (readLong(payload, 'version', SUPPORTED_VERSION) !== SUPPORTED_VERSION) {
                return null;
            }
        }
        if (readLong(docNode, 'version', SUPPORTED_VERSION) !== SUPPORTED_VERSION) {
            return null;
        }

        var doc = {
            normalized: true,
            version: SUPPORTED_VERSION,
            title: null,
            titleRuns: [],
            profile: 'simple',
            icon: null,
            sections: [],
            requestId: readString(payload, 'requestId'),
            sceneId: readString(payload, 'sceneId'),
            owner: readString(payload, 'owner'),
            revision: readLong(payload, 'revision', 0),
            anchorX: 0, anchorY: 0, hasAnchor: false,
            layoutType: null,
            truncated: false
        };
        var ax = readDouble(payload, 'x', NaN);
        var ay = readDouble(payload, 'y', NaN);
        if (isFinite(ax) && isFinite(ay)) {
            doc.anchorX = ax; doc.anchorY = ay; doc.hasAnchor = true;
        }

        var title = readString(docNode, 'title');
        if (title != null && title.length > MAX_TITLE) {
            title = title.substring(0, MAX_TITLE);
            doc.truncated = true;
        }
        if (title) {
            doc.title = title;
            // title 是纯文本：逐字保留为单个加粗 run，不走 flattenMarkup
            doc.titleRuns = [{ text: title, color: null, bold: true }];
        }

        doc.profile = parseProfile(readString(docNode, 'profile'));

        // layoutType 是 document 字段（AS2 buildItem 按物品类型写 wide/narrow，
        // C# sanitizer 原样透传）：缺省 null，调用方 opts.layoutType 仍可覆盖
        var layoutType = readString(docNode, 'layoutType');
        if (layoutType === 'narrow' || layoutType === 'wide') doc.layoutType = layoutType;

        var iconNode = docNode.icon;
        if (iconNode && typeof iconNode === 'object') {
            var iconName = readString(iconNode, 'name');
            if (iconName) {
                doc.icon = { kind: readString(iconNode, 'kind') || 'item', name: iconName };
            }
        }

        var totalChars = 0;
        var sections = docNode.sections;
        if (Array.isArray(sections)) {
            for (var si = 0; si < sections.length && si < MAX_SECTIONS; si++) {
                var secNode = sections[si];
                if (!secNode || typeof secNode !== 'object') continue;
                var section = { role: parseRole(secNode.role), runs: [] };
                var runs = secNode.runs;
                if (Array.isArray(runs)) {
                    for (var ri = 0; ri < runs.length && ri < MAX_RUNS_PER_SECTION; ri++) {
                        var runToken = runs[ri];
                        var text, color = null, bold = false,
                            italic = false, underline = false,
                            fontSize = null, fontFace = null;
                        if (runToken && typeof runToken === 'object') {
                            text = readString(runToken, 'text');
                            color = parseColor(runToken.color);
                            bold = readBool(runToken, 'bold', false);
                            italic = readBool(runToken, 'italic', false);
                            underline = readBool(runToken, 'underline', false);
                            fontSize = parseFontSize(runToken.fontSize);
                            fontFace = sanitizeFontFace(runToken.fontFace);
                        } else if (typeof runToken === 'string') {
                            text = runToken;
                        } else {
                            continue;
                        }
                        if (text == null) continue;
                        if (text.length > MAX_RUN_TEXT) {
                            text = text.substring(0, MAX_RUN_TEXT);
                            doc.truncated = true;
                        }
                        if (totalChars + text.length > MAX_TOTAL_CHARS) {
                            doc.truncated = true;
                            break;
                        }
                        totalChars += text.length;
                        // text 逐字保留：'<b>'、'&amp;' 等按字面进入 run，
                        // 渲染期 escapeHtml 只负责安全转义一次。
                        var run = { text: text, color: color, bold: bold };
                        if (italic) run.italic = true;
                        if (underline) run.underline = true;
                        if (fontSize != null) run.fontSize = fontSize;
                        if (fontFace != null) run.fontFace = fontFace;
                        section.runs.push(run);
                    }
                    if (runs.length > MAX_RUNS_PER_SECTION) doc.truncated = true;
                }
                // 空 run 段也保留：显式空段可占位（例如预留 meta 行）。
                doc.sections.push(section);
            }
            if (sections.length > MAX_SECTIONS) doc.truncated = true;
        }

        if (!hasContent(doc)) return null;
        return doc;
    }

    function hasContent(doc) {
        if (doc.title) return true;
        if (doc.icon && doc.icon.name) return true;
        for (var i = 0; i < doc.sections.length; i++) {
            if (plainTextOf(doc.sections[i].runs).length > 0) return true;
        }
        return false;
    }

    function describe(doc) {
        if (!doc) return 'tooltip-document null';
        return 'tooltip v' + doc.version
            + ' profile=' + doc.profile
            + ' req=' + (doc.requestId || '-')
            + ' scene=' + (doc.sceneId || '-')
            + ' owner=' + (doc.owner || '-')
            + ' rev=' + doc.revision
            + ' title=' + (doc.title || '-')
            + ' icon=' + (doc.icon ? doc.icon.kind + ':' + doc.icon.name : '-')
            + ' sections=' + doc.sections.length
            + (doc.layoutType ? ' lt=' + doc.layoutType : '')
            + (doc.truncated ? ' [truncated]' : '');
    }

    // ── 计分与分栏决策（对齐 AS2 StringUtils.htmlScoresBoth / shouldSplitSmart）──
    //
    // 字符权重：ASCII=1，CJK 宽=2，空白=0.5，换行 flush。常量与 tooltip.js /
    // TooltipConstants.as 同源：SPLIT_THRESHOLD=96、SMART_TOTAL_MULTIPLIER=2、
    // SMART_DESC_DIVISOR=2、MERGE_MAX_INTRO_LINES=20、MERGE_CHARS_PER_LINE≈33。
    // ⚠️ 跨语言常量同步：任一端改了需三处（AS2/C#/web）一起改。

    var SPLIT_THRESHOLD = 96;
    var SMART_TOTAL_MULT = 2;
    var SMART_DESC_DIV = 2;
    var MERGE_MAX_INTRO_LINES = 20;
    var MERGE_CHARS_PER_LINE = 33;

    function textScores(s) {
        if (!s) return { total: 0, maxLine: 0, lineCount: 1 };
        var total = 0, lineScore = 0, maxLine = 0, lineCount = 1;
        for (var i = 0, n = s.length; i < n; i++) {
            var c = s.charCodeAt(i);
            if (c === 10 || c === 13) {
                if (lineScore > maxLine) maxLine = lineScore;
                lineScore = 0; lineCount++;
                continue;
            }
            var w;
            if (c === 32 || c === 9) w = 0.5;
            else if (c < 128) w = 1;
            else if (c >= 0x4E00 && c <= 0x9FFF) w = 2;
            else if (c >= 0x3000 && c <= 0x33FF) w = 2;
            else if (c >= 0xFF00 && c <= 0xFFEF) w = 2;
            else if (c < 256) w = 1;
            else w = 2;
            total += w;
            lineScore += w;
        }
        if (lineScore > maxLine) maxLine = lineScore;
        return { total: total, maxLine: maxLine, lineCount: lineCount };
    }

    function textScore(s) { return textScores(s).total; }

    function columnPlainText(doc, roles) {
        var s = '';
        for (var i = 0; i < doc.sections.length; i++) {
            if (roles[doc.sections[i].role]) s += plainTextOf(doc.sections[i].runs);
        }
        return s;
    }

    /** AS2 shouldSplitSmart + merge 兜底同公式。 */
    function shouldSplit(doc) {
        if (!doc) return false;
        var introScore = textScore(plainTextOf(doc.titleRuns))
            + textScore(columnPlainText(doc, { intro: true }));
        var descScore = textScore(columnPlainText(doc, { description: true, body: true }));
        if ((descScore + introScore > SPLIT_THRESHOLD * SMART_TOTAL_MULT)
                && descScore > SPLIT_THRESHOLD / SMART_DESC_DIV) return true;
        if ((descScore + introScore) / MERGE_CHARS_PER_LINE > MERGE_MAX_INTRO_LINES) return true;
        return false;
    }

    // ── document → HTML 渲染 ──
    //
    // 骨架/类名与 PanelTooltip.buildItemRichHtml 输出完全一致（含 kshop-tt-* 别名），
    // ntt-* 只作 document 渲染的语义标记（测试与对比 harness 识别用，零视觉规则）。
    // 文本全转义，不产生白名单外的标签/属性。

    function escapeHtml(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function escapeAttr(s) { return escapeHtml(s).replace(/'/g, '&#39;'); }

    // run → 受限内联标记。嵌套序与 legacy sanitizeAS2Node 对齐：
    // <span style>(color/font-size/font-family) 最外 → <b> → <i> → <u> 最内。
    // 与 as2FontStyle 同款 style 序：color;font-size;font-family。
    function runHtml(run) {
        var inner = escapeHtml(run.text).replace(/\r\n|\r|\n/g, '<br>');
        if (!inner) return '';
        if (run.underline) inner = '<u>' + inner + '</u>';
        if (run.italic) inner = '<i>' + inner + '</i>';
        if (run.bold) inner = '<b>' + inner + '</b>';
        var style = '';
        if (run.color != null) style = 'color:' + run.color;
        if (run.fontSize != null) style += (style ? ';' : '') + 'font-size:' + run.fontSize + 'px';
        var family = mapFontFace(run.fontFace);
        if (family) style += (style ? ';' : '') + 'font-family:' + family;
        if (style) inner = '<span style="' + style + '">' + inner + '</span>';
        return inner;
    }

    function runsHtml(runs) {
        var out = '';
        for (var i = 0; i < runs.length; i++) out += runHtml(runs[i]);
        return out;
    }

    // section 一律渲染为 inline <span class="ntt-sec">（零视觉标记）：
    // 块级 <div> 的边界在 Chromium 行盒/innerText 上会多算一条空行，破坏与
    // legacy intro+meta+desc 纯 inline 拼装的行数对齐（几何对比实测回归）。
    // 相邻 section 之间若前段未以 <br> 收尾，补一个 <br> 保持段落边界。
    function columnHtml(doc, roles) {
        var out = '';
        var atLineStart = false;
        for (var i = 0; i < doc.sections.length; i++) {
            var sec = doc.sections[i];
            if (!roles[sec.role]) continue;
            var inner = runsHtml(sec.runs);
            // 空段保留占位：显式空 section 渲染为一个空行高度（对齐 AS2 空段落语义）
            if (!inner) inner = '<br>';
            if (out && !atLineStart) out += '<br>';
            out += '<span class="ntt-sec ntt-sec--' + sec.role + '">' + inner + '</span>';
            atLineStart = /<br>$/.test(inner);
        }
        return out;
    }

    // doc.icon.name 与 Web Icons manifest 键同源（kind:"item" → 物品键；
    // kind:"skill" → 技能名，manifest 键即技能名本身）。manifest 未就绪/键缺失
    // 时落虚线占位框，不阻断文本。
    function documentIconHtml(doc) {
        if (!doc.icon || !doc.icon.name) return '';
        if (typeof Icons === 'undefined' || !Icons || !Icons.html) return '';
        try {
            // onerror 与 tooltip.js dynamicIconHtml 同款：只隐自身 img，不连累父块
            return Icons.html(doc.icon.name, 'ntt-icon-image',
                ' onerror="this.style.display=\'none\'"');
        } catch (e) {
            return '';
        }
    }

    function documentIconUrl(doc) {
        if (!doc.icon || !doc.icon.name) return null;
        if (typeof Icons === 'undefined' || !Icons || !Icons.resolveStatic) return null;
        try { return Icons.resolveStatic(doc.icon.name); } catch (e) { return null; }
    }

    /**
     * document → 可进 innerHTML 的 HTML；input 非法/无内容 → ''。
     * opts（与 buildItemRichHtml 同一 chrome 合同，全部可选）：
     *   iconHtml / iconUrl / iconPlaceholder / iconFootHTML / metaHTML / suffix /
     *   rootClass / layoutType('wide'|'narrow') / splitMode('auto'|'split'|'merge')
     * icon 解析顺序：opts.iconHtml > opts.iconUrl > opts.iconPlaceholder >
     *   doc.icon（Icons.html(name)，miss → 占位框）。
     * layoutType 解析顺序：opts.layoutType > doc.layoutType > 'wide'（不输出 attr）。
     */
    function buildHtml(input, opts) {
        // 永远重走 normalize：normalized:true 不是可信标记，伪造对象不得绕过
        // version 校验与文本转义路径。
        var doc = normalize(input);
        if (!doc) return '';
        opts = opts || {};

        var iconBlock = '';
        var iconInner = '';
        if (opts.iconHtml) iconInner = String(opts.iconHtml);
        else if (opts.iconUrl) {
            iconInner = '<img src="' + escapeAttr(opts.iconUrl)
                + '" onerror="this.parentNode.style.display=\'none\'">';
        } else if (opts.iconPlaceholder) iconInner = String(opts.iconPlaceholder);
        else if (doc.icon) {
            iconInner = documentIconHtml(doc);
            var iconUrl = iconInner ? null : documentIconUrl(doc);
            if (!iconInner && iconUrl) {
                iconInner = '<img src="' + escapeAttr(iconUrl)
                    + '" onerror="this.parentNode.style.display=\'none\'">';
            }
            if (!iconInner) {
                iconInner = '<div class="flash-tt-icon-placeholder ntt-icon-placeholder"></div>';
            }
        }
        if (iconInner) iconBlock = '<div class="flash-tt-icon kshop-tt-icon ntt-icon">' + iconInner + '</div>';
        if (opts.iconFootHTML) iconBlock += '<div class="flash-tt-icon-foot">' + opts.iconFootHTML + '</div>';

        var titleHtml = doc.titleRuns.length
            ? '<div class="ntt-title">' + runsHtml(doc.titleRuns) + '</div>' : '';
        var introColumn = titleHtml + columnHtml(doc, { intro: true });
        var descColumn = columnHtml(doc, { description: true, body: true });
        var meta = opts.metaHTML || '';

        var splitMode = opts.splitMode || 'auto';
        var doSplit;
        if (splitMode === 'split') doSplit = true;
        else if (splitMode === 'merge') doSplit = false;
        else doSplit = shouldSplit(doc);
        if (!descColumn) doSplit = false;

        var introContent;
        if (doSplit) {
            introContent = introColumn + meta;
        } else {
            // merge：desc 段拼到 intro 末尾，对齐 AS2 <BR> 合并与既有 merge 分隔
            var sep = (introColumn || meta) && descColumn ? '<br><br>' : '';
            introContent = introColumn + meta + sep + descColumn;
        }

        var introInner = introContent
            ? '<div class="flash-tt-intro kshop-tt-intro ntt-intro">' + introContent + '</div>' : '';
        var introPanel = (iconBlock || introInner)
            ? '<div class="flash-tt-intro-panel kshop-tt-intro-panel ntt-intro-panel">' + iconBlock + introInner + '</div>' : '';

        var rootClass = opts.rootClass ? ' ' + opts.rootClass : '';
        var mergeClass = doSplit ? '' : ' flash-tt-rich--merge';
        var layoutType = (opts.layoutType === 'narrow' || opts.layoutType === 'wide')
            ? opts.layoutType : doc.layoutType;
        var layoutAttr = (layoutType === 'narrow') ? ' data-layout="narrow"' : '';
        var html = '<div class="flash-tt-rich kshop-tt-rich ntt-doc' + mergeClass + rootClass + '"'
            + ' data-doc-profile="' + doc.profile + '"' + layoutAttr + '>'
            + introPanel
            + (doSplit && descColumn
                ? '<div class="flash-tt-desc kshop-tt-desc ntt-desc">' + descColumn + '</div>' : '')
            + '</div>';
        if (opts.suffix) html += '<div class="flash-tt-suffix kshop-tt-suffix ntt-suffix">' + opts.suffix + '</div>';
        return html;
    }

    return {
        SUPPORTED_VERSION: SUPPORTED_VERSION,
        normalize: normalize,
        // 兼作"输入可渲染"校验：内部重走 normalize，不信任调用方预归一化对象
        hasContent: function(doc) { return !!normalize(doc); },
        flattenMarkup: flattenMarkup,
        parseColor: parseColor,
        textScore: textScore,
        textScores: textScores,
        shouldSplit: shouldSplit,
        escapeHtml: escapeHtml,
        plainTextOf: plainTextOf,
        buildHtml: buildHtml,
        describe: describe
    };
});
