using System;
using System.Collections.Generic;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentObservationEnvelopeStoreTests
    {
        private const string ClientId =
            "client_AAAAAAAAAAAAAAAAA";
        private const string PrincipalId =
            "principal_AAAAAAAAAAAAA";
        private const string SessionId =
            "session_AAAAAAAAAAAAAAA";
        private const string GrantId =
            "obsgrant_AAAAAAAAAAAAAA";
        private const string ObservationId =
            "observation_AAAAAAAAAAA";
        private const string TargetId =
            "target_AAAAAAAAAAAAAAAAA";
        private const string FrameId =
            "frame_AAAAAAAAAAAAAAAAAA";
        private const string Handle =
            "content_AAAAAAAAAAAAAAAA";

        [Fact]
        public void OwnerAndScopeAreRequiredForGetAndAcknowledge()
        {
            var store = new AgentObservationEnvelopeStore();
            AgentRuntimeDispatchContext owner = Context(
                ClientId,
                PrincipalId);
            store.Store(
                owner,
                ObservationDataScopesV1.Pixels,
                Envelope());

            AgentRuntimeDispatchContext otherClient = Context(
                "client_BBBBBBBBBBBBBBBBB",
                PrincipalId);
            Assert.False(store.TryGet(
                otherClient,
                GrantId,
                SessionId,
                ObservationId,
                out _,
                out _,
                out string ownerReason));
            Assert.Equal(
                "observation_scope_mismatch",
                ownerReason);
            Assert.False(store.TryAcknowledge(
                owner,
                GrantId,
                "session_BBBBBBBBBBBBBBB",
                ObservationId,
                out _,
                out _,
                out string scopeReason));
            Assert.Equal(
                "observation_scope_mismatch",
                scopeReason);

            Assert.True(store.TryAcknowledge(
                owner,
                GrantId,
                SessionId,
                ObservationId,
                out ObservationEnvelope acknowledged,
                out string acknowledgedScope,
                out string acknowledgeReason));
            Assert.Null(acknowledgeReason);
            Assert.Equal(
                ObservationId,
                acknowledged.ObservationId);
            Assert.Equal(
                ObservationDataScopesV1.Pixels,
                acknowledgedScope);
            Assert.False(store.TryGet(
                owner,
                GrantId,
                SessionId,
                ObservationId,
                out _,
                out _,
                out string terminalReason));
            Assert.Equal(
                "stale_observation",
                terminalReason);
            Assert.False(store.TryResolveContent(
                owner,
                Handle,
                out _,
                out string contentReason));
            Assert.Equal(
                "content_handle_not_found",
                contentReason);
        }

        [Fact]
        public void ContentHandleIsBoundToBothClientAndPrincipal()
        {
            var store = new AgentObservationEnvelopeStore();
            AgentRuntimeDispatchContext owner = Context(
                ClientId,
                PrincipalId);
            store.Store(
                owner,
                ObservationDataScopesV1.Pixels,
                Envelope());

            Assert.True(store.TryResolveContent(
                owner,
                Handle,
                out var binding,
                out _));
            Assert.Equal(ClientId, binding.ClientInstanceId);
            Assert.Equal(PrincipalId, binding.SecurityPrincipalId);
            Assert.Equal(ObservationId, binding.ObservationId);

            Assert.False(store.TryResolveContent(
                Context(
                    ClientId,
                    "principal_BBBBBBBBBBBBB"),
                Handle,
                out _,
                out string reason));
            Assert.Equal(
                "content_handle_binding_mismatch",
                reason);
        }

        [Theory]
        [InlineData("lifecycle", "stale_lifecycle")]
        [InlineData("attempt", "stale_attempt")]
        [InlineData("surface", "stale_surface")]
        [InlineData("coordinate", "stale_coordinate_space")]
        [InlineData("focus", "stale_focus")]
        [InlineData("modal", "stale_modal")]
        [InlineData("panel", "stale_panel_instance")]
        [InlineData("document", "stale_document")]
        [InlineData("semantic", "stale_semantic_node")]
        [InlineData("frame", "stale_observation")]
        public void ActionBindingRejectsEveryStaleGeneration(
            string mutation,
            string expectedReason)
        {
            var store = new AgentObservationEnvelopeStore();
            AgentRuntimeDispatchContext owner = Context(
                ClientId,
                PrincipalId);
            store.Store(
                owner,
                ObservationDataScopesV1.Pixels,
                Envelope());
            ActionEnvelope action = Action();
            switch (mutation)
            {
                case "lifecycle":
                    action.ExpectedLifecycleGeneration++;
                    break;
                case "attempt":
                    action.ExpectedAttemptGeneration++;
                    break;
                case "surface":
                    action.ExpectedSurfaceEpoch++;
                    break;
                case "coordinate":
                    action.ExpectedCoordinateSpaceVersion++;
                    break;
                case "focus":
                    action.ExpectedFocusEpoch++;
                    break;
                case "modal":
                    action.ExpectedModalEpoch++;
                    break;
                case "panel":
                    action.ExpectedPanelInstanceId =
                        "panel_BBBBBBBBBBBBBBBB";
                    break;
                case "document":
                    action.ExpectedDocumentGeneration++;
                    break;
                case "semantic":
                    action.ExpectedSemanticGeneration++;
                    break;
                case "frame":
                    action.FrameId =
                        "frame_BBBBBBBBBBBBBBBBB";
                    break;
            }

            Assert.False(store.TryResolveForAction(
                owner,
                action,
                out _,
                out string reason));
            Assert.Equal(expectedReason, reason);
        }

        private static AgentRuntimeDispatchContext Context(
            string clientId,
            string principalId)
        {
            return new AgentRuntimeDispatchContext(
                "connection_AAAAAAAAAAAAA",
                new PrincipalCredential(
                    "credential_AAAAAAAAAAAAA",
                    principalId,
                    clientId,
                    AgentPrincipalKind.DeveloperAgent,
                    AgentSessionMode.DeveloperInteractive,
                    1,
                    0,
                    60_000,
                    DateTimeOffset.UtcNow,
                    new[]
                    {
                        AgentCapabilitiesV1.Click,
                        "observe:pixels"
                    },
                    new[] { TargetId },
                    "test-enrollment",
                    null,
                    null,
                    null,
                    null));
        }

        private static ObservationEnvelope Envelope()
        {
            return new ObservationEnvelope
            {
                ObservationId = ObservationId,
                ObservationGrantId = GrantId,
                SessionId = SessionId,
                LifecycleGeneration = 7,
                CapturedUtc = DateTimeOffset.UtcNow,
                CapturedAtMonotonic = 10,
                AttemptId = "attempt_AAAAAAAAAAAAAAA",
                AttemptGeneration = 3,
                PanelInstanceId =
                    "panel_AAAAAAAAAAAAAAAAA",
                DocumentGeneration = 5,
                TargetId = TargetId,
                SurfaceEpoch = 11,
                CoordinateSpaceVersion = 13,
                FocusEpoch = 17,
                ModalEpoch = 19,
                SemanticSnapshotId =
                    "semantic_AAAAAAAAAAAAAA",
                SemanticGeneration = 23,
                Visible = true,
                Active = true,
                Frames = new List<FrameEnvelope>
                {
                    new FrameEnvelope
                    {
                        FrameId = FrameId,
                        ObservationId = ObservationId,
                        TargetId = TargetId,
                        SurfaceEpoch = 11,
                        CoordinateSpaceVersion = 13,
                        OpaqueContentHandle = Handle
                    }
                }
            };
        }

        private static ActionEnvelope Action()
        {
            return new ActionEnvelope
            {
                ActionId = "action_AAAAAAAAAAAAAAAAA",
                IdempotencyKey =
                    "idempotency_AAAAAAAAAAAA",
                DeadlineMs = 1_000,
                SessionId = SessionId,
                ObservationGrantId = GrantId,
                LeaseId = "lease_AAAAAAAAAAAAAAAAA",
                ObservationId = ObservationId,
                ExpectedLifecycleGeneration = 7,
                TargetId = TargetId,
                ExpectedSurfaceEpoch = 11,
                ExpectedAttemptId =
                    "attempt_AAAAAAAAAAAAAAA",
                ExpectedAttemptGeneration = 3,
                ExpectedPanelInstanceId =
                    "panel_AAAAAAAAAAAAAAAAA",
                ExpectedSemanticGeneration = 23,
                ExpectedDocumentGeneration = 5,
                ExpectedCoordinateSpaceVersion = 13,
                ExpectedFocusEpoch = 17,
                ExpectedModalEpoch = 19,
                FrameId = FrameId,
                SemanticSnapshotId =
                    "semantic_AAAAAAAAAAAAAA",
                Operation = AgentCapabilitiesV1.Click,
                Arguments = JsonSerializer.SerializeToElement(
                    new { x = 12, y = 18, button = "left" }),
                Reason = "test"
            };
        }
    }
}
