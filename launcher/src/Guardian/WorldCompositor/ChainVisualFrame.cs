using System;
using System.Collections.Generic;
using System.Globalization;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // F8 is a complete set of groups plus bounded birth/death events. Group
    // motion is authoritative AS2 state; no collision or random sampling lives here.
    internal sealed class ChainVisualFrame
    {
        // Shared three-tier bullet budget: 15360 chain units are reserved
        // inside the 16384 total alongside the 1024 ordinary snapshot slots.
        internal const int MaxUnits = 15360;
        internal const int MaxPayloadCharacters = 4 * 1024 * 1024;
        internal int Epoch, Sequence, Tick;
        internal readonly List<GroupState> Groups = new();
        internal readonly List<UnitEvent> Events = new();

        internal readonly struct GroupState
        {
            internal readonly int Id, Style, Step;
            internal readonly double X, Y, Rotation, ScaleX, ScaleY, Alpha, Advance;
            internal readonly bool Visible, AdvanceX;
            internal GroupState(int id, int style, int step, double x, double y, double rotation,
                double sx, double sy, double alpha, bool visible, double advance, bool advanceX)
            {
                Id = id; Style = style; Step = step; X = x; Y = y; Rotation = rotation;
                ScaleX = sx; ScaleY = sy; Alpha = alpha; Visible = visible;
                Advance = advance; AdvanceX = advanceX;
            }
        }

        internal readonly struct UnitEvent
        {
            internal readonly bool Birth;
            internal readonly int Group, Id;
            internal readonly double X, Y, Sin, Cos, Rotation;
            internal UnitEvent(bool birth, int group, int id, double x = 0, double y = 0,
                double sin = 0, double cos = 0, double rotation = 0)
            { Birth = birth; Group = group; Id = id; X = x; Y = y; Sin = sin; Cos = cos; Rotation = rotation; }
        }

        internal static bool TryReadHeader(string payload, out int epoch, out int sequence, out int tick)
        {
            epoch = sequence = tick = 0;
            if (string.IsNullOrEmpty(payload) || payload.Length > MaxPayloadCharacters) return false;
            int end = payload.IndexOf(';');
            ReadOnlySpan<char> header = end < 0 ? payload.AsSpan() : payload.AsSpan(0, end);
            return Token(ref header, '|', out var version) && version.SequenceEqual("1".AsSpan())
                && ReadInteger(ref header, '|', 0, int.MaxValue, out epoch)
                && ReadInteger(ref header, '|', 1, int.MaxValue, out sequence)
                && LastInteger(header, 0, int.MaxValue, out tick);
        }

        internal static bool TryParse(string payload, int styleCount, out ChainVisualFrame result)
        {
            result = null;
            if (styleCount < 1 || styleCount > 16
                || !TryReadHeader(payload, out int epoch, out int sequence, out int tick)) return false;
            var parsed = new ChainVisualFrame { Epoch = epoch, Sequence = sequence, Tick = tick };
            int first = payload.IndexOf(';');
            if (first < 0) { result = parsed; return true; }
            ReadOnlySpan<char> rows = payload.AsSpan(first + 1);
            var groupIds = new HashSet<int>();
            bool eventsStarted = false;
            int rowCount = 0;
            while (true)
            {
                if (++rowCount > MaxUnits * 3) return false;
                int next = rows.IndexOf(';');
                ReadOnlySpan<char> fields = next < 0 ? rows : rows.Slice(0, next);
                if (!Token(ref fields, ',', out var kind)
                    || !ReadInteger(ref fields, ',', 1, int.MaxValue, out int group)) return false;
                if (kind.SequenceEqual("G".AsSpan()))
                {
                    if (eventsStarted || parsed.Groups.Count == MaxUnits
                        || !groupIds.Add(group) || !ReadInteger(ref fields, ',', 0, styleCount - 1, out int style)
                        || !ReadInteger(ref fields, ',', 0, int.MaxValue, out int step)
                        || !ReadNumber(ref fields, -1000000, 1000000, out double x)
                        || !ReadNumber(ref fields, -1000000, 1000000, out double y)
                        || !ReadNumber(ref fields, -100000, 100000, out double rotation)
                        || !ReadNumber(ref fields, -10000, 10000, out double sx)
                        || !ReadNumber(ref fields, -10000, 10000, out double sy)
                        || !ReadNumber(ref fields, 0, 100, out double alpha)
                        || !ReadInteger(ref fields, ',', 0, 1, out int visible)
                        || !ReadNumber(ref fields, -1000000, 1000000, out double advance)
                        || !LastInteger(fields, 0, 1, out int advanceX)) return false;
                    parsed.Groups.Add(new GroupState(group, style, step, x, y, rotation,
                        sx, sy, alpha, visible == 1, advance, advanceX == 1));
                }
                else
                {
                    eventsStarted = true;
                    if (!groupIds.Contains(group) || parsed.Events.Count == MaxUnits * 2) return false;
                    if (kind.SequenceEqual("B".AsSpan()))
                    {
                        if (!ReadInteger(ref fields, ',', 1, int.MaxValue, out int id)
                            || !ReadNumber(ref fields, -1000000, 1000000, out double x)
                            || !ReadNumber(ref fields, -1000000, 1000000, out double y)
                            || !ReadNumber(ref fields, -1, 1, out double sin)
                            || !ReadNumber(ref fields, -1, 1, out double cos)
                            || fields.IndexOf(',') >= 0 || !Number(fields, -100000, 100000, out double rotation)) return false;
                        parsed.Events.Add(new UnitEvent(true, group, id, x, y, sin, cos, rotation));
                    }
                    else if (kind.SequenceEqual("D".AsSpan()) && LastInteger(fields, 1, int.MaxValue, out int id))
                        parsed.Events.Add(new UnitEvent(false, group, id));
                    else return false;
                }
                if (next < 0) break;
                // Process a trailing empty record too, matching the old Split grammar.
                rows = rows.Slice(next + 1);
            }
            result = parsed;
            return true;
        }

        private static bool Token(ref ReadOnlySpan<char> rest, char separator, out ReadOnlySpan<char> value)
        {
            int end = rest.IndexOf(separator);
            if (end < 0) { value = default; return false; }
            value = rest.Slice(0, end); rest = rest.Slice(end + 1); return true;
        }
        private static bool ReadInteger(ref ReadOnlySpan<char> rest, char separator, int minimum, int maximum, out int value)
        {
            value = 0;
            return Token(ref rest, separator, out var token) && Integer(token, minimum, maximum, out value);
        }
        private static bool LastInteger(ReadOnlySpan<char> text, int minimum, int maximum, out int value)
        {
            value = 0;
            return text.IndexOfAny('|', ',') < 0 && Integer(text, minimum, maximum, out value);
        }
        private static bool ReadNumber(ref ReadOnlySpan<char> rest, double minimum, double maximum, out double value)
        {
            value = 0;
            return Token(ref rest, ',', out var token) && Number(token, minimum, maximum, out value);
        }
        private static bool Integer(ReadOnlySpan<char> text, int minimum, int maximum, out int value) =>
            int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out value)
            && value >= minimum && value <= maximum;
        private static bool Number(ReadOnlySpan<char> text, double minimum, double maximum, out double value) =>
            double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value)
            && double.IsFinite(value) && value >= minimum && value <= maximum;
    }
}
