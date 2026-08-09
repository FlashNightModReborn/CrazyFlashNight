using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Tasks;

namespace CF7Launcher.Audio
{
    internal static class AudioQualificationInvocationV1
    {
        internal const string Flag = "--audio-v2-qualification-run-id";

        internal static bool ContainsFlagLike(string[] args)
        {
            if (args == null) return false;
            for (int index = 0; index < args.Length; index++)
            {
                string value = args[index];
                if (string.Equals(value, Flag, StringComparison.OrdinalIgnoreCase) ||
                    (value != null && value.StartsWith(
                        Flag + "=",
                        StringComparison.OrdinalIgnoreCase)))
                {
                    return true;
                }
            }
            return false;
        }

        internal static string ResolveRunId(
            string[] args,
            bool isolatedRuntimeCandidate)
        {
            if (args == null || args.Length == 0) return null;

            string runId = null;
            for (int index = 0; index < args.Length; index++)
            {
                string token = args[index];
                if (!string.Equals(
                    token,
                    Flag,
                    StringComparison.Ordinal))
                {
                    if (string.Equals(
                            token,
                            Flag,
                            StringComparison.OrdinalIgnoreCase) ||
                        (token != null && token.StartsWith(
                            Flag + "=",
                            StringComparison.OrdinalIgnoreCase)))
                    {
                        throw new ArgumentException(
                            "Audio v2 qualification flag syntax is not canonical.");
                    }
                    continue;
                }

                if (runId != null || index + 1 >= args.Length ||
                    !IsLowercaseHex32(args[index + 1]))
                {
                    throw new ArgumentException(
                        "Audio v2 qualification run id must be one 32-character lowercase hex value.");
                }
                runId = args[++index];
            }

            if (runId == null) return null;
            if (!isolatedRuntimeCandidate)
            {
                throw new InvalidOperationException(
                    "Audio v2 qualification is forbidden outside an isolated runtime candidate.");
            }
            if (HasToken(args, "--bus-only") ||
                HasToken(args, "--legacy-http-automation") ||
                HasToken(args, "--agent-unattended-runner") ||
                HasToken(args, "--unattended-bootstrap-request"))
            {
                throw new InvalidOperationException(
                    "Audio v2 qualification cannot be combined with alternate control-plane startup modes.");
            }
            return runId;
        }

        internal static bool IsLowercaseHex32(string value)
        {
            if (value == null || value.Length != 32) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char current = value[index];
                if (!((current >= '0' && current <= '9') ||
                    (current >= 'a' && current <= 'f')))
                {
                    return false;
                }
            }
            return true;
        }

