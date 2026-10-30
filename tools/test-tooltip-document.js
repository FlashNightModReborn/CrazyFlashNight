'use strict';

// 定向 Node 测试：launcher/web/modules/tooltip-document.js
// 覆盖 COMMON tooltip document 归一化、受限标记展开、分栏决策与 HTML 渲染。
// 纯逻辑无 DOM 依赖；不启动浏览器/游戏。

const assert = require('assert');
const Doc = require('../launcher/web/modules/tooltip-document.js');

let passed = 0;
function test(name, run) {
    run();
    passed++;
    process.stdout.write('ok - ' + name + '\n');
}

const FULL_DOC = {
    version: 1,
    title: 'M4A1-消音',
    icon: { kind: 'item', name: 'M4A1' },
    profile: 'dense',
    sections: [
        { role: 'intro', runs: [
            { text: 'M4A1-消音', bold: true },
            { text: '\n武器    步枪\n$20000\n等级限制：10\n' },
            { text: '伤害加成：' },
            { text: '+15%', color: '#FFCC00' }
        ] },
        { role: 'description', runs: [
            { text: '制式步枪的消音改进型。\n' },
            { text: '消音效果', color: '#9999FF' },
            { text: '：攻击时有 90% 几率不触发敌人仇恨' }
        ] }
    ]
};

const PAYLOAD = {
    kind: 'tooltip', op: 'show', version: 1,
    requestId: 'tt.req.7', sceneId: 'tt.scene.7', x: 612, y: 340,
    document: FULL_DOC
};

// ── normalize ──

test('normalize 完整 payload：桥身份 + 锚点齐全', () => {
    const doc = Doc.normalize(PAYLOAD);
    assert(doc, 'payload 应归一化成功');
    assert.strictEqual(doc.version, 1);
    assert.strictEqual(doc.requestId, 'tt.req.7');
    assert.strictEqual(doc.sceneId, 'tt.scene.7');
    assert.strictEqual(doc.owner, null);
    assert.strictEqual(doc.revision, 0);
    assert.strictEqual(doc.hasAnchor, true);
    assert.strictEqual(doc.anchorX, 612);
    assert.strictEqual(doc.anchorY, 340);
    assert.strictEqual(doc.profile, 'dense');
    assert.strictEqual(doc.title, 'M4A1-消音');
    assert.deepStrictEqual(doc.icon, { kind: 'item', name: 'M4A1' });
    assert.strictEqual(doc.sections.length, 2);
});

test('normalize 裸 document 节点（退化形态）', () => {
    const doc = Doc.normalize(FULL_DOC);
    assert(doc, '裸 document 应归一化成功');
    assert.strictEqual(doc.requestId, null);
    assert.strictEqual(doc.hasAnchor, false);
});

test('normalize：version 非 1 拒绝', () => {
    assert.strictEqual(Doc.normalize({ version: 2, title: 'x' }), null);
    assert.strictEqual(Doc.normalize({ version: '2', title: 'x' }), null);
    assert.strictEqual(Doc.normalize({ version: 0, title: 'x' }), null);
});

test('normalize：version 两层校验——payload v1 不能掩盖 document v2', () => {
    assert.strictEqual(
        Doc.normalize({ version: 1, document: { version: 2, title: 'x' } }), null);
    assert.strictEqual(
        Doc.normalize({ version: 2, document: { version: 1, title: 'x' } }), null);
    const ok = Doc.normalize({ version: 1, document: { version: 1, title: 'x' } });
    assert(ok, '两层都 v1 应通过');
    assert.strictEqual(ok.title, 'x');
    // document 不显式带 version 时按缺省 1 放行（对齐 C# ReadInt 缺省）
    assert(Doc.normalize({ version: 1, document: { title: 'x' } }));
});

test('normalize：无可渲染内容拒绝', () => {
    assert.strictEqual(Doc.normalize({ version: 1 }), null);
    assert.strictEqual(Doc.normalize({ version: 1, sections: [] }), null);
    assert.strictEqual(Doc.normalize(null), null);
    assert.strictEqual(Doc.normalize('str'), null);
    assert.strictEqual(Doc.normalize({ version: 1, sections: [{ role: 'intro', runs: [] }] }), null);
});

test('normalize：不突变输入对象', () => {
    const raw = JSON.parse(JSON.stringify(FULL_DOC));
    Doc.normalize(raw);
    assert.deepStrictEqual(raw, FULL_DOC);
});

test('normalize：未知 role 归入 body，不丢内容', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'weird-role', runs: [{ text: '保留内容' }] }
    ] });
    assert(doc);
    assert.strictEqual(doc.sections[0].role, 'body');
    assert.strictEqual(doc.sections[0].runs[0].text, '保留内容');
});

test('normalize：profile 大小写容错 + 缺省 simple', () => {
    const p = (v) => Doc.normalize({ version: 1, title: 'x', profile: v }).profile;
    assert.strictEqual(p('dense'), 'dense');
    assert.strictEqual(p('PINNED'), 'pinned');
    assert.strictEqual(p('Dense'), 'dense');
    assert.strictEqual(p(undefined), 'simple');
    assert.strictEqual(p('bogus'), 'simple');
});

test('normalize：icon 缺 kind 按 item；缺 name 则 icon 为空', () => {
    // 裸 document 门检要求 sections/title 其一（对齐 C#），icon-only 带 title
    const a = Doc.normalize({ version: 1, title: 'x', icon: { name: 'M4A1' } });
    assert.deepStrictEqual(a.icon, { kind: 'item', name: 'M4A1' });
    const b = Doc.normalize({ version: 1, title: 'x', icon: { kind: 'item' } });
    assert.strictEqual(b.icon, null);
});

test('normalize：run 可为裸字符串', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: ['纯字符串 run'] }
    ] });
    assert(doc);
    assert.strictEqual(doc.sections[0].runs[0].text, '纯字符串 run');
});

test('normalize：sections/runs 非数组不拆字符串（防 "abc"→三个 run）', () => {
    const doc = Doc.normalize({ version: 1, title: 'x', sections: 'not-array' });
    assert(doc);           // title 本身即有内容
    assert.strictEqual(doc.sections.length, 0);
    const doc2 = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: 'abc' }
    ] });
    assert.strictEqual(doc2, null);   // 无内容 → 拒绝
});

