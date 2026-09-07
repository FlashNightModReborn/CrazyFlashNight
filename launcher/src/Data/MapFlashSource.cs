using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Xml.Linq;

namespace CF7Launcher.Data
{
    /// <summary>按 Include 读取 XFL 或 FLA 内的 XML；不解压、不写索引，不执行脚本。</summary>
    public sealed class MapFlashSource : IDisposable
    {
        public sealed class Symbol
        {
            public string Name, Entry, Digest;
            public XDocument Document;
        }
        private readonly string folder;
        private readonly ZipArchive archive;
        public readonly Dictionary<string, Symbol> Symbols = new Dictionary<string, Symbol>(StringComparer.Ordinal);
        public readonly XDocument Document;
        public readonly string SourcePath, DocumentDigest;

        public MapFlashSource(string root, string swf)
        {
            try
            {
            string stem = swf.Substring(0, swf.Length - 4);
            string directory = MapProjectFiles.Resolve(root, stem);
            byte[] main;
            if (File.Exists(Path.Combine(directory, "DOMDocument.xml")))
            {
                folder = directory; SourcePath = stem + "/DOMDocument.xml";
                main = ReadEntry("DOMDocument.xml");
            }
            else
            {
                SourcePath = stem + ".fla";
                string file = MapProjectFiles.Resolve(root, SourcePath);
                archive = ZipFile.OpenRead(file);
                MapRuleEvaluator.Need(archive.Entries.Count <= 100000, "FLA 内部目录过大。");
                main = ReadEntry("DOMDocument.xml");
            }
            DocumentDigest = MapDefinition.Hash(main); Document = MapProjectFiles.Xml(main);
            var includes = Document.Descendants().Where(e => e.Name.LocalName == "Include").Select(e => (string)e.Attribute("href")).ToArray();
            MapRuleEvaluator.Need(includes.Length <= 16384 && includes.Distinct(StringComparer.Ordinal).Count() == includes.Length, "XFL Include 重复或过多。");
            foreach (string include in includes)
            {
                string entry = include.StartsWith("LIBRARY/", StringComparison.Ordinal) ? include : "LIBRARY/" + include;
                byte[] bytes = ReadEntry(entry); var document = MapProjectFiles.Xml(bytes);
                string name = (string)document.Root.Attribute("name");
                MapRuleEvaluator.Need(!string.IsNullOrEmpty(name) && !Symbols.ContainsKey(name), "XFL 库元件名重复或缺失。");
                Symbols[name] = new Symbol { Name = name, Entry = entry, Document = document, Digest = MapDefinition.Hash(bytes) };
            }
            }
            catch { archive?.Dispose(); throw; }
        }
        private byte[] ReadEntry(string name)
        {
            MapRuleEvaluator.Need(name != null && !name.Contains('\\') && !name.Contains(':') && name.Split('/').All(p => p != "" && p != "." && p != ".."), "XFL Include 路径非法。");
            const int limit = 16 * 1024 * 1024;
            if (folder != null) return MapProjectFiles.Read(folder, name, limit);
            var entries = archive.Entries.Where(e => string.Equals(e.FullName.Replace('\\', '/'), name, StringComparison.Ordinal)).ToArray();
            MapRuleEvaluator.Need(entries.Length == 1 && entries[0].Length <= limit, "FLA XML 缺失、重复或过大：" + name);
            using var stream = entries[0].Open(); var bytes = new byte[(int)entries[0].Length]; stream.ReadExactly(bytes);
            MapRuleEvaluator.Need(stream.ReadByte() == -1, "FLA XML 解压长度异常。"); return bytes;
        }
        public Symbol Export(string linkage)
        {
            var found = Symbols.Values.Where(s => (string)s.Document.Root.Attribute("linkageIdentifier") == linkage &&
                (string)s.Document.Root.Attribute("linkageExportForAS") == "true").ToArray();
            MapRuleEvaluator.Need(found.Length == 1, "来源未唯一声明已 Include 的导出链接：" + linkage); return found[0];
        }
        public IEnumerable<Symbol> Reachable(XDocument document)
        {
            var visited = new HashSet<string>(StringComparer.Ordinal); var pending = new Queue<XDocument>(); pending.Enqueue(document);
            while (pending.Count > 0)
            {
                var current = pending.Dequeue();
                foreach (var instance in current.Descendants().Where(e => e.Name.LocalName == "DOMSymbolInstance"))
                {
                    string name = (string)instance.Attribute("libraryItemName");
                    if (name == null || !visited.Add(name) || !Symbols.TryGetValue(name, out Symbol symbol)) continue;
                    yield return symbol;
                    if ((string)symbol.Document.Root.Attribute("linkageImportForRS") != "true") pending.Enqueue(symbol.Document);
                }
            }
        }
        public void Dispose() => archive?.Dispose();
    }
}
