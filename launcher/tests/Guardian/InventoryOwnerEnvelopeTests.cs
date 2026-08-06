using System;
using System.IO;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class InventoryOwnerEnvelopeTests
    {
        [Theory]
        [InlineData("workbench")]
        [InlineData("kshop")]
        [InlineData("npcshop")]
        [InlineData("crafting")]
        public void GenericInventoryEnvelopeRequiresExactOwnerAndInstance(
            string panel)
        {
            JObject request = BuildRequest(panel, "panel.instance.exact");

            Assert.True(WebOverlayForm.IsValidInventoryOwnerEnvelope(
                request, panel, "panel.instance.exact"));
            Assert.False(WebOverlayForm.IsValidInventoryOwnerEnvelope(
                request, panel, "panel.instance.replaced"));
            Assert.False(WebOverlayForm.IsValidInventoryOwnerEnvelope(
                request, "workbench" == panel ? "kshop" : "workbench",
                "panel.instance.exact"));
        }

        [Fact]
        public void GenericInventoryEnvelopeRejectsForeignDomainsAndNearMatches()
        {
            JObject request = BuildRequest(
                "crafting", "panel.crafting.exact");

            request["extra"] = true;
            Assert.False(IsValid(request));
            request.Remove("extra");

            request["payload"] = "not-an-object";
            Assert.False(IsValid(request));
            request["payload"] = new JObject { ["v"] = 1 };

            request["callId"] = 7;
            Assert.False(IsValid(request));
            request["callId"] = "inventory.snapshot.1";

            request["cmd"] = "";
            Assert.False(IsValid(request));
            request["cmd"] = "snapshot";

            request["type"] = "panel_response";
            Assert.False(IsValid(request));
            request["type"] = "panel";

            request["domain"] = "crafting";
            Assert.False(IsValid(request));
            request["domain"] = "inventory";

            request["panelInstanceId"] = "panel.crafting.stale";
            Assert.False(IsValid(request));
            request["panelInstanceId"] = "panel.crafting.exact";

            request.Remove("panelInstanceId");
            Assert.False(IsValid(request));
        }

        [Theory]
        [InlineData("kshop")]
        [InlineData("npcshop")]
        [InlineData("crafting")]
        public void BusinessOwnerBindingRequiresTheExactActiveTuple(
            string panel)
        {
            JObject request = BuildRequest(
                panel, "panel.business.exact");

            Assert.True(WebOverlayForm.HasExactPanelOwnerBinding(
                request,
                panel,
                panel,
                "panel.business.exact"));
            Assert.False(WebOverlayForm.HasExactPanelOwnerBinding(
                request,
                panel,
                panel,
                "panel.business.replaced"));
            Assert.False(WebOverlayForm.HasExactPanelOwnerBinding(
                request,
                panel,
                "workbench",
                "panel.business.exact"));

            request.Remove("panelInstanceId");
            Assert.False(WebOverlayForm.HasExactPanelOwnerBinding(
                request,
                panel,
                panel,
                "panel.business.exact"));
        }

        [Fact]
        public void KShopDomainlessContractRequiresThePropertyToBeAbsent()
        {
            JObject request = BuildRequest(
                "kshop", "panel.kshop.domainless");
            request.Remove("domain");
            Assert.True(
                WebOverlayForm.IsStrictDomainlessPanelEnvelope(request));

            request["domain"] = "";
            Assert.False(
                WebOverlayForm.IsStrictDomainlessPanelEnvelope(request));
            request["domain"] = JValue.CreateNull();
            Assert.False(
                WebOverlayForm.IsStrictDomainlessPanelEnvelope(request));
            request["domain"] = new JObject();
            Assert.False(
                WebOverlayForm.IsStrictDomainlessPanelEnvelope(request));
            request["domain"] = "inventory";
            Assert.False(
                WebOverlayForm.IsStrictDomainlessPanelEnvelope(request));
        }

        [Fact]
        public void DomainlessAdmissionErrorPreservesKshopWireShape()
        {
            JObject request = BuildRequest(
                "kshop", "panel.kshop.stale");
            request.Remove("domain");

            JObject response =
                WebOverlayForm.BuildPanelDomainErrorResponse(
                    request,
                    "panel_instance_expired");

            Assert.Null(response["domain"]);
            Assert.Equal("kshop", (string)response["panel"]);
            Assert.Equal(
                "panel.kshop.stale",
                (string)response["panelInstanceId"]);
        }

        [Theory]
        [InlineData("loot")]
        [InlineData("character")]
        [InlineData("skills")]
        [InlineData("")]
        public void DedicatedOrForeignOwnersCannotUseGenericInventoryGate(
            string panel)
        {
            JObject request = BuildRequest(panel, "panel.instance.exact");

            Assert.False(WebOverlayForm.IsValidInventoryOwnerEnvelope(
                request, panel, "panel.instance.exact"));
        }

        [Theory]
        [InlineData("workbench")]
        [InlineData("kshop")]
        [InlineData("npcshop")]
        [InlineData("crafting")]
        public void OwnerCloseRequiresStrictExactEnvelope(string panel)
        {
            var close = new JObject
            {
                ["type"] = "panel",
                ["panel"] = panel,
                ["cmd"] = "close",
                ["panelInstanceId"] = "panel.owner.exact"
            };
            Assert.True(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, panel, "panel.owner.exact"));

            close["extra"] = true;
            Assert.False(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, panel, "panel.owner.exact"));
            close.Remove("extra");
            close["type"] = "panel_resp";
            Assert.False(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, panel, "panel.owner.exact"));
            close["type"] = "panel";
            Assert.False(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, panel, "panel.owner.replaced"));
        }

        [Fact]
        public void OnlyCraftingMayUseExactCharacterBuildReturnReason()
        {
            var close = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "crafting",
                ["cmd"] = "close",
                ["panelInstanceId"] = "panel.crafting.return",
                ["reason"] = "navigate_character_build"
            };
            Assert.True(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, "crafting", "panel.crafting.return"));

            close["panel"] = "kshop";
            Assert.False(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, "kshop", "panel.crafting.return"));
            close["panel"] = "crafting";
            close["reason"] = "unknown_reason";
            Assert.False(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, "crafting", "panel.crafting.return"));
        }

        [Theory]
        [InlineData("kshop")]
        [InlineData("npcshop")]
        [InlineData("crafting")]
        public void OwnerCloseAcceptsOnlyKnownLifecycleFailureReasons(
            string panel)
        {
            var close = new JObject
            {
                ["type"] = "panel",
                ["panel"] = panel,
                ["cmd"] = "close",
                ["panelInstanceId"] = "panel.owner.mount",
                ["reason"] = "mount_failed"
            };
            Assert.True(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, panel, "panel.owner.mount"));

            close["reason"] = "mount_failed_other";
            Assert.False(WebOverlayForm.IsValidInventoryOwnerCloseEnvelope(
                close, panel, "panel.owner.mount"));
        }

        [Theory]
        [InlineData("workbench")]
        [InlineData("kshop")]
        [InlineData("npcshop")]
        [InlineData("crafting")]
        [InlineData("loot")]
        [InlineData("skills")]
        public void ForceCloseForHostOwnedPanelsRequiresExactInstance(
            string panel)
        {
            string instance = "panel." + panel + ".current";
            JObject payload = JObject.Parse(
                WebOverlayForm.BuildPanelForceClosePayload(
                    panel, instance, "disconnected"));
            Assert.Equal(panel, (string)payload["panel"]);
            Assert.Equal(instance, (string)payload["panelInstanceId"]);
            Assert.Null(WebOverlayForm.BuildPanelForceClosePayload(
                panel, null, "disconnected"));
        }

        [Fact]
        public void LegacyForceCloseRemainsGeneric()
        {
            JObject payload = JObject.Parse(
                WebOverlayForm.BuildPanelForceClosePayload(
                    "map", "panel.map.ignored", "disconnected"));
            Assert.Null(payload["panel"]);
            Assert.Null(payload["panelInstanceId"]);
        }

        [Theory]
        [InlineData("workbench", false, false, true)]
        [InlineData("workbench", true, false, false)]
        [InlineData("workbench", false, true, false)]
        [InlineData("kshop", true, true, true)]
        [InlineData("help", false, false, false)]
        public void WebNavigationRecoveryScopeIsExplicit(
            string panel,
            bool characterBuildBound,
            bool equipmentTuningBound,
            bool expected)
        {
            Assert.Equal(
                expected,
                WebOverlayForm.ShouldRetireInventoryOwnerOnWebNavigation(
                    panel,
                    characterBuildBound,
                    equipmentTuningBound));
        }

        [Fact]
        public void NavigationAndAcceptedOwnerCloseClearTransportPending()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string navigation = Slice(
                source,
                "_webView.CoreWebView2.NavigationStarting += delegate",
                "_webView.CoreWebView2.ContentLoading += delegate");
            Assert.Contains(
                "RetireAllInventoryOwnerRequests();",
                navigation);
            Assert.Contains(
                "BeginInventoryOwnerWebNavigationRecovery();",
                navigation);
            Assert.Contains(
                "_equipmentTuningTask.ClearPending();",
                source);

            string close = Slice(
                source,
                "case \"close\":",
                "case \"bulkQuery\":");
            int exactOwner = close.IndexOf(
                "IsValidInventoryOwnerCloseEnvelope(",
                StringComparison.Ordinal);
            int retireRequestOwner = close.IndexOf(
                "SealPanelRequestOwner(",
                StringComparison.Ordinal);
            int exactHostClose = close.IndexOf(
                "TryClosePanelExact(",
                StringComparison.Ordinal);
            int commitEffects = close.IndexOf(
                "CommitAcceptedPanelCloseEffects(",
                StringComparison.Ordinal);
            Assert.True(exactOwner >= 0);
            Assert.True(retireRequestOwner > exactOwner);
            Assert.True(exactHostClose > retireRequestOwner);
            Assert.True(commitEffects > retireRequestOwner);
            Assert.Contains(
                "deferInventoryOwnerCloseCommit",
                close);
        }

        [Fact]
        public void AuthoritativeOwnerLifecycleUsesOnlyTheActiveHostSource()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string setHost = Slice(
                source,
                "public void SetPanelHost(PanelHostController host)",
                "public void ResumeForPanel(");
            Assert.Contains(
                "_commandRouter.PanelChanged -= OnAuthoritativePanelChanged;",
                setHost);
            Assert.Contains(
                "_panelHost.PanelChanged += OnAuthoritativePanelChanged;",
                setHost);

            string retire = Slice(
                source,
                "private void RetirePanelRequestOwner(string panelName)",
                "private void RetireAllInventoryOwnerRequests()");
            Assert.Contains("_inventoryTask.ClearPending();", retire);
            Assert.Contains("_shopTask.ClearPending();", retire);
            Assert.Contains("_npcShopTask.ClearPending();", retire);
            Assert.Contains("_craftingTask.ClearPending();", retire);
        }

        [Fact]
        public void BusinessRoutesGateExactOwnerBeforeCallingTasks()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string npc = Slice(
                source,
                "if (domainRoute == PanelDomainRoute.NpcShop)",
                "if (domainRoute == PanelDomainRoute.Crafting)");
            Assert.True(
                npc.IndexOf(
                    "HasExactActivePanelOwnerBinding(parsed, \"npcshop\")",
                    StringComparison.Ordinal)
                < npc.IndexOf(
                    "_npcShopTask.HandleWebRequest(cmd, parsed)",
                    StringComparison.Ordinal));

            string crafting = Slice(
                source,
                "if (domainRoute == PanelDomainRoute.Crafting)",
                "if (domainRoute == PanelDomainRoute.Hairdresser)");
            Assert.True(
                crafting.IndexOf(
                    "HasExactActivePanelOwnerBinding(parsed, \"crafting\")",
                    StringComparison.Ordinal)
                < crafting.IndexOf(
                    "_craftingTask.HandleWebRequest(cmd, parsed)",
                    StringComparison.Ordinal));

            string kshop = Slice(
                source,
                "case \"bulkQuery\":",
                "case \"snapshot\":");
            Assert.True(
                kshop.IndexOf(
                    "HasExactActivePanelOwnerBinding(parsed, \"kshop\")",
                    StringComparison.Ordinal)
                < kshop.IndexOf(
                    "_shopTask.HandleWebRequest(cmd, parsed)",
                    StringComparison.Ordinal));
        }

        [Fact]
        public void PanelMessagesGateDocumentReadinessAndSealedOwnerBeforeDispatch()
        {
            string source = File.ReadAllText(FindWebOverlaySource());
            string handler = Slice(
                source,
                "private void HandlePanelMessage(string json)",
                "private void CommitAcceptedPanelCloseEffects(");
            int readyGate = handler.IndexOf(
                "if (!CanAcceptPanelDocumentMessages)",
                StringComparison.Ordinal);
            int ownerGate = handler.IndexOf(
                "_panelRequestOwnerLifecycle.IsAdmittedExact(",
                StringComparison.Ordinal);
            int inventoryDispatch = handler.IndexOf(
                "_inventoryTask.HandleWebRequest(cmd, parsed)",
                StringComparison.Ordinal);
            int npcDispatch = handler.IndexOf(
                "_npcShopTask.HandleWebRequest(cmd, parsed)",
                StringComparison.Ordinal);
            int craftingDispatch = handler.IndexOf(
                "_craftingTask.HandleWebRequest(cmd, parsed)",
                StringComparison.Ordinal);
            int shopDispatch = handler.IndexOf(
                "_shopTask.HandleWebRequest(cmd, parsed)",
                StringComparison.Ordinal);

            Assert.True(readyGate >= 0);
            Assert.True(ownerGate > readyGate);
            Assert.True(ownerGate < inventoryDispatch);
            Assert.True(ownerGate < npcDispatch);
            Assert.True(ownerGate < craftingDispatch);
            Assert.True(ownerGate < shopDispatch);
        }

        [Fact]
        public void PanelAdmissionWaitsForAReadyDocumentAndCharacterOwnerRelease()
        {
            string source = File.ReadAllText(FindProgramSource());
            string openGate = Slice(
                source,
                "panelHost.SetOpenGate(delegate(string panelName)",
                "panelHost.SetRebindGate(delegate(string panelName)");
            Assert.Contains(
                "webOverlay.CanAcceptPanelDocumentMessages",
                openGate);
            Assert.Contains(
                "!characterBuildTask.HasBoundPanel",
                openGate);

            string rebindGate = Slice(
                source,
                "panelHost.SetRebindGate(delegate(string panelName)",
                "panelHost.SetInitDataEnricher(");
            Assert.Contains(
                "webOverlay.CanAcceptPanelDocumentMessages",
                rebindGate);
            Assert.Contains(
                "characterBuildTask.HasBoundPanel",
                rebindGate);
        }

        private static bool IsValid(JObject request)
        {
            return WebOverlayForm.IsValidInventoryOwnerEnvelope(
                request, "crafting", "panel.crafting.exact");
        }

        private static JObject BuildRequest(
            string panel, string panelInstanceId)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = panel,
                ["domain"] = "inventory",
                ["cmd"] = "snapshot",
                ["callId"] = "inventory.snapshot.1",
                ["panelInstanceId"] = panelInstanceId,
                ["payload"] = new JObject { ["v"] = 1 }
            };
        }

        private static string Slice(
            string source, string startMarker, string endMarker)
        {
            int start = source.IndexOf(
                startMarker, StringComparison.Ordinal);
            Assert.True(start >= 0);
            int end = source.IndexOf(
                endMarker, start, StringComparison.Ordinal);
            Assert.True(end > start);
            return source.Substring(start, end - start);
        }

        private static string FindWebOverlaySource()
        {
            DirectoryInfo current =
                new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string candidate = Path.Combine(
                    current.FullName,
                    "launcher", "src", "Guardian",
                    "WebOverlayForm.cs");
                if (File.Exists(candidate)) return candidate;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                "Unable to locate launcher/src/Guardian/WebOverlayForm.cs");
        }

        private static string FindProgramSource()
        {
            DirectoryInfo current =
                new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string candidate = Path.Combine(
                    current.FullName,
                    "launcher", "src", "Program.cs");
                if (File.Exists(candidate)) return candidate;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                "Unable to locate launcher/src/Program.cs");
        }
    }
}
