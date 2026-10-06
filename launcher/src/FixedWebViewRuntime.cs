using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json;
using CF7Launcher.Guardian;

namespace CF7Launcher
{
    /// <summary>One immutable engine for every production WebView. The signed CAB is shipped in
    /// manifest-covered chunks; its complete, hash-checked contents are materialized per user.</summary>
    internal static class FixedWebViewRuntime
    {
        internal sealed class Entry
        {
            public string Path { get; set; }
            public long Size { get; set; }
            public string Sha256 { get; set; }
        }

        internal sealed class RuntimeLock
        {
            public string Schema { get; set; }
            public string Version { get; set; }
            public string Architecture { get; set; }
            public string CabSha256 { get; set; }
            public long CabSize { get; set; }
            public string ExtractedDirectory { get; set; }
            public Entry[] Parts { get; set; }
            public Entry[] Files { get; set; }
        }

        private static readonly Lazy<RuntimeLock> Specification = new Lazy<RuntimeLock>(ReadLock);
        private static readonly Lazy<Task<string>> Prepared = new Lazy<Task<string>>(
            () => Task.Run(() => Prepare(Path.Combine(AppContext.BaseDirectory, "webview2"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "CF7Launcher", "WebView2", "Fixed"), Specification.Value)));

        internal static string EnsureAvailable()
        {
            string folder = Prepared.Value.GetAwaiter().GetResult();
            ValidateVersion(CoreWebView2Environment.GetAvailableBrowserVersionString(folder));
            return Specification.Value.Version;
        }

        internal static async Task<CoreWebView2Environment> CreateAsync(string userDataFolder,
            CoreWebView2EnvironmentOptions options = null)
        {
            string folder = await Prepared.Value;
            // Engine upgrades and rollbacks must not migrate each other's browser profile.
            string profile = System.IO.Path.Combine(userDataFolder, "fixed-" + Specification.Value.Version);
            var environment = await CoreWebView2Environment.CreateAsync(folder, profile, options);
            ValidateVersion(environment.BrowserVersionString);
            return environment;
        }

