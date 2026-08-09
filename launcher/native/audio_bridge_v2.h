#ifndef CF7_AUDIO_BRIDGE_V2_H
#define CF7_AUDIO_BRIDGE_V2_H

/*
 * CF7 Audio Platform v2 public C ABI.
 *
 * This header is intentionally independent from miniaudio and the Windows SDK.
 * Every structure that can cross the DLL boundary starts with the same 12-byte
 * version prefix. All scalar ABI values have explicit widths; no C enum, bool,
 * size_t, wchar_t, HANDLE, HRESULT typedef, or miniaudio type crosses the ABI.
 *
 * Caller-owned memory is represented by a 64-bit address plus explicit
 * capacity, used length and required length. The production runtime is win-x64;
 * zero is the only null address. UTF-16 capacities and lengths are code units,
 * while UTF-8 capacities and lengths are bytes. Required lengths include the
 * terminating zero for text buffers.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#if defined(CF7_AUDIO_BRIDGE_V2_BUILD_DLL)
#define CF7_AUDIO_BRIDGE_V2_API __declspec(dllexport)
#else
#define CF7_AUDIO_BRIDGE_V2_API __declspec(dllimport)
#endif
#define CF7_AUDIO_BRIDGE_V2_CALL __cdecl
#else
#define CF7_AUDIO_BRIDGE_V2_API
#define CF7_AUDIO_BRIDGE_V2_CALL
#endif

#define CF7_AUDIO_BRIDGE_V2_ABI_MAJOR ((uint32_t)2u)
#define CF7_AUDIO_BRIDGE_V2_ABI_MINOR ((uint32_t)0u)
#define CF7_AUDIO_BRIDGE_V2_WIRE_REVISION ((uint32_t)2u)
#define CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION ((uint32_t)1u)

#define CF7_AUDIO_BRIDGE_V2_UUID_V4_TEXT_CAPACITY ((uint32_t)37u)
#define CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY ((uint32_t)65u)

#define CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_WALL_MS ((uint32_t)2000u)
#define CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES ((uint64_t)96000u)
#define CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES ((uint64_t)8388608u)
#define CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_FILE_BYTES ((uint64_t)536870912u)
#define CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_OBSERVATIONS ((uint32_t)2u)
#define CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS ((uint32_t)1000u)
#define CF7_AUDIO_BRIDGE_V2_OFFLINE_PROBE_MAX_WALL_MS ((uint32_t)120000u)

#define CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX \
    uint32_t structSize;                    \
    uint32_t abiMajor;                      \
    uint32_t abiMinor

#define CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(value)                     \
    do {                                                           \
        (value).structSize = (uint32_t)sizeof(value);               \
        (value).abiMajor = CF7_AUDIO_BRIDGE_V2_ABI_MAJOR;           \
        (value).abiMinor = CF7_AUDIO_BRIDGE_V2_ABI_MINOR;           \
    } while (0)

#define CF7_AUDIO_BRIDGE_V2_MIN_SIZE(type, lastMember)             \
    ((uint32_t)(offsetof(type, lastMember) +                       \
    sizeof(((type*)0)->lastMember)))

typedef uint32_t cf7_audio_bridge_v2_bool32;
typedef uint32_t cf7_audio_bridge_v2_result_category;
typedef uint32_t cf7_audio_bridge_v2_operation;
typedef uint32_t cf7_audio_bridge_v2_stage;
typedef uint32_t cf7_audio_bridge_v2_audio_status;
typedef uint32_t cf7_audio_bridge_v2_backend;
typedef uint32_t cf7_audio_bridge_v2_sample_format;
typedef uint32_t cf7_audio_bridge_v2_completion_state;
typedef uint32_t cf7_audio_bridge_v2_probe_outcome;
typedef uint32_t cf7_audio_bridge_v2_eof_state;
typedef uint32_t cf7_audio_bridge_v2_meter_bus;
typedef uint32_t cf7_audio_bridge_v2_execution_identity;
typedef uint64_t cf7_audio_bridge_v2_caller_address;

#define CF7_AUDIO_BRIDGE_V2_FALSE ((cf7_audio_bridge_v2_bool32)0u)
#define CF7_AUDIO_BRIDGE_V2_TRUE ((cf7_audio_bridge_v2_bool32)1u)

/* Exact H1 result-category vocabulary. */
#define CF7_AUDIO_BRIDGE_V2_RESULT_OK ((cf7_audio_bridge_v2_result_category)0u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_MISSING ((cf7_audio_bridge_v2_result_category)1u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_UNSUPPORTED_CONTAINER ((cf7_audio_bridge_v2_result_category)2u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_UNSUPPORTED_CODEC ((cf7_audio_bridge_v2_result_category)3u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_MALFORMED ((cf7_audio_bridge_v2_result_category)4u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_TRUNCATED ((cf7_audio_bridge_v2_result_category)5u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR ((cf7_audio_bridge_v2_result_category)6u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH ((cf7_audio_bridge_v2_result_category)7u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY ((cf7_audio_bridge_v2_result_category)8u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_STALE_GENERATION ((cf7_audio_bridge_v2_result_category)9u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_UNKNOWN_ID ((cf7_audio_bridge_v2_result_category)10u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_THROTTLED ((cf7_audio_bridge_v2_result_category)11u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_START_FAILED ((cf7_audio_bridge_v2_result_category)12u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_SEEK_FAILED ((cf7_audio_bridge_v2_result_category)13u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_DEVICE_UNAVAILABLE ((cf7_audio_bridge_v2_result_category)14u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_DEVICE_LOST ((cf7_audio_bridge_v2_result_category)15u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_SUPERSEDED ((cf7_audio_bridge_v2_result_category)16u)
#define CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR ((cf7_audio_bridge_v2_result_category)17u)

