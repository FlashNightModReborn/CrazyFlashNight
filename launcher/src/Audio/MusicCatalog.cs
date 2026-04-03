// CF7:ME MusicCatalog — BGM track registry with auto-discovery and hot-reload
// C# 5 syntax

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Xml;
using CF7Launcher.Guardian;
using CF7Launcher.Services;

namespace CF7Launcher.Audio
{
    internal class TrackInfo
    {
        public string Title;
        public string Url;          // relative path, e.g. "sounds/TFR/xxx.mp3"
        public string Album;
        public int FadeDuration;    // frames (30fps), default 20
        public int BaseVolume;      // 0-∞, default 100
        public int Weight;          // album-internal weight, default 100
        public bool IsRegistered;   // true = from bgm_list.xml
    }

    /// <summary>
    /// Merges bgm_list.xml (hand-authored) with filesystem auto-discovery.
    /// Monitors sounds/ for hot-reload via DirectoryWatcherService.
    ///
    /// Priority: bgm_list.xml explicit > bgm_list.xml defaults > auto-discovered.
    /// </summary>
    internal class MusicCatalog : IDisposable
    {
        private static readonly string[] AUDIO_EXTENSIONS = { ".mp3", ".wav", ".ogg", ".flac" };
        private const int DEFAULT_FADE = 20;
        private const int DEFAULT_VOLUME = 100;
        private const int DEFAULT_WEIGHT = 100;

        private readonly string _projectRoot;
        private readonly string _soundsDir;

        // Master indices
        private readonly Dictionary<string, TrackInfo> _tracks;       // title -> TrackInfo
        private readonly Dictionary<string, List<string>> _albums;    // albumName -> [title, ...]

        // URL-based dedup for auto-discovered files (avoid title collision from different folders)
        private readonly Dictionary<string, string> _urlToTitle;

        private DirectoryWatcherService _watcher;
        private bool _disposed;

        /// <summary>Fires when catalog changes (hot-reload). Argument is the update JSON string.</summary>
        public event Action<string> CatalogChanged;

        public MusicCatalog(string projectRoot)
        {
            _projectRoot = projectRoot;
            _soundsDir = Path.Combine(projectRoot, "sounds");
            _tracks = new Dictionary<string, TrackInfo>(StringComparer.OrdinalIgnoreCase);
            _albums = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            _urlToTitle = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            // Step 1: Parse bgm_list.xml (registered tracks)
            ParseBgmListXml();

            // Step 2: Scan filesystem for unregistered tracks
            int autoCount = ScanFilesystem();

            // Step 3: Build album index from all tracks
            RebuildAlbumIndex();

            LogManager.Log("[MusicCatalog] Init: " + _tracks.Count + " tracks, "
                + _albums.Count + " albums, " + autoCount + " auto-discovered");

            // Step 4: Start hot-reload watcher
            if (Directory.Exists(_soundsDir))
            {
                _watcher = new DirectoryWatcherService(
                    _soundsDir, AUDIO_EXTENSIONS, true, 500, OnFilesChanged);
                _watcher.Start();
            }
        }

        // ── bgm_list.xml parsing ──

