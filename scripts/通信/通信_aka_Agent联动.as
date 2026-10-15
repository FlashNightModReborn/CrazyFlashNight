// Agent 联动：不调用 _root.服务器；data/rag/sync_state.json 的 task_publish_version 与 _root.agent.last_task_publish_version（初始 0）比较，非战斗图轮询热更。

_root.agent = {};
_root.agent.npc_state_db_exists = false;
_root.agent.last_task_publish_version = null;
_root.agent.sync_poll_busy = false;
_root.agent.sync_apply_busy = false;
// 宿主已换任务内容而游戏侧重载未落地时为 true；下一轮无条件整目录重载补齐。
_root.agent.task_reload_owed = false;
_root.agent.failed_publish_version = null;
_root.agent.REL_SYNC_STATE = "data/rag/sync_state.json";
_root.agent.REL_NPC_STATE_DB = "data/rag/npc_state_db.json";
_root.agent.REL_LAUNCH_BAT = "data/rag/launch_cfn_rag.bat";
_root.agent.KEY_TASK_PUBLISH_VERSION = "task_publish_version";
// 槽位目录同步（G2-3②）：已对齐槽位与防重入。null＝从未对齐。
_root.agent.slot_catalog_aligned = null;
_root.agent.slot_catalog_busy = false;
// Agent 委托 id 区间（与终端 TaskRegistry.list_agent_tasks、dialogue.view.AGENT_TASK_ID_RANGE 同口径）：
// 只有落在区间内的完成才推事件，主线/支线/副本完成不打扰终端。
_root.agent.AGENT_TASK_ID_MIN = 200001;
_root.agent.AGENT_TASK_ID_MAX = 300000;

_root.agent.读取任务发布版本号 = function(raw:String):Number {
    if (raw == undefined || raw.length == 0) {
        return 0;
    }
    var j:LiteJSON = new LiteJSON();
    var obj:Object = j.parse(raw);
    if (obj == undefined || obj == null || typeof obj != "object") {
        return 0;
    }
    var v = obj[_root.agent.KEY_TASK_PUBLISH_VERSION];
    if (v == undefined) {
        return 0;
    }
    var n:Number = Number(v);
    if (isNaN(n)) {
        return 0;
    }
    return n;
};

_root.agent.检测npc状态库文件 = function():Void {
    PathManager.initialize(null);
    if (!PathManager.isEnvironmentValid()) {
        return;
    }
    var self:Object = _root.agent;
    var checkFile:Function;
    // 先检测 npc_state_db.json，不存在则检测 sync_state.json
    checkFile = function(relPath:String, onDone:Function):Void {
        var fullPath:String = PathManager.resolvePath(relPath);
        if (fullPath == null) {
            onDone(false);
            return;
        }
        var lv:LoadVars = new LoadVars();
        lv.onData = function(raw:String):Void {
            var exists:Boolean = (raw != undefined && raw.length > 0);
            onDone(exists);
        };
        lv.load(fullPath);
    };
    // 第一个回调：检测 npc_state_db.json 结果
    var onFirstCheck:Function = function(exists:Boolean):Void {
        if (exists) {
            self.npc_state_db_exists = true;
            _root.agent.注册同步轮询();
        } else {
            // 第一个不存在，检测第二个
            checkFile(self.REL_SYNC_STATE, onSecondCheck);
        }
    };
    // 第二个回调：检测 sync_state.json 结果
    var onSecondCheck:Function = function(exists:Boolean):Void {
        self.npc_state_db_exists = exists;
        _root.agent.注册同步轮询();
    };
    checkFile(self.REL_NPC_STATE_DB, onFirstCheck);
};

