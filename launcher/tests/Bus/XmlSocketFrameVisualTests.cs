using CF7Launcher.Bus;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public sealed class XmlSocketFrameVisualTests
    {
        [Fact]
        public void VisualSectionAfterInputLeavesExistingFrameSegmentsIntact()
        {
            string oldFrame = "F1|2|1\x01\x02\x03ui:1\x04" + "4|1|2|3";
            Assert.Equal(oldFrame, XmlSocketServer.SplitFrameVisualSection(oldFrame, out string absent));
            Assert.Null(absent);
            string wire = oldFrame + "\x05" + "2|120|0|1|0;0,10,20,0,100,100,100";
            Assert.Equal(oldFrame, XmlSocketServer.SplitFrameVisualSection(wire, out string visual));
            Assert.Equal("2|120|0|1|0;0,10,20,0,100,100,100", visual);
            Assert.Equal("4|1|2|3", oldFrame.Substring(oldFrame.IndexOf('\x04') + 1));
        }
    }
}
