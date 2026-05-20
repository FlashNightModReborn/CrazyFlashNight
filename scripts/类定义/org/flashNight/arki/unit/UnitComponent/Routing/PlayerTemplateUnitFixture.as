import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * PlayerTemplateUnitFixture — 玩家模板路由调用面 黑箱夹具（第三阶段）
 *
 * 目的：把"玩家模板如何使用路由 / 状态机"的真实调用面落成可测夹具结构，
 *       让端到端测试能在隔离环境里复现玩家模板与 Routing/* 的交互。
 *
 * ════════════════════════════════════════════════════════════════════
 * 为什么是"复刻"而不是"绑定真实函数"
 * ════════════════════════════════════════════════════════════════════
 *   动画完毕 / 启动跳跃浮空 等是 _root.主角函数.* 的 timeline 函数，定义在
 *   单位函数_fs_aka_玩家模板迁移.as —— 该文件不进 testloader 编译单元，
 *   testloader 里没有 _root.主角函数。因此夹具不能 `unit.动画完毕 =
 *   _root.主角函数.动画完毕`，只能**忠实复刻**其算法（沿用 RoutingEndToEndTest
 *   的 runSkillRouteEntry 先例）。
 *
 *   控制分歧（已知、受控）：原 timeline 函数靠 MovieClip timeline scope 解析
 *   裸标识符（跳横移速度 / 左行 / 攻击模式 ...）；本夹具单位是 plain MockMovieClip，
 *   不复刻 timeline scope，复刻函数一律用显式 unit.X。
 *
 * ════════════════════════════════════════════════════════════════════
 * 当前覆盖范围
 * ════════════════════════════════════════════════════════════════════
 *   - makeUnit              — 带 spy 的测试单位（MockMovieClip 基座）
 *   - runAnimationDone      — 动画完毕(998) 决策树忠实复刻（9 分支）
 *   - runJumpFloat          — 启动跳跃浮空(883) 忠实复刻（3 起跳分支 + 任务清理 + onUnload 闭包）
 *
 *   规划中的扩展（后续迭代，本阶段未做）：
 *   - 飞行状态读写(1442/1476) / 攻击模式切换(1104) 复刻
 *   - ContainerFrameScriptContract — 容器帧脚本 → 玩家模板 调用契约回放
 *
 * ════════════════════════════════════════════════════════════════════
 * 测试分层（decision vs integration）—— 防"复刻测试过度信心"
 * ════════════════════════════════════════════════════════════════════
 *   见 [[feedback-reproduction-test-overconfidence]]。runAnimationDone 是 998 的
 *   转抄，单测它只证明"复刻符合决策 spec"，**不**证明 _root.主角函数.动画完毕 真这么跑。
 *
 *   · decision 层：直接调 runAnimationDone(unit)，验证 998 决策树分支表。
 *   · integration 层：bindAnimationDoneReproduction(unit) 后，用**真实**
 *     RoutingLifecycle.completeAnimation 驱动 unit.动画完毕()，验证 routing→玩家模板
 *     的 orchestration 接缝（completeAnimation 是真 production class，有真牙齿）。
 *   · 残余 gap：复刻 ↔ 真 动画完毕 / 启动跳跃浮空 的保真度无法在 testloader 内测
 *     （玩家模板.as 不进编译单元），由"对源码的人工 review"把关 —— review-gated。
 *   · 注：启动跳跃浮空 无 completeAnimation 这类 production class 接缝，integration
 *     退化为 lifecycle 层 —— onUnload 经**真实 MockMovieClip.removeMovieClip** 触发后验证。
 *
 * AS2 strict 类型注意（[[feedback-as2-strict-function-param-dynamic-path]]）：
 * makeUnit 返回值与 runAnimationDone 形参一律 untyped，避免 :MovieClip 形参注解
 * 拒收 :MockMovieClip。
 *
 * 用法：org.flashNight.arki.unit.UnitComponent.Routing.PlayerTemplateUnitFixture.makeUnit("X");
 */
