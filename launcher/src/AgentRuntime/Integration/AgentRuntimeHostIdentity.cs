using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Exact identity consumed by the in-process Agent Runtime. Formal and
    /// isolated-candidate identities are accepted only when the manifest row
    /// for the assembly that is actually executing matches its bytes.
    /// </summary>
    internal sealed class AgentRuntimeHostIdentity
    {
        internal AgentRuntimeHostIdentity(
            RuntimeQualificationRegistration qualification,
            string coreSha256)
        {
            Qualification = qualification;
            CoreSha256 = coreSha256;
        }

        public RuntimeQualificationRegistration Qualification { get; }
        public string CoreSha256 { get; }

        public static AgentRuntimeHostIdentity Resolve(
            bool isolatedRuntimeCandidate)
        {
            string processPath = Path.GetFullPath(
                Environment.ProcessPath
                ?? throw new InvalidOperationException(
                    "agent_runtime_process_path_unavailable"));
            string assemblyPath = Path.GetFullPath(
                typeof(AgentRuntimeHostIdentity).Assembly.Location);
            string coreSha256 = HashFile(assemblyPath);
            string baseDirectory = Path.TrimEndingDirectorySeparator(
                Path.GetFullPath(AppContext.BaseDirectory));

            if (!string.Equals(
                    Path.GetFileName(baseDirectory),
                    "runtime",
                    StringComparison.OrdinalIgnoreCase))
            {
                return new AgentRuntimeHostIdentity(
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode = RuntimeMode.UnqualifiedDev,
                        ActualProcessPath = processPath,
                        UnqualifiedReason =
                            "process_not_running_from_verified_runtime"
                    },
                    coreSha256);
            }

            string manifestPath = Path.Combine(
                baseDirectory,
                "cf7-runtime-manifest.tsv");
            ManifestIdentity manifest = ReadManifest(manifestPath);
            string expectedRelativePath =
                "runtime/"
                + Path.GetFileName(assemblyPath);
            if (!manifest.Files.TryGetValue(
                    expectedRelativePath,
                    out ManifestFile core)
                || core.Length != new FileInfo(assemblyPath).Length
                || !string.Equals(
                    core.Sha256,
                    coreSha256,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "agent_runtime_core_manifest_mismatch");
            }

            return new AgentRuntimeHostIdentity(
                new RuntimeQualificationRegistration
                {
                    RuntimeMode = isolatedRuntimeCandidate
                        ? RuntimeMode.IsolatedCandidate
                        : RuntimeMode.FormalRuntime,
                    BuildIdentity =
                        manifest.BuildIdentity.ToLowerInvariant(),
                    PayloadClosure =
                        manifest.PayloadClosure.ToLowerInvariant(),
                    ActualProcessPath = processPath
                },
                coreSha256.ToLowerInvariant());
        }

        private static ManifestIdentity ReadManifest(string path)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException(
                    "Agent Runtime manifest is missing.",
                    path);
            FileInfo info = new FileInfo(path);
            if (info.Length <= 0 || info.Length > 1024 * 1024)
                throw new InvalidDataException(
                    "agent_runtime_manifest_size_invalid");

            string[] lines = File.ReadAllLines(path);
            if (lines.Length < 2
                || !string.Equals(
                    lines[0],
                    "cf7-runtime-manifest-v2",
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "agent_runtime_manifest_header_invalid");
            }

            string buildIdentity = null;
            string payloadClosure = null;
            var files = new Dictionary<string, ManifestFile>(
                StringComparer.Ordinal);
            for (int index = 1; index < lines.Length; index++)
            {
                string[] fields = lines[index].Split('\t');
                if (fields.Length == 2
                    && string.Equals(
                        fields[0],
                        "buildIdentityHash",
                        StringComparison.Ordinal))
                {
                    if (buildIdentity != null)
                        throw Duplicate("buildIdentityHash");
                    buildIdentity = RequireSha256(fields[1]);
                }
                else if (fields.Length == 2
                    && string.Equals(
                        fields[0],
                        "payloadClosureHash",
                        StringComparison.Ordinal))
                {
                    if (payloadClosure != null)
                        throw Duplicate("payloadClosureHash");
                    payloadClosure = RequireSha256(fields[1]);
                }
                else if (fields.Length == 4
                    && string.Equals(
                        fields[0],
                        "file",
                        StringComparison.Ordinal))
                {
                    string relative = fields[1]
                        .Replace('\\', '/');
                    if (string.IsNullOrWhiteSpace(relative)
                        || Path.IsPathFullyQualified(relative)
                        || relative.Contains(
                            "..",
                            StringComparison.Ordinal)
                        || !long.TryParse(
                            fields[2],
                            NumberStyles.None,
                            CultureInfo.InvariantCulture,
                            out long length)
                        || length < 0
                        || !files.TryAdd(
                            relative,
                            new ManifestFile(
                                length,
                                RequireSha256(fields[3]))))
                    {
                        throw new InvalidDataException(
                            "agent_runtime_manifest_file_invalid");
                    }
                }
            }

            if (buildIdentity == null
                || payloadClosure == null)
            {
                throw new InvalidDataException(
                    "agent_runtime_manifest_identity_missing");
            }
            return new ManifestIdentity(
                buildIdentity,
                payloadClosure,
                files);
        }

        private static InvalidDataException Duplicate(string field)
        {
            return new InvalidDataException(
                "agent_runtime_manifest_duplicate_" + field);
        }

        private static string RequireSha256(string value)
        {
            if (value == null || value.Length != 64)
                throw new InvalidDataException(
                    "agent_runtime_manifest_hash_invalid");
            for (int index = 0; index < value.Length; index++)
            {
                if (!Uri.IsHexDigit(value[index]))
                    throw new InvalidDataException(
                        "agent_runtime_manifest_hash_invalid");
            }
            return value;
        }

        private static string HashFile(string path)
        {
            using FileStream stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete);
            return Convert.ToHexString(
                    SHA256.HashData(stream))
                .ToLowerInvariant();
        }

        private sealed record ManifestFile(
            long Length,
            string Sha256);

        private sealed record ManifestIdentity(
            string BuildIdentity,
            string PayloadClosure,
            Dictionary<string, ManifestFile> Files);
    }
}
