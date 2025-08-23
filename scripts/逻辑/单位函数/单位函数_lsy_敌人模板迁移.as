import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.arki.unit.*;
import org.flashNight.naki.RandomNumberEngine.*
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.arki.component.Damage.*;

//容纳敌人函数的对象
_root.敌人函数 = new Object();


//以下14个是原版敌人的必要函数

_root.敌人函数.根据等级初始数值 = function(等级值) {
    //_root.服务器.发布服务器消息("unit: " + this._name + " at level: " + 等级值)

    this.hp满血值 = _root.根据等级计算值(this.hp_min, this.hp_max, 等级值) * _root.难度等级;
    this.空手攻击力 = _root.根据等级计算值(this.空手攻击力_min, this.空手攻击力_max, 等级值) * _root.难度等级;
    this.行走X速度 = _root.根据等级计算值(this.速度_min, this.速度_max, 等级值) / 10;
    this.行走Y速度 = this.行走X速度 / 2;
    this.跑X速度 = this.行走X速度 * this.奔跑速度倍率;
    this.跑Y速度 = this.行走Y速度 * this.奔跑速度倍率;
    // 被击硬直度 = _root.根据等级计算值(被击硬直度_min, 被击硬直度_max, 等级值);
    this.起跳速度 = isNaN(this.起跳速度) ? -10 : this.起跳速度;
    this.基本防御力 = _root.根据等级计算值(this.基本防御力_min, this.基本防御力_max, 等级值);
    this.防御力 = this.基本防御力 + this.装备防御力;
    this.躲闪率 = _root.根据等级计算值(this.躲闪率_min, this.躲闪率_max, 等级值, true, true); // 允许小数，且在60级后不再增长防止出现小于1的躲闪率
    if (isNaN(this.hp))
        this.hp = this.hp满血值;
};

_root.敌人函数.获取线性插值经验值 = function(target, list:Array) {
    var level:Number = Number(target.等级);
    var n:Number = (list == null) ? 0 : list.length;

    // 0) 兜底：没有数据 / 只有一个点
    if (n == 0) {
        target.最小经验值 = 0;
        target.最大经验值 = 0;
        return;
    }
    if (n == 1) {
        var v:Number = Number(list[0].value);
        target.最小经验值 = v;
        target.最大经验值 = v;
        return;
    }

    // 1) 选择用于插值/外推的“段”索引 i（使用线段 [i, i+1]）
    var i:Number;
    if (level <= Number(list[0].level)) {
        // 低于最小 level：用首段斜率外推
        i = 0;
    } else if (level >= Number(list[n - 1].level)) {
        // 高于最大 level：用末段斜率外推
        i = n - 2;
    } else {
        // 区间内：找到使 level < list[i+1].level 的 i
        for (i = 0; i < n - 1; i++) {
            if (level < Number(list[i + 1].level)) break;
        }
        if (i >= n - 1) i = n - 2; // 冗余保护
    }

    // 2) 读取段两端数据
    var x0:Number = Number(list[i].level);
    var x1:Number = Number(list[i + 1].level);
    var y0:Number = Number(list[i].value);
    var y1:Number = Number(list[i + 1].value);

    // 3) 防重复 level（x1 == x0）导致的除零：向左右寻找最近的有效段
    if (x1 == x0) {
        var left:Number = i - 1;
        var right:Number = i + 1;
        var found:Boolean = false;

        while (!found && (left >= 0 || right < n - 1)) {
            if (left >= 0) {
                if (Number(list[left + 1].level) != Number(list[left].level)) {
                    i = left;
                    x0 = Number(list[i].level);
                    x1 = Number(list[i + 1].level);
                    y0 = Number(list[i].value);
                    y1 = Number(list[i + 1].value);
                    found = true;
                    break;
                }
                left--;
            }
            if (right < n - 1) {
                if (Number(list[right + 1].level) != Number(list[right].level)) {
                    i = right;
                    x0 = Number(list[i].level);
                    x1 = Number(list[i + 1].level);
                    y0 = Number(list[i].value);
                    y1 = Number(list[i + 1].value);
                    found = true;
                    break;
                }
                right++;
            }
        }

        // 如果整张表所有相邻点 level 都相等，则退化为常量
        if (!found) {
            target.最小经验值 = y0;
            target.最大经验值 = y0;
            return;
        }
    }

    // 4) 使用所选“段”的斜率进行插值/外推
    target.最小经验值 = _root.常用工具函数.线性插值(
        1, x0, x1, y0, y1
    );
    target.最大经验值 = _root.常用工具函数.线性插值(
        _root.最大等级, x0, x1, y0, y1
    );
    // _root.发布消息(target.最小经验值 + " / " + target.最大经验值);
};


