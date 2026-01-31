import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.arki.component.Effect.*;

/**
 * 空中控制器（单位级）
 *
 * 目标：
 * - 统一管理空中（_y / 垂直速度 / 浮空 / temp_y）的更新，避免多个系统并发写入导致冲突
 * - 支持技能浮空、自然落地、跳跃浮空、喷气背包等“来源(source)”并发叠加
 * - 约束：同一帧只允许一个“物理积分器”写入 _y / 垂直速度（本控制器）
 *
 * 备注：
 * - 本文件只做“纵向物理/落地收尾”的统一；横向移动/旋转/阴影等仍由各系统负责
 */

_root.空中控制器 = _root.空中控制器 || {};

/** 容差：用于解决 Flash _y 精度导致的贴地抖动 */
_root.空中控制器._TOL = 0.5;

/** 内部：确保 unit.__air 存在 */
_root.空中控制器.确保 = function(unit:MovieClip):Object {
    if (!unit) return null;
    if (!unit.__air) {
        unit.__air = { sources: {} };
        _global.ASSetPropFlags(unit, ["__air"], 1, false);
    }
    if (!unit.__air.sources) unit.__air.sources = {};
    return unit.__air;
};

/** 内部：判断 sources 是否为空 */
_root.空中控制器._hasAnySource = function(air:Object):Boolean {
    if (!air || !air.sources) return false;
    for (var k:String in air.sources) {
        return true;
    }
    return false;
};

/** 停止控制器任务 */
_root.空中控制器.停止 = function(unit:MovieClip):Void {
    if (!unit || !unit.__air) return;
    EnhancedCooldownWheel.I().removeTaskByLabel(unit, "__air.step");
    delete unit.__air.running;
};

/** 启动控制器任务（每单位一个） */
_root.空中控制器.启动 = function(unit:MovieClip):Void {
    if (!unit) return;
    var air:Object = _root.空中控制器.确保(unit);
    if (!air) return;

    if (air.running) return;
    air.running = true;

    // 即刻执行一次，避免“等一帧才生效”的体感延迟
    _root.空中控制器._tick(unit);

    EnhancedCooldownWheel.I().addOrUpdateTask(
        unit,
        "__air.step",
        _root.空中控制器._tick,
        33,
        true,
        true,
        [unit]
    );
};

/** 设置/更新来源 */
_root.空中控制器.设置源 = function(unit:MovieClip, name:String, data:Object):Void {
    if (!unit || !name) return;
    var air:Object = _root.空中控制器.确保(unit);
    if (!air) return;
    air.sources[name] = data || {};
    _root.空中控制器.启动(unit);
};

/** 清除来源 */
_root.空中控制器.清除源 = function(unit:MovieClip, name:String):Void {
    if (!unit || !unit.__air || !unit.__air.sources) return;
    delete unit.__air.sources[name];
    if (!_root.空中控制器._hasAnySource(unit.__air)) {
        _root.空中控制器.停止(unit);
    }
};

// =============================================================================
// 对外高层 API：供“路由基础 / 跳跃 / 喷气背包”调用
// =============================================================================

/**
 * 启用技能浮空（用于空中释放技能/战技后维持重力更新）
 * @param unit:MovieClip
 * @param floatFlag:String 例如 "技能浮空"/"战技浮空"
 * @param man:MovieClip 技能/战技 man（可选，用于回写落地标记）
 */
_root.空中控制器.启用技能浮空 = function(unit:MovieClip, floatFlag:String, man:MovieClip):Void {
    _root.空中控制器.设置源(unit, "skillFloat", { floatFlag: floatFlag, man: man });
};

/** 关闭技能浮空（仅停止物理控制；是否清标记由控制器内部按状态处理） */
_root.空中控制器.关闭技能浮空 = function(unit:MovieClip):Void {
    _root.空中控制器.清除源(unit, "skillFloat");
};

/**
 * 启用自然落地（技能在空中结束但不触发二段跳时使用）
 * @param unit:MovieClip
 */
_root.空中控制器.启用自然落地 = function(unit:MovieClip):Void {
    _root.空中控制器.设置源(unit, "naturalFall", {});
};

