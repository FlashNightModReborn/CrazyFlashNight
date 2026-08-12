#include <stdio.h>
#include <string.h>

#include "../audio_bridge_v2.h"
#include "../audio_miniaudio_config.h"
#include "../miniaudio.h"

#define CF7_STATIC_ASSERT(name, expression) \
    typedef char name[(expression) ? 1 : -1]

#define CF7_ASSERT_PREFIX(type, tag)                                      \
    CF7_STATIC_ASSERT(tag##_struct_size_offset,                           \
        offsetof(type, structSize) == 0u);                                \
    CF7_STATIC_ASSERT(tag##_abi_major_offset,                             \
        offsetof(type, abiMajor) == sizeof(uint32_t));                    \
    CF7_STATIC_ASSERT(tag##_abi_minor_offset,                             \
        offsetof(type, abiMinor) == (sizeof(uint32_t) * 2u))

CF7_STATIC_ASSERT(cf7_uint8_width, sizeof(uint8_t) == 1u);
CF7_STATIC_ASSERT(cf7_uint16_width, sizeof(uint16_t) == 2u);
CF7_STATIC_ASSERT(cf7_uint32_width, sizeof(uint32_t) == 4u);
CF7_STATIC_ASSERT(cf7_uint64_width, sizeof(uint64_t) == 8u);
CF7_STATIC_ASSERT(cf7_int32_width, sizeof(int32_t) == 4u);
CF7_STATIC_ASSERT(cf7_int64_width, sizeof(int64_t) == 8u);
CF7_STATIC_ASSERT(cf7_float_width, sizeof(float) == 4u);
CF7_STATIC_ASSERT(cf7_double_width, sizeof(double) == 8u);
CF7_STATIC_ASSERT(cf7_address_width, sizeof(cf7_audio_bridge_v2_caller_address) == 8u);

CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_struct_header, cf7_header);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_version, cf7_version);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_utf8_buffer, cf7_utf8_buffer);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_utf16_buffer, cf7_utf16_buffer);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_array_buffer, cf7_array_buffer);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_result, cf7_result);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_capability, cf7_capability);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_runtime_snapshot, cf7_runtime_snapshot);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_meter_snapshot, cf7_meter_snapshot);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_source_snapshot, cf7_source_snapshot);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_sfx_counters, cf7_sfx_counters);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_initialize_command, cf7_initialize_command);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_bgm_command, cf7_bgm_command);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_sfx_catalog_item, cf7_sfx_catalog_item);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_sfx_catalog_command, cf7_sfx_catalog_command);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_sfx_play_item, cf7_sfx_play_item);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_sfx_batch_command, cf7_sfx_batch_command);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_gain_command, cf7_gain_command);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_runtime_probe_command, cf7_runtime_probe_command);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_offline_probe_command, cf7_offline_probe_command);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_probe_result, cf7_probe_result);
CF7_ASSERT_PREFIX(cf7_audio_bridge_v2_shutdown_command, cf7_shutdown_command);

