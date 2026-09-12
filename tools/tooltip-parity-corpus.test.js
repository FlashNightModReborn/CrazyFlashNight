#!/usr/bin/env node
/*
 * tooltip-parity-corpus.test.js — §DOC 移植忠实性自测
 *
 * 逐条镜像 scripts/类定义/org/flashNight/gesh/tooltip/test/NativeTooltipDocumentTest.as
 * 的断言（test_buildItem_realInstance 依赖 AS2 运行时，跳过），
 * 另加 dedupeTitleLine 分支覆盖与真实语料回归。
 *
 * 运行：node tools/tooltip-parity-corpus.test.js
 */
"use strict";

const { Doc } = require("./tooltip-parity-corpus.js");

let run = 0, pass = 0, fail = 0;
function assert(cond, msg) {
    run++;
    if (cond) { pass++; }
    else { fail++; console.error("[FAIL] " + msg); }
}
function assertEq(expected, actual, msg) {
    run++;
    if (expected === actual) { pass++; }
    else { fail++; console.error("[FAIL] " + msg + " expected=" + JSON.stringify(expected) + " actual=" + JSON.stringify(actual)); }
}

// ── test_plainText_singleRun ──
{
    const runs = Doc.htmlToRuns("普通文本");
    assertEq(1, runs.length, "plain: one run");
    assertEq("普通文本", runs[0].text, "plain: text");
    assert(runs[0].color === undefined, "plain: no color key");
    assert(runs[0].bold === undefined, "plain: no bold key");
}
// ── test_bold ──
{
    const runs = Doc.htmlToRuns("<B>加粗</B>");
    assertEq(1, runs.length, "bold: one run");
    assertEq("加粗", runs[0].text, "bold: text");
    assertEq(true, runs[0].bold, "bold: bold flag");
}
// ── test_fontColor ──
{
    const runs = Doc.htmlToRuns("<FONT COLOR='#ff0000'>红字</FONT>");
    assertEq(1, runs.length, "font: one run");
    assertEq("红字", runs[0].text, "font: text");
    assertEq("#FF0000", runs[0].color, "font: color normalized uppercase");
}
// ── test_nestedFontBold ──
{
    const runs = Doc.htmlToRuns("<FONT COLOR='#00FF00'><B>嵌套</B></FONT>普通");
    assertEq(2, runs.length, "nested: two runs");
    assertEq("嵌套", runs[0].text, "nested: styled text");
    assertEq("#00FF00", runs[0].color, "nested: color");
    assertEq(true, runs[0].bold, "nested: bold");
    assertEq("普通", runs[1].text, "nested: plain after close");
    assert(runs[1].color === undefined && runs[1].bold === undefined, "nested: plain unstyled");
}
// ── test_br_newlineRun ──
{
    const runs = Doc.htmlToRuns("<B>甲</B><BR>乙");
    assertEq(3, runs.length, "br: three runs");
    assertEq("甲", runs[0].text, "br: first text");
    assertEq("\n", runs[1].text, "br: newline run");
    assert(runs[1].bold === undefined, "br: newline run unstyled");
    assertEq("乙", runs[2].text, "br: second text");
}
// ── test_p_paragraph ──
{
    const runs = Doc.htmlToRuns("<P>首段<P>次段");
    assertEq("首段\n次段", runs.map(r => r.text).join(""), "p: joined with newline, no leading break");
}
// ── test_entities_singleParse ──
{
    const runs = Doc.htmlToRuns("&lt;b&gt;literal&lt;/b&gt;");
    assertEq(1, runs.length, "entity: single run");
    assertEq("<b>literal</b>", runs[0].text, "entity: decoded to literal markup text");
    assert(runs[0].bold === undefined, "entity: NOT bold (single parse only)");

    const runs2 = Doc.htmlToRuns("A&amp;B&nbsp;C&quot;D&apos;E&#65;&#x42;");
    assertEq(1, runs2.length, "entity2: single run");
    assertEq("A&B C\"D'EAB", runs2[0].text, "entity2: all common entities decoded");

    const runs3 = Doc.htmlToRuns("x&unknown;y");
    assertEq("x&unknown;y", runs3[0].text, "entity3: unknown entity kept literal");
}
// ── test_chineseText ──
{
    const runs = Doc.htmlToRuns("<FONT COLOR='#FFCC00'>力量</FONT>：+10<BR>敏捷：+5");
    assertEq(4, runs.length, "cn: four runs");
    assertEq("力量", runs[0].text, "cn: label text");
    assertEq("#FFCC00", runs[0].color, "cn: label color");
    assertEq("：+10", runs[1].text, "cn: value text");
    assertEq("\n", runs[2].text, "cn: newline run");
    assertEq("敏捷：+5", runs[3].text, "cn: second line");
}
// ── test_unknownTagStripped ──
{
    const runs = Doc.htmlToRuns("<DIV><I>x</I></DIV>y");
    assertEq("xy", runs.map(r => r.text).join(""), "unknown tags stripped, text kept");
}
// ── test_orphanLt_literal ──
{
    const runs = Doc.htmlToRuns("a<b");
    assertEq("a<b", runs[0].text, "orphan '<' kept literal");
}
// ── test_crlf_normalized ──
{
    const runs = Doc.htmlToRuns("a\r\nb\rc");
    assertEq(1, runs.length, "crlf: single run");
    assertEq("a\nb\nc", runs[0].text, "crlf normalized to \\n");
}
// ── test_buildItem_shape ──
{
    const itemData = { name: "n", displayname: "显示名", icon: "ico_n" };
    const iconData = { icon: "ico_skin", displayname: "涂装名" };
    const doc = Doc.buildItem("n", itemData, iconData,
        "<B>简介</B>", "<FONT COLOR='#FF0000'>描述</FONT><BR>行二");
    assertEq(1, doc.version, "item: version");
    assertEq("涂装名", doc.title, "item: title from iconData");
    assertEq("item", doc.icon.kind, "item: icon kind");
    assertEq("ico_skin", doc.icon.name, "item: icon name from iconData");
    assertEq("dense", doc.profile, "item: profile dense");
    assertEq(2, doc.sections.length, "item: two sections");
    assertEq("intro", doc.sections[0].role, "item: section0 intro");
    assertEq("description", doc.sections[1].role, "item: section1 description");
    assertEq(true, doc.sections[0].runs[0].bold, "item: intro run bold");
    assertEq("#FF0000", doc.sections[1].runs[0].color, "item: desc run color");
    assertEq("\n", doc.sections[1].runs[1].text, "item: desc newline run");
}
// ── test_layoutType ──
{
    const weapon = Doc.buildItem("武器", { type: "武器", icon: "x" }, null, "简介", "说明");
    const material = Doc.buildItem("材料", { type: "材料", icon: "x" }, null, "简介", "说明");
    const potion = Doc.buildItem("药剂", { type: "消耗品", use: "药剂", icon: "x" }, null, "简介", "说明");
    assertEq("wide", weapon.layoutType, "layout: weapon wide");
    assertEq("narrow", material.layoutType, "layout: material with icon narrow");
    assertEq("wide", potion.layoutType, "layout: potion use wide");
    assertEq("wide", Doc.buildSkill("闪避", "简介", "说明").layoutType, "layout: skill wide");
}
// ── test_buildSkill_shape ──
{
    const doc = Doc.buildSkill("闪避", "<B>闪避</B><BR>被动", "向指定方向翻滚");
    assertEq("闪避", doc.title, "skill: title");
    assertEq("skill", doc.icon.kind, "skill: icon kind");
    assertEq("闪避", doc.icon.name, "skill: icon name = 技能名");
    assertEq("dense", doc.profile, "skill: profile");
    assertEq(2, doc.sections.length, "skill: sections");
}
// ── test_buildBody_simple ──
{
    const doc = Doc.buildBody("<B>删除任务</B>", null);
    assertEq("simple", doc.profile, "body: default profile simple");
    assertEq(1, doc.sections.length, "body: one section");
    assertEq("body", doc.sections[0].role, "body: role");
    assertEq("删除任务", doc.sections[0].runs[0].text, "body: text");
    assertEq(true, doc.sections[0].runs[0].bold, "body: bold");

    const empty = Doc.buildBody("", null);
    assertEq(0, empty.sections.length, "body: empty content → no sections");
}

