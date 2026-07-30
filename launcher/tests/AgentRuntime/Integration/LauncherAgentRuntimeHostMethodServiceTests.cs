using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.Tests.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class
        LauncherAgentRuntimeHostMethodServiceTests
    {
        [Fact]
        public void AppLaunchBindsAlreadyRunningExactIdentityAndAudits()
        {
            using var setup = new Setup();
            PrincipalCredential principal =
                setup.Developer(
                    AgentCapabilitiesV1.LaunchApp);

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.LaunchApp,
                    setup.LaunchParameters());

            Assert.True(result.Success);
            Assert.False(
                result.Result.GetProperty("started")
                    .GetBoolean());
            Assert.True(
                result.Result.GetProperty("alreadyRunning")
                    .GetBoolean());
            Assert.Equal(
                "standard_entry",
                result.Result.GetProperty("entryPoint")
                    .GetString());
            Assert.Equal(
                setup.Identity.Qualification.RuntimeMode,
                result.Result.GetProperty("runtimeMode")
                    .Deserialize<RuntimeMode>(
                        AgentProtocolV1.JsonOptions));
            Assert.True(
                result.Result.GetProperty("minimalSessionRef")
                    .GetProperty("projectRunning")
                    .GetBoolean());
            Assert.True(
                result.Result.GetProperty("minimalSessionRef")
                    .TryGetProperty("lifecycleRef", out _));
            Assert.Equal(
                new[]
                {
                    "alreadyRunning",
                    "entryPoint",
                    "launchRequestId",
                    "minimalSessionRef",
                    "runtimeMode",
                    "started"
                },
                result.Result.EnumerateObject()
                    .Select(property => property.Name)
                    .OrderBy(name => name, StringComparer.Ordinal)
                    .ToArray());
            Assert.False(
                result.Result.TryGetProperty("session", out _));
            Assert.DoesNotContain(
                "sessionId",
                result.Result.GetRawText(),
                StringComparison.Ordinal);
            Assert.DoesNotContain(
                "launcherPid",
                result.Result.GetRawText(),
                StringComparison.Ordinal);
            AuditEntry audit = Assert.Single(
                setup.Audit.Snapshot());
            Assert.Equal(
                "host_method_completed",
                audit.EventType);
            Assert.Contains(
                principal.SecurityPrincipalId,
                audit.CanonicalPayload,
                StringComparison.Ordinal);
        }

        [Fact]
        public void AppLaunchRejectsCapabilityArgumentsAndIdentityDrift()
        {
            using var setup = new Setup();
            PrincipalCredential denied =
                setup.Developer(
                    AgentCapabilitiesV1.ListApps);
            Assert.Equal(
                "capability_denied",
                setup.Dispatch(
                        denied,
                        AgentCapabilitiesV1.LaunchApp,
                        setup.LaunchParameters())
                    .ReasonCode);

            PrincipalCredential allowed =
                setup.Developer(
                    AgentCapabilitiesV1.LaunchApp);
            AppLaunchParametersV1 badEntry =
                setup.LaunchParameters();
            badEntry.EntryPoint = "arbitrary.exe";
            Assert.Equal(
                "arguments_invalid",
                setup.Dispatch(
                        allowed,
                        AgentCapabilitiesV1.LaunchApp,
                        badEntry)
                    .ReasonCode);

            AppLaunchParametersV1 wrongMode =
                setup.LaunchParameters();
            wrongMode.RuntimeMode =
                wrongMode.RuntimeMode
                    == RuntimeMode.FormalRuntime
                    ? RuntimeMode.UnqualifiedDev
                    : RuntimeMode.FormalRuntime;
            Assert.Equal(
                "runtime_unqualified",
                setup.Dispatch(
                        allowed,
                        AgentCapabilitiesV1.LaunchApp,
                        wrongMode)
                    .ReasonCode);

            setup.ReplaceWithDifferentRuntimeIdentity();
            Assert.Equal(
                "runtime_unqualified",
                setup.Dispatch(
                        allowed,
                        AgentCapabilitiesV1.LaunchApp,
                        setup.LaunchParameters())
                    .ReasonCode);
        }

        [Fact]
        public void AppListEntryPointRoundTripsIntoExactLaunchContract()
        {
            using var setup = new Setup();
            AppDescriptorV1 discovered = Assert.Single(
                AgentAppCatalogV1.CreateList(running: true).Apps);
            Assert.Equal(
                AgentAppCatalogV1.StandardEntryPoint,
                discovered.EntryPoint);

            AppLaunchParametersV1 parameters =
                setup.LaunchParameters();
            parameters.EntryPoint = discovered.EntryPoint;
            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    setup.Developer(
                        AgentCapabilitiesV1.LaunchApp),
                    AgentCapabilitiesV1.LaunchApp,
                    parameters);

            Assert.True(result.Success);
            Assert.Equal(
                discovered.EntryPoint,
                result.Result.GetProperty("entryPoint")
                    .GetString());
        }

        [Fact]
        public void TraceExportRequiresDeveloperAndBothCapabilities()
        {
            using var setup = new Setup();
            PrincipalCredential noMethod =
                setup.Developer("observation.export");
            PrincipalCredential noExportScope =
                setup.Developer(
                    AgentCapabilitiesV1.TraceExport);
            PrincipalCredential wings =
                setup.Player(
                    AgentCapabilitiesV1.TraceExport,
                    "observation.export");

            foreach (PrincipalCredential principal in new[]
            {
                noMethod,
                noExportScope,
                wings
            })
            {
                AgentRuntimeDispatchResult result =
                    setup.Dispatch(
                        principal,
                        AgentCapabilitiesV1.TraceExport,
                        setup.TraceParameters());
                Assert.False(result.Success);
                Assert.Equal(
                    "unsupported_for_surface",
                    result.ReasonCode);
            }
            Assert.False(
                Directory.Exists(setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportRejectsWrongSessionAndInvalidBounds()
        {
            using var setup = new Setup();
            PrincipalCredential principal =
                setup.ExportDeveloper();

            TraceExportParametersV1 wrongSession =
                setup.TraceParameters(principal);
            wrongSession.SessionId = Id("other_session");
            Assert.Equal(
                "unsupported_for_surface",
                setup.Dispatch(
                        principal,
                        AgentCapabilitiesV1.TraceExport,
                        wrongSession)
                    .ReasonCode);

            TraceExportParametersV1 invalid =
                setup.TraceParameters(principal);
            invalid.MaximumRecords = 0;
            Assert.Equal(
                "arguments_invalid",
                setup.Dispatch(
                        principal,
                        AgentCapabilitiesV1.TraceExport,
                        invalid)
                    .ReasonCode);
            Assert.False(
                Directory.Exists(setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportRejectsForgedScopeOwnerAndExpiryWithoutFiles()
        {
            using var setup = new Setup();
            PrincipalCredential owner =
                setup.ExportDeveloper();
            PrincipalCredential other =
                setup.ExportDeveloper();

            TraceExportParametersV1 forged =
                setup.TraceParameters();
            Assert.False(
                setup.Dispatch(
                        owner,
                        AgentCapabilitiesV1.TraceExport,
                        forged)
                    .Success);

            ObservationGrant noScope = setup.IssueGrant(
                owner,
                new[] { ObservationDataScopesV1.Pixels },
                allowExport: false);
            TraceExportParametersV1 missingScope =
                setup.TraceParameters();
            missingScope.ObservationGrantId =
                noScope.ObservationGrantId;
            Assert.False(
                setup.Dispatch(
                        owner,
                        AgentCapabilitiesV1.TraceExport,
                        missingScope)
                    .Success);

            ObservationGrant ownerGrant = setup.IssueGrant(
                owner,
                new[] { ObservationDataScopesV1.DataExport },
                allowExport: true);
            TraceExportParametersV1 crossPrincipal =
                setup.TraceParameters();
            crossPrincipal.ObservationGrantId =
                ownerGrant.ObservationGrantId;
            Assert.False(
                setup.Dispatch(
                        other,
                        AgentCapabilitiesV1.TraceExport,
                        crossPrincipal)
                    .Success);

            ObservationGrant expiring = setup.IssueGrant(
                owner,
                new[] { ObservationDataScopesV1.DataExport },
                allowExport: true,
                lifetime: TimeSpan.FromMilliseconds(1));
            setup.Clock.Advance(TimeSpan.FromMilliseconds(2));
            TraceExportParametersV1 expired =
                setup.TraceParameters();
            expired.ObservationGrantId =
                expiring.ObservationGrantId;
            Assert.False(
                setup.Dispatch(
                        owner,
                        AgentCapabilitiesV1.TraceExport,
                        expired)
                    .Success);

            Assert.False(
                Directory.Exists(setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportFailsClosedUntilScopedLedgerExists()
        {
            using var setup = new Setup();
            PrincipalCredential principal =
                setup.ExportDeveloper();
            setup.AppendAuditPayload(
                new string('x', 2048));

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal));

            Assert.False(
                result.Success);
            Assert.Equal(
                "unsupported_for_surface",
                result.ReasonCode);
            Assert.False(
                Directory.Exists(setup.ExportDirectory));
            Assert.Contains(
                setup.Audit.Snapshot(),
                entry => entry.EventType
                    == "host_method_rejected"
                    && entry.CanonicalPayload.Contains(
                        "trace_export_unavailable",
                        StringComparison.Ordinal));
        }

        [Fact]
        public void TraceExportCannotLeakLargeOrCrossPrincipalAudit()
        {
            using var setup = new Setup();
            PrincipalCredential principal =
                setup.ExportDeveloper();
            string payload = new string('z', 60_000);
            for (int index = 0; index < 150; index++)
                setup.AppendAuditPayload(payload);

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(
                        principal,
                        maximumRecords: 10_000));

            Assert.False(result.Success);
            Assert.Equal(
                "unsupported_for_surface",
                result.ReasonCode);
            Assert.False(
                Directory.Exists(setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportFailureCleansTemporaryAndFinalFiles()
        {
            using var setup = new Setup(
                enableScopedTrace: true);
            setup.Protection.ThrowOnProtectFileCall = 4;
            PrincipalCredential principal =
                setup.ExportDeveloper();
            setup.SeedCompleteActionAudit(principal);

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal));

            Assert.False(result.Success);
            Assert.Equal(
                "internal_error",
                result.ReasonCode);
            Assert.False(
                Directory.Exists(setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportAuditFailureAfterFinalMoveCleansOwnedFiles()
        {
            using var setup = new Setup(
                enableScopedTrace: true);
            PrincipalCredential principal =
                setup.ExportDeveloper();
            setup.SeedCompleteActionAudit(principal);
            setup.Protection.OnProtectFile =
                path =>
                {
                    if (path.EndsWith(
                            ".jsonl",
                            StringComparison.Ordinal))
                    {
                        setup.ScopedAudit.Dispose();
                    }
                };

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal));

            Assert.False(result.Success);
            Assert.Equal(
                "internal_error",
                result.ReasonCode);
            Assert.False(
                Directory.Exists(setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportDeleteFailureKeepsMarkerForNextJanitorPass()
        {
            using var setup = new Setup(
                enableScopedTrace: true);
            PrincipalCredential principal =
                setup.ExportDeveloper();
            setup.SeedCompleteActionAudit(principal);
            FileStream finalLock = null;
            using var cancellation =
                new CancellationTokenSource();
            setup.Protection.OnProtectFile =
                path =>
                {
                    if (!path.EndsWith(
                            ".jsonl",
                            StringComparison.Ordinal))
                    {
                        return;
                    }
                    finalLock = new FileStream(
                        path,
                        FileMode.Open,
                        FileAccess.Read,
                        FileShare.Read);
                    cancellation.Cancel();
                };

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal),
                    cancellation.Token);

            Assert.False(result.Success);
            Assert.Equal(
                "deadline_exceeded",
                result.ReasonCode);
            Assert.Single(
                Directory.GetFiles(
                    setup.ExportDirectory,
                    "*.jsonl"));
            Assert.Single(
                Directory.GetFiles(
                    setup.ExportDirectory,
                    "*.pending"));
            Assert.True(
                setup.ScopedAudit.TrySnapshotExport(
                    principal,
                    setup.Controller.SessionId,
                    setup.Controller.Snapshot
                        .LifecycleGeneration,
                    AgentCapabilitiesV1.Click,
                    0,
                    1000,
                    out ScopedAuditExportSnapshot snapshot,
                    out string snapshotReason),
                snapshotReason);
            Assert.Contains(
                snapshot.Records,
                record =>
                    record.Entry.EventType
                        == AgentRuntimeAuditEventTypes
                            .TraceExportFailed
                    && record.Entry.CanonicalPayload
                        .Contains(
                            "trace_export_cleanup_pending",
                            StringComparison.Ordinal));

            finalLock.Dispose();
            finalLock = null;
            setup.Protection.OnProtectFile = null;
            AgentRuntimeDispatchResult retry =
                setup.Dispatch(
                    setup.Player(
                        AgentCapabilitiesV1.Click),
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters());

            Assert.False(retry.Success);
            Assert.Equal(
                "capability_denied",
                retry.ReasonCode);
            Assert.Empty(
                Directory.GetFiles(
                    setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportJanitorRemovesDeadProcessTransactionOnly()
        {
            using var setup = new Setup(
                enableScopedTrace: true);
            string artifactName =
                "trace_0123456789abcdefghijklmn.jsonl";
            string finalPath = Path.Combine(
                setup.ExportDirectory,
                artifactName);
            string temporaryPath = finalPath + ".tmp";
            string markerPath =
                finalPath + ".pending";
            Directory.CreateDirectory(
                setup.ExportDirectory);
            File.WriteAllText(finalPath, "published");
            File.WriteAllText(temporaryPath, "temporary");
            File.WriteAllText(
                markerPath,
                int.MaxValue
                    + "."
                    + DateTimeOffset.UtcNow
                        .UtcDateTime
                        .Ticks);

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    setup.Player(
                        AgentCapabilitiesV1.Click),
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters());

            Assert.False(result.Success);
            Assert.Equal(
                "capability_denied",
                result.ReasonCode);
            Assert.False(File.Exists(finalPath));
            Assert.False(File.Exists(temporaryPath));
            Assert.False(File.Exists(markerPath));
        }

        [Fact]
        public void TraceExportJanitorClaimsOnlyUnlockedLegacyTemporary()
        {
            using var setup = new Setup(
                enableScopedTrace: true);
            Directory.CreateDirectory(
                setup.ExportDirectory);
            string publishedPath = Path.Combine(
                setup.ExportDirectory,
                "trace_0123456789abcdefghijklmn.jsonl");
            string legacyTemporaryPath =
                publishedPath + ".tmp";
            string lockedTemporaryPath = Path.Combine(
                setup.ExportDirectory,
                "trace_zyxwvutsrqponmlkjihgfedc.jsonl.tmp");
            File.WriteAllText(
                publishedPath,
                "published");
            File.WriteAllText(
                legacyTemporaryPath,
                "legacy");
            using (var locked = new FileStream(
                lockedTemporaryPath,
                FileMode.CreateNew,
                FileAccess.ReadWrite,
                FileShare.None))
            {
                AgentRuntimeDispatchResult first =
                    setup.Dispatch(
                        setup.Player(
                            AgentCapabilitiesV1.Click),
                        AgentCapabilitiesV1.TraceExport,
                        setup.TraceParameters());
                Assert.False(first.Success);
                Assert.True(File.Exists(publishedPath));
                Assert.False(
                    File.Exists(legacyTemporaryPath));
                Assert.True(
                    File.Exists(lockedTemporaryPath));
            }

            AgentRuntimeDispatchResult retry =
                setup.Dispatch(
                    setup.Player(
                        AgentCapabilitiesV1.Click),
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters());

            Assert.False(retry.Success);
            Assert.True(File.Exists(publishedPath));
            Assert.False(File.Exists(lockedTemporaryPath));
        }

        [Theory]
        [InlineData("trace_short")]
        [InlineData("other_0123456789abcdefghijklmn")]
        [InlineData("trace_0123456789abcdefghijklm!")]
        [InlineData("trace_../../outside")]
        public void TraceExportRejectsInvalidArtifactFactoryBeforeFilesystem(
            string invalidArtifactId)
        {
            using var setup = new Setup(
                enableScopedTrace: true,
                fixedTraceArtifactId:
                    invalidArtifactId);
            PrincipalCredential principal =
                setup.ExportDeveloper();
            setup.SeedCompleteActionAudit(principal);

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal));

            Assert.False(result.Success);
            Assert.Equal(
                "internal_error",
                result.ReasonCode);
            Assert.False(
                Directory.Exists(setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportCompletedFactIsNotPublicationProof()
        {
            const string fixedArtifactId =
                "trace_0123456789abcdefghijklmn";
            using var setup = new Setup(
                enableScopedTrace: true,
                fixedTraceArtifactId:
                    fixedArtifactId);
            PrincipalCredential principal =
                setup.ExportDeveloper();
            setup.SeedCompleteActionAudit(principal);
            FileStream markerLock = null;
            setup.Protection.OnProtectFile =
                path =>
                {
                    if (path.EndsWith(
                            ".pending",
                            StringComparison.Ordinal))
                    {
                        markerLock = new FileStream(
                            path,
                            FileMode.Open,
                            FileAccess.Read,
                            FileShare.Read);
                    }
                };

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal));

            Assert.False(result.Success);
            Assert.Equal(
                "internal_error",
                result.ReasonCode);
            string finalPath = Path.Combine(
                setup.ExportDirectory,
                fixedArtifactId + ".jsonl");
            Assert.False(File.Exists(finalPath));
            Assert.True(
                File.Exists(finalPath + ".pending"));
            Assert.True(
                setup.ScopedAudit.TrySnapshotExport(
                    principal,
                    setup.Controller.SessionId,
                    setup.Controller.Snapshot
                        .LifecycleGeneration,
                    AgentCapabilitiesV1.Click,
                    0,
                    1000,
                    out ScopedAuditExportSnapshot snapshot,
                    out string snapshotReason),
                snapshotReason);
            ScopedAuditExportRecord[] events =
                snapshot.Records
                    .Where(record =>
                        record.Entry.EventType
                            == AgentRuntimeAuditEventTypes
                                .TraceExportCompleted
                        || record.Entry.EventType
                            == AgentRuntimeAuditEventTypes
                                .TraceExportFailed)
                    .ToArray();
            Assert.Equal(2, events.Length);
            Assert.Equal(
                AgentRuntimeAuditEventTypes
                    .TraceExportCompleted,
                events[0].Entry.EventType);
            Assert.Equal(
                AgentRuntimeAuditEventTypes
                    .TraceExportFailed,
                events[1].Entry.EventType);
            Assert.Contains(
                "trace_export_cleanup_pending",
                events[1].Entry.CanonicalPayload,
                StringComparison.Ordinal);

            markerLock.Dispose();
            markerLock = null;
            setup.Protection.OnProtectFile = null;
            setup.Dispatch(
                setup.Player(
                    AgentCapabilitiesV1.Click),
                AgentCapabilitiesV1.TraceExport,
                setup.TraceParameters());
            Assert.Empty(
                Directory.GetFiles(
                    setup.ExportDirectory));
        }

        [Fact]
        public void TraceExportJanitorPreservesMalformedMarkerSiblings()
        {
            using var setup = new Setup(
                enableScopedTrace: true);
            string finalPath = Path.Combine(
                setup.ExportDirectory,
                "trace_0123456789abcdefghijklmn.jsonl");
            string temporaryPath =
                finalPath + ".tmp";
            string markerPath =
                finalPath + ".pending";
            Directory.CreateDirectory(
                setup.ExportDirectory);
            File.WriteAllText(finalPath, "published");
            File.WriteAllText(temporaryPath, "temporary");
            File.WriteAllText(markerPath, "malformed-owner");

            setup.Dispatch(
                setup.Player(
                    AgentCapabilitiesV1.Click),
                AgentCapabilitiesV1.TraceExport,
                setup.TraceParameters());

            Assert.True(File.Exists(finalPath));
            Assert.True(File.Exists(temporaryPath));
            Assert.True(File.Exists(markerPath));
        }

        [Fact]
        public void TraceExportJanitorPreservesLiveOwnerUntilExit()
        {
            string commandProcessor =
                Environment.GetEnvironmentVariable(
                    "ComSpec");
            Assert.False(
                string.IsNullOrWhiteSpace(
                    commandProcessor));
            using Process owner = Process.Start(
                new ProcessStartInfo
                {
                    FileName = commandProcessor,
                    Arguments =
                        "/d /c ping.exe 127.0.0.1 -n 30 >nul",
                    UseShellExecute = false,
                    CreateNoWindow = true
                });
            Assert.NotNull(owner);
            Assert.False(owner.HasExited);
            DateTimeOffset ownerStartTimeUtc =
                new DateTimeOffset(
                    owner.StartTime.ToUniversalTime());
            using var setup = new Setup(
                enableScopedTrace: true);
            string finalPath = Path.Combine(
                setup.ExportDirectory,
                "trace_0123456789abcdefghijklmn.jsonl");
            string temporaryPath =
                finalPath + ".tmp";
            string markerPath =
                finalPath + ".pending";
            Directory.CreateDirectory(
                setup.ExportDirectory);
            File.WriteAllText(finalPath, "published");
            File.WriteAllText(temporaryPath, "temporary");
            File.WriteAllText(
                markerPath,
                owner.Id
                    + "."
                    + ownerStartTimeUtc
                        .UtcDateTime
                        .Ticks);

            setup.Dispatch(
                setup.Player(
                    AgentCapabilitiesV1.Click),
                AgentCapabilitiesV1.TraceExport,
                setup.TraceParameters());

            Assert.True(File.Exists(finalPath));
            Assert.True(File.Exists(temporaryPath));
            Assert.True(File.Exists(markerPath));

            owner.Kill(entireProcessTree: true);
            owner.WaitForExit();
            setup.Dispatch(
                setup.Player(
                    AgentCapabilitiesV1.Click),
                AgentCapabilitiesV1.TraceExport,
                setup.TraceParameters());

            Assert.False(File.Exists(finalPath));
            Assert.False(File.Exists(temporaryPath));
            Assert.False(File.Exists(markerPath));
        }

        [Fact]
        public void TraceExportNameCollisionNeverDeletesExistingArtifact()
        {
            const string fixedArtifactId =
                "trace_0123456789abcdefghijklmn";
            using var setup = new Setup(
                enableScopedTrace: true,
                fixedTraceArtifactId:
                    fixedArtifactId);
            PrincipalCredential principal =
                setup.ExportDeveloper();
            setup.SeedCompleteActionAudit(principal);

            AgentRuntimeDispatchResult first =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal));
            Assert.True(first.Success);
            string finalPath = Path.Combine(
                setup.ExportDirectory,
                fixedArtifactId + ".jsonl");
            byte[] firstPayload =
                File.ReadAllBytes(finalPath);

            AgentRuntimeDispatchResult collision =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal));

            Assert.False(collision.Success);
            Assert.Equal(
                "internal_error",
                collision.ReasonCode);
            Assert.Equal(
                firstPayload,
                File.ReadAllBytes(finalPath));
            Assert.False(
                File.Exists(finalPath + ".tmp"));
            Assert.False(
                File.Exists(finalPath + ".pending"));
        }

        [Fact]
        public void TraceExportWritesOnlyExactVerifiedScopedChain()
        {
            using var setup = new Setup(
                enableScopedTrace: true);
            PrincipalCredential principal =
                setup.ExportDeveloper();
            setup.SeedCompleteActionAudit(principal);

            AgentRuntimeDispatchResult result =
                setup.Dispatch(
                    principal,
                    AgentCapabilitiesV1.TraceExport,
                    setup.TraceParameters(principal));

            Assert.True(result.Success);
            string artifactName =
                result.Result.GetProperty("artifactName")
                    .GetString();
            string path = Path.Combine(
                setup.ExportDirectory,
                artifactName);
            Assert.True(File.Exists(path));
            string[] lines = File.ReadAllLines(path);
            Assert.True(lines.Length >= 3);
            using JsonDocument header =
                JsonDocument.Parse(lines[0]);
            Assert.Equal(
                "trace_header",
                header.RootElement
                    .GetProperty("recordType")
                    .GetString());
            Assert.Equal(
                principal.SecurityPrincipalId,
                header.RootElement
                    .GetProperty("scope")
                    .GetProperty("securityPrincipalId")
                    .GetString());
            Assert.Equal(
                AgentCapabilitiesV1.Click,
                header.RootElement
                    .GetProperty("scope")
                    .GetProperty("consentPurpose")
                    .GetString());
            Assert.DoesNotContain(
                setup.Audit.SegmentId,
                File.ReadAllText(path),
                StringComparison.Ordinal);
            Assert.True(
                result.Result
                    .GetProperty("exportAuditSequence")
                    .GetUInt64()
                > result.Result
                    .GetProperty("lastAuditSequence")
                    .GetUInt64());
        }

        [Fact]
        public void TraceExportRejectsOtherPurposeAndRevocationLeavesNoFile()
        {
            using (var wrongScope = new Setup(
                enableScopedTrace: true))
            {
                PrincipalCredential principal =
                    wrongScope.Developer(
                        AgentCapabilitiesV1.TraceExport,
                        "observation.export",
                        "observe:data.export",
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        AgentCapabilitiesV1.Click,
                        AgentCapabilitiesV1.TypeText);
                wrongScope.SeedCompleteActionAudit(
                    principal);
                TraceExportParametersV1 parameters =
                    wrongScope.TraceParameters(
                        principal);
                parameters.ConsentPurpose =
                    AgentCapabilitiesV1.TypeText;

                AgentRuntimeDispatchResult result =
                    wrongScope.Dispatch(
                        principal,
                        AgentCapabilitiesV1.TraceExport,
                        parameters);

                Assert.False(result.Success);
                Assert.Equal(
                    "unsupported_for_surface",
                    result.ReasonCode);
                Assert.False(
                    Directory.Exists(
                        wrongScope.ExportDirectory));
            }

            using (var revoked = new Setup(
                enableScopedTrace: true))
            {
                PrincipalCredential principal =
                    revoked.ExportDeveloper();
                revoked.SeedCompleteActionAudit(principal);
                TraceExportParametersV1 parameters =
                    revoked.TraceParameters(principal);
                revoked.Protection.OnProtectFile =
                    _ => revoked.Grants.Revoke(
                        parameters.ObservationGrantId,
                        "test_revoked");

                AgentRuntimeDispatchResult result =
                    revoked.Dispatch(
                        principal,
                        AgentCapabilitiesV1.TraceExport,
                        parameters);

                Assert.False(result.Success);
                Assert.Equal(
                    "internal_error",
                    result.ReasonCode);
                Assert.False(
                    Directory.Exists(
                        revoked.ExportDirectory));
            }
        }

        [Fact]
        public void CancellationAndUnavailableAuditCreateNoArtifact()
        {
            using (var cancelled = new Setup())
            {
                PrincipalCredential principal =
                    cancelled.ExportDeveloper();
                using var cancellation =
                    new CancellationTokenSource();
                cancellation.Cancel();
                AgentRuntimeDispatchResult result =
                    cancelled.Dispatch(
                        principal,
                        AgentCapabilitiesV1.TraceExport,
                        cancelled.TraceParameters(principal),
                        cancellation.Token);
                Assert.Equal(
                    "deadline_exceeded",
                    result.ReasonCode);
                Assert.False(
                    Directory.Exists(
                        cancelled.ExportDirectory));
            }

            using (var sealedAudit = new Setup())
            {
                PrincipalCredential principal =
                    sealedAudit.ExportDeveloper();
                sealedAudit.Audit.SealCompleted("{}");
                AgentRuntimeDispatchResult result =
                    sealedAudit.Dispatch(
                        principal,
                        AgentCapabilitiesV1.TraceExport,
                        sealedAudit.TraceParameters(principal));
                Assert.Equal(
                    "unsupported_for_surface",
                    result.ReasonCode);
                Assert.False(
                    Directory.Exists(
                        sealedAudit.ExportDirectory));
            }
        }

        private static string Id(string prefix)
        {
            return prefix + "_0123456789abcdefghijklmnop";
        }

        private sealed class Setup : IDisposable
        {
            private readonly PrincipalCredentialAuthority
                _credentials;

            private const string ConnectionId =
                "connection_0123456789abcdefghijkl";

            public Setup(
                bool enableScopedTrace = false,
                string fixedTraceArtifactId = null)
            {
                Clock = new ManualAgentRuntimeClock();
                Identity = AgentRuntimeHostIdentity.Resolve(
                    isolatedRuntimeCandidate: false);
                var launcher = new SessionProcessIdentity(
                    Environment.ProcessId,
                    Clock.UtcNow,
                    Identity.Qualification.ActualProcessPath);
                Owner = new SessionRegistryHostOwner(
                    launcher);
                Registry = new SessionSurfaceRegistry(
                    Owner,
                    new RecordingSessionSurfaceHostValidator());
                Controller = new SessionSurfaceHostController(
                    Registry,
                    Owner,
                    Identity.Qualification,
                    Identity.CoreSha256,
                    new[]
                    {
                        AgentCapabilitiesV1.LaunchApp,
                        AgentCapabilitiesV1.TraceExport
                    });
                Audit = new AppendOnlyAuditSegment(
                    Clock,
                    Id("audit_segment"));
                _credentials =
                    new PrincipalCredentialAuthority(
                        Clock,
                        new TestPrincipalEnrollmentVerifier());
                Targets = new MutableAgentTargetAuthority();
                ExportTargetId = Id("export_target");
                Targets.Set(
                    Controller.SessionId,
                    ExportTargetId);
                Grants = new ObservationGrantBroker(
                    Clock,
                    _credentials,
                    Targets);
                ScopedAudit =
                    enableScopedTrace
                        ? new ScopedAgentRuntimeAuditLedgerManager(
                            Clock,
                            _credentials,
                            new RegistryAgentAuditScopeAuthority(
                                Registry),
                            requireTrustedConnections: true)
                        : null;
                MinimalSessions =
                    new RegistryMinimalSessionReferenceProvider(
                        Registry,
                        Id("lifecycle_salt"));
                ExportDirectory = Path.Combine(
                    Path.GetTempPath(),
                    "cf7-agent-host-method-tests",
                    Guid.NewGuid().ToString("N"));
                Protection = new RecordingFileProtection();
                Service =
                    new LauncherAgentRuntimeHostMethodService(
                        Path.GetFullPath("."),
                        Clock,
                        Audit,
                        Controller,
                        MinimalSessions,
                        Grants,
                        Identity,
                        ExportDirectory,
                        Protection,
                        ScopedAudit,
                        fixedTraceArtifactId == null
                            ? null
                            : () =>
                                fixedTraceArtifactId);
            }

            public ManualAgentRuntimeClock Clock { get; }
            public AgentRuntimeHostIdentity Identity { get; }
            public SessionRegistryHostOwner Owner { get; }
            public SessionSurfaceRegistry Registry { get; }
            public SessionSurfaceHostController Controller { get; }
            public MutableAgentTargetAuthority Targets { get; }
            public ObservationGrantBroker Grants { get; }
            public ScopedAgentRuntimeAuditLedgerManager
                ScopedAudit { get; }
            public RegistryMinimalSessionReferenceProvider
                MinimalSessions { get; }
            public string ExportTargetId { get; }
            public AppendOnlyAuditSegment Audit { get; }
            public string ExportDirectory { get; }
            public RecordingFileProtection Protection { get; }
            public LauncherAgentRuntimeHostMethodService Service
            {
                get;
            }

            public PrincipalCredential Developer(
                params string[] capabilities)
            {
                return _credentials.IssueDeveloper(
                    new DeveloperEnrollmentEvidence
                    {
                        ClientInstanceId =
                            Id("developer_client")
                                + OpaqueIdGenerator
                                    .Create("suffix"),
                        EnrollmentReceipt =
                            "developer-enrollment",
                        AllowedCapabilities =
                            capabilities,
                        AllowedTargets = new[] { "*" }
                    });
            }

            public PrincipalCredential ExportDeveloper()
            {
                return Developer(
                    AgentCapabilitiesV1.TraceExport,
                    "observation.export",
                    "observe:data.export",
                    "observe:pixels",
                    AgentCapabilitiesV1
                        .ObservationGrantManage,
                    AgentCapabilitiesV1.Click);
            }

            public PrincipalCredential Player(
                params string[] capabilities)
            {
                return _credentials.IssuePlayerAssist(
                    new PlayerAssistCredentialEvidence
                    {
                        ClientInstanceId =
                            Id("player_client")
                                + OpaqueIdGenerator
                                    .Create("suffix"),
                        ConsentReceipt = "player-consent",
                        SelectedSessionId =
                            Controller.SessionId,
                        AllowedCapabilities =
                            capabilities,
                        AllowedTargets = new[] { "*" }
                    });
            }

            public AppLaunchParametersV1 LaunchParameters()
            {
                return new AppLaunchParametersV1
                {
                    LaunchRequestId = Id("launch_request"),
                    EntryPoint = "standard_entry",
                    RuntimeMode =
                        Identity.Qualification.RuntimeMode,
                    ExpectedBuildIdentity =
                        Identity.Qualification.BuildIdentity,
                    ExpectedPayloadClosure =
                        Identity.Qualification.PayloadClosure
                };
            }

            public TraceExportParametersV1 TraceParameters(
                PrincipalCredential principal = null,
                int maximumRecords = 100)
            {
                return new TraceExportParametersV1
                {
                    SessionId = Controller.SessionId,
                    ConsentPurpose =
                        AgentCapabilitiesV1.Click,
                    ObservationGrantId =
                        principal == null
                            ? Id("observation_grant")
                            : IssueGrant(
                                principal,
                                new[]
                                {
                                    ObservationDataScopesV1
                                        .DataExport
                                },
                                allowExport: true)
                                .ObservationGrantId,
                    FromServerSequence = 0,
                    MaximumRecords = maximumRecords,
                    Format = "jsonl"
                };
            }

            public ObservationGrant IssueGrant(
                PrincipalCredential principal,
                IReadOnlyCollection<string> dataScopes,
                bool allowExport,
                TimeSpan? lifetime = null)
            {
                return Grants.Issue(
                    new ObservationGrantRequest
                    {
                        CredentialId =
                            principal.CredentialId,
                        ClientInstanceId =
                            principal.ClientInstanceId,
                        SessionId = Controller.SessionId,
                        Targets = new[]
                        {
                            new ObservationTargetScope
                            {
                                TargetId = ExportTargetId
                            }
                        },
                        DataScopes = dataScopes,
                        RequestedLifetime =
                            lifetime
                            ?? TimeSpan.FromMinutes(5),
                        ConsentReceipt =
                            "trace-export-consent",
                        AllowExport = allowExport
                    });
            }

            public AgentRuntimeDispatchResult Dispatch<T>(
                PrincipalCredential principal,
                string method,
                T parameters,
                CancellationToken cancellationToken = default)
            {
                var request = new AgentJsonRpcRequest
                {
                    Id = Id("request"),
                    Method = method,
                    Params = JsonSerializer.SerializeToElement(
                        parameters,
                        AgentProtocolV1.JsonOptions)
                };
                return Service.DispatchAsync(
                        new AgentRuntimeDispatchContext(
                            ConnectionId,
                            principal),
                        request,
                        cancellationToken)
                    .GetAwaiter()
                    .GetResult();
            }

            public void SeedCompleteActionAudit(
                PrincipalCredential principal)
            {
                Assert.NotNull(ScopedAudit);
                Assert.True(
                    ScopedAudit
                        .TryRegisterAuthenticatedConnection(
                            ConnectionId,
                            principal,
                            Controller.SessionId,
                            Controller.Snapshot
                                .LifecycleGeneration,
                            out string registerReason),
                    registerReason);
                using JsonDocument arguments =
                    JsonDocument.Parse(
                        "{\"button\":\"primary\",\"coordinateSpace\":\"observation_px\",\"x\":1,\"y\":1}");
                var action = new ActionEnvelope
                {
                    ActionId = Id("action"),
                    IdempotencyKey =
                        Id("idempotency"),
                    DeadlineMs = 1000,
                    SessionId =
                        Controller.SessionId,
                    ObservationGrantId =
                        Id("action_grant"),
                    LeaseId = Id("action_lease"),
                    ObservationId =
                        Id("observation"),
                    ExpectedLifecycleGeneration =
                        Controller.Snapshot
                            .LifecycleGeneration,
                    TargetId = ExportTargetId,
                    ExpectedSurfaceEpoch = 1,
                    ExpectedCoordinateSpaceVersion = 1,
                    ExpectedFocusEpoch = 1,
                    ExpectedModalEpoch = 1,
                    FrameId = Id("frame"),
                    Operation =
                        AgentCapabilitiesV1.Click,
                    Arguments =
                        arguments.RootElement.Clone(),
                    Reason = "trace export test"
                };
                Assert.True(
                    ScopedAudit.TryAppendTrustedFact(
                        new AgentRuntimeTrustedAuditFact
                        {
                            Principal = principal,
                            ConnectionId =
                                ConnectionId,
                            SessionId =
                                Controller.SessionId,
                            LifecycleGeneration =
                                Controller.Snapshot
                                    .LifecycleGeneration,
                            ConsentPurpose =
                                AgentCapabilitiesV1
                                    .ObservationGrantManage,
                            EventType =
                                AgentRuntimeAuditEventTypes
                                    .ObservationGrantIssued,
                            ObservationGrantId =
                                action.ObservationGrantId,
                            TargetScope =
                                new[] { ExportTargetId },
                            DataScope =
                                new[]
                                {
                                    ObservationDataScopesV1
                                        .Pixels
                                },
                            AllowExport = false,
                            AllowPersistence = false,
                            State = "Active",
                            ConsentReceipt =
                                "action-consent"
                        },
                        out _,
                        out string grantAuditReason),
                    grantAuditReason);
                var lease = new WriteLease(
                    action.LeaseId,
                    principal,
                    new WriteLeaseRequest
                    {
                        CredentialId =
                            principal.CredentialId,
                        ClientInstanceId =
                            principal.ClientInstanceId,
                        SessionId =
                            Controller.SessionId,
                        LifecycleGeneration =
                            Controller.Snapshot
                                .LifecycleGeneration,
                        Kind = WriteLeaseKind.GuiInput,
                        Capabilities =
                            new[]
                            {
                                AgentCapabilitiesV1.Click
                            },
                        TargetScope =
                            new[] { ExportTargetId },
                        RequestedLifetime =
                            TimeSpan.FromMinutes(1),
                        RequestedActionLimit = 1,
                        ConsentReceipt =
                            "action-consent"
                    },
                    Clock.MonotonicMilliseconds,
                    Clock.MonotonicMilliseconds
                        + 60_000,
                    1);
                string correlationId =
                    Id("correlation");
                string hash =
                    CanonicalJsonV1
                        .ComputeActionPayloadSha256(
                            action);
                Append(
                    AgentRuntimeAuditEventTypes
                        .ActionValidation,
                    null,
                    null,
                    false);
                Append(
                    AgentRuntimeAuditEventTypes
                        .ActionBindingValidated,
                    lease,
                    null,
                    false);
                Append(
                    AgentRuntimeAuditEventTypes
                        .ActionTerminal,
                    lease,
                    ActionOutcome
                        .InputDispatched,
                    true);

                void Append(
                    string eventType,
                    WriteLease boundLease,
                    ActionOutcome? outcome,
                    bool terminal)
                {
                    bool appended =
                        ScopedAudit.TryAppend(
                            new AgentRuntimeAuditEventEnvelope
                            {
                                Principal = principal,
                                ConnectionId =
                                    ConnectionId,
                                SessionId =
                                    Controller.SessionId,
                                LifecycleGeneration =
                                    Controller.Snapshot
                                        .LifecycleGeneration,
                                ConsentPurpose =
                                    AgentCapabilitiesV1.Click,
                                CorrelationId =
                                    correlationId,
                                EventType = eventType,
                                Action = action,
                                ActionPayloadHash = hash,
                                Lease = boundLease,
                                Outcome = outcome,
                                TerminalAction = terminal
                            },
                            out _,
                            out string reasonCode);
                    Assert.True(appended, reasonCode);
                }
            }

            public void AppendAuditPayload(string value)
            {
                string json = JsonSerializer.Serialize(
                    new
                    {
                        sessionId = Controller.SessionId,
                        value
                    },
                    AgentProtocolV1.JsonOptions);
                Audit.Append(
                    "test_trace_event",
                    CanonicalJsonV1.Canonicalize(json));
            }

            public void ReplaceWithDifferentRuntimeIdentity()
            {
                RuntimeQualificationRegistration current =
                    Identity.Qualification;
                var replacement =
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode = current.RuntimeMode,
                        BuildIdentity =
                            current.BuildIdentity == null
                                ? null
                                : new string('b', 64),
                        PayloadClosure =
                            current.PayloadClosure == null
                                ? null
                                : new string('d', 64),
                        ActualProcessPath =
                            current.ActualProcessPath,
                        UnqualifiedReason =
                            current.RuntimeMode
                                == RuntimeMode.UnqualifiedDev
                                ? "replacement_unqualified"
                                : null
                    };
                Controller.ReplaceLifecycle(
                    replacement,
                    "replacement_slot");
            }

            public void Dispose()
            {
                ScopedAudit?.Dispose();
                if (!Directory.Exists(ExportDirectory))
                    return;
                try
                {
                    Directory.Delete(
                        ExportDirectory,
                        recursive: true);
                    string parent =
                        Path.GetDirectoryName(
                            ExportDirectory);
                    if (parent != null
                        && Directory.Exists(parent)
                        && !Directory.EnumerateFileSystemEntries(
                                parent)
                            .Any())
                    {
                        Directory.Delete(parent);
                    }
                }
                catch
                {
                }
            }
        }

        private sealed class RecordingFileProtection
            : IAgentRendezvousFileProtection
        {
            private int _protectFileCalls;

            public List<string> ProtectedDirectories { get; } =
                new();
            public List<string> ProtectedFiles { get; } =
                new();
            public int? ThrowOnProtectFileCall { get; set; }
            public Action<string> OnProtectFile { get; set; }

            public void ProtectDirectory(string path)
            {
                ProtectedDirectories.Add(path);
            }

            public void ProtectFile(string path)
            {
                _protectFileCalls++;
                ProtectedFiles.Add(path);
                OnProtectFile?.Invoke(path);
                if (ThrowOnProtectFileCall
                    == _protectFileCalls)
                {
                    throw new IOException(
                        "Injected ACL failure.");
                }
            }
        }
    }
}
