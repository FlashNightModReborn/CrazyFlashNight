import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;

class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.ShotTimelineTest {
    private static var passed:Number;
    private static var failed:Number;

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] ShotTimelineTest: " + message); }
    }

    private static function animation():Object {
        var result:Object = {_totalframes:8, _currentFrame:1, writes:0};
        result.gotoAndStop = function(frame:Number):Void {
            this._currentFrame = frame;
            this.writes++;
        };
        return result;
    }

    private static function actor():Object {
        var result:Object = {version:1, 攻击模式:"长枪", syncRefs:{},
            长枪:{name:"测试后坐枪", value:{shot:0}}, 长枪弹匣容量:60,
            长枪属性:{interval:240}, dispatcher:new EventDispatcher()};
        result.长枪_引用 = {_parent:result, 动画:animation()};
        return result;
    }

    private static function tick(ref:Object, frame:Number):Void {
        _root.帧计时器.当前帧数 = frame;
        _root.装备生命周期函数.长枪射击动画周期(ref);
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var oldClock:Object = _root.帧计时器;
        var oldCleanup:Function = _root.装备生命周期函数.移除异常周期函数;
        var oldShoot:Function = _root.子弹区域shoot传递;
        var unit:Object = actor();
        var ref:Object = {自机:unit, 装备类型:"长枪", 生命周期函数列表:[]};
        var init:Function = _root.装备生命周期函数.长枪射击动画初始化;
        var visual:Function = _root.装备生命周期函数.长枪射击动画视觉更新;
        var unload:Function = _root.装备生命周期函数.长枪射击动画卸载;
        _root.帧计时器 = {当前帧数:0};
        _root.装备生命周期函数.移除异常周期函数 = function(value:Object):Void {};
        var submitted:Number = 0;
        _root.子弹区域shoot传递 = function(props:Object):Void { submitted++; };
        try {
            check(init(ref, {fireStart:2, fireEnd:8}), "初始化成功");
            check(ref.生命周期函数列表.length == 1 && unit.dispatcher["_subCount"] == 2,
                "射击及 placement 共用一份卸载资源");
            tick(ref, 1); tick(ref, 2);
            check(unit.长枪_引用.动画._currentFrame == 1, "无射击保持待机");
            unit.dispatcher.publish("processShot", unit, "长枪副武器", null, {});
            unit.dispatcher.publish("processShot", {}, "长枪", null, {});
            check(ref.animationFrame == 1, "排除副武器及错误 owner");
            unit.攻击模式 = "手枪";
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            check(ref.animationFrame == 1, "非长枪姿态不触发");
            unit.攻击模式 = "长枪";

            tick(ref, 10);
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            check(unit.长枪_引用.动画._currentFrame == 2, "射击同步写击发帧");
            tick(ref, 10);
            check(ref.animationFrame == 2, "射击同 tick 不提前推进");
            tick(ref, 11); tick(ref, 11);
            check(ref.animationFrame == 3, "每个游戏帧只推进一次");
            unit.dispatcher.publish("长枪_引用");
            check(ref.animationFrame == 3, "placement 不推进逻辑时钟");
            tick(ref, 15);
            check(ref.animationFrame == 7, "帧时钟跳跃使用真实经过帧数");
            tick(ref, 16);
            check(ref.animationFrame == 8, "展示回位末帧");
            tick(ref, 17);
            check(ref.animationFrame == 1 && ref.animationStartTick == -1, "单发结束回待机");

            tick(ref, 20);
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            tick(ref, 21);
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            check(ref.animationFrame == 2 && ref.animationStartTick == 21, "连发重新对齐最新击发，不忽略新射击");
            tick(ref, 22);
            var oldAnimation:Object = unit.长枪_引用.动画;
            var oldWrites:Number = oldAnimation.writes;
            unit.长枪_引用 = {_parent:unit, 动画:animation()};
            unit.dispatcher.publish("长枪_引用");
            check(unit.长枪_引用.动画._currentFrame == 3 && ref.animationFrame == 3,
                "新 holder 同步既有状态");
            check(oldAnimation.writes == oldWrites, "不再写旧 MovieClip");
            unit.长枪_引用._parent = null;
            oldWrites = unit.长枪_引用.动画.writes;
            tick(ref, 23);
            check(unit.长枪_引用.动画.writes == oldWrites, "stale holder 窗口跳过视觉写入");
            unit.长枪_引用._parent = unit;
            unit.dispatcher.publish("长枪_引用");
            check(unit.长枪_引用.动画._currentFrame == 4, "placement 恢复不丢失经过帧数");

            unit.攻击模式 = "手枪";
            visual(ref);
            check(unit.长枪_引用.动画._currentFrame == 1 && ref.animationFrame == 4,
                "姿态切换的视觉回调只写画面");
            tick(ref, 24);
            check(ref.animationFrame == 1 && ref.animationStartTick == -1, "非长枪周期清除未完动作");
            unit.攻击模式 = "长枪"; tick(ref, 25);
            check(ref.animationFrame == 1, "重新持枪不会续播旧动作");

            unit.长枪.value.shot = 60;
            var props:Object = {shootX:101, shootY:202, 子弹威力:888};
            check(!WeaponFireCore.executeShot(unit, "长枪", null, props), "真实射击核心拒绝空弹匣");
            check(ref.animationFrame == 1 && submitted == 0, "空弹匣不触发动画或子弹提交");
            unit.长枪.value.shot = 0;
            var guard:Function = function(owner:Object, type:String, bullet:Object):Boolean { return false; };
            check(!WeaponFireCore.executeShot(unit, "长枪", null, props, guard), "真实射击核心拒绝失败 commit guard");
            check(ref.animationFrame == 1 && submitted == 0, "失败提交没有视觉副作用");
            check(WeaponFireCore.executeShot(unit, "长枪", null, props), "真实成功发射进入 processShot");
            check(ref.animationFrame == 2 && submitted == 1, "成功射击同时触发动画和一次子弹提交");
            check(props.shootX == 101 && props.shootY == 202 && props.子弹威力 == 888,
                "视觉驱动不改弹道起点或威力");

            unload(ref); unload(ref);
            check(!ref.animationActive && unit.dispatcher["_subCount"] == 0, "卸载幂等且精确退订");
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            check(ref.animationFrame == 1, "卸载后旧事件失效");
            init(ref, {fireStart:2, fireEnd:8}); init(ref, {fireStart:2, fireEnd:8});
            check(unit.dispatcher["_subCount"] == 2 && ref.生命周期函数列表.length == 1,
                "防御性初始化不累积订阅或卸载条目");
            unit.version++;
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            check(ref.animationFrame == 1, "版本失配的旧回调不可启动动画");
            tick(ref, 30);
            check(unit.dispatcher["_subCount"] == 0, "失配周期清理旧订阅");
            init(ref, {fireStart:2, fireEnd:8});
            unit.长枪 = {name:"另一把枪", value:{shot:0}};
            unit.长枪_引用.动画._currentFrame = 6;
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            tick(ref, 31);
            check(unit.长枪_引用.动画._currentFrame == 6 && unit.dispatcher["_subCount"] == 0,
                "换装不会由旧 ref 复位新武器");

            unit.长枪_引用 = undefined;
            init(ref, {fireStart:2, fireEnd:8});
            tick(ref, 40);
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            tick(ref, 42);
            unit.长枪_引用 = {_parent:unit, 动画:animation()};
            unit.dispatcher.publish("长枪_引用");
            check(unit.长枪_引用.动画._currentFrame == 4, "引用晚到时补写当前动画姿态");
            tick(ref, 39);
            check(ref.animationFrame == 1, "帧计数回退安全回待机");
            check(!init(ref, {fireStart:8, fireEnd:2}) && unit.dispatcher["_subCount"] == 0,
                "非法帧范围不会安装订阅");
            unit.长枪_引用 = animation(); unit.长枪_引用._parent = unit;
            init(ref, {fireStart:2, fireEnd:8, animationTarget:""});
            unit.dispatcher.publish("processShot", unit, "长枪", null, {});
            check(unit.长枪_引用._currentFrame == 2, "支持直接控制外层时间轴");
            unload(ref);
        } catch (error) {
            check(false, "意外异常 " + error);
        } finally {
            unload(ref);
            unit.dispatcher.destroy();
            _root.帧计时器 = oldClock;
            _root.装备生命周期函数.移除异常周期函数 = oldCleanup;
            _root.子弹区域shoot传递 = oldShoot;
        }
        trace("ShotTimelineTest Tests Passed: " + passed);
        trace("ShotTimelineTest Tests Failed: " + failed);
    }
}
