using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 统一滚轮探针入口：WebOverlayForm 全局鼠标钩子在 WM_MOUSEWHEEL 时调用
    /// NativeInteractionWheelRoute.Dispatch(nativeTooltipWidget, x, y, delta)，
    /// 返回 true = 事件被消费（不转发给 Flash），false = CallNextHookEx 放行。
    /// 真实实例导航 / 使用计数 → coverage.incoming.usage 自动注册。
    /// </summary>
    internal static class NativeInteractionWheelRoute
    {
        private static volatile TooltipInspectionController _inspection;
        private static volatile NativeTooltipWidget _inspectionWidget;

        /// <summary>
        /// task 创建检视控制器后挂接：滚轮仲裁只对同一 widget 实例生效
        /// （测试里不同 widget 的 Dispatch 不会误用旧控制器）。
        /// </summary>
        internal static void AttachInspection(TooltipInspectionController controller, NativeTooltipWidget widget)
        {
            DetachInspection();
            _inspection = controller;
            _inspectionWidget = widget;
            if (controller != null && widget != null) widget.PointerMoved += controller.Tick;
        }

        internal static void DetachInspection()
        {
            TooltipInspectionController controller = _inspection;
            NativeTooltipWidget widget = _inspectionWidget;
            if (controller != null && widget != null) widget.PointerMoved -= controller.Tick;
            _inspection = null;
            _inspectionWidget = null;
        }

        internal static bool Dispatch(NativeTooltipWidget tooltip, int screenX, int screenY, int wheelDelta)
        {
            if (tooltip == null) return false;
            Point pt = new Point(screenX, screenY);
            NativeTooltipDocument doc = null;
            try { doc = tooltip.ActiveDocument; } catch { }
            if (doc != null && doc.Profile == NativeTooltipProfile.Pinned)
            {
                // pinned 独立契约：浮层 rect 内恒消费（含滚动边界，不穿透宿主）
                INativeHudWheelConsumer pinned = tooltip as INativeHudWheelConsumer;
                if (pinned != null) return pinned.OnMouseWheel(pt, wheelDelta);
                return false;
            }
            // simple/dense → 检视控制器仲裁（dense 仅 inspect 态 owner 区内消费，
            // 纠正旧版「visible+scrollable 任意位置即滚」的越权消费）。
            TooltipInspectionController c = _inspection;
            if (c != null && ReferenceEquals(_inspectionWidget, tooltip))
            {
                try { return c.TryConsumeWheel(screenX, screenY, wheelDelta); }
                catch { return false; }
            }
            return false;
        }
    }

    /// <summary>
    /// task 侧对原生 tooltip 的最小依赖面（便于单测桩 + 后续换装）。
    /// 只读几何/滚动面为检视控制器提供 owner 命中与状态机输入：
    /// OwnerScreenBounds = owner 命中区（native 以 ownerRect 或 Flash 客户区兜底；
    /// 缺失时 dense 滚轮不拦截，见 TooltipInspectionController 头注）。
    /// </summary>
    internal interface INativeInteractionTooltipSurface
    {
        bool Show(JObject payload);
        bool Hide(string requestId);
        void Reset();
        void OnHostSuppressed(string reason);
        string CurrentSceneId { get; }
        string CurrentRequestId { get; }
        bool HasPinnedSession { get; }
        NativeTooltipDocument ActiveDocument { get; }
        bool Scrollable { get; }
        Rectangle ScreenBounds { get; }
        Rectangle? OwnerScreenBounds { get; }
        bool ScrollByLines(int delta);
        /// <summary>检视投影推送："idle"/"scan"/"pending"/"inspect"；无投影实现时为空操作。</summary>
        void SetInspectionState(string state, int remainingMs);
        event Action<string> DismissRequested;
    }

    /// <summary>把 NativeTooltipWidget 投影成 task 依赖面。</summary>
    internal sealed class NativeTooltipSurfaceAdapter : INativeInteractionTooltipSurface
    {
        private readonly NativeTooltipWidget _widget;

        public NativeTooltipSurfaceAdapter(NativeTooltipWidget widget)
        {
            if (widget == null) throw new ArgumentNullException("widget");
            _widget = widget;
        }

        internal NativeTooltipWidget Widget { get { return _widget; } }

        public bool Show(JObject payload) { return _widget.Show(payload); }
        public bool Hide(string requestId) { return _widget.Hide(requestId); }
        public void Reset() { _widget.Reset(); }
        public void OnHostSuppressed(string reason) { _widget.OnHostSuppressed(reason); }
        public string CurrentSceneId { get { return _widget.CurrentSceneId; } }
        public string CurrentRequestId { get { return _widget.CurrentRequestId; } }
        public bool HasPinnedSession
        {
            get
            {
                NativeTooltipDocument doc = _widget.ActiveDocument;
                return doc != null && doc.Profile == NativeTooltipProfile.Pinned;
            }
        }
        public NativeTooltipDocument ActiveDocument { get { return _widget.ActiveDocument; } }
        public bool Scrollable { get { return _widget.Scrollable; } }
        public Rectangle ScreenBounds { get { return _widget.ScreenBounds; } }
        public Rectangle? OwnerScreenBounds { get { return _widget.OwnerScreenBounds; } }
        public bool ScrollByLines(int delta) { return _widget.ScrollByLines(delta); }
        public void SetInspectionState(string state, int remainingMs)
        {
            // widget 是 sealed：经 object 探测投影接口，native 实现后自动接通，未实现则空操作。
            ITooltipInspectionProjection sink = ((object)_widget) as ITooltipInspectionProjection;
            if (sink != null) sink.SetInspectionState(state, remainingMs);
        }
        public event Action<string> DismissRequested
        {
            add { _widget.DismissRequested += value; }
            remove { _widget.DismissRequested -= value; }
        }
    }

    /// <summary>
    /// WebOverlayForm 全局鼠标钩子的外部点压探针（NativeInteractionTask.NotifyPhysicalButtonDown）。
    /// 菜单自身命中由 widget HitTest 负责；这里只处理「可见但点在框外」→ dismiss。
    /// </summary>
    internal static class NativeInteractionHitTest
    {
        internal static bool IsExternalPress(bool visible, Rectangle bounds, int x, int y)
        {
            return visible && !bounds.Contains(new Point(x, y));
        }
    }

    /// <summary>WebPanel 显示/隐藏时联动 native_interaction 会话（实现 Guardian.IPanelHudCompanion）。</summary>
    internal sealed class NativeInteractionPanelCompanion : IPanelHudCompanion
    {
        private readonly Tasks.NativeInteractionTask _task;

        internal NativeInteractionPanelCompanion(Tasks.NativeInteractionTask task)
        {
            _task = task;
        }

        public void Suspend()
        {
            try { _task.OnPanelSuspending(); }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] panel suspend hook throw: " + ex.Message); }
        }

        public void Resume() { }
    }
}
