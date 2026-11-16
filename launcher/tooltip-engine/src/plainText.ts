// Preserves StringUtils.htmlToPlainTextFast behavior for ChoiceReward.details.
namespace TooltipEngine {
    export function plainText(input: string): string {
        if (input == null || input == undefined)
            return "";
        var s: string = String(input);
        var len: number = s.length;
        var i: number = 0;
        var out: any[] = [];
        var ch: number;
        while (i < len) {
            ch = s.charCodeAt(i);
            if (ch == 60) {
                var j: number = i + 1;
                while (j < len) {
                    var c: number = s.charCodeAt(j);
                    if (c == 32 || c == 9 || c == 10 || c == 13)
                        j++;
                    else
                        break;
                }
                if (j < len && s.charAt(j) == "/")
                    j++;
                while (j < len) {
                    c = s.charCodeAt(j);
                    if (c == 32 || c == 9)
                        j++;
                    else
                        break;
                }
                var start: number = j;
                while (j < len) {
                    c = s.charCodeAt(j);
                    if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57))
                        j++;
                    else
                        break;
                }
                var tag: string = s.substring(start, j).toLowerCase();
                while (j < len && s.charAt(j) != ">")
                    j++;
                if (j < len)
                    j++;
                if (tag == "br" || tag == "p" || tag == "div" || tag == "li" || tag == "ul" || tag == "ol" ||
                    tag == "h1" || tag == "h2" || tag == "h3" || tag == "h4" || tag == "h5" || tag == "h6" ||
                    tag == "tr" || tag == "table" || tag == "thead" || tag == "tbody" || tag == "tfoot") {
                    out.push("\n");
                }
                i = j;
                continue;
            }
            if (ch == 38) {
                var k: number = i + 1;
                var semi: number = k;
                while (semi < len && s.charAt(semi) != ";")
                    semi++;
                if (semi < len) {
                    var entity: string = s.substring(k, semi);
                    var decoded: string = null;
                    if (entity.length > 0 && entity.charAt(0) == "#") {
                        if (entity.length > 1 && (entity.charAt(1) == "x" || entity.charAt(1) == "X")) {
                            var v: number = 0;
                            var idx: number = 2;
                            while (idx < entity.length) {
                                var cc: number = entity.charCodeAt(idx);
                                if (cc >= 48 && cc <= 57)
                                    v = v * 16 + (cc - 48);
                                else if (cc >= 65 && cc <= 70)
                                    v = v * 16 + (cc - 55);
                                else if (cc >= 97 && cc <= 102)
                                    v = v * 16 + (cc - 87);
                                else
                                    break;
                                idx++;
                            }
                            decoded = as2FromCharCode(v);
                        }
                        else {
                            var v10: number = 0;
                            var idx2: number = 1;
                            while (idx2 < entity.length) {
                                var c2: number = entity.charCodeAt(idx2);
                                if (c2 >= 48 && c2 <= 57) {
                                    v10 = v10 * 10 + (c2 - 48);
                                    idx2++;
                                }
                                else
                                    break;
                            }
                            decoded = as2FromCharCode(v10);
                        }
                    }
                    else {
                        var e: string = entity.toLowerCase();
                        if (e == "amp")
                            decoded = "&";
                        else if (e == "lt")
                            decoded = "<";
                        else if (e == "gt")
                            decoded = ">";
                        else if (e == "quot")
                            decoded = "\"";
                        else if (e == "apos")
                            decoded = "'";
                        else if (e == "nbsp")
                            decoded = " ";
                    }
                    if (decoded != null) {
                        out.push(decoded);
                        i = semi + 1;
                        continue;
                    }
                }
                out.push("&");
                i++;
                continue;
            }
            if (ch == 13) {
                out.push("\n");
                i++;
                continue;
            }
            out.push(s.charAt(i));
            i++;
        }
        var raw: string = out.join("");
        var resParts: any[] = [];
        var prevSpace: boolean = false;
        var nlCount: number = 0;
        var L: number = raw.length;
        for (i = 0; i < L; i++) {
            var chs: string = raw.charAt(i);
            var code: number = raw.charCodeAt(i);
            if (chs == "\n") {
                if (nlCount < 2)
                    resParts.push("\n");
                nlCount++;
                prevSpace = false;
            }
            else if (code == 32 || code == 9 || code == 160) {
                if (!prevSpace) {
                    resParts.push(" ");
                    prevSpace = true;
                }
            }
            else {
                resParts.push(chs);
                prevSpace = false;
                nlCount = 0;
            }
        }
        var joined: string = resParts.join("");
        var lines: any[] = joined.split("\n");
        for (i = 0; i < lines.length; i++) {
            lines[i] = trim(lines[i]);
        }
        var finalStr: string = lines.join("\n");
        return trim(finalStr);
    }
}