_root.敌人函数.宠物属性初始化 = function() {
    if (this.宠物属性) {
        for (var key in this.宠物属性) {
            if (_root.战宠进阶函数[key] && _root.战宠进阶函数[key].单位进阶执行) {
                this.单位进阶执行 = _root.战宠进阶函数[key].单位进阶执行;
                this.单位进阶执行();
            }
        }
    }
    if (isNaN(this.hp))
        this.hp = this.hp满血值;
};

_root.敌人函数.行走 = function() {
    if (this.右行 || this.左行 || this.上行 || this.下行) {
        // 定义策略对象，封装跑和走两种移动方式的参数
        var 移动策略 = {跑: {
                    x速度: 跑X速度,
                    y速度: 跑Y速度,
                    状态后缀: "跑"
                },
                走: {
                    x速度: 行走X速度,
                    y速度: 行走Y速度,
                    状态后缀: "行走"
                }};

        // 根据当前状态判断使用哪一种策略
        // 如果当前状态为攻击模式+"跑"，则使用跑的参数，否则使用走的参数
        var 初始目标状态 = this.攻击模式 + "跑";
        var 最终策略 = (this.状态 === 初始目标状态) ? 移动策略.跑 : 移动策略.走;
        var 最终状态 = this.攻击模式 + 最终策略.状态后缀;

        // 根据方向选择对应的移动操作
        if (this.右行) {
            this.方向改变("右");
            this.移动("右", 最终策略.x速度);
        } else if (this.左行) {
            this.方向改变("左");
            this.移动("左", 最终策略.x速度);
        }
        if (this.下行) {
            this.移动("下", 最终策略.y速度);
        } else if (this.上行) {
            this.移动("上", 最终策略.y速度);
        }

        // 改变状态为最终状态
        this.状态改变(最终状态);
    } else {
        // 没有移动操作时，设置为攻击模式+站立状态
        this.状态改变(this.攻击模式 + "站立");
    }
};


_root.敌人函数.移动 = function(移动方向, 速度) {
    Mover.move2D(this, 移动方向, 速度);
};



_root.敌人函数.被击移动 = function(移动方向, 速度, 摩擦力) {
    if (this.免疫击退)
        return;
    this.移动钝感硬直(_root.钝感硬直时间);
    this.减速度 = 摩擦力;
    this.speed = 速度;
    this.onEnterFrame = function() {
        if (!this.硬直中) {
            this.speed -= 减速度;
            if (this.speed <= 0) {
                delete this.onEnterFrame;
                return;
            }
            this.移动(移动方向, this.speed);
        }
    };
};

_root.敌人函数.强制移动 = _root.主角函数.强制移动;


_root.敌人函数.方向改变 = function(新方向) {
    if (this.锁定方向)
        return;
    if (新方向 === "右") {
        this.方向 = "右";
        this._xscale = myxscale;
        this.新版人物文字信息._xscale = 100;
    } else if (新方向 === "左") {
        this.方向 = "左";
        this._xscale = -myxscale;
        this.新版人物文字信息._xscale = -100;
    }
};

_root.敌人函数.状态改变 = function(新状态名) {
    if (this.状态 == 新状态名)
        return; // 已经处于该状态，跳过

    // this.旧状态 = this.状态; // 记录上一个状态名
    this.gotoAndStop(this.状态 = 新状态名);
};



_root.敌人函数.动画完毕 = function() {
    this.状态改变(this.hp <= 0 ? "血腥死" : this.攻击模式 + "站立"); // 防止没有倒地动画的敌人在击倒动画被扣至0血导致不死
    // 考虑到该函数较为低频，一些状态更新顺带在此触发
    this.倒地 = false;
    this.aabbCollider.updateFromUnitArea(this); // 起身时更新碰撞箱
};

_root.敌人函数.硬直 = function(目标, 时间) {
    if (this.stiffID != null)
        return;
    var 自机:Object = this; // 在外部保存对当前对象的引用
    目标.stop();

    this.stiffID = EnhancedCooldownWheel.I().addTask(function() {
        自机.stiffID = null;
        目标.play();
    }, 时间, 1);
};

