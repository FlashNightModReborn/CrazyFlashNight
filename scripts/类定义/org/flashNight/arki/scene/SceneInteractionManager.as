import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BoxInteractionArbiter;
import org.flashNight.arki.unit.Action.PickUp.PickUpManager;

/**
SceneManager.as
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.SceneInteractionManager {

    public static var instance:SceneInteractionManager; // 单例引用

    public var interactionInfoList:Array;
    public var currentMC;
    private var currentIdentity:Object;
    private var world:MovieClip;
    private var worldIdentity:Object;
    private var armedPress:Number;
    private var armedActor:Object;
    private var lastGestureFrame:Number;
    private var lastGestureSeq:Number;
    private var lastRepeatFrame:Number;

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
        dispose();
        var self = this;
        this.interactionInfoList = [];
        this.currentMC = null;
        var gameworld:MovieClip = _root.gameworld;
        world = gameworld;
        worldIdentity = StageReturnFlow.worldIdentity(gameworld);
        gameworld.dispatcher.subscribe("HeroMoved", this.update, this);
        if (_root.GameInput.passiveActive !== true)
            gameworld.dispatcher.subscribeGlobal("interactionKeyDown", this.interact, this);
        var identity:Object = worldIdentity;
        gameworld.addInteraction = function(mc:MovieClip, distX:Number, distZ:Number, x:Number, y:Number):Void {
            if (self.worldIdentity === identity) self.addInteraction(mc, distX, distZ, x, y);
        };
    }


    public function update(heroX:Number, heroZ:Number):Void{
        var minDiffManhattan = 9999;
        var nextMC = null;
        var nextIdentity:Object = null;

        // 对于距离在范围内的影片剪辑，取曼哈顿距离最低者
        for(var i=0; i < interactionInfoList.length; i++){
            var info = interactionInfoList[i];
            if(info.mc.enableInteractionKey !== true || info.mc.__cf7SceneInteractionIdentity !== info.identity){
                continue;
            }
            var diffX = Math.abs(info.x - heroX);
            var diffZ = Math.abs(info.y - heroZ);
            
            if(diffX < info.distX && diffZ < info.distZ){
                var diffManhattan = diffX + diffZ;
                if(diffManhattan < minDiffManhattan){
                    nextMC = info.mc;
                    nextIdentity = info.identity;
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
        this.currentIdentity = nextIdentity;
    }

    public function interact():Void{
        if(this.currentMC != null){
            this.currentMC.onUnhighlight();
            this.currentMC.onInteract();
            this.currentMC = null;
            this.currentIdentity = null;
        }
    }

    public function keyboardInteraction(repeat:Boolean):Void {
        var input:Object = _root.GameInput;
        if (!input.isInputAdmitted() || _root.暂停 || this.worldIdentity == null
                || _root.gameworld.__stageReturnWorldIdentity !== this.worldIdentity
                || this.world.__combatAdmitted === false) return;
        var actor:MovieClip = this.world[_root.控制目标];
        if (!input.isCurrentActor(actor) || !(actor.hp > 0)) return;
        var vk:Number = _root.互动键;
        var press:Number = input.getActorPress(actor, vk);
        var frame:Number = input.snapshot.systemFrame;
        if (repeat) {
            if (press == 0 || press !== this.armedPress || this.armedActor !== actor.__cf7InputIdentity
                    || this.lastRepeatFrame === frame) return;
            this.lastRepeatFrame = frame;
        } else {
            var edge:Object = input.dispatchEdge;
            if (edge == null || !edge.down || edge.vk !== vk
                    || (this.lastGestureFrame === frame && this.lastGestureSeq === edge.seq)) return;
            this.lastGestureFrame = this.lastRepeatFrame = frame;
            this.lastGestureSeq = edge.seq;
            this.armedPress = press;
            this.armedActor = actor.__cf7InputIdentity;
        }

        var pickups:PickUpManager = _root.pickupItemManager;
        if (pickups != null) pickups.setKeyboardHighlight(this.world, true);
        if (this.currentMC != null && this.currentMC.enableInteractionKey === true
                && this.currentIdentity != null && this.currentMC.__cf7SceneInteractionIdentity === this.currentIdentity) {
            this.interact();
        } else if (!BoxInteractionArbiter.dispatchKeyboard(this.world, actor) && pickups != null) {
            pickups.pickUpKeyboard(this.world, actor);
        }
    }

    public function cancelPassiveInput():Void {
        this.armedPress = 0;
        this.armedActor = null;
        var pickups:PickUpManager = _root.pickupItemManager;
        if (pickups != null && this.worldIdentity != null && this.world.__stageReturnWorldIdentity === this.worldIdentity)
            pickups.setKeyboardHighlight(this.world, false);
    }

    public function addInteraction(mc:MovieClip, distX:Number, distZ:Number, x:Number, y:Number):Void{
        if (mc.__cf7SceneInteractionIdentity == null) mc.__cf7SceneInteractionIdentity = {};
        var info = {
            mc: mc,
            identity: mc.__cf7SceneInteractionIdentity,
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
        cancelPassiveInput();
        if (worldIdentity != null && world.__stageReturnWorldIdentity === worldIdentity && world.dispatcher != null) {
            world.dispatcher.unsubscribe("HeroMoved", this.update, this);
            if (_root.GameInput.passiveActive !== true)
                world.dispatcher.unsubscribeGlobal("interactionKeyDown", this.interact, this);
        }
        world = null;
        worldIdentity = null;
        currentIdentity = null;
        currentMC = null;
        interactionInfoList = [];
    }

    /**
     * 重置单例状态（用于游戏重启后重新初始化）
     */
    public function reset():Void {
        dispose();
    }

}