_root.agent.轮询同步状态 = function():Void {
    if (_root.当前为战斗地图 == true) {
        return;
    }
    if (_root._taskReloadBusy == true) {
        return;
    }
    if (_root.agent.sync_poll_busy == true) {
        return;
    }
    if (_root.agent.sync_apply_busy == true) {
        return;
    }
    // 槽位对齐检查（G2-3②）：当前槽位与宿主侧目录投影未对齐时先补对齐，本轮不再进行版本轮询。
    var slot:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    if (slot != "" && _root.agent.slot_catalog_aligned !== slot) {
        _root.agent.请求槽位目录同步();
        return;
    }
    if (!PathManager.isEnvironmentValid()) {
        return;
    }
    var fullPath:String = PathManager.resolvePath(_root.agent.REL_SYNC_STATE);
    if (fullPath == null) {
        return;
    }
    // _root.发布消息("正在轮询……");
    _root.agent.sync_poll_busy = true;
    var lv:LoadVars = new LoadVars();
    var r:Object = _root.agent;
    lv.onData = function(raw:String):Void {
        r.sync_poll_busy = false;
        if (raw == undefined || raw.length == 0) {
            r.last_task_publish_version = 0;
            return;
        }
        var fileVer:Number = r.读取任务发布版本号(raw);
        if (isNaN(fileVer)) {
            r.last_task_publish_version = 0;
            return;
        }
        if (r.last_task_publish_version == null) {
            r.last_task_publish_version = fileVer;
            return;
        }
        if (fileVer == r.last_task_publish_version) {
            return;
        }
        _root.发布消息("正在接收终端任务数据……");
        _root.agent.同步任务热更新(fileVer);
    };
    lv.load(fullPath);
};

// 任务发布版本变化后的收敛流程。宿主是变更权威：由它重读任务目录、判定哪些源文件真的变了，
// 游戏侧只按清单增量重载，最后原子提交宿主回传的新握手（内容摘要 + 会话令牌）。
// finish 与 giveUp 合计恰好执行一次，绝不把桥留在提交窗口里；版本号只在真正收敛后推进。
_root.agent.同步任务热更新 = function(fileVer:Number):Void {
    var r:Object = _root.agent;
    if (r.sync_apply_busy == true || _root._taskReloadBusy == true || r.slot_catalog_busy == true) {
        return;
    }
    r.sync_apply_busy = true;
    var done:Boolean = false;

    function finish():Void {
        if (done) {
            return;
        }
        done = true;
        r.sync_apply_busy = false;
        r.task_reload_owed = false;
        org.flashNight.arki.map.MapDomainBridge.commitTaskSync();
        r.last_task_publish_version = fileVer;
        _root.最上层发布文字提示("已接收终端任务数据！");
    }

    // 宿主已换内容但游戏侧没跟上时，欠账标记让下一轮无条件重载到磁盘真值；
    // 版本号不推进，所以本轮不算同步完成，失败提示同一版本只出一次。
    function giveUp(reason:String):Void {
        if (done) {
            return;
        }
        done = true;
        r.sync_apply_busy = false;
        _root.发布消息("任务热更新未收敛：" + reason);
        if (r.failed_publish_version != fileVer) {
            r.failed_publish_version = fileVer;
            _root.最上层发布文字提示("任务数据更新失败！");
        }
    }

    function reload(changedFiles:Array):Void {
        if (_root._taskReloadBusy == true) {
            giveUp("任务重载已在执行中");
            return;
        }
        _root.重新加载任务数据(
            function():Void {
                finish();
            },
            function():Void {
                if (changedFiles == null) {
                    giveUp("任务数据重载失败");
                    return;
                }
                reload(null);
            },
            changedFiles
        );
    }

    org.flashNight.arki.map.MapDomainBridge.syncTasks(function(ok:Boolean, error:String, result:Object):Void {
        if (ok != true) {
            giveUp(String(error));
            return;
        }
        // 欠账优先：上一轮宿主已换内容而游戏侧没落地，这轮无论宿主怎么答都整目录重载。
        if (r.task_reload_owed == true) {
            reload(null);
            return;
        }
        if (result == undefined || result.changed != true) {
            finish();
            return;
        }
        r.task_reload_owed = true;
        reload((result.listChanged == true || !(result.changedFiles instanceof Array)) ? null : result.changedFiles);
    });
};

