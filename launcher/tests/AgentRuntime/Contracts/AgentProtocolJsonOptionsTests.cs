using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Contracts
{
    public sealed class AgentProtocolJsonOptionsTests
    {
        [Fact]
        public void WireDeserializer_RejectsUnknownProperties()
        {
            const string json =
                "{\"protocolVersion\":\"1.0\","
                + "\"clientInstanceId\":\"client_abcdefghijklmnopqrstuv\","
                + "\"clientKind\":\"jsonl_cli\","
                + "\"requestedCapabilities\":[],"
                + "\"nonce\":\"nonce_abcdefghijklmnopqrstuv\","
                + "\"connectionToken\":\"ticket_abcdefghijklmnopqrstuv\","
                + "\"credentialProof\":\"proof_abcdefghijklmnopqrstuv\","
                + "\"clientSelectedPrincipal\":\"wings_persona\"}";

            Assert.Throws<JsonException>(
                () => JsonSerializer.Deserialize<HelloMessage>(
                    json,
                    AgentProtocolV1.JsonOptions));
        }

        [Fact]
        public void WireDeserializer_RejectsNumericEnumValues()
        {
            const string json =
                "{\"protocolVersion\":\"1.0\","
                + "\"clientInstanceId\":\"client_abcdefghijklmnopqrstuv\","
                + "\"clientKind\":2,"
                + "\"requestedCapabilities\":[],"
                + "\"nonce\":\"nonce_abcdefghijklmnopqrstuv\","
                + "\"connectionToken\":\"ticket_abcdefghijklmnopqrstuv\","
                + "\"credentialProof\":\"proof_abcdefghijklmnopqrstuv\"}";

            Assert.Throws<JsonException>(
                () => JsonSerializer.Deserialize<HelloMessage>(
                    json,
                    AgentProtocolV1.JsonOptions));
        }

        [Fact]
        public void ContractValidator_RejectsGenerationBeyondSafeInteger()
        {
            var action = new ActionEnvelope
            {
                ActionId = "action_abcdefghijklmnopqrstuv",
                IdempotencyKey = "idem_abcdefghijklmnopqrstuvwx",
                DeadlineMs = 1000,
                SessionId = "session_abcdefghijklmnopqrst",
                ObservationGrantId = "grant_abcdefghijklmnopqrstuv",
                LeaseId = "lease_abcdefghijklmnopqrstuv",
                ObservationId = "observation_abcdefghijklmnop",
                ExpectedLifecycleGeneration =
                    (ulong)CanonicalJsonV1.MaximumSafeInteger + 1,
                TargetId = "target_abcdefghijklmnopqrstuv",
                ExpectedSurfaceEpoch = 1,
                ExpectedCoordinateSpaceVersion = 1,
                ExpectedFocusEpoch = 1,
                ExpectedModalEpoch = 1,
                Operation = AgentCapabilitiesV1.PressKey,
                Arguments = JsonDocument.Parse(
                    "{\"key\":\"Enter\"}").RootElement.Clone(),
                Reason = "test"
            };

            Assert.Contains(
                AgentContractValidator.Validate(action),
                violation =>
                    violation.Path == "$.expectedLifecycleGeneration"
                    && violation.Code == "safe_integer");
        }

        [Fact]
        public void ShutdownLeasePurpose_RoundTripsAsFrozenWireText()
        {
            string json = JsonSerializer.Serialize(
                LeasePurpose.Shutdown,
                AgentProtocolV1.JsonOptions);

            Assert.Equal("\"shutdown\"", json);
            Assert.Equal(
                LeasePurpose.Shutdown,
                JsonSerializer.Deserialize<LeasePurpose>(
                    json,
                    AgentProtocolV1.JsonOptions));
        }
    }
}
