using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Contracts
{
    public class CanonicalJsonV1Tests
    {
        [Fact]
        public void GenericVectors_CanonicalizeExactly()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument("canonical-json-vectors.v1.json");
            foreach (JsonElement vector in document.RootElement
                         .GetProperty("genericVectors")
                         .EnumerateArray())
            {
                Assert.Equal(
                    vector.GetProperty("expected").GetString(),
                    CanonicalJsonV1.Canonicalize(vector.GetProperty("input").GetString()));
            }
        }

        [Fact]
        public void ActionVector_ExcludesDisplayAndRequestIdentityFields()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument("canonical-json-vectors.v1.json");
            JsonElement vector = document.RootElement.GetProperty("actionVector");
            ActionEnvelope action =
                ContractFixture.Deserialize<ActionEnvelope>(vector.GetProperty("action"));
            ActionEnvelope equivalent =
                ContractFixture.Deserialize<ActionEnvelope>(vector.GetProperty("equivalentAction"));
            string expected = vector.GetProperty("expectedPayload").GetString();
            Assert.Equal(expected, CanonicalJsonV1.CreateActionPayload(action));
            Assert.Equal(expected, CanonicalJsonV1.CreateActionPayload(equivalent));
            Assert.Equal(
                vector.GetProperty("expectedSha256").GetString(),
                CanonicalJsonV1.ComputeActionPayloadSha256(action));
        }

        [Fact]
        public void ArgumentBoundsHash_BindsCanonicalOperationAndArguments()
        {
            using JsonDocument first = JsonDocument.Parse(
                """{"y":22,"x":11}""");
            using JsonDocument equivalent = JsonDocument.Parse(
                """{"x":11,"y":22}""");

            string expected =
                CanonicalJsonV1.ComputeArgumentBoundsSha256(
                    "input.click",
                    first.RootElement);
            string actual =
                CanonicalJsonV1.ComputeArgumentBoundsSha256(
                    "input.click",
                    equivalent.RootElement);
            string differentOperation =
                CanonicalJsonV1.ComputeArgumentBoundsSha256(
                    "input.double_click",
                    equivalent.RootElement);

            Assert.Equal(
                """{"arguments":{"x":11,"y":22},"operation":"input.click"}""",
                CanonicalJsonV1.CreateArgumentBoundsPayload(
                    "input.click",
                    first.RootElement));
            Assert.True(
                CanonicalJsonV1.FixedTimeEqualsSha256(
                    expected.ToLowerInvariant(),
                    actual));
            Assert.False(
                CanonicalJsonV1.FixedTimeEqualsSha256(
                    expected,
                    differentOperation));
            Assert.False(
                CanonicalJsonV1.FixedTimeEqualsSha256(
                    expected,
                    "not-a-hash"));
        }

        [Fact]
        public void InvalidVectors_FailClosed()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument("canonical-json-vectors.v1.json");
            foreach (JsonElement vector in document.RootElement
                         .GetProperty("invalidVectors")
                         .EnumerateArray())
            {
                Assert.Throws<InvalidDataException>(
                    () => CanonicalJsonV1.Canonicalize(vector.GetProperty("input").GetString()));
            }
        }

        [Fact]
        public void DirectUnicode_RemainsUtf8AndIsNotNormalized()
        {
            const string input = "{\"词\":\"夜翼\"}";
            string canonical = CanonicalJsonV1.Canonicalize(input);
            Assert.Equal(input, canonical);
            Assert.Contains("夜翼", Encoding.UTF8.GetString(Encoding.UTF8.GetBytes(canonical)));
        }
    }
}