// G2-1 载荷投影：ragchat initData 与 rag_bind_refresh 共用的五键形状。
// Host 白名单（LauncherCommandRouter.TryParseRagChatProjection）只收
// savePath/character/progress/scene/player，且 tasks_finished/tasks_active 必须是整数数组、
// task_chains_progress 必须是对象——违反任何一条整包被拒。
// 全部只读投影：缺数据回落空值，不写任何游戏状态，不依赖面板上下文。

// 剥掉称号可能携带的受限 font 标签，仅留纯文本；未闭合的 "<" 按字面保留。
_root.agent.投影剥除标签 = function(raw):String {
    if (raw == undefined || raw == null) return "";
    var s:String = String(raw);
    var out:String = "";
    var i:Number = 0;
    while (i < s.length) {
        var tagStart:Number = s.indexOf("<", i);
        if (tagStart < 0) {
            out += s.substr(i);
            break;
        }
        var tagEnd:Number = s.indexOf(">", tagStart + 1);
        if (tagEnd < 0) {
            out += s.substr(i);
            break;
        }
        out += s.substr(i, tagStart - i);
        i = tagEnd + 1;
    }
    return out;
};

// 数字安全化：非有限数回落默认值。
_root.agent.投影数字 = function(raw, dflt:Number):Number {
    var n:Number = Number(raw);
    return isFinite(n) ? n : dflt;
};

// 布尔归一化（对齐 SkillLoadoutService.parseLegacyBoolean 的已知取值；未知按 false）。
_root.agent.投影布尔 = function(raw):Boolean {
    if (typeof raw == "boolean") return raw;
    if (typeof raw == "number") return raw == 1;
    if (typeof raw == "string") {
        var s:String = String(raw).toLowerCase();
        return s == "true" || s == "1";
    }
    return false;
};

// 杀敌数达标称号：与 HeroUtil.getTitleByKillCount 同口径（降序表首匹配）。
_root.agent.投影杀敌称号 = function(killTotal:Number):String {
    var ranks:Array = org.flashNight.arki.unit.HeroUtil.getAllTitleRanks();
    if (!(ranks instanceof Array)) return "";
    for (var i:Number = 0; i < ranks.length; i++) {
        var rank:Object = ranks[i];
        if (rank != undefined && killTotal >= Number(rank.kills)) return String(rank.title);
    }
    return "";
};

// 场景段：关卡标志（对齐 map_definition sceneName）/ 当前关卡名 / 场景进入位置名 / 是否战斗地图。
// stageName 在非战斗场景是上一次战斗关卡的残留值，消费方需用 inCombat 门控。
_root.agent.投影场景段 = function():Object {
    return {
        stageFlag: (_root.关卡标志 == undefined || _root.关卡标志 == null)
            ? "" : String(_root.关卡标志),
        stageName: (_root.当前关卡名 == undefined || _root.当前关卡名 == null)
            ? "" : String(_root.当前关卡名),
        entrance: (_root.场景进入位置名 == undefined || _root.场景进入位置名 == null)
            ? "" : String(_root.场景进入位置名),
        inCombat: _root.当前为战斗地图 == true
    };
};

// 称号段：三来源——颈部装备称号 / 杀敌数达标称号 / 最终显示称号（HeroUtil.getHeroTitle 口径）。
_root.agent.投影称号段 = function():Object {
    var equipTitle:String = "";
    var hero:MovieClip = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager.findHero();
    if (hero != null && hero.颈部装备数据 != undefined && hero.颈部装备数据.data != undefined
            && hero.颈部装备数据.data.title != undefined) {
        equipTitle = String(hero.颈部装备数据.data.title);
    }
    var killStats:Object = _root.killStats;
    var byKills:String = "";
    if (killStats != undefined && killStats != null
            && isFinite(Number(killStats.total)) && Number(killStats.total) >= 0) {
        byKills = _root.agent.投影杀敌称号(Number(killStats.total));
    }
    return {
        equip: _root.agent.投影剥除标签(equipTitle),
        byKills: _root.agent.投影剥除标签(byKills),
        final: _root.agent.投影剥除标签(org.flashNight.arki.unit.HeroUtil.getHeroTitle())
    };
};

