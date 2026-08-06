using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelRequestOwnerLifecycleTests
    {
        [Fact]
        public void SameNameFreshInstanceRetiresThePreviousExactDocument()
        {
            var lifecycle = new PanelRequestOwnerLifecycle(
                WebOverlayForm.IsInventoryOwnerPanel);

            Assert.False(lifecycle.Advance(
                "kshop", "panel.kshop.a", out _, out _));
            Assert.False(lifecycle.Advance(
                "kshop", "panel.kshop.a", out _, out _));

            Assert.True(lifecycle.Advance(
                "kshop", "panel.kshop.b",
                out string retiredPanel,
                out string retiredInstance));
            Assert.Equal("kshop", retiredPanel);
            Assert.Equal("panel.kshop.a", retiredInstance);

            Assert.True(lifecycle.Advance(
                "help", null,
                out retiredPanel,
                out retiredInstance));
            Assert.Equal("kshop", retiredPanel);
            Assert.Equal("panel.kshop.b", retiredInstance);
        }

        [Fact]
        public void AcceptedCloseSealsTheExactOwnerUntilAHostTupleTransition()
        {
            var lifecycle = new PanelRequestOwnerLifecycle(
                WebOverlayForm.IsInventoryOwnerPanel);

            Assert.False(lifecycle.Advance(
                "kshop", "panel.kshop.a", out _, out _));
            Assert.True(lifecycle.IsAdmittedExact(
                "kshop", "panel.kshop.a"));
            Assert.True(lifecycle.SealExact(
                "kshop", "panel.kshop.a"));
            Assert.False(lifecycle.IsAdmittedExact(
                "kshop", "panel.kshop.a"));

            // A redundant observation of the still-closing Host tuple must not
            // reopen writes from the retired Web owner.
            Assert.False(lifecycle.Advance(
                "kshop", "panel.kshop.a", out _, out _));
            Assert.False(lifecycle.IsAdmittedExact(
                "kshop", "panel.kshop.a"));
            Assert.False(lifecycle.SealExact(
                "kshop", "panel.kshop.a"));

            Assert.True(lifecycle.Advance(
                "kshop", "panel.kshop.b",
                out string retiredPanel,
                out string retiredInstance));
            Assert.Equal("kshop", retiredPanel);
            Assert.Equal("panel.kshop.a", retiredInstance);
            Assert.True(lifecycle.IsAdmittedExact(
                "kshop", "panel.kshop.b"));
            Assert.False(lifecycle.IsAdmittedExact(
                "kshop", "panel.kshop.a"));
        }

        [Theory]
        [InlineData("kshop", "kshop")]
        [InlineData("npcshop", "npcshop")]
        [InlineData("crafting", "crafting")]
        [InlineData("workbench", "help")]
        public void HostRebindOrSwitchImmediatelyRetiresHeldInventoryWrite(
            string firstPanel,
            string nextPanel)
        {
            var pumps = new Queue<Action>();
            var sent = new List<JObject>();
            using var task = new InventoryTask(
                () => true,
                payload =>
                {
                    sent.Add(JObject.Parse(payload.TrimEnd('\0')));
                    return true;
                });
            var lifecycle = new PanelRequestOwnerLifecycle(
                WebOverlayForm.IsInventoryOwnerPanel);
            using var host = new PanelHostController(
                pumps.Enqueue,
                fire => fire());
            host.PanelChanged += delegate(string panel, string instance)
            {
                if (lifecycle.Advance(
                        panel,
                        instance,
                        out _,
                        out _))
                {
                    task.ClearPending();
                }
            };

            Assert.True(host.TryOpenPanel(firstPanel, "{}", null, null));
            PumpOne(pumps);
            string firstInstance = host.ActivePanelInstanceId;
            task.HandleWebRequest(
                "move",
                BuildMoveRequest(firstPanel, firstInstance));
            Assert.Equal("write_pending", task.WriteState);
            JObject staleFlashRequest = sent[0];

            Assert.True(host.TryOpenPanel(nextPanel, "{}", null, null));
            PumpOne(pumps);

            Assert.Equal("needs_reconcile", task.WriteState);
            Assert.Equal(nextPanel, host.ActivePanelName);
            if (nextPanel == firstPanel)
                Assert.NotEqual(firstInstance, host.ActivePanelInstanceId);

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = staleFlashRequest.Value<int>("callId"),
                ["success"] = false,
                ["error"] = "stale_state"
            }, _ => { });
            Assert.Equal("needs_reconcile", task.WriteState);
        }

        private static JObject BuildMoveRequest(
            string panel,
            string panelInstanceId)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = panel,
                ["domain"] = "inventory",
                ["cmd"] = "move",
                ["callId"] = "inventory.owner.lifecycle.move",
                ["panelInstanceId"] = panelInstanceId,
                ["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["source"] = new JObject
                    {
                        ["containerId"] = "背包",
                        ["slot"] = 2,
                        ["expectedLease"] = "inventory.owner.source"
                    },
                    ["target"] = new JObject
                    {
                        ["containerId"] = "仓库",
                        ["slot"] = 52,
                        ["expectedLease"] = "inventory.owner.target"
                    }
                }
            };
        }

        private static void PumpOne(Queue<Action> pumps)
        {
            Action pump = Assert.Single(pumps);
            pumps.Clear();
            pump();
        }
    }
}
