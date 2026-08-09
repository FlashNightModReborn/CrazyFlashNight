#ifndef CF7_AUDIO_BACKEND_POLICY_H
#define CF7_AUDIO_BACKEND_POLICY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Pure real-backend selection policy.  The production adapter performs a
 * complete context -> playback device -> device start attempt in tryBackend.
 * Tests inject deterministic failures without linking an audio backend.
 */
#define CF7_AUDIO_BACKEND_POLICY_WASAPI ((uint32_t)1u)
#define CF7_AUDIO_BACKEND_POLICY_DIRECTSOUND ((uint32_t)2u)
#define CF7_AUDIO_BACKEND_POLICY_WINMM ((uint32_t)3u)

#define CF7_AUDIO_BACKEND_POLICY_STAGE_CONTEXT ((uint32_t)10u)
#define CF7_AUDIO_BACKEND_POLICY_STAGE_DEVICE ((uint32_t)11u)
#define CF7_AUDIO_BACKEND_POLICY_STAGE_START ((uint32_t)12u)

typedef int32_t (*cf7_audio_backend_policy_try_proc)(
    void* userData,
    uint32_t backend,
    uint32_t* failureStage,
    int32_t* nativeResult);

typedef struct cf7_audio_backend_policy_result {
    uint32_t selectedBackend;
    uint32_t lastAttemptedBackend;
    uint32_t lastFailureStage;
    int32_t lastNativeResult;
    uint32_t attempts;
} cf7_audio_backend_policy_result;

int32_t cf7_audio_backend_policy_select(
    cf7_audio_backend_policy_try_proc tryBackend,
    void* userData,
    cf7_audio_backend_policy_result* result);

#ifdef __cplusplus
}
#endif

#endif