// 难度段：0=困难 1=简单 2=挑战（与 引擎_aka_作弊码 的显示口径一致）。
_root.agent.投影难度段 = function():Object {
    var mode:Number = _root.agent.投影数字(_root.difficultyMode, 0);
    var labels:Array = ["困难", "简单", "挑战"];
    var label:String = (mode >= 0 && mode < labels.length) ? String(labels[mode]) : String(labels[0]);
    return {mode: mode, label: label};
};

// 击杀段：总击杀 + 按兵种细分（数量降序、同类按名升序，最多 100 类）。
_root.agent.投影击杀段 = function():Object {
    var total:Number = 0;
    var byType:Array = [];
    var stats:Object = _root.killStats;
    if (stats != undefined && stats != null) {
        total = _root.agent.投影数字(stats.total, 0);
        var map:Object = stats.byType;
        if (map != undefined && map != null) {
            for (var key in map) {
                var count:Number = Number(map[key]);
                if (!isFinite(count) || count < 1) continue;
                byType.push({name: String(key), count: count});
            }
        }
    }
    byType.sort(function(a:Object, b:Object):Number {
        if (b.count != a.count) return b.count - a.count;
        if (a.name < b.name) return -1;
        if (a.name > b.name) return 1;
        return 0;
    });
    if (byType.length > 100) byType.length = 100;
    return {total: total, byType: byType};
};

// 成就段：AchievementService 只读投影；未就绪/异常降级为空段形状。
_root.agent.投影成就段 = function():Object {
    var empty:Object = {items: [], unlockedCount: 0, total: 0};
    var projection:Object = null;
    try {
        projection = org.flashNight.arki.achievement.AchievementService.buildAgentProjection();
    } catch (achievementProjectionError) {
        return empty;
    }
    if (projection == undefined || projection == null) return empty;
    return projection;
};

// 技能段：主角技能表 [名字, 等级, 快捷栏标志, 类型, 启用标志]；被动口径对齐 SkillLoadoutService.isPassive。
_root.agent.投影技能列表 = function():Array {
    var out:Array = [];
    var table = _root.主角技能表;
    if (!(table instanceof Array)) return out;
    var meta:Object = _root.技能表对象;
    for (var i:Number = 0; i < table.length; i++) {
        var row = table[i];
        if (!(row instanceof Array) || row.length < 1) continue;
        var name:String = (row[0] == undefined || row[0] == null) ? "" : String(row[0]);
        if (name == "" || name == "undefined") continue;
        var m:Object = (meta == undefined || meta == null) ? null : meta[name];
        var passive:Boolean = (m != null)
            && (m.Passive === true || String(m.Type).indexOf("被动") >= 0);
        out.push({
            name: name,
            level: _root.agent.投影数字(row[1], 0),
            passive: passive,
            enabled: _root.agent.投影布尔(row[4])
        });
    }
    return out;
};

