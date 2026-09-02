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
 *     arenaSnapshot      — 返回 money / playerLevel / reuseCount / reuseLimit / busy / knownEnemies
 *     arenaRollPreview   — 调 ArenaController.rollPreview，序列化 _root.出阵人员 给 web 显示
 *     arenaEquipTooltip  — (raw, level) → BaseItem.getData() 走真 calculateData，含 tier/mods
 *                          → TooltipComposer 富文本（descHTML / introHTML）
 *     arenaEnter         — 消费已 preview 好的 _root.出阵人员，commit 进场
 *     arenaReturnBase    — 定制赛结算页关闭后，从竞技场场景返回基地
 *
 * 关键不变量：
 *   - rollPreview 写 _root.出阵人员，但不碰 reuse 计数 / pool 刷新。无 cooldown，可以无限重抽
 *   - arenaEnter 只 commit，不重新抽签（保证 WYSIWYG：用户看到的就是会打到的）
 *
 * 注意：普通 close 不走本桥。定制赛结算页 close 会由 Host 显式下发 arenaReturnBase。
 */
import org.flashNight.arki.item.*;
import org.flashNight.arki.merc.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.tooltip.*;

class org.flashNight.arki.merc.ArenaPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _arenaResponseSeq:Number = 0;
    private static var _arenaResponseEnvelopes:Object = {};
    private static var _committingArenaResponseKey:String = "";
    private static var _committingArenaResponseToken:String = "";

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
        _root.gameCommands["arenaReturnBase"] = function(params) {
            org.flashNight.arki.merc.ArenaPanelService.handleReturnBase(params);
        };

        _inited = true;
    }

    public static function handleReturnBase(params:Object):Void {
        _root.角斗场入场中 = false;
        _root.角斗场对手类型 = "merc";
        _root.角斗场roster阵容 = undefined;
        _root.角斗场roster状态 = undefined;
        _root.角斗场对手禁收益 = false;
        _root.角斗场爬升 = undefined;
        _root._arenaLineupCache = [];

        if (typeof _root.返回基地 == "function") {
            _root.返回基地();
            return;
        }
        // 返回基地必须经过 StageRunSession.onReturnBaseStarted；没有权威入口时 fail closed。
    }

    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        // panel 重新打开 = 上次入场链已经走完（玩家从战场回主城，或从未真正入场）。
        // 这里把自管入场锁 reset 掉，覆盖 ArenaController.close 在 web 路径下不会被
        // 调用的事实（close 仅挂在旧 Flash 角斗场选择界面的"取消挑战"按钮上）。
        _root.角斗场入场中 = false;
        // 对手类型默认人形佣兵；roster（元战队/混编）由后续 enter 显式置位，
        // 这里复位防上一场 roster 残留泄漏进 enterArenaCommon / 角斗场加载 的分叉判断。
        _root.角斗场对手类型 = "merc";
        _root.角斗场roster阵容 = undefined;
        _root.角斗场roster状态 = undefined;
        _root.角斗场对手禁收益 = false;
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
                playerLevel: Number(_root.等级) || 1,
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
        if (isHumanoidTemplateSprite(spriteName)) return true; // 竞技场混编允许主角模板佣兵型单位
        if (_root.killStats == undefined || _root.killStats.byType == undefined) return false;
        var count:Number = Number(_root.killStats.byType[spriteName]);
        return (!isNaN(count) && count > 0);
    }

    private static function isHumanoidTemplateSprite(spriteName:String):Boolean {
        return String(spriteName || "").indexOf("主角") >= 0;
    }

    private static function buildArenaMercById(mercId:String):Array {
        if (_root.mercs_list == undefined || _root.merc_indices_by_id == undefined) return null;
        var idx = _root.merc_indices_by_id[mercId];
        if (idx == undefined) idx = _root.merc_indices_by_id[Number(mercId)];
        if (idx == undefined || _root.mercs_list[idx] == undefined) return null;
        var raw:Object = _root.mercs_list[idx];
        if (raw.hidden == true) return null; // 竞技场混编默认不抽隐藏/彩蛋佣兵
        return MercLibrary.buildMercData(raw);
    }

    /**
     * 抽一批对手并序列化给 Web 显示。
     * 输出 opponents: [{ id, name, level, gender, height, face, hair,
     *                     equips: [{slot, name, level}, ...], skills: [...] }, ...]
     * - slot 是原始数组下标 6..16（11 槽）
     * - 装备 level：若编码字符串自带 level (!=1) 用之，否则用 DressupInitializer 按佣兵 (level, name) 算出来的默认强化度
     */
    public static function handleRollPreview(params:Object):Void {
        var callId = params.callId;
        var authority:Object = buildAuthorityQuote(params);
        if (authority == null || (authority.mode != "standard" && authority.mode != "hidden")) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_authority" });
            return;
        }
        var expr:String = String(authority.expr);
        // cardIndex 来自 web batch preview 路径：每张卡发独立 preview 时带 idx 0..7。
        // 旧 callsite（如未来调试 / 兼容路径）不传 → NaN，本路径仅跳过缓存写入，业务行为不变。
        var cardIndex:Number = Number(params.cardIndex);

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

    private static function matchesFrozenLineup(
            current:Array, expectedRef:Array, expectedSignature:String):Boolean {
        return current != undefined && current === expectedRef && current.length > 0
            && _json.stringifySafe(current) === expectedSignature;
    }

    private static function buildOpponentSummary(merc:Array):Object {
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

        // 竞技场右栏与战队面板共用 MercPortraits。这里只扩充只读投影，不改变抽签、缓存或入场协议；
        // 旧 Host 缺字段时 Web 仍会按默认脸型 / 性别 fail-soft，滚动升级期间不会白屏。
        var g:String = String(merc[17]);
        var gender:String = (g == "男" || g == "主角-男" || g == "1" || merc[17] == 1) ? "男" : "女";

        return {
            id: mercId,
            name: mercName,
            level: mercLevel,
            gender: gender,
            height: Number(merc[3]) || 0,
            face: String(merc[4] || ""),
            hair: String(merc[5] || ""),
            equips: equips,
            skills: skills
        };
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
            // wire 由 sendResponse 的 stringifySafe 统一转义；保留原始 htmlText。
            // 真实数据里存在双引号属性（如 <font color="#ff00ff">）：旧 &quot; 替换会让
            // convertAS2Html 的白名单校验丢样式，' 替换会破坏 wire JSON；两者都已废弃。
            descHTML: descHTML,
            introHTML: introHTML
        });
    }

    public static function handleEnter(params:Object):Void {
        var callId = params.callId;

        var authority:Object = buildAuthorityQuote(params);
        if (authority == null) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "invalid_authority" });
            return;
        }
        var expr:String = String(authority.expr);
        var deposit:Number = Number(authority.deposit);
        var reward:Number = Number(authority.reward);
        var enterMode:String = String(params.mode || "");
        if ((authority.mode == "escalation" && enterMode != "escalation")
                || (authority.mode == "custom_pve" && enterMode != "custom_pve")
                || ((authority.mode == "standard" || authority.mode == "hidden" || authority.mode == "fallen")
                    && enterMode != "")) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "authority_mode_mismatch" });
            return;
        }
        // difficulty 来自 stage-select 重定向链；dev 模式 ARENA_TEST 直开时为 ""。
        // 非空时在 commitArena 之前设 _root.当前关卡难度 + _root.难度等级，
        // 让 _root.关卡结束 调 _root.FinishStage(name, _root.当前关卡难度) 时能匹配
        // 任务 finish_requirements 里的 "DEATH MATCH角斗场#冒险" 规则。
        var difficulty:String = String(params.difficulty || "");

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
        if (enterMode == "escalation") {
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
                var poolUnit:Object = {
                    type:     pt,
                    minLevel: (isNaN(pmin) || pmin < 1) ? 1 : pmin,
                    maxLevel: (isNaN(pmax) || pmax < 1) ? 1 : pmax,
                    weight:   (isNaN(pw) || pw <= 0) ? 1 : pw
                };
                var pParams:Object = poolParam[pi].Parameters != undefined ? poolParam[pi].Parameters
                    : (poolParam[pi].parameters != undefined ? poolParam[pi].parameters : poolParam[pi].参数);
                if (pParams != undefined) poolUnit.Parameters = ObjectUtil.clone(pParams);
                pool.push(poolUnit);
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
            if (!beginArenaCommit(params, authority, difficulty, "escalation",
                    undefined,
                    function():Void {
                        _root.角斗场对手禁收益 = false;
                    },
                    function():Boolean {
                        return ArenaController.commitEscalation(faction, pool, baseCount,
                            baseLevelMin, baseLevelMax, deposit, reward, maxWaves);
                    },
                    function():Void {
                        _root.角斗场对手禁收益 = false;
                    })) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_info_missing" });
            }
            return;
        }

        // ── 元战队 / 混编分叉：web M2 本地采样后下发 roster=[{type:"兵种N", level:L} | {kind:"merc", mercId}, ...] ──
        // 有 roster → 走 commitRoster（不碰佣兵 cache / reuse / pool）；否则落入下方人形 merc 路径。
        var rosterParam:Array = (params.roster != undefined) ? params.roster : null;
        if ((authority.mode == "hidden" || authority.mode == "fallen" || authority.mode == "custom_pve")
                && (rosterParam == null || rosterParam.length == 0)) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "roster_required" });
            return;
        }
        if (rosterParam != null && rosterParam.length > 0) {
            var squad:Array = [];
            var customPve:Boolean = (enterMode == "custom_pve");
            for (var ri:Number = 0; ri < rosterParam.length; ri++) {
                var rKind:String = String(rosterParam[ri].kind || "");
                if (rKind == "merc" || rosterParam[ri].mercId != undefined) {
                    var merc:Array = buildArenaMercById(String(rosterParam[ri].mercId));
                    if (merc == null) continue;
                    squad.push({ 类型: "merc", 佣兵: merc, 禁收益: customPve });
                    continue;
                }
                var rt:String = String(rosterParam[ri].type);
                if (_root.兵种库[rt] == undefined) continue; // 跳过 web 与 AS2 兵种库不一致的未知兵种
                if (!customPve && !isKnownArenaEnemy(rt)) continue; // 标准 roster 仍防旧缓存/伪造 payload；PVE 测试场允许全量 units.json
                var rlvl:Number = Number(rosterParam[ri].level);
                var squadUnit:Object = { 兵种: rt, 等级: (isNaN(rlvl) || rlvl < 1) ? 1 : rlvl, 禁收益: customPve };
                var rParams:Object = rosterParam[ri].Parameters != undefined ? rosterParam[ri].Parameters
                    : (rosterParam[ri].parameters != undefined ? rosterParam[ri].parameters : rosterParam[ri].参数);
                if (rParams != undefined) squadUnit.Parameters = ObjectUtil.clone(rParams);
                squad.push(squadUnit);
            }
            if (squad.length == 0) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "roster_empty" });
                return;
            }
            if (!beginArenaCommit(params, authority, difficulty,
                    customPve ? "custom_pve" : "roster",
                    undefined,
                    function():Void {
                        _root.角斗场对手禁收益 = customPve;
                    },
                    function():Boolean {
                        return ArenaController.commitRoster(squad);
                    },
                    function():Void {
                        _root.角斗场对手禁收益 = false;
                    })) {
                sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_info_missing" });
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
        var frozenLineupRef:Array = _root.出阵人员;
        var frozenLineupSignature:String = _json.stringifySafe(frozenLineupRef);

        // 原始路径："DEATH MATCH角斗场" 的 StageInfo.FadeTransitionFrame = "角斗场选择挑战者",
        // 玩家先到那个帧、由该帧 stage-select 入口预先调过 _root.载入关卡数据 把 StageManager 初始化,
        // 后续 enterArenaCommon → wuxianguotu_1 才能加载场景背景. Web 面板直接跳关, 必须手动复现 stage
        // 数据预载 + 押金/奖金/难度上下文——抽到 ArenaController.prepareArenaStage（merc 与 roster 共用）。
        if (!beginArenaCommit(params, authority, difficulty, "",
                function():Boolean {
                    return matchesFrozenLineup(
                        _root.出阵人员, frozenLineupRef, frozenLineupSignature);
                },
                function():Void {
                    _root.角斗场对手禁收益 = false;
                },
                function():Boolean {
                    return ArenaController.commitArena();
                },
                function():Void {
                    _root.角斗场对手禁收益 = false;
                })) {
            sendResponse({ task: "arena_response", callId: callId, success: false, error: "stage_info_missing" });
        }
    }

    /** XML/TimePool 成功后才复核报价/余额并提交角斗场写操作。 */
    private static function beginArenaCommit(params:Object, authority:Object,
            difficulty:String, successMode:String, finalGate:Function, beforeCommit:Function,
            commit:Function, cleanup:Function):Boolean {
        var callId = params.callId;
        var deposit:Number = Number(authority.deposit);
        var reward:Number = Number(authority.reward);
        var expr:String = String(authority.expr);
        var responseGeneration:Number = registerArenaResponseEnvelope(
            callId, deposit, reward, expr, successMode);
        var settled:Boolean = false;
        var requestToken:String = "";
        var failOnce:Function = function(errorCode:String):Void {
            if (settled) return;
            settled = true;
            try { ArenaController.cancelPendingStageStart(requestToken); }
            catch (cancelError) {
                trace("[ArenaPanelService.handleEnter] pending cancel failed: "
                    + cancelError);
            }
            _root.角斗场入场中 = false;
            try {
                if (typeof cleanup == "function") cleanup();
            } catch (cleanupError) {
                trace("[ArenaPanelService.handleEnter] failure cleanup failed: "
                    + cleanupError);
            }
            try {
                sendArenaFailureResponse(responseGeneration, requestToken, errorCode);
            } catch (failureResponseError) {
                trace("[ArenaPanelService.handleEnter] failure response failed: "
                    + failureResponseError);
            }
        };
        var prepared:Boolean = ArenaController.prepareArenaStage(deposit, reward, difficulty,
            function(data:Object, preparedToken:String):Void {
                if (settled) return;
                requestToken = String(preparedToken || "");
                if (!bindArenaResponseEnvelope(responseGeneration, requestToken)) {
                    failOnce("stage_state_changed");
                    return;
                }
                var fresh:Object = buildAuthorityQuote(params);
                if (fresh == null || String(fresh.expr) != expr
                        || Number(fresh.deposit) != deposit
                        || Number(fresh.reward) != reward
                        || String(params.difficulty || "") != difficulty) {
                    failOnce("authority_changed");
                    return;
                }
                if (Number(_root.金钱) < deposit) {
                    failOnce("insufficient_money");
                    return;
                }
                if (_root.角斗场入场中 == true || _root.发布请求 == true) {
                    failOnce("busy");
                    return;
                }
                if (typeof finalGate == "function") {
                    var gatePassed:Boolean = false;
                    try { gatePassed = finalGate() === true; }
                    catch (gateError) {
                        trace("[ArenaPanelService.handleEnter] final gate failed: " + gateError);
                    }
                    if (!gatePassed) {
                        failOnce("stage_state_changed");
                        return;
                    }
                }
                var commitSnapshot:Object = captureArenaCommitState();
                if (!markArenaResponseCommitting(responseGeneration, requestToken)) {
                    failOnce("stage_state_changed");
                    return;
                }
                try {
                    if (!ArenaController.applyPreparedArenaContext(
                            deposit, reward, difficulty)) {
                        throw new Error("prepared arena context is stale");
                    }
                    if (typeof beforeCommit == "function") beforeCommit();
                    _root.角斗场入场中 = true;
                    if (_root.soundEffectManager != undefined
                            && _root.soundEffectManager.stopBGMForTransition != undefined) {
                        _root.soundEffectManager.stopBGMForTransition();
                    }
                    if (typeof commit != "function" || commit() !== true) {
                        throw new Error("arena commit produced no transition");
                    }
                } catch (commitError) {
                    trace("[ArenaPanelService.handleEnter] deferred commit failed: " + commitError);
                    restoreArenaCommitState(commitSnapshot);
                    failOnce("stage_transition_failed");
                    return;
                }
                settled = true;
                try {
                    // commit 内部已经触发淡出；此处只从类级 exact-token 封套取回回包，
                    // 不再读取 beginArenaCommit 的任何函数局部量。
                    sendCommittedArenaResponse();
                }
                catch (responseError) {
                    trace("[ArenaPanelService.handleEnter] post-commit response failed: "
                        + responseError);
                }
            },
            function(preparedToken:String):Void {
                requestToken = String(preparedToken || "");
                if (!bindArenaResponseEnvelope(responseGeneration, requestToken)) {
                    discardArenaResponseEnvelope(responseGeneration);
                    return;
                }
                failOnce("stage_load_failed");
            });
        if (!prepared) discardArenaResponseEnvelope(responseGeneration);
        return prepared;
    }

    /**
     * 异步 arena enter 的回包必须活在类级 owner 中：AS2 主时间轴淡出后，调用方
     * activation 的 callId/报价局部量可能变成 undefined。generation 只负责抵御
     * 尚未拿到 token 的重复请求；绑定后所有 take/clear 都同时复核 exact token。
     */
    private static function registerArenaResponseEnvelope(callId,
            deposit:Number, reward:Number, expr:String, successMode:String):Number {
        var generation:Number = ++_arenaResponseSeq;
        var response:Object = {
            task:"arena_response", callId:callId, success:true,
            closePanel:true, deposit:deposit, reward:reward, expr:expr
        };
        if (successMode != "") response.mode = successMode;
        _arenaResponseEnvelopes["r" + generation] = {
            generation:generation,
            token:"",
            state:"awaiting_token",
            successResponse:response
        };
        return generation;
    }

    private static function getArenaResponseEnvelope(generation:Number):Object {
        return _arenaResponseEnvelopes["r" + generation];
    }

    private static function bindArenaResponseEnvelope(
            generation:Number, token:String):Boolean {
        if (token == "") return false;
        var envelope:Object = getArenaResponseEnvelope(generation);
        if (envelope == null || Number(envelope.generation) != generation) return false;
        if (envelope.token != "" && String(envelope.token) !== token) return false;
        envelope.token = token;
        if (envelope.state == "awaiting_token") envelope.state = "bound";
        return envelope.state == "bound" || envelope.state == "committing";
    }

    private static function markArenaResponseCommitting(
            generation:Number, token:String):Boolean {
        var key:String = "r" + generation;
        var envelope:Object = _arenaResponseEnvelopes[key];
        if (envelope == null || envelope.state != "bound"
                || String(envelope.token) !== token) return false;
        if (_committingArenaResponseKey != ""
                && _committingArenaResponseKey !== key) return false;
        envelope.state = "committing";
        _committingArenaResponseKey = key;
        _committingArenaResponseToken = token;
        return true;
    }

    private static function discardArenaResponseEnvelope(generation:Number):Void {
        var key:String = "r" + generation;
        if (_committingArenaResponseKey === key) {
            _committingArenaResponseKey = "";
            _committingArenaResponseToken = "";
        }
        delete _arenaResponseEnvelopes[key];
    }

    private static function sendArenaFailureResponse(
            generation:Number, token:String, errorCode:String):Void {
        var key:String = "r" + generation;
        var envelope:Object = _arenaResponseEnvelopes[key];
        if (envelope == null || token == ""
                || String(envelope.token) !== token) return;
        if (_committingArenaResponseKey === key) {
            _committingArenaResponseKey = "";
            _committingArenaResponseToken = "";
        }
        delete _arenaResponseEnvelopes[key];
        sendResponse({task:"arena_response",
            callId:envelope.successResponse.callId,
            success:false, error:errorCode});
    }

    private static function sendCommittedArenaResponse():Void {
        var key:String = _committingArenaResponseKey;
        if (key == "") return;
        var envelope:Object = _arenaResponseEnvelopes[key];
        if (envelope == null || envelope.state != "committing"
                || String(envelope.token) == ""
                || String(envelope.token) !== _committingArenaResponseToken) {
            _committingArenaResponseKey = "";
            _committingArenaResponseToken = "";
            return;
        }
        _committingArenaResponseKey = "";
        _committingArenaResponseToken = "";
        delete _arenaResponseEnvelopes[key];
        sendResponse(envelope.successResponse);
    }

    private static function captureArenaCommitState():Object {
        var fields:Array = [
            "关卡类型", "关卡路径", "押金", "角斗场奖金", "当前关卡难度", "难度等级",
            "角斗场入场中", "角斗场对手禁收益", "角斗场对手类型", "角斗场roster状态",
            "角斗场roster阵容", "角斗场爬升", "当前通关的关卡", "当前关卡名",
            "场景进入位置名", "敌人同伴数", "敌人同伴数据", "当前佣兵重用数"
        ];
        var values:Object = {};
        for (var i:Number = 0; i < fields.length; i++) {
            values[String(fields[i])] = _root[String(fields[i])];
        }
        return {
            fields:fields,
            values:values,
            money:_root.金钱,
            dirtyMark:_root.存档系统 != undefined
                ? _root.存档系统.dirtyMark : undefined,
            switchFrame:_root.场景转换函数 != undefined
                ? _root.场景转换函数.上次切换帧数 : undefined
        };
    }

    private static function restoreArenaCommitState(snapshot:Object):Void {
        if (snapshot == null) return;
        var fields:Array = snapshot.fields;
        for (var i:Number = 0; i < fields.length; i++) {
            var field:String = String(fields[i]);
            _root[field] = snapshot.values[field];
        }
        _root.金钱 = snapshot.money;
        if (_root.存档系统 != undefined) {
            _root.存档系统.dirtyMark = snapshot.dirtyMark;
        }
        if (_root.场景转换函数 != undefined) {
            _root.场景转换函数.上次切换帧数 = snapshot.switchFrame;
        }
    }

    /**
     * P5 双端权威复算。C# 从 XML/JSON 真源生成本局输入；AS2 在任何写入前按同一公开公式
     * 独立重算并精确比较 wire 上的 expr/deposit/reward。字符串数字、NaN/Infinity、分数人数
     * 或缺少 source digest 均 fail-closed，避免旧 Web payload 绕过 Host 直达本层。
     */
    public static function buildAuthorityQuote(params:Object):Object {
        if (params == null || typeof params.authorityId != "string" || String(params.authorityId) == ""
                || typeof params.authorityMode != "string"
                || typeof params.authoritySourceDigest != "string" || String(params.authoritySourceDigest) == "") {
            return null;
        }
        var mode:String = String(params.authorityMode);
        if (mode != "standard" && mode != "hidden" && mode != "fallen"
                && mode != "escalation" && mode != "custom_pve") return null;

        var levelMin:Number = readAuthorityInteger(params.levelMin, 1);
        var levelMax:Number = readAuthorityInteger(params.levelMax, levelMin);
        var opponentCount:Number = readAuthorityInteger(params.opponentCount, 1);
        if (isNaN(levelMin) || isNaN(levelMax) || isNaN(opponentCount)) return null;

        var expectedExpr:String = "#0@" + levelMin + "-" + levelMax + "%" + opponentCount;
        var expectedReward:Number;
        var expectedDeposit:Number;
        if (mode == "custom_pve") {
            expectedReward = 0;
            expectedDeposit = 0;
        } else if (mode == "standard" || mode == "hidden") {
            if (typeof params.economyMultiplier != "number") return null;
            var multiplier:Number = Number(params.economyMultiplier);
            if (isNaN(multiplier) || multiplier == Infinity || multiplier == -Infinity
                    || multiplier <= 0 || multiplier > 10) return null;
            if (mode == "standard" && multiplier != 1) return null;
            var perLevel:Number = levelMin >= 40 ? 1250 : 1000;
            var baseReward:Number = roundAuthority(opponentCount * levelMin * perLevel, 1000);
            expectedReward = roundAuthority(baseReward * multiplier, 1000);
            expectedDeposit = Math.max(500, roundAuthority(expectedReward / 2, 500));
        } else {
            var benchLevel:Number = readAuthorityInteger(params.benchLevel, 1);
            if (isNaN(benchLevel)) return null;
            if (mode == "escalation") {
                expectedReward = roundAuthority(benchLevel * opponentCount * 500, 100);
                expectedDeposit = roundAuthority(expectedReward, 1000);
            } else {
                expectedReward = roundAuthority(benchLevel * opponentCount * 800, 1000);
                expectedDeposit = roundAuthority(expectedReward * 0.4, 1000);
            }
        }

        if (typeof params.expr != "string" || String(params.expr) != expectedExpr
                || typeof params.deposit != "number" || Number(params.deposit) != expectedDeposit
                || typeof params.reward != "number" || Number(params.reward) != expectedReward) {
            return null;
        }
        return {
            mode:mode,
            expr:expectedExpr,
            deposit:expectedDeposit,
            reward:expectedReward
        };
    }

    private static function readAuthorityInteger(value, minimum:Number):Number {
        if (typeof value != "number") return NaN;
        var number:Number = Number(value);
        if (isNaN(number) || number == Infinity || number == -Infinity
                || number < minimum || number != Math.floor(number)) return NaN;
        return number;
    }

    private static function roundAuthority(value:Number, step:Number):Number {
        return Math.max(step, Math.round(value / step) * step);
    }

    private static function sendResponse(resp:Object):Void {
        // 响应可含用户可编辑自由文本：统一走 stringifySafe 标准转义出口。
        _root.server.sendSocketMessage(_json.stringifySafe(resp));
    }
}
