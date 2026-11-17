# 61式胸甲“机制”单步直绑与按实例应急注射：正式发布

本批围绕 `#61` 完成 UI/交互重构与按胸甲物品实例持久化，并合入最新主线完成 Runtime v2 双故障域正式发布（同时承接 `#276` 补弹机制收口）。冻结源码为 `0f838a09a216a226fd1cfb165a06d7ac175cc38a`，受控标签为 `runtime-build-v2/20261117-ti61-mechanism-instance-v1`；机器身份、四域哈希、回退点与限制边界见[机器回执](../evidence/ti61-mechanism-instance-20261117/release.json)。

UI 方面，仅选中 `统合61式胸甲` 或 `钛合金61式胸甲` 时在装备调制显示第五页签“机制”（其余装备维持四页签），移除“定制 → 外观幻化”空占位及“机制”页底部确认栏；调制页头新增可点击 `应急药 · ...` 摘要胶囊，左侧药剂栏已绑槽左上角挂零占位 `应急` 角标，支持右栏 2×4 图标药槽与左栏可用药剂格双栏单步直绑、切换及再点/停用解除，遇到 `needs_reconcile` 冻结槽位并保持关闭围栏与“重新确认结果”。

数据与权威方面，应急药授权由玩家全局 `_saveExt.emergencyInjection` 迁至每件 61 胸甲实例的 `item.value.emergencyInjection = {version:1, enabled, physicalSlot, itemKey}`，穿戴与背包各自独立记忆；`configureEmergencyInjection` 新增显式 `chestTarget`（`loadout` 校验上装槽位与 `loadoutRevision` 且 `affectedBackpackSlot=-1`；`backpack` 校验容器租约且 `affectedBackpackSlot=slot`）与 `targetEmergencyInjection` 对账。穿戴切换自动切换生效槽位，背包胸甲期间若对应药槽换物只在只读报 `item_changed` 并于穿戴刷新时立即撤权记脏；玩家单位级危机记忆仍跨胸甲保持；存档修复分层纳入 `inventory/*/value/emergencyInjection/itemKey`（L1 / Clear）。

本机已登记 X509 `builder-local-b / physical-host-b` 与 [GitHub Hosted OIDC/Sigstore 独立构建 44084543963](https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/44084543963) 对同一 43 文件闭包（`payloadClosureHash`: `1066111B3503BB94F0638F85697F90C3A22D5F5F31DED1491ACD21833CFDC96D`）达成双签名、双故障域共识，production policy **50/50**（receipt SHA-256 `A3A4A0435A5EAD16CF7BEEF58402079262FD46A61F528C14C44D1B2F085A5EBC`）。唯一 writer 完成正式替换、strict v2 consensus 与 `CRAZYFLASHER7MercenaryEmpire.exe --verify-only` 自检；正式 Core DLL 为 `A50CD02C48091113FDA769506F289E84E81B2882DA3045C43B0E030E111F4F89`，回退目录保留在 `tmp/runtime-promotions/20261117T124906143Z-611f21e6c17145078572c11fce4d846a/previous`。

测试方面，AS2 `emergency-injection` 73/73、`equipment-tuning` 128/128+194/194、`character-build`（UTF-8 内存加载完整运行）8 套含 `CharacterBuildServiceTest` 241/241 零失败，`asLoader` 三模块编译 0/0（774 类/107 继承边缘）；C# 目标域 `CharacterBuild*` 352/352、`EquipmentTuning*` 215/215、`Save*/RepairPolicy*` 211/211 零失败（全量 8422 通过 / 128 失败 / 31 跳过，128 项属 5 个无关既有测试类，不称全量全绿）；`tools/cf7-save-repair` 45/45；Web mock harness 全过。物理键鼠与按实例切装的新真机体验随本次更新纳入后续测试员常规回归，不以自动化测试代签真人手感。
