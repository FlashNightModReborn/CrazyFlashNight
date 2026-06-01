/**
 * 文件：org/flashNight/arki/merc/PetPanelService.as
 * 说明：WebView 战宠面板的 AS2 端桥。
 *
 * 同步管道（与 ArenaPanelService / MapPanelService 同构）：
 *   Web → C# PetTask → Flash gameCommands:
 *     petSnapshot       — 返回全部宠物信息快照 + 玩家状态
 *     petAdoptList      — 返回可领养宠物列表（按分类）
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
        _root.gameCommands["petAdoptList"] = function(params) {
            org.flashNight.arki.merc.PetPanelService.handleAdoptList(params);
        };
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

            // 每方案权威完成/锁定状态（替代 JS 端按方案名查 次数 的错误推断；
            // 三件套共用 基础训练.次数 计数，布尔方案查自身标志）
            var statusMap:Object = {};
            var schemeNames:Array = extractPromotionNames(petDef.Promotion);
            for (var sIdx:Number = 0; sIdx < schemeNames.length; sIdx++) {
                var sNm:String = String(schemeNames[sIdx]);
                var scDef:Object = _root.战宠进阶函数[sNm];
                if (scDef == undefined) continue;
                statusMap[sNm] = {
                    completed: isSchemeCompleted(sNm, scDef, attrs),
                    locked: isSchemeLocked(scDef, attrs, Number(info[1])),
                    // 反复型(开关/购买后开关)：JS 据此渲染为可反复点击的开关按钮，不显示"已完成"。
                    repeatable: isSchemeRepeatable(sNm, scDef),
                    // 购买后开关的前置购买是否完成（纯开关恒 true）：决定显示购买价还是免费开关。
                    purchased: isSchemePurchased(sNm, scDef, attrs)
                };
            }
            petEntry.schemeStatus = statusMap;

            pets.push(petEntry);
        }

        // 序列化宠物库摘要（名称+ID映射）
        var petLib:Array = [];
        for (var pid:Number = 0; pid < _root.宠物库.length; pid++) {
            var def:Object = _root.宠物库[pid];
            if (def != undefined) {
                petLib.push({
                    id: pid,
                    name: String(def.Name),
                    identifier: String(def.Identifier),
                    height: Number(def.Height),
                    initialLevel: Number(def.InitialLevel),
                    unlockLevel: Number(def.UnlockLevel),
                    unlockTask: Number(def.UnlockTask),
                    unique: def.Unique == true,
                    price: Number(def.Price),
                    kprice: Number(def.KPrice),
                    increasePrice: Number(def.IncreasePrice),
                    promotions: extractPromotionNames(def.Promotion)
                });
            }
        }

        // 序列化进阶方案数据字段（B1：数值/文本字段下发，逻辑函数 条件/执行 留 AS2）。
        // 这是 JS 进阶列表的权威来源，替代已删除的 pet-data.js SCHEMES（含修正后的累进 次数上限）。
        var schemesMap:Object = {};
        var advFns:Object = _root.战宠进阶函数;
        for (var sName:String in advFns) {
            var sc:Object = advFns[sName];
            if (sc == undefined || typeof sc != "object") continue;
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

        // 序列化商城分类名（A1：替代已删除的 pet-data.js CATEGORIES；网格内容仍由 adopt_list 下发）
        var categoriesArr:Array = [];
        if (_root.宠物商城列表 != undefined) {
            for (var catIdx:Number = 0; catIdx < _root.宠物商城列表.length; catIdx++) {
                var catDef:Object = _root.宠物商城列表[catIdx];
                if (catDef == undefined) continue;
                categoriesArr.push({ name: String(catDef.Name) });
            }
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            snapshot: {
                pets: pets,
                petLib: petLib,
                schemes: schemesMap,
                categories: categoriesArr,
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

    // ═══════════════════════════════════════════════════════════
    // handleAdoptList — 返回可领养宠物列表
    // ═══════════════════════════════════════════════════════════
    public static function handleAdoptList(params:Object):Void {
        var callId = params.callId;
        var categoryIdx:Number = Number(params.categoryIndex);
        if (isNaN(categoryIdx)) categoryIdx = -1;

        var adoptable:Array = [];
        if (_root.宠物商城列表 != undefined) {
            for (var c:Number = 0; c < _root.宠物商城列表.length; c++) {
                if (categoryIdx >= 0 && c != categoryIdx) continue;
                var cat:Object = _root.宠物商城列表[c];
                // cat.List 是二维数组：[[0,1,2], [3,4,5], ...]（XML 解析时按 <List> 分行）
                var rows:Array = cat.List;
                if (rows == undefined) continue;
                for (var j:Number = 0; j < rows.length; j++) {
                    var row:Array = rows[j];
                    if (row == undefined) continue;
                    for (var m:Number = 0; m < row.length; m++) {
                        var petId:Number = Number(row[m]);
                        if (isNaN(petId) || petId == null) continue;
                        var petDef:Object = _root.宠物库[petId];
                        if (petDef == undefined) continue;

                        adoptable.push({
                            petId: petId,
                            name: String(petDef.Name),
                            identifier: String(petDef.Identifier),
                            height: Number(petDef.Height),
                            price: Number(petDef.Price),
                            kprice: Number(petDef.KPrice),
                            unlockLevel: Number(petDef.UnlockLevel),
                            unlockTask: Number(petDef.UnlockTask),
                            unique: petDef.Unique == true
                        });
                    }
                }
            }
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            adoptable: adoptable
        });
    }

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

        // 检查金币/K点
        var price:Number = Number(petDef.Price);
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

        // 处理 IncreasePrice（每次购买后涨价）
        if (Number(petDef.IncreasePrice) > 0) {
            petDef.Price += Number(petDef.IncreasePrice);
        }

        _root.宠物信息[emptySlot] = newPet;
        // Plan A audit: handleBuy 写 金钱/虚拟币/宠物信息，必须标脏
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

        // 设置上下文（模拟 Flash UI 的 this 上下文）
        var ctx:Object = {
            当前宠物信息: _root.宠物信息[slotIndex],
            当前宠物属性: _root.宠物信息[slotIndex][5],
            进阶方案: _root.战宠进阶函数
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

        // 获取方案描述
        if (typeof scheme.详情页描述 == "function") {
            var ctx:Object = {
                当前宠物信息: _root.宠物信息[0] != undefined ? _root.宠物信息[0] : [petId, 1, 200, 0, 0, {}],
                当前宠物属性: {},
                进阶方案: _root.战宠进阶函数
            };
            descText = String(scheme.详情页描述.call(ctx));
        } else if (scheme.描述 != undefined) {
            if (typeof scheme.描述 == "function") {
                descText = String(scheme.描述.call({当前宠物信息: [petId, 1, 200, 0, 0, {}], 当前宠物属性: {}, 进阶方案: _root.战宠进阶函数}));
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
                进阶方案: _root.战宠进阶函数
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

    // 判定方案是否因等级/前置未达而锁定（次数条件 = 需要的前置累进计数）。
    private static function isSchemeLocked(sc:Object, attrs:Object, petLevel:Number):Boolean {
        if (sc == undefined) return true;
        if (petLevel < (Number(sc.解锁等级) || 0)) return true;
        if (sc.次数条件 != undefined && Number(sc.次数条件) > 0) {
            var cnt:Number = (attrs != undefined && attrs.基础训练 != undefined) ? (Number(attrs.基础训练.次数) || 0) : 0;
            if (cnt < Number(sc.次数条件)) return true;
        }
        return false;
    }
}
