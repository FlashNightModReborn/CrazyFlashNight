// Deliberate platform fakes for the production NativeInteractionTask/message router.
// They model no equipment, content rules, Flash behavior or WinForms inspection/layout semantics.
using System;
using System.Drawing;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Bus
{
    public sealed class XmlSocketServer
    {
        public bool IsClientReady => true;
        public bool TrySend(string message) => true;
    }
}
namespace CF7Launcher.Guardian
{
    internal static class LogManager { internal static void Log(string message) { } }
}
namespace CF7Launcher.Guardian.Hud.Tooltip
{
    internal sealed class NativeTooltipDocument { internal int Revision; }
}
namespace CF7Launcher.Guardian.Hud
{
    internal interface INativeInteractionTooltipSurface
    {
        bool Show(JObject payload);
        bool Hide(string requestId);
        void Reset();
        void OnHostSuppressed(string reason);
        string CurrentSceneId { get; }
        string CurrentRequestId { get; }
        bool HasPinnedSession { get; }
        Tooltip.NativeTooltipDocument ActiveDocument { get; }
        event Action<string> DismissRequested;
    }
    internal class NativeTooltipSurfaceAdapter : INativeInteractionTooltipSurface
    {
        internal object Widget => null;
        internal JObject LastPayload;
        internal int Shows;
        public string CurrentSceneId => LastPayload?.Value<string>("sceneId");
        public string CurrentRequestId => LastPayload?.Value<string>("requestId");
        public bool HasPinnedSession => LastPayload?["document"]?.Value<string>("profile") == "pinned";
        public Tooltip.NativeTooltipDocument ActiveDocument => LastPayload == null ? null
            : new Tooltip.NativeTooltipDocument { Revision = LastPayload.Value<int?>("revision") ?? 0 };
        public event Action<string> DismissRequested;
        public bool Show(JObject payload) { LastPayload = (JObject)payload.DeepClone(); Shows++; return true; }
        public bool Hide(string requestId) { if (CurrentRequestId != requestId) return false; LastPayload = null; return true; }
        public void Reset() { LastPayload = null; }
        public void OnHostSuppressed(string reason) { string rid = CurrentRequestId; Reset(); if (rid != null) DismissRequested?.Invoke(rid); }
    }
    internal sealed class TooltipInspectionController
    {
        internal TooltipInspectionController(INativeInteractionTooltipSurface surface) { }
        internal bool EscConsumable => false;
        internal string TryDismissPinnedAt(int x, int y) => null;
        internal bool TryDeferHide(string requestId) => false;
        internal void ExitInspection() { }
        internal void Sync() { }
    }
    internal static class NativeInteractionWheelRoute
    {
        internal static void AttachInspection(TooltipInspectionController inspection, object widget) { }
    }
    public sealed class NpcMenuWidget
    {
        public sealed class MenuSession
        {
            public string RequestId, SceneId, TargetName, Title;
            public float AnchorFx, AnchorFy;
            public Entry[] Entries;
        }
        public sealed class Entry { public string Id, Label; public bool Enabled; }
        private MenuSession _session;
        public Action<string, string, string> ActionChosen;
        public Action<string, string, string> SessionDismissed;
        public bool Visible => _session != null;
        public Rectangle ScreenBounds => Rectangle.Empty;
        public string CurrentRequestId => _session?.RequestId;
        public string CurrentSceneId => _session?.SceneId;
        public void ShowSession(MenuSession session) { _session = session; }
        public void HideSession(string request, string scene)
        { if (CurrentRequestId == request && CurrentSceneId == scene) _session = null; }
        public void ForceClear() { _session = null; }
        public void DismissInteractive(string reason)
        {
            var session = _session; _session = null;
            if (session != null) SessionDismissed?.Invoke(session.RequestId, session.SceneId, reason);
        }
    }
}
