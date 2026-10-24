#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>One-time small HUD glyph generation from the authored square item icon.</summary>
internal static class PlayerHudEquipmentOutline
{
    private const int Supersampling = 3;

    internal static Bitmap? Create(Bitmap source, int pixels)
    {
        pixels = Math.Clamp(pixels, 16, 256);
        using var normalized = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(normalized))
        {
            g.CompositingMode = CompositingMode.SourceCopy;
            g.Clear(Color.Transparent);
            g.DrawImageUnscaled(source, 0, 0);
        }
        var original = Read(normalized);
        var content = new Rectangle(0, 0, source.Width, source.Height);
        if (RemoveQualityFrame(original, source.Width, source.Height, out var interior))
        {
            content = interior;
        }
        RemoveSoftMatte(original, source.Width, source.Height);
        Write(normalized, original);
        var transparent = 0; var foreground = 0;
        for (var i = 0; i < original.Length; i += 4)
        {
            if (original[i + 3] < 16) transparent++;
            if (original[i + 3] >= 160) foreground++;
        }
        // Unseparated opaque artwork is not evidence of an item silhouette.
        if (foreground == 0 || transparent < Math.Max(1, source.Width * source.Height / 400)) return null;
        var size = Math.Clamp(pixels, 16, 256) * Supersampling;
        using var large = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(large))
        {
            g.CompositingMode = CompositingMode.SourceCopy;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            // Preserve the author's close-up, orientation and placement in the
            // square canvas. Only a verified quality frame changes this rectangle.
            var scale = (size - Supersampling * 5f) / Math.Max(content.Width, content.Height);
            var width = content.Width * scale; var height = content.Height * scale;
            g.DrawImage(normalized, new RectangleF((size - width) / 2, (size - height) / 2,
                width, height), content, GraphicsUnit.Pixel);
        }
        var raw = Read(large); var mask = new bool[size * size]; var count = 0;
        for (var i = 0; i < mask.Length; i++) { mask[i] = raw[i * 4 + 3] >= 160; if (mask[i]) count++; }
        if (count == 0) return null;
        var inside = Distance(mask, size, false); var outside = Distance(mask, size, true);
        var details = MaterialEdges(raw, mask, inside, size);
        var halfWidth = pixels / 24f * .55f * Supersampling;
        for (var i = 0; i < mask.Length; i++)
        {
            var distance = (mask[i] ? inside[i] : outside[i]) / 3f - .5f;
            var edge = Math.Clamp(halfWidth + .5f - distance, 0f, 1f);
            var alpha = (byte)Math.Round(Math.Max(Math.Max(edge * 238, details[i]), mask[i] ? 96 : 0));
            // White, already premultiplied. A faint interior keeps slender parts readable.
            raw[i * 4] = raw[i * 4 + 1] = raw[i * 4 + 2] = raw[i * 4 + 3] = alpha;
        }
        Write(large, raw);
        var result = new Bitmap(pixels, pixels, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(result))
        {
            g.CompositingMode = CompositingMode.SourceCopy;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            g.DrawImage(large, new Rectangle(0, 0, pixels, pixels));
        }
        return result;
    }

    private static bool RemoveQualityFrame(byte[] pixels, int width, int height, out Rectangle content)
    {
        content = new Rectangle(0, 0, width, height);
        if (width < 16 || height < 16 || pixels[3] < 240) return false;
        var frame = new[] { (int)pixels[0], pixels[1], pixels[2] };
        if (Math.Max(frame[0], Math.Max(frame[1], frame[2])) < 64) return false;
        bool IsFrame(int x, int y)
        {
            var i = (y * width + x) * 4;
            return pixels[i + 3] >= 240 && Math.Abs(pixels[i] - frame[0]) <= 8
                && Math.Abs(pixels[i + 1] - frame[1]) <= 8 && Math.Abs(pixels[i + 2] - frame[2]) <= 8;
        }
        bool Row(int y) { var same = 0; for (var x = 0; x < width; x++) if (IsFrame(x, y)) same++; return same >= width * .96; }
        bool Column(int x) { var same = 0; for (var y = 0; y < height; y++) if (IsFrame(x, y)) same++; return same >= height * .96; }
        var limit = Math.Min(width, height) / 8;
        var left = 0; var right = 0; var top = 0; var bottom = 0;
        while (left <= limit && Column(left)) left++;
        while (right <= limit && Column(width - 1 - right)) right++;
        while (top <= limit && Row(top)) top++;
        while (bottom <= limit && Row(height - 1 - bottom)) bottom++;
        if (left == 0 || right == 0 || top == 0 || bottom == 0 || Math.Max(Math.Max(left, right), Math.Max(top, bottom)) > limit) return false;
        // The baked quality border has a narrow antialiased transition. Keep
        // that transition out of the background probes and the item glyph.
        var inset = Math.Max(1, Math.Min(width, height) / 64);
        var interior = Rectangle.FromLTRB(left + inset, top + inset, width - right - inset, height - bottom - inset);
        var transparent = 0;
        for (var y = interior.Top; y < interior.Bottom; y++) for (var x = interior.Left; x < interior.Right; x++)
            if (pixels[(y * width + x) * 4 + 3] < 16) transparent++;
        var background = new bool[width * height];
        if (transparent < Math.Max(1, interior.Width * interior.Height / 400))
        {
            // Only remove an opaque UI background when both interior sides
            // agree on its row color. Arbitrary opaque art retains the fallback.
            var colors = new int[height * 3]; var valid = new bool[height]; var validRows = 0;
            for (var y = interior.Top; y < interior.Bottom; y++)
            {
                var a = (y * width + interior.Left) * 4; var b = (y * width + interior.Right - 1) * 4;
                var difference = 0;
                for (var c = 0; c < 3; c++)
                {
                    var low = Math.Min(Math.Min(pixels[a + c], pixels[a + 4 + c]), Math.Min(pixels[b + c], pixels[b - 4 + c]));
                    var high = Math.Max(Math.Max(pixels[a + c], pixels[a + 4 + c]), Math.Max(pixels[b + c], pixels[b - 4 + c]));
                    difference = Math.Max(difference, high - low);
                    colors[y * 3 + c] = (pixels[a + c] + pixels[a + 4 + c] + pixels[b + c] + pixels[b - 4 + c]) / 4;
                }
                if (difference <= 20) { valid[y] = true; validRows++; }
            }
            if (validRows < interior.Height * .9) return false;
            for (var y = interior.Top; y < interior.Bottom; y++) if (!valid[y])
            {
                var before = y - 1; var after = y + 1;
                while (before >= interior.Top && !valid[before]) before--;
                while (after < interior.Bottom && !valid[after]) after++;
                var nearest = before < interior.Top ? after : after >= interior.Bottom ? before
                    : y - before <= after - y ? before : after;
                for (var c = 0; c < 3; c++) colors[y * 3 + c] = colors[nearest * 3 + c];
            }
            var queue = new Queue<int>();
            void Visit(int x, int y)
            {
                if (!interior.Contains(x, y)) return;
                var i = y * width + x;
                if (background[i]) return;
                var difference = 0;
                for (var c = 0; c < 3; c++) difference = Math.Max(difference, Math.Abs(pixels[i * 4 + c] - colors[y * 3 + c]));
                if (difference > 22) return;
                background[i] = true; queue.Enqueue(i);
            }
            for (var x = interior.Left; x < interior.Right; x++) { Visit(x, interior.Top); Visit(x, interior.Bottom - 1); }
            for (var y = interior.Top; y < interior.Bottom; y++) { Visit(interior.Left, y); Visit(interior.Right - 1, y); }
            while (queue.TryDequeue(out var i))
            {
                var x = i % width; var y = i / width;
                Visit(x - 1, y); Visit(x + 1, y); Visit(x, y - 1); Visit(x, y + 1);
            }
            var removed = 0;
            for (var y = interior.Top; y < interior.Bottom; y++) for (var x = interior.Left; x < interior.Right; x++)
                if (background[y * width + x]) removed++;
            var area = interior.Width * interior.Height;
            if (removed < area / 20 || removed > area - Math.Max(4, area / 400)) return false;
        }
        for (var y = 0; y < height; y++) for (var x = 0; x < width; x++)
            if (!interior.Contains(x, y) || background[y * width + x])
            {
                var i = (y * width + x) * 4;
                pixels[i] = pixels[i + 1] = pixels[i + 2] = pixels[i + 3] = 0;
            }
        content = interior; return true;
    }

    private static void RemoveSoftMatte(byte[] pixels, int width, int height)
    {
        // Item f1 adds a strong translucent oval matte, often above 90% alpha.
        // Keep opaque artwork and its narrow antialiased neighborhood; a broad
        // translucent black/white matte is not evidence of item geometry.
        var solid = new bool[width * height];
        for (var i = 0; i < solid.Length; i++) solid[i] = pixels[i * 4 + 3] >= 254;
        for (var y = 0; y < height; y++) for (var x = 0; x < width; x++)
        {
            var i = y * width + x;
            if (pixels[i * 4 + 3] == 0 || solid[i]) continue;
            var near = false;
            for (var dy = -2; dy <= 2 && !near; dy++) for (var dx = -2; dx <= 2; dx++)
            {
                var px = x + dx; var py = y + dy;
                if (px >= 0 && px < width && py >= 0 && py < height && solid[py * width + px]) { near = true; break; }
            }
            if (!near) pixels[i * 4] = pixels[i * 4 + 1] = pixels[i * 4 + 2] = pixels[i * 4 + 3] = 0;
        }
    }

    private static byte[] MaterialEdges(byte[] pixels, bool[] mask, int[] inside, int size)
    {
        var magnitude = new int[mask.Length]; var horizontal = new bool[mask.Length];
        var result = new byte[mask.Length]; var step = Supersampling;
        for (var y = step; y < size - step; y++) for (var x = step; x < size - step; x++)
        {
            var i = y * size + x;
            if (!mask[i] || inside[i] < step * 3) continue;
            var dx = 0; var dy = 0;
            for (var channel = 0; channel < 3; channel++)
            {
                dx = Math.Max(dx, Math.Abs(pixels[(i + step) * 4 + channel] - pixels[(i - step) * 4 + channel]));
                dy = Math.Max(dy, Math.Abs(pixels[(i + size * step) * 4 + channel] - pixels[(i - size * step) * 4 + channel]));
            }
            magnitude[i] = Math.Max(dx, dy); horizontal[i] = dx >= dy;
        }
        for (var y = step; y < size - step; y++) for (var x = step; x < size - step; x++)
        {
            var i = y * size + x; var value = magnitude[i];
            var direction = horizontal[i] ? step : step * size;
            // Only strong, locally maximal material boundaries. No image noise,
            // decorative frame, or weak texture is promoted into internal linework.
            if (value >= 80 && value >= magnitude[i - direction] && value > magnitude[i + direction])
                result[i] = (byte)Math.Min(170, (value - 60) * 2);
        }
        return result;
    }

    private static int[] Distance(bool[] mask, int size, bool target)
    {
        var result = new int[mask.Length];
        for (var i = 0; i < result.Length; i++) result[i] = mask[i] == target ? 0 : 100000;
        // Chamfer distance gives smooth small strokes in linear work and bounded memory.
        for (var y = 0; y < size; y++) for (var x = 0; x < size; x++)
        {
            var i = y * size + x; var distance = result[i];
            if (x > 0) distance = Math.Min(distance, result[i - 1] + 3);
            if (y > 0)
            {
                distance = Math.Min(distance, result[i - size] + 3);
                if (x > 0) distance = Math.Min(distance, result[i - size - 1] + 4);
                if (x + 1 < size) distance = Math.Min(distance, result[i - size + 1] + 4);
            }
            result[i] = distance;
        }
        for (var y = size - 1; y >= 0; y--) for (var x = size - 1; x >= 0; x--)
        {
            var i = y * size + x; var distance = result[i];
            if (x + 1 < size) distance = Math.Min(distance, result[i + 1] + 3);
            if (y + 1 < size)
            {
                distance = Math.Min(distance, result[i + size] + 3);
                if (x > 0) distance = Math.Min(distance, result[i + size - 1] + 4);
                if (x + 1 < size) distance = Math.Min(distance, result[i + size + 1] + 4);
            }
            result[i] = distance;
        }
        return result;
    }

    private static byte[] Read(Bitmap bitmap)
    {
        var locked = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try
        {
            var result = new byte[bitmap.Width * bitmap.Height * 4];
            for (var y = 0; y < bitmap.Height; y++) Marshal.Copy(locked.Scan0 + y * locked.Stride, result, y * bitmap.Width * 4, bitmap.Width * 4);
            return result;
        }
        finally { bitmap.UnlockBits(locked); }
    }
    private static void Write(Bitmap bitmap, byte[] pixels)
    {
        var locked = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        try { for (var y = 0; y < bitmap.Height; y++) Marshal.Copy(pixels, y * bitmap.Width * 4, locked.Scan0 + y * locked.Stride, bitmap.Width * 4); }
        finally { bitmap.UnlockBits(locked); }
    }
}