test('normalize：空 run 段保留占位', () => {
    const doc = Doc.normalize({ version: 1, title: 'x', sections: [
        { role: 'intro', runs: [] }
    ] });
    assert(doc);
    assert.strictEqual(doc.sections.length, 1);
    assert.strictEqual(doc.sections[0].runs.length, 0);
});

test('normalize：伪造 normalized 标记不绕过校验', () => {
    const forged = { normalized: true, sections: 'bad', titleRuns: 'bad' };
    const out = Doc.normalize(forged);
    // 结构非法 → 不当已归一化对象直通；按普通输入走（无 title/sections → null）
    assert.strictEqual(out, null);
});

test('normalize：伪造 normalized + 合法外形仍被重新校验/转义', () => {
    // 不可信输入带 normalized:true + 非法 version → 仍拒绝
    assert.strictEqual(Doc.normalize({
        normalized: true, version: 2, title: 'x', sections: [], titleRuns: []
    }), null);
    // 带 normalized:true 且字段齐全 → 重新逐字归一化，text 不因为标记被解析
    const out = Doc.normalize({
        normalized: true, version: 1, title: '<b>t</b>',
        titleRuns: [{ text: '伪造' }],
        sections: [{ role: 'intro', runs: [{ text: 'a<b>b' }] }]
    });
    assert(out);
    // titleRuns 输入字段不被采信——从 title 重建
    assert.strictEqual(out.titleRuns.length, 1);
    assert.strictEqual(out.titleRuns[0].text, '<b>t</b>');
    assert.strictEqual(out.sections[0].runs[0].text, 'a<b>b');
    // buildHtml 同样不走直通：伪造对象渲染时标记字符仍被转义
    const html = Doc.buildHtml({
        normalized: true, version: 1, title: 'x',
        sections: [{ role: 'intro', runs: [{ text: '<img src=x>' }] }]
    });
    assert(html.indexOf('<img') < 0);
    assert(html.indexOf('&lt;img') >= 0);
});

test('normalize 纯文本契约：title/runs.text 字面量 <b>/&amp; 逐字保留', () => {
    const doc = Doc.normalize({ version: 1,
        title: '<b>M4</b>&amp;消音',
        sections: [{ role: 'intro', runs: [
            { text: '字面<b>不是</b>标记' },
            { text: 'A&amp;B&lt;x&gt;' }
        ] }] });
    assert(doc);
    assert.strictEqual(doc.title, '<b>M4</b>&amp;消音');
    assert.strictEqual(doc.titleRuns.length, 1);
    assert.strictEqual(doc.titleRuns[0].text, '<b>M4</b>&amp;消音');
    assert.strictEqual(doc.titleRuns[0].bold, true);  // 标题 run 恒定 bold，非解析产物
    assert.strictEqual(doc.sections[0].runs[0].text, '字面<b>不是</b>标记');
    assert.strictEqual(doc.sections[0].runs[0].bold, false);
    assert.strictEqual(doc.sections[0].runs[0].color, null);
    assert.strictEqual(doc.sections[0].runs[1].text, 'A&amp;B&lt;x&gt;');
});

test('buildHtml 纯文本契约：字面标记字符转义渲染，不被当标签', () => {
    const html = Doc.buildHtml({ version: 1,
        title: '<b>M4</b>',
        sections: [{ role: 'intro', runs: [{ text: 'A&amp;B' }] }] });
    assert(html.indexOf('&lt;b&gt;M4&lt;/b&gt;') >= 0,
        '字面 <b> 在 title 中必须转义为文本');
    assert(html.indexOf('A&amp;amp;B') >= 0,
        '字面 &amp; 必须转义为 &amp;amp; 显示原文');
    assert(html.indexOf('A&') < 0 || html.indexOf('A&amp;amp;') >= 0);
});

test('buildHtml：已含转义形态的文本逐字渲染（不二次解码）', () => {
    // 上游若给出 "&lt;b&gt;" 字符串，渲染后应显示为字面 "&lt;b&gt;"
    const html = Doc.buildHtml({ version: 1, sections: [{ role: 'body',
        runs: [{ text: '&lt;b&gt;' }] }] });
    assert(html.indexOf('&amp;lt;b&amp;gt;') >= 0);
    // normalize→buildHtml 往返：normalized 文档再次 buildHtml 结果一致
    const doc = Doc.normalize({ version: 1, title: '<b>t</b>',
        sections: [{ role: 'intro', runs: [{ text: 'a&amp;b' }] }] });
    assert.strictEqual(Doc.buildHtml(doc), Doc.buildHtml({
        version: 1, title: '<b>t</b>',
        sections: [{ role: 'intro', runs: [{ text: 'a&amp;b' }] }] }));
});

// ── parseColor ──

test('parseColor：#RRGGBB / RRGGBB / 0xRRGGBB → #RRGGBB 大写归一', () => {
    assert.strictEqual(Doc.parseColor('#ffcc00'), '#FFCC00');
    assert.strictEqual(Doc.parseColor('FFCC00'), '#FFCC00');
    assert.strictEqual(Doc.parseColor('0xffcc00'), '#FFCC00');
    // 3 位 hex 按 Web legacy as2FontStyle 支持面规范化为 6 位（root 约定）
    assert.strictEqual(Doc.parseColor('#FFF'), '#FFFFFF');
    assert.strictEqual(Doc.parseColor('#f00'), '#FF0000');
    assert.strictEqual(Doc.parseColor('red'), null);
    assert.strictEqual(Doc.parseColor(''), null);
    assert.strictEqual(Doc.parseColor(null), null);
    assert.strictEqual(Doc.parseColor('#GGGGGG'), null);
});

// ── flattenMarkup（受限标记展开，对齐 C# NativeTooltipMarkup）──

