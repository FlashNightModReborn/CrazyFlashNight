#nullable enable

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Xml;
using System.Xml.Linq;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal interface IPlayerInfoRasterizer
{
    PlayerInfoRasterBatch Bake(
        PlayerInfoRasterPlan plan,
        CancellationToken cancellationToken,
        PlayerInfoRasterProgress progress);
}

internal sealed class PlayerInfoRasterProgress
{
    private int _parseCount;
    private int _rasterCount;

    internal int ParseCount => Volatile.Read(ref _parseCount);
    internal int RasterCount => Volatile.Read(ref _rasterCount);
    internal void RecordParse() => Interlocked.Increment(ref _parseCount);
    internal void RecordRaster() => Interlocked.Increment(ref _rasterCount);
}

internal sealed class PlayerInfoSvgRasterizer : IPlayerInfoRasterizer
{
    internal PlayerInfoRasterBatch Bake(
        PlayerInfoRasterPlan plan,
        CancellationToken cancellationToken) =>
        Bake(plan, cancellationToken, new PlayerInfoRasterProgress());

    public PlayerInfoRasterBatch Bake(
        PlayerInfoRasterPlan plan,
        CancellationToken cancellationToken,
        PlayerInfoRasterProgress progress)
    {
        ArgumentNullException.ThrowIfNull(plan);
        ArgumentNullException.ThrowIfNull(progress);
        var layers = new List<PlayerInfoRasterLayer>(plan.Layers.Count);
        try
        {
            foreach (var layerPlan in plan.Layers)
            {
                cancellationToken.ThrowIfCancellationRequested();
                Bitmap? bitmap = null;
                Dictionary<string, Bitmap>? fragments = null;
                try
                {
                    bitmap = BakeBitmap(
                        layerPlan.Asset.Bytes,
                        layerPlan,
                        cancellationToken,
                        progress);
                    if (string.Equals(
                            layerPlan.Key.LayerId,
                            "mp.fill",
                            StringComparison.Ordinal))
                    {
                        fragments = new Dictionary<string, Bitmap>(
                            StringComparer.Ordinal);
                        var fragmentBytes =
                            PlayerInfoSvgGroupFragmenter.Create(
                                layerPlan.Asset.Bytes,
                                layerPlan.Gauge.ClipBindings);
                        foreach (var binding in layerPlan.Gauge.ClipBindings)
                        {
                            cancellationToken.ThrowIfCancellationRequested();
                            fragments.Add(
                                binding.Id,
                                BakeBitmap(
                                    fragmentBytes[binding.Id],
                                    layerPlan,
                                    cancellationToken,
                                    progress));
                        }
                    }
                    cancellationToken.ThrowIfCancellationRequested();
                    layers.Add(new PlayerInfoRasterLayer(
                        layerPlan.Key,
                        bitmap,
                        fragments));
                    bitmap = null;
                    fragments = null;
                }
                finally
                {
                    bitmap?.Dispose();
                    if (fragments is not null)
                    {
                        foreach (var fragment in fragments.Values)
                        {
                            fragment.Dispose();
                        }
                    }
                }
            }

            cancellationToken.ThrowIfCancellationRequested();
            var batch = new PlayerInfoRasterBatch(plan.BatchKey, layers);
            layers.Clear();
            return batch;
        }
        catch
        {
            foreach (var layer in layers)
            {
                layer.Dispose();
            }
            throw;
        }
    }

    private static Bitmap BakeBitmap(
        ReadOnlyMemory<byte> svgBytes,
        PlayerInfoRasterLayerPlan layerPlan,
        CancellationToken cancellationToken,
        PlayerInfoRasterProgress progress)
    {
        using var qualified = StrictSvgFacade.Load(svgBytes);
        progress.RecordParse();
        cancellationToken.ThrowIfCancellationRequested();
        using var skBitmap = qualified.Rasterize(
            layerPlan.PixelWidth,
            layerPlan.PixelHeight,
            layerPlan.SourceViewBox);
        progress.RecordRaster();
        cancellationToken.ThrowIfCancellationRequested();
        var bitmap = PlayerInfoPArgbBridge.Copy(skBitmap);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            return bitmap;
        }
        catch
        {
            bitmap.Dispose();
            throw;
        }
    }
}