CF7_STATIC_ASSERT(cf7_header_size, sizeof(cf7_audio_bridge_v2_struct_header) == 12u);
CF7_STATIC_ASSERT(cf7_version_size, sizeof(cf7_audio_bridge_v2_version) == 24u);
CF7_STATIC_ASSERT(cf7_utf8_buffer_size, sizeof(cf7_audio_bridge_v2_utf8_buffer) == 40u);
CF7_STATIC_ASSERT(cf7_utf16_buffer_size, sizeof(cf7_audio_bridge_v2_utf16_buffer) == 40u);
CF7_STATIC_ASSERT(cf7_array_buffer_size, sizeof(cf7_audio_bridge_v2_array_buffer) == 40u);
CF7_STATIC_ASSERT(cf7_result_size, sizeof(cf7_audio_bridge_v2_result) == 136u);
CF7_STATIC_ASSERT(cf7_capability_size, sizeof(cf7_audio_bridge_v2_capability) == 216u);
CF7_STATIC_ASSERT(cf7_runtime_snapshot_size, sizeof(cf7_audio_bridge_v2_runtime_snapshot) == 312u);
CF7_STATIC_ASSERT(cf7_meter_snapshot_size, sizeof(cf7_audio_bridge_v2_meter_snapshot) == 112u);
CF7_STATIC_ASSERT(cf7_source_snapshot_size, sizeof(cf7_audio_bridge_v2_source_snapshot) == 256u);
CF7_STATIC_ASSERT(cf7_sfx_counters_size, sizeof(cf7_audio_bridge_v2_sfx_counters) == 120u);
CF7_STATIC_ASSERT(cf7_initialize_command_size, sizeof(cf7_audio_bridge_v2_initialize_command) == 112u);
CF7_STATIC_ASSERT(cf7_bgm_command_size, sizeof(cf7_audio_bridge_v2_bgm_command) == 168u);
CF7_STATIC_ASSERT(cf7_sfx_catalog_item_size, sizeof(cf7_audio_bridge_v2_sfx_catalog_item) == 96u);
CF7_STATIC_ASSERT(cf7_sfx_catalog_command_size, sizeof(cf7_audio_bridge_v2_sfx_catalog_command) == 104u);
CF7_STATIC_ASSERT(cf7_sfx_play_item_size, sizeof(cf7_audio_bridge_v2_sfx_play_item) == 64u);
CF7_STATIC_ASSERT(cf7_sfx_batch_command_size, sizeof(cf7_audio_bridge_v2_sfx_batch_command) == 112u);
CF7_STATIC_ASSERT(cf7_gain_command_size, sizeof(cf7_audio_bridge_v2_gain_command) == 72u);
CF7_STATIC_ASSERT(cf7_runtime_probe_command_size, sizeof(cf7_audio_bridge_v2_runtime_probe_command) == 192u);
CF7_STATIC_ASSERT(cf7_offline_probe_command_size, sizeof(cf7_audio_bridge_v2_offline_probe_command) == 144u);
CF7_STATIC_ASSERT(cf7_probe_result_size, sizeof(cf7_audio_bridge_v2_probe_result) == 232u);
CF7_STATIC_ASSERT(cf7_shutdown_command_size, sizeof(cf7_audio_bridge_v2_shutdown_command) == 64u);

CF7_STATIC_ASSERT(cf7_result_session_offset,
    offsetof(cf7_audio_bridge_v2_result, audioSessionId) == 40u);
CF7_STATIC_ASSERT(cf7_result_ready_epoch_offset,
    offsetof(cf7_audio_bridge_v2_result, audioReadyGeneration) == 80u);
CF7_STATIC_ASSERT(cf7_result_device_epoch_offset,
    offsetof(cf7_audio_bridge_v2_result, deviceGeneration) == 88u);
CF7_STATIC_ASSERT(cf7_runtime_status_offset,
    offsetof(cf7_audio_bridge_v2_runtime_snapshot, audioStatus) == 12u);
CF7_STATIC_ASSERT(cf7_runtime_session_offset,
    offsetof(cf7_audio_bridge_v2_runtime_snapshot, audioSessionId) == 16u);
CF7_STATIC_ASSERT(cf7_runtime_ready_epoch_offset,
    offsetof(cf7_audio_bridge_v2_runtime_snapshot, audioReadyGeneration) == 56u);
CF7_STATIC_ASSERT(cf7_runtime_device_epoch_offset,
    offsetof(cf7_audio_bridge_v2_runtime_snapshot, deviceGeneration) == 64u);
CF7_STATIC_ASSERT(cf7_runtime_backend_offset,
    offsetof(cf7_audio_bridge_v2_runtime_snapshot, selectedBackend) == 72u);
CF7_STATIC_ASSERT(cf7_bgm_wire_revision_offset,
    offsetof(cf7_audio_bridge_v2_bgm_command, wireRevision) == 12u);
CF7_STATIC_ASSERT(cf7_bgm_request_id_offset,
    offsetof(cf7_audio_bridge_v2_bgm_command, requestId) == 16u);
