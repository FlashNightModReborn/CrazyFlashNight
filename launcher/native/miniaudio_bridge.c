/*
 * CF7 Audio Platform v2 native bridge.
 *
 * The public ABI is deliberately independent from miniaudio.  This file is
 * the sole owner of mutable miniaudio objects: every context, engine, sound,
 * resource-manager and decoder mutation is executed by one native owner
 * thread.  Query exports read immutable/runtime snapshots or enqueue a
 * synchronous owner query when miniaudio itself must be inspected.
 */

#ifndef NOMINMAX
#define NOMINMAX
#endif

#define CF7_AUDIO_BRIDGE_V2_BUILD_DLL
#include "audio_bridge_v2.h"
#include "audio_backend_policy.h"
#include "audio_bridge_support.h"
#include "audio_decoder_registry.h"
#include "audio_mf_decoder.h"
#include "miniaudio.h"

#include <bcrypt.h>
#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <windows.h>

#define CF7_SFX_VOICES 4u
#define CF7_SFX_CATALOG_MAX_ITEMS 4096u
#define CF7_SFX_THROTTLE_MS 30u
#define CF7_BGM_MIN_FADE_MS 100u
#define CF7_PROBE_FRAMES_PER_READ 4096u
#define CF7_PROBE_INPUT_READ_CHUNK_BYTES 65536u
#define CF7_SILENCE_THRESHOLD 0.00001
#define CF7_GAIN_MAX 1.0f

#define CF7_DECODER_MASK                                                   \
    (CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_BUILTIN |                       \
     CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_LIBVORBIS |                     \
     CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_MEDIA_FOUNDATION |              \
     CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_LIBOPUS)
#define CF7_CONTAINER_MASK                                                 \
    (CF7_AUDIO_BRIDGE_V2_CONTAINER_RIFF_WAVE |                            \
     CF7_AUDIO_BRIDGE_V2_CONTAINER_MPEG_AUDIO |                           \
     CF7_AUDIO_BRIDGE_V2_CONTAINER_NATIVE_FLAC |                          \
     CF7_AUDIO_BRIDGE_V2_CONTAINER_OGG |                                  \
     CF7_AUDIO_BRIDGE_V2_CONTAINER_MPEG4 |                                \
     CF7_AUDIO_BRIDGE_V2_CONTAINER_ADTS)
#define CF7_CODEC_MASK                                                     \
    (CF7_AUDIO_BRIDGE_V2_CODEC_PCM_OR_IEEE_FLOAT |                        \
     CF7_AUDIO_BRIDGE_V2_CODEC_MPEG_AUDIO_LAYER_III |                     \
     CF7_AUDIO_BRIDGE_V2_CODEC_FLAC |                                     \
     CF7_AUDIO_BRIDGE_V2_CODEC_VORBIS |                                   \
     CF7_AUDIO_BRIDGE_V2_CODEC_AAC_LC_OR_HE_AAC |                         \
     CF7_AUDIO_BRIDGE_V2_CODEC_OPUS)
#define CF7_EXTENSION_MASK                                                 \
    (CF7_AUDIO_BRIDGE_V2_EXTENSION_WAV |                                  \
     CF7_AUDIO_BRIDGE_V2_EXTENSION_MP3 |                                  \
     CF7_AUDIO_BRIDGE_V2_EXTENSION_FLAC |                                 \
     CF7_AUDIO_BRIDGE_V2_EXTENSION_OGG |                                  \
     CF7_AUDIO_BRIDGE_V2_EXTENSION_M4A |                                  \
     CF7_AUDIO_BRIDGE_V2_EXTENSION_MP4 |                                  \
     CF7_AUDIO_BRIDGE_V2_EXTENSION_AAC |                                  \
     CF7_AUDIO_BRIDGE_V2_EXTENSION_ADTS |                                 \
     CF7_AUDIO_BRIDGE_V2_EXTENSION_OPUS)

typedef struct cf7_internal_result {
    uint32_t category;
    uint32_t operation;
    uint32_t stage;
    int32_t rawMaResult;
    int32_t rawHresult;
    uint32_t completionState;
    char messageKey[96];
} cf7_internal_result;

typedef struct cf7_meter_values {
    float peakLeft;
    float peakRight;
    float rmsLeft;
    float rmsRight;
    uint64_t clipCount;
    uint64_t frameCount;
    uint64_t underrunCount;
} cf7_meter_values;

typedef struct cf7_meter_node {
    ma_node_base base;
    uint32_t channels;
    volatile LONG sequence;
    volatile LONG peakLeftBits;
    volatile LONG peakRightBits;
    volatile LONG rmsLeftBits;
    volatile LONG rmsRightBits;
    volatile LONG64 clipCount;
    volatile LONG64 frameCount;
    volatile LONG64 underrunCount;
    int initialized;
} cf7_meter_node;

typedef struct cf7_sfx_entry {
    char* linkageId;
    wchar_t* finalPath;
    ma_sound voices[CF7_SFX_VOICES];
    uint8_t voiceInitialized[CF7_SFX_VOICES];
    uint32_t nextVoice;
    ULONGLONG lastPlayMilliseconds;
} cf7_sfx_entry;

typedef struct cf7_audio_runtime {
    wchar_t* finalBasePath;
    char audioSessionId[CF7_AUDIO_BRIDGE_V2_UUID_V4_TEXT_CAPACITY];
    uint64_t audioReadyGeneration;
    uint64_t deviceGeneration;
    uint32_t audioStatus;
    uint32_t selectedBackend;
    char selectedDeviceIdDigest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    wchar_t* selectedDeviceName;
    uint32_t sampleRate;
    uint32_t channels;
    uint32_t sampleFormat;
    cf7_internal_result lastFailure;

    cf7_audio_decoder_registry decoderRegistry;
    int decoderRegistryInitialized;
    cf7_audio_mf_decode_control mfDecodeControl;
    ma_context context;
    int contextInitialized;
    ma_resource_manager resourceManager;
    int resourceManagerInitialized;
    ma_engine engine;
    int engineInitialized;
    ma_sound_group bgmGroup;
    int bgmGroupInitialized;
    ma_sound_group sfxGroup;
    int sfxGroupInitialized;
    cf7_meter_node bgmMeter;
    cf7_meter_node sfxMeter;

    ma_sound bgm[2];
    uint8_t bgmInitialized[2];
    uint32_t bgmActive;
    wchar_t* latestBgmPath;
    int latestBgmPresent;
    int latestBgmPaused;
    int latestBgmLoop;
    float latestBgmVolume;
    uint64_t latestBgmCursorFrames;
    uint64_t bgmDecoder;
    uint64_t bgmContainer;
    uint64_t bgmCodec;
    cf7_internal_result bgmStartResult;

    cf7_sfx_entry* sfxCatalog;
    uint32_t sfxCatalogCount;
    volatile LONG64 sfxPreReadyDrops;
    volatile LONG64 sfxRecoveryDrops;
    volatile LONG64 sfxStaleGenerationDrops;
    volatile LONG64 sfxUnknownIdCount;
    volatile LONG64 sfxThrottledCount;
    volatile LONG64 sfxStartFailureCount;
    volatile LONG64 sfxPlayedCount;
    float bgmGain;
    float sfxGain;
    float masterGain;
} cf7_audio_runtime;

typedef enum cf7_owner_job_kind {
    CF7_JOB_INITIALIZE = 1,
    CF7_JOB_BGM = 2,
    CF7_JOB_REBUILD_SFX = 3,
    CF7_JOB_SFX_BATCH = 4,
    CF7_JOB_SET_GAIN = 5,
    CF7_JOB_QUERY_BGM = 6,
    CF7_JOB_PROBE_RUNTIME = 7,
    CF7_JOB_PROBE_OFFLINE = 8,
    CF7_JOB_SHUTDOWN = 9
} cf7_owner_job_kind;

typedef struct cf7_owner_job {
    cf7_owner_job_kind kind;
    const void* command;
    void* output;
    cf7_audio_bridge_v2_result* result;
    uint64_t capturedDeviceGeneration;
    HANDLE completedEvent;
    struct cf7_owner_job* next;
} cf7_owner_job;

typedef struct cf7_owner_control {
    CRITICAL_SECTION queueLock;
    SRWLOCK snapshotLock;
    HANDLE queueEvent;
    HANDLE cancelEvent;
    HANDLE ownerThread;
    DWORD ownerThreadId;
    cf7_owner_job* queueHead;
    cf7_owner_job* queueTail;
    int admissionOpen;
    int ownerExitRequested;
    volatile LONG recoveryRequested;
    volatile LONG notificationArmed;
    volatile LONG counterOverflow;
} cf7_owner_control;

typedef struct cf7_backend_attempt {
    cf7_audio_runtime* runtime;
} cf7_backend_attempt;

typedef struct cf7_probe_vfs {
    ma_vfs_callbacks callbacks;
    ma_default_vfs base;
    uint64_t maximumBytes;
    uint64_t bytesRead;
    ma_vfs_file activeFile;
    uint64_t virtualLength;
    ULONGLONG deadline;
    volatile LONG* cancelled;
    int virtualLengthActive;
    int prefixTruncated;
    int limitHit;
    int timeoutHit;
    int cancelledHit;
} cf7_probe_vfs;

typedef enum cf7_ogg_physical_state {
    CF7_OGG_PHYSICAL_NOT_OGG = 0,
    CF7_OGG_PHYSICAL_COMPLETE = 1,
    CF7_OGG_PHYSICAL_TRUNCATED = 2,
    CF7_OGG_PHYSICAL_MALFORMED = 3
} cf7_ogg_physical_state;

typedef enum cf7_ogg_scan_phase {
    CF7_OGG_SCAN_HEADER = 0,
    CF7_OGG_SCAN_LACING = 1,
    CF7_OGG_SCAN_BODY = 2
} cf7_ogg_scan_phase;

typedef struct cf7_ogg_scan {
    unsigned char header[27];
    size_t headerBytes;
    uint32_t lacingBytes;
    uint32_t bodyBytesRemaining;
    uint64_t completePages;
    cf7_ogg_scan_phase phase;
    int notOgg;
    int malformed;
} cf7_ogg_scan;

static INIT_ONCE g_controlOnce = INIT_ONCE_STATIC_INIT;
static cf7_owner_control g_control;
static cf7_audio_runtime g_runtime;

static LONG cf7_float_to_bits(float value)
{
    LONG bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static float cf7_bits_to_float(LONG bits)
{
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static void cf7_internal_result_set(
    cf7_internal_result* value,
    uint32_t category,
    uint32_t operation,
    uint32_t stage,
    int32_t rawMaResult,
    int32_t rawHresult,
    uint32_t completionState,
    const char* messageKey)
{
    if (value == NULL) {
        return;
    }
    memset(value, 0, sizeof(*value));
    value->category = category;
    value->operation = operation;
    value->stage = stage;
    value->rawMaResult = rawMaResult;
    value->rawHresult = rawHresult;
    value->completionState = completionState;
    if (messageKey != NULL) {
        (void)strncpy_s(
            value->messageKey,
            sizeof(value->messageKey),
            messageKey,
            _TRUNCATE);
    }
}

static BOOL CALLBACK cf7_control_initialize_once(
    PINIT_ONCE initOnce,
    PVOID parameter,
    PVOID* context)
{
    (void)initOnce;
    (void)parameter;
    (void)context;
    memset(&g_control, 0, sizeof(g_control));
    memset(&g_runtime, 0, sizeof(g_runtime));
    InitializeCriticalSection(&g_control.queueLock);
    InitializeSRWLock(&g_control.snapshotLock);
    g_control.queueEvent = CreateEventW(NULL, FALSE, FALSE, NULL);
    g_control.cancelEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    g_runtime.audioStatus = CF7_AUDIO_BRIDGE_V2_AUDIO_SHUTDOWN;
    g_runtime.bgmGain = 1.0f;
    g_runtime.sfxGain = 1.0f;
    g_runtime.masterGain = 1.0f;
    cf7_internal_result_set(
        &g_runtime.lastFailure,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
        CF7_AUDIO_BRIDGE_V2_STAGE_NONE,
        0,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE,
        "audio.ok");
    cf7_internal_result_set(
        &g_runtime.bgmStartResult,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
        CF7_AUDIO_BRIDGE_V2_STAGE_NONE,
        0,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE,
        "audio.bgm.none");
    return g_control.queueEvent != NULL && g_control.cancelEvent != NULL;
}

static int cf7_control_ensure(void)
{
    return InitOnceExecuteOnce(
        &g_controlOnce,
        cf7_control_initialize_once,
        NULL,
        NULL) != FALSE;
}

static int cf7_uuid_v4_lowercase_valid(const char* value)
{
    size_t index;
    if (value == NULL || strlen(value) != 36u || value[14] != '4' ||
        (value[19] != '8' && value[19] != '9' &&
         value[19] != 'a' && value[19] != 'b')) {
        return 0;
    }
    for (index = 0u; index < 36u; ++index) {
        char c = value[index];
        if (index == 8u || index == 13u || index == 18u || index == 23u) {
            if (c != '-') {
                return 0;
            }
        } else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
            return 0;
        }
    }
    return 1;
}

static int cf7_sha256_hex_valid(const char* value)
{
    size_t index;
    if (value == NULL || strlen(value) != 64u) {
        return 0;
    }
    for (index = 0u; index < 64u; ++index) {
        char c = value[index];
        if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) {
            return 0;
        }
    }
    return 1;
}

static int cf7_finite_gain(float value)
{
    return isfinite(value) && value >= 0.0f && value <= CF7_GAIN_MAX;
}

static uint32_t cf7_result_write(
    cf7_audio_bridge_v2_result* result,
    uint32_t category,
    uint32_t operation,
    uint32_t stage,
    int32_t rawMaResult,
    int32_t rawHresult,
    uint32_t completionState,
    const char* audioSessionId,
    uint64_t audioReadyGeneration,
    uint64_t deviceGeneration,
    const char* messageKey)
{
    int stringsOk;
    if (!cf7_audio_bridge_support_prefix_valid(
            result,
            (uint32_t)sizeof(*result))) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    result->category = category;
    result->operation = operation;
    result->stage = stage;
    result->rawMaResult = rawMaResult;
    result->rawHresult = rawHresult;
    result->completionState = completionState;
    result->reserved0 = 0u;
    result->audioReadyGeneration = audioReadyGeneration;
    result->deviceGeneration = deviceGeneration;
    stringsOk = cf7_audio_bridge_support_write_utf8(
                    &result->audioSessionId,
                    audioSessionId != NULL ? audioSessionId : "") &&
        cf7_audio_bridge_support_write_utf8(
            &result->messageKey,
            messageKey != NULL ? messageKey : "audio.unspecified");
    if (!stringsOk) {
        result->category = CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
        result->stage = CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_CAPACITY;
        result->completionState = CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED;
    }
    return result->category;
}

static uint32_t cf7_result_from_internal(
    cf7_audio_bridge_v2_result* result,
    const cf7_internal_result* value,
    const char* session,
    uint64_t readyGeneration,
    uint64_t deviceGeneration)
{
    return cf7_result_write(
        result,
        value->category,
        value->operation,
        value->stage,
        value->rawMaResult,
        value->rawHresult,
        value->completionState,
        session,
        readyGeneration,
        deviceGeneration,
        value->messageKey);
}

static uint32_t cf7_result_current(
    cf7_audio_bridge_v2_result* result,
    uint32_t category,
    uint32_t operation,
    uint32_t stage,
    int32_t rawMaResult,
    int32_t rawHresult,
    uint32_t completionState,
    const char* messageKey)
{
    char session[CF7_AUDIO_BRIDGE_V2_UUID_V4_TEXT_CAPACITY];
    uint64_t ready;
    uint64_t device;
    session[0] = '\0';
    AcquireSRWLockShared(&g_control.snapshotLock);
    (void)strncpy_s(session, sizeof(session), g_runtime.audioSessionId, _TRUNCATE);
    ready = g_runtime.audioReadyGeneration;
    device = g_runtime.deviceGeneration;
    ReleaseSRWLockShared(&g_control.snapshotLock);
    return cf7_result_write(
        result,
        category,
        operation,
        stage,
        rawMaResult,
        rawHresult,
        completionState,
        session,
        ready,
        device,
        messageKey);
}

static void cf7_runtime_set_failure(const cf7_internal_result* failure)
{
    AcquireSRWLockExclusive(&g_control.snapshotLock);
    g_runtime.lastFailure = *failure;
    ReleaseSRWLockExclusive(&g_control.snapshotLock);
}

static void cf7_runtime_set_status(uint32_t status)
{
    AcquireSRWLockExclusive(&g_control.snapshotLock);
    g_runtime.audioStatus = status;
    ReleaseSRWLockExclusive(&g_control.snapshotLock);
}

static uint64_t cf7_counter_load(volatile LONG64* value)
{
    return (uint64_t)InterlockedCompareExchange64(value, 0, 0);
}

static int cf7_counter_add(volatile LONG64* value, uint64_t amount)
{
    LONG64 observed;
    LONG64 desired;
    uint64_t current;
    do {
        observed = InterlockedCompareExchange64(value, 0, 0);
        current = (uint64_t)observed;
        if (UINT64_MAX - current < amount) {
            InterlockedExchange(&g_control.counterOverflow, 1);
            SetEvent(g_control.queueEvent);
            return 0;
        }
        desired = (LONG64)(current + amount);
    } while (InterlockedCompareExchange64(value, desired, observed) != observed);
    return 1;
}

static void cf7_meter_reset(cf7_meter_node* meter)
{
    meter->sequence = 0;
    meter->peakLeftBits = cf7_float_to_bits(0.0f);
    meter->peakRightBits = cf7_float_to_bits(0.0f);
    meter->rmsLeftBits = cf7_float_to_bits(0.0f);
    meter->rmsRightBits = cf7_float_to_bits(0.0f);
    meter->clipCount = 0;
    meter->frameCount = 0;
    meter->underrunCount = 0;
}

static void cf7_meter_process(
    ma_node* node,
    const float** framesIn,
    ma_uint32* frameCountIn,
    float** framesOut,
    ma_uint32* frameCountOut)
{
    cf7_meter_node* meter = (cf7_meter_node*)node;
    const float* input = framesIn[0];
    float* output = framesOut[0];
    ma_uint32 frameCount = *frameCountOut;
    uint32_t channels = meter->channels;
    double sumLeft = 0.0;
    double sumRight = 0.0;
    float peakLeft = 0.0f;
    float peakRight = 0.0f;
    uint64_t clips = 0u;
    ma_uint32 frame;
    ma_uint32 channel;

    for (frame = 0u; frame < frameCount; ++frame) {
        float left = input[(size_t)frame * channels];
        float right = channels > 1u
            ? input[(size_t)frame * channels + 1u]
            : left;
        float absoluteLeft = isfinite(left) ? fabsf(left) : FLT_MAX;
        float absoluteRight = isfinite(right) ? fabsf(right) : FLT_MAX;
        if (absoluteLeft > peakLeft) {
            peakLeft = absoluteLeft;
        }
        if (absoluteRight > peakRight) {
            peakRight = absoluteRight;
        }
        if (absoluteLeft >= 1.0f) {
            ++clips;
        }
        if (absoluteRight >= 1.0f && channels > 1u) {
            ++clips;
        }
        if (isfinite(left)) {
            sumLeft += (double)left * (double)left;
        }
        if (isfinite(right)) {
            sumRight += (double)right * (double)right;
        }
        for (channel = 0u; channel < channels; ++channel) {
            output[(size_t)frame * channels + channel] =
                input[(size_t)frame * channels + channel];
        }
    }

    InterlockedIncrement(&meter->sequence);
    InterlockedExchange(&meter->peakLeftBits, cf7_float_to_bits(peakLeft));
    InterlockedExchange(&meter->peakRightBits, cf7_float_to_bits(peakRight));
    InterlockedExchange(
        &meter->rmsLeftBits,
        cf7_float_to_bits(frameCount > 0u
            ? (float)sqrt(sumLeft / (double)frameCount)
            : 0.0f));
    InterlockedExchange(
        &meter->rmsRightBits,
        cf7_float_to_bits(frameCount > 0u
            ? (float)sqrt(sumRight / (double)frameCount)
            : 0.0f));
    (void)InterlockedExchangeAdd64(&meter->clipCount, (LONG64)clips);
    (void)InterlockedExchangeAdd64(&meter->frameCount, (LONG64)frameCount);
    InterlockedIncrement(&meter->sequence);
    *frameCountIn = frameCount;
}