/* H1 runtime state machine. */
#define CF7_AUDIO_BRIDGE_V2_AUDIO_INITIALIZING ((cf7_audio_bridge_v2_audio_status)1u)
#define CF7_AUDIO_BRIDGE_V2_AUDIO_READY ((cf7_audio_bridge_v2_audio_status)2u)
#define CF7_AUDIO_BRIDGE_V2_AUDIO_RECOVERING ((cf7_audio_bridge_v2_audio_status)3u)
#define CF7_AUDIO_BRIDGE_V2_AUDIO_FAILED_NO_OUTPUT ((cf7_audio_bridge_v2_audio_status)4u)
#define CF7_AUDIO_BRIDGE_V2_AUDIO_SHUTDOWN ((cf7_audio_bridge_v2_audio_status)5u)

#define CF7_AUDIO_BRIDGE_V2_BACKEND_NONE ((cf7_audio_bridge_v2_backend)0u)
#define CF7_AUDIO_BRIDGE_V2_BACKEND_WASAPI ((cf7_audio_bridge_v2_backend)1u)
#define CF7_AUDIO_BRIDGE_V2_BACKEND_DIRECTSOUND ((cf7_audio_bridge_v2_backend)2u)
#define CF7_AUDIO_BRIDGE_V2_BACKEND_WINMM ((cf7_audio_bridge_v2_backend)3u)
#define CF7_AUDIO_BRIDGE_V2_BACKEND_TEST_ONLY_NULL ((cf7_audio_bridge_v2_backend)4u)

#define CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_WASAPI ((uint32_t)0x00000001u)
#define CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_DIRECTSOUND ((uint32_t)0x00000002u)
#define CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_WINMM ((uint32_t)0x00000004u)
#define CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_TEST_ONLY_NULL ((uint32_t)0x80000000u)
#define CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_PRODUCTION                  \
    (CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_WASAPI |                     \
    CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_DIRECTSOUND |                 \
    CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_WINMM)

