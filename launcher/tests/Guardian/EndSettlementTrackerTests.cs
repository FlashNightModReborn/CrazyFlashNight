using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class EndSettlementTrackerTests
{
    private static readonly HandoffRound Round = new("session", "closure", 3, 4, 1);
    private static readonly HandoffRound Later = new("session", "closure", 4, 4, 1);
    private static InputGesture Gesture(long id, HandoffRound round) => new(round, new InputScope("M", 1), id, 1, 40);

    [Fact] public void CompletionSuspendsHoverBeforeEndIsDispatched()
    {
        var tracker = new EndSettlementTracker();
        Assert.False(tracker.Pending);
        tracker.Track(Gesture(7, Round));
        Assert.True(tracker.Pending);
        Assert.False(tracker.Dispatched);
        Assert.Equal(7, tracker.PendingGesture);
        Assert.False(tracker.Expire(long.MaxValue, 1));
        Assert.True(tracker.Pending);
    }

    [Fact] public void ReplyDeadlineRunsOnlyFromActualDispatch()
    {
        var tracker = new EndSettlementTracker();
        tracker.Track(Gesture(7, Round));
        Assert.False(tracker.Expire(10_000, 500));
        Assert.False(tracker.MarkDispatched(8, Round, 100));
        Assert.True(tracker.MarkDispatched(7, Round, 1_000));
        Assert.False(tracker.Expire(1_499, 500));
        Assert.True(tracker.Pending);
        Assert.True(tracker.Expire(1_500, 500));
        Assert.False(tracker.Pending);
    }

    [Fact] public void OnlyExactEndIdentityCanSettle()
    {
        var tracker = new EndSettlementTracker();
        tracker.Track(Gesture(7, Round));
        tracker.MarkDispatched(7, Round, 0);
        Assert.False(tracker.Settle("END", 8, Round));
        Assert.False(tracker.Settle("END", 7, Later));
        Assert.False(tracker.Settle("BEGIN", 7, Round));
        Assert.False(tracker.Settle("PANEL", 7, Round));
        Assert.True(tracker.Pending);
        Assert.True(tracker.Settle("END", 7, Round));
        Assert.False(tracker.Pending);
        Assert.False(tracker.Settle("END", 7, Round));
        Assert.False(tracker.MarkDispatched(7, Round, 200));
    }

    [Fact] public void NoOpenerTerminalReplyStillUnlocks()
    {
        var tracker = new EndSettlementTracker();
        tracker.Track(Gesture(7, Round));
        tracker.MarkDispatched(7, Round, 0);
        Assert.True(tracker.Settle("END", 7, Round));
        Assert.False(tracker.Pending);
    }

    [Fact] public void CancelClearsPendingAndStaleRepliesCannotSettleNewGesture()
    {
        var tracker = new EndSettlementTracker();
        tracker.Track(Gesture(7, Round));
        tracker.MarkDispatched(7, Round, 0);
        tracker.Cancel();
        Assert.False(tracker.Pending);
        Assert.False(tracker.Settle("END", 7, Round));
        tracker.Track(Gesture(11, Later));
        Assert.False(tracker.Settle("END", 7, Round));
        Assert.False(tracker.MarkDispatched(7, Round, 5));
        Assert.True(tracker.Pending);
        Assert.True(tracker.Settle("END", 11, Later));
        Assert.False(tracker.Pending);
    }

    [Fact] public void NewerCompletionSupersedesPendingIdentity()
    {
        var tracker = new EndSettlementTracker();
        tracker.Track(Gesture(7, Round));
        tracker.MarkDispatched(7, Round, 0);
        tracker.Track(Gesture(8, Round));
        Assert.Equal(8, tracker.PendingGesture);
        Assert.False(tracker.Settle("END", 7, Round));
        Assert.True(tracker.Settle("END", 8, Round));
        Assert.False(tracker.Pending);
    }
}
