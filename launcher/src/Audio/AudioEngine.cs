// CF7:ME Audio Engine — miniaudio P/Invoke wrapper
// C# 5 syntax

using System;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Thin P/Invoke wrapper for miniaudio_bridge.dll.
    /// All methods are static, matching the C export layer 1:1.
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

        // === SFX ===
        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        public static extern int ma_bridge_sfx_load(string id, string path);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        public static extern int ma_bridge_sfx_play(string id, float volume);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        public static extern void ma_bridge_sfx_unload(string id);

        // === Global ===
        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ma_bridge_set_master_volume(float volume);

        /// <summary>
        /// Initialize the audio engine and preload all SFX from manifest.
        /// Call before XmlSocketServer.Start().
        /// </summary>
        public static bool Init(string projectRoot)
        {
            int result = ma_bridge_init(projectRoot);
            if (result != 0)
            {
                LogManager.Log("[Audio] ma_bridge_init failed: " + result);
                return false;
            }
            LogManager.Log("[Audio] Engine initialized (basePath: " + projectRoot + ")");
            return true;
        }

        // SFX 包扫描顺序：后扫覆盖前（与原 SoundPreprocessor 加载顺序一致）
        private static readonly string[] SFX_PACK_ORDER = { "武器", "特效", "人物" };

        /// <summary>
        /// Preload all SFX by scanning sounds/export/{武器,特效,人物}/ directories.
        /// Filename = linkageId, override order: 武器 → 特效 → 人物 (last wins).
        /// No manifest file needed.
        /// </summary>
        public static int PreloadFromDirectories(string projectRoot)
        {
            int loaded = 0;
            int failed = 0;

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
                    // filename = linkageId (e.g. "awp1.wav", "gunpickup.mp3")
                    // relative path for native engine to resolve
                    string relPath = "sounds/export/" + packName + "/" + filename;

                    int r = ma_bridge_sfx_load(filename, relPath);
                    if (r == 0)
                        loaded++;
                    else
                        failed++;
                }
            }

            LogManager.Log("[Audio] SFX preload: " + loaded + " loaded, " + failed + " failed"
                + " (scanned " + SFX_PACK_ORDER.Length + " packs)");
            return loaded;
        }

        /// <summary>
        /// Shutdown and cleanup.
        /// </summary>
        public static void Shutdown()
        {
            ma_bridge_shutdown();
            LogManager.Log("[Audio] Engine shutdown");
        }
    }
}
