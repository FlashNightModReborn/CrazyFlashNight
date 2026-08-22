using System;
using System.IO;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    // 战宠面板桥接（PetTask）的传输层底线验证：cmd→action 映射、双层 callId 往返、
    // 断线/未知命令错误回包。注意：进阶完成度等业务逻辑在 AS2(PetPanelService) 侧，本套不覆盖。
    public class PetTaskTests
    {
        [Fact]
        public void HandleWebRequest_Disconnected_ReturnsPanelError()
        {
            string posted = null;
            var task = new PetTask(delegate { return false; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-1\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("pets", (string)resp["panel"]);
            Assert.Equal("snapshot", (string)resp["cmd"]);
            Assert.Equal("web-1", (string)resp["callId"]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("disconnected", (string)resp["error"]);
        }

        [Fact]
        public void HandleWebRequest_Snapshot_ForwardsPetSnapshotAction()
        {
            string sent = null;
            var task = new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-2\"}"));

            Assert.EndsWith("\0", sent);
            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("petSnapshot", (string)msg["action"]);
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
            var task = new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("world_adopt", JObject.Parse("{\"callId\":\"web-wa\",\"action\":\"evil\",\"task\":\"evil\"}"));

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
            var task = new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("snapshot",
                JObject.Parse("{\"callId\":\"web-evil\",\"action\":\"petAdvance\",\"task\":\"evil\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("petSnapshot", (string)msg["action"]);
        }

        [Fact]
        public void HandleWebRequest_Advance_ForwardsExtraParams()
        {
            string sent = null;
            var task = new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("advance", JObject.Parse("{\"callId\":\"web-3\",\"slotIndex\":2,\"scheme\":\"影子刺客\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("petAdvance", (string)msg["action"]);
            Assert.Equal(2, (int)msg["slotIndex"]);
            Assert.Equal("影子刺客", (string)msg["scheme"]);
        }

        [Fact]
        public void HandleWebRequest_EquipWeapon_ForwardsLeaseBoundSource()
        {
            string sent = null;
            var task = new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("equip_weapon", JObject.Parse(
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
            var task = new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("withdraw_weapon",
                JObject.Parse("{\"callId\":\"web-withdraw\",\"slotIndex\":4}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("petWithdrawWeapon", (string)msg["action"]);
            Assert.Equal(4, (int)msg["slotIndex"]);
        }

        [Fact]
        public void HandleWebRequest_WeaponTooltip_ForwardsPetSlotAndLeaseBoundSource()
        {
            string sent = null;
            var task = new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("weapon_tooltip", JObject.Parse(
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
            Assert.Contains("_petTask.HandleWebRequest(cmd, parsed)", petsRoute);
        }

        [Fact]
        public void HandleWebRequest_UnsupportedCmd_ReturnsError()
        {
            string posted = null;
            var task = new PetTask(delegate { return true; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("bogus", JObject.Parse("{\"callId\":\"web-4\"}"));

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
            var task = new PetTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("deploy", JObject.Parse("{\"callId\":\"web-5\",\"slotIndex\":0}"));
            int fid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            var flash = JObject.Parse("{\"task\":\"pet_response\",\"callId\":" + fid + ",\"success\":true,\"deployed\":true}");
            task.HandleFlashResponse(flash, delegate(string s) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("pets", (string)resp["panel"]);
            Assert.Equal("deploy", (string)resp["cmd"]);
            Assert.Equal("web-5", (string)resp["callId"]);
            Assert.True((bool)resp["success"]);
            Assert.True((bool)resp["deployed"]);
            Assert.Null(resp["task"]);
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
    }
}
