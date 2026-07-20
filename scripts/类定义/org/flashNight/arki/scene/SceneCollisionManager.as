import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

import org.flashNight.arki.spatial.transform.SceneCoordinateManager;
import org.flashNight.sara.util.Vector;

import org.flashNight.arki.collision.CollisionLayerRenderer;

/**
SceneManager.as
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
        this.collisionLayer = _root.collisionLayer;
        this.collisions = null;
        this.movieClipCollisions = [];
        this.redrawDirtyMark = false;
        this.drawCount = 0;
    }

    public function addCollisions(_collisions):Void{
        this.collisions = ObjectUtil.toArray(ObjectUtil.clone(_collisions));
    }

    public function addMovieClipCollision(mc:MovieClip, rect):Void{
        this.movieClipCollisions.push({
            mc: mc,
            rect: rect
        })
    }

    // update 函数，被 SceneManager 调用
    public function update():Void{
        this.drawCount++;
        // 每4帧检查一次：如果影片剪辑已卸载，移除对应的碰撞箱信息并标脏
        if(this.drawCount % 4 == 0){
            for(var i = this.movieClipCollisions.length - 1; i > -1; i--){
                var mcColli = this.movieClipCollisions[i];
                if(!mcColli.mc._name){
                    this.movieClipCollisions.splice(i, 1);
                    this.redrawDirtyMark = true;
                }
            }
        }
        // 根据脏标记触发重绘，间隔最低20帧
        if(this.redrawDirtyMark && this.drawCount > 20){
            redraw();
        }
    }

    // 重绘所有碰撞箱
    public function redraw():Void{
        CollisionLayerRenderer.clearAll();

        // 再次计算边界坐标并绘制外框
        var point:Vector = SceneCoordinateManager.calculateOffset();
		var xmin:Number = _root.Xmin - point.x;
		var xmax:Number = _root.Xmax - point.x;
		var ymin:Number = _root.Ymin - point.y;
		var ymax:Number = _root.Ymax - point.y;
		// 调用统一渲染器绘制边界碰撞箱
		CollisionLayerRenderer.drawBoundary(
			collisionLayer,
			xmin, xmax, ymin, ymax,
			300,  // margin
			_root.调试模式
		);
        
        // 根据存储的数组再次绘制碰撞箱
        if (this.collisions != null){
            CollisionLayerRenderer.drawPolygons(collisionLayer, this.collisions);
        }

        // 再次绘制影片剪辑碰撞箱
        for(var i = 0; i < this.movieClipCollisions.length; i++){
            var mcColli = this.movieClipCollisions[i];
            CollisionLayerRenderer.drawRect(collisionLayer, mcColli.rect);
        }

        this.redrawDirtyMark = false;
        this.drawCount = 0;
    }
    


    /**
     * 完整清理方法（幂等）
     * 用于游戏重启时的彻底清理
     */
    public function dispose():Void {
    }

    /**
     * 重置单例状态（用于游戏重启后重新初始化）
     */
    public function reset():Void {
        dispose();
    }

}
