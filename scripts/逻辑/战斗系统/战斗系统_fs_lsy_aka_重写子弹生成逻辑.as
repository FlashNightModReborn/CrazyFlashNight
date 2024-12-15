import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;

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
    var 发射对象 = 游戏世界[Obj.发射者];

    // 计算射击角度
    var 射击角度 = 计算射击角度(Obj, 发射对象);

    // 创建发射效果和音效
    _root.创建发射效果(Obj, 发射对象);

    // 设置子弹类型标志
    BulletTypesetter.setTypeFlags(Obj);

    // 设置默认值
    _root.设置默认值(Obj, 发射对象);

    // 继承发射者属性
    _root.继承发射者属性(Obj, 发射对象);

    // 计算击退速度
    _root.计算击退速度(Obj);

    // 初始化子弹属性
    _root.初始化子弹属性(Obj);

    // 创建子弹
    var 子弹实例 = 创建子弹(Obj, 发射对象, 射击角度);

    return 子弹实例;
};

_root.计算射击角度 = function(Obj, 发射对象){
    Obj.角度偏移 = isNaN(Obj.角度偏移) ? 0 : Number(Obj.角度偏移);
    var 基础射击角度:Number = 0;
    var 发射方向 = 发射对象.方向;
    if (Obj.子弹速度 < 0) {
        Obj.子弹速度 *= -1;
        发射方向 = 发射方向 === "右" ? "左" : "右";
    }
    if(发射方向 === "左") {
        基础射击角度 = 180;
        Obj.角度偏移 = -Obj.角度偏移;
    }
    var 射击角度 = 基础射击角度 + 发射对象._rotation + Obj.角度偏移;
    return 射击角度;
}

_root.创建发射效果 = function(Obj, 发射对象){
    var 游戏世界 = _root.gameworld;
    var depth = _root.随机整数(0, _root.发射效果上限);
    var f_name = "f" + depth;
    var 发射效果对象 = 游戏世界.效果.attachMovie(Obj.发射效果, f_name, depth, {
        _xscale: 发射对象._xscale,
        _x: Obj.shootX,
        _y: Obj.shootY,
        _rotation: Obj.角度偏移
    });
    ShellSystem.launchShell(Obj.子弹种类, Obj.shootX, Obj.shootY, 发射对象._xscale);
    _root.播放音效(Obj.声音);
}

_root.设置默认值 = function(Obj, 发射对象){
    Obj.固伤 = isNaN(Obj.固伤) ? 0 : Obj.固伤;
    Obj.命中率 = isNaN(Obj.命中率) ? 发射对象.命中率 : Obj.命中率;
    Obj.最小霰弹值 = isNaN(Obj.最小霰弹值) ? 1 : Obj.最小霰弹值;
    Obj.远距离不消失 = Obj.手雷检测 || Obj.爆炸检测;
}

_root.继承发射者属性 = function(Obj, 发射对象){
    Obj.伤害类型 = !Obj.伤害类型 && 发射对象.伤害类型 ? 发射对象.伤害类型 : Obj.伤害类型;
    Obj.魔法伤害属性 = !Obj.魔法伤害属性 && 发射对象.魔法伤害属性 ? 发射对象.魔法伤害属性 : Obj.魔法伤害属性;
    Obj.吸血 = Obj.吸血 || 发射对象.吸血 ? Math.max((isNaN(Obj.吸血) ? 0 : Obj.吸血), (isNaN(发射对象.吸血) ? 0 : 发射对象.吸血)) : Obj.吸血;
    Obj.击溃 = Obj.血量上限击溃 || 发射对象.击溃 ? Math.max((isNaN(Obj.血量上限击溃) ? 0 : Obj.血量上限击溃), (isNaN(发射对象.击溃) ? 0 : 发射对象.击溃)) : Obj.血量上限击溃;
}

