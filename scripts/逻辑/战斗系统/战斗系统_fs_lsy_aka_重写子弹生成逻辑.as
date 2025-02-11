import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Attributes.*
import org.flashNight.arki.bullet.BulletComponent.Init.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.aven.Proxy.*;

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

    var 游戏世界 = _root.gameworld;
    var shooter = 游戏世界[Obj.发射者];

    // 计算射击角度
    var 射击角度 = 计算射击角度(Obj, shooter);

    // 创建发射效果和音效
    _root.创建发射效果(Obj, shooter);

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
    var bulletInstance = 创建子弹(Obj, shooter, 射击角度);

    // _root.服务器.发布服务器消息(ObjectUtil.toString(bulletInstance));

    return bulletInstance;
};

_root.计算射击角度 = function(Obj, shooter){
    Obj.角度偏移 = isNaN(Obj.角度偏移) ? 0 : Number(Obj.角度偏移);
    var 基础射击角度:Number = 0;
    var 发射方向 = shooter.方向;
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
}

_root.创建发射效果 = function(Obj, shooter){
    var 游戏世界 = _root.gameworld;
    var depth = _root.随机整数(0, _root.发射效果上限);
    var f_name = "f" + depth;
    var 发射效果对象 = 游戏世界.效果.attachMovie(Obj.发射效果, f_name, depth, {
        _xscale: shooter._xscale,
        _x: Obj.shootX,
        _y: Obj.shootY,
        _rotation: Obj.角度偏移
    });
    ShellSystem.launchShell(Obj.子弹种类, Obj.shootX, Obj.shootY, shooter._xscale);
    _root.播放音效(Obj.声音);
}

_root.创建子弹 = function(Obj, shooter, 射击角度){
    var 游戏世界 = _root.gameworld;
    var 子弹总数 = Obj.联弹检测 ? 1 : Obj.霰弹值;
    var bulletInstance;

    obj.联弹霰弹值 = obj.联弹检测 ? obj.霰弹值 : 1;

    for (var 子弹计数 = 0; 子弹计数 < 子弹总数; 子弹计数++) {
        bulletInstance = 创建子弹实例(Obj, shooter, 射击角度);
        
        BulletInitializer.initializeNanoToxicfunction(Obj,bulletInstance, shooter)

        // 创建生命周期逻辑实例
        var lifecycle:BulletLifecycle = new BulletLifecycle(900); // 当前射程阈值为900
        lifecycle.bindLifecycle(bulletInstance);

        // 创建子弹移动逻辑实例
        var movement:LinearBulletMovement = LinearBulletMovement.create(bulletInstance.速度X, bulletInstance.速度Y, bulletInstance.ZY比例);

        // 将 updateMovement 方法绑定到bulletInstance
        bulletInstance.updateMovement = Delegate.create(movement, movement.updateMovement);

        // 将 shouldDestroy 方法绑定到bulletInstance
        bulletInstance.shouldDestroy = Delegate.create(lifecycle, lifecycle.shouldDestroy);

        bulletInstance.damageManager = DamageManagerFactory.Basic.getDamageManager(bulletInstance);
        // _root.发布消息(bulletInstance.damageManager);
    }

    
    return bulletInstance;
}

