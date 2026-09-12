import org.flashNight.gesh.tooltip.NativeTooltipDocument;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.tooltip.TooltipTextBuilder;
import org.flashNight.arki.item.ItemUtil;

/**
 * NativeTooltipDocumentTest - 共享语义文档构建器测试
 *
 * 重点：嵌套标记、中文、实体（单次解析）、换行、真实实例数据。
 * document.title 与 run.text 为纯文本：实体已解码、标记已展开为 color/bold，
 * 消费端不得二次解析。
 */
class org.flashNight.gesh.tooltip.test.NativeTooltipDocumentTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    private static function assertEq(expected, actual, msg:String):Void {
        testsRun++;
        if (expected === actual) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " expected=" + expected + " actual=" + actual); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- NativeTooltipDocumentTest ---");

        test_plainText_singleRun();
        test_bold();
        test_fontColor();
        test_fontColor3Hex();
        test_fontSize_parseIntRules();
        test_fontFace_restrictedName();
        test_italicUnderline();
        test_emStrongAlias();
        test_nestedFontBold();
        test_nestedFontSizeColorBold();
        test_fontClosePopsFontFrame_keepsInnerRest();
        test_underlineSurvivesLineBreak();
        test_maliciousFaceValue_filtered();
        test_br_newlineRun();
        test_p_paragraph();
        test_entities_singleParse();
        test_chineseText();
        test_unknownTagStripped();
        test_orphanLt_literal();
        test_crlf_normalized();
        test_buildItem_shape();
        test_layoutType();
        test_buildItem_realInstance();
        test_buildSkill_shape();
        test_skillInfo_objectWithoutDescription();
        test_buildBody_simple();

        trace("--- NativeTooltipDocumentTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_plainText_singleRun():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("普通文本");
        assertEq(1, runs.length, "plain: one run");
        assertEq("普通文本", runs[0].text, "plain: text");
        assert(runs[0].color == undefined, "plain: no color key");
        assert(runs[0].bold == undefined, "plain: no bold key");
    }

    private static function test_bold():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("<B>加粗</B>");
        assertEq(1, runs.length, "bold: one run");
        assertEq("加粗", runs[0].text, "bold: text");
        assertEq(true, runs[0].bold, "bold: bold flag");
    }

    private static function test_fontColor():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("<FONT COLOR='#ff0000'>红字</FONT>");
        assertEq(1, runs.length, "font: one run");
        assertEq("红字", runs[0].text, "font: text");
        assertEq("#FF0000", runs[0].color, "font: color normalized uppercase");
        runs = NativeTooltipDocument.htmlToRuns("<font color='#000000' size='15'>黑字</font>");
        assertEq("#000000", runs[0].color, "font: trailing size preserves color");
        runs = NativeTooltipDocument.htmlToRuns("<font face='fixedsys' color=#aabbcc size='15'>字</font>");
        assertEq("#AABBCC", runs[0].color, "font: unquoted color between attributes");
    }

    private static function test_fontColor3Hex():Void {
        // 3 位 hex 按 CSS 规则逐位翻倍（对齐 Web legacy 白名单）
        var runs:Array = NativeTooltipDocument.htmlToRuns("<FONT COLOR='#abc'>x</FONT>");
        assertEq("#AABBCC", runs[0].color, "3hex: expanded to #AABBCC");
        runs = NativeTooltipDocument.htmlToRuns("<FONT COLOR='#F60'>x</FONT>");
        assertEq("#FF6600", runs[0].color, "3hex: uppercase + expand");
        runs = NativeTooltipDocument.htmlToRuns("<FONT COLOR='#ab'>x</FONT>");
        assert(runs[0].color == undefined, "3hex: 2-digit rejected");
        runs = NativeTooltipDocument.htmlToRuns("<FONT COLOR='#abcd'>x</FONT>");
        assert(runs[0].color == undefined, "3hex: 4-digit rejected");
    }

    private static function test_fontSize_parseIntRules():Void {
        // Web legacy parseInt(_,10) + px>0 && px<=96
        var runs:Array = NativeTooltipDocument.htmlToRuns("<FONT SIZE='15'>x</FONT>");
        assertEq(15, runs[0].fontSize, "size: plain 15");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE=\"30\">x</FONT>");
        assertEq(30, runs[0].fontSize, "size: double-quoted 30");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='15px'>x</FONT>");
        assertEq(15, runs[0].fontSize, "size: trailing px tolerated (parseInt)");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='+15'>x</FONT>");
        assertEq(15, runs[0].fontSize, "size: leading + accepted");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='15.9'>x</FONT>");
        assertEq(15, runs[0].fontSize, "size: 15.9 truncates to 15");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE=' 20 '>x</FONT>");
        assertEq(20, runs[0].fontSize, "size: whitespace inside quotes skipped");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='0'>x</FONT>");
        assert(runs[0].fontSize == undefined, "size: 0 rejected");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='97'>x</FONT>");
        assert(runs[0].fontSize == undefined, "size: 97 > 96 rejected");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='-5'>x</FONT>");
        assert(runs[0].fontSize == undefined, "size: negative rejected");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='abc'>x</FONT>");
        assert(runs[0].fontSize == undefined, "size: non-numeric rejected");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='0x15'>x</FONT>");
        assert(runs[0].fontSize == undefined, "size: 0x15 → parseInt 0 rejected");
        runs = NativeTooltipDocument.htmlToRuns("<FONT SIZE='96'>x</FONT>");
        assertEq(96, runs[0].fontSize, "size: 96 boundary accepted");
    }

    private static function test_fontFace_restrictedName():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("<FONT FACE='ms mincho'>x</FONT>");
        assertEq("ms mincho", runs[0].fontFace, "face: ms mincho kept");
        runs = NativeTooltipDocument.htmlToRuns("<FONT FACE=\"fixedsys\">x</FONT>");
        assertEq("fixedsys", runs[0].fontFace, "face: fixedsys kept");
        runs = NativeTooltipDocument.htmlToRuns("<FONT FACE='MS  MINCHO'>x</FONT>");
        assertEq("MS MINCHO", runs[0].fontFace, "face: spaces collapsed, case preserved");
        runs = NativeTooltipDocument.htmlToRuns("<FONT FACE='楷体-字'>x</FONT>");
        assertEq("楷体-字", runs[0].fontFace, "face: CJK + hyphen kept");
        runs = NativeTooltipDocument.htmlToRuns("<FONT FACE=''>x</FONT>");
        assert(runs[0].fontFace == undefined, "face: empty rejected");
    }

    private static function test_italicUnderline():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("<I>斜</I><U>线</U>");
        assertEq(2, runs.length, "iu: two runs");
        assertEq(true, runs[0].italic, "iu: italic flag");
        assert(runs[0].underline == undefined, "iu: no underline on first");
        assertEq(true, runs[1].underline, "iu: underline flag");
        assert(runs[1].italic == undefined, "iu: no italic on second");
    }

    private static function test_emStrongAlias():Void {
        // legacy convertAS2Html：em→i、strong→b（与 AS2 标签白名单同款映射）
        var runs:Array = NativeTooltipDocument.htmlToRuns("<EM>斜</EM><STRONG>粗</STRONG>");
        assertEq(true, runs[0].italic, "alias: em → italic");
        assertEq(true, runs[1].bold, "alias: strong → bold");
    }

    private static function test_nestedFontSizeColorBold():Void {
        // 真实语料形态：<font color="#000000" size="15">（color 在前 size 在后）
        var runs:Array = NativeTooltipDocument.htmlToRuns(
            "<FONT COLOR=\"#000000\" SIZE=\"15\"><B>黑粗</B></FONT>白");
        assertEq(2, runs.length, "nestedSC: two runs");
        assertEq("#000000", runs[0].color, "nestedSC: color kept with size");
        assertEq(15, runs[0].fontSize, "nestedSC: size kept");
        assertEq(true, runs[0].bold, "nestedSC: bold");
        assert(runs[1].color == undefined && runs[1].fontSize == undefined
            && runs[1].bold == undefined, "nestedSC: plain after font close");

        // 内层 size 覆盖外层，闭合后恢复
        runs = NativeTooltipDocument.htmlToRuns(
            "<FONT SIZE='10'>a<FONT SIZE='20'>b</FONT>c</FONT>d");
        assertEq(4, runs.length, "sizeNest: four runs");
        assertEq(10, runs[0].fontSize, "sizeNest: outer 10");
        assertEq(20, runs[1].fontSize, "sizeNest: inner 20");
        assertEq(10, runs[2].fontSize, "sizeNest: outer restored");
        assert(runs[3].fontSize == undefined, "sizeNest: plain tail");
    }

    private static function test_fontClosePopsFontFrame_keepsInnerRest():Void {
        // </FONT> 必须弹到最近 font 帧（含其上 bold 帧）——size 不得泄漏给后续文本
        var runs:Array = NativeTooltipDocument.htmlToRuns(
            "<FONT SIZE='15'><B>x</FONT>y</B>");
        assertEq(2, runs.length, "fontClose: two runs");
        assertEq(15, runs[0].fontSize, "fontClose: sized run");
        assertEq(true, runs[0].bold, "fontClose: bold inside");
        assert(runs[1].fontSize == undefined, "fontClose: size not leaked past </FONT>");
        assert(runs[1].bold == undefined, "fontClose: bold not leaked past </FONT>");
    }

    private static function test_underlineSurvivesLineBreak():Void {
        // 真实语料形态：<font face="fixedsys"><u>“…<BR>…”</u></font>——
        // <BR> 只产无样式换行 run，不弹样式栈（对齐 Web DOM）
        var runs:Array = NativeTooltipDocument.htmlToRuns(
            "<FONT FACE='fixedsys'><U>甲<BR>乙</U></FONT>丙");
        assertEq(4, runs.length, "uBR: four runs");
        assertEq("甲", runs[0].text, "uBR: first");
        assertEq(true, runs[0].underline, "uBR: first underlined");
        assertEq("fixedsys", runs[0].fontFace, "uBR: face kept");
        assertEq("\n", runs[1].text, "uBR: break run");
        assert(runs[1].underline == undefined, "uBR: break run unstyled");
        assertEq("乙", runs[2].text, "uBR: second line text");
        assertEq(true, runs[2].underline, "uBR: underline survives line break");
        assertEq("fixedsys", runs[2].fontFace, "uBR: face survives line break");
        assertEq("丙", runs[3].text, "uBR: tail text");
        assert(runs[3].underline == undefined && runs[3].fontFace == undefined,
            "uBR: styles reset after closes");
    }

    private static function test_maliciousFaceValue_filtered():Void {
        // 事件属性/CSS 元字符注入不得进 fontFace——过滤到受限字符集
        var runs:Array = NativeTooltipDocument.htmlToRuns(
            "<FONT FACE=\"x' onmouseover='alert(1)'\">t</FONT>");
        var face:String = runs[0].fontFace;
        assert(face != null, "mal: face produced");
        assert(face.indexOf("'") < 0 && face.indexOf("\"") < 0 && face.indexOf("(") < 0
            && face.indexOf(")") < 0 && face.indexOf(";") < 0 && face.indexOf("<") < 0
            && face.indexOf(">") < 0 && face.indexOf("=") < 0 && face.indexOf(":") < 0,
            "mal: no CSS/event metachars in face, actual=" + face);
        // 未闭合引号 → face 属性无效（fontFace 省略），标签外的文本不受影响
        runs = NativeTooltipDocument.htmlToRuns("<FONT FACE='broken>t</FONT>z");
        var joined:String = "";
        for (var i:Number = 0; i < runs.length; i++) joined += runs[i].text;
        assertEq("tz", joined, "mal: unterminated quote → text kept verbatim");
        assert(runs[0].fontFace == undefined, "mal: broken face value omitted");
    }

    private static function test_nestedFontBold():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns(
            "<FONT COLOR='#00FF00'><B>嵌套</B></FONT>普通");
        assertEq(2, runs.length, "nested: two runs");
        assertEq("嵌套", runs[0].text, "nested: styled text");
        assertEq("#00FF00", runs[0].color, "nested: color");
        assertEq(true, runs[0].bold, "nested: bold");
        assertEq("普通", runs[1].text, "nested: plain after close");
        assert(runs[1].color == undefined && runs[1].bold == undefined, "nested: plain unstyled");
    }

    private static function test_br_newlineRun():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("<B>甲</B><BR>乙");
        assertEq(3, runs.length, "br: three runs");
        assertEq("甲", runs[0].text, "br: first text");
        assertEq("\n", runs[1].text, "br: newline run");
        assert(runs[1].bold == undefined, "br: newline run unstyled");
        assertEq("乙", runs[2].text, "br: second text (style popped by boundary)");
    }

    private static function test_p_paragraph():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("<P>首段<P>次段");
        // 首个 <P> 不产生空行；第二个 <P> 在已有产出后插入换行 run
        var joined:String = "";
        for (var i:Number = 0; i < runs.length; i++) joined += runs[i].text;
        assertEq("首段\n次段", joined, "p: joined with newline, no leading break");
    }

    private static function test_entities_singleParse():Void {
        // 关键反例：&lt;b&gt;literal&lt;/b&gt; 解析一次后必须显示为字面 "<b>literal</b>"，
        // 不得再被当作标记（二次解析会错误变粗体并吞文本）。
        var runs:Array = NativeTooltipDocument.htmlToRuns("&lt;b&gt;literal&lt;/b&gt;");
        assertEq(1, runs.length, "entity: single run");
        assertEq("<b>literal</b>", runs[0].text, "entity: decoded to literal markup text");
        assert(runs[0].bold == undefined, "entity: NOT bold (single parse only)");

        var runs2:Array = NativeTooltipDocument.htmlToRuns("A&amp;B&nbsp;C&quot;D&apos;E&#65;&#x42;");
        assertEq(1, runs2.length, "entity2: single run");
        assertEq("A&B C\"D'EAB", runs2[0].text, "entity2: all common entities decoded");

        var runs3:Array = NativeTooltipDocument.htmlToRuns("x&unknown;y");
        assertEq("x&unknown;y", runs3[0].text, "entity3: unknown entity kept literal");
    }

    private static function test_chineseText():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("<FONT COLOR='#FFCC00'>力量</FONT>：+10<BR>敏捷：+5");
        assertEq(4, runs.length, "cn: four runs");
        assertEq("力量", runs[0].text, "cn: label text");
        assertEq("#FFCC00", runs[0].color, "cn: label color");
        assertEq("：+10", runs[1].text, "cn: value text");
        assertEq("\n", runs[2].text, "cn: newline run");
        assertEq("敏捷：+5", runs[3].text, "cn: second line");
    }

    private static function test_unknownTagStripped():Void {
        // <I> 已是合法标签，本用例改用真未知标签验证剥离语义
        var runs:Array = NativeTooltipDocument.htmlToRuns("<DIV><FOO>x</FOO></DIV>y");
        var joined:String = "";
        for (var i:Number = 0; i < runs.length; i++) joined += runs[i].text;
        assertEq("xy", joined, "unknown tags stripped, text kept");
        assert(runs[0].italic == undefined, "unknown tags: no italic leaked");
    }

    private static function test_orphanLt_literal():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("a<b");
        assertEq("a<b", runs[0].text, "orphan '<' kept literal");
    }

    private static function test_crlf_normalized():Void {
        var runs:Array = NativeTooltipDocument.htmlToRuns("a\r\nb\rc");
        assertEq(1, runs.length, "crlf: single run");
        assertEq("a\nb\nc", runs[0].text, "crlf normalized to \\n");
    }

    private static function test_buildItem_shape():Void {
        var itemData:Object = {name:"n", displayname:"显示名", icon:"ico_n"};
        var iconData:Object = {icon:"ico_skin", displayname:"涂装名"};
        var doc:Object = NativeTooltipDocument.buildItem("n", itemData, iconData,
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

    private static function test_buildItem_realInstance():Void {
        // 真实实例：fixture "测试军刀" 经业务权威链生成描述，document 保留真实数值文本
        var itemData:Object = ItemUtil.getItemData("测试军刀");
        assert(itemData != null, "realItem: fixture loaded");
        var desc:String = TooltipComposer.generateItemDescriptionText(itemData, null);
        var intro:String = TooltipComposer.generateIntroPanelContent(null, itemData, {level:9});
        var doc:Object = NativeTooltipDocument.buildItem("测试军刀", itemData, null, intro, desc);
        assertEq("测试军刀", doc.title, "realItem: title");
        var all:String = "";
        for (var s:Number = 0; s < doc.sections.length; s++) {
            var secRuns:Array = doc.sections[s].runs;
            for (var r:Number = 0; r < secRuns.length; r++) all += secRuns[r].text;
        }
        assert(all.length > 0, "realItem: runs carry generated content");
        assert(all.indexOf("100") >= 0 || all.indexOf("威力") >= 0,
            "realItem: real stats text present in runs");
    }

    private static function test_buildSkill_shape():Void {
        var doc:Object = NativeTooltipDocument.buildSkill("闪避", "<B>闪避</B><BR>被动", "向指定方向翻滚");
        assertEq("闪避", doc.title, "skill: title");
        assertEq("skill", doc.icon.kind, "skill: icon kind");
        assertEq("闪避", doc.icon.name, "skill: icon name = 技能名");
        assertEq("dense", doc.profile, "skill: profile");
        assertEq(2, doc.sections.length, "skill: sections");
    }

    // 回归：血色光剑天秤 <skill>{skillname,cd,hp,mp}</skill> 是无 description 的
    // 结构化对象——旧实现 else 分支 String(skill) 会把 "[object Object]" 写进注释。
    private static function test_skillInfo_objectWithoutDescription():Void {
        var info:Array = TooltipTextBuilder.buildSkillInfo(
            {skillname:"猩红天秤", cd:24000, hp:0, mp:0});
        var joined:String = info.join("");
        assert(joined.indexOf("[object Object]") < 0,
            "skillObj: no [object Object], got=" + joined);
        assert(joined.indexOf("猩红天秤") >= 0, "skillObj: skillname shown");
        assert(joined.indexOf("【主动战技】") >= 0, "skillObj: active-skill label");
        assert(joined.indexOf("【战技信息】") >= 0 && joined.indexOf("冷却24秒") >= 0,
            "skillObj: cooldown summary, got=" + joined);

        // 该 HTML 再进 document 链路时 run 文本同样不得含对象字面量
        var doc:Object = NativeTooltipDocument.buildBody(joined, null);
        var all:String = "";
        for (var s:Number = 0; s < doc.sections.length; s++) {
            var secRuns:Array = doc.sections[s].runs;
            for (var r:Number = 0; r < secRuns.length; r++) all += secRuns[r].text;
        }
        assert(all.indexOf("[object Object]") < 0 && all.indexOf("猩红天秤") >= 0,
            "skillObj: document runs clean");

        // 空对象 / 无 skillname 对象：不字符串化、不产 lone <BR>
        assertEq(0, TooltipTextBuilder.buildSkillInfo({}).length,
            "skillObj: empty object → no content");
        assertEq(0, TooltipTextBuilder.buildSkillInfo({cd:1000}).length,
            "skillObj: nameless object → no content");

        // description 分支不变：description 文本 + 冷却/消耗概要
        var descJoined:String = TooltipTextBuilder.buildSkillInfo(
            {description:"战技说明", cd:9000, mp:40}).join("");
        assert(descJoined.indexOf("战技说明") >= 0
            && descJoined.indexOf("冷却9秒") >= 0
            && descJoined.indexOf("消耗40MP") >= 0,
            "skillDesc: description branch intact, got=" + descJoined);

        // 裸字符串形态保持 legacy（旧式内联描述）
        var strJoined:String = TooltipTextBuilder.buildSkillInfo("旧式描述文本").join("");
        assert(strJoined.indexOf("旧式描述文本") >= 0,
            "skillStr: string kept, got=" + strJoined);
    }

    private static function test_buildBody_simple():Void {
        var doc:Object = NativeTooltipDocument.buildBody("<B>删除任务</B>", null);
        assertEq("simple", doc.profile, "body: default profile simple");
        assertEq(1, doc.sections.length, "body: one section");
        assertEq("body", doc.sections[0].role, "body: role");
        assertEq("删除任务", doc.sections[0].runs[0].text, "body: text");
        assertEq(true, doc.sections[0].runs[0].bold, "body: bold");

        var empty:Object = NativeTooltipDocument.buildBody("", null);
        assertEq(0, empty.sections.length, "body: empty content → no sections");
    }
    private static function test_layoutType():Void {
        var weapon:Object = NativeTooltipDocument.buildItem("武器", {type:"武器", icon:"x"}, null, "简介", "说明");
        var material:Object = NativeTooltipDocument.buildItem("材料", {type:"材料", icon:"x"}, null, "简介", "说明");
        var potion:Object = NativeTooltipDocument.buildItem("药剂", {type:"消耗品", use:"药剂", icon:"x"}, null, "简介", "说明");
        assertEq("wide", weapon.layoutType, "layout: weapon wide");
        assertEq("narrow", material.layoutType, "layout: material with icon narrow");
        assertEq("wide", potion.layoutType, "layout: potion use wide");
        assertEq("wide", NativeTooltipDocument.buildSkill("闪避", "简介", "说明").layoutType, "layout: skill wide");
    }

}
