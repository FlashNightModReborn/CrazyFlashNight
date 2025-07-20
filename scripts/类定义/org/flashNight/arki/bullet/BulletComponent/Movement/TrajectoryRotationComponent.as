import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;

/**
 * TrajectoryRotationComponent - 轨迹旋转组件
 * 
 * 负责根据目标的移动轨迹来计算并更新其旋转角度。
 * 这是一个辅助组件，旨在与 IMovement 实现类组合使用。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.TrajectoryRotationComponent implements IMovement {
    // 内部状态
    private var _lastX:Number;
    private var _lastY:Number;
    
    // 配置参数
    private var _enable:Boolean;
    private var _offset:Number;

    /**
     * 构造函数
     * @param enable:Boolean   是否默认启用自动旋转。
     * @param offset:Number    旋转的偏移角度。
     */
    public function TrajectoryRotationComponent(enable:Boolean, offset:Number) {
        this._enable = (enable != undefined) ? enable : true;
        this._offset = (offset != undefined) ? offset : 0;
    }

    /**
     * 初始化组件，记录目标的初始位置。
     * 应该在运动开始的第一帧调用。
     * @param target:MovieClip 目标对象。
     */
    public function initialize(target:MovieClip):Void {
        this._lastX = target._x;
        this._lastY = target._y;
    }

    /**
     * 每帧更新，计算并应用旋转。
     * @param target:MovieClip 目标对象。
     */
    public function updateMovement(target:MovieClip):Void {
        // 如果未启用，则直接返回
        if (!this._enable) {
            return;
        }

        // 1. 计算位移
        var deltaX:Number = target._x - this._lastX;
        var deltaY:Number = target._y - this._lastY;
        
        // 2. 只有在有显著移动时才更新旋转，避免静止时抖动或无效计算
        if (Math.abs(deltaX) > 0.01 || Math.abs(deltaY) > 0.01) {
            // 计算角度并转换为度数
            var angleRad:Number = Math.atan2(deltaY, deltaX);
            var angleDeg:Number = angleRad * 180 / Math.PI;
            
            // 应用旋转
            target._rotation = angleDeg + this._offset;
        }

        // 3. 记录当前坐标，为下一帧做准备
        this._lastX = target._x;
        this._lastY = target._y;
    }

    // --- 公共的 Getters 和 Setters ---

    public function setEnable(enable:Boolean):Void {
        this._enable = enable;
    }

    public function getEnable():Boolean {
        return this._enable;
    }

    public function setOffset(offset:Number):Void {
        this._offset = offset;
    }

    public function getOffset():Number {
        return this._offset;
    }
}