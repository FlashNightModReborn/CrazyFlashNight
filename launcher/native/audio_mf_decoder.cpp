#include "audio_mf_decoder.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <shlwapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <utility>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

constexpr std::uint64_t kMaxEncodedBytes = 512ULL * 1024ULL * 1024ULL;
constexpr LONGLONG kHundredNanosecondsPerSecond = 10000000LL;
constexpr DWORD kCleanupWaitMilliseconds = CF7_AUDIO_MF_CLEANUP_WAIT_MS;
constexpr DWORD kCleanupPollMilliseconds = 5U;

SRWLOCK g_mfLock = SRWLOCK_INIT;
bool g_mfStarted = false;
volatile LONG g_callbackInstanceCount = 0;
volatile LONG64 g_readRequestCount = 0;
volatile LONG64 g_readCallbackCount = 0;
volatile LONG64 g_flushRequestCount = 0;
volatile LONG64 g_flushCallbackCount = 0;
volatile LONG64 g_terminalSeekRejectCount = 0;
CO_MTA_USAGE_COOKIE g_mtaUsageCookie = nullptr;
bool g_mtaUsageHeld = false;

class Cf7MfSourceReaderCallback final : public IMFSourceReaderCallback {
public:
    enum class Phase {
        Idle,
        ReadPending,
        ReadReady,
        FlushPending,
        Terminal
    };