_root.计算击退速度 = function(Obj){
    Obj.水平击退速度 = (isNaN(Obj.水平击退速度) || Obj.水平击退速度 < 0) ? 10 : Math.min(Obj.水平击退速度, _root.最大水平击退速度);
    Obj.垂直击退速度 = isNaN(Obj.垂直击退速度) ? 0 : Math.min(Obj.垂直击退速度, _root.最大垂直击退速度);
}

_root.初始化子弹属性 = function(Obj){
    Obj.发射者名 = Obj.发射者;
    Obj.子弹敌我属性值 = Obj.子弹敌我属性;
    Obj._x = Obj.shootX;
    Obj._y = Obj.shootY;
    Obj.Z轴坐标 = Obj.shootZ;
    Obj.子弹区域area = Obj.区域定位area;
}

_root.创建子弹 = function(Obj, 发射对象, 射击角度){
    var 游戏世界 = _root.gameworld;
    var 子弹总数 = Obj.联弹检测 ? 1 : Obj.霰弹值;
    var 子弹实例;
    if(Obj.联弹检测) {
        Obj.子弹实例种类 = Obj.子弹种类.split("-")[0];
        Obj.联弹霰弹值 = Obj.霰弹值;
    } else {
        Obj.子弹实例种类 = Obj.子弹种类;
        Obj.联弹霰弹值 = 1;
    }
    for (var 子弹计数 = 0; 子弹计数 < 子弹总数; 子弹计数++) {
        子弹实例 = 创建子弹实例(Obj, 发射对象, 射击角度);
    }
    return 子弹实例;
}

_root.创建子弹实例 = function(Obj, 发射对象, 射击角度){
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
    var 子弹实例;
    if(Obj.透明检测){
        子弹实例 = _root.对象浅拷贝(Obj);
    } else {
        _root.子弹生成计数 = (_root.子弹生成计数 + 1) % 100;
        var depth = 游戏世界.子弹区域.getNextHighestDepth();
        var b_name = Obj.发射者名 + Obj.子弹种类 + depth + 散射角度 + _root.子弹生成计数;
        子弹实例 = 游戏世界.子弹区域.attachMovie(Obj.子弹实例种类, b_name, depth, Obj);
    }
    子弹实例.xmov = 子弹实例.子弹速度 * Math.cos(angle);
    子弹实例.ymov = 子弹实例.子弹速度 * Math.sin(angle);
    子弹实例.霰弹值 = Obj.联弹检测 ? Obj.霰弹值 : 1;

    设置毒属性(Obj, 子弹实例, 发射对象);
    指定生命周期函数(子弹实例);

	// 创建子弹移动逻辑实例
	var movement:LinearBulletMovement = LinearBulletMovement.create(子弹实例.速度X, 子弹实例.速度Y, 子弹实例.ZY比例);

	// 创建生命周期逻辑实例
	var lifecycle:BulletLifecycle = new BulletLifecycle(900); // 当前射程阈值为900

	// 将 updateMovement 方法绑定到子弹实例
	子弹实例.updateMovement = Delegate.create(movement, movement.updateMovement);

	// 将 shouldDestroy 方法绑定到子弹实例
	子弹实例.shouldDestroy = Delegate.create(lifecycle, lifecycle.shouldDestroy);


    return 子弹实例;
}

_root.设置毒属性 = function(Obj, 子弹实例, 发射对象){
    if(Obj.毒 || 发射对象.淬毒 || 发射对象.毒) {
        var 发射者淬毒 = isNaN(发射对象.淬毒) ? 0 : 发射对象.淬毒;
        Obj.毒 = Math.max((isNaN(Obj.毒) ? 0 : Obj.毒), (isNaN(发射对象.毒) ? 0 : 发射对象.毒));
        if(发射者淬毒 && 发射者淬毒 > Obj.毒) {
            子弹实例.毒 = 发射者淬毒;
            子弹实例.淬毒衰减 = 1;
            if(!子弹实例.近战检测 && 发射对象.淬毒 > 10) {
                发射对象.淬毒 -= 1;
            }
        } else {
            子弹实例.毒 = Obj.毒;
        }
    }
}

