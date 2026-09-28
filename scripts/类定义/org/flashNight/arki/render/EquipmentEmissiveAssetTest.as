import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissiveController;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissionState;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.tooltip.builder.EquipmentLightingInfoBuilder;

// Real registered XML, production lifecycle construction, and published art.
// Actor values are disposable fixtures; original battle cycles are not driven.
class org.flashNight.arki.render.EquipmentEmissiveAssetTest {
    private static var passed:Number,failed:Number,completed:Number,finished:Boolean;
    private static var world:MovieClip,actor:MovieClip,weapon:MovieClip,watchdog:MovieClip;
    private static var oldWorld:Object,oldClock:Object,oldPause:Object,oldCleanup:Function,saved:Object;
    private static var definitions:Object,cases:Array,cycles:Array,listener:Object,loader:MovieClipLoader;
    private static var keys:Array = ["按键输入检测","随机整数","子弹属性初始化","获得父节点"];
    private static function check(ok:Boolean,label:String):Void {
        if (ok) passed++; else { failed++; trace("EquipmentEmissiveAssetTest FAIL: " + label); }
    }
    private static function rows():Array {
        var p:String=EquipmentLightBridge.payload(),out:Array=[];
        if(p!="") {var parts:Array=p.split(";");for(var i:Number=1;i<parts.length;i++)out.push(parts[i].split(","));}
        return out;
    }
    public static function runAllTests():Void {
        passed=failed=completed=0;finished=false;definitions={};saved={};
        oldWorld=_root.gameworld;oldClock=_root.帧计时器;oldPause=_root.暂停;
        oldCleanup=_root.装备生命周期函数.移除异常周期函数;
        for(var i:Number=0;i<keys.length;i++)saved[keys[i]]=_root[keys[i]];
        _root.按键输入检测=function():Boolean{return false;};
        _root.随机整数=function(lo:Number,hi:Number):Number{return lo;};
        _root.子弹属性初始化=function():Object{return {};};
        _root.获得父节点=function():MovieClip{return EquipmentEmissiveAssetTest.actor;};
        world=_root.createEmptyMovieClip("__emissiveAssetWorld",_root.getNextHighestDepth());_root.gameworld=world;_root.暂停=false;
        _root.帧计时器={当前帧数:0,帧率:30,taskManager:{addLifecycleTask:function(owner:Object,label:String,callback:Function,interval:Number,args:Array):Number {
            EquipmentEmissiveAssetTest.cycles.push({owner:owner,callback:callback,args:args});return EquipmentEmissiveAssetTest.cycles.length;
        }},移除生命周期任务:function():Void{}};
        _root.装备生命周期函数.移除异常周期函数=function():Void{};
        var caps:Object={equipmentLights:2,equipmentRadialLights:1};caps["native"]=true;EquipmentLightBridge.configure(caps);
        cases=[
            {prefix:"蓝晶",swf:"../flashswf/arts/things.swf"},
            {prefix:"次品蓝晶",swf:"../flashswf/arts/things.swf"},
            {name:"十文字大剑",linkage:"刀-十文字大剑",swf:"../flashswf/arts/things切割.swf",adapter:"static"},
            {name:"绝地武士佩剑",linkage:"刀-绝地武士佩剑",swf:"../flashswf/arts/things切割.swf",adapter:"static"},
            {name:"审判日夜闪",linkage:"刀-审判日夜闪",swf:"../flashswf/arts/things切割.swf",adapter:"static"},
            {name:"血色光剑天秤",linkage:"刀-Codex-血色光剑天秤",swf:"../flashswf/arts/new/Codex专用素材.swf",adapter:"blood",init:"血色光剑初始化"},
            {name:"主唱光剑",linkage:"刀-主唱光剑",swf:"../flashswf/arts/new/fs配置素材.swf",adapter:"vocalist",init:"主唱光剑初始化"},
            {name:"光剑天秤",linkage:"刀-光剑天秤",swf:"../flashswf/arts/things切割.swf",adapter:"libra",init:"光剑天秤初始化"},
            {name:"电感切割刃",linkage:"刀-电感切割刃",swf:"../flashswf/arts/new/fs配置素材.swf",adapter:"inductor",init:"电感切割刃初始化"},
            {name:"光刀狮子",linkage:"刀-光刀狮子",swf:"../flashswf/arts/things切割.swf",adapter:"lion",init:"光刀狮子初始化"},
            {name:"光刃摩羯",linkage:"刀-光刃摩羯",swf:"../flashswf/arts/things切割.swf",adapter:"capricorn",init:"光刃摩羯初始化"}
        ];
        watchdog=_root.createEmptyMovieClip("__emissiveAssetWatchdog",_root.getNextHighestDepth());watchdog.frames=0;
        watchdog.onEnterFrame=function():Void{if(++this.frames>=1200){EquipmentEmissiveAssetTest.check(false,"load timeout");EquipmentEmissiveAssetTest.finish();}};
        loadXml(0);
    }
    private static function loadXml(index:Number):Void {
        var files:Array=["防具_20-39级.xml","武器_刀_默认.xml","武器_刀_直剑.xml","武器_刀_长刀.xml","武器_刀_刀剑.xml","武器_刀_重斩.xml","武器_刀_狂野.xml","武器_刀_短兵.xml","武器_刀_短柄.xml","武器_刀_长棍.xml","武器_刀_双刀.xml","equipment_mods/高等材料_枪械专用.xml"];
        var doc:XML=new XML();doc.ignoreWhite=true;
        doc.onLoad=function(ok:Boolean):Void {
            if(EquipmentEmissiveAssetTest.finished)return;
            EquipmentEmissiveAssetTest.check(ok,"registered XML "+files[index]);
            if(!ok){EquipmentEmissiveAssetTest.finish();return;}
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            var items:Array=XMLParser.configureDataAsArray(index==11 ? parsed.mod : parsed.item);
            for(var i:Number=0;i<items.length;i++)EquipmentEmissiveAssetTest.definitions[items[i].name]=items[i];
            if(index+1<files.length)EquipmentEmissiveAssetTest.loadXml(index+1);
            else {
                var count:Number=0;
                for(var name:String in EquipmentEmissiveAssetTest.definitions) {
                    var item:Object=EquipmentEmissiveAssetTest.definitions[name];
                    if(item.lifecycle.attr_环境光.init.initRoutines=="装备自发光初始化")count++;
                }
                EquipmentEmissiveAssetTest.check(count==30,"actual XML parser sees all thirty configured independent emissions");
                var torchText:String=EquipmentLightingInfoBuilder.build(EquipmentEmissiveAssetTest.definitions["战术手电"],null,true).join("");
                EquipmentEmissiveAssetTest.check(torchText.indexOf("近身补光")>=0 && torchText.indexOf("+20")>=0 && torchText.indexOf("+25")>=0,"actual flashlight mod XML produces conditional defense and lighting text");
                var laserText:String=EquipmentLightingInfoBuilder.build(EquipmentEmissiveAssetTest.definitions["镭射瞄准具"],null,true).join("");
                EquipmentEmissiveAssetTest.check(laserText.indexOf("狭窄束带")>=0 && laserText.indexOf("闪避")==-1,"actual laser mod XML produces illumination without a defense bonus");
                EquipmentEmissiveAssetTest.loadAsset();
            }
        };
        doc.load("../data/items/"+files[index]);
    }
    private static function loadAsset():Void {
        cycles=[];actor=world.createEmptyMovieClip("actor"+completed,world.getNextHighestDepth());
        listener={onLoadInit:function(loaded:MovieClip):Void {
            loaded.onEnterFrame=function():Void {
                delete this.onEnterFrame;
                try{EquipmentEmissiveAssetTest.runLoaded();}
                catch(error){EquipmentEmissiveAssetTest.check(false,"unexpected "+error);EquipmentEmissiveAssetTest.finish();}
            };
        },onLoadError:function(loaded:MovieClip,error:String):Void{EquipmentEmissiveAssetTest.check(false,"SWF "+error);EquipmentEmissiveAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip(cases[completed].swf,actor),"submit real SWF "+completed);
    }
    private static function install(item:Object,slot:String,originalInit:String):Object {
        actor[slot]={name:item.name,value:{level:1,mods:[]}};actor[slot+"数据"]=item;actor[slot+"属性"]=item.data;
        var emission:Object=item.lifecycle.attr_环境光;
        check(emission.skillInteraction=="independent" && typeof(emission.init.initParam.radius)=="number","production parser retains typed independent config "+item.name);
        check(EquipmentLightingInfoBuilder.build(item,null,false).join("").indexOf("【照明效果】")>=0,"actual equipment XML exposes its lighting feature "+item.name);
        var life:Object={attr_环境光:emission};
        if(originalInit)for(var key:String in item.lifecycle) {
            var attr:Object=item.lifecycle[key];
            if(attr.init.initRoutines==originalInit)life.attr_original={skillInteraction:attr.skillInteraction,init:attr.init,bullet:attr.bullet};
        }
        actor.装载生命周期函数(life,slot);
        for(var i:Number=0;i<cycles.length;i++)if(cycles[i].args[0].装备类型==slot)return cycles[i].args[0];
        var cleanups:Array=actor.生命周期函数列表;
        for(i=0;i<cleanups.length;i++) {
            var ref:Object=cleanups[i].额外参数;
            if(ref.equipmentLight && ref.装备类型==slot)return ref;
        }
        return null;
    }
    private static function tick():Void {
        _root.帧计时器.当前帧数++;
        for(var i:Number=0;i<cycles.length;i++)cycles[i].callback.apply(cycles[i].owner,cycles[i].args);
    }
    private static function runLoaded():Void {
        actor._x=160;actor._y=240;actor.version=1;actor.hp=100;actor.mp=actor.mp满血值=100;
        actor.攻击模式="兵器";actor.状态="兵器站立";actor.man={兵器使用标签:true,兵器攻击标签:false};
        actor.主动战技={};actor.syncRefs={};actor.dispatcher=new EventDispatcher();actor.生命周期函数列表=[];actor.闪避加成=3;
        actor.装载生命周期函数=_root.主角函数.装载生命周期函数;
        var spec:Object=cases[completed];
        if(spec.prefix)runArmor(spec);else runWeapon(spec);
        check(actor.闪避加成==3,"emissive equipment does not receive the flashlight defense bonus");
        DressupInitializer.teardownLifeCycles(actor);
        check(rows().length==0 && actor.生命周期函数列表.length==0,"production teardown clears all contributions "+completed);
        actor.dispatcher.destroy();loader.removeListener(listener);actor.removeMovieClip();actor=null;completed++;
        if(completed<cases.length)loadAsset();else finish();
    }
    private static function runArmor(spec:Object):Void {
        var suffixes:Array=["面具","战斗服","手套","下装","鞋"];
        var slots:Array=["头部装备","上装装备","手部装备","下装装备","脚部装备"];
        var segments:Array=["面具","战斗服身体","手套左手","下装小腿","鞋"];
        var refs:Array=[];var maxEnergy:Number=0,maxRadius:Number=0;
        for(var i:Number=0;i<suffixes.length;i++) {
            var item:Object=definitions[spec.prefix+suffixes[i]],config:Object=item.lifecycle.attr_环境光.init.initParam;
            var part:MovieClip=actor.attachMovie("男变装-"+spec.prefix+segments[i],"part"+i,actor.getNextHighestDepth());
            check(part._parent===actor,"published armor component "+spec.prefix+segments[i]);
            refs.push(install(item,slots[i],null));maxEnergy=Math.max(maxEnergy,config.energy);maxRadius=Math.max(maxRadius,config.radius);
        }
        tick();var data:Array=rows();
        check(cycles.length==0 && data.length==1 && Number(data[0][2])==0,"five actual armor lifecycles produce one lamp without frame tasks");
        check(Number(data[0][7])==maxRadius && Number(data[0][9])<maxEnergy*1.251,"whole armor set has a bounded radius and intensity");
        if(spec.prefix=="蓝晶")trace("EquipmentEmissiveAssetTest LightingWire blue-set: "+EquipmentLightBridge.payload());
        var id:String=data[0][1];EquipmentEmissiveController.dispose(refs[0]);
        check(rows().length==1 && rows()[0][1]==id,"removing a real armor contribution preserves the actor lamp id");
    }
    private static function runWeapon(spec:Object):Void {
        weapon=actor.attachMovie(spec.linkage,"weapon",actor.getNextHighestDepth());actor.刀_引用=weapon;
        check(weapon._parent===actor && weapon.刀口位置1._parent,"published weapon and actual blade marker "+spec.name);
        weapon._xscale=weapon._yscale=20;
        var ref:Object=install(definitions[spec.name],"刀",spec.init),state:Object;
        check(cycles.length==1 && ref.equipmentLight.kind==0,"production loader creates one independent weapon emission");
        if(spec.adapter!="static") {
            state=EquipmentEmissionState.lookup(ref,spec.adapter);
            check(state!=null && state !== ref,"real original initializer publishes its authoritative state "+spec.adapter);
            if(spec.adapter=="blood") {
                state.bloodDrawn=true;_root.装备生命周期函数.血色光剑视觉更新(state);
                check(weapon.剑体.fxBreath._visible && weapon.剑体.fxFlow._visible,"actual blood blade breath and flow agree with drawn state");
            } else if(spec.adapter=="vocalist") {
                state.animFrame=state.animDuration;_root.装备生命周期函数.主唱光剑动画更新(state);
            } else if(spec.adapter=="libra") {
                state.当前形态="攻势形态";state.当前动画帧=15;_root.装备生命周期函数.光剑天秤视觉更新(state);
            } else if(spec.adapter=="inductor") {
                state.当前帧=state.动画时长;state.动画帧=state.动画时长;_root.装备生命周期函数.电感切割刃视觉更新(state);
            } else actor.dispatcher.publish("WeaponSkill","兵器");
        }
        // Normalize fixture placement while preserving the actual authored hierarchy,
        // marker shape and affine transform. This is not a gameplay pose acceptance.
        var mark:MovieClip=weapon.刀口位置1,rect:Object=mark.getRect(mark);
        var point:Object={x:(rect.xMin+rect.xMax)*0.5,y:(rect.yMin+rect.yMax)*0.5};
        mark.localToGlobal(point);world.globalToLocal(point);weapon._x+=250-point.x;weapon._y+=185-point.y;
        tick();var data:Array=rows();
        check(data.length==1 && Number(data[0][2])==0,"actual weapon projects one active radial light "+spec.name);
        check(Math.abs(Number(data[0][3])-250)<0.1 && Math.abs(Number(data[0][4])-185)<0.1,"real blade marker reaches the world-space snapshot");
        var oldAlpha:Number=weapon._alpha;actor.man.兵器使用标签=false;tick();
        check(rows().length==0 && weapon._alpha==oldAlpha,"stowing removes illumination without rewriting authored art");
        actor.man.兵器使用标签=true;tick();actor.hp=0;
        check(rows().length==0,"dead actual-material actor leaves no persistent light");actor.hp=100;
        if(spec.adapter=="blood" || spec.name=="十文字大剑") {
            var suffixes:Array=["面具","战斗服","手套","下装","鞋"],slots:Array=["头部装备","上装装备","手部装备","下装装备","脚部装备"];
            for(var i:Number=0;i<slots.length;i++)install(definitions["蓝晶"+suffixes[i]],slots[i],null);
            point.x=(rect.xMin+rect.xMax)*0.5;point.y=(rect.yMin+rect.yMax)*0.5;
            mark.localToGlobal(point);world.globalToLocal(point);weapon._x+=180-point.x;weapon._y+=165-point.y;
            tick();data=rows();
            check(data.length==(spec.adapter=="blood" ? 2 : 1),"actual XML armor/weapon combination keeps the intended color grouping");
            trace("EquipmentEmissiveAssetTest LightingWire "+(spec.adapter=="blood" ? "blue-blood" : "blue-same")+": "+EquipmentLightBridge.payload());
        }
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete watchdog.onEnterFrame;
        if(actor){DressupInitializer.teardownLifeCycles(actor);actor.dispatcher.destroy();}
        if(loader)loader.removeListener(listener);
        EquipmentLightBridge.disconnect();world.removeMovieClip();watchdog.removeMovieClip();
        _root.gameworld=oldWorld;_root.帧计时器=oldClock;_root.暂停=oldPause;_root.装备生命周期函数.移除异常周期函数=oldCleanup;
        for(var i:Number=0;i<keys.length;i++)_root[keys[i]]=saved[keys[i]];
        trace("EquipmentEmissiveAssetTest Fixtures Completed: "+completed);
        trace("EquipmentEmissiveAssetTest Tests Passed: "+passed);
        trace("EquipmentEmissiveAssetTest Tests Failed: "+failed);
        _root.equipmentEmissiveAssetComplete();
    }
}