static ma_node_vtable g_meterVtable = {
    cf7_meter_process,
    NULL,
    1,
    1,
    0
};

static void cf7_meter_read(const cf7_meter_node* meter, cf7_meter_values* value)
{
    LONG before = 0;
    LONG after = 0;
    do {
        before = InterlockedCompareExchange((volatile LONG*)&meter->sequence, 0, 0);
        if ((before & 1) != 0) {
            SwitchToThread();
            continue;
        }
        value->peakLeft = cf7_bits_to_float(InterlockedCompareExchange(
            (volatile LONG*)&meter->peakLeftBits, 0, 0));
        value->peakRight = cf7_bits_to_float(InterlockedCompareExchange(
            (volatile LONG*)&meter->peakRightBits, 0, 0));
        value->rmsLeft = cf7_bits_to_float(InterlockedCompareExchange(
            (volatile LONG*)&meter->rmsLeftBits, 0, 0));
        value->rmsRight = cf7_bits_to_float(InterlockedCompareExchange(
            (volatile LONG*)&meter->rmsRightBits, 0, 0));
        value->clipCount = cf7_counter_load(
            (volatile LONG64*)&meter->clipCount);
        value->frameCount = cf7_counter_load(
            (volatile LONG64*)&meter->frameCount);
        value->underrunCount = cf7_counter_load(
            (volatile LONG64*)&meter->underrunCount);
        after = InterlockedCompareExchange((volatile LONG*)&meter->sequence, 0, 0);
    } while (before != after || (after & 1) != 0);
}

static uint32_t cf7_sample_format_from_ma(ma_format format)
{
    switch (format) {
    case ma_format_f32:
        return CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_F32;
    case ma_format_s16:
        return CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_S16;
    case ma_format_s24:
        return CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_S24;
    case ma_format_s32:
        return CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_S32;
    default:
        return CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_UNKNOWN;
    }
}

static ma_backend cf7_backend_to_ma(uint32_t backend)
{
    switch (backend) {
    case CF7_AUDIO_BACKEND_POLICY_WASAPI:
        return ma_backend_wasapi;
    case CF7_AUDIO_BACKEND_POLICY_DIRECTSOUND:
        return ma_backend_dsound;
    case CF7_AUDIO_BACKEND_POLICY_WINMM:
        return ma_backend_winmm;
    default:
        return ma_backend_null;
    }
}

static ma_bool32 cf7_mf_cancel_requested(void* userData)
{
    (void)userData;
    return g_control.cancelEvent != NULL &&
        WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0
        ? MA_TRUE
        : MA_FALSE;
}

static uint32_t cf7_category_from_ma(ma_result result, int pathKnown)
{
    switch (result) {
    case MA_SUCCESS:
        return CF7_AUDIO_BRIDGE_V2_RESULT_OK;
    case MA_DOES_NOT_EXIST:
        return CF7_AUDIO_BRIDGE_V2_RESULT_MISSING;
    case MA_AT_END:
        return CF7_AUDIO_BRIDGE_V2_RESULT_TRUNCATED;
    case MA_IO_ERROR:
        return CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR;
    case MA_INVALID_FILE:
        return pathKnown
            ? CF7_AUDIO_BRIDGE_V2_RESULT_MALFORMED
            : CF7_AUDIO_BRIDGE_V2_RESULT_UNSUPPORTED_CONTAINER;
    case MA_FORMAT_NOT_SUPPORTED:
    case MA_NOT_IMPLEMENTED:
        return CF7_AUDIO_BRIDGE_V2_RESULT_UNSUPPORTED_CODEC;
    default:
        return CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR;
    }
}

static void cf7_device_notification(const ma_device_notification* notification)
{
    if (notification == NULL ||
        InterlockedCompareExchange(&g_control.notificationArmed, 0, 0) == 0) {
        return;
    }
    if (notification->type == ma_device_notification_type_stopped ||
        notification->type == ma_device_notification_type_rerouted ||
        notification->type == ma_device_notification_type_interruption_began) {
        (void)InterlockedIncrement64(&g_runtime.bgmMeter.underrunCount);
        (void)InterlockedIncrement64(&g_runtime.sfxMeter.underrunCount);
        InterlockedExchange(&g_control.recoveryRequested, 1);
        SetEvent(g_control.queueEvent);
    }
}

static void cf7_bgm_uninit_sounds(void)
{
    uint32_t index;
    for (index = 0u; index < 2u; ++index) {
        if (g_runtime.bgmInitialized[index]) {
            (void)ma_sound_stop(&g_runtime.bgm[index]);
            ma_sound_uninit(&g_runtime.bgm[index]);
            g_runtime.bgmInitialized[index] = 0u;
        }
    }
    g_runtime.bgmActive = 0u;
}

static void cf7_sfx_entry_uninit_voices(cf7_sfx_entry* entry)
{
    uint32_t voice;
    if (entry == NULL) {
        return;
    }
    for (voice = 0u; voice < CF7_SFX_VOICES; ++voice) {
        if (entry->voiceInitialized[voice]) {
            (void)ma_sound_stop(&entry->voices[voice]);
            ma_sound_uninit(&entry->voices[voice]);
            entry->voiceInitialized[voice] = 0u;
        }
    }
    entry->nextVoice = 0u;
    entry->lastPlayMilliseconds = 0u;
}

static void cf7_sfx_catalog_uninit_voices(void)
{
    uint32_t index;
    for (index = 0u; index < g_runtime.sfxCatalogCount; ++index) {
        cf7_sfx_entry_uninit_voices(&g_runtime.sfxCatalog[index]);
    }
}

static void cf7_sfx_catalog_free_entries(
    cf7_sfx_entry* entries,
    uint32_t count,
    int uninitVoices)
{
    uint32_t index;
    if (entries == NULL) {
        return;
    }
    for (index = 0u; index < count; ++index) {
        if (uninitVoices) {
            cf7_sfx_entry_uninit_voices(&entries[index]);
        }
        cf7_audio_bridge_support_free(entries[index].linkageId);
        cf7_audio_bridge_support_free(entries[index].finalPath);
    }
    free(entries);
}

static void cf7_sfx_catalog_free_all(void)
{
    cf7_sfx_catalog_free_entries(
        g_runtime.sfxCatalog,
        g_runtime.sfxCatalogCount,
        g_runtime.engineInitialized);
    g_runtime.sfxCatalog = NULL;
    g_runtime.sfxCatalogCount = 0u;
}

static void cf7_graph_uninit(int preserveCatalogMetadata)
{
    InterlockedExchange(&g_control.notificationArmed, 0);
    cf7_bgm_uninit_sounds();
    cf7_sfx_catalog_uninit_voices();
    if (g_runtime.bgmGroupInitialized) {
        ma_sound_group_uninit(&g_runtime.bgmGroup);
        g_runtime.bgmGroupInitialized = 0;
    }
    if (g_runtime.sfxGroupInitialized) {
        ma_sound_group_uninit(&g_runtime.sfxGroup);
        g_runtime.sfxGroupInitialized = 0;
    }
    if (g_runtime.bgmMeter.initialized) {
        ma_node_uninit(&g_runtime.bgmMeter.base, NULL);
        g_runtime.bgmMeter.initialized = 0;
    }
    if (g_runtime.sfxMeter.initialized) {
        ma_node_uninit(&g_runtime.sfxMeter.base, NULL);
        g_runtime.sfxMeter.initialized = 0;
    }
    if (g_runtime.engineInitialized) {
        ma_engine_uninit(&g_runtime.engine);
        g_runtime.engineInitialized = 0;
    }
    if (g_runtime.resourceManagerInitialized) {
        ma_resource_manager_uninit(&g_runtime.resourceManager);
        g_runtime.resourceManagerInitialized = 0;
    }
    if (g_runtime.contextInitialized) {
        ma_context_uninit(&g_runtime.context);
        g_runtime.contextInitialized = 0;
    }
    if (!preserveCatalogMetadata) {
        cf7_sfx_catalog_free_all();
    }
    AcquireSRWLockExclusive(&g_control.snapshotLock);
    g_runtime.selectedBackend = CF7_AUDIO_BRIDGE_V2_BACKEND_NONE;
    g_runtime.selectedDeviceIdDigest[0] = '\0';
    free(g_runtime.selectedDeviceName);
    g_runtime.selectedDeviceName = NULL;
    g_runtime.sampleRate = 0u;
    g_runtime.channels = 0u;
    g_runtime.sampleFormat = CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_UNKNOWN;
    ReleaseSRWLockExclusive(&g_control.snapshotLock);
}

static ma_result cf7_meter_init_and_attach(
    cf7_meter_node* meter,
    ma_sound_group* group)
{
    ma_node_config config;
    ma_uint32 inputChannels[1];
    ma_uint32 outputChannels[1];
    ma_result result;
    uint32_t channels = ma_engine_get_channels(&g_runtime.engine);
    if (channels == 0u) {
        return MA_INVALID_OPERATION;
    }
    memset(meter, 0, sizeof(*meter));
    meter->channels = channels;
    cf7_meter_reset(meter);
    inputChannels[0] = channels;
    outputChannels[0] = channels;
    config = ma_node_config_init();
    config.vtable = &g_meterVtable;
    config.pInputChannels = inputChannels;
    config.pOutputChannels = outputChannels;
    config.initialState = ma_node_state_started;
    result = ma_node_init(
        ma_engine_get_node_graph(&g_runtime.engine),
        &config,
        NULL,
        &meter->base);
    if (result != MA_SUCCESS) {
        return result;
    }
    meter->initialized = 1;
    result = ma_node_attach_output_bus(
        &meter->base,
        0u,
        ma_engine_get_endpoint(&g_runtime.engine),
        0u);
    if (result == MA_SUCCESS) {
        result = ma_node_attach_output_bus(
            (ma_node*)group,
            0u,
            &meter->base,
            0u);
    }
    if (result != MA_SUCCESS) {
        ma_node_uninit(&meter->base, NULL);
        meter->initialized = 0;
    }
    return result;
}

static ma_result cf7_groups_and_meters_init(void)
{
    ma_result result;
    result = ma_sound_group_init(
        &g_runtime.engine,
        MA_SOUND_FLAG_NO_SPATIALIZATION,
        NULL,
        &g_runtime.bgmGroup);
    if (result != MA_SUCCESS) {
        return result;
    }
    g_runtime.bgmGroupInitialized = 1;
    result = ma_sound_group_init(
        &g_runtime.engine,
        MA_SOUND_FLAG_NO_SPATIALIZATION,
        NULL,
        &g_runtime.sfxGroup);
    if (result != MA_SUCCESS) {
        return result;
    }
    g_runtime.sfxGroupInitialized = 1;
    result = cf7_meter_init_and_attach(&g_runtime.bgmMeter, &g_runtime.bgmGroup);
    if (result != MA_SUCCESS) {
        return result;
    }
    result = cf7_meter_init_and_attach(&g_runtime.sfxMeter, &g_runtime.sfxGroup);
    if (result != MA_SUCCESS) {
        return result;
    }
    ma_sound_group_set_volume(&g_runtime.bgmGroup, g_runtime.bgmGain);
    ma_sound_group_set_volume(&g_runtime.sfxGroup, g_runtime.sfxGain);
    result = ma_sound_group_start(&g_runtime.bgmGroup);
    if (result != MA_SUCCESS) {
        return result;
    }
    result = ma_sound_group_start(&g_runtime.sfxGroup);
    if (result != MA_SUCCESS) {
        (void)ma_sound_group_stop(&g_runtime.bgmGroup);
        return result;
    }
    return ma_engine_set_volume(&g_runtime.engine, g_runtime.masterGain);
}

static int cf7_device_telemetry_publish(uint32_t selectedBackend)
{
    ma_device* device = ma_engine_get_device(&g_runtime.engine);
    char digest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    char* endpointUtf8 = NULL;
    char* nameUtf8 = NULL;
    wchar_t* nameUtf16 = NULL;
    size_t nameLength = 0u;
    ma_result result;
    int ok = 0;
    if (device == NULL) {
        return 0;
    }
    memset(digest, 0, sizeof(digest));
    if (selectedBackend == CF7_AUDIO_BRIDGE_V2_BACKEND_WASAPI) {
        if (device->playback.id.wasapi[0] == L'\0' ||
            !cf7_audio_bridge_support_utf8_from_utf16(
                device->playback.id.wasapi,
                &endpointUtf8) ||
            !cf7_audio_bridge_support_sha256(
                endpointUtf8,
                strlen(endpointUtf8),
                digest)) {
            goto cleanup;
        }
    } else if (selectedBackend == CF7_AUDIO_BRIDGE_V2_BACKEND_DIRECTSOUND) {
        if (!cf7_audio_bridge_support_sha256(
                device->playback.id.dsound,
                sizeof(device->playback.id.dsound),
                digest)) {
            goto cleanup;
        }
    } else if (selectedBackend == CF7_AUDIO_BRIDGE_V2_BACKEND_WINMM) {
        if (!cf7_audio_bridge_support_sha256(
                &device->playback.id.winmm,
                sizeof(device->playback.id.winmm),
                digest)) {
            goto cleanup;
        }
    } else {
        goto cleanup;
    }

    result = ma_device_get_name(
        device,
        ma_device_type_playback,
        NULL,
        0u,
        &nameLength);
    if (result != MA_SUCCESS || nameLength > (size_t)INT_MAX - 1u) {
        goto cleanup;
    }
    nameUtf8 = (char*)malloc(nameLength + 1u);
    if (nameUtf8 == NULL) {
        goto cleanup;
    }
    result = ma_device_get_name(
        device,
        ma_device_type_playback,
        nameUtf8,
        nameLength + 1u,
        &nameLength);
    if (result != MA_SUCCESS ||
        !cf7_audio_bridge_support_utf16_from_utf8(nameUtf8, &nameUtf16)) {
        goto cleanup;
    }

    AcquireSRWLockExclusive(&g_control.snapshotLock);
    g_runtime.selectedBackend = selectedBackend;
    (void)strncpy_s(
        g_runtime.selectedDeviceIdDigest,
        sizeof(g_runtime.selectedDeviceIdDigest),
        digest,
        _TRUNCATE);
    free(g_runtime.selectedDeviceName);
    g_runtime.selectedDeviceName = nameUtf16;
    nameUtf16 = NULL;
    g_runtime.sampleRate = device->sampleRate;
    g_runtime.channels = device->playback.channels;
    g_runtime.sampleFormat = cf7_sample_format_from_ma(device->playback.format);
    ReleaseSRWLockExclusive(&g_control.snapshotLock);
    ok = g_runtime.sampleRate != 0u && g_runtime.channels != 0u &&
        g_runtime.sampleFormat != CF7_AUDIO_BRIDGE_V2_SAMPLE_FORMAT_UNKNOWN;

cleanup:
    cf7_audio_bridge_support_free(endpointUtf8);
    free(nameUtf8);
    cf7_audio_bridge_support_free(nameUtf16);
    return ok;
}

static int32_t cf7_try_backend(
    void* userData,
    uint32_t backend,
    uint32_t* failureStage,
    int32_t* nativeResult)
{
    cf7_backend_attempt* attempt = (cf7_backend_attempt*)userData;
    cf7_audio_runtime* runtime = attempt->runtime;
    ma_backend maBackend = cf7_backend_to_ma(backend);
    ma_resource_manager_config resourceConfig;
    ma_engine_config engineConfig;
    ma_result result;

    if (backend != CF7_AUDIO_BACKEND_POLICY_WASAPI &&
        backend != CF7_AUDIO_BACKEND_POLICY_DIRECTSOUND &&
        backend != CF7_AUDIO_BACKEND_POLICY_WINMM) {
        *failureStage = CF7_AUDIO_BACKEND_POLICY_STAGE_CONTEXT;
        *nativeResult = MA_INVALID_ARGS;
        return -1;
    }

    *failureStage = CF7_AUDIO_BACKEND_POLICY_STAGE_CONTEXT;
    result = ma_context_init(&maBackend, 1u, NULL, &runtime->context);
    *nativeResult = result;
    if (result != MA_SUCCESS) {
        return -1;
    }
    runtime->contextInitialized = 1;

    resourceConfig = ma_resource_manager_config_init();
    resourceConfig.decodedFormat = ma_format_f32;
    resourceConfig.ppCustomDecodingBackendVTables =
        runtime->decoderRegistry.backends;
    resourceConfig.customDecodingBackendCount = runtime->decoderRegistry.count;
    memset(&runtime->mfDecodeControl, 0, sizeof(runtime->mfDecodeControl));
    runtime->mfDecodeControl.struct_size =
        (ma_uint32)sizeof(runtime->mfDecodeControl);
    runtime->mfDecodeControl.revision =
        CF7_AUDIO_MF_DECODE_CONTROL_REVISION;
    runtime->mfDecodeControl.maximum_read_wait_milliseconds =
        CF7_AUDIO_MF_DEFAULT_READ_WAIT_MS;
    runtime->mfDecodeControl.wait_slice_milliseconds =
        CF7_AUDIO_MF_DEFAULT_WAIT_SLICE_MS;
    runtime->mfDecodeControl.should_cancel = cf7_mf_cancel_requested;
    resourceConfig.pCustomDecodingBackendUserData =
        &runtime->mfDecodeControl;
    result = ma_resource_manager_init(&resourceConfig, &runtime->resourceManager);
    if (result != MA_SUCCESS) {
        *failureStage = CF7_AUDIO_BACKEND_POLICY_STAGE_DEVICE;
        *nativeResult = result;
        cf7_graph_uninit(1);
        return -1;
    }
    runtime->resourceManagerInitialized = 1;

    engineConfig = ma_engine_config_init();
    engineConfig.pContext = &runtime->context;
    engineConfig.pResourceManager = &runtime->resourceManager;
    engineConfig.noAutoStart = MA_TRUE;
    engineConfig.notificationCallback = cf7_device_notification;
    engineConfig.wasapi.noAutoStreamRouting = MA_TRUE;
    result = ma_engine_init(&engineConfig, &runtime->engine);
    if (result != MA_SUCCESS) {
        *failureStage = CF7_AUDIO_BACKEND_POLICY_STAGE_DEVICE;
        *nativeResult = result;
        cf7_graph_uninit(1);
        return -1;
    }
    runtime->engineInitialized = 1;
    result = cf7_groups_and_meters_init();
    if (result != MA_SUCCESS) {
        *failureStage = CF7_AUDIO_BACKEND_POLICY_STAGE_DEVICE;
        *nativeResult = result;
        cf7_graph_uninit(1);
        return -1;
    }

    *failureStage = CF7_AUDIO_BACKEND_POLICY_STAGE_START;
    result = ma_engine_start(&runtime->engine);
    *nativeResult = result;
    if (result != MA_SUCCESS) {
        cf7_graph_uninit(1);
        return -1;
    }
    if (!cf7_device_telemetry_publish(backend)) {
        *nativeResult = MA_INVALID_DATA;
        cf7_graph_uninit(1);
        return -1;
    }
    return 0;
}

