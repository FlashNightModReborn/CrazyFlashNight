using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelHostDocumentFailureTests
    {
        private sealed class Harness : IDisposable
        {
            internal readonly Queue<Action> Pumps = new Queue<Action>();
            internal readonly List<string> Rejected = new List<string>();
            internal readonly PanelHostController Host;
            internal bool Ready;
            internal bool Failed;
            internal Harness()
            {
                Host = new PanelHostController(action => Pumps.Enqueue(action), action => action());
                Host.SetOpenGate(_ => Ready);
                Host.SetDocumentUnavailableGate(() => Failed);
                Host.PanelOpenRejected += (name, reason) => Rejected.Add(name + ":" + reason);
            }
            internal void Pump() { while (Pumps.Count != 0) Pumps.Dequeue()(); }
            internal void Open(string name) { Assert.True(Host.TryOpenPanel(name, "{}", null, null)); Pump(); }
            public void Dispose() => Host.Dispose();
        }

        [Theory]
        [InlineData("kshop", "shopPanelClose")]
        [InlineData("stage-select", "stageSelectPanelClose")]
        [InlineData("map", "mapPanelClose")]
        [InlineData("tasks", "taskPanelClose")]
        public void InitFailure_RetiresDeferredLegacyOpenOnce(string panel, string closeCommand)
        {
            using var h = new Harness();
            h.Open(panel);
            Assert.Null(h.Host.ActivePanelName);
            Assert.Empty(h.Rejected);
            h.Failed = true;
            h.Host.FailUnavailableOpenRequests();
            h.Host.FailUnavailableOpenRequests();
            Assert.Equal(new[] { panel + ":document_unavailable" }, h.Rejected);
            Assert.Equal(closeCommand, WebOverlayForm.ResolvePanelCloseGameCommand(panel));
            h.Ready = true;
            h.Host.FlushDeferredBarrierOpen();
            h.Pump();
            Assert.Null(h.Host.ActivePanelName);
        }

        [Fact]
        public void NewRequestAfterFailure_IsRejectedWithoutRetainedReturnEdge()
        {
            using var h = new Harness { Failed = true };
            Assert.True(h.Host.TryOpenPanel("stage-select", "{}", "map", "{}"));
            h.Pump();
            h.Failed = false;
            h.Ready = true;
            h.Host.FlushDeferredBarrierOpen();
            h.Pump();
            Assert.Null(h.Host.ActivePanelName);
            Assert.Equal(new[] { "stage-select:document_unavailable" }, h.Rejected);
            h.Open("map");
            Assert.Equal("map", h.Host.ActivePanelName);
        }

        [Fact]
        public void SupersedingUnpostedShop_RetiresShopButRetainsLatestIntent()
        {
            using var h = new Harness();
            h.Open("kshop");
            h.Open("stage-select");
            Assert.Equal(new[] { "kshop:superseded_before_open" }, h.Rejected);
            h.Ready = true;
            h.Host.FlushDeferredBarrierOpen();
            h.Pump();
            Assert.Equal("stage-select", h.Host.ActivePanelName);
        }

        [Fact]
        public void AuthorityBarrier_IsNotMistakenForDocumentFailure()
        {
            using var h = new Harness();
            h.Open("stage-select");
            h.Host.FlushDeferredBarrierOpen();
            h.Pump();
            Assert.Empty(h.Rejected);
            h.Ready = true;
            h.Host.FlushDeferredBarrierOpen();
            h.Pump();
            Assert.Equal("stage-select", h.Host.ActivePanelName);
        }

        [Fact]
        public void FailedRebind_DoesNotReleasePresentedShopInstance()
        {
            using var h = new Harness { Ready = true };
            h.Open("kshop");
            string original = h.Host.ActivePanelInstanceId;
            h.Failed = true;
            h.Open("kshop");
            h.Host.FailUnavailableOpenRequests();
            Assert.Equal(original, h.Host.ActivePanelInstanceId);
            Assert.Empty(h.Rejected);
        }
    }
}