        private static bool HasToken(string[] args, string token)
        {
            for (int index = 0; index < args.Length; index++)
            {
                if (string.Equals(
                    args[index],
                    token,
                    StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }
    }

    internal sealed class AudioQualificationCandidateIdentityV1
    {
        internal AudioQualificationCandidateIdentityV1(
            string buildIdentity,
            string executablePath,
            string executableSha256,
            string payloadClosure,
            int pid,
            DateTimeOffset processStartUtc)
        {
            if (!IsUpperSha256(buildIdentity) ||
                string.IsNullOrWhiteSpace(executablePath) ||
                !Path.IsPathFullyQualified(executablePath) ||
                !IsUpperSha256(executableSha256) ||
                !IsUpperSha256(payloadClosure) ||
                pid <= 0)
            {
                throw new ArgumentException(
                    "Qualification candidate identity is invalid.");
            }
            BuildIdentity = buildIdentity;
            ExecutablePath = Path.GetFullPath(executablePath);
            ExecutableSha256 = executableSha256;
            PayloadClosure = payloadClosure;
            Pid = pid;
            ProcessStartUtc = processStartUtc.ToUniversalTime();
        }

        internal string BuildIdentity { get; private set; }
        internal string ExecutablePath { get; private set; }
        internal string ExecutableSha256 { get; private set; }
        internal string PayloadClosure { get; private set; }
        internal int Pid { get; private set; }
        internal DateTimeOffset ProcessStartUtc { get; private set; }

        internal static AudioQualificationCandidateIdentityV1 LoadCurrent()
        {
            string executablePath = Environment.ProcessPath;
            if (string.IsNullOrWhiteSpace(executablePath) ||
                !File.Exists(executablePath))
            {
                throw new InvalidOperationException(
                    "Qualification Core executable path is unavailable.");
            }

            string runtimeDirectory = Path.TrimEndingDirectorySeparator(
                Path.GetFullPath(AppContext.BaseDirectory));
            string executableDirectory = Path.TrimEndingDirectorySeparator(
                Path.GetFullPath(
                    Path.GetDirectoryName(executablePath) ?? string.Empty));
            if (!string.Equals(
                executableDirectory,
                runtimeDirectory,
                StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "Qualification Core executable is outside its runtime directory.");
            }
            if (!string.Equals(
                Path.GetFileName(runtimeDirectory),
                "runtime",
                StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "Qualification Core is not executing from a runtime directory.");
            }
            string candidateRoot = Directory.GetParent(runtimeDirectory)?.FullName;
            if (string.IsNullOrEmpty(candidateRoot))
                throw new InvalidOperationException("Candidate root is unavailable.");

            string metadataPath = Path.Combine(
                candidateRoot,
                "runtime-build-metadata.v2.json");
            string manifestPath = Path.Combine(
                runtimeDirectory,
                "cf7-runtime-manifest.tsv");
            ReadMetadataIdentity(
                metadataPath,
                out string metadataBuild,
                out string metadataClosure);
            ReadManifestIdentity(
                manifestPath,
                out string manifestBuild,
                out string manifestClosure);
            if (!string.Equals(
                    metadataBuild,
                    manifestBuild,
                    StringComparison.Ordinal) ||
                !string.Equals(
                    metadataClosure,
                    manifestClosure,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Candidate metadata and runtime manifest identity differ.");
            }

            using (Process process = Process.GetCurrentProcess())
            {
                string modulePath = process.MainModule?.FileName;
                if (string.IsNullOrWhiteSpace(modulePath) ||
                    !string.Equals(
                        Path.GetFullPath(modulePath),
                        Path.GetFullPath(executablePath),
                        StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException(
                        "Qualification Core process module path is inconsistent.");
                }
                return new AudioQualificationCandidateIdentityV1(
                    metadataBuild,
                    executablePath,
                    Sha256File(executablePath),
                    metadataClosure,
                    process.Id,
                    new DateTimeOffset(
                        process.StartTime.ToUniversalTime(),
                        TimeSpan.Zero));
            }
        }

        internal void Write(Utf8JsonWriter writer)
        {
            writer.WriteStartObject();
            writer.WriteString("buildIdentity", BuildIdentity);
            writer.WriteString("executablePath", ExecutablePath);
            writer.WriteString("executableSha256", ExecutableSha256);
            writer.WriteString("payloadClosure", PayloadClosure);
            writer.WriteNumber("pid", Pid);
            writer.WriteString(
                "processStartUtc",
                FormatUtc(ProcessStartUtc));
            writer.WriteEndObject();
        }

        private static void ReadMetadataIdentity(
            string path,
            out string buildIdentity,
            out string payloadClosure)
        {
            buildIdentity = null;
            payloadClosure = null;
            if (!File.Exists(path) || new FileInfo(path).Length <= 0L ||
                new FileInfo(path).Length > 65536L)
            {
                throw new InvalidOperationException(
                    "Candidate metadata is missing or oversized.");
            }
            using (JsonDocument document = JsonDocument.Parse(
                File.ReadAllBytes(path),
                new JsonDocumentOptions
                {
                    AllowTrailingCommas = false,
                    CommentHandling = JsonCommentHandling.Disallow,
                    MaxDepth = 8
                }))
            {
                JsonElement root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object ||
                    !TryUniqueString(root, "schema", out string schema) ||
                    !string.Equals(
                        schema,
                        "cf7-runtime-candidate-metadata.v2",
                        StringComparison.Ordinal) ||
                    !TryUniqueString(
                        root,
                        "buildIdentityHash",
                        out buildIdentity) ||
                    !TryUniqueString(
                        root,
                        "payloadClosureHash",
                        out payloadClosure))
                {
                    throw new InvalidOperationException(
                        "Candidate metadata identity is invalid.");
                }
            }
            buildIdentity = buildIdentity.ToUpperInvariant();
            payloadClosure = payloadClosure.ToUpperInvariant();
            if (!IsUpperSha256(buildIdentity) ||
                !IsUpperSha256(payloadClosure))
            {
                throw new InvalidOperationException(
                    "Candidate metadata hashes are invalid.");
            }
        }

        private static void ReadManifestIdentity(
            string path,
            out string buildIdentity,
            out string payloadClosure)
        {
            buildIdentity = null;
            payloadClosure = null;
            if (!File.Exists(path) || new FileInfo(path).Length <= 0L ||
                new FileInfo(path).Length > 1048576L)
            {
                throw new InvalidOperationException(
                    "Runtime manifest is missing or oversized.");
            }
            string[] lines = File.ReadAllLines(path, new UTF8Encoding(false, true));
            if (lines.Length == 0 || !string.Equals(
                lines[0],
                "cf7-runtime-manifest-v2",
                StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Runtime manifest schema is invalid.");
            }
            for (int index = 1; index < lines.Length; index++)
            {
                string[] fields = lines[index].Split('\t');
                if (fields.Length != 2) continue;
                if (string.Equals(
                    fields[0],
                    "buildIdentityHash",
                    StringComparison.Ordinal))
                {
                    if (buildIdentity != null)
                        throw new InvalidOperationException(
                            "Runtime manifest build identity is duplicated.");
                    buildIdentity = fields[1].ToUpperInvariant();
                }
                else if (string.Equals(
                    fields[0],
                    "payloadClosureHash",
                    StringComparison.Ordinal))
                {
                    if (payloadClosure != null)
                        throw new InvalidOperationException(
                            "Runtime manifest payload closure is duplicated.");
                    payloadClosure = fields[1].ToUpperInvariant();
                }
            }
            if (!IsUpperSha256(buildIdentity) ||
                !IsUpperSha256(payloadClosure))
            {
                throw new InvalidOperationException(
                    "Runtime manifest identity is invalid.");
            }
        }

        private static bool TryUniqueString(
            JsonElement root,
            string name,
            out string value)
        {
            value = null;
            int count = 0;
            foreach (JsonProperty property in root.EnumerateObject())
            {
                if (!string.Equals(
                    property.Name,
                    name,
                    StringComparison.Ordinal)) continue;
                count++;
                if (property.Value.ValueKind != JsonValueKind.String)
                    return false;
                value = property.Value.GetString();
            }
            return count == 1 && value != null;
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha256 = SHA256.Create())
            using (FileStream stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read))
            {
                return Convert.ToHexString(sha256.ComputeHash(stream));
            }
        }

        private static bool IsUpperSha256(string value)
        {
            if (value == null || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char current = value[index];
                if (!((current >= '0' && current <= '9') ||
                    (current >= 'A' && current <= 'F')))
                {
                    return false;
                }
            }
            return true;
        }

        internal static string FormatUtc(DateTimeOffset value)
        {
            return value.ToUniversalTime().ToString(
                "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
                CultureInfo.InvariantCulture);
        }
    }

    internal sealed class AudioQualificationEventV1
    {
        internal string CaseId;
        internal string Kind;
        internal long MonotonicTicks;
        internal string ObservedAtUtc;
        internal byte[] Payload;
        internal string PreviousSha256;
        internal string RunId;
        internal long Sequence;
        internal string Sha256;
        internal string Source;

        internal void Write(Utf8JsonWriter writer)
        {
            writer.WriteStartObject();
            if (CaseId == null) writer.WriteNull("caseId");
            else writer.WriteString("caseId", CaseId);
            writer.WriteString("kind", Kind);
            writer.WriteNumber("monotonicTicks", MonotonicTicks);
            writer.WriteString("observedAtUtc", ObservedAtUtc);
            writer.WritePropertyName("payload");
            AudioQualificationDiagnosticsHostV1.WriteRawObject(
                writer,
                Payload);
            writer.WriteString("previousSha256", PreviousSha256);
            writer.WriteString("runId", RunId);
            writer.WriteNumber("sequence", Sequence);
            writer.WriteString("sha256", Sha256);
            writer.WriteString("source", Source);
            writer.WriteEndObject();
        }
    }

    internal sealed class AudioQualificationDiagnosticsHostV1
        : IAudioTaskQualificationObserverV2, IDisposable
    {
        internal const string Protocol =
            "cf7.audio-v2.qualification-pipe.v1";
        internal const string ResponseSchema =
            "cf7.audio-v2.qualification-response.v1";
        internal const int MaxRequestBytes = 65536;
        internal const int MaxRequestsPerClient = 512;
        internal const int MaxConnections = 1024;
        internal const int MaxTotalRequests = 4096;
        internal const int MaxJournalEvents = 4096;
        internal const int MaxJournalByteBudget = 8 * 1024 * 1024;
        internal const int MaxCrossfadeAutomaticSamples = 150;
        internal const int CrossfadeSamplerWindowMilliseconds = 15000;
        private const int IoTimeoutMilliseconds = 5000;
        private const int CrossfadeSampleIntervalMilliseconds = 100;
        private const int SamplerStopTimeoutMilliseconds = 1000;
        private const int MaxResponseBytes = 16 * 1024 * 1024;
        private const string ZeroSha256 =
            "0000000000000000000000000000000000000000000000000000000000000000";

        private static readonly string[] OrderedCaseIds =
        {
            "bgm_playback",
            "bgm_seek",
            "bgm_crossfade",
            "format_vorbis",
            "format_aac_mp4",
            "format_opus",
            "sfx_playback",
            "dense_overlap_throttle",
            "bgm_sfx_mix",
            "gain_zero_and_default_max",
            "default_device_switch",
            "physical_route_bluetooth_or_hdmi",
            "sleep_resume",
            "no_stale_sfx_after_recovery"
        };

        private static readonly JsonWriterOptions WriterOptions =
            new JsonWriterOptions
            {
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                Indented = false,
                SkipValidation = false
            };
        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);

        private readonly object _sync = new object();
        private readonly string _runId;
        private readonly AudioQualificationCandidateIdentityV1 _candidate;
        private readonly Func<AudioCoordinatorSnapshotV2> _snapshotProvider;
        private readonly int _crossfadeSampleIntervalMilliseconds;
        private readonly int _crossfadeSamplerWindowMilliseconds;
        private readonly int _maxCrossfadeAutomaticSamples;
        private readonly List<AudioQualificationEventV1> _events =
            new List<AudioQualificationEventV1>();
        private readonly HashSet<string> _requestIds =
            new HashSet<string>(StringComparer.Ordinal);
        private readonly CancellationTokenSource _lifetime =
            new CancellationTokenSource();
        private NamedPipeServerStream _server;
        private Task _serverTask;
        private CancellationTokenSource _crossfadeSamplerCancellation;
        private Task _crossfadeSamplerTask;
        private Action _unsubscribe = delegate { };
        private string _activeCaseId;
        private int _nextCaseIndex;
        private long _lastMonotonicTicks;
        private string _lastSha256 = ZeroSha256;
        private bool _journalOverflow;
        private long _journalByteBudget;
        private int _totalRequests;
        private int _disposed;

        private AudioQualificationDiagnosticsHostV1(
            string runId,
            AudioQualificationCandidateIdentityV1 candidate,
            Func<AudioCoordinatorSnapshotV2> snapshotProvider,
            int maxCrossfadeAutomaticSamples =
                MaxCrossfadeAutomaticSamples,
            int crossfadeSampleIntervalMilliseconds =
                CrossfadeSampleIntervalMilliseconds,
            int crossfadeSamplerWindowMilliseconds =
                CrossfadeSamplerWindowMilliseconds)
        {
            if (!AudioQualificationInvocationV1.IsLowercaseHex32(runId))
                throw new ArgumentException("runId");
            if (maxCrossfadeAutomaticSamples <= 0 ||
                maxCrossfadeAutomaticSamples >
                    MaxCrossfadeAutomaticSamples ||
                crossfadeSampleIntervalMilliseconds <= 0 ||
                crossfadeSampleIntervalMilliseconds >
                    CrossfadeSampleIntervalMilliseconds ||
                crossfadeSamplerWindowMilliseconds <= 0 ||
                crossfadeSamplerWindowMilliseconds >
                    CrossfadeSamplerWindowMilliseconds)
            {
                throw new ArgumentOutOfRangeException(
                    "Qualification sampler test bounds are invalid.");
            }
            _runId = runId;
            _candidate = candidate ?? throw new ArgumentNullException("candidate");
            _snapshotProvider = snapshotProvider ??
                throw new ArgumentNullException("snapshotProvider");
            _maxCrossfadeAutomaticSamples =
                maxCrossfadeAutomaticSamples;
            _crossfadeSampleIntervalMilliseconds =
                crossfadeSampleIntervalMilliseconds;
            _crossfadeSamplerWindowMilliseconds =
                crossfadeSamplerWindowMilliseconds;
            PipeName = BuildPipeName(candidate.Pid, runId);
        }

        internal string PipeName { get; private set; }
        internal bool UsesCurrentUserOnly { get { return true; } }

        internal static AudioQualificationDiagnosticsHostV1 StartProduction(
            string runId)
        {
            var host = new AudioQualificationDiagnosticsHostV1(
                runId,
                AudioQualificationCandidateIdentityV1.LoadCurrent(),
                AudioEngine.CaptureQualificationSnapshot);
            Action<AudioCoordinatorSnapshotV2> handler =
                host.RecordCoordinatorSnapshot;
            AudioEngine.SnapshotChanged += handler;
            host._unsubscribe = delegate
            {
                AudioEngine.SnapshotChanged -= handler;
            };
            try
            {
                host.StartPipe();
                return host;
            }
            catch
            {
                host.Dispose();
                throw;
            }
        }

        internal static AudioQualificationDiagnosticsHostV1 StartForTests(
            string runId,
            AudioQualificationCandidateIdentityV1 candidate,
            Func<AudioCoordinatorSnapshotV2> snapshotProvider,
            int maxCrossfadeAutomaticSamples =
                MaxCrossfadeAutomaticSamples,
            int crossfadeSampleIntervalMilliseconds =
                CrossfadeSampleIntervalMilliseconds,
            int crossfadeSamplerWindowMilliseconds =
                CrossfadeSamplerWindowMilliseconds)
        {
            var host = new AudioQualificationDiagnosticsHostV1(
                runId,
                candidate,
                snapshotProvider,
                maxCrossfadeAutomaticSamples,
                crossfadeSampleIntervalMilliseconds,
                crossfadeSamplerWindowMilliseconds);
            host.StartPipe();
            return host;
        }

        internal static string BuildPipeName(int pid, string runId)
        {
            if (pid <= 0 ||
                !AudioQualificationInvocationV1.IsLowercaseHex32(runId))
            {
                throw new ArgumentException("Pipe identity is invalid.");
            }
            return "cf7-audio-v2-qualification-" +
                pid.ToString(CultureInfo.InvariantCulture) + "-" + runId;
        }

        internal static byte[] CanonicalRequestForTests(
            string command,
            string requestId,
            string runId,
            string caseId,
            string routeKind = null)
        {
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                if (caseId != null) writer.WriteString("caseId", caseId);
                writer.WriteString("command", command);
                writer.WriteString("protocol", Protocol);
                writer.WriteString("requestId", requestId);
                if (routeKind != null)
                    writer.WriteString("routeKind", routeKind);
                writer.WriteString("runId", runId);
                writer.WriteEndObject();
            });
        }

