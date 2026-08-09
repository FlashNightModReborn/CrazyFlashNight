using System;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Closes the native-initialized -> catalog-qualified -> audio-ready barrier.
    /// Qualification runs outside the native owner; completion is accepted only for
    /// the exact session/ready/device/capability tuple captured by the coordinator.
    /// </summary>
    internal static class AudioCatalogQualificationBinderV2
    {
        internal static bool Configure(MusicCatalog catalog)
        {
            if (catalog == null) throw new ArgumentNullException("catalog");
            var binding = new Binding(catalog);
            catalog.ReadyBarrierChangedV2 += binding.OnReadyBarrierChanged;
            bool configured = AudioEngine.ConfigureCatalogQualificationHook(
                binding.BeginCoordinatorQualification);
            if (!configured)
                catalog.ReadyBarrierChangedV2 -= binding.OnReadyBarrierChanged;
            return configured;
        }

        private static void BeginQualification(
            MusicCatalog catalog,
            AudioCatalogQualificationRequestV2 request)
        {
            Task refresh;
            try
            {
                request.CancellationToken.ThrowIfCancellationRequested();
                refresh = catalog.RequalifyForCapabilityChangeAsync();
            }
            catch (Exception ex)
            {
                LogFailure(ex);
                Complete(request, false);
                return;
            }

            if (refresh == null)
            {
                Complete(request, false);
                return;
            }

            refresh.ContinueWith(
                delegate(Task completed)
                {
                    bool accepted = false;
                    try
                    {
                        request.CancellationToken.ThrowIfCancellationRequested();
                        if (!completed.IsCanceled && !completed.IsFaulted)
                        {
                            MusicCatalogProjectionV2 projection =
                                catalog.GetProjectionV2();
                            accepted = projection != null &&
                                projection.Qualification != null &&
                                projection.Qualification.IsCompleteForCapability(
                                    request.CapabilityDigest);
                        }
                        else if (completed.Exception != null)
                        {
                            LogFailure(completed.Exception);
                        }
                    }
                    catch (Exception ex)
                    {
                        LogFailure(ex);
                    }
                    Complete(request, accepted);
                },
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }

        private static void Complete(
            AudioCatalogQualificationRequestV2 request,
            bool accepted)
        {
            try
            {
                AudioEngine.CompleteCatalogQualification(
                    request.AudioSessionId,
                    request.AudioReadyGeneration,
                    request.DeviceGeneration,
                    request.CapabilityDigest,
                    accepted);
            }
            catch (Exception ex)
            {
                LogFailure(ex);
            }
        }

        private static void LogFailure(Exception ex)
        {
            LogManager.Log(
                "[AudioV2] catalog qualification barrier failed: " +
                (ex == null ? "unknown" : ex.GetType().Name));
        }

        private sealed class Binding
        {
            private readonly MusicCatalog _catalog;

            internal Binding(MusicCatalog catalog)
            {
                _catalog = catalog;
            }

            internal void BeginCoordinatorQualification(
                AudioCatalogQualificationRequestV2 request)
            {
                BeginQualification(_catalog, request);
            }

            internal void OnReadyBarrierChanged(
                MusicCatalogReadyBarrierChangeV2 change)
            {
                if (change == null ||
                    change.Phase != MusicCatalogReadyBarrierPhaseV2.Started)
                {
                    return;
                }

                try
                {
                    // The rebuild publishes a new native/managed tuple and queues the
                    // existing coordinator-owned qualification hook.  That hook also
                    // supersedes this hot refresh, so terminal notifications here must
                    // never complete admission independently.
                    AudioEngine.BeginCatalogRefreshRebuild(
                        change.CapabilityDigest);
                }
                catch (Exception ex)
                {
                    LogFailure(ex);
                }
            }
        }
    }
}
