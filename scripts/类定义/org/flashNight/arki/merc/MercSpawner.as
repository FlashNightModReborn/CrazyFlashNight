import org.flashNight.arki.merc.*;
import org.flashNight.aven.Coordinator.EventCoordinator;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/*
 * 场景佣兵刷新链（Phase C：单步赤字驱动）。
 *
 * 设计：
 *   - frame 29 (Symbol 2396) random(几率)==0 控制触发频率（XML <Entrance> 注入）
 *   - 每次触发 spawnAtGate 调度 1 个 spawn task（真正的单步赤字驱动）
 *   - task 内部独立掷 70/30 gate/court、独立 pickGatePoint、独立位置抖动
 *   - MercBudget.shouldSpawn（sqrt 模型）在 addCourtMerc/addGateMerc 入口决定落地
 *   - 旧 emergent throttle 链（areaFactor / 0.5 / NaN / Math.max,1）已删
 *   - Initial 进场批量走 spawnInScene(count)：XML Initial 字段语义现在是"尝试数"
 *
 * mercData 数组列约定（与 MercHybridizer 共享）：
 *   [0] 等级  [1] 名字  [2] id  [3] 身高  [4] 脸型  [5] 发型
 *   [6..16] 装备  [17] 性别  [18] 价格  [19] 元数据
 */
class org.flashNight.arki.merc.MercSpawner {

    public static function removeMerc(mercId) {
        var idx:Number = -1;
        for (var i:Number = 0; i < _root.佣兵个数限制; i++) {
            if (_root.同伴数据[i][2] == mercId) {
                idx = i;
                break;
            }
        }
        if (idx == -1) {
            return undefined;
        }
        var meta:Object = _root.同伴数据[idx][19];
        var pushedBack:Boolean = false;
        if (meta && meta.是否杂交 == false) {
            _root.可雇佣兵.push(_root.同伴数据[idx]);
            pushedBack = true;
        }
        if (meta && meta.隐藏) {
            _root.隐藏的可雇佣兵.push(_root.同伴数据[idx]);
        }
        if (pushedBack) {
            invalidateIndexCache();
        }
        _root.同伴数--;
        _root.同伴数据[idx] = [];
        var compact:Array = [];
        for (var k:Number = 0; k < _root.佣兵个数限制; k++) {
            if (_root.同伴数据[k][0] != undefined) {
                compact.push(_root.同伴数据[k]);
            }
        }
        _root.同伴数据 = compact;
        _root.gameworld[_root.菜单MC对应名].removeMovieClip();
        for (var unit:String in _root.gameworld) {
            if (_root.gameworld[unit].用户ID == mercId) {
                _root.gameworld[unit].removeMovieClip();
            }
        }
        if (MercBudget.telemetryEnabled) {
            // DISMISS = 玩家解雇，merc 回到 _root.可雇佣兵 池可再次被 spawn。
            // 此时 alive_after 不会直接 -1（被解雇者的 mc 是同伴 NPC=false，本就不计入 countAlive）。
            MercBudget.emit("DISMISS", "id=" + mercId + " alive_after=" + MercCensus.countAlive());
        }
    }

    public static function initIndexCache():Void {
        var gw:MovieClip = _root.gameworld;
        if (gw.佣兵编号缓存 == undefined) {
            // 内部字段命名英文化（私有缓存，仅本类读写）
            gw.佣兵编号缓存 = {weights: [], totalWeight: 0, ready: false};
            _global.ASSetPropFlags(gw, ["佣兵编号缓存"], 1, false);
        }
    }

    // 池变化（loadFromList / removeMerc 回写）后必须失效，否则权重表跟新池长度对不齐。
    public static function invalidateIndexCache():Void {
        var gw:MovieClip = _root.gameworld;
        if (gw.佣兵编号缓存 != undefined) {
            gw.佣兵编号缓存.ready = false;
        }
    }

    public static function updateIndexCache():Void {
        initIndexCache();
        var cache:Object = _root.gameworld.佣兵编号缓存;
        if (!cache.ready) {
            cache.weights = [];
            cache.totalWeight = 0;

            // 等级分界线作为高斯分布的标准差，至少 15 级，或玩家等级的 30%
            var sigma:Number = Math.max(15, Math.floor(_root.等级 * 0.3));

            for (var i:Number = 0; i < _root.可雇佣兵.length; i++) {
                var diff:Number = Math.abs(_root.等级 - _root.可雇佣兵[i][0]);
                // 高斯 + 5% 基础权重：以玩家等级为中心呈钟形分布，所有等级保底 5%
                // weight = 0.05 + 0.95 * exp(-(diff^2) / (2 * σ^2))
                var w:Number = 0.05 + 0.95 * Math.exp(-(diff * diff) / (2 * sigma * sigma));
                cache.weights.push(w);
                cache.totalWeight += w;
            }
            cache.ready = true;
        }
    }

