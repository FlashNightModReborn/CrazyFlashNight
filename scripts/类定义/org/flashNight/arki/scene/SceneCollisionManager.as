import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;
import org.flashNight.sara.util.Vector;
import org.flashNight.arki.collision.CollisionLayerRenderer;

/**
SceneCollisionManager.as
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.SceneCollisionManager {

    public static var instance:SceneCollisionManager; // 单例引用

    public var collisionLayer:MovieClip;
    public var collisions:Array;
    public var movieClipCollisions:Array;

    private var redrawDirtyMark:Boolean = false;
    private var drawCount:Number = 0;

    /**
     * 单例获取：返回全局唯一实例
     */
    public static function getInstance():SceneCollisionManager {
        return instance || (instance = new SceneCollisionManager());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function SceneCollisionManager() {
    }

    public function init():Void{
        // 先清理上一场景可能遗留的绘图与 MC 强引用，再绑定新层。
        // 正常卸载路径已会 dispose；这里是针对异常跳转的幂等安全网。
        dispose();
        this.collisionLayer = _root.collisionLayer;
        this.collisions = [];
        this.movieClipCollisions = [];
        this.redrawDirtyMark = false;
        this.drawCount = 0;
    }

    public function addCollisions(_collisions):Void{
        if (this.collisionLayer == null || _collisions == null) return;
        if (this.collisions == null) this.collisions = [];

        // 场景环境、分段背景等可以分别提交多组 polygon。
        // 每次输入都必须追加且断开外部引用，不能覆盖先前来源。
        var appended:Array = ObjectUtil.toArray(ObjectUtil.clone(_collisions));
        for (var i:Number = 0; i < appended.length; i++) {
            this.collisions.push(appended[i]);
        }
    }

    // rect 是调用方提交的世界坐标快照。障碍移动或改形后再次提交；
    // 默认当帧生效。批量提交传 false，最后 redraw()，或等待 update()。
    public function addMovieClipCollision(mc:MovieClip, rect:Object, forceUpdate:Boolean):Void {
        // AVM1 的原生 getRect 结果带四个坐标，却可能与 null 松比较相等。
        if (this.collisionLayer == null || mc == null ||
            rect.xMin === undefined || rect.xMax === undefined ||
            rect.yMin === undefined || rect.yMax === undefined) return;
        if (this.movieClipCollisions == null) this.movieClipCollisions = [];

        var immediate:Boolean = forceUpdate !== false;
        for (var i:Number = 0; i < this.movieClipCollisions.length; i++) {
            var current:Object = this.movieClipCollisions[i];
            if (current.mc === mc) {
                var old:Object = current.rect;
                if (old.xMin != rect.xMin || old.yMin != rect.yMin ||
                    old.xMax != rect.xMax || old.yMax != rect.yMax) {
                    current.rect = copyBounds(rect);
                    this.redrawDirtyMark = true;
                }
                if (immediate && this.redrawDirtyMark) redraw();
                return;
            }
        }
        var bounds:Object = copyBounds(rect);
        this.movieClipCollisions.push({mc: mc, rect: bounds});
        if (!immediate) {
            this.redrawDirtyMark = true;
        } else if (this.redrawDirtyMark) {
            redraw();
        } else {
            // 首绘只追加这一个矩形。登记先于绘制完成通知。
            CollisionLayerRenderer.drawRect(this.collisionLayer, bounds);
        }
    }

    private static function copyBounds(rect:Object):Object {
        return {xMin:rect.xMin, yMin:rect.yMin, xMax:rect.xMax, yMax:rect.yMax};
    }

    // 默认合并移除。需要本次调用返回时即可通行的机关传 true。
    public function removeMovieClipCollision(mc:MovieClip, forceUpdate:Boolean):Boolean {
        if (mc == null || this.movieClipCollisions == null) return false;
        for (var i:Number = this.movieClipCollisions.length - 1; i >= 0; i--) {
            var mcColli:Object = this.movieClipCollisions[i];
            if (mcColli.mc === mc) {
                mcColli.mc = null;
                mcColli.rect = null;
                this.movieClipCollisions.splice(i, 1);
                this.redrawDirtyMark = true;
                if (forceUpdate) redraw();
                return true;
            }
        }
        return false;
    }

    // update 函数，被 SceneManager 调用
    public function update():Void{
        if (this.collisionLayer == null || this.movieClipCollisions == null) return;
        this.drawCount++;
        // 每4帧检查一次：如果影片剪辑已卸载，移除对应的碰撞箱信息并标脏
        if(this.drawCount % 4 == 0){
            for(var i = this.movieClipCollisions.length - 1; i > -1; i--){
                var mcColli:Object = this.movieClipCollisions[i];
                if(mcColli.mc == null || !mcColli.mc._name){
                    mcColli.mc = null;
                    mcColli.rect = null;
                    this.movieClipCollisions.splice(i, 1);
                    this.redrawDirtyMark = true;
                }
            }
        }
        // 上次重绘后，第 21 次及以后的有效更新可以提交待处理的变更。
        if(this.redrawDirtyMark && this.drawCount > 20){
            redraw();
        }
    }

    // 重绘所有碰撞箱
    public function redraw():Void{
        var layer:MovieClip = this.collisionLayer;
        if (layer == null) return;
        layer.clear();

        // 再次计算边界坐标并绘制外框
        var point:Vector = SceneCoordinateManager.calculateOffset();
		var xmin:Number = _root.Xmin - point.x;
		var xmax:Number = _root.Xmax - point.x;
		var ymin:Number = _root.Ymin - point.y;
		var ymax:Number = _root.Ymax - point.y;
		// 调用统一渲染器绘制边界碰撞箱
		CollisionLayerRenderer.drawBoundary(
			layer,
			xmin, xmax, ymin, ymax,
			300,  // margin
			_root.调试模式, true
		);
        
        // 根据存储的数组再次绘制碰撞箱
        if (this.collisions != null){
            CollisionLayerRenderer.drawPolygons(layer, this.collisions, true);
        }

        // 再次绘制影片剪辑碰撞箱
        for(var i = 0; i < this.movieClipCollisions.length; i++){
            var mcColli:Object = this.movieClipCollisions[i];
            CollisionLayerRenderer.drawRect(layer, mcColli.rect, true);
        }

        this.redrawDirtyMark = false;
        this.drawCount = 0;
        // 订阅者可以在回调内再次修改碰撞。先提交本轮状态，再通知。
        CollisionLayerRenderer.finishDrawing(layer, _root.调试模式);
    }

    /**
     * 完整清理方法（幂等）
     * 用于游戏重启时的彻底清理
     */
    public function dispose():Void {
        this.redrawDirtyMark = false;
        this.drawCount = 0;

        // 清除精确绑定的旧层。正常场景下它就是 _root.collisionLayer；
        // 异常重建时也不得误清新层。
        if (this.collisionLayer != null) {
            if (this.collisionLayer === _root.collisionLayer) {
                CollisionLayerRenderer.clearAll();
            } else {
                this.collisionLayer.clear();
                CollisionLayerRenderer.markDirty();
            }
        }

        // 显式断开动态碰撞记录持有的旧 MovieClip/矩形强引用。
        if (this.movieClipCollisions != null) {
            for (var i:Number = 0; i < this.movieClipCollisions.length; i++) {
                var mcColli:Object = this.movieClipCollisions[i];
                if (mcColli != null) {
                    mcColli.mc = null;
                    mcColli.rect = null;
                }
                this.movieClipCollisions[i] = null;
            }
        }
        if (this.collisions != null) {
            for (var j:Number = 0; j < this.collisions.length; j++) {
                this.collisions[j] = null;
            }
        }

        this.movieClipCollisions = null;
        this.collisions = null;
        this.collisionLayer = null;
    }

    /**
     * 重置单例状态（用于游戏重启后重新初始化）
     */
    public function reset():Void {
        dispose();
    }

}
