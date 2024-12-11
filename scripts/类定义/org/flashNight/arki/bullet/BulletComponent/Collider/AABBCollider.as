import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

/**
 * AABBCollider 类
 * 
 * 通过继承 AABB 类，实现 ICollider 接口，
 * 提供基于轴对齐边界框（AABB）的碰撞检测功能。
 * 使用 Vector 类作为点和向量的数据结构。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider extends AABB implements ICollider {
    
    /**
     * 构造函数，初始化 AABB 碰撞器的边界
     * @param left 左边界坐标
     * @param right 右边界坐标
     * @param top 上边界坐标
     * @param bottom 下边界坐标
     */
    public function AABBCollider(left:Number, right:Number, top:Number, bottom:Number) {
        super(left, right, top, bottom);
    }

    /**
     * 实现 ICollider 接口的碰撞检查方法。
     * 逻辑：
     * 1. 获取对方的 AABB 信息。
     * 2. 使用 AABB 的 intersects 方法进行初步碰撞检测。
     * 3. 如果 AABB 相交，计算碰撞中心点并返回 CollisionResult。
     * 
     * @param other 另一个 ICollider 实例
     * @return 碰撞结果 CollisionResult 实例
     */
    public function checkCollision(other:ICollider):CollisionResult {
        var result:CollisionResult;

        // 获取对方的 AABB 信息
        var otherAABB:AABB = other.getAABB();

        // 使用 AABB 的相交检测
        var isColliding:Boolean = this.intersects(otherAABB);
        result = new CollisionResult(isColliding);
        
        if (isColliding) {
            // 计算重叠区域的中心点
            var overlapCenter:Vector = this.getOverlapCenter(otherAABB);
            if (overlapCenter) {
                result.addInfo("overlapCenter", overlapCenter);
            }
        }
        return result;
    }

    /**
     * 实现 ICollider 接口的碰撞响应方法。
     * 可以根据需要执行相应的碰撞响应逻辑。
     * 
     * @param result 碰撞结果 CollisionResult 实例
     */
    public function handleCollision(result:CollisionResult):Void {
        if (result.isColliding) {
            var overlapCenter:Vector = result.additionalInfo["overlapCenter"];
            if (overlapCenter) {
                // 根据 overlapCenter 进行碰撞响应处理
                // 冲击力和特效或许可以在这里回调？
                // 具体先占位再考虑，还是应该组件化抽离
            }
        }
    }

    /**
     * 获取 AABB 信息
     * 
     * @return 当前实例作为 AABB 返回
     */
    public function getAABB():AABB {
        return this;
    }

    /**
     * 获取点集信息，利用aabb class本身的能力
     * 
     * @return PointSet 实例化
     */
    public function getPoints():PointSet{
        return this.toPointSet();
    };

    /**
     * 计算两个 AABB 重叠区域的中心点
     * 
     * @param other 另一个 AABB 实例
     * @return 重叠区域中心点的 Vector 实例，如果无重叠则返回 null
     */
    private function getOverlapCenter(other:AABB):Vector {
        if (!this.intersects(other)) {
            return null;
        }

        // 计算重叠区域的边界
        var overlapLeft:Number = Math.max(this.left, other.left);
        var overlapRight:Number = Math.min(this.right, other.right);
        var overlapTop:Number = Math.max(this.top, other.top);
        var overlapBottom:Number = Math.min(this.bottom, other.bottom);

        // 计算重叠区域的中心点
        var centerX:Number = (overlapLeft + overlapRight) / 2;
        var centerY:Number = (overlapTop + overlapBottom) / 2;

        return new Vector(centerX, centerY);
    }
}