/** 关闭自然落地 */
_root.空中控制器.关闭自然落地 = function(unit:MovieClip):Void {
    _root.空中控制器.清除源(unit, "naturalFall");
};

/**
 * 启用跳跃浮空（用于空手跳等需要脚本重力的跳跃状态）
 * @param unit:MovieClip
 * @param man:MovieClip 跳跃状态 man（用于读取坠地中等标记，并落地时回调动画完毕）
 */
_root.空中控制器.启用跳跃浮空 = function(unit:MovieClip, man:MovieClip):Void {
    _root.空中控制器.设置源(unit, "jumpFloat", { man: man });
};

/** 关闭跳跃浮空 */
_root.空中控制器.关闭跳跃浮空 = function(unit:MovieClip):Void {
    _root.空中控制器.清除源(unit, "jumpFloat");
};

/**
 * 启用快速下落（用于震地等快速下落攻击技能）
 * @param unit:MovieClip
 * @param man:MovieClip 技能容器 man（用于回写落地标记和控制播放）
 * @param gravity:Number 自定义重力加速度（默认20，比标准重力更强）
 * @param minHeight:Number 最小高度阈值，低于此高度视为落地（默认30）
 */
_root.空中控制器.启用快速下落 = function(unit:MovieClip, man:MovieClip, gravity:Number, minHeight:Number):Void {
    if (gravity == undefined || isNaN(gravity)) gravity = 20;
    if (minHeight == undefined || isNaN(minHeight)) minHeight = 30;
    _root.空中控制器.设置源(unit, "fastFall", {
        man: man,
        gravity: gravity,
        minHeight: minHeight
    });
};

/** 关闭快速下落 */
_root.空中控制器.关闭快速下落 = function(unit:MovieClip):Void {
    _root.空中控制器.清除源(unit, "fastFall");
};

/**
 * 启用被击飞浮空（用于被击飞状态的浮空控制）
 * 特殊逻辑：硬直中暂停重力，落地后触发倒地状态
 * @param unit:MovieClip
 * @param man:MovieClip 被击飞状态的 man 剪辑
 */
_root.空中控制器.启用被击飞浮空 = function(unit:MovieClip, man:MovieClip):Void {
    _root.空中控制器.设置源(unit, "knockback", { man: man });
};

/** 关闭被击飞浮空 */
_root.空中控制器.关闭被击飞浮空 = function(unit:MovieClip):Void {
    _root.空中控制器.清除源(unit, "knockback");
};

/**
 * 更新喷气背包来源（由 jetpackCheck 每帧调用）
 *
 * @param unit:MovieClip
 * @param active:Boolean 是否处于喷气背包飞行流程（喷气背包开始飞行/飞行浮空）
 * @param thrust:Number  当前帧期望推力（0 表示不推）
 * @param onlyHoverInSkill:Boolean 技能/战技期间只悬停（不提供上升）
 */
_root.空中控制器.更新喷气背包 = function(unit:MovieClip, active:Boolean, thrust:Number, onlyHoverInSkill:Boolean):Void {
    if (!active) {
        _root.空中控制器.清除源(unit, "jetpack");
        return;
    }
    _root.空中控制器.设置源(unit, "jetpack", {
        active: true,
        thrust: thrust || 0,
        onlyHoverInSkill: (onlyHoverInSkill == true)
    });
};

// =============================================================================
// 核心：统一纵向物理 tick
// =============================================================================

