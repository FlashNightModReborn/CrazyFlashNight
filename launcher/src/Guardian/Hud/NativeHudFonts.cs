using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Text;
using System.IO;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Native HUD 字体入口。思源宋体复用 FontPackTask 的 AppData 字体文件，
    /// 不要求注册到 Windows，也不复制进仅供 Flash CS6/FLa 编辑的“闪7重置版字体”。
    /// PrivateFontCollection 必须与 FontFamily 同生命周期，因此进程级持有、不主动 Dispose。
    /// </summary>
    internal static class NativeHudFonts
    {
        internal const string SourceHanSerifFileName = "source-han-serif-cn-regular.otf";
        private static readonly object Sync = new object();
        private static PrivateFontCollection _privateFonts;
        private static FontFamily _sourceHanSerif;
        private static bool _initialized;
        private static string _loadedPath;

        internal static Font CreateUiFont(float size, FontStyle preferredStyle, GraphicsUnit unit)
        {
            EnsureInitialized();
            FontFamily family = _sourceHanSerif;
            if (family != null)
            {
                try
                {
                    FontStyle actual = ResolveAvailableStyle(family, preferredStyle);
                    return new Font(family, size, actual, unit);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[NativeHudFonts] private font create failed: " + ex.Message);
                }
            }

            return CreateSystemFallback(size, preferredStyle, unit);
        }

        private static void EnsureInitialized()
        {
            if (_initialized) return;
            lock (Sync)
            {
                if (_initialized) return;
                string[] candidates = BuildCandidatePaths();
                for (int i = 0; i < candidates.Length; i++)
                {
                    string path = candidates[i];
                    if (string.IsNullOrEmpty(path) || !File.Exists(path)) continue;
                    PrivateFontCollection collection = null;
                    try
                    {
                        collection = new PrivateFontCollection();
                        collection.AddFontFile(path);
                        FontFamily[] families = collection.Families;
                        if (families == null || families.Length == 0)
                        {
                            collection.Dispose();
                            continue;
                        }
                        _privateFonts = collection;
                        _sourceHanSerif = families[0];
                        _loadedPath = path;
                        _initialized = true;
                        LogManager.Log("[NativeHudFonts] loaded " + _sourceHanSerif.Name + " from " + path);
                        return;
                    }
                    catch (Exception ex)
                    {
                        if (collection != null) collection.Dispose();
                        LogManager.Log("[NativeHudFonts] load failed path=" + path + " ex=" + ex.Message);
                    }
                }
                _initialized = true;
                LogManager.Log("[NativeHudFonts] Source Han Serif unavailable; using system fallback");
            }
        }

        private static FontStyle ResolveAvailableStyle(FontFamily family, FontStyle preferred)
        {
            if (family != null && family.IsStyleAvailable(preferred)) return preferred;
            if (family != null && family.IsStyleAvailable(FontStyle.Regular)) return FontStyle.Regular;
            if (family != null && family.IsStyleAvailable(FontStyle.Bold)) return FontStyle.Bold;
            return FontStyle.Regular;
        }

        private static Font CreateSystemFallback(float size, FontStyle style, GraphicsUnit unit)
        {
            string[] names = { "Source Han Serif CN", "Source Han Serif SC", "Noto Serif CJK SC", "SimSun", "Microsoft YaHei" };
            for (int i = 0; i < names.Length; i++)
            {
                try
                {
                    Font font = new Font(names[i], size, style, unit);
                    if (string.Equals(font.FontFamily.Name, names[i], StringComparison.OrdinalIgnoreCase))
                        return font;
                    font.Dispose();
                }
                catch { }
            }
            return new Font(FontFamily.GenericSerif, size, FontStyle.Regular, unit);
        }

        private static string[] BuildCandidatePaths()
        {
            List<string> paths = new List<string>();
            string localAppData = null;
            try { localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData); }
            catch { }
            if (!string.IsNullOrEmpty(localAppData))
                paths.Add(Path.Combine(localAppData, "CF7FlashNight", "fonts", SourceHanSerifFileName));

            AddProjectRelativeCandidates(paths, AppContext.BaseDirectory);
            try { AddProjectRelativeCandidates(paths, Environment.CurrentDirectory); } catch { }

            HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            List<string> unique = new List<string>();
            for (int i = 0; i < paths.Count; i++)
            {
                string full;
                try { full = Path.GetFullPath(paths[i]); }
                catch { continue; }
                if (seen.Add(full)) unique.Add(full);
            }
            return unique.ToArray();
        }

        private static void AddProjectRelativeCandidates(List<string> paths, string startDir)
        {
            if (paths == null || string.IsNullOrEmpty(startDir)) return;
            DirectoryInfo dir;
            try { dir = new DirectoryInfo(startDir); }
            catch { return; }
            for (int i = 0; i < 5 && dir != null; i++, dir = dir.Parent)
            {
                paths.Add(Path.Combine(dir.FullName, "launcher", "web", "assets", "fonts", SourceHanSerifFileName));
            }
        }

        internal static string[] CandidatePathsForTest { get { return BuildCandidatePaths(); } }
        internal static string LoadedPathForTest { get { EnsureInitialized(); return _loadedPath; } }
        internal static string LoadedFamilyNameForTest
        {
            get { EnsureInitialized(); return _sourceHanSerif != null ? _sourceHanSerif.Name : null; }
        }
    }
}
