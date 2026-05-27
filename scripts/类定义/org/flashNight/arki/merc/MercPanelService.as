/**
 * 文件：org/flashNight/arki/merc/MercPanelService.as
 * 说明：WebView 佣兵管理面板的 AS2 端桥。
 *
 * 管道：
 *   Web → C# MercTask → Flash gameCommands:
 *     mercSnapshot      — 返回已雇佣佣兵列表 + 装备信息 + gold/kpoint
 *     mercHireList      — 返回分页可雇佣列表（5条/页）+ 预计算价格
 *     mercDeploy        — 切换佣兵出战/休息状态
 *     mercDismiss       — 解雇佣兵（回写池 + 清理场景MC）
 *     mercHire          — 雇佣佣兵（扣钱 + 从池移入同伴数据）
 *     mercEquipTooltip  — 装备 tooltip 富文本（委托 ArenaPanelService）
 *     mercPanelOpen     — 面板打开（刷新 Flash 佣兵UI）
 *     mercPanelClose    — 面板关闭（重排佣兵图标）
 *
 * 注意：close 不走本桥。Web 关闭面板时 WebOverlayForm 直接走 PanelHost.ClosePanel()。
 */
import org.flashNight.arki.item.*;
import org.flashNight.arki.merc.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.gesh.tooltip.*;