    Cf7MfSourceReaderCallback()
        : references_(1),
          readEvent_(CreateEventW(nullptr, TRUE, FALSE, nullptr)),
          flushEvent_(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {
        InitializeSRWLock(&lock_);
        InterlockedIncrement(&g_callbackInstanceCount);
    }

    bool valid() const {
        return readEvent_ != nullptr && flushEvent_ != nullptr;
    }

    HANDLE read_event() const {
        return readEvent_;
    }

    HANDLE flush_event() const {
        return flushEvent_;
    }

    bool prepare_read(bool suppressSignal, DWORD callbackDelayMilliseconds) {
        bool accepted;
        AcquireSRWLockExclusive(&lock_);
        accepted = phase_ == Phase::Idle;
        if (accepted) {
            ResetEvent(readEvent_);
            readStatus_ = E_PENDING;
            readFlags_ = 0;
            readSample_.Reset();
            phase_ = Phase::ReadPending;
            suppressReadSignal_ = suppressSignal;
            callbackDelayMilliseconds_ = callbackDelayMilliseconds;
        }
        ReleaseSRWLockExclusive(&lock_);
        return accepted;
    }

    void fail_synchronous_read(HRESULT status) {
        bool completed = false;
        AcquireSRWLockExclusive(&lock_);
        if (phase_ == Phase::ReadPending) {
            readStatus_ = status;
            readFlags_ = 0;
            readSample_.Reset();
            phase_ = Phase::ReadReady;
            completed = true;
        }
        ReleaseSRWLockExclusive(&lock_);
        if (completed) {
            SetEvent(readEvent_);
        }
    }

    bool take_read(
        HRESULT* status,
        DWORD* flags,
        ComPtr<IMFSample>* sample) {
        bool ready = false;
        AcquireSRWLockExclusive(&lock_);
        if (phase_ == Phase::ReadReady) {
            *status = readStatus_;
            *flags = readFlags_;
            *sample = readSample_;
            readSample_.Reset();
            phase_ = Phase::Idle;
            ready = true;
        }
        ReleaseSRWLockExclusive(&lock_);
        return ready;
    }

    bool mark_terminal() {
        bool flushRequired = false;
        AcquireSRWLockExclusive(&lock_);
        if (phase_ != Phase::Terminal && phase_ != Phase::FlushPending) {
            phase_ = Phase::FlushPending;
            flushRequired = true;
            ResetEvent(flushEvent_);
        }
        readSample_.Reset();
        ReleaseSRWLockExclusive(&lock_);
        SetEvent(readEvent_);
        return flushRequired;
    }

    void mark_terminal_without_flush() {
        AcquireSRWLockExclusive(&lock_);
        phase_ = Phase::Terminal;
        readSample_.Reset();
        ReleaseSRWLockExclusive(&lock_);
        SetEvent(flushEvent_);
        SetEvent(readEvent_);
    }

    bool is_idle() {
        bool idle;
        AcquireSRWLockShared(&lock_);
        idle = phase_ == Phase::Idle;
        ReleaseSRWLockShared(&lock_);
        return idle;
    }

    bool flush_complete() {
        bool complete;
        AcquireSRWLockShared(&lock_);
        complete = phase_ == Phase::Terminal;
        ReleaseSRWLockShared(&lock_);
        return complete;
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** value) override {
        if (value == nullptr) {
            return E_POINTER;
        }
        *value = nullptr;
        if (iid == IID_IUnknown || iid == __uuidof(IMFSourceReaderCallback)) {
            *value = static_cast<IMFSourceReaderCallback*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return static_cast<ULONG>(InterlockedIncrement(&references_));
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining =
            static_cast<ULONG>(InterlockedDecrement(&references_));
        if (remaining == 0) {
            delete this;
        }
        return remaining;
    }

    STDMETHODIMP OnReadSample(
        HRESULT status,
        DWORD,
        DWORD flags,
        LONGLONG,
        IMFSample* sample) override {
        InterlockedIncrement64(&g_readCallbackCount);
        bool signal = true;
        DWORD delayMilliseconds = 0;
        AcquireSRWLockShared(&lock_);
        if (phase_ == Phase::ReadPending) {
            delayMilliseconds = callbackDelayMilliseconds_;
        }
        ReleaseSRWLockShared(&lock_);
        if (delayMilliseconds != 0) {
            Sleep(delayMilliseconds);
        }
        AcquireSRWLockExclusive(&lock_);
        if (phase_ == Phase::ReadPending) {
            readStatus_ = status;
            readFlags_ = flags;
            readSample_ = sample;
            phase_ = Phase::ReadReady;
            signal = !suppressReadSignal_;
        }
        ReleaseSRWLockExclusive(&lock_);
        if (signal) {
            SetEvent(readEvent_);
        }
        return S_OK;
    }

    STDMETHODIMP OnEvent(DWORD, IMFMediaEvent*) override {
        return S_OK;
    }

    STDMETHODIMP OnFlush(DWORD) override {
        InterlockedIncrement64(&g_flushCallbackCount);
        AcquireSRWLockExclusive(&lock_);
        phase_ = Phase::Terminal;
        readSample_.Reset();
        ReleaseSRWLockExclusive(&lock_);
        SetEvent(flushEvent_);
        SetEvent(readEvent_);
        return S_OK;
    }

private:
    ~Cf7MfSourceReaderCallback() {
        if (readEvent_ != nullptr) {
            CloseHandle(readEvent_);
        }
        if (flushEvent_ != nullptr) {
            CloseHandle(flushEvent_);
        }
        InterlockedDecrement(&g_callbackInstanceCount);
    }

    LONG references_;
    SRWLOCK lock_;
    HANDLE readEvent_;
    HANDLE flushEvent_;
    HRESULT readStatus_ = E_PENDING;
    DWORD readFlags_ = 0;
    ComPtr<IMFSample> readSample_;
    Phase phase_ = Phase::Idle;
    bool suppressReadSignal_ = false;
    DWORD callbackDelayMilliseconds_ = 0;
};

class Cf7ScopedComMta final {
public:
    Cf7ScopedComMta() : status_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}

    ~Cf7ScopedComMta() {
        if (SUCCEEDED(status_)) {
            CoUninitialize();
        }
    }

    HRESULT status() const {
        return status_;
    }

private:
    HRESULT status_;
};

struct Cf7MfRetiredSession {
    Cf7MfRetiredSession* next = nullptr;
    std::vector<std::uint8_t> encodedBytes;
    ComPtr<IStream> stream;
    ComPtr<IMFByteStream> byteStream;
    ComPtr<IMFSourceReaderCallback> callback;
    Cf7MfSourceReaderCallback* callbackState = nullptr;
    ComPtr<IMFSourceReader> reader;
};

SRWLOCK g_retiredLock = SRWLOCK_INIT;
Cf7MfRetiredSession* g_retiredHead = nullptr;
std::uint32_t g_retiredCount = 0;
bool g_mfTeardownDeferred = false;

struct Cf7MfDecoder {
    ma_data_source_base ds;
    ma_format format;
    ma_uint32 channels;
    ma_uint32 sampleRate;
    ma_uint64 cursorFrames;
    ma_uint64 lengthFrames;
    bool hasLength;
    bool atEnd;
    bool dataSourceInitialized;
    bool terminal;
    bool flushRequested;
    cf7_audio_mf_decode_control control;
    std::vector<std::uint8_t> encodedBytes;
    std::vector<std::uint8_t> decodedBytes;
    std::size_t decodedOffset;
    ComPtr<IStream> stream;
    ComPtr<IMFByteStream> byteStream;
    ComPtr<IMFSourceReaderCallback> callback;
    Cf7MfSourceReaderCallback* callbackState;
    ComPtr<IMFSourceReader> reader;
    Cf7MfRetiredSession* retirement;
};

std::uint32_t retired_session_count() {
    std::uint32_t count;
    AcquireSRWLockShared(&g_retiredLock);
    count = g_retiredCount;
    ReleaseSRWLockShared(&g_retiredLock);
    return count;
}

void drain_retired_sessions() {
    for (;;) {
        Cf7MfRetiredSession* ready = nullptr;
        AcquireSRWLockExclusive(&g_retiredLock);
        Cf7MfRetiredSession** link = &g_retiredHead;
        while (*link != nullptr) {
            Cf7MfRetiredSession* candidate = *link;
            if (candidate->callbackState == nullptr ||
                candidate->callbackState->flush_complete()) {
                *link = candidate->next;
                candidate->next = nullptr;
                if (g_retiredCount > 0) {
                    --g_retiredCount;
                }
                ready = candidate;
                break;
            }
            link = &candidate->next;
        }
        ReleaseSRWLockExclusive(&g_retiredLock);
        if (ready == nullptr) {
            return;
        }
        delete ready;
    }
}

void quarantine_decoder_session(Cf7MfDecoder* decoder) {
    Cf7MfRetiredSession* retired = decoder->retirement;
    if (retired == nullptr) {
        return;
    }
    decoder->retirement = nullptr;
    retired->encodedBytes = std::move(decoder->encodedBytes);
    retired->stream = std::move(decoder->stream);
    retired->byteStream = std::move(decoder->byteStream);
    retired->callback = std::move(decoder->callback);
    retired->callbackState = decoder->callbackState;
    retired->reader = std::move(decoder->reader);
    decoder->callbackState = nullptr;
    AcquireSRWLockExclusive(&g_mfLock);
    g_mfTeardownDeferred = true;
    ReleaseSRWLockExclusive(&g_mfLock);
    AcquireSRWLockExclusive(&g_retiredLock);
    retired->next = g_retiredHead;
    g_retiredHead = retired;
    ++g_retiredCount;
    ReleaseSRWLockExclusive(&g_retiredLock);
}

ma_result result_from_hresult(HRESULT value) {
    if (value == E_OUTOFMEMORY) {
        return MA_OUT_OF_MEMORY;
    }
    if (value == E_INVALIDARG || value == MF_E_INVALIDMEDIATYPE) {
        return MA_INVALID_FILE;
    }
    if (value == MF_E_UNSUPPORTED_BYTESTREAM_TYPE || value == MF_E_TOPO_CODEC_NOT_FOUND ||
        value == MF_E_INVALID_FILE_FORMAT) {
        return MA_FORMAT_NOT_SUPPORTED;
    }
    return MA_ERROR;
}

bool initialize_decode_control(
    const void* userData,
    cf7_audio_mf_decode_control* control) {
    std::memset(control, 0, sizeof(*control));
    control->struct_size = sizeof(*control);
    control->revision = CF7_AUDIO_MF_DECODE_CONTROL_REVISION;
    control->maximum_read_wait_milliseconds =
        CF7_AUDIO_MF_DEFAULT_READ_WAIT_MS;
    control->wait_slice_milliseconds = CF7_AUDIO_MF_DEFAULT_WAIT_SLICE_MS;
    if (userData != nullptr) {
        const auto* supplied =
            static_cast<const cf7_audio_mf_decode_control*>(userData);
        if (supplied->struct_size != sizeof(*supplied) ||
            supplied->revision != CF7_AUDIO_MF_DECODE_CONTROL_REVISION ||
            supplied->maximum_read_wait_milliseconds == 0 ||
            supplied->wait_slice_milliseconds == 0 ||
            supplied->wait_slice_milliseconds >
                supplied->maximum_read_wait_milliseconds ||
            (supplied->fault_flags &
                ~(CF7_AUDIO_MF_FAULT_SUPPRESS_READ_SIGNAL |
                  CF7_AUDIO_MF_FAULT_DELAY_READ_CALLBACK)) != 0 ||
            (((supplied->fault_flags &
                   CF7_AUDIO_MF_FAULT_DELAY_READ_CALLBACK) != 0) !=
                (supplied->fault_delay_milliseconds != 0)) ||
            supplied->fault_delay_milliseconds > 5000U) {
            return false;
        }
        *control = *supplied;
    }
    return true;
}

bool decode_cancelled(const Cf7MfDecoder* decoder) {
    return decoder->control.should_cancel != nullptr &&
        decoder->control.should_cancel(decoder->control.cancel_user_data) != MA_FALSE;
}

bool abort_async_reader(Cf7MfDecoder* decoder, DWORD waitMilliseconds) {
    if (decoder == nullptr) {
        return true;
    }
    decoder->terminal = true;
    if (decoder->callbackState == nullptr || !decoder->reader) {
        return true;
    }
    if (!decoder->flushRequested) {
        (void)decoder->callbackState->mark_terminal();
        decoder->flushRequested = true;
        InterlockedIncrement64(&g_flushRequestCount);
        const HRESULT flushResult = decoder->reader->Flush(
            static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS));
        if (FAILED(flushResult)) {
            return false;
        }
    }
    if (decoder->callbackState->flush_complete()) {
        return true;
    }
    if (waitMilliseconds == 0) {
        return false;
    }
    const DWORD waitResult = WaitForSingleObject(
        decoder->callbackState->flush_event(),
        waitMilliseconds);
    return waitResult == WAIT_OBJECT_0 &&
        decoder->callbackState->flush_complete();
}