static int cf7_real_graph_initialize(cf7_internal_result* failure)
{
    cf7_backend_attempt attempt;
    cf7_audio_backend_policy_result policyResult;
    int32_t selected;
    attempt.runtime = &g_runtime;
    memset(&policyResult, 0, sizeof(policyResult));
    selected = cf7_audio_backend_policy_select(
        cf7_try_backend,
        &attempt,
        &policyResult);
    if (selected != 0) {
        cf7_internal_result_set(
            failure,
            CF7_AUDIO_BRIDGE_V2_RESULT_DEVICE_UNAVAILABLE,
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            policyResult.lastFailureStage,
            policyResult.lastNativeResult,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.device.no_real_backend");
        return 0;
    }
    InterlockedExchange(&g_control.notificationArmed, 1);
    return 1;
}

static int cf7_resolve_audio_file(
    const wchar_t* input,
    wchar_t** finalPath,
    uint64_t* fileSize,
    int64_t* modified,
    DWORD* windowsError)
{
    if (g_runtime.finalBasePath == NULL) {
        if (windowsError != NULL) {
            *windowsError = ERROR_INVALID_STATE;
        }
        return 0;
    }
    return cf7_audio_bridge_support_resolve_file(
        g_runtime.finalBasePath,
        input,
        finalPath,
        fileSize,
        modified,
        windowsError);
}

static ma_result cf7_sfx_entry_init_voices(cf7_sfx_entry* entry)
{
    uint32_t voice;
    ma_result result = MA_SUCCESS;
    memset(entry->voiceInitialized, 0, sizeof(entry->voiceInitialized));
    entry->nextVoice = 0u;
    entry->lastPlayMilliseconds = 0u;
    for (voice = 0u; voice < CF7_SFX_VOICES; ++voice) {
        result = ma_sound_init_from_file_w(
            &g_runtime.engine,
            entry->finalPath,
            MA_SOUND_FLAG_DECODE | MA_SOUND_FLAG_NO_SPATIALIZATION,
            &g_runtime.sfxGroup,
            NULL,
            &entry->voices[voice]);
        if (result != MA_SUCCESS) {
            cf7_sfx_entry_uninit_voices(entry);
            return result;
        }
        entry->voiceInitialized[voice] = 1u;
    }
    return MA_SUCCESS;
}

static ma_result cf7_sfx_catalog_init_existing_voices(void)
{
    uint32_t index;
    ma_result result;
    for (index = 0u; index < g_runtime.sfxCatalogCount; ++index) {
        result = cf7_sfx_entry_init_voices(&g_runtime.sfxCatalog[index]);
        if (result != MA_SUCCESS) {
            uint32_t rollback;
            for (rollback = 0u; rollback < index; ++rollback) {
                cf7_sfx_entry_uninit_voices(&g_runtime.sfxCatalog[rollback]);
            }
            return result;
        }
    }
    return MA_SUCCESS;
}

static cf7_sfx_entry* cf7_sfx_find(const char* linkageId)
{
    uint32_t index;
    for (index = 0u; index < g_runtime.sfxCatalogCount; ++index) {
        if (strcmp(g_runtime.sfxCatalog[index].linkageId, linkageId) == 0) {
            return &g_runtime.sfxCatalog[index];
        }
    }
    return NULL;
}

static void cf7_bgm_start_result_set(
    uint32_t category,
    uint32_t operation,
    uint32_t stage,
    ma_result rawResult,
    uint32_t completion,
    const char* message)
{
    cf7_internal_result_set(
        &g_runtime.bgmStartResult,
        category,
        operation,
        stage,
        rawResult,
        0,
        completion,
        message);
}

static uint32_t cf7_bgm_play_final(
    const wchar_t* finalPath,
    int loop,
    float volume,
    float fadeSeconds,
    int updateIntent,
    cf7_audio_bridge_v2_result* result)
{
    cf7_audio_bridge_support_sniff sniff;
    char firstHash[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    DWORD windowsError = ERROR_SUCCESS;
    ma_result maResult;
    uint32_t oldSlot = g_runtime.bgmActive;
    uint32_t newSlot = 1u - oldSlot;
    uint64_t fadeMilliseconds;
    ma_uint64 now;
    wchar_t* intentPath = NULL;

    memset(&sniff, 0, sizeof(sniff));
    if (!cf7_audio_bridge_support_sniff_file(
            finalPath,
            &sniff,
            firstHash,
            &windowsError)) {
        cf7_bgm_start_result_set(
            CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR,
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
            MA_IO_ERROR,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.sniff_failed");
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR,
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
            MA_IO_ERROR,
            (int32_t)windowsError,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.sniff_failed");
    }
    if (sniff.container == 0u || sniff.codec == 0u || sniff.decoder == 0u) {
        cf7_bgm_start_result_set(
            CF7_AUDIO_BRIDGE_V2_RESULT_UNSUPPORTED_CONTAINER,
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_DECODER_INITIALIZE,
            MA_FORMAT_NOT_SUPPORTED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.unsupported_content");
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_UNSUPPORTED_CONTAINER,
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_DECODER_INITIALIZE,
            MA_FORMAT_NOT_SUPPORTED,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.unsupported_content");
    }
    if (updateIntent) {
        intentPath = _wcsdup(finalPath);
        if (intentPath == NULL) {
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR,
                CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
                CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
                MA_OUT_OF_MEMORY,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.bgm.intent_allocation_failed");
        }
    }

    if (g_runtime.bgmInitialized[newSlot]) {
        (void)ma_sound_stop(&g_runtime.bgm[newSlot]);
        ma_sound_uninit(&g_runtime.bgm[newSlot]);
        g_runtime.bgmInitialized[newSlot] = 0u;
    }
    memset(&g_runtime.bgm[newSlot], 0, sizeof(g_runtime.bgm[newSlot]));
    maResult = ma_sound_init_from_file_w(
        &g_runtime.engine,
        finalPath,
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION,
        &g_runtime.bgmGroup,
        NULL,
        &g_runtime.bgm[newSlot]);
    if (maResult != MA_SUCCESS) {
        free(intentPath);
        cf7_bgm_start_result_set(
            cf7_category_from_ma(maResult, 1),
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
            maResult,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.source_initialize_failed");
        return cf7_result_current(
            result,
            cf7_category_from_ma(maResult, 1),
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
            maResult,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.source_initialize_failed");
    }
    g_runtime.bgmInitialized[newSlot] = 1u;
    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        ma_sound_uninit(&g_runtime.bgm[newSlot]);
        g_runtime.bgmInitialized[newSlot] = 0u;
        free(intentPath);
        cf7_bgm_start_result_set(
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.cancelled");
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.cancelled");
    }
    ma_sound_set_looping(&g_runtime.bgm[newSlot], loop ? MA_TRUE : MA_FALSE);
    ma_sound_set_volume(&g_runtime.bgm[newSlot], 1.0f);
    ma_sound_group_set_volume(&g_runtime.bgmGroup, volume);
    fadeMilliseconds = (uint64_t)((double)fadeSeconds * 1000.0);
    if (fadeMilliseconds >= CF7_BGM_MIN_FADE_MS) {
        ma_sound_set_fade_in_milliseconds(
            &g_runtime.bgm[newSlot],
            0.0f,
            1.0f,
            fadeMilliseconds);
    }
    maResult = ma_sound_start(&g_runtime.bgm[newSlot]);
    if (maResult != MA_SUCCESS) {
        ma_sound_uninit(&g_runtime.bgm[newSlot]);
        g_runtime.bgmInitialized[newSlot] = 0u;
        free(intentPath);
        cf7_bgm_start_result_set(
            CF7_AUDIO_BRIDGE_V2_RESULT_START_FAILED,
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
            maResult,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.start_failed");
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_START_FAILED,
            CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
            CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
            maResult,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.start_failed");
    }

    if (g_runtime.bgmInitialized[oldSlot]) {
        if (fadeMilliseconds >= CF7_BGM_MIN_FADE_MS) {
            now = ma_engine_get_time_in_milliseconds(&g_runtime.engine);
            ma_sound_set_fade_in_milliseconds(
                &g_runtime.bgm[oldSlot],
                -1.0f,
                0.0f,
                fadeMilliseconds);
            ma_sound_set_stop_time_in_milliseconds(
                &g_runtime.bgm[oldSlot],
                now + fadeMilliseconds);
        } else {
            maResult = ma_sound_stop(&g_runtime.bgm[oldSlot]);
            if (maResult != MA_SUCCESS) {
                (void)ma_sound_stop(&g_runtime.bgm[newSlot]);
                ma_sound_uninit(&g_runtime.bgm[newSlot]);
                g_runtime.bgmInitialized[newSlot] = 0u;
                free(intentPath);
                return cf7_result_current(
                    result,
                    CF7_AUDIO_BRIDGE_V2_RESULT_START_FAILED,
                    CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
                    CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
                    maResult,
                    0,
                    CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                    "audio.bgm.old_source_stop_failed");
            }
        }
    }
    g_runtime.bgmActive = newSlot;
    g_runtime.bgmDecoder = sniff.decoder;
    g_runtime.bgmContainer = sniff.container;
    g_runtime.bgmCodec = sniff.codec;
    g_runtime.bgmGain = volume;
    if (updateIntent) {
        free(g_runtime.latestBgmPath);
        g_runtime.latestBgmPath = intentPath;
        g_runtime.latestBgmPresent = 1;
        g_runtime.latestBgmPaused = 0;
        g_runtime.latestBgmLoop = loop;
        g_runtime.latestBgmVolume = volume;
        g_runtime.latestBgmCursorFrames = 0u;
    }
    cf7_bgm_start_result_set(
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
        CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
        MA_SUCCESS,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
        "audio.bgm.started");
    return cf7_result_current(
        result,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY,
        CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
        MA_SUCCESS,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
        "audio.bgm.started");
}

static int cf7_device_generation_advance(void)
{
    int ok = 1;
    AcquireSRWLockExclusive(&g_control.snapshotLock);
    if (g_runtime.deviceGeneration == UINT64_MAX) {
        ok = 0;
    } else {
        ++g_runtime.deviceGeneration;
    }
    ReleaseSRWLockExclusive(&g_control.snapshotLock);
    return ok;
}

/*
 * Device notifications can arrive on a miniaudio callback thread, but all
 * mutation stays on the native owner. The owner only publishes RECOVERING and
 * freezes the best available cursor. The managed AudioCoordinator is the
 * lifecycle authority: it observes query_runtime, advances readyGeneration,
 * and drives the existing shutdown/initialize/catalog/replay sequence. This
 * avoids a native-only self-heal that the AS2/C# admission snapshot cannot see.
 */
static void cf7_mark_device_recovery_requested(void)
{
    ma_uint64 cursor = 0u;
    if (g_runtime.audioStatus != CF7_AUDIO_BRIDGE_V2_AUDIO_READY ||
        !g_runtime.engineInitialized) {
        InterlockedExchange(&g_control.recoveryRequested, 0);
        return;
    }
    if (g_runtime.latestBgmPresent &&
        g_runtime.bgmInitialized[g_runtime.bgmActive] &&
        ma_sound_get_cursor_in_pcm_frames(
            &g_runtime.bgm[g_runtime.bgmActive],
            &cursor) == MA_SUCCESS) {
        g_runtime.latestBgmCursorFrames = cursor;
    }
    InterlockedExchange(&g_control.notificationArmed, 0);
    cf7_runtime_set_status(CF7_AUDIO_BRIDGE_V2_AUDIO_RECOVERING);
    InterlockedExchange(&g_control.recoveryRequested, 0);
}

static int cf7_probe_vfs_cancelled(cf7_probe_vfs* vfs)
{
    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        vfs->cancelledHit = 1;
        return 1;
    }
    if (vfs->deadline != 0u && GetTickCount64() >= vfs->deadline) {
        vfs->timeoutHit = 1;
        return 1;
    }
    return 0;
}

static ma_result cf7_probe_vfs_open(
    ma_vfs* opaque,
    const char* path,
    ma_uint32 mode,
    ma_vfs_file* file)
{
    cf7_probe_vfs* vfs = (cf7_probe_vfs*)opaque;
    ma_file_info info;
    ma_result result;
    if (cf7_probe_vfs_cancelled(vfs)) {
        return vfs->timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
    }
    result = vfs->base.cb.onOpen((ma_vfs*)&vfs->base, path, mode, file);
    if (result != MA_SUCCESS || vfs->maximumBytes == 0u) {
        return result;
    }
    result = vfs->base.cb.onInfo((ma_vfs*)&vfs->base, *file, &info);
    if (result != MA_SUCCESS) {
        (void)vfs->base.cb.onClose((ma_vfs*)&vfs->base, *file);
        *file = NULL;
        return result;
    }
    vfs->activeFile = *file;
    vfs->virtualLength = info.sizeInBytes;
    vfs->virtualLengthActive = 1;
    if (vfs->virtualLength > vfs->maximumBytes) {
        vfs->virtualLength = vfs->maximumBytes;
        vfs->prefixTruncated = 1;
    }
    return MA_SUCCESS;
}

static ma_result cf7_probe_vfs_open_w(
    ma_vfs* opaque,
    const wchar_t* path,
    ma_uint32 mode,
    ma_vfs_file* file)
{
    cf7_probe_vfs* vfs = (cf7_probe_vfs*)opaque;
    ma_file_info info;
    ma_result result;
    if (cf7_probe_vfs_cancelled(vfs)) {
        return vfs->timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
    }
    result = vfs->base.cb.onOpenW((ma_vfs*)&vfs->base, path, mode, file);
    if (result != MA_SUCCESS || vfs->maximumBytes == 0u) {
        return result;
    }
    result = vfs->base.cb.onInfo((ma_vfs*)&vfs->base, *file, &info);
    if (result != MA_SUCCESS) {
        (void)vfs->base.cb.onClose((ma_vfs*)&vfs->base, *file);
        *file = NULL;
        return result;
    }
    vfs->activeFile = *file;
    vfs->virtualLength = info.sizeInBytes;
    vfs->virtualLengthActive = 1;
    if (vfs->virtualLength > vfs->maximumBytes) {
        vfs->virtualLength = vfs->maximumBytes;
        vfs->prefixTruncated = 1;
    }
    return MA_SUCCESS;
}

static ma_result cf7_probe_vfs_close(ma_vfs* opaque, ma_vfs_file file)
{
    cf7_probe_vfs* vfs = (cf7_probe_vfs*)opaque;
    ma_result result = vfs->base.cb.onClose((ma_vfs*)&vfs->base, file);
    if (file == vfs->activeFile) {
        vfs->activeFile = NULL;
        vfs->virtualLength = 0u;
        vfs->virtualLengthActive = 0;
    }
    return result;
}

static ma_result cf7_probe_vfs_read(
    ma_vfs* opaque,
    ma_vfs_file file,
    void* destination,
    size_t requested,
    size_t* bytesRead)
{
    cf7_probe_vfs* vfs = (cf7_probe_vfs*)opaque;
    size_t allowed = requested;
    size_t totalRead = 0u;
    ma_int64 cursor = 0;
    ma_result result;
    if (bytesRead != NULL) {
        *bytesRead = 0u;
    }
    if (cf7_probe_vfs_cancelled(vfs)) {
        return vfs->timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
    }
    if (vfs->virtualLengthActive && file == vfs->activeFile) {
        result = vfs->base.cb.onTell(
            (ma_vfs*)&vfs->base,
            file,
            &cursor);
        if (result != MA_SUCCESS || cursor < 0) {
            return result != MA_SUCCESS ? result : MA_INVALID_FILE;
        }
        if ((uint64_t)cursor >= vfs->virtualLength) {
            return MA_AT_END;
        }
        if ((uint64_t)allowed > vfs->virtualLength - (uint64_t)cursor) {
            allowed = (size_t)(vfs->virtualLength - (uint64_t)cursor);
        }
    }
    if (vfs->maximumBytes != 0u) {
        uint64_t remaining = vfs->maximumBytes > vfs->bytesRead
            ? vfs->maximumBytes - vfs->bytesRead
            : 0u;
        if (remaining == 0u) {
            vfs->limitHit = 1;
            return MA_CANCELLED;
        }
        if ((uint64_t)allowed > remaining) {
            allowed = (size_t)remaining;
            vfs->limitHit = 1;
        }
    }
    if (allowed != 0u && destination == NULL) {
        return MA_INVALID_ARGS;
    }
    while (totalRead < allowed) {
        size_t chunk = allowed - totalRead;
        size_t chunkRead = 0u;
        if (chunk > CF7_PROBE_INPUT_READ_CHUNK_BYTES) {
            chunk = CF7_PROBE_INPUT_READ_CHUNK_BYTES;
        }
        if (cf7_probe_vfs_cancelled(vfs)) {
            if (bytesRead != NULL) {
                *bytesRead = totalRead;
            }
            return vfs->timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
        }
        result = vfs->base.cb.onRead(
            (ma_vfs*)&vfs->base,
            file,
            (unsigned char*)destination + totalRead,
            chunk,
            &chunkRead);
        if (chunkRead > chunk) {
            if (bytesRead != NULL) {
                *bytesRead = totalRead;
            }
            return MA_INVALID_FILE;
        }
        totalRead += chunkRead;
        vfs->bytesRead += (uint64_t)chunkRead;
        if (result == MA_AT_END && chunkRead != 0u) {
            result = MA_SUCCESS;
        }
        if (result != MA_SUCCESS) {
            if (bytesRead != NULL) {
                *bytesRead = totalRead;
            }
            return result;
        }
        if (chunkRead == 0u) {
            if (bytesRead != NULL) {
                *bytesRead = totalRead;
            }
            return MA_AT_END;
        }
        if (chunkRead < chunk) {
            break;
        }
    }
    if (bytesRead != NULL) {
        *bytesRead = totalRead;
    }
    return MA_SUCCESS;
}

static ma_result cf7_probe_vfs_write(
    ma_vfs* opaque,
    ma_vfs_file file,
    const void* source,
    size_t requested,
    size_t* bytesWritten)
{
    (void)opaque;
    (void)file;
    (void)source;
    (void)requested;
    if (bytesWritten != NULL) {
        *bytesWritten = 0u;
    }
    return MA_INVALID_OPERATION;
}

static ma_result cf7_probe_vfs_seek(
    ma_vfs* opaque,
    ma_vfs_file file,
    ma_int64 offset,
    ma_seek_origin origin)
{
    cf7_probe_vfs* vfs = (cf7_probe_vfs*)opaque;
    ma_int64 virtualLength;
    ma_int64 target;
    if (cf7_probe_vfs_cancelled(vfs)) {
        return vfs->timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
    }
    if (vfs->virtualLengthActive && file == vfs->activeFile &&
        origin == ma_seek_origin_end) {
        if (vfs->virtualLength > (uint64_t)INT64_MAX) {
            return MA_INVALID_FILE;
        }
        virtualLength = (ma_int64)vfs->virtualLength;
        if ((offset > 0 && offset > INT64_MAX - virtualLength) ||
            (offset < 0 && offset < -virtualLength)) {
            return MA_INVALID_ARGS;
        }
        target = virtualLength + offset;
        return vfs->base.cb.onSeek(
            (ma_vfs*)&vfs->base,
            file,
            target,
            ma_seek_origin_start);
    }
    return vfs->base.cb.onSeek((ma_vfs*)&vfs->base, file, offset, origin);
}

static ma_result cf7_probe_vfs_tell(
    ma_vfs* opaque,
    ma_vfs_file file,
    ma_int64* cursor)
{
    cf7_probe_vfs* vfs = (cf7_probe_vfs*)opaque;
    if (cf7_probe_vfs_cancelled(vfs)) {
        return vfs->timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
    }
    return vfs->base.cb.onTell((ma_vfs*)&vfs->base, file, cursor);
}

static ma_result cf7_probe_vfs_info(
    ma_vfs* opaque,
    ma_vfs_file file,
    ma_file_info* info)
{
    cf7_probe_vfs* vfs = (cf7_probe_vfs*)opaque;
    ma_result result;
    if (cf7_probe_vfs_cancelled(vfs)) {
        return vfs->timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
    }
    result = vfs->base.cb.onInfo((ma_vfs*)&vfs->base, file, info);
    if (result == MA_SUCCESS && vfs->virtualLengthActive &&
        file == vfs->activeFile) {
        info->sizeInBytes = vfs->virtualLength;
    }
    return result;
}

static ma_result cf7_probe_vfs_initialize(
    cf7_probe_vfs* vfs,
    uint64_t maximumBytes,
    ULONGLONG deadline)
{
    ma_result result;
    memset(vfs, 0, sizeof(*vfs));
    result = ma_default_vfs_init(&vfs->base, NULL);
    if (result != MA_SUCCESS) {
        return result;
    }
    vfs->callbacks.onOpen = cf7_probe_vfs_open;
    vfs->callbacks.onOpenW = cf7_probe_vfs_open_w;
    vfs->callbacks.onClose = cf7_probe_vfs_close;
    vfs->callbacks.onRead = cf7_probe_vfs_read;
    vfs->callbacks.onWrite = cf7_probe_vfs_write;
    vfs->callbacks.onSeek = cf7_probe_vfs_seek;
    vfs->callbacks.onTell = cf7_probe_vfs_tell;
    vfs->callbacks.onInfo = cf7_probe_vfs_info;
    vfs->maximumBytes = maximumBytes;
    vfs->deadline = deadline;
    return MA_SUCCESS;
}

static void cf7_probe_result_zero_metrics(
    cf7_audio_bridge_v2_probe_result* result)
{
    result->outcome = CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE;
    result->eofState = CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED;
    result->frames = 0u;
    result->durationSeconds = 0.0;
    result->peak = 0.0;
    result->rms = 0.0;
    result->leadingSilenceFrames = 0u;
    result->trailingSilenceFrames = 0u;
    result->nonFiniteCount = 0u;
    result->elapsedMs = 0u;
    result->reserved0 = 0u;
    result->inputBytesRead = 0u;
}

static uint32_t cf7_probe_finish(
    cf7_audio_bridge_v2_probe_result* probeResult,
    cf7_audio_bridge_v2_result* result,
    uint32_t operation,
    uint32_t category,
    uint32_t stage,
    ma_result rawResult,
    uint32_t outcome,
    uint32_t eofState,
    uint32_t completion,
    const char* messageKey)
{
    uint32_t outer;
    probeResult->outcome = outcome;
    probeResult->eofState = eofState;
    outer = cf7_result_current(
        result,
        category,
        operation,
        stage,
        rawResult,
        0,
        completion,
        messageKey);
    (void)cf7_result_current(
        &probeResult->structuredResult,
        category,
        operation,
        stage,
        rawResult,
        0,
        completion,
        messageKey);
    return outer;
}

static ma_result cf7_probe_decode(
    const wchar_t* finalPath,
    uint64_t maximumFrames,
    uint64_t maximumInputBytes,
    uint32_t maximumWallMilliseconds,
    uint64_t decoderBackend,
    int requireEof,
    cf7_audio_bridge_v2_probe_result* probeResult,
    int* reachedEof,
    int* inconclusive,
    int* inputBoundInconclusive)
{
    ULONGLONG started = GetTickCount64();
    ULONGLONG deadline = started + maximumWallMilliseconds;
    ULONGLONG decodeDeadline = deadline;
    cf7_probe_vfs vfs;
    cf7_audio_mf_decode_control mfControl;
    ma_decoder decoder;
    ma_decoder_config config;
    float* frames = NULL;
    ma_result result;
    ma_uint64 totalFrames = 0u;
    ma_uint64 framesRead = 0u;
    uint32_t channels;
    uint32_t sampleRate;
    double sumSquares = 0.0;
    uint64_t sampleCount = 0u;
    uint64_t leading = 0u;
    uint64_t trailing = 0u;
    int signalSeen = 0;
    int decoderInitialized = 0;

    *reachedEof = 0;
    *inconclusive = 0;
    *inputBoundInconclusive = 0;
    result = cf7_probe_vfs_initialize(&vfs, maximumInputBytes, deadline);
    if (result != MA_SUCCESS) {
        return result;
    }
    config = ma_decoder_config_init(ma_format_f32, 0u, 0u);
    if (maximumWallMilliseconds > CF7_AUDIO_MF_CLEANUP_RESERVE_MS + 1u) {
        decodeDeadline = started + maximumWallMilliseconds -
            CF7_AUDIO_MF_CLEANUP_RESERVE_MS;
    }
    memset(&mfControl, 0, sizeof(mfControl));
    mfControl.struct_size = (ma_uint32)sizeof(mfControl);
    mfControl.revision = CF7_AUDIO_MF_DECODE_CONTROL_REVISION;
    mfControl.deadline_tick_milliseconds = decodeDeadline;
    mfControl.maximum_read_wait_milliseconds =
        maximumWallMilliseconds > CF7_AUDIO_MF_CLEANUP_RESERVE_MS + 1u
            ? maximumWallMilliseconds - CF7_AUDIO_MF_CLEANUP_RESERVE_MS
            : 1u;
    mfControl.wait_slice_milliseconds =
        mfControl.maximum_read_wait_milliseconds <
                CF7_AUDIO_MF_DEFAULT_WAIT_SLICE_MS
            ? mfControl.maximum_read_wait_milliseconds
            : CF7_AUDIO_MF_DEFAULT_WAIT_SLICE_MS;
    mfControl.should_cancel = cf7_mf_cancel_requested;
    if (decoderBackend == CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_BUILTIN) {
        config.ppCustomBackendVTables = NULL;
        config.customBackendCount = 0u;
    } else if (decoderBackend ==
            CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_MEDIA_FOUNDATION) {
        config.ppCustomBackendVTables = &g_runtime.decoderRegistry.backends[0];
        config.customBackendCount = 1u;
    } else if (decoderBackend ==
            CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_LIBVORBIS) {
        config.ppCustomBackendVTables = &g_runtime.decoderRegistry.backends[1];
        config.customBackendCount = 1u;
    } else if (decoderBackend ==
            CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_LIBOPUS) {
        config.ppCustomBackendVTables = &g_runtime.decoderRegistry.backends[2];
        config.customBackendCount = 1u;
    } else {
        config.ppCustomBackendVTables = g_runtime.decoderRegistry.backends;
        config.customBackendCount = g_runtime.decoderRegistry.count;
    }
    config.pCustomBackendUserData = &mfControl;
    result = ma_decoder_init_vfs_w(
        (ma_vfs*)&vfs,
        finalPath,
        &config,
        &decoder);
    if (GetTickCount64() >= deadline) {
        vfs.timeoutHit = 1;
    } else if (WaitForSingleObject(g_control.cancelEvent, 0u) ==
            WAIT_OBJECT_0) {
        vfs.cancelledHit = 1;
    }
    if (result != MA_SUCCESS) {
        if (vfs.timeoutHit) {
            result = MA_TIMEOUT;
        } else if (vfs.cancelledHit) {
            result = MA_CANCELLED;
        }
        if (vfs.timeoutHit || vfs.limitHit || vfs.cancelledHit ||
            vfs.prefixTruncated) {
            *inconclusive = 1;
        }
        if (!vfs.timeoutHit && !vfs.cancelledHit &&
            (vfs.limitHit || vfs.prefixTruncated)) {
            *inputBoundInconclusive = 1;
        }
        probeResult->elapsedMs = (uint32_t)(GetTickCount64() - started);
        probeResult->inputBytesRead = vfs.bytesRead;
        return result;
    }
    decoderInitialized = 1;
    channels = decoder.outputChannels;
    sampleRate = decoder.outputSampleRate;
    if (channels == 0u || channels > MA_MAX_CHANNELS || sampleRate == 0u ||
        (size_t)channels > SIZE_MAX / (sizeof(float) * CF7_PROBE_FRAMES_PER_READ)) {
        result = MA_INVALID_DATA;
        goto cleanup;
    }
    frames = (float*)malloc(
        sizeof(float) * (size_t)channels * CF7_PROBE_FRAMES_PER_READ);
    if (frames == NULL) {
        result = MA_OUT_OF_MEMORY;
        goto cleanup;
    }

    for (;;) {
        ma_uint64 requested = CF7_PROBE_FRAMES_PER_READ;
        ma_uint64 frameIndex;
        if (GetTickCount64() >= deadline ||
            WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
            vfs.timeoutHit = GetTickCount64() >= deadline;
            vfs.cancelledHit = !vfs.timeoutHit;
            *inconclusive = 1;
            result = vfs.timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
            break;
        }
        if (!requireEof && totalFrames >= maximumFrames) {
            result = MA_SUCCESS;
            break;
        }
        if (!requireEof && requested > maximumFrames - totalFrames) {
            requested = maximumFrames - totalFrames;
        }
        framesRead = 0u;
        result = ma_decoder_read_pcm_frames(
            &decoder,
            frames,
            requested,
            &framesRead);
        if (GetTickCount64() >= deadline ||
            WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
            vfs.timeoutHit = GetTickCount64() >= deadline;
            vfs.cancelledHit = !vfs.timeoutHit;
            *inconclusive = 1;
            result = vfs.timeoutHit ? MA_TIMEOUT : MA_CANCELLED;
            break;
        }
        for (frameIndex = 0u; frameIndex < framesRead; ++frameIndex) {
            uint32_t channel;
            int frameHasSignal = 0;
            for (channel = 0u; channel < channels; ++channel) {
                float sample = frames[(size_t)frameIndex * channels + channel];
                if (!isfinite(sample)) {
                    ++probeResult->nonFiniteCount;
                    continue;
                }
                {
                    double absolute = fabs((double)sample);
                    if (absolute > probeResult->peak) {
                        probeResult->peak = absolute;
                    }
                    sumSquares += (double)sample * (double)sample;
                    ++sampleCount;
                    if (absolute > CF7_SILENCE_THRESHOLD) {
                        frameHasSignal = 1;
                    }
                }
            }
            if (frameHasSignal) {
                signalSeen = 1;
                trailing = 0u;
            } else if (!signalSeen) {
                ++leading;
                ++trailing;
            } else {
                ++trailing;
            }
        }
        totalFrames += framesRead;
        if (result == MA_AT_END) {
            *reachedEof = 1;
            result = MA_SUCCESS;
            break;
        }
        if (result != MA_SUCCESS) {
            if (vfs.timeoutHit || vfs.limitHit || vfs.cancelledHit ||
                vfs.prefixTruncated || result == MA_TIMEOUT ||
                result == MA_CANCELLED) {
                *inconclusive = 1;
            }
            if (!vfs.timeoutHit && !vfs.cancelledHit &&
                (vfs.limitHit || vfs.prefixTruncated)) {
                *inputBoundInconclusive = 1;
            }
            break;
        }
        if (framesRead == 0u) {
            result = MA_INVALID_DATA;
            break;
        }
    }

    probeResult->frames = totalFrames;
    probeResult->durationSeconds = sampleRate == 0u
        ? 0.0
        : (double)totalFrames / (double)sampleRate;
    probeResult->rms = sampleCount == 0u
        ? 0.0
        : sqrt(sumSquares / (double)sampleCount);
    probeResult->leadingSilenceFrames = leading;
    probeResult->trailingSilenceFrames = trailing;

cleanup:
    if (vfs.prefixTruncated && totalFrames == 0u &&
        !vfs.timeoutHit && !vfs.cancelledHit) {
        *inconclusive = 1;
        *inputBoundInconclusive = 1;
    }
    free(frames);
    if (decoderInitialized) {
        (void)ma_decoder_uninit(&decoder);
    }
    probeResult->elapsedMs = (uint32_t)(GetTickCount64() - started);
    probeResult->inputBytesRead = vfs.bytesRead;
    return result;
}

static int cf7_capability_digest(
    char digest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY])
{
    static const char canonical[] =
        "cf7.audio-v2;abi=2.0;wire=2;probe=1;miniaudio=0.11.25;"
        "backends=wasapi,dsound,winmm;null=0;"
        "decoders=builtin,libvorbis,mf,libopus;"
        "containers=riff,mpeg,flac,ogg,mp4,adts;"
        "codecs=pcm,mp3,flac,vorbis,aac,opus;meters=bgm,sfx";
    return cf7_audio_bridge_support_sha256(
        canonical,
        sizeof(canonical) - 1u,
        digest);
}

static void cf7_ogg_scan_complete_page(cf7_ogg_scan* scan)
{
    ++scan->completePages;
    scan->phase = CF7_OGG_SCAN_HEADER;
    scan->headerBytes = 0u;
    scan->lacingBytes = 0u;
    scan->bodyBytesRemaining = 0u;
}

static void cf7_ogg_scan_update(
    cf7_ogg_scan* scan,
    const unsigned char* bytes,
    size_t byteCount)
{
    static const unsigned char capture[4] = {'O', 'g', 'g', 'S'};
    size_t offset = 0u;
    while (offset < byteCount && !scan->notOgg && !scan->malformed) {
        if (scan->phase == CF7_OGG_SCAN_HEADER) {
            size_t required = sizeof(scan->header) - scan->headerBytes;
            size_t available = byteCount - offset;
            size_t take = required < available ? required : available;
            memcpy(scan->header + scan->headerBytes, bytes + offset, take);
            scan->headerBytes += take;
            offset += take;
            if (scan->headerBytes >= sizeof(capture) &&
                memcmp(scan->header, capture, sizeof(capture)) != 0) {
                if (scan->completePages == 0u) {
                    scan->notOgg = 1;
                } else {
                    scan->malformed = 1;
                }
                continue;
            }
            if (scan->headerBytes != sizeof(scan->header)) {
                continue;
            }
            if (scan->header[4] != 0u) {
                scan->malformed = 1;
                continue;
            }
            scan->lacingBytes = 0u;
            scan->bodyBytesRemaining = 0u;
            if (scan->header[26] == 0u) {
                cf7_ogg_scan_complete_page(scan);
            } else {
                scan->phase = CF7_OGG_SCAN_LACING;
            }
            continue;
        }
        if (scan->phase == CF7_OGG_SCAN_LACING) {
            uint32_t segmentCount = scan->header[26];
            size_t available = byteCount - offset;
            size_t required = (size_t)(segmentCount - scan->lacingBytes);
            size_t take = required < available ? required : available;
            size_t index;
            for (index = 0u; index < take; ++index) {
                scan->bodyBytesRemaining += bytes[offset + index];
            }
            scan->lacingBytes += (uint32_t)take;
            offset += take;
            if (scan->lacingBytes == segmentCount) {
                if (scan->bodyBytesRemaining == 0u) {
                    cf7_ogg_scan_complete_page(scan);
                } else {
                    scan->phase = CF7_OGG_SCAN_BODY;
                }
            }
            continue;
        }
        {
            size_t available = byteCount - offset;
            size_t take = scan->bodyBytesRemaining < available
                ? (size_t)scan->bodyBytesRemaining
                : available;
            scan->bodyBytesRemaining -= (uint32_t)take;
            offset += take;
            if (scan->bodyBytesRemaining == 0u) {
                cf7_ogg_scan_complete_page(scan);
            }
        }
    }
}

static cf7_ogg_physical_state cf7_ogg_scan_finish(const cf7_ogg_scan* scan)
{
    static const unsigned char capture[4] = {'O', 'g', 'g', 'S'};
    size_t captureBytes;
    if (scan->notOgg) {
        return CF7_OGG_PHYSICAL_NOT_OGG;
    }
    if (scan->malformed) {
        return CF7_OGG_PHYSICAL_MALFORMED;
    }
    if (scan->phase == CF7_OGG_SCAN_HEADER && scan->headerBytes == 0u) {
        return scan->completePages == 0u
            ? CF7_OGG_PHYSICAL_NOT_OGG
            : CF7_OGG_PHYSICAL_COMPLETE;
    }
    if (scan->phase != CF7_OGG_SCAN_HEADER) {
        return CF7_OGG_PHYSICAL_TRUNCATED;
    }
    captureBytes = scan->headerBytes < sizeof(capture)
        ? scan->headerBytes
        : sizeof(capture);
    if (memcmp(scan->header, capture, captureBytes) != 0) {
        return scan->completePages == 0u
            ? CF7_OGG_PHYSICAL_NOT_OGG
            : CF7_OGG_PHYSICAL_MALFORMED;
    }
    return scan->headerBytes >= sizeof(capture) || scan->completePages != 0u
        ? CF7_OGG_PHYSICAL_TRUNCATED
        : CF7_OGG_PHYSICAL_NOT_OGG;
}

static int cf7_file_full_sha256(
    const wchar_t* path,
    ULONGLONG deadline,
    char digest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY],
    int* interrupted,
    cf7_ogg_physical_state* oggPhysicalState)
{
    static const char hex[] = "0123456789ABCDEF";
    BCRYPT_ALG_HANDLE algorithm = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    HANDLE file = CreateFileW(
        path,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        NULL);
    unsigned char buffer[65536];
    unsigned char rawDigest[32];
    cf7_ogg_scan oggScan;
    size_t index;
    int ok = 0;
    if (interrupted == NULL || oggPhysicalState == NULL) {
        if (file != INVALID_HANDLE_VALUE) {
            CloseHandle(file);
        }
        return 0;
    }
    *interrupted = 0;
    *oggPhysicalState = CF7_OGG_PHYSICAL_NOT_OGG;
    memset(&oggScan, 0, sizeof(oggScan));
    if (file == INVALID_HANDLE_VALUE) {
        return 0;
    }
    if (BCryptOpenAlgorithmProvider(
            &algorithm,
            BCRYPT_SHA256_ALGORITHM,
            NULL,
            0u) < 0 ||
        BCryptCreateHash(
            algorithm,
            &hash,
            NULL,
            0u,
            NULL,
            0u,
            0u) < 0) {
        goto cleanup;
    }
    for (;;) {
        DWORD actual = 0u;
        if (GetTickCount64() >= deadline) {
            *interrupted = 1;
            goto cleanup;
        }
        if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
            *interrupted = 2;
            goto cleanup;
        }
        if (!ReadFile(
                file,
                buffer,
                (DWORD)sizeof(buffer),
                &actual,
                NULL)) {
            goto cleanup;
        }
        if (actual == 0u) {
            break;
        }
        if (BCryptHashData(hash, buffer, actual, 0u) < 0) {
            goto cleanup;
        }
        cf7_ogg_scan_update(&oggScan, buffer, actual);
    }
    if (GetTickCount64() >= deadline) {
        *interrupted = 1;
        goto cleanup;
    }
    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        *interrupted = 2;
        goto cleanup;
    }
    if (BCryptFinishHash(
            hash,
            rawDigest,
            (ULONG)sizeof(rawDigest),
            0u) < 0) {
        goto cleanup;
    }
    for (index = 0u; index < sizeof(rawDigest); ++index) {
        digest[index * 2u] = hex[(rawDigest[index] >> 4u) & 0x0Fu];
        digest[index * 2u + 1u] = hex[rawDigest[index] & 0x0Fu];
    }
    digest[64] = '\0';
    *oggPhysicalState = cf7_ogg_scan_finish(&oggScan);
    ok = 1;

cleanup:
    if (hash != NULL) {
        BCryptDestroyHash(hash);
    }
    if (algorithm != NULL) {
        BCryptCloseAlgorithmProvider(algorithm, 0u);
    }
    CloseHandle(file);
    return ok;
}

static uint32_t cf7_runtime_snapshot_write(
    cf7_audio_bridge_v2_runtime_snapshot* snapshot)
{
    cf7_internal_result failure;
    const wchar_t* deviceName;
    int stringsOk;
    if (!cf7_audio_bridge_support_prefix_valid(
            snapshot,
            (uint32_t)sizeof(*snapshot))) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    AcquireSRWLockShared(&g_control.snapshotLock);
    snapshot->audioStatus = g_runtime.audioStatus;
    snapshot->audioReadyGeneration = g_runtime.audioReadyGeneration;
    snapshot->deviceGeneration = g_runtime.deviceGeneration;
    snapshot->selectedBackend = g_runtime.selectedBackend;
    snapshot->sampleRate = g_runtime.sampleRate;
    snapshot->channels = g_runtime.channels;
    snapshot->sampleFormat = g_runtime.sampleFormat;
    failure = g_runtime.lastFailure;
    deviceName = g_runtime.selectedDeviceName != NULL
        ? g_runtime.selectedDeviceName
        : L"";
    stringsOk = cf7_audio_bridge_support_write_utf8(
                    &snapshot->audioSessionId,
                    g_runtime.audioSessionId) &&
        cf7_audio_bridge_support_write_utf8(
            &snapshot->selectedDeviceIdDigest,
            g_runtime.selectedDeviceIdDigest) &&
        cf7_audio_bridge_support_write_utf16(
            &snapshot->selectedDeviceName,
            deviceName);
    (void)cf7_result_from_internal(
        &snapshot->lastStructuredFailure,
        &failure,
        g_runtime.audioSessionId,
        g_runtime.audioReadyGeneration,
        g_runtime.deviceGeneration);
    ReleaseSRWLockShared(&g_control.snapshotLock);
    return stringsOk
        ? CF7_AUDIO_BRIDGE_V2_RESULT_OK
        : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
}

static uint32_t cf7_sfx_counters_write(
    cf7_audio_bridge_v2_sfx_counters* counters)
{
    int stringOk;
    if (!cf7_audio_bridge_support_prefix_valid(
            counters,
            (uint32_t)sizeof(*counters))) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    AcquireSRWLockShared(&g_control.snapshotLock);
    counters->audioReadyGeneration = g_runtime.audioReadyGeneration;
    stringOk = cf7_audio_bridge_support_write_utf8(
        &counters->audioSessionId,
        g_runtime.audioSessionId);
    ReleaseSRWLockShared(&g_control.snapshotLock);
    counters->preReadyDrops = cf7_counter_load(&g_runtime.sfxPreReadyDrops);
    counters->recoveryDrops = cf7_counter_load(&g_runtime.sfxRecoveryDrops);
    counters->staleGenerationDrops = cf7_counter_load(
        &g_runtime.sfxStaleGenerationDrops);
    counters->unknownIdCount = cf7_counter_load(&g_runtime.sfxUnknownIdCount);
    counters->throttledCount = cf7_counter_load(&g_runtime.sfxThrottledCount);
    counters->startFailureCount = cf7_counter_load(
        &g_runtime.sfxStartFailureCount);
    counters->playedCount = cf7_counter_load(&g_runtime.sfxPlayedCount);
    return stringOk
        ? CF7_AUDIO_BRIDGE_V2_RESULT_OK
        : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
}

static int cf7_session_matches(
    const cf7_audio_bridge_v2_utf8_buffer* sessionBuffer,
    uint64_t readyGeneration,
    char** parsedSession,
    uint32_t* status,
    uint64_t* deviceGeneration)
{
    int matches;
    *parsedSession = NULL;
    if (!cf7_audio_bridge_support_read_utf8(sessionBuffer, parsedSession) ||
        !cf7_uuid_v4_lowercase_valid(*parsedSession)) {
        return -1;
    }
    AcquireSRWLockShared(&g_control.snapshotLock);
    matches = strcmp(*parsedSession, g_runtime.audioSessionId) == 0 &&
        readyGeneration == g_runtime.audioReadyGeneration;
    if (status != NULL) {
        *status = g_runtime.audioStatus;
    }
    if (deviceGeneration != NULL) {
        *deviceGeneration = g_runtime.deviceGeneration;
    }
    ReleaseSRWLockShared(&g_control.snapshotLock);
    return matches;
}

static uint32_t cf7_initialize_owner(
    const cf7_audio_bridge_v2_initialize_command* command,
    cf7_audio_bridge_v2_runtime_snapshot* snapshot,
    cf7_audio_bridge_v2_result* result)
{
    wchar_t* inputBase = NULL;
    wchar_t* finalBase = NULL;
    char* session = NULL;
    DWORD windowsError = ERROR_SUCCESS;
    ma_result maResult;
    cf7_internal_result failure;
    uint32_t category;
    uint64_t previousDeviceGeneration = 0u;
    int sameAudioSession = 0;

    memset(&failure, 0, sizeof(failure));
    if (!cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command)) ||
        !cf7_audio_bridge_support_prefix_valid(
            snapshot,
            (uint32_t)sizeof(*snapshot))) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.initialize.abi_mismatch");
    }
    if (!cf7_audio_bridge_support_read_utf16(
            &command->normalizedBasePath,
            &inputBase) ||
        !cf7_audio_bridge_support_read_utf8(
            &command->audioSessionId,
            &session) ||
        !cf7_uuid_v4_lowercase_valid(session) ||
        command->audioReadyGeneration == 0u ||
        (command->executionIdentity != CF7_AUDIO_BRIDGE_V2_EXECUTION_PRODUCTION &&
         command->executionIdentity != CF7_AUDIO_BRIDGE_V2_EXECUTION_ISOLATED_TEST) ||
        command->reserved0 != 0u) {
        cf7_audio_bridge_support_free(inputBase);
        cf7_audio_bridge_support_free(session);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.initialize.invalid_command");
    }
    if (!cf7_audio_bridge_support_resolve_base(
            inputBase,
            &finalBase,
            &windowsError)) {
        cf7_audio_bridge_support_free(inputBase);
        category = windowsError == ERROR_FILE_NOT_FOUND ||
                windowsError == ERROR_PATH_NOT_FOUND
            ? CF7_AUDIO_BRIDGE_V2_RESULT_MISSING
            : CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR;
        (void)cf7_result_write(
            result,
            category,
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_PATH,
            MA_DOES_NOT_EXIST,
            (int32_t)windowsError,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            session,
            command->audioReadyGeneration,
            0u,
            "audio.initialize.base_path_invalid");
        cf7_audio_bridge_support_free(session);
        return category;
    }
    cf7_audio_bridge_support_free(inputBase);

    AcquireSRWLockShared(&g_control.snapshotLock);
    sameAudioSession = strcmp(session, g_runtime.audioSessionId) == 0;
    if (sameAudioSession) {
        previousDeviceGeneration = g_runtime.deviceGeneration;
    }
    ReleaseSRWLockShared(&g_control.snapshotLock);

    cf7_graph_uninit(0);
    if (g_runtime.decoderRegistryInitialized) {
        cf7_audio_decoder_registry_uninit(&g_runtime.decoderRegistry);
        g_runtime.decoderRegistryInitialized = 0;
    }
    free(g_runtime.finalBasePath);
    free(g_runtime.latestBgmPath);
    g_runtime.latestBgmPath = NULL;
    g_runtime.latestBgmPresent = 0;
    g_runtime.latestBgmPaused = 0;
    g_runtime.latestBgmCursorFrames = 0u;
    g_runtime.bgmDecoder = 0u;
    g_runtime.bgmContainer = 0u;
    g_runtime.bgmCodec = 0u;
    g_runtime.sfxPreReadyDrops = 0;
    g_runtime.sfxRecoveryDrops = 0;
    g_runtime.sfxStaleGenerationDrops = 0;
    g_runtime.sfxUnknownIdCount = 0;
    g_runtime.sfxThrottledCount = 0;
    g_runtime.sfxStartFailureCount = 0;
    g_runtime.sfxPlayedCount = 0;

    AcquireSRWLockExclusive(&g_control.snapshotLock);
    g_runtime.finalBasePath = finalBase;
    finalBase = NULL;
    (void)strncpy_s(
        g_runtime.audioSessionId,
        sizeof(g_runtime.audioSessionId),
        session,
        _TRUNCATE);
    g_runtime.audioReadyGeneration = command->audioReadyGeneration;
    g_runtime.deviceGeneration = sameAudioSession
        ? previousDeviceGeneration
        : 0u;
    g_runtime.audioStatus = CF7_AUDIO_BRIDGE_V2_AUDIO_INITIALIZING;
    ReleaseSRWLockExclusive(&g_control.snapshotLock);

    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        (void)cf7_runtime_snapshot_write(snapshot);
        cf7_audio_bridge_support_free(session);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.initialize.cancelled");
    }
    maResult = cf7_audio_decoder_registry_init(&g_runtime.decoderRegistry);
    if (maResult != MA_SUCCESS) {
        cf7_internal_result_set(
            &failure,
            cf7_category_from_ma(maResult, 1),
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            CF7_AUDIO_BRIDGE_V2_STAGE_DECODER_INITIALIZE,
            maResult,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.initialize.decoder_registry_failed");
        cf7_runtime_set_failure(&failure);
        cf7_runtime_set_status(CF7_AUDIO_BRIDGE_V2_AUDIO_FAILED_NO_OUTPUT);
        (void)cf7_runtime_snapshot_write(snapshot);
        cf7_audio_bridge_support_free(session);
        return cf7_result_from_internal(
            result,
            &failure,
            g_runtime.audioSessionId,
            g_runtime.audioReadyGeneration,
            g_runtime.deviceGeneration);
    }
    g_runtime.decoderRegistryInitialized = 1;
    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        (void)cf7_runtime_snapshot_write(snapshot);
        cf7_audio_bridge_support_free(session);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.initialize.cancelled");
    }
    if (!cf7_device_generation_advance() ||
        !cf7_real_graph_initialize(&failure)) {
        if (failure.category == 0u) {
            cf7_internal_result_set(
                &failure,
                CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR,
                CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
                CF7_AUDIO_BRIDGE_V2_STAGE_DEVICE_INITIALIZE,
                MA_INVALID_OPERATION,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.initialize.device_generation_overflow");
        }
        cf7_runtime_set_failure(&failure);
        cf7_runtime_set_status(CF7_AUDIO_BRIDGE_V2_AUDIO_FAILED_NO_OUTPUT);
        (void)cf7_runtime_snapshot_write(snapshot);
        cf7_audio_bridge_support_free(session);
        return cf7_result_from_internal(
            result,
            &failure,
            g_runtime.audioSessionId,
            g_runtime.audioReadyGeneration,
            g_runtime.deviceGeneration);
    }
    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        (void)cf7_runtime_snapshot_write(snapshot);
        cf7_audio_bridge_support_free(session);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.initialize.cancelled");
    }
    cf7_internal_result_set(
        &failure,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
        CF7_AUDIO_BRIDGE_V2_STAGE_DEVICE_START,
        MA_SUCCESS,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
        "audio.initialize.ready");
    cf7_runtime_set_failure(&failure);
    cf7_runtime_set_status(CF7_AUDIO_BRIDGE_V2_AUDIO_READY);
    (void)cf7_runtime_snapshot_write(snapshot);
    cf7_audio_bridge_support_free(session);
    return cf7_result_from_internal(
        result,
        &failure,
        g_runtime.audioSessionId,
        g_runtime.audioReadyGeneration,
        g_runtime.deviceGeneration);
}

