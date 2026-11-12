import org.flashNight.arki.render.LightRegistry;
import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.render.CombatFxBridge;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.Action.Huofeng.HuofengAction;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.gesh.xml.LoadXml.LightProfilesLoader;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

// The same compiled SWF also runs from an isolated resources folder with an author-edited XML.
class org.flashNight.arki.render.DynamicLightProfilesTest {
    private static var world:MovieClip;
    private static var hero:MovieClip;
    private static var ticker:MovieClip;
    private static var xml:XML;
    private static var weapons:Object;
    private static var loadStarted:Number;
    private static var stockReady:Boolean;
    private static var ladyReady:Boolean;
    private static var assetLoader:MovieClipLoader;
    private static var assetListener:Object;
    private static var lady:MovieClip;
    private static var skill:MovieClip;
    private static var emitted:Array;
    private static var timelineStep:Number;
    private static var timelineStarted:Number;
    private static var previousInitialize:Object;
    private static var previousShoot:Object;
    private static var runId:String;
    private static var failed:Number;
    private static var observations:Array;
    private static var previousWorld:MovieClip;
    private static var previousClock:Object;
    private static var previousPause:Object;
    private static var previousHero:Object;

    private static function check(value:Boolean, message:String):Void {
        if (!value) { failed++; record("[TEST_FAIL] DynamicLightProfilesTest: " + message); }
    }
    private static function registry(profiles:String, binds:String):Object {
        var doc:XML = new XML(); doc.ignoreWhite = true;
        doc.parseXML('<LightProfiles version="1"><Profiles>'+profiles+'</Profiles><Bindings>'+binds+'</Bindings></LightProfiles>');
        return LightRegistry.parse(doc);
    }
    private static function validation():Void {
        var profile:String = '<Profile id="p" radius="100" energy="1" color="#cc8811" totalFrames="6" isExplosion="false"/>';
        var binding:String = '<Binding kind="projectile" key="a" profile="p"/>';
        check(registry(profile,binding).projectile.a.spec.radius == 100,"valid profile");
        var replacements:Array = [
            ['id="p"','id=""'], ['id="p"','id="__proto__"'], ['radius="100"','radius="0"'],
            ['radius="100"','radius="321"'], ['energy="1"','energy="NaN"'], ['energy="1"','energy="2.1"'],
            ['color="#cc8811"','color="cc8811"'], ['color="#cc8811"','color="#zz0000"'],
            ['totalFrames="6"','totalFrames="1.5"'], ['totalFrames="6"','totalFrames="0"'],
            ['isExplosion="false"','isExplosion="yes"'], ['/>',' bogus="1"/>'], ['/>',' stageFrame="2"/>'],
            ['/>',' stageFrame="7" stageRadius="90" stageEnergy="1" stageOffsetY="0"/>']
        ];
        var bad:Number = 0;
        for (var i:Number=0; i<replacements.length; i++) {
            var changed:String = profile.split(replacements[i][0]).join(replacements[i][1]);
            if (registry(changed,binding) == null) bad++;
        }
        if (registry(profile+profile,binding) == null) bad++;
        if (registry(profile,binding+binding) == null) bad++;
        if (registry(profile,binding.split('profile="p"').join('profile="missing"')) == null) bad++;
        if (registry(profile,binding.split('projectile').join('unknown')) == null) bad++;
        if (registry(profile,binding.split('key="a"').join('key=" a"')) == null) bad++;
        if (registry(profile,binding.split('/>').join(' radius="3"/>')) == null) bad++;
        if (registry(profile,binding+binding.split('projectile').join('asset')) == null) bad++;
        if (registry(profile,'<Binding kind="area" key="x" profile="p" auxProfile="absent"/>') == null) bad++;
        if (registry(profile,'<Binding kind="area" key="x" profile="p" auxProfile="p" nearFraction=".8" farFraction=".2"/>') == null) bad++;
        check(bad==23,"23 malformed author inputs rejected: "+bad);
        trace("DynamicLightProfilesTest invalid="+bad);
    }

    public static function setRunId(id:String):Void { runId=id; }

