using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace CF7Launcher.Audio
{
    internal enum AudioCoordinatorStatusV2
    {
        Initializing,
        Ready,
        Recovering,
        Unavailable,
        Shutdown
    }

    internal sealed class AudioCatalogItemV2
    {
        internal AudioCatalogItemV2(string linkageId, string normalizedPath)
        {
            LinkageId = linkageId;
            NormalizedPath = normalizedPath;
        }

        public string LinkageId { get; private set; }
        public string NormalizedPath { get; private set; }
    }

    internal sealed class AudioPreloadResultV2
    {
        private readonly ReadOnlyCollection<AudioCatalogItemV2> _items;

        internal AudioPreloadResultV2(
            IList<AudioCatalogItemV2> items,
            int failed,
            int overrides)
        {
            if (items == null) throw new ArgumentNullException("items");
            _items = new ReadOnlyCollection<AudioCatalogItemV2>(
                new List<AudioCatalogItemV2>(items));
            Failed = failed;
            Overrides = overrides;
        }

        public ReadOnlyCollection<AudioCatalogItemV2> Items
        {
            get { return _items; }
        }

        public int Failed { get; private set; }
        public int Overrides { get; private set; }
    }

    internal sealed class AudioNativeSfxCountersV2
    {
        internal AudioNativeSfxCountersV2(
            string audioSessionId,
            ulong audioReadyGeneration,
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
        public ulong PreReadyDrops { get; private set; }
        public ulong RecoveryDrops { get; private set; }
        public ulong StaleGenerationDrops { get; private set; }
        public ulong UnknownIdCount { get; private set; }
        public ulong ThrottledCount { get; private set; }
        public ulong StartFailureCount { get; private set; }
        public ulong PlayedCount { get; private set; }
    }

    internal sealed class AudioNativeCallResultV2
    {
        internal AudioNativeCallResultV2(
            uint category,
            uint operation,
            uint stage,
            int nativeCode,
            int hresult,
            uint completionState,
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            string messageKey,
            string decoderBackend)
            : this(
                category,
                operation,
                stage,
                nativeCode,
                hresult,
                completionState,
                audioSessionId,
                audioReadyGeneration,
                deviceGeneration,
                messageKey,
                decoderBackend,
                null)
        {
        }

        private AudioNativeCallResultV2(
            uint category,
            uint operation,
            uint stage,
            int nativeCode,
            int hresult,
            uint completionState,
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            string messageKey,
            string decoderBackend,
            AudioNativeSfxCountersV2 sfxCounters)
        {
            Category = category;
            Operation = operation;
            Stage = stage;
            NativeCode = nativeCode;
            Hresult = hresult;
            CompletionState = completionState;
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            DeviceGeneration = deviceGeneration;
            MessageKey = messageKey;
            DecoderBackend = decoderBackend;
            SfxCounters = sfxCounters;
        }

        public uint Category { get; private set; }
        public uint Operation { get; private set; }
        public uint Stage { get; private set; }
        public int NativeCode { get; private set; }
        public int Hresult { get; private set; }
        public uint CompletionState { get; private set; }
        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public ulong DeviceGeneration { get; private set; }
        public string MessageKey { get; private set; }
        public string DecoderBackend { get; private set; }
        public AudioNativeSfxCountersV2 SfxCounters { get; private set; }

        public bool IsOk { get { return Category == AudioNativeV2.ResultOk; } }

        internal AudioNativeCallResultV2 WithSfxCounters(
            AudioNativeSfxCountersV2 counters)
        {
            if (counters == null) throw new ArgumentNullException("counters");
            return new AudioNativeCallResultV2(
                Category,
                Operation,
                Stage,
                NativeCode,
                Hresult,
                CompletionState,
                AudioSessionId,
                AudioReadyGeneration,
                DeviceGeneration,
                MessageKey,
                DecoderBackend,
                counters);
        }

        internal static AudioNativeCallResultV2 Failure(
            uint category,
            uint operation,
            uint stage,
            string sessionId,
            ulong readyGeneration,
            ulong deviceGeneration,
            string messageKey)
        {
            return new AudioNativeCallResultV2(
                category,
                operation,
                stage,
                0,
                0,
                AudioNativeV2.CompletionFailed,
                sessionId,
                readyGeneration,
                deviceGeneration,
                messageKey,
                "none");
        }
    }

    internal sealed class AudioNativeCapabilityResultV2
    {
        internal AudioNativeCapabilityResultV2(
            bool accepted,
            string capabilityDigest,
            AudioNativeCallResultV2 result)
        {
            Accepted = accepted;
            CapabilityDigest = capabilityDigest;
            Result = result;
        }

        public bool Accepted { get; private set; }
        public string CapabilityDigest { get; private set; }
        public AudioNativeCallResultV2 Result { get; private set; }
    }

    internal sealed class AudioNativeInitializeResultV2
    {
        internal AudioNativeInitializeResultV2(
            bool ready,
            bool returnedTupleValid,
            ulong deviceGeneration,
            uint backend,
            uint sampleRate,
            uint channels,
            uint sampleFormat,
            AudioNativeCallResultV2 result)
            : this(
                ready,
                returnedTupleValid,
                deviceGeneration,
                backend,
                null,
                null,
                sampleRate,
                channels,
                sampleFormat,
                result)
        {
        }

        internal AudioNativeInitializeResultV2(
            bool ready,
            bool returnedTupleValid,
            ulong deviceGeneration,
            uint backend,
            string deviceIdDigest,
            string deviceName,
            uint sampleRate,
            uint channels,
            uint sampleFormat,
            AudioNativeCallResultV2 result)
        {
            Ready = ready;
            ReturnedTupleValid = returnedTupleValid;
            DeviceGeneration = deviceGeneration;
            Backend = backend;
            DeviceIdDigest = deviceIdDigest;
            DeviceName = deviceName;
            SampleRate = sampleRate;
            Channels = channels;
            SampleFormat = sampleFormat;
            Result = result;
        }

        public bool Ready { get; private set; }
        public bool ReturnedTupleValid { get; private set; }
        public ulong DeviceGeneration { get; private set; }
        public uint Backend { get; private set; }
        public string DeviceIdDigest { get; private set; }
        public string DeviceName { get; private set; }
        public uint SampleRate { get; private set; }
        public uint Channels { get; private set; }
        public uint SampleFormat { get; private set; }
        public AudioNativeCallResultV2 Result { get; private set; }
    }

    internal sealed class AudioNativeMeterObservationV2
    {
        internal AudioNativeMeterObservationV2(
            float peakLeft,
            float peakRight,
            float rmsLeft,
            float rmsRight,
            ulong clipCount,
            ulong frameCount,
            ulong underrunCount)
        {
            PeakLeft = peakLeft;
            PeakRight = peakRight;
            RmsLeft = rmsLeft;
            RmsRight = rmsRight;
            ClipCount = clipCount;
            FrameCount = frameCount;
            UnderrunCount = underrunCount;
        }

        public float PeakLeft { get; private set; }
        public float PeakRight { get; private set; }
        public float RmsLeft { get; private set; }
        public float RmsRight { get; private set; }
        public ulong ClipCount { get; private set; }
        public ulong FrameCount { get; private set; }
        public ulong UnderrunCount { get; private set; }

        internal static AudioNativeMeterObservationV2 Empty
        {
            get
            {
                return new AudioNativeMeterObservationV2(
                    0f, 0f, 0f, 0f, 0uL, 0uL, 0uL);
            }
        }
    }

    internal sealed class AudioNativeObservationV2
    {
        internal AudioNativeObservationV2(
            bool valid,
            float peakLeft,
            float peakRight,
            float cursorSeconds,
            float lengthSeconds,
            bool playing,
            string decoderBackend)
            : this(
                valid,
                new AudioNativeMeterObservationV2(
                    peakLeft,
                    peakRight,
                    0f,
                    0f,
                    0uL,
                    0uL,
                    0uL),
                AudioNativeMeterObservationV2.Empty,
                cursorSeconds,
                lengthSeconds,
                0uL,
                0uL,
                playing,
                decoderBackend,
                "none",
                "none",
                AudioNativeV2.ResultNotReady,
                null)
        {
        }

        internal AudioNativeObservationV2(
            bool valid,
            AudioNativeMeterObservationV2 bgmMeter,
            AudioNativeMeterObservationV2 sfxMeter,
            float cursorSeconds,
            float lengthSeconds,
            ulong cursorFrames,
            ulong lengthFrames,
            bool playing,
            string decoderBackend,
            string container,
            string codec,
            uint startCategory,
            AudioNativeSfxCountersV2 sfxCounters)
        {
            Valid = valid;
            BgmMeter = bgmMeter ?? AudioNativeMeterObservationV2.Empty;
            SfxMeter = sfxMeter ?? AudioNativeMeterObservationV2.Empty;
            PeakLeft = BgmMeter.PeakLeft;
            PeakRight = BgmMeter.PeakRight;
            CursorSeconds = cursorSeconds;
            LengthSeconds = lengthSeconds;
            CursorFrames = cursorFrames;
            LengthFrames = lengthFrames;
            Playing = playing;
            DecoderBackend = decoderBackend;
            Container = container;
            Codec = codec;
            StartCategory = startCategory;
            SfxCounters = sfxCounters;
        }

        public bool Valid { get; private set; }
        public float PeakLeft { get; private set; }
        public float PeakRight { get; private set; }
        public float CursorSeconds { get; private set; }
        public float LengthSeconds { get; private set; }
        public ulong CursorFrames { get; private set; }
        public ulong LengthFrames { get; private set; }
        public bool Playing { get; private set; }
        public string DecoderBackend { get; private set; }
        public string Container { get; private set; }
        public string Codec { get; private set; }
        public uint StartCategory { get; private set; }
        public AudioNativeMeterObservationV2 BgmMeter { get; private set; }
        public AudioNativeMeterObservationV2 SfxMeter { get; private set; }
        public AudioNativeSfxCountersV2 SfxCounters { get; private set; }
    }

    internal sealed class AudioNativeRuntimeStateV2
    {
        internal AudioNativeRuntimeStateV2(
            bool valid,
            uint audioStatus,
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            AudioNativeCallResultV2 result)
            : this(
                valid,
                audioStatus,
                audioSessionId,
                audioReadyGeneration,
                deviceGeneration,
                AudioNativeV2.BackendNone,
                null,
                null,
                0u,
                0u,
                AudioNativeV2.SampleFormatUnknown,
                result)
        {
        }

        internal AudioNativeRuntimeStateV2(
            bool valid,
            uint audioStatus,
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            uint backend,
            string deviceIdDigest,
            string deviceName,
            uint sampleRate,
            uint channels,
            uint sampleFormat,
            AudioNativeCallResultV2 result)
        {
            Valid = valid;
            AudioStatus = audioStatus;
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            DeviceGeneration = deviceGeneration;
            Backend = backend;
            DeviceIdDigest = deviceIdDigest;
            DeviceName = deviceName;
            SampleRate = sampleRate;
            Channels = channels;
            SampleFormat = sampleFormat;
            Result = result;
        }

        public bool Valid { get; private set; }
        public uint AudioStatus { get; private set; }
        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public ulong DeviceGeneration { get; private set; }
        public uint Backend { get; private set; }
        public string DeviceIdDigest { get; private set; }
        public string DeviceName { get; private set; }
        public uint SampleRate { get; private set; }
        public uint Channels { get; private set; }
        public uint SampleFormat { get; private set; }
        public AudioNativeCallResultV2 Result { get; private set; }
    }

    internal sealed class AudioRuntimeProbeResultV2
    {
        internal AudioRuntimeProbeResultV2(
            bool valid,
            uint outcome,
            ulong frames,
            double durationSeconds,
            double peak,
            double rms,
            uint elapsedMilliseconds,
            ulong inputBytesRead,
            AudioNativeCallResultV2 result)
        {
            Valid = valid;
            Outcome = outcome;
            Frames = frames;
            DurationSeconds = durationSeconds;
            Peak = peak;
            Rms = rms;
            ElapsedMilliseconds = elapsedMilliseconds;
            InputBytesRead = inputBytesRead;
            Result = result;
        }

        public bool Valid { get; private set; }
        public uint Outcome { get; private set; }
        public ulong Frames { get; private set; }
        public double DurationSeconds { get; private set; }
        public double Peak { get; private set; }
        public double Rms { get; private set; }
        public uint ElapsedMilliseconds { get; private set; }
        public ulong InputBytesRead { get; private set; }
        public AudioNativeCallResultV2 Result { get; private set; }
    }

    internal sealed class AudioNativeBgmCommandV2
    {
        internal AudioNativeBgmCommandV2(
            string requestId,
            string audioSessionId,
            ulong audioReadyGeneration,
            uint operation,
            string normalizedPath,
            bool loop,
            float volume,
            float fadeSeconds,
            float seekSeconds)
        {
            RequestId = requestId;
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            Operation = operation;
            NormalizedPath = normalizedPath;
            Loop = loop;
            Volume = volume;
            FadeSeconds = fadeSeconds;
            SeekSeconds = seekSeconds;
        }

        public string RequestId { get; private set; }
        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public uint Operation { get; private set; }
        public string NormalizedPath { get; private set; }
        public bool Loop { get; private set; }
        public float Volume { get; private set; }
        public float FadeSeconds { get; private set; }
        public float SeekSeconds { get; private set; }
    }

    internal interface IAudioNativeV2
    {
        AudioNativeCapabilityResultV2 QueryCapability();

        AudioNativeInitializeResultV2 Initialize(
            string normalizedBasePath,
            string audioSessionId,
            ulong audioReadyGeneration);

        AudioNativeRuntimeStateV2 QueryRuntime();

        AudioNativeCallResultV2 RebuildSfxCatalog(
            string audioSessionId,
            ulong audioReadyGeneration,
            IList<AudioCatalogItemV2> items);

        AudioNativeCallResultV2 SubmitBgm(AudioNativeBgmCommandV2 command);

        AudioNativeCallResultV2 SubmitSfxBatch(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong batchSequence,
            IList<string> linkageIds,
            float volume);

        AudioNativeCallResultV2 SetGain(
            string audioSessionId,
            ulong audioReadyGeneration,
            uint operation,
            float gain);

        AudioNativeObservationV2 QueryBgmObservation(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration);

        AudioNativeObservationV2 QueryBgmRecoveryObservation(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration);

        AudioRuntimeProbeResultV2 ProbeRuntimeCompatibility(
            string normalizedPath,
            ulong fileSizeBytes,
            long modifiedTimeUnixMilliseconds,
            string first64kSha256,
            string capabilityDigestSha256,
            string audioSessionId,
            ulong audioReadyGeneration);

        AudioNativeCallResultV2 Shutdown(
            string audioSessionId,
            ulong audioReadyGeneration);
    }

    // Qualification-only read expansion. Keeping this outside IAudioNativeV2
    // preserves the standard observation path and its existing test doubles.
    internal interface IAudioNativeQualificationObservationV2
    {
        AudioNativeObservationV2 QueryQualificationObservation(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration);
    }

    internal delegate AudioPreloadResultV2 AudioPreloadHookV2(
        string normalizedBasePath,
        CancellationToken cancellationToken);

    internal delegate void AudioCatalogHookV2(
        string audioSessionId,
        ulong audioReadyGeneration,
        ulong deviceGeneration,
        AudioPreloadResultV2 catalog,
        CancellationToken cancellationToken);

    internal sealed class AudioCatalogQualificationRequestV2
    {
        internal AudioCatalogQualificationRequestV2(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            string capabilityDigest,
            CancellationToken cancellationToken)
        {
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            DeviceGeneration = deviceGeneration;
            CapabilityDigest = capabilityDigest;
            CancellationToken = cancellationToken;
        }

        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public ulong DeviceGeneration { get; private set; }
        public string CapabilityDigest { get; private set; }
        public CancellationToken CancellationToken { get; private set; }
    }

    internal delegate void AudioCatalogQualificationHookV2(
        AudioCatalogQualificationRequestV2 request);

    internal sealed class AudioCoordinatorQualificationStateV2
    {
        internal uint Backend;
        internal string DeviceIdDigest;
        internal string DeviceName;
        internal uint SampleRate;
        internal uint Channels;
        internal uint SampleFormat;
        internal string SourceRequestId;
        internal AudioNativeObservationV2 Observation;
    }

    internal sealed class AudioCoordinatorSnapshotV2
    {
        private readonly ReadOnlyDictionary<string, int> _sfxHandles;

        internal AudioCoordinatorSnapshotV2(
            AudioCoordinatorStatusV2 status,
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            string normalizedBasePath,
            string capabilityDigest,
            int loaded,
            int failed,
            int overrides,
            uint failureCategory,
            string messageKey,
            float peakLeft,
            float peakRight,
            float cursorSeconds,
            float lengthSeconds,
            bool bgmPlaying,
            string decoderBackend,
            ulong preReadyDrops,
            ulong recoveryDrops,
            ulong staleGenerationDrops,
            ulong unknownIdCount,
            ulong throttledCount,
            ulong startFailureCount,
            ulong playedCount,
            IDictionary<string, int> sfxHandles,
            AudioCoordinatorQualificationStateV2 qualification = null)
        {
            Status = status;
            AudioSessionId = audioSessionId;
            AudioReadyGeneration = audioReadyGeneration;
            DeviceGeneration = deviceGeneration;
            NormalizedBasePath = normalizedBasePath;
            CapabilityDigest = capabilityDigest;
            Loaded = loaded;
            Failed = failed;
            Overrides = overrides;
            FailureCategory = failureCategory;
            MessageKey = messageKey;
            PeakLeft = peakLeft;
            PeakRight = peakRight;
            CursorSeconds = cursorSeconds;
            LengthSeconds = lengthSeconds;
            BgmPlaying = bgmPlaying;
            DecoderBackend = decoderBackend;
            PreReadyDrops = preReadyDrops;
            RecoveryDrops = recoveryDrops;
            StaleGenerationDrops = staleGenerationDrops;
            UnknownIdCount = unknownIdCount;
            ThrottledCount = throttledCount;
            StartFailureCount = startFailureCount;
            PlayedCount = playedCount;
            Backend = qualification == null
                ? AudioNativeV2.BackendNone
                : qualification.Backend;
            DeviceIdDigest = qualification == null
                ? null
                : qualification.DeviceIdDigest;
            DeviceName = qualification == null
                ? null
                : qualification.DeviceName;
            SampleRate = qualification == null
                ? 0u
                : qualification.SampleRate;
            Channels = qualification == null
                ? 0u
                : qualification.Channels;
            SampleFormat = qualification == null
                ? AudioNativeV2.SampleFormatUnknown
                : qualification.SampleFormat;
            SourceRequestId = qualification == null
                ? null
                : qualification.SourceRequestId;
            AudioNativeObservationV2 qualificationObservation =
                qualification == null ? null : qualification.Observation;
            CursorFrames = qualificationObservation == null
                ? 0uL
                : qualificationObservation.CursorFrames;
            LengthFrames = qualificationObservation == null
                ? 0uL
                : qualificationObservation.LengthFrames;
            Container = qualificationObservation == null
                ? "none"
                : qualificationObservation.Container;
            Codec = qualificationObservation == null
                ? "none"
                : qualificationObservation.Codec;
            StartCategory = qualificationObservation == null
                ? AudioNativeV2.ResultNotReady
                : qualificationObservation.StartCategory;
            BgmMeter = qualificationObservation == null
                ? AudioNativeMeterObservationV2.Empty
                : qualificationObservation.BgmMeter;
            SfxMeter = qualificationObservation == null
                ? AudioNativeMeterObservationV2.Empty
                : qualificationObservation.SfxMeter;
            _sfxHandles = new ReadOnlyDictionary<string, int>(
                new Dictionary<string, int>(
                    sfxHandles ?? new Dictionary<string, int>(),
                    StringComparer.Ordinal));
        }

        public AudioCoordinatorStatusV2 Status { get; private set; }
        public string AudioSessionId { get; private set; }
        public ulong AudioReadyGeneration { get; private set; }
        public ulong DeviceGeneration { get; private set; }
        public string NormalizedBasePath { get; private set; }
        public string CapabilityDigest { get; private set; }
        public int Loaded { get; private set; }
        public int Failed { get; private set; }
        public int Overrides { get; private set; }
        public uint FailureCategory { get; private set; }
        public string MessageKey { get; private set; }
        public float PeakLeft { get; private set; }
        public float PeakRight { get; private set; }
        public float CursorSeconds { get; private set; }
        public float LengthSeconds { get; private set; }
        public bool BgmPlaying { get; private set; }
        public string DecoderBackend { get; private set; }
        public ulong PreReadyDrops { get; private set; }
        public ulong RecoveryDrops { get; private set; }
        public ulong StaleGenerationDrops { get; private set; }
        public ulong UnknownIdCount { get; private set; }
        public ulong ThrottledCount { get; private set; }
        public ulong StartFailureCount { get; private set; }
        public ulong PlayedCount { get; private set; }
        public uint Backend { get; private set; }
        public string DeviceIdDigest { get; private set; }
        public string DeviceName { get; private set; }
        public uint SampleRate { get; private set; }
        public uint Channels { get; private set; }
        public uint SampleFormat { get; private set; }
        public string SourceRequestId { get; private set; }
        public ulong CursorFrames { get; private set; }
        public ulong LengthFrames { get; private set; }
        public string Container { get; private set; }
        public string Codec { get; private set; }
        public uint StartCategory { get; private set; }
        public AudioNativeMeterObservationV2 BgmMeter { get; private set; }
        public AudioNativeMeterObservationV2 SfxMeter { get; private set; }
        public ReadOnlyDictionary<string, int> SfxHandles
        {
            get { return _sfxHandles; }
        }

        public bool IsReady { get { return Status == AudioCoordinatorStatusV2.Ready; } }
        public bool IsSfxPreloadComplete { get { return IsReady; } }
    }

    /// <summary>
    /// Sole managed owner of Audio Platform v2 native state.
    ///
    /// All native calls, catalog replacement and recovery execute on one dedicated
    /// queue. Readers only observe immutable snapshots. Transport generations never
    /// enter this class; admission uses the audio session/ready tuple exclusively.
    /// </summary>
    internal sealed class AudioCoordinator : IAudioCommandFacadeV2, IDisposable
    {
        private const int RuntimePollIntervalMilliseconds = 200;
        private const int DeviceRecoveryMaximumAttempts = 5;
        private static readonly int[] DeviceRecoveryBackoffPollTicks =
            { 1, 2, 4, 8 };
        private static readonly string[] SfxPackOrder =
            { "武器", "特效", "人物" };

        private readonly IAudioNativeV2 _native;
        private readonly AudioPreloadHookV2 _preloadHook;
        private readonly AudioCatalogHookV2 _catalogHook;
        private readonly BlockingCollection<OwnerWorkItem> _ownerQueue;
        private readonly CancellationTokenSource _lifetime;
        private readonly Thread _ownerThread;
        private readonly Timer _runtimePollTimer;
        private readonly object _admissionLock = new object();
        private readonly ManualResetEventSlim _shutdownComplete =
            new ManualResetEventSlim(false);
        private readonly ManualResetEventSlim _nativeShutdownFenceComplete =
            new ManualResetEventSlim(false);

        private AudioCoordinatorSnapshotV2 _snapshot;
        private bool _accepting = true;
        private bool _shutdownStarted;
        private bool _nativeTouched;
        private int _ownerThreadId;
        private int _runtimePollQueued;
        private int _deviceRecoveryActive;
        private int _deviceRecoveryAttempt;
        private int _deviceRecoveryBackoffTicks;
        private string _audioSessionId;
        private ulong _audioReadyGeneration;
        private ulong _deviceGeneration;
        private uint _backend;
        private string _deviceIdDigest;
        private string _deviceName;
        private uint _sampleRate;
        private uint _channels;
        private uint _sampleFormat;
        private AudioNativeObservationV2 _lastQualificationObservation;
        private string _normalizedBasePath;
        private string _capabilityDigest;
        private AudioPreloadResultV2 _catalog;
        private Dictionary<string, int> _handleById =
            new Dictionary<string, int>(StringComparer.Ordinal);
        private Dictionary<int, AudioCatalogItemV2> _itemByHandle =
            new Dictionary<int, AudioCatalogItemV2>();
        private int _nextHandle = 1;
        private long _legacyRequestSequence;
        private ulong _legacyBatchSequence;
        private ulong _preReadyDrops;
        private ulong _recoveryDrops;
        private ulong _staleGenerationDrops;
        private ulong _unknownIdCount;
        private ulong _throttledCount;
        private ulong _startFailureCount;
        private ulong _playedCount;
        private AudioNativeSfxCountersV2 _lastNativeSfxCounters;
        private bool _hasEnteredReady;
        private bool _bootstrapGateArmed;
        private PendingBgm _bootstrapPending;
        private AudioNativeBgmCommandV2 _latestBgmIntent;
        private bool _latestBgmPaused;
        private AudioNativeBgmCommandV2 _pendingRecoveryIntent;
        private bool _pendingRecoveryPaused;
        private AudioCatalogQualificationHookV2 _catalogQualificationHook;
        private bool _catalogQualificationPending;
        private float _initialMasterGain = 1f;

        internal event Action<AudioCoordinatorSnapshotV2> SnapshotChanged;

        internal AudioCoordinator()
            : this(
                new AudioNativeV2Adapter(),
                ScanDefaultCatalog,
                NoopCatalogHook)
        {
        }

        internal AudioCoordinator(
            IAudioNativeV2 native,
            AudioPreloadHookV2 preloadHook,
            AudioCatalogHookV2 catalogHook)
            : this(native, preloadHook, catalogHook, true)
        {
        }

        internal AudioCoordinator(
            IAudioNativeV2 native,
            AudioPreloadHookV2 preloadHook,
            AudioCatalogHookV2 catalogHook,
            bool enableRuntimePolling)
        {
            if (native == null) throw new ArgumentNullException("native");
            if (preloadHook == null) throw new ArgumentNullException("preloadHook");
            if (catalogHook == null) throw new ArgumentNullException("catalogHook");

            _native = native;
            _preloadHook = preloadHook;
            _catalogHook = catalogHook;
            _ownerQueue = new BlockingCollection<OwnerWorkItem>(
                new ConcurrentQueue<OwnerWorkItem>());
            _lifetime = new CancellationTokenSource();
            _audioSessionId = NewSessionId();
            _snapshot = CreateSnapshot(
                AudioCoordinatorStatusV2.Unavailable,
                AudioNativeV2.ResultNotReady,
                "audio.not_ready",
                null);
            _ownerThread = new Thread(OwnerLoop);
            _ownerThread.IsBackground = true;
            _ownerThread.Name = "CF7 AudioCoordinator v2 owner";
            _ownerThread.Start();
            _runtimePollTimer = new Timer(
                RuntimePollTick,
                null,
                enableRuntimePolling
                    ? RuntimePollIntervalMilliseconds
                    : Timeout.Infinite,
                enableRuntimePolling
                    ? RuntimePollIntervalMilliseconds
                    : Timeout.Infinite);
        }

        internal AudioCoordinatorSnapshotV2 Snapshot
        {
            get { return Volatile.Read(ref _snapshot); }
        }

        internal bool Initialize(string projectRoot)
        {
            string normalizedRoot;
            if (!TryNormalizeRoot(projectRoot, out normalizedRoot)) return false;
            return InvokeOwner(
                delegate
                {
                    if (IsDeviceRecoveryActive()) return false;
                    return RebuildCore(normalizedRoot, false);
                },
                false);
        }

        internal bool BeginInitialize(string projectRoot)
        {
            string normalizedRoot;
            if (!TryNormalizeRoot(projectRoot, out normalizedRoot)) return false;
            return TryPost(delegate
            {
                if (!IsDeviceRecoveryActive())
                    RebuildCore(normalizedRoot, false);
            });
        }

        internal bool ConfigureInitialMasterGain(float gain)
        {
            if (!IsFiniteGain(gain)) return false;
            lock (_admissionLock)
            {
                if (_nativeTouched || _shutdownStarted) return false;
                _initialMasterGain = gain;
                return true;
            }
        }

        internal bool ConfigureCatalogQualificationHook(
            AudioCatalogQualificationHookV2 hook)
        {
            if (hook == null) return false;
            lock (_admissionLock)
            {
                if (_nativeTouched || _shutdownStarted) return false;
                _catalogQualificationHook = hook;
                return true;
            }
        }

        internal bool BeginCatalogRefreshRebuild(string capabilityDigest)
        {
            return InvokeOwner(
                delegate
                {
                    if (IsDeviceRecoveryActive()) return false;
                    AudioCoordinatorSnapshotV2 current = Snapshot;
                    bool maySupersedePending =
                        _catalogQualificationPending &&
                        (current.Status == AudioCoordinatorStatusV2.Initializing ||
                         current.Status == AudioCoordinatorStatusV2.Recovering);
                    if ((!current.IsReady && !maySupersedePending) ||
                        string.IsNullOrEmpty(_normalizedBasePath) ||
                        _deviceGeneration == 0uL ||
                        string.IsNullOrEmpty(_capabilityDigest) ||
                        !string.Equals(
                            capabilityDigest,
                            _capabilityDigest,
                            StringComparison.OrdinalIgnoreCase))
                    {
                        return false;
                    }

                    // Native validates the ready generation as well as the managed
                    // admission gate.  A hot catalog refresh therefore has to rebuild
                    // the native epoch; advancing only the managed generation would
                    // make every command in the new epoch stale at the ABI boundary.
                    ulong previousReadyGeneration = _audioReadyGeneration;
                    CaptureRecoveryCursor();
                    BeginDeviceRecoverySequenceCore();
                    AudioCoordinatorSnapshotV2 rebuilt = Snapshot;
                    return _catalogQualificationPending &&
                        rebuilt.AudioReadyGeneration != previousReadyGeneration &&
                        rebuilt.Status == AudioCoordinatorStatusV2.Recovering &&
                        string.Equals(
                            rebuilt.MessageKey,
                            "audio.catalog_qualifying",
                            StringComparison.Ordinal);
                },
                false);
        }

        internal bool CompleteCatalogQualification(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            string capabilityDigest,
            bool succeeded)
        {
            return InvokeOwner(
                delegate
                {
                    if (!_catalogQualificationPending ||
                        !string.Equals(
                            audioSessionId,
                            _audioSessionId,
                            StringComparison.Ordinal) ||
                        audioReadyGeneration != _audioReadyGeneration ||
                        deviceGeneration != _deviceGeneration ||
                        !string.Equals(
                            capabilityDigest,
                            _capabilityDigest,
                            StringComparison.OrdinalIgnoreCase))
                    {
                        return false;
                    }

                    AudioNativeBgmCommandV2 recoveryIntent =
                        _pendingRecoveryIntent;
                    bool recoveryPaused = _pendingRecoveryPaused;
                    _catalogQualificationPending = false;
                    _pendingRecoveryIntent = null;
                    _pendingRecoveryPaused = false;
                    if (!succeeded)
                    {
                        return PublishUnavailable(
                            null,
                            AudioNativeV2.ResultInternalError,
                            "audio.catalog_qualification_failed");
                    }

                    bool recoveryRequired;
                    if (!TryInspectNativeRecoveryStateCore(
                            out recoveryRequired))
                    {
                        return false;
                    }
                    if (recoveryRequired)
                    {
                        // A device notification can arrive while the newly
                        // initialized catalog is being qualified. Do not publish
                        // a transient Ready snapshot or replay BGM against a
                        // native epoch that has already entered Recovering.
                        if (IsDeviceRecoveryActive())
                        {
                            return PublishDeviceRecoveryAttemptFailure(
                                CreateRuntimeFailure(
                                    AudioNativeV2.ResultDeviceLost,
                                    "audio.device_lost"));
                        }
                        CaptureRecoveryCursor();
                        return BeginDeviceRecoverySequenceCore();
                    }

                    if (recoveryIntent != null)
                    {
                        AudioNativeBgmCommandV2 replay = RebindBgmIntent(
                            recoveryIntent,
                            _audioSessionId,
                            _audioReadyGeneration);
                        AudioNativeCallResultV2 replayResult =
                            ExecuteRecoveryBgmCore(replay, recoveryPaused);
                        if (replayResult == null || !replayResult.IsOk)
                            return false;
                    }
                    Publish(CreateSnapshot(
                        AudioCoordinatorStatusV2.Ready,
                        AudioNativeV2.ResultOk,
                        "audio.ready",
                        null));
                    EndDeviceRecoverySequenceCore();
                    return true;
                },
                false);
        }

        internal bool RecoverDevice()
        {
            return InvokeOwner(
                delegate
                {
                    if (string.IsNullOrEmpty(_normalizedBasePath)) return false;
                    if (IsDeviceRecoveryActive()) return false;
                    CaptureRecoveryCursor();
                    return BeginDeviceRecoverySequenceCore();
                },
                false);
        }

        internal bool PollNativeRuntimeOnce()
        {
            return InvokeOwner(RuntimePollOwnerTick, false);
        }

        private void RuntimePollTick(object state)
        {
            AudioCoordinatorSnapshotV2 current = Snapshot;
            bool recoveryTick =
                current.Status == AudioCoordinatorStatusV2.Recovering &&
                Volatile.Read(ref _deviceRecoveryActive) != 0 &&
                !string.Equals(
                    current.MessageKey,
                    "audio.catalog_qualifying",
                    StringComparison.Ordinal);
            if ((!current.IsReady && !recoveryTick) ||
                Interlocked.Exchange(ref _runtimePollQueued, 1) != 0)
            {
                return;
            }

            bool posted = TryPost(delegate
            {
                try
                {
                    RuntimePollOwnerTick();
                }
                finally
                {
                    Volatile.Write(ref _runtimePollQueued, 0);
                }
            });
            if (!posted)
            {
                Volatile.Write(ref _runtimePollQueued, 0);
            }
        }

        private bool RuntimePollOwnerTick()
        {
            if (IsDeviceRecoveryActive())
                return ContinueDeviceRecoverySequenceCore();
            return PollNativeRuntimeCore();
        }

        private bool PollNativeRuntimeCore()
        {
            AudioCoordinatorSnapshotV2 current = Snapshot;
            if (!current.IsReady || !_nativeTouched ||
                string.IsNullOrEmpty(_normalizedBasePath))
            {
                return false;
            }

            AudioNativeRuntimeStateV2 runtime;
            try
            {
                runtime = _native.QueryRuntime();
            }
            catch
            {
                PublishUnavailable(
                    null,
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.runtime_query_failed");
                return false;
            }
            if (runtime == null || !runtime.Valid)
            {
                PublishUnavailable(
                    runtime == null ? null : runtime.Result,
                    AudioNativeV2.ResultAbiMismatch,
                    "audio.runtime_snapshot_invalid");
                return false;
            }
            if (!string.Equals(
                    runtime.AudioSessionId,
                    _audioSessionId,
                    StringComparison.Ordinal) ||
                runtime.AudioReadyGeneration != _audioReadyGeneration)
            {
                PublishUnavailable(
                    runtime.Result,
                    AudioNativeV2.ResultStaleGeneration,
                    "audio.runtime_tuple_drift");
                return false;
            }

            AdoptRuntimeMetadata(runtime);

            bool recoveryRequired =
                runtime.AudioStatus == AudioNativeV2.AudioRecovering ||
                (runtime.AudioStatus == AudioNativeV2.AudioReady &&
                 runtime.DeviceGeneration != _deviceGeneration);
            if (!recoveryRequired)
            {
                if (runtime.AudioStatus != AudioNativeV2.AudioReady)
                {
                    PublishUnavailable(
                        runtime.Result,
                        AudioNativeV2.ResultDeviceUnavailable,
                        "audio.native_not_ready");
                }
                return false;
            }

            CaptureRecoveryCursor(runtime.DeviceGeneration);
            BeginDeviceRecoverySequenceCore();
            return true;
        }

        private bool TryInspectNativeRecoveryStateCore(
            out bool recoveryRequired)
        {
            recoveryRequired = false;
            if (!_nativeTouched)
            {
                PublishUnavailable(
                    CreateRuntimeFailure(
                        AudioNativeV2.ResultDeviceUnavailable,
                        "audio.runtime_query_failed"),
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.runtime_query_failed");
                return false;
            }

            AudioNativeRuntimeStateV2 runtime;
            try
            {
                runtime = _native.QueryRuntime();
            }
            catch
            {
                PublishUnavailable(
                    CreateRuntimeFailure(
                        AudioNativeV2.ResultDeviceUnavailable,
                        "audio.runtime_query_failed"),
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.runtime_query_failed");
                return false;
            }
            if (runtime == null || !runtime.Valid)
            {
                PublishUnavailable(
                    CreateRuntimeFailure(
                        AudioNativeV2.ResultAbiMismatch,
                        "audio.runtime_snapshot_invalid"),
                    AudioNativeV2.ResultAbiMismatch,
                    "audio.runtime_snapshot_invalid");
                return false;
            }
            if (!string.Equals(
                    runtime.AudioSessionId,
                    _audioSessionId,
                    StringComparison.Ordinal) ||
                runtime.AudioReadyGeneration != _audioReadyGeneration)
            {
                PublishUnavailable(
                    CreateRuntimeFailure(
                        AudioNativeV2.ResultStaleGeneration,
                        "audio.runtime_tuple_drift"),
                    AudioNativeV2.ResultStaleGeneration,
                    "audio.runtime_tuple_drift");
                return false;
            }

            ulong expectedDeviceGeneration = _deviceGeneration;
            AdoptRuntimeMetadata(runtime);
            recoveryRequired =
                runtime.AudioStatus == AudioNativeV2.AudioRecovering ||
                (runtime.AudioStatus == AudioNativeV2.AudioReady &&
                 runtime.DeviceGeneration != expectedDeviceGeneration);
            if (recoveryRequired) return true;
            if (runtime.AudioStatus == AudioNativeV2.AudioReady) return true;

            PublishUnavailable(
                CreateRuntimeFailure(
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.native_not_ready"),
                AudioNativeV2.ResultDeviceUnavailable,
                "audio.native_not_ready");
            return false;
        }

        private bool BeginDeviceRecoverySequenceCore()
        {
            if (IsDeviceRecoveryActive() ||
                string.IsNullOrEmpty(_normalizedBasePath) ||
                _shutdownStarted)
            {
                return false;
            }

            _deviceRecoveryAttempt = 0;
            _deviceRecoveryBackoffTicks = 0;
            Volatile.Write(ref _deviceRecoveryActive, 1);
            return RunDeviceRecoveryAttemptCore();
        }

        private bool ContinueDeviceRecoverySequenceCore()
        {
            if (!IsDeviceRecoveryActive() || _shutdownStarted ||
                _catalogQualificationPending)
            {
                return false;
            }
            if (_deviceRecoveryBackoffTicks > 0)
            {
                _deviceRecoveryBackoffTicks--;
                if (_deviceRecoveryBackoffTicks > 0) return false;
            }
            return RunDeviceRecoveryAttemptCore();
        }

        private bool RunDeviceRecoveryAttemptCore()
        {
            if (!IsDeviceRecoveryActive() || _shutdownStarted ||
                _deviceRecoveryAttempt >= DeviceRecoveryMaximumAttempts)
            {
                return false;
            }
            _deviceRecoveryAttempt++;
            return RebuildCore(
                _normalizedBasePath,
                true,
                _deviceRecoveryAttempt == 1);
        }

        private bool PublishDeviceRecoveryAttemptFailure(
            AudioNativeCallResultV2 failure)
        {
            uint category = failure == null
                ? AudioNativeV2.ResultDeviceUnavailable
                : failure.Category;
            if (category == AudioNativeV2.ResultOk)
                category = AudioNativeV2.ResultDeviceUnavailable;
            bool retryable = IsRetryableDeviceFailure(failure);
            if (!retryable || !IsDeviceRecoveryActive() ||
                _deviceRecoveryAttempt >= DeviceRecoveryMaximumAttempts)
            {
                return PublishUnavailable(
                    failure,
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.device_unavailable");
            }

            _catalogQualificationPending = false;
            _pendingRecoveryIntent = null;
            _pendingRecoveryPaused = false;
            if (_nativeTouched) BestEffortNativeShutdown();
            _deviceRecoveryBackoffTicks =
                DeviceRecoveryBackoffPollTicks[_deviceRecoveryAttempt - 1];
            Publish(CreateSnapshot(
                AudioCoordinatorStatusV2.Recovering,
                category,
                SafeMessageKey(failure, "audio.device_unavailable"),
                null));
            return false;
        }

        private AudioNativeCallResultV2 CreateRuntimeFailure(
            uint category,
            string messageKey)
        {
            return AudioNativeCallResultV2.Failure(
                category,
                AudioNativeV2.OperationQueryRuntime,
                AudioNativeV2.StageAdmission,
                _audioSessionId,
                _audioReadyGeneration,
                _deviceGeneration,
                messageKey);
        }

        private static bool IsRetryableDeviceFailure(
            AudioNativeCallResultV2 failure)
        {
            return failure != null &&
                (failure.Category == AudioNativeV2.ResultDeviceUnavailable ||
                 failure.Category == AudioNativeV2.ResultDeviceLost);
        }

        private bool IsDeviceRecoveryActive()
        {
            return Volatile.Read(ref _deviceRecoveryActive) != 0;
        }

        private void EndDeviceRecoverySequenceCore()
        {
            _deviceRecoveryAttempt = 0;
            _deviceRecoveryBackoffTicks = 0;
            Volatile.Write(ref _deviceRecoveryActive, 0);
        }

        private void CaptureRecoveryCursor()
        {
            CaptureRecoveryCursor(_deviceGeneration);
        }

        private void CaptureRecoveryCursor(ulong observedDeviceGeneration)
        {
            if (_latestBgmIntent == null || observedDeviceGeneration == 0uL)
                return;
            AudioNativeObservationV2 observation;
            try
            {
                observation = _native.QueryBgmRecoveryObservation(
                    _audioSessionId,
                    _audioReadyGeneration,
                    observedDeviceGeneration);
            }
            catch
            {
                return;
            }
            if (observation == null || !observation.Valid ||
                float.IsNaN(observation.CursorSeconds) ||
                float.IsInfinity(observation.CursorSeconds) ||
                observation.CursorSeconds < 0f)
            {
                return;
            }

            _latestBgmIntent = new AudioNativeBgmCommandV2(
                _latestBgmIntent.RequestId,
                _latestBgmIntent.AudioSessionId,
                _latestBgmIntent.AudioReadyGeneration,
                _latestBgmIntent.Operation,
                _latestBgmIntent.NormalizedPath,
                _latestBgmIntent.Loop,
                _latestBgmIntent.Volume,
                _latestBgmIntent.FadeSeconds,
                observation.CursorSeconds);
        }

        internal int EnsurePreloaded(string projectRoot)
        {
            AudioCoordinatorSnapshotV2 current = Snapshot;
            string normalizedRoot;
            if (!TryNormalizeRoot(projectRoot, out normalizedRoot)) return 0;
            if (current.IsReady && string.Equals(
                current.NormalizedBasePath,
                normalizedRoot,
                StringComparison.OrdinalIgnoreCase))
            {
                return current.Loaded;
            }
            return Initialize(normalizedRoot) ? Snapshot.Loaded : 0;
        }

        internal int ResolveSfxHandle(string linkageId)
        {
            int handle;
            if (string.IsNullOrEmpty(linkageId)) return -1;
            return Snapshot.SfxHandles.TryGetValue(linkageId, out handle)
                ? handle
                : -1;
        }

        internal int LegacySfxLoad(string path)
        {
            return InvokeOwner(
                delegate { return LegacySfxLoadCore(path); },
                -1);
        }

        internal int LegacySfxPlay(int handle, float volume)
        {
            return InvokeOwner(
                delegate
                {
                    AudioCatalogItemV2 item;
                    if (!IsFiniteGain(volume) ||
                        !_itemByHandle.TryGetValue(handle, out item))
                    {
                        IncrementCounter(ref _unknownIdCount);
                        PublishCountersOnly();
                        return -1;
                    }
                    ulong batchSequence = NextBatchSequence();
                    if (!Snapshot.IsReady)
                    {
                        AddAdmissionDrop(Snapshot, 1uL);
                        PublishCountersOnly();
                        return -1;
                    }
                    var ids = new List<string> { item.LinkageId };
                    AudioNativeCallResultV2 result;
                    try
                    {
                        result = _native.SubmitSfxBatch(
                            _audioSessionId,
                            _audioReadyGeneration,
                            batchSequence,
                            ids,
                            volume);
                    }
                    catch
                    {
                        PublishUnavailable(
                            null,
                            AudioNativeV2.ResultDeviceUnavailable,
                            "audio.native_unavailable");
                        return -1;
                    }
                    ApplySfxResult(result, 1);
                    return LegacyReturnCode(result);
                },
                -1);
        }

        internal void LegacySfxUnload(int handle)
        {
            InvokeOwner(
                delegate
                {
                    AudioCatalogItemV2 removed;
                    if (!_itemByHandle.TryGetValue(handle, out removed)) return 0;
                    _itemByHandle.Remove(handle);
                    _handleById.Remove(removed.LinkageId);
                    RebuildNativeCatalogFromHandles();
                    PublishCountersOnly();
                    return 0;
                },
                0);
        }

        internal int LegacyBgmPlay(
            string path,
            int loop,
            float volume,
            float fadeSeconds)
        {
            return InvokeOwner(
                delegate
                {
                    AudioNativeBgmCommandV2 command;
                    if (!TryBuildLegacyBgmCommand(
                        AudioNativeV2.OperationBgmPlay,
                        path,
                        loop != 0,
                        volume,
                        fadeSeconds,
                        0f,
                        out command))
                    {
                        return -1;
                    }
                    return LegacyReturnCode(ExecuteBgmCore(command, true));
                },
                -1);
        }

        /// <summary>
        /// Acquires the one fixed launcher-frontdoor BGM intent.  The request id is
        /// the ownership fence: repeating the exact intent in the same process is
        /// idempotent, while any later AS2 request naturally supersedes it.
        /// </summary>
        internal bool TryAcquireFrontdoorBgm(
            string requestId,
            string path,
            bool loop,
            float volume,
            float fadeSeconds)
        {
            if (!IsFrontdoorBgmRequestId(requestId)) return false;
            return InvokeOwner(
                delegate
                {
                    if (!Snapshot.IsReady ||
                        !IsFiniteGain(volume) ||
                        !IsFiniteRange(fadeSeconds, 0f, 60f))
                    {
                        return false;
                    }

                    string normalizedPath;
                    if (!TryNormalizeMediaPath(path, out normalizedPath))
                        return false;

                    if (_latestBgmIntent != null && string.Equals(
                            _latestBgmIntent.RequestId,
                            requestId,
                            StringComparison.Ordinal))
                    {
                        // A stable lease id must never be reused with a different
                        // payload.  Exact repeats are no-ops and do not restart the
                        // track after a duplicate Ready projection.
                        return _latestBgmIntent.Operation ==
                                AudioNativeV2.OperationBgmPlay &&
                            string.Equals(
                                _latestBgmIntent.NormalizedPath,
                                normalizedPath,
                                StringComparison.OrdinalIgnoreCase) &&
                            _latestBgmIntent.Loop == loop &&
                            _latestBgmIntent.Volume == volume &&
                            _latestBgmIntent.FadeSeconds == fadeSeconds;
                    }

                    var command = new AudioNativeBgmCommandV2(
                        requestId,
                        _audioSessionId,
                        _audioReadyGeneration,
                        AudioNativeV2.OperationBgmPlay,
                        normalizedPath,
                        loop,
                        volume,
                        fadeSeconds,
                        0f);
                    AudioNativeCallResultV2 result =
                        ExecuteBgmCore(command, true);
                    return result != null && result.IsOk;
                },
                false);
        }

        /// <summary>
        /// Revokes only this launcher's frontdoor request.  It clears both the live
        /// remembered intent and a qualification-delayed recovery replay.  If AS2
        /// has already superseded the request, this method deliberately sends no
        /// native stop and cannot silence gameplay BGM.
        /// </summary>
        internal bool RevokeFrontdoorBgm(
            string requestId,
            float fadeSeconds)
        {
            if (!IsFrontdoorBgmRequestId(requestId) ||
                !IsFiniteRange(fadeSeconds, 0f, 60f))
            {
                return false;
            }

            return InvokeOwner(
                delegate
                {
                    bool ownsLatest = HasRequestId(
                        _latestBgmIntent,
                        requestId);
                    if (HasRequestId(_pendingRecoveryIntent, requestId))
                    {
                        _pendingRecoveryIntent = null;
                        _pendingRecoveryPaused = false;
                    }

                    if (!ownsLatest)
                    {
                        // Already revoked or superseded.  This is an idempotent
                        // success, but never a license to stop another owner.
                        return true;
                    }

                    _latestBgmIntent = null;
                    _latestBgmPaused = false;
                    if (!Snapshot.IsReady)
                    {
                        // Recovering/qualifying has no current native source that
                        // this lease can safely address. Clearing both remembered
                        // intents is the durable revoke and prevents resurrection.
                        return true;
                    }

                    var stop = new AudioNativeBgmCommandV2(
                        requestId,
                        _audioSessionId,
                        _audioReadyGeneration,
                        AudioNativeV2.OperationBgmStop,
                        null,
                        false,
                        0f,
                        fadeSeconds,
                        0f);
                    AudioNativeCallResultV2 result =
                        ExecuteBgmCore(stop, false);
                    return result != null && result.IsOk;
                },
                false);
        }

        internal int LegacyBgmControl(
            uint operation,
            float scalar,
            int booleanValue)
        {
            return InvokeOwner(
                delegate
                {
                    AudioNativeBgmCommandV2 command;
                    float fade = operation == AudioNativeV2.OperationBgmStop
                        ? scalar
                        : 0f;
                    float seek = operation == AudioNativeV2.OperationBgmSeek
                        ? scalar
                        : 0f;
                    if (!TryBuildLegacyBgmCommand(
                        operation,
                        null,
                        booleanValue != 0,
                        1f,
                        fade,
                        seek,
                        out command))
                    {
                        return -1;
                    }
                    return LegacyReturnCode(ExecuteBgmCore(command, true));
                },
                -1);
        }

        internal void LegacySetGain(uint operation, float gain)
        {
            if (!IsFiniteGain(gain)) return;
            InvokeOwner(
                delegate
                {
                    if (!Snapshot.IsReady) return 0;
                    try
                    {
                        _native.SetGain(
                            _audioSessionId,
                            _audioReadyGeneration,
                            operation,
                            gain);
                    }
                    catch
                    {
                        PublishUnavailable(
                            null,
                            AudioNativeV2.ResultDeviceUnavailable,
                            "audio.native_unavailable");
                    }
                    return 0;
                },
                0);
        }

        internal AudioCoordinatorSnapshotV2 RefreshObservation()
        {
            return InvokeOwner(
                delegate
                {
                    if (!Snapshot.IsReady) return Snapshot;
                    AudioNativeObservationV2 observation;
                    try
                    {
                        observation = _native.QueryBgmObservation(
                            _audioSessionId,
                            _audioReadyGeneration,
                            _deviceGeneration);
                    }
                    catch
                    {
                        PublishUnavailable(
                            null,
                            AudioNativeV2.ResultDeviceUnavailable,
                            "audio.native_unavailable");
                        return Snapshot;
                    }
                    if (observation != null && observation.Valid)
                    {
                        PublishObservation(observation);
                    }
                    return Snapshot;
                },
                Snapshot);
        }

        internal AudioCoordinatorSnapshotV2 CaptureQualificationSnapshot()
        {
            return InvokeOwner(
                delegate
                {
                    if (!Snapshot.IsReady) return Snapshot;

                    AudioNativeRuntimeStateV2 runtime;
                    AudioNativeObservationV2 observation;
                    try
                    {
                        runtime = _native.QueryRuntime();
                        if (runtime == null || !runtime.Valid ||
                            !string.Equals(
                                runtime.AudioSessionId,
                                _audioSessionId,
                                StringComparison.Ordinal) ||
                            runtime.AudioReadyGeneration !=
                                _audioReadyGeneration ||
                            runtime.DeviceGeneration != _deviceGeneration)
                        {
                            return Snapshot;
                        }
                        AdoptRuntimeMetadata(runtime);
                        IAudioNativeQualificationObservationV2
                            qualificationNative = _native as
                                IAudioNativeQualificationObservationV2;
                        observation = qualificationNative == null
                            ? _native.QueryBgmObservation(
                                _audioSessionId,
                                _audioReadyGeneration,
                                _deviceGeneration)
                            : qualificationNative.QueryQualificationObservation(
                                _audioSessionId,
                                _audioReadyGeneration,
                                _deviceGeneration);
                    }
                    catch
                    {
                        return Snapshot;
                    }

                    if (observation != null && observation.Valid)
                    {
                        if (observation.SfxCounters != null)
                            TryApplyNativeSfxCounters(
                                observation.SfxCounters);
                        PublishObservation(observation);
                    }
                    return Snapshot;
                },
                Snapshot);
        }

        internal AudioRuntimeProbeResultV2 ProbeRuntimeCompatibility(
            string normalizedPath,
            ulong fileSizeBytes,
            long modifiedTimeUnixMilliseconds,
            string first64kSha256,
            string capabilityDigestSha256)
        {
            return InvokeOwner(
                delegate
                {
                    AudioCoordinatorSnapshotV2 current = Snapshot;
                    bool catalogQualificationProbe =
                        _catalogQualificationPending &&
                        (current.Status ==
                            AudioCoordinatorStatusV2.Initializing ||
                         current.Status ==
                            AudioCoordinatorStatusV2.Recovering) &&
                        current.AudioReadyGeneration ==
                            _audioReadyGeneration &&
                        current.DeviceGeneration == _deviceGeneration &&
                        string.Equals(
                            current.CapabilityDigest,
                            _capabilityDigest,
                            StringComparison.OrdinalIgnoreCase);
                    if (!current.IsReady && !catalogQualificationProbe)
                    {
                        return new AudioRuntimeProbeResultV2(
                            false,
                            AudioNativeV2.ProbeOutcomeNone,
                            0uL,
                            0d,
                            0d,
                            0d,
                            0u,
                            0uL,
                            AudioNativeCallResultV2.Failure(
                                AudioNativeV2.ResultNotReady,
                                AudioNativeV2.OperationRuntimeProbe,
                                AudioNativeV2.StageAdmission,
                                current.AudioSessionId,
                                current.AudioReadyGeneration,
                                current.DeviceGeneration,
                                "audio.probe_not_ready"));
                    }
                    try
                    {
                        return _native.ProbeRuntimeCompatibility(
                            normalizedPath,
                            fileSizeBytes,
                            modifiedTimeUnixMilliseconds,
                            first64kSha256,
                            capabilityDigestSha256,
                            current.AudioSessionId,
                            current.AudioReadyGeneration);
                    }
                    catch
                    {
                        return new AudioRuntimeProbeResultV2(
                            false,
                            AudioNativeV2.ProbeOutcomeNone,
                            0uL,
                            0d,
                            0d,
                            0d,
                            0u,
                            0uL,
                            AudioNativeCallResultV2.Failure(
                                AudioNativeV2.ResultInternalError,
                                AudioNativeV2.OperationRuntimeProbe,
                                AudioNativeV2.StageProbeDecode,
                                current.AudioSessionId,
                                current.AudioReadyGeneration,
                                current.DeviceGeneration,
                                "audio.probe_exception"));
                    }
                },
                new AudioRuntimeProbeResultV2(
                    false,
                    AudioNativeV2.ProbeOutcomeNone,
                    0uL,
                    0d,
                    0d,
                    0d,
                    0u,
                    0uL,
                    null));
        }

        public void DispatchBgm(
            AudioBgmRequestV2 request,
            Action<AudioBgmResultV2> respond)
        {
            if (request == null) return;
            AudioCoordinatorSnapshotV2 observed = Snapshot;
            if (!MatchesTuple(request.AudioSessionId,
                request.AudioReadyGeneration,
                observed))
            {
                SafeRespond(respond, StaleResult(request, observed));
                return;
            }
            if (!observed.IsReady)
            {
                SafeRespond(respond, UnavailableResult(request, observed));
                return;
            }

            if (!TryPost(delegate { DispatchBgmOnOwner(request, respond); }))
            {
                SafeRespond(respond, UnavailableResult(request, Snapshot));
            }
        }

        public void RejectBgm(string protocolError)
        {
        }

        public void DispatchSfx(AudioSfxBatchV2 batch)
        {
            if (batch == null) return;
            ulong eventCount = (ulong)batch.LinkageIds.Count;
            AudioCoordinatorSnapshotV2 observed = Snapshot;
            if (!MatchesTuple(batch.AudioSessionId,
                batch.AudioReadyGeneration,
                observed))
            {
                TryPost(delegate
                {
                    AddCounter(ref _staleGenerationDrops, eventCount);
                    PublishCountersOnly();
                });
                return;
            }
            if (!observed.IsReady)
            {
                TryPost(delegate
                {
                    AddAdmissionDrop(observed, eventCount);
                    PublishCountersOnly();
                });
                return;
            }

            TryPost(delegate { DispatchSfxOnOwner(batch); });
        }

        public void RejectSfx(string protocolError)
        {
        }

        public void ArmBootstrapBgmGate()
        {
            TryPost(delegate { _bootstrapGateArmed = true; });
        }

        public void CancelBootstrapBgmGate()
        {
            TryPost(delegate
            {
                SupersedeBootstrapPending();
                _bootstrapGateArmed = false;
            });
        }

        public void ReleaseBootstrapBgmGate()
        {
            TryPost(delegate
            {
                PendingBgm pending = _bootstrapPending;
                _bootstrapPending = null;
                _bootstrapGateArmed = false;
                if (pending != null)
                {
                    DispatchBgmOnOwner(pending.Request, pending.Respond);
                }
            });
        }

        public void Shutdown()
        {
            bool initiator = false;
            lock (_admissionLock)
            {
                if (!_shutdownStarted)
                {
                    _shutdownStarted = true;
                    _accepting = false;
                    initiator = true;
                    _runtimePollTimer.Change(
                        Timeout.Infinite,
                        Timeout.Infinite);
                    _lifetime.Cancel();
                    _ownerQueue.Add(new OwnerWorkItem(
                        ShutdownOnOwner,
                        true,
                        null));
                    _ownerQueue.CompleteAdding();
                }
            }

            if (!initiator)
            {
                if (Thread.CurrentThread.ManagedThreadId != _ownerThreadId)
                {
                    _shutdownComplete.Wait();
                }
                return;
            }

            RunNativeShutdownFence();
            if (Thread.CurrentThread.ManagedThreadId != _ownerThreadId)
            {
                _ownerThread.Join();
                _shutdownComplete.Wait();
            }
            _runtimePollTimer.Dispose();
        }

        public void Dispose()
        {
            Shutdown();
        }

        private bool RebuildCore(
            string normalizedRoot,
            bool recovery,
            bool advanceReadyGeneration = true)
        {
            CancellationToken cancellationToken = _lifetime.Token;
            ulong previousDeviceGeneration = _deviceGeneration;
            AudioNativeBgmCommandV2 recoveryIntent = recovery
                ? _latestBgmIntent
                : null;
            bool recoveryPaused = recovery && recoveryIntent != null &&
                _latestBgmPaused;
            try
            {
                cancellationToken.ThrowIfCancellationRequested();
                _catalogQualificationPending = false;
                _pendingRecoveryIntent = null;
                _pendingRecoveryPaused = false;
                if (!recovery && !string.IsNullOrEmpty(_normalizedBasePath))
                {
                    EndDeviceRecoverySequenceCore();
                    BestEffortNativeShutdown();
                    _audioSessionId = NewSessionId();
                    _audioReadyGeneration = 0;
                    _deviceGeneration = 0;
                    ResetCountersAndCatalog();
                    recoveryIntent = null;
                    recoveryPaused = false;
                }

                if (advanceReadyGeneration) AdvanceReadyGeneration();
                _normalizedBasePath = normalizedRoot;
                Publish(CreateSnapshot(
                    recovery
                        ? AudioCoordinatorStatusV2.Recovering
                        : AudioCoordinatorStatusV2.Initializing,
                    AudioNativeV2.ResultNotReady,
                    recovery ? "audio.recovering" : "audio.initializing",
                    null));

                _nativeTouched = true;
                AudioNativeCapabilityResultV2 capability =
                    _native.QueryCapability();
                cancellationToken.ThrowIfCancellationRequested();
                if (capability == null || !capability.Accepted)
                {
                    AudioNativeCallResultV2 failure = capability == null
                        ? null
                        : capability.Result;
                    return PublishUnavailable(
                        failure,
                        AudioNativeV2.ResultAbiMismatch,
                        "audio.abi_mismatch");
                }
                _capabilityDigest = capability.CapabilityDigest;

                AudioNativeInitializeResultV2 initialized =
                    _native.Initialize(
                        normalizedRoot,
                        _audioSessionId,
                        _audioReadyGeneration);
                // Native SFX counters are cumulative within one native initialize
                // epoch and reset on every initialize, including recovery.
                _lastNativeSfxCounters = null;
                cancellationToken.ThrowIfCancellationRequested();
                // audioReadyGeneration is managed-owned and advances before the
                // attempt. deviceGeneration is native-owned: never predict it,
                // but retain a structurally consistent epoch returned by an
                // attempted initialization even when device start fails.
                bool returnedDeviceEpoch = TryAdoptReturnedDeviceEpoch(
                    initialized,
                    recovery,
                    previousDeviceGeneration);
                if (initialized == null || !initialized.Ready)
                {
                    AudioNativeCallResultV2 failure = initialized == null
                        ? null
                        : initialized.Result;
                    if (recovery && IsDeviceRecoveryActive())
                        return PublishDeviceRecoveryAttemptFailure(failure);
                    if (!recovery && IsRetryableDeviceFailure(failure) &&
                        !_shutdownStarted)
                    {
                        // The first native initialize can race a transiently
                        // unavailable default endpoint just as a later reroute
                        // can. Count that call as attempt one and continue the
                        // same bounded episode without advancing readyGeneration
                        // again on attempts two through five.
                        _deviceRecoveryAttempt = 1;
                        _deviceRecoveryBackoffTicks = 0;
                        Volatile.Write(ref _deviceRecoveryActive, 1);
                        return PublishDeviceRecoveryAttemptFailure(failure);
                    }
                    return PublishUnavailable(
                        failure,
                        AudioNativeV2.ResultDeviceUnavailable,
                        "audio.device_unavailable");
                }
                if (!returnedDeviceEpoch)
                {
                    return PublishUnavailable(
                        initialized.Result,
                        AudioNativeV2.ResultStaleGeneration,
                        "audio.device_epoch_invalid");
                }
                if (_initialMasterGain != 1f)
                {
                    AudioNativeCallResultV2 gainResult = _native.SetGain(
                        _audioSessionId,
                        _audioReadyGeneration,
                        AudioNativeV2.OperationSetMasterGain,
                        _initialMasterGain);
                    cancellationToken.ThrowIfCancellationRequested();
                    if (gainResult == null || !gainResult.IsOk)
                    {
                        return PublishUnavailable(
                            gainResult,
                            AudioNativeV2.ResultInternalError,
                            "audio.master_gain_failed");
                    }
                }

                AudioPreloadResultV2 preload =
                    _preloadHook(normalizedRoot, cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                if (preload == null)
                {
                    return PublishUnavailable(
                        null,
                        AudioNativeV2.ResultInternalError,
                        "audio.preload_failed");
                }

                AudioNativeCallResultV2 catalogResult =
                    _native.RebuildSfxCatalog(
                        _audioSessionId,
                        _audioReadyGeneration,
                        preload.Items);
                cancellationToken.ThrowIfCancellationRequested();
                if (catalogResult == null || !catalogResult.IsOk)
                {
                    return PublishUnavailable(
                        catalogResult,
                        AudioNativeV2.ResultInternalError,
                        "audio.catalog_failed");
                }

                _catalogHook(
                    _audioSessionId,
                    _audioReadyGeneration,
                    _deviceGeneration,
                    preload,
                    cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();

                _catalog = preload;
                ReplaceManagedCatalog(preload.Items);

                AudioCatalogQualificationHookV2 qualificationHook =
                    _catalogQualificationHook;
                if (qualificationHook != null)
                {
                    _catalogQualificationPending = true;
                    _pendingRecoveryIntent = recoveryIntent;
                    _pendingRecoveryPaused = recoveryPaused;
                    Publish(CreateSnapshot(
                        recovery
                            ? AudioCoordinatorStatusV2.Recovering
                            : AudioCoordinatorStatusV2.Initializing,
                        AudioNativeV2.ResultNotReady,
                        "audio.catalog_qualifying",
                        null));
                    var qualificationRequest =
                        new AudioCatalogQualificationRequestV2(
                            _audioSessionId,
                            _audioReadyGeneration,
                            _deviceGeneration,
                            _capabilityDigest,
                            cancellationToken);
                    ThreadPool.QueueUserWorkItem(delegate
                    {
                        try
                        {
                            qualificationHook(qualificationRequest);
                        }
                        catch
                        {
                            CompleteCatalogQualification(
                                qualificationRequest.AudioSessionId,
                                qualificationRequest.AudioReadyGeneration,
                                qualificationRequest.DeviceGeneration,
                                qualificationRequest.CapabilityDigest,
                                false);
                        }
                    });
                    return false;
                }

                if (recovery && recoveryIntent != null)
                {
                    AudioNativeBgmCommandV2 replay = RebindBgmIntent(
                        recoveryIntent,
                        _audioSessionId,
                        _audioReadyGeneration);
                    AudioNativeCallResultV2 replayResult =
                        ExecuteRecoveryBgmCore(replay, recoveryPaused);
                    if (replayResult == null || !replayResult.IsOk)
                        return false;
                }
                Publish(CreateSnapshot(
                    AudioCoordinatorStatusV2.Ready,
                    AudioNativeV2.ResultOk,
                    "audio.ready",
                    null));
                if (recovery) EndDeviceRecoverySequenceCore();
                return true;
            }
            catch (OperationCanceledException)
            {
                return false;
            }
            catch (Exception)
            {
                return PublishUnavailable(
                    null,
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.unavailable");
            }
        }

        private void DispatchBgmOnOwner(
            AudioBgmRequestV2 request,
            Action<AudioBgmResultV2> respond)
        {
            AudioCoordinatorSnapshotV2 current = Snapshot;
            if (!MatchesTuple(request.AudioSessionId,
                request.AudioReadyGeneration,
                current))
            {
                SafeRespond(respond, StaleResult(request, current));
                return;
            }
            if (!current.IsReady)
            {
                SafeRespond(respond, UnavailableResult(request, current));
                return;
            }

            if (_bootstrapGateArmed &&
                (request.Operation == AudioWireV2.BgmPlay ||
                    request.Operation == AudioWireV2.BgmStop))
            {
                SupersedeBootstrapPending();
                _bootstrapPending = new PendingBgm(request, respond);
                SafeRespond(respond, new AudioBgmResultV2(
                    request.RequestId,
                    _audioSessionId,
                    _audioReadyGeneration,
                    _deviceGeneration,
                    request.Operation,
                    "accepted_deferred",
                    "ok",
                    "admission",
                    0,
                    0,
                    "none",
                    "audio.bgm.accepted_deferred"));
                return;
            }

            AudioNativeBgmCommandV2 command;
            AudioNativeCallResultV2 invalid;
            if (!TryBuildWireBgmCommand(request, out command, out invalid))
            {
                SafeRespond(respond, ToWireResult(request, invalid));
                return;
            }
            AudioNativeCallResultV2 result = ExecuteBgmCore(command, true);
            SafeRespond(respond, ToWireResult(request, result));
        }

        private void DispatchSfxOnOwner(AudioSfxBatchV2 batch)
        {
            ulong eventCount = (ulong)batch.LinkageIds.Count;
            AudioCoordinatorSnapshotV2 current = Snapshot;
            if (!MatchesTuple(batch.AudioSessionId,
                batch.AudioReadyGeneration,
                current))
            {
                AddCounter(ref _staleGenerationDrops, eventCount);
                PublishCountersOnly();
                return;
            }
            if (!current.IsReady)
            {
                AddAdmissionDrop(current, eventCount);
                PublishCountersOnly();
                return;
            }

            var ids = new List<string>(batch.LinkageIds.Count);
            for (int index = 0; index < batch.LinkageIds.Count; index++)
            {
                ids.Add(batch.LinkageIds[index]);
            }
            AudioNativeCallResultV2 result;
            try
            {
                result = _native.SubmitSfxBatch(
                    _audioSessionId,
                    _audioReadyGeneration,
                    batch.BatchSequence,
                    ids,
                    1f);
            }
            catch
            {
                PublishUnavailable(
                    null,
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.native_unavailable");
                return;
            }
            ApplySfxResult(result, ids.Count);
        }

        private AudioNativeCallResultV2 ExecuteBgmCore(
            AudioNativeBgmCommandV2 command,
            bool rememberIntent)
        {
            return ExecuteBgmCore(command, rememberIntent, false, false);
        }

        private AudioNativeCallResultV2 ExecuteRecoveryBgmCore(
            AudioNativeBgmCommandV2 command,
            bool restorePaused)
        {
            return ExecuteBgmCore(command, false, true, restorePaused);
        }

        private AudioNativeCallResultV2 ExecuteBgmCore(
            AudioNativeBgmCommandV2 command,
            bool rememberIntent,
            bool forceMutedPositioning,
            bool pauseBeforeGainRestore)
        {
            AudioCoordinatorSnapshotV2 current = Snapshot;
            bool recoveryReplayAdmission =
                forceMutedPositioning && IsDeviceRecoveryActive() &&
                current.Status == AudioCoordinatorStatusV2.Recovering &&
                MatchesTuple(
                    command.AudioSessionId,
                    command.AudioReadyGeneration,
                    current);
            if ((!current.IsReady && !recoveryReplayAdmission) ||
                !MatchesTuple(
                    command.AudioSessionId,
                    command.AudioReadyGeneration,
                    current))
            {
                return AudioNativeCallResultV2.Failure(
                    AudioNativeV2.ResultStaleGeneration,
                    command.Operation,
                    AudioNativeV2.StageAdmission,
                    _audioSessionId,
                    _audioReadyGeneration,
                    _deviceGeneration,
                    "audio.stale_generation");
            }

            AudioNativeCallResultV2 result;
            try
            {
                result = SubmitNativeBgmSequence(
                    command,
                    forceMutedPositioning,
                    pauseBeforeGainRestore);
            }
            catch
            {
                result = AudioNativeCallResultV2.Failure(
                    AudioNativeV2.ResultDeviceUnavailable,
                    command.Operation,
                    AudioNativeV2.StageNativeStart,
                    _audioSessionId,
                    _audioReadyGeneration,
                    _deviceGeneration,
                    "audio.native_unavailable");
                PublishUnavailable(
                    result,
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.native_unavailable");
                return result;
            }
            if (result == null)
            {
                result = AudioNativeCallResultV2.Failure(
                    AudioNativeV2.ResultInternalError,
                    command.Operation,
                    AudioNativeV2.StageNativeStart,
                    _audioSessionId,
                    _audioReadyGeneration,
                    _deviceGeneration,
                    "audio.native_null_result");
                PublishUnavailable(
                    result,
                    AudioNativeV2.ResultInternalError,
                    "audio.native_null_result");
                return result;
            }
            if (result.IsOk && rememberIntent)
            {
                UpdateLatestBgmIntent(command);
            }
            if (result.Category == AudioNativeV2.ResultDeviceLost)
            {
                if (IsDeviceRecoveryActive())
                {
                    // A recovered device can disappear again while the latest
                    // BGM intent is being restored. Keep the existing bounded
                    // episode and its consumed attempt budget; resetting the
                    // episode here would turn repeated device loss into an
                    // unbounded retry loop.
                    PublishDeviceRecoveryAttemptFailure(result);
                }
                else
                {
                    // A command-level device_lost result is itself a recovery
                    // trigger. Publishing Recovering without arming the episode
                    // would permanently gate the runtime poll timer.
                    CaptureRecoveryCursor();
                    BeginDeviceRecoverySequenceCore();
                }
            }
            else if (result.Category == AudioNativeV2.ResultNotReady &&
                IsDeviceRecoveryActive())
            {
                // With host-owned routing the native notification can win the
                // race with a recovery replay. A NotReady replay is therefore a
                // retryable loss of this already-counted attempt, not success and
                // not a new episode.
                PublishDeviceRecoveryAttemptFailure(
                    CreateRuntimeFailure(
                        AudioNativeV2.ResultDeviceLost,
                        "audio.device_lost"));
            }
            else if (result.Category == AudioNativeV2.ResultDeviceUnavailable ||
                result.Category == AudioNativeV2.ResultAbiMismatch)
            {
                PublishUnavailable(
                    result,
                    result.Category,
                    result.Category == AudioNativeV2.ResultAbiMismatch
                        ? "audio.abi_mismatch"
                        : "audio.device_unavailable");
            }
            else if (result.IsOk)
            {
                AudioNativeObservationV2 observation = null;
                try
                {
                    observation = _native.QueryBgmObservation(
                        _audioSessionId,
                        _audioReadyGeneration,
                        _deviceGeneration);
                }
                catch
                {
                    result = AudioNativeCallResultV2.Failure(
                        AudioNativeV2.ResultDeviceUnavailable,
                        command.Operation,
                        AudioNativeV2.StageNativeStart,
                        _audioSessionId,
                        _audioReadyGeneration,
                        _deviceGeneration,
                        "audio.native_unavailable");
                    PublishUnavailable(
                        result,
                        AudioNativeV2.ResultDeviceUnavailable,
                        "audio.native_unavailable");
                    return result;
                }
                if (observation != null && observation.Valid)
                {
                    PublishObservation(observation);
                }
            }
            return result;
        }

        private AudioNativeCallResultV2 SubmitNativeBgmSequence(
            AudioNativeBgmCommandV2 command,
            bool forceMutedPositioning,
            bool pauseBeforeGainRestore)
        {
            if (command.Operation == AudioNativeV2.OperationBgmSetGain)
            {
                return _native.SetGain(
                    command.AudioSessionId,
                    command.AudioReadyGeneration,
                    command.Operation,
                    command.Volume);
            }
            if (command.Operation != AudioNativeV2.OperationBgmPlay ||
                (!forceMutedPositioning && command.SeekSeconds <= 0f &&
                    !pauseBeforeGainRestore))
            {
                return _native.SubmitBgm(command);
            }

            // Native play initializes and starts the source, but does not consume
            // the play command's seek field. Keep the BGM group silent until the
            // source is positioned and, for recovery of a paused track, stopped.
            // Only then restore the remembered track gain. This prevents a short
            // audible burst from frame zero during recovery or positioned play.
            var mutedPlay = new AudioNativeBgmCommandV2(
                command.RequestId,
                command.AudioSessionId,
                command.AudioReadyGeneration,
                AudioNativeV2.OperationBgmPlay,
                command.NormalizedPath,
                command.Loop,
                0f,
                command.FadeSeconds,
                0f);
            AudioNativeCallResultV2 playResult = _native.SubmitBgm(mutedPlay);
            if (playResult == null || !playResult.IsOk)
                return playResult;

            if (command.SeekSeconds > 0f)
            {
                var seek = new AudioNativeBgmCommandV2(
                    command.RequestId,
                    command.AudioSessionId,
                    command.AudioReadyGeneration,
                    AudioNativeV2.OperationBgmSeek,
                    null,
                    command.Loop,
                    0f,
                    0f,
                    command.SeekSeconds);
                AudioNativeCallResultV2 seekResult = _native.SubmitBgm(seek);
                if (seekResult == null || !seekResult.IsOk)
                {
                    BestEffortStopMutedBgm(command);
                    return seekResult;
                }
            }

            if (pauseBeforeGainRestore)
            {
                var pause = new AudioNativeBgmCommandV2(
                    command.RequestId,
                    command.AudioSessionId,
                    command.AudioReadyGeneration,
                    AudioNativeV2.OperationBgmPause,
                    null,
                    command.Loop,
                    0f,
                    0f,
                    0f);
                AudioNativeCallResultV2 pauseResult = _native.SubmitBgm(pause);
                if (pauseResult == null || !pauseResult.IsOk)
                {
                    BestEffortStopMutedBgm(command);
                    return pauseResult;
                }
            }

            AudioNativeCallResultV2 gainResult = _native.SetGain(
                command.AudioSessionId,
                command.AudioReadyGeneration,
                AudioNativeV2.OperationBgmSetGain,
                command.Volume);
            if (gainResult == null || !gainResult.IsOk)
            {
                BestEffortStopMutedBgm(command);
                return gainResult;
            }
            return playResult;
        }

        private void BestEffortStopMutedBgm(AudioNativeBgmCommandV2 command)
        {
            try
            {
                _native.SubmitBgm(new AudioNativeBgmCommandV2(
                    command.RequestId,
                    command.AudioSessionId,
                    command.AudioReadyGeneration,
                    AudioNativeV2.OperationBgmStop,
                    null,
                    false,
                    0f,
                    0f,
                    0f));
            }
            catch
            {
            }
        }

        private bool TryBuildWireBgmCommand(
            AudioBgmRequestV2 request,
            out AudioNativeBgmCommandV2 command,
            out AudioNativeCallResultV2 failure)
        {
            command = null;
            failure = null;
            uint operation = MapOperation(request.Operation);
            string normalizedPath = null;
            if (operation == AudioNativeV2.OperationNone)
            {
                failure = InvalidBgmResult(
                    operation,
                    "audio.bgm.operation_invalid");
                return false;
            }
            if (operation == AudioNativeV2.OperationBgmPlay &&
                !TryNormalizeMediaPath(request.Path, out normalizedPath))
            {
                failure = AudioNativeCallResultV2.Failure(
                    AudioNativeV2.ResultIoError,
                    operation,
                    AudioNativeV2.StageValidatePath,
                    _audioSessionId,
                    _audioReadyGeneration,
                    _deviceGeneration,
                    "audio.path_outside_root");
                return false;
            }

            float volume = request.Volume.HasValue
                ? (float)request.Volume.Value
                : 1f;
            float fade = request.FadeSeconds.HasValue
                ? (float)request.FadeSeconds.Value
                : 0f;
            float seek = request.SeekSeconds.HasValue
                ? (float)request.SeekSeconds.Value
                : 0f;
            if (!IsFiniteGain(volume) || !IsFiniteRange(fade, 0f, 60f) ||
                !IsFiniteRange(seek, 0f, 86400f))
            {
                failure = InvalidBgmResult(
                    operation,
                    "audio.bgm.numeric_invalid");
                return false;
            }

            command = new AudioNativeBgmCommandV2(
                request.RequestId,
                _audioSessionId,
                _audioReadyGeneration,
                operation,
                normalizedPath,
                request.Loop.HasValue && request.Loop.Value,
                volume,
                fade,
                seek);
            return true;
        }

        private bool TryBuildLegacyBgmCommand(
            uint operation,
            string path,
            bool loop,
            float volume,
            float fade,
            float seek,
            out AudioNativeBgmCommandV2 command)
        {
            command = null;
            if (!Snapshot.IsReady || !IsKnownBgmOperation(operation) ||
                !IsFiniteGain(volume) || !IsFiniteRange(fade, 0f, 60f) ||
                !IsFiniteRange(seek, 0f, 86400f))
            {
                return false;
            }
            string normalizedPath = null;
            if (operation == AudioNativeV2.OperationBgmPlay &&
                !TryNormalizeMediaPath(path, out normalizedPath))
            {
                return false;
            }
            command = new AudioNativeBgmCommandV2(
                "legacy.bgm." + Interlocked.Increment(
                    ref _legacyRequestSequence).ToString(
                        System.Globalization.CultureInfo.InvariantCulture),
                _audioSessionId,
                _audioReadyGeneration,
                operation,
                normalizedPath,
                loop,
                volume,
                fade,
                seek);
            return true;
        }

        private int LegacySfxLoadCore(string path)
        {
            string normalizedPath;
            if (!Snapshot.IsReady ||
                !TryNormalizeMediaPath(path, out normalizedPath))
            {
                return -1;
            }
            string linkageId = Path.GetFileName(path);
            if (string.IsNullOrEmpty(linkageId)) return -1;

            int existing;
            if (_handleById.TryGetValue(linkageId, out existing)) return existing;
            int handle = NextHandle();
            var item = new AudioCatalogItemV2(linkageId, normalizedPath);
            _handleById[linkageId] = handle;
            _itemByHandle[handle] = item;
            AudioNativeCallResultV2 result = RebuildNativeCatalogFromHandles();
            if (result == null || !result.IsOk)
            {
                _handleById.Remove(linkageId);
                _itemByHandle.Remove(handle);
                return -1;
            }
            PublishCountersOnly();
            return handle;
        }

        private AudioNativeCallResultV2 RebuildNativeCatalogFromHandles()
        {
            var items = new List<AudioCatalogItemV2>(_itemByHandle.Values);
            items.Sort(delegate(AudioCatalogItemV2 left, AudioCatalogItemV2 right)
            {
                return string.CompareOrdinal(left.LinkageId, right.LinkageId);
            });
            try
            {
                return _native.RebuildSfxCatalog(
                    _audioSessionId,
                    _audioReadyGeneration,
                    items);
            }
            catch
            {
                PublishUnavailable(
                    null,
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.native_unavailable");
                return AudioNativeCallResultV2.Failure(
                    AudioNativeV2.ResultDeviceUnavailable,
                    AudioNativeV2.OperationSfxRebuildCatalog,
                    AudioNativeV2.StageNativeStart,
                    _audioSessionId,
                    _audioReadyGeneration,
                    _deviceGeneration,
                    "audio.native_unavailable");
            }
        }

        private void ApplySfxResult(AudioNativeCallResultV2 result, int count)
        {
            ulong eventCount = (ulong)Math.Max(0, count);
            if (result != null && result.SfxCounters != null &&
                TryApplyNativeSfxCounters(result.SfxCounters))
            {
                // The native aggregate is authoritative per item.  A batch-level
                // OK never implies that every linkage id reached ma_sound_start().
            }
            else if (result != null &&
                result.Category == AudioNativeV2.ResultUnknownId)
            {
                AddCounter(ref _unknownIdCount, eventCount);
            }
            else if (result != null &&
                result.Category == AudioNativeV2.ResultThrottled)
            {
                AddCounter(ref _throttledCount, eventCount);
            }
            else
            {
                // Production OK results always carry the validated native counter
                // tuple.  Missing counters fail closed instead of fabricating plays.
                AddCounter(ref _startFailureCount, eventCount);
            }
            PublishCountersOnly();
        }

        private void AddAdmissionDrop(
            AudioCoordinatorSnapshotV2 observed,
            ulong eventCount)
        {
            if (observed != null &&
                (observed.Status == AudioCoordinatorStatusV2.Recovering ||
                 (observed.Status == AudioCoordinatorStatusV2.Unavailable &&
                  _hasEnteredReady)))
            {
                AddCounter(ref _recoveryDrops, eventCount);
            }
            else
            {
                AddCounter(ref _preReadyDrops, eventCount);
            }
        }

        private bool TryApplyNativeSfxCounters(
            AudioNativeSfxCountersV2 current)
        {
            if (current == null ||
                !string.Equals(
                    current.AudioSessionId,
                    _audioSessionId,
                    StringComparison.Ordinal) ||
                current.AudioReadyGeneration != _audioReadyGeneration)
            {
                return false;
            }

            AudioNativeSfxCountersV2 previous = _lastNativeSfxCounters;
            if (previous != null &&
                (!string.Equals(
                    previous.AudioSessionId,
                    current.AudioSessionId,
                    StringComparison.Ordinal) ||
                 previous.AudioReadyGeneration !=
                    current.AudioReadyGeneration ||
                 current.PreReadyDrops < previous.PreReadyDrops ||
                 current.RecoveryDrops < previous.RecoveryDrops ||
                 current.StaleGenerationDrops <
                    previous.StaleGenerationDrops ||
                 current.UnknownIdCount < previous.UnknownIdCount ||
                 current.ThrottledCount < previous.ThrottledCount ||
                 current.StartFailureCount < previous.StartFailureCount ||
                 current.PlayedCount < previous.PlayedCount))
            {
                return false;
            }

            ulong preReadyDelta = previous == null
                ? current.PreReadyDrops
                : current.PreReadyDrops - previous.PreReadyDrops;
            ulong recoveryDelta = previous == null
                ? current.RecoveryDrops
                : current.RecoveryDrops - previous.RecoveryDrops;
            ulong staleDelta = previous == null
                ? current.StaleGenerationDrops
                : current.StaleGenerationDrops -
                    previous.StaleGenerationDrops;
            ulong unknownDelta = previous == null
                ? current.UnknownIdCount
                : current.UnknownIdCount - previous.UnknownIdCount;
            ulong throttledDelta = previous == null
                ? current.ThrottledCount
                : current.ThrottledCount - previous.ThrottledCount;
            ulong startFailureDelta = previous == null
                ? current.StartFailureCount
                : current.StartFailureCount - previous.StartFailureCount;
            ulong playedDelta = previous == null
                ? current.PlayedCount
                : current.PlayedCount - previous.PlayedCount;

            if (WouldOverflow(_preReadyDrops, preReadyDelta) ||
                WouldOverflow(_recoveryDrops, recoveryDelta) ||
                WouldOverflow(_staleGenerationDrops, staleDelta) ||
                WouldOverflow(_unknownIdCount, unknownDelta) ||
                WouldOverflow(_throttledCount, throttledDelta) ||
                WouldOverflow(_startFailureCount, startFailureDelta) ||
                WouldOverflow(_playedCount, playedDelta))
            {
                ResetForCounterOverflow();
                return true;
            }

            _preReadyDrops += preReadyDelta;
            _recoveryDrops += recoveryDelta;
            _staleGenerationDrops += staleDelta;
            _unknownIdCount += unknownDelta;
            _throttledCount += throttledDelta;
            _startFailureCount += startFailureDelta;
            _playedCount += playedDelta;
            _lastNativeSfxCounters = current;
            return true;
        }

        private static bool WouldOverflow(ulong value, ulong addition)
        {
            return ulong.MaxValue - value < addition;
        }

        private void UpdateLatestBgmIntent(AudioNativeBgmCommandV2 command)
        {
            if (command.Operation == AudioNativeV2.OperationBgmStop)
            {
                _latestBgmIntent = null;
                _latestBgmPaused = false;
                return;
            }
            if (command.Operation == AudioNativeV2.OperationBgmPlay)
            {
                _latestBgmIntent = command;
                _latestBgmPaused = false;
                return;
            }
            if (_latestBgmIntent == null) return;

            if (command.Operation == AudioNativeV2.OperationBgmPause)
            {
                _latestBgmPaused = true;
            }
            else if (command.Operation == AudioNativeV2.OperationBgmResume)
            {
                _latestBgmPaused = false;
            }

            bool loop = command.Operation == AudioNativeV2.OperationBgmSetLoop
                ? command.Loop
                : _latestBgmIntent.Loop;
            float volume = command.Operation == AudioNativeV2.OperationBgmSetGain
                ? command.Volume
                : _latestBgmIntent.Volume;
            float seek = command.Operation == AudioNativeV2.OperationBgmSeek
                ? command.SeekSeconds
                : _latestBgmIntent.SeekSeconds;
            _latestBgmIntent = new AudioNativeBgmCommandV2(
                _latestBgmIntent.RequestId,
                _latestBgmIntent.AudioSessionId,
                _latestBgmIntent.AudioReadyGeneration,
                _latestBgmIntent.Operation,
                _latestBgmIntent.NormalizedPath,
                loop,
                volume,
                _latestBgmIntent.FadeSeconds,
                seek);
        }

        private void SupersedeBootstrapPending()
        {
            PendingBgm prior = _bootstrapPending;
            _bootstrapPending = null;
            if (prior == null) return;
            SafeRespond(prior.Respond, new AudioBgmResultV2(
                prior.Request.RequestId,
                _audioSessionId,
                _audioReadyGeneration,
                _deviceGeneration,
                prior.Request.Operation,
                "superseded",
                "superseded",
                "admission",
                0,
                0,
                "none",
                "audio.bgm.superseded"));
        }

        private bool PublishUnavailable(
            AudioNativeCallResultV2 failure,
            uint fallbackCategory,
            string fallbackMessageKey)
        {
            EndDeviceRecoverySequenceCore();
            _catalogQualificationPending = false;
            _pendingRecoveryIntent = null;
            _pendingRecoveryPaused = false;
            if (_nativeTouched) BestEffortNativeShutdown();
            uint category = failure == null
                ? fallbackCategory
                : failure.Category;
            if (category == AudioNativeV2.ResultOk) category = fallbackCategory;
            Publish(CreateSnapshot(
                AudioCoordinatorStatusV2.Unavailable,
                category,
                SafeMessageKey(failure, fallbackMessageKey),
                null));
            return false;
        }

        private void PublishObservation(AudioNativeObservationV2 observation)
        {
            Publish(CreateSnapshot(
                Snapshot.Status,
                Snapshot.FailureCategory,
                Snapshot.MessageKey,
                observation));
        }

        private void PublishCountersOnly()
        {
            Publish(CreateSnapshot(
                Snapshot.Status,
                Snapshot.FailureCategory,
                Snapshot.MessageKey,
                null));
        }

        private AudioCoordinatorSnapshotV2 CreateSnapshot(
            AudioCoordinatorStatusV2 status,
            uint failureCategory,
            string messageKey,
            AudioNativeObservationV2 observation)
        {
            AudioCoordinatorSnapshotV2 prior = _snapshot;
            if (observation != null && observation.Valid)
                _lastQualificationObservation = observation;
            AudioNativeObservationV2 qualificationObservation =
                observation ?? _lastQualificationObservation;
            bool exposeReadyState = status == AudioCoordinatorStatusV2.Ready;
            int loaded = !exposeReadyState || _catalog == null
                ? 0
                : _catalog.Items.Count;
            int failed = !exposeReadyState || _catalog == null
                ? 0
                : _catalog.Failed;
            int overrides = !exposeReadyState || _catalog == null
                ? 0
                : _catalog.Overrides;
            if (!exposeReadyState)
            {
                observation = new AudioNativeObservationV2(
                    true, 0f, 0f, 0f, 0f, false, "none");
            }
            float peakLeft = observation == null
                ? (prior == null ? 0f : prior.PeakLeft)
                : observation.PeakLeft;
            float peakRight = observation == null
                ? (prior == null ? 0f : prior.PeakRight)
                : observation.PeakRight;
            float cursor = observation == null
                ? (prior == null ? 0f : prior.CursorSeconds)
                : observation.CursorSeconds;
            float length = observation == null
                ? (prior == null ? 0f : prior.LengthSeconds)
                : observation.LengthSeconds;
            bool playing = observation == null
                ? prior != null && prior.BgmPlaying
                : observation.Playing;
            string decoder = observation == null
                ? (prior == null ? "none" : prior.DecoderBackend)
                : observation.DecoderBackend;
            var qualification = new AudioCoordinatorQualificationStateV2
            {
                Backend = _backend,
                DeviceIdDigest = _deviceIdDigest,
                DeviceName = _deviceName,
                SampleRate = _sampleRate,
                Channels = _channels,
                SampleFormat = _sampleFormat,
                SourceRequestId = _latestBgmIntent == null
                    ? null
                    : _latestBgmIntent.RequestId,
                Observation = qualificationObservation
            };
            return new AudioCoordinatorSnapshotV2(
                status,
                _audioSessionId,
                _audioReadyGeneration,
                _deviceGeneration,
                _normalizedBasePath,
                _capabilityDigest,
                loaded,
                failed,
                overrides,
                failureCategory,
                messageKey,
                peakLeft,
                peakRight,
                cursor,
                length,
                playing,
                string.IsNullOrEmpty(decoder) ? "none" : decoder,
                _preReadyDrops,
                _recoveryDrops,
                _staleGenerationDrops,
                _unknownIdCount,
                _throttledCount,
                _startFailureCount,
                _playedCount,
                exposeReadyState
                    ? _handleById
                    : new Dictionary<string, int>(StringComparer.Ordinal),
                qualification);
        }

        private void Publish(AudioCoordinatorSnapshotV2 value)
        {
            if (value != null && value.Status == AudioCoordinatorStatusV2.Ready)
                _hasEnteredReady = true;
            Volatile.Write(ref _snapshot, value);
            Action<AudioCoordinatorSnapshotV2> handler = SnapshotChanged;
            if (handler == null) return;
            try { handler(value); }
            catch
            {
                // Projection observers must never break the native owner queue.
            }
        }

        private void ReplaceManagedCatalog(
            IList<AudioCatalogItemV2> items)
        {
            var oldHandles = _handleById;
            var handles = new Dictionary<string, int>(StringComparer.Ordinal);
            var byHandle = new Dictionary<int, AudioCatalogItemV2>();
            for (int index = 0; index < items.Count; index++)
            {
                AudioCatalogItemV2 item = items[index];
                int handle;
                if (!oldHandles.TryGetValue(item.LinkageId, out handle))
                    handle = NextHandle();
                handles[item.LinkageId] = handle;
                byHandle[handle] = item;
            }
            _handleById = handles;
            _itemByHandle = byHandle;
        }

        private void ResetCountersAndCatalog()
        {
            _preReadyDrops = 0;
            _recoveryDrops = 0;
            _staleGenerationDrops = 0;
            _unknownIdCount = 0;
            _throttledCount = 0;
            _startFailureCount = 0;
            _playedCount = 0;
            _lastNativeSfxCounters = null;
            _backend = AudioNativeV2.BackendNone;
            _deviceIdDigest = null;
            _deviceName = null;
            _sampleRate = 0u;
            _channels = 0u;
            _sampleFormat = AudioNativeV2.SampleFormatUnknown;
            _lastQualificationObservation = null;
            _hasEnteredReady = false;
            _catalog = null;
            _handleById = new Dictionary<string, int>(StringComparer.Ordinal);
            _itemByHandle = new Dictionary<int, AudioCatalogItemV2>();
            _nextHandle = 1;
            _legacyBatchSequence = 0uL;
            _latestBgmIntent = null;
            _latestBgmPaused = false;
            _pendingRecoveryIntent = null;
            _pendingRecoveryPaused = false;
            SupersedeBootstrapPending();
        }

        private void AdvanceReadyGeneration()
        {
            if (_audioReadyGeneration == ulong.MaxValue)
            {
                if (_nativeTouched) BestEffortNativeShutdown();
                _audioSessionId = NewSessionId();
                _audioReadyGeneration = 1uL;
                _deviceGeneration = 0uL;
                ResetCountersAndCatalog();
                return;
            }
            _audioReadyGeneration++;
            if (_audioReadyGeneration == 0uL) _audioReadyGeneration = 1uL;
        }

        private bool TryAdoptReturnedDeviceEpoch(
            AudioNativeInitializeResultV2 initialized,
            bool recovery,
            ulong previousDeviceGeneration)
        {
            if (initialized == null || !initialized.ReturnedTupleValid ||
                initialized.DeviceGeneration == 0uL ||
                (recovery && initialized.DeviceGeneration <=
                    previousDeviceGeneration))
            {
                return false;
            }

            _deviceGeneration = initialized.DeviceGeneration;
            _backend = initialized.Backend;
            _deviceIdDigest = initialized.DeviceIdDigest;
            _deviceName = initialized.DeviceName;
            _sampleRate = initialized.SampleRate;
            _channels = initialized.Channels;
            _sampleFormat = initialized.SampleFormat;
            return true;
        }

        private void AdoptRuntimeMetadata(
            AudioNativeRuntimeStateV2 runtime)
        {
            if (runtime == null) return;
            _backend = runtime.Backend;
            _deviceIdDigest = runtime.DeviceIdDigest;
            _deviceName = runtime.DeviceName;
            _sampleRate = runtime.SampleRate;
            _channels = runtime.Channels;
            _sampleFormat = runtime.SampleFormat;
        }

        private void ShutdownOnOwner()
        {
            try
            {
                EndDeviceRecoverySequenceCore();
                SupersedeBootstrapPending();
                if (_nativeTouched) BestEffortNativeShutdown();
                Publish(CreateSnapshot(
                    AudioCoordinatorStatusV2.Shutdown,
                    AudioNativeV2.ResultNotReady,
                    "audio.shutdown",
                    new AudioNativeObservationV2(
                        true, 0f, 0f, 0f, 0f, false, "none")));
            }
            finally
            {
                _shutdownComplete.Set();
            }
        }

        private void BestEffortNativeShutdown()
        {
            if (_shutdownStarted)
            {
                _nativeShutdownFenceComplete.Wait();
                _nativeTouched = false;
                return;
            }
            try
            {
                _native.Shutdown(_audioSessionId, _audioReadyGeneration);
            }
            catch
            {
            }
            finally
            {
                _nativeTouched = false;
            }
        }

        private void RunNativeShutdownFence()
        {
            try
            {
                if (!Volatile.Read(ref _nativeTouched)) return;

                AudioCoordinatorSnapshotV2 observed = Snapshot;
                string sessionId = observed.AudioSessionId;
                ulong readyGeneration = observed.AudioReadyGeneration;
                try
                {
                    AudioNativeRuntimeStateV2 runtime = _native.QueryRuntime();
                    if (runtime != null && runtime.Valid &&
                        !string.IsNullOrEmpty(runtime.AudioSessionId) &&
                        runtime.AudioReadyGeneration != 0uL)
                    {
                        sessionId = runtime.AudioSessionId;
                        readyGeneration = runtime.AudioReadyGeneration;
                    }
                }
                catch
                {
                }

                if (!string.IsNullOrEmpty(sessionId) &&
                    readyGeneration != 0uL)
                {
                    _native.Shutdown(sessionId, readyGeneration);
                }
            }
            catch
            {
            }
            finally
            {
                _nativeShutdownFenceComplete.Set();
            }
        }

        private void OwnerLoop()
        {
            _ownerThreadId = Thread.CurrentThread.ManagedThreadId;
            try
            {
                foreach (OwnerWorkItem item in
                    _ownerQueue.GetConsumingEnumerable())
                {
                    if (_lifetime.IsCancellationRequested &&
                        !item.RunDuringShutdown)
                    {
                        item.Complete(new OperationCanceledException());
                        continue;
                    }
                    try
                    {
                        item.Action();
                        item.Complete(null);
                    }
                    catch (Exception ex)
                    {
                        item.Complete(ex);
                    }
                }
            }
            finally
            {
                _shutdownComplete.Set();
            }
        }

        private bool TryPost(Action action)
        {
            lock (_admissionLock)
            {
                if (!_accepting) return false;
                _ownerQueue.Add(new OwnerWorkItem(action, false, null));
                return true;
            }
        }

        private T InvokeOwner<T>(Func<T> action, T fallback)
        {
            if (Thread.CurrentThread.ManagedThreadId == _ownerThreadId)
            {
                try { return action(); }
                catch { return fallback; }
            }

            var completion = new ManualResetEventSlim(false);
            T result = fallback;
            Exception error = null;
            var item = new OwnerWorkItem(
                delegate
                {
                    result = action();
                },
                false,
                completion);
            lock (_admissionLock)
            {
                if (!_accepting)
                {
                    completion.Dispose();
                    return fallback;
                }
                _ownerQueue.Add(item);
            }
            completion.Wait();
            error = item.Error;
            completion.Dispose();
            return error == null ? result : fallback;
        }

        private bool TryNormalizeMediaPath(string path, out string normalized)
        {
            normalized = null;
            if (string.IsNullOrWhiteSpace(path) ||
                string.IsNullOrEmpty(_normalizedBasePath))
            {
                return false;
            }
            try
            {
                string candidate = Path.IsPathRooted(path)
                    ? Path.GetFullPath(path)
                    : Path.GetFullPath(Path.Combine(_normalizedBasePath, path));
                string prefix = _normalizedBasePath.EndsWith(
                    Path.DirectorySeparatorChar.ToString(),
                    StringComparison.Ordinal)
                    ? _normalizedBasePath
                    : _normalizedBasePath + Path.DirectorySeparatorChar;
                if (!candidate.StartsWith(
                    prefix,
                    StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }
                normalized = candidate;
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static bool TryNormalizeRoot(string path, out string normalized)
        {
            normalized = null;
            if (string.IsNullOrWhiteSpace(path)) return false;
            try
            {
                string fullPath = Path.GetFullPath(path);
                string root = Path.GetPathRoot(fullPath);
                normalized = string.Equals(
                    fullPath,
                    root,
                    StringComparison.OrdinalIgnoreCase)
                    ? fullPath
                    : fullPath.TrimEnd(
                        Path.DirectorySeparatorChar,
                        Path.AltDirectorySeparatorChar);
                return normalized.Length > 0;
            }
            catch
            {
                return false;
            }
        }

        private static AudioPreloadResultV2 ScanDefaultCatalog(
            string normalizedBasePath,
            CancellationToken cancellationToken)
        {
            var byId = new Dictionary<string, AudioCatalogItemV2>(
                StringComparer.Ordinal);
            int failed = 0;
            int overrides = 0;
            for (int packIndex = 0;
                packIndex < SfxPackOrder.Length;
                packIndex++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                string directory = Path.Combine(
                    normalizedBasePath,
                    "sounds",
                    "export",
                    SfxPackOrder[packIndex]);
                if (!Directory.Exists(directory)) continue;

                string[] files;
                try
                {
                    files = Directory.GetFiles(directory);
                }
                catch
                {
                    failed++;
                    continue;
                }
                Array.Sort(files, StringComparer.OrdinalIgnoreCase);
                for (int fileIndex = 0;
                    fileIndex < files.Length;
                    fileIndex++)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    try
                    {
                        string linkageId = Path.GetFileName(files[fileIndex]);
                        string fullPath = Path.GetFullPath(files[fileIndex]);
                        if (byId.ContainsKey(linkageId)) overrides++;
                        byId[linkageId] = new AudioCatalogItemV2(
                            linkageId,
                            fullPath);
                    }
                    catch
                    {
                        failed++;
                    }
                }
            }
            var result = new List<AudioCatalogItemV2>(byId.Values);
            result.Sort(delegate(AudioCatalogItemV2 left, AudioCatalogItemV2 right)
            {
                return string.CompareOrdinal(left.LinkageId, right.LinkageId);
            });
            return new AudioPreloadResultV2(result, failed, overrides);
        }

        private static void NoopCatalogHook(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            AudioPreloadResultV2 catalog,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
        }

        private AudioBgmResultV2 ToWireResult(
            AudioBgmRequestV2 request,
            AudioNativeCallResultV2 result)
        {
            uint category = result == null
                ? AudioNativeV2.ResultInternalError
                : result.Category;
            return new AudioBgmResultV2(
                request.RequestId,
                _audioSessionId,
                _audioReadyGeneration,
                _deviceGeneration,
                request.Operation,
                CompletionName(result, request.Operation),
                CategoryName(category),
                StageName(result == null
                    ? AudioNativeV2.StageNativeStart
                    : result.Stage),
                result == null ? 0 : result.NativeCode,
                result == null ? 0 : result.Hresult,
                result != null && result.IsOk
                    ? (string.IsNullOrEmpty(result.DecoderBackend) ||
                        result.DecoderBackend == "none"
                        ? Snapshot.DecoderBackend
                        : result.DecoderBackend)
                    : "none",
                SafeMessageKey(result,
                    category == AudioNativeV2.ResultOk
                        ? "audio.bgm.completed"
                        : "audio.bgm.failed"));
        }

        private AudioBgmResultV2 StaleResult(
            AudioBgmRequestV2 request,
            AudioCoordinatorSnapshotV2 current)
        {
            return new AudioBgmResultV2(
                request.RequestId,
                current.AudioSessionId,
                current.AudioReadyGeneration,
                current.DeviceGeneration,
                request.Operation,
                "failed",
                "stale_generation",
                "admission",
                0,
                0,
                "none",
                "audio.stale_generation");
        }

        private AudioBgmResultV2 UnavailableResult(
            AudioBgmRequestV2 request,
            AudioCoordinatorSnapshotV2 current)
        {
            string category = current.Status ==
                AudioCoordinatorStatusV2.Unavailable
                ? CategoryName(current.FailureCategory)
                : "not_ready";
            if (category == "ok") category = "device_unavailable";
            return new AudioBgmResultV2(
                request.RequestId,
                current.AudioSessionId,
                current.AudioReadyGeneration,
                current.DeviceGeneration,
                request.Operation,
                "failed",
                category,
                "admission",
                0,
                0,
                "none",
                string.IsNullOrEmpty(current.MessageKey)
                    ? "audio.not_ready"
                    : current.MessageKey);
        }

        private AudioNativeCallResultV2 InvalidBgmResult(
            uint operation,
            string messageKey)
        {
            return AudioNativeCallResultV2.Failure(
                AudioNativeV2.ResultInternalError,
                operation,
                AudioNativeV2.StageAdmission,
                _audioSessionId,
                _audioReadyGeneration,
                _deviceGeneration,
                messageKey);
        }

        private static bool MatchesTuple(
            string sessionId,
            ulong readyGeneration,
            AudioCoordinatorSnapshotV2 snapshot)
        {
            return snapshot != null &&
                string.Equals(
                    sessionId,
                    snapshot.AudioSessionId,
                    StringComparison.Ordinal) &&
                readyGeneration == snapshot.AudioReadyGeneration;
        }

        private static void SafeRespond(
            Action<AudioBgmResultV2> respond,
            AudioBgmResultV2 result)
        {
            if (respond == null) return;
            try { respond(result); }
            catch { }
        }

        private static string SafeMessageKey(
            AudioNativeCallResultV2 result,
            string fallback)
        {
            return result == null || string.IsNullOrEmpty(result.MessageKey)
                ? fallback
                : result.MessageKey;
        }

        private static uint MapOperation(string operation)
        {
            if (operation == AudioWireV2.BgmPlay)
                return AudioNativeV2.OperationBgmPlay;
            if (operation == AudioWireV2.BgmStop)
                return AudioNativeV2.OperationBgmStop;
            if (operation == AudioWireV2.BgmPause)
                return AudioNativeV2.OperationBgmPause;
            if (operation == AudioWireV2.BgmResume)
                return AudioNativeV2.OperationBgmResume;
            if (operation == AudioWireV2.BgmSeek)
                return AudioNativeV2.OperationBgmSeek;
            if (operation == AudioWireV2.BgmSetLoop)
                return AudioNativeV2.OperationBgmSetLoop;
            if (operation == AudioWireV2.BgmSetGain)
                return AudioNativeV2.OperationBgmSetGain;
            return AudioNativeV2.OperationNone;
        }

        private static string CategoryName(uint value)
        {
            string[] names =
            {
                "ok", "missing", "unsupported_container",
                "unsupported_codec", "malformed", "truncated",
                "io_error", "abi_mismatch", "not_ready",
                "stale_generation", "unknown_id", "throttled",
                "start_failed", "seek_failed", "device_unavailable",
                "device_lost", "superseded", "internal_error"
            };
            return value < (uint)names.Length
                ? names[(int)value]
                : "internal_error";
        }

        private static string StageName(uint value)
        {
            switch (value)
            {
                case AudioNativeV2.StageValidateAbi: return "validate_abi";
                case AudioNativeV2.StageValidateCapacity:
                    return "validate_capacity";
                case AudioNativeV2.StageValidateSession:
                    return "validate_session";
                case AudioNativeV2.StageValidatePath: return "validate_path";
                case AudioNativeV2.StageAdmission: return "admission";
                case AudioNativeV2.StageContextInitialize:
                    return "context_initialize";
                case AudioNativeV2.StageDeviceInitialize:
                    return "device_initialize";
                case AudioNativeV2.StageDeviceStart: return "device_start";
                case AudioNativeV2.StageDecoderInitialize:
                    return "decoder_initialize";
                case AudioNativeV2.StageSourceInitialize:
                    return "source_initialize";
                case AudioNativeV2.StageNativeStart: return "native_start";
                case AudioNativeV2.StageSeek: return "seek";
                case AudioNativeV2.StageProbeInput: return "probe_input";
                case AudioNativeV2.StageProbeDecode: return "probe_decode";
                case AudioNativeV2.StageShutdown: return "shutdown";
                default: return "none";
            }
        }

        private static string CompletionName(
            AudioNativeCallResultV2 result,
            string operation)
        {
            if (result == null || !result.IsOk) return "failed";
            switch (result.CompletionState)
            {
                case AudioNativeV2.CompletionAcceptedDeferred:
                    return "accepted_deferred";
                case AudioNativeV2.CompletionStarted: return "started";
                case AudioNativeV2.CompletionStopped: return "stopped";
                case AudioNativeV2.CompletionSuperseded:
                    return "superseded";
                case AudioNativeV2.CompletionFailed: return "failed";
                default:
                    return operation == AudioWireV2.BgmStop
                        ? "stopped"
                        : "started";
            }
        }

        private static AudioNativeBgmCommandV2 RebindBgmIntent(
            AudioNativeBgmCommandV2 intent,
            string sessionId,
            ulong readyGeneration)
        {
            return new AudioNativeBgmCommandV2(
                intent.RequestId,
                sessionId,
                readyGeneration,
                intent.Operation,
                intent.NormalizedPath,
                intent.Loop,
                intent.Volume,
                intent.FadeSeconds,
                intent.SeekSeconds);
        }

        private static bool IsKnownBgmOperation(uint operation)
        {
            return operation >= AudioNativeV2.OperationBgmPlay &&
                operation <= AudioNativeV2.OperationBgmSetGain;
        }

        private static bool IsFrontdoorBgmRequestId(string requestId)
        {
            return !string.IsNullOrEmpty(requestId) &&
                requestId.Length <= 96 &&
                requestId.StartsWith(
                    "host.frontdoor.",
                    StringComparison.Ordinal);
        }

        private static bool HasRequestId(
            AudioNativeBgmCommandV2 command,
            string requestId)
        {
            return command != null && string.Equals(
                command.RequestId,
                requestId,
                StringComparison.Ordinal);
        }

        private static bool IsFiniteGain(float value)
        {
            return IsFiniteRange(value, 0f, 1f);
        }

        private static bool IsFiniteRange(float value, float min, float max)
        {
            return !float.IsNaN(value) && !float.IsInfinity(value) &&
                value >= min && value <= max;
        }

        private static int LegacyReturnCode(AudioNativeCallResultV2 result)
        {
            if (result != null && result.IsOk) return 0;
            if (result != null && result.NativeCode != 0) return result.NativeCode;
            return result == null
                ? -1
                : -Math.Max(1, (int)result.Category);
        }

        private int NextHandle()
        {
            if (_nextHandle == int.MaxValue) _nextHandle = 1;
            while (_itemByHandle.ContainsKey(_nextHandle)) _nextHandle++;
            return _nextHandle++;
        }

        private ulong NextBatchSequence()
        {
            if (_legacyBatchSequence == ulong.MaxValue)
            {
                ResetForCounterOverflow();
                return 0uL;
            }
            return ++_legacyBatchSequence;
        }

        private void IncrementCounter(ref ulong value)
        {
            if (value == ulong.MaxValue)
            {
                ResetForCounterOverflow();
                return;
            }
            value++;
        }

        private void AddCounter(ref ulong value, ulong addition)
        {
            if (ulong.MaxValue - value < addition)
            {
                ResetForCounterOverflow();
                return;
            }
            value += addition;
        }

        private void ResetForCounterOverflow()
        {
            if (_nativeTouched) BestEffortNativeShutdown();
            _audioSessionId = NewSessionId();
            _audioReadyGeneration = 0uL;
            _deviceGeneration = 0uL;
            _legacyBatchSequence = 0uL;
            ResetCountersAndCatalog();
            Publish(CreateSnapshot(
                AudioCoordinatorStatusV2.Unavailable,
                AudioNativeV2.ResultInternalError,
                "audio.counter_overflow_reset_required",
                null));
        }

        private static string NewSessionId()
        {
            return Guid.NewGuid().ToString("D");
        }

        private sealed class PendingBgm
        {
            internal PendingBgm(
                AudioBgmRequestV2 request,
                Action<AudioBgmResultV2> respond)
            {
                Request = request;
                Respond = respond;
            }

            internal AudioBgmRequestV2 Request { get; private set; }
            internal Action<AudioBgmResultV2> Respond { get; private set; }
        }

        private sealed class OwnerWorkItem
        {
            internal OwnerWorkItem(
                Action action,
                bool runDuringShutdown,
                ManualResetEventSlim completion)
            {
                Action = action;
                RunDuringShutdown = runDuringShutdown;
                Completion = completion;
            }

            internal Action Action { get; private set; }
            internal bool RunDuringShutdown { get; private set; }
            internal ManualResetEventSlim Completion { get; private set; }
            internal Exception Error { get; private set; }

            internal void Complete(Exception error)
            {
                Error = error;
                if (Completion != null) Completion.Set();
            }
        }
    }

    /// <summary>
    /// Caller-owned-memory adapter for the frozen C ABI.  The coordinator sees only
    /// typed managed values and cannot retain a native pointer after a call returns.
    /// </summary>
    internal sealed class AudioNativeV2Adapter :
        IAudioNativeV2,
        IAudioNativeQualificationObservationV2
    {
        private uint _sampleRate;

        public AudioNativeCapabilityResultV2 QueryCapability()
        {
            using (var arena = new NativeBufferArena())
            {
                AudioNativeV2.Capability capability =
                    CreateCapability(arena);
                AudioNativeV2.Result nativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.QueryCapability(
                    ref capability,
                    ref nativeResult);
                AudioNativeCallResultV2 result = ReadResult(
                    returned,
                    ref nativeResult,
                    arena,
                    AudioNativeV2.OperationQueryCapability,
                    null,
                    0uL,
                    "none");
                string capabilityDigest = null;
                bool accepted = result.IsOk &&
                    AudioNativeV2.IsProductionCapabilityAccepted(
                        ref capability) &&
                    arena.TryReadUtf8(
                        ref capability.capabilityDigestSha256,
                        out capabilityDigest);
                return new AudioNativeCapabilityResultV2(
                    accepted,
                    accepted ? capabilityDigest : null,
                    result);
            }
        }

        public AudioNativeInitializeResultV2 Initialize(
            string normalizedBasePath,
            string audioSessionId,
            ulong audioReadyGeneration)
        {
            using (var arena = new NativeBufferArena())
            {
                var command = new AudioNativeV2.InitializeCommand();
                Prefix(ref command.structSize,
                    ref command.abiMajor,
                    ref command.abiMinor,
                    Marshal.SizeOf<AudioNativeV2.InitializeCommand>());
                command.normalizedBasePath =
                    arena.CreateInputUtf16(normalizedBasePath);
                command.audioSessionId = arena.CreateInputUtf8(audioSessionId);
                command.audioReadyGeneration = audioReadyGeneration;
                command.executionIdentity = AudioNativeV2.ExecutionProduction;

                AudioNativeV2.RuntimeSnapshot runtime =
                    CreateRuntimeSnapshot(arena);
                AudioNativeV2.Result nativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.Initialize(
                    ref command,
                    ref runtime,
                    ref nativeResult);
                AudioNativeCallResultV2 result = ReadResult(
                    returned,
                    ref nativeResult,
                    arena,
                    AudioNativeV2.OperationInitialize,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");

                string actualSession;
                string deviceDigest = null;
                string deviceName = null;
                bool runtimePrefixAccepted =
                    AudioNativeV2.IsPrefixAccepted(
                        runtime.structSize,
                        runtime.abiMajor,
                        runtime.abiMinor,
                        (uint)Marshal.SizeOf<AudioNativeV2.RuntimeSnapshot>());
                bool sessionMatches = arena.TryReadUtf8(
                        ref runtime.audioSessionId,
                        out actualSession) &&
                    string.Equals(
                        audioSessionId,
                        actualSession,
                        StringComparison.Ordinal);
                bool returnedTupleValid = result != null &&
                    result.Category != AudioNativeV2.ResultAbiMismatch;
                bool runtimeTupleMatches = returnedTupleValid &&
                    runtimePrefixAccepted &&
                    runtime.audioReadyGeneration == audioReadyGeneration &&
                    runtime.deviceGeneration == result.DeviceGeneration &&
                    sessionMatches;
                bool ready = result.IsOk && runtimeTupleMatches &&
                    runtime.audioStatus == AudioNativeV2.AudioReady &&
                    runtime.deviceGeneration != 0uL &&
                    IsProductionBackend(runtime.selectedBackend) &&
                    runtime.sampleRate != 0u &&
                    runtime.channels != 0u &&
                    IsKnownSampleFormat(runtime.sampleFormat) &&
                    AudioNativeV2.IsPrefixAccepted(
                        runtime.lastStructuredFailure.structSize,
                        runtime.lastStructuredFailure.abiMajor,
                        runtime.lastStructuredFailure.abiMinor,
                        (uint)Marshal.SizeOf<AudioNativeV2.Result>()) &&
                    runtime.lastStructuredFailure.category ==
                        AudioNativeV2.ResultOk &&
                    arena.TryReadUtf8(
                        ref runtime.selectedDeviceIdDigest,
                        out deviceDigest) &&
                    IsSha256Hex(deviceDigest) &&
                    arena.TryReadUtf16(
                        ref runtime.selectedDeviceName,
                        out deviceName) &&
                    !string.IsNullOrWhiteSpace(deviceName);
                if (ready) _sampleRate = runtime.sampleRate;
                return new AudioNativeInitializeResultV2(
                    ready,
                    returnedTupleValid,
                    returnedTupleValid ? result.DeviceGeneration : 0uL,
                    runtime.selectedBackend,
                    ready ? deviceDigest : null,
                    ready ? deviceName : null,
                    runtime.sampleRate,
                    runtime.channels,
                    runtime.sampleFormat,
                    result);
            }
        }

        public AudioNativeRuntimeStateV2 QueryRuntime()
        {
            using (var arena = new NativeBufferArena())
            {
                AudioNativeV2.RuntimeSnapshot runtime =
                    CreateRuntimeSnapshot(arena);
                AudioNativeV2.Result nativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.QueryRuntime(
                    ref runtime,
                    ref nativeResult);
                AudioNativeCallResultV2 result = ReadResult(
                    returned,
                    ref nativeResult,
                    arena,
                    AudioNativeV2.OperationQueryRuntime,
                    null,
                    0uL,
                    "none");

                string actualSession = null;
                string deviceDigest = null;
                string deviceName = null;
                bool sessionReadable = arena.TryReadUtf8(
                    ref runtime.audioSessionId,
                    out actualSession);
                bool sessionShapeValid = string.IsNullOrEmpty(actualSession)
                    ? runtime.audioStatus == AudioNativeV2.AudioShutdown &&
                        runtime.audioReadyGeneration == 0uL &&
                        runtime.deviceGeneration == 0uL
                    : IsLowercaseUuidV4(actualSession) &&
                        runtime.audioReadyGeneration != 0uL &&
                        runtime.deviceGeneration != 0uL;
                bool deviceFieldsReadable = arena.TryReadUtf8(
                        ref runtime.selectedDeviceIdDigest,
                        out deviceDigest) &&
                    arena.TryReadUtf16(
                        ref runtime.selectedDeviceName,
                        out deviceName);
                bool readyDeviceShape =
                    runtime.audioStatus != AudioNativeV2.AudioReady ||
                    (IsProductionBackend(runtime.selectedBackend) &&
                     IsSha256Hex(deviceDigest) &&
                     !string.IsNullOrWhiteSpace(deviceName) &&
                     runtime.sampleRate != 0u &&
                     runtime.channels != 0u &&
                     IsKnownSampleFormat(runtime.sampleFormat));
                bool valid = result != null && result.IsOk &&
                    AudioNativeV2.IsPrefixAccepted(
                        runtime.structSize,
                        runtime.abiMajor,
                        runtime.abiMinor,
                        (uint)Marshal.SizeOf<AudioNativeV2.RuntimeSnapshot>()) &&
                    runtime.audioStatus >= AudioNativeV2.AudioInitializing &&
                    runtime.audioStatus <= AudioNativeV2.AudioShutdown &&
                    sessionReadable && sessionShapeValid &&
                    deviceFieldsReadable && readyDeviceShape &&
                    string.Equals(
                        result.AudioSessionId,
                        actualSession,
                        StringComparison.Ordinal) &&
                    result.AudioReadyGeneration ==
                        runtime.audioReadyGeneration &&
                    result.DeviceGeneration == runtime.deviceGeneration;
                return new AudioNativeRuntimeStateV2(
                    valid,
                    runtime.audioStatus,
                    actualSession,
                    runtime.audioReadyGeneration,
                    runtime.deviceGeneration,
                    runtime.selectedBackend,
                    deviceDigest,
                    deviceName,
                    runtime.sampleRate,
                    runtime.channels,
                    runtime.sampleFormat,
                    result);
            }
        }

        public AudioNativeCallResultV2 RebuildSfxCatalog(
            string audioSessionId,
            ulong audioReadyGeneration,
            IList<AudioCatalogItemV2> items)
        {
            if (items == null) throw new ArgumentNullException("items");
            using (var arena = new NativeBufferArena())
            {
                int itemSize = Marshal.SizeOf<AudioNativeV2.SfxCatalogItem>();
                IntPtr itemArray = arena.AllocateArray(itemSize, items.Count);
                for (int index = 0; index < items.Count; index++)
                {
                    AudioCatalogItemV2 item = items[index];
                    var nativeItem = new AudioNativeV2.SfxCatalogItem();
                    Prefix(ref nativeItem.structSize,
                        ref nativeItem.abiMajor,
                        ref nativeItem.abiMinor,
                        itemSize);
                    nativeItem.linkageId =
                        arena.CreateInputUtf8(item.LinkageId);
                    nativeItem.normalizedPath =
                        arena.CreateInputUtf16(item.NormalizedPath);
                    Marshal.StructureToPtr(
                        nativeItem,
                        IntPtr.Add(itemArray, checked(index * itemSize)),
                        false);
                }

                var command = new AudioNativeV2.SfxCatalogCommand();
                Prefix(ref command.structSize,
                    ref command.abiMajor,
                    ref command.abiMinor,
                    Marshal.SizeOf<AudioNativeV2.SfxCatalogCommand>());
                command.audioSessionId = arena.CreateInputUtf8(audioSessionId);
                command.audioReadyGeneration = audioReadyGeneration;
                if (!AudioNativeV2.TryCreateArrayBuffer(
                    itemArray,
                    (uint)itemSize,
                    (uint)items.Count,
                    (uint)items.Count,
                    out command.items))
                {
                    return ManagedFailure(
                        AudioNativeV2.ResultInternalError,
                        AudioNativeV2.OperationSfxRebuildCatalog,
                        AudioNativeV2.StageValidateCapacity,
                        audioSessionId,
                        audioReadyGeneration,
                        0uL,
                        "audio.catalog_capacity");
                }

                AudioNativeV2.Result nativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.RebuildSfxCatalog(
                    ref command,
                    ref nativeResult);
                return ReadResult(
                    returned,
                    ref nativeResult,
                    arena,
                    AudioNativeV2.OperationSfxRebuildCatalog,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");
            }
        }

        public AudioNativeCallResultV2 SubmitBgm(
            AudioNativeBgmCommandV2 value)
        {
            if (value == null) throw new ArgumentNullException("value");
            using (var arena = new NativeBufferArena())
            {
                var command = new AudioNativeV2.BgmCommand();
                Prefix(ref command.structSize,
                    ref command.abiMajor,
                    ref command.abiMinor,
                    Marshal.SizeOf<AudioNativeV2.BgmCommand>());
                command.wireRevision = AudioNativeV2.WireRevision;
                command.requestId = arena.CreateInputUtf8(value.RequestId);
                command.audioSessionId =
                    arena.CreateInputUtf8(value.AudioSessionId);
                command.audioReadyGeneration = value.AudioReadyGeneration;
                command.operation = value.Operation;
                command.normalizedPath = string.IsNullOrEmpty(
                    value.NormalizedPath)
                    ? arena.CreateEmptyInputUtf16()
                    : arena.CreateInputUtf16(value.NormalizedPath);
                command.loop = value.Loop
                    ? AudioNativeV2.True
                    : AudioNativeV2.False;
                command.volume = value.Volume;
                command.fadeSeconds = value.FadeSeconds;
                command.seekSeconds = value.SeekSeconds;

                AudioNativeV2.Result nativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.SubmitBgm(
                    ref command,
                    ref nativeResult);
                return ReadResult(
                    returned,
                    ref nativeResult,
                    arena,
                    value.Operation,
                    value.AudioSessionId,
                    value.AudioReadyGeneration,
                    "none");
            }
        }

        public AudioNativeCallResultV2 SubmitSfxBatch(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong batchSequence,
            IList<string> linkageIds,
            float volume)
        {
            if (linkageIds == null) throw new ArgumentNullException("linkageIds");
            using (var arena = new NativeBufferArena())
            {
                int itemSize = Marshal.SizeOf<AudioNativeV2.SfxPlayItem>();
                IntPtr itemArray = arena.AllocateArray(
                    itemSize,
                    linkageIds.Count);
                for (int index = 0; index < linkageIds.Count; index++)
                {
                    var nativeItem = new AudioNativeV2.SfxPlayItem();
                    Prefix(ref nativeItem.structSize,
                        ref nativeItem.abiMajor,
                        ref nativeItem.abiMinor,
                        itemSize);
                    nativeItem.linkageId =
                        arena.CreateInputUtf8(linkageIds[index]);
                    nativeItem.volume = volume;
                    Marshal.StructureToPtr(
                        nativeItem,
                        IntPtr.Add(itemArray, checked(index * itemSize)),
                        false);
                }

                var command = new AudioNativeV2.SfxBatchCommand();
                Prefix(ref command.structSize,
                    ref command.abiMajor,
                    ref command.abiMinor,
                    Marshal.SizeOf<AudioNativeV2.SfxBatchCommand>());
                command.wireRevision = AudioNativeV2.WireRevision;
                command.audioSessionId = arena.CreateInputUtf8(audioSessionId);
                command.audioReadyGeneration = audioReadyGeneration;
                command.batchSequence = batchSequence;
                if (!AudioNativeV2.TryCreateArrayBuffer(
                    itemArray,
                    (uint)itemSize,
                    (uint)linkageIds.Count,
                    (uint)linkageIds.Count,
                    out command.linkageIds))
                {
                    return ManagedFailure(
                        AudioNativeV2.ResultInternalError,
                        AudioNativeV2.OperationSfxPlayBatch,
                        AudioNativeV2.StageValidateCapacity,
                        audioSessionId,
                        audioReadyGeneration,
                        0uL,
                        "audio.sfx_capacity");
                }

                AudioNativeV2.SfxCounters counters = CreateSfxCounters(arena);
                AudioNativeV2.Result nativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.SubmitSfxBatch(
                    ref command,
                    ref counters,
                    ref nativeResult);
                AudioNativeCallResultV2 result = ReadResult(
                    returned,
                    ref nativeResult,
                    arena,
                    AudioNativeV2.OperationSfxPlayBatch,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");
                if (result.Category == AudioNativeV2.ResultAbiMismatch)
                    return result;

                string actualSession;
                if (!AudioNativeV2.IsPrefixAccepted(
                    counters.structSize,
                    counters.abiMajor,
                    counters.abiMinor,
                    (uint)Marshal.SizeOf<AudioNativeV2.SfxCounters>()) ||
                    counters.audioReadyGeneration != audioReadyGeneration ||
                    !arena.TryReadUtf8(
                        ref counters.audioSessionId,
                        out actualSession) ||
                    !string.Equals(
                        audioSessionId,
                        actualSession,
                        StringComparison.Ordinal))
                {
                    return ManagedFailure(
                        AudioNativeV2.ResultAbiMismatch,
                        AudioNativeV2.OperationSfxPlayBatch,
                        AudioNativeV2.StageValidateAbi,
                        audioSessionId,
                        audioReadyGeneration,
                        result.DeviceGeneration,
                        "audio.sfx_counter_tuple");
                }
                return result.WithSfxCounters(
                    new AudioNativeSfxCountersV2(
                        actualSession,
                        counters.audioReadyGeneration,
                        counters.preReadyDrops,
                        counters.recoveryDrops,
                        counters.staleGenerationDrops,
                        counters.unknownIdCount,
                        counters.throttledCount,
                        counters.startFailureCount,
                        counters.playedCount));
            }
        }

        public AudioNativeCallResultV2 SetGain(
            string audioSessionId,
            ulong audioReadyGeneration,
            uint operation,
            float gain)
        {
            using (var arena = new NativeBufferArena())
            {
                var command = new AudioNativeV2.GainCommand();
                Prefix(ref command.structSize,
                    ref command.abiMajor,
                    ref command.abiMinor,
                    Marshal.SizeOf<AudioNativeV2.GainCommand>());
                command.audioSessionId = arena.CreateInputUtf8(audioSessionId);
                command.audioReadyGeneration = audioReadyGeneration;
                command.operation = operation;
                command.gain = gain;
                AudioNativeV2.Result nativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.SetGain(
                    ref command,
                    ref nativeResult);
                return ReadResult(
                    returned,
                    ref nativeResult,
                    arena,
                    operation,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");
            }
        }

        public AudioNativeObservationV2 QueryBgmObservation(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration)
        {
            using (var arena = new NativeBufferArena())
            {
                AudioNativeV2.MeterSnapshot meter = CreateMeter(arena);
                meter.bus = AudioNativeV2.MeterBgmPreMaster;
                AudioNativeV2.Result meterNativeResult = CreateResult(arena);
                uint meterReturned = AudioNativeV2.QueryMeter(
                    ref meter,
                    ref meterNativeResult);
                AudioNativeCallResultV2 meterResult = ReadResult(
                    meterReturned,
                    ref meterNativeResult,
                    arena,
                    AudioNativeV2.OperationQueryMeter,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");

                AudioNativeV2.SourceSnapshot source = CreateSource(arena);
                AudioNativeV2.Result sourceNativeResult = CreateResult(arena);
                uint sourceReturned = AudioNativeV2.QueryBgmSource(
                    ref source,
                    ref sourceNativeResult);
                AudioNativeCallResultV2 sourceResult = ReadResult(
                    sourceReturned,
                    ref sourceNativeResult,
                    arena,
                    AudioNativeV2.OperationQueryRuntime,
                    audioSessionId,
                    audioReadyGeneration,
                    DecoderName(source.decoder));

                string meterSession;
                string sourceSession;
                bool valid = meterResult.IsOk && sourceResult.IsOk &&
                    IsMeterTupleValid(
                        ref meter,
                        arena,
                        AudioNativeV2.MeterBgmPreMaster,
                        audioSessionId,
                        audioReadyGeneration,
                        deviceGeneration,
                        out meterSession) &&
                    IsSourceTupleValid(
                        ref source,
                        arena,
                        audioSessionId,
                        audioReadyGeneration,
                        deviceGeneration,
                        out sourceSession);
                float cursorSeconds = _sampleRate == 0u
                    ? 0f
                    : (float)((double)source.cursorFrames / _sampleRate);
                float lengthSeconds = _sampleRate == 0u
                    ? 0f
                    : (float)((double)source.lengthFrames / _sampleRate);
                return new AudioNativeObservationV2(
                    valid,
                    valid ? ClampMeter(meter.peakLeft) : 0f,
                    valid ? ClampMeter(meter.peakRight) : 0f,
                    valid ? cursorSeconds : 0f,
                    valid ? lengthSeconds : 0f,
                    valid && source.playing == AudioNativeV2.True,
                    valid ? DecoderName(source.decoder) : "none");
            }
        }

        public AudioNativeObservationV2 QueryQualificationObservation(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration)
        {
            using (var arena = new NativeBufferArena())
            {
                AudioNativeV2.MeterSnapshot bgmMeter = CreateMeter(arena);
                bgmMeter.bus = AudioNativeV2.MeterBgmPreMaster;
                AudioNativeV2.Result bgmMeterNativeResult = CreateResult(arena);
                uint bgmMeterReturned = AudioNativeV2.QueryMeter(
                    ref bgmMeter,
                    ref bgmMeterNativeResult);
                AudioNativeCallResultV2 bgmMeterResult = ReadResult(
                    bgmMeterReturned,
                    ref bgmMeterNativeResult,
                    arena,
                    AudioNativeV2.OperationQueryMeter,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");

                AudioNativeV2.MeterSnapshot sfxMeter = CreateMeter(arena);
                sfxMeter.bus = AudioNativeV2.MeterSfxPreMaster;
                AudioNativeV2.Result sfxMeterNativeResult = CreateResult(arena);
                uint sfxMeterReturned = AudioNativeV2.QueryMeter(
                    ref sfxMeter,
                    ref sfxMeterNativeResult);
                AudioNativeCallResultV2 sfxMeterResult = ReadResult(
                    sfxMeterReturned,
                    ref sfxMeterNativeResult,
                    arena,
                    AudioNativeV2.OperationQueryMeter,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");

                AudioNativeV2.SourceSnapshot source = CreateSource(arena);
                AudioNativeV2.Result sourceNativeResult = CreateResult(arena);
                uint sourceReturned = AudioNativeV2.QueryBgmSource(
                    ref source,
                    ref sourceNativeResult);
                AudioNativeCallResultV2 sourceResult = ReadResult(
                    sourceReturned,
                    ref sourceNativeResult,
                    arena,
                    AudioNativeV2.OperationQueryRuntime,
                    audioSessionId,
                    audioReadyGeneration,
                    DecoderName(source.decoder));

                AudioNativeV2.SfxCounters counters =
                    CreateSfxCounters(arena);
                AudioNativeV2.Result countersNativeResult =
                    CreateResult(arena);
                uint countersReturned = AudioNativeV2.QuerySfxCounters(
                    ref counters,
                    ref countersNativeResult);
                AudioNativeCallResultV2 countersResult = ReadResult(
                    countersReturned,
                    ref countersNativeResult,
                    arena,
                    AudioNativeV2.OperationQueryRuntime,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");

                string bgmMeterSession;
                string sfxMeterSession;
                string sourceSession;
                string countersSession = null;
                bool countersValid = countersResult.IsOk &&
                    AudioNativeV2.IsPrefixAccepted(
                        counters.structSize,
                        counters.abiMajor,
                        counters.abiMinor,
                        (uint)Marshal.SizeOf<AudioNativeV2.SfxCounters>()) &&
                    counters.audioReadyGeneration == audioReadyGeneration &&
                    arena.TryReadUtf8(
                        ref counters.audioSessionId,
                        out countersSession) &&
                    string.Equals(
                        audioSessionId,
                        countersSession,
                        StringComparison.Ordinal);
                bool valid = bgmMeterResult.IsOk &&
                    sfxMeterResult.IsOk && sourceResult.IsOk &&
                    countersValid &&
                    IsMeterTupleValid(
                        ref bgmMeter,
                        arena,
                        AudioNativeV2.MeterBgmPreMaster,
                        audioSessionId,
                        audioReadyGeneration,
                        deviceGeneration,
                        out bgmMeterSession) &&
                    IsMeterTupleValid(
                        ref sfxMeter,
                        arena,
                        AudioNativeV2.MeterSfxPreMaster,
                        audioSessionId,
                        audioReadyGeneration,
                        deviceGeneration,
                        out sfxMeterSession) &&
                    IsSourceTupleValid(
                        ref source,
                        arena,
                        audioSessionId,
                        audioReadyGeneration,
                        deviceGeneration,
                        out sourceSession);
                float cursorSeconds = _sampleRate == 0u
                    ? 0f
                    : (float)((double)source.cursorFrames / _sampleRate);
                float lengthSeconds = _sampleRate == 0u
                    ? 0f
                    : (float)((double)source.lengthFrames / _sampleRate);
                return new AudioNativeObservationV2(
                    valid,
                    valid ? MeterObservation(ref bgmMeter) :
                        AudioNativeMeterObservationV2.Empty,
                    valid ? MeterObservation(ref sfxMeter) :
                        AudioNativeMeterObservationV2.Empty,
                    valid ? cursorSeconds : 0f,
                    valid ? lengthSeconds : 0f,
                    valid ? source.cursorFrames : 0uL,
                    valid ? source.lengthFrames : 0uL,
                    valid && source.playing == AudioNativeV2.True,
                    valid ? DecoderName(source.decoder) : "none",
                    valid ? ContainerName(source.container) : "none",
                    valid ? CodecName(source.codec) : "none",
                    valid ? source.startResult.category :
                        AudioNativeV2.ResultNotReady,
                    valid
                        ? new AudioNativeSfxCountersV2(
                            countersSession,
                            counters.audioReadyGeneration,
                            counters.preReadyDrops,
                            counters.recoveryDrops,
                            counters.staleGenerationDrops,
                            counters.unknownIdCount,
                            counters.throttledCount,
                            counters.startFailureCount,
                            counters.playedCount)
                        : null);
            }
        }

        public AudioNativeObservationV2 QueryBgmRecoveryObservation(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration)
        {
            using (var arena = new NativeBufferArena())
            {
                AudioNativeV2.SourceSnapshot source = CreateSource(arena);
                AudioNativeV2.Result sourceNativeResult = CreateResult(arena);
                uint sourceReturned = AudioNativeV2.QueryBgmSource(
                    ref source,
                    ref sourceNativeResult);
                AudioNativeCallResultV2 sourceResult = ReadResult(
                    sourceReturned,
                    ref sourceNativeResult,
                    arena,
                    AudioNativeV2.OperationQueryRuntime,
                    audioSessionId,
                    audioReadyGeneration,
                    DecoderName(source.decoder));

                string sourceSession;
                bool resultAccepted = sourceResult.IsOk ||
                    sourceResult.Category == AudioNativeV2.ResultNotReady;
                bool valid = resultAccepted &&
                    IsSourceTupleValid(
                        ref source,
                        arena,
                        audioSessionId,
                        audioReadyGeneration,
                        deviceGeneration,
                        out sourceSession);
                float cursorSeconds = _sampleRate == 0u
                    ? 0f
                    : (float)((double)source.cursorFrames / _sampleRate);
                float lengthSeconds = _sampleRate == 0u
                    ? 0f
                    : (float)((double)source.lengthFrames / _sampleRate);
                return new AudioNativeObservationV2(
                    valid,
                    0f,
                    0f,
                    valid ? cursorSeconds : 0f,
                    valid ? lengthSeconds : 0f,
                    valid && source.playing == AudioNativeV2.True,
                    valid ? DecoderName(source.decoder) : "none");
            }
        }

        public AudioRuntimeProbeResultV2 ProbeRuntimeCompatibility(
            string normalizedPath,
            ulong fileSizeBytes,
            long modifiedTimeUnixMilliseconds,
            string first64kSha256,
            string capabilityDigestSha256,
            string audioSessionId,
            ulong audioReadyGeneration)
        {
            using (var arena = new NativeBufferArena())
            {
                var command = new AudioNativeV2.RuntimeProbeCommand();
                Prefix(ref command.structSize,
                    ref command.abiMajor,
                    ref command.abiMinor,
                    Marshal.SizeOf<AudioNativeV2.RuntimeProbeCommand>());
                command.normalizedPath = arena.CreateInputUtf16(normalizedPath);
                command.fileSizeBytes = fileSizeBytes;
                command.modifiedTimeUnixMilliseconds =
                    modifiedTimeUnixMilliseconds;
                command.first64kSha256 = arena.CreateInputUtf8(first64kSha256);
                command.capabilityDigestSha256 =
                    arena.CreateInputUtf8(capabilityDigestSha256);
                command.probeContractRevision =
                    AudioNativeV2.ProbeContractRevision;
                command.maxWallMs = AudioNativeV2.RuntimeProbeMaxWallMs;
                command.maxDecodedFrames =
                    AudioNativeV2.RuntimeProbeMaxDecodedFrames;
                command.maxInputBytes = AudioNativeV2.RuntimeProbeMaxInputBytes;
                command.maxFileBytes = AudioNativeV2.RuntimeProbeMaxFileBytes;
                command.stableObservationCount =
                    AudioNativeV2.RuntimeProbeStableObservations;
                command.stableIntervalMs =
                    AudioNativeV2.RuntimeProbeStableIntervalMs;

                AudioNativeV2.ProbeResult probe = CreateProbeResult(arena);
                AudioNativeV2.Result outerNativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.ProbeRuntimeCompatibility(
                    ref command,
                    ref probe,
                    ref outerNativeResult);
                AudioNativeCallResultV2 outer = ReadResult(
                    returned,
                    ref outerNativeResult,
                    arena,
                    AudioNativeV2.OperationRuntimeProbe,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");
                AudioNativeCallResultV2 structured = ReadResult(
                    probe.structuredResult.category,
                    ref probe.structuredResult,
                    arena,
                    AudioNativeV2.OperationRuntimeProbe,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");

                bool valid =
                    outer.Category != AudioNativeV2.ResultAbiMismatch &&
                    structured.Category != AudioNativeV2.ResultAbiMismatch &&
                    AudioNativeV2.IsPrefixAccepted(
                        probe.structSize,
                        probe.abiMajor,
                        probe.abiMinor,
                        (uint)Marshal.SizeOf<AudioNativeV2.ProbeResult>()) &&
                    probe.outcome >=
                        AudioNativeV2.ProbeCompatibleSignalPresent &&
                    probe.outcome <=
                        AudioNativeV2.ProbeInconclusiveTimeoutNotUnsupported &&
                    probe.eofState == AudioNativeV2.EofNotRequired &&
                    probe.frames <=
                        AudioNativeV2.RuntimeProbeMaxDecodedFrames &&
                    probe.inputBytesRead <=
                        AudioNativeV2.RuntimeProbeMaxInputBytes &&
                    IsFiniteNonNegative(probe.durationSeconds) &&
                    IsFiniteNonNegative(probe.peak) &&
                    IsFiniteNonNegative(probe.rms);
                return new AudioRuntimeProbeResultV2(
                    valid,
                    probe.outcome,
                    probe.frames,
                    probe.durationSeconds,
                    probe.peak,
                    probe.rms,
                    probe.elapsedMs,
                    probe.inputBytesRead,
                    valid ? structured : outer);
            }
        }

        public AudioNativeCallResultV2 Shutdown(
            string audioSessionId,
            ulong audioReadyGeneration)
        {
            using (var arena = new NativeBufferArena())
            {
                var command = new AudioNativeV2.ShutdownCommand();
                Prefix(ref command.structSize,
                    ref command.abiMajor,
                    ref command.abiMinor,
                    Marshal.SizeOf<AudioNativeV2.ShutdownCommand>());
                command.audioSessionId = arena.CreateInputUtf8(audioSessionId);
                command.audioReadyGeneration = audioReadyGeneration;
                AudioNativeV2.Result nativeResult = CreateResult(arena);
                uint returned = AudioNativeV2.Shutdown(
                    ref command,
                    ref nativeResult);
                AudioNativeCallResultV2 result = ReadResult(
                    returned,
                    ref nativeResult,
                    arena,
                    AudioNativeV2.OperationShutdown,
                    audioSessionId,
                    audioReadyGeneration,
                    "none");
                _sampleRate = 0u;
                return result;
            }
        }

        private static AudioNativeV2.Capability CreateCapability(
            NativeBufferArena arena)
        {
            var value = new AudioNativeV2.Capability();
            Prefix(ref value.structSize,
                ref value.abiMajor,
                ref value.abiMinor,
                Marshal.SizeOf<AudioNativeV2.Capability>());
            Prefix(ref value.abiVersion.structSize,
                ref value.abiVersion.abiMajor,
                ref value.abiVersion.abiMinor,
                Marshal.SizeOf<AudioNativeV2.Version>());
            value.bridgeBuildId = arena.CreateOutputUtf8(257u);
            Prefix(ref value.miniaudioVersion.structSize,
                ref value.miniaudioVersion.abiMajor,
                ref value.miniaudioVersion.abiMinor,
                Marshal.SizeOf<AudioNativeV2.Version>());
            value.capabilityDigestSha256 = arena.CreateOutputUtf8(
                AudioNativeV2.Sha256HexCapacity);
            return value;
        }

        private static AudioNativeV2.RuntimeSnapshot CreateRuntimeSnapshot(
            NativeBufferArena arena)
        {
            var value = new AudioNativeV2.RuntimeSnapshot();
            Prefix(ref value.structSize,
                ref value.abiMajor,
                ref value.abiMinor,
                Marshal.SizeOf<AudioNativeV2.RuntimeSnapshot>());
            value.audioSessionId = arena.CreateOutputUtf8(
                AudioNativeV2.UuidV4TextCapacity);
            value.selectedDeviceIdDigest = arena.CreateOutputUtf8(
                AudioNativeV2.Sha256HexCapacity);
            value.selectedDeviceName = arena.CreateOutputUtf16(1025u);
            value.lastStructuredFailure = CreateResult(arena);
            return value;
        }

        private static AudioNativeV2.MeterSnapshot CreateMeter(
            NativeBufferArena arena)
        {
            var value = new AudioNativeV2.MeterSnapshot();
            Prefix(ref value.structSize,
                ref value.abiMajor,
                ref value.abiMinor,
                Marshal.SizeOf<AudioNativeV2.MeterSnapshot>());
            value.audioSessionId = arena.CreateOutputUtf8(
                AudioNativeV2.UuidV4TextCapacity);
            return value;
        }

        private static AudioNativeV2.SourceSnapshot CreateSource(
            NativeBufferArena arena)
        {
            var value = new AudioNativeV2.SourceSnapshot();
            Prefix(ref value.structSize,
                ref value.abiMajor,
                ref value.abiMinor,
                Marshal.SizeOf<AudioNativeV2.SourceSnapshot>());
            value.audioSessionId = arena.CreateOutputUtf8(
                AudioNativeV2.UuidV4TextCapacity);
            value.startResult = CreateResult(arena);
            return value;
        }

        private static AudioNativeV2.SfxCounters CreateSfxCounters(
            NativeBufferArena arena)
        {
            var value = new AudioNativeV2.SfxCounters();
            Prefix(ref value.structSize,
                ref value.abiMajor,
                ref value.abiMinor,
                Marshal.SizeOf<AudioNativeV2.SfxCounters>());
            value.audioSessionId = arena.CreateOutputUtf8(
                AudioNativeV2.UuidV4TextCapacity);
            return value;
        }

        private static AudioNativeV2.ProbeResult CreateProbeResult(
            NativeBufferArena arena)
        {
            var value = new AudioNativeV2.ProbeResult();
            Prefix(ref value.structSize,
                ref value.abiMajor,
                ref value.abiMinor,
                Marshal.SizeOf<AudioNativeV2.ProbeResult>());
            value.structuredResult = CreateResult(arena);
            return value;
        }

        private static AudioNativeV2.Result CreateResult(
            NativeBufferArena arena)
        {
            var value = new AudioNativeV2.Result();
            Prefix(ref value.structSize,
                ref value.abiMajor,
                ref value.abiMinor,
                Marshal.SizeOf<AudioNativeV2.Result>());
            value.audioSessionId = arena.CreateOutputUtf8(
                AudioNativeV2.UuidV4TextCapacity);
            value.messageKey = arena.CreateOutputUtf8(257u);
            return value;
        }

        private static AudioNativeCallResultV2 ReadResult(
            uint returned,
            ref AudioNativeV2.Result value,
            NativeBufferArena arena,
            uint expectedOperation,
            string expectedSessionId,
            ulong expectedReadyGeneration,
            string decoderBackend)
        {
            if (!AudioNativeV2.IsPrefixAccepted(
                    value.structSize,
                    value.abiMajor,
                    value.abiMinor,
                    (uint)Marshal.SizeOf<AudioNativeV2.Result>()) ||
                returned != value.category ||
                value.operation != expectedOperation)
            {
                return ManagedFailure(
                    AudioNativeV2.ResultAbiMismatch,
                    value.operation,
                    AudioNativeV2.StageValidateAbi,
                    expectedSessionId,
                    expectedReadyGeneration,
                    value.deviceGeneration,
                    "audio.native_result_invalid");
            }

            string actualSession = null;
            string messageKey = null;
            arena.TryReadUtf8(ref value.audioSessionId, out actualSession);
            arena.TryReadUtf8(ref value.messageKey, out messageKey);
            if (expectedSessionId != null &&
                (!string.Equals(
                    expectedSessionId,
                    actualSession,
                    StringComparison.Ordinal) ||
                    value.audioReadyGeneration != expectedReadyGeneration))
            {
                return ManagedFailure(
                    AudioNativeV2.ResultAbiMismatch,
                    value.operation,
                    AudioNativeV2.StageValidateSession,
                    expectedSessionId,
                    expectedReadyGeneration,
                    value.deviceGeneration,
                    "audio.native_result_tuple");
            }

            return new AudioNativeCallResultV2(
                value.category,
                value.operation,
                value.stage,
                value.rawMaResult,
                value.rawHresult,
                value.completionState,
                actualSession,
                value.audioReadyGeneration,
                value.deviceGeneration,
                messageKey,
                string.IsNullOrEmpty(decoderBackend)
                    ? "none"
                    : decoderBackend);
        }

        private static AudioNativeCallResultV2 ManagedFailure(
            uint category,
            uint operation,
            uint stage,
            string sessionId,
            ulong readyGeneration,
            ulong deviceGeneration,
            string messageKey)
        {
            return AudioNativeCallResultV2.Failure(
                category,
                operation,
                stage,
                sessionId,
                readyGeneration,
                deviceGeneration,
                messageKey);
        }

        private static bool IsMeterTupleValid(
            ref AudioNativeV2.MeterSnapshot value,
            NativeBufferArena arena,
            uint expectedBus,
            string expectedSession,
            ulong expectedReady,
            ulong expectedDevice,
            out string actualSession)
        {
            actualSession = null;
            return AudioNativeV2.IsPrefixAccepted(
                    value.structSize,
                    value.abiMajor,
                    value.abiMinor,
                    (uint)Marshal.SizeOf<AudioNativeV2.MeterSnapshot>()) &&
                value.bus == expectedBus &&
                value.audioReadyGeneration == expectedReady &&
                value.deviceGeneration == expectedDevice &&
                IsFiniteNonNegative(value.peakLeft) &&
                IsFiniteNonNegative(value.peakRight) &&
                IsFiniteNonNegative(value.rmsLeft) &&
                IsFiniteNonNegative(value.rmsRight) &&
                arena.TryReadUtf8(
                    ref value.audioSessionId,
                    out actualSession) &&
                string.Equals(
                    expectedSession,
                    actualSession,
                    StringComparison.Ordinal);
        }

        private static bool IsSourceTupleValid(
            ref AudioNativeV2.SourceSnapshot value,
            NativeBufferArena arena,
            string expectedSession,
            ulong expectedReady,
            ulong expectedDevice,
            out string actualSession)
        {
            actualSession = null;
            return AudioNativeV2.IsPrefixAccepted(
                    value.structSize,
                    value.abiMajor,
                    value.abiMinor,
                    (uint)Marshal.SizeOf<AudioNativeV2.SourceSnapshot>()) &&
                value.audioReadyGeneration == expectedReady &&
                value.deviceGeneration == expectedDevice &&
                (value.playing == AudioNativeV2.False ||
                    value.playing == AudioNativeV2.True) &&
                IsFiniteUnit(value.sourceGroupMasterGain) &&
                AudioNativeV2.IsPrefixAccepted(
                    value.startResult.structSize,
                    value.startResult.abiMajor,
                    value.startResult.abiMinor,
                    (uint)Marshal.SizeOf<AudioNativeV2.Result>()) &&
                value.startResult.category <=
                    AudioNativeV2.ResultInternalError &&
                value.startResult.completionState <=
                    AudioNativeV2.CompletionFailed &&
                arena.TryReadUtf8(
                    ref value.audioSessionId,
                    out actualSession) &&
                string.Equals(
                    expectedSession,
                    actualSession,
                    StringComparison.Ordinal);
        }

        private static void Prefix(
            ref uint structSize,
            ref uint abiMajor,
            ref uint abiMinor,
            int size)
        {
            structSize = checked((uint)size);
            abiMajor = AudioNativeV2.AbiMajor;
            abiMinor = AudioNativeV2.AbiMinor;
        }

        private static bool IsProductionBackend(uint backend)
        {
            return backend == AudioNativeV2.BackendWasapi ||
                backend == AudioNativeV2.BackendDirectSound ||
                backend == AudioNativeV2.BackendWinMm;
        }

        private static bool IsKnownSampleFormat(uint sampleFormat)
        {
            return sampleFormat == AudioNativeV2.SampleFormatF32 ||
                sampleFormat == AudioNativeV2.SampleFormatS16 ||
                sampleFormat == AudioNativeV2.SampleFormatS24 ||
                sampleFormat == AudioNativeV2.SampleFormatS32;
        }

        private static string DecoderName(ulong decoder)
        {
            if ((decoder & AudioNativeV2.DecoderBackendLibOpus) != 0uL)
                return "libopus";
            if ((decoder & AudioNativeV2.DecoderBackendMediaFoundation) != 0uL)
                return "media_foundation";
            if ((decoder & AudioNativeV2.DecoderBackendLibVorbis) != 0uL)
                return "libvorbis";
            if ((decoder & AudioNativeV2.DecoderBackendBuiltin) != 0uL)
                return "builtin";
            return "none";
        }

        private static string ContainerName(ulong container)
        {
            if ((container & AudioNativeV2.ContainerAdts) != 0uL)
                return "adts";
            if ((container & AudioNativeV2.ContainerMpeg4) != 0uL)
                return "mpeg4";
            if ((container & AudioNativeV2.ContainerOgg) != 0uL)
                return "ogg";
            if ((container & AudioNativeV2.ContainerNativeFlac) != 0uL)
                return "native_flac";
            if ((container & AudioNativeV2.ContainerMpegAudio) != 0uL)
                return "mpeg_audio";
            if ((container & AudioNativeV2.ContainerRiffWave) != 0uL)
                return "riff_wave";
            return "none";
        }

        private static string CodecName(ulong codec)
        {
            if ((codec & AudioNativeV2.CodecOpus) != 0uL)
                return "opus";
            if ((codec & AudioNativeV2.CodecAacLcOrHeAac) != 0uL)
                return "aac_lc_or_he_aac";
            if ((codec & AudioNativeV2.CodecVorbis) != 0uL)
                return "vorbis";
            if ((codec & AudioNativeV2.CodecFlac) != 0uL)
                return "flac";
            if ((codec & AudioNativeV2.CodecMpegAudioLayerIii) != 0uL)
                return "mpeg_audio_layer_iii";
            if ((codec & AudioNativeV2.CodecPcmOrIeeeFloat) != 0uL)
                return "pcm_or_ieee_float";
            return "none";
        }

        private static AudioNativeMeterObservationV2 MeterObservation(
            ref AudioNativeV2.MeterSnapshot meter)
        {
            return new AudioNativeMeterObservationV2(
                meter.peakLeft,
                meter.peakRight,
                meter.rmsLeft,
                meter.rmsRight,
                meter.clipCount,
                meter.frameCount,
                meter.underrunCount);
        }

        private static bool IsSha256Hex(string value)
        {
            if (value == null || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char current = value[index];
                if (!((current >= '0' && current <= '9') ||
                    (current >= 'A' && current <= 'F') ||
                    (current >= 'a' && current <= 'f')))
                {
                    return false;
                }
            }
            return true;
        }

        private static bool IsLowercaseUuidV4(string value)
        {
            Guid parsed;
            return value != null && value.Length == 36 &&
                value[14] == '4' &&
                (value[19] == '8' || value[19] == '9' ||
                 value[19] == 'a' || value[19] == 'b') &&
                Guid.TryParseExact(value, "D", out parsed) &&
                string.Equals(
                    parsed.ToString("D"),
                    value,
                    StringComparison.Ordinal);
        }

        private static float ClampMeter(float value)
        {
            if (float.IsNaN(value) || float.IsInfinity(value) || value < 0f)
                return 0f;
            return value > 1f ? 1f : value;
        }

        private static bool IsFiniteNonNegative(float value)
        {
            return !float.IsNaN(value) &&
                !float.IsInfinity(value) &&
                value >= 0f;
        }

        private static bool IsFiniteNonNegative(double value)
        {
            return !double.IsNaN(value) &&
                !double.IsInfinity(value) &&
                value >= 0d;
        }

        private static bool IsFiniteUnit(float value)
        {
            return IsFiniteNonNegative(value) && value <= 1f;
        }

        internal sealed class NativeBufferArena : IDisposable
        {
            private static readonly UTF8Encoding StrictUtf8 =
                new UTF8Encoding(false, true);
            private readonly List<NativeAllocation> _allocations =
                new List<NativeAllocation>();

            internal AudioNativeV2.Utf8Buffer CreateInputUtf8(string value)
            {
                if (value == null || value.IndexOf('\0') >= 0)
                    throw new ArgumentException("Invalid UTF-8 input.", "value");
                byte[] payload = StrictUtf8.GetBytes(value);
                IntPtr pointer = Allocate(checked(payload.Length + 1));
                Marshal.Copy(payload, 0, pointer, payload.Length);
                Marshal.WriteByte(pointer, payload.Length, (byte)0u);
                AudioNativeV2.Utf8Buffer result;
                if (!AudioNativeV2.TryCreateUtf8Buffer(
                    pointer,
                    checked((uint)payload.Length + 1u),
                    AudioNativeV2.BufferReadOnly,
                    out result))
                {
                    throw new InvalidOperationException("UTF-8 buffer rejected.");
                }
                result.lengthBytes = checked((uint)payload.Length);
                result.requiredBytes = 0u;
                return result;
            }

            internal AudioNativeV2.Utf16Buffer CreateInputUtf16(string value)
            {
                if (value == null || value.IndexOf('\0') >= 0)
                    throw new ArgumentException("Invalid UTF-16 input.", "value");
                IntPtr pointer = Allocate(checked((value.Length + 1) * 2));
                for (int index = 0; index < value.Length; index++)
                {
                    Marshal.WriteInt16(
                        pointer,
                        checked(index * 2),
                        unchecked((short)value[index]));
                }
                Marshal.WriteInt16(pointer, checked(value.Length * 2), 0);
                AudioNativeV2.Utf16Buffer result;
                if (!AudioNativeV2.TryCreateUtf16Buffer(
                    pointer,
                    checked((uint)value.Length + 1u),
                    AudioNativeV2.BufferReadOnly,
                    out result))
                {
                    throw new InvalidOperationException("UTF-16 buffer rejected.");
                }
                result.lengthCodeUnits = checked((uint)value.Length);
                result.requiredCodeUnits = 0u;
                return result;
            }

            internal AudioNativeV2.Utf16Buffer CreateEmptyInputUtf16()
            {
                return CreateInputUtf16(string.Empty);
            }

            internal AudioNativeV2.Utf8Buffer CreateOutputUtf8(uint capacity)
            {
                if (capacity == 0u) throw new ArgumentOutOfRangeException("capacity");
                IntPtr pointer = Allocate(checked((int)capacity));
                AudioNativeV2.Utf8Buffer result;
                if (!AudioNativeV2.TryCreateUtf8Buffer(
                    pointer,
                    capacity,
                    AudioNativeV2.BufferWriteOnly,
                    out result))
                {
                    throw new InvalidOperationException("UTF-8 output rejected.");
                }
                return result;
            }

            internal AudioNativeV2.Utf16Buffer CreateOutputUtf16(uint capacity)
            {
                if (capacity == 0u) throw new ArgumentOutOfRangeException("capacity");
                IntPtr pointer = Allocate(checked((int)capacity * 2));
                AudioNativeV2.Utf16Buffer result;
                if (!AudioNativeV2.TryCreateUtf16Buffer(
                    pointer,
                    capacity,
                    AudioNativeV2.BufferWriteOnly,
                    out result))
                {
                    throw new InvalidOperationException("UTF-16 output rejected.");
                }
                return result;
            }

            internal bool TryReadUtf8(
                ref AudioNativeV2.Utf8Buffer buffer,
                out string value)
            {
                value = null;
                if (!AudioNativeV2.IsPrefixAccepted(
                        buffer.structSize,
                        buffer.abiMajor,
                        buffer.abiMinor,
                        (uint)Marshal.SizeOf<AudioNativeV2.Utf8Buffer>()) ||
                    buffer.flags != AudioNativeV2.BufferWriteOnly ||
                    buffer.dataAddress == 0uL ||
                    buffer.capacityBytes > int.MaxValue ||
                    !OwnsExact(
                        buffer.dataAddress,
                        checked((int)buffer.capacityBytes)) ||
                    buffer.requiredBytes == 0u ||
                    buffer.requiredBytes > buffer.capacityBytes ||
                    buffer.lengthBytes + 1u != buffer.requiredBytes ||
                    buffer.lengthBytes > 4096u)
                {
                    return false;
                }
                IntPtr pointer = AddressToPointer(buffer.dataAddress);
                if (Marshal.ReadByte(pointer, checked((int)buffer.lengthBytes)) != 0)
                    return false;
                byte[] payload = new byte[(int)buffer.lengthBytes];
                Marshal.Copy(pointer, payload, 0, payload.Length);
                try
                {
                    value = StrictUtf8.GetString(payload);
                    return value.IndexOf('\0') < 0;
                }
                catch (DecoderFallbackException)
                {
                    return false;
                }
            }

            internal bool TryReadUtf16(
                ref AudioNativeV2.Utf16Buffer buffer,
                out string value)
            {
                value = null;
                if (!AudioNativeV2.IsPrefixAccepted(
                        buffer.structSize,
                        buffer.abiMajor,
                        buffer.abiMinor,
                        (uint)Marshal.SizeOf<AudioNativeV2.Utf16Buffer>()) ||
                    buffer.flags != AudioNativeV2.BufferWriteOnly ||
                    buffer.dataAddress == 0uL ||
                    buffer.capacityCodeUnits > int.MaxValue / 2u ||
                    !OwnsExact(
                        buffer.dataAddress,
                        checked((int)buffer.capacityCodeUnits * 2)) ||
                    buffer.requiredCodeUnits == 0u ||
                    buffer.requiredCodeUnits > buffer.capacityCodeUnits ||
                    buffer.lengthCodeUnits + 1u != buffer.requiredCodeUnits ||
                    buffer.lengthCodeUnits > 1024u)
                {
                    return false;
                }
                IntPtr pointer = AddressToPointer(buffer.dataAddress);
                if (Marshal.ReadInt16(
                    pointer,
                    checked((int)buffer.lengthCodeUnits * 2)) != 0)
                {
                    return false;
                }
                char[] payload = new char[(int)buffer.lengthCodeUnits];
                for (int index = 0; index < payload.Length; index++)
                {
                    payload[index] = unchecked((char)Marshal.ReadInt16(
                        pointer,
                        checked(index * 2)));
                }
                value = new string(payload);
                return value.IndexOf('\0') < 0;
            }

            internal IntPtr AllocateArray(int elementSize, int count)
            {
                if (elementSize <= 0 || count < 0)
                    throw new ArgumentOutOfRangeException();
                if (count == 0) return IntPtr.Zero;
                return Allocate(checked(elementSize * count));
            }

            private IntPtr Allocate(int bytes)
            {
                IntPtr pointer = Marshal.AllocHGlobal(bytes);
                _allocations.Add(new NativeAllocation(pointer, bytes));
                for (int index = 0; index < bytes; index++)
                    Marshal.WriteByte(pointer, index, (byte)0u);
                return pointer;
            }

            public void Dispose()
            {
                for (int index = _allocations.Count - 1; index >= 0; index--)
                {
                    Marshal.FreeHGlobal(_allocations[index].Pointer);
                }
                _allocations.Clear();
            }

            private bool OwnsExact(ulong address, int bytes)
            {
                IntPtr pointer = AddressToPointer(address);
                for (int index = 0; index < _allocations.Count; index++)
                {
                    NativeAllocation allocation = _allocations[index];
                    if (allocation.Pointer == pointer &&
                        allocation.Bytes == bytes)
                    {
                        return true;
                    }
                }
                return false;
            }

            private static IntPtr AddressToPointer(ulong value)
            {
                if (IntPtr.Size != sizeof(ulong))
                    throw new PlatformNotSupportedException();
                return new IntPtr(unchecked((long)value));
            }

            private sealed class NativeAllocation
            {
                internal NativeAllocation(IntPtr pointer, int bytes)
                {
                    Pointer = pointer;
                    Bytes = bytes;
                }

                internal IntPtr Pointer { get; private set; }
                internal int Bytes { get; private set; }
            }
        }
    }
}
