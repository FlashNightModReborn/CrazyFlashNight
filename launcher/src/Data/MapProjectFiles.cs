using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    internal static class MapProjectFiles
    {
        public static void PlainPath(string path)
        {
            for (string p = Path.GetFullPath(path); p != null; p = Path.GetDirectoryName(p))
                if ((Directory.Exists(p) || File.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("地图内容路径不能经过链接或重解析目录。");
        }
        public static string Resolve(string root, string relative)
        {
            MapRuleEvaluator.Need(relative != null && relative.Length < 240 && !relative.Contains('\\') && !relative.Contains(':') && !relative.StartsWith('/') &&
                !relative.Any(char.IsControl) && relative.Split('/').All(part => part.Length > 0 && part != "." && part != ".."), "地图内容相对路径不合法。");
            string fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
            string full = Path.GetFullPath(Path.Combine(fullRoot, relative.Replace('/', Path.DirectorySeparatorChar)));
            MapRuleEvaluator.Need(full.StartsWith(fullRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase), "地图内容路径越界。");
            PlainPath(full); return full;
        }
        public static byte[] Read(string root, string relative, int limit = 4 * 1024 * 1024)
        {
            using var stream = new FileStream(Resolve(root, relative), FileMode.Open, FileAccess.Read, FileShare.Read);
            MapRuleEvaluator.Need(stream.Length >= 0 && stream.Length <= limit, "地图内容文件过大：" + relative);
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes); return bytes;
        }
        public static JObject Json(byte[] bytes)
        {
            using var reader = new JsonTextReader(new StringReader(new UTF8Encoding(false, true).GetString(bytes).TrimStart((char)0xFEFF))) { MaxDepth = 48, DateParseHandling = DateParseHandling.None };
            var value = JObject.Load(reader, new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error });
            if (reader.Read()) throw new InvalidDataException("内容 JSON 含多余字节。");
            return value;
        }
        public static XDocument Xml(byte[] bytes, long limit = 16 * 1024 * 1024)
        {
            using var stream = new MemoryStream(bytes, false);
            using var reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = limit });
            return XDocument.Load(reader, LoadOptions.PreserveWhitespace);
        }
        public static void Atomic(string target, byte[] bytes)
        {
            PlainPath(target); Directory.CreateDirectory(Path.GetDirectoryName(target));
            string temp = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes); stream.Flush(true); }
                if (File.Exists(target)) File.Replace(temp, target, null); else File.Move(temp, target);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
}
