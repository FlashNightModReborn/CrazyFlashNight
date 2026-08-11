#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>

#include "../audio_bridge_v2.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#define FILETIME_UNIX_EPOCH_TICKS UINT64_C(116444736000000000)
#define FILETIME_TICKS_PER_MILLISECOND UINT64_C(10000)

typedef uint32_t (__cdecl *query_capability_proc)(
    cf7_audio_bridge_v2_capability*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *initialize_proc)(
    const cf7_audio_bridge_v2_initialize_command*,
    cf7_audio_bridge_v2_runtime_snapshot*,
    cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *query_runtime_proc)(
    cf7_audio_bridge_v2_runtime_snapshot*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *query_meter_proc)(
    cf7_audio_bridge_v2_meter_snapshot*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *query_source_proc)(
    cf7_audio_bridge_v2_source_snapshot*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *query_counters_proc)(
    cf7_audio_bridge_v2_sfx_counters*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *submit_bgm_proc)(
    const cf7_audio_bridge_v2_bgm_command*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *set_gain_proc)(
    const cf7_audio_bridge_v2_gain_command*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *probe_runtime_proc)(
    const cf7_audio_bridge_v2_runtime_probe_command*,
    cf7_audio_bridge_v2_probe_result*,
    cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *probe_offline_proc)(
    const cf7_audio_bridge_v2_offline_probe_command*,
    cf7_audio_bridge_v2_probe_result*,
    cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *shutdown_proc)(
    const cf7_audio_bridge_v2_shutdown_command*, cf7_audio_bridge_v2_result*);

static int g_failures;
static int g_checks;

typedef struct probe_thread_context {
    probe_offline_proc function;
    const cf7_audio_bridge_v2_offline_probe_command* command;
    cf7_audio_bridge_v2_probe_result* probe;
    cf7_audio_bridge_v2_result* result;
    HANDLE enteredEvent;
    uint32_t returnedCategory;
} probe_thread_context;

#define CHECK(expression)                                                    \
    do {                                                                     \
        ++g_checks;                                                          \
        if (!(expression)) {                                                 \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expression);  \
            ++g_failures;                                                    \
        }                                                                    \
    } while (0)

static cf7_audio_bridge_v2_utf8_buffer output_utf8(char* value, uint32_t capacity)
{
    cf7_audio_bridge_v2_utf8_buffer result;
    memset(&result, 0, sizeof(result));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(result);
    result.dataAddress = (uint64_t)(uintptr_t)value;
    result.capacityBytes = capacity;
    result.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY;
    return result;
}

static cf7_audio_bridge_v2_utf16_buffer output_utf16(
    wchar_t* value,
    uint32_t capacity)
{
    cf7_audio_bridge_v2_utf16_buffer result;
    memset(&result, 0, sizeof(result));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(result);
    result.dataAddress = (uint64_t)(uintptr_t)value;
    result.capacityCodeUnits = capacity;
    result.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY;
    return result;
}

static cf7_audio_bridge_v2_utf8_buffer input_utf8(const char* value)
{
    cf7_audio_bridge_v2_utf8_buffer result;
    size_t length = strlen(value);
    memset(&result, 0, sizeof(result));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(result);
    result.dataAddress = (uint64_t)(uintptr_t)value;
    result.capacityBytes = (uint32_t)length + 1u;
    result.lengthBytes = (uint32_t)length;
    result.requiredBytes = 0u;
    result.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY;
    return result;
}

static cf7_audio_bridge_v2_utf16_buffer input_utf16(const wchar_t* value)
{
    cf7_audio_bridge_v2_utf16_buffer result;
    size_t length = wcslen(value);
    memset(&result, 0, sizeof(result));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(result);
    result.dataAddress = (uint64_t)(uintptr_t)value;
    result.capacityCodeUnits = (uint32_t)length + 1u;
    result.lengthCodeUnits = (uint32_t)length;
    result.requiredCodeUnits = 0u;
    result.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY;
    return result;
}

static void initialize_result(
    cf7_audio_bridge_v2_result* result,
    char session[64],
    char message[128])
{
    memset(result, 0, sizeof(*result));
    memset(session, 0, 64u);
    memset(message, 0, 128u);
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(*result);
    result->audioSessionId = output_utf8(session, 64u);
    result->messageKey = output_utf8(message, 128u);
}

static void initialize_runtime(
    cf7_audio_bridge_v2_runtime_snapshot* runtime,
    char session[64],
    char digest[80],
    wchar_t name[512],
    char failureSession[64],
    char failureMessage[128])
{
    memset(runtime, 0, sizeof(*runtime));
    memset(session, 0, 64u);
    memset(digest, 0, 80u);
    memset(name, 0, 512u * sizeof(wchar_t));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(*runtime);
    runtime->audioSessionId = output_utf8(session, 64u);
    runtime->selectedDeviceIdDigest = output_utf8(digest, 80u);
    runtime->selectedDeviceName = output_utf16(name, 512u);
    initialize_result(
        &runtime->lastStructuredFailure,
        failureSession,
        failureMessage);
}

static void initialize_probe_result(
    cf7_audio_bridge_v2_probe_result* probe,
    char session[64],
    char message[128])
{
    memset(probe, 0, sizeof(*probe));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(*probe);
    initialize_result(&probe->structuredResult, session, message);
}

static int uppercase_sha256(const char* value)
{
    size_t index;
    if (strlen(value) != 64u) {
        return 0;
    }
    for (index = 0u; index < 64u; ++index) {
        if (!((value[index] >= '0' && value[index] <= '9') ||
              (value[index] >= 'A' && value[index] <= 'F'))) {
            return 0;
        }
    }
    return 1;
}

static void write_u16_le(unsigned char* target, uint16_t value)
{
    target[0] = (unsigned char)(value & 0xFFu);
    target[1] = (unsigned char)((value >> 8u) & 0xFFu);
}

static void write_u32_le(unsigned char* target, uint32_t value)
{
    target[0] = (unsigned char)(value & 0xFFu);
    target[1] = (unsigned char)((value >> 8u) & 0xFFu);
    target[2] = (unsigned char)((value >> 16u) & 0xFFu);
    target[3] = (unsigned char)((value >> 24u) & 0xFFu);
}