_root.敌人函数.移动钝感硬直 = _root.主角函数.移动钝感硬直;


_root.敌人函数.随机掉钱 = function() {
    if (!this.不掉钱 && random(_root.打怪掉钱机率) === 0) {
        var 金币时间倍率 = _root.天气系统.金币时间倍率;
        //_root.发布消息("金币时间倍率" + 金币时间倍率);
        var 昼夜爆金币 = this.hp满血值 * 金币时间倍率 / 5;

        _root.pickupItemManager.createCollectible("金钱", random(昼夜爆金币), this._x, this._y, true);
    }
};

_root.敌人函数.计算经验值 = function() {
    this.随机掉钱();
    this.掉落物判定();

    var 经验时间倍率 = _root.天气系统.经验时间倍率;

    //_root.发布消息("经验时间倍率" + 经验时间倍率);
    _root.经验值计算(this.最小经验值 * 经验时间倍率, this.最大经验值 * 经验时间倍率, this.等级, _root.最大等级);
    _root.主角是否升级(_root.等级, _root.经验值);
    this.已加经验值 = true;
};

_root.敌人函数.攻击呐喊 = function() {
    var arr:Array = 性别 === "女" ? 女_攻击呐喊_库 : 男_攻击呐喊_库;
    _root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};

_root.敌人函数.中招呐喊 = function() {
    var arr:Array = 性别 === "女" ? 女_中招呐喊_库 : 男_中招呐喊_库;
    _root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};

_root.敌人函数.击倒呐喊 = function() {
    var time = getTimer();
    if (time - this.上次击倒呐喊时间 < 300)
        return; // 击倒呐喊的最低间隔为300毫秒
    this.上次击倒呐喊时间 = time;

    var arr:Array = 性别 === "女" ? 女_击倒呐喊_库 : 男_击倒呐喊_库;
    _root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};


//以下是新增或新整合的函数


/*
   死亡检测统一函数
   可传的参数：
   noCount: 不计入关卡杀怪数
   noCorpse: 不贴尸体
   remainMovie: 不卸载元件

   例：
   _parent.死亡检测();
   _parent.死亡检测({noCount:true});
   _parent.死亡检测({noCorpse:true});
   _parent.死亡检测({remainMovie:true});
   _parent.死亡检测({noCount:true, noCorpse:true});
 */
_root.敌人函数.死亡检测 = function(para) {
    if (this.hp <= 0 && !this.已加经验值) {
        this.man.stop();
        if (this.是否为敌人 === true || this.是否为敌人 === "null") {
            if (this.是否为敌人 === true && para.noCount !== true) {
                _root.敌人死亡计数++;
                _root.gameworld[this.产生源].僵尸型敌人场上实际人数--;
                _root.gameworld[this.产生源].僵尸型敌人总个数--;
            }
            this.计算经验值();
        }
        this.人物文字信息._visible = false;
        this.新版人物文字信息._visible = false;
        if (para.remainMovie === true) {
            StaticDeinitializer.deinitializeUnit(this); // 不卸载元件直接注销单位
        } else {
            if (para.noCorpse !== true)
                _root.add2map(this, 2); // 检测是否需要贴尸体
            this.removeMovieClip(); // 移除单位
        }
    }
};


_root.敌人函数.掉落物判定 = function() {
    if (this.掉落物 == null)
        return;
    this.掉落物 = _root.配置数据为数组(this.掉落物);
    var 玩家逆向等级 = _root.主角被动技能.逆向.启用 ? _root.主角被动技能.逆向.等级 : 0;
    if (this.掉落物.length > 0) {
        for (var i = this.掉落物.length - 1; i > -1; i--) {
            var item = this.掉落物[i];
            if (玩家逆向等级 < item.最小逆向等级 || 玩家逆向等级 > item.最大逆向等级) {
                this.掉落物.splice(i, 1);
                continue;
            }
            this.掉落物品(item);
            if (item.总数 <= 0) {
                this.掉落物.splice(i, 1);
            }
        }
    }
}

