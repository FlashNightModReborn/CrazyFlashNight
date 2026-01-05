/**
 * 剑圣手甲 - 装备生命周期函数
 *
 * 功能特性：
 * - 在底层背景上挂载"武士铁血腕刃"
 * - 跟随左下臂_引用的位置和旋转
 * - 攻击模式为"空手"时展开腕刃，其他模式收缩
 *
 * 动画帧约定：
 * - 第1帧：完全收缩状态
 * - 第1-15帧：展开动画
 * - 第15帧：完全展开状态
 * - 收缩时反向播放15->1
 *
 * 进阶等级效果：
 * - 无进阶：不挂载腕刃，直接移除周期函数
 * - 二阶：挂载腕刃
 * - 三阶：挂载腕刃 + 待扩展
 * - 四阶：挂载腕刃 + 待扩展
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数：
 *   - weapon: 武器素材名称（默认"武士铁血腕刃"）
 */
_root.装备生命周期函数.剑圣手甲初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // 获取装备进阶等级
    var equipItem:Object = target[ref.装备类型];
    var tier:String = equipItem && equipItem.value ? equipItem.value.tier : null;
    ref.tier = tier;

    // 无进阶：不挂载腕刃，直接移除周期函数
    if (!tier) {
        _root.装备生命周期函数.移除周期函数(ref);
        return;
    }

    // 进阶等级映射
    var tierNum:String;
    switch (tier) {
        case "二阶": tierNum = "2"; break;
        case "三阶": tierNum = "3"; break;
        case "四阶": tierNum = "4"; break;
        default:
            _root.装备生命周期函数.移除周期函数(ref);
            return;
    }

    // 从XML读取进阶配置
    var tierConfig:Object = param ? param["tier_" + tierNum] : null;
    if (!tierConfig) {
        _root.装备生命周期函数.移除周期函数(ref);
        return;
    }

    // 武器配置（从XML读取）
    ref.weaponAsset = param.weapon ? param.weapon : "武士铁血腕刃";
    ref.weaponDepth = 10001; // 与胸甲错开深度
    ref.weaponName = ref.weaponAsset + "剑圣_手甲";

    // 动画帧配置（从XML读取）
    ref.minFrame = param.minFrame ? Number(param.minFrame) : 1;
    ref.maxFrame = param.maxFrame ? Number(param.maxFrame) : 15;
    ref.currentFrame = ref.minFrame;
    ref.weapon = null;  // 初始不创建，需要时才挂载

    // 刀锋利度转换百分比（从XML读取）
    ref.knifeConvertRate = Number(tierConfig.knifeConvertRate) || 0;
    ref.buffApplied = false; // buff是否已应用

    // 缓存坐标转换用的点对象，避免每帧创建
    ref.localPoint = {x: 0, y: 0};
    ref.p0 = {x: 0, y: 0};
    ref.pX = {x: 100, y: 0};
    ref.pY = {x: 0, y: 100};

    // 订阅玩家模板重新初始化事件，清理残留weapon和buff标记
    target.dispatcher.subscribe("InitPlayerTemplateEnd", function() {
        var layer:MovieClip = target.底层背景;
        if (layer[ref.weaponName]) {
            layer[ref.weaponName].removeMovieClip();
        }
        // 清除target级标记，允许重新应用buff
        target.剑圣腕刃增强已应用 = false;
    }, target);

    // 用于同步渲染
    target.syncRequiredEquips.左下臂_引用 = true;
    target.dispatcher.subscribe("StatusChange", function(unit) {
        _root.装备生命周期函数.剑圣手甲渲染更新(ref);
    }, target);

    // 立即应用buff
    target.dispatcher.subscribe("UnitInitialized", function() {
        _root.装备生命周期函数.剑圣手甲应用Buff(ref);
    },target);

    // _root.发布消息("剑圣腕刃系统启动 - " + tier);
};