test('flattenMarkup：<font color> 与 <b> 展开为 run 样式', () => {
    const runs = Doc.flattenMarkup("a<font color='#FF0000'>红<b>粗</b></font>尾", null, false);
    const texts = runs.map(r => r.text);
    assert.deepStrictEqual(texts, ['a', '红', '粗', '尾']);
    assert.strictEqual(runs[1].color, '#FF0000');
    assert.strictEqual(runs[1].bold, false);
    assert.strictEqual(runs[2].color, '#FF0000');
    assert.strictEqual(runs[2].bold, true);
    assert.strictEqual(runs[3].color, null);
    assert.strictEqual(runs[3].bold, false);
});

test('flattenMarkup：<br> → \\n run；\\n 字面保留', () => {
    const runs = Doc.flattenMarkup('a<br>b<br/>c\nd', null, false);
    assert.strictEqual(runs.map(r => r.text).join(''), 'a\nb\nc\nd');
});

test('flattenMarkup：<p> 首段抑制，后续段落换行', () => {
    const runs = Doc.flattenMarkup('<p>一段<p>二段', null, false);
    assert.strictEqual(runs.map(r => r.text).join(''), '一段\n二段');
    const bare = Doc.flattenMarkup('x<p>y', null, false);
    assert.strictEqual(bare.map(r => r.text).join(''), 'x\ny');
});

test('flattenMarkup：未识别标签剥离、孤立 < 字面保留、实体解码', () => {
    const runs = Doc.flattenMarkup('a<img src=x>b<script>alert(1)</script>c&lt;d&amp;e<孤立', null, false);
    const text = runs.map(r => r.text).join('');
    // 未知标签剥离但内文保留；孤立 '<' 字面保留；实体解码
    assert.strictEqual(text, 'abalert(1)c<d&e<孤立');
});

test('flattenMarkup：未闭合标记不跨 run 边界（显式适配出口自身语义）', () => {
    // flattenMarkup 是显式旧 HTML 适配出口：标记状态不跨调用边界
    const r1 = Doc.flattenMarkup('<b>粗体未闭合', null, false);
    const r2 = Doc.flattenMarkup('应非粗体', null, false);
    assert.strictEqual(r1[0].bold, true);
    assert.strictEqual(r2[0].bold, false);
    // 而 normalize 路径对同样输入【不】展开标记——逐字保留
    const doc = Doc.normalize({ version: 1, sections: [{ role: 'intro', runs: [
        { text: "<b>粗体未闭合" },
        { text: '应非粗体' }
    ] }] });
    assert(doc);
    assert.strictEqual(doc.sections[0].runs[0].text, '<b>粗体未闭合');
    assert.strictEqual(doc.sections[0].runs[0].bold, false);
});

test('flattenMarkup：run base color/bold 生效且可被内联 font 覆盖', () => {
    const runs = Doc.flattenMarkup("灰<font color='#00FF00'>绿</font>回灰", '#888888', true);
    assert.strictEqual(runs[0].color, '#888888');
    assert.strictEqual(runs[0].bold, true);
    assert.strictEqual(runs[1].color, '#00FF00');
    assert.strictEqual(runs[1].bold, true);
    assert.strictEqual(runs[2].color, '#888888');
});

// ── 计分与分栏 ──

test('textScore：ASCII=1 CJK=2 空白=0.5 换行=0', () => {
    assert.strictEqual(Doc.textScore('abc'), 3);
    assert.strictEqual(Doc.textScore('中文'), 4);
    assert.strictEqual(Doc.textScore('a b'), 2.5);
    assert.strictEqual(Doc.textScore('a\n中'), 3);
});

test('shouldSplit：长 desc 分栏，短文档合并', () => {
    const longDesc = '这是一段很长很长的说明文字。'.repeat(30);   // 远超阈值
    const splitDoc = Doc.normalize({ version: 1, title: 'x', sections: [
        { role: 'intro', runs: [{ text: '标题行' }] },
        { role: 'description', runs: [{ text: longDesc }] }
    ] });
    assert.strictEqual(Doc.shouldSplit(splitDoc), true);
    const mergeDoc = Doc.normalize({ version: 1, title: 'x', sections: [
        { role: 'intro', runs: [{ text: '短提示' }] }
    ] });
    assert.strictEqual(Doc.shouldSplit(mergeDoc), false);
});

// ── buildHtml ──

