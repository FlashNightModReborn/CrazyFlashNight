/**
 * 文件：org/flashNight/arki/achievement/AchievementService.as
 * 说明：成就系统 AS2 权威服务（设计：docs/成就系统-A轮-设计-2026-06-10.md §4.1）。
 *
 * 架构（四层之判定/生命周期层，与 TaskPanelService 同构的桥协议）：
 *   - 内容：data/achievement/*.json 经 AchievementDataLoader 非阻塞加载（绝不抄任务帧
 *     stop()/play() 阻塞模式——数据缺失 = 降级提示，不挡启动）。
 *   - 状态：_root._saveExt.成就 = {v, base:{kt}, cnt, unl, claimed}（随 mydata.ext 透传存档）。
 *   - 触发：惰性权威 + 低频轮询锁存——handleState 开面板全量现算（纯只读）；
 *     scanTick（10 秒循环任务）为解锁锁存 + toast 通知的唯一写点。
 *   - 命令：gameCommands["achievementState"|"achievementClaim"]（C# TaskTask 转发，
 *     全称命名防 WebOverlayForm "claim" 被 ShopTask 截胡）。
 *
 * 硬约束（设计 §10 陷阱表）：
 *   - D1 基线红线：base.kt undefined → 快照【当前 killStats.total】，绝不写 0（老档秒解锁）；
 *     ensureInit 首行就绪门控（角色名/killStats undefined → false），三入口统一走它，禁旁路。
 *   - scanTick 必须用 帧计时器.添加循环任务（添加或更新任务 = 单次任务陷阱，跑一次即死）。
 *   - ext 引用每次现场解引用，禁缓存跨帧（loadAll 整体替换 _root._saveExt）。
 *   - unl 锁存位图只加不减（棘轮，防 itemOwned 卖出回退）；对外 unlocked = 锁存 ‖ 现算。
 *   - claimed 置位必须在 acquire 成功【之后】（反面教材：任务 appendQuestRewards 先写后发）。
 *   - progressOf 永不返 null、cur 封顶 target（HeroUtil.getNextTitleInfo 满档返 null 教训）。
 *   - hidden 硬门控：未解锁 hidden 条目不回 progress（防探测）；明文仅经 hiddenReveals 回传。
 */
import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.json.LoadJson.AchievementDataLoader;
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.arki.item.ItemUtil;
import LiteJSON;

