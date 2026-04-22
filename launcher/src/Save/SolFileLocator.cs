// CF7:ME SOL file path resolver.
// Flash Player's SharedObject storage layout is version-dependent; in
// particular the drive-letter handling has at least 3 variants seen in the
// wild. This locator probes current-root variants only and keeps the winning
// probe as a hint, not as a source of cross-root fallback.
// C# 5 syntax.

using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Guardian;

namespace CF7Launcher.Save
{
    /// <summary>
    /// Locates a SOL file for a given SWF path and slot name.
    /// Probe order: current-root SWF drop/keep drive, current-root EXE
    /// drop/keep drive, then root-scoped fallback inside the current runtime
    /// directory only.
    /// </summary>
    public class SolFileLocator : ISolFileLocator
    {
        private readonly string _shareRoot;
        private readonly object _cacheLock = new object();
        private string _hashCache;
        private ProbeKind _probeCache = ProbeKind.Unknown;

        private enum ProbeKind
        {
            Unknown,
            SwfDropDrive,
            SwfKeepDrive,
            ExeDropDrive,
            ExeKeepDrive,
            RootScopedFallback
        }

        private sealed class DirectProbe
        {
            public string Path;
            public ProbeKind Kind;
            public string Label;
        }

        public SolFileLocator()
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _shareRoot = Path.Combine(appData, "Macromedia", "Flash Player", "#SharedObjects");
        }

        public SolFileLocator(string shareRoot)
        {
            _shareRoot = shareRoot;
        }

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
            string exeFileName = Path.GetFileName(Path.ChangeExtension(swfPath, ".exe"));

            string preferredHash;
            ProbeKind cachedProbe;
            lock (_cacheLock)
            {
                preferredHash = _hashCache;
                cachedProbe = _probeCache;
            }

            string[] hashDirs = EnumerateHashDirs();
            if (hashDirs == null || hashDirs.Length == 0) return null;

            foreach (string hashDir in OrderedHashDirs(hashDirs, preferredHash))
            {
                string hashName = Path.GetFileName(hashDir);
                DirectProbe[] probes = BuildDirectProbes(hashDir, swfPath, solFileName);

                if (preferredHash != null && string.Equals(hashName, preferredHash, StringComparison.OrdinalIgnoreCase))
                {
                    string cachedHit = TryCachedProbe(hashDir, swfPath, solFileName, swfFileName, exeFileName, probes, cachedProbe);
                    if (cachedHit != null)
                        return cachedHit;
                }

                for (int i = 0; i < probes.Length; i++)
                {
                    if (File.Exists(probes[i].Path))
                    {
                        Cache(hashName, probes[i].Kind);
                        LogManager.Log("[SolFileLocator] hit " + probes[i].Label + ": " + probes[i].Path);
                        return probes[i].Path;
                    }
                }

                string scopedHit = FindRootScopedFallback(hashDir, swfPath, solFileName, swfFileName, exeFileName);
                if (scopedHit != null)
                {
                    Cache(hashName, ProbeKind.RootScopedFallback);
                    LogManager.Log("[SolFileLocator] hit root_scoped_fallback: " + scopedHit);
                    return scopedHit;
                }
            }

