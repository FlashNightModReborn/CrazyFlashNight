using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Dialogue;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// G1 依赖的最小事件：<c>LinePresented</c>（一句开始显示）与 <c>TypingFinished</c>
    /// （逐字显示完成/被补全）。D-10 的"每句开始显示即可输入"只认这两个时点。
    /// </summary>
    public sealed class NativeDialogueTypingEventsTests
    {
        private static NativeDialogueFrame Frame(string text, int revision)
        {
            return new NativeDialogueFrame
            {
                RequestId = "nd:3",
                SceneId = "scene.events",
                Revision = revision,
                LineIndex = revision - 1,
                LineCount = 3,
                Name = "Andy Law",
                Title = "雇佣兵",
                Text = text,
                PortraitKey = "",
                Expression = "普通",
                ImageAction = "keep",
                ImagePath = ""
            };
        }

        [Fact]
        public void LinePresentedFiresOncePerFrameAndTypingFinishedAfterCompletion()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            var presented = new List<string>();
            var finished = new List<string>();
            widget.LinePresented = f => presented.Add(f.Text);
            widget.TypingFinished = f => finished.Add(f.Text);

            Assert.True(widget.ShowFrame(Frame("第一句", 1)));
            Assert.Equal(new[] { "第一句" }, presented);
            Assert.Empty(finished);                    // 还没打字

            widget.Tick(5000);                         // 足够长：一次走完
            Assert.Equal(new[] { "第一句" }, finished);  // 只发一次

            widget.Tick(5000);
            Assert.Single(finished);                   // 同一帧不重复通知
        }

        [Fact]
        public void EmptyLineIsPresentedAndImmediatelyFinished()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            var presented = new List<string>();
            var finished = new List<string>();
            widget.LinePresented = f => presented.Add(f.Text ?? "");
            widget.TypingFinished = f => finished.Add(f.Text ?? "");

            Assert.True(widget.ShowFrame(Frame("", 1)));
            Assert.Single(presented);
            Assert.Single(finished);                   // 空正文＝零打字，立刻完成

            widget.Tick(100);
            Assert.Single(finished);
        }

        [Fact]
        public void CompleteCurrentLineTypingNotifiesWithoutAdvancing()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            var finished = new List<string>();
            widget.TypingFinished = f => finished.Add(f.Text);

            Assert.True(widget.ShowFrame(Frame("很长的一句话", 1)));
            Assert.True(widget.CompleteCurrentLineTyping());

            Assert.Equal(new[] { "很长的一句话" }, finished);
            Assert.Equal("很长的一句话", widget.CurrentFrame.Text);   // 不换句
            Assert.Equal(1, widget.CurrentFrame.Revision);
            Assert.True(widget.TypingCompleteForTest);
        }

        [Fact]
        public void NewFrameResetsTypingNotification()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeDialogueWidget(anchor);
            int finished = 0;
            widget.TypingFinished = _ => finished++;

            widget.ShowFrame(Frame("第一句", 1));
            widget.Tick(5000);
            Assert.Equal(1, finished);

            widget.ShowFrame(Frame("第二句", 2));
            widget.Tick(5000);
            Assert.Equal(2, finished);
        }
    }
}
