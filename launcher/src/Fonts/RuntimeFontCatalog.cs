using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.Guardian;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Fonts
{
    /// <summary>
    /// Gate E runtime reader for the deterministic projection generated from fonts/fonts.xml.
    /// The projection carries the XML hash, so stale generated data fails soft to system fonts.
    /// Native selections are process-lifetime cached by design; changing a native font requires restart.
    /// </summary>
    internal static class RuntimeFontCatalog
    {
        internal const string VirtualHost = "cfn-fonts.local";
        internal const long MaxFontBytes = 256L * 1024L * 1024L;

        private sealed class Asset
        {
            internal string Id;
            internal string File;
            internal string Format;
            internal long Bytes;
            internal string Sha256;
            internal HashSet<string> Targets;
        }

        private sealed class Face
        {
            internal string Id;
            internal string AssetId;
            internal string Family;
            internal int Weight;
            internal string Style;
        }

        private sealed class Role
        {
            internal string Id;
            internal List<string> Faces = new List<string>();
            internal List<string> System = new List<string>();
            internal List<string> Generic = new List<string>();
        }

        internal sealed class ResolvedAsset
        {
            internal string AssetId;
            internal string File;
            internal string Path;
            internal string Source;
            internal string Integrity;
        }

        private static readonly object Sync = new object();
        private static readonly Dictionary<string, Asset> AssetsById =
            new Dictionary<string, Asset>(StringComparer.Ordinal);
        private static readonly Dictionary<string, Asset> AssetsByFile =
            new Dictionary<string, Asset>(StringComparer.OrdinalIgnoreCase);
        private static readonly Dictionary<string, Face> FacesById =
            new Dictionary<string, Face>(StringComparer.Ordinal);
        private static readonly Dictionary<string, Role> RolesById =
            new Dictionary<string, Role>(StringComparer.Ordinal);
        private static readonly HashSet<string> AllowedHosts =
            new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private static readonly Dictionary<string, ResolvedAsset> NativeSelections =
            new Dictionary<string, ResolvedAsset>(StringComparer.Ordinal);
        private static readonly Dictionary<string, FontFamily> NativeFamilies =
            new Dictionary<string, FontFamily>(StringComparer.Ordinal);
        private static readonly List<PrivateFontCollection> PrivateCollections =
            new List<PrivateFontCollection>();

        private static bool _configured;
        private static bool _ready;
        private static string _projectRoot;
        private static string _fontRoot;
        private static string _projectionPath;
        private static string _failure;
        private static string _projectionJson;

        internal static bool IsReady { get { lock (Sync) return _ready; } }
        internal static string Failure { get { lock (Sync) return _failure; } }
        internal static string FontRoot { get { lock (Sync) return _fontRoot; } }
        internal static string CacheDirectory
        {
            get
            {
                lock (Sync)
                    return string.IsNullOrEmpty(_fontRoot)
                        ? null
                        : Path.Combine(_fontRoot, "temporary", "cache");
            }
        }

        internal static void Configure(string projectRoot)
        {
            ConfigureCore(projectRoot);
        }

        private static void ConfigureCore(string projectRoot)
        {
            lock (Sync)
            {
                if (_configured) return;
                _configured = true;
                try
                {
                    _projectRoot = Path.GetFullPath(projectRoot);
                    _fontRoot = Path.Combine(_projectRoot, "fonts");
                    _projectionPath = Path.Combine(_projectRoot, "launcher", "web", "generated", "font-catalog.json");
                    string xmlPath = Path.Combine(_fontRoot, "fonts.xml");
                    LoadProjection(xmlPath, _projectionPath);
                    _ready = true;
                    LogManager.Log("[FontCatalog] Gate E catalog ready assets=" + AssetsById.Count
                        + " roles=" + RolesById.Count + " source=" + _projectionPath);
                }
                catch (Exception ex)
                {
                    _failure = ex.GetType().Name + ": " + ex.Message;
                    _ready = false;
                    ClearModels();
                    LogManager.Log("[FontCatalog] catalog unavailable; system fallback only: " + _failure);
                }
            }
        }

        private static void LoadProjection(string xmlPath, string projectionPath)
        {
            if (!File.Exists(xmlPath)) throw new FileNotFoundException("fonts.xml missing", xmlPath);
            if (!File.Exists(projectionPath)) throw new FileNotFoundException("font-catalog.json missing", projectionPath);
            byte[] xmlBytes = File.ReadAllBytes(xmlPath);
            string expectedSourceHash = Sha256(xmlBytes);
            _projectionJson = File.ReadAllText(projectionPath, Encoding.UTF8);
            JObject root = JObject.Parse(_projectionJson);
            if (root.Value<int?>("schemaVersion") != 1) throw new InvalidDataException("projection schemaVersion must be 1");
            if (root.Value<bool?>("runtimeAuthority") != true) throw new InvalidDataException("projection is not runtime authority");
            string gate = root.Value<string>("gate");
            if (!string.Equals(gate, "D", StringComparison.Ordinal)
                && !string.Equals(gate, "E", StringComparison.Ordinal))
                throw new InvalidDataException("native runtime requires Gate D or E projection");
            if (!string.Equals(root.Value<string>("sourceSha256"), expectedSourceHash, StringComparison.Ordinal))
                throw new InvalidDataException("projection sourceSha256 does not match fonts.xml");

            JArray allowedHosts = root.Value<JArray>("allowedHosts") ?? throw new InvalidDataException("projection allowedHosts missing");
            foreach (string host in allowedHosts.Values<string>())
            {
                if (string.IsNullOrWhiteSpace(host) || Uri.CheckHostName(host) != UriHostNameType.Dns)
                    throw new InvalidDataException("invalid allowed host: " + host);
                if (!AllowedHosts.Add(host)) throw new InvalidDataException("duplicate allowed host: " + host);
            }
            if (AllowedHosts.Count == 0) throw new InvalidDataException("projection allowedHosts empty");

            JArray assets = root.Value<JArray>("assets") ?? throw new InvalidDataException("projection assets missing");
            foreach (JObject item in assets.OfType<JObject>())
            {
                Asset asset = new Asset
                {
                    Id = Required(item, "id"),
                    File = Required(item, "file"),
                    Format = Required(item, "format"),
                    Bytes = item.Value<long?>("bytes") ?? 0L,
                    Sha256 = Required(item, "sha256"),
                    Targets = new HashSet<string>((item.Value<JArray>("targets") ?? new JArray())
                        .Values<string>(), StringComparer.Ordinal),
                };
                if (!IsSafeFontFileName(asset.File)) throw new InvalidDataException("unsafe asset filename: " + asset.File);
                if (asset.Bytes < 1 || asset.Bytes > MaxFontBytes) throw new InvalidDataException("invalid asset bytes: " + asset.Id);
                if (!IsSha256(asset.Sha256)) throw new InvalidDataException("invalid asset sha256: " + asset.Id);
                if (AssetsById.ContainsKey(asset.Id) || AssetsByFile.ContainsKey(asset.File))
                    throw new InvalidDataException("duplicate asset: " + asset.Id);
                AssetsById.Add(asset.Id, asset);
                AssetsByFile.Add(asset.File, asset);
            }

            JObject faces = root.Value<JObject>("faces") ?? throw new InvalidDataException("projection faces missing");
            foreach (JProperty property in faces.Properties())
            {
                JObject item = property.Value as JObject ?? throw new InvalidDataException("invalid face: " + property.Name);
                Face face = new Face
                {
                    Id = Required(item, "id"),
                    AssetId = Required(item, "asset"),
                    Family = Required(item, "family"),
                    Weight = item.Value<int?>("weight") ?? 400,
                    Style = Required(item, "style"),
                };
                if (!AssetsById.ContainsKey(face.AssetId)) throw new InvalidDataException("face references unknown asset: " + face.Id);
                if (!string.Equals(face.Id, property.Name, StringComparison.Ordinal) || FacesById.ContainsKey(face.Id))
                    throw new InvalidDataException("duplicate or mismatched face: " + property.Name);
                FacesById.Add(face.Id, face);
            }

            JObject roles = root.Value<JObject>("roles") ?? throw new InvalidDataException("projection roles missing");
            foreach (JProperty property in roles.Properties())
            {
                JObject item = property.Value as JObject ?? throw new InvalidDataException("invalid role: " + property.Name);
                Role role = new Role { Id = Required(item, "id") };
                role.Faces.AddRange((item.Value<JArray>("faces") ?? new JArray()).Values<string>());
                foreach (JObject fallback in (item.Value<JArray>("system") ?? new JArray()).OfType<JObject>())
                    role.System.Add(Required(fallback, "family"));
                foreach (JObject fallback in (item.Value<JArray>("generic") ?? new JArray()).OfType<JObject>())
                    role.Generic.Add(Required(fallback, "family"));
                if (!string.Equals(role.Id, property.Name, StringComparison.Ordinal) || RolesById.ContainsKey(role.Id))
                    throw new InvalidDataException("duplicate or mismatched role: " + property.Name);
                if (role.Faces.Any((faceId) => !FacesById.ContainsKey(faceId)))
                    throw new InvalidDataException("role references unknown face: " + role.Id);
                RolesById.Add(role.Id, role);
            }
        }

        private static string Required(JObject item, string name)
        {
            string value = item.Value<string>(name);
            if (string.IsNullOrWhiteSpace(value)) throw new InvalidDataException("missing " + name);
            return value;
        }

        internal static Font CreateFont(string roleId, float size, FontStyle preferredStyle, GraphicsUnit unit)
        {
            Role role;
            lock (Sync)
            {
                if (!_ready || !RolesById.TryGetValue(roleId, out role))
                    return UncataloguedFallback(roleId, size, preferredStyle, unit);

                foreach (string faceId in role.Faces)
                {
                    FontFamily family = LoadNativeFace(faceId);
                    if (family == null) continue;
                    try { return new Font(family, size, AvailableStyle(family, preferredStyle), unit); }
                    catch (Exception ex) { LogManager.Log("[FontCatalog] private font create failed role=" + roleId + " face=" + faceId + " ex=" + ex.Message); }
                }
                foreach (string familyName in role.System)
                {
                    Font font = TryCreateInstalled(familyName, size, preferredStyle, unit);
                    if (font != null) return font;
                }
                foreach (string generic in role.Generic) return GenericFallback(size, preferredStyle, unit, generic);
            }
            return UncataloguedFallback(roleId, size, preferredStyle, unit);
        }

        private static Font UncataloguedFallback(
            string roleId,
            float size,
            FontStyle preferredStyle,
            GraphicsUnit unit)
        {
            // Projection failure must not turn the pre-existing native HUD into a
            // serif UI. Keep the old Windows-safe family as the emergency body
            // fallback, while retaining narrow mono/symbol behavior. Physical
            // choices still live here at the resolver boundary, never in widgets.
            if (!string.IsNullOrEmpty(roleId)
                && roleId.IndexOf("mono", StringComparison.Ordinal) >= 0)
                return GenericFallback(size, preferredStyle, unit, "monospace");
            if (!string.IsNullOrEmpty(roleId)
                && roleId.IndexOf("symbol", StringComparison.Ordinal) >= 0)
            {
                Font symbol = TryCreateInstalled(
                    "Segoe UI Symbol", size, preferredStyle, unit);
                if (symbol != null) return symbol;
            }
            Font body = TryCreateInstalled(
                "Microsoft YaHei", size, preferredStyle, unit);
            return body ?? GenericFallback(
                size, preferredStyle, unit, "sans-serif");
        }

        private static FontFamily LoadNativeFace(string faceId)
        {
            FontFamily cached;
            if (NativeFamilies.TryGetValue(faceId, out cached)) return cached;
            Face face;
            if (!FacesById.TryGetValue(faceId, out face)) return null;
            Asset asset = AssetsById[face.AssetId];
            if (!asset.Targets.Contains("native")) return null;
            ResolvedAsset resolved;
            if (!NativeSelections.TryGetValue(faceId, out resolved))
            {
                resolved = ResolveAsset(asset);
                NativeSelections[faceId] = resolved;
            }
            if (resolved == null || string.IsNullOrEmpty(resolved.Path)) return null;
            PrivateFontCollection collection = null;
            try
            {
                collection = new PrivateFontCollection();
                collection.AddFontFile(resolved.Path);
                FontFamily family = collection.Families.FirstOrDefault();
                if (family == null) throw new InvalidDataException("private collection contains no family");
                PrivateCollections.Add(collection);
                NativeFamilies[faceId] = family;
                LogManager.Log("[FontCatalog] native face=" + faceId + " source=" + resolved.Source + " path=" + resolved.Path);
                return family;
            }
            catch (Exception ex)
            {
                if (collection != null) collection.Dispose();
                LogManager.Log("[FontCatalog] native load rejected face=" + faceId + " path=" + resolved.Path + " ex=" + ex.Message);
                return null;
            }
        }

        private static ResolvedAsset ResolveAsset(Asset asset)
        {
            foreach (Tuple<string, string, bool> source in SourceDirectories())
            {
                string candidate = Path.Combine(source.Item2, asset.File);
                string integrity;
                if (VerifyCandidate(candidate, asset, source.Item3, out integrity))
                {
                    return new ResolvedAsset
                    {
                        AssetId = asset.Id,
                        File = asset.File,
                        Path = Path.GetFullPath(candidate),
                        Source = source.Item1,
                        Integrity = integrity,
                    };
                }
            }
            return null;
        }

        private static IEnumerable<Tuple<string, string, bool>> SourceDirectories()
        {
            yield return Tuple.Create("temporary/custom", Path.Combine(_fontRoot, "temporary", "custom"), true);
            yield return Tuple.Create("temporary/cache", Path.Combine(_fontRoot, "temporary", "cache"), false);
            yield return Tuple.Create("permanent/runtime", Path.Combine(_fontRoot, "permanent", "runtime"), false);
        }

        private static bool VerifyCandidate(string file, Asset asset, bool custom, out string integrity)
        {
            integrity = "missing";
            try
            {
                FileInfo info = new FileInfo(file);
                if (!info.Exists || info.Length < 4 || info.Length > MaxFontBytes) return false;
                byte[] bytes = File.ReadAllBytes(file);
                if (!HasFontMagic(bytes, asset.Format)) { integrity = "invalid-font"; return false; }
                if (custom) { integrity = "custom-override"; return true; }
                if (info.Length != asset.Bytes || !string.Equals(Sha256(bytes), asset.Sha256, StringComparison.Ordinal))
                {
                    integrity = "mismatch";
                    return false;
                }
                integrity = "verified";
                return true;
            }
            catch { return false; }
        }

        private static bool HasFontMagic(byte[] bytes, string format)
        {
            if (bytes == null || bytes.Length < 4) return false;
            string magic = Encoding.ASCII.GetString(bytes, 0, 4);
            if (string.Equals(format, "otf", StringComparison.Ordinal)) return magic == "OTTO";
            if (string.Equals(format, "woff", StringComparison.Ordinal)) return magic == "wOFF";
            if (string.Equals(format, "woff2", StringComparison.Ordinal)) return magic == "wOF2";
            if (string.Equals(format, "ttf", StringComparison.Ordinal))
                return (bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0)
                    || magic == "true" || magic == "typ1";
            return false;
        }

        internal static void RegisterWebResources(CoreWebView2 core, string owner)
        {
            if (core == null) return;
            core.AddWebResourceRequestedFilter("https://" + VirtualHost + "/*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += delegate(object sender, CoreWebView2WebResourceRequestedEventArgs args)
            {
                HandleWebResourceRequest(core, args, owner);
            };
            LogManager.Log("[FontCatalog] Web resource handler registered owner=" + owner);
        }

        private static void HandleWebResourceRequest(CoreWebView2 core, CoreWebView2WebResourceRequestedEventArgs args, string owner)
        {
            try
            {
                Uri uri;
                if (!Uri.TryCreate(args.Request.Uri, UriKind.Absolute, out uri)
                    || !string.Equals(uri.Scheme, "https", StringComparison.OrdinalIgnoreCase)
                    || !string.Equals(uri.Host, VirtualHost, StringComparison.OrdinalIgnoreCase)
                    || !string.Equals(args.Request.Method, "GET", StringComparison.OrdinalIgnoreCase))
                {
                    args.Response = Response(core, 400, "Bad Request", Array.Empty<byte>(), "text/plain");
                    return;
                }
                string escaped = uri.AbsolutePath.TrimStart('/');
                string file = Uri.UnescapeDataString(escaped);
                if (!IsSafeFontFileName(file))
                {
                    args.Response = Response(core, 404, "Not Found", Array.Empty<byte>(), "text/plain");
                    return;
                }
                Asset asset;
                ResolvedAsset resolved;
                lock (Sync)
                {
                    if (!_ready || !AssetsByFile.TryGetValue(file, out asset))
                    {
                        args.Response = Response(core, 404, "Not Found", Array.Empty<byte>(), "text/plain");
                        return;
                    }
                    resolved = ResolveAsset(asset);
                }
                if (resolved == null)
                {
                    args.Response = Response(core, 404, "Not Found", Array.Empty<byte>(), "text/plain");
                    return;
                }
                byte[] body = File.ReadAllBytes(resolved.Path);
                args.Response = Response(core, 200, "OK", body, MimeType(asset.Format));
                LogManager.Log("[FontCatalog] web font owner=" + owner + " file=" + file + " source=" + resolved.Source);
            }
            catch (Exception ex)
            {
                LogManager.Log("[FontCatalog] web request failed owner=" + owner + " ex=" + ex.Message);
                args.Response = Response(core, 500, "Internal Server Error", Array.Empty<byte>(), "text/plain");
            }
        }

        private static CoreWebView2WebResourceResponse Response(CoreWebView2 core, int status, string reason, byte[] body, string mime)
        {
            MemoryStream stream = new MemoryStream(body ?? Array.Empty<byte>(), false);
            string headers = "Content-Type: " + mime + "\r\n"
                + "Access-Control-Allow-Origin: *\r\n"
                + "Cross-Origin-Resource-Policy: cross-origin\r\n"
                + "Cache-Control: no-store\r\n";
            return core.Environment.CreateWebResourceResponse(stream, status, reason, headers);
        }

        private static string MimeType(string format)
        {
            if (format == "woff2") return "font/woff2";
            if (format == "woff") return "font/woff";
            if (format == "otf") return "font/otf";
            return "font/ttf";
        }

        private static Font TryCreateInstalled(string familyName, float size, FontStyle preferred, GraphicsUnit unit)
        {
            try
            {
                using (FontFamily family = new FontFamily(familyName))
                    return new Font(family, size, AvailableStyle(family, preferred), unit);
            }
            catch { return null; }
        }

        private static FontStyle AvailableStyle(FontFamily family, FontStyle preferred)
        {
            if (family.IsStyleAvailable(preferred)) return preferred;
            if (family.IsStyleAvailable(FontStyle.Regular)) return FontStyle.Regular;
            if (family.IsStyleAvailable(FontStyle.Bold)) return FontStyle.Bold;
            if (family.IsStyleAvailable(FontStyle.Italic)) return FontStyle.Italic;
            return FontStyle.Regular;
        }

        private static Font GenericFallback(float size, FontStyle preferred, GraphicsUnit unit, string generic)
        {
            FontFamily family = string.Equals(generic, "monospace", StringComparison.OrdinalIgnoreCase)
                ? FontFamily.GenericMonospace
                : string.Equals(generic, "sans-serif", StringComparison.OrdinalIgnoreCase)
                    ? FontFamily.GenericSansSerif
                    : FontFamily.GenericSerif;
            return new Font(family, size, AvailableStyle(family, preferred), unit);
        }

        private static bool IsSafeFontFileName(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > 128 || value != Path.GetFileName(value)) return false;
            if (value.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return false;
            string extension = Path.GetExtension(value);
            return extension.Equals(".ttf", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".otf", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".woff", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".woff2", StringComparison.OrdinalIgnoreCase);
        }

        private static string Sha256(byte[] bytes)
        {
            using (SHA256 hash = SHA256.Create())
            {
                StringBuilder builder = new StringBuilder(64);
                foreach (byte item in hash.ComputeHash(bytes)) builder.Append(item.ToString("x2"));
                return builder.ToString();
            }
        }

        private static bool IsSha256(string value)
        {
            return value != null && value.Length == 64 && value.All((character) =>
                (character >= '0' && character <= '9') || (character >= 'a' && character <= 'f'));
        }

        private static void ClearModels()
        {
            AssetsById.Clear();
            AssetsByFile.Clear();
            FacesById.Clear();
            RolesById.Clear();
            AllowedHosts.Clear();
            NativeSelections.Clear();
            NativeFamilies.Clear();
        }

        internal static ResolvedAsset ResolveFile(string file)
        {
            lock (Sync)
            {
                Asset asset;
                return _ready && AssetsByFile.TryGetValue(file, out asset) ? ResolveAsset(asset) : null;
            }
        }

        internal static bool IsAllowedDownloadHost(string host)
        {
            lock (Sync) return _ready && !string.IsNullOrWhiteSpace(host) && AllowedHosts.Contains(host);
        }

        internal static string ProjectionJsonForTest { get { lock (Sync) return _projectionJson; } }
        internal static string[] RoleIdsForTest { get { lock (Sync) return RolesById.Keys.OrderBy((item) => item, StringComparer.Ordinal).ToArray(); } }

        internal static void ConfigureForTest(string projectRoot)
        {
            ConfigureCore(projectRoot);
        }

        internal static ResolvedAsset NativeSelectionForTest(string faceId)
        {
            lock (Sync)
            {
                ResolvedAsset selected;
                return NativeSelections.TryGetValue(faceId, out selected) ? selected : null;
            }
        }

        internal static void ResetForTest()
        {
            lock (Sync)
            {
                foreach (PrivateFontCollection collection in PrivateCollections)
                    try { collection.Dispose(); } catch { }
                PrivateCollections.Clear();
                ClearModels();
                _configured = false;
                _ready = false;
                _projectRoot = null;
                _fontRoot = null;
                _projectionPath = null;
                _failure = null;
                _projectionJson = null;
            }
        }
    }
}
