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
//
// Correlation id (Phase 2b-ext):
//   请求若携带 number 类型的 "requestId", config_set_resp 会原样回显.
//   前端以此按请求关联 applyFn, 保证连点/乱序场景下每个响应对齐自己的请求.
//
// currentValue (Plan A+):
//   config_set_resp 无论 ok/失败都附带 "currentValue" = 服务端当前真实值 (已做过所有 rollback).
//   前端对 key 的最终 UI 状态无条件按 currentValue 对齐, 不再依赖本地 prior 快照——
//   这样"连续失败级联"/"optimistic 中间态残留"等一类由客户端 prior 捕获时机错位导致
//   的漂移, 协议层直接被消灭. 未知 key / 无 userPrefs 等路径下 currentValue 省略.

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
            // requestId 可选, 前端带的话原样回显用于 resp 匹配
            JToken reqIdTok = msg["requestId"];
            long? requestId = (reqIdTok != null && reqIdTok.Type == JTokenType.Integer)
                ? (long?)reqIdTok.Value<long>() : null;
            if (string.IsNullOrEmpty(key))
            {
                // key 缺失, 无法给出 currentValue
                PostConfigSetResp(bootForm, null, requestId, false, "key_missing", null);
                return;
            }
            if (userPrefs == null)
            {
                // userPrefs 不可用也无从报 currentValue
                PostConfigSetResp(bootForm, key, requestId, false, "userprefs_unavailable", null);
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
                        if (!IsBool(val)) { PostConfigSetResp(bootForm, key, requestId, false, "bad_value", GetCurrentJValue(userPrefs, key)); return; }
                        userPrefs.IntroEnabled = val.Value<bool>();
                        break;
                    case "lastPlayedSlot":
                        // 允许 null 清空 (first-boot 或重置). 其他类型视为错误。
                        if (val == null || val.Type == JTokenType.Null) userPrefs.LastPlayedSlot = null;
                        else if (val.Type == JTokenType.String) userPrefs.LastPlayedSlot = val.Value<string>();
                        else { PostConfigSetResp(bootForm, key, requestId, false, "bad_value", GetCurrentJValue(userPrefs, key)); return; }
                        break;
                    case "sfxEnabled":
                        if (!IsBool(val)) { PostConfigSetResp(bootForm, key, requestId, false, "bad_value", GetCurrentJValue(userPrefs, key)); return; }
                        userPrefs.SfxEnabled = val.Value<bool>();
                        break;
                    case "ambientEnabled":
                        if (!IsBool(val)) { PostConfigSetResp(bootForm, key, requestId, false, "bad_value", GetCurrentJValue(userPrefs, key)); return; }
                        userPrefs.AmbientEnabled = val.Value<bool>();
                        break;
                    case "uiFontScale":
                        if (val == null || (val.Type != JTokenType.Float && val.Type != JTokenType.Integer))
                        {
                            PostConfigSetResp(bootForm, key, requestId, false, "bad_value", GetCurrentJValue(userPrefs, key));
                            return;
                        }
                        userPrefs.UiFontScale = UserPrefs.ClampFontScale(val.Value<double>());
                        break;
                    default:
                        // 未知 key: 无法给 currentValue (不知道用户意图的 key 对应哪个字段)
                        PostConfigSetResp(bootForm, key, requestId, false, "unknown_key", null);
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
                    // currentValue = 回滚后真实值 (与磁盘一致)
                    PostConfigSetResp(bootForm, key, requestId, false, "save_failed", GetCurrentJValue(userPrefs, key));
                    return;
                }
                // 成功: currentValue = 新写入的值 (和 desired 一致, 前端 apply 是幂等 no-op)
                PostConfigSetResp(bootForm, key, requestId, true, null, GetCurrentJValue(userPrefs, key));
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
                PostConfigSetResp(bootForm, key, requestId, false, "exception", GetCurrentJValue(userPrefs, key));
            }
        }

        /// <summary>根据 key 返回 userPrefs 当前真实值的 JToken 形式.
        /// 用于 config_set_resp.currentValue, 让前端无条件按服务端权威值对齐 UI.
        /// 未知 key / 空 userPrefs 返回 null, 由调用方自行判断是否在 resp 里省略 currentValue.</summary>
        private static JToken GetCurrentJValue(UserPrefs userPrefs, string key)
        {
            if (userPrefs == null || string.IsNullOrEmpty(key)) return null;
            switch (key)
            {
                case "introEnabled":   return new JValue(userPrefs.IntroEnabled);
                case "lastPlayedSlot":
                    // null 字段要显式序列化为 JSON null (不要省略字段 —— 前端需区分"字段缺失"和"字段=null")
                    return userPrefs.LastPlayedSlot != null
                        ? (JToken)new JValue(userPrefs.LastPlayedSlot)
                        : (JToken)JValue.CreateNull();
                case "sfxEnabled":     return new JValue(userPrefs.SfxEnabled);
                case "ambientEnabled": return new JValue(userPrefs.AmbientEnabled);
                case "uiFontScale":    return new JValue(userPrefs.UiFontScale);
                default: return null;
            }
        }

        private static bool IsBool(JToken val)
        {
            return val != null && val.Type == JTokenType.Boolean;
        }

        private static void PostConfigSetResp(BootstrapPanel bootForm, string key, long? requestId, bool ok, string err, JToken currentValue)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "config_set_resp";
            if (key != null) obj["key"] = key;
            if (requestId.HasValue) obj["requestId"] = requestId.Value;
            obj["ok"] = ok;
            if (!ok && err != null) obj["error"] = err;
            // currentValue: null 表示服务端无法给出权威值 (未知 key / userPrefs 不可用).
            // 其他所有情况都附带真实值 (已 rollback 后), 前端无条件 apply 对齐.
            if (currentValue != null) obj["currentValue"] = currentValue;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }
    }
}
