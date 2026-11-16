// Content rules migrated from scripts/类定义/org/flashNight/gesh/tooltip/TooltipFormatter.as.
// This TypeScript source is the production authority; no AS2 runtime dependencies.
namespace TooltipEngine {
    export namespace TooltipFormatter {
        const DISPLAY_SNAP_EPSILON: number = 0.000000000001;
        const DISPLAY_SNAP_MAX_DECIMALS: number = 6;
        function snapDisplayNumber(value?: number): number {
            if (as2IsNaN(value) || !as2IsFinite(value))
                return value;
            var scale: number = 1;
            for (var digits: number = 0; as2LessEqual(digits, DISPLAY_SNAP_MAX_DECIMALS); digits++) {
                var scaled: number = value * scale;
                if (!as2IsFinite(scaled))
                    return value;
                var snapped: number = Math.round(scaled) / scale;
                if (as2LessEqual(Math.abs(value - snapped), DISPLAY_SNAP_EPSILON)) {
                    return as2Equal(snapped, 0) ? 0 : snapped;
                }
                scale *= 10;
            }
            return value;
        }
        function formatDisplayValue(value?: any): string {
            if (as2NotEqual(typeof value, "number"))
                return String(value);
            return String(snapDisplayNumber(as2Number(value)));
        }
        export function bold(s?: string): string {
            return "<B>" + s + "</B>";
        }
        export function color(s?: string, hex?: string): string {
            return "<FONT COLOR='" + hex + "'>" + s + "</FONT>";
        }
        export function br(): string {
            return "<BR>";
        }
        export function normalizeDescription(text?: string): string {
            var normalized: string = text.split("\r\n").join("\n");
            var lines: any[] = normalized.split("\n");
            var result: string = "";
            for (var i: number = 0; as2Less(i, lines.length); i++) {
                var line: string = lines[i];
                var j: number = 0;
                while (as2Less(j, line.length) && (as2Equal(line.charAt(j), " ") || as2Equal(line.charAt(j), "\t"))) {
                    j++;
                }
                line = line.substring(j);
                if (as2Equal(i, 0)) {
                    result = line;
                }
                else {
                    if (as2Equal(line.substring(0, 4).toUpperCase(), "<BR>")) {
                        result += line;
                    }
                    else {
                        result += "<BR>" + line;
                    }
                }
            }
            return result;
        }
        export function kv(label?: string, val?: any, suffix?: string): string {
            if (suffix === undefined)
                suffix = "";
            return label + "：" + val + suffix;
        }
        export function numLine(buf?: any[], label?: string, val?: any, suffix?: string): void {
            if (val === undefined || val === null)
                return;
            var n: number = as2Number(val);
            if (!as2IsNaN(n) && n === 0)
                return;
            if (val === "" || as2Equal(val, "0") || as2Equal(val, "null"))
                return;
            buf.push(label, "：", (as2IsNaN(n) ? val : n), (suffix ? suffix : ""), "<BR>");
        }
        export function upgradeLine(buf?: any[], data?: any, equipData?: any, property?: string, label?: string, suffix?: string, afterValueHtml?: string): void {
            var base: any = data?.[property];
            var final: any = equipData?.[property];
            if (!base && !final)
                return;
            if (!label)
                label = TooltipConstants.PROPERTY_DICT[property];
            if (!label)
                label = property;
            if (!suffix)
                suffix = "";
            if (!afterValueHtml)
                afterValueHtml = "";
            if (!equipData || as2Equal(final, base)) {
                buf.push(label, "：", formatDisplayValue(base), suffix, afterValueHtml, "<BR>");
                return;
            }
            if (as2Equal(base, null))
                base = 0;
            if (as2IsNaN(final) || as2IsNaN(base)) {
                buf.push(label, "：<FONT COLOR='" + TooltipConstants.COL_HL + "'>", formatDisplayValue(final), suffix, "</FONT>", afterValueHtml);
                buf.push(" (" + TooltipConstants.TXT_OVERRIDE + formatDisplayValue(base) + ")<BR>");
            }
            else {
                var displayBase: number = snapDisplayNumber(as2Number(base));
                var displayFinal: number = snapDisplayNumber(as2Number(final));
                var enhance: number = snapDisplayNumber(displayFinal - displayBase);
                if (as2Equal(enhance, 0)) {
                    buf.push(label, "：", displayFinal, suffix, afterValueHtml, "<BR>");
                    return;
                }
                buf.push(label, "：<FONT COLOR='" + TooltipConstants.COL_HL + "'>", displayFinal, suffix, "</FONT>", afterValueHtml);
                var sign: string;
                if (as2Less(enhance, 0)) {
                    enhance = -enhance;
                    sign = " - ";
                }
                else {
                    sign = " + ";
                }
                buf.push(" (", displayBase, sign, enhance, ")<BR>");
            }
        }
        export function colorLine(buf?: any[], hex?: string, text?: string): void {
            if (as2Equal(text, undefined) || as2Equal(text, ""))
                return;
            buf.push("<FONT COLOR='" + hex + "'>", text, "</FONT><BR>");
        }
        export function enhanceLine(buf?: any[], type?: string, data?: any, property?: string, val?: any, label?: string): void {
            var base: any = data?.[property];
            if (!val)
                return;
            if (!label)
                label = TooltipConstants.PROPERTY_DICT[property];
            if (!label)
                label = property;
            if (type === "add") {
                var n: number = as2Number(val);
                if (as2IsNaN(n) || n === 0)
                    return;
                var sign: any = " + ";
                if (as2Less(n, 0)) {
                    n = -n;
                    sign = " - ";
                }
                buf.push(label, sign, n, "<BR>");
            }
            else if (type === "multiply") {
                if (!base)
                    return;
                var n: number = (as2Number(val) * 100) >> 0;
                var sign: any = " + ";
                if (as2Less(n, 0)) {
                    n = -n;
                    sign = " - ";
                }
                if (as2IsNaN(n) || n === 0)
                    return;
                buf.push(label, sign, n, "%<BR>");
            }
            else if (type === "override") {
                buf.push(label, " -> ", val, "<BR>");
            }
        }
        export function statLine(buf?: any[], type?: string, property?: string, val?: any, label?: string): void {
            if (!val)
                return;
            if (!label)
                label = TooltipConstants.PROPERTY_DICT[property];
            if (!label)
                label = property;
            if (type === "add") {
                var n: number = as2Number(val);
                if (as2IsNaN(n) || n === 0)
                    return;
                var sign: any = " + ";
                if (as2Less(n, 0)) {
                    n = -n;
                    sign = " - ";
                }
                buf.push(label, sign, n, "<BR>");
            }
            else if (type === "multiply") {
                var n: number = (as2Number(val) * 100) >> 0;
                var sign: any = " + ";
                if (as2Less(n, 0)) {
                    n = -n;
                    sign = " - ";
                }
                if (as2IsNaN(n) || n === 0)
                    return;
                buf.push(label, sign, n, "%<BR>");
            }
            else if (type === "override") {
                buf.push(label, " -> ", val, "<BR>");
            }
            else if (type === "merge") {
                buf.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TAG_MERGE + "</FONT> ", label, " -> ", val, "<BR>");
            }
        }
    }
}
