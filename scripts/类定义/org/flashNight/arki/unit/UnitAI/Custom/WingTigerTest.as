import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.arki.component.StatHandler.ImpactHandler;
import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.KillEventComponent;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DeathEventComponent;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.unit.UnitAI.Custom.WingTigerController;
import flash.display.BitmapData;
import flash.geom.Matrix;

/** 真实 XML、发布的 things5 SWF 和生产受击/死亡消费者。
 * 单位属性初始化、地图移动与经验/掉落使用隔离夹具；不启动存档或正式关卡。
 */
class org.flashNight.arki.unit.UnitAI.Custom.WingTigerTest {
    private static var passed:Number,failed:Number,age:Number,loaded:Boolean,serial:Number,late:Number,rewards:Number;
    private static var world:MovieClip,driver:MovieClip,bullet:MovieClip,red:MovieClip,blue:MovieClip,entry:MovieClip,retreat:MovieClip,npc:MovieClip;
    private static var loader:MovieClipLoader,listener:Object,props:Object;
    private static function check(ok:Boolean,name:String):Void {
        if(ok) passed++;else {failed++;trace("[TEST_FAIL] WingTigerTest: "+name);}
    }
    public static function runAllTests():Void {
        passed=failed=age=serial=late=rewards=0;loaded=false;
        _root.暂停=false;_root.重力加速度=1;_root.控制目标="__no_player";
        _root.帧计时器={当前帧数:0,帧率:30};
        _root.是否阴影=false;_root.血腥开关=true;
        LinearCongruentialEngine.getInstance().setSeed(123456);
        _root.初始化思考标签=function(c:MovieClip):Void {c.stop();c._visible=false;};
        _root.效果=function():Void {};_root.播放音效=function():Void {};
        _root.soundEffectManager={playSound:function():Void {}};
        _root.服务器={发布服务器消息:function():Void {}};
        _root.add2map=function():Void {WingTigerTest.check(false,"retreat must not paste a corpse");};
        _root.子弹属性初始化=function(c:MovieClip):Object {return {};};
        _root.子弹区域shoot传递=function():Void {};_root.子弹区域shoot=function():Void {};
        _root.初始化敌人模板=function():Void {WingTigerTest.initializeActor(this);};
        driver=_root.createEmptyMovieClip("__wingTigerDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {WingTigerTest.tick();};
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {
            WingTigerTest.check(ok,"real enemy XML loads");
            if(!ok){WingTigerTest.finish();return;}
            var data:Object=XMLParser.parseXMLNode(this.firstChild);
            WingTigerTest.props=data[WingTigerController.KIND];
            WingTigerTest.check(WingTigerTest.props.重量==40 && WingTigerTest.props.韧性系数==.8,"canonical agile properties");
            WingTigerTest.loadArt();
        };
        xml.load("../data/enemy_properties/原版敌人 2013-2016.xml");
    }
    private static function loadArt():Void {
        world=_root.createEmptyMovieClip("__wingTigerLibrary",_root.getNextHighestDepth());
        loader=new MovieClipLoader();listener={};
        listener.onLoadInit=function(mc:MovieClip):Void {
            mc.stop();var children:Array=[];
            for(var key:String in mc) {
                var child=mc[key];if(typeof child=="movieclip" && child._parent===mc) children.push(child);
            }
            for(var i:Number=0;i<children.length;i++) {children[i].swapDepths(mc.getNextHighestDepth());children[i].removeMovieClip();}
            _root.gameworld=mc;mc.dispatcher=new EventDispatcher();
            var source:MovieClip=mc.createEmptyMovieClip("fixtureSource",mc.getNextHighestDepth());
            source.僵尸型敌人场上实际人数=4;source.僵尸型敌人总个数=4;
            WingTigerTest.loaded=true;WingTigerTest.age=0;
        };
        listener.onLoadError=function():Void {WingTigerTest.check(false,"native things5 load");WingTigerTest.finish();};
        loader.addListener(listener);loader.loadClip("../flashswf/arts/things5.swf",world);
    }
    private static function initializeActor(u:MovieClip):Void {
        u.hp=u.hp满血值=20000;u.防御力=800;u.躲闪率=3;
        u.韧性系数=.8;u.重量=40;u.起跳速度=-10;
        u.Z轴坐标=u._y;u.攻击模式="空手";u.浮空=false;u.倒地=false;u.硬直中=false;
        u.垂直速度=0;u.免疫击退=false;u.无敌=false;u.已加经验值=false;u.产生源="fixtureSource";
        u.空手攻击力=120;u.x轴攻击范围=100;u.y轴攻击范围=15;
        u.攻击目标="无";u.myxscale=100;u.remainingImpactForce=0;
        u.aabbCollider={updateFromUnitArea:function():Void {}};
        u.area._visible=false;u.人物文字信息._visible=false;
        u.dispatcher=new EventDispatcher();
        u.状态改变=_root.敌人函数.状态改变;u.动画完毕=_root.敌人函数.动画完毕;
        u.击飞浮空=_root.敌人函数.击飞浮空;u.击飞倒地=_root.敌人函数.击飞倒地;
        u.死亡检测=_root.敌人函数.死亡检测;
        u.计算经验值=function():Void {WingTigerTest.rewards++;this.已加经验值=true;};
        u.移动=function(d:String,v:Number):Void {
            if(d=="左")this._x-=v;else if(d=="右")this._x+=v;
            else if(d=="上")this.Z轴坐标-=v;else if(d=="下")this.Z轴坐标+=v;
        };
        u.移动钝感硬直=function(t:Number):Void {};
        u.被击移动=_root.敌人函数.被击移动;
        u.方向改变=function(d:String):Void {this.方向=d;this._xscale=d=="左"?-100:100;};
        u.行走=function():Void {};u.击倒呐喊=function():Void {};u.攻击呐喊=function():Void {};
        u.dispatcher.subscribe("death",DeathEventComponent.onDeath,u);
        ImpactHandler.refreshImpactDerived(u);
        u.状态=u.登场动画?"登场":"空手站立";
        u.gotoAndStop(u.状态);
    }
    private static function fake(side:Boolean,tune:Object):MovieClip {
        var u:MovieClip=world.createEmptyMovieClip("logic"+(++serial),world.getNextHighestDepth());
        u.兵种=WingTigerController.KIND;u.是否为敌人=side;u._y=300;
        initializeActor(u);
        u.翅虎参数=tune;
        u.createEmptyMovieClip("man",0);
        u.状态改变=function(s:String):Void {this.状态=s;};
        WingTigerController.initialize(u);delete u.__wingTiger.thinker.onEnterFrame;
        return u;
    }
    private static function step(u:MovieClip,n:Number):Void {
        for(var i:Number=0;i<n;i++) {_root.帧计时器.当前帧数++;WingTigerController.tick(u);}
    }
    private static function logicTests():Void {
        var p:Object=WingTigerController.defaults();
        check(p.controlFrames==48 && p.cooldownFrames==240,"1.6 second recovery and 8 second cooldown");
        var tiny:MovieClip=fake(false,{guardFrames:.5,controlFrames:.5});
        check(tiny.__wingTiger.tune.guardFrames==1 && tiny.__wingTiger.tune.controlFrames==1,"fractional frame overrides cannot produce a permanent zero-frame guard");
        var old:MovieClip=fake(false);var cleanup:Function=old.__wingTiger.unloadCallback;
        old.removeMovieClip();serial--;
        var fresh:MovieClip=fake(false);cleanup.call(fresh);
        check(!fresh.__wingTiger.finished,"late old unload cannot dispose a replacement at the same native path");
        bullet=world.createEmptyMovieClip("fixtureBullet",world.getNextHighestDepth());
        bullet.水平击退速度=20;bullet.垂直击退速度=0;bullet.击倒率=0;
        for(var side:Number=0;side<2;side++) {
            var u:MovieClip=fake(side==1);u.状态="击倒";u.浮空=true;u.硬直中=true;u._y=180;
            u.flyID=EnhancedCooldownWheel.I().addTask(function():Void {WingTigerTest.late++;},1000,1);
            u.stiffID=EnhancedCooldownWheel.I().addTask(function():Void {WingTigerTest.late++;},1000,1);
            u.knockStiffID=EnhancedCooldownWheel.I().addTask(function():Void {WingTigerTest.late++;},1000,1);
            for(var i:Number=0;i<47;i++) {
                u.hp--;ImpactStateHandler.handleImpactState(u,bullet,null,"左",true);step(u,1);
            }
            check(u.__wingTiger.recoveries==0,"continuous real airborne impacts retain delay side "+side);
            var hp:Number=u.hp;step(u,1);
            check(u.__wingTiger.recoveries==1 && u.状态=="近战","both factions reliably break control side "+side);
            check(u.hp==hp && !u.无敌,"recovery cannot heal or grant invulnerability side "+side);
            check(!u.浮空 && !u.倒地 && !u.硬直中 && u._y==u.Z轴坐标 && u.垂直速度==0,"physics handed back side "+side);
            check(u.flyID==null && u.stiffID==null && u.knockStiffID==null && u.onEnterFrame==undefined,"old control callbacks cancelled side "+side);
            check(u.近战招式=="a1" && u.免疫击退 && u.man.刚体标签,"no-target fallback and guarded entry side "+side);
            u.hp-=100;ImpactStateHandler.handleImpactState(u,bullet,null,"左",true);
            check(u.状态=="近战" && u.hp==hp-100,"guard allows damage while stopping another knockdown side "+side);
            step(u,8);check(!u.免疫击退 && !u.man.刚体标签,"temporary guard released side "+side);
            u.状态="倒地";step(u,231);check(u.__wingTiger.recoveries==1,"no recovery spam before cooldown side "+side);
            step(u,1);check(u.__wingTiger.recoveries==2,"persistent control gets a second chance after cooldown side "+side);
            u._visible=false;delete u.__wingTiger.thinker.onEnterFrame;
        }
        EnhancedCooldownWheel.I().tick();
        check(late==0,"cancelled impact tasks do not reapply the old motion");
        var v:MovieClip=fake(false);v.状态="被击";step(v,47);
        _root.暂停=true;step(v,80);check(v.__wingTiger.controlled==47,"pause does not consume recovery delay");
        _root.暂停=false;step(v,1);check(v.__wingTiger.recoveries==1,"recovery resumes on the next active frame");
        v=fake(false);v.状态="击倒";step(v,30);v.状态="空手站立";step(v,1);v.状态="被击";step(v,18);
        check(v.__wingTiger.recoveries==1,"one-frame gaps cannot restart an infinite-control timer");
        v=fake(false);v.状态="击倒";step(v,30);v.状态="空手站立";step(v,8);
        check(v.__wingTiger.controlled==0,"real free action resets the control episode");
        v.状态="击倒";v._封印冻结=true;step(v,80);check(v.__wingTiger.recoveries==0,"does not break seal control");
        v._封印冻结=false;v.状态="被投";step(v,80);check(v.__wingTiger.recoveries==0,"does not escape a scripted throw");
        v.状态="击倒";v.hp=0;step(v,80);check(v.hp==0 && v.__wingTiger.recoveries==0,"lethal damage wins over recovery");
        v=fake(false);v.状态="击倒";step(v,48);v.位移锁向截止帧=987654;
        v.状态="空手站立";step(v,1);check(v.位移锁向截止帧==987654,"does not clear another owner facing window");
        var seen:Object={};var target:MovieClip=world.createEmptyMovieClip("liveTarget",world.getNextHighestDepth());
        target.hp=100;target._x=50;
        for(i=0;i<12;i++) {
            v=fake(false);v.攻击目标=target._name;v._x=150;v.状态="击倒";step(v,48);
            seen[v.近战招式]=true;check(v.近战招式=="a1" || v.近战招式=="a2","random recovery uses only mobile moves "+i);
            check(v.方向=="左","recovery faces its own live target "+i);
            v._visible=false;delete v.__wingTiger.thinker.onEnterFrame;
        }
        check(seen.a1 && seen.a2,"seeded run exercises both mobile moves");
    }
    private static function native(side:Boolean,name:String,params:Object):MovieClip {
        params.兵种=WingTigerController.KIND;params.是否为敌人=side;params._x=side?650:300;params._y=430;
        return world.attachMovie(WingTigerController.KIND,name,world.getNextHighestDepth(),params);
    }
    private static function capture(label:String,u:MovieClip):Void {
        var image:BitmapData=new BitmapData(340,280,true,0);
        var matrix:Matrix=new Matrix();matrix.translate(170,245);image.draw(u,matrix);
        trace("WingTigerCapture "+label+" Start 340 280");
        for(var y:Number=0;y<280;y++) {
            var row:String="",last:Number=image.getPixel32(0,y),count:Number=1;
            for(var x:Number=1;x<340;x++) {
                var pixel:Number=image.getPixel32(x,y);
                if(pixel==last)count++;
                else {row+=last.toString(16)+":"+count+";";last=pixel;count=1;}
            }
            row+=last.toString(16)+":"+count+";";
            trace("WingTigerCapture "+label+" Row "+y+" "+row);
        }
        trace("WingTigerCapture "+label+" Complete");image.dispose();
    }
    private static function tick():Void {
        _root.帧计时器.当前帧数++;EnhancedCooldownWheel.I().tick();
        if(!loaded) {if(++age>240){check(false,"loading watchdog");finish();}return;}
        age++;
        if(age==2) {
            logicTests();
            blue=native(false,"blue",{});red=native(true,"red",{});
            entry=native(true,"entry",{登场动画:"a0",死亡动画:"a1"});
            retreat=native(true,"retreat",{死亡动画:"a1"});
            npc=native(false,"npc",{NPC:true});
        }
        if(age==5) {
            check(blue.__wingTiger && red.__wingTiger,"actual native blue and red actors initialized");
            check(npc.__wingTiger==undefined,"NPC display excluded");
            check(entry.状态=="登场" && entry.man.body && entry.man.smoke && entry.无敌,"stage opt-in native entry composition");
            blue.状态改变("击倒");blue.硬直中=true;blue.man.stop();
            red.状态改变("击倒");red.硬直中=true;red.man.stop();
            retreat.hp=0;KillEventComponent.onKill(retreat);
            check(retreat.状态=="烟雾退场" && retreat.__wingTiger.phase=="retreat","production kill routes to retreat");
            check(retreat.man && retreat.__wingTigerThink._parent==undefined,"death cleanup removes old direct thinker");
        }
        if(age==8) {
            check(retreat.man && retreat.__wingTiger.thinker && retreat.__wingTiger.thinker._parent===retreat.man,"retreat observer survives under reserved man");
            capture("entry-early",entry);
        }
        if(age==15) {capture("entry-reveal",entry);capture("retreat",retreat);}
        if(age==30) {
            check(entry.状态=="空手站立" && !entry.无敌,"entry completes and returns vulnerability");
            check(entry.__wingTiger.thinker._parent===entry,"entry observer survives the destroyed animation context");
            check(retreat._parent==undefined && rewards==1,"retreat completes ordinary reward and unload once");
            check(world.fixtureSource.僵尸型敌人场上实际人数==3 && world.fixtureSource.僵尸型敌人总个数==3,"retreat releases ordinary wave counts once");
            blue.__wingTiger.controlled=47;red.__wingTiger.controlled=47;
        }
        if(age==33) {
            check(blue.__wingTiger.recoveries==1 && red.__wingTiger.recoveries==1,"native recovery works in both factions");
            check(blue.状态=="近战" && blue.man && blue.刚体,"actual attack container acquires native armor");
            check(blue.__wingTigerSmoke1 && blue.__wingTigerSmoke1._totalframes==26,"native visual-only smoke linkage resolves");
            check(blue.hp==20000 && !blue.无敌,"native recovery preserves HP and vulnerability");
            capture("recovery",blue);
            blue.hp=0;KillEventComponent.onKill(blue);
            check(blue.状态=="血腥死" && blue.__wingTiger.phase=="active","non-stage lethal damage keeps native death");
        }
        if(age==44) {
            check(red.__wingTiger.guard==0 && !red.免疫击退,"native guard expires");
            check(rewards==1,"retreat reward cannot replay on later frames");
            check(entry.__wingTiger.recoveries==0,"entry smoke does not count as combat recovery");
            trace("WingTigerTest Native Transitions Complete: 1");finish();
        }
    }
    private static function finish():Void {
        delete driver.onEnterFrame;
        EnhancedCooldownWheel.I().deactivateAll();
        trace("WingTigerTest Tests Passed: "+passed);
        trace("WingTigerTest Tests Failed: "+failed);
        _root.wingTigerTestComplete();
    }
}
