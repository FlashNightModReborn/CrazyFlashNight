#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "audio_bridge_support.h"

#include <bcrypt.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define CF7_FILETIME_UNIX_EPOCH_TICKS UINT64_C(116444736000000000)
#define CF7_FILETIME_TICKS_PER_MILLISECOND UINT64_C(10000)
#define CF7_SNIFF_BYTES ((DWORD)65536u)

static int cf7_is_high_surrogate(wchar_t value)
{
    return value >= (wchar_t)0xD800 && value <= (wchar_t)0xDBFF;
}

static int cf7_is_low_surrogate(wchar_t value)
{
    return value >= (wchar_t)0xDC00 && value <= (wchar_t)0xDFFF;
}

static int cf7_utf16_is_well_formed(const wchar_t* value, size_t length)
{
    size_t index;
    for (index = 0u; index < length; ++index) {
        if (cf7_is_high_surrogate(value[index])) {
            if (index + 1u >= length || !cf7_is_low_surrogate(value[index + 1u])) {
                return 0;
            }
            ++index;
        } else if (cf7_is_low_surrogate(value[index])) {
            return 0;
        }
    }
    return 1;
}

int cf7_audio_bridge_support_prefix_valid(const void* value, uint32_t minimumSize)
{
    const cf7_audio_bridge_v2_struct_header* header;
    if (value == NULL) {
        return 0;
    }
    header = (const cf7_audio_bridge_v2_struct_header*)value;
    return header->structSize >= minimumSize &&
        header->abiMajor == CF7_AUDIO_BRIDGE_V2_ABI_MAJOR &&
        header->abiMinor <= CF7_AUDIO_BRIDGE_V2_ABI_MINOR;
}

int cf7_audio_bridge_support_read_utf8(
    const cf7_audio_bridge_v2_utf8_buffer* buffer,
    char** valueOut)
{
    const char* source;
    char* copy;
    int convertedLength;
    wchar_t* validation;

    if (valueOut == NULL) {
        return 0;
    }
    *valueOut = NULL;
    if (!cf7_audio_bridge_support_prefix_valid(buffer, (uint32_t)sizeof(*buffer)) ||
        buffer->flags != CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY ||
        buffer->requiredBytes != 0u ||
        (buffer->dataAddress == 0u &&
            (buffer->capacityBytes != 0u || buffer->lengthBytes != 0u)) ||
        (buffer->dataAddress != 0u &&
            (buffer->capacityBytes == 0u || buffer->lengthBytes >= buffer->capacityBytes))) {
        return 0;
    }
    if (buffer->dataAddress == 0u) {
        copy = (char*)malloc(1u);
        if (copy == NULL) {
            return 0;
        }
        copy[0] = '\0';
        *valueOut = copy;
        return 1;
    }

    source = (const char*)(uintptr_t)buffer->dataAddress;
    if (source[buffer->lengthBytes] != '\0' ||
        memchr(source, '\0', buffer->lengthBytes) != NULL ||
        buffer->lengthBytes > (uint32_t)INT_MAX) {
        return 0;
    }
    convertedLength = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        source,
        (int)buffer->lengthBytes,
        NULL,
        0);
    if (buffer->lengthBytes != 0u && convertedLength <= 0) {
        return 0;
    }
    validation = (wchar_t*)malloc(((size_t)convertedLength + 1u) * sizeof(wchar_t));
    if (validation == NULL) {
        return 0;
    }
    if (convertedLength > 0 && MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            source,
            (int)buffer->lengthBytes,
            validation,
            convertedLength) != convertedLength) {
        free(validation);
        return 0;
    }
    free(validation);

    copy = (char*)malloc((size_t)buffer->lengthBytes + 1u);
    if (copy == NULL) {
        return 0;
    }
    memcpy(copy, source, (size_t)buffer->lengthBytes + 1u);
    *valueOut = copy;
    return 1;
}

