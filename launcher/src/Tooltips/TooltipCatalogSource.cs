using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Microsoft.ClearScript.V8;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tooltips
{
    internal sealed record TooltipSnapshot(string Catalog, string Digest, string Archive);

    /// <summary>The tooltip worker and the launcher's equipment preview consume one immutable snapshot per launch.</summary>
    internal sealed class TooltipCatalogSource
    {
        private readonly string _root;
        private static readonly UTF8Encoding SourceEncoding = new(false, true);
        private readonly Lazy<TooltipSnapshot> _snapshot;
        private readonly Action<string> _log;
        internal bool IsCheckout { get; }
        internal TooltipSnapshot Snapshot => _snapshot.Value;

        internal TooltipCatalogSource(string root, Action<string> log = null)
        {
            _root = Path.GetFullPath(root);
            _log = log;
            string marker = Path.Combine(_root, ".git");
            // Source trees (Git checkouts, worktrees, or source archives) carry authoring tools;
            // prepared packages from cf7-packer contain only runtime layers.
            IsCheckout = Directory.Exists(marker) || File.Exists(marker)
                || File.Exists(Path.Combine(_root, "tools", "tooltip-catalog.cjs"));
            _snapshot = new Lazy<TooltipSnapshot>(() => IsCheckout ? CompileCheckout() : ReadPackage());
        }

        internal static string ReadText(string path, int limit)
        {
            using var stream = File.OpenRead(path);
            long length = stream.Length;
            if (length <= 0 || length > limit) throw new InvalidDataException("tooltip_resource_size: " + path);
            var bytes = new byte[(int)length];
            stream.ReadExactly(bytes);
            var text = SourceEncoding.GetString(bytes);
            return text.StartsWith('\uFEFF') ? text.Substring(1) : text;
        }

        internal static string Hash(string text) =>
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();

        private TooltipSnapshot CompileCheckout()
        {
            using var engine = new V8ScriptEngine(V8ScriptEngineFlags.DisableGlobalMembers);
            engine.Execute("tooltip-catalog-compiler.js", ReadText(Path.Combine(_root,
                "launcher", "scripts", "dist", "tooltip-catalog-compiler.js"), 4 * 1024 * 1024));
            var compiler = engine.Script.TooltipCatalog;
            var sources = new Dictionary<string, string>(StringComparer.Ordinal);
            long chars = 0;
            void ReadSources(string pathsJson)
            {
                var paths = JsonConvert.DeserializeObject<string[]>(pathsJson);
                foreach (string relative in paths)
                {
                    if (sources.ContainsKey(relative)) continue;
                    if (!relative.StartsWith("data/", StringComparison.Ordinal) || relative.Contains('\\') ||
                        relative.Contains(':') || Array.Exists(relative.Split('/'), part => part.Length == 0 || part == "." || part == ".."))
                        throw new InvalidDataException("tooltip_catalog_source_path: " + relative);
                    string text;
                    try { text = ReadText(Path.Combine(_root, relative), 16 * 1024 * 1024); }
                    catch (Exception ex) when (relative.StartsWith("data/crafting/", StringComparison.Ordinal) &&
                        ex is IOException or UnauthorizedAccessException or DecoderFallbackException or InvalidDataException)
                    {
                        _log?.Invoke("[TooltipService] " + relative + ": " + ex.Message);
                        text = "";
                    }
                    chars += text.Length;
                    if (chars > 128 * 1024 * 1024 || sources.Count >= 4096) throw new InvalidDataException("tooltip_catalog_source_size");
                    sources.Add(relative, text);
                }
            }
            ReadSources((string)compiler.listJson);
            ReadSources((string)compiler.pathsJson(JsonConvert.SerializeObject(sources)));
            var projection = compiler.checkout(JsonConvert.SerializeObject(sources));
            string diagnostic = (string)projection.diagnostic;
            if (diagnostic.Length > 0) _log?.Invoke("[TooltipService] recipe data unavailable: " + diagnostic);
            string payload = (string)projection.payload;
            string digest = Hash(payload);
            string catalog = (string)compiler.serialize(payload, digest);
            return new TooltipSnapshot(catalog, Hash(catalog), (string)compiler.archiveJson(payload));
        }

        private TooltipSnapshot ReadPackage()
        {
            string dir = Path.Combine(_root, "data", "tooltip");
            string catalog = ReadText(Path.Combine(dir, "tooltip-catalog.json"), 64 * 1024 * 1024);
            var receipt = JObject.Parse(ReadText(Path.Combine(dir, "tooltip-catalog.manifest.json"), 1024 * 1024));
            var version = JObject.Parse(catalog).Value<string>("contentVersion");
            if (string.IsNullOrEmpty(version) || receipt["contentVersion"]?.Type != JTokenType.String ||
                receipt.Value<string>("contentVersion") != version || receipt["version"]?.Type != JTokenType.Integer
                || receipt.Value<string>("output") != "data/tooltip/tooltip-catalog.json"
                || receipt.Value<int>("version") is not (1 or 2))
                throw new InvalidDataException("tooltip_catalog_schema");
            string expected = receipt.Value<string>("outputSha256");
            if (expected?.StartsWith("sha256:", StringComparison.Ordinal) == true) expected = expected.Substring(7);
            string digest = Hash(catalog);
            if (!string.Equals(expected, digest, StringComparison.OrdinalIgnoreCase) && catalog.Contains("\r\n"))
                digest = Hash(catalog.Replace("\r\n", "\n"));
            if (!string.Equals(expected, digest, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("tooltip_catalog_hash");
            return new TooltipSnapshot(catalog, digest, null);
        }
    }
}
