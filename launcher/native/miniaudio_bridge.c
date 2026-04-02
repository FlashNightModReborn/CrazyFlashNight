/*
 * miniaudio_bridge.c  v2
 * CF7:ME audio bridge — exports C functions for C# P/Invoke
 *
 * Architecture:
 *   ma_engine
 *   +-- g_bgmGroup (ma_sound_group) -- BGM bus, volume at group level
 *   |   +-- g_bgm[0] (stream)  \ dual-slot crossfade
 *   |   +-- g_bgm[1] (stream)  / individual sounds fade 0<->1
 *   +-- g_sfxGroup (ma_sound_group) -- SFX bus, volume at group level
 *       +-- SfxSlot[0].voices[0..3]  \ 4-voice pool per sound
 *       +-- SfxSlot[1].voices[0..3]  | handle = slot index
 *       +-- ...                       /
 *
 * SFX API is handle-based: load() returns int handle, play() takes int handle.
 * String->handle mapping lives in C# (Dictionary<string,int>).
 *
 * BGM volume is set on g_bgmGroup so it never interferes with per-sound
 * fade curves during crossfade transitions.
 */

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#define MA_EXPORT __declspec(dllexport)
#else
#define MA_EXPORT
#endif

/* ========== Constants ========== */
#define MAX_SFX_SLOTS       1024
#define SFX_VOICES          4       /* overlapping voices per SFX */
#define MAX_WPATH_LEN       1024
#define DEFAULT_THROTTLE_MS 90
#define MIN_FADE_MS         100

/* ========== SFX slot (voice pool) ========== */
typedef struct {
    ma_sound  voices[SFX_VOICES];
    int       voiceInited[SFX_VOICES];
    int       voiceCount;       /* successfully initialized voices */
    int       nextVoice;        /* round-robin index */
    int       loaded;           /* slot is active */
    ULONGLONG lastPlayTime;
} SfxSlot;

/* ========== Peak detector node ========== */
typedef struct {
    ma_node_base base;
    volatile float peakL;
    volatile float peakR;
} PeakDetector;

static void peak_process_pcm(ma_node* pNode, const float** ppFramesIn,
    ma_uint32* pFrameCountIn, float** ppFramesOut, ma_uint32* pFrameCountOut)
{
    PeakDetector* pd = (PeakDetector*)pNode;
    ma_uint32 count = *pFrameCountOut;    /* passthrough: consume = produce */
    const float* in = ppFramesIn[0];
    float* out = ppFramesOut[0];
    float pL = 0.0f, pR = 0.0f;
    ma_uint32 i;

    for (i = 0; i < count; i++) {
        float l = in[i * 2 + 0];
        float r = in[i * 2 + 1];
        float al = l < 0 ? -l : l;
        float ar = r < 0 ? -r : r;
        if (al > pL) pL = al;
        if (ar > pR) pR = ar;
        out[i * 2 + 0] = l;
        out[i * 2 + 1] = r;
    }

    pd->peakL = pL;
    pd->peakR = pR;
    *pFrameCountIn = count;
}

static ma_node_vtable g_peakVtable = {
    peak_process_pcm,
    NULL,   /* onGetRequiredInputFrameCount */
    1,      /* 1 input bus */
    1,      /* 1 output bus */
    0       /* flags */
};

/* ========== Global state ========== */
static ma_engine      g_engine;
static int            g_initialized = 0;
static wchar_t        g_basePath[MAX_WPATH_LEN] = {0};

/* Sound groups (buses) */
static ma_sound_group g_bgmGroup;
static ma_sound_group g_sfxGroup;

/* BGM peak detector (between bgmGroup and engine endpoint) */
static PeakDetector   g_bgmPeak;

/* BGM dual-instance crossfade */
static ma_sound       g_bgm[2];
static int            g_bgmLoaded[2] = {0, 0};
static int            g_bgmActive = 0;

/* SFX — handle = index into g_sfx[] */
static SfxSlot        g_sfx[MAX_SFX_SLOTS];
static int            g_sfxCount = 0;
static int            g_throttleMs = DEFAULT_THROTTLE_MS;

/* ========== Helpers ========== */

/*
 * _snwprintf on MSVC does NOT guarantee null-termination on overflow.
 * We always manually terminate after the call.
 */