// 装备段：主角 11 槽（与 CharacterBuildService.SLOT_ALLOWLIST 同集），读 物品栏.装备栏 权威。
_root.agent.投影装备列表 = function():Array {
    var out:Array = [];
    var inventory:Object = _root.物品栏;
    var bar:Object = (inventory == null) ? null : inventory.装备栏;
    if (bar == null) return out;
    var slots:Array = ["头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"];
    var dict:Object = _root.物品属性列表;
    for (var i:Number = 0; i < slots.length; i++) {
        var slot:String = slots[i];
        var name:String = "";
        if (typeof bar.getNameString == "function") {
            var rawName = bar.getNameString(slot);
            if (rawName != undefined && rawName != null) name = String(rawName);
        }
        if ((name == "" || name == "undefined") && typeof bar.getItem == "function") {
            var item:Object = bar.getItem(slot);
            if (item != null && item.name != undefined && item.name != null) name = String(item.name);
        }
        if (name == "" || name == "undefined") continue;
        var displayname:String = name;
        if (dict != undefined && dict != null
                && dict[name] != undefined && dict[name] != null
                && dict[name].displayname != undefined
                && String(dict[name].displayname) != "") {
            displayname = String(dict[name].displayname);
        }
        var level:Number = 1;
        if (typeof bar.getLevel == "function") {
            var lv:Number = Number(bar.getLevel(slot));
            if (isFinite(lv) && lv >= 1) level = lv;
        }
        out.push({slot: slot, name: name, displayname: displayname, level: level});
    }
    return out;
};

// 宠物段：宠物信息槽 [宠物id, 等级, 体力, , 出战标志]；显示名走 战宠UI函数（自定义名权威）。
_root.agent.投影宠物列表 = function():Array {
    var out:Array = [];
    var pets:Array = _root.宠物信息;
    if (!(pets instanceof Array)) return out;
    var lib:Object = _root.宠物库;
    for (var i:Number = 0; i < pets.length; i++) {
        var info:Array = pets[i];
        if (info == undefined || !(info instanceof Array) || info.length < 5) continue;
        var def:Object = (lib == undefined || lib == null) ? undefined : lib[info[0]];
        if (def == undefined || def == null) continue;
        var name:String = String(def.Name);
        if (_root.战宠UI函数 != undefined
                && typeof _root.战宠UI函数.获取宠物显示名 == "function") {
            var shown = _root.战宠UI函数.获取宠物显示名(i);
            if (shown != undefined && shown != null && String(shown) != "") name = String(shown);
        }
        out.push({
            name: name,
            identifier: String(def.Identifier),
            level: _root.agent.投影数字(info[1], 0),
            stamina: _root.agent.投影数字(info[2], 0),
            deployed: Number(info[4]) == 1
        });
    }
    return out;
};

// 佣兵段：同伴数据全列 [等级, 名字, id, 身高, 脸型, 发型, ...装备..., 性别, 价格, 元数据]；
// 出战与 佣兵是否出战信息 同下标（MercSpawner 严格并行压实）。人格/对话为旧档缺列时降级空值。
_root.agent.投影佣兵列表 = function():Array {
    var out:Array = [];
    var data:Array = _root.同伴数据;
    if (!(data instanceof Array)) return out;
    var deploy:Array = _root.佣兵是否出战信息;
    for (var i:Number = 0; i < data.length; i++) {
        var merc:Array = data[i];
        if (merc == undefined || !(merc instanceof Array) || merc[0] == undefined) continue;
        var name:String = (merc[1] == undefined || merc[1] == null) ? "" : String(merc[1]);
        if (name == "" || name == "undefined") continue;
        var level:Number = _root.agent.投影数字(merc[0], 0);
        var gender:String = String(merc[17]);
        gender = (gender == "男" || gender == "主角-男" || gender == "1" || merc[17] == 1)
            ? "男" : "女";
        var personality:Object = {};
        if (typeof _root.生成随机人格 == "function") {
            try {
                var p:Object = org.flashNight.arki.merc.MercPanelService
                    .buildPersonality(merc, name, level);
                if (p != undefined && p != null) personality = p;
            } catch (personalityError) {
            }
        }
        var dialogues:Array = [];
        var meta:Object = merc[19];
        if (meta != undefined && meta != null && meta.对话 instanceof Array) {
            var lines:Array = meta.对话;
            for (var j:Number = 0; j < lines.length; j++) {
                var line:Object = lines[j];
                if (line == undefined || line == null) continue;
                var text:String = (line.文本 != undefined) ? String(line.文本) : String(line);
                if (text != "" && text != "undefined") dialogues.push(text);
            }
        }
        out.push({
            name: name,
            id: (merc[2] == undefined || merc[2] == null) ? "" : String(merc[2]),
            level: level,
            gender: gender,
            personality: personality,
            dialogues: dialogues,
            deployed: (deploy instanceof Array) && (Number(deploy[i]) == 1)
        });
    }
    return out;
};