class org.flashNight.arki.achievement.AchievementService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _dataReady:Boolean = false;
    private static var _dataFailed:Boolean = false;
    private static var defs:Object = null;       // id(String) → 成就定义（raw JSON 条目）
    private static var defIds:Array = null;      // 遍历顺序（JSON 声明序）
    private static var _scanRegistered:Boolean = false;
    private static var _scanTaskID:String = null; // 循环任务 id 备查（cleanup 路径防御）
    private static var _suppressToastOnce:Boolean = false; // 容器新建/补缺/自愈后首轮 scan 静默（防老档追溯解锁 toast 轰炸）

    // ═══════════════════════════════════════════════════════════
    // install — 安装入口（任务系统_WebView.as 帧 41 调用；此刻存档未读，不碰数据）
    // ═══════════════════════════════════════════════════════════
    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["achievementState"] = function(params) {
            org.flashNight.arki.achievement.AchievementService.handleState(params);
        };
        _root.gameCommands["achievementClaim"] = function(params) {
            org.flashNight.arki.achievement.AchievementService.handleClaim(params);
        };

        // 场景转换每次都发 SceneReady（含 newCharacter 延迟 30 帧）→ ensureInit 幂等 O(1)
        EventBus.getInstance().subscribe("SceneReady", onSceneReady, AchievementService);

        // 非阻塞加载成就目录（不进时间轴帧，加载失败降级不挡启动）
        AchievementDataLoader.getInstance().load(onData, onError);

        _inited = true;
    }

    private static function onData(raw:Array):Void {
        defs = {};
        defIds = [];
        for (var i:Number = 0; i < raw.length; i++) {
            var def:Object = raw[i];
            if (def == undefined || def.id == undefined) continue;
            var idStr:String = String(def.id);
            if (defs[idStr] != undefined) continue; // dup 运行时保守跳过（派生器已在 build 拦截）
            defs[idStr] = def;
            defIds.push(idStr);
        }
        _dataReady = true;
    }

    private static function onError():Void {
        _dataFailed = true;
        _root.发布消息("成就数据加载失败，成就功能暂不可用");
    }

    private static function onSceneReady():Void {
        if (!ensureInit()) return;
        if (!_scanRegistered) {
            // ⚠ 必须 添加循环任务（无限循环）。添加或更新任务 在任务不存在时建【单次任务】
            //   （TaskManager.as:574-587），scanTick 跑一次即死且本 flag 锁死重注册 → 通知整体失效。
            //   回调闭包包装：addLoopTask 回调 scope 统一为 null（TaskManager.as:375 契约）。
            _scanTaskID = _root.帧计时器.添加循环任务(function() {
                org.flashNight.arki.achievement.AchievementService.scanTick();
            }, 10000);
            _scanRegistered = true;
        }
    }

    // ═══════════════════════════════════════════════════════════
    // ensureInit — 状态容器初始化/补缺/基线快照/单调自愈（唯一入口，禁旁路手写）
    //   挂三处：onSceneReady / 每个 gameCommands handler 首行 / scanTick 首行。
    // ═══════════════════════════════════════════════════════════
    private static function ensureInit():Boolean {
        // D1 红线执行点：存档/killStats 未就绪绝不拍基线（防标题画面拍出 0/假基线）
        if (_root.角色名 == undefined || _root.killStats == undefined) return false;

        var ext:Object = _root._saveExt; // 每次现场解引用，禁缓存（loadAll 整体替换 ext）
        if (ext == undefined) ext = _root._saveExt = {};

        var a:Object = ext.成就;
        var dirty:Boolean = false;
        if (a == undefined) {
            a = ext.成就 = {v: 1, base: {}, cnt: {}, unl: {}, claimed: {}};
            _suppressToastOnce = true;
            dirty = true;
        }
        if (a.v == undefined) { a.v = 1; dirty = true; }            // record() 先行建容器路径回填
        if (a.base == undefined) { a.base = {}; dirty = true; }
        if (a.cnt == undefined) { a.cnt = {}; dirty = true; }
        if (a.unl == undefined) { a.unl = {}; _suppressToastOnce = true; dirty = true; } // 迁移档首轮锁存静默
        if (a.claimed == undefined) { a.claimed = {}; dirty = true; }

        // killTotal 基线快照：undefined → 快照【当前值】，绝不写 0（D1：否则老档秒解锁且随档固化）
        if (isNaN(Number(a.base.kt))) {
            a.base.kt = Number(_root.killStats.total) || 0;
            dirty = true;
        }
        // 单调性自愈：基线 > 当前 total = 删档残留等异常 → 整体重建（兜底防线，设计 §3.3；
        // 主防线 = newCharacter/deleteSlot 清 _saveExt，本分支探测不到 kt==0 残留属可接受盲区）
        if (Number(a.base.kt) > (Number(_root.killStats.total) || 0)) {
            ext.成就 = {v: 1, base: {kt: Number(_root.killStats.total) || 0}, cnt: {}, unl: {}, claimed: {}};
            _suppressToastOnce = true;
            dirty = true;
        }

        if (dirty) _root.存档系统.dirtyMark = true;
        return true;
    }

    // ═══════════════════════════════════════════════════════════
    // 判定层 — 逐类型进度现算（无通用求值器，YAGNI 已否决；枚举=派生器白名单同集）
    // ═══════════════════════════════════════════════════════════
    private static function curOf(def:Object):Number {
        var o:Object = def.objective;
        var t:String = o.type;
        var p:Object = (o.params != undefined) ? o.params : {};
        var a:Object = _root._saveExt.成就;

        if (t == "killTotal") {
            // D1 公式：基线后增量
            return Math.max(0, (Number(_root.killStats.total) || 0) - (Number(a.base.kt) || 0));
        }
        if (t == "economyCount") {
            var c:Number = Number(a.cnt[p.counter]);
            return isNaN(c) ? 0 : c;
        }
        if (t == "infraLevel") {
            var lv:Number = Number(_root.基建系统.infrastructure[p.name]);
            return isNaN(lv) ? 0 : lv;
        }
        if (t == "infraBuiltCount") {
            var n:Number = 0;
            var infra:Object = _root.基建系统.infrastructure;
            for (var k:String in infra) {
                if (Number(infra[k]) > 0) n++;
            }
            return n;
        }
        if (t == "taskFinished") {
            // ⚠ tasks_finished 值=完成次数非布尔（可重复任务自增），显式 >=1，禁 ==true
            return (Number(_root.tasks_finished[String(p.taskId)]) >= 1) ? 1 : 0;
        }
        if (t == "chainProgress") {
            var prog:Number = Number(_root.task_chains_progress[p.chain]);
            return isNaN(prog) ? 0 : prog;
        }
        if (t == "skillLevel") {
            var sl:Number = Number(_root.根据技能名查找主角技能等级(p.skill));
            return isNaN(sl) ? 0 : sl;
        }
        if (t == "itemOwned") {
            var cnt:Number = (p.count != undefined && !isNaN(Number(p.count))) ? Number(p.count) : 1;
            return TaskUtil.containTaskItems([p.item + "#" + cnt]) ? 1 : 0;
        }
        return 0; // 未知类型（派生器已拦）：永不解锁，不抛错（AS2 无 try/finally，回调禁 throw）
    }

    // 永不返 null；cur 封顶 target（HeroUtil.getNextTitleInfo 满档返 null 教训；ach-ui4 断言）
    private static function progressOf(def:Object):Object {
        var target:Number = Number(def.objective.target);
        if (isNaN(target) || target < 1) target = 1;
        var cur:Number = curOf(def);
        if (isNaN(cur) || cur < 0) cur = 0;
        if (cur > target) cur = target;
        return {cur: cur, target: target};
    }

    private static function check(def:Object):Boolean {
        var pr:Object = progressOf(def);
        return pr.cur >= pr.target;
    }

    // 对外唯一 unlocked 口径：锁存位图 ‖ 现算（棘轮；状态型追溯解锁天然成立，锁存只固化达成事实）
    private static function isUnlocked(def:Object):Boolean {
        var a:Object = _root._saveExt.成就;
        if (a != undefined && a.unl != undefined && a.unl[String(def.id)] == 1) return true;
        return check(def);
    }

    // ═══════════════════════════════════════════════════════════
    // scanTick — 解锁锁存 + toast 通知的唯一写点（10 秒循环任务，两次触发间零每帧成本）
    // ═══════════════════════════════════════════════════════════
    public static function scanTick():Void {
        if (!_dataReady) return;
        if (!ensureInit()) return;
        var a:Object = _root._saveExt.成就; // 现场解引用
        var newly:Array = [];
        for (var i:Number = 0; i < defIds.length; i++) {
            var idStr:String = defIds[i];
            if (a.unl[idStr] == 1) continue;
            if (check(defs[idStr])) {
                a.unl[idStr] = 1; // 锁存只加不减
                newly.push(idStr);
            }
        }
        if (newly.length > 0) {
            _root.存档系统.dirtyMark = true;
            if (!_suppressToastOnce) {
                for (var j:Number = 0; j < newly.length; j++) {
                    _root.发布消息("成就解锁：" + defs[newly[j]].title);
                }
            }
        }
        // 首轮静默仅一次：老档追溯解锁可达十几条，首扫静默锁存；正常会话首扫照常通知
        _suppressToastOnce = false;
    }

    // ═══════════════════════════════════════════════════════════
    // buildStateOverlay — state/claim 回包共用的完整状态投影（单一口径，web 原子重渲）
    //   纯只读（锁存写点只归 scanTick / handleClaim ⑥）。
    //   hidden 硬门控：未解锁 hidden 条目剔除 progress（进度可探测=隐藏成就泄露）；
    //   已解锁 hidden 经 hiddenReveals 按需回传明文（catalog 已脱敏，含 rewards）。
    // ═══════════════════════════════════════════════════════════
    private static function buildStateOverlay():Object {
        if (!_dataReady) return null;
        var a:Object = _root._saveExt.成就;
        if (a == undefined) return null;
        var unlocked:Array = [];
        var claimed:Array = [];
        var progress:Object = {};
        var hiddenReveals:Array = [];
        for (var i:Number = 0; i < defIds.length; i++) {
            var idStr:String = defIds[i];
            var def:Object = defs[idStr];
            var unl:Boolean = isUnlocked(def);
            var clm:Boolean = (Number(a.claimed[idStr]) > 0);
            if (unl) unlocked.push(idStr);
            if (clm) claimed.push(idStr);
            if (def.hidden == true && !unl && !clm) continue;
            progress[idStr] = progressOf(def).cur;
            if (def.hidden == true) {
                hiddenReveals.push({
                    id: def.id,
                    title: String(def.title),
                    description: String(def.description),
                    rewards: parseRewards(def)
                });
            }
        }
        return {unlocked: unlocked, claimed: claimed, progress: progress, hiddenReveals: hiddenReveals};
    }

    private static function parseRewards(def:Object):Array {
        var out:Array = [];
        var rw:Array = def.rewards;
        if (rw == undefined) return out;
        for (var i:Number = 0; i < rw.length; i++) {
            var parts:Array = String(rw[i]).split("#");
            var cnt:Number = (parts[1] != undefined) ? Number(parts[1]) : 1;
            out.push({name: parts[0], count: isNaN(cnt) ? 1 : cnt});
        }
        return out;
    }

    // ═══════════════════════════════════════════════════════════
    // handleState — 只读状态叠加（开面板/写后刷新；静态文案/goal 由 web 读 catalog，不经桥）
    // ═══════════════════════════════════════════════════════════
    public static function handleState(params:Object):Void {
        var callId = params.callId;
        if (!_dataReady || !ensureInit()) {
            sendResponse({task: "task_response", callId: callId, cmd: "achievementState",
                success: false, error: "not_ready", dataReady: _dataReady});
            return;
        }
        var ov:Object = buildStateOverlay();
        sendResponse({task: "task_response", callId: callId, cmd: "achievementState", success: true,
            unlocked: ov.unlocked, claimed: ov.claimed, progress: ov.progress,
            hiddenReveals: ov.hiddenReveals, dataReady: true});
    }

    // ═══════════════════════════════════════════════════════════
    // handleClaim — 领取（写操作，门控链照 TaskPanelService.handleFinish；每分支必回包）
    // ═══════════════════════════════════════════════════════════
    public static function handleClaim(params:Object):Void {
        var callId = params.callId;
        // ① 就绪门控
        if (!_dataReady || !ensureInit()) {
            sendResponse(claimResp(callId, false, "not_ready", null));
            return;
        }
        // ② 稳定主键（绝不收 index）
        var idStr:String = String(params.achievementId);
        var def:Object = defs[idStr];
        if (def == undefined) {
            sendResponse(claimResp(callId, false, "achievement_not_found", null));
            return;
        }
        var a:Object = _root._saveExt.成就;
        // ③ 服务端权威解锁判定（锁存‖现算，绝不信 web 的 unlocked）
        if (!isUnlocked(def)) {
            sendResponse(claimResp(callId, false, "not_unlocked", null));
            return;
        }
        // ④ 领取幂等位图
        if (Number(a.claimed[idStr]) > 0) {
            sendResponse(claimResp(callId, false, "already_claimed", null));
            return;
        }
        // ⑤ 奖励发放（acquire 全有或全无）；背包满 → 不置 claimed，保持 unlocked 可重试
        //   （D3：天然化解旧档批量补发雪崩；不应用任务挑战折扣——任务域行为，有意分叉）
        var rewardsArr:Array = (def.rewards != undefined) ? def.rewards : [];
        var ok:Boolean = true;
        if (rewardsArr.length > 0) {
            ok = (ItemUtil.acquire(ItemUtil.getRequirementFromTask(rewardsArr)) == true);
        }
        if (!ok) {
            sendResponse(claimResp(callId, false, "inventory_full", null));
            return;
        }
        // ⑥ 成功置位：必须在 acquire true 之后（claimed ⊇ unlocked 不变量 + 锁存写入沿）
        a.claimed[idStr] = 1;
        a.unl[idStr] = 1;
        _root.存档系统.dirtyMark = true;
        sendResponse(claimResp(callId, true, undefined, parseRewards(def)));
    }

    // claim 回包：每分支并入完整 state overlay（单一口径），web 原子重渲零额外往返
    private static function claimResp(callId, success:Boolean, error:String, rewards:Array):Object {
        var resp:Object = {task: "task_response", callId: callId, cmd: "achievementClaim", success: success};
        if (error != undefined) resp.error = error;
        if (rewards != null) resp.rewards = rewards;
        var ov:Object = buildStateOverlay();
        if (ov != null) {
            resp.unlocked = ov.unlocked;
            resp.claimed = ov.claimed;
            resp.progress = ov.progress;
            resp.hiddenReveals = ov.hiddenReveals;
            resp.dataReady = true;
        } else {
            resp.dataReady = _dataReady;
        }
        return resp;
    }

    // ═══════════════════════════════════════════════════════════
    // sendResponse — 统一回包（与 TaskPanelService 同口径）
    // ═══════════════════════════════════════════════════════════
    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
