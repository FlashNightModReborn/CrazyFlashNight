using System;
using System.Threading;
using System.Threading.Tasks;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Binds MusicCatalog's immutable probe input to the single-owner native
    /// Audio Platform v2 runtime probe.  The adapter never infers support from an
    /// extension and never widens the frozen H1 bounds.
    /// </summary>
    internal sealed class AudioMusicCatalogProbePortV2 :
        IMusicCatalogRuntimeProbePortV2
    {
        public string CapabilityDigest
        {
            get
            {
                string digest = AudioEngine.SnapshotV2.CapabilityDigest;
                return IsUpperSha256(digest) ? digest : null;
            }
        }

        public Task<MusicCatalogProbeResultV2> ProbeAsync(
            MusicCatalogProbeInputV2 input,
            CancellationToken cancellationToken)
        {
            if (input == null) throw new ArgumentNullException("input");
            cancellationToken.ThrowIfCancellationRequested();

            if (!HasExactContract(input))
            {
                return Task.FromResult(CreateResult(
                    input,
                    MusicCatalogProbeOutcomeV2.AbiMismatch,
                    false));
            }

            return Task.Run(
                delegate
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    AudioRuntimeProbeResultV2 native =
                        AudioEngine.ProbeRuntimeCompatibility(
                            input.NormalizedPath,
                            input.FileSizeBytes,
                            input.ModifiedTimeUnixMilliseconds,
                            input.First64kSha256,
                            input.CapabilityDigest);
                    return MapNativeResult(input, native);
                },
                cancellationToken);
        }

        internal static bool HasExactContract(MusicCatalogProbeInputV2 input)
        {
            if (input == null ||
                string.IsNullOrWhiteSpace(input.NormalizedPath) ||
                !IsUpperSha256(input.First64kSha256) ||
                !IsUpperSha256(input.CapabilityDigest) ||
                !IsUpperSha256(input.CacheKey))
            {
                return false;
            }

            MusicCatalogProbePolicyV2 policy =
                MusicCatalogProbePolicyV2.Production;
            return input.StableObservationCount ==
                    MusicCatalogProbePolicyV2.ProductionStableObservationCount &&
                input.StableIntervalMilliseconds ==
                    (uint)policy.StabilityInterval.TotalMilliseconds &&
                input.MaxFileBytes == (ulong)policy.MaxFileBytes &&
                input.FirstHashBytes == (uint)policy.FirstHashBytes &&
                input.MaxWallMilliseconds ==
                    (int)policy.ProbeMaxWall.TotalMilliseconds &&
                input.MaxInputBytes == policy.MaxInputBytes &&
                input.MaxDecodedFrames == policy.MaxDecodedFrames &&
                input.ProbeContractRevision ==
                    MusicCatalogProbePolicyV2.ProductionContractRevision &&
                input.StableObservationCount ==
                    AudioNativeV2.RuntimeProbeStableObservations &&
                input.StableIntervalMilliseconds ==
                    AudioNativeV2.RuntimeProbeStableIntervalMs &&
                input.MaxFileBytes == AudioNativeV2.RuntimeProbeMaxFileBytes &&
                input.MaxWallMilliseconds ==
                    (int)AudioNativeV2.RuntimeProbeMaxWallMs &&
                input.MaxInputBytes == AudioNativeV2.RuntimeProbeMaxInputBytes &&
                input.MaxDecodedFrames ==
                    AudioNativeV2.RuntimeProbeMaxDecodedFrames &&
                input.ProbeContractRevision == AudioNativeV2.ProbeContractRevision;
        }

        internal static MusicCatalogProbeResultV2 MapNativeResult(
            MusicCatalogProbeInputV2 input,
            AudioRuntimeProbeResultV2 native)
        {
            if (input == null) throw new ArgumentNullException("input");
            if (native == null || native.Result == null)
            {
                return CreateResult(
                    input,
                    MusicCatalogProbeOutcomeV2.InternalError,
                    false);
            }

            bool capabilityMatched = native.Valid && native.Result.IsOk;
            if (native.Valid)
            {
                if (native.Outcome == AudioNativeV2.ProbeCompatibleSignalPresent)
                {
                    return CreateResult(
                        input,
                        MusicCatalogProbeOutcomeV2.CompatibleSignalPresent,
                        capabilityMatched);
                }
                if (native.Outcome == AudioNativeV2.ProbeCompatibleSignalUnknown)
                {
                    return CreateResult(
                        input,
                        MusicCatalogProbeOutcomeV2.CompatibleSignalUnknown,
                        capabilityMatched);
                }
                if (native.Outcome ==
                    AudioNativeV2.ProbeInconclusiveTimeoutNotUnsupported)
                {
                    return CreateResult(
                        input,
                        MusicCatalogProbeOutcomeV2.InconclusiveTimeout,
                        capabilityMatched);
                }
            }

            return CreateResult(
                input,
                MapFailure(native.Result),
                false);
        }

        private static MusicCatalogProbeOutcomeV2 MapFailure(
            AudioNativeCallResultV2 result)
        {
            if (result == null) return MusicCatalogProbeOutcomeV2.InternalError;
            switch (result.Category)
            {
                case AudioNativeV2.ResultMissing:
                    return MusicCatalogProbeOutcomeV2.Missing;
                case AudioNativeV2.ResultUnsupportedContainer:
                    return MusicCatalogProbeOutcomeV2.UnsupportedContainer;
                case AudioNativeV2.ResultUnsupportedCodec:
                    return MusicCatalogProbeOutcomeV2.UnsupportedCodec;
                case AudioNativeV2.ResultMalformed:
                    return MusicCatalogProbeOutcomeV2.Malformed;
                case AudioNativeV2.ResultTruncated:
                    return MusicCatalogProbeOutcomeV2.Truncated;
                case AudioNativeV2.ResultIoError:
                    return MusicCatalogProbeOutcomeV2.IoError;
                case AudioNativeV2.ResultAbiMismatch:
                    return MusicCatalogProbeOutcomeV2.AbiMismatch;
                case AudioNativeV2.ResultNotReady:
                case AudioNativeV2.ResultStaleGeneration:
                case AudioNativeV2.ResultDeviceUnavailable:
                case AudioNativeV2.ResultDeviceLost:
                    return MusicCatalogProbeOutcomeV2.NotReady;
                case AudioNativeV2.ResultThrottled:
                    if (string.Equals(
                            result.MessageKey,
                            "audio.probe.runtime.unstable_input",
                            StringComparison.Ordinal) ||
                        string.Equals(
                            result.MessageKey,
                            "audio.probe.runtime.content_changed",
                            StringComparison.Ordinal))
                    {
                        return MusicCatalogProbeOutcomeV2.UnstableInput;
                    }
                    return MusicCatalogProbeOutcomeV2.Throttled;
                default:
                    return MusicCatalogProbeOutcomeV2.InternalError;
            }
        }

        private static MusicCatalogProbeResultV2 CreateResult(
            MusicCatalogProbeInputV2 input,
            MusicCatalogProbeOutcomeV2 outcome,
            bool capabilityMatched)
        {
            return new MusicCatalogProbeResultV2(
                outcome,
                input.CacheKey,
                input.CapabilityDigest,
                capabilityMatched);
        }

        private static bool IsUpperSha256(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                if ((character < '0' || character > '9') &&
                    (character < 'A' || character > 'F'))
                {
                    return false;
                }
            }
            return true;
        }
    }
}
