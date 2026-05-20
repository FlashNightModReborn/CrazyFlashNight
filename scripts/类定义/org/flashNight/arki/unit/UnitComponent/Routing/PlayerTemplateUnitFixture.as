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
 *   - runStoreFlyState / runLoadFlyState — 飞行状态读写(1442/1476) 忠实复刻（slot1/slot2 快照）
 *   - runAttackModeSwitch   — 攻击模式切换(1104) 忠实复刻（武器持有门控 + 双枪合并）
 *
 *   规划中的扩展（后续迭代，本阶段未做）：
 *   - ContainerFrameScriptContract — 容器帧脚本 → 玩家模板 调用契约回放（见 ContainerFrameScriptContract.as）
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

        // ──── 飞行状态读写(1442/1476) 字段 ────
        u.flyType = 1;
        u.flySpeed = 0;
        u.leftFlySpeed = 0;
        u.rightFlySpeed = 0;
        u.upFlySpeed = 0;
        u.downFlySpeed = 0;

        // ──── 攻击模式切换(1104) 武器持有字段 ────
        u.手雷 = false;
        u.长枪 = false;
        u.刀 = false;
        u.手枪 = false;
        u.手枪2 = false;
        u.是否允许发送联机数据 = false;

        // ──── spy 计数 ────
        u.__spy_stateChanges = [];
        u.__spy_stateChangeCount = 0;
        u.__spy_aabbUpdateCount = 0;
        u.__spy_flyStoreCalls = [];
        u.__spy_bonusModeReads = [];

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

        // ──── collaborator spy：存储当前飞行状态 / 根据模式重新读取武器加成 ────
        // 注：runStoreFlyState 是 存储当前飞行状态 的复刻；此处的 spy 仅供 runAttackModeSwitch
        // 记录"是否调了 存储当前飞行状态"，两者分属不同层（复刻 vs collaborator 记录）。
        u.存储当前飞行状态 = function(type) {
            this.__spy_flyStoreCalls.push(type);
        };
        u.根据模式重新读取武器加成 = function(mode) {
            this.__spy_bonusModeReads.push(mode);
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
     *   本复刻把 scheduler / airProvider 提为显式形参以便 testloader 隔离注入 —— 同
     *   runAnimationDone 用显式 unit.X 的取舍。
     *
     *   **airProvider 是函数不是对象**：原函数在 body 与 onUnload(line 947) 各**重新读取**
     *   一次 `_root.空中控制器`（live read，非 setup 期捕获）。本复刻在 body 与 onUnload
     *   各调一次 airProvider() 还原此语义 —— 使测试能覆盖"启动时有 air、卸载时 air 被
     *   替换/置空/损坏"的不可靠边界场景（空中控制器不可假设可靠）。若复刻成捕获快照，
     *   这类场景将不可测。
     *
     * @param unit         夹具单位（untyped）
     * @param man          跳跃状态 man 剪辑（untyped，建议 MockMovieClip）
     * @param scheduler    调度器 stub（需 removeTask 方法）
     * @param airProvider  返回当前空中控制器的函数 ():air；body 与 onUnload 各取一次。
     *                     provider 本身或其返回值为 undefined 均视作"无 air"，安全跳过。
     */
    public static function runJumpFloat(unit, man, scheduler, airProvider):Void {
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

        // 接入空中控制器：跳跃状态接管纵向物理（body 期 live-read airProvider）
        var air = (airProvider != undefined) ? airProvider() : undefined;
        if (air != undefined) {
            air.关闭自然落地(unit);
            air.启用跳跃浮空(unit, man);
        }

        // onUnload 清理（链式叠加 prev）
        var manRef = man;
        var unitRef = unit;
        var schedulerRef = scheduler;
        var airProviderRef = airProvider;
        var prevOnUnload:Function = man.onUnload;
        man.onUnload = function() {
            if (prevOnUnload != undefined) {
                prevOnUnload.apply(this);
            }
            manRef.坠地中 = false;
            unitRef.浮空 = false;
            unitRef.刚体 = false;
            // onUnload 期**重新读取** air —— 复刻原函数 line 947 的 live read，
            // 而非用 setup 期捕获值，使 air 在卸载前被替换/置空的场景可测。
            var airNow = (airProviderRef != undefined) ? airProviderRef() : undefined;
            if (airNow != undefined) {
                airNow.关闭跳跃浮空(unitRef);
            }
            if (unitRef.__跳跃浮空任务ID != null) {
                schedulerRef.removeTask(unitRef.__跳跃浮空任务ID);
                unitRef.__跳跃浮空任务ID = null;
            }
        };
    }

    // ════════════════════════════════════════════════════════════════════
    // runStoreFlyState / runLoadFlyState — 飞行状态读写(1442/1476) 忠实复刻
    // ════════════════════════════════════════════════════════════════════

    /**
     * root 桩对象：代替原函数读写的 _root 全局（控制目标 + fly_* 飞行状态寄存器）。
     *
     * 受控分歧（已知）：原函数直接读写 `_root.控制目标` 与 `_root.fly_*`（约 20 个槽位
     *   + fly_isFly1/2 两个标志）；本复刻把它们收进单个 root 形参 —— 同 runJumpFloat
     *   把 airProvider 提为形参的取舍，且 Routing/* class 不应直接触达 _root
     *   （[[feedback-routing-runtime-adapter-surface]]）。root 字段名与 `_root.fly_*`
     *   1:1（如 root.fly_isFly1 ↔ _root.fly_isFly1）。
     *
     * fly_* 是**跨状态切换的飞行快照寄存器**：slot1 给"切换武器"、slot2 给"状态改变"。
     */

    /**
     * 复刻自 单位函数_fs_aka_玩家模板迁移.as:1442-1473 的 _root.主角函数.存储当前飞行状态。
     *
     * 门控：type 空值兜底为 "状态改变"；须 unit 为控制目标 && 飞行浮空 && flyType==1。
     *   S1  type==="切换武器" && fly_isFly1!=true → 写 slot1（fly_isFly1=true, fly_isFly2=false）
     *   S2  type==="状态改变" && fly_isFly1!=true → 写 slot2（fly_isFly2=true）
     *
     * @param unit  夹具单位（untyped）
     * @param type  "切换武器" / "状态改变"；空值兜底 "状态改变"
     * @param root  _root 桩对象（控制目标 + fly_*）
     */
    public static function runStoreFlyState(unit, type, root):Void {
        if (!type) {
            type = "状态改变";
        }
        if (unit._name === root.控制目标 && unit.飞行浮空 && unit.flyType == 1) {
            if (type === "切换武器" && root.fly_isFly1 != true) {
                root.fly_isFly1 = true;
                root.fly_isFly2 = false;
                root.fly_flySpeed1 = unit.flySpeed;
                root.fly_leftFlySpeed1 = unit.leftFlySpeed;
                root.fly_rightFlySpeed1 = unit.rightFlySpeed;
                root.fly_upFlySpeed1 = unit.upFlySpeed;
                root.fly_downFlySpeed1 = unit.downFlySpeed;
                root.fly_y1 = unit._y;
                root.fly_起始Y1 = unit.起始Y;
                root.fly_Z轴坐标1 = unit.Z轴坐标;
            }
            if (type === "状态改变" && root.fly_isFly1 != true) {
                root.fly_isFly2 = true;
                root.fly_flySpeed2 = unit.flySpeed;
                root.fly_leftFlySpeed2 = unit.leftFlySpeed;
                root.fly_rightFlySpeed2 = unit.rightFlySpeed;
                root.fly_upFlySpeed2 = unit.upFlySpeed;
                root.fly_downFlySpeed2 = unit.downFlySpeed;
                root.fly_y2 = unit._y;
                root.fly_起始Y2 = unit.起始Y;
                root.fly_Z轴坐标2 = unit.Z轴坐标;
            }
        }
    }

    /**
     * 复刻自 单位函数_fs_aka_玩家模板迁移.as:1476-1509 的 _root.主角函数.读取当前飞行状态。
     *
     * 门控：unit 非控制目标直接 return（**注意：不校验 飞行浮空/flyType**，与 存储 不对称）。
     *   L1  type==="切换武器" && fly_isFly1==true → 读 slot1（fly_isFly1=false, 飞行浮空=true）
     *   L2  type==="状态改变" && fly_isFly2==true && fly_isFly1!=true → 读 slot2
     *       （fly_isFly2=false, 飞行浮空=true）—— fly_isFly1 为真会阻断 slot2 读取
     *
     * @param unit  夹具单位（untyped）
     * @param type  "切换武器" / "状态改变"；空值兜底 "状态改变"
     * @param root  _root 桩对象（控制目标 + fly_*）
     */
    public static function runLoadFlyState(unit, type, root):Void {
        if (unit._name !== root.控制目标) {
            return;
        }
        if (!type) {
            type = "状态改变";
        }
        if (type === "切换武器" && root.fly_isFly1 == true) {
            root.fly_isFly1 = false;
            unit.flySpeed = root.fly_flySpeed1;
            unit.leftFlySpeed = root.fly_leftFlySpeed1;
            unit.rightFlySpeed = root.fly_rightFlySpeed1;
            unit.upFlySpeed = root.fly_upFlySpeed1;
            unit.downFlySpeed = root.fly_downFlySpeed1;
            unit._y = root.fly_y1;
            unit.起始Y = root.fly_起始Y1;
            unit.Z轴坐标 = root.fly_Z轴坐标1;
            unit.飞行浮空 = true;
        } else if (type === "状态改变" && root.fly_isFly2 == true && root.fly_isFly1 != true) {
            root.fly_isFly2 = false;
            unit.flySpeed = root.fly_flySpeed2;
            unit.leftFlySpeed = root.fly_leftFlySpeed2;
            unit.rightFlySpeed = root.fly_rightFlySpeed2;
            unit.upFlySpeed = root.fly_upFlySpeed2;
            unit.downFlySpeed = root.fly_downFlySpeed2;
            unit._y = root.fly_y2;
            unit.起始Y = root.fly_起始Y2;
            unit.Z轴坐标 = root.fly_Z轴坐标2;
            unit.飞行浮空 = true;
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // runAttackModeSwitch — 攻击模式切换(1104) 忠实复刻
    // ════════════════════════════════════════════════════════════════════

    /**
     * 复刻自 单位函数_fs_aka_玩家模板迁移.as:1104-1152 的 _root.主角函数.攻击模式切换。
     *
     * 切换前置：飞行浮空 && 控制目标 → 存储当前飞行状态("切换武器")。
     * 早装配：模式 != "手枪" → 根据模式重新读取武器加成(模式)。
     * 模式决策（武器持有门控；模式是单一值，等价 switch）：
     *   空手                       → 攻击模式=空手, 状态改变
     *   手雷 && unit.手雷           → 非联机时 攻击模式=手雷, 状态改变
     *   长枪 && unit.长枪           → 攻击模式=长枪, 状态改变
     *   兵器 && unit.刀             → 攻击模式=兵器, 状态改变
     *   手枪:
     *     手枪 && 手枪2 → 攻击模式="双枪", 根据模式("手枪2"), 根据模式("手枪"), 状态改变
     *     仅 手枪        → 攻击模式="手枪",  根据模式("手枪"),  状态改变
     *     仅 手枪2       → 攻击模式="手枪2", 根据模式("手枪2"), 状态改变
     * 尾部：dpsInvalidator(unit) 恒调用；控制目标 → root.玩家信息界面.刷新攻击模式。
     *
     * 受控分歧（已知）：原函数尾部调静态 `PlayerInfoProvider.invalidateDpsCache(this)` 与
     *   读 `_root.控制目标` / `_root.玩家信息界面`；本复刻把 DPS 失效提为 dpsInvalidator
     *   形参（同 airProvider 取舍，避免拖入 PlayerInfoProvider class），_root 收进 root 桩。
     *
     * @param unit          夹具单位（untyped）
     * @param 模式          目标攻击模式字符串
     * @param root          _root 桩对象（控制目标 + 玩家信息界面 + fly_*）
     * @param dpsInvalidator 函数 (unit):Void，复刻 PlayerInfoProvider.invalidateDpsCache
     */
    public static function runAttackModeSwitch(unit, 模式, root, dpsInvalidator):Void {
        if (unit.飞行浮空 && unit._name === root.控制目标) {
            unit.存储当前飞行状态("切换武器");
        }
        if (模式 != "手枪") {
            unit.根据模式重新读取武器加成(模式);
        }
        if (模式 === "空手") {
            unit.攻击模式 = 模式;
            unit.状态改变("攻击模式切换");
        }
        if (模式 === "手雷" && unit.手雷) {
            if (unit.是否允许发送联机数据 != true) {
                unit.攻击模式 = 模式;
                unit.状态改变("攻击模式切换");
            }
        }
        if (模式 === "长枪" && unit.长枪) {
            unit.攻击模式 = 模式;
            unit.状态改变("攻击模式切换");
        }
        if (模式 === "兵器" && unit.刀) {
            unit.攻击模式 = 模式;
            unit.状态改变("攻击模式切换");
        }
        if (模式 === "手枪") {
            if (unit.手枪2 && unit.手枪) {
                unit.攻击模式 = "双枪";
                unit.根据模式重新读取武器加成("手枪2");
                unit.根据模式重新读取武器加成("手枪");
                unit.状态改变("攻击模式切换");
            } else if (unit.手枪) {
                unit.攻击模式 = "手枪";
                unit.根据模式重新读取武器加成("手枪");
                unit.状态改变("攻击模式切换");
            } else if (unit.手枪2) {
                unit.攻击模式 = "手枪2";
                unit.根据模式重新读取武器加成("手枪2");
                unit.状态改变("攻击模式切换");
            }
        }
        if (dpsInvalidator != undefined) {
            dpsInvalidator(unit);
        }
        if (root.控制目标 === unit._name) {
            root.玩家信息界面.刷新攻击模式(unit.攻击模式);
        }
    }
}
