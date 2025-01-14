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
    }
    return bulletInstance;
}

_root.创建子弹实例 = function(Obj, shooter, 射击角度){
    var 游戏世界 = _root.gameworld;
    var 散射角度 = Obj.近战检测 ? 0 : 射击角度 + (Obj.联弹检测 ? 0 : _root.随机偏移(Obj.子弹散射度));
    var 形状偏角 = 0;
    if(Obj.ZY比例 && Obj.速度X && Obj.速度Y){
        形状偏角 = Math.atan2(Obj.速度Y, Obj.速度X) * (180 / Math.PI);
        if (形状偏角 < 0) {
            形状偏角 += 360;
        }
    } else {
        形状偏角 = 散射角度;
    }
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


    return bulletInstance;
}

// --------------------子弹伤害结算核心--------------------
// 专注于伤害与效果计算，并将计算结果打包返回
_root.子弹伤害结算核心 = function(子弹, shooter, hitTarget, overlapRatio, 消耗霰弹值, 躲闪状态)
{
    // 返回结果对象，将所有与最终显示相关的数据收集起来
    var 计算结果 = {
        总伤害数字列表: [],      // 用于存放每次段伤害值，用于后续分段显示
        伤害数字颜色: null,     // 记录颜色
        伤害数字大小: 28,       // 记录字号
        伤害字符: "",           // 记录附加字符（魔法、毒、斩等）
        最终子弹霰弹值: 子弹.霰弹值, // 保留子弹霰弹值
        躲闪状态字符: "",       // 记录“MISS”或其他特殊字符
        实际消耗霰弹值: 1,      // 实际消耗霰弹值
        显示次数: 1             // 多段伤害显示次数
    };

    // 如果目标无敌或是NPC，则不做任何计算
    if (hitTarget.无敌 || hitTarget.man.无敌标签 || hitTarget.NPC) {
        return 计算结果; 
    }

    // 如果目标HP为0，也无需计算
    if (hitTarget.hp == 0) {
        return 计算结果;
    }

    // 对目标防御力进行处理
    hitTarget.防御力 = isNaN(hitTarget.防御力) ? 1 : Math.min(hitTarget.防御力, 99000);
    
    // 子弹破坏力初步计算
    子弹.破坏力 = Number(子弹.子弹威力) + (isNaN(shooter.伤害加成) ? 0 : shooter.伤害加成);

    // 随机波动
    var 伤害波动数字 = 子弹.破坏力 * ((!_root.调试模式 || 子弹.霰弹值 > 1) ? (0.85 + _root.basic_random() * 0.3) : 1);
    var 百分比伤 = isNaN(子弹.百分比伤害) ? 0 : hitTarget.hp * 子弹.百分比伤害 / 100;

    // 累加固伤与百分比伤害
    子弹.破坏力 = 伤害波动数字 + 子弹.固伤 + 百分比伤;

    // 暴击
    if (子弹.暴击) {
        子弹.破坏力 = 子弹.破坏力 * 子弹.暴击(子弹);
    }

    // 计算伤害数字颜色（默认）
    var 默认伤害数字颜色 = 子弹.子弹敌我属性值 ? "#FFCC00" : "#FF0000";
    计算结果.伤害数字颜色 = 默认伤害数字颜色;

    // 三种主要伤害类型：真伤、魔法、物理
    if (子弹.伤害类型 === "真伤") {
        计算结果.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#4A0099" : "#660033";
        计算结果.伤害字符 += '<font color="' + 计算结果.伤害数字颜色 + '" size="20"> 真</font>';
        hitTarget.损伤值 = 子弹.破坏力;
    } else if (子弹.伤害类型 === "魔法") {
        计算结果.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#0099FF" : "#AC99FF";
        var 魔法伤害属性字符 = 子弹.魔法伤害属性 ? 子弹.魔法伤害属性 : "能";
        计算结果.伤害字符 += '<font color="' + 计算结果.伤害数字颜色 + '" size="20"> ' + 魔法伤害属性字符 + '</font>';
        
        var 魔法属性 = 子弹.魔法伤害属性;
        var 魔抗表 = hitTarget.魔法抗性;
        var 敌人法抗 = 10 + hitTarget.等级 / 2;

        if (魔抗表) {
            if (魔法属性 && (魔抗表[魔法属性] != undefined)) {
                敌人法抗 = 魔抗表[魔法属性];
            } else if (魔抗表["基础"] != undefined) {
                敌人法抗 = 魔抗表["基础"];
            }
        }

        
        敌人法抗 = isNaN(敌人法抗) ? 20 : Math.min(Math.max(敌人法抗, -1000), 100);
        hitTarget.损伤值 = Math.floor(子弹.破坏力 * (100 - 敌人法抗) / 100);
    } else {
        hitTarget.损伤值 = 子弹.破坏力 * _root.防御减伤比(hitTarget.防御力);
    }

    var 伤害数字 = hitTarget.损伤值;
    var 伤害数字大小 = 计算结果.伤害数字大小;

    // ---- 多种特殊状态：跳弹、过穿、躲闪、格挡 等 ----
    switch (躲闪状态) {
        case "跳弹":
            伤害数字 = _root.跳弹伤害计算(伤害数字, hitTarget.防御力);
            hitTarget.损伤值 = 伤害数字;
            伤害数字大小 *= 0.3 + 0.7 * 伤害数字 / 子弹.破坏力;
            计算结果.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#7F6A00" : "#7F0000";
            break;
        case "过穿":
            伤害数字 = _root.过穿伤害计算(伤害数字, hitTarget.防御力);
            hitTarget.损伤值 = 伤害数字;
            伤害数字大小 *= 0.3 + 0.7 * 伤害数字 / 子弹.破坏力;
            计算结果.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#FFE770" : "#FF7F7F";
            break;
        case "躲闪":
        case "直感":
            伤害数字 = NaN;
            hitTarget.损伤值 = 0;
            伤害数字大小 *= 0.5;
            break;
        case "格挡":
            伤害数字 = hitTarget.受击反制(伤害数字, 子弹);
            if (伤害数字) {
                hitTarget.损伤值 = 伤害数字;
                伤害数字大小 *= 0.3 + 0.7 * hitTarget.损伤值 / 子弹.破坏力;
            } else if (伤害数字 === 0) {
                hitTarget.损伤值 = 0;
                伤害数字大小 *= 1.2;
            } else {
                伤害数字 = NaN;
                hitTarget.损伤值 = 0;
                伤害数字大小 *= 0.5;
            }
            break;
        default:
            伤害数字 = Math.max(Math.floor(伤害数字), 1);
            hitTarget.损伤值 = 伤害数字;
            _root.受击变红(120, hitTarget);
    }

    // ---- 计算实际消耗霰弹值 ----
    var 实际消耗霰弹值 = Math.min(
        子弹.霰弹值,
        Math.ceil(
            Math.min(
                子弹.最小霰弹值 + overlapRatio * ((子弹.霰弹值 - 子弹.最小霰弹值) + 1) * 1.2,
                hitTarget.hp / (hitTarget.损伤值 > 0 ? hitTarget.损伤值 : 1)
            )
        )
    );
    计算结果.实际消耗霰弹值 = 实际消耗霰弹值;

    if (子弹.联弹检测 && !子弹.穿刺检测) {
        子弹.霰弹值 -= 实际消耗霰弹值;
        计算结果.最终子弹霰弹值 = 子弹.霰弹值;
    }

    hitTarget.损伤值 *= 实际消耗霰弹值;
    伤害数字 *= 实际消耗霰弹值;

    // ---- 淬毒 / 毒返 ----
    var 淬毒量 = 0;
    if (子弹.nanoToxic > 0) {
        淬毒量 = 子弹.nanoToxic;
        if (子弹.普通检测) {
            淬毒量 *= 1;
        } else {
            淬毒量 *= 0.3;
        }
        子弹.附加层伤害计算 += 淬毒量;
    }
    if (淬毒量 > 0 && 伤害数字) {
        hitTarget.损伤值 += 淬毒量;
        伤害数字 = hitTarget.损伤值;
        计算结果.伤害字符 += '<font color="#66dd00" size="20"> 毒</font>';
        if (子弹.nanoToxicDecay && 子弹.近战检测 && shooter.淬毒 > 10) {
            shooter.淬毒 -= 子弹.nanoToxicDecay;
        }
        if (hitTarget.毒返 > 0) {
            var 毒返淬毒值 = 淬毒量 * hitTarget.毒返;
            if(hitTarget.毒返函数) {
                hitTarget.毒返函数(淬毒量, 毒返淬毒值);
            }
            hitTarget.淬毒 = 毒返淬毒值;
        }
    }

    // ---- 吸血 ----
    if (子弹.吸血 > 0 && hitTarget.损伤值 > 1) {
        var 吸血量 = Math.floor(Math.max(Math.min(hitTarget.损伤值 * 子弹.吸血 / 100, hitTarget.hp), 0));
        shooter.hp += Math.min(吸血量, shooter.hp满血值 * 1.5 - shooter.hp);
        计算结果.伤害字符 = '<font color="#bb00aa" size="15"> 汲:' + Math.floor(吸血量 / 实际消耗霰弹值).toString() + "</font>" + 计算结果.伤害字符;
    }

    // ---- 击溃 ----
    var 击溃量 = 0;
    if (子弹.击溃 > 0 && hitTarget.损伤值 > 1) {
        击溃量 = Math.floor(hitTarget.hp满血值 * 子弹.击溃 / 100);
        子弹.附加层伤害计算 += 击溃量;
        if (hitTarget.hp满血值 > 0) {
            hitTarget.hp满血值 -= 击溃量;
            hitTarget.损伤值 += 击溃量;
        }
        计算结果.伤害字符 += '<font color="#FF3333" size="20"> 溃</font>';
        伤害数字 = Math.floor(hitTarget.损伤值);
    }

    // ---- 斩杀 ----
    if (子弹.斩杀) {
        if (hitTarget.hp < hitTarget.hp满血值 * 子弹.斩杀 / 100) {
            hitTarget.损伤值 += hitTarget.hp; 
            hitTarget.hp = 0;
            计算结果.伤害字符 = 子弹.子弹敌我属性值 
                                ? '<font color="#4A0099" size="20"> 斩</font>'
                                : '<font color="#660033" size="20"> 斩</font>';
        }
        伤害数字 = Math.floor(hitTarget.损伤值);
    }

    // ---- 分段显示所需准备 ----
    计算结果.显示次数 = 实际消耗霰弹值;
    // 将初始伤害数字存下来，用于后续分段
    var 剩余伤害 = 伤害数字;
    
    // 这里并不调用显示函数，而是将所有分段伤害放到 计算结果.总伤害数字列表
    // 在后面“显示函数”里统一处理
    if (实际消耗霰弹值 > 1) {
        for (var i = 0; i < 实际消耗霰弹值 - 1; ++i) {
            var 波动伤害 = (剩余伤害 / (实际消耗霰弹值 - i)) * (100 + _root.随机偏移(50 / 实际消耗霰弹值)) / 100;
            波动伤害 = isNaN(波动伤害) ? 0 : 波动伤害; 
            计算结果.总伤害数字列表.push(Math.floor(波动伤害));
            剩余伤害 -= 波动伤害;
        }
    }
    // 剩下最后一次伤害
    计算结果.总伤害数字列表.push(isNaN(剩余伤害) ? 0 : Math.floor(剩余伤害));

    // 更新最终的伤害数字大小和颜色
    计算结果.伤害数字大小 = 伤害数字大小;
    
    // 记录目标受到的总伤害
    // 如果是 NaN 则说明 MISS
    hitTarget.hp = isNaN(hitTarget.损伤值) ? hitTarget.hp : Math.floor(hitTarget.hp - hitTarget.损伤值);
    hitTarget.hp = (hitTarget.hp < 0 || isNaN(hitTarget.hp)) ? 0 : hitTarget.hp;

    // 返回给显示函数
    return 计算结果;
};

