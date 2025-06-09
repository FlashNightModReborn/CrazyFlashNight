import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.装备生命周期函数.镜之虎彻初始化 = function(reflector:Object, paramObj:Object) {
    reflector.lastTime = 0;
    reflector.precent = Number(paramObj.precent) || 2;
    reflector.duration = Number(paramObj.duration) || 0.25;
    reflector.basicRate = Number(paramObj.basicRate) || 5;
    reflector.speed = Number(paramObj.speed) || 360;
    reflector.borderLength = Number(paramObj.borderLength) || 180;
    reflector.damageRate = Number(paramObj.damageRate) || 40;
    reflector.bulletrename = reflector.bulletrename || "镜闪";
};

_root.装备生命周期函数.镜之虎彻周期 = function(reflector:Object, paramObj:Object) {
    _root.装备生命周期函数.移除异常周期函数(reflector);

    var timeFlag:Boolean = true;
    var duration:Number = reflector.duration * 1000;
    var target:MovieClip = reflector.自机;
    var time:Number = getTimer();
    // _root.发布消息(target._x, _root.Xmin, _root.Xmax)

    if(time - reflector.lastTime > duration)
    {
        reflector.lastTime = time;
    }
    else
    {
        timeFlag = false;
    }
    if(timeFlag && _root.兵器攻击检测(target))
    {
        var flag:Boolean = true;
        switch(target.getSmallState())
        {
            case "兵器二段中":
            case "兵器三段中":
            case "兵器四段中":
            case "兵器五段中":
                flag = true;
            break;
            default:
                flag = _root.成功率(reflector.basicRate);
        }
        if(flag)
        {
            _root.镜闪变亮(duration / 2,target);		

            

            var distance:Number = Math.min(target._x - _root.Xmin, _root.Xmax - target._x)
            var atksp:Number = Math.max(0, Math.min(reflector.speed,distance));
            // _root.发布消息(distance, atksp)
            if(((target.方向 == "左") && target._x > _root.Xmin + reflector.borderLength) ||
               ((target.方向 == "右") && target._x < _root.Xmax - reflector.borderLength) ) {

                target.man.攻击时移动(0, atksp);
                target.man.攻击时可改变移动方向(1);
                Mover.enforceScreenBounds(target);
            }

            var mpCount:Number = Math.floor(target.mp满血值 / 100 * reflector.precent);
            if(target.mp >= mpCount)
            {
                target.mp -= mpCount;
                var myPoint = {x:this._x,y:this._y};
                _parent.localToGlobal(myPoint);
                _root.gameworld.globalToLocal(myPoint);
                声音 = "";
                霰弹值 = 1;
                子弹散射度 = 0;
                发射效果 = "";
                子弹种类 = reflector.bulletrename;
                子弹威力 = mpCount * reflector.damageRate;
                子弹速度 = 0;
                击中地图效果 = "";
                Z轴攻击范围 = 150;
                击倒率 = 100;
                击中后子弹的效果 = "";
                发射者名 = target._name;
                shootX = myPoint.x;
                Z轴坐标 = shootY = target._y;
                _root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,null,击倒率,击中后子弹的效果);
            }
            else if(target == TargetCacheManager.findHero())
            {
                _root.发布消息("气力不足，难以发挥武器的真正力量……");
            }
        }
    }
};
