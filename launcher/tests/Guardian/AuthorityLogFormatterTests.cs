using System;
using System.Collections.Generic;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class AuthorityLogFormatterTests
    {
        [Theory]
        [InlineData("short.token")]
        [InlineData("long.token.abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            + "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")]
        public void PanelIngress_RedactsShortAndLongAuthorityValuesWithStableReference(
            string secret)
        {
            string json = "{\"type\":\"panel\",\"panel\":\"kshop\","
                + "\"domain\":\"inventory\",\"cmd\":\"checkoutCommit\","
                + "\"callId\":\"kshop.log.1\",\"payload\":{\"v\":1,"
                + "\"expectedCheckoutToken\":\"" + secret + "\"}}";

            string line = Capture(delegate
            {
                return WebOverlayForm.FormatPanelEnvelopeLog(
                    "checkoutCommit", json);
            });

            Assert.Contains("task=panel", line);
            Assert.Contains("cmd=checkoutCommit", line);
            Assert.Contains("callId=kshop.log.1", line);
            Assert.Contains("payload=redacted", line);
            Assert.Contains("expectedCheckoutTokenRef="
                + AuthorityLogFormatter.CreateReference(secret), line);
            Assert.DoesNotContain(secret, line);
        }

        [Fact]
        public void PanelIngress_KeyOrderDoesNotChangeAuthorityReference()
        {
            const string secret = "checkout.order.secret";
            string first = "{\"panel\":\"kshop\",\"cmd\":\"checkoutCommit\","
                + "\"callId\":\"order.1\",\"payload\":{"
                + "\"expectedCheckoutToken\":\"" + secret + "\",\"v\":1}}";
            string second = "{\"payload\":{\"v\":1,\"expectedCheckoutToken\":\""
                + secret + "\"},\"callId\":\"order.1\","
                + "\"cmd\":\"checkoutCommit\",\"panel\":\"kshop\"}";

            string expectedRef = AuthorityLogFormatter.CreateReference(secret);
            string firstLine = Capture(() =>
                WebOverlayForm.FormatPanelEnvelopeLog("checkoutCommit", first));
            string secondLine = Capture(() =>
                WebOverlayForm.FormatPanelEnvelopeLog("checkoutCommit", second));

            Assert.Contains("expectedCheckoutTokenRef=" + expectedRef, firstLine);
            Assert.Contains("expectedCheckoutTokenRef=" + expectedRef, secondLine);
            Assert.DoesNotContain(secret, firstLine);
            Assert.DoesNotContain(secret, secondLine);
        }

        [Fact]
        public void PanelIngress_EquipmentTuningDomainIsAlwaysAnAuthoritySurface()
        {
            const string json = "{\"panel\":\"diagnostic\","
                + "\"domain\":\"equipment_tuning\",\"cmd\":\"snapshot\","
                + "\"callId\":\"tune.domain.1\",\"payload\":{\"v\":1}}";

            string line = Capture(() =>
                WebOverlayForm.FormatPanelEnvelopeLog("snapshot", json));

            Assert.Contains("domain=equipment_tuning", line);
            Assert.Contains("payload=redacted", line);
            Assert.DoesNotContain(json, line);
        }

        [Theory]
        [InlineData("{\"panel\":\"kshop\",\"cmd\":\"checkoutCommit\","
            + "\"payload\":{\"expectedCheckoutToken\":\"first.secret\","
            + "\"expectedCheckoutToken\":\"second.secret\"}}")]
        [InlineData("{\"panel\":\"kshop\",\"cmd\":\"checkoutCommit\","
            + "\"payload\":{\"expectedCheckoutToken\":\"truncated.secret\"}")]
        [InlineData("{\"panel\":\"kshop_v2\",\"cmd\":\"checkoutCommit\","
            + "\"payload\":{\"expectedCheckoutToken\":\"near.secret\"}}")]
        public void PanelIngress_DuplicateMalformedAndNearMatchNeverLogRawEnvelope(
            string json)
        {
            string line = Capture(() =>
                WebOverlayForm.FormatPanelEnvelopeLog("checkoutCommit", json));

            Assert.Contains("payload=redacted", line);
            Assert.DoesNotContain("first.secret", line);
            Assert.DoesNotContain("second.secret", line);
            Assert.DoesNotContain("truncated.secret", line);
            Assert.DoesNotContain("near.secret", line);
        }

        [Fact]
        public void PanelIngress_EscapedDuplicateSensitiveKeyFailsClosed()
        {
            const string json = "{\"panel\":\"kshop\",\"cmd\":\"checkoutCommit\","
                + "\"payload\":{\"expectedCheckoutToken\":\"plain.secret\","
                + "\"expectedCheckout\\u0054oken\":\"escaped.secret\"}}";

            string line = Capture(() =>
                WebOverlayForm.FormatPanelEnvelopeLog("checkoutCommit", json));

            Assert.Contains("envelope=malformed", line);
            Assert.Contains("payload=redacted", line);
            Assert.DoesNotContain("plain.secret", line);
            Assert.DoesNotContain("escaped.secret", line);
        }

        [Theory]
        [InlineData("ShopTask", "shopCheckoutCommit", "expectedCheckoutToken",
            "checkout.flash.secret")]
        [InlineData("CraftingTask", "craftingCommit", "expectedCraftToken",
            "craft.flash.secret")]
        [InlineData("NpcShopTask", "npcShopTradeCommit", "expectedTradeToken",
            "trade.flash.secret")]
        [InlineData("InventoryTask", "inventoryMove", "expectedLease",
            "inventory.lease.secret")]
        [InlineData("SkillTask", "skillLearnCommit", "expectedLearnToken",
            "skill.learn.secret")]
        public void FlashCommandLogs_KeepRoutingSummaryAndDeterministicTokenReference(
            string component,
            string action,
            string tokenKey,
            string secret)
        {
            var command = new JObject
            {
                ["task"] = "cmd",
                ["action"] = action,
                ["callId"] = 17,
                [tokenKey] = secret
            };

            string line = Capture(() =>
                AuthorityLogFormatter.FormatFlashCommand(component, command));

            Assert.Contains("[" + component + "] -> Flash:", line);
            Assert.Contains("task=cmd", line);
            Assert.Contains("cmd=" + action, line);
            Assert.Contains("callId=17", line);
            Assert.Contains(tokenKey + "Ref="
                + AuthorityLogFormatter.CreateReference(secret), line);
            Assert.DoesNotContain(secret, line);
        }

        [Theory]
        [InlineData("shop_response", "checkoutToken", "checkout.response.secret")]
        [InlineData("crafting_response", "craftToken", "craft.response.secret")]
        [InlineData("npcshop_response", "tradeToken", "trade.response.secret")]
        public void XmlSocketResponseFamilies_RedactBeforeTaskValidation(
            string task,
            string tokenKey,
            string secret)
        {
            string json = "{\"task\":\"" + task + "\",\"callId\":23,"
                + "\"success\":true,\"" + tokenKey + "\":\"" + secret + "\"}";

            string line = Capture(() =>
                XmlSocketServer.FormatJsonMessageLog(json));

            Assert.Contains("task=" + task, line);
            Assert.Contains("callId=23", line);
            Assert.Contains("success=true", line);
            Assert.Contains(tokenKey + "Ref="
                + AuthorityLogFormatter.CreateReference(secret), line);
            Assert.DoesNotContain(secret, line);
        }

        [Fact]
        public void MaterialShopAuthorityLogs_RetainOnlyExactRoutingMetadata()
        {
            const string material = "战术握把";
            const string shop = "迷之盔甲君";
            const string snapshot = "materials.snapshot.42";
            var command = new JObject
            {
                ["task"] = "cmd",
                ["action"] = "craftingMaterialShopAuthorize",
                ["callId"] = 41,
                ["v"] = 1,
                ["materialSnapshotId"] = snapshot,
                ["materialName"] = material,
                ["shopId"] = shop,
                ["catalogIndex"] = 57
            };
            string response = new JObject
            {
                ["task"] = "material_shop_access_response",
                ["callId"] = 41,
                ["success"] = true,
                ["v"] = 1,
                ["decision"] = "allow",
                ["reason"] = "indexed_live_match",
                ["materialSnapshotId"] = snapshot,
                ["materialName"] = material,
                ["shopId"] = shop,
                ["catalogIndex"] = 57,
                ["itemName"] = material
            }.ToString(Newtonsoft.Json.Formatting.None);

            string commandLine = Capture(() =>
                AuthorityLogFormatter.FormatFlashCommand(
                    "MaterialShopAccessTask",
                    command));
            string responseLine = Capture(() =>
                XmlSocketServer.FormatJsonMessageLog(response));

            Assert.Contains("[MaterialShopAccessTask] -> Flash:", commandLine);
            Assert.Contains("cmd=craftingMaterialShopAuthorize", commandLine);
            Assert.Contains("callId=41", commandLine);
            Assert.Contains("task=material_shop_access_response", responseLine);
            Assert.Contains("callId=41", responseLine);
            Assert.Contains("success=true", responseLine);
            Assert.Contains("payload=redacted", responseLine);
            foreach (string privateValue in new[] { material, shop, snapshot })
            {
                Assert.DoesNotContain(privateValue, commandLine);
                Assert.DoesNotContain(privateValue, responseLine);
            }
        }

        [Theory]
        [InlineData("shop_response_v2")]
        [InlineData("CRAFTING_RESPONSE")]
        [InlineData("npcshop_respons")]
        [InlineData("material_shop_access_response_v2")]
        public void XmlSocketNearMatchResponseFamiliesFailClosed(string task)
        {
            const string secret = "near.response.secret";
            string json = "{\"task\":\"" + task + "\",\"callId\":29,"
                + "\"success\":true,\"mysteryToken\":\"" + secret + "\"}";

            string line = Capture(() =>
                XmlSocketServer.FormatJsonMessageLog(json));

            Assert.Contains("envelope=near_match", line);
            Assert.Contains("payload=redacted", line);
            Assert.DoesNotContain(secret, line);
        }

        [Fact]
        public void XmlSocketGenericUnknownTokenKeyUsesAnonymousReferenceNotRawKeyOrValue()
        {
            const string secret = "generic.token.secret";
            const string json = "{\"task\":\"ping\",\"callId\":31,\"success\":true,"
                + "\"vendorFutureToken\":\"generic.token.secret\"}";

            string line = Capture(() =>
                XmlSocketServer.FormatJsonMessageLog(json));

            Assert.Contains("task=other", line);
            Assert.Contains("unknownAuthorityFieldCount=1", line);
            Assert.Contains(AuthorityLogFormatter.CreateReference(secret), line);
            Assert.DoesNotContain("vendorFutureToken", line);
            Assert.DoesNotContain(secret, line);
        }

        [Theory]
        [InlineData("{\"task\":\"shop_response\",\"task\":\"ping\","
            + "\"checkoutToken\":\"duplicate.transport.secret\"}")]
        [InlineData("{\"task\":\"crafting_response\",\"craftToken\":"
            + "\"malformed.transport.secret\"")]
        [InlineData("{\"task\":\"ping\",\"mystery\\u0054oken\":"
            + "\"escaped.transport.secret\",\"mysteryToken\":\"second.secret\"}")]
        public void XmlSocketDuplicateEscapedAndMalformedInputsNeverReachRawFallback(
            string json)
        {
            string line = Capture(() =>
                XmlSocketServer.FormatJsonMessageLog(json));

            Assert.Contains("payload=redacted", line);
            Assert.DoesNotContain("duplicate.transport.secret", line);
            Assert.DoesNotContain("malformed.transport.secret", line);
            Assert.DoesNotContain("escaped.transport.secret", line);
            Assert.DoesNotContain("second.secret", line);
        }

        [Fact]
        public void DiagnosticProjection_RecursivelyRedactsLeaseTransactionAndUnknownAuthority()
        {
            const string lease = "nested.lease.secret";
            const string transaction = "nested.transaction.secret";
            const string capability = "future.capability.secret";
            var envelope = new JObject
            {
                ["task"] = "cmd",
                ["source"] = new JObject
                {
                    ["expectedLease"] = lease,
                    ["nested"] = new JArray
                    {
                        new JObject
                        {
                            ["transactionId"] = transaction,
                            ["vendorCapability"] = capability
                        }
                    }
                }
            };

            string line = Capture(() => AuthorityLogFormatter
                .SanitizeAuthorityEnvelope(envelope)
                .ToString(Newtonsoft.Json.Formatting.None));

            Assert.Contains("\"expectedLeaseRef\":\""
                + AuthorityLogFormatter.CreateReference(lease) + "\"", line);
            Assert.Contains("\"transactionIdRef\":\""
                + AuthorityLogFormatter.CreateReference(transaction) + "\"", line);
            Assert.Contains("\"unknownAuthorityFieldCount\":1", line);
            Assert.Contains(AuthorityLogFormatter.CreateReference(capability), line);
            Assert.DoesNotContain("vendorCapability", line);
            Assert.DoesNotContain(lease, line);
            Assert.DoesNotContain(transaction, line);
            Assert.DoesNotContain(capability, line);
        }

        [Theory]
        [InlineData("equipment_tuning")]
        [InlineData("equipment_tuning_v2")]
        public void EquipmentDebug_HashesSourceAndIntentKeys(string scope)
        {
            const string sourceKey = "inventory:背包:7:debug.lease.secret";
            const string intentKey = "convert:背包:8:debug.target.lease.secret";
            string json = new JObject
            {
                ["type"] = "debug",
                ["scope"] = scope,
                ["event"] = "preview_issued",
                ["cmd"] = "preview",
                ["webCallId"] = "tune.debug.1",
                ["sourceKey"] = sourceKey,
                ["intentKey"] = intentKey,
                ["tokenPresent"] = true
            }.ToString(Newtonsoft.Json.Formatting.None);

            string line;
            Assert.True(AuthorityLogFormatter.TryFormatEquipmentTuningDebug(
                json, out line));
            Assert.Contains("sourceKeyRef="
                + AuthorityLogFormatter.CreateReference(sourceKey), line);
            Assert.Contains("intentKeyRef="
                + AuthorityLogFormatter.CreateReference(intentKey), line);
            Assert.Contains("payload=redacted", line);
            Assert.DoesNotContain(sourceKey, line);
            Assert.DoesNotContain(intentKey, line);
            if (scope != "equipment_tuning")
                Assert.Contains("envelope=near_match", line);
        }

        [Theory]
        [InlineData("{\"scope\":\"equipment_tuning\",\"sourceKey\":\"malformed.debug.secret\"")]
        [InlineData("{\"scope\":\"equipment_tuning\",\"scope\":\"other\",\"sourceKey\":\"duplicate.debug.secret\"}")]
        public void EquipmentDebug_MalformedOrDuplicateEnvelopeFailsClosed(string json)
        {
            string line;
            Assert.True(AuthorityLogFormatter.TryFormatEquipmentTuningDebug(
                json, out line));
            Assert.Contains("envelope=malformed", line);
            Assert.Contains("payload=redacted", line);
            Assert.DoesNotContain("malformed.debug.secret", line);
            Assert.DoesNotContain("duplicate.debug.secret", line);
        }

        private static string Capture(Func<string> buildLine)
        {
            var lines = new List<string>();
            LogManager.SetSink(lines.Add);
            try
            {
                LogManager.Log(buildLine());
            }
            finally
            {
                LogManager.ResetSink();
            }
            return Assert.Single(lines);
        }
    }
}
