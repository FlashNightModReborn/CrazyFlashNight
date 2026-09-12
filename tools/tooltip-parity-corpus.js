#!/usr/bin/env node
/*
 * tooltip-parity-corpus.js — parity-corpus 岗位工具
 *
 * 从真实 AS2 composer 语料（TooltipCorpusDump 的 TC_ITEM trace / 解析后 JSON）
 * 提取 Web 权威 vs Native tooltip 对比所需的样本与确定性场景。
 *
 * 职责边界：
 * - document(v1) 为 scripts/类定义/org/flashNight/gesh/tooltip/NativeTooltipDocument.as
 *   的逐函数忠实 JS 移植（见 §DOC 移植标记，函数名一一对应）。
 * - 物品身份投影按 InventoryPanelService.buildTooltipProjection 语义：
 *   iconData = 实例投影（tier 覆盖后 icon/displayname），itemData = 原始词条。
 *   tier 覆盖 icon/displayname 按 TierSystem.applyTierDataToItem 规则从
 *   data/items/*.xml 的 data_* 块重放（仅 icon/displayname 两字段，不碰数值——
 *   数值文本已在语料 HTML 内，本工具零发明）。
 * - tier 名 → 数据块键映射解析自 data/equipment/equipment_config.xml <TierMapping>。
 * - 图标解析自 launcher/web/icons/manifest.json + launcher/web/icons/ 下 WebP 尺寸。
 * - 语料新旧判定：物品源 XML / 配件定义文件的 git 最后提交与 mtime 对语料采集时间。
 *
 * 用法：
 *   node tools/tooltip-parity-corpus.js --corpus <json|trace> --out <dir>
 *   默认 --corpus tmp/native-interaction-migration-20260912/parity-corpus-fresh.json
 *        --out    tmp/native-interaction-migration-20260912/parity-corpus
 */
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { execFileSync } = require("child_process");

const REPO_ROOT = path.resolve(__dirname, "..");
const rel = (p) => path.relative(REPO_ROOT, p).replace(/\\/g, "/");
const abs = (p) => path.resolve(REPO_ROOT, p);

function parseArgs(argv) {
    const args = {
        corpus: "tmp/native-interaction-migration-20260912/parity-corpus-fresh.json",
        out: "tmp/native-interaction-migration-20260912/parity-corpus",
        manifest: "launcher/web/icons/manifest.json",
        iconsDir: "launcher/web/icons",
        itemsDir: "data/items",
        equipConfig: "data/equipment/equipment_config.xml",
        setsFile: "data/items/item_sets.xml",
    };
    for (let i = 2; i < argv.length; i++) {
        const k = argv[i].replace(/^--/, "");
        if (i + 1 < argv.length && !argv[i + 1].startsWith("--")) args[k] = argv[++i];
        else args[k] = true;
    }
    return args;
}

function git(args) {
    try {
        return execFileSync("git", args, { cwd: REPO_ROOT, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 }).trim();
    } catch (e) {
        return null;
    }
}

const sha256 = (s) => crypto.createHash("sha256").update(s, "utf8").digest("hex");

/* ════════════════════════════════════════════════════════════════════
 * §DOC — NativeTooltipDocument.as 忠实移植（逐函数对应，勿改语义）
 * 源：scripts/类定义/org/flashNight/gesh/tooltip/NativeTooltipDocument.as
 * ════════════════════════════════════════════════════════════════════ */