#define CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_BUILTIN ((uint64_t)0x0000000000000001u)
#define CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_LIBVORBIS ((uint64_t)0x0000000000000002u)
#define CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_MEDIA_FOUNDATION ((uint64_t)0x0000000000000004u)
#define CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_LIBOPUS ((uint64_t)0x0000000000000008u)

#define CF7_AUDIO_BRIDGE_V2_CONTAINER_RIFF_WAVE ((uint64_t)0x0000000000000001u)
#define CF7_AUDIO_BRIDGE_V2_CONTAINER_MPEG_AUDIO ((uint64_t)0x0000000000000002u)
#define CF7_AUDIO_BRIDGE_V2_CONTAINER_NATIVE_FLAC ((uint64_t)0x0000000000000004u)
#define CF7_AUDIO_BRIDGE_V2_CONTAINER_OGG ((uint64_t)0x0000000000000008u)
#define CF7_AUDIO_BRIDGE_V2_CONTAINER_MPEG4 ((uint64_t)0x0000000000000010u)
#define CF7_AUDIO_BRIDGE_V2_CONTAINER_ADTS ((uint64_t)0x0000000000000020u)

#define CF7_AUDIO_BRIDGE_V2_CODEC_PCM_OR_IEEE_FLOAT ((uint64_t)0x0000000000000001u)
#define CF7_AUDIO_BRIDGE_V2_CODEC_MPEG_AUDIO_LAYER_III ((uint64_t)0x0000000000000002u)
#define CF7_AUDIO_BRIDGE_V2_CODEC_FLAC ((uint64_t)0x0000000000000004u)
#define CF7_AUDIO_BRIDGE_V2_CODEC_VORBIS ((uint64_t)0x0000000000000008u)
#define CF7_AUDIO_BRIDGE_V2_CODEC_AAC_LC_OR_HE_AAC ((uint64_t)0x0000000000000010u)
#define CF7_AUDIO_BRIDGE_V2_CODEC_OPUS ((uint64_t)0x0000000000000020u)

#define CF7_AUDIO_BRIDGE_V2_EXTENSION_WAV ((uint64_t)0x0000000000000001u)
#define CF7_AUDIO_BRIDGE_V2_EXTENSION_MP3 ((uint64_t)0x0000000000000002u)
#define CF7_AUDIO_BRIDGE_V2_EXTENSION_FLAC ((uint64_t)0x0000000000000004u)
#define CF7_AUDIO_BRIDGE_V2_EXTENSION_OGG ((uint64_t)0x0000000000000008u)
#define CF7_AUDIO_BRIDGE_V2_EXTENSION_M4A ((uint64_t)0x0000000000000010u)
#define CF7_AUDIO_BRIDGE_V2_EXTENSION_MP4 ((uint64_t)0x0000000000000020u)
#define CF7_AUDIO_BRIDGE_V2_EXTENSION_AAC ((uint64_t)0x0000000000000040u)
#define CF7_AUDIO_BRIDGE_V2_EXTENSION_ADTS ((uint64_t)0x0000000000000080u)
#define CF7_AUDIO_BRIDGE_V2_EXTENSION_OPUS ((uint64_t)0x0000000000000100u)

#define CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_UNKNOWN ((cf7_audio_bridge_v2_sample_format)0u)
#define CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_F32 ((cf7_audio_bridge_v2_sample_format)1u)
#define CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_S16 ((cf7_audio_bridge_v2_sample_format)2u)
#define CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_S24 ((cf7_audio_bridge_v2_sample_format)3u)
#define CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_S32 ((cf7_audio_bridge_v2_sample_format)4u)

#define CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE ((cf7_audio_bridge_v2_completion_state)0u)
#define CF7_AUDIO_BRIDGE_V2_COMPLETION_ACCEPTED_DEFERRED ((cf7_audio_bridge_v2_completion_state)1u)
#define CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED ((cf7_audio_bridge_v2_completion_state)2u)
#define CF7_AUDIO_BRIDGE_V2_COMPLETION_STOPPED ((cf7_audio_bridge_v2_completion_state)3u)
#define CF7_AUDIO_BRIDGE_V2_COMPLETION_SUPERSEDED ((cf7_audio_bridge_v2_completion_state)4u)
#define CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED ((cf7_audio_bridge_v2_completion_state)5u)

