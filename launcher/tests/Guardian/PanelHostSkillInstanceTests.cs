using System;
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelHostSkillInstanceTests
    {
        [Fact]
        public void OpenPayload_OverwritesUntrustedInstanceInTopAndInitData()
        {
            string json = PanelHostController.BuildPanelOpenPayload("skills",
                "{\"view\":\"manage\",\"panelInstanceId\":\"web.supplied\"}", "host.instance.9");
            JObject payload = JObject.Parse(json);
            Assert.Equal("host.instance.9", (string)payload["panelInstanceId"]);
            Assert.Equal("host.instance.9", (string)payload["initData"]["panelInstanceId"]);
            Assert.Equal("manage", (string)payload["initData"]["view"]);
        }

        [Theory]
        [InlineData("map", "panel.map.1", false)]
        [InlineData("skills", null, false)]
        [InlineData("skills", "panel.skills.1", true)]
        public void SkillsDomainRoute_RequiresActiveSkillsPanelAndInstance(string panel, string instance, bool expected)
        {
            Assert.Equal(expected, WebOverlayForm.IsActiveSkillPanel(panel, instance));
        }

        [Fact]
        public void EquipmentTuningDomainRoute_RequiresActiveWorkbenchAndExactHostInstance()
        {
            JObject request = JObject.Parse(@"{
                'type':'panel','panel':'workbench','domain':'equipment_tuning','cmd':'snapshot',
                'callId':'tune.route.1','panelInstanceId':'panel.workbench.1','payload':{}
            }");
            Assert.Equal(WebOverlayForm.PanelDomainRoute.EquipmentTuning,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", "equipment_tuning"));
            Assert.True(WebOverlayForm.IsActiveEquipmentTuningPanel(
                "workbench", "panel.workbench.1", request));
            Assert.False(WebOverlayForm.IsActiveEquipmentTuningPanel(
                "skills", "panel.workbench.1", request));
            Assert.False(WebOverlayForm.IsActiveEquipmentTuningPanel(
                "workbench", "panel.workbench.2", request));
            request["panel"] = "skills";
            Assert.False(WebOverlayForm.IsActiveEquipmentTuningPanel(
                "workbench", "panel.workbench.1", request));
        }

        [Fact]
        public void LoadoutDomainRoute_RequiresActiveWorkbenchAndExactHostInstance()
        {
            JObject request = JObject.Parse(@"{
                'type':'panel','panel':'workbench','domain':'loadout','cmd':'snapshot',
                'callId':'loadout.route.1','panelInstanceId':'panel.workbench.1',
                'payload':{'v':1}
            }");
            Assert.Equal(
                WebOverlayForm.PanelDomainRoute.Loadout,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", "loadout"));
            Assert.True(WebOverlayForm.IsActiveCharacterBuildPanel(
                "workbench", "panel.workbench.1", request));
            Assert.False(WebOverlayForm.IsActiveCharacterBuildPanel(
                "skills", "panel.workbench.1", request));
            Assert.False(WebOverlayForm.IsActiveCharacterBuildPanel(
                "workbench", "panel.workbench.2", request));
            request["panel"] = "skills";
            Assert.False(WebOverlayForm.IsActiveCharacterBuildPanel(
                "workbench", "panel.workbench.1", request));
        }

        [Fact]
        public void WorkbenchCloseEnvelope_NormalCloseRequiresExactActiveInstance()
        {
            JObject valid = JObject.Parse(@"{
                'type':'panel','panel':'workbench','cmd':'close',
                'panelInstanceId':'panel.workbench.2'
            }");
            Assert.True(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                valid, "workbench", "panel.workbench.2"));
            Assert.False(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                valid, "workbench", "panel.workbench.old"));
            Assert.False(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                valid, "skills", "panel.workbench.2"));

            valid["extra"] = true;
            Assert.False(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                valid, "workbench", "panel.workbench.2"));
        }

        [Theory]
        [InlineData("lazy_user_cancel")]
        [InlineData("lazy_cancel")]
        [InlineData("lazy_load_failed")]
        [InlineData("lazy_register_failed")]
        [InlineData("lazy_register_missing")]
        [InlineData("mount_failed")]
        [InlineData("navigate_skills")]
        public void WorkbenchCloseEnvelope_LazyCloseRequiresWhitelistedReasonAndExactInstance(
            string reason)
        {
            JObject valid = JObject.Parse(@"{
                'type':'panel','panel':'workbench','cmd':'close',
                'panelInstanceId':'panel.workbench.lazy','reason':'placeholder'
            }");
            valid["reason"] = reason;
            Assert.True(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                valid, "workbench", "panel.workbench.lazy"));

            valid["panelInstanceId"] = "panel.workbench.stale";
            Assert.False(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                valid, "workbench", "panel.workbench.lazy"));
            valid.Remove("panelInstanceId");
            Assert.False(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                valid, "workbench", "panel.workbench.lazy"));
        }

        [Fact]
        public void WorkbenchCloseEnvelope_RejectsIllegalReasonAndExtraFields()
        {
            JObject invalid = JObject.Parse(@"{
                'type':'panel','panel':'workbench','cmd':'close',
                'panelInstanceId':'panel.workbench.lazy','reason':'mount_failed_other'
            }");
            Assert.False(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                invalid, "workbench", "panel.workbench.lazy"));
            invalid["reason"] = "lazy_load_failed";
            invalid["extra"] = true;
            Assert.False(WebOverlayForm.IsValidWorkbenchCloseEnvelope(
                invalid, "workbench", "panel.workbench.lazy"));
        }

        [Fact]
        public void ForceClosePayload_BindsWorkbenchButPreservesGenericPanelCompatibility()
        {
            JObject workbench = JObject.Parse(WebOverlayForm.BuildPanelForceClosePayload(
                "workbench", "panel.workbench.current", "disconnected"));
            Assert.Equal("workbench", (string)workbench["panel"]);
            Assert.Equal("panel.workbench.current", (string)workbench["panelInstanceId"]);
            Assert.Equal("disconnected", (string)workbench["reason"]);
            Assert.Null(WebOverlayForm.BuildPanelForceClosePayload(
                "workbench", null, "disconnected"));

            JObject generic = JObject.Parse(WebOverlayForm.BuildPanelForceClosePayload(
                "map", "panel.map.1", "disconnected"));
            Assert.Null(generic["panel"]);
            Assert.Null(generic["panelInstanceId"]);
        }

        [Fact]
        public void SwitchManageEnvelope_RequiresExactInstanceAndNestedPresentationPayload()
        {
            JObject valid = JObject.Parse(@"{
                'type':'panel','panel':'skills','cmd':'switch_manage','panelInstanceId':'panel.skills.2',
                'payload':{'v':1,'focusSkillKey':'闪现'}
            }");
            Assert.True(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.2"));
            Assert.False(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.old"));

            valid["focusSkillKey"] = "顶层字段不允许";
            Assert.False(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.2"));
            valid.Remove("focusSkillKey");
            valid["payload"]["extra"] = true;
            Assert.False(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.2"));
        }

        [Fact]
        public void SwitchTrainerEnvelope_RequiresExactManageInstanceAndSameNestedShape()
        {
            JObject valid = JObject.Parse(@"{
                'type':'panel','panel':'skills','cmd':'switch_trainer','panelInstanceId':'panel.skills.manage.3',
                'payload':{'v':1,'focusSkillKey':'闪现'}
            }");
            Assert.True(WebOverlayForm.IsValidSkillTrainerSwitchEnvelope(valid, "skills", "panel.skills.manage.3"));
            Assert.False(WebOverlayForm.IsValidSkillTrainerSwitchEnvelope(valid, "skills", "panel.skills.old"));
            Assert.False(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.manage.3"));

            valid["payload"]["trainerSession"] = "web.must.not.receive.this";
            Assert.False(WebOverlayForm.IsValidSkillTrainerSwitchEnvelope(valid, "skills", "panel.skills.manage.3"));
        }

        [Fact]
        public void ReturnOpenHitsCharacterAuthorityGateBeforeSameNameRebindOrPanelSwitch()
        {
            string source = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "PanelHostController.cs"));
            string execute = Slice(
                source,
                "private void ExecuteCommand(PanelCommand cmd)",
                "private void ExecuteTrackedOpen(PanelCommand cmd)");
            int authorityGate = execute.IndexOf(
                "Func<string, bool> openGate = _openGate;",
                StringComparison.Ordinal);
            int deferIntent = execute.IndexOf(
                "_deferredBarrierOpen = cmd;",
                authorityGate,
                StringComparison.Ordinal);
            int sameNameRebind = execute.IndexOf(
                "if (_activePanel == cmd.Name)",
                StringComparison.Ordinal);
            int panelSwitch = execute.IndexOf(
                "if (_activePanel != null) DoClose();",
                StringComparison.Ordinal);
            Assert.True(authorityGate >= 0);
            Assert.True(deferIntent > authorityGate);
            Assert.True(sameNameRebind > deferIntent);
            Assert.True(panelSwitch > sameNameRebind);

            string exactClose = Slice(
                source,
                "private void ExecuteExactClose(PanelCommand cmd)",
                "private void QueueReturnOpen()");
            Assert.Contains(
                "QueueReturnOpen();",
                exactClose);
            string returnOpen = Slice(
                source,
                "private void QueueReturnOpen()",
                "#endregion");
            Assert.Contains(
                "PanelCommandKind.Open",
                returnOpen);

            string program = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Program.cs"));
            Assert.Contains(
                "panelHost.SetOpenGate(delegate(string panelName)",
                program);
            Assert.Contains(
                "return !form.IsShutdownAdmissionClosed",
                program);
            Assert.Contains(
                "&& !characterBuildTask.HasBoundPanel;",
                program);
            Assert.Contains(
                "panelHost.FlushDeferredBarrierOpen();",
                program);
        }

        [Fact]
        public void DeferredReturnOpenReassertsPauseOnlyAfterBindingSettlementFlush()
        {
            string panelHost = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "PanelHostController.cs"));
            string flush = Slice(
                panelHost,
                "public void FlushDeferredBarrierOpen()",
                "public void ClearReturnStack()");
            Assert.Contains(
                "EnqueueAndPump(deferred.Value);",
                flush);

            string open = Slice(
                panelHost,
                "private bool DoOpen(string name, string initDataJson, string reservedPanelInstanceId,",
                "private void DoRebind(string name, string initDataJson)");
            int activeIdentity = open.IndexOf(
                "_activePanel = name;",
                StringComparison.Ordinal);
            int pauseAssert = open.IndexOf(
                "_web.AssertWebPanelPause();",
                activeIdentity,
                StringComparison.Ordinal);
            Assert.True(activeIdentity >= 0);
            Assert.True(pauseAssert > activeIdentity);

            string program = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Program.cs"));
            string settled = Slice(
                program,
                "characterBuildTask.SetCoordinatorSettled(delegate",
                "MapTask mapTask");
            Assert.Contains(
                "panelHost.FlushDeferredBarrierOpen();",
                settled);
        }

        [Fact]
        public void DiscardDeferredBarrierOpenDropsRecoveryWindowCompetitor()
        {
            var pumps =
                new Queue<Action>();
            using (var host =
                new PanelHostController(
                    delegate(Action pump)
                    {
                        pumps.Enqueue(
                            pump);
                    },
                    delegate(Action fire)
                    {
                        fire();
                    }))
            {
                host.SetOpenGate(
                    delegate
                    {
                        return false;
                    });
                Assert.True(
                    host.TryOpenPanel(
                        "map",
                        "{}",
                        null,
                        null));
                Assert.Single(
                    pumps);
                pumps.Dequeue()();
                Assert.False(
                    host.IsPanelOpen);

                host.SetOpenGate(
                    delegate
                    {
                        return true;
                    });
                Assert.True(
                    host.DiscardDeferredBarrierOpen());
                host.FlushDeferredBarrierOpen();

                Assert.Empty(
                    pumps);
                Assert.False(
                    host.IsPanelOpen);
                Assert.False(
                    host.DiscardDeferredBarrierOpen());
            }
        }

        [Fact]
        public void WorkbenchExactCloseRechecksNameAndInstanceAtExecution()
        {
            string source = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "PanelHostController.cs"));
            string exactClose = Slice(
                source,
                "private void ExecuteExactClose(PanelCommand cmd)",
                "private void QueueReturnOpen()");
            int nameCheck = exactClose.IndexOf(
                "_activePanel, cmd.Name",
                StringComparison.Ordinal);
            int instanceCheck = exactClose.IndexOf(
                "_activePanelInstanceId,",
                StringComparison.Ordinal);
            int close = exactClose.IndexOf(
                "DoClose();",
                StringComparison.Ordinal);
            int completion = exactClose.IndexOf(
                "cmd.ExactCloseCompleted",
                StringComparison.Ordinal);
            Assert.True(nameCheck >= 0);
            Assert.True(instanceCheck > nameCheck);
            Assert.True(close > instanceCheck);
            Assert.True(completion > close);
            Assert.Contains(
                "return;",
                exactClose);

            string overlay = File.ReadAllText(
                FindRepositoryFile(
                    "launcher", "src", "Guardian",
                    "WebOverlayForm.cs"));
            string closeHandler = Slice(
                overlay,
                "case \"close\":",
                "case \"bulkQuery\":");
            Assert.Contains(
                "_panelHost.TryClosePanelExact(",
                closeHandler);
        }

        private static string Slice(
            string source,
            string startMarker,
            string endMarker)
        {
            int start = source.IndexOf(
                startMarker, StringComparison.Ordinal);
            Assert.True(start >= 0);
            int end = source.IndexOf(
                endMarker, start, StringComparison.Ordinal);
            Assert.True(end > start);
            return source.Substring(start, end - start);
        }

        private static string FindRepositoryFile(
            params string[] relativeParts)
        {
            DirectoryInfo current =
                new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string path = current.FullName;
                foreach (string part in relativeParts)
                    path = Path.Combine(path, part);
                if (File.Exists(path)) return path;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                string.Join(
                    Path.DirectorySeparatorChar.ToString(),
                    relativeParts));
        }
    }
}
