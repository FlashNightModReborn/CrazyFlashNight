#include "../audio_bridge_support.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define CHECK(expression) do { \
    if (!(expression)) { \
        fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expression); \
        failures += 1; \
    } \
} while (0)

static void set_prefix(void* value, uint32_t size)
{
    cf7_audio_bridge_v2_struct_header* header =
        (cf7_audio_bridge_v2_struct_header*)value;
    header->structSize = size;
    header->abiMajor = CF7_AUDIO_BRIDGE_V2_ABI_MAJOR;
    header->abiMinor = CF7_AUDIO_BRIDGE_V2_ABI_MINOR;
}

static wchar_t* arg_to_wide(const char* value)
{
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
    wchar_t* result;
    if (count <= 0) return NULL;
    result = (wchar_t*)malloc((size_t)count * sizeof(wchar_t));
    if (result == NULL) return NULL;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result, count) != count) {
        free(result);
        return NULL;
    }
    return result;
}

int main(int argc, char** argv)
{
    static const char expectedSha[] =
        "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD";
    struct {
        unsigned char before;
        char bytes[4];
        unsigned char after;
    } guarded;
    cf7_audio_bridge_v2_utf8_buffer input;
    cf7_audio_bridge_v2_utf8_buffer output;
    cf7_audio_bridge_support_sniff sniff;
    char digest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    char firstDigest[CF7_AUDIO_BRIDGE_V2_SHA256_HEX_CAPACITY];
    char* copy = NULL;
    wchar_t* baseInput;
    wchar_t* insideInput;
    wchar_t* outsideInput;
    wchar_t* junctionInput;
    wchar_t* finalBase = NULL;
    wchar_t* finalFile = NULL;
    uint64_t fileSize = 0u;
    int64_t modified = 0;
    DWORD error = ERROR_SUCCESS;

    if (argc != 5) {
        fprintf(stderr, "usage: support-contract base inside outside junction-file\n");
        return 2;
    }

    memset(&input, 0, sizeof(input));
    set_prefix(&input, (uint32_t)sizeof(input));
    input.dataAddress = (uint64_t)(uintptr_t)"audio";
    input.capacityBytes = 6u;
    input.lengthBytes = 5u;
    input.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY;
    CHECK(cf7_audio_bridge_support_read_utf8(&input, &copy));
    CHECK(copy != NULL && strcmp(copy, "audio") == 0);
    cf7_audio_bridge_support_free(copy);
    copy = NULL;
    input.abiMinor += 1u;
    CHECK(!cf7_audio_bridge_support_read_utf8(&input, &copy));

    memset(&guarded, 0xA5, sizeof(guarded));
    memset(&output, 0, sizeof(output));
    set_prefix(&output, (uint32_t)sizeof(output));
    output.dataAddress = (uint64_t)(uintptr_t)guarded.bytes;
    output.capacityBytes = 4u;
    output.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY;
    CHECK(!cf7_audio_bridge_support_write_utf8(&output, "audio"));
    CHECK(output.requiredBytes == 6u && output.lengthBytes == 0u);
    CHECK(guarded.before == 0xA5u && guarded.after == 0xA5u);
    CHECK((unsigned char)guarded.bytes[0] == 0xA5u);

    CHECK(cf7_audio_bridge_support_sha256("abc", 3u, digest));
    CHECK(strcmp(digest, expectedSha) == 0);

    baseInput = arg_to_wide(argv[1]);
    insideInput = arg_to_wide(argv[2]);
    outsideInput = arg_to_wide(argv[3]);
    junctionInput = arg_to_wide(argv[4]);
    CHECK(baseInput != NULL && insideInput != NULL && outsideInput != NULL && junctionInput != NULL);
    if (baseInput != NULL && insideInput != NULL && outsideInput != NULL && junctionInput != NULL) {
        CHECK(cf7_audio_bridge_support_resolve_base(baseInput, &finalBase, &error));
        CHECK(finalBase != NULL);
        if (finalBase != NULL) {
            CHECK(cf7_audio_bridge_support_resolve_file(
                finalBase, insideInput, &finalFile, &fileSize, &modified, &error));
            CHECK(finalFile != NULL && fileSize >= 3u && modified > 0);
            cf7_audio_bridge_support_free(finalFile);
            finalFile = NULL;
            CHECK(!cf7_audio_bridge_support_resolve_file(
                finalBase, outsideInput, &finalFile, &fileSize, &modified, &error));
            CHECK(!cf7_audio_bridge_support_resolve_file(
                finalBase, junctionInput, &finalFile, &fileSize, &modified, &error));
        }
        CHECK(cf7_audio_bridge_support_sniff_file(
            insideInput, &sniff, firstDigest, &error));
        CHECK(sniff.decoder == CF7_AUDIO_BRIDGE_V2_DECODER_BACKEND_BUILTIN);
        CHECK(sniff.container == CF7_AUDIO_BRIDGE_V2_CONTAINER_MPEG_AUDIO);
        CHECK(sniff.codec == CF7_AUDIO_BRIDGE_V2_CODEC_MPEG_AUDIO_LAYER_III);
        CHECK(strlen(firstDigest) == 64u);
    }

    cf7_audio_bridge_support_free(finalBase);
    free(baseInput);
    free(insideInput);
    free(outsideInput);
    free(junctionInput);

    if (failures != 0) return 1;
    puts("audio bridge support contract PASS");
    return 0;
}
