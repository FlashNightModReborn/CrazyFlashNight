// CF7:ME Audio Engine — miniaudio P/Invoke wrapper
// C# 5 syntax

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Thin P/Invoke wrapper for miniaudio_bridge.dll.
    /// SFX uses handle-based API: native load() returns int handle,
    /// C# caches filename->handle in a Dictionary for O(1) lookup.
    /// </summary>
    internal static class AudioEngine
    {
        private const string DLL = "miniaudio.dll";

        // === Lifecycle ===
        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        public static extern int ma_bridge_init(string basePath);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ma_bridge_shutdown();

        // === BGM ===
        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        public static extern int ma_bridge_bgm_play(string path, int loop, float volume, float fadeSec);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ma_bridge_bgm_stop(float fadeSec);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ma_bridge_bgm_set_volume(float volume);

        // === SFX (handle-based) ===
        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        public static extern int ma_bridge_sfx_load(string path);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ma_bridge_sfx_play(int handle, float volume);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ma_bridge_sfx_unload(int handle);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ma_bridge_sfx_set_volume(float volume);

        // === BGM info (peak / cursor / length / isPlaying) ===
        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ma_bridge_bgm_get_peak(out float peakL, out float peakR);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern float ma_bridge_bgm_get_cursor();

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern float ma_bridge_bgm_get_length();

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ma_bridge_bgm_is_playing();

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ma_bridge_bgm_seek(float seconds);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ma_bridge_bgm_set_looping(int looping);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ma_bridge_bgm_pause();

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern int ma_bridge_bgm_resume();

        // === Global ===
        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ma_bridge_set_master_volume(float volume);

        // === Shutdown 幂等保护 ===
        private static volatile bool _shutdown;

        // === SFX handle cache ===
        // 异步 preload 后 socket 线程会调 ResolveSfxHandle；preload 写、resolve 读，需要 lock
        // （Dictionary 写入期间 reader 触发 hash bucket rehash 会读到坏指针）。
        private static readonly Dictionary<string, int> _sfxHandles = new Dictionary<string, int>();
        private static readonly object _sfxHandlesLock = new object();
        // preload 完成信号：sfx_play 在 preload 未完成时 fallback 到 ResolveSfxHandle = -1（行为与"id 不存在"一致），
        // 玩家不会听到错位音效，preload 完成后自然恢复。
        private static volatile bool _sfxPreloadComplete;

        public static bool IsSfxPreloadComplete { get { return _sfxPreloadComplete; } }

        /// <summary>
        /// Resolve a SFX id (filename) to its native handle.
        /// Returns -1 if not found (含 preload 未完成期间).
        /// </summary>
        public static int ResolveSfxHandle(string id)
        {
            lock (_sfxHandlesLock)
            {
                int handle;
                return _sfxHandles.TryGetValue(id, out handle) ? handle : -1;
            }
        }

        /// <summary>
        /// Initialize the audio engine.
        /// Call before XmlSocketServer.Start().
        /// </summary>
        public static bool Init(string projectRoot)
        {
            int result = ma_bridge_init(projectRoot);
            if (result != 0)
            {
                LogManager.Log("[Audio] ma_bridge_init failed: " + result);
                PerfTrace.Mark("audio.init_failed", "rc=" + result);
                return false;
            }
            LogManager.Log("[Audio] Engine initialized (basePath: " + projectRoot + ")");
            PerfTrace.Mark("audio.init_done");
            return true;
        }

        // SFX pack scan order: later packs override earlier (same as original SoundPreprocessor)
        private static readonly string[] SFX_PACK_ORDER = { "武器", "特效", "人物" };

        /// <summary>
        /// Preload all SFX by scanning sounds/export/{武器,特效,人物}/ directories.
        /// Filename = linkageId, override order: 武器 -> 特效 -> 人物 (last wins).
        /// Returns number of successfully loaded sounds.
        /// </summary>
        public static int PreloadFromDirectories(string projectRoot)
        {
            int loaded = 0;
            int failed = 0;
            int overridden = 0;

            for (int p = 0; p < SFX_PACK_ORDER.Length; p++)
            {
                string packName = SFX_PACK_ORDER[p];
                string dir = Path.Combine(projectRoot, "sounds", "export", packName);
                if (!Directory.Exists(dir))
                {
                    LogManager.Log("[Audio] SFX dir not found: " + dir);
                    continue;
                }

                string[] files = Directory.GetFiles(dir);
                for (int i = 0; i < files.Length; i++)
                {
                    string filename = Path.GetFileName(files[i]);
                    string relPath = "sounds/export/" + packName + "/" + filename;

                    int handle = ma_bridge_sfx_load(relPath);
                    if (handle >= 0)
                    {
                        // If same id was already loaded from an earlier pack, unload it
                        int oldHandle;
                        bool wasOverride;
                        lock (_sfxHandlesLock)
                        {
                            wasOverride = _sfxHandles.TryGetValue(filename, out oldHandle);
                            _sfxHandles[filename] = handle;
                        }
                        if (wasOverride)
                        {
                            ma_bridge_sfx_unload(oldHandle);
                            overridden++;
                        }
                        loaded++;
                    }
                    else
                    {
                        if (failed < 3)
                        {
                            LogManager.Log("[Audio] SFX load FAIL: rc=" + handle + " path=" + relPath);
                        }
                        failed++;
                    }
                }
            }

            _sfxPreloadComplete = true;
            LogManager.Log("[Audio] SFX preload: " + loaded + " loaded, " + failed + " failed, "
                + overridden + " overridden (scanned " + SFX_PACK_ORDER.Length + " packs)");
            PerfTrace.Mark("audio.sfx_preload_done",
                "loaded=" + loaded + " failed=" + failed + " overridden=" + overridden);
            return loaded;
        }

        /// <summary>
        /// 异步 preload 入口：fire-and-forget 后台线程加载 SFX。
        /// 主线程不阻塞，UI 立即可见；preload 期间 sfx_play 走 ResolveSfxHandle = -1 fallback（与"id 不存在"等价，
        /// 不会播错音效）。preload 完成 ~1.2s 后自然就绪。
        /// </summary>
        public static void PreloadFromDirectoriesAsync(string projectRoot)
        {
            System.Threading.ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                try
                {
                    PreloadFromDirectories((string)state);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[Audio] async preload threw: " + ex.Message);
                    PerfTrace.Mark("audio.sfx_preload_failed", ex.Message);
                }
            }, projectRoot);
        }

        /// <summary>
        /// Shutdown and cleanup.
        /// </summary>
        public static void Shutdown()
        {
            if (_shutdown) return;
            _shutdown = true;
            lock (_sfxHandlesLock) { _sfxHandles.Clear(); }
            ma_bridge_shutdown();
            LogManager.Log("[Audio] Engine shutdown");
        }
    }
}
