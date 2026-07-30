using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Contracts
{
    public class ContractArtifactTests
    {
        private static readonly string[] ArtifactNames =
        {
            "agent-runtime.v1.schema.json",
            "json-rpc.v1.schema.json",
            "method-params.v1.schema.json",
            "method-registry.v1.json",
            "parameter-contracts.v1.json",
            "capability-applicability.v1.json",
            "limits.v1.json",
            "reason-codes.v1.json",
            "canonical-json-vectors.v1.json",
            "contract-vectors.v1.json",
            "rpc-vectors.v1.json"
        };

        [Fact]
        public void EveryJsonArtifact_IsStrictJson()
        {
            foreach (string artifact in ArtifactNames)
            {
                using JsonDocument document = ContractFixture.ReadDocument(artifact);
                Assert.Equal(JsonValueKind.Object, document.RootElement.ValueKind);
            }
        }

        [Fact]
        public void Schema_CoversFrozenDescriptorsEpochsAndReceiptSemantics()
        {
            using JsonDocument document = ContractFixture.ReadDocument("agent-runtime.v1.schema.json");
            JsonElement definitions = document.RootElement.GetProperty("$defs");
            foreach (string definition in new[]
                     {
                         "hello",
                         "welcome",
                         "sessionDescriptor",
                         "surfaceDescriptor",
                         "observationGrantDescriptor",
                         "leaseDescriptor",
                         "observationEnvelope",
                         "frameEnvelope",
                         "actionEnvelope",
                         "actionReceipt",
                         "hairDomainActionResult",
                         "hairConsentDescriptor"
                     })
            {
                Assert.True(definitions.TryGetProperty(definition, out _), definition);
            }

            HashSet<string> actionRequired = definitions
                .GetProperty("actionEnvelope")
                .GetProperty("required")
                .EnumerateArray()
                .Select(item => item.GetString())
                .ToHashSet(StringComparer.Ordinal);
            Assert.Contains("expectedFocusEpoch", actionRequired);
            Assert.Contains("expectedModalEpoch", actionRequired);
            Assert.Contains("expectedCoordinateSpaceVersion", actionRequired);

            JsonElement actionProperties = definitions
                .GetProperty("actionEnvelope")
                .GetProperty("properties");
            Assert.True(actionProperties.TryGetProperty("expectedDocumentGeneration", out _));
            Assert.True(actionProperties.TryGetProperty("expectedSemanticGeneration", out _));
            Assert.True(actionProperties.TryGetProperty("semanticSnapshotId", out _));
            Assert.True(actionProperties.TryGetProperty("nodeId", out _));

            HashSet<string> activePanelRequired = definitions
                .GetProperty("activePanel")
                .GetProperty("required")
                .EnumerateArray()
                .Select(item => item.GetString())
                .ToHashSet(StringComparer.Ordinal);
            Assert.Contains("targetId", activePanelRequired);

            JsonElement receipt = definitions.GetProperty("actionReceipt");
            JsonElement lease =
                definitions.GetProperty("leaseDescriptor");
            Assert.Contains(
                "shutdown",
                lease.GetProperty("properties")
                    .GetProperty("purpose")
                    .GetProperty("enum")
                    .EnumerateArray()
                    .Select(item => item.GetString()));
            JsonElement shutdownLeaseCondition = lease
                .GetProperty("allOf")
                .EnumerateArray()
                .Single(item =>
                    item.TryGetProperty("if", out JsonElement condition)
                    && condition.GetProperty("properties")
                        .TryGetProperty(
                            "purpose",
                            out JsonElement purpose)
                    && purpose.GetProperty("const").GetString()
                        == "shutdown");
            Assert.Equal(
                new[]
                {
                    "developer_interactive",
                    "unattended_test"
                },
                shutdownLeaseCondition.GetProperty("then")
                    .GetProperty("properties")
                    .GetProperty("sessionMode")
                    .GetProperty("enum")
                    .EnumerateArray()
                    .Select(item => item.GetString()));
            Assert.Equal(
                "renewAfter",
                shutdownLeaseCondition.GetProperty("then")
                    .GetProperty("not")
                    .GetProperty("required")[0]
                    .GetString());
            Assert.Equal(
                "#/$defs/hairDomainActionResult",
                receipt.GetProperty("properties")
                    .GetProperty("domainResult")
                    .GetProperty("$ref")
                    .GetString());
            JsonElement domainResult =
                definitions.GetProperty("hairDomainActionResult");
            Assert.False(
                domainResult.GetProperty("additionalProperties").GetBoolean());
            Assert.Equal(
                new[] { "previewHash", "transactionId" },
                domainResult.GetProperty("required")
                    .EnumerateArray()
                    .Select(item => item.GetString())
                    .OrderBy(item => item, StringComparer.Ordinal));
            Assert.Equal(
                new[] { "restoreExpiresAtUtc" },
                domainResult.GetProperty("dependentRequired")
                    .GetProperty("restoreToken")
                    .EnumerateArray()
                    .Select(item => item.GetString()));
            Assert.Equal(
                new[] { "restoreToken" },
                domainResult.GetProperty("dependentRequired")
                    .GetProperty("restoreExpiresAtUtc")
                    .EnumerateArray()
                    .Select(item => item.GetString()));

            JsonElement hairConsent =
                definitions.GetProperty("hairConsentDescriptor");
            Assert.False(
                hairConsent.GetProperty(
                    "additionalProperties").GetBoolean());
            Assert.Equal(
                new[]
                {
                    "consentReceipt",
                    "consentToken",
                    "expiresInMs",
                    "previewHash",
                    "transactionId"
                },
                hairConsent.GetProperty("required")
                    .EnumerateArray()
                    .Select(item => item.GetString())
                    .OrderBy(item => item, StringComparer.Ordinal));
            Assert.Equal(
                60_000,
                hairConsent.GetProperty("properties")
                    .GetProperty("expiresInMs")
                    .GetProperty("const")
                    .GetInt32());

            JsonElement domainCommittedCondition = receipt
                .GetProperty("allOf")
                .EnumerateArray()
                .Single(item =>
                    item.GetProperty("if")
                        .GetProperty("properties")
                        .GetProperty("outcome")
                        .GetProperty("const")
                        .GetString() == "domain_committed");
            Assert.Contains(
                "domainResult",
                domainCommittedCondition.GetProperty("then")
                    .GetProperty("required")
                    .EnumerateArray()
                    .Select(item => item.GetString()));
            Assert.Equal(
                "domainResult",
                domainCommittedCondition.GetProperty("else")
                    .GetProperty("not")
                    .GetProperty("required")[0]
                    .GetString());

            string schema = document.RootElement.GetRawText();
            foreach (string outcome in new[]
                     {
                         "rejected",
                         "input_dispatched",
                         "effect_observed",
                         "domain_committed",
                         "unknown"
                     })
            {
                Assert.Contains("\"" + outcome + "\"", schema, StringComparison.Ordinal);
            }
            foreach (string reconcileKind in new[]
                     {
                         "domain_authoritative",
                         "visual_ambiguous",
                         "manual_required"
                     })
            {
                Assert.Contains("\"" + reconcileKind + "\"", schema, StringComparison.Ordinal);
            }
        }

        [Fact]
        public void LeaseAcquireSchema_ExposesDedicatedOneShotShutdownKind()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "method-params.v1.schema.json");
            JsonElement lease = document.RootElement
                .GetProperty("$defs")
                .GetProperty("leaseAcquire");
            Assert.Contains(
                "shutdown",
                lease.GetProperty("properties")
                    .GetProperty("kind")
                    .GetProperty("enum")
                    .EnumerateArray()
                    .Select(item => item.GetString()));
            string contract = JsonSerializer.Serialize(lease);
            Assert.Contains(
                "\"const\":\"shutdown\"",
                contract,
                StringComparison.Ordinal);
            Assert.Contains(
                "\"const\":\"session.shutdown\"",
                contract,
                StringComparison.Ordinal);

            using JsonDocument parameterContracts =
                ContractFixture.ReadDocument(
                    "parameter-contracts.v1.json");
            JsonElement shutdown = parameterContracts.RootElement
                .GetProperty("contracts")
                .GetProperty("leaseAcquire")
                .GetProperty("kindBindings")
                .GetProperty("shutdown");
            Assert.Equal(
                new[] { "session.shutdown" },
                shutdown.GetProperty("capabilitiesExact")
                    .EnumerateArray()
                    .Select(item => item.GetString()));
            Assert.Equal(
                1,
                shutdown.GetProperty(
                    "minimumTargets").GetInt32());
            Assert.Equal(
                1,
                shutdown.GetProperty(
                    "maximumTargets").GetInt32());
            Assert.Equal(
                "launcher",
                shutdown.GetProperty(
                    "requiredTargetKind").GetString());
            Assert.Equal(
                new[]
                {
                    "developer_interactive",
                    "unattended_test"
                },
                shutdown.GetProperty(
                        "allowedSessionModes")
                    .EnumerateArray()
                    .Select(item => item.GetString()));
            Assert.Equal(
                30_000,
                shutdown.GetProperty(
                    "maximumTtlMs").GetInt32());
            Assert.Equal(
                1,
                shutdown.GetProperty(
                    "maximumActions").GetInt32());
            Assert.False(
                shutdown.GetProperty(
                    "renewAfterAllowed").GetBoolean());
            Assert.Equal(
                "operation_invalid",
                shutdown.GetProperty(
                    "renewalOperationResult").GetString());
        }

        [Fact]
        public void CapabilityRegistry_MatchesCompiledThirteenItemApplicability()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument("capability-applicability.v1.json");
            JsonElement entries = document.RootElement.GetProperty("capabilities");
            Assert.Equal(13, entries.GetArrayLength());
            Assert.Equal(13, AgentCapabilitiesV1.GuiCapabilitySet.Count);
            Assert.Equal(13, CapabilityApplicabilityV1.GuiCapabilities.Count);

            var byName = entries.EnumerateArray().ToDictionary(
                item => item.GetProperty("name").GetString(),
                StringComparer.Ordinal);
            Assert.Equal(
                AgentCapabilitiesV1.GuiCapabilitySet.OrderBy(item => item, StringComparer.Ordinal),
                byName.Keys.OrderBy(item => item, StringComparer.Ordinal));

            foreach (CapabilityApplicability compiled in CapabilityApplicabilityV1.GuiCapabilities)
            {
                JsonElement artifact = byName[compiled.Name];
                Assert.Equal(compiled.ReferenceName, artifact.GetProperty("referenceName").GetString());
                Assert.Equal(
                    compiled.Modes.Select(ContractFixture.EnumText).OrderBy(item => item, StringComparer.Ordinal),
                    artifact.GetProperty("modes").EnumerateArray()
                        .Select(item => item.GetString())
                        .OrderBy(item => item, StringComparer.Ordinal));
                Assert.Equal(
                    compiled.Surfaces.Select(ContractFixture.EnumText).OrderBy(item => item, StringComparer.Ordinal),
                    artifact.GetProperty("surfaces").EnumerateArray()
                        .Select(item => item.GetString())
                        .OrderBy(item => item, StringComparer.Ordinal));
                Assert.Equal(
                    compiled.RequiresObservationGrant,
                    artifact.GetProperty("requiresObservationGrant").GetBoolean());
                Assert.Equal(
                    compiled.RequiresWriteLease,
                    artifact.GetProperty("requiresWriteLease").GetBoolean());
                Assert.Equal(
                    compiled.RequiresSemanticProvider,
                    artifact.GetProperty("requiresSemanticProvider").GetBoolean());
                Assert.Equal(
                    compiled.RequiresNativeInputGate,
                    artifact.GetProperty("nativePathRequiresContainmentGate").GetBoolean());
                Assert.Equal(
                    compiled.PreLaunchAllowed,
                    artifact.GetProperty("preLaunchAllowed").GetBoolean());
            }

            Assert.True(
                CapabilityApplicabilityV1.GuiCapabilities.Single(
                    item => item.Name
                        == AgentCapabilitiesV1.ListWindows)
                    .RequiresObservationGrant);
            Assert.Empty(
                CapabilityApplicabilityV1.GuiCapabilities.Single(
                    item => item.Name
                        == AgentCapabilitiesV1.SetValue)
                    .Surfaces);
            Assert.Empty(
                CapabilityApplicabilityV1.GuiCapabilities.Single(
                    item => item.Name
                        == AgentCapabilitiesV1
                            .PerformSecondaryAction)
                    .Surfaces);
            Assert.Equal(
                new[] { SurfaceKind.Flash },
                CapabilityApplicabilityV1.GuiCapabilities.Single(
                    item => item.Name
                        == AgentCapabilitiesV1.ActivateWindow)
                    .Surfaces);

            Assert.Equal(
                "never_discover_capture_observe_or_input",
                document.RootElement.GetProperty("securitySurfacePolicy").GetString());
        }

        [Fact]
        public void LimitsArtifact_MatchesCompiledHardCaps()
        {
            using JsonDocument document = ContractFixture.ReadDocument("limits.v1.json");
            JsonElement root = document.RootElement;
            JsonElement frame = root.GetProperty("frame");
            Assert.Equal(AgentProtocolV1.FrameMagic, frame.GetProperty("magic").GetString());
            Assert.Equal(AgentProtocolV1.FrameHeaderBytes, frame.GetProperty("headerBytes").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumJsonFrameBytes,
                frame.GetProperty("maximumJsonFrameBytes").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumBinaryChunkBytes,
                frame.GetProperty("maximumBinaryChunkBytes").GetInt32());
            Assert.Equal(
                AgentProtocolV1.BinaryChunkMetadataLengthBytes,
                frame.GetProperty("binaryChunkMetadataLengthBytes").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumBinaryChunkMetadataBytes,
                frame.GetProperty("maximumBinaryChunkMetadataBytes").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumBinaryReadCount,
                frame.GetProperty("maximumBinaryReadCount").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumBinaryObjectBytes,
                frame.GetProperty("maximumBinaryObjectBytes").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumActionDeadlineMs,
                root.GetProperty("action").GetProperty("maximumDeadlineMs").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumObservationTtlMs,
                root.GetProperty("observation").GetProperty("maximumObservationTtlMs").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumObservationGrantTtlMs,
                root.GetProperty("observation").GetProperty("maximumGrantTtlMs").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumContentHandleTtlMs,
                root.GetProperty("observation").GetProperty("maximumContentHandleTtlMs").GetInt32());
            Assert.Equal(
                AgentProtocolV1.MaximumTargetScopeItems,
                root.GetProperty("scope").GetProperty("maximumTargetScopeItems").GetInt32());
            JsonElement shutdown =
                root.GetProperty("lease")
                    .GetProperty("shutdown");
            Assert.Equal(
                30_000,
                shutdown.GetProperty(
                    "maximumTtlMs").GetInt32());
            Assert.Equal(
                1,
                shutdown.GetProperty(
                    "maximumActions").GetInt32());
            Assert.Equal(
                1,
                shutdown.GetProperty(
                    "minimumTargets").GetInt32());
            Assert.Equal(
                1,
                shutdown.GetProperty(
                    "maximumTargets").GetInt32());
            Assert.Equal(
                "launcher",
                shutdown.GetProperty(
                    "requiredTargetKind").GetString());
            Assert.Equal(
                new[]
                {
                    "developer_interactive",
                    "unattended_test"
                },
                shutdown.GetProperty(
                        "allowedSessionModes")
                    .EnumerateArray()
                    .Select(item => item.GetString()));
            Assert.False(
                shutdown.GetProperty(
                    "renewAfterAllowed").GetBoolean());
            Assert.False(
                shutdown.GetProperty(
                    "automaticRenewal").GetBoolean());
            Assert.Equal(
                "operation_invalid",
                shutdown.GetProperty(
                    "renewalOperationResult").GetString());
        }

        [Fact]
        public void ReasonRegistry_MatchesCompiledClosedRegistry()
        {
            using JsonDocument document = ContractFixture.ReadDocument("reason-codes.v1.json");
            JsonElement entries = document.RootElement.GetProperty("reasonCodes");
            HashSet<string> artifactCodes = entries.EnumerateObject()
                .Select(item => item.Name)
                .ToHashSet(StringComparer.Ordinal);
            Assert.Equal(
                AgentReasonCodesV1.All.Keys.OrderBy(item => item, StringComparer.Ordinal),
                artifactCodes.OrderBy(item => item, StringComparer.Ordinal));

            foreach ((string code, ReasonCodeDefinition compiled) in AgentReasonCodesV1.All)
            {
                JsonElement artifact = entries.GetProperty(code);
                Assert.Equal(compiled.Retryable, artifact.GetProperty("retryable").GetBoolean());
                Assert.Equal(
                    compiled.AllowedOutcomes.Select(ContractFixture.EnumText)
                        .OrderBy(item => item, StringComparer.Ordinal),
                    artifact.GetProperty("outcomes").EnumerateArray()
                        .Select(item => item.GetString())
                        .OrderBy(item => item, StringComparer.Ordinal));
                Assert.Equal(
                    compiled.AllowedReconcileKinds.Select(ContractFixture.EnumText)
                        .OrderBy(item => item, StringComparer.Ordinal),
                    artifact.GetProperty("reconcileKinds").EnumerateArray()
                        .Select(item => item.GetString())
                        .OrderBy(item => item, StringComparer.Ordinal));
            }
        }
    }
}
