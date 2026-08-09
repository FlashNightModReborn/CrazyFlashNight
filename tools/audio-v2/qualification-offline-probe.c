#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "audio_bridge_v2.h"

typedef uint32_t (__cdecl *query_capability_proc)(cf7_audio_bridge_v2_capability*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *initialize_proc)(const cf7_audio_bridge_v2_initialize_command*, cf7_audio_bridge_v2_runtime_snapshot*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *probe_offline_proc)(const cf7_audio_bridge_v2_offline_probe_command*, cf7_audio_bridge_v2_probe_result*, cf7_audio_bridge_v2_result*);
typedef uint32_t (__cdecl *shutdown_proc)(const cf7_audio_bridge_v2_shutdown_command*, cf7_audio_bridge_v2_result*);

static cf7_audio_bridge_v2_utf8_buffer input_utf8(const char* value)
{
    cf7_audio_bridge_v2_utf8_buffer buffer;
    size_t length = strlen(value);
    memset(&buffer, 0, sizeof(buffer));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(buffer);
    buffer.dataAddress = (uint64_t)(uintptr_t)value;
    buffer.capacityBytes = (uint32_t)length + 1u;
    buffer.lengthBytes = (uint32_t)length;
    buffer.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY;
    return buffer;
}

static cf7_audio_bridge_v2_utf16_buffer input_utf16(const wchar_t* value)
{
    cf7_audio_bridge_v2_utf16_buffer buffer;
    size_t length = wcslen(value);
    memset(&buffer, 0, sizeof(buffer));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(buffer);
    buffer.dataAddress = (uint64_t)(uintptr_t)value;
    buffer.capacityCodeUnits = (uint32_t)length + 1u;
    buffer.lengthCodeUnits = (uint32_t)length;
    buffer.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY;
    return buffer;
}

static cf7_audio_bridge_v2_utf8_buffer output_utf8(char* value, uint32_t capacity)
{
    cf7_audio_bridge_v2_utf8_buffer buffer;
    memset(&buffer, 0, sizeof(buffer));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(buffer);
    buffer.dataAddress = (uint64_t)(uintptr_t)value;
    buffer.capacityBytes = capacity;
    buffer.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY;
    return buffer;
}

static cf7_audio_bridge_v2_utf16_buffer output_utf16(wchar_t* value, uint32_t capacity)
{
    cf7_audio_bridge_v2_utf16_buffer buffer;
    memset(&buffer, 0, sizeof(buffer));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(buffer);
    buffer.dataAddress = (uint64_t)(uintptr_t)value;
    buffer.capacityCodeUnits = capacity;
    buffer.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY;
    return buffer;
}

static void initialize_result(cf7_audio_bridge_v2_result* result, char* session, char* message)
{
    memset(result, 0, sizeof(*result));
    memset(session, 0, 64u);
    memset(message, 0, 256u);
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(*result);
    result->audioSessionId = output_utf8(session, 64u);
    result->messageKey = output_utf8(message, 256u);
}

static void initialize_runtime(
    cf7_audio_bridge_v2_runtime_snapshot* runtime,
    char* session,
    char* digest,
    wchar_t* name,
    char* failureSession,
    char* failureMessage)
{
    memset(runtime, 0, sizeof(*runtime));
    memset(session, 0, 64u);
    memset(digest, 0, 80u);
    memset(name, 0, sizeof(wchar_t) * 512u);
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(*runtime);
    runtime->audioSessionId = output_utf8(session, 64u);
    runtime->selectedDeviceIdDigest = output_utf8(digest, 80u);
    runtime->selectedDeviceName = output_utf16(name, 512u);
    initialize_result(&runtime->lastStructuredFailure, failureSession, failureMessage);
}

static void initialize_probe(cf7_audio_bridge_v2_probe_result* probe, char* session, char* message)
{
    memset(probe, 0, sizeof(*probe));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(*probe);
    initialize_result(&probe->structuredResult, session, message);
}

static FARPROC required_export(HMODULE module, const char* name)
{
    FARPROC address = GetProcAddress(module, name);
    if (address == NULL) {
        fprintf(stderr, "missing export %s\n", name);
        ExitProcess(11u);
    }
    return address;
}