ma_result read_async_sample(
    Cf7MfDecoder* decoder,
    DWORD* flags,
    ComPtr<IMFSample>* sample) {
    if (decoder == nullptr || flags == nullptr || sample == nullptr ||
        decoder->callbackState == nullptr || !decoder->reader ||
        decoder->terminal) {
        return MA_INVALID_OPERATION;
    }
    if (decode_cancelled(decoder)) {
        (void)abort_async_reader(decoder, 0);
        return MA_CANCELLED;
    }
    const ULONGLONG started = GetTickCount64();
    ULONGLONG deadline =
        decoder->control.maximum_read_wait_milliseconds >
                (std::numeric_limits<ULONGLONG>::max)() - started
            ? (std::numeric_limits<ULONGLONG>::max)()
            : started + decoder->control.maximum_read_wait_milliseconds;
    if (decoder->control.deadline_tick_milliseconds != 0 &&
        decoder->control.deadline_tick_milliseconds < deadline) {
        deadline = decoder->control.deadline_tick_milliseconds;
    }
    if (GetTickCount64() >= deadline) {
        (void)abort_async_reader(decoder, 0);
        return MA_TIMEOUT;
    }
    const bool suppressSignal =
        (decoder->control.fault_flags &
            CF7_AUDIO_MF_FAULT_SUPPRESS_READ_SIGNAL) != 0;
    const DWORD callbackDelayMilliseconds =
        (decoder->control.fault_flags &
            CF7_AUDIO_MF_FAULT_DELAY_READ_CALLBACK) != 0
        ? decoder->control.fault_delay_milliseconds
        : 0;
    if (!decoder->callbackState->prepare_read(
            suppressSignal,
            callbackDelayMilliseconds)) {
        return MA_CANCELLED;
    }
    InterlockedIncrement64(&g_readRequestCount);
    HRESULT status = decoder->reader->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
        0,
        nullptr,
        nullptr,
        nullptr,
        nullptr);
    if (FAILED(status)) {
        decoder->callbackState->fail_synchronous_read(status);
        (void)abort_async_reader(decoder, 0);
        return result_from_hresult(status);
    }

    for (;;) {
        if (decode_cancelled(decoder)) {
            (void)abort_async_reader(decoder, 0);
            return MA_CANCELLED;
        }
        const ULONGLONG now = GetTickCount64();
        if (now >= deadline) {
            (void)abort_async_reader(decoder, 0);
            return MA_TIMEOUT;
        }
        ULONGLONG remaining = deadline - now;
        DWORD waitMilliseconds = decoder->control.wait_slice_milliseconds;
        if (remaining < waitMilliseconds) {
            waitMilliseconds = static_cast<DWORD>(remaining);
        }
        if (waitMilliseconds == 0) {
            waitMilliseconds = 1;
        }
        const DWORD waitResult = WaitForSingleObject(
            decoder->callbackState->read_event(),
            waitMilliseconds);
        if (waitResult == WAIT_OBJECT_0) {
            if (decoder->callbackState->take_read(&status, flags, sample)) {
                return SUCCEEDED(status)
                    ? MA_SUCCESS
                    : result_from_hresult(status);
            }
            if (decoder->terminal) {
                return MA_CANCELLED;
            }
        } else if (waitResult == WAIT_FAILED) {
            (void)abort_async_reader(decoder, 0);
            return MA_ERROR;
        }
    }
}

