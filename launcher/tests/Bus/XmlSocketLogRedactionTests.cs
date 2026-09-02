using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public sealed class XmlSocketLogRedactionTests
    {
        [Fact]
        public void EquipmentTuningResponseLog_RedactsShortPayloadAndKeepsOnlySafeMetadata()
        {
            const string message = "{\"task\":\"equipment_tuning_response\","
                + "\"callId\":\"call.secret\\r\\n[forged]\",\"command\":\"commit\","
                + "\"success\":true,\"tuningToken\":\"token.secret\","
                + "\"transactionId\":\"transaction.secret\","
                + "\"snapshot\":{\"equipment\":\"snapshot.secret\"}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.StartsWith("[XmlSocket:JSON] task=equipment_tuning_response command=commit"
                + " callId=other success=true payload=redacted len=" + message.Length,
                line);
            Assert.Contains(" tuningTokenRef="
                + AuthorityLogFormatter.CreateReference("token.secret"), line);
            Assert.Contains(" transactionIdRef="
                + AuthorityLogFormatter.CreateReference("transaction.secret"), line);
            AssertEquipmentTuningSecretsAbsent(line);
        }

        [Fact]
        public void EquipmentTuningResponseLog_RedactsLongPayloadWithoutPrefixSampling()
        {
            string message = "{\"task\":\"equipment_tuning_response\","
                + "\"callId\":91,\"command\":\"snapshot\",\"success\":false,"
                + "\"tuningToken\":\"token.secret\",\"transactionId\":\"transaction.secret\","
                + "\"snapshot\":{\"equipment\":\"snapshot.secret\",\"padding\":\""
                + new string('x', 600) + "\"}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.True(message.Length >= 500);
            Assert.StartsWith("[XmlSocket:JSON] task=equipment_tuning_response command=snapshot"
                + " callId=91 success=false payload=redacted len=" + message.Length,
                line);
            Assert.Contains(" tuningTokenRef="
                + AuthorityLogFormatter.CreateReference("token.secret"), line);
            Assert.Contains(" transactionIdRef="
                + AuthorityLogFormatter.CreateReference("transaction.secret"), line);
            AssertEquipmentTuningSecretsAbsent(line);
            Assert.DoesNotContain(new string('x', 20), line);
        }

        [Fact]
        public void MalformedEquipmentTuningResponseLog_FailsClosedBeforeRawFallback()
        {
            const string message = "{\"task\" : \"equipment_tuning_response\","
                + "\"callId\":17,\"command\":\"preview\",\"success\":true,"
                + "\"tuningToken\":\"token.secret\",\"transactionId\":\"transaction.secret\","
                + "\"snapshot\":{\"equipment\":\"snapshot.secret\"}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=equipment_tuning_response_family"
                + " envelope=malformed payload=redacted len=" + message.Length, line);
            AssertEquipmentTuningSecretsAbsent(line);
        }

        [Fact]
        public void MalformedLongEquipmentTuningResponseLog_DoesNotExposePrefixSample()
        {
            string message = "{\"task\":\"equipment_tuning_response\","
                + "\"tuningToken\":\"token.secret\",\"transactionId\":\"transaction.secret\","
                + "\"snapshot\":{\"equipment\":\"snapshot.secret\",\"padding\":\""
                + new string('x', 600);

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.True(message.Length >= 500);
            Assert.Equal("[XmlSocket:JSON] task=equipment_tuning_response_family"
                + " envelope=malformed payload=redacted len=" + message.Length, line);
            AssertEquipmentTuningSecretsAbsent(line);
            Assert.DoesNotContain(new string('x', 20), line);
        }

        [Theory]
        [InlineData("equipment_tuning_response_v2")]
        [InlineData("EQUIPMENT_TUNING_RESPONSE")]
        [InlineData("equipment_tuning_respons")]
        [InlineData("equipment_tuning_\\r\\n[forged]")]
        public void NearMatchEquipmentTuningTaskLog_FailsClosedWithoutChangingRouting(
            string task)
        {
            string message = "{\"task\":\"" + task + "\","
                + "\"command\":\"preview\",\"success\":true,"
                + "\"tuningToken\":\"token.secret\",\"transactionId\":\"transaction.secret\","
                + "\"snapshot\":{\"equipment\":\"snapshot.secret\"}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=equipment_tuning_response_family"
                + " envelope=near_match payload=redacted len=" + message.Length, line);
            AssertEquipmentTuningSecretsAbsent(line);
            Assert.DoesNotContain("forged", line);
            Assert.DoesNotContain("\r", line);
            Assert.DoesNotContain("\n", line);
        }

        [Theory]
        [InlineData("{\"task\":\"equipment_tuning_response\",\"task\":\"ping\",")]
        [InlineData("{\"task\":\"ping\",\"task\":\"equipment_tuning_response\",")]
        public void DuplicateTaskEquipmentTuningLog_CannotBypassRedaction(string prefix)
        {
            string message = prefix
                + "\"command\":\"commit\",\"success\":true,"
                + "\"tuningToken\":\"token.secret\",\"transactionId\":\"transaction.secret\","
                + "\"snapshot\":{\"equipment\":\"snapshot.secret\"}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=equipment_tuning_response_family"
                + " envelope=malformed payload=redacted len=" + message.Length, line);
            AssertEquipmentTuningSecretsAbsent(line);
        }

        [Fact]
        public void EscapedDuplicateTaskKey_CannotBypassMalformedRedaction()
        {
            const string message = "{\"task\":\"ping\",\"\\u0074ask\":"
                + "\"equipment_tuning_response\",\"command\":\"commit\","
                + "\"tuningToken\":\"token.secret\","
                + "\"transactionId\":\"transaction.secret\","
                + "\"snapshot\":{\"equipment\":\"snapshot.secret\"}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] envelope=malformed payload=redacted len="
                + message.Length, line);
            AssertEquipmentTuningSecretsAbsent(line);
        }

        [Fact]
        public void OrdinaryMalformedJson_NeverFallsBackToRawOrPrefixLogging()
        {
            const string message = "{\"task\":\"ping\",\"diagnostic\":\"secret.value\"";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] envelope=malformed payload=redacted len="
                + message.Length, line);
            Assert.DoesNotContain("secret.value", line);
        }

        [Fact]
        public void EquipmentTuningResponseLog_RejectsUntrustedMetadataFromSummary()
        {
            string callId = "call.secret" + new string('c', 600) + "\\r\\n[forged]";
            string command = "preview" + new string('p', 600) + "\\r\\n[forged]";
            string message = "{\"task\":\"equipment_tuning_response\","
                + "\"callId\":\"" + callId + "\","
                + "\"command\":\"" + command + "\","
                + "\"success\":\"true\\r\\n[forged]\","
                + "\"tuningToken\":\"token.secret\",\"transactionId\":\"transaction.secret\","
                + "\"snapshot\":{\"equipment\":\"snapshot.secret\"}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.StartsWith("[XmlSocket:JSON] task=equipment_tuning_response command=other"
                + " callId=other success=unknown payload=redacted len=" + message.Length,
                line);
            AssertEquipmentTuningSecretsAbsent(line);
            Assert.DoesNotContain("forged", line);
            Assert.DoesNotContain("\r", line);
            Assert.DoesNotContain("\n", line);
            Assert.DoesNotContain(new string('c', 20), line);
            Assert.DoesNotContain(new string('p', 20), line);
        }

        [Fact]
        public void LoadoutCandidatesResponseLog_KeepsRoutingAndRedactsCandidateAuthority()
        {
            const string lease = "lease.character.secret";
            const string itemName = "candidate.item.secret";
            string message = "{\"task\":\"loadout_response\",\"command\":\"candidates\","
                + "\"callId\":7,\"success\":true,\"payload\":{\"candidates\":[{"
                + "\"item\":{\"name\":\"" + itemName + "\"},\"source\":{"
                + "\"expectedLease\":\"" + lease + "\"}}]}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.StartsWith("[XmlSocket:JSON] task=loadout_response cmd=candidates"
                + " callId=7 success=true payload=redacted len=" + message.Length,
                line);
            Assert.Contains(AuthorityLogFormatter.CreateReference(lease), line);
            Assert.DoesNotContain(lease, line);
            Assert.DoesNotContain(itemName, line);
        }

        [Fact]
        public void ItemUseResponseLog_RedactsOperationAndRewardAuthority()
        {
            const string operationId = "itemuse.operation.secret";
            const string chestSessionId = "reward.chest.secret";
            string message = "{\"task\":\"item_use_response\",\"command\":\"open\","
                + "\"callId\":9,\"success\":true,\"operationId\":\""
                + operationId + "\",\"rewardAuthority\":{\"sourceKind\":\"reward_inbox\","
                + "\"chestSessionId\":\"" + chestSessionId + "\"}}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.StartsWith(
                "[XmlSocket:JSON] task=item_use_response cmd=open"
                + " callId=9 success=true payload=redacted len=" + message.Length,
                line);
            Assert.DoesNotContain(operationId, line);
            Assert.DoesNotContain(chestSessionId, line);
        }

        [Fact]
        public void NearMatchLoadoutResponseLog_FailsClosed()
        {
            const string lease = "lease.near-match.secret";
            string message = "{\"task\":\"loadout_response_v2\","
                + "\"command\":\"candidates\",\"success\":true,"
                + "\"expectedLease\":\"" + lease + "\"}";

            string line = XmlSocketServer.FormatJsonMessageLog(message);

            Assert.Equal("[XmlSocket:JSON] task=authority_response_family"
                + " envelope=near_match payload=redacted len=" + message.Length,
                line);
            Assert.DoesNotContain(lease, line);
        }

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

        private static void AssertEquipmentTuningSecretsAbsent(string line)
        {
            Assert.DoesNotContain("call.secret", line);
            Assert.DoesNotContain("\"tuningToken\"", line);
            Assert.DoesNotContain("token.secret", line);
            Assert.DoesNotContain("\"transactionId\"", line);
            Assert.DoesNotContain("transaction.secret", line);
            Assert.DoesNotContain("\"snapshot\"", line);
            Assert.DoesNotContain("snapshot.secret", line);
        }
    }
}