test('buildHtml：骨架复用 .flash-tt-rich + .ntt-doc，分栏列映射正确', () => {
    const longDesc = '长说明。'.repeat(60);
    const doc = Doc.normalize({ version: 1, title: 'M4A1', icon: { name: 'M4A1' },
        profile: 'dense', sections: [
            { role: 'intro', runs: [{ text: '属性行' }] },
            { role: 'description', runs: [{ text: longDesc }] }
        ] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('flash-tt-rich') >= 0 && html.indexOf('ntt-doc') >= 0);
    assert(html.indexOf('data-doc-profile="dense"') >= 0);
    assert(html.indexOf('flash-tt-intro-panel') >= 0);
    assert(html.indexOf('flash-tt-desc') >= 0, '长 desc 应分栏出右栏');
    assert(html.indexOf('ntt-title') >= 0 && html.indexOf('M4A1') >= 0);
    // 占位 icon（Icons 未加载）
    assert(html.indexOf('ntt-icon-placeholder') >= 0);
    // intro 内容不混进 desc 列
    const descIdx = html.indexOf('flash-tt-desc');
    assert(html.indexOf('属性行') < descIdx);
    assert(html.indexOf(longDesc.substring(0, 6)) > descIdx);
});

test('buildHtml：merge 模式 desc 拼入 intro', () => {
    const doc = Doc.normalize({ version: 1, title: 'x', sections: [
        { role: 'intro', runs: [{ text: '短' }] },
        { role: 'description', runs: [{ text: '短说明' }] }
    ] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('flash-tt-rich--merge') >= 0);
    assert(html.indexOf('flash-tt-desc') < 0, 'merge 不应有独立 desc 栏');
    assert(html.indexOf('短说明') >= 0);
});

test('buildHtml：chrome 参数 meta/suffix/rootClass/layoutType 透传', () => {
    const doc = Doc.normalize(FULL_DOC);
    const html = Doc.buildHtml(doc, {
        metaHTML: '<span class="meta">已发现 3/5</span>',
        suffix: '<div class="banner">锁定</div>',
        rootClass: 'my-panel-tt',
        layoutType: 'narrow',
        iconHtml: '<img src="i.png">'
    });
    assert(html.indexOf('my-panel-tt') >= 0);
    assert(html.indexOf('data-layout="narrow"') >= 0);
    assert(html.indexOf('已发现 3/5') >= 0);
    assert(html.indexOf('flash-tt-suffix') >= 0 && html.indexOf('锁定') >= 0);
    assert(html.indexOf('i.png') >= 0);
});

test('buildHtml：扩展 run 样式 italic/underline/fontSize/fontFace', () => {
    const html = Doc.buildHtml({ version: 1, title: 'x', sections: [{ role: 'intro', runs: [
        { text: '斜体', italic: true },
        { text: '下划', underline: true },
        { text: '大字', fontSize: 20 },
        { text: '等宽', fontFace: 'fixedsys' },
        { text: '嵌套', color: '#FF0000', bold: true, italic: true, underline: true, fontSize: 15 }
    ] }] });
    assert(html.indexOf('<i>斜体</i>') >= 0, 'italic → <i>');
    assert(html.indexOf('<u>下划</u>') >= 0, 'underline → <u>');
    assert(html.indexOf('font-size:20px') >= 0, 'fontSize → font-size:Npx');
    // 无 CF7FontCatalog（node 环境）→ font-family 不输出（legacy 未命中同行为）
    assert(html.indexOf('font-family') < 0, '无 catalog 时 fontFace 不得输出');
    // 嵌套序与 legacy 一致：span 最外 → b → i → u
    assert(html.indexOf('<span style="color:#FF0000;font-size:15px"><b><i><u>嵌套</u></i></b></span>') >= 0,
        '嵌套序 span>b>i>u + style 序 color;font-size');
});

test('buildHtml：fontFace 经 CF7FontCatalog.legacyFamily 映射（有 catalog 时）', () => {
    globalThis.CF7FontCatalog = {
        legacyFamily: function(f) { return f === 'fixedsys' ? '"Fixedsys",monospace' : null; }
    };
    try {
        const html = Doc.buildHtml({ version: 1, sections: [{ role: 'intro', runs: [
            { text: 'a', fontFace: 'fixedsys' }, { text: 'b', fontFace: '不存在的字体' }
        ] }] });
        assert(html.indexOf('font-family:"Fixedsys",monospace') >= 0, '命中 catalog 应输出映射族');
        // 未映射 face 不输出（legacy 同款），但文本不丢
        const b = html.indexOf('>b<');
        assert(b >= 0, '未映射 face 的文本仍渲染');
        assert(!/font-family:[^"']*不存在/.test(html), '未映射不得泄漏原 face 名');
    } finally { delete globalThis.CF7FontCatalog; }
});

test('normalize：扩展字段 sanitize——越界/注入一律丢弃', () => {
    const doc = Doc.normalize({ version: 1, sections: [{ role: 'body', runs: [
        { text: 'a', fontSize: 0 }, { text: 'b', fontSize: 97 },
        { text: 'c', fontSize: 'abc' }, { text: 'd', fontSize: '15px' },
        { text: 'e', fontFace: 'evil" onmouseover="alert(1)' },
        { text: 'f', fontFace: 'ms mincho' },
        { text: 'g', italic: 'yes', underline: 1 },
        { text: 'h', fontSize: 15.9 }
    ] }] });
    const r = doc.sections[0].runs;
    assert.strictEqual(r[0].fontSize, undefined, 'fontSize=0 丢弃');
    assert.strictEqual(r[1].fontSize, undefined, 'fontSize=97 丢弃');
    assert.strictEqual(r[2].fontSize, undefined, 'fontSize=abc 丢弃');
    assert.strictEqual(r[3].fontSize, 15, "'15px' 按 legacy parseInt → 15");
    assert(!/["()]/.test(r[4].fontFace || ''), 'fontFace 注入字符被白名单剥除');
    assert.strictEqual(r[5].fontFace, 'ms mincho', '合法多空格字体名保留');
    assert.strictEqual(r[6].italic, undefined, "italic='yes' 非布尔丢弃");
    assert.strictEqual(r[6].underline, true, 'underline=1 按 readBool 规则收');
    assert.strictEqual(r[7].fontSize, 15, '15.9 parseInt → 15');
    // 渲出的 HTML 不含注入物
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('onmouseover') < 0 && html.indexOf('alert') < 0);
});

test('flattenMarkup：i/u/font size/face 标记 → run 扩展字段', () => {
    const runs = Doc.flattenMarkup(
        "<B><I><U>x</U></I></B><FONT SIZE='20' FACE='ms mincho'>y</FONT>"
        + "<FONT SIZE='15'>z</FONT>w");
    assert.strictEqual(runs[0].text, 'x');
    assert(runs[0].bold && runs[0].italic && runs[0].underline, 'x 三层嵌套样式');
    assert.strictEqual(runs[1].fontSize, 20, 'size 属性入 run');
    assert.strictEqual(runs[1].fontFace, 'ms mincho', 'face 属性入 run');
    assert.strictEqual(runs[2].fontSize, 15, 'size-only font 帧');
    assert.strictEqual(runs[3].text, 'w');
    assert.strictEqual(runs[3].fontSize, undefined, '</font> 弹栈后样式复位');
    // 3 位 hex 规范化与 Web legacy 一致
    const hex = Doc.flattenMarkup("<FONT COLOR='#F00'>c</FONT>");
    assert.strictEqual(hex[0].color, '#FF0000', '3位hex → #RRGGBB');
});

test('buildHtml：document.layoutType 字段驱动 narrow，opts 仍可覆盖', () => {
    // AS2 buildItem 在 document 上写 layoutType（C# sanitizer 透传）；
    // 缺省 wide 不输出 attr，opts.layoutType 显式传入时优先
    const narrowDoc = { version: 1, title: 'x', layoutType: 'narrow',
        sections: [{ role: 'intro', runs: [{ text: 'a' }] }] };
    assert(Doc.buildHtml(narrowDoc).indexOf('data-layout="narrow"') >= 0);
    assert(Doc.buildHtml(narrowDoc, { layoutType: 'wide' })
        .indexOf('data-layout') < 0, 'opts.layoutType=wide 应覆盖 doc.narrow');
    const plainDoc = { version: 1, title: 'x',
        sections: [{ role: 'intro', runs: [{ text: 'a' }] }] };
    assert(Doc.buildHtml(plainDoc).indexOf('data-layout') < 0);
    assert.strictEqual(Doc.normalize(narrowDoc).layoutType, 'narrow');
    assert.strictEqual(Doc.normalize(plainDoc).layoutType, null);
    assert.strictEqual(
        Doc.normalize({ version: 1, title: 'x', layoutType: 'bogus' }).layoutType, null);
});

test('buildHtml：文本全转义——注入标记按字面显示，不产生真实标签', () => {
    const doc = Doc.normalize({ version: 1, sections: [{ role: 'body', runs: [
        { text: "<img src=x onerror=alert(1)>文本&amp;注\u91ca" }
    ] }] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('<img') < 0, 'run.text 的 <img> 不得成为真实标签');
    assert(html.indexOf('&lt;img src=x onerror=alert(1)&gt;') >= 0,
        '注入串应转义为可见文本');
    assert(html.indexOf('文本&amp;amp;注释') >= 0,
        '字面 &amp; 不得解码（纯文本契约）');
});

test('buildHtml：run 内 \\n → <br>；color/bold 渲染为受限标签', () => {
    const doc = Doc.normalize({ version: 1, sections: [{ role: 'intro', runs: [
        { text: '第一行\n第二行', color: '#FFCC00', bold: true }
    ] }] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('color:#FFCC00') >= 0);
    assert(html.indexOf('<b>') >= 0);
    assert(html.indexOf('第一行<br>第二行') >= 0);
});

test('buildHtml：非法输入返回空串', () => {
    assert.strictEqual(Doc.buildHtml(null), '');
    assert.strictEqual(Doc.buildHtml({ version: 9, title: 'x' }), '');
    assert.strictEqual(Doc.buildHtml({}), '');
});

test('CSS 接线：panels/tooltip-document.css 存在且 panels.css 已 import', () => {
    const fs = require('fs'), path = require('path');
    const cssPath = path.join(__dirname, '../launcher/web/css/panels/tooltip-document.css');
    const panelsPath = path.join(__dirname, '../launcher/web/css/panels.css');
    assert(fs.existsSync(cssPath), 'tooltip-document.css 必须存在');
    const panels = fs.readFileSync(panelsPath, 'utf8');
    assert(panels.indexOf('panels/tooltip-document.css') >= 0, 'panels.css 必须 import');
});

test('CSS 权威：tooltip-document.css 不重写主题/字体/布局（Web 权威回归门）', () => {
    // 注释视觉权威 = 迁移前 Web：document 输出复用 .flash-tt-* 骨架与 #panel-tooltip
    // --tt-* token。本文件只允许注释/标记说明，禁止再次注入 NativeHud 语义 token
    // 或任何会改变渲染的规则（上轮错误改动回归门）。
    const fs = require('fs'), path = require('path');
    const css = fs.readFileSync(
        path.join(__dirname, '../launcher/web/css/panels/tooltip-document.css'), 'utf8');
    // NativeHud 特征值不得出现
    assert.strictEqual(css.indexOf('--ntt-'), -1, '不得定义 --ntt-* 主题 token');
    assert.strictEqual(css.indexOf('rgba(5, 7, 9'), -1, 'PanelFillDense 不得回归');
    assert.strictEqual(css.indexOf('#FFD700'), -1, 'NativeHud Gold 不得回归');
    assert.strictEqual(css.indexOf('intelligence-archive'), -1, 'serif 字体覆盖不得回归');
    // 不得重写 --tt-* token / font / 盒模型属性
    assert(!/--tt-[a-z-]+\s*:/.test(css), '不得覆写 --tt-* token');
    assert(!/font-family\s*:/.test(css), '不得覆写 font-family');
    // 文件应只剩注释：剥离注释后不允许存在任何声明块
    const stripped = css.replace(/\/\*[\s\S]*?\*\//g, '');
    assert(!/\{[^}]*\}/.test(stripped),
        'tooltip-document.css 不允许携带任何生效规则（ntt-* 为零视觉标记）');
});

test('导出面：不再携带 JS 内嵌主题入口', () => {
    assert.strictEqual(typeof Doc.installTheme, 'undefined');
    assert.strictEqual(typeof Doc.THEME_CSS, 'undefined');
});

test('describe：诊断串含关键身份字段', () => {
    const doc = Doc.normalize(PAYLOAD);
    const s = Doc.describe(doc);
    assert(s.indexOf('tt.req.7') >= 0 && s.indexOf('dense') >= 0);
});

test('截断上限：超长 run.text 截断不抛', () => {
    const big = 'x'.repeat(40000);
    const doc = Doc.normalize({ version: 1, sections: [{ role: 'body', runs: [{ text: big }] }] });
    assert(doc);
    assert(doc.sections[0].runs[0].text.length <= 32768);
    assert.strictEqual(doc.truncated, true);
});

// ── 结构部件：左侧插条 rail ──

test('normalize rail：最多 2 项、相邻去重、非纯文本丢弃', () => {
    const doc = Doc.normalize({ version: 1, rail: ['长枪', '突击步枪'],
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert.deepStrictEqual(doc.rail, ['长枪', '突击步枪']);

    const capped = Doc.normalize({ version: 1, rail: ['a', 'b', 'c'],
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert.deepStrictEqual(capped.rail, ['a', 'b'], '超出 2 项截断');

    const dup = Doc.normalize({ version: 1, rail: ['长枪', '长枪'],
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert.deepStrictEqual(dup.rail, ['长枪'], '相邻重复去重');

    const dirty = Doc.normalize({ version: 1,
        rail: ['', '  ', 42, { a: 1 }, 'x'.repeat(25), '正常'],
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert.deepStrictEqual(dirty.rail, ['正常'],
        '空白/数字/对象/超 24 字一律丢弃（只收非空字符串）');

    const absent = Doc.normalize({ version: 1, sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert.deepStrictEqual(absent.rail, [], '缺省 rail 为空数组，旧 payload 形状不变');

    const notArray = Doc.normalize({ version: 1, rail: '长枪',
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert.deepStrictEqual(notArray.rail, [], '非数组 rail 忽略');
});

test('rail 不单独构成可渲染内容', () => {
    assert.strictEqual(Doc.normalize({ version: 1, rail: ['长枪', '突击步枪'] }), null,
        '只有 rail 无正文应整体拒绝');
    assert.strictEqual(Doc.normalize({ version: 1, rail: ['长枪'], sections: [] }), null);
});

test('buildHtml rail：书签块自上下排，横向文字无窄腰/空帽', () => {
    const doc = Doc.normalize({ version: 1, rail: ['长枪', '突击步枪'],
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('flash-tt-rich--rail') >= 0, '有 rail 才挂修饰类');
    assert(html.indexOf('flash-tt-rail ntt-rail') >= 0, '书签容器');
    const blocks = html.match(/flash-tt-rail-block/g) || [];
    assert.strictEqual(blocks.length, 2, '两项 = 两个白色书签块');
    assert(html.indexOf('>长枪<') >= 0 && html.indexOf('>突击步枪<') >= 0);
    assert(html.indexOf('flash-tt-rail-waist') < 0, '书签式不再有窄腰');
    assert(!/flash-tt-rail-block--cap/.test(html), '书签式不再补空帽');
    assert(html.indexOf('--tt-rail-chars') < 0, '字号收缩计数已废弃');
});

test('buildHtml rail：单文本只有一块书签', () => {
    const doc = Doc.normalize({ version: 1, rail: ['长枪'],
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    const html = Doc.buildHtml(doc);
    const blocks = html.match(/flash-tt-rail-block/g) || [];
    assert.strictEqual(blocks.length, 1, '单段文本 = 单块');
    assert(html.indexOf('flash-tt-rail-waist') < 0);
});

test('buildHtml 无 rail：不产轨道也不改修饰类', () => {
    const html = Doc.buildHtml(FULL_DOC);
    assert(!/flash-tt-rail/.test(html), '无 rail 不得出现轨道节点');
    assert(html.indexOf('flash-tt-rich--rail') < 0, '无 rail 保持 legacy 盒模型');
});

test('buildHtml rail：文本按字面转义，不产生真实标签', () => {
    const doc = Doc.normalize({ version: 1, rail: ['<zz onerror=a>'],
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('<zz') < 0, 'rail 文本不得成为真实标签');
    assert(html.indexOf('&lt;zz onerror=a&gt;') >= 0, '转义后按字面显示');
});

// ── 结构部件：弹夹框（双行）──

test('normalize magazine：名称必需，图标/子弹类型可选', () => {
    const full = Doc.normalize({ version: 1, magazine: {
        name: '11 号弹夹', icon: '突击步枪通用弹药', ammo: '4.7mm 无壳弹' },
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert.deepStrictEqual(full.magazine, {
        name: '11 号弹夹', icon: '突击步枪通用弹药', ammo: '4.7mm 无壳弹' });

    const nameOnly = Doc.normalize({ version: 1, magazine: { name: '弹夹' },
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert.strictEqual(nameOnly.magazine.icon, null, '缺图标记为 null，行仍成立');
    assert.strictEqual(nameOnly.magazine.ammo, null, '缺子弹类型标记为 null');

    for (const bad of [null, undefined, {}, { name: '  ' }, { icon: '只有图标' }, { name: 42 }]) {
        const d = Doc.normalize({ version: 1, magazine: bad,
            sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
        assert.strictEqual(d.magazine, null, '无效 magazine 归 null: ' + JSON.stringify(bad));
    }
    assert.strictEqual(Doc.normalize({ version: 1, magazine: { name: 'x'.repeat(65) },
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] }).magazine, null,
        '超 64 字弹夹名整块丢弃');
});

test('magazine 不单独构成可渲染内容', () => {
    assert.strictEqual(Doc.normalize({ version: 1, magazine: { name: '弹夹' } }), null);
});

test('buildHtml magazine：第一行图标+名称，第二行子弹类型', () => {
    const doc = Doc.normalize({ version: 1, magazine: {
        name: '11 号 4.7mm 无壳弹弹夹', icon: '弹药', ammo: '4.7mm 无壳弹' },
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('flash-tt-mag ntt-mag') >= 0, '弹夹块挂在 intro 面板内');
    assert(html.indexOf('flash-tt-mag-row') >= 0, '第一行容器');
    assert(html.indexOf('flash-tt-mag-icon') >= 0 && html.indexOf('flash-tt-mag-name') >= 0);
    assert(html.indexOf('11 号 4.7mm 无壳弹弹夹') >= 0, '名称紧跟图标之后');
    assert(html.indexOf('flash-tt-mag-ammo ntt-mag-ammo') >= 0, '第二行子弹类型');
    assert(html.indexOf('flash-tt-mag') < html.indexOf('11 号'), '图标位排在名称之前');
    assert(html.indexOf('flash-tt-mag-row') < html.indexOf('flash-tt-mag-ammo'),
        '子弹类型行在名称行之后');
    assert(html.indexOf('使用弹夹') < 0, '标签字符由数据侧不再下发');
});

test('buildHtml magazine：无 ammo 时不产第二行', () => {
    const doc = Doc.normalize({ version: 1, magazine: { name: '弹夹' },
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    assert(Doc.buildHtml(doc).indexOf('flash-tt-mag-ammo') < 0);
});

test('buildHtml 无 magazine：不产弹夹行', () => {
    assert(Doc.buildHtml(FULL_DOC).indexOf('flash-tt-mag') < 0);
});

// ── attachments 子框（已安装插件）──

test('normalize attachments：rows 有效才成立，无效回退保留 runs', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: 'x' }] },
        { role: 'sub', kind: 'attachments', title: '已安装2个配件',
            rows: [
                { name: '扩容弹匣', icon: 'mod_expand',
                    runs: [{ text: ' 弹夹容量 +5', color: '#FFFF00' }] },
                { name: '   ' },
                { icon: '只有图标' }
            ],
            runs: [{ text: '回退文本' }] }
    ] });
    const sec = doc.sections[1];
    assert.strictEqual(sec.kind, 'attachments');
    assert.strictEqual(sec.title, '已安装2个配件');
    assert.strictEqual(sec.rows.length, 1, '空名/仅图标行丢弃');
    assert.strictEqual(sec.rows[0].name, '扩容弹匣');
    assert.strictEqual(sec.rows[0].icon, 'mod_expand');
    assert.strictEqual(sec.rows[0].runs[0].color, '#FFFF00');

    const fallback = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: 'x' }] },
        { role: 'sub', kind: 'attachments', rows: [],
            runs: [{ text: '回退文本' }] }
    ] });
    assert.strictEqual(fallback.sections[1].kind, undefined, '无有效行不带 kind');
    assert.strictEqual(fallback.sections[1].rows, undefined);
    assert.strictEqual(Doc.plainTextOf(fallback.sections[1].runs), '回退文本');

    const wrongKind = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: 'x' }] },
        { role: 'sub', kind: 'Attachments', rows: [{ name: 'a' }],
            runs: [{ text: '回退文本' }] }
    ] });
    assert.strictEqual(wrongKind.sections[1].kind, undefined, 'kind 仅精确匹配小写');
});

test('buildHtml attachments：标题 + 逐行图标/名称/效果，runs 不叠加', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: 'x' }] },
        { role: 'sub', kind: 'attachments', title: '已安装1个配件',
            rows: [{ name: '扩容弹匣', icon: 'mod_expand',
                runs: [{ text: ' 弹夹容量 +5', color: '#FFFF00' }] }],
            runs: [{ text: '回退文本' }] }
    ] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('flash-tt-sub-panel--attachments') >= 0, 'attachments 标记类');
    assert(html.indexOf('flash-tt-sub-title') >= 0 && html.indexOf('已安装1个配件') >= 0);
    assert(html.indexOf('flash-tt-attach-row') >= 0 && html.indexOf('flash-tt-attach-icon') >= 0);
    assert(html.indexOf('flash-tt-attach-name') >= 0
        && html.indexOf('<b>扩容弹匣</b>') >= 0, '插件名独占名称行并加粗');
    assert(html.indexOf('flash-tt-attach-effect') >= 0
        && html.indexOf('弹夹容量 +5') >= 0, '具体影响进入附属效果行');
    assert(html.indexOf('flash-tt-attach-name') < html.indexOf('flash-tt-attach-effect'),
        '效果行位于配件名之后');
    assert(html.indexOf('回退文本') < 0, 'rows 成立时不再叠加 fallback runs');
});

test('attachments rows 计入可渲染内容，但结构部件本身不成立', () => {
    const rowsOnly = Doc.normalize({ version: 1, sections: [
        { role: 'sub', kind: 'attachments', rows: [{ name: '扩容弹匣' }] }
    ] });
    assert(rowsOnly, '只有 attachments 行也算正文内容');
    assert.strictEqual(Doc.normalize({ version: 1, sections: [
        { role: 'sub', kind: 'attachments', rows: [{ name: '  ' }] }
    ] }), null, '无有效行且无正文的文档不成立');
});

// ── acquisition 子框（获取方式）──

test('normalize acquisition：kind 放行、商店行带头像键、空行回退', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: 'x' }] },
        { role: 'sub', kind: 'acquisition', title: '获取方式',
            rows: [
                { name: '合成', runs: [{ text: '武器合成 ($10000)' }] },
                { name: 'Shop Girl', icon: 'Shop Girl' },
                { name: '   ' }
            ],
            runs: [{ text: '回退文本' }] }
    ] });
    const sec = doc.sections[1];
    assert.strictEqual(sec.kind, 'acquisition');
    assert.strictEqual(sec.title, '获取方式');
    assert.strictEqual(sec.rows.length, 2, '空名行丢弃');
    assert.strictEqual(sec.rows[1].icon, 'Shop Girl', '商店行 icon = NPC 头像键');

    const fallback = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: 'x' }] },
        { role: 'sub', kind: 'acquisition', rows: [],
            runs: [{ text: '回退文本' }] }
    ] });
    assert.strictEqual(fallback.sections[1].kind, undefined, '无有效行不带 kind');
    assert.strictEqual(Doc.plainTextOf(fallback.sections[1].runs), '回退文本');
});

