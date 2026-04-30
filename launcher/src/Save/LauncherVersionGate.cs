// INV-2: 旧版反污染 gate
//
// 在 saves/.launcher-version-marker.json 记录当前 launcher 修复版本号 (CurrentSchemaVersion).
// 每次启动:
//   marker 不存在     → 视为首次启动 / 老版机, 触发提示 (建议跑 cf7-save-repair 一次)
//   marker 解析失败   → 同上 (兜底)
//   marker.version <  → 首次升级到当前修复版, 触发提示
//   marker.version >= → 沉默 (信任 saves/{slot}.json 干净)
//
// 决策后立刻 WriteMarker 写回当前版本, 提示只显示一次.
//
// CurrentSchemaVersion 升级时机: 任何破坏存档完整性的 bug 修复 commit (例如 C1a 的
// XmlSocketServer UTF-8 切割修复) 都应 +1, 让升级到该修复版的玩家收到一次老档检查提示.

using System;
using System.IO;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    public static class LauncherVersionGate
    {
        public const int CurrentSchemaVersion = 1;
        public const string MarkerFileName = ".launcher-version-marker.json";

        public class GateResult
        {
            public bool ShouldShowToast;
            public string Reason;
            public int PreviousVersion = -1;  // -1 = 未读到 / 不存在
        }

        public static GateResult Check(string savesDir)
        {
            if (string.IsNullOrEmpty(savesDir))
                throw new ArgumentNullException("savesDir");

            GateResult r = new GateResult();
            string markerPath = Path.Combine(savesDir, MarkerFileName);

            if (!File.Exists(markerPath))
            {
                r.ShouldShowToast = true;
                r.Reason = "no_marker";
                return r;
            }

            int prevVersion;
            try
            {
                string content = File.ReadAllText(markerPath, Encoding.UTF8);
                JObject obj = JObject.Parse(content);
                JToken vt = obj["version"];
                if (vt == null || vt.Type != JTokenType.Integer)
                {
                    r.ShouldShowToast = true;
                    r.Reason = "marker_invalid_format";
                    return r;
                }
                prevVersion = vt.Value<int>();
            }
            catch (Exception)
            {
                r.ShouldShowToast = true;
                r.Reason = "marker_parse_error";
                return r;
            }

            r.PreviousVersion = prevVersion;
            if (prevVersion < CurrentSchemaVersion)
            {
                r.ShouldShowToast = true;
                r.Reason = "version_upgrade_from_" + prevVersion;
            }
            else
            {
                r.ShouldShowToast = false;
                r.Reason = "marker_current";
            }
            return r;
        }

        public static void WriteMarker(string savesDir)
        {
            if (string.IsNullOrEmpty(savesDir))
                throw new ArgumentNullException("savesDir");
            if (!Directory.Exists(savesDir))
                Directory.CreateDirectory(savesDir);

            string markerPath = Path.Combine(savesDir, MarkerFileName);
            string tmpPath = markerPath + ".tmp";

            JObject obj = new JObject();
            obj["version"] = CurrentSchemaVersion;
            obj["writtenAt"] = DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'");

            File.WriteAllText(tmpPath, obj.ToString(Formatting.None), new UTF8Encoding(false));
            if (File.Exists(markerPath))
                File.Delete(markerPath);
            File.Move(tmpPath, markerPath);
        }
    }
}
