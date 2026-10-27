import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Utils.ShootingAngleCalculator;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Loader.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.EventDispatcher;

/** Coverage regression: real five-piece lifecycle -> one WeaponSkill -> factory -> queue -> damage.
 * Sound, hit-number presentation, target cache and external damage noise are isolated.
 * The production implementation is exercised unchanged by this fixture; no inventory/save is opened.
 */
class org.flashNight.arki.bullet.BulletComponent.Chain.VerticalPierceCoverageTest {
    private static var passed:Number,failed:Number,index:Number,step:Number,frames:Number;
    private static var finished:Boolean,loadedWorld:Boolean;
    private static var library:MovieClip,driver:MovieClip,hero:MovieClip,enemy:MovieClip;
    private static var loader:MovieClipLoader,listener:Object,saved:Object;
    private static var items:Object,configs:Object,tasks:Array,cases:Array,current:Object;
    private static var cacheRow:Object,projectile:Object,precheck:Function,results:Object;
    private static var slots:Array=["头部装备","上装装备","下装装备","脚部装备","手部装备"];
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] "+label);}
    }
    private static function noop():Void {}
    private static function noise():Number{return 1;}
    private static function spread(span:Number):Number{return LinearCongruentialEngine.getInstance().randomOffset(span);}
    private static function noMap(x:Number,y:Number,precise:Boolean):Boolean{return false;}
    private static function enemies(unit:Object,interval:Number):Object{return cacheRow;}
    private static function shallow(source:Object):Object {var copy:Object={};for(var key:String in source)copy[key]=source[key];return copy;}
    private static function shape(parent:MovieClip,name:String,x:Number,y:Number,w:Number,h:Number):MovieClip {
        var mc:MovieClip=parent.createEmptyMovieClip(name,parent.getNextHighestDepth());
        mc.beginFill(0xffffff);mc.moveTo(x,y);mc.lineTo(x+w,y);mc.lineTo(x+w,y+h);mc.lineTo(x,y+h);mc.lineTo(x,y);mc.endFill();return mc;
    }
    public static function runAllTests():Void {
        passed=failed=index=step=frames=0;finished=loadedWorld=false;items={};configs={};tasks=[];
        results={};
        cases=[{label:"flat-far",distance:480,angle:0,count:12,level:13,spread:0},
            {label:"flat-near",distance:120,angle:0,count:12,level:13,spread:0},
            {label:"tilt1-far",distance:480,angle:1,count:12,level:13,spread:0},
            {label:"tilt1-near",distance:120,angle:1,count:12,level:13,spread:0},
            {label:"epsilon-plus",distance:480,angle:0,directAngle:0.001,count:12,level:13,spread:0},
            {label:"epsilon-minus",distance:480,angle:0,directAngle:-0.001,count:12,level:13,spread:0},
            {label:"left-flat",distance:480,angle:0,count:12,level:13,spread:0,left:true},
            {label:"left-epsilon-minus",distance:480,angle:0,directAngle:179.999,count:12,level:13,spread:0,left:true},
            {label:"left-epsilon-plus",distance:480,angle:0,directAngle:180.001,count:12,level:13,spread:0,left:true},
            {label:"flat-mc",distance:480,angle:0,count:12,level:13,spread:0,mc:true},
            {label:"left-mc",distance:480,angle:0,count:12,level:13,spread:0,mc:true,left:true},
            {label:"spread5-far",distance:480,angle:0,count:12,level:13},
            {label:"spread5-near",distance:120,angle:0,count:12,level:13},
            {label:"spread5-left",distance:480,angle:0,count:12,level:13,left:true},
            {label:"wide-target",distance:480,angle:0,count:12,level:13,spread:0,width:180},
            {label:"normal-chain-control",distance:480,angle:0,count:12,level:13,spread:0,kind:"纵向联弹-普通子弹",unaffected:true},
            {label:"single-pierce-control",distance:480,angle:0,count:1,level:13,spread:0,kind:"穿刺子弹",unaffected:true}];
        driver=_root.createEmptyMovieClip("__verticalDamageDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {if(++VerticalPierceCoverageTest.frames>240){VerticalPierceCoverageTest.check(false,"fixture load timeout");VerticalPierceCoverageTest.finish();}};
        loadDocument(0);
    }
    private static function loadDocument(which:Number):Void {
        var doc=new XML();doc.ignoreWhite=true;doc.probeIndex=which;
        doc.onLoad=function(ok:Boolean):Void {
            if(!ok){VerticalPierceCoverageTest.check(false,"XML load "+this.probeIndex);VerticalPierceCoverageTest.finish();return;}
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            if(this.probeIndex==0){
                var rows:Array=XMLParser.configureDataAsArray(parsed.set);
                for(var i:Number=0;i<rows.length;i++)VerticalPierceCoverageTest.configs[rows[i].id]=rows[i];
            }else if(this.probeIndex==1){
                var rows:Array=XMLParser.configureDataAsArray(parsed.item);
                for(var i:Number=0;i<rows.length;i++)if(rows[i].setId==UnifiedType61Runtime.SET_ID)VerticalPierceCoverageTest.items[rows[i].use]=rows[i];
            }else{
                var attributes:Object={attributeData:{},shellData:{},movementData:{}};
                var attrLoader:AttributeLoader=new AttributeLoader();
                var rows:Array=XMLParser.configureDataAsArray(parsed.bullet);
                for(var i:Number=0;i<rows.length;i++){
                    var attr:Object=attrLoader.load(rows[i]);if(attr!=null)attributes.attributeData[rows[i].name]=attr;
                }
                ChainBulletConfigResolver.resolve(parsed,attributes);
                var initApi:Object=org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
                VerticalPierceCoverageTest.saved={attributeMap:initApi.attributeMap};
                initApi.attributeMap=attributes.attributeData;
                VerticalPierceCoverageTest.loadLibrary();return;
            }
            VerticalPierceCoverageTest.loadDocument(this.probeIndex+1);
        };
        var paths:Array=["../data/items/item_sets.xml","../data/items/防具_40+级.xml","../data/items/bullets_cases.xml"];
        doc.load(paths[which]);
    }
    private static function loadLibrary():Void {
        library=_root.createEmptyMovieClip("__verticalDamageLibrary",_root.getNextHighestDepth());
        listener={onLoadInit:function(mc:MovieClip):Void{VerticalPierceCoverageTest.setup();},
            onLoadError:function(mc:MovieClip,code:String):Void{VerticalPierceCoverageTest.check(false,"bullet library "+code);VerticalPierceCoverageTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/原版素材库-子弹.swf",library),"actual bullet SWF requested");
    }
    private static function setup():Void {
        if(finished)return;
        try {
            var queue:Object=BulletQueueProcessor,cache:Object=TargetCacheManager,resultType:Object=DamageResult;
            saved.world=_root.gameworld;saved.clock=_root.帧计时器;saved.paused=_root.暂停;saved.control=_root.控制目标;
            saved.collision=_root.collisionLayer;saved.xmin=_root.Xmin;saved.xmax=_root.Xmax;saved.ymin=_root.Ymin;saved.ymax=_root.Ymax;
            saved.random=_root.随机偏移;saved.copy=_root.对象浅拷贝;saved.shoot=_root.子弹区域shoot传递;
            saved.initBullet=_root.子弹属性初始化;saved.getSkill=_root.主角函数.获取装备主动战技种类;
            saved.cleanup=_root.装备生命周期函数.移除异常周期函数;saved.jetInit=_root.装备生命周期函数.喷气背包初始化;saved.jetCycle=_root.装备生命周期函数.喷气背包周期;
            saved.message=_root.发布消息;saved.items=ItemUtil.itemDataDict;saved.sets=ItemUtil.itemSetConfigDict;saved.memoryWorld=_root.__unified61World;
            saved.queues=queue.activeQueues;saved.fake=queue.fakeUnits;saved.uids=queue.queueUIDs;saved.probe=queue._raySettleProbe;
            saved.acquireEnemy=cache.acquireEnemyCache;saved.display=resultType.prototype.triggerDisplay;
            saved.noise=PinkNoiseEngine.getInstance();saved.fluctuation=saved.noise.randomFluctuation;
            saved.rng=LinearCongruentialEngine.getInstance();saved.rngState=saved.rng.captureState();
            _root.gameworld=library;library.子弹区域=library;_root.暂停=false;
            _root.帧计时器={当前帧数:0,帧率:30,eventBus:new EventDispatcher(),taskManager:{addLifecycleTask:function(owner:Object,label:String,action:Function,interval:Number,args:Array):String{
                var id:String="vertical-probe:"+VerticalPierceCoverageTest.tasks.length;
                VerticalPierceCoverageTest.tasks.push({owner:owner,label:label,action:action,args:args,active:true});return id;
            }},移除生命周期任务:function(owner:Object,label:String):Void{
                for(var i:Number=0;i<VerticalPierceCoverageTest.tasks.length;i++){
                    var row:Object=VerticalPierceCoverageTest.tasks[i];if(row.owner===owner && row.label==label)row.active=false;
                }
            }};
            _root.Xmin=-2000;_root.Xmax=2200;_root.Ymin=-1000;_root.Ymax=1000;_root.collisionLayer={hitTest:noMap};
            _root.随机偏移=spread;_root.对象浅拷贝=shallow;_root.子弹区域shoot传递=shoot;
            _root.子弹属性初始化=function(mc:MovieClip,kind:String,unit:MovieClip):Object{return {发射者:unit._name,是否为敌人:unit.是否为敌人,最小霰弹值:1,击倒率:10,命中率:100};};
            _root.主角函数.获取装备主动战技种类=function(slot:String,use:String):String{return null;};
            _root.装备生命周期函数.移除异常周期函数=noop;_root.装备生命周期函数.喷气背包初始化=noop;_root.装备生命周期函数.喷气背包周期=noop;_root.发布消息=noop;
            ItemUtil.itemDataDict={};ItemUtil.itemSetConfigDict=configs;
            cache.acquireEnemyCache=enemies;queue._raySettleProbe=null;resultType.prototype.triggerDisplay=noop;saved.noise.randomFluctuation=noise;
            FactionManager.initialize();BulletQueueProcessor.initialize();ColliderFactoryRegistry.init();DamageManagerFactory.init();
            ChainUnitManager.getLayer().onEnterFrame=null;loadedWorld=true;
            beginCase();driver.onEnterFrame=function():Void{VerticalPierceCoverageTest.tick();};
        }catch(error:Error){check(false,"setup "+error);finish();}
    }
    private static function beginCase():Void {
        current=cases[index];current.emissions=0;current.events=0;current.segments=0;current.damage=0;current.maxUnits=0;current.polygonObserved=false;step=0;projectile=null;precheck=null;tasks=[];
        saved.rng.restoreState(123456);
        hero=library.createEmptyMovieClip("hero"+index,library.getNextHighestDepth());
        hero._x=0;hero._y=hero.Z轴坐标=200;hero.version=index+100;hero.等级=40;hero.重量=120;hero.方向=current.left ? "左" : "右";hero.是否为敌人=false;
        hero.hp满血值=hero.hp=5000;hero.mp满血值=hero.mp=1000;hero.防御力=3000;hero.伤害加成=1200;hero.damageTakenMultiplier=1;
        hero.基础韧性系数=1;hero.韧性加成=20;hero.韧性系数=1.2;hero.基础躲闪率=3;hero.躲闪率=3;hero.闪避加成=0;
        hero.魔法抗性={基础:14,热:14,冷:14,电:14,波:14,蚀:14,毒:14};hero.状态="站立";hero.攻击模式="兵器";
        hero.行走X速度=4;hero.起跳速度=-10;hero.dispatcher=new EventDispatcher();hero.syncRefs={};hero.man=hero.createEmptyMovieClip("man",1);
        hero.刀={name:"光剑天秤",value:{level:13}};hero.被动技能={};hero.生命周期函数列表=[];hero.主动战技={};
        hero.装载生命周期函数=_root.主角函数.装载生命周期函数;hero.完成生命周期函数装载=_root.主角函数.完成生命周期函数装载;
        hero.shield=AdaptiveShield.createDormant("vertical-damage-probe");hero.shield.setOwner(hero);hero.buffManager=new BuffManager(hero,{});
        for(var i:Number=0;i<slots.length;i++){
            var source:Object=ObjectUtil.clone(items[slots[i]]);
            hero[slots[i]]={name:source.name,value:{level:current.level}};hero[slots[i]+"数据"]=source;
        }
        _root.控制目标=hero._name;
        SetEffectController.prepare(hero);
        for(i=0;i<slots.length;i++)hero.装载生命周期函数(hero[slots[i]+"数据"].lifecycle,slots[i]);
        hero.完成生命周期函数装载();
        check(hero.__unifiedType61!=undefined,current.label+" real five-piece runtime");
        enemy=library.createEmptyMovieClip("enemy"+index,library.getNextHighestDepth());enemy._x=current.left ? -14-current.distance : 14+current.distance;enemy._y=enemy.Z轴坐标=200;
        enemy.hp=enemy.hp满血值=10000000;enemy.防御力=1;enemy.重量=38;enemy.等级=40;enemy.躲闪率=0;enemy.懒闪避=0;enemy.damageTakenMultiplier=1;
        enemy.是否为敌人=true;enemy.flags=0;enemy.中心高度=75;enemy.魔法抗性={基础:0};
        enemy.shield={absorbDamage:function(d:Number,bypass:Boolean,n:Number):Number{return d;}};
        var targetWidth:Number=current.width>0 ? current.width : 55.93986512;
        enemy.area=shape(enemy,"area",-targetWidth*0.5,-158.8,targetWidth,159.81407166);
        enemy.aabbCollider=ColliderFactoryRegistry.getFactory("AABB").createFromUnitArea(enemy);
        enemy.dispatcher=new EventDispatcher();enemy.dispatcher.subscribe("hit",function(t:MovieClip,s:MovieClip,b:Object,c:Object,d:Object):Void{VerticalPierceCoverageTest.recordHit(b,c,d);},enemy);
        var a:Object=enemy.aabbCollider;cacheRow={data:[enemy],leftValues:[a.left],rightValues:[a.right],rightMaxValues:[a.right]};
    }
    private static function shoot(props:Object):Object {
        current.emissions++;
        check(props.子弹散射度==5,current.label+" real chest XML diffusion is five");
        if(typeof(current.spread)=="number")props.子弹散射度=current.spread;
        trace("[COVERAGE_INPUT] case="+current.label+" split="+props.霰弹值+" power="+props.子弹威力+" type="+props.子弹种类+" speed="+props.子弹速度+" spread="+props.子弹散射度+" interval="+props.发射间隔毫秒+" damageType="+props.伤害类型);
        props.角度偏移=current.angle;props.霰弹值=current.count;
        if(current.fill>0)props.每帧补弹数=current.fill;
        if(current.kind)props.子弹种类=current.kind;
        var template:Object=_root.联弹系统.对象化模板["纵向联弹"];
        if(current.mc)delete _root.联弹系统.对象化模板["纵向联弹"];
        var angle:Number=ShootingAngleCalculator.calculate(props,hero);
        // Explicit factory-angle probes exercise epsilon boundaries without the normal integer offset conversion.
        if(typeof(current.directAngle)=="number")angle=current.directAngle;
        BulletFactory.prepareBulletData(props,hero);projectile=BulletFactory.createBullet(props,hero,angle);
        if(current.mc)_root.联弹系统.对象化模板["纵向联弹"]=template;
        check(projectile!=null,current.label+" actual factory birth");
        check(Math.abs(((projectile._rotation-angle+540)%360)-180)<0.0001,current.label+" actual launch angle matches probe");
        check(projectile.子弹散射度==(typeof(current.spread)=="number" ? current.spread : 5),current.label+" actual spread matches case");
        precheck=projectile.onEnterFrame;if(typeof(precheck)=="function")projectile.onEnterFrame=null;
        current.objectMode=projectile.chainGroup.isObject===true;
        trace("[COVERAGE_BIRTH] case="+current.label+" flags="+projectile.flags+" rotation="+projectile._rotation+" object="+current.objectMode+" minScatter="+projectile.最小霰弹值+" fill="+projectile.chainGroup.补弹分子+"/"+projectile.chainGroup.补弹分母);
        return projectile;
    }
    private static function recordHit(b:Object,c:Object,d:Object):Void {
        if(b.polygonCollider)current.polygonObserved=true;
        current.events++;current.segments+=d.actualScatterUsed;current.damage+=enemy.损伤值;
        var a:Object=b.aabbCollider;var g:ChainGroup=b.chainGroup;
        trace("[COVERAGE_HIT] case="+current.label+" frame="+step+" segments="+d.actualScatterUsed+" ratio="+c.overlapRatio+" cumulative="+b.hitCount+" damage="+enemy.损伤值+" chainCount="+g.count+" width="+(a.right-a.left)+" rotation="+b._rotation);
    }
    private static function tick():Void {
        if(finished)return;
        try{
            step++;_root.帧计时器.当前帧数++;hero.shield.update(1);
            var copy:Array=tasks.slice();for(var i:Number=0;i<copy.length;i++)if(copy[i].active && copy[i].owner._parent)copy[i].action.apply(copy[i].owner,copy[i].args);
            if(step==1)hero.dispatcher.publish("WeaponSkill","兵器");
            ChainUnitManager.tick();
            if(projectile){
                if(typeof(precheck)=="function" && projectile._parent)precheck.call(projectile);
                var group:ChainGroup=ChainUnitManager.findGroupByBullet(projectile);
                if(group && group.单元体列表.length>current.maxUnits)current.maxUnits=group.单元体列表.length;
            }
            BulletQueueProcessor.processQueue();
            if(step==85){
                var diag:Object=hero.__unifiedType61.getDiagnostics();
                check(current.emissions==1 && diag.cannonCount==1,current.label+" exactly one chest emission");
                check(current.events>0 && current.segments>0,current.label+" actual damage reached target");
                check(isFinite(enemy.hp) && current.damage>100,current.label+" real damage rather than fallback one");
                trace("[COVERAGE_RESULT] case="+current.label+" emissions="+current.emissions+" cannonCount="+diag.cannonCount+" settlements="+current.events+" totalSegments="+current.segments+" totalDamage="+current.damage+" hpLoss="+(10000000-enemy.hp)+" maxUnits="+current.maxUnits);
                check(current.polygonObserved===(!current.unaffected),current.label+" coverage path selection");
                results[current.label]={segments:current.segments,events:current.events,damage:current.damage};
                cleanupCase();index++;
                if(index<cases.length)beginCase();else{verifyCrossCases();finish();}
            }
        }catch(error:Error){check(false,"tick "+error);finish();}
    }
    private static function verifyCrossCases():Void {
        check(results["flat-far"].segments==results["epsilon-plus"].segments
            && results["flat-far"].segments==results["epsilon-minus"].segments,"zero-degree coverage has no discontinuity");
        check(results["left-flat"].segments==results["left-epsilon-minus"].segments
            && results["left-flat"].segments==results["left-epsilon-plus"].segments,"180-degree coverage has no discontinuity");
        check(results["flat-mc"].segments==results["flat-far"].segments,"right MC and object coverage agree");
        check(results["left-mc"].segments==results["left-flat"].segments,"left MC and object coverage agree");
        check(results["tilt1-far"].segments==13 && results["tilt1-near"].segments==27,"existing non-horizontal baseline preserved");
        check(results["wide-target"].segments>results["flat-far"].segments && results["wide-target"].segments>24,"target size remains meaningful without a 24-hit hard cap");
        check(results["single-pierce-control"].segments==3,"ordinary piercing bullet behavior preserved");
        check(results["normal-chain-control"].segments==12,"non-piercing vertical chain budget preserved");
    }
    private static function cleanupCase():Void {
        if(projectile && typeof(projectile.removeMovieClip)=="function")projectile.removeMovieClip();
        if(hero){DressupInitializer.teardownLifeCycles(hero);hero.dispatcher.destroy();hero.buffManager.destroy();hero.removeMovieClip();}
        if(enemy){enemy.dispatcher.destroy();enemy.removeMovieClip();}
        ChainUnitManager.resetAll();projectile=null;hero=null;enemy=null;tasks=[];
    }
    private static function finish():Void {
        if(finished)return;finished=true;
        if(loadedWorld){
            cleanupCase();var queue:Object=BulletQueueProcessor,cache:Object=TargetCacheManager,resultType:Object=DamageResult;
            queue.activeQueues=saved.queues;queue.fakeUnits=saved.fake;queue.queueUIDs=saved.uids;queue._raySettleProbe=saved.probe;cache.acquireEnemyCache=saved.acquireEnemy;
            resultType.prototype.triggerDisplay=saved.display;saved.noise.randomFluctuation=saved.fluctuation;saved.rng.restoreState(saved.rngState);
            _root.帧计时器.eventBus.destroy();_root.gameworld=saved.world;_root.帧计时器=saved.clock;_root.暂停=saved.paused;_root.控制目标=saved.control;
            _root.collisionLayer=saved.collision;_root.Xmin=saved.xmin;_root.Xmax=saved.xmax;_root.Ymin=saved.ymin;_root.Ymax=saved.ymax;
            _root.随机偏移=saved.random;_root.对象浅拷贝=saved.copy;_root.子弹区域shoot传递=saved.shoot;_root.子弹属性初始化=saved.initBullet;
            _root.主角函数.获取装备主动战技种类=saved.getSkill;_root.装备生命周期函数.移除异常周期函数=saved.cleanup;
            _root.装备生命周期函数.喷气背包初始化=saved.jetInit;_root.装备生命周期函数.喷气背包周期=saved.jetCycle;_root.发布消息=saved.message;
            ItemUtil.itemDataDict=saved.items;ItemUtil.itemSetConfigDict=saved.sets;_root.__unified61World=saved.memoryWorld;
        }
        if(saved){var initApi:Object=org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;initApi.attributeMap=saved.attributeMap;}
        if(loader)loader.removeListener(listener);if(library)library.removeMovieClip();if(driver)driver.onEnterFrame=null;
        trace("VerticalPierceCoverageTest Checks Passed: "+passed);trace("VerticalPierceCoverageTest Checks Failed: "+failed);
        _root.verticalPierceCoverageComplete();if(driver)driver.removeMovieClip();
    }
}
