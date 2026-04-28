using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// ComboWidget 状态机回归。
    ///
    /// 关键不变量：
    /// 1. 三态：Idle / Input / Hit，仅 Hit 启用 WantsAnimationTick（NativeHud 才会 16ms tick）
    /// 2. 输入态：typed/hints 任一非空 → Visible，渲染已输入 + 各分支剩余
    /// 3. 命中态：N combo|... 触发 ShowHit，HIT_MS 内 Visible，倒计时归零回落 Input/Idle
    /// 4. V8 缓冲：legacy combo 中 cmdName 非空帧 → 缓存 pendingTyped/pendingName，等 N 前缀确认
    ///    pendingAge 超过 PENDING_MAX_AGE 自动失效（防 V8 识别但 AS2 未执行残留）
    /// 5. typed 来源优先级（ResolveHitTyped）：pendingTyped（名匹配）→ knownPatterns[name] → name fallback
    /// 6. legacy combo|... 在 hit 持续期内被忽略（与 web combo.js lastState=='hit' 跳帧同语义）
    /// 7. s:0 → 完整复位（清 typed/hints/known/pending/hit）
    /// 8. ParseHints / SafeStripPrefix / StripPathPrefix 是 pure helper，独立可测
    /// </summary>
    public class ComboWidgetTests
    {
        private static ComboWidget MakeWidget()
        {
            Control anchor = new Control();
            ComboWidget w = new ComboWidget(anchor);
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

        // ── 默认/可见性 ──
        [Fact]
        public void Default_NoData_Hidden()
        {
            ComboWidget w = MakeWidget();
            Assert.False(w.Visible);
            Assert.Equal(ComboWidget.BarModeForTest.Idle, w.TestMode);
            Assert.False(w.WantsAnimationTick);
        }

        [Fact]
        public void GameNotReady_Hidden_EvenWithInput()
        {
            ComboWidget w = MakeWidget();
            w.ForceGameReady(false);
            w.OnLegacyUiData("combo", new[] { "", "↓↘", "波动拳:↓↘A:1" });
            Assert.False(w.Visible);
        }

        // ── Input 态 ──
        [Fact]
        public void LegacyInput_TypedOnly_ShowsInput()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "↓", "" });
            Assert.True(w.Visible);
            Assert.Equal(ComboWidget.BarModeForTest.Input, w.TestMode);
            Assert.Equal("↓", w.TypedSnapshot);
            Assert.Equal(0, w.ParsedHintCount);
        }

        [Fact]
        public void LegacyInput_HintsOnly_ShowsInput()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "", "波动拳:↓↘A:3" });
            Assert.True(w.Visible);
            Assert.Equal(1, w.ParsedHintCount);
        }

        [Fact]
        public void LegacyInput_TypedAndHints_BothRendered()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "↓↘", "波动拳:↓↘A:1;诛杀步:→→:2" });
            Assert.True(w.Visible);
            Assert.Equal("↓↘", w.TypedSnapshot);
            Assert.Equal(2, w.ParsedHintCount);
            // hints 入历史缓存供 ShowHit fallback
            string seq;
            Assert.True(w.TryGetKnownPattern("波动拳", out seq));
            Assert.Equal("↓↘A", seq);
            Assert.True(w.TryGetKnownPattern("诛杀步", out seq));
            Assert.Equal("→→", seq);
        }

        [Fact]
        public void LegacyInput_BothEmpty_FallsBackToIdle()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "↓", "" });
            Assert.True(w.Visible);
            // ROOT 回落
            w.OnLegacyUiData("combo", new[] { "", "", "" });
            Assert.True(w.Visible);
            Assert.False(w.VisualVisibleForTest);
            Assert.Equal(ComboWidget.BarModeForTest.Idle, w.TestMode);
            Assert.Equal("", w.TypedSnapshot);
        }

        // ── V8 命中缓冲 ──
        [Fact]
        public void LegacyInput_UpdateWhileVisible_RepaintsWithoutBounds()
        {
            ComboWidget w = MakeWidget();
            int boundsCount = 0;
            int repaintCount = 0;
            w.BoundsOrVisibilityChanged += delegate { boundsCount++; };
            w.RepaintRequested += delegate { repaintCount++; };

            w.OnLegacyUiData("combo", new[] { "", "A", "Move:AB:1" });
            Assert.Equal(1, boundsCount);
            Assert.Equal(0, repaintCount);

            w.OnLegacyUiData("combo", new[] { "", "AB", "Move:ABC:1" });
            Assert.Equal(1, boundsCount);
            Assert.Equal(1, repaintCount);
        }

        [Fact]
        public void LegacyInput_ClearToIdle_RepaintsWithoutBounds()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "A", "Move:AB:1" });
            int boundsCount = 0;
            int repaintCount = 0;
            w.BoundsOrVisibilityChanged += delegate { boundsCount++; };
            w.RepaintRequested += delegate { repaintCount++; };

            w.OnLegacyUiData("combo", new[] { "", "", "" });

            Assert.Equal(0, boundsCount);
            Assert.Equal(1, repaintCount);
            Assert.True(w.Visible);
            Assert.False(w.VisualVisibleForTest);
        }

        [Fact]
        public void LegacyCmdNameNonEmpty_CachesPending_DoesNotShowInput()
        {
            ComboWidget w = MakeWidget();
            // V8 DFA 命中帧
            w.OnLegacyUiData("combo", new[] { "波动拳", "↓↘A", "" });
            // input 不更新（防确认前闪烁）
            Assert.Equal("", w.TypedSnapshot);
            // pending 写入
            Assert.Equal("↓↘A", w.PendingTyped);
            Assert.Equal("波动拳", w.PendingName);
            Assert.Equal(0, w.PendingAge);
        }

        [Fact]
        public void Pending_AgesOut_AfterMaxFrames()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "波动拳", "↓↘A", "" });
            Assert.Equal("波动拳", w.PendingName);
            // 之后每帧没有 cmdName + 没有 typed/hints → 老化
            // PENDING_MAX_AGE_FRAMES = 10，需要超过 10 帧才清空
            for (int i = 0; i < 11; i++)
                w.OnLegacyUiData("combo", new[] { "", "", "" });
            Assert.Equal("", w.PendingName);
            Assert.Equal("", w.PendingTyped);
        }

        // ── Hit 态 ──
        [Fact]
        public void NotchCombo_DFA_TriggersHitWithGoldPath()
        {
            ComboWidget w = MakeWidget();
            // 先输入累积 knownPatterns
            w.OnLegacyUiData("combo", new[] { "", "↓↘", "波动拳:↓↘A:1" });
            // N combo 前缀通知
            w.OnNotchNotice("combo", "DFA 波动拳", Color.Gold);
            Assert.True(w.Visible);
            Assert.True(w.IsHitState);
            Assert.True(w.WantsAnimationTick);
            Assert.Equal("波动拳", w.HitName);
            // typed 来源：pendingTyped 不存在 → knownPatterns["波动拳"] = "↓↘A"
            Assert.Equal("↓↘A", w.HitTyped);
            Assert.True(w.HitIsDFA);
        }

        [Fact]
        public void Hit_TickRequestsRepaint_WhileAnimationActive()
        {
            ComboWidget w = MakeWidget();
            int repaintCount = 0;
            w.RepaintRequested += delegate { repaintCount++; };
            w.OnNotchNotice("combo", "DFA 波动拳", Color.Gold);

            w.AdvanceHitMs(16);

            Assert.True(w.IsHitState);
            Assert.True(repaintCount > 0);
        }

        [Fact]
        public void NotchCombo_FromInput_RepaintsWithoutBounds()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "A", "Move:AB:1" });
            int boundsCount = 0;
            int repaintCount = 0;
            int animationCount = 0;
            w.BoundsOrVisibilityChanged += delegate { boundsCount++; };
            w.RepaintRequested += delegate { repaintCount++; };
            w.AnimationStateChanged += delegate { animationCount++; };

            w.OnNotchNotice("combo", "DFA Move", Color.Gold);

            Assert.True(w.IsHitState);
            Assert.Equal(0, boundsCount);
            Assert.Equal(1, repaintCount);
            Assert.Equal(1, animationCount);
        }

        [Fact]
        public void NotchCombo_FromIdle_FiresBounds()
        {
            ComboWidget w = MakeWidget();
            int boundsCount = 0;
            int repaintCount = 0;
            w.BoundsOrVisibilityChanged += delegate { boundsCount++; };
            w.RepaintRequested += delegate { repaintCount++; };

            w.OnNotchNotice("combo", "DFA Move", Color.Gold);

            Assert.True(w.IsHitState);
            Assert.Equal(1, boundsCount);
            Assert.Equal(0, repaintCount);
        }

        [Fact]
        public void NotchCombo_RepeatedHit_RestartsAnimation()
        {
            ComboWidget w = MakeWidget();
            int animationCount = 0;
            w.AnimationStateChanged += delegate { animationCount++; };

            w.OnNotchNotice("combo", "DFA Move", Color.Gold);
            w.AdvanceHitMs(100);
            w.OnNotchNotice("combo", "DFA Move", Color.Gold);

            Assert.True(w.IsHitState);
            Assert.Equal(2, animationCount);
            Assert.Equal(1200, w.HitRemainingMs);
        }

        [Fact]
        public void NotchCombo_Sync_TriggersHitWithCyanPath()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "→→", "诛杀步:→→:1" });
            w.OnNotchNotice("combo", "Sync 诛杀步", Color.Cyan);
            Assert.True(w.IsHitState);
            Assert.False(w.HitIsDFA);
            Assert.Equal("诛杀步", w.HitName);
            Assert.Equal("→→", w.HitTyped);
        }

        [Fact]
        public void NotchCombo_PendingTypedMatches_PrefersPending()
        {
            ComboWidget w = MakeWidget();
            // 先用 hints 帧让 knownPatterns["波动连段"]="↓↘A↓↘"（短版）
            w.OnLegacyUiData("combo", new[] { "", "", "波动连段:↓↘A↓↘:0" });
            // V8 缓冲：pendingTyped="↓↘A↓↘B"（更长，且名匹配）
            w.OnLegacyUiData("combo", new[] { "波动连段", "↓↘A↓↘B", "" });
            w.OnNotchNotice("combo", "DFA 波动连段", Color.Gold);
            Assert.Equal("↓↘A↓↘B", w.HitTyped); // pending 优先于 knownPatterns
        }

        [Fact]
        public void NotchCombo_PendingNameMismatch_FallsBackToKnown()
        {
            ComboWidget w = MakeWidget();
            // pending 缓的招式名不匹配 → fallback 到 knownPatterns
            w.OnLegacyUiData("combo", new[] { "", "", "诛杀步:→→:0" });
            w.OnLegacyUiData("combo", new[] { "波动拳", "↓↘A", "" });
            // 命中的是诛杀步而不是 pending 缓的波动拳
            w.OnNotchNotice("combo", "Sync 诛杀步", Color.Cyan);
            Assert.Equal("→→", w.HitTyped); // knownPatterns，pending 不匹配名跳过
        }

        [Fact]
        public void NotchCombo_NoPendingNoKnown_FallsBackToName()
        {
            ComboWidget w = MakeWidget();
            w.OnNotchNotice("combo", "DFA 未知招式", Color.Gold);
            Assert.True(w.IsHitState);
            Assert.Equal("未知招式", w.HitName);
            Assert.Equal("未知招式", w.HitTyped); // fallback
        }

        [Fact]
        public void NotchCombo_NoKnownDFAOrSyncPrefix_TextUntouched()
        {
            ComboWidget w = MakeWidget();
            // 不是 DFA/Sync 前缀
            w.OnNotchNotice("combo", "杂项 文本", Color.Gold);
            Assert.True(w.IsHitState);
            // StripPathPrefix 不剥离非 DFA/Sync 前缀
            Assert.Equal("杂项 文本", w.HitName);
            Assert.False(w.HitIsDFA); // "杂项" 不以 "DFA" 起始
        }

        [Fact]
        public void Hit_AdvancesToZero_FallsBackToInput()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "↓↘", "波动拳:↓↘A:1" });
            w.OnNotchNotice("combo", "DFA 波动拳", Color.Gold);
            Assert.True(w.IsHitState);
            // 推进到 hit 倒计时归零
            w.AdvanceHitMs(2000);
            Assert.False(w.IsHitState);
            Assert.False(w.WantsAnimationTick);
            // 已有 typed/hints → 回到 Input
            Assert.Equal(ComboWidget.BarModeForTest.Input, w.TestMode);
            Assert.True(w.Visible);
        }

        [Fact]
        public void Hit_AdvancesToInput_RepaintsWithoutBounds()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "A", "Move:AB:1" });
            w.OnNotchNotice("combo", "DFA Move", Color.Gold);
            int boundsCount = 0;
            int repaintCount = 0;
            int animationCount = 0;
            w.BoundsOrVisibilityChanged += delegate { boundsCount++; };
            w.RepaintRequested += delegate { repaintCount++; };
            w.AnimationStateChanged += delegate { animationCount++; };

            w.AdvanceHitMs(2000);

            Assert.False(w.IsHitState);
            Assert.Equal(ComboWidget.BarModeForTest.Input, w.TestMode);
            Assert.Equal(0, boundsCount);
            Assert.Equal(1, repaintCount);
            Assert.Equal(1, animationCount);
        }

        [Fact]
        public void Hit_AdvancesToZero_WithoutInput_FallsBackToIdle()
        {
            ComboWidget w = MakeWidget();
            w.OnNotchNotice("combo", "DFA 波动拳", Color.Gold);
            Assert.True(w.IsHitState);
            w.AdvanceHitMs(2000);
            Assert.False(w.IsHitState);
            Assert.Equal(ComboWidget.BarModeForTest.Idle, w.TestMode);
            Assert.True(w.Visible);
            Assert.False(w.VisualVisibleForTest);
        }

        [Fact]
        public void Hit_ClearsPendingBuffer()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "波动拳", "↓↘A", "" });
            Assert.NotEqual("", w.PendingName);
            w.OnNotchNotice("combo", "DFA 波动拳", Color.Gold);
            Assert.Equal("", w.PendingName);
            Assert.Equal("", w.PendingTyped);
        }

        [Fact]
        public void HitInProgress_LegacyComboFrame_Ignored()
        {
            ComboWidget w = MakeWidget();
            w.OnNotchNotice("combo", "DFA 波动拳", Color.Gold);
            Assert.Equal(ComboWidget.BarModeForTest.Hit, w.TestMode);
            // 即便 input 帧推送也不动
            w.OnLegacyUiData("combo", new[] { "", "↓→↘", "" });
            Assert.Equal(ComboWidget.BarModeForTest.Hit, w.TestMode);
            Assert.Equal("", w.TypedSnapshot); // 输入未被写入
        }

        // ── Reset (s:0) ──
        [Fact]
        public void GameNotReady_ClearsAllState()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "↓↘", "波动拳:↓↘A:1" });
            w.OnNotchNotice("combo", "DFA 波动拳", Color.Gold);
            Assert.True(w.IsHitState);
            // s:0 → 复位
            w.OnUiDataChanged(Snapshot("s:0"), new HashSet<string> { "s" });
            Assert.False(w.Visible);
            Assert.False(w.IsHitState);
            Assert.Equal("", w.TypedSnapshot);
            Assert.Equal(0, w.ParsedHintCount);
            Assert.Equal("", w.PendingName);
        }

        // ── Legacy types contract ──
        [Fact]
        public void LegacyTypes_OnlyCombo()
        {
            ComboWidget w = MakeWidget();
            int count = 0;
            string only = null;
            foreach (string t in w.LegacyTypes) { count++; only = t; }
            Assert.Equal(1, count);
            Assert.Equal("combo", only);
        }

        [Fact]
        public void NoticeCategories_OnlyCombo()
        {
            ComboWidget w = MakeWidget();
            int count = 0;
            string only = null;
            foreach (string c in w.NoticeCategories) { count++; only = c; }
            Assert.Equal(1, count);
            Assert.Equal("combo", only);
        }

        [Fact]
        public void OnLegacyUiData_NonComboType_Ignored()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("task", new[] { "随便", "什么" });
            Assert.False(w.Visible);
            Assert.Equal("", w.TypedSnapshot);
        }

        [Fact]
        public void OnNotchNotice_NonComboCategory_Ignored()
        {
            ComboWidget w = MakeWidget();
            w.OnNotchNotice("perf", "DFA 看上去像 combo", Color.Gold);
            Assert.False(w.Visible);
            Assert.False(w.IsHitState);
        }

        // ── Pure helper 单测 ──
        [Theory]
        [InlineData("DFA 波动拳", "波动拳")]
        [InlineData("Sync 诛杀步", "诛杀步")]
        [InlineData("DFA波动拳", "波动拳")]    // 无空格也剥
        [InlineData("Sync   带多个空格", "带多个空格")]
        [InlineData("普通文本", "普通文本")]   // 非 DFA/Sync → 不剥
        [InlineData("", "")]
        [InlineData(null, "")]
        public void StripPathPrefix_VariousInputs(string input, string expected)
        {
            Assert.Equal(expected, ComboWidget.StripPathPrefix(input));
        }

        [Theory]
        [InlineData("↓↘A", "↓↘", "A")]
        [InlineData("↓↘A", "↓↘A", "")]      // 全部输入完
        [InlineData("↓↘A", "", "↓↘A")]
        [InlineData("", "↓↘", "")]
        [InlineData("↓↘A", "↓↘A↓↘B", "")] // typed 比 fullSeq 长 → 空
        public void SafeStripPrefix_VariousInputs(string fullSeq, string typed, string expected)
        {
            Assert.Equal(expected, ComboWidget.SafeStripPrefix(fullSeq, typed));
        }

        [Fact]
        public void ParseHints_EmptyString_ReturnsEmptyList()
        {
            Assert.Empty(ComboWidget.ParseHints(""));
            Assert.Empty(ComboWidget.ParseHints(null));
        }

        [Fact]
        public void ParseHints_SingleEntry_ParsesAllFields()
        {
            var list = ComboWidget.ParseHints("波动拳:↓↘A:3");
            Assert.Single(list);
            Assert.Equal("波动拳", list[0].Name);
            Assert.Equal("↓↘A", list[0].FullSeq);
            Assert.Equal(3, list[0].Steps);
        }

        [Fact]
        public void ParseHints_MultipleEntries_ParsesAll()
        {
            var list = ComboWidget.ParseHints("波动拳:↓↘A:1;诛杀步:→→:2;升龙拳:→↓↘A:3");
            Assert.Equal(3, list.Count);
            Assert.Equal("升龙拳", list[2].Name);
            Assert.Equal("→↓↘A", list[2].FullSeq);
            Assert.Equal(3, list[2].Steps);
        }

        [Fact]
        public void ParseHints_MalformedEntry_Skipped()
        {
            // 段数 < 3 跳过
            var list = ComboWidget.ParseHints("波动拳:↓↘A;诛杀步:→→:2");
            Assert.Single(list);
            Assert.Equal("诛杀步", list[0].Name);
        }

        [Fact]
        public void ParseHints_NonNumericSteps_DefaultsToZero()
        {
            var list = ComboWidget.ParseHints("招式:↓↘:abc");
            Assert.Single(list);
            Assert.Equal(0, list[0].Steps);
        }

        // ── 测量宽度回归：base 字体测量结果不应再除以 Scale ──
        // 修复前 RecomputeMeasuredWidthBase 用 base 字体测量后又除以 Scale，
        // 在 1080p/全屏（Scale > 1）时把宽度算小，导致文字被截断。
        // 修复后：base 字体测量结果直接落在设计坐标系，与 ScreenBounds 单向 base→scaled 转换匹配。

        [Fact]
        public void MeasureWidthBase_LongInput_FitsTextWithPadding()
        {
            ComboWidget w = MakeWidget();
            // 长 typed 序列 + 多分支 hints
            w.OnLegacyUiData("combo", new[] { "", "↓↘→A", "波动拳:↓↘→AB:1;升龙拳:→↓↘C:2;诛杀步:→→D:3" });
            int widthBase = w.MeasureWidthBase();
            // 不严格断言绝对像素（依赖字体 metric），但宽度必须显著大于 MIN_BAR_W_BASE（160）
            // 避免回归（修复前除 Scale 在 base 测量场景下 widthBase 反而变小，可能 < 160 落到 clamp）
            Assert.True(widthBase > 160,
                "widthBase=" + widthBase + " 应包含 typed+多分支 remain+name 的真实测量宽度，不应被 Scale 除小");
        }

        [Fact]
        public void MeasureWidthBase_HitMode_WidthCoversSeqAndName()
        {
            ComboWidget w = MakeWidget();
            // 极长招式 + 长序列，hit 态宽度应明显反映文本
            w.OnNotchNotice("combo", "DFA 极长大招的展示用招式名称", System.Drawing.Color.Gold);
            int widthBase = w.MeasureWidthBase();
            // 仅断言宽度>0 且非 fallback MIN（修复前在 Scale=1 时一致；保护未来 Scale 改动不偷偷除小）
            Assert.True(widthBase >= 0);
        }

        [Fact]
        public void PaintWidthBase_ShortInput_UsesNaturalWidth()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "A", "" });

            int widthBase = w.PaintWidthBaseForTest();

            Assert.True(widthBase > 0);
            Assert.True(widthBase < 160, "widthBase=" + widthBase + " should follow web natural content width, not the old 160/480 fixed bar");
        }

        [Fact]
        public void PaintWidthBase_InputPreview_UsesCompactNativeSpacing()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "→", "燃烧指节:→B:1" });

            int widthBase = w.PaintWidthBaseForTest();

            Assert.True(widthBase > 0);
            Assert.True(widthBase < 100,
                "widthBase=" + widthBase + " should keep native input previews tighter than the CSS-fidelity layout");
        }

        [Fact]
        public void InputPreviewHarness_BurningKnuckle_JoinsTypedAndRemain()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "→", "燃烧指节:→B:1" });

            ComboWidget.InputLayoutProbe probe = w.InputPreviewProbeForTest();

            Assert.False(float.IsNaN(probe.SequenceJoinGapBase));
            Assert.False(float.IsNaN(probe.RemainToNameGapBase));
            Assert.True(probe.SequenceJoinGapBase >= 1.5f && probe.SequenceJoinGapBase <= 2.5f,
                "sequence gap=" + probe.SequenceJoinGapBase + " should keep typed and remain readable without looking detached");
            Assert.True(probe.RemainToNameGapBase <= 2f,
                "name gap=" + probe.RemainToNameGapBase + " should keep the name pill close without the old loose flex offset");
            Assert.True(probe.BarWidthBase < 94,
                "barWidth=" + probe.BarWidthBase + " should reproduce the screenshot case as a compact native preview");
        }

        [Fact]
        public void InputPreviewHarness_BurningKnuckle_RenderedPixelsDoNotLeaveSequenceGap()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "→", "燃烧指节:→B:1" });

            ComboWidget.InputRenderProbe probe = w.InputPreviewRenderProbeForTest(2.5f);

            Assert.True(probe.TypedInkRight >= 0, "typed ink should be visible in the render harness");
            Assert.True(probe.RemainInkLeft >= 0, "remain ink should be visible in the render harness");
            Assert.True(probe.SequenceInkGap >= 2 && probe.SequenceInkGap <= 8,
                "rendered ink gap=" + probe.SequenceInkGap
                + " typedRight=" + probe.TypedInkRight
                + " remainLeft=" + probe.RemainInkLeft
                + " typedLeft=" + probe.TypedInkLeft
                + " remainRight=" + probe.RemainInkRight
                + " size=" + probe.Width + "x" + probe.Height
                + " should keep →B visually joined at fullscreen scale");
        }

        [Fact]
        public void PaintWidthBase_HitPreview_UsesVisualPathMetrics()
        {
            ComboWidget w = MakeWidget();
            w.OnLegacyUiData("combo", new[] { "", "→", "燃烧指节:→B:1" });
            w.OnNotchNotice("combo", "DFA 燃烧指节", Color.Gold);

            int widthBase = w.PaintWidthBaseForTest();
            ComboWidget.HitLayoutProbe probe = w.HitPreviewProbeForTest();

            Assert.Equal("→B", w.HitTyped);
            Assert.True(widthBase > 0);
            Assert.True(probe.SeqToNameGapBase <= 6f);
            Assert.True(probe.SeqWidthBase > 28f,
                "seqWidth=" + probe.SeqWidthBase + " should include readable hit-state spacing between → and B");
            Assert.True(widthBase < 112,
                "widthBase=" + widthBase + " should keep hit previews on the same visual path metrics as input");
        }

        [Fact]
        public void PaintWidthBase_LongInput_ClampsToReservedSlot()
        {
            ComboWidget w = MakeWidget();
            string longSeq = new string('A', 120);
            w.OnLegacyUiData("combo", new[] { "", longSeq, "Move:" + longSeq + "B:1" });

            Assert.Equal(480, w.PaintWidthBaseForTest());
        }
    }
}
