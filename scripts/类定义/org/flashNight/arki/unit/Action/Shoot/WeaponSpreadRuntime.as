/** 玩家枪械近期射击密度。仅角色运行态持有实际物件引用，不写物品/存档。 */
class org.flashNight.arki.unit.Action.Shoot.WeaponSpreadRuntime {
    private static var WINDOW_MS:Number = 500;
    private static var _bus:Object;
    private static var _clock:Number = 0;
    private static var _lastFrame:Number;
    private static var _epoch:Number = 0;

    // 普通枪弹与三种纵向枪式模板。横向霰弹、拖尾、导弹、弓箭、喷火/技能不借共享工厂加入。
    private static var GUN_UNITS:Object = {
        普通子弹:true, 加强普通子弹:true, 精制普通子弹:true,
        普通无壳子弹:true, 无壳子弹:true, 穿刺子弹:true,
        次级穿刺子弹:true, 无壳穿刺子弹:true, 蓝紫穿刺子弹:true,
        反器材普通子弹:true, 山猫反器材普通子弹:true, 巴雷特子弹:true,
        能量普通子弹:true, 绿色能量普通子弹:true, 巨型穿刺能量子弹:true,
        铁枪能量子弹:true, 铁枪磁轨弹:true, 红色针弹:true,
        普通麻醉子弹:true, 等离子穿刺子弹:true, 高温自锐针弹:true,
        烈焰普通子弹:true, 冰冷子弹:true
    };

    private static function allows(owner:Object, slot:String, props:Object):Boolean {
        if (owner._name !== _root.控制目标 || _root.gameworld[owner._name] !== owner) return false;
        if (slot != "长枪" && slot != "手枪" && slot != "手枪2") return false;
        var category:String = owner[slot + "数据"].weapontype;
        if (category == "近战" || category == "压制近战" || category == "弓弩" || category == "发射器") return false;
        var type:String = props.子弹种类;
        if (GUN_UNITS[type]) return true;
        var separator:Number = type.indexOf("-");
        if (separator < 0) return false;
        var prefix:String = type.substr(0, separator);
        return (prefix == "纵向联弹" || prefix == "纵向机枪联弹" || prefix == "纵向手枪联弹")
            && GUN_UNITS[type.substr(separator + 1)] == true;
    }

    /** 一个全局帧订阅；暂停帧不增长，未开火时无需遍历角色/武器。 */
    private static function bindClock():Boolean {
        var bus:Object = _root.帧计时器.eventBus;
        if (!bus) return false;
        if (_bus !== bus) {
            if (_bus) _bus.unsubscribe("frameUpdate", onFrame);
            _bus = bus;
            _clock = 0;
            _lastFrame = undefined;
            _epoch++;
            if (!_bus.subscribe("frameUpdate", onFrame)) { _bus = null; return false; }
        }
        return true;
    }

    private static function onFrame(frame:Number):Void {
        if (isNaN(frame) || frame === _lastFrame) return;
        _lastFrame = frame;
        if (!_root.暂停) _clock++;
    }

    /** 包含本次提交。环形队列按帧合桶，连续射击和同帧多次提交均保持有界空间。 */
    private static function record(owner:Object, weapon:Object, windowFrames:Number):Number {
        var states:Array = owner.__weaponSpreadStates;
        if (!states) states = owner.__weaponSpreadStates = [];
        var cutoff:Number = _clock - windowFrames;
        var state:Object;
        for (var i:Number = 0; i < states.length;) {
            var candidate:Object = states[i];
            if (candidate.epoch != _epoch || candidate.lastTick <= cutoff
                    || candidate.size != windowFrames) {
                states[i] = states[states.length - 1];
                states.length--;
                continue;
            }
            // BaseItem 包装可以重建；同一个 value 引用仍是同一实际武器。相同型号不同物件不合并。
            if (candidate.weapon === weapon || candidate.value === weapon.value) state = candidate;
            i++;
        }
        if (!state) {
            state = {weapon:weapon, value:weapon.value, epoch:_epoch, size:windowFrames,
                ticks:new Array(windowFrames), counts:new Array(windowFrames),
                head:0, buckets:0, total:0, lastTick:_clock};
            states[states.length] = state;
        }
        var ticks:Array = state.ticks;
        var counts:Array = state.counts;
        var head:Number = state.head;
        var buckets:Number = state.buckets;
        var total:Number = state.total;
        while (buckets > 0 && ticks[head] <= cutoff) {
            total -= counts[head];
            head = (head + 1) % windowFrames;
            buckets--;
        }
        var tail:Number = (head + buckets - 1 + windowFrames) % windowFrames;
        if (buckets > 0 && ticks[tail] == _clock) counts[tail]++;
        else {
            tail = (head + buckets) % windowFrames;
            ticks[tail] = _clock;
            counts[tail] = 1;
            buckets++;
        }
        state.head = head;
        state.buckets = buckets;
        state.total = total + 1;
        state.lastTick = _clock;
        return state.total;
    }

    /** 在 processShot 选定原始散射后调用，只写本发角度倍率；射速戳须属于本次提交。 */
    public static function applyShot(owner:Object, slot:String, weapon:Object, props:Object):Number {
        props.武器扩散倍率 = 1;
        if (_root.暂停 || !weapon || typeof weapon.value != "object"
                || isNaN(props.子弹威力) || !allows(owner, slot, props)) return 1;
        var frameMs:Number = org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I().每帧毫秒;
        var interval:Number = props.发射间隔毫秒;
        if (!(frameMs > 0) || !isFinite(frameMs) || !(interval > 0) || !isFinite(interval)
                || !bindClock()) return 1;
        var windowFrames:Number = Math.ceil(WINDOW_MS / frameMs);
        var intervalFrames:Number = Math.ceil(interval / frameMs);
        if (windowFrames < 1) windowFrames = 1;
        if (intervalFrames < 1) intervalFrames = 1;
        var count:Number = record(owner, weapon, windowFrames);
        var density:Number = count * intervalFrames / windowFrames;
        if (density > 1) density = 1;
        var multiplier:Number = 0.5 + 0.5 * density;
        var base:Number = props.站立子弹散射度;
        var original:Number = props.子弹散射度;
        // 移动额外散布照旧：新半径=基础*m+原移动惩罚，但继续用原整数半径抽样。
        if (base > 0 && original > 0 && isFinite(base) && isFinite(original)) {
            if (base > original) base = original;
            props.武器扩散倍率 = 1 - base * (1 - multiplier) / original;
        }
        return multiplier;
    }
}
