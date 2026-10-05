using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using Microsoft.Web.WebView2.Core;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class FixedRuntimeLiveFactAttribute : FactAttribute
    {
        public FixedRuntimeLiveFactAttribute()
        {
            if (Environment.GetEnvironmentVariable("CF7_TEST_FIXED_WEBVIEW_PAYLOAD") == null)
                Skip = "Explicit CF7_TEST_FIXED_WEBVIEW_PAYLOAD required for full bundled-engine materialization.";
        }
    }

    public sealed class FixedWebViewRuntimeLiveTests
    {
        [FixedRuntimeLiveFact]
        public void WholeArchive_MaterializesExactEngineAndRepairsTamperedCache()
        {
            string payload = Environment.GetEnvironmentVariable("CF7_TEST_FIXED_WEBVIEW_PAYLOAD");
            string cache = Path.Combine(Path.GetTempPath(), "cf7-fixed-runtime-live-" + Guid.NewGuid().ToString("N"));
            var specification = FixedWebViewRuntime.ReadLock();
            var timer = Stopwatch.StartNew();
            string engine = FixedWebViewRuntime.Prepare(payload, cache, specification);
            Assert.Equal(specification.Version, CoreWebView2Environment.GetAvailableBrowserVersionString(engine));
            FixedWebViewRuntime.VerifyTree(engine, specification.Files);
            long initialMs = timer.ElapsedMilliseconds;
            timer.Restart();
            Assert.Equal(engine, FixedWebViewRuntime.Prepare(payload, cache, specification));
            long reuseMs = timer.ElapsedMilliseconds;
            // Corrupt an inert data file in this test's unique cache; no user profile or live engine is touched.
            var entry = specification.Files.First(x => x.Path == "Locales/zh-CN.pak");
            string path = FixedWebViewRuntime.SafePath(engine, entry.Path);
            using (var file = new FileStream(path, FileMode.Open, FileAccess.ReadWrite))
            { int value = file.ReadByte(); file.Position = 0; file.WriteByte((byte)(value ^ 1)); }
            Assert.Equal(engine, FixedWebViewRuntime.Prepare(payload, cache, specification));
            FixedWebViewRuntime.VerifyTree(engine, specification.Files);
            Assert.Single(Directory.GetDirectories(cache, "*.invalid-*"));
            Console.WriteLine("Fixed WebView2 archive verified: version=" + specification.Version
                + " cab=" + specification.CabSha256 + " files=" + specification.Files.Length
                + " initialMs=" + initialMs + " reuseMs=" + reuseMs + " cache=" + cache);
        }
    }
}
