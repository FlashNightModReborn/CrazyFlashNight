using System;
using System.Collections.Generic;
using System.Drawing;
using System.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Dialogue;
using Xunit;
using Xunit.Abstractions;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// G0-4：Native 正文框可见容量实测。
    ///
    /// 不走真实游戏（P0 不做游戏内运行），但走**生产排版链路**：
    /// <see cref="NativeDialogueWidget"/> 的同一份皮肤字段（正文 573×72.65、字号 12、
    /// 行高 1.2em、首行缩进 6）、同一套 GDI+ 字体与 MeasureString 字符宽、
    /// 同一个 <see cref="NativeDialogueTextLayout"/> 贪心折行。
    /// 段宽按 TextLocalWidth 反算（与 EnsurePlanLocked 完全一致），与 viewport/DPR 无关
    /// （正文排版在局部文字空间完成，控件再整体变换）。
    ///
    /// 容量定义：不触发滚动、不裁切 = 折行行数 ≤ BodyCapacityLines（PaintBody 的裁剪高度）。
    /// </summary>
    public sealed class NativeDialogueBodyCapacityTests
    {
        private readonly ITestOutputHelper _output;

        public NativeDialogueBodyCapacityTests(ITestOutputHelper output)
        {
            _output = output;
        }

        private static NativeDialogueWidget NewWidget(Control anchor)
        {
            return new NativeDialogueWidget(anchor);
        }

        private static void ShowText(NativeDialogueWidget widget, string text)
        {
            widget.ShowFrame(new NativeDialogueFrame
            {
                RequestId = "nd:1",
                SceneId = "scene.capacity",
                Revision = 1,
                LineIndex = 0,
                LineCount = 1,
                Name = "Andy Law",
                Title = "雇佣兵",
                Text = text,
                PortraitKey = "",
                Expression = "普通",
                ImageAction = "keep",
                ImagePath = ""
            });
        }

        /// <summary>二分：最长多少字仍能在不滚动的前提下完整显示。</summary>
        private static int MeasureCapacity(NativeDialogueWidget widget, Func<int, string> build)
        {
            int capacityLines = widget.BodyCapacityLines;
            int lo = 0, hi = 600;
            while (lo < hi)
            {
                int mid = (lo + hi + 1) / 2;
                ShowText(widget, build(mid));
                if (widget.PlanLineCountForTest <= capacityLines) lo = mid;
                else hi = mid - 1;
            }
            return lo;
        }

        [Fact]
        public void BodyCapacityMatchesProtocolEstimateWithinOneLine()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = NewWidget(anchor);

            int capacityLines = widget.BodyCapacityLines;
            Assert.Equal(5, capacityLines);      // 72.65 / (12 × 1.2) = 5 行

            // 纯中文（每个字全宽，最保守）
            int pureCjk = MeasureCapacity(widget, n => new string('字', n));
            // 代表性中文：长句 + 标点（逗号/顿号/句号；标点禁则会让行尾提前断）
            const string sample =
                "北边那条路前几天塌了，现在只能绕南边过去；南边的桥也不稳，晚上没人敢走。" +
                "你要是真打算去，先去货栈找老周，他知道一条旧路，不过那条路要穿过废楼。";
            int withPunct = MeasureCapacity(widget, n => BuildSample(sample, n));

            int charsPerLine = pureCjk / capacityLines;
            _output.WriteLine("capacityLines=" + capacityLines);
            _output.WriteLine("pureCjk=" + pureCjk + " (charsPerLine=" + charsPerLine + ")");
            _output.WriteLine("withPunct=" + withPunct);
            _output.WriteLine("85%=" + (int)Math.Floor(pureCjk * 0.85) + " 70%=" + (int)Math.Floor(pureCjk * 0.70));

            // 结构调整时先失效，避免容量悄悄漂移：协议估算 195，允许 ±1 行（≈39 字）偏差。
            Assert.InRange(pureCjk, 195 - charsPerLine, 195 + charsPerLine);
            Assert.True(withPunct > 0);
            Assert.True(withPunct <= pureCjk);   // 标点禁则只会更早断行，不会更宽

            // 边界：正好容量可容纳；多一个字必须折到第 6 行（触发滚动）
            ShowText(widget, new string('字', pureCjk));
            Assert.True(widget.PlanLineCountForTest <= capacityLines);
            ShowText(widget, new string('字', pureCjk + 1));
            Assert.True(widget.PlanLineCountForTest > capacityLines);
        }

        private static string BuildSample(string sample, int length)
        {
            if (length <= 0) return "";
            var sb = new StringBuilder(length);
            for (int i = 0; i < length; i++) sb.Append(sample[i % sample.Length]);
            return sb.ToString();
        }
    }
}
