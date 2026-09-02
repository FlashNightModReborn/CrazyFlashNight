using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    /// <summary>
    /// Host-owned, presentation-only mapping from immutable slotKey to a
    /// player-editable Unicode display name. Missing or malformed metadata
    /// never blocks save discovery or loading.
    /// </summary>
    public sealed class SaveSlotCatalog
    {
        public const int SchemaVersion = 1;
        public const int DisplayNameMinTextElements = 1;
        public const int DisplayNameMaxTextElements = 32;
        public const string FileName = ".slot-display-names.json";

        private readonly string _path;
        private readonly object _gate = new object();

        public SaveSlotCatalog(string savesDir)
        {
            if (string.IsNullOrEmpty(savesDir))
                throw new ArgumentNullException("savesDir");
            Directory.CreateDirectory(savesDir);
            _path = Path.Combine(savesDir, FileName);
        }

        public string CatalogPath { get { return _path; } }

        public static bool TryNormalizeDisplayName(
            string value,
            out string normalized,
            out string error)
        {
            normalized = null;
            error = null;
            if (value == null)
            {
                error = "display_name_missing";
                return false;
            }

            string candidate = value.Trim();
            if (candidate.Length == 0)
            {
                error = "display_name_empty";
                return false;
            }

            for (int i = 0; i < candidate.Length; i++)
            {
                if (char.IsControl(candidate[i]))
                {
                    error = "display_name_control_character";
                    return false;
                }
            }

            int count;
            try
            {
                count = StringInfo.ParseCombiningCharacters(candidate).Length;
            }
            catch (ArgumentException)
            {
                error = "display_name_invalid_unicode";
                return false;
            }

            if (count < DisplayNameMinTextElements
                || count > DisplayNameMaxTextElements)
            {
                error = "display_name_length";
                return false;
            }

            normalized = candidate;
            return true;
        }

        public IDictionary<string, string> ReadAll()
        {
            lock (_gate)
            {
                string error;
                Dictionary<string, string> map;
                if (!TryReadAllLocked(out map, out error))
                {
                    if (error != "metadata_not_found")
                        LogManager.Log("[SaveSlotCatalog] read fallback: " + error);
                    return new Dictionary<string, string>(StringComparer.Ordinal);
                }
                return map;
            }
        }

        public string ResolveDisplayName(
            string slotKey,
            string characterName,
            IDictionary<string, string> snapshot = null)
        {
            string stored;
            IDictionary<string, string> source = snapshot ?? ReadAll();
            if (source.TryGetValue(slotKey, out stored))
                return stored;

            string normalizedCharacter;
            string ignored;
            if (TryNormalizeDisplayName(characterName, out normalizedCharacter, out ignored))
                return normalizedCharacter;
            return slotKey;
        }

        public bool TrySetDisplayName(
            string slotKey,
            string displayName,
            out string normalized,
            out string error)
        {
            normalized = null;
            error = null;
            string exactSlot;
            if (!SaveSlotKey.TryValidateExisting(slotKey, out exactSlot))
            {
                error = "invalid_slot_key";
                return false;
            }
            if (!TryNormalizeDisplayName(displayName, out normalized, out error))
                return false;

            lock (_gate)
            {
                Dictionary<string, string> map;
                string readError;
                if (!TryReadAllLocked(out map, out readError)
                    && readError != "metadata_not_found")
                {
                    error = readError;
                    return false;
                }

                map[exactSlot] = normalized;
                JObject root = BuildDocument(map);
                if (!TryWriteAtomicLocked(root, out error))
                    return false;

                Dictionary<string, string> verified;
                string verifyError;
                if (!TryReadAllLocked(out verified, out verifyError))
                {
                    error = "metadata_verify_failed:" + verifyError;
                    return false;
                }
                string roundTrip;
                if (!verified.TryGetValue(exactSlot, out roundTrip)
                    || !string.Equals(roundTrip, normalized, StringComparison.Ordinal))
                {
                    error = "metadata_verify_mismatch";
                    return false;
                }
                return true;
            }
        }

        /// <summary>
        /// Removes the optional presentation override so the slot once again
        /// follows the character name stored in the authoritative save.
        /// Missing metadata or an already-absent entry is a successful no-op;
        /// malformed existing metadata remains fail-closed and is never
        /// overwritten.
        /// </summary>
        public bool TryRemoveDisplayName(
            string slotKey,
            out string error)
        {
            error = null;
            string exactSlot;
            if (!SaveSlotKey.TryValidateExisting(slotKey, out exactSlot))
            {
                error = "invalid_slot_key";
                return false;
            }

            lock (_gate)
            {
                Dictionary<string, string> map;
                string readError;
                if (!TryReadAllLocked(out map, out readError))
                {
                    if (readError == "metadata_not_found") return true;
                    error = readError;
                    return false;
                }
                if (!map.Remove(exactSlot)) return true;

                if (!TryWriteAtomicLocked(BuildDocument(map), out error))
                    return false;

                Dictionary<string, string> verified;
                string verifyError;
                if (!TryReadAllLocked(out verified, out verifyError))
                {
                    error = "metadata_verify_failed:" + verifyError;
                    return false;
                }
                if (verified.ContainsKey(exactSlot))
                {
                    error = "metadata_verify_mismatch";
                    return false;
                }
                return true;
            }
        }

        private bool TryReadAllLocked(
            out Dictionary<string, string> map,
            out string error)
        {
            map = new Dictionary<string, string>(StringComparer.Ordinal);
            error = null;
            if (!File.Exists(_path))
            {
                error = "metadata_not_found";
                return false;
            }

            try
            {
                JObject root = JObject.Parse(File.ReadAllText(_path, Encoding.UTF8));
                if (root.Value<int?>("v") != SchemaVersion)
                {
                    error = "metadata_schema_version";
                    return false;
                }
                JObject slots = root["slots"] as JObject;
                if (slots == null)
                {
                    error = "metadata_slots_missing";
                    return false;
                }

                foreach (JProperty property in slots.Properties())
                {
                    string slotKey;
                    if (!SaveSlotKey.TryValidateExisting(property.Name, out slotKey))
                        continue;
                    JObject entry = property.Value as JObject;
                    string raw = entry != null
                        ? entry.Value<string>("displayName")
                        : property.Value.Type == JTokenType.String
                            ? property.Value.Value<string>()
                            : null;
                    string normalized;
                    string ignored;
                    if (TryNormalizeDisplayName(raw, out normalized, out ignored))
                        map[slotKey] = normalized;
                }
                return true;
            }
            catch (Exception ex)
            {
                error = "metadata_parse_failed:" + ex.GetType().Name;
                return false;
            }
        }

        private static JObject BuildDocument(IDictionary<string, string> map)
        {
            JObject slots = new JObject();
            List<string> keys = new List<string>(map.Keys);
            keys.Sort(StringComparer.Ordinal);
            for (int i = 0; i < keys.Count; i++)
            {
                slots[keys[i]] = new JObject
                {
                    ["displayName"] = map[keys[i]]
                };
            }
            return new JObject
            {
                ["v"] = SchemaVersion,
                ["slots"] = slots
            };
        }

        private bool TryWriteAtomicLocked(JObject document, out string error)
        {
            error = null;
            string tmp = _path + ".tmp-" + Guid.NewGuid().ToString("N");
            try
            {
                File.WriteAllText(
                    tmp,
                    document.ToString(Formatting.None),
                    new UTF8Encoding(false));
                if (File.Exists(_path))
                    File.Replace(tmp, _path, null, true);
                else
                    File.Move(tmp, _path);
                return true;
            }
            catch (Exception ex)
            {
                error = "metadata_write_failed:" + ex.GetType().Name;
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
                return false;
            }
        }
    }
}
