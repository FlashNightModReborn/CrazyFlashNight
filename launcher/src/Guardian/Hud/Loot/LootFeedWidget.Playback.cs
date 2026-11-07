using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.PlayerInfo;

namespace CF7Launcher.Guardian.Hud.Loot
{
    public sealed partial class LootFeedWidget : INativeHudResumable
    {
        private sealed class ContentPlayback
        {
            internal string Icon;
            internal LootIconCatalog.IconDescription Description;
            internal long Elapsed, Started;
            internal bool Running, Retained;
            internal int Content = -1;
        }

        private readonly Dictionary<long, ContentPlayback> _contentPlayback = new Dictionary<long, ContentPlayback>();
        private readonly List<long> _removedPlayback = new List<long>();
        private Func<long> _contentClock = () => Stopwatch.GetElapsedTime(0L).Ticks;
        private bool _hostSuppressed;

        internal LootFeedWidget(Control anchor, LootIconCatalog icons, Func<long> contentClock)
            : this(anchor, icons)
        {
            _contentClock = contentClock ?? throw new ArgumentNullException(nameof(contentClock));
        }

        private void SynchronizeContentPlayback()
        {
            long now = Math.Max(0L, _contentClock());
            bool allowAnimation = !PlayerHudMotionSettings.ReducedMotion;
            foreach (var state in _contentPlayback.Values)
            {
                if (state.Running)
                {
                    long delta = now >= state.Started ? now - state.Started : 0L;
                    state.Elapsed = delta > long.MaxValue - state.Elapsed ? long.MaxValue : state.Elapsed + delta;
                }
                state.Running = false;
                state.Retained = false;
            }
            var cards = _model.Cards;
            for (int i = 0; i < cards.Count; i++)
            {
                var card = cards[i];
                if (!_contentPlayback.TryGetValue(card.Sequence, out var state) || state.Icon != card.Icon)
                {
                    state = new ContentPlayback { Icon = card.Icon };
                    _contentPlayback[card.Sequence] = state;
                }
                state.Retained = true;
                // Preparation is separate from the signature/paint hot path. WebP
                // metadata is deferred while the user has selected static content.
                state.Description = _icons.DescribeForPlayback(card.Icon, allowAnimation);
                state.Content = state.Description?.Sample(state.Elapsed, allowAnimation) ?? -1;
                state.Running = !_hostSuppressed && allowAnimation && state.Description?.Animated == true;
                state.Started = now;
            }
            // Never bind a first-time pending card, but retain a preempted card's phase.
            var pending = _model.PendingCards;
            for (int i = 0; i < pending.Count; i++)
                if (_contentPlayback.TryGetValue(pending[i].Sequence, out var state)) state.Retained = true;
            _removedPlayback.Clear();
            foreach (var pair in _contentPlayback)
                if (!pair.Value.Retained) _removedPlayback.Add(pair.Key);
            for (int i = 0; i < _removedPlayback.Count; i++) _contentPlayback.Remove(_removedPlayback[i]);
        }

        private int ContentVisualSignature(LootFeedModel.LootCard card)
        {
            if (!_contentPlayback.TryGetValue(card.Sequence, out var state) || state.Description == null) return 0;
            return unchecked((state.Content + 2) * 31 + state.Description.Revision);
        }

        private bool DrawContentIcon(Graphics graphics, LootFeedModel.LootCard card, Rectangle destination, float alpha)
        {
            return _contentPlayback.TryGetValue(card.Sequence, out var state)
                && _icons.TryDrawPlayback(graphics, destination, state.Description, state.Content, alpha);
        }

        public void SetHostSuppressed(bool suppressed)
        {
            if (_disposed || _hostSuppressed == suppressed) return;
            SynchronizeContentPlayback(); // Bank visible time at the transition, not at the next Tick.
            _hostSuppressed = suppressed;
            SynchronizeContentPlayback();
            if (!suppressed && Visible)
            {
                _lastVisualSignature = ComputeVisualSignature();
                _lastRepaintAtMs = _model.NowMs;
                FireRepaint();
            }
        }
    }
}
