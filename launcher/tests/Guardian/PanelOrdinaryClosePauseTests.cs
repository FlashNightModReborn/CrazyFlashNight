using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelOrdinaryClosePauseTests
    {
        public static IEnumerable<object[]> OrdinaryPanels()
        {
            foreach (string panel in new[] {
                "skills", "map-workbench", "asset-workbench", "settings", "warlord",
                "team", "blackmarket", "gym", "map", "meridians", "stage-select",
                "tablet", "garage", "sleep", "bookshelf", "surgery", "subway",
                "egg-stage-select", "dressup", "cutscene-test", "lut-lab", "ragchat",
                "lockbox", "pinalign", "gobang", "arena", "tasks", "jukebox", "help",
                "intelligence" }) yield return new object[] { panel };
        }

        private sealed class Harness : IDisposable
        {
            internal readonly Queue<Action> Queue = new();
            internal readonly List<string> Commands = new();
            internal readonly PanelHostController Host;
            internal readonly WebOverlayForm Overlay;
            private readonly SkillTask _skills;
            private readonly SettingsTask _settings;

            internal Harness()
            {
                Host = new PanelHostController(a => Queue.Enqueue(a), a => a());
                Host.CloseInputHeldForTests = () => false;
                // Run the real message handlers without constructing HWNDs, WebView2,
                // cursor hooks or a player process. Only close-path dependencies exist.
                Overlay = (WebOverlayForm)RuntimeHelpers.GetUninitializedObject(typeof(WebOverlayForm));
                GC.SuppressFinalize(Overlay);
                SetField(Overlay, "_panelHost", Host);
                SetField(Overlay, "_webReady", true);
                SetField(Overlay, "_panelMode", true);
                Overlay.GameCommandSenderForTests = command => { Commands.Add(command); return true; };
                Host.ReleaseClosePauseForTests = () => Assert.True(Overlay.ReleaseClosePause());
                _skills = new SkillTask(() => false, _ => false);
                _settings = new SettingsTask(() => false, _ => false, null, () => false);
                SetField(Overlay, "_skillTask", _skills);
                SetField(Overlay, "_settingsTask", _settings);
            }

            internal string Open(string panel)
            {
                Host.OpenPanel(panel, "{}");
                Pump();
                return Host.ActivePanelInstanceId;
            }

            internal void Close(string panel, string instance)
            {
                var message = new JObject { ["type"] = "panel", ["panel"] = panel,
                    ["cmd"] = "close", ["panelInstanceId"] = instance };
                string method = "HandlePanelMessage";
                if (panel == "map-workbench" || panel == "asset-workbench")
                {
                    message["domain"] = panel == "map-workbench" ? "map_workbench" : "asset_workbench";
                    message["callId"] = "ordinary.close.test";
                    message["payload"] = new JObject();
                    method = panel == "map-workbench" ? "HandleMapWorkbenchMessage" : "HandleAssetWorkbenchMessage";
                }
                MethodInfo handler = typeof(WebOverlayForm).GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic);
                object[] arguments = method == "HandlePanelMessage"
                    ? new object[] { message.ToString() }
                    : new object[] { message.ToString(), "https://overlay.local/overlay.html" };
                handler.Invoke(Overlay, arguments);
            }

            internal void Pump()
            {
                int remaining = 100;
                while (Queue.Count > 0) { Assert.True(remaining-- > 0); Queue.Dequeue()(); }
            }

            private static void SetField(object target, string name, object value)
            {
                target.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic).SetValue(target, value);
            }

            public void Dispose()
            {
                Host.Dispose();
                _skills.Dispose();
                _settings.Dispose();
                // The uninitialized Form never owned native resources; do not run its
                // normal UI teardown against this intentionally incomplete test object.
            }
        }

        [Theory]
        [MemberData(nameof(OrdinaryPanels))]
        public void OrdinaryCloseReleasesGenericPauseExactlyOnce(string panel)
        {
            using var h = new Harness();
            string instance = h.Open(panel);
            h.Close(panel, instance);
            Assert.DoesNotContain("webPanelUnpause", h.Commands);
            h.Pump();
            Assert.False(h.Host.IsPanelOpen);
            Assert.Equal("Closed", h.Host.LastCloseOutcome.Outcome);
            Assert.Equal(1, h.Commands.Count(c => c == "webPanelUnpause"));
        }

        [Theory]
        [InlineData("skills")]
        [InlineData("map-workbench")]
        [InlineData("asset-workbench")]
        public void RepeatedOrdinaryCloseDoesNotLeaveOrDoubleReleasePause(string panel)
        {
            using var h = new Harness();
            for (int i = 1; i <= 3; i++)
            {
                string instance = h.Open(panel);
                h.Close(panel, instance);
                h.Close(panel, instance);
                h.Pump();
                Assert.False(h.Host.IsPanelOpen);
                Assert.Equal(i, h.Commands.Count(c => c == "webPanelUnpause"));
            }
        }

        [Theory]
        [InlineData("skills")]
        [InlineData("map-workbench")]
        [InlineData("asset-workbench")]
        public void ForeignCloseCannotReleaseCurrentPanelPause(string panel)
        {
            using var h = new Harness();
            string instance = h.Open(panel);
            h.Close(panel, "foreign.instance");
            h.Pump();
            Assert.Equal(instance, h.Host.ActivePanelInstanceId);
            Assert.DoesNotContain("webPanelUnpause", h.Commands);
        }

        [Theory]
        [InlineData("skills")]
        [InlineData("map-workbench")]
        [InlineData("asset-workbench")]
        public void SupersededCloseCannotReleaseReplacementPause(string panel)
        {
            using var h = new Harness();
            string instance = h.Open(panel);
            h.Close(panel, instance);
            h.Host.OpenPanel("map", "{}");
            h.Pump();
            Assert.Equal("map", h.Host.ActivePanelName);
            Assert.DoesNotContain("webPanelUnpause", h.Commands);
        }
    }
}
