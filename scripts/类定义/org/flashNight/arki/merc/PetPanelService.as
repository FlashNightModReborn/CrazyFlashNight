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
                xp: Number(info[3]),
                deployed: Number(info[4]) == 1,
                height: Number(petDef.Height),
                promotions: []
            };

            // 序列化进阶属性
            var attrs:Object = info[5];
            if (attrs != undefined && typeof attrs == "object") {
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

            // 计算经验值需求
            petEntry.xpNeeded = calcXpForLevel(info[1] + 1);
            petEntry.maxStamina = 20;

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
                    promotions: def.Promotion != undefined ? def.Promotion.slice() : []
                });
            }
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            snapshot: {
                pets: pets,
                petLib: petLib,
                gold: Number(_root.金钱) || 0,
                kpoint: Number(_root.K点) || 0,
                playerLevel: Number(_root.等级) || 1,
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
                for (var j:Number = 0; j < cat.ids.length; j++) {
                    var petId:Number = cat.ids[j];
                    var petDef:Object = _root.宠物库[petId];
                    if (petDef == undefined) continue;

                    // 检查是否已拥有（Unique宠物）
                    var owned:Boolean = false;
                    if (petDef.Unique == true) {
                        for (var k:Number = 0; k < _root.宠物信息.length; k++) {
                            if (_root.宠物信息[k][0] == petId) {
                                owned = true;
                                break;
                            }
                        }
                    }
                    if (owned) continue;

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

        // 检查宠物栏是否已满
        if (_root.宠物信息.length >= _root.宠物领养限制) {
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
        if (kprice > 0 && _root.K点 < kprice) {
            sendResponse({ task: "pet_response", callId: callId, success: false, error: "insufficient_kpoint" });
            return;
        }

        // 执行购买
        if (price > 0) _root.金钱 -= price;
        if (kprice > 0) _root.K点 -= kprice;

        // 创建宠物信息条目
        var initialLevel:Number = Number(petDef.InitialLevel) || 1;
        var newPet:Array = [petId, initialLevel, 20, 0, 0, {}];

        // 处理 IncreasePrice（每次购买后涨价）
        if (Number(petDef.IncreasePrice) > 0) {
            petDef.Price += Number(petDef.IncreasePrice);
        }

        _root.宠物信息.push(newPet);

        // 刷新宠物UI
        if (_root.宠物信息界面 != undefined && _root.宠物信息界面.排列宠物图标 != undefined) {
            _root.宠物信息界面.排列宠物图标();
        }

        sendResponse({
            task: "pet_response",
            callId: callId,
            success: true,
            petId: petId,
            slotIndex: _root.宠物信息.length - 1,
            gold: Number(_root.金钱) || 0,
            kpoint: Number(_root.K点) || 0
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

        var success:Boolean = true;
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
                _root.战宠UI函数.设置宠物出战(slotIndex, true, heroX, heroY);
            }
        } else {
            // 休息：移除宠物单位
            _root.战宠UI函数.设置宠物出战(slotIndex, false);
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

        // 检查条件
        var condFn:Function = scheme.条件;
        if (typeof condFn == "function") {
            // 临时绑定上下文执行条件检查
            var oldFail:String = scheme.失败提示;
            scheme.当前宠物信息 = ctx.当前宠物信息;
            scheme.当前宠物属性 = ctx.当前宠物属性;
            var condResult:Boolean = condFn.call(ctx);
            if (!condResult) {
                var failMsg:String = scheme.失败提示 || "条件不满足";
                sendResponse({ task: "pet_response", callId: callId, success: false, error: "condition_failed", reason: failMsg });
                return;
            }
        }

        // 执行进阶
        var execFn:Function = scheme.执行;
        if (typeof execFn == "function") {
            execFn.call(ctx);
        }

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
            kpoint: Number(_root.K点) || 0
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
                当前宠物信息: _root.宠物信息[0] != undefined ? _root.宠物信息[0] : [petId, 1, 20, 0, 0, {}],
                当前宠物属性: {},
                进阶方案: _root.战宠进阶函数
            };
            descText = String(scheme.详情页描述.call(ctx));
        } else if (scheme.描述 != undefined) {
            if (typeof scheme.描述 == "function") {
                descText = String(scheme.描述.call({当前宠物信息: [petId, 1, 20, 0, 0, {}], 当前宠物属性: {}, 进阶方案: _root.战宠进阶函数}));
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
                当前宠物信息: [petId, 1, 20, 0, 0, {}],
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
    private static function calcXpForLevel(level:Number):Number {
        if (_root.战宠UI函数 != undefined && _root.战宠UI函数.计算战宠升级所需经验 != undefined) {
            // 引擎函数需要 兵种 参数，这里用通用估算
        }
        return Math.floor((50 + ((400 - 50) / 59) * level) * level);
    }
}
