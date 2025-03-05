import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.bullet.BulletComponent.Attributes.*
import org.flashNight.arki.bullet.BulletComponent.Init.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.aven.Proxy.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.Factory.BulletFactory

DamageManagerFactory.init();
//重写子弹生成逻辑
_root.子弹生成计数 = 0;

//加入新参数水平击退速度和垂直击退速度。未填写的话默认分别为10和5（和子弹区域shoot一致），最大击退速度可以调节下方常数（目前为33）。
//额外添加了命中率,固伤,百分比伤害，血量上限击溃，防御粉碎，命中率未输入则寻找发射者的命中，固伤与百分比未输入默认为0
_root.最大水平击退速度 = 33;
_root.最大垂直击退速度 = 15;

_root.子弹区域shoot = function(声音, 霰弹值, 子弹散射度, 发射效果, 子弹种类, 子弹威力, 子弹速度, Z轴攻击范围, 击中地图效果, 发射者, shootX, shootY, shootZ, 子弹敌我属性, 击倒率, 击中后子弹的效果, 水平击退速度, 垂直击退速度, 命中率, 固伤, 百分比伤害, 血量上限击溃, 防御粉碎, 区域定位area, 吸血, 毒, 最小霰弹值, 不硬直, 伤害类型, 魔法伤害属性, 速度X, 速度Y, ZY比例, 斩杀, 暴击, 水平击退反向, 角度偏移)
{
	var 子弹属性 = {
		声音:声音,
		霰弹值:霰弹值,
		子弹散射度:子弹散射度,
		发射效果:发射效果,
		子弹种类:子弹种类,
		子弹威力:子弹威力,
		子弹速度:子弹速度,
		Z轴攻击范围:Z轴攻击范围,
		击中地图效果:击中地图效果,
		发射者:发射者,
		shootX:shootX,
		shootY:shootY,
		shootZ:shootZ,
		子弹敌我属性:子弹敌我属性,
		击倒率:击倒率,
		击中后子弹的效果:击中后子弹的效果,
		水平击退速度:水平击退速度,
		垂直击退速度:垂直击退速度,
		命中率:命中率,
		固伤:固伤,
		百分比伤害:百分比伤害,
		血量上限击溃:血量上限击溃,
		防御粉碎:防御粉碎,
		区域定位area:区域定位area,
		吸血:吸血,
		毒:毒,
		最小霰弹值:最小霰弹值,
		不硬直:不硬直,
		伤害类型:伤害类型,
		魔法伤害属性:魔法伤害属性,
		速度X:速度X,
		速度Y:速度Y,
		ZY比例:ZY比例,
		斩杀:斩杀,
		暴击:暴击,
		水平击退反向:水平击退反向,
		角度偏移:角度偏移
	};
	_root.子弹区域shoot传递(子弹属性);
}

_root.子弹区域shoot传递 = function(Obj){
    //暂停判定

    if (_root.暂停 || isNaN(Obj.子弹威力)) return;

    var gameWorld:MovieClip = _root.gameworld;
    var shooter:MovieClip = gameWorld[Obj.发射者];

    // 计算射击角度
    var 射击角度:Number = 计算射击角度(Obj, shooter);

    // 创建发射效果和音效
    var shootX:Number = Obj.shootX;
    var shootY:Number = Obj.shootY;
    var xscale:Number = shooter._xscale;
    var effect:MovieClip = _root.效果(Obj.发射效果, shootX, shootY, xscale);
    if(effect) effect._rotation = Obj.角度偏移;
    ShellSystem.launchShell(Obj.子弹种类, shootX, shootY, xscale);
    _root.播放音效(Obj.声音);

    // 设置子弹类型标志
    BulletTypesetter.setTypeFlags(Obj);

    // 1. 设置默认值
    BulletInitializer.setDefaults(Obj, shooter);

    // 2. 继承发射者属性
    BulletInitializer.inheritShooterAttributes(Obj, shooter);

    // 3. 计算击退速度
    BulletInitializer.calculateKnockback(Obj);

    // 4. 初始化子弹属性
    BulletInitializer.initializeBulletProperties(Obj);

    // 创建子弹
    var bulletInstance = BulletFactory.createBullet(Obj, shooter, 射击角度);

    // _root.服务器.发布服务器消息(ObjectUtil.toString(bulletInstance));

    return bulletInstance;
};

