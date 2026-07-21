using System;
using System.Collections.Generic;
using Xunit;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class DevLockboxS0CoordinatorTests
    {
        private const long Epoch = 17;

        private sealed class IdentitySequence
        {
            private int _flow;
            private int _request;
            private int _panel;

            public int Calls { get; private set; }

            public string NextFlow()
            {
                Calls++;
                return "flow." + (++_flow);
            }

            public string NextRequest()
            {
                Calls++;
                return "request." + (++_request);
            }

            public string NextPanel()
            {
                Calls++;
                return "panel.lockbox." + (++_panel);
            }
        }

        private static DevLockboxS0Coordinator NewCoordinator(out IdentitySequence ids,
            long epoch = Epoch)
        {
            ids = new IdentitySequence();
            return new DevLockboxS0Coordinator(epoch,
                ids.NextFlow, ids.NextRequest, ids.NextPanel);
        }

        private static DevLockboxS0Coordinator.BeginRequest ValidRequest(long epoch = Epoch)
        {
            return new DevLockboxS0Coordinator.BeginRequest
            {
                IsDevRepository = true,
                EnvironmentGateValue = "1",
                Origin = DevLockboxS0Coordinator.RouteOrigin.TrustedAs2Socket,
                Source = "as2-chest-s0",
                Fixture = "insurance-safe-s0-v1",
                IsPanelOrchestrationIdle = true,
                WebDocumentEpoch = epoch
            };
        }

        private static DevLockboxS0Coordinator.AttemptIdentity Begin(
            DevLockboxS0Coordinator coordinator,
            DevLockboxS0Coordinator.BeginRequest request = null)
        {
            DevLockboxS0Coordinator.AttemptIdentity identity;
            DevLockboxS0Coordinator.BeginRejection rejection;
            Assert.True(coordinator.TryBegin(request ?? ValidRequest(), out identity, out rejection));
            Assert.Equal(DevLockboxS0Coordinator.BeginRejection.None, rejection);
            Assert.NotNull(identity);
            return identity;
        }

        private static DevLockboxS0Coordinator.AttemptIdentity BeginAndBind(
            DevLockboxS0Coordinator coordinator,
            DevLockboxS0Coordinator.BeginRequest request = null)
        {
            DevLockboxS0Coordinator.AttemptIdentity identity = Begin(coordinator, request);
            Assert.True(coordinator.CanExecuteQueuedOpen(identity.RequestToken));
            Assert.True(coordinator.MarkQueuedOpenExecuting(identity.RequestToken));
            Assert.True(coordinator.TryAcknowledgeBind(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            return identity;
        }

        private static void AssertRejected(Action<DevLockboxS0Coordinator.BeginRequest> mutate,
            DevLockboxS0Coordinator.BeginRejection expected)
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.BeginRequest request = ValidRequest();
            mutate(request);
            DevLockboxS0Coordinator.AttemptIdentity identity;
            DevLockboxS0Coordinator.BeginRejection rejection;
            Assert.False(coordinator.TryBegin(request, out identity, out rejection));
            Assert.Null(identity);
            Assert.Equal(expected, rejection);
            Assert.Equal(0, ids.Calls);
            Assert.Equal(DevLockboxS0Coordinator.FlowState.Idle, coordinator.State);
            Assert.False(coordinator.HoldsGlobalPause);
        }

        [Fact]
        public void H01_StrictDevRouteGateRejectsWithoutQueueing()
        {
            AssertRejected(r => r.IsDevRepository = false,
                DevLockboxS0Coordinator.BeginRejection.NotDevRepository);
            AssertRejected(r => r.EnvironmentGateValue = "true",
                DevLockboxS0Coordinator.BeginRejection.EnvironmentGateClosed);
            AssertRejected(r => r.EnvironmentGateValue = "01",
                DevLockboxS0Coordinator.BeginRejection.EnvironmentGateClosed);
            AssertRejected(r => r.Source = "as2-chest",
                DevLockboxS0Coordinator.BeginRejection.SourceMismatch);
            AssertRejected(r => r.Fixture = "insurance-safe-s0-v2",
                DevLockboxS0Coordinator.BeginRejection.FixtureMismatch);
        }

        [Fact]
        public void H02_QueueAcceptanceThenBindTimeoutIsUnknownAndKeepsIdentityPauseAndExclusivity()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = Begin(coordinator);

            Assert.Equal(DevLockboxS0Coordinator.FlowState.OpenQueued, coordinator.State);
            Assert.True(coordinator.MarkQueuedOpenExecuting(identity.RequestToken));
            Assert.True(coordinator.MarkBindTimeout(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));

            Assert.Equal(DevLockboxS0Coordinator.FlowState.OpenBindUnknown, coordinator.State);
            Assert.Same(identity, coordinator.ActiveIdentity);
            Assert.True(coordinator.HoldsGlobalPause);
            Assert.False(coordinator.CanReleaseGlobalPause);

            DevLockboxS0Coordinator.AttemptIdentity second;
            DevLockboxS0Coordinator.BeginRejection rejection;
            Assert.False(coordinator.TryBegin(ValidRequest(), out second, out rejection));
            Assert.Equal(DevLockboxS0Coordinator.BeginRejection.Busy, rejection);
            Assert.Equal(3, ids.Calls);
        }

        [Fact]
        public void H03_OnlyExactInitialAckOrExactUnknownStateQueryCanBind()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = Begin(coordinator);
            Assert.True(coordinator.MarkQueuedOpenExecuting(identity.RequestToken));

            Assert.False(coordinator.TryAcknowledgeBind("flow.stale",
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.False(coordinator.TryAcknowledgeBind(identity.FlowHandle,
                "panel.lockbox.stale", identity.WebDocumentEpoch));
            Assert.False(coordinator.TryAcknowledgeBind(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch + 1));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.OpenQueued, coordinator.State);

            Assert.True(coordinator.MarkBindTimeout(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.False(coordinator.ApplyExactBindQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch,
                (DevLockboxS0Coordinator.BindQueryConclusion)999));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.OpenBindUnknown, coordinator.State);

            Assert.False(coordinator.TryAcknowledgeBind(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.OpenBindUnknown, coordinator.State);
            Assert.True(coordinator.ApplyExactBindQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch,
                DevLockboxS0Coordinator.BindQueryConclusion.Bound));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.PanelBound, coordinator.State);
        }

        [Fact]
        public void TrackedOpenNoPostProof_ClearsOnlyAnExactAlreadyTerminalDomCandidate()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = Begin(coordinator);
            Assert.True(coordinator.MarkQueuedOpenExecuting(identity.RequestToken));
            Assert.True(coordinator.ConfirmAuthorityExpired(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.False(coordinator.CanReleaseGlobalPause);

            Assert.False(coordinator.ConfirmTrackedOpenDidNotReachDom("flow.stale",
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.False(coordinator.ConfirmTrackedOpenDidNotReachDom(identity.FlowHandle,
                "panel.lockbox.stale", identity.WebDocumentEpoch));
            Assert.False(coordinator.CanReleaseGlobalPause);

            Assert.True(coordinator.ConfirmTrackedOpenDidNotReachDom(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.True(coordinator.CanReleaseGlobalPause);
        }

        [Fact]
        public void H04_SecondOpenIsBusyBeforeAnyNewIdentityIsAllocated()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            BeginAndBind(coordinator);
            Assert.Equal(3, ids.Calls);

            DevLockboxS0Coordinator.AttemptIdentity second;
            DevLockboxS0Coordinator.BeginRejection rejection;
            Assert.False(coordinator.TryBegin(ValidRequest(), out second, out rejection));
            Assert.Equal(DevLockboxS0Coordinator.BeginRejection.Busy, rejection);
            Assert.Null(second);
            Assert.Equal(3, ids.Calls);
        }

        [Theory]
        [InlineData(DevLockboxS0Coordinator.LimitedResult.Success)]
        [InlineData(DevLockboxS0Coordinator.LimitedResult.Cancel)]
        [InlineData(DevLockboxS0Coordinator.LimitedResult.Failure)]
        public void H05_EachExactFlowAcceptsOnlyOneLimitedResult(
            DevLockboxS0Coordinator.LimitedResult result)
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = BeginAndBind(coordinator);

            Assert.False(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1,
                (DevLockboxS0Coordinator.LimitedResult)999));
            Assert.Equal(1, DevLockboxS0Coordinator.MaximumFlowCallId);
            Assert.False(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 2, result));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.PanelBound, coordinator.State);
            Assert.Equal(0, coordinator.SubmittedFlowCallId);
            Assert.True(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, result));
            Assert.False(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, result));
            Assert.False(coordinator.TrySubmitResult(identity.FlowHandle + ".old",
                identity.PanelInstanceId, identity.WebDocumentEpoch, 2, result));
            Assert.Equal(1, coordinator.SubmittedFlowCallId);
            Assert.Equal(result, coordinator.SubmittedResult);

            bool requiresTerminal = result != DevLockboxS0Coordinator.LimitedResult.Success;
            if (requiresTerminal)
            {
                Assert.False(coordinator.TryAcknowledgeResult(identity.FlowHandle,
                    identity.PanelInstanceId, identity.WebDocumentEpoch, 1, result, 1, false));
                Assert.Equal(DevLockboxS0Coordinator.FlowState.ResultPending, coordinator.State);
            }
            Assert.True(coordinator.TryAcknowledgeResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, result, 1,
                requiresTerminal));
            Assert.False(coordinator.TryAcknowledgeResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, result, 1,
                requiresTerminal));
            Assert.Equal(requiresTerminal ? DevLockboxS0Coordinator.FlowState.KnownTerminal
                    : DevLockboxS0Coordinator.FlowState.ResultApplied,
                coordinator.State);
        }

        [Fact]
        public void H06_ResultTransportUnknownAllowsOnlyCausalQueryAndNeverReplay()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = BeginAndBind(coordinator);
            Assert.True(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1,
                DevLockboxS0Coordinator.LimitedResult.Success));

            Assert.True(coordinator.MarkResultTransportUnknown(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.ReconcileRequired, coordinator.State);
            Assert.Equal(1, coordinator.UnknownFlowCallId);
            Assert.True(coordinator.CanIssueCausalResultQuery);
            Assert.False(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1,
                DevLockboxS0Coordinator.LimitedResult.Success));
            Assert.False(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 2,
                DevLockboxS0Coordinator.LimitedResult.Success));
            Assert.True(coordinator.HoldsGlobalPause);
        }

        [Fact]
        public void H06B_ExternalResultSilenceReservesCallWithoutInventingAResultOrWrite()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = BeginAndBind(coordinator);

            Assert.False(coordinator.MarkExternalResultDeliveryUnknown("flow.stale",
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1));
            Assert.False(coordinator.MarkExternalResultDeliveryUnknown(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 2));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.PanelBound, coordinator.State);

            Assert.True(coordinator.MarkExternalResultDeliveryUnknown(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.ReconcileRequired, coordinator.State);
            Assert.Equal(1, coordinator.SubmittedFlowCallId);
            Assert.Equal(1, coordinator.UnknownFlowCallId);
            Assert.Null(coordinator.SubmittedResult);
            Assert.True(coordinator.CanIssueCausalResultQuery);
            Assert.False(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1,
                DevLockboxS0Coordinator.LimitedResult.Success));
            Assert.False(coordinator.ApplyAuthorityQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, 0,
                DevLockboxS0Coordinator.AuthorityQueryConclusion.ConfirmedNoWrite, true));
            Assert.False(coordinator.ApplyAuthorityQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, 1,
                DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedSuccess, false));
            Assert.True(coordinator.ApplyAuthorityQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, 1,
                DevLockboxS0Coordinator.AuthorityQueryConclusion.ConfirmedNoWrite, true));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.KnownTerminal, coordinator.State);
            Assert.False(coordinator.CanReleaseGlobalPause);
            Assert.True(coordinator.RecordExactCloseAck(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.True(coordinator.CanReleaseGlobalPause);
        }

        [Fact]
        public void H07_OnlyFreshAuthorityWatermarkResolvesUnknownCall()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = BeginAndBind(coordinator);
            Assert.True(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1,
                DevLockboxS0Coordinator.LimitedResult.Success));
            Assert.True(coordinator.MarkResultTransportUnknown(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1));

            Assert.False(coordinator.ApplyAuthorityQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, 0,
                DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedSuccess, false));
            Assert.False(coordinator.ApplyAuthorityQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, 1,
                DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedFailure, false));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.ReconcileRequired, coordinator.State);

            Assert.True(coordinator.ApplyAuthorityQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1, 1,
                DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedSuccess, false));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.ResultApplied, coordinator.State);
            Assert.True(coordinator.MarkSuccessAuthorityTerminal(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1));
            Assert.True(coordinator.RecordExactCloseAck(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.True(coordinator.CanReleaseGlobalPause);

            IdentitySequence cancelIds;
            DevLockboxS0Coordinator cancelCoordinator = NewCoordinator(out cancelIds);
            DevLockboxS0Coordinator.AttemptIdentity cancelIdentity = BeginAndBind(cancelCoordinator);
            Assert.True(cancelCoordinator.TrySubmitResult(cancelIdentity.FlowHandle,
                cancelIdentity.PanelInstanceId, cancelIdentity.WebDocumentEpoch, 1,
                DevLockboxS0Coordinator.LimitedResult.Cancel));
            Assert.True(cancelCoordinator.MarkResultTransportUnknown(cancelIdentity.FlowHandle,
                cancelIdentity.PanelInstanceId, cancelIdentity.WebDocumentEpoch, 1));
            Assert.False(cancelCoordinator.ApplyAuthorityQuery(cancelIdentity.FlowHandle,
                cancelIdentity.PanelInstanceId, cancelIdentity.WebDocumentEpoch, 1, 1,
                DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedCancel, false));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.ReconcileRequired,
                cancelCoordinator.State);
            Assert.True(cancelCoordinator.ApplyAuthorityQuery(cancelIdentity.FlowHandle,
                cancelIdentity.PanelInstanceId, cancelIdentity.WebDocumentEpoch, 1, 1,
                DevLockboxS0Coordinator.AuthorityQueryConclusion.AppliedCancel, true));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.KnownTerminal,
                cancelCoordinator.State);
        }

        [Fact]
        public void H08_GenericUnpauseIsBlockedUntilThisLeaseHasKnownTerminalAndNoDom()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = Begin(coordinator);
            Assert.True(coordinator.ShouldBlockGenericUnpause);
            Assert.True(coordinator.CancelQueuedOpenExact(identity.RequestToken));
            Assert.True(coordinator.ShouldBlockGenericUnpause);
            Assert.False(coordinator.CanReleaseGlobalPause);

            Assert.True(coordinator.AcknowledgeKnownRevocation(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.True(coordinator.CanReleaseGlobalPause);
            Assert.True(coordinator.TryReleaseGlobalPauseAndReset());
            Assert.False(coordinator.ShouldBlockGenericUnpause);
            Assert.False(coordinator.HoldsGlobalPause);
        }

        [Fact]
        public void H10_LostBindAckUsesExactQueryOrExactCloseWithoutNewSession()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = Begin(coordinator);
            Assert.True(coordinator.MarkQueuedOpenExecuting(identity.RequestToken));
            Assert.True(coordinator.MarkBindTimeout(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));

            Assert.True(coordinator.ApplyExactBindQuery(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch,
                DevLockboxS0Coordinator.BindQueryConclusion.Bound));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.PanelBound, coordinator.State);
            Assert.Same(identity, coordinator.ActiveIdentity);
            Assert.Equal(3, ids.Calls);

            Assert.True(coordinator.RecordExactCloseAck(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.RevokePending, coordinator.State);
            Assert.True(coordinator.AcknowledgeKnownRevocation(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.True(coordinator.TryReleaseGlobalPauseAndReset());
            Assert.Equal(3, ids.Calls);

            IdentitySequence closeIds;
            DevLockboxS0Coordinator closeCoordinator = NewCoordinator(out closeIds);
            DevLockboxS0Coordinator.AttemptIdentity closeIdentity = Begin(closeCoordinator);
            Assert.True(closeCoordinator.MarkQueuedOpenExecuting(closeIdentity.RequestToken));
            Assert.True(closeCoordinator.MarkBindTimeout(closeIdentity.FlowHandle,
                closeIdentity.PanelInstanceId, closeIdentity.WebDocumentEpoch));
            Assert.True(closeCoordinator.RecordExactCloseAck(closeIdentity.FlowHandle,
                closeIdentity.PanelInstanceId, closeIdentity.WebDocumentEpoch));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.RevokePending,
                closeCoordinator.State);
            Assert.True(closeCoordinator.AcknowledgeKnownRevocation(closeIdentity.FlowHandle,
                closeIdentity.PanelInstanceId, closeIdentity.WebDocumentEpoch));
            Assert.True(closeCoordinator.TryReleaseGlobalPauseAndReset());
            Assert.Equal(3, closeIds.Calls);
        }

        [Fact]
        public void H11_ExactQueuedCancellationPreventsLateExecution()
        {
            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = Begin(coordinator);

            Assert.False(coordinator.CancelQueuedOpenExact("request.stale"));
            Assert.True(coordinator.CanExecuteQueuedOpen(identity.RequestToken));
            Assert.True(coordinator.CancelQueuedOpenExact(identity.RequestToken));
            Assert.False(coordinator.CanExecuteQueuedOpen(identity.RequestToken));
            Assert.False(coordinator.MarkQueuedOpenExecuting(identity.RequestToken));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.RevokePending, coordinator.State);

            IdentitySequence failureIds;
            DevLockboxS0Coordinator failureCoordinator = NewCoordinator(out failureIds);
            DevLockboxS0Coordinator.AttemptIdentity failureIdentity = Begin(failureCoordinator);
            Assert.True(failureCoordinator.MarkQueuedOpenExecuting(failureIdentity.RequestToken));
            Assert.False(failureCoordinator.MarkKnownOpenFailure(failureIdentity.FlowHandle,
                failureIdentity.PanelInstanceId, failureIdentity.WebDocumentEpoch,
                (DevLockboxS0Coordinator.KnownOpenFailure)999));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.OpenQueued,
                failureCoordinator.State);
        }

        [Fact]
        public void HB01_OpaqueIdentityPartsEnforceShapeLengthAndLifetimeNonReuse()
        {
            string[] invalidParts =
            {
                string.Empty,
                " leading",
                "trailing ",
                "embedded" + (char)1 + "control",
                new string('x', DevLockboxS0Coordinator.MaximumIdentityPartLength + 1)
            };
            foreach (string invalidPart in invalidParts)
            {
                DevLockboxS0Coordinator coordinator = new DevLockboxS0Coordinator(Epoch,
                    () => invalidPart, () => "request.valid", () => "panel.valid");
                DevLockboxS0Coordinator.AttemptIdentity rejectedIdentity;
                DevLockboxS0Coordinator.BeginRejection rejection;
                Assert.False(coordinator.TryBegin(ValidRequest(), out rejectedIdentity,
                    out rejection));
                Assert.Equal(DevLockboxS0Coordinator.BeginRejection.InvalidIdentity, rejection);
                Assert.Equal(DevLockboxS0Coordinator.FlowState.Idle, coordinator.State);
            }

            DevLockboxS0Coordinator maxLengthCoordinator = new DevLockboxS0Coordinator(Epoch,
                () => new string('x', DevLockboxS0Coordinator.MaximumIdentityPartLength),
                () => "request.valid", () => "panel.valid");
            DevLockboxS0Coordinator.AttemptIdentity maxLengthIdentity;
            DevLockboxS0Coordinator.BeginRejection maxLengthRejection;
            Assert.True(maxLengthCoordinator.TryBegin(ValidRequest(), out maxLengthIdentity,
                out maxLengthRejection));

            int requestNumber = 0;
            int panelNumber = 0;
            DevLockboxS0Coordinator reuseCoordinator = new DevLockboxS0Coordinator(Epoch,
                () => "flow.never-reuse",
                () => "request." + (++requestNumber),
                () => "panel." + (++panelNumber));
            DevLockboxS0Coordinator.AttemptIdentity first = Begin(reuseCoordinator);
            Assert.True(reuseCoordinator.CancelQueuedOpenExact(first.RequestToken));
            Assert.True(reuseCoordinator.AcknowledgeKnownRevocation(first.FlowHandle,
                first.PanelInstanceId, first.WebDocumentEpoch));
            Assert.True(reuseCoordinator.TryReleaseGlobalPauseAndReset());

            DevLockboxS0Coordinator.AttemptIdentity reusedIdentity;
            DevLockboxS0Coordinator.BeginRejection reusedRejection;
            Assert.False(reuseCoordinator.TryBegin(ValidRequest(), out reusedIdentity,
                out reusedRejection));
            Assert.Equal(DevLockboxS0Coordinator.BeginRejection.InvalidIdentity,
                reusedRejection);
            Assert.Equal(DevLockboxS0Coordinator.FlowState.Idle, reuseCoordinator.State);
        }

        [Fact]
        public void H12_DocumentEpochChangePreservesAuthorityUntilExactTeardownConverges()
        {
            Assert.Throws<ArgumentOutOfRangeException>(() =>
                new DevLockboxS0Coordinator(0));
            Assert.Throws<ArgumentOutOfRangeException>(() =>
                new DevLockboxS0Coordinator((long)int.MaxValue + 1));

            IdentitySequence invalidEpochIds;
            DevLockboxS0Coordinator invalidEpochCoordinator =
                NewCoordinator(out invalidEpochIds);
            DevLockboxS0Coordinator.BeginRequest invalidEpochRequest = ValidRequest();
            invalidEpochRequest.WebDocumentEpoch = (long)int.MaxValue + 1;
            DevLockboxS0Coordinator.AttemptIdentity invalidEpochIdentity;
            DevLockboxS0Coordinator.BeginRejection invalidEpochRejection;
            Assert.False(invalidEpochCoordinator.TryBegin(invalidEpochRequest,
                out invalidEpochIdentity, out invalidEpochRejection));
            Assert.Equal(DevLockboxS0Coordinator.BeginRejection.InvalidDocumentEpoch,
                invalidEpochRejection);
            Assert.Equal(0, invalidEpochIds.Calls);
            invalidEpochRequest.WebDocumentEpoch = 0;
            Assert.False(invalidEpochCoordinator.TryBegin(invalidEpochRequest,
                out invalidEpochIdentity, out invalidEpochRejection));
            Assert.Equal(DevLockboxS0Coordinator.BeginRejection.InvalidDocumentEpoch,
                invalidEpochRejection);
            Assert.Equal(0, invalidEpochIds.Calls);

            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids, 41);
            DevLockboxS0Coordinator.AttemptIdentity identity =
                BeginAndBind(coordinator, ValidRequest(41));

            Assert.False(coordinator.CanRebuildWebDocument);
            Assert.True(coordinator.AdvanceWebDocumentEpoch(42));
            Assert.Equal(42, coordinator.WebDocumentEpoch);
            Assert.Equal(DevLockboxS0Coordinator.FlowState.PanelBound, coordinator.State);
            Assert.True(coordinator.DocumentEpochChanged);
            Assert.False(coordinator.CanReleaseGlobalPause);
            Assert.False(coordinator.TryAcknowledgeBind(identity.FlowHandle,
                identity.PanelInstanceId, 42));
            Assert.False(coordinator.TrySubmitResult(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch, 1,
                DevLockboxS0Coordinator.LimitedResult.Cancel));

            Assert.True(coordinator.ConfirmOldDocumentTeardown(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.Equal(DevLockboxS0Coordinator.FlowState.RevokePending, coordinator.State);
            Assert.True(coordinator.ConfirmAuthorityExpired(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.True(coordinator.CanReleaseGlobalPause);
            Assert.True(coordinator.TryReleaseGlobalPauseAndReset());

            DevLockboxS0Coordinator.AttemptIdentity next;
            DevLockboxS0Coordinator.BeginRejection rejection;
            Assert.True(coordinator.TryBegin(ValidRequest(42), out next, out rejection));
            Assert.NotEqual(identity.FlowHandle, next.FlowHandle);
            Assert.Equal(42, next.WebDocumentEpoch);

            IdentitySequence maxEpochIds;
            DevLockboxS0Coordinator maxEpochCoordinator =
                NewCoordinator(out maxEpochIds, int.MaxValue);
            Begin(maxEpochCoordinator, ValidRequest(int.MaxValue));
            Assert.False(maxEpochCoordinator.AdvanceWebDocumentEpoch(
                (long)int.MaxValue + 1));
            Assert.Equal(int.MaxValue, maxEpochCoordinator.WebDocumentEpoch);
        }

        [Fact]
        public void H13_WebAndHttpOriginsCannotEnterTrustedAs2TaskBoundary()
        {
            AssertRejected(r => r.Origin = DevLockboxS0Coordinator.RouteOrigin.WebMessage,
                DevLockboxS0Coordinator.BeginRejection.UntrustedOrigin);
            AssertRejected(r => r.Origin = DevLockboxS0Coordinator.RouteOrigin.Http,
                DevLockboxS0Coordinator.BeginRejection.UntrustedOrigin);
            AssertRejected(r => r.Origin = DevLockboxS0Coordinator.RouteOrigin.Other,
                DevLockboxS0Coordinator.BeginRejection.UntrustedOrigin);

            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            Begin(coordinator);
            Assert.Equal(DevLockboxS0Coordinator.FlowState.OpenQueued, coordinator.State);
        }

        [Fact]
        public void H14_GlobalPanelSerializationIsRequiredBeforeAndThroughoutFlow()
        {
            AssertRejected(r => r.IsPanelOrchestrationIdle = false,
                DevLockboxS0Coordinator.BeginRejection.PanelOrchestrationBusy);

            IdentitySequence ids;
            DevLockboxS0Coordinator coordinator = NewCoordinator(out ids);
            DevLockboxS0Coordinator.AttemptIdentity identity = Begin(coordinator);
            Assert.True(coordinator.ShouldRejectOtherPanelOpen);
            Assert.True(coordinator.MarkQueuedOpenExecuting(identity.RequestToken));
            Assert.True(coordinator.MarkBindTimeout(identity.FlowHandle,
                identity.PanelInstanceId, identity.WebDocumentEpoch));
            Assert.True(coordinator.ShouldRejectOtherPanelOpen);
            Assert.True(coordinator.ShouldBlockGenericUnpause);

            DevLockboxS0Coordinator.AttemptIdentity second;
            DevLockboxS0Coordinator.BeginRejection rejection;
            Assert.False(coordinator.TryBegin(ValidRequest(), out second, out rejection));
            Assert.Equal(DevLockboxS0Coordinator.BeginRejection.Busy, rejection);
        }

        [Fact]
        public void H15_LockboxOutcomeMappingIsExactAndFinite()
        {
            DevLockboxS0Coordinator.LimitedResult mapped;
            Assert.True(DevLockboxS0Coordinator.TryMapLockboxOutcome("success", false, out mapped));
            Assert.Equal(DevLockboxS0Coordinator.LimitedResult.Success, mapped);
            Assert.True(DevLockboxS0Coordinator.TryMapLockboxOutcome("partial_success", false, out mapped));
            Assert.Equal(DevLockboxS0Coordinator.LimitedResult.Success, mapped);
            Assert.True(DevLockboxS0Coordinator.TryMapLockboxOutcome("fail", false, out mapped));
            Assert.Equal(DevLockboxS0Coordinator.LimitedResult.Failure, mapped);
            Assert.True(DevLockboxS0Coordinator.TryMapLockboxOutcome(null, true, out mapped));
            Assert.Equal(DevLockboxS0Coordinator.LimitedResult.Cancel, mapped);

            Assert.False(DevLockboxS0Coordinator.TryMapLockboxOutcome("SUCCESS", false, out mapped));
            Assert.False(DevLockboxS0Coordinator.TryMapLockboxOutcome("timeout", false, out mapped));
            Assert.False(DevLockboxS0Coordinator.TryMapLockboxOutcome("success", true, out mapped));
            Assert.False(DevLockboxS0Coordinator.TryMapLockboxOutcome(null, false, out mapped));
        }
    }
}
