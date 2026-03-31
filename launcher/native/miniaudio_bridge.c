/*
 * miniaudio_bridge.c
 * CF7:ME audio bridge - exports C functions for C# P/Invoke
 *
 * All string parameters use wchar_t* (UTF-16 from C#).
 * File paths use miniaudio's _w() variants directly.
 * SFX IDs are converted to UTF-8 for internal hash lookup.
 *
 * BGM uses dual-instance crossfade: old BGM fades out while new BGM
 * fades in, scheduled on the engine's global clock for sample-accurate timing.
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
#define MAX_SFX_SLOTS   1024
#define MAX_ID_LEN      512
#define MAX_WPATH_LEN   1024
#define DEFAULT_THROTTLE_MS 90
#define MIN_FADE_MS     100

/* ========== SFX slot ========== */
typedef struct {
    char id[MAX_ID_LEN];
    ma_sound sound;
    int loaded;
    ULONGLONG lastPlayTime;
} SfxSlot;

/* ========== Global state ========== */
static ma_engine g_engine;
static int g_initialized = 0;
static wchar_t g_basePath[MAX_WPATH_LEN] = {0};

/* BGM dual-instance: ping-pong between slot 0 and 1 */
static ma_sound g_bgm[2];
static int g_bgmLoaded[2] = {0, 0};
static int g_bgmActive = 0;  /* index of currently active (or fading-in) BGM */

/* SFX */
static SfxSlot g_sfx[MAX_SFX_SLOTS];
static int g_sfxCount = 0;
static int g_throttleMs = DEFAULT_THROTTLE_MS;

/* ========== Helpers ========== */

static char* wchar_to_utf8(const wchar_t* wstr, char* out, int outSize) {
    int needed;
    if (wstr == NULL) return NULL;
    needed = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
    if (needed <= 0 || needed > outSize) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, out, outSize, NULL, NULL);
    return out;
}

static void resolve_wpath(const wchar_t* relPath, wchar_t* out, int outLen) {
    wchar_t* p;
    if (g_basePath[0] != L'\0') {
        _snwprintf(out, outLen, L"%s/%s", g_basePath, relPath);
    } else {
        _snwprintf(out, outLen, L"%s", relPath);
    }
    out[outLen - 1] = L'\0';
    for (p = out; *p; p++) {
        if (*p == L'\\') *p = L'/';
    }
}

static SfxSlot* find_sfx(const char* id) {
    int i;
    for (i = 0; i < g_sfxCount; i++) {
        if (strcmp(g_sfx[i].id, id) == 0)
            return &g_sfx[i];
    }
    return NULL;
}

/* Uninit a BGM slot if loaded */
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

    memset(g_sfx, 0, sizeof(g_sfx));
    g_sfxCount = 0;
    g_bgmLoaded[0] = g_bgmLoaded[1] = 0;
    g_bgmActive = 0;
    g_initialized = 1;

    return 0;
}

MA_EXPORT void ma_bridge_shutdown(void) {
    int i;
    if (!g_initialized) return;

    bgm_uninit_slot(0);
    bgm_uninit_slot(1);

    for (i = 0; i < g_sfxCount; i++) {
        if (g_sfx[i].loaded) {
            ma_sound_uninit(&g_sfx[i].sound);
            g_sfx[i].loaded = 0;
        }
    }
    g_sfxCount = 0;

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

    /* Determine slots: old = current active, new = the other one */
    oldSlot = g_bgmActive;
    newSlot = 1 - oldSlot;

    /* Clean up new slot if it has leftover data */
    bgm_uninit_slot(newSlot);

    /* Init new BGM (stream mode for large files) */
    result = ma_sound_init_from_file_w(&g_engine, fullPath,
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION,
        NULL, NULL, &g_bgm[newSlot]);
    if (result != MA_SUCCESS) return -2;
    g_bgmLoaded[newSlot] = 1;

    ma_sound_set_looping(&g_bgm[newSlot], loop ? MA_TRUE : MA_FALSE);

    if (fadeMs >= MIN_FADE_MS && g_bgmLoaded[oldSlot]) {
        /*
         * Overlapping crossfade:
         * Old BGM fades out while new BGM fades in simultaneously.
         * Both run for fadeMs duration, no silence gap.
         */

        /* Old: fade out from current volume to 0, then auto-stop */
        ma_sound_set_fade_in_milliseconds(&g_bgm[oldSlot], -1.0f, 0.0f, fadeMs);
        ma_sound_set_stop_time_in_milliseconds(&g_bgm[oldSlot], now + fadeMs);

        /* New: start immediately with fade-in */
        ma_sound_set_volume(&g_bgm[newSlot], volume);
        ma_sound_set_fade_in_milliseconds(&g_bgm[newSlot], 0.0f, 1.0f, fadeMs);
        ma_sound_start(&g_bgm[newSlot]);

    } else if (fadeMs >= MIN_FADE_MS) {
        /* No old BGM playing, just fade in the new one */
        ma_sound_set_volume(&g_bgm[newSlot], volume);
        ma_sound_set_fade_in_milliseconds(&g_bgm[newSlot], 0.0f, 1.0f, fadeMs);
        ma_sound_start(&g_bgm[newSlot]);

    } else {
        /* Short/zero fade: immediate playback */
        if (g_bgmLoaded[oldSlot]) {
            ma_sound_stop(&g_bgm[oldSlot]);
        }
        ma_sound_set_volume(&g_bgm[newSlot], volume);
        ma_sound_start(&g_bgm[newSlot]);
    }

    /* Flip active slot */
    g_bgmActive = newSlot;

    /* Clean up old slot after transition (deferred: it may still be fading) */
    /* Old slot will be cleaned up on next bgm_play or shutdown */

    return 0;
}

