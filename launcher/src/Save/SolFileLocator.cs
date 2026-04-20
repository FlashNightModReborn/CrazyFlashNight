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
    public class SolFileLocator : ISolFileLocator
    {
        private readonly string _shareRoot;     // %APPDATA%\Macromedia\Flash Player\#SharedObjects
        private readonly object _cacheLock = new object();
        private string _hashCache;              // winning hash subdir like "BMTA4F55"
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
        /// Flash Player may create multiple hash subdirs (different Flash
        /// plugin installs, different machine states) — probe every subdir in
        /// order, winning hash is cached for stability.
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

            string solFileName = SanitizeSlot(slot) + ".sol";
            string swfFileName = Path.GetFileName(swfPath);

            // Build subpath candidates from swfPath.
            // Example swfPath: "E:\steam\steamapps\common\...\CRAZYFLASHER7MercenaryEmpire.swf"
            // Flash "localhost" + "<path-with-or-without-drive>" + <swfName>
            string variantA = BuildSubPath(swfPath, includeDrive: false);
            string variantB = BuildSubPath(swfPath, includeDrive: true);

            // Preferred probe order: last-winning hash first (stability),
            // then all remaining subdirs. Ensures we don't silently miss a
            // SOL under a non-first hash subdir.
            string preferredHash;
            Variant cachedVariant;
            lock (_cacheLock)
            {
                preferredHash = _hashCache;
                cachedVariant = _variantCache;
            }

            string[] hashDirs = EnumerateHashDirs();
            if (hashDirs == null || hashDirs.Length == 0) return null;

            foreach (string hashDir in OrderedHashDirs(hashDirs, preferredHash))
            {
                string tryA = Path.Combine(hashDir, variantA, solFileName);
                string tryB = Path.Combine(hashDir, variantB, solFileName);

                // Honor the last-winning variant first for the preferred hash.
                string hashName = Path.GetFileName(hashDir);
                bool isPreferred = (preferredHash != null && hashName == preferredHash);
                if (isPreferred)
                {
                    if (cachedVariant == Variant.DropDrive && File.Exists(tryA))
                        return tryA;
                    if (cachedVariant == Variant.KeepDrive && File.Exists(tryB))
                        return tryB;
                }

                if (File.Exists(tryA)) { Cache(hashName, Variant.DropDrive); return tryA; }
                if (File.Exists(tryB)) { Cache(hashName, Variant.KeepDrive); return tryB; }

                string globHit = GlobFallback(hashDir, swfFileName, solFileName);
                if (globHit != null)
                {
                    Cache(hashName, Variant.Glob);
                    return globHit;
                }
            }

            return null;
        }

        /// <summary>
        /// Delete every SOL candidate matching (slot, swfPath) across all known
        /// hash dirs / path variants. Used by "fresh start" flows so hidden
        /// corrupt SOL residues do not hijack new-character creation.
        /// </summary>
        public int DeleteAllSolFiles(string slot, string swfPath)
        {
            HashSet<string> candidates = CollectSolCandidates(slot, swfPath);
            int deleted = 0;
            foreach (string path in candidates)
            {
                try
                {
                    File.Delete(path);
                    deleted++;
                    LogManager.Log("[SolFileLocator] deleted SOL: " + path);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[SolFileLocator] delete SOL failed: " + path + " ex=" + ex.Message);
                }
            }
            if (deleted > 0)
            {
                lock (_cacheLock)
                {
                    _hashCache = null;
                    _variantCache = Variant.Unknown;
                }
            }
            return deleted;
        }

        private HashSet<string> CollectSolCandidates(string slot, string swfPath)
        {
            HashSet<string> hits = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (string.IsNullOrEmpty(slot) || string.IsNullOrEmpty(swfPath))
                return hits;
            if (!Directory.Exists(_shareRoot))
                return hits;

            string solFileName = SanitizeSlot(slot) + ".sol";
            string swfFileName = Path.GetFileName(swfPath);
            string variantA = BuildSubPath(swfPath, includeDrive: false);
            string variantB = BuildSubPath(swfPath, includeDrive: true);
            string[] hashDirs = EnumerateHashDirs();
            if (hashDirs == null || hashDirs.Length == 0) return hits;

            foreach (string hashDir in hashDirs)
            {
                string tryA = Path.Combine(hashDir, variantA, solFileName);
                string tryB = Path.Combine(hashDir, variantB, solFileName);
                if (File.Exists(tryA)) hits.Add(tryA);
                if (File.Exists(tryB)) hits.Add(tryB);
                AddGlobMatches(hashDir, swfFileName, solFileName, hits);
            }
            return hits;
        }

        private void Cache(string hash, Variant v)
        {
            lock (_cacheLock)
            {
                _hashCache = hash;
                _variantCache = v;
            }
        }

        private string[] EnumerateHashDirs()
        {
            try
            {
                string[] subs = Directory.GetDirectories(_shareRoot);
                if (subs.Length == 0)
                {
                    LogManager.Log("[SolFileLocator] no hash subdir under " + _shareRoot);
                    return null;
                }
                return subs;
            }
            catch (Exception ex)
            {
                LogManager.Log("[SolFileLocator] enumerate hash subdirs failed: " + ex.Message);
                return null;
            }
        }

        private static IEnumerable<string> OrderedHashDirs(string[] hashDirs, string preferredHash)
        {
            if (preferredHash != null)
            {
                foreach (string d in hashDirs)
                {
                    if (Path.GetFileName(d) == preferredHash) { yield return d; break; }
                }
            }
            foreach (string d in hashDirs)
            {
                if (preferredHash == null || Path.GetFileName(d) != preferredHash)
                    yield return d;
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

        private static void AddGlobMatches(string hashDir, string swfFileName, string solFileName, ISet<string> hits)
        {
            string localhost = Path.Combine(hashDir, "localhost");
            if (!Directory.Exists(localhost)) return;
            try
            {
                string[] candidates = Directory.GetFiles(
                    localhost,
                    solFileName,
                    SearchOption.AllDirectories);
                foreach (string candidate in candidates)
                {
                    string parent = Path.GetFileName(Path.GetDirectoryName(candidate) ?? string.Empty);
                    if (string.Equals(parent, swfFileName, StringComparison.OrdinalIgnoreCase))
                        hits.Add(candidate);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[SolFileLocator] glob collect failed: " + ex.Message);
            }
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
