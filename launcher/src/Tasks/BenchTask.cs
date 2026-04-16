using System;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Lightweight latency bench hooks used by protocol smoke tests.
    /// The goal is to measure transport overhead without perturbing
    /// production task handlers or game logic.
    /// </summary>
    public sealed class BenchTask
    {
        private readonly XmlSocketServer _socket;

        public BenchTask(XmlSocketServer socket)
        {
            _socket = socket;
        }

        /// <summary>
        /// Synchronous JSON route benchmark.
        /// </summary>
        public string HandleSync(JObject message)
        {
            JObject payload = message.Value<JObject>("payload");
            string token = payload != null ? payload.Value<string>("token") : null;
            if (!string.IsNullOrEmpty(token))
            {
                long recvUs = BenchTrace.NowUs();
                long sendUs = BenchTrace.NowUs();
                BenchTrace.LogEcho("json_sync", token, recvUs, sendUs);
            }
            return BuildSuccess("bench_sync", payload);
        }

        /// <summary>
        /// Async JSON route benchmark. Mirrors archive/data_query style by
        /// hopping onto ThreadPool before responding.
        /// </summary>
        public void HandleAsync(JObject message, Action<string> respond)
        {
            JObject payload = message.Value<JObject>("payload");
            ThreadPool.QueueUserWorkItem(delegate
            {
                string token = payload != null ? payload.Value<string>("token") : null;
                long recvUs = BenchTrace.NowUs();
                long sendUs = BenchTrace.NowUs();
                if (!string.IsNullOrEmpty(token))
                    BenchTrace.LogEcho("json_async", token, recvUs, sendUs);
                respond(BuildSuccess("bench_async", payload));
            });
        }

        /// <summary>
        /// Fire-and-forget JSON route benchmark. Used together with
        /// sendTaskToNode/sendSocketMessage from AS2. The handler actively
        /// pushes an ack back to Flash, but returns null so the original
        /// fire-and-forget semantics stay intact.
        /// </summary>
        public string HandlePush(JObject message)
        {
            JObject payload = message.Value<JObject>("payload");
            string mode = payload != null ? payload.Value<string>("mode") : null;
            string token = payload != null ? payload.Value<string>("token") : null;
            string action = payload != null ? payload.Value<string>("action") : null;

            if (string.IsNullOrEmpty(mode))
                mode = "cmd";
            if (token == null)
                token = "";

            if (mode == "k")
                PushK(token);
            else
                PushCmd(token, action);

            return null;
        }

        private void PushCmd(string token, string action)
        {
            long recvUs = BenchTrace.NowUs();
            JObject msg = new JObject();
            msg["task"] = "cmd";
            msg["action"] = string.IsNullOrEmpty(action) ? "benchAck" : action;
            msg["token"] = token;
            long sendUs = BenchTrace.NowUs();
            BenchTrace.LogEcho("json_push_cmd", token, recvUs, sendUs);
            _socket.Send(msg.ToString(Formatting.None) + "\0");
        }

        private void PushK(string token)
        {
            long recvUs = BenchTrace.NowUs();
            // K payload v2:
            //   chr(cmdId+0x20) \x01 {typed} \x02 {hints}
            // cmdId=0 => chr(0x20), hints carries the benchmark token.
            string payload = ((char)0x20).ToString() + "\x01\x02" + token;
            long sendUs = BenchTrace.NowUs();
            BenchTrace.LogEcho("json_push_k", token, recvUs, sendUs);
            _socket.Send("K" + payload + "\0");
        }

        private static string BuildSuccess(string task, JObject payload)
        {
            JObject obj = new JObject();
            obj["success"] = true;
            obj["task"] = task;
            if (payload != null)
                obj["echo"] = payload.DeepClone();
            return obj.ToString(Formatting.None);
        }
    }
}