class org.flashNight.arki.unit.UnitComponent.Routing.PlayerTemplateUnitFixture {

    // ════════════════════════════════════════════════════════════════════
    // 夹具构造
    // ════════════════════════════════════════════════════════════════════

    /**
     * 构造一个玩家模板测试单位。
     *
     * 字段集合 = 动画完毕(998) / 启动跳跃浮空(883) 读写到的单位字段；
     * collaborator（状态改变 / aabbCollider.updateFromUnitArea）以 spy 形式注入，
     * 测试断言走 __spy_* 字段。
     *
     * 返回值 untyped：见类注释的 strict 类型说明。
     */
    public static function makeUnit(name:String) {
        var u:MockMovieClip = new MockMovieClip();
        u.__name = name;
        u._name = name;

        // ──── 动画完毕(998) 决策树字段 ────
        u.技能名 = undefined;
        u.hp = 100;
        u.状态 = "空手站立";
        u.攻击模式 = "空手";
        u.跳横移速度 = 0;
        u.跑X速度 = 5;
        u.左行 = false;
        u.右行 = false;
        u.上行 = false;
        u.下行 = false;
        u.技能浮空 = false;
        u.__preserveFloatFlagOnUnload = undefined;
        u.飞行浮空 = false;
        u.垂直速度 = 0;
        u.起跳速度 = -10;
        u.起始Y = 0;
        u.Z轴坐标 = 100;
        u._y = 100;

        // ──── 启动跳跃浮空(883) / completeAnimation 集成所需字段 ────
        u.浮空 = false;
        u.temp_y = 0;
        u.刚体 = false;
        u.__技能浮空任务ID = undefined;
        u.__自然落地任务ID = undefined;
        u.__跳跃浮空任务ID = undefined;

        // ──── spy 计数 ────
        u.__spy_stateChanges = [];
        u.__spy_stateChangeCount = 0;
        u.__spy_aabbUpdateCount = 0;

        // ──── collaborator spy：状态改变 ────
        // 生产侧 真实实现是 StateTransition.apply（已 class 化，由 StateTransitionTest 覆盖）。
        // 夹具这里只记录"动画完毕 决定路由到哪个状态"，不重复跑状态机。
        u.状态改变 = function(新状态名) {
            this.__spy_stateChanges.push(新状态名);
            this.__spy_stateChangeCount++;
        };

        // ──── collaborator spy：aabbCollider.updateFromUnitArea ────
        u.aabbCollider = {
            __owner: u,
            updateFromUnitArea: function(unit) {
                this.__owner.__spy_aabbUpdateCount++;
            }
        };

        return u;
    }

    // ════════════════════════════════════════════════════════════════════
    // runAnimationDone — 动画完毕(998) 决策树忠实复刻
    // ════════════════════════════════════════════════════════════════════