_root.空中控制器._tick = function(unit:MovieClip):Void {
    // unit 可能已被卸载
    if (!unit || unit._parent == undefined) {
        return;
    }
    var air:Object = unit.__air;
    if (!air || !air.sources) {
        return;
    }
    if (!_root.空中控制器._hasAnySource(air)) {
        _root.空中控制器.停止(unit);
        return;
    }

    var tol:Number = _root.空中控制器._TOL;
    var z:Number = unit.Z轴坐标;
    if (isNaN(z)) {
        // 无 Z 轴信息无法判定落地，直接退出（保守）
        return;
    }

    var state:String = unit.状态;

    // 状态切换时的来源让出（保持旧逻辑一致）
    // - 自然落地：进入跳跃/技能/战技时通常由对应系统接管；__自然落地接管=true 则不让出
    if (air.sources.naturalFall != undefined && !unit.__自然落地接管) {
        if (state == "空手跳" || state == "兵器跳" || state == "技能" || state == "战技") {
            delete air.sources.naturalFall;
        }
    }

    // - 跳跃浮空：仅在跳跃状态下有效，离开跳跃状态立即让出（避免落地回调误触发）
    if (air.sources.jumpFloat != undefined) {
        if (state != "空手跳" && state != "兵器跳") {
            delete air.sources.jumpFloat;
        }
    }

    if (!_root.空中控制器._hasAnySource(air)) {
        _root.空中控制器.停止(unit);
        return;
    }

    // 需要纵向积分的来源：任意一个存在即可
    var jet:Object = air.sources.jetpack;
    var ff:Object = air.sources.fastFall;
    var kb:Object = air.sources.knockback;
    var hasPhysics:Boolean = (air.sources.skillFloat != undefined) || (air.sources.naturalFall != undefined) || (air.sources.jumpFloat != undefined) || (jet && jet.active) || (ff != undefined) || (kb != undefined);

    if (!hasPhysics) {
        _root.空中控制器.停止(unit);
        return;
    }

    if (isNaN(unit.垂直速度)) unit.垂直速度 = 0;

    // 快速下落模式：使用自定义重力，独立处理
    if (ff != undefined) {
        var ffGravity:Number = ff.gravity || 20;
        var ffMinHeight:Number = ff.minHeight || 30;
        var currentHeight:Number = z - unit._y;

        if (currentHeight >= ffMinHeight) {
            // 还在空中，继续下落
            unit.垂直速度 += ffGravity;
            unit._y += unit.垂直速度;
            if (unit._y > z) {
                unit._y = z;
            }
            unit.temp_y = unit._y;
            unit.浮空 = true;
        } else {
            // 已落地
            unit._y = z;
            unit.temp_y = 0;
            unit.浮空 = false;
            unit.技能浮空 = false;
            if (unit.flySpeed > 0) {
                unit.flySpeed = 0;
            }
            if (ff.man) {
                ff.man.落地 = true;
                ff.man.play(); // 继续播放技能动画
            }
            delete air.sources.fastFall;
        }
        // 快速下落时不执行其他物理逻辑
        if (!_root.空中控制器._hasAnySource(air)) {
            _root.空中控制器.停止(unit);
        }
        return;
    }

    // 被击飞浮空模式：硬直中暂停重力，独立处理
    if (kb != undefined) {
        // 硬直中暂停重力更新
        if (unit.硬直中 != true) {
            unit.浮空 = true;
            unit._y += unit.垂直速度;
            unit.垂直速度 += _root.重力加速度;
        }

        // 落地检测
        if (unit._y >= z) {
            unit._y = z;
            if (kb.man) {
                kb.man.落地 = true;
                // 受身反制时触发动画完毕，否则触发倒地状态
                if (kb.man.受身反制) {
                    unit.动画完毕();
                } else {
                    unit.状态改变("倒地");
                }
            }
            delete air.sources.knockback;
        }

        // 被击飞时不执行其他物理逻辑
        if (!_root.空中控制器._hasAnySource(air)) {
            _root.空中控制器.停止(unit);
        }
        return;
    }

    // 喷气背包：技能/战技期间只悬停（不提供上升/下降）
    var hoverInSkill:Boolean = (jet && jet.active && jet.onlyHoverInSkill == true && (state == "技能" || state == "战技"));

    if (hoverInSkill) {
        // 技能/战技期间：喷气背包只负责“悬停”，但不能阻断技能自身写入的垂直速度（如升龙拳）
        // 策略：本帧仍按当前垂直速度积分一次位置；随后把垂直速度归零并且不施加重力，达到“无操作则悬停”。
        unit._y += unit.垂直速度;
        unit.temp_y = unit._y;
        unit.垂直速度 = 0;
        unit.浮空 = (unit._y < z - tol);
    } else {
        // 推力：以“设置上升速度下限”的方式实现（不叠加更强上升，避免干扰技能本身的上升）
        if (jet && jet.active && jet.thrust > 0) {
            var desiredV:Number = -jet.thrust;
            if (unit.垂直速度 > desiredV) {
                unit.垂直速度 = desiredV;
            }
        }

        // 位置/速度更新（与既有任务逻辑保持一致：先位移后加速度）
        unit._y += unit.垂直速度;
        unit.temp_y = unit._y;
        unit.垂直速度 += _root.重力加速度;
        unit.浮空 = (unit._y < z - tol);
    }

    // 技能浮空的“跳跃中方向”横向修正（保持旧逻辑：仅技能浮空时可用）
    if (air.sources.skillFloat != undefined && !(jet && jet.active)) {
        if (unit.跳跃中上下方向 == "上") {
            unit.跳跃上下移动("上", unit.跳横移速度 / 2);
        } else if (unit.跳跃中上下方向 == "下") {
            unit.跳跃上下移动("下", unit.跳横移速度 / 2);
        }
        if (unit.跳跃中左右方向 == "右") {
            unit.移动("右", unit.跳横移速度);
        } else if (unit.跳跃中左右方向 == "左") {
            unit.移动("左", unit.跳横移速度);
        }
    }

    // 状态切换：跳跃接管时，技能浮空需要让出控制权并清标记
    if (air.sources.skillFloat != undefined) {
        if (state == "空手跳" || state == "兵器跳" || state == unit.攻击模式 + "跳") {
            // 让出控制权给跳跃状态：这里不清 unit[floatFlag]
            // - enableDoubleJump 场景需要把“技能浮空”带到跳跃 load 阶段由启动跳跃浮空消费
            // - 非 enableDoubleJump 场景会在技能 man 的 onUnload 中清掉该标记
            delete air.sources.skillFloat;
        }
    }

    // 落地判定
    if (unit._y >= z - tol) {
        unit._y = z;
        unit.temp_y = 0;
        unit.浮空 = false;

        // 统一落地收尾
        if (air.sources.skillFloat != undefined) {
            sf = air.sources.skillFloat;
            if (sf.floatFlag) unit[sf.floatFlag] = false;
            if (sf.man) sf.man.落地 = true;
            delete air.sources.skillFloat;
        }

        if (air.sources.naturalFall != undefined) {
            var 需要动画完毕:Boolean = (unit.__自然落地接管 == true);
            delete unit.__自然落地接管;
            unit.技能浮空 = false;
            _root.效果("灰尘1", unit._x, unit._y, unit._xscale);
            _root.播放音效("soundland.wav");
            delete air.sources.naturalFall;
            if (需要动画完毕) {
                unit.动画完毕();
            }
        }

        if (air.sources.jumpFloat != undefined) {
            var jf:Object = air.sources.jumpFloat;
            var manRef:MovieClip = jf ? jf.man : null;
            if (manRef) {
                manRef.落地 = true;
                if (!manRef.坠地中 || manRef._currentframe < 77) {
                    _root.效果("灰尘1", unit._x, unit._y, unit._xscale);
                    _root.播放音效("soundland.wav");
                    unit.动画完毕();
                }
            } else {
                // 无 man 引用时，保守触发动画完毕
                unit.动画完毕();
            }
            delete air.sources.jumpFloat;
        }

        if (jet && jet.active) {
            unit.flySpeed = 0;
            unit.flyType = -1;
            unit.飞行浮空 = false;
            unit.喷气背包开始飞行 = 0;
            unit._rotation = 0;
            _root.fly_isFly1 = false;
            _root.fly_isFly2 = false;
            // 仅在落地时补一次落地效果（避免与 jumpFloat 重复）
            _root.效果("灰尘1", unit._x, unit._y, unit._xscale);
            _root.播放音效("soundland.wav");
            delete air.sources.jetpack;
        }
    }

    // 无来源则停止
    if (!_root.空中控制器._hasAnySource(air)) {
        _root.空中控制器.停止(unit);
    }
};