// 改进后的子弹统计钩子
// 增强报告生成代码
_root.创建子弹实例 = function(Obj, shooter, 射击角度) {
    var 游戏世界 = _root.gameworld;
    var 散射角度 = Obj.近战检测 ? 0 : 射击角度 + (Obj.联弹检测 ? 0 : _root.随机偏移(Obj.子弹散射度));
    var 形状偏角 = 0;
    if(Obj.ZY比例 && Obj.速度X && Obj.速度Y){
        形状偏角 = Math.atan2(Obj.速度Y, Obj.速度X) * (180 / Math.PI);
        if (形状偏角 < 0) { 形状偏角 += 360; }
    } else { 形状偏角 = 散射角度; }
    Obj._rotation = 形状偏角;
    var angle = 散射角度 * (Math.PI / 180);
    var bulletInstance;
    if(Obj.透明检测){
        bulletInstance = _root.对象浅拷贝(Obj);
    } else {
        _root.子弹生成计数 = (_root.子弹生成计数 + 1) % 100;
        var depth = 游戏世界.子弹区域.getNextHighestDepth();
        var b_name = Obj.发射者名 + Obj.子弹种类 + depth + 散射角度 + _root.子弹生成计数;
        bulletInstance = 游戏世界.子弹区域.attachMovie(Obj.baseAsset, b_name, depth, Obj);
    }

    bulletInstance.xmov = bulletInstance.子弹速度 * Math.cos(angle);
    bulletInstance.ymov = bulletInstance.子弹速度 * Math.sin(angle);
    bulletInstance.霰弹值 = Obj.联弹检测 ? Obj.霰弹值 : 1;

    /*

    var report_len = 16;

    // 初始化统计信息（如果没有）
    if (!游戏世界.bulletStats) {
        游戏世界.bulletStats = {
            shooters: {},
            bulletTypes: {},
            totalShots: 0,
            timeStats: {},
            unitShots: {},
            lastSecondStats: {
                shooters: {},
                bulletTypes: {},
                totalShots: 0
            }
        };
    }

    // 增加单位发射数量
    if (!游戏世界.bulletStats.shooters[shooter]) {
        游戏世界.bulletStats.shooters[shooter] = {
            shotCount: 0,
            bulletTypes: {}
        };
    }
    游戏世界.bulletStats.shooters[shooter].shotCount++;

    // 增加子弹类型发射数量
    if (!游戏世界.bulletStats.bulletTypes[Obj.子弹种类]) {
        游戏世界.bulletStats.bulletTypes[Obj.子弹种类] = {
            shotCount: 0,
            shooters: {}
        };
    }
    游戏世界.bulletStats.bulletTypes[Obj.子弹种类].shotCount++;

    // 增加全局子弹统计
    游戏世界.bulletStats.totalShots++;

    // 时间统计：跟踪每一帧创建的子弹数量
    var currentFrame = _root.帧计时器.当前帧数;
    var currentSecond = Math.floor(currentFrame / 30);
    if (!游戏世界.bulletStats.timeStats[currentSecond]) {
        游戏世界.bulletStats.timeStats[currentSecond] = {
            totalShots: 0,
            shooters: {}
        };
    }
    游戏世界.bulletStats.timeStats[currentSecond].totalShots++;
    if (!游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter]) {
        游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter] = 0;
    }
    游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter]++;

    // 增加每个单位的子弹创建数量
    if (!游戏世界.bulletStats.unitShots[shooter]) {
        游戏世界.bulletStats.unitShots[shooter] = {
            shotCount: 0,
            bulletTypes: {}
        };
    }
    游戏世界.bulletStats.unitShots[shooter].shotCount++;
    if (!游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类]) {
        游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类] = 0;
    }
    游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类]++;

    // 每秒汇总一次统计信息
    if (currentFrame % 30 == 0) {
        var report = "子弹创建与发射频率分析报告：\n";

        // 发射者排行（按发射数量）
        var sortedShooters = [];
        for (var shooterName in 游戏世界.bulletStats.shooters) {
            sortedShooters.push({ name: shooterName, count: 游戏世界.bulletStats.shooters[shooterName].shotCount });
        }
        sortedShooters.sort(function(a, b) { return b.count - a.count; });

        report += "发射者排行（按发射数量）：\n";
        for (var i = 0; i < Math.min(report_len, sortedShooters.length); i++) {
            var shooterSummary = sortedShooters[i];
            report += shooterSummary.name + ": " + shooterSummary.count + " 发射\n";

            // 每个发射者发射的子弹类型统计
            for (var bulletType in 游戏世界.bulletStats.shooters[shooterSummary.name].bulletTypes) {
                report += "  -> " + bulletType + ": " + 游戏世界.bulletStats.shooters[shooterSummary.name].bulletTypes[bulletType] + " 发射\n";
            }
        }

        // 子弹类型排行（按发射数量）
        var sortedBulletTypes = [];
        for (var bulletType in 游戏世界.bulletStats.bulletTypes) {
            sortedBulletTypes.push({ name: bulletType, count: 游戏世界.bulletStats.bulletTypes[bulletType].shotCount });
        }
        sortedBulletTypes.sort(function(a, b) { return b.count - a.count; });

        report += "子弹类型排行（按发射数量）：\n";
        for (var i = 0; i < Math.min(report_len, sortedBulletTypes.length); i++) {
            var bulletTypeSummary = sortedBulletTypes[i];
            report += bulletTypeSummary.name + ": " + bulletTypeSummary.count + " 发射\n";
        }

        // 最多创建子弹的单位（按创建子弹数量）
        var sortedUnitShots = [];
        for (var unitName in 游戏世界.bulletStats.unitShots) {
            sortedUnitShots.push({ name: unitName, count: 游戏世界.bulletStats.unitShots[unitName].shotCount });
        }
        sortedUnitShots.sort(function(a, b) { return b.count - a.count; });

        report += "最多创建子弹的单位排行：\n";
        for (var i = 0; i < Math.min(report_len, sortedUnitShots.length); i++) {
            var unitSummary = sortedUnitShots[i];
            report += unitSummary.name + ": " + unitSummary.count + " 次创建\n";

            // 每个单位创建的子弹类型统计
            for (var bulletType in 游戏世界.bulletStats.unitShots[unitSummary.name].bulletTypes) {
                report += "  -> " + bulletType + ": " + 游戏世界.bulletStats.unitShots[unitSummary.name].bulletTypes[bulletType] + " 次创建\n";
            }
        }

        // 每秒子弹创建频率分析
        report += "\n每秒子弹创建频率分析：\n";
        var sortedTimeStats = [];
        for (var second in 游戏世界.bulletStats.timeStats) {
            var timeData = 游戏世界.bulletStats.timeStats[second];
            sortedTimeStats.push({ second: second, shotCount: timeData.totalShots });
        }
        sortedTimeStats.sort(function(a, b) { return b.shotCount - a.shotCount; });

        for (var i = 0; i < Math.min(report_len, sortedTimeStats.length); i++) {
            var timeSummary = sortedTimeStats[i];
            report += "第 " + timeSummary.second + " 秒: " + timeSummary.shotCount + " 子弹创建\n";

            // 每秒区间内的发射者发射情况
            for (var shooterName in 游戏世界.bulletStats.timeStats[timeSummary.second].shooters) {
                report += "  发射者 " + shooterName + ": " + 游戏世界.bulletStats.timeStats[timeSummary.second].shooters[shooterName] + " 发射\n";
            }
        }

        // 总子弹数量（全局）
        report += "总子弹数量（全局）: " + 游戏世界.bulletStats.totalShots + "\n";

        // 发送汇总后的统计信息
        _root.服务器.发布服务器消息(report);
    }

    */

    return bulletInstance;
};



