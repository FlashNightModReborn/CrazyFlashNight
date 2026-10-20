import org.flashNight.arki.scene.*;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.arki.dialogue.NativeDialogueAppearance;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.neur.Event.EventBus;
import flash.display.BitmapData;
import flash.geom.Matrix;

/** Native art, scene identity, interaction, hit/fuse and native wave timer.
 * Damage settlement and pickups are captured fixtures; no player saves are used.
 */
class org.flashNight.arki.scene.NewcomerRescueTest {
    private static var passed:Number=0;
    private static var failed:Number=0;
    private static var index:Number=0;
    private static var files:Array;
    private static var holder:MovieClip;
    private static var loader:MovieClipLoader;
    private static var world:MovieClip;
    private static var hero:MovieClip;
    private static var watch:MovieClip;
    private static var manager:Object;
    private static var saved:Object;
    private static var ticks:Number=0;
    private static var events:Object={};
    private static var shots:Number=0;
    private static var clears:Number=0;
    private static var bakes:Number=0;
    private static var gifts:Array=[];
    private static var spawn:Object;
    private static var lastProps:Object;
    private static var oldAction:Function;
    public static function runAllTests():Void {
        saved={world:_root.gameworld,hero:_root.控制目标,pause:_root.暂停,transition:_root.场景转换中,
            clock:_root.帧计时器,sound:_root.播放音效,tip:_root.最上层发布文字提示,bake:_root.贴背景图,add2map:_root.add2map,
            pickup:_root.创建可拾取物,spawn:_root.加载游戏世界人物,props:_root.子弹属性初始化,
            shoot:_root.子弹区域shoot传递,ymin:_root.Ymin,ymax:_root.Ymax,factory:StaticInitializer.factory,
            types:_root.兵种库,enemyInit:_root.初始化敌人模板};
        PathManager.setLogLevel(0);PathManager.initialize(_root._url);
        _root.贴背景图=function():Void {};
        _root.add2map=function(mc:MovieClip,layer:Number):Void {if(layer==2)org.flashNight.arki.scene.NewcomerRescueTest.bakes++;};
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {org.flashNight.arki.scene.NewcomerRescueTest.loadedStage(this,ok);};
        xml.load(PathManager.resolvePath("data/stages/副本任务/新人救援.xml"));
    }
    public static function loadedStage(xml:XML,ok:Boolean):Void {
        check(ok && xml.status==0,"production XML loads");
        var data:Object=XMLParser.parseXMLNode(xml.firstChild);
        var stages:Array=XMLParser.configureDataAsArray(data.SubStage);
        check(stages.length==8 && stages[0].id==0 && stages[7].id==7,"eight ordered rooms");
        check(stages[3].Wave.SubWave[1].WaveInformation.Duration==75,"native 75-second hold");
        var lanes:Array=stages[3].SpawnPoint.Point;var capacity:Number=0;
        for(var li:Number=0;li<lanes.length;li++)capacity+=lanes[li].QuantityMax;
        check(lanes.length==6 && capacity==48,"six horde lanes permit 48 concurrent actors");
        var horde:Array=stages[3].Wave.SubWave[1].EnemyGroup.Enemy;var reserve:Number=0;var fodder:Number=0;
        for(var hi:Number=0;hi<horde.length;hi++){
            reserve+=horde[hi].Quantity;
            if(horde[hi].Interval<=550)fodder+=horde[hi].Quantity;
        }
        check(reserve==745 && fodder==720,"dense horde reserve is predominantly continuous basic zombies");
        check(stages[4].SpawnPoint.Point[0].NoCount && stages[5].SpawnPoint.Point[1].NoCount,"pursuit spawn points are excluded from clear counts");
        check(stages[7].Wave.SubWave[0].EnemyGroup.Enemy[0].Type=="兵种456" && stages[7].Wave.SubWave[0].EnemyGroup.Enemy[1].Type=="兵种13","published drone and temporary dog IDs");
        check(stages[2].BasicInformation.Environment.Door.Direction=="左" && stages[3].BasicInformation.Environment.Door.Direction=="右" && stages[4].BasicInformation.PlayerX==100,"jeep turns around east toward the clinic");
        var groundArrows:Number=0;
        for(var ri:Number=0;ri<stages.length;ri++){
            var instances:Array=XMLParser.configureDataAsArray(stages[ri].Instances.Instance);
            for(var ai:Number=0;ai<instances.length;ai++)if(instances[ai].Identifier=="地图箭头")groundArrows++;
        }
        check(groundArrows==0,"no preplaced ground arrows in any room");
        var raidEnemies:Array=stages[7].Wave.SubWave[2].EnemyGroup.Enemy;var hostileBandits:Boolean=true;
        for(var ei:Number=0;ei<raidEnemies.length;ei++)if(raidEnemies[ei].IsHostile!==true || raidEnemies[ei].Type=="兵种27" || raidEnemies[ei].Type=="兵种28")hostileBandits=false;
        check(hostileBandits && raidEnemies[4].Type=="兵种48","dedicated male bandits are explicitly hostile");
        var clinicExplained:Boolean=false;
        for(var ci:Number=0;ci<stages[2].Event.length;ci++)if(stages[2].Event[ci].EventName=="WaveFinished" && stages[2].Event[ci].FollowingEvent.EventName=="RescueClinicExplained")clinicExplained=true;
        check(clinicExplained,"clinic contact is enabled after spoken guidance");
        testAuthoredPortraits(stages);
        files=["backgrounds/gk6_1_BG_70002_departure","backgrounds/gk5_4_BG_70002_rescue",
            "backgrounds/gk5_3_BG_70002","backgrounds/gk5_4_BG_70002_evacuated",
            "backgrounds/gk5_5_BG_70002_return","backgrounds/gk6_1_BG_70002_receiving",
            "backgrounds/gk6_2_BG_70002_raid","arts/70002_jeep","arts/70002_station","portraits/前治安官（无线电）",
            "backgrounds/gk5_5_BG_70002_outbound"];
        loadNext();
    }
    private static function testAuthoredPortraits(stages:Array):Void {
        var previousWorld=_root.gameworld;var previousHero=_root.控制目标;
        _root.gameworld={portraitTestHero:{性别:"女",脸型:"女变装-基本脸型",发型:"玩家专用发型",
            头部装备:"钛合金61式头部装甲",上装装备:"钛合金61式胸甲",颈部装备:"玩家专用围巾"}};
        _root.控制目标="portraitTestHero";
        var player:Object=NativeDialogueAppearance.build("$PC_CHAR","普通",null,"$PC");
        check(player.kind=="doll" && player.appearance.body=="钛合金61式胸甲","portrait control starts with a differently dressed player");
        var codec:LiteJSON=new LiteJSON();var snapshots:Object={};var count:Number=0;var rows:Number=0;var stable:Boolean=true;
        for(var si:Number=0;si<stages.length;si++){
            var stageEvents:Array=XMLParser.configureDataAsArray(stages[si].Event);
            for(var ei:Number=0;ei<stageEvents.length;ei++){
                var lines:Array=XMLParser.configureDataAsArray(stageEvents[ei].Dialogue);
                for(var di:Number=0;di<lines.length;di++){
                    var raw:Object=lines[di];var name:String=raw.Name;
                    if(name!="卫生所幸存者" && name!="防线哨兵" && name!="老兵通话记录")continue;
                    rows++;
                    var parsed:Object=StageInfo.parseSingleDialogue([raw])[0];
                    var portrait:Object=NativeDialogueAppearance.build(parsed.char,"普通",parsed.target,parsed.name);
                    var identity:String=codec.stringify(portrait.appearance);
                    if(snapshots[name]!=undefined){if(snapshots[name]!=identity)stable=false;continue;}
                    count++;snapshots[name]=identity;
                    check(portrait.kind=="doll" && portrait.appearance.gender==raw.Gender && portrait.appearance.face==raw.FaceType && portrait.appearance.hair==raw.HairStyle && (name!="老兵通话记录" || portrait.expression=="普通（无线电）"),"authored speaker owns gender, face, hair and radio filter: "+name);
                    check(portrait.appearance.body==raw.BodyArmor && portrait.appearance.body!=player.appearance.body && portrait.appearance.head=="" && portrait.appearance.neck=="","authored speaker never inherits player armor or empty slots: "+name);
                    trace("NewcomerRescueTest Portrait: "+codec.stringifySafe({name:name,title:raw.Title,text:raw.Text,expression:portrait.expression,appearance:portrait.appearance}));
                    var originalBody:String=portrait.appearance.body;parsed.target.上装装备="已经改变的外观";
                    check(portrait.appearance.body==originalBody,"portrait snapshot stays detached from mutable line attributes: "+name);
                }
            }
        }
        check(count==3 && rows==8,"all eight supporting lines use three explicit portrait actors");
        check(stable,"each supporting speaker keeps the same appearance across events");
        var playerAgain:Object=NativeDialogueAppearance.build("$PC_CHAR","普通",null,"$PC");
        check(playerAgain.appearance.body==player.appearance.body && playerAgain.appearance.gender=="女","returning to player dialogue keeps the player's own identity");
        _root.gameworld=previousWorld;_root.控制目标=previousHero;
    }
    private static function loadNext():Void {
        if(holder!=null)holder.removeMovieClip();
        if(index==files.length){setupWorld();return;}
        holder=_root.createEmptyMovieClip("__rescueAssetProbe",_root.getNextHighestDepth());
        loader=new MovieClipLoader();
        loader.addListener({onLoadInit:function(mc:MovieClip):Void {org.flashNight.arki.scene.NewcomerRescueTest.loadedAsset(mc);},
            onLoadError:function(mc:MovieClip,code:String):Void {org.flashNight.arki.scene.NewcomerRescueTest.assetError(code);}});
        loader.loadClip(PathManager.resolvePath("flashswf/"+files[index]+".swf"),holder);
    }
    public static function assetError(code:String):Void {check(false,"asset load: "+files[index]+" "+code);index++;loadNext();}
    public static function loadedAsset(mc:MovieClip):Void {
        check(mc._width>100 && mc._height>70,"nonempty native art "+files[index]);
        drawReviewTile(mc);
        if(index==1 || index==3){
            var image:BitmapData=new BitmapData(1800,730,true,0);
            image.draw(mc,new Matrix(1,0,0,1,937.7,245.1));
            check(olivePixels(image,720,160,940,290)>100,"truck retains olive body fills instead of one shared palette");
            check(olivePixels(image,100,535,300,610)>40,"motorcycle retains painted olive panels");
            check(olivePixels(image,1330,160,1510,340)>100,"clinic reinforcement retains painted fills");
            image.dispose();
        }
        if(index==7 || index==8){
            mc.gotoAndStop("investigate");check(mc._currentframe==1 && mc._totalframes==4,"four stopped states "+files[index]);
            var before:Number=fingerprint(mc);mc.gotoAndStop("destructible");check(mc._currentframe==2,"destructible label");
            if(index==7)check(mc.vehicleState.引信特效._totalframes==46 && mc.vehicleState.引信特效._currentframe==1,"native 45-frame fuse smoke/fire MovieClip starts stopped on idle frame 1");
            if(index==8)check(mc.stationState.groundProps._width>20 && mc.stationState.coverProp._width>20 && mc.stationState.initiatorProp._width>10 && mc.stationState.corpseProp._width>20 && mc.stationState.crateProp._width>10,"station state splits into five non-empty child MovieClips");
            mc.gotoAndStop("detonating");check(mc._currentframe==3,"detonating label");
            if(index==7)check(mc.vehicleState.殉爆特效._totalframes==78,"full native 78-frame explosion is a live MovieClip");
            if(index==7)check(mc.vehicleState.殉爆特效._xscale==125 && mc.vehicleState.殉爆特效._yscale==125,"explosion diameter is over twice its previous size");
            if(index==7){
                var flare:MovieClip=mc.vehicleState.殉爆特效;flare._visible=false;
                var shell:Number=fingerprint(mc.vehicleState);mc.vehicleState.gotoAndStop("wreck");
                check(mc.vehicleState._currentframe==8 && fingerprint(mc.vehicleState)!=shell,"wreck replaces the intact shell in the early blast cue");
                check(mc.vehicleState.殉爆特效===flare && flare._totalframes==78,"long smoke effect survives the body transition");
                flare._visible=true;
            }
            mc.gotoAndStop("wreck");check(mc._currentframe==4 && fingerprint(mc)!=before,"wreck visibly differs from investigation");
        }
        if(index==9){
            check(mc.__radioBitmap.width==1024 && mc.__radioSource._visible===false,"native radio effect renders the original once into a transparent bitmap");
            check(mc.__radioBitmap.getPixel32(80,80)==0 && mc.__radioBitmap.getPixel32(250,220)!=0,"radio portrait preserves silhouette transparency without a rectangular plate");
            var face:Number=mc.__radioBitmap.getPixel(250,220);
            check((face&255)>(face>>16),"native radio postprocess has a cool blue palette");
        }
        index++;loadNext();
    }
    private static function olivePixels(image:BitmapData,x0:Number,y0:Number,x1:Number,y1:Number):Number {
        var count:Number=0;
        for(var y:Number=y0;y<y1;y+=2)for(var x:Number=x0;x<x1;x+=2){
            var rgb:Number=image.getPixel(x,y);var red:Number=rgb>>16;var green:Number=(rgb>>8)&255;var blue:Number=rgb&255;
            if(green>red*1.04 && green>blue*1.08 && green>25)count++;
        }
        return count;
    }
    private static function drawReviewTile(mc:MovieClip):Void {
        var board:MovieClip=_root.__rescueArtReview;
        if(board==null)board=_root.createEmptyMovieClip("__rescueArtReview",_root.getNextHighestDepth());
        var tile:MovieClip=board.createEmptyMovieClip("tile"+index,board.getNextHighestDepth());
        tile._x=(index%3)*340;tile._y=Math.floor(index/3)*180;
        tile.createTextField("label",1,2,0,336,20);tile.label.text=files[index];tile.label.setTextFormat(new TextFormat("_sans",11,0xFFFFFF));
        var bounds:Object=mc.getBounds(mc);var scale:Number=Math.min(336/(bounds.xMax-bounds.xMin),155/(bounds.yMax-bounds.yMin));
        var image:BitmapData=new BitmapData(336,155,false,0x333333);
        image.draw(mc,new Matrix(scale,0,0,scale,-bounds.xMin*scale,-bounds.yMin*scale));
        var picture:MovieClip=tile.createEmptyMovieClip("picture",2);picture._y=21;picture.attachBitmap(image,0,"auto",true);
    }
    private static function fingerprint(mc:MovieClip):Number {
        var b:Object=mc.getBounds(mc);var scale:Number=Math.min(420/(b.xMax-b.xMin),420/(b.yMax-b.yMin));
        var image:BitmapData=new BitmapData(440,440,true,0);image.draw(mc,new Matrix(scale,0,0,scale,10-b.xMin*scale,10-b.yMin*scale));
        var value:Number=0;
        for(var y:Number=0;y<440;y+=4)for(var x:Number=0;x<440;x+=4)value=(value+(image.getPixel32(x,y)>>>0)*(x+y+1))%1000000007;
        image.dispose();return value;
    }
    private static function setupWorld():Void {
        _root.暂停=false;_root.场景转换中=false;_root.Ymin=240;_root.Ymax=730;
        _root.帧计时器={当前帧数:1,eventBus:EventBus.getInstance()};
        _root.播放音效=function(name:String):Void {};
        _root.最上层发布文字提示=function(text:String):Void {};
        _root.创建可拾取物=function(name:String,n:Number,x:Number,y:Number,toss:Boolean,gates:Object):Void {
            org.flashNight.arki.scene.NewcomerRescueTest.gifts.push({name:name,quantity:n,gates:gates});
        };
        _root.兵种库={兵种456:{兵种名:"敌人-盗贼小飞机",名字:"望风鸢",是否为敌人:true,身高:175}};
        // The real RSL export is attached. Only combat initialization is isolated;
        // this verifies linkage, actual art and pre-initialization faction values.
        _root.初始化敌人模板=function():Void {this.hp=100;this.gotoAndStop("空手站立");};
        _root.加载游戏世界人物=function(id:String,name:String,depth:Number,init:Object):MovieClip {
            org.flashNight.arki.scene.NewcomerRescueTest.spawn={id:id,name:name,init:init};
            init.兵种=id;
            return _root.gameworld.attachMovie(id,name,depth,init);
        };
        _root.子弹属性初始化=function(area:MovieClip,type:String,source:MovieClip):Object {return {发射者:source._name};};
        _root.子弹区域shoot传递=function(props:Object):Void {
            org.flashNight.arki.scene.NewcomerRescueTest.shots++;org.flashNight.arki.scene.NewcomerRescueTest.lastProps=props;
        };
        StaticInitializer.factory=new AABBColliderFactory(4);
        world=_root.__rescueNativeWorld;world._x=0;world._y=0;_root.gameworld=world;
        check(world._name!=undefined && world.门1._name!=undefined,"native battle-world source shares the host asset library context");
        SceneManager.getInstance().initGameWorld(world);
        hero=world.createEmptyMovieClip("rescueTestHero",world.getNextHighestDepth());
        hero.hp=100;hero.是否为敌人=false;_root.控制目标=hero._name;
        world.dispatcher.subscribe("RescueClinicContact",recordClinic,NewcomerRescueTest);
        world.dispatcher.subscribe("RescueDroneReported",recordReport,NewcomerRescueTest);
        world.dispatcher.subscribe("RescueJeepInvestigated",recordInvestigation,NewcomerRescueTest);
        world.dispatcher.subscribe("UnitDeath",recordDeath,NewcomerRescueTest);
        world.dispatcher.subscribe("Clear",recordClear,NewcomerRescueTest);
        manager=StageManager.getInstance();saved.clear=manager.clearStage;
        saved.managerWorld=manager.gameworld;saved.stageInfo=manager.currentStageInfo;saved.stageList=manager.stageInfoList;saved.stage=manager.currentStage;
        manager.gameworld=world;manager.currentStageInfo={basicInfo:{Animation:{Load:-1}}};manager.stageInfoList=new Array(8);manager.currentStage=2;
        manager.isActive=true;manager.isFailed=false;manager.isFinished=false;
        NewcomerRescueController.start(0);
        check(!NewcomerRescueController.interceptClear(manager,world) && !NewcomerRescueController.snapshot().observerActive,"departure has no objective lock or idle observer");
        NewcomerRescueController.start(1);NewcomerRescueController.signal("observer");
        check(spawn.id=="敌人-盗贼小飞机" && spawn.init.是否为敌人===null && spawn.init.产生源=="无","observer resolves unit ID to the actual exported linkage");
        check(_root.兵种库.兵种456.是否为敌人===true,"neutral override cannot mutate the shared hostile unit table");
        NewcomerRescueController.signal("observer");NewcomerRescueController.signal("report");NewcomerRescueController.signal("report");
        check(events.report==1,"uplink happens once independently of later drone death");
        NewcomerRescueController.start(2);
        check(NewcomerRescueController.interceptClear(manager,world),"clinic exit stays locked after ordinary combat");
        check(world.允许通行!==true,"clinic passage stays closed before contact");
        NewcomerRescueController.signal("clinic");oldAction=world.__rescueInteraction.onInteract;
        check(world.__rescueInteraction.enableInteractionKey && world.__rescueInteraction.hint==undefined,"dialogue enables native interaction without a floating callout");
        setHero(0,0);oldAction();check(!events.clinic,"far interaction rejected");
        setHero(1420,370);hero.hp=0;oldAction();check(!events.clinic,"dead interaction rejected");
        hero.hp=100;_root.暂停=true;oldAction();check(!events.clinic,"paused interaction rejected");_root.暂停=false;
        SceneInteractionManager.instance.update(hero._x,hero.Z轴坐标);
        SceneInteractionManager.instance.interact();oldAction();check(events.clinic==1 && world.__rescueInteraction._name==undefined,"real interaction manager consumes and removes clinic contact once");
        NewcomerRescueController.signal("clinic_done");NewcomerRescueController.signal("clinic_done");
        check(clears==1 && !NewcomerRescueController.interceptClear(manager,world),"dialogue completion opens clinic once");
        check(world.允许通行===true,"real StageManager clear opens the native exit after the contact dialogue");
        NewcomerRescueController.start(6);oldAction();check(NewcomerRescueController.snapshot().phase=="battle","same-world stale callback is inert");
        NewcomerRescueController.start(3);
        watch=_root.createEmptyMovieClip("__rescueTestWatch",_root.getNextHighestDepth());
        watch.onEnterFrame=function():Void {org.flashNight.arki.scene.NewcomerRescueTest.waitForJeep();};
    }
    public static function recordClinic():Void {events.clinic=events.clinic>0?events.clinic+1:1;}
    public static function recordReport():Void {events.report=events.report>0?events.report+1:1;}
    public static function recordInvestigation():Void {events.investigated=events.investigated>0?events.investigated+1:1;}
    public static function recordDeath(name:String):Void {if(name=="战斗吉普")events.death=events.death>0?events.death+1:1;}
    public static function recordClear():Void {clears++;}
    public static function waitForJeep():Void {
        ticks++;
        if(ticks>650){check(false,"jeep load watchdog");finish();return;}
        if(!NewcomerRescueController.snapshot().artReady)return;
        delete watch.onEnterFrame;watch.removeMovieClip();watch=null;
        var drone:MovieClip=world.rescue_drone_observer;
        trace("NewcomerRescueTest Drone: name="+drone._name+" width="+drone._width+" faction="+drone.是否为敌人+" frame="+drone._currentframe);
        check(drone._name=="rescue_drone_observer" && drone._width>40 && drone.是否为敌人===null,"real drone export attaches as third faction with visible art");
        check(!NewcomerRescueController.snapshot().observerActive,"asset watcher retires when both actual SWFs load");
        var jeep:MovieClip=world.战斗吉普;
        check(jeep.dispatcher!=undefined && jeep.aabbCollider!=undefined && jeep.hitPoint==3 && jeep.是否为敌人===true && gifts.length==2,"actual map-element initializer creates hostile-faction target and pre-places supplies on room entry");
        check(world.__rescueStationGround.getDepth()<world.__rescueStationArt.getDepth() && world.__rescueStationArt.getDepth()<world.__rescueStationInitiator.getDepth() && world.__rescueStationInitiator.getDepth()<world.__rescueStationCorpse.getDepth() && world.__rescueStationCorpse.getDepth()<world.__rescueStationCrate.getDepth(),"station props are split into five strictly ordered depth planes");
        jeep.dispatcher.publish("hit",jeep,hero,{});
        check(jeep.hitPoint==3 && jeep.无敌,"pre-investigation hits cannot detonate");
        check(world.__rescueInteraction._name==undefined,"jeep investigation remains unavailable until spoken guidance finishes");
        NewcomerRescueController.signal("jeep_ready");
        setHero(1515,470);world.__rescueInteraction.onInteract();
        check(events.investigated==1 && NewcomerRescueController.snapshot().phase=="record","near investigation starts record");
        NewcomerRescueController.signal("jeep_unlock");NewcomerRescueController.signal("jeep_unlock");
        check(gifts.length==2 && gifts[0].name=="Type56R" && gifts[1].name=="突击步枪通用弹药","room entry and unlock keep a single pre-placed supply set");
        var gates:Object=gifts[0].gates;
        check(gates.最小任务链进度==1 && gates.最大任务链进度==1 && gates.要求进行中任务ID==70002 && gates.一次性领取ID=="iron_spear_70002_veteran_type56r","real pickup request carries all persistence gates");
        var hostile:MovieClip=world.createEmptyMovieClip("hostile",world.getNextHighestDepth());hostile.是否为敌人=true;
        jeep.dispatcher.publish("hit",jeep,hostile,{});check(jeep.hitPoint==3,"hostile hits do not consume player objective");
        for(var i:Number=0;i<3;i++)jeep.dispatcher.publish("hit",jeep,hero,{});
        check(NewcomerRescueController.snapshot().phase=="fuse" && NewcomerRescueController.snapshot().fuseFrame==2 && world.__rescueBlastWarning==undefined && shots==0,"three actual hit events start native fuse smoke/fire without a rectangular warning overlay");
        _root.暂停=true;for(i=0;i<60;i++)NewcomerRescueController.tick();
        check(NewcomerRescueController.snapshot().fuse==45 && NewcomerRescueController.snapshot().fuseFrame==2 && shots==0,"pause freezes fuse and smoke progression");_root.暂停=false;
        for(i=0;i<44;i++)NewcomerRescueController.tick();check(shots==0 && NewcomerRescueController.snapshot().fuseFrame==46,"last-hit frame and first 44 fuse ticks advance native smoke/fire to frame 46");
        NewcomerRescueController.tick();check(shots==1 && NewcomerRescueController.snapshot().phase=="exploding" && world.__rescueJeepArt._x==0,"fuse submits exactly one normal bullet settlement request and resets chassis vibration");
        check(lastProps.子弹威力==1800 && lastProps.shootZ==392 && lastProps.Z轴攻击范围==160 && lastProps.是否为敌人===false,"AOE request uses authored blast tuning");
        check(NewcomerRescueController.snapshot().blastFrame==1 && !NewcomerRescueController.snapshot().wreckVisible,"blast begins with a controlled first frame");
        for(i=0;i<6;i++)NewcomerRescueController.tick();
        check(NewcomerRescueController.snapshot().blastFrame==7 && !NewcomerRescueController.snapshot().wreckVisible,"body waits only for the opening flare");
        NewcomerRescueController.tick();
        check(NewcomerRescueController.snapshot().wreckVisible && world.__rescueJeepArt.vehicleState._currentframe==8 && NewcomerRescueController.snapshot().blastFrame==8 && !events.death,"wreck appears under the early blast while the long effect continues");
        _root.暂停=true;for(i=0;i<60;i++)NewcomerRescueController.tick();_root.暂停=false;
        check(NewcomerRescueController.snapshot().fuse==71 && NewcomerRescueController.snapshot().blastFrame==8,"pause freezes both the visual effect and wreck clock");
        for(i=0;i<70;i++)NewcomerRescueController.tick();check(!events.death,"death event waits for complete effect interval");
        NewcomerRescueController.tick();for(i=0;i<4;i++)NewcomerRescueController.tick();
        check(events.death==1 && shots==1 && world.__rescueJeepArt._currentframe==4 && jeep.hp==0 && jeep.aabbCollider==undefined && NewcomerRescueController.snapshot().hitPoint==undefined && bakes==2,"wreck bakes into background, retires target and emits a single named UnitDeath");
        NewcomerRescueController.signal("hold");check(NewcomerRescueController.interceptClear(manager,world),"wreck alone cannot complete hold");
        NewcomerRescueController.signal("hold_done");check(clears==2 && NewcomerRescueController.snapshot().done,"hold completion releases clear once");
        NewcomerRescueController.start(4);check(NewcomerRescueController.interceptClear(manager,world),"pursuit waits for exit boundary");
        NewcomerRescueController.signal("escape");check(!NewcomerRescueController.interceptClear(manager,world),"boundary releases pursuit without clear-all");
        testTimer();
        NewcomerRescueController.start(-1);check(NewcomerRescueController.snapshot()==null && world.__rescueJeepArt._name==undefined && world.__rescueStationCorpse==undefined,"teardown removes owned art, split station props and observer");
        finish();
    }
    private static function testTimer():Void {
        var sp:Object=WaveSpawner.getInstance();var oldFinish:Function=sp.finishWave;
        sp.gameworld=world;world.地图.僵尸型敌人总个数=0;sp.waveInformation={};
        sp.spawnPoints=[{NoCount:true,僵尸型敌人总个数:200},{NoCount:false,僵尸型敌人总个数:3}];
        check(sp.getEnemyCount()==3,"production NoCount excludes pursuit while retaining counted hostiles");
        sp.spawnPoints=[];sp.isActive=true;sp.isFinished=false;sp.countDownTime=0;sp.waveTime=75;sp.finishRequirement=-1;
        sp.finishWave=function():Void {this.isFinished=true;};
        for(var i:Number=0;i<74;i++)sp.clockTick();check(!sp.isFinished,"empty 75-second hold cannot finish early");
        sp.clockTick();check(sp.isFinished && sp.countDownTime==75,"native timer finishes exactly at 75 seconds");
        sp.finishWave=oldFinish;sp.isActive=false;
    }
    private static function setHero(x:Number,y:Number):Void {hero._x=x;hero._y=y;hero.Z轴坐标=y;}
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else {failed++;trace("NewcomerRescueTest FAIL: "+label);}
    }
    private static function finish():Void {
        if(watch!=null){delete watch.onEnterFrame;watch.removeMovieClip();}
        NewcomerRescueController.start(-1);manager.clearStage=saved.clear;manager.isActive=false;
        manager.gameworld=saved.managerWorld;manager.currentStageInfo=saved.stageInfo;manager.stageInfoList=saved.stageList;manager.currentStage=saved.stage;
        _root.gameworld=saved.world;_root.控制目标=saved.hero;_root.暂停=saved.pause;_root.场景转换中=saved.transition;
        _root.帧计时器=saved.clock;_root.播放音效=saved.sound;_root.最上层发布文字提示=saved.tip;_root.贴背景图=saved.bake;_root.add2map=saved.add2map;
        _root.创建可拾取物=saved.pickup;_root.加载游戏世界人物=saved.spawn;_root.子弹属性初始化=saved.props;_root.子弹区域shoot传递=saved.shoot;
        _root.Ymin=saved.ymin;_root.Ymax=saved.ymax;StaticInitializer.factory=saved.factory;
        _root.兵种库=saved.types;_root.初始化敌人模板=saved.enemyInit;
        trace("NewcomerRescueTest Tests Passed: "+passed);trace("NewcomerRescueTest Tests Failed: "+failed);
        trace("NewcomerRescueTest Assets Loaded: "+index+"/"+files.length);
        trace("FocusedTestRunId newcomer-rescue Complete: "+_root.__newcomerRescueFocusedRunId);
    }
}