    public static function pickRandomMercIndex(taken:Array):Number {
        updateIndexCache();
        var cache:Object = _root.gameworld.佣兵编号缓存;

        var available:Array = [];
        for (var i:Number = 0; i < cache.weights.length; i++) {
            if (taken[i] == undefined) {
                available.push(i);
            }
        }
        if (available.length == 0) {
            return -1;
        }

        var r:Number = _root.basic_random() * cache.totalWeight;
        var acc:Number = 0;
        for (var j:Number = 0; j < available.length; j++) {
            var idx:Number = available[j];
            acc += cache.weights[idx];
            if (r <= acc) {
                return idx;
            }
        }
        return -1;
    }

    public static function spawnInWorld(count:Number, isGateBatch:Boolean):Void {
        var frameFlag:Number = _root.gameworld.frameFlag;
        MercLibrary.ensureBundleLoaded(function(response:Object):Void {
            if (frameFlag != _root.gameworld.frameFlag) return;
            if (response.success) {
                MercSpawner.spawnInternal(count, isGateBatch, frameFlag);
            } else {
                _root.服务器.发布服务器消息("[生成游戏世界佣兵] 查询失败:", response.error);
            }
        });
    }

    /**
     * 帧计时器异步入队佣兵生成任务（Phase C 单步赤字驱动设计）。
     *
     * 设计要点：
     *   1. 每个 task 独立掷 70/30 gate/court — batch 内不会"全门口"或"全场景"扎堆
     *      （isGateBatch 才入 70% gate 分支，否则恒走 court）
     *   2. 每个 task 独立 pickGatePoint() — 多门场景每次随机门，单门场景靠 ±X 抖动散开
     *   3. 槽位分配错峰（slotMs=2000）— 严格防聚簇，旧 [1, 2N] 均匀随机会出生日悖论爆发
     *   4. spawnAtGate(frame 29 周期触发) 传 count=1 — 真正的单步赤字：每帧 29 触发 = 1 spawn
     *      实际密度由 frame 29 rate + MercBudget.targetAlive 共同决定，不再依赖
     *      areaFactor / 0.5 / NaN 那一套 emergent throttle
     *   5. spawnInScene(Initial 进场批量) 传 count=Initial — XML 里的 Initial 现在是
     *      "进场尝试数"，每次受 MercBudget 上限收敛
     *
     * 场景切换检测：fFlag != _root.gameworld.frameFlag 时跳过，避免新场景误刷。
     */
    public static function spawnInternal(count:Number, isGateBatch:Boolean, frameFlag:Number):Void {
        var slotMs:Number = 2000;
        if (count > _root.可雇佣兵.length) {
            count = _root.可雇佣兵.length;
        }
        var taken:Array = [];

        for (var i:Number = 0; i < count; i++) {
            var pick:Number = pickRandomMercIndex(taken);
            if (pick == -1) break;
            taken[pick] = -1;

            var delayMs:Number = i * slotMs + _root.随机整数(0, slotMs - 1);

            _root.帧计时器.添加单次任务(
                function(isGateBatch, pick, fFlag) {
                    if (fFlag != _root.gameworld.frameFlag) return;
                    // Per-task 70/30 gate/court roll：每个 task 独立掷骰，单 batch 内混合
                    var atGate:Boolean = isGateBatch && LinearCongruentialEngine.instance.successRate(70);
                    if (atGate) {
                        // gameworld.出生点列表 在 配置场景环境信息 里被注释掉了（异步时序问题），
                        // live walk 兜底；无门则 fallback court 路径，避免 undefined 坐标 spawn。
                        var gate = MercSpawner.pickGatePoint();
                        if (gate != null) {
                            // X 方向 ±100 抖动；单门场景下也散成水平线避免堆叠。
                            // Y 不动：人物应落在门口地板，垂直方向偏移会导致悬空/穿地。
                            var jitterX:Number = _root.随机整数(-100, 100);
                            MercSpawner.addGateMerc(pick, gate._x + jitterX, gate._y);
                            return;
                        }
                        if (MercBudget.telemetryEnabled) {
                            MercBudget.emit("NO_GATE", "fallback=court pick=" + pick);
                        }
                    }
                    MercSpawner.addCourtMerc(pick);
                },
                delayMs,
                isGateBatch, pick, frameFlag
            );
        }
    }

