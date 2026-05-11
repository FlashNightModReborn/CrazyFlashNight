import org.flashNight.arki.merc.*;

/*
 * MercBudget：佣兵驻留预算（B 阶段最小骨架）。
 *
 * 当前职责：根据地图面积 + 地图倍率算 targetAlive，提供 shouldSpawn() 给
 * MercSpawner 做赤字门控。**与现有 spawn 链并行**，不替换 areaFactor / 0.5 / NaN
 * 链路（那是 C 阶段的事）。
 *
 * 暂不接 PerformanceActuator 的 softU——baseDensityPxPerMerc 是常量。
 * D 阶段（独立项目）把 _root.面积系数 切到这里时，再让 baseDensity 跟 softU 联动。
 *
 * Kill switch：MercBudget.enabled = false 立即恢复旧路径行为（shouldSpawn 始终 true）。
 *
 * baseDensityPxPerMerc=1000000 的标定推导：
 *   典型非战斗地图 ~4M px²，希望驻留 ~4 个可雇佣兵
 *   （玩家 + 5 已雇 = 6，frame 29 cap=10 留 4 个槽位）
 *   → 4M / 4 = 1M px²/merc 起步。后续按 MercCensus.dump() 真值修。
 *
 * gw.面积系数（地图 multiplier，从 XML AreaMultiplier 读）语义保留：
 *   值越大 → target 越大 → 该地图越密。跟旧 spawnInternal 里 *= gw.面积系数 同向。
 */
class org.flashNight.arki.merc.MercBudget {

    public static var enabled:Boolean = true;

    /**
     * 量化标定开关。开启后核心路径（PASS/DENY/SPAWN/DISMISS/DESPAWN/LOAD/NO_GATE）
     * 走 _root.服务器.发布服务器消息 输出可批量 grep/awk 的单行日志。
     *
     * 默认 false（标定已完成 2026-05-11）：onUnload 注册、emit 调用全部短路；
     * 后续如需再次 debug，游戏内 _root.佣兵遥测(true) 即可临时打开。
     */
    public static var telemetryEnabled:Boolean = false;

    /**
     * 平方根密度模型的尺度参数：target = round(sqrt(area * mapMult / densityScale))。
     *
     * 历史教训：早期版本用 area*mult / baseDensity 线性模型，baseDensity=1M。
     * 结果室内场景（13万-50万 px²）全部落到 target=1 兜底，而户外（数 M）线性
     * 暴涨到几十个，无法用单一参数兼顾两端尺度。
     *
     * sqrt 模型把两端压缩到合理范围（实测 indoor 3-5 / outdoor 10-17）。
     * mapMult 参与 sqrt 内部，设计师 mult ×2 只会给 √2 倍 target，避免引爆。
     *
     * 实测推荐值 densityScale = 20000；调小变密，调大变稀。
     */
    public static var densityScale:Number = 20000;

    public static function targetAlive():Number {
        var area:Number = (_root.Xmax - _root.Xmin) * (_root.Ymax - _root.Ymin);
        var mapMult:Number = isNaN(_root.gameworld.面积系数) ? 1 : _root.gameworld.面积系数;
        var target:Number = Math.round(Math.sqrt(area * mapMult / densityScale));
        if (target < 1) target = 1;
        return target;
    }

    public static function shouldSpawn():Boolean {
        // 快路径：kill switch 关 + 遥测关 → 不走 census walk
        if (!enabled && !telemetryEnabled) return true;
        var alive:Number = MercCensus.countAlive();
        var target:Number = targetAlive();
        var pass:Boolean = (!enabled) || (alive < target);
        if (telemetryEnabled) {
            var ev:String = (!enabled) ? "BYPASS" : (pass ? "PASS" : "DENY");
            emit(ev, "alive=" + alive + " target=" + target);
        }
        return pass;
    }

    /**
     * 统一日志出口。格式："[佣兵预算] EVENT scene=NAME k1=v1 k2=v2 ..."。
     * 对 _root.服务器 缺失做防御（启动早期某些路径可能未初始化）。
     */
    public static function emit(event:String, payload:String):Void {
        if (!telemetryEnabled) return;
        if (_root.服务器 == undefined) return;
        // 场景名优先级：gameworld.场景名（attachMovie 时注入，覆盖全部场景）
        //              > _root.当前关卡名（仅 stage 类场景设置）
        var scene:String;
        if (_root.gameworld != undefined && _root.gameworld.场景名 != undefined) {
            scene = _root.gameworld.场景名;
        } else if (_root.当前关卡名 != undefined) {
            scene = _root.当前关卡名;
        } else {
            scene = "?";
        }
        _root.服务器.发布服务器消息("[佣兵预算] " + event + " scene=" + scene + " " + payload);
    }

    /**
     * 场景加载一次性快照。在 关卡系统_lsy_add2map_加载背景.as 末尾调用，
     * 记录 area/mult/target，让标定能按场景定量。
     */
    public static function emitLoad():Void {
        if (!telemetryEnabled) return;
        var area:Number = (_root.Xmax - _root.Xmin) * (_root.Ymax - _root.Ymin);
        var mapMult:Number = isNaN(_root.gameworld.面积系数) ? 1 : _root.gameworld.面积系数;
        var target:Number = targetAlive();
        emit("LOAD", "area=" + area + " mapMult=" + mapMult + " target=" + target);
    }
}
