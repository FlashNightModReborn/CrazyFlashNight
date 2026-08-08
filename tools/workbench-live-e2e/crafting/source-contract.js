"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const { fail } = require("./common");
const RuntimeProducer = require("./runtime-producer");

const SOURCE_FINGERPRINT_SCHEMA = "workbench-live-e2e.crafting.source-fingerprint.v7";
const SOURCE_CLOSURE_SCHEMA = "workbench-live-e2e.crafting.source-closure.v7";
const SOURCE_BINDING_SCHEMA = "workbench-live-e2e.crafting.source-binding.v2";
const LOADED_SCHEMA = "workbench-live-e2e.crafting.loaded-production.v4";
const FONT_ENVIRONMENT_SCHEMA = "workbench-live-e2e.crafting.font-environment.v1";
const ICON_PROJECTION_SCHEMA = "workbench-live-e2e.crafting.icon-resource-projection.v1";
const AS2_ALGORITHM_CONTRACT_SCHEMA =
  "workbench-live-e2e.crafting.as2-algorithm-contract.v3";
const HEX64 = /^[a-f0-9]{64}$/;
const GIT_OID = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
const REQUIRED_SOURCE_PHASES = Object.freeze([
  "initial", "before_first_start", "after_commit",
  "before_restart", "after_readback", "final",
]);

const LAZY_REGISTRY_WEB = "launcher/web/modules/panels-lazy-registry.js";
const OVERLAY_STARTUP_WEB = Object.freeze([
  "launcher/web/modules/game-ui-behavior.js",
  "launcher/web/lib/marked.min.js",
  "launcher/web/modules/perf-frame-limiter.js",
  "launcher/web/modules/bridge.js",
  "launcher/web/modules/uidata.js",
  "launcher/web/modules/toast.js",
  "launcher/web/modules/sparkline.js",
  "launcher/web/modules/notch.js",
  "launcher/web/modules/cursor-feedback.js",
  "launcher/web/modules/currency.js",
  "launcher/web/modules/combo.js",
  "launcher/web/modules/lazy-loader.js",
  "launcher/web/modules/panels.js",
  "launcher/web/modules/panel-scale.js",
  "launcher/web/modules/audio.js",
  "launcher/web/modules/overlay-audio-bindings.js",
  "launcher/web/modules/tooltip.js",
  "launcher/web/modules/asset-timeline.js",
  "launcher/web/modules/icons.js",
  "launcher/web/modules/map-panel-data.js",
  "launcher/web/modules/map-fit-presets.js",
  "launcher/web/modules/map-hud.js",
]);

const OVERLAY_STYLE_WEB = Object.freeze([
  "launcher/web/css/game-ui-behavior.css",
  "launcher/web/css/overlay.css",
  "launcher/web/css/panels.css",
  "launcher/web/modules/minigames/shared/minigame-shell.css",
  "launcher/web/modules/minigames/lockbox/lockbox.css",
  "launcher/web/modules/minigames/pinalign/pinalign.css",
  "launcher/web/modules/minigames/gobang/gobang.css",
]);

const PANELS_IMPORT_STYLE_WEB = Object.freeze([
  "launcher/web/css/panels/foundation-top.css",
  "launcher/web/css/workbench/tokens.css",
  "launcher/web/css/panels/foundation-rest.css",
  "launcher/web/css/workbench/core.css",
  "launcher/web/css/workbench/profiles.css",
  "launcher/web/css/panels/features.css",
  "launcher/web/css/workbench/arena.css",
  "launcher/web/css/workbench/inventory.css",
  "launcher/web/css/workbench/skins.css",
  "launcher/web/css/workbench/entities.css",
  "launcher/web/css/workbench/crafting.css",
  "launcher/web/css/workbench/equipment-inspector.css",
  "launcher/web/css/workbench/skills.css",
  "launcher/web/css/workbench/equipment-tuning.css",
  "launcher/web/css/workbench/components.css",
  "launcher/web/css/workbench/character-build.css",
  "launcher/web/css/workbench/character-build-stats.css",
  "launcher/web/css/workbench/team.css",
  "launcher/web/css/workbench/states.css",
  "launcher/web/css/workbench/motion.css",
  "launcher/web/css/hairdresser.css",
  "launcher/web/css/workbench/utilities.css",
]);

const CRAFTING_LAZY_WEB = Object.freeze([
  "launcher/web/modules/panel-runtime.js",
  "launcher/web/modules/workbench-lifecycle.js",
  "launcher/web/modules/workbench-focus.js",
  "launcher/web/modules/workbench-primitives.js",
  "launcher/web/modules/workbench-profile.js",
  "launcher/web/modules/workbench.js",
  "launcher/web/modules/workbench-components.js",
  "launcher/web/modules/item-filter.js",
  "launcher/web/modules/asset-timeline.js",
  "launcher/web/modules/dressup-doll-renderer.js",
  "launcher/web/modules/workbench-inspection-viewport.js",
  "launcher/web/modules/equipment-inspector.js",
  "launcher/web/modules/crafting-inspector.js",
  "launcher/web/modules/crafting-materials.js",
  "launcher/web/modules/crafting-detail-presenter.js",
  "launcher/web/modules/inventory-runtime.js",
  "launcher/web/modules/crafting-runtime.js",
  "launcher/web/modules/crafting.js",
]);

const ORGANIZER_LAZY_WEB = Object.freeze([
  "launcher/web/modules/inventory-runtime.js",
  "launcher/web/modules/inventory-ui.js",
  "launcher/web/modules/inventory-workbench-config.js",
  "launcher/web/modules/inventory-workbench-quick-transfer.js",
  "launcher/web/modules/inventory-workbench-owned-view.js",
  "launcher/web/modules/inventory-storage-workbench.js",
  "launcher/web/modules/crafting-inventory-organizer.js",
]);

const HOST_FILES = Object.freeze([
  "launcher/src/Tasks/CraftingTask.cs",
  "launcher/src/Tasks/InventoryTask.cs",
  "launcher/src/Tasks/PanelPendingCallTracker.cs",
  "launcher/src/Tasks/PanelBridge.cs",
  "launcher/src/Guardian/AuthorityLogFormatter.cs",
  "launcher/src/Guardian/PanelHostController.cs",
  "launcher/src/Guardian/PanelRequestOwnerLifecycle.cs",
  "launcher/src/Guardian/WebOverlayForm.cs",
  "launcher/src/Guardian/LauncherCommandRouter.cs",
  "launcher/src/Guardian/LogManager.cs",
  "launcher/src/Bus/TaskRegistry.cs",
  "launcher/src/Bus/XmlSocketServer.cs",
  "launcher/src/Program.cs",
]);

const AS2_FILES = Object.freeze([
  "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as",
  "scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as",
  "scripts/类定义/org/flashNight/arki/item/BaseItem.as",
  "scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as",
  "scripts/类定义/org/flashNight/arki/item/equipment/EquipmentConfigManager.as",
  "scripts/类定义/org/flashNight/arki/item/equipment/TierSystem.as",
  "scripts/类定义/org/flashNight/arki/item/obtain/ItemObtainIndex.as",
  "scripts/类定义/org/flashNight/arki/item/synthesis/SynthesisIndex.as",
  "scripts/类定义/org/flashNight/gesh/json/LoadJson/CraftingListLoader.as",
  "scripts/类定义/org/flashNight/gesh/xml/LoadXml/EquipmentConfigLoader.as",
  "scripts/类定义/org/flashNight/gesh/xml/LoadXml/EquipModDataLoader.as",
  "scripts/类定义/org/flashNight/gesh/xml/LoadXml/EquipModListLoader.as",
  "scripts/类定义/org/flashNight/gesh/xml/LoadXml/ItemDataLoader.as",
  "scripts/类定义/org/flashNight/gesh/object/ObjectUtil.as",
  "scripts/类定义/org/flashNight/gesh/string/StringUtils.as",
  "scripts/类定义/org/flashNight/gesh/tooltip/TooltipComposer.as",
  "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
  "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as",
  "scripts/类定义/LiteJSON.as",
]);