test('buildHtml acquisition：商店行用 cfn-assets 头像 URL，无图标行留空占位', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: 'x' }] },
        { role: 'sub', kind: 'acquisition', title: '获取方式',
            rows: [
                { name: 'NPC商店' },
                { name: 'Shop Girl', icon: 'Shop Girl', depth: 1,
                    runs: [{ text: ' ($100)' }] }
            ],
            runs: [{ text: '回退文本' }] }
    ] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('flash-tt-sub-panel--acquisition') >= 0, 'acquisition 标记类');
    assert(html.indexOf('获取方式') >= 0, '子框标题');
    assert(html.indexOf('https://cfn-assets.local/portraits/icons/'
        + encodeURIComponent('Shop Girl') + '.webp') >= 0, '商店行头像 URL');
    assert(html.indexOf(encodeURIComponent('无头像')) >= 0, '头像加载失败有兜底');
    assert(html.indexOf('<b>NPC商店</b>') >= 0, '类别标签为父级行');
    assert(html.indexOf('flash-tt-attach-row--child') >= 0, 'NPC 行携带子级缩进类');
    assert(html.indexOf('flash-tt-attach-row--category') >= 0, '大类携带左对齐类');
    assert(html.indexOf('($100)') >= 0, '花费保留在来源名称行');
    assert(html.indexOf('ntt-attach-effect') < 0, '来源花费不另起效果行');
    assert(html.indexOf('回退文本') < 0, 'rows 成立时不再叠加 fallback runs');
});

