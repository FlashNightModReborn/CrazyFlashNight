#nullable enable

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
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
                using var qualified = StrictSvgFacade.Load(layerPlan.Asset.Bytes);
                progress.RecordParse();
                cancellationToken.ThrowIfCancellationRequested();
                using var skBitmap = qualified.Rasterize(
                    layerPlan.PixelWidth,
                    layerPlan.PixelHeight,
                    layerPlan.SourceViewBox);
                progress.RecordRaster();
                cancellationToken.ThrowIfCancellationRequested();

                Bitmap? bitmap = null;
                try
                {
                    bitmap = PlayerInfoPArgbBridge.Copy(skBitmap);
                    cancellationToken.ThrowIfCancellationRequested();
                    layers.Add(new PlayerInfoRasterLayer(
                        layerPlan.Key,
                        bitmap));
                    bitmap = null;
                }
                finally
                {
                    bitmap?.Dispose();
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
}

internal sealed class PlayerInfoRasterLayer(
    PlayerInfoRasterKey key,
    Bitmap bitmap) : IDisposable
{
    private Bitmap? _bitmap = bitmap ?? throw new ArgumentNullException(nameof(bitmap));

    internal PlayerInfoRasterKey Key { get; } = key;
    internal Bitmap Bitmap =>
        Volatile.Read(ref _bitmap) ??
        throw new ObjectDisposedException(nameof(PlayerInfoRasterLayer));
    internal long ByteSize { get; } = checked(
        (long)key.PixelWidth * key.PixelHeight * 4L);
    internal bool IsDisposed => Volatile.Read(ref _bitmap) is null;

    public void Dispose()
    {
        Interlocked.Exchange(ref _bitmap, null)?.Dispose();
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
