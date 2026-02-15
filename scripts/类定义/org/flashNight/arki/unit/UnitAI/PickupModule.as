import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.UnitAIData;

/**
 * 拾取模块 — 作为子状态机嵌入根机 EnemyBehavior
 *
 * 内部状态：ChasingPickup (唯一)
 * 退出条件：由根机 Gate 检测（目标消失 / area==null / 超时）
 *
 * 使用方式：
 *   根机调用 setPickupEnabled() 注册本模块
 *   Selector 找到拾取物后设 data.target = item 并 ChangeState("PickupModule")
 */
class org.flashNight.arki.unit.UnitAI.PickupModule extends FSM_StateMachine {

    public static var CHASE_PICKUP_TIME:Number = 30; // 最大拾取时间 = 30 action（120帧）

    public function PickupModule(_data:UnitAIData) {
        super(null, null, null);
        // C3d: data 必须在 AddStatus 之前设定
        this.data = _data;

        this.AddStatus("ChasingPickup", new FSM_Status(this.chase_pickup, null, null));
        // 无内部转换，退出完全由根机 Gate 控制
    }

    // ═══════ 拾取物品 ═══════

    public function chase_pickup():Void {
        data.updateSelf();
        data.updateTarget();

        var self = data.self;
        var pickupXRange = isNaN(self.x轴拾取距离) ? 40 : self.x轴拾取距离;
        var pickupZRange = 20;

        if (data.absdiff_z < pickupZRange && data.absdiff_x < pickupXRange) {
            // 拾取范围内
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            if (data.diff_x < 0) {
                self.方向改变("左");
            } else if (data.diff_x > 0) {
                self.方向改变("右");
            }
            self.状态改变("拾取");
        } else {
            var sm = this.superMachine;
            if (sm.actionCount % 2 == 0) {
                if (data.absdiff_x + data.absdiff_z < 150) {
                    self.状态改变(self.攻击模式 + "行走");
                } else if (self.状态 != self.攻击模式 + "跑" && LinearCongruentialEngine.instance.randomCheck(3)) {
                    self.状态改变(self.攻击模式 + "跑");
                }
                self.上行 = data.diff_z < 0;
                self.下行 = data.diff_z > 0;
                self.左行 = data.diff_x < 0;
                self.右行 = data.diff_x > 0;
            }
        }
    }
}