test('buildHtml：A兵团相关文案前插入徽标并加下划线', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [
            { text: '普通红字', color: '#B22222' },
            { text: 'A兵团士兵', color: '#ff0000' },
            { text: 'AndyLaw', color: '#FF0000' },
            { text: 'Andy Law' },
            { text: 'Andy套装' },
            { text: '安迪烙' }
        ] }
    ] });
    const html = Doc.buildHtml(doc);
    const marks = html.match(/ntt-a-legion-mark/g) || [];
    assert.strictEqual(marks.length, 5, '预设红字与明确 A兵团内容均有徽标');
    assert(html.indexOf('<u>A兵团士兵</u>') >= 0, 'A兵团红字带下划线');
    assert(html.indexOf('<u>AndyLaw</u>') >= 0, 'AndyLaw 红字带下划线');
    assert(html.indexOf('<span style="color:#FF0000"><u>Andy Law</u></span>') >= 0,
        '未着色 Andy Law 也带红色下划线');
    assert(html.indexOf('<span style="color:#FF0000"><u>Andy套装</u></span>') >= 0,
        '单独 Andy 也有徽标');
    assert(html.indexOf('<span style="color:#FF0000"><u>安迪烙</u></span>') >= 0,
        '安迪烙也有徽标');
    assert(html.indexOf('ntt-a-legion-mark') < html.indexOf('A兵团士兵'), '徽标在文字前');
    assert(html.indexOf('普通红字') < html.indexOf('ntt-a-legion-mark'), '其他红色系不插徽标');
});

