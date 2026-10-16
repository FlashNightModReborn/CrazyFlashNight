import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.ReloadEventComponent;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.neur.Event.EventDispatcher;
import flash.display.BitmapData;
import flash.geom.Matrix;

/** Published native timelines, with isolated in-memory damage and world fixtures. */
class org.flashNight.arki.unit.Action.Melee.Cf6SoldierAssetTest {
    private static var library:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var passed:Number,failed:Number,ticks:Number;
    private static var ready:Boolean,finished:Boolean;
    private static var cases:Array,probes:Array,images:Object,sourceLibraries:Array,weaponXml:XML,defaults:Array;
    private static var loadedWeapons:Number=0;
    private static var link:String="敌人-CF6特种兵";

    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[TEST_FAIL] Cf6SoldierAssetTest: "+label);}
    }
    private static function record():Object {
        return {shots:0,stabs:0,done:0,deathChecks:0,removed:false,physics:0,landings:0,
            powerOk:true,areaOk:true,contractOk:true,muzzleOk:true,shotFrames:"",shotTicks:[],ammoBefore:0};
    }
    public static function runAllTests():Void {
        passed=failed=ticks=0;ready=finished=false;cases=[];probes=[];images={};
        library=_root.createEmptyMovieClip("__soldierLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__soldierTestDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;_root.暂停=false;
        _root.控制目标="__no_player";_root.控制目标全自动=false;_root.是否阴影=true;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};
        _root.add2map=function():Void {};_root.add2map2=function():Void {};
        _root.敌人函数={配置音效:function():Void {},
            大学军校学员随机兵器表:["M4A1改","AK74战术版","M4A1战术版","DD MK18战术版"],
            状态改变:function(state:String):Void {if(this.状态==state)return;this.状态=state;this.gotoAndStop(state);}};
        _root.主角函数={长枪射击:WeaponFireCore.LONG_GUN_SHOOT,
            初始化长枪射击函数:function():Void {ShootInitCore.initLongGun(this,this._parent);},
            清理射击任务:function(unit:MovieClip):Void {ShootCore.cleanup(unit);},
            根据模式重新读取武器加成:function():Void {},
            初始化换弹负担:ReloadManager.initReloadBurden,
            换弹门禁:ReloadManager.handleReloadGate,换弹帧率控制:ReloadManager.controlReloadFrameRate};
        _root.装备引用配置={配置装扮:DressupReferenceManager.attach,刷新所有装扮:DressupReferenceManager.refreshAll};
        _root.帧计时器={当前帧数:0};
        _root.soundEffectManager={playSound:function():Void {}};
        _root.对象浅拷贝=function(source:Object):Object {var copy:Object={};for(var k:String in source)copy[k]=source[k];return copy;};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.子弹区域shoot传递=function(data:Object):Void {Cf6SoldierAssetTest.capture(data);};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.mp=0;this.空手攻击力=100;this.等级=30;
            this.状态="长枪站立";this.攻击模式="长枪";this.方向="右";this.攻击目标="无";
            this.Z轴坐标=this._y=200;this._x=200;this.myxscale=100;this.是否为敌人=true;
            this.倒地=this.浮空=this.硬直中=this.刚体=this.免疫击退=false;
            this.unitAI={data:{xrange:100,zrange:10,xdistance:50}};
            this.swapDepths=function():Void {};this.行走=function():Void {};
            this.方向改变=function(dir:String):Void {this.方向=dir;this._xscale=dir=="左"?-100:100;};
            this.动画完毕=function():Void {
                this.fixtureRecord.done++;this.倒地=false;this.攻击目标="无";
                this.状态改变(this.hp>0?"长枪站立":"血腥死");
            };
            this.击飞浮空=function():Void {this.fixtureRecord.physics++;this.浮空=true;};
            this.击飞倒地=function():Void {this.fixtureRecord.landings++;this.倒地=true;this._y=this.Z轴坐标;};
            this.死亡检测=function():Void {
                this.fixtureRecord.deathChecks++;
                if(this.hp<=0){this.fixtureRecord.removed=true;this.removeMovieClip();}
            };
            this.dispatcher=new EventDispatcher();this.syncRefs={};this.被动技能={};this.伤害加成=0;
            this.基础命中率=20;this.基础命中加成=0;this.version=1;
            DressupInitializer.loadEquipmentData(this,"长枪",DressupInitializer.loadEquipment,1);
            DressupInitializer.updateDressupKeys(this);
            this.长枪弹匣容量=this.长枪属性.capacity;this.长枪.value.shot=0;
            FireEventComponent.initialize(this);ReloadEventComponent.initialize(this);
            this.stop();
        };
        driver.onEnterFrame=function():Void {Cf6SoldierAssetTest.tick();};
        weaponXml=new XML();weaponXml.ignoreWhite=true;
        weaponXml.onLoad=function(ok:Boolean):Void {
            Cf6SoldierAssetTest.check(ok,"load canonical rifle XML");
            if(!ok){Cf6SoldierAssetTest.finish();return;}
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            ItemUtil.itemDataDict={};ItemUtil.equipmentDict={};ItemUtil.multiTierDict={};
            for(var i:Number=0;i<parsed.item.length;i++){
                var item:Object=parsed.item[i];ItemUtil.itemDataDict[item.name]=item;ItemUtil.equipmentDict[item.name]=true;
            }
            Cf6SoldierAssetTest.check(ItemUtil.itemDataDict["AK47"].data.capacity>0,"external rifle is available");
            Cf6SoldierAssetTest.sourceLibraries=[];Cf6SoldierAssetTest.loadedWeapons=0;
            Cf6SoldierAssetTest.loadNextLibrary();
        };
        weaponXml.load("../data/items/武器_长枪_突击步枪.xml");
    }
    private static function loadNextLibrary():Void {
        // Top-level RSL imports share the game's attachment scope. A nested
        // loadMovie consumer cannot expose imported exports to root code.
        loaded(library);
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        var states:Array=["长枪站立","长枪行走","长枪跑","长枪跳","近战","长枪攻击","拾取","躲闪","被击","击倒","倒地","被投","血腥死","消失"];
        for(var side:Number=0;side<2;side++)for(var s:Number=0;s<states.length;s++) {
            var p:MovieClip=library.attachMovie(link,"soldierProbe"+probes.length,library.getNextHighestDepth(),{fixtureRecord:record(),长枪:"M4A1战术版"});
            check(p!=null,"attach state "+states[s]);probes.push({actor:p,state:states[s],side:side});
        }
        var moves:Array=["shoot","knife","hit0","hit1","down","knockdown","throw","death0","death1","death2",
            "interruptShoot","deadShoot","interruptKnife","deadKnife","hardHitShoot","hardHitKnife"];
        for(var j:Number=0;j<2;j++)for(var m:Number=0;m<moves.length;m++) {
            var rec:Object=record();var u:MovieClip=library.attachMovie(link,"soldierCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:rec,长枪:"M4A1战术版"});
            check(u!=null,"attach "+moves[m]+" "+j);cases.push({actor:u,move:moves[m],side:j,record:rec});
        }
        var gunNames:Array=["M4A1改","AK74战术版","DD MK18战术版","AK47#4"];
        for(var g:Number=0;g<gunNames.length;g++)for(var side2:Number=0;side2<2;side2++){
            var rg:Object=record();var ug:MovieClip=library.attachMovie(link,"soldierCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:rg,长枪:gunNames[g]});
            check(ug!=null,"attach configured rifle "+gunNames[g]);
            cases.push({actor:ug,move:"shoot",side:side2,record:rg,configured:gunNames[g]});
        }
        var reloadGuns:Array=["M4A1改","AK74战术版","M4A1战术版","DD MK18战术版"];
        for(var g2:Number=0;g2<reloadGuns.length;g2++)for(var side3:Number=0;side3<2;side3++){
            var rr:Object=record();var ur:MovieClip=library.attachMovie(link,"soldierCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:rr,长枪:reloadGuns[g2]});
            check(ur!=null,"attach real reload "+reloadGuns[g2]);cases.push({actor:ur,move:"reload",side:side3,record:rr,configured:reloadGuns[g2]});
        }
        for(var si:Number=0;si<2;si++)for(var mode:Number=0;mode<2;mode++){
            var ri:Object=record();var ui:MovieClip=library.attachMovie(link,"soldierCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:ri,长枪:"M4A1战术版"});
            cases.push({actor:ui,move:mode==0?"lateInterruptShoot":"reloadInterrupt",side:si,record:ri});
        }
        defaults=[];
        for(var di:Number=0;di<6;di++)defaults.push(library.attachMovie(link,"soldierDefault"+di,library.getNextHighestDepth(),{fixtureRecord:record()}));
        ready=true;ticks=0;
    }
    private static function capture(data:Object):Void {
        var u:MovieClip=library[data.发射者],rec:Object=u.fixtureRecord;
        if(rec==undefined)return;
        var shot:Boolean=data.子弹种类!="近战子弹";
        rec.contractOk=rec.contractOk && data.shootZ==u.Z轴坐标 && data.百分比伤害==undefined && data.血量上限击溃==undefined;
        if(shot){
            var d:Object=u.长枪属性;
            rec.powerOk=rec.powerOk && data.子弹威力==d.power && data.子弹威力!=u.空手攻击力;
            rec.shots++;rec.shotFrames+=u.man._currentframe+",";rec.shotTicks.push(ticks);
            rec.contractOk=rec.contractOk && data.霰弹值==d.split && data.Z轴攻击范围==d.bulletsize
                && data.子弹速度==d.velocity && data.子弹散射度==d.diffusion
                && data.声音==d.sound && data.发射效果==d.muzzle && data.子弹种类==d.bullet;
            var p:Object={x:0,y:0};u.man.枪.枪.装扮.枪口位置.localToGlobal(p);library.globalToLocal(p);
            rec.muzzleOk=rec.muzzleOk && Math.abs(data.shootX-p.x)<0.2 && Math.abs(data.shootY-p.y)<0.2;
        }else{
            rec.powerOk=rec.powerOk && data.子弹威力==100;
            rec.stabs++;
            rec.contractOk=rec.contractOk && data.子弹种类=="近战子弹" && data.子弹速度==0 && data.击倒率==10 && data.Z轴攻击范围==24;
            var bounds:Object=data.区域定位area.getBounds(library);
            rec.areaOk=rec.areaOk && Math.abs(bounds.xMax-bounds.xMin-101)<0.3 && Math.abs(bounds.yMax-bounds.yMin-135)<0.3;
        }
    }
    private static function pixelHex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function render(u:MovieClip,key:String):Void {
        if(u==null || images[key])return;
        var info:Boolean=u.人物文字信息._visible;u.人物文字信息._visible=false;
        var bd:BitmapData=new BitmapData(640,430,true,0xffe8e6e2);
        var matrix:Matrix=u.transform.matrix,scale:Number=key=="airborne-shadow"?1.0:1.7;
        matrix.a*=scale;matrix.b*=scale;matrix.c*=scale;matrix.d*=scale;matrix.tx=320;matrix.ty=350;
        bd.draw(u,matrix);u.人物文字信息._visible=info;
        var visible:Number=0;
        for(var y:Number=0;y<430;y+=3)for(var x:Number=0;x<640;x+=3)if(bd.getPixel(x,y)!=0xe8e6e2)visible++;
        check(visible>200,"native pixels "+key+" "+visible);images[key]=true;
        trace("[SOLDIER_POSE] "+key+" state="+u.状态+" frame="+u.man._currentframe);
        if(_root.soldierCapture===true) {
            trace("[SOLDIER_IMAGE_BEGIN] "+key+" 640 430");
            for(var row:Number=0;row<430;row++) {
                var parts:Array=[],last:Number=bd.getPixel32(0,row),count:Number=1;
                for(var col:Number=1;col<640;col++) {
                    var value:Number=bd.getPixel32(col,row);
                    if(value==last)count++;else{parts.push(pixelHex(last)+":"+count);last=value;count=1;}
                }
                parts.push(pixelHex(last)+":"+count);trace("[SOLDIER_IMAGE_ROW] "+key+" "+row+" "+parts.join(","));
            }
            trace("[SOLDIER_IMAGE_END] "+key);
        }
        bd.dispose();
    }
    private static function shadowCheck(u:MovieClip,label:String):Void {
        check(u.soldierShadow!=null && u.soldierShadow._visible,"shadow "+label);
        check(library.shadow==undefined && u.shadow==undefined,"private shadow ownership "+label);
        var p:Object={x:0,y:0};u.soldierShadow.localToGlobal(p);library.globalToLocal(p);
        check(Math.abs(p.y-u.Z轴坐标)<0.2,"grounded shadow "+label);
    }
    private static function limbCoverage(u:MovieClip):Void {
        var bd:BitmapData=new BitmapData(200,220,true,0x00000000);
        var matrix:Matrix=u.man.transform.matrix;matrix.tx+=90;matrix.ty+=190;bd.draw(u.man,matrix);
        var left:Number=0,right:Number=0;
        for(var y:Number=120;y<181;y++) {
            for(var x:Number=40;x<76;x++)if((bd.getPixel32(x,y)>>>24)>180)left++;
            for(var x2:Number=85;x2<116;x2++)if((bd.getPixel32(x2,y)>>>24)>180)right++;
        }
        check(left>160,"visible left lower limb, independently of body bounds and shadow");
        check(right>160,"visible right lower limb, independently of body bounds and shadow");
        trace("[SOLDIER_LIMB_COVERAGE] left="+left+" right="+right);bd.dispose();
    }
    private static function decisions():Void {
        var u:MovieClip=probes[0].actor;
        check(u.hasDressup===true && u.enableShoot===true,"fixed body uses standard equipment and shooting lifecycle");
        u.soldierClock=100;u.soldierReadyAt=0;
        check(u.soldierChooseAttack(80,0,0)=="knife","close knife");
        check(u.soldierChooseAttack(300,0,0)=="shoot","ranged burst");
        check(u.soldierChooseAttack(461,0,0)=="none","outside range");
        check(u.soldierChooseAttack(100,25,0)=="none","lane mismatch");
        check(u.soldierChooseAttack(100,0,86)=="none","high target rejected");
        check(u.soldierChooseAttack(Number("bad"),0,0)=="none","invalid coordinate rejected");
        u.soldierReadyAt=101;check(u.soldierChooseAttack(100,0,0)=="none","reaction delay");u.soldierReadyAt=0;
        var target:MovieClip=library.createEmptyMovieClip("soldierDecisionTarget",library.getNextHighestDepth());
        target.hp=1000;target._x=500;target.Z轴坐标=target._y=200;target.createEmptyMovieClip("area",1);
        var change:Function=u.状态改变;
        u.状态改变=function(state:String):Void {this.requestedState=state;this.状态=state;};
        u.攻击目标=target._name;u.soldierTargetName=target._name;
        var flags:Array=["暂停","manual","硬直中","倒地","浮空","dead","badTarget"];
        for(var i:Number=0;i<flags.length;i++) {
            u.状态="长枪站立";u.requestedState="none";u.soldierClock=99;var flag:String=flags[i];
            if(flag=="暂停")_root.暂停=true;else if(flag=="manual")_root.控制目标=u._name;
            else if(flag=="dead")u.hp=0;else if(flag=="badTarget")target.hp=0;else u[flag]=true;
            u.soldierTick();check(u.requestedState==(flag=="dead"?"血腥死":"none"),"AI guard "+flag);
            _root.暂停=false;_root.控制目标="__no_player";u.hp=target.hp=1000;u.硬直中=u.倒地=u.浮空=false;
        }
        u.状态="长枪站立";u.requestedState="none";u.soldierClock=99;target.Z轴坐标=target._y=240;u.soldierTick();
        check(u.requestedState=="none" && u.下行===true,"align depth before attack");
        target.Z轴坐标=target._y=200;u.soldierClock=99;u.soldierTick();
        check(u.requestedState=="长枪攻击","private AI selects shooting");
        check(u.unitAI.data.xrange==0 && u.unitAI.data.zrange==24 && u.unitAI.data.xdistance==190,"shared AI cache matches applied ranges");
        target._x=u._x+80;u.状态="长枪站立";u.requestedState="none";u.soldierClock=99;u.soldierTick();
        check(u.requestedState=="近战","private AI selects knife");
        target.浮空高度=120;u.状态="长枪站立";u.requestedState="none";u.soldierClock=99;u.soldierTick();
        check(u.requestedState=="none","authored extra airborne height respected");
        target.浮空高度=Number("bad");u.状态="长枪站立";u.requestedState="none";u.soldierClock=99;u.soldierTick();
        check(u.requestedState=="近战","invalid optional height preserves ground height");
        u.状态="长枪攻击";u.soldierBeginAttack(u.man,"shoot");var first:Object=u.man.soldierToken;
        var firstDeadline:Number=u.soldierAttackOwner.fireDeadline,firstNext:Number=u.soldierNextShootAt;
        check(firstDeadline-u.soldierClock==18 && firstNext-firstDeadline==30,"bounded 18-frame fire window and 30-frame rest");
        check(u.soldierChooseAttack(300,0,0)=="none","ranged attack cannot restart during rest");
        check(u.soldierChooseAttack(80,0,0)=="knife","knife remains available during shooting rest");
        u.soldierBeginAttack(u.man,"shoot");
        check(u.soldierAttackOwner==null && u.soldierNextShootAt==firstNext,"forced pose reentry cannot bypass shooting rest");
        u.状态="长枪攻击";u.soldierClock=firstNext;
        u.soldierBeginAttack(u.man,"shoot");var current:Object=u.man.soldierToken;u.man.soldierToken=first;
        check(!u.soldierCanAct(u.man),"stale action token rejected");u.man.soldierToken=current;
        check(u.soldierCanAct(u.man),"current action token accepted");
        var originalWeapon:Object=u.长枪,originalVersion:Number=u.version;
        u.长枪=BaseItem.createFromString("AK47#4");check(!u.soldierCanAct(u.man),"weapon replacement rejects old shooting owner");u.长枪=originalWeapon;
        u.version++;check(!u.soldierCanAct(u.man),"reinitialization rejects old shooting owner");u.version=originalVersion;
        _root.暂停=true;check(!u.soldierCanAct(u.man),"paused action blocked");_root.暂停=false;
        var alien:MovieClip=u.createEmptyMovieClip("alien",999);alien.soldierToken=current;
        check(!u.soldierCanAct(alien),"foreign body cannot reuse current token");alien.removeMovieClip();
        var deadline:Number=u.soldierAttackOwner.fireDeadline,nextFire:Number=u.soldierNextShootAt;
        var ammoBefore:Number=u.长枪.value.shot;
        u.soldierClock=deadline;
        check(u.长枪射击(u.soldierMuzzleMarker(u.man),{})===false,"late scheduled shot rejected exactly at fire deadline");
        check(u.长枪.value.shot==ammoBefore,"rejected late shot does not consume ammunition");
        u.soldierDriveShooting(u.man);
        check(u.soldierAttackOwner==null && u.动作A===false,"fire deadline ends attack and scheduler ownership");
        check(u.soldierNextShootAt==nextFire,"ending shooting preserves mandatory rest");
        u.soldierCancelAttack();check(!u.soldierCanAct(u.man),"cancelled action blocked");
        check(u.soldierNextShootAt==nextFire,"hit/state cancellation cannot reset rest");
        _root.暂停=true;var pausedClock:Number=u.soldierClock;u.soldierTick();_root.暂停=false;
        check(u.soldierClock==pausedClock && u.soldierNextShootAt==nextFire,"pause freezes fire-rest clock");
        u.soldierClock=nextFire-1;check(u.soldierChooseAttack(300,0,0)=="none","last rest frame blocks shooting");
        u.soldierClock=nextFire;check(u.soldierChooseAttack(300,0,0)=="shoot","shooting resumes at exact rest boundary");
        u.状态改变=change;u.状态="长枪站立";u.攻击目标="无";u.左行=u.右行=u.上行=u.下行=false;target.removeMovieClip();
        trace("[SOLDIER_GUN_DIAG] unit="+u+" name="+u.长枪.name+" skinKey="+u.长枪_装扮+" holder="+u.man.枪.枪+" skin="+u.man.枪.枪.装扮+" marker="+u.man.枪.枪.装扮.枪口位置+" ref="+u.长枪_引用+" actorUrl="+u._url);
        var before:Object=u.soldierMuzzle(u.man);check(before!=null,"configured rifle muzzle exists");
        _root.是否阴影=false;u.soldierShadow.updateSoldierShadow();check(!u.soldierShadow._visible,"shadow option off");
        _root.是否阴影=true;u.soldierShadow.updateSoldierShadow();check(u.soldierShadow._visible,"shadow option on");
        u._y=150;u._rotation=25;u._xscale=-160;u._yscale=160;
        u.soldierShadow.updateSoldierShadow();shadowCheck(u,"lifted rotated mirrored");
        var transformed:Object=u.soldierMuzzle(u.man),expected:Object={x:0,y:0};
        u.man.枪.枪.装扮.枪口位置.localToGlobal(expected);library.globalToLocal(expected);
        check(transformed!=null && Math.abs(transformed.x-expected.x)<0.1 && Math.abs(transformed.y-expected.y)<0.1,"muzzle follows complete native transform");
        render(u,"airborne-shadow");u._y=200;u._rotation=0;u._xscale=u._yscale=100;u.soldierShadow.updateSoldierShadow();
    }
    private static function tick():Void {
        if(finished)return;ticks++;_root.帧计时器.当前帧数=ticks;
        if(!ready){if(ticks>900){check(false,"load timeout");finish();}return;}
        if(ticks==3) {
            for(var s:Number=0;s<probes.length;s++) {
                var pr:Object=probes[s];pr.actor.方向改变(pr.side==0?"右":"左");pr.actor.状态改变(pr.state);
            }
            for(var i:Number=0;i<cases.length;i++) {
                var c:Object=cases[i],u:MovieClip=c.actor;u.方向改变(c.side==0?"右":"左");
                if(c.move.indexOf("reload")==0){u.长枪.value.shot=u.长枪弹匣容量-1;u.状态改变("长枪攻击");}
                else if(c.move=="shoot" || c.move.indexOf("Shoot")>0)u.状态改变("长枪攻击");
                else if(c.move=="knife" || c.move.indexOf("Knife")>0)u.状态改变("近战");
                else if(c.move.substr(0,3)=="hit")u.状态改变("被击");
                else if(c.move=="down")u.状态改变("倒地");else if(c.move=="knockdown")u.状态改变("击倒");
                else if(c.move=="throw")u.状态改变("被投");
                else if(c.move.substr(0,5)=="death"){u.hp=0;u.状态改变("血腥死");}
            }
        }
        if(ticks==4) {
            for(var j:Number=0;j<cases.length;j++) {
                var q:Object=cases[j];
                if(q.move.substr(0,3)=="hit")q.actor.man.gotoAndPlay("a"+q.move.substr(3));
                else if(q.move.substr(0,5)=="death")q.actor.man.gotoAndPlay("a"+q.move.substr(5));
                else if(q.move.indexOf("interrupt")==0){q.actor.状态改变("被击");q.actor.man.gotoAndPlay("a0");}
                else if(q.move.indexOf("dead")==0)q.actor.hp=0;
                else if(q.move.indexOf("hardHit")==0)q.actor.硬直中=true;
            }
        }
        if(ticks==5) {
            for(var k:Number=0;k<probes.length;k++) {
                var p:Object=probes[k];
                if(p.state=="消失"){check(p.actor.man==null && p.actor.soldierShadow==null,"disappeared body and shadow");continue;}
                check(p.actor.man._width>0,"state has body "+p.state);shadowCheck(p.actor,p.state+" "+p.side);
            }
            for(var di2:Number=0;di2<defaults.length;di2++){
                var du:MovieClip=defaults[di2],allowed:Boolean=false;
                for(var pi:Number=0;pi<_root.敌人函数.大学军校学员随机兵器表.length;pi++)if(du.长枪.name==_root.敌人函数.大学军校学员随机兵器表[pi])allowed=true;
                check(allowed && du.长枪 instanceof BaseItem,"omitted primary resolves shared cadet pool "+di2);
            }
            var standing:MovieClip=probes[0].actor;standing.man.gotoAndStop(1);limbCoverage(standing);render(standing,"stand");
            var dying:MovieClip=cases[7].actor,oldFrame:Number=dying.man._currentframe;dying.man.gotoAndStop(1);
            var a:Object=standing.man.getBounds(library),b:Object=dying.man.getBounds(library);
            check(Math.abs((a.yMax-a.yMin)-(b.yMax-b.yMin))<0.3,"death initial body height");
            check(Math.abs(a.yMax-b.yMax)<0.3,"death initial ground");
            check(Math.abs(a.xMin-b.xMin)<0.3 && Math.abs(a.xMax-b.xMax)<0.3,"death initial horizontal alignment");
            trace("[SOLDIER_DEATH_SCALE] standing="+(a.yMax-a.yMin)+" death="+(b.yMax-b.yMin)+" groundDelta="+(b.yMax-a.yMax)+" ground="+(a.yMax-standing._y));
            render(dying,"death-start");dying.man.gotoAndPlay(oldFrame);standing.man.play();decisions();
        }
        if(ticks==9){
            for(var li:Number=48;li<cases.length;li++)if(cases[li].move=="lateInterruptShoot"){
                cases[li].record.allowedShots=cases[li].record.shots;cases[li].actor.状态改变("被击");cases[li].actor.man.gotoAndPlay("a0");
            }
            render(cases[0].actor,"shoot");
            for(var g3:Number=32;g3<40;g3+=2)render(cases[g3].actor,"rifle-"+cases[g3].configured.split("#")[0]);
        }
        if(ticks==24){
            render(cases[40].actor,"reload");
            for(var ir:Number=48;ir<cases.length;ir++)if(cases[ir].move=="reloadInterrupt"){
                check(cases[ir].actor.man.换弹标签===true,"interrupt actual active reload");
                cases[ir].actor.状态改变("被击");cases[ir].actor.man.gotoAndPlay("a0");
            }
        }
        if(ticks==16)render(cases[1].actor,"knife");
        if(ticks==20)for(var n:Number=0;n<cases.length;n++)if(cases[n].move=="knockdown") {
            cases[n].actor.浮空=false;cases[n].actor.状态改变("倒地");
        }
        if(ticks==22)render(cases[4].actor,"down");
        if(ticks==30){render(cases[7].actor,"death-a0-middle");render(cases[8].actor,"death-a1-middle");render(cases[9].actor,"death-a2-late");}
        if(ticks==44)render(cases[8].actor,"death-a1-late");
        if(ticks==54)render(cases[7].actor,"death-a0-late");
        if(ticks==180) {
            for(var r:Number=0;r<cases.length;r++) {
                var e:Object=cases[r],rec:Object=e.record;
                check(rec.shots==(e.move=="shoot"?3:e.move.indexOf("reload")==0?1:e.move=="lateInterruptShoot"?rec.allowedShots:0) && rec.stabs==(e.move=="knife"?1:0),"exact emissions "+e.move+" "+e.side+" shots="+rec.shots+" stabs="+rec.stabs);
                check(rec.powerOk && rec.contractOk && rec.areaOk && rec.muzzleOk,"projectile/area/muzzle contract "+r);
                if(e.move=="shoot"){
                    var gap:Number=Math.floor(e.actor.长枪属性.interval/(1000/30));
                    for(var q1:Number=1;q1<rec.shotTicks.length;q1++)check(rec.shotTicks[q1]-rec.shotTicks[q1-1]>=gap,"weapon cadence "+r);
                    check(e.actor.长枪.value.shot==3,"standard ammunition commit "+r);
                }
                if(e.move=="lateInterruptShoot")check(rec.allowedShots>0 && e.actor.长枪.value.shot==rec.allowedShots && e.actor.keepshooting==undefined,"interruption clears an already active shooting loop "+r);
                if(e.move=="reloadInterrupt")check(e.actor.长枪.value.shot==e.actor.长枪弹匣容量 && e.actor.soldierReloadCount==1,"interrupted reload does not commit fresh ammunition "+r);
                if(e.configured=="AK47#4")check(e.actor.长枪.value.level==4,"external enhancement level is preserved "+r);
                if(e.move=="reload")check(e.actor.长枪.value.shot==0 && e.actor.soldierReloadCount==1,"actual magazine emptied and reloaded once "+r);
                if(e.configured)check(e.actor.长枪.name==e.configured.split("#")[0],"external weapon wins over random default "+r);
                if(e.move=="shoot" || e.move=="knife" || e.move=="reload") {
                    check(rec.done==1,"attack completes once "+r);
                    check(e.actor.soldierAttackOwner==null && e.actor.soldierInvalidMuzzleCount==0,"attack owner released and no missing muzzle "+r);
                    check(!e.actor.刚体 && !e.actor.免疫击退,"ordinary soldier gains no attack armor "+r);
                } else if(e.move.substr(0,5)=="death" || e.move.indexOf("dead")==0) {
                    check(rec.removed && rec.deathChecks==1,"death settles once "+r);
                } else if(e.move=="throw") {
                    check(rec.done==0 && e.actor.man._currentframe==13,"grab pose waits for external throw lifecycle "+r);
                } else {
                    check(rec.done==1,"hit/down/cancel recovery "+r+" done="+rec.done);
                }
                if(e.move=="knockdown")check(rec.physics==1 && rec.landings==1,"airborne and landing delegates "+r);
            }
            var needed:Array=["stand","shoot","knife","down","death-start","death-a0-middle","death-a0-late","death-a1-middle","death-a1-late","death-a2-late","airborne-shadow"];
            for(var z:Number=0;z<needed.length;z++)check(images[needed[z]]===true,"native image captured "+needed[z]);
            finish();
        }
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        trace("Cf6SoldierAssetTest: "+passed+" passed, "+failed+" failed; 52 actual timeline cases");
        if(failed>0)trace("[TEST_FAIL] Cf6SoldierAssetTest suite failed");
        if(_root.cf6SoldierAssetComplete!=undefined)_root.cf6SoldierAssetComplete();
    }
}
