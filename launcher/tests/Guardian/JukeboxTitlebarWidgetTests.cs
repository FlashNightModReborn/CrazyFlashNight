using System.Collections.Generic;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// JukeboxTitlebarWidget 状态机回归。
    ///
    /// 关键不变量：
    /// 1. 未就绪（s=0）→ 永远不可见，bgm 仍可缓存但 Visible=false
    /// 2. 切歌（bgm 变化）→ 清 ring buffer + 重置 marquee 起始 dwell
    /// 3. WantsAnimationTick = (gameReady && playing && !paused && !disableVisualizers) || marqueeActive
    /// 4. pause click：仅 hasBgm 时翻转 _isPaused 并调 _onTogglePause；无 BGM 时静默忽略
    /// 5. expand click：始终调 _onExpand（不依赖 bgmTitle，与 web 行为一致——展开浏览器无需正在播放）
    /// 6. pl>=2 → disableVisualizers=true，关闭 mini wave tick；title marquee 仍可启
    /// 7. UiData "bgm" piece 形如 "bgm:Title"，StripPrefix 后是纯标题
    /// </summary>
    public class JukeboxTitlebarWidgetTests
    {
        private class Capture
        {
            public int PauseToggleCount;
            public int ExpandCount;
        }

        private static JukeboxTitlebarWidget MakeWidget(out Capture cap)
        {
            cap = new Capture();
            Capture local = cap;
            Control anchor = new Control();
            JukeboxTitlebarWidget w = new JukeboxTitlebarWidget(
                anchor,
                delegate { local.PauseToggleCount++; },
                delegate { local.ExpandCount++; });
            w.ForceGameReady(true);
            return w;
        }

        private static IReadOnlyDictionary<string, string> Snapshot(params string[] kvPieces)
        {
            Dictionary<string, string> dict = new Dictionary<string, string>();
            foreach (string p in kvPieces)
            {
                int colon = p.IndexOf(':');
                string k = colon > 0 ? p.Substring(0, colon) : p;
                dict[k] = p;
            }
            return dict;
        }

        // ── Visible 门控 ──
        [Fact]
        public void NotReady_NoVisible()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.ForceGameReady(false);
            Assert.False(w.Visible);
        }

        [Fact]
        public void Ready_Visible_EvenWithoutBgm()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            // 即便没有 BGM，title 显示"未播放"，控件仍可见（与 web has-bgm 类切换 visibility 不同——
            // C# widget 整条永远显示，has-bgm 仅控制 mini wave 与暗色 title）
            Assert.True(w.Visible);
            Assert.Equal("", w.CurrentTitle);
        }

        // ── UiData 通道 ──
        [Fact]
        public void Bgm_UpdatesTitle_StripsPrefix()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.OnUiDataChanged(Snapshot("bgm:Final Sky"), new HashSet<string> { "bgm" });
            Assert.Equal("Final Sky", w.CurrentTitle);
        }

        [Fact]
        public void Bgm_Change_ClearsHistory()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.OnUiDataChanged(Snapshot("bgm:A"), new HashSet<string> { "bgm" });
            w.InjectPeakSample(0.5f, 0.5f);
            w.InjectPeakSample(0.6f, 0.4f);
            Assert.Equal(2, w.PeakHistoryLen);
            w.OnUiDataChanged(Snapshot("bgm:B"), new HashSet<string> { "bgm" });
            Assert.Equal(0, w.PeakHistoryLen);
            Assert.Equal("B", w.CurrentTitle);
        }

        [Fact]
        public void Bgm_Same_NoOp()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.OnUiDataChanged(Snapshot("bgm:Same"), new HashSet<string> { "bgm" });
            w.InjectPeakSample(0.3f, 0.3f);
            Assert.Equal(1, w.PeakHistoryLen);
            // 相同值不触发 history 清空
            w.OnUiDataChanged(Snapshot("bgm:Same"), new HashSet<string> { "bgm" });
            Assert.Equal(1, w.PeakHistoryLen);
        }

        [Fact]
        public void GameNotReady_ResetsState()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.OnUiDataChanged(Snapshot("bgm:Track"), new HashSet<string> { "bgm" });
            w.InjectPeakSample(0.5f, 0.5f);
            w.ForceIsPlaying(true);
            // s:0 推送 → 复位
            w.OnUiDataChanged(Snapshot("s:0"), new HashSet<string> { "s" });
            Assert.False(w.Visible);
            Assert.Equal("", w.CurrentTitle);
            Assert.Equal(0, w.PeakHistoryLen);
            Assert.False(w.IsPlayingForTest);
        }

        // ── pl perf level → disableVisualizers ──
        [Fact]
        public void PerfLevel_HighDisablesVisualizers()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.OnUiDataChanged(Snapshot("pl:0"), new HashSet<string> { "pl" });
            Assert.False(w.DisableVisualizersForTest);
            w.OnUiDataChanged(Snapshot("pl:2"), new HashSet<string> { "pl" });
            Assert.True(w.DisableVisualizersForTest);
            w.OnUiDataChanged(Snapshot("pl:1"), new HashSet<string> { "pl" });
            Assert.False(w.DisableVisualizersForTest);
        }

        // ── WantsAnimationTick 推导 ──
        [Fact]
        public void WantsTick_RequiresPlayingAndNotPaused()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.ForceBgmTitle("Track");
            // 默认 not playing → 不需要 tick
            Assert.False(w.WantsAnimationTick);
            w.ForceIsPlaying(true);
            Assert.True(w.WantsAnimationTick);
            w.ForceIsPaused(true);
            Assert.False(w.WantsAnimationTick); // paused 镜像生效
            w.ForceIsPaused(false);
            w.ForceDisableVisualizers(true);
            Assert.False(w.WantsAnimationTick); // pl 高也关
            w.ForceDisableVisualizers(false);
            Assert.True(w.WantsAnimationTick);
        }

        [Fact]
        public void WantsTick_FalseWhenNotVisible()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.ForceGameReady(false);
            w.ForceIsPlaying(true);
            Assert.False(w.WantsAnimationTick);
        }

        // ── pause click ──
        [Fact]
        public void PauseClick_WithBgm_TogglesPaused_AndCallsCallback()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            w.ForceBgmTitle("Track");
            w.ForceIsPlaying(true);
            Assert.False(w.IsPausedForTest);
            w.SimulatePauseClick();
            Assert.True(w.IsPausedForTest);
            Assert.Equal(1, c.PauseToggleCount);
            // 再点 → 恢复
            w.SimulatePauseClick();
            Assert.False(w.IsPausedForTest);
            Assert.Equal(2, c.PauseToggleCount);
        }

        [Fact]
        public void PauseClick_NoBgm_Ignored()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            // 没有 BGM
            Assert.Equal("", w.CurrentTitle);
            w.SimulatePauseClick();
            Assert.False(w.IsPausedForTest);
            Assert.Equal(0, c.PauseToggleCount);
        }

        // ── expand click ──
        [Fact]
        public void ExpandClick_AlwaysCallsCallback()
        {
            Capture c;
            JukeboxTitlebarWidget w = MakeWidget(out c);
            // 即使无 BGM 也允许展开（玩家进入面板浏览选歌）
            w.SimulateExpandClick();
            Assert.Equal(1, c.ExpandCount);
            w.ForceBgmTitle("Track");
            w.SimulateExpandClick();
            Assert.Equal(2, c.ExpandCount);
        }

        // ── helper pure functions ──
        [Theory]
        [InlineData("bgm:Final Sky", "bgm", "Final Sky")]
        [InlineData("bgm:", "bgm", "")]
        [InlineData("Final Sky", "bgm", "Final Sky")]   // 无前缀 → 原样返回
        [InlineData("", "bgm", "")]
        [InlineData(null, "bgm", "")]
        public void StripPrefix_Cases(string input, string key, string expected)
        {
            Assert.Equal(expected, JukeboxTitlebarWidget.StripPrefix(input, key));
        }

        [Theory]
        [InlineData("pl:2", "pl", 0, 2)]
        [InlineData("pl:0", "pl", 99, 0)]
        [InlineData("pl:abc", "pl", 7, 7)]   // 解析失败 → fallback
        [InlineData("", "pl", 99, 99)]
        public void ParseIntPiece_Cases(string input, string key, int fallback, int expected)
        {
            Assert.Equal(expected, JukeboxTitlebarWidget.ParseIntPiece(input, key, fallback));
        }
    }
}
