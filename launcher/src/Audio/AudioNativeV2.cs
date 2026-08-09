using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Blittable managed mirror of launcher/native/audio_bridge_v2.h.
    /// This type is intentionally not wired into AudioEngine until the native
    /// v2 implementation and its production capability handshake both exist.
    /// </summary>
    internal static class AudioNativeV2
    {
        internal const string DllName = "miniaudio.dll";

        internal const uint AbiMajor = 2u;
        internal const uint AbiMinor = 0u;
        internal const uint WireRevision = 2u;
        internal const uint ProbeContractRevision = 1u;

        internal const uint UuidV4TextCapacity = 37u;
        internal const uint Sha256HexCapacity = 65u;

        internal const uint RuntimeProbeMaxWallMs = 2000u;
        internal const ulong RuntimeProbeMaxDecodedFrames = 96000u;
        internal const ulong RuntimeProbeMaxInputBytes = 8388608u;
        internal const ulong RuntimeProbeMaxFileBytes = 536870912u;
        internal const uint RuntimeProbeStableObservations = 2u;
        internal const uint RuntimeProbeStableIntervalMs = 1000u;
        internal const uint OfflineProbeMaxWallMs = 120000u;

        internal const uint False = 0u;
        internal const uint True = 1u;

        internal const uint ResultOk = 0u;
        internal const uint ResultMissing = 1u;
        internal const uint ResultUnsupportedContainer = 2u;
        internal const uint ResultUnsupportedCodec = 3u;
        internal const uint ResultMalformed = 4u;
        internal const uint ResultTruncated = 5u;
        internal const uint ResultIoError = 6u;
        internal const uint ResultAbiMismatch = 7u;
        internal const uint ResultNotReady = 8u;
        internal const uint ResultStaleGeneration = 9u;
        internal const uint ResultUnknownId = 10u;
        internal const uint ResultThrottled = 11u;
        internal const uint ResultStartFailed = 12u;
        internal const uint ResultSeekFailed = 13u;
        internal const uint ResultDeviceUnavailable = 14u;
        internal const uint ResultDeviceLost = 15u;
        internal const uint ResultSuperseded = 16u;
        internal const uint ResultInternalError = 17u;

        internal const uint AudioInitializing = 1u;
        internal const uint AudioReady = 2u;
        internal const uint AudioRecovering = 3u;
        internal const uint AudioFailedNoOutput = 4u;
        internal const uint AudioShutdown = 5u;

        internal const uint BackendNone = 0u;
        internal const uint BackendWasapi = 1u;
        internal const uint BackendDirectSound = 2u;
        internal const uint BackendWinMm = 3u;
        internal const uint BackendTestOnlyNull = 4u;

        internal const uint BackendMaskWasapi = 0x00000001u;
        internal const uint BackendMaskDirectSound = 0x00000002u;
        internal const uint BackendMaskWinMm = 0x00000004u;
        internal const uint BackendMaskTestOnlyNull = 0x80000000u;
        internal const uint BackendMaskProduction =
            BackendMaskWasapi | BackendMaskDirectSound | BackendMaskWinMm;

        internal const ulong DecoderBackendBuiltin = 0x0000000000000001uL;
        internal const ulong DecoderBackendLibVorbis = 0x0000000000000002uL;
        internal const ulong DecoderBackendMediaFoundation = 0x0000000000000004uL;
        internal const ulong DecoderBackendLibOpus = 0x0000000000000008uL;
        internal const ulong RequiredDecoderBackends =
            DecoderBackendBuiltin |
            DecoderBackendLibVorbis |
            DecoderBackendMediaFoundation |
            DecoderBackendLibOpus;

        internal const ulong ContainerRiffWave = 0x0000000000000001uL;
        internal const ulong ContainerMpegAudio = 0x0000000000000002uL;
        internal const ulong ContainerNativeFlac = 0x0000000000000004uL;
        internal const ulong ContainerOgg = 0x0000000000000008uL;
        internal const ulong ContainerMpeg4 = 0x0000000000000010uL;
        internal const ulong ContainerAdts = 0x0000000000000020uL;
        internal const ulong RequiredContainers =
            ContainerRiffWave |
            ContainerMpegAudio |
            ContainerNativeFlac |
            ContainerOgg |
            ContainerMpeg4 |
            ContainerAdts;

        internal const ulong CodecPcmOrIeeeFloat = 0x0000000000000001uL;
        internal const ulong CodecMpegAudioLayerIii = 0x0000000000000002uL;
        internal const ulong CodecFlac = 0x0000000000000004uL;
        internal const ulong CodecVorbis = 0x0000000000000008uL;
        internal const ulong CodecAacLcOrHeAac = 0x0000000000000010uL;
        internal const ulong CodecOpus = 0x0000000000000020uL;
        internal const ulong RequiredCodecs =
            CodecPcmOrIeeeFloat |
            CodecMpegAudioLayerIii |
            CodecFlac |
            CodecVorbis |
            CodecAacLcOrHeAac |
            CodecOpus;

        internal const ulong ExtensionWav = 0x0000000000000001uL;
        internal const ulong ExtensionMp3 = 0x0000000000000002uL;
        internal const ulong ExtensionFlac = 0x0000000000000004uL;
        internal const ulong ExtensionOgg = 0x0000000000000008uL;
        internal const ulong ExtensionM4a = 0x0000000000000010uL;
        internal const ulong ExtensionMp4 = 0x0000000000000020uL;
        internal const ulong ExtensionAac = 0x0000000000000040uL;
        internal const ulong ExtensionAdts = 0x0000000000000080uL;
        internal const ulong ExtensionOpus = 0x0000000000000100uL;
        internal const ulong RequiredExtensions =
            ExtensionWav |
            ExtensionMp3 |
            ExtensionFlac |
            ExtensionOgg |
            ExtensionM4a |
            ExtensionMp4 |
            ExtensionAac |
            ExtensionAdts |
            ExtensionOpus;

        internal const uint SampleFormatUnknown = 0u;
        internal const uint SampleFormatF32 = 1u;
        internal const uint SampleFormatS16 = 2u;
        internal const uint SampleFormatS24 = 3u;
        internal const uint SampleFormatS32 = 4u;

        internal const uint CompletionNone = 0u;
        internal const uint CompletionAcceptedDeferred = 1u;
        internal const uint CompletionStarted = 2u;
        internal const uint CompletionStopped = 3u;
        internal const uint CompletionSuperseded = 4u;
        internal const uint CompletionFailed = 5u;

        internal const uint OperationNone = 0u;
        internal const uint OperationQueryCapability = 1u;
        internal const uint OperationInitialize = 2u;
        internal const uint OperationQueryRuntime = 3u;
        internal const uint OperationQueryMeter = 4u;
        internal const uint OperationBgmPlay = 10u;
        internal const uint OperationBgmStop = 11u;
        internal const uint OperationBgmPause = 12u;
        internal const uint OperationBgmResume = 13u;
        internal const uint OperationBgmSeek = 14u;
        internal const uint OperationBgmSetLoop = 15u;
        internal const uint OperationBgmSetGain = 16u;
        internal const uint OperationSfxRebuildCatalog = 20u;
        internal const uint OperationSfxPlayBatch = 21u;
        internal const uint OperationSfxSetGain = 22u;
        internal const uint OperationSetMasterGain = 23u;
        internal const uint OperationRuntimeProbe = 30u;
        internal const uint OperationOfflineProbe = 31u;
        internal const uint OperationShutdown = 40u;

        internal const uint StageNone = 0u;
        internal const uint StageValidateAbi = 1u;
        internal const uint StageValidateCapacity = 2u;
        internal const uint StageValidateSession = 3u;
        internal const uint StageValidatePath = 4u;
        internal const uint StageAdmission = 5u;
        internal const uint StageContextInitialize = 10u;
        internal const uint StageDeviceInitialize = 11u;
        internal const uint StageDeviceStart = 12u;
        internal const uint StageDecoderInitialize = 20u;
        internal const uint StageSourceInitialize = 21u;
        internal const uint StageNativeStart = 22u;
        internal const uint StageSeek = 23u;
        internal const uint StageProbeInput = 30u;
        internal const uint StageProbeDecode = 31u;
        internal const uint StageShutdown = 40u;

        internal const uint BufferReadOnly = 0x00000001u;
        internal const uint BufferWriteOnly = 0x00000002u;

        internal const uint ProbeOutcomeNone = 0u;
        internal const uint ProbeCompatibleSignalPresent = 1u;
        internal const uint ProbeCompatibleSignalUnknown = 2u;
        internal const uint ProbeIncompatible = 3u;
        internal const uint ProbeInconclusiveTimeoutNotUnsupported = 4u;
        internal const uint ProbeQualificationPassed = 5u;
        internal const uint ProbeQualificationFailedTimeout = 6u;
        internal const uint ProbeQualificationFailed = 7u;

        internal const uint EofNotRequired = 0u;
        internal const uint EofReached = 1u;
        internal const uint EofNotReached = 2u;

        internal const uint MeterBgmPreMaster = 1u;
        internal const uint MeterSfxPreMaster = 2u;

        internal const uint ExecutionProduction = 0x50524F44u;
        internal const uint ExecutionIsolatedTest = 0x54455354u;

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct StructHeader
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct Version
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal uint major;
            internal uint minor;
            internal uint patch;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct Utf8Buffer
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal ulong dataAddress;
            internal uint capacityBytes;
            internal uint lengthBytes;
            internal uint requiredBytes;
            internal uint flags;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct Utf16Buffer
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal ulong dataAddress;
            internal uint capacityCodeUnits;
            internal uint lengthCodeUnits;
            internal uint requiredCodeUnits;
            internal uint flags;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct ArrayBuffer
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal ulong dataAddress;
            internal uint elementSize;
            internal uint capacityElements;
            internal uint countElements;
            internal uint requiredElements;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct Result
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal uint category;
            internal uint operation;
            internal uint stage;
            internal int rawMaResult;
            internal int rawHresult;
            internal uint completionState;
            internal uint reserved0;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal ulong deviceGeneration;
            internal Utf8Buffer messageKey;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct Capability
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Version abiVersion;
            internal Utf8Buffer bridgeBuildId;
            internal Version miniaudioVersion;
            internal ulong decoderBackends;
            internal ulong containers;
            internal ulong codecs;
            internal ulong extensions;
            internal uint compiledBackendMask;
            internal uint supportsRuntimeCompatibilityProbe;
            internal uint supportsOfflineQualificationProbe;
            internal uint supportsSeek;
            internal uint supportsLoop;
            internal uint supportsDeviceRecovery;
            internal uint supportsBgmMeter;
            internal uint supportsSfxMeter;
            internal uint testOnlyNullEnabled;
            internal Utf8Buffer capabilityDigestSha256;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct RuntimeSnapshot
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal uint audioStatus;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal ulong deviceGeneration;
            internal uint selectedBackend;
            internal Utf8Buffer selectedDeviceIdDigest;
            internal Utf16Buffer selectedDeviceName;
            internal uint sampleRate;
            internal uint channels;
            internal uint sampleFormat;
            internal Result lastStructuredFailure;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct MeterSnapshot
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal uint bus;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal ulong deviceGeneration;
            internal float peakLeft;
            internal float peakRight;
            internal float rmsLeft;
            internal float rmsRight;
            internal ulong clipCount;
            internal ulong frameCount;
            internal ulong underrunCount;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct SourceSnapshot
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal ulong deviceGeneration;
            internal ulong decoder;
            internal ulong container;
            internal ulong codec;
            internal ulong cursorFrames;
            internal ulong lengthFrames;
            internal uint playing;
            internal float sourceGroupMasterGain;
            internal Result startResult;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct SfxCounters
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal ulong preReadyDrops;
            internal ulong recoveryDrops;
            internal ulong staleGenerationDrops;
            internal ulong unknownIdCount;
            internal ulong throttledCount;
            internal ulong startFailureCount;
            internal ulong playedCount;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct InitializeCommand
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf16Buffer normalizedBasePath;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal uint executionIdentity;
            internal uint reserved0;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct BgmCommand
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal uint wireRevision;
            internal Utf8Buffer requestId;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal uint operation;
            internal Utf16Buffer normalizedPath;
            internal uint loop;
            internal float volume;
            internal float fadeSeconds;
            internal float seekSeconds;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct SfxCatalogItem
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf8Buffer linkageId;
            internal Utf16Buffer normalizedPath;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct SfxCatalogCommand
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal ArrayBuffer items;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct SfxPlayItem
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf8Buffer linkageId;
            internal float volume;
            internal uint reserved0;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct SfxBatchCommand
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal uint wireRevision;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal ulong batchSequence;
            internal ArrayBuffer linkageIds;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct GainCommand
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
            internal uint operation;
            internal float gain;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct RuntimeProbeCommand
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf16Buffer normalizedPath;
            internal ulong fileSizeBytes;
            internal long modifiedTimeUnixMilliseconds;
            internal Utf8Buffer first64kSha256;
            internal Utf8Buffer capabilityDigestSha256;
            internal uint probeContractRevision;
            internal uint maxWallMs;
            internal ulong maxDecodedFrames;
            internal ulong maxInputBytes;
            internal ulong maxFileBytes;
            internal uint stableObservationCount;
            internal uint stableIntervalMs;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct OfflineProbeCommand
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf16Buffer normalizedPath;
            internal Utf8Buffer fullSha256;
            internal Utf8Buffer capabilityDigestSha256;
            internal uint probeContractRevision;
            internal uint maxWallMs;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct ProbeResult
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Result structuredResult;
            internal uint outcome;
            internal uint eofState;
            internal ulong frames;
            internal double durationSeconds;
            internal double peak;
            internal double rms;
            internal ulong leadingSilenceFrames;
            internal ulong trailingSilenceFrames;
            internal ulong nonFiniteCount;
            internal uint elapsedMs;
            internal uint reserved0;
            internal ulong inputBytesRead;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        internal struct ShutdownCommand
        {
            internal uint structSize;
            internal uint abiMajor;
            internal uint abiMinor;
            internal Utf8Buffer audioSessionId;
            internal ulong audioReadyGeneration;
        }

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_query_capability")]
        internal static extern uint QueryCapability(
            [In, Out] ref Capability capability,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_initialize")]
        internal static extern uint Initialize(
            [In] ref InitializeCommand command,
            [In, Out] ref RuntimeSnapshot runtimeSnapshot,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_query_runtime")]
        internal static extern uint QueryRuntime(
            [In, Out] ref RuntimeSnapshot runtimeSnapshot,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_query_meter")]
        internal static extern uint QueryMeter(
            [In, Out] ref MeterSnapshot meterSnapshot,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_query_bgm_source")]
        internal static extern uint QueryBgmSource(
            [In, Out] ref SourceSnapshot sourceSnapshot,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_query_sfx_counters")]
        internal static extern uint QuerySfxCounters(
            [In, Out] ref SfxCounters counters,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_submit_bgm")]
        internal static extern uint SubmitBgm(
            [In] ref BgmCommand command,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_rebuild_sfx_catalog")]
        internal static extern uint RebuildSfxCatalog(
            [In] ref SfxCatalogCommand command,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_submit_sfx_batch")]
        internal static extern uint SubmitSfxBatch(
            [In] ref SfxBatchCommand command,
            [In, Out] ref SfxCounters counters,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_set_gain")]
        internal static extern uint SetGain(
            [In] ref GainCommand command,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_probe_runtime_compatibility")]
        internal static extern uint ProbeRuntimeCompatibility(
            [In] ref RuntimeProbeCommand command,
            [In, Out] ref ProbeResult probeResult,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_probe_offline_qualification")]
        internal static extern uint ProbeOfflineQualification(
            [In] ref OfflineProbeCommand command,
            [In, Out] ref ProbeResult probeResult,
            [In, Out] ref Result result);

        [DllImport(
            DllName,
            CallingConvention = CallingConvention.Cdecl,
            ExactSpelling = true,
            EntryPoint = "cf7_audio_bridge_v2_shutdown")]
        internal static extern uint Shutdown(
            [In] ref ShutdownCommand command,
            [In, Out] ref Result result);

        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);

        internal static bool IsPrefixAccepted(
            uint structSize,
            uint abiMajor,
            uint abiMinor,
            uint minimumSize)
        {
            return structSize >= minimumSize &&
                abiMajor == AbiMajor &&
                abiMinor <= AbiMinor;
        }

        internal static bool TryCreateUtf8Buffer(
            IntPtr address,
            uint capacityBytes,
            uint flags,
            out Utf8Buffer value)
        {
            value = default(Utf8Buffer);
            if ((flags != BufferReadOnly && flags != BufferWriteOnly) ||
                ((address == IntPtr.Zero) != (capacityBytes == 0u)))
            {
                return false;
            }
            value.structSize = (uint)Marshal.SizeOf<Utf8Buffer>();
            value.abiMajor = AbiMajor;
            value.abiMinor = AbiMinor;
            value.dataAddress = ToAddress(address);
            value.capacityBytes = capacityBytes;
            value.flags = flags;
            return true;
        }

        internal static bool TryCreateUtf16Buffer(
            IntPtr address,
            uint capacityCodeUnits,
            uint flags,
            out Utf16Buffer value)
        {
            value = default(Utf16Buffer);
            if ((flags != BufferReadOnly && flags != BufferWriteOnly) ||
                ((address == IntPtr.Zero) != (capacityCodeUnits == 0u)))
            {
                return false;
            }
            value.structSize = (uint)Marshal.SizeOf<Utf16Buffer>();
            value.abiMajor = AbiMajor;
            value.abiMinor = AbiMinor;
            value.dataAddress = ToAddress(address);
            value.capacityCodeUnits = capacityCodeUnits;
            value.flags = flags;
            return true;
        }

        internal static bool TryCreateArrayBuffer(
            IntPtr address,
            uint elementSize,
            uint capacityElements,
            uint countElements,
            out ArrayBuffer value)
        {
            value = default(ArrayBuffer);
            if (elementSize == 0u ||
                countElements > capacityElements ||
                (capacityElements > 0u && address == IntPtr.Zero))
            {
                return false;
            }

            value.structSize = (uint)Marshal.SizeOf<ArrayBuffer>();
            value.abiMajor = AbiMajor;
            value.abiMinor = AbiMinor;
            value.dataAddress = ToAddress(address);
            value.elementSize = elementSize;
            value.capacityElements = capacityElements;
            value.countElements = countElements;
            return true;
        }

        internal static bool TryWriteUtf8ToCallerOwnedMemory(
            ref Utf8Buffer buffer,
            string text)
        {
            byte[] payload;
            uint required;
            IntPtr destination;
            if (!IsPrefixAccepted(
                    buffer.structSize,
                    buffer.abiMajor,
                    buffer.abiMinor,
                    (uint)Marshal.SizeOf<Utf8Buffer>()) ||
                buffer.flags != BufferWriteOnly ||
                text == null ||
                text.IndexOf('\0') >= 0)
            {
                return false;
            }

            try
            {
                payload = StrictUtf8.GetBytes(text);
            }
            catch (EncoderFallbackException)
            {
                return false;
            }

            required = checked((uint)payload.Length + 1u);
            buffer.requiredBytes = required;
            buffer.lengthBytes = 0u;
            if (buffer.dataAddress == 0uL || buffer.capacityBytes < required)
            {
                return false;
            }

            destination = ToIntPtr(buffer.dataAddress);
            Marshal.Copy(payload, 0, destination, payload.Length);
            Marshal.WriteByte(destination, payload.Length, (byte)0u);
            buffer.lengthBytes = (uint)payload.Length;
            return true;
        }

        internal static bool TryWriteUtf16ToCallerOwnedMemory(
            ref Utf16Buffer buffer,
            string text)
        {
            uint required;
            IntPtr destination;
            int index;
            if (!IsPrefixAccepted(
                    buffer.structSize,
                    buffer.abiMajor,
                    buffer.abiMinor,
                    (uint)Marshal.SizeOf<Utf16Buffer>()) ||
                buffer.flags != BufferWriteOnly ||
                text == null ||
                text.IndexOf('\0') >= 0)
            {
                return false;
            }

            required = checked((uint)text.Length + 1u);
            buffer.requiredCodeUnits = required;
            buffer.lengthCodeUnits = 0u;
            if (buffer.dataAddress == 0uL ||
                buffer.capacityCodeUnits < required)
            {
                return false;
            }

            destination = ToIntPtr(buffer.dataAddress);
            for (index = 0; index < text.Length; index++)
            {
                Marshal.WriteInt16(
                    destination,
                    checked(index * sizeof(char)),
                    unchecked((short)text[index]));
            }
            Marshal.WriteInt16(
                destination,
                checked(text.Length * sizeof(char)),
                0);
            buffer.lengthCodeUnits = (uint)text.Length;
            return true;
        }

        internal static bool IsProductionCapabilityAccepted(
            ref Capability capability)
        {
            string bridgeBuildId;
            string capabilityDigest;
            if (!IsPrefixAccepted(
                    capability.structSize,
                    capability.abiMajor,
                    capability.abiMinor,
                    (uint)Marshal.SizeOf<Capability>()) ||
                !IsPrefixAccepted(
                    capability.abiVersion.structSize,
                    capability.abiVersion.abiMajor,
                    capability.abiVersion.abiMinor,
                    (uint)Marshal.SizeOf<Version>()) ||
                capability.abiVersion.major != AbiMajor ||
                capability.abiVersion.minor != AbiMinor ||
                !IsPrefixAccepted(
                    capability.miniaudioVersion.structSize,
                    capability.miniaudioVersion.abiMajor,
                    capability.miniaudioVersion.abiMinor,
                    (uint)Marshal.SizeOf<Version>()) ||
                (capability.miniaudioVersion.major == 0u &&
                    capability.miniaudioVersion.minor == 0u &&
                    capability.miniaudioVersion.patch == 0u) ||
                capability.compiledBackendMask != BackendMaskProduction ||
                capability.decoderBackends != RequiredDecoderBackends ||
                capability.containers != RequiredContainers ||
                capability.codecs != RequiredCodecs ||
                capability.extensions != RequiredExtensions ||
                capability.supportsRuntimeCompatibilityProbe != True ||
                capability.supportsOfflineQualificationProbe != True ||
                capability.supportsSeek != True ||
                capability.supportsLoop != True ||
                capability.supportsDeviceRecovery != True ||
                capability.supportsBgmMeter != True ||
                capability.supportsSfxMeter != True ||
                capability.testOnlyNullEnabled != False ||
                !TryReadCompletedUtf8(
                    ref capability.bridgeBuildId,
                    out bridgeBuildId) ||
                string.IsNullOrWhiteSpace(bridgeBuildId) ||
                !TryReadCompletedUtf8(
                    ref capability.capabilityDigestSha256,
                    out capabilityDigest) ||
                !IsSha256Hex(capabilityDigest))
            {
                return false;
            }

            return true;
        }

        internal static bool IsProductionReadyHandshakeAccepted(
            ref Capability capability,
            ref RuntimeSnapshot runtimeSnapshot,
            string expectedAudioSessionId,
            ulong expectedAudioReadyGeneration)
        {
            string actualAudioSessionId;
            string selectedDeviceIdDigest;
            string selectedDeviceName;
            if (!IsProductionCapabilityAccepted(ref capability) ||
                string.IsNullOrEmpty(expectedAudioSessionId) ||
                !IsUuidV4Lowercase(expectedAudioSessionId) ||
                expectedAudioReadyGeneration == 0uL ||
                !IsPrefixAccepted(
                    runtimeSnapshot.structSize,
                    runtimeSnapshot.abiMajor,
                    runtimeSnapshot.abiMinor,
                    (uint)Marshal.SizeOf<RuntimeSnapshot>()) ||
                runtimeSnapshot.audioStatus != AudioReady ||
                runtimeSnapshot.audioReadyGeneration !=
                    expectedAudioReadyGeneration ||
                runtimeSnapshot.deviceGeneration == 0uL ||
                !IsProductionBackend(runtimeSnapshot.selectedBackend) ||
                runtimeSnapshot.sampleRate == 0u ||
                runtimeSnapshot.channels == 0u ||
                !IsKnownSampleFormat(runtimeSnapshot.sampleFormat) ||
                !IsPrefixAccepted(
                    runtimeSnapshot.lastStructuredFailure.structSize,
                    runtimeSnapshot.lastStructuredFailure.abiMajor,
                    runtimeSnapshot.lastStructuredFailure.abiMinor,
                    (uint)Marshal.SizeOf<Result>()) ||
                runtimeSnapshot.lastStructuredFailure.category != ResultOk ||
                !TryReadCompletedUtf8(
                    ref runtimeSnapshot.audioSessionId,
                    out actualAudioSessionId) ||
                !string.Equals(
                    expectedAudioSessionId,
                    actualAudioSessionId,
                    StringComparison.Ordinal) ||
                !TryReadCompletedUtf8(
                    ref runtimeSnapshot.selectedDeviceIdDigest,
                    out selectedDeviceIdDigest) ||
                !IsSha256Hex(selectedDeviceIdDigest) ||
                !TryReadCompletedUtf16(
                    ref runtimeSnapshot.selectedDeviceName,
                    out selectedDeviceName) ||
                string.IsNullOrWhiteSpace(selectedDeviceName))
            {
                return false;
            }

            return true;
        }

        internal static bool IsArrayBufferValid(
            ref ArrayBuffer buffer,
            uint expectedElementSize)
        {
            return IsPrefixAccepted(
                    buffer.structSize,
                    buffer.abiMajor,
                    buffer.abiMinor,
                    (uint)Marshal.SizeOf<ArrayBuffer>()) &&
                expectedElementSize != 0u &&
                buffer.elementSize == expectedElementSize &&
                buffer.countElements <= buffer.capacityElements &&
                (buffer.capacityElements == 0u || buffer.dataAddress != 0uL);
        }

        private static bool TryReadCompletedUtf8(
            ref Utf8Buffer buffer,
            out string value)
        {
            byte[] payload;
            IntPtr address;
            value = null;
            if (!IsPrefixAccepted(
                    buffer.structSize,
                    buffer.abiMajor,
                    buffer.abiMinor,
                    (uint)Marshal.SizeOf<Utf8Buffer>()) ||
                buffer.flags != BufferWriteOnly ||
                buffer.dataAddress == 0uL ||
                buffer.capacityBytes == 0u ||
                buffer.requiredBytes == 0u ||
                buffer.requiredBytes > buffer.capacityBytes ||
                buffer.lengthBytes > 4096u ||
                buffer.lengthBytes + 1u != buffer.requiredBytes)
            {
                return false;
            }

            address = ToIntPtr(buffer.dataAddress);
            if (Marshal.ReadByte(address, checked((int)buffer.lengthBytes)) != 0u)
            {
                return false;
            }

            payload = new byte[(int)buffer.lengthBytes];
            Marshal.Copy(address, payload, 0, payload.Length);
            try
            {
                value = StrictUtf8.GetString(payload);
            }
            catch (DecoderFallbackException)
            {
                return false;
            }
            return value.IndexOf('\0') < 0;
        }

        private static bool TryReadCompletedUtf16(
            ref Utf16Buffer buffer,
            out string value)
        {
            char[] payload;
            IntPtr address;
            int index;
            value = null;
            if (!IsPrefixAccepted(
                    buffer.structSize,
                    buffer.abiMajor,
                    buffer.abiMinor,
                    (uint)Marshal.SizeOf<Utf16Buffer>()) ||
                buffer.flags != BufferWriteOnly ||
                buffer.dataAddress == 0uL ||
                buffer.capacityCodeUnits == 0u ||
                buffer.requiredCodeUnits == 0u ||
                buffer.requiredCodeUnits > buffer.capacityCodeUnits ||
                buffer.lengthCodeUnits > 1024u ||
                buffer.lengthCodeUnits + 1u != buffer.requiredCodeUnits)
            {
                return false;
            }

            address = ToIntPtr(buffer.dataAddress);
            if (Marshal.ReadInt16(
                    address,
                    checked((int)buffer.lengthCodeUnits * sizeof(char))) != 0)
            {
                return false;
            }

            payload = new char[(int)buffer.lengthCodeUnits];
            for (index = 0; index < payload.Length; index++)
            {
                payload[index] = unchecked((char)Marshal.ReadInt16(
                    address,
                    checked(index * sizeof(char))));
            }
            value = new string(payload);
            return value.IndexOf('\0') < 0;
        }

        private static bool IsProductionBackend(uint backend)
        {
            return backend == BackendWasapi ||
                backend == BackendDirectSound ||
                backend == BackendWinMm;
        }

        private static bool IsKnownSampleFormat(uint sampleFormat)
        {
            return sampleFormat == SampleFormatF32 ||
                sampleFormat == SampleFormatS16 ||
                sampleFormat == SampleFormatS24 ||
                sampleFormat == SampleFormatS32;
        }

        private static bool IsSha256Hex(string value)
        {
            int index;
            char valueChar;
            if (value == null || value.Length != 64)
            {
                return false;
            }
            for (index = 0; index < value.Length; index++)
            {
                valueChar = value[index];
                if (!((valueChar >= '0' && valueChar <= '9') ||
                    (valueChar >= 'A' && valueChar <= 'F') ||
                    (valueChar >= 'a' && valueChar <= 'f')))
                {
                    return false;
                }
            }
            return true;
        }

        private static bool IsUuidV4Lowercase(string value)
        {
            Guid parsed;
            char variant;
            if (value == null ||
                value.Length != 36 ||
                !Guid.TryParseExact(value, "D", out parsed) ||
                !string.Equals(
                    parsed.ToString("D"),
                    value,
                    StringComparison.Ordinal) ||
                value[14] != '4')
            {
                return false;
            }
            variant = value[19];
            return variant == '8' ||
                variant == '9' ||
                variant == 'a' ||
                variant == 'b';
        }

        private static ulong ToAddress(IntPtr value)
        {
            if (IntPtr.Size != sizeof(ulong))
            {
                throw new PlatformNotSupportedException(
                    "Audio Platform v2 ABI is win-x64 only.");
            }
            return unchecked((ulong)value.ToInt64());
        }

        private static IntPtr ToIntPtr(ulong value)
        {
            if (IntPtr.Size != sizeof(ulong))
            {
                throw new PlatformNotSupportedException(
                    "Audio Platform v2 ABI is win-x64 only.");
            }
            return new IntPtr(unchecked((long)value));
        }
    }
}
