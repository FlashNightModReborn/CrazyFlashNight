using CF7Launcher.Bus;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public sealed class XmlSocketFrameVisualTests
    {
        [Fact]
        public void CombatEventsDoNotLeakIntoBulletOrInputPayloads()
        {
            string oldFrame="F1|2|1\x01\x02\x03ui:1\x04"+"4|1|2|3";
            string bullet="2|120|0|1|0;0,10,20,0,100,100,100";
            string fx="2|120|120|0;m,18,10,20,100,100,0,123,0";
            string wire=oldFrame+"\x05"+bullet+"\x06"+fx;
            string beforeFx=XmlSocketServer.SplitFrameCombatFxSection(wire,out string actualFx);
            Assert.Equal(fx,actualFx);
            Assert.Equal(oldFrame,XmlSocketServer.SplitFrameVisualSection(beforeFx,out string actualBullet));
            Assert.Equal(bullet,actualBullet);
            Assert.Equal(oldFrame,XmlSocketServer.SplitFrameCombatFxSection(oldFrame,out string missing));
            Assert.Null(missing);
            Assert.Equal(oldFrame,XmlSocketServer.SplitFrameCombatFxSection(oldFrame+"\x06"+fx,out actualFx));
            Assert.Equal(fx,actualFx);
        }

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
