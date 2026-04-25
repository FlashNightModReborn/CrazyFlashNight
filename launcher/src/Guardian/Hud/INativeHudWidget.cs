using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 鼠标事件类型。NativeHudOverlay 接收 WM_NCHITTEST 命中后通过 OnMouseEvent 派发给 widget。
    /// </summary>
    public enum MouseEventKind
    {
        Move,
        Down,
        Up,
        Click,
        Enter,
        Leave
    }

    /// <summary>
    /// NativeHudOverlay 内的渲染单元协议。
    ///
    /// 关键设计：
    /// - 动态 bounds：NativeHud 取所有 Visible widget 的 ScreenBounds union 作为窗口大小，无 widget 时 SW_HIDE
    /// - request-frame：widget 通过 WantsAnimationTick 声明是否需要 16ms tick；池为空时 NativeHud 停 timer
    /// - 单帧重绘：RepaintRequested 触发 NativeHud 单次 invalidate，不需启 tick
    /// </summary>
    public interface INativeHudWidget
    {
        /// <summary>Widget 在屏幕坐标系下的矩形（NativeHud 用其 union 算 hud bounds）。</summary>
        Rectangle ScreenBounds { get; }

        /// <summary>Widget 是否参与渲染与命中测试。</summary>
        bool Visible { get; }

        /// <summary>
        /// 渲染入口。被 NativeHudOverlay 在合成 bitmap 时调用。
        /// </summary>
        /// <param name="g">共享 Graphics（指向 NativeHud 的 _composedBitmap）</param>
        /// <param name="dpr">设备像素比</param>
        /// <param name="hudOrigin">hud 窗口在屏幕的左上原点；widget 自行做 ScreenBounds - hudOrigin 转为 bitmap 局部坐标</param>
        void Paint(Graphics g, float dpr, Point hudOrigin);

        /// <summary>命中测试。screenPt 是屏幕坐标。返回 true 表示该 widget 拥有该点的事件。</summary>
        bool TryHitTest(Point screenPt);

        /// <summary>NativeHud 收到鼠标消息后转发给命中的 widget。</summary>
        void OnMouseEvent(MouseEventArgs e, MouseEventKind kind);

        /// <summary>Bounds 或 Visible 变化时 fire；NativeHud 据此重算 union 与窗口大小。</summary>
        event EventHandler BoundsOrVisibilityChanged;

        /// <summary>仅需单帧重绘（无须启 tick）时 fire。</summary>
        event EventHandler RepaintRequested;

        /// <summary>是否需要 16ms 动画 tick。collapsed/static widget 应返回 false。</summary>
        bool WantsAnimationTick { get; }

        /// <summary>动画 tick 入口。仅 WantsAnimationTick==true 的 widget 会被调用。</summary>
        void Tick(int deltaMs);

        /// <summary>WantsAnimationTick 切换时 fire；NativeHud 据此 Start/Stop _animTick。</summary>
        event EventHandler AnimationStateChanged;
    }

    /// <summary>
    /// Widget 实现此接口表示需要从 UiData snapshot 接收推送。
    /// NativeHudOverlay 在 snapshot 变化时遍历 _widgets.OfType IUiDataConsumer 并调 OnUiDataChanged。
    ///
    /// snapshot 形态：Dictionary string,string（key → 完整 "key:val" 片段，与 WebOverlayForm._uiDataSnapshot 一致）。
    /// Widget 自行从 fullPiece 解码出业务数据（如 "g:1234" → 货币 1234），然后透传给 web 时直接发 fullPiece。
    /// </summary>
    public interface IUiDataConsumer
    {
        /// <param name="snapshot">完整 UiData 快照（非 delta）；调用时已是 NativeHud 拷贝的只读视图</param>
        /// <param name="changedKeys">本次变化的 key 集合（性能 hint，可忽略）</param>
        void OnUiDataChanged(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys);
    }
}
