using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using CF7Launcher.Audio;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Save;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class GameLaunchFlowFrontdoorBgmTests
    {
        [Fact]
        public void AcceptedBootstrapLoadKeepsBgmWhileOpAndLegacyYield()
        {
            using (var load = new Harness())
            {
                load.PreparePrewarm("attempt-load");
                load.Flow.StartGameFromBootstrap(
                    "slot-load",
                    false,
                    true);

                Assert.Empty(load.Lease.Yields);
            }

            using (var op = new Harness())
            {
                op.PreparePrewarm("attempt-op");
                op.Flow.StartGameFromBootstrap(
                    "slot-op",
                    true,
                    true);

                Assert.Single(op.Lease.Yields);
                Assert.Contains("launch_accepted:load", op.Lease.Yields[0]);
            }

            using (var create = new Harness())
            {
                create.PreparePrewarm("attempt-create");
                InvokePrivate(
                    create.Flow,
                    "StartGameInternal",
                    "slot-create",
                    false,
                    true,
                    SolResolveResult.NewEmpty(),
                    true,
                    "create",
                    null);

                Assert.Empty(create.Lease.Yields);
            }

            using (var legacy = new Harness())
            {
                legacy.PreparePrewarm("attempt-legacy");
                legacy.Flow.StartGame("slot-legacy", false, false);

                Assert.Single(legacy.Lease.Yields);
                Assert.Contains(
                    "launch_accepted:legacy",
                    legacy.Lease.Yields[0]);
            }
        }

        [Fact]
        public void CharacterSubmitKeepsBgmUntilExactGameplayReveal()
        {
            using (var harness = new Harness(true))
            {
                const string openRequestId = "open-frontdoor-bgm-test";
                const string attemptId = "attempt-create-submit";
                const string slotKey = "slot-create-submit";
                harness.PrepareCharacterSubmit(
                    openRequestId,
                    attemptId,
                    slotKey);

                string error;
                Assert.True(
                    harness.Flow.SubmitCharacterCreate(
                        openRequestId,
                        attemptId,
                        slotKey,
                        false,
                        null,
                        BuildCharacterDraft(),
                        out error),
                    error);
                Assert.Empty(harness.Lease.Yields);

                InvokePrivate(harness.Flow, "DoPerformReveal");

                Assert.Single(harness.Lease.Yields);
                Assert.Equal(
                    "gameplay_reveal",
                    harness.Lease.Yields[0]);
            }
        }

        [Fact]
        public void ResetRestoresThroughSceneReadyButNotAfterActualReveal()
        {
            using (var visible = new Harness())
            {
                visible.Flow.Reset(null, "frontdoor_cancel");
                Assert.Single(visible.Lease.Enters);
            }

            using (var sceneReady = new Harness())
            {
                sceneReady.PrepareSceneWait("attempt-scene");
                sceneReady.Flow.ObserveUiData(
                    new UiDataPacket("s:1|ga:attempt-scene"));

                SetPrivateField(
                    sceneReady.Flow,
                    "_state",
                    GameLaunchFlow.State.Idle);
                sceneReady.Flow.Reset(null, "after_scene_ready");

                Assert.Single(sceneReady.Lease.Enters);
            }

            using (var revealed = new Harness())
            {
                SetPrivateField(revealed.Flow, "_revealPerformed", true);
                revealed.Flow.Reset(null, "after_reveal");

                Assert.Empty(revealed.Lease.Enters);
            }
        }

        [Fact]
        public void ErrorRestoresBeforeHandoffButNeverStealsBackAfterHandoff()
        {
            using (var beforeHandoff = new Harness())
            {
                beforeHandoff.PrepareError("attempt-error-before", false);
                InvokePrivate(
                    beforeHandoff.Flow,
                    "TransitionToError",
                    "forced_frontdoor_error");

                Assert.Single(beforeHandoff.Lease.Enters);
            }

            using (var sceneReadyPreReveal = new Harness())
            {
                sceneReadyPreReveal.PrepareSceneWait(
                    "attempt-scene-error");
                sceneReadyPreReveal.Flow.ObserveUiData(
                    new UiDataPacket(
                        "s:1|ga:attempt-scene-error"));
                InvokePrivate(
                    sceneReadyPreReveal.Flow,
                    "TransitionToError",
                    "forced_after_scene_before_reveal");

                Assert.Single(sceneReadyPreReveal.Lease.Enters);
            }

            using (var afterHandoff = new Harness())
            {
                afterHandoff.PrepareError("attempt-error-after", true);
                InvokePrivate(
                    afterHandoff.Flow,
                    "TransitionToError",
                    "forced_post_scene_error");

                Assert.Empty(afterHandoff.Lease.Enters);
            }
        }

        private static object InvokePrivate(
            GameLaunchFlow flow,
            string name,
            params object[] arguments)
        {
            MethodInfo method = typeof(GameLaunchFlow).GetMethod(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(method);
            return method.Invoke(flow, arguments);
        }

        private static JObject BuildCharacterDraft()
        {
            return new JObject
            {
                ["characterName"] = "新角色",
                ["gender"] = "male",
                ["height"] = 175,
                ["faceIdentifier"] = "face_a",
                ["hairIdentifier"] = "hair_a",
                ["upperIdentifier"] = "upper_a",
                ["lowerIdentifier"] = "lower_a",
                ["footwearIdentifier"] = "foot_a",
                ["difficulty"] = "normal"
            };
        }

        private static T GetPrivateField<T>(
            GameLaunchFlow flow,
            string name)
        {
            FieldInfo field = typeof(GameLaunchFlow).GetField(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            return (T)field.GetValue(flow);
        }

        private static void SetPrivateField<T>(
            GameLaunchFlow flow,
            string name,
            T value)
        {
            FieldInfo field = typeof(GameLaunchFlow).GetField(
                name,
                BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            field.SetValue(flow, value);
        }

        private sealed class FakeLease : IFrontdoorBgmLease
        {
            internal List<string> Enters { get; } = new List<string>();
            internal List<string> Yields { get; } = new List<string>();

            public void EnterFrontdoor(string reason)
            {
                Enters.Add(reason);
            }

            public void YieldToGameplay(string reason)
            {
                Yields.Add(reason);
            }
        }

        private sealed class Harness : IDisposable
        {
            private readonly string _root;

            internal Harness(bool withSaveContext = false)
            {
                SaveResolutionContext saveContext = null;
                if (withSaveContext)
                {
                    _root = Path.Combine(
                        Path.GetTempPath(),
                        "cf7-frontdoor-bgm-flow-" +
                        Guid.NewGuid().ToString("N"));
                    Directory.CreateDirectory(_root);
                    saveContext = new SaveResolutionContext(
                        null,
                        null,
                        new ArchiveTask(_root),
                        null,
                        _root);
                }
                Router = new MessageRouter();
                Server = new XmlSocketServer(
                    Router,
                    AllowLoopbackXmlSocketPeerAuthority.Instance);
                ProcessManager = new ProcessManager(
                    "unused-flash.exe",
                    "unused.swf");
                Lease = new FakeLease();
                Flow = new GameLaunchFlow(
                    Server,
                    Router,
                    ProcessManager,
                    new WindowManager(),
                    null,
                    null,
                    null,
                    null,
                    saveContext,
                    60000,
                    null,
                    Lease);
                Flow.CharacterCreateWebPostForTests = delegate { };
                Flow.CharacterCreateAs2PushForTests = delegate { };
            }

            internal MessageRouter Router { get; }
            internal XmlSocketServer Server { get; }
            internal ProcessManager ProcessManager { get; }
            internal FakeLease Lease { get; }
            internal GameLaunchFlow Flow { get; }

            internal void PreparePrewarm(string attemptId)
            {
                SetPrivateField(
                    Flow,
                    "_state",
                    GameLaunchFlow.State.WaitingConnect);
                SetPrivateField(Flow, "_currentAttemptId", attemptId);
                SetPrivateField<string>(Flow, "_pendingSlot", null);
            }

            internal void PrepareSceneWait(string attemptId)
            {
                SetPrivateField(
                    Flow,
                    "_state",
                    GameLaunchFlow.State.Ready);
                SetPrivateField(Flow, "_currentAttemptId", attemptId);
                SetPrivateField(Flow, "_pendingSlot", "slot-scene");
                SetPrivateField(Flow, "_frontdoorMode", "load");
                SetPrivateField(Flow, "_revealWaitingScene", true);
                SetPrivateField(Flow, "_revealWaitingJs", true);
                SetPrivateField(Flow, "_revealWaitingFlash", false);
                SetPrivateField(Flow, "_revealPerformed", false);
            }

            internal void PrepareCharacterSubmit(
                string openRequestId,
                string attemptId,
                string slotKey)
            {
                Type contextType = typeof(GameLaunchFlow).GetNestedType(
                    "CharacterCreateOpenContext",
                    BindingFlags.NonPublic);
                Assert.NotNull(contextType);
                object context = Activator.CreateInstance(
                    contextType,
                    true);
                FieldInfo mode = contextType.GetField(
                    "Mode",
                    BindingFlags.Instance | BindingFlags.NonPublic);
                FieldInfo request = contextType.GetField(
                    "OpenRequestId",
                    BindingFlags.Instance | BindingFlags.NonPublic);
                Assert.NotNull(mode);
                Assert.NotNull(request);
                mode.SetValue(context, "new");
                request.SetValue(context, openRequestId);

                SetPrivateField(Flow, "_state", GameLaunchFlow.State.Ready);
                SetPrivateField(Flow, "_frontdoorMode", "create");
                SetPrivateField(Flow, "_currentAttemptId", attemptId);
                SetPrivateField(Flow, "_pendingSlot", slotKey);
                SetPrivateField(
                    Flow,
                    "_characterCreateContext",
                    context);
                SetPrivateField(
                    Flow,
                    "_characterCreateSnapshotReceived",
                    true);
            }

            internal void PrepareError(
                string attemptId,
                bool authorityReached)
            {
                SetPrivateField(
                    Flow,
                    "_state",
                    GameLaunchFlow.State.WaitingGameReady);
                SetPrivateField(Flow, "_currentAttemptId", attemptId);
                SetPrivateField(Flow, "_pendingSlot", "slot-error");
                SetPrivateField(Flow, "_revealPerformed", authorityReached);
            }

            public void Dispose()
            {
                System.Threading.Timer definitive = GetPrivateField<
                    System.Threading.Timer>(
                    Flow,
                    "_characterCreateDefinitiveTimer");
                if (definitive != null) definitive.Dispose();
                ProcessManager.Dispose();
                Server.Dispose();
                if (!string.IsNullOrEmpty(_root))
                {
                    try { Directory.Delete(_root, true); }
                    catch { }
                }
            }
        }
    }
}