    public static function runAllTests():Void {
        failed=0; loadStarted=getTimer(); stockReady=false; ladyReady=false; weapons={}; observations=[];
        // CS6 exercises the parser locally. The companion runner reuses this exact SWF in Player 20
        // for same-origin external artwork, complete combat lifecycles and the four XML restarts.
        if (_root._url.indexOf("/light-author-proof/")<0) {
            validation();
            record("DynamicLightProfilesTest Tests Failed: "+failed);
            trace("FocusedTestRunId dynamic-light-profiles Complete: "+runId);
            return;
        }
        previousWorld=_root.gameworld; previousClock=_root.帧计时器; previousPause=_root.暂停; previousHero=_root.控制目标;
        world=_root.createEmptyMovieClip("__dynamicLightWorld",_root.getNextHighestDepth());
        _root.gameworld=world; _root.帧计时器={当前帧数:1}; _root.暂停=false; _root.控制目标="fixtureHero";
        hero=world.createEmptyMovieClip("fixtureHero",1); hero._x=200;hero._y=180;hero.version=1;
        hero.createEmptyMovieClip("man",1); hero.被动技能={};
        assetLoader=new MovieClipLoader();
        assetListener={};
        assetListener.onLoadInit=function(target:MovieClip):Void {
            if (target._name=="子弹区域") DynamicLightProfilesTest.stockReady=true;
            if (target._name=="效果") DynamicLightProfilesTest.ladyReady=true;
        };
        assetListener.onLoadError=function(target:MovieClip, reason:String):Void {
            DynamicLightProfilesTest.check(false,"external art "+target._name+" failed: "+reason);
        };
        assetLoader.addListener(assetListener);
        assetLoader.loadClip("../flashswf/arts/原版素材库-子弹.swf",world.createEmptyMovieClip("子弹区域",2));
        assetLoader.loadClip("../flashswf/arts/new/lady.swf",world.createEmptyMovieClip("效果",3));
        xml=new XML(); xml.ignoreWhite=true; xml.onLoad=function(ok:Boolean):Void {
            if (!ok) { DynamicLightProfilesTest.check(false,"weapon XML"); return; }
            for (var item:XMLNode=this.firstChild.firstChild; item!=null; item=item.nextSibling) {
                var name:String; var fields:Array=[];
                for (var n:XMLNode=item.firstChild; n!=null; n=n.nextSibling) {
                    if (n.nodeName=="name") name=n.firstChild.nodeValue;
                    else if (n.nodeName=="data") for (var f:XMLNode=n.firstChild; f!=null; f=f.nextSibling) {
                        var text:String=f.firstChild.nodeValue;
                        fields[f.nodeName] = isNaN(Number(text)) ? text : Number(text);
                    }
                }
                if (name=="RPG" || name=="M3 Rocket Launcher") weapons[name]=fields;
            }
        };
        xml.load(PathManager.resolvePath("data/items/武器_长枪_发射器.xml"));
        LightProfilesLoader.start();
        ticker=_root.createEmptyMovieClip("__dynamicLightClock",_root.getNextHighestDepth());
        ticker.onEnterFrame=function():Void { DynamicLightProfilesTest.poll(); };
    }

    private static function poll():Void {
        if (LightProfilesLoader.settled() && weapons.RPG && weapons["M3 Rocket Launcher"] && stockReady && ladyReady && linkagesReady()) {
            delete ticker.onEnterFrame;
            var caps:Object={version:1,generation:1,styles:[],digest:"",worldLights:true,equipmentLights:2,equipmentRadialLights:1}; caps["native"]=false;
            CombatFxBridge.configure(caps);
            ColliderFactoryRegistry.init();
            DamageManagerFactory.init();
            validation();
            rocket("RPG"); rocket("M3 Rocket Launcher");
            var bridge:Object=EquipmentLightBridge;
            if (bridge["lightProfiles"].count>0) { examples(); saturation(); beginTimeline(); return; }
            else record("LightAuthorDegraded empty");

            finish(); return;
        }
        if (getTimer()-loadStarted>45000) {
            check(false,"load url="+_root._url+" root="+PathManager.resolvePath("data/combat_visuals/light_profiles.xml")
                +" registry="+LightProfilesLoader.settled()+" weapons="+(weapons.RPG!=null)+"/"+(weapons["M3 Rocket Launcher"]!=null)
                +" stock="+world.子弹区域.getBytesLoaded()+"/"+world.子弹区域.getBytesTotal()
                +" lady="+world.效果.getBytesLoaded()+"/"+world.效果.getBytesTotal());
            finish();
        }
    }

