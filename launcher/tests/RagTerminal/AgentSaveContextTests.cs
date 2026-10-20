using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using CF7Launcher.Data;
using CF7Launcher.Guardian;
using CF7Launcher.RagTerminal;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.RagTerminal
{
    /// <summary>
    /// 进程级槽位上下文单测：写入点（bind / 刷新绑定，以及 MapDomainTask 的 task_sync——后者在
    /// Tasks/MapDomainSessionTests 里就地断言）、非法形态不派生路径、换槽位立刻失效对话覆盖层缓存。
    /// </summary>
    public sealed class AgentSaveContextTests : IDisposable
    {
        private readonly string _root =
            Path.Combine(Path.GetTempPath(), "cf7-agent-save-context-" + Guid.NewGuid().ToString("N"));

        public AgentSaveContextTests()
        {
            Directory.CreateDirectory(_root);
            AgentSaveContext.Clear();
            AgentDialogueOverrides.Invalidate();
            LogManager.SetSink(line => { });
        }

        public void Dispose()
        {
            AgentSaveContext.Clear();
            AgentDialogueOverrides.Invalidate();
            LogManager.ResetSink();
            try { Directory.Delete(_root, true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }

        private void WriteOverlay(string slotKey, string json)
        {
            string dir = Path.Combine(_root, "data", "rag", "agent_saves", slotKey);
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, AgentDialogueOverrides.OverlayFileName), json);
        }

        private static Dictionary<string, List<DialogueGroup>> BaseIndex()
        {
            JArray subs = new JArray();
            subs.Add(new JObject { ["id"] = "", ["name"] = "Andy Law", ["title"] = "A兵团老大",
                ["char"] = "Andy Law", ["text"] = "基础台词", ["target"] = JValue.CreateNull(), ["imageurl"] = JValue.CreateNull() });
            return new Dictionary<string, List<DialogueGroup>>(StringComparer.Ordinal)
            {
                ["Andy Law"] = new List<DialogueGroup> { new DialogueGroup { TaskRequirement = 0, GroupId = "3", SubDialogues = subs } }
            };
        }

        [Fact]
        public void SetStoresSlotKeyAndClearResets()
        {
            Assert.Null(AgentSaveContext.CurrentSlotKey);
            AgentSaveContext.Set("slotA");
            Assert.Equal("slotA", AgentSaveContext.CurrentSlotKey);
            AgentSaveContext.Set("slotB");
            Assert.Equal("slotB", AgentSaveContext.CurrentSlotKey);
            AgentSaveContext.Clear();
            Assert.Null(AgentSaveContext.CurrentSlotKey);
        }

        [Fact]
        public void EmptyOrIllegalSlotShapesNeverBecomeCurrentSlot()
        {
            AgentSaveContext.Set("slotA");
            foreach (string value in new[] { null, "", "../slotA", "slot A", "存档一", new string('a', 129) })
            {
                AgentSaveContext.Set(value);
                Assert.Null(AgentSaveContext.CurrentSlotKey);   // 非法形态等同解绑，不派生覆盖层路径
                AgentSaveContext.Set("slotA");
            }
            AgentSaveContext.Set(new string('a', 128));
            Assert.Equal(new string('a', 128), AgentSaveContext.CurrentSlotKey);
        }

        [Fact]
        public void SettingSlotInvalidatesDialogueOverlayCache()
        {
            string path = Path.Combine(_root, "data", "rag", "agent_saves", "slotA", AgentDialogueOverrides.OverlayFileName);
            WriteOverlay("slotA", "{overrides:[{npc:'Andy Law',action:'replace',base_dialogue_id:'3',subdialogues:[{Text:'覆盖台词一'}]}]}");
            DateTime stamp = File.GetLastWriteTimeUtc(path);
            long length = new FileInfo(path).Length;
            AgentDialogueOverrides overrides = new AgentDialogueOverrides(_root);
            Dictionary<string, List<DialogueGroup>> baseIndex = BaseIndex();

            AgentSaveContext.Set("slotA");
            Assert.Equal("覆盖台词一", Text(overrides.Apply("slotA", baseIndex)));
            Assert.Equal(1, AgentDialogueOverrides.CachedSlotCount);

            // 改写内容但把指纹（长度 + 写入时间）复原：只有缓存被显式失效才可能读到新内容。
            WriteOverlay("slotA", "{overrides:[{npc:'Andy Law',action:'replace',base_dialogue_id:'3',subdialogues:[{Text:'覆盖台词二'}]}]}");
            File.SetLastWriteTimeUtc(path, stamp);
            Assert.Equal(length, new FileInfo(path).Length);
            Assert.Equal("覆盖台词一", Text(overrides.Apply("slotA", baseIndex)));   // 缓存命中

            // 换槽位 / 再收到一次绑定信号都必须立刻生效：上下文写入即清掉覆盖层缓存。
            AgentSaveContext.Set("slotA");
            Assert.Equal(0, AgentDialogueOverrides.CachedSlotCount);
            Assert.Equal("覆盖台词二", Text(overrides.Apply("slotA", baseIndex)));

            AgentSaveContext.Set("slotB");
            Assert.Equal(0, AgentDialogueOverrides.CachedSlotCount);
            AgentSaveContext.Clear();
            Assert.Equal(0, AgentDialogueOverrides.CachedSlotCount);
        }

        private static string Text(Dictionary<string, List<DialogueGroup>> merged) =>
            (string)merged["Andy Law"][0].SubDialogues[0]["text"];

        [Fact]
        public async Task BindRecordsSlotFromPayload()
        {
            var handler = new RagHttpStub(request => RagHttpStub.Json(
                "{\"ok\":true,\"mode\":\"embedded\",\"frontend_url\":\"" + RagTerminalService.LoopbackOrigin + "/ragchat\"}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            await service.BindAsync("slotA");

            Assert.Equal("slotA", AgentSaveContext.CurrentSlotKey);
            Assert.Contains("slot_key", handler.Bodies[0], StringComparison.Ordinal);
            Assert.Contains("slotA", handler.Bodies[0], StringComparison.Ordinal);
        }

        [Fact]
        public async Task RefreshRecordsSlotEvenWhenExeIsOffline()
        {
            // 覆盖层是本地文件：exe 不在线（health 不 ok）也要让宿主知道当前存档。
            var handler = new RagHttpStub(request => RagHttpStub.Json("{\"status\":\"down\"}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            await service.RefreshBindingBestEffortAsync("slotB", new JObject { ["name"] = "角色" });

            Assert.Equal("slotB", AgentSaveContext.CurrentSlotKey);
            Assert.Single(handler.Requests);      // 只探测了 health，没有 bind
        }

        [Fact]
        public async Task InterjectBindingReplaysCachedProjectionAndFillsPlayerName()
        {
            bool online = false;
            var handler = new RagHttpStub(request =>
            {
                if (request.RequestUri.AbsolutePath == "/api/health")
                {
                    return RagHttpStub.Json(online
                        ? "{\"status\":\"ok\",\"mode\":\"embedded\"}"
                        : "{\"status\":\"down\"}");
                }
                return RagHttpStub.Json("{\"ok\":true}");
            });
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            // 先在 exe 离线时收到投影：只缓存、不 bind；角色名为空，留给插话快照补。
            await service.RefreshBindingBestEffortAsync("slotB",
                new JObject { ["name"] = "" });
            Assert.Equal("slotB", AgentSaveContext.CurrentSlotKey);
            Assert.DoesNotContain(handler.Requests,
                r => r.RequestUri.AbsolutePath == "/api/integration/bind");

            online = true;
            await service.EnsureInterjectBindingAsync("测试玩家");

            string bindBody = handler.Bodies[handler.Bodies.Count - 1];
            JObject payload = JObject.Parse(bindBody);
            Assert.Equal("slotB", payload.Value<string>("slot_key"));
            Assert.Equal("测试玩家", payload["character"].Value<string>("name"));

            int binds = handler.Requests.FindAll(
                r => r.RequestUri.AbsolutePath == "/api/integration/bind").Count;
            Assert.Equal(1, binds);

            // 同一投影/玩家名重复插话不再重复 bind。
            await service.EnsureInterjectBindingAsync("测试玩家");
            binds = handler.Requests.FindAll(
                r => r.RequestUri.AbsolutePath == "/api/integration/bind").Count;
            Assert.Equal(1, binds);
        }

        [Fact]
        public async Task InterjectBindingDropsProjectionFromAnotherSlot()
        {
            bool online = false;
            var handler = new RagHttpStub(request => request.RequestUri.AbsolutePath == "/api/health"
                ? RagHttpStub.Json(online
                    ? "{\"status\":\"ok\",\"mode\":\"embedded\"}"
                    : "{\"status\":\"down\"}")
                : RagHttpStub.Json("{\"ok\":true}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });

            await service.RefreshBindingBestEffortAsync("slotA",
                new JObject { ["name"] = "旧存档角色" });
            AgentSaveContext.Set("slotB");
            online = true;
            await service.EnsureInterjectBindingAsync("新玩家");

            JObject payload = JObject.Parse(handler.Bodies[handler.Bodies.Count - 1]);
            Assert.Equal("slotB", payload.Value<string>("slot_key"));
            Assert.Equal("新玩家", payload["character"].Value<string>("name"));
            Assert.DoesNotContain("旧存档角色", payload.ToString(), StringComparison.Ordinal);
        }

        [Fact]
        public async Task UnbindInvalidatesInterjectBindingForNextTurn()
        {
            var handler = new RagHttpStub(request => request.RequestUri.AbsolutePath == "/api/health"
                ? RagHttpStub.Json("{\"status\":\"ok\",\"mode\":\"embedded\"}")
                : RagHttpStub.Json("{\"ok\":true}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });
            AgentSaveContext.Set("slotA");

            await service.EnsureInterjectBindingAsync("玩家");
            await service.UnbindAsync();
            await service.EnsureInterjectBindingAsync("玩家");

            int binds = handler.Requests.FindAll(
                r => r.RequestUri.AbsolutePath == "/api/integration/bind").Count;
            Assert.Equal(2, binds);
        }

        [Fact]
        public async Task InvalidSlotBindsNothingAndRecordsNothing()
        {
            var handler = new RagHttpStub(request => RagHttpStub.Json("{\"ok\":true}"));
            using var service = new RagTerminalService(@"C:\x\CrazyFlashNight", null, handler, path => { });
            AgentSaveContext.Set("slotA");

            RagTerminalPrepareResult bound = await service.BindAsync("../slotA");
            await service.RefreshBindingBestEffortAsync("slot A");

            Assert.False(bound.Success);
            Assert.Equal("rag_slot_invalid", bound.Error);
            Assert.Empty(handler.Requests);
            Assert.Equal("slotA", AgentSaveContext.CurrentSlotKey);   // 非法值不改写既有绑定
        }
    }
}
