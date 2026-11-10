using System;
using CF7Launcher.Bus;
using Xunit;

namespace Launcher.Tests.Bus
{
    public sealed class QualificationConsolePolicyTests
    {
        [Theory]
        [InlineData("cf7_agent_review1110")]
        [InlineData("cf7_agent_i2051110")]
        public void FixedCommandsRoundTripUtf8ForTheTwoQualificationSlots(string slot)
        {
            foreach (string command in new[] {
                "#get:savePath", QualificationConsolePolicy.PlayerProbe, QualificationConsolePolicy.SceneProbe, QualificationConsolePolicy.CoreProbe,
                "#_root.当前关卡名=尸母巢穴", "#_root.关卡类型=无限过图",
                "#_root.关卡路径=data/stages/诺亚前线基地深处/尸母巢穴.xml",
                "#_root.淡出跳转帧=wuxianguotu_1",
                "#func:_root.选关界面进入关卡(简单)", "#func:_root.返回基地()",
                "#func:_root.书中调试(1110,10,cf6-sting,historical)1:int2:int",
                "#func:_root.书中调试(1110,13,cf6-sting,type61)1:int2:int" })
            {
                Assert.True(QualificationConsolePolicy.TryApprove(slot, command, out var encoded));
                Assert.All(encoded, c => Assert.InRange((int)c, 0, 127));
                Assert.Equal(command, Uri.UnescapeDataString(encoded));
            }
        }
        [Theory]
        [InlineData("cf7_agent_152_a28", "#get:savePath")]
        [InlineData("cf7_agent_i2051110_near", "#get:savePath")]
        [InlineData("cf7_agent_review1110", "#give:复活币,100")]
        [InlineData("cf7_agent_review1110", "#set:等级=99")]
        [InlineData("cf7_agent_review1110", "#_root.当前关卡名=其他关卡")]
        [InlineData("cf7_agent_review1110", "#_root.淡出跳转帧=1")]
        [InlineData("cf7_agent_review1110", "#eval:hero.hp = 1")]
        [InlineData("cf7_agent_review1110", "#func:_root.书中调试(1110,9,cf6-sting,historical)1:int2:int")]
        [InlineData("cf7_agent_review1110", "#func:_root.书中调试(1,10,cf6-sting,historical)1:int2:int")]
        public void NoArbitraryCheatOrOtherSlotIsAdmitted(string slot, string command) =>
            Assert.False(QualificationConsolePolicy.TryApprove(slot, command, out _));
    }
}
