using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class MercTaskTests
    {
        private const string PanelInstance = "panel.team.merc.1";

        [Fact]
        public void HandleWebRequest_Disconnected_ReturnsOwnedPanelError()
        {
            string posted = null;
            var task = Bind(new MercTask(
                delegate { return false; }, delegate(string payload) { }));
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("snapshot", Request("{\"callId\":\"web-1\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", resp.Value<string>("type"));
            Assert.Equal("mercs", resp.Value<string>("panel"));
            Assert.Equal("snapshot", resp.Value<string>("cmd"));
            Assert.Equal("web-1", resp.Value<string>("callId"));
            Assert.Equal(PanelInstance, resp.Value<string>("panelInstanceId"));
            Assert.False(resp.Value<bool>("success"));
            Assert.Equal("disconnected", resp.Value<string>("error"));
        }

        [Theory]
        [InlineData("snapshot", "mercSnapshot")]
        [InlineData("hire_list", "mercHireList")]
        [InlineData("deploy", "mercDeploy")]
        [InlineData("dismiss", "mercDismiss")]
        [InlineData("hire", "mercHire")]
        [InlineData("world_hire", "mercWorldHire")]
        [InlineData("revive", "mercRevive")]
        [InlineData("equip_tooltip", "mercEquipTooltip")]
        public void HandleWebRequest_KnownCommand_ForwardsTrustedAction(
            string cmd, string action)
        {
            string sent = null;
            var task = Bind(new MercTask(
                delegate { return true; },
                delegate(string payload) { sent = payload; }));

            task.HandleWebRequest(cmd, Request(
                "{\"callId\":\"web-2\",\"action\":\"evil\",\"task\":\"evil\",\"page\":2}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", msg.Value<string>("task"));
            Assert.Equal(action, msg.Value<string>("action"));
            Assert.Equal(2, msg.Value<int>("page"));
            Assert.Null(msg["panel"]);
            Assert.Equal(PanelInstance, msg.Value<string>("panelInstanceId"));
        }

        [Fact]
        public void HandleWebRequest_Unsupported_ReturnsOwnedError()
        {
            string posted = null;
            var task = Bind(new MercTask(
                delegate { return true; }, delegate(string payload) { }));
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("bogus", Request("{\"callId\":\"web-3\"}"));

            var response = JObject.Parse(posted);
            Assert.Equal("unsupported_cmd", response.Value<string>("error"));
            Assert.Equal(PanelInstance, response.Value<string>("panelInstanceId"));
        }

        [Fact]
        public void HandleFlashResponse_RestoresWebCallAndOwner()
        {
            string sent = null;
            string posted = null;
            var task = Bind(new MercTask(
                delegate { return true; },
                delegate(string payload) { sent = payload; }));
            task.SetPostToWeb(delegate(string json) { posted = json; });
            task.HandleWebRequest(
                "deploy", Request("{\"callId\":\"web-4\",\"mercIndex\":1}"));
            int fid = JObject.Parse(sent.TrimEnd('\0')).Value<int>("callId");

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "merc_response",
                ["callId"] = fid,
                ["success"] = true
            }, delegate(string ignored) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("mercs", resp.Value<string>("panel"));
            Assert.Equal("deploy", resp.Value<string>("cmd"));
            Assert.Equal("web-4", resp.Value<string>("callId"));
            Assert.Equal(PanelInstance, resp.Value<string>("panelInstanceId"));
            Assert.Null(resp["task"]);
        }

        [Fact]
        public void HandleFlashResponse_WorldHire_PreservesHiredFlag()
        {
            string sent = null;
            string posted = null;
            var task = Bind(new MercTask(
                delegate { return true; },
                delegate(string payload) { sent = payload; }));
            task.SetPostToWeb(delegate(string json) { posted = json; });
            task.HandleWebRequest("world_hire", Request("{\"callId\":\"web-wh\"}"));
            int fid = JObject.Parse(sent.TrimEnd('\0')).Value<int>("callId");

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "merc_response",
                ["callId"] = fid,
                ["success"] = true,
                ["hired"] = true,
                ["mercName"] = "X"
            }, delegate(string ignored) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("world_hire", resp.Value<string>("cmd"));
            Assert.True(resp.Value<bool>("success"));
            Assert.True(resp.Value<bool>("hired"));
            Assert.Equal(PanelInstance, resp.Value<string>("panelInstanceId"));
        }

        [Fact]
        public void ExactTeamOwner_RejectsForeignReplacementAndLateResponse()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            var task = Bind(new MercTask(
                delegate { return true; },
                delegate(string payload)
                {
                    sent.Add(JObject.Parse(payload.TrimEnd('\0')));
                }));
            task.SetPostToWeb(delegate(string json)
            {
                posted.Add(JObject.Parse(json));
            });

            task.HandleWebRequest(
                "deploy", Request("{\"callId\":\"web-old\",\"mercIndex\":1}"));
            int oldFid = sent[0].Value<int>("callId");
            Assert.Equal(1, task.PendingCountForTest);

            const string replacement = "panel.team.merc.2";
            Assert.True(task.BindPanelInstance(replacement));
            Assert.Equal(0, task.PendingCountForTest);
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "merc_response",
                ["callId"] = oldFid,
                ["success"] = true,
                ["deployed"] = true
            }, delegate(string ignored) { });
            Assert.Empty(posted);

            task.HandleWebRequest(
                "deploy", Request("{\"callId\":\"web-retired\",\"mercIndex\":1}"));
            Assert.Single(posted);
            Assert.Equal("panel_instance_expired", posted[0].Value<string>("error"));
            Assert.Equal(PanelInstance, posted[0].Value<string>("panelInstanceId"));

            JObject active = Request("{\"callId\":\"web-active\",\"mercIndex\":1}");
            active["panelInstanceId"] = replacement;
            task.HandleWebRequest("deploy", active);
            Assert.Equal(2, sent.Count);
            int activeFid = sent[1].Value<int>("callId");
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "merc_response",
                ["callId"] = activeFid,
                ["success"] = true
            }, delegate(string ignored) { });
            Assert.Equal(2, posted.Count);
            Assert.Equal(replacement, posted[1].Value<string>("panelInstanceId"));
            Assert.Equal("web-active", posted[1].Value<string>("callId"));

            Assert.True(WebOverlayForm.IsActiveMercPanelOwner(
                "team", replacement, active));
            Assert.False(WebOverlayForm.IsActiveMercPanelOwner(
                "mercs", replacement, active));
            Assert.False(WebOverlayForm.IsActiveMercPanelOwner(
                "team", PanelInstance, active));
        }

        [Fact]
        public void WebOverlayRoute_RequiresActiveMercPanelOwner()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            int route = source.IndexOf(
                "else if (panel == \"mercs\")", StringComparison.Ordinal);
            Assert.True(route >= 0, "Unable to locate MercTask panel route.");
            string mercRoute = source.Substring(route);
            Assert.Contains(
                "IsActiveMercPanelOwner(activeName, activeInstance, parsed)",
                mercRoute);
            Assert.Contains("_mercTask.HandleWebRequest(cmd, parsed)", mercRoute);
            Assert.Contains("RespondPanelDomainError(parsed, \"panel_instance_expired\")", mercRoute);
        }

        [Fact]
        public void ReentrantFlashResponseDuringSend_DoesNotLeavePendingOrTimeout()
        {
            MercTask task = null;
            var posted = new List<JObject>();
            try
            {
                task = new MercTask(
                    delegate { return true; },
                    delegate(string payload)
                    {
                        JObject sent = JObject.Parse(payload.TrimEnd('\0'));
                        task.HandleFlashResponse(new JObject
                        {
                            ["task"] = "merc_response",
                            ["callId"] = sent.Value<int>("callId"),
                            ["success"] = true
                        }, delegate(string ignored) { });
                        return true;
                    },
                    30);
                Bind(task);
                task.SetPostToWeb(delegate(string json)
                {
                    posted.Add(JObject.Parse(json));
                });

                task.HandleWebRequest(
                    "deploy", Request("{\"callId\":\"web-reentrant\",\"mercIndex\":0}"));

                Assert.Equal(0, task.PendingCountForTest);
                Assert.Single(posted);
                Assert.Equal("web-reentrant", posted[0].Value<string>("callId"));
                Assert.Equal(PanelInstance, posted[0].Value<string>("panelInstanceId"));
                Thread.Sleep(100);
                Assert.Single(posted);
            }
            finally
            {
                if (task != null) task.Dispose();
            }
        }

        [Fact]
        public void DeliveryUnknown_ClearsPendingAndSuppressesDuplicateCallId()
        {
            var posted = new List<JObject>();
            using (var task = new MercTask(
                delegate { return true; },
                delegate(string payload) { return false; },
                100))
            {
                Bind(task);
                task.SetPostToWeb(delegate(string json)
                {
                    posted.Add(JObject.Parse(json));
                });
                JObject request = Request(
                    "{\"callId\":\"web-unknown\",\"mercIndex\":0}");

                task.HandleWebRequest("deploy", request);

                Assert.Equal(0, task.PendingCountForTest);
                Assert.Single(posted);
                Assert.Equal("delivery_unknown", posted[0].Value<string>("error"));
                Assert.Equal(PanelInstance, posted[0].Value<string>("panelInstanceId"));

                task.HandleWebRequest("deploy", request);
                Assert.Single(posted);
            }
        }

        private static MercTask Bind(MercTask task)
        {
            Assert.True(task.BindPanelInstance(PanelInstance));
            return task;
        }

        private static JObject Request(string json)
        {
            JObject request = JObject.Parse(json);
            request["panel"] = "mercs";
            request["panelInstanceId"] = PanelInstance;
            return request;
        }

        private static string FindWebOverlaySource()
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string fromRepository = Path.Combine(
                    current.FullName, "launcher", "src", "Guardian", "WebOverlayForm.cs");
                if (File.Exists(fromRepository)) return fromRepository;

                string fromLauncher = Path.Combine(
                    current.FullName, "src", "Guardian", "WebOverlayForm.cs");
                if (File.Exists(fromLauncher)) return fromLauncher;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                "Unable to locate launcher/src/Guardian/WebOverlayForm.cs.");
        }
    }
}
