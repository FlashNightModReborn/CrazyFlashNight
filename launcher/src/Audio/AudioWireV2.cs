using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Parsed, immutable Audio Platform v2 BGM request.
    ///
    /// The wire model intentionally contains only audio-domain epochs.  XMLSocket
    /// connection generations belong to the transport and must never be copied here.
    /// </summary>
    internal sealed class AudioBgmRequestV2
    {
        internal AudioBgmRequestV2(
            string requestId,
            string audioSessionId,
            ulong audioReadyGeneration,
            string operation,
            string path,
            bool? loop,
            double? volume,
            double? fadeSeconds,
            double? seekSeconds)
        {
            RequestId = requestId;
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            Operation = operation;
            Path = path;
            Loop = loop;
            Volume = volume;
            FadeSeconds = fadeSeconds;
            SeekSeconds = seekSeconds;
        }

        public int WireRevision { get { return AudioWireV2.WireRevision; } }
        public string RequestId { get; private set; }
        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public string Operation { get; private set; }
        public string Path { get; private set; }
        public bool? Loop { get; private set; }
        public double? Volume { get; private set; }
        public double? FadeSeconds { get; private set; }
        public double? SeekSeconds { get; private set; }
    }

    /// <summary>Parsed, immutable Audio Platform v2 SFX fast-lane batch.</summary>
    internal sealed class AudioSfxBatchV2
    {
        private readonly ReadOnlyCollection<string> _linkageIds;

        internal AudioSfxBatchV2(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong batchSequence,
            string[] linkageIds)
        {
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            BatchSequence = batchSequence;
            _linkageIds = Array.AsReadOnly((string[])linkageIds.Clone());
        }

        public int WireRevision { get { return AudioWireV2.WireRevision; } }
        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public ulong BatchSequence { get; private set; }
        public ReadOnlyCollection<string> LinkageIds { get { return _linkageIds; } }
    }

    /// <summary>
    /// Structured BGM completion supplied by the coordinator facade.  The task router
    /// accepts this typed model instead of arbitrary JSON so transport-only fields can
    /// never leak into the audio result.
    /// </summary>
    internal sealed class AudioBgmResultV2
    {
        internal AudioBgmResultV2(
            string requestId,
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            string operation,
            string completionState,
            string category,
            string stage,
            int nativeCode,
            int hresult,
            string decoderBackend,
            string messageKey)
        {
            RequestId = requestId;
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            DeviceGeneration = deviceGeneration;
            Operation = operation;
            CompletionState = completionState;
            Category = category;
            Stage = stage;
            NativeCode = nativeCode;
            HResult = hresult;
            DecoderBackend = decoderBackend;
            MessageKey = messageKey;
        }

        public string RequestId { get; private set; }
        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public ulong DeviceGeneration { get; private set; }
        public string Operation { get; private set; }
        public string CompletionState { get; private set; }
        public string Category { get; private set; }
        public string Stage { get; private set; }
        public int NativeCode { get; private set; }
        public int HResult { get; private set; }
        public string DecoderBackend { get; private set; }
        public string MessageKey { get; private set; }
    }

    /// <summary>One immutable aggregate SFX-counter snapshot.</summary>
    internal sealed class AudioSfxCountersV2
    {
        internal AudioSfxCountersV2(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            ulong preReadyDrops,
            ulong recoveryDrops,
            ulong staleGenerationDrops,
            ulong unknownIdCount,
            ulong throttledCount,
            ulong startFailureCount,
            ulong playedCount)
        {
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            DeviceGeneration = deviceGeneration;
            PreReadyDrops = preReadyDrops;
            RecoveryDrops = recoveryDrops;
            StaleGenerationDrops = staleGenerationDrops;
            UnknownIdCount = unknownIdCount;
            ThrottledCount = throttledCount;
            StartFailureCount = startFailureCount;
            PlayedCount = playedCount;
        }

        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public ulong DeviceGeneration { get; private set; }
        public ulong PreReadyDrops { get; private set; }
        public ulong RecoveryDrops { get; private set; }
        public ulong StaleGenerationDrops { get; private set; }
        public ulong UnknownIdCount { get; private set; }
        public ulong ThrottledCount { get; private set; }
        public ulong StartFailureCount { get; private set; }
        public ulong PlayedCount { get; private set; }
    }

    /// <summary>
    /// Strict, allocation-bounded Audio Platform v2 wire codec.
    ///
    /// This class is deliberately side-effect free.  It validates syntax and the
    /// frozen wire vocabulary; coordinator state, path containment and native calls
    /// remain outside this layer.
    /// </summary>
    internal static class AudioWireV2
    {
        public const int WireRevision = 2;

        public const int MaxBgmRequestUtf8Bytes = 65536;
        public const int MaxRequestIdUtf8Bytes = 128;
        public const int MaxBgmPathUtf16CodeUnits = 32767;
        public const double MaxVolume = 1.0d;
        public const double MaxFadeSeconds = 60.0d;
        public const double MaxSeekSeconds = 86400.0d;

        public const int MaxSfxMessageUtf8Bytes = 8192;
        public const int MaxSfxBatchIds = 64;
        public const int MaxSfxLinkageIdUtf16CodeUnits = 255;

        public const string BgmPlay = "play";
        public const string BgmStop = "stop";
        public const string BgmPause = "pause";
        public const string BgmResume = "resume";
        public const string BgmSeek = "seek";
        public const string BgmSetLoop = "set_loop";
        public const string BgmSetGain = "set_gain";

        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);

        private static readonly JsonLoadSettings StrictJsonSettings =
            new JsonLoadSettings
            {
                DuplicatePropertyNameHandling =
                    DuplicatePropertyNameHandling.Error
            };

        private static readonly string[] ResultCategoryValues =
        {
            "ok",
            "missing",
            "unsupported_container",
            "unsupported_codec",
            "malformed",
            "truncated",
            "io_error",
            "abi_mismatch",
            "not_ready",
            "stale_generation",
            "unknown_id",
            "throttled",
            "start_failed",
            "seek_failed",
            "device_unavailable",
            "device_lost",
            "superseded",
            "internal_error"
        };

        private static readonly string[] CompletionStateValues =
        {
            "accepted_deferred",
            "started",
            "stopped",
            "superseded",
            "failed"
        };

        private static readonly string[] CounterNameValues =
        {
            "preReadyDrops",
            "recoveryDrops",
            "staleGenerationDrops",
            "unknownIdCount",
            "throttledCount",
            "startFailureCount",
            "playedCount"
        };

        private static readonly ReadOnlyCollection<string> ResultCategoryList =
            Array.AsReadOnly(ResultCategoryValues);
        private static readonly ReadOnlyCollection<string> CompletionStateList =
            Array.AsReadOnly(CompletionStateValues);
        private static readonly ReadOnlyCollection<string> CounterNameList =
            Array.AsReadOnly(CounterNameValues);

        private static readonly HashSet<string> ResultCategorySet =
            new HashSet<string>(ResultCategoryValues, StringComparer.Ordinal);
        private static readonly HashSet<string> CompletionStateSet =
            new HashSet<string>(CompletionStateValues, StringComparer.Ordinal);
        private static readonly HashSet<string> CounterNameSet =
            new HashSet<string>(CounterNameValues, StringComparer.Ordinal);

        private static readonly HashSet<string> Operations =
            new HashSet<string>(StringComparer.Ordinal)
            {
                BgmPlay,
                BgmStop,
                BgmPause,
                BgmResume,
                BgmSeek,
                BgmSetLoop,
                BgmSetGain
            };

        private static readonly HashSet<string> ResultStages =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "none",
                "validate_abi",
                "validate_capacity",
                "validate_session",
                "validate_path",
                "admission",
                "context_initialize",
                "device_initialize",
                "device_start",
                "decoder_initialize",
                "source_initialize",
                "native_start",
                "seek",
                "probe_input",
                "probe_decode",
                "shutdown"
            };

        private static readonly HashSet<string> DecoderBackends =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "none",
                "builtin",
                "libvorbis",
                "media_foundation",
                "libopus"
            };

        private static readonly HashSet<string> PlayKeys = Set(
            "wireRevision", "requestId", "audioSessionId",
            "audioReadyGeneration", "operation",
            "path", "loop", "volume", "fadeSeconds");

        private static readonly HashSet<string> StopKeys = Set(
            "wireRevision", "requestId", "audioSessionId",
            "audioReadyGeneration", "operation", "fadeSeconds");

        private static readonly HashSet<string> NoPayloadKeys = Set(
            "wireRevision", "requestId", "audioSessionId",
            "audioReadyGeneration", "operation");

        private static readonly HashSet<string> SeekKeys = Set(
            "wireRevision", "requestId", "audioSessionId",
            "audioReadyGeneration", "operation", "seekSeconds");

        private static readonly HashSet<string> LoopKeys = Set(
            "wireRevision", "requestId", "audioSessionId",
            "audioReadyGeneration", "operation", "loop");

        private static readonly HashSet<string> GainKeys = Set(
            "wireRevision", "requestId", "audioSessionId",
            "audioReadyGeneration", "operation", "volume");

        public static ReadOnlyCollection<string> ResultCategories
        {
            get { return ResultCategoryList; }
        }

        public static ReadOnlyCollection<string> CompletionStates
        {
            get { return CompletionStateList; }
        }

        public static ReadOnlyCollection<string> CounterNames
        {
            get { return CounterNameList; }
        }

        public static bool IsResultCategory(string value)
        {
            return value != null && ResultCategorySet.Contains(value);
        }

        public static bool IsCompletionState(string value)
        {
            return value != null && CompletionStateSet.Contains(value);
        }

        public static bool IsCounterName(string value)
        {
            return value != null && CounterNameSet.Contains(value);
        }

        /// <summary>
        /// Parses raw JSON with duplicate-property rejection before JObject can collapse
        /// duplicate semantics.  Callers that still possess the raw frame should prefer
        /// this overload.
        /// </summary>
        public static bool TryParseBgmRequest(
            string json,
            out AudioBgmRequestV2 request,
            out string error)
        {
            request = null;
            error = null;
            if (string.IsNullOrEmpty(json))
            {
                error = "bgm.json_empty";
                return false;
            }

            try
            {
                if (StrictUtf8.GetByteCount(json) > MaxBgmRequestUtf8Bytes)
                {
                    error = "bgm.json_too_large";
                    return false;
                }

                JObject message = JObject.Parse(json, StrictJsonSettings);
                return TryParseBgmRequest(message, out request, out error);
            }
            catch (Exception ex) when (
                ex is JsonException
                || ex is ArgumentException
                || ex is EncoderFallbackException)
            {
                error = "bgm.json_invalid";
                return false;
            }
        }

        /// <summary>
        /// Parses an already materialized object.  Exact keys and types are still checked;
        /// duplicate-key protection requires the raw-string overload above.
        /// </summary>
        public static bool TryParseBgmRequest(
            JObject message,
            out AudioBgmRequestV2 request,
            out string error)
        {
            request = null;
            error = null;
            if (message == null)
            {
                error = "bgm.object_null";
                return false;
            }

            string operation;
            if (!TryReadString(message["operation"], out operation)
                || !Operations.Contains(operation))
            {
                error = "bgm.operation";
                return false;
            }

            HashSet<string> expectedKeys = ExpectedKeys(operation);
            if (expectedKeys == null || !HasExactKeys(message, expectedKeys))
            {
                error = "bgm.keys";
                return false;
            }

            if (!IsExactWireRevision(message["wireRevision"]))
            {
                error = "bgm.wire_revision";
                return false;
            }

            string requestId;
            if (!TryReadString(message["requestId"], out requestId)
                || !IsCanonicalRequestId(requestId))
            {
                error = "bgm.request_id";
                return false;
            }

            string audioSessionId;
            if (!TryReadString(message["audioSessionId"], out audioSessionId)
                || !IsCanonicalAudioSessionId(audioSessionId))
            {
                error = "bgm.audio_session_id";
                return false;
            }

            ulong audioReadyGeneration;
            if (!TryReadUint64DecimalString(
                message["audioReadyGeneration"],
                out audioReadyGeneration))
            {
                error = "bgm.audio_ready_generation";
                return false;
            }

            string path = null;
            bool? loop = null;
            double? volume = null;
            double? fadeSeconds = null;
            double? seekSeconds = null;

            if (operation == BgmPlay)
            {
                if (!TryReadString(message["path"], out path)
                    || !IsValidBgmPath(path))
                {
                    error = "bgm.path";
                    return false;
                }

                bool loopValue;
                if (!TryReadBoolean(message["loop"], out loopValue))
                {
                    error = "bgm.loop";
                    return false;
                }
                loop = loopValue;

                double volumeValue;
                if (!TryReadBoundedNumber(
                    message["volume"], 0.0d, MaxVolume, out volumeValue))
                {
                    error = "bgm.volume";
                    return false;
                }
                volume = volumeValue;

                double fadeValue;
                if (!TryReadBoundedNumber(
                    message["fadeSeconds"], 0.0d, MaxFadeSeconds, out fadeValue))
                {
                    error = "bgm.fade_seconds";
                    return false;
                }
                fadeSeconds = fadeValue;
            }
            else if (operation == BgmStop)
            {
                double fadeValue;
                if (!TryReadBoundedNumber(
                    message["fadeSeconds"], 0.0d, MaxFadeSeconds, out fadeValue))
                {
                    error = "bgm.fade_seconds";
                    return false;
                }
                fadeSeconds = fadeValue;
            }
            else if (operation == BgmSeek)
            {
                double seekValue;
                if (!TryReadBoundedNumber(
                    message["seekSeconds"], 0.0d, MaxSeekSeconds, out seekValue))
                {
                    error = "bgm.seek_seconds";
                    return false;
                }
                seekSeconds = seekValue;
            }
            else if (operation == BgmSetLoop)
            {
                bool loopValue;
                if (!TryReadBoolean(message["loop"], out loopValue))
                {
                    error = "bgm.loop";
                    return false;
                }
                loop = loopValue;
            }
            else if (operation == BgmSetGain)
            {
                double volumeValue;
                if (!TryReadBoundedNumber(
                    message["volume"], 0.0d, MaxVolume, out volumeValue))
                {
                    error = "bgm.volume";
                    return false;
                }
                volume = volumeValue;
            }

            request = new AudioBgmRequestV2(
                requestId,
                audioSessionId,
                audioReadyGeneration,
                operation,
                path,
                loop,
                volume,
                fadeSeconds,
                seekSeconds);
            return true;
        }

        /// <summary>Serializes a parsed request in the H1 field order.</summary>
        public static JObject SerializeBgmRequest(AudioBgmRequestV2 request)
        {
            if (request == null) throw new ArgumentNullException("request");

            JObject result = new JObject
            {
                ["wireRevision"] = WireRevision,
                ["requestId"] = request.RequestId,
                ["audioSessionId"] = request.AudioSessionId,
                ["audioReadyGeneration"] = ToDecimalString(
                    request.AudioReadyGeneration),
                ["operation"] = request.Operation
            };

            if (request.Operation == BgmPlay)
            {
                result["path"] = request.Path;
                result["loop"] = request.Loop.Value;
                result["volume"] = request.Volume.Value;
                result["fadeSeconds"] = request.FadeSeconds.Value;
            }
            else if (request.Operation == BgmStop)
            {
                result["fadeSeconds"] = request.FadeSeconds.Value;
            }
            else if (request.Operation == BgmSeek)
            {
                result["seekSeconds"] = request.SeekSeconds.Value;
            }
            else if (request.Operation == BgmSetLoop)
            {
                result["loop"] = request.Loop.Value;
            }
            else if (request.Operation == BgmSetGain)
            {
                result["volume"] = request.Volume.Value;
            }
            else if (request.Operation != BgmPause
                && request.Operation != BgmResume)
            {
                throw new ArgumentException(
                    "Unsupported BGM operation.", "request");
            }

            AudioBgmRequestV2 reparsed;
            string error;
            if (!TryParseBgmRequest(result, out reparsed, out error))
            {
                throw new ArgumentException(
                    "Invalid BGM request model: " + error,
                    "request");
            }
            return result;
        }

        /// <summary>
        /// Serializes one correlated BGM result.  All fields are emitted in a stable order;
        /// audio-domain uint64 values remain decimal strings for AS2 precision safety.
        /// </summary>
        public static JObject SerializeBgmResult(
            string requestId,
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            string operation,
            string completionState,
            string category,
            string stage,
            int nativeCode,
            int hresult,
            string decoderBackend,
            string messageKey)
        {
            return SerializeBgmResult(new AudioBgmResultV2(
                requestId,
                audioSessionId,
                audioReadyGeneration,
                deviceGeneration,
                operation,
                completionState,
                category,
                stage,
                nativeCode,
                hresult,
                decoderBackend,
                messageKey));
        }

        public static JObject SerializeBgmResult(AudioBgmResultV2 result)
        {
            if (result == null) throw new ArgumentNullException("result");
            if (!IsCanonicalRequestId(result.RequestId))
                throw new ArgumentException("Invalid request id.", "requestId");
            if (!IsCanonicalAudioSessionId(result.AudioSessionId))
                throw new ArgumentException(
                    "Invalid audio session id.", "audioSessionId");
            if (!Operations.Contains(result.Operation))
                throw new ArgumentException("Invalid operation.", "operation");
            if (!CompletionStateSet.Contains(result.CompletionState))
                throw new ArgumentException(
                    "Invalid completion state.", "completionState");
            if (!ResultCategorySet.Contains(result.Category))
                throw new ArgumentException("Invalid result category.", "category");
            if (!HasValidResultSemantics(
                result.CompletionState,
                result.Category))
                throw new ArgumentException(
                    "Completion state and result category disagree.",
                    "category");
            if (!ResultStages.Contains(result.Stage))
                throw new ArgumentException("Invalid result stage.", "stage");
            if (!DecoderBackends.Contains(result.DecoderBackend))
                throw new ArgumentException(
                    "Invalid decoder backend.", "decoderBackend");
            if (!IsMessageKey(result.MessageKey))
                throw new ArgumentException("Invalid message key.", "messageKey");

            return new JObject
            {
                ["wireRevision"] = WireRevision,
                ["requestId"] = result.RequestId,
                ["audioSessionId"] = result.AudioSessionId,
                ["audioReadyGeneration"] = ToDecimalString(
                    result.AudioReadyGeneration),
                ["deviceGeneration"] = ToDecimalString(
                    result.DeviceGeneration),
                ["operation"] = result.Operation,
                ["completionState"] = result.CompletionState,
                ["category"] = result.Category,
                ["stage"] = result.Stage,
                ["nativeCode"] = result.NativeCode,
                ["hresult"] = result.HResult,
                ["decoderBackend"] = result.DecoderBackend,
                ["messageKey"] = result.MessageKey
            };
        }

        public static bool TryParseSfxBatch(
            string message,
            out AudioSfxBatchV2 batch,
            out string error)
        {
            batch = null;
            error = null;
            if (string.IsNullOrEmpty(message))
            {
                error = "sfx.message_empty";
                return false;
            }

            try
            {
                if (StrictUtf8.GetByteCount(message) > MaxSfxMessageUtf8Bytes)
                {
                    error = "sfx.message_too_large";
                    return false;
                }
            }
            catch (EncoderFallbackException)
            {
                error = "sfx.invalid_unicode";
                return false;
            }

            if (message.IndexOf('\0') >= 0
                || message.IndexOf('\r') >= 0
                || message.IndexOf('\n') >= 0)
            {
                error = "sfx.control_character";
                return false;
            }

            string[] fields = message.Split(
                new[] { '|' },
                StringSplitOptions.None);
            if (fields.Length < 5)
            {
                error = "sfx.fields_missing";
                return false;
            }
            if (fields.Length > 4 + MaxSfxBatchIds)
            {
                error = "sfx.too_many_ids";
                return false;
            }
            if (!string.Equals(fields[0], "S2", StringComparison.Ordinal))
            {
                error = "sfx.wire_revision";
                return false;
            }
            if (!IsCanonicalAudioSessionId(fields[1]))
            {
                error = "sfx.audio_session_id";
                return false;
            }

            ulong audioReadyGeneration;
            if (!TryParseUint64DecimalString(
                fields[2], out audioReadyGeneration))
            {
                error = "sfx.audio_ready_generation";
                return false;
            }

            ulong batchSequence;
            if (!TryParseUint64DecimalString(fields[3], out batchSequence))
            {
                error = "sfx.batch_sequence";
                return false;
            }

            string[] linkageIds = new string[fields.Length - 4];
            for (int i = 4; i < fields.Length; i++)
            {
                if (!IsValidLinkageId(fields[i]))
                {
                    error = "sfx.linkage_id";
                    return false;
                }
                // Order and duplicates are semantic: two same-id events in one frame
                // remain two play intents.  This layer must never silently de-duplicate.
                linkageIds[i - 4] = fields[i];
            }

            batch = new AudioSfxBatchV2(
                fields[1],
                audioReadyGeneration,
                batchSequence,
                linkageIds);
            return true;
        }

        public static string SerializeSfxBatch(AudioSfxBatchV2 batch)
        {
            if (batch == null) throw new ArgumentNullException("batch");
            if (!IsCanonicalAudioSessionId(batch.AudioSessionId))
                throw new ArgumentException(
                    "Invalid audio session id.", "batch");
            if (batch.LinkageIds.Count == 0
                || batch.LinkageIds.Count > MaxSfxBatchIds)
                throw new ArgumentException(
                    "Invalid SFX id count.", "batch");

            var builder = new StringBuilder();
            builder.Append("S2|");
            builder.Append(batch.AudioSessionId);
            builder.Append('|');
            builder.Append(ToDecimalString(batch.AudioReadyGeneration));
            builder.Append('|');
            builder.Append(ToDecimalString(batch.BatchSequence));

            for (int i = 0; i < batch.LinkageIds.Count; i++)
            {
                string linkageId = batch.LinkageIds[i];
                if (!IsValidLinkageId(linkageId))
                    throw new ArgumentException(
                        "Invalid SFX linkage id.", "batch");
                builder.Append('|');
                builder.Append(linkageId);
            }

            string message = builder.ToString();
            try
            {
                if (StrictUtf8.GetByteCount(message) > MaxSfxMessageUtf8Bytes)
                    throw new ArgumentException(
                        "SFX batch exceeds the wire bound.", "batch");
            }
            catch (EncoderFallbackException)
            {
                throw new ArgumentException(
                    "SFX batch contains invalid Unicode.", "batch");
            }
            return message;
        }

        /// <summary>
        /// Emits the exact H1 counter names.  Counters use decimal strings because AS2
        /// cannot safely represent the complete uint64 range as Number.
        /// </summary>
        public static JObject SerializeSfxCounters(AudioSfxCountersV2 counters)
        {
            if (counters == null) throw new ArgumentNullException("counters");
            if (!IsCanonicalAudioSessionId(counters.AudioSessionId))
                throw new ArgumentException(
                    "Invalid audio session id.", "counters");

            return new JObject
            {
                ["wireRevision"] = WireRevision,
                ["audioSessionId"] = counters.AudioSessionId,
                ["audioReadyGeneration"] = ToDecimalString(
                    counters.AudioReadyGeneration),
                ["deviceGeneration"] = ToDecimalString(
                    counters.DeviceGeneration),
                ["preReadyDrops"] = ToDecimalString(counters.PreReadyDrops),
                ["recoveryDrops"] = ToDecimalString(counters.RecoveryDrops),
                ["staleGenerationDrops"] = ToDecimalString(
                    counters.StaleGenerationDrops),
                ["unknownIdCount"] = ToDecimalString(counters.UnknownIdCount),
                ["throttledCount"] = ToDecimalString(counters.ThrottledCount),
                ["startFailureCount"] = ToDecimalString(
                    counters.StartFailureCount),
                ["playedCount"] = ToDecimalString(counters.PlayedCount)
            };
        }

        private static HashSet<string> ExpectedKeys(string operation)
        {
            if (operation == BgmPlay) return PlayKeys;
            if (operation == BgmStop) return StopKeys;
            if (operation == BgmPause || operation == BgmResume)
                return NoPayloadKeys;
            if (operation == BgmSeek) return SeekKeys;
            if (operation == BgmSetLoop) return LoopKeys;
            if (operation == BgmSetGain) return GainKeys;
            return null;
        }

        private static bool HasExactKeys(
            JObject value,
            HashSet<string> expected)
        {
            if (value.Count != expected.Count) return false;
            foreach (JProperty property in value.Properties())
            {
                if (!expected.Contains(property.Name)) return false;
            }
            return true;
        }

        private static HashSet<string> Set(params string[] values)
        {
            return new HashSet<string>(values, StringComparer.Ordinal);
        }

        private static bool IsExactWireRevision(JToken token)
        {
            return token != null
                && token.Type == JTokenType.Integer
                && string.Equals(
                    token.ToString(Formatting.None),
                    "2",
                    StringComparison.Ordinal);
        }

        private static bool TryReadString(JToken token, out string value)
        {
            value = null;
            if (token == null || token.Type != JTokenType.String) return false;
            value = (string)token;
            return value != null;
        }

        private static bool TryReadBoolean(JToken token, out bool value)
        {
            value = false;
            if (token == null || token.Type != JTokenType.Boolean) return false;
            value = (bool)token;
            return true;
        }

        private static bool TryReadBoundedNumber(
            JToken token,
            double minimum,
            double maximum,
            out double value)
        {
            value = 0.0d;
            if (token == null
                || (token.Type != JTokenType.Integer
                    && token.Type != JTokenType.Float))
            {
                return false;
            }

            try
            {
                value = token.Value<double>();
            }
            catch (Exception ex) when (
                ex is FormatException
                || ex is InvalidCastException
                || ex is OverflowException)
            {
                return false;
            }

            return !double.IsNaN(value)
                && !double.IsInfinity(value)
                && value >= minimum
                && value <= maximum;
        }

        private static bool TryReadUint64DecimalString(
            JToken token,
            out ulong value)
        {
            value = 0;
            string text;
            return TryReadString(token, out text)
                && TryParseUint64DecimalString(text, out value);
        }

        private static bool TryParseUint64DecimalString(
            string text,
            out ulong value)
        {
            value = 0;
            if (string.IsNullOrEmpty(text) || text.Length > 20) return false;
            if (text.Length > 1 && text[0] == '0') return false;
            for (int i = 0; i < text.Length; i++)
            {
                char c = text[i];
                if (c < '0' || c > '9') return false;
            }
            return ulong.TryParse(
                text,
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out value);
        }

        private static bool IsCanonicalAudioSessionId(string value)
        {
            if (value == null || value.Length != 36) return false;
            Guid parsed;
            if (!Guid.TryParseExact(value, "D", out parsed)) return false;
            if (!string.Equals(
                parsed.ToString("D"),
                value,
                StringComparison.Ordinal))
            {
                return false;
            }
            if (value[14] != '4') return false;
            char variant = value[19];
            return variant == '8'
                || variant == '9'
                || variant == 'a'
                || variant == 'b';
        }

        private static bool IsCanonicalRequestId(string value)
        {
            if (string.IsNullOrEmpty(value)) return false;
            int byteCount;
            try
            {
                byteCount = StrictUtf8.GetByteCount(value);
            }
            catch (EncoderFallbackException)
            {
                return false;
            }
            if (byteCount > MaxRequestIdUtf8Bytes
                || !IsAsciiAlphaNumeric(value[0]))
            {
                return false;
            }

            for (int i = 1; i < value.Length; i++)
            {
                char c = value[i];
                if (!IsAsciiAlphaNumeric(c)
                    && c != '.'
                    && c != '_'
                    && c != ':'
                    && c != '-')
                {
                    return false;
                }
            }
            return true;
        }

        private static bool IsAsciiAlphaNumeric(char value)
        {
            return (value >= 'a' && value <= 'z')
                || (value >= 'A' && value <= 'Z')
                || (value >= '0' && value <= '9');
        }

        private static bool IsValidBgmPath(string value)
        {
            if (string.IsNullOrWhiteSpace(value)
                || value.Length > MaxBgmPathUtf16CodeUnits
                || value.IndexOf('\0') >= 0
                || value.IndexOf('\r') >= 0
                || value.IndexOf('\n') >= 0)
            {
                return false;
            }
            try
            {
                StrictUtf8.GetByteCount(value);
                return true;
            }
            catch (EncoderFallbackException)
            {
                return false;
            }
        }

        private static bool IsValidLinkageId(string value)
        {
            if (string.IsNullOrEmpty(value)
                || value.Length > MaxSfxLinkageIdUtf16CodeUnits
                || value.IndexOf('|') >= 0
                || value.IndexOf('\0') >= 0
                || value.IndexOf('\r') >= 0
                || value.IndexOf('\n') >= 0
                || value.IndexOf('/') >= 0
                || value.IndexOf('\\') >= 0
                || value == "."
                || value == "..")
            {
                return false;
            }
            try
            {
                StrictUtf8.GetByteCount(value);
                return true;
            }
            catch (EncoderFallbackException)
            {
                return false;
            }
        }

        private static bool HasValidResultSemantics(
            string completionState,
            string category)
        {
            if (completionState == "failed")
                return category != "ok" && category != "superseded";
            if (completionState == "superseded")
                return category == "superseded";
            return category == "ok";
        }

        private static bool IsMessageKey(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > 128)
                return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                if ((c < 'a' || c > 'z')
                    && (c < '0' || c > '9')
                    && c != '.'
                    && c != '_'
                    && c != '-')
                {
                    return false;
                }
            }
            return true;
        }

        private static string ToDecimalString(ulong value)
        {
            return value.ToString(CultureInfo.InvariantCulture);
        }
    }
}
