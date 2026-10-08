using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class FpsSampleFreshnessTests
    {
        [Fact]
        public void NoSampleAndExpiredSample_AreNeverPresentedAsCurrent()
        {
            double now = 0;
            var buffer = new FpsRingBuffer(8, () => now);
            Assert.False(buffer.HasFreshSample);
            buffer.Push(30);
            Assert.True(buffer.HasFreshSample);
            now = FpsRingBuffer.FreshSampleLimitMs;
            Assert.False(buffer.HasFreshSample);
            Assert.True(buffer.HasData);
            Assert.Equal(30f, buffer.Latest);
            buffer.Push(24);
            Assert.True(buffer.HasFreshSample);
            Assert.Equal(24f, buffer.Latest);
        }

        [Fact]
        public void SceneReset_PreservesHistoryButWaitsForANewMeasuredSample()
        {
            double now = 500;
            var buffer = new FpsRingBuffer(8, () => now);
            buffer.Push(30);
            buffer.NotifySceneReset();
            Assert.Equal(1, buffer.Count);
            Assert.False(buffer.HasFreshSample);
            buffer.Push(27);
            Assert.True(buffer.HasFreshSample);
            Assert.Equal(1, buffer.SamplesAfterReset);
        }
    }
}