// --------------------子弹伤害显示--------------------
// 专注于显示数字特效与构建伤害字符串
_root.子弹伤害显示 = function(hitTarget, 计算结果, 躲闪状态)
{
    // 分段伤害数字列表
    var 分段伤害列表 = 计算结果.总伤害数字列表;
    var 伤害数字颜色 = 计算结果.伤害数字颜色;
    var 伤害数字大小 = 计算结果.伤害数字大小;
    var 伤害字符 = 计算结果.伤害字符;
    
    // 根据躲闪状态判断是否显示 MISS
    var 躲闪状态字符 = "";
    // 在主逻辑中，当伤害为 NaN 时也会显示 MISS，这里统一处理
    // 但因为分段伤害在核心已经 split 完毕，这里只负责推入
    // 万一所有伤害都为 0 或 NaN，可根据具体需求自定义
    // 这里先跟原逻辑保持一致，保留 “MISS” 当某段伤害为 0
    // 后续需要考虑在这里做更细腻的判断。
    // 包括且不限于，对联弹造成的伤害，使用滚动式刷新的数字，以节约特效数量

    // 分段显示
    for (var i = 0; i < 分段伤害列表.length; i++) {
        var 本段伤害 = 分段伤害列表[i];
        var 显示数字;
        if (本段伤害 <= 0) {
            显示数字 = '<font color="' + 伤害数字颜色 + '" size="' + 伤害数字大小 + '">MISS</font>';
        } else {
            显示数字 = '<font color="' + 伤害数字颜色 + '" size="' + 伤害数字大小 + '">' 
                      + 躲闪状态字符 
                      + Math.floor(本段伤害) 
                      + "</font>";
        }
        _root.打击数字特效("", 显示数字 + 伤害字符, hitTarget._x, hitTarget._y);
    }
};

