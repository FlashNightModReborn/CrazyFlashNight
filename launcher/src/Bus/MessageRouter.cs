using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Bus
{
    /// <summary>
    /// 消息路由：按 task 字段分发到 Task 处理器。
    /// wrapResponse：注入 callId 到响应中。
    /// </summary>
    public class MessageRouter
    {
        public delegate string TaskHandler(JObject message);
        public delegate void AsyncTaskHandler(JObject message, Action<string> respond);

        private readonly Dictionary<string, TaskHandler> _syncHandlers;
        private readonly Dictionary<string, AsyncTaskHandler> _asyncHandlers;

        public event Action<string> OnConsoleResult;

        public MessageRouter()
        {
            _syncHandlers = new Dictionary<string, TaskHandler>();
            _asyncHandlers = new Dictionary<string, AsyncTaskHandler>();
        }

        public void RegisterSync(string taskType, TaskHandler handler)
        {
            _syncHandlers[taskType] = handler;
        }

        public void RegisterAsync(string taskType, AsyncTaskHandler handler)
        {
            _asyncHandlers[taskType] = handler;
        }

        /// <summary>
        /// 处理一条 JSON 消息，返回同步响应字符串。
        /// 异步任务通过 respond 回调返回。
        /// </summary>
        public string ProcessMessage(string json, Action<string> asyncRespond)
        {
            JObject msg;
            try
            {
                msg = JObject.Parse(json);
            }
            catch
            {
                return JsonError("Expected JSON format", null);
            }

            string taskType = msg.Value<string>("task");
            if (string.IsNullOrEmpty(taskType))
                return JsonError("No task type provided", null);

            // console_result 特殊处理：通知 ConsoleTask 的 FIFO 队列
            if (taskType == "console_result")
            {
                Action<string> handler = OnConsoleResult;
                if (handler != null)
                    handler(json);
                return null; // 不回复
            }

            JToken callIdToken = msg["callId"];

            // 同步任务
            TaskHandler syncHandler;
            if (_syncHandlers.TryGetValue(taskType, out syncHandler))
            {
                string result = syncHandler(msg);
                return WrapResponse(result, callIdToken);
            }

            // 异步任务
            AsyncTaskHandler asyncHandler;
            if (_asyncHandlers.TryGetValue(taskType, out asyncHandler))
            {
                asyncHandler(msg, delegate(string result)
                {
                    string wrapped = WrapResponse(result, callIdToken);
                    if (asyncRespond != null)
                        asyncRespond(wrapped);
                });
                return null; // 异步，不立即返回
            }

            return WrapResponse(JsonError("Unknown task type", null), callIdToken);
        }

        /// <summary>
        /// 复刻 socketServer.js wrapResponse：如果原始请求带 callId，注入到响应 JSON 中。
        /// </summary>
        private static string WrapResponse(string resultJson, JToken callId)
        {
            if (callId == null || resultJson == null)
                return resultJson;

            try
            {
                JObject obj = JObject.Parse(resultJson);
                obj["callId"] = callId;
                return obj.ToString(Formatting.None);
            }
            catch
            {
                return resultJson;
            }
        }

        public static string JsonError(string error, JToken callId)
        {
            JObject obj = new JObject();
            obj["success"] = false;
            obj["error"] = error;
            if (callId != null)
                obj["callId"] = callId;
            return obj.ToString(Formatting.None);
        }
    }
}
