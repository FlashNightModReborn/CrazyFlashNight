using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.Hud.Loot
{
    /// <summary>
    /// Loot feed 的纯逻辑模型。
    ///
    /// 五个可见槽位属于同一个优先级池；等待中的卡片不推进生命周期，也不会被限流静默丢弃。
    /// 调度优先级、信息保真等级和视觉等级分别建模，避免“重要信息一定要像 Boss 一样吵闹”。
    /// </summary>
    internal sealed class LootFeedModel
    {
        internal const int MergeWindowMs = 2500;
        internal const int FadeMs = 280;
        internal const int MaxVisibleCards = 5;
        internal const int CountVisualIntervalMs = 125;
        internal const int MinPreemptVisibleMs = 400;
        internal const int MinResumeHoldMs = 700;
        internal const int MaxDistinctOrdinaryKillCards = 8;

        [Flags]
        internal enum Change
        {
            None = 0,
            Visual = 1,
            Geometry = 2
        }

        internal enum RetentionClass
        {
            Compressible = 0,
            ExactAggregate = 1,
            Guaranteed = 2
        }

        internal enum UrgencyClass
        {
            Ambient = 0,
            Prompt = 1,
            Immediate = 2
        }

        internal sealed class LootCard
        {
            internal string Kind;
            internal string Name;
            internal string Icon;
            internal string Source;
            internal int EliteLevel;
            internal long Count;
            internal long DisplayCount;
            internal long PreviousDisplayCount;
            internal int CountTransitionStartedMs;
            internal int LastDisplayCommitMs;
            internal int LastEventMs;
            internal int VisibleAgeMs;
            internal int RemainingHoldMs;
            internal int FadeElapsedMs;
            internal long Sequence;
            internal int Priority;
            internal RetentionClass Retention;
            internal UrgencyClass Urgency;
            internal bool IsAmbientSummary;
        }

        private readonly List<LootCard> _active = new List<LootCard>();
        private readonly List<LootCard> _pending = new List<LootCard>();
        private int _nowMs;
        private long _nextSequence;
        private int _displayPendingCount;
        private int _lastPendingDisplayCommitMs;

        internal int NowMs { get { return _nowMs; } }
        internal int ActiveCount { get { return _active.Count; } }
        internal int PendingCount { get { return _pending.Count; } }
        internal int DisplayPendingCount { get { return _displayPendingCount; } }
        internal IReadOnlyList<LootCard> Cards { get { return _active; } }
        internal IReadOnlyList<LootCard> PendingCards { get { return _pending; } }
        internal bool WantsTick
        {
            get
            {
                return _active.Count > 0
                    || _pending.Count > 0
                    || _displayPendingCount != _pending.Count;
            }
        }

        internal Change Add(
            string kind, string name, string icon, long count, string source, int eliteLevel = 0)
        {
            if (string.IsNullOrEmpty(kind) || string.IsNullOrEmpty(name) || count <= 0)
                return Change.None;

            source = string.IsNullOrEmpty(source) ? "unknown" : source;
            eliteLevel = kind == "kill" ? Math.Max(0, Math.Min(2, eliteLevel)) : 0;

            LootCard existing = FindMergeTarget(kind, name, icon, source, eliteLevel);
            if (existing != null)
                return MergeInto(existing, count);

            bool isOrdinaryKill = kind == "kill" && eliteLevel == 0 && source == "kill";
            bool isAmbientSummary = false;
            if (isOrdinaryKill && CountDetailedOrdinaryKills() >= MaxDistinctOrdinaryKillCards)
            {
                LootCard summary = FindAmbientSummary();
                if (summary != null)
                    return MergeInto(summary, count);

                name = "杂兵击杀";
                icon = null;
                isAmbientSummary = true;
            }

            LootCard card = CreateCard(kind, name, icon, count, source, eliteLevel);
            card.IsAmbientSummary = isAmbientSummary;
            _pending.Add(card);

            if (ReconcileSlots())
                return Change.Visual | Change.Geometry;

            // 新条目只进入等待队列时，不逐事件触发重绘；等待计数在 8 Hz 的 Tick 中提交。
            return Change.None;
        }

        internal Change Tick(int deltaMs)
        {
            deltaMs = Math.Max(0, deltaMs);
            _nowMs += deltaMs;
            Change change = Change.None;

            for (int i = _active.Count - 1; i >= 0; i--)
            {
                LootCard card = _active[i];
                card.VisibleAgeMs += deltaMs;

                if (card.Count != card.DisplayCount
                    && _nowMs - card.LastDisplayCommitMs >= CountVisualIntervalMs)
                {
                    if (CommitDisplayCount(card))
                        change |= Change.Geometry;
                    change |= Change.Visual;
                }

                int remainingDelta = deltaMs;
                if (card.RemainingHoldMs > 0)
                {
                    int holdStep = Math.Min(card.RemainingHoldMs, remainingDelta);
                    card.RemainingHoldMs -= holdStep;
                    remainingDelta -= holdStep;
                }
                if (card.RemainingHoldMs <= 0)
                    card.FadeElapsedMs += remainingDelta;

                if (card.FadeElapsedMs >= FadeMs)
                {
                    if (_pending.Count > 0)
                    {
                        int candidateIndex = SelectBestPendingIndex();
                        LootCard candidate = _pending[candidateIndex];
                        _pending.RemoveAt(candidateIndex);
                        Activate(candidate);
                        _active[i] = candidate; // 复用原槽，其他可见卡不换位
                    }
                    else
                    {
                        _active.RemoveAt(i);
                    }
                    change |= Change.Visual | Change.Geometry;
                }
            }

            if (ReconcileSlots())
                change |= Change.Visual | Change.Geometry;

            if (_displayPendingCount != _pending.Count
                && (_nowMs - _lastPendingDisplayCommitMs >= CountVisualIntervalMs
                    || _active.Count == 0))
            {
                bool geometryChanged = (_displayPendingCount == 0) != (_pending.Count == 0);
                _displayPendingCount = _pending.Count;
                _lastPendingDisplayCommitMs = _nowMs;
                change |= Change.Visual;
                if (geometryChanged)
                    change |= Change.Geometry;
            }

            return change;
        }

        internal static float AlphaFor(LootCard card, int fadeInMs)
        {
            if (card == null) return 0f;

            float alpha = 1f;
            if (fadeInMs > 0 && card.VisibleAgeMs < fadeInMs)
                alpha *= SmoothStep((float)card.VisibleAgeMs / fadeInMs);
            if (card.FadeElapsedMs > 0)
            {
                float progress = (float)card.FadeElapsedMs / FadeMs;
                alpha *= 1f - SmoothStep(progress);
            }
            return Math.Max(0f, Math.Min(1f, alpha));
        }

        internal static float SmoothStep(float value)
        {
            float t = Math.Max(0f, Math.Min(1f, value));
            return t * t * (3f - 2f * t);
        }

        /// <summary>
        /// 计数列的稳定几何桶：1 不显示计数，2..9 为一位，10..99 为两位，以此类推。
        /// 只有跨桶时才需要发布 bounds，同一位数内的割草累计仍是纯视觉更新。
        /// </summary>
        internal static int CountLayoutBucket(long count)
        {
            if (count <= 1) return 0;
            int digits = 0;
            long value = count;
            do
            {
                digits++;
                value /= 10;
            } while (value > 0);
            return digits;
        }

        private LootCard FindMergeTarget(
            string kind, string name, string icon, string source, int eliteLevel)
        {
            for (int i = _active.Count - 1; i >= 0; i--)
            {
                LootCard card = _active[i];
                if (Matches(card, kind, name, icon, source, eliteLevel)
                    && _nowMs - card.LastEventMs <= MergeWindowMs)
                    return card;
            }
            for (int i = _pending.Count - 1; i >= 0; i--)
            {
                LootCard card = _pending[i];
                if (Matches(card, kind, name, icon, source, eliteLevel))
                    return card;
            }
            return null;
        }

        private Change MergeInto(LootCard card, long count)
        {
            card.Count = SaturatingAdd(card.Count, count);
            card.LastEventMs = _nowMs;

            if (_active.IndexOf(card) < 0)
                return Change.None;

            card.RemainingHoldMs = HoldFor(card.Kind, card.Source, card.EliteLevel);
            card.FadeElapsedMs = 0;
            if (_nowMs - card.LastDisplayCommitMs >= CountVisualIntervalMs)
            {
                bool geometryChanged = CommitDisplayCount(card);
                return Change.Visual | (geometryChanged ? Change.Geometry : Change.None);
            }
            return Change.None;
        }

        private LootCard CreateCard(
            string kind, string name, string icon, long count, string source, int eliteLevel)
        {
            RetentionClass retention;
            UrgencyClass urgency;
            int priority;
            ResolvePolicy(kind, source, eliteLevel, out retention, out urgency, out priority);

            return new LootCard
            {
                Kind = kind,
                Name = name,
                Icon = icon,
                Source = source,
                EliteLevel = eliteLevel,
                Count = count,
                DisplayCount = count,
                PreviousDisplayCount = count,
                CountTransitionStartedMs = -1000000,
                LastDisplayCommitMs = _nowMs,
                LastEventMs = _nowMs,
                RemainingHoldMs = HoldFor(kind, source, eliteLevel),
                Sequence = _nextSequence++,
                Priority = priority,
                Retention = retention,
                Urgency = urgency
            };
        }

        private bool ReconcileSlots()
        {
            bool changed = false;

            while (_active.Count < MaxVisibleCards && _pending.Count > 0)
            {
                int candidateIndex = SelectBestPendingIndex();
                LootCard candidate = _pending[candidateIndex];
                _pending.RemoveAt(candidateIndex);
                Activate(candidate);
                _active.Add(candidate);
                changed = true;
            }

            while (_active.Count == MaxVisibleCards && _pending.Count > 0)
            {
                int candidateIndex = SelectBestPendingIndex();
                int victimIndex = SelectVictimIndex();
                LootCard candidate = _pending[candidateIndex];
                LootCard victim = _active[victimIndex];

                if (!Outranks(candidate, victim) || !CanPreempt(candidate, victim))
                    break;

                _pending.RemoveAt(candidateIndex);
                Demote(victim);
                _pending.Add(victim);
                Activate(candidate);
                _active[victimIndex] = candidate;
                changed = true;
            }

            return changed;
        }

        private int SelectBestPendingIndex()
        {
            int best = 0;
            for (int i = 1; i < _pending.Count; i++)
            {
                LootCard candidate = _pending[i];
                LootCard incumbent = _pending[best];
                if (candidate.Priority > incumbent.Priority
                    || (candidate.Priority == incumbent.Priority && candidate.Urgency > incumbent.Urgency)
                    || (candidate.Priority == incumbent.Priority && candidate.Urgency == incumbent.Urgency
                        && candidate.Sequence < incumbent.Sequence))
                    best = i;
            }
            return best;
        }

        private int SelectVictimIndex()
        {
            int victim = 0;
            for (int i = 1; i < _active.Count; i++)
            {
                LootCard candidate = _active[i];
                LootCard incumbent = _active[victim];
                if (candidate.Priority < incumbent.Priority
                    || (candidate.Priority == incumbent.Priority && candidate.Urgency < incumbent.Urgency)
                    || (candidate.Priority == incumbent.Priority && candidate.Urgency == incumbent.Urgency
                        && candidate.Sequence < incumbent.Sequence))
                    victim = i;
            }
            return victim;
        }

        private static bool Outranks(LootCard candidate, LootCard victim)
        {
            return candidate.Priority > victim.Priority
                || (candidate.Priority == victim.Priority && candidate.Urgency > victim.Urgency);
        }

        private static bool CanPreempt(LootCard candidate, LootCard victim)
        {
            return candidate.Urgency == UrgencyClass.Immediate
                || victim.VisibleAgeMs >= MinPreemptVisibleMs;
        }

        private void Activate(LootCard card)
        {
            card.VisibleAgeMs = 0;
            card.FadeElapsedMs = 0;
            card.RemainingHoldMs = Math.Max(card.RemainingHoldMs, MinResumeHoldMs);
            // pending 不老化：激活后重新开启合并窗口，避免排队时间制造同 key 重复卡。
            card.LastEventMs = _nowMs;
            if (card.Count != card.DisplayCount)
                CommitDisplayCount(card);
        }

        private static void Demote(LootCard card)
        {
            card.VisibleAgeMs = 0;
            card.FadeElapsedMs = 0;
            card.RemainingHoldMs = Math.Max(card.RemainingHoldMs, MinResumeHoldMs);
        }

        private bool CommitDisplayCount(LootCard card)
        {
            int previousBucket = CountLayoutBucket(card.DisplayCount);
            card.PreviousDisplayCount = card.DisplayCount;
            card.DisplayCount = card.Count;
            card.CountTransitionStartedMs = _nowMs;
            card.LastDisplayCommitMs = _nowMs;
            return previousBucket != CountLayoutBucket(card.DisplayCount);
        }

        private int CountDetailedOrdinaryKills()
        {
            int count = 0;
            for (int i = 0; i < _active.Count; i++)
                if (IsDetailedOrdinaryKill(_active[i])) count++;
            for (int i = 0; i < _pending.Count; i++)
                if (IsDetailedOrdinaryKill(_pending[i])) count++;
            return count;
        }

        private LootCard FindAmbientSummary()
        {
            for (int i = 0; i < _active.Count; i++)
                if (_active[i].IsAmbientSummary) return _active[i];
            for (int i = 0; i < _pending.Count; i++)
                if (_pending[i].IsAmbientSummary) return _pending[i];
            return null;
        }

        private static bool IsDetailedOrdinaryKill(LootCard card)
        {
            return card.Kind == "kill" && card.Source == "kill"
                && card.EliteLevel == 0 && !card.IsAmbientSummary;
        }

        private static bool Matches(
            LootCard card, string kind, string name, string icon, string source, int eliteLevel)
        {
            return card.Kind == kind
                && card.Name == name
                && card.Icon == icon
                && card.Source == source
                && card.EliteLevel == eliteLevel;
        }

        private static void ResolvePolicy(
            string kind, string source, int eliteLevel,
            out RetentionClass retention, out UrgencyClass urgency, out int priority)
        {
            if (kind == "kill" && eliteLevel >= 2)
            {
                retention = RetentionClass.Guaranteed;
                urgency = UrgencyClass.Immediate;
                priority = 3;
                return;
            }

            if (source == "quest_reward" || source == "level_reward" || source == "loot_box")
            {
                retention = RetentionClass.Guaranteed;
                urgency = UrgencyClass.Prompt;
                priority = 3;
                return;
            }

            if ((kind == "kill" && eliteLevel == 1) || source == "pickup")
            {
                retention = RetentionClass.ExactAggregate;
                urgency = UrgencyClass.Prompt;
                priority = 2;
                return;
            }

            if (kind == "kill")
            {
                retention = RetentionClass.Compressible;
                urgency = UrgencyClass.Ambient;
                priority = 1;
                return;
            }

            retention = RetentionClass.ExactAggregate;
            urgency = UrgencyClass.Prompt;
            priority = 2;
        }

        private static int HoldFor(string kind, string source, int eliteLevel)
        {
            if (kind == "kill" && eliteLevel >= 2) return 3000;
            if (source == "quest_reward" || source == "level_reward" || source == "loot_box") return 2800;
            if (kind == "kill" && eliteLevel == 1) return 2200;
            if (kind == "kill") return 1600;
            if (source == "pickup") return 2200;
            return 2200;
        }

        private static long SaturatingAdd(long left, long right)
        {
            if (right > 0 && left > long.MaxValue - right) return long.MaxValue;
            return left + right;
        }
    }
}