        public void RecordBgmRequest(AudioBgmRequestV2 request)
        {
            if (request == null || !CanRecordActiveEvent()) return;
            AppendActiveEvent(
                "as2_bgm_request",
                "as2_ingress",
                WriteJson(delegate(Utf8JsonWriter writer)
                {
                    writer.WriteStartObject();
                    writer.WriteNumber(
                        "audioReadyGeneration",
                        request.AudioReadyGeneration);
                    writer.WriteString(
                        "audioSessionId",
                        request.AudioSessionId);
                    WriteNullableNumber(
                        writer,
                        "fadeSeconds",
                        request.FadeSeconds);
                    WriteNullableBoolean(writer, "loop", request.Loop);
                    writer.WriteString("operation", request.Operation);
                    WriteNullableString(writer, "path", request.Path);
                    writer.WriteString("requestId", request.RequestId);
                    WriteNullableNumber(
                        writer,
                        "seekSeconds",
                        request.SeekSeconds);
                    WriteNullableNumber(writer, "volume", request.Volume);
                    writer.WriteNumber("wireRevision", request.WireRevision);
                    writer.WriteEndObject();
                }));
        }

        public void RecordBgmResult(AudioBgmResultV2 result)
        {
            if (result == null || !CanRecordActiveEvent()) return;
            AppendActiveEvent(
                "as2_bgm_result",
                "audio_coordinator",
                WriteJson(delegate(Utf8JsonWriter writer)
                {
                    writer.WriteStartObject();
                    writer.WriteNumber(
                        "audioReadyGeneration",
                        result.AudioReadyGeneration);
                    writer.WriteString(
                        "audioSessionId",
                        result.AudioSessionId);
                    writer.WriteString("category", result.Category);
                    writer.WriteString(
                        "completionState",
                        result.CompletionState);
                    writer.WriteString(
                        "decoderBackend",
                        result.DecoderBackend);
                    writer.WriteNumber(
                        "deviceGeneration",
                        result.DeviceGeneration);
                    writer.WriteNumber("hresult", result.HResult);
                    writer.WriteString("messageKey", result.MessageKey);
                    writer.WriteNumber("nativeCode", result.NativeCode);
                    writer.WriteString("operation", result.Operation);
                    writer.WriteString("requestId", result.RequestId);
                    writer.WriteString("stage", result.Stage);
                    writer.WriteEndObject();
                }));
        }

