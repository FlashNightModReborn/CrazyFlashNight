import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.render.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.spatial.transform.*;

/**
 * AABBRenderer 类
 *
 * 用于可视化调试 AABB 碰撞器（AABBCollider）的边界框，
 * 采用静态方法提供统一接口，无需实例化。
 */
class org.flashNight.arki.render.AABBRenderer {

    /**
     * 渲染传入的 AABBCollider 对象对应的轴对齐边界框。
     * 为便于调试，本方法绘制一个无填充、仅显示线框的矩形，
     * 并依据 AABBCollider 的 left、right、top、bottom 值计算四个顶点。
     *
     * @param collider 需要调试绘制的 AABBCollider 对象
     */
    public static function renderAABB(iCollider:ICollider):Void {
        if (iCollider == null) return;
        
        var collider:AABB = iCollider.getAABB(0).moveNew(SceneCoordinateManager.effectOffset);

        var p0:Vector = new Vector(collider.left, collider.top);
        var p1:Vector = new Vector(collider.right, collider.top);
        var p2:Vector = new Vector(collider.right, collider.bottom);
        var p3:Vector = new Vector(collider.left, collider.bottom);
        
        // 调用 VectorAfterimageRenderer 绘制线框
        // 参数依次为：点数组、填充色、线条色、线宽、填充透明度、线条透明度、残影数量（shadowCount）
        VectorAfterimageRenderer.instance.drawShape(
            [p0, p1, p2, p3],
            0xFF0000,   // 填充色（红色）
            0x00FF00,   // 线条色（绿色）
            2,          // 线宽
            80,         // 填充透明度
            100,        // 线条透明度
            30          // 残影数量（可根据实际需要调整）
        );
    }
}
