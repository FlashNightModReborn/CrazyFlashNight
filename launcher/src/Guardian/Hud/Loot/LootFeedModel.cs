using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.Hud.Loot
{
    /// <summary>
    /// Loot feed 纯逻辑模型：合并、限流、容量折叠、生命周期。
    /// 不依赖任何绘图/UI 类型，时钟只经 Tick 推进，便于 Launcher.Tests 单测。
    ///
    /// 设计要点（P1 决策）：
    /// - 同 (kind,name,icon) 在 MergeWindowMs 内合并为单卡，计数累加并移到最新位
    /// - 金钱/K点与物品同规则（同 key 天然单卡滚动累加）
    /// - 新卡创建受令牌窗口限流（RateMaxNewCards/RateWindowMs）；合并事件不受限
    ///   —— 洪水保护依赖"同 key 合并免费"，无需按优先级丢弃的复杂状态机
    /// - 超限被丢事件计入 DroppedCount，与超容量卡一起折叠为"还有 n 条"
    /// - kind 为不透明字符串（协议白名单在 LootTask 校验），P2 击杀播报只加渲染分支
    /// </summary>
    internal sealed class LootFeedModel
    {
        internal const int MergeWindowMs = 2500;
        internal const int HoldMs = 4000;
        internal const int FadeMs = 1200;
        internal const int MaxVisibleCards = 5;
        internal const int RateWindowMs = 1000;
        internal const int RateMaxNewCards = 10;

        internal sealed class LootCard
        {
            internal string Kind;
            internal string Name;
            internal string Icon;
            internal string Source;
            internal long Count;
            internal int BornMs;
            internal int LastEventMs;
        }

        private readonly List<LootCard> _cards = new List<LootCard>(); // 旧 → 新
        private int _nowMs;
        private int _rateWindowStartMs;
        private int _newCardsInWindow;

        internal int NowMs { get { return _nowMs; } }
        internal int ActiveCount { get { return _cards.Count; } }
        internal int DroppedCount { get; private set; }
        internal IReadOnlyList<LootCard> Cards { get { return _cards; } }

        /// <summary>折叠计数：超容量卡数 + 被限流丢弃的事件数。</summary>
        internal int OverflowCount
        {
            get { return Math.Max(0, _cards.Count - MaxVisibleCards) + DroppedCount; }
        }

        internal void Add(string kind, string name, string icon, long count, string source)
        {
            if (string.IsNullOrEmpty(kind) || string.IsNullOrEmpty(name) || count <= 0) return;

            // 合并窗口内同 key → 累加并挪到最新位（合并免费，不占限流额度）
            for (int i = _cards.Count - 1; i >= 0; i--)
            {
                LootCard c = _cards[i];
                if (c.Kind == kind && c.Name == name && c.Icon == icon
                        && _nowMs - c.LastEventMs <= MergeWindowMs)
                {
                    c.Count += count;
                    c.LastEventMs = _nowMs;
                    if (i != _cards.Count - 1)
                    {
                        _cards.RemoveAt(i);
                        _cards.Add(c);
                    }
                    return;
                }
            }

            // 新卡限流：窗口内最多 RateMaxNewCards 张，超出丢弃并计数
            if (_nowMs - _rateWindowStartMs >= RateWindowMs)
            {
                _rateWindowStartMs = _nowMs;
                _newCardsInWindow = 0;
            }
            if (_newCardsInWindow >= RateMaxNewCards)
            {
                DroppedCount++;
                return;
            }
            _newCardsInWindow++;

            _cards.Add(new LootCard
            {
                Kind = kind,
                Name = name,
                Icon = icon,
                Source = source,
                Count = count,
                BornMs = _nowMs,
                LastEventMs = _nowMs
            });
        }

        /// <summary>推进时钟并清理寿命结束的卡。返回是否有卡被移除。</summary>
        internal bool Tick(int deltaMs)
        {
            _nowMs += Math.Max(0, deltaMs);
            int removed = _cards.RemoveAll(c => _nowMs - c.LastEventMs > HoldMs + FadeMs);
            if (_cards.Count == 0 && DroppedCount > 0) DroppedCount = 0;
            return removed > 0;
        }

        /// <summary>卡片当前透明度（淡入二次方缓出对齐 ToastWidget 的淡出曲线）。</summary>
        internal static float AlphaFor(LootCard card, int nowMs, int fadeInMs)
        {
            float a = 1f;
            int bornAge = nowMs - card.BornMs;
            if (bornAge < fadeInMs)
                a *= Math.Max(0f, (float)bornAge / fadeInMs);
            int age = nowMs - card.LastEventMs;
            if (age > HoldMs)
            {
                float t = Math.Max(0f, (float)(HoldMs + FadeMs - age) / FadeMs);
                a *= t * t;
            }
            return Math.Max(0f, Math.Min(1f, a));
        }
    }
}
