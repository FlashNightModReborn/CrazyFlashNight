import flash.display.BitmapData;
import flash.geom.Rectangle;
import flash.geom.Matrix;
import org.flashNight.sara.util.*;

class org.flashNight.sara.util.Tile extends BitmapData {
    private var aabb:AABB; // AABB 表示瓦片的边界

    // 构造函数，传入地图影片剪辑和瓦片的边界
    public function Tile(mapClip:MovieClip, bounds:AABB) {
        // 初始化 BitmapData
        super(bounds.getWidth(), bounds.getLength(), true, 0x00000000);

        this.aabb = bounds;

        // 生成位图数据，切片并缓存
        this.createTileBitmap(mapClip);
    }

    // 从地图影片剪辑切割并缓存位图数据
    private function createTileBitmap(mapClip:MovieClip):Void {
        var matrix:Matrix = new Matrix(1, 0, 0, 1, -this.aabb.getLeft(), -this.aabb.getTop());
        this.draw(mapClip, matrix);
    }

    // 获取当前瓦片的 AABB 边界
    public function getBounds():AABB {
        return this.aabb;
    }
}