static void resolve_wpath(const wchar_t* relPath, wchar_t* out, int outLen) {
    wchar_t* p;
    if (g_basePath[0] != L'\0') {
        _snwprintf(out, outLen, L"%s/%s", g_basePath, relPath);
    } else {
        _snwprintf(out, outLen, L"%s", relPath);
    }
    out[outLen - 1] = L'\0';
    /* Normalize backslashes to forward slashes */
    for (p = out; *p; p++) {
        if (*p == L'\\') *p = L'/';
    }
}

static void bgm_uninit_slot(int slot) {
    if (g_bgmLoaded[slot]) {
        ma_sound_uninit(&g_bgm[slot]);
        g_bgmLoaded[slot] = 0;
    }
}

/* ========== Lifecycle ========== */

MA_EXPORT int ma_bridge_init(const wchar_t* basePath) {
    ma_engine_config config;
    ma_result result;

    if (g_initialized) return 0;

    if (basePath != NULL) {
        wcsncpy(g_basePath, basePath, MAX_WPATH_LEN - 1);
        g_basePath[MAX_WPATH_LEN - 1] = L'\0';
    }

    config = ma_engine_config_init();
    result = ma_engine_init(&config, &g_engine);
    if (result != MA_SUCCESS) return -1;

    /* Initialize sound groups (buses) */
    result = ma_sound_group_init(&g_engine, 0, NULL, &g_bgmGroup);
    if (result != MA_SUCCESS) {
        ma_engine_uninit(&g_engine);
        return -1;
    }
    result = ma_sound_group_init(&g_engine, 0, NULL, &g_sfxGroup);
    if (result != MA_SUCCESS) {
        ma_sound_group_uninit(&g_bgmGroup);
        ma_engine_uninit(&g_engine);
        return -1;
    }

    /* Initialize BGM peak detector node (stereo passthrough) */
    {
        ma_node_config peakCfg;
        ma_uint32 inCh[1], outCh[1];
        ma_uint32 ch = ma_engine_get_channels(&g_engine);
        if (ch < 2) ch = 2; /* force stereo for peak L/R */
        inCh[0] = ch;
        outCh[0] = ch;
        peakCfg = ma_node_config_init();
        peakCfg.vtable = &g_peakVtable;
        peakCfg.pInputChannels = inCh;
        peakCfg.pOutputChannels = outCh;
        peakCfg.initialState = ma_node_state_started;

        memset(&g_bgmPeak, 0, sizeof(g_bgmPeak));
        result = ma_node_init(ma_engine_get_node_graph(&g_engine),
            &peakCfg, NULL, &g_bgmPeak.base);
        if (result == MA_SUCCESS) {
            /* Wire: peakNode output → engine endpoint */
            ma_node_attach_output_bus(&g_bgmPeak.base, 0,
                ma_engine_get_endpoint(&g_engine), 0);
            /* Wire: bgmGroup output → peakNode input (replaces default → endpoint) */
            ma_node_attach_output_bus((ma_node*)&g_bgmGroup, 0,
                &g_bgmPeak.base, 0);
        }
        /* If peak node init fails, bgmGroup remains wired to endpoint (graceful degradation) */
    }

    memset(g_sfx, 0, sizeof(g_sfx));
    g_sfxCount = 0;
    g_bgmLoaded[0] = g_bgmLoaded[1] = 0;
    g_bgmActive = 0;
    g_initialized = 1;

    return 0;
}

MA_EXPORT void ma_bridge_shutdown(void) {
    int i, v;
    if (!g_initialized) return;

    bgm_uninit_slot(0);
    bgm_uninit_slot(1);

    for (i = 0; i < g_sfxCount; i++) {
        if (!g_sfx[i].loaded) continue;
        for (v = 0; v < SFX_VOICES; v++) {
            if (g_sfx[i].voiceInited[v]) {
                ma_sound_uninit(&g_sfx[i].voices[v]);
            }
        }
        g_sfx[i].loaded = 0;
    }
    g_sfxCount = 0;

    ma_node_uninit(&g_bgmPeak.base, NULL);
    ma_sound_group_uninit(&g_sfxGroup);
    ma_sound_group_uninit(&g_bgmGroup);
    ma_engine_uninit(&g_engine);
    g_initialized = 0;
}

/* ========== BGM ========== */