// 基建段：复用平板权威快照（名称→等级），不另立第二套读法。
_root.agent.投影基建段 = function():Object {
    if (typeof _root.平板基建等级快照 == "function") {
        var snapshot:Object = _root.平板基建等级快照();
        if (snapshot != undefined && snapshot != null) return snapshot;
    }
    return {};
};

// 玩家段：基础身份、货币、称号、难度、击杀、成就、技能、装备、宠物、佣兵、基建。
_root.agent.投影玩家段 = function():Object {
    return {
        gender: (_root.性别 == undefined || _root.性别 == null) ? "" : String(_root.性别),
        level: _root.agent.投影数字(_root.等级, 0),
        height: _root.agent.投影数字(_root.身高, 0),
        title: _root.agent.投影称号段(),
        difficulty: _root.agent.投影难度段(),
        money: _root.agent.投影数字(_root.金钱, 0),
        kpoint: _root.agent.投影数字(_root.虚拟币, 0),
        kills: _root.agent.投影击杀段(),
        achievements: _root.agent.投影成就段(),
        skills: _root.agent.投影技能列表(),
        equipment: _root.agent.投影装备列表(),
        pets: _root.agent.投影宠物列表(),
        mercs: _root.agent.投影佣兵列表(),
        infrastructure: _root.agent.投影基建段()
    };
};

// 角色段：存档键 _root.角色名。
_root.agent.投影角色段 = function():Object {
    return {
        name: (_root.角色名 == undefined || _root.角色名 == null) ? "" : String(_root.角色名)
    };
};

// 进度段：tasks_finished 是「任务id→完成次数」表，投影为完成 id 的整数数组；
// tasks_active 取当前任务列表 tasks_to_do 的同口径过滤 id。
_root.agent.投影进度段 = function():Object {
    var finished:Array = [];
    var finishedMap:Object = _root.tasks_finished;
    if (finishedMap != undefined && finishedMap != null) {
        for (var taskKey in finishedMap) {
            var id:Number = Number(taskKey);
            var count:Number = Number(finishedMap[taskKey]);
            if (!isFinite(id) || id != Math.floor(id) || id < 0) continue;
            if (!isFinite(count) || count < 1) continue;
            finished.push(id);
        }
    }
    var active:Array = [];
    var activeList:Array = _root.tasks_to_do;
    if (activeList instanceof Array) {
        for (var i:Number = 0; i < activeList.length; i++) {
            var entry:Object = activeList[i];
            if (entry == undefined || entry == null) continue;
            var activeId:Number = Number(entry.id);
            if (!isFinite(activeId) || activeId != Math.floor(activeId) || activeId < 0) continue;
            active.push(activeId);
        }
    }
    var chains:Object = {};
    var chainMap:Object = _root.task_chains_progress;
    if (chainMap != undefined && chainMap != null) {
        for (var chain in chainMap) {
            var progress:Number = Number(chainMap[chain]);
            if (!isFinite(progress)) continue;
            chains[chain] = progress;
        }
    }
    return {tasks_finished: finished, task_chains_progress: chains, tasks_active: active};
};

_root.agent.构建存档投影 = function(savePath:String):Object {
    return {
        savePath: savePath,
        character: _root.agent.投影角色段(),
        progress: _root.agent.投影进度段(),
        scene: _root.agent.投影场景段(),
        player: _root.agent.投影玩家段()
    };
};

// G2-3③④：durable 落盘与任务完成时的投影刷新出口。经 Host 转发 rag_bind_refresh，
// exe 不在线由 Host 侧静默跳过；本函数不弹任何提示（best-effort）。
_root.agent.推送绑定刷新 = function():Void {
    if (_root.server == undefined || _root.server == null) return;
    if (typeof _root.server.sendTaskToNode != "function") return;
    if (_root.server.isSocketConnected !== true) return;
    var savePath:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    if (savePath == "") return;
    _root.server.sendTaskToNode("rag_bind_refresh", _root.agent.构建存档投影(savePath), null);
};

