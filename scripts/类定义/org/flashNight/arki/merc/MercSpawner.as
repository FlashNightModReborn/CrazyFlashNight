import org.flashNight.arki.merc.*;

/*
 * 场景佣兵刷新链。
 *
 * Step 5 改动：
 *   - 干掉 _mercDataRefCount + cleanup 闭包：bundle 由 MercLibrary 缓存，session 级
 *     不主动失效。spawn 不再 null _root 状态。
 *   - 干掉 _root.战队信息数组 / 随机名称库 / 佣兵随机对话 / 佣兵对话池 的写入。
 *     Hybridizer / createMercEntity 直接读 MercLibrary.bundle.X。
 *   - hybridize 返回值：createMercData 接收返回值用作单元素临时库，
 *     不再写 _root.随机可雇佣兵。
 *
 * mercData 数组列约定（与 MercHybridizer 共享）：
 *   [0] 等级  [1] 名字  [2] id  [3] 身高  [4] 脸型  [5] 发型
 *   [6..16] 装备  [17] 性别  [18] 价格  [19] 元数据
 *
 * Emergent throttle 文档（保留）：
 *   外层 frame 29 (Symbol 2396): random(几率)==0 控制触发频率（XML <Entrance>）
 *   内层 spawnAtGate: 几率为 undefined 时强制 1 个佣兵（重要兜底节流）
 *   数量门控 frame 29: 场上 ≥10 不刷
 * 不要单独"修"内层 spawnAtGate 的几率参数行为；redesign 留待 schema 扩展
 * <Entrance>/<EntranceDensity> 解耦 + frame 29 改成 _root.门口刷可雇用玩家(几率)
 * 时一并设计。
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
        if (meta && meta.是否杂交 == false) {
            _root.可雇佣兵.push(_root.同伴数据[idx]);
        }
        if (meta && meta.隐藏) {
            _root.隐藏的可雇佣兵.push(_root.同伴数据[idx]);
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
    }

    public static function initIndexCache():Void {
        var gw:MovieClip = _root.gameworld;
        if (gw.佣兵编号缓存 == undefined) {
            // 内部字段命名英文化（私有缓存，仅本类读写）
            gw.佣兵编号缓存 = {weights: [], totalWeight: 0, ready: false};
            _global.ASSetPropFlags(gw, ["佣兵编号缓存"], 1, false);
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

    public static function spawnInWorld(addFn:Function, chance:Number, atGate:Boolean):Void {
        var frameFlag:Number = _root.gameworld.frameFlag;
        MercLibrary.ensureBundleLoaded(function(response:Object):Void {
            if (frameFlag != _root.gameworld.frameFlag) return;
            if (response.success) {
                MercSpawner.spawnInternal(addFn, chance, atGate, frameFlag);
            } else {
                _root.服务器.发布服务器消息("[生成游戏世界佣兵] 查询失败:", response.error);
            }
        });
    }

    /**
     * 帧计时器异步入队佣兵生成任务。
     *
     * 场景切换检测：fFlag != _root.gameworld.frameFlag 时跳过，避免在新场景中
     * 错误生成。bundle 数据由 MercLibrary 持有，不再需要 refcount 同步。
     */
    public static function spawnInternal(addFn:Function, chance:Number, atGate:Boolean, frameFlag:Number):Void {
        var gw:MovieClip = _root.gameworld;
        var totalCount:Number = _root.成功率(100 / chance) ? _root.随机整数(1, 3) : 0.5;
        var areaFactor:Number = (_root.Xmax - _root.Xmin) * (_root.Ymax - _root.Ymin) / _root.面积系数;
        if (!isNaN(gw.面积系数)) areaFactor *= gw.面积系数;
        totalCount = Math.floor(Math.max(totalCount * areaFactor, 1));
        if (totalCount > _root.可雇佣兵.length) {
            totalCount = _root.可雇佣兵.length;
        }

        var taken:Array = [];

        for (var i:Number = 0; i < totalCount; i++) {
            var pick:Number = pickRandomMercIndex(taken);
            if (pick == -1) break;

            _root.帧计时器.添加单次任务(
                function(atGate, pick, addFn, fFlag) {
                    if (fFlag != _root.gameworld.frameFlag) return;
                    if (atGate) {
                        var gate = _root.随机选择数组元素(_root.gameworld.出生点列表);
                        addFn(pick, gate._x, gate._y);
                    } else {
                        addFn(pick);
                    }
                },
                _root.随机整数(1, totalCount * 2) * 1000,
                atGate, pick, addFn, frameFlag
            );

            taken[pick] = -1;
        }
    }

    // === 不要单独"修"这个函数 ===
    // 历史链路：MC 实例属性 _root.门口佣兵刷新器.几率 由场景 XML <Entrance> 注入
    // （见 关卡系统_lsy_add2map_加载背景.as），用作 Symbol 2396 frame 29 的
    // random(几率)==0 触发频率门控；frame 29 调本函数时未传参，本函数体内
    // 历史误字"机率"裸标识符 → undefined → 100/几率=NaN → Math.max(...,1)
    // 兜底强制 1 个佣兵。
    //
    // 实际节流结构（buggy 行为已成 emergent design）:
    //   外层(设计): frame 29 random(几率)==0  → 按 Entrance 控制触发频率
    //   内层(兜底): 函数体几率=undefined      → 强制每次 1 个（关键节流）
    //   数量门控:   frame 29 i < 10            → 场上 ≥10 不刷
    //
    // 若把 frame 29 改成 _root.门口刷可雇用玩家(几率) 让内层"恢复设计意图"，
    // 内层会从"强制 1 个"放宽到"_root.成功率(100/几率) ? 1-3 : 兜底 1"，
    // 整体期望刷出量约 +14%（Entrance=7 时）。运营反馈是当前已偏多，故
    // 暂不修，留到 schema 扩展 <Entrance>/<EntranceDensity> 解耦时一并设计。
    //
    // 形参保留中文"几率"是为了让上述注释中的"几率/机率"对照保持锚点；其他方法用 chance。
    public static function spawnAtGate(几率:Number):Void {
        if (_root.成功率(30)) {
            spawnInWorld(_root.添加场上佣兵, 几率, false);
        } else {
            spawnInWorld(_root.添加场上佣兵, 几率, true);
        }
    }

    public static function spawnInScene(chance:Number):Void {
        spawnInWorld(_root.添加场上佣兵, chance, false);
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
     * Step 5: hybridize 返回值改造后，杂交结果是临时单元素数组，不再写 _root.随机可雇佣兵。
     */
    public static function createMercData(n:Number, hybridChance:Number) {
        var lib:Array = _root.可雇佣兵;
        if (_root.isEasyMode() != true) {
            // 在竞技场之后解锁，当达到 38 时杂交率达到 25
            hybridChance = Math.min(hybridChance, Math.max(0, _root.主线任务进度 - 13));
        }
        if (_root.成功率(hybridChance)) {
            // hybridize 返回杂交后的副本；用作"单元素临时库"
            lib = [MercHybridizer.hybridize(n, hybridChance, true)];
            n = 0;
        }
        lib[n][2] = lib[n][2].toString() + lib[n][1] + lib[n][0].toString() + _root.随机整数(0, 9999).toString();

        if (lib[n] == undefined || lib[n][1] + "" == "undefined") {
            return null;
        }
        return lib[n];
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

        return mc;
    }

    public static function addGateMerc(n:Number, X:Number, Y:Number):Void {
        var data:Array = createMercData(n, _root.杂交佣兵几率);
        createMercEntity(data, X, Y);
    }

    public static function addCourtMerc(n:Number):Void {
        var data:Array = createMercData(n, _root.杂交佣兵几率);
        var pos:Object = randomValidPosition();
        createMercEntity(data, pos.x, pos.y);
    }
}