    /**
     * 复刻自 单位函数_fs_aka_玩家模板迁移.as:998-1044 的 _root.主角函数.动画完毕。
     *
     * 决策树（9 分支）：
     *   B1  hp<=0                                  → 状态改变("血腥死")
     *   B2  状态===攻击模式+"跳" && 跳横移速度===跑X速度 && 方向键
     *                                              → 状态改变(攻击模式+"跑")
     *   B3  技能浮空 && 飞行浮空 && 持枪族
     *         · wantsDoubleJump → 补垂直速度/起始Y + delete __preserve
     *         · 技能浮空=false   → 状态改变(攻击模式+"站立")
     *   B4-prep 技能浮空 && wantsDoubleJump && 攻击模式==="兵器"
     *                                              → 补垂直速度/起始Y（不 delete __preserve）
     *   B4  技能浮空 && 攻击模式∈{空手,兵器}        → 状态改变(攻击模式+"跳")
     *   B5  技能浮空 && 其他攻击模式                → 状态改变("空手跳")
     *   B6  落地兜底                                → 状态改变(攻击模式+"站立") + aabb 更新
     *
     * @param unit  夹具单位（untyped，见类注释）
     */
    public static function runAnimationDone(unit):Void {
        unit.技能名 = null;

        // B1：死亡兜底
        if (unit.hp <= 0) {
            unit.状态改变("血腥死");
            return;
        }

        // B2：跳跃中按方向键且跳横移速度=跑速 → 衔接到跑
        if (unit.状态 === unit.攻击模式 + "跳"
            && unit.跳横移速度 === unit.跑X速度
            && (unit.左行 || unit.右行 || unit.上行 || unit.下行)) {
            unit.状态改变(unit.攻击模式 + "跑");
            return;
        }

        // 技能浮空分支
        if (unit.技能浮空) {
            var wantsDoubleJump:Boolean = (unit.__preserveFloatFlagOnUnload == "技能浮空");

            // B3：喷气背包飞行 + 持枪族（持枪无"跳"分支，保持站立继续射击/飞行）
            if (unit.飞行浮空 && (unit.攻击模式 === "长枪" || unit.攻击模式 === "双枪"
                || unit.攻击模式 === "手枪" || unit.攻击模式 === "手枪2")) {
                if (wantsDoubleJump) {
                    unit.垂直速度 = unit.起跳速度;
                    unit.起始Y = unit.Z轴坐标;
                    delete unit.__preserveFloatFlagOnUnload;
                }
                unit.技能浮空 = false;
                unit.状态改变(unit.攻击模式 + "站立");
                return;
            }

            // B4-prep：兵器跳 enableDoubleJump 预补起跳速度
            if (wantsDoubleJump && unit.攻击模式 === "兵器") {
                unit.垂直速度 = unit.起跳速度;
                unit.起始Y = unit.Z轴坐标;
            }

            // B4：空手 / 兵器 → 对应跳；B5：其他攻击模式 → 空手跳
            if (unit.攻击模式 === "空手" || unit.攻击模式 === "兵器") {
                unit.状态改变(unit.攻击模式 + "跳");
                return;
            } else {
                unit.状态改变("空手跳");
                return;
            }
        }

        // B6：普通落地兜底
        unit.状态改变(unit.攻击模式 + "站立");
        unit.aabbCollider.updateFromUnitArea(unit);
    }

    // ════════════════════════════════════════════════════════════════════
    // bindAnimationDoneReproduction — 把 unit.动画完毕 绑到 998 复刻
    // ════════════════════════════════════════════════════════════════════

    /**
     * 供 integration 层使用：让真实 RoutingLifecycle.completeAnimation 调
     * unit.动画完毕() 时进入决策树复刻，从而端到端验证 routing→玩家模板 接缝。
     *
     * @param unit  夹具单位（untyped，见类注释）
     */
    public static function bindAnimationDoneReproduction(unit):Void {
        unit.动画完毕 = function() {
            PlayerTemplateUnitFixture.runAnimationDone(this);
        };
    }

    // ════════════════════════════════════════════════════════════════════
    // runJumpFloat — 启动跳跃浮空(883) 忠实复刻
    // ════════════════════════════════════════════════════════════════════