static int cf7_array_input_valid(
    const cf7_audio_bridge_v2_array_buffer* array,
    uint32_t elementSize,
    uint32_t maximumCount)
{
    return cf7_audio_bridge_support_prefix_valid(
               array,
               (uint32_t)sizeof(*array)) &&
        array->elementSize == elementSize &&
        array->countElements <= array->capacityElements &&
        array->countElements <= maximumCount &&
        array->requiredElements == 0u &&
        ((array->countElements == 0u) || array->dataAddress != 0u);
}

static uint32_t cf7_rebuild_sfx_owner(
    const cf7_audio_bridge_v2_sfx_catalog_command* command,
    cf7_audio_bridge_v2_result* result)
{
    char* session = NULL;
    uint32_t status = 0u;
    int matches;
    cf7_sfx_entry* entries = NULL;
    cf7_audio_bridge_v2_sfx_catalog_item* inputItems;
    uint32_t index;
    uint32_t previous;
    ma_result maResult;
    DWORD windowsError;
    uint64_t fileSize;
    int64_t modified;
    if (!cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command)) ||
        !cf7_array_input_valid(
            &command->items,
            (uint32_t)sizeof(cf7_audio_bridge_v2_sfx_catalog_item),
            CF7_SFX_CATALOG_MAX_ITEMS)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.sfx.catalog_invalid");
    }
    matches = cf7_session_matches(
        &command->audioSessionId,
        command->audioReadyGeneration,
        &session,
        &status,
        NULL);
    if (matches <= 0) {
        cf7_audio_bridge_support_free(session);
        return cf7_result_current(
            result,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_RESULT_STALE_GENERATION
                : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_SESSION
                : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            matches == 0
                ? "audio.sfx.catalog_stale"
                : "audio.sfx.catalog_session_invalid");
    }
    cf7_audio_bridge_support_free(session);
    if (status != CF7_AUDIO_BRIDGE_V2_AUDIO_READY) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.sfx.catalog_not_ready");
    }
    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.sfx.catalog_cancelled");
    }
    if (command->items.countElements != 0u) {
        entries = (cf7_sfx_entry*)calloc(
            command->items.countElements,
            sizeof(*entries));
        if (entries == NULL) {
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR,
                CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
                CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
                MA_OUT_OF_MEMORY,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.sfx.catalog_allocation_failed");
        }
    }
    inputItems = (cf7_audio_bridge_v2_sfx_catalog_item*)(uintptr_t)
        command->items.dataAddress;
    for (index = 0u; index < command->items.countElements; ++index) {
        if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
            cf7_sfx_catalog_free_entries(
                entries,
                command->items.countElements,
                1);
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
                CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
                CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
                MA_CANCELLED,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.sfx.catalog_cancelled");
        }
        if (!cf7_audio_bridge_support_prefix_valid(
                &inputItems[index],
                (uint32_t)sizeof(inputItems[index])) ||
            !cf7_audio_bridge_support_read_utf8(
                &inputItems[index].linkageId,
                &entries[index].linkageId) ||
            !cf7_audio_bridge_support_read_utf16(
                &inputItems[index].normalizedPath,
                &entries[index].finalPath) ||
            entries[index].linkageId[0] == '\0' ||
            entries[index].finalPath[0] == L'\0') {
            cf7_sfx_catalog_free_entries(entries, command->items.countElements, 1);
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
                CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
                CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
                MA_INVALID_ARGS,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.sfx.catalog_item_invalid");
        }
        for (previous = 0u; previous < index; ++previous) {
            if (strcmp(entries[previous].linkageId, entries[index].linkageId) == 0) {
                cf7_sfx_catalog_free_entries(
                    entries,
                    command->items.countElements,
                    1);
                return cf7_result_current(
                    result,
                    CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
                    CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
                    CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
                    MA_INVALID_ARGS,
                    0,
                    CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                    "audio.sfx.catalog_duplicate_id");
            }
        }
        {
            wchar_t* resolved = NULL;
            windowsError = ERROR_SUCCESS;
            if (!cf7_resolve_audio_file(
                    entries[index].finalPath,
                    &resolved,
                    &fileSize,
                    &modified,
                    &windowsError)) {
                cf7_sfx_catalog_free_entries(
                    entries,
                    command->items.countElements,
                    1);
                return cf7_result_current(
                    result,
                    windowsError == ERROR_FILE_NOT_FOUND ||
                            windowsError == ERROR_PATH_NOT_FOUND
                        ? CF7_AUDIO_BRIDGE_V2_RESULT_MISSING
                        : CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR,
                    CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
                    CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_PATH,
                    MA_DOES_NOT_EXIST,
                    (int32_t)windowsError,
                    CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                    "audio.sfx.catalog_path_invalid");
            }
            cf7_audio_bridge_support_free(entries[index].finalPath);
            entries[index].finalPath = resolved;
        }
        maResult = cf7_sfx_entry_init_voices(&entries[index]);
        if (maResult != MA_SUCCESS) {
            cf7_sfx_catalog_free_entries(
                entries,
                command->items.countElements,
                1);
            return cf7_result_current(
                result,
                cf7_category_from_ma(maResult, 1),
                CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
                CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
                maResult,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.sfx.catalog_decode_failed");
        }
    }
    cf7_sfx_catalog_free_all();
    g_runtime.sfxCatalog = entries;
    g_runtime.sfxCatalogCount = command->items.countElements;
    return cf7_result_current(
        result,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
        CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
        MA_SUCCESS,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
        "audio.sfx.catalog_rebuilt");
}

