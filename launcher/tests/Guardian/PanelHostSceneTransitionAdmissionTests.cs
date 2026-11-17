using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class PanelHostSceneTransitionAdmissionTests
{
    private sealed class Rig : IDisposable
    {
        internal readonly Form Owner = new();
        internal readonly Queue<Action> Pumps = new();
        internal readonly List<string> Rejected = new();
        internal readonly SceneTransitionController Transition;
        internal readonly PanelHostController Host;
        internal int Opens;
        internal bool Presented = true;

        internal Rig()
        {
            string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
            Transition = new SceneTransitionController(Owner, Owner, root, a => a(), _ => true,
                () => false, _ => Presented, _ => false, Array.Empty<OverlayBase>(), _ => { });
            Set(Transition, "_preparing", true); // Queue/admission fixture; does not start WebView2.
            Host = new PanelHostController(a => Pumps.Enqueue(a), a => a());
            Host.ConfigureTransitionSettlement(Transition);
            Transition.ConfigureSettlement(_ => true, _ => true);
            Host.SetInitDataEnricher((_, json, _) => { Opens++; return json; });
            Host.PanelOpenRejected += (name, reason) => Rejected.Add(name + ":" + reason);
        }

        internal void Pump() { while (Pumps.Count != 0) Pumps.Dequeue()(); }
        internal void Open(string name, string json = "{}")
        {
            Assert.True(Host.TryOpenPanel(name, json, null, null));
            Pump();
        }
        internal void Project(string phase, int revision = 1, string id = "tr:1")
        {
            Transition.Task.Handle(new JObject { ["payload"] = new JObject {
                ["version"] = 1, ["requestId"] = id, ["revision"] = revision,
                ["phase"] = phase, ["imageId"] = "Andy", ["tip"] = "",
                ["targetScene"] = 2, ["actionPending"] = false
            } });
        }
        public void Dispose() { Host.Dispose(); Transition.Dispose(); Owner.Dispose(); }
    }

    private static void Set(object target, string name, object value) => target.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic).SetValue(target, value);
    private static object Get(object target, string name) => target.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic).GetValue(target);
    private static object Call(object target, string name, params object[] args) => target.GetType()
        .GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(target, args);

    [Fact]
    public void HelpCannotPauseTheWorldBeforeItsFreshRevealFrame()
    {
        using var r = new Rig();
        r.Project("reveal");
        r.Open("help");
        Assert.Null(r.Host.ActivePanelName);
        Assert.Equal(0, r.Opens);
        Assert.False(r.Host.GameOwnsInput);
        r.Project("hide", 2);
        r.Pump();
        Assert.Equal("help", r.Host.ActivePanelName);
        Assert.Equal(1, r.Opens);
        r.Project("hide", 2);
        r.Pump();
        Assert.Equal(1, r.Opens);
    }

    [Fact]
    public void WebRevealReceiptAloneCannotPauseTheAs2FadeTail()
    {
        using var r = new Rig();
        r.Project("reveal");
        Set(r.Transition, "_revealed", true);
        Assert.False(r.Transition.OwnsCurtain);
        r.Open("workbench");
        Assert.Null(r.Host.ActivePanelName);
        Assert.Equal(0, r.Opens);
        r.Project("hide", 2);
        r.Pump();
        Assert.Equal("workbench", r.Host.ActivePanelName);
        Assert.Equal(1, r.Opens);
    }

    [Fact]
    public void OnlyLastDeferredIntentOpensWithoutClosingTheExistingSource()
    {
        using var r = new Rig();
        r.Open("arena");
        string source = r.Host.ActivePanelInstanceId;
        r.Project("cover");
        r.Open("help");
        r.Open("workbench");
        Assert.Equal("arena", r.Host.ActivePanelName);
        Assert.Equal(source, r.Host.ActivePanelInstanceId);
        Assert.Contains("help:superseded_before_open", r.Rejected);
        Assert.Equal(1, r.Opens);
        r.Project("hide", 2);
        r.Pump();
        Assert.Equal("workbench", r.Host.ActivePanelName);
        Assert.Equal(2, r.Opens);
    }

    [Fact]
    public void OldTimelineHideCannotReleaseAnOpenWaitingForANewCurtain()
    {
        using var r = new Rig();
        r.Project("cover");
        r.Open("help");
        r.Project("cover", id: "tr:2");
        r.Project("hide", 2);
        r.Pump();
        Assert.Null(r.Host.ActivePanelName);
        r.Project("hide", 2, "tr:2");
        r.Pump();
        Assert.Equal("help", r.Host.ActivePanelName);
        Assert.Equal(1, r.Opens);
    }

    [Fact]
    public void TrackedOpenRejectsBeforePostingOrEnrichingAndNeverReplays()
    {
        using var r = new Rig();
        r.Project("loading");
        PanelHostController.TrackedOpenOutcome? outcome = null;
        Assert.True(r.Host.TryOpenTrackedPanel("help", "{}", "help.pending", () => true, x => outcome = x));
        r.Pump();
        Assert.Equal(PanelHostController.TrackedOpenOutcome.PreExecutionRejected, outcome);
        Assert.Null(r.Host.ActivePanelName);
        Assert.Equal(0, r.Opens);
        r.Project("hide", 2);
        r.Pump();
        Assert.Equal(0, r.Opens);
    }

    [Fact]
    public void ExactReplaceCannotCommitCapabilitiesUnderTheCurtain()
    {
        using var r = new Rig();
        r.Open("crafting");
        string source = r.Host.ActivePanelInstanceId;
        r.Project("cover");
        int commits = 0, aborts = 0;
        var plan = new PreparedPanelReplace("npcshop", "shop.new", "{}", () => commits++, () => aborts++);
        PanelHostController.ExactReplaceOutcome? outcome = null;
        Assert.True(r.Host.TryReplacePanelExact("crafting", source, plan, () => true, x => outcome = x));
        r.Pump();
        Assert.Equal(PanelHostController.ExactReplaceOutcome.PreExecutionRejected, outcome);
        Assert.Equal(0, commits);
        Assert.Equal(1, aborts);
        Assert.Equal(source, r.Host.ActivePanelInstanceId);
        r.Project("hide", 2);
        r.Pump();
        Assert.Equal(0, commits);
    }

    [Fact]
    public void CompletingTheTimelineStillRespectsOtherAuthorityBarriers()
    {
        using var r = new Rig();
        bool allowed = false;
        r.Host.SetOpenGate(_ => allowed);
        r.Project("cover");
        r.Open("help");
        r.Project("hide", 2);
        r.Pump();
        Assert.Null(r.Host.ActivePanelName);
        allowed = true;
        r.Host.FlushDeferredBarrierOpen();
        r.Pump();
        Assert.Equal("help", r.Host.ActivePanelName);
        Assert.Equal(1, r.Opens);
    }

    [Fact]
    public void DiscardedIntentDoesNotReturnWhenTheTimelineEnds()
    {
        using var r = new Rig();
        r.Project("cover");
        r.Open("help");
        Assert.True(r.Host.DiscardDeferredBarrierOpen());
        r.Project("hide", 2);
        r.Pump();
        Assert.Null(r.Host.ActivePanelName);
        Assert.Equal(0, r.Opens);
    }

    [Theory]
    [InlineData("loot")]
    [InlineData("book-comic")]
    public void APanelNameAloneCannotBorrowTransitionOwnedPresentation(string panel)
    {
        using var r = new Rig();
        r.Project("reveal");
        r.Open(panel);
        Assert.Null(r.Host.ActivePanelName);
        Assert.Equal(0, r.Opens);
        Assert.Empty(r.Rejected);
    }

    [Fact]
    public void OnlyTheExactParallelSettlementKeepsItsExistingEarlyAdmission()
    {
        using var r = new Rig();
        var report = new JObject {
            ["v"] = 1, ["runId"] = "run.1", ["stageName"] = "并行返回", ["difficulty"] = "简单",
            ["outcome"] = "victory", ["activeFrames"] = 900, ["totalKills"] = 0,
            ["omittedKillTypes"] = 0, ["totalItemGains"] = 0, ["totalItemLosses"] = 0,
            ["omittedItemFlowTypes"] = 0, ["rewardRollOmissions"] = 0,
            ["kills"] = new JArray(), ["itemFlows"] = new JArray(), ["rewardStashed"] = true
        };
        r.Transition.Task.Handle(new JObject { ["payload"] = new JObject {
            ["version"] = 2, ["requestId"] = "tr:1", ["revision"] = 1, ["phase"] = "loading",
            ["imageId"] = "Andy", ["tip"] = "", ["targetScene"] = 2, ["actionPending"] = false,
            ["report"] = report, ["reportVisible"] = true, ["reportHandoff"] = true
        } });
        Set(r.Transition.SettlementSurface, "_ready", true); // Endpoint availability only; no Web pixels claimed.
        var data = new JObject { ["sourceKind"] = "stage_settlement", ["report"] = report.DeepClone() };
        Assert.False((bool)Call(r.Host, "SceneTransitionBlocksOpen", "loot", data.ToString()));
        r.Open("loot", data.ToString());
        Assert.Equal("loot", r.Host.ActivePanelName);
        Assert.Equal(1, r.Opens);
        data["report"]["runId"] = "run.foreign";
        Assert.True((bool)Call(r.Host, "SceneTransitionBlocksOpen", "loot", data.ToString()));
        Assert.True((bool)Call(r.Host, "SceneTransitionBlocksOpen", "help", "{}"));
    }

    [Fact]
    public void OnlyTheCurrentIntroComicCanBorrowItsTransition()
    {
        using var r = new Rig();
        r.Transition.Task.Handle(new JObject { ["payload"] = new JObject {
            ["version"] = 3, ["requestId"] = "tr:1", ["revision"] = 3, ["phase"] = "reveal",
            ["imageId"] = "Andy", ["tip"] = "", ["targetScene"] = 2, ["actionPending"] = false,
            ["introId"] = "intro:1", ["introState"] = "loading"
        } });
        Set(Get(r.Transition, "_intro"), "TimelineRetired", true);
        var data = new JObject {
            ["v"] = 2, ["presentationId"] = "bookcomic:1", ["slot"] = "bookrun_fixture",
            ["sceneId"] = "scene:2", ["pageId"] = "prologue", ["introId"] = "intro:1"
        };
        Assert.False((bool)Call(r.Host, "SceneTransitionBlocksOpen", "book-comic", data.ToString()));
        data["introId"] = "intro:2";
        Assert.True((bool)Call(r.Host, "SceneTransitionBlocksOpen", "book-comic", data.ToString()));
        Assert.True((bool)Call(r.Host, "SceneTransitionBlocksOpen", "book-comic", "{broken"));
    }

    [Fact]
    public void RetiredIntroKeepsTheExistingSuccessorPanelAdmission()
    {
        using var r = new Rig();
        r.Transition.Task.Handle(new JObject { ["payload"] = new JObject {
            ["version"] = 3, ["requestId"] = "tr:1", ["revision"] = 3, ["phase"] = "intro",
            ["imageId"] = "Andy", ["tip"] = "", ["targetScene"] = 2, ["actionPending"] = false,
            ["introId"] = "intro:1", ["introState"] = "narrative"
        } });
        r.Open("intelligence");
        Assert.Equal("intelligence", r.Host.ActivePanelName);
        Assert.Equal(1, r.Opens);
    }

    [Fact]
    public void IntroTimelineRetirementReleasesThePreviouslyDeferredIntent()
    {
        using var r = new Rig();
        r.Project("cover");
        r.Open("help");
        Assert.Null(r.Host.ActivePanelName);
        r.Transition.Task.Handle(new JObject { ["payload"] = new JObject {
            ["version"] = 3, ["requestId"] = "tr:1", ["revision"] = 2, ["phase"] = "intro",
            ["imageId"] = "Andy", ["tip"] = "", ["targetScene"] = 2, ["actionPending"] = false,
            ["introId"] = "intro:1", ["introState"] = "opening"
        } });
        r.Pump();
        Assert.Equal("help", r.Host.ActivePanelName);
        Assert.Equal(1, r.Opens);
    }

    [Fact]
    public void ClosedSettlementStillWaitsForItsFreshResumeFrame()
    {
        using var r = new Rig();
        Set(r.Transition, "_retainedScene", 2L);
        Set(r.Transition.SettlementSurface, "_panelInstance", "loot.resume");
        r.Presented = false;
        r.Transition.ReleaseSettlement("{\"type\":\"panel_cmd\",\"cmd\":\"close\"}");
        r.Open("help");
        Call(r.Transition, "Tick");
        r.Pump();
        Assert.Null(r.Host.ActivePanelName);
        r.Presented = true;
        Call(r.Transition, "Tick");
        r.Pump();
        Assert.Equal("help", r.Host.ActivePanelName);
        Assert.Equal(1, r.Opens);
    }

    [Fact]
    public void DisposalCannotReopenADeferredPanel()
    {
        using var r = new Rig();
        r.Project("cover");
        r.Open("help");
        r.Host.Dispose();
        r.Project("hide", 2);
        r.Pump();
        Assert.Null(r.Host.ActivePanelName);
        Assert.Equal(0, r.Opens);
    }
}