const Doc = (() => {
    const ROLE_INTRO = "intro";
    const ROLE_DESCRIPTION = "description";
    const ROLE_BODY = "body";
    const PROFILE_SIMPLE = "simple";
    const PROFILE_DENSE = "dense";

    // buildItem：title/icon 优先取 iconData（实例投影），回退 itemData（原始词条）
    function buildItem(name, itemData, iconData, introHtml, descHtml) {
        let iconName = null;
        let title = null;
        if (iconData != null) {
            if (iconData.icon !== undefined && iconData.icon !== "") iconName = String(iconData.icon);
            if (iconData.displayname !== undefined && iconData.displayname !== "") title = String(iconData.displayname);
        }
        if (iconName == null && itemData != null
                && itemData.icon !== undefined && itemData.icon !== "") {
            iconName = String(itemData.icon);
        }
        if (title == null && itemData != null
                && itemData.displayname !== undefined && itemData.displayname !== "") {
            title = String(itemData.displayname);
        }
        if (title == null) title = name;

        const sections = [];
        pushSection(sections, ROLE_INTRO, introHtml);
        pushSection(sections, ROLE_DESCRIPTION, descHtml);
        title = dedupeTitleLine(title, sections);
        const icon = (iconName != null) ? { kind: "item", name: iconName } : null;
        const doc = buildSectioned(title, icon, sections, PROFILE_DENSE);
        let typeName = (itemData != null && itemData.type !== undefined) ? String(itemData.type) : "";
        if (typeName === "消耗品" && itemData.use !== undefined) typeName = String(itemData.use);
        doc.layoutType = (typeName === "武器" || typeName === "防具" || typeName === "技能" || typeName === "药剂") ? "wide" : "narrow";
        return doc;
    }

    function buildSkill(skillName, introHtml, descHtml) {
        const sections = [];
        pushSection(sections, ROLE_INTRO, introHtml);
        pushSection(sections, ROLE_DESCRIPTION, descHtml);
        const icon = (skillName != null && skillName !== "")
            ? { kind: "skill", name: String(skillName) } : null;
        const doc = buildSectioned(dedupeTitleLine(skillName, sections), icon, sections, PROFILE_DENSE);
        doc.layoutType = "wide";
        return doc;
    }

    function buildBody(bodyHtml, profile) {
        const sections = [];
        pushSection(sections, ROLE_BODY, bodyHtml);
        return buildSectioned(null, null, sections,
            (profile != null && profile !== "") ? profile : PROFILE_SIMPLE);
    }

    function buildSectioned(title, icon, sections, profile) {
        const doc = { version: 1 };
        if (title != null && title !== "") doc.title = String(title);
        if (icon != null && icon.name !== undefined && icon.name !== "") {
            doc.icon = {
                kind: (icon.kind !== undefined && icon.kind !== "") ? String(icon.kind) : "item",
                name: String(icon.name)
            };
        }
        doc.profile = (profile != null && profile !== "") ? String(profile) : PROFILE_SIMPLE;
        doc.sections = (sections != null) ? sections : [];
        return doc;
    }

    function makeSection(role, html) {
        return { role: role, runs: htmlToRuns(html) };
    }

    function pushSection(sections, role, html) {
        const section = makeSection(role, html);
        if (section.runs.length > 0) sections.push(section);
    }

    // dedupeTitleLine：intro 首行与 title 相等或以 [tier] 前缀 + title 结尾，
    // 且首行是独立标题行（后随 "\n" run 或首行即全部）→ 提升为 title 并剥离
    function dedupeTitleLine(title, sections) {
        if (title == null || title === "" || sections == null || sections.length === 0) return title;
        const sec = sections[0];
        if (sec.role !== ROLE_INTRO || sec.runs == null || sec.runs.length === 0) return title;
        const first = String(sec.runs[0].text);
        let match = (first === title);
        if (!match && first.length > title.length
                && first.substring(first.length - title.length) === title) {
            const prefix = first.substring(0, first.length - title.length);
            match = prefix.length > 2
                && prefix.charAt(0) === "["
                && prefix.charAt(prefix.length - 1) === "]";
        }
        if (!match) return title;
        if (sec.runs.length > 1 && sec.runs[1].text !== "\n") return title;
        const rest = sec.runs.slice(1);
        if (rest.length > 0 && rest[0].text === "\n") rest.shift();
        if (rest.length === 0) sections.shift();
        else sec.runs = rest;
        return first;
    }

    // htmlToRuns：受限标记 → run 栈解析
    //   <BR>/<P>/<FONT color|size|face>/<B|STRONG>/<I|EM>/<U> + 实体；其余剥离
    //   样式帧栈：{color?,size?,face?,font,bold,italic,underline}
    //   <FONT> 压 font:true 帧；</FONT> 弹到最近 font 帧（无则仅弹栈顶）
    //   </B|STRONG>/</I|EM>/</U> 弹到最近对应置位帧；无匹配容错忽略
    //   <BR> 产无样式 "\n" run 且不弹栈（<u>甲<BR>乙</u> 乙仍 underline）
    function htmlToRuns(html) {
        const runs = [];
        if (html == null) return runs;
        const s = String(html);
        const len = s.length;
        if (len === 0) return runs;

        const stack = [];
        let pending = "";
        let i = 0;

        while (i < len) {
            const code = s.charCodeAt(i);

            if (code === 60) { // '<'
                const tagEndIndex = s.indexOf(">", i + 1);
                if (tagEndIndex < 0) {
                    pending += "<";
                    i++;
                    continue;
                }
                const tagBody = s.substring(i + 1, tagEndIndex);
                const kind = classifyTag(tagBody);
                if (kind === 1) { // <BR>
                    pending = flushPending(runs, pending, stack);
                    pushRun(runs, "\n", null, false, false, false, NaN, null);
                } else if (kind === 2) { // <P>
                    pending = flushPending(runs, pending, stack);
                    if (runs.length > 0) pushRun(runs, "\n", null, false, false, false, NaN, null);
                } else if (kind === 3) { // <FONT ...>
                    pending = flushPending(runs, pending, stack);
                    stack.push({
                        color: parseFontColor(tagBody),
                        size: parseFontSize(tagBody),
                        face: parseFontFace(tagBody),
                        font: true, bold: false, italic: false, underline: false
                    });
                } else if (kind === 4) { // </FONT>
                    pending = flushPending(runs, pending, stack);
                    popStyle(stack, "font");
                } else if (kind === 5) { // <B>/<STRONG>
                    pending = flushPending(runs, pending, stack);
                    stack.push({ bold: true });
                } else if (kind === 6) { // </B>/</STRONG>
                    pending = flushPending(runs, pending, stack);
                    popStyle(stack, "bold");
                } else if (kind === 7) { // <I>/<EM>
                    pending = flushPending(runs, pending, stack);
                    stack.push({ italic: true });
                } else if (kind === 8) { // </I>/</EM>
                    pending = flushPending(runs, pending, stack);
                    popStyle(stack, "italic");
                } else if (kind === 9) { // <U>
                    pending = flushPending(runs, pending, stack);
                    stack.push({ underline: true });
                } else if (kind === 10) { // </U>
                    pending = flushPending(runs, pending, stack);
                    popStyle(stack, "underline");
                }
                // kind === 0：剥离未知标签
                i = tagEndIndex + 1;
                continue;
            }

            if (code === 38) { // '&'
                const semi = s.indexOf(";", i + 1);
                if (semi > i && semi - i <= 10) {
                    const decoded = decodeEntity(s.substring(i + 1, semi));
                    if (decoded != null) {
                        pending += decoded;
                        i = semi + 1;
                        continue;
                    }
                }
                pending += "&";
                i++;
                continue;
            }

            if (code === 13) { // '\r' / '\r\n' → '\n'
                pending += "\n";
                i++;
                if (i < len && s.charCodeAt(i) === 10) i++;
                continue;
            }

            pending += s.charAt(i);
            i++;
        }
        flushPending(runs, pending, stack);
        return runs;
    }

    function flushPending(runs, pending, stack) {
        if (pending.length > 0) {
            pushRun(runs, pending, currentColor(stack), currentBold(stack),
                currentFlag(stack, "italic"), currentFlag(stack, "underline"),
                currentFontSize(stack), currentFontFace(stack));
        }
        return "";
    }

    function pushRun(runs, text, color, bold, italic, underline, fontSize, fontFace) {
        if (text == null || text.length === 0) return;
        const run = { text: text };
        if (color != null && color !== "") run.color = color;
        if (bold === true) run.bold = true;
        if (italic === true) run.italic = true;
        if (underline === true) run.underline = true;
        if (!isNaN(fontSize)) run.fontSize = fontSize;
        if (fontFace != null && fontFace !== "") run.fontFace = fontFace;
        runs.push(run);
    }

    function currentColor(stack) {
        for (let i = stack.length - 1; i >= 0; i--) {
            if (stack[i].color != null) return stack[i].color;
        }
        return null;
    }

    function currentBold(stack) {
        return currentFlag(stack, "bold");
    }

    // flag 类样式（bold/italic/underline）：任一存活帧置位即生效
    function currentFlag(stack, flag) {
        for (let i = stack.length - 1; i >= 0; i--) {
            if (stack[i][flag] === true) return true;
        }
        return false;
    }

    // size/face 类属性：栈顶向下取首个定义该属性的帧（内层覆盖外层）
    function currentFontSize(stack) {
        for (let i = stack.length - 1; i >= 0; i--) {
            if (stack[i].size != null && !isNaN(stack[i].size)) return stack[i].size;
        }
        return NaN;
    }

    function currentFontFace(stack) {
        for (let i = stack.length - 1; i >= 0; i--) {
            if (stack[i].face != null && stack[i].face !== "") return stack[i].face;
        }
        return null;
    }

    // 按标记弹栈：font→最近 font 帧，bold/italic/underline→最近置位帧（含其上所有帧）
    // font 无匹配仍弹栈顶一帧（沿用旧容错）；其余无匹配忽略
    function popStyle(stack, flag) {
        for (let i = stack.length - 1; i >= 0; i--) {
            if (stack[i][flag] === true) {
                stack.splice(i);
                return;
            }
        }
        if (flag === "font" && stack.length > 0) stack.pop();
    }

    // classifyTag：0=剥离 1=<BR> 2=<P> 3=<FONT> 4=</FONT> 5=<B|STRONG> 6=</B|STRONG>
    //              7=<I|EM> 8=</I|EM> 9=<U> 10=</U>；大小写不敏感
    function classifyTag(tagBody) {
        if (tagBody == null) return 0;
        const t = trimBlank(tagBody);
        if (t.length === 0) return 0;
        const closing = (t.charAt(0) === "/");
        let name = closing ? t.substring(1) : t;
        let end = name.length;
        for (let k = 0; k < name.length; k++) {
            const c = name.charCodeAt(k);
            if (c === 32 || c === 9 || c === 10 || c === 13 || c === 47) { // 空白或 '/'
                end = k;
                break;
            }
        }
        name = name.substring(0, end).toLowerCase();

        if (name === "br") return 1;
        if (name === "p") return closing ? 0 : 2;
        if (name === "font") return closing ? 4 : 3;
        if (name === "b" || name === "strong") return closing ? 6 : 5;
        if (name === "i" || name === "em") return closing ? 8 : 7;
        if (name === "u") return closing ? 10 : 9;
        return 0;
    }

    // readFontAttr：<FONT> 属性值抽取——name 前必须是串首/空白/'/'，name 后必须是
    // 空白或 '='（防 mycolor/asize 粘连）；'=' 与值间只允许空白；值取引号内或首个
    // 非空白 token；无效/缺失返回 null
    function readFontAttr(tagBody, name) {
        if (tagBody == null) return null;
        const lower = tagBody.toLowerCase();
        const nameLen = name.length;
        let from = 0;
        while (true) {
            const idx = lower.indexOf(name, from);
            if (idx < 0) return null;
            if (idx > 0) {
                const prev = lower.charCodeAt(idx - 1);
                if (!(prev === 32 || prev === 9 || prev === 10 || prev === 13 || prev === 47)) {
                    from = idx + 1;
                    continue;
                }
            }
            const after = idx + nameLen;
            if (after < lower.length) {
                const nc = lower.charCodeAt(after);
                if (!(nc === 32 || nc === 9 || nc === 10 || nc === 13 || nc === 61)) { // ws 或 '='
                    from = idx + 1;
                    continue;
                }
            }
            const attributeEqualsAt = tagBody.indexOf("=", after);
            if (attributeEqualsAt < 0) return null;
            const mid = tagBody.substring(after, attributeEqualsAt);
            let clean = true;
            for (let m = 0; m < mid.length; m++) {
                const mc = mid.charCodeAt(m);
                if (!(mc === 32 || mc === 9 || mc === 10 || mc === 13)) { clean = false; break; }
            }
            if (!clean) { from = after; continue; } // '=' 属于别的属性，找下一处 name
            let tail = trimEdge(tagBody.substring(attributeEqualsAt + 1), " \t\r\n");
            if (tail.length === 0) return null;
            const quote = tail.charAt(0);
            if (quote === "'" || quote === "\"") {
                const qend = tail.indexOf(quote, 1);
                if (qend < 0) return null;
                return tail.substring(1, qend);
            }
            let vend = 0;
            while (vend < tail.length && " \t\r\n".indexOf(tail.charAt(vend)) < 0) vend++;
            return tail.substring(0, vend);
        }
    }

    // parseFontColor：<FONT> COLOR → 规范化 "#RRGGBB"；无效 null
    function parseFontColor(tagBody) {
        return normalizeHexColor(readFontAttr(tagBody, "color"));
    }

    // normalizeHexColor：#RRGGBB/RRGGBB/0xRRGGBB → "#RRGGBB"；#RGB 三位逐位
    // 翻倍展开（对齐 Web legacy as2FontStyle 3/6 位 hex 白名单）；其余 null
    function normalizeHexColor(value) {
        if (value == null) return null;
        let hex = trimEdge(value, " \t\r\n");
        if (hex.charAt(0) === "#") {
            hex = hex.substring(1);
        } else if (hex.length > 2 && hex.substring(0, 2).toLowerCase() === "0x") {
            hex = hex.substring(2);
        }
        if (hex.length === 3) {
            hex = hex.charAt(0) + hex.charAt(0)
                + hex.charAt(1) + hex.charAt(1)
                + hex.charAt(2) + hex.charAt(2);
        }
        if (hex.length !== 6) return null;
        for (let k = 0; k < 6; k++) {
            const c = hex.charCodeAt(k);
            const isHex = (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
            if (!isHex) return null;
        }
        return "#" + hex.toUpperCase();
    }

    // parseFontSize：<FONT SIZE> → 1..96 整数。JS parseInt(_,10) 语义：前导空白、
    // 可选 +/-、取前导十进制数字（"15px"→15、"+15"→15、"15.9"→15、无数字→NaN），
    // 再按 Web legacy px>0 && px<=96 判定。无效 NaN
    function parseFontSize(tagBody) {
        const raw = readFontAttr(tagBody, "size");
        if (raw == null) return NaN;
        let i = 0;
        const n = raw.length;
        while (i < n && isSpaceCode(raw.charCodeAt(i))) i++;
        let sign = 1;
        if (i < n) {
            const sc = raw.charCodeAt(i);
            if (sc === 43) i++;            // '+'
            else if (sc === 45) { sign = -1; i++; } // '-'
        }
        let v = 0;
        let digits = 0;
        while (i < n) {
            const c = raw.charCodeAt(i);
            if (c < 48 || c > 57) break;
            v = v * 10 + (c - 48);
            digits++;
            i++;
        }
        if (digits === 0) return NaN;
        v *= sign;
        return (v >= 1 && v <= 96) ? v : NaN;
    }

    // parseFontFace：<FONT FACE> → 受限字体名：仅留 [0-9A-Za-z_]/CJK U+4E00..9FA5/
    // 空格/'-'（与 Web legacy face.replace(/[^\w一-龥 \-]/g,'') 同款），连续空格折叠、
    // 去首尾、≤64 字符；全过滤空 → null。产出是字体名而非 CSS 片段
    function parseFontFace(tagBody) {
        const raw = readFontAttr(tagBody, "face");
        if (raw == null) return null;
        let out = "";
        const n = raw.length;
        for (let i = 0; i < n; i++) {
            const c = raw.charCodeAt(i);
            if (c === 32) { // 空格：折叠为单个，且不留首尾
                if (out.length > 0 && out.charCodeAt(out.length - 1) !== 32) out += " ";
                continue;
            }
            if (isFaceChar(c)) out += String.fromCharCode(c);
            // 其余字符（含 \t\n 等）直接剥除
        }
        while (out.length > 0 && out.charCodeAt(out.length - 1) === 32) {
            out = out.substring(0, out.length - 1);
        }
        if (out.length > 64) out = out.substring(0, 64);
        return (out.length > 0) ? out : null;
    }

    // face 白名单字符：[0-9A-Za-z_]/CJK U+4E00..U+9FA5/'-'（空格单独处理）
    function isFaceChar(c) {
        return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
            || c === 95 || c === 45 || (c >= 0x4E00 && c <= 0x9FA5);
    }

    // JS \s 等价集（parseInt 前导空白跳过用）
    function isSpaceCode(c) {
        return c === 32 || (c >= 9 && c <= 13) || c === 0xA0 || c === 0x1680
            || (c >= 0x2000 && c <= 0x200A) || c === 0x2028 || c === 0x2029
            || c === 0x202F || c === 0x205F || c === 0x3000 || c === 0xFEFF;
    }

    // decodeEntity：amp/lt/gt/quot/apos/nbsp + &#NN; / &#xHH;；未知 null
    function decodeEntity(entity) {
        if (entity == null || entity.length === 0) return null;
        const lower = entity.toLowerCase();
        if (lower === "amp") return "&";
        if (lower === "lt") return "<";
        if (lower === "gt") return ">";
        if (lower === "quot") return "\"";
        if (lower === "apos") return "'";
        if (lower === "nbsp") return " ";
        if (entity.charAt(0) === "#") {
            const hex = entity.length > 1 && (entity.charAt(1) === "x" || entity.charAt(1) === "X");
            const digits = entity.substring(hex ? 2 : 1);
            if (digits.length === 0) return null;
            let v = 0;
            for (let d = 0; d < digits.length; d++) {
                const dc = digits.charCodeAt(d);
                let digit;
                if (dc >= 48 && dc <= 57) digit = dc - 48;
                else if (hex && dc >= 65 && dc <= 70) digit = dc - 55;
                else if (hex && dc >= 97 && dc <= 102) digit = dc - 87;
                else return null;
                v = hex ? v * 16 + digit : v * 10 + digit;
                if (v > 0xFFFF) return null;
            }
            return String.fromCharCode(v);
        }
        return null;
    }

    function trimBlank(s) {
        return trimEdge(s, " \t\r\n");
    }

    function trimEdge(s, chars) {
        let a = 0;
        let b = s.length;
        while (a < b && chars.indexOf(s.charAt(a)) >= 0) a++;
        while (b > a && chars.indexOf(s.charAt(b - 1)) >= 0) b--;
        return s.substring(a, b);
    }

    return { buildItem, buildSkill, buildBody, buildSectioned, makeSection, htmlToRuns,
             dedupeTitleLine, classifyTag, parseFontColor, parseFontSize, parseFontFace,
             normalizeHexColor, readFontAttr, decodeEntity };
})();

/* ════════════════════════════════════════════════════════════════════
 * §XML — data/items/*.xml 索引与 tier 身份块（仅 icon/displayname 重放）
 * ════════════════════════════════════════════════════════════════════ */

function decodeXmlEntities(s) {
    if (s == null) return s;
    return s.replace(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);/g, (m, e) => Doc.decodeEntity(e) || m);
}