    /**
     * 复刻自 单位函数_fs_aka_玩家模板迁移.as:883-956 的 _root.主角函数.启动跳跃浮空。
     *
     * 起跳模式三分支：
     *   J1  技能浮空==true              → 二段跳：清 技能浮空 + delete __preserve +
     *                                     垂直速度=起跳速度 + 起始Y=Z轴坐标（不 gotoAndPlay）
     *   J2  原本在空中 || temp_y>0       → 空中进入：man.gotoAndPlay("跳跃状态") + 起始Y=Z轴坐标
     *                                     （跳过翻滚动画，不动垂直速度）
     *   J3  正常起跳                     → 垂直速度=起跳速度 + 起始Y=Z轴坐标（不 gotoAndPlay）
     *
     *   原本在空中 = (浮空==true) || (_y < Z轴坐标-0.5)，**必须在 浮空 置位前算**
     *   —— 否则 J3 恒不可达（原函数注释强调的时序，本复刻保留）。
     *
     * 无条件副作用：man.跳跃移动倍率/落地/坠地中 初始化（在三分支之前）；浮空=true、
     *   temp_y=0（三分支之后）；清 __跳跃浮空任务ID / __技能浮空任务ID 旧任务；
     *   airController 关闭自然落地 + 启用跳跃浮空；挂 onUnload 闭包（链式叠加 prev）。
     *
     * 受控分歧（已知）：原函数硬编码 `EnhancedCooldownWheel.I()` 与读 `_root.空中控制器`；
     *   本复刻把 scheduler / airController 提为显式形参以便 testloader 隔离注入 —— 同
     *   runAnimationDone 用显式 unit.X 的取舍。onUnload 闭包内原函数在 unload 时重读
     *   `_root.空中控制器`，本复刻用 setup 期捕获的 airController（稳定 air 下等价）。
     *
     * @param unit          夹具单位（untyped）
     * @param man           跳跃状态 man 剪辑（untyped，建议 MockMovieClip）
     * @param scheduler     调度器 stub（需 removeTask 方法）
     * @param airController 空中控制器 stub（关闭自然落地/启用跳跃浮空/关闭跳跃浮空），可为 undefined
     */
    public static function runJumpFloat(unit, man, scheduler, airController):Void {
        // 原本在空中：在设置 浮空 标记之前判断
        var 原本在空中:Boolean = (unit.浮空 == true) || (unit._y < unit.Z轴坐标 - 0.5);

        man.跳跃移动倍率 = 1;
        man.落地 = false;
        man.坠地中 = false;

        if (unit.技能浮空 == true) {
            // J1 二段跳
            unit.技能浮空 = false;
            delete unit.__preserveFloatFlagOnUnload;
            unit.垂直速度 = unit.起跳速度;
            unit.起始Y = unit.Z轴坐标;
        } else if (原本在空中 || unit.temp_y > 0) {
            // J2 空中进入（非二段跳）：跳过翻滚动画
            man.gotoAndPlay("跳跃状态");
            unit.起始Y = unit.Z轴坐标;
        } else {
            // J3 正常起跳
            unit.垂直速度 = unit.起跳速度;
            unit.起始Y = unit.Z轴坐标;
        }

        unit.浮空 = true;
        unit.temp_y = 0;

        // 清理旧跳跃浮空 / 技能浮空任务（防重复并发）
        if (unit.__跳跃浮空任务ID != null) {
            scheduler.removeTask(unit.__跳跃浮空任务ID);
            unit.__跳跃浮空任务ID = null;
        }
        if (unit.__技能浮空任务ID != null) {
            scheduler.removeTask(unit.__技能浮空任务ID);
            unit.__技能浮空任务ID = null;
        }

        // 接入空中控制器：跳跃状态接管纵向物理
        if (airController != undefined) {
            airController.关闭自然落地(unit);
            airController.启用跳跃浮空(unit, man);
        }

        // onUnload 清理（链式叠加 prev）
        var manRef = man;
        var unitRef = unit;
        var schedulerRef = scheduler;
        var airRef = airController;
        var prevOnUnload:Function = man.onUnload;
        man.onUnload = function() {
            if (prevOnUnload != undefined) {
                prevOnUnload.apply(this);
            }
            manRef.坠地中 = false;
            unitRef.浮空 = false;
            unitRef.刚体 = false;
            if (airRef != undefined) {
                airRef.关闭跳跃浮空(unitRef);
            }
            if (unitRef.__跳跃浮空任务ID != null) {
                schedulerRef.removeTask(unitRef.__跳跃浮空任务ID);
                unitRef.__跳跃浮空任务ID = null;
            }
        };
    }
}