#define CF7_AUDIO_BRIDGE_V2_OPERATION_NONE ((cf7_audio_bridge_v2_operation)0u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_CAPABILITY ((cf7_audio_bridge_v2_operation)1u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE ((cf7_audio_bridge_v2_operation)2u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME ((cf7_audio_bridge_v2_operation)3u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_METER ((cf7_audio_bridge_v2_operation)4u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY ((cf7_audio_bridge_v2_operation)10u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_STOP ((cf7_audio_bridge_v2_operation)11u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PAUSE ((cf7_audio_bridge_v2_operation)12u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_RESUME ((cf7_audio_bridge_v2_operation)13u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_SEEK ((cf7_audio_bridge_v2_operation)14u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_SET_LOOP ((cf7_audio_bridge_v2_operation)15u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_SET_GAIN ((cf7_audio_bridge_v2_operation)16u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG ((cf7_audio_bridge_v2_operation)20u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH ((cf7_audio_bridge_v2_operation)21u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_SET_GAIN ((cf7_audio_bridge_v2_operation)22u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_SET_MASTER_GAIN ((cf7_audio_bridge_v2_operation)23u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE ((cf7_audio_bridge_v2_operation)30u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE ((cf7_audio_bridge_v2_operation)31u)
#define CF7_AUDIO_BRIDGE_V2_OPERATION_SHUTDOWN ((cf7_audio_bridge_v2_operation)40u)

#define CF7_AUDIO_BRIDGE_V2_STAGE_NONE ((cf7_audio_bridge_v2_stage)0u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI ((cf7_audio_bridge_v2_stage)1u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_CAPACITY ((cf7_audio_bridge_v2_stage)2u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_SESSION ((cf7_audio_bridge_v2_stage)3u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_PATH ((cf7_audio_bridge_v2_stage)4u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION ((cf7_audio_bridge_v2_stage)5u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_CONTEXT_INITIALIZE ((cf7_audio_bridge_v2_stage)10u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_DEVICE_INITIALIZE ((cf7_audio_bridge_v2_stage)11u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_DEVICE_START ((cf7_audio_bridge_v2_stage)12u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_DECODER_INITIALIZE ((cf7_audio_bridge_v2_stage)20u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE ((cf7_audio_bridge_v2_stage)21u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START ((cf7_audio_bridge_v2_stage)22u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_SEEK ((cf7_audio_bridge_v2_stage)23u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT ((cf7_audio_bridge_v2_stage)30u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE ((cf7_audio_bridge_v2_stage)31u)
#define CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN ((cf7_audio_bridge_v2_stage)40u)

#define CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY ((uint32_t)0x00000001u)
#define CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY ((uint32_t)0x00000002u)

#define CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE ((cf7_audio_bridge_v2_probe_outcome)0u)
#define CF7_AUDIO_BRIDGE_V2_PROBE_COMPATIBLE_SIGNAL_PRESENT ((cf7_audio_bridge_v2_probe_outcome)1u)
#define CF7_AUDIO_BRIDGE_V2_PROBE_COMPATIBLE_SIGNAL_UNKNOWN ((cf7_audio_bridge_v2_probe_outcome)2u)
#define CF7_AUDIO_BRIDGE_V2_PROBE_INCOMPATIBLE ((cf7_audio_bridge_v2_probe_outcome)3u)
#define CF7_AUDIO_BRIDGE_V2_PROBE_INCONCLUSIVE_TIMEOUT_NOT_UNSUPPORTED ((cf7_audio_bridge_v2_probe_outcome)4u)
#define CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_PASSED ((cf7_audio_bridge_v2_probe_outcome)5u)
#define CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED_TIMEOUT ((cf7_audio_bridge_v2_probe_outcome)6u)
#define CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED ((cf7_audio_bridge_v2_probe_outcome)7u)