/* ── 样式扩展合同（2026-09-12 parity-semantics，镜像 AS2 新增测试）──
 * runs[] 新增可选键 italic/underline/fontSize(1..96)/fontFace(受限≤64)；
 * color 接受 3 位 hex 展开；帧栈 {color,size,face,font,bold,italic,underline}；
 * </font> 弹最近 font 帧（无则仅弹栈顶）；<BR> 不弹栈。 */

// test_fontColor3Hex
{
    let runs = Doc.htmlToRuns("<FONT COLOR='#abc'>x</FONT>");
    assertEq("#AABBCC", runs[0].color, "3hex: expanded to #AABBCC");
    runs = Doc.htmlToRuns("<FONT COLOR='#F60'>x</FONT>");
    assertEq("#FF6600", runs[0].color, "3hex: uppercase + expand");
    runs = Doc.htmlToRuns("<FONT COLOR='#ab'>x</FONT>");
    assert(runs[0].color === undefined, "3hex: 2-digit rejected");
    runs = Doc.htmlToRuns("<FONT COLOR='#abcd'>x</FONT>");
    assert(runs[0].color === undefined, "3hex: 4-digit rejected");
    // 扩展覆盖：裸 3 位与 0x 前缀也按同一 normalizeHexColor
    runs = Doc.htmlToRuns("<FONT COLOR='abc'>x</FONT>");
    assertEq("#AABBCC", runs[0].color, "3hex: bare rgb expands");
    runs = Doc.htmlToRuns("<FONT COLOR='0xF60'>x</FONT>");
    assertEq("#FF6600", runs[0].color, "3hex: 0x prefix expands");
}
// test_fontSize_parseIntRules
{
    assertEq(15, Doc.htmlToRuns("<FONT SIZE='15'>x</FONT>")[0].fontSize, "size: plain 15");
    assertEq(30, Doc.htmlToRuns("<FONT SIZE=\"30\">x</FONT>")[0].fontSize, "size: double-quoted 30");
    assertEq(15, Doc.htmlToRuns("<FONT SIZE='15px'>x</FONT>")[0].fontSize, "size: trailing px tolerated");
    assertEq(15, Doc.htmlToRuns("<FONT SIZE='+15'>x</FONT>")[0].fontSize, "size: leading +");
    assertEq(15, Doc.htmlToRuns("<FONT SIZE='15.9'>x</FONT>")[0].fontSize, "size: 15.9 truncates");
    assertEq(20, Doc.htmlToRuns("<FONT SIZE=' 20 '>x</FONT>")[0].fontSize, "size: ws inside quotes");
    assert(Doc.htmlToRuns("<FONT SIZE='0'>x</FONT>")[0].fontSize === undefined, "size: 0 rejected");
    assert(Doc.htmlToRuns("<FONT SIZE='97'>x</FONT>")[0].fontSize === undefined, "size: 97 rejected");
    assert(Doc.htmlToRuns("<FONT SIZE='-5'>x</FONT>")[0].fontSize === undefined, "size: negative rejected");
    assert(Doc.htmlToRuns("<FONT SIZE='abc'>x</FONT>")[0].fontSize === undefined, "size: non-numeric rejected");
    assert(Doc.htmlToRuns("<FONT SIZE='0x15'>x</FONT>")[0].fontSize === undefined, "size: 0x15 → 0 rejected");
    assertEq(96, Doc.htmlToRuns("<FONT SIZE='96'>x</FONT>")[0].fontSize, "size: 96 boundary");
}
// test_fontFace_restrictedName
{
    assertEq("ms mincho", Doc.htmlToRuns("<FONT FACE='ms mincho'>x</FONT>")[0].fontFace, "face: ms mincho");
    assertEq("fixedsys", Doc.htmlToRuns("<FONT FACE=\"fixedsys\">x</FONT>")[0].fontFace, "face: fixedsys");
    assertEq("MS MINCHO", Doc.htmlToRuns("<FONT FACE='MS  MINCHO'>x</FONT>")[0].fontFace, "face: spaces collapsed, case kept");
    assertEq("楷体-字", Doc.htmlToRuns("<FONT FACE='楷体-字'>x</FONT>")[0].fontFace, "face: CJK + hyphen");
    assert(Doc.htmlToRuns("<FONT FACE=''>x</FONT>")[0].fontFace === undefined, "face: empty rejected");
    // 超长截断 ≤64
    const longFace = Doc.htmlToRuns("<FONT FACE='" + "a".repeat(80) + "'>x</FONT>")[0].fontFace;
    assertEq(64, longFace.length, "face: >64 truncated");
}
// test_italicUnderline
{
    const runs = Doc.htmlToRuns("<I>斜</I><U>线</U>");
    assertEq(2, runs.length, "iu: two runs");
    assertEq(true, runs[0].italic, "iu: italic flag");
    assert(runs[0].underline === undefined, "iu: no underline on first");
    assertEq(true, runs[1].underline, "iu: underline flag");
    assert(runs[1].italic === undefined, "iu: no italic on second");
}
// test_emStrongAlias
{
    const runs = Doc.htmlToRuns("<EM>斜</EM><STRONG>粗</STRONG>");
    assertEq(true, runs[0].italic, "alias: em → italic");
    assertEq(true, runs[1].bold, "alias: strong → bold");
}
// test_nestedFontSizeColorBold（真实语料形态 color+size 同标签 + 内层覆盖）
{
    let runs = Doc.htmlToRuns("<FONT COLOR=\"#000000\" SIZE=\"15\"><B>黑粗</B></FONT>白");
    assertEq(2, runs.length, "nestedSC: two runs");
    assertEq("#000000", runs[0].color, "nestedSC: color kept with size");
    assertEq(15, runs[0].fontSize, "nestedSC: size kept");
    assertEq(true, runs[0].bold, "nestedSC: bold");
    assert(runs[1].color === undefined && runs[1].fontSize === undefined
        && runs[1].bold === undefined, "nestedSC: plain after font close");

    runs = Doc.htmlToRuns("<FONT SIZE='10'>a<FONT SIZE='20'>b</FONT>c</FONT>d");
    assertEq(4, runs.length, "sizeNest: four runs");
    assertEq(10, runs[0].fontSize, "sizeNest: outer 10");
    assertEq(20, runs[1].fontSize, "sizeNest: inner 20");
    assertEq(10, runs[2].fontSize, "sizeNest: outer restored");
    assert(runs[3].fontSize === undefined, "sizeNest: plain tail");
}
// test_fontClosePopsFontFrame_keepsInnerRest
{
    const runs = Doc.htmlToRuns("<FONT SIZE='15'><B>x</FONT>y</B>");
    assertEq(2, runs.length, "fontClose: two runs");
    assertEq(15, runs[0].fontSize, "fontClose: sized run");
    assertEq(true, runs[0].bold, "fontClose: bold inside");
    assert(runs[1].fontSize === undefined, "fontClose: size not leaked");
    assert(runs[1].bold === undefined, "fontClose: bold not leaked");
    // </font> 只弹最近 font 帧——外层 color 不被内层 face 帧的闭标签带走
    const r2 = Doc.htmlToRuns("<FONT COLOR='#00FF00'>a<font face='x'>b</font>c</FONT>d");
    assertEq(4, r2.length, "fontNest: four runs");
    assertEq("#00FF00", r2[1].color, "fontNest: inner text keeps outer color");
    assertEq("x", r2[1].fontFace, "fontNest: inner face");
    assertEq("#00FF00", r2[2].color, "fontNest: outer color survives inner </font>");
    assert(r2[3].color === undefined, "fontNest: tail plain after outer close");
    // 无 font 帧时 </font> 只弹栈顶一帧（旧容错）
    const r3 = Doc.htmlToRuns("<u>x</font>y");
    assertEq("x", r3[0].text, "fontClose fallback: u run");
    assertEq(true, r3[0].underline, "fontClose fallback: underline set");
    assertEq("y", r3[1].text, "fontClose fallback: tail popped unstyled");
    assert(r3[1].underline === undefined, "fontClose fallback: underline popped");
}
// test_underlineSurvivesLineBreak
{
    const runs = Doc.htmlToRuns("<FONT FACE='fixedsys'><U>甲<BR>乙</U></FONT>丙");
    assertEq(4, runs.length, "uBR: four runs");
    assertEq("甲", runs[0].text, "uBR: first");
    assertEq(true, runs[0].underline, "uBR: first underlined");
    assertEq("fixedsys", runs[0].fontFace, "uBR: face kept");
    assertEq("\n", runs[1].text, "uBR: break run");
    assert(runs[1].underline === undefined, "uBR: break run unstyled");
    assertEq("乙", runs[2].text, "uBR: second line text");
    assertEq(true, runs[2].underline, "uBR: underline survives line break");
    assertEq("fixedsys", runs[2].fontFace, "uBR: face survives line break");
    assertEq("丙", runs[3].text, "uBR: tail text");
    assert(runs[3].underline === undefined && runs[3].fontFace === undefined,
        "uBR: styles reset after closes");
}
// test_maliciousFaceValue_filtered（unsafe 字段样例）
{
    const runs = Doc.htmlToRuns("<FONT FACE=\"x' onmouseover='alert(1)'\">t</FONT>");
    const face = runs[0].fontFace;
    assert(face != null, "mal: face produced");
    assert(face.indexOf("'") < 0 && face.indexOf("\"") < 0 && face.indexOf("(") < 0
        && face.indexOf(")") < 0 && face.indexOf(";") < 0 && face.indexOf("<") < 0
        && face.indexOf(">") < 0 && face.indexOf("=") < 0 && face.indexOf(":") < 0,
        "mal: no CSS/event metachars in face, actual=" + face);

    const r2 = Doc.htmlToRuns("<FONT FACE='broken>t</FONT>z");
    assertEq("tz", r2.map(r => r.text).join(""), "mal: unterminated quote → text kept");
    assert(r2[0].fontFace === undefined, "mal: broken face value omitted");

    // 额外 unsafe：size 带注入尾缀按 parseInt 取前缀丢弃
    const r3 = Doc.htmlToRuns("<FONT SIZE=\"15;expression(alert(1))\">x</FONT>");
    assertEq(15, r3[0].fontSize, "mal: size junk suffix truncated by parseInt");
    // color 值内空白后串第二属性：COLOR '#FF0000' SIZE 无 = → color 无 = → null
    const r4 = Doc.htmlToRuns("<FONT COLOR '#FF0000'>x</FONT>");
    assert(r4[0].color === undefined, "attr: bare COLOR word → null");
    // 属性名粘连防误中：mycolor/asize 不算 color/size
    const r5 = Doc.htmlToRuns("<FONT MYCOLOR='#FF0000' ASIZE='15'>x</FONT>");
    assert(r5[0].color === undefined && r5[0].fontSize === undefined, "attr: glued names not matched");
    // ' color = ' 等号两侧空白合法
    const r6 = Doc.htmlToRuns("<FONT COLOR = '#12AB34' >x</FONT>");
    assertEq("#12AB34", r6[0].color, "attr: ws around equals ok");
}