        public void RecordSfxBatch(AudioSfxBatchV2 batch)
        {
            if (batch == null || !CanRecordActiveEvent()) return;
            AppendActiveEvent(
                "as2_sfx_batch",
                "as2_ingress",
                WriteJson(delegate(Utf8JsonWriter writer)
                {
                    writer.WriteStartObject();
                    writer.WriteNumber(
                        "audioReadyGeneration",
                        batch.AudioReadyGeneration);
                    writer.WriteString(
                        "audioSessionId",
                        batch.AudioSessionId);
                    writer.WriteNumber(
                        "batchSequence",
                        batch.BatchSequence);
                    writer.WritePropertyName("linkageIds");
                    writer.WriteStartArray();
                    for (int index = 0;
                        index < batch.LinkageIds.Count;
                        index++)
                    {
                        writer.WriteStringValue(batch.LinkageIds[index]);
                    }
                    writer.WriteEndArray();
                    writer.WriteNumber("wireRevision", batch.WireRevision);
                    writer.WriteEndObject();
                }));
        }

        internal void RecordCoordinatorSnapshot(
            AudioCoordinatorSnapshotV2 snapshot)
        {
            if (snapshot == null || !CanRecordActiveEvent()) return;
            string kind = snapshot.Status ==
                AudioCoordinatorStatusV2.Recovering
                ? "coordinator_recovery"
                : "coordinator_snapshot";
            byte[] payload = SerializeSnapshot(snapshot);
            lock (_sync)
            {
                if (_activeCaseId == null) return;
                AppendEventLocked(
                    kind,
                    "audio_coordinator",
                    payload);
            }
        }

        private void StartPipe()
        {
            _serverTask = Task.Run(delegate
            {
                return RunAcceptLoopAsync(_lifetime.Token);
            });
        }