_root.指定生命周期函数 = function(子弹实例){
    if(子弹实例.透明检测){
        子弹实例.子弹生命周期 = _root.子弹生命周期;
        子弹实例.子弹生命周期();
    } else {
        子弹实例.onEnterFrame = _root.子弹生命周期;
    }
}


// 伤害结算函数
_root.子弹伤害结算 = function(子弹, 发射对象, 命中对象, 覆盖率, 消耗霰弹值, 躲闪状态, 碰撞中心)
{
    // 以下代码为原先伤害计算部分的逻辑，仅将所有 this 替换为 子弹，并使用传入的参数
    // 保持代码逻辑与原有一致
    // --------------------伤害结算开始--------------------
    if(命中对象.无敌 || 命中对象.man.无敌标签 || 命中对象.NPC){
        if(子弹.击中时触发函数){
            子弹.击中时触发函数();
        }
    } else if (命中对象.hp != 0) {
        var 伤害字符 = "";
        var 伤害数字颜色 = 子弹.子弹敌我属性值 ? "#FFCC00" : "#FF0000";

        命中对象.防御力 = isNaN(命中对象.防御力) ? 1 : Math.min(命中对象.防御力, 99000);
        if(子弹.击中时触发函数){
            子弹.击中时触发函数();
        }

        子弹.破坏力 = Number(子弹.子弹威力) + (isNaN(发射对象.伤害加成) ? 0 : 发射对象.伤害加成);
        var 伤害波动数字 = 子弹.破坏力 * ((!_root.调试模式 || 子弹.霰弹值 > 1) ? (0.85 + _root.basic_random() * 0.3) : 1);
        var 百分比伤 = isNaN(子弹.百分比伤害) ? 0 : 命中对象.hp * 子弹.百分比伤害 / 100;
        子弹.破坏力 = 伤害波动数字 + 子弹.固伤 + 百分比伤;

        if(子弹.暴击){
            子弹.破坏力 = 子弹.破坏力 * 子弹.暴击(子弹);
        }

        if(子弹.伤害类型 === "真伤"){
            伤害数字颜色 = 子弹.子弹敌我属性值 ? "#4A0099" : "#660033";
            伤害字符 += '<font color="'+伤害数字颜色+'" size="20"> 真</font>';
            命中对象.损伤值 = 子弹.破坏力;
        } else if(子弹.伤害类型 === "魔法"){
            伤害数字颜色 = 子弹.子弹敌我属性值 ? "#0099FF" : "#AC99FF";
            var 魔法伤害属性字符 = 子弹.魔法伤害属性 ? 子弹.魔法伤害属性 : "能";
            伤害字符 += '<font color="' + 伤害数字颜色 + '" size="20"> ' + 魔法伤害属性字符 + '</font>';
            var 敌人法抗 = 子弹.魔法伤害属性 ? (命中对象.魔法抗性 && (命中对象.魔法抗性[子弹.魔法伤害属性] || 命中对象.魔法抗性[子弹.魔法伤害属性]===0) ? 命中对象.魔法抗性[子弹.魔法伤害属性]: (命中对象.魔法抗性 && (命中对象.魔法抗性["基础"] ||命中对象.魔法抗性["基础"]===0) ? 命中对象.魔法抗性["基础"]: 10 +命中对象.等级 / 2 )  ):(命中对象.魔法抗性 && (命中对象.魔法抗性["基础"] || 命中对象.魔法抗性["基础"]===0) ? 命中对象.魔法抗性["基础"]: 10 +命中对象.等级 / 2 );
            敌人法抗 = isNaN(敌人法抗) ? 20:Math.min(Math.max(敌人法抗,-1000),100);
            命中对象.损伤值 = Math.floor(子弹.破坏力 *(100 - 敌人法抗) / 100);
        } else {
            命中对象.损伤值 = 子弹.破坏力 * _root.防御减伤比(命中对象.防御力);
        }

        子弹.附加层伤害计算 = 0;
        var 淬毒量 = 0;       
        var 击溃量 = 0;
        var 淬毒数值 = 子弹.淬毒;
        var 子弹霰弹值 = 子弹.霰弹值;
        if (子弹.淬毒 > 0)
        {
            淬毒量 = 子弹.淬毒;
            if(子弹.普通检测){
                淬毒量 *= 1;
            }else{
                淬毒量 *= 0.3;
            }
            子弹.附加层伤害计算 += 淬毒量;
        }

        if (子弹.击溃 > 0 && 命中对象.hp满血值 > 0)
        {
            击溃量 = Math.floor(命中对象.hp满血值 * 子弹.击溃 / 100);
            子弹.附加层伤害计算 += 击溃量;
        }

        var 伤害数字 = 命中对象.损伤值;
        var 伤害数字大小 = 28;
        var 显示数字;

        var 躲闪状态字符 = "";
        // 躲闪状态逻辑保持不变
        switch (躲闪状态)
        {
            case "跳弹" :
                伤害数字 = _root.跳弹伤害计算(伤害数字, 命中对象.防御力);
                命中对象.损伤值 = 伤害数字;
                伤害数字大小 *= 0.3 + 0.7 * 伤害数字 / 子弹.破坏力;
                伤害数字颜色 = 子弹.子弹敌我属性值 ? "#7F6A00" : "#7F0000";
                break;
            case "过穿" :
                伤害数字 = _root.过穿伤害计算(伤害数字, 命中对象.防御力);
                命中对象.损伤值 = 伤害数字;
                伤害数字大小 *= 0.3 + 0.7 * 伤害数字 / 子弹.破坏力;
                伤害数字颜色 = 子弹.子弹敌我属性值 ? "#FFE770" : "#FF7F7F";
                break;
            case "躲闪" :
            case "直感" :
                伤害数字 = NaN;
                命中对象.损伤值 = 0;
                伤害数字大小 *= 0.5;
                break;
            case "格挡" :
                伤害数字 = 命中对象.受击反制(伤害数字,子弹);
                if(伤害数字){
                    命中对象.损伤值 = 伤害数字;
                    伤害数字大小 *= 0.3 + 0.7 * 命中对象.损伤值 / 子弹.破坏力;
                }else if(伤害数字 === 0){
                    命中对象.损伤值 = 0;
                    伤害数字大小 *= 1.2;
                }else{
                    伤害数字 = NaN;
                    命中对象.损伤值 = 0;
                    伤害数字大小 *= 0.5;
                }
                break;
            default :
                伤害数字 = Math.max(Math.floor(伤害数字), 1);
                命中对象.损伤值 = 伤害数字;
                _root.受击变红(120,命中对象);
        }

        var 实际消耗霰弹值 = Math.min(子弹.霰弹值,Math.ceil(Math.min(子弹.最小霰弹值 + 覆盖率 * ((子弹.霰弹值-子弹.最小霰弹值) + 1) * 1.2,命中对象.hp / 命中对象.损伤值)));
        if (子弹.联弹检测 && !子弹.穿刺检测) {
            子弹.霰弹值 -= 实际消耗霰弹值;
        }

        命中对象.损伤值 *= 实际消耗霰弹值;
        伤害数字 *= 实际消耗霰弹值;

        if (淬毒量 > 0 && 伤害数字)
        {
            命中对象.损伤值 += 淬毒量;
            伤害数字 = 命中对象.损伤值;
            伤害字符 += '<font color="#66dd00" size="20"> 毒</font>';
            if(子弹.淬毒衰减 && 子弹.近战检测 && 发射对象.淬毒 > 10){
                发射对象.淬毒 -= 子弹.淬毒衰减;
            }
            if (命中对象.毒返 > 0)
            {
                var 毒返淬毒值 = 淬毒量 * 命中对象.毒返;
                if(命中对象.毒返函数){
                    命中对象.毒返函数(淬毒量, 毒返淬毒值);
                }
                命中对象.淬毒 = 毒返淬毒值;
            }
        }

        if (子弹.吸血 > 0 && 命中对象.损伤值 > 1)
        {
            var 吸血量 = Math.floor(Math.max(Math.min(命中对象.损伤值 * 子弹.吸血 /100, 命中对象.hp), 0));
            发射对象.hp += Math.min(吸血量,发射对象.hp满血值 * 1.5 - 发射对象.hp);
            伤害字符 = '<font color="#bb00aa" size="15"> 汲:'+ Math.floor(吸血量 / 实际消耗霰弹值).toString() +"</font>" + 伤害字符;
        }

        if (子弹.击溃 > 0 && 命中对象.损伤值 > 1)
        {
            击溃量 = 击溃量 && !isNaN(击溃量) ? 击溃量 : 1;
            if(命中对象.hp满血值 > 0){
                命中对象.hp满血值 -= 击溃量;
                命中对象.损伤值 += 击溃量;
            }
            伤害字符 += '<font color="#FF3333" size="20"> 溃</font>';
            伤害数字 = Math.floor(命中对象.损伤值);
        }

        if(子弹.斩杀){
            if(命中对象.hp < 命中对象.hp满血值 * 子弹.斩杀 / 100){
                命中对象.损伤值 += 命中对象.hp;
                命中对象.hp = 0;
                伤害字符 = 子弹.子弹敌我属性值 ? '<font color="#4A0099" size="20"> 斩</font>' : '<font color="#660033" size="20"> 斩</font>';
            }
            伤害数字 = Math.floor(命中对象.损伤值);
        }

        if (实际消耗霰弹值 > 1)
        {
            for (var 联弹索引 = 0; 联弹索引 < 实际消耗霰弹值 - 1; ++联弹索引)
            {
                var 波动伤害 = (伤害数字 / (实际消耗霰弹值 - 联弹索引)) * (100 + _root.随机偏移(50 / 实际消耗霰弹值)) / 100;
                伤害数字 -= 波动伤害;
                显示数字 = '<font color="' + 伤害数字颜色 + '" size="' + 伤害数字大小 + '">' + 躲闪状态字符 + (isNaN(波动伤害) ? "MISS" : Math.floor(波动伤害)) + "</font>";
                _root.打击数字特效("", 显示数字 + 伤害字符,命中对象._x,命中对象._y);
            }
        }

        显示数字 = '<font color="' + 伤害数字颜色 + '" size="' + 伤害数字大小 + '">' + 躲闪状态字符 + (isNaN(伤害数字) ? "MISS" : Math.floor(伤害数字)) +  "</font>";
        _root.打击数字特效("",显示数字 + 伤害字符,命中对象._x,命中对象._y);
        命中对象.hp = isNaN(命中对象.损伤值) ? 命中对象.hp : Math.floor(命中对象.hp - 命中对象.损伤值);
    }

    命中对象.hp = (命中对象.hp < 0 || isNaN(命中对象.hp)) ? 0 : 命中对象.hp;

    if (命中对象._name === _root.控制目标)
    {
        _root.玩家信息界面.刷新hp显示();
    }

    //伤害结算完毕
    // --------------------伤害结算结束--------------------
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
    var areaAABB:Object;
    var bullet_rotation:Number = this._rotation; // 本地化避免多次访问造成getter开销
    var isRotated:Boolean = (bullet_rotation != 0 && bullet_rotation != 180);
    var isPointSet:Boolean = this.联弹检测 && isRotated;
    var isAxisAlignedChain = this.联弹检测 && !isRotated;

    if (this.透明检测 && !this.子弹区域area) {
        areaAABB = isAxisAlignedChain ? CoverageAABBCollider.fromTransparentBullet(this) : AABBCollider.fromTransparentBullet(this);
    } else {
        detectionArea = this.子弹区域area || this.area;
        areaAABB = isAxisAlignedChain ? CoverageAABBCollider.fromBullet(this, detectionArea) : AABBCollider.fromBullet(this, detectionArea);
    }


    
    var area面积, 击中矩形, 击中点集, area点集边向量;
    if(isPointSet)
    {
        var area点集 = _root.影片剪辑至游戏世界点集(detectionArea);
        area面积 = _root.点集面积系数(area点集);
        area点集边向量 = [];
        var 击中点集;
    }
    else
    {
        击中矩形 = {};
        area面积 = _root.calculateRectArea(areaAABB);
    }

    if (_root.调试模式)
    {
        _root.绘制线框(detectionArea);
    }
    var 游戏世界 = _root.gameworld;
    var 发射对象 = 游戏世界[this.发射者名];
    var 遍历敌人表 = _root.帧计时器.获取敌人缓存(发射对象,5);
    if(this.友军伤害){
        var 遍历友军表 = _root.帧计时器.获取友军缓存(发射对象,5);
        遍历敌人表 = 遍历敌人表.concat(遍历友军表);
    }
    var 击中次数 = 0;
    var 是否生成击中后效果 = true;

    for (var i = 0; i < 遍历敌人表.length ; ++i)
    {
        this.命中对象 = 遍历敌人表[i];
        var Z轴坐标差 = this.命中对象.Z轴坐标 - this.Z轴坐标;

        if (Math.abs(Z轴坐标差) >= this.Z轴攻击范围 || !(this.命中对象.是否为敌人 == this.子弹敌我属性值))
        {
            continue;
        }
        if ((this.命中对象._name != this.发射者名 || this.友军伤害) && this.命中对象.防止无限飞 != true || (this.命中对象.hp <= 0 && !this.近战检测))
        {
            var 覆盖率 = 1;
            var 碰撞中心;

            var result:CollisionResult = areaAABB.checkCollision(AABBCollider.fromUnitArea(this.命中对象), Z轴坐标差);
            if (result.isColliding) {
                if (this.联弹检测) {
                    if(isPointSet){
                        击中点集 = _root.点集碰撞检测(area点集, this.命中对象.area, area点集边向量,Z轴坐标差);
                        if(击中点集.length < 3)
                        {
                            continue;
                        }
                        覆盖率 = _root.点集面积系数(击中点集) / area面积;
                        碰撞中心 = {x:this._x,y:this._y};
                    }
                    else{
                        覆盖率 = result.overlapRatio;
                        碰撞中心 = result.overlapCenter;
                    }
                }else{
                    碰撞中心 = result.overlapCenter;
                }
            } else {
                continue;
            }

            //击中
            击中次数++;
            if(_root.调试模式)
            {
                _root.绘制线框(this.命中对象.area);
            }
            var 命中对象血槽 = this.命中对象.新版人物文字信息 ? this.命中对象.新版人物文字信息.头顶血槽 : this.命中对象.人物文字信息.头顶血槽;
            命中对象血槽._visible = true;
            命中对象血槽.gotoAndPlay(2);
            this.命中对象.攻击目标 = 发射对象._name;

            _root.冲击力刷新(this.命中对象);

            // 命中率计算略，原代码有提到根据命中率计算闪避
            var 躲闪状态 = this.伤害类型 == "真伤" ? "未躲闪": _root.躲闪状态计算(this.命中对象,_root.根据命中计算闪避结果(发射对象, this.命中对象, 命中率),this);

            // 调用伤害结算函数
            var 消耗霰弹值 = 1; // 在伤害计算中实际会重新计算
            _root.子弹伤害结算(this, 发射对象, this.命中对象, 覆盖率, 消耗霰弹值, 躲闪状态, 碰撞中心);

            //伤害结算结束后，继续原逻辑
            if(!this.近战检测 && !this.爆炸检测 && this.命中对象.hp <= 0)
            {
                this.命中对象.状态改变("血腥死");
            }

            var 被击方向 = (this.命中对象._x < 发射对象._x) ? "左" : "右" ;
            if(this.水平击退反向){
                被击方向 = 被击方向 === "左" ? "右" : "左";
            }
            this.命中对象.方向改变(被击方向 === "左" ? "右" : "左");

            if (_root.血腥开关)
            {
                var 子弹效果碎片 = "";
                switch (this.命中对象.击中效果)
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
                    var 效果对象 = _root.效果(子弹效果碎片, 碰撞中心.x, 碰撞中心.y, 发射对象._xscale);
                    效果对象.出血来源 = this.命中对象._name;
                }
            }

            var 刚体检测 = this.命中对象.刚体 || this.命中对象.man.刚体标签;
            if (!this.命中对象.浮空 && !this.命中对象.倒地)
            {
                _root.冲击力结算(this.命中对象.损伤值,this.击倒率,this.命中对象);
                this.命中对象.血条变色状态 = "常态";

                if (!isNaN(this.命中对象.hp) && this.命中对象.hp <= 0)
                {
                    this.命中对象.状态改变(_root.血腥开关 ? "血腥死" : "击倒");
                }
                else if (躲闪状态 == "躲闪")
                {
                    this.命中对象.被击移动(被击方向,this.水平击退速度,3);
                }
                else
                {
                    if (this.命中对象.残余冲击力 > this.命中对象.韧性上限)
                    {
                        if (!刚体检测)
                        {
                            this.命中对象.状态改变("击倒");
                            this.命中对象.血条变色状态 = "击倒";
                        }
                        this.命中对象.残余冲击力 = 0;
                        this.命中对象.被击移动(被击方向,this.水平击退速度,0.5);
                    }
                    else if (this.命中对象.残余冲击力 > this.命中对象.韧性上限 / _root.踉跄判定 / this.命中对象.躲闪率)
                    {
                        if (!刚体检测)
                        {
                            this.命中对象.状态改变("被击");
                            this.命中对象.血条变色状态 = "被击";
                        }

                        this.命中对象.被击移动(被击方向,this.水平击退速度,2);
                    }
                    else
                    {
                        this.命中对象.被击移动(被击方向,this.水平击退速度,3);
                    }
                }
            }
            else
            {
                this.命中对象.残余冲击力 = 0;
                if (!刚体检测)
                {
                    this.命中对象.状态改变("击倒");
                    this.命中对象.血条变色状态 = "击倒";
                    if (!(this.垂直击退速度 > 0))
                    {
                        var y速度 = 5;
                        this.命中对象.man.垂直速度 = -y速度;
                    }
                }
                this.命中对象.被击移动(被击方向,this.水平击退速度,0.5);
            }

            if(!this.近战检测 && !this.爆炸检测 && this.命中对象.hp <= 0)
            {
                this.命中对象.状态改变("血腥死");
            }

            switch (this.命中对象.血条变色状态)
            {
                case "常态": _root.重置色彩(命中对象血槽);
                    break;
                default: _root.暗化色彩(命中对象血槽);
            }

            _root.效果(this.命中对象.击中效果, 碰撞中心.x, 碰撞中心.y, 发射对象._xscale);
            if(this.命中对象.击中效果 == this.击中后子弹的效果) {
                是否生成击中后效果 = false;
            }

            if (this.近战检测 && !this.不硬直)
            {
                发射对象.硬直(发射对象.man,_root.钝感硬直时间);
            }
            else if(!this.穿刺检测)
            {
                this.gotoAndPlay("消失");
            }

            if (this.垂直击退速度 > 0)
            {
                this.命中对象.man.play();
                clearInterval(this.命中对象.pauseInterval);
                this.命中对象.硬直中 = false;
                clearInterval(this.命中对象.pauseInterval2);

                _root.fly(this.命中对象,this.垂直击退速度,0);
            }
        }
    }

    if(是否生成击中后效果 && 击中次数 > 0){
        _root.效果(this.击中后子弹的效果,this._x,this._y,发射对象._xscale);
    }

    // 调用更新运动逻辑
    this.updateMovement(this);

    // 检查是否需要销毁
    if (this.shouldDestroy(this)) {
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



//将传递参数改为对象，需要严格对应属性名，使用格式详情见下方注释
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