bool is_mpeg4_audio(const std::vector<std::uint8_t>& bytes) {
    return bytes.size() >= 12 &&
        bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p';
}

bool is_adts_aac(const std::vector<std::uint8_t>& bytes) {
    return bytes.size() >= 7 && bytes[0] == 0xFF && (bytes[1] & 0xF6) == 0xF0;
}

ma_result read_encoded_input(
    ma_read_proc onRead,
    ma_seek_proc onSeek,
    ma_tell_proc onTell,
    void* userData,
    std::vector<std::uint8_t>* bytesOut) {
    ma_int64 original = 0;
    ma_int64 length = 0;
    if (onRead == nullptr || onSeek == nullptr || onTell == nullptr || bytesOut == nullptr) {
        return MA_INVALID_ARGS;
    }
    if (onTell(userData, &original) != MA_SUCCESS ||
        onSeek(userData, 0, ma_seek_origin_end) != MA_SUCCESS ||
        onTell(userData, &length) != MA_SUCCESS ||
        onSeek(userData, 0, ma_seek_origin_start) != MA_SUCCESS) {
        return MA_INVALID_FILE;
    }
    if (length <= 0 || static_cast<std::uint64_t>(length) > kMaxEncodedBytes ||
        static_cast<std::uint64_t>(length) > (std::numeric_limits<UINT>::max)()) {
        (void)onSeek(userData, original, ma_seek_origin_start);
        return MA_INVALID_FILE;
    }

    try {
        bytesOut->resize(static_cast<std::size_t>(length));
    } catch (...) {
        (void)onSeek(userData, original, ma_seek_origin_start);
        return MA_OUT_OF_MEMORY;
    }

    std::size_t total = 0;
    while (total < bytesOut->size()) {
        size_t readNow = 0;
        const ma_result result = onRead(
            userData,
            bytesOut->data() + total,
            bytesOut->size() - total,
            &readNow);
        if ((result != MA_SUCCESS && result != MA_AT_END) || readNow == 0) {
            (void)onSeek(userData, original, ma_seek_origin_start);
            bytesOut->clear();
            return MA_INVALID_FILE;
        }
        total += readNow;
    }
    (void)onSeek(userData, original, ma_seek_origin_start);
    return MA_SUCCESS;
}

ma_result refresh_output_type(Cf7MfDecoder* decoder) {
    ComPtr<IMFMediaType> outputType;
    HRESULT hr = decoder->reader->GetCurrentMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
        &outputType);
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }
    decoder->channels = MFGetAttributeUINT32(outputType.Get(), MF_MT_AUDIO_NUM_CHANNELS, 0);
    decoder->sampleRate = MFGetAttributeUINT32(outputType.Get(), MF_MT_AUDIO_SAMPLES_PER_SECOND, 0);
    if (decoder->channels == 0 || decoder->channels > MA_MAX_CHANNELS || decoder->sampleRate == 0) {
        return MA_INVALID_FILE;
    }
    decoder->format = ma_format_f32;
    return MA_SUCCESS;
}