_root.敌人函数.掉落物品 = function(item) {
    var itemData = _root.getItemData(item.名字);
    if (itemData == null)
        return;
    if (!isNaN(item.概率)) {
        if (!_root.成功率(item.概率))
            return;
    }

    if (isNaN(item.最小数量) || isNaN(item.最大数量)) {
        item.最小数量 = item.最大数量 = 1;
    }
    if (isNaN(item.总数))
        item.总数 = item.最大数量;

    // 检查情报物品是否达到上限
    if (itemData.use === "情报") {
        var value = _root.收集品栏.情报.getValue(item.名字);
        var maxvalue = itemData.maxvalue;
        if (value >= maxvalue)
            return;
        else if (maxvalue - value < item.最大数量) {
            item.最大数量 = maxvalue - value;
            if (item.最大数量 < item.最小数量) {
                item.最小数量 = item.最大数量;
            }
        }
    }
    var 数量 = item.最小数量 + random(item.最大数量 - item.最小数量 + 1);
    if (item.总数 < 数量)
        数量 = item.总数;
    item.总数 -= 数量;
    var yoffset = random(21) - 10;
    _root.pickupItemManager.createCollectible(item.名字, 数量, this._x, this._y + yoffset, true);
}


_root.敌人函数.fly = function(target:MovieClip) {
    if (target.硬直中 == false) {
        target._y += target.垂直速度;
        target.垂直速度 += _root.重力加速度;
        target.aabbCollider.updateFromUnitArea(target); // 更新碰撞箱
    }
    if (target._y >= target.Z轴坐标) {
        target._y = target.Z轴坐标;
        target.浮空 = false;
        EnhancedCooldownWheel.I().removeTask(target.flyID);
        target.flyID = null;
        if (target.状态 == "击倒") {
            target.状态改变("倒地");
        }
    }
}

_root.敌人函数.击飞浮空 = function() {
    if (this.flyID != null)
        return;
    this.浮空 = true;
    this.倒地 = false;
    this.man.落地 = false;
    if (this._y >= this.Z轴坐标)
        this._y = this.Z轴坐标 - 1;
    if (this.垂直速度 >= this.起跳速度)
        this.垂直速度 = this.起跳速度;

    var self:MovieClip = this;
    this.flyID = EnhancedCooldownWheel.I().addTask(function() {
        _root.敌人函数.fly(self);
    }, 33, -1);
}

_root.敌人函数.击飞倒地 = function() {
    this._y = this.Z轴坐标;
    this.垂直速度 = 0;
    this.倒地 = true;
    this.aabbCollider.updateFromUnitArea(this); // 倒地时更新碰撞箱
}

_root.敌人函数.尝试拾取 = function() {
    var 拾取对象 = _root.gameworld[this.拾取目标];
    this.拾取目标 = "无";
    if (!拾取对象.area) {
        return;
    }
    if (this.是否为敌人 === false) {
        if (_root.物品栏.背包.getFirstVacancy() > -1) {
            _root.pickupItemManager.pickup(拾取对象, this, false);
        }
    } else {
        拾取对象.gotoAndPlay("消失");
    }
}


_root.敌人函数.应用影子色彩 = function(target:MovieClip) {
    if (target.影子单位) {
        target.影子倍率 = target.影子倍率 ? target.影子倍率 : 0;
        target.透明倍率 = target.透明倍率 ? target.透明倍率 : 0.7;
        _root.设置色彩(target, target.影子倍率, target.影子倍率, target.影子倍率, NaN, NaN, NaN, target.透明倍率, 0);
        target.不掉钱 = true;
        target.掉落物 = [];
    } else if (target.超时空传送) {
        _root.设置色彩(target, 0.3, 0.55, 1.1, NaN, NaN, NaN, NaN, NaN);
    } else if (target.色彩单位) {
        _root.设置色彩(target, target.红色乘数, target.绿色乘数, target.蓝色乘数, target.红色偏移, target.绿色偏移, target.蓝色偏移, target.透明乘数, target.透明偏移);
        target.不掉钱 = true;
        target.掉落物 = [];
    } else {
        _root.重置色彩(target);
    }
}
_root.敌人函数.魔法伤害种类 = MagicDamageTypes.getMagicDamageTypesArray();