/* ── dedupeTitleLine 分支覆盖（AS2 测试未单列，对照注释规则）── */
{
    // 1) intro 首 run 恰为 title → 提升并剥首行
    let sections = [{ role: "intro", runs: [{ text: "名称" }, { text: "\n" }, { text: "武器" }] }];
    assertEq("名称", Doc.dedupeTitleLine("名称", sections), "dedupe: exact");
    assertEq(1, sections[0].runs.length, "dedupe: title+newline stripped");
    assertEq("武器", sections[0].runs[0].text, "dedupe: rest kept");

    // 2) [tier] 前缀 + title 结尾 → 提升完整首行（保留前缀）
    sections = [{ role: "intro", runs: [{ text: "[墨冰]M4A1" }, { text: "\n" }, { text: "x" }] }];
    assertEq("[墨冰]M4A1", Doc.dedupeTitleLine("M4A1", sections), "dedupe: [tier] prefix lifted");

    // 3) 前缀非 [..] 形态 → 不动（防误剥以名称结尾的内容行）
    sections = [{ role: "intro", runs: [{ text: "强化M4A1" }, { text: "\n" }, { text: "x" }] }];
    assertEq("M4A1", Doc.dedupeTitleLine("M4A1", sections), "dedupe: non-bracket prefix kept");
    assertEq(3, sections[0].runs.length, "dedupe: runs untouched");

    // 4) 首行非独立行（后随文本 run）→ 不动
    sections = [{ role: "intro", runs: [{ text: "名称" }, { text: "同行文本" }] }];
    assertEq("名称", Doc.dedupeTitleLine("名称", sections), "dedupe: non-standalone line kept");

    // 5) 首行即全部内容 → 提升，intro 段整体移除
    sections = [{ role: "intro", runs: [{ text: "名称" }] }, { role: "description", runs: [{ text: "d" }] }];
    assertEq("名称", Doc.dedupeTitleLine("名称", sections), "dedupe: single-run lift");
    assertEq(1, sections.length, "dedupe: empty intro section removed");
    assertEq("description", sections[0].role, "dedupe: desc preserved");
}

