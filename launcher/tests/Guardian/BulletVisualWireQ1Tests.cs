using System;
using System.Globalization;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class BulletVisualWireQ1Tests
{
    [Fact]
    public void EveryOptionalMaskReconstructsTheSameFloatsAsTheLegacyPacket()
    {
        for (int mask = 0; mask < 16; mask++)
        {
            float rotation = (mask & 1) != 0 ? -37.25f : 0;
            float sx = (mask & 2) != 0 ? -100 : 100;
            float sy = (mask & 4) != 0 ? 175.5f : 100;
            float alpha = (mask & 8) != 0 ? 42 : 100;
            string row = (3 + 16 * mask) + ",-12.5,1e-7";
            if ((mask & 1) != 0) row += "," + rotation.ToString("R", CultureInfo.InvariantCulture);
            if ((mask & 2) != 0) row += "," + sx.ToString("R", CultureInfo.InvariantCulture);
            if ((mask & 4) != 0) row += "," + sy.ToString("R", CultureInfo.InvariantCulture);
            if ((mask & 8) != 0) row += "," + alpha.ToString("R", CultureInfo.InvariantCulture);
            Assert.True(BulletVisualWireQ1.TryParse("Q1|1|2|3|4|1|0|R;" + row, 8, out var packed));
            Assert.True(BulletVisualFrame.TryParse(FormattableString.Invariant(
                $"2|4|1|0|0|1;3,-12.5,1e-7,{rotation},{sx},{sy},{alpha}"), 8, out var legacy));
            Assert.Equal(legacy.Instances, packed.Instances);
            Assert.Equal(4, packed.Frame);
            Assert.Equal(3, packed.SnapshotSequence);
            Assert.True(packed.NativeOwned);
        }
    }

    [Theory]
    [InlineData("Q1|1|1|1|0|0|0|R;")]
    [InlineData("Q1|1|1|1|0|1|0|R;0,1,2;")]
    [InlineData("Q1|1|1|1|0|1|0|R;256,1,2")]
    [InlineData("Q1|1|1|1|0|1|0|Q;0,1,2")]
    [InlineData("Q1|1|1|1|0|1|1|R;0,1,2")]
    [InlineData("Q1|01|1|1|0|1|0|R;0,1,2")]
    [InlineData("Q1|1|1|1|0|1|0|R;0,NaN,2")]
    [InlineData("Q1|1|1|1|0|1|0|R;0,1, 2")]
    [InlineData("Q1|1|1|1|0|1|0|R;128,1,2,101")]
    public void MalformedOrUnlicensedCoordinatesAreRejectedAtomically(string text)
        => Assert.False(BulletVisualWireQ1.TryParse(text, 8, out _));

    [Fact]
    public void EmptyAndMaximumCompleteSnapshotsHaveIndependentPacketSequences()
    {
        Assert.True(BulletVisualWireQ1.TryParse("Q1|1|1|2|0|0|0|R", 8, out var empty));
        Assert.Empty(empty.Instances);
        string rows = string.Join(';', System.Linq.Enumerable.Repeat("0,10,20", 1024));
        Assert.True(BulletVisualWireQ1.TryParse("Q1|1|1|3|0|1024|0|R;" + rows, 8, out var full));
        Assert.Equal(1024, full.NormalCount);
        Assert.Equal(empty.Frame, full.Frame);
        Assert.True(full.SnapshotSequence > empty.SnapshotSequence);
        Assert.False(BulletVisualWireQ1.TryParse("Q1|1|1|3|0|1025|0|R;" + rows + ";0,10,20", 8, out _));
    }
}
