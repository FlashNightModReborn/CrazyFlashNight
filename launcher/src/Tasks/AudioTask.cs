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
                case "master_vol":
                    HandleMasterVol(message);
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

            AudioEngine.ma_bridge_bgm_play(path, loop, vol, fade);
        }

        private void HandleBgmStop(JObject msg)
        {
            float fade = msg.Value<float?>("fade") ?? 0.0f;
            AudioEngine.ma_bridge_bgm_stop(fade);
        }

        private void HandleBgmVol(JObject msg)
        {
            float vol = msg.Value<float?>("vol") ?? 1.0f;
            AudioEngine.ma_bridge_bgm_set_volume(vol);
        }

        private void HandleMasterVol(JObject msg)
        {
            float vol = msg.Value<float?>("vol") ?? 1.0f;
            AudioEngine.ma_bridge_set_master_volume(vol);
        }

        /// <summary>
        /// SFX fast-lane handler. Called directly from XmlSocketServer
        /// when message prefix is 'S'.
        /// Batch format: S{id1}|{id2}|{id3} (pipe-delimited, all at vol=1.0)
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
                AudioEngine.ma_bridge_sfx_play(id, 1.0f);
            }
        }
    }
}