MA_EXPORT int ma_bridge_bgm_play(const wchar_t* wpath, int loop, float volume, float fadeSec) {
    wchar_t fullPath[MAX_WPATH_LEN];
    ma_result result;
    ma_uint64 now;
    ma_uint64 fadeMs;
    int oldSlot, newSlot;

    if (!g_initialized || wpath == NULL) return -1;

    resolve_wpath(wpath, fullPath, MAX_WPATH_LEN);

    fadeMs = (ma_uint64)(fadeSec * 1000.0f);
    now = ma_engine_get_time_in_milliseconds(&g_engine);

    oldSlot = g_bgmActive;
    newSlot = 1 - oldSlot;

    bgm_uninit_slot(newSlot);

    /* Init new BGM attached to bgmGroup */
    result = ma_sound_init_from_file_w(&g_engine, fullPath,
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION,
        &g_bgmGroup, NULL, &g_bgm[newSlot]);
    if (result != MA_SUCCESS) return -2;
    g_bgmLoaded[newSlot] = 1;

    ma_sound_set_looping(&g_bgm[newSlot], loop ? MA_TRUE : MA_FALSE);

    /*
     * Volume strategy: group volume = user-set loudness, individual sound
     * volume fades between 0 and 1. Final output = group_vol * sound_vol.
     * This keeps crossfade curves independent of the volume slider.
     */
    ma_sound_group_set_volume(&g_bgmGroup, volume);

    if (fadeMs >= MIN_FADE_MS && g_bgmLoaded[oldSlot]) {
        /*
         * Overlapping crossfade:
         * Old BGM fades out (current -> 0), new BGM fades in (0 -> 1).
         * Both run for fadeMs duration, no silence gap.
         *
         * NOTE: 不能用 ma_sound_set_volume(0) 初始化新音轨！
         * miniaudio 的 base volume 和 fader 是 *相乘* 关系：
         *   output = fader_processed_PCM × base_volume
         * base_volume=0 会导致永远静音，无论 fader 如何变化。
         * 正确做法：base_volume=1，让 fader 独立控制 0→1 淡入。
         */
        ma_sound_set_fade_in_milliseconds(&g_bgm[oldSlot], -1.0f, 0.0f, fadeMs);
        ma_sound_set_stop_time_in_milliseconds(&g_bgm[oldSlot], now + fadeMs);

        ma_sound_set_volume(&g_bgm[newSlot], 1.0f);
        ma_sound_set_fade_in_milliseconds(&g_bgm[newSlot], 0.0f, 1.0f, fadeMs);
        ma_sound_start(&g_bgm[newSlot]);

    } else if (fadeMs >= MIN_FADE_MS) {
        /* No old BGM playing, just fade in the new one */
        ma_sound_set_volume(&g_bgm[newSlot], 1.0f);
        ma_sound_set_fade_in_milliseconds(&g_bgm[newSlot], 0.0f, 1.0f, fadeMs);
        ma_sound_start(&g_bgm[newSlot]);

    } else {
        /* Short/zero fade: immediate playback */
        if (g_bgmLoaded[oldSlot]) {
            ma_sound_stop(&g_bgm[oldSlot]);
        }
        ma_sound_set_volume(&g_bgm[newSlot], 1.0f);
        ma_sound_start(&g_bgm[newSlot]);
    }

    g_bgmActive = newSlot;
    return 0;
}

MA_EXPORT int ma_bridge_bgm_stop(float fadeSec) {
    ma_uint64 fadeMs;
    int i;

    if (!g_initialized) return -1;

    fadeMs = (ma_uint64)(fadeSec * 1000.0f);

    /* Stop BOTH slots — catches the active one and any still-fading-out old one */
    for (i = 0; i < 2; i++) {
        if (!g_bgmLoaded[i]) continue;
        if (fadeMs >= MIN_FADE_MS) {
            ma_sound_stop_with_fade_in_milliseconds(&g_bgm[i], fadeMs);
        } else {
            ma_sound_stop(&g_bgm[i]);
        }
    }

    return 0;
}

/*
 * Set BGM bus volume. Uses group-level control so it never overwrites
 * the per-sound fade curves that crossfade relies on.
 */
MA_EXPORT void ma_bridge_bgm_set_volume(float volume) {
    if (!g_initialized) return;
    ma_sound_group_set_volume(&g_bgmGroup, volume);
}

/* ========== SFX (handle-based, voice pool) ========== */

/*
 * Load a sound effect. Returns handle (>= 0) on success, < 0 on error.
 * Each sound gets SFX_VOICES instances for overlapping playback.
 * miniaudio's resource manager shares decoded data across instances.
 */