    /**
     * 周期门口刷新入口。Symbol 2396 frame 29 经 _root.门口刷可雇用玩家() 调入。
     * 每次触发 = 1 spawn 尝试（单步赤字驱动）；实际是否落地由 MercBudget.shouldSpawn 决定。
     * 几率参数已经废弃——它从来就不是这里读，而是 frame 29 自己读 _root.门口佣兵刷新器.几率
     * 做 random(几率)==0 触发频率门控；保留参数名为兼容旧调用 site。
     */
    public static function spawnAtGate(几率:Number):Void {
        spawnInWorld(1, true);
    }

    /**
     * 场景加载时的进场批量。count = XML 里的 Initial 字段（已重新诠释为"尝试数"）。
     * 每个 task 独立走 court 路径（不走门），MercBudget 自动卡在 target 上限。
     */
    public static function spawnInScene(count:Number):Void {
        spawnInWorld(count, false);
    }

    /**
     * Live walk gameworld 找门点（是否从门加载主角=true 且非"出生地"）。
     * 不缓存：场景里的 door MC 可能在脚本中动态启停；walk 成本对 ≤100 子节点忽略不计。
     * 同样模式见 MecenaryBehavior.as:280-288。
     */
    public static function pickGatePoint() {
        var gw:MovieClip = _root.gameworld;
        var doors:Array = [];
        for (var k:String in gw) {
            var mc:MovieClip = gw[k];
            if (mc.是否从门加载主角 && k != "出生地") {
                doors.push(mc);
            }
        }
        if (doors.length == 0) return null;
        return _root.随机选择数组元素(doors);
    }

    public static function randomValidPosition():Object {
        var x:Number;
        var y:Number;
        for (var i:Number = 0; i < 99; i++) {
            x = _root.随机整数(_root.Xmin, _root.Xmax);
            y = _root.随机整数(_root.Ymin, _root.Ymax);
            if (!_root.collisionLayer.hitTest(x, y, true)) {
                break;
            }
        }
        return {x: x, y: y};
    }

    /**
     * 创建佣兵数据（含杂交概率应用）。
     * 杂交分支由 hybridize 返回新副本；非杂交分支必须 deep-clone，
     * 否则下面改写 instance[2] 会污染 _root.可雇佣兵 源记录的 id（重复 spawn 同索引会拼接膨胀）。
     */
    public static function createMercData(n:Number, hybridChance:Number) {
        if (_root.isEasyMode() != true) {
            // 在竞技场之后解锁，当达到 38 时杂交率达到 25
            hybridChance = Math.min(hybridChance, Math.max(0, _root.主线任务进度 - 13));
        }
        var instance:Array;
        if (LinearCongruentialEngine.instance.successRate(hybridChance)) {
            instance = MercHybridizer.hybridize(n, hybridChance, true);
        } else {
            instance = _root.深拷贝数组(_root.可雇佣兵[n]);
        }
        if (instance == undefined || instance[1] + "" == "undefined") {
            return null;
        }
        instance[2] = instance[2].toString() + instance[1] + instance[0].toString() + _root.随机整数(0, 9999).toString();
        return instance;
    }

