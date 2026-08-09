using System;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Narrow admission boundary between the AS2/socket protocol and the audio
    /// coordinator.  Implementations own readiness, generations, latest-wins policy,
    /// counters and native work; AudioTask only validates and routes.
    /// </summary>
    internal interface IAudioCommandFacadeV2
    {
        void DispatchBgm(
            AudioBgmRequestV2 request,
            Action<AudioBgmResultV2> respond);

        void RejectBgm(string protocolError);

        void DispatchSfx(AudioSfxBatchV2 batch);

        void RejectSfx(string protocolError);

        void ArmBootstrapBgmGate();

        void CancelBootstrapBgmGate();

        void ReleaseBootstrapBgmGate();
    }
}