test('buildHtml：军阀文案使用黑黄徽标与淡金色下划线', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: '军阀士兵', color: '#00FFFF' }] }
    ] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('ntt-warlord-mark') >= 0, '军阀内容带黑黄徽标');
    assert(html.indexOf('<span style="color:#FFFFE0"><u>军阀士兵</u></span>') >= 0,
        '军阀文字使用 #FFFFE0 下划线');
});

test('buildHtml：物品名使用独立居中大字号标题块', () => {
    const html = Doc.buildHtml(FULL_DOC);
    assert(html.indexOf('class="ntt-title"') >= 0, 'document.title 独立标题块');
    assert(html.indexOf('class="ntt-title"')
        < html.indexOf('class="ntt-sec ntt-sec--intro"'), '标题位于正文 section 之前');
});

// ── 子注释框淡入算法 ──

test('fadeMsForSub：子框严格慢于主组且逐层递增', () => {
    assert.strictEqual(Doc.FADE_MAIN_MS, 500, '主组淡入 = 用户口径 0.5s');
    const d1 = Doc.fadeMsForSub(1), d2 = Doc.fadeMsForSub(2), d3 = Doc.fadeMsForSub(3);
    assert(d1 > Doc.FADE_MAIN_MS, '第一个子框也慢于主组');
    assert(d1 < d2 && d2 < d3, '越靠下的子框越慢');
    assert.strictEqual(d1, 675);
    assert.strictEqual(d2, 750);
    assert.strictEqual(d3, 825);
});

