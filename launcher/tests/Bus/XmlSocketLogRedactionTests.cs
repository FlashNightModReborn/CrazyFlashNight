using CF7Launcher.Bus;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public sealed class XmlSocketLogRedactionTests
    {
        [Fact]
        public void LootResponseLog_RedactsIdentityAndRewards()
        {
            const string message = "{\"task\":\"loot_response\",\"chestSessionId\":\"chest.secret\","
                + "\"lootContainerId\":\"container.secret\",\"reward\":\"reward.secret\"}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=loot_response payload=redacted len="
                + message.Length, line);
            Assert.DoesNotContain("chest.secret", line);
            Assert.DoesNotContain("container.secret", line);
            Assert.DoesNotContain("reward.secret", line);
        }

        [Fact]
        public void LootPanelRequestLog_RedactsRealCallbackEnvelope()
        {
            const string message = "{\"task\":\"panel_request\",\"payload\":{\"panel\":\"loot\","
                + "\"source\":\"source.secret\",\"initData\":{\"v\":1,"
                + "\"chestSessionId\":\"chest.secret\","
                + "\"lootContainerId\":\"container.secret\",\"containerEpoch\":73,"
                + "\"openAttemptSeq\":91,\"displayName\":\"reward.secret\","
                + "\"capacity\":8,\"columns\":4}},\"callId\":17}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=panel_request panel=loot payload=redacted len="
                + message.Length, line);
            Assert.DoesNotContain("chestSessionId", line);
            Assert.DoesNotContain("lootContainerId", line);
            Assert.DoesNotContain("containerEpoch", line);
            Assert.DoesNotContain("openAttemptSeq", line);
            Assert.DoesNotContain("source", line);
            Assert.DoesNotContain("initData", line);
            Assert.DoesNotContain("chest.secret", line);
            Assert.DoesNotContain("container.secret", line);
            Assert.DoesNotContain("source.secret", line);
            Assert.DoesNotContain("reward.secret", line);
        }

        [Fact]
        public void LootPanelRequestLog_RedactsLegacyRootEnvelope()
        {
            const string message = "{\"task\":\"panel_request\",\"panel\":\"loot\","
                + "\"initData\":{\"chestSessionId\":\"legacy.secret\"}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=panel_request panel=loot payload=redacted len="
                + message.Length, line);
            Assert.DoesNotContain("legacy.secret", line);
        }

        [Fact]
        public void MalformedShortLootResponseLog_DoesNotFallBackToRawPayload()
        {
            const string message = "{\"task\" : \"loot_response\","
                + "\"chestSessionId\":\"chest.secret\","
                + "\"closeLease\":\"lease.secret\",\"reward\":\"reward.secret\"";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=loot_response payload=redacted len="
                + message.Length, line);
            Assert.DoesNotContain("chest.secret", line);
            Assert.DoesNotContain("lease.secret", line);
            Assert.DoesNotContain("reward.secret", line);
        }

        [Fact]
        public void TruncatedLongLootResponseLog_DoesNotExposeFirst120Characters()
        {
            string message = "{\"task\":\"loot_response\","
                + "\"chestSessionId\":\"chest.secret\","
                + "\"closeLease\":\"lease.secret\",\"reward\":\"reward.secret\","
                + "\"padding\":\"" + new string('x', 600);

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.True(message.Length >= 500);
            Assert.Equal("[XmlSocket:JSON] task=loot_response payload=redacted len="
                + message.Length, line);
            Assert.DoesNotContain("chest.secret", line);
            Assert.DoesNotContain("lease.secret", line);
            Assert.DoesNotContain("reward.secret", line);
        }

        [Fact]
        public void MalformedShortLootPanelRequestLog_DoesNotFallBackToRawPayload()
        {
            const string message = "{\"task\":\"panel_request\",\"payload\":{"
                + "\"panel\" : \"loot\",\"initData\":{"
                + "\"chestSessionId\":\"chest.secret\","
                + "\"closeLease\":\"lease.secret\",\"reward\":\"reward.secret\"}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=panel_request panel=loot payload=redacted len="
                + message.Length, line);
            Assert.DoesNotContain("chest.secret", line);
            Assert.DoesNotContain("lease.secret", line);
            Assert.DoesNotContain("reward.secret", line);
        }

        [Fact]
        public void TruncatedLongLootPanelRequestLog_DoesNotExposeFirst120Characters()
        {
            string message = "{\"task\":\"panel_request\",\"payload\":{"
                + "\"panel\":\"loot\",\"initData\":{"
                + "\"chestSessionId\":\"chest.secret\","
                + "\"closeLease\":\"lease.secret\",\"reward\":\"reward.secret\","
                + "\"padding\":\"" + new string('x', 600);

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.True(message.Length >= 500);
            Assert.Equal("[XmlSocket:JSON] task=panel_request panel=loot payload=redacted len="
                + message.Length, line);
            Assert.DoesNotContain("chest.secret", line);
            Assert.DoesNotContain("lease.secret", line);
            Assert.DoesNotContain("reward.secret", line);
        }

        [Fact]
        public void OrdinaryPanelRequestLog_PreservesLegacyFormat()
        {
            const string message = "{\"task\":\"panel_request\",\"payload\":{\"panel\":\"map\","
                + "\"source\":\"native_hud\",\"initData\":{\"view\":\"world\"}},\"callId\":18}";

            Assert.Equal("[XmlSocket:JSON] " + message,
                XmlSocketServer.FormatJsonMessageLog(message));
        }

        [Fact]
        public void NonPanelTaskWithLootShapedPayload_PreservesLegacyFormat()
        {
            const string message = "{\"task\":\"ping\",\"payload\":{\"panel\":\"loot\","
                + "\"source\":\"diagnostic\"}}";

            Assert.Equal("[XmlSocket:JSON] " + message,
                XmlSocketServer.FormatJsonMessageLog(message));
        }

        [Fact]
        public void NonLootJsonLog_PreservesLegacyFormat()
        {
            const string message = "{\"task\":\"ping\",\"value\":1}";

            Assert.Equal("[XmlSocket:JSON] " + message,
                XmlSocketServer.FormatJsonMessageLog(message));
        }
    }
}
