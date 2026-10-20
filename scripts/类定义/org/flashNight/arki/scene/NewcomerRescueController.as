import org.flashNight.arki.scene.*;
import org.flashNight.arki.dialogue.NativeDialogueService;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.gesh.object.ObjectUtil;
import flash.display.BitmapData;
import flash.geom.Matrix;

/** 70002 owns only its room interactions and jeep. Native waves own combat. */
class org.flashNight.arki.scene.NewcomerRescueController {
    private static var room:Object;
    private static var watch:MovieClip;
    private static var serial:Number=0;
    private static var installed:Boolean=false;

    public static function start(index:Number):Void {
        if(!installed){installed=true;NativeInteractionContext.onSceneTeardown(teardown);}
        teardown();
        if(isNaN(index) || index<0 || index>7)return;
        var world:MovieClip=_root.gameworld;
        room={world:world,owner:StageReturnFlow.worldIdentity(world),serial:++serial,
            manager:StageManager.getInstance(),index:index,phase:"battle",done:false,
            artReady:false,loadTicks:0,attempt:0,fuse:0,blast:false,reported:false,suppliesSpawned:false};
        if(index==3){room.phase="investigate";spawnJeepSupplies(room);loadJeep(room);}
    }
    private static function spawnJeepSupplies(r:Object):Void {
        if(r==null || r.suppliesSpawned)return;
        r.suppliesSpawned=true;
        var gates:Object={任务链名称:"铁枪会",最小任务链进度:1,最大任务链进度:1,
            要求进行中任务ID:70002,一次性领取ID:"iron_spear_70002_veteran_type56r"};
        _root.创建可拾取物("Type56R",1,1454,510,false,gates);
        _root.创建可拾取物("突击步枪通用弹药",1,1388,530,false);
        SceneManager.instance.addInstance({Identifier:"资源箱",x:1340,y:560,
            Parameters:{掉落物:[{名字:"普通手雷",概率:100,最小数量:3,最大数量:3}]}},"rescue_grenades");
    }
    private static function current(r:Object):Boolean {
        return r!=null && r===room && r.owner!=null
            && r.owner===StageReturnFlow.worldIdentity(_root.gameworld)
            && r.manager.isActive && !r.manager.isFailed && !r.manager.isFinished;
    }
    private static function paused():Boolean {
        return _root.暂停===true || _root.场景转换中===true || NativeDialogueService.hasActiveSession();
    }
    private static function ensureWatch():Void {
        if(watch!=null)return;
        watch=_root.createEmptyMovieClip("__newcomerRescueWatch",_root.getNextHighestDepth());
        watch.onEnterFrame=function():Void {org.flashNight.arki.scene.NewcomerRescueController.tick();};
    }
    private static function stopWatch():Void {
        if(watch!=null){delete watch.onEnterFrame;watch.removeMovieClip();watch=null;}
    }
    private static function retireLoader(r:Object):Void {
        if(r.loader!=null && r.listener!=null)r.loader.removeListener(r.listener);
        r.loader=null;r.listener=null;
    }
    private static function loadJeep(r:Object):Void {
        if(!current(r))return;
        retireLoader(r);r.attempt++;r.artReady=false;r.loadTicks=0;
        var art:MovieClip=r.world.createEmptyMovieClip("__rescueJeepArt",r.world.getNextHighestDepth());
        r.art=art;r.loadingPart="body";r.loader=new MovieClipLoader();
        r.listener={owner:r,attempt:r.attempt,part:r.loadingPart,
            onLoadInit:function(mc:MovieClip):Void {
                org.flashNight.arki.scene.NewcomerRescueController.artLoaded(this.owner,this.attempt,this.part,mc);
            },
            onLoadError:function(mc:MovieClip,code:String):Void {
                org.flashNight.arki.scene.NewcomerRescueController.artError(this.owner,this.attempt,code,this.part);
            }};
        r.loader.addListener(r.listener);
        var url:String=PathManager.resolvePath("flashswf/arts/70002_jeep.swf");
        if(!r.loader.loadClip(url==null?"flashswf/arts/70002_jeep.swf":url,art))artError(r,r.attempt,"request_rejected");
        ensureWatch();
    }
    public static function artLoaded(r:Object,attempt:Number,part:String,mc:MovieClip):Void {
        if(!current(r) || r.attempt!=attempt || part!=r.loadingPart || mc!==(part=="body"?r.art:r.station))return;
        retireLoader(r);
        if(!(mc._width>0 && mc._height>0)){artError(r,attempt,"empty_art");return;}
        mc._x=0;mc._y=0;mc.gotoAndStop("investigate");mc.cacheAsBitmap=true;
        if(part=="body"){
            DepthManager.instance.updateDepth(mc,392);
            r.loadingPart="station";r.loadTicks=0;
            var station:MovieClip=r.world.createEmptyMovieClip("__rescueStationArt",r.world.getNextHighestDepth());
            r.station=station;r.loader=new MovieClipLoader();
            r.listener={owner:r,attempt:r.attempt,part:"station",
                onLoadInit:function(loaded:MovieClip):Void {
                    org.flashNight.arki.scene.NewcomerRescueController.artLoaded(this.owner,this.attempt,this.part,loaded);
                },
                onLoadError:function(loaded:MovieClip,code:String):Void {
                    org.flashNight.arki.scene.NewcomerRescueController.artError(this.owner,this.attempt,code,this.part);
                }};
            r.loader.addListener(r.listener);
            var path:String=PathManager.resolvePath("flashswf/arts/70002_station.swf");
            if(!r.loader.loadClip(path==null?"flashswf/arts/70002_station.swf":path,station))artError(r,r.attempt,"station_rejected");
            return;
        }
        var st:MovieClip=mc.stationState;
        r.stationGround=extractStationProp(r,st.groundProps,"__rescueStationGround",200);
        r.stationInitiator=extractStationProp(r,st.initiatorProp,"__rescueStationInitiator",390);
        r.stationCorpse=extractStationProp(r,st.corpseProp,"__rescueStationCorpse",412);
        r.stationCrate=extractStationProp(r,st.crateProp,"__rescueStationCrate",475);
        syncStation(r,"investigate");
        r.artReady=true;r.loadTicks=0;
        createJeepTarget(r);setGround(r,"investigate");
        if(r.briefed)makeInteraction(r,1515,470,"jeep");
        stopWatch();
    }
    private static function extractStationProp(r:Object,src:MovieClip,name:String,z:Number):MovieClip {
        if(src==null)return null;
        var b:Object=src.getBounds(r.station);
        var w:Number=Math.ceil(b.xMax-b.xMin)+4;
        var h:Number=Math.ceil(b.yMax-b.yMin)+4;
        if(!(w>4 && h>4))return null;
        var bmp:BitmapData=new BitmapData(w,h,true,0);
        var m:Matrix=src.transform.matrix;
        m.tx-=b.xMin-2;m.ty-=b.yMin-2;
        bmp.draw(src,m);
        var holder:MovieClip=r.world.createEmptyMovieClip(name,r.world.getNextHighestDepth());
        holder._x=b.xMin-2;holder._y=b.yMin-2;
        holder.attachBitmap(bmp,0,"auto",true);
        holder.__bmp=bmp;
        DepthManager.instance.updateDepth(holder,z);
        return holder;
    }
    private static function syncStation(r:Object,state:String):Void {
        if(r.station==null)return;
        r.station.gotoAndStop(state);
        var st:MovieClip=r.station.stationState;
        if(st!=null){
            st.groundProps._visible=false;
            st.initiatorProp._visible=false;
            st.corpseProp._visible=false;
            st.crateProp._visible=false;
        }
        DepthManager.instance.updateDepth(r.station,384);
    }
    public static function artError(r:Object,attempt:Number,code:String,part:String):Void {
        if(!current(r) || r.attempt!=attempt || (part!=undefined && part!=r.loadingPart))return;
        retireLoader(r);
        if(r.attempt<2){loadJeep(r);return;}
        stopWatch();r.world.dispatcher.publish("RescueAssetFailed");
    }
    // Ground-only collision is owned by the current state, separately from the
    // shootable body. Do not append the entire car silhouette to static polygons.
    private static function setGround(r:Object,state:String):Void {
        var collision:SceneCollisionManager=SceneCollisionManager.instance;
        if(collision.collisionLayer==null)return;
        if(r.jeepGround==null){
            r.jeepGround=r.world.createEmptyMovieClip("__rescueJeepGround",r.world.getNextHighestDepth());
            r.coverGround=r.world.createEmptyMovieClip("__rescueCoverGround",r.world.getNextHighestDepth());
        }
        collision.addMovieClipCollision(r.jeepGround,{xMin:628,yMin:310.5,xMax:1051,yMax:393.3});
        var cover:Object=state=="wreck"?{xMin:1402,yMin:389.8,xMax:1493.2,yMax:440.2}:
            state=="detonating"?{xMin:1400.7,yMin:357.8,xMax:1491.8,yMax:426.2}:
            {xMin:1405,yMin:375,xMax:1502,yMax:384};
        collision.addMovieClipCollision(r.coverGround,cover);collision.redraw();
    }
    private static function removeGround(r:Object):Void {
        var collision:SceneCollisionManager=SceneCollisionManager.instance;
        var changed:Boolean=false;
        for(var i:Number=collision.movieClipCollisions.length-1;i>=0;i--){
            var mc:MovieClip=collision.movieClipCollisions[i].mc;
            if(mc===r.jeepGround || mc===r.coverGround){collision.movieClipCollisions.splice(i,1);changed=true;}
        }
        r.jeepGround.removeMovieClip();r.coverGround.removeMovieClip();
        if(changed)collision.redraw();
    }
    private static function rectangle(mc:MovieClip,x0:Number,y0:Number,x1:Number,y1:Number):Void {
        mc.beginFill(0,0);mc.moveTo(x0,y0);mc.lineTo(x1,y0);mc.lineTo(x1,y1);
        mc.lineTo(x0,y1);mc.lineTo(x0,y0);mc.endFill();
    }
    private static function createJeepTarget(r:Object):Void {
        var unit:MovieClip=r.world.createEmptyMovieClip("战斗吉普",r.world.getNextHighestDepth());
        unit._x=835;unit._y=392;unit.hitPoint=3;unit.maxFrame=1;unit.threat=0;
        unit.产生源="无";unit.等级=18;unit.身高=175;unit.名字="战斗吉普";
        unit.element=unit.createEmptyMovieClip("element",1);
        unit.man=unit.createEmptyMovieClip("man",2);
        unit.area=unit.createEmptyMovieClip("area",3);
        rectangle(unit.area,-225,-212,215,0);
        unit.无敌=true;unit.man.无敌标签=true;
        StaticInitializer.initializeMapElementFast(unit,null,true,true);
        // Register as hostile faction so player/allies can shoot it while zombies ignore it.
        TargetCacheManager.removeUnit(unit);
        unit.是否为敌人=true;
        TargetCacheManager.addUnit(unit);
        // Only actual hits from the player or allies consume the authored hit budget.
        // Damage type, weapon family and pellet count use the ordinary hit pipeline.
        unit.dispatcher.subscribeSingle("hit",onJeepHit,NewcomerRescueController);
        unit.dispatcher.subscribeSingle("kill",ignorePrematureKill,NewcomerRescueController);
        r.jeep=unit;
    }
    private static function ignorePrematureKill(target:MovieClip):Void {
        if(current(room) && target===room.jeep && room.phase!="fuse" && room.phase!="exploding" && room.phase!="wreck")target.hp=9999999;
    }
    public static function onJeepHit(target:MovieClip,shooter:MovieClip,bullet:MovieClip):Void {
        var r:Object=room;
        if(!current(r) || target!==r.jeep || r.phase!="armed" || paused())return;
        if(shooter._name!=_root.控制目标 && shooter.是否为敌人!==false)return;
        target.hp=9999999;target.hitPoint--;
        if(target.hitPoint>0)return;
        target.无敌=true;target.man.无敌标签=true;target.hp=0;delete target.aabbCollider;
        r.phase="fuse";r.fuse=45;
        TargetCacheManager.removeUnit(target);
        r.art.cacheAsBitmap=false;
        r.fuseEffect=r.art.vehicleState.引信特效;
        r.fuseEffect.gotoAndStop(2);
        _root.最上层发布文字提示("弹药舱起火了！立刻远离吉普！");
        _root.播放音效("触电.wav");ensureWatch();
    }
    private static function makeInteraction(r:Object,x:Number,y:Number,kind:String):Void {
        if(r.anchor!=null){r.anchor.enableInteractionKey=false;r.anchor.removeMovieClip();}
        var anchor:MovieClip=r.world.createEmptyMovieClip("__rescueInteraction",r.world.getNextHighestDepth());
        anchor._x=x;anchor._y=y;anchor.enableInteractionKey=true;
        // Base-siege pattern: dialogue explains the location before enabling it.
        // The existing interaction manager supplies the nearby key indicator.
        var owner:Object=r.owner;var ticket:Number=r.serial;
        anchor.onInteract=function():Void {org.flashNight.arki.scene.NewcomerRescueController.interact(owner,ticket);};
        r.world.addInteraction(anchor,85,75,x,y);r.anchor=anchor;r.interaction=kind;
        DepthManager.instance.updateDepth(anchor,_root.Ymax);
        var hero:MovieClip=r.world[_root.控制目标];
        if(hero._name!=undefined)SceneInteractionManager.instance.update(hero._x,isNaN(hero.Z轴坐标)?hero._y:hero.Z轴坐标);
    }
    public static function interact(owner:Object,ticket:Number):Void {
        var r:Object=room;
        if(!current(r) || r.owner!==owner || r.serial!=ticket || paused() || !r.anchor.enableInteractionKey)return;
        var hero:MovieClip=r.world[_root.控制目标];
        var y:Number=isNaN(hero.Z轴坐标)?hero._y:hero.Z轴坐标;
        if(!(hero.hp>0) || Math.abs(hero._x-r.anchor._x)>85 || Math.abs(y-r.anchor._y)>75)return;
        r.anchor.enableInteractionKey=false;r.anchor.removeMovieClip();r.anchor=null;
        if(r.interaction=="clinic")r.world.dispatcher.publish("RescueClinicContact");
        else if(r.interaction=="jeep" && r.artReady && r.phase=="investigate"){
            r.phase="record";r.world.dispatcher.publish("RescueJeepInvestigated");
        }
    }
    public static function signal(name:String):Void {
        var r:Object=room;
        if(!current(r) || r.done)return;
        if(name=="observer" && r.index==1 && !r.observer){
            var attribute:Object=_root.兵种库["兵种456"];
            if(attribute.兵种名==null){r.world.dispatcher.publish("RescueAssetFailed");return;}
            // Explicit null is a real third faction, passed as an Object before initialization.
            // NoCount/third-faction actors never enter the ordinary hostile wave budget.
            var init:Object=ObjectUtil.clone(attribute);
            init._x=1180;init._y=510;init.等级=22;init.是否为敌人=null;
            init.产生源="无";init.publishStageEvent=true;init.threatThreshold=0;
            var drone:MovieClip=_root.加载游戏世界人物(attribute.兵种名,"rescue_drone_observer",r.world.getNextHighestDepth(),init);
            if(drone._name==undefined){r.world.dispatcher.publish("RescueAssetFailed");return;}
            r.observer=true;
        }else if(name=="report" && r.index==1 && !r.reported){
            r.reported=true;_root.播放音效("触电.wav");r.world.dispatcher.publish("RescueDroneReported");
        }else if(name=="clinic" && r.index==2){
            r.phase="contact";makeInteraction(r,1420,370,"clinic");
        }else if(name=="clinic_done" && r.index==2){
            completeRoom(r);
        }else if(name=="jeep_ready" && r.index==3 && r.phase=="investigate" && !r.briefed){
            r.briefed=true;
            if(r.artReady)makeInteraction(r,1515,470,"jeep");
        }else if(name=="jeep_unlock" && r.index==3 && r.phase=="record" && r.artReady){
            r.phase="armed";r.art.gotoAndStop("destructible");syncStation(r,"destructible");
            r.art.vehicleState.引信特效.gotoAndStop(1);
            r.jeep.无敌=false;r.jeep.man.无敌标签=false;
        }else if(name=="hold" && r.index==3 && r.blast){
            r.phase="holding";
        }else if(name=="hold_done" && r.index==3 && r.phase=="holding"){
            completeRoom(r);
        }else if(name=="escape" && (r.index==4 || r.index==5)){
            r.done=true;r.phase="complete";
        }else if(name=="receiving_done" && r.index==6){
            completeRoom(r);
        }else if(name=="raid_done" && r.index==7){
            r.done=true;r.phase="complete";
        }
    }
    private static function completeRoom(r:Object):Void {
        if(r.anchor!=null){r.anchor.enableInteractionKey=false;r.anchor.removeMovieClip();r.anchor=null;}
        r.done=true;r.phase="complete";r.manager.clearStage();
    }
    private static function explode(r:Object):Void {
        if(!current(r) || r.blast)return;
        r.blast=true;r.phase="exploding";r.fuse=78;
        r.fuseEffect=null;r.art._x=0;
        r.art.cacheAsBitmap=false;r.art._alpha=100;r.art.gotoAndStop("detonating");
        // One effective-frame clock owns both the flare and body transition.
        // The wreck replaces the shell under frame 8's blast, while smoke lives on.
        r.effect=r.art.vehicleState.殉爆特效;r.effect.gotoAndStop(1);r.wreckVisible=false;
        syncStation(r,"detonating");setGround(r,"detonating");
        var area:MovieClip=r.jeep.createEmptyMovieClip("blastArea",r.jeep.getNextHighestDepth());
        rectangle(area,-330,-345,330,180);area._visible=false;
        var props:Object=_root.子弹属性初始化(area,"近战子弹",r.jeep);
        props.是否为敌人=false;
        props.子弹威力=1800;props.霰弹值=1;props.子弹散射度=0;props.子弹速度=0;
        props.区域定位area=area;props.shootZ=392;props.Z轴攻击范围=160;
        props.击倒率=1;props.水平击退速度=10;props.垂直击退速度=4;
        props.击中地图效果="";props.击中后子弹的效果="火花";
        _root.子弹区域shoot传递(props);
        _root.播放音效("高爆弹爆炸.wav");
    }
    private static function bakeWreck(r:Object):Void {
        r.art.保留屏外尸体=true;r.station.保留屏外尸体=true;
        _root.add2map(r.art,2);_root.add2map(r.station,2);
        if(r.jeep!=null){
            r.jeep.hp=0;delete r.jeep.aabbCollider;
            TargetCacheManager.removeUnit(r.jeep);
            r.jeep.removeMovieClip();r.jeep=null;
        }
    }
    public static function tick():Void {
        var r:Object=room;
        if(!current(r)){teardown();return;}
        if(paused())return;
        if(!r.artReady){
            r.loadTicks++;
            if(r.loadTicks>600)artError(r,r.attempt,"timeout");
            return;
        }
        if(r.phase=="fuse"){
            r.fuse--;
            var fuseFrame:Number=Math.min(47-r.fuse,46);
            r.fuseEffect.gotoAndStop(fuseFrame);
            r.art._x=(r.fuse%2==0)?1.5:-1.5;
            if(r.fuse<=0)explode(r);
        }else if(r.phase=="exploding"){
            r.fuse--;
            var blastFrame:Number=Math.min(79-r.fuse,78);
            if(!r.wreckVisible && blastFrame>=8){
                r.art.vehicleState.gotoAndStop("wreck");r.wreckVisible=true;
                r.effect=r.art.vehicleState.殉爆特效;
                syncStation(r,"wreck");setGround(r,"wreck");
            }
            r.effect.gotoAndStop(blastFrame);
            if(r.fuse<=0){
                r.phase="wreck";
                r.art.gotoAndStop("wreck");syncStation(r,"wreck");r.art.cacheAsBitmap=true;r.station.cacheAsBitmap=true;
                bakeWreck(r);setGround(r,"wreck");stopWatch();
                r.effect=null;
                // Exactly once, after the real bullet settlement and wreck transition.
                r.world.dispatcher.publish("UnitDeath","战斗吉普");
            }
        }else stopWatch();
    }
    public static function interceptClear(manager:Object,world:Object):Boolean {
        var r:Object=room;
        if(!current(r) || r.manager!==manager || r.world!==world || r.done)return false;
        return r.index==2 || r.index==3 || r.index==4 || r.index==5 || r.index==6 || r.index==7;
    }
    public static function prepareDebugClear(manager:Object,world:Object):Void {
        var r:Object=room;
        if(!current(r) || r.manager!==manager || r.world!==world)return;
        r.done=true;r.phase="complete";stopWatch();
        r.anchor.enableInteractionKey=false;r.art._x=0;
    }
    public static function snapshot():Object {
        if(!current(room))return null;
        return {index:room.index,phase:room.phase,done:room.done,reported:room.reported,fuse:room.fuse,
            artReady:room.artReady,blast:room.blast,observerActive:watch!=null,hitPoint:room.jeep.hitPoint,
            wreckVisible:room.wreckVisible,fuseFrame:room.fuseEffect._currentframe,blastFrame:room.effect._currentframe};
    }
    private static function removeExtractedProp(mc:MovieClip):Void {
        if(mc==null)return;
        if(mc.__bmp!=null)mc.__bmp.dispose();
        mc.removeMovieClip();
    }
    private static function teardown():Void {
        stopWatch();
        if(room!=null){
            retireLoader(room);
            if(room.owner===StageReturnFlow.worldIdentity(_root.gameworld)){
                removeGround(room);
                room.anchor.enableInteractionKey=false;room.anchor.removeMovieClip();
                removeExtractedProp(room.stationGround);
                removeExtractedProp(room.stationInitiator);
                removeExtractedProp(room.stationCorpse);
                removeExtractedProp(room.stationCrate);
                room.jeep.removeMovieClip();room.art.removeMovieClip();room.station.removeMovieClip();
            }
        }
        room=null;
    }
}