// --------------------子弹伤害结算核心--------------------
// 专注于伤害与效果计算，并将计算结果打包返回
// --------------------子弹伤害结算核心--------------------
_root.子弹伤害结算核心 = function(bullet, shooter, hitTarget, overlapRatio, 消耗霰弹值, dodgeState) {
    var damageResult:DamageResult = DamageResult.IMPACT;
    damageResult.reset();

    var manager:DamageManager = bullet.damageManager;
    manager.overlapRatio = overlapRatio;
    manager.dodgeState = dodgeState;

    if (hitTarget.无敌 || hitTarget.man.无敌标签 || hitTarget.NPC) {
        return damageResult; 
    }
    
    if (hitTarget.hp == 0) {
        return damageResult;
    }
    
    hitTarget.防御力 = isNaN(hitTarget.防御力) ? 1 : Math.min(hitTarget.防御力, 99000);
    bullet.破坏力 = Number(bullet.子弹威力) + (isNaN(shooter.伤害加成) ? 0 : shooter.伤害加成);
    
    var damageVariance:Number = bullet.破坏力 * ((!_root.调试模式 || bullet.霰弹值 > 1) ? (0.85 + _root.basic_random() * 0.3) : 1);
    var percentageDamage:Number = isNaN(bullet.百分比伤害) ? 0 : hitTarget.hp * bullet.百分比伤害 / 100;
    bullet.破坏力 = damageVariance + bullet.固伤 + percentageDamage;
    

    /*
    manager.execute(bullet, shooter, hitTarget, damageResult);
    _root.发布消息(damageResult.toString());

    */


    var crit:CritDamageHandle = CritDamageHandle.instance;
    if(crit.canHandle(bullet)) crit.handleBulletDamage(bullet, shooter, hitTarget, manager, damageResult);

    
    var uni:UniversalDamageHandle = UniversalDamageHandle.instance;
    uni.handleBulletDamage(bullet, shooter, hitTarget, manager, damageResult);
    

    var damageNumber:Number = hitTarget.损伤值;
    var damageSize:Number = damageResult.damageSize;

    var actualScatterUsed:Number = Math.min(
        bullet.霰弹值,
        Math.ceil(
            Math.min(
                bullet.最小霰弹值 + overlapRatio * ((bullet.霰弹值 - bullet.最小霰弹值) + 1) * 1.2,
                hitTarget.hp / (hitTarget.损伤值 > 0 ? hitTarget.损伤值 : 1)
            )
        )
    );
    damageResult.actualScatterUsed = actualScatterUsed;
    
    if (bullet.联弹检测 && !bullet.穿刺检测) {
        bullet.霰弹值 -= actualScatterUsed;
        damageResult.finalScatterValue = bullet.霰弹值;
    }
    
    hitTarget.损伤值 *= actualScatterUsed;
    damageNumber *= actualScatterUsed;
    
    var poisonAmount:Number = 0;
    if (bullet.nanoToxic > 0) {
        poisonAmount = bullet.nanoToxic;
        if (bullet.普通检测) {
            poisonAmount *= 1;
        } else {
            poisonAmount *= 0.3;
        }
        bullet.additionalEffectDamage += poisonAmount;
    }
    if (poisonAmount > 0 && !isNaN(damageNumber) && damageNumber > 0) {
        hitTarget.损伤值 += poisonAmount;
        damageNumber = hitTarget.损伤值;
        damageResult.addDamageEffect('<font color="#66dd00" size="20"> 毒</font>');
        if (bullet.nanoToxicDecay && bullet.近战检测 && shooter.淬毒 > 10) {
            shooter.淬毒 -= bullet.nanoToxicDecay;
        }
        if (hitTarget.毒返 > 0) {
            var poisonReturnAmount:Number = poisonAmount * hitTarget.毒返;
            if (hitTarget.毒返函数) {
                hitTarget.毒返函数(poisonAmount, poisonReturnAmount);
            }
            hitTarget.淬毒 = poisonReturnAmount;
        }
    }
    
    if (bullet.吸血 > 0 && hitTarget.损伤值 > 1) {
        var lifeStealAmount:Number = Math.floor(Math.max(Math.min(hitTarget.损伤值 * bullet.吸血 / 100, hitTarget.hp), 0));
        shooter.hp += Math.min(lifeStealAmount, shooter.hp满血值 * 1.5 - shooter.hp);
        damageResult.addDamageEffect('<font color="#bb00aa" size="15"> 汲:' + Math.floor(lifeStealAmount / actualScatterUsed).toString() + "</font>");
    }
    
    var crumbleAmount:Number = 0;
    if (bullet.击溃 > 0 && hitTarget.损伤值 > 1) {
        crumbleAmount = Math.floor(hitTarget.hp满血值 * bullet.击溃 / 100);
        bullet.additionalEffectDamage += crumbleAmount;
        if (hitTarget.hp满血值 > 0) {
            hitTarget.hp满血值 -= crumbleAmount;
            hitTarget.损伤值 += crumbleAmount;
        }
        damageResult.addDamageEffect('<font color="#FF3333" size="20"> 溃</font>');
        damageNumber = Math.floor(hitTarget.损伤值);
    }
    
    if (bullet.斩杀) {
        if (hitTarget.hp < hitTarget.hp满血值 * bullet.斩杀 / 100) {
            hitTarget.损伤值 += hitTarget.hp; 
            hitTarget.hp = 0;
            var executeColor:String = bullet.子弹敌我属性值 ? '#4A0099' : '#660033';
            damageResult.addDamageEffect('<font color="' + executeColor + '" size="20"> 斩</font>');
        }
        damageNumber = Math.floor(hitTarget.损伤值);
    }
    
    damageResult.displayCount = damage.actualScatterUsed;
    damageResult.displayCount = actualScatterUsed; 
    var remainingDamage:Number = damageNumber;
    
    if (actualScatterUsed > 1) {
        for (var i:Number = 0; i < actualScatterUsed - 1; i++) {
            var fluctuatedDamage:Number = (remainingDamage / (actualScatterUsed - i)) * (100 + _root.随机偏移(50 / actualScatterUsed)) / 100;
            fluctuatedDamage = isNaN(fluctuatedDamage) ? 0 : fluctuatedDamage;
            damageResult.addDamageValue(Math.floor(fluctuatedDamage));
            remainingDamage -= fluctuatedDamage;
        }
    }
    damageResult.addDamageValue(isNaN(remainingDamage) ? 0 : Math.floor(remainingDamage));
    
    damageResult.damageSize = damageSize;
    
    hitTarget.hp = isNaN(hitTarget.损伤值) ? hitTarget.hp : Math.floor(hitTarget.hp - hitTarget.损伤值);
    hitTarget.hp = (hitTarget.hp < 0 || isNaN(hitTarget.hp)) ? 0 : hitTarget.hp;

    // _root.服务器.发布服务器消息(damageResult);
    
    return damageResult;
};


