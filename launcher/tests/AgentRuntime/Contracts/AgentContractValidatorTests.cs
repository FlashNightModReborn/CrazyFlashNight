using System.Linq;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Contracts
{
    public class AgentContractValidatorTests
    {
        [Fact]
        public void ValidContractVectors_PassTypedValidation()
        {
            using JsonDocument document = ContractFixture.ReadDocument("contract-vectors.v1.json");
            JsonElement valid = document.RootElement.GetProperty("valid");

            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<SessionDescriptor>(valid.GetProperty("session"))));
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<ObservationGrantDescriptor>(
                    valid.GetProperty("observationGrant"))));
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<LeaseDescriptor>(valid.GetProperty("lease"))));
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<LeaseDescriptor>(
                    valid.GetProperty("shutdownLease"))));
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<LeaseDescriptor>(
                    valid.GetProperty("structuredActionLease"))));
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<ObservationEnvelope>(valid.GetProperty("observation"))));
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<ActionReceipt>(valid.GetProperty("inputReceipt"))));
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<ActionReceipt>(valid.GetProperty("domainReceipt"))));
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<ActionReceipt>(valid.GetProperty("unknownReceipt"))));

            using JsonDocument canonical =
                ContractFixture.ReadDocument("canonical-json-vectors.v1.json");
            Assert.Empty(AgentContractValidator.Validate(
                ContractFixture.Deserialize<ActionEnvelope>(
                    canonical.RootElement.GetProperty("actionVector").GetProperty("action"))));
        }

        [Fact]
        public void FocusAndModalEpochs_AreMandatoryPositiveBindings()
        {
            ActionEnvelope action = ReadAction();
            action.ExpectedFocusEpoch = 0;
            action.ExpectedModalEpoch = 0;
            var violations = AgentContractValidator.Validate(action);
            Assert.Contains(violations, item => item.Path == "$.expectedFocusEpoch");
            Assert.Contains(violations, item => item.Path == "$.expectedModalEpoch");
        }

        [Fact]
        public void CoordinateAction_RequiresBoundFrameAndObservationSpace()
        {
            ActionEnvelope action = ReadAction();
            action.FrameId = null;
            action.Arguments = JsonDocument.Parse("{\"x\":1,\"y\":2}").RootElement.Clone();
            var violations = AgentContractValidator.Validate(action);
            Assert.Contains(violations, item => item.Path == "$.frameId");
            Assert.Contains(violations, item => item.Path == "$.arguments.coordinateSpace");
        }

        [Fact]
        public void SemanticAction_RequiresSnapshotNodeAndGeneration()
        {
            ActionEnvelope action = ReadAction();
            action.Operation = AgentCapabilitiesV1.SetValue;
            action.FrameId = null;
            action.NodeId = null;
            action.SemanticSnapshotId = null;
            action.ExpectedSemanticGeneration = null;
            action.Arguments = JsonDocument.Parse("{\"value\":\"建议\"}").RootElement.Clone();
            var violations = AgentContractValidator.Validate(action);
            Assert.Contains(violations, item => item.Path == "$.nodeId");
            Assert.Contains(violations, item => item.Path == "$.semanticSnapshotId");
            Assert.Contains(violations, item => item.Path == "$.expectedSemanticGeneration");
        }

        [Fact]
        public void PlayerAssistLease_EnforcesTargetActionAndTimeCaps()
        {
            LeaseDescriptor lease = ReadLease();
            lease.ExpiresMonotonic = lease.IssuedMonotonic + 30_001;
            lease.Scope.MaximumActions = 9;
            lease.Scope.TargetScope.Add("qqqqqqqqqqqqqqqqqqqqqq");
            var violations = AgentContractValidator.Validate(lease);
            Assert.Contains(violations, item => item.Path == "$.expiresMonotonic");
            Assert.Contains(violations, item => item.Path == "$.scope.maximumActions");
            Assert.Contains(violations, item => item.Path == "$.scope.targetScope");
        }

        [Fact]
        public void ShutdownLease_IsExactOneShotAndHasDedicatedPurpose()
        {
            LeaseDescriptor lease = ReadShutdownLease();
            Assert.Empty(
                AgentContractValidator.Validate(lease));

            lease.ExpiresMonotonic =
                lease.IssuedMonotonic + 30_001;
            lease.Scope.MaximumActions = 2;
            lease.Scope.TargetScope.Add(
                "qqqqqqqqqqqqqqqqqqqqqq");
            lease.Capabilities.Add(
                AgentCapabilitiesV1.Click);
            var violations =
                AgentContractValidator.Validate(lease);

            Assert.Contains(
                violations,
                item => item.Path
                    == "$.expiresMonotonic");
            Assert.Contains(
                violations,
                item => item.Path
                    == "$.scope.maximumActions");
            Assert.Contains(
                violations,
                item => item.Path
                    == "$.scope.targetScope");
            Assert.Contains(
                violations,
                item => item.Path
                    == "$.capabilities");
        }

        [Fact]
        public void PlayerAssistShutdownLease_IsAnImpossibleDescriptor()
        {
            LeaseDescriptor lease = ReadShutdownLease();
            lease.SessionMode = SessionMode.PlayerAssist;
            lease.ConsentReceipt = "player-consent-1";
            lease.Scope.ArgumentBoundsHash =
                "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD";

            ContractViolation violation = Assert.Single(
                AgentContractValidator.Validate(lease));

            Assert.Equal("$.sessionMode", violation.Path);
            Assert.Equal("lease_kind_mismatch", violation.Code);

            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "contract-vectors.v1.json");
            JsonElement vector = document.RootElement
                .GetProperty("invalidCases")
                .EnumerateArray()
                .Single(item =>
                    item.GetProperty("id").GetString()
                        == "player-assist-shutdown-impossible");
            Assert.Equal(
                "shutdownLease",
                vector.GetProperty("base").GetString());
            Assert.Equal(
                "sessionMode=player_assist",
                vector.GetProperty("mutation").GetString());
            Assert.Equal(
                violation.Code,
                vector.GetProperty(
                    "expectedViolationCode").GetString());
        }

        [Fact]
        public void PlayerAssistStructuredActionLease_IsAnImpossibleDescriptor()
        {
            LeaseDescriptor lease = ReadStructuredActionLease();
            lease.SessionMode = SessionMode.PlayerAssist;
            lease.ConsentReceipt = "player-consent-1";
            lease.Scope.ArgumentBoundsHash =
                "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD";

            ContractViolation violation = Assert.Single(
                AgentContractValidator.Validate(lease));

            Assert.Equal("$.sessionMode", violation.Path);
            Assert.Equal("lease_kind_mismatch", violation.Code);
        }

        [Fact]
        public void StructuredActionLease_IsNonrenewable()
        {
            LeaseDescriptor lease = ReadStructuredActionLease();
            lease.RenewAfter = 15_000;

            ContractViolation violation = Assert.Single(
                AgentContractValidator.Validate(lease));

            Assert.Equal("$.renewAfter", violation.Path);
            Assert.Equal("forbidden", violation.Code);
        }

        [Fact]
        public void PanelOpenAuthority_RequiresStructuredActionPurposeReciprocally()
        {
            LeaseDescriptor wrongPurpose = ReadStructuredActionLease();
            wrongPurpose.Purpose = LeasePurpose.GuiInput;

            var wrongPurposeViolations =
                AgentContractValidator.Validate(wrongPurpose);

            Assert.Contains(
                wrongPurposeViolations,
                item => item.Path == "$.capabilities"
                    && item.Code == "lease_kind_mismatch");
            Assert.Contains(
                wrongPurposeViolations,
                item => item.Path == "$.scope.operationScope"
                    && item.Code == "lease_kind_mismatch");

            LeaseDescriptor wrongOperation = ReadStructuredActionLease();
            wrongOperation.Scope.OperationScope =
                new()
                {
                    AgentCapabilitiesV1.Click
                };

            Assert.Contains(
                AgentContractValidator.Validate(wrongOperation),
                item => item.Path == "$.scope.operationScope"
                    && item.Code == "exactly_one");
        }

        [Fact]
        public void NonShutdownPurposeCannotCarryShutdownAuthority()
        {
            LeaseDescriptor lease = ReadLease();
            lease.Capabilities =
                new()
                {
                    AgentCapabilitiesV1.SessionShutdown
                };
            lease.Scope.OperationScope =
                new()
                {
                    AgentCapabilitiesV1.SessionShutdown
                };

            var violations =
                AgentContractValidator.Validate(lease);

            Assert.Contains(
                violations,
                item => item.Path == "$.capabilities"
                    && item.Code
                        == "lease_kind_mismatch");
            Assert.Contains(
                violations,
                item => item.Path
                    == "$.scope.operationScope"
                    && item.Code
                        == "lease_kind_mismatch");
        }

        [Fact]
        public void SecurityOrForeignModal_ProhibitsPixelAndSemanticReturn()
        {
            ObservationEnvelope observation = ReadObservation();
            observation.BlockingModalKind = BlockingModalKind.HumanOnlySecurity;
            observation.Accessibility = JsonDocument.Parse("{\"name\":\"forbidden\"}").RootElement.Clone();
            var violations = AgentContractValidator.Validate(observation);
            Assert.Contains(violations, item => item.Path == "$.frames");
            Assert.Contains(violations, item => item.Path == "$.accessibility");
        }

        [Fact]
        public void OwnedBusinessModalFrame_BindsItsOwnTargetGenerations()
        {
            ObservationEnvelope observation = ReadObservation();
            FrameEnvelope primary = observation.Frames[0];
            observation.Frames.Add(new FrameEnvelope
            {
                FrameId = "modalframeabcdefghijkl",
                ObservationId = observation.ObservationId,
                TargetId = "modaltargetabcdefghijk",
                SurfaceEpoch = primary.SurfaceEpoch + 10,
                SourceLayer = SourceLayer.BusinessModal,
                ZIndex = primary.ZIndex + 1,
                CapturedAtMonotonic = primary.CapturedAtMonotonic,
                CoordinateSpaceId = "modalspaceabcdefghijkl",
                CoordinateSpaceVersion =
                    primary.CoordinateSpaceVersion + 20,
                CaptureRectPhysical = primary.CaptureRectPhysical,
                ClientRectPhysical = primary.ClientRectPhysical,
                ContentRectPhysical = primary.ContentRectPhysical,
                FrameToTargetContentTransform =
                    primary.FrameToTargetContentTransform,
                Width = primary.Width,
                Height = primary.Height,
                Dpi = primary.Dpi,
                PixelFormat = primary.PixelFormat,
                ContentHash = primary.ContentHash,
                OpaqueContentHandle =
                    "modalcontentabcdefghij"
            });

            Assert.Empty(AgentContractValidator.Validate(observation));
        }

        [Fact]
        public void OwnedFrame_TargetEpochsStillFailClosedIndependently()
        {
            ObservationEnvelope observation = ReadObservation();
            FrameEnvelope frame = observation.Frames[0];
            frame.TargetId = "not an opaque id";
            frame.SurfaceEpoch = 0;
            frame.CoordinateSpaceVersion = 0;

            var violations = AgentContractValidator.Validate(observation);
            Assert.Contains(
                violations,
                item => item.Path == "$.frames[0].targetId");
            Assert.Contains(
                violations,
                item => item.Path == "$.frames[0].surfaceEpoch");
            Assert.Contains(
                violations,
                item => item.Path
                    == "$.frames[0].coordinateSpaceVersion");
        }

        [Fact]
        public void UnknownReceipt_RequiresExplicitNonRetryableReconciliation()
        {
            ActionReceipt receipt = ReadReceipt("unknownReceipt");
            receipt.ReconcileKind = ReconcileKind.None;
            receipt.Retryable = true;
            receipt.EvidenceKind = EvidenceKind.None;
            var violations = AgentContractValidator.Validate(receipt);
            Assert.Contains(violations, item => item.Path == "$.reconcileKind");
            Assert.Contains(violations, item => item.Path == "$.retryable");
            Assert.Contains(violations, item => item.Path == "$.evidenceKind");
        }

        [Fact]
        public void FormalRuntimeRequiresBuildAndPayloadIdentity()
        {
            SessionDescriptor session = ReadSession();
            session.RuntimeQualification.BuildIdentity = null;
            session.RuntimeQualification.PayloadClosure = null;
            var violations = AgentContractValidator.Validate(session);
            Assert.Contains(violations, item => item.Path == "$.runtimeQualification.buildIdentity");
            Assert.Contains(violations, item => item.Path == "$.runtimeQualification.payloadClosure");
        }

        [Fact]
        public void ActivePanelRequiresItsExactDiscoverableTarget()
        {
            SessionDescriptor session = ReadSession();
            session.ActivePanel.TargetId =
                "target_not_registered_AAAA";

            var violations =
                AgentContractValidator.Validate(session);

            Assert.Contains(
                violations,
                item => item.Path
                        == "$.activePanel.targetId"
                    && item.Code
                        == "target_not_found");
        }

        [Fact]
        public void ReceiptReasonRegistry_OwnsOutcomeReconcileAndRetryability()
        {
            ActionReceipt receipt = ReadReceipt("inputReceipt");
            receipt.ReasonCode = "stale_focus";
            receipt.Outcome = ActionOutcome.InputDispatched;
            receipt.Retryable = false;
            var violations = AgentContractValidator.Validate(receipt);
            Assert.Contains(violations, item => item.Code == "reason_outcome_mismatch");
            Assert.Contains(violations, item => item.Code == "reason_retryable_mismatch");
        }

        [Fact]
        public void DomainCommittedReceipt_RequiresTypedHairResult()
        {
            ActionReceipt receipt = ReadReceipt("domainReceipt");
            receipt.DomainResult = null;

            var violations = AgentContractValidator.Validate(receipt);

            Assert.Contains(
                violations,
                item => item.Path == "$.domainResult"
                    && item.Code == "required");
        }

        [Fact]
        public void NonDomainReceipt_ProhibitsDomainResult()
        {
            ActionReceipt receipt = ReadReceipt("inputReceipt");
            receipt.DomainResult = ReadReceipt("domainReceipt").DomainResult;

            var violations = AgentContractValidator.Validate(receipt);

            Assert.Contains(
                violations,
                item => item.Path == "$.domainResult"
                    && item.Code == "prohibited");
        }

        [Fact]
        public void HairDomainResult_RequiresTransactionAndPreviewBindings()
        {
            ActionReceipt receipt = ReadReceipt("domainReceipt");
            receipt.DomainResult.TransactionId = "not opaque";
            receipt.DomainResult.PreviewHash = "not a hash";

            var violations = AgentContractValidator.Validate(receipt);

            Assert.Contains(
                violations,
                item => item.Path == "$.domainResult.transactionId");
            Assert.Contains(
                violations,
                item => item.Path == "$.domainResult.previewHash");
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void HairDomainResult_RestoreTokenAndExpiryArePaired(
            bool retainToken)
        {
            ActionReceipt receipt = ReadReceipt("domainReceipt");
            if (retainToken)
                receipt.DomainResult.RestoreExpiresAtUtc = null;
            else
                receipt.DomainResult.RestoreToken = null;

            var violations = AgentContractValidator.Validate(receipt);

            Assert.Contains(
                violations,
                item => item.Path == "$.domainResult"
                    && item.Code == "paired_required");
        }

        private static ActionEnvelope ReadAction()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument("canonical-json-vectors.v1.json");
            return ContractFixture.Deserialize<ActionEnvelope>(
                document.RootElement.GetProperty("actionVector").GetProperty("action"));
        }

        private static SessionDescriptor ReadSession()
        {
            using JsonDocument document = ContractFixture.ReadDocument("contract-vectors.v1.json");
            return ContractFixture.Deserialize<SessionDescriptor>(
                document.RootElement.GetProperty("valid").GetProperty("session"));
        }

        private static LeaseDescriptor ReadLease()
        {
            using JsonDocument document = ContractFixture.ReadDocument("contract-vectors.v1.json");
            return ContractFixture.Deserialize<LeaseDescriptor>(
                document.RootElement.GetProperty("valid").GetProperty("lease"));
        }

        private static LeaseDescriptor
            ReadShutdownLease()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "contract-vectors.v1.json");
            return ContractFixture
                .Deserialize<LeaseDescriptor>(
                    document.RootElement
                        .GetProperty("valid")
                        .GetProperty(
                            "shutdownLease"));
        }

        private static LeaseDescriptor
            ReadStructuredActionLease()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "contract-vectors.v1.json");
            return ContractFixture
                .Deserialize<LeaseDescriptor>(
                    document.RootElement
                        .GetProperty("valid")
                        .GetProperty(
                            "structuredActionLease"));
        }

        private static ObservationEnvelope ReadObservation()
        {
            using JsonDocument document = ContractFixture.ReadDocument("contract-vectors.v1.json");
            return ContractFixture.Deserialize<ObservationEnvelope>(
                document.RootElement.GetProperty("valid").GetProperty("observation"));
        }

        private static ActionReceipt ReadReceipt(string name)
        {
            using JsonDocument document = ContractFixture.ReadDocument("contract-vectors.v1.json");
            return ContractFixture.Deserialize<ActionReceipt>(
                document.RootElement.GetProperty("valid").GetProperty(name));
        }
    }
}
