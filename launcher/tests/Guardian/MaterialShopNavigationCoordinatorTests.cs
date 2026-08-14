using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Launcher.Tests.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class MaterialShopNavigationCoordinatorTests
    {
        private sealed class ManualDeadline : IDisposable
        {
            internal readonly Action Callback;
            internal bool Disposed;

            internal ManualDeadline(Action callback)
            {
                Callback = callback;
            }

            internal void Fire()
            {
                if (!Disposed) Callback();
            }

            public void Dispose()
            {
                Disposed = true;
            }
        }

        private sealed class Harness : IDisposable
        {
            internal readonly Queue<Action> Pumps = new Queue<Action>();
            internal readonly List<string> Web = new List<string>();
            internal readonly List<JObject> Authority = new List<JObject>();
            internal readonly List<JObject> NpcWire = new List<JObject>();
            internal readonly List<JObject> PanelPosts = new List<JObject>();
            internal readonly List<ManualDeadline> Deadlines = new List<ManualDeadline>();
            internal readonly PanelHostController Host;
            internal readonly LauncherCommandRouter Router;
            internal readonly MaterialShopAccessTask Access;
            internal readonly InventoryTask Inventory;
            internal readonly NpcShopTask NpcShop;
            internal readonly CraftingTaskMaterialsV2Tests.Harness CraftingHarness;
            internal readonly MaterialShopNavigationCoordinator Coordinator;
            internal long Now;
            internal Func<long> Clock;
            internal int NextInstance;
            internal readonly string SourceInstance;

            internal Harness(bool deliverPanelPost = true)
            {
                Host = new PanelHostController(
                    action => Pumps.Enqueue(action),
                    action => action());
                Assert.True(Host.TryOpenPanel("crafting", "{}", null, null));
                Pump();
                SourceInstance = Host.ActivePanelInstanceId;
                CraftingHarness = CraftingTaskMaterialsV2Tests.OpenV2Session(
                    "materials.snapshot.42", null, SourceInstance);
                Inventory = new InventoryTask(() => true, _ => true);
                NpcShop = new NpcShopTask(
                    () => true,
                    value =>
                    {
                        NpcWire.Add(JObject.Parse(value.TrimEnd('\0')));
                        return true;
                    });
                Access = new MaterialShopAccessTask(
                    () => true,
                    value =>
                    {
                        Authority.Add(JObject.Parse(value.TrimEnd('\0')));
                        return true;
                    });
                Router = new LauncherCommandRouter(
                    null,
                    (Action<Keys>)null,
                    null,
                    null,
                    null,
                    _ => { },
                    _ => { },
                    _ => { });
                Router.SetPanelHost(Host);
                Clock = () => Now;
                Coordinator = new MaterialShopNavigationCoordinator(
                    Host,
                    Access,
                    CraftingHarness.Task,
                    Inventory,
                    NpcShop,
                    Router,
                    value => { Web.Add(value); return true; },
                    () => Clock(),
                    (milliseconds, callback) =>
                    {
                        Assert.Equal(
                            MaterialShopNavigationCoordinator.MaterialShopNavigationTimeoutMs,
                            milliseconds);
                        var deadline = new ManualDeadline(callback);
                        Deadlines.Add(deadline);
                        return deadline;
                    },
                    () => "panel.material.target." + (++NextInstance));
                Host.SetExactReplacePosterForTests(value =>
                {
                    PanelPosts.Add(JObject.Parse(value));
                    return deliverPanelPost;
                });
                BindOwners("crafting", SourceInstance);
            }

            internal void BindOwners(string panel, string instance)
            {
                CraftingHarness.Task.BindMaterialShopNavigationOwner(panel, instance);
                Inventory.BindMaterialShopNavigationOwner(panel, instance);
                NpcShop.BindMaterialShopNavigationOwner(panel, instance);
            }

            internal void Pump()
            {
                Action action = Assert.Single(Pumps);
                Pumps.Clear();
                action();
            }

            internal void Allow()
            {
                int fid = Authority[Authority.Count - 1].Value<int>("callId");
                Access.HandleFlashResponse(AllowResponse(fid), null);
            }

            internal JObject LastWeb()
            {
                return JObject.Parse(Web[Web.Count - 1]);
            }

            internal void PrimeNpcCatalog(string instance)
            {
                NpcShop.HandleWebRequest(
                    "snapshot",
                    NpcSnapshotRequest(instance));
                int fid = NpcWire[NpcWire.Count - 1].Value<int>("callId");
                NpcShop.HandleFlashResponse(NpcSnapshotResponse(fid), null);
            }

            public void Dispose()
            {
                Coordinator.Dispose();
                Access.Dispose();
                NpcShop.Dispose();
                Inventory.Dispose();
                CraftingHarness.Dispose();
                Host.Dispose();
            }
        }

        [Fact]
        public void FlatEnvelopesAndOuterCloseAreExact()
        {
            JObject forward = Forward("panel.crafting");
            JObject reverse = Reverse("panel.npcshop");
            JObject close = Close("panel.npcshop", "escape");
            JObject systemClose = SystemClose("panel.npcshop");

            Assert.True(MaterialShopNavigationCoordinator.IsValidForwardEnvelope(forward));
            Assert.True(MaterialShopNavigationCoordinator.IsValidReverseEnvelope(reverse));
            Assert.True(MaterialShopNavigationCoordinator.IsValidNpcShopOuterCloseEnvelope(close));
            Assert.True(MaterialShopNavigationCoordinator
                .IsValidNpcShopSystemFailureCloseEnvelope(systemClose));

            forward["preferredItemName"] = "战术握把";
            reverse["materialName"] = "战术握把";
            close["reason"] = "keyboard";
            Assert.False(MaterialShopNavigationCoordinator.IsValidForwardEnvelope(forward));
            Assert.False(MaterialShopNavigationCoordinator.IsValidReverseEnvelope(reverse));
            Assert.False(MaterialShopNavigationCoordinator.IsValidNpcShopOuterCloseEnvelope(close));
            systemClose["reason"] = "mount_failed";
            Assert.False(MaterialShopNavigationCoordinator
                .IsValidNpcShopSystemFailureCloseEnvelope(systemClose));

            forward.Remove("preferredItemName");
            forward["catalogIndex"] = 10001;
            Assert.False(MaterialShopNavigationCoordinator.IsValidForwardEnvelope(forward));
        }

        [Fact]
        public void ForwardAndReverse_CommitStrictInitDataWithoutSuccessAck()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            Assert.Single(harness.Authority);
            Assert.Equal(
                MaterialShopNavigationCoordinator.TransitionPhase.AuthorityPending,
                harness.Coordinator.ActivePhaseForTests);

            harness.Allow();
            harness.Pump();

            Assert.Equal("npcshop", harness.Host.ActivePanelName);
            string npcInstance = harness.Host.ActivePanelInstanceId;
            Assert.True(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
            Assert.Empty(harness.Web);
            Assert.False(harness.CraftingHarness.Task
                .TryAcquireMaterialShopNavigationLease(
                    "crafting",
                    harness.SourceInstance,
                    "lease.must-remain-transferred.forward",
                    "materials.snapshot.42",
                    "战术握把",
                    out _));
            Assert.False(harness.Inventory.TryAcquireMaterialShopNavigationLease(
                "crafting",
                harness.SourceInstance,
                "lease.must-remain-transferred.forward",
                out _));
            JObject npcInit = (JObject)harness.PanelPosts[0]["initData"];
            Assert.Equal(9, npcInit.Count);
            Assert.Equal("crafting_materials", npcInit.Value<string>("source"));
            Assert.Equal("战术握把", npcInit.Value<string>("preferredItemName"));
            Assert.Equal(57, npcInit.Value<int>("preferredCatalogIndex"));
            Assert.True(npcInit.Value<bool>("canReturnCraftingMaterials"));
            Assert.Equal(npcInstance, npcInit.Value<string>("panelInstanceId"));

            // Mirror WebOverlay's authoritative owner-retirement/bind sequence.
            harness.CraftingHarness.Task.ClearPending();
            harness.Inventory.ClearPending();
            harness.Coordinator.OnPanelChanged("npcshop", npcInstance);
            harness.BindOwners("npcshop", npcInstance);
            harness.PrimeNpcCatalog(npcInstance);

            harness.Coordinator.HandleReverse(Reverse(npcInstance));
            harness.Pump();

            Assert.Equal("crafting", harness.Host.ActivePanelName);
            Assert.False(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
            Assert.Empty(harness.Web);
            Assert.False(harness.NpcShop.TryAcquireMaterialShopNavigationLease(
                "npcshop",
                npcInstance,
                "lease.must-remain-transferred.reverse",
                "迷之盔甲君",
                out _));
            Assert.False(harness.Inventory.TryAcquireMaterialShopNavigationLease(
                "npcshop",
                npcInstance,
                "lease.must-remain-transferred.reverse",
                out _));
            JObject craftingInit = (JObject)harness.PanelPosts[1]["initData"];
            Assert.Equal(6, craftingInit.Count);
            Assert.Equal("materials", craftingInit.Value<string>("view"));
            Assert.Equal("npcshop_return", craftingInit.Value<string>("source"));
            Assert.Equal("战术握把", craftingInit.Value<string>("preferredMaterialName"));
        }

        [Fact]
        public void CancelAllAfterReverseCommitPermit_CannotConsumeRouteMidCommit()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            harness.Pump();
            string npcInstance = harness.Host.ActivePanelInstanceId;
            harness.CraftingHarness.Task.ClearPending();
            harness.Inventory.ClearPending();
            harness.Coordinator.OnPanelChanged("npcshop", npcInstance);
            harness.BindOwners("npcshop", npcInstance);
            harness.PrimeNpcCatalog(npcInstance);
            harness.Host.SetExactReplacePosterForTests(value =>
            {
                harness.PanelPosts.Add(JObject.Parse(value));
                harness.Coordinator.CancelAll("during_reverse_commit");
                Assert.True(harness.Coordinator.HasMaterialReturnRoute(
                    npcInstance));
                return true;
            });

            harness.Coordinator.HandleReverse(Reverse(npcInstance));
            harness.Pump();

            Assert.Equal("crafting", harness.Host.ActivePanelName);
            Assert.False(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
            Assert.Null(harness.Coordinator.ActivePhaseForTests);
        }

        [Fact]
        public void DeadlineConstants_ReserveTheFrozenDeliveryMargin()
        {
            Assert.Equal(
                5000,
                MaterialShopNavigationCoordinator.MaterialShopNavigationTimeoutMs);
            Assert.Equal(
                1500,
                MaterialShopNavigationCoordinator.MaterialShopNavigationDeliveryMarginMs);
            Assert.Equal(
                6500,
                MaterialShopNavigationCoordinator.MaterialShopNavigationWebWatchdogMs);
        }

        [Fact]
        public void WebSendDeliveryMargin_AllowsPermitBefore6500AndFencesBoundaryLateAllow()
        {
            using (var beforeBoundary = new Harness())
            {
                // Web sent at t=0; controlled Host ingress consumes the full 1500ms margin.
                beforeBoundary.Now =
                    MaterialShopNavigationCoordinator
                        .MaterialShopNavigationDeliveryMarginMs;
                beforeBoundary.Coordinator.HandleForward(
                    Forward(beforeBoundary.SourceInstance));
                beforeBoundary.Now =
                    MaterialShopNavigationCoordinator
                        .MaterialShopNavigationWebWatchdogMs - 1;

                beforeBoundary.Allow();
                beforeBoundary.Pump();

                Assert.Equal("npcshop", beforeBoundary.Host.ActivePanelName);
                Assert.Null(beforeBoundary.Coordinator.ActivePhaseForTests);
            }

            using (var atBoundary = new Harness())
            {
                atBoundary.Now =
                    MaterialShopNavigationCoordinator
                        .MaterialShopNavigationDeliveryMarginMs;
                atBoundary.Coordinator.HandleForward(
                    Forward(atBoundary.SourceInstance));
                int fid = Assert.Single(atBoundary.Authority)
                    .Value<int>("callId");
                atBoundary.Now =
                    MaterialShopNavigationCoordinator
                        .MaterialShopNavigationWebWatchdogMs;

                Assert.Single(atBoundary.Deadlines).Fire();
                atBoundary.Access.HandleFlashResponse(
                    AllowResponse(fid), null);

                Assert.Equal("timeout", atBoundary.LastWeb()
                    .Value<string>("error"));
                Assert.Empty(atBoundary.Pumps);
                Assert.Equal("crafting", atBoundary.Host.ActivePanelName);
            }
        }

        [Fact]
        public void ForwardAllocation_LogsExactWebToFidOwnerBindingWithoutBusinessPayload()
        {
            using var harness = new Harness();
            var lines = new List<string>();
            LogManager.SetSink(lines.Add);
            try
            {
                harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            }
            finally
            {
                LogManager.ResetSink();
            }

            int fid = Assert.Single(harness.Authority).Value<int>("callId");
            string receipt = Assert.Single(lines, line =>
                line.StartsWith(
                    "event=authority_flash_call_bound",
                    StringComparison.Ordinal));
            Assert.Equal(
                "event=authority_flash_call_bound"
                + " domain=material_shop_access"
                + " webCallIdRef="
                + AuthorityLogFormatter.CreateReference("material.open.1")
                + " flashCallId=" + fid
                + " panel=crafting"
                + " panelInstanceIdRef="
                + AuthorityLogFormatter.CreateReference(harness.SourceInstance)
                + " cmd=open_npc_shop"
                + " action=craftingMaterialShopAuthorize",
                receipt);
            Assert.DoesNotContain("material.open.1", receipt);
            Assert.DoesNotContain(harness.SourceInstance, receipt);
            Assert.DoesNotContain("战术握把", receipt);
            Assert.DoesNotContain("迷之盔甲君", receipt);
            Assert.DoesNotContain("materials.snapshot.42", receipt);
        }

        [Fact]
        public void SingleDeadline_TimesOutAndLateAllowCannotOpenTarget()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            Assert.Single(harness.Deadlines);
            harness.Now = MaterialShopNavigationCoordinator.MaterialShopNavigationTimeoutMs;

            harness.Deadlines[0].Fire();

            Assert.Equal("timeout", harness.LastWeb().Value<string>("error"));
            Assert.Equal("crafting", harness.Host.ActivePanelName);
            Assert.Null(harness.Coordinator.ActivePhaseForTests);
            harness.Allow();
            Assert.Empty(harness.Pumps);
            Assert.Equal("crafting", harness.Host.ActivePanelName);
        }

        [Fact]
        public void ExactSourceClose_CancelsPendingAuthorityAndLateAllowCannotOpenTarget()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            int fid = Assert.Single(harness.Authority).Value<int>("callId");

            Assert.False(harness.Coordinator.CancelPreCommitForSource(
                "crafting",
                "foreign.instance",
                "source_close"));
            Assert.True(harness.Coordinator.CancelPreCommitForSource(
                "crafting",
                harness.SourceInstance,
                "source_close"));

            Assert.Null(harness.Coordinator.ActivePhaseForTests);
            Assert.Equal(0, harness.Access.PendingCount);
            harness.Access.HandleFlashResponse(AllowResponse(fid), null);
            Assert.Empty(harness.Pumps);
            Assert.Equal("crafting", harness.Host.ActivePanelName);
        }

        [Fact]
        public void ExactSourceClose_AfterForwardTargetReserved_DrainsReplaceThenClosesOnce()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            int closeAdmission = 0;
            int closeCommit = 0;

            Assert.True(harness.Coordinator
                .TryHandlePreCommitCraftingSourceClose(
                    "crafting",
                    harness.SourceInstance,
                    delegate
                    {
                        closeAdmission++;
                        return harness.Host.TryClosePanelExact(
                            "crafting",
                            harness.SourceInstance,
                            false,
                            closed =>
                            {
                                if (closed) closeCommit++;
                            });
                    }));
            Assert.Equal(0, closeAdmission);

            harness.Pump();

            Assert.Equal(1, closeAdmission);
            Assert.Equal(1, closeCommit);
            Assert.False(harness.Host.IsPanelOpen);
            Assert.Empty(harness.PanelPosts);
            Assert.False(harness.Coordinator.HasMaterialReturnRoute(
                "panel.material.target.1"));
        }

        [Fact]
        public void DeadlineExpiringDuringFixedLeaseAcquisition_ReleasesEveryFence()
        {
            using var harness = new Harness();
            int reads = 0;
            harness.Clock = delegate
            {
                reads++;
                return reads >= 3
                    ? MaterialShopNavigationCoordinator.MaterialShopNavigationTimeoutMs
                    : 0;
            };

            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));

            Assert.Empty(harness.Authority);
            Assert.Equal("timeout", harness.LastWeb().Value<string>("error"));
            Assert.True(harness.CraftingHarness.Task.TryAcquireMaterialShopNavigationLease(
                "crafting",
                harness.SourceInstance,
                "lease.after-mid-acquire-deadline",
                "materials.snapshot.42",
                "战术握把",
                out MaterialShopSettlementWitness craftingWitness));
            Assert.True(harness.Inventory.TryAcquireMaterialShopNavigationLease(
                "crafting",
                harness.SourceInstance,
                "lease.after-mid-acquire-deadline",
                out MaterialShopSettlementWitness inventoryWitness));
            Assert.True(harness.Inventory.ReleaseMaterialShopNavigationLease(
                inventoryWitness));
            Assert.True(harness.CraftingHarness.Task.ReleaseMaterialShopNavigationLease(
                craftingWitness));
        }

        [Fact]
        public void DuplicateCoalescesConflictAuditsAndNewCallGetsBusy()
        {
            using var harness = new Harness();
            JObject first = Forward(harness.SourceInstance);
            harness.Coordinator.HandleForward(first);
            harness.Coordinator.HandleForward((JObject)first.DeepClone());
            JObject conflict = (JObject)first.DeepClone();
            conflict["shopId"] = "另一个合法商店";
            harness.Coordinator.HandleForward(conflict);
            JObject second = (JObject)first.DeepClone();
            second["callId"] = "material.open.2";
            harness.Coordinator.HandleForward(second);

            Assert.Single(harness.Authority);
            Assert.Single(harness.Web);
            JObject busy = harness.LastWeb();
            Assert.Equal("busy", busy.Value<string>("error"));
            Assert.Equal("material.open.2", busy.Value<string>("callId"));
            Assert.Equal(7, busy.Count);
        }

        [Fact]
        public void PostNotDelivered_PreservesSourceAndReleasesLeases()
        {
            using var harness = new Harness(false);
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            harness.Pump();

            Assert.Equal("crafting", harness.Host.ActivePanelName);
            Assert.Equal(harness.SourceInstance, harness.Host.ActivePanelInstanceId);
            Assert.Equal("navigation_unavailable", harness.LastWeb().Value<string>("error"));
            Assert.False(harness.Coordinator.HasMaterialReturnRoute("panel.material.target.1"));
            Assert.True(harness.CraftingHarness.Task.TryAcquireMaterialShopNavigationLease(
                "crafting",
                harness.SourceInstance,
                "lease.after-post-failure",
                "materials.snapshot.42",
                "战术握把",
                out _));
        }

        [Fact]
        public void ForwardImmediateHostAdmissionFailure_ReleasesBothLeases()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            Assert.True(harness.Host.TryClosePanelExact(
                "crafting",
                harness.SourceInstance,
                null));

            harness.Allow();

            Assert.Equal("admission_failed", harness.LastWeb()
                .Value<string>("error"));
            Assert.True(harness.CraftingHarness.Task
                .TryAcquireMaterialShopNavigationLease(
                    "crafting",
                    harness.SourceInstance,
                    "lease.after-api-false",
                    "materials.snapshot.42",
                    "战术握把",
                    out MaterialShopSettlementWitness craftingWitness));
            Assert.True(harness.Inventory.TryAcquireMaterialShopNavigationLease(
                "crafting",
                harness.SourceInstance,
                "lease.after-api-false",
                out MaterialShopSettlementWitness inventoryWitness));
            Assert.True(harness.Inventory.ReleaseMaterialShopNavigationLease(
                inventoryWitness));
            Assert.True(harness.CraftingHarness.Task
                .ReleaseMaterialShopNavigationLease(craftingWitness));
        }

        [Fact]
        public void ForwardHostUnavailableAfterAdmission_ReleasesBothLeases()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();

            harness.Host.Dispose();

            Assert.Equal("navigation_unavailable", harness.LastWeb()
                .Value<string>("error"));
            Assert.True(harness.CraftingHarness.Task
                .TryAcquireMaterialShopNavigationLease(
                    "crafting",
                    harness.SourceInstance,
                    "lease.after-host-unavailable",
                    "materials.snapshot.42",
                    "战术握把",
                    out MaterialShopSettlementWitness craftingWitness));
            Assert.True(harness.Inventory.TryAcquireMaterialShopNavigationLease(
                "crafting",
                harness.SourceInstance,
                "lease.after-host-unavailable",
                out MaterialShopSettlementWitness inventoryWitness));
            Assert.True(harness.Inventory.ReleaseMaterialShopNavigationLease(
                inventoryWitness));
            Assert.True(harness.CraftingHarness.Task
                .ReleaseMaterialShopNavigationLease(craftingWitness));
        }

        [Fact]
        public void ForwardSourceMismatch_ReleasesLeaseAndCapsuleForExactRetry()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            SetActivePanelInstanceForRace(
                harness.Host,
                "panel.crafting.superseded");
            harness.Pump();

            // The old source tuple is no longer active, so the strict coordinator must not
            // deliver even a failure envelope to that retired document.
            Assert.Empty(harness.Web);
            Assert.Empty(harness.PanelPosts);
            SetActivePanelInstanceForRace(
                harness.Host,
                harness.SourceInstance);
            JObject retry = Forward(harness.SourceInstance);
            retry["callId"] = "material.open.retry";

            harness.Coordinator.HandleForward(retry);
            Assert.Equal(2, harness.Authority.Count);
            harness.Allow();
            harness.Pump();

            Assert.Equal("npcshop", harness.Host.ActivePanelName);
            Assert.Single(harness.PanelPosts);
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void ReversePostFailureOrThrow_ReleasesLeaseAndCapsuleForExactRetry(
            bool throws)
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            harness.Pump();
            string npcInstance = harness.Host.ActivePanelInstanceId;
            harness.CraftingHarness.Task.ClearPending();
            harness.Inventory.ClearPending();
            harness.Coordinator.OnPanelChanged("npcshop", npcInstance);
            harness.BindOwners("npcshop", npcInstance);
            harness.PrimeNpcCatalog(npcInstance);
            harness.Host.SetExactReplacePosterForTests(_ =>
            {
                if (throws) throw new InvalidOperationException("fixture");
                return false;
            });

            harness.Coordinator.HandleReverse(Reverse(npcInstance));
            harness.Pump();

            Assert.Equal("navigation_unavailable", harness.LastWeb()
                .Value<string>("error"));
            Assert.Equal("npcshop", harness.Host.ActivePanelName);
            Assert.True(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
            harness.Host.SetExactReplacePosterForTests(value =>
            {
                harness.PanelPosts.Add(JObject.Parse(value));
                return true;
            });
            JObject retry = Reverse(npcInstance);
            retry["callId"] = "material.return.retry";

            harness.Coordinator.HandleReverse(retry);
            harness.Pump();

            Assert.Equal("crafting", harness.Host.ActivePanelName);
            Assert.False(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
            Assert.Equal(2, harness.PanelPosts.Count);
        }

        [Fact]
        public void ReversePreExecutionDeadline_ReleasesLeaseAndCapsuleForExactRetry()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            harness.Pump();
            string npcInstance = harness.Host.ActivePanelInstanceId;
            harness.CraftingHarness.Task.ClearPending();
            harness.Inventory.ClearPending();
            harness.Coordinator.OnPanelChanged("npcshop", npcInstance);
            harness.BindOwners("npcshop", npcInstance);
            harness.PrimeNpcCatalog(npcInstance);

            harness.Coordinator.HandleReverse(Reverse(npcInstance));
            harness.Now = MaterialShopNavigationCoordinator
                .MaterialShopNavigationTimeoutMs;
            harness.Pump();

            Assert.Equal("timeout", harness.LastWeb().Value<string>("error"));
            Assert.Equal("npcshop", harness.Host.ActivePanelName);
            Assert.True(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
            JObject retry = Reverse(npcInstance);
            retry["callId"] = "material.return.after-timeout";

            harness.Coordinator.HandleReverse(retry);
            harness.Pump();

            Assert.Equal("crafting", harness.Host.ActivePanelName);
            Assert.False(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
        }

        [Theory]
        [InlineData("button")]
        [InlineData("escape")]
        [InlineData("backdrop")]
        [InlineData("toggle")]
        public void MaterialRouteOuterClose_WithoutCatalog_ConsumesOnlyAtExactHostCommit(
            string reason)
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            harness.Pump();
            string npcInstance = harness.Host.ActivePanelInstanceId;
            harness.CraftingHarness.Task.ClearPending();
            harness.Inventory.ClearPending();
            harness.Coordinator.OnPanelChanged("npcshop", npcInstance);
            harness.BindOwners("npcshop", npcInstance);
            bool closedCommit = false;

            Assert.True(harness.Coordinator.TryHandleMaterialRouteOuterClose(
                Close(npcInstance, reason),
                () => closedCommit = true));
            Assert.True(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
            harness.Pump();

            Assert.True(closedCommit);
            Assert.False(harness.Host.IsPanelOpen);
            Assert.False(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
        }

        [Fact]
        public void MaterialRouteSystemFailureClose_ConsumesCommittedRouteWithoutCatalog()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            harness.Pump();
            string npcInstance = harness.Host.ActivePanelInstanceId;
            harness.CraftingHarness.Task.ClearPending();
            harness.Inventory.ClearPending();
            harness.Coordinator.OnPanelChanged("npcshop", npcInstance);
            harness.BindOwners("npcshop", npcInstance);
            int committed = 0;

            Assert.True(harness.Coordinator.TryHandleMaterialRouteOuterClose(
                SystemClose(npcInstance),
                () => committed++));
            harness.Pump();

            Assert.Equal(1, committed);
            Assert.False(harness.Host.IsPanelOpen);
            Assert.False(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
        }

        [Fact]
        public void OuterClose_AfterReverseTargetReserved_AbortsReturnAndClosesNpcShopOnce()
        {
            using var harness = new Harness();
            harness.Coordinator.HandleForward(Forward(harness.SourceInstance));
            harness.Allow();
            harness.Pump();
            string npcInstance = harness.Host.ActivePanelInstanceId;
            harness.CraftingHarness.Task.ClearPending();
            harness.Inventory.ClearPending();
            harness.Coordinator.OnPanelChanged("npcshop", npcInstance);
            harness.BindOwners("npcshop", npcInstance);
            harness.PrimeNpcCatalog(npcInstance);
            harness.Coordinator.HandleReverse(Reverse(npcInstance));
            int closedCommit = 0;

            Assert.True(harness.Coordinator.TryHandleMaterialRouteOuterClose(
                Close(npcInstance, "escape"),
                () => closedCommit++));
            Assert.True(harness.Coordinator.HasMaterialReturnRoute(npcInstance));

            harness.Pump();

            Assert.Equal(1, closedCommit);
            Assert.False(harness.Host.IsPanelOpen);
            Assert.False(harness.Coordinator.HasMaterialReturnRoute(npcInstance));
            Assert.Single(harness.PanelPosts);
            Assert.Equal("npcshop", harness.PanelPosts[0].Value<string>("panel"));
        }

        private static JObject Forward(string instance)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "crafting",
                ["cmd"] = "open_npc_shop",
                ["callId"] = "material.open.1",
                ["panelInstanceId"] = instance,
                ["source"] = "crafting_materials",
                ["materialSnapshotId"] = "materials.snapshot.42",
                ["materialName"] = "战术握把",
                ["shopId"] = "迷之盔甲君",
                ["catalogIndex"] = 57
            };
        }

        private static JObject Reverse(string instance)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "npcshop",
                ["cmd"] = "return_crafting_materials",
                ["callId"] = "material.return.1",
                ["panelInstanceId"] = instance
            };
        }

        private static JObject Close(string instance, string reason)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "npcshop",
                ["cmd"] = "close",
                ["panelInstanceId"] = instance,
                ["reason"] = reason
            };
        }

        private static JObject SystemClose(string instance)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "npcshop",
                ["cmd"] = "close",
                ["panelInstanceId"] = instance
            };
        }

        private static JObject AllowResponse(int fid)
        {
            return new JObject
            {
                ["task"] = "material_shop_access_response",
                ["callId"] = fid,
                ["success"] = true,
                ["v"] = 1,
                ["decision"] = "allow",
                ["reason"] = "indexed_live_match",
                ["materialSnapshotId"] = "materials.snapshot.42",
                ["materialName"] = "战术握把",
                ["shopId"] = "迷之盔甲君",
                ["catalogIndex"] = 57,
                ["itemName"] = "战术握把"
            };
        }

        private static JObject NpcSnapshotRequest(string instance)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "npcshop",
                ["domain"] = "npcshop",
                ["panelInstanceId"] = instance,
                ["cmd"] = "snapshot",
                ["callId"] = "npc.material.snapshot",
                ["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["shopId"] = "迷之盔甲君"
                }
            };
        }

        private static JObject NpcSnapshotResponse(int fid)
        {
            JObject emptyView(string id) => new JObject
            {
                ["containerId"] = id,
                ["capacity"] = 0,
                ["accessibleCapacity"] = 0,
                ["viewCapacity"] = 0,
                ["offset"] = 0,
                ["limit"] = 0,
                ["filterKey"] = "all",
                ["slots"] = new JArray()
            };
            return new JObject
            {
                ["task"] = "npcshop_response",
                ["callId"] = fid,
                ["success"] = true,
                ["v"] = 1,
                ["shopId"] = "迷之盔甲君",
                ["balance"] = 5000,
                ["buyMultiplier"] = 1,
                ["catalog"] = new JArray(new JObject
                {
                    ["catalogIndex"] = 57,
                    ["itemName"] = "战术握把",
                    ["displayName"] = "战术握把",
                    ["icon"] = "战术握把",
                    ["majorType"] = "材料",
                    ["use"] = "材料",
                    ["actionType"] = "",
                    ["weaponType"] = "",
                    ["setId"] = "",
                    ["setName"] = "",
                    ["setOrder"] = 0,
                    ["basePrice"] = 1000,
                    ["unitPrice"] = 1000,
                    ["maxQuantity"] = 50,
                    ["requiredInfo"] = "",
                    ["locked"] = false
                }),
                ["layout"] = new JObject
                {
                    ["title"] = "迷之盔甲君",
                    ["defaultSection"] = "",
                    ["sections"] = new JArray()
                },
                ["views"] = new JObject
                {
                    ["material"] = emptyView("材料"),
                    ["intelligence"] = emptyView("情报")
                }
            };
        }

        private static void SetActivePanelInstanceForRace(
            PanelHostController host,
            string panelInstanceId)
        {
            FieldInfo field = typeof(PanelHostController).GetField(
                "_activePanelInstanceId",
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            field.SetValue(host, panelInstanceId);
        }
    }
}