int cf7_audio_bridge_support_read_utf16(
    const cf7_audio_bridge_v2_utf16_buffer* buffer,
    wchar_t** valueOut)
{
    const wchar_t* source;
    wchar_t* copy;
    size_t byteCount;
    if (valueOut == NULL) {
        return 0;
    }
    *valueOut = NULL;
    if (!cf7_audio_bridge_support_prefix_valid(buffer, (uint32_t)sizeof(*buffer)) ||
        buffer->flags != CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY ||
        buffer->requiredCodeUnits != 0u ||
        (buffer->dataAddress == 0u &&
            (buffer->capacityCodeUnits != 0u || buffer->lengthCodeUnits != 0u)) ||
        (buffer->dataAddress != 0u &&
            (buffer->capacityCodeUnits == 0u ||
                buffer->lengthCodeUnits >= buffer->capacityCodeUnits))) {
        return 0;
    }
    if (buffer->dataAddress == 0u) {
        copy = (wchar_t*)malloc(sizeof(wchar_t));
        if (copy == NULL) {
            return 0;
        }
        copy[0] = L'\0';
        *valueOut = copy;
        return 1;
    }
    source = (const wchar_t*)(uintptr_t)buffer->dataAddress;
    if (source[buffer->lengthCodeUnits] != L'\0' ||
        wmemchr(source, L'\0', buffer->lengthCodeUnits) != NULL ||
        !cf7_utf16_is_well_formed(source, buffer->lengthCodeUnits)) {
        return 0;
    }
    if ((size_t)buffer->lengthCodeUnits > (SIZE_MAX / sizeof(wchar_t)) - 1u) {
        return 0;
    }
    byteCount = ((size_t)buffer->lengthCodeUnits + 1u) * sizeof(wchar_t);
    copy = (wchar_t*)malloc(byteCount);
    if (copy == NULL) {
        return 0;
    }
    memcpy(copy, source, byteCount);
    *valueOut = copy;
    return 1;
}

int cf7_audio_bridge_support_write_utf8(
    cf7_audio_bridge_v2_utf8_buffer* buffer,
    const char* value)
{
    size_t length;
    char* destination;
    int convertedLength;
    if (!cf7_audio_bridge_support_prefix_valid(buffer, (uint32_t)sizeof(*buffer)) ||
        buffer->flags != CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY || value == NULL) {
        return 0;
    }
    length = strlen(value);
    if (length > UINT32_MAX - 1u || length > INT_MAX) {
        return 0;
    }
    convertedLength = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, value, (int)length, NULL, 0);
    if (length != 0u && convertedLength <= 0) {
        return 0;
    }
    buffer->requiredBytes = (uint32_t)length + 1u;
    buffer->lengthBytes = 0u;
    if (buffer->dataAddress == 0u || buffer->capacityBytes < buffer->requiredBytes) {
        return 0;
    }
    destination = (char*)(uintptr_t)buffer->dataAddress;
    memcpy(destination, value, length + 1u);
    buffer->lengthBytes = (uint32_t)length;
    return 1;
}

int cf7_audio_bridge_support_write_utf16(
    cf7_audio_bridge_v2_utf16_buffer* buffer,
    const wchar_t* value)
{
    size_t length;
    wchar_t* destination;
    if (!cf7_audio_bridge_support_prefix_valid(buffer, (uint32_t)sizeof(*buffer)) ||
        buffer->flags != CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY || value == NULL) {
        return 0;
    }
    length = wcslen(value);
    if (!cf7_utf16_is_well_formed(value, length) || length > UINT32_MAX - 1u) {
        return 0;
    }
    buffer->requiredCodeUnits = (uint32_t)length + 1u;
    buffer->lengthCodeUnits = 0u;
    if (buffer->dataAddress == 0u ||
        buffer->capacityCodeUnits < buffer->requiredCodeUnits) {
        return 0;
    }
    destination = (wchar_t*)(uintptr_t)buffer->dataAddress;
    memcpy(destination, value, (length + 1u) * sizeof(wchar_t));
    buffer->lengthCodeUnits = (uint32_t)length;
    return 1;
}

void cf7_audio_bridge_support_free(void* value)
{
    free(value);
}

static int cf7_hash_finish(
    BCRYPT_HASH_HANDLE hash,
    char hexOut[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY])
{
    static const char hex[] = "0123456789ABCDEF";
    unsigned char digest[32];
    size_t index;
    if (BCryptFinishHash(hash, digest, (ULONG)sizeof(digest), 0u) < 0) {
        return 0;
    }
    for (index = 0u; index < sizeof(digest); ++index) {
        hexOut[index * 2u] = hex[digest[index] >> 4u];
        hexOut[index * 2u + 1u] = hex[digest[index] & 0x0Fu];
    }
    hexOut[64] = '\0';
    return 1;
}

