import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.component.Collider.AbstractColliderFactory extends LightObjectPool implements IColliderFactory  {

    private var factoryReference:AbstractColliderFactory; // 保存工厂自身引用

    /**
     * 构造函数
     * 
     * @param createFunc 创建对象的函数，必须返回一个ICollider实例
     * @param initialSize 初始分配的对象数量，可选
     */
    public function AbstractColliderFactory(createFunc:Function, initialSize:Number) {
        super(createFunc);
        this.factoryReference = this; // 保存工厂引用
        initializePool(initialSize);
    }

    /**
     * 可选：初始化对象池，预先分配一定数量的对象进入池中，提高高频场景下的性能。
     */
    private function initializePool(initialSize:Number):Void {
        if (initialSize > 0) {
            for (var i:Number = 0; i < initialSize; i++) {
                var obj:ICollider = ICollider(this.createFunc());
                this.releaseObject(obj);
            }
        }
    }

    public function getObject():ICollider {
        var obj:ICollider = ICollider(super.getObject());
        obj.setFactory(this.factoryReference); // 确保工厂引用一致
        return obj;
    }

    /**
     * 将使用完的 ICollider 回收进对象池
     * 子类可直接使用此方法，或根据需要重写
     * 
     * @param collider 要释放的ICollider实例
     */
    public function releaseCollider(collider:ICollider):Void {
        collider.setFactory(null); // 清空工厂引用
        this.releaseObject(collider);
    }

    /**
     * 占位方法：基于透明子弹创建 ICollider 实例
     * 子类必须重写此方法，补充具体逻辑
     * 
     * @param bullet 透明子弹对象
     * @return ICollider 实例
     */
    public function createFromTransparentBullet(bullet:Object):ICollider {
        throw new Error("Abstract method createFromTransparentBullet must be overridden by subclass");
        return null;
    }

    /**
     * 占位方法：基于子弹与检测区域创建 ICollider 实例
     * 子类必须重写此方法，补充具体逻辑
     * 
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹检测区域 MovieClip 实例
     * @return ICollider 实例
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        throw new Error("Abstract method createFromBullet must be overridden by subclass");
        return null;
    }

    /**
     * 占位方法：基于单位区域创建 ICollider 实例
     * 子类必须重写此方法，补充具体逻辑
     * 
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return ICollider 实例
     */
    public function createFromUnitArea(unit:MovieClip):ICollider {
        throw new Error("Abstract method createFromUnitArea must be overridden by subclass");
        return null;
    }
}