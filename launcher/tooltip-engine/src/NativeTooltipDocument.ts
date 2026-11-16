// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/NativeTooltipDocument.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace NativeTooltipDocument {
        export const ROLE_INTRO: string = "intro";
        export const ROLE_DESCRIPTION: string = "description";
        export const ROLE_BODY: string = "body";
        export const ROLE_SUB: string = "sub";
        export const PROFILE_SIMPLE: string = "simple";
        export const PROFILE_DENSE: string = "dense";
        export const PROFILE_PINNED: string = "pinned";
        export function buildItem(name?: string, itemData?: any, iconData?: any, introHtml?: string, descHtml?: string, subHtmls?: any[], extras?: any): any {
            var iconName: string = null;
            var title: string = null;
            if (iconData != null) {
                if (iconData.icon != undefined && iconData.icon != "")
                    iconName = String(iconData.icon);
                if (iconData.displayname != undefined && iconData.displayname != "")
                    title = String(iconData.displayname);
            }
            if (iconName == null && itemData != null
                && itemData.icon != undefined && itemData.icon != "") {
                iconName = String(itemData.icon);
            }
            if (title == null && itemData != null
                && itemData.displayname != undefined && itemData.displayname != "") {
                title = String(itemData.displayname);
            }
            if (title == null)
                title = name;
            var sections: any[] = [];
            if (descHtml != null && extras != null && extras.upgrades != null) {
                var upgradeStart: number = descHtml.lastIndexOf(TooltipConstants.LBL_UPGRADE_PATH);
                if (upgradeStart >= 0) {
                    var headerStart: number = descHtml.toLowerCase().lastIndexOf("<font", upgradeStart);
                    descHtml = descHtml.substring(0, headerStart >= 0 ? headerStart : upgradeStart);
                }
            }
            pushSection(sections, ROLE_INTRO, introHtml);
            pushSection(sections, ROLE_DESCRIPTION, descHtml);
            if (subHtmls != null) {
                for (var si: number = 0; si < subHtmls.length; si++) {
                    var subEntry: any = subHtmls[si];
                    if (typeof subEntry == "string") {
                        pushSection(sections, ROLE_SUB, String(subEntry));
                    }
                    else if (subEntry != null) {
                        pushAttachments(sections, subEntry);
                    }
                }
            }
            title = dedupeTitleLine(title, sections);
            var icon: any = (iconName != null) ? { kind: "item", name: iconName } : null;
            var doc: any = buildSectioned(title, icon, sections, PROFILE_DENSE);
            var typeName: string = (itemData != null && itemData.type != undefined) ? String(itemData.type) : "";
            if (typeName == "消耗品" && itemData.use != undefined)
                typeName = String(itemData.use);
            doc.layoutType = (typeName == "武器" || typeName == "防具" || typeName == "技能" || typeName == "药剂") ? "wide" : "narrow";
            attachExtras(doc, extras);
            return doc;
        }
        function attachExtras(doc?: any, extras?: any): void {
            if (extras == null)
                return;
            if (Array.isArray(extras.rail)) {
                var rail: any[] = [];
                for (var i: number = 0; i < extras.rail.length && i < 2; i++) {
                    var text: string = safeText(extras.rail[i]);
                    if (text == null)
                        continue;
                    if (rail.length > 0 && rail[rail.length - 1] == text)
                        continue;
                    rail.push(text);
                }
                if (rail.length > 0)
                    doc.rail = rail;
            }
            var mag: any = extras.magazine;
            if (mag != null) {
                var magName: string = safeText(mag.name);
                if (magName != null) {
                    var magazine: any = { name: magName };
                    var magIcon: string = safeText(mag.icon);
                    if (magIcon != null)
                        magazine.icon = magIcon;
                    var magAmmo: string = safeText(mag.ammo);
                    if (magAmmo != null)
                        magazine.ammo = magAmmo;
                    doc.magazine = magazine;
                }
            }
            if (extras.upgrades != null) {
                pushAttachments(doc.sections, extras.upgrades, ROLE_DESCRIPTION);
            }
        }
        function pushAttachments(sections?: any[], entry?: any, targetRole?: string): void {
            if (targetRole == null)
                targetRole = ROLE_SUB;
            var kind: string = (entry != null && entry.kind != undefined) ? String(entry.kind) : null;
            if (kind != "attachments" && kind != "acquisition" && kind != "modinfo"
                && kind != "upgrades") {
                if (entry != null && entry.html != undefined) {
                    pushSection(sections, targetRole, String(entry.html));
                }
                return;
            }
            var title: string = safeText(entry.title);
            var rows: any[] = [];
            var fallback: any[] = [];
            if (title != null) {
                fallback.push({ text: title + "：", bold: true });
                fallback.push({ text: "\n" });
            }
            var source: any[] = (Array.isArray(entry.rows)) ? entry.rows : [];
            for (var i: number = 0; i < source.length; i++) {
                var raw: any = source[i];
                if (raw == null)
                    continue;
                var rowName: string = safeText(raw.name);
                if (rowName == null && kind != "modinfo")
                    continue;
                var effectHtml: string = (raw.effect == undefined || raw.effect == null)
                    ? "" : String(raw.effect);
                var row: any = { name: (rowName != null ? rowName : ""), runs: htmlToRuns(effectHtml) };
                if (rowName == null && row.runs.length == 0)
                    continue;
                var rowIcon: string = safeText(raw.icon);
                if (rowIcon != null)
                    row.icon = rowIcon;
                if (as2Number(raw.depth) === 1)
                    row.depth = 1;
                rows.push(row);
                var fallbackPrefix: string = row.depth === 1 ? "    • "
                    : (kind == "attachments" ? "  • " : "");
                fallback.push({ text: fallbackPrefix + (rowName != null ? rowName : "") });
                var effectRuns: any[] = row.runs;
                for (var r: number = 0; r < effectRuns.length; r++)
                    fallback.push(effectRuns[r]);
                fallback.push({ text: "\n" });
            }
            if (rows.length == 0)
                return;
            var section: any = { role: targetRole, kind: kind, rows: rows };
            if (title != null)
                section.title = title;
            section.runs = fallback;
            sections.push(section);
        }
        function safeText(value?: any): string {
            if (value == null || value == undefined)
                return null;
            var s: string = trimBlank(String(value));
            if (s.length == 0 || s == "null" || s == "undefined")
                return null;
            return s;
        }
        export function buildSkill(skillName?: string, introHtml?: string, descHtml?: string): any {
            var sections: any[] = [];
            pushSection(sections, ROLE_INTRO, introHtml);
            pushSection(sections, ROLE_DESCRIPTION, descHtml);
            var icon: any = (skillName != null && skillName != "")
                ? { kind: "skill", name: String(skillName) } : null;
            var doc: any = buildSectioned(dedupeTitleLine(skillName, sections), icon, sections, PROFILE_DENSE);
            doc.layoutType = "wide";
            return doc;
        }
        export function buildBody(bodyHtml?: string, profile?: string): any {
            var sections: any[] = [];
            pushSection(sections, ROLE_BODY, bodyHtml);
            return buildSectioned(null, null, sections, (profile != null && profile != "") ? profile : PROFILE_SIMPLE);
        }
        export function buildSectioned(title?: string, icon?: any, sections?: any[], profile?: string): any {
            var doc: any = { version: 1 };
            if (title != null && title != "")
                doc.title = String(title);
            if (icon != null && icon.name != undefined && icon.name != "") {
                doc.icon = {
                    kind: (icon.kind != undefined && icon.kind != "") ? String(icon.kind) : "item",
                    name: String(icon.name)
                };
            }
            doc.profile = (profile != null && profile != "") ? String(profile) : PROFILE_SIMPLE;
            doc.sections = (sections != null) ? sections : [];
            return doc;
        }
        export function makeSection(role?: string, html?: string): any {
            return { role: role, runs: htmlToRuns(html) };
        }
        function pushSection(sections?: any[], role?: string, html?: string): void {
            var section: any = makeSection(role, html);
            if (section.runs.length > 0)
                sections.push(section);
        }
        export function dedupeTitleLine(title?: string, sections?: any[]): string {
            if (title == null || title == "" || sections == null || sections.length == 0)
                return title;
            var sec: any = sections[0];
            if (sec.role != ROLE_INTRO || sec.runs == null || sec.runs.length == 0)
                return title;
            var first: string = String(sec.runs[0].text);
            var match: boolean = (first == title);
            if (!match && first.length > title.length
                && first.substring(first.length - title.length) == title) {
                var prefix: string = first.substring(0, first.length - title.length);
                match = prefix.length > 2
                    && prefix.charAt(0) == "["
                    && prefix.charAt(prefix.length - 1) == "]";
            }
            if (!match)
                return title;
            if (sec.runs.length > 1 && sec.runs[1].text != "\n")
                return title;
            var rest: any[] = sec.runs.slice(1);
            if (rest.length > 0 && rest[0].text == "\n")
                rest.shift();
            if (rest.length == 0)
                sections.shift();
            else
                sec.runs = rest;
            return first;
        }
        export function htmlToRuns(html?: string): any[] {
            var runs: any[] = [];
            if (html == null)
                return runs;
            var s: string = String(html);
            var len: number = s.length;
            if (len == 0)
                return runs;
            var stack: any[] = [];
            var pending: string = "";
            var i: number = 0;
            while (i < len) {
                var code: number = s.charCodeAt(i);
                if (code == 60) {
                    var tagEndIndex: number = s.indexOf(">", i + 1);
                    if (tagEndIndex < 0) {
                        pending += "<";
                        i++;
                        continue;
                    }
                    var tagBody: string = s.substring(i + 1, tagEndIndex);
                    var kind: number = classifyTag(tagBody);
                    if (kind == 1) {
                        pending = flushPending(runs, pending, stack);
                        pushRun(runs, "\n", null, false, false, false, NaN, null);
                    }
                    else if (kind == 2) {
                        pending = flushPending(runs, pending, stack);
                        if (runs.length > 0)
                            pushRun(runs, "\n", null, false, false, false, NaN, null);
                    }
                    else if (kind == 3) {
                        pending = flushPending(runs, pending, stack);
                        stack.push({
                            color: parseFontColor(tagBody),
                            size: parseFontSize(tagBody),
                            face: parseFontFace(tagBody),
                            font: true, bold: false, italic: false, underline: false
                        });
                    }
                    else if (kind == 4) {
                        pending = flushPending(runs, pending, stack);
                        popStyle(stack, "font");
                    }
                    else if (kind == 5) {
                        pending = flushPending(runs, pending, stack);
                        stack.push({ bold: true });
                    }
                    else if (kind == 6) {
                        pending = flushPending(runs, pending, stack);
                        popStyle(stack, "bold");
                    }
                    else if (kind == 7) {
                        pending = flushPending(runs, pending, stack);
                        stack.push({ italic: true });
                    }
                    else if (kind == 8) {
                        pending = flushPending(runs, pending, stack);
                        popStyle(stack, "italic");
                    }
                    else if (kind == 9) {
                        pending = flushPending(runs, pending, stack);
                        stack.push({ underline: true });
                    }
                    else if (kind == 10) {
                        pending = flushPending(runs, pending, stack);
                        popStyle(stack, "underline");
                    }
                    i = tagEndIndex + 1;
                    continue;
                }
                if (code == 38) {
                    var semi: number = s.indexOf(";", i + 1);
                    if (semi > i && semi - i <= 10) {
                        var decoded: string = decodeEntity(s.substring(i + 1, semi));
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
                if (code == 13) {
                    pending += "\n";
                    i++;
                    if (i < len && s.charCodeAt(i) == 10)
                        i++;
                    continue;
                }
                pending += s.charAt(i);
                i++;
            }
            flushPending(runs, pending, stack);
            return runs;
        }
        function flushPending(runs?: any[], pending?: string, stack?: any[]): string {
            if (pending.length > 0) {
                pushRun(runs, pending, currentColor(stack), currentBold(stack), currentFlag(stack, "italic"), currentFlag(stack, "underline"), currentFontSize(stack), currentFontFace(stack));
            }
            return "";
        }
        function pushRun(runs?: any[], text?: string, color?: string, bold?: boolean, italic?: boolean, underline?: boolean, fontSize?: number, fontFace?: string): void {
            if (text == null || text.length == 0)
                return;
            var run: any = { text: text };
            if (color != null && color != "")
                run.color = color;
            if (bold === true)
                run.bold = true;
            if (italic === true)
                run.italic = true;
            if (underline === true)
                run.underline = true;
            if (!as2IsNaN(fontSize))
                run.fontSize = fontSize;
            if (fontFace != null && fontFace != "")
                run.fontFace = fontFace;
            runs.push(run);
        }
        function currentColor(stack?: any[]): string {
            for (var i: number = stack.length - 1; i >= 0; i--) {
                if (stack[i].color != null)
                    return stack[i].color;
            }
            return null;
        }
        function currentBold(stack?: any[]): boolean {
            return currentFlag(stack, "bold");
        }
        function currentFlag(stack?: any[], flag?: string): boolean {
            for (var i: number = stack.length - 1; i >= 0; i--) {
                if (stack[i][flag] === true)
                    return true;
            }
            return false;
        }
        function currentFontSize(stack?: any[]): number {
            for (var i: number = stack.length - 1; i >= 0; i--) {
                if (stack[i].size != null && !as2IsNaN(stack[i].size))
                    return stack[i].size;
            }
            return NaN;
        }
        function currentFontFace(stack?: any[]): string {
            for (var i: number = stack.length - 1; i >= 0; i--) {
                if (stack[i].face != null && stack[i].face != "")
                    return stack[i].face;
            }
            return null;
        }
        function popStyle(stack?: any[], flag?: string): void {
            for (var i: number = stack.length - 1; i >= 0; i--) {
                if (stack[i][flag] === true) {
                    stack.splice(i);
                    return;
                }
            }
            if (flag == "font" && stack.length > 0)
                stack.pop();
        }
        function classifyTag(tagBody?: string): number {
            if (tagBody == null)
                return 0;
            var t: string = trimBlank(tagBody);
            if (t.length == 0)
                return 0;
            var closing: boolean = (t.charAt(0) == "/");
            var name: string = closing ? t.substring(1) : t;
            var end: number = name.length;
            for (var k: number = 0; k < name.length; k++) {
                var c: number = name.charCodeAt(k);
                if (c == 32 || c == 9 || c == 10 || c == 13 || c == 47) {
                    end = k;
                    break;
                }
            }
            name = name.substring(0, end).toLowerCase();
            if (name == "br")
                return 1;
            if (name == "p")
                return closing ? 0 : 2;
            if (name == "font")
                return closing ? 4 : 3;
            if (name == "b" || name == "strong")
                return closing ? 6 : 5;
            if (name == "i" || name == "em")
                return closing ? 8 : 7;
            if (name == "u")
                return closing ? 10 : 9;
            return 0;
        }
        function readFontAttr(tagBody?: string, name?: string): string {
            if (tagBody == null)
                return null;
            var lower: string = tagBody.toLowerCase();
            var nameLen: number = name.length;
            var from: number = 0;
            while (true) {
                var idx: number = lower.indexOf(name, from);
                if (idx < 0)
                    return null;
                if (idx > 0) {
                    var prev: number = lower.charCodeAt(idx - 1);
                    if (!(prev == 32 || prev == 9 || prev == 10 || prev == 13 || prev == 47)) {
                        from = idx + 1;
                        continue;
                    }
                }
                var after: number = idx + nameLen;
                if (after < lower.length) {
                    var nc: number = lower.charCodeAt(after);
                    if (!(nc == 32 || nc == 9 || nc == 10 || nc == 13 || nc == 61)) {
                        from = idx + 1;
                        continue;
                    }
                }
                var attributeEqualsAt: number = tagBody.indexOf("=", after);
                if (attributeEqualsAt < 0)
                    return null;
                var mid: string = tagBody.substring(after, attributeEqualsAt);
                var clean: boolean = true;
                for (var m: number = 0; m < mid.length; m++) {
                    var mc: number = mid.charCodeAt(m);
                    if (!(mc == 32 || mc == 9 || mc == 10 || mc == 13)) {
                        clean = false;
                        break;
                    }
                }
                if (!clean) {
                    from = after;
                    continue;
                }
                var tail: string = trimEdge(tagBody.substring(attributeEqualsAt + 1), " \t\r\n");
                if (tail.length == 0)
                    return null;
                var quote: string = tail.charAt(0);
                if (quote == "'" || quote == "\"") {
                    var qend: number = tail.indexOf(quote, 1);
                    if (qend < 0)
                        return null;
                    return tail.substring(1, qend);
                }
                var vend: number = 0;
                while (vend < tail.length && " \t\r\n".indexOf(tail.charAt(vend)) < 0)
                    vend++;
                return tail.substring(0, vend);
            }
        }
        function parseFontColor(tagBody?: string): string {
            return normalizeHexColor(readFontAttr(tagBody, "color"));
        }
        function normalizeHexColor(value?: string): string {
            if (value == null)
                return null;
            var hex: string = trimEdge(value, " \t\r\n");
            if (hex.charAt(0) == "#") {
                hex = hex.substring(1);
            }
            else if (hex.length > 2 && hex.substring(0, 2).toLowerCase() == "0x") {
                hex = hex.substring(2);
            }
            if (hex.length == 3) {
                hex = hex.charAt(0) + hex.charAt(0)
                    + hex.charAt(1) + hex.charAt(1)
                    + hex.charAt(2) + hex.charAt(2);
            }
            if (hex.length != 6)
                return null;
            for (var k: number = 0; k < 6; k++) {
                var c: number = hex.charCodeAt(k);
                var isHex: boolean = (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
                if (!isHex)
                    return null;
            }
            return "#" + hex.toUpperCase();
        }
        function parseFontSize(tagBody?: string): number {
            var raw: string = readFontAttr(tagBody, "size");
            if (raw == null)
                return NaN;
            var i: number = 0;
            var n: number = raw.length;
            while (i < n && isSpaceCode(raw.charCodeAt(i)))
                i++;
            var sign: number = 1;
            if (i < n) {
                var sc: number = raw.charCodeAt(i);
                if (sc == 43)
                    i++;
                else if (sc == 45) {
                    sign = -1;
                    i++;
                }
            }
            var v: number = 0;
            var digits: number = 0;
            while (i < n) {
                var c: number = raw.charCodeAt(i);
                if (c < 48 || c > 57)
                    break;
                v = v * 10 + (c - 48);
                digits++;
                i++;
            }
            if (digits == 0)
                return NaN;
            v *= sign;
            return (v >= 1 && v <= 96) ? v : NaN;
        }
        function parseFontFace(tagBody?: string): string {
            var raw: string = readFontAttr(tagBody, "face");
            if (raw == null)
                return null;
            var out: string = "";
            var n: number = raw.length;
            for (var i: number = 0; i < n; i++) {
                var c: number = raw.charCodeAt(i);
                if (c == 32) {
                    if (out.length > 0 && out.charCodeAt(out.length - 1) != 32)
                        out += " ";
                    continue;
                }
                if (isFaceChar(c))
                    out += as2FromCharCode(c);
            }
            while (out.length > 0 && out.charCodeAt(out.length - 1) == 32) {
                out = out.substring(0, out.length - 1);
            }
            if (out.length > 64)
                out = out.substring(0, 64);
            return (out.length > 0) ? out : null;
        }
        function isFaceChar(c?: number): boolean {
            return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
                || c == 95 || c == 45 || (c >= 0x4E00 && c <= 0x9FA5);
        }
        function isSpaceCode(c?: number): boolean {
            return c == 32 || (c >= 9 && c <= 13) || c == 0xA0 || c == 0x1680
                || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029
                || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF;
        }
        function decodeEntity(entity?: string): string {
            if (entity == null || entity.length == 0)
                return null;
            var lower: string = entity.toLowerCase();
            if (lower == "amp")
                return "&";
            if (lower == "lt")
                return "<";
            if (lower == "gt")
                return ">";
            if (lower == "quot")
                return "\"";
            if (lower == "apos")
                return "'";
            if (lower == "nbsp")
                return " ";
            if (entity.charAt(0) == "#") {
                var hex: boolean = entity.length > 1 && (entity.charAt(1) == "x" || entity.charAt(1) == "X");
                var digits: string = entity.substring(hex ? 2 : 1);
                if (digits.length == 0)
                    return null;
                var v: number = 0;
                for (var d: number = 0; d < digits.length; d++) {
                    var dc: number = digits.charCodeAt(d);
                    var digit: number;
                    if (dc >= 48 && dc <= 57)
                        digit = dc - 48;
                    else if (hex && dc >= 65 && dc <= 70)
                        digit = dc - 55;
                    else if (hex && dc >= 97 && dc <= 102)
                        digit = dc - 87;
                    else
                        return null;
                    v = hex ? v * 16 + digit : v * 10 + digit;
                    if (v > 0xFFFF)
                        return null;
                }
                return as2FromCharCode(v);
            }
            return null;
        }
        function trimBlank(s?: string): string {
            return trimEdge(s, " \t\r\n");
        }
        function trimEdge(s?: string, chars?: string): string {
            var a: number = 0;
            var b: number = s.length;
            while (a < b && chars.indexOf(s.charAt(a)) >= 0)
                a++;
            while (b > a && chars.indexOf(s.charAt(b - 1)) >= 0)
                b--;
            return s.substring(a, b);
        }
    }
}
