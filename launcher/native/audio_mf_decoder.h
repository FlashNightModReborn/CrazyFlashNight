#ifndef CF7_AUDIO_MF_DECODER_H
#define CF7_AUDIO_MF_DECODER_H

#include "audio_miniaudio_config.h"
#include "miniaudio.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Media Foundation is restricted to the AAC contract accepted for Audio v2.
 * WMA/ASF deliberately remains unadvertised and is rejected by this backend.
 */
#define CF7_AUDIO_MF_DECODE_CONTROL_REVISION 1U
#define CF7_AUDIO_MF_DEFAULT_READ_WAIT_MS 2000U
#define CF7_AUDIO_MF_DEFAULT_WAIT_SLICE_MS 10U
#define CF7_AUDIO_MF_CLEANUP_WAIT_MS 250U
#define CF7_AUDIO_MF_CLEANUP_RESERVE_MS 500U

#define CF7_AUDIO_MF_FAULT_NONE 0U
#define CF7_AUDIO_MF_FAULT_SUPPRESS_READ_SIGNAL 1U
#define CF7_AUDIO_MF_FAULT_DELAY_READ_CALLBACK 2U

typedef ma_bool32 (*cf7_audio_mf_should_cancel_proc)(void* user_data);

/*
 * Native-internal custom-backend policy. This is not part of the public
 * audio_bridge_v2 ABI. The backend copies the structure during init, so the
 * structure itself may be stack-owned; cancel_user_data must remain valid for
 * the decoder lifetime.
 */
typedef struct cf7_audio_mf_decode_control {
    ma_uint32 struct_size;
    ma_uint32 revision;
    ma_uint64 deadline_tick_milliseconds;
    ma_uint32 maximum_read_wait_milliseconds;
    ma_uint32 wait_slice_milliseconds;
    cf7_audio_mf_should_cancel_proc should_cancel;
    void* cancel_user_data;
    ma_uint32 fault_flags;
    ma_uint32 fault_delay_milliseconds;
} cf7_audio_mf_decode_control;

ma_result cf7_audio_mf_runtime_startup(void);
void cf7_audio_mf_runtime_shutdown(void);
ma_uint32 cf7_audio_mf_test_retired_session_count(void);
ma_uint32 cf7_audio_mf_test_callback_instance_count(void);
void cf7_audio_mf_test_reset_counters(void);
ma_uint64 cf7_audio_mf_test_read_request_count(void);
ma_uint64 cf7_audio_mf_test_read_callback_count(void);
ma_uint64 cf7_audio_mf_test_flush_request_count(void);
ma_uint64 cf7_audio_mf_test_flush_callback_count(void);
ma_uint64 cf7_audio_mf_test_terminal_seek_reject_count(void);
extern ma_decoding_backend_vtable* cf7_audio_decoding_backend_mf_aac;

#ifdef __cplusplus
}
#endif

#endif
