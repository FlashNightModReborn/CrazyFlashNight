using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class PanelFocusRestoreGateTests
    {
        [Fact]
        public void TryQueue_RequiresLiveForegroundTakingPanel()
        {
            PanelFocusRestoreGate gate = new PanelFocusRestoreGate();
            gate.BeginPanel();

            int ignored;
            Assert.False(gate.TryQueue(false, true, false, 1000, out ignored));
            Assert.False(gate.TryQueue(true, false, false, 1000, out ignored));
            Assert.False(gate.TryQueue(true, true, true, 1000, out ignored));
            Assert.True(gate.TryQueue(true, true, false, 1000, out ignored));
        }

        [Fact]
        public void PendingCallback_IsBoundToExactPanelGeneration()
        {
            PanelFocusRestoreGate gate = new PanelFocusRestoreGate();
            int firstGeneration = gate.BeginPanel();
            int queuedGeneration;
            Assert.True(gate.TryQueue(true, true, false, 1000, out queuedGeneration));
            Assert.Equal(firstGeneration, queuedGeneration);

            int replacementGeneration = gate.BeginPanel();
            Assert.NotEqual(firstGeneration, replacementGeneration);
            Assert.False(gate.TryBeginExecution(firstGeneration, true, true, false,
                true, 1001));
            Assert.True(gate.TryQueue(true, true, false, 1001, out queuedGeneration));
            Assert.Equal(replacementGeneration, queuedGeneration);
            gate.Complete(firstGeneration);
            Assert.True(gate.TryBeginExecution(replacementGeneration, true, true, false,
                true, 1001));
            Assert.True(gate.TryCommitExecution(replacementGeneration, true, true, false,
                1001));
        }

        [Fact]
        public void ClosedOrDisposedPanel_CannotExecuteQueuedRestore()
        {
            PanelFocusRestoreGate gate = new PanelFocusRestoreGate();
            gate.BeginPanel();
            int generation;
            Assert.True(gate.TryQueue(true, true, false, 1000, out generation));

            gate.EndPanel();
            Assert.False(gate.TryBeginExecution(generation, true, false, false,
                true, 1001));

            gate.BeginPanel();
            Assert.True(gate.TryQueue(true, true, false, 1002, out generation));
            Assert.False(gate.TryBeginExecution(generation, true, true, true,
                true, 1002));
        }

        [Fact]
        public void ExecutionRevalidation_RejectsCloseOrReplacementDuringActivation()
        {
            PanelFocusRestoreGate gate = new PanelFocusRestoreGate();
            gate.BeginPanel();
            int generation;
            Assert.True(gate.TryQueue(true, true, false, 1000, out generation));
            Assert.True(gate.TryBeginExecution(generation, true, true, false,
                true, 1000));

            gate.EndPanel();
            Assert.False(gate.TryCommitExecution(generation, true, false, false, 1001));

            int replacementGeneration = gate.BeginPanel();
            Assert.NotEqual(generation, replacementGeneration);
            Assert.False(gate.TryCommitExecution(generation, true, true, false, 1001));
        }

        [Fact]
        public void ExternalForeground_DoesNotConsumeDebounceWindow()
        {
            PanelFocusRestoreGate gate = new PanelFocusRestoreGate();
            gate.BeginPanel();
            int generation;
            Assert.True(gate.TryQueue(true, true, false, 1000, out generation));
            Assert.False(gate.TryBeginExecution(generation, true, true, false,
                false, 1001));
            gate.Complete(generation);

            Assert.True(gate.TryQueue(true, true, false, 1002, out generation));
            Assert.True(gate.TryBeginExecution(generation, true, true, false,
                true, 1002));
            Assert.True(gate.TryCommitExecution(generation, true, true, false, 1002));
        }

        [Fact]
        public void FailureBeforeSuccessfulMoveFocus_RemainsImmediatelyRetryable()
        {
            PanelFocusRestoreGate gate = new PanelFocusRestoreGate();
            gate.BeginPanel();
            int generation;
            Assert.True(gate.TryQueue(true, true, false, 1000, out generation));
            Assert.True(gate.TryBeginExecution(generation, true, true, false,
                true, 1000));

            // The host commits only after MoveFocus succeeds.  A foreground race or MoveFocus
            // exception completes without consuming the debounce window.
            gate.Complete(generation);
            Assert.True(gate.TryQueue(true, true, false, 1001, out generation));
            Assert.True(gate.TryBeginExecution(generation, true, true, false,
                true, 1001));
            Assert.True(gate.TryCommitExecution(generation, true, true, false, 1001));
        }

        [Fact]
        public void SameGeneration_IsSingleFlightAndDebounced()
        {
            PanelFocusRestoreGate gate = new PanelFocusRestoreGate();
            gate.BeginPanel();
            int generation;
            int ignored;
            Assert.True(gate.TryQueue(true, true, false, 1000, out generation));
            Assert.False(gate.TryQueue(true, true, false, 1000, out ignored));
            Assert.True(gate.TryBeginExecution(generation, true, true, false,
                true, 1000));
            Assert.True(gate.TryCommitExecution(generation, true, true, false, 1000));
            gate.Complete(generation);

            Assert.False(gate.TryQueue(true, true, false,
                1000 + PanelFocusRestoreGate.DebounceMilliseconds - 1, out ignored));
            Assert.True(gate.TryQueue(true, true, false,
                1000 + PanelFocusRestoreGate.DebounceMilliseconds, out generation));
        }

        [Fact]
        public void NewPanelGeneration_BypassesPreviousPanelDebounce()
        {
            PanelFocusRestoreGate gate = new PanelFocusRestoreGate();
            gate.BeginPanel();
            int generation;
            Assert.True(gate.TryQueue(true, true, false, 1000, out generation));
            Assert.True(gate.TryBeginExecution(generation, true, true, false,
                true, 1000));
            Assert.True(gate.TryCommitExecution(generation, true, true, false, 1000));
            gate.Complete(generation);

            int replacementGeneration = gate.BeginPanel();
            Assert.True(gate.TryQueue(true, true, false, 1001, out generation));
            Assert.Equal(replacementGeneration, generation);
            Assert.True(gate.TryBeginExecution(generation, true, true, false,
                true, 1001));
            Assert.True(gate.TryCommitExecution(generation, true, true, false, 1001));
        }
    }
}
