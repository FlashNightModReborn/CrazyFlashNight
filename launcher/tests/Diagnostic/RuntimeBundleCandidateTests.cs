using System;
using System.IO;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public sealed class RuntimeBundleCandidateTests : IDisposable
    {
        const string BuildIdentity = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        const string PayloadClosure = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";

        readonly string _tempRoot;
        readonly string _candidateRoot;
        readonly string _runtimeDir;
        readonly string _projectRoot;

        public RuntimeBundleCandidateTests()
        {
            _tempRoot = Path.Combine(Path.GetTempPath(), "cf7-runtime-candidate-tests-" + Guid.NewGuid().ToString("N"));
            _projectRoot = Path.Combine(_tempRoot, "project");
            _candidateRoot = Path.Combine(_projectRoot, "tmp", "runtime-candidates", "v2", "candidate");
            _runtimeDir = Path.Combine(_candidateRoot, "runtime");
            Directory.CreateDirectory(_runtimeDir);
            Directory.CreateDirectory(Path.Combine(_projectRoot, "launcher", "web"));
            File.WriteAllText(Path.Combine(_projectRoot, "crossdomain.xml"), "<cross-domain-policy />");
            File.WriteAllText(Path.Combine(_projectRoot, "launcher", "web", "bootstrap.html"), "<!doctype html>");
            WriteManifest(BuildIdentity, PayloadClosure);
            WriteMetadata("cf7-runtime-candidate-metadata.v2", BuildIdentity, PayloadClosure);
        }

        [Fact]
        public void IsolatedIdentityBoundCandidateUsesRuntimeOnlyProbe()
        {
            Assert.True(global::Program.IsIsolatedRuntimeCandidate(_runtimeDir, _projectRoot));
            Assert.Equal("--verify-runtime-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, _projectRoot));
            Assert.Equal("CF7:FlashNight — 隔离候选 / 未部署",
                GuardianForm.SelectWindowTitle(true));
        }

        [Fact]
        public void FormalInstallRootAlwaysUsesCompleteInstallProbe()
        {
            Assert.False(global::Program.IsIsolatedRuntimeCandidate(_runtimeDir, _candidateRoot));
            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, _candidateRoot));
            Assert.Equal("CF7:FlashNight", GuardianForm.SelectWindowTitle(false));
        }

        [Fact]
        public void MissingCandidateMetadataFailsClosed()
        {
            File.Delete(Path.Combine(_candidateRoot, "runtime-build-metadata.v2.json"));

            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, _projectRoot));
        }

        [Fact]
        public void WrongCandidateSchemaFailsClosed()
        {
            WriteMetadata("cf7-runtime-candidate-metadata.v1", BuildIdentity, PayloadClosure);

            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, _projectRoot));
        }

        [Fact]
        public void MetadataManifestIdentityMismatchFailsClosed()
        {
            WriteMetadata("cf7-runtime-candidate-metadata.v2",
                "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
                PayloadClosure);

            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, _projectRoot));
        }

        [Fact]
        public void MetadataManifestPayloadClosureMismatchFailsClosed()
        {
            WriteMetadata("cf7-runtime-candidate-metadata.v2", BuildIdentity,
                "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC");

            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, _projectRoot));
        }

        [Fact]
        public void MissingRequestedProjectRootFailsClosed()
        {
            string missingRoot = Path.Combine(_tempRoot, "missing-project");

            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, missingRoot));
        }

        [Fact]
        public void WalkUpWithoutExplicitProjectRootFailsClosed()
        {
            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, null));
        }

        [Fact]
        public void CandidateOutsideExplicitProjectsCandidateTreeFailsClosed()
        {
            string outsideRoot = Path.Combine(_tempRoot, "outside-candidate");
            string outsideRuntime = Path.Combine(outsideRoot, "runtime");
            Directory.CreateDirectory(outsideRuntime);
            File.Copy(Path.Combine(_candidateRoot, "runtime-build-metadata.v2.json"),
                Path.Combine(outsideRoot, "runtime-build-metadata.v2.json"));
            File.Copy(Path.Combine(_runtimeDir, "cf7-runtime-manifest.tsv"),
                Path.Combine(outsideRuntime, "cf7-runtime-manifest.tsv"));

            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(outsideRuntime, _projectRoot));
        }

        [Fact]
        public void NestedCustomCandidateInsideProducerTreeUsesRuntimeOnlyProbe()
        {
            string nestedRoot = Path.Combine(_projectRoot, "tmp", "runtime-candidates", "v2", "custom", "nested");
            string nestedRuntime = Path.Combine(nestedRoot, "runtime");
            Directory.CreateDirectory(nestedRuntime);
            File.Copy(Path.Combine(_candidateRoot, "runtime-build-metadata.v2.json"),
                Path.Combine(nestedRoot, "runtime-build-metadata.v2.json"));
            File.Copy(Path.Combine(_runtimeDir, "cf7-runtime-manifest.tsv"),
                Path.Combine(nestedRuntime, "cf7-runtime-manifest.tsv"));

            Assert.Equal("--verify-runtime-only",
                global::Program.SelectRuntimeVerificationArgument(nestedRuntime, _projectRoot));
        }

        [Fact]
        public void DuplicateManifestIdentityFailsClosed()
        {
            File.AppendAllText(Path.Combine(_runtimeDir, "cf7-runtime-manifest.tsv"),
                "buildIdentityHash\t" + BuildIdentity + "\n");

            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, _projectRoot));
        }

        [Fact]
        public void MissingCompleteInstallSentinelFailsClosed()
        {
            File.Delete(Path.Combine(_projectRoot, "launcher", "web", "bootstrap.html"));

            Assert.Equal("--verify-only",
                global::Program.SelectRuntimeVerificationArgument(_runtimeDir, _projectRoot));
        }

        void WriteMetadata(string schema, string buildIdentity, string payloadClosure)
        {
            string json = "{\n"
                          + "  \"schema\": \"" + schema + "\",\n"
                          + "  \"buildIdentityHash\": \"" + buildIdentity + "\",\n"
                          + "  \"payloadClosureHash\": \"" + payloadClosure + "\"\n"
                          + "}\n";
            File.WriteAllText(Path.Combine(_candidateRoot, "runtime-build-metadata.v2.json"), json);
        }

        void WriteManifest(string buildIdentity, string payloadClosure)
        {
            string manifest = "cf7-runtime-manifest-v2\n"
                              + "buildIdentityHash\t" + buildIdentity + "\n"
                              + "payloadClosureHash\t" + payloadClosure + "\n";
            File.WriteAllText(Path.Combine(_runtimeDir, "cf7-runtime-manifest.tsv"), manifest);
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(_tempRoot)) Directory.Delete(_tempRoot, true);
            }
            catch { }
        }
    }
}