#define CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED ((cf7_audio_bridge_v2_eof_state)0u)
#define CF7_AUDIO_BRIDGE_V2_EOF_REACHED ((cf7_audio_bridge_v2_eof_state)1u)
#define CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED ((cf7_audio_bridge_v2_eof_state)2u)

#define CF7_AUDIO_BRIDGE_V2_METER_BGM_PRE_MASTER ((cf7_audio_bridge_v2_meter_bus)1u)
#define CF7_AUDIO_BRIDGE_V2_METER_SFX_PRE_MASTER ((cf7_audio_bridge_v2_meter_bus)2u)

#define CF7_AUDIO_BRIDGE_V2_EXECUTION_PRODUCTION \
    ((cf7_audio_bridge_v2_execution_identity)0x50524F44u)
#define CF7_AUDIO_BRIDGE_V2_EXECUTION_ISOLATED_TEST \
    ((cf7_audio_bridge_v2_execution_identity)0x54455354u)

#pragma pack(push, 8)

typedef struct cf7_audio_bridge_v2_struct_header {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
} cf7_audio_bridge_v2_struct_header;

typedef struct cf7_audio_bridge_v2_version {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    uint32_t major;
    uint32_t minor;
    uint32_t patch;
} cf7_audio_bridge_v2_version;

typedef struct cf7_audio_bridge_v2_utf8_buffer {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_caller_address dataAddress;
    uint32_t capacityBytes;
    uint32_t lengthBytes;
    uint32_t requiredBytes;
    uint32_t flags;
} cf7_audio_bridge_v2_utf8_buffer;

typedef struct cf7_audio_bridge_v2_utf16_buffer {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_caller_address dataAddress;
    uint32_t capacityCodeUnits;
    uint32_t lengthCodeUnits;
    uint32_t requiredCodeUnits;
    uint32_t flags;
} cf7_audio_bridge_v2_utf16_buffer;

typedef struct cf7_audio_bridge_v2_array_buffer {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_caller_address dataAddress;
    uint32_t elementSize;
    uint32_t capacityElements;
    uint32_t countElements;
    uint32_t requiredElements;
} cf7_audio_bridge_v2_array_buffer;

typedef struct cf7_audio_bridge_v2_result {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_result_category category;
    cf7_audio_bridge_v2_operation operation;
    cf7_audio_bridge_v2_stage stage;
    int32_t rawMaResult;
    int32_t rawHresult;
    cf7_audio_bridge_v2_completion_state completionState;
    uint32_t reserved0;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    uint64_t deviceGeneration;
    cf7_audio_bridge_v2_utf8_buffer messageKey;
} cf7_audio_bridge_v2_result;

/* Build capability. Build codec support never implies runtime device readiness. */
typedef struct cf7_audio_bridge_v2_capability {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_version abiVersion;
    cf7_audio_bridge_v2_utf8_buffer bridgeBuildId;
    cf7_audio_bridge_v2_version miniaudioVersion;
    uint64_t decoderBackends;
    uint64_t containers;
    uint64_t codecs;
    uint64_t extensions;
    uint32_t compiledBackendMask;
    cf7_audio_bridge_v2_bool32 supportsRuntimeCompatibilityProbe;
    cf7_audio_bridge_v2_bool32 supportsOfflineQualificationProbe;
    cf7_audio_bridge_v2_bool32 supportsSeek;
    cf7_audio_bridge_v2_bool32 supportsLoop;
    cf7_audio_bridge_v2_bool32 supportsDeviceRecovery;
    cf7_audio_bridge_v2_bool32 supportsBgmMeter;
    cf7_audio_bridge_v2_bool32 supportsSfxMeter;
    cf7_audio_bridge_v2_bool32 testOnlyNullEnabled;
    cf7_audio_bridge_v2_utf8_buffer capabilityDigestSha256;
} cf7_audio_bridge_v2_capability;

