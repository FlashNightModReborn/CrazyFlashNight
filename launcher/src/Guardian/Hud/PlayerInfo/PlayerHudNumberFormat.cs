#nullable enable
using System;
using System.Globalization;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal readonly record struct PlayerHudNumberText(string Text, float ReservedWidth);

/// <summary>Presentation only: snapshots, percent calculation and gameplay keep their original values.</summary>
internal static class PlayerHudNumberFormat
{
    internal static string Full(double value) => double.IsFinite(value)
        ? Math.Floor(value).ToString("0", CultureInfo.InvariantCulture)
        : double.IsPositiveInfinity(value) ? "∞" : "--";

    internal static string Fit(double value, Func<string, float> measure, float width, double reference = 0, bool compact = false)
        => Format(value, measure, width, reference, compact).Text;

    internal static PlayerHudNumberText Format(double value, Func<string, float> measure, float width,
        double reference = 0, bool compact = false)
        => FormatNumber(value, new Metrics(measure), width, reference, compact, Full(value));

    internal static bool RequiresCompact(double value, Func<string, float> measure, float width)
        => double.IsFinite(value) && Math.Abs(value) >= 10000 && new Metrics(measure).Envelope(Full(value)) > width;

    internal static string FitText(string value, Func<string, float> measure, float width)
        => FormatText(value, measure, width).Text;

    internal static PlayerHudNumberText FormatText(string value, Func<string, float> measure, float width)
    {
        if (value.Length == 0) value = "--";
        var metrics = new Metrics(measure);
        if (TryNumber(value, out var number))
            return FormatNumber(number, metrics, width, 0, false, value);
        var separator = value.IndexOf('/');
        if (separator > 0 && separator == value.LastIndexOf('/'))
        {
            var leftRaw = value[..separator].Trim(); var rightRaw = value[(separator + 1)..].Trim();
            var numericLeft = TryNumber(leftRaw, out var a);
            var numericRight = TryNumber(rightRaw, out var b);
            if (numericLeft && numericRight)
            {
                var anchor = Math.Max(Math.Abs(a), Math.Abs(b));
                var gap = measure("/");
                var rawLeftWidth = RawWidth(a, leftRaw, anchor, metrics);
                var rawRightWidth = RawWidth(b, rightRaw, Math.Abs(b), metrics);
                // Even a nearly depleted resource keeps the capacity's compact mode.
                var capacityLeftWidth = Math.Max(rawLeftWidth, metrics.Envelope(Full(anchor)));
                var exactEnvelope = metrics.Envelope(value);
                if (capacityLeftWidth + gap + rawRightWidth <= width && exactEnvelope <= width)
                    return new(value, Math.Max(exactEnvelope,rawLeftWidth + gap + rawRightWidth));
                // Small loaded/critical counts reserve their digit band, never become 0.00万.
                // Both budgets are stable within that band; a narrow '1' cannot steal the other field's precision.
                var leftBudget = Math.Abs(a) < 10000 ? rawLeftWidth : (width - gap) * 0.45f;
                var rightBudget = Math.Max(1, width - gap - leftBudget);
                var left = FormatNumber(a, metrics, leftBudget, anchor, true, leftRaw);
                var right = FormatNumber(b, metrics, rightBudget, Math.Abs(b), true, rightRaw);
                return new(left.Text + "/" + right.Text, left.ReservedWidth + gap + right.ReservedWidth);
            }
            if (numericLeft || numericRight)
            {
                var marker = numericLeft ? rightRaw : leftRaw;
                var markerWidth = measure(marker); var gap = measure("/");
                var numberPart = FormatNumber(numericLeft ? a : b, metrics,
                    Math.Max(1,width-markerWidth-gap),0,false,numericLeft ? leftRaw : rightRaw);
                return new(numericLeft ? numberPart.Text+"/"+marker : marker+"/"+numberPart.Text,
                    numberPart.ReservedWidth+gap+markerWidth);
            }
        }
        // Percentages and nonnumeric markers retain their established size and exact text.
        return new(value, measure(value));
    }

    private static bool TryNumber(string text, out double value)
        => double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value) && double.IsFinite(value);

    private static float RawWidth(double value, string raw, double reference, Metrics metrics)
        => Math.Abs(value) < 10000 ? metrics.Envelope(raw)
            : metrics.Envelope((value < 0 ? "-" : "") + Full(Math.Max(Math.Abs(value), reference)));

    private static double Unit(double magnitude) => magnitude >= 1e12 ? 1e12 : magnitude >= 1e8 ? 1e8 : 1e4;

    private static PlayerHudNumberText FormatNumber(double value, Metrics metrics, float width,
        double reference, bool compact, string raw)
    {
        if (!double.IsFinite(value)) return new(raw, metrics.Envelope(raw));
        var magnitude = Math.Abs(value);
        var anchor = double.IsFinite(reference) ? Math.Max(magnitude, Math.Abs(reference)) : magnitude;
        var plainWidth = RawWidth(value, raw, anchor, metrics);
        if (magnitude < 10000 || (!compact && plainWidth <= width)) return new(raw, plainWidth);
        var divisor = Unit(magnitude);
        // The maximum stabilizes compact mode; precision follows the current magnitude band so
        // a small remaining amount is not rounded down to whole 万 just because capacity is huge.
        var suffix = divisor == 1e12 ? "万亿" : divisor == 1e8 ? "亿" : "万";
        var scaled = value / divisor;
        var integerTemplate = (value < 0 ? "-" : "") + Full(magnitude / divisor);
        for (var digits = 2; digits >= 0; digits--)
        {
            var template = integerTemplate + (digits > 0 ? "." + new string('0', digits) : "") + suffix;
            var reserved = metrics.Envelope(template);
            if (reserved > width) continue;
            var factor = Math.Pow(10, digits);
            var truncated = Math.Truncate(scaled * factor) / factor;
            return new(truncated.ToString(digits == 2 ? "0.00" : digits == 1 ? "0.0" : "0",
                CultureInfo.InvariantCulture) + suffix, reserved);
        }
        if (Math.Abs(scaled) < 10000)
            return new(Math.Truncate(scaled).ToString("0", CultureInfo.InvariantCulture) + suffix,
                metrics.Envelope(integerTemplate + suffix));
        var exponent = (int)Math.Floor(Math.Log10(magnitude));
        var mantissa = Math.Truncate(value / Math.Pow(10, exponent) * 10) / 10;
        var scientific = mantissa.ToString("0.0", CultureInfo.InvariantCulture) + "e" + exponent.ToString(CultureInfo.InvariantCulture);
        return new(scientific, metrics.Envelope(scientific));
    }

    /// <summary>Reserve the widest digit, not the digits that happen to occur in this frame.</summary>
    private sealed class Metrics(Func<string, float> measure)
    {
        private char? _widest;
        internal float Envelope(string text)
        {
            var hasDigit = false;
            foreach (var c in text) if (c is >= '0' and <= '9') { hasDigit = true; break; }
            if (!hasDigit) return measure(text);
            if (!_widest.HasValue)
            {
                var maximum = -1f;
                for (var digit = '0'; digit <= '9'; digit++)
                {
                    var candidate = measure(digit.ToString());
                    if (candidate > maximum) { maximum = candidate; _widest = digit; }
                }
            }
            var chars = text.ToCharArray();
            for (var i = 0; i < chars.Length; i++) if (chars[i] is >= '0' and <= '9') chars[i] = _widest!.Value;
            return measure(new string(chars));
        }
    }
}