int cf7_audio_bridge_support_sha256(
    const void* bytes,
    size_t byteCount,
    char hexOut[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY])
{
    BCRYPT_ALG_HANDLE algorithm = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    int ok = 0;
    if (hexOut == NULL || (bytes == NULL && byteCount != 0u) || byteCount > ULONG_MAX) {
        return 0;
    }
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, NULL, 0u) >= 0 &&
        BCryptCreateHash(algorithm, &hash, NULL, 0u, NULL, 0u, 0u) >= 0 &&
        BCryptHashData(hash, (PUCHAR)bytes, (ULONG)byteCount, 0u) >= 0) {
        ok = cf7_hash_finish(hash, hexOut);
    }
    if (hash != NULL) {
        BCryptDestroyHash(hash);
    }
    if (algorithm != NULL) {
        BCryptCloseAlgorithmProvider(algorithm, 0u);
    }
    return ok;
}

int cf7_audio_bridge_support_sha256_handle(
    HANDLE file,
    uint64_t maximumBytes,
    char hexOut[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY],
    uint64_t* bytesReadOut)
{
    BCRYPT_ALG_HANDLE algorithm = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    unsigned char buffer[65536];
    LARGE_INTEGER original;
    LARGE_INTEGER zero;
    uint64_t total = 0u;
    int ok = 0;
    if (file == NULL || file == INVALID_HANDLE_VALUE || hexOut == NULL) {
        return 0;
    }
    if (bytesReadOut != NULL) {
        *bytesReadOut = 0u;
    }
    zero.QuadPart = 0;
    if (!SetFilePointerEx(file, zero, &original, FILE_CURRENT) ||
        !SetFilePointerEx(file, zero, NULL, FILE_BEGIN)) {
        return 0;
    }
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, NULL, 0u) < 0 ||
        BCryptCreateHash(algorithm, &hash, NULL, 0u, NULL, 0u, 0u) < 0) {
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
        if (!ReadFile(file, buffer, requested, &actual, NULL)) {
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
    ok = cf7_hash_finish(hash, hexOut);

cleanup:
    (void)SetFilePointerEx(file, original, NULL, FILE_BEGIN);
    if (bytesReadOut != NULL) {
        *bytesReadOut = total;
    }
    if (hash != NULL) {
        BCryptDestroyHash(hash);
    }
    if (algorithm != NULL) {
        BCryptCloseAlgorithmProvider(algorithm, 0u);
    }
    return ok;
}

int cf7_audio_bridge_support_utf8_from_utf16(const wchar_t* value, char** valueOut)
{
    int count;
    char* result;
    if (value == NULL || valueOut == NULL) {
        return 0;
    }
    *valueOut = NULL;
    count = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, NULL, 0, NULL, NULL);
    if (count <= 0) {
        return 0;
    }
    result = (char*)malloc((size_t)count);
    if (result == NULL) {
        return 0;
    }
    if (WideCharToMultiByte(
            CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, result, count, NULL, NULL) != count) {
        free(result);
        return 0;
    }
    *valueOut = result;
    return 1;
}

int cf7_audio_bridge_support_utf16_from_utf8(const char* value, wchar_t** valueOut)
{
    int count;
    wchar_t* result;
    if (value == NULL || valueOut == NULL) {
        return 0;
    }
    *valueOut = NULL;
    count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
    if (count <= 0) {
        return 0;
    }
    result = (wchar_t*)malloc((size_t)count * sizeof(wchar_t));
    if (result == NULL) {
        return 0;
    }
    if (MultiByteToWideChar(
            CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result, count) != count) {
        free(result);
        return 0;
    }
    *valueOut = result;
    return 1;
}