typedef struct cf7_audio_bridge_v2_runtime_snapshot {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_audio_status audioStatus;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    uint64_t deviceGeneration;
    cf7_audio_bridge_v2_backend selectedBackend;
    cf7_audio_bridge_v2_utf8_buffer selectedDeviceIdDigest;
    cf7_audio_bridge_v2_utf16_buffer selectedDeviceName;
    uint32_t sampleRate;
    uint32_t channels;
    cf7_audio_bridge_v2_sample_format sampleFormat;
    cf7_audio_bridge_v2_result lastStructuredFailure;
} cf7_audio_bridge_v2_runtime_snapshot;

typedef struct cf7_audio_bridge_v2_meter_snapshot {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_meter_bus bus;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    uint64_t deviceGeneration;
    float peakLeft;
    float peakRight;
    float rmsLeft;
    float rmsRight;
    uint64_t clipCount;
    uint64_t frameCount;
    uint64_t underrunCount;
} cf7_audio_bridge_v2_meter_snapshot;

typedef struct cf7_audio_bridge_v2_source_snapshot {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    uint64_t deviceGeneration;
    uint64_t decoder;
    uint64_t container;
    uint64_t codec;
    uint64_t cursorFrames;
    uint64_t lengthFrames;
    cf7_audio_bridge_v2_bool32 playing;
    float sourceGroupMasterGain;
    cf7_audio_bridge_v2_result startResult;
} cf7_audio_bridge_v2_source_snapshot;

typedef struct cf7_audio_bridge_v2_sfx_counters {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    uint64_t preReadyDrops;
    uint64_t recoveryDrops;
    uint64_t staleGenerationDrops;
    uint64_t unknownIdCount;
    uint64_t throttledCount;
    uint64_t startFailureCount;
    uint64_t playedCount;
} cf7_audio_bridge_v2_sfx_counters;

typedef struct cf7_audio_bridge_v2_initialize_command {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf16_buffer normalizedBasePath;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    cf7_audio_bridge_v2_execution_identity executionIdentity;
    uint32_t reserved0;
} cf7_audio_bridge_v2_initialize_command;

/* BGM request fields preserve the exact H1 order after the ABI prefix. */
typedef struct cf7_audio_bridge_v2_bgm_command {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    uint32_t wireRevision;
    cf7_audio_bridge_v2_utf8_buffer requestId;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    cf7_audio_bridge_v2_operation operation;
    cf7_audio_bridge_v2_utf16_buffer normalizedPath;
    cf7_audio_bridge_v2_bool32 loop;
    float volume;
    float fadeSeconds;
    float seekSeconds;
} cf7_audio_bridge_v2_bgm_command;

typedef struct cf7_audio_bridge_v2_sfx_catalog_item {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf8_buffer linkageId;
    cf7_audio_bridge_v2_utf16_buffer normalizedPath;
} cf7_audio_bridge_v2_sfx_catalog_item;

typedef struct cf7_audio_bridge_v2_sfx_catalog_command {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    cf7_audio_bridge_v2_array_buffer items;
} cf7_audio_bridge_v2_sfx_catalog_command;

typedef struct cf7_audio_bridge_v2_sfx_play_item {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf8_buffer linkageId;
    float volume;
    uint32_t reserved0;
} cf7_audio_bridge_v2_sfx_play_item;

/* SFX batch fields preserve the exact H1 order after the ABI prefix. */
typedef struct cf7_audio_bridge_v2_sfx_batch_command {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    uint32_t wireRevision;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    uint64_t batchSequence;
    cf7_audio_bridge_v2_array_buffer linkageIds;
} cf7_audio_bridge_v2_sfx_batch_command;

