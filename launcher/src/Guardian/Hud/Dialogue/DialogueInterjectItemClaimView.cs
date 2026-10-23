using System;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>
    /// 输入条上的待处理索取视图：只在 pending claim + 实时持有查询完成后生成。
    /// 按钮可用性只由 claim 与真实持有决定，不跟随输入框 Enabled/StartRequired/ConfigRequired。
    /// </summary>
    internal sealed class DialogueInterjectItemClaimView
    {
        internal string ClaimId { get; set; }
        internal string Npc { get; set; }
        internal string ItemName { get; set; }
        /// <summary>后端要求数量；装备固定 1。</summary>
        internal int Quantity { get; set; }
        /// <summary>当前可交付持有数（普通物品为各容器合计，装备只算背包）。</summary>
        internal int Count { get; set; }
        /// <summary>装备背包内最低强化度；非装备为 0。</summary>
        internal int MinLevel { get; set; }
        internal bool Equipment { get; set; }
        internal bool Busy { get; set; }

        /// <summary>真实持有是否足够交付本次索取。</summary>
        internal bool Enough
        {
            get { return !Busy && Count >= Math.Max(1, Quantity); }
        }

        /// <summary>
        /// 主按钮文案（协议 7.5.6）：
        /// 普通物品「赠送X个XXX（当前持有Y）」；
        /// 装备强化度 Z&gt;1「赠送 1 个 XXX （当前持有Y个;强化度为Z）」。
        /// </summary>
        internal string AcceptText
        {
            get
            {
                string name = ItemName ?? "";
                if (Equipment)
                {
                    if (MinLevel > 1)
                        return "赠送 1 个 " + name + " （当前持有" + Count + "个;强化度为" + MinLevel + "）";
                    return "赠送1个" + name + "（当前持有" + Count + "）";
                }
                return "赠送" + Math.Max(1, Quantity) + "个" + name + "（当前持有" + Count + "）";
            }
        }

        internal string RejectText { get { return "不赠送"; } }
    }
}
