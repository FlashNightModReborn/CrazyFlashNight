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
 *     mercRevive        — 消耗复活币复活阵亡佣兵（出战信息 -1 → 0）
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
        _root.gameCommands["mercRevive"] = function(params) {
            org.flashNight.arki.merc.MercPanelService.handleRevive(params);
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
            // 出战信息三态：1=出战 0=休息 -1=阵亡（死亡检测写 -1，见 玩家模板迁移 处理佣兵死亡）
            summary.deployed = (_root.佣兵是否出战信息[i] == 1);
            summary.dead = (_root.佣兵是否出战信息[i] == -1);
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
                reviveCoins: Number(ItemUtil.getTotal("复活币")) || 0,
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

        // 收集非隐藏佣兵；顺手实扫最高等级——不取"末位即最大"的捷径，
        // 升序不变量可能被池的其他写方（XML 直写 / 历史版本解雇 push 池尾）破坏，
        // 取末位会把 Lv.20+/40+/60+/80+ 定位钮错误禁用。
        var visible:Array = [];
        var poolMaxLevel:Number = 0;
        for (var i:Number = 0; i < pool.length; i++) {
            var m:Array = pool[i];
            if (m == undefined || m[0] == undefined) continue;
            if (m[19] && m[19].隐藏) continue;
            visible.push(i); // 存的是 pool 中的 index
            if (Number(m[0]) > poolMaxLevel) poolMaxLevel = Number(m[0]);
        }

        var totalPages:Number = Math.max(1, Math.ceil(visible.length / perPage));

        // 等级快速定位：可雇佣兵池在 MercLibrary.loadFromList 已按等级升序排序
        // （InsertionSort.sortOn 列 0），minLevel 仅需定位首个达标项所在页。
        // 命中后覆盖请求页码；无人达标 → 落到最后一页。页内精确定位由 Web 端
        // scrollIntoView 完成。
        var minLevel:Number = Number(params.minLevel);
        if (!isNaN(minLevel) && minLevel > 0) {
            var jumpIdx:Number = visible.length;
            for (var v:Number = 0; v < visible.length; v++) {
                if (Number(pool[visible[v]][0]) >= minLevel) { jumpIdx = v; break; }
            }
            page = Math.floor(jumpIdx / perPage) + 1;
        }

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
                totalCount: visible.length,
                // 可见池最高等级（构建 visible 时实扫），供 Web 端禁用超出范围的等级定位钮
                maxLevel: poolMaxLevel
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
        // 阵亡（-1）的佣兵不能出战/休息切换，必须先消耗复活币复活（mercRevive）
        if (currentState == -1) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "merc_dead" });
            return;
        }
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

        // Plan A audit 同口径：解雇写 同伴数据 / 同伴数 / 可雇佣兵 / 佣兵是否出战信息（全 save-relevant），必须标脏
        _root.存档系统.dirtyMark = true;

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

        // 身份校验：池索引是易失的（hire splice / 解雇回池重排都会位移），Web 端列表
        // 刷新前的快速连点会带着 stale poolIndex 进来——只查存在性会按错位索引扣钱
        // 雇到别人。带 mercId 时必须匹配，不匹配让 Web 重拉列表。（不带时兼容放行）
        if (params.mercId != undefined && String(params.mercId) != "" && String(merc[2]) != String(params.mercId)) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "pool_changed" });
            return;
        }

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

        // 成就记账（埋点 #12，雇佣成功分支=扣款后）
        if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
            org.flashNight.arki.achievement.AchievementMetrics.record("佣兵雇佣次数", 1);
            org.flashNight.arki.achievement.AchievementMetrics.record("佣兵雇佣花费金币", goldPrice);
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
    // handleRevive — 消耗 1 枚复活币复活阵亡佣兵
    // 复活后回到休息位（0）而非直接出战：玩家自行决定何时再派出，
    // 也避免在战斗图里把人直接拉进场。
    // ═══════════════════════════════════════════════════════════
    public static function handleRevive(params:Object):Void {
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

        if (Number(_root.佣兵是否出战信息[mercIndex]) != -1) {
            sendResponse({ task: "merc_response", callId: callId, success: false, error: "not_dead" });
            return;
        }

        // 扣 1 枚复活币（材料栏权威扣减；不足时 singleSubmit 返回 false）
        if (!ItemUtil.singleSubmit("复活币", 1)) {
            sendResponse({
                task: "merc_response",
                callId: callId,
                success: false,
                error: "no_revive_coin",
                reviveCoins: Number(ItemUtil.getTotal("复活币")) || 0
            });
            return;
        }

        _root.佣兵是否出战信息[mercIndex] = 0;
        // 写 佣兵是否出战信息 + 扣材料均 save-relevant，必须标脏
        _root.存档系统.dirtyMark = true;

        sendResponse({
            task: "merc_response",
            callId: callId,
            success: true,
            mercIndex: mercIndex,
            mercName: String(merc[1]),
            reviveCoins: Number(ItemUtil.getTotal("复活币")) || 0
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

        // 性别列实际是字符串："男"/"女"（MercLibrary.loadFromList 原样存入
        // mercenaries.json 的 gender 字段；旧存档另有 "主角-男"/"主角-女" 遗留形态）。
        // 旧实现按 1/"1" 判男 → 全员误判为女。数字形态仅作兜底保留。
        var g:String = String(merc[17]);
        var gender:String = (g == "男" || g == "主角-男" || g == "1" || merc[17] == 1) ? "男" : "女";

        var personality:Object = buildPersonality(mercName, mercLevel);

        return {
            slotIndex:   slotIndex,
            name:        mercName,
            id:          mercId,
            level:       mercLevel,
            gender:      gender,
            height:      Number(merc[3]) || 0,
            face:        String(merc[4] || ""),
            faceId:      (merc[19] && merc[19].脸型ID != undefined) ? String(merc[19].脸型ID) : "",
            hair:        String(merc[5] || ""),
            hairId:      (merc[19] && merc[19].发型ID != undefined) ? String(merc[19].发型ID) : "",
            equips:      equips,
            personality: serializePersonality(personality),
            skills:      buildSkills(mercName, mercLevel, merc, personality)
        };
    }

    // ═══════════════════════════════════════════════════════════
    // buildPersonality — 重算佣兵人格六维（仅展示用）
    // 与 单位函数_fs_aka_玩家模板迁移.as 配置人形怪AI 的 aiSeed 算法严格同构：
    // seed = 等级 起步 → 名字逐字符 seed*31+charCode → &0x7FFFFFFF，
    // 再走 _root.生成随机人格（确定性 LCG）。不调 计算AI参数（派生参数面板用不到）。
    // ═══════════════════════════════════════════════════════════
    // public：角斗场面板 (ArenaPanelService) 复用同一份人格重算，避免「两套种子」漂移
    public static function buildPersonality(mercName:String, mercLevel:Number):Object {
        var seed:Number = mercLevel;
        for (var i:Number = 0; i < mercName.length; i++) {
            seed = seed * 31 + mercName.charCodeAt(i);
        }
        seed = seed & 0x7FFFFFFF;
        return _root.生成随机人格(seed);
    }

    // 序列化人格为有序数组（固定维度顺序，JSON 键保持 ASCII）
    private static function serializePersonality(p:Object):Array {
        var dims:Array = ["勇气", "技术", "经验", "反应", "智力", "谋略"];
        var traits:Array = [];
        for (var i:Number = 0; i < dims.length; i++) {
            var v:Number = Number(p[dims[i]]);
            if (isNaN(v)) v = 0;
            traits.push({ name: dims[i], value: Math.round(v * 100) / 100 });
        }
        return traits;
    }

    // ═══════════════════════════════════════════════════════════
    // buildSkills — 重算佣兵已学技能（仅展示用）
    // 算法与 单位函数_fs_aka_玩家模板迁移.as 主角函数.初始化可用技能 严格同构
    // （等级桶 + 装备组合预过滤 → LCG 抽技能 → 剩余点数随机强化）。
    // 命中 _root.技能缓存（实体已初始化过）时直接采用游戏内结果；
    // 未命中时本地重算且【不回写缓存】——若两边实现意外漂移，
    // 不能让面板的展示值污染战斗权威数据。
    // ═══════════════════════════════════════════════════════════
    // public：角斗场面板 (ArenaPanelService) 复用同一份技能重算（含 _root.技能缓存 命中优先）
    public static function buildSkills(mercName:String, mercLevel:Number, merc:Array, personality:Object):Array {
        var 技术档位:Number = (personality && personality.技术) ? Math.round(personality.技术 * 4) : 0;
        var 缓存键:String = mercName + "_" + mercLevel + "_t" + 技术档位;
        var learned:Array = _root.技能缓存[缓存键];
        if (learned == undefined) {
            learned = computeSkillList(mercName, mercLevel, merc, personality);
        }

        var out:Array = [];
        for (var i:Number = 0; i < learned.length; i++) {
            var sk:Object = learned[i];
            out.push({
                name:     String(sk.技能名),
                level:    Number(sk.技能等级) || 1,
                type:     String(sk.类型),
                trait:    String(sk.功能),
                cooldown: Number(sk.冷却) || 0,
                cost:     Number(sk.消耗) || 0,
                unlock:   Number(sk.限制) || 0
            });
        }
        return out;
    }

    private static function computeSkillList(mercName:String, mercLevel:Number, merc:Array, personality:Object):Array {
        var 主角函数:Object = _root.主角函数;
        var 技能表:Array = 主角函数.人形怪技能表;
        if (技能表 == undefined) return [];

        var 可学技能数:Number = 3 + ((mercLevel / 5) >> 0);

        // 装备组合: 0=无刀无枪, 1=有刀无枪, 2=无刀有枪, 3=有刀有枪
        // （注意：取自 mercData 原始装备列；若实体初始化时被默认装备链改写过，
        //   组合可能与战斗实测有出入，仅作展示预估。）
        var 有刀:Number = merc[15] ? 1 : 0;
        var 有枪:Number = (merc[12] || merc[13] || merc[14]) ? 2 : 0;
        var 装备组合:Number = 有刀 + 有枪;

        // 种子（同 初始化可用技能：等级 + 名字字符码累加）
        var 种子:Number = mercLevel;
        for (var ci:Number = 0; ci < mercName.length; ci++) {
            种子 += mercName.charCodeAt(ci);
        }

        var LCG_A:Number = 1664525;
        var LCG_C:Number = 1013904223;
        var LCG_M:Number = 4294967296;

        var 技能点总数:Number = _root.计算技能点数总和(mercLevel);
        if (personality && personality.技术) {
            技能点总数 = Math.round(技能点总数 * (1 + personality.技术));
        }

        var 桶最大等级:Number = 主角函数.技能等级桶最大等级;
        var 查询等级:Number = mercLevel > 桶最大等级 ? 桶最大等级 : mercLevel;
        var 预过滤索引:Array = 主角函数.装备技能桶[查询等级][装备组合];
        if (预过滤索引 == undefined) return [];

        var 可用技能表:Array = 预过滤索引.slice(0);
        var 可用技能强化表:Array = [];
        var 已学技能表:Array = [];
        var 可用长度:Number;
        var 随机索引:Number;
        var 最后索引:Number;
        var 原始技能:Object;
        var 点数:Number;

        while (可学技能数 > 0 && (可用长度 = 可用技能表.length) > 0) {
            种子 = (LCG_A * 种子 + LCG_C) % LCG_M;
            随机索引 = (种子 / LCG_M * 可用长度) >> 0;

            var 待检测技能索引:Number = 可用技能表[随机索引];
            最后索引 = 可用长度 - 1;
            if (随机索引 != 最后索引) {
                可用技能表[随机索引] = 可用技能表[最后索引];
            }
            可用技能表.pop();

            原始技能 = 技能表[待检测技能索引];
            点数 = 原始技能.点数;

            if (技能点总数 >= 点数) {
                可用技能强化表.push({
                    技能名: 原始技能.技能名,
                    点数: 点数,
                    冷却: 原始技能.冷却,
                    消耗: 原始技能.消耗,
                    限制: 原始技能.限制,
                    类型: 原始技能.类型,
                    功能: 原始技能.功能,
                    技能等级: 1
                });
                可学技能数--;
                技能点总数 -= 点数;
            }
        }

        var 待强化技能:Object;
        var 强化点数:Number;

        while (技能点总数 > 0 && (可用长度 = 可用技能强化表.length) > 0) {
            种子 = (LCG_A * 种子 + LCG_C) % LCG_M;
            随机索引 = (种子 / LCG_M * 可用长度) >> 0;

            待强化技能 = 可用技能强化表[随机索引];
            强化点数 = 待强化技能.点数;

            if (技能点总数 >= 强化点数 && 待强化技能.技能等级 < 10) {
                待强化技能.技能等级 += 1;
                技能点总数 -= 强化点数;
            } else {
                最后索引 = 可用长度 - 1;
                if (随机索引 != 最后索引) {
                    可用技能强化表[随机索引] = 可用技能强化表[最后索引];
                }
                已学技能表.push(待强化技能);
                可用技能强化表.pop();
            }
        }

        var 强化表长度:Number = 可用技能强化表.length;
        for (var ri:Number = 0; ri < 强化表长度; ri++) {
            已学技能表.push(可用技能强化表[ri]);
        }

        return 已学技能表;
    }

    // ═══════════════════════════════════════════════════════════
    // sendResponse — 发送 JSON 回包到 C#
    // ═══════════════════════════════════════════════════════════
    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
