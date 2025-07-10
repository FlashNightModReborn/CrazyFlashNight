import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/**
SceneManager.as
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.SceneManager {
    public static var instance:SceneManager; // 单例引用

    public var gameworld:MovieClip; // 当前gameworld
    
    /**
     * 单例获取：返回全局唯一实例
     */
    public static function getInstance():SceneManager {
        return instance || (instance = new SceneManager());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function SceneManager() {
        gameworld = null;
    }

    /*
     * 对新附加的gameworld进行初始化，并附加必要组件。
     */
    public function initGameWorld(_gw:MovieClip):Void{
        gameworld = _gw;
        // gameworld地图碰撞箱层已经弃用，为防止错误附加一个空影片剪辑作为地图层
        if(gameworld.地图 == null) gameworld.createEmptyMovieClip("地图", -2);
        // 附加子弹层，层级在所有人物之下
        if(gameworld.子弹区域 == null) gameworld.createEmptyMovieClip("子弹区域", -1);
        // 附加效果层，层级在所有人物之上
        if(gameworld.效果 == null) gameworld.createEmptyMovieClip("效果", 32767);

        // 创建事件分发器
        gameworld.dispatcher = new LifecycleEventDispatcher(gameworld);

        // 将上述属性设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["效果", "子弹区域", "地图", "dispatcher"], 1, false);

        // 发布场景切换事件
        _root.帧计时器.eventBus.publish("SceneChanged");
    }

    /*
     * 移除gameworld及其组件
     */
    public function removeGameWorld():Void{
        gameworld.dispatcher.destroy();
        gameworld.dispatcher = null;

        gameworld.deadbody.layers[0].dispose();
        gameworld.deadbody.layers[1].dispose();
        gameworld.deadbody.layers[2].dispose();
        gameworld.swapDepths(_root.getNextHighestDepth());
        gameworld.removeMovieClip();
        gameworld = null;
    }


    public function addBodyLayers(w:Number ,h:Number):Void{
        var deadbody = gameworld.deadbody;
        if(deadbody.layers != null) return;
        //位图层的大小范围在(1024,512)到(2880,1024)之间
        if(w < 1024) w = 1024;
        else if(w >= 2880) w = 2880;
        if(h < 512) h = 512;
        else if(h >= 1024) h = 1024;
        deadbody.layers = new Array(3);
        deadbody.layers[0] = new flash.display.BitmapData(w, h, true, 13421772);
        deadbody.layers[1] = null; // 从未被使用的deadbody1不添加
        deadbody.layers[2] = new flash.display.BitmapData(w, h, true, 13421772);
        deadbody.attachBitmap(deadbody.layers[0], 0);
        deadbody.attachBitmap(deadbody.layers[2], 2);

        // 将 'deadbody' 设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["deadbody"], 1, false);
    }


    public function addInstance(info:Object, name:String):MovieClip{
        var inst;
        if (info.url != null) {
            // 检测url参数载入外部swf
            inst = gameworld.createEmptyMovieClip(name, gameworld.getNextHighestDepth());
            inst.loadMovie(info.url);
        } else if(info.Identifier != null) {
            // 根据identifier从库中加载元件
            inst = gameworld.attachMovie(info.Identifier, name, gameworld.getNextHighestDepth());
        }else{
            // 否则，创建空元件
            inst = gameworld.createEmptyMovieClip(name, gameworld.getNextHighestDepth());
        }
        inst._x = info.x;
        inst._y = info.y;
        inst.swapDepths(isNaN(info.Depth) ? info.y : info.Depth);
        if (info.Parameters) ObjectUtil.cloneParameters(inst, info.Parameters);
        return inst;
    }

}