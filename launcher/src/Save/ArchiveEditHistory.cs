using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    // Called under the owning ArchiveTask lock/FIFO. A write-ahead record can only restore the
    // exact post-edit bytes and token. Keep the previously applicable entry if the next save fails.
    internal sealed class ArchiveEditHistory
    {
        private readonly string _folder;
        internal ArchiveEditHistory(string saves) => _folder = Path.Combine(saves, ".editor-undo");
        private string RecordPath(string slot) => Path.Combine(_folder, slot + ".json");
        private static string Digest(byte[] data) => Convert.ToHexString(SHA256.HashData(data));

        private JArray Read(string slot)
        {
            string path = RecordPath(slot);
            return File.Exists(path) ? JArray.Parse(File.ReadAllText(path, Encoding.UTF8)) : new JArray();
        }

        internal void Prepare(string slot, string shadowPath, string next)
        {
            if (!File.Exists(shadowPath)) return;
            byte[] before = File.ReadAllBytes(shadowPath);
            string priorHash = Digest(before);
            string afterHash = Digest(Encoding.UTF8.GetBytes(next));
            if (afterHash == priorHash) return;
            var prior = Read(slot).OfType<JObject>().FirstOrDefault(row => (string)row["after"] == priorHash);
            var rows = new JArray(new JObject {
                ["token"] = Guid.NewGuid().ToString("N"), ["after"] = afterHash, ["beforeHash"] = priorHash,
                ["before"] = Convert.ToBase64String(before)
            });
            if (prior != null) rows.Add(prior.DeepClone());
            Directory.CreateDirectory(_folder);
            DurableFileWriter.WriteAllText(RecordPath(slot), rows.ToString(Formatting.None), new UTF8Encoding(false));
        }

        private JObject Match(string slot, string shadowPath)
        {
            var rows = Read(slot);
            if (rows.Count == 0 || !File.Exists(shadowPath)) return null;
            string current = Digest(File.ReadAllBytes(shadowPath));
            return rows.OfType<JObject>().FirstOrDefault(row => (string)row["after"] == current);
        }

        internal string Token(string slot, string shadowPath) => (string)Match(slot, shadowPath)?["token"];

        internal bool TryRestore(string slot, string shadowPath, string token)
        {
            var row = Match(slot, shadowPath);
            if (row == null || !Guid.TryParseExact(token, "N", out _) || token != (string)row["token"]) return false;
            byte[] original = Convert.FromBase64String((string)row["before"]);
            if (Digest(original) != (string)row["beforeHash"]) return false;
            InvalidateDuring(slot, () => DurableFileWriter.WriteAllBytes(shadowPath, original));
            return true;
        }

        // Remove the token before another write can recreate matching bytes. A definite refusal
        // keeps the previous edit undoable. An unconfirmed commit must never re-arm stale history.
        internal void InvalidateDuring(string slot, Action write, Func<bool> mayRestore = null)
        {
            string path = RecordPath(slot);
            if (!File.Exists(path)) { write(); return; }
            byte[] previous = File.ReadAllBytes(path);
            File.Delete(path);
            try { write(); }
            catch (Exception error) when (error is not FileCommitUnconfirmedException)
            {
                if (mayRestore == null || mayRestore()) DurableFileWriter.WriteAllBytes(path, previous);
                throw;
            }
        }
    }
}