static int cf7_final_path(HANDLE handle, wchar_t** valueOut)
{
    DWORD required;
    DWORD written;
    wchar_t* value;
    if (valueOut == NULL) {
        return 0;
    }
    *valueOut = NULL;
    required = GetFinalPathNameByHandleW(
        handle, NULL, 0u, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (required == 0u || required == UINT32_MAX) {
        return 0;
    }
    value = (wchar_t*)malloc(((size_t)required + 1u) * sizeof(wchar_t));
    if (value == NULL) {
        return 0;
    }
    written = GetFinalPathNameByHandleW(
            handle,
            value,
            required + 1u,
            FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (written == 0u || written > required) {
        free(value);
        return 0;
    }
    required = written;
    while (required > 4u &&
        (value[required - 1u] == L'\\' || value[required - 1u] == L'/')) {
        value[--required] = L'\0';
    }
    *valueOut = value;
    return 1;
}

int cf7_audio_bridge_support_resolve_base(
    const wchar_t* inputPath,
    wchar_t** finalPathOut,
    DWORD* windowsErrorOut)
{
    HANDLE handle;
    BY_HANDLE_FILE_INFORMATION info;
    int ok;
    if (finalPathOut == NULL || inputPath == NULL || inputPath[0] == L'\0') {
        return 0;
    }
    *finalPathOut = NULL;
    if (windowsErrorOut != NULL) {
        *windowsErrorOut = ERROR_SUCCESS;
    }
    handle = CreateFileW(
        inputPath,
        FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS,
        NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        if (windowsErrorOut != NULL) {
            *windowsErrorOut = GetLastError();
        }
        return 0;
    }
    ok = GetFileInformationByHandle(handle, &info) &&
        (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0u &&
        cf7_final_path(handle, finalPathOut);
    if (!ok && windowsErrorOut != NULL) {
        *windowsErrorOut = GetLastError();
    }
    CloseHandle(handle);
    return ok;
}

static int cf7_path_is_contained(const wchar_t* base, const wchar_t* candidate)
{
    size_t baseLength;
    if (base == NULL || candidate == NULL) {
        return 0;
    }
    baseLength = wcslen(base);
    if (baseLength == 0u || _wcsnicmp(base, candidate, baseLength) != 0) {
        return 0;
    }
    return candidate[baseLength] == L'\\' || candidate[baseLength] == L'/';
}

int cf7_audio_bridge_support_resolve_file(
    const wchar_t* finalBasePath,
    const wchar_t* inputPath,
    wchar_t** finalPathOut,
    uint64_t* fileSizeOut,
    int64_t* modifiedUnixMillisecondsOut,
    DWORD* windowsErrorOut)
{
    HANDLE handle;
    BY_HANDLE_FILE_INFORMATION info;
    wchar_t* finalPath = NULL;
    ULARGE_INTEGER size;
    ULARGE_INTEGER modified;
    int ok = 0;
    if (finalBasePath == NULL || inputPath == NULL || finalPathOut == NULL ||
        fileSizeOut == NULL || modifiedUnixMillisecondsOut == NULL) {
        return 0;
    }
    *finalPathOut = NULL;
    *fileSizeOut = 0u;
    *modifiedUnixMillisecondsOut = 0;
    if (windowsErrorOut != NULL) {
        *windowsErrorOut = ERROR_SUCCESS;
    }
    handle = CreateFileW(
        inputPath,
        GENERIC_READ | FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        if (windowsErrorOut != NULL) {
            *windowsErrorOut = GetLastError();
        }
        return 0;
    }
    if (!GetFileInformationByHandle(handle, &info) ||
        (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0u ||
        !cf7_final_path(handle, &finalPath) ||
        !cf7_path_is_contained(finalBasePath, finalPath)) {
        if (windowsErrorOut != NULL) {
            *windowsErrorOut = GetLastError() == ERROR_SUCCESS
                ? ERROR_ACCESS_DENIED
                : GetLastError();
        }
        goto cleanup;
    }
    size.HighPart = info.nFileSizeHigh;
    size.LowPart = info.nFileSizeLow;
    modified.HighPart = info.ftLastWriteTime.dwHighDateTime;
    modified.LowPart = info.ftLastWriteTime.dwLowDateTime;
    if (modified.QuadPart < CF7_FILETIME_UNIX_EPOCH_TICKS) {
        if (windowsErrorOut != NULL) {
            *windowsErrorOut = ERROR_INVALID_DATA;
        }
        goto cleanup;
    }
    *fileSizeOut = size.QuadPart;
    *modifiedUnixMillisecondsOut = (int64_t)(
        (modified.QuadPart - CF7_FILETIME_UNIX_EPOCH_TICKS) /
        CF7_FILETIME_TICKS_PER_MILLISECOND);
    *finalPathOut = finalPath;
    finalPath = NULL;
    ok = 1;

cleanup:
    free(finalPath);
    CloseHandle(handle);
    return ok;
}

static int cf7_contains_bytes(
    const unsigned char* bytes,
    size_t byteCount,
    const char* needle,
    size_t needleLength)
{
    size_t index;
    if (needleLength == 0u || byteCount < needleLength) {
        return 0;
    }
    for (index = 0u; index <= byteCount - needleLength; ++index) {
        if (memcmp(bytes + index, needle, needleLength) == 0) {
            return 1;
        }
    }
    return 0;
}

static void cf7_sniff_bytes(
    const unsigned char* bytes,
    size_t byteCount,
    cf7_audio_bridge_support_sniff* value)
{
    memset(value, 0, sizeof(*value));
    if (byteCount >= 12u && memcmp(bytes, "RIFF", 4u) == 0 &&
        memcmp(bytes + 8u, "WAVE", 4u) == 0) {
        value->decoder = CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_BUILTIN;
        value->container = CF7_AUDIO_BRIDGE_V2_CONTAINER_RIFF_WAVE;
        value->codec = CF7_AUDIO_BRIDGE_V2_CODEC_PCM_OR_IEEE_FLOAT;
    } else if (byteCount >= 4u && memcmp(bytes, "fLaC", 4u) == 0) {
        value->decoder = CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_BUILTIN;
        value->container = CF7_AUDIO_BRIDGE_V2_CONTAINER_NATIVE_FLAC;
        value->codec = CF7_AUDIO_BRIDGE_V2_CODEC_FLAC;
    } else if (byteCount >= 4u && memcmp(bytes, "OggS", 4u) == 0) {
        value->container = CF7_AUDIO_BRIDGE_V2_CONTAINER_OGG;
        if (cf7_contains_bytes(bytes, byteCount, "OpusHead", 8u)) {
            value->decoder = CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_LIBOPUS;
            value->codec = CF7_AUDIO_BRIDGE_V2_CODEC_OPUS;
        } else if (cf7_contains_bytes(bytes, byteCount, "vorbis", 6u)) {
            value->decoder = CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_LIBVORBIS;
            value->codec = CF7_AUDIO_BRIDGE_V2_CODEC_VORBIS;
        }
    } else if (byteCount >= 12u && memcmp(bytes + 4u, "ftyp", 4u) == 0) {
        value->decoder = CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_MEDIA_FOUNDATION;
        value->container = CF7_AUDIO_BRIDGE_V2_CONTAINER_MPEG4;
        value->codec = CF7_AUDIO_BRIDGE_V2_CODEC_AAC_LC_OR_HE_AAC;
    } else if (byteCount >= 7u && bytes[0] == 0xFFu && (bytes[1] & 0xF6u) == 0xF0u) {
        value->decoder = CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_MEDIA_FOUNDATION;
        value->container = CF7_AUDIO_BRIDGE_V2_CONTAINER_ADTS;
        value->codec = CF7_AUDIO_BRIDGE_V2_CODEC_AAC_LC_OR_HE_AAC;
    } else if ((byteCount >= 3u && memcmp(bytes, "ID3", 3u) == 0) ||
        (byteCount >= 2u && bytes[0] == 0xFFu && (bytes[1] & 0xE0u) == 0xE0u)) {
        value->decoder = CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_BUILTIN;
        value->container = CF7_AUDIO_BRIDGE_V2_CONTAINER_MPEG_AUDIO;
        value->codec = CF7_AUDIO_BRIDGE_V2_CODEC_MPEG_AUDIO_LAYER_III;
    }
}

int cf7_audio_bridge_support_sniff_file(
    const wchar_t* path,
    cf7_audio_bridge_support_sniff* sniffOut,
    char first64kSha256Out[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY],
    DWORD* windowsErrorOut)
{
    HANDLE file;
    unsigned char* bytes;
    DWORD actual = 0u;
    int ok = 0;
    if (path == NULL || sniffOut == NULL || first64kSha256Out == NULL) {
        return 0;
    }
    if (windowsErrorOut != NULL) {
        *windowsErrorOut = ERROR_SUCCESS;
    }
    file = CreateFileW(
        path,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        NULL);
    if (file == INVALID_HANDLE_VALUE) {
        if (windowsErrorOut != NULL) {
            *windowsErrorOut = GetLastError();
        }
        return 0;
    }
    bytes = (unsigned char*)malloc(CF7_SNIFF_BYTES);
    if (bytes == NULL) {
        if (windowsErrorOut != NULL) {
            *windowsErrorOut = ERROR_OUTOFMEMORY;
        }
        CloseHandle(file);
        return 0;
    }
    if (ReadFile(file, bytes, CF7_SNIFF_BYTES, &actual, NULL) && actual != 0u &&
        cf7_audio_bridge_support_sha256(bytes, actual, first64kSha256Out)) {
        cf7_sniff_bytes(bytes, actual, sniffOut);
        ok = 1;
    } else if (windowsErrorOut != NULL) {
        *windowsErrorOut = GetLastError();
    }
    free(bytes);
    CloseHandle(file);
    return ok;
}
