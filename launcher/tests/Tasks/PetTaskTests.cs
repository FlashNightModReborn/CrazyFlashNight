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
    // 战宠面板桥接（PetTask）的传输层底线验证：cmd→action 映射、双层 callId 往返、
    // 断线/未知命令错误回包。注意：进阶完成度等业务逻辑在 AS2(PetPanelService) 侧，本套不覆盖。
    public class PetTaskTests
    {
        private const string PanelInstance = "panel.team.pet.1";

        [Theory]
        [InlineData("zombie")]
        [InlineData("thief")]
        [InlineData("military")]
        public void DogForm_UsesTrustedActionAndKeepsExactInstance(string form)
        {
            string sent = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));
            var request = Request("{\"callId\":\"dog-form\",\"slotIndex\":2,\"action\":\"petDelete\"}");
            request["dogForm"] = form;
            task.HandleWebRequest("change_dog_form", request);
            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("petChangeDogForm", (string)msg["action"]);
            Assert.Equal(form, (string)msg["dogForm"]);
            Assert.Equal(2, (int)msg["slotIndex"]);
        }

        [Theory]
        [InlineData("warlord")]
        [InlineData("")]
        [InlineData(null)]
        public void DogForm_RejectsUnknownFormWithoutSending(string form)
        {
            string sent = null, posted = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));
            task.SetPostToWeb(delegate(string json) { posted = json; });
            var request = Request("{\"callId\":\"dog-invalid\",\"slotIndex\":0}");
            request["dogForm"] = form;
            task.HandleWebRequest("change_dog_form", request);
            Assert.Null(sent);
            Assert.Equal("invalid_dog_form", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void LevelUp_ForwardsSingleCountTargetAndMaxMode()
        {
            var sent = new List<JObject>();
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent.Add(JObject.Parse(payload.TrimEnd('\0'))); }));

            task.HandleWebRequest("level_up", LevelRequest("{\"callId\":\"lv-1\",\"slotIndex\":0}"));
            task.HandleWebRequest("level_up", LevelRequest("{\"callId\":\"lv-5\",\"slotIndex\":1,\"count\":5}"));
            task.HandleWebRequest("level_up", LevelRequest("{\"callId\":\"lv-t\",\"slotIndex\":2,\"targetLevel\":25}"));
            task.HandleWebRequest("level_up", LevelRequest("{\"callId\":\"lv-m\",\"slotIndex\":3,\"mode\":\"max\"}"));

            Assert.Equal(4, sent.Count);
            Assert.Equal("petLevelUp", (string)sent[0]["action"]);
            Assert.Equal(0, (int)sent[0]["slotIndex"]);
            Assert.Equal(5, (int)sent[1]["count"]);
            Assert.Equal(25, (int)sent[2]["targetLevel"]);
            Assert.Equal("max", (string)sent[3]["mode"]);
        }

        [Theory]
        [InlineData("{\"callId\":\"bad-1\"}", "invalid_slot")]
        [InlineData("{\"callId\":\"bad-2\",\"slotIndex\":-1}", "invalid_slot")]
        [InlineData("{\"callId\":\"bad-3\",\"slotIndex\":0,\"count\":0}", "invalid_count")]
        [InlineData("{\"callId\":\"bad-4\",\"slotIndex\":0,\"count\":1.5}", "invalid_count")]
        [InlineData("{\"callId\":\"bad-5\",\"slotIndex\":0,\"targetLevel\":1}", "invalid_target_level")]
        [InlineData("{\"callId\":\"bad-6\",\"slotIndex\":0,\"mode\":\"all\"}", "invalid_level_up_mode")]
        [InlineData("{\"callId\":\"bad-7\",\"slotIndex\":0,\"count\":5,\"mode\":\"max\"}", "invalid_level_up_request")]
        [InlineData("{\"callId\":\"bad-8\",\"slotIndex\":0,\"count\":9223372036854775808}", "invalid_count")]
        [InlineData("{\"callId\":\"bad-9\",\"slotIndex\":0,\"targetLevel\":9223372036854775808}", "invalid_target_level")]
        [InlineData("{\"callId\":\"bad-10\",\"slotIndex\":9223372036854775808}", "invalid_slot")]
        [InlineData("{\"callId\":\"bare\",\"slotIndex\":0,\"targetLevel\":25}", "stale_level_quote")]
        [InlineData("{\"callId\":\"badquote\",\"slotIndex\":0,\"targetLevel\":25,\"levelQuote\":{\"token\":\"q\",\"fromLevel\":20,\"toLevel\":26,\"stoneCost\":225}}", "stale_level_quote")]
        public void LevelUp_RejectsInvalidPayloadWithoutSending(string json, string expectedError)
        {
            string sent = null, posted = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));
            task.SetPostToWeb(delegate(string payload) { posted = payload; });

            task.HandleWebRequest("level_up", Request(json));

            Assert.Null(sent);
            Assert.Equal(expectedError, (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void LevelUp_MalformedSuccessReply_ConvertsToRequiresReconcile()
        {
            string sent = null, posted = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));
            task.SetPostToWeb(delegate(string payload) { posted = payload; });

            task.HandleWebRequest("level_up", LevelRequest("{\"callId\":\"lv-bad-reply\",\"slotIndex\":1,\"count\":5}"));
            int fid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"pet_response\",\"callId\":" + fid + ",\"success\":true}"), null);

            var resp = JObject.Parse(posted);
            Assert.False((bool)resp["success"]);
            Assert.Equal("malformed_response", (string)resp["error"]);
            Assert.True((bool)resp["requiresReconcile"]);
        }

        [Fact]
        public void LevelUp_MismatchedTargetOrCountReply_ConvertsToRequiresReconcile()
        {
            string sent = null, posted = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));
            task.SetPostToWeb(delegate(string payload) { posted = payload; });

            task.HandleWebRequest("level_up", LevelRequest("{\"callId\":\"lv-target-drift\",\"slotIndex\":2,\"targetLevel\":25}"));
            int fid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"pet_response\",\"callId\":" + fid + ",\"success\":true,\"slotIndex\":2,\"oldLevel\":10,\"newLevel\":11,\"levelsGained\":1,\"stoneCost\":5}"), null);

            var resp = JObject.Parse(posted);
            Assert.False((bool)resp["success"]);
            Assert.Equal("malformed_response", (string)resp["error"]);
            Assert.True((bool)resp["requiresReconcile"]);

            task.HandleWebRequest("level_up", LevelRequest("{\"callId\":\"lv-nonbool\",\"slotIndex\":2,\"count\":5}"));
            fid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"pet_response\",\"callId\":" + fid + ",\"success\":\"true\",\"slotIndex\":2,\"newLevel\":15,\"levelsGained\":5,\"stoneCost\":10}"), null);
            resp = JObject.Parse(posted);
            Assert.False((bool)resp["success"]);
            Assert.Equal("malformed_response", (string)resp["error"]);
            Assert.True((bool)resp["requiresReconcile"]);
        }

        [Fact]
        public void HandleWebRequest_Disconnected_ReturnsPanelError()
        {
            string posted = null;
            var task = Bind(new PetTask(delegate { return false; }, delegate(string payload) { }));
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("snapshot", Request("{\"callId\":\"web-1\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("pets", (string)resp["panel"]);
            Assert.Equal("snapshot", (string)resp["cmd"]);
            Assert.Equal("web-1", (string)resp["callId"]);
            Assert.Equal(PanelInstance, (string)resp["panelInstanceId"]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("disconnected", (string)resp["error"]);
        }

        [Fact]
        public void HandleWebRequest_Snapshot_ForwardsPetSnapshotAction()
        {
            string sent = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));

            task.HandleWebRequest("snapshot", Request("{\"callId\":\"web-2\"}"));

            Assert.EndsWith("\0", sent);
            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("petSnapshot", (string)msg["action"]);
            Assert.Equal(1, (int)msg["dogFormVersion"]);
            Assert.Equal(1, (int)msg["callId"]);
            // 转发到 Flash 的消息不应残留 web 信封字段
            Assert.Null(msg["type"]);
            Assert.Null(msg["panel"]);
            Assert.Null(msg["cmd"]);
        }

        [Fact]
        public void HandleWebRequest_WorldAdopt_ForwardsPetWorldAdoptAction()
        {
            // 世界内招募（NPC 处确认）：cmd world_adopt → action petWorldAdopt，且夹带 action/task 不得覆盖。
            string sent = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));

            task.HandleWebRequest("world_adopt", Request("{\"callId\":\"web-wa\",\"action\":\"evil\",\"task\":\"evil\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("petWorldAdopt", (string)msg["action"]);
        }

        [Fact]
        public void HandleWebRequest_WebSuppliedActionTask_CannotOverrideTrustedAction()
        {
            // 安全反向用例：Web 夹带 action/task 不得覆盖 C# 由 cmd 派生的可信 action/信封
            // （AS2 裸分发 _root.gameCommands[action]，无白名单，否则可绕过 cmd→action 映射）。
            string sent = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));

            task.HandleWebRequest("snapshot",
                Request("{\"callId\":\"web-evil\",\"action\":\"petAdvance\",\"task\":\"evil\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("petSnapshot", (string)msg["action"]);
            Assert.Equal(1, (int)msg["dogFormVersion"]);
        }

        [Fact]
        public void HandleWebRequest_Advance_ForwardsExtraParams()
        {
            string sent = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));

            task.HandleWebRequest("advance", Request("{\"callId\":\"web-3\",\"slotIndex\":2,\"scheme\":\"影子刺客\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("petAdvance", (string)msg["action"]);
            Assert.Equal(2, (int)msg["slotIndex"]);
            Assert.Equal("影子刺客", (string)msg["scheme"]);
        }

        [Fact]
        public void HandleWebRequest_EquipWeapon_ForwardsLeaseBoundSource()
        {
            string sent = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));

            task.HandleWebRequest("equip_weapon", Request(
                "{\"callId\":\"web-equip\",\"slotIndex\":4,\"source\":{\"containerId\":\"背包\",\"slot\":7,\"expectedLease\":\"lease-7\"}}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("petEquipWeapon", (string)msg["action"]);
            Assert.Equal(4, (int)msg["slotIndex"]);
            Assert.Equal("背包", (string)msg["source"]["containerId"]);
            Assert.Equal(7, (int)msg["source"]["slot"]);
            Assert.Equal("lease-7", (string)msg["source"]["expectedLease"]);
        }

        [Fact]
        public void HandleWebRequest_WithdrawWeapon_ForwardsPetSlot()
        {
            string sent = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));

            task.HandleWebRequest("withdraw_weapon",
                Request("{\"callId\":\"web-withdraw\",\"slotIndex\":4}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("petWithdrawWeapon", (string)msg["action"]);
            Assert.Equal(4, (int)msg["slotIndex"]);
        }

        [Fact]
        public void HandleWebRequest_WeaponTooltip_ForwardsPetSlotAndLeaseBoundSource()
        {
            string sent = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));

            task.HandleWebRequest("weapon_tooltip", Request(
                "{\"callId\":\"web-weapon-tip\",\"slotIndex\":4,\"source\":{\"containerId\":\"背包\",\"slot\":7,\"expectedLease\":\"lease-7\"}}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("petWeaponTooltip", (string)msg["action"]);
            Assert.Equal(4, (int)msg["slotIndex"]);
            Assert.Equal("背包", (string)msg["source"]["containerId"]);
            Assert.Equal(7, (int)msg["source"]["slot"]);
            Assert.Equal("lease-7", (string)msg["source"]["expectedLease"]);
        }

        [Theory]
        [InlineData("equip_weapon")]
        [InlineData("withdraw_weapon")]
        [InlineData("weapon_tooltip")]
        public void WebOverlayRoute_ManagedWeaponCommandsReachPetTask(string command)
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            const string allowlistStart = "case \"snapshot\":";
            const string allowlistEnd = "string panel = parsed.Value<string>(\"panel\") ?? \"\";";
            int start = source.IndexOf(allowlistStart, StringComparison.Ordinal);
            int end = source.IndexOf(allowlistEnd, start, StringComparison.Ordinal);

            Assert.True(start >= 0, "Unable to locate WebOverlay panel command allowlist.");
            Assert.True(end > start, "Unable to locate end of WebOverlay panel command allowlist.");
            string allowlist = source.Substring(start, end - start);
            Assert.Contains("case \"" + command + "\":", allowlist);

            string petsRoute = source.Substring(end);
            Assert.Contains("else if (panel == \"pets\")", petsRoute);
            Assert.Contains("IsActivePetPanelOwner(activeName, activeInstance, parsed)", petsRoute);
            Assert.Contains("_petTask.HandleWebRequest(cmd, parsed)", petsRoute);
        }

        [Fact]
        public void ExactTeamOwner_RejectsInactiveForeignAndRetiredReplacement()
        {
            string sent = null;
            string posted = null;
            var task = Bind(new PetTask(
                delegate { return true; },
                delegate(string payload) { sent = payload; }));
            task.SetPostToWeb(delegate(string json) { posted = json; });

            JObject foreign = Request("{\"callId\":\"web-stale\",\"slotIndex\":4}");
            foreign["panelInstanceId"] = "panel.team.pet.stale";
            task.HandleWebRequest("withdraw_weapon", foreign);
            Assert.Null(sent);
            Assert.Equal("panel_instance_expired", JObject.Parse(posted).Value<string>("error"));

            Assert.True(task.BindPanelInstance("panel.team.pet.2"));
            posted = null;
            task.HandleWebRequest("equip_weapon", Request(
                "{\"callId\":\"web-retired\",\"slotIndex\":4,\"source\":{\"containerId\":\"背包\",\"slot\":7,\"expectedLease\":\"lease-7\"}}"));
            Assert.Null(sent);
            Assert.Equal("panel_instance_expired", JObject.Parse(posted).Value<string>("error"));

            JObject active = Request("{\"callId\":\"web-active\",\"slotIndex\":4}");
            active["panelInstanceId"] = "panel.team.pet.2";
            task.HandleWebRequest("withdraw_weapon", active);
            Assert.Equal("petWithdrawWeapon",
                JObject.Parse(sent.TrimEnd('\0')).Value<string>("action"));

            Assert.True(WebOverlayForm.IsActivePetPanelOwner(
                "team", "panel.team.pet.2", active));
            Assert.False(WebOverlayForm.IsActivePetPanelOwner(
                "pets", "panel.team.pet.2", active));
            Assert.False(WebOverlayForm.IsActivePetPanelOwner(
                "team", "panel.team.pet.other", active));
        }

        [Fact]
        public void HandleWebRequest_UnsupportedCmd_ReturnsError()
        {
            string posted = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { }));
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("bogus", Request("{\"callId\":\"web-4\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("pets", (string)resp["panel"]);
            Assert.Equal("bogus", (string)resp["cmd"]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("unsupported_cmd", (string)resp["error"]);
        }

        [Fact]
        public void HandleFlashResponse_MapsBackToOriginalWebCallId()
        {
            string sent = null;
            string posted = null;
            var task = Bind(new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; }));
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("deploy", Request("{\"callId\":\"web-5\",\"slotIndex\":0}"));
            int fid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            var flash = JObject.Parse("{\"task\":\"pet_response\",\"callId\":" + fid + ",\"success\":true,\"deployed\":true}");
            task.HandleFlashResponse(flash, delegate(string s) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("pets", (string)resp["panel"]);
            Assert.Equal("deploy", (string)resp["cmd"]);
            Assert.Equal("web-5", (string)resp["callId"]);
            Assert.Equal(PanelInstance, (string)resp["panelInstanceId"]);
            Assert.True((bool)resp["success"]);
            Assert.True((bool)resp["deployed"]);
            Assert.Null(resp["task"]);
        }

        [Fact]
        public void ReentrantFlashResponseDuringSend_DoesNotLeavePendingOrTimeout()
        {
            PetTask task = null;
            var posted = new List<JObject>();
            try
            {
                task = new PetTask(
                    delegate { return true; },
                    delegate(string payload)
                    {
                        JObject sent = JObject.Parse(payload.TrimEnd('\0'));
                        task.HandleFlashResponse(
                            new JObject
                            {
                                ["task"] = "pet_response",
                                ["callId"] = sent.Value<int>("callId"),
                                ["success"] = true,
                                ["deployed"] = true
                            },
                            delegate(string ignored) { });
                        return true;
                    },
                    null,
                    30);
                Bind(task);
                task.SetPostToWeb(delegate(string json)
                {
                    posted.Add(JObject.Parse(json));
                });

                task.HandleWebRequest(
                    "deploy",
                    Request("{\"callId\":\"web-reentrant\",\"slotIndex\":0}"));

                Assert.Equal(0, task.PendingCountForTest);
                Assert.Single(posted);
                Assert.Equal("web-reentrant", posted[0].Value<string>("callId"));
                Assert.True(posted[0].Value<bool>("success"));

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
            using (var task = new PetTask(
                delegate { return true; },
                delegate(string payload) { return false; },
                null,
                100))
            {
                Bind(task);
                task.SetPostToWeb(delegate(string json)
                {
                    posted.Add(JObject.Parse(json));
                });

                JObject request = Request(
                    "{\"callId\":\"web-unknown\",\"slotIndex\":0}");
                task.HandleWebRequest("deploy", request);

                Assert.Equal(0, task.PendingCountForTest);
                Assert.Single(posted);
                Assert.Equal("delivery_unknown", posted[0].Value<string>("error"));

                task.HandleWebRequest("deploy", request);
                Assert.Single(posted);
            }
        }

        private static string FindWebOverlaySource()
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string fromRepository = Path.Combine(
                    current.FullName,
                    "launcher",
                    "src",
                    "Guardian",
                    "WebOverlayForm.cs");
                if (File.Exists(fromRepository))
                    return fromRepository;

                string fromLauncher = Path.Combine(
                    current.FullName,
                    "src",
                    "Guardian",
                    "WebOverlayForm.cs");
                if (File.Exists(fromLauncher))
                    return fromLauncher;

                current = current.Parent;
            }

            throw new FileNotFoundException(
                "Unable to locate launcher/src/Guardian/WebOverlayForm.cs.");
        }

        private static JObject LevelRequest(string json)
        {
            JObject request = Request(json);
            int target = (int?)request["targetLevel"] ?? (20 + ((int?)request["count"] ?? 1));
            request["levelQuote"] = new JObject
            {
                ["token"] = "pet.quote.1", ["fromLevel"] = 20, ["toLevel"] = target, ["stoneCost"] = 225
            };
            return request;
        }

        [Theory]
        [InlineData("ok", true)]
        [InlineData("other_token", false)]
        [InlineData("wrong_base", false)]
        [InlineData("wrong_cost", false)]
        [InlineData("missing_binding", false)]
        public void LevelUp_SuccessMustMatchTheConfirmedQuote(string variant, bool accepted)
        {
            string sent = null, posted = null;
            using var task = Bind(new PetTask(() => true, payload => sent = payload));
            task.SetPostToWeb(payload => posted = payload);
            JObject request = LevelRequest("{\"callId\":\"bound\",\"slotIndex\":0,\"targetLevel\":25}");
            task.HandleWebRequest("level_up", request);
            JObject wire = JObject.Parse(sent.TrimEnd('\0'));
            Assert.True(JToken.DeepEquals(request["levelQuote"], wire["levelQuote"]));
            var response = new JObject
            {
                ["task"]="pet_response", ["callId"]=wire["callId"], ["success"]=true, ["slotIndex"]=0,
                ["oldLevel"]=variant == "wrong_base" ? 1 : 20, ["newLevel"]=25,
                ["levelsGained"]=variant == "wrong_base" ? 24 : 5, ["stoneCost"]=variant == "wrong_cost" ? 227 : 225,
                ["levelUpToken"]=variant == "other_token" ? "pet.quote.2" : "pet.quote.1"
            };
            if (variant == "missing_binding") response.Remove("levelUpToken");
            task.HandleFlashResponse(response, null);
            JObject result = JObject.Parse(posted);
            Assert.Equal(accepted, (bool)result["success"]);
            if (!accepted) Assert.True((bool)result["requiresReconcile"]);
        }

        private static PetTask Bind(PetTask task)
        {
            Assert.True(task.BindPanelInstance(PanelInstance));
            return task;
        }

        private static JObject Request(string json)
        {
            JObject request = JObject.Parse(json);
            request["panel"] = "pets";
            request["panelInstanceId"] = PanelInstance;
            return request;
        }
    }
}
