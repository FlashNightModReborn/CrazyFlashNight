/**
 * 文件：org/flashNight/arki/merc/ArenaPanelService.as
 * 说明：WebView 角斗场（DEATH MATCH）面板的 AS2 端桥。
 *
 * 同步管道（与 stage-select / map 同构）：
 *   Web → C# ArenaTask → Flash gameCommands:
 *     arenaSnapshot      — 返回 money / reuseCount / reuseLimit / busy
 *     arenaRollPreview   — 调 ArenaController.rollPreview，序列化 _root.出阵人员 给 web 显示
 *     arenaEquipTooltip  — (raw, level) → BaseItem.getData() 走真 calculateData，含 tier/mods
 *                          → TooltipComposer 富文本（descHTML / introHTML）
 *     arenaEnter         — 消费已 preview 好的 _root.出阵人员，commit 进场
 *
 * 关键不变量：
 *   - rollPreview 写 _root.出阵人员，但不碰 reuse 计数 / pool 刷新。无 cooldown，可以无限重抽
 *   - arenaEnter 只 commit，不重新抽签（保证 WYSIWYG：用户看到的就是会打到的）
 *
 * 注意：close 不走本桥。Web 关闭面板时 WebOverlayForm 直接走 PanelHost.ClosePanel()。
 */
import org.flashNight.arki.item.*;
import org.flashNight.arki.merc.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.gesh.tooltip.*;

