// File: org/flashNight/arki/component/Damage/DamageManager.as

import org.flashNight.arki.component.Damage.IDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;

class org.flashNight.arki.component.Damage.DamageManager {

    private var _allHandles:Array;    // 所有可用的处理器
    private var _handles:Array;       // 当前适用的处理器
    public var overlapRatio:Number;   // 用于多段 / 霰弹计算
    public var dodgeState:String;     // 躲闪状态

    public function DamageManager() {
        this._allHandles = [];
        this._handles = [];
        this.overlapRatio = 1;
        this.dodgeState = "";
    }

    /**
     * 注册所有可能的处理器
     * 通常在初始化时调用
     */
    public function registerHandle(handle:IDamageHandle):Void {
        this._allHandles.push(handle);
    }

    /**
     * 根据子弹属性，选择性地添加处理器到 _handles
     * @param bullet 子弹对象
     */
    public function initializeHandles(bullet:Object):Void {
        this._handles = [];
        for (var i:Number = 0; i < this._allHandles.length; i++) {
            var handle:IDamageHandle = IDamageHandle(this._allHandles[i]);
            if (handle.canHandle(bullet)) {
                this._handles.push(handle);
            }
        }
    }

    /**
     * 添加一个处理器到列表（兼容旧方法）
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