static uint32_t cf7_bgm_owner(
    const cf7_audio_bridge_v2_bgm_command* command,
    cf7_audio_bridge_v2_result* result)
{
    char* session = NULL;
    char* requestId = NULL;
    wchar_t* path = NULL;
    wchar_t* finalPath = NULL;
    uint32_t status = 0u;
    int matches;
    uint64_t fileSize = 0u;
    int64_t modified = 0;
    DWORD windowsError = ERROR_SUCCESS;
    ma_result maResult = MA_SUCCESS;
    ma_uint64 cursorFrames = 0u;
    uint32_t slot;
    uint64_t fadeMilliseconds;

    if (!cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command)) ||
        command->wireRevision != CF7_AUDIO_BRIDGE_V2_WIRE_REVISION ||
        command->operation < CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY ||
        command->operation > CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_SET_LOOP ||
        !isfinite(command->fadeSeconds) || command->fadeSeconds < 0.0f ||
        command->fadeSeconds > 60.0f ||
        !isfinite(command->seekSeconds) || command->seekSeconds < 0.0f ||
        !cf7_finite_gain(command->volume) ||
        (command->loop != CF7_AUDIO_BRIDGE_V2_FALSE &&
         command->loop != CF7_AUDIO_BRIDGE_V2_TRUE) ||
        !cf7_audio_bridge_support_read_utf8(
            &command->requestId,
            &requestId) ||
        requestId[0] == '\0' ||
        !cf7_audio_bridge_support_read_utf16(
            &command->normalizedPath,
            &path)) {
        cf7_audio_bridge_support_free(requestId);
        cf7_audio_bridge_support_free(path);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            command != NULL ? command->operation : CF7_AUDIO_BRIDGE_V2_OPERATION_NONE,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.invalid_command");
    }
    cf7_audio_bridge_support_free(requestId);
    matches = cf7_session_matches(
        &command->audioSessionId,
        command->audioReadyGeneration,
        &session,
        &status,
        NULL);
    if (matches <= 0) {
        cf7_audio_bridge_support_free(session);
        cf7_audio_bridge_support_free(path);
        return cf7_result_current(
            result,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_RESULT_STALE_GENERATION
                : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            command->operation,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_SESSION
                : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            matches == 0
                ? "audio.bgm.stale"
                : "audio.bgm.session_invalid");
    }
    cf7_audio_bridge_support_free(session);
    if (status != CF7_AUDIO_BRIDGE_V2_AUDIO_READY) {
        cf7_audio_bridge_support_free(path);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.not_ready");
    }
    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        cf7_audio_bridge_support_free(path);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.cancelled");
    }

    if (command->operation == CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY) {
        if (path[0] == L'\0' || !cf7_resolve_audio_file(
                path,
                &finalPath,
                &fileSize,
                &modified,
                &windowsError)) {
            cf7_audio_bridge_support_free(path);
            return cf7_result_current(
                result,
                windowsError == ERROR_FILE_NOT_FOUND ||
                        windowsError == ERROR_PATH_NOT_FOUND
                    ? CF7_AUDIO_BRIDGE_V2_RESULT_MISSING
                    : CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR,
                command->operation,
                CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_PATH,
                MA_DOES_NOT_EXIST,
                (int32_t)windowsError,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.bgm.path_invalid");
        }
        cf7_audio_bridge_support_free(path);
        {
            uint32_t category = cf7_bgm_play_final(
                finalPath,
                command->loop == CF7_AUDIO_BRIDGE_V2_TRUE,
                command->volume,
                command->fadeSeconds,
                1,
                result);
            cf7_audio_bridge_support_free(finalPath);
            return category;
        }
    }
    cf7_audio_bridge_support_free(path);

    switch (command->operation) {
    case CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_STOP:
        fadeMilliseconds = (uint64_t)((double)command->fadeSeconds * 1000.0);
        for (slot = 0u; slot < 2u; ++slot) {
            if (!g_runtime.bgmInitialized[slot]) {
                continue;
            }
            maResult = fadeMilliseconds >= CF7_BGM_MIN_FADE_MS
                ? ma_sound_stop_with_fade_in_milliseconds(
                    &g_runtime.bgm[slot],
                    fadeMilliseconds)
                : ma_sound_stop(&g_runtime.bgm[slot]);
            if (maResult != MA_SUCCESS) {
                return cf7_result_current(
                    result,
                    CF7_AUDIO_BRIDGE_V2_RESULT_START_FAILED,
                    command->operation,
                    CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
                    maResult,
                    0,
                    CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                    "audio.bgm.stop_failed");
            }
        }
        free(g_runtime.latestBgmPath);
        g_runtime.latestBgmPath = NULL;
        g_runtime.latestBgmPresent = 0;
        g_runtime.latestBgmPaused = 0;
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
            MA_SUCCESS,
            0,
            fadeMilliseconds >= CF7_BGM_MIN_FADE_MS
                ? CF7_AUDIO_BRIDGE_V2_COMPLETION_ACCEPTED_DEFERRED
                : CF7_AUDIO_BRIDGE_V2_COMPLETION_STOPPED,
            fadeMilliseconds >= CF7_BGM_MIN_FADE_MS
                ? "audio.bgm.stop_deferred"
                : "audio.bgm.stopped");

    case CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PAUSE:
        for (slot = 0u; slot < 2u; ++slot) {
            if (g_runtime.bgmInitialized[slot] &&
                ma_sound_is_playing(&g_runtime.bgm[slot])) {
                maResult = ma_sound_stop(&g_runtime.bgm[slot]);
                if (maResult != MA_SUCCESS) {
                    return cf7_result_current(
                        result,
                        CF7_AUDIO_BRIDGE_V2_RESULT_START_FAILED,
                        command->operation,
                        CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
                        maResult,
                        0,
                        CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                        "audio.bgm.pause_failed");
                }
            }
        }
        g_runtime.latestBgmPaused = 1;
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
            MA_SUCCESS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_STOPPED,
            "audio.bgm.paused");

    case CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_RESUME:
        if (!g_runtime.bgmInitialized[g_runtime.bgmActive]) {
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
                command->operation,
                CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
                MA_INVALID_OPERATION,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.bgm.no_source");
        }
        maResult = ma_sound_start(&g_runtime.bgm[g_runtime.bgmActive]);
        if (maResult != MA_SUCCESS) {
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_START_FAILED,
                command->operation,
                CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
                maResult,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.bgm.resume_failed");
        }
        g_runtime.latestBgmPaused = 0;
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
            MA_SUCCESS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
            "audio.bgm.resumed");

    case CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_SEEK:
        if (!g_runtime.bgmInitialized[g_runtime.bgmActive]) {
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
                command->operation,
                CF7_AUDIO_BRIDGE_V2_STAGE_SEEK,
                MA_INVALID_OPERATION,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.bgm.no_source");
        }
        maResult = ma_sound_seek_to_second(
            &g_runtime.bgm[g_runtime.bgmActive],
            command->seekSeconds);
        if (maResult != MA_SUCCESS) {
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_SEEK_FAILED,
                command->operation,
                CF7_AUDIO_BRIDGE_V2_STAGE_SEEK,
                maResult,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.bgm.seek_failed");
        }
        if (ma_sound_get_cursor_in_pcm_frames(
                &g_runtime.bgm[g_runtime.bgmActive],
                &cursorFrames) == MA_SUCCESS) {
            g_runtime.latestBgmCursorFrames = cursorFrames;
        } else {
            g_runtime.latestBgmCursorFrames = 0u;
        }
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_SEEK,
            MA_SUCCESS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
            "audio.bgm.seeked");

    case CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_SET_LOOP:
        if (!g_runtime.bgmInitialized[g_runtime.bgmActive]) {
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
                command->operation,
                CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
                MA_INVALID_OPERATION,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.bgm.no_source");
        }
        ma_sound_set_looping(
            &g_runtime.bgm[g_runtime.bgmActive],
            command->loop == CF7_AUDIO_BRIDGE_V2_TRUE ? MA_TRUE : MA_FALSE);
        g_runtime.latestBgmLoop = command->loop == CF7_AUDIO_BRIDGE_V2_TRUE;
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_SOURCE_INITIALIZE,
            MA_SUCCESS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
            "audio.bgm.loop_updated");
    default:
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.operation_invalid");
    }
}

