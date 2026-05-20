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
 *
 *   规划中的扩展（后续迭代，本阶段未做）：
 *   - runJumpFloat          — 启动跳跃浮空(883) + 空中控制器 / EnhancedCooldownWheel 边界 stub
 *   - 飞行状态读写(1442/1476) / 攻击模式切换(1104) 复刻
 *   - ContainerFrameScriptContract — 容器帧脚本 → 玩家模板 调用契约回放
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
     * 字段集合 = 动画完毕(998) 决策树读写到的全部单位字段；
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
}
