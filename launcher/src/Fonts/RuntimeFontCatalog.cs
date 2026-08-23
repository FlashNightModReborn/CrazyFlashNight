using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Text;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.Guardian;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;
using SkiaSharp;

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
            internal string ContentSha256;
            internal byte[] Bytes;
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
        private static readonly Dictionary<string, ResolvedAsset> ResolvedAssetsById =
            new Dictionary<string, ResolvedAsset>(StringComparer.Ordinal);
        private static readonly Dictionary<string, ResolvedAsset> NativeSelections =
            new Dictionary<string, ResolvedAsset>(StringComparer.Ordinal);
        private static readonly Dictionary<string, FontFamily> NativeFamilies =
            new Dictionary<string, FontFamily>(StringComparer.Ordinal);
        private static readonly List<PrivateFontCollection> PrivateCollections =
            new List<PrivateFontCollection>();
        private static readonly List<IntPtr> PrivateFontMemory =
            new List<IntPtr>();

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
            if (resolved == null || resolved.Bytes == null || resolved.Bytes.Length < 4) return null;
            PrivateFontCollection collection = null;
            IntPtr fontMemory = IntPtr.Zero;
            try
            {
                collection = new PrivateFontCollection();
                fontMemory = Marshal.AllocCoTaskMem(resolved.Bytes.Length);
                Marshal.Copy(resolved.Bytes, 0, fontMemory, resolved.Bytes.Length);
                collection.AddMemoryFont(fontMemory, resolved.Bytes.Length);
                FontFamily family = collection.Families.FirstOrDefault();
                if (family == null) throw new InvalidDataException("private collection contains no family");
                PrivateCollections.Add(collection);
                PrivateFontMemory.Add(fontMemory);
                fontMemory = IntPtr.Zero;
                NativeFamilies[faceId] = family;
                LogManager.Log("[FontCatalog] native face=" + faceId + " source=" + resolved.Source + " path=" + resolved.Path);
                return family;
            }
            catch (Exception ex)
            {
                if (collection != null) collection.Dispose();
                if (fontMemory != IntPtr.Zero) Marshal.FreeCoTaskMem(fontMemory);
                LogManager.Log("[FontCatalog] native load rejected face=" + faceId + " path=" + resolved.Path + " ex=" + ex.Message);
                return null;
            }
        }

        private static ResolvedAsset ResolveAsset(Asset asset)
        {
            ResolvedAsset cached;
            if (ResolvedAssetsById.TryGetValue(asset.Id, out cached)) return cached;

            ResolvedAsset resolved = ResolveAssetFresh(asset);
            if (resolved != null)
            {
                // Web and native consumers share a process-lifetime byte lease.
                // FontPack status intentionally bypasses this cache so a disk
                // integrity audit still observes replacement or corruption.
                ResolvedAssetsById.Add(asset.Id, resolved);
            }
            return resolved;
        }

        private static ResolvedAsset ResolveAssetFresh(Asset asset)
        {
            foreach (Tuple<string, string, bool> source in SourceDirectories())
            {
                string candidate = Path.Combine(source.Item2, asset.File);
                string integrity;
                byte[] verifiedBytes;
                if (VerifyCandidate(candidate, asset, source.Item3, out integrity, out verifiedBytes))
                {
                    ResolvedAsset resolved = new ResolvedAsset
                    {
                        AssetId = asset.Id,
                        File = asset.File,
                        Path = Path.GetFullPath(candidate),
                        Source = source.Item1,
                        Integrity = integrity,
                        ContentSha256 = string.Equals(integrity, "verified", StringComparison.Ordinal)
                            ? asset.Sha256
                            : Sha256(verifiedBytes),
                        Bytes = verifiedBytes,
                    };
                    return resolved;
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

        private static bool VerifyCandidate(
            string file,
            Asset asset,
            bool custom,
            out string integrity,
            out byte[] verifiedBytes)
        {
            integrity = "missing";
            verifiedBytes = null;
            try
            {
                FileInfo info = new FileInfo(file);
                if (!info.Exists || info.Length < 4 || info.Length > MaxFontBytes) return false;
                byte[] bytes = File.ReadAllBytes(file);
                if (bytes.Length < 4 || bytes.LongLength > MaxFontBytes) return false;
                if (!HasValidFontStructure(bytes, asset.Format)) { integrity = "invalid-font"; return false; }
                if (custom)
                {
                    // Custom files are intentionally not pinned to the catalog hash, so
                    // structure checks alone are not an integrity boundary. Ask the same
                    // production font parser used elsewhere by the launcher to decode the
                    // face before allowing an override to shadow cache/permanent sources.
                    // WOFF is expanded with strict bounds before the decoded SFNT is passed
                    // to Skia. SkiaSharp 3.119.4 cannot decode the project's valid WOFF2,
                    // so local WOFF2 overrides deliberately fail closed; hash-pinned
                    // cache/permanent WOFF2 remains WebView-served.
                    if (string.Equals(asset.Format, "woff2", StringComparison.Ordinal))
                    {
                        integrity = "unsupported-custom-font";
                        return false;
                    }
                    if (!CanUseCustomFont(bytes, asset.Format))
                    {
                        integrity = "invalid-font";
                        return false;
                    }
                    if ((string.Equals(asset.Format, "otf", StringComparison.Ordinal)
                            || string.Equals(asset.Format, "ttf", StringComparison.Ordinal))
                        && asset.Targets.Contains("native")
                        && !CanParseNativeFont(bytes))
                    {
                        integrity = "invalid-font";
                        return false;
                    }
                    integrity = "custom-override";
                    verifiedBytes = bytes;
                    return true;
                }
                if (bytes.LongLength != asset.Bytes || !string.Equals(Sha256(bytes), asset.Sha256, StringComparison.Ordinal))
                {
                    integrity = "mismatch";
                    return false;
                }
                integrity = "verified";
                verifiedBytes = bytes;
                return true;
            }
            catch { return false; }
        }

        private static bool HasValidFontStructure(byte[] bytes, string format)
        {
            if (!HasFontMagic(bytes, format)) return false;
            if (string.Equals(format, "otf", StringComparison.Ordinal)
                || string.Equals(format, "ttf", StringComparison.Ordinal))
                return HasValidSfntStructure(bytes);
            if (string.Equals(format, "woff", StringComparison.Ordinal))
                return HasValidWoffStructure(bytes);
            if (string.Equals(format, "woff2", StringComparison.Ordinal))
                return HasValidWoff2Structure(bytes);
            return false;
        }

        private static bool HasValidSfntStructure(byte[] bytes)
        {
            if (bytes == null || bytes.Length < 12) return false;
            int numTables = ReadUInt16BigEndian(bytes, 4);
            if (numTables < 1 || numTables > 4096
                || 12L + (16L * numTables) > bytes.Length) return false;
            for (int i = 0; i < numTables; i++)
            {
                int record = 12 + (16 * i);
                uint offset = ReadUInt32BigEndian(bytes, record + 8);
                uint length = ReadUInt32BigEndian(bytes, record + 12);
                if (!RangeFits(bytes, offset, length)) return false;
            }
            return true;
        }

        private static bool HasValidWoffStructure(byte[] bytes)
        {
            if (bytes == null || bytes.Length < 44
                || ReadUInt32BigEndian(bytes, 8) != (uint)bytes.Length
                || ReadUInt16BigEndian(bytes, 14) != 0) return false;
            int numTables = ReadUInt16BigEndian(bytes, 12);
            uint totalSfntSize = ReadUInt32BigEndian(bytes, 16);
            if (numTables < 1 || numTables > 4096
                || totalSfntSize < 12 || totalSfntSize > MaxFontBytes
                || 44L + (20L * numTables) > bytes.Length) return false;
            for (int i = 0; i < numTables; i++)
            {
                int record = 44 + (20 * i);
                uint offset = ReadUInt32BigEndian(bytes, record + 4);
                uint compressedLength = ReadUInt32BigEndian(bytes, record + 8);
                uint originalLength = ReadUInt32BigEndian(bytes, record + 12);
                if ((offset & 3U) != 0 || compressedLength == 0 || originalLength == 0
                    || compressedLength > originalLength
                    || !RangeFits(bytes, offset, compressedLength)) return false;
            }
            uint metaOffset = ReadUInt32BigEndian(bytes, 24);
            uint metaLength = ReadUInt32BigEndian(bytes, 28);
            uint metaOriginalLength = ReadUInt32BigEndian(bytes, 32);
            if (metaOffset == 0
                ? metaLength != 0 || metaOriginalLength != 0
                : metaLength == 0 || metaOriginalLength == 0 || !RangeFits(bytes, metaOffset, metaLength))
                return false;
            uint privateOffset = ReadUInt32BigEndian(bytes, 36);
            uint privateLength = ReadUInt32BigEndian(bytes, 40);
            return privateOffset == 0
                ? privateLength == 0
                : privateLength > 0 && RangeFits(bytes, privateOffset, privateLength);
        }

        private static bool HasValidWoff2Structure(byte[] bytes)
        {
            if (bytes == null || bytes.Length < 48
                || ReadUInt32BigEndian(bytes, 8) != (uint)bytes.Length
                || ReadUInt16BigEndian(bytes, 14) != 0) return false;
            int numTables = ReadUInt16BigEndian(bytes, 12);
            uint totalSfntSize = ReadUInt32BigEndian(bytes, 16);
            uint totalCompressedSize = ReadUInt32BigEndian(bytes, 20);
            long minimumDirectoryBytes = 2L * numTables;
            if (numTables < 1 || numTables > 4096
                || totalSfntSize < 12 || totalSfntSize > MaxFontBytes
                || totalCompressedSize == 0
                || 48L + minimumDirectoryBytes + totalCompressedSize > bytes.Length) return false;
            uint metaOffset = ReadUInt32BigEndian(bytes, 28);
            uint metaLength = ReadUInt32BigEndian(bytes, 32);
            uint metaOriginalLength = ReadUInt32BigEndian(bytes, 36);
            if (metaOffset == 0
                ? metaLength != 0 || metaOriginalLength != 0
                : metaLength == 0 || metaOriginalLength == 0 || !RangeFits(bytes, metaOffset, metaLength))
                return false;
            uint privateOffset = ReadUInt32BigEndian(bytes, 40);
            uint privateLength = ReadUInt32BigEndian(bytes, 44);
            return privateOffset == 0
                ? privateLength == 0
                : privateLength > 0 && RangeFits(bytes, privateOffset, privateLength);
        }

        private static bool CanParseFont(byte[] bytes, string format)
        {
            try
            {
                if (string.Equals(format, "woff", StringComparison.Ordinal))
                {
                    byte[] sfnt = DecodeWoffToSfnt(bytes);
                    if (sfnt == null) return false;
                    using (SKData data = SKData.CreateCopy(sfnt))
                    using (SKTypeface probe = SKTypeface.FromData(data, 0))
                        return probe != null && probe.GlyphCount > 0;
                }
                using (SKData data = SKData.CreateCopy(bytes))
                using (SKTypeface probe = SKTypeface.FromData(data, 0))
                    return probe != null && probe.GlyphCount > 0;
            }
            catch { return false; }
        }

        private static bool CanUseCustomFont(byte[] bytes, string format)
        {
            return !string.Equals(format, "woff2", StringComparison.Ordinal)
                && CanParseFont(bytes, format);
        }

        private static bool ValidatePackFormat(
            byte[] bytes,
            string format,
            bool nativeTarget,
            out string validationState)
        {
            validationState = "invalid-structure";
            if (bytes == null || !HasValidFontStructure(bytes, format)) return false;

            if (string.Equals(format, "woff2", StringComparison.Ordinal))
            {
                if (nativeTarget)
                {
                    validationState = "native-format-unsupported";
                    return false;
                }
                // The catalog hash pins exact WOFF2 bytes, but the current launcher has
                // no common WOFF2 decoder. Keep this web-only state explicit instead of
                // presenting a bounded container check as an actual parser success.
                validationState = "pinned-web-structure-only";
                return true;
            }

            if (!string.Equals(format, "ttf", StringComparison.Ordinal)
                && !string.Equals(format, "otf", StringComparison.Ordinal)
                && !string.Equals(format, "woff", StringComparison.Ordinal))
            {
                validationState = "format-unsupported";
                return false;
            }
            if (!CanParseFont(bytes, format))
            {
                validationState = "runtime-parser-rejected";
                return false;
            }
            if (nativeTarget)
            {
                // Native loading consumes raw SFNT bytes through AddMemoryFont. WOFF is
                // valid for Web after bounded SFNT reconstruction, but is not a native
                // pack format until that same decoded snapshot has a native lifecycle.
                if (!string.Equals(format, "ttf", StringComparison.Ordinal)
                    && !string.Equals(format, "otf", StringComparison.Ordinal))
                {
                    validationState = "native-format-unsupported";
                    return false;
                }
                if (!CanParseNativeFont(bytes))
                {
                    validationState = "native-parser-rejected";
                    return false;
                }
                validationState = "runtime-parser-native-verified";
                return true;
            }
            validationState = "runtime-parser-verified";
            return true;
        }

        private static byte[] DecodeWoffToSfnt(byte[] woff)
        {
            if (!HasValidWoffStructure(woff)) return null;
            int tableCount = ReadUInt16BigEndian(woff, 12);
            uint totalSizeValue = ReadUInt32BigEndian(woff, 16);
            if (totalSizeValue > int.MaxValue) return null;
            int totalSize = (int)totalSizeValue;
            int tableDataOffset = Align4(12 + (16 * tableCount));
            if (tableDataOffset > totalSize) return null;

            byte[] sfnt = new byte[totalSize];
            WriteUInt32BigEndian(sfnt, 0, ReadUInt32BigEndian(woff, 4));
            WriteUInt16BigEndian(sfnt, 4, tableCount);
            int maxPowerOfTwo = 1;
            int entrySelector = 0;
            while ((maxPowerOfTwo << 1) <= tableCount)
            {
                maxPowerOfTwo <<= 1;
                entrySelector++;
            }
            int searchRange = maxPowerOfTwo * 16;
            WriteUInt16BigEndian(sfnt, 6, searchRange);
            WriteUInt16BigEndian(sfnt, 8, entrySelector);
            WriteUInt16BigEndian(sfnt, 10, (tableCount * 16) - searchRange);

            int outputOffset = tableDataOffset;
            for (int index = 0; index < tableCount; index++)
            {
                int woffRecord = 44 + (20 * index);
                uint compressedOffsetValue = ReadUInt32BigEndian(woff, woffRecord + 4);
                uint compressedLengthValue = ReadUInt32BigEndian(woff, woffRecord + 8);
                uint originalLengthValue = ReadUInt32BigEndian(woff, woffRecord + 12);
                if (compressedOffsetValue > int.MaxValue
                    || compressedLengthValue > int.MaxValue
                    || originalLengthValue > int.MaxValue) return null;
                int compressedOffset = (int)compressedOffsetValue;
                int compressedLength = (int)compressedLengthValue;
                int originalLength = (int)originalLengthValue;
                if (outputOffset > totalSize || originalLength > totalSize - outputOffset) return null;

                byte[] table = new byte[originalLength];
                if (compressedLength == originalLength)
                {
                    Buffer.BlockCopy(woff, compressedOffset, table, 0, originalLength);
                }
                else
                {
                    using (var source = new MemoryStream(
                        woff, compressedOffset, compressedLength, false))
                    using (var zlib = new ZLibStream(source, CompressionMode.Decompress, false))
                    {
                        int readTotal = 0;
                        while (readTotal < table.Length)
                        {
                            int read = zlib.Read(table, readTotal, table.Length - readTotal);
                            if (read == 0) break;
                            readTotal += read;
                        }
                        if (readTotal != table.Length || zlib.ReadByte() != -1) return null;
                    }
                }

                int sfntRecord = 12 + (16 * index);
                Buffer.BlockCopy(woff, woffRecord, sfnt, sfntRecord, 4);
                WriteUInt32BigEndian(sfnt, sfntRecord + 4,
                    ReadUInt32BigEndian(woff, woffRecord + 16));
                WriteUInt32BigEndian(sfnt, sfntRecord + 8, (uint)outputOffset);
                WriteUInt32BigEndian(sfnt, sfntRecord + 12, originalLengthValue);
                Buffer.BlockCopy(table, 0, sfnt, outputOffset, originalLength);
                outputOffset = Align4(outputOffset + originalLength);
            }
            return outputOffset == totalSize ? sfnt : null;
        }

        private static bool CanParseNativeFont(byte[] bytes)
        {
            IntPtr fontMemory = IntPtr.Zero;
            try
            {
                if (bytes == null || bytes.Length < 4) return false;
                fontMemory = Marshal.AllocCoTaskMem(bytes.Length);
                Marshal.Copy(bytes, 0, fontMemory, bytes.Length);
                using (PrivateFontCollection probe = new PrivateFontCollection())
                {
                    probe.AddMemoryFont(fontMemory, bytes.Length);
                    return probe.Families.Length > 0;
                }
            }
            catch { return false; }
            finally
            {
                if (fontMemory != IntPtr.Zero) Marshal.FreeCoTaskMem(fontMemory);
            }
        }

        private static int ReadUInt16BigEndian(byte[] bytes, int offset)
        {
            return (bytes[offset] << 8) | bytes[offset + 1];
        }

        private static uint ReadUInt32BigEndian(byte[] bytes, int offset)
        {
            return ((uint)bytes[offset] << 24)
                | ((uint)bytes[offset + 1] << 16)
                | ((uint)bytes[offset + 2] << 8)
                | bytes[offset + 3];
        }

        private static bool RangeFits(byte[] bytes, uint offset, uint length)
        {
            return bytes != null && offset <= (uint)bytes.Length
                && length <= (uint)bytes.Length - offset;
        }

        private static int Align4(int value)
        {
            return (value + 3) & ~3;
        }

        private static void WriteUInt16BigEndian(byte[] bytes, int offset, int value)
        {
            bytes[offset] = (byte)(value >> 8);
            bytes[offset + 1] = (byte)value;
        }

        private static void WriteUInt32BigEndian(byte[] bytes, int offset, uint value)
        {
            bytes[offset] = (byte)(value >> 24);
            bytes[offset + 1] = (byte)(value >> 16);
            bytes[offset + 2] = (byte)(value >> 8);
            bytes[offset + 3] = (byte)value;
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
                    args.Response = Response(core, 400, "Bad Request", Array.Empty<byte>(), "text/plain", null);
                    return;
                }
                string escaped = uri.AbsolutePath.TrimStart('/');
                string file = Uri.UnescapeDataString(escaped);
                if (!IsSafeFontFileName(file))
                {
                    args.Response = Response(core, 404, "Not Found", Array.Empty<byte>(), "text/plain", null);
                    return;
                }
                Asset asset;
                ResolvedAsset resolved;
                lock (Sync)
                {
                    if (!_ready || !AssetsByFile.TryGetValue(file, out asset))
                    {
                        args.Response = Response(core, 404, "Not Found", Array.Empty<byte>(), "text/plain", null);
                        return;
                    }
                    resolved = ResolveAsset(asset);
                }
                if (resolved == null)
                {
                    args.Response = Response(core, 404, "Not Found", Array.Empty<byte>(), "text/plain", null);
                    return;
                }
                string entityTag = EntityTag(resolved.ContentSha256);
                string ifNoneMatch = null;
                try { ifNoneMatch = args.Request.Headers.GetHeader("If-None-Match"); }
                catch { }
                if (MatchesIfNoneMatch(ifNoneMatch, entityTag))
                {
                    args.Response = Response(
                        core, 304, "Not Modified", Array.Empty<byte>(), MimeType(asset.Format), entityTag);
                    return;
                }
                args.Response = Response(core, 200, "OK", resolved.Bytes, MimeType(asset.Format), entityTag);
                LogManager.Log("[FontCatalog] web font owner=" + owner + " file=" + file + " source=" + resolved.Source);
            }
            catch (Exception ex)
            {
                LogManager.Log("[FontCatalog] web request failed owner=" + owner + " ex=" + ex.Message);
                args.Response = Response(core, 500, "Internal Server Error", Array.Empty<byte>(), "text/plain", null);
            }
        }

        private static CoreWebView2WebResourceResponse Response(
            CoreWebView2 core,
            int status,
            string reason,
            byte[] body,
            string mime,
            string entityTag)
        {
            MemoryStream stream = new MemoryStream(body ?? Array.Empty<byte>(), false);
            string headers = ResponseHeaders(mime, entityTag);
            return core.Environment.CreateWebResourceResponse(stream, status, reason, headers);
        }

        private static string ResponseHeaders(string mime, string entityTag)
        {
            return "Content-Type: " + mime + "\r\n"
                + "Access-Control-Allow-Origin: *\r\n"
                + "Cross-Origin-Resource-Policy: cross-origin\r\n"
                + (string.IsNullOrEmpty(entityTag)
                    ? "Cache-Control: no-store\r\n"
                    : "Cache-Control: private, max-age=0, must-revalidate\r\n"
                        + "ETag: " + entityTag + "\r\n");
        }

        private static string EntityTag(string contentSha256)
        {
            return string.IsNullOrEmpty(contentSha256)
                ? null
                : "\"sha256-" + contentSha256 + "\"";
        }

        private static bool MatchesIfNoneMatch(string value, string entityTag)
        {
            if (string.IsNullOrWhiteSpace(value) || string.IsNullOrEmpty(entityTag)) return false;
            foreach (string item in value.Split(','))
            {
                string candidate = item.Trim();
                if (candidate == "*" || string.Equals(candidate, entityTag, StringComparison.Ordinal)
                    || string.Equals(candidate, "W/" + entityTag, StringComparison.Ordinal))
                    return true;
            }
            return false;
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
            ResolvedAssetsById.Clear();
            NativeSelections.Clear();
            NativeFamilies.Clear();
        }

        internal static ResolvedAsset ResolveFile(string file)
        {
            lock (Sync)
            {
                Asset asset;
                return _ready && AssetsByFile.TryGetValue(file, out asset) ? ResolveAssetFresh(asset) : null;
            }
        }

        internal static ResolvedAsset ResolveWebFileForTest(string file)
        {
            lock (Sync)
            {
                Asset asset;
                return _ready && AssetsByFile.TryGetValue(file, out asset) ? ResolveAsset(asset) : null;
            }
        }

        internal static int ResolvedAssetCountForTest
        {
            get { lock (Sync) return ResolvedAssetsById.Count; }
        }

        internal static string WebResponseHeadersForTest(ResolvedAsset resolved)
        {
            return ResponseHeaders("font/woff2", EntityTag(resolved == null ? null : resolved.ContentSha256));
        }

        internal static bool MatchesIfNoneMatchForTest(string value, ResolvedAsset resolved)
        {
            return MatchesIfNoneMatch(value, EntityTag(resolved == null ? null : resolved.ContentSha256));
        }

        internal static bool ValidatePackCandidate(
            string file,
            byte[] verifiedBytes,
            out string validationState)
        {
            string format;
            bool nativeTarget;
            long expectedBytes;
            string expectedSha256;
            lock (Sync)
            {
                Asset asset;
                if (!_ready)
                {
                    validationState = "catalog-unavailable";
                    return false;
                }
                if (string.IsNullOrEmpty(file) || !AssetsByFile.TryGetValue(file, out asset))
                {
                    validationState = "unknown-asset";
                    return false;
                }
                format = asset.Format;
                nativeTarget = asset.Targets.Contains("native");
                expectedBytes = asset.Bytes;
                expectedSha256 = asset.Sha256;
            }

            if (verifiedBytes == null || verifiedBytes.LongLength != expectedBytes
                || !string.Equals(Sha256(verifiedBytes), expectedSha256, StringComparison.Ordinal))
            {
                validationState = "catalog-integrity-mismatch";
                return false;
            }
            return ValidatePackFormat(verifiedBytes, format, nativeTarget, out validationState);
        }

        internal static bool IsAllowedDownloadHost(string host)
        {
            lock (Sync) return _ready && !string.IsNullOrWhiteSpace(host) && AllowedHosts.Contains(host);
        }

        internal static string ProjectionJsonForTest { get { lock (Sync) return _projectionJson; } }
        internal static string[] RoleIdsForTest { get { lock (Sync) return RolesById.Keys.OrderBy((item) => item, StringComparer.Ordinal).ToArray(); } }

        internal static bool IsValidCustomFontForTest(string file, string format)
        {
            try
            {
                byte[] bytes = File.ReadAllBytes(file);
                return HasValidFontStructure(bytes, format)
                    && CanUseCustomFont(bytes, format);
            }
            catch { return false; }
        }

        internal static bool HasValidFontStructureForTest(string file, string format)
        {
            try { return HasValidFontStructure(File.ReadAllBytes(file), format); }
            catch { return false; }
        }

        internal static bool CanParseFontForTest(string file, string format)
        {
            try { return CanParseFont(File.ReadAllBytes(file), format); }
            catch { return false; }
        }

        internal static bool ValidatePackFormatForTest(
            byte[] bytes,
            string format,
            bool nativeTarget,
            out string validationState)
        {
            try { return ValidatePackFormat(bytes, format, nativeTarget, out validationState); }
            catch
            {
                validationState = "probe-exception";
                return false;
            }
        }

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
                foreach (IntPtr memory in PrivateFontMemory)
                    try { Marshal.FreeCoTaskMem(memory); } catch { }
                PrivateFontMemory.Clear();
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
