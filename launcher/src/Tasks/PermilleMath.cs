using System;
using System.Globalization;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// NPC 价格路径的非负 safe-integer 千分比合同。
    /// 所有失败都以 false 显式拒绝，不做浮点容差或截断修复。
    /// </summary>
    internal static class PermilleMath
    {
        internal const long Scale = 1000L;
        internal const long MaxSafeInteger = 9007199254740991L;

        internal static bool TryReadSafeNonNegativeInteger(JToken token, out long value)
        {
            return TryReadSafeInteger(token, out value) && value >= 0;
        }

        internal static bool TryReadSafeInteger(JToken token, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;

            long candidate;
            if (!long.TryParse(
                    token.ToString(Formatting.None),
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out candidate)) return false;
            if (!IsSafeInteger(candidate)) return false;
            value = candidate;
            return true;
        }

        internal static bool TryMultiply(
            long left,
            long right,
            out long product)
        {
            product = 0;
            if (!IsSafeNonNegativeInteger(left)
                || !IsSafeNonNegativeInteger(right)) return false;
            if (left != 0 && right > MaxSafeInteger / left) return false;

            product = checked(left * right);
            return product <= MaxSafeInteger;
        }

        internal static bool TryAdd(long left, long right, out long sum)
        {
            sum = 0;
            if (!IsSafeNonNegativeInteger(left)
                || !IsSafeNonNegativeInteger(right)
                || right > MaxSafeInteger - left) return false;

            sum = checked(left + right);
            return true;
        }

        internal static bool TryAddSigned(long left, long right, out long sum)
        {
            sum = 0;
            if (!IsSafeInteger(left) || !IsSafeInteger(right)) return false;
            long candidate = checked(left + right);
            if (!IsSafeInteger(candidate)) return false;
            sum = candidate;
            return true;
        }

        internal static bool TrySubtract(long left, long right, out long difference)
        {
            difference = 0;
            if (!IsSafeInteger(left) || !IsSafeInteger(right)) return false;
            long candidate = checked(left - right);
            if (!IsSafeInteger(candidate)) return false;
            difference = candidate;
            return true;
        }

        /// <summary>floor(amount * ratePermille / 1000).</summary>
        internal static bool TryFloor(
            long amount,
            long ratePermille,
            out long result)
        {
            result = 0;
            long product;
            if (!TryMultiply(amount, ratePermille, out product)) return false;
            result = product / Scale;
            return true;
        }

        private static bool IsSafeNonNegativeInteger(long value)
        {
            return value >= 0 && value <= MaxSafeInteger;
        }

        private static bool IsSafeInteger(long value)
        {
            return value >= -MaxSafeInteger && value <= MaxSafeInteger;
        }
    }
}
