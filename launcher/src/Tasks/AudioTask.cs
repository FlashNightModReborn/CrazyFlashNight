// CF7:ME Audio Task — JSON handler for BGM + volume commands
// C# 5 syntax

using System;
using System.Globalization;
using Newtonsoft.Json.Linq;
using CF7Launcher.Audio;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Handles audio JSON messages routed via MessageRouter.
    /// Commands: bgm_play, bgm_stop, bgm_vol, master_vol
    ///
    /// SFX uses fast-lane prefix 'S' in XmlSocketServer, not this handler.
    /// </summary>
    public class AudioTask
    {
        /// <summary>
        /// Flash 侧发起 bgm_play/bgm_stop 时置 true,
        /// WebOverlayForm.OnAudioTick 读取并转为 _manualStop, 防止误触 jukeboxTrackEnd。
        /// volatile 保证跨线程可见性。
        /// </summary>
        public static volatile bool FlashBgmChange;

        private sealed class DeferredBgmPlay
        {
            public string Path;
            public int Loop;
            public float Vol;
            public float Fade;
            public float? Seek;
            public int? LoopOverride;
            public float? VolumeOverride;
        }

        private static readonly object _bootstrapGateLock = new object();
        private static bool _bootstrapBgmGateActive;
        private static DeferredBgmPlay _deferredBgmPlay;

        /// <summary>
        /// 片头视频播放期间挂起 Flash 发来的 BGM 启动请求。
        /// 这样游戏可以继续后台加载, 但不会在视频尚未播完时抢先出声。
        /// </summary>
        public static void ArmBootstrapBgmGate()
        {
            lock (_bootstrapGateLock)
            {
                _bootstrapBgmGateActive = true;
                _deferredBgmPlay = null;
            }
            LogManager.Log("[Audio] bootstrap BGM gate armed");
        }

        public static void CancelBootstrapBgmGate()
        {
            bool hadState;
            lock (_bootstrapGateLock)
            {
                hadState = _bootstrapBgmGateActive || _deferredBgmPlay != null;
                _bootstrapBgmGateActive = false;
                _deferredBgmPlay = null;
            }
            if (hadState)
                LogManager.Log("[Audio] bootstrap BGM gate cancelled");
        }

        public static void ReleaseBootstrapBgmGate()
        {
            DeferredBgmPlay pending;
            lock (_bootstrapGateLock)
            {
                if (!_bootstrapBgmGateActive && _deferredBgmPlay == null)
                    return;
                _bootstrapBgmGateActive = false;
                pending = _deferredBgmPlay;
                _deferredBgmPlay = null;
            }

            if (pending == null || string.IsNullOrEmpty(pending.Path))
            {
                LogManager.Log("[Audio] bootstrap BGM gate released (no deferred track)");
                return;
            }

            LogManager.Log("[Audio] bootstrap BGM gate released -> play deferred path=" + pending.Path
                + " loop=" + pending.Loop
                + " vol=" + pending.Vol.ToString("F3")
                + " fade=" + pending.Fade.ToString("F2"));

            FlashBgmChange = true;
            int rc = AudioEngine.ma_bridge_bgm_play(pending.Path, pending.Loop, pending.Vol, pending.Fade);
            if (rc != 0)
            {
                LogManager.Log("[Audio] deferred bgm_play FAILED: rc=" + rc + " path=" + pending.Path);
                return;
            }

            if (pending.LoopOverride.HasValue)
                AudioEngine.ma_bridge_bgm_set_looping(pending.LoopOverride.Value);
            if (pending.VolumeOverride.HasValue)
                AudioEngine.ma_bridge_bgm_set_volume(pending.VolumeOverride.Value);
            if (pending.Seek.HasValue)
            {
                int seekRc = AudioEngine.ma_bridge_bgm_seek(pending.Seek.Value);
                if (seekRc != 0)
                    LogManager.Log("[Audio] deferred bgm_seek FAILED: rc=" + seekRc
                        + " sec=" + pending.Seek.Value.ToString("F2"));
            }
        }

        /// <summary>
        /// Sync handler registered with MessageRouter.
        /// All audio commands are fire-and-forget (returns null).
        /// </summary>
        public string Handle(JObject message)
        {
            string cmd = message.Value<string>("cmd");
            if (cmd == null)
            {
                LogManager.Log("[Audio] Missing 'cmd' field");
                return null;
            }

            switch (cmd)
            {
                case "bgm_play":
                    HandleBgmPlay(message);
                    break;
                case "bgm_stop":
                    HandleBgmStop(message);
                    break;
                case "bgm_vol":
                    HandleBgmVol(message);
                    break;
                case "sfx_vol":
                    HandleSfxVol(message);
                    break;
                case "master_vol":
                    HandleMasterVol(message);
                    break;
                case "bgm_seek":
                    HandleBgmSeek(message);
                    break;
                case "bgm_loop":
                    HandleBgmLoop(message);
                    break;
                default:
                    LogManager.Log("[Audio] Unknown cmd: " + cmd);
                    break;
            }

            return null; // fire-and-forget
        }

        private void HandleBgmPlay(JObject msg)
        {
            string path = msg.Value<string>("path");
            if (path == null) { LogManager.Log("[Audio] bgm_play: missing path"); return; }

            int loop = msg.Value<int?>("loop") ?? 0;
            float vol = msg.Value<float?>("vol") ?? 1.0f;
            float fade = msg.Value<float?>("fade") ?? 0.0f;

            lock (_bootstrapGateLock)
            {
                if (_bootstrapBgmGateActive)
                {
                    if (_deferredBgmPlay == null) _deferredBgmPlay = new DeferredBgmPlay();
                    _deferredBgmPlay.Path = path;
                    _deferredBgmPlay.Loop = loop;
                    _deferredBgmPlay.Vol = vol;
                    _deferredBgmPlay.Fade = fade;
                    LogManager.Log("[Audio] bgm_play deferred by bootstrap gate: path=" + path
                        + " loop=" + loop
                        + " vol=" + vol.ToString("F3")
                        + " fade=" + fade.ToString("F2"));
                    return;
                }
            }

            LogManager.Log("[Audio] bgm_play: path=" + path + " loop=" + loop
                + " vol=" + vol.ToString("F3") + " fade=" + fade.ToString("F2"));

            FlashBgmChange = true;
            int rc = AudioEngine.ma_bridge_bgm_play(path, loop, vol, fade);
            if (rc != 0)
                LogManager.Log("[Audio] bgm_play FAILED: rc=" + rc + " path=" + path);
        }

        private void HandleBgmStop(JObject msg)
        {
            float fade = msg.Value<float?>("fade") ?? 0.0f;
            lock (_bootstrapGateLock)
            {
                if (_bootstrapBgmGateActive)
                {
                    _deferredBgmPlay = null;
                    LogManager.Log("[Audio] bgm_stop during bootstrap gate: clear deferred track, fade="
                        + fade.ToString("F2"));
                }
            }
            LogManager.Log("[Audio] bgm_stop: fade=" + fade.ToString("F2"));
            FlashBgmChange = true;
            int rc = AudioEngine.ma_bridge_bgm_stop(fade);
            if (rc != 0)
                LogManager.Log("[Audio] bgm_stop FAILED: rc=" + rc);
        }

        private void HandleBgmVol(JObject msg)
        {
            float vol = msg.Value<float?>("vol") ?? 1.0f;
            lock (_bootstrapGateLock)
            {
                if (_bootstrapBgmGateActive)
                {
                    if (_deferredBgmPlay == null) _deferredBgmPlay = new DeferredBgmPlay();
                    _deferredBgmPlay.VolumeOverride = vol;
                    LogManager.Log("[Audio] bgm_vol deferred by bootstrap gate: vol=" + vol.ToString("F3"));
                    return;
                }
            }
            AudioEngine.ma_bridge_bgm_set_volume(vol);
        }

        private void HandleSfxVol(JObject msg)
        {
            float vol = msg.Value<float?>("vol") ?? 1.0f;
            AudioEngine.ma_bridge_sfx_set_volume(vol);
        }

        private void HandleMasterVol(JObject msg)
        {
            float vol = msg.Value<float?>("vol") ?? 1.0f;
            AudioEngine.ma_bridge_set_master_volume(vol);
        }

        private void HandleBgmLoop(JObject msg)
        {
            int loop = msg.Value<int?>("loop") ?? 1;
            lock (_bootstrapGateLock)
            {
                if (_bootstrapBgmGateActive)
                {
                    if (_deferredBgmPlay == null) _deferredBgmPlay = new DeferredBgmPlay();
                    _deferredBgmPlay.LoopOverride = loop;
                    LogManager.Log("[Audio] bgm_loop deferred by bootstrap gate: loop=" + loop);
                    return;
                }
            }
            AudioEngine.ma_bridge_bgm_set_looping(loop);
        }

        private void HandleBgmSeek(JObject msg)
        {
            float sec = msg.Value<float?>("sec") ?? 0.0f;
            lock (_bootstrapGateLock)
            {
                if (_bootstrapBgmGateActive)
                {
                    if (_deferredBgmPlay == null) _deferredBgmPlay = new DeferredBgmPlay();
                    _deferredBgmPlay.Seek = sec;
                    LogManager.Log("[Audio] bgm_seek deferred by bootstrap gate: sec=" + sec.ToString("F2"));
                    return;
                }
            }
            int rc = AudioEngine.ma_bridge_bgm_seek(sec);
            if (rc != 0)
                LogManager.Log("[Audio] bgm_seek FAILED: rc=" + rc + " sec=" + sec.ToString("F2"));
        }

        /// <summary>
        /// SFX fast-lane handler. Called directly from XmlSocketServer
        /// when message prefix is 'S'.
        /// Batch format: S{id1}|{id2}|{id3} (pipe-delimited, all at vol=1.0)
        /// Resolves string ids to native handles via AudioEngine cache (O(1) Dictionary lookup).
        /// </summary>
        public static void HandleSfxFastLane(string message)
        {
            // Strip 'S' prefix
            string payload = message.Substring(1);
            if (payload.Length == 0) return;

            // Split by pipe for batch playback
            string[] ids = payload.Split('|');
            for (int i = 0; i < ids.Length; i++)
            {
                string id = ids[i];
                if (id.Length == 0) continue;
                int handle = AudioEngine.ResolveSfxHandle(id);
                if (handle >= 0)
                {
                    AudioEngine.ma_bridge_sfx_play(handle, 1.0f);
                }
            }
        }
    }
}