_root.初始化敌人模板 = function() {
    //以下14个是原版敌人的必要函数
    this.根据等级初始数值 = this.根据等级初始数值 ? this.根据等级初始数值 : _root.敌人函数.根据等级初始数值;
    this.行走 = this.行走 ? this.行走 : _root.敌人函数.行走;
    this.移动 = this.移动 ? this.移动 : _root.敌人函数.移动;
    this.被击移动 = this.被击移动 ? this.被击移动 : _root.敌人函数.被击移动;
    this.方向改变 = this.方向改变 ? this.方向改变 : _root.敌人函数.方向改变;
    this.状态改变 = this.状态改变 ? this.状态改变 : _root.敌人函数.状态改变;
    this.动画完毕 = this.动画完毕 ? this.动画完毕 : _root.敌人函数.动画完毕;
    this.硬直 = this.硬直 ? this.硬直 : _root.敌人函数.硬直;
    this.移动钝感硬直 = this.移动钝感硬直 ? this.移动钝感硬直 : _root.敌人函数.移动钝感硬直;
    this.随机掉钱 = this.随机掉钱 ? this.随机掉钱 : _root.敌人函数.随机掉钱;
    this.计算经验值 = this.计算经验值 ? this.计算经验值 : _root.敌人函数.计算经验值;
    this.攻击呐喊 = this.攻击呐喊 ? this.攻击呐喊 : _root.敌人函数.攻击呐喊;
    this.中招呐喊 = this.中招呐喊 ? this.中招呐喊 : _root.敌人函数.中招呐喊;
    this.击倒呐喊 = this.击倒呐喊 ? this.击倒呐喊 : _root.敌人函数.击倒呐喊;

    //以下是新增或新整合的函数
    this.死亡检测 = _root.敌人函数.死亡检测;
    this.强制移动 = _root.敌人函数.强制移动;
    this.击飞浮空 = _root.敌人函数.击飞浮空;
    this.击飞倒地 = _root.敌人函数.击飞倒地;
    this.宠物属性初始化 = this.宠物属性初始化 ? this.宠物属性初始化 : _root.敌人函数.宠物属性初始化;
    this.掉落物判定 = _root.敌人函数.掉落物判定;
    this.掉落物品 = _root.敌人函数.掉落物品;

    if (this.允许拾取 === true)
        this.尝试拾取 = _root.敌人函数.尝试拾取;

    //敌人属性表涉及的参数，共18项
    if (!this.兵种)
        _root.发布消息("警告：敌人未加载兵种信息！")
    var 敌人属性 = _root.敌人属性表[this.兵种];
    if (敌人属性 == null)
        敌人属性 = _root.敌人属性表["默认"];
    //13项基础数值
    if (敌人属性.线性插值经验值.length > 1) {
        _root.敌人函数.获取线性插值经验值(this, 敌人属性.线性插值经验值);
    } else {
        if (isNaN(this.最小经验值))
            this.最小经验值 = 敌人属性.最小经验值;
        if (isNaN(this.最大经验值))
            this.最大经验值 = 敌人属性.最大经验值;
    }
    if (isNaN(this.hp_min))
        this.hp_min = 敌人属性.hp_min;
    if (isNaN(this.hp_max))
        this.hp_max = 敌人属性.hp_max;
    if (isNaN(this.速度_min))
        this.速度_min = 敌人属性.速度_min;
    if (isNaN(this.速度_max))
        this.速度_max = 敌人属性.速度_max;
    if (isNaN(this.空手攻击力_min))
        this.空手攻击力_min = 敌人属性.空手攻击力_min;
    if (isNaN(this.空手攻击力_max))
        this.空手攻击力_max = 敌人属性.空手攻击力_max;
    if (isNaN(this.躲闪率_min))
        this.躲闪率_min = 敌人属性.躲闪率_min;
    if (isNaN(this.躲闪率_max))
        this.躲闪率_max = 敌人属性.躲闪率_max;
    if (isNaN(this.基本防御力_min))
        this.基本防御力_min = 敌人属性.基本防御力_min;
    if (isNaN(this.基本防御力_max))
        this.基本防御力_max = 敌人属性.基本防御力_max;
    if (isNaN(this.装备防御力))
        this.装备防御力 = 敌人属性.装备防御力;
    //性别 重量 韧性
    if (this.性别 == null)
        this.性别 = 敌人属性.性别;
    if (isNaN(this.重量))
        this.重量 = 敌人属性.重量;
    if (isNaN(this.韧性系数))
        this.韧性系数 = 敌人属性.韧性系数;
    //label
    if (!this.label)
        this.label = new Object();
    for (var key in 敌人属性.label) {
        if (!label[key])
            label[key] = 敌人属性.label[key];
    }
    //魔法抗性
    if (!this.魔法抗性)
        this.魔法抗性 = new Object();
    for (var key in 敌人属性.魔法抗性) {
        if (isNaN(魔法抗性[key]))
            this.魔法抗性[key] = 敌人属性.魔法抗性[key];
    }

    // 基础抗性值
    var baseResist = (this.魔法抗性.基础 !== undefined) ? this.魔法抗性.基础 : (10 + this.等级 / 2);
    // 遍历每个抗性类型进行补全
    for (var i = 0; i < _root.敌人函数.魔法伤害种类.length; i++) {
        var type = _root.敌人函数.魔法伤害种类[i];
        if (isNaN(魔法抗性[type])) {
            this.魔法抗性[type] = baseResist;
        }
    }

    //掉落物
    if (!this.掉落物 && 敌人属性.掉落物 && 敌人属性.掉落物 != "null")
        this.掉落物 = _root.duplicateOf(敌人属性.掉落物);

    //被击硬直度是一个原版从未使用过的属性，这里顺理成章地将其弃用
    // 被击硬直度_min = !isNaN(被击硬直度_min) ? 被击硬直度_min : 1000;
    // 被击硬直度_max = !isNaN(被击硬直度_max) ? 被击硬直度_max : 1000;

    //以下是可以自定义的原版参数
    this.称号 = this.称号 ? this.称号 : "";
    if (isNaN(this.身高))
        this.身高 = 175;
    this.方向 = this.方向 ? this.方向 : "右";
    this.攻击模式 = this.攻击模式 ? this.攻击模式 : "空手";
    this.状态 = this.登场动画 ? "登场" : this.攻击模式 + "站立";
    this.击中效果 = this.击中效果 ? this.击中效果 : "飙血";
    this.刚体 = this.刚体 ? true : false;
    this.无敌 = this.无敌 === true ? true : false;

    //以下是可自定义的原版ai相关参数，在ai改革后可能被废弃
    this.x轴攻击范围 = this.x轴攻击范围 ? this.x轴攻击范围 : 100;
    this.y轴攻击范围 = this.y轴攻击范围 ? this.y轴攻击范围 : 10;
    this.x轴保持距离 = !isNaN(this.x轴保持距离) ? this.x轴保持距离 : 50;
    this.停止机率 = !isNaN(this.停止机率) ? this.停止机率 : 50;
    this.随机移动机率 = !isNaN(this.随机移动机率) ? this.随机移动机率 : 50;
    this.攻击欲望 = !isNaN(this.攻击欲望) ? this.攻击欲望 : 5;

    //以下是可以自定义的新增参数
    this.命中率 = !isNaN(this.命中率) ? this.命中率 : 10;
    this.免疫击退 = this.免疫击退 ? true : false;
    this.锁定方向 = this.锁定方向 ? true : false;
    this.奔跑速度倍率 = !isNaN(this.奔跑速度倍率) ? this.奔跑速度倍率 : 2;
    this.允许拾取 = this.允许拾取 ? true : false;

    //以下是自动初始化的必要参数
    this.dispatcher.publish("aggroClear", this);
    this.攻击模式 = "空手";
    this.格斗架势 = false;
    this.浮空 = false;
    this.倒地 = false;
    this.硬直中 = false;
    this.垂直速度 = 0;
    this.已加经验值 = false;
    this.remainingImpactForce = 0;

    //转换身高，调整层级
    var 身高转换值 = UnitUtil.getHeightPercentage(this.身高);
    this._xscale = 身高转换值;
    this._yscale = 身高转换值;
    myxscale = this._xscale;
    this.Z轴坐标 = this._y;
    this.swapDepths(this._y + random(10));

    // 应用新版人物文字信息
    if (this.人物文字信息) {
        this.attachMovie("新版人物文字信息", "新版人物文字信息", this.getNextHighestDepth());
        this.新版人物文字信息._x = 人物文字信息._x;
        this.新版人物文字信息._y = 人物文字信息._y;

        this.人物文字信息.unloadMovie();
    }

    // 应用初始器
    this.根据等级初始数值(等级);
    this.宠物属性初始化();
    StaticInitializer.initializeUnit(this);

    // 应用影子色彩
    _root.敌人函数.应用影子色彩(this);

    // 初始化完毕
    this.方向改变(方向);
    this.gotoAndStop(状态);
}