/**
 * 剑圣手甲 - 应用腕刃增强buff
 * 将装备刀锋利度加成的一定百分比转换为空手攻击力加成
 * 使用buffManager持久化管理
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲应用Buff = function(ref:Object):Void {
    var target:MovieClip = ref.自机;
    if (!target.buffManager) return;

    // 使用target上的标记防止重复应用（跨ref对象）
    if (target.剑圣腕刃增强已应用) return;

    var knifeBonus:Number = target.装备刀锋利度加成 || 0;
    var bonusValue:Number = Math.floor(knifeBonus * ref.knifeConvertRate);

    // 调试：记录应用buff前的空手攻击力
    // _root.发布消息("应用buff前 - 空手攻击力=" + target.空手攻击力 + ", 装备刀锋利度加成=" + knifeBonus);

    if (bonusValue > 0) {
        // 构建MetaBuff：空手攻击力加算
        var childBuffs:Array = [
            new PodBuff("空手攻击力", BuffCalculationType.ADD, bonusValue)
        ];

        // _root.发布消息("剑圣腕刃增强计算: 装备刀锋利度加成=" + knifeBonus + " × 转换率=" + ref.knifeConvertRate + " = " + bonusValue);

        // 无时间限制，手动控制移除
        var components:Array = [];
        var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

        target.buffManager.addBuff(metaBuff, "剑圣腕刃增强");
        target.buffManager.update(0);

        // _root.发布消息("剑圣腕刃增强已应用，buff值=" + bonusValue);
        // _root.发布消息("应用buff后 - 空手攻击力=" + target.空手攻击力);

        // 在target上标记已应用，防止跨ref重复
        target.剑圣腕刃增强已应用 = true;
        ref.buffApplied = true;
    }
};


/**
 * 剑圣手甲 - 渲染更新函数
 * 更新weapon的位置和旋转，跟随左下臂_引用
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲渲染更新 = function(ref:Object) {
    var weapon:MovieClip = ref.weapon;
    var target:MovieClip = ref.自机;
    var forearm:MovieClip = target.左下臂_引用;

    if (!weapon || !forearm) {
        return;
    }

    // weapon 的容器（底层背景）
    var container:MovieClip = target.底层背景;

    // 位移：以 左下臂_引用 的原点作为挂点
    var localPoint:Object = ref.localPoint;
    localPoint.x = 0;
    localPoint.y = 0;
    forearm.localToGlobal(localPoint);
    container.globalToLocal(localPoint);
    weapon._x = localPoint.x;
    weapon._y = localPoint.y;

    // 旋转/翻转：用坐标变换求真实朝向，兼容动作中身体引用被镜像
    var p0:Object = ref.p0;
    var pX:Object = ref.pX;
    var pY:Object = ref.pY;
    p0.x = 0;   p0.y = 0;
    pX.x = 100; pX.y = 0;
    pY.x = 0;   pY.y = 100;

    forearm.localToGlobal(p0);
    forearm.localToGlobal(pX);
    forearm.localToGlobal(pY);
    container.globalToLocal(p0);
    container.globalToLocal(pX);
    container.globalToLocal(pY);

    var vxX:Number = pX.x - p0.x;
    var vxY:Number = pX.y - p0.y;
    var vyX:Number = pY.x - p0.x;
    var vyY:Number = pY.y - p0.y;

    var angle:Number = Math.atan2(vxY, vxX) * 180 / Math.PI;
    var det:Number = vxX * vyY - vxY * vyX; // <0 表示发生镜像（左右翻转）
    var mirrored:Boolean = (det < 0);

    if (mirrored) {
        angle -= 180;
        if (weapon._xscale > 0) {
            weapon._xscale = -weapon._xscale;
        }
    } else {
        if (weapon._xscale < 0) {
            weapon._xscale = -weapon._xscale;
        }
    }
    weapon._rotation = angle;
};

/**
 * 剑圣手甲 - 周期函数
 * 控制腕刃的展开/收缩动画
 * 性能优化：收缩到第1帧时移除weapon，需要时再创建
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲周期 = function(ref:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);

    var tier:String = ref.tier;
    if (!tier) {
        return;
    }

    var target:MovieClip = ref.自机;

    // 检查攻击模式，空手或拳类技能时展开腕刃
    var shouldDeploy:Boolean = (target.攻击模式 == "空手") ||
        (target.技能名 != undefined && target.技能名.indexOf("拳") > -1);

    // 动画状态机
    if (shouldDeploy) {
        // 需要展开
        if (ref.currentFrame < ref.maxFrame) {
            ref.currentFrame++;
        }
        // 确保weapon存在
        if (!ref.weapon) {
            var layer:MovieClip = target.底层背景;
            var weapon:MovieClip = layer.attachMovie(ref.weaponAsset, ref.weaponName, ref.weaponDepth);
            weapon.stop();
            ref.weapon = weapon;
        }
        // 更新显示帧和位置
        ref.weapon.gotoAndStop(ref.currentFrame);
        _root.装备生命周期函数.剑圣手甲渲染更新(ref);
    } else {
        // 需要收缩
        if (ref.currentFrame > ref.minFrame) {
            ref.currentFrame--;
            // 收缩过程中仍需更新
            if (ref.weapon) {
                ref.weapon.gotoAndStop(ref.currentFrame);
                _root.装备生命周期函数.剑圣手甲渲染更新(ref);
            }
        } else if (ref.weapon) {
            // 已完全收缩，移除weapon
            ref.weapon.removeMovieClip();
            ref.weapon = null;
        }
    }
};