function extractTag(block, tag) {
    const m = block.match(new RegExp("<" + tag + ">([\\s\\S]*?)</" + tag + ">"));
    return m ? decodeXmlEntities(m[1].replace(/^\s+|\s+$/g, "")) : null;
}

// 解析单个 items XML 文本 → [{name,displayname,icon,type,use,tiers:{dataKey:{icon?,displayname?}}}]
function parseItemsXml(text) {
    const items = [];
    const itemRe = /<item\b[^>]*>([\s\S]*?)<\/item>/g;
    let m;
    while ((m = itemRe.exec(text)) !== null) {
        const body = m[1];
        // 先抽 data_* 顶层块（tier 覆盖），再从剩余文本取顶层字段
        const tiers = {};
        const stripped = body.replace(/<(data(?:_\w+)?)>([\s\S]*?)<\/\1>/g, (whole, key, inner) => {
            if (key !== "data") {
                const icon = extractTag(inner, "icon");
                const displayname = extractTag(inner, "displayname");
                tiers[key] = {};
                if (icon != null) tiers[key].icon = icon;
                if (displayname != null) tiers[key].displayname = displayname;
            }
            return "";
        });
        const name = extractTag(stripped, "name");
        if (name == null) continue;
        items.push({
            name,
            displayname: extractTag(stripped, "displayname"),
            icon: extractTag(stripped, "icon"),
            type: extractTag(stripped, "type"),
            use: extractTag(stripped, "use"),
            tiers,
        });
    }
    return items;
}