test('buildHtml：每个 role:"sub" 段独立成框、挂在侧栏并按序携带淡入时长', () => {
    const doc = Doc.normalize({ version: 1, sections: [
        { role: 'intro', runs: [{ text: 'x' }] },
        { role: 'sub', runs: [{ text: '插件' }] },
        { role: 'sub', runs: [{ text: '战技' }] },
        { role: 'sub', runs: [{ text: '暴击斩杀' }] }
    ] });
    const html = Doc.buildHtml(doc);
    const boxes = html.match(/flash-tt-sub-panel/g) || [];
    assert.strictEqual(boxes.length, 3, '每个 sub 段一个独立子框');
    assert(html.indexOf('--tt-fade-ms:675') >= 0, '第 1 框 675ms');
    assert(html.indexOf('--tt-fade-ms:750') >= 0, '第 2 框 750ms');
    assert(html.indexOf('--tt-fade-ms:825') >= 0, '第 3 框 825ms');
    assert(html.indexOf('--tt-fade-ms:500') < 0, '主组时长走 CSS 默认 token，不逐层内联');
    // 主框体在前，侧栏（含全部子框）排在主框之后，子框不再堆在主框下方
    const sideIdx = html.indexOf('flash-tt-side');
    assert(sideIdx > html.indexOf('flash-tt-intro-panel'), '侧栏排在主框体之后');
    assert(sideIdx < html.indexOf('flash-tt-sub-panel'), '子框都挂在侧栏内');
});

test('buildHtml：描述栏与子框同列，淡入按时序 675/750/825', () => {
    const doc = Doc.normalize({ version: 1, title: 'x', sections: [
        { role: 'intro', runs: [{ text: '属性行' }] },
        { role: 'description', runs: [{ text: ('长说明。').repeat(60) }] },
        { role: 'sub', runs: [{ text: '插件' }] },
        { role: 'sub', runs: [{ text: '战技' }] }
    ] });
    const html = Doc.buildHtml(doc);
    assert(html.indexOf('flash-tt-desc') >= 0, '长 desc 分栏');
    const sideIdx = html.indexOf('flash-tt-side');
    const descIdx = html.indexOf('flash-tt-desc');
    const firstSub = html.indexOf('flash-tt-sub-panel');
    assert(sideIdx >= 0 && sideIdx < descIdx, '描述栏在侧栏内');
    assert(descIdx < firstSub, '子框接在描述栏之后，同一列');
    const descTag = html.substring(descIdx, html.indexOf('>', descIdx));
    assert(descTag.indexOf('--tt-fade-ms:675ms') >= 0, '描述栏占第 1 槽，675ms：' + descTag);
    assert(html.indexOf('--tt-fade-ms:750') >= 0 && html.indexOf('--tt-fade-ms:825') >= 0,
        '子框顺延 750/825');
    assert(html.indexOf('--tt-fade-ms:500') < 0, '主组不内联时长，走 CSS 默认 token');
});

test('describe：诊断串含 rail 与 magazine 身份', () => {
    const doc = Doc.normalize({ version: 1, rail: ['长枪', '突击步枪'],
        magazine: { name: '11 号弹夹' },
        sections: [{ role: 'intro', runs: [{ text: 'x' }] }] });
    const s = Doc.describe(doc);
    assert(s.indexOf('rail=2') >= 0, 'rail 块数进诊断：' + s);
    assert(s.indexOf('11 号弹夹') >= 0, '弹夹名进诊断：' + s);
});

console.log('\n' + passed + ' tests passed');
