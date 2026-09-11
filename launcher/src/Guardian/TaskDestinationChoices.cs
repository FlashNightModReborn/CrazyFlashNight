using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>日常交付与关卡返回共用的只读选项协议，不包含导航执行权限。</summary>
    public sealed class TaskDestinationChoices
    {
        public string Status { get; internal set; }
        public string Token { get; internal set; }
        public IReadOnlyList<Choice> Choices { get; internal set; }
        public sealed class Choice
        {
            public string Id { get; internal set; }
            public string TaskName { get; internal set; }
            public string LocationName { get; internal set; }
            public string NpcName { get; internal set; }
            public string Label => LocationName + " · " + NpcName;
        }
        public static bool TryParse(JObject value, out TaskDestinationChoices result)
        {
            result = null;
            if (!HasExactKeys(value, "status", "token", "choices")) return false;
            string status;
            if (!TryReadText(value["status"], 16, false, out status)) return false;
            if (status != "none" && status != "loading" && status != "ready"
                && status != "error" && status != "confirming") return false;
            string token;
            if (!TryReadText(value["token"], 96, true, out token)
                || (token != "" && !TryReadOpaque(value["token"], 96, out token))) return false;
            JArray rows = value["choices"] as JArray;
            if (rows == null || rows.Count > 128
                || ((status == "none" || status == "loading" || status == "error") && rows.Count != 0)
                || ((status == "ready" || status == "confirming") && token == "")
                || (status == "confirming" && rows.Count == 0)
                || (status == "none" && token != "")) return false;
            var choices = new List<Choice>();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken item in rows)
            {
                JObject row = item as JObject;
                string id, taskName, locationName, npcName;
                if (!HasExactKeys(row, "id", "taskName", "locationName", "npcName")
                    || !TryReadOpaque(row["id"], 96, out id) || !ids.Add(id)
                    || !TryReadText(row["taskName"], 256, false, out taskName)
                    || !TryReadText(row["locationName"], 96, false, out locationName)
                    || !TryReadText(row["npcName"], 96, false, out npcName)) return false;
                choices.Add(new Choice { Id = id, TaskName = taskName, LocationName = locationName, NpcName = npcName });
            }
            result = new TaskDestinationChoices { Status = status, Token = token, Choices = choices.AsReadOnly() };
            return true;
        }

        internal static bool TryReadOpaque(JToken token, int maxLength, out string value)
        {
            value = token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
            if (string.IsNullOrEmpty(value) || value.Length > maxLength) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool allowed = (c >= 'A' && c <= 'Z')
                    || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9')
                    || c == '.' || c == '_' || c == '~' || c == '-' || c == ':';
                if (!allowed) return false;
            }
            return true;
        }

        private static bool TryReadText(
            JToken token, int maxLength, bool allowEmpty, out string value)
        {
            value = token != null && token.Type == JTokenType.String
                ? token.Value<string>() : null;
            if (value == null || value.Length > maxLength
                    || (!allowEmpty && value.Length == 0))
                return false;
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i])) return false;
            return true;
        }

        internal static bool HasExactKeys(JObject value, params string[] expected)
        {
            if (value == null || value.Count != expected.Length) return false;
            for (int i = 0; i < expected.Length; i++)
                if (value.Property(expected[i]) == null) return false;
            return true;
        }
    }
}