_root.计算射击角度 = function(Obj, shooter){
    Obj.角度偏移 = Obj.角度偏移 | 0;
    var 基础射击角度:Number = 0;
    var 发射方向:String = shooter.方向;
    if (Obj.子弹速度 < 0) {
        Obj.子弹速度 *= -1;
        发射方向 = 发射方向 === "右" ? "左" : "右";
    }
    if(发射方向 === "左") {
        基础射击角度 = 180;
        Obj.角度偏移 = -Obj.角度偏移;
    }
    var 射击角度 = 基础射击角度 + shooter._rotation + Obj.角度偏移;
    return 射击角度;
};


// 子弹生命周期函数
_root.子弹生命周期 = function()
{
    // 原有逻辑保持不变，仅在合适位置调用 _root.子弹伤害结算

    // 如果没有 area 且不是透明检测，直接进行运动更新
    if(!this.area && !this.透明检测){
        this.updateMovement(this);
        return;
    }

    var detectionArea:MovieClip;
    var areaAABB:ICollider = this.aabbCollider;
    var bullet_rotation:Number = this._rotation; // 本地化避免多次访问造成getter开销
    var isPointSet:Boolean = this.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);

    if (this.透明检测 && !this.子弹区域area) {
        areaAABB.updateFromTransparentBullet(this);
    } else {
        detectionArea = this.子弹区域area || this.area;
        areaAABB.updateFromBullet(this, detectionArea);
    }

    if (_root.调试模式)
    {
        _root.绘制线框(detectionArea);
    }
    var gameWorld = _root.gameworld;
    var shooter = gameWorld[this.发射者名];
    var unitMap
    if(this.友军伤害) {
        unitMap = TargetCacheManager.getCachedAll(shooter,1);
    }
    else
    {
        unitMap = TargetCacheManager.getCachedEnemy(shooter,1);
    }
    
    var 击中次数 = 0;
    var 是否生成击中后效果 = true;

    var len:Number = unitMap.length;
    var hitTarget:MovieClip;
    var zOffset:Number;
    var overlapRatio:Number;
    var overlapCenter:Vector;
    var unitArea:AABBCollider;
    var result:CollisionResult;

    for (var i:Number = 0; i < len ; ++i)
    {
        hitTarget = this.hitTarget = unitMap[i];
        zOffset = hitTarget.Z轴坐标 - this.Z轴坐标;

        if (Math.abs(zOffset) >= this.Z轴攻击范围)
        {
            continue;
        }
        if (hitTarget.防止无限飞 != true || (hitTarget.hp <= 0 && !this.近战检测))
        {
            overlapRatio = 1;

            unitArea = hitTarget.aabbCollider;
            unitArea.updateFromUnitArea(hitTarget);
            
            result = areaAABB.checkCollision(unitArea, zOffset);

            if(!result.isColliding)
            {
                if(result.isOrdered)
                {
                    continue;
                }
                else
                {
                    break;
                }
            }
            if(isPointSet) {
                this.polygonCollider.updateFromBullet(this, detectionArea)
                result = this.polygonCollider.checkCollision(unitArea, zOffset);
            }

            overlapRatio = result.overlapRatio;
            overlapCenter = result.overlapCenter;

            //击中
            击中次数++;
            if(_root.调试模式)
            {
                _root.绘制线框(hitTarget.area);
            }
            var hpBar = hitTarget.新版人物文字信息 ? hitTarget.新版人物文字信息.头顶血槽 : hitTarget.人物文字信息.头顶血槽;
            hpBar._visible = true;
            hpBar.gotoAndPlay(2);
            hitTarget.攻击目标 = shooter._name;

                // ------------------------兼容区------------------------------
            this.附加层伤害计算 = 0; 
            this.命中对象 = hitTarget;

            _root.冲击力刷新(hitTarget);
            hitTarget.dispatcher.publish("hit");

            // 命中率计算略，原代码有提到根据命中率计算闪避
            var dodgeState = this.伤害类型 == "真伤" ? "未躲闪": _root.躲闪状态计算(hitTarget,_root.根据命中计算闪避结果(shooter, hitTarget, 命中率),this);

            // 调用伤害结算函数
            if(this.击中时触发函数) this.击中时触发函数();

            DamageCalculator.calculateDamage(
                this, 
                shooter, 
                hitTarget, 
                overlapRatio, 
                dodgeState
            ).triggerDisplay(hitTarget._x, hitTarget._y);

            if (hitTarget._name === _root.控制目标) {
                _root.玩家信息界面.刷新hp显示();
            }

            //伤害结算结束后，继续原逻辑
            if(!this.近战检测 && !this.爆炸检测 && hitTarget.hp <= 0)
            {
                hitTarget.状态改变("血腥死");
            }

            var 被击方向 = (hitTarget._x < shooter._x) ? "左" : "右" ;
            if(this.水平击退反向){
                被击方向 = 被击方向 === "左" ? "右" : "左";
            }
            hitTarget.方向改变(被击方向 === "左" ? "右" : "左");

            if (_root.血腥开关)
            {
                var 子弹效果碎片 = "";
                switch (hitTarget.击中效果)
                {
                    case "飙血":
                        子弹效果碎片 = "子弹碎片-飞血";
                        break;
                    case "异形飙血":
                        子弹效果碎片 = "子弹碎片-异形飞血";
                        break;
                    default:
                }

                if(子弹效果碎片 != "")
                {
                    var 效果对象 = _root.效果(子弹效果碎片, overlapCenter.x, overlapCenter.y, shooter._xscale);
                    效果对象.出血来源 = hitTarget._name;
                }
            }

            var 刚体检测 = hitTarget.刚体 || hitTarget.man.刚体标签;
            if (!hitTarget.浮空 && !hitTarget.倒地)
            {
                _root.冲击力结算(hitTarget.损伤值,this.击倒率,hitTarget);
                hitTarget.血条变色状态 = "常态";

                if (!isNaN(hitTarget.hp) && hitTarget.hp <= 0)
                {
                    hitTarget.状态改变(_root.血腥开关 ? "血腥死" : "击倒");
                }
                else if (dodgeState == "躲闪")
                {
                    hitTarget.被击移动(被击方向,this.水平击退速度,3);
                }
                else
                {
                    if (hitTarget.remainingImpactForce > hitTarget.韧性上限)
                    {
                        if (!刚体检测)
                        {
                            hitTarget.状态改变("击倒");
                            hitTarget.血条变色状态 = "击倒";
                        }
                        hitTarget.remainingImpactForce = 0;
                        hitTarget.被击移动(被击方向,this.水平击退速度,0.5);
                    }
                    else if (hitTarget.remainingImpactForce > hitTarget.韧性上限 / _root.踉跄判定 / hitTarget.躲闪率)
                    {
                        if (!刚体检测)
                        {
                            hitTarget.状态改变("被击");
                            hitTarget.血条变色状态 = "被击";
                        }

                        hitTarget.被击移动(被击方向,this.水平击退速度,2);
                    }
                    else
                    {
                        hitTarget.被击移动(被击方向,this.水平击退速度,3);
                    }
                }
            }
            else
            {
                hitTarget.remainingImpactForce = 0;
                if (!刚体检测)
                {
                    hitTarget.状态改变("击倒");
                    hitTarget.血条变色状态 = "击倒";
                    if (!(this.垂直击退速度 > 0))
                    {
                        var y速度 = 5;
                        hitTarget.man.垂直速度 = -y速度;
                    }
                }
                hitTarget.被击移动(被击方向,this.水平击退速度,0.5);
            }

            if(!this.近战检测 && !this.爆炸检测 && hitTarget.hp <= 0)
            {
                hitTarget.状态改变("血腥死");
            }

            switch (hitTarget.血条变色状态)
            {
                case "常态": _root.重置色彩(hpBar);
                    break;
                default: _root.暗化色彩(hpBar);
            }

            _root.效果(hitTarget.击中效果, overlapCenter.x, overlapCenter.y, shooter._xscale);
            if(hitTarget.击中效果 == this.击中后子弹的效果) {
                是否生成击中后效果 = false;
            }

            if (this.近战检测 && !this.不硬直)
            {
                shooter.硬直(shooter.man,_root.钝感硬直时间);
            }
            else if(!this.穿刺检测)
            {
                this.gotoAndPlay("消失");
            }

            if (this.垂直击退速度 > 0)
            {
                hitTarget.man.play();
                clearInterval(hitTarget.pauseInterval);
                hitTarget.硬直中 = false;
                clearInterval(hitTarget.pauseInterval2);

                _root.fly(hitTarget,this.垂直击退速度,0);
            }
        }
    }

    if(是否生成击中后效果 && 击中次数 > 0){
        _root.效果(this.击中后子弹的效果,this._x,this._y,shooter._xscale);
    }

    // 调用更新运动逻辑
    this.updateMovement(this);

    // 检查是否需要销毁
    if (this.shouldDestroy(this)) {
        areaAABB.getFactory().releaseCollider(areaAABB);

        if(isPointSet)
        {
            this.polygonCollider.getFactory().releaseCollider(this.polygonCollider);
        }

        if (this.击中地图) {
            this.霰弹值 = 1;
            _root.效果(this.击中地图效果, this._x, this._y);
            if (this.击中时触发函数) {
                this.击中时触发函数();
            }
            this.gotoAndPlay("消失");
        } else {
            this.removeMovieClip();
        }
        return;
    }
};



