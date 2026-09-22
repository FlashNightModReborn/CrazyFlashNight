using System;
using System.Threading;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Tasks
{
    public sealed class WorldLightingTask
    {
        private readonly Action<Action> _dispatch;
        private readonly Action<WorldLightingFrame> _adopt;
        private readonly Action _reset;
        private long _epoch;
        internal WorldLightingTask(Action<Action> dispatch, Action<WorldLightingFrame> adopt, Action reset)
        { _dispatch=dispatch; _adopt=adopt; _reset=reset; }
        internal string Handle(JObject message)
        {
            try {
                if (!WorldLightingFrame.TryParse(message?["payload"] as JObject, out var frame)) {
                    LogManager.Log("event=world_lighting_rejected reason=malformed"); return null;
                }
                long epoch=Interlocked.Read(ref _epoch);
                _dispatch(() => { if (epoch==Interlocked.Read(ref _epoch)) _adopt(frame); });
            } catch (Exception error) { LogManager.Log("[WorldLighting] "+error.Message); }
            return null;
        }
        internal void Disconnected()
        {
            Interlocked.Increment(ref _epoch);
            _dispatch(_reset);
        }
    }
}