ma_result initialize_source_reader(Cf7MfDecoder* decoder, bool mpeg4) {
    decoder->stream.Attach(SHCreateMemStream(
        decoder->encodedBytes.data(),
        static_cast<UINT>(decoder->encodedBytes.size())));
    if (!decoder->stream) {
        return MA_OUT_OF_MEMORY;
    }

    HRESULT hr = MFCreateMFByteStreamOnStreamEx(decoder->stream.Get(), &decoder->byteStream);
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }

    ComPtr<IMFAttributes> byteStreamAttributes;
    if (SUCCEEDED(decoder->byteStream.As(&byteStreamAttributes))) {
        (void)byteStreamAttributes->SetString(
            MF_BYTESTREAM_CONTENT_TYPE,
            mpeg4 ? L"audio/mp4" : L"audio/aac");
    }

    auto* callbackState = new (std::nothrow) Cf7MfSourceReaderCallback();
    if (callbackState == nullptr || !callbackState->valid()) {
        if (callbackState != nullptr) {
            callbackState->Release();
        }
        return MA_OUT_OF_MEMORY;
    }
    decoder->callback.Attach(callbackState);
    decoder->callbackState = callbackState;

    ComPtr<IMFAttributes> readerAttributes;
    hr = MFCreateAttributes(&readerAttributes, 2);
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }
    hr = readerAttributes->SetUINT32(MF_READWRITE_DISABLE_CONVERTERS, FALSE);
    if (SUCCEEDED(hr)) {
        hr = readerAttributes->SetUnknown(
            MF_SOURCE_READER_ASYNC_CALLBACK,
            decoder->callback.Get());
    }
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }

    hr = MFCreateSourceReaderFromByteStream(
        decoder->byteStream.Get(),
        readerAttributes.Get(),
        &decoder->reader);
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }

    (void)decoder->reader->SetStreamSelection(
        static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS),
        FALSE);
    hr = decoder->reader->SetStreamSelection(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
        TRUE);
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }

    ComPtr<IMFMediaType> nativeType;
    hr = decoder->reader->GetNativeMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
        0,
        &nativeType);
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }
    GUID subtype = GUID_NULL;
    hr = nativeType->GetGUID(MF_MT_SUBTYPE, &subtype);
    if (FAILED(hr) || (subtype != MFAudioFormat_AAC && subtype != MFAudioFormat_ADTS)) {
        return MA_FORMAT_NOT_SUPPORTED;
    }

    ComPtr<IMFMediaType> requestedType;
    hr = MFCreateMediaType(&requestedType);
    if (FAILED(hr) ||
        FAILED(requestedType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio)) ||
        FAILED(requestedType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float))) {
        return result_from_hresult(FAILED(hr) ? hr : E_FAIL);
    }
    hr = decoder->reader->SetCurrentMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
        nullptr,
        requestedType.Get());
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }

    ma_result result = refresh_output_type(decoder);
    if (result != MA_SUCCESS) {
        return result;
    }

    PROPVARIANT duration;
    PropVariantInit(&duration);
    hr = decoder->reader->GetPresentationAttribute(
        static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE),
        MF_PD_DURATION,
        &duration);
    if (SUCCEEDED(hr) && duration.vt == VT_UI8 && duration.uhVal.QuadPart > 0) {
        const unsigned long long value = duration.uhVal.QuadPart;
        const unsigned long long wholeSeconds =
            value / static_cast<unsigned long long>(kHundredNanosecondsPerSecond);
        const unsigned long long remainder =
            value % static_cast<unsigned long long>(kHundredNanosecondsPerSecond);
        const unsigned long long maxFrames = (std::numeric_limits<ma_uint64>::max)();
        if (wholeSeconds <= maxFrames / decoder->sampleRate) {
            const ma_uint64 wholeFrames =
                static_cast<ma_uint64>(wholeSeconds) * decoder->sampleRate;
            const ma_uint64 partialFrames = static_cast<ma_uint64>(
                (remainder * decoder->sampleRate + kHundredNanosecondsPerSecond - 1) /
                kHundredNanosecondsPerSecond);
            if (partialFrames <= maxFrames - wholeFrames) {
                decoder->lengthFrames = wholeFrames + partialFrames;
                decoder->hasLength = true;
            }
        }
    }
    PropVariantClear(&duration);
    return MA_SUCCESS;
}

