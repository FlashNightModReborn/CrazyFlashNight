using System;
using CF7Launcher.Audio;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class AudioMusicCatalogProbePortV2Tests
    {
        [Fact]
        public void ExactContract_MatchesFrozenRuntimeProbeBounds()
        {
            MusicCatalogProbeInputV2 input = ExactInput();

            Assert.True(AudioMusicCatalogProbePortV2.HasExactContract(input));
        }

        [Fact]
        public void Contract_RejectsLowercaseDigestAndBoundDrift()
        {
            MusicCatalogProbeInputV2 lowercase = ExactInput(
                capabilityDigest: new string('a', 64));
            MusicCatalogProbeInputV2 drift = ExactInput(
                maxInputBytes: AudioNativeV2.RuntimeProbeMaxInputBytes + 1UL);

            Assert.False(AudioMusicCatalogProbePortV2.HasExactContract(lowercase));
            Assert.False(AudioMusicCatalogProbePortV2.HasExactContract(drift));
        }

        [Theory]
        [InlineData(
            AudioNativeV2.ProbeCompatibleSignalPresent,
            (int)MusicCatalogProbeOutcomeV2.CompatibleSignalPresent)]
        [InlineData(
            AudioNativeV2.ProbeCompatibleSignalUnknown,
            (int)MusicCatalogProbeOutcomeV2.CompatibleSignalUnknown)]
        [InlineData(
            AudioNativeV2.ProbeInconclusiveTimeoutNotUnsupported,
            (int)MusicCatalogProbeOutcomeV2.InconclusiveTimeout)]
        public void NativePositiveOutcomes_MapWithoutExtensionInference(
            uint nativeOutcome,
            int expected)
        {
            MusicCatalogProbeInputV2 input = ExactInput();
            AudioRuntimeProbeResultV2 native = NativeResult(
                true,
                nativeOutcome,
                AudioNativeV2.ResultOk,
                "audio.probe.runtime.complete");

            MusicCatalogProbeResultV2 mapped =
                AudioMusicCatalogProbePortV2.MapNativeResult(input, native);

            Assert.Equal((MusicCatalogProbeOutcomeV2)expected, mapped.Outcome);
            Assert.Equal(input.CacheKey, mapped.CacheKey);
            Assert.Equal(input.CapabilityDigest, mapped.CapabilityDigest);
            Assert.True(mapped.CapabilityMatched);
        }

        [Theory]
        [InlineData(
            AudioNativeV2.ResultMissing,
            (int)MusicCatalogProbeOutcomeV2.Missing)]
        [InlineData(
            AudioNativeV2.ResultUnsupportedContainer,
            (int)MusicCatalogProbeOutcomeV2.UnsupportedContainer)]
        [InlineData(
            AudioNativeV2.ResultUnsupportedCodec,
            (int)MusicCatalogProbeOutcomeV2.UnsupportedCodec)]
        [InlineData(
            AudioNativeV2.ResultMalformed,
            (int)MusicCatalogProbeOutcomeV2.Malformed)]
        [InlineData(
            AudioNativeV2.ResultTruncated,
            (int)MusicCatalogProbeOutcomeV2.Truncated)]
        [InlineData(
            AudioNativeV2.ResultIoError,
            (int)MusicCatalogProbeOutcomeV2.IoError)]
        [InlineData(
            AudioNativeV2.ResultAbiMismatch,
            (int)MusicCatalogProbeOutcomeV2.AbiMismatch)]
        [InlineData(
            AudioNativeV2.ResultDeviceLost,
            (int)MusicCatalogProbeOutcomeV2.NotReady)]
        public void NativeFailureCategory_MapsToTypedCatalogOutcome(
            uint category,
            int expected)
        {
            MusicCatalogProbeResultV2 mapped =
                AudioMusicCatalogProbePortV2.MapNativeResult(
                    ExactInput(),
                    NativeResult(
                        true,
                        AudioNativeV2.ProbeIncompatible,
                        category,
                        "audio.probe.runtime.failed"));

            Assert.Equal((MusicCatalogProbeOutcomeV2)expected, mapped.Outcome);
            Assert.False(mapped.CapabilityMatched);
        }

        [Theory]
        [InlineData("audio.probe.runtime.unstable_input")]
        [InlineData("audio.probe.runtime.content_changed")]
        public void NativeInputRace_IsProbingNotUnsupported(string messageKey)
        {
            MusicCatalogProbeResultV2 mapped =
                AudioMusicCatalogProbePortV2.MapNativeResult(
                    ExactInput(),
                    NativeResult(
                        false,
                        AudioNativeV2.ProbeOutcomeNone,
                        AudioNativeV2.ResultThrottled,
                        messageKey));

            Assert.Equal(MusicCatalogProbeOutcomeV2.UnstableInput, mapped.Outcome);
            Assert.False(mapped.CapabilityMatched);
        }

        [Fact]
        public void PositiveClaimWithNonOkResult_RemainsFailClosed()
        {
            MusicCatalogProbeResultV2 mapped =
                AudioMusicCatalogProbePortV2.MapNativeResult(
                    ExactInput(),
                    NativeResult(
                        true,
                        AudioNativeV2.ProbeCompatibleSignalPresent,
                        AudioNativeV2.ResultInternalError,
                        "audio.probe.runtime.invalid_result"));

            Assert.Equal(
                MusicCatalogProbeOutcomeV2.CompatibleSignalPresent,
                mapped.Outcome);
            Assert.False(mapped.CapabilityMatched);
        }

        [Fact]
        public void NullNativeResult_IsInternalErrorWithExactEcho()
        {
            MusicCatalogProbeInputV2 input = ExactInput();

            MusicCatalogProbeResultV2 mapped =
                AudioMusicCatalogProbePortV2.MapNativeResult(input, null);

            Assert.Equal(MusicCatalogProbeOutcomeV2.InternalError, mapped.Outcome);
            Assert.Equal(input.CacheKey, mapped.CacheKey);
            Assert.Equal(input.CapabilityDigest, mapped.CapabilityDigest);
            Assert.False(mapped.CapabilityMatched);
        }

        private static MusicCatalogProbeInputV2 ExactInput(
            string capabilityDigest = null,
            ulong? maxInputBytes = null)
        {
            return new MusicCatalogProbeInputV2(
                "C:/fixture/audio.m4a",
                4096UL,
                638900000000000000L,
                1770000000000L,
                new string('A', 64),
                capabilityDigest ?? new string('B', 64),
                new string('C', 64),
                ".m4a",
                MusicCatalog.DecoderMediaFoundation,
                MusicCatalog.ContainerMpeg4,
                MusicCatalog.CodecAacLcOrHeAac,
                false,
                AudioNativeV2.RuntimeProbeStableObservations,
                AudioNativeV2.RuntimeProbeStableIntervalMs,
                AudioNativeV2.RuntimeProbeMaxFileBytes,
                65536u,
                (int)AudioNativeV2.RuntimeProbeMaxWallMs,
                maxInputBytes ?? AudioNativeV2.RuntimeProbeMaxInputBytes,
                AudioNativeV2.RuntimeProbeMaxDecodedFrames,
                AudioNativeV2.ProbeContractRevision);
        }

        private static AudioRuntimeProbeResultV2 NativeResult(
            bool valid,
            uint outcome,
            uint category,
            string messageKey)
        {
            var result = new AudioNativeCallResultV2(
                category,
                AudioNativeV2.OperationRuntimeProbe,
                AudioNativeV2.StageProbeDecode,
                0,
                0,
                category == AudioNativeV2.ResultOk
                    ? AudioNativeV2.CompletionNone
                    : AudioNativeV2.CompletionFailed,
                "00000000-0000-4000-8000-000000000001",
                1UL,
                1UL,
                messageKey,
                "media_foundation");
            return new AudioRuntimeProbeResultV2(
                valid,
                outcome,
                48000UL,
                1d,
                0.5d,
                0.1d,
                10u,
                1024UL,
                result);
        }
    }
}
