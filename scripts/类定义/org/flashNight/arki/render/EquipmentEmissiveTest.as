import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissiveController;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissionState;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController;
import org.flashNight.neur.Event.EventDispatcher;

class org.flashNight.arki.render.EquipmentEmissiveTest {
    private static var passed:Number, failed:Number;
    private static function check(value:Boolean,label:String):Void {
        if (value) passed++; else { failed++; trace("EquipmentEmissiveTest FAIL: " + label); }
    }
    private static function actor(world:MovieClip,name:String):MovieClip {
        var a:MovieClip = world.createEmptyMovieClip(name,world.getNextHighestDepth());
        a._x = 160; a._y = 220; a.hp = 100; a.version = 1; a.攻击模式 = "兵器";
        a.man = {兵器使用标签:true,兵器攻击标签:false}; a.dispatcher = new EventDispatcher(); a.生命周期函数列表 = [];
        var blade:MovieClip = a.createEmptyMovieClip("blade",a.getNextHighestDepth()); a.刀_引用 = blade;
        var mark:MovieClip = blade.createEmptyMovieClip("刀口位置1",blade.getNextHighestDepth()); mark._x = 20; mark._y = -75;
        mark.beginFill(0); mark.moveTo(-5,-20); mark.lineTo(5,-20); mark.lineTo(5,20); mark.lineTo(-5,20); mark.endFill();
        var gun:MovieClip = a.createEmptyMovieClip("gun",a.getNextHighestDepth()); a.长枪_引用 = gun;
        var muzzle:MovieClip = gun.createEmptyMovieClip("枪口位置",gun.getNextHighestDepth()); muzzle._x = 45; muzzle._y = -70;
        return a;
    }
    private static function refFor(a:MovieClip,slot:String):Object {
        if (!a[slot]) a[slot] = {name:"fixture-" + slot,value:{mods:[]}};
        return {自机:a,装备类型:slot,生命周期函数列表:a.生命周期函数列表};
    }
    private static function body(ref:Object):Boolean {
        return EquipmentEmissiveController.initialize(ref,{group:"body",radius:100,energy:0.4,color:0x6688FF});
    }
    private static function blade(ref:Object,color:Number,adapter:String):Boolean {
        return EquipmentEmissiveController.initialize(ref,{group:"blade",radius:60,energy:0.5,color:color,adapter:adapter});
    }
    private static function rows():Array {
        var p:String = EquipmentLightBridge.payload();
        var out:Array = [];
        if (p != "") {
            var parts:Array = p.split(";");
            for (var i:Number = 1; i < parts.length; i++) out.push(parts[i].split(","));
        }
        return out;
    }
    private static function hasId(data:Array,id:Number):Boolean {
        for (var i:Number = 0; i < data.length; i++) if (Number(data[i][1]) == id) return true;
        return false;
    }
    private static function idSet(data:Array):String {
        var ids:Array = [];
        for (var i:Number = 0; i < data.length; i++) ids.push(Number(data[i][1]));
        ids.sort(Array.NUMERIC); return ids.join(",");
    }
    private static function benchmark(world:MovieClip,pieces:Number,moving:Boolean,unitCount:Number,withBlade:Boolean):Object {
        clearActors(world);EquipmentLightBridge.resetScene();
        if (unitCount == undefined) unitCount = 20;
        var slots:Array=["头部装备","上装装备","手部装备","下装装备","脚部装备"];
        var units:Array=[], swords:Array=[];
        for(var n:Number=0;n<unitCount;n++) {
            var unit:MovieClip=actor(world,"perf"+pieces+"_"+n);
            unit._x=140+(n%5)*35;unit._y=220+Math.floor(n/5)*5;
            units.push(unit);
            for(var p:Number=0;p<pieces;p++)body(refFor(unit,slots[p]));
            if(withBlade) {var sword:Object=refFor(unit,"刀");blade(sword,0xFF5566,"static");swords.push(sword);}
        }
        var elapsed:Number=0, durations:Array=[];
        for(var iteration:Number=0;iteration<120;iteration++) {
            if (moving) {
                _root.帧计时器.当前帧数++;
                for(n=0;n<units.length;n++)units[n]._x=140+(n%5)*35+(iteration%20)*0.25;
            }
            if(withBlade)for(n=0;n<swords.length;n++)EquipmentEmissiveController.update(swords[n]);
            var start:Number=getTimer();
            EquipmentLightBridge.payload();
            var duration:Number=getTimer()-start;elapsed+=duration;durations.push(duration);
        }
        durations.sort(Array.NUMERIC);
        var result:Object=EquipmentLightBridge.getStats();result.meanPayloadMs=elapsed/120;
        var output:Array=rows();result.bounded=true;
        for(var i:Number=0;i<output.length;i++)if(Number(output[i][7])!=100 || Number(output[i][9])>0.5001)result.bounded=false;
        trace("EquipmentEmissiveTest PayloadBenchmark sources="+result.activeSources+" candidates="+result.candidates
            +" admitted="+result.admitted+" meanMs="+result.meanPayloadMs+" p95Ms="+durations[113]
            +" moving="+!!moving+" actors="+unitCount+" blades="+!!withBlade+" iterations=120 (payload CPU only; not game FPS)");
        EquipmentLightBridge.profilePayloadForTests(true);
        for(iteration=0;iteration<120;iteration++)EquipmentLightBridge.payload();
        var phases:Object=EquipmentLightBridge.profilePayloadForTests(false);
        trace("EquipmentEmissiveTest PayloadProfile sources="+result.activeSources+" calls="+phases.calls
            +" validationMs="+phases.validation/120+" collectionMs="+phases.collection/120
            +" aggregationMs="+phases.aggregation/120+" admissionMs="+phases.admission/120
            +" serializationMs="+phases.serialization/120);
        return result;
    }
    private static function clearActors(world:MovieClip):Void {
        var children:Array=[];
        for(var name:String in world)if(typeof(world[name])=="movieclip" && world[name]._parent===world)children.push(world[name]);
        for(var i:Number=0;i<children.length;i++)children[i].removeMovieClip();
    }
    private static function cacheRegressions(world:MovieClip):Void {
        clearActors(world);EquipmentLightBridge.resetScene();
        var a:MovieClip=actor(world,"cacheHero");_root.控制目标="cacheHero";
        var torso:Object=refFor(a,"上装装备"),legs:Object=refFor(a,"下装装备");
        EquipmentEmissiveController.initialize(torso,{group:"body",radius:100,energy:0.4,color:0xFF0000});
        EquipmentEmissiveController.initialize(legs,{group:"body",radius:80,energy:0.2,color:0x0000FF});
        var first:String=EquipmentLightBridge.payload();
        check(first==EquipmentLightBridge.payload(),"an unchanged snapshot retains byte-identical radial fields");
        a._x=177.25;a._y=231.5;
        var data:Array=rows(),row:Array=data[0];
        check(Number(row[3])==a._x && Number(row[4])==a._y-75,"cached radial record follows subpixel actor movement in the same tick");
        a.中心高度=40;a.身高=175;
        check(Number(rows()[0][4])==a._y-40,"body center changes invalidate the position without a lifecycle tick");
        var oldItem:Object=a.上装装备;
        a.上装装备={name:oldItem.name,value:{mods:[]}};
        row=rows()[0];
        check(EquipmentLightBridge.getStats().activeSources==1 && Number(row[7])==80 && Number(row[9])==0.2 && Number(row[12])==1,
            "same-frame item replacement removes the dominant radius energy and color from the cache");
        a.上装装备=oldItem;body(torso);
        a.下装装备.value.mods.push("mod-a");rows();
        check(EquipmentLightBridge.getStats().activeSources==1,"a mod mutation invalidates one member of a cached body group");
        body(legs);a.下装装备.value.mods[0]="mod-b";rows();
        check(EquipmentLightBridge.getStats().activeSources==1,"same-length mod edits cannot reuse cached body membership");
        EquipmentEmissiveController.dispose(torso);
        var builtin:Object=refFor(a,"上装装备"),plugin:Object=refFor(a,"上装装备");plugin.来源插件="test";
        EquipmentEmissiveController.initialize(builtin,{group:"body",radius:110,energy:0.6,color:0xFF0000});
        EquipmentEmissiveController.initialize(plugin,{group:"body",radius:70,energy:0.2,color:0x0000FF});
        row=rows()[0];check(Number(row[7])==110 && Number(row[9])==0.6,"builtin source owns a shared body slot");
        EquipmentLightBridge.hide(builtin);row=rows()[0];
        check(Number(row[7])==70 && Number(row[9])==0.2 && Number(row[12])==1,"hidden builtin immediately hands its body slot to the plugin");
        EquipmentLightBridge.sampleRadial(builtin,null,1,0xFF0000);row=rows()[0];
        check(Number(row[7])==110 && Number(row[9])==0.6 && Number(row[10])==1,"restored builtin invalidates the plugin aggregate and wire tail");
        var sword:Object=refFor(a,"刀");blade(sword,0xFF0000,"static");
        row=rows()[0];check(rows().length==1 && Number(row[9])>0.6,"compatible blade modifies the cached body union");
        EquipmentEmissiveController.dispose(sword);row=rows()[0];
        check(Number(row[7])==110 && Number(row[9])==0.6,"removing the blade restores the cached body base and serialized tail");
        world._x=31;world._y=11;world._xscale=world._yscale=75;
        row=rows()[0];check(Number(row[3])==a._x && Number(row[4])==a._y-40,"camera zoom and translation do not contaminate world-space body coordinates");
        world._x=-4000;check(rows().length==0,"camera movement culls a previously cached radial record");
        world._x=0;world._y=0;world._xscale=world._yscale=100;
        check(rows().length==1,"cached body reappears immediately when the camera returns");
        clearActors(world);EquipmentLightBridge.resetScene();
        var parent:MovieClip=world.createEmptyMovieClip("nested",world.getNextHighestDepth());parent._x=70;parent._y=20;parent._xscale=125;parent._yscale=80;
        a=actor(parent,"nestedHero");torso=refFor(a,"上装装备");body(torso);
        var point:Object={x:0,y:0};a.localToGlobal(point);world.globalToLocal(point);row=rows()[0];
        check(Math.abs(Number(row[3])-point.x)<0.0001 && Math.abs(Number(row[4])-point.y+75)<0.0001,"nested actors retain transform conversion instead of the direct-parent shortcut");
        parent._visible=false;check(rows().length==0,"hidden ancestor revokes a cached nested body immediately");
        parent._visible=true;_root.暂停=true;a.hp=0;
        check(rows().length==0,"paused death bypasses cached membership and lamp residency");
        _root.暂停=false;
    }
    private static function brightnessRegressions(world:MovieClip):Void {
        clearActors(world);EquipmentLightBridge.resetScene();
        var a:MovieClip=actor(world,"brightnessHero");a._x=180;a._y=240;_root.控制目标=a._name;
        var slots:Array=["头部装备","上装装备","手部装备","下装装备","脚部装备"];
        var energies:Array=[0.56,0.84,0.48,0.72,0.44],radii:Array=[115,160,125,140,115];
        for(var i:Number=0;i<slots.length;i++)EquipmentEmissiveController.initialize(refFor(a,slots[i]),{group:"body",radius:radii[i],energy:energies[i],color:0x7496F0});
        var data:Array=rows(),id:Number=Number(data[0][1]);
        check(Number(data[0][7])==160 && Number(data[0][9])==1.05,"full blue armor provides the brighter bounded near fill");
        check(Number(data[0][10])>0.54 && Number(data[0][12])>Number(data[0][10])+0.25,"neutral fill preserves the blue hue while lifting material detail");
        var sword:Object=refFor(a,"刀");EquipmentEmissiveController.initialize(sword,{group:"blade",radius:135,energy:0.99,color:0x7496F0});
        data=rows();check(data.length==1 && Number(data[0][9])==1.5,"compatible armor and blade share the ordinary muzzle peak");
        check(Number(data[0][1])==id,"raising a merged peak does not replace the resident body identity");
        EquipmentLightBridge.sampleRadial(sword,a.刀_引用.刀口位置1,1,0xFF526B);data=rows();
        check(data.length==2 && Number(data[0][10])!=Number(data[1][10]),"red blade and blue armor retain separate tints");
        var bounded:Boolean=true;
        for(var x:Number=0;x<550;x+=5)for(var y:Number=0;y<400;y+=5) {
            var sum:Number=0;
            for(i=0;i<data.length;i++) {
                var dx:Number=x-Number(data[i][3]),dy:Number=y-Number(data[i][4]);
                var falloff:Number=Math.max(0,1-(dx*dx+dy*dy)/(Number(data[i][7])*Number(data[i][7])));
                sum+=Number(data[i][9])*falloff*falloff;
            }
            if(sum>1.5003)bounded=false;
        }
        check(bounded,"separate colors obey the combined muzzle peak across the overlap field");
        a.刀_引用.刀口位置1._x=0;EquipmentLightBridge.sampleRadial(sword,a.刀_引用.刀口位置1,1,0xFF526B);data=rows();
        check(Number(data[0][9])+Number(data[1][9])<1.5002,"coincident colored sources share one total peak budget");
        a.man.兵器攻击标签=true;
        EquipmentEmissiveController.noteTrail(a,a.刀_引用,[{edge1:{x:180,y:165},edge2:{x:180,y:165}}],world);data=rows();
        check(data.length==2 && Number(data[0][9])+Number(data[1][9])<1.5002,"blade-trail pulse stays inside the same combined peak");
        _root.帧计时器.当前帧数+=4;a.man.兵器攻击标签=false;a.刀_引用.刀口位置1._x=310;
        EquipmentLightBridge.sampleRadial(sword,a.刀_引用.刀口位置1,1,0xFF526B);data=rows();
        var restored:Boolean=false;
        for(i=0;i<data.length;i++)if(Number(data[i][1])==id)restored=Number(data[i][9])==1.05;
        check(data.length==2 && restored,"nonoverlapping lights recover their independent base strength");
        EquipmentEmissiveController.dispose(sword);
        check(Number(rows()[0][9])==1.05,"ending the blade contribution cannot leave dimmed armor cached");
    }
    public static function runAllTests():Void {
        passed = failed = 0;
        var oldWorld = _root.gameworld, oldClock = _root.帧计时器, oldPause = _root.暂停, oldHero = _root.控制目标;
        var world:MovieClip = _root.createEmptyMovieClip("__emissiveFixture",_root.getNextHighestDepth());
        _root.gameworld = world; _root.帧计时器 = {当前帧数:0}; _root.暂停 = false; _root.控制目标 = "hero";
        EquipmentLightBridge.disconnect();
        try {
            var a:MovieClip = actor(world,"hero");
            var slots:Array = ["头部装备","上装装备","手部装备","下装装备","脚部装备"];
            var refs:Array = []; var i:Number;
            for (i = 0; i < slots.length; i++) { var r:Object = refFor(a,slots[i]); refs.push(r); check(body(r),"body bind " + slots[i]); }
            var caps:Object = {equipmentLights:2}; caps["native"] = true; EquipmentLightBridge.configure(caps);
            check(rows().length == 0,"old host does not receive an unknown radial kind");
            caps.equipmentRadialLights = 1; EquipmentLightBridge.configure(caps);
            var data:Array = rows(), first:Array = data[0]; var id:Number = Number(first[1]);
            check(data.length == 1 && Number(first[2]) == 0 && first.length == 17,"five worn pieces share one radial record");
            check(Number(first[3]) == 160 && Number(first[4]) == 145,"body centre uses the actual actor");
            check(Number(first[5]) == 0 && Number(first[6]) == 0 && Number(first[8]) == 0 && Number(first[15]) == 0,"radial reserved and near fields are zero");
            check(Number(first[7]) == 100 && Math.abs(Number(first[9])-0.5)<0.000001,"pieces have a bounded bonus and do not add their radii");
            check(EquipmentLightBridge.getStats().activeSources == 5 && EquipmentLightBridge.getStats().admitted == 1,"aggregation diagnostics distinguish contributors and lamps");
            var hidden:MovieClip=actor(world,"hiddenArmor");hidden._visible=false;var hiddenRef:Object=refFor(hidden,"上装装备");
            var hiddenBound:Boolean=body(hiddenRef);var hiddenBefore:Number=rows().length;hidden._visible=true;
            check(hiddenBound && hiddenBefore==1 && rows().length==2,"armor initialized while hidden becomes visible without a frame task");
            EquipmentEmissiveController.dispose(hiddenRef);hidden.removeMovieClip();
            EquipmentEmissiveController.dispose(refs[0]);
            check(rows().length == 1 && Number(rows()[0][1]) == id,"removing one piece keeps the actor light id");
            for (i = 1; i < 4; i++) EquipmentEmissiveController.dispose(refs[i]);
            check(Math.abs(Number(rows()[0][9])-0.4)<0.000001,"one remaining piece retains its own energy");
            a.version = 2; check(rows().length == 0,"old equipment generation immediately disappears");
            var torso:Object = refFor(a,"上装装备"); body(torso);
            check(Number(rows()[0][1]) == id,"rebuilding worn equipment on the same actor keeps the group id");
            var cleanupCount:Number = a.生命周期函数列表.length; body(torso); body(torso);
            check(a.生命周期函数列表.length == cleanupCount,"reinitialization does not grow the shared cleanup list");
            a.上装装备.value.mods.push("changed"); check(rows().length == 0,"same-frame mod changes invalidate a contribution");
            body(torso);a.上装装备.value.mods[0]="replaced";check(rows().length==0,"same-length in-place mod replacement also invalidates the source");
            body(torso); a._visible = false; check(rows().length == 0,"hidden actor leaves no body light");
            a._visible = true; EquipmentEmissiveController.update(torso); world._visible = false;
            check(rows().length == 0,"hidden world leaves no body light"); world._visible = true;
            a._x = -2000; EquipmentEmissiveController.update(torso); check(rows().length == 0,"offscreen body is culled by radius");
            a._x = 160; EquipmentEmissiveController.update(torso); _root.暂停 = true; _root.帧计时器.当前帧数 = 100;
            check(rows().length == 1,"pause retains a valid body light");
            EquipmentLightBridge.disconnect();check(rows().length==0,"transport disconnect revokes persistent armor projection");
            EquipmentLightBridge.configure(caps);check(rows().length==1,"init-only armor resumes after reconnect without a lifecycle tick");
            EquipmentLightBridge.resetScene();
            check(rows().length == 1,"reset while paused retains the valid init-only body source");
            _root.帧计时器.当前帧数 = 104;_root.暂停 = false; check(rows().length == 1,"static armor persists without per-piece frame callbacks");
            EquipmentEmissiveController.update(torso); a.hp = 0; check(rows().length == 0,"death removes illumination without waiting for a callback");
            a.hp = 100; EquipmentEmissiveController.update(torso);
            var sword:Object = refFor(a,"刀"); blade(sword,0x6688FF,"static");
            check(rows().length == 1,"nearby same-color blade contribution merges with body");
            blade(sword,0xFF5566,"static"); data = rows();
            check(data.length == 2,"red blade keeps a distinct source beside blue armor");
            a.man.兵器使用标签 = false; a.攻击模式 = "长枪";
            var torch:Object = refFor(a,"长枪"); EquipmentLightController.initialize(torch,{kind:"flashlight"});
            data = rows(); check(data.length == 1 && Number(data[0][2]) == 1,"strong flashlight near fill covers redundant weak armor light");
            check(Number(data[0][10]) == 1 && Number(data[0][11]) > 0.9,"armor cannot recolor the flashlight cone");
            EquipmentLightController.dispose(torch); check(rows().length == 1 && Number(rows()[0][2]) == 0,"armor returns when the flashlight leaves");
            EquipmentEmissiveController.dispose(torso); a.man.兵器使用标签 = true; a.攻击模式 = "兵器";
            EquipmentEmissiveController.update(sword); data = rows(); id = Number(data[0][1]);
            a.man.兵器攻击标签 = true;
            var trail:Array = [{edge1:{x:180,y:120},edge2:{x:200,y:140}}];
            EquipmentEmissiveController.noteTrail(a,a.刀_引用,trail,world);
            var energy:Number = Number(rows()[0][9]);
            check(energy > 0.5 && energy < 0.6 && Number(rows()[0][1]) == id,"a trail boosts the existing light without a new id");
            for (i = 1; i < 50; i++) trail.push(trail[0]);
            EquipmentEmissiveController.noteTrail(a,a.刀_引用,trail,world);
            check(rows().length == 1 && Number(rows()[0][9]) == energy,"fifty segments cannot become fifty lights or stack energy");
            _root.暂停 = true; _root.帧计时器.当前帧数 = 200;
            check(Number(rows()[0][9]) == energy,"pause freezes the trail envelope");
            a.刀_引用._visible=false;check(rows().length==0,"hiding the actual blade during pause immediately removes its light");
            a.刀_引用._visible=true;EquipmentEmissiveController.update(sword);
            check(Number(rows()[0][9])==energy,"paused pose refresh preserves the frozen trail envelope");
            _root.暂停 = false; _root.帧计时器.当前帧数 = 204; a.man.兵器攻击标签 = false; EquipmentEmissiveController.update(sword);
            check(Math.abs(Number(rows()[0][9])-0.5)<0.000001,"trail energy returns to the base after four ticks");
            a.man.兵器使用标签 = false; EquipmentEmissiveController.update(sword); check(rows().length == 0,"stowing immediately removes the sword and its envelope");
            a.man.兵器使用标签 = true;
            EquipmentEmissiveController.update(sword);_root.帧计时器.当前帧数+=3;
            check(rows().length==0,"dynamic weapon sampling still expires without a heartbeat");
            var authority:Object = refFor(a,"刀"); authority.bloodActive = true; authority.bloodDrawn = false;
            EquipmentEmissionState.bind(authority,"blood"); blade(sword,0xFF5566,"blood"); check(rows().length == 0,"blood blade reads its actual drawn state");
            authority.bloodDrawn = true; EquipmentEmissiveController.update(sword); check(rows().length == 1,"blood blade can illuminate without activating a battle skill");
            authority.weaponMode = "话筒支架"; authority.animFrame = 30; authority.animDuration = 30;
            EquipmentEmissionState.bind(authority,"vocalist"); blade(sword,0xFF8866,"vocalist"); check(rows().length == 0,"microphone mode is not a lightsaber");
            authority.weaponMode = "光剑"; authority.animFrame = 1; EquipmentEmissiveController.update(sword); check(rows().length == 0,"collapsed singer blade remains dark");
            authority.animFrame = 15; EquipmentEmissiveController.update(sword); energy = Number(rows()[0][9]);
            authority.animFrame = 30; EquipmentEmissiveController.update(sword); check(Number(rows()[0][9]) > energy,"singer light follows extension progress");
            authority.当前形态 = "默认形态"; authority.isSkillInCd = false; authority.天秤切换次数 = 7;
            EquipmentEmissionState.bind(authority,"libra"); blade(sword,0xFFFFFF,"libra"); check(rows().length == 0,"default Libra respects its existing inactive window");
            authority.isSkillInCd = true; EquipmentEmissiveController.update(sword); check(rows().length == 1 && Number(rows()[0][12]) == 1,"Libra cooldown uses blue illumination");
            authority.当前形态 = "攻势形态"; EquipmentEmissiveController.update(sword); check(Number(rows()[0][10]) == 1 && Number(rows()[0][11]) < 0.6,"Libra offensive form uses red illumination");
            authority.当前形态 = "守御形态"; EquipmentEmissiveController.update(sword); check(Number(rows()[0][11]) > 0.7 && authority.天秤切换次数 == 7,"visual observation preserves battle state");
            authority.当前帧 = 1; authority.动画时长 = 15; authority.过载值 = 0; authority.过载阈值 = 120;
            EquipmentEmissionState.bind(authority,"inductor"); blade(sword,0xFFFFFF,"inductor"); check(rows().length == 0,"folded inductor stays dark");
            authority.当前帧 = 15; EquipmentEmissiveController.update(sword); check(Number(rows()[0][12]) == 1,"active inductor uses blue illumination");
            authority.过载值 = 120; EquipmentEmissiveController.update(sword); check(Number(rows()[0][10]) == 1 && authority.过载值 == 120,"overload color does not consume energy or trigger damage");
            authority.draw = false; EquipmentEmissionState.bind(authority,"lion"); blade(sword,0xFFAA66,"lion"); check(rows().length == 0,"lion waits for its real activation");
            authority.draw = true; EquipmentEmissiveController.update(sword); check(rows().length == 1,"lion follows the activated lifecycle state");
            authority.draw = 1; EquipmentEmissionState.bind(authority,"capricorn"); blade(sword,0x99FF66,"capricorn"); check(rows().length == 1,"Capricorn reads its remaining activation window");
            authority.draw = 0; EquipmentEmissiveController.update(sword); check(rows().length == 0,"Capricorn stops when its window ends");
            authority.draw = 150; EquipmentEmissiveController.update(sword); EquipmentEmissionState.release(authority); EquipmentEmissiveController.update(sword);
            check(rows().length == 0,"removed state authority cannot leave a conditional light alive");
            check(!EquipmentEmissiveController.initialize(sword,{group:"blade",adapter:"unknown"}),"unknown adapter fails closed");
            check(!EquipmentLightController.initialize(torch,{kind:"body"}),"gun controller rejects unknown kinds instead of treating them as lasers");
            var oldRef:Object = torso; var oldState:Object = authority; a.removeMovieClip();
            a = actor(world,"hero"); var newRef:Object = refFor(a,"上装装备"); body(newRef);
            var newState:Object = refFor(a,"刀"); newState.draw = true; EquipmentEmissionState.bind(newState,"lion");
            EquipmentEmissiveController.dispose(oldRef); EquipmentEmissionState.release(oldState);
            check(rows().length == 1 && EquipmentEmissionState.lookup(newState,"lion") === newState,"late cleanup cannot mutate a same-path replacement actor");
            clearActors(world);EquipmentLightBridge.resetScene();
            var crowd:Array = [];
            for (i = 0; i < 17; i++) { var npc:MovieClip = actor(world,"npc" + i); npc._x = 150 + i*5; r = refFor(npc,"上装装备"); body(r); crowd.push(r); }
            var previous:Array = rows(); check(previous.length == 16 && EquipmentLightBridge.getStats().dropped == 1,"visible crowd obeys the sixteen-lamp budget");
            var hero:MovieClip = actor(world,"priorityHero"); hero._x = 30; _root.控制目标 = "priorityHero";
            var heroRef:Object = refFor(hero,"上装装备"); body(heroRef); data = rows();
            check(data.length == 16 && hasId(data,heroRef.equipmentLight.lightGroup.id),"a later player can displace an earlier NPC");
            var retained:Number = 0; for (i = 0; i < previous.length; i++) if (hasId(data,Number(previous[i][1]))) retained++;
            check(retained == 15,"priority admission preserves the other fifteen residents");
            var waiting:Object;
            for (i = 0; i < crowd.length; i++) if (!hasId(data,crowd[i].equipmentLight.lightGroup.id)) waiting = crowd[i];
            var stable:String = idSet(data); waiting.自机._x = Stage.width * 0.5; waiting.自机._y = Stage.height * 0.5 + 75;
            _root.帧计时器.当前帧数++;
            for (i = 0; i < crowd.length; i++) EquipmentEmissiveController.update(crowd[i]); EquipmentEmissiveController.update(heroRef);
            check(idSet(rows()) == stable,"same-tier arrivals cannot churn seats during minimum residency");
            _root.帧计时器.当前帧数+=9;
            for (i = 0; i < crowd.length; i++) EquipmentEmissiveController.update(crowd[i]); EquipmentEmissiveController.update(heroRef);
            check(hasId(rows(),waiting.equipmentLight.lightGroup.id),"a clearly closer NPC can enter after residency and hysteresis");
            hero.hp = 0; check(!hasId(rows(),heroRef.equipmentLight.lightGroup.id),"death bypasses budget residency immediately");
            var single:Object=benchmark(world,1),full:Object=benchmark(world,5);
            check(single.activeSources==20 && full.activeSources==100 && single.candidates==20 && full.candidates==20
                && single.admitted==16 && full.admitted==16,"five times the worn contributors do not multiply native lamps");
            check(single.bounded && full.bounded,"dense full armor still respects radius and intensity bounds");
            benchmark(world,5,true,20);benchmark(world,5,true,5);benchmark(world,5,true,1);
            benchmark(world,5,true,20,true);
            cacheRegressions(world);
            brightnessRegressions(world);
            clearActors(world);EquipmentLightBridge.resetScene();_root.控制目标="capacityHero";
            for(i=0;i<52;i++) {
                var capped:MovieClip=actor(world,"capped"+i);
                for(var part:Number=0;part<5;part++)body(refFor(capped,slots[part]));
            }
            check(EquipmentLightBridge.getStats().registered==256,"raw contributor ceiling remains bounded");
            var lateHero:MovieClip=actor(world,"capacityHero"),lateRef:Object=refFor(lateHero,"上装装备");body(lateRef);
            check(EquipmentLightBridge.getStats().registered==256 && hasId(rows(),lateRef.equipmentLight.lightGroup.id),
                "a late player is protected even when the raw contributor registry is full");
            EquipmentLightBridge.disconnect(); check(rows().length == 0,"disconnect clears every persistent source");
        } catch (error) { check(false,"exception " + error); }
        world.removeMovieClip(); _root.gameworld = oldWorld; _root.帧计时器 = oldClock; _root.暂停 = oldPause; _root.控制目标 = oldHero;
        EquipmentLightBridge.disconnect();
        trace("EquipmentEmissiveTest Tests Passed: " + passed);
        trace("EquipmentEmissiveTest Tests Failed: " + failed);
    }
}