MA_EXPORT int ma_bridge_sfx_load(const wchar_t* wpath) {
    wchar_t fullPath[MAX_WPATH_LEN];
    SfxSlot* slot;
    int v;

    if (!g_initialized || wpath == NULL) return -1;
    if (g_sfxCount >= MAX_SFX_SLOTS) return -3;

    slot = &g_sfx[g_sfxCount];
    resolve_wpath(wpath, fullPath, MAX_WPATH_LEN);

    memset(slot, 0, sizeof(SfxSlot));

    for (v = 0; v < SFX_VOICES; v++) {
        ma_result result = ma_sound_init_from_file_w(&g_engine, fullPath,
            MA_SOUND_FLAG_DECODE | MA_SOUND_FLAG_NO_SPATIALIZATION,
            &g_sfxGroup, NULL, &slot->voices[v]);
        if (result == MA_SUCCESS) {
            slot->voiceInited[v] = 1;
            slot->voiceCount++;
        }
    }

    if (slot->voiceCount == 0) return -2;

    slot->loaded = 1;
    return g_sfxCount++;
}

/*
 * Play a sound effect by handle. Returns:
 *   0  = playing
 *   1  = throttled (same sound played too recently)
 *  <0  = error
 */
MA_EXPORT int ma_bridge_sfx_play(int handle, float volume) {
    SfxSlot* slot;
    ULONGLONG now;
    int attempts, idx;

    if (!g_initialized) return -1;
    if (handle < 0 || handle >= g_sfxCount) return -1;

    slot = &g_sfx[handle];
    if (!slot->loaded) return -2;

    now = GetTickCount64();
    if ((now - slot->lastPlayTime) < (ULONGLONG)g_throttleMs) return 1;
    slot->lastPlayTime = now;

    /* Round-robin: pick next initialized voice */
    for (attempts = 0; attempts < SFX_VOICES; attempts++) {
        idx = slot->nextVoice;
        slot->nextVoice = (slot->nextVoice + 1) % SFX_VOICES;
        if (slot->voiceInited[idx]) {
            ma_sound_seek_to_pcm_frame(&slot->voices[idx], 0);
            ma_sound_set_volume(&slot->voices[idx], volume);
            ma_sound_start(&slot->voices[idx]);
            return 0;
        }
    }

    return -2;
}

/* Unload a sound effect by handle, freeing all voice instances. */
MA_EXPORT void ma_bridge_sfx_unload(int handle) {
    SfxSlot* slot;
    int v;
    if (!g_initialized) return;
    if (handle < 0 || handle >= g_sfxCount) return;

    slot = &g_sfx[handle];
    if (!slot->loaded) return;

    for (v = 0; v < SFX_VOICES; v++) {
        if (slot->voiceInited[v]) {
            ma_sound_stop(&slot->voices[v]);
            ma_sound_uninit(&slot->voices[v]);
            slot->voiceInited[v] = 0;
        }
    }
    slot->voiceCount = 0;
    slot->loaded = 0;
}

/* Set SFX bus volume (group-level). */
MA_EXPORT void ma_bridge_sfx_set_volume(float volume) {
    if (!g_initialized) return;
    ma_sound_group_set_volume(&g_sfxGroup, volume);
}

/* ========== BGM info (peak / cursor / length / isPlaying) ========== */

MA_EXPORT void ma_bridge_bgm_get_peak(float* outL, float* outR) {
    if (!g_initialized || outL == NULL || outR == NULL) {
        if (outL) *outL = 0.0f;
        if (outR) *outR = 0.0f;
        return;
    }
    *outL = g_bgmPeak.peakL;
    *outR = g_bgmPeak.peakR;
}

MA_EXPORT float ma_bridge_bgm_get_cursor(void) {
    float cursor = 0.0f;
    if (g_initialized && g_bgmLoaded[g_bgmActive])
        ma_sound_get_cursor_in_seconds(&g_bgm[g_bgmActive], &cursor);
    return cursor;
}

MA_EXPORT float ma_bridge_bgm_get_length(void) {
    float length = 0.0f;
    if (g_initialized && g_bgmLoaded[g_bgmActive])
        ma_sound_get_length_in_seconds(&g_bgm[g_bgmActive], &length);
    return length;
}

MA_EXPORT int ma_bridge_bgm_is_playing(void) {
    if (g_initialized && g_bgmLoaded[g_bgmActive])
        return ma_sound_is_playing(&g_bgm[g_bgmActive]) ? 1 : 0;
    return 0;
}

/* ========== Global ========== */

MA_EXPORT void ma_bridge_set_master_volume(float volume) {
    if (!g_initialized) return;
    ma_engine_set_volume(&g_engine, volume);
}
