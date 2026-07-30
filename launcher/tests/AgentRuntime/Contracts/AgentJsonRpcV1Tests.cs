using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Contracts
{
    public sealed class AgentJsonRpcV1Tests
    {
        [Fact]
        public void MethodRegistryArtifact_MatchesClosedCompiledRegistry()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "method-registry.v1.json");
            Assert.False(
                document.RootElement
                    .GetProperty(
                        "genericActionExecuteWireMethod")
                    .GetBoolean());
            JsonElement methods =
                document.RootElement.GetProperty("methods");
            Assert.Equal(39, methods.GetArrayLength());
            var artifact = methods.EnumerateArray().ToDictionary(
                item => item.GetProperty("name").GetString(),
                StringComparer.Ordinal);
            Assert.Equal(
                AgentMethodsV1.All.Keys.OrderBy(
                    item => item,
                    StringComparer.Ordinal),
                artifact.Keys.OrderBy(
                    item => item,
                    StringComparer.Ordinal));

            foreach ((string name, AgentMethodDefinition compiled)
                in AgentMethodsV1.All)
            {
                JsonElement item = artifact[name];
                JsonElement capability =
                    item.GetProperty("requiredCapability");
                if (compiled.RequiredCapability == null)
                {
                    Assert.Equal(
                        JsonValueKind.Null,
                        capability.ValueKind);
                }
                else
                {
                    Assert.Equal(
                        compiled.RequiredCapability,
                        capability.GetString());
                    Assert.Contains(
                        compiled.RequiredCapability,
                        AgentCapabilitiesV1.All);
                }
                Assert.Equal(
                    compiled.ParameterContract,
                    item.GetProperty(
                        "parameterContract").GetString());
                Assert.Equal(
                    compiled.PreAuthentication,
                    item.GetProperty(
                        "preAuthentication").GetBoolean());
            }

            Assert.DoesNotContain(
                "action.execute",
                artifact.Keys);
            Assert.All(
                AgentCapabilitiesV1.GuiCapabilitySet,
                capability =>
                {
                    Assert.True(
                        artifact.TryGetValue(
                            capability,
                            out JsonElement method));
                    Assert.Equal(
                        capability,
                        method.GetProperty(
                            "requiredCapability").GetString());
                });
        }

        [Fact]
        public void JsonRpcSchemaMethodEnum_MatchesAllThirtyNineMethods()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "json-rpc.v1.schema.json");
            string[] schemaMethods = document.RootElement
                .GetProperty("$defs")
                .GetProperty("method")
                .GetProperty("enum")
                .EnumerateArray()
                .Select(item => item.GetString())
                .OrderBy(
                    item => item,
                    StringComparer.Ordinal)
                .ToArray();
            string[] compiledMethods =
                AgentMethodsV1.All.Keys
                    .OrderBy(
                        item => item,
                        StringComparer.Ordinal)
                    .ToArray();

            Assert.Equal(39, schemaMethods.Length);
            Assert.Equal(compiledMethods, schemaMethods);
        }

        [Fact]
        public void ParameterContractArtifact_MatchesCompiledExactSets()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "parameter-contracts.v1.json");
            JsonElement contracts =
                document.RootElement.GetProperty("contracts");
            Assert.Equal(
                AgentParameterContractsV1.All.Keys
                    .OrderBy(
                        item => item,
                        StringComparer.Ordinal),
                contracts.EnumerateObject()
                    .Select(item => item.Name)
                    .OrderBy(
                        item => item,
                        StringComparer.Ordinal));
            foreach ((
                string name,
                AgentParameterContractDefinition compiled)
                in AgentParameterContractsV1.All)
            {
                JsonElement artifact =
                    contracts.GetProperty(name);
                Assert.Equal(
                    compiled.RequiredProperties.OrderBy(
                        item => item,
                        StringComparer.Ordinal),
                    artifact.GetProperty("required")
                        .EnumerateArray()
                        .Select(item => item.GetString())
                        .OrderBy(
                            item => item,
                            StringComparer.Ordinal));
                Assert.Equal(
                    compiled.OptionalProperties.OrderBy(
                        item => item,
                        StringComparer.Ordinal),
                    artifact.GetProperty("optional")
                        .EnumerateArray()
                        .Select(item => item.GetString())
                        .OrderBy(
                            item => item,
                            StringComparer.Ordinal));
            }

            Assert.Equal(
                ObservationDataScopesV1.All.OrderBy(
                    item => item,
                    StringComparer.Ordinal),
                document.RootElement
                    .GetProperty("observationDataScopes")
                    .EnumerateArray()
                    .Select(item => item.GetString())
                    .OrderBy(
                        item => item,
                        StringComparer.Ordinal));
            Assert.DoesNotContain(
                "frame",
                ObservationDataScopesV1.All);
            Assert.DoesNotContain(
                "structured",
                ObservationDataScopesV1.All);
            Assert.DoesNotContain(
                "uia",
                ObservationDataScopesV1.All);

            foreach (AgentMethodDefinition method
                in AgentMethodsV1.All.Values.Where(
                    item => !item.PreAuthentication))
            {
                Assert.True(
                    AgentParameterContractsV1.TryGet(
                        method.ParameterContract,
                        out _),
                    method.Name);
            }
        }

        [Fact]
        public void EveryRegisteredMethod_HasValidExactParams()
        {
            IReadOnlyDictionary<string, object> samples =
                ValidParameterSamples();
            Assert.Equal(
                AgentMethodsV1.All.Count - 1,
                samples.Count);
            foreach ((string method, object parameters)
                in samples)
            {
                JsonElement value = Element(parameters);
                IReadOnlyList<ContractViolation> errors =
                    AgentJsonRpcValidator.ValidateParameters(
                        method,
                        value);
                Assert.True(
                    errors.Count == 0,
                    method
                    + ": "
                    + string.Join(
                        "; ",
                        errors.Select(
                            item => item.ToString())));

                string raw = value.GetRawText();
                using JsonDocument extra =
                    JsonDocument.Parse(
                        raw.Substring(0, raw.Length - 1)
                        + (raw.Length == 2 ? string.Empty : ",")
                        + "\"unexpected\":true}");
                Assert.Contains(
                    AgentJsonRpcValidator.ValidateParameters(
                        method,
                        extra.RootElement),
                    violation =>
                        violation.Code
                            == "unknown_property");
            }
        }

        [Fact]
        public void ParamsValidator_ClosesGrantAndActionBypasses()
        {
            JsonElement ungrantedWindow = Element(
                new
                {
                    sessionId = Id("session")
                });
            Assert.NotEmpty(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.ListWindows,
                    ungrantedWindow));

            JsonElement legacyScope = Element(
                new
                {
                    sessionId = Id("session"),
                    observationGrantId = Id("grant"),
                    dataScope = "frame"
                });
            Assert.NotEmpty(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.ListWindows,
                    legacyScope));

            JsonElement pixelWindowState = Element(
                new
                {
                    sessionId = Id("session"),
                    observationGrantId = Id("grant"),
                    dataScope =
                        ObservationDataScopesV1.Pixels,
                    targetId = Id("target")
                });
            Assert.Empty(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.GetWindowState,
                    pixelWindowState));
            Assert.Contains(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.GetWindow,
                    pixelWindowState),
                violation =>
                    violation.Path == "$.params.dataScope"
                    && violation.Code == "constant");

            JsonElement unsupportedWindowStateScope = Element(
                new
                {
                    sessionId = Id("session"),
                    observationGrantId = Id("grant"),
                    dataScope =
                        ObservationDataScopesV1.Accessibility,
                    targetId = Id("target")
                });
            Assert.Contains(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.GetWindowState,
                    unsupportedWindowStateScope),
                violation =>
                    violation.Path == "$.params.dataScope"
                    && violation.Code == "enum");

            JsonElement nonPixelCapture = Element(
                new
                {
                    observationGrantId = Id("grant"),
                    sessionId = Id("session"),
                    targetId = Id("target"),
                    dataScope =
                        ObservationDataScopesV1.Accessibility,
                    allowValidatedFlashKeyframeFallback = false
                });
            Assert.Contains(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentMethodsV1.ObservationCapture,
                    nonPixelCapture),
                violation =>
                    violation.Path == "$.params.dataScope"
                    && violation.Code
                        == "pixels_scope_required");

            JsonElement automaticRenewal = Element(
                new
                {
                    sessionId = Id("session"),
                    kind = "gui_input",
                    capabilities = new[]
                    {
                        AgentCapabilitiesV1.Click
                    },
                    targetScope = new[] { Id("target") },
                    requestedTtlMs = 1000,
                    requestedActionLimit = 1,
                    allowAutomaticRenewal = true
                });
            Assert.Contains(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.LeaseAcquire,
                    automaticRenewal),
                violation =>
                    violation.Code
                        == "unknown_property");

            JsonElement boundedLease = Element(
                new
                {
                    sessionId = Id("session"),
                    kind = "gui_input",
                    capabilities = new[]
                    {
                        AgentCapabilitiesV1.Click
                    },
                    targetScope = new[] { Id("target") },
                    requestedTtlMs = 1000,
                    requestedActionLimit = 1,
                    argumentBoundsHash =
                        new string('A', 64)
                });
            Assert.Empty(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.LeaseAcquire,
                    boundedLease));

            JsonElement shutdownLease = Element(
                new
                {
                    sessionId = Id("session"),
                    kind = "shutdown",
                    capabilities = new[]
                    {
                        AgentCapabilitiesV1
                            .SessionShutdown
                    },
                    targetScope =
                        new[] { Id("target") },
                    requestedTtlMs = 30_000,
                    requestedActionLimit = 1
                });
            Assert.Empty(
                AgentJsonRpcValidator
                    .ValidateParameters(
                        AgentCapabilitiesV1
                            .LeaseAcquire,
                        shutdownLease));

            JsonElement guiShutdownLease = Element(
                new
                {
                    sessionId = Id("session"),
                    kind = "gui_input",
                    capabilities = new[]
                    {
                        AgentCapabilitiesV1
                            .SessionShutdown
                    },
                    targetScope =
                        new[] { Id("target") },
                    requestedTtlMs = 1000,
                    requestedActionLimit = 1
                });
            Assert.Contains(
                AgentJsonRpcValidator
                    .ValidateParameters(
                        AgentCapabilitiesV1
                            .LeaseAcquire,
                        guiShutdownLease),
                violation =>
                    violation.Code
                        == "lease_kind_mismatch");

            JsonElement widenedShutdownLease = Element(
                new
                {
                    sessionId = Id("session"),
                    kind = "shutdown",
                    capabilities = new[]
                    {
                        AgentCapabilitiesV1
                            .SessionShutdown,
                        AgentCapabilitiesV1.Click
                    },
                    targetScope = new[]
                    {
                        Id("target"),
                        Id("other-target")
                    },
                    requestedTtlMs = 30_001,
                    requestedActionLimit = 2
                });
            var shutdownViolations =
                AgentJsonRpcValidator
                    .ValidateParameters(
                        AgentCapabilitiesV1
                            .LeaseAcquire,
                        widenedShutdownLease);
            Assert.Contains(
                shutdownViolations,
                violation => violation.Path
                    == "$.params.capabilities");
            Assert.Contains(
                shutdownViolations,
                violation => violation.Path
                    == "$.params.targetScope");
            Assert.Contains(
                shutdownViolations,
                violation => violation.Path
                    == "$.params.requestedTtlMs");
            Assert.Contains(
                shutdownViolations,
                violation => violation.Path
                    == "$.params.requestedActionLimit");

            JsonElement malformedBounds = Element(
                new
                {
                    sessionId = Id("session"),
                    kind = "gui_input",
                    capabilities = new[]
                    {
                        AgentCapabilitiesV1.Click
                    },
                    targetScope = new[] { Id("target") },
                    requestedTtlMs = 1000,
                    requestedActionLimit = 1,
                    argumentBoundsHash =
                        new string('Z', 64)
                });
            Assert.Contains(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.LeaseAcquire,
                    malformedBounds),
                violation =>
                    violation.Path
                        == "$.params.argumentBoundsHash"
                    && violation.Code == "sha256");

            JsonElement revokeReason = Element(
                new
                {
                    observationGrantId = Id("grant"),
                    reason = "client text"
                });
            Assert.Contains(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentMethodsV1.ObservationGrantRevoke,
                    revokeReason),
                violation =>
                    violation.Code
                        == "unknown_property");

            JsonElement firstGrantByKind = Element(
                new
                {
                    lifecycleRef = Id("lifecycle"),
                    targetKinds = new[] { "flash" },
                    dataScopes = new[]
                    {
                        ObservationDataScopesV1.WindowMetadata
                    },
                    requestedTtlMs = 1000,
                    allowEphemeralKeyframes = false,
                    allowPersistence = false,
                    allowExport = false
                });
            Assert.Empty(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentMethodsV1.ObservationGrantIssue,
                    firstGrantByKind));

            JsonElement ambiguousGrantTarget = Element(
                new
                {
                    lifecycleRef = Id("lifecycle"),
                    targetIds = new[] { Id("target") },
                    targetKinds = new[] { "flash" },
                    dataScopes = new[]
                    {
                        ObservationDataScopesV1.WindowMetadata
                    },
                    requestedTtlMs = 1000,
                    allowEphemeralKeyframes = false,
                    allowPersistence = false,
                    allowExport = false
                });
            Assert.Contains(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentMethodsV1.ObservationGrantIssue,
                    ambiguousGrantTarget),
                violation =>
                    violation.Code
                        == "target_selector_exclusive");

            var wrongArguments =
                (Dictionary<string, object>)Action(
                    AgentCapabilitiesV1.TypeText);
            wrongArguments["arguments"] =
                new Dictionary<string, object>
                {
                    ["text"] = "ok",
                    ["script"] = "not allowed"
                };
            Assert.Contains(
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.TypeText,
                    Element(wrongArguments)),
                violation =>
                    violation.Path
                        == "$.params.arguments.script"
                    && violation.Code
                        == "unknown_property");
        }

        [Fact]
        public void RpcVectors_ExerciseValidAndInvalidMessages()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "rpc-vectors.v1.json");
            AssertVectors(
                document.RootElement.GetProperty(
                    "validRequests"),
                AgentJsonRpcValidator.ValidateRequest,
                valid: true);
            AssertVectors(
                document.RootElement.GetProperty(
                    "invalidRequests"),
                AgentJsonRpcValidator.ValidateRequest,
                valid: false);
            AssertVectors(
                document.RootElement.GetProperty(
                    "validResponses"),
                AgentJsonRpcValidator.ValidateResponse,
                valid: true);
            AssertVectors(
                document.RootElement.GetProperty(
                    "invalidResponses"),
                AgentJsonRpcValidator.ValidateResponse,
                valid: false);
        }

        [Theory]
        [InlineData("\\uD83D")]
        [InlineData("\\uDE00")]
        public void TypeTextContractRejectsIsolatedSurrogate(
            string escapedSurrogate)
        {
            string json = JsonSerializer.Serialize(
                    Action(AgentCapabilitiesV1.TypeText))
                .Replace(
                    "\"hello\"",
                    "\"" + escapedSurrogate + "\"",
                    StringComparison.Ordinal);
            using JsonDocument document =
                JsonDocument.Parse(json);

            IReadOnlyList<ContractViolation> violations =
                AgentJsonRpcValidator.ValidateParameters(
                    AgentCapabilitiesV1.TypeText,
                    document.RootElement);

            Assert.Contains(
                violations,
                violation =>
                    violation.Path
                        == "$.params.arguments.text"
                    && violation.Code
                        == "string_range");
        }

        [Fact]
        public void RequestValidator_RejectsDuplicatePropertiesRecursively()
        {
            using JsonDocument document = JsonDocument.Parse(
                "{\"jsonrpc\":\"2.0\",\"id\":\"x\","
                + "\"method\":\"session.status\","
                + "\"params\":{\"value\":1,\"value\":2}}");
            Assert.Contains(
                AgentJsonRpcValidator.ValidateRequest(
                    document.RootElement),
                violation =>
                    violation.Code == "duplicate");
        }

        [Fact]
        public void BinaryVectors_RoundTripOrFailClosed()
        {
            using JsonDocument document =
                ContractFixture.ReadDocument(
                    "rpc-vectors.v1.json");
            foreach (JsonElement vector
                in document.RootElement
                    .GetProperty("validBinaryChunks")
                    .EnumerateArray())
            {
                BinaryChunkMetadata metadata =
                    ContractFixture.Deserialize<
                        BinaryChunkMetadata>(
                        vector.GetProperty("metadata"));
                byte[] content = Convert.FromBase64String(
                    vector.GetProperty(
                        "contentBase64").GetString());
                byte[] encoded =
                    BinaryChunkCodecV1.Encode(
                        metadata,
                        content);
                Assert.True(
                    encoded.Length
                    <= AgentProtocolV1
                        .MaximumBinaryChunkBytes);
                DecodedBinaryChunk decoded =
                    BinaryChunkCodecV1.Decode(encoded);
                Assert.Equal(
                    metadata.Handle,
                    decoded.Metadata.Handle);
                Assert.Equal(
                    metadata.Offset,
                    decoded.Metadata.Offset);
                Assert.Equal(
                    metadata.TotalLength,
                    decoded.Metadata.TotalLength);
                Assert.Equal(
                    metadata.Final,
                    decoded.Metadata.Final);
                Assert.Equal(
                    metadata.ContentHash,
                    decoded.Metadata.ContentHash);
                Assert.Equal(content, decoded.Content);
            }

            foreach (JsonElement vector
                in document.RootElement
                    .GetProperty("invalidBinaryChunks")
                    .EnumerateArray())
            {
                BinaryChunkMetadata metadata =
                    ContractFixture.Deserialize<
                        BinaryChunkMetadata>(
                        vector.GetProperty("metadata"));
                byte[] content = Convert.FromBase64String(
                    vector.GetProperty(
                        "contentBase64").GetString());
                Assert.Throws<InvalidDataException>(
                    () => BinaryChunkCodecV1.Encode(
                        metadata,
                        content));
            }
        }

        [Fact]
        public void BinaryDecoder_RejectsUnknownOrDuplicateHeaderMembers()
        {
            const string duplicate =
                "{\"handle\":\"EEEEEEEEEEEEEEEEEEEEEE\","
                + "\"offset\":0,\"offset\":0,"
                + "\"totalLength\":0,\"final\":true,"
                + "\"contentHash\":"
                + "\"e3b0c44298fc1c149afbf4c8996fb924"
                + "27ae41e4649b934ca495991b7852b855\"}";
            byte[] payload = MakeRawBinaryPayload(
                duplicate,
                Array.Empty<byte>());
            Assert.Throws<InvalidDataException>(
                () => BinaryChunkCodecV1.Decode(payload));
        }

        [Fact]
        public void BinaryCapacity_IncludesPrefixAndEncodedHeader()
        {
            var metadata = new BinaryChunkMetadata
            {
                Handle = "EEEEEEEEEEEEEEEEEEEEEE",
                Offset = 0,
                TotalLength = 1,
                Final = true,
                ContentHash =
                    "ca978112ca1bbdcafac231b39a23dc4d"
                    + "a786eff8147c4e72b9807785afee48bb"
            };
            int metadataLength =
                JsonSerializer.SerializeToUtf8Bytes(
                    metadata,
                    AgentProtocolV1.JsonOptions).Length;
            Assert.Equal(
                AgentProtocolV1.MaximumBinaryChunkBytes,
                AgentProtocolV1
                    .BinaryChunkMetadataLengthBytes
                + metadataLength
                + BinaryChunkCodecV1
                    .MaximumDataBytesForMetadata(
                        metadataLength));
        }

        private static void AssertVectors(
            JsonElement vectors,
            Func<JsonElement,
                IReadOnlyList<ContractViolation>>
                validator,
            bool valid)
        {
            foreach (JsonElement vector
                in vectors.EnumerateArray())
            {
                IReadOnlyList<ContractViolation> errors =
                    validator(
                        vector.GetProperty("value"));
                if (valid)
                {
                    Assert.True(
                        errors.Count == 0,
                        vector.GetProperty("name").GetString()
                        + ": "
                        + string.Join(
                            "; ",
                            errors.Select(
                                item => item.ToString())));
                }
                else
                {
                    Assert.True(
                        errors.Count > 0,
                        vector.GetProperty("name").GetString());
                }
            }
        }

        private static byte[] MakeRawBinaryPayload(
            string metadata,
            byte[] content)
        {
            byte[] header = Encoding.UTF8.GetBytes(metadata);
            byte[] payload = new byte[
                AgentProtocolV1
                    .BinaryChunkMetadataLengthBytes
                + header.Length
                + content.Length];
            payload[0] = (byte)header.Length;
            payload[1] = (byte)(header.Length >> 8);
            payload[2] = (byte)(header.Length >> 16);
            payload[3] = (byte)(header.Length >> 24);
            Buffer.BlockCopy(
                header,
                0,
                payload,
                AgentProtocolV1
                    .BinaryChunkMetadataLengthBytes,
                header.Length);
            Buffer.BlockCopy(
                content,
                0,
                payload,
                AgentProtocolV1
                    .BinaryChunkMetadataLengthBytes
                + header.Length,
                content.Length);
            return payload;
        }

        private static IReadOnlyDictionary<string, object>
            ValidParameterSamples()
        {
            var samples =
                new Dictionary<string, object>(
                    StringComparer.Ordinal)
                {
                    [AgentCapabilitiesV1.ListWindows] =
                        WindowParams(false),
                    [AgentCapabilitiesV1.GetWindow] =
                        WindowParams(true),
                    [AgentCapabilitiesV1.ListApps] =
                        new Dictionary<string, object>(),
                    [AgentCapabilitiesV1.LaunchApp] =
                        new
                        {
                            launchRequestId = Id("launch"),
                            entryPoint = "standard_entry",
                            runtimeMode = "formal_runtime"
                        },
                    [AgentCapabilitiesV1.GetWindowState] =
                        WindowParams(true),
                    [AgentCapabilitiesV1.SessionStatus] =
                        new Dictionary<string, object>(),
                    [AgentCapabilitiesV1.SessionDiscover] =
                        new Dictionary<string, object>(),
                    [AgentCapabilitiesV1.SessionAttach] =
                        new
                        {
                            sessionId = Id("session"),
                            lifecycleGeneration = 1
                        },
                    [AgentCapabilitiesV1.SessionDetach] =
                        new
                        {
                            sessionId = Id("session"),
                            lifecycleGeneration = 1
                        },
                    [AgentCapabilitiesV1.LeaseAcquire] =
                        new
                        {
                            sessionId = Id("session"),
                            kind = "gui_input",
                            capabilities = new[]
                            {
                                AgentCapabilitiesV1.Click
                            },
                            targetScope =
                                new[] { Id("target") },
                            requestedTtlMs = 1000,
                            requestedActionLimit = 1
                        },
                    [AgentCapabilitiesV1.LeaseRenew] =
                        new
                        {
                            leaseId = Id("lease"),
                            requestedTtlMs = 1000
                        },
                    [AgentCapabilitiesV1.LeaseRelease] =
                        new
                        {
                            leaseId = Id("lease")
                        },
                    [AgentCapabilitiesV1.TraceExport] =
                        new
                        {
                            sessionId = Id("session"),
                            observationGrantId = Id("grant"),
                            consentPurpose =
                                AgentCapabilitiesV1.Click,
                            fromServerSequence = 0,
                            maximumRecords = 100,
                            format = "jsonl"
                        },
                    [AgentMethodsV1.ObservationGrantIssue] =
                        new
                        {
                            lifecycleRef = Id("lifecycle"),
                            targetIds =
                                new[] { Id("target") },
                            dataScopes = new[]
                            {
                                ObservationDataScopesV1.Pixels
                            },
                            requestedTtlMs = 1000,
                            allowEphemeralKeyframes = false,
                            allowPersistence = false,
                            allowExport = false
                        },
                    [AgentMethodsV1.ObservationGrantRevoke] =
                        new
                        {
                            observationGrantId = Id("grant")
                        },
                    [AgentMethodsV1.ObservationCapture] =
                        new
                        {
                            observationGrantId = Id("grant"),
                            sessionId = Id("session"),
                            targetId = Id("target"),
                            dataScope =
                                ObservationDataScopesV1.Pixels,
                            allowValidatedFlashKeyframeFallback =
                                false
                        },
                    [AgentMethodsV1.ObservationGet] =
                        ObservationReference(),
                    [AgentMethodsV1.ObservationAck] =
                        ObservationReference(),
                    [AgentMethodsV1.ContentRead] =
                        new
                        {
                            handle = Id("handle"),
                            offset = 0,
                            count = 1024
                        },
                    [AgentMethodsV1.ActionGet] =
                        new
                        {
                            sessionId = Id("session"),
                            actionId = Id("action")
                        },
                    [AgentMethodsV1.HairInspect] =
                        HairInspect(),
                    [AgentMethodsV1.HairPreview] =
                        HairPreview(),
                    [AgentMethodsV1.HairConsent] =
                        new
                        {
                            observationGrantId = Id("grant"),
                            targetId = Id("target"),
                            sessionId = Id("session"),
                            lifecycleGeneration = 1,
                            transactionId = Id("hairtx"),
                            previewHash = new string('c', 64)
                        },
                    [AgentMethodsV1.HairReconcile] =
                        new
                        {
                            observationGrantId = Id("grant"),
                            targetId = Id("target"),
                            transactionId = Id("hairtx")
                        }
                };
            foreach (string method in new[]
                     {
                         AgentCapabilitiesV1.Click,
                         AgentCapabilitiesV1.PressKey,
                         AgentCapabilitiesV1.TypeText,
                         AgentCapabilitiesV1.Scroll,
                         AgentCapabilitiesV1.SetValue,
                         AgentCapabilitiesV1.Drag,
                         AgentCapabilitiesV1
                             .PerformSecondaryAction,
                         AgentCapabilitiesV1.ActivateWindow,
                         AgentCapabilitiesV1.SessionShutdown,
                         AgentCapabilitiesV1.LifecycleReveal,
                         AgentCapabilitiesV1.LifecycleCancel,
                         AgentCapabilitiesV1.PanelOpen,
                         AgentMethodsV1.HairCommit,
                         AgentMethodsV1.HairRestore
                     })
            {
                samples[method] = Action(method);
            }
            return samples;
        }

        private static object WindowParams(
            bool includeTarget)
        {
            var value = new Dictionary<string, object>
            {
                ["sessionId"] = Id("session"),
                ["observationGrantId"] = Id("grant"),
                ["dataScope"] =
                    ObservationDataScopesV1.WindowMetadata
            };
            if (includeTarget)
            {
                value["targetId"] = Id("target");
            }
            return value;
        }

        private static object ObservationReference()
        {
            return new
            {
                observationGrantId = Id("grant"),
                sessionId = Id("session"),
                observationId = Id("observation")
            };
        }

        private static object HairInspect()
        {
            return new
            {
                observationGrantId = Id("grant"),
                targetId = Id("target"),
                binding = HairBinding()
            };
        }

        private static object HairPreview()
        {
            return new
            {
                observationGrantId = Id("grant"),
                targetId = Id("target"),
                binding = HairBinding(),
                hairIdentifier = "short_hair",
                expectedCurrentHair = "default_hair",
                expectedRevision = 1,
                expectedGeneration = 1,
                expectedSnapshotHash =
                    new string('a', 64)
            };
        }

        private static object HairBinding()
        {
            return new
            {
                sessionId = Id("session"),
                lifecycleGeneration = 1,
                attemptId = Id("attempt"),
                attemptGeneration = 1,
                slotId = "slot-1",
                saveSignature = new string('b', 64)
            };
        }

        private static object Action(string method)
        {
            var action = new Dictionary<string, object>
            {
                ["actionId"] = Id("action"),
                ["idempotencyKey"] = Id("idempotency"),
                ["deadlineMs"] = 1000,
                ["sessionId"] = Id("session"),
                ["observationGrantId"] = Id("grant"),
                ["leaseId"] = Id("lease"),
                ["observationId"] = Id("observation"),
                ["expectedLifecycleGeneration"] = 1,
                ["targetId"] = Id("target"),
                ["expectedSurfaceEpoch"] = 1,
                ["expectedCoordinateSpaceVersion"] = 1,
                ["expectedFocusEpoch"] = 1,
                ["expectedModalEpoch"] = 1,
                ["operation"] = method,
                ["reason"] = "contract test"
            };
            switch (method)
            {
                case AgentCapabilitiesV1.Click:
                    action["frameId"] = Id("frame");
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["coordinateSpace"] =
                                "observation_px",
                            ["x"] = 10,
                            ["y"] = 20,
                            ["button"] = "primary",
                            ["clickCount"] = 1
                        };
                    break;
                case AgentCapabilitiesV1.PressKey:
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["key"] = "A",
                            ["modifiers"] =
                                new[] { "ctrl" },
                            ["repeat"] = 1
                        };
                    break;
                case AgentCapabilitiesV1.TypeText:
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["text"] = "hello"
                        };
                    break;
                case AgentCapabilitiesV1.Scroll:
                    action["frameId"] = Id("frame");
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["coordinateSpace"] =
                                "observation_px",
                            ["x"] = 10,
                            ["y"] = 20,
                            ["deltaX"] = 0,
                            ["deltaY"] = 120
                        };
                    break;
                case AgentCapabilitiesV1.SetValue:
                    SemanticBinding(action);
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["value"] = "value"
                        };
                    break;
                case AgentCapabilitiesV1.Drag:
                    action["frameId"] = Id("frame");
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["coordinateSpace"] =
                                "observation_px",
                            ["startX"] = 1,
                            ["startY"] = 2,
                            ["endX"] = 3,
                            ["endY"] = 4,
                            ["durationMs"] = 100
                        };
                    break;
                case AgentCapabilitiesV1
                    .PerformSecondaryAction:
                    SemanticBinding(action);
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["action"] = "expand"
                        };
                    break;
                case AgentCapabilitiesV1.PanelOpen:
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["panel"] = "hairdresser"
                        };
                    break;
                case AgentMethodsV1.HairCommit:
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["transactionId"] = Id("hairtx"),
                            ["previewHash"] =
                                new string('c', 64),
                            ["consentToken"] =
                                "consent-token"
                        };
                    break;
                case AgentMethodsV1.HairRestore:
                    action["arguments"] =
                        new Dictionary<string, object>
                        {
                            ["transactionId"] = Id("hairtx"),
                            ["restoreToken"] =
                                "restore-token"
                        };
                    break;
                default:
                    action["arguments"] =
                        new Dictionary<string, object>();
                    break;
            }
            return action;
        }

        private static void SemanticBinding(
            IDictionary<string, object> action)
        {
            action["nodeId"] = Id("node");
            action["semanticSnapshotId"] =
                Id("semantic");
            action["expectedSemanticGeneration"] = 1;
        }

        private static JsonElement Element(object value)
        {
            return JsonSerializer.SerializeToElement(
                value,
                AgentProtocolV1.JsonOptions);
        }

        private static string Id(string seed)
        {
            string normalized =
                new string(
                    seed.Where(char.IsLetterOrDigit)
                        .Select(char.ToUpperInvariant)
                        .DefaultIfEmpty('X')
                        .ToArray());
            return string.Concat(
                Enumerable.Repeat(
                    normalized,
                    22 / normalized.Length + 1))
                .Substring(0, 22);
        }
    }
}
