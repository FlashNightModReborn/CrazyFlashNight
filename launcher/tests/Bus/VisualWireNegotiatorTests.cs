using System.Collections.Generic;
using CF7Launcher.Bus;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Bus;

public sealed class VisualWireNegotiatorTests
{
    private static JObject Selection(JObject offer, string choice = "q1") => new() {
        ["task"] = "visual_wire_select", ["version"] = 1, ["token"] = offer["token"], ["offerId"] = 1,
        ["channels"] = new JObject { ["f5"] = choice, ["scenePose"] = "legacy" }, ["f5QuantProfile"] = "none"
    };

    [Fact]
    public void InstallsDecoderBeforeCommitAndRetiresLegacyOnlyAfterActualData()
    {
        var sent = new List<JObject>();
        var wire = new VisualWireNegotiator(true, (text, generation) => { sent.Add(JObject.Parse(text.TrimEnd('\0'))); return true; });
        wire.Ready(2);
        Assert.False(wire.CanDecodeQ1(2, 1));
        var select = Selection(sent[0]);
        string commit = wire.Select(select, 2);
        Assert.NotNull(commit);
        Assert.True(wire.CanDecodeQ1(2, 1));
        Assert.False(wire.LegacyRetired(2));
        Assert.Equal(commit, wire.Select(select, 2));
        Assert.Null(wire.Select(Selection(sent[0], "legacy"), 2));
        Assert.True(wire.ActivateQ1(2));
        Assert.True(wire.LegacyRetired(2));
        wire.Disconnected(1);
        Assert.True(wire.CanDecodeQ1(2, 1));
        wire.Disconnected(2);
        Assert.False(wire.CanDecodeQ1(2, 1));
        wire.Ready(3);
        Assert.Null(wire.Select(select, 3));
        Assert.Null(wire.Select(Selection(sent[1]), 2));
        Assert.NotNull(wire.Select(Selection(sent[1]), 3));
    }

    [Fact]
    public void GenerationRouterUsesOriginalMessageGenerationAndRejectsDuplicateJsonProperties()
    {
        var router = new MessageRouter();
        int observed = -1;
        router.RegisterSyncForGeneration("test", (message, generation) => { observed = generation; return "{\"success\":true}"; });
        Assert.NotNull(router.ProcessMessage("{\"task\":\"test\"}", 12, null));
        Assert.Equal(12, observed);
        router.ProcessMessage("{\"task\":\"test\",\"task\":\"test\"}", 99, null);
        Assert.Equal(12, observed);
        router.ProcessMessage("{\"task\":\"test\"}", null);
        Assert.Equal(0, observed);
    }

    [Fact]
    public void MalformedSelectionCannotChangeTheInstalledChoice()
    {
        JObject offer = null;
        var wire = new VisualWireNegotiator(true, (text, generation) => { offer = JObject.Parse(text.TrimEnd('\0')); return true; });
        wire.Ready(1);
        foreach (var bad in new[] { Selection(offer), Selection(offer), Selection(offer), Selection(offer) })
        {
            // Each malformed variant is independent, including a decimal value that compares numerically equal.
            if (wire.Rejected == 0) bad["version"] = 1.0;
            else if (wire.Rejected == 1) bad["extra"] = true;
            else if (wire.Rejected == 2) bad["channels"]["scenePose"] = "l2";
            else bad["offerId"] = JToken.Parse("99999999999999999999999999999999999");
            Assert.Null(wire.Select(bad, 1));
            Assert.False(wire.CanDecodeQ1(1, 1));
        }
        Assert.NotNull(wire.Select(Selection(offer), 1));
        Assert.False((bool)JObject.Parse(wire.Select(Selection(offer), 1))["qAllowed"]);
    }
}