// equipment_config.xml → {tierName → dataKey}
function parseTierNameToKey(text) {
    const map = {};
    const re = /<TierMapping\b[^>]*\bname="([^"]+)"[^>]*\bkey="([^"]+)"/g;
    let m;
    while ((m = re.exec(text)) !== null) map[decodeXmlEntities(m[1])] = m[2];
    // 属性顺序兜底（key 在前 name 在后的写法）
    const re2 = /<TierMapping\b[^>]*\bkey="([^"]+)"[^>]*\bname="([^"]+)"/g;
    while ((m = re2.exec(text)) !== null) map[decodeXmlEntities(m[2])] = m[1];
    return map;
}

/* ════════════════════════════════════════════════════════════════════
 * §ICON — manifest + WebP 尺寸
 * ════════════════════════════════════════════════════════════════════ */

function webpSize(buf) {
    if (buf.length < 16 || buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WEBP") return null;
    const fourcc = buf.toString("ascii", 12, 16);
    if (fourcc === "VP8X" && buf.length >= 30) {
        const w = (buf[24] | (buf[25] << 8) | (buf[26] << 16)) + 1;
        const h = (buf[27] | (buf[28] << 8) | (buf[29] << 16)) + 1;
        return { width: w, height: h, format: "VP8X" };
    }
    if (fourcc === "VP8 " && buf.length >= 30) {
        // lossy：3B frame tag + 9D 01 2A + w/h (14bit LE)
        if (buf[23] === 0x9D && buf[24] === 0x01 && buf[25] === 0x2A) {
            const w = buf[26] | ((buf[27] & 0x3F) << 8);
            const h = buf[28] | ((buf[29] & 0x3F) << 8);
            return { width: w, height: h, format: "VP8" };
        }
        return null;
    }
    if (fourcc === "VP8L" && buf.length >= 25) {
        if (buf[20] !== 0x2F) return null;
        const b0 = buf[21], b1 = buf[22], b2 = buf[23], b3 = buf[24];
        const w = 1 + (((b1 & 0x3F) << 8) | b0);
        const h = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6));
        return { width: w, height: h, format: "VP8L" };
    }
    return null;
}

function aspectOf(w, h) {
    if (!w || !h) return "unknown";
    const r = w / h;
    return r >= 1.4 ? "wide" : (r <= 0.72 ? "tall" : "square");
}

/* ════════════════════════════════════════════════════════════════════
 * §CORPUS — trace / JSON 读取（TC_ITEM 16 列，¶→\n ¤→\r）
 * ════════════════════════════════════════════════════════════════════ */

function unescapeField(s) {
    return s.replace(/¶/g, "\n").replace(/¤/g, "\r");
}

function parseTrace(text) {
    const records = [];
    let runId = null;
    let summary = null;
    for (const line of text.split(/\r?\n/)) {
        if (line.startsWith("TOOLTIP_CORPUS_BEGIN|")) {
            runId = line.split("|")[1] || null;
            continue;
        }
        if (line.startsWith("TC_TOTAL|")) {
            summary = {};
            for (const kv of line.slice(9).split("|")) {
                const eq = kv.indexOf("=");
                if (eq > 0) summary[kv.slice(0, eq)] = Number(kv.slice(eq + 1));
            }
            continue;
        }
        if (!line.startsWith("TC_ITEM|")) continue;
        const c = line.slice(8).split("|");
        if (c.length < 16) continue;
        const modsField = unescapeField(c[7]);
        records.push({
            id: Number(c[0]),
            variant: c[1],
            name: unescapeField(c[2]),
            displayName: unescapeField(c[3]),
            type: unescapeField(c[4]),
            use: unescapeField(c[5]),
            tier: unescapeField(c[6]),
            mods: modsField ? modsField.split(",").filter(Boolean) : [],
            icon: unescapeField(c[8]),
            modslot: c[9] === "" ? null : Number(c[9]),
            tierOptions: Number(c[10]) || 0,
            authorChars: Number(c[11]) || 0,
            split: c[12] === "1" || c[12] === "true",
            introHTML: unescapeField(c[13]),
            descHTML: unescapeField(c[14]),
            introChars: Number(c[15]) || 0,
        });
    }
    return { schema: "cf7.tooltip-corpus.v1", runId, summary, records };
}

