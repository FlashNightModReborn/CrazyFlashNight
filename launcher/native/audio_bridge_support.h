#ifndef CF7_AUDIO_BRIDGE_SUPPORT_H
#define CF7_AUDIO_BRIDGE_SUPPORT_H

#include "audio_bridge_v2.h"

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cf7_audio_bridge_support_sniff {
    uint64_t decoder;
    uint64_t container;
    uint64_t codec;
} cf7_audio_bridge_support_sniff;

int cf7_audio_bridge_support_prefix_valid(
    const void* value,
    uint32_t minimumSize);

int cf7_audio_bridge_support_read_utf8(
    const cf7_audio_bridge_v2_utf8_buffer* buffer,
    char** valueOut);

int cf7_audio_bridge_support_read_utf16(
    const cf7_audio_bridge_v2_utf16_buffer* buffer,
    wchar_t** valueOut);

int cf7_audio_bridge_support_write_utf8(
    cf7_audio_bridge_v2_utf8_buffer* buffer,
    const char* value);

int cf7_audio_bridge_support_write_utf16(
    cf7_audio_bridge_v2_utf16_buffer* buffer,
    const wchar_t* value);

void cf7_audio_bridge_support_free(void* value);

int cf7_audio_bridge_support_sha256(
    const void* bytes,
    size_t byteCount,
    char hexOut[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY]);

int cf7_audio_bridge_support_sha256_handle(
    HANDLE file,
    uint64_t maximumBytes,
    char hexOut[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY],
    uint64_t* bytesReadOut);

int cf7_audio_bridge_support_utf8_from_utf16(
    const wchar_t* value,
    char** valueOut);

int cf7_audio_bridge_support_utf16_from_utf8(
    const char* value,
    wchar_t** valueOut);

int cf7_audio_bridge_support_resolve_base(
    const wchar_t* inputPath,
    wchar_t** finalPathOut,
    DWORD* windowsErrorOut);

int cf7_audio_bridge_support_resolve_file(
    const wchar_t* finalBasePath,
    const wchar_t* inputPath,
    wchar_t** finalPathOut,
    uint64_t* fileSizeOut,
    int64_t* modifiedUnixMillisecondsOut,
    DWORD* windowsErrorOut);

int cf7_audio_bridge_support_sniff_file(
    const wchar_t* path,
    cf7_audio_bridge_support_sniff* sniffOut,
    char first64kSha256Out[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY],
    DWORD* windowsErrorOut);

#ifdef __cplusplus
}
#endif

#endif
