// 1. 核心框架组件 (按包层级排序)
import org.flashNight.arki.bullet.BulletComponent.Attributes.*; // 属性定义优先
import org.flashNight.arki.bullet.BulletComponent.Collider.*;   // 碰撞组件
import org.flashNight.arki.bullet.BulletComponent.Init.*;       // 初始化组件
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*; // 生命周期管理
import org.flashNight.arki.bullet.BulletComponent.Movement.*;  // 移动逻辑
import org.flashNight.arki.bullet.BulletComponent.Shell.*;     // 弹壳组件
import org.flashNight.arki.bullet.BulletComponent.Type.*;      // 类型定义
import org.flashNight.arki.bullet.BulletComponent.Utils.*;     // 工具类
import org.flashNight.arki.render.*;
import org.flashNight.arki.spatial.transform.*;
// 2. 子弹工厂（具体类单独导入）
import org.flashNight.arki.bullet.Factory.BulletFactory;

// 3. 其他组件（按功能分类）
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.component.Damage.*;      // 伤害计算
import org.flashNight.arki.component.Effect.*;      // 特效组件
import org.flashNight.arki.component.StatHandler.*; // 状态系统

// 4. 单位组件
import org.flashNight.arki.unit.UnitComponent.Targetcache.*; // 目标缓存

// 5. 辅助模块（按字母顺序）
import org.flashNight.aven.Proxy.*;     // 代理模式实现
import org.flashNight.gesh.object.*;    // 对象管理
import org.flashNight.naki.Sort.*;      // 排序算法
import org.flashNight.neur.Event.*;     // 事件系统
import org.flashNight.sara.util.*;      // 工具方法

 
DamageManagerFactory.init();
BulletInitializer.initializeAttributes();

//重写子弹生成逻辑
_root.子弹生成计数 = 0;

//加入新参数水平击退速度和垂直击退速度。未填写的话默认分别为10和5（和子弹区域shoot一致），最大击退速度可以调节下方常数（目前为33）。
//额外添加了命中率,固伤,百分比伤害，血量上限击溃，防御粉碎，命中率未输入则寻找发射者的命中，固伤与百分比未输入默认为0
_root.最大水平击退速度 = 33;
_root.最大垂直击退速度 = 15;

