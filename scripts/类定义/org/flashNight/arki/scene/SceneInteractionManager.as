import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.gesh.depth.DepthManager;
import flash.display.BitmapData;
import flash.geom.Point;

/**
SceneManager.as
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.SceneInteractionManager {

    public static var instance:SceneInteractionManager; // 单例引用

    public var interactionInfoList:Array;
    public var currentMC;

    /**
     * 单例获取：返回全局唯一实例
     */
    public static function getInstance():SceneInteractionManager {
        return instance || (instance = new SceneInteractionManager());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function SceneInteractionManager() {
    }

    public function init():Void {
        var self = this;
        this.interactionInfoList = [];
        this.currentMC = null;
        var gameworld = _root.gameworld;
        gameworld.dispatcher.subscribe("HeroMoved", this.update, this);
        gameworld.dispatcher.subscribeGlobal("interactionKeyDown", this.interact, this);
        gameworld.addInteraction = function(mc:MovieClip, distX:Number, distZ:Number, x:Number, y:Number){
            self.addInteraction(mc, distX, distZ, x, y);
        }
    }


    public function update(heroX:Number, heroZ:Number):Void{
        var minDiffManhattan = 9999;
        var nextMC = null;

        // 对于距离在范围内的影片剪辑，取曼哈顿距离最低者
        for(var i=0; i < interactionInfoList.length; i++){
            var info = interactionInfoList[i];
            if(info.mc.enableInteractionKey !== true){
                continue;
            }
            var diffX = Math.abs(info.x - heroX);
            var diffZ = Math.abs(info.y - heroZ);
            
            if(diffX < info.distX && diffZ < info.distZ){
                var diffManhattan = diffX + diffZ;
                if(diffManhattan < minDiffManhattan){
                    nextMC = info.mc;
                    minDiffManhattan = diffManhattan;
                }
            }
        }

        if(nextMC !== this.currentMC){
            this.currentMC.onUnhighlight();
        }
        if(nextMC != null){
            nextMC.onHighlight();
        }
        this.currentMC = nextMC;

    }

    public function interact():Void{
        if(this.currentMC != null){
            this.currentMC.onUnhighlight();
            this.currentMC.onInteract();
        }
    }

    public function addInteraction(mc:MovieClip, distX:Number, distZ:Number, x:Number, y:Number):Void{
        var info = {
            mc: mc,
            distX: distX > 0 ? distX : 50,
            distZ: distZ > 0 ? distZ : 50,
            x: x > 0 ? x : mc._x,
            y: y > 0 ? y : mc._y
        }
        if(mc.enableInteractionKey == null){
            mc.enableInteractionKey = true;
        }

        this.interactionInfoList.push(info);
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
