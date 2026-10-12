using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.ArenaWorker;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public class WorkerProjectionTests
{
    private static JObject Configuration(bool none = true)
    {
        string root = Path.Combine(Path.GetTempPath(), "cf7-projection-test-" + Guid.NewGuid().ToString("N"));
        var consumers = new JObject();
        foreach (string name in WorkerProjectionPolicy.ConsumerNames)
            consumers[name] = none && name != "sceneLighting" && name != "equipmentLighting" ? "none" : "full";
        return new JObject { ["schema"] = "arena-worker.launch.v2", ["workerId"] = "w01", ["sessionEpoch"] = "s01",
            ["projectRoot"] = root, ["stateRoot"] = Path.Combine(root, "tmp", "arena-worker", "s01"),
            ["saveRoot"] = Path.Combine(root, "saves"), ["outputRoot"] = Path.Combine(root, "tmp", "arena-calibration"),
            ["swfOrigin"] = Path.Combine(root, "CRAZYFLASHER7MercenaryEmpire.swf"), ["slot"] = "cf7_agent_fixture",
            ["presentationPolicy"] = "full", ["projectionConsumers"] = consumers, ["controlFrameFormat"] = "f-visual-v1",
            ["visualSeedRevision"] = WorkerProjectionPolicy.VisualRevision,
            ["simulationRngConsumptionRevision"] = WorkerProjectionPolicy.SimulationRevision, ["sessionVisualSeed"] = 42 };
    }
    private static JObject Bindings()
    {
        var result = new JObject();
        foreach (string name in WorkerProjectionPolicy.CatalogNames) result[name] = "sha256:" + new string('a', 64);
        return result;
    }
    [Fact]
    public void ExistingUppercaseCatalogDigestsAreNormalizedAtTheNewContractBoundary()
    {
        string raw = new string('A', 64);
        JObject bindings = WorkerProjectionPolicy.BindCatalogs(raw, raw, "sha256:" + raw, raw);
        Assert.All(bindings.Properties(), p => Assert.Equal("sha256:" + new string('a', 64), (string)p.Value));
        Assert.Throws<InvalidOperationException>(() => WorkerProjectionPolicy.BindCatalogs(null, raw, raw, raw));
        Assert.Throws<InvalidOperationException>(() => WorkerProjectionPolicy.BindCatalogs(new string('G', 64), raw, raw, raw));
    }
    private sealed class Fixture : IDisposable
    {
        internal List<string> Faults = new();
        internal List<JObject> Offers = new();
        internal DateTime Now = new(2026, 10, 11, 0, 0, 0, DateTimeKind.Utc);
        internal WorkerProjectionNegotiator Projection;
        internal bool Clean;
        internal bool StartupReady;
        internal Fixture(bool none = true, bool send = true, bool clean = true, bool startupReady = true)
        {
            Clean = clean;
            StartupReady = startupReady;
            JObject config = Configuration(none);
            var policy = ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]);
            Projection = new WorkerProjectionNegotiator(policy, Bindings(), (wire, generation) => {
                Offers.Add(JObject.Parse(wire.TrimEnd('\0'))); return send;
            }, (reason, generation) => Faults.Add(reason), () => Now, startTimer: false, clean: () => Clean,
                startupReady: () => StartupReady);
            Projection.Ready(7);
        }
        internal JObject Prepared()
        {
            var result = (JObject)Offers[0].DeepClone(); result["task"] = "worker_projection_prepared";
            result["accepted"] = true; result["clean"] = true; return result;
        }
        internal JObject Install()
        {
            var commit = JObject.Parse(Projection.Prepared(Prepared(), 7));
            commit["task"] = "worker_projection_committed"; commit["installClockKind"] = "flashRootEnterFrame";
            commit["installEpoch"] = 1; commit["installTick"] = 2;
            Projection.Committed(commit, 7); return commit;
        }
        public void Dispose() => Projection.Dispose();
    }
    [Fact]
    public void NoneRequiresExactActualInstallationAndRetainsLights()
    {
        using var f = new Fixture();
        Assert.False(f.Projection.IsReady); Assert.False(f.Projection.IsNone("ray", 7));
        JObject receipt = f.Install();
        Assert.True(f.Projection.IsReady); Assert.True(f.Projection.IsNone("ray", 7));
        Assert.False(f.Projection.IsNone("sceneLighting", 7)); Assert.False(f.Projection.IsNone("equipmentLighting", 7));
        Assert.False(f.Projection.IsNone("ray", 6)); Assert.Empty(f.Faults);
        Assert.True(JToken.DeepEquals(receipt, f.Projection.Status()["installReceipt"]));
    }
    [Fact]
    public void DuplicateMessagesAreIdempotentButChangedReceiptFailsClosed()
    {
        using var f = new Fixture();
        string first = f.Projection.Prepared(f.Prepared(), 7);
        for (int i = 0; i < 100; i++) Assert.Equal(first, f.Projection.Prepared(f.Prepared(), 7));
        JObject receipt = f.Install(); f.Projection.Committed(receipt, 7);
        Assert.True(f.Projection.IsReady); receipt["installTick"] = 3;
        f.Projection.Committed(receipt, 7);
        Assert.False(f.Projection.IsReady); Assert.Single(f.Faults);
    }
    [Theory]
    [InlineData("clean")]
    [InlineData("catalog")]
    [InlineData("consumer")]
    [InlineData("extra")]
    [InlineData("version_float")]
    public void PreparedMustDescribeInstalledMatchingCapabilities(string malformed)
    {
        using var f = new Fixture(); JObject message = f.Prepared();
        switch (malformed)
        {
            case "clean": message["clean"] = false; break;
            case "catalog": message["catalogBindings"]["rayStyles"] = "sha256:" + new string('b', 64); break;
            case "consumer": message["projectionConsumers"]["ray"] = "full"; break;
            case "extra": message["fakePresented"] = true; break;
            case "version_float": message["version"] = 1.0; break;
        }
        Assert.Null(f.Projection.Prepared(message, 7)); Assert.False(f.Projection.IsReady); Assert.Single(f.Faults);
    }
    [Fact]
    public void StaleConnectionAndWrongContractCannotMutateCurrentPolicy()
    {
        using var f = new Fixture(); JObject message = f.Prepared();
        Assert.Null(f.Projection.Prepared(message, 6)); message["contractId"] = new string('b', 32);
        Assert.Null(f.Projection.Prepared(message, 7)); Assert.Empty(f.Faults);
        JObject wrongShape = f.Prepared(); wrongShape["workerId"] = new JObject { ["spoof"] = "w01" };
        Assert.Null(f.Projection.Prepared(wrongShape, 7)); Assert.Empty(f.Faults);
        f.Install(); f.Projection.Disconnected(6); Assert.True(f.Projection.IsReady);
        f.Projection.Disconnected(7); Assert.False(f.Projection.IsReady);
        f.Projection.Ready(8); Assert.Single(f.Offers); // unknown old installation needs a new process
    }
    [Fact]
    public void LostCommittedAckAndFailedOfferCannotBecomeSilentNone()
    {
        using var f = new Fixture(); Assert.NotNull(f.Projection.Prepared(f.Prepared(), 7));
        f.Now = f.Now.AddSeconds(10); f.Projection.CheckTimeout();
        Assert.False(f.Projection.IsReady); Assert.Equal("worker_projection_timeout", Assert.Single(f.Faults));
        f.Projection.CheckTimeout(); Assert.Single(f.Faults);
        using var send = new Fixture(send: false);
        Assert.Equal("worker_projection_offer_send_failed", Assert.Single(send.Faults));
    }
    [Fact]
    public void LoaderTimeDoesNotConsumeTheOfferDeadlineAndCannotBeUnlimited()
    {
        using var f = new Fixture(startupReady:false);
        Assert.Empty(f.Offers);f.Now=f.Now.AddSeconds(15);f.Projection.CheckTimeout();
        Assert.Empty(f.Offers);Assert.Empty(f.Faults);
        f.StartupReady=true;f.Projection.CheckTimeout();Assert.Single(f.Offers);
        f.Now=f.Now.AddSeconds(9);f.Install();Assert.True(f.Projection.IsReady);
        using var blocked = new Fixture(startupReady:false);
        blocked.Now=blocked.Now.AddSeconds(120);blocked.Projection.CheckTimeout();
        Assert.Equal("worker_projection_timeout",Assert.Single(blocked.Faults));
    }
    [Fact]
    public void CatalogReadinessAfterTheLoaderDeadlineCannotReopenItsWindow()
    {
        using var f = new Fixture(startupReady:false);
        f.Now=f.Now.AddSeconds(120);f.StartupReady=true;f.Projection.CheckTimeout();
        Assert.Empty(f.Offers);Assert.False(f.Projection.IsReady);
        Assert.Equal("worker_projection_timeout",Assert.Single(f.Faults));
    }
    [Fact]
    public void PreparedCannotInstallTheStatusContractBeforeAnOfferWasSent()
    {
        using var f = new Fixture(startupReady:false);
        JObject status=f.Projection.Status();
        JObject prepared=(JObject)status["policy"].DeepClone();
        prepared["task"]="worker_projection_prepared";prepared["version"]=1;
        prepared["workerId"]="w01";prepared["sessionEpoch"]="s01";
        prepared["connectionGeneration"]=status["connectionGeneration"];
        prepared["contractId"]=status["contractId"];prepared["sequence"]=1;
        prepared["accepted"]=true;prepared["clean"]=true;
        Assert.Null(f.Projection.Prepared(prepared,7));Assert.False(f.Projection.IsReady);
        Assert.Equal("worker_projection_prepared_out_of_phase",Assert.Single(f.Faults));
    }
    [Fact]
    public void ForbiddenSourceProjectionFailsBeforeItsInnerParserRuns()
    {
        using var f = new Fixture(); f.Install();
        var frame = new FrameTask(null, null); frame.SetWorkerProjection(f.Projection);
        int visualFrames = 0; frame.VisualFrameStarted = () => visualFrames++;
        frame.HandleRaw("bad-camera", "", "", "", connectionGeneration: 7, rayVisualPayload: "deliberately not a ray packet");
        Assert.Equal(0, visualFrames); Assert.Equal("unexpected_projection_after_none:ray", Assert.Single(f.Faults));
    }
    [Fact]
    public void F6RetainsClockAndEquipmentRowsButRejectsDecorationBeforeDtoParsing()
    {
        using var f = new Fixture(); f.Install();
        Assert.False(f.Projection.ObserveCombatDecorations("1|2|3|0;l,1,1,0,0,1,0,100,20,1,1,1,1", 7));
        Assert.Empty(f.Faults);
        Assert.True(f.Projection.ObserveCombatDecorations("1|2|3|0;s,intentionally malformed", 7));
        Assert.Equal("unexpected_projection_after_none:combatDecoration", Assert.Single(f.Faults));
    }
    [Fact]
    public void HostCannotAdmitPreparedWhileOldNativeProjectionIsStillLive()
    {
        using var f = new Fixture(clean:false);
        Assert.Null(f.Projection.Prepared(f.Prepared(), 7));
        Assert.Equal("worker_projection_host_not_clean", Assert.Single(f.Faults));
    }
    [Fact]
    public void NewProjectionBetweenPreparedAndInstalledCannotPassTheHostBarrier()
    {
        using var f = new Fixture();
        JObject commit = JObject.Parse(f.Projection.Prepared(f.Prepared(), 7));
        commit["task"] = "worker_projection_committed"; commit["installClockKind"] = "flashRootEnterFrame";
        commit["installEpoch"] = 1; commit["installTick"] = 2;
        f.Clean = false; f.Projection.Committed(commit, 7);
        Assert.False(f.Projection.IsReady); Assert.Equal("worker_projection_host_not_clean", Assert.Single(f.Faults));
    }
    [Theory]
    [InlineData("presentationPolicy", "none")]
    [InlineData("controlFrameFormat", "f-control-placeholder-v1")]
    [InlineData("simulationRngConsumptionRevision", "visual-isolation-2")]
    public void ThisCandidateCannotEnableDeferredD3OrNewGameplayRng(string field, string value)
    {
        JObject config = Configuration(); config[field] = value;
        Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]));
    }
    [Fact]
    public void LegacySchemaCannotSmuggleNoneAndSessionPolicyOwnsItsCopy()
    {
        JObject config = Configuration(); config["schema"] = "arena-worker.launch.v1";
        Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]));
        config["schema"] = "arena-worker.launch.v2";
        var policy = ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]);
        config["projectionConsumers"]["ray"] = "full";
        Assert.True(policy.Projection.IsNone("ray"));
        config["projectionConsumers"]["equipmentLighting"] = "none";
        Assert.Throws<InvalidOperationException>(() => ArenaWorkerPolicy.FromConfiguration(config, (string)config["projectRoot"]));
    }
}
