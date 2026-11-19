using System;
using System.IO;
using Microsoft.ClearScript.V8;

namespace CF7Launcher.Tooltips
{
    /// <summary>The content worker receives a complete snapshot and has no host objects or filesystem bridge.</summary>
    internal sealed class TooltipV8Engine : ITooltipContentEngine
    {
        private readonly V8ScriptEngine _engine;
        public string Identity { get; }

        internal TooltipV8Engine(string projectRoot) : this(projectRoot, new TooltipCatalogSource(projectRoot)) { }

        internal TooltipV8Engine(string projectRoot, TooltipCatalogSource source)
        {
            string path = Path.Combine(projectRoot, "launcher", "scripts", "dist", "tooltip-bundle.js");
            string bundle = TooltipCatalogSource.ReadText(path, 16 * 1024 * 1024);
            var snapshot = source.Snapshot;
            Identity = "tooltip-v1:" + TooltipCatalogSource.Hash(bundle) + ":" + snapshot.Digest;
            _engine = new V8ScriptEngine(V8ScriptEngineFlags.DisableGlobalMembers);
            try
            {
                _engine.Execute("tooltip-bundle.js", bundle);
                _engine.Script.TooltipEngine.initCatalog(snapshot.Catalog);
            }
            catch { _engine.Dispose(); throw; }
        }

        public string BuildProjection(string inputJson) =>
            _engine.Script.TooltipEngine.buildProjectionJson(inputJson) as string
                ?? throw new InvalidOperationException("tooltip_v8_result_type");

        public void Dispose() => _engine.Dispose();
    }
}