class org.flashNight.arki.merc.MercPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["mercSnapshot"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handleSnapshot(params);
        };
        _root.gameCommands["mercHireList"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handleHireList(params);
        };
        _root.gameCommands["mercDeploy"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handleDeploy(params);
        };
        _root.gameCommands["mercDismiss"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handleDismiss(params);
        };
        _root.gameCommands["mercHire"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handleHire(params);
        };
        _root.gameCommands["mercEquipTooltip"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handleEquipTooltip(params);
        };
        _root.gameCommands["mercPanelOpen"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handlePanelOpen(params);
        };
        _root.gameCommands["mercPanelClose"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handlePanelClose(params);
        };

        _inited = true;
    }

    // ═══════════════════════════════════════════════════════════
    // handleSnapshot — 返回已雇佣佣兵全景快照
    // ═══════════════════════════════════════════════════════════
    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;

        var hiredMercs:Array = [];
        var maxSlots:Number = Number(_root.佣兵个数限制) || 0;
        for (var i:Number = 0; i < maxSlots; i++) {
            var merc:Array = _root.同伴数据[i];
            if (merc == undefined || merc[0] == undefined) continue;
            var summary:Object = buildMercSummary(merc, i);
            summary.deployed = (_root.佣兵是否出战信息[i] == 1);
            hiredMercs.push(summary);
        }

        sendResponse({
            task: "merc_response",
            callId: callId,
            success: true,
            snapshot: {
                hiredMercs: hiredMercs,
                gold:   Number(_root.金钱) || 0,
                kpoint: Number(_root.虚拟币) || 0,
                maxSlots: maxSlots,
                isCombatMap: (_root.关卡类型 != undefined && _root.关卡类型 != "")
            }
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleHireList — 分页返回可雇佣列表（10条/页）
    // ═══════════════════════════════════════════════════════════
    public static function handleHireList(params:Object):Void {
        var callId = params.callId;
        var page:Number = Number(params.page) || 1;
        var perPage:Number = 10;

        var pool:Array = _root.可雇佣兵;
        if (pool == undefined) pool = [];
        var hidden:Array = _root.隐藏的可雇佣兵;
        if (hidden == undefined) hidden = [];

        // 收集非隐藏佣兵
        var visible:Array = [];
        for (var i:Number = 0; i < pool.length; i++) {
            var m:Array = pool[i];
            if (m == undefined || m[0] == undefined) continue;
            if (m[19] && m[19].隐藏) continue;
            visible.push(i); // 存的是 pool 中的 index
        }

        var totalPages:Number = Math.max(1, Math.ceil(visible.length / perPage));
        if (page < 1) page = 1;
        if (page > totalPages) page = totalPages;

        var start:Number = (page - 1) * perPage;
        var end:Number = Math.min(start + perPage, visible.length);

        var isEasy:Boolean = _root.isEasyMode != undefined ? _root.isEasyMode() : false;

        var hireable:Array = [];
        for (var j:Number = start; j < end; j++) {
            var poolIdx:Number = visible[j];
            var rawMerc:Array = pool[poolIdx];
            var mercLevel:Number = Number(rawMerc[0]);

            // 价格计算（与 Flash UI 完全一致）
            var baseGold:Number = Number(rawMerc[18]) * 1.5;
            var kPrice:Number = 0;
            if (!isEasy && mercLevel >= 50) {
                kPrice = (mercLevel - 50) * 100;
            }
            if (rawMerc[19] && rawMerc[19].价格倍率) {
                var mult:Number = Number(rawMerc[19].价格倍率);
                baseGold = Math.floor(baseGold * mult / 500) * 500;
                kPrice = Math.floor(kPrice * mult / 100) * 100;
            }
            var goldPrice:Number = Math.floor(baseGold);

            var summary:Object = buildMercSummary(rawMerc, -1);
            summary.poolIndex = poolIdx;
            summary.goldPrice = goldPrice;
            summary.kPrice = kPrice;

            hireable.push(summary);
        }

        sendResponse({
            task: "merc_response",
            callId: callId,
            success: true,
            hireList: {
                hireable: hireable,
                page: page,
                totalPages: totalPages,
                totalCount: visible.length
            }
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleDeploy — 切换出战/休息
    // ═══════════════════════════════════════════════════════════
    public static function handleDeploy(params:Object):Void {
        var callId = params.callId;
        var mercIndex:Number = Number(params.mercIndex);

        if (isNaN(mercIndex) || mercIndex < 0) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "invalid_index" });
            return;
        }

        var merc:Array = _root.同伴数据[mercIndex];
        if (merc == undefined || merc[0] == undefined) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "merc_not_found" });
            return;
        }

        if (_root.佣兵是否出战信息 == undefined) _root.佣兵是否出战信息 = [];
        var currentState:Number = Number(_root.佣兵是否出战信息[mercIndex]) || 0;
        var newState:Number = (currentState == 1) ? 0 : 1;
        _root.佣兵是否出战信息[mercIndex] = newState;
        // Plan A audit: handleDeploy 写 佣兵是否出战信息（save-relevant），必须标脏
        _root.存档系统.dirtyMark = true;

        sendResponse({
            task: "merc_response",
            callId: callId,
            success: true,
            deployed: (newState == 1),
            mercIndex: mercIndex,
            mercName: String(merc[1]),
            mercId: String(merc[2])
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleDismiss — 解雇佣兵
    // ═══════════════════════════════════════════════════════════
    public static function handleDismiss(params:Object):Void {
        var callId = params.callId;
        var mercIndex:Number = Number(params.mercIndex);

        if (isNaN(mercIndex) || mercIndex < 0) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "invalid_index" });
            return;
        }

        var merc:Array = _root.同伴数据[mercIndex];
        if (merc == undefined || merc[0] == undefined) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "merc_not_found" });
            return;
        }

        var mercId:String = String(merc[2]);
        var mercName:String = String(merc[1]);

        MercSpawner.removeMerc(mercId);

        sendResponse({
            task: "merc_response",
            callId: callId,
            success: true,
            mercIndex: mercIndex,
            mercName: mercName,
            mercId: mercId
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleHire — 雇佣佣兵
    // ═══════════════════════════════════════════════════════════
    public static function handleHire(params:Object):Void {
        var callId = params.callId;
        var poolIndex:Number = Number(params.poolIndex);

        if (isNaN(poolIndex) || poolIndex < 0) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "invalid_index" });
            return;
        }

        var pool:Array = _root.可雇佣兵;
        if (pool == undefined || pool[poolIndex] == undefined) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "merc_not_found" });
            return;
        }

        var merc:Array = pool[poolIndex];

        // 检查佣兵槽位上限
        var maxSlots:Number = Number(_root.佣兵个数限制) || 0;
        var currentCount:Number = Number(_root.同伴数) || 0;
        if (maxSlots > 0 && currentCount >= maxSlots) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "slots_full", currentCount: currentCount, maxSlots: maxSlots });
            return;
        }

        var mercLevel:Number = Number(merc[0]);

        // 计算价格（与 Flash UI 完全一致）
        var isEasy:Boolean = _root.isEasyMode != undefined ? _root.isEasyMode() : false;
        var goldPrice:Number = Math.floor(Number(merc[18]) * 1.5);
        var kPrice:Number = 0;
        if (!isEasy && mercLevel >= 50) {
            kPrice = (mercLevel - 50) * 100;
        }
        if (merc[19] && merc[19].价格倍率) {
            var mult:Number = Number(merc[19].价格倍率);
            goldPrice = Math.floor(goldPrice * mult / 500) * 500;
            kPrice = Math.floor(kPrice * mult / 100) * 100;
        }

        // 检查金币
        var currentGold:Number = Number(_root.金钱) || 0;
        if (currentGold < goldPrice) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "insufficient_gold", goldPrice: goldPrice, currentGold: currentGold });
            return;
        }

        // 检查K点
        var currentKPoint:Number = Number(_root.虚拟币) || 0;
        if (kPrice > 0 && currentKPoint < kPrice) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "insufficient_kpoint", kPrice: kPrice, currentKPoint: currentKPoint });
            return;
        }

        // 扣款
        _root.金钱 -= goldPrice;
        if (kPrice > 0) {
            _root.虚拟币 -= kPrice;
        }

        // 从可雇佣兵池移除
        pool.splice(poolIndex, 1);

        // 追加到同伴数据
        if (_root.同伴数据 == undefined) _root.同伴数据 = [];
        _root.同伴数据.push(merc);
        _root.同伴数 = (_root.同伴数 == undefined) ? 1 : _root.同伴数 + 1;

        // 初始化出战信息（默认不出战）
        if (_root.佣兵是否出战信息 == undefined) _root.佣兵是否出战信息 = [];
        _root.佣兵是否出战信息[_root.同伴数据.length - 1] = 0;
        // Plan A audit: handleRecruit 写 金钱/虚拟币/同伴数据/同伴数/佣兵是否出战信息，全部 save-relevant，必须标脏
        _root.存档系统.dirtyMark = true;

        var mercName:String = String(merc[1]);

        // WebView 面板管理 UI 刷新（JS 端 hire 回包后 requestSnapshot 已重新拉取列表），
        // 不调用 Flash 排列佣兵图标()：避免 gotoAndStop + attachMovie 帧脚本干扰
        // PanelHost 的 close 恢复序列，导致关闭面板后鼠标阻塞。

        sendResponse({
            task: "merc_response",
            callId: callId,
            success: true,
            mercName: mercName,
            goldRemaining: Number(_root.金钱),
            kpointRemaining: Number(_root.虚拟币),
            goldPrice: goldPrice,
            kPrice: kPrice
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handleEquipTooltip — 装备富文本 tooltip
    // 注意：不能委托 ArenaPanelService，因为后者发 arena_response 而非 merc_response
    // ═══════════════════════════════════════════════════════════
    public static function handleEquipTooltip(params:Object):Void {
        var callId = params.callId;
        var raw:String = String(params.raw || params.name || "");
        var equipLevel:Number = Number(params.level);

        if (raw == "") {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "invalid_raw" });
            return;
        }

        var item:BaseItem = BaseItem.createFromString(raw);
        if (item == undefined || item == null) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "item_not_found", itemName: raw });
            return;
        }

        if (!isNaN(equipLevel) && equipLevel > 0) item.value.level = equipLevel;

        var itemData:Object = ItemUtil.getItemData(item.name);
        if (itemData == undefined) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "item_data_missing", itemName: raw });
            return;
        }

        var descHTML:String = TooltipComposer.generateItemDescriptionText(itemData, item);
        var introHTML:String = TooltipComposer.generateIntroPanelContent(item, itemData, item.value);

        sendResponse({
            task: "merc_response",
            callId: callId,
            success: true,
            itemName: String(item.name),
            displayname: String(itemData.displayname || item.name),
            descHTML: descHTML.split('"').join("&quot;"),
            introHTML: introHTML.split('"').join("&quot;")
        });
    }

    // ═══════════════════════════════════════════════════════════
    // handlePanelOpen / handlePanelClose
    // ═══════════════════════════════════════════════════════════
    public static function handlePanelOpen(params:Object):Void {
        // 隐藏 Flash 旧 UI，WebView 面板覆盖在上面
        if (_root.佣兵信息界面 != undefined) {
            _root.佣兵信息界面._visible = false;
        }
    }

    public static function handlePanelClose(params:Object):Void {
        // WebView 面板关闭后，不刷新 Flash UI（避免 gotoAndStop + attachMovie
        // 帧脚本触发副作用阻塞 Flash 线程）。如有需要，玩家下次打开面板时 snapshot 会同步最新状态。
    }

    // ═══════════════════════════════════════════════════════════
    // buildMercSummary — 序列化单个佣兵（含装备信息）
    // 与 ArenaPanelService.buildOpponentSummary 同构
    // ═══════════════════════════════════════════════════════════
    private static function buildMercSummary(merc:Array, slotIndex:Number):Object {
        var mercLevel:Number = Number(merc[0]);
        var mercName:String = String(merc[1]);
        var mercId:String = String(merc[2]);
        var defaultEquipLevel:Number = DressupInitializer.getEquipmentDefaultLevel(mercLevel, mercName);

        var equips:Array = [];
        for (var slot:Number = 6; slot <= 16; slot++) {
            var raw = merc[slot];
            if (raw == undefined || String(raw) == "" || String(raw) == "null") continue;
            var item = BaseItem.createFromString(raw);
            if (item == undefined || item == null) continue;

            var lvl:Number = (item.value != undefined && item.value.level > 1) ? Number(item.value.level) : defaultEquipLevel;
            item.value.level = lvl;
            var calcData:Object = item.getData();
            var iconKey:String = (calcData && calcData.icon) ? String(calcData.icon) : String(item.name);
            var displayName:String = (calcData && calcData.displayname) ? String(calcData.displayname) : String(item.name);
            equips.push({
                slot:        slot,
                raw:         String(raw),
                name:        String(item.name),
                icon:        iconKey,
                displayname: displayName,
                level:       lvl
            });
        }

        var gender:String = (merc[17] == 1 || merc[17] == "1") ? "男" : "女";

        return {
            slotIndex:   slotIndex,
            name:        mercName,
            id:          mercId,
            level:       mercLevel,
            gender:      gender,
            height:      Number(merc[3]) || 0,
            equips:      equips
        };
    }

    // ═══════════════════════════════════════════════════════════
    // sendResponse — 发送 JSON 回包到 C#
    // ═══════════════════════════════════════════════════════════
    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
