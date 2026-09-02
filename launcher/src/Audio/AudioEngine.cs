// CF7:ME Audio Engine compatibility facade.

using System;
using System.Threading;
using CF7Launcher.Guardian;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// The only process-level audio facade.
    ///
    /// Existing public method names remain during the A1-A4 migration, but every call
    /// now passes through AudioCoordinator's single owner queue.  Raw P/Invoke belongs
    /// exclusively to AudioNativeV2 and its caller-owned-memory adapter.
    /// </summary>
    internal static class AudioEngine
    {
        private static readonly AudioCoordinator Coordinator =
            new AudioCoordinator();

        internal static IAudioCommandFacadeV2 CommandFacadeV2
        {
            get { return Coordinator; }
        }

        internal static AudioCoordinatorSnapshotV2 SnapshotV2
        {
            get { return Coordinator.Snapshot; }
        }

        internal static event Action<AudioCoordinatorSnapshotV2> SnapshotChanged
        {
            add { Coordinator.SnapshotChanged += value; }
            remove { Coordinator.SnapshotChanged -= value; }
        }

        public static bool IsSfxPreloadComplete
        {
            get { return Coordinator.Snapshot.IsSfxPreloadComplete; }
        }

        public static int ResolveSfxHandle(string id)
        {
            return Coordinator.ResolveSfxHandle(id);
        }

        internal static AudioRuntimeProbeResultV2 ProbeRuntimeCompatibility(
            string normalizedPath,
            ulong fileSizeBytes,
            long modifiedTimeUnixMilliseconds,
            string first64kSha256,
            string capabilityDigestSha256)
        {
            return Coordinator.ProbeRuntimeCompatibility(
                normalizedPath,
                fileSizeBytes,
                modifiedTimeUnixMilliseconds,
                first64kSha256,
                capabilityDigestSha256);
        }

        internal static AudioCoordinatorSnapshotV2 CaptureQualificationSnapshot()
        {
            return Coordinator.CaptureQualificationSnapshot();
        }

        /// <summary>
        /// Performs one atomic v2 rebuild.  A missing ABI, unsupported capability or
        /// lack of a real output device returns false and leaves the process running in
        /// the explicit audio-unavailable state.
        /// </summary>
        public static bool Init(string projectRoot)
        {
            bool ready = Coordinator.Initialize(projectRoot);
            AudioCoordinatorSnapshotV2 snapshot = Coordinator.Snapshot;
            if (!ready)
            {
                LogManager.Log(
                    "[AudioV2] unavailable: category=" +
                    snapshot.FailureCategory +
                    " messageKey=" + snapshot.MessageKey +
                    " audioReadyGeneration=" +
                    snapshot.AudioReadyGeneration);
                PerfTrace.Mark(
                    "audio.init_failed",
                    "category=" + snapshot.FailureCategory);
                return false;
            }

            LogManager.Log(
                "[AudioV2] ready: basePath=" + snapshot.NormalizedBasePath +
                " audioSessionId=" + snapshot.AudioSessionId +
                " audioReadyGeneration=" + snapshot.AudioReadyGeneration +
                " deviceGeneration=" + snapshot.DeviceGeneration +
                " loaded=" + snapshot.Loaded);
            PerfTrace.Mark(
                "audio.init_done",
                "readyGeneration=" + snapshot.AudioReadyGeneration +
                " deviceGeneration=" + snapshot.DeviceGeneration);
            return true;
        }

        internal static bool BeginInitialize(string projectRoot)
        {
            return Coordinator.BeginInitialize(projectRoot);
        }

        internal static bool ConfigureInitialMasterGain(float gain)
        {
            return Coordinator.ConfigureInitialMasterGain(gain);
        }

        internal static bool ConfigureCatalogQualificationHook(
            AudioCatalogQualificationHookV2 hook)
        {
            return Coordinator.ConfigureCatalogQualificationHook(hook);
        }

        internal static bool CompleteCatalogQualification(
            string audioSessionId,
            ulong audioReadyGeneration,
            ulong deviceGeneration,
            string capabilityDigest,
            bool succeeded)
        {
            return Coordinator.CompleteCatalogQualification(
                audioSessionId,
                audioReadyGeneration,
                deviceGeneration,
                capabilityDigest,
                succeeded);
        }

        internal static bool BeginCatalogRefreshRebuild(
            string capabilityDigest)
        {
            return Coordinator.BeginCatalogRefreshRebuild(
                capabilityDigest);
        }

        internal static bool TryAcquireFrontdoorBgm(
            string requestId,
            string path,
            bool loop,
            float volume,
            float fadeSeconds)
        {
            return Coordinator.TryAcquireFrontdoorBgm(
                requestId,
                path,
                loop,
                volume,
                fadeSeconds);
        }

        internal static bool RevokeFrontdoorBgm(
            string requestId,
            float fadeSeconds)
        {
            return Coordinator.RevokeFrontdoorBgm(
                requestId,
                fadeSeconds);
        }

        public static int PreloadFromDirectories(string projectRoot)
        {
            int loaded = Coordinator.EnsurePreloaded(projectRoot);
            AudioCoordinatorSnapshotV2 snapshot = Coordinator.Snapshot;
            PerfTrace.Mark(
                "audio.sfx_preload_done",
                "loaded=" + loaded +
                " failed=" + snapshot.Failed +
                " overridden=" + snapshot.Overrides);
            return loaded;
        }

        public static void PreloadFromDirectoriesAsync(string projectRoot)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    PreloadFromDirectories(projectRoot);
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[AudioV2] preload compatibility call failed: " +
                        ex.GetType().Name);
                    PerfTrace.Mark(
                        "audio.sfx_preload_failed",
                        ex.GetType().Name);
                }
            });
        }

        // Legacy signatures retained for callers being migrated in later slices.
        public static int ma_bridge_init(string basePath)
        {
            return Coordinator.Initialize(basePath) ? 0 : -1;
        }

        public static void ma_bridge_shutdown()
        {
            Coordinator.Shutdown();
        }

        public static int ma_bridge_bgm_play(
            string path,
            int loop,
            float volume,
            float fadeSec)
        {
            return Coordinator.LegacyBgmPlay(
                path,
                loop,
                volume,
                fadeSec);
        }

        public static int ma_bridge_bgm_stop(float fadeSec)
        {
            return Coordinator.LegacyBgmControl(
                AudioNativeV2.OperationBgmStop,
                fadeSec,
                0);
        }

        public static void ma_bridge_bgm_set_volume(float volume)
        {
            Coordinator.LegacySetGain(
                AudioNativeV2.OperationBgmSetGain,
                volume);
        }

        public static int ma_bridge_sfx_load(string path)
        {
            return Coordinator.LegacySfxLoad(path);
        }

        public static int ma_bridge_sfx_play(int handle, float volume)
        {
            return Coordinator.LegacySfxPlay(handle, volume);
        }

        public static void ma_bridge_sfx_unload(int handle)
        {
            Coordinator.LegacySfxUnload(handle);
        }

        public static void ma_bridge_sfx_set_volume(float volume)
        {
            Coordinator.LegacySetGain(
                AudioNativeV2.OperationSfxSetGain,
                volume);
        }

        public static void ma_bridge_bgm_get_peak(
            out float peakL,
            out float peakR)
        {
            AudioCoordinatorSnapshotV2 snapshot =
                Coordinator.RefreshObservation();
            peakL = snapshot.PeakLeft;
            peakR = snapshot.PeakRight;
        }

        public static float ma_bridge_bgm_get_cursor()
        {
            return Coordinator.RefreshObservation().CursorSeconds;
        }

        public static float ma_bridge_bgm_get_length()
        {
            return Coordinator.RefreshObservation().LengthSeconds;
        }

        public static int ma_bridge_bgm_is_playing()
        {
            return Coordinator.RefreshObservation().BgmPlaying ? 1 : 0;
        }

        public static int ma_bridge_bgm_seek(float seconds)
        {
            return Coordinator.LegacyBgmControl(
                AudioNativeV2.OperationBgmSeek,
                seconds,
                0);
        }

        public static void ma_bridge_bgm_set_looping(int looping)
        {
            Coordinator.LegacyBgmControl(
                AudioNativeV2.OperationBgmSetLoop,
                0f,
                looping);
        }

        public static int ma_bridge_bgm_pause()
        {
            return Coordinator.LegacyBgmControl(
                AudioNativeV2.OperationBgmPause,
                0f,
                0);
        }

        public static int ma_bridge_bgm_resume()
        {
            return Coordinator.LegacyBgmControl(
                AudioNativeV2.OperationBgmResume,
                0f,
                0);
        }

        public static void ma_bridge_set_master_volume(float volume)
        {
            Coordinator.LegacySetGain(
                AudioNativeV2.OperationSetMasterGain,
                volume);
        }

        public static void Shutdown()
        {
            Coordinator.Shutdown();
            LogManager.Log("[AudioV2] coordinator shutdown");
        }
    }
}
