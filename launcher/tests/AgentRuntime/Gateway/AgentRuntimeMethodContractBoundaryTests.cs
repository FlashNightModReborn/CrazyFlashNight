using System;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentRuntimeMethodContractBoundaryTests
    {
        [Fact]
        public void ExactParameterContractRejectsUnknownProperties()
        {
            JsonElement parameters =
                JsonSerializer.SerializeToElement(
                    new
                    {
                        sessionId =
                            "session_AAAAAAAAAAAAAAA",
                        lifecycleGeneration = 1,
                        callerChosenHwnd = 1234
                    });

            var violations =
                AgentMethodParameterValidatorV1.Validate(
                    AgentCapabilitiesV1.SessionAttach,
                    parameters);

            Assert.Contains(
                violations,
                violation =>
                    violation.Path
                        == "$.params.callerChosenHwnd"
                    && violation.Code
                        == "unknown_property");
        }

        [Fact]
        public async Task UnwiredHostMethodFailsClosed()
        {
            var service =
                new FailClosedAgentRuntimeHostMethodService();
            AgentRuntimeDispatchResult result =
                await service.DispatchAsync(
                    Context(),
                    Request(
                        AgentCapabilitiesV1.LaunchApp,
                        new
                        {
                            appId = "cf7.flash_night"
                        }),
                    CancellationToken.None);

            Assert.False(result.Success);
            Assert.Equal(
                "unsupported_for_surface",
                result.ReasonCode);
        }

        [Fact]
        public void FailClosedLeaseLifecycleNeverActivatesGuiInput()
        {
            var lifecycle =
                new FailClosedAgentWriteLeaseLifecycle();
            WriteLease guiLease = Lease(WriteLeaseKind.GuiInput);
            WriteLease domainLease =
                Lease(WriteLeaseKind.DomainTransaction);
            WriteLease structuredLease =
                Lease(WriteLeaseKind.StructuredAction);
            WriteLease shutdownLease =
                Lease(WriteLeaseKind.Shutdown);

            Assert.False(lifecycle.TryActivate(
                guiLease,
                out string guiReason));
            Assert.Equal("input_guard_unhealthy", guiReason);
            Assert.True(lifecycle.TryActivate(
                domainLease,
                out string domainReason));
            Assert.Null(domainReason);
            Assert.True(lifecycle.TryActivate(
                structuredLease,
                out string structuredReason));
            Assert.Null(structuredReason);
            Assert.True(lifecycle.TryActivate(
                shutdownLease,
                out string shutdownReason));
            Assert.Null(shutdownReason);
        }

        private static AgentRuntimeDispatchContext Context()
        {
            return new AgentRuntimeDispatchContext(
                "connection_AAAAAAAAAAAAA",
                Principal());
        }

        private static PrincipalCredential Principal()
        {
            return new PrincipalCredential(
                "credential_AAAAAAAAAAAAA",
                "principal_AAAAAAAAAAAAA",
                "client_AAAAAAAAAAAAAAAAA",
                AgentPrincipalKind.DeveloperAgent,
                AgentSessionMode.DeveloperInteractive,
                1,
                0,
                60_000,
                DateTimeOffset.UtcNow,
                new[]
                {
                    AgentCapabilitiesV1.LaunchApp,
                    AgentCapabilitiesV1.Click
                },
                new[] { "target_AAAAAAAAAAAAAAAAA" },
                "test-enrollment",
                null,
                null,
                null,
                null);
        }

        private static WriteLease Lease(WriteLeaseKind kind)
        {
            return new WriteLease(
                "lease_AAAAAAAAAAAAAAAAA",
                Principal(),
                new WriteLeaseRequest
                {
                    SessionId =
                        "session_AAAAAAAAAAAAAAA",
                    LifecycleGeneration = 1,
                    Kind = kind,
                    Capabilities = new[]
                    {
                        AgentCapabilitiesV1.Click
                    },
                    TargetScope = new[]
                    {
                        "target_AAAAAAAAAAAAAAAAA"
                    }
                },
                1,
                10_000,
                1);
        }

        private static AgentJsonRpcRequest Request(
            string method,
            object parameters)
        {
            return new AgentJsonRpcRequest
            {
                Id = "request_AAAAAAAAAAAAAAA",
                Method = method,
                Params = JsonSerializer.SerializeToElement(
                    parameters,
                    AgentProtocolV1.JsonOptions)
            };
        }
    }
}