    // CS6 can announce first-frame initialization before making a large library's exports available.
    private static function linkagesReady():Boolean {
        var stock:MovieClip=world.子弹区域.attachMovie("火箭弹","__checkRocket",900);
        var lady:MovieClip=world.效果.attachMovie("支援飞弹","__checkLady",900);
        var ready:Boolean=stock._parent===world.子弹区域 && lady._parent===world.效果;
        stock.removeMovieClip();lady.removeMovieClip();
        return ready;
    }

    private static function observe(label:String):String {
        var wire:String=EquipmentLightBridge.payload();
        record("LightAuthorSample "+label+" "+wire);
        return wire;
    }
    private static function rocket(name:String):Void {
        EquipmentLightBridge.resetScene();
        var rng:LinearCongruentialEngine=LinearCongruentialEngine.getInstance();
        var previous:Number=rng.captureState();rng.restoreState(12345);
        var props:Object=ShootInitCore.generateBulletProps(hero,"长枪",weapons[name],{});
        props.shootX=200;props.shootY=180;props.shootZ=180;
        BulletFactory.prepareBulletData(props,hero);
        var shot:MovieClip=BulletFactory.createBullet(props,hero,0);
        check(props.baseAsset=="火箭弹" && shot._parent===world.子弹区域 && shot.area._parent===shot,"actual stock rocket for "+name);
        var box:Object=shot.area.getBounds(world);
        check(isFinite(box.xMin+box.xMax+shot.xmov+shot.ymov) && box.xMax>box.xMin && shot.damageManager!=null && shot.aabbCollider!=null,"rocket motion, hit area and damage lifecycle");
        shot._x=200;shot._y=180;
        observe(name=="RPG"?"rpg":"m3");
        record("LightGameplay "+name+" "+[props.子弹种类,props.子弹威力,props.伤害类型,props.flags,shot.xmov,shot.ymov,box.xMin,box.xMax,box.yMin,box.yMax,rng.captureState()].join("|"));
        shot.removeMovieClip();rng.restoreState(previous);
    }

