/**
 * 文件：org/flashNight/arki/merc/ArenaPanelService.as
 * 说明：WebView 角斗场（DEATH MATCH）面板的 AS2 端桥。
 *
 * Panel 打开入口（两条）：
 *   1. LauncherCommandRouter "ARENA_TEST" 按钮直接 OpenPanel("arena", ...) — 仅 dev 模式
 *   2. 玩家在 stage-select panel 上选 "DEATH MATCH角斗场" 难度 → StageSelectPanelService
 *      识别后发 panel_request{panel:"arena"} → LauncherCommandRouter.RequestOpenPanel("arena")
 *      → PanelHostController 内部自动 DoClose(stage-select) + DoOpen(arena)，替换式过渡
 *
 * 同步管道（与 stage-select / map 同构）：
 *   Web → C# ArenaTask → Flash gameCommands:
 *     arenaSnapshot      — 返回 money / reuseCount / reuseLimit / busy / knownEnemies
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
        // panel 重新打开 = 上次入场链已经走完（玩家从战场回主城，或从未真正入场）。
        // 这里把自管入场锁 reset 掉，覆盖 ArenaController.close 在 web 路径下不会被
        // 调用的事实（close 仅挂在旧 Flash 角斗场选择界面的"取消挑战"按钮上）。
        _root.角斗场入场中 = false;
        // 对手类型默认人形；roster（元战队/非人形）由后续 enter 显式置位，
        // 这里复位防上一场 roster 残留泄漏进 enterArenaCommon / 角斗场加载 的分叉判断。
        _root.角斗场对手类型 = "merc";
        _root.角斗场roster阵容 = undefined;
        _root.角斗场爬升 = undefined; // 爬升模式状态复位，防上一场残留泄漏进 角斗场加载 分叉
        // batch preview lineup cache 镜像 web 端 _previewCache：snapshot 是 panel open 必经握手，
        // 这里清空让本 session 8 路 preview 重抽签。跨 session 复用旧 lineup 不安全
        // （_root.可雇佣兵 pool 在战斗 / 雇佣等流程后可能已变）。
        _root._arenaLineupCache = [];
        sendResponse({
            task: "arena_response",
            callId: callId,
            success: true,
            snapshot: {
                money:       Number(_root.金钱) || 0,
                reuseCount:  Number(_root.当前佣兵重用数) || 0,
                reuseLimit:  Number(_root.竞技场佣兵重用基数) || 0,
                busy:        (_root.发布请求 == true) || (_root.决斗场进入中 == true),
                knownEnemies: buildKnownEnemies()
            }
        });
    }

    private static function buildKnownEnemies():Array {
        var out:Array = [];
        if (_root.killStats == undefined || _root.killStats.byType == undefined) return out;
        var byType:Object = _root.killStats.byType;
        for (var key:String in byType) {
            var count:Number = Number(byType[key]);
            if (!isNaN(count) && count > 0) out.push(key);
        }
        return out;
    }

    private static function isKnownArenaEnemy(type:String):Boolean {
        if (_root.兵种库 == undefined || _root.兵种库[type] == undefined) return false;
        var spriteName:String = String(_root.兵种库[type].兵种名 || "");
        if (spriteName == "") return false;
        if (_root.killStats == undefined || _root.killStats.byType == undefined) return false;
        var count:Number = Number(_root.killStats.byType[spriteName]);
        return (!isNaN(count) && count > 0);
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
        // cardIndex 来自 web batch preview 路径：每张卡发独立 preview 时带 idx 0..7。
        // 旧 callsite（如未来调试 / 兼容路径）不传 → NaN，本路径仅跳过缓存写入，业务行为不变。
        var cardIndex:Number = Number(params.cardIndex);

        if (expr == "") {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_expr", cardIndex: cardIndex });
            return;
        }
        if (!ArenaController.rollPreview(expr)) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stock_insufficient", cardIndex: cardIndex });
            return;
        }

        var lineup:Array = _root.出阵人员;

        // 写 cardIndex → lineup 缓存（深拷贝避免 _root.出阵人员 后续被覆盖时污染缓存）。
        // handleEnter 按同样 cardIndex 取出 lineup 写回 _root.出阵人员 → commitArena 消费，
        // 守住 WYSIWYG: 用户看到的对手 = 实际打到的对手。
        if (!isNaN(cardIndex)) {
            if (_root._arenaLineupCache == undefined) _root._arenaLineupCache = [];
            _root._arenaLineupCache[cardIndex] = cloneLineup(lineup);
        }

        var opponents:Array = [];
        for (var i:Number = 0; i < lineup.length; i++) {
            opponents.push(buildOpponentSummary(lineup[i]));
        }

        sendResponse({
            task: "arena_response",
            callId: callId,
            success: true,
            cardIndex: cardIndex,
            expr: expr,
            opponents: opponents
        });
    }

    // 双层数组浅拷贝：merc tuple 是 Array，slot 是 string/number 基本类型，浅拷贝足够。
    // 避免后续 batch preview 改写 _root.出阵人员 时污染历史缓存槽位。
    private static function cloneLineup(src:Array):Array {
        var out:Array = [];
        for (var i:Number = 0; i < src.length; i++) {
            out.push(src[i].slice());
        }
        return out;
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

        // 技能：复用佣兵面板同一份重算（人格 → 技能列表，含 _root.技能缓存 命中优先），
        // 与 MercPanelService 共用一处算法，避免「展示用技能」与战斗权威技能两套种子漂移。
        // skills 形状 [{name, level, type, trait, cooldown, cost, unlock}, ...]，web 端按佣兵卡同款图标流渲染。
        var personality:Object = MercPanelService.buildPersonality(mercName, mercLevel);
        var skills:Array = MercPanelService.buildSkills(mercName, mercLevel, merc, personality);

        return { name: mercName, level: mercLevel, equips: equips, skills: skills };
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
            // LiteJSON 不转义双引号；TooltipComposer 的 <FONT COLOR='...'> 都用单引号，
            // 因此当前数据里 " 出现概率为 0，下面替换实际是 no-op。
            // 仍保留：未来若内容含字面 "，转 &quot; 比换 ' 更稳——
            //   - 转 '：内容里若已有 '（罕见但可能），会被当作属性闭合提前结束
            //   - 转 &quot;：HTML 渲染时变回字面 "，JSON 中是无害 ASCII，不影响任何边界
            descHTML: descHTML.split('"').join("&quot;"),
            introHTML: introHTML.split('"').join("&quot;")
        });
    }

    public static function handleEnter(params:Object):Void {
        var callId = params.callId;

        var expr:String = String(params.expr || "");
        var deposit:Number = Number(params.deposit);
        var reward:Number = Number(params.reward);
        // difficulty 来自 stage-select 重定向链；dev 模式 ARENA_TEST 直开时为 ""。
        // 非空时在 commitArena 之前设 _root.当前关卡难度 + _root.难度等级，
        // 让 _root.关卡结束 调 _root.FinishStage(name, _root.当前关卡难度) 时能匹配
        // 任务 finish_requirements 里的 "DEATH MATCH角斗场#冒险" 规则。
        var difficulty:String = String(params.difficulty || "");

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
        // 自管入场锁：防止 web 端 10s timeout 触发后用户重点 confirm 造成双扣 / 双跳关。
        // 注：_root.发布请求 / _root.决斗场进入中 在当前代码库内没有任何地方 set 为 true，
        // 仅 ArenaController.close 单向 reset，故无法靠它兜底；保留其检查仅作向后兼容预留。
        // 锁的 reset 路径：
        //   - 正常路径：handleSnapshot 入口（下次玩家打开 panel 即解锁）
        //   - 异常路径：commitArena 抛 Error 时本函数 catch 块直接 reset，避免玩家被锁死在主城
        if (_root.角斗场入场中 == true) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "busy" });
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

        // ── 爬升模式（Phase 3）分叉：web 下发 mode="escalation" + faction + pool（该势力单位池）──
        // 战斗循环 / 压力板决策 / 奖池经济全在 关卡回调函数 自管；这里仅校验 pool + 预载场景 + commit。
        if (String(params.mode) == "escalation") {
            var poolParam:Array = (params.pool != undefined) ? params.pool : null;
            if (poolParam == null || poolParam.length == 0) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "escalation_pool_empty" });
                return;
            }
            var pool:Array = [];
            for (var pi:Number = 0; pi < poolParam.length; pi++) {
                var pt:String = String(poolParam[pi].type);
                if (_root.兵种库[pt] == undefined) continue; // 跳过 web 与 AS2 兵种库不一致的未知兵种
                if (!isKnownArenaEnemy(pt)) continue; // 防旧缓存/伪造 payload 刷出玩家未击杀过的 spritename
                var pmin:Number = Number(poolParam[pi].minLevel);
                var pmax:Number = Number(poolParam[pi].maxLevel);
                var pw:Number = Number(poolParam[pi].weight);
                pool.push({
                    type:     pt,
                    minLevel: (isNaN(pmin) || pmin < 1) ? 1 : pmin,
                    maxLevel: (isNaN(pmax) || pmax < 1) ? 1 : pmax,
                    weight:   (isNaN(pw) || pw <= 0) ? 1 : pw
                });
            }
            if (pool.length == 0) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "escalation_pool_unknown" });
                return;
            }
            var faction:String = String(params.faction || "");
            var baseCount:Number = Number(params.baseCount);
            if (isNaN(baseCount) || baseCount < 1) baseCount = 4;
            var baseLevelMin:Number = Number(params.baseLevelMin);
            if (isNaN(baseLevelMin) || baseLevelMin < 1) baseLevelMin = 1;
            var baseLevelMax:Number = Number(params.baseLevelMax);
            if (isNaN(baseLevelMax) || baseLevelMax < baseLevelMin) baseLevelMax = baseLevelMin;
            var maxWaves:Number = Number(params.maxWaves);
            if (isNaN(maxWaves) || maxWaves < 1) maxWaves = 10; // 波数上限（小5/大10/联军15），缺省 10
            if (!ArenaController.prepareArenaStage(deposit, reward, difficulty)) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_info_missing" });
                return;
            }
            _root.角斗场入场中 = true;
            sendResponse({
                task: "arena_response", callId: callId, success: true,
                closePanel: true, deposit: deposit, reward: reward, expr: expr, mode: "escalation"
            });
            if (_root.soundEffectManager != undefined && _root.soundEffectManager.stopBGMForTransition != undefined) {
                _root.soundEffectManager.stopBGMForTransition();
            }
            try {
                ArenaController.commitEscalation(faction, pool, baseCount, baseLevelMin, baseLevelMax, deposit, reward, maxWaves);
            } catch (eE:Error) {
                _root.角斗场入场中 = false;
                if (typeof _root.最上层发布文字提示 == "function") _root.最上层发布文字提示("角斗场入场失败：" + eE.message);
            }
            return;
        }

        // ── 元战队（非人形怪）分叉：web M2 本地采样后下发 roster=[{type:"兵种N", level:L}, ...] ──
        // 有 roster → 走 commitRoster（不碰佣兵 cache / reuse / pool）；否则落入下方人形 merc 路径。
        var rosterParam:Array = (params.roster != undefined) ? params.roster : null;
        if (rosterParam != null && rosterParam.length > 0) {
            var squad:Array = [];
            for (var ri:Number = 0; ri < rosterParam.length; ri++) {
                var rt:String = String(rosterParam[ri].type);
                if (_root.兵种库[rt] == undefined) continue; // 跳过 web 与 AS2 兵种库不一致的未知兵种
                if (!isKnownArenaEnemy(rt)) continue; // 防旧缓存/伪造 payload 刷出玩家未击杀过的 spritename
                var rlvl:Number = Number(rosterParam[ri].level);
                squad.push({ 兵种: rt, 等级: (isNaN(rlvl) || rlvl < 1) ? 1 : rlvl });
            }
            if (squad.length == 0) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "roster_empty" });
                return;
            }
            if (!ArenaController.prepareArenaStage(deposit, reward, difficulty)) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_info_missing" });
                return;
            }
            _root.角斗场入场中 = true;
            sendResponse({
                task: "arena_response", callId: callId, success: true,
                closePanel: true, deposit: deposit, reward: reward, expr: expr, mode: "roster"
            });
            if (_root.soundEffectManager != undefined && _root.soundEffectManager.stopBGMForTransition != undefined) {
                _root.soundEffectManager.stopBGMForTransition();
            }
            try {
                ArenaController.commitRoster(squad);
            } catch (eR:Error) {
                _root.角斗场入场中 = false;
                if (typeof _root.最上层发布文字提示 == "function") _root.最上层发布文字提示("角斗场入场失败：" + eR.message);
            }
            return;
        }

        // 缓存优先取出（守 WYSIWYG）：web 端 batch preview 已按 cardIndex 抽过 8 卡，
        // 这里按 cardIndex 取缓存写回 _root.出阵人员 → 让 commitArena 消费用户实际看到的那批人。
        // 兜底：缓存不存在 + _root.出阵人员 也空（web 漏调 batch preview）→ 现场再抽一次保证不空 commit。
        var cardIndex:Number = Number(params.cardIndex);
        var cached:Array = (_root._arenaLineupCache != undefined && !isNaN(cardIndex))
                           ? _root._arenaLineupCache[cardIndex] : undefined;
        if (cached != undefined && cached.length > 0) {
            _root.出阵人员 = cloneLineup(cached); // 深拷贝写回，避免后续操作污染缓存槽位
        } else if (_root.出阵人员 == undefined || _root.出阵人员.length == 0) {
            if (!ArenaController.rollPreview(expr)) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "stock_insufficient" });
                return;
            }
        }

        // 原始路径："DEATH MATCH角斗场" 的 StageInfo.FadeTransitionFrame = "角斗场选择挑战者",
        // 玩家先到那个帧、由该帧 stage-select 入口预先调过 _root.载入关卡数据 把 StageManager 初始化,
        // 后续 enterArenaCommon → wuxianguotu_1 才能加载场景背景. Web 面板直接跳关, 必须手动复现 stage
        // 数据预载 + 押金/奖金/难度上下文——抽到 ArenaController.prepareArenaStage（merc 与 roster 共用）。
        if (!ArenaController.prepareArenaStage(deposit, reward, difficulty)) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_info_missing" });
            return;
        }

        // 上自管入场锁；handleSnapshot 入口 reset。覆盖 web 端 10s timeout 后的重发场景。
        _root.角斗场入场中 = true;

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
        // commit 已 preview 好的 _root.出阵人员（含 reuse 计数 / pool 刷新 / 扣押金 / 跳关）。
        // try/catch 兜底：commitArena 内任意 step 抛错都不能让 角斗场入场中 锁卡死。
        // 否则正常路径下要等下次开 panel 才解锁；若错误源持续存在玩家会永远入不了场。
        // 注：sendResponse(success) 已在 commit 之前发出 → web panel 已 close；异常时
        // 走 最上层发布文字提示 让玩家知道发生了什么，并 reset 锁让下一次 confirm 可行。
        try {
            ArenaController.commitArena();
        } catch (e:Error) {
            _root.角斗场入场中 = false;
            if (typeof _root.最上层发布文字提示 == "function") {
                _root.最上层发布文字提示("角斗场入场失败：" + e.message);
            }
            trace("[ArenaPanelService.handleEnter] commitArena failed: " + e.message);
        }
    }

    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
