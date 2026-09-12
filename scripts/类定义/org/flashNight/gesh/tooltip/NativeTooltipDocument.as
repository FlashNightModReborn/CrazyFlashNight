/**
 * NativeTooltipDocument - 共享注释语义文档构建器（COMMON 桥协议 v1）
 *
 * 职责：
 * - 把 TooltipComposer / SkillTooltipComposer 产出的业务权威 HTML **一次性**解析为
 *   受限语义文档 document：{version, title?, icon?, sections:[{role,
 *   runs:[{text,color?,bold?,italic?,underline?,fontSize?,fontFace?}]}], profile, layoutType?}
 * - document.title 与 sections[].runs[].text 均为**纯文本**：实体已解码、内联标记
 *   已展开为 run 级样式键。C#/Web 消费端不得对 title/run.text 再做标记展开
 *   或实体解码（二次解析会改变语义，例如 &lt;b&gt;x&lt;/b&gt; 应显示为字面
 *   "<b>x</b>" 文本而非粗体）。
 * - 仅识别旧注释已有标记：<FONT COLOR/SIZE/FACE>、<B>/<STRONG>、<I>/<EM>、<U>、
 *   <BR>、<P>；其余标签剥离。孤立 '<' 无 '>' 配对按字面文本保留。
 *   样式语义对齐迁移前 Web convertAS2Html（tooltip.js）：
 *   fontSize 按 JS parseInt(_,10) 规则取 1..96；fontFace 过滤为受限字体名
 *   （仅 [0-9A-Za-z_]/CJK U+4E00..U+9FA5/空格/连字符，≤64 字符），由消费端
 *   经各自字体 catalog 映射（Web=CF7FontCatalog.legacyFamily），非 CSS 片段；
 *   color 接受 #RGB 三位并展开为 #RRGGBB（与 Web/CSS 一致）。
 *
 * 典型用法：
 *   var doc = NativeTooltipDocument.buildItem(name, itemData, iconData, introHtml, descHtml);
 *   if (NativeTooltipBridge.show(doc) == null) { // 回退旧 Flash 渲染 }
 */
class org.flashNight.gesh.tooltip.NativeTooltipDocument {

    // ── 段角色 / profile 常量 ──
    public static var ROLE_INTRO:String = "intro";
    public static var ROLE_DESCRIPTION:String = "description";
    public static var ROLE_BODY:String = "body";

    public static var PROFILE_SIMPLE:String = "simple";
    public static var PROFILE_DENSE:String = "dense";
    public static var PROFILE_PINNED:String = "pinned";

    // ── 高层构建入口 ──

    /**
     * 物品注释文档。title 取 displayname（涂装实例经 iconData/getData 覆盖优先），
     * icon.name 为图标资产键（itemData.icon，与 Web Icons 目录键同源）。
     */
    public static function buildItem(name:String, itemData:Object, iconData:Object,
            introHtml:String, descHtml:String):Object {
        var iconName:String = null;
        var title:String = null;
        if (iconData != null) {
            if (iconData.icon != undefined && iconData.icon != "") iconName = String(iconData.icon);
            if (iconData.displayname != undefined && iconData.displayname != "") title = String(iconData.displayname);
        }
        if (iconName == null && itemData != null
                && itemData.icon != undefined && itemData.icon != "") {
            iconName = String(itemData.icon);
        }
        if (title == null && itemData != null
                && itemData.displayname != undefined && itemData.displayname != "") {
            title = String(itemData.displayname);
        }
        if (title == null) title = name;

        var sections:Array = [];
        pushSection(sections, ROLE_INTRO, introHtml);
        pushSection(sections, ROLE_DESCRIPTION, descHtml);
        title = dedupeTitleLine(title, sections);
        var icon:Object = (iconName != null) ? {kind:"item", name:iconName} : null;
        var doc:Object = buildSectioned(title, icon, sections, PROFILE_DENSE);
        var typeName:String = (itemData != null && itemData.type != undefined) ? String(itemData.type) : "";
        if (typeName == "消耗品" && itemData.use != undefined) typeName = String(itemData.use);
        // 与 Web inferLayoutType 同源分类，展示端不根据图标是否存在猜布局。
        doc.layoutType = (typeName == "武器" || typeName == "防具" || typeName == "技能" || typeName == "药剂") ? "wide" : "narrow";
        return doc;
    }

