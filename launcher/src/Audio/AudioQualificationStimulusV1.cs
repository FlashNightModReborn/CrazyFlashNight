using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Bus;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Candidate-only qualification stimulus surface.  This pipe is deliberately
    /// separate from the read-only qualification observer.  Every accepted action
    /// is still sent to Flash and must enter the production AS2 AudioBridge route.
    /// </summary>
    internal sealed class AudioQualificationStimulusHostV1 : IDisposable
    {
        internal const string Protocol =
            "cf7.audio-v2.qualification-stimulus-pipe.v1";
        internal const string ResponseSchema =
            "cf7.audio-v2.qualification-stimulus-response.v1";
        internal const int MaxRequestBytes = 65536;
        internal const int MaxRequestsPerClient = 128;
        internal const int MaxConnections = 256;
        internal const int MaxTotalRequests = 1024;
        private const int IoTimeoutMilliseconds = 5000;
        private const int MaxPathLength = 1024;

        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);
        private static readonly JsonWriterOptions WriterOptions =
            new JsonWriterOptions
            {
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                Indented = false,
                SkipValidation = false
            };

        private readonly object _sync = new object();
        private readonly string _runId;
        private readonly AudioQualificationCandidateIdentityV1 _candidate;
        private readonly AudioQualificationDiagnosticsHostV1 _diagnostics;
        private readonly Func<int> _getReadyGeneration;
        private readonly Func<string, int, bool> _trySendIfGeneration;
        private readonly HashSet<string> _requestIds =
            new HashSet<string>(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _caseSteps =
            new Dictionary<string, int>(StringComparer.Ordinal);
        private readonly CancellationTokenSource _lifetime =
            new CancellationTokenSource();
        private NamedPipeServerStream _server;
        private Task _serverTask;
        private Action _unsubscribe = delegate { };
        private RecoveryArm _recoveryArm;
        private int _armedGeneration;
        private int _armInFlightGeneration;
        private int _totalRequests;
        private int _disposed;

        private AudioQualificationStimulusHostV1(
            string runId,
            AudioQualificationCandidateIdentityV1 candidate,
            AudioQualificationDiagnosticsHostV1 diagnostics,
            Func<int> getReadyGeneration,
            Func<string, int, bool> trySendIfGeneration)
        {
            if (!AudioQualificationInvocationV1.IsLowercaseHex32(runId))
                throw new ArgumentException("runId");
            _runId = runId;
            _candidate = candidate ?? throw new ArgumentNullException("candidate");
            _diagnostics = diagnostics ??
                throw new ArgumentNullException("diagnostics");
            _getReadyGeneration = getReadyGeneration ??
                throw new ArgumentNullException("getReadyGeneration");
            _trySendIfGeneration = trySendIfGeneration ??
                throw new ArgumentNullException("trySendIfGeneration");
            PipeName = BuildPipeName(candidate.Pid, runId);
        }

        internal string PipeName { get; private set; }
        internal bool UsesCurrentUserOnly { get { return true; } }

        internal static AudioQualificationStimulusHostV1 StartProduction(
            string runId,
            AudioQualificationDiagnosticsHostV1 diagnostics,
            XmlSocketServer socketServer)
        {
            if (socketServer == null)
                throw new ArgumentNullException("socketServer");

            var host = new AudioQualificationStimulusHostV1(
                runId,
                AudioQualificationCandidateIdentityV1.LoadCurrent(),
                diagnostics,
                delegate
                {
                    return socketServer.TryGetReadyGeneration(
                        out int generation)
                        ? generation
                        : 0;
                },
                delegate(string payload, int generation)
                {
                    return socketServer.TrySendIfGen(payload, generation);
                });

            Action<int> readyHandler = host.OnClientReady;
            Action<int> disconnectedHandler = host.OnClientDisconnected;
            Action<AudioCoordinatorSnapshotV2> snapshotHandler =
                host.RecordCoordinatorSnapshot;
            socketServer.OnClientReadyForGeneration += readyHandler;
            socketServer.OnClientDisconnectedForGeneration +=
                disconnectedHandler;
            AudioEngine.SnapshotChanged += snapshotHandler;
            host._unsubscribe = delegate
            {
                AudioEngine.SnapshotChanged -= snapshotHandler;
                socketServer.OnClientDisconnectedForGeneration -=
                    disconnectedHandler;
                socketServer.OnClientReadyForGeneration -= readyHandler;
            };
            try
            {
                host.StartPipe();
                host.TryArmCurrentConnection();
                return host;
            }
            catch
            {
                host.Dispose();
                throw;
            }
        }

        internal static AudioQualificationStimulusHostV1 StartForTests(
            string runId,
            AudioQualificationCandidateIdentityV1 candidate,
            AudioQualificationDiagnosticsHostV1 diagnostics,
            Func<int> getReadyGeneration,
            Func<string, int, bool> trySendIfGeneration)
        {
            var host = new AudioQualificationStimulusHostV1(
                runId,
                candidate,
                diagnostics,
                getReadyGeneration,
                trySendIfGeneration);
            host.StartPipe();
            host.TryArmCurrentConnection();
            return host;
        }

        internal static string BuildPipeName(int pid, string runId)
        {
            if (pid <= 0 ||
                !AudioQualificationInvocationV1.IsLowercaseHex32(runId))
            {
                throw new ArgumentException("Pipe identity is invalid.");
            }
            return "cf7-audio-v2-qualification-stimulus-" +
                pid.ToString(CultureInfo.InvariantCulture) + "-" + runId;
        }

        internal static byte[] CanonicalRequestForTests(
            string command,
            string requestId,
            string runId,
            string caseId,
            string operation,
            string path = null,
            double? fadeSeconds = null,
            bool? loop = null,
            double? seekSeconds = null,
            double? volume = null,
            IReadOnlyList<string> linkageIds = null)
        {
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                writer.WriteString("caseId", caseId);
                writer.WriteString("command", command);
                if (string.Equals(
                    operation,
                    "play",
                    StringComparison.Ordinal))
                {
                    writer.WriteNumber("fadeSeconds", fadeSeconds.Value);
                    writer.WriteBoolean("loop", loop.Value);
                }
                if (string.Equals(
                    operation,
                    "sfx",
                    StringComparison.Ordinal))
                {
                    writer.WritePropertyName("linkageIds");
                    writer.WriteStartArray();
                    for (int index = 0; index < linkageIds.Count; index++)
                        writer.WriteStringValue(linkageIds[index]);
                    writer.WriteEndArray();
                }
                writer.WriteString("operation", operation);
                if (string.Equals(
                    operation,
                    "play",
                    StringComparison.Ordinal))
                {
                    writer.WriteString("path", path);
                }
                writer.WriteString("protocol", Protocol);
                writer.WriteString("requestId", requestId);
                writer.WriteString("runId", runId);
                if (string.Equals(
                    operation,
                    "seek",
                    StringComparison.Ordinal))
                {
                    writer.WriteNumber("seekSeconds", seekSeconds.Value);
                }
                if (string.Equals(
                        operation,
                        "play",
                        StringComparison.Ordinal) ||
                    string.Equals(
                        operation,
                        "set_gain",
                        StringComparison.Ordinal))
                {
                    writer.WriteNumber("volume", volume.Value);
                }
                writer.WriteEndObject();
            });
        }

        internal void NotifyClientReadyForTests(int generation)
        {
            OnClientReady(generation);
        }

        internal void NotifyClientDisconnectedForTests(int generation)
        {
            OnClientDisconnected(generation);
        }

        internal void RecordCoordinatorSnapshot(
            AudioCoordinatorSnapshotV2 snapshot)
        {
            if (snapshot == null ||
                snapshot.Status != AudioCoordinatorStatusV2.Recovering ||
                Volatile.Read(ref _disposed) != 0)
            {
                return;
            }

            RecoveryArm armed;
            lock (_sync)
            {
                armed = _recoveryArm;
                if (armed == null) return;
                _recoveryArm = null;
            }

            if (!_diagnostics.IsActiveCase(armed.CaseId)) return;
            int generation = SafeReadyGeneration();
            bool maySend;
            lock (_sync)
            {
                maySend = generation > 0 &&
                    generation == _armedGeneration &&
                    Volatile.Read(ref _disposed) == 0;
            }
            if (!maySend) return;
            if (!SafeSend(armed.FlashPayload, generation)) return;
            lock (_sync)
            {
                AdvanceStepLocked(armed.CaseId, "sfx");
            }
        }

        private void OnClientReady(int generation)
        {
            if (generation <= 0 || Volatile.Read(ref _disposed) != 0)
                return;
            TryArmGeneration(generation);
        }

        private void OnClientDisconnected(int generation)
        {
            if (generation <= 0) return;
            lock (_sync)
            {
                if (_armedGeneration == generation)
                    _armedGeneration = 0;
                if (_armInFlightGeneration == generation)
                    _armInFlightGeneration = 0;
            }
        }

        private void TryArmCurrentConnection()
        {
            int generation = SafeReadyGeneration();
            if (generation > 0) TryArmGeneration(generation);
        }

        private bool TryArmGeneration(int generation)
        {
            if (generation <= 0 || Volatile.Read(ref _disposed) != 0)
                return false;
            lock (_sync)
            {
                if (_armedGeneration == generation) return true;
                if (_armInFlightGeneration != 0) return false;
                _armInFlightGeneration = generation;
            }

            bool sent = SafeReadyGeneration() == generation &&
                SafeSend(BuildArmPayload(), generation);
            lock (_sync)
            {
                if (_armInFlightGeneration == generation)
                {
                    _armInFlightGeneration = 0;
                    if (sent) _armedGeneration = generation;
                }
                return sent && _armedGeneration == generation;
            }
        }

        private bool TrySendStimulus(byte[] payload)
        {
            int generation = SafeReadyGeneration();
            if (generation <= 0 || !TryArmGeneration(generation))
                return false;
            lock (_sync)
            {
                if (_armedGeneration != generation ||
                    Volatile.Read(ref _disposed) != 0)
                {
                    return false;
                }
            }
            return SafeReadyGeneration() == generation &&
                SafeSend(payload, generation);
        }

        private int SafeReadyGeneration()
        {
            try { return _getReadyGeneration(); }
            catch { return 0; }
        }

        private bool SafeSend(byte[] payload, int generation)
        {
            if (payload == null || generation <= 0 ||
                Volatile.Read(ref _disposed) != 0)
            {
                return false;
            }
            try
            {
                return _trySendIfGeneration(
                    StrictUtf8.GetString(payload) + "\0",
                    generation);
            }
            catch
            {
                return false;
            }
        }

        private byte[] BuildArmPayload()
        {
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                writer.WriteString("action", "audioV2QualificationStimulus");
                writer.WriteString("operation", "arm");
                writer.WriteString("runId", _runId);
                writer.WriteString("task", "cmd");
                writer.WriteEndObject();
            });
        }

        private byte[] BuildFlashPayload(StimulusRequest request)
        {
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                writer.WriteString("action", "audioV2QualificationStimulus");
                writer.WriteString("caseId", request.CaseId);
                if (string.Equals(
                    request.Operation,
                    "play",
                    StringComparison.Ordinal))
                {
                    writer.WriteNumber("fadeSeconds", request.FadeSeconds.Value);
                    writer.WriteBoolean("loop", request.Loop.Value);
                }
                if (string.Equals(
                    request.Operation,
                    "sfx",
                    StringComparison.Ordinal))
                {
                    writer.WritePropertyName("linkageIds");
                    writer.WriteStartArray();
                    for (int index = 0;
                        index < request.LinkageIds.Count;
                        index++)
                    {
                        writer.WriteStringValue(request.LinkageIds[index]);
                    }
                    writer.WriteEndArray();
                }
                writer.WriteString("operation", request.Operation);
                if (string.Equals(
                    request.Operation,
                    "play",
                    StringComparison.Ordinal))
                {
                    writer.WriteString("path", request.Path);
                }
                writer.WriteString("runId", _runId);
                if (string.Equals(
                    request.Operation,
                    "seek",
                    StringComparison.Ordinal))
                {
                    writer.WriteNumber("seekSeconds", request.SeekSeconds.Value);
                }
                writer.WriteString("task", "cmd");
                if (string.Equals(
                        request.Operation,
                        "play",
                        StringComparison.Ordinal) ||
                    string.Equals(
                        request.Operation,
                        "set_gain",
                        StringComparison.Ordinal))
                {
                    writer.WriteNumber("volume", request.Volume.Value);
                }
                writer.WriteEndObject();
            });
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
                        if (Volatile.Read(ref _disposed) != 0) return;
                        _server = server;
                    }
                    await server.WaitForConnectionAsync(cancellationToken)
                        .ConfigureAwait(false);
                    await ProcessConnectionAsync(server, cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    if (cancellationToken.IsCancellationRequested) return;
                }
                catch (ObjectDisposedException)
                {
                    if (cancellationToken.IsCancellationRequested) return;
                }
                catch (IOException)
                {
                    // A malformed or disconnected client only consumes this connection.
                }
                catch (InvalidDataException)
                {
                    // Strict protocol violations are fail-closed per connection.
                }
                finally
                {
                    lock (_sync)
                    {
                        if (ReferenceEquals(_server, server)) _server = null;
                    }
                    try { server?.Dispose(); } catch { }
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
                        "Stimulus request budget is exhausted.");
                }
                StimulusRequest request = ParseRequest(frame);
                byte[] response = HandleRequest(request);
                await WriteFrameAsync(
                    server,
                    response,
                    cancellationToken).ConfigureAwait(false);
            }
        }

        private byte[] HandleRequest(StimulusRequest request)
        {
            lock (_sync)
            {
                if (Volatile.Read(ref _disposed) != 0)
                    throw new InvalidDataException(
                        "Stimulus host is disposed.");
                if (!_requestIds.Add(request.RequestId))
                    throw new InvalidDataException(
                        "Stimulus request id was replayed.");
            }
            if (TryGetBetweenCaseGap(
                request.Command,
                out string previousCase,
                out string nextCase))
            {
                if (!_diagnostics.IsBetweenCases(
                    previousCase,
                    nextCase))
                {
                    throw new InvalidDataException(
                        "Between-case stimulus is outside its exact marker gap.");
                }
            }
            else if (!_diagnostics.IsActiveCase(request.CaseId))
            {
                throw new InvalidDataException(
                    "Stimulus case is not the active observer case.");
            }

            byte[] flashPayload = BuildFlashPayload(request);
            if (string.Equals(
                request.Command,
                "arm_recovery_sfx",
                StringComparison.Ordinal))
            {
                lock (_sync)
                {
                    ValidateStepLocked(request);
                    if (_recoveryArm != null)
                        throw new InvalidDataException(
                            "Recovery SFX stimulus is already armed.");
                    _recoveryArm = new RecoveryArm
                    {
                        CaseId = request.CaseId,
                        FlashPayload = flashPayload
                    };
                }
                return SerializeResponse(request, "armed", false);
            }

            lock (_sync) ValidateStepLocked(request);
            if (!TrySendStimulus(flashPayload))
                throw new InvalidDataException(
                    "Stimulus could not be sent to the exact ready Flash generation.");
            lock (_sync) AdvanceStepLocked(request.CaseId, request.Operation);
            return SerializeResponse(request, "ok", true);
        }

        private void ValidateStepLocked(StimulusRequest request)
        {
            int step = _caseSteps.TryGetValue(
                request.CaseId,
                out int current)
                ? current
                : 0;
            string expected = ExpectedOperation(request.CaseId, step);
            if (!string.Equals(
                    expected,
                    request.Operation,
                    StringComparison.Ordinal) ||
                (string.Equals(
                    request.CaseId,
                    "no_stale_sfx_after_recovery",
                    StringComparison.Ordinal) !=
                 string.Equals(
                    request.Command,
                    "arm_recovery_sfx",
                    StringComparison.Ordinal)) ||
                (string.Equals(
                    request.CaseId,
                    "post_gain_restore",
                    StringComparison.Ordinal) &&
                 (!_caseSteps.TryGetValue(
                        "gain_zero_and_default_max",
                        out int gainStep) ||
                  gainStep != 2)) ||
                (string.Equals(
                    request.CaseId,
                    "pre_sfx_bgm_mute",
                    StringComparison.Ordinal) &&
                 (!_caseSteps.TryGetValue(
                        "format_opus",
                        out int opusStep) ||
                  opusStep != 1)) ||
                (string.Equals(
                    request.CaseId,
                    "pre_mix_bgm_restore",
                    StringComparison.Ordinal) &&
                 (!_caseSteps.TryGetValue(
                        "pre_sfx_bgm_mute",
                        out int muteStep) ||
                  muteStep != 1 ||
                  !_caseSteps.TryGetValue(
                        "dense_overlap_throttle",
                        out int denseStep) ||
                  denseStep != 1)))
            {
                throw new InvalidDataException(
                    "Stimulus operation is not valid for this case step.");
            }
        }

        private void AdvanceStepLocked(string caseId, string operation)
        {
            int step = _caseSteps.TryGetValue(caseId, out int current)
                ? current
                : 0;
            if (!string.Equals(
                ExpectedOperation(caseId, step),
                operation,
                StringComparison.Ordinal))
            {
                return;
            }
            _caseSteps[caseId] = checked(step + 1);
        }

        private static string ExpectedOperation(string caseId, int step)
        {
            switch (caseId)
            {
                case "bgm_playback":
                case "bgm_crossfade":
                case "format_vorbis":
                case "format_aac_mp4":
                case "format_opus":
                    return step == 0 ? "play" : null;
                case "bgm_seek":
                    return step == 0 ? "seek" : null;
                case "sfx_playback":
                case "dense_overlap_throttle":
                case "bgm_sfx_mix":
                case "no_stale_sfx_after_recovery":
                    return step == 0 ? "sfx" : null;
                case "gain_zero_and_default_max":
                    return step < 2 ? "set_gain" : null;
                case "post_gain_restore":
                case "pre_sfx_bgm_mute":
                case "pre_mix_bgm_restore":
                    return step == 0 ? "set_gain" : null;
                default:
                    return null;
            }
        }

        private static bool TryGetBetweenCaseGap(
            string command,
            out string previousCase,
            out string nextCase)
        {
            switch (command)
            {
                case "post_gain_restore":
                    previousCase = "gain_zero_and_default_max";
                    nextCase = "default_device_switch";
                    return true;
                case "pre_sfx_bgm_mute":
                    previousCase = "format_opus";
                    nextCase = "sfx_playback";
                    return true;
                case "pre_mix_bgm_restore":
                    previousCase = "dense_overlap_throttle";
                    nextCase = "bgm_sfx_mix";
                    return true;
                default:
                    previousCase = null;
                    nextCase = null;
                    return false;
            }
        }

        private StimulusRequest ParseRequest(byte[] frame)
        {
            try
            {
                using (JsonDocument document = JsonDocument.Parse(
                    frame,
                    new JsonDocumentOptions
                    {
                        AllowTrailingCommas = false,
                        CommentHandling = JsonCommentHandling.Disallow,
                        MaxDepth = 6
                    }))
                {
                    JsonElement root = document.RootElement;
                    if (root.ValueKind != JsonValueKind.Object)
                        throw new InvalidDataException(
                            "Stimulus request must be an object.");
                    var names = new HashSet<string>(StringComparer.Ordinal);
                    foreach (JsonProperty property in root.EnumerateObject())
                    {
                        if (!names.Add(property.Name))
                            throw new InvalidDataException(
                                "Stimulus request has duplicate keys.");
                    }

                    string caseId = RequiredString(root, "caseId");
                    string command = RequiredString(root, "command");
                    string operation = RequiredString(root, "operation");
                    string protocol = RequiredString(root, "protocol");
                    string requestId = RequiredString(root, "requestId");
                    string runId = RequiredString(root, "runId");
                    if (!string.Equals(protocol, Protocol, StringComparison.Ordinal) ||
                        !AudioQualificationInvocationV1.IsLowercaseHex32(
                            requestId) ||
                        !string.Equals(runId, _runId, StringComparison.Ordinal) ||
                        (!string.Equals(
                            command,
                            "dispatch",
                            StringComparison.Ordinal) &&
                         !string.Equals(
                            command,
                            "arm_recovery_sfx",
                            StringComparison.Ordinal) &&
                         !string.Equals(
                             command,
                             "post_gain_restore",
                             StringComparison.Ordinal) &&
                         !string.Equals(
                             command,
                             "pre_sfx_bgm_mute",
                             StringComparison.Ordinal) &&
                         !string.Equals(
                             command,
                             "pre_mix_bgm_restore",
                             StringComparison.Ordinal)))
                    {
                        throw new InvalidDataException(
                            "Stimulus request binding is invalid.");
                    }

                    var request = new StimulusRequest
                    {
                        CaseId = caseId,
                        Command = command,
                        Operation = operation,
                        RequestId = requestId
                    };
                    if (string.Equals(operation, "play", StringComparison.Ordinal))
                    {
                        RequireExactNames(
                            names,
                            "caseId", "command", "fadeSeconds", "loop",
                            "operation", "path", "protocol", "requestId",
                            "runId", "volume");
                        request.FadeSeconds = RequiredFiniteNumber(
                            root,
                            "fadeSeconds");
                        request.Loop = RequiredBoolean(root, "loop");
                        request.Path = RequiredString(root, "path");
                        request.Volume = RequiredFiniteNumber(root, "volume");
                    }
                    else if (string.Equals(
                        operation,
                        "seek",
                        StringComparison.Ordinal))
                    {
                        RequireExactNames(
                            names,
                            "caseId", "command", "operation", "protocol",
                            "requestId", "runId", "seekSeconds");
                        request.SeekSeconds = RequiredFiniteNumber(
                            root,
                            "seekSeconds");
                    }
                    else if (string.Equals(
                        operation,
                        "set_gain",
                        StringComparison.Ordinal))
                    {
                        RequireExactNames(
                            names,
                            "caseId", "command", "operation", "protocol",
                            "requestId", "runId", "volume");
                        request.Volume = RequiredFiniteNumber(root, "volume");
                    }
                    else if (string.Equals(
                        operation,
                        "sfx",
                        StringComparison.Ordinal))
                    {
                        RequireExactNames(
                            names,
                            "caseId", "command", "linkageIds", "operation",
                            "protocol", "requestId", "runId");
                        request.LinkageIds = RequiredLinkageIds(root);
                    }
                    else
                    {
                        throw new InvalidDataException(
                            "Stimulus operation is invalid.");
                    }

                    ValidateCaseGrammar(request);
                    byte[] canonical = CanonicalRequestForTests(
                        request.Command,
                        request.RequestId,
                        _runId,
                        request.CaseId,
                        request.Operation,
                        request.Path,
                        request.FadeSeconds,
                        request.Loop,
                        request.SeekSeconds,
                        request.Volume,
                        request.LinkageIds);
                    if (!frame.AsSpan().SequenceEqual(canonical))
                        throw new InvalidDataException(
                            "Stimulus request is not canonical JSON.");
                    return request;
                }
            }
            catch (JsonException ex)
            {
                throw new InvalidDataException(
                    "Stimulus request JSON is invalid.",
                    ex);
            }
        }

        private void ValidateCaseGrammar(StimulusRequest request)
        {
            switch (request.CaseId)
            {
                case "bgm_playback":
                    RequirePlay(request, false);
                    break;
                case "bgm_crossfade":
                    RequirePlay(request, true);
                    break;
                case "format_vorbis":
                case "format_aac_mp4":
                case "format_opus":
                    RequirePlay(request, false);
                    break;
                case "bgm_seek":
                    if (!string.Equals(
                            request.Operation,
                            "seek",
                            StringComparison.Ordinal) ||
                        request.SeekSeconds.Value <= 0.0 ||
                        request.SeekSeconds.Value > 86400.0)
                    {
                        throw new InvalidDataException(
                            "Seek stimulus is outside its strict bounds.");
                    }
                    break;
                case "sfx_playback":
                case "bgm_sfx_mix":
                case "no_stale_sfx_after_recovery":
                    RequireSfxCount(request, 1);
                    break;
                case "dense_overlap_throttle":
                    RequireSfxCount(request, 6);
                    if (new HashSet<string>(
                        request.LinkageIds,
                        StringComparer.Ordinal).Count != 6)
                    {
                        throw new InvalidDataException(
                            "Dense SFX stimulus ids must be unique.");
                    }
                    break;
                case "gain_zero_and_default_max":
                    if (!string.Equals(
                        request.Operation,
                        "set_gain",
                        StringComparison.Ordinal))
                    {
                        throw new InvalidDataException(
                            "Gain case requires set_gain.");
                    }
                    lock (_sync)
                    {
                        int step = _caseSteps.TryGetValue(
                            request.CaseId,
                            out int current)
                            ? current
                            : 0;
                        double expected = step == 0 ? 1.0 : 0.0;
                        if (request.Volume.Value != expected)
                            throw new InvalidDataException(
                                "Gain stimulus order must be one then zero.");
                    }
                    break;
                case "post_gain_restore":
                    if (!string.Equals(
                            request.Operation,
                            "set_gain",
                            StringComparison.Ordinal) ||
                        request.Volume != 1.0)
                    {
                        throw new InvalidDataException(
                            "Post-gain restore must set exact gain one.");
                    }
                    break;
                case "pre_sfx_bgm_mute":
                    if (!string.Equals(
                            request.Operation,
                            "set_gain",
                            StringComparison.Ordinal) ||
                        request.Volume != 0.0)
                    {
                        throw new InvalidDataException(
                            "Pre-SFX BGM mute must set exact gain zero.");
                    }
                    break;
                case "pre_mix_bgm_restore":
                    if (!string.Equals(
                            request.Operation,
                            "set_gain",
                            StringComparison.Ordinal) ||
                        request.Volume != 1.0)
                    {
                        throw new InvalidDataException(
                            "Pre-mix BGM restore must set exact gain one.");
                    }
                    break;
                default:
                    throw new InvalidDataException(
                        "This qualification case has no software stimulus.");
            }

            string expectedCommand;
            switch (request.CaseId)
            {
                case "no_stale_sfx_after_recovery":
                    expectedCommand = "arm_recovery_sfx";
                    break;
                case "post_gain_restore":
                case "pre_sfx_bgm_mute":
                case "pre_mix_bgm_restore":
                    expectedCommand = request.CaseId;
                    break;
                default:
                    expectedCommand = "dispatch";
                    break;
            }
            if (!string.Equals(
                request.Command,
                expectedCommand,
                StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "Stimulus command does not match the case grammar.");
            }
        }

        private void RequirePlay(StimulusRequest request, bool crossfade)
        {
            if (!string.Equals(
                    request.Operation,
                    "play",
                    StringComparison.Ordinal) ||
                request.Loop != true ||
                request.Volume != 1.0 ||
                (crossfade
                    ? request.FadeSeconds.Value <= 0.0 ||
                      request.FadeSeconds.Value > 60.0
                    : request.FadeSeconds.Value != 0.0) ||
                !IsQualificationPath(request.Path))
            {
                throw new InvalidDataException(
                    "Play stimulus does not satisfy its strict grammar.");
            }
        }

        private static void RequireSfxCount(
            StimulusRequest request,
            int expected)
        {
            if (!string.Equals(
                    request.Operation,
                    "sfx",
                    StringComparison.Ordinal) ||
                request.LinkageIds == null ||
                request.LinkageIds.Count != expected)
            {
                throw new InvalidDataException(
                    "SFX stimulus count is invalid.");
            }
        }

        private bool IsQualificationPath(string path)
        {
            if (string.IsNullOrEmpty(path) || path.Length > MaxPathLength)
                return false;
            string prefix = "tmp/audio-v2-qualification/" + _runId + "/";
            if (!path.StartsWith(prefix, StringComparison.Ordinal) ||
                path.Length == prefix.Length)
            {
                return false;
            }
            for (int index = 0; index < path.Length; index++)
            {
                char current = path[index];
                bool allowed = (current >= 'a' && current <= 'z') ||
                    (current >= '0' && current <= '9') ||
                    current == '.' || current == '_' || current == '-' ||
                    current == '/';
                if (!allowed) return false;
            }
            string[] segments = path.Split('/');
            for (int index = 0; index < segments.Length; index++)
            {
                if (segments[index].Length == 0 ||
                    string.Equals(segments[index], ".", StringComparison.Ordinal) ||
                    string.Equals(segments[index], "..", StringComparison.Ordinal))
                {
                    return false;
                }
            }
            return true;
        }

        private static IReadOnlyList<string> RequiredLinkageIds(
            JsonElement root)
        {
            if (!root.TryGetProperty(
                    "linkageIds",
                    out JsonElement value) ||
                value.ValueKind != JsonValueKind.Array)
            {
                throw new InvalidDataException(
                    "Stimulus linkageIds must be an array.");
            }
            var result = new List<string>();
            foreach (JsonElement entry in value.EnumerateArray())
            {
                if (entry.ValueKind != JsonValueKind.String)
                    throw new InvalidDataException(
                        "Stimulus linkage id is not a string.");
                string id = entry.GetString();
                if (string.IsNullOrWhiteSpace(id) || id.Length > 128 ||
                    id.IndexOf('|') >= 0 || id.IndexOf('/') >= 0 ||
                    id.IndexOf('\\') >= 0 ||
                    string.Equals(id, ".", StringComparison.Ordinal) ||
                    string.Equals(id, "..", StringComparison.Ordinal))
                {
                    throw new InvalidDataException(
                        "Stimulus linkage id is invalid.");
                }
                for (int index = 0; index < id.Length; index++)
                {
                    if (char.IsControl(id[index]))
                        throw new InvalidDataException(
                            "Stimulus linkage id contains control characters.");
                }
                result.Add(id);
            }
            return result;
        }

        private static string RequiredString(JsonElement root, string name)
        {
            if (!root.TryGetProperty(name, out JsonElement value) ||
                value.ValueKind != JsonValueKind.String ||
                string.IsNullOrEmpty(value.GetString()))
            {
                throw new InvalidDataException(
                    "Stimulus request string is invalid: " + name);
            }
            return value.GetString();
        }

        private static double RequiredFiniteNumber(
            JsonElement root,
            string name)
        {
            if (!root.TryGetProperty(name, out JsonElement value) ||
                value.ValueKind != JsonValueKind.Number ||
                !value.TryGetDouble(out double result) ||
                double.IsNaN(result) ||
                double.IsInfinity(result))
            {
                throw new InvalidDataException(
                    "Stimulus request number is invalid: " + name);
            }
            return result;
        }

        private static bool RequiredBoolean(JsonElement root, string name)
        {
            if (!root.TryGetProperty(name, out JsonElement value) ||
                (value.ValueKind != JsonValueKind.True &&
                 value.ValueKind != JsonValueKind.False))
            {
                throw new InvalidDataException(
                    "Stimulus request boolean is invalid: " + name);
            }
            return value.GetBoolean();
        }

        private static void RequireExactNames(
            HashSet<string> names,
            params string[] expected)
        {
            if (names.Count != expected.Length)
                throw new InvalidDataException(
                    "Stimulus request keys are not exact.");
            for (int index = 0; index < expected.Length; index++)
            {
                if (!names.Contains(expected[index]))
                    throw new InvalidDataException(
                        "Stimulus request keys are not exact.");
            }
        }

        private byte[] SerializeResponse(
            StimulusRequest request,
            string result,
            bool sent)
        {
            return WriteJson(delegate(Utf8JsonWriter writer)
            {
                writer.WriteStartObject();
                writer.WritePropertyName("candidate");
                _candidate.Write(writer);
                writer.WriteString("caseId", request.CaseId);
                writer.WriteString("command", request.Command);
                writer.WriteString("operation", request.Operation);
                writer.WriteString("protocol", Protocol);
                writer.WriteString("requestId", request.RequestId);
                writer.WriteString("result", result);
                writer.WriteString("runId", _runId);
                writer.WriteString("schema", ResponseSchema);
                writer.WriteBoolean("sent", sent);
                writer.WriteEndObject();
            });
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
                                "Stimulus frame is unterminated.");
                    if (one[0] == (byte)'\n') break;
                    if (one[0] == (byte)'\r' || one[0] == 0)
                        throw new InvalidDataException(
                            "Stimulus frame contains forbidden bytes.");
                    if (buffer.Length >= MaxRequestBytes)
                        throw new InvalidDataException(
                            "Stimulus request exceeds 64 KiB.");
                    buffer.WriteByte(one[0]);
                }
                if (buffer.Length == 0L)
                    throw new InvalidDataException(
                        "Stimulus request is empty.");
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

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
            try { _unsubscribe(); } catch { }
            _lifetime.Cancel();
            NamedPipeServerStream server;
            lock (_sync)
            {
                server = _server;
                _server = null;
                _recoveryArm = null;
                _armedGeneration = 0;
                _armInFlightGeneration = 0;
            }
            try { server?.Dispose(); } catch { }
            Task serverTask = _serverTask;
            if (serverTask != null && Task.CurrentId != serverTask.Id)
            {
                try { serverTask.Wait(IoTimeoutMilliseconds); } catch { }
            }
            _lifetime.Dispose();
        }

        private sealed class StimulusRequest
        {
            internal string CaseId;
            internal string Command;
            internal double? FadeSeconds;
            internal IReadOnlyList<string> LinkageIds;
            internal bool? Loop;
            internal string Operation;
            internal string Path;
            internal string RequestId;
            internal double? SeekSeconds;
            internal double? Volume;
        }

        private sealed class RecoveryArm
        {
            internal string CaseId;
            internal byte[] FlashPayload;
        }
    }
}