            return null;
        }

        public int DeleteAllSolFiles(string slot, string swfPath)
        {
            HashSet<string> candidates = CollectSolCandidates(slot, swfPath);
            List<string> ordered = new List<string>(candidates);
            ordered.Sort(StringComparer.OrdinalIgnoreCase);
            LogManager.Log("[SolFileLocator] delete candidates slot=" + slot
                + " count=" + ordered.Count
                + (ordered.Count > 0 ? " => " + string.Join(" | ", ordered.ToArray()) : string.Empty));

            int deleted = 0;
            for (int i = 0; i < ordered.Count; i++)
            {
                string path = ordered[i];
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
                    _probeCache = ProbeKind.Unknown;
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
            string exeFileName = Path.GetFileName(Path.ChangeExtension(swfPath, ".exe"));
            string[] hashDirs = EnumerateHashDirs();
            if (hashDirs == null || hashDirs.Length == 0) return hits;

            for (int i = 0; i < hashDirs.Length; i++)
            {
                DirectProbe[] probes = BuildDirectProbes(hashDirs[i], swfPath, solFileName);
                for (int j = 0; j < probes.Length; j++)
                {
                    if (File.Exists(probes[j].Path))
                        hits.Add(probes[j].Path);
                }
                AddRootScopedMatches(hashDirs[i], swfPath, solFileName, swfFileName, exeFileName, hits);
            }

            return hits;
        }

        private void Cache(string hash, ProbeKind probe)
        {
            lock (_cacheLock)
            {
                _hashCache = hash;
                _probeCache = probe;
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
                Array.Sort(subs, StringComparer.OrdinalIgnoreCase);
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
                for (int i = 0; i < hashDirs.Length; i++)
                {
                    if (string.Equals(Path.GetFileName(hashDirs[i]), preferredHash, StringComparison.OrdinalIgnoreCase))
                    {
                        yield return hashDirs[i];
                        break;
                    }
                }
            }

            for (int i = 0; i < hashDirs.Length; i++)
            {
                if (preferredHash == null
                    || !string.Equals(Path.GetFileName(hashDirs[i]), preferredHash, StringComparison.OrdinalIgnoreCase))
                {
                    yield return hashDirs[i];
                }
            }
        }

        private static string TryCachedProbe(
            string hashDir,
            string swfPath,
            string solFileName,
            string swfFileName,
            string exeFileName,
            DirectProbe[] probes,
            ProbeKind cachedProbe)
        {
            for (int i = 0; i < probes.Length; i++)
            {
                if (probes[i].Kind == cachedProbe && File.Exists(probes[i].Path))
                {
                    LogManager.Log("[SolFileLocator] hit cached " + probes[i].Label + ": " + probes[i].Path);
                    return probes[i].Path;
                }
            }

            if (cachedProbe == ProbeKind.RootScopedFallback)
            {
                string cachedHit = FindRootScopedFallback(hashDir, swfPath, solFileName, swfFileName, exeFileName);
                if (cachedHit != null)
                {
                    LogManager.Log("[SolFileLocator] hit cached root_scoped_fallback: " + cachedHit);
                    return cachedHit;
                }
            }

            return null;
        }

        private static DirectProbe[] BuildDirectProbes(string hashDir, string swfPath, string solFileName)
        {
            string exePath = Path.ChangeExtension(swfPath, ".exe");
            return new DirectProbe[]
            {
                new DirectProbe
                {
                    Kind = ProbeKind.SwfDropDrive,
                    Label = "swf_drop_drive",
                    Path = Path.Combine(hashDir, BuildSubPath(swfPath, false), solFileName)
                },
                new DirectProbe
                {
                    Kind = ProbeKind.SwfKeepDrive,
                    Label = "swf_keep_drive",
                    Path = Path.Combine(hashDir, BuildSubPath(swfPath, true), solFileName)
                },
                new DirectProbe
                {
                    Kind = ProbeKind.ExeDropDrive,
                    Label = "exe_drop_drive",
                    Path = Path.Combine(hashDir, BuildSubPath(exePath, false), solFileName)
                },
                new DirectProbe
                {
                    Kind = ProbeKind.ExeKeepDrive,
                    Label = "exe_keep_drive",
                    Path = Path.Combine(hashDir, BuildSubPath(exePath, true), solFileName)
                }
            };
        }

        private static string[] BuildScopedRoots(string hashDir, string swfPath)
        {
            string swfDir = Path.GetDirectoryName(swfPath);
            if (string.IsNullOrEmpty(swfDir))
                return new string[0];

            return new string[]
            {
                Path.Combine(hashDir, BuildSubPath(swfDir, false)),
                Path.Combine(hashDir, BuildSubPath(swfDir, true))
            };
        }

        private static string BuildSubPath(string absolutePath, bool includeDrive)
        {
            List<string> segments = new List<string>();
            segments.Add("localhost");

            string root = Path.GetPathRoot(absolutePath);
            string rest = absolutePath.Substring(root != null ? root.Length : 0);

            if (includeDrive && !string.IsNullOrEmpty(root))
            {
                char drive = root[0];
                if (char.IsLetter(drive))
                    segments.Add(drive.ToString());
            }

            string[] parts = rest.Split('\\', '/');
            for (int i = 0; i < parts.Length; i++)
            {
                if (parts[i].Length > 0)
                    segments.Add(parts[i]);
            }

            return string.Join("/", segments.ToArray());
        }

        private static string FindRootScopedFallback(string hashDir, string swfPath, string solFileName, string swfFileName, string exeFileName)
        {
            string[] scopedRoots = BuildScopedRoots(hashDir, swfPath);
            try
            {
                for (int i = 0; i < scopedRoots.Length; i++)
                {
                    string scopedRoot = scopedRoots[i];
                    if (!Directory.Exists(scopedRoot))
                        continue;

                    string[] candidates = Directory.GetFiles(scopedRoot, solFileName, SearchOption.AllDirectories);
                    Array.Sort(candidates, StringComparer.OrdinalIgnoreCase);
                    for (int j = 0; j < candidates.Length; j++)
                    {
                        if (IsCurrentRootMatch(candidates[j], swfFileName, exeFileName))
                            return candidates[j];
                    }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[SolFileLocator] root-scoped fallback failed: " + ex.Message);
            }

            return null;
        }

        private static void AddRootScopedMatches(string hashDir, string swfPath, string solFileName, string swfFileName, string exeFileName, ISet<string> hits)
        {
            string[] scopedRoots = BuildScopedRoots(hashDir, swfPath);
            try
            {
                for (int i = 0; i < scopedRoots.Length; i++)
                {
                    string scopedRoot = scopedRoots[i];
                    if (!Directory.Exists(scopedRoot))
                        continue;

                    string[] candidates = Directory.GetFiles(scopedRoot, solFileName, SearchOption.AllDirectories);
                    Array.Sort(candidates, StringComparer.OrdinalIgnoreCase);
                    for (int j = 0; j < candidates.Length; j++)
                    {
                        if (IsCurrentRootMatch(candidates[j], swfFileName, exeFileName))
                            hits.Add(candidates[j]);
                    }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[SolFileLocator] root-scoped collect failed: " + ex.Message);
            }
        }

        private static bool IsCurrentRootMatch(string candidate, string swfFileName, string exeFileName)
        {
            string parent = Path.GetFileName(Path.GetDirectoryName(candidate) ?? string.Empty);
            return string.Equals(parent, swfFileName, StringComparison.OrdinalIgnoreCase)
                || string.Equals(parent, exeFileName, StringComparison.OrdinalIgnoreCase);
        }

        private static string SanitizeSlot(string slot)
        {
            return slot;
        }
    }
}
