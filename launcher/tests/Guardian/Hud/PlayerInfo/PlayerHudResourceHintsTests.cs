using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudResourceHintsTests
{
    internal static JObject Hints(string state = "ready", string reason = "") => new()
    {
        ["skills"] = new JArray(Enumerable.Range(0, 12).Select(_ => new JObject { ["state"] = state, ["reason"] = reason })),
        ["drugs"] = new JArray(Enumerable.Range(0, 4).Select(_ => new JObject { ["state"] = "ready", ["reason"] = "" })),
        ["weapon"] = new JObject { ["state"] = state, ["reason"] = reason },
        ["switchBlocked"] = false, ["feedback"] = null
    };
    private static PlayerHudSnapshot Snapshot()
    {
        var state = new PlayerHudState();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()), 1));
        return state.Snapshot;
    }
    private static PlayerHudSnapshot Notice(PlayerHudSnapshot snapshot, long serial = 1, string reason = "mp") => snapshot with
    {
        Resources = PlayerHudState.ReadResources(Hints()) with { Feedback = new(serial, "skill", 1, reason) }
    };

    [Fact]
    public void FreshAvm1ResourceWireIsAcceptedByTheProductionParser()
    {
        var json = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "PlayerHud", "as2-resource-hints-wire.json"));
        var state = new PlayerHudState();
        Assert.True(state.Receive(Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(json)), 1));
        Assert.NotNull(state.Snapshot.Resources);
        Assert.Equal(12, state.Snapshot.Resources.Skills.Length);
        Assert.Equal(4, state.Snapshot.Resources.Drugs.Length);
        Assert.False(state.Snapshot.Resources.SwitchBlocked);
    }

    [Fact]
    public void LegacyBaselineAndNewResourceDeltaHaveOneAtomicAdoptionPoint()
    {
        var state = new PlayerHudState(); var full = PlayerHudStateTests.Full();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(full), 1)); Assert.Null(state.Snapshot.Resources);
        var next = new JObject { ["v"] = 1, ["epoch"] = 1, ["seq"] = 2, ["full"] = false,
            ["visible"] = true, ["groups"] = new JObject { ["resources"] = Hints("last", "mp") } };
        Assert.True(state.Receive(PlayerHudStateTests.Encode(next), 2));
        Assert.Equal("last", state.Snapshot.Resources.Skills[0].State);
        var accepted = state.Snapshot;
        next["seq"] = 3; next["groups"]["resources"]["switchBlocked"] = "true";
        Assert.False(state.Receive(PlayerHudStateTests.Encode(next), 3)); Assert.Same(accepted, state.Snapshot);
        Assert.True(state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full(2, 4)), 4));
        Assert.Null(state.Snapshot.Resources); // A full old producer cannot retain the new producer's state.
    }

    [Theory]
    [InlineData("ready", "mp")]
    [InlineData("unknown", "item")]
    [InlineData("last", "")]
    [InlineData("blocked", "cooldown")]
    [InlineData("full", "")]
    public void RejectsAmbiguousOrFabricatedResourceStates(string state, string reason)
        => Assert.Throws<FormatException>(() => PlayerHudState.ReadResources(Hints(state, reason)));

    [Theory]
    [InlineData("skill", 0, "mp")]
    [InlineData("skill", 13, "mp")]
    [InlineData("drug", 4, "item")]
    [InlineData("drug", 0, "mp")]
    [InlineData("switch", 0, "mp")]
    [InlineData("weapon", 1, "mp")]
    [InlineData("weapon", 0, "empty")]
    public void RejectsWrongFeedbackTarget(string kind, int slot, string reason)
    {
        var hint = Hints(); hint["feedback"] = new JObject { ["serial"] = 1, ["kind"] = kind, ["slot"] = slot, ["reason"] = reason };
        Assert.Throws<FormatException>(() => PlayerHudState.ReadResources(hint));
    }

    [Fact]
    public void LowMpAloneNeverStartsAlarmAndDuplicateSnapshotsCannotRestartIt()
    {
        var snapshot = Snapshot(); var motion = new PlayerHudDenialMotion(); motion.Observe(snapshot);
        Assert.False(motion.Observe(snapshot with { Vitals = snapshot.Vitals with { Mp = 0 } }));
        Assert.Equal(0, motion.MpAlpha);
        var rejected = Notice(snapshot); Assert.True(motion.Observe(rejected));
        Assert.True(motion.MpAlpha > 0); Assert.True(motion.SlotAlpha("skill", 1) > 0);
        Assert.Equal(0, motion.SlotAlpha("weapon", 0));
        motion.Advance(500); motion.Observe(rejected); motion.Advance(150);
        Assert.False(motion.Active); Assert.Equal(0, motion.MpAlpha);
        motion.Observe(Notice(snapshot, 2)); Assert.True(motion.Active);
    }

    [Fact]
    public void BaselinePauseHideDeathAndDisconnectCannotReplayAStoredDenial()
    {
        var baseline = Snapshot(); var rejected = Notice(baseline);
        var motion = new PlayerHudDenialMotion(); motion.Observe(rejected);
        Assert.False(motion.Active);
        motion.Observe(Notice(baseline, 2)); Assert.True(motion.Active);
        motion.Observe(Notice(baseline, 2) with { Vitals = baseline.Vitals with { Paused = true } });
        Assert.False(motion.Active); motion.Observe(Notice(baseline, 2)); Assert.False(motion.Active);
        motion.Observe(Notice(baseline, 3), false); motion.Observe(Notice(baseline, 3)); Assert.False(motion.Active);
        motion.Observe(Notice(baseline, 4) with { Vitals = baseline.Vitals with { Hp = 0 } });
        motion.Observe(Notice(baseline, 4)); Assert.False(motion.Active);
        motion.Observe(null); motion.Observe(Notice(baseline, 5)); Assert.False(motion.Active);
        motion.Observe(Notice(baseline, 6) with { Epoch = 2 }); Assert.False(motion.Active);
    }

    [Fact]
    public void ItemDenialDoesNotFlashMpAndSwitchSealTracksTheCurrentTarget()
    {
        var snapshot = Snapshot(); var motion = new PlayerHudDenialMotion(); motion.Observe(snapshot);
        motion.Observe(Notice(snapshot, 1, "item")); Assert.True(motion.Active); Assert.Equal(0, motion.MpAlpha);
        var hints = PlayerHudState.ReadResources(Hints()) with { SwitchBlocked = true };
        var stocked = snapshot with { Resources = hints, Loadout = snapshot.Loadout with { Bank = 1 } };
        Assert.Equal("blocked", PlayerHudResourceHintPainter.Hint(stocked, "switch", 0).State);
        Assert.Equal("unknown", PlayerHudResourceHintPainter.Hint(stocked with { Resources = hints with { SwitchBlocked = false } }, "switch", 0).State);
        Assert.Equal("ready", PlayerHudResourceHintPainter.Hint(stocked, "drug", 4).State);
    }

    [Theory]
    [InlineData(8355.5, "8355")]
    [InlineData(99999.99, "99999")]
    [InlineData(0.5, "0.5")]
    [InlineData(0.001, "<0.01")]
    public void StrengthPlaqueUsesWholeLargeValuesWithoutChangingAuthority(double strength, string expected)
    {
        var detail = new PlayerHudShield("finite", strength, true, new("full", 1, 0, 0));
        Assert.Equal(expected, PlayerHudResourceStyle.ShieldStrengthReadout(detail));
        Assert.Equal(strength, detail.Strength);
    }

    [Fact]
    public void SealAndDenialStayInsideTheAuthoredFrameFootprint()
    {
        using var image = new Bitmap(64, 48, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(image))
            PlayerHudResourceHintPainter.PaintSlot(g, new(10, 10, 26, 26), new("blocked", "mp"), true, 0, 1);
        var painted = 0;
        for (var y = 0; y < image.Height; y++) for (var x = 0; x < image.Width; x++)
        {
            var pixel = image.GetPixel(x, y); if (pixel.A == 0) continue;
            var bounds = PlayerHudSlotFeedbackGeometry.MaximumPaintBounds;
            bounds.Offset(10, 10);
            painted++; Assert.True(bounds.Contains(x, y), $"Feedback leaked outside authored frame: {x},{y}");
        }
        Assert.True(painted > 200);
    }

    [Fact]
    public void OptionalWarningAtlasUsesProductionPainterAtActualSlotSize()
    {
        var folder = Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE_DIR");
        if (string.IsNullOrWhiteSpace(folder)) return;
        Directory.CreateDirectory(folder);
        using var image = new Bitmap(420, 96, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(image); g.Clear(Color.FromArgb(35, 37, 39));
        using var font = new Font("Microsoft YaHei", 9); using var ink = new SolidBrush(Color.White);
        var states = new[] { new PlayerHudResourceHint("ready", ""), new("last", "mp"), new("blocked", "mp"), new("blocked", "item"), new("blocked", "empty") };
        var labels = new[] { "正常", "仅够一次", "缺蓝", "缺材料", "空组" };
        for (var i = 0; i < states.Length; i++)
        {
            var r = new RectangleF(12 + i * 82, 16, 26, 26);
            g.DrawRectangle(Pens.Gray, r.X, r.Y, r.Width, r.Height);
            g.DrawLine(Pens.Gainsboro, r.X + 5, r.Y + 13, r.Right - 4, r.Top + 3);
            PlayerHudResourceHintPainter.PaintSlot(g, r, states[i], true, 375, 0);
            g.DrawString(i == 4 ? "6" : "U", font, ink, r.X + 8, r.Bottom - 10);
            g.DrawString(labels[i], font, ink, r.X - 4, 56);
        }
        image.Save(Path.Combine(folder, "resource-warning-atlas.png"), ImageFormat.Png);
    }
}