// Reviewed v2 literals. Capture validates current bytes against these constants; it never
// derives a replacement contract from the source being tested.
const AS2_ALGORITHM_EXPECTATIONS = Object.freeze([
  { relativePath: "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
    className: "org.flashNight.arki.item.ItemUtil", modifiers: ["public", "static"],
    functionName: "require", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 11, signatureTokenSha256: "789fd14ed13d8e749ae5a448e181a786fa1c295e6e127363aeeb2d3d6c9e455b",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 601, bodyTokenSha256: "9d6be98ad3f4336de5d0e77a4024bb8210f1eb787809e6be78e7bc661004e844",
    tokenCount: 612, normalizedTokenSha256: "7575a7101d448ac41380fcb2352586207fc8326140ab2475659aedad7bd59d98" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
    className: "org.flashNight.arki.item.ItemUtil", modifiers: ["public", "static"],
    functionName: "acquire", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 11, signatureTokenSha256: "0a2f1ddbfa02223e41bdb15bdc60ed981c3e7178d8e96af343bbf3b22422694c",
    returnTokenCount: 2, returnTokenSha256: "62ff10cea0b7b9a8ea2ca89d725304c12609173b1e797afec17f5142802f6959",
    bodyTokenCount: 701, bodyTokenSha256: "60ab3525d6eaaac255ecc8b1df76afebd35a108eccc77d5d2624bebe29432ea1",
    tokenCount: 712, normalizedTokenSha256: "d666ebbfb09cf1f08d10e0ccc8d00228b6a8fb66b61ec4ed33be3c3c3de7f00e" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
    className: "org.flashNight.arki.item.ItemUtil", modifiers: ["public", "static"],
    functionName: "contain", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 11, signatureTokenSha256: "ebddea9306a313c1261d0576b8ef885cb80ead6d5b1a55569ff98bd0a4d1a0fe",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 478, bodyTokenSha256: "56174a07b5c1364a4c40a90a0c68498b24608a16516522cf763101d0f1044f01",
    tokenCount: 489, normalizedTokenSha256: "292b7e0b9cb5b08ab6e90f1a8706d5880e5a9940425e883144bdc9573690d4ad" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
    className: "org.flashNight.arki.item.ItemUtil", modifiers: ["public", "static"],
    functionName: "submit", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 11, signatureTokenSha256: "ff79483ec27e37f32f57ff59cd914422c7cb898ec8355f31d8dd41b216cea9ea",
    returnTokenCount: 2, returnTokenSha256: "62ff10cea0b7b9a8ea2ca89d725304c12609173b1e797afec17f5142802f6959",
    bodyTokenCount: 300, bodyTokenSha256: "bbf6bc35d167bed60b013bec04cf683b231331cb45da3ad53d3a0d8c26037db0",
    tokenCount: 311, normalizedTokenSha256: "9c93043352c7d3dfa194767760863f39f102ea436261ac17c117f9bd436926a8" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
    className: "org.flashNight.arki.item.ItemUtil", modifiers: ["public", "static"],
    functionName: "singleRequire", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 15, signatureTokenSha256: "439235f2ea5c3eb3cd6bd141fee2eb5c0ca5f8cb3bd134c9fef7d3e5130ca423",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 20, bodyTokenSha256: "c70393b98a6e12b7f22edc99153e7e0585f4be7a5387df21d7c19b387090192e",
    tokenCount: 35, normalizedTokenSha256: "7fda6f37589d85a7d3b54f750ccfdd301a4266b51d796121006a772d818f4304" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
    className: "org.flashNight.arki.item.ItemUtil", modifiers: ["public", "static"],
    functionName: "singleAcquire", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 15, signatureTokenSha256: "cee8bc891d5a4ca1b90d2f5852726b5852d55e6d37cf084dcf240ba5c16f747d",
    returnTokenCount: 2, returnTokenSha256: "62ff10cea0b7b9a8ea2ca89d725304c12609173b1e797afec17f5142802f6959",
    bodyTokenCount: 20, bodyTokenSha256: "2dd82762b29197b67669a347d14d7cb67c4dc8ca29641ee932bcd42aec8330e4",
    tokenCount: 35, normalizedTokenSha256: "14809f1c6b0bc6bccf9c264d4ed55c7f2a011b3f04ffe608057ab02a02a6f2b5" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as",
    className: "org.flashNight.arki.item.itemCollection.ArrayInventory", modifiers: ["public"],
    functionName: "add", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 14, signatureTokenSha256: "01bbfacf5fabaea976e7e47327526a8eefd7d98c1b4f3eb08a6de6536e6d7d22",
    returnTokenCount: 2, returnTokenSha256: "62ff10cea0b7b9a8ea2ca89d725304c12609173b1e797afec17f5142802f6959",
    bodyTokenCount: 202, bodyTokenSha256: "6990ed28af868b582b17cf1daa60fdcbfca70911c700fde67d6be637b3dcb14a",
    tokenCount: 216, normalizedTokenSha256: "1afce81c75dd92da98d9ca3c0933616e27c09ad797eeb3d2da8c61100b9b1df6" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as",
    className: "org.flashNight.arki.item.itemCollection.ArrayInventory", modifiers: ["public"],
    functionName: "getIndexes", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 7, signatureTokenSha256: "111e2e81e8ed3900bb67a13a57e1a5812f60325e43983d64fdb08731d7e2936b",
    returnTokenCount: 2, returnTokenSha256: "04b5c118cd7dead14bcef417c9db2f4439914198c243af04db237eddc59b7b0c",
    bodyTokenCount: 7, bodyTokenSha256: "a68ed31a2a85d3d52904be9c54b0879ecc8a02d2c76a2db84daddc5141034b38",
    tokenCount: 14, normalizedTokenSha256: "b8da00f31cf56192dccce5823b861e0fdff0bf26475e3bcac8ae50db75518544" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as",
    className: "org.flashNight.arki.item.itemCollection.ArrayInventory", modifiers: ["public"],
    functionName: "getItemArray", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 7, signatureTokenSha256: "9db1fe707e92968a58747e6c30ec3eb59073381128c66dc5f5c9e619880c3c98",
    returnTokenCount: 2, returnTokenSha256: "04b5c118cd7dead14bcef417c9db2f4439914198c243af04db237eddc59b7b0c",
    bodyTokenCount: 53, bodyTokenSha256: "77c0da311eb749a88e3dd7734d82a72bf28ab1f2672543133daddf8c27818157",
    tokenCount: 60, normalizedTokenSha256: "d799c785847b4d4306cdf5e5fd6b9c95963faa3da88b0a5855a21c088b82a39d" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as",
    className: "org.flashNight.arki.item.itemCollection.ArrayInventory", modifiers: ["public"],
    functionName: "searchFirstKey", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 10, signatureTokenSha256: "8b0e2a29a111051eb42dc8a6c6856d040699bf2cb9aa7d592a5cd5f218bf201c",
    returnTokenCount: 2, returnTokenSha256: "adce924caaf57b154e4eae346fc8653788320ea2ba7a6a09ee9da878965a3777",
    bodyTokenCount: 94, bodyTokenSha256: "3cf27d687a75257b6c874e5ab27d996fec4da946ea70fee0e95fb58b270f181d",
    tokenCount: 104, normalizedTokenSha256: "65620a2a85a4cad1a01f38762b4937b9bdd3815792cecc8e069a0cf1b497cedb" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as",
    className: "org.flashNight.arki.item.itemCollection.ArrayInventory", modifiers: ["public"],
    functionName: "getFirstVacancy", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 7, signatureTokenSha256: "266d7e84c4fdeeba0f515bd7c4a20fadf333802693ef0209aa1e7649ea7cfeac",
    returnTokenCount: 2, returnTokenSha256: "0f410e1b1feb2623691b3dc78fbb271f9df90cacc571ec662b3e89e21824fce3",
    bodyTokenCount: 101, bodyTokenSha256: "02129feca123a37d843534e568bd9c8571721d66dda916341eff01bb9c82b224",
    tokenCount: 108, normalizedTokenSha256: "d441543b8ea704b95329058a0ddb0b86a9f4adb7b9bbb871a7006c2402795fb1" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as",
    className: "org.flashNight.arki.item.itemCollection.ArrayInventory", modifiers: ["public"],
    functionName: "getVacancies", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 10, signatureTokenSha256: "268e4044c3944856051ef80917097f25dbfaf2c8a598a613395d53de8cdd44b0",
    returnTokenCount: 2, returnTokenSha256: "04b5c118cd7dead14bcef417c9db2f4439914198c243af04db237eddc59b7b0c",
    bodyTokenCount: 185, bodyTokenSha256: "d8542dd49c066d251d418aadbe4f65dad193933cd7c11a27d5bbba71e099ccf8",
    tokenCount: 195, normalizedTokenSha256: "47fa870047271da6f7ea8944e791d8bd97353f312fac43682f5b53d3c36f7b6b" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as",
    className: "org.flashNight.arki.item.CraftingPanelService", modifiers: ["private", "static"],
    functionName: "executeCommit", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 11, signatureTokenSha256: "f3460d8207d6a51216e63393b8296b927f3a9954d91c9a3f942a2eb3acf12dcf",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 728, bodyTokenSha256: "942b0e6fcc0fb739b9ae57a383e715fcef7cf236c2d577b6ffdf75e434c42e61",
    tokenCount: 739, normalizedTokenSha256: "6ed800fd3cdbfede032e6fb429400bdeddb2b02053453ba4bf1921e6750e8426" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as",
    className: "org.flashNight.arki.item.CraftingPanelService", modifiers: ["private", "static"],
    functionName: "buildPlan", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 27, signatureTokenSha256: "33d3439b80c3c761359c4c200b8e03d8a9860499e91b69dd29be9267e4113624",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 998, bodyTokenSha256: "fa5036d772416705fcd65b7983ee1bc30cbad52f20dac25f19fbe6caf8935ce0",
    tokenCount: 1025, normalizedTokenSha256: "8a5f9674813f9e3ce0803d9073e941993d6ca46aa90d061fa125cf5bd9e672eb" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as",
    className: "org.flashNight.arki.item.CraftingPanelService", modifiers: ["private", "static"],
    functionName: "projectOutputDeliveryAfterSubmit", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 19, signatureTokenSha256: "5d1537d5d4b0043bc9bb9e48c265aba5cba16e92d24e074907229cf51f32749a",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 375, bodyTokenSha256: "cdbe90600df31fb20adb09be6f00ba39ec7cb19f2e9f40285d842246f1047a82",
    tokenCount: 394, normalizedTokenSha256: "52024d3d98c0ed230d1c741a46eb9eb5e2324420a099bb67ba03ca4d2b1cd8b6" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as",
    className: "org.flashNight.arki.item.CraftingPanelService", modifiers: ["private", "static"],
    functionName: "outputReceiptMatchesPrototype", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 23, signatureTokenSha256: "5493c247adceec310e43c5281fffcd2c99ce8fc39595131e58946776f5bcef7d",
    returnTokenCount: 2, returnTokenSha256: "62ff10cea0b7b9a8ea2ca89d725304c12609173b1e797afec17f5142802f6959",
    bodyTokenCount: 253, bodyTokenSha256: "a7bbbd92952d5bbdd889952302e2aeccaf11ac3268257d4b706c9f2dd0335885",
    tokenCount: 276, normalizedTokenSha256: "8336b4589bf48aadc0d3b769cc663b6cace6ebcd8388faf3727aa6ae6e56ec1e" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as",
    className: "org.flashNight.arki.item.CraftingPanelService", modifiers: ["private", "static"],
    functionName: "deepEqual", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 19, signatureTokenSha256: "1ced81e648e5b03972076b9b6e4dae8448d9d205f9f8e678beba577758e1ecf3",
    returnTokenCount: 2, returnTokenSha256: "62ff10cea0b7b9a8ea2ca89d725304c12609173b1e797afec17f5142802f6959",
    bodyTokenCount: 197, bodyTokenSha256: "5a734ac29419f9b0d3a9aba20c027095367d096e27ffa9ed7c6d2f7fbfde1fa6",
    tokenCount: 216, normalizedTokenSha256: "0ac7ff06b60ee548e770166714865f7c625bd15535671ce8f0a070c08533bc63" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as",
    className: "org.flashNight.arki.item.InventoryPanelService", modifiers: ["public", "static"],
    functionName: "buildOutputPrototype", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 15, signatureTokenSha256: "4fa20c2f073bbebd59323092ba0e6b352f42c13dda86e4958b6d29cee21424fe",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 134, bodyTokenSha256: "d85210c75c37c44fcd89a4f4be66d75ab652be88118240ab2f2a63d295dd6056",
    tokenCount: 149, normalizedTokenSha256: "38be8fe56776865e306cc31f7f04aa46ecb87cd2640366b9e40f4a7a0d8c8f84" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as",
    className: "org.flashNight.arki.item.InventoryPanelService", modifiers: ["public", "static"],
    functionName: "buildOutputReceipt", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 11, signatureTokenSha256: "4945aadfe893b6b63f35cc7bb304473327217391c69099ea013ae2e2ef8ec552",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 107, bodyTokenSha256: "fc365a40b8a9f3cfd16407b2b331a5b62017a863c736ed58689437d79db97bba",
    tokenCount: 118, normalizedTokenSha256: "ebf9457f3cc2cfa2aa0c9094702a502eb82b3f968143d4be9bbcdd5e7807d3b6" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as",
    className: "org.flashNight.arki.item.InventoryPanelService", modifiers: ["private", "static"],
    functionName: "buildItemProjectionInternal", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 15, signatureTokenSha256: "32eee30baaa11242cb7754cc7001c52ec7cca4e603fef27fc06c3151b2f86a72",
    returnTokenCount: 2, returnTokenSha256: "f92ed6dde146db78769a8561df9ae9b75566d8cd334b9d3851ce78ade4e681a7",
    bodyTokenCount: 982, bodyTokenSha256: "2f8e278dac4e0e8da418d40cfb71ae9941a15755f289cdca70c51af54fcd931f",
    tokenCount: 997, normalizedTokenSha256: "6e0d316b2d7c81c997de6303a9473c820ecc169e0c1b1ebf240907714215351b" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/BaseItem.as",
    className: "org.flashNight.arki.item.BaseItem", modifiers: ["public", "static"],
    functionName: "create", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 19, signatureTokenSha256: "63a28589a5a41a5d8b5dfabe73739938316185b8dbf1ad5d31983b29e38157f8",
    returnTokenCount: 2, returnTokenSha256: "0285c572afbbf1294d59ad347259c7b9bea909b7adac34252cb510b1444f4444",
    bodyTokenCount: 87, bodyTokenSha256: "44d1c828b87468706151f8a3700393c8933bd92462b7047ebbf2d27a4df28bcb",
    tokenCount: 106, normalizedTokenSha256: "469b84ba2c45e8f91668d7da6ee8875e0985861d019b8790f40b836b1c173493" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/EquipmentUtil.as",
    className: "org.flashNight.arki.item.EquipmentUtil", modifiers: ["public", "static"],
    functionName: "getMaxLevel", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 8, signatureTokenSha256: "e2cbae5ba4e52f20a301010a3e6ed301b83c37d20ec7dea4d65c921052fd735f",
    returnTokenCount: 2, returnTokenSha256: "0f410e1b1feb2623691b3dc78fbb271f9df90cacc571ec662b3e89e21824fce3",
    bodyTokenCount: 9, bodyTokenSha256: "025c5ff40c1b45875336973c95428779faa806c0ecc366c5c4338a2f6931923e",
    tokenCount: 17, normalizedTokenSha256: "5b48631c2b9a315fcc921440dcccb672dd6a851754e66d10561dfe4f7e39a14e" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/equipment/TierSystem.as",
    className: "org.flashNight.arki.item.equipment.TierSystem", modifiers: ["public", "static"],
    functionName: "getAvailableTierMaterials", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 11, signatureTokenSha256: "e32e117b09301d22bbeee2ac2a31a3bbc1c0b043e495e3b38af77c43cd5bcdea",
    returnTokenCount: 2, returnTokenSha256: "04b5c118cd7dead14bcef417c9db2f4439914198c243af04db237eddc59b7b0c",
    bodyTokenCount: 214, bodyTokenSha256: "c689d9290046e18ab747291e624625f6bd8fed562b34457af3dff67b8b38cfb6",
    tokenCount: 225, normalizedTokenSha256: "89d7396be27348cd833f5e523eaabb1aaa640cdbbd1430e217b109e5d9da2df2" },
  { relativePath: "scripts/类定义/org/flashNight/arki/item/equipment/EquipmentConfigManager.as",
    className: "org.flashNight.arki.item.equipment.EquipmentConfigManager", modifiers: ["public", "static"],
    functionName: "getTierKey", classDepth: 0, memberDepth: 1,
    signatureTokenCount: 11, signatureTokenSha256: "04a1780535a10f75862d0deec00a068dfac84def76611a53019eb995827c06c0",
    returnTokenCount: 2, returnTokenSha256: "adce924caaf57b154e4eae346fc8653788320ea2ba7a6a09ee9da878965a3777",
    bodyTokenCount: 8, bodyTokenSha256: "0f7e527ea06b9f882c4024feddf36c76943798ba5a6d6678f09f4d5f6a1ede39",
    tokenCount: 19, normalizedTokenSha256: "9be000b9782195f69eade016d63b1728b75f526d76e6f4e88a79c4b3cbcd7f6f" },
]);

