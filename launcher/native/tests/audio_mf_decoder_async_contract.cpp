#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>

#include "audio_mf_decoder.h"
#include "miniaudio.h"

#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {

int g_checks = 0;

bool check(bool condition, const char* expression, int line) {
    ++g_checks;
    if (!condition) {
        std::fprintf(stderr, "FAIL line=%d expression=%s\n", line, expression);
        return false;
    }
    return true;
}

#define CHECK(expression) \
    do { \
        if (!check((expression), #expression, __LINE__)) { \
            return 1; \
        } \
    } while (false)

constexpr DWORD kReadWaitMilliseconds = 50U;
constexpr DWORD kCallbackDelayMilliseconds = 600U;
constexpr DWORD kLateCallbackDrainMilliseconds = 900U;
constexpr ULONGLONG kMaximumReadElapsedMilliseconds = 400U;
constexpr ULONGLONG kMaximumUninitElapsedMilliseconds = 500U;
constexpr int kIterations = 4;

struct TimedCancel {
    ULONGLONG cancelAt;
};

ma_bool32 should_cancel(void* userData) {
    const auto* cancel = static_cast<const TimedCancel*>(userData);
    return cancel != nullptr && GetTickCount64() >= cancel->cancelAt
        ? MA_TRUE
        : MA_FALSE;
}

int run_iteration(const wchar_t* path, bool cancellationCase) {
    const ULONGLONG iterationStarted = GetTickCount64();
    const ULONGLONG startupStarted = GetTickCount64();
    CHECK(cf7_audio_mf_runtime_startup() == MA_SUCCESS);
    const ULONGLONG startupElapsed = GetTickCount64() - startupStarted;
    cf7_audio_mf_test_reset_counters();

    cf7_audio_mf_decode_control control{};
    control.struct_size = sizeof(control);
    control.revision = CF7_AUDIO_MF_DECODE_CONTROL_REVISION;
    control.maximum_read_wait_milliseconds = cancellationCase
        ? 1000U
        : kReadWaitMilliseconds;
    control.wait_slice_milliseconds = 5U;
    control.fault_flags = CF7_AUDIO_MF_FAULT_DELAY_READ_CALLBACK;
    control.fault_delay_milliseconds = kCallbackDelayMilliseconds;
    TimedCancel cancel{};
    if (cancellationCase) {
        control.should_cancel = should_cancel;
        control.cancel_user_data = &cancel;
    }

    ma_decoding_backend_vtable* backends[] = {
        cf7_audio_decoding_backend_mf_aac
    };
    ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 0, 0);
    config.ppCustomBackendVTables = backends;
    config.customBackendCount = 1;
    config.pCustomBackendUserData = &control;

    ma_decoder decoder{};
    const ULONGLONG initStarted = GetTickCount64();
    CHECK(ma_decoder_init_file_w(path, &config, &decoder) == MA_SUCCESS);
    const ULONGLONG initElapsed = GetTickCount64() - initStarted;
    CHECK(decoder.outputChannels > 0 && decoder.outputChannels <= MA_MAX_CHANNELS);
    if (cancellationCase) {
        cancel.cancelAt = GetTickCount64() + 100U;
    }

    std::vector<float> frames(
        static_cast<std::size_t>(decoder.outputChannels) * 4096U);
    ma_uint64 framesRead = 0;
    const ULONGLONG readStarted = GetTickCount64();
    const ma_result readResult = ma_decoder_read_pcm_frames(
        &decoder,
        frames.data(),
        4096U,
        &framesRead);
    const ULONGLONG readElapsed = GetTickCount64() - readStarted;
    CHECK(readResult == (cancellationCase ? MA_CANCELLED : MA_TIMEOUT));
    CHECK(framesRead == 0);
    CHECK(readElapsed >= kReadWaitMilliseconds);
    CHECK(readElapsed <= kMaximumReadElapsedMilliseconds);
    CHECK(cf7_audio_mf_test_read_request_count() == 1U);
    CHECK(cf7_audio_mf_test_flush_request_count() == 1U);

    const ULONGLONG seekStarted = GetTickCount64();
    CHECK(ma_decoder_seek_to_pcm_frame(&decoder, 100U) != MA_SUCCESS);
    CHECK(GetTickCount64() - seekStarted < kReadWaitMilliseconds);
    CHECK(cf7_audio_mf_test_terminal_seek_reject_count() == 1U);

    const ULONGLONG uninitStarted = GetTickCount64();
    ma_decoder_uninit(&decoder);
    const ULONGLONG uninitElapsed = GetTickCount64() - uninitStarted;
    CHECK(uninitElapsed <= kMaximumUninitElapsedMilliseconds);
    CHECK(cf7_audio_mf_test_retired_session_count() == 1U);
    CHECK(cf7_audio_mf_runtime_startup() == MA_BUSY);

    Sleep(kLateCallbackDrainMilliseconds);
    const ULONGLONG shutdownStarted = GetTickCount64();
    cf7_audio_mf_runtime_shutdown();
    const ULONGLONG shutdownElapsed = GetTickCount64() - shutdownStarted;
    CHECK(cf7_audio_mf_test_read_callback_count() == 1U);
    CHECK(cf7_audio_mf_test_flush_callback_count() == 1U);
    CHECK(cf7_audio_mf_test_retired_session_count() == 0U);
    CHECK(cf7_audio_mf_test_callback_instance_count() == 0U);
    std::printf(
        "MF async iteration mode=%s startup=%llu init=%llu read=%llu uninit=%llu shutdown=%llu total=%llu ms\n",
        cancellationCase ? "cancel" : "timeout",
        static_cast<unsigned long long>(startupElapsed),
        static_cast<unsigned long long>(initElapsed),
        static_cast<unsigned long long>(readElapsed),
        static_cast<unsigned long long>(uninitElapsed),
        static_cast<unsigned long long>(shutdownElapsed),
        static_cast<unsigned long long>(GetTickCount64() - iterationStarted));
    return 0;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) {
        std::fwprintf(stderr, L"usage: %ls <large-m4a-path>\n", argv[0]);
        return 2;
    }
    const DWORD attributes = GetFileAttributesW(argv[1]);
    CHECK(attributes != INVALID_FILE_ATTRIBUTES);
    CHECK((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0);

    for (int iteration = 0; iteration < kIterations; ++iteration) {
        const int result = run_iteration(argv[1], iteration == kIterations - 1);
        if (result != 0) {
            return result;
        }
    }
    std::printf(
        "audio MF async contract PASS checks=%d iterations=%d\n",
        g_checks,
        kIterations);
    return 0;
}
