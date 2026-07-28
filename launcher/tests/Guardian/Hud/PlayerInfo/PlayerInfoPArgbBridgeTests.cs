#nullable enable

using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoPArgbBridgeTests
{
    [Fact]
    public void Copy_PreservesRawPremultipliedBgraAndOwnsIndependentMemory()
    {
        using SKBitmap source = new(
            2,
            1,
            SKColorType.Bgra8888,
            SKAlphaType.Premul);
        byte[] expected =
        [
            25, 50, 100, 128,
            0, 0, 0, 0
        ];
        Marshal.Copy(expected, 0, source.GetPixels(), expected.Length);

        using Bitmap destination = PlayerInfoPArgbBridge.Copy(source);
        Assert.Equal(PixelFormat.Format32bppPArgb, destination.PixelFormat);
        Assert.Equal(expected, ReadRawRow(destination));

        byte[] replacement =
        [
            1, 2, 3, 4,
            5, 6, 7, 8
        ];
        Marshal.Copy(replacement, 0, source.GetPixels(), replacement.Length);
        Assert.Equal(expected, ReadRawRow(destination));
    }

    [Fact]
    public void Copy_RejectsUnpremultipliedSource()
    {
        using SKBitmap source = new(
            1,
            1,
            SKColorType.Bgra8888,
            SKAlphaType.Unpremul);

        InvalidDataException error = Assert.Throws<InvalidDataException>(
            () => PlayerInfoPArgbBridge.Copy(source));

        Assert.Contains("Bgra8888/Premul", error.Message);
    }

    [Fact]
    public void Copy_TransparentAndSemiTransparentPixelsRespectPArgbInvariant()
    {
        using SKBitmap source = new(
            3,
            1,
            SKColorType.Bgra8888,
            SKAlphaType.Premul);
        byte[] expected =
        [
            0, 0, 0, 0,
            32, 64, 96, 128,
            255, 128, 64, 255
        ];
        Marshal.Copy(expected, 0, source.GetPixels(), expected.Length);

        using Bitmap destination = PlayerInfoPArgbBridge.Copy(source);
        byte[] actual = ReadRawRow(destination);

        Assert.Equal(expected, actual);
        for (var offset = 0; offset < actual.Length; offset += 4)
        {
            byte alpha = actual[offset + 3];
            Assert.True(actual[offset] <= alpha);
            Assert.True(actual[offset + 1] <= alpha);
            Assert.True(actual[offset + 2] <= alpha);
            if (alpha == 0)
            {
                Assert.Equal(0, actual[offset]);
                Assert.Equal(0, actual[offset + 1]);
                Assert.Equal(0, actual[offset + 2]);
            }
        }
    }

    [Fact]
    public void Copy_PreservesDistinctRowsWithoutStrideBleed()
    {
        using SKBitmap source = new(
            2,
            2,
            SKColorType.Bgra8888,
            SKAlphaType.Premul);
        byte[] expected =
        [
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16
        ];
        for (var row = 0; row < source.Height; row++)
        {
            Marshal.Copy(
                expected,
                row * source.Width * 4,
                IntPtr.Add(source.GetPixels(), row * source.RowBytes),
                source.Width * 4);
        }

        using Bitmap destination = PlayerInfoPArgbBridge.Copy(source);

        Assert.Equal(expected, ReadRawPixels(destination));
    }

    private static byte[] ReadRawRow(Bitmap bitmap)
    {
        Assert.Equal(1, bitmap.Height);
        return ReadRawPixels(bitmap);
    }

    private static byte[] ReadRawPixels(Bitmap bitmap)
    {
        BitmapData? data = null;
        try
        {
            data = bitmap.LockBits(
                new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                ImageLockMode.ReadOnly,
                PixelFormat.Format32bppPArgb);
            var rowBytes = checked(bitmap.Width * 4);
            var bytes = new byte[checked(rowBytes * bitmap.Height)];
            for (var row = 0; row < bitmap.Height; row++)
            {
                Marshal.Copy(
                    IntPtr.Add(data.Scan0, checked(row * data.Stride)),
                    bytes,
                    row * rowBytes,
                    rowBytes);
            }
            return bytes;
        }
        finally
        {
            if (data is not null)
            {
                bitmap.UnlockBits(data);
            }
        }
    }
}
