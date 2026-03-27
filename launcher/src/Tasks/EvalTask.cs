using System;
using System.Threading;
using Microsoft.ClearScript;
using Microsoft.ClearScript.V8;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// ClearScript V8 替代 vm2 沙箱。
    /// 每次 eval 创建新引擎实例，1 秒超时。
    /// 响应：{success:true, result:<value>} 或 {success:false, error:"..."}
    /// </summary>
    public static class EvalTask
    {
        public static string Handle(JObject message)
        {
            string code = message.Value<string>("payload");
            if (string.IsNullOrEmpty(code))
                return Error("No code provided for eval");

            V8ScriptEngine engine = null;
            CancellationTokenSource cts = null;
            try
            {
                engine = new V8ScriptEngine();
                cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(1000));
                cts.Token.Register(delegate { engine.Interrupt(); });

                object result = engine.Evaluate(code);

                JObject resp = new JObject();
                resp["success"] = true;
                resp["result"] = result != null ? JToken.FromObject(result) : JValue.CreateNull();
                return resp.ToString(Newtonsoft.Json.Formatting.None);
            }
            catch (ScriptInterruptedException)
            {
                return Error("execution timed out");
            }
            catch (ScriptEngineException ex)
            {
                return Error(ex.Message);
            }
            catch (Exception ex)
            {
                return Error(ex.Message);
            }
            finally
            {
                if (cts != null) cts.Dispose();
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
