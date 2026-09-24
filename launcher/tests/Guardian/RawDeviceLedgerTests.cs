using System;
using System.Linq;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class RawDeviceLedgerTests
{
    [Fact] public void PausePulseDoesNotCreateAnUnreleasableDeviceHold()
    {
        var state = new RawDeviceLedger();
        Assert.Equal(RawPacketResult.Invalid, state.Keyboard(1, 19, 69, 4, out var changes));
        Assert.Empty(changes); Assert.False(state.IsDown(19));
        Assert.True(state.SnapshotConsistent(Snapshot()));
    }
    private static System.Collections.Generic.Dictionary<int, bool> Snapshot(params int[] held) =>
        RawDeviceLedger.SnapshotKeys.ToDictionary(key => key, held.Contains);

    [Fact] public void SecondKeyboardReleaseCannotReleaseFirstKeyboard()
    {
        var state = new RawDeviceLedger(); state.Reconcile(Snapshot());
        Assert.Equal(RawPacketResult.Observed, state.Keyboard(1, 65, 30, 0, out _));
        state.Keyboard(2, 65, 30, 0, out _); state.Keyboard(2, 65, 30, 1, out var release);
        Assert.True(release.Single().Down); Assert.True(state.IsDown(65));
        Assert.False(state.SnapshotConsistent(Snapshot()));
        Assert.Throws<InvalidOperationException>(() => state.Reconcile(Snapshot()));
        state.Keyboard(1, 65, 30, 1, out release); Assert.False(release.Single().Down);
    }

    [Fact] public void PreheldSnapshotNeedsReconciliationNotOrphanUp()
    {
        var state = new RawDeviceLedger(); state.Reconcile(Snapshot(65));
        state.Keyboard(2, 65, 30, 1, out var orphan);
        Assert.True(orphan.Single().Down);
        state.Reconcile(Snapshot()); Assert.False(state.IsDown(65));
    }

    [Fact] public void RepeatAndTwoPhysicalEnterKeysDoNotLoseHold()
    {
        var state = new RawDeviceLedger();
        state.Keyboard(1, 13, 28, 0, out _); state.Keyboard(1, 13, 28, 0, out _);
        state.Keyboard(1, 13, 28, 2, out _); state.Keyboard(1, 13, 28, 1, out var mainUp);
        Assert.True(mainUp.Single().Down);
        state.Keyboard(1, 13, 28, 3, out var keypadUp); Assert.False(keypadUp.Single().Down);
    }

    [Fact] public void NumlockChangedBetweenDownAndUpUsesOriginalPhysicalKey()
    {
        var state = new RawDeviceLedger();
        state.Keyboard(1, 97, 79, 0, out _);
        state.Keyboard(1, 35, 79, 1, out var up);
        Assert.Equal(new RawKeyChange(97, false), up.Single());
    }

    [Fact] public void ModifierAliasesRespectBothSidesAndDevices()
    {
        var state = new RawDeviceLedger();
        state.Keyboard(1, 17, 29, 0, out _); state.Keyboard(2, 17, 29, 2, out _);
        state.Keyboard(1, 17, 29, 1, out var up);
        Assert.Equal(new RawKeyChange(162, false), up[0]); Assert.Equal(new RawKeyChange(17, true), up[1]);
        state.Keyboard(2, 17, 29, 3, out up); Assert.Equal(new RawKeyChange(17, false), up[1]);
    }

    [Fact] public void MouseMalformedPacketIsAtomicAndTwoMiceAggregate()
    {
        var state = new RawDeviceLedger();
        Assert.Equal(RawPacketResult.Invalid, state.Mouse(1, 1 | (3 << 2), out _));
        Assert.False(state.IsDown(1));
        state.Mouse(1, 1, out _); state.Mouse(2, 1, out _); state.Mouse(2, 2, out var release);
        Assert.True(release.Single().Down); state.Mouse(1, 2, out release); Assert.False(release.Single().Down);
    }

    [Theory]
    [InlineData(65, 0, 0)] [InlineData(65, 255, 0)] [InlineData(17, 29, 4)]
    [InlineData(162, 29, 2)] [InlineData(65, 30, 8)]
    public void AmbiguousPacketsCannotInventSideOrRelease(int key, int scan, int flags)
    {
        var state = new RawDeviceLedger();
        Assert.Equal(RawPacketResult.Invalid, state.Keyboard(1, key, scan, flags, out _));
    }
}