ma_result mf_read_frames(
    ma_data_source* dataSource,
    void* framesOut,
    ma_uint64 frameCount,
    ma_uint64* framesReadOut) {
    auto* decoder = reinterpret_cast<Cf7MfDecoder*>(dataSource);
    if (framesReadOut != nullptr) {
        *framesReadOut = 0;
    }
    if (decoder == nullptr || (framesOut == nullptr && frameCount > 0)) {
        return MA_INVALID_ARGS;
    }
    if (frameCount == 0) {
        return MA_SUCCESS;
    }
    if (decoder->terminal) {
        return MA_CANCELLED;
    }
    Cf7ScopedComMta com;
    if (FAILED(com.status())) {
        return result_from_hresult(com.status());
    }

    const std::size_t bytesPerFrame = decoder->channels * sizeof(float);
    auto* output = static_cast<std::uint8_t*>(framesOut);
    ma_uint64 totalFrames = 0;
    unsigned emptySamples = 0;

    while (totalFrames < frameCount) {
        if (decoder->decodedOffset < decoder->decodedBytes.size()) {
            const std::size_t availableBytes = decoder->decodedBytes.size() - decoder->decodedOffset;
            const ma_uint64 availableFrames = static_cast<ma_uint64>(availableBytes / bytesPerFrame);
            const ma_uint64 copyFrames = (std::min)(frameCount - totalFrames, availableFrames);
            const std::size_t copyBytes = static_cast<std::size_t>(copyFrames) * bytesPerFrame;
            std::memcpy(
                output + static_cast<std::size_t>(totalFrames) * bytesPerFrame,
                decoder->decodedBytes.data() + decoder->decodedOffset,
                copyBytes);
            decoder->decodedOffset += copyBytes;
            totalFrames += copyFrames;
            decoder->cursorFrames += copyFrames;
            continue;
        }

        decoder->decodedBytes.clear();
        decoder->decodedOffset = 0;
        if (decoder->atEnd) {
            break;
        }

        DWORD flags = 0;
        ComPtr<IMFSample> sample;
        const ma_result readResult = read_async_sample(
            decoder,
            &flags,
            &sample);
        if (readResult != MA_SUCCESS) {
            return readResult;
        }
        if ((flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) != 0) {
            const ma_uint32 expectedChannels = decoder->channels;
            const ma_uint32 expectedSampleRate = decoder->sampleRate;
            if (refresh_output_type(decoder) != MA_SUCCESS ||
                decoder->channels != expectedChannels ||
                decoder->sampleRate != expectedSampleRate) {
                return MA_FORMAT_NOT_SUPPORTED;
            }
        }
        if ((flags & MF_SOURCE_READERF_ENDOFSTREAM) != 0) {
            decoder->atEnd = true;
        }
        if (!sample) {
            if (decoder->atEnd) {
                break;
            }
            if (++emptySamples > 1024) {
                return MA_ERROR;
            }
            continue;
        }

        ComPtr<IMFMediaBuffer> buffer;
        if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) {
            return MA_ERROR;
        }
        BYTE* bytes = nullptr;
        DWORD maximumLength = 0;
        DWORD currentLength = 0;
        if (FAILED(buffer->Lock(&bytes, &maximumLength, &currentLength))) {
            return MA_ERROR;
        }
        if (currentLength == 0 || currentLength % bytesPerFrame != 0) {
            (void)buffer->Unlock();
            return MA_INVALID_FILE;
        }
        try {
            decoder->decodedBytes.assign(bytes, bytes + currentLength);
        } catch (...) {
            (void)buffer->Unlock();
            return MA_OUT_OF_MEMORY;
        }
        (void)buffer->Unlock();
    }

    if (framesReadOut != nullptr) {
        *framesReadOut = totalFrames;
    }
    return totalFrames > 0 ? MA_SUCCESS : MA_AT_END;
}

ma_result mf_seek_frame(ma_data_source* dataSource, ma_uint64 frameIndex) {
    auto* decoder = reinterpret_cast<Cf7MfDecoder*>(dataSource);
    if (decoder == nullptr || decoder->sampleRate == 0 || !decoder->reader) {
        return MA_INVALID_ARGS;
    }
    if (decoder->terminal || decoder->callbackState == nullptr ||
        !decoder->callbackState->is_idle()) {
        InterlockedIncrement64(&g_terminalSeekRejectCount);
        return MA_INVALID_OPERATION;
    }
    if (frameIndex > static_cast<ma_uint64>((std::numeric_limits<LONGLONG>::max)() / kHundredNanosecondsPerSecond)) {
        return MA_INVALID_ARGS;
    }
    Cf7ScopedComMta com;
    if (FAILED(com.status())) {
        return result_from_hresult(com.status());
    }
    PROPVARIANT position;
    PropVariantInit(&position);
    position.vt = VT_I8;
    position.hVal.QuadPart = static_cast<LONGLONG>(
        (frameIndex * kHundredNanosecondsPerSecond) / decoder->sampleRate);
    const HRESULT hr = decoder->reader->SetCurrentPosition(GUID_NULL, position);
    PropVariantClear(&position);
    if (FAILED(hr)) {
        return result_from_hresult(hr);
    }
    decoder->decodedBytes.clear();
    decoder->decodedOffset = 0;
    decoder->cursorFrames = frameIndex;
    decoder->atEnd = false;
    return MA_SUCCESS;
}