static wchar_t* utf8_to_wide(const char* value)
{
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
    wchar_t* converted;
    if (count <= 0) return NULL;
    converted = (wchar_t*)calloc((size_t)count, sizeof(wchar_t));
    if (converted == NULL) return NULL;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, converted, count) != count) {
        free(converted);
        return NULL;
    }
    return converted;
}

static wchar_t* joined_path(const wchar_t* root, const wchar_t* relative)
{
    size_t rootLength = wcslen(root);
    size_t relativeLength = wcslen(relative);
    wchar_t* result = (wchar_t*)calloc(rootLength + relativeLength + 2u, sizeof(wchar_t));
    size_t index;
    if (result == NULL) return NULL;
    memcpy(result, root, rootLength * sizeof(wchar_t));
    if (rootLength > 0u && root[rootLength - 1u] != L'\\' && root[rootLength - 1u] != L'/') result[rootLength++] = L'\\';
    for (index = 0u; index < relativeLength; ++index) result[rootLength + index] = relative[index] == L'/' ? L'\\' : relative[index];
    return result;
}

int wmain(int argc, wchar_t** argv)
{
    static const char sessionId[] = "417f4407-9dce-4f3f-b1f0-87d497b31c91";
    HMODULE module;
    query_capability_proc queryCapability;
    initialize_proc initialize;
    probe_offline_proc probeOffline;
    shutdown_proc shutdown;
    cf7_audio_bridge_v2_capability capability;
    cf7_audio_bridge_v2_initialize_command initializeCommand;
    cf7_audio_bridge_v2_runtime_snapshot runtime;
    cf7_audio_bridge_v2_shutdown_command shutdownCommand;
    cf7_audio_bridge_v2_result callResult;
    char capabilityBuild[256], capabilityDigest[80];
    char resultSession[64], resultMessage[256];
    char runtimeSession[64], runtimeDigest[80], runtimeFailureSession[64], runtimeFailureMessage[256];
    wchar_t runtimeName[512];
    FILE* inventory;
    char line[32768];
    unsigned long index = 0u;
    uint32_t category;

    if (argc != 4) {
        fputs("usage: qualification-offline-probe <dll> <base-root> <inventory-tsv>\n", stderr);
        return 2;
    }
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    module = LoadLibraryExW(argv[1], NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (module == NULL) return 10;
    queryCapability = (query_capability_proc)required_export(module, "cf7_audio_bridge_v2_query_capability");
    initialize = (initialize_proc)required_export(module, "cf7_audio_bridge_v2_initialize");
    probeOffline = (probe_offline_proc)required_export(module, "cf7_audio_bridge_v2_probe_offline_qualification");
    shutdown = (shutdown_proc)required_export(module, "cf7_audio_bridge_v2_shutdown");

    memset(&capability, 0, sizeof(capability));
    memset(capabilityBuild, 0, sizeof(capabilityBuild));
    memset(capabilityDigest, 0, sizeof(capabilityDigest));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(capability);
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(capability.abiVersion);
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(capability.miniaudioVersion);
    capability.bridgeBuildId = output_utf8(capabilityBuild, (uint32_t)sizeof(capabilityBuild));
    capability.capabilityDigestSha256 = output_utf8(capabilityDigest, (uint32_t)sizeof(capabilityDigest));
    initialize_result(&callResult, resultSession, resultMessage);
    category = queryCapability(&capability, &callResult);
    if (category != CF7_AUDIO_BRIDGE_V2_RESULT_OK || capability.testOnlyNullEnabled != CF7_AUDIO_BRIDGE_V2_FALSE ||
        capability.compiledBackendMask != CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_PRODUCTION ||
        capability.supportsOfflineQualificationProbe != CF7_AUDIO_BRIDGE_V2_TRUE || strlen(capabilityDigest) != 64u) return 12;

    memset(&initializeCommand, 0, sizeof(initializeCommand));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(initializeCommand);
    initializeCommand.normalizedBasePath = input_utf16(argv[2]);
    initializeCommand.audioSessionId = input_utf8(sessionId);
    initializeCommand.audioReadyGeneration = 1u;
    initializeCommand.executionIdentity = CF7_AUDIO_BRIDGE_V2_EXECUTION_PRODUCTION;
    initialize_runtime(&runtime, runtimeSession, runtimeDigest, runtimeName, runtimeFailureSession, runtimeFailureMessage);
    initialize_result(&callResult, resultSession, resultMessage);
    category = initialize(&initializeCommand, &runtime, &callResult);
    if (category != CF7_AUDIO_BRIDGE_V2_RESULT_OK || runtime.audioStatus != CF7_AUDIO_BRIDGE_V2_AUDIO_READY ||
        runtime.selectedBackend < CF7_AUDIO_BRIDGE_V2_BACKEND_WASAPI || runtime.selectedBackend > CF7_AUDIO_BRIDGE_V2_BACKEND_WINMM ||
        runtime.selectedBackend == CF7_AUDIO_BRIDGE_V2_BACKEND_TEST_ONLY_NULL || strlen(runtimeDigest) != 64u ||
        runtime.sampleRate == 0u || runtime.channels == 0u) {
        FreeLibrary(module);
        return 13;
    }

    printf("CF7_AUDIO_V2_OFFLINE_PROBE_V1\n");
    printf("runtime\t%u\t%llu\t%u\t%u\t%s\n", runtime.selectedBackend,
        (unsigned long long)runtime.deviceGeneration, runtime.sampleRate, runtime.channels, runtimeDigest);
    inventory = _wfopen(argv[3], L"rb");
    if (inventory == NULL) return 14;
    while (fgets(line, (int)sizeof(line), inventory) != NULL) {
        char* tab;
        char* newline;
        char* relativeUtf8 = line;
        char* digest;
        wchar_t* relativeWide;
        wchar_t* fullPath;
        cf7_audio_bridge_v2_offline_probe_command command;
        cf7_audio_bridge_v2_probe_result probe;
        char probeSession[64], probeMessage[256];
        newline = strchr(line, '\n');
        if (newline == NULL || newline[1] != '\0' || (newline > line && newline[-1] == '\r')) return 15;
        *newline = '\0';
        tab = strchr(line, '\t');
        if (tab == NULL || strchr(tab + 1, '\t') != NULL) return 15;
        *tab = '\0';
        digest = tab + 1;
        if (strlen(relativeUtf8) == 0u || strlen(digest) != 64u) return 15;
        relativeWide = utf8_to_wide(relativeUtf8);
        fullPath = relativeWide == NULL ? NULL : joined_path(argv[2], relativeWide);
        if (fullPath == NULL) return 16;
        memset(&command, 0, sizeof(command));
        CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(command);
        command.normalizedPath = input_utf16(fullPath);
        command.fullSha256 = input_utf8(digest);
        command.capabilityDigestSha256 = input_utf8(capabilityDigest);
        command.probeContractRevision = CF7_AUDIO_BRIDGE_V2_PROBE_CONTRACT_REVISION;
        command.maxWallMs = CF7_AUDIO_BRIDGE_V2_OFFLINE_PROBE_MAX_WALL_MS;
        initialize_probe(&probe, probeSession, probeMessage);
        initialize_result(&callResult, resultSession, resultMessage);
        category = probeOffline(&command, &probe, &callResult);
        printf("asset\t%lu\t%u\t%u\t%u\t%llu\t%.17g\t%.17g\t%.17g\t%llu\t%llu\t%llu\t%u\t%llu\n",
            index, category, probe.outcome, probe.eofState, (unsigned long long)probe.frames,
            probe.durationSeconds, probe.peak, probe.rms,
            (unsigned long long)probe.leadingSilenceFrames, (unsigned long long)probe.trailingSilenceFrames,
            (unsigned long long)probe.nonFiniteCount, probe.elapsedMs, (unsigned long long)probe.inputBytesRead);
        free(fullPath);
        free(relativeWide);
        ++index;
    }
    if (ferror(inventory) != 0) return 17;
    fclose(inventory);

    memset(&shutdownCommand, 0, sizeof(shutdownCommand));
    CF7_AUDIO_BRIDGE_V2_INIT_STRUCT(shutdownCommand);
    shutdownCommand.audioSessionId = input_utf8(sessionId);
    shutdownCommand.audioReadyGeneration = 1u;
    initialize_result(&callResult, resultSession, resultMessage);
    category = shutdown(&shutdownCommand, &callResult);
    if (category != CF7_AUDIO_BRIDGE_V2_RESULT_OK || !FreeLibrary(module)) return 18;
    printf("complete\t%lu\n", index);
    return 0;
}
