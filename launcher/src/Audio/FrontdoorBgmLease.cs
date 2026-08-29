using System;
using System.IO;
using CF7Launcher.Guardian;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// The launch flow only needs two semantic edges.  This deliberately is not a
    /// generic route, priority, playlist or per-slot preference surface.
    /// </summary>
    internal interface IFrontdoorBgmLease
    {
        void EnterFrontdoor(string reason);
        void YieldToGameplay(string reason);
    }

    internal interface IFrontdoorBgmAudioPort
    {
        AudioCoordinatorSnapshotV2 Snapshot { get; }
        event Action<AudioCoordinatorSnapshotV2> SnapshotChanged;

        bool TryAcquire(
            string requestId,
            string path,
            bool loop,
            float gain,
            float fadeSeconds);

        bool Revoke(string requestId, float fadeSeconds);
    }

    internal sealed class AudioEngineFrontdoorBgmPort :
        IFrontdoorBgmAudioPort
    {
        public AudioCoordinatorSnapshotV2 Snapshot
        {
            get { return AudioEngine.SnapshotV2; }
        }

        public event Action<AudioCoordinatorSnapshotV2> SnapshotChanged
        {
            add { AudioEngine.SnapshotChanged += value; }
            remove { AudioEngine.SnapshotChanged -= value; }
        }

        public bool TryAcquire(
            string requestId,
            string path,
            bool loop,
            float gain,
            float fadeSeconds)
        {
            return AudioEngine.TryAcquireFrontdoorBgm(
                requestId,
                path,
                loop,
                gain,
                fadeSeconds);
        }

        public bool Revoke(string requestId, float fadeSeconds)
        {
            return AudioEngine.RevokeFrontdoorBgm(
                requestId,
                fadeSeconds);
        }
    }

    /// <summary>
    /// Owns the launcher/frontdoor copy of the historical main-menu track until
    /// GameLaunchFlow hands BGM authority to OP/gameplay.  AudioCoordinator's exact
    /// request-id CAS makes yield safe even when AS2 has already installed a newer
    /// BGM intent, and clears recovery replay state when the endpoint is rebuilding.
    /// </summary>
    internal sealed class FrontdoorBgmLease :
        IFrontdoorBgmLease,
        IDisposable
    {
        internal const string TrackRelativePath =
            @"sounds\PTXOA馆长\主菜单.mp3";
        internal const float TrackGain = 0.4f;
        internal const float FadeSeconds = 1f;

        private readonly object _gate = new object();
        private readonly IFrontdoorBgmAudioPort _audio;
        private readonly string _requestId;
        private readonly bool _trackAvailable;
        private bool _desired;
        private bool _acquireInFlight;
        private bool _disposed;

        internal FrontdoorBgmLease(string projectRoot)
            : this(
                new AudioEngineFrontdoorBgmPort(),
                projectRoot,
                "host.frontdoor." + Guid.NewGuid().ToString("N"))
        {
        }

        internal FrontdoorBgmLease(
            IFrontdoorBgmAudioPort audio,
            string projectRoot,
            string requestId)
        {
            if (audio == null) throw new ArgumentNullException("audio");
            if (string.IsNullOrEmpty(requestId) ||
                !requestId.StartsWith(
                    "host.frontdoor.",
                    StringComparison.Ordinal))
            {
                throw new ArgumentException(
                    "Frontdoor BGM request id is invalid.",
                    "requestId");
            }

            _audio = audio;
            _requestId = requestId;
            _trackAvailable = HasFixedTrack(projectRoot);
            _audio.SnapshotChanged += OnAudioSnapshotChanged;
            if (!_trackAvailable)
            {
                LogManager.Log(
                    "[FrontdoorBgm] fixed track missing: " +
                    TrackRelativePath);
            }
        }

        public void EnterFrontdoor(string reason)
        {
            lock (_gate)
            {
                if (_disposed) return;
                _desired = true;
            }
            LogManager.Log(
                "[FrontdoorBgm] enter reason=" + SafeReason(reason));
            TryAcquireIfReady();
        }

        public void YieldToGameplay(string reason)
        {
            lock (_gate)
            {
                if (_disposed) return;
                _desired = false;
            }
            bool revoked = false;
            try
            {
                revoked = _audio.Revoke(_requestId, FadeSeconds);
            }
            catch
            {
            }
            LogManager.Log(
                "[FrontdoorBgm] yield reason=" + SafeReason(reason) +
                " revoked=" + revoked);
        }

        public void Dispose()
        {
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                _desired = false;
            }
            try { _audio.SnapshotChanged -= OnAudioSnapshotChanged; }
            catch { }
            try { _audio.Revoke(_requestId, FadeSeconds); }
            catch { }
        }

        private void OnAudioSnapshotChanged(AudioCoordinatorSnapshotV2 snapshot)
        {
            TryAcquireIfReady(snapshot);
        }

        private void TryAcquireIfReady()
        {
            AudioCoordinatorSnapshotV2 snapshot = null;
            try { snapshot = _audio.Snapshot; }
            catch { }
            TryAcquireIfReady(snapshot);
        }

        private void TryAcquireIfReady(AudioCoordinatorSnapshotV2 snapshot)
        {
            lock (_gate)
            {
                if (_disposed || !_desired || !_trackAvailable ||
                    snapshot == null || !snapshot.IsReady ||
                    !string.IsNullOrWhiteSpace(snapshot.SourceRequestId) ||
                    _acquireInFlight)
                {
                    return;
                }
                _acquireInFlight = true;
            }

            bool acquired = false;
            try
            {
                acquired = _audio.TryAcquire(
                    _requestId,
                    TrackRelativePath,
                    true,
                    TrackGain,
                    FadeSeconds);
            }
            catch
            {
            }

            bool revokeLateAcquire;
            lock (_gate)
            {
                _acquireInFlight = false;
                revokeLateAcquire = acquired && (_disposed || !_desired);
            }
            if (revokeLateAcquire)
            {
                try { _audio.Revoke(_requestId, FadeSeconds); }
                catch { }
                return;
            }
            if (acquired)
            {
                LogManager.Log(
                    "[FrontdoorBgm] acquired requestId=" + _requestId);
            }
        }

        private static bool HasFixedTrack(string projectRoot)
        {
            if (string.IsNullOrWhiteSpace(projectRoot)) return false;
            try
            {
                string root = Path.GetFullPath(projectRoot);
                string track = Path.GetFullPath(Path.Combine(
                    root,
                    TrackRelativePath));
                string prefix = root.EndsWith(
                    Path.DirectorySeparatorChar.ToString(),
                    StringComparison.Ordinal)
                    ? root
                    : root + Path.DirectorySeparatorChar;
                return track.StartsWith(
                        prefix,
                        StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(track);
            }
            catch
            {
                return false;
            }
        }

        private static string SafeReason(string reason)
        {
            return string.IsNullOrWhiteSpace(reason)
                ? "unspecified"
                : reason.Replace('\r', '_').Replace('\n', '_');
        }
    }
}
