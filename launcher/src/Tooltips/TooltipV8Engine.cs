using System;
using System.IO;
using System.Security.Cryptography;
using Microsoft.ClearScript.V8;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tooltips
{
    /// <summary>
    /// One non-realtime ClearScript instance for trusted Tooltip TS. Construct, invoke and dispose
    /// exclusively on TooltipService's worker. No host objects, I/O bridge, GameInput locks or globals.
    /// </summary>
    internal sealed class TooltipV8Engine : ITooltipContentEngine
    {
        private readonly V8ScriptEngine _engine;
        public string Identity { get; }

        internal TooltipV8Engine(string projectRoot)
        {
            string root = Path.GetFullPath(projectRoot);
            string bundlePath = Path.Combine(root, "launcher", "scripts", "dist", "tooltip-bundle.js");
            string catalogPath = Path.Combine(root, "data", "tooltip", "tooltip-catalog.json");
            string manifestPath = Path.Combine(root, "data", "tooltip", "tooltip-catalog.manifest.json");
            string bundle = ReadBounded(bundlePath, 16 * 1024 * 1024);
            string catalog = ReadBounded(catalogPath, 64 * 1024 * 1024);
            var manifest = JObject.Parse(ReadBounded(manifestPath, 1024 * 1024));
            ValidateCatalogFiles(root, catalogPath, catalog, manifest);
            Identity = "tooltip-v1:" + HashFile(bundlePath) + ":" + HashFile(catalogPath);
            _engine = new V8ScriptEngine(V8ScriptEngineFlags.DisableGlobalMembers);
            try
            {
                _engine.Execute("tooltip-bundle.js", bundle);
                _engine.Script.TooltipEngine.initCatalog(catalog);
            }
            catch { _engine.Dispose(); throw; }
        }

        public string BuildProjection(string inputJson)
        {
            object result = _engine.Script.TooltipEngine.buildProjectionJson(inputJson);
            return result as string ?? throw new InvalidOperationException("tooltip_v8_result_type");
        }

        private static string ReadBounded(string path, long maxBytes)
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.Length == 0 || info.Length > maxBytes)
                throw new InvalidDataException("tooltip_resource_size: " + path);
            return File.ReadAllText(path);
        }

        private static void ValidateCatalogFiles(string root, string catalogPath, string json, JObject manifest)
        {
            var catalog = JObject.Parse(json);
            if (catalog["version"]?.Type != JTokenType.Integer || catalog.Value<int>("version") != 1
                || catalog["contentVersion"]?.Type != JTokenType.String
                || manifest["version"]?.Type != JTokenType.Integer || manifest.Value<int>("version") != 1
                || !string.Equals(manifest.Value<string>("contentVersion"), catalog.Value<string>("contentVersion"), StringComparison.Ordinal)
                || !string.Equals(manifest.Value<string>("output"), "data/tooltip/tooltip-catalog.json", StringComparison.Ordinal)
                || manifest["sourceFiles"] is not JObject sources || sources.Count == 0)
                throw new InvalidDataException("tooltip_catalog_schema");
            if (!HashMatches(manifest.Value<string>("outputSha256"), HashFile(catalogPath)))
                throw new InvalidDataException("tooltip_catalog_hash");
            string prefix = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            foreach (var source in sources.Properties())
            {
                string relative = source.Name.Replace('/', Path.DirectorySeparatorChar);
                string path = Path.GetFullPath(Path.Combine(root, relative));
                if (Path.IsPathRooted(relative) || !path.StartsWith(prefix, StringComparison.Ordinal)
                    || source.Value.Type != JTokenType.String)
                    throw new InvalidDataException("tooltip_catalog_source_path");
                // Runtime depends on authoritative data, not the presence of development generators.
                // Full generator/source equality remains the catalog generator's --check gate.
                if (!source.Name.StartsWith("data/", StringComparison.Ordinal)) continue;
                if (!File.Exists(path) || !HashMatches(source.Value.Value<string>(), HashFile(path)))
                    throw new InvalidDataException("tooltip_catalog_stale: " + source.Name);
            }
        }

        private static bool HashMatches(string expected, string actual)
        {
            if (expected != null && expected.StartsWith("sha256:", StringComparison.Ordinal)) expected = expected.Substring(7);
            return string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase);
        }

        private static string HashFile(string path)
        {
            using var stream = File.OpenRead(path);
            return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        }

        public void Dispose() => _engine.Dispose();
    }
}
