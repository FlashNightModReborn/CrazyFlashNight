using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public class R2ProtocolAndReducerMutationTests
{
    private const int InitialConnection = 1;
    private const int ActionVk = 0x44;
    private const int ShiftVk = 16;
    private static readonly string EmptyBitmap = new('0', 64);

    // G21: the Host passes the competing directions, Shift and double-tap
    // direction through to the consumer in frame order.
    [Theory]
    [InlineData(-1)]
    [InlineData(0)]
    [InlineData(1)]
    public void ComboFramePreservesDirectionConflictShiftAndDoubleTapDirection(int direction)
    {
        var input = GrantGame();
        const int mask = 1 | 32 | 64 | 128;
        const string atoms = "9,32,D;10,64,D;11,1,D;11,128,D";
        string wire = ComboWire(input, 12, mask: mask, facing: 0, direction: direction, atomCount: 4, atoms: atoms);
        var frame = ParseCombo(wire);

        Assert.Equal(wire, frame.Wire);
        Assert.Equal(12, frame.Frame);
        Assert.Equal(mask, frame.Mask);
        Assert.Equal(0, frame.Facing);
        Assert.Equal(direction, frame.Direction);
        Assert.Equal(atoms, frame.Atoms);
        Assert.True(input.BeginCombo(frame, InitialConnection));
        Assert.False(input.BeginCombo(frame, InitialConnection));
        Assert.True(input.IsGameKeyboardAdmitted);
    }

    // G22: drive a pulse between actual Host latches. Its edges must survive
    // even when the corresponding bitmap bit is zero in both snapshots.
    [Fact]
    public void ShortPulseAndMultipleEdgesKeepTheirOrderBetweenLatches()
    {
        var input = GrantGame();
        const int leftVk = 0x25;
        Assert.Equal(1, input.LastLatchedFrameSeq);
        Assert.Equal(EmptyBitmap, input.AdmittedHex);
        Assert.True(input.ObserveKey(ActionVk, true));
        Assert.True(input.ObserveKey(leftVk, true));
        Assert.True(input.ObserveKey(ActionVk, false));
        Assert.False(input.ObserveKey(leftVk, true));

        var batch = TakeBatch(input);
        var edges = BatchEdges(batch);
        Assert.Equal(new[] { (ActionVk, true), (leftVk, true), (ActionVk, false) },
            edges.Select(edge => (edge.Vk, edge.Down)));
        Assert.True(edges[0].Sequence < edges[1].Sequence && edges[1].Sequence < edges[2].Sequence);
        Assert.False(BitmapContains(batch[8], ActionVk));
        Assert.True(BitmapContains(batch[8], leftVk));
        Assert.False(input.TryTakeOutput(out _));
        Assert.True(input.Receive(InitialConnection, Latch(batch, 2)));
        Assert.Equal(2, input.LastLatchedFrameSeq);

        string atoms = $"{edges[0].Sequence},1,D;{edges[1].Sequence},32,D;{edges[2].Sequence},1,U";
        var frame = ParseCombo(ComboWire(input, 2, mask: 32, atomCount: 3, atoms: atoms));
        Assert.Equal(atoms, frame.Atoms);
        Assert.True(input.BeginCombo(frame, InitialConnection));
        Assert.False(input.BeginCombo(frame, InitialConnection));
        Assert.True(input.ObserveKey(leftVk, false));
        AssertEdges(input, (leftVk, false));
    }

    // G23: an old completion cannot publish under a later frame, connection,
    // or epoch. Actor/config travel in the originating frame identity.
    [Fact]
    public void DelayedComboCompletionCannotPublishUnderANewerOrigin()
    {
        var input = GrantGame();
        var previous = ParseCombo(ComboWire(input, 1, actor: 4, config: 6));
        var current = ParseCombo(ComboWire(input, 2, actor: 5, config: 7));
        var oldActor = ParseCombo(ComboWire(input, 2, actor: 4, config: 7));
        var oldConfig = ParseCombo(ComboWire(input, 2, actor: 5, config: 6));
        Assert.False(input.BeginCombo(previous, InitialConnection + 1));
        Assert.True(input.BeginCombo(previous, InitialConnection));
        Assert.True(input.BeginCombo(current, InitialConnection));
        Assert.False(input.BeginCombo(previous, InitialConnection));
        Assert.False(input.CompleteCombo(previous, "1|7|old||[]"));
        Assert.False(input.CompleteCombo(oldActor, "1|7|old_actor||[]"));
        Assert.False(input.CompleteCombo(oldConfig, "1|7|old_config||[]"));
        Assert.False(input.TryTakeOutput(out _));
        Assert.True(input.CompleteCombo(current, "1|8|current||[]"));
        Assert.False(input.CompleteCombo(current, "1|8|duplicate||[]"));
        Assert.Equal(1, input.V8ComboCount);
        Assert.True(input.TryTakeOutput(out var command));
        Assert.Equal($"I1|K|{current.Origin}|1|8|current||[]", command.Payload);

        var ticket = RequireCancel(input.Cancel("modal_open"));
        AssertControl(input, CancelWire(ticket, "modal_open"));
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.True(input.Acknowledge(ticket, InputParticipant.V8));
        TakeBatch(input);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
        var successor = ParseCombo(ComboWire(input, 2, actor: 5, config: 7));
        Assert.True(input.BeginCombo(successor, InitialConnection));
        Assert.False(input.BeginCombo(current, InitialConnection));
        Assert.False(input.CompleteCombo(current, "1|9|late||[]"));
        Assert.True(input.CompleteCombo(successor, "1|10|fresh||[]"));
        Assert.True(input.TryTakeOutput(out var fresh));
        Assert.Equal($"I1|K|{successor.Origin}|1|10|fresh||[]", fresh.Payload);
        Assert.False(input.TryTakeOutput(out _));
        Assert.True(input.IsGameKeyboardAdmitted);
    }

    [Fact]
    public void HintOnlyComboResultPreservesQueuedCommandsAndCommandSequence()
    {
        var input = GrantGame();
        var command = ParseCombo(ComboWire(input, 1));
        var hints = ParseCombo(ComboWire(input, 2));
        var next = ParseCombo(ComboWire(input, 3));
        const string hintResult = """0|0|||[{"name":"example","sequence":"AB","steps":1}]""";
        Assert.True(input.BeginCombo(command, InitialConnection));
        Assert.True(input.CompleteCombo(command, "1|7|first||[]"));
        Assert.True(input.BeginCombo(hints, InitialConnection));
        Assert.True(input.CompleteCombo(hints, hintResult));
        Assert.True(input.BeginCombo(next, InitialConnection));
        Assert.True(input.CompleteCombo(next, "2|9|second||[]"));

        Assert.Equal(3, input.PendingData);
        Assert.True(input.TryTakeOutput(out var firstOutput));
        Assert.True(input.TryTakeOutput(out var hintOutput));
        Assert.True(input.TryTakeOutput(out var nextOutput));
        Assert.Equal($"I1|K|{command.Origin}|1|7|first||[]", firstOutput.Payload);
        Assert.Equal($"I1|K|{hints.Origin}|{hintResult}", hintOutput.Payload);
        Assert.Equal($"I1|K|{next.Origin}|2|9|second||[]", nextOutput.Payload);
        Assert.False(input.TryTakeOutput(out _));
    }

    // G24: Host data and deferred results are settled at the cancel boundary,
    // while the physical Down remains and its real Up only clears suppression.
    [Fact]
    public void CancelDropsQueuedBatchAndComboAndFencesDeferredCompletion()
    {
        var input = GrantGame();
        Assert.True(input.ObserveKey(ActionVk, true));
        var command = ParseCombo(ComboWire(input, 1, mask: 1, atomCount: 1, atoms: "2,1,D"));
        Assert.True(input.BeginCombo(command, InitialConnection));
        Assert.True(input.CompleteCombo(command, "1|7|queued||[]"));
        var deferred = ParseCombo(ComboWire(input, 2, mask: 1));
        Assert.True(input.BeginCombo(deferred, InitialConnection));
        Assert.Equal(2, input.PendingData);

        var ticket = RequireCancel(input.Cancel("modal_open"));
        AssertControl(input, CancelWire(ticket, "modal_open"));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.True(input.IsPhysicallyDown(ActionVk));
        Assert.True(input.IsSuppressed(ActionVk));
        Assert.Equal(EmptyBitmap, input.AdmittedHex);
        Assert.False(input.TryTakeOutput(out _));
        Assert.False(input.CompleteCombo(deferred, "2|7|now_stale||[]"));
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.True(input.IsWaiting(ticket, InputParticipant.V8));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.True(input.Acknowledge(ticket, InputParticipant.V8));
        Assert.Empty(BatchEdges(TakeBatch(input)));
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.False(input.CompleteCombo(deferred, "2|7|still_stale||[]"));
        Assert.False(input.ObserveKey(ActionVk, false));
        Assert.False(input.IsPhysicallyDown(ActionVk));
        Assert.False(input.IsSuppressed(ActionVk));
        Assert.False(input.TryTakeOutput(out _));
    }

    // G28: one generic modifier stays Down until the last side releases.
    [Theory]
    [InlineData(0xA0, 0xA1, ShiftVk)]
    [InlineData(0xA2, 0xA3, 17)]
    [InlineData(0xA4, 0xA5, 18)]
    public void ModifierPairEmitsOneGenericDownAndOnlyTheFinalGenericUp(int left, int right, int aggregate)
    {
        var input = GrantGame();
        Assert.True(input.ObserveKey(left, true));
        Assert.True(input.ObserveKey(right, true));
        Assert.False(input.ObserveKey(right, true));
        AssertEdges(input, (left, true), (aggregate, true), (right, true));
        Assert.True(BitmapContains(input.AdmittedHex, aggregate));

        Assert.True(input.ObserveKey(left, false));
        AssertEdges(input, (left, false));
        Assert.True(input.IsPhysicallyDown(aggregate));
        Assert.True(BitmapContains(input.AdmittedHex, aggregate));

        Assert.True(input.ObserveKey(right, false));
        AssertEdges(input, (right, false), (aggregate, false));
        Assert.False(input.IsPhysicallyDown(aggregate));
        Assert.False(BitmapContains(input.AdmittedHex, aggregate));
    }

    [Theory]
    [InlineData(0xA0, 0xA1, ShiftVk)]
    [InlineData(0xA2, 0xA3, 17)]
    [InlineData(0xA4, 0xA5, 18)]
    public void CancelSuppressesBothModifierSidesAndAggregateUntilTheirRealUps(int left, int right, int aggregate)
    {
        var input = GrantGame();
        Assert.True(input.ObserveKey(left, true));
        Assert.True(input.ObserveKey(right, true));
        AssertEdges(input, (left, true), (aggregate, true), (right, true));

        var ticket = RequireCancel(input.Cancel("modal_open"));
        AssertControl(input, CancelWire(ticket, "modal_open"));
        Assert.False(input.IsGameKeyboardAdmitted);
        foreach (int vk in new[] { left, right, aggregate })
        {
            Assert.True(input.IsPhysicallyDown(vk));
            Assert.True(input.IsSuppressed(vk));
            Assert.False(BitmapContains(input.AdmittedHex, vk));
        }

        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
        var initial = TakeBatch(input);
        Assert.Empty(BatchEdges(initial));
        Assert.Equal(EmptyBitmap, initial[8]);
        Assert.False(input.ObserveKey(left, false));
        Assert.False(input.IsSuppressed(left));
        Assert.True(input.IsSuppressed(right));
        Assert.True(input.IsSuppressed(aggregate));
        Assert.True(input.IsPhysicallyDown(aggregate));
        Assert.False(BitmapContains(input.AdmittedHex, aggregate));
        Assert.False(input.TryTakeOutput(out _));

        Assert.False(input.ObserveKey(right, false));
        Assert.Empty(input.SuppressedVks);
        Assert.False(input.IsPhysicallyDown(aggregate));
        Assert.Equal(EmptyBitmap, input.AdmittedHex);
        Assert.False(input.TryTakeOutput(out _));
        Assert.True(input.ObserveKey(left, true));
        AssertEdges(input, (left, true), (aggregate, true));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void SameKeyHeldByTwoDevicesWaitsForTheFinalPhysicalUp(bool cancelWhileHeld)
    {
        var input = GrantGame();
        const long firstDevice = 11, secondDevice = 22;
        const InputObservationSource attributed = InputObservationSource.Hardware;
        Assert.True(input.ObserveKey(ActionVk, true, source: attributed, deviceId: firstDevice));
        Assert.False(input.ObserveKey(ActionVk, true, source: attributed, deviceId: secondDevice));
        Assert.False(input.ObserveKey(ActionVk, true, source: attributed, deviceId: firstDevice));
        AssertEdges(input, (ActionVk, true));
        if (cancelWhileHeld)
        {
            var cancel = RequireCancel(input.Cancel("modal_open"));
            AssertControl(input, CancelWire(cancel, "modal_open"));
            Assert.True(input.Receive(InitialConnection, CancelledWire(cancel)));
            Assert.Empty(BatchEdges(TakeBatch(input)));
            Assert.True(input.IsSuppressed(ActionVk));
        }

        Assert.False(input.ObserveKey(ActionVk, false, source: attributed, deviceId: firstDevice));
        Assert.True(input.IsPhysicallyDown(ActionVk));
        Assert.Equal(!cancelWhileHeld, BitmapContains(input.AdmittedHex, ActionVk));
        Assert.Equal(cancelWhileHeld, input.IsSuppressed(ActionVk));
        Assert.False(input.TryTakeOutput(out _));

        Assert.Equal(!cancelWhileHeld, input.ObserveKey(ActionVk, false, source: attributed, deviceId: secondDevice));
        Assert.False(input.IsPhysicallyDown(ActionVk));
        Assert.False(input.IsSuppressed(ActionVk));
        if (cancelWhileHeld)
            Assert.False(input.TryTakeOutput(out _));
        else
            AssertEdges(input, (ActionVk, false));
        Assert.True(input.ObserveKey(ActionVk, true, source: attributed, deviceId: firstDevice));
        AssertEdges(input, (ActionVk, true));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ForegroundOrSourceLossInvalidatesObservationAndUnstableReturnCannotGrant(bool sourceLost)
    {
        var input = GrantGame();
        Assert.True(input.ObserveKey(ActionVk, true));
        long oldGeneration = input.ObservationGeneration;
        if (sourceLost)
            input.ObserveSourceLost("device_removed");
        else
            input.SetForeground(false);
        Assert.True(input.ObservationGeneration > oldGeneration);
        Assert.False(input.IsPhysicallyDown(ActionVk));
        Assert.False(input.IsGameKeyboardAdmitted);
        var ticket = RequireCancel(input.LastAppliedCancel);
        AssertControl(input, CancelWire(ticket, sourceLost ? "device_removed" : "foreground_lost"));
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.False(input.IsWaiting(ticket, InputParticipant.AS2));

        int sampled = 0;
        input.SetForeground(true, held: vk => vk == ActionVk && ++sampled == 2);
        Assert.True(sampled >= 2);
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.Equal(1L, input.CurrentKeyboardEpoch);
        Assert.False(input.TryTakeOutput(out _));

        input.SetForeground(true, held: _ => false);
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
        Assert.Empty(BatchEdges(TakeBatch(input)));
    }

    [Fact]
    public void LedgerSourceLossRequiresNewPrefixAndStableCompleteSnapshots()
    {
        var ledger = new PhysicalInputLedger(new[] { 0, ActionVk, 255 }, fullVkRange: true);
        var clear = new Dictionary<int, bool> { [0] = false, [ActionVk] = false, [255] = false };
        Assert.True(ledger.ConfirmSources(ledger.Prefix));
        Assert.True(ledger.TryReconcile(ledger.Prefix, clear, clear, environmentQualified: true, prefixDrained: true));
        Assert.NotNull(ledger.Observe(ledger.Prefix.Generation, ActionVk, true, InputObservationSource.Hardware, deviceId: 11));
        Assert.False(ledger.TryReconcile(ledger.Prefix, clear, clear, environmentQualified: true, prefixDrained: true));
        Assert.Equal(ObservedKeyState.Down, ledger[ActionVk]);
        Assert.Null(ledger.TryProveNeutral());
        var previous = ledger.Prefix;

        var fresh = ledger.Invalidate("source_lost");
        Assert.True(fresh.Generation > previous.Generation);
        Assert.Equal(ObservedKeyState.Unknown, ledger[ActionVk]);
        Assert.Equal(ObservedKeyState.Unknown, ledger[255]);
        Assert.False(ledger.HasQualifiedBaseline);
        Assert.Null(ledger.TryProveNeutral());
        Assert.False(ledger.ConfirmSources(previous));
        Assert.Null(ledger.Observe(previous.Generation, ActionVk, false, InputObservationSource.Unmarked));
        Assert.True(ledger.ConfirmSources(fresh));
        var unstable = new Dictionary<int, bool>(clear) { [ActionVk] = true };
        Assert.False(ledger.TryReconcile(fresh, clear, unstable, environmentQualified: true, prefixDrained: true));
        Assert.Equal(ObservedKeyState.Unknown, ledger[ActionVk]);
        Assert.Null(ledger.TryProveNeutral());
        Assert.True(ledger.TryReconcile(ledger.Prefix, clear, clear, environmentQualified: true, prefixDrained: true));
        Assert.Equal(ObservedKeyState.Up, ledger[ActionVk]);
        Assert.NotNull(ledger.TryProveNeutral());
    }

    // G30: reject invalid VKs without consuming a serial; reject reordered
    // reports without changing either the physical or admitted state.
    [Fact]
    public void OutOfRangeVksAndNonMonotonicInputSerialsDoNotChangeState()
    {
        var ledger = new PhysicalInputLedger(new[] { 0, 255 }, fullVkRange: true);
        var original = ledger.Prefix;
        Assert.Null(ledger.Observe(original.Generation, -1, true, InputObservationSource.Unmarked));
        Assert.Null(ledger.Observe(original.Generation, 256, true, InputObservationSource.Unmarked));
        Assert.Equal(original, ledger.Prefix);

        var input = GrantGame();
        Assert.False(input.ObserveKey(-1, true, inputSerial: 100));
        Assert.False(input.ObserveKey(256, true, inputSerial: 101));
        Assert.True(input.ObserveKey(255, true, inputSerial: 50));
        Assert.False(input.ObserveKey(255, false, inputSerial: 50));
        Assert.False(input.ObserveKey(255, false, inputSerial: 49));
        Assert.False(input.ObserveKey(255, false, inputSerial: -5));
        Assert.True(input.IsPhysicallyDown(255));
        Assert.True(BitmapContains(input.AdmittedHex, 255));
        AssertEdges(input, (255, true));
        Assert.True(input.ObserveKey(255, false, inputSerial: 51));
        AssertEdges(input, (255, false));
    }

    [Fact]
    public void OlderEndpointIncarnationAndFocusSerialCannotReplaceTheCurrentTextLease()
    {
        var input = GrantGame();
        const string endpoint = "modifier.edit.itemQuery";
        Assert.True(input.RegisterObservedInstance(endpoint, 8));
        Assert.False(input.RegisterObservedInstance(endpoint, 7));
        var focus = new TextFocusObservation(input.CurrentSessionId, new IntPtr(1), new IntPtr(2), 10, true);
        Assert.Null(input.AcquireText(endpoint, 7, focus));
        var lease = input.AcquireText(endpoint, 8, focus);
        Assert.NotNull(lease);
        Assert.False(input.RegisterObservedInstance(endpoint, 7));
        Assert.Null(input.AcquireText(endpoint, 8, focus));
        Assert.Null(input.AcquireText(endpoint, 8, focus with { FocusSerial = 9 }));
        Assert.Equal(lease, input.CurrentTextLease);
        Assert.NotNull(input.AcquireText(endpoint, 8, focus with { FocusSerial = 11 }));
        Assert.NotEqual(lease, input.CurrentTextLease);
    }

    [Fact]
    public void InputSerialCeilingRevokesBeforeAReleaseCanCrossTheBoundary()
    {
        var input = GrantGame();
        Assert.True(input.ObserveKey(ActionVk, true, inputSerial: long.MaxValue - 1));
        AssertEdges(input, (ActionVk, true));
        Assert.False(input.ObserveKey(ActionVk, false, inputSerial: long.MaxValue));
        Assert.True(input.IsPhysicallyDown(ActionVk));
        Assert.True(input.IsSuppressed(ActionVk));
        var ticket = RequireCancel(input.LastAppliedCancel);
        AssertControl(input, CancelWire(ticket, "sequence_exhausted"));
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.Equal(1L, input.CurrentKeyboardEpoch);
        Assert.False(input.Heartbeat());
        Assert.False(input.TryTakeOutput(out _));
    }

    [Fact]
    public void EndpointIncarnationCeilingCannotWrapOrKeepAnOldGestureLive()
    {
        var input = GrantGame();
        const string endpoint = SessionInputAuthority.WorldEndpoint;
        Assert.True(input.RegisterObservedInstance(endpoint, long.MaxValue - 1));
        long finalInstance = input.NextInstanceGeneration(endpoint);
        Assert.Equal(long.MaxValue, finalInstance);
        Assert.True(input.TryBeginPointer(endpoint, finalInstance, 1, Point.Empty, "target", out var old));
        Assert.Equal(0L, input.NextInstanceGeneration(endpoint));
        Assert.False(input.ValidatePointerCommit(old, "target"));
        Assert.False(input.TryBeginPointer(endpoint, finalInstance, 1, Point.Empty, "target", out _));
        var ticket = RequireCancel(input.LastAppliedCancel);
        AssertControl(input, CancelWire(ticket, "sequence_exhausted"));
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.Equal(1L, input.CurrentKeyboardEpoch);
    }

    [Fact]
    public void CancelTicketCeilingSettlesTheLastGrantWithoutReusingATicket()
    {
        var input = GrantGame();
        var inbound = new InputCancel(input.CurrentSessionId, InitialConnection, "Game", 1,
            int.MaxValue - 1, "AS2", InitialConnection);
        string packet = CancelWire(inbound, "peer_cancel");
        Assert.True(input.Receive(InitialConnection, packet));
        AssertControl(input, packet);
        Assert.True(input.Receive(InitialConnection, CancelledWire(inbound)));
        AssertControl(input, CancelledWire(inbound));
        TakeBatch(input);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
        var last = RequireCancel(input.Cancel("final_ticket"));
        Assert.Equal(int.MaxValue, last.Ticket);
        AssertControl(input, CancelWire(last, "final_ticket"));
        Assert.True(input.Receive(InitialConnection, CancelledWire(last)));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
        Assert.False(input.TryTakeOutput(out _));
    }

    [Fact]
    public void RebindRejectsOldConnectionAndSessionBeforeAcceptingNewFrames()
    {
        var input = GrantGame();
        var previous = ParseCombo(ComboWire(input, 1));
        var previousCapability = Capability(input, InitialConnection);
        input.Disconnect(InitialConnection);
        input.Connect(InitialConnection + 1);
        AssertControl(input, $"I1|Bind|{input.CurrentSessionId}|2|15|1|64");
        Assert.False(input.Receive(InitialConnection, previousCapability));
        Assert.False(input.Receive(InitialConnection + 1, previousCapability));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.True(input.Receive(InitialConnection + 1, Capability(input, InitialConnection + 1)));
        TakeBatch(input);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
        Assert.False(input.BeginCombo(previous, InitialConnection + 1));
        var fresh = ParseCombo(ComboWire(input, 1));
        var newSession = GrantGame();
        Assert.False(newSession.BeginCombo(previous, InitialConnection));
        Assert.True(input.BeginCombo(fresh, InitialConnection + 1));
    }

    [Fact]
    public void LatchCannotAdvanceToAnUnissuedBatchOrReplayAnOldFrame()
    {
        var input = GrantGame();
        Assert.True(input.Heartbeat());
        var batch = TakeBatch(input);
        string unissued = $"I1|Latch|{batch[2]}|{batch[3]}|{batch[4]}|3|2|2";
        Assert.Equal("2", batch[5]);
        Assert.False(input.Receive(InitialConnection, unissued));
        Assert.False(input.Receive(InitialConnection, Latch(batch, 1)));
        Assert.Equal(1, input.LastLatchedFrameSeq);
        Assert.True(input.Receive(InitialConnection, Latch(batch, 2)));
        Assert.False(input.Receive(InitialConnection, Latch(batch, 2)));
        Assert.False(input.Receive(InitialConnection, $"I1|Latch|{batch[2]}|{batch[3]}|{batch[4]}|1|3|3"));
        Assert.Equal(2, input.LastLatchedFrameSeq);
        Assert.True(input.IsGameKeyboardAdmitted);
    }

    // G33: geometry invalidates the pinned world gesture in isolation.
    [Fact]
    public void GeometryChangeInvalidatesOnlyTheOldWorldGestureWithoutRekeying()
    {
        var input = GrantGame();
        Assert.True(input.ObserveKey(ActionVk, true));
        AssertEdges(input, (ActionVk, true));
        long keyboardEpoch = input.CurrentKeyboardEpoch;
        long geometry = input.CurrentGeometryVersion;
        string bitmap = input.AdmittedHex;
        var point = new Point(20, 25);
        const string world = SessionInputAuthority.WorldEndpoint;
        long worldInstance = input.NextInstanceGeneration(world);
        var invalidated = new List<long>();
        input.GestureInvalidated += invalidated.Add;
        Assert.True(input.TryBeginPointer(world, worldInstance, 1, point, "door.before", out var old));
        Assert.True(input.ValidatePointerCommit(old, "door.before"));

        input.ChangeWorldGeometry();
        Assert.False(input.ValidatePointerCommit(old, "door.before"));
        Assert.Equal(old.GestureId, Assert.Single(invalidated));
        Assert.Equal(geometry + 1, input.CurrentGeometryVersion);
        Assert.Equal(keyboardEpoch, input.CurrentKeyboardEpoch);
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.Equal(bitmap, input.AdmittedHex);
        Assert.False(input.TryTakeOutput(out _));

        Assert.True(input.TryBeginPointer(world, worldInstance, 1, point, "door.after", out var fresh));
        Assert.Equal(input.CurrentGeometryVersion, fresh.GeometryVersion);
        Assert.True(fresh.GestureId > old.GestureId);
        Assert.True(input.ValidatePointerCommit(fresh, "door.after"));
        Assert.False(input.ValidatePointerCommit(old, "door.after"));
    }

    // G34: use the normal queue writer path; no probe bypasses capacity.
    [Fact]
    public void QueueOverflowUsesDedicatedCancelControlSlotBeforeAnyData()
    {
        var input = GrantGame();
        Assert.Equal(64, SessionInputAuthority.DataCapacity);
        for (int i = 0; i < SessionInputAuthority.DataCapacity; i++)
            Assert.True(input.Heartbeat());
        Assert.Equal(64, input.PendingData);
        Assert.False(input.TryTakeOutput(out _, controlOnly: true));
        Assert.False(input.Heartbeat());
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.Equal(64, input.PendingDataAtCancel);
        Assert.Equal(0, input.PendingData);
        var ticket = RequireCancel(input.LastAppliedCancel);
        AssertControl(input, CancelWire(ticket, "data_exhausted"));
        Assert.False(input.TryTakeOutput(out _));
        Assert.True(input.IsWaiting(ticket, InputParticipant.AS2));
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.True(input.IsGameKeyboardAdmitted);
    }

    [Fact]
    public async Task FailedWriteRevokesButOnlyCurrentDisconnectRetiresSocketParticipant()
    {
        var input = GrantGame();
        Assert.True(input.BeginCombo(ParseCombo(ComboWire(input, 1)), InitialConnection));
        var attemptedBatch = new TaskCompletionSource<InputWireRecord>(TaskCreationOptions.RunContinuationsAsynchronously);
        var attemptedCancel = new TaskCompletionSource<InputWireRecord>(TaskCreationOptions.RunContinuationsAsynchronously);
        input.AttachWriter((generation, payload) =>
        {
            var record = new InputWireRecord(generation, payload);
            if (payload.StartsWith("I1|Cancel|", StringComparison.Ordinal))
            {
                attemptedCancel.TrySetResult(record);
                return true;
            }

            attemptedBatch.TrySetResult(record);
            return false;
        });
        Assert.True(input.ObserveKey(ActionVk, true));
        var timeout = TimeSpan.FromSeconds(10);
        var batch = await attemptedBatch.Task.WaitAsync(timeout);
        var cancel = await attemptedCancel.Task.WaitAsync(timeout);
        Assert.StartsWith("I1|InputBatch|", batch.Payload);
        var ticket = RequireCancel(input.LastAppliedCancel);
        Assert.Equal(InitialConnection, cancel.Connection);
        Assert.Equal(CancelWire(ticket, "transport_write"), cancel.Payload);
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.True(input.IsWaiting(ticket, InputParticipant.AS2));

        input.Disconnect(InitialConnection + 1);
        Assert.True(input.IsWaiting(ticket, InputParticipant.AS2));
        input.Disconnect(InitialConnection);
        Assert.False(input.IsWaiting(ticket, InputParticipant.AS2));
        Assert.True(input.IsWaiting(ticket, InputParticipant.V8));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.True(input.Acknowledge(ticket, InputParticipant.V8));
    }

    // G35: a local cancel never becomes an inbound replay record merely by
    // settling. An exact peer-originated replay may only repeat its receipt.
    [Fact]
    public void LateLocalCancelAndReusedTicketCannotRevokeEpochTwo()
    {
        var input = GrantGame();
        var ticket = RequireCancel(input.Cancel("modal_open"));
        AssertControl(input, CancelWire(ticket, "modal_open"));
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        TakeBatch(input);
        Assert.True(input.ObserveKey(ActionVk, true));
        AssertEdges(input, (ActionVk, true));
        string bitmap = input.AdmittedHex;

        Assert.False(input.Receive(InitialConnection, CancelWire(ticket, "late")));
        Assert.False(input.Receive(InitialConnection, CancelWire(ticket with { Ticket = ticket.Ticket + 1 }, "late")));
        Assert.False(input.Receive(InitialConnection, CancelWire(ticket with { Epoch = 2 }, "reused_ticket")));
        Assert.Equal(1, input.AppliedCancelCount);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.Equal(bitmap, input.AdmittedHex);
        Assert.False(input.TryTakeOutput(out _));
    }

    [Fact]
    public void ExactSettledInboundCancelReplayOnlyReturnsTheOriginalReceipt()
    {
        var input = GrantGame();
        var ticket = new InputCancel(input.CurrentSessionId, InitialConnection, "Game", 1, 7, "AS2", InitialConnection);
        string packet = CancelWire(ticket, "peer_cancel");
        Assert.True(input.Receive(InitialConnection, packet));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.Equal(ticket, RequireCancel(input.LastAppliedCancel));
        AssertControl(input, packet);
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        AssertControl(input, CancelledWire(ticket));
        TakeBatch(input);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);

        Assert.False(input.Receive(InitialConnection, CancelWire(ticket with { Incarnation = 2 }, "peer_cancel")));
        Assert.False(input.TryTakeOutput(out _, controlOnly: true));
        Assert.True(input.Receive(InitialConnection, packet));
        AssertControl(input, CancelledWire(ticket));
        Assert.False(input.TryTakeOutput(out _));
        Assert.Equal(1, input.AppliedCancelCount);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
        Assert.True(input.IsGameKeyboardAdmitted);
    }

    // G36: isolate one identity/settlement mutation per fixture.
    [Theory]
    [InlineData(2, "00000000000000000000000000000000")]
    [InlineData(3, "2")]
    [InlineData(4, "Pointer")]
    [InlineData(5, "2")]
    [InlineData(6, "2")]
    [InlineData(7, "V8")]
    [InlineData(8, "2")]
    [InlineData(9, "0")]
    [InlineData(10, "0")]
    public void ForgedCancelledCannotSettleAnyOfTheFrozenParticipants(int field, string replacement)
    {
        var input = GrantGame();
        input.AttachNative(() => () => false);
        Assert.True(input.BeginCombo(ParseCombo(ComboWire(input, 1)), InitialConnection));
        var ticket = RequireCancel(input.Cancel("modal_open"));
        AssertControl(input, CancelWire(ticket, "modal_open"));
        var fields = CancelledWire(ticket).Split('|');
        Assert.NotEqual(fields[field], replacement);
        fields[field] = replacement;

        Assert.False(input.Receive(InitialConnection, string.Join('|', fields)));
        Assert.True(input.IsWaiting(ticket, InputParticipant.AS2));
        Assert.True(input.IsWaiting(ticket, InputParticipant.V8));
        Assert.True(input.IsWaiting(ticket, InputParticipant.NativeBridge));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.True(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.False(input.Receive(InitialConnection, CancelledWire(ticket)));
        Assert.False(input.IsGameKeyboardAdmitted);
        input.AttachNative(null);
        Assert.True(input.IsWaiting(ticket, InputParticipant.NativeBridge));
        Assert.False(input.Acknowledge(ticket, InputParticipant.V8 | InputParticipant.NativeBridge));
        Assert.True(input.Acknowledge(ticket, InputParticipant.V8));
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.True(input.Acknowledge(ticket, InputParticipant.NativeBridge));
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.Equal(2L, input.CurrentKeyboardEpoch);
    }

    // G37: each candidate changes one field of an otherwise valid packet
    // where possible, followed by a positive control through the same receiver.
    [Theory]
    [InlineData("I2|Bind|{session}|1|15|1|64")]
    [InlineData("I2|Capability|{session}|1|15|1|64")]
    [InlineData("I1|Capability|{session}|1|14|1|64")]
    [InlineData("I1|Capability|{session}|1|015|1|64")]
    [InlineData("I1|Capability|{session}|1|15|2|64")]
    [InlineData("I1|Capability|{session}|1|15|1|65")]
    [InlineData("I1|Capability|{session}|1|15|1")]
    [InlineData("I1|Capability|{session}|1|15|1|64|extra")]
    [InlineData("I1|Capability|{session}|01|15|1|64")]
    [InlineData("I1|Capability|{session}|-5|15|1|64")]
    [InlineData("I1|Capability|{session}|2147483648|15|1|64")]
    [InlineData("I1|Capability|{session}|NaN|15|1|64")]
    [InlineData("I1|Capability|{session}|1|15|1|64\0")]
    [InlineData("I1|Capability|{session}|1|15|1|64\n")]
    [InlineData("I1|Capability|{session}|1|15|1|６４")]
    public void MalformedCapabilityCannotBindOrChangeAnActiveGrant(string mutation)
    {
        var input = AwaitCapability();
        string packet = mutation.Replace("{session}", input.CurrentSessionId, StringComparison.Ordinal);
        Assert.False(input.Receive(InitialConnection, packet));
        Assert.False(input.Bound);
        Assert.False(input.IsGameKeyboardAdmitted);
        Assert.False(input.TryTakeOutput(out _));
        Assert.True(input.Receive(InitialConnection, Capability(input, InitialConnection)));
        TakeBatch(input);
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.False(input.Receive(InitialConnection, packet));
        Assert.False(input.Receive(InitialConnection, Capability(input, InitialConnection)));
        Assert.True(input.Bound);
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.Equal(1L, input.CurrentKeyboardEpoch);
        Assert.False(input.TryTakeOutput(out _));
    }

    [Theory]
    [InlineData(0, "I2")]
    [InlineData(2, "01")]
    [InlineData(3, "-5")]
    [InlineData(4, "2147483648")]
    [InlineData(4, "")]
    [InlineData(5, "NaN")]
    [InlineData(6, "3")]
    [InlineData(9, "256")]
    [InlineData(10, "2")]
    [InlineData(11, "-0")]
    [InlineData(13, "-\0")]
    [InlineData(13, "-\n")]
    [InlineData(13, "é")]
    public void MalformedComboHeaderOrWireTextCannotProduceAFrame(int field, string mutation)
    {
        var input = GrantGame();
        string good = ComboWire(input, 1);
        var fields = good.Split('|');
        fields[field] = mutation;
        Assert.False(VersionedComboFrame.TryParse(string.Join('|', fields), out _));
        Assert.False(VersionedComboFrame.TryParse(good[..good.LastIndexOf('|')], out _));
        Assert.False(VersionedComboFrame.TryParse(good + "|extra", out _));
        Assert.True(input.BeginCombo(ParseCombo(good), InitialConnection));
    }

    [Theory]
    [InlineData(2, "1,1,D")]
    [InlineData(1, "1,1,D;2,1,U")]
    [InlineData(0, "1,1,D")]
    [InlineData(1, "-")]
    [InlineData(1, "1,3,D")]
    [InlineData(1, "1,0,D")]
    [InlineData(1, "1,256,D")]
    [InlineData(1, "0,1,D")]
    [InlineData(1, "01,1,D")]
    [InlineData(1, "-5,1,D")]
    [InlineData(1, "2147483648,1,D")]
    [InlineData(1, "1,1")]
    [InlineData(1, "1,1,X")]
    [InlineData(2, "2,1,D;1,1,U")]
    [InlineData(2, "1,1,D;1,1,U")]
    [InlineData(2, "1,128,D;1,1,D")]
    public void ComboAtomsRejectWrongCardinalityActionBitsAndOrder(int count, string atoms)
    {
        var input = GrantGame();
        Assert.False(VersionedComboFrame.TryParse(ComboWire(input, 1, atomCount: count, atoms: atoms), out _));
    }

    [Fact]
    public void ComboFrameAcceptsSignedCeilingAndSixtyFourAtomsButRejectsSixtyFive()
    {
        var input = GrantGame();
        var atoms = Enumerable.Range(1, 64).Select(edge => $"{edge},1,{(edge % 2 == 1 ? 'D' : 'U')}");
        string atLimit = string.Join(";", atoms);
        var frame = ParseCombo(ComboWire(input, int.MaxValue, atomCount: 64, atoms: atLimit));
        Assert.Equal(int.MaxValue, frame.Frame);
        Assert.Equal(atLimit, frame.Atoms);
        Assert.False(VersionedComboFrame.TryParse(
            ComboWire(input, int.MaxValue, atomCount: 65, atoms: atLimit + ";65,1,D"), out _));
    }

    [Theory]
    [InlineData("1|7|duplicate||[]", "combo_result_invalid")]
    [InlineData("3|7|skipped||[]", "combo_result_invalid")]
    [InlineData("0|7|zero||[]", "combo_result_invalid")]
    [InlineData("2|0|||[]", "combo_result_invalid")]
    [InlineData("02|7|name||[]", "combo_result_invalid")]
    [InlineData("2147483648|7|name||[]", "combo_result_invalid")]
    [InlineData("2|-5|name||[]", "combo_result_invalid")]
    [InlineData("2|7|name|[]", "combo_result_invalid")]
    [InlineData("2|7|bad%ZZ||[]", "combo_result_invalid")]
    [InlineData("2|7|name||{}", "combo_result_invalid")]
    [InlineData("2|7|name||[", "combo_result_invalid")]
    [InlineData("2|7|bad\0name||[]", "combo_result_overflow")]
    [InlineData("2|7|bad\nname||[]", "combo_result_overflow")]
    [InlineData("2|7|é||[]", "combo_result_overflow")]
    public void InvalidComboCompletionRevokesGrantAndPublishesOnlyCancel(string result, string reason)
    {
        var input = GrantGame();
        var first = ParseCombo(ComboWire(input, 1));
        Assert.True(input.BeginCombo(first, InitialConnection));
        Assert.True(input.CompleteCombo(first, "1|7|first||[]"));
        Assert.True(input.TryTakeOutput(out var positive));
        Assert.Equal($"I1|K|{first.Origin}|1|7|first||[]", positive.Payload);
        var next = ParseCombo(ComboWire(input, 2));
        Assert.True(input.BeginCombo(next, InitialConnection));

        Assert.False(input.CompleteCombo(next, result));
        Assert.False(input.IsGameKeyboardAdmitted);
        var ticket = RequireCancel(input.LastAppliedCancel);
        AssertControl(input, CancelWire(ticket, reason));
        Assert.False(input.TryTakeOutput(out _));
    }

    [Fact]
    public void WireLimitRejectsOverlongCapabilityComboFrameAndResultWithoutTruncating()
    {
        Assert.True(SessionInputAuthority.WireText(new string('x', 4096)));
        Assert.False(SessionInputAuthority.WireText(new string('x', 4097)));
        var input = AwaitCapability();
        string capability = Capability(input, InitialConnection);
        Assert.False(input.Receive(InitialConnection, capability.PadRight(4097, 'x')));
        Assert.False(input.Bound);
        Assert.True(input.Receive(InitialConnection, capability));
        TakeBatch(input);
        string valid = ComboWire(input, 1);
        Assert.False(VersionedComboFrame.TryParse(valid.PadRight(4097, 'x'), out _));

        var first = ParseCombo(valid);
        Assert.True(input.BeginCombo(first, InitialConnection));
        Assert.True(input.CompleteCombo(first, SizedComboResult(first, 1, 4096)));
        Assert.True(input.TryTakeOutput(out var atLimit));
        Assert.Equal(4096, atLimit.Payload.Length);
        var next = ParseCombo(ComboWire(input, 2));
        Assert.True(input.BeginCombo(next, InitialConnection));
        Assert.False(input.CompleteCombo(next, SizedComboResult(next, 2, 4097)));
        Assert.False(input.IsGameKeyboardAdmitted);
        AssertControl(input, CancelWire(RequireCancel(input.LastAppliedCancel), "combo_result_overflow"));
        Assert.False(input.TryTakeOutput(out _));
    }

    private static SessionInputAuthority AwaitCapability()
    {
        var input = new SessionInputAuthority(PassiveFlashInputMode.Disabled);
        input.SetForeground(true);
        input.SetBusinessEligible(true, "test_ready");
        input.Connect(InitialConnection);
        AssertControl(input, $"I1|Bind|{input.CurrentSessionId}|{InitialConnection}|15|1|64");
        return input;
    }

    private static SessionInputAuthority GrantGame()
    {
        var input = AwaitCapability();
        Assert.True(input.Receive(InitialConnection, Capability(input, InitialConnection)));
        Assert.True(input.IsGameKeyboardAdmitted);
        Assert.Equal(1L, input.CurrentKeyboardEpoch);
        var batch = TakeBatch(input);
        Assert.Empty(BatchEdges(batch));
        Assert.True(input.Receive(InitialConnection, Latch(batch, 1)));
        return input;
    }

    private static string Capability(SessionInputAuthority input, int connection) =>
        $"I1|Capability|{input.CurrentSessionId}|{connection}|15|1|64";

    private static string CancelWire(InputCancel ticket, string reason) => $"I1|Cancel|{ticket.Fields}|{reason}";

    private static string CancelledWire(InputCancel ticket) => $"I1|Cancelled|{ticket.Fields}|1|1";

    private static InputCancel RequireCancel(InputCancel? ticket)
    {
        Assert.True(ticket.HasValue);
        return ticket.Value;
    }

    private static void AssertControl(SessionInputAuthority input, string expected)
    {
        Assert.True(input.TryTakeOutput(out var record, controlOnly: true));
        Assert.Equal(input.ConnectionIncarnation, record.Connection);
        Assert.Equal(expected, record.Payload);
    }

    private static string[] TakeBatch(SessionInputAuthority input)
    {
        Assert.True(input.TryTakeOutput(out var record));
        Assert.Equal(input.ConnectionIncarnation, record.Connection);
        var fields = record.Payload.Split('|');
        Assert.Equal(11, fields.Length);
        Assert.Equal("I1", fields[0]);
        Assert.Equal("InputBatch", fields[1]);
        Assert.Equal(input.CurrentSessionId, fields[2]);
        Assert.Equal(64, fields[8].Length);
        return fields;
    }

    private static string Latch(string[] batch, int frame) =>
        $"I1|Latch|{batch[2]}|{batch[3]}|{batch[4]}|{batch[5]}|{frame}|{frame}";

    private static (int Sequence, int Vk, bool Down)[] BatchEdges(string[] batch)
    {
        var edges = batch[10] == "-" ? Array.Empty<string>() : batch[10].Split(';');
        Assert.Equal(int.Parse(batch[9], CultureInfo.InvariantCulture), edges.Length);
        return edges.Select(edge =>
        {
            var fields = edge.Split(',');
            Assert.Equal(3, fields.Length);
            Assert.True(fields[2] is "D" or "U");
            return (int.Parse(fields[0], CultureInfo.InvariantCulture),
                int.Parse(fields[1], CultureInfo.InvariantCulture), fields[2] == "D");
        }).ToArray();
    }

    private static void AssertEdges(SessionInputAuthority input, params (int Vk, bool Down)[] expected) =>
        Assert.Equal(expected, BatchEdges(TakeBatch(input)).Select(edge => (edge.Vk, edge.Down)));

    private static bool BitmapContains(string bitmap, int vk)
    {
        uint word = uint.Parse(bitmap.AsSpan((vk >> 5) * 8, 8), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return (word & (1u << (vk & 31))) != 0;
    }

    private static string ComboWire(SessionInputAuthority input, int frame, int actor = 1, int config = 1,
        int mask = 0, int facing = 1, int direction = 0, int atomCount = 0, string atoms = "-") =>
        $"I1|{input.CurrentSessionId}|{input.ConnectionIncarnation}|{input.CurrentKeyboardEpoch}|{frame}|{actor}|0|1|{config}|{mask}|{facing}|{direction}|{atomCount}|{atoms}";

    private static VersionedComboFrame ParseCombo(string wire)
    {
        Assert.True(VersionedComboFrame.TryParse(wire, out var frame), wire);
        return frame;
    }

    private static string SizedComboResult(VersionedComboFrame frame, int sequence, int packetLength)
    {
        string prefix = $"I1|K|{frame.Origin}|{sequence}|7|";
        const string suffix = "||[]";
        return $"{sequence}|7|{new string('x', packetLength - prefix.Length - suffix.Length)}{suffix}";
    }
}
