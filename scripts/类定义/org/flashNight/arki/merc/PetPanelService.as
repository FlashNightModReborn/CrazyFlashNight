/**
 * 文件：org/flashNight/arki/merc/PetPanelService.as
 * 说明：WebView 战宠面板的 AS2 端桥。
 *
 * 同步管道（与 ArenaPanelService / MapPanelService 同构）：
 *   Web → C# PetTask → Flash gameCommands:
 *     petSnapshot       — 返回全部宠物信息快照 + 玩家状态
 *     petAdopt          — 领养宠物（petId）
 *     petDeploy         — 出战/休息切换（slotIndex）
 *     petAdvance        — 执行进阶（slotIndex, schemeName）
 *     petPreviewAdvance — 预览进阶效果（消耗、属性变化）
 *     petExpandSlot     — 扩充宠物格子
 *     petRename         — 重命名宠物
 *     petTooltip        — 获取进阶方案 tooltip 详情
 *     petWeaponTooltip  — 获取托管/预设/背包候选长枪的实例级完整注释
 *     petEquipWeapon    — 将背包长枪交付给支持托管武器的战宠
 *     petWithdrawWeapon — 原样取回战宠托管长枪
 *     petPanelOpen      — 面板打开时准备数据
 *     petPanelClose     — 面板关闭时刷新 UI
 *
 * 关键不变量：
 *   - 所有写操作必须通过本桥执行，保证 _root.宠物信息 是唯一数据源
 *   - 响应格式：{ task: "pet_response", callId: callId, success: true/false, ... }
 *   - 使用 LiteJSON 序列化（与 ArenaPanelService 相同）
 */
