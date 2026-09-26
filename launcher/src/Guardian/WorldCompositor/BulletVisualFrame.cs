using System;
using System.Diagnostics;
using System.Globalization;
using System.Text;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // F-packet section 5: complete, bounded visual snapshot. The first batch
    // observes Flash only; parsing does not grant native display ownership.
    internal sealed class BulletVisualFrame
    {
        internal readonly int Epoch, Frame, NormalCount, ChainCount, Overflow;
        internal readonly bool NativeOwned;
        internal readonly BulletVisualInstance[] Instances;
        private BulletVisualFrame(int epoch, int frame, int normal, int chain, int overflow, bool nativeOwned,
            BulletVisualInstance[] instances)
        {
            Epoch = epoch; Frame = frame; NormalCount = normal; ChainCount = chain;
            Overflow = overflow; NativeOwned = nativeOwned; Instances = instances;
        }

        internal static bool TryParse(string payload, int styleCount, out BulletVisualFrame result)
        {
            result = null;
            if (string.IsNullOrEmpty(payload) || payload.Length > 65536
                || styleCount < 1 || styleCount > 16) return false;
            ReadOnlySpan<char> rest = payload.AsSpan();
            int firstEntry = rest.IndexOf(';');
            ReadOnlySpan<char> header = firstEntry < 0 ? rest : rest.Slice(0, firstEntry);
            if (!Int(ref header, '|', out int epoch) || !Int(ref header, '|', out int frame)
                || !Int(ref header, '|', out int normal) || !Int(ref header, '|', out int chain)) return false;
            int owner = 0;
            int overflow;
            // Old shadow packets lack the ownership field. They can never
            // authorize native drawing, even when received by a paired host.
            if (header.IndexOf('|') >= 0)
            {
                if (!Int(ref header, '|', out overflow) || !FinalInt(header, out owner)
                    || (owner != 0 && owner != 1)) return false;
            }
            else if (!FinalInt(header, out overflow)) return false;
            if (epoch < 0 || frame < 0 || normal < 0 || chain < 0
                || normal > 256 || chain > 256
                || normal + chain > 256 || overflow < 0 || overflow > 65535) return false;
            int count = normal + chain;
            if ((firstEntry < 0) != (count == 0)) return false;
            var instances = new BulletVisualInstance[count];
            if (count > 0)
            {
                rest = rest.Slice(firstEntry + 1);
                for (int i = 0; i < count; i++)
                {
                    int separator = rest.IndexOf(';');
                    if ((i < count - 1 && separator < 0)
                        || (i == count - 1 && separator >= 0)) return false;
                    ReadOnlySpan<char> entry = separator < 0 ? rest : rest.Slice(0, separator);
                    if (!Int(ref entry, ',', out int style) || style < 0 || style >= styleCount
                        || !Float(ref entry, ',', -1000000, 1000000, out float x)
                        || !Float(ref entry, ',', -1000000, 1000000, out float y)
                        || !Float(ref entry, ',', -100000, 100000, out float rotation)
                        || !Float(ref entry, ',', -10000, 10000, out float scaleX)
                        || !Float(ref entry, ',', -10000, 10000, out float scaleY)
                        || !FinalFloat(entry, 0, 100, out float alpha)) return false;
                    instances[i] = new BulletVisualInstance(style, x, y, rotation, scaleX, scaleY, alpha);
                    if (separator >= 0) rest = rest.Slice(separator + 1);
                }
            }
            result = new BulletVisualFrame(epoch, frame, normal, chain, overflow, owner == 1, instances);
            return true;
        }

        private static bool Int(ref ReadOnlySpan<char> value, char separator, out int parsed)
        {
            parsed = 0;
            int index = value.IndexOf(separator);
            if (index <= 0) return false;
            bool ok = int.TryParse(value.Slice(0, index), NumberStyles.None,
                CultureInfo.InvariantCulture, out parsed);
            value = value.Slice(index + 1);
            return ok;
        }
        private static bool FinalInt(ReadOnlySpan<char> value, out int parsed) =>
            int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out parsed);
        private static bool Float(ref ReadOnlySpan<char> value, char separator,
            float minimum, float maximum, out float parsed)
        {
            parsed = 0;
            int index = value.IndexOf(separator);
            if (index <= 0) return false;
            bool ok = FinalFloat(value.Slice(0, index), minimum, maximum, out parsed);
            value = value.Slice(index + 1);
            return ok;
        }
        private static bool FinalFloat(ReadOnlySpan<char> value, float minimum,
            float maximum, out float parsed) =>
            float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out parsed)
            && float.IsFinite(parsed) && parsed >= minimum && parsed <= maximum;
    }

    internal readonly struct BulletVisualInstance
    {
        internal readonly int Style;
        internal readonly float X, Y, Rotation, ScaleX, ScaleY, Alpha;
        internal BulletVisualInstance(int style, float x, float y, float rotation,
            float scaleX, float scaleY, float alpha)
        {
            Style = style; X = x; Y = y; Rotation = rotation;
            ScaleX = scaleX; ScaleY = scaleY; Alpha = alpha;
        }
    }

    internal sealed class BulletVisualShadow
    {
        private readonly int _styleCount;
        private readonly string[] _styleIds;
        private readonly object _sync = new object();
        private int _generation = -1, _epoch = -1, _lastFrame = -1;
        private int _packets, _maxCount, _overflow, _invalid;
        private long _parseTicks, _bytes, _lastReport;
        private readonly int[] _normalMax, _chainMax, _normalFrames, _chainFrames;
        private readonly int[] _currentNormal, _currentChain;
        internal BulletVisualShadow(BulletVisualCatalog catalog)
        {
            _styleCount = catalog.Styles.Count;
            _styleIds = new string[_styleCount];
            for (int i = 0; i < _styleCount; i++) _styleIds[i] = catalog.Styles[i].Id;
            _normalMax = new int[_styleCount]; _chainMax = new int[_styleCount];
            _normalFrames = new int[_styleCount]; _chainFrames = new int[_styleCount];
            _currentNormal = new int[_styleCount]; _currentChain = new int[_styleCount];
        }

        internal void Reset()
        {
            lock (_sync) { _generation = -1; ResetCounters(); }
        }
        internal void ResetIfGeneration(int generation)
        {
            lock (_sync) if (generation == _generation) ResetCounters();
        }
        private void ResetCounters()
        {
            _epoch = -1; _lastFrame = -1; _packets = 0; _maxCount = 0;
            _overflow = 0; _invalid = 0; _parseTicks = 0; _bytes = 0;
            _lastReport = 0;
            Array.Clear(_normalMax); Array.Clear(_chainMax);
            Array.Clear(_normalFrames); Array.Clear(_chainFrames);
        }

        internal BulletVisualFrame Observe(string payload, int generation)
        {
            long started = Stopwatch.GetTimestamp();
            bool valid = BulletVisualFrame.TryParse(payload, _styleCount, out BulletVisualFrame frame);
            lock (_sync)
            {
                if (generation < _generation) return null;
                if (generation > _generation) { _generation = generation; ResetCounters(); }
                if (!valid || frame.Epoch < _epoch
                    || (frame.Epoch == _epoch && frame.Frame <= _lastFrame))
                {
                    if (++_invalid <= 8) LogManager.Log("event=bullet_visual_shadow_rejected");
                    return null;
                }
                if (frame.Epoch != _epoch) { _epoch = frame.Epoch; _lastFrame = -1; }
                _lastFrame = frame.Frame;
                _packets++;
                _bytes += payload.Length;
                _maxCount = Math.Max(_maxCount, frame.Instances.Length);
                _overflow += frame.Overflow;
                Array.Clear(_currentNormal); Array.Clear(_currentChain);
                for (int i = 0; i < frame.Instances.Length; i++)
                {
                    int style = frame.Instances[i].Style;
                    if (i < frame.NormalCount) _currentNormal[style]++;
                    else _currentChain[style]++;
                }
                for (int i = 0; i < _styleCount; i++)
                {
                    _normalMax[i] = Math.Max(_normalMax[i], _currentNormal[i]);
                    _chainMax[i] = Math.Max(_chainMax[i], _currentChain[i]);
                    if (_currentNormal[i] > 0) _normalFrames[i]++;
                    if (_currentChain[i] > 0) _chainFrames[i]++;
                }
                _parseTicks += Stopwatch.GetTimestamp() - started;
                long now = Stopwatch.GetTimestamp();
                if (_lastReport == 0) _lastReport = now;
                if (now - _lastReport < Stopwatch.Frequency * 2) return frame;
                double parseUs = _packets > 0
                    ? _parseTicks * 1000000.0 / Stopwatch.Frequency / _packets : 0;
                LogManager.Log(string.Format(CultureInfo.InvariantCulture,
                    "event=bullet_visual_shadow generation={0} epoch={1} frames={2} maxItems={3} chars={4} overflow={5} invalid={6} parseUsPerFrame={7:F1} coverage={8}",
                    _generation, _epoch, _packets, _maxCount, _bytes, _overflow, _invalid, parseUs,
                    FormatCoverage()));
                _packets = 0; _maxCount = 0; _overflow = 0; _invalid = 0;
                _parseTicks = 0; _bytes = 0; _lastReport = now;
                Array.Clear(_normalMax); Array.Clear(_chainMax);
                Array.Clear(_normalFrames); Array.Clear(_chainFrames);
                return frame;
            }
        }

        internal string CoverageForTests()
        {
            lock (_sync) return FormatCoverage();
        }

        private string FormatCoverage()
        {
            var result = new StringBuilder();
            for (int i = 0; i < _styleCount; i++)
            {
                if (i > 0) result.Append(',');
                result.Append("normal.").Append(_styleIds[i]).Append('=')
                    .Append(_normalMax[i]).Append('/').Append(_normalFrames[i]);
                result.Append(",chain.").Append(_styleIds[i]).Append('=')
                    .Append(_chainMax[i]).Append('/').Append(_chainFrames[i]);
            }
            return result.ToString();
        }
    }
}