typedef struct cf7_audio_bridge_v2_gain_command {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
    cf7_audio_bridge_v2_operation operation;
    float gain;
} cf7_audio_bridge_v2_gain_command;

typedef struct cf7_audio_bridge_v2_runtime_probe_command {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf16_buffer normalizedPath;
    uint64_t fileSizeBytes;
    int64_t modifiedTimeUnixMilliseconds;
    cf7_audio_bridge_v2_utf8_buffer first64kSha256;
    cf7_audio_bridge_v2_utf8_buffer capabilityDigestSha256;
    uint32_t probeContractRevision;
    uint32_t maxWallMs;
    uint64_t maxDecodedFrames;
    uint64_t maxInputBytes;
    uint64_t maxFileBytes;
    uint32_t stableObservationCount;
    uint32_t stableIntervalMs;
} cf7_audio_bridge_v2_runtime_probe_command;

typedef struct cf7_audio_bridge_v2_offline_probe_command {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf16_buffer normalizedPath;
    cf7_audio_bridge_v2_utf8_buffer fullSha256;
    cf7_audio_bridge_v2_utf8_buffer capabilityDigestSha256;
    uint32_t probeContractRevision;
    uint32_t maxWallMs;
} cf7_audio_bridge_v2_offline_probe_command;

typedef struct cf7_audio_bridge_v2_probe_result {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_result structuredResult;
    cf7_audio_bridge_v2_probe_outcome outcome;
    cf7_audio_bridge_v2_eof_state eofState;
    uint64_t frames;
    double durationSeconds;
    double peak;
    double rms;
    uint64_t leadingSilenceFrames;
    uint64_t trailingSilenceFrames;
    uint64_t nonFiniteCount;
    uint32_t elapsedMs;
    uint32_t reserved0;
    uint64_t inputBytesRead;
} cf7_audio_bridge_v2_probe_result;

typedef struct cf7_audio_bridge_v2_shutdown_command {
    CF7_AUDIO_BRIDGE_V2_STRUCT_PREFIX;
    cf7_audio_bridge_v2_utf8_buffer audioSessionId;
    uint64_t audioReadyGeneration;
} cf7_audio_bridge_v2_shutdown_command;

#pragma pack(pop)

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_query_capability(
    cf7_audio_bridge_v2_capability* capability,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_initialize(
    const cf7_audio_bridge_v2_initialize_command* command,
    cf7_audio_bridge_v2_runtime_snapshot* runtimeSnapshot,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_query_runtime(
    cf7_audio_bridge_v2_runtime_snapshot* runtimeSnapshot,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_query_meter(
    cf7_audio_bridge_v2_meter_snapshot* meterSnapshot,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_query_bgm_source(
    cf7_audio_bridge_v2_source_snapshot* sourceSnapshot,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_query_sfx_counters(
    cf7_audio_bridge_v2_sfx_counters* counters,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_submit_bgm(
    const cf7_audio_bridge_v2_bgm_command* command,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_rebuild_sfx_catalog(
    const cf7_audio_bridge_v2_sfx_catalog_command* command,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_submit_sfx_batch(
    const cf7_audio_bridge_v2_sfx_batch_command* command,
    cf7_audio_bridge_v2_sfx_counters* counters,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_set_gain(
    const cf7_audio_bridge_v2_gain_command* command,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_probe_runtime_compatibility(
    const cf7_audio_bridge_v2_runtime_probe_command* command,
    cf7_audio_bridge_v2_probe_result* probeResult,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_probe_offline_qualification(
    const cf7_audio_bridge_v2_offline_probe_command* command,
    cf7_audio_bridge_v2_probe_result* probeResult,
    cf7_audio_bridge_v2_result* result);

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category CF7_AUDIO_BRIDGE_V2_CALL
cf7_audio_bridge_v2_shutdown(
    const cf7_audio_bridge_v2_shutdown_command* command,
    cf7_audio_bridge_v2_result* result);

#ifdef __cplusplus
}
#endif

#endif
