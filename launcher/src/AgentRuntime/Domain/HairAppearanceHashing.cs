using System;
using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace CF7Launcher.AgentRuntime.Domain
{
    internal static class HairAppearanceHashing
    {
        private const string SnapshotDomain = "cf7.hair.snapshot.v1";
        private const string PreviewDomain = "cf7.appearance.hair.preview.v1";

        public static string ComputeSnapshotHash(
            HairAuthoritativeSnapshot snapshot)
        {
            if (snapshot == null)
            {
                throw new ArgumentNullException(nameof(snapshot));
            }

            using (IncrementalHash hash =
                IncrementalHash.CreateHash(HashAlgorithmName.SHA256))
            {
                AppendString(hash, SnapshotDomain);
                AppendBinding(hash, snapshot.Binding);
                AppendInt64(hash, snapshot.Revision);
                AppendInt64(hash, snapshot.Generation);
                AppendString(hash, snapshot.CurrentHair);
                AppendInt32(hash, snapshot.Catalog.Count);
                for (int i = 0; i < snapshot.Catalog.Count; i++)
                {
                    HairCatalogEntry entry = snapshot.Catalog[i];
                    AppendString(hash, entry.Identifier);
                    AppendString(hash, entry.DisplayName);
                }
                return ToLowerHex(hash.GetHashAndReset());
            }
        }

        public static string ComputePreviewHash(
            string transactionId,
            HairSaveBinding binding,
            string beforeHair,
            string afterHair,
            long expectedRevision,
            long expectedGeneration,
            string expectedSnapshotHash)
        {
            using (IncrementalHash hash =
                IncrementalHash.CreateHash(HashAlgorithmName.SHA256))
            {
                AppendString(hash, PreviewDomain);
                AppendString(hash, HairAppearanceOperation.Name);
                AppendString(hash, transactionId);
                AppendBinding(hash, binding);
                AppendString(hash, beforeHair);
                AppendString(hash, afterHair);
                AppendInt64(hash, expectedRevision);
                AppendInt64(hash, expectedGeneration);
                AppendString(hash, expectedSnapshotHash);
                return ToLowerHex(hash.GetHashAndReset());
            }
        }

        public static string HashOpaqueToken(string token)
        {
            if (string.IsNullOrEmpty(token))
            {
                return string.Empty;
            }
            return ToLowerHex(
                SHA256.HashData(Encoding.UTF8.GetBytes(token)));
        }

        public static bool FixedTimeTokenMatches(
            string token,
            string expectedHash)
        {
            if (!HairAppearanceValidation.IsSha256(expectedHash))
            {
                return false;
            }

            byte[] actual = SHA256.HashData(
                Encoding.UTF8.GetBytes(token ?? string.Empty));
            byte[] expected;
            try
            {
                expected = Convert.FromHexString(expectedHash);
            }
            catch (FormatException)
            {
                return false;
            }
            return CryptographicOperations.FixedTimeEquals(actual, expected);
        }

        private static void AppendBinding(
            IncrementalHash hash,
            HairSaveBinding binding)
        {
            if (binding == null)
            {
                throw new ArgumentNullException(nameof(binding));
            }
            AppendString(hash, binding.SessionId);
            AppendInt64(hash, binding.LifecycleGeneration);
            AppendString(hash, binding.AttemptId);
            AppendInt64(hash, binding.AttemptGeneration);
            AppendString(hash, binding.SlotId);
            AppendString(hash, binding.SaveSignature);
        }

        private static void AppendString(
            IncrementalHash hash,
            string value)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(value ?? string.Empty);
            AppendInt32(hash, bytes.Length);
            hash.AppendData(bytes);
        }

        private static void AppendInt32(IncrementalHash hash, int value)
        {
            byte[] bytes = new byte[sizeof(int)];
            BinaryPrimitives.WriteInt32BigEndian(bytes, value);
            hash.AppendData(bytes);
        }

        private static void AppendInt64(IncrementalHash hash, long value)
        {
            byte[] bytes = new byte[sizeof(long)];
            BinaryPrimitives.WriteInt64BigEndian(bytes, value);
            hash.AppendData(bytes);
        }

        private static string ToLowerHex(byte[] value)
        {
            return Convert.ToHexString(value).ToLowerInvariant();
        }
    }

    internal static class HairAppearanceValidation
    {
        public static bool IsValidBinding(HairSaveBinding binding)
        {
            return binding != null
                && IsSafeString(binding.SessionId, 160, false)
                && binding.LifecycleGeneration >= 0
                && IsSafeString(binding.AttemptId, 160, true)
                && binding.AttemptGeneration >= 0
                && IsSafeString(binding.SlotId, 160, false)
                && IsSafeString(binding.SaveSignature, 256, false);
        }

        public static bool IsValidSnapshot(
            HairAuthoritativeSnapshot snapshot)
        {
            if (snapshot == null
                || !IsValidBinding(snapshot.Binding)
                || snapshot.Revision < 0
                || snapshot.Generation < 0
                || !IsSafeString(snapshot.CurrentHair, 160, false)
                || snapshot.Catalog == null
                || snapshot.Catalog.Count == 0
                || snapshot.Catalog.Count > 1024)
            {
                return false;
            }

            bool currentFound = false;
            for (int i = 0; i < snapshot.Catalog.Count; i++)
            {
                HairCatalogEntry entry = snapshot.Catalog[i];
                if (entry == null
                    || !IsSafeString(entry.Identifier, 160, false)
                    || !IsSafeString(entry.DisplayName, 160, false))
                {
                    return false;
                }
                if (string.Equals(
                    entry.Identifier,
                    snapshot.CurrentHair,
                    StringComparison.Ordinal))
                {
                    currentFound = true;
                }
            }
            return currentFound;
        }

        public static bool CatalogContains(
            HairAuthoritativeSnapshot snapshot,
            string identifier)
        {
            if (snapshot == null || snapshot.Catalog == null)
            {
                return false;
            }
            for (int i = 0; i < snapshot.Catalog.Count; i++)
            {
                HairCatalogEntry entry = snapshot.Catalog[i];
                if (entry != null
                    && string.Equals(
                        entry.Identifier,
                        identifier,
                        StringComparison.Ordinal))
                {
                    return true;
                }
            }
            return false;
        }

        public static bool IsSafeString(
            string value,
            int maxLength,
            bool allowEmpty)
        {
            if (value == null
                || value.Length > maxLength
                || (!allowEmpty && value.Length == 0))
            {
                return false;
            }
            for (int i = 0; i < value.Length; i++)
            {
                if (char.IsControl(value[i]))
                {
                    return false;
                }
            }
            return true;
        }

        public static bool IsSha256(string value)
        {
            if (value == null || value.Length != 64)
            {
                return false;
            }
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool digit = c >= '0' && c <= '9';
                bool lower = c >= 'a' && c <= 'f';
                if (!digit && !lower)
                {
                    return false;
                }
            }
            return true;
        }

        public static bool PreviewHashIsAuthentic(
            HairAppearancePreview preview)
        {
            if (preview == null
                || !IsSafeString(preview.TransactionId, 160, false)
                || !IsValidBinding(preview.Binding)
                || !IsSafeString(preview.BeforeHair, 160, false)
                || !IsSafeString(preview.AfterHair, 160, false)
                || preview.ExpectedRevision < 0
                || preview.ExpectedGeneration < 0
                || !IsSha256(preview.ExpectedSnapshotHash)
                || !IsSha256(preview.PreviewHash))
            {
                return false;
            }

            string expected = HairAppearanceHashing.ComputePreviewHash(
                preview.TransactionId,
                preview.Binding,
                preview.BeforeHair,
                preview.AfterHair,
                preview.ExpectedRevision,
                preview.ExpectedGeneration,
                preview.ExpectedSnapshotHash);
            return string.Equals(
                expected,
                preview.PreviewHash,
                StringComparison.Ordinal);
        }
    }
}