internal static class PlayerInfoSvgGroupFragmenter
{
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly XNamespace SvgNamespace =
        "http://www.w3.org/2000/svg";

    internal static IReadOnlyDictionary<string, ReadOnlyMemory<byte>> Create(
        ReadOnlyMemory<byte> canonicalBytes,
        IReadOnlyList<PlayerInfoClipBinding> bindings)
    {
        ArgumentNullException.ThrowIfNull(bindings);
        if (bindings.Count != 2)
        {
            throw new InvalidDataException(
                "MP fill fragmentation requires exactly two clip bindings.");
        }

        var canonical = LoadValidatedDocument(canonicalBytes);
        var fillRoot = FindFillRoot(canonical);
        var directGroups = fillRoot
            .Elements(SvgNamespace + "g")
            .ToArray();
        if (directGroups.Length == 0 ||
            fillRoot.Elements().Count() != directGroups.Length)
        {
            throw new InvalidDataException(
                "Canonical MP fill root must contain only direct named groups.");
        }

        var directIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var group in directGroups)
        {
            var id = (string?)group.Attribute("id");
            if (string.IsNullOrEmpty(id) || !directIds.Add(id))
            {
                throw new InvalidDataException(
                    "Canonical MP fill direct groups must have unique IDs.");
            }
        }

        var boundIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var binding in bindings)
        {
            if (string.IsNullOrEmpty(binding.Id) ||
                binding.SvgGroupIds.Count == 0)
            {
                throw new InvalidDataException(
                    "MP fill clip binding is empty.");
            }
            foreach (var groupId in binding.SvgGroupIds)
            {
                if (!boundIds.Add(groupId))
                {
                    throw new InvalidDataException(
                        $"MP fill group '{groupId}' is bound more than once.");
                }
            }
        }
        if (!directIds.SetEquals(boundIds))
        {
            throw new InvalidDataException(
                "MP fill clip bindings do not partition every direct group.");
        }

        var result =
            new Dictionary<string, ReadOnlyMemory<byte>>(StringComparer.Ordinal);
        foreach (var binding in bindings)
        {
            var fragment = new XDocument(canonical);
            var fragmentRoot = FindFillRoot(fragment);
            var keep = binding.SvgGroupIds.ToHashSet(StringComparer.Ordinal);
            foreach (var group in fragmentRoot
                         .Elements(SvgNamespace + "g")
                         .ToArray())
            {
                var id = (string?)group.Attribute("id") ??
                    throw new InvalidDataException(
                        "Canonical MP fill direct group lost its ID.");
                if (!keep.Contains(id))
                {
                    group.Remove();
                }
            }
            var bytes = StrictUtf8.GetBytes(
                fragment.ToString(SaveOptions.DisableFormatting));
            StrictSvgValidator.Validate(bytes);
            if (!result.TryAdd(binding.Id, bytes))
            {
                throw new InvalidDataException(
                    $"MP fill clip binding '{binding.Id}' is duplicated.");
            }
        }
        return result;
    }

    private static XDocument LoadValidatedDocument(
        ReadOnlyMemory<byte> canonicalBytes)
    {
        StrictSvgValidator.Validate(canonicalBytes);
        var xml = StrictUtf8.GetString(canonicalBytes.Span);
        using var text = new StringReader(xml);
        using var reader = XmlReader.Create(text, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            MaxCharactersInDocument = StrictSvgValidator.MaxBytes,
            MaxCharactersFromEntities = 0
        });
        return XDocument.Load(
            reader,
            LoadOptions.PreserveWhitespace | LoadOptions.SetLineInfo);
    }

    private static XElement FindFillRoot(XDocument document)
    {
        var roots = document
            .Descendants(SvgNamespace + "g")
            .Where(element => string.Equals(
                (string?)element.Attribute("id"),
                "mp-fill",
                StringComparison.Ordinal))
            .ToArray();
        if (roots.Length != 1)
        {
            throw new InvalidDataException(
                "Canonical MP fill must contain exactly one mp-fill group.");
        }
        return roots[0];
    }
}

