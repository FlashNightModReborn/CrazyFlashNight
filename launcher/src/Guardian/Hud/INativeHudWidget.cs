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

    /// <summary>
    /// Widget 实现此接口表示需要接收旧版（非 KV）UiData 推送。
    /// 旧格式：第一段无 ":" 时整包视为 "type|field1|field2|..." 一次性事件
    /// （如 "task|TaskName"、"announce|Text"），不写入 snapshot，只触发一次回调。
    ///
    /// 与 IUiDataConsumer 互补：snapshot KV 走 IUiDataConsumer，瞬时事件走本接口。
    /// QuestNoticeWidget 同时实现两者：td/tdh/tdn/mm 走 snapshot；task/announce 走 legacy 通知。
    ///
    /// **类型门控**：consumer 必须声明关心的 type 集合（LegacyTypes），NativeHudOverlay 据此
    /// 过滤掉无人订阅的 legacy 包（如 FrameTask 每帧推 combo|...，QuestNotice 不关心，整条 BeginInvoke
    /// 派发都跳过）。集合不可变；构造期固定下来。
    /// </summary>
    public interface IUiDataLegacyConsumer
    {
        /// <summary>本 consumer 关心的 legacy type 名集合（不可变）。NativeHud 用 union 决定整包是否派发。</summary>
        IEnumerable<string> LegacyTypes { get; }

        /// <param name="type">第一段 type 名（如 "task" / "announce"）；保证已在 LegacyTypes 内</param>
        /// <param name="fields">type 之后的 fields 数组（可能为空数组，但非 null）</param>
        void OnLegacyUiData(string type, string[] fields);
    }

    /// <summary>
    /// Widget 实现此接口表示需要接收 N 前缀 notch 通知（XmlSocketServer 解析后的 AddNotice）。
    ///
    /// 数据通路：socket "N{category}|{colorHex}|{text}" → INotchSink.AddNotice(category, text, color)
    /// → NativeHudOverlay 将其 fan-out 到所有 INotchNoticeConsumer widget。
    ///
    /// 与 IUiDataLegacyConsumer 区别：legacy UiData 是 FrameTask/socket 推的高频流（含 combo|...，每帧可能数十次），
    /// 而 N 前缀 notice 是 AS2 业务确认事件（如 N combo|ffd700|DFA 波动拳，命中招式时一次性触发）。
    /// ComboWidget 同时实现两者：每帧 combo|... 走 LegacyConsumer 更新 input/typed 缓存；N combo|... 走本接口触发 hit 动画。
    ///
    /// **类别门控**：consumer 必须声明 NoticeCategories 集合（不可变），NativeHud 据此过滤。
    /// </summary>
    public interface INotchNoticeConsumer
    {
        /// <summary>本 consumer 关心的 notice category 集合（不可变）。NativeHud 用 union 过滤无人订阅的 category。</summary>
        IEnumerable<string> NoticeCategories { get; }

        /// <summary>NativeHud 在 UI 线程派发的 notice。已通过 NoticeCategories 门控。</summary>
        void OnNotchNotice(string category, string text, System.Drawing.Color accentColor);
    }
}