//对初始化单位的函数进行包装
_root.敌人函数.初始化单位 = function(target) {
    StaticInitializer.initializeUnit(target);
}
_root.敌人函数.注销单位 = function(target) {
    StaticDeinitializer.deinitializeUnit(target);
}

_root.敌人函数.跳转到招式 = _root.主角函数.跳转到招式;


//#change:主角-牛仔



//容纳敌人二级函数的对象，包括了原版的二级函数，以及新写或基于原版修改的二级函数
_root.敌人二级函数 = new Object();

//最广泛的二级函数
_root.敌人二级函数.攻击时移动 = function(速度) {
    var 移动方向 = _parent.方向;
    if (速度 < 0) {
        速度 = -速度;
        移动方向 = 移动方向 === "右" ? "左" : "右";
    }
    _parent.移动(移动方向, 速度);
};

//首次实装于武装JK
_root.敌人二级函数.攻击时四向移动 = function(上, 下, 左, 右) {
    if (上 != 0) {
        _parent.移动("上", 上);
    } else if (下 != 0) {
        _parent.移动("下", 下);
    }
    if (左 != 0) {
        _parent.方向改变("左");
        _parent.移动("左", 左);
    } else if (右 != 0) {
        _parent.方向改变("右");
        _parent.移动("右", 右);
    }
}