    private static function examples():Void {
        EquipmentLightBridge.resetScene();
        var obj:Object={baseAsset:"透明子弹",子弹种类:"透明子弹",魔法伤害属性:"冷",声音:"冰冻",吸血:70,
                        lightBinding:"area.ice-stream",lightCastId:{},lightSourceSlot:0,lightFacing:1};
        var hit:Object={aabbCollider:{left:80,right:380,top:150,bottom:210}};
        EquipmentLightBridge.registerBullet(hit,obj,hero);observe("lady-right");
        obj.lightFacing=-1; EquipmentLightBridge.registerBullet(hit,obj,hero);observe("lady-left");
        delete obj.lightBinding;EquipmentLightBridge.resetScene();EquipmentLightBridge.registerBullet(hit,obj,hero);
        check(EquipmentLightBridge.payload()=="","transparent combat properties alone stay dark");
        var stage:Array=["加强电球","量子爆弹"];var boundary:Array=[7,33];
        for (var i:Number=0; i<stage.length; i++) {
            EquipmentLightBridge.resetScene();
            var mc:MovieClip=world.效果.attachMovie(stage[i],"stage"+i,10+i);
            check(mc._totalframes>=boundary[i],"real staged artwork "+stage[i]);
            mc._x=250;mc._y=200;mc.gotoAndStop(boundary[i]-1);
            EquipmentLightBridge.registerEffect(mc,stage[i]);observe("stage"+i+"-before");
            mc.gotoAndStop(boundary[i]);observe("stage"+i+"-at");
            mc.removeMovieClip();
        }
        EquipmentLightBridge.resetScene();
        var ordinary:MovieClip=world.效果.attachMovie("支援飞弹","ordinary",15);
        check(ordinary._parent===world.效果,"real ordinary projectile asset");
        ordinary._x=240;ordinary._y=160;
        EquipmentLightBridge.registerBullet(ordinary,{baseAsset:"支援飞弹"},hero);observe("ordinary");
        ordinary.removeMovieClip();
        EquipmentLightBridge.resetScene();
        var action:Object={tier:1,frame:10};
        var business:Object=HuofengAction;
        business["tickNirvana"](null,hero,action);observe("huofeng");
        var bridge:Object=EquipmentLightBridge;var live:Object=bridge["projectiles"][0];
        var duration:Number=live.expireTick-live.birthTick;
        record("LightLease duration="+duration);
        CombatFxBridge.flush();
        var atBirth:String=EquipmentLightBridge.payload();
        check(CombatFxBridge.lightTick()==live.birthTick && atBirth!="","birth is age zero in the actual F8 clock");
        _root.暂停=true;
        for (var k:Number=0;k<9;k++) { _root.帧计时器.当前帧数++; CombatFxBridge.flush(); }
        check(CombatFxBridge.lightTick()==live.birthTick && EquipmentLightBridge.payload()==atBirth,"paused F8 clock freezes the envelope");
        _root.暂停=false;
        business["tickNirvana"](null,hero,action); CombatFxBridge.flush();
        check(bridge["projectiles"].length==1 && bridge["projectiles"][0]===live,"the same action renews its slot");
        action.cancelled=true;check(EquipmentLightBridge.payload()=="","cancelled action clears its pulse");
        var death:Object={}; EquipmentLightBridge.emitPulseAt("__huofeng_nirvana",200,180,hero,1,1,death,0);
        for (k=0;k<duration;k++) CombatFxBridge.flush();
        check(EquipmentLightBridge.payload()!="","one-shot event keeps its complete authored tail");
        CombatFxBridge.flush(); check(EquipmentLightBridge.payload()=="","one-shot tail expires on its game tick");
    }

    private static function saturation():Void {
        EquipmentLightBridge.resetScene();
        var api:Object=EquipmentLightBridge;var actors:Array=[];var i:Number;
        for (i=0;i<48;i++) {
            var clip:MovieClip=world.createEmptyMovieClip("cap"+i,100+i);
            clip._x=120+i;clip._y=100;actors.push(clip);
            EquipmentLightBridge.registerBullet(clip,{baseAsset:"火球"},hero);
        }
        EquipmentLightBridge.payload();
        var entries:Array=api["projectiles"];
        var held:Object=entries[47];var old:Array=[held.id,held.x,held.y,held.energy,held.expireTick];
        EquipmentLightBridge.emitPulseAt("__huofeng_nirvana",430,260,null,1,1,{},0);
        EquipmentLightBridge.payload();
        check(entries.length==48 && held===entries[47] && old.join(",")==[held.id,held.x,held.y,held.energy,held.expireTick].join(","),"rejected pulse cannot move, recolor or extend the last protected light");
        for(i=0;i<actors.length;i++) actors[i].removeMovieClip();
    }
    private static function beginTimeline():Void {
        emitted=[]; timelineStep=0; timelineStarted=getTimer();
        previousInitialize=_root.子弹属性初始化;
        previousShoot=_root.子弹区域shoot传递;
        _root.子弹属性初始化=function():Object { return {}; };
        _root.子弹区域shoot传递=function(props:Object):Void {
            if (props.lightBinding!=undefined) DynamicLightProfilesTest.emitted.push(props);
        };
        lady=world.效果.attachMovie("敌人-Lady","__timelineLady",35);
        lady.version=1; lady.方向="左"; lady.空手攻击力=200; lady._x=120; lady._y=270;
        lady.gotoAndStop("近战");
        ticker.onEnterFrame=function():Void { DynamicLightProfilesTest.sampleTimeline(); };
    }

