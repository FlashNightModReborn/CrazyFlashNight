using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Xml.Linq;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // LUT 实验室 baker：data/environment/color_engine_preset.xml → 8 参数快照
    // → WorldColorMatrix.Generate 组矩阵 → 32^3 节点逐点求值输出 RGBA8（32768*4，R 最快）。
    // 插值规则严格复刻 AS2 WorldLightingBridge.parameters：light===7 短路恒等；
    // floor/ceil 线性插值；light>9 用 8/9 档外推；任何 NaN/非有限值整体拒绝。
    // 逐点求值语义对齐原生 shader（Compositor.cpp PS）：graded=saturate(matrix*c+offset/255)、
    // c.a 恒 1、out=pow(graded, 1/max(gamma,1e-3))，与 ShaderSettings 的 offset/gamma 排布一致。
    internal static class WorldLutBaker
    {
        internal const int LutSize = 32;
        internal const int RgbaBytes = LutSize * LutSize * LutSize * 4;

        // 8 参数顺序 = AS2 parameters 的 keys：红/绿/蓝/透明乘数、亮度、对比度、饱和度、色相。
        // XML 缺省值复刻 AS2 加载并配置色彩预设：乘数=1，其余=0；非数值文本存 NaN
        // （对应 AS2 Number() 语义），由 Interpolate 统一拒绝。
        internal static Dictionary<string, Dictionary<int, double[]>> LoadPresetTables(string xmlPath)
        {
            var doc = XDocument.Load(xmlPath);
            var result = new Dictionary<string, Dictionary<int, double[]>>(StringComparer.Ordinal);
            if (doc.Root == null) return result;
            foreach (var set in doc.Root.Elements("PresetSet"))
            {
                var nameElement = set.Element("name");
                if (nameElement == null) continue;
                var table = new Dictionary<int, double[]>();
                foreach (var preset in set.Elements("Preset"))
                {
                    double levelValue = Field(preset, "level", double.NaN);
                    if (!double.IsFinite(levelValue)) continue;
                    table[(int)levelValue] = new double[]
                    {
                        Field(preset, "redMultiplier", 1), Field(preset, "greenMultiplier", 1),
                        Field(preset, "blueMultiplier", 1), Field(preset, "alphaMultiplier", 1),
                        Field(preset, "Brightness", 0), Field(preset, "Contrast", 0),
                        Field(preset, "Saturation", 0), Field(preset, "Hue", 0)
                    };
                }
                result[nameElement.Value.Trim()] = table;
            }
            return result;
        }

        private static double Field(XElement preset, string name, double fallback)
        {
            var element = preset.Element(name);
            if (element == null) return fallback;
            double value;
            return double.TryParse(element.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out value)
                ? value : double.NaN;
        }

        // 契约 mode 别名："夜视" → XML PresetSet "夜视仪"；其余按 PresetSet name 精确命中。
        internal static string ResolvePresetSetName(Dictionary<string, Dictionary<int, double[]>> tables, string mode)
        {
            if (tables == null || string.IsNullOrEmpty(mode)) return null;
            if (mode == "夜视") mode = "夜视仪";
            return tables.ContainsKey(mode) ? mode : null;
        }

        internal static double[] Interpolate(Dictionary<int, double[]> table, double light)
        {
            if (!double.IsFinite(light)) return null;
            if (light == 7) return new double[] { 1, 1, 1, 1, 0, 0, 0, 0 };
            int first = light > 9 ? 8 : (int)Math.Floor(light);
            int last = light > 9 ? 9 : (int)Math.Ceiling(light);
            double[] a, b;
            if (table == null || !table.TryGetValue(first, out a) || !table.TryGetValue(last, out b)) return null;
            double ratio = first == last ? 0 : (light - first) / (last - first);
            var result = new double[8];
            for (int i = 0; i < 8; i++)
            {
                double value = a[i] * (1 - ratio) + b[i] * ratio;
                if (!double.IsFinite(value)) return null;
                result[i] = value;
            }
            return result;
        }

        internal static byte[] Bake(double[] parameters, double gamma)
        {
            double[] m = WorldColorMatrix.Generate(parameters);
            double inverseGamma = 1.0 / Math.Max(gamma, 1e-3);
            var rgba = new byte[RgbaBytes];
            int offset = 0;
            for (int b = 0; b < LutSize; b++)
            {
                double cb = b / (double)(LutSize - 1);
                for (int g = 0; g < LutSize; g++)
                {
                    double cg = g / (double)(LutSize - 1);
                    for (int r = 0; r < LutSize; r++)
                    {
                        double cr = r / (double)(LutSize - 1);
                        rgba[offset++] = Quantize(Math.Pow(Saturate(
                            m[0] * cr + m[1] * cg + m[2] * cb + m[3] + m[4] / 255.0), inverseGamma));
                        rgba[offset++] = Quantize(Math.Pow(Saturate(
                            m[5] * cr + m[6] * cg + m[7] * cb + m[8] + m[9] / 255.0), inverseGamma));
                        rgba[offset++] = Quantize(Math.Pow(Saturate(
                            m[10] * cr + m[11] * cg + m[12] * cb + m[13] + m[14] / 255.0), inverseGamma));
                        rgba[offset++] = 255;
                    }
                }
            }
            return rgba;
        }

        internal static byte[] BakeFromXml(string xmlPath, string mode, double level, double gamma, out string resolvedMode)
        {
            var tables = LoadPresetTables(xmlPath);
            resolvedMode = ResolvePresetSetName(tables, mode);
            if (resolvedMode == null) return null;
            double[] parameters = Interpolate(tables[resolvedMode], level);
            return parameters == null ? null : Bake(parameters, gamma);
        }

        private static double Saturate(double value) { return value < 0 ? 0 : value > 1 ? 1 : value; }
        private static byte Quantize(double value)
        {
            int quantized = (int)Math.Floor(value * 255.0 + 0.5);
            return (byte)(quantized < 0 ? 0 : quantized > 255 ? 255 : quantized);
        }

        // .CUBE 写出：RGB 浮点三元组（无 alpha），节点序与 Bake 一致（R 最快）。
        internal static void WriteCube(string path, string title, byte[] rgba)
        {
            if (rgba == null || rgba.Length != RgbaBytes) throw new ArgumentException("32^3 RGBA buffer required");
            var builder = new StringBuilder(RgbaBytes / 2);
            builder.Append("TITLE \"").Append(title).Append("\"\n");
            builder.Append("LUT_3D_SIZE ").Append(LutSize).Append('\n');
            builder.Append("DOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n");
            for (int node = 0; node < LutSize * LutSize * LutSize; node++)
            {
                int o = node * 4;
                builder.Append(Channel(rgba[o])).Append(' ')
                       .Append(Channel(rgba[o + 1])).Append(' ')
                       .Append(Channel(rgba[o + 2])).Append('\n');
            }
            File.WriteAllText(path, builder.ToString(), new UTF8Encoding(false));
        }

        private static string Channel(byte value) => (value / 255.0).ToString("0.######", CultureInfo.InvariantCulture);
    }
}