_root.子弹区域shoot表演 = _root.子弹区域shoot;


// 初始化函数

_root.子弹属性初始化 = function(子弹元件:MovieClip,子弹种类:String,发射者:MovieClip){
	var myPoint = {x:子弹元件._x,y:子弹元件._y};
	子弹元件._parent.localToGlobal(myPoint);
	var 转换中间y = myPoint.y;
	_root.gameworld.globalToLocal(myPoint);
	shootX = myPoint.x;
	shootY = myPoint.y;
	if(!发射者){
		发射者 = 子弹元件._parent._parent;
	}
	var 子弹属性 = {
		声音:"",
		霰弹值:1,
		子弹散射度:1,
		发射效果:"",
		子弹种类:子弹种类 == undefined ? "普通子弹" : 子弹种类,
		子弹威力:10,
		子弹速度:10,
		Z轴攻击范围:10,
		击中地图效果:"火花",
		发射者:发射者._name,
		shootX:shootX,
		shootY:shootY,
		转换中间y:转换中间y,
		shootZ:发射者.Z轴坐标,
		子弹敌我属性:!发射者.是否为敌人,
		击倒率:10,
		击中后子弹的效果:"",
		水平击退速度:NaN,
		垂直击退速度:NaN,
		命中率:NaN,
		固伤:NaN,
		百分比伤害:NaN,
		血量上限击溃:NaN,
		防御粉碎:NaN,
		吸血:NaN,
		毒:NaN,
		最小霰弹值:1,
		不硬直:false,
		区域定位area:undefined,
		伤害类型:undefined,
		魔法伤害属性:undefined,
		速度X:undefined,
		速度Y:undefined,
		ZY比例:undefined,
		斩杀:undefined,
		暴击:undefined,
		水平击退反向:false,
		角度偏移:0
	}
	return 子弹属性;
}

