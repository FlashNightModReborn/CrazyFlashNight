using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelHostSkillInstanceTests
    {
        [Fact]
        public void OpenPayload_OverwritesUntrustedInstanceInTopAndInitData()
        {
            string json = PanelHostController.BuildPanelOpenPayload("skills",
                "{\"view\":\"manage\",\"panelInstanceId\":\"web.supplied\"}", "host.instance.9");
            JObject payload = JObject.Parse(json);
            Assert.Equal("host.instance.9", (string)payload["panelInstanceId"]);
            Assert.Equal("host.instance.9", (string)payload["initData"]["panelInstanceId"]);
            Assert.Equal("manage", (string)payload["initData"]["view"]);
        }

        [Theory]
        [InlineData("map", "panel.map.1", false)]
        [InlineData("skills", null, false)]
        [InlineData("skills", "panel.skills.1", true)]
        public void SkillsDomainRoute_RequiresActiveSkillsPanelAndInstance(string panel, string instance, bool expected)
        {
            Assert.Equal(expected, WebOverlayForm.IsActiveSkillPanel(panel, instance));
        }

        [Fact]
        public void SwitchManageEnvelope_RequiresExactInstanceAndNestedPresentationPayload()
        {
            JObject valid = JObject.Parse(@"{
                'type':'panel','panel':'skills','cmd':'switch_manage','panelInstanceId':'panel.skills.2',
                'payload':{'v':1,'focusSkillKey':'闪现'}
            }");
            Assert.True(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.2"));
            Assert.False(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.old"));

            valid["focusSkillKey"] = "顶层字段不允许";
            Assert.False(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.2"));
            valid.Remove("focusSkillKey");
            valid["payload"]["extra"] = true;
            Assert.False(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.2"));
        }

        [Fact]
        public void SwitchTrainerEnvelope_RequiresExactManageInstanceAndSameNestedShape()
        {
            JObject valid = JObject.Parse(@"{
                'type':'panel','panel':'skills','cmd':'switch_trainer','panelInstanceId':'panel.skills.manage.3',
                'payload':{'v':1,'focusSkillKey':'闪现'}
            }");
            Assert.True(WebOverlayForm.IsValidSkillTrainerSwitchEnvelope(valid, "skills", "panel.skills.manage.3"));
            Assert.False(WebOverlayForm.IsValidSkillTrainerSwitchEnvelope(valid, "skills", "panel.skills.old"));
            Assert.False(WebOverlayForm.IsValidSkillManageSwitchEnvelope(valid, "skills", "panel.skills.manage.3"));

            valid["payload"]["trainerSession"] = "web.must.not.receive.this";
            Assert.False(WebOverlayForm.IsValidSkillTrainerSwitchEnvelope(valid, "skills", "panel.skills.manage.3"));
        }
    }
}
