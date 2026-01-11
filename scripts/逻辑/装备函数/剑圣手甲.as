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
 * - 二阶：挂载腕刃 + 30%常驻空手加成 + 刀剑乱舞触发70%限时加成(12s)
 * - 三阶：挂载腕刃 + 30%常驻空手加成 + 刀剑乱舞触发70%限时加成(15s)
 * - 四阶：挂载腕刃 + 30%常驻空手加成 + 刀剑乱舞触发70%限时加成(18s)
 *
 * 平衡设计：
 * - 腕刃流（单挑）：使用刀剑乱舞获得100%威力，但CD较长(24-30s)
 * - 刀剑流（对群）：不依赖刀剑乱舞，配合肩炮连杀减CD机制
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数：
 *   - weapon: 武器素材名称（默认"武士铁血腕刃"）
 *   - tier_2/tier_3/tier_4: 各进阶等级的配置节点
 *     - knifeConvertRate: 刀锋利度转换百分比（总转换率）
 *     - baseRatio: 常驻加成比例（默认0.3即30%）
 *     - burstRatio: 刀剑乱舞触发加成比例（默认0.7即70%）
 *     - burstDuration: 刀剑乱舞加成持续时间秒数（二阶12s，三阶15s，四阶18s）
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

    // 常驻/爆发加成比例配置（默认30%常驻，70%爆发）
    ref.baseRatio = (tierConfig.baseRatio != undefined) ? Number(tierConfig.baseRatio) : 0.3;
    ref.burstRatio = (tierConfig.burstRatio != undefined) ? Number(tierConfig.burstRatio) : 0.7;

    // 刀剑乱舞加成持续时间（秒），按进阶等级递增
    var defaultDurations:Array = [];
    defaultDurations[2] = 12;  // 二阶12秒
    defaultDurations[3] = 15;  // 三阶15秒
    defaultDurations[4] = 18;  // 四阶18秒
    var burstDurationSeconds:Number = (tierConfig.burstDuration != undefined) ? Number(tierConfig.burstDuration) : defaultDurations[Number(tierNum)];
    ref.burstDurationFrames = Math.ceil(burstDurationSeconds * _root.帧计时器.帧率);

    ref.buffApplied = false; // 常驻buff是否已应用

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
        target.剑圣腕刃常驻增强已应用 = false;
    }, target);

    // 用于同步渲染
    target.syncRequiredEquips.左下臂_引用 = true;
    target.dispatcher.subscribe("StatusChange", function(unit) {
        _root.装备生命周期函数.剑圣手甲渲染更新(ref);
    }, target);

    // 立即应用常驻buff（30%加成）
    target.dispatcher.subscribe("UnitInitialized", function() {
        _root.装备生命周期函数.剑圣手甲应用常驻Buff(ref);
    }, target);

    // 订阅刀剑乱舞战技事件，触发时应用爆发buff（70%加成）
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        // 检查是否为刀剑乱舞战技
        if (ref.自机.技能名 == "刀剑乱舞") {
            _root.装备生命周期函数.剑圣手甲应用爆发Buff(ref);
        }
    }, target);

    // _root.发布消息("剑圣腕刃系统启动 - " + tier);
};

