using System;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Threading;

namespace CF7Launcher.Diagnostic
{
    internal static partial class FocusTrace
    {
        private static int[] _skillKeys = Array.Empty<int>();
        private static long _skillKeysAt;
        internal static bool IsSkillKey(uint key)
        {
            if (!Enabled || Environment.TickCount64 - Interlocked.Read(ref _skillKeysAt) > 5000) return false;
            foreach (int configured in Volatile.Read(ref _skillKeys)) if (key == configured) return true;
            return false;
        }
        private static void CaptureSkillLogBatch(string decoded)
        {
            string marker = "[SkillInputAS2] session=" + Session + " v=1 ";
            int count = 0;
            foreach (Match match in Regex.Matches(decoded, Regex.Escape(marker) + @"[^|&\r\n]{0,1024}"))
            {
                if (++count > 128) { Record("skill.transport_dropped", new { reason = "batch_limit" }); break; }
                string raw = match.Value;
                Record("skill.as2_observation", new { source = "http_log_batch", raw });
                if (!raw.Contains(" event=keys ", StringComparison.Ordinal)) continue;
                Match detail = Regex.Match(raw, @" detail=([^ ]*)");
                string[] values = Uri.UnescapeDataString(detail.Groups[1].Value).Split(',');
                if (values.Length != 12) continue;
                int[] keys = new int[12];
                for (int i = 0; i < keys.Length; i++)
                    keys[i] = int.TryParse(values[i], NumberStyles.None, CultureInfo.InvariantCulture, out int key)
                        && key > 0 && key <= 255 ? key : -1;
                Volatile.Write(ref _skillKeys, keys);
                Interlocked.Exchange(ref _skillKeysAt, Environment.TickCount64);
            }
        }
    }
}