import LiteJSON;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.merc.ManagedLongGunService;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.arki.merc.PetPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["petSnapshot"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleSnapshot(params);
        };
        // petAdoptList 已移除：商城静态目录改由 C# PetTask 直读 pets.xml 回答（web 直连，不经 Flash）。
        // 见 docs/战宠pets.xml-AS2去常驻化-bundle迁移方案-2026-06-02.md。
        _root.gameCommands["petAdopt"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleAdopt(params);
        };
        _root.gameCommands["petDeploy"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleDeploy(params);
        };
        _root.gameCommands["petAdvance"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleAdvance(params);
        };
        _root.gameCommands["petPreviewAdvance"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handlePreviewAdvance(params);
        };
        _root.gameCommands["petExpandSlot"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleExpandSlot(params);
        };
        _root.gameCommands["petRename"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleRename(params);
        };
        _root.gameCommands["petTooltip"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleTooltip(params);
        };
        _root.gameCommands["petWeaponTooltip"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleWeaponTooltip(params);
        };
        _root.gameCommands["petRestoreStamina"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleRestoreStamina(params);
        };
        _root.gameCommands["petEquipWeapon"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleEquipWeapon(params);
        };
        _root.gameCommands["petWithdrawWeapon"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleWithdrawWeapon(params);
        };
        _root.gameCommands["petLevelUp"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleLevelUp(params);
        };
        _root.gameCommands["petDelete"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleDelete(params);
        };
        _root.gameCommands["petPanelOpen"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handlePanelOpen(params);
        };
        _root.gameCommands["petPanelClose"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handlePanelClose(params);
        };

        // 世界内招募（旧 Symbol 2035 宠物分支）web 等价。NPC 入口走 MercPanelService.openWebHire
        // （判 kind=pet），确认写回到此。设计见 docs/佣兵世界内雇佣-Web迁移-架构设计-2026-06-27.md。
        _root.gameCommands["petWorldAdopt"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleWorldAdopt(params);
        };

        _inited = true;
    }

    // ═══════════════════════════════════════════════════════════
    // handleSnapshot — 返回全部宠物状态快照
    // ═══════════════════════════════════════════════════════════
    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        var pets:Array = [];
        var 宠物信息:Array = _root.宠物信息;
        // 同一轮只签发一次背包 lease。若每只 T800 各取一次快照，后一个会令前一个候选
        // 的 source lease 立即过期，多 T800 存档会出现“看得见但无法交付”。
        var weaponBagSnapshot:Object = ManagedLongGunService.hasSupportedPet(宠物信息)
            && _root.物品栏 != undefined && _root.物品栏.背包 != null
            ? InventoryPanelService.buildExternalSnapshot("背包", 0, 50) : null;

        for (var i:Number = 0; i < 宠物信息.length; i++) {
            var info:Array = 宠物信息[i];
            if (info == undefined || info.length < 5) continue;
            var petDef:Object = _root.宠物库[info[0]];
            if (petDef == undefined) continue;

            var petEntry:Object = {
                slotIndex: i,
                petId: Number(info[0]),
                name: _root.战宠UI函数 != undefined
                    && typeof _root.战宠UI函数.获取宠物显示名 == "function"
                    ? _root.战宠UI函数.获取宠物显示名(i) : String(petDef.Name),
                identifier: String(petDef.Identifier),
                level: Number(info[1]),
                stamina: Number(info[2]),
                xp: 0,
                deployed: Number(info[4]) == 1,
                height: Number(petDef.Height),
                promotions: []
            };

            // 序列化进阶属性 / 提取经验值
            var attrs:Object = info[5];
            var xpFromAttr:Number = 0;
            var xpNeededFromAttr:Number = 0;
            if (attrs != undefined && typeof attrs == "object") {
                xpFromAttr = Number(attrs.宠物升级经验) || 0;
                xpNeededFromAttr = Number(attrs.宠物升级所需经验) || 0;
                var promos:Array = [];
                for (var key:String in attrs) {
                    // 托管快照是 AS2/存档权威，Web 只能读 managedLongGun 安全投影。
                    // 不得经通用进阶属性分支泄漏完整 item.value/mods/lastUpdate。
                    if (key == "托管长枪") continue;
                    var val:Object = attrs[key];
                    if (val != undefined && typeof val == "object") {
                        var promoEntry:Object = { scheme: key };
                        for (var f:String in val) {
                            promoEntry[f] = val[f];
                        }
                        promos.push(promoEntry);
                    }
                }
                petEntry.promotions = promos;
            }

            petEntry.xp = xpFromAttr;
            petEntry.xpNeeded = xpNeededFromAttr > 0 ? xpNeededFromAttr : calcXpForLevel(String(petDef.Identifier), info[1]);
            petEntry.maxStamina = 200;

            // 战斗数值成长展示（敌人属性表插值 + 已达成进阶方案重放，三点采样：
            // 起点 Lv.1 / 当前 / 满级）；属性缺失时不下发，JS 隐藏区块
            var combat:Object = buildCombatStats(String(petDef.Identifier), Number(info[1]), attrs);
            if (combat != undefined) petEntry.combat = combat;

            // 每方案权威完成/锁定状态（替代 JS 端按方案名查 次数 的错误推断；
            // 三件套共用 基础训练.次数 计数，布尔方案查自身标志）
            var statusMap:Object = {};
            var schemeNames:Array = extractPromotionNames(petDef.Promotion);
            // 本宠物专属方案子集（per-pet 进阶方案，还原原始设计）：用于前置档判定，
            // 中/强体质宠（无基础训练/强化药剂）据此跳过其不具备的低阶前置。
            var petSchemeSet:Object = filterSchemeSet(schemeNames);
            for (var sIdx:Number = 0; sIdx < schemeNames.length; sIdx++) {
                var sNm:String = String(schemeNames[sIdx]);
                var scDef:Object = _root.战宠进阶函数[sNm];
                if (scDef == undefined) continue;
                if (typeof scDef.执行 != "function") continue; // 与 schemesMap 同口径，跳过 凑数组的 等占位方案
                var lockReason:String = schemeLockReason(scDef, attrs, Number(info[1]), petSchemeSet);
                statusMap[sNm] = {
                    completed: isSchemeCompleted(sNm, scDef, attrs),
                    locked: lockReason != "",
                    // 锁定原因细分（""未锁 / "level"等级不足 / "prereq"前置训练未完成）：
                    // 供 JS 区分文案——等级锁显"需Lv.X"，前置锁显"需先完成前置训练"。
                    // 旧实现只下发布尔 locked，JS 一律误显"需Lv.X"（前置未达时玩家明明已够级，困惑）。
                    lockReason: lockReason,
                    // 反复型(开关/购买后开关)：JS 据此渲染为可反复点击的开关按钮，不显示"已完成"。
                    repeatable: isSchemeRepeatable(sNm, scDef),
                    // 购买后开关的前置购买是否完成（纯开关恒 true）：决定显示购买价还是免费开关。
                    purchased: isSchemePurchased(sNm, scDef, attrs)
                };
                // 反复型(开关)方案的描述/状态依赖本宠物属性（发色、淬毒启用…）；schemesMap.desc 用空白
                // dummy ctx 算，会显示"undefined发"或丢失开关状态。这里用真实 ctx 重算 描述（短文且自带状态），
                // 下发 perPetDesc 供 JS 优先采用。描述函数已在内存中，运行时调用无需重发布 SWF。
                if (statusMap[sNm].repeatable) {
                    statusMap[sNm].desc = buildSchemePerPetDesc(scDef, info, attrs, petSchemeSet);
                    // 开关类方案的当前开/关（或当前值）状态：供 JS 渲染明确的状态控件
                    // （二元开关→拨动开关亮灭；多值循环→当前值色块 chip），不再让玩家从文案里猜状态。
                    var ts:Object = readToggleState(sNm, attrs);
                    if (ts != undefined) {
                        statusMap[sNm].toggleKind = ts.kind;
                        if (ts.kind == "binary") statusMap[sNm].toggleOn = ts.enabled;
                        else statusMap[sNm].toggleValue = ts.value;
                    }
                }
            }
            petEntry.schemeStatus = statusMap;

            var managedWeapon:Object = ManagedLongGunService.buildPanelState(info, weaponBagSnapshot);
            if (managedWeapon != null) petEntry.managedLongGun = managedWeapon;

            pets.push(petEntry);
        }

        // 宠物库摘要（petLib）已下沉 C# PetTask.pet_lib（web 直读 pets.xml），snapshot 不再序列化下发。
        // 见 docs/战宠pets.xml-AS2去常驻化-bundle迁移方案-2026-06-02.md（真·Phase 2）。

        // 序列化进阶方案数据字段（B1：数值/文本字段下发，逻辑函数 条件/执行 留 AS2）。
        // 这是 JS 进阶列表的权威来源，替代已删除的 pet-data.js SCHEMES（含修正后的累进 次数上限）。
        var schemesMap:Object = {};
        var advFns:Object = _root.战宠进阶函数;
        for (var sName:String in advFns) {
            var sc:Object = advFns[sName];
            if (sc == undefined || typeof sc != "object") continue;
            // 跳过占位/无行为方案（如 凑数组的：执行=null、条件恒 false），它仅为旧 Flash 网格 UI
            // 凑数对齐用。不下发 schemesMap，JS renderPromotions 的 if(!scheme) continue 即自动隐藏，
            // 否则会在大量宠物上渲染出一个点击必返回"条件不满足"的脏"执行"按钮。
            if (typeof sc.执行 != "function") continue;
            var scCtx:Object = { 当前宠物信息: [0, 1, 200, 0, 0, {}], 当前宠物属性: {}, 进阶方案: advFns };
            var scDesc:String = "";
            if (typeof sc.详情页描述 == "function") {
                scDesc = String(sc.详情页描述.call(scCtx));
            } else if (typeof sc.描述 == "function") {
                scDesc = String(sc.描述.call(scCtx));
            } else if (sc.描述 != undefined) {
                scDesc = String(sc.描述);
            }
            // 列表用简介取第一段（<br> 前），与具体宠物无关，对齐旧 pet-data 静态 desc
            var brIdx:Number = scDesc.indexOf("<br>");
            if (brIdx >= 0) scDesc = scDesc.substring(0, brIdx);
            schemesMap[sName] = {
                maxTier: Number(sc.次数上限) || 1,
                gold: Number(sc.消耗金币) || 0,
                kpoint: Number(sc.消耗K点) || 0,
                unlockLevel: Number(sc.解锁等级) || 0,
                buttonText: String(sc.执行按钮文字 || "执行"),
                // 进阶类型："开关"/"购买后开关"（反复型）或 ""（一次性购买/三件套）。
                // 对纯开关，gold 是运行时(每张图)扣费而非升级价，JS 不应据此做购买门槛。
                // 字段优先，缺失回退类内已知集合（帧脚本未重发布时仍正确）。
                type: getSchemeType(sName, sc),
                desc: scDesc
            };
        }

        // 商城分类名 + 网格已下沉 C#（PetTask.adopt_list 直读 pets.xml），snapshot 不再下发 categories。
        // 涨价覆盖：C# adopt_list/pet_lib 只知 pets.xml 基础价；IncreasePrice>0 的宠物当前价含已购次数，
        // 仅 AS2 知晓（存档态），故在此随 snapshot 下发当前价，web 商城网格据此覆盖显示+可购判定。
        var priceOverrides:Object = {};
        for (var ovId:Number = 0; ovId < _root.宠物库.length; ovId++) {
            var ovDef:Object = _root.宠物库[ovId];
            if (ovDef != undefined && Number(ovDef.IncreasePrice) > 0) {
                priceOverrides[ovId] = getPetCurrentPrice(ovId);
            }
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            snapshot: {
                pets: pets,
                schemes: schemesMap,
                priceOverrides: priceOverrides,
                gold: Number(_root.金钱) || 0,
                kpoint: Number(_root.虚拟币) || 0,
                playerLevel: Number(_root.等级) || 1,
                playerTask: Number(_root.主线任务进度) || 0,
                maxDeploy: calcMaxDeploy(),
                maxSlots: Number(_root.宠物领养限制) || 5,
                currentDeployCount: countDeployed(),
                isCombatMap: _root.当前为战斗地图 == true
            }
        });
    }

    // handleAdoptList 已删除：商城静态目录（分类网格 + 宠物展示定义）改由 C# PetTask 直读 pets.xml
    // 回答 web（不经 Flash），AS2 不再常驻 _root.宠物商城列表。运行态门槛（金币/等级/任务进度/格子）
    // 仍由 web 端用 snapshot 字段判定。等价 C#：launcher/src/Data/PetCatalogLoader.cs + PetTask.RespondAdoptList。

    // ═══════════════════════════════════════════════════════════
    // handleAdopt — 领养宠物
    // ═══════════════════════════════════════════════════════════
    public static function handleAdopt(params:Object):Void {
        var callId = params.callId;
        var petId:Number = Number(params.petId);
        if (isNaN(petId)) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_pet_id" });
            return;
        }

        var petDef:Object = _root.宠物库[petId];
        if (petDef == undefined) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "pet_not_found" });
            return;
        }

        // 服务端权威解锁守卫（等级 + 主线进度）：UI 门控在无 snapshot 时会失效
        // （pet-panel.js 的 unlockTask 判定被 _snapshot 短路，等级判定默认 playerLevel=1），
        // 且任何越过 UI 的消息都不应绕过任务锁。权威值直读 _root（与 snapshot 同源）。
        var reqLevel:Number = Number(petDef.UnlockLevel) || 0;
        if ((Number(_root.等级) || 1) < reqLevel) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "level_locked", reason: "需Lv." + reqLevel });
            return;
        }
        var reqTask:Number = Number(petDef.UnlockTask) || 0;
        if (reqTask > 0 && (Number(_root.主线任务进度) || 0) < reqTask) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "task_locked", reason: "需主线进度 " + reqTask });
            return;
        }

        // 查找空位（Flash 宠物界面采用固定槽位+空位填充模式）
        var emptySlot:Number = -1;
        for (var s:Number = 0; s < _root.宠物信息.length; s++) {
            var slotEntry:Array = _root.宠物信息[s];
            if (slotEntry == undefined || slotEntry.length == 0) {
                emptySlot = s;
                break;
            }
        }

        if (emptySlot < 0) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "slots_full" });
            return;
        }

        // 检查Unique宠物是否已拥有
        if (petDef.Unique == true) {
            for (var k:Number = 0; k < _root.宠物信息.length; k++) {
                if (_root.宠物信息[k][0] == petId) {
                    sendResponse({ task: "pet_response", callId: callId, success: false, error: "already_owned" });
                    return;
                }
            }
        }

        // 检查金币/K点。金币价 = 基础价 + IncreasePrice×已购次数（持久涨价，见 getPetCurrentPrice）。
        var price:Number = getPetCurrentPrice(petId);
        var kprice:Number = Number(petDef.KPrice);
        if (price > 0 && _root.金钱 < price) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "insufficient_gold" });
            return;
        }
        if (kprice > 0 && _root.虚拟币 < kprice) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "insufficient_kpoint" });
            return;
        }

        // 资产扣款、涨价计数与宠物落槽先组成一个领域事务；成就/UI 等可选
        // 回调只能在提交后执行，不能造成真实扣款却没有回执。
        var assetContext:Object = {
            source:"pet_service", reason:"adopt", mergeScope:"operation"
        };
        var adoptSnapshot:Object = capturePetTransactionState();
        var assetTransaction:Object =
            org.flashNight.arki.item.PlayerAssetTransaction.begin(assetContext);
        var moneyBeforeAdopt:Number = Number(_root.金钱);
        var kpointsBeforeAdopt:Number = Number(_root.虚拟币);
        try {
            // 领养全部权威写前直接标脏；货币写 finally 固化真实 delta，
            // 后续涨价/落槽异常时 catch 可以先结算 frame。
            org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
                _root.存档系统);
            try {
                if (price > 0) _root.金钱 -= price;
                if (kprice > 0) _root.虚拟币 -= kprice;
            } finally {
                org.flashNight.arki.item.PlayerAssetTransaction.recordCurrencyDeltas(
                    Number(_root.金钱) - moneyBeforeAdopt,
                    Number(_root.虚拟币) - kpointsBeforeAdopt, assetContext);
            }

            // 创建宠物信息并填入空位
            var initialLevel:Number = Number(petDef.InitialLevel) || 1;
            var newPet:Array = [petId, initialLevel, 200, 0, 0, {}];

            // 涨价：记已购次数（持久于存档），不再原地改写 宠物库.Price 配置。
            // 副作用更正：旧实现改写 宠物库.Price 会连带抬高 刷怪系统 算的可雇用宠物价；
            // 改为基于次数计算后，刷怪价回到基础价（解除该意外耦合）。
            if (Number(petDef.IncreasePrice) > 0) {
                incrementPetPurchaseCount(petId);
            }

            _root.宠物信息[emptySlot] = newPet;
        } catch (adoptError) {
            var adoptRestored:Boolean = restorePetTransactionState(adoptSnapshot);
            org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                assetTransaction, !adoptRestored);
            throw adoptError;
        }
        org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);

        // 成就记账（埋点 #9，领养成功无条件计数；口径=web 面板领养，关卡内 NPC 雇宠帧脚本不计。
        // 不复用上方 宠物购买次数——那是 IncreasePrice>0 才记的涨价口径，两口径隔离）
        try {
            if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
                org.flashNight.arki.achievement.AchievementMetrics.record("宠物领养次数", 1);
                org.flashNight.arki.achievement.AchievementMetrics.record("宠物领养花费金币", price);
            }
        } catch (adoptMetricError) {
            trace("[PetPanelService] post-commit adopt metric failed: " + adoptMetricError);
        }

        // 刷新宠物UI
        refreshPetIconsSafely("adopt");

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            petId: petId,
            slotIndex: emptySlot,
            gold: Number(_root.金钱) || 0,
            kpoint: Number(_root.虚拟币) || 0
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleDeploy — 出战/休息切换
    // ═══════════════════════════════════════════════════════════
    public static function handleDeploy(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        if (isNaN(slotIndex) || slotIndex < 0 || slotIndex >= _root.宠物信息.length) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_slot" });
            return;
        }

        var petInfo:Array = _root.宠物信息[slotIndex];
        if (petInfo == undefined || petInfo.length < 5) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_pet" });
            return;
        }

        var wasDeployed:Boolean = petInfo[4] == 1;
        var maxDeploy:Number = calcMaxDeploy();
        var currentDeploy:Number = countDeployed();

        if (!wasDeployed && currentDeploy >= maxDeploy) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "deploy_limit_reached", maxDeploy: maxDeploy, currentDeploy: currentDeploy });
            return;
        }

        if (!wasDeployed && Number(petInfo[2]) <= 0) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "stamina_depleted" });
            return;
        }

        if (_root.当前为战斗地图 == true && !wasDeployed) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "cannot_deploy_in_combat" });
            return;
        }

        // Web 与旧 Flash UI 共用同一个同步原子入口：helper 负责 dirty-first、
        // provisional flag、场景创建/移除及失败回滚，调用方不再维护第二套状态机。
        var desiredDeploy:Boolean = !wasDeployed;
        var heroX:Number = 500;
        var heroY:Number = 300;
        if (desiredDeploy) {
            try {
                var hero:MovieClip = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager.findHero();
                if (hero != undefined) {
                    heroX = hero._x;
                    heroY = hero._y;
                }
            } catch (deployHeroLookupError) {
                trace("[PetPanelService] deploy hero lookup failed, using fallback: "
                    + deployHeroLookupError);
            }
        }
        var deployToggle:Function = _root.战宠UI函数 == undefined
            ? null : _root.战宠UI函数.尝试切换宠物出战状态;
        var success:Boolean = typeof deployToggle == "function"
            && deployToggle(
                slotIndex, desiredDeploy, heroX, heroY) === true;

        if (!success) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "deploy_failed", deployed: wasDeployed, currentDeployCount: countDeployed(), maxDeploy: maxDeploy });
            return;
        }

        // 刷新UI
        refreshPetIconsSafely("deploy");

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            slotIndex: slotIndex,
            deployed: petInfo[4] == 1,
            currentDeployCount: countDeployed(),
            maxDeploy: maxDeploy
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 托管长枪 — 背包完整快照交付 / 原样取回
    // ═══════════════════════════════════════════════════════════
    public static function handleEquipWeapon(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        if (!validPetSlot(slotIndex)) {
            sendResponse({task:"pet_response", callId:callId,
                success:false, error:"invalid_slot"});
            return;
        }
        var petInfo:Array = _root.宠物信息[slotIndex];
        var result:Object = ManagedLongGunService.handoff(petInfo, params.source);
        sendManagedWeaponResult(callId, slotIndex, petInfo, result);
    }

    public static function handleWithdrawWeapon(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        if (!validPetSlot(slotIndex)) {
            sendResponse({task:"pet_response", callId:callId,
                success:false, error:"invalid_slot"});
            return;
        }
        var petInfo:Array = _root.宠物信息[slotIndex];
        var result:Object = ManagedLongGunService.withdraw(petInfo);
        sendManagedWeaponResult(callId, slotIndex, petInfo, result);
    }

    private static function sendManagedWeaponResult(callId, slotIndex:Number,
                                                      petInfo:Array, result:Object):Void {
        var bagSnapshot:Object = _root.物品栏 != undefined && _root.物品栏.背包 != null
            ? InventoryPanelService.buildExternalSnapshot("背包", 0, 50) : null;
        var response:Object = {
            task:"pet_response",
            callId:callId,
            success:result != null && result.success === true,
            slotIndex:slotIndex,
            inventorySnapshot:bagSnapshot,
            managedLongGun:ManagedLongGunService.buildPanelState(petInfo, bagSnapshot)
        };
        if (response.success) {
            response.operation = result.operation;
            response.sourceSlot = result.sourceSlot;
            response.targetSlot = result.targetSlot;
            response.weapon = result.weapon;
            response.rebuilt = rebuildPetIfDeployed(
                slotIndex, petInfo, false, null, "managed_weapon");
            response.refreshDeferred = petInfo[4] == 1 && response.rebuilt !== true;
        } else {
            response.error = result == null ? "operation_failed" : String(result.error);
        }
        sendResponse(response);
    }

    // ═══════════════════════════════════════════════════════════
    // handleAdvance — 执行进阶方案
    // ═══════════════════════════════════════════════════════════
    public static function handleAdvance(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        var schemeName:String = String(params.scheme || "");

        if (isNaN(slotIndex) || slotIndex < 0 || slotIndex >= _root.宠物信息.length) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_slot" });
            return;
        }
        if (schemeName == "") {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_scheme" });
            return;
        }

        var scheme:Object = _root.战宠进阶函数[schemeName];
        if (scheme == undefined) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "scheme_not_found" });
            return;
        }

        // 设置上下文（模拟 Flash UI 的 this 上下文）。进阶方案用本宠子集（per-pet）：
        // 还原原始设计，使条件函数的前置守卫对中/强体质宠正确短路，不再误判前置不足。
        var advPetId:Number = Number(_root.宠物信息[slotIndex][0]);
        var petSchemeSet:Object = buildPetSchemeSet(advPetId);

        // 服务端授权守卫：方案必须在本宠 Promotion 子集内。否则条件/执行函数读到的
        // this.进阶方案[该方案] 为 undefined → 等级/金币守卫退化成 `x < undefined`(恒 false) 被绕过，
        // 且 `_root.金钱 -= undefined` 会把金钱写成 NaN、并越权写入未授权属性（如对普通宠注入 钙化 战斗增益）。
        // web UI 只下发本宠已配置方案，但畸形/过期消息可能传入越权方案，故服务端显式拦截。
        if (petSchemeSet[schemeName] == undefined) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "scheme_not_allowed", reason: "该宠物不支持此进阶方案" });
            return;
        }

        var advanceAttrs:Object = _root.宠物信息[slotIndex][5];
        var mustInitializeAdvanceAttrs:Boolean = advanceAttrs == undefined
            || typeof advanceAttrs != "object";
        if (mustInitializeAdvanceAttrs) advanceAttrs = {};
        var ctx:Object = {
            当前宠物信息: _root.宠物信息[slotIndex],
            当前宠物属性: advanceAttrs,
            进阶方案: petSchemeSet
        };

        // 服务端完成度守卫：一次性付费方案（如钙化）的 条件 不自检完成，必须在此拦截重复执行，
        // 否则会被反复点击重复扣费。三件套按 基础训练.次数 判定完成。
        if (isSchemeCompleted(schemeName, scheme, ctx.当前宠物属性)) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "already_completed", reason: "已完成进阶" });
            return;
        }

        // 检查条件：条件函数把失败原因写到 this（即 ctx），旧实现误读 scheme.失败提示（恒为默认值）
        var condFn:Function = scheme.条件;
        if (typeof condFn == "function") {
            ctx.失败提示 = "";
            var condResult:Boolean = condFn.call(ctx);
            if (!condResult) {
                var failMsg:String = (ctx.失败提示 != undefined && ctx.失败提示 != "") ? ctx.失败提示 : "条件不满足";
                sendResponse({ task: "pet_response", callId: callId, success: false, error: "condition_failed", reason: failMsg });
                return;
            }
        }

        // 执行进阶。方案脚本仍持有货币写权；服务层以提交前后权威差值统一出回执。
        var moneyBeforeAdvance:Number = Number(_root.金钱);
        var kpointsBeforeAdvance:Number = Number(_root.虚拟币);
        var assetContext:Object = {
            source:"pet_service", reason:"advance_" + schemeName,
            mergeScope:"operation"
        };
        var advanceSnapshot:Object = capturePetTransactionState();
        var assetTransaction:Object =
            org.flashNight.arki.item.PlayerAssetTransaction.begin(assetContext);
        var execFn:Function = scheme.执行;
        try {
            // 方案脚本可同时写货币与宠物属性；缺少存档系统时不得进入脚本。
            org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
                _root.存档系统);
            // 旧档缺少 attrs 时，条件预检只使用局部空对象；只有进入已受 snapshot
            // 保护的事务后才落盘，condition_failed 不得偷偷迁移玩家存档。
            if (mustInitializeAdvanceAttrs) {
                _root.宠物信息[slotIndex][5] = advanceAttrs;
            }
            try {
                if (typeof execFn == "function") execFn.call(ctx);
            } finally {
                org.flashNight.arki.item.PlayerAssetTransaction.recordCurrencyDeltas(
                    Number(_root.金钱) - moneyBeforeAdvance,
                    Number(_root.虚拟币) - kpointsBeforeAdvance,
                    assetContext);
            }
        } catch (advanceError) {
            var advanceRestored:Boolean = restorePetTransactionState(
                advanceSnapshot);
            org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                assetTransaction, !advanceRestored);
            throw advanceError;
        }

        org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);

        // 成就记账（埋点 #10，仅非反复型方案——开关型(影子刺客发色/常驻淬毒)可反复切换，计数会被刷；
        // 金额不顺带：影子刺客二次免费会失真）。消费者回执先闭合，避免可选埋点异常泄漏事务栈。
        try {
            if (!isSchemeRepeatable(schemeName, scheme)
                    && org.flashNight.arki.achievement.AchievementMetrics != undefined) {
                org.flashNight.arki.achievement.AchievementMetrics.record("宠物进阶次数", 1);
            }
        } catch (advanceMetricError) {
            // 可选埋点不得阻断已提交进阶后的重建与 success response，
            // 否则调用方重放会再次扣费/进阶。
            trace("[PetPanelService] post-commit advance metric failed: " + advanceMetricError);
        }

        // slotIndex 是存档槽，不是宠物 mc 库索引；进阶只改变属性投影，必须保留
        // 受伤后的绝对 HP/MP。尤其反复型方案可免费切换，绝不能借重建回满血。
        // 失败时进阶资产已权威提交，但旧战斗单位保持可用并明确要求稍后刷新。
        var advanceRebuilt:Boolean = rebuildPetIfDeployed(
            slotIndex, ctx.当前宠物信息, false, "升级动画2", "advance");

        // 刷新UI
        refreshPetIconsSafely("advance");

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            slotIndex: slotIndex,
            scheme: schemeName,
            gold: Number(_root.金钱) || 0,
            kpoint: Number(_root.虚拟币) || 0,
            rebuilt: advanceRebuilt,
            refreshDeferred: ctx.当前宠物信息[4] == 1 && advanceRebuilt !== true
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handlePreviewAdvance — 预览进阶效果
    // ═══════════════════════════════════════════════════════════
    public static function handlePreviewAdvance(params:Object):Void {
        var callId = params.callId;
        var petId:Number = Number(params.petId);
        var schemeName:String = String(params.scheme || "");

        if (isNaN(petId)) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_pet_id" });
            return;
        }

        var scheme:Object = _root.战宠进阶函数[schemeName];
        if (scheme == undefined) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "scheme_not_found" });
            return;
        }

        var goldCost:Number = Number(scheme.消耗金币) || 0;
        var kpointCost:Number = Number(scheme.消耗K点) || 0;
        var maxTier:Number = Number(scheme.次数上限) || 1;
        var unlockLevel:Number = Number(scheme.解锁等级) || 0;
        var descText:String = "";

        // 获取方案描述。进阶方案用本宠子集，使前置档守卫对中/强体质宠正确短路（描述不再误显"请先训练"）。
        var previewSchemeSet:Object = buildPetSchemeSet(petId);
        if (typeof scheme.详情页描述 == "function") {
            var ctx:Object = {
                当前宠物信息: _root.宠物信息[0] != undefined ? _root.宠物信息[0] : [petId, 1, 200, 0, 0, {}],
                当前宠物属性: {},
                进阶方案: previewSchemeSet
            };
            descText = String(scheme.详情页描述.call(ctx));
        } else if (scheme.描述 != undefined) {
            if (typeof scheme.描述 == "function") {
                descText = String(scheme.描述.call({当前宠物信息: [petId, 1, 200, 0, 0, {}], 当前宠物属性: {}, 进阶方案: previewSchemeSet}));
            } else {
                descText = String(scheme.描述);
            }
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            scheme: schemeName,
            goldCost: goldCost,
            kpointCost: kpointCost,
            maxTier: maxTier,
            unlockLevel: unlockLevel,
            description: descText
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleExpandSlot — 扩充宠物格子
    // ═══════════════════════════════════════════════════════════
    public static function handleExpandSlot(params:Object):Void {
        var callId = params.callId;
        var maxSlots:Number = _root.最大宠物格子数 || 80;

        if (_root.宠物领养限制 >= maxSlots) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "max_slots_reached", maxSlots: maxSlots });
            return;
        }

        // 开格子消耗（与 Flash UI 一致）
        var expandCost:Number = 50000;
        if (_root.金钱 < expandCost) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "insufficient_gold", cost: expandCost });
            return;
        }

        var assetContext:Object = {
            source:"pet_service", reason:"expand_slot", mergeScope:"operation"
        };
        var expandSnapshot:Object = capturePetTransactionState();
        var assetTransaction:Object =
            org.flashNight.arki.item.PlayerAssetTransaction.begin(assetContext);
        var moneyBeforeExpand:Number = Number(_root.金钱);
        try {
            org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
                _root.存档系统);
            try {
                _root.金钱 -= expandCost;
            } finally {
                org.flashNight.arki.item.PlayerAssetTransaction.recordCurrencyDeltas(
                    Number(_root.金钱) - moneyBeforeExpand, 0, assetContext);
            }
            _root.开宠物格子();
        } catch (expandError) {
            var expandRestored:Boolean = restorePetTransactionState(expandSnapshot);
            org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                assetTransaction, !expandRestored);
            throw expandError;
        }
        org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            maxSlots: Number(_root.宠物领养限制),
            gold: Number(_root.金钱) || 0
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleRename — 重命名宠物
    // ═══════════════════════════════════════════════════════════
    public static function handleRename(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        var newName:String = String(params.name || "");
        var result:Object = renamePetSlot(slotIndex, newName);
        if (result.success === true) refreshPetIconsSafely("rename");
        result.task = "pet_response";
        result.callId = callId;
        sendResponse(result);
    }

    /** customName 是唯一显示名覆盖字段；写入后，已出战单位统一整只重建。 */
    public static function renamePetSlot(slotIndex:Number, newName:String):Object {
        if (isNaN(slotIndex) || Math.floor(slotIndex) != slotIndex
                || slotIndex < 0 || slotIndex >= _root.宠物信息.length) {
            return {success:false, error:"invalid_slot"};
        }
        if (newName == "" || newName.length > 10) {
            return {success:false, error:"invalid_name"};
        }

        // 宠物重命名：先进入存档队列，再正规化旧档属性并提交名称。
        var petInfo:Array = _root.宠物信息[slotIndex];
        if (petInfo == undefined || petInfo.length < 5) {
            return {success:false, error:"invalid_pet"};
        }
        _root.存档系统.dirtyMark = true;
        var attrs:Object = petInfo[5];
        if (attrs == undefined || typeof attrs != "object") {
            attrs = {};
            petInfo[5] = attrs;
        }
        attrs.customName = newName;

        var renameRebuilt:Boolean = rebuildPetIfDeployed(
            slotIndex, petInfo, false, null, "rename");
        return {
            success:true,
            slotIndex:slotIndex,
            name:newName,
            rebuilt:renameRebuilt,
            refreshDeferred:petInfo[4] == 1 && renameRebuilt !== true
        };
    }

    // ═══════════════════════════════════════════════════════════
    // handleTooltip — 获取进阶方案详情 tooltip
    // ═══════════════════════════════════════════════════════════
    public static function handleTooltip(params:Object):Void {
        var callId = params.callId;
        var schemeName:String = String(params.scheme || "");
        var petId:Number = Number(params.petId);

        var scheme:Object = _root.战宠进阶函数[schemeName];
        if (scheme == undefined) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "scheme_not_found" });
            return;
        }

        var desc:String = "";
        if (typeof scheme.详情页描述 == "function") {
            var ctx:Object = {
                当前宠物信息: [petId, 1, 200, 0, 0, {}],
                当前宠物属性: {},
                进阶方案: buildPetSchemeSet(petId)
            };
            desc = String(scheme.详情页描述.call(ctx));
        } else if (typeof scheme.描述 == "function") {
            desc = String(scheme.描述());
        } else {
            desc = String(scheme.描述 || "");
        }

        var btnText:String = String(scheme.执行按钮文字 || "执行");
        var goldCost:Number = Number(scheme.消耗金币) || 0;
        var kpointCost:Number = Number(scheme.消耗K点) || 0;

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            scheme: schemeName,
            description: desc,
            buttonText: btnText,
            goldCost: goldCost,
            kpointCost: kpointCost
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleWeaponTooltip — 托管/预设/候选长枪的 canonical 物品注释
    // ═══════════════════════════════════════════════════════════
    public static function handleWeaponTooltip(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        if (!validPetSlot(slotIndex)) {
            sendResponse({task:"pet_response", callId:callId,
                success:false, error:"invalid_slot"});
            return;
        }

        var petInfo:Array = _root.宠物信息[slotIndex];
        var tooltip:Object = ManagedLongGunService.buildWeaponTooltip(
            petInfo, params.source == undefined ? null : params.source);
        if (tooltip == null || tooltip.success !== true) {
            sendResponse({task:"pet_response", callId:callId, success:false,
                error:tooltip == null ? "tooltip_failed" : String(tooltip.error)});
            return;
        }
        sendResponse({
            task:"pet_response",
            callId:callId,
            success:true,
            v:Number(tooltip.v),
            itemName:String(tooltip.itemName),
            displayname:String(tooltip.displayname),
            iconName:String(tooltip.iconName),
            itemType:String(tooltip.itemType),
            descHTML:String(tooltip.descHTML),
            introHTML:String(tooltip.introHTML)
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleRestoreStamina — 消耗金币恢复宠物体力
    // ═══════════════════════════════════════════════════════════
    public static function handleRestoreStamina(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        var result:Object = restoreStaminaSlot(slotIndex);
        result.task = "pet_response";
        result.callId = callId;
        sendResponse(result);
    }

    /** Web 与旧 Flash UI 共用的体力恢复资产核心；权威费用固定为 1000 金币。 */
    public static function restoreStaminaSlot(slotIndex:Number):Object {
        if (isNaN(slotIndex) || Math.floor(slotIndex) != slotIndex
                || slotIndex < 0 || slotIndex >= _root.宠物信息.length) {
            return {success:false, error:"invalid_slot"};
        }
        var petInfo:Array = _root.宠物信息[slotIndex];
        if (petInfo == undefined || petInfo.length < 5) {
            return {success:false, error:"invalid_pet"};
        }

        var currentStamina:Number = Number(petInfo[2]);
        if (currentStamina >= 200) {
            return {success:false, error:"stamina_full"};
        }

        var cost:Number = 1000;
        if (_root.金钱 < cost) {
            return {success:false, error:"insufficient_gold", cost:cost};
        }

        var assetContext:Object = {
            source:"pet_service", reason:"restore_stamina", mergeScope:"operation"
        };
        var restoreSnapshot:Object = capturePetTransactionState();
        var assetTransaction:Object =
            org.flashNight.arki.item.PlayerAssetTransaction.begin(assetContext);
        var moneyBeforeRestore:Number = Number(_root.金钱);
        try {
            org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
                _root.存档系统);
            try {
                _root.金钱 -= cost;
            } finally {
                org.flashNight.arki.item.PlayerAssetTransaction.recordCurrencyDeltas(
                    Number(_root.金钱) - moneyBeforeRestore, 0, assetContext);
            }
            petInfo[2] = 200;
        } catch (restoreError) {
            var staminaRestored:Boolean = restorePetTransactionState(
                restoreSnapshot);
            org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                assetTransaction, !staminaRestored);
            throw restoreError;
        }
        org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);

        return {
            success:true,
            slotIndex:slotIndex,
            stamina:200,
            cost:cost,
            gold:Number(_root.金钱) || 0
        };
    }

    // ═══════════════════════════════════════════════════════════
    // handleLevelUp — 消耗战宠灵石升级
    // ═══════════════════════════════════════════════════════════
    public static function handleLevelUp(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        var result:Object = levelUpSlot(slotIndex);
        if (result.success === true) refreshPetIconsSafely("level_up");
        result.task = "pet_response";
        result.callId = callId;
        sendResponse(result);
    }

    /**
     * Web 与旧 Flash UI 共用的同步升级核心。
     *
     * 所有只读校验与费用计算先完成；显式玩家物资事务再把 singleSubmit 的 loss
     * 与等级/下一档阈值写绑定为同一个提交点。dirtyMark 必须先于第一项权威写，
     * 而重建、动画、埋点均在提交后隔离，因此失败重建只返回 refreshDeferred，
     * 不会把已扣灵石且已升级的操作伪装成可重试失败。
     */
    public static function levelUpSlot(slotIndex:Number):Object {
        if (isNaN(slotIndex) || Math.floor(slotIndex) != slotIndex
                || slotIndex < 0 || slotIndex >= _root.宠物信息.length) {
            return {success:false, error:"invalid_slot"};
        }

        var petInfo:Array = _root.宠物信息[slotIndex];
        if (petInfo == undefined || petInfo.length < 5) {
            return {success:false, error:"invalid_pet"};
        }

        var currentLevel:Number = Number(petInfo[1]);
        var levelLimit:Number = Number(_root.等级限制) || 100;
        if (!isFinite(currentLevel) || currentLevel < 0) {
            return {success:false, error:"invalid_pet"};
        }
        if (currentLevel >= levelLimit) {
            return {success:false, error:"level_maxed", levelLimit:levelLimit};
        }

        var petId:Number = Number(petInfo[0]);
        var petDef:Object = _root.宠物库[petId];
        if (petDef == undefined) return {success:false, error:"pet_not_found"};
        var identifier:String = String(petDef.Identifier);

        // 不为旧档补对象/阈值，直到灵石提交成功；insufficient 必须是零宠物写。
        var oldAttrs:Object = petInfo[5];
        var hasObjectAttrs:Boolean = oldAttrs != undefined && typeof oldAttrs == "object";
        var xpNeeded:Number = hasObjectAttrs
            ? Number(oldAttrs.宠物升级所需经验) : 0;
        if (!isFinite(xpNeeded) || xpNeeded <= 0) {
            xpNeeded = 0;
            if (_root.战宠UI函数 != undefined
                    && typeof _root.战宠UI函数.计算战宠升级所需经验 == "function") {
                xpNeeded = Number(_root.战宠UI函数.计算战宠升级所需经验(
                    identifier, currentLevel));
                if (!isFinite(xpNeeded) || xpNeeded < 0) xpNeeded = 0;
            }
        }
        var stoneCost:Number = currentLevel * 2 + Math.floor(xpNeeded / 10000);
        if (!isFinite(stoneCost) || stoneCost <= 0) stoneCost = 1;

        // 阈值计算会调用旧 UI 的可注入函数，必须在扣灵石/写等级前完成。
        // 一旦进入显式资产 frame，成功扣除后的路径只允许本地权威赋值，
        // 避免可选计算异常截断 success response 并让同一升级被重放。
        var newLevel:Number = currentLevel + 1;
        var newXpNeeded:Number = 0;
        if (_root.战宠UI函数 != undefined
                && typeof _root.战宠UI函数.计算战宠升级所需经验 == "function") {
            newXpNeeded = Number(_root.战宠UI函数.计算战宠升级所需经验(
                identifier, newLevel));
            if (!isFinite(newXpNeeded) || newXpNeeded < 0) newXpNeeded = 0;
        }

        var levelContext:Object = {
            source:"pet_service", reason:"level_up", mergeScope:"operation"
        };
        var levelSnapshot:Object = capturePetTransactionState();
        var levelTransaction:Object =
            org.flashNight.arki.item.PlayerAssetTransaction.begin(levelContext);
        var levelDirtyMarked:Boolean = false;
        var levelPetWriteStarted:Boolean = false;
        var levelTransactionSettled:Boolean = false;
        try {
            // 存档队列不可用时在 singleSubmit 与宠物字段写之前同步失败关闭。
            org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
                _root.存档系统);
            levelDirtyMarked = true;
            if (!_root.singleSubmit("战宠灵石", stoneCost, levelContext)) {
                // singleSubmit=false 尚未触碰宠物权威；只恢复通用资产/dirty，避免
                // 全量宠物快照克隆把确定零写伪装成对象替换。
                var levelAssetsRestored:Boolean = ItemUtil.restorePlayerAssetSnapshot(
                    levelSnapshot.assets);
                if (!levelAssetsRestored) {
                    org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                        levelTransaction, true);
                    levelTransactionSettled = true;
                    throw new Error("pet_level_asset_restore_failed");
                }
                org.flashNight.arki.item.PlayerAssetTransaction.rollback(levelTransaction);
                levelTransactionSettled = true;
                return {success:false, error:"insufficient_stones", cost:stoneCost};
            }

            var attrs:Object = hasObjectAttrs ? oldAttrs : {};
            levelPetWriteStarted = true;
            if (!hasObjectAttrs) petInfo[5] = attrs;
            petInfo[1] = newLevel;
            attrs.宠物升级所需经验 = newXpNeeded;
        } catch (levelError) {
            if (!levelTransactionSettled) {
                // dirty 首写自身失败时还没有任何可恢复的领域写；不要二次触碰同一
                // 故障 setter。扣石阶段异常只需恢复通用资产，宠物首写后才恢复全域。
                var levelRestored:Boolean = true;
                if (levelDirtyMarked) {
                    levelRestored = levelPetWriteStarted
                        ? restorePetTransactionState(levelSnapshot)
                        : ItemUtil.restorePlayerAssetSnapshot(levelSnapshot.assets);
                }
                org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                    levelTransaction, !levelRestored);
                levelTransactionSettled = true;
            }
            throw levelError;
        }
        org.flashNight.arki.item.PlayerAssetTransaction.commit(levelTransaction);

        try {
            if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
                org.flashNight.arki.achievement.AchievementMetrics.record("宠物培养次数", 1);
            }
        } catch (levelMetricError) {
            trace("[PetPanelService] post-commit level metric failed: " + levelMetricError);
        }

        var levelRebuilt:Boolean = rebuildPetIfDeployed(
            slotIndex, petInfo, true, "升级动画2", "level_up");
        return {
            success:true,
            slotIndex:slotIndex,
            newLevel:newLevel,
            stoneCost:stoneCost,
            newXpNeeded:newXpNeeded,
            levelLimit:levelLimit,
            rebuilt:levelRebuilt,
            refreshDeferred:petInfo[4] == 1 && levelRebuilt !== true
        };
    }

    // ═══════════════════════════════════════════════════════════
    // handleDelete — 删除宠物并返还灵石
    // ═══════════════════════════════════════════════════════════
    public static function handleDelete(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        var result:Object = deletePetSlot(slotIndex);
        if (result.success === true) refreshPetIconsSafely("delete");
        result.task = "pet_response";
        result.callId = callId;
        sendResponse(result);
    }

    /**
     * Web 与旧 Flash UI 共用的解散核心。托管武器取回、灵石返还与清槽共用
     * 同一玩家物资 frame；只有所有权已经提交后才定点撤销该 slot 的场景投影。
     */
    public static function deletePetSlot(slotIndex:Number):Object {
        if (isNaN(slotIndex) || Math.floor(slotIndex) != slotIndex
                || slotIndex < 0 || slotIndex >= _root.宠物信息.length) {
            return {success:false, error:"invalid_slot"};
        }

        var petInfo:Array = _root.宠物信息[slotIndex];
        if (petInfo == undefined || petInfo.length == 0) {
            return {success:false, error:"empty_slot"};
        }
        if (_root.当前为战斗地图 == true) {
            return {success:false, error:"combat_locked"};
        }

        var currentLevel:Number = Number(petInfo[1]);

        // 计算返还灵石
        var attrs:Object = petInfo[5];
        var xpNeeded:Number = 0;
        if (attrs != undefined && typeof attrs == "object") {
            xpNeeded = Number(attrs.宠物升级所需经验) || 0;
        }
        var stoneRefund:Number = Math.floor(Math.sqrt(currentLevel) * 0.8 * xpNeeded / 10000);
        if (isNaN(stoneRefund) || stoneRefund < 0) stoneRefund = 0;

        // 先完成全部无副作用预检。托管武器需要一个真实背包空位；若塞不下，宠物、
        // 场景实例与灵石均保持不变。灵石虽通常进材料栏，仍需防数量上限/异常存档。
        var weaponPreflight:Object = ManagedLongGunService.preflightWithdrawal(petInfo);
        if (weaponPreflight.success !== true) {
            return {success:false, error:String(weaponPreflight.error)};
        }
        if (stoneRefund > 0 && ItemUtil.singleRequire("战宠灵石", stoneRefund) == null) {
            return {success:false, error:"inventory_full", refund:stoneRefund};
        }

        // 返还灵石与清空宠物槽属于同一个领域提交；singleAcquire 在外层事务内
        // 只缓冲 gain，直到宠物所有权状态已经清除才发布。
        var deleteContext:Object = {
            source:"pet_service", reason:"delete_refund", mergeScope:"operation"
        };
        var deleteSnapshot:Object = capturePetTransactionState();
        var deleteTransaction:Object =
            org.flashNight.arki.item.PlayerAssetTransaction.begin(deleteContext);
        var weaponReturned:Boolean = false;
        try {
            // 托管取回、灵石返还与清槽之前统一 fail-fast 标脏。
            org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
                _root.存档系统);
            if (weaponPreflight.required === true) {
                var weaponReturn:Object = ManagedLongGunService.withdraw(petInfo);
                if (weaponReturn.success !== true) {
                    restorePetTransactionState(deleteSnapshot);
                    org.flashNight.arki.item.PlayerAssetTransaction.rollback(deleteTransaction);
                    return {success:false, error:String(weaponReturn.error)};
                }
                weaponReturned = true;
            }
            if (stoneRefund > 0) {
                if (!_root.singleAcquire("战宠灵石", stoneRefund, deleteContext)) {
                    restorePetTransactionState(deleteSnapshot);
                    org.flashNight.arki.item.PlayerAssetTransaction.rollback(deleteTransaction);
                    return {success:false, error:"inventory_full", refund:stoneRefund,
                        weaponReturned:weaponReturned};
                }
            }

            // 清空槽位
            _root.宠物信息[slotIndex] = [];
            org.flashNight.arki.item.PlayerAssetTransaction.commit(deleteTransaction);
        } catch (deleteAssetError) {
            var deleteRestored:Boolean = restorePetTransactionState(deleteSnapshot);
            org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                deleteTransaction, !deleteRestored);
            throw deleteAssetError;
        }

        // 所有权写入成功后只撤掉被删 slot 的运行态投影。既有其他战宠保持原实例，
        // 避免 bare remove 已提交但 canonical 名仍等待 phase flush 时同栈全量重载。
        var deleteSceneProjected:Boolean = false;
        try {
            if (_root.战宠UI函数 != undefined
                    && typeof _root.战宠UI函数.移除场景宠物槽 == "function") {
                deleteSceneProjected = _root.战宠UI函数.移除场景宠物槽(
                    slotIndex) === true;
            }
        } catch (deleteSceneRefreshError) {
            trace("[PetPanelService] post-commit delete slot projection failed: "
                + deleteSceneRefreshError);
            deleteSceneProjected = false;
        }
        var deleteRefreshDeferred:Boolean = deleteSceneProjected !== true;
        recordPetRefreshSafely(slotIndex, !deleteRefreshDeferred, "delete");
        return {
            success:true,
            slotIndex:slotIndex,
            deleted:true,
            stoneRefund:stoneRefund,
            weaponReturned:weaponReturned,
            refreshDeferred:deleteRefreshDeferred
        };
    }

    // ═══════════════════════════════════════════════════════════
    // handlePanelOpen — 面板打开时暂停游戏
    // ═══════════════════════════════════════════════════════════
    public static function handlePanelOpen(params:Object):Void {
        // 面板打开时无需特殊处理（暂停由 C# PanelHostController 管理）
        var callId = params.callId;
        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handlePanelClose — 面板关闭时刷新
    // ═══════════════════════════════════════════════════════════
    public static function handlePanelClose(params:Object):Void {
        // 关闭时刷新宠物图标
        refreshPetIconsSafely("panel_close");
        var callId = params.callId;
        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 世界内招募（战宠）—— 旧 Symbol 2035 宠物分支的 web 等价。
    //   入口同佣兵：Symbol 1770 bt2（NPC 有 宠物数据）→ MercPanelService.openWebHire(kind="pet")。
    //   权威读 openWebHire stash 的 _root._pendingHire.pet + .雇佣价格（NPC 可能已超时离场，web 不传）。
    //   ⚠ 顺手修：原版 雇佣宠物 卡 金钱 门但漏扣费（佣兵那边 雇佣佣兵:183 是扣的），
    //     用户拍板对齐佣兵语义 → 此处补扣 雇佣价格。
    // ═══════════════════════════════════════════════════════════
    public static function handleWorldAdopt(params:Object):Void {
        var callId = params.callId;
        // 权威读 stash 的数据快照（可雇 NPC 有寿命会自行 despawn；team 面板现已随 webPanelPause 暂停游戏，
        // despawn 计时同冻、离场窗口基本消除，但仍 stash 防御性兜底，复刻旧 Symbol 2035 survive despawn。不信 web，安全姿态不变）
        var stash:Object = _root._pendingHire;
        if (stash == undefined || stash.pet == undefined || stash.pet == null) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "npc_gone" });
            return;
        }
        var petData:Array = stash.pet;

        // 定价（复刻 刷新宠物数据:76）：金币 = NPC.雇佣价格（世界内招募无 K点）
        var goldPrice:Number = Number(stash.雇佣价格) || 0;

        // 栏位（复刻 结算:139-150 pet 分支）：宠物信息 length==0 空格
        var slot:Number = -1;
        for (var s:Number = 0; s < _root.宠物信息.length; s++) {
            var occ:Array = _root.宠物信息[s];
            if (occ == undefined || occ.length == 0) { slot = s; break; }
        }
        if (slot < 0) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "slots_full" });
            return;
        }

        // 金钱门（复刻 结算:132）+ ⚠ 顺手修扣费（原版 雇佣宠物 无此扣减）
        if (Number(_root.金钱) < goldPrice) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "insufficient_gold", goldPrice: goldPrice, currentGold: Number(_root.金钱) });
            return;
        }
        // 扣款与宠物落槽必须先形成一个权威事务事实。模式判定等旧函数可能抛错；
        // 即使领域状态只能保留为已发生的部分结果，也不能留下真实扣款却没有回执。
        var assetContext:Object = {
            source:"pet_service", reason:"world_adopt", mergeScope:"operation"
        };
        var worldAdoptSnapshot:Object = capturePetTransactionState();
        var assetTransaction:Object =
            org.flashNight.arki.item.PlayerAssetTransaction.begin(assetContext);
        var moneyBeforeWorldAdopt:Number = Number(_root.金钱);
        try {
            org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
                _root.存档系统);
            try {
                _root.金钱 -= goldPrice;   // ← 顺手修：原版 雇佣宠物 漏此行（gate-but-no-charge）
            } finally {
                org.flashNight.arki.item.PlayerAssetTransaction.recordCurrencyDeltas(
                    Number(_root.金钱) - moneyBeforeWorldAdopt, 0, assetContext);
            }

            // 写入 + 出战上限处理（复刻 雇佣宠物:250-262）。petData = NPC.宠物数据 直接落槽（已是 宠物信息 格式）
            _root.宠物信息[slot] = petData;
            _root.最大宠物出战数 = Math.min(_root.等级 / 5, 5);
            if (_root.isChallengeMode() == true) _root.最大宠物出战数 = _root.等级 / 35;
            if (_root.isEasyMode() == true) _root.最大宠物出战数 = 5 + _root.等级 / 5;
            if (_root.出战宠物id库.length >= _root.最大宠物出战数) _root.宠物信息[slot][4] = 0;
        } catch (worldAdoptError) {
            var worldAdoptRestored:Boolean = restorePetTransactionState(
                worldAdoptSnapshot);
            org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                assetTransaction, !worldAdoptRestored);
            throw worldAdoptError;
        }
        org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);

        // 成就记账（对齐 handleAdopt 埋点 #9）
        try {
            if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
                org.flashNight.arki.achievement.AchievementMetrics.record("宠物领养次数", 1);
                org.flashNight.arki.achievement.AchievementMetrics.record("宠物领养花费金币", goldPrice);
            }
        } catch (worldAdoptMetricError) {
            trace("[PetPanelService] post-commit world adopt metric failed: "
                + worldAdoptMetricError);
        }

        // 权威招募已经提交；先清 one-shot stash，任何 post-commit 场景回调失败
        // 都不能让同一 NPC 请求再次扣款/落槽。
        _root._pendingHire = undefined;

        // 世界：删 NPC（还在才删，超时离场则跳过）+ 定点部署新宠（AS2 独占）。
        try {
            var npc:Object = stash.npcId != undefined && _root.gameworld != undefined
                ? _root.gameworld[stash.npcId] : undefined;
            if (npc != undefined && npc._x != undefined) {
                _root.gameworld[stash.npcId].removeMovieClip();
            }
        } catch (worldNpcCleanupError) {
            trace("[PetPanelService] post-commit world NPC cleanup failed: "
                + worldNpcCleanupError);
        }
        // 新宠权威 flag=1 时只部署新 slot；既有单位不清场、不重建，因此其同图
        // 已结算效果与 canonical 实例都原样保留。flag=0 无需场景写，视为已收敛。
        var worldSceneProjected:Boolean = _root.宠物信息[slot][4] != 1;
        if (!worldSceneProjected) {
            try {
                var controlledHero:Object = _root.gameworld != undefined
                    ? _root.gameworld[_root.控制目标] : undefined;
                worldSceneProjected = controlledHero != undefined
                    && _root.战宠UI函数 != undefined
                    && typeof _root.战宠UI函数.设置宠物出战 == "function"
                    && _root.战宠UI函数.设置宠物出战(
                        slot, true, controlledHero._x, controlledHero._y) === true;
            } catch (worldSceneDeployError) {
                trace("[PetPanelService] post-commit world pet deploy failed: "
                    + worldSceneDeployError);
                worldSceneProjected = false;
            }
        }
        var worldRefreshDeferred:Boolean = worldSceneProjected !== true;
        recordPetRefreshSafely(slot, !worldRefreshDeferred, "world_adopt");
        refreshPetIconsSafely("world_adopt");

        sendResponse({ task: "pet_response", callId: callId, success: true,
            hired: true, slotIndex: slot, gold: Number(_root.金钱) || 0,
            refreshDeferred: worldRefreshDeferred });
    }

    // ═══════════════════════════════════════════════════════════
    // 工具函数
    // ═══════════════════════════════════════════════════════════

    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringifySafe(resp));
    }

    /**
     * Flash 宠物图标只是权威状态的可选投影。帧脚本异常不能截断 Web 成功回包，
     * 否则领养、进阶、升级或删除会被误判成未知结果并被客户端重放。
     */
    private static function refreshPetIconsSafely(reason:String):Void {
        try {
            if (_root.宠物信息界面 != undefined
                    && _root.宠物信息界面.排列宠物图标 != undefined) {
                _root.宠物信息界面.排列宠物图标();
            }
        } catch (petIconRefreshError) {
            trace("[PetPanelService] post-commit icon refresh failed reason="
                + reason + " error=" + petIconRefreshError);
        }
    }

    private static function validPetSlot(slotIndex:Number):Boolean {
        if (isNaN(slotIndex) || Math.floor(slotIndex) != slotIndex
                || slotIndex < 0 || slotIndex >= _root.宠物信息.length) return false;
        var info:Array = _root.宠物信息[slotIndex];
        return info != undefined && info.length >= 5;
    }

    private static function rebuildPetIfDeployed(slotIndex:Number, petInfo:Array,
                                                  upgradeRebuild:Boolean,
                                                  effectName:String,
                                                  refreshReason:String):Boolean {
        if (petInfo == undefined || petInfo[4] != 1) return true;
        if (_root.战宠UI函数 == undefined
                || typeof _root.战宠UI函数.重建宠物单位 != "function") {
            recordPetRefreshSafely(slotIndex, false, refreshReason);
            return false;
        }
        var rebuildSuccess:Boolean = false;
        try {
            rebuildSuccess = _root.战宠UI函数.重建宠物单位(
                slotIndex, upgradeRebuild === true, effectName) === true;
        } catch (rebuildError) {
            // 资产/等级/进阶均已提交；重建失败只要求后续刷新，不得截断 success 回包。
            trace("[PetPanelService] post-commit pet rebuild failed slot="
                + slotIndex + " error=" + rebuildError);
        }
        recordPetRefreshSafely(slotIndex, rebuildSuccess, refreshReason);
        return rebuildSuccess;
    }

    /** refresh-deferred 本身也是 post-commit 可观测性，记录器异常不能改写领域结果。 */
    private static function recordPetRefreshSafely(slotIndex:Number, success:Boolean,
                                                    reason:String):Void {
        try {
            if (_root.战宠UI函数 != undefined
                    && typeof _root.战宠UI函数.记录宠物刷新结果 == "function") {
                _root.战宠UI函数.记录宠物刷新结果(slotIndex, success, reason);
            }
        } catch (refreshRecordError) {
            trace("[PetPanelService] refresh-deferred marker failed slot="
                + slotIndex + " reason=" + reason + " error=" + refreshRecordError);
        }
    }

    /**
     * 七个宠物资产操作的 exact 领域快照。通用容器/货币由 ItemUtil 负责；
     * 宠物槽、涨价计数与出战/格子标量由本服务恢复。所有恢复均发生在 PAT
     * settle(false) 之前，只有完整成功才丢弃 partial receipt。
     */
    private static function capturePetTransactionState():Object {
        var ext:Object = _root._saveExt;
        var purchaseCountsExists:Boolean = ext != undefined && ext != null
            && ext.hasOwnProperty("宠物购买次数");
        return {
            assets:ItemUtil.capturePlayerAssetSnapshot(),
            petInfo:ObjectUtil.clone(_root.宠物信息),
            purchaseCountsExists:purchaseCountsExists,
            purchaseCounts:purchaseCountsExists
                ? ObjectUtil.clone(ext.宠物购买次数) : null,
            petSlotLimit:_root.宠物领养限制,
            maxDeploy:_root.最大宠物出战数,
            deployedIds:ObjectUtil.clone(_root.出战宠物id库)
        };
    }

    private static function restorePetTransactionState(snapshot:Object):Boolean {
        if (snapshot == null) return false;
        try {
            _root.宠物信息 = ObjectUtil.clone(snapshot.petInfo);
            _root.宠物领养限制 = snapshot.petSlotLimit;
            _root.最大宠物出战数 = snapshot.maxDeploy;
            _root.出战宠物id库 = ObjectUtil.clone(snapshot.deployedIds);
            if (snapshot.purchaseCountsExists === true) {
                if (_root._saveExt == undefined || _root._saveExt == null) {
                    _root._saveExt = {};
                }
                _root._saveExt.宠物购买次数 = ObjectUtil.clone(
                    snapshot.purchaseCounts);
            } else if (_root._saveExt != undefined && _root._saveExt != null) {
                delete _root._saveExt.宠物购买次数;
            }
        } catch (petRestoreError) {
            trace("[PetPanelService] pet authority snapshot restore failed: "
                + petRestoreError);
            return false;
        }
        return ItemUtil.restorePlayerAssetSnapshot(snapshot.assets);
    }

    // ── 宠物购买涨价（持久）─────────────────────────────────────────────
    // IncreasePrice>0 的宠物每购买一次金币价 +IncreasePrice。已购次数持久化于
    // _root._saveExt.宠物购买次数（存档预留命名空间，随 mydata.ext 往返，无需改 SaveManager/C#）。
    // Price 不再原地改写 宠物库 配置（配置保持只读=基础价），价格处处由次数计算。
    private static function getPetPurchaseCount(petId:Number):Number {
        var ext:Object = _root._saveExt;
        if (ext == undefined || ext.宠物购买次数 == undefined) return 0;
        var c:Number = Number(ext.宠物购买次数[petId]);
        return isNaN(c) ? 0 : c;
    }

    private static function getPetCurrentPrice(petId:Number):Number {
        // 权威单一来源：引擎 _root.获取宠物当前售价（战宠系统.as），与刷怪雇佣价同口径。
        // 下方 inline 仅作 fallback，防 asLoader 先于主 SWF 重发布的过渡期。
        if (typeof _root.获取宠物当前售价 == "function") return Number(_root.获取宠物当前售价(petId));
        var def:Object = _root.宠物库[petId];
        if (def == undefined) return 0;
        var base:Number = Number(def.Price) || 0;
        var inc:Number = Number(def.IncreasePrice) || 0;
        if (inc <= 0) return base;
        return base + inc * getPetPurchaseCount(petId);
    }

    private static function incrementPetPurchaseCount(petId:Number):Void {
        if (_root._saveExt == undefined) _root._saveExt = {};
        if (_root._saveExt.宠物购买次数 == undefined) _root._saveExt.宠物购买次数 = {};
        var c:Number = Number(_root._saveExt.宠物购买次数[petId]);
        _root._saveExt.宠物购买次数[petId] = (isNaN(c) ? 0 : c) + 1;
    }

    /** 计算最大出战数 */
    private static function calcMaxDeploy():Number {
        if (_root.战宠UI函数 != undefined && _root.战宠UI函数.计算战宠最大出战数 != undefined) {
            return Number(_root.战宠UI函数.计算战宠最大出战数());
        }
        if (_root.isChallengeMode != undefined && _root.isChallengeMode()) {
            return Math.ceil(Number(_root.等级) / 35);
        }
        return Math.min(Math.ceil(Number(_root.等级) / 5), 5);
    }

    /** 统计当前出战数 */
    private static function countDeployed():Number {
        var count:Number = 0;
        for (var i:Number = 0; i < _root.宠物信息.length; i++) {
            if (_root.宠物信息[i] != undefined && _root.宠物信息[i][4] == 1) {
                count++;
            }
        }
        return count;
    }

    /** 计算战宠升级所需经验（简化公式） */
    // 计算指定兵种在 level 级的升级所需经验。优先用引擎权威公式（依赖 敌人属性表[兵种] 的
    // 真实经验区间），与 handleLevelUp 的扣费基准一致，确保前端预览 == 实际扣费。
    private static function calcXpForLevel(identifier:String, level:Number):Number {
        if (_root.战宠UI函数 != undefined && _root.战宠UI函数.计算战宠升级所需经验 != undefined
            && identifier != undefined && identifier != "") {
            var v:Number = Number(_root.战宠UI函数.计算战宠升级所需经验(identifier, level));
            if (!isNaN(v) && v > 0) return v;
        }
        // 引擎不可用时的粗略回退估算
        return Math.floor((50 + ((400 - 50) / 59) * level) * level);
    }

    // ═══════════════════════════════════════════════════════════
    // buildCombatStats — 战斗数值成长展示（仅展示，非战斗权威）
    // 三点采样（起点 Lv.1 / 当前等级 / 满级 _root.等级限制），每点 = 基线插值
    // + 已达成进阶方案加成，供 JS 渲染「起点→当前→终点」成长条。
    // 兵种缺属性表时返回 undefined，snapshot 不下发，JS 隐藏区块。
    // ═══════════════════════════════════════════════════════════
    private static function buildCombatStats(identifier:String, level:Number, petAttrs:Object):Object {
        var ep:Object = _root.敌人属性表[identifier];
        if (ep == undefined || _root.根据等级计算值 == undefined) return undefined;
        if (isNaN(Number(ep.hp_min))) return undefined;

        var maxLevel:Number = Number(_root.等级限制) || 100;
        var startP:Object = statsAtLevel(ep, 1, petAttrs);
        var curP:Object   = statsAtLevel(ep, level, petAttrs);
        var maxP:Object   = statsAtLevel(ep, maxLevel, petAttrs);

        return {
            hp:      { start: startP.hp,      cur: curP.hp,      max: maxP.hp },
            attack:  { start: startP.attack,  cur: curP.attack,  max: maxP.attack },
            defense: { start: startP.defense, cur: curP.defense, max: maxP.defense },
            speed:   { start: startP.speed,   cur: curP.speed,   max: maxP.speed },
            startLevel: 1,
            maxLevel: maxLevel,
            difficulty: Number(_root.难度等级) || 1
        };
    }

    // 经逐一审计确认"纯数值"的进阶方案白名单：其 单位进阶执行 只读 this.宠物属性、
    // 只写 this 上的数值字段，无任何 _root / 全局副作用，可安全在纯对象 sim 上重放。
    // 常驻淬毒 被刻意排除——它的 单位进阶执行 是"进图扣费上毒"运行时逻辑：战斗地图上会
    // 真实扣 _root.金钱（500/次，三点采样 = 每次快照每只宠最多误扣 1500）并 发布消息。
    // 它也不影响 hp/攻击/防御/速度 展示，排除零损失。
    // 新增方案默认不重放（成长条少算加成，纯展示损失），审计确认无副作用后再加入。
    private static var PURE_ADVANCE_SCHEMES:Object = {
        基础训练: true, 强化药剂: true, 超级血清: true,
        弹射弧光斩: true, 广域裂空斩: true, 导弹烈炎炮: true,
        冲腿龙息: true, 晶能者: true, 复仇者: true, 抱头嘲讽: true,
        涅槃重生: true, 影子刺客: true, 追踪飞弹: true, 驯鹰者: true,
        美洲狮: true, 追猎: true, 战马血清: true, 钙化: true,
        终结者步枪: true, 净化治疗: true, 溢出治疗: true,
        能量子弹: true, 剧毒子弹: true
    };

    // 在指定等级模拟出战实体的最终数值：
    // 1) 基线 = 敌人函数.根据等级初始数值 同构插值（hp/攻击 × _root.难度等级，防御/速度不随）；
    // 2) 进阶 = 敌人函数.宠物属性初始化 同构地重放 已达成方案的 单位进阶执行——
    //    仅限 PURE_ADVANCE_SCHEMES 白名单内方案（见上），写入只落在 sim 上，
    //    绝不回写真实 宠物属性。
    private static function statsAtLevel(ep:Object, level:Number, petAttrs:Object):Object {
        var diff:Number = Number(_root.难度等级) || 1;
        var sim:Object = {
            hp满血值:   Math.floor(_root.根据等级计算值(ep.hp_min, ep.hp_max, level) * diff),
            空手攻击力: Math.floor(_root.根据等级计算值(ep.空手攻击力_min, ep.空手攻击力_max, level) * diff),
            防御力:     Number(_root.根据等级计算值(ep.基本防御力_min, ep.基本防御力_max, level)),
            行走X速度:  Number(_root.根据等级计算值(ep.速度_min, ep.速度_max, level)) / 10,
            韧性系数:   0,
            hp:         0,
            已有称号:   true,
            宠物属性:   (petAttrs != undefined) ? petAttrs : {}
        };
        if (petAttrs != undefined && _root.战宠进阶函数 != undefined) {
            for (var key:String in petAttrs) {
                if (PURE_ADVANCE_SCHEMES[key] != true) continue; // 只重放审计过的纯数值方案
                var schemeDef:Object = _root.战宠进阶函数[key];
                if (schemeDef != undefined && typeof schemeDef.单位进阶执行 == "function") {
                    sim.单位进阶执行 = schemeDef.单位进阶执行;
                    sim.单位进阶执行();
                }
            }
        }
        return {
            hp:      Math.floor(sim.hp满血值),
            attack:  Math.floor(sim.空手攻击力),
            defense: Math.floor(sim.防御力),
            speed:   Math.round(sim.行走X速度 * 10)
        };
    }

    // 解析 pets.xml 的 <Promotion><Item>方案名</Item></Promotion>。通用 XML 解析器
    // (解析XML节点) 会把多个同名 <Item> 折成 {Item: 数组}，单个折成 {Item: 字符串}，
    // 空则整个 Promotion 缺省。统一归一化为方案名字符串数组，供 JS 进阶列表使用。
    private static function extractPromotionNames(promo:Object):Array {
        if (promo == undefined) return [];
        if (promo instanceof Array) return promo.slice(); // 防御：已是数组
        var items:Object = promo.Item;
        if (items == undefined) return [];
        var out:Array = [];
        if (items instanceof Array) {
            for (var i:Number = 0; i < items.length; i++) out.push(String(items[i]));
        } else {
            out.push(String(items)); // 单个 Item
        }
        return out;
    }

    // 用真实宠物 ctx 计算反复型(开关)方案的列表描述（自带当前开关状态）。先调 初始化 补默认值
    // （如 切换发型 默认发色），避免显示 "undefined发"；再取 描述（短文，含"点击可开启/关闭"等状态语）
    // 的首段。
    // 注意：当前宠物属性 用浅拷贝而非真实 attrs 引用——初始化 会向 ctx.当前宠物属性 写默认值
    // （如 发色="橙"），若直接传真实 attrs，纯展示的描述构建会静默改写权威内存态（不标脏 → 与存档脱同步）。
    // 浅拷贝后 初始化 只动副本，描述照常显示默认值，真实 attrs 保持只读。
    private static function buildSchemePerPetDesc(sc:Object, info:Array, attrs:Object, petSchemeSet:Object):String {
        var ctxAttrs:Object = {};
        if (attrs != undefined && typeof attrs == "object") {
            for (var k:String in attrs) ctxAttrs[k] = attrs[k];
        }
        var ctx:Object = { 当前宠物信息: info, 当前宠物属性: ctxAttrs, 进阶方案: petSchemeSet };
        if (typeof sc.初始化 == "function") sc.初始化.call(ctx); // 补默认值（如发色），只动副本
        var d:String = "";
        if (typeof sc.描述 == "function") d = String(sc.描述.call(ctx));
        else if (sc.描述 != undefined) d = String(sc.描述);
        var br:Number = d.indexOf("<br>");
        if (br >= 0) d = d.substring(0, br);
        return d;
    }

    // 反复型方案的类内回退映射。权威来源是 战宠进阶函数[方案].进阶类型，但该数据定义在帧脚本
    // (单位函数_aka_战宠进阶.as)里，需重发布主 SWF 才生效；本类经 asLoader 单独编译刷新更快。
    // 为避免"类已更新、帧脚本未重发布"时反复型方案被误锁，这里内置已知集合作回退（字段优先于回退）。
    private static var _repeatableTypes:Object = null;
    private static function getRepeatableTypes():Object {
        if (_repeatableTypes == null) {
            _repeatableTypes = { 常驻淬毒:"开关", 切换发型:"开关", 影子刺客:"购买后开关" };
        }
        return _repeatableTypes;
    }

    // 取方案进阶类型："开关"/"购买后开关"（反复型）或 ""（一次性购买/三件套）。
    // 字段(进阶类型)优先；缺失时回退到类内已知集合。
    private static function getSchemeType(schemeName:String, sc:Object):String {
        if (sc != undefined && sc.进阶类型 != undefined && sc.进阶类型 != "") return String(sc.进阶类型);
        var m:Object = getRepeatableTypes();
        return (m[schemeName] != undefined) ? String(m[schemeName]) : "";
    }

    // 判定某进阶方案是否为"可反复执行"型（开关 / 购买后开关），这类方案永不进入"已完成"锁死态。
    // 进阶类型="开关"      纯开关(切换发型/常驻淬毒)：无前置购买，反复切换。
    // 进阶类型="购买后开关" 混合(影子刺客)：首次=一次性付费购买，购买后=免费启用/停用开关。
    private static function isSchemeRepeatable(schemeName:String, sc:Object):Boolean {
        var t:String = getSchemeType(schemeName, sc);
        return t == "开关" || t == "购买后开关";
    }

    // 判定某进阶方案对该宠物是否已完成（用于 UI 禁用 + handleAdvance 服务端守卫）。
    // 反复型(开关/购买后开关)永不"完成"（否则会被锁死无法再切换，见影子刺客/常驻淬毒）；
    // 三件套(基础训练/强化药剂/超级血清)共用累进计数 基础训练.次数，按各自 次数上限(>0) 判定；
    // 一次性付费方案(钙化/武器升级等)按自身布尔标志判定。
    // 隐含契约：次数上限>0 的方案当前均以 基础训练.次数 为权威累进计数（仅三件套），新增此类方案须沿用同源计数。
    private static function isSchemeCompleted(schemeName:String, sc:Object, attrs:Object):Boolean {
        if (sc == undefined) return false;
        if (isSchemeRepeatable(schemeName, sc)) return false;
        if (sc.次数上限 != undefined && Number(sc.次数上限) > 0) {
            var cnt:Number = (attrs != undefined && attrs.基础训练 != undefined) ? (Number(attrs.基础训练.次数) || 0) : 0;
            return cnt >= Number(sc.次数上限);
        }
        var paid:Boolean = (Number(sc.消耗金币) || 0) > 0 || (Number(sc.消耗K点) || 0) > 0;
        if (!paid) return false;
        var flag:Object = (attrs != undefined) ? attrs[schemeName] : undefined;
        return flag != undefined && flag !== false && flag !== 0 && flag !== "";
    }

    // 判定"购买后开关"型方案的前置一次性购买是否已完成（决定 UI 显示"购买价"还是"免费开关"）。
    // 纯开关型无购买前置，恒视为已就绪；非反复型不适用。
    private static function isSchemePurchased(schemeName:String, sc:Object, attrs:Object):Boolean {
        var t:String = getSchemeType(schemeName, sc);
        if (t == "开关") return true; // 纯开关无购买前置
        if (t != "购买后开关") return false;
        var flag:Object = (attrs != undefined) ? attrs[schemeName] : undefined;
        return flag != undefined && flag !== false && flag !== 0 && flag !== "";
    }

    // 判定方案锁定原因（细分等级锁/前置锁，供 JS 区分文案）。
    //   ""      = 未锁
    //   "level" = 等级未达 解锁等级
    //   "prereq"= 显式前置方案或前置累进未达（三件套链 基础训练→强化药剂→超级血清）
    // 等级优先：若等级也不够则先报 level（升级是更靠前的硬门槛）。
    //
    // petSchemeSet = 本宠物自己的方案子集（按 Promotion 过滤的全局表）。还原原始设计：
    // 次数前置仅当本宠链里**确实存在更低阶前置**（基础训练/强化药剂）时才强制；中/强体质宠
    // 从更高档起步（promotion 不含低阶训练），前置天然满足，不再被误锁。等价条件函数里的
    // `if(进阶方案.基础训练 && ...)` / `if((进阶方案.基础训练||进阶方案.强化药剂) && ...)` 守卫。
    private static function schemeLockReason(sc:Object, attrs:Object, petLevel:Number, petSchemeSet:Object):String {
        if (sc == undefined) return "level";
        if (petLevel < (Number(sc.解锁等级) || 0)) return "level";
        if (sc.前置方案 != undefined && String(sc.前置方案) != "") {
            var prerequisite:String = String(sc.前置方案);
            var prerequisiteValue:Object = attrs == undefined ? undefined : attrs[prerequisite];
            if (prerequisiteValue == undefined || prerequisiteValue === false
                    || prerequisiteValue === 0 || prerequisiteValue === "") return "prereq";
        }
        var req:Number = Number(sc.次数条件);
        if (sc.次数条件 != undefined && req > 0) {
            // 本宠链里是否有产出"次数<req"的更低阶前置：基础训练产出次数1，强化药剂产出次数2。
            var enforce:Boolean = false;
            if (petSchemeSet != undefined) {
                if (petSchemeSet["基础训练"] != undefined) enforce = true;
                else if (req >= 2 && petSchemeSet["强化药剂"] != undefined) enforce = true;
            }
            if (enforce) {
                var cnt:Number = (attrs != undefined && attrs.基础训练 != undefined) ? (Number(attrs.基础训练.次数) || 0) : 0;
                if (cnt < req) return "prereq";
            }
        }
        return "";
    }

    // 构造本宠物专属的进阶方案子集（仅含该宠 Promotion 列表里、且全局表确有定义的方案）。
    // 还原"进阶方案 = 本宠子集"的原始语义：传给条件/描述函数的 ctx.进阶方案 用它而非全局表，
    // 使 `进阶方案.基础训练` 对缺该档的宠物为 undefined → 守卫短路 → 跳过低阶前置直接可用。
    private static function buildPetSchemeSet(petId:Number):Object {
        var def:Object = _root.宠物库[petId];
        if (def == undefined) return {};
        return filterSchemeSet(extractPromotionNames(def.Promotion));
    }

    private static function filterSchemeSet(names:Array):Object {
        var set:Object = {};
        if (names == undefined) return set;
        for (var i:Number = 0; i < names.length; i++) {
            var nm:String = String(names[i]);
            if (_root.战宠进阶函数[nm] != undefined) set[nm] = _root.战宠进阶函数[nm];
        }
        return set;
    }

    // 读取开关类方案的当前状态（per-scheme：各方案状态字段不统一，无通用契约，故按方案名分派）。
    //   { kind:"binary", on:Boolean }  —— 二元开关（常驻淬毒.启用 / 影子单位）：JS 渲染 ON/OFF 拨动开关
    //   { kind:"cycle",  value:String } —— 多值循环（发型当前色）：JS 渲染当前值色块 chip
    //   undefined                       —— 非状态型开关：JS 回退通用按钮
    // 注：状态字段取自 当前宠物属性（存档权威），只读不写。新增开关方案需在此登记。
    private static function readToggleState(schemeName:String, attrs:Object):Object {
        if (attrs == undefined) attrs = {};
        // 注：字段名避开 AS2 保留字（on/onClipEvent 等是事件处理器关键字，作对象键会导致解析失败）。
        if (schemeName == "常驻淬毒") {
            var t:Object = attrs.常驻淬毒;
            return { kind: "binary", enabled: (t != undefined && t.启用 == true) };
        }
        if (schemeName == "影子刺客") {
            // 购买前无开关意义（JS 以 purchased=false 渲染购买按钮）；购买后读 影子单位 的启停。
            return { kind: "binary", enabled: (attrs.影子单位 == true) };
        }
        if (schemeName == "切换发型") {
            var c:String = (attrs.发色 != undefined) ? String(attrs.发色) : "橙";
            return { kind: "cycle", value: c + "发" };
        }
        return undefined;
    }
}
