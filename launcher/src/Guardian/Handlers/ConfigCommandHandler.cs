// BMH 拆分：config_set。
// 前端 send({cmd:'config_set', key:'introEnabled', value:true/false}) 等.
// key 白名单:
//   introEnabled (bool), lastPlayedSlot (string),
//   sfxEnabled (bool), ambientEnabled (bool),
//   uiFontScale (number, clamped to [FontScaleMin..FontScaleMax])
// 异常的 key 返回 config_set_resp {ok:false, error:"unknown_key"}.
// 异常的 value 类型返回 {ok:false, error:"bad_value"}.

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
            try
            {
                switch (key)
                {
                    case "introEnabled":
                        userPrefs.IntroEnabled = val != null && val.Type == JTokenType.Boolean && val.Value<bool>();
                        break;
                    case "lastPlayedSlot":
                        userPrefs.LastPlayedSlot = val != null && val.Type == JTokenType.String ? val.Value<string>() : null;
                        break;
                    case "sfxEnabled":
                        userPrefs.SfxEnabled = val != null && val.Type == JTokenType.Boolean && val.Value<bool>();
                        break;
                    case "ambientEnabled":
                        userPrefs.AmbientEnabled = val != null && val.Type == JTokenType.Boolean && val.Value<bool>();
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
                userPrefs.Save();
                PostConfigSetResp(bootForm, key, true, null);
            }
            catch (Exception ex)
            {
                LogManager.Log("[BMH] config_set error key=" + key + " ex=" + ex.Message);
                PostConfigSetResp(bootForm, key, false, "exception");
            }
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