        private async Task RunAcceptLoopAsync(
            CancellationToken cancellationToken)
        {
            for (int connectionIndex = 0;
                connectionIndex < MaxConnections &&
                Volatile.Read(ref _totalRequests) < MaxTotalRequests &&
                !cancellationToken.IsCancellationRequested;
                connectionIndex++)
            {
                NamedPipeServerStream server = null;
                try
                {
                    server = CreateServer();
                    lock (_sync)
                    {
                        if (Volatile.Read(ref _disposed) != 0)
                            return;
                        _server = server;
                    }
                    await server.WaitForConnectionAsync(cancellationToken)
                        .ConfigureAwait(false);
                    await ProcessConnectionAsync(
                        server,
                        cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    if (cancellationToken.IsCancellationRequested) return;
                    // A per-client I/O timeout only consumes that connection.
                    // The bounded host remains available to later valid clients.
                }
                catch (ObjectDisposedException)
                {
                    if (cancellationToken.IsCancellationRequested) return;
                }
                catch (IOException)
                {
                    // One broken client cannot consume the qualification bridge.
                }
                catch (InvalidDataException)
                {
                    // One invalid client is disconnected; the next bounded accept remains usable.
                }
                catch (DecoderFallbackException)
                {
                    // Malformed UTF-8 is scoped to this client connection.
                }
                finally
                {
                    lock (_sync)
                    {
                        if (ReferenceEquals(_server, server))
                            _server = null;
                    }
                    if (server != null)
                    {
                        try
                        {
                            if (server.IsConnected) server.Disconnect();
                        }
                        catch { }
                        try { server.Dispose(); } catch { }
                    }
                }
            }
        }

        private NamedPipeServerStream CreateServer()
        {
            return new NamedPipeServerStream(
                PipeName,
                PipeDirection.InOut,
                1,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly,
                4096,
                4096);
        }

        private async Task ProcessConnectionAsync(
            NamedPipeServerStream server,
            CancellationToken cancellationToken)
        {
            for (int count = 0;
                count < MaxRequestsPerClient &&
                !cancellationToken.IsCancellationRequested;
                count++)
            {
                byte[] frame = await ReadFrameAsync(
                    server,
                    cancellationToken).ConfigureAwait(false);
                if (frame == null) return;
                if (Interlocked.Increment(ref _totalRequests) >
                    MaxTotalRequests)
                {
                    throw new InvalidDataException(
                        "Qualification request budget is exhausted.");
                }
                QualificationRequest request = ParseRequest(frame);
                byte[] response = HandleRequest(request);
                if (response.Length > MaxResponseBytes)
                    throw new InvalidDataException(
                        "Qualification response exceeded its bound.");
                await WriteFrameAsync(
                    server,
                    response,
                    cancellationToken).ConfigureAwait(false);
            }
        }

        private byte[] HandleRequest(QualificationRequest request)
        {
            lock (_sync)
            {
                if (_journalOverflow)
                    throw new InvalidDataException(
                        "Qualification journal overflowed.");
                if (!_requestIds.Add(request.RequestId))
                    throw new InvalidDataException(
                        "Qualification request id was replayed.");
            }

            if (string.Equals(
                request.Command,
                "begin_case",
                StringComparison.Ordinal))
            {
                AudioQualificationEventV1 marker = BeginCase(
                    request.CaseId,
                    request.RouteKind);
                return SerializeEventResponse(request, marker);
            }
            if (string.Equals(
                request.Command,
                "end_case",
                StringComparison.Ordinal))
            {
                AudioQualificationEventV1 marker = EndCase(request.CaseId);
                return SerializeEventResponse(request, marker);
            }
            if (string.Equals(
                request.Command,
                "snapshot",
                StringComparison.Ordinal))
            {
                lock (_sync)
                {
                    if (_activeCaseId == null ||
                        !string.Equals(
                            request.CaseId,
                            _activeCaseId,
                            StringComparison.Ordinal))
                    {
                        throw new InvalidDataException(
                            "Qualification snapshot case does not match the active case.");
                    }
                }
                AudioCoordinatorSnapshotV2 snapshot = _snapshotProvider();
                if (snapshot == null)
                    throw new InvalidDataException(
                        "Qualification snapshot is unavailable.");
                byte[] payload = SerializeSnapshot(snapshot);
                AudioQualificationEventV1 observed = AppendEvent(
                    "qualification_snapshot",
                    "qualification_observer",
                    payload);
                return SerializeSnapshotResponse(
                    request,
                    observed,
                    snapshot,
                    payload);
            }
            if (string.Equals(
                request.Command,
                "journal",
                StringComparison.Ordinal))
            {
                return SerializeJournalResponse(request);
            }
            throw new InvalidDataException("Unknown qualification command.");
        }

        private AudioQualificationEventV1 BeginCase(
            string caseId,
            string routeKind)
        {
            lock (_sync)
            {
                if (_activeCaseId != null ||
                    _nextCaseIndex >= OrderedCaseIds.Length ||
                    !string.Equals(
                        OrderedCaseIds[_nextCaseIndex],
                        caseId,
                        StringComparison.Ordinal))
                {
                    throw new InvalidDataException(
                        "Qualification case order is invalid.");
                }
                _activeCaseId = caseId;
                AudioQualificationEventV1 marker = AppendEventLocked(
                    "case_begin",
                    "qualification_observer",
                    routeKind == null
                        ? EmptyObject()
                        : WriteJson(delegate(Utf8JsonWriter writer)
                        {
                            writer.WriteStartObject();
                            writer.WriteString("routeKind", routeKind);
                            writer.WriteEndObject();
                        }));
                if (marker != null && string.Equals(
                    caseId,
                    "bgm_crossfade",
                    StringComparison.Ordinal))
                {
                    StartCrossfadeSamplerLocked();
                }
                return marker;
            }
        }

        private AudioQualificationEventV1 EndCase(string caseId)
        {
            CancellationTokenSource samplerCancellation = null;
            Task samplerTask = null;
            lock (_sync)
            {
                if (!string.Equals(
                    _activeCaseId,
                    caseId,
                    StringComparison.Ordinal))
                {
                    throw new InvalidDataException(
                        "Qualification case end does not match the active case.");
                }
                if (string.Equals(
                    caseId,
                    "bgm_crossfade",
                    StringComparison.Ordinal))
                {
                    samplerCancellation = _crossfadeSamplerCancellation;
                    samplerTask = _crossfadeSamplerTask;
                }
            }
            try { samplerCancellation?.Cancel(); } catch { }
            WaitSamplerBounded(samplerTask);

            AudioQualificationEventV1 marker;
            lock (_sync)
            {
                if (!string.Equals(
                    _activeCaseId,
                    caseId,
                    StringComparison.Ordinal))
                {
                    throw new InvalidDataException(
                        "Qualification case changed while stopping its sampler.");
                }
                marker = AppendEventLocked(
                    "case_end",
                    "qualification_observer",
                    EmptyObject());
                _activeCaseId = null;
                _nextCaseIndex++;
                if (ReferenceEquals(
                    _crossfadeSamplerCancellation,
                    samplerCancellation))
                {
                    _crossfadeSamplerCancellation = null;
                    _crossfadeSamplerTask = null;
                }
            }
            DisposeCancellationAfterTask(
                samplerCancellation,
                samplerTask);
            return marker;
        }

        private void StartCrossfadeSamplerLocked()
        {
            if (_crossfadeSamplerCancellation != null ||
                _crossfadeSamplerTask != null)
            {
                throw new InvalidDataException(
                    "Qualification crossfade sampler is already active.");
            }
            var cancellation = CancellationTokenSource
                .CreateLinkedTokenSource(_lifetime.Token);
            _crossfadeSamplerCancellation = cancellation;
            _crossfadeSamplerTask = Task.Run(delegate
            {
                return RunCrossfadeSamplerAsync(cancellation);
            });
        }

        private async Task RunCrossfadeSamplerAsync(
            CancellationTokenSource owner)
        {
            CancellationToken cancellationToken = owner.Token;
            long startedAt = Stopwatch.GetTimestamp();
            int sampleCount = 0;
            try
            {
                while (!cancellationToken.IsCancellationRequested &&
                    sampleCount < _maxCrossfadeAutomaticSamples &&
                    !SamplerWindowElapsed(startedAt))
                {
                    lock (_sync)
                    {
                        if (Volatile.Read(ref _disposed) != 0 ||
                            !ReferenceEquals(
                                _crossfadeSamplerCancellation,
                                owner) ||
                            !string.Equals(
                                _activeCaseId,
                                "bgm_crossfade",
                                StringComparison.Ordinal))
                        {
                            return;
                        }
                    }

                    AudioCoordinatorSnapshotV2 snapshot = null;
                    try { snapshot = _snapshotProvider(); } catch { }
                    if (snapshot != null)
                    {
                        byte[] payload = SerializeSnapshot(snapshot);
                        lock (_sync)
                        {
                            if (cancellationToken.IsCancellationRequested ||
                                SamplerWindowElapsed(startedAt) ||
                                Volatile.Read(ref _disposed) != 0 ||
                                !ReferenceEquals(
                                    _crossfadeSamplerCancellation,
                                    owner) ||
                                !string.Equals(
                                    _activeCaseId,
                                    "bgm_crossfade",
                                    StringComparison.Ordinal))
                            {
                                return;
                            }
                            if (AppendEventLocked(
                                "qualification_snapshot",
                                "qualification_observer",
                                payload) == null)
                            {
                                return;
                            }
                            sampleCount++;
                        }
                    }

                    await Task.Delay(
                        _crossfadeSampleIntervalMilliseconds,
                        cancellationToken).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
            {
                // Case end and host disposal are the only normal exits.
            }
        }

        private bool SamplerWindowElapsed(long startedAt)
        {
            long elapsedTicks = Stopwatch.GetTimestamp() - startedAt;
            return elapsedTicks >= 0L &&
                ((double)elapsedTicks * 1000.0 /
                    Stopwatch.Frequency) >=
                _crossfadeSamplerWindowMilliseconds;
        }

        private static void WaitSamplerBounded(Task task)
        {
            if (task == null || Task.CurrentId == task.Id) return;
            try { task.Wait(SamplerStopTimeoutMilliseconds); } catch { }
        }

        private static void DisposeCancellationAfterTask(
            CancellationTokenSource cancellation,
            Task task)
        {
            if (cancellation == null) return;
            if (task == null || task.IsCompleted)
            {
                try { cancellation.Dispose(); } catch { }
                return;
            }
            task.ContinueWith(
                delegate
                {
                    try { cancellation.Dispose(); } catch { }
                },
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }

        private AudioQualificationEventV1 AppendEvent(
            string kind,
            string source,
            byte[] payload)
        {
            lock (_sync)
            {
                return AppendEventLocked(kind, source, payload);
            }
        }

        private AudioQualificationEventV1 AppendActiveEvent(
            string kind,
            string source,
            byte[] payload)
        {
            lock (_sync)
            {
                if (Volatile.Read(ref _disposed) != 0 ||
                    _activeCaseId == null)
                {
                    return null;
                }
                return AppendEventLocked(kind, source, payload);
            }
        }

        private bool CanRecordActiveEvent()
        {
            lock (_sync)
            {
                return Volatile.Read(ref _disposed) == 0 &&
                    _activeCaseId != null &&
                    !_journalOverflow;
            }
        }

        private AudioQualificationEventV1 AppendEventLocked(
            string kind,
            string source,
            byte[] payload)
        {
            if (_journalOverflow || Volatile.Read(ref _disposed) != 0)
                return null;
            byte[] safePayload = payload ?? EmptyObject();
            long eventByteBudget = checked((long)safePayload.Length + 2048L);
            if (_events.Count >= MaxJournalEvents ||
                eventByteBudget > MaxJournalByteBudget ||
                _journalByteBudget >
                    MaxJournalByteBudget - eventByteBudget)
            {
                _journalOverflow = true;
                return null;
            }
            long monotonic = Stopwatch.GetTimestamp();
            if (monotonic <= _lastMonotonicTicks)
                monotonic = checked(_lastMonotonicTicks + 1L);
            _lastMonotonicTicks = monotonic;
            var value = new AudioQualificationEventV1
            {
                CaseId = _activeCaseId,
                Kind = kind,
                MonotonicTicks = monotonic,
                ObservedAtUtc = AudioQualificationCandidateIdentityV1.FormatUtc(
                    DateTimeOffset.UtcNow),
                Payload = safePayload,
                PreviousSha256 = _lastSha256,
                RunId = _runId,
                Sequence = _events.Count + 1L,
                Source = source
            };
            value.Sha256 = HashEvent(value);
            _lastSha256 = value.Sha256;
            _events.Add(value);
            _journalByteBudget += eventByteBudget;
            return value;
        }

        private static string HashEvent(AudioQualificationEventV1 value)
        {
            byte[] material = WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                if (value.CaseId == null) writer.WriteNull("caseId");
                else writer.WriteString("caseId", value.CaseId);
                writer.WriteString("kind", value.Kind);
                writer.WriteNumber(
                    "monotonicTicks",
                    value.MonotonicTicks);
                writer.WriteString("observedAtUtc", value.ObservedAtUtc);
                writer.WritePropertyName("payload");
                WriteRawObject(writer, value.Payload);
                writer.WriteString(
                    "previousSha256",
                    value.PreviousSha256);
                writer.WriteString("runId", value.RunId);
                writer.WriteNumber("sequence", value.Sequence);
                writer.WriteString("source", value.Source);
                writer.WriteEndObject();
            });
            using (SHA256 sha256 = SHA256.Create())
                return Convert.ToHexString(sha256.ComputeHash(material));
        }

        private byte[] SerializeEventResponse(
            QualificationRequest request,
            AudioQualificationEventV1 value)
        {
            if (value == null)
                throw new InvalidDataException(
                    "Qualification journal overflowed.");
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                writer.WritePropertyName("candidate");
                _candidate.Write(writer);
                writer.WriteString("command", request.Command);
                writer.WritePropertyName("event");
                value.Write(writer);
                WriteResponseTail(writer, request);
                writer.WriteEndObject();
            });
        }

