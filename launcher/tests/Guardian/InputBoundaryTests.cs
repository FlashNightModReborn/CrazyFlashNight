using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class InputBoundaryTests
    {
        [Fact]
        public void ControlCurrentEdgeOverridesPreEventAsyncStateAndSidesRemainIndependent()
        {
            Assert.True(KeyboardHook.ControlSideAfterEvent(0xA2, 0xA2, true, false));
            Assert.False(KeyboardHook.ControlSideAfterEvent(0xA2, 0xA2, false, true));
            Assert.True(KeyboardHook.ControlSideAfterEvent(0xA3, 0xA2, false, true));
            Assert.False(KeyboardHook.ControlSideAfterEvent(0xA2, 0x57, true, false));
            Assert.True(KeyboardHook.ControlSideAfterEvent(0xA3, 0x57, true, true));
        }

        [Theory]
        [InlineData(90u, 100u, false)]
        [InlineData(100u, 100u, false)]
        [InlineData(101u, 100u, true)]
        [InlineData(9000u, 100u, true)]
        [InlineData(10u, 4294967290u, true)]
        [InlineData(4294967290u, 10u, false)]
        public void QueueBoundaryRejectsOldAndAmbiguousEdgesWithoutAgeThreshold(uint message, uint boundary, bool expected)
        {
            Assert.Equal(expected, PointerInputBoundary.IsCurrent(message, boundary));
        }
    }
}
