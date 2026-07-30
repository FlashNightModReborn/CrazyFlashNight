using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Implements the two host-level v1 methods without accepting a client
    /// path or executable. app.launch binds to the already-running standard
    /// entry. trace.export delegates only to the exact scoped-ledger
    /// exporter; no client path or global-log filtering is accepted.
    /// </summary>
    internal sealed class LauncherAgentRuntimeHostMethodService
        : IAgentRuntimeHostMethodService
    {
        private readonly AppendOnlyAuditSegment _audit;
        private readonly SessionSurfaceHostController _sessions;
        private readonly IMinimalSessionReferenceProvider
            _minimalSessions;
        private readonly AgentRuntimeHostIdentity _identity;
        private readonly ScopedAgentRuntimeTraceExporter
            _traceExporter;

        public LauncherAgentRuntimeHostMethodService(
            string projectRoot,
            IAgentRuntimeClock clock,
            AppendOnlyAuditSegment audit,
            SessionSurfaceHostController sessions,
            IMinimalSessionReferenceProvider minimalSessions,
            ObservationGrantBroker grants,
            AgentRuntimeHostIdentity identity,
            string exportDirectoryOverride = null,
            IAgentRendezvousFileProtection fileProtection = null,
            ScopedAgentRuntimeAuditLedgerManager
                scopedAudit = null,
            Func<string> traceArtifactIdFactory = null)
        {
            if (string.IsNullOrWhiteSpace(projectRoot))
                throw new ArgumentException(
                    "A project root is required.",
                    nameof(projectRoot));
            _ = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _audit = audit
                ?? throw new ArgumentNullException(nameof(audit));
            _sessions = sessions
                ?? throw new ArgumentNullException(nameof(sessions));
            _minimalSessions = minimalSessions
                ?? throw new ArgumentNullException(
                    nameof(minimalSessions));
            _ = grants
                ?? throw new ArgumentNullException(nameof(grants));
            _identity = identity
                ?? throw new ArgumentNullException(nameof(identity));
            if (scopedAudit != null)
            {
                string directory =
                    exportDirectoryOverride
                    ?? Path.Combine(
                        Path.GetFullPath(projectRoot),
                        ".openai",
                        "agent-runtime",
                        "exports");
                _traceExporter =
                    new ScopedAgentRuntimeTraceExporter(
                        scopedAudit,
                        grants,
                        sessions,
                        directory,
                        fileProtection,
                        artifactIdFactory:
                            traceArtifactIdFactory);
            }
        }

        public Task<AgentRuntimeDispatchResult> DispatchAsync(
            AgentRuntimeDispatchContext context,
            AgentJsonRpcRequest request,
            CancellationToken cancellationToken)
        {
            if (context == null)
                throw new ArgumentNullException(nameof(context));
            if (request == null)
                throw new ArgumentNullException(nameof(request));
            if (cancellationToken.IsCancellationRequested)
            {
                return Task.FromResult(
                    AgentRuntimeDispatchResult.Rejected(
                        "deadline_exceeded"));
            }
            if ((request.Method
                        == AgentCapabilitiesV1.LaunchApp
                    || request.Method
                        == AgentCapabilitiesV1.TraceExport)
                && AgentMethodParameterValidatorV1.Validate(
                        request.Method,
                        request.Params)
                    .Count != 0)
            {
                AuditRejected(
                    context,
                    request.Method,
                    "arguments_invalid");
                return Task.FromResult(
                    AgentRuntimeDispatchResult.Rejected(
                        "arguments_invalid"));
            }
            try
            {
                return Task.FromResult(
                    request.Method switch
                    {
                        AgentCapabilitiesV1.LaunchApp =>
                            Launch(
                                context,
                                Read<AppLaunchParametersV1>(
                                    request)),
                        AgentCapabilitiesV1.TraceExport =>
                            ExportTrace(
                                context,
                                Read<TraceExportParametersV1>(
                                    request),
                                cancellationToken),
                        _ => AgentRuntimeDispatchResult.Rejected(
                            "operation_invalid")
                    });
            }
            catch (JsonException)
            {
                AuditRejected(
                    context,
                    request.Method,
                    "arguments_invalid");
                return Task.FromResult(
                    AgentRuntimeDispatchResult.Rejected(
                        "arguments_invalid"));
            }
            catch (ArgumentException)
            {
                AuditRejected(
                    context,
                    request.Method,
                    "arguments_invalid");
                return Task.FromResult(
                    AgentRuntimeDispatchResult.Rejected(
                        "arguments_invalid"));
            }
            catch (OverflowException)
            {
                AuditRejected(
                    context,
                    request.Method,
                    "arguments_invalid");
                return Task.FromResult(
                    AgentRuntimeDispatchResult.Rejected(
                        "arguments_invalid"));
            }
        }

        private AgentRuntimeDispatchResult Launch(
            AgentRuntimeDispatchContext context,
            AppLaunchParametersV1 parameters)
        {
            RuntimeQualificationRegistration current =
                _identity.Qualification;
            if (context.Principal.State
                    != CredentialState.Active
                || !context.Principal.AllowsCapability(
                    AgentCapabilitiesV1.LaunchApp))
            {
                AuditRejected(
                    context,
                    AgentCapabilitiesV1.LaunchApp,
                    "capability_denied");
                return AgentRuntimeDispatchResult.Rejected(
                    "capability_denied");
            }
            if (!string.Equals(
                    parameters.EntryPoint,
                    AgentAppCatalogV1.StandardEntryPoint,
                    StringComparison.Ordinal)
                || !Enum.IsDefined(parameters.RuntimeMode)
                || parameters.RuntimeMode
                    == RuntimeMode.IsolatedCandidate
                    && (string.IsNullOrWhiteSpace(
                            parameters
                                .ExpectedBuildIdentity)
                        || string.IsNullOrWhiteSpace(
                            parameters
                                .ExpectedPayloadClosure)))
            {
                AuditRejected(
                    context,
                    AgentCapabilitiesV1.LaunchApp,
                    "arguments_invalid");
                return AgentRuntimeDispatchResult.Rejected(
                    "arguments_invalid");
            }
            if (parameters.RuntimeMode != current.RuntimeMode)
            {
                AuditRejected(
                    context,
                    AgentCapabilitiesV1.LaunchApp,
                    "runtime_identity_mismatch");
                return AgentRuntimeDispatchResult.Rejected(
                    "runtime_unqualified");
            }
            if (parameters.ExpectedBuildIdentity != null
                && !string.Equals(
                    parameters.ExpectedBuildIdentity,
                    current.BuildIdentity,
                    StringComparison.OrdinalIgnoreCase))
            {
                AuditRejected(
                    context,
                    AgentCapabilitiesV1.LaunchApp,
                    "runtime_identity_mismatch");
                return AgentRuntimeDispatchResult.Rejected(
                    "runtime_unqualified");
            }
            if (parameters.ExpectedPayloadClosure != null
                && !string.Equals(
                    parameters.ExpectedPayloadClosure,
                    current.PayloadClosure,
                    StringComparison.OrdinalIgnoreCase))
            {
                AuditRejected(
                    context,
                    AgentCapabilitiesV1.LaunchApp,
                    "runtime_identity_mismatch");
                return AgentRuntimeDispatchResult.Rejected(
                    "runtime_unqualified");
            }

            SessionSnapshot session = _sessions.Snapshot;
            if (!IdentityMatchesSession(session))
            {
                AuditRejected(
                    context,
                    AgentCapabilitiesV1.LaunchApp,
                    "runtime_session_identity_mismatch");
                return AgentRuntimeDispatchResult.Rejected(
                    "runtime_unqualified");
            }
            if (!TryAppendAudit(
                "host_method_completed",
                new
                {
                    method = AgentCapabilitiesV1.LaunchApp,
                    securityPrincipalId =
                        context.Principal.SecurityPrincipalId,
                    launchRequestId =
                        parameters.LaunchRequestId,
                    sessionId = session.SessionId,
                    lifecycleGeneration =
                        session.LifecycleGeneration,
                    runtimeMode = current.RuntimeMode,
                    alreadyRunning = true
                }))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            return AgentRuntimeDispatchResult.Completed(
                new AppLaunchResultV1
                {
                    LaunchRequestId =
                        parameters.LaunchRequestId,
                    EntryPoint =
                        AgentAppCatalogV1.StandardEntryPoint,
                    Started = false,
                    AlreadyRunning = true,
                    RuntimeMode = current.RuntimeMode,
                    MinimalSessionRef =
                        _minimalSessions
                            .GetMinimalReference()
                });
        }

        private AgentRuntimeDispatchResult ExportTrace(
            AgentRuntimeDispatchContext context,
            TraceExportParametersV1 parameters,
            CancellationToken cancellationToken)
        {
            if (_traceExporter == null)
            {
                AuditRejected(
                    context,
                    AgentCapabilitiesV1.TraceExport,
                    "trace_export_unavailable");
                return AgentRuntimeDispatchResult.Rejected(
                    "unsupported_for_surface");
            }
            return _traceExporter.Export(
                context,
                parameters,
                cancellationToken);
        }

        private void AuditRejected(
            AgentRuntimeDispatchContext context,
            string method,
            string reasonCode)
        {
            TryAppendAudit(
                "host_method_rejected",
                new
                {
                    method,
                    securityPrincipalId =
                        context.Principal.SecurityPrincipalId,
                    sessionId = CurrentSessionId(),
                    reasonCode
                });
        }

        private bool TryAppendAudit<T>(
            string eventType,
            T payload)
        {
            try
            {
                string json = JsonSerializer.Serialize(
                    payload,
                    AgentProtocolV1.JsonOptions);
                _audit.Append(
                    eventType,
                    CanonicalJsonV1.Canonicalize(json));
                return true;
            }
            catch
            {
                return false;
            }
        }

        private bool IdentityMatchesSession(
            SessionSnapshot session)
        {
            if (session?.RuntimeQualification == null)
                return false;
            RuntimeQualificationRegistration expected =
                _identity.Qualification;
            RuntimeQualificationRegistration actual =
                session.RuntimeQualification;
            return expected.RuntimeMode == actual.RuntimeMode
                && EqualIdentity(
                    expected.BuildIdentity,
                    actual.BuildIdentity)
                && EqualIdentity(
                    expected.PayloadClosure,
                    actual.PayloadClosure)
                && string.Equals(
                    expected.UnqualifiedReason,
                    actual.UnqualifiedReason,
                    StringComparison.Ordinal)
                && expected.UnqualifiedDevVisualInputAuthorized
                    == actual
                        .UnqualifiedDevVisualInputAuthorized
                && string.Equals(
                    Path.GetFullPath(
                        expected.ActualProcessPath),
                    Path.GetFullPath(
                        actual.ActualProcessPath),
                    StringComparison.OrdinalIgnoreCase)
                && EqualIdentity(
                    _identity.CoreSha256,
                    session.CoreSha256);
        }

        private string CurrentSessionId()
        {
            try
            {
                return _sessions.Snapshot.SessionId;
            }
            catch
            {
                return null;
            }
        }

        private static bool EqualIdentity(
            string left,
            string right)
        {
            return string.Equals(
                left,
                right,
                StringComparison.OrdinalIgnoreCase);
        }

        private static T Read<T>(
            AgentJsonRpcRequest request)
        {
            return request.Params.Deserialize<T>(
                AgentProtocolV1.JsonOptions)
                ?? throw new JsonException(
                    "request_params_deserialization_failed");
        }
    }
}
