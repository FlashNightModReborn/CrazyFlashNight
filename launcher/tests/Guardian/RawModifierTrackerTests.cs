using System.Linq;
using System;
using System.IO;
using System.Text.Json;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class RawModifierTrackerTests
{
    [Theory]
    [InlineData(16,42,0,160)] [InlineData(16,54,0,161)]
    [InlineData(17,29,0,162)] [InlineData(17,29,2,163)]
    [InlineData(18,56,0,164)] [InlineData(18,56,2,165)]
    public void PhysicalSidesAreDecodedAndReleaseClosesOnlyTheirState(int vk,int scan,int flags,int expected)
    {
        var t=new RawModifierTracker();
        Assert.Equal(RawModifierDisposition.Observed,t.Observe(1,vk,scan,flags,out var down));
        Assert.Equal(expected,down.Key);Assert.True(down.RawDown);Assert.True(down.KeyDown);Assert.True(down.AggregateDown);
        Assert.Equal(RawModifierDisposition.Observed,t.Observe(1,vk,scan,flags|1,out var up));
        Assert.False(up.RawDown);Assert.False(up.KeyDown);Assert.False(up.AggregateDown);Assert.Empty(t.HeldKeys);
    }
    [Fact] public void OneKeyboardReleaseCannotEraseAnotherKeyboardHold()
    {
        var t=new RawModifierTracker();t.Observe(1,17,29,0,out _);t.Observe(2,17,29,0,out _);
        t.Observe(1,17,29,1,out var firstUp);
        Assert.False(firstUp.RawDown);Assert.True(firstUp.KeyDown);Assert.True(firstUp.AggregateDown);
        t.Observe(2,17,29,1,out var finalUp);Assert.False(finalUp.KeyDown);Assert.Empty(t.HeldKeys);
    }
    [Fact] public void RepeatsAreIdempotentAndLeftReleaseDoesNotClearRight()
    {
        var t=new RawModifierTracker();t.Observe(1,17,29,0,out _);t.Observe(1,17,29,0,out _);
        t.Observe(1,17,29,2,out _);t.Observe(1,17,29,1,out var leftUp);
        Assert.False(leftUp.KeyDown);Assert.True(leftUp.AggregateDown);Assert.Equal(new[]{163},t.HeldKeys.ToArray());
        t.Observe(1,17,29,3,out _);Assert.Empty(t.HeldKeys);
    }
    [Theory]
    [InlineData(17,0,0)] [InlineData(16,29,0)] [InlineData(162,29,2)]
    [InlineData(18,56,4)] [InlineData(16,42,2)] [InlineData(17,29,8)]
    public void UnknownOrContradictoryPacketsCannotClearHeldState(int vk,int scan,int flags)
    {
        var t=new RawModifierTracker();t.Observe(1,17,29,0,out _);
        Assert.Equal(RawModifierDisposition.Unsupported,t.Observe(1,vk,scan,flags,out _));
        Assert.Equal(new[]{162},t.HeldKeys.ToArray());
    }
    [Fact] public void NonModifierAndOrphanUpNeverInventAHeldKey()
    {
        var t=new RawModifierTracker();Assert.Equal(RawModifierDisposition.NotModifier,t.Observe(1,65,30,0,out _));
        Assert.Equal(RawModifierDisposition.Observed,t.Observe(1,16,42,1,out var up));
        Assert.False(up.KeyDown);Assert.Empty(t.HeldKeys);
    }
    [Fact] public void FrozenManualRawSequenceRecoversAllModifierHoldsWithoutBorrowingLlCallbacks()
    {
        using var doc=JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Fixtures","InputOwnership","r9-manual-modifiers.json")));
        var t=new RawModifierTracker();int count=0,downs=0,ups=0,maxHeld=0;
        foreach(var packet in doc.RootElement.GetProperty("packets").EnumerateArray()) {
            Assert.Equal(RawModifierDisposition.Observed,t.Observe(packet.GetProperty("deviceAlias").GetInt64(),
                packet.GetProperty("key").GetInt32(),packet.GetProperty("scan").GetInt32(),packet.GetProperty("flags").GetInt32(),out var state));
            count++;if(state.RawDown)downs++;else ups++;
            maxHeld=Math.Max(maxHeld,t.HeldKeys.Count);
        }
        Assert.Equal(48,count);Assert.Equal(24,downs);Assert.Equal(24,ups);Assert.Equal(3,maxHeld);Assert.Empty(t.HeldKeys);
    }
}