internal sealed class PlayerInfoRasterLayer : IDisposable
{
    private sealed class OwnedPayload(
        Bitmap bitmap,
        IReadOnlyDictionary<string, Bitmap> fragments)
    {
        internal Bitmap Bitmap { get; } = bitmap;
        internal IReadOnlyDictionary<string, Bitmap> Fragments { get; } =
            fragments;
    }

    private OwnedPayload? _payload;

    internal PlayerInfoRasterLayer(
        PlayerInfoRasterKey key,
        Bitmap bitmap)
        : this(key, bitmap, null)
    {
    }

    internal PlayerInfoRasterLayer(
        PlayerInfoRasterKey key,
        Bitmap bitmap,
        IReadOnlyDictionary<string, Bitmap>? fragments)
    {
        ArgumentNullException.ThrowIfNull(bitmap);
        var ownedFragments = fragments is null
            ? new Dictionary<string, Bitmap>(StringComparer.Ordinal)
            : new Dictionary<string, Bitmap>(
                fragments,
                StringComparer.Ordinal);
        var fragmentReferences = new HashSet<Bitmap>(
            ReferenceEqualityComparer.Instance);
        if (ownedFragments.Any(entry =>
                string.IsNullOrEmpty(entry.Key) ||
                entry.Value is null ||
                ReferenceEquals(entry.Value, bitmap) ||
                !fragmentReferences.Add(entry.Value)))
        {
            throw new ArgumentException(
                "PlayerInfo raster fragments must have unique IDs and distinct bitmaps.",
                nameof(fragments));
        }
        if (bitmap.Width != key.PixelWidth ||
            bitmap.Height != key.PixelHeight ||
            bitmap.PixelFormat != PixelFormat.Format32bppPArgb ||
            ownedFragments.Values.Any(fragment =>
                fragment.Width != key.PixelWidth ||
                fragment.Height != key.PixelHeight ||
                fragment.PixelFormat != PixelFormat.Format32bppPArgb))
        {
            throw new ArgumentException(
                "PlayerInfo raster layer payload does not match its PArgb key.",
                nameof(bitmap));
        }

        Key = key;
        ByteSize = checked(
            (long)key.PixelWidth *
            key.PixelHeight *
            4L *
            (1L + ownedFragments.Count));
        _payload = new OwnedPayload(bitmap, ownedFragments);
    }

    internal PlayerInfoRasterKey Key { get; }
    internal Bitmap Bitmap =>
        Volatile.Read(ref _payload)?.Bitmap ??
        throw new ObjectDisposedException(nameof(PlayerInfoRasterLayer));
    internal IEnumerable<string> FragmentIds =>
        Volatile.Read(ref _payload)?.Fragments.Keys ??
        throw new ObjectDisposedException(nameof(PlayerInfoRasterLayer));
    internal long ByteSize { get; }
    internal bool IsDisposed => Volatile.Read(ref _payload) is null;

    internal Bitmap RequireFragment(string fragmentId)
    {
        if (string.IsNullOrEmpty(fragmentId))
        {
            throw new ArgumentException(
                "Fragment ID is required.",
                nameof(fragmentId));
        }
        var payload = Volatile.Read(ref _payload) ??
            throw new ObjectDisposedException(nameof(PlayerInfoRasterLayer));
        if (!payload.Fragments.TryGetValue(fragmentId, out var fragment))
        {
            throw new InvalidDataException(
                $"PlayerInfo layer '{Key.LayerId}' lacks fragment '{fragmentId}'.");
        }
        return fragment;
    }

    public void Dispose()
    {
        var payload = Interlocked.Exchange(ref _payload, null);
        if (payload is null)
        {
            return;
        }
        payload.Bitmap.Dispose();
        foreach (var fragment in payload.Fragments.Values)
        {
            fragment.Dispose();
        }
    }
}

internal sealed class PlayerInfoRasterBatch : IDisposable
{
    private PlayerInfoRasterLayer[]? _layers;