_root.子弹区域shoot = function(声音, 霰弹值, 子弹散射度, 发射效果, 子弹种类, 子弹威力, 子弹速度, Z轴攻击范围, 击中地图效果, 发射者, shootX, shootY, shootZ, null, 击倒率, 击中后子弹的效果, 水平击退速度, 垂直击退速度, 命中率, 固伤, 百分比伤害, 血量上限击溃, 防御粉碎, 区域定位area, 吸血, 毒, 最小霰弹值, 不硬直, 伤害类型, 魔法伤害属性, 速度X, 速度Y, ZY比例, 斩杀, 暴击, 水平击退反向, 角度偏移)
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
    var shootingAngle:Number = ShootingAngleCalculator.calculate(Obj, shooter);

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
    var bulletInstance = BulletFactory.createBullet(Obj, shooter, shootingAngle);
    // _root.服务器.发布服务器消息(ObjectUtil.toString(bulletInstance));

    // 创建发射效果和音效
    var shootX:Number = Obj.shootX;
    var shootY:Number = Obj.shootY;
    var xscale:Number = shooter._xscale;
    var effect:MovieClip = EffectSystem.Effect(Obj.发射效果, shootX, shootY, xscale);
    if(effect) effect._rotation = Obj.角度偏移;
    ShellSystem.launchShell(bulletInstance, shootX, shootY, xscale);
    _root.soundEffectManager.playSound(Obj.声音);

    return bulletInstance;
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
    var bullet_rotation:Number = this._rotation; // 本地化以减少多次访问 getter 的开销
    var isPointSet:Boolean = this.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);
    var bulletZOffset:Number = this.Z轴坐标;
    var bulletZRange:Number  = this.Z轴攻击范围;

    if (this.透明检测 && !this.子弹区域area) {
        areaAABB.updateFromTransparentBullet(this);
    } else {
        detectionArea = this.子弹区域area || this.area;
        areaAABB.updateFromBullet(this, detectionArea);
    }

    if (_root.调试模式)
    {
        // 绘制当前碰撞箱，并显示以子弹 Z轴坐标为基准的 z 轴攻击范围上下边界
        AABBRenderer.renderAABB(areaAABB, 0, "line", bulletZRange);
    }
    
    var gameWorld = _root.gameworld;
    var shooter = gameWorld[this.发射者名];
    var rangeResult:Object;
    if(this.友军伤害) {
        rangeResult = TargetCacheManager.getCachedAllFromIndex(shooter, 1, areaAABB);
    }
    else
    {
        rangeResult = TargetCacheManager.getCachedEnemyFromIndex(shooter, 1, areaAABB);
    }

    var unitMap:Array = rangeResult.data;
    var startIndex:Number = rangeResult.startIndex;
    this.shouldGeneratePostHitEffect = true;

    var len:Number = unitMap.length;
    var hitTarget:MovieClip;
    var zOffset:Number;
    var overlapRatio:Number;
    var overlapCenter:Vector;
    var unitArea:AABBCollider;
    var collisionResult:CollisionResult;

    for (var i:Number = startIndex; i < len ; ++i)
    {
        hitTarget = this.hitTarget = unitMap[i];
        // 计算子弹与目标在 z 轴上的相对偏移值
        zOffset = bulletZOffset - hitTarget.Z轴坐标;

        if (Math.abs(zOffset) >= bulletZRange)
        {
            continue;
        }
        if (hitTarget.hp > 0 && hitTarget.防止无限飞 != true)
        {
            overlapRatio = 1;

            unitArea = hitTarget.aabbCollider;
            collisionResult = areaAABB.checkCollision(unitArea, zOffset);

            if(!collisionResult.isColliding)
            {
                if(collisionResult.isOrdered)
                {
                    continue;
                }
                else
                {
                    break;
                }
            }
            if(isPointSet) {
                this.polygonCollider.updateFromBullet(this, detectionArea);
                collisionResult = this.polygonCollider.checkCollision(unitArea, zOffset);
            }

            if (_root.调试模式)
            {
                AABBRenderer.renderAABB(areaAABB, zOffset, "thick");
                AABBRenderer.renderAABB(unitArea, zOffset, "filled");
            }

            overlapRatio = collisionResult.overlapRatio;
            overlapCenter = collisionResult.overlapCenter;

            // 命中处理
            this.hitCount++;
            this.附加层伤害计算 = 0;
            this.命中对象 = hitTarget;

            var dodgeState = this.伤害类型 == "真伤" ? "未躲闪": 
            DodgeHandler.calculateDodgeState(hitTarget,
                DodgeHandler.calcDodgeResult(shooter, hitTarget, this.命中率), this);
            
            if(this.击中时触发函数) this.击中时触发函数();

            var damageResult:DamageResult = DamageCalculator.calculateDamage(
                this, 
                shooter, 
                hitTarget, 
                overlapRatio, 
                dodgeState
            );

            var dispatcher:EventDispatcher = hitTarget.dispatcher;
            dispatcher.publish("hit", hitTarget, shooter, this, collisionResult, damageResult);

            if(hitTarget.hp <= 0)
            {
                if(!this.近战检测 && !this.爆炸检测)
                {
                    dispatcher.publish("kill", hitTarget);
                }
                else {
                    dispatcher.publish("death", hitTarget);
                }
            }

            damageResult.triggerDisplay(hitTarget._x, hitTarget._y);

            if (this.近战检测 && !this.不硬直)
            {
                shooter.硬直(shooter.man, _root.钝感硬直时间);
            }
            else if(!this.穿刺检测)
            {
                this.gotoAndPlay("消失");
            }
        }

        if(this.pierceLimit && this.pierceLimit < this.hitCount) {
            this.shouldDestroy = function() {
                return true;
            };
            break;
        }
    }

    if(this.shouldGeneratePostHitEffect && this.hitCount > 0){
        EffectSystem.Effect(this.击中后子弹的效果, this._x, this._y, shooter._xscale);
    }

    // 更新子弹运动逻辑
    this.updateMovement(this);

    // 销毁检测及后续处理
    if (this.shouldDestroy(this)) {
        areaAABB.getFactory().releaseCollider(areaAABB);

        if(isPointSet)
        {
            this.polygonCollider.getFactory().releaseCollider(this.polygonCollider);
        }

        if (this.击中地图) {
            this.霰弹值 = 1;
            EffectSystem.Effect(this.击中地图效果, this._x, this._y);
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
	
	_root.子弹区域shoot传递(子弹属性);


*/





