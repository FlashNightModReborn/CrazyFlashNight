import flash.display.BitmapData;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.unit.UnitComponent.Routing.StateTransition;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.neur.Event.EventDispatcher;

/** Native player upper-body/leg timelines under the actual traversal and state services.
 * Reload callbacks are sentinels, with a positive native-frame control; no inventory is used.
 */
class org.flashNight.arki.scene.Cf6TraversalNativeTest {
    private static var saved:Object,world:MovieClip,driver:MovieClip,hero:MovieClip;
    private static var clothes:Object,pants:Object,rifle:Object,pistol:Object,cases:Array,row:Object,t:Object,room:Object;
    private static var stage:String,index:Number,age:Number,pending:Number,passed:Number,failed:Number;
    private static var sideEffects:Number,done:Boolean;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6TraversalNative: "+label);}
    }
    private static function noop():Void {}
    private static function noKey():Boolean {return false;}
    public static function effect():Void {sideEffects++;}
    public static function bindUpper(u:MovieClip):Void {
        u.换弹匣=effect;u.主手换弹匣=effect;u.副手换弹匣=effect;u.结束换弹=effect;
        u.开始射击=effect;u.长枪射击=effect;u.手枪射击=effect;u.手枪2射击=effect;
    }
    public static function initActor(u:MovieClip):Void {
        u.stop();u.hp=u.hp满血值=100;u.身高=175;u.性别="男";u.兵种="主角-男";
        u.操控编号=-1;u.是否为敌人=false;u.hasDressup=true;u.syncRefs={};u.dispatcher=new EventDispatcher();
        u.被动技能={};u.version=index+1;u.攻击模式=row.mode;u.状态=row.mode+"站立";u.方向="右";u.myxscale=100;
        u.动作A=u.动作B=u.动作C=false;u.行走=noop;u.行走冷却帧=0;u.按键控制攻击模式=noop;u.按键检测=noKey;
        u.状态改变=function(value:String):Void {StateTransition.apply(this,value);};
        u.方向改变=function(value:String):Void {if(this.锁定方向)return;this.方向=value;this._xscale=value=="左"?-100:100;};
        u.读取当前飞行状态=noop;u.存储当前飞行状态=noop;
        var top:Array=["身体","上臂","左下臂","右下臂"];
        for(var i:Number=0;i<top.length;i++) u[top[i]]="男"+clothes.data.dressup+top[i];
        var legs:Array=["屁股","左大腿","右大腿","左小腿","右小腿"];
        for(i=0;i<legs.length;i++) u[legs[i]]="男"+pants.data.dressup+legs[i];
        u.长枪_装扮=rifle.data.dressup;u.长枪属性=rifle.data;u.长枪弹匣容量=rifle.data.capacity;
        u.手枪_装扮=u.手枪2_装扮=pistol.data.dressup;u.手枪属性=u.手枪2属性=pistol.data;
        u.长枪={name:rifle.name,value:{level:1,shot:5}};
        u.手枪={name:pistol.name,value:{level:1,shot:3}};u.手枪2={name:pistol.name,value:{level:1,shot:4}};
        u.上装装备={name:clothes.name,value:{level:1}};u.下装装备={name:pants.name,value:{level:1}};
        u.头部装备数据={};u.生命周期函数列表=[];
    }
    public static function runAllTests():Void {
        passed=failed=sideEffects=0;index=-1;done=false;stage="xml";age=0;pending=3;
        saved={world:_root.gameworld,depth:DepthManager.instance,control:_root.控制目标,manager:StageManager.instance,
            skin:_root.装备引用配置,functions:_root.主角函数,initPlayer:_root.初始化玩家模板,
            initHero:_root.初始化主角模板,shadow:_root.是否阴影,pause:_root.暂停,sound:_root.播放音效,
            ext:_root._saveExt,slot:_root.savePath,stageName:_root.当前关卡名};
        var definition:Object=BookDefinition;saved.definition=definition._cf6;
        PauseManager.install();_root.暂停=false;_root.是否阴影=false;_root.播放音效=noop;
        _root.装备引用配置={配置装扮:DressupReferenceManager.attach,刷新所有装扮:DressupReferenceManager.refreshAll};
        _root.主角函数={持枪行走状态机:noop,双枪行走状态机:noop,
            初始化换弹负担:effect,换弹门禁:effect,换弹帧率控制:effect,
            双枪初始化换弹负担:effect,双枪换弹门禁:effect,双枪换弹帧率控制:effect};
        var init:Function=function():Void {org.flashNight.arki.scene.Cf6TraversalNativeTest.bindUpper(this);};
        _root.主角函数.初始化长枪射击函数=init;_root.主角函数.初始化手枪射击函数=init;
        _root.主角函数.初始化手枪2射击函数=init;_root.主角函数.初始化双枪射击函数=init;
        _root.初始化玩家模板=function():Void {org.flashNight.arki.scene.Cf6TraversalNativeTest.initActor(this);};
        _root.初始化主角模板=_root.初始化玩家模板;
        world=_root.createEmptyMovieClip("__cf6TraversalNativeWorld",30060);world._visible=false;
        world.__stageReturnWorldIdentity={};world.dispatcher=new EventDispatcher();world.getNextHighestDepth=function():Number {return 900000+(this.__next=this.__next==undefined?1:this.__next+1);};
        _root.gameworld=world;DepthManager.instance=new DepthManager(world,0,870655,32);DepthManager.instance.calibrate(0,600);
        var manager:Object={currentStage:0,isFailed:false,isFinished:false,isActive:true,gameworld:world};var managerClass:Object=StageManager;managerClass.instance=manager;
        room={world:world,owner:world.__stageReturnWorldIdentity,stageManager:manager,stageIndex:0};world.__cf6Mechanism=room;
        cases=[];var modes:Array=["长枪","手枪","双枪"];
        for(var i:Number=0;i<modes.length;i++) {cases.push({mode:modes[i],duration:174,kind:"door",serviceMode:"depart"});cases.push({mode:modes[i],duration:30,kind:"elevator",serviceMode:"arrive"});}
        driver=_root.createEmptyMovieClip("__cf6TraversalNativeWatch",30061);
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6TraversalNativeTest.tick();};
        check(_root.__cadenceRsl!=undefined && _root.__appearanceEquipmentRsl!=undefined,"actual player and equipment RSL anchors");
        loadXml("data/items/防具_0-19级.xml","clothes");loadXml("data/items/武器_长枪_突击步枪.xml","rifle");loadXml("data/items/武器_手枪_大威力手枪.xml","pistol");
    }
    private static function loadXml(url:String,key:String):Void {
        var doc:XML=new XML();doc.ignoreWhite=true;
        doc.onLoad=function(ok:Boolean):Void {org.flashNight.arki.scene.Cf6TraversalNativeTest.xmlReady(key,ok,this);};doc.load(url);
    }
    public static function xmlReady(key:String,ok:Boolean,doc:XML):Void {
        if(done) return;check(ok,"real equipment XML "+key);if(!ok) {finish();return;}
        var items:Array=XMLParser.configureDataAsArray(XMLParser.parseXMLNode(doc.firstChild).item);
        for(var i:Number=0;i<items.length;i++) {
            var item:Object=items[i];
            if(key=="clothes" && item.name=="Andy上装-NPC") clothes=item;
            if(key=="clothes" && item.name=="Andy下装-NPC") pants=item;
            if(key=="rifle" && item.name=="M4A1") rifle=item;
            if(key=="pistol" && item.name=="Desert Eagle") pistol=item;
        }
        check(key=="clothes" ? clothes.data.dressup=="变装-Andy上装" && pants.data.dressup=="变装-Andy下装"
            : key=="rifle" ? rifle.data.dressup=="枪-长枪-M4A1" : pistol.data.dressup=="枪-手枪-Desert Eagle","real XML dressup mapping "+key);
        if(--pending==0) nextCase();
    }
    private static function nextCase():Void {
        if(t!=null) Cf6TraversalService.cancel(t);t=null;Cf6MapMechanism.teardown();
        if(hero!=undefined) {DepthManager.instance.removeMovieClip(hero);hero.removeMovieClip();}
        if(++index==cases.length) {finish();return;}
        row=cases[index];sideEffects=0;row.legFrames={};row.legChanges={};row.walkSamples=0;row.upperEscapes=0;row.rootMismatch=0;row.directionEscapes=0;
        var name:String="nativeTraversalHero"+index;_root.控制目标=name;
        var init:Object=Cf6ActorMaskState.prepare(world,world.__stageReturnWorldIdentity,name,{_x:250,_y:300,Z轴坐标:300,性别:"男"});
        hero=world.attachMovie("主角-男",name,world.getNextHighestDepth(),init);Cf6ActorMaskState.bind(hero,init);
        initActor(hero);hero.gotoAndStop(row.mode+"站立");DepthManager.instance.updateDepth(hero,300);
        stage="warm";age=0;
    }
    private static function weaponReady():Boolean {
        if(row.mode=="长枪") return hero.长枪_引用._name=="装扮" && hero.长枪_引用._width>0;
        if(row.mode=="手枪") return hero.手枪_引用._name=="装扮" && hero.手枪_引用._width>0;
        return hero.手枪_引用._name=="装扮" && hero.手枪2_引用._name=="装扮" && hero.手枪_引用._width>0 && hero.手枪2_引用._width>0;
    }
    private static function start():Void {
        var samples:Array=[];
        for(var f:Number=1;f<=row.duration;f++) {
            // Exact source A03 departure action spans: stand1-54, walk55-90,
            // stand91-136, walk137-174. Spatially bounded to this disposable world.
            var walk:Boolean=row.kind=="elevator" || f>=55 && f<=90 || f>=137;
            samples.push({frame:f,x:(row.kind=="elevator"?150:250)+f/10,z:300,visible:true,action:walk?"walk":"stand"});
        }
        var spec:Object={mode:row.serviceMode,fps:30,durationFrames:row.duration,
            actorReleaseFrame:null,actorSortY:300,gate:{x:250,z:300,radius:42},exit:{x:270,z:300},samples:samples};
        if(row.kind=="elevator") {
            room.mapId="A10";_root.savePath="cf6.native.arrival";_root.当前关卡名="书中历险-毒刺行动";
            _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",slot:String(_root.savePath),seed:47,startedAt:100}};
            var definition:Object=BookDefinition;definition._cf6={maps:[{id:"A10",mechanism:{traversal:{arrive:spec}}}]};
            check(hero._visible && visiblePixels(),"positive control: actual dressed player exists at default spawn "+index);
            var early:Object=Cf6MapMechanism.captureSpawnWindow(world,null,world.__stageReturnWorldIdentity);
            check(early!=null && !hero._visible && hero.锁定方向===true && !_root.暂停,"actual SceneReady handler hides native player before any subsequent render "+index);
        }
        t=Cf6TraversalService.create(room,spec);
        row.walk=hero.行走;row.switchMode=hero.按键控制攻击模式;row.keyCheck=hero.按键检测;
        sideEffects=0;stage=row.kind=="elevator"?"prepared":"play";age=0;
    }
    private static function visiblePixels():Boolean {
        var b:BitmapData=new BitmapData(800,600,true,0);b.draw(world);
        var rect:Object=b.getColorBoundsRect(0xFF000000,0,false);var visible:Boolean=rect.width>0 && rect.height>0;b.dispose();return visible;
    }
    private static function observe():Void {
        if(hero.方向!="右") row.directionEscapes++;
        if(hero.man._currentframe!=2) row.upperEscapes++;
        if(hero.状态!=row.mode+(t.rules.samples[t.rules.frame-1].action=="walk"?"行走":"站立")) row.rootMismatch++;
        if(hero.状态==row.mode+"行走") {
            row.walkSamples++;
            for(var key:String in hero) {
                var child:MovieClip=hero[key];
                if(typeof child!="movieclip" || child._parent!==hero || child===hero.man || child._totalframes!==22) continue;
                if(row.legFrames[key]!=undefined && row.legFrames[key]!=child._currentframe)
                    row.legChanges[key]=row.legChanges[key]==undefined?1:row.legChanges[key]+1;
                row.legFrames[key]=child._currentframe;
            }
        }
    }
    public static function tick():Void {
        if(done) return;age++;
        if(stage=="xml") {if(age>300) {check(false,"XML timeout");finish();}return;}
        if(stage=="warm" && age==5) {
            check(hero.man._totalframes==(row.mode=="长枪"?78:row.mode=="手枪"?76:107) && weaponReady(),"real upper body and equipped weapon "+index);
            hero.man.gotoAndStop(row.mode=="双枪"?"主手换弹匣":"换弹匣");stage="positive";age=0;return;
        }
        if(stage=="positive" && age==2) {
            check(sideEffects>0,"positive native reload frame reaches sentinel "+index);
            hero.man.gotoAndStop("空闲");stage="reset";age=0;return;
        }
        if(stage=="reset" && age==2) {start();return;}
        if(stage=="prepared") {
            hero.方向改变("左");Cf6TraversalService.observePreparedArrival();
            if(age==3) {
                check(!hero._visible && !visiblePixels() && hero.方向=="右" && t.rules.frame==0,"three actual asset-wait frames remain invisible and direction-held "+index);
                stage="play";age=0;
            }
            return;
        }
        if(stage=="play") {
            // Observe the previous actual render turn BEFORE applying the next sample.
            if(t.rules.frame>0) observe();
            var cue:String=Cf6TraversalService.tick(t,hero,true);
            if(row.kind=="elevator" && t.rules.frame==1)
                check(hero._visible && visiblePixels() && Math.abs(hero._x-t.rules.samples[0].x)<0.06,"first visible native frame is already at the authored arrival point "+index);
            if(cue=="cancelled") {check(false,"unexpected traversal cancellation "+index);finish();return;}
            if(cue=="complete") {row.cue=cue;stage="terminal";age=0;}
            return;
        }
        if(stage=="terminal" && age==1) {
            // Arrival already restores standing at completion; departure keeps the owned last pose.
            if(hero.man._currentframe!=2) row.upperEscapes++;
            var moved:Number=0;for(var key:String in row.legChanges) if(row.legChanges[key]>2) moved++;
            check(row.cue=="complete" && t.rules.frame==row.duration,"full duration completed "+index);
            check(row.upperEscapes==0,"upper body stays idle on every real turn "+index);
            check(sideEffects==0,"no shooting/reload frame callback during traversal "+index);
            check(moved>=2 && row.walkSamples>10,"both native 22-frame leg clips actually advance "+index);
            check(row.rootMismatch==0,"real StateTransition selects authored root walk/stand "+index);
            check(row.directionEscapes==0 && hero.方向=="右","native traversal keeps its frozen authored heading on every observed frame "+index);
            check(hero.长枪.value.shot==5 && hero.手枪.value.shot==3 && hero.手枪2.value.shot==4,"weapon ammo data unchanged "+index);
            check(weaponReady() && hero.攻击模式==row.mode,"original equipment and attack mode retained "+index);
            if(row.kind=="door") Cf6TraversalService.finishAdvance(t,"rejected",{status:"rejected",manualAllowed:true});
            check(!t.acquired && hero.行走===row.walk && hero.按键控制攻击模式===row.switchMode && hero.按键检测===row.keyCheck && !_root.暂停,"owned input and pause restored "+index);
            stage="released";age=0;return;
        }
        if(stage=="released" && age==4) {
            check(hero.man._currentframe==2 && sideEffects==0 && hero.man.__cf6TraversalAnimationOwner==undefined,"release cannot autoplay upper-body combat actions "+index);
            check(row.kind!="elevator" || hero.状态==row.mode+"站立","normal arrival restores standard standing pose "+index);
            trace("Cf6TraversalNative Case: mode="+row.mode+" kind="+row.kind+" frames="+t.rules.frame+" upperEscapes="+row.upperEscapes+" sideEffects="+sideEffects+" walkingTurns="+row.walkSamples);
            nextCase();
        }
    }
    private static function finish():Void {
        if(done) return;done=true;if(t!=null) Cf6TraversalService.cancel(t);Cf6MapMechanism.teardown();
        delete driver.onEnterFrame;driver.removeMovieClip();world.removeMovieClip();
        _root.gameworld=saved.world;DepthManager.instance=saved.depth;_root.控制目标=saved.control;
        var managerClass:Object=StageManager;managerClass.instance=saved.manager;
        _root.装备引用配置=saved.skin;_root.主角函数=saved.functions;_root.初始化玩家模板=saved.initPlayer;_root.初始化主角模板=saved.initHero;
        _root.是否阴影=saved.shadow;_root.播放音效=saved.sound;_root.暂停=saved.pause;
        var definition:Object=BookDefinition;definition._cf6=saved.definition;
        _root._saveExt=saved.ext;_root.savePath=saved.slot;_root.当前关卡名=saved.stageName;
        trace("Cf6TraversalNativeTest Tests Passed: "+passed);trace("Cf6TraversalNativeTest Tests Failed: "+failed);
        _root.cf6TraversalNativeComplete();
    }
}
