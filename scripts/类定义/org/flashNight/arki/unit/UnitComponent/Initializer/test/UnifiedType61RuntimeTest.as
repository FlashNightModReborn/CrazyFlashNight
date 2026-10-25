import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.hud.PlayerHudBuffProjection;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.EventDispatcher;

/** 真实 XML / 五件门控 / 护盾 / Buff / ReloadManager；库存提交仅隔离在内存，零玩家槽位。 */
class org.flashNight.arki.unit.UnitComponent.Initializer.test.UnifiedType61RuntimeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var serial:Number;
    private static var tasks:Array;
    private static var units:Array;
    private static var emitted:Array;
    private static var configs:Object;
    private static var items:Object;
    private static var saved:Object;
    private static var watchdog:MovieClip;
    private static var completed:Boolean;
    private static var stock:Number;
    private static var paid:Number;
    private static var hero:Object;
    private static var hudProjections:Array;
    private static var slots:Array = ["头部装备", "上装装备", "下装装备", "脚部装备", "手部装备"];
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[FAIL] UnifiedType61RuntimeTest: " + label); }
    }
    private static function near(a:Number, b:Number):Boolean { return Math.abs(a-b) < .0001; }
    public static function runAllTests():Void {
        passed=0;failed=0;serial=0;tasks=[];units=[];emitted=[];hudProjections=[];completed=false;stock=20;paid=0;
        saved={world:_root.gameworld,clock:_root.帧计时器,control:_root.控制目标,ui:_root.玩家信息界面,
            items:ItemUtil.itemDataDict,sets:ItemUtil.itemSetConfigDict,save:_root.存档系统,
            shoot:_root.子弹区域shoot传递,initBullet:_root.子弹属性初始化,message:_root.发布消息,
            getSkill:_root.主角函数.获取装备主动战技种类,cleanup:_root.装备生命周期函数.移除异常周期函数,
            jetInit:_root.装备生命周期函数.喷气背包初始化,jetCycle:_root.装备生命周期函数.喷气背包周期,
            memoryWorld:_root.__unified61World};
        var itemApi:Object=org.flashNight.arki.item.ItemUtil;
        var targetApi:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        saved.submit=itemApi.singleSubmit;saved.total=itemApi.getTotal;saved.hero=targetApi.findHero;
        itemApi.singleSubmit=function(name:String, count:Number, context:Object):Boolean {
            if (UnifiedType61RuntimeTest.stock<count) return false;
            UnifiedType61RuntimeTest.stock-=count;UnifiedType61RuntimeTest.paid+=count;return true;
        };
        itemApi.getTotal=function(name:String):Number { return UnifiedType61RuntimeTest.stock; };
        targetApi.findHero=function():Object { return UnifiedType61RuntimeTest.hero; };
        _root.gameworld=_root;_root.存档系统={};_root.玩家信息界面={玩家必要信息界面:{}};
        ItemUtil.itemDataDict={};
        _root.帧计时器={当前帧数:0,帧率:30,taskManager:{addLifecycleTask:function(owner:Object,label:String,action:Function,interval:Number,args:Array):String {
            var id:String="u61-test:"+UnifiedType61RuntimeTest.tasks.length;
            UnifiedType61RuntimeTest.tasks.push({owner:owner,label:label,action:action,args:args,active:true});return id;
        }},移除生命周期任务:function(owner:Object,label:String):Void {
            for(var i:Number=0;i<UnifiedType61RuntimeTest.tasks.length;i++) {
                var row:Object=UnifiedType61RuntimeTest.tasks[i];if(row.owner===owner && row.label==label)row.active=false;
            }
        }};
        _root.发布消息=function(message):Void {};
        _root.主角函数.获取装备主动战技种类=function(slot:String,use:String):String { return null; };
        _root.装备生命周期函数.移除异常周期函数=function(ref:Object):Void {};
        _root.装备生命周期函数.喷气背包初始化=function(ref:Object,param:Object):Void {ref.自机.jetCount++;};
        _root.装备生命周期函数.喷气背包周期=function(ref:Object,param:Object):Void {};
        _root.子弹属性初始化=function(mc:MovieClip,kind:String,unit:MovieClip):Object {
            return {发射者:unit._name,是否为敌人:unit.是否为敌人,最小霰弹值:1,击倒率:10,命中率:10};
        };
        _root.子弹区域shoot传递=function(props:Object):Void {UnifiedType61RuntimeTest.emitted.push(ObjectUtil.clone(props));};
        watchdog=_root.createEmptyMovieClip("__unified61Watch",_root.getNextHighestDepth());watchdog.count=0;
        watchdog.onEnterFrame=function():Void {if(++this.count>240){UnifiedType61RuntimeTest.check(false,"XML timeout");UnifiedType61RuntimeTest.finish();}};
        loadDocument(0);
    }
    private static function loadDocument(index:Number):Void {
        var doc=new XML();doc.ignoreWhite=true;doc.testIndex=index;
        doc.onLoad=function(ok:Boolean):Void {
            if(!ok){UnifiedType61RuntimeTest.check(false,"candidate XML load");UnifiedType61RuntimeTest.finish();return;}
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            if(this.testIndex==0){
                UnifiedType61RuntimeTest.configs={};var entries:Array=XMLParser.configureDataAsArray(parsed.set);
                for(var i:Number=0;i<entries.length;i++)UnifiedType61RuntimeTest.configs[entries[i].id]=entries[i];
                UnifiedType61RuntimeTest.loadDocument(1);
            }else{
                UnifiedType61RuntimeTest.items={};var entries:Array=XMLParser.configureDataAsArray(parsed.item);
                for(var i:Number=0;i<entries.length;i++)if(entries[i].setId==UnifiedType61Runtime.SET_ID)UnifiedType61RuntimeTest.items[entries[i].use]=entries[i];
                UnifiedType61RuntimeTest.execute();
            }
        };
        var paths:Array=["../data/items/item_sets.xml","../data/items/防具_40+级.xml"];
        doc.load(paths[index]);
    }
    private static function bind(unit:MovieClip):Void {
        SetEffectController.prepare(unit);
        for(var i:Number=0;i<slots.length;i++)unit.装载生命周期函数(unit[slots[i]+"数据"].lifecycle,slots[i]);
        unit.完成生命周期函数装载();
    }
    private static function makeUnit(count:Number, key:String, invalid:Boolean):MovieClip {
        var u:MovieClip=_root.createEmptyMovieClip("__unified61Unit"+(++serial),_root.getNextHighestDepth());units.push(u);
        _root.控制目标=u._name;hero=u;u.version=serial;u.等级=40;u.重量=120;u.方向="右";u.是否为敌人=false;
        u.hp满血值=u.hp=5000;u.mp满血值=u.mp=1000;u.防御力=3000;u.伤害加成=2400;u.damageTakenMultiplier=1;
        u.基础韧性系数=1;u.韧性加成=20;u.韧性系数=1.2;u.基础躲闪率=3;u.躲闪率=3;u.闪避加成=0;
        u.魔法抗性={基础:14,热:14,冷:14,电:14,波:14,蚀:14,毒:14};u.状态="站立";u.攻击模式="兵器";u.Z轴坐标=0;
        var ratio:Number=org.flashNight.arki.unit.UnitUtil.getWeightSpeedRatio(120,40);u.行走X速度=4*ratio;u.起跳速度=-10*ratio;
        u.dispatcher=new EventDispatcher();u.syncRefs={};u.man=u.createEmptyMovieClip("man",1);u.jetCount=0;
        u.刀={name:key,value:{level:1}};u.被动技能={枪械师:{启用:true,等级:10}};
        u.生命周期函数列表=[];u.主动战技={};u.装载生命周期函数=_root.主角函数.装载生命周期函数;
        u.完成生命周期函数装载=_root.主角函数.完成生命周期函数装载;
        u.shield=AdaptiveShield.createDormant("unified61-test");u.shield.setOwner(u);u.buffManager=new BuffManager(u,{});
        for(var i:Number=0;i<slots.length;i++){
            var source:Object=ObjectUtil.clone(items[slots[i]]);if(i>=count)source.setId="";
            u[slots[i]]={name:source.name,value:{level:1}};u[slots[i]+"数据"]=source;
        }
        if(invalid)u.上装装备数据.lifecycle.attr_统合61.init.initParam.rechargeSeconds=0;
        bind(u);return u;
    }
    private static function advance(frames:Number):Void {
        for(var n:Number=0;n<frames;n++){
            _root.帧计时器.当前帧数++;
            for(var u:Number=0;u<units.length;u++)if(units[u]._parent)units[u].shield.update(1);
            var snapshot:Array=tasks.slice();
            for(var i:Number=0;i<snapshot.length;i++)if(snapshot[i].active && snapshot[i].owner._parent)snapshot[i].action.apply(snapshot[i].owner,snapshot[i].args);
        }
    }
    private static function closeUnit(u:MovieClip):Void {
        DressupInitializer.teardownLifeCycles(u);u.dispatcher.destroy();u.buffManager.destroy();u.removeMovieClip();
    }
    private static function gun(u:Object,slot:String,cap:Number,shot:Number):Void {
        u[slot]={name:"fixture-"+slot,value:{level:1,shot:shot}};u[slot+"弹匣容量"]=cap;
        u[slot+"属性"]={clipname:"fixture-magazine",reloadType:"magazine"};
    }
    private static function switchTo(u:Object,mode:String):Void {
        var old:String=u.攻击模式;u.攻击模式=mode;u.dispatcher.publish("attackModeChanged",u,old,mode);
    }
    private static function observeHud(manager:Object):PlayerHudBuffProjection {
        var projection:PlayerHudBuffProjection=new PlayerHudBuffProjection();
        projection.setDetailsEnabled(true);projection.initialize(manager);hudProjections.push(projection);return projection;
    }
    private static function hudRow(projection:PlayerHudBuffProjection,name:String):Object {
        var rows:Array=projection.snapshot();
        for(var i:Number=0;i<rows.length;i++)if(rows[i].info.name==name)return rows[i];
        return null;
    }
    private static function hudMod(row:Object,property:String):Number {
        var mods:Array=row.mods;
        for(var i:Number=0;i<mods.length;i++)if(mods[i].property==property)return Number(mods[i].value);
        return Number.NaN;
    }
    private static function verifyHudLifecycle():Void {
        var u:MovieClip=makeUnit(5,"",false);advance(1);
        var r:UnifiedType61Runtime=u.__unifiedType61;var shield:Shield=Shield(u.shield.getShieldById(r.getShieldId()));
        var projection:PlayerHudBuffProjection=observeHud(u.buffManager);
        var core:Object=hudRow(projection,"全装助力"),buffer:Object=hudRow(projection,"缓冲护盾");
        check(projection.snapshot().length==2,"cold HUD has exactly two set states");
        check(core.info.description.length>0 && buffer.info.description.length>0,"HUD states have equipment explanations");
        check(core.timed===false && buffer.timed===false,"permanent set states do not invent duration");
        check(core.mods.length==6,"core details expose six real injected modifiers");
        check(buffer.mods.length==7,"buffer details expose seven real resistance modifiers");
        check(hudMod(core,"重量")==-12 && near(hudMod(core,"damageTakenMultiplier"),.88),"HUD reads actual servo and reduction values");
        check(buffer.activation.active===true,"online buffer is visible as active");
        var capacity:Number=shield.getCapacity(),frame:Number=Number(_root.帧计时器.当前帧数),reloads:Number=r.getDiagnostics().reloadCount;
        for(var i:Number=0;i<5;i++)projection.snapshot();
        check(shield.getCapacity()==capacity && Number(_root.帧计时器.当前帧数)==frame && r.getDiagnostics().reloadCount==reloads,"HUD reads cannot tick or refill resources");
        shield.consumeCapacity(999);
        buffer=hudRow(projection,"缓冲护盾");
        check(buffer.activation.active===false && hudMod(buffer,"魔法抗性.热")==0,"broken shield immediately shows inactive zero protection");
        u.刀.name="光剑天秤";advance(90);
        check(hudMod(hudRow(projection,"全装助力"),"闪避加成")==175,"authorization updates existing HUD modifiers");
        check(hudRow(projection,"缓冲护盾").activation.active===true,"rebuilt shield restores active presentation");
        DressupInitializer.teardownLifeCycles(u);
        check(projection.snapshot().length==0 && u.buffManager.getAllMetaBuffs().length==0,"unequip removes both HUD states and their owned groups");
        bind(u);advance(1);
        check(projection.snapshot().length==2 && hudRow(projection,"全装助力")!=null,"warm re-equip produces the same two named states");
        var rebound:PlayerHudBuffProjection=observeHud(u.buffManager);
        check(rebound.snapshot().length==2 && hudRow(rebound,"缓冲护盾").info.name==hudRow(projection,"缓冲护盾").info.name,"cold rebind agrees with warm event delivery");
        var podId:String=u.buffManager.addBuff(new PodBuff("伤害加成",BuffCalculationType.ADD,1),"unified61-test:standalone");
        check(projection.snapshot().length==2,"standalone Pod additions cannot create anonymous HUD cards");
        u.buffManager.removeBuff(podId);u.buffManager.update(0);
        check(projection.snapshot().length==2,"removing hidden standalone Pod preserves named cards");
        closeUnit(u);
    }
    private static function execute():Void {
        ItemUtil.itemSetConfigDict=configs;
        try{
            for(var count:Number=0;count<5;count++){
                var partial:MovieClip=makeUnit(count,"光剑天秤",false);
                check(partial.__unifiedType61==undefined,"partial set gated "+count);
                check(near(partial.damageTakenMultiplier,1),"partial no damage buff "+count);
                if(count==4)check(partial.jetCount==1,"jetpack retains individual ownership");
                closeUnit(partial);
            }
            var invalid:MovieClip=makeUnit(5,"",true);
            check(invalid.__unifiedType61==undefined,"invalid config rollback");
            check(near(invalid.重量,120),"rollback weight");closeUnit(invalid);
            var u:MovieClip=makeUnit(5,"",false);var r:UnifiedType61Runtime=u.__unifiedType61;
            check(r!=undefined,"five-piece native lifecycle");
            var shield:Shield=Shield(u.shield.getShieldById(r.getShieldId()));
            check(shield.getCapacity()==0 && shield.getStrength()==0,"pre-resource setup cannot shield");
            advance(1);
            check(near(shield.getCapacity(),250),"five percent normal max HP");
            check(shield.getStrength()==3000,"stable defense as strength");
            check(near(u.damageTakenMultiplier,.88),"twelve percent reduction");
            check(near(u.韧性系数,3.7) && u.韧性加成==270,"five rubber toughness only");
            check(near(u.躲闪率,3/1.35) && u.闪避加成==35,"one sensor normal tier");
            check(u.重量==108,"constant twelve kilogram servo");
            check(near(u.行走X速度,4*org.flashNight.arki.unit.UnitUtil.getWeightSpeedRatio(108,40)),"servo reprojects movement");
            check(u.mp==1000 && u.hp==5000,"startup no HP MP cost");
            u.mp=0;advance(1);check(shield.getCapacity()==250 && shield.getStrength()==3000,"zero MP preserves buffer");
            check(WeatherSystem.getInstance().getNightVisionManager().validate(0,u)=="浅绿夜视仪","zero MP preserves darkest-scene vision");u.mp=1000;
            check(near(u.魔法抗性.热,25),"normal shield resistance floor");
            check(WeatherSystem.getInstance().getNightVisionManager().getRegistered().视觉情况=="浅绿夜视仪","green vision registered");
            var bt:String=u.buffManager.addBuff(new PodBuff("damageTakenMultiplier",BuffCalculationType.MULT_NEGATIVE,.8),"test:霸体");u.buffManager.update(0);
            check(near(u.damageTakenMultiplier,.8),"stronger reduction replaces not multiplies");u.buffManager.removeBuff(bt);u.buffManager.update(0);
            check(near(u.damageTakenMultiplier,.88),"set reduction resumes");
            var temp:String=u.buffManager.addBuff(new PodBuff("防御力",BuffCalculationType.ADD,9000),"test:temporary");u.buffManager.update(0);advance(1);
            check(u.防御力==12000,"temporary defense is actually active in fixture");
            check(shield.getStrength()==3000,"temporary defense does not inflate shield");u.buffManager.removeBuff(temp);u.buffManager.update(0);
            shield.consumeCapacity(100);advance(30);check(near(shield.getCapacity(),150),"one second no-hit delay");
            advance(30);check(near(shield.getCapacity(),250),"one second full-capacity recharge");
            shield.consumeCapacity(999);check(shield.getStrength()==0 && !shield.getResistBypass(),"break immediately clears protection");
            check(near(u.魔法抗性.热,14),"break immediately removes own resistance");
            check(near(u.韧性系数,3.7) && u.重量==108,"break retains core equipment aids");
            u.hp=4000;advance(149);check(shield.getCapacity()==0,"normal fixed wait not early");
            advance(1);check(near(shield.getCapacity(),250),"five seconds rebuild even after HP loss");
            shield.consumeCapacity(100);var before:Number=shield.getCapacity();u.刀={name:"光剑天秤",value:{level:1}};advance(1);
            check(r.getDiagnostics().authorized && shield.getResistBypass(),"equipped constellation unlocks off-hand");
            check(shield.getCapacity()==before,"authorization does not refill");
            check(near(u.躲闪率,3/2.75) && u.闪避加成==175,"five sensor additive projection");
            check(near(u.魔法抗性.热,45),"authorized floor");
            var energy:String=u.buffManager.addBuff(new PodBuff("魔法抗性.热",BuffCalculationType.ADD,50),"test:energy");u.buffManager.update(0);
            check(near(u.魔法抗性.热,95),"energy plus authorized reaches95");
            var reservoir:Shield=Shield.createRechargeable(10000,100,0,0,"external-energy");u.shield.addShield(reservoir,true);
            check(u.shield.absorbDamage(2000,true,1)==0,"buffer bridges true-hit into energy reservoir");
            check(shield.getCapacity()==0 && reservoir.getCapacity()<10000,"same hit consumes both layers");
            check(u.shield.absorbDamage(100,true,1)==100,"empty buffer cannot lend bypass resistance");
            check(near(u.魔法抗性.热,64),"external energy buff survives buffer loss");
            advance(89);check(shield.getCapacity()==0,"authorized wait not early");advance(1);
            check(near(shield.getCapacity(),250),"three seconds full rebuild");
            u.刀={name:"血色光剑天秤",value:{level:1}};advance(1);
            check(!r.getDiagnostics().authorized && !shield.getResistBypass(),"blood sword excluded");
            check(near(u.魔法抗性.热,75),"normal plus energy reaches75");u.buffManager.removeBuff(energy);u.buffManager.update(0);
            shield.consumeCapacity(250);var shots:Number=emitted.length;u.dispatcher.publish("WeaponSkill","兵器");
            check(near(shield.getCapacity(),250),"successful skill immediate refill");advance(2);
            check(emitted.length==shots,"cannon opens before fire");advance(1);
            check(emitted.length==shots+1,"one burst per successful skill");
            var props:Object=emitted[emitted.length-1];check(props.霰弹值==12 && props.子弹威力==200,"12 segments and G/12 base");
            check(props.伤害类型=="魔法" && props.魔法伤害属性=="热","ordinary heat cannon");
            u.刀={name:"光刃摩羯",value:{level:1}};advance(1);u.dispatcher.publish("WeaponSkill","长枪");advance(3);
            check(emitted[emitted.length-1].伤害类型=="真伤","authorized any weapon-skill cannon");
            gun(u,"长枪",60,30);gun(u,"手枪",30,0);gun(u,"手枪2",30,15);hero=u;
            u.dispatcher.publish("attackModeChanged",u,"空手","长枪");
            check(u.长枪.value.shot==30 && paid==0,"stale event cannot reload a different current mode");
            switchTo(u,"长枪");check(u.长枪.value.shot==0 && paid==1,"ordinary magazine paid background reload");
            check(u.长枪.value.reloadCount==30,"gunslinger preserves remaining rounds");
            var ready:Number=r.getDiagnostics().readyAt.长枪;u.长枪.value.shot=10;
            switchTo(u,"兵器");switchTo(u,"长枪");check(u.长枪.value.shot==10 && paid==1,"no early redemption");
            ReloadManager.commitMagazine(u,"长枪","fixture-magazine");
            check(r.getDiagnostics().readyAt.长枪==ready,"ordinary roll-equivalent reload keeps clock");
            switchTo(u,"双枪");check(u.手枪2.value.shot==0,"secondary independent ready slot");
            check(r.getDiagnostics().readyAt.手枪==0,"full primary keeps its ready slot");
            u.手枪.value.shot=15;stock=0;u.手枪.value.reloadCount=0;switchTo(u,"兵器");switchTo(u,"双枪");
            check(u.手枪.value.shot==15 && r.getDiagnostics().readyAt.手枪==0,"failed reload retains rounds and ready");
            check(u.手枪.value.reloadCount==0,"failed paid reload rolls recovery back");
            stock=1;switchTo(u,"兵器");switchTo(u,"双枪");check(u.手枪.value.shot==0,"retry on next actual switch");
            var longReady:Number=r.getDiagnostics().readyAt.长枪;u.长枪.value.shot=20;stock=10;
            advance(longReady-Number(_root.帧计时器.当前帧数)-1);switchTo(u,"长枪");
            check(u.长枪.value.shot==20,"twelve seconds not redeemed one frame early");advance(1);switchTo(u,"兵器");switchTo(u,"长枪");
            check(u.长枪.value.shot==0,"twelve seconds becomes ready exactly");
            shield.consumeCapacity(100);before=shield.getCapacity();ready=r.getDiagnostics().readyAt.手枪;
            DressupInitializer.teardownLifeCycles(u);check(u.__unifiedType61==undefined,"teardown removes runtime");
            check(near(u.重量,120) && near(u.韧性系数,1.2) && near(u.躲闪率,3),"teardown restores ordinary attributes");
            check(u.shield.getShieldById(reservoir.getId())===reservoir,"teardown preserves other shield");
            bind(u);advance(1);r=u.__unifiedType61;shield=Shield(u.shield.getShieldById(r.getShieldId()));
            check(near(shield.getCapacity(),before),"same-map re-equip preserves damaged capacity");
            advance(28);check(near(shield.getCapacity(),before),"re-equip cannot bypass no-hit recharge delay");
            check(r.getDiagnostics().readyAt.手枪==ready,"same-map re-equip preserves gun clock");
            u.hp=0;advance(1);check(shield.getCapacity()==0 && !shield.getResistBypass(),"death cannot retain protection");
            u.hp=1000;advance(1);check(shield.getCapacity()==0,"revive does not grant free initial shield");advance(90);
            check(near(shield.getCapacity(),250),"revive rebuilds after fixed delay");
            closeUnit(u);
            verifyHudLifecycle();
        }catch(error:Error){check(false,"exception "+error.message);}
        finish();
    }
    private static function finish():Void {
        if(completed)return;completed=true;
        for(var h:Number=0;h<hudProjections.length;h++)hudProjections[h].deinitialize();
        for(var i:Number=0;i<units.length;i++)if(units[i]._parent)closeUnit(units[i]);
        if(watchdog)watchdog.removeMovieClip();
        var itemApi:Object=org.flashNight.arki.item.ItemUtil;var targetApi:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        itemApi.singleSubmit=saved.submit;itemApi.getTotal=saved.total;targetApi.findHero=saved.hero;
        _root.gameworld=saved.world;_root.帧计时器=saved.clock;_root.控制目标=saved.control;_root.玩家信息界面=saved.ui;
        _root.存档系统=saved.save;ItemUtil.itemDataDict=saved.items;ItemUtil.itemSetConfigDict=saved.sets;
        _root.子弹区域shoot传递=saved.shoot;_root.子弹属性初始化=saved.initBullet;_root.发布消息=saved.message;
        _root.主角函数.获取装备主动战技种类=saved.getSkill;_root.装备生命周期函数.移除异常周期函数=saved.cleanup;
        _root.装备生命周期函数.喷气背包初始化=saved.jetInit;_root.装备生命周期函数.喷气背包周期=saved.jetCycle;
        _root.__unified61World=saved.memoryWorld;
        trace("UnifiedType61RuntimeTest Tests Passed: "+passed);trace("UnifiedType61RuntimeTest Tests Failed: "+failed);
        _root.unifiedSetFocusedComplete();
    }
}
