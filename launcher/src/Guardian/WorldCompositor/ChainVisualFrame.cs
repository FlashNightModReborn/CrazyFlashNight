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
            string[] header = (end < 0 ? payload : payload.Substring(0, end)).Split('|');
            return header.Length == 4 && header[0] == "1" && Integer(header[1], 0, int.MaxValue, out epoch)
                && Integer(header[2], 1, int.MaxValue, out sequence)
                && Integer(header[3], 0, int.MaxValue, out tick);
        }

        internal static bool TryParse(string payload, int styleCount, out ChainVisualFrame result)
        {
            result = null;
            if (styleCount < 1 || styleCount > 16
                || !TryReadHeader(payload, out int epoch, out int sequence, out int tick)) return false;
            var parsed = new ChainVisualFrame { Epoch = epoch, Sequence = sequence, Tick = tick };
            string[] rows = payload.Split(';');
            if (rows.Length > MaxUnits * 3 + 1) return false;
            var groupIds = new HashSet<int>();
            bool eventsStarted = false;
            for (int i = 1; i < rows.Length; i++)
            {
                string[] fields = rows[i].Split(',');
                if (fields.Length < 3 || !Integer(fields[1], 1, int.MaxValue, out int group)) return false;
                if (fields[0] == "G")
                {
                    if (eventsStarted || fields.Length != 13 || parsed.Groups.Count == MaxUnits
                        || !groupIds.Add(group) || !Integer(fields[2], 0, styleCount - 1, out int style)
                        || !Integer(fields[3], 0, int.MaxValue, out int step)
                        || !Number(fields[4], -1000000, 1000000, out double x)
                        || !Number(fields[5], -1000000, 1000000, out double y)
                        || !Number(fields[6], -100000, 100000, out double rotation)
                        || !Number(fields[7], -10000, 10000, out double sx)
                        || !Number(fields[8], -10000, 10000, out double sy)
                        || !Number(fields[9], 0, 100, out double alpha)
                        || !Integer(fields[10], 0, 1, out int visible)
                        || !Number(fields[11], -1000000, 1000000, out double advance)
                        || !Integer(fields[12], 0, 1, out int advanceX)) return false;
                    parsed.Groups.Add(new GroupState(group, style, step, x, y, rotation,
                        sx, sy, alpha, visible == 1, advance, advanceX == 1));
                    continue;
                }
                eventsStarted = true;
                if (!groupIds.Contains(group) || parsed.Events.Count == MaxUnits * 2
                    || !Integer(fields[2], 1, int.MaxValue, out int id)) return false;
                if (fields[0] == "B")
                {
                    if (fields.Length != 8
                        || !Number(fields[3], -1000000, 1000000, out double x)
                        || !Number(fields[4], -1000000, 1000000, out double y)
                        || !Number(fields[5], -1, 1, out double sin)
                        || !Number(fields[6], -1, 1, out double cos)
                        || !Number(fields[7], -100000, 100000, out double rotation)) return false;
                    parsed.Events.Add(new UnitEvent(true, group, id, x, y, sin, cos, rotation));
                }
                else if (fields[0] == "D" && fields.Length == 3)
                    parsed.Events.Add(new UnitEvent(false, group, id));
                else return false;
            }
            result = parsed;
            return true;
        }

        private static bool Integer(string text, int minimum, int maximum, out int value) =>
            int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out value)
            && value >= minimum && value <= maximum;
        private static bool Number(string text, double minimum, double maximum, out double value) =>
            double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value)
            && double.IsFinite(value) && value >= minimum && value <= maximum;
    }
}