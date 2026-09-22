using System;
using System.Drawing;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal static class WorldPointerMapper
    {
        // Matches the native compositor's aspect-preserving viewport, including rounding
        // bars. Negative coordinates are retained during a drag outside the client area.
        internal static Point Map(Point display, Size output, Size source)
        {
            if (output.Width < 1 || output.Height < 1 || source.Width < 1 || source.Height < 1)
                throw new ArgumentOutOfRangeException(nameof(output));
            double scale = Math.Min((double)output.Width / source.Width, (double)output.Height / source.Height);
            double left = (output.Width - source.Width * scale) / 2;
            double top = (output.Height - source.Height * scale) / 2;
            return new Point((int)Math.Floor((display.X - left) / scale), (int)Math.Floor((display.Y - top) / scale));
        }
        internal static IntPtr Pack(Point point) => new IntPtr(unchecked((int)((uint)(ushort)point.X | ((uint)(ushort)point.Y << 16))));
        internal static Point Unpack(IntPtr value) => new Point((short)(value.ToInt64() & 65535), (short)((value.ToInt64() >> 16) & 65535));
    }
}
