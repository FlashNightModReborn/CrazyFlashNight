#ifndef CF7_AUDIO_DECODER_REGISTRY_H
#define CF7_AUDIO_DECODER_REGISTRY_H

#include "audio_miniaudio_config.h"
#include "miniaudio.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CF7_AUDIO_DECODER_BACKEND_COUNT 3U

typedef struct cf7_audio_decoder_registry {
    ma_decoding_backend_vtable* backends[CF7_AUDIO_DECODER_BACKEND_COUNT];
    ma_uint32 count;
    ma_bool32 mediaFoundationStarted;
} cf7_audio_decoder_registry;

ma_result cf7_audio_decoder_registry_init(cf7_audio_decoder_registry* registry);
void cf7_audio_decoder_registry_uninit(cf7_audio_decoder_registry* registry);

#ifdef __cplusplus
}
#endif

#endif