// --------------------子弹伤害结算（主函数）--------------------
// 继续保留原本的入口，但在里面调用 核心计算函数 和 显示函数。
// --------------------子弹伤害结算（主函数）--------------------
_root.子弹伤害结算 = function(bullet, shooter, hitTarget, overlapRatio, 消耗霰弹值, dodgeState, overlapCenter) {
    _root.子弹伤害结算核心(
        bullet, 
        shooter, 
        hitTarget, 
        overlapRatio, 
        消耗霰弹值, 
        dodgeState
    ).triggerDisplay(hitTarget._x, hitTarget._y);

    
    if (hitTarget._name === _root.控制目标) {
        _root.玩家信息界面.刷新hp显示();
    }
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
    var isRotated:Boolean = (bullet_rotation != 0 && bullet_rotation != 180);
    var isPointSet:Boolean = this.联弹检测 && isRotated;

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
    var 游戏世界 = _root.gameworld;
    var shooter = 游戏世界[this.发射者名];
    var unitMap = _root.帧计时器.获取敌人缓存(shooter,1);
    if(this.友军伤害){
        var 遍历友军表 = _root.帧计时器.获取友军缓存(shooter,1);
        unitMap = unitMap.concat(遍历友军表);

        InsertionSort.sort(unitMap, function(a:Object, b:Object):Number {
            return a.aabbCollider.right - b.aabbCollider.right;
        });
    }
    var 击中次数 = 0;
    var 是否生成击中后效果 = true;

    for (var i = 0; i < unitMap.length ; ++i)
    {
        this.hitTarget = unitMap[i];
        var hitTarget:MovieClip = this.hitTarget;
        var zOffset = hitTarget.Z轴坐标 - this.Z轴坐标;

        if (Math.abs(zOffset) >= this.Z轴攻击范围)
        {
            continue;
        }
        if (hitTarget.防止无限飞 != true || (hitTarget.hp <= 0 && !this.近战检测))
        {
            var overlapRatio = 1;
            var overlapCenter;

            var unitArea:AABBCollider = hitTarget.aabbCollider;
            unitArea.updateFromUnitArea(hitTarget);

            var result:CollisionResult = areaAABB.checkCollision(unitArea, zOffset);

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

            _root.冲击力刷新(hitTarget);
            hitTarget.dispatcher.publish("hit");

            // 命中率计算略，原代码有提到根据命中率计算闪避
            var dodgeState = this.伤害类型 == "真伤" ? "未躲闪": _root.躲闪状态计算(hitTarget,_root.根据命中计算闪避结果(shooter, hitTarget, 命中率),this);

            // 调用伤害结算函数
            var 消耗霰弹值 = 1; // 在伤害计算中实际会重新计算

            if(this.击中时触发函数) this.击中时触发函数();

            _root.子弹伤害结算(this, shooter, hitTarget, overlapRatio, 消耗霰弹值, dodgeState, overlapCenter);

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






