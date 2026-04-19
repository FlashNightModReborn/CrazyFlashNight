// BMH 拆分：config_set。
// 前端 send({cmd:'config_set', key:'introEnabled', value:true/false}) 等.
// key 白名单:
//   introEnabled (bool), lastPlayedSlot (string | null),
//   sfxEnabled (bool), ambientEnabled (bool),
//   uiFontScale (number, clamped to [FontScaleMin..FontScaleMax])
//
// 协议错误语义 (所有键统一)：
//   unknown_key   — key 不在白名单
//   bad_value     — value 类型与 key 期望不匹配 (bool 键传了 string 等)
//   save_failed   — 内存值已更新但 %LOCALAPPDATA% 落盘失败 (磁盘满 / 权限问题)
//   exception     — 其他意外错误
//   ok:true       — 已落盘, 可以认为"下次启动仍是这个值"

using System;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Config;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class ConfigCommandHandler
    {
        internal static void HandleConfigSet(JObject msg, BootstrapPanel bootForm, UserPrefs userPrefs)
        {
            string key = msg.Value<string>("key");
            if (string.IsNullOrEmpty(key))
            {
                PostConfigSetResp(bootForm, null, false, "key_missing");
                return;
            }
            if (userPrefs == null)
            {
                PostConfigSetResp(bootForm, key, false, "userprefs_unavailable");
                return;
            }
            JToken val = msg["value"];
            // 快照所有字段: 磁盘写入失败时回滚内存, 保证 userPrefs 内存 == 磁盘真实状态.
            // 不然 save_failed 回包回得对, 但下次 list_resp 又把脏内存推回前端, 变成幽灵生效状态.
            string      snapLastPlayedSlot = userPrefs.LastPlayedSlot;
            bool        snapIntroEnabled   = userPrefs.IntroEnabled;
            bool        snapSfxEnabled     = userPrefs.SfxEnabled;
            bool        snapAmbientEnabled = userPrefs.AmbientEnabled;
            double      snapUiFontScale    = userPrefs.UiFontScale;
            try
            {
                switch (key)
                {
                    case "introEnabled":
                        if (!IsBool(val)) { PostConfigSetResp(bootForm, key, false, "bad_value"); return; }
                        userPrefs.IntroEnabled = val.Value<bool>();
                        break;
                    case "lastPlayedSlot":
                        // 允许 null 清空 (first-boot 或重置). 其他类型视为错误。
                        if (val == null || val.Type == JTokenType.Null) userPrefs.LastPlayedSlot = null;
                        else if (val.Type == JTokenType.String) userPrefs.LastPlayedSlot = val.Value<string>();
                        else { PostConfigSetResp(bootForm, key, false, "bad_value"); return; }
                        break;
                    case "sfxEnabled":
                        if (!IsBool(val)) { PostConfigSetResp(bootForm, key, false, "bad_value"); return; }
                        userPrefs.SfxEnabled = val.Value<bool>();
                        break;
                    case "ambientEnabled":
                        if (!IsBool(val)) { PostConfigSetResp(bootForm, key, false, "bad_value"); return; }
                        userPrefs.AmbientEnabled = val.Value<bool>();
                        break;
                    case "uiFontScale":
                        if (val == null || (val.Type != JTokenType.Float && val.Type != JTokenType.Integer))
                        {
                            PostConfigSetResp(bootForm, key, false, "bad_value");
                            return;
                        }
                        userPrefs.UiFontScale = UserPrefs.ClampFontScale(val.Value<double>());
                        break;
                    default:
                        PostConfigSetResp(bootForm, key, false, "unknown_key");
                        return;
                }
                bool saved = userPrefs.Save();
                if (!saved)
                {
                    // 回滚内存到磁盘状态
                    userPrefs.LastPlayedSlot = snapLastPlayedSlot;
                    userPrefs.IntroEnabled   = snapIntroEnabled;
                    userPrefs.SfxEnabled     = snapSfxEnabled;
                    userPrefs.AmbientEnabled = snapAmbientEnabled;
                    userPrefs.UiFontScale    = snapUiFontScale;
                    PostConfigSetResp(bootForm, key, false, "save_failed");
                    return;
                }
                PostConfigSetResp(bootForm, key, true, null);
            }
            catch (Exception ex)
            {
                // 异常路径也回滚, 避免部分字段写入后抛异常残留脏状态
                userPrefs.LastPlayedSlot = snapLastPlayedSlot;
                userPrefs.IntroEnabled   = snapIntroEnabled;
                userPrefs.SfxEnabled     = snapSfxEnabled;
                userPrefs.AmbientEnabled = snapAmbientEnabled;
                userPrefs.UiFontScale    = snapUiFontScale;
                LogManager.Log("[BMH] config_set error key=" + key + " ex=" + ex.Message);
                PostConfigSetResp(bootForm, key, false, "exception");
            }
        }

        private static bool IsBool(JToken val)
        {
            return val != null && val.Type == JTokenType.Boolean;
        }

        private static void PostConfigSetResp(BootstrapPanel bootForm, string key, bool ok, string err)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "config_set_resp";
            if (key != null) obj["key"] = key;
            obj["ok"] = ok;
            if (!ok && err != null) obj["error"] = err;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }
    }
}
