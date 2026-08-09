// CF7:ME MusicCatalog — content/capability driven BGM catalog projection.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Audio
{
    internal enum MusicCatalogProbeOutcomeV2
    {
        CompatibleSignalPresent,
        CompatibleSignalUnknown,
        InconclusiveTimeout,
        UnstableInput,
        Missing,
        UnsupportedContainer,
        UnsupportedCodec,
        Malformed,
        Truncated,
        IoError,
        AbiMismatch,
        NotReady,
        Throttled,
        InternalError
    }

    /// <summary>
    /// Frozen input handed to the runtime-probe adapter.  CacheKey is deliberately
    /// included so the adapter/caller can recompute and audit the exact cache identity.
    /// </summary>
    internal sealed class MusicCatalogProbeInputV2
    {
        internal MusicCatalogProbeInputV2(
            string normalizedPath,
            ulong fileSizeBytes,
            long modifiedTimeUtcTicks,
            long modifiedTimeUnixMilliseconds,
            string first64kSha256,
            string capabilityDigest,
            string cacheKey,
            string hintExtension,
            string detectedDecoder,
            string detectedContainer,
            string detectedCodec,
            bool extensionMismatch,
            uint stableObservationCount,
            uint stableIntervalMilliseconds,
            ulong maxFileBytes,
            uint firstHashBytes,
            int maxWallMilliseconds,
            ulong maxInputBytes,
            ulong maxDecodedFrames,
            uint probeContractRevision)
        {
            NormalizedPath = normalizedPath;
            FileSizeBytes = fileSizeBytes;
            ModifiedTimeUtcTicks = modifiedTimeUtcTicks;
            ModifiedTimeUnixMilliseconds = modifiedTimeUnixMilliseconds;
            First64kSha256 = first64kSha256;
            CapabilityDigest = capabilityDigest;
            CacheKey = cacheKey;
            HintExtension = hintExtension;
            DetectedDecoder = detectedDecoder;
            DetectedContainer = detectedContainer;
            DetectedCodec = detectedCodec;
            ExtensionMismatch = extensionMismatch;
            StableObservationCount = stableObservationCount;
            StableIntervalMilliseconds = stableIntervalMilliseconds;
            MaxFileBytes = maxFileBytes;
            FirstHashBytes = firstHashBytes;
            MaxWallMilliseconds = maxWallMilliseconds;
            MaxInputBytes = maxInputBytes;
            MaxDecodedFrames = maxDecodedFrames;
            ProbeContractRevision = probeContractRevision;
        }

        public string NormalizedPath { get; private set; }
        public ulong FileSizeBytes { get; private set; }
        public long ModifiedTimeUtcTicks { get; private set; }
        public long ModifiedTimeUnixMilliseconds { get; private set; }
        public string First64kSha256 { get; private set; }
        public string CapabilityDigest { get; private set; }
        public string CacheKey { get; private set; }
        public string HintExtension { get; private set; }
        public string DetectedDecoder { get; private set; }
        public string DetectedContainer { get; private set; }
        public string DetectedCodec { get; private set; }
        public bool ExtensionMismatch { get; private set; }
        public uint StableObservationCount { get; private set; }
        public uint StableIntervalMilliseconds { get; private set; }
        public ulong MaxFileBytes { get; private set; }
        public uint FirstHashBytes { get; private set; }
        public int MaxWallMilliseconds { get; private set; }
        public ulong MaxInputBytes { get; private set; }
        public ulong MaxDecodedFrames { get; private set; }
        public uint ProbeContractRevision { get; private set; }
    }

    internal sealed class MusicCatalogProbeResultV2
    {
        internal MusicCatalogProbeResultV2(
            MusicCatalogProbeOutcomeV2 outcome,
            string cacheKey,
            string capabilityDigest,
            bool capabilityMatched)
        {
            Outcome = outcome;
            CacheKey = cacheKey;
            CapabilityDigest = capabilityDigest;
            CapabilityMatched = capabilityMatched;
        }

        public MusicCatalogProbeOutcomeV2 Outcome { get; private set; }
        public string CacheKey { get; private set; }
        public string CapabilityDigest { get; private set; }
        public bool CapabilityMatched { get; private set; }

        internal static MusicCatalogProbeResultV2 CompatibleSignalPresent(
            MusicCatalogProbeInputV2 input)
        {
            return new MusicCatalogProbeResultV2(
                MusicCatalogProbeOutcomeV2.CompatibleSignalPresent,
                input.CacheKey,
                input.CapabilityDigest,
                true);
        }

        internal static MusicCatalogProbeResultV2 CompatibleSignalUnknown(
            MusicCatalogProbeInputV2 input)
        {
            return new MusicCatalogProbeResultV2(
                MusicCatalogProbeOutcomeV2.CompatibleSignalUnknown,
                input.CacheKey,
                input.CapabilityDigest,
                true);
        }

        internal static MusicCatalogProbeResultV2 InconclusiveTimeout(
            MusicCatalogProbeInputV2 input)
        {
            return new MusicCatalogProbeResultV2(
                MusicCatalogProbeOutcomeV2.InconclusiveTimeout,
                input.CacheKey,
                input.CapabilityDigest,
                true);
        }
    }

    internal sealed class MusicCatalogQualificationSnapshotV2
    {
        internal MusicCatalogQualificationSnapshotV2(
            int revision,
            bool isComplete,
            string capabilityDigest,
            int available,
            int probing,
            int unavailable)
        {
            Revision = revision;
            IsComplete = isComplete;
            CapabilityDigest = capabilityDigest;
            Available = available;
            Probing = probing;
            Unavailable = unavailable;
        }

        public int Revision { get; private set; }
        public bool IsComplete { get; private set; }
        public string CapabilityDigest { get; private set; }
        public int Available { get; private set; }
        public int Probing { get; private set; }
        public int Unavailable { get; private set; }

        internal bool IsCompleteForCapability(string capabilityDigest)
        {
            return IsComplete && IsSha256HexValue(capabilityDigest) &&
                string.Equals(
                    CapabilityDigest,
                    capabilityDigest,
                    StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsSha256HexValue(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                if ((character < '0' || character > '9') &&
                    (character < 'a' || character > 'f') &&
                    (character < 'A' || character > 'F'))
                {
                    return false;
                }
            }
            return true;
        }
    }

    /// <summary>
    /// One atomic catalog/qualification projection.  Publisher code can bind the
    /// exact JSON it sends to the same revision and capability decision it gates.
    /// </summary>
    internal sealed class MusicCatalogProjectionV2
    {
        internal MusicCatalogProjectionV2(
            string catalogJson,
            MusicCatalogQualificationSnapshotV2 qualification)
        {
            CatalogJson = catalogJson;
            Qualification = qualification;
        }

        public string CatalogJson { get; private set; }
        public MusicCatalogQualificationSnapshotV2 Qualification
        {
            get;
            private set;
        }
    }

    internal enum MusicCatalogReadyBarrierPhaseV2
    {
        Started,
        Completed,
        Failed
    }

    internal sealed class MusicCatalogReadyBarrierChangeV2
    {
        internal MusicCatalogReadyBarrierChangeV2(
            int revision,
            string capabilityDigest,
            MusicCatalogReadyBarrierPhaseV2 phase)
        {
            Revision = revision;
            CapabilityDigest = capabilityDigest;
            Phase = phase;
        }

        public int Revision { get; private set; }
        public string CapabilityDigest { get; private set; }
        public MusicCatalogReadyBarrierPhaseV2 Phase { get; private set; }
    }

    /// <summary>
    /// Narrow asynchronous/background port.  MusicCatalog owns filesystem stability,
    /// hashing, caching and timeout; the adapter owns only the bounded runtime probe.
    /// </summary>
    internal interface IMusicCatalogRuntimeProbePortV2
    {
        string CapabilityDigest { get; }

        Task<MusicCatalogProbeResultV2> ProbeAsync(
            MusicCatalogProbeInputV2 input,
            CancellationToken cancellationToken);
    }

    internal sealed class MusicCatalogProbePolicyV2
    {
        internal const uint ProductionStableObservationCount = 2u;
        internal const uint ProductionContractRevision = 1u;

        internal static readonly MusicCatalogProbePolicyV2 Production =
            new MusicCatalogProbePolicyV2(
                TimeSpan.FromMilliseconds(1000),
                TimeSpan.FromMilliseconds(2000),
                TimeSpan.FromMilliseconds(2250),
                536870912L,
                65536,
                8388608UL,
                96000UL,
                1,
                ProductionContractRevision);

        internal MusicCatalogProbePolicyV2(
            TimeSpan stabilityInterval,
            TimeSpan probeMaxWall,
            TimeSpan managedAwaitTimeout,
            long maxFileBytes,
            int firstHashBytes,
            ulong maxInputBytes,
            ulong maxDecodedFrames,
            int maxConcurrentProbes,
            uint contractRevision)
        {
            if (stabilityInterval < TimeSpan.Zero)
                throw new ArgumentOutOfRangeException("stabilityInterval");
            if (probeMaxWall <= TimeSpan.Zero)
                throw new ArgumentOutOfRangeException("probeMaxWall");
            if (managedAwaitTimeout < probeMaxWall)
                throw new ArgumentOutOfRangeException("managedAwaitTimeout");
            if (maxFileBytes <= 0)
                throw new ArgumentOutOfRangeException("maxFileBytes");
            if (firstHashBytes <= 0)
                throw new ArgumentOutOfRangeException("firstHashBytes");
            if (maxInputBytes == 0UL)
                throw new ArgumentOutOfRangeException("maxInputBytes");
            if (maxDecodedFrames == 0UL)
                throw new ArgumentOutOfRangeException("maxDecodedFrames");
            if (maxConcurrentProbes <= 0)
                throw new ArgumentOutOfRangeException("maxConcurrentProbes");
            if (contractRevision == 0u)
                throw new ArgumentException(
                    "Probe contract revision is required.",
                    "contractRevision");

            StabilityInterval = stabilityInterval;
            ProbeMaxWall = probeMaxWall;
            ManagedAwaitTimeout = managedAwaitTimeout;
            MaxFileBytes = maxFileBytes;
            FirstHashBytes = firstHashBytes;
            MaxInputBytes = maxInputBytes;
            MaxDecodedFrames = maxDecodedFrames;
            MaxConcurrentProbes = maxConcurrentProbes;
            ContractRevision = contractRevision;
        }

        internal TimeSpan StabilityInterval { get; private set; }
        internal TimeSpan ProbeMaxWall { get; private set; }
        internal TimeSpan ManagedAwaitTimeout { get; private set; }
        internal long MaxFileBytes { get; private set; }
        internal int FirstHashBytes { get; private set; }
        internal ulong MaxInputBytes { get; private set; }
        internal ulong MaxDecodedFrames { get; private set; }
        internal int MaxConcurrentProbes { get; private set; }
        internal uint ContractRevision { get; private set; }
    }

    internal sealed class TrackInfo
    {
        internal TrackInfo(
            string title,
            string url,
            string album,
            int fadeDuration,
            int baseVolume,
            int weight,
            bool isRegistered,
            string fullPath,
            string availability,
            string reason,
            long observedSize,
            long observedMtimeUtcTicks,
            string first64kSha256,
            string cacheKey)
        {
            Title = title;
            Url = url;
            Album = album;
            FadeDuration = fadeDuration;
            BaseVolume = baseVolume;
            Weight = weight;
            IsRegistered = isRegistered;
            FullPath = fullPath;
            Availability = availability;
            Reason = reason;
            ObservedSize = observedSize;
            ObservedMtimeUtcTicks = observedMtimeUtcTicks;
            First64kSha256 = first64kSha256;
            CacheKey = cacheKey;
        }

        public string Title { get; private set; }
        public string Url { get; private set; }
        public string Album { get; private set; }
        public int FadeDuration { get; private set; }
        public int BaseVolume { get; private set; }
        public int Weight { get; private set; }
        public bool IsRegistered { get; private set; }
        internal string FullPath { get; private set; }
        public string Availability { get; private set; }
        public string Reason { get; private set; }
        internal long ObservedSize { get; private set; }
        internal long ObservedMtimeUtcTicks { get; private set; }
        internal string First64kSha256 { get; private set; }
        internal string CacheKey { get; private set; }

        internal TrackInfo WithProbeProjection(
            string availability,
            string reason,
            MusicCatalog.FileObservation observation,
            string first64kSha256,
            string cacheKey)
        {
            return new TrackInfo(
                Title,
                Url,
                Album,
                FadeDuration,
                BaseVolume,
                Weight,
                IsRegistered,
                FullPath,
                availability,
                reason,
                observation != null && observation.Exists
                    ? observation.Size
                    : -1L,
                observation != null && observation.Exists
                    ? observation.MtimeUtcTicks
                    : 0L,
                first64kSha256,
                cacheKey);
        }

        internal bool SameProjection(TrackInfo other)
        {
            return other != null &&
                string.Equals(Title, other.Title, StringComparison.Ordinal) &&
                string.Equals(Url, other.Url, StringComparison.Ordinal) &&
                string.Equals(Album, other.Album, StringComparison.Ordinal) &&
                FadeDuration == other.FadeDuration &&
                BaseVolume == other.BaseVolume &&
                Weight == other.Weight &&
                string.Equals(
                    Availability,
                    other.Availability,
                    StringComparison.Ordinal) &&
                string.Equals(Reason, other.Reason, StringComparison.Ordinal);
        }
    }

    /// <summary>
    /// Merges registered and discovered BGM candidates.  Extension is discovery hint
    /// only; availability comes from one stable-input, capability-bound runtime probe.
    /// Every publication replaces one immutable snapshot under a lock.
    /// </summary>
    internal sealed class MusicCatalog : IDisposable
    {
        internal const string AvailabilityAvailable = "available";
        internal const string AvailabilityProbing = "probing";
        internal const string AvailabilityUnavailable = "unavailable";

        internal const string ReasonPendingProbe = "pending_probe";
        internal const string ReasonMissing = "missing";
        internal const string ReasonUnstableInput = "unstable_input";
        internal const string ReasonInconclusiveTimeout = "inconclusive_timeout";
        internal const string ReasonCompatibleSignalPresent =
            "compatible_signal_present";
        internal const string ReasonCompatibleSignalUnknown =
            "compatible_signal_unknown";
        internal const string ReasonExtensionMismatch = "extension_mismatch";

        internal const string DecoderBuiltin = "builtin";
        internal const string DecoderLibVorbis = "libvorbis";
        internal const string DecoderLibOpus = "libopus";
        internal const string DecoderMediaFoundation = "media_foundation";
        internal const string ContainerRiffWave = "riff_wave";
        internal const string ContainerMpegAudio = "mpeg_audio";
        internal const string ContainerNativeFlac = "native_flac";
        internal const string ContainerOgg = "ogg";
        internal const string ContainerMpeg4 = "mpeg4";
        internal const string ContainerAdts = "adts";
        internal const string CodecPcmOrIeeeFloat = "pcm_or_ieee_float";
        internal const string CodecMpegAudioLayerIII = "mpeg_audio_layer_iii";
        internal const string CodecFlac = "flac";
        internal const string CodecVorbis = "vorbis";
        internal const string CodecAacLcOrHeAac = "aac_lc_or_he_aac";
        internal const string CodecOpus = "opus";

        private static readonly string[] AudioHintExtensions =
        {
            ".wav", ".mp3", ".flac", ".ogg", ".m4a",
            ".mp4", ".aac", ".adts", ".opus"
        };

        private const int DefaultFade = 20;
        private const int DefaultVolume = 100;
        private const int DefaultWeight = 100;
        private const int WatchDebounceMilliseconds = 500;

        private readonly string _projectRoot;
        private readonly string _soundsDir;
        private readonly string _soundsPrefix;
        private readonly IMusicCatalogRuntimeProbePortV2 _probePort;
        private readonly MusicCatalogProbePolicyV2 _policy;
        private readonly object _sync = new object();
        private readonly SemaphoreSlim _refreshSerial = new SemaphoreSlim(1, 1);
        private readonly CancellationTokenSource _lifetime =
            new CancellationTokenSource();
        private readonly Dictionary<string, ProbeProjection> _probeCache =
            new Dictionary<string, ProbeProjection>(StringComparer.Ordinal);
        private readonly List<Task> _backgroundTasks = new List<Task>();
        private readonly HashSet<string> _dirtyPaths =
            new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        private CatalogSnapshot _snapshot;
        private CancellationTokenSource _activeRefresh;
        private Task _latestRefresh = Task.CompletedTask;
        private FileSystemWatcher _watcher;
        private Timer _watchDebounce;
        private int _refreshRevision;
        private bool _forceFullWatchRefresh;
        private bool _disposed;

        /// <summary>Hot-reload delta. Changed projections are carried in added.</summary>
        public event Action<string> CatalogChanged;

        /// <summary>
        /// Typed qualification boundary for Coordinator/Publisher gating.  A start
        /// notification (IsComplete=false) always precedes projection deltas; a final
        /// notification is bound to one frozen capability digest and revision.
        /// </summary>
        internal event Action<MusicCatalogQualificationSnapshotV2>
            QualificationChangedV2;

        /// <summary>
        /// Hot filesystem/catalog rebuild boundary.  Coordinator-requested initial or
        /// capability requalification already owns a ready epoch and is deliberately
        /// excluded; watcher/test refreshes use this event to revoke and later restore
        /// admission around their exact revision.
        /// </summary>
        internal event Action<MusicCatalogReadyBarrierChangeV2>
            ReadyBarrierChangedV2;

        public MusicCatalog(string projectRoot)
            : this(
                projectRoot,
                UnavailableMusicCatalogProbePort.Instance,
                MusicCatalogProbePolicyV2.Production,
                true)
        {
        }

        internal MusicCatalog(
            string projectRoot,
            IMusicCatalogRuntimeProbePortV2 probePort)
            : this(
                projectRoot,
                probePort,
                MusicCatalogProbePolicyV2.Production,
                true)
        {
        }

        internal MusicCatalog(
            string projectRoot,
            IMusicCatalogRuntimeProbePortV2 probePort,
            MusicCatalogProbePolicyV2 policy,
            bool startWatcher)
        {
            if (string.IsNullOrWhiteSpace(projectRoot))
                throw new ArgumentException("Project root is required.", "projectRoot");
            if (probePort == null) throw new ArgumentNullException("probePort");
            if (policy == null) throw new ArgumentNullException("policy");

            _projectRoot = NormalizePath(Path.GetFullPath(projectRoot));
            _soundsDir = NormalizePath(Path.Combine(_projectRoot, "sounds"));
            _soundsPrefix = _soundsDir.TrimEnd('/') + "/";
            _probePort = probePort;
            _policy = policy;

            _snapshot = DiscoverSnapshot(
                CatalogSnapshot.Empty,
                null,
                true,
                0,
                ReadCapabilityDigest());

            LogManager.Log(
                "[MusicCatalog] Discovery: " + _snapshot.Tracks.Count +
                " tracks, " + _snapshot.Albums.Count + " albums");

            if (startWatcher) StartWatcher();
            _latestRefresh = ScheduleRefresh(false, null, true, false);
        }

        internal static string[] GetAudioHintExtensionsForTests()
        {
            return (string[])AudioHintExtensions.Clone();
        }

        internal Task WaitForIdleForTestsAsync()
        {
            lock (_sync) return _latestRefresh;
        }

        internal Task WaitForCurrentQualificationAsync()
        {
            lock (_sync) return _latestRefresh;
        }

        internal Task RequalifyForCapabilityChangeAsync()
        {
            return ScheduleRefresh(true, null, true, false);
        }

        internal MusicCatalogQualificationSnapshotV2 QualificationSnapshotV2
        {
            get
            {
                lock (_sync) return _snapshot.ToQualificationSnapshot();
            }
        }

        internal Task RefreshForTestsAsync()
        {
            return ScheduleRefresh(true, null, true, true);
        }

        internal static string BuildProbeCacheKey(
            string normalizedPath,
            long size,
            long modifiedTimeUtcTicks,
            string first64kSha256,
            string capabilityDigest,
            uint contractRevision)
        {
            if (string.IsNullOrEmpty(normalizedPath) || size < 0L ||
                !IsSha256Hex(first64kSha256) ||
                !IsSha256Hex(capabilityDigest) ||
                contractRevision == 0u)
            {
                return null;
            }

            string canonical =
                contractRevision.ToString(CultureInfo.InvariantCulture) + "\n" +
                NormalizePath(normalizedPath).ToLowerInvariant() + "\n" +
                size.ToString(CultureInfo.InvariantCulture) + "\n" +
                modifiedTimeUtcTicks.ToString(CultureInfo.InvariantCulture) + "\n" +
                first64kSha256.ToLowerInvariant() + "\n" +
                capabilityDigest.ToLowerInvariant();
            return Sha256Hex(Encoding.UTF8.GetBytes(canonical));
        }

        /// <summary>Full atomic snapshot for Flash/Web projection.</summary>
        public string GetFullCatalogJson()
        {
            return GetProjectionV2().CatalogJson;
        }

        /// <summary>
        /// Authoritative Jukebox admission check.  Individual track state is not enough:
        /// while a hot refresh owns the ready barrier the prior snapshot can still carry
        /// "available", so the whole qualification snapshot must also be complete.
        /// </summary>
        internal bool IsTrackAvailableForPlayback(string title)
        {
            if (string.IsNullOrEmpty(title)) return false;

            CatalogSnapshot snapshot;
            lock (_sync) snapshot = _snapshot;
            if (snapshot == null || !snapshot.QualificationComplete) return false;

            TrackInfo track;
            return snapshot.Tracks.TryGetValue(title, out track) &&
                track != null &&
                string.Equals(track.Title, title, StringComparison.Ordinal) &&
                string.Equals(
                    track.Availability,
                    AvailabilityAvailable,
                    StringComparison.Ordinal);
        }

        internal MusicCatalogProjectionV2 GetProjectionV2()
        {
            CatalogSnapshot snapshot;
            lock (_sync) snapshot = _snapshot;
            return new MusicCatalogProjectionV2(
                BuildFullCatalogJson(snapshot),
                snapshot.ToQualificationSnapshot());
        }

        private Task ScheduleRefresh(
            bool notify,
            ISet<string> dirtyPaths,
            bool forceFull,
            bool ownsReadyBarrier)
        {
            HashSet<string> dirtyCopy = dirtyPaths == null
                ? new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                : new HashSet<string>(dirtyPaths, StringComparer.OrdinalIgnoreCase);
            CancellationTokenSource refresh;
            int revision;
            Task task;
            lock (_sync)
            {
                if (_disposed) return Task.CompletedTask;
                if (_activeRefresh != null) _activeRefresh.Cancel();
                _activeRefresh = CancellationTokenSource.CreateLinkedTokenSource(
                    _lifetime.Token);
                refresh = _activeRefresh;
                revision = ++_refreshRevision;
                task = Task.Run(
                    () => RunRefreshAsync(
                        revision,
                        notify,
                        dirtyCopy,
                        forceFull,
                        ownsReadyBarrier,
                        refresh.Token),
                    refresh.Token);
                _latestRefresh = task;
                _backgroundTasks.Add(task);
            }
            task.ContinueWith(
                completed => CompleteBackgroundTask(completed),
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
            return task;
        }

        private async Task RunRefreshAsync(
            int revision,
            bool notify,
            ISet<string> dirtyPaths,
            bool forceFull,
            bool ownsReadyBarrier,
            CancellationToken cancellationToken)
        {
            bool readyBarrierStarted = false;
            string capabilityDigest = null;
            await _refreshSerial.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                CatalogSnapshot previous;
                lock (_sync) previous = _snapshot;
                capabilityDigest = ReadCapabilityDigest();
                if (ownsReadyBarrier)
                {
                    FireReadyBarrierChanged(new MusicCatalogReadyBarrierChangeV2(
                        revision,
                        capabilityDigest,
                        MusicCatalogReadyBarrierPhaseV2.Started));
                    readyBarrierStarted = true;
                }
                bool rebuildAll = forceFull || !string.Equals(
                    previous.CapabilityDigest,
                    capabilityDigest,
                    StringComparison.OrdinalIgnoreCase);

                CatalogSnapshot discovered = DiscoverSnapshot(
                    previous,
                    dirtyPaths,
                    rebuildAll,
                    revision,
                    capabilityDigest);
                PublishSnapshot(discovered, revision, notify);

                CatalogSnapshot qualified = await QualifySnapshotAsync(
                    discovered,
                    capabilityDigest,
                    cancellationToken).ConfigureAwait(false);
                PublishSnapshot(qualified, revision, notify);
                if (readyBarrierStarted && IsCurrentRefresh(revision))
                {
                    FireReadyBarrierChanged(new MusicCatalogReadyBarrierChangeV2(
                        revision,
                        capabilityDigest,
                        MusicCatalogReadyBarrierPhaseV2.Completed));
                }
            }
            catch (OperationCanceledException)
            {
                // Newer hot reload or Dispose owns the next state.
                if (readyBarrierStarted && IsCurrentRefresh(revision))
                {
                    FireReadyBarrierChanged(new MusicCatalogReadyBarrierChangeV2(
                        revision,
                        capabilityDigest,
                        MusicCatalogReadyBarrierPhaseV2.Failed));
                }
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[MusicCatalog] Background refresh failed: " +
                    ex.GetType().Name);
                if (readyBarrierStarted && IsCurrentRefresh(revision))
                {
                    FireReadyBarrierChanged(new MusicCatalogReadyBarrierChangeV2(
                        revision,
                        capabilityDigest,
                        MusicCatalogReadyBarrierPhaseV2.Failed));
                }
            }
            finally
            {
                _refreshSerial.Release();
            }
        }

        private CatalogSnapshot DiscoverSnapshot(
            CatalogSnapshot previous,
            ISet<string> dirtyPaths,
            bool forceFull,
            int revision,
            string capabilityDigest)
        {
            var tracks = new Dictionary<string, TrackInfo>(
                StringComparer.OrdinalIgnoreCase);
            var urls = new Dictionary<string, string>(
                StringComparer.OrdinalIgnoreCase);

            ParseRegisteredTracks(tracks, urls, previous, dirtyPaths, forceFull);
            ScanDiscoveredTracks(tracks, urls, previous, dirtyPaths, forceFull);
            return CatalogSnapshot.Create(
                tracks.Values,
                revision,
                false,
                capabilityDigest);
        }

        private void ParseRegisteredTracks(
            IDictionary<string, TrackInfo> tracks,
            IDictionary<string, string> urls,
            CatalogSnapshot previous,
            ISet<string> dirtyPaths,
            bool forceFull)
        {
            string xmlPath = Path.Combine(_projectRoot, "sounds", "bgm_list.xml");
            if (!File.Exists(xmlPath)) return;

            try
            {
                var doc = new XmlDocument();
                doc.Load(xmlPath);
                XmlNodeList nodes = doc.SelectNodes("/data/music");
                if (nodes == null) return;

                for (int index = 0; index < nodes.Count; index++)
                {
                    XmlNode node = nodes[index];
                    string title = GetChildText(node, "title");
                    string url = NormalizeUrl(GetChildText(node, "url"));
                    if (string.IsNullOrEmpty(title) || string.IsNullOrEmpty(url) ||
                        string.Equals(title, "stop", StringComparison.Ordinal))
                    {
                        continue;
                    }

                    string album = GetChildText(node, "album");
                    if (string.IsNullOrEmpty(album)) album = DeriveAlbumFromUrl(url);
                    TrackInfo track = CreateCandidate(
                        title,
                        url,
                        album,
                        ParseInt(GetChildText(node, "fadeDuration"), DefaultFade),
                        ParseInt(GetChildText(node, "baseVolume"), DefaultVolume),
                        ParseInt(GetChildText(node, "weight"), DefaultWeight),
                        true,
                        previous,
                        dirtyPaths,
                        forceFull);
                    tracks[title] = track;
                    urls[url] = title;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[MusicCatalog] Error parsing bgm_list.xml: " + ex.Message);
            }
        }

        private void ScanDiscoveredTracks(
            IDictionary<string, TrackInfo> tracks,
            IDictionary<string, string> urls,
            CatalogSnapshot previous,
            ISet<string> dirtyPaths,
            bool forceFull)
        {
            if (!Directory.Exists(_soundsDir)) return;
            string[] directories;
            try { directories = Directory.GetDirectories(_soundsDir); }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[MusicCatalog] Discovery failed: " + ex.GetType().Name);
                return;
            }

            Array.Sort(directories, StringComparer.OrdinalIgnoreCase);
            for (int directoryIndex = 0;
                directoryIndex < directories.Length;
                directoryIndex++)
            {
                string directory = directories[directoryIndex];
                string album = Path.GetFileName(directory);
                if (string.Equals(
                    album,
                    "export",
                    StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                string[] files;
                try { files = Directory.GetFiles(directory); }
                catch { continue; }
                Array.Sort(files, StringComparer.OrdinalIgnoreCase);

                for (int fileIndex = 0; fileIndex < files.Length; fileIndex++)
                {
                    string extension = Path.GetExtension(files[fileIndex]);
                    if (!IsAudioHintExtension(extension)) continue;

                    string url = NormalizeUrl(
                        "sounds/" + album + "/" +
                        Path.GetFileName(files[fileIndex]));
                    if (urls.ContainsKey(url)) continue;

                    string title = Path.GetFileNameWithoutExtension(files[fileIndex]);
                    title = MakeUniqueTitle(title, album, tracks);
                    TrackInfo track = CreateCandidate(
                        title,
                        url,
                        album,
                        DefaultFade,
                        DefaultVolume,
                        DefaultWeight,
                        false,
                        previous,
                        dirtyPaths,
                        forceFull);
                    tracks[title] = track;
                    urls[url] = title;
                }
            }
        }

        private TrackInfo CreateCandidate(
            string title,
            string url,
            string album,
            int fade,
            int volume,
            int weight,
            bool registered,
            CatalogSnapshot previous,
            ISet<string> dirtyPaths,
            bool forceFull)
        {
            string fullPath = ResolveCatalogPath(url);
            if (fullPath == null)
            {
                return NewTrack(
                    title, url, album, fade, volume, weight, registered, null,
                    AvailabilityUnavailable, "invalid_path", null);
            }

            FileObservation observation = ObserveFile(fullPath);
            if (!observation.Exists)
            {
                return NewTrack(
                    title, url, album, fade, volume, weight, registered, fullPath,
                    AvailabilityUnavailable, ReasonMissing, observation);
            }

            TrackInfo prior;
            bool dirty = forceFull ||
                (dirtyPaths != null && dirtyPaths.Contains(fullPath));
            if (!dirty && previous.Tracks.TryGetValue(title, out prior) &&
                string.Equals(prior.FullPath, fullPath, StringComparison.OrdinalIgnoreCase) &&
                prior.ObservedSize == observation.Size &&
                prior.ObservedMtimeUtcTicks == observation.MtimeUtcTicks &&
                prior.Availability != AvailabilityProbing)
            {
                return new TrackInfo(
                    title, url, album, fade, volume, weight, registered, fullPath,
                    prior.Availability, prior.Reason,
                    prior.ObservedSize, prior.ObservedMtimeUtcTicks,
                    prior.First64kSha256, prior.CacheKey);
            }

            return NewTrack(
                title, url, album, fade, volume, weight, registered, fullPath,
                AvailabilityProbing, ReasonPendingProbe, observation);
        }

        private static TrackInfo NewTrack(
            string title,
            string url,
            string album,
            int fade,
            int volume,
            int weight,
            bool registered,
            string fullPath,
            string availability,
            string reason,
            FileObservation observation)
        {
            return new TrackInfo(
                title,
                url,
                album,
                fade,
                volume,
                weight,
                registered,
                fullPath,
                availability,
                reason,
                observation != null && observation.Exists
                    ? observation.Size
                    : -1L,
                observation != null && observation.Exists
                    ? observation.MtimeUtcTicks
                    : 0L,
                null,
                null);
        }

        private async Task<CatalogSnapshot> QualifySnapshotAsync(
            CatalogSnapshot discovered,
            string capabilityDigest,
            CancellationToken cancellationToken)
        {
            List<TrackInfo> ordered = discovered.OrderedTracks;
            var first = new FileObservation[ordered.Count];
            bool hasProbeCandidates = false;
            for (int index = 0; index < ordered.Count; index++)
            {
                if (ordered[index].Availability != AvailabilityProbing) continue;
                first[index] = ObserveFile(ordered[index].FullPath);
                hasProbeCandidates = true;
            }
            if (!hasProbeCandidates)
            {
                return CatalogSnapshot.Create(
                    ordered,
                    discovered.Revision,
                    true,
                    capabilityDigest);
            }

            await Task.Delay(
                _policy.StabilityInterval,
                cancellationToken).ConfigureAwait(false);

            var qualified = new TrackInfo[ordered.Count];
            var tasks = new List<Task>();
            using (var probeSlots = new SemaphoreSlim(
                _policy.MaxConcurrentProbes,
                _policy.MaxConcurrentProbes))
            {
                for (int index = 0; index < ordered.Count; index++)
                {
                    TrackInfo track = ordered[index];
                    if (track.Availability != AvailabilityProbing)
                    {
                        qualified[index] = track;
                        continue;
                    }

                    FileObservation second = ObserveFile(track.FullPath);
                    FileObservation firstObservation = first[index];
                    if (!SameObservation(firstObservation, second))
                    {
                        qualified[index] = track.WithProbeProjection(
                            AvailabilityProbing,
                            ReasonUnstableInput,
                            second,
                            null,
                            null);
                        continue;
                    }
                    if (!second.Exists)
                    {
                        qualified[index] = track.WithProbeProjection(
                            AvailabilityUnavailable,
                            ReasonMissing,
                            second,
                            null,
                            null);
                        continue;
                    }
                    if (second.Size > _policy.MaxFileBytes)
                    {
                        qualified[index] = track.WithProbeProjection(
                            AvailabilityUnavailable,
                            "file_too_large",
                            second,
                            null,
                            null);
                        continue;
                    }

                    int capture = index;
                    tasks.Add(QualifyTrackAsync(
                        track,
                        second,
                        probeSlots,
                        capabilityDigest,
                        cancellationToken).ContinueWith(
                            completed =>
                            {
                                if (completed.IsCanceled)
                                    throw new OperationCanceledException(
                                        cancellationToken);
                                if (completed.IsFaulted)
                                    throw completed.Exception.InnerException;
                                qualified[capture] = completed.Result;
                            },
                            cancellationToken,
                            TaskContinuationOptions.ExecuteSynchronously,
                            TaskScheduler.Default));
                }
                if (tasks.Count > 0)
                    await Task.WhenAll(tasks).ConfigureAwait(false);
            }

            cancellationToken.ThrowIfCancellationRequested();
            return CatalogSnapshot.Create(
                qualified,
                discovered.Revision,
                true,
                capabilityDigest);
        }

        private async Task<TrackInfo> QualifyTrackAsync(
            TrackInfo track,
            FileObservation observation,
            SemaphoreSlim probeSlots,
            string capabilityDigest,
            CancellationToken cancellationToken)
        {
            FilePrefixEvidence prefix;
            try
            {
                prefix = ReadFilePrefix(
                    track.FullPath,
                    _policy.FirstHashBytes,
                    cancellationToken);
            }
            catch (OperationCanceledException) { throw; }
            catch
            {
                return track.WithProbeProjection(
                    AvailabilityProbing,
                    ReasonUnstableInput,
                    observation,
                    null,
                    null);
            }

            string hintExtension = Path.GetExtension(
                track.FullPath).ToLowerInvariant();
            ContentEvidence content = SniffContent(
                prefix.Bytes,
                hintExtension);

            if (!IsSha256Hex(capabilityDigest))
            {
                return track.WithProbeProjection(
                    AvailabilityUnavailable,
                    "probe_unavailable",
                    observation,
                    prefix.Sha256,
                    null);
            }
            capabilityDigest = capabilityDigest.ToUpperInvariant();

            string cacheKey = BuildProbeCacheKey(
                track.FullPath,
                observation.Size,
                observation.MtimeUtcTicks,
                prefix.Sha256,
                capabilityDigest,
                _policy.ContractRevision);
            ProbeProjection cached;
            lock (_sync)
            {
                if (_probeCache.TryGetValue(cacheKey, out cached))
                {
                    return track.WithProbeProjection(
                        cached.Availability,
                        cached.Reason,
                        observation,
                        prefix.Sha256,
                        cacheKey);
                }
            }

            ProbeProjection contentFailure = null;
            if (string.IsNullOrEmpty(content.DetectedContainer))
                contentFailure = ProbeProjection.Unavailable("unsupported_container");
            else if (string.IsNullOrEmpty(content.DetectedCodec) ||
                string.IsNullOrEmpty(content.DetectedDecoder))
                contentFailure = ProbeProjection.Unavailable("unsupported_codec");
            if (contentFailure != null)
            {
                lock (_sync) _probeCache[cacheKey] = contentFailure;
                return track.WithProbeProjection(
                    contentFailure.Availability,
                    contentFailure.Reason,
                    observation,
                    prefix.Sha256,
                    cacheKey);
            }

            long unixMilliseconds = new DateTimeOffset(
                new DateTime(
                    observation.MtimeUtcTicks,
                    DateTimeKind.Utc)).ToUnixTimeMilliseconds();
            var input = new MusicCatalogProbeInputV2(
                track.FullPath,
                (ulong)observation.Size,
                observation.MtimeUtcTicks,
                unixMilliseconds,
                prefix.Sha256,
                capabilityDigest,
                cacheKey,
                hintExtension,
                content.DetectedDecoder,
                content.DetectedContainer,
                content.DetectedCodec,
                content.ExtensionMismatch,
                MusicCatalogProbePolicyV2.ProductionStableObservationCount,
                checked((uint)_policy.StabilityInterval.TotalMilliseconds),
                checked((ulong)_policy.MaxFileBytes),
                checked((uint)_policy.FirstHashBytes),
                checked((int)_policy.ProbeMaxWall.TotalMilliseconds),
                _policy.MaxInputBytes,
                _policy.MaxDecodedFrames,
                _policy.ContractRevision);

            await probeSlots.WaitAsync(cancellationToken).ConfigureAwait(false);
            ProbeProjection projection;
            try
            {
                projection = await InvokeProbeAsync(
                    input,
                    cancellationToken).ConfigureAwait(false);
            }
            finally
            {
                probeSlots.Release();
            }

            if (projection.Cacheable)
            {
                lock (_sync) _probeCache[cacheKey] = projection;
            }
            return track.WithProbeProjection(
                projection.Availability,
                projection.Reason,
                observation,
                prefix.Sha256,
                cacheKey);
        }

        private async Task<ProbeProjection> InvokeProbeAsync(
            MusicCatalogProbeInputV2 input,
            CancellationToken cancellationToken)
        {
            using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken))
            {
                Task<MusicCatalogProbeResultV2> probeTask;
                try
                {
                    probeTask = _probePort.ProbeAsync(input, timeout.Token);
                }
                catch
                {
                    return ProbeProjection.Unavailable("internal_error");
                }
                if (probeTask == null)
                    return ProbeProjection.Unavailable("probe_unavailable");

                Task delay = Task.Delay(
                    _policy.ManagedAwaitTimeout,
                    cancellationToken);
                Task winner = await Task.WhenAny(probeTask, delay).ConfigureAwait(false);
                if (!ReferenceEquals(winner, probeTask))
                {
                    timeout.Cancel();
                    ObserveLateProbe(probeTask);
                    cancellationToken.ThrowIfCancellationRequested();
                    return ProbeProjection.Probing(ReasonInconclusiveTimeout);
                }

                MusicCatalogProbeResultV2 result;
                try { result = await probeTask.ConfigureAwait(false); }
                catch (OperationCanceledException)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    return ProbeProjection.Probing(ReasonInconclusiveTimeout);
                }
                catch
                {
                    return ProbeProjection.Unavailable("internal_error");
                }
                if (result == null)
                    return ProbeProjection.Unavailable("probe_unavailable");
                return MapProbeResult(input, result);
            }
        }

        private static ProbeProjection MapProbeResult(
            MusicCatalogProbeInputV2 input,
            MusicCatalogProbeResultV2 result)
        {
            if (!string.Equals(
                    result.CacheKey,
                    input.CacheKey,
                    StringComparison.Ordinal) ||
                !string.Equals(
                    result.CapabilityDigest,
                    input.CapabilityDigest,
                    StringComparison.Ordinal))
            {
                return ProbeProjection.Unavailable("probe_evidence_invalid");
            }

            if (result.Outcome == MusicCatalogProbeOutcomeV2.InconclusiveTimeout)
                return ProbeProjection.Probing(ReasonInconclusiveTimeout);
            if (result.Outcome == MusicCatalogProbeOutcomeV2.UnstableInput)
                return ProbeProjection.Probing(ReasonUnstableInput);

            if (result.Outcome ==
                MusicCatalogProbeOutcomeV2.CompatibleSignalPresent)
            {
                if (!result.CapabilityMatched)
                    return ProbeProjection.Unavailable("capability_mismatch");
                return ProbeProjection.Available(
                    input.ExtensionMismatch
                        ? ReasonExtensionMismatch
                        : ReasonCompatibleSignalPresent);
            }
            if (result.Outcome ==
                MusicCatalogProbeOutcomeV2.CompatibleSignalUnknown)
            {
                if (!result.CapabilityMatched)
                    return ProbeProjection.Unavailable("capability_mismatch");
                return ProbeProjection.Available(
                    input.ExtensionMismatch
                        ? ReasonExtensionMismatch
                        : ReasonCompatibleSignalUnknown);
            }

            switch (result.Outcome)
            {
                case MusicCatalogProbeOutcomeV2.UnsupportedContainer:
                    return ProbeProjection.Unavailable("unsupported_container");
                case MusicCatalogProbeOutcomeV2.UnsupportedCodec:
                    return ProbeProjection.Unavailable("unsupported_codec");
                case MusicCatalogProbeOutcomeV2.Malformed:
                    return ProbeProjection.Unavailable("malformed");
                case MusicCatalogProbeOutcomeV2.Truncated:
                    return ProbeProjection.Unavailable("truncated");
                case MusicCatalogProbeOutcomeV2.IoError:
                    return ProbeProjection.Unavailable("io_error");
                case MusicCatalogProbeOutcomeV2.AbiMismatch:
                    return ProbeProjection.Unavailable("abi_mismatch");
                case MusicCatalogProbeOutcomeV2.Missing:
                    return ProbeProjection.Unavailable(ReasonMissing);
                case MusicCatalogProbeOutcomeV2.NotReady:
                    return ProbeProjection.Unavailable("not_ready");
                case MusicCatalogProbeOutcomeV2.Throttled:
                    return ProbeProjection.Unavailable("throttled");
                default:
                    return ProbeProjection.Unavailable("internal_error");
            }
        }

        private void PublishSnapshot(
            CatalogSnapshot next,
            int revision,
            bool notify)
        {
            CatalogSnapshot prior;
            MusicCatalogQualificationSnapshotV2 qualification;
            lock (_sync)
            {
                if (_disposed || revision != _refreshRevision) return;
                prior = _snapshot;
                _snapshot = next;
                qualification = next.ToQualificationSnapshot();
            }
            FireQualificationChanged(qualification);
            if (!notify) return;
            lock (_sync)
            {
                if (_disposed || revision != _refreshRevision) return;
            }

            string update = BuildUpdateJson(prior, next);
            if (update != null) FireCatalogChanged(update);
        }

        private void FireQualificationChanged(
            MusicCatalogQualificationSnapshotV2 qualification)
        {
            Action<MusicCatalogQualificationSnapshotV2> handler =
                QualificationChangedV2;
            if (handler == null || qualification == null) return;
            try { handler(qualification); }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[MusicCatalog] QualificationChangedV2 error: " +
                    ex.GetType().Name);
            }
        }

        private bool IsCurrentRefresh(int revision)
        {
            lock (_sync)
            {
                return !_disposed && revision == _refreshRevision;
            }
        }

        private void FireReadyBarrierChanged(
            MusicCatalogReadyBarrierChangeV2 change)
        {
            Action<MusicCatalogReadyBarrierChangeV2> handler =
                ReadyBarrierChangedV2;
            if (handler == null || change == null) return;
            try { handler(change); }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[MusicCatalog] ReadyBarrierChangedV2 error: " +
                    ex.GetType().Name);
            }
        }

        private void FireCatalogChanged(string json)
        {
            Action<string> handler = CatalogChanged;
            if (handler == null || string.IsNullOrEmpty(json)) return;
            try { handler(json); }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[MusicCatalog] CatalogChanged error: " + ex.Message);
            }
        }

        private static string BuildFullCatalogJson(CatalogSnapshot snapshot)
        {
            var root = new JObject
            {
                ["task"] = "catalog",
                ["type"] = "catalog"
            };
            var tracks = new JArray();
            for (int index = 0; index < snapshot.OrderedTracks.Count; index++)
                tracks.Add(TrackJson(snapshot.OrderedTracks[index]));
            root["tracks"] = tracks;

            var albums = new JObject();
            foreach (KeyValuePair<string, List<string>> album in snapshot.Albums)
                albums[album.Key] = new JArray(album.Value);
            root["albums"] = albums;
            return root.ToString(Newtonsoft.Json.Formatting.None);
        }

        private static string BuildUpdateJson(
            CatalogSnapshot prior,
            CatalogSnapshot next)
        {
            var changed = new List<TrackInfo>();
            foreach (TrackInfo track in next.OrderedTracks)
            {
                TrackInfo oldTrack;
                if (!prior.Tracks.TryGetValue(track.Title, out oldTrack) ||
                    !track.SameProjection(oldTrack))
                {
                    changed.Add(track);
                }
            }

            var removed = new List<string>();
            foreach (string title in prior.Tracks.Keys)
            {
                if (!next.Tracks.ContainsKey(title)) removed.Add(title);
            }
            removed.Sort(StringComparer.Ordinal);
            if (changed.Count == 0 && removed.Count == 0) return null;

            var root = new JObject
            {
                ["task"] = "catalogUpdate",
                ["type"] = "catalogUpdate"
            };
            var added = new JArray();
            for (int index = 0; index < changed.Count; index++)
                added.Add(TrackJson(changed[index]));
            root["added"] = added;
            root["removed"] = new JArray(removed);
            return root.ToString(Newtonsoft.Json.Formatting.None);
        }

        private static JObject TrackJson(TrackInfo track)
        {
            return new JObject
            {
                ["title"] = track.Title,
                ["url"] = track.Url,
                ["album"] = track.Album,
                ["fade"] = track.FadeDuration,
                ["vol"] = track.BaseVolume,
                ["weight"] = track.Weight,
                ["availability"] = track.Availability,
                ["reason"] = track.Reason
            };
        }

        private void StartWatcher()
        {
            if (!Directory.Exists(_soundsDir)) return;
            _watcher = new FileSystemWatcher(_soundsDir, "*.*");
            _watcher.IncludeSubdirectories = true;
            _watcher.InternalBufferSize = 32768;
            _watcher.NotifyFilter = NotifyFilters.FileName |
                NotifyFilters.DirectoryName |
                NotifyFilters.LastWrite |
                NotifyFilters.Size;
            _watcher.Created += OnWatchedPathChanged;
            _watcher.Changed += OnWatchedPathChanged;
            _watcher.Deleted += OnWatchedPathChanged;
            _watcher.Renamed += OnWatchedPathRenamed;
            _watcher.Error += OnWatcherError;
            _watcher.EnableRaisingEvents = true;
        }

        private void OnWatchedPathChanged(object sender, FileSystemEventArgs args)
        {
            if (!IsRelevantWatchedPath(args.FullPath)) return;
            QueueWatchedRefresh(args.FullPath, false);
        }

        private void OnWatchedPathRenamed(object sender, RenamedEventArgs args)
        {
            bool oldRelevant = IsRelevantWatchedPath(args.OldFullPath);
            bool newRelevant = IsRelevantWatchedPath(args.FullPath);
            if (!oldRelevant && !newRelevant) return;
            if (oldRelevant) QueueWatchedRefresh(args.OldFullPath, false);
            if (newRelevant) QueueWatchedRefresh(args.FullPath, false);
        }

        private void OnWatcherError(object sender, ErrorEventArgs args)
        {
            QueueWatchedRefresh(null, true);
        }

        private bool IsRelevantWatchedPath(string path)
        {
            if (string.IsNullOrEmpty(path)) return false;
            string fileName = Path.GetFileName(path);
            if (string.Equals(
                fileName,
                "bgm_list.xml",
                StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
            if (!IsAudioHintExtension(Path.GetExtension(path))) return false;
            string normalized = NormalizePath(path);
            return normalized.IndexOf(
                "/export/",
                StringComparison.OrdinalIgnoreCase) < 0;
        }

        private void QueueWatchedRefresh(string path, bool forceFull)
        {
            lock (_sync)
            {
                if (_disposed) return;
                if (!string.IsNullOrEmpty(path))
                    _dirtyPaths.Add(NormalizePath(path));
                _forceFullWatchRefresh = _forceFullWatchRefresh || forceFull ||
                    (!string.IsNullOrEmpty(path) &&
                        string.Equals(
                            Path.GetFileName(path),
                            "bgm_list.xml",
                            StringComparison.OrdinalIgnoreCase));
                if (_watchDebounce == null)
                {
                    _watchDebounce = new Timer(
                        FlushWatchedRefresh,
                        null,
                        WatchDebounceMilliseconds,
                        Timeout.Infinite);
                }
                else
                {
                    _watchDebounce.Change(
                        WatchDebounceMilliseconds,
                        Timeout.Infinite);
                }
            }
        }

        private void FlushWatchedRefresh(object state)
        {
            HashSet<string> dirty;
            bool forceFull;
            lock (_sync)
            {
                if (_disposed) return;
                dirty = new HashSet<string>(
                    _dirtyPaths,
                    StringComparer.OrdinalIgnoreCase);
                _dirtyPaths.Clear();
                forceFull = _forceFullWatchRefresh;
                _forceFullWatchRefresh = false;
            }
            ScheduleRefresh(true, dirty, forceFull, true);
        }

        private string ResolveCatalogPath(string url)
        {
            try
            {
                string relative = url.Replace('/', Path.DirectorySeparatorChar);
                string full = NormalizePath(Path.GetFullPath(
                    Path.Combine(_projectRoot, relative)));
                if (!full.StartsWith(
                    _soundsPrefix,
                    StringComparison.OrdinalIgnoreCase))
                {
                    return null;
                }
                return full;
            }
            catch { return null; }
        }

        private static FileObservation ObserveFile(string path)
        {
            if (string.IsNullOrEmpty(path)) return FileObservation.Missing;
            try
            {
                var info = new FileInfo(path);
                info.Refresh();
                if (!info.Exists) return FileObservation.Missing;
                return new FileObservation(
                    true,
                    info.Length,
                    info.LastWriteTimeUtc.Ticks);
            }
            catch { return FileObservation.Missing; }
        }

        private static bool SameObservation(
            FileObservation left,
            FileObservation right)
        {
            return left != null && right != null &&
                left.Exists && right.Exists &&
                left.Size == right.Size &&
                left.MtimeUtcTicks == right.MtimeUtcTicks;
        }

        private static FilePrefixEvidence ReadFilePrefix(
            string path,
            int maxBytes,
            CancellationToken cancellationToken)
        {
            using (var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete))
            {
                int remaining = maxBytes;
                int total = 0;
                var prefix = new byte[maxBytes];
                while (remaining > 0)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    int read = stream.Read(
                        prefix,
                        total,
                        remaining);
                    if (read <= 0) break;
                    total += read;
                    remaining -= read;
                }
                if (total != prefix.Length) Array.Resize(ref prefix, total);
                return new FilePrefixEvidence(
                    prefix,
                    Sha256Hex(prefix));
            }
        }

        private static ContentEvidence SniffContent(
            byte[] bytes,
            string hintExtension)
        {
            string decoder = null;
            string container = null;
            string codec = null;
            if (MatchesAscii(bytes, 0, "RIFF") &&
                MatchesAscii(bytes, 8, "WAVE"))
            {
                decoder = DecoderBuiltin;
                container = ContainerRiffWave;
                codec = CodecPcmOrIeeeFloat;
            }
            else if (MatchesAscii(bytes, 0, "fLaC"))
            {
                decoder = DecoderBuiltin;
                container = ContainerNativeFlac;
                codec = CodecFlac;
            }
            else if (MatchesAscii(bytes, 0, "OggS"))
            {
                container = ContainerOgg;
                if (ContainsAscii(bytes, "OpusHead"))
                {
                    decoder = DecoderLibOpus;
                    codec = CodecOpus;
                }
                else if (ContainsAscii(bytes, "vorbis"))
                {
                    decoder = DecoderLibVorbis;
                    codec = CodecVorbis;
                }
            }
            else if (MatchesAscii(bytes, 4, "ftyp"))
            {
                decoder = DecoderMediaFoundation;
                container = ContainerMpeg4;
                codec = CodecAacLcOrHeAac;
            }
            else if (bytes != null && bytes.Length >= 7 &&
                bytes[0] == 0xff && (bytes[1] & 0xf6) == 0xf0)
            {
                decoder = DecoderMediaFoundation;
                container = ContainerAdts;
                codec = CodecAacLcOrHeAac;
            }
            else if (MatchesAscii(bytes, 0, "ID3") ||
                (bytes != null && bytes.Length >= 2 &&
                    bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0))
            {
                decoder = DecoderBuiltin;
                container = ContainerMpegAudio;
                codec = CodecMpegAudioLayerIII;
            }

            bool extensionMismatch = !string.IsNullOrEmpty(container) &&
                !ExtensionMatchesContent(hintExtension, container, codec);
            return new ContentEvidence(
                decoder,
                container,
                codec,
                extensionMismatch);
        }

        private static bool ExtensionMatchesContent(
            string extension,
            string container,
            string codec)
        {
            if (string.Equals(extension, ".wav", StringComparison.OrdinalIgnoreCase))
                return container == ContainerRiffWave;
            if (string.Equals(extension, ".mp3", StringComparison.OrdinalIgnoreCase))
                return container == ContainerMpegAudio;
            if (string.Equals(extension, ".flac", StringComparison.OrdinalIgnoreCase))
                return container == ContainerNativeFlac;
            if (string.Equals(extension, ".ogg", StringComparison.OrdinalIgnoreCase))
                return container == ContainerOgg;
            if (string.Equals(extension, ".opus", StringComparison.OrdinalIgnoreCase))
                return container == ContainerOgg && codec == CodecOpus;
            if (string.Equals(extension, ".m4a", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(extension, ".mp4", StringComparison.OrdinalIgnoreCase))
                return container == ContainerMpeg4;
            if (string.Equals(extension, ".aac", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(extension, ".adts", StringComparison.OrdinalIgnoreCase))
                return container == ContainerAdts;
            return false;
        }

        private static bool MatchesAscii(byte[] bytes, int offset, string value)
        {
            if (bytes == null || value == null || offset < 0 ||
                bytes.Length - offset < value.Length)
                return false;
            for (int index = 0; index < value.Length; index++)
            {
                if (bytes[offset + index] != (byte)value[index]) return false;
            }
            return true;
        }

        private static bool ContainsAscii(byte[] bytes, string value)
        {
            if (bytes == null || value == null || bytes.Length < value.Length)
                return false;
            for (int offset = 0; offset <= bytes.Length - value.Length; offset++)
            {
                if (MatchesAscii(bytes, offset, value)) return true;
            }
            return false;
        }

        private static string Sha256Hex(byte[] bytes)
        {
            using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(bytes));
        }

        private static string Hex(byte[] bytes)
        {
            var builder = new StringBuilder(bytes.Length * 2);
            for (int index = 0; index < bytes.Length; index++)
                builder.Append(bytes[index].ToString("X2", CultureInfo.InvariantCulture));
            return builder.ToString();
        }

        private static bool IsSha256Hex(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char c = value[index];
                if ((c < '0' || c > '9') &&
                    (c < 'a' || c > 'f') &&
                    (c < 'A' || c > 'F'))
                {
                    return false;
                }
            }
            return true;
        }

        private string ReadCapabilityDigest()
        {
            try
            {
                string value = _probePort.CapabilityDigest;
                return IsSha256Hex(value) ? value.ToUpperInvariant() : null;
            }
            catch
            {
                return null;
            }
        }

        private static string MakeUniqueTitle(
            string baseTitle,
            string album,
            IDictionary<string, TrackInfo> tracks)
        {
            if (!tracks.ContainsKey(baseTitle)) return baseTitle;
            string candidate = album + "/" + baseTitle;
            if (!tracks.ContainsKey(candidate)) return candidate;
            int suffix = 2;
            while (tracks.ContainsKey(candidate + "#" + suffix)) suffix++;
            return candidate + "#" + suffix;
        }

        private static string DeriveAlbumFromUrl(string url)
        {
            if (url == null) return "unknown";
            string[] parts = NormalizeUrl(url).Split('/');
            if (parts.Length >= 3) return parts[1];
            if (parts.Length >= 2) return parts[0];
            return "unknown";
        }

        private static string NormalizeUrl(string value)
        {
            return value == null ? null : value.Replace('\\', '/');
        }

        private static string NormalizePath(string value)
        {
            return value == null ? null : value.Replace('\\', '/');
        }

        private static string GetChildText(XmlNode parent, string childName)
        {
            XmlNode child = parent.SelectSingleNode(childName);
            return child != null ? child.InnerText.Trim() : null;
        }

        private static int ParseInt(string value, int fallback)
        {
            int parsed;
            return !string.IsNullOrEmpty(value) && int.TryParse(value, out parsed)
                ? parsed
                : fallback;
        }

        private static bool IsAudioHintExtension(string extension)
        {
            if (string.IsNullOrEmpty(extension)) return false;
            for (int index = 0; index < AudioHintExtensions.Length; index++)
            {
                if (string.Equals(
                    extension,
                    AudioHintExtensions[index],
                    StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }

        private static void ObserveLateProbe(Task task)
        {
            task.ContinueWith(
                completed =>
                {
                    var ignored = completed.Exception;
                },
                CancellationToken.None,
                TaskContinuationOptions.OnlyOnFaulted |
                    TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }

        private void CompleteBackgroundTask(Task task)
        {
            lock (_sync) _backgroundTasks.Remove(task);
            if (task.IsFaulted)
            {
                var ignored = task.Exception;
            }
        }

        public void Dispose()
        {
            Task[] tasks;
            lock (_sync)
            {
                if (_disposed) return;
                _disposed = true;
                _lifetime.Cancel();
                if (_activeRefresh != null) _activeRefresh.Cancel();
                if (_watchDebounce != null)
                {
                    _watchDebounce.Dispose();
                    _watchDebounce = null;
                }
                if (_watcher != null)
                {
                    _watcher.EnableRaisingEvents = false;
                    _watcher.Dispose();
                    _watcher = null;
                }
                tasks = _backgroundTasks.ToArray();
            }

            if (tasks.Length > 0)
            {
                try { Task.WaitAll(tasks, TimeSpan.FromSeconds(5)); }
                catch (AggregateException) { }
            }

            lock (_sync)
            {
                if (_activeRefresh != null)
                {
                    _activeRefresh.Dispose();
                    _activeRefresh = null;
                }
            }
            _lifetime.Dispose();
            _refreshSerial.Dispose();
        }

        private sealed class CatalogSnapshot
        {
            internal static readonly CatalogSnapshot Empty = Create(
                new TrackInfo[0],
                0,
                false,
                null);

            private CatalogSnapshot(
                Dictionary<string, TrackInfo> tracks,
                List<TrackInfo> orderedTracks,
                SortedDictionary<string, List<string>> albums,
                int revision,
                bool qualificationComplete,
                string capabilityDigest)
            {
                Tracks = tracks;
                OrderedTracks = orderedTracks;
                Albums = albums;
                Revision = revision;
                QualificationComplete = qualificationComplete;
                CapabilityDigest = capabilityDigest;
            }

            internal Dictionary<string, TrackInfo> Tracks { get; private set; }
            internal List<TrackInfo> OrderedTracks { get; private set; }
            internal SortedDictionary<string, List<string>> Albums
            {
                get;
                private set;
            }
            internal int Revision { get; private set; }
            internal bool QualificationComplete { get; private set; }
            internal string CapabilityDigest { get; private set; }

            internal static CatalogSnapshot Create(
                IEnumerable<TrackInfo> source,
                int revision,
                bool qualificationComplete,
                string capabilityDigest)
            {
                var tracks = new Dictionary<string, TrackInfo>(
                    StringComparer.OrdinalIgnoreCase);
                foreach (TrackInfo track in source)
                {
                    if (track != null) tracks[track.Title] = track;
                }
                List<TrackInfo> ordered = tracks.Values.ToList();
                ordered.Sort((left, right) => string.CompareOrdinal(
                    left.Title,
                    right.Title));

                var albums = new SortedDictionary<string, List<string>>(
                    StringComparer.Ordinal);
                for (int index = 0; index < ordered.Count; index++)
                {
                    TrackInfo track = ordered[index];
                    if (string.IsNullOrEmpty(track.Album)) continue;
                    List<string> titles;
                    if (!albums.TryGetValue(track.Album, out titles))
                    {
                        titles = new List<string>();
                        albums[track.Album] = titles;
                    }
                    titles.Add(track.Title);
                }
                return new CatalogSnapshot(
                    tracks,
                    ordered,
                    albums,
                    revision,
                    qualificationComplete,
                    capabilityDigest);
            }

            internal MusicCatalogQualificationSnapshotV2 ToQualificationSnapshot()
            {
                int available = 0;
                int probing = 0;
                int unavailable = 0;
                for (int index = 0; index < OrderedTracks.Count; index++)
                {
                    string value = OrderedTracks[index].Availability;
                    if (value == AvailabilityAvailable) available++;
                    else if (value == AvailabilityProbing) probing++;
                    else unavailable++;
                }
                return new MusicCatalogQualificationSnapshotV2(
                    Revision,
                    QualificationComplete,
                    CapabilityDigest,
                    available,
                    probing,
                    unavailable);
            }
        }

        private sealed class ProbeProjection
        {
            private ProbeProjection(
                string availability,
                string reason,
                bool cacheable)
            {
                Availability = availability;
                Reason = reason;
                Cacheable = cacheable;
            }

            internal string Availability { get; private set; }
            internal string Reason { get; private set; }
            internal bool Cacheable { get; private set; }

            internal static ProbeProjection Available(string reason)
            {
                return new ProbeProjection(
                    AvailabilityAvailable,
                    reason,
                    true);
            }

            internal static ProbeProjection Probing(string reason)
            {
                return new ProbeProjection(
                    AvailabilityProbing,
                    reason,
                    false);
            }

            internal static ProbeProjection Unavailable(string reason)
            {
                return new ProbeProjection(
                    AvailabilityUnavailable,
                    reason,
                    true);
            }
        }

        private sealed class FilePrefixEvidence
        {
            internal FilePrefixEvidence(byte[] bytes, string sha256)
            {
                Bytes = bytes;
                Sha256 = sha256;
            }

            internal byte[] Bytes { get; private set; }
            internal string Sha256 { get; private set; }
        }

        private sealed class ContentEvidence
        {
            internal ContentEvidence(
                string detectedDecoder,
                string detectedContainer,
                string detectedCodec,
                bool extensionMismatch)
            {
                DetectedDecoder = detectedDecoder;
                DetectedContainer = detectedContainer;
                DetectedCodec = detectedCodec;
                ExtensionMismatch = extensionMismatch;
            }

            internal string DetectedDecoder { get; private set; }
            internal string DetectedContainer { get; private set; }
            internal string DetectedCodec { get; private set; }
            internal bool ExtensionMismatch { get; private set; }
        }

        internal sealed class FileObservation
        {
            internal static readonly FileObservation Missing =
                new FileObservation(false, -1L, 0L);

            internal FileObservation(bool exists, long size, long mtimeUtcTicks)
            {
                Exists = exists;
                Size = size;
                MtimeUtcTicks = mtimeUtcTicks;
            }

            internal bool Exists { get; private set; }
            internal long Size { get; private set; }
            internal long MtimeUtcTicks { get; private set; }
        }

        private sealed class UnavailableMusicCatalogProbePort :
            IMusicCatalogRuntimeProbePortV2
        {
            internal static readonly UnavailableMusicCatalogProbePort Instance =
                new UnavailableMusicCatalogProbePort();

            private UnavailableMusicCatalogProbePort() { }

            public string CapabilityDigest { get { return null; } }

            public Task<MusicCatalogProbeResultV2> ProbeAsync(
                MusicCatalogProbeInputV2 input,
                CancellationToken cancellationToken)
            {
                return Task.FromResult<MusicCatalogProbeResultV2>(null);
            }
        }
    }
}
