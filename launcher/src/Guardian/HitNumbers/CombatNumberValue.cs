using System;
using System.Globalization;

namespace CF7Launcher.Guardian.HitNumbers
{
    /// <summary>世界数字统一使用有界整数；资源结算和治疗聚合仍保留原精度。</summary>
    internal static class CombatNumberValue
    {
        internal static int ClampToInteger(double value)
        {
            if (double.IsNaN(value)) return 0;
            if (value >= int.MaxValue) return int.MaxValue;
            if (value <= int.MinValue) return int.MinValue;
            return (int)value;
        }

        internal static string Format(int value, bool positiveSign = false) =>
            (positiveSign ? "+" : string.Empty) + value.ToString(CultureInfo.InvariantCulture);
    }
}
