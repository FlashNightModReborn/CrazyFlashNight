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
 *     petPanelOpen      — 面板打开时准备数据
 *     petPanelClose     — 面板关闭时刷新 UI
 *
 * 关键不变量：
 *   - 所有写操作必须通过本桥执行，保证 _root.宠物信息 是唯一数据源
 *   - 响应格式：{ task: "pet_response", callId: callId, success: true/false, ... }
 *   - 使用 LiteJSON 序列化（与 ArenaPanelService 相同）
 */
import LiteJSON;

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
        _root.gameCommands["petRestoreStamina"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleRestoreStamina(params);
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

        _inited = true;
    }

    // ═══════════════════════════════════════════════════════════
    // handleSnapshot — 返回全部宠物状态快照
    // ═══════════════════════════════════════════════════════════
    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        var pets:Array = [];
        var 宠物信息:Array = _root.宠物信息;

        for (var i:Number = 0; i < 宠物信息.length; i++) {
            var info:Array = 宠物信息[i];
            if (info == undefined || info.length < 5) continue;
            var petDef:Object = _root.宠物库[info[0]];
            if (petDef == undefined) continue;

            var petEntry:Object = {
                slotIndex: i,
                petId: Number(info[0]),
                name: String(petDef.Name),
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

        // 执行购买
        if (price > 0) _root.金钱 -= price;
        if (kprice > 0) _root.虚拟币 -= kprice;

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
        // Plan A audit: handleBuy 写 金钱/虚拟币/宠物信息/购买次数，必须标脏
        _root.存档系统.dirtyMark = true;

        // 刷新宠物UI
        if (_root.宠物信息界面 != undefined && _root.宠物信息界面.排列宠物图标 != undefined) {
            _root.宠物信息界面.排列宠物图标();
        }

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

        // 执行出战/休息（由现有引擎函数处理）
        // 使用 _parent._parent 路径说明：原 Flash UI 的按钮函数依赖 _parent 作用域。
        // 从 Web 面板调用时，我们直接修改 _root 状态并调用引擎函数。
        var prevState:Number = petInfo[4];
        petInfo[4] = (prevState == 1) ? 0 : 1;

        var success:Boolean = false;
        if (petInfo[4] == 1) {
            // 出战：需要创建宠物单位
            var hero:MovieClip = undefined;
            if (typeof _root.gameworld != "undefined") {
                // 尝试通过 TargetCacheManager 获取主角位置
                var heroX:Number = 500;
                var heroY:Number = 300;
                if (typeof org != "undefined" && org.flashNight != undefined
                    && org.flashNight.arki != undefined && org.flashNight.arki.unit != undefined
                    && org.flashNight.arki.unit.UnitComponent != undefined
                    && org.flashNight.arki.unit.UnitComponent.Targetcache != undefined
                    && org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager != undefined) {
                    hero = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager.findHero();
                    if (hero != undefined) {
                        heroX = hero._x;
                        heroY = hero._y;
                    }
                }
                success = _root.战宠UI函数.设置宠物出战(slotIndex, true, heroX, heroY);
            }
        } else {
            // 休息：移除宠物单位
            success = _root.战宠UI函数.设置宠物出战(slotIndex, false);
        }

        if (!success) {
            // 引擎拒绝（体力不足 / 宠物mc库已存在该 id / 找不到待移除 mc，或无 gameworld）：
            // 回滚出战标志，保持存档与场上 mc 一致，避免"出战中却无宠物"或反之的错位坏档。
            // 对齐引擎 出战按钮函数 的 success 回滚契约。
            petInfo[4] = prevState;
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "deploy_failed", deployed: prevState == 1, currentDeployCount: countDeployed(), maxDeploy: maxDeploy });
            return;
        }

        // 出战标志（petInfo[4]）属存档字段，写入成功后标脏
        _root.存档系统.dirtyMark = true;

        // 刷新UI
        if (_root.宠物信息界面 != undefined && _root.宠物信息界面.排列宠物图标 != undefined) {
            _root.宠物信息界面.排列宠物图标();
        }

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

        var ctx:Object = {
            当前宠物信息: _root.宠物信息[slotIndex],
            当前宠物属性: _root.宠物信息[slotIndex][5],
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

        // 执行进阶
        var execFn:Function = scheme.执行;
        if (typeof execFn == "function") {
            execFn.call(ctx);
        }

        // 进阶 执行 写入 金钱 / 宠物属性（均存档字段），标脏
        _root.存档系统.dirtyMark = true;

        // 刷新宠物单位（如果已出战）
        if (ctx.当前宠物信息[4] == 1) {
            _root.宠物升级加载(slotIndex);
        }

        // 刷新UI
        if (_root.宠物信息界面 != undefined && _root.宠物信息界面.排列宠物图标 != undefined) {
            _root.宠物信息界面.排列宠物图标();
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            slotIndex: slotIndex,
            scheme: schemeName,
            gold: Number(_root.金钱) || 0,
            kpoint: Number(_root.虚拟币) || 0
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

        _root.金钱 -= expandCost;
        _root.开宠物格子();

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

        if (isNaN(slotIndex) || slotIndex < 0 || slotIndex >= _root.宠物信息.length) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_slot" });
            return;
        }
        if (newName == "" || newName.length > 10) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_name" });
            return;
        }

        // 宠物重命名：在 宠物属性 中存储自定义名称
        var petInfo:Array = _root.宠物信息[slotIndex];
        var attrs:Object = petInfo[5];
        if (attrs == undefined) {
            attrs = {};
            petInfo[5] = attrs;
        }
        attrs.customName = newName;
        // customName 存于 宠物属性[5]（随 宠物信息 落盘），标脏
        _root.存档系统.dirtyMark = true;

        // 刷新UI
        if (_root.宠物信息界面 != undefined && _root.宠物信息界面.排列宠物图标 != undefined) {
            _root.宠物信息界面.排列宠物图标();
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            slotIndex: slotIndex,
            name: newName
        });
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
    // handleRestoreStamina — 消耗金币恢复宠物体力
    // ═══════════════════════════════════════════════════════════
    public static function handleRestoreStamina(params:Object):Void {
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

        var currentStamina:Number = Number(petInfo[2]);
        if (currentStamina >= 200) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "stamina_full" });
            return;
        }

        var cost:Number = 1000;
        if (_root.金钱 < cost) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "insufficient_gold", cost: cost });
            return;
        }

        _root.金钱 -= cost;
        petInfo[2] = 200;
        // 金钱 / 宠物体力(petInfo[2]) 均存档字段，标脏
        _root.存档系统.dirtyMark = true;

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            slotIndex: slotIndex,
            stamina: 200,
            gold: Number(_root.金钱) || 0
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleLevelUp — 消耗战宠灵石升级
    // ═══════════════════════════════════════════════════════════
    public static function handleLevelUp(params:Object):Void {
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

        var currentLevel:Number = Number(petInfo[1]);
        var levelLimit:Number = Number(_root.等级限制) || 100;
        if (currentLevel >= levelLimit) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "level_maxed" });
            return;
        }

        var petId:Number = Number(petInfo[0]);
        var petDef:Object = _root.宠物库[petId];
        if (petDef == undefined) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "pet_not_found" });
            return;
        }
        var identifier:String = String(petDef.Identifier);

        // 确保经验值已初始化
        var attrs:Object = petInfo[5];
        if (attrs == undefined || typeof attrs != "object") {
            attrs = {};
            petInfo[5] = attrs;
        }
        if (Number(attrs.宠物升级所需经验) <= 0 && _root.战宠UI函数 != undefined
            && _root.战宠UI函数.计算战宠升级所需经验 != undefined) {
            attrs.宠物升级所需经验 = _root.战宠UI函数.计算战宠升级所需经验(identifier, currentLevel);
        }
        var xpNeeded:Number = Number(attrs.宠物升级所需经验) || 0;
        var stoneCost:Number = currentLevel * 2 + Math.floor(xpNeeded / 10000);
        if (stoneCost <= 0) stoneCost = 1;

        // 扣除灵石
        if (!_root.singleSubmit("战宠灵石", stoneCost)) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "insufficient_stones", cost: stoneCost });
            return;
        }

        // 升级
        petInfo[1] = currentLevel + 1;
        var newLevel:Number = petInfo[1];

        // 重新计算下一级经验需求
        var newXpNeeded:Number = 0;
        if (_root.战宠UI函数 != undefined && _root.战宠UI函数.计算战宠升级所需经验 != undefined) {
            newXpNeeded = Number(_root.战宠UI函数.计算战宠升级所需经验(identifier, newLevel));
        }
        attrs.宠物升级所需经验 = newXpNeeded;
        // 等级(petInfo[1]) / 宠物升级所需经验 均存档字段，标脏（singleSubmit 已扣灵石，但等级写入需独立保证落盘）
        _root.存档系统.dirtyMark = true;

        // 刷新出战宠物单位（注意：宠物升级加载 的参数是 mc库索引）
        if (petInfo[4] == 1 && _root.出战宠物id库 != undefined) {
            var mcIdx:Number = -1;
            for (var m:Number = 0; m < _root.出战宠物id库.length; m++) {
                if (_root.出战宠物id库[m] == slotIndex) {
                    mcIdx = m;
                    break;
                }
            }
            if (mcIdx >= 0 && _root.宠物升级加载 != undefined) {
                _root.宠物升级加载(mcIdx);
            }
        }

        // 刷新 Flash UI
        if (_root.宠物信息界面 != undefined && _root.宠物信息界面.排列宠物图标 != undefined) {
            _root.宠物信息界面.排列宠物图标();
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            slotIndex: slotIndex,
            newLevel: newLevel,
            stoneCost: stoneCost,
            newXpNeeded: newXpNeeded,
            levelLimit: levelLimit
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleDelete — 删除宠物并返还灵石
    // ═══════════════════════════════════════════════════════════
    public static function handleDelete(params:Object):Void {
        var callId = params.callId;
        var slotIndex:Number = Number(params.slotIndex);
        if (isNaN(slotIndex) || slotIndex < 0 || slotIndex >= _root.宠物信息.length) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "invalid_slot" });
            return;
        }

        var petInfo:Array = _root.宠物信息[slotIndex];
        if (petInfo == undefined || petInfo.length == 0) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "empty_slot" });
            return;
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

        // 清理场上所有宠物 MC
        if (_root.删除场景宠物 != undefined) {
            _root.删除场景宠物();
        }

        // 返还灵石
        if (stoneRefund > 0) {
            _root.singleAcquire("战宠灵石", stoneRefund);
        }

        // 清空槽位
        _root.宠物信息[slotIndex] = [];
        // 删除宠物 + 返还灵石均存档字段；返还为 0 时 singleAcquire 不触发标脏，故此处独立标脏
        _root.存档系统.dirtyMark = true;

        // 重建场上其他出战宠物
        var hasDeployed:Boolean = false;
        for (var k:Number = 0; k < _root.宠物信息.length; k++) {
            if (_root.宠物信息[k] != undefined && _root.宠物信息[k].length > 0 && _root.宠物信息[k][4] == 1) {
                hasDeployed = true;
                break;
            }
        }
        if (hasDeployed && _root.加载宠物 != undefined) {
            var heroX:Number = 500;
            var heroY:Number = 300;
            if (typeof org != "undefined" && org.flashNight != undefined
                && org.flashNight.arki != undefined && org.flashNight.arki.unit != undefined
                && org.flashNight.arki.unit.UnitComponent != undefined
                && org.flashNight.arki.unit.UnitComponent.Targetcache != undefined
                && org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager != undefined) {
                var hero:MovieClip = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager.findHero();
                if (hero != undefined) {
                    heroX = hero._x;
                    heroY = hero._y;
                }
            }
            _root.加载宠物(heroX, heroY);
        }

        // 刷新 Flash UI
        if (_root.宠物信息界面 != undefined && _root.宠物信息界面.排列宠物图标 != undefined) {
            _root.宠物信息界面.排列宠物图标();
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            slotIndex: slotIndex,
            deleted: true,
            stoneRefund: stoneRefund
        });
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
        if (_root.宠物信息界面 != undefined && _root.宠物信息界面.排列宠物图标 != undefined) {
            _root.宠物信息界面.排列宠物图标();
        }
        var callId = params.callId;
        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true
        });
    }

    // ═══════════════════════════════════════════════════════════
    // 工具函数
    // ═══════════════════════════════════════════════════════════

    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
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
    //   "prereq"= 前置累进未达（次数条件 = 需要的 基础训练.次数；三件套链 基础训练→强化药剂→超级血清）
    // 等级优先：若等级也不够则先报 level（升级是更靠前的硬门槛）。
    //
    // petSchemeSet = 本宠物自己的方案子集（按 Promotion 过滤的全局表）。还原原始设计：
    // 次数前置仅当本宠链里**确实存在更低阶前置**（基础训练/强化药剂）时才强制；中/强体质宠
    // 从更高档起步（promotion 不含低阶训练），前置天然满足，不再被误锁。等价条件函数里的
    // `if(进阶方案.基础训练 && ...)` / `if((进阶方案.基础训练||进阶方案.强化药剂) && ...)` 守卫。
    private static function schemeLockReason(sc:Object, attrs:Object, petLevel:Number, petSchemeSet:Object):String {
        if (sc == undefined) return "level";
        if (petLevel < (Number(sc.解锁等级) || 0)) return "level";
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
