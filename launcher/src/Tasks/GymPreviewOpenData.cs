using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>健身面板受控打开快照；仅接受 AS2 生成的 v2 目录与开窗 token。</summary>
    internal static class GymPreviewOpenData
    {
        private static readonly HashSet<string> Stations = new HashSet<string>(StringComparer.Ordinal)
        { "dummy", "dumbbell", "squat" };
        private static readonly HashSet<string> EquipmentSlots = new HashSet<string>(StringComparer.Ordinal)
        { "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备", "长枪", "手枪", "手枪2", "刀", "手雷" };
        private const long MaxSafeInteger = 9007199254740991L;
        private static readonly Regex SafeToken = new Regex("^[A-Za-z0-9._~-]{1,128}$", RegexOptions.Compiled);

        internal static JObject Build(string source, string extras)
        {
            if (source != "world_gym" || string.IsNullOrEmpty(extras) || extras.Length > 20000) return null;
            JObject outer;
            try { outer = JObject.Parse(extras, StrictJson); }
            catch (JsonException) { return null; }
            if (!Exact(outer, "stationId", "snapshotJson")) return null;
            string station = Text(outer["stationId"], 16);
            string raw = Text(outer["snapshotJson"], 16000);
            if (station == null || !Stations.Contains(station) || raw == null) return null;
            JObject snapshot;
            try { snapshot = JObject.Parse(raw, StrictJson); }
            catch (JsonException) { return null; }
            if (!Exact(snapshot, "v", "openToken", "stationId", "balances", "portrait", "projects", "pendingSession")
                || !Integer(snapshot["v"], 2, 2)
                || !ValidToken(snapshot["openToken"], "gym.open.")
                || Text(snapshot["stationId"], 16) != station
                || !ValidBalances(snapshot["balances"] as JObject)
                || !ValidPortrait(snapshot["portrait"] as JObject)
                || !ValidProjects(snapshot["projects"] as JArray, station)
                || !ValidPendingSession(snapshot["pendingSession"], station,
                    snapshot["projects"] as JArray)) return null;
            return new JObject
            {
                ["mode"] = "preview", ["source"] = source,
                ["stationId"] = station, ["snapshot"] = snapshot
            };
        }

        private static readonly JsonLoadSettings StrictJson = new JsonLoadSettings
        { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error };

        private static bool ValidBalances(JObject value)
        {
            return Exact(value, "money", "kpoint")
                && Integer(value["money"], 0, MaxSafeInteger)
                && Integer(value["kpoint"], 0, MaxSafeInteger);
        }

        private static bool ValidPortrait(JObject value)
        {
            if (!Exact(value, "gender", "equipment", "hair", "face")) return false;
            string gender = Text(value["gender"], 6);
            if ((gender != "male" && gender != "female")
                || OptionalText(value["hair"], 160) == null || OptionalText(value["face"], 160) == null)
                return false;
            var equipment = value["equipment"] as JObject;
            if (equipment == null || equipment.Properties().Count() > EquipmentSlots.Count) return false;
            foreach (JProperty item in equipment.Properties())
                if (!EquipmentSlots.Contains(item.Name) || Text(item.Value, 160) == null) return false;
            return true;
        }

        private static bool ValidProjects(JArray projects, string station)
        {
            if (projects == null || projects.Count == 0 || projects.Count > 13) return false;
            var indices = new HashSet<long>();
            foreach (JToken token in projects)
            {
                var item = token as JObject;
                if (!Exact(item, "id", "index", "rewardLabel", "rewardAmount", "currency",
                    "cost", "durationMs", "current", "cap", "baseExperience", "capExperience")) return false;
                if (!Integer(item["index"], 0, 12)) return false;
                long index = item["index"].Value<long>();
                if (!indices.Add(index) || Text(item["id"], 32) != station + "." + index) return false;
                string currency = Text(item["currency"], 8);
                if ((currency != "money" && currency != "kpoint")
                    || Text(item["rewardLabel"], 32) == null
                    || !Integer(item["rewardAmount"], 1, MaxSafeInteger)
                    || !Integer(item["cost"], 1, MaxSafeInteger)
                    || !Integer(item["durationMs"], 1, 3600000)
                    || !Integer(item["current"], 0, MaxSafeInteger)) return false;
                JToken cap = item["cap"];
                if (cap == null || (cap.Type != JTokenType.Null && !Integer(cap, 1, MaxSafeInteger))) return false;
                if (cap.Type == JTokenType.Null && Text(item["rewardLabel"], 32) != "技能点") return false;
                if (!Integer(item["baseExperience"], 0, MaxSafeInteger)
                    || !Integer(item["capExperience"], 0, MaxSafeInteger)
                    || (cap.Type == JTokenType.Null
                        ? item.Value<long>("baseExperience") != 0
                            || item.Value<long>("capExperience") != 0
                        : item.Value<long>("baseExperience") != 10000
                            || item.Value<long>("capExperience") != 50000))
                    return false;
            }
            return true;
        }

        private static bool ValidPendingSession(
            JToken pending, string station, JArray projects)
        {
            if (pending == null) return false;
            if (pending.Type == JTokenType.Null) return true;
            var session = pending as JObject;
            if (!Exact(session, "sessionToken", "stationId", "projectId", "phase")
                || !ValidToken(session["sessionToken"], "gym.session.")
                || Text(session["stationId"], 16) != station
                || Text(session["phase"], 16) != "save_pending") return false;
            string projectId = Text(session["projectId"], 32);
            return projectId != null && projects.Any(project =>
                Text(project?["id"], 32) == projectId);
        }

        private static bool Exact(JObject value, params string[] keys)
        {
            return value != null && value.Properties().Count() == keys.Length
                && keys.All(key => value.Property(key, StringComparison.Ordinal) != null);
        }

        private static string Text(JToken value, int limit)
        {
            if (value == null || value.Type != JTokenType.String) return null;
            string text = value.Value<string>();
            return !string.IsNullOrEmpty(text) && text.Length <= limit && !text.Any(char.IsControl) ? text : null;
        }

        private static string OptionalText(JToken value, int limit)
        {
            if (value == null || value.Type != JTokenType.String) return null;
            string text = value.Value<string>();
            return text != null && text.Length <= limit && !text.Any(char.IsControl) ? text : null;
        }

        private static bool ValidToken(JToken value, string prefix)
        {
            string token = Text(value, 128);
            return token != null && token.StartsWith(prefix, StringComparison.Ordinal)
                && SafeToken.IsMatch(token);
        }

        private static bool Integer(JToken value, long min, long max)
        {
            if (value == null || value.Type != JTokenType.Integer) return false;
            try { long number = value.Value<long>(); return number >= min && number <= max; }
            catch (Exception) { return false; }
        }
    }
}