class org.flashNight.arki.merc.ArenaPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["arenaSnapshot"] = function(params) {
            org.flashNight.arki.merc.ArenaPanelService.handleSnapshot(params);
        };
        _root.gameCommands["arenaRollPreview"] = function(params) {
            org.flashNight.arki.merc.ArenaPanelService.handleRollPreview(params);
        };
        _root.gameCommands["arenaEquipTooltip"] = function(params) {
            org.flashNight.arki.merc.ArenaPanelService.handleEquipTooltip(params);
        };
        _root.gameCommands["arenaEnter"] = function(params) {
            org.flashNight.arki.merc.ArenaPanelService.handleEnter(params);
        };

        _inited = true;
    }

    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        sendResponse({
            task: "arena_response",
            callId: callId,
            success: true,
            snapshot: {
                money:       Number(_root.金钱) || 0,
                reuseCount:  Number(_root.当前佣兵重用数) || 0,
                reuseLimit:  Number(_root.竞技场佣兵重用基数) || 0,
                busy:        (_root.发布请求 == true) || (_root.决斗场进入中 == true)
            }
        });
    }

    /**
     * 抽一批对手并序列化给 Web 显示。
     * 输出 opponents: [{ name, level, equips: [{slot, name, level}, ...] }, ...]
     * - slot 是原始数组下标 6..16（11 槽）
     * - 装备 level：若编码字符串自带 level (!=1) 用之，否则用 DressupInitializer 按佣兵 (level, name) 算出来的默认强化度
     */
    public static function handleRollPreview(params:Object):Void {
        var callId = params.callId;
        var expr:String = String(params.expr || "");

        if (expr == "") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_expr" });
            return;
        }
        if (!ArenaController.rollPreview(expr)) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stock_insufficient" });
            return;
        }

        var lineup:Array = _root.出阵人员;
        var opponents:Array = [];
        for (var i:Number = 0; i < lineup.length; i++) {
            opponents.push(buildOpponentSummary(lineup[i]));
        }

        sendResponse({
            task: "arena_response",
            callId: callId,
            success: true,
            expr: expr,
            opponents: opponents
        });
    }

    private static function buildOpponentSummary(merc:Array):Object {
        var mercLevel:Number = Number(merc[0]);
        var mercName:String = String(merc[1]);
        var defaultEquipLevel:Number = DressupInitializer.getEquipmentDefaultLevel(mercLevel, mercName);

        var equips:Array = [];
        for (var slot:Number = 6; slot <= 16; slot++) {
            var raw = merc[slot];
            if (raw == undefined || String(raw) == "" || String(raw) == "null") continue;
            var item = BaseItem.createFromString(raw);
            if (item == undefined || item == null) continue;

            var lvl:Number = (item.value != undefined && item.value.level > 1) ? Number(item.value.level) : defaultEquipLevel;
            // BaseItem.createFromString 拆 "name#value#tier#mods"，已把 ##四阶 解析进 item.value.tier。
            // 调 baseItem.getData() 才会触发 EquipmentUtil.calculateData 应用 tier / level / mods，
            // 返回真正的进阶版数据（含正确的 displayname / icon / 防御值等）。
            item.value.level = lvl; // 先把强化等级落进 value，让 calculateData 算对加成
            var calcData:Object = item.getData();
            var iconKey:String = (calcData && calcData.icon) ? String(calcData.icon) : String(item.name);
            var displayName:String = (calcData && calcData.displayname) ? String(calcData.displayname) : String(item.name);
            equips.push({
                slot:        slot,
                raw:         String(raw),          // 完整编码字符串（如 "黑色皮手套##四阶"）— tooltip 查询时回传
                name:        String(item.name),    // 拆出来的基础 name（不含 ##tier）— 仅诊断用
                icon:        iconKey,              // 进阶后的图标 manifest key
                displayname: displayName,          // 进阶后的用户可见名
                level:       lvl
            });
        }

        return { name: mercName, level: mercLevel, equips: equips };
    }

    /**
     * Web hover 装备格时调：给定 (raw, level) 重建 BaseItem，走真 baseItem.getData()
     * 让 TooltipComposer 输出带进阶的数据（而非 Web物品注释HTML 的 baseItem=null 简化路径）。
     */
    public static function handleEquipTooltip(params:Object):Void {
        var callId = params.callId;
        var raw:String = String(params.raw || params.name || "");
        var equipLevel:Number = Number(params.level);

        if (raw == "") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_raw" });
            return;
        }

        var item:BaseItem = BaseItem.createFromString(raw);
        if (item == undefined || item == null) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "item_not_found", itemName: raw });
            return;
        }

        if (!isNaN(equipLevel) && equipLevel > 0) item.value.level = equipLevel;

        // 关键：参考 _root.物品图标注释（权威路径）的实现 —— TooltipComposer 必须拿 raw itemData
        // 才能正确显示"基础值 + 强化增益"的拆分（例如 "空手加成: 68 (50 + 18)"）。
        // 如果预先调 item.getData() 把 itemData 算过，差值公式 base - calc 恒为 0 → 拆分丢失，
        // 还会出现 "伤害加成: 0 (60 - 60)" 这种 ghost row。getData() 仅用于需要 calculateData
        // 输出（如 displayname / icon）的字段。
        var itemData:Object = ItemUtil.getItemData(item.name);
        if (itemData == undefined) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "item_data_missing", itemName: raw });
            return;
        }

        var descHTML:String = TooltipComposer.generateItemDescriptionText(itemData, item);
        var introHTML:String = TooltipComposer.generateIntroPanelContent(item, itemData, item.value);

        sendResponse({
            task: "arena_response",
            callId: callId,
            success: true,
            itemName: String(item.name),
            displayname: String(itemData.displayname || item.name),
            // LiteJSON 不转义双引号；XML 内嵌 <font color="..."> 会破坏 JSON → 与 Web物品注释HTML 同步把 " 换 '
            descHTML: descHTML.split('"').join("'"),
            introHTML: introHTML.split('"').join("'")
        });
    }

    public static function handleEnter(params:Object):Void {
        var callId = params.callId;

        var expr:String = String(params.expr || "");
        var deposit:Number = Number(params.deposit);
        var reward:Number = Number(params.reward);

        if (expr == "") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_expr" });
            return;
        }
        if (isNaN(deposit) || isNaN(reward) || deposit < 0 || reward < 0) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_amounts" });
            return;
        }
        if (_root.金钱 < deposit) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "insufficient_money" });
            return;
        }
        if (_root.发布请求 == true) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "busy" });
            return;
        }
        if (typeof _root.载入关卡数据 != "function") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_loader_unavailable" });
            return;
        }
        if (_root.淡出动画 == undefined || _root.淡出动画.淡出跳转帧 == undefined) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_transition_unavailable" });
            return;
        }

        // WYSIWYG: 必须先 preview 过；如果 web 端漏调（异常路径），兜底再抽一次保证不空 commit
        if (_root.出阵人员 == undefined || _root.出阵人员.length == 0) {
            if (!ArenaController.rollPreview(expr)) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "stock_insufficient" });
                return;
            }
        }

        // 原始路径："DEATH MATCH角斗场" 的 StageInfo.FadeTransitionFrame = "角斗场选择挑战者",
        // 玩家先到那个帧、由该帧 stage-select 入口预先调过 _root.载入关卡数据 把
        // StageManager 初始化, 后续 enterArenaCommon → wuxianguotu_1 才能加载场景背景.
        // Web 面板直接跳关, 必须在此手动复现 stage 数据预载.
        var stageInfo:Object = _root.StageInfoDict ? _root.StageInfoDict["DEATH MATCH角斗场"] : undefined;
        if (stageInfo == undefined || stageInfo.url == undefined || String(stageInfo.url) == "") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_info_missing" });
            return;
        }

        _root.载入关卡数据(String(stageInfo.Type || "无限过图"), String(stageInfo.url));
        _root.关卡类型 = String(stageInfo.Type || "无限过图");
        _root.关卡路径 = String(stageInfo.url);

        _root.押金 = deposit;
        _root.角斗场奖金 = reward;

        sendResponse({
            task: "arena_response",
            callId: callId,
            success: true,
            closePanel: true,
            deposit: deposit,
            reward: reward,
            expr: expr
        });

        if (_root.soundEffectManager != undefined && _root.soundEffectManager.stopBGMForTransition != undefined) {
            _root.soundEffectManager.stopBGMForTransition();
        }
        // commit 已 preview 好的 _root.出阵人员（含 reuse 计数 / pool 刷新 / 扣押金 / 跳关）
        ArenaController.commitArena();
    }

    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
