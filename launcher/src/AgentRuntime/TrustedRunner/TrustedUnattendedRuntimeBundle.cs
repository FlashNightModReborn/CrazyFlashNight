using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CF7Launcher.AgentRuntime.TrustedRunner
{
    internal sealed class TrustedUnattendedRuntimeBundle
    {
        private const string ManifestHeader =
            "cf7-runtime-manifest-v2";
        private const string CandidateSchema =
            "cf7-runtime-candidate-metadata.v2";
        private static readonly HashSet<string> MetadataNames =
            new HashSet<string>(
                new[]
                {
                    "publishMode",
                    "artifactSourceHash",
                    "producerRecipeHash",
                    "toolchainLockHash",
                    "toolchainBaseline",
                    "buildIdentityHash",
                    "payloadClosureHash"
                },
                StringComparer.Ordinal);

        private TrustedUnattendedRuntimeBundle(
            string projectRoot,
            string deploymentRoot,
            string corePath,
            string runtimeMode,
            string buildIdentity,
            string payloadClosure,
            string coreSha256,
            long coreSize)
        {
            ProjectRoot = projectRoot;
            DeploymentRoot = deploymentRoot;
            CorePath = corePath;
            RuntimeMode = runtimeMode;
            BuildIdentity = buildIdentity;
            PayloadClosure = payloadClosure;
            CoreSha256 = coreSha256;
            CoreSize = coreSize;
        }

        public string ProjectRoot { get; }
        public string DeploymentRoot { get; }
        public string CorePath { get; }
        public string RuntimeMode { get; }
        public string BuildIdentity { get; }
        public string PayloadClosure { get; }
        public string CoreSha256 { get; }
        public long CoreSize { get; }

        public static TrustedUnattendedRuntimeBundle VerifySelectedProcess(
            string processPath = null,
            bool verifyNativePolicy = true)
        {
            string corePath = CanonicalFile(
                processPath ?? Environment.ProcessPath,
                "trusted_runner_process_invalid");
            DirectoryInfo runtimeDirectory =
                Directory.GetParent(corePath)
                ?? throw Fail("trusted_runner_runtime_root_invalid");
            if (!string.Equals(
                    runtimeDirectory.Name,
                    "runtime",
                    StringComparison.OrdinalIgnoreCase))
            {
                throw Fail("trusted_runner_runtime_root_invalid");
            }

            string deploymentRoot =
                CanonicalDirectory(
                    runtimeDirectory.Parent?.FullName,
                    "trusted_runner_deployment_root_invalid");
            string expectedCore = Path.Combine(
                deploymentRoot,
                "runtime",
                "CRAZYFLASHER7MercenaryEmpire.Core.exe");
            if (!SamePath(corePath, expectedCore))
                throw Fail("trusted_runner_core_path_invalid");

            string projectRoot;
            string runtimeMode;
            string metadataPath = Path.Combine(
                deploymentRoot,
                "runtime-build-metadata.v2.json");
            if (File.Exists(metadataPath))
            {
                runtimeMode = "isolated_candidate";
                projectRoot = DeriveCandidateProjectRoot(
                    deploymentRoot);
            }
            else
            {
                runtimeMode = "formal_runtime";
                projectRoot = deploymentRoot;
                RequireProjectSentinels(projectRoot);
            }

            RejectReparseChain(
                corePath,
                projectRoot);

            Manifest manifest = ReadAndVerifyManifest(
                deploymentRoot);
            if (runtimeMode == "isolated_candidate")
            {
                VerifyCandidateMetadata(
                    metadataPath,
                    manifest);
                RequireProjectSentinels(projectRoot);
            }

            FileRow coreRow = manifest.Files.SingleOrDefault(
                row => string.Equals(
                    row.Path,
                    "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe",
                    StringComparison.Ordinal));
            if (coreRow == null)
                throw Fail("trusted_runner_core_not_in_payload");
            FileRow bootstrapRow =
                manifest.Files.SingleOrDefault(
                    row => string.Equals(
                        row.Path,
                        "CRAZYFLASHER7MercenaryEmpire.exe",
                        StringComparison.Ordinal));
            if (bootstrapRow == null)
                throw Fail(
                    "trusted_runner_bootstrap_not_in_payload");
            if (verifyNativePolicy)
            {
                VerifyNativePolicy(
                    deploymentRoot,
                    runtimeMode);
            }

            return new TrustedUnattendedRuntimeBundle(
                projectRoot,
                deploymentRoot,
                corePath,
                runtimeMode,
                manifest.Metadata["buildIdentityHash"]
                    .ToLowerInvariant(),
                manifest.Metadata["payloadClosureHash"]
                    .ToLowerInvariant(),
                coreRow.Sha256.ToLowerInvariant(),
                coreRow.Size);
        }

        private static void VerifyNativePolicy(
            string deploymentRoot,
            string runtimeMode)
        {
            string bootstrapPath = CanonicalFile(
                Path.Combine(
                    deploymentRoot,
                    "CRAZYFLASHER7MercenaryEmpire.exe"),
                "trusted_runner_bootstrap_missing");
            var startInfo = new ProcessStartInfo
            {
                FileName = bootstrapPath,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = deploymentRoot,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            startInfo.ArgumentList.Add(
                string.Equals(
                    runtimeMode,
                    "isolated_candidate",
                    StringComparison.Ordinal)
                    ? "--verify-runtime-only"
                    : "--verify-only");
            using Process verifier =
                Process.Start(startInfo)
                ?? throw Fail(
                    "trusted_runner_native_verifier_start_failed");
            System.Threading.Tasks.Task outputDrain =
                verifier.StandardOutput.BaseStream
                    .CopyToAsync(Stream.Null);
            System.Threading.Tasks.Task errorDrain =
                verifier.StandardError.BaseStream
                    .CopyToAsync(Stream.Null);
            if (!verifier.WaitForExit(60_000))
            {
                try
                {
                    verifier.Kill(
                        entireProcessTree: true);
                }
                catch
                {
                }
                throw Fail(
                    "trusted_runner_native_verifier_timeout");
            }
            System.Threading.Tasks.Task.WhenAll(
                    outputDrain,
                    errorDrain)
                .GetAwaiter()
                .GetResult();
            if (verifier.ExitCode != 0)
            {
                throw Fail(
                    "trusted_runner_native_policy_rejected");
            }
        }

        private static string DeriveCandidateProjectRoot(
            string deploymentRoot)
        {
            DirectoryInfo candidate =
                new DirectoryInfo(deploymentRoot);
            DirectoryInfo v2 = candidate.Parent;
            DirectoryInfo candidates = v2?.Parent;
            DirectoryInfo temporary = candidates?.Parent;
            DirectoryInfo project = temporary?.Parent;
            if (project == null
                || !string.Equals(
                    v2?.Name,
                    "v2",
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    candidates?.Name,
                    "runtime-candidates",
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    temporary?.Name,
                    "tmp",
                    StringComparison.OrdinalIgnoreCase)
                || !IsOpaqueSegment(candidate.Name))
            {
                throw Fail("trusted_runner_candidate_path_invalid");
            }

            string projectRoot =
                CanonicalDirectory(
                    project.FullName,
                    "trusted_runner_project_root_invalid");
            string expectedBase = Path.Combine(
                projectRoot,
                "tmp",
                "runtime-candidates",
                "v2");
            if (!IsContainedPath(expectedBase, deploymentRoot))
                throw Fail("trusted_runner_candidate_path_invalid");
            return projectRoot;
        }

        private static Manifest ReadAndVerifyManifest(
            string deploymentRoot)
        {
            string manifestPath = CanonicalFile(
                Path.Combine(
                    deploymentRoot,
                    "runtime",
                    "cf7-runtime-manifest.tsv"),
                "trusted_runner_manifest_missing");
            FileInfo manifestInfo = new FileInfo(manifestPath);
            if (manifestInfo.Length <= 0
                || manifestInfo.Length > 8 * 1024 * 1024)
            {
                throw Fail("trusted_runner_manifest_size_invalid");
            }

            string[] lines = File.ReadAllLines(
                manifestPath,
                new UTF8Encoding(false, true));
            if (lines.Length < 9
                || !string.Equals(
                    lines[0],
                    ManifestHeader,
                    StringComparison.Ordinal))
            {
                throw Fail("trusted_runner_manifest_invalid");
            }

            var metadata =
                new Dictionary<string, string>(
                    StringComparer.Ordinal);
            var rows = new List<FileRow>();
            var paths = new HashSet<string>(
                StringComparer.Ordinal);
            for (int index = 1; index < lines.Length; index++)
            {
                string line = lines[index];
                if (line.Length == 0)
                    throw Fail("trusted_runner_manifest_invalid");
                string[] fields = line.Split('\t');
                if (fields.Length == 2
                    && MetadataNames.Contains(fields[0]))
                {
                    if (!metadata.TryAdd(
                            fields[0],
                            fields[1]))
                    {
                        throw Fail(
                            "trusted_runner_manifest_duplicate_metadata");
                    }
                    continue;
                }
                if (fields.Length != 4
                    || !string.Equals(
                        fields[0],
                        "file",
                        StringComparison.Ordinal))
                {
                    throw Fail("trusted_runner_manifest_invalid");
                }

                string relative = ValidateRelativePath(
                    fields[1]);
                if (!paths.Add(relative)
                    || !long.TryParse(
                        fields[2],
                        NumberStyles.None,
                        CultureInfo.InvariantCulture,
                        out long size)
                    || size < 0
                    || !IsSha256(fields[3]))
                {
                    throw Fail("trusted_runner_manifest_file_invalid");
                }
                rows.Add(
                    new FileRow(
                        relative,
                        size,
                        fields[3].ToUpperInvariant()));
            }
            if (!metadata.Keys.ToHashSet(
                    StringComparer.Ordinal)
                .SetEquals(MetadataNames))
            {
                throw Fail("trusted_runner_manifest_metadata_invalid");
            }
            foreach (string hashName in new[]
            {
                "artifactSourceHash",
                "producerRecipeHash",
                "toolchainLockHash",
                "buildIdentityHash",
                "payloadClosureHash"
            })
            {
                if (!IsSha256(metadata[hashName]))
                    throw Fail("trusted_runner_manifest_hash_invalid");
            }

            string expectedBuildIdentity = Sha256Hex(
                "artifactSourceHash\t"
                    + metadata["artifactSourceHash"]
                        .ToUpperInvariant()
                    + "\nproducerRecipeHash\t"
                    + metadata["producerRecipeHash"]
                        .ToUpperInvariant()
                    + "\ntoolchainLockHash\t"
                    + metadata["toolchainLockHash"]
                        .ToUpperInvariant()
                    + "\n");
            if (!string.Equals(
                    expectedBuildIdentity,
                    metadata["buildIdentityHash"],
                    StringComparison.OrdinalIgnoreCase))
            {
                throw Fail("trusted_runner_build_identity_mismatch");
            }

            foreach (FileRow row in rows)
            {
                string fullPath = Path.GetFullPath(
                    Path.Combine(
                        deploymentRoot,
                        row.Path.Replace(
                            '/',
                            Path.DirectorySeparatorChar)));
                if (!IsContainedPath(
                        deploymentRoot,
                        fullPath))
                {
                    throw Fail("trusted_runner_payload_path_escape");
                }
                fullPath = CanonicalFile(
                    fullPath,
                    "trusted_runner_payload_missing");
                RejectReparseChain(
                    fullPath,
                    deploymentRoot);
                FileInfo file = new FileInfo(
                    fullPath);
                if (file.Length != row.Size
                    || !string.Equals(
                        HashFile(fullPath),
                        row.Sha256,
                        StringComparison.OrdinalIgnoreCase))
                {
                    throw Fail("trusted_runner_payload_mismatch");
                }
            }

            string canonicalClosure = string.Concat(
                rows.OrderBy(
                        row => row.Path,
                        StringComparer.Ordinal)
                    .Select(
                        row => row.Path
                            + "\t"
                            + row.Size.ToString(
                                CultureInfo.InvariantCulture)
                            + "\t"
                            + row.Sha256.ToUpperInvariant()
                            + "\n"));
            if (!string.Equals(
                    Sha256Hex(canonicalClosure),
                    metadata["payloadClosureHash"],
                    StringComparison.OrdinalIgnoreCase))
            {
                throw Fail("trusted_runner_payload_closure_mismatch");
            }

            return new Manifest(metadata, rows);
        }

        private static void VerifyCandidateMetadata(
            string metadataPath,
            Manifest manifest)
        {
            FileInfo info = new FileInfo(
                CanonicalFile(
                    metadataPath,
                    "trusted_runner_candidate_metadata_missing"));
            if (info.Length <= 0
                || info.Length > 64 * 1024)
            {
                throw Fail(
                    "trusted_runner_candidate_metadata_invalid");
            }
            RejectReparseChain(
                metadataPath,
                info.Directory?.Parent?.Parent?.Parent
                    ?.Parent?.Parent?.FullName);
            using JsonDocument document =
                JsonDocument.Parse(
                    File.ReadAllBytes(metadataPath),
                    new JsonDocumentOptions
                    {
                        AllowTrailingCommas = false,
                        CommentHandling =
                            JsonCommentHandling.Disallow,
                        MaxDepth = 8
                    });
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
                throw Fail(
                    "trusted_runner_candidate_metadata_invalid");
            var seen = new HashSet<string>(
                StringComparer.Ordinal);
            foreach (JsonProperty property
                in root.EnumerateObject())
            {
                if (!seen.Add(property.Name))
                    throw Fail(
                        "trusted_runner_candidate_metadata_invalid");
            }
            if (!root.TryGetProperty(
                    "schema",
                    out JsonElement schema)
                || !string.Equals(
                    schema.GetString(),
                    CandidateSchema,
                    StringComparison.Ordinal)
                || !root.TryGetProperty(
                    "buildIdentityHash",
                    out JsonElement build)
                || !root.TryGetProperty(
                    "payloadClosureHash",
                    out JsonElement closure)
                || !string.Equals(
                    build.GetString(),
                    manifest.Metadata["buildIdentityHash"],
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    closure.GetString(),
                    manifest.Metadata["payloadClosureHash"],
                    StringComparison.OrdinalIgnoreCase))
            {
                throw Fail(
                    "trusted_runner_candidate_metadata_mismatch");
            }
        }

        private static void RequireProjectSentinels(
            string projectRoot)
        {
            foreach (string relative in new[]
            {
                "crossdomain.xml",
                @"launcher\web\bootstrap.html"
            })
            {
                string path = Path.Combine(
                    projectRoot,
                    relative);
                CanonicalFile(
                    path,
                    "trusted_runner_project_sentinel_missing");
                RejectReparseChain(path, projectRoot);
            }
        }

        internal static void RejectReparseChain(
            string leafPath,
            string rootPath)
        {
            if (string.IsNullOrWhiteSpace(rootPath))
                throw Fail("trusted_runner_path_root_invalid");
            string root = Path.TrimEndingDirectorySeparator(
                Path.GetFullPath(rootPath));
            string leaf = Path.GetFullPath(leafPath);
            if (!IsContainedPath(root, leaf))
                throw Fail("trusted_runner_path_escape");

            FileSystemInfo current = File.Exists(leaf)
                ? new FileInfo(leaf)
                : new DirectoryInfo(leaf);
            while (current != null)
            {
                if ((current.Attributes
                        & FileAttributes.ReparsePoint) != 0)
                {
                    throw Fail("trusted_runner_reparse_rejected");
                }
                string currentPath =
                    Path.TrimEndingDirectorySeparator(
                        current.FullName);
                if (SamePath(currentPath, root))
                    return;
                current = current switch
                {
                    FileInfo file => file.Directory,
                    DirectoryInfo directory =>
                        directory.Parent,
                    _ => null
                };
            }
            throw Fail("trusted_runner_path_escape");
        }

        internal static bool SamePath(
            string left,
            string right)
        {
            return string.Equals(
                Path.TrimEndingDirectorySeparator(
                    Path.GetFullPath(left)),
                Path.TrimEndingDirectorySeparator(
                    Path.GetFullPath(right)),
                StringComparison.OrdinalIgnoreCase);
        }

        internal static bool IsContainedPath(
            string root,
            string path)
        {
            string canonicalRoot =
                Path.TrimEndingDirectorySeparator(
                    Path.GetFullPath(root));
            string canonicalPath =
                Path.TrimEndingDirectorySeparator(
                    Path.GetFullPath(path));
            return SamePath(
                    canonicalRoot,
                    canonicalPath)
                || canonicalPath.StartsWith(
                    canonicalRoot
                        + Path.DirectorySeparatorChar,
                    StringComparison.OrdinalIgnoreCase);
        }

        internal static string HashFile(string path)
        {
            using FileStream stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                64 * 1024,
                FileOptions.SequentialScan);
            return Convert.ToHexString(
                SHA256.HashData(stream));
        }

        private static string ValidateRelativePath(
            string value)
        {
            string normalized =
                (value ?? string.Empty)
                    .Replace('\\', '/');
            if (normalized.Length == 0
                || normalized.StartsWith(
                    "/",
                    StringComparison.Ordinal)
                || normalized.Contains('\t')
                || normalized.Contains('\r')
                || normalized.Contains('\n')
                || normalized.Split('/').Any(
                    segment => segment.Length == 0
                        || segment == "."
                        || segment == "..")
                || !string.Equals(
                    value,
                    normalized,
                    StringComparison.Ordinal))
            {
                throw Fail("trusted_runner_payload_path_invalid");
            }
            return normalized;
        }

        private static string CanonicalFile(
            string path,
            string reason)
        {
            if (string.IsNullOrWhiteSpace(path)
                || !File.Exists(path))
            {
                throw Fail(reason);
            }
            FileInfo info = new FileInfo(
                Path.GetFullPath(path));
            if ((info.Attributes
                    & (FileAttributes.Directory
                        | FileAttributes.ReparsePoint)) != 0)
            {
                throw Fail(reason);
            }
            return info.FullName;
        }

        private static string CanonicalDirectory(
            string path,
            string reason)
        {
            if (string.IsNullOrWhiteSpace(path)
                || !Directory.Exists(path))
            {
                throw Fail(reason);
            }
            DirectoryInfo info = new DirectoryInfo(
                Path.GetFullPath(path));
            if ((info.Attributes
                    & FileAttributes.ReparsePoint) != 0)
            {
                throw Fail(reason);
            }
            return Path.TrimEndingDirectorySeparator(
                info.FullName);
        }

        private static bool IsOpaqueSegment(string value)
        {
            return !string.IsNullOrEmpty(value)
                && value.Length <= 128
                && value.All(
                    character =>
                        (character >= 'A'
                            && character <= 'Z')
                        || (character >= 'a'
                            && character <= 'z')
                        || (character >= '0'
                            && character <= '9')
                        || character == '-'
                        || character == '_');
        }

        private static bool IsSha256(string value)
        {
            return value != null
                && value.Length == 64
                && value.All(Uri.IsHexDigit);
        }

        private static string Sha256Hex(string value)
        {
            return Convert.ToHexString(
                SHA256.HashData(
                    Encoding.UTF8.GetBytes(value)));
        }

        private static InvalidDataException Fail(
            string reason)
        {
            return new InvalidDataException(reason);
        }

        private sealed class Manifest
        {
            public Manifest(
                IReadOnlyDictionary<string, string> metadata,
                IReadOnlyList<FileRow> files)
            {
                Metadata = metadata;
                Files = files;
            }

            public IReadOnlyDictionary<string, string>
                Metadata { get; }
            public IReadOnlyList<FileRow> Files { get; }
        }

        private sealed class FileRow
        {
            public FileRow(
                string path,
                long size,
                string sha256)
            {
                Path = path;
                Size = size;
                Sha256 = sha256;
            }

            public string Path { get; }
            public long Size { get; }
            public string Sha256 { get; }
        }
    }
}