/*使用示例：

	子弹属性 = _root.子弹属性初始化(this);
	
	//以下部分只需要更改需要更改的属性,其余部分可注释掉
	子弹属性.声音 = "";
	子弹属性.霰弹值 = 1;
	子弹属性.子弹散射度 = 1;
	子弹属性.子弹种类 = "普通子弹";
	子弹属性.子弹威力 = 10;
	子弹属性.子弹速度 = 10;
	子弹属性.Z轴攻击范围 = 10.
	子弹属性.击倒率 = 10;
	子弹属性.水平击退速度 = NaN;
	子弹属性.垂直击退速度 = NaN;
	
	//非常用
	子弹属性.发射效果 = "";
	子弹属性.击中地图效果 = "火花".
	子弹属性.击中后子弹的效果 = "".
	子弹属性.命中率 = NaN.
	子弹属性.固伤 = NaN;
	子弹属性.百分比伤害 = NaN;
	子弹属性.血量上限击溃 = NaN;
	子弹属性.防御粉碎 = NaN;
	子弹属性.区域定位area = undefinded;
	
	//已初始化内容，通常不需要重复赋值，可注释掉
	子弹属性.发射者 = 子弹属性.发射者.
	子弹属性.shootX = 子弹属性.shootX;
	子弹属性.shootY = 子弹属性.shootY;
	子弹属性.shootZ = 子弹属性.shootZ;
	子弹属性.子弹敌我属性 = 子弹属性.子弹敌我属性;
	
	_root.子弹区域shoot传递(子弹属性);


*/






