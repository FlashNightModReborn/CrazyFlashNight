using System;
using System.Collections.Generic;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// Router 单测。Flag OFF 路径（_panelHost == null）触发 PostToWeb fallback；
    /// Flag ON 路径无法在单测里覆盖（PanelHostController 依赖 Form），通过集成测试 + 手测覆盖。
    /// </summary>
    public class LauncherCommandRouterTests
    {
        private class Capture
        {
            public List<Keys> SentKeys = new List<Keys>();
            public List<string> Posts = new List<string>();
            public List<string> ActivePanels = new List<string>();
            public List<bool> StateCallbacks = new List<bool>();
            public int Fullscreen, Log, Exit;
        }

        private static LauncherCommandRouter MakeRouter(Capture c)
        {
            return new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => c.SentKeys.Add(k),
                onToggleFullscreen: () => c.Fullscreen++,
                onToggleLog: () => c.Log++,
                onForceExit: () => c.Exit++,
                postToWeb: s => c.Posts.Add(s),
                onPanelStateChanged: b => c.StateCallbacks.Add(b),
                setActivePanel: name => c.ActivePanels.Add(name));
        }

        [Fact]
        public void KeyDispatch_QWRPO_ForwardedAsKeys()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("Q");
            r.Dispatch("W");
            r.Dispatch("R");
            r.Dispatch("P");
            r.Dispatch("O");
            Assert.Equal(new[] { Keys.Q, Keys.W, Keys.R, Keys.P, Keys.O }, c.SentKeys);
        }

        [Fact]
        public void F_TogglesFullscreen_NotSentAsKey()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("F");
            Assert.Equal(1, c.Fullscreen);
            Assert.Empty(c.SentKeys);
        }

        [Fact]
        public void LOG_TogglesLog()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("LOG");
            Assert.Equal(1, c.Log);
        }

        [Fact]
        public void EXIT_AndExitConfirm_ForceExit()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("EXIT");
            r.Dispatch("EXIT_CONFIRM");
            Assert.Equal(2, c.Exit);
        }

        [Fact]
        public void HELP_OpenPanelFallback_PostsPanelCmdOpen()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("HELP");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"help\"", c.Posts[0]);
            Assert.Contains("\"cmd\":\"open\"", c.Posts[0]);
            Assert.Equal(new[] { "help" }, c.ActivePanels);
            Assert.Equal(new[] { true }, c.StateCallbacks);
        }

        [Fact]
        public void WAREHOUSE_DefaultRoute_UsesBattleboxStorage()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("WAREHOUSE");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"workbench\"", c.Posts[0]);
            Assert.Contains("\"profile\":\"battlebox\"", c.Posts[0]);
            Assert.Contains("\"view\":\"storage\"", c.Posts[0]);
            Assert.Contains("\"source\":\"nativehud\"", c.Posts[0]);
            Assert.Equal(new[] { "workbench" }, c.ActivePanels);
            Assert.Equal(new[] { true }, c.StateCallbacks);
        }

        [Fact]
        public void WAREHOUSE_DefaultRoute_DoesNotEmitTuningCapabilitySwitch()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.Dispatch("WAREHOUSE");

            Assert.DoesNotContain("tuningAvailable", Assert.Single(c.Posts));
        }

        [Fact]
        public void WAREHOUSE_DisabledRoute_DoesNotOpenWebPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.WebInventoryWorkbenchEnabled = false;
            r.Dispatch("WAREHOUSE");
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Fact]
        public void EQUIP_UI_AlwaysKeepsLegacyEquipmentCommand()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return true; });
            r.Dispatch("EQUIP_UI");

            Assert.Single(commands);
            Assert.Equal("openEquipUI", (string)JObject.Parse(commands[0].TrimEnd('\0'))["action"]);
        }

        [Fact]
        public void EQUIP_UI_DoesNotOpenWorkbenchSideRoute()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return true; });
            r.Dispatch("EQUIP_UI");

            JObject command = JObject.Parse(Assert.Single(commands).TrimEnd('\0'));
            Assert.Equal("cmd", (string)command["task"]);
            Assert.Equal("openEquipUI", (string)command["action"]);
            Assert.Equal(2, command.Count);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void EQUIP_UI_SendFailure_DoesNotAttemptTuningSideRoute()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return false; });
            r.Dispatch("EQUIP_UI");

            Assert.Single(commands);
            Assert.Equal("openEquipUI", (string)JObject.Parse(commands[0].TrimEnd('\0'))["action"]);
            Assert.Empty(c.Posts);
        }

        [Theory]
        [InlineData("{\"profile\":\"battlebox\",\"view\":\"tuning\"}")]
        [InlineData("{\"profile\":\"battlebox\",\"view\":\"storage\"}")]
        [InlineData(null)]
        public void RequestOpenPanel_LegacyEquipmentTuningRedirectIsPaused(string extras)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel("workbench", "legacy_equipment_tuning", null, null, null, null, null, extras);

            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Fact]
        public void CraftingRequest_WhitelistsCategoryAndBuildsRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("crafting", "legacy_crafting_entry", null, null, null, null, null,
                "{\"category\":\"武器合成\",\"ignored\":\"x\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"crafting\"", c.Posts[0]);
            Assert.Contains("\"category\":\"武器合成\"", c.Posts[0]);
            Assert.DoesNotContain("ignored", c.Posts[0]);
            Assert.Equal(new[] { "crafting" }, c.ActivePanels);
        }

        [Fact]
        public void CraftingRequest_RejectsUnknownCategory()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("crafting", "legacy_crafting_entry", null, null, null, null, null,
                "{\"category\":\"未知分类\"}");
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void GOBANG_TEST_OpenPanelFallback_IncludesInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("GOBANG_TEST");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"gobang\"", c.Posts[0]);
            Assert.Contains("\"initData\"", c.Posts[0]);
            Assert.Contains("\"ruleset\":\"casual\"", c.Posts[0]);
        }

        [Fact]
        public void INTELLIGENCE_TEST_OpenPanelFallback_IncludesFixtureInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("INTELLIGENCE_TEST");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"intelligence\"", c.Posts[0]);
            Assert.Contains("\"itemName\":\"资料\"", c.Posts[0]);
            Assert.Contains("\"value\":99", c.Posts[0]);
            Assert.Contains("\"decryptLevel\":10", c.Posts[0]);
        }

        [Fact]
        public void INTELLIGENCE_OpenPanelFallback_UsesRuntimeProdInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("INTELLIGENCE");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"intelligence\"", c.Posts[0]);
            Assert.Contains("\"mode\":\"prod\"", c.Posts[0]);
            Assert.Contains("\"source\":\"runtime\"", c.Posts[0]);
            Assert.Contains("\"debug\":false", c.Posts[0]);
            Assert.Equal(new[] { "intelligence" }, c.ActivePanels);
            Assert.Equal(new[] { true }, c.StateCallbacks);
        }

        [Fact]
        public void NewTaskUi_WhenFlashUnavailable_PostsUnavailableToast()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("NEW_TASK_UI");

            Assert.Single(c.Posts);
            Assert.Contains("任务面板暂时不可用", c.Posts[0]);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Theory]
        [InlineData("TEAM")]
        [InlineData("PETS")]
        [InlineData("MERCS")]
        public void TeamEntries_WhenFlashUnavailable_PostUnavailableToast(string key)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.Dispatch(key);

            Assert.Single(c.Posts);
            Assert.Contains("战队面板暂时不可用", c.Posts[0]);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void RequestOpenPanel_Map_RoutesToOpenMapPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("map", "as2_request", "page-1");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"map\"", c.Posts[0]);
            Assert.Contains("\"page\":\"page-1\"", c.Posts[0]);
            Assert.Contains("\"source\":\"as2_request\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_StageSelect_RoutesRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("stage-select", "as2_base_gate", null, "基地门口");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"stage-select\"", c.Posts[0]);
            Assert.Contains("\"mode\":\"runtime\"", c.Posts[0]);
            Assert.Contains("\"fixture\":\"mixed\"", c.Posts[0]);
            Assert.Contains("\"frameLabel\":\"基地门口\"", c.Posts[0]);
            Assert.Contains("\"returnFrameLabel\":\"基地门口\"", c.Posts[0]);
            Assert.Contains("\"source\":\"as2_base_gate\"", c.Posts[0]);
            Assert.Contains("\"debug\":false", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_StageSelect_CarriesExplicitReturnFrame()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("stage-select", "as2_legacy_stage_gate", null, "黑铁会总部", "基地车库");
            Assert.Single(c.Posts);
            Assert.Contains("\"frameLabel\":\"黑铁会总部\"", c.Posts[0]);
            Assert.Contains("\"returnFrameLabel\":\"基地车库\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_Tasks_RoutesToOpenTasksPanelWithInitData()
        {
            // 副本任务（委托任务）入口回归：NPC openWebDungeon 发 panel_request panel="tasks"，
            // 必须开 tasks 面板并透传 initData {view,taskId}。曾因 RequestOpenPanel 无 tasks 分支
            // 静默丢弃（"[Router] RequestOpenPanel unsupported panel=tasks"），NPC 点击无反应。
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("tasks", "npc_dungeon", null, null, null, null, null, "{\"view\":\"dungeon\",\"taskId\":20052}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"tasks\"", c.Posts[0]);
            Assert.Contains("\"view\":\"dungeon\"", c.Posts[0]);
            Assert.Contains("\"taskId\":20052", c.Posts[0]);
            Assert.Contains("\"source\":\"npc_dungeon\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_Team_RoutesToOpenTeamPanelWithInitData()
        {
            // 世界内雇佣入口：NPC openWebHire 发 panel_request panel="team"，必须开 team 面板并
            // 透传 initData {view:"hire",kind,npcId,initialTab}。无 team 分支会静默丢弃（unsupported panel）。
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("team", "npc_hire", null, null, null, null, null, "{\"view\":\"hire\",\"kind\":\"merc\",\"npcId\":\"敌人123\",\"initialTab\":\"mercenary\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"team\"", c.Posts[0]);
            Assert.Contains("\"view\":\"hire\"", c.Posts[0]);
            Assert.Contains("\"kind\":\"merc\"", c.Posts[0]);
            Assert.Contains("\"source\":\"npc_hire\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchWarehouse_UsesStrictWarehouseProfile()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "dormitory", null, null, null, null, null,
                "{\"profile\":\"warehouse\",\"rightContainer\":\"任意容器\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"workbench\"", c.Posts[0]);
            Assert.Contains("\"profile\":\"warehouse\"", c.Posts[0]);
            Assert.Contains("\"view\":\"storage\"", c.Posts[0]);
            Assert.DoesNotContain("tuningAvailable", c.Posts[0]);
            Assert.Contains("\"source\":\"dormitory\"", c.Posts[0]);
            Assert.DoesNotContain("rightContainer", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchUnknownProfile_IsRejected()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "dormitory", null, null, null, null, null,
                "{\"profile\":\"仓库\"}");
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchTuning_AllowsNormalEquipmentSource()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "nativehud_equipment", null, null, null, null, null,
                "{\"profile\":\"battlebox\",\"view\":\"tuning\",\"ignored\":true}");

            Assert.Single(c.Posts);
            Assert.Contains("\"view\":\"tuning\"", c.Posts[0]);
            Assert.DoesNotContain("tuningAvailable", c.Posts[0]);
            Assert.Contains("\"source\":\"nativehud_equipment\"", c.Posts[0]);
            Assert.DoesNotContain("ignored", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_WorkbenchTuning_AgentControlUsesSameNormalRoute()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("workbench", "agent_control", null, null, null, null, null,
                "{\"profile\":\"battlebox\",\"view\":\"tuning\"}");

            Assert.Single(c.Posts);
            Assert.Contains("\"view\":\"tuning\"", c.Posts[0]);
            Assert.DoesNotContain("tuningAvailable", c.Posts[0]);
            Assert.Contains("\"source\":\"agent_control\"", c.Posts[0]);
        }

        [Theory]
        [InlineData("dormitory", "{\"profile\":\"warehouse\",\"view\":\"tuning\"}")]
        [InlineData("dormitory", "{\"profile\":\"warehouse\",\"view\":\"unknown\"}")]
        public void RequestOpenPanel_WorkbenchRejectsInvalidTuningProfileOrUnknownView(string source, string extras)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.RequestOpenPanel("workbench", source, null, null, null, null, null, extras);

            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void RequestOpenPanel_Unknown_NoPost()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("nonexistent", "src", null);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void RequestOpenPanel_SkillsTrainer_RebuildsStrictRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("skills", "untrusted_source", null, null, null, null, null,
                "{\"view\":\"trainer\",\"trainerSession\":\"trainer.session.7\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"skills\"", c.Posts[0]);
            Assert.Contains("\"source\":\"world_skill_trainer\"", c.Posts[0]);
            Assert.Contains("\"view\":\"trainer\"", c.Posts[0]);
            Assert.Contains("\"trainerSession\":\"trainer.session.7\"", c.Posts[0]);
            Assert.DoesNotContain("untrusted_source", c.Posts[0]);
        }

        [Fact]
        public void SkillsButton_WhenSocketPreflightFails_DoesNotOpenEmptyPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("SKILLS");
            Assert.Single(c.Posts);
            Assert.Contains("旧物品界面", c.Posts[0]);
            Assert.DoesNotContain("\"cmd\":\"open\"", c.Posts[0]);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void SkillsButton_SendTrueWaitsForPanelRequestAndTimesOutWithoutOpening()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var commands = new List<string>();
            r.SetGameCommandSenderForTests(value => { commands.Add(value); return true; });
            r.SkillOpenTimeoutMs = 20;

            r.Dispatch("SKILLS");

            Assert.Single(commands);
            Assert.Contains("skillPanelOpen", commands[0]);
            Assert.Empty(c.Posts);
            Assert.Empty(c.ActivePanels);
            Assert.True(System.Threading.SpinWait.SpinUntil(() => c.Posts.Count == 1, 2000));
            Assert.Contains("技能服务未就绪", c.Posts[0]);
            Assert.DoesNotContain("\"cmd\":\"open\"", c.Posts[0]);
        }

        [Fact]
        public void SkillsButton_ReadyPanelRequestOpensOnceAndCancelsTimeoutToast()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.SetGameCommandSenderForTests(value => true);
            r.SkillOpenTimeoutMs = 40;

            r.Dispatch("SKILLS");
            Assert.Empty(c.Posts);
            r.RequestOpenPanel("skills", "nativehud", null, null, null, null, null, "{\"view\":\"manage\"}");
            System.Threading.Thread.Sleep(100);

            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"skills\"", c.Posts[0]);
            Assert.DoesNotContain("技能服务未就绪", c.Posts[0]);
        }

        [Fact]
        public void SkillsButton_SynchronousPanelRequestDuringSendCannotInstallStaleTimeout()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.SkillOpenTimeoutMs = 20;
            r.SetGameCommandSenderForTests(value =>
            {
                if (value.Contains("skillPanelOpen"))
                    r.RequestOpenPanel("skills", "nativehud", null, null, null, null, null, "{\"view\":\"manage\"}");
                return true;
            });

            r.Dispatch("SKILLS");
            System.Threading.Thread.Sleep(80);

            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"skills\"", c.Posts[0]);
            Assert.DoesNotContain("技能服务未就绪", c.Posts[0]);
        }

        [Theory]
        [InlineData("{\"view\":\"trainer\"}")]
        [InlineData("{\"view\":\"manage\",\"trainerSession\":\"trainer.one\"}")]
        [InlineData("{\"view\":\"trainer\",\"trainerSession\":\"bad token\"}")]
        [InlineData("{\"view\":\"trainer\",\"trainerSession\":\"trainer.one\",\"catalog\":[]}")]
        public void RequestOpenPanel_SkillsRejectsMalformedOrRawExtras(string extras)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("skills", "world", null, null, null, null, null, extras);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void RequestOpenPanel_TwoTrainerSessions_GetDistinctPanelInstancesAndLatestContext()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("skills", "world", null, null, null, null, null,
                "{\"view\":\"trainer\",\"trainerSession\":\"trainer.a\"}");
            r.RequestOpenPanel("skills", "world", null, null, null, null, null,
                "{\"view\":\"trainer\",\"trainerSession\":\"trainer.b\"}");
            Assert.Equal(2, c.Posts.Count);
            var first = Newtonsoft.Json.Linq.JObject.Parse(c.Posts[0]);
            var second = Newtonsoft.Json.Linq.JObject.Parse(c.Posts[1]);
            Assert.NotEqual((string)first["panelInstanceId"], (string)second["panelInstanceId"]);
            Assert.Equal("trainer.a", (string)first["initData"]["trainerSession"]);
            Assert.Equal("trainer.b", (string)second["initData"]["trainerSession"]);
        }

        [Fact]
        public void SkillsTrainerManageRoundTrip_PreservesFocusButKeepsCapabilityInsideHost()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                r.RequestOpenPanel("skills", "world", null, null, null, null, null,
                    "{\"view\":\"trainer\",\"trainerSession\":\"trainer.switch\"}");
                string trainerInstance = r.ActiveFallbackPanelInstanceId;
                task.BindPanelInstance(trainerInstance);

                Assert.True(r.RebindSkillsToManage(trainerInstance, "闪现"));
                Assert.Equal(2, c.Posts.Count);
                JObject manage = JObject.Parse(c.Posts[1]);
                Assert.Equal("manage", (string)manage["initData"]["view"]);
                Assert.Equal("闪现", (string)manage["initData"]["focusSkillKey"]);
                Assert.True((bool)manage["initData"]["canReturnTrainer"]);
                Assert.Null(manage["initData"]["trainerSession"]);
                Assert.NotEqual(trainerInstance, (string)manage["panelInstanceId"]);
                Assert.Empty(sent); // 返回凭据只暂存在 Host；切换本身不提前清理。
                Assert.False(r.RebindSkillsToManage(trainerInstance, "闪现"));
                Assert.Equal(2, c.Posts.Count);

                string manageInstance = (string)manage["panelInstanceId"];
                task.BindPanelInstance(manageInstance);
                Assert.True(r.RebindSkillsToTrainer(manageInstance, "闪现"));
                Assert.Equal(3, c.Posts.Count);
                JObject trainer = JObject.Parse(c.Posts[2]);
                Assert.Equal("trainer", (string)trainer["initData"]["view"]);
                Assert.Equal("trainer.switch", (string)trainer["initData"]["trainerSession"]);
                Assert.Equal("闪现", (string)trainer["initData"]["focusSkillKey"]);
                Assert.False(r.RebindSkillsToTrainer(manageInstance, "闪现"));
            }
        }

        [Fact]
        public void FallbackSkillsRebind_PreservesOldInstanceThroughUnknownWriteReconcileThenAppliesLatestManageIntent()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            var web = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                task.SetPostToWeb(value => web.Add(JObject.Parse(value)));
                r.SetSkillTask(task);
                task.SetCoordinatorSettled(r.FlushDeferredFallbackSkillRebind);
                r.RequestOpenPanel("skills", "world", null, null, null, null, null, "{\"view\":\"manage\"}");
                Assert.Single(c.Posts);
                string oldInstance = (string)JObject.Parse(c.Posts[0])["panelInstanceId"];
                task.BindPanelInstance(oldInstance);
                task.HandleFlashResponse(SkillCleanupAck((int)sent[0]["callId"], 12), null);

                JObject write = SkillRequest("equip", "fallback.write");
                write["panelInstanceId"] = oldInstance;
                task.HandleWebRequest("equip", write);
                int writeFid = (int)sent[sent.Count - 1]["callId"];
                r.RequestOpenPanel("skills", "world", null, null, null, null, null,
                    "{\"view\":\"trainer\",\"trainerSession\":\"trainer.new\"}");
                Assert.Single(c.Posts);
                Assert.Equal(oldInstance, r.ActiveFallbackPanelInstanceId);

                task.HandleFlashResponse(SkillError(writeFid, "future_error", 12), null);
                Assert.Equal("needs_reconcile", task.WriteState);
                JObject reconcile = SkillRequest("snapshot", "fallback.reconcile");
                reconcile["panelInstanceId"] = oldInstance;
                reconcile["payload"]["reconcileId"] = "fallback.probe";
                reconcile["payload"]["reconcileAfterCallId"] = "fallback.write";
                task.HandleWebRequest("snapshot", reconcile);
                int reconcileFid = (int)sent[sent.Count - 1]["callId"];
                JObject snapshot = SkillSnapshot(12);
                snapshot["task"] = "skill_response";
                snapshot["callId"] = reconcileFid;
                task.HandleFlashResponse(snapshot, null);
                Assert.Single(c.Posts);
                task.HandleFlashResponse(SkillCleanupAck((int)sent[sent.Count - 1]["callId"], 12), null);

                Assert.Equal(2, c.Posts.Count);
                JObject reopened = JObject.Parse(c.Posts[1]);
                Assert.NotEqual(oldInstance, (string)reopened["panelInstanceId"]);
                Assert.Equal("manage", (string)reopened["initData"]["view"]);
                Assert.Equal(oldInstance, (string)web[web.Count - 1]["panelInstanceId"]);
            }
        }

        [Fact]
        public void FallbackDisconnectClear_AllowsRealRecoveryOpenWhileTaskNeedsReconcile()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                r.RequestOpenPanel("skills", "world", null, null, null, null, null, "{\"view\":\"manage\"}");
                string oldInstance = r.ActiveFallbackPanelInstanceId;
                task.BindPanelInstance(oldInstance);
                JObject write = SkillRequest("equip", "fallback.disconnect.write");
                write["panelInstanceId"] = oldInstance;
                task.HandleWebRequest("equip", write);
                r.RequestOpenPanel("skills", "world", null, null, null, null, null, "{\"view\":\"manage\"}");
                Assert.Single(c.Posts);

                task.ClearPending();
                r.ClearFallbackPanelInstance();
                r.RequestOpenPanel("skills", "world", null, null, null, null, null, "{\"view\":\"manage\"}");

                Assert.Equal(2, c.Posts.Count);
                JObject recovery = JObject.Parse(c.Posts[1]);
                Assert.NotEqual(oldInstance, (string)recovery["panelInstanceId"]);
                Assert.Equal("needs_reconcile", (string)recovery["initData"]["writeState"]);
                Assert.Equal("fallback.disconnect.write", (string)recovery["initData"]["reconcileAfterCallId"]);
            }
        }

        [Fact]
        public void FallbackTrainerSwitchToOtherPanel_ClosesScopedCapabilityBeforeFirstBusinessRequest()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                r.RequestOpenPanel("skills", "world", null, null, null, null, null,
                    "{\"view\":\"trainer\",\"trainerSession\":\"trainer.first\"}");
                Assert.Single(c.Posts);

                r.RequestOpenPanel("map", "switch_test", null);

                Assert.Equal(2, c.Posts.Count);
                Assert.Single(sent);
                Assert.Equal("skillPanelClose", (string)sent[0]["action"]);
                Assert.Equal("trainer.first", (string)sent[0]["trainerSession"]);
            }
        }

        [Fact]
        public void ForceCleanupInFlight_TrainerRequestDowngradesToManageThenRunsScopedCleanup()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            var sent = new List<JObject>();
            using (var task = new SkillTask(() => true, value => { sent.Add(ParseWire(value)); return true; }))
            {
                r.SetSkillTask(task);
                task.RequestTrainerCleanup(null);
                Assert.Single(sent);
                Assert.Null(sent[0]["trainerSession"]);

                r.RequestOpenPanel("skills", "world", null, null, null, null, null,
                    "{\"view\":\"trainer\",\"trainerSession\":\"trainer.candidate.C\"}");
                Assert.Single(c.Posts);
                JObject opened = JObject.Parse(c.Posts[0]);
                Assert.Equal("manage", (string)opened["initData"]["view"]);

                task.HandleFlashResponse(SkillCleanupAck((int)sent[0]["callId"], 12), null);
                Assert.Equal(2, sent.Count);
                Assert.Equal("skillPanelClose", (string)sent[1]["action"]);
                Assert.Equal("trainer.candidate.C", (string)sent[1]["trainerSession"]);
                Assert.False(task.CanOpenTrainer);

                task.HandleFlashResponse(SkillCleanupAck((int)sent[1]["callId"], 12), null);
                Assert.True(task.CanOpenTrainer);
            }
        }

        [Fact]
        public void EmptyKey_SilentlyIgnored()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("");
            r.Dispatch(null);
            Assert.Empty(c.SentKeys);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void UnknownKey_SilentlyIgnored()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("NONEXISTENT_KEY");
            Assert.Empty(c.SentKeys);
            Assert.Empty(c.Posts);
        }

        private static JObject SkillRequest(string cmd, string callId)
        {
            JObject payload = new JObject { ["v"] = 1 };
            if (cmd == "snapshot") payload["view"] = "manage";
            else if (cmd == "equip")
            {
                payload["skillKey"] = "闪现"; payload["slot"] = 4; payload["expectedRevision"] = 12;
            }
            return new JObject
            {
                ["type"] = "panel", ["panel"] = "skills", ["domain"] = "skills",
                ["cmd"] = cmd, ["callId"] = callId,
                ["panelInstanceId"] = "fallback.unbound", ["payload"] = payload
            };
        }

        private static JObject SkillError(int callId, string error, int revision)
        {
            return new JObject
            {
                ["task"] = "skill_response", ["callId"] = callId, ["success"] = false,
                ["v"] = 1, ["error"] = error, ["revision"] = revision
            };
        }

        private static JObject SkillCleanupAck(int callId, int revision)
        {
            return new JObject
            {
                ["task"] = "skill_response", ["callId"] = callId, ["success"] = true,
                ["v"] = 1, ["changed"] = false, ["revision"] = revision
            };
        }

        private static JObject SkillSnapshot(int revision)
        {
            var loadout = new JArray();
            for (int slot = 1; slot <= 12; slot++) loadout.Add(new JObject
            {
                ["slot"] = slot, ["skillKey"] = null, ["keyLabel"] = slot.ToString(),
                ["stateHealth"] = "ok", ["writeBlocked"] = false
            });
            return new JObject
            {
                ["success"] = true, ["v"] = 1, ["revision"] = revision, ["view"] = "manage",
                ["player"] = new JObject { ["level"] = 20, ["skillPoints"] = 10, ["easyMode"] = false },
                ["learned"] = new JArray(), ["loadout"] = loadout, ["trainer"] = null,
                ["diagnostics"] = new JArray()
            };
        }

        private static JObject ParseWire(string value) { return JObject.Parse(value.TrimEnd('\0')); }
    }
}