    private static function sampleTimeline():Void {
        if (getTimer()-timelineStarted>8000) {
            check(false,"published Lady timeline step="+timelineStep+" actor="+lady._currentframe+" skill="+skill._currentframe+" shots="+emitted.length);
            endTimeline(); return;
        }
        if (timelineStep==0) {
            for (var key:String in lady) {
                var child:MovieClip=lady[key];
                if (typeof(child)=="movieclip" && child._parent===lady && child._totalframes>614) {
                    skill=child; break;
                }
            }
            if (!skill) return;
            skill.gotoAndStop(254);
            timelineStep=1; return;
        }
        if (timelineStep==1 && skill.__projectileLightCast.firstFrame==254) {
            emitted=[]; skill.gotoAndStop(269); timelineStep=2; return;
        }
        if ((timelineStep==2 || timelineStep==5) && emitted.length>0) {
            var ice:Object=emitted[0];
            var iceBounds:Object=ice.区域定位area.getBounds(world);
            check(ice.子弹种类=="透明子弹" && ice.lightBinding=="area.ice-stream" && ice.lightFacing==-1 &&
                  ice.lightSourceSlot==0 && ice.lightCastId===skill.__projectileLightCast && iceBounds.xMax>iceBounds.xMin,
                  "published ice timeline supplies real collision bounds, actor facing and cast identity");
            EquipmentLightBridge.resetScene();
            EquipmentLightBridge.registerBullet({aabbCollider:{left:iceBounds.xMin,right:iceBounds.xMax,top:iceBounds.yMin,bottom:iceBounds.yMax}},ice,lady);
            var iceWire:String=EquipmentLightBridge.payload();
            var span:Number=iceBounds.xMax-iceBounds.xMin;
            var broad:Boolean=timelineStep==5;
            check(iceWire.split(";").length==(broad ? 3 : 2) && (broad ? span>=180 : span<180),"published ice stroke uses its actual collider width");
            record("LightTimeline ice frame="+skill._currentframe+" slot="+ice.lightSourceSlot+" facing="+ice.lightFacing+" span="+span+" "+iceWire);
            if (!broad) { emitted=[]; skill.gotoAndStop(287); timelineStep=5; return; }
            skill.gotoAndStop(603); timelineStep=3; return;
        }
        if (timelineStep==3 && skill.__projectileLightCast.firstFrame==603) {
            emitted=[]; skill.gotoAndStop(615); timelineStep=4; return;
        }
        if (timelineStep==4 && emitted.length>=2) {
            var a:Object=emitted[0],b:Object=emitted[1];
            var same:Boolean=a.lightCastId===skill.__projectileLightCast && b.lightCastId===a.lightCastId;
            var slots:Array=[a.lightSourceSlot,b.lightSourceSlot]; slots.sort(Array.NUMERIC);
            check(a.lightBinding=="area.blade-dance" && b.lightBinding==a.lightBinding && same &&
                  slots.join(",")=="1228,1229","published Lady frame 615 emits the two authored blade slots");
            record("LightTimeline blades frame="+skill._currentframe+" slots="+slots.join(","));
            endTimeline();
        }
    }

    private static function endTimeline():Void {
        delete ticker.onEnterFrame;
        _root.子弹属性初始化=previousInitialize;
        _root.子弹区域shoot传递=previousShoot;
        lady.removeMovieClip();
        finish();
    }

    private static function record(line:String):Void {
        observations.push(line);
        trace(line);
    }
    private static function finish():Void {
        record("DynamicLightProfilesTest Tests Failed: "+failed);
        // Release Flash Player has no debug trace. Write this fixture's receipt only in its isolated test root.
        if (_root._url.indexOf("/light-author-proof/") >= 0) {
            var receipt:SharedObject=SharedObject.getLocal("cf7-light-author-"+runId);
            receipt.data.report="CF7-LIGHT-BEGIN\n"+System.capabilities.version+"\n"+observations.join("\n")+"\nCF7-LIGHT-END";
            receipt.flush();
        }
        trace("FocusedTestRunId dynamic-light-profiles Complete: "+runId);
        assetLoader.removeListener(assetListener); xml.onLoad=null;CombatFxBridge.disconnect();ticker.removeMovieClip();world.removeMovieClip();
        _root.gameworld=previousWorld;_root.帧计时器=previousClock;_root.暂停=previousPause;_root.控制目标=previousHero;
    }
}