function loadCorpus(file) {
    const text = fs.readFileSync(abs(file), "utf8");
    if (/\.json$/i.test(file)) {
        const j = JSON.parse(text);
        let runId = (j.meta && j.meta.runId) || j.runId || null;
        // JSON 无 runId 时尝试同名 .trace 的 TOOLTIP_CORPUS_BEGIN 头
        if (runId == null) {
            const traceFile = file.replace(/\.json$/i, ".trace");
            if (fs.existsSync(abs(traceFile))) {
                const head = fs.readFileSync(abs(traceFile), "utf8").split(/\r?\n/, 8).join("\n");
                const m = head.match(/TOOLTIP_CORPUS_BEGIN\|(\S+)/);
                if (m) runId = m[1];
            }
        }
        return { data: j, runId, summary: j.summary || null, records: j.records };
    }
    const t = parseTrace(text);
    return { data: t, runId: t.runId, summary: t.summary, records: t.records };
}

/* ════════════════════════════════════════════════════════════════════
 * §FRESHNESS — 语料采集时点之后的源数据漂移标注（不重建内容，只标注）
 * ════════════════════════════════════════════════════════════════════ */

function buildFreshnessChecker(corpusMtime) {
    const lastCommitCache = new Map();
    const mtimeCache = new Map();
    const dirtySet = new Set((git(["status", "--porcelain", "--", "data", "scripts/类定义"]) || "")
        .split("\n").map(l => l.slice(3).trim()).filter(Boolean));

    function lastCommitISO(file) {
        if (!lastCommitCache.has(file)) {
            const out = git(["log", "-1", "--format=%cI", "--", file]);
            lastCommitCache.set(file, out || null);
        }
        return lastCommitCache.get(file);
    }
    function fileMtime(file) {
        if (!mtimeCache.has(file)) {
            try { mtimeCache.set(file, fs.statSync(abs(file)).mtime.toISOString()); }
            catch (e) { mtimeCache.set(file, null); }
        }
        return mtimeCache.get(file);
    }
    function checkFile(file) {
        // 返回 null | {file, reason[]}
        if (!file) return null;
        const reasons = [];
        const lc = lastCommitISO(file);
        if (lc && lc > corpusMtime) reasons.push("commit-after-corpus:" + lc);
        const mt = fileMtime(file);
        if (mt && mt > corpusMtime) reasons.push("mtime-after-corpus:" + mt);
        if (dirtySet.has(file)) reasons.push("worktree-dirty");
        return reasons.length ? { file, reasons } : null;
    }
    return { checkFile, dirtySet };
}

/* ════════════════════════════════════════════════════════════════════
 * §SAMPLES — 样本选择（首个钛合金P90；其余覆盖维度见 coverageTags）
 * ════════════════════════════════════════════════════════════════════ */

// 匹配字段：name + variant (+tier +modsCount +mod 名)；找首个匹配记录
const SAMPLE_SPEC = [
    { id: "ti-p90-base",     match: { name: "钛合金P90", variant: "base" },
      tags: ["mandated-first", "weapon", "pistol", "cn"],
      note: "指定首样本：钛合金 P90 基础态" },
    { id: "ti-p90-mods1",    match: { name: "钛合金P90", variant: "mods-1", mods: ["KM型消声器"] },
      tags: ["mandated-first", "weapon", "pistol", "mod-real", "cn"],
      note: "钛合金 P90 + 真实配件 KM型消声器（消音覆盖路径）" },
    { id: "p90-print-base",  match: { name: "P90印花集", variant: "base" },
      tags: ["weapon", "pistol", "icon-identity-diverge", "cn"],
      note: "静态 icon 键≠name 的真实投影样本（icon=钛合金P90）" },
    { id: "macs3-base", match: { name: "MACSIII", variant: "base" },
      tags: ["human-regression", "weapon", "long-gun", "melee", "long-desc"],
      note: "人验反例：基础态长说明必须与 Web 使用相同的检视触发规则" },
    { id: "blood-sword-base", match: { name: "血色光剑天秤", variant: "base" },
      tags: ["human-regression", "weapon", "blade", "skill-text", "long-desc"],
      note: "人验反例：结构化技能说明不得输出对象字符串" },
    { id: "macs3-tier-cond", match: { name: "MACSIII", variant: "tier", tier: "冷凝" },
      tags: ["weapon", "long-gun", "melee", "tier-identity-override", "very-long-desc", "skill-text", "en-name"],
      note: "冷凝进阶：displayname/icon 覆盖为 MACSIV，desc 692 字符+内嵌技能块" },
    { id: "macs3-mods1",     match: { name: "MACSIII", variant: "mods-1" },
      tags: ["weapon", "long-gun", "melee", "mod-real", "en-name"],
      note: "近战长枪 + 真实配件实例" },
    { id: "m4a1-mods3",      match: { name: "M4A1", variant: "mods-3" },
      tags: ["weapon", "long-gun", "multi-color-max", "mod-real-3", "en-name"],
      note: "三配件实例，语料内 FONT 颜色密度最高一档" },
    { id: "m4a1-tier-ice",   match: { name: "M4A1", variant: "tier", tier: "墨冰" },
      tags: ["weapon", "long-gun", "tier-identity-override", "en-name"],
      note: "墨冰涂装进阶：标题 [墨冰] 前缀 + icon 覆盖" },
    { id: "dominator-base",  match: { name: "dominator", variant: "base" },
      tags: ["weapon", "pistol", "en-name", "long-desc"],
      note: "英文内部名 + 长描述（~596 字符）" },
    { id: "cheatengine-base", match: { name: "CheatEngine", variant: "base" },
      tags: ["armor", "neck", "en-name"],
      note: "颈部装备，英文名防具" },
    { id: "pencil-base",     match: { name: "pencil", variant: "base" },
      tags: ["weapon", "blade", "en-name"],
      note: "英文名短兵器" },
    { id: "firecracker-base", match: { name: "鞭炮", variant: "base" },
      tags: ["consumable", "grenade", "short-desc", "cn", "narrow"],
      note: "最短描述档（2 字符），narrow 消耗品" },
    { id: "m202-base",       match: { name: "M202火箭发射器", variant: "base" },
      tags: ["weapon", "launcher", "short-desc", "mixed-cn-en"],
      note: "发射器类 + 极短描述" },
    { id: "retreat-base",    match: { name: "退路", variant: "base" },
      tags: ["weapon", "pistol", "short-desc", "cn"],
      note: "手枪 + 极短描述" },
    { id: "armor-tier",      match: { name: "黑丝灰色格子短裙", variant: "tier" },
      tags: ["armor", "tier", "cn"],
      note: "防具进阶实例（displayname/icon 与 name 分离的词条）" },
    { id: "armor-mods",      match: { name: "红外夜视仪", variant: "mods-1" },
      tags: ["armor", "head", "mod-real", "cn"],
      note: "防具 + 真实配件实例" },
    { id: "potion-hp-base",  match: { name: "普通hp药剂", variant: "base" },
      tags: ["consumable", "potion", "wide-by-use", "mixed-cn-en"],
      note: "消耗品/药剂 → layoutType=wide（use 替换 type 的分类路径）" },
    { id: "material-km-base", match: { name: "KM型消声器", variant: "base" },
      tags: ["material", "mod-material", "long-desc", "narrow", "cn"],
      note: "材料/配件物品本体：narrow 布局 + 308 字符说明" },
    { id: "intel-sewer-base", match: { name: "下水道探索报告", variant: "base" },
      tags: ["intel", "collectible", "narrow", "cn"],
      note: "收集品/情报类 narrow 样本" },
    { id: "money-base",      match: { name: "金币", variant: "base" },
      tags: ["consumable", "currency", "displayname-diverge", "narrow", "cn"],
      note: "displayname(金钱)≠name(金币) 的投影样本" },
    { id: "type79-modscover", match: { name: "TYPE79", variant: "mods-cover", mods: ["战术导轨"] },
      tags: ["weapon", "long-gun", "mod-coverage", "en-name"],
      note: "modCoverage 变体（106 配件定义逐一真实安装路径）" },
    { id: "order-will-base", match: { name: "指令意志", variant: "base" },
      tags: ["weapon", "blade", "u-tag", "font-face", "multi-color", "cn"],
      note: "desc 含 <u> 与 face=\"fixedsys\" 遗留标记（census: underline 全语料仅此物品）" },
    { id: "ryu-ichimonji-base", match: { name: "龍一文字", variant: "base" },
      tags: ["weapon", "blade", "font-face", "font-size", "jp-text", "cn"],
      note: "desc 含 size=20 + face=ms mincho 嵌套零色帧与日文引文" },
    { id: "inductor-blade-base", match: { name: "电感切割刃", variant: "base" },
      tags: ["weapon", "blade", "color-size-sametag", "cn"],
      note: "color=\"#000000\" size=\"15\" 同标签真实实例——root parseFontColor 修复的直接回归" },
];