// G4-1：Agent 委托完成事件（纯通知，query 语义——不改任何游戏状态、不等 exe 应答）。
// 经 Host 的 rag_task_completed 转发到终端 POST /api/integration/task-completed，终端只对
// 发布时挂了对话重写标记的委托自动派对话修改子 Agent；同存档同任务的幂等由终端侧保证，
// 可重复委托每次交付都推一次也无害。exe 不在线由 Host 静默跳过，本函数不弹任何提示。
_root.agent.推送任务完成 = function(taskId):Void {
    var id:Number = Number(taskId);
    if (!isFinite(id) || id != Math.floor(id)) return;
    if (id < _root.agent.AGENT_TASK_ID_MIN || id > _root.agent.AGENT_TASK_ID_MAX) return;
    if (_root.server == undefined || _root.server == null) return;
    if (typeof _root.server.sendTaskToNode != "function") return;
    if (_root.server.isSocketConnected !== true) return;
    var savePath:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    if (savePath == "") return;
    _root.server.sendTaskToNode("rag_task_completed",
        {savePath: savePath, taskId: id, npc: _root.agent.任务发布NPC(String(id))}, null);
};

// 事件里的 npc 只作终端侧的兜底名字（终端以任务记录里的 get_npc 为权威）；读不到给空串。
_root.agent.任务发布NPC = function(taskId:String):String {
    if (org.flashNight.arki.task.TaskUtil.tasks == null) return "";
    var taskData:Object = org.flashNight.arki.task.TaskUtil.getRawTaskData(taskId);
    if (taskData == undefined || taskData == null
            || taskData.get_npc == undefined || taskData.get_npc == null) return "";
    return String(taskData.get_npc);
};

// G2-3②：换槽位后的任务目录对齐。宿主按新 savePath 重读覆盖层并回变化清单，
// 游戏侧只重载真正变化的文件（silent=true 不弹提示、不推进任务发布版本号）。
// 失败 trace-only；下一轮 7 秒轮询的对齐检查会重试，task_reload_owed 防止
// 「宿主已换内容而游戏侧没落地」被一个 changed=false 的答复抹掉。
_root.agent.请求槽位目录同步 = function():Void {
    var r:Object = _root.agent;
    var slot:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    if (slot == "" || r.slot_catalog_busy == true) return;
    if (r.sync_apply_busy == true || _root._taskReloadBusy == true) return;
    if (r.slot_catalog_aligned === slot) return;
    r.slot_catalog_busy = true;
    var done:Boolean = false;

    function finish():Void {
        if (done) return;
        done = true;
        r.slot_catalog_busy = false;
        r.task_reload_owed = false;
        org.flashNight.arki.map.MapDomainBridge.commitTaskSync();
        r.slot_catalog_aligned = slot;
    }

    function giveUp(reason:String):Void {
        if (done) return;
        done = true;
        r.slot_catalog_busy = false;
        trace("[Agent] 槽位目录同步未收敛：" + reason);
    }

    function reload(changedFiles:Array):Void {
        if (_root._taskReloadBusy == true) {
            giveUp("任务重载已在执行中");
            return;
        }
        _root.重新加载任务数据(
            function():Void {
                finish();
            },
            function():Void {
                if (changedFiles == null) {
                    giveUp("任务数据重载失败");
                    return;
                }
                reload(null);
            },
            changedFiles,
            true
        );
    }

    org.flashNight.arki.map.MapDomainBridge.syncTasks(function(ok:Boolean, error:String, result:Object):Void {
        if (ok != true) {
            giveUp(String(error));
            return;
        }
        // 欠账优先：上一轮宿主已换内容而游戏侧没落地，这轮无论宿主怎么答都整目录重载。
        if (r.task_reload_owed == true) {
            reload(null);
            return;
        }
        if (result == undefined || result.changed != true) {
            finish();
            return;
        }
        r.task_reload_owed = true;
        reload((result.listChanged == true || !(result.changedFiles instanceof Array)) ? null : result.changedFiles);
    });
};

