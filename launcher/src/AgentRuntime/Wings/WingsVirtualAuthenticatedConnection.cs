using System;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Wings
{
    /// <summary>
    /// In-process Wings transport boundary. It deliberately replays the
    /// external Gateway's closed-method/parameter validation, capability
    /// check, per-connection scheduler and two authoritative revocation
    /// checks before entering the shared method dispatcher.
    /// </summary>
    internal sealed class WingsVirtualAuthenticatedConnection
        : IAsyncDisposable,
          IDisposable
    {
        private readonly object _sync = new object();
        private readonly IAgentConnectionResourceAuthority
            _resources;
        private readonly IAgentRuntimeMethodDispatcher
            _dispatcher;
        private readonly AgentRequestScheduler _scheduler;
        private readonly CancellationTokenSource
            _connectionCancellation =
                new CancellationTokenSource();
        private string _forcedTerminationReason;
        private bool _disposed;

        internal WingsVirtualAuthenticatedConnection(
            PrincipalCredential principal,
            IAgentConnectionResourceAuthority resources,
            IAgentRuntimeMethodDispatcher dispatcher,
            IAgentRuntimeClock clock)
        {
            Principal = principal
                ?? throw new ArgumentNullException(
                    nameof(principal));
            if (principal.PrincipalKind
                    != AgentPrincipalKind.WingsPersona
                || principal.SessionMode
                    != AgentSessionMode.PlayerAssist
                || principal.State
                    != CredentialState.Active
                || string.IsNullOrWhiteSpace(
                    principal.SelectedSessionId))
            {
                throw new InvalidOperationException(
                    "wings_virtual_principal_invalid");
            }
            _resources = resources
                ?? throw new ArgumentNullException(
                    nameof(resources));
            _dispatcher = dispatcher
                ?? throw new ArgumentNullException(
                    nameof(dispatcher));
            _scheduler = new AgentRequestScheduler(
                clock
                    ?? throw new ArgumentNullException(
                        nameof(clock)));
            ConnectionId =
                OpaqueIdGenerator.Create("wconn");
            try
            {
                _resources.RegisterConnection(
                    ConnectionId,
                    Principal,
                    Terminate);
            }
            catch
            {
                _scheduler.Dispose();
                _connectionCancellation.Dispose();
                throw;
            }
        }

        internal PrincipalCredential Principal { get; }
        internal string ConnectionId { get; }

        public Task<AgentRuntimeDispatchResult> DispatchAsync(
            string method,
            JsonElement parameters,
            CancellationToken cancellationToken)
        {
            return DispatchCoreAsync(
                method,
                parameters,
                null,
                cancellationToken);
        }

        internal Task<AgentRuntimeDispatchResult>
            DispatchLeaseAcquireAsync(
                WingsActionIntentV1 intent,
                LeaseAcquireParametersV1 parameters,
                CancellationToken cancellationToken)
        {
            if (!TryValidateTrustedLeaseRequest(
                    intent,
                    parameters))
            {
                return Task.FromResult(
                    AgentRuntimeDispatchResult.Rejected(
                        "argument_bounds_invalid"));
            }
            return DispatchCoreAsync(
                AgentCapabilitiesV1.LeaseAcquire,
                JsonSerializer.SerializeToElement(
                    parameters,
                    AgentProtocolV1.JsonOptions),
                intent.ArgumentBoundsHash,
                cancellationToken);
        }

        private async Task<AgentRuntimeDispatchResult>
            DispatchCoreAsync(
                string method,
                JsonElement parameters,
                string hostAttestedArgumentBoundsHash,
                CancellationToken cancellationToken)
        {
            if (string.IsNullOrWhiteSpace(method))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "operation_invalid");
            }
            if (parameters.ValueKind
                != JsonValueKind.Object)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "arguments_invalid");
            }
            lock (_sync)
            {
                if (_disposed)
                {
                    return AgentRuntimeDispatchResult
                        .Rejected("credential_revoked");
                }
            }

            var request = new AgentJsonRpcRequest
            {
                Id = OpaqueIdGenerator.Create("wrpc"),
                Method = method,
                Params = parameters.Clone()
            };
            JsonElement root =
                JsonSerializer.SerializeToElement(
                    request,
                    AgentProtocolV1.JsonOptions);
            var violations =
                AgentJsonRpcValidator.ValidateRequest(root);
            if (violations.Count != 0)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    NormalizeValidationReason(
                        violations[0]));
            }
            if (string.Equals(
                    method,
                    AgentMethodsV1.RuntimeHello,
                    StringComparison.Ordinal)
                || !AgentMethodsV1.TryGet(
                    method,
                    out AgentMethodDefinition definition)
                || definition.PreAuthentication)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "operation_invalid");
            }
            if (!Principal.AllowsCapability(
                    definition.RequiredCapability))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "capability_denied");
            }
            if (!_resources.IsDispatchAuthorized(
                    ConnectionId,
                    Principal))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    ForcedReason());
            }

            using var callerLinked =
                CancellationTokenSource
                    .CreateLinkedTokenSource(
                        cancellationToken,
                        _connectionCancellation.Token);
            int deadlineMs = ReadDeadline(parameters);
            AgentScheduledResult<
                AgentRuntimeDispatchResult> scheduled;
            AgentRuntimeDispatchResult dispatched = null;
            try
            {
                scheduled = await _scheduler.ExecuteAsync(
                        deadlineMs,
                        async token =>
                        {
                            if (token.IsCancellationRequested
                                || !_resources
                                    .IsDispatchAuthorized(
                                        ConnectionId,
                                        Principal))
                            {
                                return AgentRuntimeDispatchResult
                                    .Rejected(
                                        ForcedReason());
                            }
                            dispatched =
                                await _dispatcher.DispatchAsync(
                                        new AgentRuntimeDispatchContext(
                                            ConnectionId,
                                            Principal,
                                            hostAttestedArgumentBoundsHash),
                                        request,
                                        token)
                                    .ConfigureAwait(false);
                            return dispatched;
                        },
                        callerLinked.Token)
                    .ConfigureAwait(false);
            }
            catch (ObjectDisposedException)
            {
                dispatched?.ResponseCompletion?.Abort();
                return AgentRuntimeDispatchResult.Rejected(
                    ForcedReason());
            }
            if (!scheduled.Success)
            {
                dispatched?.ResponseCompletion?.Abort();
                if (scheduled.ReasonCode
                        == "connection_cancelled"
                    && !_connectionCancellation
                        .IsCancellationRequested)
                {
                    return AgentRuntimeDispatchResult.Rejected(
                        "internal_error");
                }
                return AgentRuntimeDispatchResult.Rejected(
                    scheduled.ReasonCode
                        == "connection_cancelled"
                            ? ForcedReason()
                            : AgentRuntimeGateway
                                .NormalizeReason(
                                    scheduled
                                        .ReasonCode));
            }
            AgentRuntimeDispatchResult result =
                scheduled.Value
                ?? AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            AgentRuntimeResponseCompletion completion =
                result.ResponseCompletion;
            if (!result.Success)
            {
                completion?.Abort();
                return result;
            }
            if (callerLinked.IsCancellationRequested
                || !_resources.IsDispatchAuthorized(
                    ConnectionId,
                    Principal))
            {
                completion?.Abort();
                return AgentRuntimeDispatchResult.Rejected(
                    ForcedReason());
            }
            if (completion != null
                && !completion.TryPrepareWrite())
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "response_delivery_not_authorized");
            }
            completion?.CommitAfterWrite();
            return result;
        }

        private bool TryValidateTrustedLeaseRequest(
            WingsActionIntentV1 intent,
            LeaseAcquireParametersV1 parameters)
        {
            if (intent == null
                || parameters == null
                || !string.Equals(
                    Principal.SelectedSessionId,
                    intent.SessionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    parameters.SessionId,
                    intent.SessionId,
                    StringComparison.Ordinal)
                || !CanonicalJsonV1.FixedTimeEqualsSha256(
                    intent.ArgumentBoundsHash,
                    parameters.ArgumentBoundsHash)
                || parameters.RequestedActionLimit != 1
                || parameters.TargetScope == null
                || parameters.TargetScope.Count != 1
                || !string.Equals(
                    parameters.TargetScope[0],
                    intent.TargetId,
                    StringComparison.Ordinal)
                || parameters.Capabilities == null
                || parameters.Capabilities.Count != 1
                || !AgentMethodsV1.TryGet(
                    intent.Operation,
                    out AgentMethodDefinition method)
                || !string.Equals(
                    parameters.Capabilities[0],
                    method.RequiredCapability,
                    StringComparison.Ordinal)
                || !PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        Principal,
                        parameters.ConsentReceipt))
            {
                return false;
            }

            if (intent.LeaseKind
                == WingsActionLeaseKind.GuiInput)
            {
                return string.Equals(
                        parameters.Kind,
                        "gui_input",
                        StringComparison.Ordinal)
                    && parameters.PreviewHash == null
                    && parameters.ExpectedRevision == null
                    && parameters.Operation == null;
            }

            return string.Equals(
                    parameters.Kind,
                    "domain_transaction",
                    StringComparison.Ordinal)
                && string.Equals(
                    parameters.Operation,
                    intent.Operation,
                    StringComparison.Ordinal)
                && intent.HairBinding != null
                && string.Equals(
                    parameters.PreviewHash,
                    intent.HairBinding.PreviewHash,
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    parameters.ExpectedRevision,
                    intent.HairBinding.ExpectedRevision,
                    StringComparison.Ordinal);
        }

        public void Dispose()
        {
            DisposeAsync().AsTask()
                .GetAwaiter()
                .GetResult();
        }

        public ValueTask DisposeAsync()
        {
            return CloseAsync(
                "connection_closed",
                AgentConnectionTerminationKind
                    .CleanDisconnect);
        }

        internal ValueTask RevokeAsync(string reasonCode)
        {
            return CloseAsync(
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "credential_revoked"
                    : AgentRuntimeGateway.NormalizeReason(
                        reasonCode),
                AgentConnectionTerminationKind.Cancelled);
        }

        private async ValueTask CloseAsync(
            string reasonCode,
            AgentConnectionTerminationKind kind)
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                _forcedTerminationReason ??=
                    reasonCode;
            }
            try
            {
                _connectionCancellation.Cancel();
            }
            catch
            {
            }
            _scheduler.Dispose();
            try
            {
                await _resources.RevokeAsync(
                    ConnectionId,
                    new AgentConnectionTermination(
                        kind,
                        reasonCode,
                        null))
                    .ConfigureAwait(false);
            }
            finally
            {
                _connectionCancellation.Dispose();
            }
        }

        private void Terminate(string reasonCode)
        {
            lock (_sync)
            {
                _forcedTerminationReason ??=
                    string.IsNullOrWhiteSpace(reasonCode)
                        ? "credential_revoked"
                        : AgentRuntimeGateway
                            .NormalizeReason(reasonCode);
            }
            try
            {
                _connectionCancellation.Cancel();
            }
            catch
            {
            }
        }

        private string ForcedReason()
        {
            lock (_sync)
            {
                return _forcedTerminationReason
                    ?? "credential_revoked";
            }
        }

        private static int ReadDeadline(
            JsonElement parameters)
        {
            if (parameters.TryGetProperty(
                    "deadlineMs",
                    out JsonElement deadline)
                && deadline.ValueKind
                    == JsonValueKind.Number
                && deadline.TryGetInt32(out int value)
                && value > 0)
            {
                return Math.Min(
                    value,
                    AgentProtocolV1
                        .MaximumActionDeadlineMs);
            }
            return AgentProtocolV1
                .MaximumActionDeadlineMs;
        }

        private static string NormalizeValidationReason(
            ContractViolation violation)
        {
            if (violation == null)
                return "arguments_invalid";
            if (string.Equals(
                    violation.Code,
                    "rpc_method_not_found",
                    StringComparison.Ordinal))
            {
                return "operation_invalid";
            }
            if (string.Equals(
                    violation.Code,
                    "protocol_version_mismatch",
                    StringComparison.Ordinal))
            {
                return "protocol_version_mismatch";
            }
            return "arguments_invalid";
        }
    }
}
