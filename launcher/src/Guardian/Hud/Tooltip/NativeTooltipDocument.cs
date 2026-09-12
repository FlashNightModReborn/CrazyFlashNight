using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Text;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.Tooltip
{
    /// <summary>tooltip document 交互 profile。与 COMMON 桥协议 / web PanelTooltip 三态对应。</summary>
    public enum NativeTooltipProfile
    {
        /// <summary>短提示：单面板、不命中、不滚动。</summary>
        Simple,
        /// <summary>密集检视：可分栏、不命中、长文由 owner 转发滚轮。</summary>
        Dense,
        /// <summary>固定检视器：分栏 + header + 独立滚动，命中参与。</summary>
        Pinned
    }

    /// <summary>受限语义文档的段落角色。未知 role 一律归入 Body，不丢弃内容。</summary>
    public enum NativeTooltipSectionRole
    {
        /// <summary>简介段：进左 intro 面板（icon 下/旁），分栏时的左栏。</summary>
        Intro,
        /// <summary>描述段：分栏时的右栏正文；merge 时拼入 intro 末尾。</summary>
        Description,
        /// <summary>正文段：与 description 同栏追加，顺序保留。</summary>
        Body
    }

    /// <summary>
    /// 已展开的样式 run。Text 为纯文本（内联标记已解析为样式键），
    /// '\n' 保留为硬换行（run 内可出现，布局时按行切分——切分/分片必须
    /// 把 Color/Bold/Italic/Underline/FontSize/FontFace 一并复制给每个片段）。
    /// 可选样式语义对齐迁移前 Web convertAS2Html：FontSize 为 legacy
    /// font-size 绝对 px 值（1..96）；FontFace 为受限字体名（已过滤到
    /// [0-9A-Za-z_]/CJK/空格/连字符，无 CSS 元字符），由渲染端经字体
    /// catalog 映射（Web=CF7FontCatalog.legacyFamily），未命中按默认字体。
    /// </summary>
    public sealed class NativeTooltipRun
    {
        public string Text;
        public Color? Color;
        public bool Bold;
        public bool Italic;
        public bool Underline;
        public int? FontSize;
        public string FontFace;

        public NativeTooltipRun() { }
        public NativeTooltipRun(string text, Color? color, bool bold)
        {
            Text = text;
            Color = color;
            Bold = bold;
        }
        public NativeTooltipRun(string text, Color? color, bool bold,
            bool italic = false, bool underline = false,
            int? fontSize = null, string fontFace = null)
        {
            Text = text;
            Color = color;
            Bold = bold;
            Italic = italic;
            Underline = underline;
            FontSize = fontSize;
            FontFace = fontFace;
        }
    }

    /// <summary>tooltip document 段落。</summary>
    public sealed class NativeTooltipSection
    {
        public NativeTooltipSectionRole Role;
        public List<NativeTooltipRun> Runs = new List<NativeTooltipRun>();

        /// <summary>纯文本视图（诊断/评分用），run 间无分隔符。</summary>
        public string PlainText
        {
            get
            {
                if (Runs.Count == 0) return "";
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < Runs.Count; i++)
                    if (Runs[i].Text != null) sb.Append(Runs[i].Text);
                return sb.ToString();
            }
        }
    }

    /// <summary>
    /// icon 引用。catalog 无按 kind 分派：kind=="item" 与 kind=="skill" 共用
    /// launcher/web/icons/manifest.json 命名空间（技能图标烘焙时剥掉「图标-」
    /// linkage 前缀，以裸技能名为键）；敌人/纸娃娃按 ref 名（"敌人-*"/"纸娃娃-*"）
    /// 自动路由到头像库/胸像库。未知 kind 查不到时渲染层画占位框。
    /// </summary>
    public sealed class NativeTooltipIcon
    {
        public string Kind;
        public string Name;
        public bool IsItem { get { return string.Equals(Kind, "item", StringComparison.Ordinal); } }
    }

    /// <summary>
    /// COMMON 桥协议 v1 的 tooltip document（受限语义文档）。
    ///
    /// 线格式：
    ///   payload  = {version:1, requestId, sceneId, x, y, owner?, revision?, document:{...}}
    ///   document = {version:1, title, icon:{kind,name}, profile,
    ///               sections:[{role, runs:[{text, color?, bold?}]}]}
    ///
    /// 纯文本契约（COMMON 合流修正）：title 与 run.text 都是 AS2 聚合端
    /// htmlToRuns 已展开的纯文本，C# 逐字保留——不得再做内联标记展开或实体解码。
    /// 反例：原始 HTML "&lt;b&gt;literal&lt;/b&gt;" 聚合一次后 text 应为字面量
    /// "&lt;b&gt;literal&lt;/b&gt;"；此处再解析会错误加粗并吞掉字符。
    /// 旧 HTML 转换仅保留在 FromLegacyHtmlDocument 旧入口（见下），与纯文档入口分开。
    ///
    /// 解析容错原则：字段缺失/类型异常只降级，不抛；version 非 1 拒绝。
    /// 解析结果不可变预期：widget 持有期间不得改写（实现上只对内部 List 做只读消费）。
    /// </summary>
    public sealed class NativeTooltipDocument
    {
        public const int SupportedVersion = 1;

        public int Version { get; private set; }
        public string Title { get; private set; }
        public List<NativeTooltipRun> TitleRuns { get; private set; }
        public NativeTooltipProfile Profile { get; private set; }
        public string LayoutType { get; private set; }
        public NativeTooltipIcon Icon { get; private set; }
        public List<NativeTooltipSection> Sections { get; private set; }

        // 桥身份（payload 层）
        public string RequestId { get; private set; }
        public string SceneId { get; private set; }
        public string Owner { get; private set; }
        public long Revision { get; private set; }
        public float AnchorX { get; private set; }
        public float AnchorY { get; private set; }
        public bool HasAnchor { get; private set; }
        public RectangleF? AnchorRect { get; private set; }
        public string PlacementHint { get; private set; }

        private NativeTooltipDocument() { }

        /// <summary>完整 tooltip.show payload → document。校验失败返回 null（不抛）。</summary>
        public static NativeTooltipDocument FromPayload(JObject payload)
        {
            string error;
            NativeTooltipDocument doc;
            return TryFromPayload(payload, out doc, out error) ? doc : null;
        }

        public static bool TryFromPayload(JObject payload, out NativeTooltipDocument doc)
        {
            string error;
            return TryFromPayload(payload, out doc, out error);
        }

        /// <summary>
        /// 解析 tooltip.show payload。document 子对象缺失时回退把 payload 本身当 document
        /// （便于直接喂 document JSON 的测试/诊断入口）。version 非 1 或 document 无内容 → false。
        /// </summary>
        public static bool TryFromPayload(JObject payload,
            out NativeTooltipDocument doc, out string error)
        {
            doc = null;
            error = null;
            if (payload == null) { error = "payload null"; return false; }

            int version = ReadInt(payload, "version", SupportedVersion);
            if (version != SupportedVersion) { error = "unsupported version " + version; return false; }

            JObject documentNode = payload["document"] as JObject;
            if (documentNode == null)
            {
                // payload 即 document 的退化形态：要求至少带 sections/title 其一
                if (payload["sections"] != null || payload["title"] != null) documentNode = payload;
            }
            if (documentNode == null) { error = "document missing"; return false; }

            doc = new NativeTooltipDocument();
            doc.Version = version;
            doc.RequestId = ReadString(payload, "requestId");
            doc.SceneId = ReadString(payload, "sceneId");
            doc.Owner = ReadString(payload, "owner");
            doc.Revision = ReadLong(payload, "revision", 0);
            if (doc.Owner == null) doc.Owner = ReadString(documentNode, "owner");
            if (doc.Revision == 0) doc.Revision = ReadLong(documentNode, "revision", 0);
            double ax = ReadDouble(payload, "x", double.NaN);
            double ay = ReadDouble(payload, "y", double.NaN);
            if (!double.IsNaN(ax) && !double.IsNaN(ay))
            {
                doc.AnchorX = (float)ax;
                doc.AnchorY = (float)ay;
                doc.HasAnchor = true;
            }

            JObject anchorRect = payload["anchorRect"] as JObject;
            if (payload["anchorRect"] != null)
            {
                if (anchorRect == null) { error = "invalid anchorRect"; doc = null; return false; }
                double x = ReadDouble(anchorRect, "x", double.NaN);
                double y = ReadDouble(anchorRect, "y", double.NaN);
                double width = ReadDouble(anchorRect, "width", double.NaN);
                double height = ReadDouble(anchorRect, "height", double.NaN);
                if (!double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(width)
                    || !double.IsFinite(height) || Math.Abs(x) > 8192 || Math.Abs(y) > 8192
                    || width <= 0 || height <= 0 || width > 8192 || height > 8192)
                {
                    error = "invalid anchorRect";
                    doc = null;
                    return false;
                }
                doc.AnchorRect = new RectangleF((float)x, (float)y, (float)width, (float)height);
            }
            string hint = ReadString(payload, "placement");
            if (hint == "left" || hint == "right" || hint == "top" || hint == "bottom")
                doc.PlacementHint = hint;

            string docError;
            if (!doc.PopulateDocument(documentNode, out docError))
            {
                error = docError;
                doc = null;
                return false;
            }
            return true;
        }

        /// <summary>仅 document 节点 → document（无桥身份，供测试/离线 fixture）。纯文本入口。</summary>
        public static NativeTooltipDocument FromDocument(JObject documentNode)
        {
            if (documentNode == null) return null;
            NativeTooltipDocument doc = new NativeTooltipDocument();
            doc.Version = ReadInt(documentNode, "version", SupportedVersion);
            if (doc.Version != SupportedVersion) return null;
            string error;
            return doc.PopulateDocument(documentNode, out error) ? doc : null;
        }

        /// <summary>
        /// 旧 HTML 兼容入口：与纯文档入口刻意分开。
        /// 仅当上游仍是旧 htmlText（未跑 htmlToRuns）时使用——title/run.text 会经
        /// NativeTooltipMarkup 做一次受限展开（font color / b / br / p / 实体）。
        /// 桥 v1 document 是已展开纯文本，绝对不要走这里，否则二次解析。
        /// </summary>
        public static NativeTooltipDocument FromLegacyHtmlDocument(JObject documentNode)
        {
            NativeTooltipDocument doc = FromDocument(documentNode);
            if (doc == null) return null;
            if (!string.IsNullOrEmpty(doc.Title))
                doc.TitleRuns = NativeTooltipMarkup.Flatten(doc.Title, null, true);
            foreach (NativeTooltipSection section in doc.Sections)
            {
                List<NativeTooltipRun> expanded = new List<NativeTooltipRun>(section.Runs.Count);
                NativeTooltipMarkup.FlatState state = new NativeTooltipMarkup.FlatState();
                foreach (NativeTooltipRun run in section.Runs)
                {
                    state.Reset(run);
                    NativeTooltipMarkup.FlattenInto(run.Text, expanded, state);
                }
                section.Runs = expanded;
            }
            return doc;
        }

        /// <summary>是否有可渲染内容（title / icon / 任一非空 section）。</summary>
        public bool HasContent
        {
            get
            {
                if (!string.IsNullOrEmpty(Title)) return true;
                if (Icon != null && !string.IsNullOrEmpty(Icon.Name)) return true;
                for (int i = 0; i < Sections.Count; i++)
                    if (Sections[i].PlainText.Length > 0) return true;
                return false;
            }
        }

        /// <summary>指定角色的全部段落（保留原始顺序）。</summary>
        public IEnumerable<NativeTooltipSection> SectionsByRole(NativeTooltipSectionRole role)
        {
            for (int i = 0; i < Sections.Count; i++)
                if (Sections[i].Role == role) yield return Sections[i];
        }

        public string Describe()
        {
            return "tooltip v" + Version + " profile=" + Profile
                + " req=" + (RequestId ?? "-") + " scene=" + (SceneId ?? "-")
                + " owner=" + (Owner ?? "-") + " rev=" + Revision
                + " title=" + (Title ?? "-")
                + " icon=" + (Icon != null ? (Icon.Kind + ":" + Icon.Name) : "-")
                + " sections=" + Sections.Count;
        }

        // ── document 节点填充 ──

        private bool PopulateDocument(JObject node, out string error)
        {
            error = null;
            // document 自带显式 version 时同样须为 1（payload 已查外层 version）
            int docVersion = ReadInt(node, "version", SupportedVersion);
            if (docVersion != SupportedVersion) { error = "unsupported document version " + docVersion; return false; }

            Title = ReadString(node, "title");
            // 纯文本契约：title 逐字保留；渲染层把标题整体按粗体呈现（表达样式，非解析）。
            TitleRuns = string.IsNullOrEmpty(Title)
                ? new List<NativeTooltipRun>()
                : new List<NativeTooltipRun> { new NativeTooltipRun(Title, null, true) };

            LayoutType = string.Equals(ReadString(node, "layoutType"), "narrow", StringComparison.Ordinal) ? "narrow" : "wide";
            string profile = ReadString(node, "profile");
            Profile = string.Equals(profile, "dense", StringComparison.OrdinalIgnoreCase) ? NativeTooltipProfile.Dense
                : string.Equals(profile, "pinned", StringComparison.OrdinalIgnoreCase) ? NativeTooltipProfile.Pinned
                : NativeTooltipProfile.Simple;

            JObject iconNode = node["icon"] as JObject;
            if (iconNode != null)
            {
                string name = ReadString(iconNode, "name");
                if (!string.IsNullOrEmpty(name))
                    Icon = new NativeTooltipIcon { Kind = ReadString(iconNode, "kind") ?? "item", Name = name };
            }

            Sections = new List<NativeTooltipSection>();
            JArray sections = node["sections"] as JArray;
            if (sections != null)
            {
                foreach (JToken token in sections)
                {
                    JObject secNode = token as JObject;
                    if (secNode == null) continue;
                    NativeTooltipSection section = new NativeTooltipSection();
                    section.Role = ParseRole(ReadString(secNode, "role"));

                    JArray runs = secNode["runs"] as JArray;
                    if (runs != null)
                    {
                        foreach (JToken runToken in runs)
                        {
                            JObject runNode = runToken as JObject;
                            string text;
                            Color? baseColor = null;
                            bool baseBold = false;
                            bool baseItalic = false;
                            bool baseUnderline = false;
                            int? baseFontSize = null;
                            string baseFontFace = null;
                            if (runNode != null)
                            {
                                text = ReadString(runNode, "text");
                                baseColor = ParseColor(ReadString(runNode, "color"));
                                baseBold = ReadBool(runNode, "bold", false);
                                baseItalic = ReadBool(runNode, "italic", false);
                                baseUnderline = ReadBool(runNode, "underline", false);
                                baseFontSize = ParseFontSizeToken(runNode["fontSize"]);
                                baseFontFace = NormalizeFontFace(ReadString(runNode, "fontFace"));
                            }
                            else if (runToken.Type == JTokenType.String)
                            {
                                text = runToken.Value<string>();
                            }
                            else continue;
                            // 纯文本契约：text 逐字保留（'\n' 是显式硬换行，布局层切分）。
                            // 不做任何内联标记展开 / 实体解码。
                            if (text != null)
                                section.Runs.Add(new NativeTooltipRun(
                                    text, baseColor, baseBold, baseItalic,
                                    baseUnderline, baseFontSize, baseFontFace));
                        }
                    }
                    // 空 run 段也保留：显式空段可占位（例如预留 meta 行）。
                    Sections.Add(section);
                }
            }

            if (!HasContent) { error = "document has no renderable content"; return false; }
            return true;
        }

        // ── JSON 读取助手（容错，不抛） ──

        internal static string ReadString(JObject node, string name)
        {
            JToken t = node[name];
            if (t == null || t.Type == JTokenType.Null) return null;
            if (t.Type == JTokenType.String) return t.Value<string>();
            try { return t.ToString(); } catch { return null; }
        }

        internal static int ReadInt(JObject node, string name, int fallback)
        {
            JToken t = node[name];
            if (t == null || t.Type == JTokenType.Null) return fallback;
            try
            {
                if (t.Type == JTokenType.Integer) return t.Value<int>();
                if (t.Type == JTokenType.Float) return (int)t.Value<double>();
                int v;
                if (int.TryParse(t.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out v)) return v;
            }
            catch { }
            return fallback;
        }

        internal static long ReadLong(JObject node, string name, long fallback)
        {
            JToken t = node[name];
            if (t == null || t.Type == JTokenType.Null) return fallback;
            try
            {
                if (t.Type == JTokenType.Integer) return t.Value<long>();
                if (t.Type == JTokenType.Float) return (long)t.Value<double>();
                long v;
                if (long.TryParse(t.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out v)) return v;
            }
            catch { }
            return fallback;
        }

        internal static double ReadDouble(JObject node, string name, double fallback)
        {
            JToken t = node[name];
            if (t == null || t.Type == JTokenType.Null) return fallback;
            try
            {
                if (t.Type == JTokenType.Float || t.Type == JTokenType.Integer) return t.Value<double>();
                double v;
                if (double.TryParse(t.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out v)) return v;
            }
            catch { }
            return fallback;
        }

        internal static bool ReadBool(JObject node, string name, bool fallback)
        {
            JToken t = node[name];
            if (t == null || t.Type == JTokenType.Null) return fallback;
            try
            {
                if (t.Type == JTokenType.Boolean) return t.Value<bool>();
                if (t.Type == JTokenType.Integer) return t.Value<long>() != 0;
                bool v;
                if (bool.TryParse(t.ToString(), out v)) return v;
            }
            catch { }
            return fallback;
        }

        /// <summary>
        /// 解析 "#RRGGBB" / "RRGGBB" / "0xRRGGBB"；3 位 "#RGB" 按 CSS 规则逐位
        /// 翻倍（对齐 Web legacy as2FontStyle 的 3/6 位 hex 白名单）。失败返回 null。
        /// </summary>
        internal static Color? ParseColor(string value)
        {
            if (string.IsNullOrEmpty(value)) return null;
            string s = value.Trim();
            if (s.StartsWith("#", StringComparison.Ordinal)) s = s.Substring(1);
            else if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) s = s.Substring(2);
            if (s.Length == 3)
            {
                s = new string(new[] { s[0], s[0], s[1], s[1], s[2], s[2] });
            }
            if (s.Length != 6) return null;
            int rgb;
            if (!int.TryParse(s, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out rgb)) return null;
            return Color.FromArgb(0xFF, (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
        }

        /// <summary>
        /// run.fontSize 容错读取：Integer 直接取；Float 向零截断（对齐 parseInt）；
        /// String 按 JS parseInt(_,10) 语义（前导空白、可选 +/-、前导数字）。
        /// 结果须在 1..96（Web legacy px>0 && px<=96），否则 null。
        /// </summary>
        internal static int? ParseFontSizeToken(JToken token)
        {
            if (token == null || token.Type == JTokenType.Null) return null;
            try
            {
                double v;
                if (token.Type == JTokenType.Integer) v = token.Value<long>();
                else if (token.Type == JTokenType.Float) v = Math.Truncate(token.Value<double>());
                else if (token.Type == JTokenType.String)
                    return ParseLegacyFontSize(token.Value<string>());
                else return null;
                if (v >= 1 && v <= 96) return (int)v;
            }
            catch { }
            return null;
        }

        /// <summary>JS parseInt(s,10) 语义 + 1..96 判定；无效返回 null。</summary>
        internal static int? ParseLegacyFontSize(string raw)
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
        /// run.fontFace 容错读取：受限字体名再过滤一次（防未走 sanitizer 的输入）——
        /// 仅保留 [0-9A-Za-z_]、CJK U+4E00..U+9FA5、空格、连字符（与 Web legacy
        /// face.replace(/[^\w一-龥 \-]/g,'') 同款），空白折叠为单空格、去首尾、
        /// ≤64 字符；全过滤为空 → null。产出是字体名，不是 CSS 片段。
        /// </summary>
        internal static string NormalizeFontFace(string value)
        {
            if (string.IsNullOrEmpty(value)) return null;
            StringBuilder sb = new StringBuilder(value.Length);
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
            if (face.Length > 64) face = face.Substring(0, 64);
            return face.Length > 0 ? face : null;
        }

        private static bool IsFontFaceChar(char c)
        {
            return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                || c == '_' || c == '-' || (c >= '一' && c <= '龥');
        }

        private static NativeTooltipSectionRole ParseRole(string role)
        {
            if (string.Equals(role, "intro", StringComparison.OrdinalIgnoreCase)) return NativeTooltipSectionRole.Intro;
            if (string.Equals(role, "description", StringComparison.OrdinalIgnoreCase)) return NativeTooltipSectionRole.Description;
            return NativeTooltipSectionRole.Body;
        }
    }

    /// <summary>
    /// 受限内联标记展开器。只识别旧注释已有标记（对齐迁移前 Web convertAS2Html）：
    ///   &lt;font color|size|face&gt;…&lt;/font&gt;（嵌套/跨 run，样式栈；
    ///   color 支持 #RGB 三位展开，size 按 JS parseInt 取 1..96，face 过滤受限字体名）
    ///   &lt;b&gt;/&lt;strong&gt;、&lt;i&gt;/&lt;em&gt;、&lt;u&gt; 配对开闭
    ///   &lt;br&gt; / &lt;br/&gt; → '\n'（不弹样式栈，样式跨行保留）
    ///   &lt;p…&gt; → 段落换行（仅当已产出内容，避免头部空行）；&lt;/p&gt; 剥离
    ///   实体 &amp;lt; &amp;gt; &amp;amp; &amp;quot; &amp;apos; &amp;nbsp; &amp;#NN;
    /// 其余 &lt;…&gt; 标签剥离；孤立 '&lt;' 无 '&gt;' 配对按字面文本保留。
    /// </summary>
    internal static class NativeTooltipMarkup
    {
        /// <summary>样式栈帧：记录开标签置位的属性；IsFont 标记 &lt;font&gt; 帧供 </font> 定向弹栈。</summary>
        internal sealed class StyleFrame
        {
            internal Color? Color;
            internal int? FontSize;
            internal string FontFace;
            internal bool IsFont;
            internal bool Bold;
            internal bool Italic;
            internal bool Underline;
        }

        /// <summary>跨 run 携带的展开状态（样式栈）。</summary>
        internal sealed class FlatState
        {
            internal readonly List<StyleFrame> StyleStack = new List<StyleFrame>();
            internal Color? BaseColor;
            internal bool BaseBold;
            internal bool BaseItalic;
            internal bool BaseUnderline;
            internal int? BaseFontSize;
            internal string BaseFontFace;
            internal bool ProducedAnyText;

            internal void Reset(NativeTooltipRun baseRun)
            {
                // 跨 run 边界重置基础样式：JSON run 属性是新的底层样式；
                // 未闭合的标记作用域不穿透 JSON run 边界（run 是自包含样式单元）。
                StyleStack.Clear();
                BaseColor = baseRun != null ? baseRun.Color : null;
                BaseBold = baseRun != null && baseRun.Bold;
                BaseItalic = baseRun != null && baseRun.Italic;
                BaseUnderline = baseRun != null && baseRun.Underline;
                BaseFontSize = baseRun != null ? baseRun.FontSize : null;
                BaseFontFace = baseRun != null ? baseRun.FontFace : null;
            }

            internal Color? CurrentColor
            {
                get
                {
                    for (int i = StyleStack.Count - 1; i >= 0; i--)
                        if (StyleStack[i].Color.HasValue) return StyleStack[i].Color;
                    return BaseColor;
                }
            }

            internal int? CurrentFontSize
            {
                get
                {
                    for (int i = StyleStack.Count - 1; i >= 0; i--)
                        if (StyleStack[i].FontSize.HasValue) return StyleStack[i].FontSize;
                    return BaseFontSize;
                }
            }

            internal string CurrentFontFace
            {
                get
                {
                    for (int i = StyleStack.Count - 1; i >= 0; i--)
                        if (StyleStack[i].FontFace != null) return StyleStack[i].FontFace;
                    return BaseFontFace;
                }
            }

            internal bool CurrentBold { get { return CurrentFlag(f => f.Bold, BaseBold); } }
            internal bool CurrentItalic { get { return CurrentFlag(f => f.Italic, BaseItalic); } }
            internal bool CurrentUnderline { get { return CurrentFlag(f => f.Underline, BaseUnderline); } }

            private bool CurrentFlag(Func<StyleFrame, bool> flag, bool baseValue)
            {
                for (int i = StyleStack.Count - 1; i >= 0; i--)
                    if (flag(StyleStack[i])) return true;
                return baseValue;
            }
        }

        internal static List<NativeTooltipRun> Flatten(string text, Color? baseColor, bool baseBold)
        {
            List<NativeTooltipRun> output = new List<NativeTooltipRun>();
            FlatState state = new FlatState();
            state.Reset(new NativeTooltipRun(null, baseColor, baseBold));
            FlattenInto(text, output, state);
            return output;
        }

        /// <summary>
        /// 把一段 text 展开成 styled run 追加到 output。'\n' 保留在 run.Text 内。
        /// state.ProducedAnyText 追踪是否已产出文本，用于 &lt;p&gt; 的首段抑制。
        /// </summary>
        internal static void FlattenInto(string text,
            List<NativeTooltipRun> output, FlatState state)
        {
            if (string.IsNullOrEmpty(text)) return;
            int pos = 0;
            StringBuilder pending = new StringBuilder();

            Action flush = delegate
            {
                if (pending.Length == 0) return;
                output.Add(new NativeTooltipRun(
                    pending.ToString(), state.CurrentColor, state.CurrentBold,
                    state.CurrentItalic, state.CurrentUnderline,
                    state.CurrentFontSize, state.CurrentFontFace));
                pending.Length = 0;
                state.ProducedAnyText = true;
            };

            while (pos < text.Length)
            {
                char c = text[pos];
                if (c == '<')
                {
                    int gt = text.IndexOf('>', pos + 1);
                    if (gt < 0)
                    {
                        // 孤立 '<'：字面保留
                        pending.Append(c);
                        pos++;
                        continue;
                    }
                    string tagBody = text.Substring(pos + 1, gt - pos - 1);
                    TagKind kind = ClassifyTag(tagBody);
                    if (kind == TagKind.LineBreak)
                    {
                        flush();
                        // <br> 产无样式换行 run，不弹样式栈——样式跨行保留（对齐 Web DOM）
                        output.Add(new NativeTooltipRun("\n", null, false));
                        state.ProducedAnyText = true;
                    }
                    else if (kind == TagKind.Paragraph)
                    {
                        flush();
                        if (state.ProducedAnyText)
                            output.Add(new NativeTooltipRun("\n", null, false));
                    }
                    else if (kind == TagKind.FontOpen)
                    {
                        flush();
                        state.StyleStack.Add(new StyleFrame
                        {
                            Color = ParseFontColor(tagBody),
                            FontSize = NativeTooltipDocument.ParseLegacyFontSize(
                                ReadFontAttr(tagBody, "size")),
                            FontFace = NativeTooltipDocument.NormalizeFontFace(
                                ReadFontAttr(tagBody, "face")),
                            IsFont = true
                        });
                    }
                    else if (kind == TagKind.FontClose || kind == TagKind.BoldClose
                        || kind == TagKind.ItalicClose || kind == TagKind.UnderlineClose)
                    {
                        flush();
                        PopStyle(state.StyleStack, kind);
                    }
                    else if (kind == TagKind.BoldOpen)
                    {
                        flush();
                        state.StyleStack.Add(new StyleFrame { Bold = true });
                    }
                    else if (kind == TagKind.ItalicOpen)
                    {
                        flush();
                        state.StyleStack.Add(new StyleFrame { Italic = true });
                    }
                    else if (kind == TagKind.UnderlineOpen)
                    {
                        flush();
                        state.StyleStack.Add(new StyleFrame { Underline = true });
                    }
                    // TagKind.Strip：静默剥离
                    pos = gt + 1;
                    continue;
                }
                if (c == '&')
                {
                    int semi = text.IndexOf(';', pos + 1);
                    if (semi > pos && semi - pos <= 10)
                    {
                        string entity = text.Substring(pos + 1, semi - pos - 1);
                        string decoded;
                        if (TryDecodeEntity(entity, out decoded))
                        {
                            pending.Append(decoded);
                            pos = semi + 1;
                            continue;
                        }
                    }
                    pending.Append(c);
                    pos++;
                    continue;
                }
                pending.Append(c);
                pos++;
            }
            flush();
        }

        private enum TagKind
        {
            Strip, LineBreak, Paragraph, FontOpen, FontClose,
            BoldOpen, BoldClose, ItalicOpen, ItalicClose, UnderlineOpen, UnderlineClose
        }

        private static TagKind ClassifyTag(string tagBody)
        {
            if (tagBody == null) return TagKind.Strip;
            string t = tagBody.Trim();
            if (t.Length == 0) return TagKind.Strip;
            bool closing = t[0] == '/';
            string name = closing ? t.Substring(1) : t;
            // 取标签名首词
            int space = name.IndexOf(' ');
            int slash = name.IndexOf('/');
            int end = name.Length;
            if (space >= 0 && space < end) end = space;
            if (slash >= 0 && slash < end) end = slash;
            name = name.Substring(0, end);

            if (name.Equals("br", StringComparison.OrdinalIgnoreCase)) return TagKind.LineBreak;
            if (name.Equals("p", StringComparison.OrdinalIgnoreCase)) return closing ? TagKind.Strip : TagKind.Paragraph;
            if (name.Equals("font", StringComparison.OrdinalIgnoreCase)) return closing ? TagKind.FontClose : TagKind.FontOpen;
            if (name.Equals("b", StringComparison.OrdinalIgnoreCase) || name.Equals("strong", StringComparison.OrdinalIgnoreCase))
                return closing ? TagKind.BoldClose : TagKind.BoldOpen;
            if (name.Equals("i", StringComparison.OrdinalIgnoreCase) || name.Equals("em", StringComparison.OrdinalIgnoreCase))
                return closing ? TagKind.ItalicClose : TagKind.ItalicOpen;
            if (name.Equals("u", StringComparison.OrdinalIgnoreCase)) return closing ? TagKind.UnderlineClose : TagKind.UnderlineOpen;
            return TagKind.Strip;
        }

        /// <summary>
        /// 按标签类别弹栈：</font> 弹到最近 IsFont 帧（含其上所有帧）；
        /// </b>|</i>|</u>（含 strong/em 闭）弹到最近置位对应标记的帧。
        /// font 无匹配帧时仍弹栈顶一帧（沿用旧容错）；其余标记无匹配容错忽略。
        /// </summary>
        private static void PopStyle(List<StyleFrame> stack, TagKind close)
        {
            Func<StyleFrame, bool> match;
            switch (close)
            {
                case TagKind.FontClose: match = f => f.IsFont; break;
                case TagKind.BoldClose: match = f => f.Bold; break;
                case TagKind.ItalicClose: match = f => f.Italic; break;
                default: match = f => f.Underline; break;
            }
            for (int i = stack.Count - 1; i >= 0; i--)
            {
                if (match(stack[i]))
                {
                    stack.RemoveRange(i, stack.Count - i);
                    return;
                }
            }
            // font 无匹配帧时仍弹最后一帧；多余 </b>|</i>|</u> 容错忽略，不清空既有样式。
            if (close == TagKind.FontClose && stack.Count > 0) stack.RemoveAt(stack.Count - 1);
        }

        /// <summary>
        /// <font> 属性值抽取（对齐 AS2 readFontAttr）：name 前必须是串首/空白/'/'，
        /// name 后必须是空白或 '='（防 "color" 命中 "mycolor" 等粘连）；'=' 与值之间
        /// 只允许空白；值取引号内或首个非空白 token。无效/缺失返回 null。
        /// </summary>
        private static string ReadFontAttr(string tagBody, string name)
        {
            if (tagBody == null) return null;
            int from = 0;
            while (true)
            {
                int idx = tagBody.IndexOf(name, from, StringComparison.OrdinalIgnoreCase);
                if (idx < 0) return null;
                if (idx > 0 && !IsAttrBoundary(tagBody[idx - 1]))
                {
                    from = idx + 1;
                    continue;
                }
                int after = idx + name.Length;
                if (after < tagBody.Length
                    && !(char.IsWhiteSpace(tagBody[after]) || tagBody[after] == '='))
                {
                    from = idx + 1;
                    continue;
                }
                int eq = tagBody.IndexOf('=', after);
                if (eq < 0) return null;
                bool clean = true;
                for (int m = after; m < eq; m++)
                {
                    if (!char.IsWhiteSpace(tagBody[m])) { clean = false; break; }
                }
                if (!clean) { from = after; continue; } // '=' 属于别的属性，继续找下一处 name
                int vstart = eq + 1;
                while (vstart < tagBody.Length && char.IsWhiteSpace(tagBody[vstart])) vstart++;
                if (vstart >= tagBody.Length) return null;
                char quote = tagBody[vstart];
                if (quote == '\'' || quote == '"')
                {
                    int qend = tagBody.IndexOf(quote, vstart + 1);
                    if (qend < 0) return null;
                    return tagBody.Substring(vstart + 1, qend - vstart - 1);
                }
                int vend = vstart;
                while (vend < tagBody.Length && !char.IsWhiteSpace(tagBody[vend])) vend++;
                return tagBody.Substring(vstart, vend - vstart);
            }
        }

        private static bool IsAttrBoundary(char c)
        {
            return char.IsWhiteSpace(c) || c == '/';
        }

        private static Color? ParseFontColor(string tagBody)
        {
            // 形态：<font color='#RRGGBB'> / color="#RRGGBB" / color=#RRGGBB
            return NativeTooltipDocument.ParseColor(ReadFontAttr(tagBody, "color"));
        }

        private static bool TryDecodeEntity(string entity, out string decoded)
        {
            decoded = null;
            if (string.IsNullOrEmpty(entity)) return false;
            switch (entity)
            {
                case "lt": decoded = "<"; return true;
                case "gt": decoded = ">"; return true;
                case "amp": decoded = "&"; return true;
                case "quot": decoded = "\""; return true;
                case "apos": decoded = "'"; return true;
                case "nbsp": decoded = " "; return true;
            }
            if (entity[0] == '#')
            {
                int code;
                bool hex = entity.Length > 1 && (entity[1] == 'x' || entity[1] == 'X');
                string digits = hex ? entity.Substring(2) : entity.Substring(1);
                if (int.TryParse(digits,
                        hex ? NumberStyles.HexNumber : NumberStyles.Integer,
                        CultureInfo.InvariantCulture, out code)
                    && code >= 0 && code <= 0x10FFFF)
                {
                    try { decoded = char.ConvertFromUtf32(code); return true; }
                    catch { return false; }
                }
            }
            return false;
        }
    }
}
