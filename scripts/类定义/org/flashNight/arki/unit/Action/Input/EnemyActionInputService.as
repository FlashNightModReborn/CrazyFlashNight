import org.flashNight.arki.unit.Action.Input.EnemyActionRuntime;

/** 原生能力输入；玩家 Lee 的普通攻击随跑动分流，特殊动作按下沿且不缓冲。 */
class org.flashNight.arki.unit.Action.Input.EnemyActionInputService {
    private static var lastUnit:Object;
    private static var lastIdentity:Object;

    /** true 表示该单位已接管整条输入，主角技能/药剂旧链不得继续执行。 */
    public static function updateControl(unit:Object):Boolean {
        var runtime:Object = unit.__enemyActionRuntime;
        if (lastUnit != null && (unit !== lastUnit || runtime.identity !== lastIdentity)) {
            // MovieClip 同路径重建会重定向旧引用；只清仍具有捕获身份的旧实例。
            if (lastUnit.__enemyActionRuntime.identity === lastIdentity) {
                EnemyActionRuntime.clearInput(lastUnit);
                EnemyActionRuntime.abortToReady(lastUnit,
                    EnemyActionRuntime.currentToken(lastUnit), "controlLost");
            }
            lastUnit = null;
            lastIdentity = null;
        }
        if (!runtime || !runtime.enabled) return false;
        lastUnit = unit;
        lastIdentity = runtime.identity;
        var mask:Number = (Key.isDown(_root.左键) ? 1 : 0)
            | (Key.isDown(_root.右键) ? 2 : 0)
            | (Key.isDown(_root.上键) ? 4 : 0)
            | (Key.isDown(_root.下键) ? 8 : 0)
            | (Key.isDown(_root.A键) ? 16 : 0)
            | (Key.isDown(_root.B键) ? 32 : 0)
            | (Key.isDown(_root.C键) ? 64 : 0)
            | (Key.isDown(_root.奔跑键) ? 128 : 0);
        for (var slot:Number = 1; slot <= 12; slot++) {
            if (Key.isDown(_root["快捷技能栏键" + slot])) mask |= 1 << (7 + slot);
        }
        var enabled:Boolean = !_root.暂停 && _root.控制目标全自动 !== true
            && unit.hp > 0 && unit._warlordActionAiHeld !== true;
        updateSample(unit, mask, enabled);
        org.flashNight.arki.scene.StageRunSession.observeInputState(unit, enabled ? mask : 0);
        return true;
    }

    public static function updateSample(unit:Object, mask:Number, enabled:Boolean):Void {
        var runtime:Object = unit.__enemyActionRuntime;
        if (!runtime || !runtime.enabled) return;
        if (!enabled) {
            EnemyActionRuntime.clearInput(unit);
            // 暂停不取消正在播放的动作；死亡则立即撤销伤害/位移资格。
            if (!(unit.hp > 0)) EnemyActionRuntime.cancel(unit, runtime.active, "death");
            return;
        }
        // 与原生行走一致：横向右优先、纵向下优先。朝向、移动和小跳
        // 消费同一份已裁决方向，避免按住相反方向时输入层与时间轴互相翻转。
        if ((mask & 3) == 3) mask &= ~1;
        if ((mask & 12) == 12) mask &= ~4;
        unit.左行 = (mask & 1) != 0;
        unit.右行 = (mask & 2) != 0;
        unit.上行 = (mask & 4) != 0;
        unit.下行 = (mask & 8) != 0;
        unit.强制奔跑 = (mask & 128) != 0;
        // 旧模板字段永不承载第二条动作触发源。
        unit.动作A = unit.动作B = unit.动作C = false;
        var actionMask:Number = mask & runtime.inputMask;
        if (runtime.inputBlocked) {
            runtime.inputPrevious = actionMask;
            if (actionMask != 0) return;
            runtime.inputBlocked = false;
        }
        // 玩家招式持续消费转向，不重启动作；外部施加的锁向仍由方向改变拒绝。
        var active:Object = runtime.active;
        if (active == null || active.action.allowFacingInput === true) {
            if ((mask & 1) != 0) unit.方向改变("左");
            else if ((mask & 2) != 0) unit.方向改变("右");
        }
        // 先结算跑/走状态：CD中的按住攻击也必须能移动；松开奔跑键当帧即改回普攻。
        if (runtime.active == null) {
            var state:String = unit.状态;
            if (state == "空手站立" || state == "空手行走" || state == "空手跑") {
                if ((mask & 15) != 0 && unit.强制奔跑 && state != "空手跑") {
                    unit.状态改变("空手跑");
                } else if (!unit.强制奔跑 && state == "空手跑") {
                    unit.状态改变("空手行走");
                }
            }
        }
        var previous:Number = runtime.inputPrevious;
        runtime.inputPrevious = actionMask;
        var inputs:Array = runtime.profile.inputs;
        // 同帧专用动作优先于普攻；所有按下沿均已消费，不在后摇结束时补发。
        for (var i:Number = inputs.length - 1; i >= 0; i--) {
            var mapping:Object = inputs[i];
            // 按住 J 只在空闲时续打；主动再按一次才可取消，防止连打抢掉新技能。
            var rising:Boolean = (previous & mapping.bit) == 0;
            if ((actionMask & mapping.bit) != 0
                && (rising || (mapping.held && runtime.active == null))) {
                var actionId:String = mapping.runningActionId != undefined && EnemyActionRuntime.isRunning(unit)
                    ? mapping.runningActionId : mapping.actionId;
                EnemyActionRuntime.request(unit, actionId, "player", null);
                return;
            }
        }

    }
}