//由李小龙的瞬移改写，增加了最小与最大移动距离参数
_root.敌人二级函数.X轴追踪移动 = function(保持距离, 最小移动距离, 最大移动距离) {
    if (!_parent.攻击目标 || _parent.攻击目标 === "无") {
        return;
    }
    var 方向 = _parent.方向;
    var distance = _root.gameworld[_parent.攻击目标]._x - _parent._x;
    if (方向 === "左") {
        distance = -distance;
    }
    distance -= 保持距离;
    if (!isNaN(最小移动距离) && distance < 最小移动距离) {
        distance = 最小移动距离;
    }
    if (最大移动距离 > 0 && distance > 最大移动距离) {
        distance = 最大移动距离;
    }
    _parent.移动(_parent.方向, distance);
};

//首次实装于独狼
_root.敌人二级函数.Z轴追踪移动 = function(最大移动距离) {
    if (!_parent.攻击目标 || _parent.攻击目标 === "无") {
        return;
    }
    var distance = _root.gameworld[_parent.攻击目标].Z轴坐标 - _parent.Z轴坐标;
    var 方向 = "下";
    if (distance < 0) {
        distance = -distance;
        方向 = "上";
    }
    if (最大移动距离 > 0 && distance > 最大移动距离) {
        distance = 最大移动距离;
    }
    _parent.移动(方向, distance);
};

//根据攻击目标的位置计算移动角度，可限制角度的最大值。首次实装于方舟爪豪
//大于最大角度则返回最大角度，攻击目标在身后则返回角度限制下的随机值
_root.敌人二级函数.计算攻击角度 = function(最大角度) {
    if (!最大角度 || 最大角度 <= 0) {
        return 0;
    }
    var 水平距离 = _root.gameworld[_parent.攻击目标]._x - _parent._x;
    水平距离 = _parent.方向 === "左" ? -水平距离 : 水平距离;
    if (水平距离 <= 0) {
        return 2 * Math.random() * 最大角度 - 最大角度;
    }
    var 垂直距离 = _root.gameworld[_parent.攻击目标].Z轴坐标 - _parent.Z轴坐标;
    var 角度 = Math.atan(垂直距离 / 水平距离) / Math.PI * 180;
    角度 = Math.min(角度, 最大角度);
    角度 = Math.max(角度, -最大角度);
    return 角度;
}

//以固定角度移动，可能需要同时限制转向。首次实装于方舟爪豪
_root.敌人二级函数.固定角度移动 = function(速度, 角度) {
    if (!攻击时移动)
        攻击时移动 = _root.敌人二级函数.攻击时移动;
    攻击时移动(速度 * Math.cos(角度 * Math.PI / 180));
    var 垂直速度 = 速度 * Math.sin(角度 * Math.PI / 180);
    var 垂直方向 = "上";
    if (垂直速度 < 0) {
        垂直速度 = -垂直速度;
        垂直方向 = "下";
    }
    _parent.移动(垂直方向, 垂直速度);
}