const FIXED_SWF = Object.freeze([
  "CRAZYFLASHER7MercenaryEmpire.swf",
  "flashswf/levels/基地场景合集.swf",
  "scripts/asLoader.swf",
]);

function normalize(value) {
  return String(value || "").replace(/\\/g, "/").replace(/^\.\//, "");
}

const AS2_WORD_START_RE = /^[\p{L}\p{Nl}_$]$/u;
const AS2_WORD_PART_RE = /^[\p{L}\p{Nl}\p{Nd}\p{Mn}\p{Mc}\p{Pc}_$]$/u;
const AS2_MULTI_SYMBOLS = Object.freeze([
  ">>>=", "===", "!==", ">>>", "<<=", ">>=", "==", "!=", "<=", ">=", "++", "--",
  "&&", "||", "+=", "-=", "*=", "/=", "%=", "<<", ">>", "&=", "|=", "^=", "::", "..",
]);
const AS2_MEMBER_MODIFIERS = new Set([
  "public", "private", "protected", "internal", "static", "final", "override", "native",
]);

function as2AlgorithmFail(code, message, details) {
  fail(code, "source_identity", message, details || {});
}

function tokenizeAs2Detailed(sourceValue) {
  const source = String(sourceValue || "");
  const tokens = [];
  let index = source.charCodeAt(0) === 0xFEFF ? 1 : 0;
  function emit(kind, value, start, end) {
    tokens.push({ kind, value, start, end });
  }
  while (index < source.length) {
    const current = source[index];
    const next = source[index + 1];
    if (/\s/.test(current)) { index += 1; continue; }
    if (current === "/" && next === "/") {
      index += 2;
      while (index < source.length && source[index] !== "\r" && source[index] !== "\n") index += 1;
      continue;
    }
    if (current === "/" && next === "*") {
      const start = index;
      index += 2;
      while (index < source.length && !(source[index] === "*" && source[index + 1] === "/")) {
        index += 1;
      }
      if (index >= source.length) as2AlgorithmFail("as2_algorithm_tokenization_invalid",
        "AS2 source contains an unterminated block comment", { start });
      index += 2;
      continue;
    }
    if (current === '"' || current === "'") {
      const start = index;
      const quote = current;
      index += 1;
      let closed = false;
      while (index < source.length) {
        if (source[index] === "\\") {
          if (index + 1 >= source.length) break;
          index += 2;
          continue;
        }
        if (source[index] === quote) { index += 1; closed = true; break; }
        index += 1;
      }
      if (!closed) as2AlgorithmFail("as2_algorithm_tokenization_invalid",
        "AS2 source contains an unterminated string literal", { start });
      emit("string", source.slice(start, index), start, index);
      continue;
    }
    if (AS2_WORD_START_RE.test(current)) {
      const start = index;
      index += 1;
      while (index < source.length && AS2_WORD_PART_RE.test(source[index])) index += 1;
      emit("word", source.slice(start, index), start, index);
      continue;
    }
    const number = /^(?:0[xX][0-9A-Fa-f]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)/
      .exec(source.slice(index));
    if (number) {
      const start = index;
      index += number[0].length;
      emit("number", number[0], start, index);
      continue;
    }
    const symbol = AS2_MULTI_SYMBOLS.find((candidate) => source.startsWith(candidate, index))
      || current;
    emit("symbol", symbol, index, index + symbol.length);
    index += symbol.length;
  }
  return tokens;
}

function tokenizeAs2(source) {
  return tokenizeAs2Detailed(source).map((token) => token.value);
}

function matchingAs2Token(tokens, openIndex, openValue, closeValue, functionName) {
  if (!tokens[openIndex] || tokens[openIndex].value !== openValue) {
    as2AlgorithmFail("as2_algorithm_function_structure_invalid",
      "AS2 algorithm declaration lacks its structural opening token", {
        functionName, openValue,
      });
  }
  let depth = 0;
  for (let index = openIndex; index < tokens.length; index += 1) {
    if (tokens[index].value === openValue) depth += 1;
    else if (tokens[index].value === closeValue) {
      depth -= 1;
      if (depth === 0) return index;
      if (depth < 0) break;
    }
  }
  as2AlgorithmFail("as2_algorithm_function_structure_invalid",
    "AS2 algorithm declaration has an unclosed structural boundary", {
      functionName, openValue, closeValue,
    });
}

function indexAs2BraceParents(tokens) {
  const parentOpenByToken = new Array(tokens.length).fill(null);
  const closeByOpen = new Map();
  const stack = [];
  tokens.forEach((token, index) => {
    parentOpenByToken[index] = stack.length ? stack[stack.length - 1] : null;
    if (token.value === "{") { stack.push(index); return; }
    if (token.value !== "}") return;
    if (!stack.length) as2AlgorithmFail("as2_algorithm_source_structure_invalid",
      "AS2 source contains an unmatched closing brace", { start: token.start });
    closeByOpen.set(stack.pop(), index);
  });
  if (stack.length) as2AlgorithmFail("as2_algorithm_source_structure_invalid",
    "AS2 source contains an unclosed brace", { start: tokens[stack[stack.length - 1]].start });
  return { parentOpenByToken, closeByOpen };
}

function as2QualifiedClassName(tokens, classIndex) {
  let cursor = classIndex + 1;
  if (!tokens[cursor] || tokens[cursor].kind !== "word") return null;
  let name = tokens[cursor].value;
  cursor += 1;
  while (tokens[cursor] && tokens[cursor].value === "."
      && tokens[cursor + 1] && tokens[cursor + 1].kind === "word") {
    name += "." + tokens[cursor + 1].value;
    cursor += 2;
  }
  return { name, signatureEnd: cursor };
}

function targetAs2ClassBody(tokens, expectation, braceIndex) {
  const declarations = [];
  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index].kind !== "word" || tokens[index].value !== "class") continue;
    const qualified = as2QualifiedClassName(tokens, index);
    if (!qualified || qualified.name !== expectation.className) continue;
    let bodyOpen = qualified.signatureEnd;
    while (bodyOpen < tokens.length && tokens[bodyOpen].value !== "{") {
      if ([";", "}", "function", "class"].includes(tokens[bodyOpen].value)) {
        as2AlgorithmFail("as2_algorithm_class_structure_invalid",
          "AS2 target class declaration escaped its structural boundary", {
            className: expectation.className, token: tokens[bodyOpen].value,
          });
      }
      bodyOpen += 1;
    }
    if (bodyOpen >= tokens.length || !braceIndex.closeByOpen.has(bodyOpen)) {
      as2AlgorithmFail("as2_algorithm_class_structure_invalid",
        "AS2 target class lacks one structural body", { className: expectation.className });
    }
    declarations.push({ classIndex: index, bodyOpen,
      bodyClose: braceIndex.closeByOpen.get(bodyOpen) });
  }
  if (declarations.length !== 1) {
    as2AlgorithmFail("as2_algorithm_class_cardinality_invalid",
      "AS2 algorithm anchor requires one exact target class declaration", {
        className: expectation.className, count: declarations.length,
      });
  }
  const declaration = declarations[0];
  if (braceIndex.parentOpenByToken[declaration.classIndex] !== null
      || braceIndex.parentOpenByToken[declaration.bodyOpen] !== null) {
    as2AlgorithmFail("as2_algorithm_class_depth_invalid",
      "AS2 target class must be a file-level declaration", {
        className: expectation.className, start: tokens[declaration.classIndex].start,
      });
  }
  return declaration;
}

