using System;
using Microsoft.ClearScript;
using Microsoft.ClearScript.V8;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 正则匹配 — 使用 V8 执行以保证 JS 正则行为一致。
    /// 响应字段是 match（不是 result）：
    ///   成功有匹配: {success:true, match:[...]}
    ///   成功无匹配: {success:true, match:false}
    ///   失败: {success:false, error:"..."}
    /// </summary>
    public static class RegexTask
    {
        public static string Handle(JObject message)
        {
            string text = message.Value<string>("payload") ?? "";
            JObject extra = message.Value<JObject>("extra");
            string pattern = extra != null ? extra.Value<string>("pattern") : null;
            string flags = extra != null ? (extra.Value<string>("flags") ?? "") : "";

            if (string.IsNullOrEmpty(pattern))
                return Error("No pattern provided");

            V8ScriptEngine engine = null;
            try
            {
                engine = new V8ScriptEngine();

                // 注入参数并执行
                engine.Script.inputText = text;
                engine.Script.inputPattern = pattern;
                engine.Script.inputFlags = flags;

                object result = engine.Evaluate(
                    "(function() {" +
                    "  var r = new RegExp(inputPattern, inputFlags);" +
                    "  var m = r.exec(inputText);" +
                    "  if (m === null) return JSON.stringify({success:true, match:false});" +
                    "  return JSON.stringify({success:true, match:Array.prototype.slice.call(m)});" +
                    "})()");

                // result 是 JSON 字符串，直接返回
                return result != null ? result.ToString() : Error("null result");
            }
            catch (Exception ex)
            {
                return Error(ex.Message);
            }
            finally
            {
                if (engine != null) engine.Dispose();
            }
        }

        private static string Error(string msg)
        {
            JObject resp = new JObject();
            resp["success"] = false;
            resp["error"] = msg;
            return resp.ToString(Newtonsoft.Json.Formatting.None);
        }
    }
}
