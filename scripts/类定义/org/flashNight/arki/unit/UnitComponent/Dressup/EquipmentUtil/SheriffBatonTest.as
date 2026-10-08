import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.item.equipment.EquipmentLifecyclePolicy;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.PodBuff;
import org.flashNight.arki.component.Buff.BuffCalculationType;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.SheriffBatonController;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.gesh.xml.XMLParser;

// Actual item XML, production lifecycle loader, real BuffManager and published art.
// Input is injected at the existing key-query boundary; this is not a physical E2E.
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.SheriffBatonTest {
    private static var passed:Number, failed:Number, pressed:Number;
    private static var finished:Boolean;
    private static var old:Object, item:Object, cycles:Array, removed:Array;
    private static var world:MovieClip, actor:MovieClip, saber:MovieClip, watchdog:MovieClip;
    private static var loader:MovieClipLoader, listener:Object;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("SheriffBatonTest FAIL: " + label); }
    }
    public static function runAllTests():Void {
        passed=0; failed=0; pressed=0; finished=false; cycles=[]; removed=[];
        old={world:_root.gameworld,clock:_root.帧计时器,pause:_root.暂停,key:_root.武器变形键,
            input:_root.按键输入检测,control:_root.控制目标,items:ItemUtil.itemDataDict,
            cleanup:_root.装备生命周期函数.移除异常周期函数,mods:ModRegistry.getModList()};
        world=_root.createEmptyMovieClip("__sheriffBatonTest",_root.getNextHighestDepth());
        _root.gameworld=world; _root.暂停=false; _root.武器变形键=81;
        _root.帧计时器={当前帧数:0,taskManager:{addLifecycleTask:function(owner:Object,label:String,callback:Function,interval:Number,args:Array):Number {
            SheriffBatonTest.cycles.push({owner:owner,callback:callback,args:args});
            return SheriffBatonTest.cycles.length;
        }},移除生命周期任务:function(owner:Object,label:String):Void { SheriffBatonTest.removed.push(label); }};
        _root.按键输入检测=function(unit:MovieClip,key:Number):Boolean {
            return unit._name==_root.控制目标 && SheriffBatonTest.pressed==key;
        };
        _root.装备生命周期函数.移除异常周期函数=function(ref:Object):Void {};
        watchdog=_root.createEmptyMovieClip("__sheriffBatonWatchdog",_root.getNextHighestDepth());
        watchdog.frames=0;
        watchdog.onEnterFrame=function():Void {
            if (++this.frames>=600) { SheriffBatonTest.check(false,"load timeout"); SheriffBatonTest.finish(); }
        };
        var xml:XML=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(success:Boolean):Void {
            SheriffBatonTest.check(success,"actual short-weapon XML loaded");
            if (!success) { SheriffBatonTest.finish();return; }
            var list:Array=XMLParser.configureDataAsArray(XMLParser.parseXMLNode(this.firstChild).item);
            for (var i:Number=0;i<list.length;i++) if(list[i].name=="特勤警棍") SheriffBatonTest.item=list[i];
            SheriffBatonTest.loadAsset();
        };
        xml.load("../data/items/武器_刀_短兵.xml");
    }
    private static function loadAsset():Void {
        check(item!=undefined && EquipmentLifecyclePolicy.isIndependentLifecycle(item.lifecycle),"real XML independent Q lifecycle");
        ItemUtil.itemDataDict={};ItemUtil.itemDataDict[item.name]=item;
        actor=world.createEmptyMovieClip("actor",world.getNextHighestDepth());
        listener={};
        listener.onLoadInit=function(loaded:MovieClip):Void {
            SheriffBatonTest.saber=loaded.attachMovie("刀-Codex-特勤警棍","saber",loaded.getNextHighestDepth());
            loaded.onEnterFrame=function():Void {
                delete this.onEnterFrame;
                try { SheriffBatonTest.runLoaded(); }
                catch(error) { SheriffBatonTest.check(false,"unexpected "+error);SheriffBatonTest.finish(); }
            };
        };
        listener.onLoadError=function(loaded:MovieClip,error:String):Void {
            SheriffBatonTest.check(false,"SWF load "+error);SheriffBatonTest.finish();
        };
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Codex专用素材.swf",actor),"submit actual weapon SWF");
    }
    private static function equip(value:Object, flat:Number):Object {
        cycles=[]; pressed=0;
        actor.version=1;actor.hp=100;actor.攻击模式="空手";actor.主动战技={};actor.syncRefs={};
        actor.防御力=100;actor.dispatcher=new EventDispatcher();actor.buffManager=new BuffManager(actor,{});
        actor.man=actor.createEmptyMovieClip("man",actor.getNextHighestDepth());actor.man.兵器使用标签=true;
        actor.刀={name:item.name,value:value};
        actor.刀数据=EquipmentCalculator.calculatePure(item,value,EquipmentConfigManager.getFullConfig(),ModRegistry.getModDict());
        actor.兵器动作类型=actor.刀数据.actiontype;
        actor.刀属性=actor.刀数据.data;actor.刀属性.power+=flat;
        actor.刀_引用=saber;_root.控制目标=actor._name;
        actor.装载生命周期函数=_root.主角函数.装载生命周期函数;
        actor.装载生命周期函数(actor.刀数据.lifecycle,"刀");
        check(cycles.length==1,"production loader registers exactly one Q lifecycle");
        return cycles[0].args[0];
    }
    private static function tick(n:Number):Void {
        if (n==undefined)n=1;
        for(var j:Number=0;j<n;j++) {
            _root.帧计时器.当前帧数++;
            for(var i:Number=0;i<cycles.length;i++) cycles[i].callback.apply(cycles[i].owner,cycles[i].args);
        }
    }
    private static function press(key:Number):Void { pressed=0;tick();pressed=key;tick(); }
    private static function teardown():Void {
        DressupInitializer.teardownLifeCycles(actor);actor.buffManager.clearAllBuffs();actor.buffManager.destroy();actor.dispatcher.destroy();
    }
    private static function runLoaded():Void {
        check(saber._parent===actor && saber._totalframes==15,"published linkage has 15 real frames");
        check(saber._currentframe==1,"published weapon starts stopped as a baton");
        var ref:Object=equip({level:1,mods:[]},0);
        check(actor.兵器动作类型=="棍棒","baton equips the club attack module");
        check(actor.刀属性.power==220 && actor.防御力==100,"initial stowed baton has no defense");
        actor.buffManager.addBuffImmediate(new PodBuff("防御力",BuffCalculationType.ADD,20),"unrelated-defense");
        press(81);check(ref.frame==1,"Q cannot transform a stowed weapon");
        actor.攻击模式="兵器";tick();
        check(ref.frame==1 && actor.防御力==285,"drawing with held Q does not toggle; defense stacks additively");
        press(81);check(ref.frame==2 && actor.刀属性.power==220 && actor.防御力==120,"Q begins unfolding without double benefit");
        cycles[0].callback.apply(actor,cycles[0].args);
        check(ref.frame==2,"same-frame task dedup prevents double advance");
        var intact:Boolean=true;
        for(var i:Number=0;i<13;i++) {
            tick();
            for(var box:Number=1;box<=3;box++) if(saber["刀口位置"+box]._parent!==saber)intact=false;
        }
        check(intact,"all three collision interfaces survive every transform frame");
        check(ref.frame==15 && saber._currentframe==15 && actor.刀属性.power==330 && actor.防御力==120,"blade art and attack value reach endpoint together");
        check(actor.兵器动作类型=="短兵","unfolded dagger uses short-blade module");
        tick(40);check(ref.frame==15,"held Q never automatically toggles back");
        press(81);check(ref.frame==14 && actor.刀属性.power==220 && actor.防御力==120,"reverse starts with reduced power and no defense");
        check(actor.兵器动作类型=="棍棒","reverse immediately retires dagger module");
        tick(13);check(ref.frame==1 && actor.防御力==285,"defense returns only after fully folded");
        for(i=0;i<3;i++){press(81);tick(13);press(81);tick(13);}
        check(actor.刀属性.power==220 && actor.防御力==285,"repeated round trips do not accumulate stats");
        actor.攻击模式="手枪";tick();check(actor.防御力==120,"holster removes only baton defense");
        actor.攻击模式="兵器";tick();check(actor.防御力==285,"redraw reapplies baton defense once");
        actor.hp=0;tick();check(actor.防御力==120,"death removes conditional defense");
        actor.hp=100;tick();check(actor.防御力==285,"living redraw restores correct defense");
        saber._visible=false;tick();check(actor.防御力==120,"invisible weapon cannot defend");
        saber._visible=true;tick();
        _root.武器变形键=84;press(81);check(ref.frame==1,"old Q ignored after key remapping");
        press(84);check(ref.frame==2,"configured transform key remains authoritative");
        _root.暂停=true;tick(5);check(ref.frame==2,"paused game does not advance transformation");
        _root.暂停=false;tick(13);
        actor.攻击模式="手枪";tick();actor.攻击模式="兵器";tick();
        check(ref.frame==15 && actor.刀属性.power==330,"blade mode survives holstering within lifecycle");
        saber.removeMovieClip();saber=actor.attachMovie("刀-Codex-特勤警棍","saber",actor.getNextHighestDepth());
        actor.刀_引用=saber;actor.dispatcher.publish("刀_引用");
        check(saber._currentframe==15,"replacement placement immediately receives current visual frame");
        check(actor.刀属性.power==330,"placement event does not advance or alter combat state");
        press(84);tick(13);DressupInitializer.teardownLifeCycles(actor);
        check(actor.防御力==120 && actor.刀属性.power==330,"production teardown restores base power and unrelated defense");
        check(actor.兵器动作类型==item.actiontype,"teardown restores the original action type");
        check(actor.生命周期函数列表.length==0 && actor.dispatcher["_subCount"]==0,"production teardown leaves no callbacks or placement listeners");
        actor.buffManager.clearAllBuffs();actor.buffManager.destroy();actor.dispatcher.destroy();

        _root.武器变形键=81;
        ref=equip({level:5,mods:[]},50);actor.攻击模式="兵器";tick();
        check(actor.刀属性.power==349,"upgrade pipeline preserves external flat sharpness");
        check(actor.防御力==100+Math.floor(165*1.36),"conditional defense uses same upgrade factor");
        press(81);tick(13);check(actor.刀属性.power==499,"upgraded blade restores exact full power");
        press(81);tick(13);
        actor.buffManager.clearAllBuffs();actor.buffManager.destroy();actor.防御力=700;actor.buffManager=new BuffManager(actor,{});tick();
        check(actor.防御力==700+Math.floor(165*1.36),"BuffManager reset cannot leave old manager writing to actor");
        actor.version++;tick();
        check(ref.disposed && actor.防御力==700,"version invalidation retires defense");
        check(removed[removed.length-1]==ref.标签名,"invalid lifecycle also retires its scheduled task");
        teardown();

        ModRegistry.loadModData([{name:"sheriff-test-mod",stats:{flat:{power:40},percentage:{power:20}}}]);
        ref=equip({level:1,mods:["sheriff-test-mod"]},25);
        var expected:Object=ItemUtil.getItemData(item.name);expected.data.power=220;
        expected=EquipmentCalculator.calculatePure(expected,actor.刀.value,EquipmentConfigManager.getFullConfig(),ModRegistry.getModDict());
        check(actor.刀属性.power==expected.data.power+25,"modifier pipeline and external flat additions preserved in baton mode");
        actor.攻击模式="兵器";tick();press(81);tick(13);
        check(actor.刀属性.power==ref.fullPower,"modified blade restores its full calculated power");
        check(item.data.power==330 && item.data.defence==0,"runtime projection never mutates source item data");
        press(81);tick(13);
        var oldRef:Object=ref, oldManager:BuffManager=actor.buffManager;
        actor.removeMovieClip();actor=world.createEmptyMovieClip("actor",world.getNextHighestDepth());
        actor.防御力=999;actor.刀属性={power:777};actor.dispatcher=new EventDispatcher();
        SheriffBatonController.dispose(oldRef);
        check(actor.防御力==999 && actor.刀属性.power==777,"same-path replacement is untouched by stale teardown");
        check(oldRef.disposed,"stale lifecycle terminates");
        finish();
    }
    private static function finish():Void {
        if(finished)return;finished=true;
        if(actor){DressupInitializer.teardownLifeCycles(actor);if(actor.dispatcher)actor.dispatcher.destroy();}
        if(loader)loader.removeListener(listener);
        world.removeMovieClip();watchdog.removeMovieClip();
        _root.gameworld=old.world;_root.帧计时器=old.clock;_root.暂停=old.pause;_root.武器变形键=old.key;
        _root.按键输入检测=old.input;_root.控制目标=old.control;ItemUtil.itemDataDict=old.items;
        _root.装备生命周期函数.移除异常周期函数=old.cleanup;ModRegistry.loadModData(old.mods);
        trace("SheriffBatonTest Tests Passed: "+passed);
        trace("SheriffBatonTest Tests Failed: "+failed);
        _root.sheriffBatonTestComplete();
    }
}