        private byte[] SerializeSnapshotResponse(
            QualificationRequest request,
            AudioQualificationEventV1 observed,
            AudioCoordinatorSnapshotV2 snapshot,
            byte[] snapshotBytes)
        {
            if (observed == null)
                throw new InvalidDataException(
                    "Qualification journal overflowed.");
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                writer.WritePropertyName("candidate");
                _candidate.Write(writer);
                writer.WriteString("command", request.Command);
                writer.WritePropertyName("event");
                observed.Write(writer);
                WriteResponseTail(writer, request);
                writer.WritePropertyName("session");
                WriteSession(writer, snapshot);
                writer.WritePropertyName("snapshot");
                WriteRawObject(writer, snapshotBytes);
                writer.WriteEndObject();
            });
        }

        private byte[] SerializeJournalResponse(QualificationRequest request)
        {
            AudioQualificationEventV1[] events;
            string sha256;
            lock (_sync)
            {
                if (_journalOverflow)
                    throw new InvalidDataException(
                        "Qualification journal overflowed.");
                if (_events.Count > MaxJournalEvents ||
                    _journalByteBudget > MaxJournalByteBudget ||
                    _journalByteBudget + 4096L > MaxResponseBytes)
                {
                    throw new InvalidDataException(
                        "Qualification journal response bound is exceeded.");
                }
                events = _events.ToArray();
                sha256 = HashEventArray(events);
            }
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                writer.WritePropertyName("candidate");
                _candidate.Write(writer);
                writer.WriteString("command", request.Command);
                writer.WritePropertyName("journal");
                writer.WriteStartObject();
                writer.WritePropertyName("events");
                writer.WriteStartArray();
                for (int index = 0; index < events.Length; index++)
                    events[index].Write(writer);
                writer.WriteEndArray();
                writer.WriteNumber(
                    "firstSequence",
                    events.Length == 0 ? 0L : events[0].Sequence);
                writer.WriteNumber(
                    "lastSequence",
                    events.Length == 0
                        ? 0L
                        : events[events.Length - 1].Sequence);
                writer.WriteString("sha256", sha256);
                writer.WriteEndObject();
                WriteResponseTail(writer, request);
                writer.WriteEndObject();
            });
        }

        private static string HashEventArray(
            AudioQualificationEventV1[] events)
        {
            byte[] bytes = WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartArray();
                for (int index = 0; index < events.Length; index++)
                    events[index].Write(writer);
                writer.WriteEndArray();
            });
            using (SHA256 sha256 = SHA256.Create())
                return Convert.ToHexString(sha256.ComputeHash(bytes));
        }

        private void WriteResponseTail(
            Utf8JsonWriter writer,
            QualificationRequest request)
        {
            writer.WriteString("protocol", Protocol);
            writer.WriteString("requestId", request.RequestId);
            writer.WriteString("result", "ok");
            writer.WriteString("runId", _runId);
            writer.WriteString("schema", ResponseSchema);
        }

        private static byte[] SerializeSnapshot(
            AudioCoordinatorSnapshotV2 snapshot)
        {
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                WriteSnapshot(writer, snapshot);
            });
        }

        private static void WriteSnapshot(
            Utf8JsonWriter writer,
            AudioCoordinatorSnapshotV2 snapshot)
        {
            writer.WriteStartObject();
            writer.WritePropertyName("bgmMeter");
            WriteMeter(writer, snapshot.BgmMeter);
            writer.WritePropertyName("counters");
            writer.WriteStartObject();
            writer.WriteNumber("playedCount", snapshot.PlayedCount);
            writer.WriteNumber("preReadyDrops", snapshot.PreReadyDrops);
            writer.WriteNumber("recoveryDrops", snapshot.RecoveryDrops);
            writer.WriteNumber(
                "staleGenerationDrops",
                snapshot.StaleGenerationDrops);
            writer.WriteNumber(
                "startFailureCount",
                snapshot.StartFailureCount);
            writer.WriteNumber("throttledCount", snapshot.ThrottledCount);
            writer.WriteNumber("unknownIdCount", snapshot.UnknownIdCount);
            writer.WriteEndObject();
            writer.WritePropertyName("runtime");
            writer.WriteStartObject();
            writer.WriteNumber(
                "audioReadyGeneration",
                snapshot.AudioReadyGeneration);
            writer.WriteString(
                "audioSessionId",
                snapshot.AudioSessionId ?? string.Empty);
            writer.WriteString("backend", BackendName(snapshot.Backend));
            writer.WriteNumber("channels", snapshot.Channels);
            writer.WriteNumber(
                "deviceGeneration",
                snapshot.DeviceGeneration);
            writer.WriteString(
                "deviceIdDigest",
                snapshot.DeviceIdDigest ?? string.Empty);
            writer.WriteString(
                "deviceName",
                snapshot.DeviceName ?? string.Empty);
            writer.WriteString(
                "sampleFormat",
                SampleFormatName(snapshot.SampleFormat));
            writer.WriteNumber("sampleRate", snapshot.SampleRate);
            writer.WriteString("status", StatusName(snapshot.Status));
            writer.WriteEndObject();
            writer.WritePropertyName("sfxMeter");
            WriteMeter(writer, snapshot.SfxMeter);
            writer.WritePropertyName("source");
            writer.WriteStartObject();
            writer.WriteString("codec", snapshot.Codec ?? "none");
            writer.WriteString(
                "container",
                snapshot.Container ?? "none");
            writer.WriteNumber("cursorFrames", snapshot.CursorFrames);
            writer.WriteString(
                "decoderBackend",
                snapshot.DecoderBackend ?? "none");
            writer.WriteNumber("lengthFrames", snapshot.LengthFrames);
            writer.WriteBoolean("playing", snapshot.BgmPlaying);
            WriteNullableString(
                writer,
                "requestId",
                snapshot.SourceRequestId);
            writer.WriteString(
                "startCategory",
                ResultCategoryName(snapshot.StartCategory));
            writer.WriteEndObject();
            writer.WriteEndObject();
        }

        private static void WriteSession(
            Utf8JsonWriter writer,
            AudioCoordinatorSnapshotV2 snapshot)
        {
            writer.WriteStartObject();
            writer.WriteNumber(
                "audioReadyGeneration",
                snapshot.AudioReadyGeneration);
            writer.WriteString(
                "audioSessionId",
                snapshot.AudioSessionId ?? string.Empty);
            writer.WriteNumber(
                "deviceGeneration",
                snapshot.DeviceGeneration);
            writer.WriteBoolean("ready", snapshot.IsReady);
            writer.WriteString("status", StatusName(snapshot.Status));
            writer.WriteEndObject();
        }

        private static void WriteMeter(
            Utf8JsonWriter writer,
            AudioNativeMeterObservationV2 meter)
        {
            meter = meter ?? AudioNativeMeterObservationV2.Empty;
            writer.WriteStartObject();
            writer.WriteNumber("clipCount", meter.ClipCount);
            writer.WriteNumber("frameCount", meter.FrameCount);
            WriteCanonicalDecimal(writer, "peakLeft", meter.PeakLeft);
            WriteCanonicalDecimal(writer, "peakRight", meter.PeakRight);
            WriteCanonicalDecimal(writer, "rmsLeft", meter.RmsLeft);
            WriteCanonicalDecimal(writer, "rmsRight", meter.RmsRight);
            writer.WriteNumber("underrunCount", meter.UnderrunCount);
            writer.WriteEndObject();
        }

        private QualificationRequest ParseRequest(byte[] frame)
        {
            try
            {
                using (JsonDocument document = JsonDocument.Parse(
                    frame,
                    new JsonDocumentOptions
                    {
                        AllowTrailingCommas = false,
                        CommentHandling = JsonCommentHandling.Disallow,
                        MaxDepth = 4
                    }))
                {
                    JsonElement root = document.RootElement;
                    if (root.ValueKind != JsonValueKind.Object)
                        throw new InvalidDataException(
                            "Qualification request must be an object.");
                    var names = new HashSet<string>(StringComparer.Ordinal);
                    foreach (JsonProperty property in root.EnumerateObject())
                    {
                        if (!names.Add(property.Name))
                            throw new InvalidDataException(
                                "Qualification request has duplicate keys.");
                    }
                    string command = RequiredString(root, "command");
                    bool marker = string.Equals(
                            command,
                            "begin_case",
                            StringComparison.Ordinal) ||
                        string.Equals(
                            command,
                            "end_case",
                            StringComparison.Ordinal);
                    bool snapshot = string.Equals(
                        command,
                        "snapshot",
                        StringComparison.Ordinal);
                    if (!marker && !snapshot &&
                        !string.Equals(
                            command,
                            "journal",
                            StringComparison.Ordinal))
                    {
                        throw new InvalidDataException(
                            "Qualification command is invalid.");
                    }
                    bool physicalRouteBegin = string.Equals(
                            command,
                            "begin_case",
                            StringComparison.Ordinal) &&
                        root.TryGetProperty(
                            "caseId",
                            out JsonElement physicalCase) &&
                        physicalCase.ValueKind == JsonValueKind.String &&
                        string.Equals(
                            physicalCase.GetString(),
                            "physical_route_bluetooth_or_hdmi",
                            StringComparison.Ordinal);
                    bool caseBound = marker || snapshot;
                    int expectedCount = marker
                        ? (physicalRouteBegin ? 6 : 5)
                        : (snapshot ? 5 : 4);
                    if (names.Count != expectedCount ||
                        !names.Contains("command") ||
                        !names.Contains("protocol") ||
                        !names.Contains("requestId") ||
                        !names.Contains("runId") ||
                        (caseBound != names.Contains("caseId")) ||
                        (physicalRouteBegin != names.Contains("routeKind")))
                    {
                        throw new InvalidDataException(
                            "Qualification request keys are not exact.");
                    }
                    string protocol = RequiredString(root, "protocol");
                    string requestId = RequiredString(root, "requestId");
                    string runId = RequiredString(root, "runId");
                    string caseId = caseBound
                        ? RequiredString(root, "caseId")
                        : null;
                    string routeKind = physicalRouteBegin
                        ? RequiredString(root, "routeKind")
                        : null;
                    if (!string.Equals(
                            protocol,
                            Protocol,
                            StringComparison.Ordinal) ||
                        !AudioQualificationInvocationV1.IsLowercaseHex32(
                            requestId) ||
                        !string.Equals(
                            runId,
                            _runId,
                            StringComparison.Ordinal) ||
                        (caseBound && Array.IndexOf(
                            OrderedCaseIds,
                            caseId) < 0) ||
                        (physicalRouteBegin &&
                         !string.Equals(
                             routeKind,
                             "bluetooth",
                             StringComparison.Ordinal) &&
                         !string.Equals(
                             routeKind,
                             "hdmi",
                             StringComparison.Ordinal)))
                    {
                        throw new InvalidDataException(
                            "Qualification request binding is invalid.");
                    }
                    byte[] canonical = CanonicalRequestForTests(
                        command,
                        requestId,
                        runId,
                        caseId,
                        routeKind);
                    if (!frame.AsSpan().SequenceEqual(canonical))
                        throw new InvalidDataException(
                            "Qualification request is not canonical JSON.");
                    return new QualificationRequest
                    {
                        CaseId = caseId,
                        Command = command,
                        RequestId = requestId,
                        RouteKind = routeKind
                    };
                }
            }
            catch (JsonException ex)
            {
                throw new InvalidDataException(
                    "Qualification request JSON is invalid.",
                    ex);
            }
        }

        private static string RequiredString(
            JsonElement root,
            string name)
        {
            if (!root.TryGetProperty(name, out JsonElement value) ||
                value.ValueKind != JsonValueKind.String ||
                string.IsNullOrEmpty(value.GetString()))
            {
                throw new InvalidDataException(
                    "Qualification request string is invalid: " + name);
            }
            return value.GetString();
        }

        private static async Task<byte[]> ReadFrameAsync(
            Stream stream,
            CancellationToken cancellationToken)
        {
            using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken))
            using (var buffer = new MemoryStream())
            {
                timeout.CancelAfter(IoTimeoutMilliseconds);
                byte[] one = new byte[1];
                while (true)
                {
                    int read = await stream.ReadAsync(
                        one,
                        0,
                        1,
                        timeout.Token).ConfigureAwait(false);
                    if (read == 0)
                        return buffer.Length == 0L
                            ? null
                            : throw new InvalidDataException(
                                "Qualification frame is unterminated.");
                    if (one[0] == (byte)'\n') break;
                    if (one[0] == (byte)'\r' || one[0] == 0)
                        throw new InvalidDataException(
                            "Qualification frame contains forbidden bytes.");
                    if (buffer.Length >= MaxRequestBytes)
                        throw new InvalidDataException(
                            "Qualification request exceeds 64 KiB.");
                    buffer.WriteByte(one[0]);
                }
                if (buffer.Length == 0L)
                    throw new InvalidDataException(
                        "Qualification request is empty.");
                byte[] value = buffer.ToArray();
                StrictUtf8.GetString(value);
                return value;
            }
        }

        private static async Task WriteFrameAsync(
            Stream stream,
            byte[] frame,
            CancellationToken cancellationToken)
        {
            using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken))
            {
                timeout.CancelAfter(IoTimeoutMilliseconds);
                await stream.WriteAsync(
                    frame,
                    0,
                    frame.Length,
                    timeout.Token).ConfigureAwait(false);
                await stream.WriteAsync(
                    new[] { (byte)'\n' },
                    0,
                    1,
                    timeout.Token).ConfigureAwait(false);
                await stream.FlushAsync(timeout.Token).ConfigureAwait(false);
            }
        }

        internal static void WriteRawObject(
            Utf8JsonWriter writer,
            byte[] value)
        {
            if (value == null)
                throw new ArgumentNullException("value");
            writer.WriteRawValue(value, skipInputValidation: false);
        }

        private static byte[] WriteJson(Action<Utf8JsonWriter> write)
        {
            using (var buffer = new MemoryStream())
            {
                using (var writer = new Utf8JsonWriter(buffer, WriterOptions))
                {
                    write(writer);
                    writer.Flush();
                }
                return buffer.ToArray();
            }
        }

        private static byte[] EmptyObject()
        {
            return new[] { (byte)'{', (byte)'}' };
        }

        private static void WriteNullableString(
            Utf8JsonWriter writer,
            string name,
            string value)
        {
            if (value == null) writer.WriteNull(name);
            else writer.WriteString(name, value);
        }

        private static void WriteNullableNumber(
            Utf8JsonWriter writer,
            string name,
            double? value)
        {
            if (value.HasValue)
                WriteCanonicalDecimal(writer, name, value.Value);
            else writer.WriteNull(name);
        }

        private static void WriteCanonicalDecimal(
            Utf8JsonWriter writer,
            string name,
            double value)
        {
            if (double.IsNaN(value) ||
                double.IsInfinity(value) ||
                value < 0.0 ||
                value >= 1e21)
            {
                throw new InvalidDataException(
                    "Qualification decimal is outside its canonical range: " +
                    name);
            }
            double quantized = Math.Round(
                value,
                6,
                MidpointRounding.AwayFromZero);
            string raw = quantized == 0.0
                ? "0"
                : quantized.ToString(
                    "0.######",
                    CultureInfo.InvariantCulture);
            writer.WritePropertyName(name);
            writer.WriteRawValue(raw, skipInputValidation: false);
        }

        private static void WriteNullableBoolean(
            Utf8JsonWriter writer,
            string name,
            bool? value)
        {
            if (value.HasValue) writer.WriteBoolean(name, value.Value);
            else writer.WriteNull(name);
        }

        private static string StatusName(AudioCoordinatorStatusV2 value)
        {
            switch (value)
            {
                case AudioCoordinatorStatusV2.Initializing:
                    return "initializing";
                case AudioCoordinatorStatusV2.Ready:
                    return "ready";
                case AudioCoordinatorStatusV2.Recovering:
                    return "recovering";
                case AudioCoordinatorStatusV2.Shutdown:
                    return "shutdown";
                default:
                    return "unavailable";
            }
        }

        private static string BackendName(uint value)
        {
            if (value == AudioNativeV2.BackendWasapi) return "wasapi";
            if (value == AudioNativeV2.BackendDirectSound)
                return "directsound";
            if (value == AudioNativeV2.BackendWinMm) return "winmm";
            if (value == AudioNativeV2.BackendTestOnlyNull)
                return "test_only_null";
            return "none";
        }

        private static string SampleFormatName(uint value)
        {
            if (value == AudioNativeV2.SampleFormatF32) return "f32";
            if (value == AudioNativeV2.SampleFormatS16) return "s16";
            if (value == AudioNativeV2.SampleFormatS24) return "s24";
            if (value == AudioNativeV2.SampleFormatS32) return "s32";
            return "unknown";
        }

        private static string ResultCategoryName(uint value)
        {
            switch (value)
            {
                case AudioNativeV2.ResultOk: return "ok";
                case AudioNativeV2.ResultMissing: return "missing";
                case AudioNativeV2.ResultUnsupportedContainer:
                    return "unsupported_container";
                case AudioNativeV2.ResultUnsupportedCodec:
                    return "unsupported_codec";
                case AudioNativeV2.ResultMalformed: return "malformed";
                case AudioNativeV2.ResultTruncated: return "truncated";
                case AudioNativeV2.ResultIoError: return "io_error";
                case AudioNativeV2.ResultAbiMismatch: return "abi_mismatch";
                case AudioNativeV2.ResultNotReady: return "not_ready";
                case AudioNativeV2.ResultStaleGeneration:
                    return "stale_generation";
                case AudioNativeV2.ResultUnknownId: return "unknown_id";
                case AudioNativeV2.ResultThrottled: return "throttled";
                case AudioNativeV2.ResultStartFailed: return "start_failed";
                case AudioNativeV2.ResultSeekFailed: return "seek_failed";
                case AudioNativeV2.ResultDeviceUnavailable:
                    return "device_unavailable";
                case AudioNativeV2.ResultDeviceLost: return "device_lost";
                case AudioNativeV2.ResultSuperseded: return "superseded";
                default: return "internal_error";
            }
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
            try { _unsubscribe(); } catch { }
            _lifetime.Cancel();
            NamedPipeServerStream server;
            CancellationTokenSource samplerCancellation;
            Task samplerTask;
            lock (_sync)
            {
                server = _server;
                _server = null;
                samplerCancellation = _crossfadeSamplerCancellation;
                samplerTask = _crossfadeSamplerTask;
                _crossfadeSamplerCancellation = null;
                _crossfadeSamplerTask = null;
                _activeCaseId = null;
            }
            try { samplerCancellation?.Cancel(); } catch { }
            try { server?.Dispose(); } catch { }
            WaitSamplerBounded(samplerTask);
            DisposeCancellationAfterTask(
                samplerCancellation,
                samplerTask);
            Task serverTask = _serverTask;
            if (serverTask != null &&
                Task.CurrentId != serverTask.Id)
            {
                try { serverTask.Wait(IoTimeoutMilliseconds); } catch { }
            }
            _lifetime.Dispose();
        }

        private sealed class QualificationRequest
        {
            internal string CaseId;
            internal string Command;
            internal string RequestId;
            internal string RouteKind;
        }
    }
}
