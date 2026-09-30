using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class WorldLightSubmitBatchTests
    {
        [Fact]
        public void LatestBorrowedPictureIsPublishedOnceAtFrameEnd()
        {
            var rendered = new List<float>();
            var batch = new WorldLightSubmitBatch((frame, x, y, scale) => rendered.Add(frame.Data[0] + x));
            var draw = new CombatFxDrawFrame(1);
            batch.Begin(); draw.Data[0] = 1; batch.Submit(draw, 10, 0, 1, false);
            draw.Data[0] = 2; batch.Submit(draw, 20, 0, 1, true);
            Assert.Empty(rendered);
            batch.End(); Assert.Equal(new[] { 22f }, rendered);
        }

        [Fact]
        public void LifecycleClearPublishesImmediatelyAndCancelsQueuedPicture()
        {
            var rendered = new List<int>();
            var batch = new WorldLightSubmitBatch((frame, x, y, scale) => rendered.Add(frame.LightCount));
            batch.Begin(); batch.Submit(new CombatFxDrawFrame(1) { LightCount = 2 }, 0, 0, 1, true);
            batch.Submit(new CombatFxDrawFrame(1), 0, 0, 1, true, immediate: true);
            Assert.Equal(new[] { 0 }, rendered);
            batch.End(); Assert.Equal(new[] { 0 }, rendered);
        }

        [Fact]
        public void ForeignThreadUpdateCannotJoinOrReplayAnOlderBatch()
        {
            var rendered = new List<int>(); var gate = new object();
            var batch = new WorldLightSubmitBatch((frame, x, y, scale) => rendered.Add(frame.LightCount));
            lock (gate) { batch.Begin(); batch.Submit(new CombatFxDrawFrame(1) { LightCount = 1 }, 0, 0, 1, false); }
            Exception failed = null;
            var worker = new Thread(() => {
                try {
                    lock (gate) {
                        batch.Begin(); batch.Submit(new CombatFxDrawFrame(1) { LightCount = 3 }, 0, 0, 1, true); batch.End();
                    }
                } catch (Exception error) { failed = error; }
            });
            worker.Start(); Assert.True(worker.Join(TimeSpan.FromSeconds(5))); Assert.Null(failed);
            lock (gate) batch.End();
            Assert.Equal(new[] { 3 }, rendered);
        }

        [Fact]
        public void FailedFlushLeavesNoPendingReplayAndRetainsRayFaultClassification()
        {
            int calls = 0;
            var batch = new WorldLightSubmitBatch((frame, x, y, scale) => { if (++calls == 1) throw new InvalidOperationException(); });
            batch.Begin(); batch.Submit(new CombatFxDrawFrame(1), 0, 0, 1, true);
            Assert.Throws<InvalidOperationException>(() => batch.End()); Assert.True(batch.FailureWasRay);
            batch.Begin(); batch.End(); Assert.Equal(1, calls);
            batch.Begin(); batch.Submit(new CombatFxDrawFrame(1), 0, 0, 1, false); batch.End();
            Assert.Equal(2, calls); Assert.False(batch.FailureWasRay);
        }
    }
}
