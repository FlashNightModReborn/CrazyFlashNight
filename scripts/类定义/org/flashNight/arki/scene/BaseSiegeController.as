import org.flashNight.arki.scene.*;
import org.flashNight.arki.dialogue.NativeDialogueService;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.path.PathManager;

/** Scene events own combat. A short-lived observer only waits for external art/units. */
class org.flashNight.arki.scene.BaseSiegeController {
    private static var installed:Boolean=false;
    private static var room:Object;
    private static var loadWatch:MovieClip;
    private static var sequence:Number=0;

    public static function start(kind:String):Void {
        if(!installed){installed=true;NativeInteractionContext.onSceneTeardown(teardown);}
        teardown();
        if(kind!="rhino" && kind!="tigr" && kind!="roof")return;
        var world:MovieClip=_root.gameworld;
        room={world:world,owner:StageReturnFlow.worldIdentity(world),serial:++sequence,
            kind:kind,manager:StageManager.getInstance(),phase:"battle",explained:false,
            deployed:false,assetsReady:false,guardReady:false,counterStarted:false,
            combatCleared:false,done:false,renderPhase:1,loadTicks:0};
        if(kind!="roof")room.target=kind=="rhino"?{x:1560,y:420}:{x:555,y:600};
        prepareArt(room);
        world.dispatcher.subscribe("HeroMoved",refreshArt,BaseSiegeController);
        ensureLoadWatch();
    }
    private static function current(r:Object):Boolean {
        return r!=null && r===room && r.owner!=null
            && r.owner===StageReturnFlow.worldIdentity(_root.gameworld)
            && r.manager.isActive && !r.manager.isFailed && !r.manager.isFinished;
    }
    private static function paused():Boolean {
        return _root.暂停===true || _root.场景转换中===true || NativeDialogueService.hasActiveSession();
    }
    private static function ensureLoadWatch():Void {
        if(loadWatch!=null)return;
        loadWatch=_root.createEmptyMovieClip("__baseSiegeLoadWatch",_root.getNextHighestDepth());
        loadWatch.onEnterFrame=function():Void {org.flashNight.arki.scene.BaseSiegeController.pollLoaded();};
    }
    private static function stopLoadWatch():Void {
        if(loadWatch!=null){delete loadWatch.onEnterFrame;loadWatch.removeMovieClip();loadWatch=null;}
    }
    private static function setCoilStatic(mc:MovieClip, deployed:Boolean):Void {
        var shield:MovieClip=mc.shieldMC;
        var interference:MovieClip=mc.interferenceMC;
        shield.gotoAndStop(73);
        interference.gotoAndStop(49);
        shield._visible=!deployed;
        interference._visible=deployed;
        mc.effectStandby._visible=!deployed;
        mc.effectPowered._visible=deployed;
        mc.effectStandby.gotoAndStop(1);
        if(deployed)mc.effectPowered.gotoAndPlay(1);else mc.effectPowered.gotoAndStop(1);
        shield.cacheAsBitmap=true;interference.cacheAsBitmap=true;
        mc.cacheAsBitmap=false;
    }
    private static function startCoilTransition(r:Object):Void {
        var mc:MovieClip=r.world.stageInstance0;
        mc.cacheAsBitmap=false;
        mc.effectStandby._visible=false;
        mc.effectPowered._visible=false;
        mc.effectPowered.gotoAndStop(1);
        mc.shieldMC.cacheAsBitmap=false;mc.interferenceMC.cacheAsBitmap=false;
        mc.shieldMC._visible=true;
        mc.interferenceMC._visible=false;
        mc.shieldMC.gotoAndStop(73);
        mc.interferenceMC.gotoAndStop(1);
        r.animPhase="shieldReturn";r.animTick=0;
    }
    private static function stepCoilTransition(r:Object):Void {
        if(r.animPhase==null)return;
        var mc:MovieClip=r.world.stageInstance0;
        r.animTick++;
        if(r.animPhase=="shieldReturn"){
            var back:Number=73-Math.round(72*r.animTick/36);
            if(back<1)back=1;
            mc.shieldMC.gotoAndStop(back);
            if(r.animTick>=36){
                mc.shieldMC._visible=false;
                mc.interferenceMC._visible=true;
                mc.interferenceMC.gotoAndStop(1);
                r.animPhase="interferenceForward";r.animTick=0;
            }
        }else if(r.animPhase=="interferenceForward"){
            var forward:Number=1+Math.round(48*r.animTick/25);
            if(forward>49)forward=49;
            mc.interferenceMC.gotoAndStop(forward);
            if(r.animTick>=25){
                mc.effectStandby._visible=false;
                mc.effectPowered._visible=true;
                r.animPhase=null;r.animTick=0;setCoilStatic(mc,true);
            }
        }
    }
    private static function prepareArt(r:Object):Void {
        r.art=[];
        for(var i:Number=0;i<2;i++){
            var mc:MovieClip=r.world["stageInstance"+i];
            var ticket:Object={index:i,ready:false,attempts:0,
                url:"flashswf/backgrounds/base_siege_"+(r.kind=="roof"?(i==0?"hind":"equipment"):(i==0?"coil":"relay"))+".swf",
                x:mc._x,y:mc._y,sx:mc._xscale,sy:mc._yscale};
            r.art.push(ticket);
            if(mc.__siegeReady===true && mc._width>0 && mc._height>0)ticket.ready=true;
            else loadArt(r,ticket);
        }
    }
    private static function retireArtLoader(ticket:Object):Void {
        if(ticket.loader!=null)ticket.loader.removeListener(ticket.listener);
        ticket.loader=null;ticket.listener=null;
    }
    private static function loadArt(r:Object,ticket:Object):Void {
        retireArtLoader(ticket);ticket.ready=false;ticket.attempts++;
        var name:String="stageInstance"+ticket.index;
        var mc:MovieClip=r.world[name];
        if(mc._name==undefined)mc=r.world.createEmptyMovieClip(name,r.world.getNextHighestDepth());
        DepthManager.instance.removeMovieClip(mc);
        // A loadMovie placeholder is not an initialization receipt. Own the replacement
        // with MovieClipLoader and apply position/scale only after its onLoadInit.
        mc.unloadMovie();
        ticket.loader=new MovieClipLoader();
        ticket.listener={room:r,ticket:ticket,attempt:ticket.attempts,
            onLoadInit:function(loaded:MovieClip):Void {
                org.flashNight.arki.scene.BaseSiegeController.artLoaded(this.room,this.ticket,loaded,this.attempt);
            },
            onLoadError:function(loaded:MovieClip,code:String):Void {
                org.flashNight.arki.scene.BaseSiegeController.artError(this.room,this.ticket,code,this.attempt);
            }};
        ticket.loader.addListener(ticket.listener);
        var resolved:String=PathManager.resolvePath(ticket.url);
        if(!ticket.loader.loadClip(resolved==null?ticket.url:resolved,mc))artError(r,ticket,"request_rejected",ticket.attempts);
    }
    public static function artLoaded(r:Object,ticket:Object,mc:MovieClip,attempt:Number):Void {
        if(!current(r) || r.done || r.art[ticket.index]!==ticket || attempt!=ticket.attempts || mc!==r.world["stageInstance"+ticket.index])return;
        mc._x=ticket.x;mc._y=ticket.y;mc._xscale=ticket.sx;mc._yscale=ticket.sy;
        mc._visible=true;
        if(!(mc._width>0 && mc._height>0)){artError(r,ticket,"empty_art",attempt);return;}
        if(r.kind=="roof")mc.gotoAndStop(ticket.index==1?r.renderPhase:1);
        else if(ticket.index==0){r.animPhase=null;r.animTick=0;setCoilStatic(mc,r.deployed);}
        else mc.gotoAndStop(1);
        mc.cacheAsBitmap=r.kind=="roof" || ticket.index!=0;
        ticket.ready=true;retireArtLoader(ticket);
        r.loadTicks=0;ensureLoadWatch();
    }
    public static function artError(r:Object,ticket:Object,code:String,attempt:Number):Void {
        if(!current(r) || r.done || r.art[ticket.index]!==ticket || attempt!=ticket.attempts)return;
        retireArtLoader(ticket);
        _root.服务器.发布服务器消息("[BaseSiege] art_load_failed room="+r.kind+" index="+ticket.index+" attempt="+ticket.attempts+" code="+code);
        if(ticket.attempts<2)loadArt(r,ticket);
    }
    /** Event-driven recovery if a scene prop was removed after initialization. */
    public static function refreshArt():Void {
        var r:Object=room;
        if(!current(r) || r.done || !r.assetsReady)return;
        for(var i:Number=0;i<r.art.length;i++){
            var mc:MovieClip=r.world["stageInstance"+i];
            if(mc._name!=undefined && mc._width>0 && mc._height>0)continue;
            r.assetsReady=false;r.anchor.enableInteractionKey=false;
            r.art[i].attempts=0;loadArt(r,r.art[i]);r.loadTicks=0;ensureLoadWatch();
        }
    }
    public static function pollLoaded():Void {
        var r:Object=room;
        if(!current(r)){teardown();return;}
        r.loadTicks++;
        stepCoilTransition(r);
        if(!r.assetsReady && r.art[0].ready===true && r.art[1].ready===true){
            var a:MovieClip=r.world.stageInstance0;var b:MovieClip=r.world.stageInstance1;
            a.cacheAsBitmap=r.kind=="roof";b.cacheAsBitmap=true;
            if(r.kind=="roof"){
                DepthManager.instance.updateDepth(a,274);DepthManager.instance.updateDepth(b,410);
                b.gotoAndStop(r.renderPhase);
            }else{
                DepthManager.instance.updateDepth(a,r.kind=="rhino"?385:340);
                DepthManager.instance.updateDepth(b,r.kind=="rhino"?394.6:621.6);
                if(r.animPhase==null)setCoilStatic(a,r.deployed);
            }
            r.assetsReady=true;
            if(r.anchor!=null){r.anchor.enableInteractionKey=r.explained && !r.deployed;refreshInteraction(r);}
        }
        if(r.deployed && !r.guardReady){
            var guard:MovieClip=r.world.siege_relay_guard;
            if(guard.hp>0 && guard.area._name!=undefined && typeof guard.状态改变=="function"){
                // Reuse the live protection-unit hitbox/HP/AI target, keep this map's relay art.
                guard.man._visible=false;guard.threat=30;
                guard.area._width=50;guard.area._height=76;guard.area._x=-25;guard.area._y=-76;
                guard.aabbCollider.updateFromUnitArea(guard);
                r.guardReady=true;r.counterStarted=true;
                r.world.dispatcher.publish("SiegeCounterattack");
            }
        }
        if(r.assetsReady && (!r.deployed || r.guardReady) && r.animPhase==null){stopLoadWatch();return;}
        if(r.loadTicks==300 && !r.assetsReady){
            for(var i:Number=0;i<r.art.length;i++)if(!r.art[i].ready && r.art[i].attempts<2)loadArt(r,r.art[i]);
        }
        if(r.loadTicks>600){
            _root.服务器.发布服务器消息("[BaseSiege] init_timeout room="+r.kind+" assets="+r.assetsReady+" guard="+r.guardReady+" guardHp="+r.world.siege_relay_guard.hp);
            stopLoadWatch();r.world.dispatcher.publish("SiegeAssetFailed");
        }
    }
    private static function makeInteraction(r:Object):Void {
        if(r.anchor!=null)return;
        var mc:MovieClip=r.world.createEmptyMovieClip("__siegeOperation",r.world.getNextHighestDepth());
        mc._x=r.target.x;mc._y=r.target.y;mc.enableInteractionKey=r.assetsReady;
        var owner:Object=r.owner;var serial:Number=r.serial;
        mc.onInteract=function():Void {org.flashNight.arki.scene.BaseSiegeController.interact(owner,serial);};
        r.world.addInteraction(mc,90,70,r.target.x,r.target.y);r.anchor=mc;
        // Dialogue may finish while the hero is already standing beside the device.
        refreshInteraction(r);
    }
    private static function refreshInteraction(r:Object):Void {
        var actor:MovieClip=r.world[_root.控制目标];
        if(actor._name!=undefined)SceneInteractionManager.instance.update(actor._x,
            isNaN(actor.Z轴坐标)?actor._y:actor.Z轴坐标);
    }
    public static function interact(owner:Object,serial:Number):Void {
        var r:Object=room;
        if(!current(r) || r.owner!==owner || r.serial!==serial)return;
        var actor:MovieClip=r.world[_root.控制目标];
        var y:Number=isNaN(actor.Z轴坐标)?actor._y:actor.Z轴坐标;
        var near:Boolean=Math.abs(actor._x-r.target.x)<90 && Math.abs(y-r.target.y)<70;
        if(!BaseSiegeRules.canDeploy(r.explained,r.deployed,near,actor.hp>0,paused(),r.assetsReady))return;
        r.deployed=true;r.phase="defending";r.anchor.enableInteractionKey=false;
        startCoilTransition(r);
        _root.播放音效("触电.wav");
        r.world.dispatcher.publish("SiegeRelayActivated");
        r.loadTicks=0;ensureLoadWatch();
    }
    public static function signal(name:String):Void {
        var r:Object=room;
        if(!current(r) || r.done)return;
        if(name=="enable" && r.kind!="roof" && !r.explained){
            r.explained=true;r.phase="ready";makeInteraction(r);
        }else if(name=="outage" && r.kind=="roof" && !r.combatCleared){
            r.renderPhase=2;r.phase="offline";
            if(r.assetsReady)r.world.stageInstance1.gotoAndStop(2);
        }else if(name=="restore" && r.kind=="roof" && r.phase=="ending"){
            r.renderPhase=3;r.phase="restored";
            if(r.assetsReady)r.world.stageInstance1.gotoAndStop(3);
        }else if(name=="finished" && r.kind=="roof" && r.phase=="restored"){
            r.done=true;r.phase="complete";stopLoadWatch();r.manager.clearStage();
        }
    }
    /** Only the existing modifier's explicit complete-map action calls this. */
    public static function prepareDebugClear(manager:Object,world:Object):Void {
        var r:Object=room;
        if(!current(r) || r.manager!==manager || r.world!==world)return;
        r.done=true;r.phase="complete";
        for(var i:Number=0;i<r.art.length;i++)retireArtLoader(r.art[i]);
        r.world.siege_relay_guard.threat=0;
        r.anchor.enableInteractionKey=false;r.anchor.removeMovieClip();stopLoadWatch();
    }
    public static function interceptClear(manager:Object,world:Object):Boolean {
        var r:Object=room;
        if(!current(r) || world!==r.world || r.done)return false;
        if(r.kind!="roof"){
            if(!BaseSiegeRules.canClearRelay(r.deployed,r.guardReady,
                    WaveSpawner.instance.isFinished===true,r.world.siege_relay_guard.hp>0))return true;
            r.done=true;r.phase="complete";r.world.siege_relay_guard.threat=0;
            r.anchor.enableInteractionKey=false;r.anchor.removeMovieClip();stopLoadWatch();
            return false;
        }
        if(!r.combatCleared){
            r.combatCleared=true;r.phase="ending";r.manager=manager;
            r.world.dispatcher.publish("SiegeRoofSecured");
        }
        return true;
    }
    public static function snapshot():Object {
        if(!current(room))return null;
        return {kind:room.kind,phase:room.phase,deployed:room.deployed,
            explained:room.explained,assetsReady:room.assetsReady,guardReady:room.guardReady,
            counterStarted:room.counterStarted,done:room.done,combatCleared:room.combatCleared,
            observerActive:loadWatch!=null,loadTicks:room.loadTicks,
            coilAnimation:room.animPhase==null?"none":room.animPhase};
    }
    private static function teardown():Void {
        stopLoadWatch();
        if(room!=null){
            for(var i:Number=0;i<room.art.length;i++)retireArtLoader(room.art[i]);
            room.world.dispatcher.unsubscribe("HeroMoved",refreshArt,BaseSiegeController);
        }
        if(room!=null && room.owner===StageReturnFlow.worldIdentity(_root.gameworld)){
            room.anchor.enableInteractionKey=false;room.anchor.removeMovieClip();
        }
        room=null;
    }
}