static uint32_t cf7_sfx_batch_owner(
    const cf7_audio_bridge_v2_sfx_batch_command* command,
    cf7_audio_bridge_v2_sfx_counters* counters,
    cf7_audio_bridge_v2_result* result,
    uint64_t capturedDeviceGeneration)
{
    char* session = NULL;
    uint32_t status = 0u;
    uint64_t currentDevice = 0u;
    int matches;
    cf7_audio_bridge_v2_sfx_play_item* items;
    uint32_t index;
    if (!cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command)) ||
        command->wireRevision != CF7_AUDIO_BRIDGE_V2_WIRE_REVISION ||
        command->batchSequence == 0u ||
        !cf7_array_input_valid(
            &command->linkageIds,
            (uint32_t)sizeof(cf7_audio_bridge_v2_sfx_play_item),
            UINT32_MAX)) {
        (void)cf7_sfx_counters_write(counters);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.sfx.batch_invalid");
    }
    matches = cf7_session_matches(
        &command->audioSessionId,
        command->audioReadyGeneration,
        &session,
        &status,
        &currentDevice);
    if (matches <= 0) {
        if (matches == 0) {
            (void)cf7_counter_add(
                &g_runtime.sfxStaleGenerationDrops,
                command->linkageIds.countElements);
        }
        cf7_audio_bridge_support_free(session);
        (void)cf7_sfx_counters_write(counters);
        return cf7_result_current(
            result,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_RESULT_STALE_GENERATION
                : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_SESSION
                : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            matches == 0
                ? "audio.sfx.batch_stale"
                : "audio.sfx.batch_session_invalid");
    }
    cf7_audio_bridge_support_free(session);
    if (status != CF7_AUDIO_BRIDGE_V2_AUDIO_READY ||
        capturedDeviceGeneration != currentDevice) {
        (void)cf7_counter_add(
            status == CF7_AUDIO_BRIDGE_V2_AUDIO_RECOVERING ||
                    capturedDeviceGeneration != currentDevice
                ? &g_runtime.sfxRecoveryDrops
                : &g_runtime.sfxPreReadyDrops,
            command->linkageIds.countElements);
        (void)cf7_sfx_counters_write(counters);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.sfx.batch_dropped_not_ready");
    }
    if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        (void)cf7_counter_add(
            &g_runtime.sfxRecoveryDrops,
            command->linkageIds.countElements);
        (void)cf7_sfx_counters_write(counters);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.sfx.batch_cancelled");
    }

    items = (cf7_audio_bridge_v2_sfx_play_item*)(uintptr_t)
        command->linkageIds.dataAddress;
    for (index = 0u; index < command->linkageIds.countElements; ++index) {
        char* linkage = NULL;
        cf7_sfx_entry* entry;
        ULONGLONG now;
        uint32_t attempts;
        int played = 0;
        if (WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
            (void)cf7_counter_add(
                &g_runtime.sfxRecoveryDrops,
                command->linkageIds.countElements - index);
            (void)cf7_sfx_counters_write(counters);
            return cf7_result_current(
                result,
                CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
                CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
                CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
                MA_CANCELLED,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.sfx.batch_cancelled");
        }
        if (!cf7_audio_bridge_support_prefix_valid(
                &items[index],
                (uint32_t)sizeof(items[index])) ||
            items[index].reserved0 != 0u ||
            !cf7_finite_gain(items[index].volume) ||
            !cf7_audio_bridge_support_read_utf8(
                &items[index].linkageId,
                &linkage) ||
            linkage[0] == '\0') {
            cf7_audio_bridge_support_free(linkage);
            (void)cf7_counter_add(&g_runtime.sfxUnknownIdCount, 1u);
            continue;
        }
        entry = cf7_sfx_find(linkage);
        cf7_audio_bridge_support_free(linkage);
        if (entry == NULL) {
            (void)cf7_counter_add(&g_runtime.sfxUnknownIdCount, 1u);
            continue;
        }
        now = GetTickCount64();
        if (entry->lastPlayMilliseconds != 0u &&
            now - entry->lastPlayMilliseconds < CF7_SFX_THROTTLE_MS) {
            (void)cf7_counter_add(&g_runtime.sfxThrottledCount, 1u);
            continue;
        }
        for (attempts = 0u; attempts < CF7_SFX_VOICES; ++attempts) {
            uint32_t voice = entry->nextVoice;
            ma_result seekResult;
            ma_result startResult;
            entry->nextVoice = (voice + 1u) % CF7_SFX_VOICES;
            if (!entry->voiceInitialized[voice]) {
                continue;
            }
            seekResult = ma_sound_seek_to_pcm_frame(&entry->voices[voice], 0u);
            if (seekResult != MA_SUCCESS) {
                continue;
            }
            ma_sound_set_volume(&entry->voices[voice], items[index].volume);
            startResult = ma_sound_start(&entry->voices[voice]);
            if (startResult == MA_SUCCESS) {
                entry->lastPlayMilliseconds = now;
                (void)cf7_counter_add(&g_runtime.sfxPlayedCount, 1u);
                played = 1;
                break;
            }
        }
        if (!played) {
            (void)cf7_counter_add(&g_runtime.sfxStartFailureCount, 1u);
        }
    }
    (void)cf7_sfx_counters_write(counters);
    return cf7_result_current(
        result,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
        CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
        MA_SUCCESS,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
        "audio.sfx.batch_processed");
}

static uint32_t cf7_set_gain_owner(
    const cf7_audio_bridge_v2_gain_command* command,
    cf7_audio_bridge_v2_result* result)
{
    char* session = NULL;
    uint32_t status = 0u;
    int matches;
    ma_result maResult = MA_SUCCESS;
    if (!cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command)) ||
        !cf7_finite_gain(command->gain) ||
        (command->operation != CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_SET_GAIN &&
         command->operation != CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_SET_GAIN &&
         command->operation != CF7_AUDIO_BRIDGE_V2_OPERATION_SET_MASTER_GAIN)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            command != NULL ? command->operation : CF7_AUDIO_BRIDGE_V2_OPERATION_NONE,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.gain.invalid_command");
    }
    matches = cf7_session_matches(
        &command->audioSessionId,
        command->audioReadyGeneration,
        &session,
        &status,
        NULL);
    if (matches <= 0) {
        cf7_audio_bridge_support_free(session);
        return cf7_result_current(
            result,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_RESULT_STALE_GENERATION
                : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            command->operation,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_SESSION
                : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            matches == 0 ? "audio.gain.stale" : "audio.gain.session_invalid");
    }
    cf7_audio_bridge_support_free(session);
    if (status != CF7_AUDIO_BRIDGE_V2_AUDIO_READY) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.gain.not_ready");
    }
    if (command->operation == CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_SET_GAIN) {
        ma_sound_group_set_volume(&g_runtime.bgmGroup, command->gain);
        g_runtime.bgmGain = command->gain;
        g_runtime.latestBgmVolume = command->gain;
    } else if (command->operation == CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_SET_GAIN) {
        ma_sound_group_set_volume(&g_runtime.sfxGroup, command->gain);
        g_runtime.sfxGain = command->gain;
    } else {
        maResult = ma_engine_set_volume(&g_runtime.engine, command->gain);
        if (maResult == MA_SUCCESS) {
            g_runtime.masterGain = command->gain;
        }
    }
    if (maResult != MA_SUCCESS) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR,
            command->operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
            maResult,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.gain.native_failed");
    }
    return cf7_result_current(
        result,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        command->operation,
        CF7_AUDIO_BRIDGE_V2_STAGE_NATIVE_START,
        MA_SUCCESS,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
        "audio.gain.updated");
}

static uint32_t cf7_query_bgm_owner(
    cf7_audio_bridge_v2_source_snapshot* snapshot,
    cf7_audio_bridge_v2_result* result)
{
    ma_uint64 cursor = 0u;
    ma_uint64 length = 0u;
    ma_result cursorResult = MA_SUCCESS;
    ma_result lengthResult = MA_SUCCESS;
    int stringOk;
    uint32_t status;
    if (!cf7_audio_bridge_support_prefix_valid(
            snapshot,
            (uint32_t)sizeof(*snapshot))) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.query_invalid");
    }
    AcquireSRWLockShared(&g_control.snapshotLock);
    status = g_runtime.audioStatus;
    snapshot->audioReadyGeneration = g_runtime.audioReadyGeneration;
    snapshot->deviceGeneration = g_runtime.deviceGeneration;
    stringOk = cf7_audio_bridge_support_write_utf8(
        &snapshot->audioSessionId,
        g_runtime.audioSessionId);
    ReleaseSRWLockShared(&g_control.snapshotLock);
    snapshot->decoder = g_runtime.bgmDecoder;
    snapshot->container = g_runtime.bgmContainer;
    snapshot->codec = g_runtime.bgmCodec;
    snapshot->sourceGroupMasterGain = g_runtime.bgmGain;
    snapshot->playing = CF7_AUDIO_BRIDGE_V2_FALSE;
    if (g_runtime.bgmInitialized[g_runtime.bgmActive]) {
        cursorResult = ma_sound_get_cursor_in_pcm_frames(
            &g_runtime.bgm[g_runtime.bgmActive],
            &cursor);
        lengthResult = ma_sound_get_length_in_pcm_frames(
            &g_runtime.bgm[g_runtime.bgmActive],
            &length);
        snapshot->playing = ma_sound_is_playing(
            &g_runtime.bgm[g_runtime.bgmActive])
            ? CF7_AUDIO_BRIDGE_V2_TRUE
            : CF7_AUDIO_BRIDGE_V2_FALSE;
    }
    snapshot->cursorFrames = cursorResult == MA_SUCCESS
        ? cursor
        : (g_runtime.latestBgmPresent
            ? g_runtime.latestBgmCursorFrames
            : 0u);
    snapshot->lengthFrames = lengthResult == MA_SUCCESS ? length : 0u;
    (void)cf7_result_from_internal(
        &snapshot->startResult,
        &g_runtime.bgmStartResult,
        g_runtime.audioSessionId,
        g_runtime.audioReadyGeneration,
        g_runtime.deviceGeneration);
    if (!stringOk) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_CAPACITY,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.query_capacity");
    }
    if (status != CF7_AUDIO_BRIDGE_V2_AUDIO_READY) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.bgm.query_not_ready");
    }
    return cf7_result_current(
        result,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
        CF7_AUDIO_BRIDGE_V2_STAGE_NONE,
        MA_SUCCESS,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE,
        "audio.bgm.query_ok");
}