ma_result mf_get_data_format(
    ma_data_source* dataSource,
    ma_format* format,
    ma_uint32* channels,
    ma_uint32* sampleRate,
    ma_channel* channelMap,
    size_t channelMapCapacity) {
    auto* decoder = reinterpret_cast<Cf7MfDecoder*>(dataSource);
    if (decoder == nullptr) {
        return MA_INVALID_ARGS;
    }
    if (format != nullptr) {
        *format = decoder->format;
    }
    if (channels != nullptr) {
        *channels = decoder->channels;
    }
    if (sampleRate != nullptr) {
        *sampleRate = decoder->sampleRate;
    }
    if (channelMap != nullptr) {
        ma_channel_map_init_standard(
            ma_standard_channel_map_microsoft,
            channelMap,
            channelMapCapacity,
            decoder->channels);
    }
    return MA_SUCCESS;
}

ma_result mf_get_cursor(ma_data_source* dataSource, ma_uint64* cursor) {
    auto* decoder = reinterpret_cast<Cf7MfDecoder*>(dataSource);
    if (decoder == nullptr || cursor == nullptr) {
        return MA_INVALID_ARGS;
    }
    *cursor = decoder->cursorFrames;
    return MA_SUCCESS;
}

ma_result mf_get_length(ma_data_source* dataSource, ma_uint64* length) {
    auto* decoder = reinterpret_cast<Cf7MfDecoder*>(dataSource);
    if (decoder == nullptr || length == nullptr) {
        return MA_INVALID_ARGS;
    }
    if (!decoder->hasLength) {
        *length = 0;
        return MA_NOT_IMPLEMENTED;
    }
    *length = decoder->lengthFrames;
    return MA_SUCCESS;
}

ma_data_source_vtable g_mfDataSourceVtable = {
    mf_read_frames,
    mf_seek_frame,
    mf_get_data_format,
    mf_get_cursor,
    mf_get_length,
    nullptr,
    0
};

ma_result mf_backend_init(
    void* backendUserData,
    ma_read_proc onRead,
    ma_seek_proc onSeek,
    ma_tell_proc onTell,
    void* readUserData,
    const ma_decoding_backend_config*,
    const ma_allocation_callbacks* allocationCallbacks,
    ma_data_source** backendOut) {
    if (backendOut == nullptr) {
        return MA_INVALID_ARGS;
    }
    *backendOut = nullptr;

    cf7_audio_mf_decode_control control;
    if (!initialize_decode_control(backendUserData, &control)) {
        return MA_INVALID_ARGS;
    }

    Cf7ScopedComMta com;
    if (FAILED(com.status())) {
        return result_from_hresult(com.status());
    }
    drain_retired_sessions();
    AcquireSRWLockExclusive(&g_mfLock);
    if (g_mfTeardownDeferred && retired_session_count() == 0) {
        g_mfTeardownDeferred = false;
    }
    const bool mfStarted = g_mfStarted && !g_mfTeardownDeferred;
    ReleaseSRWLockExclusive(&g_mfLock);
    if (!mfStarted) {
        return MA_DEVICE_NOT_INITIALIZED;
    }

    void* storage = ma_malloc(sizeof(Cf7MfDecoder), allocationCallbacks);
    if (storage == nullptr) {
        return MA_OUT_OF_MEMORY;
    }
    auto* decoder = new (storage) Cf7MfDecoder{};
    decoder->format = ma_format_f32;
    decoder->control = control;
    decoder->retirement = new (std::nothrow) Cf7MfRetiredSession();
    if (decoder->retirement == nullptr) {
        decoder->~Cf7MfDecoder();
        ma_free(decoder, allocationCallbacks);
        return MA_OUT_OF_MEMORY;
    }

    ma_result result = read_encoded_input(
        onRead,
        onSeek,
        onTell,
        readUserData,
        &decoder->encodedBytes);
    const bool mpeg4 = result == MA_SUCCESS && is_mpeg4_audio(decoder->encodedBytes);
    const bool adts = result == MA_SUCCESS && is_adts_aac(decoder->encodedBytes);
    if (result != MA_SUCCESS || (!mpeg4 && !adts)) {
        delete decoder->retirement;
        decoder->retirement = nullptr;
        decoder->~Cf7MfDecoder();
        ma_free(decoder, allocationCallbacks);
        return result == MA_SUCCESS ? MA_INVALID_FILE : result;
    }

    ma_data_source_config dataSourceConfig = ma_data_source_config_init();
    dataSourceConfig.vtable = &g_mfDataSourceVtable;
    result = ma_data_source_init(&dataSourceConfig, &decoder->ds);
    if (result == MA_SUCCESS) {
        decoder->dataSourceInitialized = true;
        result = initialize_source_reader(decoder, mpeg4);
    }
    if (result != MA_SUCCESS) {
        const bool cleanupComplete = abort_async_reader(
            decoder,
            kCleanupWaitMilliseconds);
        if (decoder->dataSourceInitialized) {
            ma_data_source_uninit(&decoder->ds);
        }
        if (!cleanupComplete) {
            quarantine_decoder_session(decoder);
        }
        if (decoder->retirement != nullptr) {
            delete decoder->retirement;
            decoder->retirement = nullptr;
        }
        decoder->~Cf7MfDecoder();
        ma_free(decoder, allocationCallbacks);
        return result;
    }

    *backendOut = reinterpret_cast<ma_data_source*>(decoder);
    return MA_SUCCESS;
}