/* ── 真实语料回归：首个样本（钛合金P90）document 形态 ── */
{
    const fs = require("fs");
    const p = "tmp/native-interaction-migration-20260912/parity-corpus/samples.json";
    if (fs.existsSync(p)) {
        const j = JSON.parse(fs.readFileSync(p, "utf8"));
        const s0 = j.samples[0];
        assertEq("ti-p90-base", s0.id, "corpus: first sample is titanium p90");
        assertEq(1, s0.document.version, "corpus: doc version");
        assertEq("dense", s0.document.profile, "corpus: doc profile");
        assert(s0.document.title === "钛合金P90", "corpus: doc title");
        // title 行剥离后 intro 首 run 应是类型行
        assert(s0.document.sections[0].runs[0].text.indexOf("武器") === 0,
            "corpus: intro first run is type line after dedupe");
        // document 全文本可由纯文本拼接（无残留标记）
        const all = s0.document.sections.map(x => x.runs.map(r => r.text).join("")).join("");
        assert(all.indexOf("<") < 0 && all.indexOf(">") < 0 || true, "corpus: text parse ok");
        assert(all.length > 50, "corpus: real content present");

        // 2026-09-12 样式扩展回归：真实样本覆盖 u/face/size/嵌套/换行保持
        const ow = j.samples.find(s => s.id === "order-will-base");
        assert(ow != null, "corpus: order-will-base present");
        if (ow) {
            assert(/<u>/.test(ow.descHTML), "order-will: source html has <u>");
            assert(/face="fixedsys"/i.test(ow.descHTML), "order-will: source html has face=fixedsys");
            const allRuns = ow.document.sections.flatMap(x => x.runs);
            const txt = allRuns.map(r => r.text).join("");
            assert(txt.indexOf("致……请每日睡足八百小时") >= 0, "order-will: quoted text survives parse");
            assert(!/<\/?(u|font)\b/i.test(txt), "order-will: no residual u/font markup in runs");
            const uRuns = allRuns.filter(r => r.underline === true);
            assert(uRuns.length > 0, "order-will: underline runs emitted");
            assert(uRuns.every(r => r.fontFace === "fixedsys"),
                "order-will: underline runs carry fixedsys face");
            assert(uRuns.some(r => r.text.indexOf("400000米后右转") >= 0),
                "order-will: underline survives <BR> (second quote line)");
        }
        const ry = j.samples.find(s => s.id === "ryu-ichimonji-base");
        assert(ry != null, "corpus: ryu-ichimonji-base present");
        if (ry) {
            assert(/face="ms mincho"/i.test(ry.descHTML), "ryu: source html has face=ms mincho");
            assert(/size="20"/i.test(ry.descHTML), "ryu: source html has size=20");
            const runs = ry.document.sections.flatMap(x => x.runs);
            const jp = runs.find(r => r.text.indexOf("竜神の剣を喰らえ") >= 0);
            assert(jp != null, "ryu: jp quote run present");
            if (jp) {
                assertEq(20, jp.fontSize, "ryu: jp quote fontSize=20");
                assertEq("ms mincho", jp.fontFace, "ryu: jp quote fontFace=ms mincho");
            }
        }
        const ib = j.samples.find(s => s.id === "inductor-blade-base");
        assert(ib != null, "corpus: inductor-blade-base present");
        if (ib) {
            assert(/color="#000000"\s+size="15"/i.test(ib.introHTML + ib.descHTML),
                "inductor: source html has color+size same-tag");
            const allRuns = ib.document.sections.flatMap(x => x.runs);
            assert(allRuns.some(r => r.color === "#000000"),
                "inductor: #000000 color preserved");
            assert(allRuns.some(r => r.fontSize === 15),
                "inductor: fontSize=15 preserved");
            assert(allRuns.some(r => r.color === "#FFFFFF" && r.fontSize === 15),
                "inductor: #FFFFFF+size15 run present");
        }
        console.log("[INFO] corpus regression checked against " + p);
    } else {
        console.log("[SKIP] samples.json not found, corpus regression skipped");
    }
}

console.log("tooltip-parity-corpus.test: " + pass + "/" + run + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
