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
    ref.isGlowActive = false;  // 预设辉光状态为关闭（常驻态）

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

    // 缓存坐标转换用的点对象，避免每帧创建
    ref.localPoint = {x: 0, y: 0};
    ref.p0 = {x: 0, y: 0};
    ref.pX = {x: 100, y: 0};
    ref.pY = {x: 0, y: 100};

    // 订阅玩家模板重新初始化事件，清理残留weapon
    target.dispatcher.subscribe("UnitReInitialized", function() {
        var layer:MovieClip = target.底层背景;
        if (layer[ref.weaponName]) {
            layer[ref.weaponName].removeMovieClip();
        }
    }, target);

    // 左下臂引用加载时同步渲染
    target.syncRefs.左下臂_引用 = true;
    target.dispatcher.subscribe("左下臂_引用", function(unit) {
        _root.装备生命周期函数.剑圣手甲渲染更新(ref);
    }, target);

    // 初始化 Buff 系统（使用 EventListenerComponent 统一管理）
    target.dispatcher.subscribe("UnitInitialized", function() {
        _root.装备生命周期函数.剑圣手甲初始化Buff系统(ref);
    }, target);

    // _root.发布消息("剑圣腕刃系统启动 - " + tier);
};

/**
 * 剑圣手甲 - 初始化 Buff 系统
 * 使用 EventListenerComponent 统一管理常驻/爆发状态切换
 *
 * 设计模式：
 * - 一个控制器 MetaBuff（永久）挂载 EventListenerComponent
 * - 一个效果 buff ID "剑圣腕刃增强"，通过同 ID 替换切换状态
 * - 辉光状态在回调中直接控制，无需轮询
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲初始化Buff系统 = function(ref:Object):Void {
    var target:MovieClip = ref.自机;
    if (!target.buffManager) return;

    // 预计算数值
    var knifeBonus:Number = target.装备刀锋利度加成 || 0;
    var baseValue:Number = Math.floor(knifeBonus * ref.knifeConvertRate * ref.baseRatio);
    var burstValue:Number = Math.floor(knifeBonus * ref.knifeConvertRate * ref.burstRatio);
    var fullValue:Number = baseValue + burstValue;  // 爆发态的总加成

    // 无加成则不创建 buff
    if (baseValue <= 0 && burstValue <= 0) return;

    // 缓存数值到 ref 供回调使用
    ref.baseValue = baseValue;
    ref.burstValue = burstValue;
    ref.fullValue = fullValue;

    // ========== 1. 创建控制器 MetaBuff ==========
    // EventListenerComponent 监听 WeaponSkill 事件
    var eventComp:EventListenerComponent = new EventListenerComponent({
        dispatcher: target.dispatcher,
        eventName: "WeaponSkill",
        filter: function(mode:String):Boolean {
            // 只响应刀剑乱舞技能
            return ref.自机.技能名 == "刀剑乱舞";
        },
        duration: ref.burstDurationFrames,
        onActivate: function():Void {
            // 切换到爆发态
            _root.装备生命周期函数.剑圣手甲切换到爆发态(ref);
        },
        onDeactivate: function():Void {
            // 切换回常驻态
            _root.装备生命周期函数.剑圣手甲切换到常驻态(ref);
        },
        onRefresh: function():Void {
            // 刷新时保持爆发态（duration 自动刷新，无需额外操作）
        }
    });

    // 控制器 MetaBuff（永久，无 PodBuff，仅挂载 EventListenerComponent）
    var controllerMeta:MetaBuff = new MetaBuff([], [eventComp], 0);
    target.buffManager.addBuff(controllerMeta, "剑圣腕刃控制器");

    // ========== 2. 立即应用常驻态效果 ==========
    _root.装备生命周期函数.剑圣手甲切换到常驻态(ref);
};

/**
 * 剑圣手甲 - 切换到常驻态
 * 应用 30% 基础加成，关闭辉光
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲切换到常驻态 = function(ref:Object):Void {
    var target:MovieClip = ref.自机;
    if (!target.buffManager) return;

    var baseValue:Number = ref.baseValue;
    if (baseValue > 0) {
        // 构建常驻态 MetaBuff
        var childBuffs:Array = [
            new PodBuff("空手攻击力", BuffCalculationType.ADD, baseValue)
        ];
        var metaBuff:MetaBuff = new MetaBuff(childBuffs, [], 0);

        // 同 ID 替换
        target.buffManager.addBuff(metaBuff, "剑圣腕刃增强");
    }

    // 关闭辉光
    _root.装备生命周期函数.剑圣手甲设置辉光(ref, false);
};

/**
 * 剑圣手甲 - 切换到爆发态
 * 应用 100% 完整加成（30% + 70%），开启辉光
 * 同时抵消等量刀锋利度加成，避免双重计算
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲切换到爆发态 = function(ref:Object):Void {
    var target:MovieClip = ref.自机;
    if (!target.buffManager) return;

    var fullValue:Number = ref.fullValue;
    var burstValue:Number = ref.burstValue;

    if (fullValue > 0) {
        // 构建爆发态 MetaBuff
        // 空手攻击力获得完整加成，同时抵消刀锋利度加成避免双重计算
        var childBuffs:Array = [
            new PodBuff("空手攻击力", BuffCalculationType.ADD, fullValue),
            new PodBuff("装备刀锋利度加成", BuffCalculationType.ADD, -burstValue)
        ];
        var metaBuff:MetaBuff = new MetaBuff(childBuffs, [], 0);

        // 同 ID 替换
        target.buffManager.addBuff(metaBuff, "剑圣腕刃增强");
    }

    // 开启辉光
    _root.装备生命周期函数.剑圣手甲设置辉光(ref, true);
};

/**
 * 剑圣手甲 - 设置腕刃辉光可见性
 * 用于视觉反馈爆发buff的激活状态
 *
 * 通过 ref.isGlowActive 标记跟踪状态，确保 weapon 重建时能正确恢复
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Boolean} visible 是否可见
 */
_root.装备生命周期函数.剑圣手甲设置辉光 = function(ref:Object, visible:Boolean):Void {
    // 记录辉光状态，供 weapon 重建时使用
    ref.isGlowActive = visible;

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
 *
 * 注意：辉光状态由 EventListenerComponent 的回调直接控制，无需轮询
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣手甲周期 = function(ref:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);

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
        }
        // 更新显示帧和位置
        ref.weapon.gotoAndStop(ref.currentFrame);
        _root.装备生命周期函数.剑圣手甲渲染更新(ref);
        // 每帧同步辉光状态（解决 attachMovie 后子元件加载延迟问题）
        if (ref.weapon.辉光) {
            ref.weapon.辉光._visible = (ref.isGlowActive === true);
        }
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
