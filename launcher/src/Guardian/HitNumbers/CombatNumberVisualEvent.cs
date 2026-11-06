using System;

namespace CF7Launcher.Guardian.HitNumbers
{
    /// <summary>纯表现候选。生命周期键不进入伤害账本；聚合器不生成坐标或 PaintItem。</summary>
    internal sealed class CombatNumberVisualEvent
    {
        internal CombatNumberTargetAnchor Anchor;
        internal int Sequence, Value, TotalValue;
        internal double Born, Published, RecoveryStarted;
        internal float RecoveryFrom = 1f;
        internal float Alpha = 1f;
        internal string LifecycleKey => Anchor.LifecycleKey;
        internal string PresentationTargetKey => Anchor.PresentationTargetKey;
        internal float Opacity(double now)
        {
            float fade = (float)Math.Clamp((HealNumberAccumulator.LifetimeSeconds - (now - Published)) / 0.25, 0, 1);
            float progress = (float)Math.Clamp((now - RecoveryStarted) / 0.08, 0, 1);
            return fade * (RecoveryFrom + (1 - RecoveryFrom) * progress);
        }
    }

    internal sealed class CombatNumberTargetAnchor
    {
        internal CombatNumberTargetAnchor(string lifecycleKey)
        {
            LifecycleKey = lifecycleKey;
            // 原始实例/epoch 保持生命周期权威，不按坐标猜测伤害 MovieClip 名的别名。
            int epoch = lifecycleKey.LastIndexOf(".heal.", StringComparison.Ordinal);
            PresentationTargetKey = epoch > 0 && int.TryParse(lifecycleKey.AsSpan(epoch + 6), out int generation) && generation >= 0
                ? lifecycleKey.Substring(0, epoch) : lifecycleKey;
        }
        internal string LifecycleKey { get; }
        internal string PresentationTargetKey { get; }
        internal float WorldX, WorldY;
    }
}