CF7_STATIC_ASSERT(cf7_bgm_session_offset,
    offsetof(cf7_audio_bridge_v2_bgm_command, audioSessionId) == 56u);
CF7_STATIC_ASSERT(cf7_bgm_ready_epoch_offset,
    offsetof(cf7_audio_bridge_v2_bgm_command, audioReadyGeneration) == 96u);
CF7_STATIC_ASSERT(cf7_bgm_operation_offset,
    offsetof(cf7_audio_bridge_v2_bgm_command, operation) == 104u);
CF7_STATIC_ASSERT(cf7_sfx_wire_revision_offset,
    offsetof(cf7_audio_bridge_v2_sfx_batch_command, wireRevision) == 12u);
CF7_STATIC_ASSERT(cf7_sfx_session_offset,
    offsetof(cf7_audio_bridge_v2_sfx_batch_command, audioSessionId) == 16u);
CF7_STATIC_ASSERT(cf7_sfx_ready_epoch_offset,
    offsetof(cf7_audio_bridge_v2_sfx_batch_command, audioReadyGeneration) == 56u);
CF7_STATIC_ASSERT(cf7_sfx_batch_sequence_offset,
    offsetof(cf7_audio_bridge_v2_sfx_batch_command, batchSequence) == 64u);
CF7_STATIC_ASSERT(cf7_sfx_ids_offset,
    offsetof(cf7_audio_bridge_v2_sfx_batch_command, linkageIds) == 72u);

static unsigned long g_assertions = 0u;
static unsigned long g_failures = 0u;

static void cf7_check(int passed, int line, const char* expression)
{
    g_assertions += 1u;
    if (!passed) {
        g_failures += 1u;
        printf("[FAIL] line=%d expression=%s\n", line, expression);
    }
}