// --------------------子弹伤害结算（主函数）--------------------
// 继续保留原本的入口，但在里面调用 核心计算函数 和 显示函数。
_root.子弹伤害结算 = function(子弹, shooter, hitTarget, overlapRatio, 消耗霰弹值, 躲闪状态, overlapCenter)
{
    // 调用 核心伤害计算函数
    var 计算结果 = _root.子弹伤害结算核心(
        子弹, 
        shooter, 
        hitTarget, 
        overlapRatio, 
        消耗霰弹值, 
        躲闪状态
    );

    // 调用 显示函数
    _root.子弹伤害显示(
        hitTarget, 
        计算结果, 
        躲闪状态
    );

    // 判断是否为当前玩家，需要刷新血条显示
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
            var 躲闪状态 = this.伤害类型 == "真伤" ? "未躲闪": _root.躲闪状态计算(hitTarget,_root.根据命中计算闪避结果(shooter, hitTarget, 命中率),this);

            // 调用伤害结算函数
            var 消耗霰弹值 = 1; // 在伤害计算中实际会重新计算

            if(子弹.击中时触发函数) 子弹.击中时触发函数();

            _root.子弹伤害结算(this, shooter, hitTarget, overlapRatio, 消耗霰弹值, 躲闪状态, overlapCenter);

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
                else if (躲闪状态 == "躲闪")
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



_root.子弹区域shoot表演 = function(声音, 霰弹值, 子弹散射度, 发射效果, 子弹种类, 子弹威力, 子弹速度, Z轴攻击范围, 击中地图效果, 发射者, shootX, shootY, shootZ, 子弹敌我属性, 击倒率, 击中后子弹的效果)
{
	if (_root.暂停 == false)
	{
		if (_root.控制目标全自动 == false and _root.控制目标 == _root.gameworld[发射者]._name)
		{
			if (_root.gameworld[发射者]._xscale > 0)
			{
				if (Key.isDown(_root.下键))
				{
					射击角度 = 30;
				}
				else if (Key.isDown(_root.上键))
				{
					射击角度 = 330;
				}
				else
				{
					射击角度 = 0;
				}
			}
			else if (Key.isDown(_root.下键))
			{
				射击角度 = 150;
			}
			else if (Key.isDown(_root.上键))
			{
				射击角度 = 210;
			}
			else
			{
				射击角度 = 180;
			}
		}
		else if (_root.gameworld[发射者]._xscale > 0)
		{
			射击角度 = 0;
		}
		else
		{
			射击角度 = 180;
		}
		f_name = "f" + depth;
		_root.gameworld.效果.attachMovie(发射效果,f_name,random(20));
		_root.gameworld.效果[f_name]._xscale = _root.gameworld[发射者]._xscale;
		_root.gameworld.效果[f_name]._x = shootX;
		_root.gameworld.效果[f_name]._y = shootY;
		_root.播放音效(声音);
		i = 1;
		while (i <= 霰弹值)
		{
			depth++;
			if (depth > 100)
			{
				depth = 0;
			}
			if (random(2) == 0)
			{
				散射角度 = 射击角度 - random(子弹散射度);
			}
			else
			{
				散射角度 = 射击角度 + random(子弹散射度);
			}
			angle = 散射角度 * 3.14 / 180;
			b_name = 发射者 + "zidan" + depth + 散射角度;
			_root.gameworld.子弹区域.attachMovie(子弹种类,b_name,_root.gameworld.子弹区域.getNextHighestDepth(),{_rotation:散射角度, _x:shootX, _y:shootY});
			_root.gameworld.子弹区域[b_name].发射者名 = 发射者;
			_root.gameworld.子弹区域[b_name].子弹敌我属性值 = 子弹敌我属性;
			_root.gameworld.子弹区域[b_name].子弹威力 = 子弹威力;
			_root.gameworld.子弹区域[b_name].Z轴坐标 = shootZ;
			_root.gameworld.子弹区域[b_name].xmov = 子弹速度 * Math.cos(angle);
			_root.gameworld.子弹区域[b_name].ymov = 子弹速度 * Math.sin(angle);
			_root.gameworld.子弹区域[b_name].onEnterFrame = function()
			{
				var _loc3_ = {x:0, y:0};
				this.localToGlobal(_loc3_);
				for (each in _root.gameworld)
				{
					if (_root.gameworld[each].是否允许发送联机数据 == true)
					{
						if (_root.gameworld[each].是否为敌人 == 子弹敌我属性 and _root.gameworld[each]._name != 发射者 and _root.gameworld[each].area.hitTest(this.area) == true and Math.abs(this.Z轴坐标 - _root.gameworld[each].Z轴坐标) < Z轴攻击范围)
						{
							_root.gameworld[each].攻击目标 = _root.gameworld[发射者]._name;
							if (_root.gameworld[each]._name === _root.控制目标)
							{
								_root.玩家信息界面.刷新hp显示();
							}
							被击移动速度 = 10;
							if (_root.血腥开关 == true)
							{
								if (_root.gameworld[each].击中效果 == "飙血")
								{
									临时效果名 = 效果("子弹碎片-飞血", this._x, _root.gameworld[each]._y, _root.gameworld[发射者]._xscale);
									_root.gameworld.效果[临时效果名].出血来源 = each;
								}
								else if (_root.gameworld[each].击中效果 == "异形飙血")
								{
									临时效果名 = 效果("子弹碎片-异形飞血", this._x, _root.gameworld[each]._y, _root.gameworld[发射者]._xscale);
									_root.gameworld.效果[临时效果名].出血来源 = each;
								}
							}
							效果(_root.gameworld[each].击中效果,this._x,this._y,_root.gameworld[发射者]._xscale);
							效果(击中后子弹的效果,this._x,this._y,_root.gameworld[发射者]._xscale);
							if (子弹种类 != "近战子弹")
							{
								this.gotoAndPlay("消失");
							}
						}
					}
				}
				if (this._y > this.Z轴坐标 and 子弹种类 != "近战子弹" )
				{
					效果(击中地图效果,this._x,this._y);
					this.gotoAndPlay("消失");
				}
				if (_root.gameworld.地图.hitTest(_loc3_.x, _loc3_.y, true))
				{
					效果(击中地图效果,this._x,this._y);
					子弹碎片depth = random(50);
					子弹碎片b_name = "zidan子弹碎片" + 子弹碎片depth;
					_root.gameworld.效果.attachMovie("子弹碎片",子弹碎片b_name,_root.gameworld.效果.getNextHighestDepth(),{_x:this._x, _y:this._y});
					this.gotoAndPlay("消失");
				}
				this._x += this.xmov;
				this._y += this.ymov;
				if (Math.abs(this._x - _root.gameworld[发射者]._x) > 800 || Math.abs(this._y - _root.gameworld[发射者]._y) > 800)
				{
					this.removeMovieClip();
				}
			};
			i++;
		}
	}
};



// 初始化函数

_root.子弹属性初始化 = Delegate.create(BulletAttributesFactory, BulletAttributesFactory.initializeFromMovieClip);

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