function matchSpec(records, spec) {
    return records.find(r => {
        const m = spec.match;
        if (r.name !== m.name || r.variant !== m.variant) return false;
        if (m.tier !== undefined && r.tier !== m.tier) return false;
        if (m.mods !== undefined) {
            if (!Array.isArray(r.mods) || r.mods.length !== m.mods.length) return false;
            for (const mod of m.mods) if (r.mods.indexOf(mod) < 0) return false;
        }
        return true;
    }) || null;
}

/* ════════════════════════════════════════════════════════════════════
 * §SCENARIOS — 确定性位置 × 视口 × dpi 矩阵
 * ════════════════════════════════════════════════════════════════════ */

function mulberry32(seed) {
    let a = seed >>> 0;
    return function () {
        a |= 0; a = (a + 0x6D2B79F5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function buildScenarios() {
    // Flash 逻辑 1024×576 坐标；边缘/临界点位按 tooltip.js 语义选取：
    //   VIEWPORT_INSET=8, ANCHOR_GAP=10, POINTER_EXCLUSION=16，四侧打分制。
    const positions = [
        { id: "center",              x: 512,  y: 288, kind: "fixed" },
        { id: "corner-tl",           x: 16,   y: 16,  kind: "fixed" },
        { id: "corner-tr",           x: 1008, y: 16,  kind: "fixed" },
        { id: "corner-bl",           x: 16,   y: 560, kind: "fixed" },
        { id: "corner-br",           x: 1008, y: 560, kind: "fixed" },
        { id: "edge-top",            x: 512,  y: 16,  kind: "fixed" },
        { id: "edge-right",          x: 1008, y: 288, kind: "fixed" },
        { id: "edge-bottom",         x: 512,  y: 560, kind: "fixed" },
        { id: "edge-left",           x: 16,   y: 288, kind: "fixed" },
        { id: "crit-flip-left-3rd",  x: 341,  y: 288, kind: "fixed" }, // 1/3 界：左/右候选竞争区
        { id: "crit-flip-right-3rd", x: 683,  y: 288, kind: "fixed" }, // 2/3 界
        { id: "crit-bottom-band",    x: 512,  y: 540, kind: "fixed" }, // 底侧可行性翻转带
        { id: "crit-wide-right",     x: 900,  y: 200, kind: "fixed" }, // 宽面板被迫左侧/stacked
        { id: "extreme-zero",        x: 0,    y: 0,   kind: "fixed" },
        { id: "extreme-max",         x: 1024, y: 576, kind: "fixed" },
    ];
    // seed 随机点位（确定性 mulberry32，种子固定；生成后写死坐标供复核）
    const rng = mulberry32(20260912);
    for (let k = 0; k < 4; k++) {
        const x = Math.round(32 + rng() * (1024 - 64));
        const y = Math.round(32 + rng() * (576 - 64));
        positions.push({ id: "rand-" + (k + 1), x, y, kind: "seeded", seed: 20260912 });
    }

    const viewports = [
        { id: "v1024",       w: 1024, h: 576,  dpi: 1 },
        { id: "v1600",       w: 1600, h: 900,  dpi: 1 },
        { id: "v1920",       w: 1920, h: 1080, dpi: 1 },
        { id: "v1600-d125",  w: 1600, h: 900,  dpi: 1.25 },
        { id: "v1920-d150",  w: 1920, h: 1080, dpi: 1.5 },
    ];

    const scenarios = [];
    const push = (pos, vp, extra) => {
        scenarios.push(Object.assign({
            id: pos.id + "@" + vp.id,
            positionId: pos.id,
            viewport: { w: vp.w, h: vp.h, dpi: vp.dpi },
            anchor: { x: pos.x, y: pos.y },
            profile: "dense",
            scrollLines: 0,
            placement: null,
            phase: "matrix",
        }, extra || {}));
    };
    const byId = (id) => positions.find(p => p.id === id);
    const fixed = positions.filter(p => p.kind === "fixed");
    const seeded = positions.filter(p => p.kind === "seeded");

    // 主矩阵：全部固定点位 @1024；P90-first 相位小集合（主样本先跑）用 phase 标记
    const p90First = new Set(["center", "corner-tr", "corner-br", "edge-right",
                            "crit-flip-left-3rd", "crit-flip-right-3rd", "crit-bottom-band", "crit-wide-right"]);
    for (const p of fixed) {
        push(p, viewports[0], p90First.has(p.id) ? { phase: "p90-first" } : undefined);
    }
    // 边界点位 @1600/@1920
    const boundary = ["corner-tl", "corner-tr", "corner-bl", "corner-br",
                      "edge-right", "edge-bottom", "crit-flip-right-3rd"];
    for (const id of boundary) { push(byId(id), viewports[1]); push(byId(id), viewports[2]); }
    // dpi 组合：1600@1.25 / 1920@1.5，各 3 个代表点位
    for (const id of ["center", "corner-br", "edge-right"]) {
        push(byId(id), viewports[3]);
        push(byId(id), viewports[4]);
    }
    // seed 随机：@1024 全量 + @1600 前两个
    for (const p of seeded) push(p, viewports[0]);
    for (const p of seeded.slice(0, 2)) push(p, viewports[1]);
    // placement 偏好覆盖：center@1024 四向
    for (const pl of ["left", "right", "top", "bottom"]) {
        push(byId("center"), viewports[0],
            { id: "center-place-" + pl + "@v1024", placement: pl });
    }
    // 滚动行数覆盖：dense 下滚动 3/5 行
    push(byId("center"), viewports[0], { id: "center-scroll3@v1024", scrollLines: 3 });
    push(byId("center"), viewports[0], { id: "center-scroll5@v1024", scrollLines: 5 });

    return {
        schema: "cf7.tooltip-parity-scenarios.v1",
        anchors: "Flash 逻辑 1024x576 坐标；clientX=anchor.x*viewport.w/1024, clientY=anchor.y*viewport.h/576（与 FlashCoordinateMapper 同源）",
        seed: 20260912,
        positions,
        viewports,
        scenarios,
    };
}

/* ════════════════════════════════════════════════════════════════════
 * §MAIN
 * ════════════════════════════════════════════════════════════════════ */

module.exports = { Doc, parseItemsXml, parseTierNameToKey, webpSize, parseTrace, buildScenarios };

function main() {
    const args = parseArgs(process.argv);
    const corpusFile = args.corpus;
    const outDir = abs(args.out);
    const corpusStat = fs.statSync(abs(corpusFile));
    const corpusMtime = corpusStat.mtime.toISOString();
    const corpus = loadCorpus(corpusFile);
    const records = corpus.records;
    if (!Array.isArray(records) || records.length === 0) {
        console.error("语料为空或不可解析: " + corpusFile);
        process.exit(1);
    }

    const repoBaseline = git(["rev-parse", "HEAD"]);
    const worktreeDirty = (git(["status", "--porcelain"]) || "").length > 0;

    // ── 物品 XML 索引（当前工作区；tier 身份块仅取 icon/displayname）──
    const itemIndex = new Map(); // name → {file, displayname, icon, type, use, tiers}
    const itemsDirAbs = abs(args.itemsDir);
    for (const f of fs.readdirSync(itemsDirAbs)) {
        if (!f.endsWith(".xml")) continue;
        const relFile = rel(path.join(itemsDirAbs, f));
        const text = fs.readFileSync(path.join(itemsDirAbs, f), "utf8");
        for (const it of parseItemsXml(text)) {
            if (!itemIndex.has(it.name)) itemIndex.set(it.name, Object.assign({ file: relFile }, it));
        }
    }
    // 配件定义索引：mod 名 → equipment_mods/*.xml 文件
    const modDefIndex = new Map();
    const modsDirAbs = path.join(itemsDirAbs, "equipment_mods");
    if (fs.existsSync(modsDirAbs)) {
        for (const f of fs.readdirSync(modsDirAbs)) {
            if (!f.endsWith(".xml")) continue;
            const relFile = rel(path.join(modsDirAbs, f));
            const text = fs.readFileSync(path.join(modsDirAbs, f), "utf8");
            const re = /<mod\b[^>]*>([\s\S]*?)<\/mod>/g;
            let m;
            while ((m = re.exec(text)) !== null) {
                const n = extractTag(m[1], "name");
                if (n != null && !modDefIndex.has(n)) modDefIndex.set(n, relFile);
            }
        }
    }
    // tier 名 → 数据块键
    const tierNameToKey = parseTierNameToKey(fs.readFileSync(abs(args.equipConfig), "utf8"));

    // ── 图标 manifest ──
    const manifestText = fs.readFileSync(abs(args.manifest), "utf8");
    const manifest = JSON.parse(manifestText);
    const manifestSha = sha256(manifestText);
    const iconsDirAbs = abs(args.iconsDir);
    function resolveIcon(name) {
        const entry = manifest[name];
        if (entry == null) return { name, inManifest: false };
        let uri = null;
        if (typeof entry === "string") uri = entry;
        else if (entry.uri) uri = entry.uri;
        else if (entry.f1) uri = entry.f1;
        else if (Array.isArray(entry.frames) && entry.frames[0]) uri = entry.frames[0].uri || entry.frames[0];
        if (uri == null) return { name, inManifest: true, uri: null, exists: false };
        const p = path.join(iconsDirAbs, uri);
        let exists = fs.existsSync(p), size = null;
        if (exists) {
            const buf = fs.readFileSync(p);
            size = webpSize(buf.slice(0, 64));
        }
        return {
            name, inManifest: true, uri,
            path: "icons/" + uri, exists,
            width: size ? size.width : null,
            height: size ? size.height : null,
            aspect: size ? aspectOf(size.width, size.height) : "unknown",
        };
    }

    const freshness = buildFreshnessChecker(corpusMtime);

    // ── 选择样本 ──
    const samples = [];
    const misses = [];
    for (const spec of SAMPLE_SPEC) {
        const rec = matchSpec(records, spec);
        if (!rec) { misses.push(spec.id + " ← " + JSON.stringify(spec.match)); continue; }

        const xmlItem = itemIndex.get(rec.name) || null;
        // tier 身份重放：tierData.icon/displayname 覆盖（applyTierDataToItem 顶层规则）
        let identityOverride = null;
        if (rec.variant === "tier" && rec.tier && xmlItem) {
            const tierKey = tierNameToKey[rec.tier] || null;
            const block = tierKey && xmlItem.tiers ? xmlItem.tiers[tierKey] : null;
            if (block && (block.icon != null || block.displayname != null)) {
                identityOverride = { tier: rec.tier, key: tierKey };
                if (block.icon != null) identityOverride.icon = block.icon;
                if (block.displayname != null) identityOverride.displayname = block.displayname;
            }
        }
        const projection = {
            displayname: identityOverride && identityOverride.displayname != null
                ? identityOverride.displayname : rec.displayName,
            icon: identityOverride && identityOverride.icon != null
                ? identityOverride.icon : rec.icon,
        };
        const itemData = { icon: rec.icon, displayname: rec.displayName, type: rec.type, use: rec.use };
        const document = Doc.buildItem(rec.name, itemData, projection, rec.introHTML, rec.descHTML);
        // buildTooltipProjection 同款 itemType：消耗品→use 替换
        let itemType = rec.type;
        if (itemType === "消耗品" && rec.use !== undefined) itemType = rec.use;

        const iconInfo = resolveIcon(document.icon ? document.icon.name : null);

        // 新鲜度/漂移标注
        const depDrift = [];
        if (xmlItem) {
            const d = freshness.checkFile(xmlItem.file);
            if (d) depDrift.push(d);
        } else {
            depDrift.push({ file: null, reasons: ["item-xml-not-found"] });
        }
        const seenDepFiles = new Set();
        for (const mod of rec.mods || []) {
            const mf = modDefIndex.get(mod);
            const d = freshness.checkFile(mf);
            if (d) {
                if (seenDepFiles.has(d.file)) continue;
                seenDepFiles.add(d.file);
                depDrift.push(Object.assign({ mod }, d));
            } else if (!mf) depDrift.push({ mod, file: null, reasons: ["mod-def-not-found"] });
        }
        if ((rec.introHTML + rec.descHTML).indexOf("套装") >= 0) {
            const d = freshness.checkFile(args.setsFile);
            if (d) depDrift.push(Object.assign({ dep: "item_sets" }, d));
        }
        const identityDrift = xmlItem
            && (xmlItem.icon !== rec.icon || xmlItem.displayname !== rec.displayName);

        samples.push({
            id: spec.id,
            corpusId: rec.id,
            variant: rec.variant,
            name: rec.name,
            displayName: projection.displayname,
            itemType,
            itemUse: rec.use,
            tier: rec.tier || "",
            mods: rec.mods || [],
            modslot: rec.modslot,
            tierOptions: rec.tierOptions,
            split: rec.split === true,
            layoutType: document.layoutType,
            icon: document.icon ? { kind: document.icon.kind, name: document.icon.name } : null,
            iconAsset: iconInfo,
            introHTML: rec.introHTML,
            descHTML: rec.descHTML,
            document,
            provenance: {
                corpusRecordId: rec.id,
                corpusTrace: rel(abs(corpusFile)),
                sourceItemXml: xmlItem ? xmlItem.file : null,
                composerIdentity: "TooltipComposer.generateIntroPanelContent/generateItemDescriptionText",
                documentBy: "tooltip-parity-corpus.js §DOC port of NativeTooltipDocument.as",
                identityReplay: identityOverride || null,
                sourceHtmlSha256: sha256(rec.introHTML + "" + rec.descHTML),
            },
            freshness: {
                stale: depDrift.length > 0 || identityDrift === true,
                identityDrift: identityDrift === true,
                depDrift,
            },
            coverageTags: spec.tags,
            note: spec.note,
        });
    }

    // ── 验证 ──
    const errors = [];
    const seenIds = new Set();
    const allowedViewports = new Set(["1024x576", "1600x900", "1920x1080"]);
    for (const s of samples) {
        if (seenIds.has(s.id)) errors.push("dup id " + s.id);
        seenIds.add(s.id);
        if (!s.name) errors.push(s.id + ": empty name");
        if (!s.itemType) errors.push(s.id + ": empty itemType");
        if (s.itemUse === undefined) errors.push(s.id + ": missing itemUse");
        if (typeof s.introHTML !== "string" || s.introHTML.length === 0) errors.push(s.id + ": empty introHTML");
        if (typeof s.descHTML !== "string" || s.descHTML.length === 0) errors.push(s.id + ": empty descHTML");
        const d = s.document;
        if (!d || d.version !== 1) errors.push(s.id + ": document.version!==1");
        if (!d.profile) errors.push(s.id + ": document.profile missing");
        if (!Array.isArray(d.sections) || d.sections.length === 0) errors.push(s.id + ": no sections");
        if (d.layoutType !== "wide" && d.layoutType !== "narrow") errors.push(s.id + ": bad layoutType " + d.layoutType);
        if (s.layoutType !== d.layoutType) errors.push(s.id + ": layoutType mismatch top/doc");
        if (d.icon && s.icon && d.icon.name !== s.icon.name) errors.push(s.id + ": icon mismatch");
        if (!s.iconAsset || !s.iconAsset.inManifest) errors.push(s.id + ": icon not in manifest: " + (s.icon && s.icon.name));
        else if (!s.iconAsset.exists) errors.push(s.id + ": icon asset missing: " + s.iconAsset.path);
        // document 纯文本不含未解码实体 / 残留标记（一次性投影自检）
        for (const sec of d.sections) {
            for (const run of sec.runs) {
                if (/<\/?(font|b|br|p|i|em|u|strong)\b/i.test(run.text)) errors.push(s.id + ": run text residual markup: " + run.text.slice(0, 40));
                if (/&(amp|lt|gt|quot|apos|nbsp|#\d+|#x[0-9a-fA-F]+);/i.test(run.text)) errors.push(s.id + ": run text residual entity: " + run.text.slice(0, 40));
                if (run.color !== undefined && !/^#[0-9A-F]{6}$/.test(run.color)) errors.push(s.id + ": bad color " + run.color);
                if (run.bold !== undefined && run.bold !== true) errors.push(s.id + ": non-true bold");
                if (run.italic !== undefined && run.italic !== true) errors.push(s.id + ": non-true italic");
                if (run.underline !== undefined && run.underline !== true) errors.push(s.id + ": non-true underline");
                if (run.fontSize !== undefined
                        && (!Number.isInteger(run.fontSize) || run.fontSize < 1 || run.fontSize > 96))
                    errors.push(s.id + ": bad fontSize " + run.fontSize);
                if (run.fontFace !== undefined
                        && (typeof run.fontFace !== "string" || run.fontFace.length === 0 || run.fontFace.length > 64))
                    errors.push(s.id + ": bad fontFace " + JSON.stringify(run.fontFace));
            }
        }
    }
    const scen = buildScenarios();
    const seenScen = new Set();
    for (const sc of scen.scenarios) {
        if (seenScen.has(sc.id)) errors.push("dup scenario " + sc.id);
        seenScen.add(sc.id);
        if (sc.anchor.x < 0 || sc.anchor.x > 1024 || sc.anchor.y < 0 || sc.anchor.y > 576)
            errors.push(sc.id + ": anchor out of logical range");
        if (!allowedViewports.has(sc.viewport.w + "x" + sc.viewport.h))
            errors.push(sc.id + ": viewport not allowed");
    }

    // ── 输出 ──
    const samplesDoc = {
        schema: "cf7.tooltip-parity-samples.v1",
        provenance: {
            source: "AS2 TooltipCorpusDump TC_ITEM trace → " + rel(abs(corpusFile)),
            composerIdentity: "org.flashNight.gesh.tooltip.TooltipComposer + NativeTooltipDocument.buildItem",
            corpusSchema: corpus.data.schema || null,
            corpusRunId: corpus.runId,
            corpusSummary: corpus.summary,
            corpusMtime,
            repoBaseline,
            worktreeDirty,
            iconManifest: rel(abs(args.manifest)),
            iconManifestSha256: manifestSha,
            documentBuilder: "JS port §DOC of NativeTooltipDocument.as (worktree)",
            tierIdentityReplay: "data/equipment/equipment_config.xml TierMapping + data/items/*.xml data_* blocks (icon/displayname only)",
            generatedAt: new Date().toISOString(),
            generator: "tools/tooltip-parity-corpus.js",
        },
        samples,
    };

    fs.mkdirSync(outDir, { recursive: true });
    const samplesPath = path.join(outDir, "samples.json");
    const scenPath = path.join(outDir, "scenarios.json");
    fs.writeFileSync(samplesPath, JSON.stringify(samplesDoc, null, 2) + "\n", "utf8");
    fs.writeFileSync(scenPath, JSON.stringify(scen, null, 2) + "\n", "utf8");

    // ── 摘要 ──
    console.log("== tooltip-parity-corpus ==");
    console.log("corpus: " + corpusFile + " (" + records.length + " records, runId=" + corpus.runId + ")");
    console.log("samples: " + samples.length + " selected, " + misses.length + " missed");
    for (const m of misses) console.log("  MISS " + m);
    for (const s of samples) {
        const flag = s.freshness.stale ? " STALE:" + s.freshness.depDrift.map(d => d.file || d.mod || d.dep).join(",") : "";
        console.log("  " + s.id.padEnd(20) + " corpus#" + String(s.corpusId).padEnd(5)
            + " " + s.layoutType + " icon=" + (s.icon ? s.icon.name : "none")
            + " asset=" + (s.iconAsset.exists ? s.iconAsset.path : "MISSING") + flag);
    }
    console.log("scenarios: " + scen.scenarios.length
        + " (positions=" + scen.positions.length + ", viewports=" + scen.viewports.length + ")");
    console.log("wrote: " + rel(samplesPath));
    console.log("wrote: " + rel(scenPath));
    if (errors.length) {
        console.log("VALIDATION ERRORS (" + errors.length + "):");
        for (const e of errors) console.log("  " + e);
        process.exit(2);
    }
    console.log("validation: OK");
}

if (require.main === module) main();
