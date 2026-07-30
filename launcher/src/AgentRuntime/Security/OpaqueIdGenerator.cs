using System;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace CF7Launcher.AgentRuntime.Security
{
    public static class OpaqueIdGenerator
    {
        private const int EntropyBytes = 18;
        private static readonly Regex PrefixPattern = new Regex(
            "^[a-z][a-z0-9_]{0,31}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        public static string Create(string prefix)
        {
            if (string.IsNullOrWhiteSpace(prefix)
                || !PrefixPattern.IsMatch(prefix))
            {
                throw new ArgumentException(
                    "Opaque ID prefixes must be lowercase protocol identifiers.",
                    nameof(prefix));
            }

            byte[] entropy = new byte[EntropyBytes];
            RandomNumberGenerator.Fill(entropy);
            string encoded = Convert.ToBase64String(entropy)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
            return prefix + "_" + encoded;
        }
    }
}
