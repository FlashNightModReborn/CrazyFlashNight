#include "../audio_backend_policy.h"

#include <stdio.h>
#include <string.h>

typedef struct fixture {
    int outcomes[3];
    uint32_t stages[3];
    uint32_t seen[3];
    uint32_t count;
} fixture;

static int failures = 0;

#define CHECK(expression) do { \
    if (!(expression)) { \
        fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expression); \
        failures += 1; \
    } \
} while (0)

static int32_t try_backend(
    void* userData,
    uint32_t backend,
    uint32_t* failureStage,
    int32_t* nativeResult)
{
    fixture* value = (fixture*)userData;
    uint32_t index = value->count++;
    value->seen[index] = backend;
    *failureStage = value->stages[index];
    *nativeResult = -(int32_t)(100u + index);
    return value->outcomes[index];
}

int main(void)
{
    fixture value;
    cf7_audio_backend_policy_result result;

    memset(&value, 0, sizeof(value));
    value.outcomes[0] = 0;
    CHECK(cf7_audio_backend_policy_select(try_backend, &value, &result) == 0);
    CHECK(result.selectedBackend == CF7_AUDIO_BACKEND_POLICY_WASAPI);
    CHECK(result.attempts == 1u);

    memset(&value, 0, sizeof(value));
    value.outcomes[0] = -1;
    value.stages[0] = CF7_AUDIO_BACKEND_POLICY_STAGE_DEVICE;
    value.outcomes[1] = 0;
    CHECK(cf7_audio_backend_policy_select(try_backend, &value, &result) == 0);
    CHECK(value.count == 2u);
    CHECK(value.seen[0] == CF7_AUDIO_BACKEND_POLICY_WASAPI);
    CHECK(value.seen[1] == CF7_AUDIO_BACKEND_POLICY_DIRECTSOUND);
    CHECK(result.selectedBackend == CF7_AUDIO_BACKEND_POLICY_DIRECTSOUND);

    memset(&value, 0, sizeof(value));
    value.outcomes[0] = -1;
    value.outcomes[1] = -1;
    value.outcomes[2] = -1;
    value.stages[0] = CF7_AUDIO_BACKEND_POLICY_STAGE_CONTEXT;
    value.stages[1] = CF7_AUDIO_BACKEND_POLICY_STAGE_DEVICE;
    value.stages[2] = CF7_AUDIO_BACKEND_POLICY_STAGE_START;
    CHECK(cf7_audio_backend_policy_select(try_backend, &value, &result) == -2);
    CHECK(value.count == 3u);
    CHECK(value.seen[2] == CF7_AUDIO_BACKEND_POLICY_WINMM);
    CHECK(result.selectedBackend == 0u);
    CHECK(result.lastFailureStage == CF7_AUDIO_BACKEND_POLICY_STAGE_START);
    CHECK(result.lastNativeResult == -102);

    CHECK(cf7_audio_backend_policy_select(NULL, &value, &result) == -1);
    CHECK(cf7_audio_backend_policy_select(try_backend, &value, NULL) == -1);

    if (failures != 0) {
        return 1;
    }
    puts("audio backend policy contract PASS");
    return 0;
}