    public static function createMercEntity(mercData:Array, X:Number, Y:Number):MovieClip {
        if (mercData == null) {
            return null;
        }

        _root.生成佣兵计数++;
        var mercName:String = "佣兵" + mercData[1] + _root.生成佣兵计数;

        _root.加载游戏世界人物("佣兵npc", mercName, _root.gameworld.getNextHighestDepth(), {_x: X, _y: Y});
        var mc:MovieClip = _root.gameworld[mercName];

        // MC 实例字段都是公共契约（其他系统/AI/UI 直接读），保留中文
        mc.佣兵库编号 = mercData[1];
        mc.是否为敌人 = false;
        mc.脸型     = mercData[4];
        mc.发型     = mercData[5];
        mc.头部装备 = mercData[6];
        mc.上装装备 = mercData[7];
        mc.手部装备 = mercData[8];
        mc.下装装备 = mercData[9];
        mc.脚部装备 = mercData[10];
        mc.颈部装备 = mercData[11];
        mc.长枪     = mercData[12];
        mc.手枪     = mercData[13];
        mc.手枪2    = mercData[14];
        mc.刀       = mercData[15];
        mc.手雷     = mercData[16];
        mc.名字     = mercData[1];
        mc.身高     = mercData[3];
        mc.性别     = mercData[17];
        mc.等级     = mercData[0];
        mc.NPC = true;
        mc.佣兵数据 = mercData;
        // 受雇欲望为 5 的单位必定可以雇佣
        mc.受雇欲望 = 5;

        // 提前生成人格向量（幂等，初始化玩家模板中的二次调用会跳过已生成的）
        _root.配置人形怪AI(mc);

        // 按人格主维度抽对话（先人格 → 再按人格抽匹配对话）
        mc.默认对话 = [[]];
        var b:Object = MercLibrary.bundle;
        var pool:Object = b == null ? null : b.pool;
        var dialogues:Array = b == null ? null : b.dialogues;

        if (pool != null && mc.personality != null) {
            var personality:Object = mc.personality;
            // 维度名是 personality 的字段名（外部契约），保留中文
            var dims:Array = ["勇气", "技术", "经验", "反应", "智力", "谋略"];
            // 按人格值降序排列 → 前 2 个为主要维度
            dims.sort(function(x, y) {
                return (personality[y] > personality[x]) ? 1 : ((personality[y] < personality[x]) ? -1 : 0);
            });

            var di:Number = 0;
            // 第一主维度：抽 2 条
            var p1:Array = pool[dims[0]];
            if (p1 != null && p1.length > 0) {
                for (var i:Number = 0; i < 2; i++) {
                    var d1:Object = p1[_root.获取随机索引(p1)];
                    mc.默认对话[0][di++] = [mercData[1], "佣兵", "主角模板",
                        d1.Text + "   (" + d1.Personality + ":" + d1.Value + ")",
                        d1.Expression, mc];
                }
            }
            // 第二主维度：抽 1 条
            var p2:Array = pool[dims[1]];
            if (p2 != null && p2.length > 0) {
                var d2:Object = p2[_root.获取随机索引(p2)];
                mc.默认对话[0][di++] = [mercData[1], "佣兵", "主角模板",
                    d2.Text + "   (" + d2.Personality + ":" + d2.Value + ")",
                    d2.Expression, mc];
            }
            // 随机池补充 0-2 条
            var fillCount:Number = _root.随机整数(0, 2);
            for (var j:Number = 0; j < fillCount; j++) {
                var dr:Object = dialogues[_root.获取随机索引(dialogues)];
                mc.默认对话[0][di++] = [mercData[1], "佣兵", "主角模板",
                    dr.Text + "   (" + dr.Personality + ":" + dr.Value + ")",
                    dr.Expression, mc];
            }
        } else if (dialogues != null) {
            // Fallback: bundle.pool 未就绪时走原始随机逻辑
            var n:Number = _root.随机整数(1, 5);
            for (var k:Number = 0; k < n; ++k) {
                var d:Object = dialogues[_root.获取随机索引(dialogues)];
                var text:String = d.Text + "   (" + d.Personality + ":" + d.Value + ")";
                mc.默认对话[0][k] = [mercData[1], "佣兵", "主角模板", text, d.Expression, mc];
            }
        }

        mc.方向 = (_root.随机整数(0, 1) == 0) ? "左" : "右";

        // 生命周期遥测：onUnload 触发于 HIRE（Symbol 2035 removeMovieClip）、DEATH、场景切换。
        // 钩子注册受 telemetryEnabled gate：默认关时不占 EventCoordinator 槽，零开销。
        // 后续打开 telemetry 时新 spawn 才有 DESPAWN，旧 mc 不补；ad-hoc debug 可接受。
        if (MercBudget.telemetryEnabled) {
            EventCoordinator.addUnloadCallback(mc, function() {
                MercBudget.emit("DESPAWN", "id=" + mc.佣兵库编号 + " alive_after=" + (MercCensus.countAlive() - 1));
            });
        }

        return mc;
    }

    public static function addGateMerc(n:Number, X:Number, Y:Number):Void {
        // MercBudget 赤字门控：每个调度任务 fire 时复查，避免一批任务 schedule 时 OK
        // 但 fire 时已超 cap 的过冲。kill switch (MercBudget.enabled=false) 直接放行。
        if (!MercBudget.shouldSpawn()) return;
        var data:Array = createMercData(n, _root.杂交佣兵几率);
        var mc:MovieClip = createMercEntity(data, X, Y);
        if (mc != null && MercBudget.telemetryEnabled) {
            MercBudget.emit("SPAWN", "id=" + mc.佣兵库编号 + " atGate=true alive_after=" + MercCensus.countAlive());
        }
    }

    public static function addCourtMerc(n:Number):Void {
        if (!MercBudget.shouldSpawn()) return;
        var data:Array = createMercData(n, _root.杂交佣兵几率);
        var pos:Object = randomValidPosition();
        var mc:MovieClip = createMercEntity(data, pos.x, pos.y);
        if (mc != null && MercBudget.telemetryEnabled) {
            MercBudget.emit("SPAWN", "id=" + mc.佣兵库编号 + " atGate=false alive_after=" + MercCensus.countAlive());
        }
    }
}
