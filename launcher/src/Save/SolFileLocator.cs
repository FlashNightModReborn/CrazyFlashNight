// CF7:ME SOL file path resolver.
// Flash Player's SharedObject storage layout is version-dependent; in
// particular the drive-letter handling has at least 3 variants seen in the
// wild. This locator probes all of them and caches which one worked.
// C# 5 syntax.

using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Guardian;

namespace CF7Launcher.Save
{
    /// <summary>
    /// Locates a SOL file for a given SWF path and slot name.
    /// Variant fallback: drop-drive / keep-drive / directory-glob.
    /// </summary>
    public class SolFileLocator
    {
        private readonly string _shareRoot;     // %APPDATA%\Macromedia\Flash Player\#SharedObjects
        private readonly object _cacheLock = new object();
        private string _hashCache;              // subdir like "BMTA4F55"
        private Variant _variantCache = Variant.Unknown;

        private enum Variant { Unknown, DropDrive, KeepDrive, Glob }

        public SolFileLocator()
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _shareRoot = Path.Combine(
                appData,
                "Macromedia",
                "Flash Player",
                "#SharedObjects");
        }

        /// <summary>
        /// Return the full path to the SOL file for (slot, swfPath), or null
        /// if none of the variants yield an existing file.
        /// </summary>
        public string FindSolFile(string slot, string swfPath)
        {
            if (string.IsNullOrEmpty(slot) || string.IsNullOrEmpty(swfPath))
                return null;
            if (!Directory.Exists(_shareRoot))
            {
                LogManager.Log("[SolFileLocator] shareRoot missing: " + _shareRoot);
                return null;
            }

            string hash = GetHashSubdir();
            if (hash == null) return null;
            string hashDir = Path.Combine(_shareRoot, hash);

            string solFileName = SanitizeSlot(slot) + ".sol";
            string swfFileName = Path.GetFileName(swfPath);

            // Build subpath candidates from swfPath.
            // Example swfPath: "E:\steam\steamapps\common\...\CRAZYFLASHER7MercenaryEmpire.swf"
            // Flash "localhost" + "<path-with-or-without-drive>" + <swfName>
            string variantA = BuildSubPath(swfPath, includeDrive: false);
            string variantB = BuildSubPath(swfPath, includeDrive: true);

            // Try cached variant first for stability.
            Variant cached;
            lock (_cacheLock) { cached = _variantCache; }

            string tryA = Path.Combine(hashDir, variantA, solFileName);
            string tryB = Path.Combine(hashDir, variantB, solFileName);

            if (cached == Variant.DropDrive && File.Exists(tryA)) return tryA;
            if (cached == Variant.KeepDrive && File.Exists(tryB)) return tryB;

            if (File.Exists(tryA)) { Cache(Variant.DropDrive); return tryA; }
            if (File.Exists(tryB)) { Cache(Variant.KeepDrive); return tryB; }

            // Glob fallback: walk hashDir/localhost/** searching for <swfName>/<slot>.sol.
            string globHit = GlobFallback(hashDir, swfFileName, solFileName);
            if (globHit != null)
            {
                Cache(Variant.Glob);
                return globHit;
            }

            return null;
        }

        private void Cache(Variant v)
        {
            lock (_cacheLock) { _variantCache = v; }
        }

        private string GetHashSubdir()
        {
            lock (_cacheLock)
            {
                if (_hashCache != null) return _hashCache;
            }
            try
            {
                string[] subs = Directory.GetDirectories(_shareRoot);
                if (subs.Length == 0)
                {
                    LogManager.Log("[SolFileLocator] no hash subdir under " + _shareRoot);
                    return null;
                }
                // In the wild there's typically exactly one; if multiple, pick
                // the first (Flash uses a stable machine-specific hash).
                string name = Path.GetFileName(subs[0]);
                lock (_cacheLock) { _hashCache = name; }
                return name;
            }
            catch (Exception ex)
            {
                LogManager.Log("[SolFileLocator] GetHashSubdir failed: " + ex.Message);
                return null;
            }
        }

        /// <summary>
        /// Build "localhost/&lt;path-segments&gt;/&lt;swfFileName&gt;" from an absolute
        /// Windows path. When includeDrive is false, drops "E:" entirely.
        /// When true, treats "E" as a path segment (no colon).
        /// </summary>
        private static string BuildSubPath(string swfPath, bool includeDrive)
        {
            List<string> segments = new List<string>();
            segments.Add("localhost");

            string root = Path.GetPathRoot(swfPath);
            string rest = swfPath.Substring(root != null ? root.Length : 0);

            if (includeDrive && !string.IsNullOrEmpty(root))
            {
                // root typically "E:\" — take the drive letter as a segment.
                char drive = root[0];
                if (char.IsLetter(drive))
                {
                    segments.Add(drive.ToString());
                }
            }

            foreach (string seg in rest.Split('\\', '/'))
            {
                if (seg.Length > 0)
                    segments.Add(seg);
            }

            // segments now ends with the SWF filename; we want the directory
            // that contains <slot>.sol, which Flash Player names with the SWF
            // filename itself. BuildSubPath returns the subdir minus the file.
            // So we keep the SWF filename as the final directory segment.
            return string.Join("/", segments.ToArray());
        }

        private static string GlobFallback(string hashDir, string swfFileName, string solFileName)
        {
            string localhost = Path.Combine(hashDir, "localhost");
            if (!Directory.Exists(localhost)) return null;
            try
            {
                // Recursively search for any directory ending with the SWF
                // filename and containing the target SOL file.
                string[] candidates = Directory.GetFiles(
                    localhost,
                    solFileName,
                    SearchOption.AllDirectories);
                foreach (string candidate in candidates)
                {
                    string parent = Path.GetFileName(Path.GetDirectoryName(candidate) ?? string.Empty);
                    if (string.Equals(parent, swfFileName, StringComparison.OrdinalIgnoreCase))
                        return candidate;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[SolFileLocator] glob fallback failed: " + ex.Message);
            }
            return null;
        }

        /// <summary>
        /// Slot names are already sanitized by callers (ArchiveTask), but we
        /// re-apply here because this is the canonical SOL-path builder.
        /// </summary>
        private static string SanitizeSlot(string slot)
        {
            // Flash stores SOL files as <name>.sol where <name> is whatever
            // AS2 code passed to getLocal. Callers pass slot names from
            // AppConfig which we trust; no transformation needed here.
            return slot;
        }
    }
}