        internal static void ValidateCore(CoreWebView2 core)
        {
            string folder = Prepared.Value.GetAwaiter().GetResult();
            using var process = Process.GetProcessById(checked((int)core.BrowserProcessId));
            string actual = process.MainModule.FileName;
            string expected = System.IO.Path.Combine(folder, "msedgewebview2.exe");
            // MSIX desktop hosts can redirect LocalAppData transparently. Compare final file
            // paths, not a logical path against Process.MainModule's physical cache path.
            if (!string.Equals(ResolvePhysicalPath(actual), ResolvePhysicalPath(expected), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("WebView2 engine path differs from the bundled runtime: " + actual);
            LogManager.Log("[WebView2] fixed runtime version=" + Specification.Value.Version
                + " cabSha256=" + Specification.Value.CabSha256 + " browser=" + actual);
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint length, uint flags);

        internal static string ResolvePhysicalPath(string path)
        {
            using var file = File.OpenRead(path);
            var result = new StringBuilder(1024);
            uint length = GetFinalPathNameByHandle(file.SafeFileHandle, result, (uint)result.Capacity, 0);
            if (length == 0) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            if (length >= result.Capacity)
            {
                result = new StringBuilder(checked((int)length + 1));
                length = GetFinalPathNameByHandle(file.SafeFileHandle, result, (uint)result.Capacity, 0);
                if (length == 0 || length >= result.Capacity) throw new IOException("Cannot resolve fixed WebView2 physical path.");
            }
            return result.ToString();
        }

        internal static RuntimeLock ReadLock()
        {
            using var stream = typeof(FixedWebViewRuntime).Assembly.GetManifestResourceStream(
                "CF7Launcher.webview2-runtime.lock.json");
            using var reader = new StreamReader(stream ?? throw new InvalidDataException("Missing WebView2 lock."));
            var value = JsonConvert.DeserializeObject<RuntimeLock>(reader.ReadToEnd());
            if (value == null || value.Schema != "cf7-fixed-webview2.v1" || value.Architecture != "x64"
                || !System.Version.TryParse(value.Version, out _) || !IsHash(value.CabSha256)
                || value.CabSize <= 0 || value.Parts == null || value.Parts.Length == 0
                || value.Files == null || value.Files.Length == 0)
                throw new InvalidDataException("Invalid WebView2 lock.");
            SafePath("C:\\runtime", value.ExtractedDirectory);
            foreach (var item in value.Parts.Concat(value.Files))
            {
                SafePath("C:\\runtime", item.Path);
                if (item.Size < 0 || !IsHash(item.Sha256)) throw new InvalidDataException("Invalid WebView2 file lock.");
            }
            return value;
        }

        private static bool IsHash(string hash) => hash != null && hash.Length == 64
            && hash.All(c => (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'));

        private static void ValidateVersion(string actual)
        {
            if (!string.Equals(actual, Specification.Value.Version, StringComparison.Ordinal))
                throw new InvalidOperationException("Expected fixed WebView2 " + Specification.Value.Version
                    + "; loaded " + actual + ". Check WebView2 environment or policy overrides.");
        }

        internal static string SafePath(string root, string relative)
        {
            if (string.IsNullOrEmpty(relative) || relative.Contains('\\') || relative.Contains(':')
                || relative.Split('/').Any(s => s.Length == 0 || s == "." || s == ".."
                    || s.EndsWith(' ') || s.EndsWith('.')))
                throw new InvalidDataException("Unsafe WebView2 path: " + relative);
            string fullRoot = System.IO.Path.GetFullPath(root).TrimEnd(System.IO.Path.DirectorySeparatorChar);
            string full = System.IO.Path.GetFullPath(System.IO.Path.Combine(fullRoot, relative));
            if (!full.StartsWith(fullRoot + System.IO.Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("WebView2 path escaped its root.");
            return full;
        }

        private static void RejectReparseAncestors(string path)
        {
            for (var directory = new DirectoryInfo(path); directory != null; directory = directory.Parent)
                if (directory.Exists && (directory.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("WebView2 cache cannot use a reparse point: " + directory.FullName);
        }

        private static IEnumerable<string> EnumerateFiles(string root)
        {
            foreach (string path in Directory.EnumerateFileSystemEntries(root))
            {
                var attributes = File.GetAttributes(path);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("WebView2 tree contains a reparse point: " + path);
                if ((attributes & FileAttributes.Directory) == 0) yield return path;
                else foreach (string child in EnumerateFiles(path)) yield return child;
            }
        }

        internal static void VerifyTree(string root, Entry[] entries)
        {
            RejectReparseAncestors(root);
            if (!Directory.Exists(root)) throw new DirectoryNotFoundException(root);
            var expected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var item in entries)
            {
                string path = SafePath(root, item.Path);
                if (!expected.Add(path)) throw new InvalidDataException("Duplicate WebView2 file: " + item.Path);
                VerifyFile(path, item.Size, item.Sha256);
            }
            foreach (string file in EnumerateFiles(root))
                if (!expected.Remove(file)) throw new InvalidDataException("Unexpected WebView2 file: " + file);
            if (expected.Count != 0) throw new InvalidDataException("Incomplete WebView2 tree.");
        }

        internal static void VerifyFile(string path, long size, string hash)
        {
            if (!File.Exists(path) || new FileInfo(path).Length != size
                || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Missing or invalid WebView2 payload: " + path);
            using var stream = File.OpenRead(path);
            if (!string.Equals(Convert.ToHexString(SHA256.HashData(stream)), hash, StringComparison.Ordinal))
                throw new InvalidDataException("WebView2 payload hash mismatch: " + path);
        }

        internal static string Prepare(string payload, string cacheRoot, RuntimeLock specification)
        {
            RejectReparseAncestors(payload);
            RejectReparseAncestors(cacheRoot);
            string entryRoot = SafePath(cacheRoot, specification.Version + "-" + specification.CabSha256);
            string engine = SafePath(entryRoot, "engine");
            using var mutex = new Mutex(false, "Local\\CF7-FixedWebView2-" + specification.CabSha256);
            bool acquired;
            try { acquired = mutex.WaitOne(TimeSpan.FromMinutes(3)); }
            catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) throw new TimeoutException("Another process is preparing the fixed WebView2 runtime.");
            try
            {
                // Validate the shipped source even when an older process already populated the cache.
                VerifyTree(payload, specification.Parts);
                if (Directory.Exists(entryRoot))
                {
                    try { VerifyTree(engine, specification.Files); return engine; }
                    catch (Exception error) when (error is IOException || error is InvalidDataException || error is UnauthorizedAccessException)
                    {
                        // Keep evidence and any active browser's files; never recursively delete a suspect tree.
                        RejectReparseAncestors(entryRoot);
                        Directory.Move(entryRoot, entryRoot + ".invalid-" + Guid.NewGuid().ToString("N"));
                        LogManager.Log("[WebView2] quarantined invalid fixed runtime: " + error.Message);
                    }
                }
                Directory.CreateDirectory(cacheRoot);
                string staging = SafePath(cacheRoot, ".staging-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(staging);
                string cab = SafePath(staging, "runtime.cab");
                using (var output = new FileStream(cab, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    foreach (var part in specification.Parts)
                    {
                        using var input = File.OpenRead(SafePath(payload, part.Path));
                        input.CopyTo(output);
                    }
                VerifyFile(cab, specification.CabSize, specification.CabSha256);
                RunSystemTool("expand.exe", new[] { "-F:*", cab, staging });
                File.Delete(cab);
                string stagedEngine = SafePath(staging, specification.ExtractedDirectory);
                VerifyTree(stagedEngine, specification.Files);
                GrantAppContainerReadAccess(stagedEngine);
                Directory.Move(stagedEngine, SafePath(staging, "engine"));
                Directory.Move(staging, entryRoot);
                LogManager.Log("[WebView2] materialized fixed runtime " + specification.Version);
                return engine;
            }
            finally { mutex.ReleaseMutex(); }
        }

        private static void GrantAppContainerReadAccess(string folder)
        {
            // Fixed Runtime >=120 requires these rights for unpackaged Win32 apps on Windows 10.
            if (Environment.OSVersion.Version.Build >= 22000) return;
            RunSystemTool("icacls.exe", new[] { folder, "/grant",
                "*S-1-15-2-1:(OI)(CI)(RX)", "*S-1-15-2-2:(OI)(CI)(RX)", "/T", "/Q" });
        }

        private static void RunSystemTool(string name, IEnumerable<string> arguments)
        {
            var start = new ProcessStartInfo(System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System), name))
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (string argument in arguments) start.ArgumentList.Add(argument);
            using var process = Process.Start(start);
            var output = process.StandardOutput.ReadToEndAsync();
            var error = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(120000))
            {
                process.Kill(true);
                throw new TimeoutException("Fixed WebView2 preparation timed out: " + name);
            }
            if (process.ExitCode != 0)
                throw new IOException("Fixed WebView2 preparation failed: " + name + " " + error.GetAwaiter().GetResult());
            output.GetAwaiter().GetResult();
        }
    }
}