    /** 技能注释文档。icon.name = 技能名（对应旧 "图标-"+技能名 链接）。 */
    public static function buildSkill(skillName:String, introHtml:String, descHtml:String):Object {
        var sections:Array = [];
        pushSection(sections, ROLE_INTRO, introHtml);
        pushSection(sections, ROLE_DESCRIPTION, descHtml);
        var icon:Object = (skillName != null && skillName != "")
            ? {kind:"skill", name:String(skillName)} : null;
        var doc:Object = buildSectioned(dedupeTitleLine(skillName, sections), icon, sections, PROFILE_DENSE);
        doc.layoutType = "wide";
        return doc;
    }

    /** 通用短提示文档（_root.注释 / 工作台 body 段）。默认 simple。 */
    public static function buildBody(bodyHtml:String, profile:String):Object {
        var sections:Array = [];
        pushSection(sections, ROLE_BODY, bodyHtml);
        return buildSectioned(null, null, sections,
            (profile != null && profile != "") ? profile : PROFILE_SIMPLE);
    }

    /** 低层装配：显式给出 title/icon/sections/profile。 */
    public static function buildSectioned(title:String, icon:Object, sections:Array, profile:String):Object {
        var doc:Object = {version:1};
        if (title != null && title != "") doc.title = String(title);
        if (icon != null && icon.name != undefined && icon.name != "") {
            doc.icon = {
                kind:(icon.kind != undefined && icon.kind != "") ? String(icon.kind) : "item",
                name:String(icon.name)
            };
        }
        doc.profile = (profile != null && profile != "") ? String(profile) : PROFILE_SIMPLE;
        doc.sections = (sections != null) ? sections : [];
        return doc;
    }

    public static function makeSection(role:String, html:String):Object {
        return {role:role, runs:htmlToRuns(html)};
    }

    private static function pushSection(sections:Array, role:String, html:String):Void {
        var section:Object = makeSection(role, html);
        if (section.runs.length > 0) sections.push(section);
    }

    /**
     * 简介段标题去重（仅在文档构建边界发生）。
     *
     * 业务生成器（buildIntroHeader / 技能简介）的首行固定是 <B>[tier]名称</B><BR>
     * 标题头；宿主侧又会把 document.title 渲染为标题行。两者并存会多画一次名称。
     * 规则：intro 首段首个 run 文本与 title 相等、或以 title 结尾（允许 [tier] 前缀），
     * 且其后紧跟换行 run（首行确为独立标题行）时——把该完整首行提升为 title
     * （保留 [tier] 前缀），并从 intro 剥掉该 run 与紧随的 "\n" run；
     * 其余 runs（类型/价格/强化等级/词条颜色）原样保留。首行与 title 无关时不动。
     */
    private static function dedupeTitleLine(title:String, sections:Array):String {
        if (title == null || title == "" || sections == null || sections.length == 0) return title;
        var sec:Object = sections[0];
        if (sec.role != ROLE_INTRO || sec.runs == null || sec.runs.length == 0) return title;
        var first:String = String(sec.runs[0].text);
        var match:Boolean = (first == title);
        if (!match && first.length > title.length
                && first.substring(first.length - title.length) == title) {
            // 允许的前缀仅限 "[tier]" 形态，防止误剥以名称结尾的内容行
            var prefix:String = first.substring(0, first.length - title.length);
            match = prefix.length > 2
                && prefix.charAt(0) == "["
                && prefix.charAt(prefix.length - 1) == "]";
        }
        if (!match) return title;
        // 标题必须是独立行：后随换行 run，或首行即全部内容
        if (sec.runs.length > 1 && sec.runs[1].text != "\n") return title;
        var rest:Array = sec.runs.slice(1);
        if (rest.length > 0 && rest[0].text == "\n") rest.shift();
        if (rest.length == 0) sections.shift();
        else sec.runs = rest;
        return first;
    }

