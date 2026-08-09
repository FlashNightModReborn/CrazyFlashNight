#include "audio_backend_policy.h"

#include <string.h>

int32_t cf7_audio_backend_policy_select(
    cf7_audio_backend_policy_try_proc tryBackend,
    void* userData,
    cf7_audio_backend_policy_result* result)
{
    static const uint32_t orderedBackends[] = {
        CF7_AUDIO_BACKEND_POLICY_WASAPI,
        CF7_AUDIO_BACKEND_POLICY_DIRECTSOUND,
        CF7_AUDIO_BACKEND_POLICY_WINMM
    };
    uint32_t index;

    if (tryBackend == NULL || result == NULL) {
        return -1;
    }
    memset(result, 0, sizeof(*result));

    for (index = 0u;
         index < (uint32_t)(sizeof(orderedBackends) / sizeof(orderedBackends[0]));
         ++index) {
        uint32_t failureStage = CF7_AUDIO_BACKEND_POLICY_STAGE_CONTEXT;
        int32_t nativeResult = 0;
        int32_t attemptResult;

        result->attempts += 1u;
        result->lastAttemptedBackend = orderedBackends[index];
        attemptResult = tryBackend(
            userData,
            orderedBackends[index],
            &failureStage,
            &nativeResult);
        if (attemptResult == 0) {
            result->selectedBackend = orderedBackends[index];
            result->lastFailureStage = 0u;
            result->lastNativeResult = 0;
            return 0;
        }

        result->lastFailureStage = failureStage;
        result->lastNativeResult = nativeResult;
    }

    return -2;
}
