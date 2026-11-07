using System;

namespace CF7Launcher.Guardian.Hud.Icons
{
    /// <summary>Immutable value-only timeline. All time arguments are TimeSpan ticks.</summary>
    internal sealed class IconTimeline
    {
        private readonly int[] _content;
        private readonly long[] _ends;
        private readonly decimal _fps;
        internal long PeriodTicks { get; }
        internal int SlotCount => _content.Length;

        internal IconTimeline(int[] content, double fps, int[] durationMs = null)
        {
            if (content == null || content.Length == 0) throw new ArgumentException("Empty timeline.", nameof(content));
            _content = (int[])content.Clone();
            decimal rate = double.IsFinite(fps) && fps > 0 && fps <= TimeSpan.TicksPerSecond ? (decimal)fps : 24m;
            if (rate <= 0 || content.Length * (decimal)TimeSpan.TicksPerSecond / rate > long.MaxValue) rate = 24m;
            _fps = rate;
            if (durationMs != null && durationMs.Length == content.Length)
            {
                var ends = new long[content.Length];
                long sum = 0;
                for (int i = 0; i < ends.Length; i++)
                    ends[i] = sum = checked(sum + Math.Max(0L, durationMs[i]) * TimeSpan.TicksPerMillisecond);
                if (sum > 0) { _ends = ends; PeriodTicks = sum; }
            }
            if (_ends == null)
                PeriodTicks = Math.Max(1L, (long)decimal.Ceiling(content.Length * (decimal)TimeSpan.TicksPerSecond / _fps));
        }

        internal int Sample(long elapsedTicks)
        {
            elapsedTicks = Math.Max(0L, elapsedTicks);
            if (_ends == null)
            {
                // Keep the rational FPS until after division. Rounding each slot or
                // repeatedly rounding the period would accumulate drift at 24/29.97 FPS.
                decimal slot = decimal.Truncate(elapsedTicks * _fps / TimeSpan.TicksPerSecond);
                return _content[(int)(slot % _content.Length)];
            }
            long phase = elapsedTicks % PeriodTicks;
            int lo = 0, hi = _ends.Length - 1;
            while (lo < hi)
            {
                int mid = lo + (hi - lo) / 2;
                if (phase < _ends[mid]) hi = mid;
                else lo = mid + 1;
            }
            return _content[lo];
        }
    }
}
