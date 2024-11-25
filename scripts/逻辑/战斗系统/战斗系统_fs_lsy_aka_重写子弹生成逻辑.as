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
    创建发射效果(Obj, 发射对象);

    // 设置子弹类型标志
    设置子弹类型标志(Obj);

    // 设置默认值
    设置默认值(Obj, 发射对象);

    // 继承发射者属性
    继承发射者属性(Obj, 发射对象);

    // 计算击退速度
    计算击退速度(Obj);

    // 初始化子弹属性
    初始化子弹属性(Obj);

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
    _root.弹壳系统.发射弹壳(Obj.子弹种类, Obj.shootX, Obj.shootY, 发射对象._xscale);
    _root.播放音效(Obj.声音);
}

_root.设置子弹类型标志 = function(Obj){
    Obj.近战检测 = Obj.子弹种类.indexOf("近战") != -1;
    Obj.联弹检测 = Obj.子弹种类.indexOf("联弹") != -1;
    Obj.穿刺检测 = Obj.穿刺检测 || Obj.子弹种类.indexOf("穿刺") != -1;
    Obj.透明检测 = Obj.透明检测 || Obj.子弹种类 === "近战子弹" || Obj.子弹种类 === "近战联弹" || Obj.子弹种类 === "透明子弹";
    Obj.手雷检测 = Obj.手雷检测 || Obj.子弹种类.indexOf("手雷") != -1;
    Obj.爆炸检测 = Obj.爆炸检测 || Obj.子弹种类.indexOf("爆炸") != -1;
    Obj.普通检测 = !Obj.穿刺检测 && !Obj.爆炸检测 && (Obj.近战检测 || Obj.透明检测 || Obj.子弹种类.indexOf("普通") > -1 || Obj.子弹种类.indexOf("能量子弹") > -1 || Obj.子弹种类 == "精制子弹");
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


_root.子弹生命周期 = function() {
    if (_root.是否需要提前返回(this)) {
        _root.子弹基础运动控制(this);
        return;
    }

    _root.设置子弹碰撞区域(this);

    _root.设置碰撞检测标志(this);

    if (_root.调试模式) {
        _root.绘制线框(this.检测area);
    }

    var 发射对象 = _root.gameworld[this.发射者名];
    var 遍历敌人表 = _root.获取遍历敌人表(this, 发射对象);

    var 击中次数 = 0;
    var 是否生成击中后效果 = true;

    for (var i = 0; i < 遍历敌人表.length; ++i) {
        this.命中对象 = 遍历敌人表[i];
        if (_root.是否有效目标(this)) {
            if (_root.检测碰撞并处理(this, 发射对象)) {
                击中次数++;
            }
        }
    }

    if (是否生成击中后效果 && 击中次数 > 0) {
        _root.生成击中后效果(this, 发射对象);
    }

    if (_root.检测子弹击中地图(this)) {
        this.gotoAndPlay("消失");
    }

    _root.子弹基础运动控制(this);
};

_root.是否需要提前返回 = function(子弹) {
    if (!子弹.area && !子弹.透明检测) {
        return true;
    }
    return false;
};

_root.设置子弹碰撞区域 = function(子弹) {
    var 检测area;
    var area线框;
    if (子弹.透明检测 && !子弹.子弹区域area) {
        area线框 = {left: 子弹._x - 12.5, right: 子弹._x + 12.5, top: 子弹._y - 12.5, bottom: 子弹._y + 12.5};
    } else {
        if (子弹.子弹区域area) {
            检测area = 子弹.子弹区域area;
        } else {
            检测area = 子弹.area;
        }
        var area_key:String = (检测area._x ^ 检测area._height) + "_" + (检测area._width ^ 检测area._y);
        if (!子弹[area_key]) {
            子弹[area_key] = {area: _root.areaToRectGameworld(检测area), x: 子弹._x, y: 子弹._y};
        }
        var cache_area = 子弹[area_key].area;
        var x_offset:Number = 子弹._x - 子弹[area_key].x;
        var y_offset:Number = 子弹._y - 子弹[area_key].y;
        area线框 = {
            left: cache_area.left + x_offset,
            right: cache_area.right + x_offset,
            top: cache_area.top + y_offset,
            bottom: cache_area.bottom + y_offset
        };
    }
    子弹.area线框 = area线框;
    子弹.检测area = 检测area;
};

_root.设置碰撞检测标志 = function(子弹) {
    子弹.点集碰撞检测许可 = 子弹.联弹检测 && 子弹._rotation != 0 && 子弹._rotation != 180;
    if (子弹.点集碰撞检测许可) {
        子弹.area点集 = _root.影片剪辑至游戏世界点集(子弹.检测area);
        子弹.area面积 = _root.点集面积系数(子弹.area点集);
        子弹.area点集边向量 = [];
    } else {
        子弹.击中矩形 = {};
        子弹.area面积 = _root.calculateRectArea(子弹.area线框);
    }
};

_root.获取遍历敌人表 = function(子弹, 发射对象) {
    var 遍历敌人表 = _root.帧计时器.获取敌人缓存(发射对象, 5);
    if (子弹.友军伤害) {
        var 遍历友军表 = _root.帧计时器.获取友军缓存(发射对象, 5);
        遍历敌人表 = 遍历敌人表.concat(遍历友军表);
    }
    return 遍历敌人表;
};

_root.是否有效目标 = function(子弹) {
    var Z轴坐标差 = 子弹.命中对象.Z轴坐标 - 子弹.Z轴坐标;
    if (Math.abs(Z轴坐标差) >= 子弹.Z轴攻击范围 || !(子弹.命中对象.是否为敌人 == 子弹.子弹敌我属性值)) {
        return false;
    }
    if ((子弹.命中对象._name != 子弹.发射者名 || 子弹.友军伤害) && 子弹.命中对象.防止无限飞 != true || (子弹.命中对象.hp <= 0 && !子弹.近战检测)) {
        return true;
    }
    return false;
};

_root.检测碰撞并处理 = function(子弹, 发射对象) {
    if (_root.检测碰撞(子弹)) {
        _root.处理击中(子弹, 发射对象);
        return true;
    }
    return false;
};

_root.检测碰撞 = function(子弹) {
    var 游戏世界 = _root.gameworld;
    var Z轴坐标差 = 子弹.命中对象.Z轴坐标 - 子弹.Z轴坐标;
    var 覆盖率 = 1;
    var 目标线框 = 子弹.命中对象.area.getRect(游戏世界);
    var 碰撞中心;
    if (_root.aabb碰撞检测(子弹.area线框, 目标线框, Z轴坐标差)) {
        if (子弹.联弹检测) {
            if (子弹.点集碰撞检测许可) {
                子弹.击中点集 = _root.点集碰撞检测(子弹.area点集, 子弹.命中对象.area, 子弹.area点集边向量, Z轴坐标差);
                if (子弹.击中点集.length < 3) {
                    return false;
                }
                覆盖率 = _root.点集面积系数(子弹.击中点集) / 子弹.area面积;
                碰撞中心 = {x: 子弹._x, y: 子弹._y};
            } else {
                子弹.击中矩形 = _root.rectHitTest(子弹.area线框, 子弹.命中对象.area, Z轴坐标差);
                覆盖率 = _root.calculateRectArea(子弹.击中矩形) / 子弹.area面积;
                if (覆盖率 <= 0) {
                    return false;
                }
                碰撞中心 = {
                    x: (子弹.击中矩形.left + 子弹.击中矩形.right) / 2,
                    y: (子弹.击中矩形.top + 子弹.击中矩形.bottom) / 2
                };
            }
        } else {
            碰撞中心 = {
                x: (Math.max(子弹.area线框.left, 目标线框.xMin) + Math.min(子弹.area线框.right, 目标线框.xMax)) / 2,
                y: (Math.max(子弹.area线框.top, 目标线框.yMin) + Math.min(子弹.area线框.bottom, 目标线框.yMax)) / 2
            };
        }
        子弹.碰撞中心 = 碰撞中心;
        子弹.覆盖率 = 覆盖率;
        return true;
    } else {
        return false;
    }
};

_root.处理击中 = function(子弹, 发射对象) {
    if (_root.调试模式) {
        _root.绘制线框(子弹.命中对象.area);
    }
    var 命中对象血槽 = 子弹.命中对象.新版人物文字信息 ? 子弹.命中对象.新版人物文字信息.头顶血槽 : 子弹.命中对象.人物文字信息.头顶血槽;
    命中对象血槽._visible = true;
    命中对象血槽.gotoAndPlay(2);
    子弹.命中对象.攻击目标 = 发射对象._name;

    _root.冲击力刷新(子弹.命中对象);

    if (子弹.命中对象.无敌 || 子弹.命中对象.man.无敌标签 || 子弹.命中对象.NPC) {
        if (子弹.击中时触发函数) {
            子弹.击中时触发函数();
        }
    } else if (子弹.命中对象.hp != 0) {
        _root.计算伤害并应用(子弹, 发射对象);
    }

    _root.更新目标状态(子弹, 发射对象);
    _root.处理特效(子弹, 发射对象);

    if (!子弹.近战检测 && !子弹.爆炸检测 && 子弹.命中对象.hp <= 0) {
        子弹.命中对象.状态改变("血腥死");
    }

    if (子弹.近战检测 && !子弹.不硬直) {
        发射对象.硬直(发射对象.man, _root.钝感硬直时间);
    } else if (!子弹.穿刺检测) {
        子弹.gotoAndPlay("消失");
    }

    if (子弹.垂直击退速度 > 0) {
        子弹.命中对象.man.play();
        clearInterval(子弹.命中对象.pauseInterval);
        子弹.命中对象.硬直中 = false;
        clearInterval(子弹.命中对象.pauseInterval2);

        _root.fly(子弹.命中对象, 子弹.垂直击退速度, 0);
    }
};

_root.计算伤害并应用 = function(子弹, 发射对象) {
    // 初始化伤害显示相关的变量
    _root.初始化伤害显示(子弹);

    // 调整目标防御力
    _root.调整目标防御(子弹.命中对象);

    // 处理击中时触发的函数
    if (子弹.击中时触发函数) {
        子弹.击中时触发函数();
    }

    // 计算基础破坏力
    _root.计算基础破坏力(子弹, 发射对象);

    // 应用暴击效果
    if (子弹.暴击) {
        _root.应用暴击(子弹);
    }

    // 根据伤害类型计算损伤值
    _root.应用伤害类型(子弹);

    // 特殊伤害加成（如踩人）
    _root.特殊伤害加成(子弹, 发射对象);

    // 计算附加层伤害（毒、击溃）
    _root.计算附加层伤害(子弹);

    // 处理躲闪状态并调整伤害
    var 原始伤害数字 = 子弹.命中对象.损伤值;
    var 躲闪状态 = 子弹.伤害类型 == "真伤" ? "未躲闪" : _root.计算躲闪状态(子弹, 发射对象);
    _root.调整伤害根据躲闪状态(子弹, 躲闪状态, 原始伤害数字);

    // 消耗霰弹值
    _root.消耗霰弹值(子弹);

    // 应用毒、吸血、击溃、斩杀等效果
    _root.应用特殊效果(子弹, 发射对象);

    // 显示伤害数字
    _root.显示伤害数字(子弹, 躲闪状态);

    // 更新目标的HP
    _root.更新目标HP(子弹);

    // 如果目标是玩家，刷新HP显示
    if (子弹.命中对象._name === _root.控制目标) {
        _root.玩家信息界面.刷新hp显示();
    }
};

_root.初始化伤害显示 = function(子弹) {
    子弹.伤害字符 = "";
    子弹.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#FFCC00" : "#FF0000";
};

_root.调整目标防御 = function(目标) {
    目标.防御力 = isNaN(目标.防御力) ? 1 : Math.min(目标.防御力, 99000);
};

_root.计算基础破坏力 = function(子弹, 发射对象) {
    子弹.破坏力 = Number(子弹.子弹威力) + (isNaN(发射对象.伤害加成) ? 0 : 发射对象.伤害加成);
    var 伤害波动 = (!_root.调试模式 || 子弹.霰弹值 > 1) ? (0.85 + _root.basic_random() * 0.3) : 1;
    var 伤害波动数字 = 子弹.破坏力 * 伤害波动;
    var 百分比伤 = isNaN(子弹.百分比伤害) ? 0 : 子弹.命中对象.hp * 子弹.百分比伤害 / 100;
    子弹.破坏力 = 伤害波动数字 + 子弹.固伤 + 百分比伤;
};

_root.应用暴击 = function(子弹) {
    子弹.破坏力 *= 子弹.暴击(子弹);
};

_root.应用伤害类型 = function(子弹) {
    if (子弹.伤害类型 === "真伤") {
        子弹.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#4A0099" : "#660033";
        子弹.伤害字符 += '<font color="' + 子弹.伤害数字颜色 + '" size="20"> 真</font>';
        子弹.命中对象.损伤值 = 子弹.破坏力;
    } else if (子弹.伤害类型 === "魔法") {
        子弹.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#0099FF" : "#AC99FF";
        var 魔法属性字符 = 子弹.魔法伤害属性 ? 子弹.魔法伤害属性 : "能";
        子弹.伤害字符 += '<font color="' + 子弹.伤害数字颜色 + '" size="20"> ' + 魔法属性字符 + '</font>';
        var 敌人法抗 = _root.获取敌人法抗(子弹.命中对象, 子弹.魔法伤害属性);
        子弹.命中对象.损伤值 = Math.floor(子弹.破坏力 * (100 - 敌人法抗) / 100);
    } else {
        子弹.命中对象.损伤值 = 子弹.破坏力 * _root.防御减伤比(子弹.命中对象.防御力);
    }
};

_root.获取敌人法抗 = function(目标, 魔法伤害属性) {
    var 法抗;
    if (魔法伤害属性) {
        if (目标.魔法抗性 && (目标.魔法抗性[魔法伤害属性] || 目标.魔法抗性[魔法伤害属性] === 0)) {
            法抗 = 目标.魔法抗性[魔法伤害属性];
        } else if (目标.魔法抗性 && (目标.魔法抗性["基础"] || 目标.魔法抗性["基础"] === 0)) {
            法抗 = 目标.魔法抗性["基础"];
        } else {
            法抗 = 10 + 目标.等级 / 2;
        }
    } else {
        if (目标.魔法抗性 && (目标.魔法抗性["基础"] || 目标.魔法抗性["基础"] === 0)) {
            法抗 = 目标.魔法抗性["基础"];
        } else {
            法抗 = 10 + 目标.等级 / 2;
        }
    }
    法抗 = isNaN(法抗) ? 20 : Math.min(Math.max(法抗, -1000), 100);
    return 法抗;
};

_root.特殊伤害加成 = function(子弹, 发射对象) {
    if (子弹.发射者名 == "玩家0" && 发射对象.getSmallState() == "踩人中" && (子弹.命中对象.状态 == "击倒" || 子弹.命中对象.状态 == "倒地")) {
        子弹.命中对象.损伤值 *= 1.5;
    }
};

_root.计算附加层伤害 = function(子弹) {
    子弹.附加层伤害计算 = 0;
    子弹.淬毒量 = 0;
    子弹.击溃量 = 0;

    if (子弹.毒 > 0) {
        子弹.淬毒量 = 子弹.毒 * (子弹.普通检测 ? 1 : 0.3);
        子弹.附加层伤害计算 += 子弹.淬毒量;
    }

    if (子弹.击溃 > 0 && 子弹.命中对象.hp满血值 > 0) {
        子弹.击溃量 = Math.floor(子弹.命中对象.hp满血值 * 子弹.击溃 / 100);
        子弹.附加层伤害计算 += 子弹.击溃量;
    }
};

_root.计算躲闪状态 = function(子弹, 发射对象) {
    return _root.躲闪状态计算(
        子弹.命中对象,
        _root.根据命中计算闪避结果(发射对象, 子弹.命中对象, 子弹.命中率),
        子弹
    );
};

_root.调整伤害根据躲闪状态 = function(子弹, 躲闪状态, 原始伤害数字) {
    子弹.伤害数字大小 = 28;

    switch (躲闪状态) {
        case "跳弹":
            子弹.伤害数字 = _root.跳弹伤害计算(子弹.命中对象.损伤值, 子弹.命中对象.防御力);
            子弹.命中对象.损伤值 = 子弹.伤害数字;
            子弹.伤害数字大小 *= 0.3 + 0.7 * 子弹.伤害数字 / 原始伤害数字;
            子弹.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#7F6A00" : "#7F0000";
            break;
        case "过穿":
            子弹.伤害数字 = _root.过穿伤害计算(子弹.命中对象.损伤值, 子弹.命中对象.防御力);
            子弹.命中对象.损伤值 = 子弹.伤害数字;
            子弹.伤害数字大小 *= 0.3 + 0.7 * 子弹.伤害数字 / 原始伤害数字;
            子弹.伤害数字颜色 = 子弹.子弹敌我属性值 ? "#FFE770" : "#FF7F7F";
            break;
        case "躲闪":
        case "直感":
            子弹.伤害数字 = NaN;
            子弹.命中对象.损伤值 = 0;
            子弹.伤害数字大小 *= 0.5;
            break;
        case "格挡":
            子弹.伤害数字 = 子弹.命中对象.受击反制(子弹.命中对象.损伤值, 子弹);
            if (子弹.伤害数字) {
                子弹.命中对象.损伤值 = 子弹.伤害数字;
                子弹.伤害数字大小 *= 0.3 + 0.7 * 子弹.伤害数字 / 原始伤害数字;
            } else if (子弹.伤害数字 === 0) {
                子弹.命中对象.损伤值 = 0;
                子弹.伤害数字大小 *= 1.2;
            } else {
                子弹.伤害数字 = NaN;
                子弹.命中对象.损伤值 = 0;
                子弹.伤害数字大小 *= 0.5;
            }
            break;
        default:
            子弹.伤害数字 = Math.max(Math.floor(子弹.命中对象.损伤值), 1);
            子弹.命中对象.损伤值 = 子弹.伤害数字;
            _root.受击变红(120, 子弹.命中对象);
    }
};

_root.消耗霰弹值 = function(子弹) {
    var 最大消耗 = 子弹.命中对象.hp / 子弹.命中对象.损伤值;
    var 计算消耗 = 子弹.最小霰弹值 + 子弹.覆盖率 * ((子弹.霰弹值 - 子弹.最小霰弹值) + 1) * 1.2;
    子弹.消耗霰弹值 = Math.min(子弹.霰弹值, Math.ceil(Math.min(计算消耗, 最大消耗)));

    if (子弹.联弹检测 && !子弹.穿刺检测) {
        子弹.霰弹值 -= 子弹.消耗霰弹值;
    }

    子弹.命中对象.损伤值 *= 子弹.消耗霰弹值;
    子弹.伤害数字 *= 子弹.消耗霰弹值;
};

_root.应用特殊效果 = function(子弹, 发射对象) {
    if (子弹.淬毒量 > 0 && 子弹.伤害数字) {
        子弹.命中对象.损伤值 += 子弹.淬毒量;
        子弹.伤害数字 = 子弹.命中对象.损伤值;
        子弹.伤害字符 += '<font color="#66dd00" size="20"> 毒</font>';
        if (子弹.淬毒衰减 && 子弹.近战检测 && 发射对象.淬毒 > 10) {
            发射对象.淬毒 -= 子弹.淬毒衰减;
        }
        if (子弹.命中对象.毒返 > 0) {
            var 毒返淬毒值 = 子弹.淬毒量 * 子弹.命中对象.毒返;
            if (子弹.命中对象.毒返函数) {
                子弹.命中对象.毒返函数(子弹.淬毒量, 毒返淬毒值);
            }
            子弹.命中对象.淬毒 = 毒返淬毒值;
        }
    }

    if (子弹.吸血 > 0 && 子弹.命中对象.损伤值 > 1) {
        var 吸血量 = Math.floor(Math.max(Math.min(子弹.命中对象.损伤值 * 子弹.吸血 / 100, 子弹.命中对象.hp), 0));
        发射对象.hp += Math.min(吸血量, 发射对象.hp满血值 * 1.5 - 发射对象.hp);
        子弹.伤害字符 = '<font color="#bb00aa" size="15"> 汲:' + Math.floor(吸血量 / 子弹.消耗霰弹值).toString() + "</font>" + 子弹.伤害字符;
    }

    if (子弹.击溃 > 0 && 子弹.命中对象.损伤值 > 1) {
        var 击溃量 = 子弹.击溃量 && !isNaN(子弹.击溃量) ? 子弹.击溃量 : 1;
        if (子弹.命中对象.hp满血值 > 0) {
            子弹.命中对象.hp满血值 -= 击溃量;
            子弹.命中对象.损伤值 += 击溃量;
        }
        子弹.伤害字符 += '<font color="#FF3333" size="20"> 溃</font>';
        子弹.伤害数字 = Math.floor(子弹.命中对象.损伤值);
    }

    if (子弹.斩杀) {
        if (子弹.命中对象.hp < 子弹.命中对象.hp满血值 * 子弹.斩杀 / 100) {
            子弹.命中对象.损伤值 += 子弹.命中对象.hp;
            子弹.命中对象.hp = 0;
            子弹.伤害字符 = 子弹.子弹敌我属性值 ? '<font color="#4A0099" size="20"> 斩</font>' : '<font color="#660033" size="20"> 斩</font>';
        }
        子弹.伤害数字 = Math.floor(子弹.命中对象.损伤值);
    }
};

_root.显示伤害数字 = function(子弹, 躲闪状态) {
    var 控制字符串 = "";

    if (子弹.消耗霰弹值 > 1) {
        var 剩余伤害 = 子弹.伤害数字;
        for (var i = 0; i < 子弹.消耗霰弹值 - 1; ++i) {
            var 波动伤害 = (剩余伤害 / (子弹.消耗霰弹值 - i)) * (100 + _root.随机偏移(50 / 子弹.消耗霰弹值)) / 100;
            剩余伤害 -= 波动伤害;
            var 显示数字 = '<font color="' + 子弹.伤害数字颜色 + '" size="' + 子弹.伤害数字大小 + '">' + (isNaN(波动伤害) ? "MISS" : Math.floor(波动伤害)) + "</font>";
            _root.打击数字特效(控制字符串, 显示数字 + 子弹.伤害字符, 子弹.命中对象._x, 子弹.命中对象._y);
        }
        子弹.伤害数字 = 剩余伤害;
    }

    var 最终显示数字 = '<font color="' + 子弹.伤害数字颜色 + '" size="' + 子弹.伤害数字大小 + '">' + (isNaN(子弹.伤害数字) ? "MISS" : Math.floor(子弹.伤害数字)) + "</font>";
    _root.打击数字特效(控制字符串, 最终显示数字 + 子弹.伤害字符, 子弹.命中对象._x, 子弹.命中对象._y);
};

_root.更新目标HP = function(子弹) {
    子弹.命中对象.hp = isNaN(子弹.命中对象.损伤值) ? 子弹.命中对象.hp : Math.floor(子弹.命中对象.hp - 子弹.命中对象.损伤值);
    子弹.命中对象.hp = (子弹.命中对象.hp < 0 || isNaN(子弹.命中对象.hp)) ? 0 : 子弹.命中对象.hp;
};


_root.更新目标状态 = function(子弹, 发射对象) {
    var 被击方向 = (子弹.命中对象._x < 发射对象._x) ? "左" : "右";
    if (子弹.水平击退反向) {
        被击方向 = 被击方向 === "左" ? "右" : "左";
    }
    子弹.命中对象.方向改变(被击方向 === "左" ? "右" : "左");

    var 刚体检测 = 子弹.命中对象.刚体 || 子弹.命中对象.man.刚体标签;
    if (!子弹.命中对象.浮空 && !子弹.命中对象.倒地) {
        _root.冲击力结算(子弹.命中对象.损伤值, 子弹.击倒率, 子弹.命中对象);
        子弹.命中对象.血条变色状态 = "常态";

        if (!isNaN(子弹.命中对象.hp) && 子弹.命中对象.hp <= 0) {
            子弹.命中对象.状态改变(_root.血腥开关 ? "血腥死" : "击倒");
        } else if (子弹.躲闪状态 == "躲闪") {
            子弹.命中对象.被击移动(被击方向, 子弹.水平击退速度, 3);
        } else {
            if (子弹.命中对象.残余冲击力 > 子弹.命中对象.韧性上限) {
                if (!刚体检测) {
                    子弹.命中对象.状态改变("击倒");
                    子弹.命中对象.血条变色状态 = "击倒";
                }
                子弹.命中对象.残余冲击力 = 0;
                子弹.命中对象.被击移动(被击方向, 子弹.水平击退速度, 0.5);
            } else if (子弹.命中对象.残余冲击力 > 子弹.命中对象.韧性上限 / _root.踉跄判定 / 子弹.命中对象.躲闪率) {
                if (!刚体检测) {
                    子弹.命中对象.状态改变("被击");
                    子弹.命中对象.血条变色状态 = "被击";
                }
                子弹.命中对象.被击移动(被击方向, 子弹.水平击退速度, 2);
            } else {
                子弹.命中对象.被击移动(被击方向, 子弹.水平击退速度, 3);
            }
        }
    } else {
        子弹.命中对象.残余冲击力 = 0;
        if (!刚体检测) {
            子弹.命中对象.状态改变("击倒");
            子弹.命中对象.血条变色状态 = "击倒";
            if (!(子弹.垂直击退速度 > 0)) {
                var y速度 = 5;
                子弹.命中对象.man.垂直速度 = -y速度;
            }
        }
        子弹.命中对象.被击移动(被击方向, 子弹.水平击退速度, 0.5);
    }

    switch (子弹.命中对象.血条变色状态) {
        case "常态":
            _root.重置色彩(子弹.命中对象.新版人物文字信息 ? 子弹.命中对象.新版人物文字信息.头顶血槽 : 子弹.命中对象.人物文字信息.头顶血槽);
            break;
        default:
            _root.暗化色彩(子弹.命中对象.新版人物文字信息 ? 子弹.命中对象.新版人物文字信息.头顶血槽 : 子弹.命中对象.人物文字信息.头顶血槽);
    }
};

_root.处理特效 = function(子弹, 发射对象) {
    if (_root.血腥开关) {
        var 子弹效果碎片 = "";
        switch (子弹.命中对象.击中效果) {
            case "飙血":
                子弹效果碎片 = "子弹碎片-飞血";
                break;
            case "异形飙血":
                子弹效果碎片 = "子弹碎片-异形飞血";
                break;
            default:
        }

        if (子弹效果碎片 != "") {
            var 效果对象 = _root.效果(子弹效果碎片, 子弹.碰撞中心.x, 子弹.碰撞中心.y, 发射对象._xscale);
            效果对象.出血来源 = 子弹.命中对象._name;
        }
    }

    _root.效果(子弹.命中对象.击中效果, 子弹.碰撞中心.x, 子弹.碰撞中心.y, 发射对象._xscale);
    if (子弹.命中对象.击中效果 == 子弹.击中后子弹的效果) {
        子弹.是否生成击中后效果 = false;
    }
};

_root.生成击中后效果 = function(子弹, 发射对象) {
    _root.效果(子弹.击中后子弹的效果, 子弹._x, 子弹._y, 发射对象._xscale);
};

_root.检测子弹击中地图 = function(子弹) {
    var 游戏世界 = _root.gameworld;
    var 击中地图判定 = false;
    if (子弹._x < _root.Xmin || 子弹._x > _root.Xmax || 子弹.Z轴坐标 < _root.Ymin || 子弹.Z轴坐标 > _root.Ymax) {
        击中地图判定 = true;
    } else if (子弹._y > 子弹.Z轴坐标 && !子弹.近战检测) {
        击中地图判定 = true;
    } else {
        var 子弹地面坐标 = {x: 子弹._x, y: 子弹.Z轴坐标};
        游戏世界.localToGlobal(子弹地面坐标);
        if (游戏世界.地图.hitTest(子弹地面坐标.x, 子弹地面坐标.y, true)) {
            击中地图判定 = true;
        }
    }
    if (击中地图判定) {
        子弹.击中地图 = true;
        子弹.霰弹值 = 1;
        _root.效果(子弹.击中地图效果, 子弹._x, 子弹._y);
        if (子弹.击中时触发函数) {
            子弹.击中时触发函数();
        }
        return true;
    }
    return false;
};


_root.子弹基础运动控制 = function(子弹:MovieClip){
	if(子弹.速度X && 子弹.速度Y && 子弹.ZY比例){
		子弹._x += 子弹.速度X;
		子弹._y += 子弹.速度Y;
		子弹.Z轴坐标 = 子弹._y * 子弹.ZY比例;
	}else{
		子弹._x += 子弹.xmov;
		子弹._y += 子弹.ymov;
	}
	if (!子弹.远距离不消失 && (Math.abs(子弹._x - _root.gameworld[子弹.发射者名]._x) > 900 || Math.abs(子弹._y - _root.gameworld[子弹.发射者名]._y) > 900))
	{
		子弹.removeMovieClip();
	}
}


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