#define CF7_CHECK(expression) \
    cf7_check((expression) ? 1 : 0, __LINE__, #expression)

static void cf7_set_prefix(void* value, uint32_t structSize)
{
    cf7_audio_bridge_v2_struct_header* header;
    header = (cf7_audio_bridge_v2_struct_header*)value;
    header->structSize = structSize;
    header->abiMajor = CF7_AUDIO_BRIDGE_V2_ABI_MAJOR;
    header->abiMinor = CF7_AUDIO_BRIDGE_V2_ABI_MINOR;
}

static int cf7_prefix_is_accepted(const void* value, uint32_t minimumSize)
{
    const cf7_audio_bridge_v2_struct_header* header;
    if (value == NULL) {
        return 0;
    }
    header = (const cf7_audio_bridge_v2_struct_header*)value;
    if (header->structSize < minimumSize) {
        return 0;
    }
    if (header->abiMajor != CF7_AUDIO_BRIDGE_V2_ABI_MAJOR) {
        return 0;
    }
    if (header->abiMinor > CF7_AUDIO_BRIDGE_V2_ABI_MINOR) {
        return 0;
    }
    return 1;
}

static int cf7_utf8_input_is_valid(const cf7_audio_bridge_v2_utf8_buffer* buffer)
{
    const char* text;
    if (!cf7_prefix_is_accepted(buffer, (uint32_t)sizeof(*buffer))) {
        return 0;
    }
    if (buffer->flags != CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY) {
        return 0;
    }
    if (buffer->dataAddress == (cf7_audio_bridge_v2_caller_address)0u) {
        return buffer->capacityBytes == 0u && buffer->lengthBytes == 0u;
    }
    if (buffer->capacityBytes == 0u || buffer->lengthBytes >= buffer->capacityBytes) {
        return 0;
    }
    text = (const char*)(uintptr_t)buffer->dataAddress;
    return text[buffer->lengthBytes] == '\0';
}

static int cf7_utf16_input_is_valid(const cf7_audio_bridge_v2_utf16_buffer* buffer)
{
    const uint16_t* text;
    if (!cf7_prefix_is_accepted(buffer, (uint32_t)sizeof(*buffer))) {
        return 0;
    }
    if (buffer->flags != CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY) {
        return 0;
    }
    if (buffer->dataAddress == (cf7_audio_bridge_v2_caller_address)0u) {
        return buffer->capacityCodeUnits == 0u && buffer->lengthCodeUnits == 0u;
    }
    if (buffer->capacityCodeUnits == 0u ||
            buffer->lengthCodeUnits >= buffer->capacityCodeUnits) {
        return 0;
    }
    text = (const uint16_t*)(uintptr_t)buffer->dataAddress;
    return text[buffer->lengthCodeUnits] == (uint16_t)0u;
}

static int cf7_write_utf8(
    cf7_audio_bridge_v2_utf8_buffer* buffer,
    const char* value)
{
    uint32_t required;
    char* destination;
    size_t sourceLength;
    if (!cf7_prefix_is_accepted(buffer, (uint32_t)sizeof(*buffer))) {
        return 0;
    }
    if (buffer->flags != CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY || value == NULL) {
        return 0;
    }
    sourceLength = strlen(value);
    if (sourceLength > (size_t)UINT32_MAX - 1u) {
        return 0;
    }
    required = (uint32_t)sourceLength + 1u;
    buffer->requiredBytes = required;
    buffer->lengthBytes = 0u;
    if (buffer->dataAddress == (cf7_audio_bridge_v2_caller_address)0u ||
            buffer->capacityBytes < required) {
        return 0;
    }
    destination = (char*)(uintptr_t)buffer->dataAddress;
    memcpy(destination, value, required);
    buffer->lengthBytes = required - 1u;
    return 1;
}

static int cf7_array_is_valid(
    const cf7_audio_bridge_v2_array_buffer* buffer,
    uint32_t expectedElementSize)
{
    if (!cf7_prefix_is_accepted(buffer, (uint32_t)sizeof(*buffer))) {
        return 0;
    }
    if (buffer->elementSize != expectedElementSize) {
        return 0;
    }
    if (buffer->countElements > buffer->capacityElements) {
        return 0;
    }
    if (buffer->capacityElements > 0u &&
            buffer->dataAddress == (cf7_audio_bridge_v2_caller_address)0u) {
        return 0;
    }
    return 1;
}

static void cf7_test_abi_prefix(void)
{
    struct cf7_extended_capability {
        cf7_audio_bridge_v2_capability value;
        uint64_t futureTail;
    } extendedValue;
    cf7_audio_bridge_v2_capability value;

    memset(&value, 0, sizeof(value));
    cf7_set_prefix(&value, (uint32_t)sizeof(value));
    CF7_CHECK(cf7_prefix_is_accepted(&value, (uint32_t)sizeof(value)) == 1);

    value.structSize = (uint32_t)sizeof(value) - 1u;
    CF7_CHECK(cf7_prefix_is_accepted(&value, (uint32_t)sizeof(value)) == 0);
    value.structSize = (uint32_t)sizeof(value);
    value.abiMajor = CF7_AUDIO_BRIDGE_V2_ABI_MAJOR - 1u;
    CF7_CHECK(cf7_prefix_is_accepted(&value, (uint32_t)sizeof(value)) == 0);
    value.abiMajor = CF7_AUDIO_BRIDGE_V2_ABI_MAJOR + 1u;
    CF7_CHECK(cf7_prefix_is_accepted(&value, (uint32_t)sizeof(value)) == 0);
    value.abiMajor = CF7_AUDIO_BRIDGE_V2_ABI_MAJOR;
    value.abiMinor = CF7_AUDIO_BRIDGE_V2_ABI_MINOR + 1u;
    CF7_CHECK(cf7_prefix_is_accepted(&value, (uint32_t)sizeof(value)) == 0);
    CF7_CHECK(cf7_prefix_is_accepted(NULL, (uint32_t)sizeof(value)) == 0);

    memset(&extendedValue, 0, sizeof(extendedValue));
    cf7_set_prefix(&extendedValue.value, (uint32_t)sizeof(extendedValue));
    CF7_CHECK(cf7_prefix_is_accepted(
        &extendedValue.value,
        (uint32_t)sizeof(extendedValue.value)) == 1);
}

static void cf7_test_utf8_capacity_and_canary(void)
{
    unsigned char guarded[9];
    cf7_audio_bridge_v2_utf8_buffer output;
    unsigned int index;

    memset(guarded, 0xA5, sizeof(guarded));
    memset(&output, 0, sizeof(output));
    cf7_set_prefix(&output, (uint32_t)sizeof(output));
    output.dataAddress = (cf7_audio_bridge_v2_caller_address)(uintptr_t)&guarded[2];
    output.capacityBytes = 4u;
    output.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY;

    CF7_CHECK(cf7_write_utf8(&output, "abcd") == 0);
    CF7_CHECK(output.requiredBytes == 5u);
    CF7_CHECK(output.lengthBytes == 0u);
    for (index = 0u; index < (unsigned int)sizeof(guarded); ++index) {
        CF7_CHECK(guarded[index] == 0xA5u);
    }

    output.capacityBytes = 5u;
    CF7_CHECK(cf7_write_utf8(&output, "abcd") == 1);
    CF7_CHECK(output.requiredBytes == 5u);
    CF7_CHECK(output.lengthBytes == 4u);
    CF7_CHECK(guarded[0] == 0xA5u && guarded[1] == 0xA5u);
    CF7_CHECK(guarded[2] == (unsigned char)'a');
    CF7_CHECK(guarded[5] == (unsigned char)'d');
    CF7_CHECK(guarded[6] == 0u);
    CF7_CHECK(guarded[7] == 0xA5u && guarded[8] == 0xA5u);

    output.dataAddress = (cf7_audio_bridge_v2_caller_address)0u;
    output.capacityBytes = 0u;
    CF7_CHECK(cf7_write_utf8(&output, "abcd") == 0);
    CF7_CHECK(output.requiredBytes == 5u);
}

static void cf7_test_input_capacity(void)
{
    char utf8Text[4];
    uint16_t utf16Text[4];
    cf7_audio_bridge_v2_utf8_buffer utf8Input;
    cf7_audio_bridge_v2_utf16_buffer utf16Input;

    utf8Text[0] = 'a';
    utf8Text[1] = 'b';
    utf8Text[2] = 'c';
    utf8Text[3] = '\0';
    memset(&utf8Input, 0, sizeof(utf8Input));
    cf7_set_prefix(&utf8Input, (uint32_t)sizeof(utf8Input));
    utf8Input.dataAddress = (cf7_audio_bridge_v2_caller_address)(uintptr_t)utf8Text;
    utf8Input.capacityBytes = 4u;
    utf8Input.lengthBytes = 3u;
    utf8Input.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY;
    CF7_CHECK(cf7_utf8_input_is_valid(&utf8Input) == 1);
    utf8Input.lengthBytes = 4u;
    CF7_CHECK(cf7_utf8_input_is_valid(&utf8Input) == 0);
    utf8Input.lengthBytes = 3u;
    utf8Input.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_WRITE_ONLY;
    CF7_CHECK(cf7_utf8_input_is_valid(&utf8Input) == 0);
    utf8Input.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY;
    utf8Text[3] = 'x';
    CF7_CHECK(cf7_utf8_input_is_valid(&utf8Input) == 0);

    utf16Text[0] = (uint16_t)'a';
    utf16Text[1] = (uint16_t)'b';
    utf16Text[2] = (uint16_t)'c';
    utf16Text[3] = (uint16_t)0u;
    memset(&utf16Input, 0, sizeof(utf16Input));
    cf7_set_prefix(&utf16Input, (uint32_t)sizeof(utf16Input));
    utf16Input.dataAddress = (cf7_audio_bridge_v2_caller_address)(uintptr_t)utf16Text;
    utf16Input.capacityCodeUnits = 4u;
    utf16Input.lengthCodeUnits = 3u;
    utf16Input.flags = CF7_AUDIO_BRIDGE_V2_BUFFER_READ_ONLY;
    CF7_CHECK(cf7_utf16_input_is_valid(&utf16Input) == 1);
    utf16Input.lengthCodeUnits = 4u;
    CF7_CHECK(cf7_utf16_input_is_valid(&utf16Input) == 0);
    utf16Input.lengthCodeUnits = 3u;
    utf16Text[3] = (uint16_t)'x';
    CF7_CHECK(cf7_utf16_input_is_valid(&utf16Input) == 0);
}

static void cf7_test_array_capacity(void)
{
    cf7_audio_bridge_v2_sfx_play_item items[2];
    cf7_audio_bridge_v2_array_buffer array;
    memset(items, 0, sizeof(items));
    memset(&array, 0, sizeof(array));
    cf7_set_prefix(&array, (uint32_t)sizeof(array));
    array.dataAddress = (cf7_audio_bridge_v2_caller_address)(uintptr_t)items;
    array.elementSize = (uint32_t)sizeof(items[0]);
    array.capacityElements = 2u;
    array.countElements = 2u;
    CF7_CHECK(cf7_array_is_valid(&array, (uint32_t)sizeof(items[0])) == 1);
    array.countElements = 3u;
    CF7_CHECK(cf7_array_is_valid(&array, (uint32_t)sizeof(items[0])) == 0);
    array.countElements = 2u;
    array.elementSize -= 1u;
    CF7_CHECK(cf7_array_is_valid(&array, (uint32_t)sizeof(items[0])) == 0);
    array.elementSize = (uint32_t)sizeof(items[0]);
    array.dataAddress = (cf7_audio_bridge_v2_caller_address)0u;
    CF7_CHECK(cf7_array_is_valid(&array, (uint32_t)sizeof(items[0])) == 0);
    array.capacityElements = 0u;
    array.countElements = 0u;
    CF7_CHECK(cf7_array_is_valid(&array, (uint32_t)sizeof(items[0])) == 1);
}

static void cf7_test_frozen_constants(void)
{
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_ABI_MAJOR == 2u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_ABI_MINOR == 0u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_WIRE_REVISION == 2u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_RESULT_INTERNAL_ERROR == 17u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_PRODUCTION == 7u);
    CF7_CHECK((CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_PRODUCTION &
        CF7_AUDIO_BRIDGE_V2_BACKEND_MASK_TEST_ONLY_NULL) == 0u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_WALL_MS == 2000u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_DECODED_FRAMES == 96000u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_INPUT_BYTES == 8388608u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_MAX_FILE_BYTES == 536870912u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_OBSERVATIONS == 2u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_RUNTIME_PROBE_STABLE_INTERVAL_MS == 1000u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_OFFLINE_PROBE_MAX_WALL_MS == 120000u);
    CF7_CHECK(CF7_AUDIO_BRIDGE_V2_PROBE_INCONCLUSIVE_TIMEOUT_NOT_UNSUPPORTED !=
        CF7_AUDIO_BRIDGE_V2_PROBE_INCOMPATIBLE);
}

static void cf7_test_engine_wasapi_routing_config(void)
{
    ma_engine_config config = ma_engine_config_init();
    CF7_CHECK(config.wasapi.noAutoStreamRouting == MA_FALSE);
    config.wasapi.noAutoStreamRouting = MA_TRUE;
    CF7_CHECK(config.wasapi.noAutoStreamRouting == MA_TRUE);
}

int main(void)
{
    cf7_test_abi_prefix();
    cf7_test_utf8_capacity_and_canary();
    cf7_test_input_capacity();
    cf7_test_array_capacity();
    cf7_test_frozen_constants();
    cf7_test_engine_wasapi_routing_config();

    if (g_failures != 0u) {
        printf("[FAIL] audio_bridge_v2_contract assertions=%lu failures=%lu\n",
            g_assertions,
            g_failures);
        return 1;
    }

    printf("[PASS] audio_bridge_v2_contract assertions=%lu\n", g_assertions);
    return 0;
}
