using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.AgentRuntime.TrustedRunner;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.TrustedRunner
{
    public sealed class
        TrustedUnattendedBootstrapLeaseTests
    {
        [Fact]
        public void LeasePublishesExactCurrentRunnerIdentityAndTombstonesOnDispose()
        {
            string root =
                Path.Combine(
                    Path.GetTempPath(),
                    "cf7-trusted-bootstrap-test-"
                    + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            string localAppData =
                Path.Combine(root, "local-app-data");
            try
            {
                string processPath =
                    Environment.ProcessPath
                    ?? throw new InvalidOperationException(
                        "test_process_path_missing");
                FileInfo executable =
                    new FileInfo(processPath);
                TrustedUnattendedRuntimeBundle bundle =
                    CreateBundle(
                        root,
                        processPath,
                        executable.Length);
                var protection =
                    new RecordingProtection();
                TrustedUnattendedBootstrapLease lease =
                    TrustedUnattendedBootstrapLease
                        .Create(
                            bundle,
                            "cf7_agent_equipment_tuning",
                            DateTimeOffset.UtcNow,
                            localAppData,
                            protection);
                string requestPath =
                    lease.RequestPath;
                try
                {
                    Assert.True(
                        File.Exists(requestPath));
                    using JsonDocument request =
                        JsonDocument.Parse(
                            File.ReadAllBytes(
                                requestPath));
                    JsonElement rootElement =
                        request.RootElement;
                    Assert.Equal(
                        "cf7.agent_runtime.trusted_unattended_bootstrap_request.v2",
                        rootElement
                            .GetProperty("schema")
                            .GetString());
                    Assert.Equal(
                        Environment.ProcessId,
                        rootElement
                            .GetProperty(
                                "runnerProcessId")
                            .GetInt32());
                    Assert.Equal(
                        processPath,
                        rootElement
                            .GetProperty(
                                "runnerExecutablePath")
                            .GetString());
                    Assert.Equal(
                        executable.Length,
                        rootElement
                            .GetProperty(
                                "runnerExecutableSize")
                            .GetInt64());
                    Assert.Equal(
                        processPath,
                        rootElement
                            .GetProperty(
                                "runtimeExecutablePath")
                            .GetString());
                    Assert.Single(
                        protection.ProtectedFiles);
                    Assert.Equal(
                        requestPath,
                        protection.ProtectedFiles[0]);
                }
                finally
                {
                    lease.Dispose();
                }
                Assert.False(
                    File.Exists(requestPath));
            }
            finally
            {
                if (Directory.Exists(root))
                {
                    Directory.Delete(
                        root,
                        recursive: true);
                }
            }
        }

        [Fact]
        public void CredentialWaitUsesAcquisitionDeadlineBeforeRequestExpiry()
        {
            string root =
                Path.Combine(
                    Path.GetTempPath(),
                    "cf7-trusted-bootstrap-wait-test-"
                    + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            string localAppData =
                Path.Combine(root, "local-app-data");
            try
            {
                string processPath =
                    Environment.ProcessPath
                    ?? throw new InvalidOperationException(
                        "test_process_path_missing");
                FileInfo executable =
                    new FileInfo(processPath);
                TrustedUnattendedRuntimeBundle bundle =
                    CreateBundle(
                        root,
                        processPath,
                        executable.Length);
                using TrustedUnattendedBootstrapLease lease =
                    TrustedUnattendedBootstrapLease.Create(
                        bundle,
                        "cf7_agent_equipment_tuning",
                        DateTimeOffset.UtcNow,
                        localAppData,
                        new RecordingProtection());
                using Process guardian =
                    Process.GetCurrentProcess();
                Stopwatch elapsed = Stopwatch.StartNew();

                TimeoutException failure =
                    Assert.Throws<TimeoutException>(
                        () => lease.WaitForCredential(
                            guardian,
                            TimeSpan.FromMilliseconds(10),
                            TimeSpan.FromMilliseconds(100),
                            CancellationToken.None));

                elapsed.Stop();
                Assert.Equal(
                    "trusted_runner_credential_timeout",
                    failure.Message);
                Assert.InRange(
                    elapsed.Elapsed,
                    TimeSpan.FromMilliseconds(50),
                    TimeSpan.FromSeconds(5));
                Assert.True(
                    lease.ExpiresUtc
                        > DateTimeOffset.UtcNow
                            .AddMinutes(5));
                Assert.Throws<ArgumentOutOfRangeException>(
                    () => lease.WaitForCredential(
                        guardian,
                        TimeSpan.FromMilliseconds(10),
                        TimeSpan.FromSeconds(31),
                        CancellationToken.None));
                using var cancelled =
                    new CancellationTokenSource();
                cancelled.Cancel();
                Assert.Throws<OperationCanceledException>(
                    () => lease.WaitForCredential(
                        guardian,
                        TimeSpan.FromMilliseconds(10),
                        TimeSpan.FromMilliseconds(100),
                        cancelled.Token));
            }
            finally
            {
                if (Directory.Exists(root))
                {
                    Directory.Delete(
                        root,
                        recursive: true);
                }
            }
        }

        private static
            TrustedUnattendedRuntimeBundle
            CreateBundle(
                string projectRoot,
                string corePath,
                long coreSize)
        {
            ConstructorInfo constructor =
                typeof(TrustedUnattendedRuntimeBundle)
                    .GetConstructor(
                        BindingFlags.Instance
                            | BindingFlags.NonPublic,
                        binder: null,
                        new[]
                        {
                            typeof(string),
                            typeof(string),
                            typeof(string),
                            typeof(string),
                            typeof(string),
                            typeof(string),
                            typeof(string),
                            typeof(long)
                        },
                        modifiers: null)
                ?? throw new InvalidOperationException(
                    "bundle_constructor_missing");
            return
                (TrustedUnattendedRuntimeBundle)
                    constructor.Invoke(
                        new object[]
                        {
                            projectRoot,
                            projectRoot,
                            corePath,
                            "isolated_candidate",
                            new string('A', 64),
                            new string('B', 64),
                            new string('C', 64),
                            coreSize
                        });
        }

        private sealed class RecordingProtection
            : IAgentRendezvousFileProtection
        {
            public System.Collections.Generic
                .List<string> ProtectedFiles
                { get; } =
                    new System.Collections.Generic
                        .List<string>();

            public void ProtectDirectory(
                string path)
            {
            }

            public void ProtectFile(
                string path)
            {
                ProtectedFiles.Add(path);
            }
        }
    }
}
