import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.gesh.depth.DepthManager;

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
        // 附加效果层，层级在 DM 管理区和创建暂存区之上
        if(gameworld.效果 == null) gameworld.createEmptyMovieClip("效果", 1048000);

        // 创建事件分发器
        gameworld.dispatcher = new LifecycleEventDispatcher(gameworld);

        // ── 重写 getNextHighestDepth ──
        // 计数器 900000-999999（创建暂存区），避开 Twip 深度范围(0-870655) 和 UnitBullet 域(1000000+)
        // 所有新建 gw 子级在此创建后，同帧被 DM.updateDepth 移到 Twip 深度
        var _gwDC:Number = 900000;
        gameworld.getNextHighestDepth = function():Number {
            var d:Number = _gwDC++;
            if (_gwDC >= 1000000) _gwDC = 900000;
            return d;
        };

        // ── 创建 DepthManager ──
        if (DepthManager.instance) DepthManager.instance.dispose();
        DepthManager.instance = new DepthManager(gameworld, 0, 1048575, 256);
        // 用当前可用边界标定（非战斗场景帧脚本已设 Ymin/Ymax；战斗场景在 StageManager 中精确覆盖）
        var ym:Number = _root.Ymin;
        var yM:Number = _root.Ymax;
        DepthManager.instance.calibrate(
            isNaN(ym) ? 0 : ym,
            isNaN(yM) ? 1200 : yM
        );

        // 将上述属性设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["效果", "子弹区域", "地图", "dispatcher", "getNextHighestDepth"], 1, false);

        // 发布场景切换事件
        _root.帧计时器.eventBus.publish("SceneChanged");
    }

    /*
     * 移除gameworld及其组件
     */
    public function removeGameWorld():Void{
        // 幂等检查
        if (gameworld == null) {
            return;
        }

        // 销毁事件分发器
        if (gameworld.dispatcher != null) {
            gameworld.dispatcher.destroy();
            gameworld.dispatcher = null;
        }

        // 释放BitmapData资源
        if (gameworld.deadbody != null && gameworld.deadbody.layers != null) {
            if (gameworld.deadbody.layers[0] != null) {
                gameworld.deadbody.layers[0].dispose();
            }
            if (gameworld.deadbody.layers[1] != null) {
                gameworld.deadbody.layers[1].dispose();
            }
            if (gameworld.deadbody.layers[2] != null) {
                gameworld.deadbody.layers[2].dispose();
            }
            gameworld.deadbody.layers = null;
        }

        // 显式 dispose DepthManager：清空内部数据，解绑 onUnload 回调。
        // 注意：instance = null 必须在 removeMovieClip 之后。
        // 原因：removeMovieClip 会级联触发子级 onUnload → StaticDeinitializer.deInitializeUnit
        // → DepthManager.instance.removeMovieClip(target)。若 instance 已 null 则空引用。
        // dispose 后内部数据已清空，子级的 removeMovieClip 调用会安全 return false。
        if (DepthManager.instance) {
            DepthManager.instance.dispose();
        }

        gameworld.swapDepths(_root.getNextHighestDepth());
        gameworld.removeMovieClip();
        DepthManager.instance = null;
        gameworld = null;
    }

    /**
     * 完整清理方法（幂等）
     * 用于游戏重启时的彻底清理
     */
    public function dispose():Void {
        removeGameWorld();
    }

    /**
     * 重置单例状态（用于游戏重启后重新初始化）
     */
    public function reset():Void {
        dispose();
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
        // Y 排序实例走 DepthManager；显式 Depth 配置的固定装饰物保持原样
        if (isNaN(info.Depth)) {
            DepthManager.instance.updateDepth(inst, info.y);
        } else {
            inst.swapDepths(info.Depth);
        }
        if (info.Parameters) ObjectUtil.cloneParameters(inst, info.Parameters);
        return inst;
    }

}