// 读档完成点（通信_fs_bootstrap / SaveManager.replacePlayerContext）：
// 换槽位＝向终端重推绑定 + 任务目录按新槽位对齐，两者都 best-effort。
_root.agent.槽位已切换 = function():Void {
    _root.agent.推送绑定刷新();
    _root.agent.请求槽位目录同步();
};

_root.agent.注册同步轮询 = function():Void {
    if(_root.agent.npc_state_db_exists){
        _root.帧计时器.添加循环任务(_root.agent.轮询同步状态, 7000);
    }
};
_root.agent.启动外部RAG工具 = function():Void {
    _root.最上层发布文字提示("正在启动通讯终端，请稍后……");
    // 游戏内嵌集成（阶段一）：改走 Host panel_request —— Host 负责确保 cfn-rag 就绪并把
    // 当前存档绑定给终端，随后以外层 ragchat 面板 iframe 承载终端页面；就绪/绑定失败由
    // Host 经 gameCommand ragChatUnavailable 回 toast，本函数不再直接拉起外部浏览器窗口。
    if (typeof _root.server.sendSocketMessage != "function") {
        _root.最上层发布文字提示("通讯终端暂不可用，请稍后重试。");
        return;
    }
    var savePath:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
    var initFields:Array = [{name:"savePath", value:savePath}];
    if (savePath != "") {
        // G2-1：非空槽位才带全量投影；raw=true 让 PanelRequestEnvelope 原样内联
        // stringifySafe 的输出（对象投影不能走字符串字段的二次转义）。
        var projection:Object = _root.agent.构建存档投影(savePath);
        var json:LiteJSON = new LiteJSON();
        initFields.push({name:"character", value:json.stringifySafe(projection.character), raw:true});
        initFields.push({name:"progress", value:json.stringifySafe(projection.progress), raw:true});
        initFields.push({name:"scene", value:json.stringifySafe(projection.scene), raw:true});
        initFields.push({name:"player", value:json.stringifySafe(projection.player), raw:true});
    }
    var sent:Boolean = _root.server.sendSocketMessage(
        org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "ragchat", "agent_console", [], initFields
        )
    );
    if (!sent) {
        _root.最上层发布文字提示("通讯终端暂不可用，请稍后重试。");
    }
    // 旧外部拉起路径（阶段五删除）：
    // fscommand("fullscreen", "false");
    // fscommand("exec", "launch_rag.bat");
};

// Host→AS2 失败回执：面板未开（或前置就绪失败）时给出明确提示；纯提示，不写任何游戏状态。
if (_root.gameCommands == undefined) _root.gameCommands = {};
_root.gameCommands["ragChatUnavailable"] = function(params:Object):Void {
    var message:String = (params == undefined || params.message == undefined) ? "" : String(params.message);
    if (message == "") {
        message = "通讯终端暂不可用，请稍后重试。";
    }
    _root.最上层发布文字提示(message);
};

// 平板 Web 面板的「终端通信」按钮经 Host tablet 域回环到本命令；
// 实际打开仍走 启动外部RAG工具 → panel_request（savePath 由 AS2 侧取 _root.savePath）。
// callId 回执经 tablet_response 由 Host TabletTask 关联储备后回包 tablet 面板。
_root.gameCommands["openRagTerminal"] = function(params:Object):Void {
    if (typeof _root.agent.启动外部RAG工具 == "function") {
        _root.agent.启动外部RAG工具();
    }
    if (_root.平板回执 != undefined) {
        _root.平板回执(params, {task:"tablet_response", ok:true});
    }
};

_root.agent.检测npc状态库文件();