function as2TokenDigest(tokens) {
  return Evidence.sha256Text(Evidence.canonicalJson(tokens.map((token) => [token.kind, token.value])));
}

function as2BraceDepthAt(tokenIndex, braceIndex) {
  let depth = 0;
  let parent = braceIndex.parentOpenByToken[tokenIndex];
  while (parent !== null) {
    depth += 1;
    parent = braceIndex.parentOpenByToken[parent];
  }
  return depth;
}

function extractAs2FunctionContract(source, expectation) {
  if (!Evidence.isPlainObject(expectation) || typeof expectation.relativePath !== "string"
      || !expectation.relativePath || typeof expectation.className !== "string"
      || !expectation.className || !Array.isArray(expectation.modifiers)
      || typeof expectation.functionName !== "string" || !expectation.functionName) {
    as2AlgorithmFail("as2_algorithm_expectation_invalid",
      "AS2 algorithm extraction requires one complete versioned expectation");
  }
  const tokens = tokenizeAs2Detailed(source);
  const braceIndex = indexAs2BraceParents(tokens);
  const targetClass = targetAs2ClassBody(tokens, expectation, braceIndex);
  const declarations = [];
  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index].kind !== "word" || tokens[index].value !== "function"
        || !tokens[index + 1] || tokens[index + 1].value !== expectation.functionName) continue;
    if (tokens[index + 1].kind !== "word" || !tokens[index + 2]
        || tokens[index + 2].value !== "(") {
      as2AlgorithmFail("as2_algorithm_function_structure_invalid",
        "AS2 target function declaration is malformed", {
          functionName: expectation.functionName, start: tokens[index].start,
        });
    }
    declarations.push(index);
  }
  if (declarations.length !== 1) {
    as2AlgorithmFail("as2_algorithm_function_cardinality_invalid",
      "AS2 algorithm anchor requires one exact target function declaration", {
        functionName: expectation.functionName, count: declarations.length,
      });
  }
  const functionIndex = declarations[0];
  const parameterOpen = functionIndex + 2;
  const parameterClose = matchingAs2Token(tokens, parameterOpen, "(", ")",
    expectation.functionName);
  let bodyOpen = parameterClose + 1;
  while (bodyOpen < tokens.length && tokens[bodyOpen].value !== "{") {
    if ([";", "}", "function", "class"].includes(tokens[bodyOpen].value)) {
      as2AlgorithmFail("as2_algorithm_function_structure_invalid",
        "AS2 target function return declaration escaped its structural boundary", {
          functionName: expectation.functionName, token: tokens[bodyOpen].value,
        });
    }
    bodyOpen += 1;
  }
  if (bodyOpen >= tokens.length || !braceIndex.closeByOpen.has(bodyOpen)) {
    as2AlgorithmFail("as2_algorithm_function_structure_invalid",
      "AS2 target function lacks one structural body", { functionName: expectation.functionName });
  }
  const bodyClose = braceIndex.closeByOpen.get(bodyOpen);
  const nested = tokens.slice(bodyOpen + 1, bodyClose).find((token) =>
    token.kind === "word" && token.value === "function");
  if (nested) {
    as2AlgorithmFail("as2_algorithm_nested_function_invalid",
      "AS2 target function contains a nested function boundary", {
        functionName: expectation.functionName, nestedAt: nested.start,
      });
  }
  let memberStart = functionIndex;
  while (memberStart > 0 && tokens[memberStart - 1].kind === "word"
      && AS2_MEMBER_MODIFIERS.has(tokens[memberStart - 1].value)) memberStart -= 1;
  [memberStart, functionIndex, parameterOpen, bodyOpen].forEach((tokenIndex) => {
    if (tokenIndex <= targetClass.bodyOpen || tokenIndex >= targetClass.bodyClose
        || braceIndex.parentOpenByToken[tokenIndex] !== targetClass.bodyOpen) {
      as2AlgorithmFail("as2_algorithm_member_depth_invalid",
        "AS2 target function must be a direct member of its exact target class", {
          className: expectation.className, functionName: expectation.functionName,
          start: tokens[tokenIndex] && tokens[tokenIndex].start,
        });
    }
  });
  const modifiers = tokens.slice(memberStart, functionIndex).map((token) => token.value);
  const signatureTokens = tokens.slice(memberStart, bodyOpen);
  const returnTokens = tokens.slice(parameterClose + 1, bodyOpen);
  const bodyTokens = tokens.slice(bodyOpen, bodyClose + 1);
  const functionTokens = tokens.slice(memberStart, bodyClose + 1);
  return {
    relativePath: expectation.relativePath,
    className: expectation.className,
    functionName: expectation.functionName,
    modifiers,
    classDepth: as2BraceDepthAt(targetClass.classIndex, braceIndex),
    memberDepth: as2BraceDepthAt(functionIndex, braceIndex),
    nestedFunctionCount: 0,
    signatureTokenCount: signatureTokens.length,
    signatureTokenSha256: as2TokenDigest(signatureTokens),
    returnTokenCount: returnTokens.length,
    returnTokenSha256: as2TokenDigest(returnTokens),
    bodyTokenCount: bodyTokens.length,
    bodyTokenSha256: as2TokenDigest(bodyTokens),
    tokenCount: functionTokens.length,
    normalizedTokenSha256: as2TokenDigest(functionTokens),
    start: tokens[memberStart].start,
    end: tokens[bodyClose].end,
  };
}

function assertAs2FunctionExpectation(observed, expected) {
  const fields = [
    "relativePath", "className", "functionName", "classDepth", "memberDepth",
    "signatureTokenCount", "signatureTokenSha256", "returnTokenCount", "returnTokenSha256",
    "bodyTokenCount", "bodyTokenSha256", "tokenCount", "normalizedTokenSha256",
  ];
  const mismatch = fields.find((field) => observed[field] !== expected[field]);
  if (mismatch || Evidence.canonicalJson(observed.modifiers)
      !== Evidence.canonicalJson(expected.modifiers)) {
    as2AlgorithmFail("as2_algorithm_contract_mismatch",
      "ItemUtil/ArrayInventory executable algorithm differs from its fixed versioned contract", {
        relativePath: expected.relativePath, className: expected.className,
        functionName: expected.functionName, field: mismatch || "modifiers",
        expected: mismatch ? expected[mismatch] : expected.modifiers,
        actual: mismatch ? observed[mismatch] : observed.modifiers,
      });
  }
  return true;
}

function as2AlgorithmContractEntry(expected, observed) {
  return {
    locator: "root:" + expected.relativePath,
    className: observed.className,
    functionName: observed.functionName,
    modifiers: observed.modifiers,
    classDepth: observed.classDepth,
    memberDepth: observed.memberDepth,
    nestedFunctionCount: observed.nestedFunctionCount,
    signatureTokenCount: observed.signatureTokenCount,
    signatureTokenSha256: observed.signatureTokenSha256,
    returnTokenCount: observed.returnTokenCount,
    returnTokenSha256: observed.returnTokenSha256,
    bodyTokenCount: observed.bodyTokenCount,
    bodyTokenSha256: observed.bodyTokenSha256,
    tokenCount: observed.tokenCount,
    normalizedTokenSha256: observed.normalizedTokenSha256,
  };
}

function captureAs2AlgorithmContract(root) {
  const byFile = new Map();
  const functions = AS2_ALGORITHM_EXPECTATIONS.map((expected) => {
    if (!byFile.has(expected.relativePath)) {
      byFile.set(expected.relativePath, exactText(root, expected.relativePath,
        "as2_algorithm_source_invalid"));
    }
    const observed = extractAs2FunctionContract(byFile.get(expected.relativePath), expected);
    assertAs2FunctionExpectation(observed, expected);
    return as2AlgorithmContractEntry(expected, observed);
  });
  return { schema: AS2_ALGORITHM_CONTRACT_SCHEMA, functions };
}