static int sha256_file(
    const wchar_t* path,
    uint64_t maximumBytes,
    char digest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY])
{
    static const char hex[] = "0123456789ABCDEF";
    BCRYPT_ALG_HANDLE algorithm = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    HANDLE file = INVALID_HANDLE_VALUE;
    unsigned char buffer[4096];
    unsigned char rawDigest[32];
    uint64_t total = 0u;
    size_t index;
    int ok = 0;
    file = CreateFileW(
        path,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        NULL);
    if (file == INVALID_HANDLE_VALUE ||
        BCryptOpenAlgorithmProvider(
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
        DWORD requested = (DWORD)sizeof(buffer);
        DWORD actual = 0u;
        if (maximumBytes != 0u) {
            uint64_t remaining;
            if (total >= maximumBytes) {
                break;
            }
            remaining = maximumBytes - total;
            if (remaining < requested) {
                requested = (DWORD)remaining;
            }
        }
        if (!ReadFile(
                file,
                buffer,
                requested,
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
        total += actual;
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
    ok = 1;

cleanup:
    if (hash != NULL) {
        BCryptDestroyHash(hash);
    }
    if (algorithm != NULL) {
        BCryptCloseAlgorithmProvider(algorithm, 0u);
    }
    if (file != INVALID_HANDLE_VALUE) {
        CloseHandle(file);
    }
    return ok;
}

static int write_probe_fixture(
    const wchar_t* basePath,
    wchar_t relativePath[128],
    wchar_t fullPath[1024],
    uint64_t* fileSize,
    int64_t* modifiedUnixMilliseconds,
    char digest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY])
{
    enum { sampleCount = 960 };
    unsigned char header[44];
    int16_t samples[sampleCount];
    WIN32_FILE_ATTRIBUTE_DATA attributes;
    ULARGE_INTEGER size;
    ULARGE_INTEGER modified;
    HANDLE file;
    DWORD written;
    size_t index;
    if (basePath == NULL || fileSize == NULL ||
        modifiedUnixMilliseconds == NULL) {
        return 0;
    }
    if (swprintf_s(
            relativePath,
            128u,
            L"cf7-audio-v2-runtime-contract-%lu.wav",
            GetCurrentProcessId()) < 0 ||
        swprintf_s(
            fullPath,
            1024u,
            L"%ls\\%ls",
            basePath,
            relativePath) < 0) {
        return 0;
    }
    memset(header, 0, sizeof(header));
    memcpy(header, "RIFF", 4u);
    write_u32_le(header + 4u, 36u + (uint32_t)sizeof(samples));
    memcpy(header + 8u, "WAVEfmt ", 8u);
    write_u32_le(header + 16u, 16u);
    write_u16_le(header + 20u, 1u);
    write_u16_le(header + 22u, 1u);
    write_u32_le(header + 24u, 48000u);
    write_u32_le(header + 28u, 96000u);
    write_u16_le(header + 32u, 2u);
    write_u16_le(header + 34u, 16u);
    memcpy(header + 36u, "data", 4u);
    write_u32_le(header + 40u, (uint32_t)sizeof(samples));
    for (index = 0u; index < sampleCount; ++index) {
        samples[index] = (int16_t)((index & 1u) == 0u ? 4096 : -4096);
    }
    file = CreateFileW(
        fullPath,
        GENERIC_WRITE,
        0u,
        NULL,
        CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (file == INVALID_HANDLE_VALUE) {
        return 0;
    }
    if (!WriteFile(file, header, (DWORD)sizeof(header), &written, NULL) ||
        written != (DWORD)sizeof(header) ||
        !WriteFile(file, samples, (DWORD)sizeof(samples), &written, NULL) ||
        written != (DWORD)sizeof(samples) ||
        !FlushFileBuffers(file)) {
        CloseHandle(file);
        DeleteFileW(fullPath);
        return 0;
    }
    CloseHandle(file);
    if (!GetFileAttributesExW(
            fullPath,
            GetFileExInfoStandard,
            &attributes)) {
        DeleteFileW(fullPath);
        return 0;
    }
    size.HighPart = attributes.nFileSizeHigh;
    size.LowPart = attributes.nFileSizeLow;
    modified.HighPart = attributes.ftLastWriteTime.dwHighDateTime;
    modified.LowPart = attributes.ftLastWriteTime.dwLowDateTime;
    if (modified.QuadPart < FILETIME_UNIX_EPOCH_TICKS ||
        !sha256_file(fullPath, 0u, digest)) {
        DeleteFileW(fullPath);
        return 0;
    }
    *fileSize = size.QuadPart;
    *modifiedUnixMilliseconds = (int64_t)(
        (modified.QuadPart - FILETIME_UNIX_EPOCH_TICKS) /
        FILETIME_TICKS_PER_MILLISECOND);
    return 1;
}

static int write_large_wav_probe_fixture(
    const wchar_t* basePath,
    wchar_t relativePath[128],
    wchar_t fullPath[1024],
    uint64_t* fileSize,
    int64_t* modifiedUnixMilliseconds,
    char first64kDigest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY])
{
    enum { samplesPerChunk = 4096, requiredSamples = 96000 };
    const uint64_t totalBytes =
        CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES + 4096u;
    unsigned char header[44];
    int16_t samples[samplesPerChunk];
    WIN32_FILE_ATTRIBUTE_DATA attributes;
    ULARGE_INTEGER size;
    ULARGE_INTEGER modified;
    LARGE_INTEGER length;
    HANDLE file;
    DWORD written;
    uint32_t samplesRemaining = requiredSamples;
    size_t index;
    if (swprintf_s(
            relativePath,
            128u,
            L"cf7-audio-v2-large-wav-contract-%lu.wav",
            GetCurrentProcessId()) < 0 ||
        swprintf_s(
            fullPath,
            1024u,
            L"%ls\\%ls",
            basePath,
            relativePath) < 0 ||
        totalBytes - 8u > UINT32_MAX ||
        totalBytes - sizeof(header) > UINT32_MAX) {
        return 0;
    }
    memset(header, 0, sizeof(header));
    memcpy(header, "RIFF", 4u);
    write_u32_le(header + 4u, (uint32_t)(totalBytes - 8u));
    memcpy(header + 8u, "WAVEfmt ", 8u);
    write_u32_le(header + 16u, 16u);
    write_u16_le(header + 20u, 1u);
    write_u16_le(header + 22u, 1u);
    write_u32_le(header + 24u, 48000u);
    write_u32_le(header + 28u, 96000u);
    write_u16_le(header + 32u, 2u);
    write_u16_le(header + 34u, 16u);
    memcpy(header + 36u, "data", 4u);
    write_u32_le(header + 40u, (uint32_t)(totalBytes - sizeof(header)));
    for (index = 0u; index < samplesPerChunk; ++index) {
        samples[index] = (int16_t)((index & 1u) == 0u ? 4096 : -4096);
    }
    file = CreateFileW(
        fullPath,
        GENERIC_WRITE,
        0u,
        NULL,
        CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (file == INVALID_HANDLE_VALUE) {
        return 0;
    }
    if (!WriteFile(file, header, (DWORD)sizeof(header), &written, NULL) ||
        written != (DWORD)sizeof(header)) {
        CloseHandle(file);
        DeleteFileW(fullPath);
        return 0;
    }
    while (samplesRemaining != 0u) {
        uint32_t chunkSamples = samplesRemaining < (uint32_t)samplesPerChunk
            ? samplesRemaining
            : (uint32_t)samplesPerChunk;
        DWORD chunkBytes = chunkSamples * (DWORD)sizeof(samples[0]);
        if (!WriteFile(file, samples, chunkBytes, &written, NULL) ||
            written != chunkBytes) {
            CloseHandle(file);
            DeleteFileW(fullPath);
            return 0;
        }
        samplesRemaining -= chunkSamples;
    }
    length.QuadPart = (LONGLONG)totalBytes;
    if (!SetFilePointerEx(file, length, NULL, FILE_BEGIN) ||
        !SetEndOfFile(file) ||
        !FlushFileBuffers(file)) {
        CloseHandle(file);
        DeleteFileW(fullPath);
        return 0;
    }
    CloseHandle(file);
    if (!GetFileAttributesExW(
            fullPath,
            GetFileExInfoStandard,
            &attributes)) {
        DeleteFileW(fullPath);
        return 0;
    }
    size.HighPart = attributes.nFileSizeHigh;
    size.LowPart = attributes.nFileSizeLow;
    modified.HighPart = attributes.ftLastWriteTime.dwHighDateTime;
    modified.LowPart = attributes.ftLastWriteTime.dwLowDateTime;
    if (size.QuadPart != totalBytes ||
        modified.QuadPart < FILETIME_UNIX_EPOCH_TICKS ||
        !sha256_file(fullPath, 65536u, first64kDigest)) {
        DeleteFileW(fullPath);
        return 0;
    }
    *fileSize = size.QuadPart;
    *modifiedUnixMilliseconds = (int64_t)(
        (modified.QuadPart - FILETIME_UNIX_EPOCH_TICKS) /
        FILETIME_TICKS_PER_MILLISECOND);
    return 1;
}

static int write_sparse_fixture(
    const wchar_t* basePath,
    wchar_t relativePath[128],
    wchar_t fullPath[1024],
    uint64_t sizeBytes)
{
    HANDLE file;
    LARGE_INTEGER length;
    if (swprintf_s(
            relativePath,
            128u,
            L"cf7-audio-v2-cancel-contract-%lu.bin",
            GetCurrentProcessId()) < 0 ||
        swprintf_s(
            fullPath,
            1024u,
            L"%ls\\%ls",
            basePath,
            relativePath) < 0 ||
        sizeBytes > (uint64_t)INT64_MAX) {
        return 0;
    }
    file = CreateFileW(
        fullPath,
        GENERIC_WRITE,
        0u,
        NULL,
        CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    if (file == INVALID_HANDLE_VALUE) {
        return 0;
    }
    length.QuadPart = (LONGLONG)sizeBytes;
    if (!SetFilePointerEx(file, length, NULL, FILE_BEGIN) ||
        !SetEndOfFile(file)) {
        CloseHandle(file);
        DeleteFileW(fullPath);
        return 0;
    }
    CloseHandle(file);
    return 1;
}

static int write_mf_input_bound_fixture(
    const wchar_t* basePath,
    const wchar_t* sourcePath,
    wchar_t relativePath[128],
    wchar_t fullPath[1024],
    uint64_t* fileSize,
    int64_t* modifiedUnixMilliseconds,
    char first64kDigest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY])
{
    unsigned char header[12];
    HANDLE file;
    DWORD written = 0u;
    LARGE_INTEGER length;
    WIN32_FILE_ATTRIBUTE_DATA attributes;
    ULARGE_INTEGER size;
    ULARGE_INTEGER modified;
    if (swprintf_s(
            relativePath,
            128u,
            L"cf7-audio-v2-mf-bound-contract-%lu.m4a",
            GetCurrentProcessId()) < 0 ||
        swprintf_s(
            fullPath,
            1024u,
            L"%ls\\%ls",
            basePath,
            relativePath) < 0) {
        return 0;
    }
    if (sourcePath != NULL && sourcePath[0] != L'\0') {
        if (!CopyFileW(sourcePath, fullPath, TRUE)) {
            return 0;
        }
    } else {
        memset(header, 0, sizeof(header));
        header[3] = 12u;
        memcpy(header + 4u, "ftyp", 4u);
        memcpy(header + 8u, "M4A ", 4u);
        file = CreateFileW(
            fullPath,
            GENERIC_WRITE,
            0u,
            NULL,
            CREATE_NEW,
            FILE_ATTRIBUTE_NORMAL,
            NULL);
        if (file == INVALID_HANDLE_VALUE) {
            return 0;
        }
        length.QuadPart = (LONGLONG)(
            CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES + 4096u);
        if (!WriteFile(
                file,
                header,
                (DWORD)sizeof(header),
                &written,
                NULL) ||
            written != (DWORD)sizeof(header) ||
            !SetFilePointerEx(file, length, NULL, FILE_BEGIN) ||
            !SetEndOfFile(file)) {
            CloseHandle(file);
            DeleteFileW(fullPath);
            return 0;
        }
        CloseHandle(file);
    }
    if (!GetFileAttributesExW(
            fullPath,
            GetFileExInfoStandard,
            &attributes)) {
        DeleteFileW(fullPath);
        return 0;
    }
    size.HighPart = attributes.nFileSizeHigh;
    size.LowPart = attributes.nFileSizeLow;
    modified.HighPart = attributes.ftLastWriteTime.dwHighDateTime;
    modified.LowPart = attributes.ftLastWriteTime.dwLowDateTime;
    if (size.QuadPart <= CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES ||
        modified.QuadPart < FILETIME_UNIX_EPOCH_TICKS ||
        !sha256_file(fullPath, 65536u, first64kDigest)) {
        DeleteFileW(fullPath);
        return 0;
    }
    *fileSize = size.QuadPart;
    *modifiedUnixMilliseconds = (int64_t)(
        (modified.QuadPart - FILETIME_UNIX_EPOCH_TICKS) /
        FILETIME_TICKS_PER_MILLISECOND);
    return 1;
}

static DWORD WINAPI probe_thread_main(void* parameter)
{
    probe_thread_context* context = (probe_thread_context*)parameter;
    SetEvent(context->enteredEvent);
    context->returnedCategory = context->function(
        context->command,
        context->probe,
        context->result);
    return 0u;
}

static FARPROC require_export(HMODULE module, const char* name)
{
    FARPROC value = GetProcAddress(module, name);
    CHECK(value != NULL);
    return value;
}

#define LOAD_TYPED(target, module, name)               \
    do {                                                \
        FARPROC raw = require_export((module), (name)); \
        memset(&(target), 0, sizeof(target));           \
        if (raw != NULL) {                              \
            memcpy(&(target), &raw, sizeof(target));    \
        }                                               \
    } while (0)

int wmain(int argc, wchar_t** argv)
{
    static const char* allExports[] = {
        "cf7_audio_bridge_v2_query_capability",
        "cf7_audio_bridge_v2_initialize",
        "cf7_audio_bridge_v2_query_runtime",
        "cf7_audio_bridge_v2_query_meter",
        "cf7_audio_bridge_v2_query_bgm_source",
        "cf7_audio_bridge_v2_query_sfx_counters",
        "cf7_audio_bridge_v2_submit_bgm",
        "cf7_audio_bridge_v2_rebuild_sfx_catalog",
        "cf7_audio_bridge_v2_submit_sfx_batch",
        "cf7_audio_bridge_v2_set_gain",
        "cf7_audio_bridge_v2_probe_runtime_compatibility",
        "cf7_audio_bridge_v2_probe_offline_qualification",
        "cf7_audio_bridge_v2_shutdown"
    };
    const char currentSession[] = "01234567-89ab-4cde-8fab-0123456789ab";
    const char staleSession[] = "11111111-1111-4111-8111-111111111111";
    HMODULE module;
    size_t index;
    query_capability_proc queryCapability;
    initialize_proc initialize;
    query_runtime_proc queryRuntime;
    query_meter_proc queryMeter;
    query_source_proc querySource;
    query_counters_proc queryCounters;
    submit_bgm_proc submitBgm;
    set_gain_proc setGain;
    probe_runtime_proc probeRuntime;
    probe_offline_proc probeOffline;
    shutdown_proc shutdown;
    cf7_audio_bridge_v2_capability capability;
    cf7_audio_bridge_v2_initialize_command initializeCommand;
    cf7_audio_bridge_v2_runtime_snapshot runtime;
    cf7_audio_bridge_v2_result result;
    cf7_audio_bridge_v2_meter_snapshot meter;
    cf7_audio_bridge_v2_source_snapshot source;
    cf7_audio_bridge_v2_sfx_counters counters;
    cf7_audio_bridge_v2_bgm_command bgmCommand;
    cf7_audio_bridge_v2_gain_command gain;
    cf7_audio_bridge_v2_runtime_probe_command runtimeProbe;
    cf7_audio_bridge_v2_offline_probe_command offlineProbe;
    cf7_audio_bridge_v2_probe_result probe;
    cf7_audio_bridge_v2_shutdown_command shutdownCommand;
    char resultSession[64];
    char resultMessage[128];
    char capabilityBuild[128];
    char capabilityDigest[80];
    char runtimeSession[64];
    char runtimeDigest[80];
    wchar_t runtimeName[512];
    char runtimeFailureSession[64];
    char runtimeFailureMessage[128];
    char meterSession[64];
    char sourceSession[64];
    char sourceResultSession[64];
    char sourceResultMessage[128];
    char counterSession[64];
    char probeSession[64];
    char probeMessage[128];
    wchar_t fixtureRelative[128];
    wchar_t fixtureFull[1024];
    wchar_t largeWavRelative[128];
    wchar_t largeWavFull[1024];
    wchar_t cancelRelative[128];
    wchar_t cancelFull[1024];
    wchar_t mfBoundRelative[128];
    wchar_t mfBoundFull[1024];
    char fixtureDigest[80];
    char largeWavDigest[80];
    char mfBoundDigest[80];
    char wrongDigest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    uint64_t fixtureSize = 0u;
    int64_t fixtureModified = 0;
    uint64_t largeWavSize = 0u;
    int64_t largeWavModified = 0;
    uint64_t mfBoundSize = 0u;
    int64_t mfBoundModified = 0;
    int fixtureCreated = 0;
    int largeWavFixtureCreated = 0;
    int mfBoundFixtureCreated = 0;
    int mfBoundExpectCompatible;
    int cancelFixtureCreated = 0;
    int shutdownPerformed = 0;
    cf7_audio_bridge_v2_offline_probe_command cancelProbe;
    cf7_audio_bridge_v2_probe_result cancelProbeResult;
    cf7_audio_bridge_v2_result cancelResult;
    char cancelProbeSession[64];
    char cancelProbeMessage[128];
    char cancelResultSession[64];
    char cancelResultMessage[128];
    probe_thread_context probeThreadContext = {0};
    HANDLE probeThread = NULL;
    HANDLE probeEnteredEvent = NULL;
    ULONGLONG shutdownStarted = 0u;
    ULONGLONG playbackDeadline = 0u;
    uint32_t callResult;
    uint32_t initializeCategory;
    uint32_t sourceCallResult = CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY;
    uint32_t meterCallResult = CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY;
    uint64_t deviceGeneration;
    int playbackObserved = 0;

    if (argc != 3 && argc != 4) {
        fwprintf(
            stderr,
            L"usage: %s <miniaudio.dll> <contained-base> [large-m4a-source]\n",
            argv[0]);
        return 2;
    }
    mfBoundExpectCompatible = argc == 4;
    module = LoadLibraryW(argv[1]);
    if (module == NULL) {
        fwprintf(stderr, L"LoadLibrary failed: %lu\n", GetLastError());
        return 2;
    }
    for (index = 0u; index < sizeof(allExports) / sizeof(allExports[0]); ++index) {
        (void)require_export(module, allExports[index]);
    }
    LOAD_TYPED(queryCapability, module, allExports[0]);
    LOAD_TYPED(initialize, module, allExports[1]);
    LOAD_TYPED(queryRuntime, module, allExports[2]);
    LOAD_TYPED(queryMeter, module, allExports[3]);
    LOAD_TYPED(querySource, module, allExports[4]);
    LOAD_TYPED(queryCounters, module, allExports[5]);
    LOAD_TYPED(submitBgm, module, allExports[6]);
    LOAD_TYPED(setGain, module, allExports[9]);
    LOAD_TYPED(probeRuntime, module, allExports[10]);
    LOAD_TYPED(probeOffline, module, allExports[11]);
    LOAD_TYPED(shutdown, module, allExports[12]);

    memset(&capability, 0, sizeof(capability));
    memset(capabilityBuild, 0, sizeof(capabilityBuild));
    memset(capabilityDigest, 0, sizeof(capabilityDigest));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(capability);
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(capability.abiVersion);
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(capability.miniaudioVersion);
    capability.bridgeBuildId = output_utf8(capabilityBuild, sizeof(capabilityBuild));
    capability.capabilityDigestSha256 = output_utf8(
        capabilityDigest,
        sizeof(capabilityDigest));
    initialize_result(&result, resultSession, resultMessage);
    callResult = queryCapability(&capability, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
    CHECK(result.category == callResult);
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_CAPABILITY);
    CHECK(result.audioReadyGeneration == 0u);
    CHECK(resultSession[0] == '\0');
    CHECK(capability.compiledBackendMask ==
        CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_PRODUCTION);
    CHECK(capability.testOnlyNullEnabled == CF7_AUDIO_BRIDGE_V2_FALSE);
    CHECK(capability.supportsRuntimeCompatibilityProbe == CF7_AUDIO_BRIDGE_V2_TRUE);
    CHECK(capability.supportsOfflineQualificationProbe == CF7_AUDIO_BRIDGE_V2_TRUE);
    CHECK(capability.supportsDeviceRecovery == CF7_AUDIO_BRIDGE_V2_TRUE);
    CHECK(uppercase_sha256(capabilityDigest));

    memset(&initializeCommand, 0, sizeof(initializeCommand));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(initializeCommand);
    initializeCommand.normalizedBasePath = input_utf16(argv[2]);
    initializeCommand.audioSessionId = input_utf8(currentSession);
    initializeCommand.audioReadyGeneration = 1u;
    initializeCommand.executionIdentity = CF7_AUDIO_BRIDGE_V2_EXECUTION_PRODUCTION;
    initialize_runtime(
        &runtime,
        runtimeSession,
        runtimeDigest,
        runtimeName,
        runtimeFailureSession,
        runtimeFailureMessage);
    initialize_result(&result, resultSession, resultMessage);
    initializeCategory = initialize(&initializeCommand, &runtime, &result);
    CHECK(initializeCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK ||
        initializeCategory == CF7_AUDIO_BRIDGE_V2_RESULT_DEVICE_UNAVAILABLE);
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_INITIALIZE);
    CHECK(strcmp(resultSession, currentSession) == 0);
    CHECK(result.audioReadyGeneration == 1u);
    CHECK(result.deviceGeneration >= 1u);
    CHECK(strcmp(runtimeSession, currentSession) == 0);
    CHECK(runtime.audioReadyGeneration == 1u);
    deviceGeneration = runtime.deviceGeneration;
    if (initializeCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK) {
        CHECK(runtime.audioStatus == CF7_AUDIO_BRIDGE_V2_AUDIO_READY);
        CHECK(runtime.selectedBackend >= CF7_AUDIO_BRIDGE_V2_BACKEND_WASAPI &&
            runtime.selectedBackend <= CF7_AUDIO_BRIDGE_V2_BACKEND_WINMM);
        CHECK(runtime.selectedBackend != CF7_AUDIO_BRIDGE_V2_BACKEND_TEST_ONLY_NULL);
        CHECK(uppercase_sha256(runtimeDigest));
        CHECK(runtimeName[0] != L'\0');
        CHECK(runtime.sampleRate > 0u);
        CHECK(runtime.channels > 0u);
    } else {
        CHECK(runtime.audioStatus == CF7_AUDIO_BRIDGE_V2_AUDIO_FAILED_NO_OUTPUT);
        CHECK(runtime.selectedBackend == CF7_AUDIO_BRIDGE_V2_BACKEND_NONE);
    }

    initialize_runtime(
        &runtime,
        runtimeSession,
        runtimeDigest,
        runtimeName,
        runtimeFailureSession,
        runtimeFailureMessage);
    initialize_result(&result, resultSession, resultMessage);
    callResult = queryRuntime(&runtime, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME);
    CHECK(strcmp(resultSession, currentSession) == 0);
    CHECK(result.audioReadyGeneration == 1u);
    CHECK(result.deviceGeneration == deviceGeneration);

    memset(&meter, 0, sizeof(meter));
    memset(meterSession, 0, sizeof(meterSession));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(meter);
    meter.bus = CF7_AUDIO_BRIDGE_V2_METER_BGM_PRE_MASTER;
    meter.audioSessionId = output_utf8(meterSession, sizeof(meterSession));
    initialize_result(&result, resultSession, resultMessage);
    callResult = queryMeter(&meter, &result);
    CHECK(callResult == (initializeCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK
        ? CF7_AUDIO_BRIDGE_V2_RESULT_OK
        : CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY));
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_METER);
    CHECK(strcmp(resultSession, currentSession) == 0);
    CHECK(strcmp(meterSession, currentSession) == 0);
    CHECK(meter.deviceGeneration == deviceGeneration);

    memset(&source, 0, sizeof(source));
    memset(sourceSession, 0, sizeof(sourceSession));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(source);
    source.audioSessionId = output_utf8(sourceSession, sizeof(sourceSession));
    initialize_result(
        &source.startResult,
        sourceResultSession,
        sourceResultMessage);
    initialize_result(&result, resultSession, resultMessage);
    callResult = querySource(&source, &result);
    CHECK(callResult == (initializeCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK
        ? CF7_AUDIO_BRIDGE_V2_RESULT_OK
        : CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY));
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME);
    CHECK(strcmp(resultSession, currentSession) == 0);
    CHECK(strcmp(sourceSession, currentSession) == 0);

    memset(&counters, 0, sizeof(counters));
    memset(counterSession, 0, sizeof(counterSession));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(counters);
    counters.audioSessionId = output_utf8(counterSession, sizeof(counterSession));
    initialize_result(&result, resultSession, resultMessage);
    callResult = queryCounters(&counters, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_QUERY_RUNTIME);
    CHECK(strcmp(resultSession, currentSession) == 0);

    memset(&gain, 0, sizeof(gain));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(gain);
    gain.audioSessionId = input_utf8(staleSession);
    gain.audioReadyGeneration = 1u;
    gain.operation = CF7_AUDIO_BRIDGE_V2_OPERATION_SET_MASTER_GAIN;
    gain.gain = 0.25f;
    initialize_result(&result, resultSession, resultMessage);
    callResult = setGain(&gain, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_STALE_GENERATION);
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_SET_MASTER_GAIN);
    CHECK(strcmp(resultSession, currentSession) == 0);
    CHECK(result.audioReadyGeneration == 1u);

    memset(&runtimeProbe, 0, sizeof(runtimeProbe));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(runtimeProbe);
    runtimeProbe.normalizedPath = input_utf16(L"");
    runtimeProbe.first64kSha256 = input_utf8("");
    runtimeProbe.capabilityDigestSha256 = input_utf8("");
    initialize_probe_result(&probe, probeSession, probeMessage);
    initialize_result(&result, resultSession, resultMessage);
    callResult = probeRuntime(&runtimeProbe, &probe, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH);
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
    CHECK(probe.structuredResult.operation ==
        CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
    CHECK(strcmp(resultSession, currentSession) == 0);
    CHECK(strcmp(probeSession, currentSession) == 0);
    CHECK(result.audioReadyGeneration == 1u);
    CHECK(probe.structuredResult.audioReadyGeneration == 1u);
    CHECK(result.deviceGeneration == deviceGeneration);
    CHECK(probe.structuredResult.deviceGeneration == deviceGeneration);

    memset(&offlineProbe, 0, sizeof(offlineProbe));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(offlineProbe);
    offlineProbe.normalizedPath = input_utf16(L"");
    offlineProbe.fullSha256 = input_utf8("");
    offlineProbe.capabilityDigestSha256 = input_utf8("");
    initialize_probe_result(&probe, probeSession, probeMessage);
    initialize_result(&result, resultSession, resultMessage);
    callResult = probeOffline(&offlineProbe, &probe, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_ABI_MISMATCH);
    CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE);
    CHECK(probe.structuredResult.operation ==
        CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE);
    CHECK(strcmp(resultSession, currentSession) == 0);
    CHECK(strcmp(probeSession, currentSession) == 0);

    memset(&shutdownCommand, 0, sizeof(shutdownCommand));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(shutdownCommand);
    shutdownCommand.audioSessionId = input_utf8(currentSession);
    shutdownCommand.audioReadyGeneration = 1u;

    if (initializeCategory == CF7_AUDIO_BRIDGE_V2_RESULT_OK) {
        memset(fixtureRelative, 0, sizeof(fixtureRelative));
        memset(fixtureFull, 0, sizeof(fixtureFull));
        memset(fixtureDigest, 0, sizeof(fixtureDigest));
        memset(wrongDigest, '0', sizeof(wrongDigest) - 1u);
        wrongDigest[sizeof(wrongDigest) - 1u] = '\0';
        fixtureCreated = write_probe_fixture(
            argv[2],
            fixtureRelative,
            fixtureFull,
            &fixtureSize,
            &fixtureModified,
            fixtureDigest);
        CHECK(fixtureCreated);
        if (fixtureCreated) {
            memset(&bgmCommand, 0, sizeof(bgmCommand));
            CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(bgmCommand);
            bgmCommand.wireRevision = CF7_AUDIO_BRIDGE_V2_WIRE_REVISION;
            bgmCommand.requestId = input_utf8("runtime-contract.bgm.play");
            bgmCommand.audioSessionId = input_utf8(currentSession);
            bgmCommand.audioReadyGeneration = 1u;
            bgmCommand.operation = CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY;
            bgmCommand.normalizedPath = input_utf16(fixtureFull);
            bgmCommand.loop = CF7_AUDIO_BRIDGE_V2_TRUE;
            bgmCommand.volume = 1.0f;
            initialize_result(&result, resultSession, resultMessage);
            callResult = submitBgm(&bgmCommand, &result);
            CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
            CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_PLAY);
            CHECK(result.completionState == CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED);
            CHECK(strcmp(resultSession, currentSession) == 0);

            playbackDeadline = GetTickCount64() + 3000u;
            do {
                memset(&source, 0, sizeof(source));
                memset(sourceSession, 0, sizeof(sourceSession));
                CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(source);
                source.audioSessionId = output_utf8(
                    sourceSession,
                    sizeof(sourceSession));
                initialize_result(
                    &source.startResult,
                    sourceResultSession,
                    sourceResultMessage);
                initialize_result(&result, resultSession, resultMessage);
                sourceCallResult = querySource(&source, &result);

                memset(&meter, 0, sizeof(meter));
                memset(meterSession, 0, sizeof(meterSession));
                CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(meter);
                meter.bus = CF7_AUDIO_BRIDGE_V2_METER_BGM_PRE_MASTER;
                meter.audioSessionId = output_utf8(
                    meterSession,
                    sizeof(meterSession));
                initialize_result(&result, resultSession, resultMessage);
                meterCallResult = queryMeter(&meter, &result);

                playbackObserved =
                    sourceCallResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK &&
                    meterCallResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK &&
                    source.playing == CF7_AUDIO_BRIDGE_V2_TRUE &&
                    source.cursorFrames > 0u &&
                    source.lengthFrames > 0u &&
                    source.startResult.category == CF7_AUDIO_BRIDGE_V2_RESULT_OK &&
                    source.startResult.completionState ==
                        CF7_AUDIO_BRIDGE_V2_COMPLETION_STARTED &&
                    meter.frameCount > 0u &&
                    (meter.peakLeft > 0.0f || meter.peakRight > 0.0f) &&
                    (meter.rmsLeft > 0.0f || meter.rmsRight > 0.0f);
                if (!playbackObserved) {
                    Sleep(10u);
                }
            } while (!playbackObserved && GetTickCount64() < playbackDeadline);
            if (!playbackObserved) {
                fprintf(
                    stderr,
                    "BGM playback diagnostic sourceCategory=%u meterCategory=%u playing=%u cursor=%llu length=%llu frames=%llu peak=(%.6f,%.6f) rms=(%.6f,%.6f)\n",
                    sourceCallResult,
                    meterCallResult,
                    source.playing,
                    (unsigned long long)source.cursorFrames,
                    (unsigned long long)source.lengthFrames,
                    (unsigned long long)meter.frameCount,
                    meter.peakLeft,
                    meter.peakRight,
                    meter.rmsLeft,
                    meter.rmsRight);
            }
            CHECK(playbackObserved);
            CHECK(strcmp(sourceSession, currentSession) == 0);
            CHECK(strcmp(meterSession, currentSession) == 0);
            CHECK(source.audioReadyGeneration == 1u);
            CHECK(source.deviceGeneration == deviceGeneration);
            CHECK(meter.audioReadyGeneration == 1u);
            CHECK(meter.deviceGeneration == deviceGeneration);

            bgmCommand.requestId = input_utf8("runtime-contract.bgm.stop");
            bgmCommand.operation = CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_STOP;
            bgmCommand.normalizedPath = input_utf16(L"");
            bgmCommand.loop = CF7_AUDIO_BRIDGE_V2_FALSE;
            initialize_result(&result, resultSession, resultMessage);
            callResult = submitBgm(&bgmCommand, &result);
            CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
            CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_BGM_STOP);
            CHECK(result.completionState == CF7_AUDIO_BRIDGE_V2_COMPLETION_STOPPED);
            CHECK(strcmp(resultSession, currentSession) == 0);

            memset(&runtimeProbe, 0, sizeof(runtimeProbe));
            CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(runtimeProbe);
            runtimeProbe.normalizedPath = input_utf16(fixtureFull);
            runtimeProbe.fileSizeBytes = fixtureSize;
            runtimeProbe.modifiedTimeUnixMilliseconds = fixtureModified;
            runtimeProbe.first64kSha256 = input_utf8(fixtureDigest);
            runtimeProbe.capabilityDigestSha256 = input_utf8(capabilityDigest);
            runtimeProbe.probeContractRevision =
                CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION;
            runtimeProbe.maxWallMs =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_WALL_MS;
            runtimeProbe.maxDecodedFrames =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES;
            runtimeProbe.maxInputBytes =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES;
            runtimeProbe.maxFileBytes =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_FILE_BYTES;
            runtimeProbe.stableObservationCount =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_OBSERVATIONS;
            runtimeProbe.stableIntervalMs =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS;

            runtimeProbe.modifiedTimeUnixMilliseconds = fixtureModified + 1;
            initialize_probe_result(&probe, probeSession, probeMessage);
            initialize_result(&result, resultSession, resultMessage);
            callResult = probeRuntime(&runtimeProbe, &probe, &result);
            CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_THROTTLED);
            CHECK(result.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(probe.structuredResult.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(strcmp(resultMessage, "audio.probe.runtime.unstable_input") == 0);
            CHECK(strcmp(probeMessage, resultMessage) == 0);
            CHECK(strcmp(resultSession, currentSession) == 0);
            CHECK(strcmp(probeSession, currentSession) == 0);

            runtimeProbe.modifiedTimeUnixMilliseconds = fixtureModified;
            runtimeProbe.first64kSha256 = input_utf8(wrongDigest);
            initialize_probe_result(&probe, probeSession, probeMessage);
            initialize_result(&result, resultSession, resultMessage);
            callResult = probeRuntime(&runtimeProbe, &probe, &result);
            CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_THROTTLED);
            CHECK(result.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(probe.structuredResult.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(strcmp(resultMessage, "audio.probe.runtime.content_changed") == 0);
            CHECK(strcmp(probeMessage, resultMessage) == 0);
            CHECK(strcmp(resultSession, currentSession) == 0);
            CHECK(strcmp(probeSession, currentSession) == 0);

            runtimeProbe.first64kSha256 = input_utf8(fixtureDigest);
            initialize_probe_result(&probe, probeSession, probeMessage);
            initialize_result(&result, resultSession, resultMessage);
            callResult = probeRuntime(&runtimeProbe, &probe, &result);
            if (callResult != CF7_AUDIO_BRIDGE_V2_RESULT_OK) {
                fprintf(
                    stderr,
                    "runtime probe diagnostic category=%u stage=%u ma=%d message=%s outcome=%u\n",
                    result.category,
                    result.stage,
                    result.rawMaResult,
                    resultMessage,
                    probe.outcome);
            }
            CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
            CHECK(result.category == callResult);
            CHECK(result.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(probe.structuredResult.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(probe.outcome ==
                CF7_AUDIO_BRIDGE_V2_PROBE_COMPATIBLE_SIGNAL_PRESENT);
            CHECK(probe.eofState == CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED);
            CHECK(probe.frames > 0u &&
                probe.frames <= CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES);
            CHECK(probe.peak > 0.0);
            CHECK(probe.rms > 0.0);
            CHECK(probe.inputBytesRead > 0u &&
                probe.inputBytesRead <=
                    CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES);
            CHECK(probe.elapsedMs <
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS);
            CHECK(strcmp(resultSession, currentSession) == 0);
            CHECK(strcmp(probeSession, currentSession) == 0);
            CHECK(result.audioReadyGeneration == 1u);
            CHECK(probe.structuredResult.audioReadyGeneration == 1u);
            CHECK(result.deviceGeneration == deviceGeneration);
            CHECK(probe.structuredResult.deviceGeneration == deviceGeneration);

            memset(&offlineProbe, 0, sizeof(offlineProbe));
            CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(offlineProbe);
            offlineProbe.normalizedPath = input_utf16(fixtureFull);
            offlineProbe.fullSha256 = input_utf8(fixtureDigest);
            offlineProbe.capabilityDigestSha256 = input_utf8(capabilityDigest);
            offlineProbe.probeContractRevision =
                CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION;
            offlineProbe.maxWallMs =
                CF7_AUDIO_BRIDGE_V2_OFFLINE_PROBE_MAX_WALL_MS;
            initialize_probe_result(&probe, probeSession, probeMessage);
            initialize_result(&result, resultSession, resultMessage);
            callResult = probeOffline(&offlineProbe, &probe, &result);
            if (callResult != CF7_AUDIO_BRIDGE_V2_RESULT_OK) {
                fprintf(
                    stderr,
                    "offline probe diagnostic category=%u stage=%u ma=%d message=%s outcome=%u eof=%u\n",
                    result.category,
                    result.stage,
                    result.rawMaResult,
                    resultMessage,
                    probe.outcome,
                    probe.eofState);
            }
            CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
            CHECK(result.category == callResult);
            CHECK(result.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE);
            CHECK(probe.structuredResult.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE);
            CHECK(probe.outcome ==
                CF7_AUDIO_BRIDGE_V2_PROBE_QUALIFICATION_PASSED);
            CHECK(probe.eofState == CF7_AUDIO_BRIDGE_V2_EOF_REACHED);
            CHECK(probe.frames == 960u);
            CHECK(probe.peak > 0.0);
            CHECK(probe.rms > 0.0);
            CHECK(probe.nonFiniteCount == 0u);
            CHECK(strcmp(resultSession, currentSession) == 0);
            CHECK(strcmp(probeSession, currentSession) == 0);
            CHECK(result.audioReadyGeneration == 1u);
            CHECK(probe.structuredResult.audioReadyGeneration == 1u);
            CHECK(result.deviceGeneration == deviceGeneration);
            CHECK(probe.structuredResult.deviceGeneration == deviceGeneration);
        }

        memset(largeWavRelative, 0, sizeof(largeWavRelative));
        memset(largeWavFull, 0, sizeof(largeWavFull));
        memset(largeWavDigest, 0, sizeof(largeWavDigest));
        largeWavFixtureCreated = write_large_wav_probe_fixture(
            argv[2],
            largeWavRelative,
            largeWavFull,
            &largeWavSize,
            &largeWavModified,
            largeWavDigest);
        CHECK(largeWavFixtureCreated);
        if (largeWavFixtureCreated) {
            memset(&runtimeProbe, 0, sizeof(runtimeProbe));
            CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(runtimeProbe);
            runtimeProbe.normalizedPath = input_utf16(largeWavFull);
            runtimeProbe.fileSizeBytes = largeWavSize;
            runtimeProbe.modifiedTimeUnixMilliseconds = largeWavModified;
            runtimeProbe.first64kSha256 = input_utf8(largeWavDigest);
            runtimeProbe.capabilityDigestSha256 = input_utf8(capabilityDigest);
            runtimeProbe.probeContractRevision =
                CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION;
            runtimeProbe.maxWallMs =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_WALL_MS;
            runtimeProbe.maxDecodedFrames =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES;
            runtimeProbe.maxInputBytes =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES;
            runtimeProbe.maxFileBytes =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_FILE_BYTES;
            runtimeProbe.stableObservationCount =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_OBSERVATIONS;
            runtimeProbe.stableIntervalMs =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS;
            initialize_probe_result(&probe, probeSession, probeMessage);
            initialize_result(&result, resultSession, resultMessage);
            callResult = probeRuntime(&runtimeProbe, &probe, &result);
            if (callResult != CF7_AUDIO_BRIDGE_V2_RESULT_OK ||
                probe.outcome !=
                    CF7_AUDIO_BRIDGE_V2_PROBE_COMPATIBLE_SIGNAL_PRESENT) {
                fprintf(
                    stderr,
                    "large WAV probe diagnostic category=%u stage=%u ma=%d message=%s outcome=%u frames=%llu inputBytes=%llu elapsedMs=%u\n",
                    result.category,
                    result.stage,
                    result.rawMaResult,
                    resultMessage,
                    probe.outcome,
                    (unsigned long long)probe.frames,
                    (unsigned long long)probe.inputBytesRead,
                    probe.elapsedMs);
            }
            CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
            CHECK(result.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(probe.structuredResult.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(probe.outcome ==
                CF7_AUDIO_BRIDGE_V2_PROBE_COMPATIBLE_SIGNAL_PRESENT);
            CHECK(probe.frames ==
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES);
            CHECK(probe.inputBytesRead > 0u &&
                probe.inputBytesRead <
                    CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES);
            CHECK(probe.elapsedMs <
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS);
            CHECK(strcmp(
                resultMessage,
                "audio.probe.runtime.compatible_signal") == 0);
            CHECK(strcmp(probeMessage, resultMessage) == 0);
            CHECK(strcmp(resultSession, currentSession) == 0);
            CHECK(strcmp(probeSession, currentSession) == 0);
            CHECK(result.audioReadyGeneration == 1u);
            CHECK(probe.structuredResult.audioReadyGeneration == 1u);
            CHECK(result.deviceGeneration == deviceGeneration);
            CHECK(probe.structuredResult.deviceGeneration == deviceGeneration);
            CHECK(DeleteFileW(largeWavFull) != FALSE);
            largeWavFixtureCreated = 0;
        }

        memset(mfBoundRelative, 0, sizeof(mfBoundRelative));
        memset(mfBoundFull, 0, sizeof(mfBoundFull));
        memset(mfBoundDigest, 0, sizeof(mfBoundDigest));
        mfBoundFixtureCreated = write_mf_input_bound_fixture(
            argv[2],
            mfBoundExpectCompatible ? argv[3] : NULL,
            mfBoundRelative,
            mfBoundFull,
            &mfBoundSize,
            &mfBoundModified,
            mfBoundDigest);
        CHECK(mfBoundFixtureCreated);
        if (mfBoundFixtureCreated) {
            memset(&runtimeProbe, 0, sizeof(runtimeProbe));
            CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(runtimeProbe);
            runtimeProbe.normalizedPath = input_utf16(mfBoundFull);
            runtimeProbe.fileSizeBytes = mfBoundSize;
            runtimeProbe.modifiedTimeUnixMilliseconds = mfBoundModified;
            runtimeProbe.first64kSha256 = input_utf8(mfBoundDigest);
            runtimeProbe.capabilityDigestSha256 = input_utf8(capabilityDigest);
            runtimeProbe.probeContractRevision =
                CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION;
            runtimeProbe.maxWallMs =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_WALL_MS;
            runtimeProbe.maxDecodedFrames =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES;
            runtimeProbe.maxInputBytes =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES;
            runtimeProbe.maxFileBytes =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_FILE_BYTES;
            runtimeProbe.stableObservationCount =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_OBSERVATIONS;
            runtimeProbe.stableIntervalMs =
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS;
            initialize_probe_result(&probe, probeSession, probeMessage);
            initialize_result(&result, resultSession, resultMessage);
            callResult = probeRuntime(&runtimeProbe, &probe, &result);
            CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
            CHECK(result.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(probe.structuredResult.operation ==
                CF7_AUDIO_BRIDGE_V2_OPERATION_RUNTIME_PROBE);
            CHECK(probe.outcome == (mfBoundExpectCompatible
                ? CF7_AUDIO_BRIDGE_V2_PROBE_COMPATIBLE_SIGNAL_PRESENT
                : CF7_AUDIO_BRIDGE_V2_PROBE_INCONCLUSIVE_TIMEOUT_NOT_UNSUPPORTED));
            CHECK(probe.eofState == CF7_AUDIO_BRIDGE_V2_EOF_NOT_REQUIRED);
            CHECK(probe.frames == (mfBoundExpectCompatible
                ? CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES
                : 0u));
            CHECK(probe.inputBytesRead ==
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES);
            CHECK(probe.elapsedMs <
                CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS);
            CHECK(strcmp(
                resultMessage,
                mfBoundExpectCompatible
                    ? "audio.probe.runtime.compatible_signal"
                    : "audio.probe.runtime.input_bound_exceeded") == 0);
            CHECK(strcmp(probeMessage, resultMessage) == 0);
            CHECK(strcmp(resultSession, currentSession) == 0);
            CHECK(strcmp(probeSession, currentSession) == 0);
            CHECK(result.audioReadyGeneration == 1u);
            CHECK(probe.structuredResult.audioReadyGeneration == 1u);
            CHECK(result.deviceGeneration == deviceGeneration);
            CHECK(probe.structuredResult.deviceGeneration == deviceGeneration);
            CHECK(DeleteFileW(mfBoundFull) != FALSE);
            mfBoundFixtureCreated = 0;
        }

        memset(cancelRelative, 0, sizeof(cancelRelative));
        memset(cancelFull, 0, sizeof(cancelFull));
        cancelFixtureCreated = write_sparse_fixture(
            argv[2],
            cancelRelative,
            cancelFull,
            UINT64_C(1073741824));
        CHECK(cancelFixtureCreated);
        if (cancelFixtureCreated) {
            memset(&cancelProbe, 0, sizeof(cancelProbe));
            CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(cancelProbe);
            cancelProbe.normalizedPath = input_utf16(cancelFull);
            cancelProbe.fullSha256 = input_utf8(wrongDigest);
            cancelProbe.capabilityDigestSha256 = input_utf8(capabilityDigest);
            cancelProbe.probeContractRevision =
                CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION;
            cancelProbe.maxWallMs =
                CF7_AUDIO_BRIDGE_V2_OFFLINE_PROBE_MAX_WALL_MS;
            initialize_probe_result(
                &cancelProbeResult,
                cancelProbeSession,
                cancelProbeMessage);
            initialize_result(
                &cancelResult,
                cancelResultSession,
                cancelResultMessage);
            probeEnteredEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
            CHECK(probeEnteredEvent != NULL);
            if (probeEnteredEvent != NULL) {
                memset(&probeThreadContext, 0, sizeof(probeThreadContext));
                probeThreadContext.function = probeOffline;
                probeThreadContext.command = &cancelProbe;
                probeThreadContext.probe = &cancelProbeResult;
                probeThreadContext.result = &cancelResult;
                probeThreadContext.enteredEvent = probeEnteredEvent;
                probeThread = CreateThread(
                    NULL,
                    0u,
                    probe_thread_main,
                    &probeThreadContext,
                    0u,
                    NULL);
                CHECK(probeThread != NULL);
            }
            if (probeThread != NULL) {
                CHECK(WaitForSingleObject(
                    probeEnteredEvent,
                    1000u) == WAIT_OBJECT_0);
                Sleep(25u);
                initialize_result(&result, resultSession, resultMessage);
                shutdownStarted = GetTickCount64();
                callResult = shutdown(&shutdownCommand, &result);
                shutdownPerformed = 1;
                CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
                CHECK(result.operation ==
                    CF7_AUDIO_BRIDGE_V2_OPERATION_SHUTDOWN);
                CHECK(strcmp(resultSession, currentSession) == 0);
                CHECK(GetTickCount64() - shutdownStarted < 5000u);
                CHECK(WaitForSingleObject(probeThread, 5000u) == WAIT_OBJECT_0);
                CHECK(probeThreadContext.returnedCategory ==
                    CF7_AUDIO_BRIDGE_V2_RESULT_NOT_READY);
                CHECK(cancelResult.operation ==
                    CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE);
                CHECK(cancelProbeResult.structuredResult.operation ==
                    CF7_AUDIO_BRIDGE_V2_OPERATION_OFFLINE_PROBE);
                CHECK(strcmp(cancelResultMessage, "audio.owner.cancelled") == 0);
                CHECK(strcmp(cancelProbeMessage, cancelResultMessage) == 0);
                CHECK(strcmp(cancelResultSession, currentSession) == 0);
                CHECK(strcmp(cancelProbeSession, currentSession) == 0);
                CHECK(cancelResult.audioReadyGeneration == 1u);
                CHECK(cancelProbeResult.structuredResult.audioReadyGeneration == 1u);
                CHECK(cancelResult.deviceGeneration == deviceGeneration);
                CHECK(cancelProbeResult.structuredResult.deviceGeneration ==
                    deviceGeneration);
                CloseHandle(probeThread);
                probeThread = NULL;
            }
            if (probeEnteredEvent != NULL) {
                CloseHandle(probeEnteredEvent);
                probeEnteredEvent = NULL;
            }
            CHECK(DeleteFileW(cancelFull) != FALSE);
            cancelFixtureCreated = 0;
        }
    }

    if (!shutdownPerformed) {
        initialize_result(&result, resultSession, resultMessage);
        callResult = shutdown(&shutdownCommand, &result);
        CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
        CHECK(result.operation == CF7_AUDIO_BRIDGE_V2_OPERATION_SHUTDOWN);
        CHECK(strcmp(resultSession, currentSession) == 0);
        CHECK(result.audioReadyGeneration == 1u);
    }
    initialize_result(&result, resultSession, resultMessage);
    callResult = shutdown(&shutdownCommand, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);
    CHECK(strcmp(resultSession, currentSession) == 0);

    /*
     * Managed recovery tears down the native owner and initializes again with
     * the same audio session but a new ready generation. Device generation is
     * native lifecycle state, so it must remain monotonic across that fence.
     */
    initializeCommand.audioSessionId = input_utf8(currentSession);
    initializeCommand.audioReadyGeneration = 2u;
    initialize_runtime(
        &runtime,
        runtimeSession,
        runtimeDigest,
        runtimeName,
        runtimeFailureSession,
        runtimeFailureMessage);
    initialize_result(&result, resultSession, resultMessage);
    callResult = initialize(&initializeCommand, &runtime, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK ||
        callResult == CF7_AUDIO_BRIDGE_V2_RESULT_DEVICE_UNAVAILABLE);
    CHECK(strcmp(resultSession, currentSession) == 0);
    CHECK(result.audioReadyGeneration == 2u);
    CHECK(runtime.deviceGeneration == deviceGeneration + 1u);
    CHECK(result.deviceGeneration == runtime.deviceGeneration);

    memset(&shutdownCommand, 0, sizeof(shutdownCommand));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(shutdownCommand);
    shutdownCommand.audioSessionId = input_utf8(currentSession);
    shutdownCommand.audioReadyGeneration = 2u;
    initialize_result(&result, resultSession, resultMessage);
    callResult = shutdown(&shutdownCommand, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);

    /* A genuinely new audio session owns a fresh device-generation domain. */
    initializeCommand.audioSessionId = input_utf8(staleSession);
    initializeCommand.audioReadyGeneration = 1u;
    initialize_runtime(
        &runtime,
        runtimeSession,
        runtimeDigest,
        runtimeName,
        runtimeFailureSession,
        runtimeFailureMessage);
    initialize_result(&result, resultSession, resultMessage);
    callResult = initialize(&initializeCommand, &runtime, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK ||
        callResult == CF7_AUDIO_BRIDGE_V2_RESULT_DEVICE_UNAVAILABLE);
    CHECK(strcmp(resultSession, staleSession) == 0);
    CHECK(result.audioReadyGeneration == 1u);
    CHECK(runtime.deviceGeneration == 1u);
    CHECK(result.deviceGeneration == 1u);

    memset(&shutdownCommand, 0, sizeof(shutdownCommand));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(shutdownCommand);
    shutdownCommand.audioSessionId = input_utf8(staleSession);
    shutdownCommand.audioReadyGeneration = 1u;
    initialize_result(&result, resultSession, resultMessage);
    callResult = shutdown(&shutdownCommand, &result);
    CHECK(callResult == CF7_AUDIO_BRIDGE_V2_RESULT_OK);

    if (fixtureCreated) {
        CHECK(DeleteFileW(fixtureFull) != FALSE);
    }
    if (largeWavFixtureCreated) {
        CHECK(DeleteFileW(largeWavFull) != FALSE);
    }

    CHECK(FreeLibrary(module) != FALSE);
    if (g_failures != 0) {
        fprintf(stderr, "audio bridge v2 runtime contract FAIL checks=%d failures=%d\n",
            g_checks, g_failures);
        return 1;
    }
    printf("audio bridge v2 runtime contract PASS checks=%d initCategory=%u\n",
        g_checks, initializeCategory);
    return 0;
}
