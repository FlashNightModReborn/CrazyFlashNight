using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    /// <summary>
    /// One rotating, verified semantic snapshot per physical slot. This is a
    /// recovery artifact, not a second save authority or a history ledger.
    /// </summary>
    public sealed class RebuildBackupStore
    {
        public const int SchemaVersion = 1;
        public const string DirectoryName = ".rebuild-backups";

        private readonly string _directory;
        private readonly object _gate = new object();

        public RebuildBackupStore(string savesDir)
        {
            if (string.IsNullOrEmpty(savesDir))
                throw new ArgumentNullException("savesDir");
            _directory = Path.Combine(savesDir, DirectoryName);
        }

        public string GetBackupPath(string slotKey)
        {
            string exact;
            if (!SaveSlotKey.TryValidateExisting(slotKey, out exact))
                throw new ArgumentException("invalid slot key", "slotKey");
            return Path.Combine(_directory, exact + ".json");
        }

        public bool TryWriteLatest(
            string slotKey,
            string displayName,
            JObject snapshot,
            string source,
            out string path,
            out string error)
        {
            path = null;
            error = null;
            string exact;
            if (!SaveSlotKey.TryValidateExisting(slotKey, out exact))
            {
                error = "invalid_slot_key";
                return false;
            }
            string normalizedDisplay;
            if (!SaveSlotCatalog.TryNormalizeDisplayName(
                    displayName,
                    out normalizedDisplay,
                    out error))
                return false;
            if (snapshot == null)
            {
                error = "backup_snapshot_missing";
                return false;
            }
            if (string.IsNullOrEmpty(source))
            {
                error = "backup_source_missing";
                return false;
            }

            JObject normalized = snapshot.DeepClone() as JObject;
            SaveMigrator.NormalizeResolvedSnapshot(normalized);
            if (!SaveMigrator.ValidateResolvedSnapshot(normalized))
            {
                error = "backup_snapshot_invalid";
                return false;
            }

            string snapshotJson = normalized.ToString(Formatting.None);
            string hash = Sha256(snapshotJson);
            JObject document = new JObject
            {
                ["v"] = SchemaVersion,
                ["slotKey"] = exact,
                ["displayName"] = normalizedDisplay,
                ["createdAt"] = DateTime.UtcNow.ToString("o"),
                ["source"] = source,
                ["snapshotSha256"] = hash,
                ["snapshot"] = normalized
            };

            lock (_gate)
            {
                path = GetBackupPath(exact);
                string tmp = path + ".tmp-" + Guid.NewGuid().ToString("N");
                try
                {
                    Directory.CreateDirectory(_directory);
                    File.WriteAllText(
                        tmp,
                        document.ToString(Formatting.None),
                        new UTF8Encoding(false));
                    if (File.Exists(path))
                        File.Replace(tmp, path, null, true);
                    else
                        File.Move(tmp, path);
                }
                catch (Exception ex)
                {
                    error = "backup_write_failed:" + ex.GetType().Name;
                    try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
                    return false;
                }

                JObject verified;
                if (!TryReadAndValidate(path, exact, out verified, out error))
                    return false;
                return true;
            }
        }

        public bool TryReadLatest(
            string slotKey,
            out JObject document,
            out string error)
        {
            document = null;
            error = null;
            string exact;
            if (!SaveSlotKey.TryValidateExisting(slotKey, out exact))
            {
                error = "invalid_slot_key";
                return false;
            }
            lock (_gate)
            {
                return TryReadAndValidate(
                    GetBackupPath(exact),
                    exact,
                    out document,
                    out error);
            }
        }

        private static bool TryReadAndValidate(
            string path,
            string expectedSlot,
            out JObject document,
            out string error)
        {
            document = null;
            error = null;
            try
            {
                if (!File.Exists(path))
                {
                    error = "backup_not_found";
                    return false;
                }
                JObject parsed = JObject.Parse(File.ReadAllText(path, Encoding.UTF8));
                if (parsed.Value<int?>("v") != SchemaVersion
                    || parsed.Value<string>("slotKey") != expectedSlot)
                {
                    error = "backup_identity_mismatch";
                    return false;
                }
                JObject snapshot = parsed["snapshot"] as JObject;
                if (snapshot == null)
                {
                    error = "backup_snapshot_missing";
                    return false;
                }
                SaveMigrator.NormalizeResolvedSnapshot(snapshot);
                if (!SaveMigrator.ValidateResolvedSnapshot(snapshot))
                {
                    error = "backup_snapshot_invalid";
                    return false;
                }
                string actualHash = Sha256(snapshot.ToString(Formatting.None));
                if (!string.Equals(
                        actualHash,
                        parsed.Value<string>("snapshotSha256"),
                        StringComparison.Ordinal))
                {
                    error = "backup_hash_mismatch";
                    return false;
                }
                document = parsed;
                return true;
            }
            catch (Exception ex)
            {
                error = "backup_verify_failed:" + ex.GetType().Name;
                return false;
            }
        }

        private static string Sha256(string value)
        {
            using (SHA256 sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(value));
                StringBuilder sb = new StringBuilder(hash.Length * 2);
                for (int i = 0; i < hash.Length; i++)
                    sb.Append(hash[i].ToString("X2"));
                return sb.ToString();
            }
        }
    }
}