/**
 * 剑圣手甲 - 应用常驻腕刃增强buff（30%加成）
 * 将装备刀锋利度加成的30%转换为空手攻击力加成
 * 使用buffManager持久化管理，无时间限制
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲应用常驻Buff = function(ref:Object):Void {
    var target:MovieClip = ref.自机;
    if (!target.buffManager) return;

    // 使用target上的标记防止重复应用（跨ref对象）
    if (target.剑圣腕刃常驻增强已应用) return;

    var knifeBonus:Number = target.装备刀锋利度加成 || 0;
    // 只应用baseRatio比例（默认30%）的加成
    var bonusValue:Number = Math.floor(knifeBonus * ref.knifeConvertRate * ref.baseRatio);

    if (bonusValue > 0) {
        // 构建MetaBuff：空手攻击力加算（常驻）
        var childBuffs:Array = [
            new PodBuff("空手攻击力", BuffCalculationType.ADD, bonusValue)
        ];

        // 无时间限制，手动控制移除
        var components:Array = [];
        var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

        target.buffManager.addBuff(metaBuff, "剑圣腕刃常驻增强");
        target.buffManager.update(0);

        // 在target上标记已应用，防止跨ref重复
        target.剑圣腕刃常驻增强已应用 = true;
        ref.buffApplied = true;

        // _root.发布消息("剑圣腕刃常驻增强已应用，buff值=" + bonusValue + "（30%）");
    }
};

/**
 * 剑圣手甲 - 应用爆发腕刃增强buff（70%加成）
 * 刀剑乱舞战技触发时，将剩余70%的刀锋利度加成转换为限时空手攻击力加成
 * 使用同ID替换机制，重复触发会刷新持续时间
 * 同时控制腕刃辉光的显示/隐藏
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲应用爆发Buff = function(ref:Object):Void {
    var target:MovieClip = ref.自机;
    if (!target.buffManager) return;

    var knifeBonus:Number = target.装备刀锋利度加成 || 0;
    // 应用burstRatio比例（默认70%）的加成
    var bonusValue:Number = Math.floor(knifeBonus * ref.knifeConvertRate * ref.burstRatio);

    if (bonusValue > 0) {
        // 构建MetaBuff：空手攻击力加算（限时）
        // 同时抵消等量的刀锋利度加成，避免双重加成
        var childBuffs:Array = [
            new PodBuff("空手攻击力", BuffCalculationType.ADD, bonusValue),
            new PodBuff("装备刀锋利度加成", BuffCalculationType.ADD, bonusValue * -1)
        ];

        // 添加时间限制组件，到期自动移除
        var components:Array = [
            new TimeLimitComponent(ref.burstDurationFrames)
        ];
        var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

        // 使用固定ID，重复触发会替换（刷新持续时间）
        target.buffManager.addBuff(metaBuff, "剑圣腕刃爆发增强");
        target.buffManager.update(0);

        // 启动辉光效果
        _root.装备生命周期函数.剑圣手甲设置辉光(ref, true);

        // _root.发布消息("剑圣腕刃爆发增强已应用，buff值=" + bonusValue + "（70%），持续" + (ref.burstDurationFrames / _root.帧计时器.帧率) + "秒");
    }
};

/**
 * 剑圣手甲 - 设置腕刃辉光可见性
 * 用于视觉反馈爆发buff的激活状态
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Boolean} visible 是否可见
 */
_root.装备生命周期函数.剑圣手甲设置辉光 = function(ref:Object, visible:Boolean):Void {
    var weapon:MovieClip = ref.weapon;
    if (weapon && weapon.辉光) {
        weapon.辉光._visible = visible;
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

    // 检查腕刃反转标签，叠加一次反转
    if (target.man.腕刃反转标签) {
        mirrored = !mirrored;
        // 腕刃素材朝向修正：加180度使其指向手臂延伸方向
        angle += 180;
    }

    

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
 * 同时检查爆发buff状态并同步辉光显示
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
        org.flashNight.arki.unit.HeroUtil.isFistSkill(target.技能名);

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
            // 新创建的weapon，根据当前buff状态设置辉光
            _root.装备生命周期函数.剑圣手甲同步辉光状态(ref);
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

    // 同步辉光状态（检查爆发buff是否仍然存在）
    _root.装备生命周期函数.剑圣手甲同步辉光状态(ref);
};

/**
 * 剑圣手甲 - 同步辉光状态
 * 根据爆发buff是否存在来控制辉光显示
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲同步辉光状态 = function(ref:Object):Void {
    var weapon:MovieClip = ref.weapon;
    if (!weapon || !weapon.辉光) return;

    var target:MovieClip = ref.自机;
    if (!target.buffManager) return;

    // 检查爆发buff是否存在（通过buffManager的_idMap）
    var hasBurstBuff:Boolean = (target.buffManager._idMap["剑圣腕刃爆发增强"] != undefined);
    weapon.辉光._visible = hasBurstBuff;
};
