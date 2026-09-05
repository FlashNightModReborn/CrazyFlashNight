using System;
using System.Drawing;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class SaveFeedbackStateTests
    {
        [Fact]
        public void CompletedSave_UsesFourRepaintsThenStopsEvenWithFrequentTicks()
        {
            long now = 0;
            var state = new SaveFeedbackState(() => now);
            Assert.False(state.NeedsTick);
            int repaints = state.HandlePacket(new UiDataPacket("sv:1|sv:1|q:77|sv:2")) ? 1 : 0;
            Assert.Equal(SaveFeedbackVisual.SavedBright, state.Visual);
            Assert.Equal(1, state.CompletedSaveCount);
            for (now = 1; now <= 10000; now++)
                if (state.Tick()) repaints++;
            Assert.Equal(4, repaints);
            Assert.False(state.NeedsTick);
            Assert.Equal(SaveFeedbackVisual.None, state.Visual);
            Assert.Equal(1, state.CompletedSaveCount);
        }

        [Fact]
        public void BurstSaves_CoalescePresentationButCountEveryCompletedFlush()
        {
            long now = 0;
            var wall = new DateTime(2026, 9, 5, 12, 34, 56);
            var state = new SaveFeedbackState(() => now, () => wall);
            Assert.True(state.HandlePacket(new UiDataPacket("sv:1|sv:2")));
            for (now = 1; now < 100; now++)
                Assert.False(state.HandlePacket(new UiDataPacket("sv:1|sv:1|sv:2")));
            Assert.Equal(100, state.CompletedSaveCount);
            Assert.Equal(wall, state.LastSavedAt);
            Assert.Equal("已保存 12:34:56 · 100 次", state.Hint);
            now = 1250; // 最后一次成功后仍有短暂淡出，不逐个排队播放。
            Assert.Equal(SaveFeedbackVisual.SavedDim, state.Visual);
            now = 1300;
            Assert.True(state.Tick());
            Assert.False(state.NeedsTick);
        }

        [Fact]
        public void PendingAndFailure_AreStaticAndNeverCountAsCompleted()
        {
            var state = new SaveFeedbackState();
            Assert.True(state.HandlePacket(new UiDataPacket("sv:1")));
            Assert.Equal(SaveFeedbackVisual.Saving, state.Visual);
            Assert.Equal("正在存盘", state.Hint);
            Assert.False(state.NeedsTick);
            Assert.True(state.HandlePacket(new UiDataPacket("sv:3")));
            Assert.Equal(SaveFeedbackVisual.Unconfirmed, state.Visual);
            Assert.Equal("保存未确认，请重试", state.Hint);
            Assert.False(state.NeedsTick);
            Assert.Equal(0, state.CompletedSaveCount);
            Assert.Null(state.LastSavedAt);
            Assert.False(state.HandlePacket(new UiDataPacket("q:77|sv:invalid|sv:0|sv:4")));
            Assert.Equal(SaveFeedbackVisual.Unconfirmed, state.Visual);
            Assert.True(state.HandlePacket(new UiDataPacket("sv:1|sv:2")));
            Assert.Equal(1, state.CompletedSaveCount);
        }

        [Fact]
        public void HiddenHud_DoesNotReplayExpiredSuccessOnResume()
        {
            long now = 0;
            var state = new SaveFeedbackState(() => now);
            state.HandlePacket(new UiDataPacket("sv:2"));
            now = 60000; // Web 面板遮挡期间没有 Tick。
            Assert.Equal(SaveFeedbackVisual.None, state.Visual);
            Assert.True(state.Tick());
            Assert.False(state.NeedsTick);
            Assert.False(state.Tick());
            Assert.Contains("1 次", state.Hint);
        }

        [Fact]
        public void OrderedReadinessEvents_ResetSessionHistoryWithinSamePacket()
        {
            var state = new SaveFeedbackState();
            state.HandlePacket(new UiDataPacket("sv:1|sv:2|sv:1|sv:3"));
            Assert.Equal(1, state.CompletedSaveCount);
            Assert.Equal(SaveFeedbackVisual.Unconfirmed, state.Visual);
            state.HandlePacket(new UiDataPacket("s:0|s:1"));
            Assert.Equal(SaveFeedbackVisual.None, state.Visual);
            Assert.Equal(0, state.CompletedSaveCount);
            Assert.Empty(state.Hint);
            state.HandlePacket(new UiDataPacket("sv:2|s:0|s:1|sv:2"));
            Assert.Equal(1, state.CompletedSaveCount);
            Assert.Equal(SaveFeedbackVisual.SavedBright, state.Visual);
        }

        [Theory]
        [InlineData(0.5f)]
        [InlineData(1f)]
        [InlineData(1.5625f)]
        [InlineData(2f)]
        public void AccentPixels_StayInsideOriginalButtonAtEveryScale(float scale)
        {
            var button = new Rectangle(10, 10, (int)(34 * scale), (int)(32 * scale));
            using (var bitmap = new Bitmap(button.Right + 10, button.Bottom + 10))
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                foreach (SaveFeedbackVisual visual in Enum.GetValues<SaveFeedbackVisual>())
                {
                    graphics.Clear(Color.Transparent);
                    SaveFeedbackState.PaintAccent(graphics, button, scale, visual);
                    int painted = 0;
                    for (int y = 0; y < bitmap.Height; y++)
                        for (int x = 0; x < bitmap.Width; x++)
                        {
                            if (bitmap.GetPixel(x, y).A == 0) continue;
                            Assert.True(button.Contains(x, y), visual + " escaped button at " + scale);
                            painted++;
                        }
                    Assert.Equal(visual != SaveFeedbackVisual.None, painted > 0);
                }
            }
        }
    }
}
