using System;
using System.Globalization;

namespace CF7Launcher.Guardian.WorldCompositor;

internal static class BulletVisualWireQ1
{
    internal static bool TryParse(string payload, int styleCount, out BulletVisualFrame frame)
    {
        frame = null;
        if (string.IsNullOrEmpty(payload) || payload.Length > 4 * 1024 * 1024 || styleCount is < 1 or > 16) return false;
        int first = payload.IndexOf(';');
        ReadOnlySpan<char> header = first < 0 ? payload.AsSpan() : payload.AsSpan(0, first);
        if (!Token(ref header, '|', out var magic) || !magic.SequenceEqual("Q1".AsSpan())
            || !Integer(ref header, '|', 1, int.MaxValue, out int offer)
            || !Integer(ref header, '|', 1, int.MaxValue, out int epoch)
            || !Integer(ref header, '|', 1, int.MaxValue, out int sequence)
            || !Integer(ref header, '|', 0, int.MaxValue, out int sourceFrame)
            || !Integer(ref header, '|', 0, BulletVisualFrame.OrdinaryLimit, out int count)
            || !Integer(ref header, '|', 0, 0, out _)
            || !header.SequenceEqual("R".AsSpan())) return false;
        // This candidate deliberately admits raw coordinates only.
        if (count == 0)
        {
            if (first >= 0) return false;
            frame = BulletVisualFrame.CreateQ1(offer, epoch, sequence, sourceFrame, Array.Empty<BulletVisualInstance>());
            return true;
        }
        if (first < 0) return false;
        var items = new BulletVisualInstance[count];
        ReadOnlySpan<char> rows = payload.AsSpan(first + 1);
        for (int i = 0; i < count; i++)
        {
            int separator = rows.IndexOf(';');
            bool last = i == count - 1;
            if ((last && separator >= 0) || (!last && separator < 0)) return false;
            ReadOnlySpan<char> row = separator < 0 ? rows : rows.Slice(0, separator);
            if (separator >= 0) rows = rows.Slice(separator + 1);
            if (!Integer(ref row, ',', 0, 255, out int tag) || tag % 16 >= styleCount
                || !Float(ref row, true, -1000000, 1000000, out float x)) return false;
            int mask = tag / 16;
            if (!Float(ref row, mask != 0, -1000000, 1000000, out float y)) return false;
            float rotation = 0, scaleX = 100, scaleY = 100, alpha = 100;
            if ((mask & 1) != 0 && !Float(ref row, (mask & 14) != 0, -100000, 100000, out rotation)) return false;
            if ((mask & 2) != 0 && !Float(ref row, (mask & 12) != 0, -10000, 10000, out scaleX)) return false;
            if ((mask & 4) != 0 && !Float(ref row, (mask & 8) != 0, -10000, 10000, out scaleY)) return false;
            if ((mask & 8) != 0 && !Float(ref row, false, 0, 100, out alpha)) return false;
            if (!row.IsEmpty) return false;
            items[i] = new BulletVisualInstance(tag % 16, x, y, rotation, scaleX, scaleY, alpha);
        }
        frame = BulletVisualFrame.CreateQ1(offer, epoch, sequence, sourceFrame, items);
        return true;
    }

    private static bool Token(ref ReadOnlySpan<char> source, char delimiter, out ReadOnlySpan<char> token)
    {
        int index = source.IndexOf(delimiter);
        token = index < 0 ? default : source.Slice(0, index);
        if (index < 0) return false;
        source = source.Slice(index + 1);
        return !token.IsEmpty;
    }

    private static bool Integer(ref ReadOnlySpan<char> source, char delimiter, int minimum, int maximum, out int value)
    {
        value = 0;
        if (!Token(ref source, delimiter, out var token) || token.Length > 10
            || (token.Length > 1 && token[0] == '0')) return false;
        return int.TryParse(token, NumberStyles.None, CultureInfo.InvariantCulture, out value) && value >= minimum && value <= maximum;
    }

    private static bool Float(ref ReadOnlySpan<char> source, bool followed, float minimum, float maximum, out float value)
    {
        value = 0;
        int separator = followed ? source.IndexOf(',') : -1;
        if (followed && separator < 0) return false;
        ReadOnlySpan<char> token = followed ? source.Slice(0, separator) : source;
        source = followed ? source.Slice(separator + 1) : default;
        if (token.IsEmpty || token.Length > 128) return false;
        // The generic range search can box characters before tiered compilation
        // specializes its comparer. Keep bounded cold packets allocation-free.
        for (int i = 0; i < token.Length; i++) if (token[i] <= ' ') return false;
        return float.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out value)
            && float.IsFinite(value) && value >= minimum && value <= maximum;
    }
}