    internal PlayerInfoRasterBatch(
        string batchKey,
        IEnumerable<PlayerInfoRasterLayer> layers)
    {
        if (string.IsNullOrEmpty(batchKey))
        {
            throw new ArgumentException("Batch key is required.", nameof(batchKey));
        }
        var materialized = layers?.ToArray() ??
            throw new ArgumentNullException(nameof(layers));
        if (materialized.Length != PlayerInfoSvgAssetCatalog.ExpectedAssetCount ||
            materialized.Select(layer => layer.Key.LayerId)
                .Distinct(StringComparer.Ordinal)
                .Count() != PlayerInfoSvgAssetCatalog.ExpectedAssetCount)
        {
            throw new ArgumentException(
                $"A PlayerInfo raster batch must own exactly {PlayerInfoSvgAssetCatalog.ExpectedAssetCount} unique layers.",
                nameof(layers));
        }
        if (materialized.Any(layer =>
                layer.Bitmap.Width != layer.Key.PixelWidth ||
                layer.Bitmap.Height != layer.Key.PixelHeight ||
                layer.Bitmap.PixelFormat != PixelFormat.Format32bppPArgb))
        {
            throw new ArgumentException(
                "PlayerInfo raster layer bitmap does not match its PArgb key contract.",
                nameof(layers));
        }

        BatchKey = batchKey;
        ByteSize = materialized.Aggregate(
            0L,
            (total, layer) => checked(total + layer.ByteSize));
        _layers = materialized;
    }

    internal string BatchKey { get; }
    internal long ByteSize { get; }
    internal IReadOnlyList<PlayerInfoRasterLayer> Layers =>
        Volatile.Read(ref _layers) ??
        throw new ObjectDisposedException(nameof(PlayerInfoRasterBatch));
    internal bool IsDisposed => Volatile.Read(ref _layers) is null;

    public void Dispose()
    {
        DisposeOwnedLayers();
    }

    internal int DisposeOwnedLayers()
    {
        var layers = Interlocked.Exchange(ref _layers, null);
        if (layers is null)
        {
            return 0;
        }
        foreach (var layer in layers)
        {
            layer.Dispose();
        }
        return layers.Length;
    }
}

internal static class PlayerInfoPArgbBridge
{
    internal static Bitmap Copy(SKBitmap source)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (source.Width <= 0 ||
            source.Height <= 0 ||
            source.ColorType != SKColorType.Bgra8888 ||
            source.AlphaType != SKAlphaType.Premul ||
            source.GetPixels() == IntPtr.Zero)
        {
            throw new InvalidDataException(
                "PlayerInfo raster source must be non-empty Bgra8888/Premul.");
        }

        var rowBytes = checked(source.Width * 4);
        if (source.RowBytes < rowBytes)
        {
            throw new InvalidDataException(
                "PlayerInfo raster source stride is shorter than one BGRA row.");
        }

        var destination = new Bitmap(
            source.Width,
            source.Height,
            PixelFormat.Format32bppPArgb);
        try
        {
            BitmapData? locked = null;
            try
            {
                locked = destination.LockBits(
                    new Rectangle(0, 0, destination.Width, destination.Height),
                    ImageLockMode.WriteOnly,
                    PixelFormat.Format32bppPArgb);
                if (locked.Scan0 == IntPtr.Zero ||
                    Math.Abs((long)locked.Stride) < rowBytes)
                {
                    throw new InvalidDataException(
                        "PlayerInfo PArgb destination stride is shorter than one BGRA row.");
                }

                var row = new byte[rowBytes];
                for (var y = 0; y < source.Height; y++)
                {
                    var sourceRow = IntPtr.Add(
                        source.GetPixels(),
                        checked(y * source.RowBytes));
                    var destinationRow = IntPtr.Add(
                        locked.Scan0,
                        checked(y * locked.Stride));
                    Marshal.Copy(sourceRow, row, 0, rowBytes);
                    Marshal.Copy(row, 0, destinationRow, rowBytes);
                }
            }
            finally
            {
                if (locked is not null)
                {
                    destination.UnlockBits(locked);
                }
            }
            return destination;
        }
        catch
        {
            destination.Dispose();
            throw;
        }
    }
}
