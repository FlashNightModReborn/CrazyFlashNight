using System;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

// Real message-queue/registration lifecycle only. No synthetic input, no neutral
// certification, and no business endpoint. The suite's existing serial policy
// prevents concurrent in-process Raw Input ownership.
public sealed class RawInputSourceControlTests
{
    [Fact]
    public async Task ControlLaneUsesObserverThreadAndOrdersDeclaredSourceLoss()
    {
        using var source = new RawInputSource();
        int caller = Environment.CurrentManagedThreadId;
        var first = await source.OnObserver((ledger, _) => (Thread: Environment.CurrentManagedThreadId, Prefix: ledger.Prefix));
        Assert.NotEqual(caller, first.Thread);
        source.RequestFaultControl();
        var after = await source.OnObserver((ledger, _) => (Thread: Environment.CurrentManagedThreadId, Prefix: ledger.Prefix));
        Assert.Equal(first.Thread, after.Thread);
        Assert.True(after.Prefix.Generation > first.Prefix.Generation);
    }

    [Fact]
    public async Task RetiredObserverRejectsControlWithoutExecutingIt()
    {
        var source = new RawInputSource();
        source.Dispose();
        Assert.False(source.Status.Healthy);
        Assert.Equal("observer_stopped", source.Status.Reason);
        bool called = false;
        await Assert.ThrowsAsync<InvalidOperationException>(() => source.OnObserver((_, _) => { called = true; return 1; }));
        Assert.False(called);
        source.Dispose();
    }
}