MA_EXPORT int ma_bridge_bgm_stop(float fadeSec) {
    ma_uint64 fadeMs;
    int slot;

    if (!g_initialized) return -1;

    slot = g_bgmActive;
    if (!g_bgmLoaded[slot]) return -1;

    fadeMs = (ma_uint64)(fadeSec * 1000.0f);
    if (fadeMs >= MIN_FADE_MS) {
        ma_sound_stop_with_fade_in_milliseconds(&g_bgm[slot], fadeMs);
    } else {
        ma_sound_stop(&g_bgm[slot]);
    }

    return 0;
}

MA_EXPORT void ma_bridge_bgm_set_volume(float volume) {
    int slot;
    if (!g_initialized) return;
    slot = g_bgmActive;
    if (g_bgmLoaded[slot]) {
        ma_sound_set_volume(&g_bgm[slot], volume);
    }
}

/* ========== SFX ========== */

MA_EXPORT int ma_bridge_sfx_load(const wchar_t* wid, const wchar_t* wpath) {
    char idUtf8[MAX_ID_LEN];
    wchar_t fullPath[MAX_WPATH_LEN];
    ma_result result;
    SfxSlot* slot;

    if (!g_initialized || wid == NULL || wpath == NULL) return -1;
    if (g_sfxCount >= MAX_SFX_SLOTS) return -3;
    if (wchar_to_utf8(wid, idUtf8, sizeof(idUtf8)) == NULL) return -4;

    slot = find_sfx(idUtf8);
    if (slot != NULL) {
        if (slot->loaded) {
            ma_sound_uninit(&slot->sound);
            slot->loaded = 0;
        }
    } else {
        slot = &g_sfx[g_sfxCount++];
        strncpy(slot->id, idUtf8, MAX_ID_LEN - 1);
        slot->id[MAX_ID_LEN - 1] = '\0';
    }

    resolve_wpath(wpath, fullPath, MAX_WPATH_LEN);

    result = ma_sound_init_from_file_w(&g_engine, fullPath,
        MA_SOUND_FLAG_DECODE | MA_SOUND_FLAG_NO_SPATIALIZATION,
        NULL, NULL, &slot->sound);
    if (result != MA_SUCCESS) {
        slot->loaded = 0;
        return -2;
    }

    slot->loaded = 1;
    slot->lastPlayTime = 0;
    return 0;
}

MA_EXPORT int ma_bridge_sfx_play(const wchar_t* wid, float volume) {
    char idUtf8[MAX_ID_LEN];
    SfxSlot* slot;
    ULONGLONG now;

    if (!g_initialized || wid == NULL) return -1;
    if (wchar_to_utf8(wid, idUtf8, sizeof(idUtf8)) == NULL) return -4;

    slot = find_sfx(idUtf8);
    if (slot == NULL || !slot->loaded) return -2;

    now = GetTickCount64();
    if ((now - slot->lastPlayTime) < (ULONGLONG)g_throttleMs) return 1;
    slot->lastPlayTime = now;

    ma_sound_seek_to_pcm_frame(&slot->sound, 0);
    ma_sound_set_volume(&slot->sound, volume);
    ma_sound_start(&slot->sound);

    return 0;
}

MA_EXPORT void ma_bridge_sfx_unload(const wchar_t* wid) {
    char idUtf8[MAX_ID_LEN];
    SfxSlot* slot;
    if (!g_initialized || wid == NULL) return;
    if (wchar_to_utf8(wid, idUtf8, sizeof(idUtf8)) == NULL) return;

    slot = find_sfx(idUtf8);
    if (slot != NULL && slot->loaded) {
        ma_sound_stop(&slot->sound);
        ma_sound_uninit(&slot->sound);
        slot->loaded = 0;
    }
}

/* ========== Global ========== */

MA_EXPORT void ma_bridge_set_master_volume(float volume) {
    if (!g_initialized) return;
    ma_engine_set_volume(&g_engine, volume);
}