        private void ParseBgmListXml()
        {
            string xmlPath = Path.Combine(_projectRoot, "sounds", "bgm_list.xml");
            if (!File.Exists(xmlPath))
            {
                LogManager.Log("[MusicCatalog] bgm_list.xml not found: " + xmlPath);
                return;
            }

            try
            {
                XmlDocument doc = new XmlDocument();
                doc.Load(xmlPath);

                XmlNodeList musicNodes = doc.SelectNodes("/data/music");
                if (musicNodes == null) return;

                for (int i = 0; i < musicNodes.Count; i++)
                {
                    XmlNode node = musicNodes[i];
                    string title = GetChildText(node, "title");
                    string url = GetChildText(node, "url");
                    if (string.IsNullOrEmpty(title) || string.IsNullOrEmpty(url)) continue;
                    if (title == "stop") continue; // reserved keyword

                    string album = GetChildText(node, "album");
                    if (string.IsNullOrEmpty(album))
                        album = DeriveAlbumFromUrl(url);

                    int fade = ParseInt(GetChildText(node, "fadeDuration"), DEFAULT_FADE);
                    int vol = ParseInt(GetChildText(node, "baseVolume"), DEFAULT_VOLUME);
                    int weight = ParseInt(GetChildText(node, "weight"), DEFAULT_WEIGHT);

                    var track = new TrackInfo
                    {
                        Title = title,
                        Url = url,
                        Album = album,
                        FadeDuration = fade,
                        BaseVolume = vol,
                        Weight = weight,
                        IsRegistered = true
                    };

                    _tracks[title] = track;
                    _urlToTitle[url] = title;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[MusicCatalog] Error parsing bgm_list.xml: " + ex.Message);
            }
        }

        // ── Filesystem scan ──

        private int ScanFilesystem()
        {
            int count = 0;
            if (!Directory.Exists(_soundsDir)) return 0;

            string[] dirs = Directory.GetDirectories(_soundsDir);
            for (int d = 0; d < dirs.Length; d++)
            {
                string dirName = Path.GetFileName(dirs[d]);
                // Skip SFX export directory
                if (string.Equals(dirName, "export", StringComparison.OrdinalIgnoreCase))
                    continue;

                string[] files = Directory.GetFiles(dirs[d]);
                for (int f = 0; f < files.Length; f++)
                {
                    string ext = Path.GetExtension(files[f]);
                    if (!IsAudioExtension(ext)) continue;

                    string relUrl = "sounds/" + dirName + "/" + Path.GetFileName(files[f]);

                    // Already registered by bgm_list.xml?
                    if (_urlToTitle.ContainsKey(relUrl)) continue;

                    string title = Path.GetFileNameWithoutExtension(files[f]);
                    // Avoid title collision: if title exists, prefix with folder
                    if (_tracks.ContainsKey(title))
                        title = dirName + "/" + title;

                    var track = new TrackInfo
                    {
                        Title = title,
                        Url = relUrl,
                        Album = dirName,
                        FadeDuration = DEFAULT_FADE,
                        BaseVolume = DEFAULT_VOLUME,
                        Weight = DEFAULT_WEIGHT,
                        IsRegistered = false
                    };

                    _tracks[title] = track;
                    _urlToTitle[relUrl] = title;
                    count++;
                }
            }
            return count;
        }

        // ── Album index ──

        private void RebuildAlbumIndex()
        {
            _albums.Clear();
            foreach (var kv in _tracks)
            {
                TrackInfo t = kv.Value;
                if (string.IsNullOrEmpty(t.Album)) continue;

                List<string> list;
                if (!_albums.TryGetValue(t.Album, out list))
                {
                    list = new List<string>();
                    _albums[t.Album] = list;
                }
                list.Add(t.Title);
            }
        }

        // ── Hot-reload callback ──

        private void OnFilesChanged(List<FileChangeInfo> batch)
        {
            if (batch == null)
            {
                // Buffer overflow — full rescan
                LogManager.Log("[MusicCatalog] Buffer overflow, doing full rescan");
                int autoRemoved = 0;
                // Remove all auto-discovered, then rescan
                var toRemove = new List<string>();
                foreach (var kv in _tracks)
                {
                    if (!kv.Value.IsRegistered) toRemove.Add(kv.Key);
                }
                for (int i = 0; i < toRemove.Count; i++)
                {
                    TrackInfo t = _tracks[toRemove[i]];
                    _urlToTitle.Remove(t.Url);
                    _tracks.Remove(toRemove[i]);
                    autoRemoved++;
                }
                int added = ScanFilesystem();
                RebuildAlbumIndex();
                LogManager.Log("[MusicCatalog] Rescan complete: +" + added + " -" + autoRemoved);
                // Push full catalog
                FireCatalogChanged(GetFullCatalogJson());
                return;
            }

            var addedTracks = new List<TrackInfo>();
            var removedTitles = new List<string>();

            for (int i = 0; i < batch.Count; i++)
            {
                FileChangeInfo change = batch[i];
                string relUrl = "sounds/" + change.RelativePath;

                if (change.ChangeType == FileChangeType.Created)
                {
                    // Skip if already registered
                    if (_urlToTitle.ContainsKey(relUrl)) continue;

                    // Skip if in export/ dir
                    if (change.RelativePath.StartsWith("export/", StringComparison.OrdinalIgnoreCase)
                        || change.RelativePath.StartsWith("export\\", StringComparison.OrdinalIgnoreCase))
                        continue;

                    // Derive album from subfolder
                    int slash = change.RelativePath.IndexOf('/');
                    if (slash < 0) slash = change.RelativePath.IndexOf('\\');
                    string album = (slash > 0) ? change.RelativePath.Substring(0, slash) : "unknown";

                    string title = Path.GetFileNameWithoutExtension(change.FullPath);
                    if (_tracks.ContainsKey(title))
                        title = album + "/" + title;

                    var track = new TrackInfo
                    {
                        Title = title,
                        Url = relUrl,
                        Album = album,
                        FadeDuration = DEFAULT_FADE,
                        BaseVolume = DEFAULT_VOLUME,
                        Weight = DEFAULT_WEIGHT,
                        IsRegistered = false
                    };

                    _tracks[title] = track;
                    _urlToTitle[relUrl] = title;
                    addedTracks.Add(track);
                }
                else if (change.ChangeType == FileChangeType.Deleted)
                {
                    string title;
                    if (!_urlToTitle.TryGetValue(relUrl, out title)) continue;

                    TrackInfo existing;
                    if (_tracks.TryGetValue(title, out existing) && existing.IsRegistered)
                        continue; // Don't remove registered tracks

                    _tracks.Remove(title);
                    _urlToTitle.Remove(relUrl);
                    removedTitles.Add(title);
                }
            }

            if (addedTracks.Count == 0 && removedTitles.Count == 0) return;

            RebuildAlbumIndex();

            LogManager.Log("[MusicCatalog] Hot-reload: +" + addedTracks.Count + " -" + removedTitles.Count);

            // Build incremental update JSON
            string updateJson = BuildUpdateJson(addedTracks, removedTitles);
            FireCatalogChanged(updateJson);
        }

        private void FireCatalogChanged(string json)
        {
            if (CatalogChanged != null)
            {
                try { CatalogChanged(json); }
                catch (Exception ex) { LogManager.Log("[MusicCatalog] CatalogChanged error: " + ex.Message); }
            }
        }

        // ── JSON serialization ──

        /// <summary>Full catalog JSON for initial push to Flash and WebView.</summary>
        public string GetFullCatalogJson()
        {
            StringBuilder sb = new StringBuilder(4096);
            sb.Append("{\"task\":\"catalog\",\"type\":\"catalog\",\"tracks\":[");

            bool first = true;
            foreach (var kv in _tracks)
            {
                if (!first) sb.Append(',');
                first = false;
                AppendTrackJson(sb, kv.Value);
            }

            sb.Append("],\"albums\":{");
            bool firstAlbum = true;
            foreach (var kv in _albums)
            {
                if (!firstAlbum) sb.Append(',');
                firstAlbum = false;
                sb.Append('"');
                EscapeJsonString(sb, kv.Key);
                sb.Append("\":[");
                for (int i = 0; i < kv.Value.Count; i++)
                {
                    if (i > 0) sb.Append(',');
                    sb.Append('"');
                    EscapeJsonString(sb, kv.Value[i]);
                    sb.Append('"');
                }
                sb.Append(']');
            }
            sb.Append("}}");
            return sb.ToString();
        }

        private string BuildUpdateJson(List<TrackInfo> added, List<string> removed)
        {
            StringBuilder sb = new StringBuilder(1024);
            sb.Append("{\"task\":\"catalogUpdate\",\"type\":\"catalogUpdate\",\"added\":[");
            for (int i = 0; i < added.Count; i++)
            {
                if (i > 0) sb.Append(',');
                AppendTrackJson(sb, added[i]);
            }
            sb.Append("],\"removed\":[");
            for (int i = 0; i < removed.Count; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append('"');
                EscapeJsonString(sb, removed[i]);
                sb.Append('"');
            }
            sb.Append("]}");
            return sb.ToString();
        }

        private void AppendTrackJson(StringBuilder sb, TrackInfo t)
        {
            sb.Append("{\"title\":\"");
            EscapeJsonString(sb, t.Title);
            sb.Append("\",\"url\":\"");
            EscapeJsonString(sb, t.Url);
            sb.Append("\",\"album\":\"");
            EscapeJsonString(sb, t.Album);
            sb.Append("\",\"fade\":");
            sb.Append(t.FadeDuration);
            sb.Append(",\"vol\":");
            sb.Append(t.BaseVolume);
            sb.Append(",\"weight\":");
            sb.Append(t.Weight);
            sb.Append('}');
        }

        // ── Helpers ──

        private static string DeriveAlbumFromUrl(string url)
        {
            // "sounds/TFR/file.mp3" -> "TFR"
            if (url == null) return "unknown";
            // Normalize separators
            url = url.Replace('\\', '/');
            string[] parts = url.Split('/');
            // Expected: sounds/{album}/{file}
            if (parts.Length >= 3) return parts[1];
            if (parts.Length >= 2) return parts[0];
            return "unknown";
        }

        private static string GetChildText(XmlNode parent, string childName)
        {
            XmlNode child = parent.SelectSingleNode(childName);
            return child != null ? child.InnerText.Trim() : null;
        }

        private static int ParseInt(string s, int defaultValue)
        {
            if (string.IsNullOrEmpty(s)) return defaultValue;
            int result;
            return int.TryParse(s, out result) ? result : defaultValue;
        }

        private static bool IsAudioExtension(string ext)
        {
            if (string.IsNullOrEmpty(ext)) return false;
            for (int i = 0; i < AUDIO_EXTENSIONS.Length; i++)
            {
                if (string.Equals(ext, AUDIO_EXTENSIONS[i], StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        private static void EscapeJsonString(StringBuilder sb, string s)
        {
            if (s == null) return;
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                switch (c)
                {
                    case '\\': sb.Append("\\\\"); break;
                    case '"': sb.Append("\\\""); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default: sb.Append(c); break;
                }
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            if (_watcher != null)
            {
                _watcher.Dispose();
                _watcher = null;
            }
        }
    }
}