static uint32_t cf7_probe_runtime_owner(
    const cf7_audio_bridge_v2_runtime_probe_command* command,
    cf7_audio_bridge_v2_probe_result* probeResult,
    cf7_audio_bridge_v2_result* result)
{
    wchar_t* inputPath = NULL;
    wchar_t* firstPath = NULL;
    wchar_t* secondPath = NULL;
    char* expectedFirstHash = NULL;
    char* expectedCapability = NULL;
    char capability[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    char actualFirstHash[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    cf7_audio_bridge_support_sniff sniff;
    uint64_t firstSize = 0u;
    uint64_t secondSize = 0u;
    int64_t firstModified = 0;
    int64_t secondModified = 0;
    DWORD windowsError = ERROR_SUCCESS;
    ULONGLONG started = GetTickCount64();
    ULONGLONG elapsed;
    uint32_t status;
    uint32_t remainingWall;
    ma_result maResult;
    int eofReached;
    int inconclusive;
    int inputBoundInconclusive;
    uint32_t category;

    if (!cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command)) ||
        !cf7_audio_bridge_support_prefix_valid(
            probeResult,
            (uint32_t)sizeof(*probeResult))) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.abi_mismatch");
    }
    cf7_probe_result_zero_metrics(probeResult);
    if (command->probeContractRevision !=
            CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION ||
        command->maxWallMs != CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_WALL_MS ||
        command->maxDecodedFrames !=
            CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES ||
        command->maxInputBytes !=
            CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES ||
        command->maxFileBytes !=
            CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_FILE_BYTES ||
        command->stableObservationCount !=
            CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_OBSERVATIONS ||
        command->stableIntervalMs !=
            CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS ||
        !cf7_audio_bridge_support_read_utf16(
            &command->normalizedPath,
            &inputPath) ||
        !cf7_audio_bridge_support_read_utf8(
            &command->first64kSha256,
            &expectedFirstHash) ||
        !cf7_audio_bridge_support_read_utf8(
            &command->capabilityDigestSha256,
            &expectedCapability) ||
        inputPath[0] == L'\0' ||
        !cf7_sha256_hex_valid(expectedFirstHash) ||
        !cf7_sha256_hex_valid(expectedCapability) ||
        !cf7_capability_digest(capability) ||
        strcmp(expectedCapability, capability) != 0) {
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(expectedFirstHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            MA_INVALID_ARGS,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.invalid_contract");
    }
    AcquireSRWLockShared(&g_control.snapshotLock);
    status = g_runtime.audioStatus;
    ReleaseSRWLockShared(&g_control.snapshotLock);
    if (status != CF7_AUDIO_BRIDGE_V2_AUDIO_READY ||
        !g_runtime.decoderRegistryInitialized) {
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(expectedFirstHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.not_ready");
    }
    if (!cf7_resolve_audio_file(
            inputPath,
            &firstPath,
            &firstSize,
            &firstModified,
            &windowsError)) {
        category = windowsError == ERROR_FILE_NOT_FOUND ||
                windowsError == ERROR_PATH_NOT_FOUND
            ? CF7_AUDIO_BRIDGE_V2_RESULT_MISSING
            : CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR;
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(expectedFirstHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            category,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_PATH,
            MA_DOES_NOT_EXIST,
            CF7_AUDIO_BRIDGE_V2_PROBE_INCOMPATIBLE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.path_invalid");
    }
    if (firstSize != command->fileSizeBytes ||
        firstModified != command->modifiedTimeUnixMilliseconds ||
        firstSize > command->maxFileBytes) {
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(firstPath);
        cf7_audio_bridge_support_free(expectedFirstHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_THROTTLED,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            MA_BUSY,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.unstable_input");
    }
    memset(&sniff, 0, sizeof(sniff));
    if (!cf7_audio_bridge_support_sniff_file(
            firstPath,
            &sniff,
            actualFirstHash,
            &windowsError)) {
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(firstPath);
        cf7_audio_bridge_support_free(expectedFirstHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_THROTTLED,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            MA_BUSY,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.content_changed");
    }
    if (!cf7_resolve_audio_file(
            inputPath,
            &secondPath,
            &secondSize,
            &secondModified,
            &windowsError) ||
        firstSize != secondSize || firstModified != secondModified ||
        _wcsicmp(firstPath, secondPath) != 0) {
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(firstPath);
        cf7_audio_bridge_support_free(secondPath);
        cf7_audio_bridge_support_free(expectedFirstHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_THROTTLED,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            MA_BUSY,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.unstable_input");
    }
    if (strcmp(expectedFirstHash, actualFirstHash) != 0) {
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(firstPath);
        cf7_audio_bridge_support_free(secondPath);
        cf7_audio_bridge_support_free(expectedFirstHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_THROTTLED,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            MA_BUSY,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.content_changed");
    }
    cf7_audio_bridge_support_free(inputPath);
    cf7_audio_bridge_support_free(firstPath);
    cf7_audio_bridge_support_free(expectedFirstHash);
    cf7_audio_bridge_support_free(expectedCapability);
    if (sniff.decoder == 0u || sniff.container == 0u || sniff.codec == 0u) {
        cf7_audio_bridge_support_free(secondPath);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_UNSUPPORTED_CONTAINER,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            MA_FORMAT_NOT_SUPPORTED,
            CF7_AUDIO_BRIDGE_V2_PROBE_INCOMPATIBLE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.unsupported_content");
    }
    elapsed = GetTickCount64() - started;
    if (elapsed >= command->maxWallMs) {
        cf7_audio_bridge_support_free(secondPath);
        probeResult->elapsedMs = command->maxWallMs;
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE,
            MA_TIMEOUT,
            CF7_AUDIO_BRIDGE_V2_PROBE_INCONCLUSIVE_TIMEOUT_NOT_UNSUPPORTED,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE,
            "audio.probe.runtime.inconclusive_timeout");
    }
    remainingWall = command->maxWallMs - (uint32_t)elapsed;
    maResult = cf7_probe_decode(
        secondPath,
        command->maxDecodedFrames,
        command->maxInputBytes,
        remainingWall,
        sniff.decoder,
        0,
        probeResult,
        &eofReached,
        &inconclusive,
        &inputBoundInconclusive);
    cf7_audio_bridge_support_free(secondPath);
    probeResult->elapsedMs = (uint32_t)(GetTickCount64() - started);
    if (!inconclusive && probeResult->elapsedMs >= command->maxWallMs) {
        inconclusive = 1;
        maResult = MA_TIMEOUT;
    } else if (!inconclusive &&
        WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        inconclusive = 1;
        maResult = MA_CANCELLED;
    }
    if (inconclusive) {
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            maResult == MA_CANCELLED && !inputBoundInconclusive
                ? CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY
                : CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE,
            maResult,
            maResult == MA_CANCELLED && !inputBoundInconclusive
                ? CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE
                : CF7_AUDIO_BRIDGE_V2_PROBE_INCONCLUSIVE_TIMEOUT_NOT_UNSUPPORTED,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            maResult == MA_CANCELLED && !inputBoundInconclusive
                ? CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED
                : CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE,
            inputBoundInconclusive
                ? "audio.probe.runtime.input_bound_exceeded"
                : maResult == MA_CANCELLED
                ? "audio.owner.cancelled"
                : "audio.probe.runtime.inconclusive_timeout");
    }
    if (maResult != MA_SUCCESS || probeResult->frames == 0u) {
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            maResult == MA_SUCCESS
                ? CF7_AUDIO_BRIDGE_V2_RESULT_MALFORMED
                : cf7_category_from_ma(maResult, 1),
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE,
            maResult,
            CF7_AUDIO_BRIDGE_V2_PROBE_INCOMPATIBLE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.runtime.decode_failed");
    }
    return cf7_probe_finish(
        probeResult,
        result,
        CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE,
        MA_SUCCESS,
        probeResult->peak > CF7_SILENCE_THRESHOLD
            ? CF7_AUDIO_BRIDGE_V2_PROBE_COMPATIBLE_SIGNAL_PRESENT
            : CF7_AUDIO_BRIDGE_V2_PROBE_COMPATIBLE_SIGNAL_UNKNOWN,
        CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
        probeResult->peak > CF7_SILENCE_THRESHOLD
            ? "audio.probe.runtime.compatible_signal"
            : "audio.probe.runtime.compatible_signal_unknown");
}

static uint32_t cf7_probe_offline_owner(
    const cf7_audio_bridge_v2_offline_probe_command* command,
    cf7_audio_bridge_v2_probe_result* probeResult,
    cf7_audio_bridge_v2_result* result)
{
    wchar_t* inputPath = NULL;
    wchar_t* finalPath = NULL;
    char* expectedFullHash = NULL;
    char* expectedCapability = NULL;
    char capability[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    char actualFullHash[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    uint64_t fileSize = 0u;
    int64_t modified = 0;
    DWORD windowsError = ERROR_SUCCESS;
    uint32_t status;
    ULONGLONG started = GetTickCount64();
    ULONGLONG elapsed;
    uint32_t remainingWall;
    ma_result maResult;
    int eofReached;
    int inconclusive;
    int inputBoundInconclusive;
    int hashOk = 0;
    int hashInterrupted = 0;
    cf7_ogg_physical_state oggPhysicalState = CF7_OGG_PHYSICAL_NOT_OGG;
    uint32_t category;

    if (!cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command)) ||
        !cf7_audio_bridge_support_prefix_valid(
            probeResult,
            (uint32_t)sizeof(*probeResult))) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.offline.abi_mismatch");
    }
    cf7_probe_result_zero_metrics(probeResult);
    if (command->probeContractRevision !=
            CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION ||
        command->maxWallMs != CF7_AUDIO_BRIDGE_V2_OFFLINE_PROBE_MAX_WALL_MS ||
        !cf7_audio_bridge_support_read_utf16(
            &command->normalizedPath,
            &inputPath) ||
        !cf7_audio_bridge_support_read_utf8(
            &command->fullSha256,
            &expectedFullHash) ||
        !cf7_audio_bridge_support_read_utf8(
            &command->capabilityDigestSha256,
            &expectedCapability) ||
        inputPath[0] == L'\0' ||
        !cf7_sha256_hex_valid(expectedFullHash) ||
        !cf7_sha256_hex_valid(expectedCapability) ||
        !cf7_capability_digest(capability) ||
        strcmp(expectedCapability, capability) != 0) {
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(expectedFullHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            MA_INVALID_ARGS,
            CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.offline.invalid_contract");
    }
    AcquireSRWLockShared(&g_control.snapshotLock);
    status = g_runtime.audioStatus;
    ReleaseSRWLockShared(&g_control.snapshotLock);
    if (status != CF7_AUDIO_BRIDGE_V2_AUDIO_READY ||
        !g_runtime.decoderRegistryInitialized) {
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(expectedFullHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.offline.not_ready");
    }
    if (!cf7_resolve_audio_file(
            inputPath,
            &finalPath,
            &fileSize,
            &modified,
            &windowsError)) {
        category = windowsError == ERROR_FILE_NOT_FOUND ||
                windowsError == ERROR_PATH_NOT_FOUND
            ? CF7_AUDIO_BRIDGE_V2_RESULT_MISSING
            : CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR;
        cf7_audio_bridge_support_free(inputPath);
        cf7_audio_bridge_support_free(expectedFullHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            category,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_PATH,
            MA_DOES_NOT_EXIST,
            CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.offline.path_invalid");
    }
    cf7_audio_bridge_support_free(inputPath);
    hashOk = cf7_file_full_sha256(
        finalPath,
        started + command->maxWallMs,
        actualFullHash,
        &hashInterrupted,
        &oggPhysicalState);
    if (!hashOk && hashInterrupted) {
        cf7_audio_bridge_support_free(finalPath);
        cf7_audio_bridge_support_free(expectedFullHash);
        cf7_audio_bridge_support_free(expectedCapability);
        probeResult->elapsedMs = (uint32_t)(GetTickCount64() - started);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            hashInterrupted == 2
                ? CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY
                : CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            hashInterrupted == 2 ? MA_CANCELLED : MA_TIMEOUT,
            hashInterrupted == 2
                ? CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE
                : CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED_TIMEOUT,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            hashInterrupted == 2
                ? "audio.owner.cancelled"
                : "audio.probe.offline.hash_timeout");
    }
    if (!hashOk ||
        strcmp(expectedFullHash, actualFullHash) != 0) {
        cf7_audio_bridge_support_free(finalPath);
        cf7_audio_bridge_support_free(expectedFullHash);
        cf7_audio_bridge_support_free(expectedCapability);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_IO_ERROR,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            MA_INVALID_DATA,
            CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.offline.hash_or_size_mismatch");
    }
    cf7_audio_bridge_support_free(expectedFullHash);
    cf7_audio_bridge_support_free(expectedCapability);
    if (oggPhysicalState == CF7_OGG_PHYSICAL_TRUNCATED ||
        oggPhysicalState == CF7_OGG_PHYSICAL_MALFORMED) {
        cf7_audio_bridge_support_free(finalPath);
        probeResult->elapsedMs = (uint32_t)(GetTickCount64() - started);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            oggPhysicalState == CF7_OGG_PHYSICAL_TRUNCATED
                ? CF7_AUDIO_BRIDGE_V2_RESULT_TRUNCATED
                : CF7_AUDIO_BRIDGE_V2_RESULT_MALFORMED,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_INPUT,
            oggPhysicalState == CF7_OGG_PHYSICAL_TRUNCATED
                ? MA_AT_END
                : MA_INVALID_FILE,
            CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            oggPhysicalState == CF7_OGG_PHYSICAL_TRUNCATED
                ? "audio.probe.offline.truncated_ogg"
                : "audio.probe.offline.malformed_ogg");
    }
    elapsed = GetTickCount64() - started;
    if (elapsed >= command->maxWallMs) {
        cf7_audio_bridge_support_free(finalPath);
        probeResult->elapsedMs = command->maxWallMs;
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE,
            MA_TIMEOUT,
            CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED_TIMEOUT,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.offline.timeout");
    }
    remainingWall = command->maxWallMs - (uint32_t)elapsed;
    maResult = cf7_probe_decode(
        finalPath,
        UINT64_MAX,
        0u,
        remainingWall,
        0u,
        1,
        probeResult,
        &eofReached,
        &inconclusive,
        &inputBoundInconclusive);
    cf7_audio_bridge_support_free(finalPath);
    probeResult->elapsedMs = (uint32_t)(GetTickCount64() - started);
    if (!inconclusive && probeResult->elapsedMs >= command->maxWallMs) {
        inconclusive = 1;
        maResult = MA_TIMEOUT;
    } else if (!inconclusive &&
        WaitForSingleObject(g_control.cancelEvent, 0u) == WAIT_OBJECT_0) {
        inconclusive = 1;
        maResult = MA_CANCELLED;
    }
    if (inconclusive) {
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            maResult == MA_CANCELLED
                ? CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY
                : CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE,
            maResult,
            maResult == MA_CANCELLED
                ? CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE
                : CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED_TIMEOUT,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            maResult == MA_CANCELLED
                ? "audio.owner.cancelled"
                : "audio.probe.offline.timeout");
    }
    if (maResult != MA_SUCCESS || !eofReached || probeResult->frames == 0u ||
        probeResult->nonFiniteCount != 0u) {
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            maResult == MA_SUCCESS
                ? CF7_AUDIO_BRIDGE_V2_RESULT_MALFORMED
                : cf7_category_from_ma(maResult, 1),
            CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE,
            maResult,
            CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_FAILED,
            eofReached
                ? CF7_AUDIO_BRIDGE_V2_EOF_REACHED
                : CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.probe.offline.qualification_failed");
    }
    return cf7_probe_finish(
        probeResult,
        result,
        CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_STAGE_PROBE_DECODE,
        MA_SUCCESS,
        CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_PASSED,
        CF7_AUDIO_BRIDGE_V2_EOF_REACHED,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED,
        probeResult->peak > CF7_SILENCE_THRESHOLD
            ? "audio.probe.offline.passed_signal"
            : "audio.probe.offline.passed_silent");
}

static int cf7_output_utf8_valid(
    const cf7_audio_bridge_v2_utf8_buffer* buffer,
    uint32_t minimumCapacity)
{
    return cf7_audio_bridge_support_prefix_valid(
               buffer,
               (uint32_t)sizeof(*buffer)) &&
        buffer->flags == CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY &&
        buffer->dataAddress != 0u &&
        buffer->capacityBytes >= minimumCapacity;
}

static int cf7_output_utf16_valid(
    const cf7_audio_bridge_v2_utf16_buffer* buffer,
    uint32_t minimumCapacity)
{
    return cf7_audio_bridge_support_prefix_valid(
               buffer,
               (uint32_t)sizeof(*buffer)) &&
        buffer->flags == CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY &&
        buffer->dataAddress != 0u &&
        buffer->capacityCodeUnits >= minimumCapacity;
}

static int cf7_result_output_valid(const cf7_audio_bridge_v2_result* result)
{
    return cf7_audio_bridge_support_prefix_valid(
               result,
               (uint32_t)sizeof(*result)) &&
        cf7_output_utf8_valid(
            &result->audioSessionId,
            CF7_AUDIO_BRIDGE_V2_UUID_V4_TEXT_CAPACITY) &&
        cf7_output_utf8_valid(&result->messageKey, 96u);
}

static int cf7_runtime_output_valid(
    const cf7_audio_bridge_v2_runtime_snapshot* snapshot)
{
    return cf7_audio_bridge_support_prefix_valid(
               snapshot,
               (uint32_t)sizeof(*snapshot)) &&
        cf7_output_utf8_valid(
            &snapshot->audioSessionId,
            CF7_AUDIO_BRIDGE_V2_UUID_V4_TEXT_CAPACITY) &&
        cf7_output_utf8_valid(
            &snapshot->selectedDeviceIdDigest,
            CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY) &&
        cf7_output_utf16_valid(&snapshot->selectedDeviceName, 256u) &&
        cf7_result_output_valid(&snapshot->lastStructuredFailure);
}

static int cf7_counters_output_valid(
    const cf7_audio_bridge_v2_sfx_counters* counters)
{
    return cf7_audio_bridge_support_prefix_valid(
               counters,
               (uint32_t)sizeof(*counters)) &&
        cf7_output_utf8_valid(
            &counters->audioSessionId,
            CF7_AUDIO_BRIDGE_V2_UUID_V4_TEXT_CAPACITY);
}

static int cf7_source_output_valid(
    const cf7_audio_bridge_v2_source_snapshot* snapshot)
{
    return cf7_audio_bridge_support_prefix_valid(
               snapshot,
               (uint32_t)sizeof(*snapshot)) &&
        cf7_output_utf8_valid(
            &snapshot->audioSessionId,
            CF7_AUDIO_BRIDGE_V2_UUID_V4_TEXT_CAPACITY) &&
        cf7_result_output_valid(&snapshot->startResult);
}

static int cf7_probe_output_valid(
    const cf7_audio_bridge_v2_probe_result* probeResult)
{
    return cf7_audio_bridge_support_prefix_valid(
               probeResult,
               (uint32_t)sizeof(*probeResult)) &&
        cf7_result_output_valid(&probeResult->structuredResult);
}

static uint32_t cf7_shutdown_owner(
    const cf7_audio_bridge_v2_shutdown_command* command,
    cf7_audio_bridge_v2_result* result)
{
    cf7_internal_result shutdownResult;
    (void)command;

    cf7_graph_uninit(0);
    if (g_runtime.decoderRegistryInitialized) {
        cf7_audio_decoder_registry_uninit(&g_runtime.decoderRegistry);
        g_runtime.decoderRegistryInitialized = 0;
    }
    free(g_runtime.finalBasePath);
    g_runtime.finalBasePath = NULL;
    free(g_runtime.latestBgmPath);
    g_runtime.latestBgmPath = NULL;
    g_runtime.latestBgmPresent = 0;
    cf7_internal_result_set(
        &shutdownResult,
        CF7_AUDIO_BRIDGE_V2_RESULT_OK,
        CF7_AUDIO_BRIDGE_V2_OPERATION_SHUTDOWN,
        CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
        MA_SUCCESS,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_STOPPED,
        "audio.shutdown.complete");
    cf7_runtime_set_failure(&shutdownResult);
    cf7_runtime_set_status(CF7_AUDIO_BRIDGE_V2_AUDIO_SHUTDOWN);
    g_control.ownerExitRequested = 1;
    return cf7_result_from_internal(
        result,
        &shutdownResult,
        g_runtime.audioSessionId,
        g_runtime.audioReadyGeneration,
        g_runtime.deviceGeneration);
}

static uint32_t cf7_owner_job_operation(const cf7_owner_job* job)
{
    if (job->kind == CF7_JOB_BGM &&
        cf7_audio_bridge_support_prefix_valid(
            job->command,
            (uint32_t)sizeof(cf7_audio_bridge_v2_bgm_command))) {
        return ((const cf7_audio_bridge_v2_bgm_command*)job->command)->operation;
    }
    if (job->kind == CF7_JOB_SET_GAIN &&
        cf7_audio_bridge_support_prefix_valid(
            job->command,
            (uint32_t)sizeof(cf7_audio_bridge_v2_gain_command))) {
        return ((const cf7_audio_bridge_v2_gain_command*)job->command)->operation;
    }
    switch (job->kind) {
    case CF7_JOB_INITIALIZE:
        return CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE;
    case CF7_JOB_REBUILD_SFX:
        return CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG;
    case CF7_JOB_SFX_BATCH:
        return CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH;
    case CF7_JOB_QUERY_BGM:
        return CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME;
    case CF7_JOB_PROBE_RUNTIME:
        return CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE;
    case CF7_JOB_PROBE_OFFLINE:
        return CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE;
    case CF7_JOB_SHUTDOWN:
        return CF7_AUDIO_BRIDGE_V2_OPERATION_SHUTDOWN;
    default:
        return CF7_AUDIO_BRIDGE_V2_OPERATION_NONE;
    }
}

static void cf7_cancel_owner_job(cf7_owner_job* job)
{
    uint32_t operation = cf7_owner_job_operation(job);
    if (job->kind == CF7_JOB_INITIALIZE && job->output != NULL) {
        (void)cf7_runtime_snapshot_write(
            (cf7_audio_bridge_v2_runtime_snapshot*)job->output);
    } else if (job->kind == CF7_JOB_SFX_BATCH && job->output != NULL) {
        (void)cf7_sfx_counters_write(
            (cf7_audio_bridge_v2_sfx_counters*)job->output);
    } else if ((job->kind == CF7_JOB_PROBE_RUNTIME ||
                job->kind == CF7_JOB_PROBE_OFFLINE) &&
        job->output != NULL) {
        cf7_audio_bridge_v2_probe_result* probeResult =
            (cf7_audio_bridge_v2_probe_result*)job->output;
        cf7_probe_result_zero_metrics(probeResult);
        (void)cf7_probe_finish(
            probeResult,
            job->result,
            operation,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_CANCELLED,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            job->kind == CF7_JOB_PROBE_RUNTIME
                ? CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED
                : CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.cancelled");
        return;
    }
    (void)cf7_result_current(
        job->result,
        CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
        operation,
        CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
        MA_CANCELLED,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
        "audio.owner.cancelled");
}

static void cf7_process_owner_job(cf7_owner_job* job)
{
    switch (job->kind) {
    case CF7_JOB_INITIALIZE:
        (void)cf7_initialize_owner(
            (const cf7_audio_bridge_v2_initialize_command*)job->command,
            (cf7_audio_bridge_v2_runtime_snapshot*)job->output,
            job->result);
        break;
    case CF7_JOB_BGM:
        (void)cf7_bgm_owner(
            (const cf7_audio_bridge_v2_bgm_command*)job->command,
            job->result);
        break;
    case CF7_JOB_REBUILD_SFX:
        (void)cf7_rebuild_sfx_owner(
            (const cf7_audio_bridge_v2_sfx_catalog_command*)job->command,
            job->result);
        break;
    case CF7_JOB_SFX_BATCH:
        (void)cf7_sfx_batch_owner(
            (const cf7_audio_bridge_v2_sfx_batch_command*)job->command,
            (cf7_audio_bridge_v2_sfx_counters*)job->output,
            job->result,
            job->capturedDeviceGeneration);
        break;
    case CF7_JOB_SET_GAIN:
        (void)cf7_set_gain_owner(
            (const cf7_audio_bridge_v2_gain_command*)job->command,
            job->result);
        break;
    case CF7_JOB_QUERY_BGM:
        (void)cf7_query_bgm_owner(
            (cf7_audio_bridge_v2_source_snapshot*)job->output,
            job->result);
        break;
    case CF7_JOB_PROBE_RUNTIME:
        (void)cf7_probe_runtime_owner(
            (const cf7_audio_bridge_v2_runtime_probe_command*)job->command,
            (cf7_audio_bridge_v2_probe_result*)job->output,
            job->result);
        break;
    case CF7_JOB_PROBE_OFFLINE:
        (void)cf7_probe_offline_owner(
            (const cf7_audio_bridge_v2_offline_probe_command*)job->command,
            (cf7_audio_bridge_v2_probe_result*)job->output,
            job->result);
        break;
    case CF7_JOB_SHUTDOWN:
        (void)cf7_shutdown_owner(
            (const cf7_audio_bridge_v2_shutdown_command*)job->command,
            job->result);
        break;
    default:
        (void)cf7_result_current(
            job->result,
            CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR,
            CF7_AUDIO_BRIDGE_V2_OPERATION_NONE,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unknown_job");
        break;
    }
}

static cf7_owner_job* cf7_owner_pop_job(void)
{
    cf7_owner_job* job;
    EnterCriticalSection(&g_control.queueLock);
    job = g_control.queueHead;
    if (job != NULL) {
        g_control.queueHead = job->next;
        if (g_control.queueHead == NULL) {
            g_control.queueTail = NULL;
        }
        job->next = NULL;
    }
    LeaveCriticalSection(&g_control.queueLock);
    return job;
}

static DWORD WINAPI cf7_owner_thread_proc(void* parameter)
{
    (void)parameter;
    for (;;) {
        cf7_owner_job* job;
        (void)WaitForSingleObject(g_control.queueEvent, INFINITE);
        if (InterlockedExchange(&g_control.counterOverflow, 0) != 0) {
            cf7_internal_result overflow;
            cf7_graph_uninit(1);
            cf7_internal_result_set(
                &overflow,
                CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR,
                CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
                CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
                MA_INVALID_OPERATION,
                0,
                CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
                "audio.counter_overflow_fail_closed");
            cf7_runtime_set_failure(&overflow);
            cf7_runtime_set_status(CF7_AUDIO_BRIDGE_V2_AUDIO_FAILED_NO_OUTPUT);
        }
        if (InterlockedCompareExchange(&g_control.recoveryRequested, 0, 0) != 0) {
            cf7_mark_device_recovery_requested();
        }
        while ((job = cf7_owner_pop_job()) != NULL) {
            if (InterlockedCompareExchange(
                    &g_control.recoveryRequested,
                    0,
                    0) != 0 && job->kind != CF7_JOB_SHUTDOWN) {
                cf7_mark_device_recovery_requested();
            }
            if (job->kind != CF7_JOB_SHUTDOWN &&
                WaitForSingleObject(
                    g_control.cancelEvent,
                    0u) == WAIT_OBJECT_0) {
                cf7_cancel_owner_job(job);
            } else {
                cf7_process_owner_job(job);
            }
            SetEvent(job->completedEvent);
            if (g_control.ownerExitRequested) {
                return 0u;
            }
        }
        if (g_control.ownerExitRequested) {
            return 0u;
        }
    }
}

static int cf7_owner_start(cf7_owner_job_kind requestedKind)
{
    int ok = 1;
    if (!cf7_control_ensure()) {
        return 0;
    }
    EnterCriticalSection(&g_control.queueLock);
    if (g_control.ownerThread == NULL) {
        if (requestedKind != CF7_JOB_INITIALIZE) {
            LeaveCriticalSection(&g_control.queueLock);
            return 0;
        }
        ResetEvent(g_control.cancelEvent);
        g_control.ownerExitRequested = 0;
        g_control.admissionOpen = 1;
        g_control.queueHead = NULL;
        g_control.queueTail = NULL;
        g_control.ownerThread = CreateThread(
            NULL,
            0u,
            cf7_owner_thread_proc,
            NULL,
            0u,
            &g_control.ownerThreadId);
        if (g_control.ownerThread == NULL) {
            g_control.admissionOpen = 0;
            ok = 0;
        }
    } else if (!g_control.admissionOpen) {
        ok = 0;
    }
    LeaveCriticalSection(&g_control.queueLock);
    return ok;
}

static int cf7_submit_job(cf7_owner_job* job)
{
    if (!cf7_owner_start(job->kind)) {
        return 0;
    }
    job->completedEvent = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (job->completedEvent == NULL) {
        return 0;
    }
    job->next = NULL;
    EnterCriticalSection(&g_control.queueLock);
    if (!g_control.admissionOpen) {
        LeaveCriticalSection(&g_control.queueLock);
        CloseHandle(job->completedEvent);
        job->completedEvent = NULL;
        return 0;
    }
    if (g_control.queueTail == NULL) {
        g_control.queueHead = job;
        g_control.queueTail = job;
    } else {
        g_control.queueTail->next = job;
        g_control.queueTail = job;
    }
    SetEvent(g_control.queueEvent);
    LeaveCriticalSection(&g_control.queueLock);
    (void)WaitForSingleObject(job->completedEvent, INFINITE);
    CloseHandle(job->completedEvent);
    job->completedEvent = NULL;
    return 1;
}

static int cf7_submit_shutdown_job(cf7_owner_job* job)
{
    HANDLE ownerThread;
    job->completedEvent = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (job->completedEvent == NULL) {
        return 0;
    }
    job->next = NULL;
    EnterCriticalSection(&g_control.queueLock);
    if (g_control.ownerThread == NULL || !g_control.admissionOpen) {
        LeaveCriticalSection(&g_control.queueLock);
        CloseHandle(job->completedEvent);
        job->completedEvent = NULL;
        return 0;
    }
    g_control.admissionOpen = 0;
    SetEvent(g_control.cancelEvent);
    if (g_control.queueTail == NULL) {
        g_control.queueHead = job;
        g_control.queueTail = job;
    } else {
        g_control.queueTail->next = job;
        g_control.queueTail = job;
    }
    ownerThread = g_control.ownerThread;
    SetEvent(g_control.queueEvent);
    LeaveCriticalSection(&g_control.queueLock);
    (void)WaitForSingleObject(job->completedEvent, INFINITE);
    CloseHandle(job->completedEvent);
    job->completedEvent = NULL;
    (void)WaitForSingleObject(ownerThread, INFINITE);
    EnterCriticalSection(&g_control.queueLock);
    CloseHandle(g_control.ownerThread);
    g_control.ownerThread = NULL;
    g_control.ownerThreadId = 0u;
    g_control.queueHead = NULL;
    g_control.queueTail = NULL;
    LeaveCriticalSection(&g_control.queueLock);
    return 1;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_query_capability(
    cf7_audio_bridge_v2_capability* capability,
    cf7_audio_bridge_v2_result* result)
{
    char digest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    int outputsOk;
    if (!cf7_control_ensure() || !cf7_result_output_valid(result) ||
        !cf7_audio_bridge_support_prefix_valid(
            capability,
            (uint32_t)sizeof(*capability)) ||
        !cf7_audio_bridge_support_prefix_valid(
            &capability->abiVersion,
            (uint32_t)sizeof(capability->abiVersion)) ||
        !cf7_audio_bridge_support_prefix_valid(
            &capability->miniaudioVersion,
            (uint32_t)sizeof(capability->miniaudioVersion)) ||
        !cf7_output_utf8_valid(&capability->bridgeBuildId, 48u) ||
        !cf7_output_utf8_valid(
            &capability->capabilityDigestSha256,
            CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY) ||
        !cf7_capability_digest(digest)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    capability->abiVersion.major = CF7_AUDIO_BRIDGE_V2_ABI_MAJOR;
    capability->abiVersion.minor = CF7_AUDIO_BRIDGE_V2_ABI_MINOR;
    capability->abiVersion.patch = 0u;
    capability->miniaudioVersion.major = MA_VERSION_MAJOR;
    capability->miniaudioVersion.minor = MA_VERSION_MINOR;
    capability->miniaudioVersion.patch = MA_VERSION_REVISION;
    capability->decoderBackends = CF7_DECODER_MASK;
    capability->containers = CF7_CONTAINER_MASK;
    capability->codecs = CF7_CODEC_MASK;
    capability->extensions = CF7_EXTENSION_MASK;
    capability->compiledBackendMask = CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_PRODUCTION;
    capability->supportsRuntimeCompatibilityProbe = CF7_AUDIO_BRIDGE_V2_TRUE;
    capability->supportsOfflineQualificationProbe = CF7_AUDIO_BRIDGE_V2_TRUE;
    capability->supportsSeek = CF7_AUDIO_BRIDGE_V2_TRUE;
    capability->supportsLoop = CF7_AUDIO_BRIDGE_V2_TRUE;
    capability->supportsDeviceRecovery = CF7_AUDIO_BRIDGE_V2_TRUE;
    capability->supportsBgmMeter = CF7_AUDIO_BRIDGE_V2_TRUE;
    capability->supportsSfxMeter = CF7_AUDIO_BRIDGE_V2_TRUE;
    capability->testOnlyNullEnabled = CF7_AUDIO_BRIDGE_V2_FALSE;
    outputsOk = cf7_audio_bridge_support_write_utf8(
                    &capability->bridgeBuildId,
                    "cf7-audio-v2-abi2-miniaudio-0.11.25") &&
        cf7_audio_bridge_support_write_utf8(
            &capability->capabilityDigestSha256,
            digest);
    return cf7_result_current(
        result,
        outputsOk
            ? CF7_AUDIO_BRIDGE_V2_RESULT_OK
            : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
        CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_CAPABILITY,
        outputsOk
            ? CF7_AUDIO_BRIDGE_V2_STAGE_NONE
            : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_CAPACITY,
        outputsOk ? MA_SUCCESS : MA_INVALID_ARGS,
        0,
        outputsOk
            ? CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE
            : CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
        outputsOk ? "audio.capability.ok" : "audio.capability.capacity");
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_initialize(
    const cf7_audio_bridge_v2_initialize_command* command,
    cf7_audio_bridge_v2_runtime_snapshot* runtimeSnapshot,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    if (!cf7_result_output_valid(result) ||
        !cf7_runtime_output_valid(runtimeSnapshot)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_INITIALIZE;
    job.command = command;
    job.output = runtimeSnapshot;
    job.result = result;
    if (!cf7_submit_job(&job)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unavailable");
    }
    return result->category;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_query_runtime(
    cf7_audio_bridge_v2_runtime_snapshot* runtimeSnapshot,
    cf7_audio_bridge_v2_result* result)
{
    uint32_t snapshotCategory;
    if (!cf7_control_ensure() || !cf7_result_output_valid(result) ||
        !cf7_runtime_output_valid(runtimeSnapshot)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    snapshotCategory = cf7_runtime_snapshot_write(runtimeSnapshot);
    return cf7_result_current(
        result,
        snapshotCategory,
        CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
        snapshotCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK
            ? CF7_AUDIO_BRIDGE_V2_STAGE_NONE
            : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_CAPACITY,
        snapshotCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK
            ? MA_SUCCESS
            : MA_INVALID_ARGS,
        0,
        snapshotCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK
            ? CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE
            : CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
        snapshotCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK
            ? "audio.runtime.ok"
            : "audio.runtime.capacity");
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_query_meter(
    cf7_audio_bridge_v2_meter_snapshot* meterSnapshot,
    cf7_audio_bridge_v2_result* result)
{
    cf7_meter_values values;
    cf7_meter_node* meter;
    uint32_t status;
    int stringOk;
    if (!cf7_control_ensure() || !cf7_result_output_valid(result) ||
        !cf7_audio_bridge_support_prefix_valid(
            meterSnapshot,
            (uint32_t)sizeof(*meterSnapshot)) ||
        !cf7_output_utf8_valid(
            &meterSnapshot->audioSessionId,
            CF7_AUDIO_BRIDGE_V2_UUID_V4_TEXT_CAPACITY) ||
        (meterSnapshot->bus != CF7_AUDIO_BRIDGE_V2_METER_BGM_PRE_MASTER &&
         meterSnapshot->bus != CF7_AUDIO_BRIDGE_V2_METER_SFX_PRE_MASTER)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    meter = meterSnapshot->bus == CF7_AUDIO_BRIDGE_V2_METER_BGM_PRE_MASTER
        ? &g_runtime.bgmMeter
        : &g_runtime.sfxMeter;
    cf7_meter_read(meter, &values);
    AcquireSRWLockShared(&g_control.snapshotLock);
    status = g_runtime.audioStatus;
    meterSnapshot->audioReadyGeneration = g_runtime.audioReadyGeneration;
    meterSnapshot->deviceGeneration = g_runtime.deviceGeneration;
    stringOk = cf7_audio_bridge_support_write_utf8(
        &meterSnapshot->audioSessionId,
        g_runtime.audioSessionId);
    ReleaseSRWLockShared(&g_control.snapshotLock);
    meterSnapshot->peakLeft = values.peakLeft;
    meterSnapshot->peakRight = values.peakRight;
    meterSnapshot->rmsLeft = values.rmsLeft;
    meterSnapshot->rmsRight = values.rmsRight;
    meterSnapshot->clipCount = values.clipCount;
    meterSnapshot->frameCount = values.frameCount;
    meterSnapshot->underrunCount = values.underrunCount;
    if (!stringOk) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_METER,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_CAPACITY,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.meter.capacity");
    }
    return cf7_result_current(
        result,
        status == CF7_AUDIO_BRIDGE_V2_AUDIO_READY
            ? CF7_AUDIO_BRIDGE_V2_RESULT_OK
            : CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
        CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_METER,
        status == CF7_AUDIO_BRIDGE_V2_AUDIO_READY
            ? CF7_AUDIO_BRIDGE_V2_STAGE_NONE
            : CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
        status == CF7_AUDIO_BRIDGE_V2_AUDIO_READY
            ? MA_SUCCESS
            : MA_INVALID_OPERATION,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE,
        status == CF7_AUDIO_BRIDGE_V2_AUDIO_READY
            ? "audio.meter.ok"
            : "audio.meter.not_ready");
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_query_bgm_source(
    cf7_audio_bridge_v2_source_snapshot* sourceSnapshot,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    if (!cf7_result_output_valid(result) ||
        !cf7_source_output_valid(sourceSnapshot)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_QUERY_BGM;
    job.output = sourceSnapshot;
    job.result = result;
    if (!cf7_submit_job(&job)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unavailable");
    }
    return result->category;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_query_sfx_counters(
    cf7_audio_bridge_v2_sfx_counters* counters,
    cf7_audio_bridge_v2_result* result)
{
    uint32_t category;
    if (!cf7_control_ensure() || !cf7_result_output_valid(result) ||
        !cf7_counters_output_valid(counters)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    category = cf7_sfx_counters_write(counters);
    return cf7_result_current(
        result,
        category,
        CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME,
        category == CF7_AUDIO_BRIDGE_V2_RESULT_OK
            ? CF7_AUDIO_BRIDGE_V2_STAGE_NONE
            : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_CAPACITY,
        category == CF7_AUDIO_BRIDGE_V2_RESULT_OK ? MA_SUCCESS : MA_INVALID_ARGS,
        0,
        CF7_AUDIO_BRIDGE_V2_COMPLETION_NONE,
        category == CF7_AUDIO_BRIDGE_V2_RESULT_OK
            ? "audio.sfx.counters_ok"
            : "audio.sfx.counters_capacity");
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_submit_bgm(
    const cf7_audio_bridge_v2_bgm_command* command,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    uint32_t operation = CF7_AUDIO_BRIDGE_V2_OPERATION_NONE;
    if (!cf7_result_output_valid(result)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    if (cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command))) {
        operation = command->operation;
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_BGM;
    job.command = command;
    job.result = result;
    if (!cf7_submit_job(&job)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unavailable");
    }
    return result->category;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_rebuild_sfx_catalog(
    const cf7_audio_bridge_v2_sfx_catalog_command* command,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    if (!cf7_result_output_valid(result)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_REBUILD_SFX;
    job.command = command;
    job.result = result;
    if (!cf7_submit_job(&job)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_REBUILD_CATALOG,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unavailable");
    }
    return result->category;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_submit_sfx_batch(
    const cf7_audio_bridge_v2_sfx_batch_command* command,
    cf7_audio_bridge_v2_sfx_counters* counters,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    char* session = NULL;
    int matches;
    uint32_t status = 0u;
    uint64_t deviceGeneration = 0u;
    uint32_t itemCount = 0u;
    if (!cf7_result_output_valid(result) ||
        !cf7_counters_output_valid(counters)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    if (!cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command)) ||
        !cf7_array_input_valid(
            &command->linkageIds,
            (uint32_t)sizeof(cf7_audio_bridge_v2_sfx_play_item),
            65536u)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
            CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.sfx.batch_invalid");
    }
    itemCount = command->linkageIds.countElements;
    matches = cf7_session_matches(
        &command->audioSessionId,
        command->audioReadyGeneration,
        &session,
        &status,
        &deviceGeneration);
    cf7_audio_bridge_support_free(session);
    if (matches <= 0) {
        if (matches == 0) {
            (void)cf7_counter_add(&g_runtime.sfxStaleGenerationDrops, itemCount);
        }
        (void)cf7_sfx_counters_write(counters);
        return cf7_result_current(
            result,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_RESULT_STALE_GENERATION
                : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_SESSION
                : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            matches == 0
                ? "audio.sfx.batch_stale"
                : "audio.sfx.batch_session_invalid");
    }
    if (status != CF7_AUDIO_BRIDGE_V2_AUDIO_READY) {
        (void)cf7_counter_add(
            status == CF7_AUDIO_BRIDGE_V2_AUDIO_RECOVERING
                ? &g_runtime.sfxRecoveryDrops
                : &g_runtime.sfxPreReadyDrops,
            itemCount);
        (void)cf7_sfx_counters_write(counters);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_INVALID_OPERATION,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.sfx.batch_dropped_not_ready");
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_SFX_BATCH;
    job.command = command;
    job.output = counters;
    job.result = result;
    job.capturedDeviceGeneration = deviceGeneration;
    if (!cf7_submit_job(&job)) {
        (void)cf7_counter_add(&g_runtime.sfxRecoveryDrops, itemCount);
        (void)cf7_sfx_counters_write(counters);
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SFX_PLAY_BATCH,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unavailable");
    }
    return result->category;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_set_gain(
    const cf7_audio_bridge_v2_gain_command* command,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    uint32_t operation = CF7_AUDIO_BRIDGE_V2_OPERATION_NONE;
    if (!cf7_result_output_valid(result)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    if (cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command))) {
        operation = command->operation;
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_SET_GAIN;
    job.command = command;
    job.result = result;
    if (!cf7_submit_job(&job)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            operation,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unavailable");
    }
    return result->category;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_probe_runtime_compatibility(
    const cf7_audio_bridge_v2_runtime_probe_command* command,
    cf7_audio_bridge_v2_probe_result* probeResult,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    if (!cf7_result_output_valid(result) ||
        !cf7_probe_output_valid(probeResult)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_PROBE_RUNTIME;
    job.command = command;
    job.output = probeResult;
    job.result = result;
    if (!cf7_submit_job(&job)) {
        cf7_probe_result_zero_metrics(probeResult);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unavailable");
    }
    return result->category;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_probe_offline_qualification(
    const cf7_audio_bridge_v2_offline_probe_command* command,
    cf7_audio_bridge_v2_probe_result* probeResult,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    if (!cf7_result_output_valid(result) ||
        !cf7_probe_output_valid(probeResult)) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_PROBE_OFFLINE;
    job.command = command;
    job.output = probeResult;
    job.result = result;
    if (!cf7_submit_job(&job)) {
        cf7_probe_result_zero_metrics(probeResult);
        return cf7_probe_finish(
            probeResult,
            result,
            CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            CF7_AUDIO_BRIDGE_V2_PROBE_OUTCOME_NONE,
            CF7_AUDIO_BRIDGE_V2_EOF_NOT_REACHED,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.owner.unavailable");
    }
    return result->category;
}

CF7_AUDIO_BRIDGE_V2_API cf7_audio_bridge_v2_result_category
CF7_AUDIO_BRIDGE_V2_CALL cf7_audio_bridge_v2_shutdown(
    const cf7_audio_bridge_v2_shutdown_command* command,
    cf7_audio_bridge_v2_result* result)
{
    cf7_owner_job job;
    char* session = NULL;
    int matches;
    int ownerExists;
    if (!cf7_control_ensure() || !cf7_result_output_valid(result) ||
        !cf7_audio_bridge_support_prefix_valid(
            command,
            (uint32_t)sizeof(*command))) {
        return CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH;
    }
    matches = cf7_session_matches(
        &command->audioSessionId,
        command->audioReadyGeneration,
        &session,
        NULL,
        NULL);
    cf7_audio_bridge_support_free(session);
    if (matches <= 0) {
        return cf7_result_current(
            result,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_RESULT_STALE_GENERATION
                : CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SHUTDOWN,
            matches == 0
                ? CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_SESSION
                : CF7_AUDIO_BRIDGE_V2_STAGE_VALIDATE_ABI,
            MA_INVALID_ARGS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            matches == 0 ? "audio.shutdown.stale" : "audio.shutdown.session_invalid");
    }
    EnterCriticalSection(&g_control.queueLock);
    ownerExists = g_control.ownerThread != NULL;
    LeaveCriticalSection(&g_control.queueLock);
    if (!ownerExists) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_OK,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SHUTDOWN,
            CF7_AUDIO_BRIDGE_V2_STAGE_SHUTDOWN,
            MA_SUCCESS,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_STOPPED,
            "audio.shutdown.already_complete");
    }
    memset(&job, 0, sizeof(job));
    job.kind = CF7_JOB_SHUTDOWN;
    job.command = command;
    job.result = result;
    if (!cf7_submit_shutdown_job(&job)) {
        return cf7_result_current(
            result,
            CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY,
            CF7_AUDIO_BRIDGE_V2_OPERATION_SHUTDOWN,
            CF7_AUDIO_BRIDGE_V2_STAGE_ADMISSION,
            MA_UNAVAILABLE,
            0,
            CF7_AUDIO_BRIDGE_V2_COMPLETION_FAILED,
            "audio.shutdown.admission_closed");
    }
    return result->category;
}
