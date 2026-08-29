using System;
using System.Text.RegularExpressions;

namespace CF7Launcher.Save
{
    /// <summary>
    /// Physical save identity accepted by every Host file-custody boundary.
    /// Display names are deliberately not converted into slot keys.
    /// </summary>
    public static class SaveSlotKey
    {
        public const int MaxLength = 32;
        public const int ExistingMaxLength = 128;
        private static readonly Regex NewKeyPattern = new Regex(
            "^[A-Za-z0-9_-]{1,32}$",
            RegexOptions.Compiled | RegexOptions.CultureInvariant);
        private static readonly Regex ExistingKeyPattern = new Regex(
            "^[A-Za-z0-9_-]{1,128}$",
            RegexOptions.Compiled | RegexOptions.CultureInvariant);

        public static bool TryValidate(string value, out string slotKey)
        {
            slotKey = null;
            if (string.IsNullOrEmpty(value) || !NewKeyPattern.IsMatch(value))
                return false;

            slotKey = value;
            return true;
        }

        public static bool IsValid(string value)
        {
            string ignored;
            return TryValidate(value, out ignored);
        }

        public static bool TryValidateExisting(string value, out string slotKey)
        {
            slotKey = null;
            if (string.IsNullOrEmpty(value)
                || !ExistingKeyPattern.IsMatch(value))
                return false;
            slotKey = value;
            return true;
        }

        public static bool IsValidExisting(string value)
        {
            string ignored;
            return TryValidateExisting(value, out ignored);
        }

        public static string CreateNew()
        {
            // 4-char prefix + 28 hexadecimal chars = the existing 32-char
            // SharedObject/Bootstrap limit while retaining 112 random bits.
            return "cf7_" + Guid.NewGuid().ToString("N").Substring(0, 28);
        }
    }
}
