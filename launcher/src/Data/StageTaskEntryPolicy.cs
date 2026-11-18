using System.Linq;
using Newtonsoft.Json.Linq;
using static CF7Launcher.Data.MapRuleEvaluator;

namespace CF7Launcher.Data
{
    // Task acceptance, charges, and rollback stay in Flash. This class reads the
    // effective task definition just as the ordinary entry path reads StageInfo.
    internal sealed class StageTaskEntryPolicy
    {
        private readonly string taskId;
        private readonly bool dispatch, replayable;
        private readonly long money, kpoints, level;
        internal JObject Scope { get; }
        internal static bool Supports(string kind) => kind == "dispatch_board" || kind == "dungeon_task";

        internal StageTaskEntryPolicy(string kind, string stage, string difficulty, JObject selector, MapTaskCatalog catalog)
        {
            Need(selector != null && Supports(kind), "invalid_task_selector");
            Keys(selector, "taskId", "board", "mode");
            taskId = Text(selector, "taskId", 12);
            var task = catalog.Tasks[taskId] as JObject;
            Need(task != null && task["finish_requirements"] is JArray objectives && objectives.Count > 0, "task_data_unavailable");
            string[] target = ((string)task["finish_requirements"][0] ?? "").Split('#');
            Need(target.Length == 2 && target[0] == stage, "task_target_mismatch");
            dispatch = kind == "dispatch_board";
            Scope = new JObject { ["chains"]=new JArray(), ["clears"]=new JArray(), ["tasks"]=new JObject() };
            if (dispatch)
            {
                string board = Text(selector, "board", 80);
                var boards = task["dispatch_board"];
                Need(boards?.Type == JTokenType.String ? (string)boards == board : boards is JArray list && list.Values<string>().Contains(board), "board_mismatch");
                Need(difficulty == target[1], "invalid_difficulty");
                replayable = (bool?)task["dispatch_replayable"] == true;
                Scope["tasks"][taskId] = replayable ? new JArray("active","finished") : new JArray("active");
                return;
            }
            Need(((string)task["chain"] ?? "").Split('#')[0] == "委托", "not_dungeon_task");
            string mode = Text(selector, "mode", 16);
            Need(mode == "normal" || mode == "challenge", "invalid_difficulty");
            string expected = mode == "challenge" ? (string)task["challenge"]?["difficulty"] : target[1];
            Need(expected == difficulty && StageDifficulties.Contains(expected), "invalid_difficulty");
            money = Cost(task, "deposit", 0); kpoints = Cost(task, "Kdeposit", 0); level = Cost(task, "restricted_level", 1);
            Scope["assets"] = new JArray("money", "kpoints", "level");
        }
        private static long Cost(JObject task, string key, long fallback) =>
            task[key] == null ? fallback : System.Math.Max(fallback, Integer(task[key], key));
        internal string Rejection(JObject facts)
        {
            if (dispatch)
            {
                var player = facts["tasks"][taskId];
                return (bool?)player["active"] == true || (replayable && (long?)player["finished"] > 0) ? null : "task_not_active";
            }
            var assets = facts["assets"];
            if (!((long?)assets["money"] >= money)) return "insufficient_money";
            if (!((long?)assets["level"] >= level)) return "insufficient_level";
            return kpoints > 0 && !((long?)assets["kpoints"] >= kpoints) ? "insufficient_kpoint" : null;
        }
    }
}
