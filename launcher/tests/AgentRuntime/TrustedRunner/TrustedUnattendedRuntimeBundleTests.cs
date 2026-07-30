using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.AgentRuntime.TrustedRunner;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.TrustedRunner
{
    public sealed class TrustedUnattendedRuntimeBundleTests
        : IDisposable
    {
        private readonly string _temporaryRoot;

        public TrustedUnattendedRuntimeBundleTests()
        {
            _temporaryRoot = Path.Combine(
                Path.GetTempPath(),
                "cf7-trusted-runner-tests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_temporaryRoot);
        }

        [Fact]
        public void FormalRuntimeVerifiesExactCorePayload()
        {
            string deployment = CreateProjectSkeleton();
            string core = WriteBundle(deployment);

            TrustedUnattendedRuntimeBundle bundle =
                TrustedUnattendedRuntimeBundle
                    .VerifySelectedProcess(
                        core,
                        verifyNativePolicy: false);

            Assert.Equal(
                "formal_runtime",
                bundle.RuntimeMode);
            Assert.True(
                TrustedUnattendedRuntimeBundle.SamePath(
                    deployment,
                    bundle.ProjectRoot));
            Assert.Equal(
                HashFile(core),
                bundle.CoreSha256,
                ignoreCase: true);
        }

        [Fact]
        public void CandidateDerivesProjectRootFromFixedTree()
        {
            string project = CreateProjectSkeleton();
            string deployment = Path.Combine(
                project,
                "tmp",
                "runtime-candidates",
                "v2",
                "candidate_A");
            Directory.CreateDirectory(deployment);
            string core = WriteBundle(deployment);
            WriteMetadata(deployment);

            TrustedUnattendedRuntimeBundle bundle =
                TrustedUnattendedRuntimeBundle
                    .VerifySelectedProcess(
                        core,
                        verifyNativePolicy: false);

            Assert.Equal(
                "isolated_candidate",
                bundle.RuntimeMode);
            Assert.True(
                TrustedUnattendedRuntimeBundle.SamePath(
                    project,
                    bundle.ProjectRoot));
        }

        [Fact]
        public void CandidateOutsideFixedTreeFailsClosed()
        {
            string project = CreateProjectSkeleton();
            string deployment = Path.Combine(
                project,
                "candidate_A");
            Directory.CreateDirectory(deployment);
            string core = WriteBundle(deployment);
            WriteMetadata(deployment);

            InvalidDataException error = Assert.Throws<
                InvalidDataException>(
                    () => TrustedUnattendedRuntimeBundle
                        .VerifySelectedProcess(
                            core,
                            verifyNativePolicy: false));

            Assert.Equal(
                "trusted_runner_candidate_path_invalid",
                error.Message);
        }

        [Fact]
        public void MutatedCoreFailsBeforeRunnerStarts()
        {
            string deployment = CreateProjectSkeleton();
            string core = WriteBundle(deployment);
            File.AppendAllText(
                core,
                "mutation",
                Encoding.UTF8);

            InvalidDataException error = Assert.Throws<
                InvalidDataException>(
                    () => TrustedUnattendedRuntimeBundle
                        .VerifySelectedProcess(
                            core,
                            verifyNativePolicy: false));

            Assert.Equal(
                "trusted_runner_payload_mismatch",
                error.Message);
        }

        [Fact]
        public void ManifestCannotRenameCoreIdentity()
        {
            string deployment = CreateProjectSkeleton();
            string core = WriteBundle(
                deployment,
                "runtime/not-the-core.exe");

            InvalidDataException error = Assert.Throws<
                InvalidDataException>(
                    () => TrustedUnattendedRuntimeBundle
                        .VerifySelectedProcess(
                            core,
                            verifyNativePolicy: false));

            Assert.Equal(
                "trusted_runner_core_not_in_payload",
                error.Message);
        }

        private string CreateProjectSkeleton()
        {
            string project = Path.Combine(
                _temporaryRoot,
                "project_"
                    + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(
                Path.Combine(
                    project,
                    "launcher",
                    "web"));
            File.WriteAllText(
                Path.Combine(project, "crossdomain.xml"),
                "<cross-domain-policy />",
                Encoding.UTF8);
            File.WriteAllText(
                Path.Combine(
                    project,
                    "launcher",
                    "web",
                    "bootstrap.html"),
                "<html></html>",
                Encoding.UTF8);
            return project;
        }

        private static string WriteBundle(
            string deployment,
            string manifestCorePath =
                "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe")
        {
            string runtime = Path.Combine(
                deployment,
                "runtime");
            Directory.CreateDirectory(runtime);
            string core = Path.Combine(
                runtime,
                "CRAZYFLASHER7MercenaryEmpire.Core.exe");
            File.WriteAllBytes(
                core,
                Encoding.UTF8.GetBytes(
                    "trusted-runner-fixture"));

            string bootstrap = Path.Combine(
                deployment,
                "CRAZYFLASHER7MercenaryEmpire.exe");
            File.WriteAllBytes(
                bootstrap,
                Encoding.UTF8.GetBytes("bootstrap-fixture"));
            string manifestCoreFullPath = Path.Combine(
                deployment,
                manifestCorePath.Replace(
                    '/',
                    Path.DirectorySeparatorChar));
            if (!string.Equals(
                    manifestCoreFullPath,
                    core,
                    StringComparison.OrdinalIgnoreCase))
            {
                Directory.CreateDirectory(
                    Path.GetDirectoryName(
                        manifestCoreFullPath));
                File.Copy(
                    core,
                    manifestCoreFullPath);
            }

            string artifact = new string('A', 64);
            string producer = new string('B', 64);
            string toolchain = new string('C', 64);
            string build = HashText(
                "artifactSourceHash\t"
                    + artifact
                    + "\nproducerRecipeHash\t"
                    + producer
                    + "\ntoolchainLockHash\t"
                    + toolchain
                    + "\n");
            var rows = new List<Row>
            {
                new Row(
                    "CRAZYFLASHER7MercenaryEmpire.exe",
                    new FileInfo(bootstrap).Length,
                    HashFile(bootstrap)),
                new Row(
                    manifestCorePath,
                    new FileInfo(
                        manifestCoreFullPath).Length,
                    HashFile(manifestCoreFullPath))
            };
            string closure = HashText(
                string.Concat(
                    rows.OrderBy(
                            row => row.Path,
                            StringComparer.Ordinal)
                        .Select(
                            row => row.Path
                                + "\t"
                                + row.Size.ToString(
                                    CultureInfo.InvariantCulture)
                                + "\t"
                                + row.Hash
                                + "\n")));
            var lines = new List<string>
            {
                "cf7-runtime-manifest-v2",
                "publishMode\tframework-dependent",
                "artifactSourceHash\t" + artifact,
                "producerRecipeHash\t" + producer,
                "toolchainLockHash\t" + toolchain,
                "toolchainBaseline\tfixture",
                "buildIdentityHash\t" + build,
                "payloadClosureHash\t" + closure
            };
            lines.AddRange(
                rows.Select(
                    row => "file\t"
                        + row.Path
                        + "\t"
                        + row.Size.ToString(
                            CultureInfo.InvariantCulture)
                        + "\t"
                        + row.Hash));
            File.WriteAllText(
                Path.Combine(
                    runtime,
                    "cf7-runtime-manifest.tsv"),
                string.Join("\n", lines) + "\n",
                new UTF8Encoding(false));
            return core;
        }

        private static void WriteMetadata(
            string deployment)
        {
            string[] manifest = File.ReadAllLines(
                Path.Combine(
                    deployment,
                    "runtime",
                    "cf7-runtime-manifest.tsv"));
            string build = ReadValue(
                manifest,
                "buildIdentityHash");
            string closure = ReadValue(
                manifest,
                "payloadClosureHash");
            File.WriteAllText(
                Path.Combine(
                    deployment,
                    "runtime-build-metadata.v2.json"),
                "{\"schema\":\"cf7-runtime-candidate-metadata.v2\","
                    + "\"buildIdentityHash\":\""
                    + build
                    + "\",\"payloadClosureHash\":\""
                    + closure
                    + "\"}",
                new UTF8Encoding(false));
        }

        private static string ReadValue(
            IEnumerable<string> lines,
            string name)
        {
            return lines.Single(
                    line => line.StartsWith(
                        name + "\t",
                        StringComparison.Ordinal))
                .Split('\t')[1];
        }

        private static string HashText(string value)
        {
            return Convert.ToHexString(
                SHA256.HashData(
                    Encoding.UTF8.GetBytes(value)));
        }

        private static string HashFile(string path)
        {
            using FileStream stream = File.OpenRead(path);
            return Convert.ToHexString(
                SHA256.HashData(stream));
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(_temporaryRoot))
                {
                    Directory.Delete(
                        _temporaryRoot,
                        true);
                }
            }
            catch
            {
            }
        }

        private sealed record Row(
            string Path,
            long Size,
            string Hash);
    }
}
