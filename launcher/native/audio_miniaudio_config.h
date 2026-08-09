#ifndef CF7_AUDIO_MINIAUDIO_CONFIG_H
#define CF7_AUDIO_MINIAUDIO_CONFIG_H

/*
 * Production miniaudio compile policy for CF7 Audio Platform v2.
 *
 * This file is force-included for every native audio translation unit so the
 * public miniaudio structure layouts and the implementation are compiled with
 * one identical backend set.  A qualification-only Null build must use a
 * separate, unmistakable test target; the production DLL never defines
 * MA_ENABLE_NULL.
 */
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_WASAPI
#define MA_ENABLE_DSOUND
#define MA_ENABLE_WINMM
#define MA_NO_NULL

#endif /* CF7_AUDIO_MINIAUDIO_CONFIG_H */
