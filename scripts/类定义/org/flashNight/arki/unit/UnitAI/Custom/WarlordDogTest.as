import org.flashNight.arki.unit.UnitAI.Custom.WarlordDogController;
import org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.component.Shield.Shield;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.UnitUpdateWheel;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.spatial.move.Mover;
import flash.display.BitmapData;
import flash.geom.Matrix;

/** Native actor plus real shield/Buff/target caches. No player save or rewards. */
class org.flashNight.arki.unit.UnitAI.Custom.WarlordDogTest {
    private static var passed:Number,failed:Number,age:Number,phase:Number,pose:Number;
    private static var driver:MovieClip,world:MovieClip,dog:MovieClip,robot:MovieClip,ally:MovieClip,human:MovieClip;
    private static var player:MovieClip,noncombat:MovieClip;
    private static var calls:Array;
    private static var productionShoot:Function;
    private static var nativeRayCreates:Number;
    private static var finished:Boolean;
    private static var poses:Array = ["空手站立","空手行走","空手跑","空手攻击","被击","击倒","倒地","被投","血腥死"];
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++; else {failed++;trace("WarlordDogTest FAIL: "+label);}
    }
    public static function runAllTests():Void {
        passed=0;failed=0;age=0;phase=0;pose=0;finished=false;calls=[];
        _root.暂停=false;_root.是否阴影=true;_root.血腥开关=true;
        _root.重力加速度=1;_root.最大等级=60;_root.难度等级=1;_root.控制目标="fixturePlayer";
        _root.Xmin=-1000;_root.Xmax=1000;_root.Ymin=-500;_root.Ymax=1000;
        _root.duplicateOf=ObjectUtil.clone;
        _root.装备引用配置={配置装扮:function():MovieClip{return null;}};
        _root.帧计时器={当前帧数:0,帧率:30,unitUpdateWheel:UnitUpdateWheel.I(),
            添加冷却任务:function():Void{},移除任务:function():Void{},添加任务:function():Number{return 0;}};
        _root.collisionLayer={hitTest:function():Boolean{return false;}};
        _root.对象浅拷贝=function(o:Object):Object {var r:Object={};for(var k:String in o)r[k]=o[k];return r;};
        _root.播放音效=function():Void {};
        delete _root.ServerManagerFrameClip.onEnterFrame;
        productionShoot=_root.子弹区域shoot传递;
        _root.子弹区域shoot传递=function(p:Object):Object {WarlordDogTest.calls.push(p);return {};};
        driver=_root.createEmptyMovieClip("__ironGuardTest",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {
            if(++WarlordDogTest.age>300){WarlordDogTest.check(false,"loading watchdog");WarlordDogTest.finish();}
        };
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {
            WarlordDogTest.check(ok,"load real military enemy XML");
            if(!ok){WarlordDogTest.finish();return;}
            _root.敌人属性表=XMLParser.parseXMLNode(this.firstChild);
            WarlordDogTest.setup();
        };
        xml.load("../data/enemy_properties/军阀新人物.xml");
    }
    private static function setup():Void {
        world=_root.createEmptyMovieClip("__ironGuardWorld",_root.getNextHighestDepth());
        _root.gameworld=world;world.dispatcher=new EventDispatcher();world._x=260;world._y=250;
        DepthManager.instance=new DepthManager(world,100,1048575,4);DepthManager.instance.calibrate(-500,1000);
        org.flashNight.arki.component.Collider.ColliderFactoryRegistry.init();
        StaticInitializer.factory=new AABBColliderFactory(4);
        FactionManager.initialize();TargetCacheManager.initialize();Mover.init();
        robot=makeTarget("robot",150,false);robot.魔法抗性={机械:0,电:-100};
        human=makeTarget("human",240,false);human.魔法抗性={装甲:25};
        ally=makeTarget("rifleman",-80,true);ally.攻击目标="human";
        player=makeTarget("fixturePlayer",-240,true);player.攻击目标="human";
        noncombat=makeTarget("noncombat",-320,true);noncombat.unitAIType="None";noncombat.攻击目标="human";
        spawn();age=0;
        driver.onEnterFrame=function():Void {
            try{WarlordDogTest.advance();}
            catch(error){WarlordDogTest.check(false,"exception: "+error);WarlordDogTest.finish();}
        };
    }
    private static function makeTarget(name:String,x:Number,faction:Boolean):MovieClip {
        var t:MovieClip=world.createEmptyMovieClip(name,world.getNextHighestDepth());
        t._x=x;t._y=0;t.Z轴坐标=0;t.hp=10000;t.hp满血值=10000;t.等级=20;t.重量=60;
        t.是否为敌人=faction;t.version=100;t.兵种="fixture";t.躲闪率=30;t.防御力=100;
        t.unitAIType="StandardAI";t.dispatcher=new EventDispatcher();t.防止无限飞=false;
        t.man={无敌标签:false};t.damageTakenMultiplier=1;t.ti61CrumbleTakenMultiplier=1;
        t.shield=AdaptiveShield.acquireDormantFromPool(name+"_fixture_shield");t.shield.setOwner(t);
        t.懒闪避=0;t.魔法抗性={基础:0,电:0};
        var area:MovieClip=t.createEmptyMovieClip("area",0);area.beginFill(0x335566,100);
        area.moveTo(-15,-120);area.lineTo(15,-120);area.lineTo(15,0);area.lineTo(-15,0);area.endFill();area._visible=false;
        t.aabbCollider=new AABBCollider(0,0,0,0);t.aabbCollider.updateFromUnitArea(t);
        TargetCacheManager.addUnit(t);return t;
    }
    private static function spawn():Void {
        dog=world.attachMovie(WarlordDogController.KIND,"ironGuard",world.getNextHighestDepth(),
            {_x:0,_y:0,兵种:WarlordDogController.KIND,等级:20,是否为敌人:true,名字:"军阀铁卫犬",身高:175});
        check(dog!=undefined,"native dog linkage attaches");
        if(!dog)finish();
    }
    private static function advance():Void {
        if(finished)return;
        _root.帧计时器.当前帧数++;
        age++;
        if(phase==0 && age>=4){
            check(dog.__unitInitializedVersion==dog.version,"production initializer completed");
            check(dog.__ironGuard!=undefined,"unit-local controller initialized");
            check(dog.man.part230!=undefined && dog.man.part235!=undefined,"native head and jaw are named live clips");
            check(dog.man.part215!=undefined,"live mouth component exists");
            check(dog.man.part200!=undefined,"energy collar exists");
            mechanism();
            dog.removeMovieClip();spawn();phase=1;age=0;return;
        }
        if(phase==1 && age>=4){
            captureDog("charged");
            nativeRayCreates=0;
            _root.子弹区域shoot传递=function(props:Object):Object {
                var result:Object=WarlordDogTest.productionShoot(props);
                if(result && props.子弹种类=="磁暴射线")WarlordDogTest.nativeRayCreates++;
                return result;
            };
            var mouth:Object={x:320,y:107};dog.man.part230.localToGlobal(mouth);world.globalToLocal(mouth);
            robot._x=mouth.x;robot.hp=10000;robot.aabbCollider.updateFromUnitArea(robot);
            dog.命中率=999999;dog.状态="空手攻击";dog.gotoAndStop("空手攻击");
            phase=3;age=0;return;
        }
        if(phase==3){
            BulletQueueProcessor.processQueue();
            if(age<28)return;
            check(dog.__ironGuard.bites>0,"real attack timeline calls bite emitter");
            check(robot.hp<10000,"real melee geometry settles actual damage");
            check(nativeRayCreates==1 && dog.__ironGuard.discharges==1,"real collision creates exactly one electrical ray");
            check(!dog.__ironGuard.ready,"real attack consumes the energy shield");
            trace("WarlordDogTest Collision: hp="+robot.hp+" emitters="+dog.__ironGuard.bites+" rays="+nativeRayCreates);
            captureDog("spent");
            _root.子弹区域shoot传递=function(props:Object):Object{return {};};
            _root.暂停=true;dog.gotoAndStop(poses[pose]);phase=2;age=0;return;
        }
        if(phase==2 && age>=4){
            if(pose<8) {
                check(!dog.__ironGuard.ready && dog.man.part200._currentframe==2,
                    "spent indicator survives native pose rebind "+poses[pose]);
            }
            var bitmap:BitmapData=new BitmapData(256,256,true,0);
            bitmap.draw(dog,new Matrix(1,0,0,1,128,120));
            var bounds:Object=bitmap.getColorBoundsRect(0xFF000000,0,false);
            check(bounds.width>15 && bounds.height>10,"native visible pose "+poses[pose]);
            captureDog("pose-"+pose);
            bitmap.dispose();
            trace("WarlordDogTest Pose: "+poses[pose]+" bounds="+bounds.width+"x"+bounds.height);
            pose++;
            if(pose==poses.length){finish();return;}
            dog.gotoAndStop(poses[pose]);age=0;
        }
    }
    private static function mechanism():Void {
        var c:Object=dog.__ironGuard;
        if(!c){check(false,"missing context prevents mechanism tests");return;}
        trace("WarlordDogTest Stats: hp="+dog.hp+" max="+dog.hp满血值+" attack="+dog.空手攻击力+" defense="+dog.防御力);
        check(dog.hp满血值==847 && dog.空手攻击力==116 && dog.防御力==344,"own level uses real formula-derived profile");
        check(c.ready && c.layer.getCapacity()==c.layer.getMaxCapacity(),"spawn has full energy shield");
        check(dog.韧性系数==dog.基础韧性系数*5,"shield applies finite toughness bonus");
        check(dog.man.part200._currentframe==1,"charged indicator is lit");
        var owned:Object=c.layer;
        var external:Shield=Shield.createRechargeable(70,10,0,0,"other-system");
        c.container.addShield(external,true);
        WarlordDogController.command(c,robot);
        check(ally.攻击目标=="robot","focus changes allied target");
        check(player.攻击目标=="human","focus excludes the controlled player even with AI metadata");
        check(noncombat.攻击目标=="human","focus excludes noncombat AI");
        check(robot.攻击目标==undefined,"focus does not taunt the hostile target");
        var before:Number=c.commands;
        dog.攻击目标="robot";_root.帧计时器.当前帧数++;
        WarlordDogController.tick(c);
        check(c.commands==before,"unchanged target does not continuously command");
        robot.version++;_root.帧计时器.当前帧数=c.focusAt;WarlordDogController.tick(c);
        check(c.commands==before+1,"reused target path with a new unit version receives a fresh command");
        var original:Number=owned.getCapacity();
        owned.consumeCapacity(original-1);
        check(c.ready && owned.getCapacity()==1,"partially depleted shield retains discharge permission");
        calls=[];WarlordDogController.onBiteHit(c,{hitTarget:human});
        check(calls.length==0 && c.ready,"armor-only human does not discharge");
        WarlordDogController.onBiteHit(c,{hitTarget:robot});
        check(calls.length==1 && calls[0].子弹种类=="磁暴射线","mechanical zero entry triggers single Tesla ray");
        check(calls[0].伤害类型=="魔法" && calls[0].魔法伤害属性=="电","Tesla explicitly uses electrical damage");
        check(calls[0].lockonTarget===robot && calls[0].击中时触发函数==undefined,"ray locks original victim without inheriting callback");
        check(!c.ready && !c.layer && dog.man.part200._currentframe==2,"discharge synchronously removes shield and lamp");
        check(dog.韧性系数==dog.基础韧性系数,"discharge synchronously removes toughness");
        check(c.container.getShieldById(external.getId())===external && external.getCapacity()==70,"other shield layer is preserved");
        WarlordDogController.onBiteHit(c,{hitTarget:robot});
        check(calls.length==1,"repeated hit cannot discharge twice");
        var deadline:Number=c.readyAt;
        _root.帧计时器.当前帧数=deadline-2;dog.hp-=1;WarlordDogController.tick(c);
        check(!c.ready && c.readyAt==deadline,"damage during waiting does not reset recharge deadline");
        check(c.container.getShieldById(owned.getId())==undefined,"waiting exposes no partial owned shield");
        dog.攻击目标="human";_root.帧计时器.当前帧数++;WarlordDogController.tick(c);
        check(ally.攻击目标=="human","focus remains available while energy is empty");
        _root.帧计时器.当前帧数=deadline;WarlordDogController.tick(c);
        check(c.ready && c.layer.getCapacity()==c.layer.getMaxCapacity(),"complete wait restores one full shield");
        check(dog.man.part200._currentframe==1 && dog.韧性系数>dog.基础韧性系数,"recharge restores lamp and toughness together");
        c.layer.consumeCapacity(c.layer.getMaxCapacity());
        check(!c.ready && dog.韧性系数==dog.基础韧性系数,"physical shield break removes energy and toughness");
        _root.暂停=true;_root.帧计时器.当前帧数=c.readyAt;WarlordDogController.tick(c);
        check(!c.ready,"pause prevents recharge activation");
        _root.暂停=false;WarlordDogController.tick(c);
        check(!c.ready,"paused frames do not advance recharge");
        _root.帧计时器.当前帧数=c.readyAt;WarlordDogController.tick(c);
        check(c.ready,"remaining active frames complete recharge after resume");
        var realShoot:Function=_root.子弹区域shoot传递;
        _root.子弹区域shoot传递=function(p:Object):Object{return null;};
        WarlordDogController.onBiteHit(c,{hitTarget:robot});
        check(c.ready,"failed ray creation retains energy");
        _root.子弹区域shoot传递=realShoot;
        dog.hp=0;WarlordDogController.tick(c);
        check(c.disposed && !c.ready && c.readyAt==0,"death disposes recharge lifecycle");
        _root.帧计时器.当前帧数+=1000;WarlordDogController.tick(c);
        check(!c.ready && !c.layer,"dead dog cannot recharge");
    }
    private static function captureDog(id:String):Void {
        if(_root.ironGuardCapture!==true)return;
        dog.新版人物文字信息._visible=false;dog.人物文字信息._visible=false;dog.area._visible=false;
        var bitmap:BitmapData=new BitmapData(256,256,true,0);
        var m:Matrix=dog.transform.matrix.clone();m.tx=128;m.ty=128;
        bitmap.draw(dog,m,null,"normal",null,true);
        var output:String="[ASSET_BITMAP_BEGIN] iron-guard-"+id+" 256 256\n";
        var bounds:Object=bitmap.getColorBoundsRect(0xFFFFFFFF,0,false);
        for(var y:Number=bounds.y;y<bounds.y+bounds.height;y++){
            var row:String="",last:Number=0,count:Number=bounds.x;
            for(var x:Number=bounds.x;x<bounds.x+bounds.width;x++){
                var pixel:Number=bitmap.getPixel32(x,y);
                if(pixel==last)count++;
                else{if(count)row+=hex(last)+":"+count+",";last=pixel;count=1;}
            }
            if(last==0)count+=bitmap.width-(bounds.x+bounds.width);
            else{row+=hex(last)+":"+count+",";last=0;count=bitmap.width-(bounds.x+bounds.width);}
            row+=hex(last)+":"+count;
            output+="[ASSET_BITMAP_ROW] "+y+" "+row+"\n";
        }
        trace(output+"[ASSET_BITMAP_END] iron-guard-"+id);bitmap.dispose();
    }
    private static function hex(pixel:Number):String {
        var low:String=(pixel&65535).toString(16);while(length(low)<4)low="0"+low;
        return ((pixel>>>16)&65535).toString(16)+low;
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;_root.暂停=true;
        if(dog){dog.stop();dog.man.stop();WarlordDogController.dispose(dog.__ironGuard);}
        trace("WarlordDogTest Tests Passed: "+passed);
        trace("WarlordDogTest Tests Failed: "+failed);
        trace("WarlordDogTest Native Poses: "+pose);
        _root.warlordDogTestComplete();
    }
}