void mf_backend_uninit(
    void*,
    ma_data_source* backend,
    const ma_allocation_callbacks* allocationCallbacks) {
    auto* decoder = reinterpret_cast<Cf7MfDecoder*>(backend);
    if (decoder == nullptr) {
        return;
    }
    Cf7ScopedComMta com;
    const bool cleanupComplete = SUCCEEDED(com.status()) &&
        abort_async_reader(decoder, kCleanupWaitMilliseconds);
    if (decoder->dataSourceInitialized) {
        ma_data_source_uninit(&decoder->ds);
    }
    if (!cleanupComplete) {
        quarantine_decoder_session(decoder);
    }
    if (decoder->retirement != nullptr) {
        delete decoder->retirement;
        decoder->retirement = nullptr;
    }
    decoder->~Cf7MfDecoder();
    ma_free(decoder, allocationCallbacks);
    drain_retired_sessions();
}

ma_decoding_backend_vtable g_mfBackendVtable = {
    mf_backend_init,
    nullptr,
    nullptr,
    nullptr,
    mf_backend_uninit
};

}  // namespace

extern "C" {

ma_decoding_backend_vtable* cf7_audio_decoding_backend_mf_aac = &g_mfBackendVtable;

ma_result cf7_audio_mf_runtime_startup(void) {
    Cf7ScopedComMta com;
    if (FAILED(com.status())) {
        return result_from_hresult(com.status());
    }
    AcquireSRWLockExclusive(&g_mfLock);
    drain_retired_sessions();
    if (g_mfStarted) {
        if (retired_session_count() != 0) {
            ReleaseSRWLockExclusive(&g_mfLock);
            return MA_BUSY;
        }
        g_mfTeardownDeferred = false;
        ReleaseSRWLockExclusive(&g_mfLock);
        return MA_SUCCESS;
    }
    HRESULT hr = CoIncrementMTAUsage(&g_mtaUsageCookie);
    if (SUCCEEDED(hr)) {
        g_mtaUsageHeld = true;
        hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    }
    if (SUCCEEDED(hr)) {
        g_mfStarted = true;
    } else if (g_mtaUsageHeld) {
        (void)CoDecrementMTAUsage(g_mtaUsageCookie);
        g_mtaUsageCookie = nullptr;
        g_mtaUsageHeld = false;
    }
    ReleaseSRWLockExclusive(&g_mfLock);
    return SUCCEEDED(hr) ? MA_SUCCESS : result_from_hresult(hr);
}

void cf7_audio_mf_runtime_shutdown(void) {
    Cf7ScopedComMta com;
    if (FAILED(com.status())) {
        return;
    }
    const ULONGLONG deadline = GetTickCount64() + kCleanupWaitMilliseconds;
    AcquireSRWLockExclusive(&g_mfLock);
    do {
        drain_retired_sessions();
        if (retired_session_count() == 0 || GetTickCount64() >= deadline) {
            break;
        }
        Sleep(kCleanupPollMilliseconds);
    } while (true);
    if (g_mfStarted) {
        if (retired_session_count() == 0) {
            (void)MFShutdown();
            g_mfStarted = false;
            g_mfTeardownDeferred = false;
            if (g_mtaUsageHeld) {
                (void)CoDecrementMTAUsage(g_mtaUsageCookie);
                g_mtaUsageCookie = nullptr;
                g_mtaUsageHeld = false;
            }
        } else {
            g_mfTeardownDeferred = true;
        }
    }
    ReleaseSRWLockExclusive(&g_mfLock);
}

ma_uint32 cf7_audio_mf_test_retired_session_count(void) {
    return static_cast<ma_uint32>(retired_session_count());
}

ma_uint32 cf7_audio_mf_test_callback_instance_count(void) {
    const LONG count = InterlockedCompareExchange(
        &g_callbackInstanceCount,
        0,
        0);
    return count < 0 ? 0U : static_cast<ma_uint32>(count);
}

void cf7_audio_mf_test_reset_counters(void) {
    InterlockedExchange64(&g_readRequestCount, 0);
    InterlockedExchange64(&g_readCallbackCount, 0);
    InterlockedExchange64(&g_flushRequestCount, 0);
    InterlockedExchange64(&g_flushCallbackCount, 0);
    InterlockedExchange64(&g_terminalSeekRejectCount, 0);
}

ma_uint64 cf7_audio_mf_test_read_request_count(void) {
    return static_cast<ma_uint64>(
        InterlockedCompareExchange64(&g_readRequestCount, 0, 0));
}

ma_uint64 cf7_audio_mf_test_read_callback_count(void) {
    return static_cast<ma_uint64>(
        InterlockedCompareExchange64(&g_readCallbackCount, 0, 0));
}

ma_uint64 cf7_audio_mf_test_flush_request_count(void) {
    return static_cast<ma_uint64>(
        InterlockedCompareExchange64(&g_flushRequestCount, 0, 0));
}

ma_uint64 cf7_audio_mf_test_flush_callback_count(void) {
    return static_cast<ma_uint64>(
        InterlockedCompareExchange64(&g_flushCallbackCount, 0, 0));
}

ma_uint64 cf7_audio_mf_test_terminal_seek_reject_count(void) {
    return static_cast<ma_uint64>(
        InterlockedCompareExchange64(&g_terminalSeekRejectCount, 0, 0));
}

}  // extern "C"
