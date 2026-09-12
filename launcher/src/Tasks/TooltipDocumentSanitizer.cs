using System;
using System.Globalization;
using System.Text;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// COMMON 桥协议 v1 tooltip document（受限语义文档）的宿主边界净化器。
    ///
    /// 背景：`_root.Web物品注释HTML` 的返回对象新增可选 `document` 字段，
    /// 与 descHTML/introHTML 同管道经各 task 的 tooltip 成功响应转发给 Web。
    /// 四个严格白名单 task（Inventory/Shop/NpcShop/Crafting）只允许该可选键，
    /// 不放宽其余 schema。
    ///
    /// 安全契约（与 Guardian.Hud.Tooltip.NativeTooltipDocument 的容错语义对齐）：
    ///   - document 缺失/非法：剥离该键（strip），不否决整包——旧 HTML 成功包
    ///     不得因新增可选字段异常而整体 malformed。
    ///   - 字段级异常只降级：未知 role→"body"、run 可为裸字符串、非法 color/
    ///     bold/italic/underline/fontSize/fontFace/profile 直接省略该键；
    ///     版本解析失败按缺省 1。
    ///   - run 可选样式键（对齐迁移前 Web convertAS2Html）：color 支持 #RGB
    ///     三位展开为 #RRGGBB；fontSize 按 JS parseInt(_,10) 语义取 1..96；
    ///     fontFace 过滤为受限字体名（[0-9A-Za-z_]/CJK U+4E00..U+9FA5/空格/
    ///     连字符，≤64 字符）——是字体名而非 CSS 片段，由消费端经 catalog 映射。
    ///   - 文档级拒绝（→剥离）：非对象、version 解析结果 ≠1、净化后无可渲染
    ///     内容（title/icon/任一非空 section 文本全缺）。
    ///   - 结构规模上界：section/run/字符总量超限时截断或剔除超限元素，
    ///     输出永远满足下列常量上界。
    ///   - 纯文本契约：title 与 runs[].text 逐字透传，不做 HTML 解析、
    ///     不做实体解码、不做内联标记展开（AS2 聚合端已展开一次）。
    ///   - 输出为白名单重建：document 内任何未列举键（owner/revision/自定义
    ///     字段）一律不转发。
    /// </summary>
    internal static class TooltipDocumentSanitizer
    {
        internal const string DocumentKey = "document";
        internal const int SupportedVersion = 1;

        internal const int MaxTitleChars = 1024;
        internal const int MaxSections = 16;
        internal const int MaxRunsPerSection = 64;
        internal const int MaxTotalRuns = 256;
        internal const int MaxRunTextChars = 65536;
        internal const int MaxTotalTextChars = 262144;
        internal const int MaxIconKindChars = 32;
        internal const int MaxIconNameChars = 256;
        internal const int MaxProfileChars = 16;
        internal const int MaxFontFaceChars = 64;

        /// <summary>
        /// 与 HasExactKeys 相同的严格白名单，但额外容忍至多一个 "document" 键
        /// （可选增量；其内容合法性由 TrySanitize 单独裁决）。
        /// expectedKeys 本身不含 "document"；若误含，则按普通必需键处理。
        /// </summary>
        internal static bool HasExactKeysAllowingOptionalDocument(
            JObject value,
            params string[] expectedKeys)
        {
            if (value == null) return false;
            bool expectedHasDocument = false;
            for (int i = 0; i < expectedKeys.Length; i++)
            {
                if (string.Equals(
                        expectedKeys[i], DocumentKey, StringComparison.Ordinal))
                {
                    expectedHasDocument = true;
                    break;
                }
            }
            int matched = 0;
            int documentCount = 0;
            foreach (JProperty property in value.Properties())
            {
                if (!expectedHasDocument
                    && string.Equals(
                        property.Name, DocumentKey, StringComparison.Ordinal))
                {
                    documentCount++;
                    continue;
                }
                bool found = false;
                for (int i = 0; i < expectedKeys.Length; i++)
                {
                    if (string.Equals(
                            property.Name, expectedKeys[i], StringComparison.Ordinal))
                    {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
                matched++;
            }
            return documentCount <= 1 && matched == expectedKeys.Length;
        }

        /// <summary>
        /// 净化 token 指向的 document。成功时 sanitized 为白名单重建的 JObject；
        /// 失败返回 false（调用方剥离该键，不否决整包响应）。
        /// </summary>
        internal static bool TrySanitize(JToken token, out JObject sanitized)
        {
            sanitized = null;
            JObject node = token as JObject;
            if (node == null || !IsSupportedVersion(node["version"])) return false;

            var output = new JObject { ["version"] = SupportedVersion };
            bool hasContent = false;
            int totalChars = 0;

            string title = ReadPlainText(node["title"], MaxTitleChars);
            if (title != null)
            {
                output["title"] = title;
                if (title.Length > 0) hasContent = true;
            }

            JObject iconNode = node["icon"] as JObject;
            if (iconNode != null)
            {
                string name = ReadPlainText(iconNode["name"], MaxIconNameChars);
                if (!string.IsNullOrEmpty(name))
                {
                    string kind = ReadPlainText(iconNode["kind"], MaxIconKindChars)
                        ?? "item";
                    output["icon"] = new JObject
                    {
                        ["kind"] = kind,
                        ["name"] = name
                    };
                    hasContent = true;
                }
            }

            string layoutType = node["layoutType"]?.Type == JTokenType.String ? (string)node["layoutType"] : null;
            if (layoutType == "wide" || layoutType == "narrow") output["layoutType"] = layoutType;

            string profile = NormalizeProfile(node["profile"]);
            if (profile != null) output["profile"] = profile;

            JArray sections = node["sections"] as JArray;
            if (sections != null)
            {
                var emittedSections = new JArray();
                int totalRuns = 0;
                foreach (JToken sectionToken in sections)
                {
                    if (emittedSections.Count >= MaxSections
                        || totalChars >= MaxTotalTextChars
                        || totalRuns >= MaxTotalRuns) break;
                    JObject sectionNode = sectionToken as JObject;
                    if (sectionNode == null) continue;

                    var cleanSection = new JObject
                    {
                        ["role"] = NormalizeRole(sectionNode["role"])
                    };
                    var cleanRuns = new JArray();
                    JArray runs = sectionNode["runs"] as JArray;
                    if (runs != null)
                    {
                        foreach (JToken runToken in runs)
                        {
                            if (cleanRuns.Count >= MaxRunsPerSection
                                || totalRuns >= MaxTotalRuns
                                || totalChars >= MaxTotalTextChars) break;
                            JObject cleanRun = SanitizeRun(runToken);
                            if (cleanRun == null) continue;
                            string text = cleanRun.Value<string>("text");
                            if (totalChars + text.Length > MaxTotalTextChars) break;
                            cleanRuns.Add(cleanRun);
                            totalRuns++;
                            totalChars += text.Length;
                            if (text.Length > 0) hasContent = true;
                        }
                    }
                    // 空 run 段保留：显式空段可占位（与 NativeTooltipDocument 一致）。
                    cleanSection["runs"] = cleanRuns;
                    emittedSections.Add(cleanSection);
                }
                if (emittedSections.Count > 0) output["sections"] = emittedSections;
            }

            if (!hasContent) return false;
            sanitized = output;
            return true;
        }

        /// <summary>
        /// 净化 source document 并落到 target["document"]；无/非法 document 时
        /// 保证 target 不携带该键（剥离语义，对克隆/重建两种调用路径都安全）。
        /// </summary>
        internal static void ApplyTo(JToken source, JObject target)
        {
            JObject doc;
            if (TrySanitize(source, out doc)) target[DocumentKey] = doc;
            else target.Remove(DocumentKey);
        }

        private static JObject SanitizeRun(JToken runToken)
        {
            JToken textToken = null;
            JToken colorToken = null;
            JToken boldToken = null;
            JToken italicToken = null;
            JToken underlineToken = null;
            JToken fontSizeToken = null;
            JToken fontFaceToken = null;
            JObject runNode = runToken as JObject;
            if (runNode != null)
            {
                textToken = runNode["text"];
                colorToken = runNode["color"];
                boldToken = runNode["bold"];
                italicToken = runNode["italic"];
                underlineToken = runNode["underline"];
                fontSizeToken = runNode["fontSize"];
                fontFaceToken = runNode["fontFace"];
            }
            else if (runToken != null && runToken.Type == JTokenType.String)
            {
                textToken = runToken;
            }
            else
            {
                return null;
            }
            string text = ReadPlainText(textToken, MaxRunTextChars);
            if (text == null) return null;

            var run = new JObject { ["text"] = text };
            string color = NormalizeColor(colorToken);
            if (color != null) run["color"] = color;
            if (boldToken != null && boldToken.Type == JTokenType.Boolean)
                run["bold"] = boldToken.Value<bool>();
            if (italicToken != null && italicToken.Type == JTokenType.Boolean)
                run["italic"] = italicToken.Value<bool>();
            if (underlineToken != null && underlineToken.Type == JTokenType.Boolean)
                run["underline"] = underlineToken.Value<bool>();
            int? fontSize = NormalizeFontSize(fontSizeToken);
            if (fontSize.HasValue) run["fontSize"] = fontSize.Value;
            string fontFace = NormalizeFontFace(fontFaceToken);
            if (fontFace != null) run["fontFace"] = fontFace;
            return run;
        }

        /// <summary>title/run.text/icon.name/kind 的纯文本上界校验：逐字保留，仅限长与非法控制字符。</summary>
        private static string ReadPlainText(JToken token, int maxChars)
        {
            if (token == null || token.Type != JTokenType.String) return null;
            string value = token.Value<string>();
            return IsPlainText(value, maxChars) ? value : null;
        }

        private static bool IsPlainText(string value, int maxChars)
        {
            if (value == null || value.Length > maxChars) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char current = value[i];
                if (char.IsControl(current)
                    && current != '\r' && current != '\n' && current != '\t')
                {
                    return false;
                }
            }
            return true;
        }

        /// <summary>
        /// version 缺失/无法解析按缺省 1（与 NativeTooltipDocument.ReadInt 容错一致）；
        /// 解析结果非 1 → false。
        /// </summary>
        private static bool IsSupportedVersion(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return true;
            try
            {
                if (token.Type == JTokenType.Integer)
                    return token.Value<long>() == SupportedVersion;
                if (token.Type == JTokenType.Float)
                    return token.Value<double>() == SupportedVersion;
                int parsed;
                if (int.TryParse(
                        token.ToString(),
                        NumberStyles.Integer,
                        CultureInfo.InvariantCulture,
                        out parsed))
                {
                    return parsed == SupportedVersion;
                }
            }
            catch { }
            return true;
        }

        /// <summary>未知/缺失 role 一律归入 "body"（不丢弃内容）；已知值归一化为小写。</summary>
        private static string NormalizeRole(JToken token)
        {
            if (token != null && token.Type == JTokenType.String)
            {
                string role = token.Value<string>();
                if (string.Equals(role, "intro", StringComparison.OrdinalIgnoreCase))
                    return "intro";
                if (string.Equals(role, "description", StringComparison.OrdinalIgnoreCase))
                    return "description";
            }
            return "body";
        }

        /// <summary>已知 profile 归一化为小写；未知/缺失 → null（省略，消费端默认 simple）。</summary>
        private static string NormalizeProfile(JToken token)
        {
            if (token == null || token.Type != JTokenType.String) return null;
            string profile = token.Value<string>();
            if (profile == null || profile.Length > MaxProfileChars) return null;
            if (string.Equals(profile, "simple", StringComparison.OrdinalIgnoreCase))
                return "simple";
            if (string.Equals(profile, "dense", StringComparison.OrdinalIgnoreCase))
                return "dense";
            if (string.Equals(profile, "pinned", StringComparison.OrdinalIgnoreCase))
                return "pinned";
            return null;
        }

        /// <summary>
        /// "#RRGGBB"/"RRGGBB"/"0xRRGGBB" → "#RRGGBB" 大写归一；"#RGB" 三位按 CSS
        /// 规则逐位翻倍（对齐 Web legacy as2FontStyle 白名单）。其余 → null。
        /// </summary>
        private static string NormalizeColor(JToken token)
        {
            if (token == null || token.Type != JTokenType.String) return null;
            string value = token.Value<string>();
            if (string.IsNullOrEmpty(value)) return null;
            string s = value.Trim();
            if (s.StartsWith("#", StringComparison.Ordinal)) s = s.Substring(1);
            else if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) s = s.Substring(2);
            if (s.Length == 3)
                s = new string(new[] { s[0], s[0], s[1], s[1], s[2], s[2] });
            if (s.Length != 6) return null;
            int rgb;
            if (!int.TryParse(
                    s, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out rgb))
                return null;
            return "#" + s.ToUpperInvariant();
        }

        /// <summary>
        /// run.fontSize：Integer 直接取；Float 向零截断；String 按 JS
        /// parseInt(_,10) 语义（前导空白、可选 +/-、前导数字）。限 1..96
        /// （Web legacy px>0 && px<=96），越界/无效 → null。
        /// </summary>
        private static int? NormalizeFontSize(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return null;
            try
            {
                if (token.Type == JTokenType.Integer)
                {
                    long v = token.Value<long>();
                    return (v >= 1 && v <= 96) ? (int?)v : null;
                }
                if (token.Type == JTokenType.Float)
                {
                    double d = Math.Truncate(token.Value<double>());
                    return (d >= 1 && d <= 96) ? (int?)d : null;
                }
                if (token.Type == JTokenType.String)
                    return ParseLegacyFontSize(token.Value<string>());
            }
            catch { }
            return null;
        }

        /// <summary>JS parseInt(s,10) 语义 + 1..96 判定；无效返回 null。</summary>
        private static int? ParseLegacyFontSize(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return null;
            int i = 0, n = raw.Length;
            while (i < n && char.IsWhiteSpace(raw[i])) i++;
            int sign = 1;
            if (i < n && (raw[i] == '+' || raw[i] == '-'))
            {
                if (raw[i] == '-') sign = -1;
                i++;
            }
            long v = 0;
            int digits = 0;
            while (i < n)
            {
                char c = raw[i];
                if (c < '0' || c > '9') break;
                v = v * 10 + (c - '0');
                if (v > 9600) return null; // 早退防溢出（仍恒 >96）
                digits++;
                i++;
            }
            if (digits == 0) return null;
            v *= sign;
            return (v >= 1 && v <= 96) ? (int?)v : null;
        }

        /// <summary>
        /// run.fontFace → 受限字体名：仅保留 [0-9A-Za-z_]、CJK U+4E00..U+9FA5、
        /// 空格、连字符（与 Web legacy face.replace(/[^\w一-龥 \-]/g,'') 同款），
        /// 空格折叠为单个、去首尾、≤MaxFontFaceChars；全过滤为空 → null。
        /// 产出是字体名而非 CSS 片段；消费端经各自字体 catalog 映射。
        /// </summary>
        private static string NormalizeFontFace(JToken token)
        {
            if (token == null || token.Type != JTokenType.String) return null;
            string value = token.Value<string>();
            if (string.IsNullOrEmpty(value)) return null;
            var sb = new StringBuilder(value.Length);
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                if (c == ' ')
                {
                    if (sb.Length > 0 && sb[sb.Length - 1] != ' ') sb.Append(' ');
                    continue;
                }
                if (IsFontFaceChar(c)) sb.Append(c);
                // 其余字符（含 \t\n 等）直接剥除——与 legacy replace 一致
            }
            string face = sb.ToString().TrimEnd(' ');
            if (face.Length > MaxFontFaceChars) face = face.Substring(0, MaxFontFaceChars);
            return face.Length > 0 ? face : null;
        }

        private static bool IsFontFaceChar(char c)
        {
            return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                || c == '_' || c == '-' || (c >= '一' && c <= '龥');
        }
    }
}
