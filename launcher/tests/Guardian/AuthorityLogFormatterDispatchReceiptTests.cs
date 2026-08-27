using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class AuthorityLogFormatterDispatchReceiptTests
    {
        [Theory]
        [InlineData("EquipmentTuningTask", "equipment_tuning", "workbench", "snapshot", "equipmentTuningSnapshot", "view.session~1")]
        [InlineData("EquipmentTuningTask", "equipment_tuning", "workbench", "preview", "equipmentTuningPreview", "view.session~1")]
        [InlineData("EquipmentTuningTask", "equipment_tuning", "workbench", "commit", "equipmentTuningCommit", "view.session~1")]
        [InlineData("EquipmentTuningTask", "equipment_tuning", "workbench", "tooltip", "equipmentTuningTooltip", "view.session~1")]
        [InlineData("EquipmentTuningTask", "equipment_tuning", "workbench", "detach", "equipmentTuningDetach", "view.session~1")]
        [InlineData("ShopTask", "shop", "kshop", "bulkQuery", "shopBulkQuery", null)]
        [InlineData("ShopTask", "shop", "kshop", "tooltip", "shopTooltip", null)]
        [InlineData("ShopTask", "shop", "kshop", "saveCart", "shopSaveCart", null)]
        [InlineData("ShopTask", "shop", "kshop", "checkoutPreview", "shopCheckoutPreview", null)]
        [InlineData("ShopTask", "shop", "kshop", "checkoutCommit", "shopCheckoutCommit", null)]
        [InlineData("ShopTask", "shop", "kshop", "checkout", "shopCheckout", null)]
        [InlineData("ShopTask", "shop", "kshop", "claim", "shopClaim", null)]
        [InlineData("CraftingTask", "crafting", "crafting", "snapshot", "craftingSnapshot", null)]
        [InlineData("CraftingTask", "crafting", "crafting", "materials", "craftingMaterials", null)]
        [InlineData("CraftingTask", "crafting", "crafting", "materialDetail", "craftingMaterialDetail", null)]
        [InlineData("CraftingTask", "crafting", "crafting", "preview", "craftingPreview", null)]
        [InlineData("CraftingTask", "crafting", "crafting", "tooltip", "craftingTooltip", null)]
        [InlineData("CraftingTask", "crafting", "crafting", "commit", "craftingCommit", null)]
        [InlineData("NpcShopTask", "npcshop", "npcshop", "snapshot", "npcShopSnapshot", null)]
        [InlineData("NpcShopTask", "npcshop", "npcshop", "tooltip", "npcShopTooltip", null)]
        [InlineData("NpcShopTask", "npcshop", "npcshop", "batchPreview", "npcShopBatchPreview", null)]
        [InlineData("NpcShopTask", "npcshop", "npcshop", "tradePreview", "npcShopTradePreview", null)]
        [InlineData("NpcShopTask", "npcshop", "npcshop", "buy", "npcShopBuy", null)]
        [InlineData("NpcShopTask", "npcshop", "npcshop", "batchSell", "npcShopBatchSell", null)]
        [InlineData("NpcShopTask", "npcshop", "npcshop", "tradeCommit", "npcShopTradeCommit", null)]
        [InlineData("InventoryTask", "inventory", "workbench", "snapshot", "inventorySnapshot", null)]
        [InlineData("InventoryTask", "inventory", "kshop", "tooltip", "inventoryTooltip", null)]
        [InlineData("InventoryTask", "inventory", "npcshop", "discard", "inventoryDiscard", null)]
        [InlineData("InventoryTask", "inventory", "crafting", "move", "inventoryMove", null)]
        [InlineData("InventoryTask", "inventory", "loot", "merge", "inventoryMerge", null)]
        [InlineData("InventoryTask", "inventory", "workbench", "swap", "inventorySwap", null)]
        [InlineData("InventoryTask", "inventory", "kshop", "autoTransfer", "inventoryAutoTransfer", null)]
        [InlineData("InventoryTask", "inventory", "workbench", "autoTransferBatch", "inventoryAutoTransferBatch", null)]
        [InlineData("InventoryTask", "inventory", "workbench", "sortAndMerge", "inventorySortAndMerge", null)]
        [InlineData("SkillTask", "skills", "skills", "snapshot", "skillSnapshot", null)]
        [InlineData("SkillTask", "skills", "skills", "learnPreview", "skillLearnPreview", null)]
        [InlineData("SkillTask", "skills", "skills", "learnCommit", "skillLearnCommit", null)]
        [InlineData("SkillTask", "skills", "skills", "equip", "skillEquip", null)]
        [InlineData("SkillTask", "skills", "skills", "unequip", "skillUnequip", null)]
        [InlineData("SkillTask", "skills", "skills", "moveSlot", "skillMoveSlot", null)]
        [InlineData("SkillTask", "skills", "skills", "setPassive", "skillSetPassive", null)]
        [InlineData("SkillTask", "skills", "skills", "reorder", "skillReorder", null)]
        public void CanonicalDispatchMappings_FormatExactBindingReceipt(
            string component,
            string domain,
            string panel,
            string cmd,
            string action,
            string viewSessionId)
        {
            string line = AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                component,
                "web.call-1",
                42,
                panel,
                "panel.instance~1",
                cmd,
                action,
                viewSessionId);

            string expected = "event=authority_flash_call_bound"
                + " domain=" + domain
                + " webCallId=web.call-1"
                + " flashCallId=42"
                + " panel=" + panel
                + " panelInstanceId=panel.instance~1"
                + " cmd=" + cmd
                + " action=" + action;
            if (component == "EquipmentTuningTask")
                expected += " viewSessionId=view.session~1";

            Assert.Equal(expected, line);
        }

        [Fact]
        public void AttackerControlledFields_AreProjectedAsOtherWithoutRawSecret()
        {
            const string secret = "raw-secret";
            string line = AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "CraftingTask",
                "web\r\n" + secret,
                -7,
                secret,
                "panel\n" + secret,
                secret,
                secret);

            Assert.Equal(
                "event=authority_flash_call_bound domain=crafting"
                + " webCallId=other flashCallId=other panel=other"
                + " panelInstanceId=other cmd=other action=other",
                line);
            Assert.DoesNotContain(secret, line);
            Assert.DoesNotContain("\r", line);
            Assert.DoesNotContain("\n", line);
        }

        [Fact]
        public void MaterialShopBindingReceipt_HashesWebAndSourceIdentifiers()
        {
            const string webCallId = "material.open-1";
            const string sourceInstance = "panel.crafting~1";
            string line = AuthorityLogFormatter
                .FormatMaterialShopAuthorityFlashCallBound(
                    webCallId,
                    42,
                    sourceInstance);

            Assert.Equal(
                "event=authority_flash_call_bound"
                + " domain=material_shop_access"
                + " webCallIdRef="
                + AuthorityLogFormatter.CreateReference(webCallId)
                + " flashCallId=42"
                + " panel=crafting"
                + " panelInstanceIdRef="
                + AuthorityLogFormatter.CreateReference(sourceInstance)
                + " cmd=open_npc_shop"
                + " action=craftingMaterialShopAuthorize",
                line);
            Assert.DoesNotContain(webCallId, line);
            Assert.DoesNotContain(sourceInstance, line);
        }

        [Fact]
        public void CrossDomainActionAndUnreachableInventoryPanel_FailClosed()
        {
            string mismatch = AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "CraftingTask",
                "craft.call-1",
                7,
                "crafting",
                "crafting.instance-1",
                "commit",
                "shopCheckoutCommit");
            string unreachablePanel = AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "InventoryTask",
                "inventory.call-1",
                8,
                "skills",
                "skills.instance-1",
                "move",
                "inventoryMove");

            Assert.EndsWith(" cmd=commit action=other", mismatch);
            Assert.Contains(" domain=inventory ", unreachablePanel);
            Assert.Contains(" panel=other ", unreachablePanel);
            Assert.EndsWith(" cmd=move action=inventoryMove", unreachablePanel);
        }

        [Fact]
        public void EquipmentViewSessionId_IsFormattedWithoutEchoingInvalidValue()
        {
            const string secret = "view\nraw-secret";
            string line = AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "EquipmentTuningTask",
                "tune.call-1",
                9,
                "workbench",
                "workbench.instance-1",
                "preview",
                "equipmentTuningPreview",
                secret);

            Assert.EndsWith(" viewSessionId=other", line);
            Assert.DoesNotContain(secret, line);
            Assert.DoesNotContain("\n", line);
        }

        [Theory]
        [InlineData("workbench")]
        [InlineData("kshop")]
        [InlineData("crafting")]
        [InlineData("npcshop")]
        [InlineData("skills")]
        [InlineData("loot")]
        public void ExactCloseCompletion_FormatsKnownPanelAndInstance(
            string panel)
        {
            string line =
                AuthorityLogFormatter.FormatPanelExactCloseCompleted(
                    panel,
                    "panel.instance~1");

            Assert.Equal(
                "event=panel_exact_close_completed panel=" + panel
                + " panelInstanceId=panel.instance~1",
                line);
        }

        [Fact]
        public void ExactCloseCompletion_ProjectsInvalidFieldsAsOther()
        {
            const string privateValue = "private\r\nvalue";
            string line =
                AuthorityLogFormatter.FormatPanelExactCloseCompleted(
                    privateValue,
                    privateValue);

            Assert.Equal(
                "event=panel_exact_close_completed panel=other"
                + " panelInstanceId=other",
                line);
            Assert.DoesNotContain(privateValue, line);
            Assert.DoesNotContain("\r", line);
            Assert.DoesNotContain("\n", line);
        }
    }
}
