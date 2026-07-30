using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Integration;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    [CollectionDefinition(
        CollectionName,
        DisableParallelization = true)]
    public sealed class AgentRuntimeHostIdentityCollection
    {
        public const string CollectionName =
            "Agent Runtime host identity AppContext";
    }

    [Collection(
        AgentRuntimeHostIdentityCollection.CollectionName)]
    public sealed class AgentRuntimeHostIdentityTests
    {
        private static readonly string BuildIdentity =
            new string('A', 64);
        private static readonly string PayloadClosure =
            new string('B', 64);

        [Fact]
        public void ResolveOutsideRuntimeDowngradesToUnqualifiedDev()
        {
            using var scope =
                new BaseDirectoryScope("development");

            AgentRuntimeHostIdentity identity =
                AgentRuntimeHostIdentity.Resolve(
                    isolatedRuntimeCandidate: false);

            Assert.Equal(
                RuntimeMode.UnqualifiedDev,
                identity.Qualification.RuntimeMode);
            Assert.Equal(
                "process_not_running_from_verified_runtime",
                identity.Qualification.UnqualifiedReason);
            Assert.Null(identity.Qualification.BuildIdentity);
            Assert.Null(identity.Qualification.PayloadClosure);
            Assert.Equal(
                Path.GetFullPath(Environment.ProcessPath),
                identity.Qualification.ActualProcessPath);
            Assert.Equal(CoreSha256(), identity.CoreSha256);
        }

        [Theory]
        [InlineData(false, RuntimeMode.FormalRuntime)]
        [InlineData(true, RuntimeMode.IsolatedCandidate)]
        public void ResolveAcceptsOnlyExactLoadedCoreRow(
            bool isolatedRuntimeCandidate,
            RuntimeMode expectedMode)
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteManifest(
                Header,
                BuildLine,
                PayloadLine,
                FileLine(
                    "runtime/decoy.dll",
                    1,
                    new string('C', 64)),
                FileLine(
                    CoreRelativePath,
                    CoreLength,
                    CoreSha256().ToUpperInvariant()));

            AgentRuntimeHostIdentity identity =
                AgentRuntimeHostIdentity.Resolve(
                    isolatedRuntimeCandidate);

            Assert.Equal(
                expectedMode,
                identity.Qualification.RuntimeMode);
            Assert.Equal(
                BuildIdentity.ToLowerInvariant(),
                identity.Qualification.BuildIdentity);
            Assert.Equal(
                PayloadClosure.ToLowerInvariant(),
                identity.Qualification.PayloadClosure);
            Assert.Null(identity.Qualification.UnqualifiedReason);
            Assert.Equal(CoreSha256(), identity.CoreSha256);
        }

        [Theory]
        [InlineData("cf7-runtime-manifest-v1")]
        [InlineData("CF7-RUNTIME-MANIFEST-V2")]
        [InlineData("")]
        public void ResolveRejectsInvalidManifestHeader(
            string header)
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteManifest(
                header,
                BuildLine,
                PayloadLine,
                ExactCoreLine);

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_manifest_header_invalid",
                error.Message);
        }

        [Theory]
        [InlineData(
            "buildIdentityHash",
            "agent_runtime_manifest_duplicate_buildIdentityHash")]
        [InlineData(
            "payloadClosureHash",
            "agent_runtime_manifest_duplicate_payloadClosureHash")]
        [InlineData(
            "file",
            "agent_runtime_manifest_file_invalid")]
        public void ResolveRejectsDuplicateManifestFields(
            string duplicate,
            string expectedMessage)
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            string[] lines = ValidManifest();
            string duplicateLine = duplicate switch
            {
                "buildIdentityHash" => BuildLine,
                "payloadClosureHash" => PayloadLine,
                _ => ExactCoreLine
            };
            Array.Resize(ref lines, lines.Length + 1);
            lines[lines.Length - 1] = duplicateLine;
            scope.WriteManifest(lines);

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(expectedMessage, error.Message);
        }

        [Theory]
        [InlineData("buildIdentityHash", 63, 'A')]
        [InlineData("buildIdentityHash", 64, 'G')]
        [InlineData("payloadClosureHash", 65, 'B')]
        [InlineData("file", 64, 'Z')]
        public void ResolveRejectsMalformedSha256(
            string field,
            int length,
            char character)
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            string invalidHash = new string(character, length);
            string build = field == "buildIdentityHash"
                ? "buildIdentityHash\t" + invalidHash
                : BuildLine;
            string payload = field == "payloadClosureHash"
                ? "payloadClosureHash\t" + invalidHash
                : PayloadLine;
            string file = field == "file"
                ? FileLine(
                    CoreRelativePath,
                    CoreLength,
                    invalidHash)
                : ExactCoreLine;
            scope.WriteManifest(
                Header,
                build,
                payload,
                file);

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_manifest_hash_invalid",
                error.Message);
        }

        [Theory]
        [InlineData("-1")]
        [InlineData("+1")]
        [InlineData(" 1")]
        [InlineData("not-a-number")]
        [InlineData("9223372036854775808")]
        public void ResolveRejectsInvalidManifestFileLength(
            string length)
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteManifest(
                Header,
                BuildLine,
                PayloadLine,
                "file\t"
                    + CoreRelativePath
                    + "\t"
                    + length
                    + "\t"
                    + CoreSha256());

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_manifest_file_invalid",
                error.Message);
        }

        [Theory]
        [InlineData("../evil.dll")]
        [InlineData("runtime/../evil.dll")]
        [InlineData("runtime\\..\\evil.dll")]
        [InlineData("C:\\runtime\\evil.dll")]
        public void ResolveRejectsManifestPathTraversal(
            string relativePath)
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteManifest(
                Header,
                BuildLine,
                PayloadLine,
                FileLine(
                    relativePath,
                    CoreLength,
                    CoreSha256()));

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_manifest_file_invalid",
                error.Message);
        }

        [Fact]
        public void ResolveRejectsEmptyManifest()
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteRaw(string.Empty);

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_manifest_size_invalid",
                error.Message);
        }

        [Fact]
        public void ResolveRejectsOversizedManifest()
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteRaw(new string('X', (1024 * 1024) + 1));

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_manifest_size_invalid",
                error.Message);
        }

        [Fact]
        public void ResolveRejectsMissingActualCoreRow()
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteManifest(
                Header,
                BuildLine,
                PayloadLine,
                FileLine(
                    "runtime/not-the-loaded-core.dll",
                    CoreLength,
                    CoreSha256()));

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_core_manifest_mismatch",
                error.Message);
        }

        [Fact]
        public void ResolveRejectsActualCoreLengthMismatch()
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteManifest(
                Header,
                BuildLine,
                PayloadLine,
                FileLine(
                    CoreRelativePath,
                    CoreLength + 1,
                    CoreSha256()));

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_core_manifest_mismatch",
                error.Message);
        }

        [Fact]
        public void ResolveRejectsActualCoreHashMismatch()
        {
            using var scope =
                new BaseDirectoryScope("runtime");
            scope.WriteManifest(
                Header,
                BuildLine,
                PayloadLine,
                FileLine(
                    CoreRelativePath,
                    CoreLength,
                    new string('0', 64)));

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () => AgentRuntimeHostIdentity.Resolve(false));

            Assert.Equal(
                "agent_runtime_core_manifest_mismatch",
                error.Message);
        }

        private const string Header =
            "cf7-runtime-manifest-v2";

        private static string BuildLine =>
            "buildIdentityHash\t" + BuildIdentity;

        private static string PayloadLine =>
            "payloadClosureHash\t" + PayloadClosure;

        private static string CorePath =>
            typeof(AgentRuntimeHostIdentity).Assembly.Location;

        private static long CoreLength =>
            new FileInfo(CorePath).Length;

        private static string CoreRelativePath =>
            "runtime/" + Path.GetFileName(CorePath);

        private static string ExactCoreLine =>
            FileLine(
                CoreRelativePath,
                CoreLength,
                CoreSha256());

        private static string[] ValidManifest()
        {
            return new[]
            {
                Header,
                BuildLine,
                PayloadLine,
                ExactCoreLine
            };
        }

        private static string FileLine(
            string relativePath,
            long length,
            string sha256)
        {
            return "file\t"
                + relativePath
                + "\t"
                + length
                + "\t"
                + sha256;
        }

        private static string CoreSha256()
        {
            using FileStream stream = new FileStream(
                CorePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete);
            return Convert.ToHexString(
                    SHA256.HashData(stream))
                .ToLowerInvariant();
        }

        private sealed class BaseDirectoryScope : IDisposable
        {
            private const string BaseDirectoryData =
                "APP_CONTEXT_BASE_DIRECTORY";
            private readonly object _previousBaseDirectory;
            private readonly string _root;
            private bool _disposed;

            public BaseDirectoryScope(string leafName)
            {
                _previousBaseDirectory =
                    AppDomain.CurrentDomain.GetData(
                        BaseDirectoryData);
                _root = Path.Combine(
                    Path.GetTempPath(),
                    "cf7-agent-runtime-identity-tests-"
                        + Guid.NewGuid().ToString("N"));
                DirectoryPath = Path.Combine(
                    _root,
                    leafName);
                Directory.CreateDirectory(DirectoryPath);
                AppDomain.CurrentDomain.SetData(
                    BaseDirectoryData,
                    DirectoryPath
                        + Path.DirectorySeparatorChar);
            }

            public string DirectoryPath { get; }

            public void WriteManifest(
                params string[] lines)
            {
                File.WriteAllLines(
                    Path.Combine(
                        DirectoryPath,
                        "cf7-runtime-manifest.tsv"),
                    lines,
                    new UTF8Encoding(false));
            }

            public void WriteRaw(string content)
            {
                File.WriteAllText(
                    Path.Combine(
                        DirectoryPath,
                        "cf7-runtime-manifest.tsv"),
                    content,
                    new UTF8Encoding(false));
            }

            public void Dispose()
            {
                if (_disposed)
                    return;
                _disposed = true;
                AppDomain.CurrentDomain.SetData(
                    BaseDirectoryData,
                    _previousBaseDirectory);
                Directory.Delete(_root, recursive: true);
            }
        }
    }
}