function localWebPath(parentRelativePath, reference, phase) {
  const raw = String(reference || "").trim().replace(/[?#].*$/, "");
  if (!raw || /^[a-z][a-z0-9+.-]*:/i.test(raw) || raw.startsWith("//")
      || raw.startsWith("/") || raw.split(/[\\/]/).includes("..")) {
    fail("source_web_reference_invalid", phase || "source_identity",
      "production Web declaration is not one local bounded resource", {
        parentRelativePath, reference,
      });
  }
  const relative = path.posix.normalize(path.posix.join(path.posix.dirname(
    normalize(parentRelativePath)), raw.replace(/\\/g, "/")));
  if (!relative.startsWith("launcher/web/") || relative.includes("../")) {
    fail("source_web_reference_escape", phase || "source_identity",
      "production Web declaration escaped launcher/web", { parentRelativePath, reference });
  }
  return relative;
}

function localCssAssetPath(parentRelativePath, reference) {
  const raw = String(reference || "").trim().replace(/[?#].*$/, "");
  if (!raw || /^[a-z][a-z0-9+.-]*:/i.test(raw) || raw.startsWith("//")
      || raw.startsWith("/")) {
    fail("source_css_asset_reference_invalid", "source_identity",
      "production CSS asset is not one relative Web resource", {
        parentRelativePath, reference,
      });
  }
  const relative = path.posix.normalize(path.posix.join(path.posix.dirname(
    normalize(parentRelativePath)), raw.replace(/\\/g, "/")));
  if (!relative.startsWith("launcher/web/") || relative.includes("../")) {
    fail("source_css_asset_reference_escape", "source_identity",
      "production CSS asset escaped launcher/web", { parentRelativePath, reference });
  }
  return relative;
}

function quotedModuleReferences(text) {
  const output = [];
  const pattern = /['"](modules\/[A-Za-z0-9_./-]+\.js)['"]/g;
  let match;
  while ((match = pattern.exec(text)) !== null) output.push("launcher/web/" + match[1]);
  return output;
}

function exactText(root, relativePath, code) {
  exactFile(root, { role: "declaration", relativePath });
  try { return fs.readFileSync(path.resolve(root, relativePath.replace(/\//g, path.sep)), "utf8"); }
  catch (_error) {
    fail(code, "source_identity", "production declaration cannot be read", { relativePath });
  }
}

function verifyOverlayStartupInventory(root) {
  const text = exactText(root, "launcher/web/overlay.html", "source_startup_inventory_invalid");
  const actual = Array.from(text.matchAll(/<script\s+src="([^"]+)"\s*><\/script>/g))
    .map((entry) => "launcher/web/" + normalize(entry[1]));
  const expected = OVERLAY_STARTUP_WEB.concat([LAZY_REGISTRY_WEB]);
  if (Evidence.canonicalJson(actual) !== Evidence.canonicalJson(expected)) {
    fail("source_startup_inventory_invalid", "source_identity",
      "overlay startup scripts differ from the exact Crafting inventory", { actual, expected });
  }
  return actual;
}

function verifyOverlayStyleInventory(root) {
  const overlay = exactText(root, "launcher/web/overlay.html", "source_style_inventory_invalid");
  const overlayStyles = Array.from(overlay.matchAll(
    /<link\s+rel="stylesheet"\s+href="([^"]+)"\s*>/g))
    .map((entry) => "launcher/web/" + normalize(entry[1]));
  if (Evidence.canonicalJson(overlayStyles) !== Evidence.canonicalJson(OVERLAY_STYLE_WEB)) {
    fail("source_style_inventory_invalid", "source_identity",
      "overlay stylesheet order differs from the exact Crafting inventory");
  }
  const panels = exactText(root, "launcher/web/css/panels.css", "source_style_inventory_invalid");
  const imports = Array.from(panels.matchAll(/@import\s+url\("([^"]+)"\);/g))
    .map((entry) => path.posix.normalize("launcher/web/css/" + entry[1].slice(2)));
  if ((panels.match(/@import\b/g) || []).length !== imports.length
      || Evidence.canonicalJson(imports) !== Evidence.canonicalJson(PANELS_IMPORT_STYLE_WEB)) {
    fail("source_style_inventory_invalid", "source_identity",
      "panels.css import order differs from the exact Crafting inventory");
  }
  const union = overlayStyles.concat(imports);
  if (new Set(union).size !== union.length) {
    fail("source_style_inventory_invalid", "source_identity",
      "Crafting stylesheet inventory contains duplicates");
  }
  return { overlayStyles, imports };
}

function deriveConditionalWebResources(root, stylePaths) {
  const assetPaths = [];
  const fontUrls = [];
  stylePaths.forEach((relativePath) => {
    const text = exactText(root, relativePath, "source_style_resource_invalid");
    Array.from(text.matchAll(/url\(\s*(?:(['"])(.*?)\1|([^'"\s][^)]*?))\s*\)/gi))
      .map((match) => String(match[2] || match[3] || "").trim())
      .filter((reference) => reference && !reference.startsWith("data:")
        && !reference.startsWith("#"))
      .forEach((reference) => {
        if (/^https:\/\/cfn-fonts\.local\/[A-Za-z0-9._-]+$/.test(reference)) {
          fontUrls.push(reference);
          return;
        }
        if (/^[a-z][a-z0-9+.-]*:/i.test(reference) || reference.startsWith("//")) {
          fail("source_css_external_resource_invalid", "source_identity",
            "production CSS declares an ungoverned external resource", {
              parent: relativePath, reference,
            });
        }
        const assetPath = localCssAssetPath(relativePath, reference);
        if (path.posix.extname(assetPath).toLowerCase() === ".css") return;
        if (![".png", ".jpg", ".jpeg", ".svg", ".webp"].includes(
          path.posix.extname(assetPath).toLowerCase())) {
          fail("source_css_asset_type_invalid", "source_identity",
            "production CSS declares an unsupported local asset", {
              parent: relativePath, reference, assetPath,
            });
        }
        if (!assetPaths.includes(assetPath)) assetPaths.push(assetPath);
      });
  });
  return { assetPaths, fontUrls: Array.from(new Set(fontUrls)).sort() };
}

function deriveIdlePrewarmResources(root, overlayText) {
  const calls = Array.from(overlayText.matchAll(
    /\bMapPanelData\.prewarmAssets\(\s*(['"])([^'"]+)\1\s*\)/g));
  if (calls.length !== 1 || calls[0][2] !== "base") {
    fail("source_idle_prewarm_declaration_invalid", "source_identity",
      "Overlay must declare one exact base-map idle prewarm call");
  }
  const relativePath = "launcher/web/modules/map-panel-data.js";
  const mapText = exactText(root, relativePath, "source_idle_prewarm_contract_invalid");
  [
    "if (page.backgroundUrl) urls.push(page.backgroundUrl);",
    "var visuals = page.sceneVisuals || [];",
    "if (visuals[i] && visuals[i].assetUrl) urls.push(visuals[i].assetUrl);",
    "img.src = resolveAssetUrlForPrewarm(urls[j]);",
  ].forEach((statement) => {
    if (mapText.split(statement).length !== 2) {
      fail("source_idle_prewarm_contract_invalid", "source_identity",
        "map prewarm projection no longer has its one exact source statement", { statement });
    }
  });
  const pagesStart = mapText.indexOf("var _pages = {");
  const baseStart = mapText.indexOf("\n        base: {", pagesStart);
  const factionStart = mapText.indexOf("\n        faction: {", baseStart);
  if (pagesStart < 0 || baseStart < 0 || factionStart < 0) {
    fail("source_idle_prewarm_page_invalid", "source_identity",
      "map base-page declaration cannot be bounded exactly");
  }
  const basePage = mapText.slice(baseStart, factionStart);
  const backgrounds = Array.from(basePage.matchAll(/\bbackgroundUrl:\s*(['"])([^'"]+)\1/g));
  const visualsStart = basePage.indexOf("sceneVisuals: [");
  const visualsEnd = basePage.indexOf("\n            ],", visualsStart);
  if (backgrounds.length !== 1 || visualsStart < 0 || visualsEnd < 0) {
    fail("source_idle_prewarm_page_invalid", "source_identity",
      "map base page lacks one background and one bounded sceneVisuals list");
  }
  const visualBlock = basePage.slice(visualsStart, visualsEnd);
  const visuals = Array.from(visualBlock.matchAll(/\bassetUrl:\s*(['"])([^'"]+)\1/g))
    .map((entry) => entry[2]);
  const assets = [backgrounds[0][2]].concat(visuals);
  if (visuals.length !== 14 || new Set(assets).size !== 15) {
    fail("source_idle_prewarm_asset_set_invalid", "source_identity",
      "base map idle prewarm must project one background and fourteen unique visuals");
  }
  return assets.map((reference) => {
    const assetPath = localWebPath("launcher/web/overlay.html", reference,
      "source_identity");
    if (path.posix.extname(assetPath).toLowerCase() !== ".webp") {
      fail("source_idle_prewarm_asset_type_invalid", "source_identity",
        "base map idle prewarm contains a non-WebP asset", { reference, assetPath });
    }
    return assetPath;
  });
}

function parseFontManifest(root, expectedFontUrls) {
  const relativePath = "launcher/web/assets/fonts/font-pack-manifest.json";
  let manifest;
  try { manifest = JSON.parse(exactText(root, relativePath,
    "source_font_manifest_invalid").replace(/^\uFEFF/, "")); } catch (_error) { manifest = null; }
  if (!manifest || manifest.schemaVersion !== 1 || !Evidence.isPlainObject(manifest.groups)) {
    fail("source_font_manifest_invalid", "source_identity",
      "font-pack manifest is missing or unsupported");
  }
  const resources = [];
  Object.keys(manifest.groups).forEach((groupName) => {
    const group = manifest.groups[groupName];
    if (!Evidence.isPlainObject(group) || !Array.isArray(group.files)) {
      fail("source_font_manifest_invalid", "source_identity",
        "font-pack group lacks a files array", { groupName });
    }
    group.files.forEach((entry) => {
      const name = String(entry && entry.name || "");
      if (!/^[A-Za-z0-9._-]+\.(?:ttf|otf|woff2)$/.test(name)
          || path.basename(name) !== name || !Number.isSafeInteger(entry.bytes)
          || entry.bytes < 1 || !HEX64.test(String(entry.sha256 || ""))
          || typeof entry.shippedFallback !== "boolean" || !Array.isArray(entry.urls)
          || entry.urls.length < 1) {
        fail("source_font_manifest_invalid", "source_identity",
          "font-pack file declaration is malformed", { groupName, name });
      }
      resources.push({ group: groupName, name,
        url: "https://cfn-fonts.local/" + name, bytes: entry.bytes,
        sha256: entry.sha256, shippedFallback: entry.shippedFallback });
    });
  });
  if (!resources.length || new Set(resources.map((entry) => entry.name)).size !== resources.length
      || Evidence.canonicalJson(resources.map((entry) => entry.url).sort())
        !== Evidence.canonicalJson(expectedFontUrls.slice().sort())) {
    fail("source_font_css_projection_invalid", "source_identity",
      "CSS font URLs and font-pack manifest are not one exact set");
  }
  return resources;
}

function validateIconManifest(root) {
  const relativePath = "launcher/web/icons/manifest.json";
  let manifest;
  try { manifest = JSON.parse(exactText(root, relativePath,
    "source_icon_manifest_invalid").replace(/^\uFEFF/, "")); } catch (_error) { manifest = null; }
  if (!Evidence.isPlainObject(manifest) || !Object.keys(manifest).length
      || Object.keys(manifest).some((name) => !name.trim()
        || !Evidence.isPlainObject(manifest[name]))) {
    fail("source_icon_manifest_invalid", "source_identity",
      "icon manifest is not one non-empty exact object");
  }
  return manifest;
}

function assertDeclaredLazyWeb(root) {
  const registry = fs.readFileSync(path.join(root, "launcher", "web", "modules",
    "panels-lazy-registry.js"), "utf8");
  const crafting = fs.readFileSync(path.join(root, "launcher", "web", "modules",
    "crafting.js"), "utf8");
  const craftingBlock = /Panels\.registerLazy\('crafting',([\s\S]*?)\bnoop\);/.exec(registry);
  const organizerBlock = /var ORGANIZER_DEPS\s*=\s*\[([\s\S]*?)\];/.exec(crafting);
  const craftingRefs = craftingBlock && quotedModuleReferences(craftingBlock[1]);
  const organizerRefs = organizerBlock && quotedModuleReferences(organizerBlock[1]);
  if (!craftingBlock || !organizerBlock
      || Evidence.canonicalJson(craftingRefs) !== Evidence.canonicalJson(CRAFTING_LAZY_WEB)
      || Evidence.canonicalJson(organizerRefs) !== Evidence.canonicalJson(ORGANIZER_LAZY_WEB)) {
    fail("source_dependency_declaration_mismatch", "source_identity",
      "production Crafting/organizer lazy declarations differ from the exact audited inventory");
  }
  return { crafting: craftingRefs, organizer: organizerRefs };
}

function craftingDataFiles(root) {
  const list = "data/crafting/list.xml";
  const text = fs.readFileSync(path.join(root, ...list.split("/")), "utf8");
  const output = [list];
  const pattern = /<list>([^<]+)<\/list>/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    const name = match[1].trim();
    if (!name || /[\\/:*?"<>|]/.test(name)) {
      fail("source_data_list_invalid", "source_identity",
        "Crafting list.xml contains an unsafe data child", { name });
    }
    output.push("data/crafting/" + name + ".json");
  }
  if (output.length < 2 || new Set(output).size !== output.length) {
    fail("source_data_list_invalid", "source_identity",
      "Crafting list.xml is empty or duplicated");
  }
  return output;
}

function referencedXmlDataFiles(root, listPath, basePath, tags, contractName) {
  const text = exactText(root, listPath, "source_data_list_invalid");
  const output = [listPath];
  const counts = {};
  tags.forEach((tag) => { counts[tag] = 0; });
  const pattern = new RegExp("<(" + tags.join("|") + ")>([^<]+)</\\1>", "g");
  let match;
  while ((match = pattern.exec(text)) !== null) {
    const tag = match[1];
    const name = match[2].trim();
    if (!/^[^\\/:*?\"<>|]+\.xml$/i.test(name) || name === "." || name === "..") {
      fail("source_data_list_invalid", "source_identity",
        contractName + " contains one unsafe XML child", { tag, name });
    }
    counts[tag] += 1;
    output.push(basePath + name);
  }
  if (tags.some((tag) => counts[tag] < 1)
      || new Set(output.map((entry) => entry.toLowerCase())).size !== output.length) {
    fail("source_data_list_invalid", "source_identity",
      contractName + " is empty, incomplete, or duplicated", { counts });
  }
  return output;
}

function itemProjectionDataFiles(root) {
  const items = referencedXmlDataFiles(root, "data/items/list.xml", "data/items/",
    ["itemSets", "items"], "item projection list");
  const mods = referencedXmlDataFiles(root, "data/items/equipment_mods/list.xml",
    "data/items/equipment_mods/", ["uiPresentation", "items"],
    "equipment modifier projection list");
  const output = ["data/equipment/equipment_config.xml"].concat(items, mods);
  if (new Set(output.map((entry) => entry.toLowerCase())).size !== output.length) {
    fail("source_data_list_invalid", "source_identity",
      "item projection data closure contains duplicates");
  }
  return output;
}

function descriptors(root) {
  verifyOverlayStartupInventory(root);
  assertDeclaredLazyWeb(root);
  const styles = verifyOverlayStyleInventory(root);
  const allStyles = styles.overlayStyles.concat(styles.imports);
  const conditional = deriveConditionalWebResources(root, allStyles);
  const overlayText = exactText(root, "launcher/web/overlay.html",
    "source_idle_prewarm_declaration_invalid");
  const idlePrewarm = deriveIdlePrewarmResources(root, overlayText);
  parseFontManifest(root, conditional.fontUrls);
  validateIconManifest(root);
  RuntimeProducer.verifyBuildFileInventory(root);
  const shared = OVERLAY_STARTUP_WEB.filter((entry) => CRAFTING_LAZY_WEB.includes(entry));
  if (Evidence.canonicalJson(shared)
      !== Evidence.canonicalJson(["launcher/web/modules/asset-timeline.js"])) {
    fail("source_dependency_declaration_mismatch", "source_identity",
      "Crafting startup/lazy overlap differs from the one exact shared producer", { shared });
  }
  const web = OVERLAY_STARTUP_WEB.concat([LAZY_REGISTRY_WEB],
    CRAFTING_LAZY_WEB.filter((entry) => !OVERLAY_STARTUP_WEB.includes(entry)),
    ORGANIZER_LAZY_WEB.filter((entry) => !OVERLAY_STARTUP_WEB.includes(entry)
      && !CRAFTING_LAZY_WEB.includes(entry)), styles.overlayStyles, styles.imports);
  if (new Set(web).size !== web.length) {
    fail("source_dependency_declaration_mismatch", "source_identity",
      "Crafting Web inventory contains unexpected duplicates");
  }
  const all = [
    { role: "page", relativePath: "launcher/web/overlay.html" },
    ...OVERLAY_STARTUP_WEB.map((relativePath) => ({ role: CRAFTING_LAZY_WEB.includes(relativePath)
      ? "overlay_startup_crafting_web" : "overlay_startup_web", relativePath })),
    { role: "lazy_registry", relativePath: LAZY_REGISTRY_WEB },
    ...CRAFTING_LAZY_WEB.filter((entry) => !OVERLAY_STARTUP_WEB.includes(entry))
      .map((relativePath) => ({ role: "crafting_lazy_web", relativePath })),
    ...ORGANIZER_LAZY_WEB.filter((entry) => !OVERLAY_STARTUP_WEB.includes(entry)
      && !CRAFTING_LAZY_WEB.includes(entry))
      .map((relativePath) => ({ role: "organizer_lazy_web", relativePath })),
    ...styles.overlayStyles.map((relativePath) => ({ role: "overlay_stylesheet", relativePath })),
    ...styles.imports.map((relativePath) => ({ role: "panels_import_stylesheet", relativePath })),
    ...idlePrewarm.map((relativePath) => ({ role: "idle_prewarm_image", relativePath })),
    ...conditional.assetPaths.map((relativePath) => ({ role: "css_conditional_asset", relativePath })),
    { role: "font_pack_manifest", relativePath: "launcher/web/assets/fonts/font-pack-manifest.json" },
    { role: "icon_manifest", relativePath: "launcher/web/icons/manifest.json" },
    ...HOST_FILES.map((relativePath) => ({ role: "host_source", relativePath })),
    ...RuntimeProducer.BUILD_FILES,
    ...AS2_FILES.map((relativePath) => ({ role: "as2_source", relativePath })),
    ...craftingDataFiles(root).map((relativePath) => ({ role: "crafting_data", relativePath })),
    ...itemProjectionDataFiles(root)
      .map((relativePath) => ({ role: "item_projection_data", relativePath })),
    ...FIXED_SWF.map((relativePath) => ({ role: "production_swf", relativePath })),
  ];
  if (new Set(all.map((entry) => entry.relativePath.toLowerCase())).size !== all.length) {
    fail("source_inventory_duplicate", "source_identity",
      "Crafting production closure contains duplicate paths");
  }
  return all;
}

function exactFile(root, descriptor) {
  const canonicalRoot = path.resolve(root);
  const absolute = path.resolve(canonicalRoot,
    descriptor.relativePath.replace(/\//g, path.sep));
  const relative = normalize(path.relative(canonicalRoot, absolute));
  if (relative !== normalize(descriptor.relativePath) || relative.startsWith("../")) {
    fail("source_asset_path_escape", "source_identity",
      "production source asset escaped the repository root", descriptor);
  }
  let stat;
  let real;
  try {
    stat = fs.lstatSync(absolute);
    real = fs.realpathSync.native(absolute);
  } catch (_error) {
    fail("source_asset_missing", "source_identity",
      "required Crafting production asset is missing", descriptor);
  }
  if (!stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== absolute.toLowerCase()) {
    fail("source_asset_not_regular", "source_identity",
      "required Crafting production asset is not one exact regular file", descriptor);
  }
  const bytes = fs.readFileSync(absolute);
  return { role: descriptor.role, locator: "root:" + normalize(descriptor.relativePath),
    bytes: bytes.length, sha256: Evidence.sha256Bytes(bytes) };
}

function gitHead(root) {
  const result = childProcess.spawnSync("git", ["rev-parse", "HEAD"], {
    cwd: root, encoding: "utf8", windowsHide: true, maxBuffer: 1024 * 1024,
  });
  const head = String(result.stdout || "").trim().toLowerCase();
  if (result.status !== 0 || !GIT_OID.test(head)) {
    fail("source_git_head_invalid", "source_identity",
      "current repository HEAD could not be bound");
  }
  return head;
}

function fingerprintPayload(value) {
  return { schema: value.schema, capturedAt: value.capturedAt,
    root: value.root, head: value.head, files: value.files,
    producerInputs: value.producerInputs, as2AlgorithmContract: value.as2AlgorithmContract };
}

function validateSourceFingerprint(value) {
  if (!Evidence.isPlainObject(value) || value.schema !== SOURCE_FINGERPRINT_SCHEMA
      || !Number.isFinite(Date.parse(value.capturedAt)) || path.resolve(value.root || "") !== value.root
      || !GIT_OID.test(String(value.head || "")) || !Array.isArray(value.files)
      || !value.files.length || new Set(value.files.map((entry) => entry && entry.locator)).size !== value.files.length
      || value.files.some((entry) => !Evidence.isPlainObject(entry)
        || !/^[a-z0-9_]+$/.test(String(entry.role || ""))
        || !/^root:[^\\]+$/.test(String(entry.locator || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1
        || !HEX64.test(String(entry.sha256 || "")))) return false;
  const expectedAlgorithmContract = { schema: AS2_ALGORITHM_CONTRACT_SCHEMA,
    functions: AS2_ALGORITHM_EXPECTATIONS.map((entry) => ({
      locator: "root:" + entry.relativePath, className: entry.className,
      functionName: entry.functionName, modifiers: entry.modifiers,
      classDepth: entry.classDepth, memberDepth: entry.memberDepth, nestedFunctionCount: 0,
      signatureTokenCount: entry.signatureTokenCount,
      signatureTokenSha256: entry.signatureTokenSha256,
      returnTokenCount: entry.returnTokenCount, returnTokenSha256: entry.returnTokenSha256,
      bodyTokenCount: entry.bodyTokenCount, bodyTokenSha256: entry.bodyTokenSha256,
      tokenCount: entry.tokenCount, normalizedTokenSha256: entry.normalizedTokenSha256,
    })) };
  if (!Evidence.isPlainObject(value.as2AlgorithmContract)
      || value.as2AlgorithmContract.schema !== AS2_ALGORITHM_CONTRACT_SCHEMA
      || !Array.isArray(value.as2AlgorithmContract.functions)
      || value.as2AlgorithmContract.functions.length !== AS2_ALGORITHM_EXPECTATIONS.length
      || value.as2AlgorithmContract.functions.some((entry) => !Evidence.isPlainObject(entry)
        || !/^root:[^\\]+$/.test(String(entry.locator || ""))
        || typeof entry.className !== "string" || !entry.className
        || typeof entry.functionName !== "string" || !entry.functionName
        || !Array.isArray(entry.modifiers) || !entry.modifiers.length
        || entry.modifiers.some((modifier) => typeof modifier !== "string" || !modifier)
        || entry.classDepth !== 0 || entry.memberDepth !== 1 || entry.nestedFunctionCount !== 0
        || !Number.isInteger(entry.signatureTokenCount) || entry.signatureTokenCount < 1
        || !HEX64.test(String(entry.signatureTokenSha256 || ""))
        || !Number.isInteger(entry.returnTokenCount) || entry.returnTokenCount < 1
        || !HEX64.test(String(entry.returnTokenSha256 || ""))
        || !Number.isInteger(entry.bodyTokenCount) || entry.bodyTokenCount < 2
        || !HEX64.test(String(entry.bodyTokenSha256 || ""))
        || !Number.isInteger(entry.tokenCount) || entry.tokenCount < 1
        || !HEX64.test(String(entry.normalizedTokenSha256 || "")))
      || Evidence.canonicalJson(value.as2AlgorithmContract)
        !== Evidence.canonicalJson(expectedAlgorithmContract)) return false;
  try { RuntimeProducer.validateProducerInputsEnvelope(value.producerInputs, value.root); }
  catch (_error) { return false; }
  return value.fingerprintSha256 === Evidence.sha256Text(
    Evidence.canonicalJson(fingerprintPayload(value)));
}

function captureSourceFingerprint(root, capturedAt) {
  const value = { schema: SOURCE_FINGERPRINT_SCHEMA,
    capturedAt: capturedAt || new Date().toISOString(), root: path.resolve(root),
    head: gitHead(root), files: descriptors(root).map((entry) => exactFile(root, entry)),
    producerInputs: RuntimeProducer.currentProducerInputs(root),
    as2AlgorithmContract: captureAs2AlgorithmContract(root) };
  value.fingerprintSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(fingerprintPayload(value)));
  return value;
}

function stableFingerprint(value) {
  return { root: value.root, head: value.head, files: value.files,
    producerInputs: value.producerInputs, as2AlgorithmContract: value.as2AlgorithmContract };
}

function assertSameFingerprint(expected, actual, phase) {
  if (!validateSourceFingerprint(expected) || !validateSourceFingerprint(actual)) {
    fail("source_fingerprint_invalid", phase || "source_identity",
      "production source fingerprint is malformed");
  }
  if (Evidence.canonicalJson(stableFingerprint(expected))
      !== Evidence.canonicalJson(stableFingerprint(actual))) {
    fail("source_fingerprint_drift", phase || "source_identity",
      "production Web/Host/AS2/data/SWF bytes changed during the journey");
  }
  return actual;
}

function sealSourceClosure(records) {
  const value = { schema: SOURCE_CLOSURE_SCHEMA, root: records[0] && records[0].fingerprint.root,
    requiredPhases: REQUIRED_SOURCE_PHASES.slice(), records: JSON.parse(JSON.stringify(records || [])) };
  value.closureSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function validateSourceClosure(value) {
  if (!Evidence.isPlainObject(value) || value.schema !== SOURCE_CLOSURE_SCHEMA
      || path.resolve(value.root || "") !== value.root
      || JSON.stringify(value.requiredPhases) !== JSON.stringify(REQUIRED_SOURCE_PHASES)
      || !Array.isArray(value.records) || value.records.length !== REQUIRED_SOURCE_PHASES.length) return false;
  const unsigned = Object.assign({}, value);
  delete unsigned.closureSha256;
  if (value.closureSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) return false;
  let baseline = null;
  return value.records.every((record, index) => {
    if (!Evidence.isPlainObject(record) || record.phase !== REQUIRED_SOURCE_PHASES[index]
        || !Number.isFinite(Date.parse(record.observedAt))
        || !validateSourceFingerprint(record.fingerprint)
        || record.fingerprint.root !== value.root) return false;
    if (!baseline) baseline = record.fingerprint;
    return Evidence.canonicalJson(stableFingerprint(record.fingerprint))
      === Evidence.canonicalJson(stableFingerprint(baseline));
  });
}

function assertCurrentSourceClosure(root, closure) {
  if (!validateSourceClosure(closure) || path.resolve(closure.root) !== path.resolve(root)) {
    fail("source_closure_invalid", "source_identity",
      "production source phase closure is malformed, foreign-rooted, or drifting");
  }
  return assertSameFingerprint(closure.records[0].fingerprint,
    captureSourceFingerprint(root), "source_current_tree");
}

function publicCandidateIdentity(identity) {
  return { runtimeMode: identity.runtimeMode, processPath: path.resolve(identity.processPath || ""),
    coreSha256: identity.coreSha256, buildIdentity: identity.buildIdentity,
    payloadClosure: identity.payloadClosure };
}

function bindSourceClosure(fingerprint, identity, runId, candidateRoot, candidateProducer) {
  const value = { schema: SOURCE_BINDING_SCHEMA, runId,
    sourceRoot: fingerprint.root, candidateRoot: path.resolve(candidateRoot),
    sourceFingerprintSha256: fingerprint.fingerprintSha256,
    producerInputsSha256: fingerprint.producerInputs && fingerprint.producerInputs.inputsSha256,
    candidateIdentitySha256: Evidence.sha256Text(
      Evidence.canonicalJson(publicCandidateIdentity(identity))),
    candidateProducerSha256: candidateProducer && candidateProducer.evidenceSha256 };
  value.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function webFiles(closure) {
  const fingerprint = closure.records ? closure.records[0].fingerprint : closure;
  return fingerprint.files.filter((entry) =>
    ["page", "overlay_startup_web", "overlay_startup_crafting_web", "lazy_registry",
      "crafting_lazy_web", "organizer_lazy_web", "overlay_stylesheet",
      "panels_import_stylesheet"].includes(entry.role));
}

function scriptFiles(closure) {
  return webFiles(closure).filter((entry) => entry.role !== "page"
    && entry.locator.endsWith(".js"));
}

function styleFiles(closure) {
  return webFiles(closure).filter((entry) => entry.locator.endsWith(".css"));
}

function roleFiles(closure, role) {
  const fingerprint = closure.records ? closure.records[0].fingerprint : closure;
  return fingerprint.files.filter((entry) => entry.role === role);
}

function urlForWebFile(entry) {
  return "https://overlay.local/" + entry.locator.slice("root:launcher/web/".length);
}

function idlePrewarmFiles(closure) { return roleFiles(closure, "idle_prewarm_image"); }
function cssConditionalAssetFiles(closure) { return roleFiles(closure, "css_conditional_asset"); }

function expectedStaticResourceSet(closure) {
  return [{ url: "https://overlay.local/overlay.html", resourceType: "Document",
    origin: "https://overlay.local", mimeType: "text/html" }]
    .concat(scriptFiles(closure).map((entry) => ({ url: urlForWebFile(entry),
      resourceType: "Script", origin: "https://overlay.local", mimeType: "text/javascript" })))
    .concat(styleFiles(closure).map((entry) => ({ url: urlForWebFile(entry),
      resourceType: "Stylesheet", origin: "https://overlay.local", mimeType: "text/css" })))
    .concat(idlePrewarmFiles(closure).map((entry) => ({ url: urlForWebFile(entry),
      resourceType: "Image", origin: "https://overlay.local", mimeType: "image/webp" })));
}

function mimeTypeForAsset(locator) {
  const extension = path.posix.extname(locator).toLowerCase();
  if (extension === ".png") return "image/png";
  if ([".jpg", ".jpeg"].includes(extension)) return "image/jpeg";
  if (extension === ".svg") return "image/svg+xml";
  if (extension === ".webp") return "image/webp";
  return "";
}

function cssConditionalResourceSet(closure) {
  return cssConditionalAssetFiles(closure).map((entry) => ({ locator: entry.locator,
    url: urlForWebFile(entry), resourceType: "Image", origin: "https://overlay.local",
    mimeType: mimeTypeForAsset(entry.locator), sha256: entry.sha256, bytes: entry.bytes }));
}

function oneRoleFile(closure, role, code) {
  const matches = roleFiles(closure, role);
  if (matches.length !== 1) {
    fail(code, "source_identity", "source closure lacks one exact manifest role", { role });
  }
  return matches[0];
}

function assertBoundCurrentFile(root, closure, role, relativePath, code) {
  const bound = oneRoleFile(closure, role, code);
  const current = exactFile(root, { role, relativePath });
  if (Evidence.canonicalJson(bound) !== Evidence.canonicalJson(current)) {
    fail(code, "source_identity", "current manifest bytes differ from the source closure", { role });
  }
  return bound;
}

function fontEnvironmentRoot(root, environment) {
  const localAppData = String(environment && environment.LOCALAPPDATA || "").trim();
  return localAppData ? path.resolve(localAppData, "CF7FlashNight", "fonts")
    : path.resolve(root, "launcher", "web", "assets", "fonts");
}

function captureFontEnvironment(root, closure, environment) {
  const manifest = assertBoundCurrentFile(root, closure, "font_pack_manifest",
    "launcher/web/assets/fonts/font-pack-manifest.json", "source_font_manifest_mismatch");
  const stylePaths = styleFiles(closure).map((entry) => entry.locator.slice("root:".length));
  const conditional = deriveConditionalWebResources(root, stylePaths);
  const resources = parseFontManifest(root, conditional.fontUrls);
  const mappingRoot = fontEnvironmentRoot(root, environment || process.env);
  const installed = [];
  resources.forEach((entry) => {
    const filePath = path.resolve(mappingRoot, entry.name);
    let stat;
    let real;
    try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
    catch (_error) { stat = null; real = null; }
    if (!stat) return;
    if (!stat.isFile() || stat.isSymbolicLink() || path.resolve(real) !== filePath) {
      fail("font_environment_file_invalid", "source_identity",
        "mapped manifest font is not one exact regular file", { name: entry.name });
    }
    const bytes = fs.readFileSync(filePath);
    const digest = Evidence.sha256Bytes(bytes);
    if (bytes.length !== entry.bytes || digest !== entry.sha256) {
      fail("font_environment_file_mismatch", "source_identity",
        "mapped manifest font differs from its declared bytes", { name: entry.name });
    }
    installed.push({ name: entry.name, url: entry.url, path: filePath,
      bytes: bytes.length, sha256: digest });
  });
  const value = { schema: FONT_ENVIRONMENT_SCHEMA, mappingRoot,
    manifestLocator: manifest.locator, manifestSha256: manifest.sha256, installed };
  value.environmentSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function verifyFontEnvironment(root, closure, evidence, environment) {
  const current = captureFontEnvironment(root, closure, environment || process.env);
  if (!Evidence.isPlainObject(evidence) || evidence.schema !== FONT_ENVIRONMENT_SCHEMA
      || Evidence.canonicalJson(current) !== Evidence.canonicalJson(evidence)) {
    fail("font_environment_mismatch", "source_identity",
      "loaded font mapping differs from the current successful manifest subset");
  }
  return evidence;
}

function iconFrameUri(frame) { return frame && (frame.uri || frame.file || frame.filename) || null; }
function normalizedIconFrames(entry) {
  const raw = Array.isArray(entry.timelineFrames) && entry.timelineFrames.length
    ? entry.timelineFrames : Array.isArray(entry.frames) ? entry.frames : [];
  const frames = [];
  const seen = new Set();
  raw.forEach((frame, index) => {
    const uri = iconFrameUri(frame);
    if (!uri) return;
    const number = frame.frame || frame.index || index + 1;
    frames.push(Object.assign({}, frame, { frame: number, uri }));
    seen.add(String(number));
  });
  if (entry.f1 && !seen.has("1")) frames.unshift({ frame: 1, uri: entry.f1 });
  if (entry.f2 && !seen.has("2")) frames.push({ frame: 2, uri: entry.f2 });
  return frames.sort((left, right) => Number(left.frame || 0) - Number(right.frame || 0));
}
function normalizedLayerFrames(layer) {
  let raw = Array.isArray(layer && layer.timelineFrames) && layer.timelineFrames.length
    ? layer.timelineFrames : Array.isArray(layer && layer.frames) ? layer.frames : [];
  if ((!raw || !raw.length) && layer && layer.export) {
    raw = Array.isArray(layer.export.timelineFrames) && layer.export.timelineFrames.length
      ? layer.export.timelineFrames : Array.isArray(layer.export.frames) ? layer.export.frames : [];
  }
  return (raw || []).map((frame, index) => Object.assign({}, frame, {
    frame: frame.frame || frame.index || index + 1, uri: iconFrameUri(frame),
  })).filter((frame) => frame.uri)
    .sort((left, right) => Number(left.frame || 0) - Number(right.frame || 0));
}
function distinctIconFrames(frames) {
  const keys = ["uri", "cropX", "cropY", "cropWidth", "cropHeight", "canvasWidth", "canvasHeight"];
  return new Set(frames.map((frame) => Evidence.canonicalJson(keys.map((key) =>
    Object.prototype.hasOwnProperty.call(frame, key) ? frame[key] : null)))).size;
}
function iconEntryUris(entry) {
  if (entry.format === "webp-animated") {
    const frames = normalizedIconFrames(entry);
    const uri = entry.uri || frames[0] && frames[0].uri || entry.f1;
    return uri ? [uri] : [];
  }
  const nested = Evidence.isPlainObject(entry.nestedAnimation) ? entry.nestedAnimation : null;
  const layers = nested && Array.isArray(nested.layers) ? nested.layers : [];
  const base = nested && (typeof nested.base === "string" ? nested.base
    : nested.base && nested.base.uri) || entry.f1 || null;
  if (layers.length && base) {
    const values = [base];
    layers.forEach((layer) => normalizedLayerFrames(layer).forEach((frame) => values.push(frame.uri)));
    return Array.from(new Set(values));
  }
  const frames = normalizedIconFrames(entry);
  if (!frames.length) return [];
  const staticPlayback = ["static", "static-first-frame"].includes(entry.playback);
  const animated = !staticPlayback && distinctIconFrames(frames) > 1
    && (entry.animated === true || !!entry.playback);
  return Array.from(new Set((animated ? frames : frames.slice(0, 1)).map((frame) => frame.uri)));
}

function iconResourceSetForNames(root, closure, iconNames) {
  const manifestFile = assertBoundCurrentFile(root, closure, "icon_manifest",
    "launcher/web/icons/manifest.json", "source_icon_manifest_mismatch");
  const manifest = validateIconManifest(root);
  const names = [];
  (iconNames || []).forEach((value) => {
    const name = String(value || "").trim();
    if (name && !names.includes(name)) names.push(name);
  });
  if (!names.length) fail("dynamic_icon_authority_empty", "source_identity",
    "authoritative Crafting/Inventory snapshots expose no icon names");
  const bindings = [];
  const resourceByUrl = new Map();
  names.forEach((iconName) => {
    const entry = manifest[iconName];
    if (!Evidence.isPlainObject(entry)) {
      fail("dynamic_icon_name_unbound", "source_identity",
        "authoritative Crafting/Inventory icon is absent from the manifest", { iconName });
    }
    const uris = iconEntryUris(entry);
    if (!uris.length) fail("dynamic_icon_entry_empty", "source_identity",
      "authoritative icon resolves to no image", { iconName });
    const urls = [];
    uris.forEach((uri) => {
      const normalized = String(uri || "").replace(/\\/g, "/");
      if (!normalized || normalized.startsWith("/") || /^[a-z][a-z0-9+.-]*:/i.test(normalized)
          || normalized.split("/").some((part) => !part || part === "." || part === "..")
          || ![".png", ".webp"].includes(path.posix.extname(normalized).toLowerCase())) {
        fail("dynamic_icon_uri_invalid", "source_identity",
          "manifest icon URI is not one bounded PNG/WebP", { iconName, uri });
      }
      const relativePath = "launcher/web/icons/" + normalized;
      const file = exactFile(root, { role: "dynamic_icon_asset", relativePath });
      const url = "https://overlay.local/icons/" + normalized;
      const resource = { locator: file.locator, url, resourceType: "Image",
        origin: "https://overlay.local", mimeType: path.posix.extname(normalized).toLowerCase()
          === ".png" ? "image/png" : "image/webp", sha256: file.sha256, bytes: file.bytes };
      urls.push(url);
      if (!resourceByUrl.has(url)) resourceByUrl.set(url, resource);
    });
    bindings.push({ iconName, urls });
  });
  return { schema: ICON_PROJECTION_SCHEMA, manifestLocator: manifestFile.locator,
    manifestSha256: manifestFile.sha256, iconNames: names, bindings,
    resources: Array.from(resourceByUrl.values()).sort((left, right) => left.url.localeCompare(right.url)) };
}

module.exports = {
  AS2_ALGORITHM_CONTRACT_SCHEMA, AS2_ALGORITHM_EXPECTATIONS, AS2_FILES,
  CRAFTING_LAZY_WEB, FIXED_SWF, FONT_ENVIRONMENT_SCHEMA, HOST_FILES,
  ICON_PROJECTION_SCHEMA, LAZY_REGISTRY_WEB, LOADED_SCHEMA,
  OVERLAY_STARTUP_WEB, OVERLAY_STYLE_WEB, PANELS_IMPORT_STYLE_WEB,
  ORGANIZER_LAZY_WEB, REQUIRED_SOURCE_PHASES, SOURCE_BINDING_SCHEMA,
  SOURCE_CLOSURE_SCHEMA, SOURCE_FINGERPRINT_SCHEMA,
  assertCurrentSourceClosure, assertSameFingerprint, bindSourceClosure,
  assertAs2FunctionExpectation, captureAs2AlgorithmContract, captureSourceFingerprint, descriptors,
  extractAs2FunctionContract, publicCandidateIdentity, scriptFiles, styleFiles, tokenizeAs2,
  captureFontEnvironment, cssConditionalResourceSet, expectedStaticResourceSet,
  iconResourceSetForNames, idlePrewarmFiles, verifyFontEnvironment,
  sealSourceClosure, validateSourceClosure, validateSourceFingerprint, webFiles,
  captureCandidateProducerBinding: RuntimeProducer.captureCandidateProducerBinding,
  verifyCandidateProducerBinding: RuntimeProducer.verifyCandidateProducerBinding,
  CANDIDATE_PRODUCER_SCHEMA: RuntimeProducer.CANDIDATE_PRODUCER_SCHEMA,
};