    // ── 受限标记 → 样式 run 解析 ──
    //
    // 样式帧栈：{color:String?, size:Number?, face:String?, font:Boolean,
    //           bold:Boolean, italic:Boolean, underline:Boolean}
    //   <FONT> 压 font:true 帧，携带 color/size/face 各自解析值（可缺省）
    //   <B>/<STRONG> 压 bold 帧；<I>/<EM> 压 italic 帧；<U> 压 underline 帧
    //   </FONT> 弹到最近 font 帧（含其上所有帧）；无 font 帧则只弹栈顶一帧
    //   </B>|</I>|</U>（含 strong/em 闭）弹到最近对应标记帧；无匹配容错忽略
    //   <BR>    flush 后追加无样式 run {text:"\n"}；不弹栈——<u>甲<BR>乙</u>
    //           的"乙"保持 underline（对齐 Web DOM 换行不断样式）
    //   <P>     flush 后若已有产出再追加 {text:"\n"}（首段不产生空行）
    // 文本实体解码后进入 pending，样式变化或换行时 flush 为带样式的 run。
    // 同名属性内层覆盖外层：currentX 自栈顶向下取首个定义该属性的帧。

    public static function htmlToRuns(html:String):Array {
        var runs:Array = [];
        if (html == null) return runs;
        var s:String = String(html);
        var len:Number = s.length;
        if (len == 0) return runs;

        var stack:Array = [];
        var pending:String = "";
        var i:Number = 0;

        while (i < len) {
            var code:Number = s.charCodeAt(i);

            if (code == 60) { // '<'
                var tagEndIndex:Number = s.indexOf(">", i + 1);
                if (tagEndIndex < 0) {
                    pending += "<";
                    i++;
                    continue;
                }
                var tagBody:String = s.substring(i + 1, tagEndIndex);
                var kind:Number = classifyTag(tagBody);
                if (kind == 1) { // <BR>
                    pending = flushPending(runs, pending, stack);
                    pushRun(runs, "\n", null, false, false, false, NaN, null);
                } else if (kind == 2) { // <P>
                    pending = flushPending(runs, pending, stack);
                    if (runs.length > 0) pushRun(runs, "\n", null, false, false, false, NaN, null);
                } else if (kind == 3) { // <FONT ...>
                    pending = flushPending(runs, pending, stack);
                    stack.push({
                        color:parseFontColor(tagBody),
                        size:parseFontSize(tagBody),
                        face:parseFontFace(tagBody),
                        font:true, bold:false, italic:false, underline:false
                    });
                } else if (kind == 4) { // </FONT>
                    pending = flushPending(runs, pending, stack);
                    popStyle(stack, "font");
                } else if (kind == 5) { // <B>/<STRONG>
                    pending = flushPending(runs, pending, stack);
                    stack.push({bold:true});
                } else if (kind == 6) { // </B>/</STRONG>
                    pending = flushPending(runs, pending, stack);
                    popStyle(stack, "bold");
                } else if (kind == 7) { // <I>/<EM>
                    pending = flushPending(runs, pending, stack);
                    stack.push({italic:true});
                } else if (kind == 8) { // </I>/</EM>
                    pending = flushPending(runs, pending, stack);
                    popStyle(stack, "italic");
                } else if (kind == 9) { // <U>
                    pending = flushPending(runs, pending, stack);
                    stack.push({underline:true});
                } else if (kind == 10) { // </U>
                    pending = flushPending(runs, pending, stack);
                    popStyle(stack, "underline");
                }
                // kind == 0：剥离未知标签
                i = tagEndIndex + 1;
                continue;
            }

            if (code == 38) { // '&'
                var semi:Number = s.indexOf(";", i + 1);
                if (semi > i && semi - i <= 10) {
                    var decoded:String = decodeEntity(s.substring(i + 1, semi));
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

            if (code == 13) { // '\r' / '\r\n' → '\n'
                pending += "\n";
                i++;
                if (i < len && s.charCodeAt(i) == 10) i++;
                continue;
            }

            pending += s.charAt(i);
            i++;
        }
        flushPending(runs, pending, stack);
        return runs;
    }

    // ── 私有辅助 ──

    /** pending 出栈为 run；返回重置后的空 pending。 */
    private static function flushPending(runs:Array, pending:String, stack:Array):String {
        if (pending.length > 0) {
            pushRun(runs, pending, currentColor(stack), currentBold(stack),
                currentFlag(stack, "italic"), currentFlag(stack, "underline"),
                currentFontSize(stack), currentFontFace(stack));
        }
        return "";
    }

    private static function pushRun(runs:Array, text:String, color:String, bold:Boolean,
            italic:Boolean, underline:Boolean, fontSize:Number, fontFace:String):Void {
        if (text == null || text.length == 0) return;
        var run:Object = {text:text};
        if (color != null && color != "") run.color = color;
        if (bold === true) run.bold = true;
        if (italic === true) run.italic = true;
        if (underline === true) run.underline = true;
        if (!isNaN(fontSize)) run.fontSize = fontSize;
        if (fontFace != null && fontFace != "") run.fontFace = fontFace;
        runs.push(run);
    }

    private static function currentColor(stack:Array):String {
        for (var i:Number = stack.length - 1; i >= 0; i--) {
            if (stack[i].color != null) return stack[i].color;
        }
        return null;
    }

    private static function currentBold(stack:Array):Boolean {
        return currentFlag(stack, "bold");
    }

    /** flag 类样式（bold/italic/underline）：任一存活帧置位即生效。 */
    private static function currentFlag(stack:Array, flag:String):Boolean {
        for (var i:Number = stack.length - 1; i >= 0; i--) {
            if (stack[i][flag] === true) return true;
        }
        return false;
    }

    /** size/face 类属性：栈顶向下取首个定义该属性的帧（内层覆盖外层）。 */
    private static function currentFontSize(stack:Array):Number {
        for (var i:Number = stack.length - 1; i >= 0; i--) {
            if (stack[i].size != null && !isNaN(stack[i].size)) return stack[i].size;
        }
        return NaN;
    }

    private static function currentFontFace(stack:Array):String {
        for (var i:Number = stack.length - 1; i >= 0; i--) {
            if (stack[i].face != null && stack[i].face != "") return stack[i].face;
        }
        return null;
    }

    /**
     * 按标记弹栈："font" 弹到最近 font 帧，"bold"/"italic"/"underline" 弹到
     * 最近置位对应标记的帧（均含其上所有帧）。
     * font 无匹配帧时仍弹栈顶一帧（沿用旧"无 color 帧弹顶层"容错）；
     * 其余标记无匹配容错忽略，不清空既有样式。
     */
    private static function popStyle(stack:Array, flag:String):Void {
        for (var i:Number = stack.length - 1; i >= 0; i--) {
            if (stack[i][flag] === true) {
                stack.splice(i);
                return;
            }
        }
        if (flag == "font" && stack.length > 0) stack.pop();
    }

    /**
     * 标签分类：0=剥离 1=<BR> 2=<P> 3=<FONT> 4=</FONT> 5=<B|STRONG> 6=</B|STRONG>
     * 7=<I|EM> 8=</I|EM> 9=<U> 10=</U>
     * 大小写不敏感；<BR/>、<FONT COLOR='..'> 等形态均可。
     */
    private static function classifyTag(tagBody:String):Number {
        if (tagBody == null) return 0;
        var t:String = trimBlank(tagBody);
        if (t.length == 0) return 0;
        var closing:Boolean = (t.charAt(0) == "/");
        var name:String = closing ? t.substring(1) : t;
        var end:Number = name.length;
        for (var k:Number = 0; k < name.length; k++) {
            var c:Number = name.charCodeAt(k);
            if (c == 32 || c == 9 || c == 10 || c == 13 || c == 47) { // 空白或 '/'
                end = k;
                break;
            }
        }
        name = name.substring(0, end).toLowerCase();

        if (name == "br") return 1;
        if (name == "p") return closing ? 0 : 2;
        if (name == "font") return closing ? 4 : 3;
        if (name == "b" || name == "strong") return closing ? 6 : 5;
        if (name == "i" || name == "em") return closing ? 8 : 7;
        if (name == "u") return closing ? 10 : 9;
        return 0;
    }

    /**
     * <FONT> 属性值抽取：name 前必须是串首/空白/'/'，name 后必须是空白或 '='
     * （防 "color" 命中 "mycolor"、"size" 命中 "asize"、值串内片段等粘连）；
     * '=' 与值之间只允许空白；值取引号内或首个非空白 token。
     * 无效/缺失返回 null。
     */
    private static function readFontAttr(tagBody:String, name:String):String {
        if (tagBody == null) return null;
        var lower:String = tagBody.toLowerCase();
        var nameLen:Number = name.length;
        var from:Number = 0;
        while (true) {
            var idx:Number = lower.indexOf(name, from);
            if (idx < 0) return null;
            if (idx > 0) {
                var prev:Number = lower.charCodeAt(idx - 1);
                if (!(prev == 32 || prev == 9 || prev == 10 || prev == 13 || prev == 47)) {
                    from = idx + 1;
                    continue;
                }
            }
            var after:Number = idx + nameLen;
            if (after < lower.length) {
                var nc:Number = lower.charCodeAt(after);
                if (!(nc == 32 || nc == 9 || nc == 10 || nc == 13 || nc == 61)) { // ws 或 '='
                    from = idx + 1;
                    continue;
                }
            }
            var attributeEqualsAt:Number = tagBody.indexOf("=", after);
            if (attributeEqualsAt < 0) return null;
            var mid:String = tagBody.substring(after, attributeEqualsAt);
            var clean:Boolean = true;
            for (var m:Number = 0; m < mid.length; m++) {
                var mc:Number = mid.charCodeAt(m);
                if (!(mc == 32 || mc == 9 || mc == 10 || mc == 13)) { clean = false; break; }
            }
            if (!clean) { from = after; continue; } // '=' 属于别的属性，继续找下一处 name
            var tail:String = trimEdge(tagBody.substring(attributeEqualsAt + 1), " \t\r\n");
            if (tail.length == 0) return null;
            var quote:String = tail.charAt(0);
            if (quote == "'" || quote == "\"") {
                var qend:Number = tail.indexOf(quote, 1);
                if (qend < 0) return null;
                return tail.substring(1, qend);
            }
            var vend:Number = 0;
            while (vend < tail.length && " \t\r\n".indexOf(tail.charAt(vend)) < 0) vend++;
            return tail.substring(0, vend);
        }
    }

    /** 解析 <FONT> 的 COLOR 属性，输出规范化 "#RRGGBB"（大写）；无效返回 null。 */
    private static function parseFontColor(tagBody:String):String {
        return normalizeHexColor(readFontAttr(tagBody, "color"));
    }

    /**
     * "#RRGGBB"/"RRGGBB"/"0xRRGGBB" → "#RRGGBB"；"#RGB" 三位按 CSS 规则逐位
     * 翻倍展开为 "#RRGGBB"（对齐 Web legacy as2FontStyle 的 3/6 位 hex 白名单）。
     * 其余 → null。
     */
    private static function normalizeHexColor(value:String):String {
        if (value == null) return null;
        var hex:String = trimEdge(value, " \t\r\n");
        if (hex.charAt(0) == "#") {
            hex = hex.substring(1);
        } else if (hex.length > 2 && hex.substring(0, 2).toLowerCase() == "0x") {
            hex = hex.substring(2);
        }
        if (hex.length == 3) {
            hex = hex.charAt(0) + hex.charAt(0)
                + hex.charAt(1) + hex.charAt(1)
                + hex.charAt(2) + hex.charAt(2);
        }
        if (hex.length != 6) return null;
        for (var k:Number = 0; k < 6; k++) {
            var c:Number = hex.charCodeAt(k);
            var isHex:Boolean = (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
            if (!isHex) return null;
        }
        return "#" + hex.toUpperCase();
    }

    /**
     * <FONT SIZE> → 1..96 的整数。按 JS parseInt(_,10) 语义：前导空白、可选
     * +/- 号、取前导十进制数字（"15px"→15、"+15"→15、"15.9"→15、无数字→NaN），
     * 再按 Web legacy 的 px>0 && px<=96 判定。无效返回 NaN。
     */
    private static function parseFontSize(tagBody:String):Number {
        var raw:String = readFontAttr(tagBody, "size");
        if (raw == null) return NaN;
        var i:Number = 0;
        var n:Number = raw.length;
        while (i < n && isSpaceCode(raw.charCodeAt(i))) i++;
        var sign:Number = 1;
        if (i < n) {
            var sc:Number = raw.charCodeAt(i);
            if (sc == 43) i++;            // '+'
            else if (sc == 45) { sign = -1; i++; } // '-'
        }
        var v:Number = 0;
        var digits:Number = 0;
        while (i < n) {
            var c:Number = raw.charCodeAt(i);
            if (c < 48 || c > 57) break;
            v = v * 10 + (c - 48);
            digits++;
            i++;
        }
        if (digits == 0) return NaN;
        v *= sign;
        return (v >= 1 && v <= 96) ? v : NaN;
    }

    /**
     * <FONT FACE> → 受限字体名：仅保留 [0-9A-Za-z_]、CJK U+4E00..U+9FA5、
     * 空格、连字符 '-'（与 Web legacy face.replace(/[^\w一-龥 \-]/g,'') 同款），
     * 连续空格折叠为一个、去首尾、≤64 字符；全过滤为空 → null。
     * 产出是字体名而非 CSS 片段：消费端必须经各自字体 catalog 映射使用。
     */
    private static function parseFontFace(tagBody:String):String {
        var raw:String = readFontAttr(tagBody, "face");
        if (raw == null) return null;
        var out:String = "";
        var n:Number = raw.length;
        for (var i:Number = 0; i < n; i++) {
            var c:Number = raw.charCodeAt(i);
            if (c == 32) { // 空格：折叠为单个，且不留首尾
                if (out.length > 0 && out.charCodeAt(out.length - 1) != 32) out += " ";
                continue;
            }
            if (isFaceChar(c)) out += String.fromCharCode(c);
            // 其余字符（含 \t\n 等）直接剥除——与 legacy replace 一致
        }
        while (out.length > 0 && out.charCodeAt(out.length - 1) == 32) {
            out = out.substring(0, out.length - 1);
        }
        if (out.length > 64) out = out.substring(0, 64);
        return (out.length > 0) ? out : null;
    }

    /** face 白名单字符：[0-9A-Za-z_]/CJK U+4E00..U+9FA5/'-'（空格在 parseFontFace 单独处理）。 */
    private static function isFaceChar(c:Number):Boolean {
        return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
            || c == 95 || c == 45 || (c >= 0x4E00 && c <= 0x9FA5);
    }

    /** JS \s 等价集（供 parseInt 前导空白跳过用）。 */
    private static function isSpaceCode(c:Number):Boolean {
        return c == 32 || (c >= 9 && c <= 13) || c == 0xA0 || c == 0x1680
            || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029
            || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF;
    }

    /** 实体解码：amp/lt/gt/quot/apos/nbsp + &#NN; / &#xHH;。未知返回 null。 */
    private static function decodeEntity(entity:String):String {
        if (entity == null || entity.length == 0) return null;
        var lower:String = entity.toLowerCase();
        if (lower == "amp") return "&";
        if (lower == "lt") return "<";
        if (lower == "gt") return ">";
        if (lower == "quot") return "\"";
        if (lower == "apos") return "'";
        if (lower == "nbsp") return " ";
        if (entity.charAt(0) == "#") {
            var hex:Boolean = entity.length > 1 && (entity.charAt(1) == "x" || entity.charAt(1) == "X");
            var digits:String = entity.substring(hex ? 2 : 1);
            if (digits.length == 0) return null;
            var v:Number = 0;
            for (var d:Number = 0; d < digits.length; d++) {
                var dc:Number = digits.charCodeAt(d);
                var digit:Number;
                if (dc >= 48 && dc <= 57) digit = dc - 48;
                else if (hex && dc >= 65 && dc <= 70) digit = dc - 55;
                else if (hex && dc >= 97 && dc <= 102) digit = dc - 87;
                else return null;
                v = hex ? v * 16 + digit : v * 10 + digit;
                if (v > 0xFFFF) return null; // 超出 BMP 不产出（代理对无意义）
            }
            return String.fromCharCode(v);
        }
        return null;
    }

    private static function trimBlank(s:String):String {
        return trimEdge(s, " \t\r\n");
    }

    /** 去除两端出现在 chars 集合中的字符。 */
    private static function trimEdge(s:String, chars:String):String {
        var a:Number = 0;
        var b:Number = s.length;
        while (a < b && chars.indexOf(s.charAt(a)) >= 0) a++;
        while (b > a && chars.indexOf(s.charAt(b - 1)) >= 0) b--;
        return s.substring(a, b);
    }
}
