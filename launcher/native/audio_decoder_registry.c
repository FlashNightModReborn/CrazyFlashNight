#include "audio_decoder_registry.h"

#include "audio_mf_decoder.h"
#include "extras/decoders/libopus/miniaudio_libopus.h"
#include "extras/decoders/libvorbis/miniaudio_libvorbis.h"

#include <string.h>

ma_result cf7_audio_decoder_registry_init(cf7_audio_decoder_registry* registry) {
    ma_result result;
    if (registry == NULL) {
        return MA_INVALID_ARGS;
    }
    memset(registry, 0, sizeof(*registry));

    result = cf7_audio_mf_runtime_startup();
    if (result != MA_SUCCESS) {
        return result;
    }
    registry->mediaFoundationStarted = MA_TRUE;

    /* Content-sniffing backends return MA_INVALID_FILE when the stream is not theirs. */
    registry->backends[0] = cf7_audio_decoding_backend_mf_aac;
    registry->backends[1] = ma_decoding_backend_libvorbis;
    registry->backends[2] = ma_decoding_backend_libopus;
    if (registry->backends[0] == NULL || registry->backends[1] == NULL || registry->backends[2] == NULL) {
        cf7_audio_decoder_registry_uninit(registry);
        return MA_NOT_IMPLEMENTED;
    }
    registry->count = CF7_AUDIO_DECODER_BACKEND_COUNT;
    return MA_SUCCESS;
}

void cf7_audio_decoder_registry_uninit(cf7_audio_decoder_registry* registry) {
    if (registry == NULL) {
        return;
    }
    if (registry->mediaFoundationStarted) {
        cf7_audio_mf_runtime_shutdown();
    }
    memset(registry, 0, sizeof(*registry));
}
