using System;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 上层 Native HUD 分区仲裁（docs/上层HUD风格锚定与分区仲裁-ADR-2026-11-05.md D4/D5）。
    ///
    /// 全部数值为 1024×576 设计坐标，UI 线程读写。分区：
    /// - TL 状态列：Buff 栏 → 聚焦目标；静态预算保证最坏情况不越过 BL 事件卡保留区。
    /// - BL 事件流：结构化事件卡（Loot，底边 460 向上）→ fallback 消息（其上方，动态让位）。
    /// - TC 刘海区：刘海及展开菜单/图表的稳定最大占位 → Combo（宽度受刘海安全宽度约束）。
    ///
    /// widget 只上报自身占用并订阅 <see cref="Changed"/>；位置由本类的纯函数给出。
    /// </summary>
    public static class HudZoneLayout
    {
        public const float LeftColumnX = 5f;
        /// <summary>左列右界 = 最宽刘海左侧安全线（与 PlayerHudBuffLayout.SafeRight 同源）。</summary>
        public const float LeftColumnRight = (1024 - RightHudLayout.PreferredNotchMaxWidthBase) / 2f
            - RightHudLayout.NotchRightGapBase;
        public const float ZoneGap = 6f;

        public const float EventBottomY = 460f;
        public const float EventCardHeight = 26f;
        public const float EventCardGap = 3f;
        public const float EventPendingRowHeight = 15f;
        public const int EventMaxCards = 5;
        /// <summary>BL 结构化事件卡最坏占用（5 卡 + 待显示行）。</summary>
        public const float EventCardsReserveHeight = EventMaxCards * (EventCardHeight + EventCardGap) + EventPendingRowHeight;
        /// <summary>TL 状态列最坏底边上限：不得进入 BL 事件卡保留区。</summary>
        public const float TopLeftMaxBottom = EventBottomY - EventCardsReserveHeight - ZoneGap;

        public const float ComboGap = 2f;
        /// <summary>Combo 最大宽度不超过刘海安全上限，避免侵入 TL 列与 TR 动作行。</summary>
        public const float ComboMaxWidth = RightHudLayout.PreferredNotchMaxWidthBase;

        private static float _topLeftBottom;
        private static float _eventCardsTop = EventBottomY;
        private static float _notchStableBottom = NativeHudTheme.TopBarHeightBase;

        /// <summary>任一分区上报值变化时触发（UI 线程）。</summary>
        public static event EventHandler Changed;

        public static float TopLeftBottom { get { return _topLeftBottom; } }
        public static float EventCardsTop { get { return _eventCardsTop; } }
        public static float NotchStableBottom { get { return _notchStableBottom; } }

        public static void ReportTopLeftBottom(float bottom)
        {
            Set(ref _topLeftBottom, Math.Max(0f, bottom));
        }

        public static void ReportEventCardsTop(float top)
        {
            Set(ref _eventCardsTop, Math.Max(0f, Math.Min(EventBottomY, top)));
        }

        public static void ReportNotchStableBottom(float bottom)
        {
            Set(ref _notchStableBottom, Math.Max(NativeHudTheme.TopBarHeightBase, bottom));
        }

        /// <summary>
        /// fallback 消息区域：下沿紧贴事件卡上方（无卡时贴 460），上沿让位 TL 状态列。
        /// 返回的 bottom 可能小于 top，表示当前没有可用空间（消息整体隐藏，不覆盖状态列）。
        /// </summary>
        public static void FallbackRegion(float topLeftBottom, float eventCardsTop, out float top, out float bottom)
        {
            bool hasCards = eventCardsTop < EventBottomY - 0.5f;
            bottom = hasCards ? eventCardsTop - ZoneGap : EventBottomY;
            top = topLeftBottom > 0.5f ? topLeftBottom + ZoneGap : ZoneGap;
        }

        public static void CurrentFallbackRegion(out float top, out float bottom)
        {
            FallbackRegion(_topLeftBottom, _eventCardsTop, out top, out bottom);
        }

        public static float ComboTop(float notchStableBottom)
        {
            return Math.Max(NativeHudTheme.TopBarHeightBase, notchStableBottom) + ComboGap;
        }

        public static float CurrentComboTop()
        {
            return ComboTop(_notchStableBottom);
        }

        /// <summary>BL 事件卡顶边（设计坐标）。</summary>
        public static float EventCardsTopFor(int activeCards, bool hasPendingRow)
        {
            if (activeCards <= 0) return EventBottomY;
            float h = activeCards * (EventCardHeight + EventCardGap) + (hasPendingRow ? EventPendingRowHeight : 0f);
            return EventBottomY - h;
        }

        internal static void ResetForTests()
        {
            _topLeftBottom = 0f;
            _eventCardsTop = EventBottomY;
            _notchStableBottom = NativeHudTheme.TopBarHeightBase;
            Changed = null;
        }

        private static void Set(ref float field, float value)
        {
            if (Math.Abs(field - value) < 0.25f) return;
            field = value;
            EventHandler h = Changed;
            if (h != null) h(null, EventArgs.Empty);
        }
    }
}
