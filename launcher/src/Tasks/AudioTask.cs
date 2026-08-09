// CF7:ME Audio Platform v2 task router.

using System;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Audio;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    internal interface IAudioTaskQualificationObserverV2
    {
        void RecordBgmRequest(AudioBgmRequestV2 request);
        void RecordBgmResult(AudioBgmResultV2 result);
        void RecordSfxBatch(AudioSfxBatchV2 batch);
    }

    /// <summary>
    /// Strict Audio Platform v2 protocol adapter.
    ///
    /// This type owns no decoder, device, readiness or generation state.  It validates
    /// the AS2 wire and forwards typed commands to one injected coordinator facade.
    /// XMLSocket connection generations remain in XmlSocketServer and never enter this
    /// class or the audio wire models.
    /// </summary>
    public sealed class AudioTask
    {
        private readonly IAudioCommandFacadeV2 _facade;
        private readonly IAudioTaskQualificationObserverV2
            _qualificationObserver;

        private static IAudioCommandFacadeV2 _processFacade =
            UnavailableAudioCommandFacadeV2.Instance;

        /// <summary>
        /// Compatibility signal consumed by the existing jukebox tick.  It records a
        /// validated Flash BGM change intent, not proof that playback started.
        /// </summary>
        public static volatile bool FlashBgmChange;

        public AudioTask()
            : this(UnavailableAudioCommandFacadeV2.Instance)
        {
        }

        internal AudioTask(IAudioCommandFacadeV2 facade)
            : this(facade, null)
        {
        }

        internal AudioTask(
            IAudioCommandFacadeV2 facade,
            IAudioTaskQualificationObserverV2 qualificationObserver)
        {
            if (facade == null) throw new ArgumentNullException("facade");
            _facade = facade;
            _qualificationObserver = qualificationObserver;
        }

        /// <summary>
        /// Retained until Program is moved to the coordinator-owned volume warning sink.
        /// AudioTask no longer owns gain state and therefore cannot emit that warning.
        /// </summary>
        public static void SetToastSink(IToastSink sink)
        {
            // Compatibility hook only.  The v2 facade/coordinator owns volume policy.
        }

        /// <summary>
        /// Binds the same facade used by this registered task to the existing static
        /// bootstrap lifecycle hooks in GameLaunchFlow.  TaskRegistry calls this exactly
        /// when it installs the audio routes.
        /// </summary>
        internal void BindAsProcessFacade()
        {
            Volatile.Write(ref _processFacade, _facade);
        }

        internal static void ResetProcessFacadeForTests()
        {
            Volatile.Write(
                ref _processFacade,
                UnavailableAudioCommandFacadeV2.Instance);
            FlashBgmChange = false;
        }

        public static void ArmBootstrapBgmGate()
        {
            InvokeLifecycle(
                delegate(IAudioCommandFacadeV2 facade)
                {
                    facade.ArmBootstrapBgmGate();
                },
                "arm_bootstrap_gate");
        }

        public static void CancelBootstrapBgmGate()
        {
            InvokeLifecycle(
                delegate(IAudioCommandFacadeV2 facade)
                {
                    facade.CancelBootstrapBgmGate();
                },
                "cancel_bootstrap_gate");
        }

        public static void ReleaseBootstrapBgmGate()
        {
            InvokeLifecycle(
                delegate(IAudioCommandFacadeV2 facade)
                {
                    facade.ReleaseBootstrapBgmGate();
                },
                "release_bootstrap_gate");
        }

        /// <summary>
        /// Async MessageRouter handler.  A facade may emit more than one correlated
        /// completion (for example accepted_deferred, then started).  The router-provided
        /// callback remains connection-generation-bound inside XmlSocketServer.
        /// </summary>
        public void HandleAsync(JObject message, Action<string> respond)
        {
            AudioBgmRequestV2 request;
            string error;
            if (!TryParseEnvelope(message, out request, out error))
            {
                RejectBgm(error);
                return;
            }

            if (request.Operation == AudioWireV2.BgmPlay
                || request.Operation == AudioWireV2.BgmStop)
            {
                FlashBgmChange = true;
            }

            RecordQualificationBgmRequest(request);

            try
            {
                _facade.DispatchBgm(
                    request,
                    delegate(AudioBgmResultV2 result)
                    {
                        if (result == null) return;
                        RecordQualificationBgmResult(result);
                        if (respond == null) return;
                        try
                        {
                            JObject serialized =
                                AudioWireV2.SerializeBgmResult(result);
                            respond(serialized.ToString(Formatting.None));
                        }
                        catch (Exception ex)
                        {
                            LogManager.Log(
                                "[AudioV2] rejected facade BGM result: "
                                + ex.GetType().Name);
                        }
                    });
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[AudioV2] BGM facade dispatch failed: "
                    + ex.GetType().Name);
            }
        }

        /// <summary>
        /// Strict S2 fast-lane entry.  Returns true only when one typed batch was handed
        /// to the facade.  Invalid/stale business state is classified by the facade and
        /// never replayed by this adapter.
        /// </summary>
        internal bool HandleSfxFastLane(string message)
        {
            AudioSfxBatchV2 batch;
            string error;
            if (!AudioWireV2.TryParseSfxBatch(message, out batch, out error))
            {
                RejectSfx(error);
                return false;
            }

            try
            {
                RecordQualificationSfxBatch(batch);
                _facade.DispatchSfx(batch);
                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[AudioV2] SFX facade dispatch failed: "
                    + ex.GetType().Name);
                return false;
            }
        }

        private static bool TryParseEnvelope(
            JObject message,
            out AudioBgmRequestV2 request,
            out string error)
        {
            request = null;
            error = null;
            if (message == null
                || message["task"] == null
                || message["task"].Type != JTokenType.String
                || !string.Equals(
                    (string)message["task"],
                    "audio",
                    StringComparison.Ordinal))
            {
                error = "bgm.envelope";
                return false;
            }

            var payload = new JObject();
            foreach (JProperty property in message.Properties())
            {
                if (string.Equals(
                    property.Name,
                    "task",
                    StringComparison.Ordinal))
                {
                    continue;
                }
                payload.Add(property.Name, property.Value.DeepClone());
            }

            return AudioWireV2.TryParseBgmRequest(
                payload,
                out request,
                out error);
        }

        private void RejectBgm(string error)
        {
            string safeError = string.IsNullOrEmpty(error)
                ? "bgm.protocol_error"
                : error;
            LogManager.Log("[AudioV2] rejected BGM wire: " + safeError);
            try
            {
                _facade.RejectBgm(safeError);
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[AudioV2] BGM rejection callback failed: "
                    + ex.GetType().Name);
            }
        }

        private void RejectSfx(string error)
        {
            string safeError = string.IsNullOrEmpty(error)
                ? "sfx.protocol_error"
                : error;
            LogManager.Log("[AudioV2] rejected SFX wire: " + safeError);
            try
            {
                _facade.RejectSfx(safeError);
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[AudioV2] SFX rejection callback failed: "
                    + ex.GetType().Name);
            }
        }

        private static void InvokeLifecycle(
            Action<IAudioCommandFacadeV2> action,
            string operation)
        {
            IAudioCommandFacadeV2 facade =
                Volatile.Read(ref _processFacade);
            try
            {
                action(facade);
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[AudioV2] lifecycle " + operation + " failed: "
                    + ex.GetType().Name);
            }
        }

        private void RecordQualificationBgmRequest(
            AudioBgmRequestV2 request)
        {
            try { _qualificationObserver?.RecordBgmRequest(request); }
            catch
            {
                // Qualification observers are read-only and must never affect AS2.
            }
        }

        private void RecordQualificationBgmResult(
            AudioBgmResultV2 result)
        {
            try { _qualificationObserver?.RecordBgmResult(result); }
            catch
            {
                // Qualification observers are read-only and must never affect AS2.
            }
        }

        private void RecordQualificationSfxBatch(
            AudioSfxBatchV2 batch)
        {
            try { _qualificationObserver?.RecordSfxBatch(batch); }
            catch
            {
                // Qualification observers are read-only and must never affect AS2.
            }
        }

        /// <summary>
        /// Fail-closed placeholder used until Program injects the real coordinator.
        /// It never calls the legacy static AudioEngine and never reports audio ready.
        /// </summary>
        private sealed class UnavailableAudioCommandFacadeV2
            : IAudioCommandFacadeV2
        {
            public static readonly UnavailableAudioCommandFacadeV2 Instance =
                new UnavailableAudioCommandFacadeV2();

            private readonly string _audioSessionId =
                Guid.NewGuid().ToString("D");

            private UnavailableAudioCommandFacadeV2()
            {
            }

            public void DispatchBgm(
                AudioBgmRequestV2 request,
                Action<AudioBgmResultV2> respond)
            {
                if (respond == null) return;
                bool stale = !string.Equals(
                    request.AudioSessionId,
                    _audioSessionId,
                    StringComparison.Ordinal)
                    || request.AudioReadyGeneration != 0;
                respond(new AudioBgmResultV2(
                    request.RequestId,
                    _audioSessionId,
                    0,
                    0,
                    request.Operation,
                    "failed",
                    stale ? "stale_generation" : "not_ready",
                    "admission",
                    0,
                    0,
                    "none",
                    stale
                        ? "audio.stale_generation"
                        : "audio.not_ready"));
            }

            public void RejectBgm(string protocolError)
            {
            }

            public void DispatchSfx(AudioSfxBatchV2 batch)
            {
            }

            public void RejectSfx(string protocolError)
            {
            }

            public void ArmBootstrapBgmGate()
            {
            }

            public void CancelBootstrapBgmGate()
            {
            }

            public void ReleaseBootstrapBgmGate()
            {
            }
        }
    }
}
