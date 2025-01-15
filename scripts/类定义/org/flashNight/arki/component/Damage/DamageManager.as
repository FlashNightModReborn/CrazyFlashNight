// File: org/flashNight/arki/component/Damage/DamageManager.as

import org.flashNight.arki.component.Damage.IDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.DamageManager {

    private var _handles:Array;          // IDamageHandle 列表
    public var overlapRatio:Number;      // 用于多段 / 霰弹计算
    public var dodgeState:String;        // 躲闪状态
    // 你也可以在这里加更多需要在各个 Handle 中共享的变量

    public function DamageManager() {
        this._handles = [];
        this.overlapRatio = 1;
        this.dodgeState = "";
    }

    /**
     * 添加一个处理器到列表
     */
    public function addHandle(handle:IDamageHandle):Void {
        this._handles.push(handle);
    }

    /**
     * 执行所有处理器
     * @param bullet   子弹
     * @param shooter  发射者
     * @param target   被击中目标
     * @param result   DamageResult
     */
    public function execute(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        // 顺序调用 handle
        for (var i:Number = 0; i < this._handles.length; i++) {
            var handle:IDamageHandle = IDamageHandle(this._handles[i]);
            handle.handleBulletDamage(bullet, shooter, target, this, result);
        }
    }
}
