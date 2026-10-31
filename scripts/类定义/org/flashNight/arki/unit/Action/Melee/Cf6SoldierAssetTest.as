import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.ReloadEventComponent;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.KillEventComponent;
import org.flashNight.arki.component.Damage.CritDamageHandle;
import org.flashNight.arki.component.Damage.ExecuteDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.Shield.BaseShield;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Damage.DamageCalculator;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.unit.UnitAI.core.UnitAIData;
import org.flashNight.arki.unit.UnitAI.behavior.CombatModule;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;
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
    private static var cases:Array,probes:Array,images:Object,sourceLibraries:Array,weaponXml:XML,sidearmXml:XML,pistolXml:XML,defaults:Array;
    private static var loadedWeapons:Number=0;
    private static var phases:Array,elites:Array,lanes:Array,pairs:Array,roles:Array,tactics:Array;
    private static var grenadeXml:XML;
    private static var completionCases:Array;
    private static var reviewQueue:Array,reviewUnits:Array,reviewIndex:Number,reviewStage:Number,reviewDone:Boolean;
    private static var link:String="敌人-CF6特种兵";

    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[TEST_FAIL] Cf6SoldierAssetTest: "+label);}
    }
    private static function record():Object {
        return {contacts:0,bashes:0,grenades:0,explosions:0,shots:0,stabs:0,done:0,deathChecks:0,removed:false,physics:0,landings:0,
            powerOk:true,areaOk:true,contractOk:true,muzzleOk:true,shotFrames:"",shotTicks:[],
            sidearmShots:0,sidearmTicks:[],sidearmFrames:"",ammoBefore:0,slotShots:{长枪:0,手枪:0,手枪2:0}};
    }
    private static function reloadDiag(u:MovieClip,stage:String):Void {
        var owner:Object=u.soldierAttackOwner;
        trace("[ELITE_RELOAD_DIAG] "+u._name+" stage="+stage+" frame="+u.man._currentframe
            +" label="+u.man.换弹标签+" owner="+(owner==null?"null":owner.reload+"/"+owner.reloadSlot+"/"+owner.active)
            +" can="+u.soldierCanAct(u.man)+" shot="+u.手枪.value.shot+"/"+u.手枪弹匣容量
            +" per="+u.man.perRoundReload+" tube="+u.man.reloadCanSelectTube
            +" type="+u.man.dualReloadWeaponType+" hand="+u.man.dualReloadStartHand
            +" burden="+u.man.reloadBurden+" ctrl="+u.man.reloadFrameControlRequest+"/"+u.man.reloadFrameControlActive+"/"+u.man.reloadFrameProgress
            +" gate="+u.man.reloadGateFrame+"/"+u.man.reloadLoopBackFrame+"/"+u.man.reloadEndFrame
            +" count="+u.soldierReloadCount+" error="+u.soldierWeaponError);
    }
    public static function runAllTests():Void {
        passed=failed=ticks=0;ready=finished=false;reviewDone=false;cases=[];probes=[];images={};phases=[];elites=[];lanes=[];pairs=[];roles=[];tactics=[];completionCases=[];
        _root.cf6InventoryReads=0;_root.cf6InventoryWrites=0;
        ItemUtil.singleContain=function():Object {_root.cf6InventoryReads++;return null;};
        ItemUtil.getTotal=function():Number {_root.cf6InventoryReads++;return 0;};
        ItemUtil.singleSubmit=function():Boolean {_root.cf6InventoryWrites++;return false;};
        if(_root.soldierCapture===true || _root.soldierTacticalCapture===true || _root.soldierChargeEvasionCapture===true || _root.soldierMotionCapture===true)trace("[SOLDIER_CAPTURE_PROTOCOL] region-rle-v2");
        if(_root.soldierChargeEvasionCapture===true)trace("[R10_SCENE_EXPECTED] 82");
        check(typeof _root.士兵测试初始化掉落物=="function","canonical equipment drop initializer is available before attachment");
        library=_root.createEmptyMovieClip("__soldierLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__soldierTestDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;_root.暂停=false;
        library.createEmptyMovieClip("deadbody",library.getNextHighestDepth()).layers=[null,null,{}];
        _root.控制目标="__no_player";_root.控制目标全自动=false;_root.是否阴影=true;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};
        _root.add2map=function():Void {};_root.add2map2=function():Void {};
        _root.fixtureCrit=false;_root.重力加速度=1;
        _root.成功率=function(chance:Number):Boolean {_root.fixtureChance=chance;return _root.fixtureCrit;};
        _root.敌人函数={配置音效:function():Void {},
            标准击杀:KillEventComponent.onKill,
            行走:_root.士兵测试标准行走,
            大学军校学员随机兵器表:["M4A1改","AK74战术版","M4A1战术版","DD MK18战术版"],
            状态改变:function(state:String):Void {if(this.状态==state)return;this.状态=state;this.gotoAndStop(state);}};
        _root.主角函数={长枪射击:WeaponFireCore.LONG_GUN_SHOOT,
            手枪射击:WeaponFireCore.PISTOL_SHOOT,手枪2射击:WeaponFireCore.PISTOL2_SHOOT,
            初始化掉落物:_root.士兵测试初始化掉落物,
            初始化长枪射击函数:function():Void {ShootInitCore.initLongGun(this,this._parent);},
            初始化混合双枪:function():Void {
                var unit:MovieClip = this._parent;
                WeaponAmmoRuntime.ensure(unit, "手枪");
                WeaponAmmoRuntime.ensure(unit, "手枪2");
                this.子弹属性 = ShootInitCore.generateBulletProps(unit, "手枪", unit.手枪属性, {});
                this.主手射击速度 = unit.手枪属性.interval;
                this.主手使用弹匣名称 = unit.手枪属性.clipname;
                this.主手是否单发 = unit.手枪属性.singleshoot;
                this.主手剩余弹匣数 = ShootInitCore.resolveMagazineStock(unit, this.主手使用弹匣名称);
                if (unit.eliteSidearmEnabled()) {
                    this.子弹属性2 = ShootInitCore.generateBulletProps(unit, "手枪2", unit.手枪2属性, {});
                    this.副手射击速度 = unit.手枪2属性.interval;
                    this.副手使用弹匣名称 = unit.手枪2属性.clipname;
                    this.副手是否单发 = unit.手枪2属性.singleshoot;
                    this.副手剩余弹匣数 = ShootInitCore.resolveMagazineStock(unit, this.副手使用弹匣名称);
                }
                this.主手换弹匣 = ReloadManager.createHandReloadFunction(this, unit, _root,
                    {handPrefix:"主手", weaponType:"手枪"}, null);
                this.副手换弹匣 = ReloadManager.createHandReloadFunction(this, unit, _root,
                    {handPrefix:"副手", weaponType:"手枪2"}, null);
            },
            取消混合换弹:function():Void {
                ReloadManager.cancelReload(this, false);
            },
            混合手枪换弹匣:function():Void {
                var slot:String = this._parent.soldierAttackOwner.reloadSlot;
                if (slot == "手枪2") this.副手换弹匣();
                else if (slot == "手枪") this.主手换弹匣();
            },
            开始混合手枪换弹:function(slot:String):Void {
                var unit:MovieClip = this._parent;
                if (slot == undefined) slot = "手枪";
                if ((slot != "手枪" && slot != "手枪2") || !WeaponAmmoRuntime.canReload(unit, slot, false)) return;
                ShootCore.stopForReload(unit);
                ReloadManager.bumpReloadGeneration(this);
                this.dualReloadStartHand = slot == "手枪2" ? "副手" : "主手";
                delete this._dualReloadFirstInitStartFrame;
                this.换弹标签 = true;
                this.gotoAndPlay(unit.soldierAttackOwner.reloadPair===true?"双枪同步换弹匣":"双枪换弹匣");
            },
            清理射击任务:function(unit:MovieClip,preserve:Boolean):Void {ShootCore.cleanup(unit,preserve);},
            根据模式重新读取武器加成:function():Void {},
            初始化换弹负担:ReloadManager.initReloadBurden,
            双枪初始化换弹负担:ReloadManager.initDualGunReloadBurden,
            换弹门禁:ReloadManager.handleReloadGate,双枪换弹门禁:ReloadManager.handleDualGunReloadGate,
            换弹帧率控制:ReloadManager.controlReloadFrameRate};
        _root.装备引用配置={配置装扮:DressupReferenceManager.attach,刷新所有装扮:DressupReferenceManager.refreshAll};
        _root.帧计时器={当前帧数:0};
        _root.soundEffectManager={playSound:function():Void {}};
        _root.对象浅拷贝=function(source:Object):Object {var copy:Object={};for(var k:String in source)copy[k]=source[k];return copy;};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.getItemData=function(name:String):Object {return ItemUtil.itemDataDict[name];};
        _root.子弹区域shoot传递=function(data:Object):MovieClip {Cf6SoldierAssetTest.capture(data);return _root.gameworld;};
        _root.初始化敌人模板=function():Void {
            // Legacy cases isolate primary fire; completion cases exercise default-on subweapons.
            if(this.fixtureCompletion!==true)this.特种兵副武器=false;
            // Freeze the historical emission fixtures; R9 scenarios use live defaults.
            if(this.fixtureTacticalModern!==true){
                this.特种兵战术_rifleShots=3;this.特种兵战术_rifleFireFrames=18;
                this.特种兵战术_rifleRestFrames=30;this.特种兵战术_eliteStandShots=5;
            }
            this.hp=this.hp满血值=1000;this.mp=0;this.空手攻击力=100;this.等级=30;
            this.状态="长枪站立";this.攻击模式="长枪";this.方向="右";this.攻击目标="无";
            this.Z轴坐标=this._y=200;this._x=200;this.myxscale=100;this.是否为敌人=true;
            this.倒地=this.浮空=this.硬直中=this.刚体=this.免疫击退=false;
            this.unitAI={data:{xrange:100,zrange:10,xdistance:50}};
            this.swapDepths=function():Void {};
            this.行走=this.行走 || _root.敌人函数.行走;
            this.行走X速度=8;this.行走Y速度=4;this.跑X速度=16;this.跑Y速度=8;
            this.移动=function(direction:String,amount:Number):Void {
                if(direction=="上")this._y-=amount;else if(direction=="下")this._y+=amount;
                else if(direction=="左")this._x-=amount;else if(direction=="右")this._x+=amount;
                this.Z轴坐标=this._y;
            };
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
            this.damageTakenMultiplier=1;this.buffManager=new BuffManager(this);
            this.斗兽标定隔离=true;
            this.dispatcher.subscribe("death",function():Void {this.fixtureRecord.deaths++;},this);
            this.fixtureRecord.deaths=0;
            this.基础命中率=20;this.基础命中加成=0;this.version=1;
            DressupInitializer.loadEquipmentData(this,"长枪",DressupInitializer.loadEquipment,1);
            for(var pistolIndex:Number=0;pistolIndex<2;pistolIndex++){
                var pistolSlot:String=pistolIndex==0?"手枪":"手枪2";
                if(this[pistolSlot]){
                    DressupInitializer.loadEquipmentData(this,pistolSlot,DressupInitializer.loadEquipment,1);
                    this[pistolSlot+"弹匣容量"]=this[pistolSlot+"属性"].capacity;
                    this[pistolSlot].value.shot=0;
                }
            }
            DressupInitializer.updateDressupKeys(this);
            this.长枪弹匣容量=this.长枪属性.capacity;this.长枪.value.shot=0;
            FireEventComponent.initialize(this);ReloadEventComponent.initialize(this);
            if(this.fixtureCompletion===true)LongGunSubWeaponCore.configureUnit(this,ItemUtil.itemDataDict[this.长枪.name]);
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
            sidearmXml.load("../data/items/武器_手枪_大威力手枪.xml");
        };
        weaponXml.load("../data/items/武器_长枪_突击步枪.xml");
        sidearmXml=new XML();sidearmXml.ignoreWhite=true;
        sidearmXml.onLoad=function(ok:Boolean):Void {
            Cf6SoldierAssetTest.check(ok,"load canonical FR506 XML");
            if(!ok){Cf6SoldierAssetTest.finish();return;}
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            for(var i:Number=0;i<parsed.item.length;i++){
                var item:Object=parsed.item[i];ItemUtil.itemDataDict[item.name]=item;ItemUtil.equipmentDict[item.name]=true;
            }
            Cf6SoldierAssetTest.check(ItemUtil.itemDataDict["FR506"].data.reloadType=="tube","FR506 tube data is available");
            pistolXml.load("../data/items/武器_手枪_突击步枪.xml");
        };
        pistolXml=new XML();pistolXml.ignoreWhite=true;
        pistolXml.onLoad=function(ok:Boolean):Void {
            Cf6SoldierAssetTest.check(ok,"load canonical short HK53 XML");
            if(!ok){Cf6SoldierAssetTest.finish();return;}
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            for(var i:Number=0;i<parsed.item.length;i++){
                var item:Object=parsed.item[i];ItemUtil.itemDataDict[item.name]=item;ItemUtil.equipmentDict[item.name]=true;
            }
            Cf6SoldierAssetTest.check(ItemUtil.itemDataDict["短HK53"].use=="手枪"
                && ItemUtil.itemDataDict["短HK53"].data.capacity==30,"external short HK53 canonical pistol data");
            Cf6SoldierAssetTest.sourceLibraries=[];Cf6SoldierAssetTest.loadedWeapons=0;
            grenadeXml.load("../data/items/消耗品_手雷.xml");
        };
        grenadeXml=new XML();grenadeXml.ignoreWhite=true;
        grenadeXml.onLoad=function(ok:Boolean):Void {
            Cf6SoldierAssetTest.check(ok,"load configured grenade item catalog");
            if(!ok){Cf6SoldierAssetTest.finish();return;}
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            for(var i:Number=0;i<parsed.item.length;i++){
                var item:Object=parsed.item[i];ItemUtil.itemDataDict[item.name]=item;
            }
            Cf6SoldierAssetTest.loadNextLibrary();
        };
    }
    private static function loadNextLibrary():Void {
        // Top-level RSL imports share the game's attachment scope. A nested
        // loadMovie consumer cannot expose imported exports to root code.
        loaded(library);
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        var fr506Probe:MovieClip=library.attachMovie("枪-手枪-FR506","fr506LinkProbe",library.getNextHighestDepth());
        check(fr506Probe!=null && fr506Probe.枪口位置!=null,"FR506 shared RSL scope and live muzzle");
        fr506Probe.removeMovieClip();
        var hk53Probe:MovieClip=library.attachMovie("枪-手枪-短HK53","hk53LinkProbe",library.getNextHighestDepth());
        check(hk53Probe!=null && hk53Probe.枪口位置!=null,"short HK53 shared RSL scope and live muzzle");
        hk53Probe.removeMovieClip();
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
        var phaseMoves:Array=["stand","shoot","knife","hit","break","breakReload"];
        for(var ps:Number=0;ps<2;ps++)for(var pm:Number=0;pm<phaseMoves.length;pm++){
            var phaseRec:Object=record();
            var phaseUnit:MovieClip=library.attachMovie("敌人-CF6持盾特种兵","phaseCase"+phases.length,
                library.getNextHighestDepth(),{fixtureRecord:phaseRec,长枪:"AK47#4"});
            check(phaseUnit!=null,"attach shield "+phaseMoves[pm]);
            phases.push({actor:phaseUnit,record:phaseRec,side:ps,move:phaseMoves[pm]});
        }
        for(var ov:Number=0;ov<2;ov++){
            var overrideRec:Object=record();
            var overrideUnit:MovieClip=library.attachMovie(ov==0?link:"敌人-CF6持盾特种兵","phaseOverride"+ov,
                library.getNextHighestDepth(),{fixtureRecord:overrideRec,长枪:"M4A1战术版",特种兵初始阶段:ov+1,特种兵持盾减伤率:40});
            phases.push({actor:overrideUnit,record:overrideRec,side:ov,move:"override",expectedPhase:ov+1,overrideReduction:40});
        }
        var eliteMoves:Array=["stand","retreat","slide","reload","interrupt","break","mobilityStiff","sidearmReload","sidearmInterrupt","noSidearm",
            "primaryReload","primaryInterrupt","externalPair","identityLong","identityMain","identityOff"];
        for(var es:Number=0;es<2;es++)for(var em:Number=0;em<eliteMoves.length;em++){
            var er:Object=record();er.elite=true;
            var init:Object={fixtureRecord:er,特种兵烟雾弹:false,长枪:"M4A1战术版",手枪:eliteMoves[em]=="externalPair"?"短HK53":"FR506",手枪2:"FR506"};
            if(eliteMoves[em]=="noSidearm")init.特种兵精英消融="noSidearm";
            if(eliteMoves[em]=="identityLong")init.掉落物=[{名字:"短HK53",概率:37}];
            if(eliteMoves[em]=="identityMain")init.不掉装备=true;
            if(eliteMoves[em]=="identityOff")init.是否为敌人=false;
            var eu:MovieClip=library.attachMovie(eliteMoves[em]=="break"?"敌人-CF6持盾特种精英":"敌人-CF6特种精英",
                "eliteCase"+elites.length,library.getNextHighestDepth(),init);
            check(eu!=null,"attach elite "+eliteMoves[em]);
            elites.push({actor:eu,record:er,move:eliteMoves[em],side:es});
        }
        createLaneCases();createPairCases();createRoleCases();createTacticalCases();createCompletionCases();
        ready=true;ticks=0;
    }
    private static function validateEliteEquipment(c:Object,u:MovieClip):Void {
            var mainName:String=c.move=="externalPair"?"短HK53":"FR506";
            check(u.手枪 instanceof BaseItem && u.手枪.name==mainName,"elite configured main pistol item "+c.move);
            check(u.手枪2 instanceof BaseItem && u.手枪2.name=="FR506" && u.手枪2!==u.手枪
                && u.手枪2.value!==u.手枪.value,"elite independent second FR506 item "+c.move);
            check(u.手枪弹匣容量==(mainName=="FR506"?6:30) && u.手枪2弹匣容量==6,"elite independent real capacities "+c.move);
            check(u.手枪_装扮==(mainName=="FR506"?"枪-手枪-FR506":"枪-手枪-短HK53")
                && u.手枪2_装扮=="枪-手枪-FR506","elite two dressup authorities "+c.move);
            if(mainName=="短HK53")check(u.手枪属性.interval==100 && u.手枪2属性.interval==160
                && u.手枪属性.reloadType!="tube" && u.手枪2属性.reloadType=="tube",
                "external mixed pistol rates and reload types remain independent");
            if(c.move=="identityLong")check(u.掉落物.length==1 && u.掉落物[0].名字=="短HK53"
                && u.掉落物[0].概率==37,"explicit drop rules retain their original item and chance");
            else if(c.move=="identityMain" || c.move=="identityOff")
                check(u.掉落物==null,"no-equipment-drop and friendly initialization suppress automatic drops");
            else {
                var frDrops:Number=0,hkDrops:Number=0,rifleDrops:Number=0;
                for(var dropIndex:Number=0;dropIndex<u.掉落物.length;dropIndex++){
                    var drop:Object=u.掉落物[dropIndex];
                    if(drop.名字=="FR506")frDrops++;
                    if(drop.名字=="短HK53")hkDrops++;
                    if(drop.名字=="M4A1战术版")rifleDrops++;
                    check(typeof drop.名字=="string" && drop.概率==100,"standard automatic equipment drop rule names and chance");
                }
                check(rifleDrops==1 && frDrops==(mainName=="短HK53"?1:2) && hkDrops==(mainName=="短HK53"?1:0),
                    "drop rules preserve both independent default pistols or configured short HK53 plus FR506");
            }
    }
    private static function capture(data:Object):Void {
        var subUnit:MovieClip=library[data.发射者];
        if(subUnit.soldierSubweaponCall!=null){
            var subRecord:Object=subUnit.fixtureRecord,config:Object=subUnit.长枪副武器配置;
            subRecord.subshots=(subRecord.subshots|0)+1;
            var point:Object={x:0,y:0};subUnit.soldierMuzzleMarker(subUnit.man).localToGlobal(point);library.globalToLocal(point);
            check(Math.abs(data.shootX-point.x)<0.2 && Math.abs(data.shootY-point.y)<0.2,"NPC subweapon uses live muzzle "+subUnit._name);
            check(data.子弹威力==config.resolvedPower && data.子弹种类==config.bullet
                && data.发射间隔毫秒==config.cd && data.区域定位area==undefined && data.产生源==subUnit._name,"NPC subweapon keeps canonical projectile properties "+subUnit._name);
            return;
        }
        if(data.子弹种类=="普通爆炸"){
            var explosionUnit:MovieClip=library[data.发射者];
            explosionUnit.fixtureRecord.explosions++;explosionUnit.fixtureRecord.explosionData=data;return;
        }
        if(data.子弹种类=="高爆手雷" || data.子弹种类=="普通手雷"){
            var grenadeUnit:MovieClip=library[data.发射者];
            grenadeUnit.fixtureRecord.grenades++;grenadeUnit.fixtureRecord.grenadeData=data;return;
        }
        if(data.子弹种类=="近战子弹" && library[data.发射者].soldierAttackOwner.bash){
            var bashUnit:MovieClip=library[data.发射者];
            bashUnit.fixtureRecord.bashes++;bashUnit.fixtureRecord.bashData=data;return;
        }

        if(data.子弹种类=="近战子弹" && library[data.发射者].soldierAttackOwner.charge){
            var chargeUnit:MovieClip=library[data.发射者];
            chargeUnit.fixtureRecord.contacts++;chargeUnit.fixtureRecord.contactData=data;
            chargeUnit.fixtureRecord.contactAreaWasLive=data.区域定位area!=null;
            chargeUnit.fixtureRecord.contactBounds=data.区域定位area.getBounds(library);return;
        }
        var u:MovieClip=library[data.发射者],rec:Object=u.fixtureRecord;
        if(rec==undefined)return;
        var shot:Boolean=data.子弹种类!="近战子弹";
        rec.contractOk=rec.contractOk && data.shootZ==u.Z轴坐标 && data.百分比伤害==undefined && data.血量上限击溃==undefined;
        if(shot){
            var owner:Object=u.soldierAttackOwner;
            var sidearm:Boolean=rec.elite && owner.currentWeapon=="secondary";
            var slot:String=rec.elite?(sidearm?"手枪2":owner.kind=="retreat"?"手枪":"长枪"):"长枪";
            var d:Object=u[slot+"属性"];
            rec.slotShots[slot]++;
            if(rec.laneCase===true){
                var laneTarget:MovieClip=library[u.攻击目标];
                var laneGap:Number=Math.abs(laneTarget.Z轴坐标-u.Z轴坐标);
                if(laneGap>u.soldierTuning.laneRange){
                    rec.offLaneShots++;rec.minimumFireGap=Math.min(rec.minimumFireGap,laneGap);
                }
            }
            if(rec.elite)check(data.发射间隔毫秒==d.interval,"actual fired slot interval stamp "+slot);
            rec.powerOk=rec.powerOk && data.子弹威力==d.power && data.子弹威力!=u.空手攻击力;
            if(sidearm){rec.sidearmShots++;rec.sidearmTicks.push(ticks);rec.sidearmFrames+=u.man._currentframe+",";}
            else{rec.shots++;rec.shotFrames+=u.man._currentframe+",";rec.shotTicks.push(ticks);}
            rec.contractOk=rec.contractOk && data.霰弹值==d.split && data.Z轴攻击范围==d.bulletsize
                && data.子弹速度==d.velocity && data.子弹散射度==(rec.elite?
                    (u.standardShotMoving?data.移动子弹散射度:data.站立子弹散射度):d.diffusion)
                && data.声音==d.sound && data.发射效果==d.muzzle && data.子弹种类==d.bullet;
            var p:Object={x:0,y:0};
            if(sidearm)u.man.枪2.枪.装扮.枪口位置.localToGlobal(p);
            else u.man.枪.枪.装扮.枪口位置.localToGlobal(p);
            library.globalToLocal(p);
            rec.muzzleOk=rec.muzzleOk && Math.abs(data.shootX-p.x)<0.2 && Math.abs(data.shootY-p.y)<0.2;
        }else{
            rec.powerOk=rec.powerOk && data.子弹威力==100;
            rec.stabs++;
            rec.contractOk=rec.contractOk && data.子弹种类=="近战子弹" && data.子弹速度==0 && data.击倒率==10 && data.Z轴攻击范围==24;
            var bounds:Object=data.区域定位area.getBounds(library);
            rec.areaOk=rec.areaOk && Math.abs(bounds.xMax-bounds.xMin-135)<0.3 && Math.abs(bounds.yMax-bounds.yMin-135)<0.3;
            knifeDamageContract(data,u);
        }
    }
    private static function knifeDamageContract(data:Object,u:MovieClip):Void {
        check(typeof data.暴击=="function" && data.斩杀==5,"both phases emit standard crit and low execute");
        var damage:DamageResult=new DamageResult();
        _root.fixtureCrit=false;data.破坏力=100;
        CritDamageHandle.getInstance().handleBulletDamage(data,u,null,null,damage);
        check(data.破坏力==100 && _root.fixtureChance==10,"ordinary knife roll stays at one times");
        _root.fixtureCrit=true;data.破坏力=100;
        CritDamageHandle.getInstance().handleBulletDamage(data,u,null,null,damage);
        check(data.破坏力==600,"rare knife roll uses six times standard crit handler");
        var old:Number=u.soldierTuning.knifeCritMultiplier;u.soldierTuning.knifeCritMultiplier=99;
        check(data.暴击(data)==6,"emitted knife snapshots multiplier independently of later tuning");
        u.soldierTuning.knifeCritMultiplier=old;_root.fixtureCrit=false;
        for(var mode:Number=0;mode<5;mode++){
            var target:Object={hp:mode==3?1000:49,hp满血值:1000,损伤值:0};
            target.shield=new BaseShield(200,mode==2?100:0,0,0);
            damage=new DamageResult();
            if(mode==1)damage.dodgeStatus="MISS";
            if(mode==4){damage.scatterModelEnabled=true;damage.actualScatterUsed=3;damage.scatterMissCount=3;}
            ExecuteDamageHandle.getInstance().handleBulletDamage(data,u,target,null,damage);
            check(mode==0?target.hp==0 && target.shield.getCapacity()==0:target.hp>0,
                "standard execution hit/miss/shield/fullHP/allMiss case "+mode);
        }
    }
    private static function pixelHex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function writeNativeCapture(bd:BitmapData,key:String):Void {
        var readStart:Number=getTimer();
        var raster:Object=bd.getColorBoundsRect(0xffffffff,0xffe8e6e2,false);
        var left:Number=Math.max(0,raster.x),right:Number=Math.min(bd.width,raster.x+raster.width);
        var rows:Array=[];
        for(var row:Number=0;row<bd.height;row++) {
            if(raster.width==0 || row<raster.y || row>=raster.y+raster.height){
                rows.push("[SOLDIER_IMAGE_ROW] "+key+" "+row+" ffe8e6e2:"+bd.width);
            }else{
                var parts:Array=[];
                if(left>0)parts.push("ffe8e6e2:"+left);
                var last:Number=bd.getPixel32(left,row),count:Number=1;
                for(var col:Number=left+1;col<right;col++) {
                    var value:Number=bd.getPixel32(col,row);
                    if(value==last)count++;else{parts.push(pixelHex(last)+":"+count);last=value;count=1;}
                }
                parts.push(pixelHex(last)+":"+count);
                if(right<bd.width)parts.push("ffe8e6e2:"+(bd.width-right));
                rows.push("[SOLDIER_IMAGE_ROW] "+key+" "+row+" "+parts.join(","));
            }
        }
        var writeStart:Number=getTimer();
        if(typeof _root.cf6CaptureEndpoint=="string"){
            // Keep large pixel payloads out of CS6's synchronous Output panel.
            // Only the task-owned loopback collector is used by this template.
            var send:LoadVars=new LoadVars(),reply:LoadVars=new LoadVars();
            send.run=_root.cf6CaptureRun;send.key=key;
            send.data="[SOLDIER_IMAGE_BEGIN] "+key+" "+bd.width+" "+bd.height+"\n"
                +rows.join("\n")+"\n[SOLDIER_IMAGE_END] "+key+"\n";
            _root.cf6CapturePending++;
            reply.onLoad=function(ok:Boolean):Void {
                _root.cf6CapturePending--;
                if(!ok || this.ok!="1")_root.cf6CaptureErrors++;
            };
            send.sendAndLoad(_root.cf6CaptureEndpoint,reply,"POST");
            trace("[SOLDIER_IMAGE_HTTP] "+key);
        }else{
        trace("[SOLDIER_IMAGE_BEGIN] "+key+" "+bd.width+" "+bd.height);
        for(var batch:Number=0;batch<rows.length;batch+=32)trace(rows.slice(batch,batch+32).join("\n"));
        trace("[SOLDIER_IMAGE_END] "+key);
        }
        trace("[SOLDIER_CAPTURE_TIME] "+key+" readMs="+(writeStart-readStart)+" writeMs="+(getTimer()-writeStart)
            +" x="+raster.x+" y="+raster.y+" w="+raster.width+" h="+raster.height);
    }
    private static function checkHolsters(u:MovieClip,key:String):Void {
        var waist:MovieClip=u.man.腰挂;
        check(waist!=null,"native waist socket "+key);
        var waistPixels:BitmapData=new BitmapData(220,160,true,0);
        var waistMatrix:Matrix=new Matrix();waistMatrix.translate(120,110);
        waistPixels.draw(waist,waistMatrix);
        check((waistPixels.getPixel32(55,90)>>>24)>0,"empty leather holster renders "+key);
        check((waistPixels.getPixel32(117,120)>>>24)>0,"waist cloth renders without a body gap "+key);
        waistPixels.dispose();
        var owner:Object=u.soldierAttackOwner;
        var active:Boolean=owner.elite===true && owner.active===true && u.状态=="长枪攻击";
        var holders:Array=[waist.主手,waist.副手],slots:Array=["手枪","手枪2"];
        for(var h:Number=0;h<2;h++){
            var holder:MovieClip=holders[h],slot:String=slots[h];
            var equipped:Boolean=u.soldierIsElite===true && typeof u[slot+"_装扮"]=="string" && u[slot+"_装扮"]!="";
            var drawn:Boolean=active && (owner.reload?(!owner.smokePrepared && (owner.reloadPair===true || owner.reloadSlot==slot)):
                owner.kind=="retreat" && (h==0 || u.特种兵精英消融!="noSidearm"));
            check(holder._visible===(equipped && !drawn),"holster visibility "+key+" "+slot);
            if(equipped){
                check(holder.装扮!=null && holder.holsteredSkin==u[slot+"_装扮"],"holster uses configured skin "+key+" "+slot);
                check(holder.装扮!==u[slot+"_引用"],"holster cannot own live shooting reference "+key+" "+slot);
            }else check(holder.装扮==null,"ordinary waist contains no pistol skin "+key+" "+slot);
        }
        trace("[SOLDIER_HOLSTER] key="+key+" primary="+waist.主手._visible+" secondary="+waist.副手._visible
            +" mainSkin="+waist.主手.holsteredSkin+" offSkin="+waist.副手.holsteredSkin);
    }
    private static function checkBodyPixels(u:MovieClip,key:String):Void {
        var hidden:Array=[u.man.枪,u.man.枪2,u.man.腰挂,u.soldierShadow,u.人物文字信息],visibility:Array=[];
        for(var i:Number=0;i<hidden.length;i++){visibility.push(hidden[i]._visible);hidden[i]._visible=false;}
        var pixels:BitmapData=new BitmapData(640,430,true,0xffe8e6e2),m:Matrix=u.transform.matrix;
        m.a*=1.7;m.b*=1.7;m.c*=1.7;m.d*=1.7;m.tx=320;m.ty=350;pixels.draw(u,m);
        for(var j:Number=0;j<hidden.length;j++)hidden[j]._visible=visibility[j];
        var bodyPixels:Number=0;
        for(var y:Number=0;y<430;y+=3)for(var x:Number=0;x<640;x+=3)
            if(pixels.getPixel(x,y)!=0xe8e6e2)bodyPixels++;
        check(bodyPixels>350,"body remains visible without weapons, holsters or shadow "+key+" pixels="+bodyPixels);
        trace("[SOLDIER_BODY_PIXELS] "+key+" "+bodyPixels);pixels.dispose();
    }
    private static function render(u:MovieClip,key:String):Void {
        if(u==null || images[key])return;
        checkHolsters(u,key);
        if(key.indexOf("r9review-")==0)checkBodyPixels(u,key);
        if(_root.soldierCapture!==true){images[key]=true;return;}
        var info:Boolean=u.人物文字信息._visible;u.人物文字信息._visible=false;
        var bd:BitmapData=new BitmapData(640,430,true,0xffe8e6e2);
        var matrix:Matrix=u.transform.matrix,scale:Number=key=="airborne-shadow"?1.0:1.7;
        matrix.a*=scale;matrix.b*=scale;matrix.c*=scale;matrix.d*=scale;matrix.tx=320;matrix.ty=350;
        bd.draw(u,matrix);u.人物文字信息._visible=info;
        var visible:Number=0;
        for(var y:Number=0;y<430;y+=3)for(var x:Number=0;x<640;x+=3)if(bd.getPixel(x,y)!=0xe8e6e2)visible++;
        check(visible>200,"native pixels "+key+" "+visible);
        if(key.indexOf("elite-")==0){
            var bodyPixels:Number=0;
            for(var py:Number=0;py<315;py+=3)for(var px:Number=0;px<640;px+=3)if(bd.getPixel(px,py)!=0xe8e6e2)bodyPixels++;
            check(bodyPixels>200,"elite visible body above shadow "+key);
            if(u.man.枪!=null){
                // Skin bounds include a long laser beam; compare the actual
                // holder transform with the ordinary soldier instead.
                var gunMatrix:Matrix=u.man.枪.transform.matrix;
                var ordinaryMatrix:Matrix=probes[0].actor.man.枪.transform.matrix;
                var sx:Number=Math.sqrt(gunMatrix.a*gunMatrix.a+gunMatrix.b*gunMatrix.b);
                var sy:Number=Math.sqrt(gunMatrix.c*gunMatrix.c+gunMatrix.d*gunMatrix.d);
                var baseX:Number=Math.sqrt(ordinaryMatrix.a*ordinaryMatrix.a+ordinaryMatrix.b*ordinaryMatrix.b);
                var baseY:Number=Math.sqrt(ordinaryMatrix.c*ordinaryMatrix.c+ordinaryMatrix.d*ordinaryMatrix.d);
                var poseOwner:Object=u.soldierAttackOwner;
                var pistolPose:Boolean=poseOwner.elite===true && (poseOwner.reload
                    ? !poseOwner.smokePrepared && poseOwner.reloadSlot!="长枪" : poseOwner.kind=="retreat");
                if(pistolPose){baseX=baseY=1;}
                check(Math.abs(sx-baseX)<0.001 && Math.abs(sy-baseY)<0.001,"elite action weapon holder scale "+key);
                if(pistolPose)check(Math.abs(u.man.枪.枪._xscale-20)<0.001 && Math.abs(u.man.枪.枪._yscale-20)<0.001,
                    "elite standard pistol grip mount scale "+key);
                var guns:Number=0;
                for(var depth:Number=-16384;depth<0;depth++)if(u.man.getInstanceAtDepth(depth)._name=="枪")guns++;
                check(guns==1,"one live elite gun holder "+key+" count="+guns);
            }
            if(u.man.枪2!=null){
                if(key=="elite-retreat-0" || key=="elite-sidearmReload-0"){
                    var diagnosticGun:Object=u.man.枪2.枪.装扮,diagnosticRef:Object=u.手枪2_引用;
                    trace("[ELITE_FR506_DIAG] key="+key+" gun="+diagnosticGun+" ref="+diagnosticRef
                        +" same="+(diagnosticGun===diagnosticRef)+" muzzle="+diagnosticGun.枪口位置
                        +" gunUrl="+diagnosticGun._url+" refUrl="+diagnosticRef._url+" skinKey="+u.手枪2_装扮);
                }
                if(u.特种兵精英消融=="noSidearm")check(!u.man.枪2._visible,"elite sidearm ablation hidden "+key);
                else check(u.man.枪2._visible,"elite sidearm visible "+key);
                check(u.man.枪2.枪.装扮===u.手枪2_引用 && u.man.枪2.枪.装扮.枪口位置!=null,
                    "elite sidearm live muzzle "+key);
                var sideguns:Number=0;
                for(var sideDepth:Number=-16384;sideDepth<0;sideDepth++)
                    if(u.man.getInstanceAtDepth(sideDepth)._name=="枪2")sideguns++;
                check(sideguns==1,"one live elite sidearm holder "+key+" count="+sideguns);
            }
        }
        images[key]=true;
        trace("[SOLDIER_POSE] "+key+" state="+u.状态+" frame="+u.man._currentframe
            +" x="+u._x+" z="+u.Z轴坐标+" primary="+u.长枪.value.shot+" secondary="+u.手枪.value.shot);
        if(_root.soldierCapture===true && (!_root.soldierCaptureOnlyPairReload || key.indexOf("elite-pair-")==0)
            && (!_root.soldierCaptureOnlyShield || key.indexOf("shield-")==0)
            && (!_root.soldierCaptureOnlyElite || key.indexOf("elite-")==0 || key.indexOf("holster-")==0)) {
            trace("[SOLDIER_NATIVE_PIXELS] "+key+" "+visible);
            writeNativeCapture(bd,key);
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
        u.特种兵投掷物=false;u.soldierClock=100;u.soldierReadyAt=0;
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
        u.状态="击倒";u.浮空=true;u.hp=0;u.requestedState="none";u.soldierTick();
        check(u.requestedState=="none" && u.状态=="击倒","airborne lethal knockdown stays in airborne pose until landing");
        u.状态="倒地";u.浮空=false;u.倒地=true;u.requestedState="none";u.soldierTick();
        check(u.requestedState=="none" && u.状态=="倒地","landing lethal knockdown stays in down recovery until ground settlement");
        u.hp=1000;u.倒地=false;
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
        movementContract(u,target);
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
    private static function movementContract(u:MovieClip,target:MovieClip):Void {
        u.soldierCancelAttack();u.状态="长枪站立";u._x=200;u._y=u.Z轴坐标=200;
        u.攻击目标=target._name;u.soldierMovementTarget="";
        target._x=500;target._y=target.Z轴坐标=201;u.soldierNextShootAt=u.soldierClock+300;
        var savedData:Object=u.unitAI.data;var data:UnitAIData=new UnitAIData(u);
        data.target=target;data.xrange=0;data.zrange=24;data.xdistance=190;
        var combat:Object=new CombatModule(data);combat.superMachine={getActionCount:function():Number {return 0;}};
        combat.chase();check(u.下行===true,"real generic chase writes vertical motion for a one-pixel gap");
        for(var legacy:Number=0;legacy<4;legacy++)_root.敌人函数.行走.call(u);
        check(u.Z轴坐标==216,"old generic movement overshoots the tiny target gap");
        combat.chase();check(u.上行===true,"real generic chase reverses after overshoot");
        trace("[SOLDIER_MOVEMENT] legacyTargetZ="+target.Z轴坐标+" legacyUnitZ="+u.Z轴坐标+" reversal="+u.上行);
        u._x=200;u._y=u.Z轴坐标=200;u.soldierClearMovement();
        for(var tick:Number=0;tick<48;tick++){
            if((tick&3)==0)combat.chase();
            u.行走();
            check(u.Z轴坐标==200 && u._x==200,"movement consumer rejects generic cold-fire jitter frame "+tick);
        }
        trace("[SOLDIER_MOVEMENT] corrected48FrameDrift="+(u.Z轴坐标-200));
        target.Z轴坐标=target._y=250;
        var previous:Number=u.Z轴坐标;
        for(var align:Number=0;align<20;align++){
            combat.chase();u.行走();
            check(u.Z轴坐标>=previous && u.Z轴坐标<=238,"depth alignment converges without overshoot "+align);
            previous=u.Z轴坐标;
        }
        check(u.Z轴坐标==238 && !u.上行 && !u.下行,"alignment stops at inner twelve-pixel band");
        target.Z轴坐标=target._y=257;combat.chase();u.行走();
        check(u.Z轴坐标==238,"nineteen-pixel gap does not restart alignment inside outer band");
        target.Z轴坐标=target._y=263;combat.chase();u.行走();check(u.Z轴坐标>238,"gap above twenty-four pixels restarts alignment");
        var frozen:Number=u.Z轴坐标;_root.暂停=true;u.行走();_root.暂停=false;check(u.Z轴坐标==frozen,"paused movement stays frozen");
        target.hp=0;u.行走();check(!u.上行 && !u.下行 && !u.左行 && !u.右行,"invalid target clears owned movement");target.hp=1000;
        u._x=200;u._y=u.Z轴坐标=200;target._x=900;target.Z轴坐标=target._y=200;u.soldierClearMovement();
        for(var xTick:Number=0;xTick<45;xTick++)u.行走();
        check(u._x==480 && !u.左行 && !u.右行,"out-of-range approach settles at four-hundred-twenty pixels");
        var clock:Number=u.soldierClock;u.soldierClearMovement();_root.控制目标=u._name;u.上行=true;u.行走();_root.控制目标="__no_player";
        check(u.Z轴坐标==196 && u.soldierClock==clock,"manual control retains canonical walking");
        u.unitAI.data=savedData;u._x=200;u._y=u.Z轴坐标=200;u.soldierClearMovement();
    }
    private static function shieldDamageContract(u:MovieClip):Void {
        var expected:Number=1-u.soldierShieldReduction/100;
        check(u.soldierBuffError=="" && u.buffManager.getBuffById("霸体减伤_CF6特种兵持盾")!=null,"shield reduction is a real named Buff");
        check(Math.abs(u.damageTakenMultiplier-expected)<0.0001,"shield applies configured coefficient before downstream handlers");
        _root.技能函数.霸体减伤(u,30,0,"fixture-weak");u.buffManager.update(0);
        check(Math.abs(u.damageTakenMultiplier-expected)<0.0001,"weaker external reduction does not multiply shield reduction");
        _root.技能函数.霸体减伤(u,90,0,"fixture-strong");u.buffManager.update(0);
        check(Math.abs(u.damageTakenMultiplier-0.1)<0.0001,"stronger external reduction wins");
        _root.技能函数.移除霸体减伤(u,"fixture-strong");u.buffManager.update(0);
        check(Math.abs(u.damageTakenMultiplier-expected)<0.0001,"removing stronger source restores own shield Buff");
        _root.技能函数.移除霸体减伤(u,"fixture-weak");u.buffManager.update(0);
        var noise:Object=PinkNoiseEngine.getInstance(),oldNoise:Function=noise.randomFluctuation;
        noise.randomFluctuation=function(percent:Number):Number {return 1;};
        DamageManagerFactory.init();u.shield=new BaseShield(0,0,0,0);u.防御力=1;
        var bullet:Object={子弹威力:100,固伤:0,百分比伤害:0,霰弹值:1,伤害类型:"真伤",flags:0};
        bullet.damageManager=DamageManagerFactory.resolveForBullet(bullet);
        var before:Number=u.hp;DamageCalculator.calculateDamage(bullet,{伤害加成:0},u,1,"");
        trace("[SOLDIER_SHIELD_BUFF] multiplier="+u.damageTakenMultiplier+" input=100 hpLoss="+(before-u.hp));
        check(Math.abs(before-u.hp-100*expected)<0.001,"real DamageCalculator applies shield multiplier to committed HP loss");
        check(u.状态=="长枪站立" && Math.abs(u.soldierShieldGuardDamage-100*expected)<0.001,"light shield hit below 10 percent accumulates without crouch guard");
        u.状态="近战";u.hp-=120;
        check(u.状态=="近战","super-armor shield skill is not interrupted by 10 percent HP loss");
        u.状态="长枪站立";u.hp-=80;
        check(u.状态=="被击" && u.soldierShieldGuardDamage==0 && u.soldierPhase==1 && u.刚体
            && Math.abs(u.damageTakenMultiplier-expected)<0.0001,
            "10 percent shield HP loss in stand/move/ordinary shoot enters crouch guard while keeping frontal reduction and rigid armor");
        u.hp=before;u.状态改变("长枪站立");noise.randomFluctuation=oldNoise;
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
        if(ticks==16){render(cases[1].actor,"knife");render(cases[0].actor,"holster-ordinary-0");render(cases[16].actor,"holster-ordinary-1");}
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
                    check(rec.done==0 && e.actor.man._currentframe==14,"grab pose waits for external throw lifecycle "+r);
                } else {
                    check(rec.done==1,"hit/down/cancel recovery "+r+" done="+rec.done);
                }
                if(e.move=="knockdown")check(rec.physics==1 && rec.landings==1,"airborne and landing delegates "+r);
            }
            var needed:Array=["stand","shoot","knife","down","death-start","death-a0-middle","death-a0-late","death-a1-middle","death-a1-late","death-a2-late","airborne-shadow"];
            for(var z:Number=0;z<needed.length;z++)check(images[needed[z]]===true,"native image captured "+needed[z]);
        }
        eliteTick();laneTick();pairTick();roleTick();tacticalTick();completionTick();phaseTick();
    }
    private static function travelTrace(u:MovieClip,body:MovieClip,owner:Object):Void {
        if(_root.soldierCaptureTravel!==true || !owner.elite || owner.reload)return;
        var frame:Number=body._currentframe;
        if(owner.fixtureTravelFrames==undefined)owner.fixtureTravelFrames={};
        if(owner.fixtureTravelFrames[frame])return;
        owner.fixtureTravelFrames[frame]=true;
        trace("[ELITE_TRAVEL] kind="+owner.kind+" frame="+frame+" x="+u._x+" z="+u.Z轴坐标+" facing="+u.方向);
    }
    private static function eliteForwardContract(u:MovieClip,side:Number):Void {
        var saved:Object={x:u._x,z:u.Z轴坐标,direction:u.方向,target:u.攻击目标,
            hard:u.硬直中,mobility:u.eliteMobility,distance:u.eliteMoveDistance,frames:u.eliteMoveFrames,nextShoot:u.soldierNextShootAt};
        var target:MovieClip=library.createEmptyMovieClip("eliteForwardProbe"+side,library.getNextHighestDepth());
        target.hp=1000;target.area=target.createEmptyMovieClip("area",1);
        u.攻击目标=target._name;u.硬直中=false;u.eliteMobility=true;
        var sign:Number=side==0?1:-1;
        var owner:Object={kind:"run",first:166,last:205,logicalFrame:180,advanceSign:sign,faceSign:sign,target:target._name,motionFrames:0,strafeSign:1,slideMovedZ:0,slideZSign:0,shots:0,shotLimit:5,fireGrace:2,restFrames:30};
        target._x=u._x+sign*430;target.Z轴坐标=u.Z轴坐标;
        var before:Number=u._x;u.eliteMove(owner,u.man);
        check((u._x-before)*sign>0,"rifle running fire advances in entry direction "+side);
        target._x=u._x+sign*350;owner.kind="slide";owner.first=212;owner.last=248;owner.logicalFrame=214;owner.slideTravelBudget=620;owner.slideStepSpeed=16;owner.slideMovedX=0;owner.slideStalledFrames=0;
        before=u._x;u.eliteMove(owner,u.man);
        check((u._x-before)*sign>0,"rifle low slide advances toward its safe firing band "+side);
        target._x=u._x+sign*40;
        before=u._x;u.eliteMove(owner,u.man);
        check((u._x-before)*sign>0 && owner.kind=="slide","close target does not brake a committed slide "+side);
        target._x=u._x-sign*50;before=u._x;u.eliteMove(owner,u.man);
        check((u._x-before)*sign>0 && u.方向==(sign>0?"右":"左"),"crossing target does not reverse the sliding body "+side);
        target._x=u._x-sign*430;owner.logicalFrame=229;before=u._x;
        var beforeZ:Number=u.Z轴坐标;u.eliteMove(owner,u.man);
        check(u._x==before && u.Z轴坐标==beforeZ && owner.kind=="stand"
            && u.方向==(sign>0?"左":"右"),"completed slide stops and faces back in a standing pose "+side);
        u._x=saved.x;u._y=u.Z轴坐标=saved.z;u.方向改变(saved.direction);u.攻击目标=saved.target;
        u.硬直中=saved.hard;u.eliteMobility=saved.mobility;u.eliteMoveDistance=saved.distance;u.eliteMoveFrames=saved.frames;u.soldierNextShootAt=saved.nextShoot;
        delete u.standardShotMoving;target.removeMovieClip();
    }
    private static function eliteTick():Void {
        for(var i:Number=0;i<elites.length;i++){
            var c:Object=elites[i],u:MovieClip=c.actor,rec:Object=c.record;
            if(u.buffManager!=null)u.buffManager.update(1);
            if(ticks==188 && (c.move=="stand" || c.move=="externalPair" || c.move=="break")){
                u.方向改变(c.side==0?"右":"左");render(u,"holster-idle-"+c.move+"-"+c.side);
            }
            if(ticks==190){
                validateEliteEquipment(c,u);
                check(u.hp满血值==1000 && u.空手攻击力==100,"elite inherits fixture panel "+i);
                u.方向改变(c.side==0?"右":"左");
                if(c.move=="break"){
                    check(u.名字=="CF6特种兵·持盾一阶段" && u.damageTakenMultiplier==0.25,"elite hidden shield identity "+i);
                    c.weapon=u.长枪;c.pistol=u.手枪;c.sidearm=u.手枪2;c.version=u.version;
                    u.长枪.value.shot=2;u.手枪.value.shot=2;u.手枪2.value.shot=3;u.hp=0;
                }else{
                    var target:MovieClip=library.createEmptyMovieClip("eliteTarget"+i,library.getNextHighestDepth());
                    target.hp=1000;target.Z轴坐标=target._y=u.Z轴坐标;
                    target._x=u._x+(c.side==0?1:-1)*((c.move=="retreat" || c.move=="mobilityStiff")?180:c.move=="slide"?430:320);
                    target.area=target.createEmptyMovieClip("area",1);u.攻击目标=target._name;
                    var retreatMove:Boolean=(c.move=="retreat" || c.move=="mobilityStiff"
                        || c.move=="sidearmReload" || c.move=="sidearmInterrupt" || c.move=="noSidearm"
                        || c.move=="primaryReload" || c.move=="primaryInterrupt" || c.move=="externalPair"
                        || c.move.indexOf("identity")==0);
                    u.eliteNextAction=retreatMove?"retreat":c.move=="slide"?"slide":"stand";
                    if(c.move=="slide"){
                        u.soldierPendingSlide=true; // Direct action fixture; genuine smoke transition is exercised below.
                    }
                    if(c.move=="reload")u.长枪.value.shot=u.长枪弹匣容量;
                    if(c.move=="sidearmReload" || c.move=="sidearmInterrupt" || c.move=="primaryReload" || c.move=="primaryInterrupt"){
                        c.reloadSlot=c.move.indexOf("primary")==0?"手枪":"手枪2";
                        u[c.reloadSlot].value.shot=c.move.indexOf("Interrupt")<0?u[c.reloadSlot+"弹匣容量"]-2:3;
                        c.initialSidearmShot=u[c.reloadSlot].value.shot;
                    }
                    if((_root.soldierCaptureMotion===true || _root.soldierCaptureTravel===true) && c.side==0
                        && (c.move=="stand" || c.move=="retreat" || c.move=="slide")){
                        u.eliteCaptureFirstFrame=function(body:MovieClip,owner:Object):Void {
                            var unit:MovieClip=this;
                            var first:Number=owner.kind=="stand"?46:owner.kind=="retreat"?2:212;
                            var valid:Boolean=owner.age==0 && owner.logicalFrame==first
                                && body===unit.man && body._currentframe==first;
                            Cf6SoldierAssetTest.check(valid,"elite settled first capture "+owner.kind);
                            if(valid){
                                Cf6SoldierAssetTest.travelTrace(unit,body,owner);
                                if(_root.soldierCaptureMotion===true)Cf6SoldierAssetTest.render(unit,"elite-motion-"+owner.kind+"-0-"+first);
                            }
                        };
                    }
                    if(c.move=="sidearmReload" || c.move=="sidearmInterrupt")reloadDiag(u,"before");
                    u.状态改变("长枪攻击");
                }
            }
            if(c.reloadSlot!=undefined && !c.reloadRequested
                && u.soldierAttackOwner!=null && u.soldierAttackOwner.elite && !u.soldierAttackOwner.reload
                && u.soldierCanAct(u.man)){
                c.reloadRequested=true;u.eliteBeginReload(u.man,c.reloadSlot);reloadDiag(u,"begin");
            }
            if(ticks==201 && c.move=="mobilityStiff"){
                c.owner=u.soldierAttackOwner;c.frozenFrame=u.man._currentframe;c.travel=u.eliteMoveDistance;
                u.硬直中=true;
            }
            if(ticks==205 && c.move=="mobilityStiff"){
                check(u.soldierAttackOwner===c.owner && c.owner.active,"movement hitstop keeps elite owner "+i);
                check(u.man._currentframe>c.frozenFrame,"movement hitstop does not stop the attack pose "+i);
                check(u.eliteMoveDistance>c.travel,"committed running pose retains displacement through light stagger "+i);
            }
            if(ticks==224 && c.move=="mobilityStiff"){
                check(rec.shots>0 && u.eliteMoveDistance>c.travel,"light stagger retains bounded moving fire "+i);
            }
            if(ticks==225 && c.move=="mobilityStiff")u.硬直中=false;
            if(ticks==201 && c.move=="interrupt"){
                c.allowed=rec.shots;check(c.allowed>0,"elite interrupt follows real fire "+i);
                u.状态改变("被击");u.man.gotoAndPlay("a0");
            }
            if(ticks==201 && (c.move=="sidearmReload" || c.move=="sidearmInterrupt"))reloadDiag(u,"201");
            if(c.reloadSlot!=undefined && c.initialSidearmShot!=undefined
                && u[c.reloadSlot].value.shot<c.initialSidearmShot && u[c.reloadSlot].value.shot>=0){
                c.sawTubeProgress=true;
                if(c.move.indexOf("Interrupt")>=0 && !c.interruptedTube){
                    c.partialShot=u[c.reloadSlot].value.shot;
                    check(c.partialShot>0 && c.partialShot<c.initialSidearmShot && c.partialShot<u[c.reloadSlot+"弹匣容量"],
                        "FR506 interrupt follows a real partial tube commit "+i);
                    c.interruptedTube=true;u.状态改变("被击");u.man.gotoAndPlay("a0");
                }
            }
            if(c.fullEmpty && u.man.换弹标签===true && c.emptyBranch!==true)
                c.emptyBranch=u.man.perRoundReload===false && u.man.reloadCanSelectTube===true;
            if(ticks==230 && (c.move=="sidearmReload" || c.move=="primaryReload")){
                reloadDiag(u,"230");
                check(c.sawTubeProgress && u[c.reloadSlot].value.shot==0 && u.soldierReloadCount==1,
                    "FR506 partial tube completes before empty reload "+i);
                u[c.reloadSlot].value.shot=u[c.reloadSlot+"弹匣容量"];c.fullEmpty=true;c.reloadRequested=false;u.状态改变("长枪攻击");
            }
            if(ticks==230 && (c.move=="sidearmInterrupt" || c.move=="primaryInterrupt")){
                c.partialRetained=c.interruptedTube===true && u[c.reloadSlot].value.shot==c.partialShot
                    && rec.shots==0 && rec.sidearmShots==0 && u.soldierAttackOwner==null;
                check(c.partialRetained,"partial hand reload interruption preserves committed ammunition "+i);
                u[c.reloadSlot].value.shot=u[c.reloadSlot+"弹匣容量"];
                c.startedEmptyInterrupt=true;c.reloadRequested=false;u.状态改变("长枪攻击");
            }
            if(ticks==240 && c.startedEmptyInterrupt){
                check(u.man.换弹标签===true && u.man.perRoundReload===false
                    && u.soldierAttackOwner.reloadSlot==c.reloadSlot && u.man._currentframe<328,
                    "interrupt actual full-empty hand transaction before commit "+i);
                c.interruptedEmpty=true;u.状态改变("被击");u.man.gotoAndPlay("a0");
            }
            if(ticks==205 && (c.move=="stand" || c.move=="retreat" || c.move=="slide" || c.move=="reload"
                || c.move=="sidearmReload" || c.move=="sidearmInterrupt" || c.move=="noSidearm"))
                render(u,"elite-"+c.move+"-"+c.side);
            if(ticks==205 && c.move=="primaryReload")render(u,"holster-primaryReload-"+c.side);
            if(ticks==228 && c.move=="retreat")render(u,"elite-retreat-fire-"+c.side);
            if(ticks==242 && c.move=="primaryInterrupt")render(u,"holster-interrupted-"+c.side);
            if(ticks==246 && c.move=="slide")render(u,"elite-slide-low-"+c.side);
            if(ticks==268 && c.move=="slide")render(u,"elite-slide-tail-"+c.side);
            if(c.move=="slide" && u.soldierAttackOwner.elite && !u.soldierAttackOwner.reload){
                if(c.forwardPreviousX!=undefined)check((u._x-c.forwardPreviousX)*(c.side==0?1:-1)>=-0.001,"rifle action never actively backsteps "+i);
                c.forwardPreviousX=u._x;
            }
            if((_root.soldierCaptureMotion===true || _root.soldierCaptureTravel===true) && c.side==0
                && (c.move=="stand" || c.move=="retreat" || c.move=="slide") && u.soldierAttackOwner.elite){
                var mf:Number=u.man._currentframe;
                var firstFrame:Number=c.move=="stand"?46:c.move=="retreat"?2:212;
                var lastFrame:Number=c.move=="stand"?77:c.move=="retreat"?44:248;
                if(mf>=firstFrame && mf<=lastFrame){
                    travelTrace(u,u.man,u.soldierAttackOwner);
                    if(_root.soldierCaptureMotion===true)render(u,"elite-motion-"+c.move+"-0-"+mf);
                }
            }
            if(ticks==207)c.pausedFrame=u.man._currentframe;
            if(ticks==210 && c.move=="slide")check(u.man._currentframe==c.pausedFrame,"elite motion pauses with controller "+i);
            if(ticks==221 && c.move.indexOf("identity")==0){
                c.allowedTotal=rec.shots+rec.sidearmShots;
                check(c.allowedTotal>0,"identity replacement follows actual dual fire "+i);
                var identitySlot:String=c.move=="identityLong"?"长枪":c.move=="identityMain"?"手枪":"手枪2";
                var oldItem:BaseItem=u[identitySlot];
                u[identitySlot]=new BaseItem(oldItem.name,{level:oldItem.value.level,shot:oldItem.value.shot},oldItem.lastUpdate);
                c.identityInvalidated=!u.soldierCanAct(u.man);
                check(c.identityInvalidated,"all three equipment identities are authoritative "+identitySlot);
                check(!u.elitePistolShot("手枪",u.elitePistolMuzzleMarker(u.man,"手枪"),u.man.子弹属性)
                    && !u.elitePistolShot("手枪2",u.elitePistolMuzzleMarker(u.man,"手枪2"),u.man.子弹属性2),
                    "stale dual callbacks cannot adopt replacement equipment "+identitySlot);
            }
            if(ticks==225 && c.move=="break"){
                check(u.soldierPhase==2 && u.hp==350 && u.hp满血值==1000,"elite same 35 percent second life "+i);
                check(u.长枪===c.weapon && u.手枪===c.pistol && u.手枪2===c.sidearm && u.version==c.version,
                    "elite phase preserves weapon and initialization identities "+i);
                check(u.长枪.value.shot==2 && u.手枪.value.shot==2 && u.手枪2.value.shot==3,"elite phase preserves all three ammunition states "+i);
                check(!u.刚体 && !u.无敌 && u.damageTakenMultiplier==1,"elite adds no armor after break "+i);
                check(u.名字=="CF6特种精英·二阶段","elite identity revealed after break "+i);
                render(u,"elite-break-"+c.side);
            }
            if(ticks==300 && c.move!="break"){
                if(c.move=="sidearmReload" || c.move=="sidearmInterrupt")reloadDiag(u,"300");
                check(rec.powerOk && rec.contractOk && rec.muzzleOk,"elite standard bullet and live muzzle "+i);
                check(!u.刚体 && !u.无敌 && u.soldierInvalidMuzzleCount==0,"elite no extra armor or invalid muzzle "+i);
                if(c.move=="reload")check(u.长枪.value.shot==0 && u.soldierReloadCount==1,"elite standard reload commits once "+i);
                else if(c.move=="sidearmReload" || c.move=="primaryReload"){
                    check(u.手枪.value.shot==0 && u.手枪2.value.shot==0 && u.长枪.value.shot==0 && u.soldierReloadCount==2
                        && c.sawTubeProgress && c.emptyBranch && u.soldierWeaponError=="",
                        "FR506 partial tube and empty reload commit only their own ammunition "+i);
                }else if(c.move=="sidearmInterrupt" || c.move=="primaryInterrupt"){
                    check(c.partialRetained===true && c.sawTubeProgress && c.interruptedEmpty===true
                        && u[c.reloadSlot].value.shot==u[c.reloadSlot+"弹匣容量"]
                        && u[c.reloadSlot=="手枪"?"手枪2":"手枪"].value.shot==0
                        && rec.shots==0 && rec.sidearmShots==0 && u.soldierAttackOwner==null,
                        "both partial and full-empty hand interruptions grant no free refill "+i);
                }else if(c.move=="noSidearm"){
                    check(rec.shots==4 && rec.sidearmShots==0 && u.长枪.value.shot==0 && u.手枪.value.shot==4 && u.手枪2.value.shot==0,
                        "noSidearm keeps identical equipment but disables only sidearm behavior "+i);
                }else if(c.move.indexOf("identity")==0){
                    check(c.identityInvalidated===true && rec.shots+rec.sidearmShots==c.allowedTotal,"replaced slot rejects all late callbacks "+i);
                }else if(c.move=="interrupt")check(rec.shots==c.allowed,"elite stale shots rejected "+i);
                else{
                    var expectedPrimary:Number=c.move=="slide"?5:c.move=="stand"?5:4;
                    var isRetreat:Boolean=c.move=="retreat" || c.move=="mobilityStiff" || c.move=="externalPair";
                    var expectedSidearm:Number=isRetreat?4:0;
                    check(rec.slotShots.长枪==(isRetreat?0:expectedPrimary)
                        && rec.slotShots.手枪==(isRetreat?expectedPrimary:0) && rec.slotShots.手枪2==expectedSidearm,
                        "actual three-slot projectile emission accounting "+i);
                    check(rec.shots==expectedPrimary && rec.sidearmShots==expectedSidearm
                        && u.长枪.value.shot==(isRetreat?0:expectedPrimary)
                        && u.手枪.value.shot==(isRetreat?expectedPrimary:0) && u.手枪2.value.shot==expectedSidearm,
                        "elite exact primary and sidearm ammunition "+i);
                    if(c.move=="stand")check(u.eliteMoveDistance==0,"elite stationary action stays still "+i);
                    else check(u.eliteMoveDistance>0,"elite moving action moves actual unit "+i);
                    trace("[ELITE_ACTION_AUDIT] "+c.move+" side="+c.side+" primary="+rec.shots
                        +" sidearm="+rec.sidearmShots+" moveFrames="+u.eliteMoveFrames+" distance="+u.eliteMoveDistance);
                    var gap:Number=Math.ceil(u[isRetreat?"手枪属性":"长枪属性"].interval/(1000/30));
                    for(var j:Number=1;j<rec.shotTicks.length;j++)check(rec.shotTicks[j]-rec.shotTicks[j-1]>=gap,"elite real gun cadence "+i);
                    var sideGap:Number=Math.ceil(u.手枪2属性.interval/(1000/30));
                    for(var k:Number=1;k<rec.sidearmTicks.length;k++)
                        check(rec.sidearmTicks[k]-rec.sidearmTicks[k-1]>=sideGap,"elite FR506 independent cadence "+i);
                }
                check(u.soldierAttackOwner==null,"elite action releases ownership "+i);
                if(c.move=="slide" || c.move=="retreat" || c.move=="stand" || c.move=="mobilityStiff")check(u.eliteCompletedActions==1 && u.eliteInterruptedActions==0,"elite natural action audit "+i);
                if(c.move=="slide")eliteForwardContract(u,c.side);
                if(c.move=="interrupt")check(u.eliteInterruptedActions==1,"elite interrupt audit "+i);
            }
        }
    }
    private static function createLaneCases():Void {
        var actions:Array=["stand","retreat","run","slide"];
        for(var side:Number=0;side<2;side++)for(var a:Number=0;a<actions.length;a++)for(var timing:Number=0;timing<2;timing++){
            var rec:Object=record();rec.elite=true;rec.laneCase=true;rec.offLaneShots=0;rec.minimumFireGap=10000;
            var unit:MovieClip=library.attachMovie("敌人-CF6特种精英","laneCase"+lanes.length,
                library.getNextHighestDepth(),{fixtureRecord:rec,特种兵烟雾弹:false,长枪:"M4A1战术版",手枪:"FR506",手枪2:"FR506"});
            check(unit!=null,"attach lane suppression "+actions[a]+" "+side+" "+timing);
            lanes.push({actor:unit,record:rec,kind:actions[a],side:side,early:timing==0});
        }
    }
    private static function laneTick():Void {
        for(var i:Number=0;i<lanes.length;i++){
            var c:Object=lanes[i],u:MovieClip=c.actor,rec:Object=c.record;
            var label:String=c.kind+" side="+c.side+" early="+c.early;
            if(ticks==190){
                var target:MovieClip=library.createEmptyMovieClip("laneTarget"+i,library.getNextHighestDepth());
                target.hp=1000;target.area=target.createEmptyMovieClip("area",1);
                target._x=u._x+(c.side==0?1:-1)*(c.kind=="retreat"?180:430);
                target.Z轴坐标=target._y=u.Z轴坐标+96;
                target.攻击模式="长枪";target.动作A=c.kind=="slide";
                u.攻击目标=target._name;u.方向改变(c.side==0?"右":"左");
                c.target=target;u.soldierReadyAt=0;
                check(u.soldierChooseAttack(Math.abs(target._x-u._x),96,0)=="none",
                    "off-lane target still requires alignment before starting "+label);
                target.Z轴坐标=target._y=u.Z轴坐标;
                if(c.kind=="stand")u.特种兵战术_retreatTrigger=0;
                var picked:String=u.soldierChooseAttack(Math.abs(target._x-u._x),0,0);
                check(picked=="shoot" && u.eliteNextAction==(c.kind=="retreat"?"retreat":"run"),
                    "native AI offers regular moving fire from aligned target "+label);
                u.eliteNextAction=c.kind;if(c.kind=="slide")u.soldierPendingSlide=true;
                u.状态改变("长枪攻击");
            }
            var owner:Object=u.soldierAttackOwner;
            if(owner.elite && !c.departed && (c.early || rec.shots>0)){
                c.departed=true;c.beforeShots=rec.shots+rec.sidearmShots;c.owner=owner;
                check(c.early?c.beforeShots<2:c.beforeShots>0,"departure occurs at requested firing phase "+label);
            }
            if(c.departed && owner.elite && owner.active){
                // A continuously strafing target stays outside the firing lane, including during the slide.
                c.target.Z轴坐标=c.target._y=u.Z轴坐标+(c.side==0?96:-96);
                if(c.kind=="run")c.target._x=u._x+(c.side==0?430:-430);
                if(owner.burstOpen && c.deadline==undefined){c.deadline=owner.fireDeadline;c.nextShoot=u.soldierNextShootAt;}
            }
            if(c.departed && rec.done==1 && !c.completed){
                c.completed=true;c.endShots=rec.shots+rec.sidearmShots;
                var primary:Number=c.kind=="stand" || c.kind=="slide"?5:c.kind=="run"?8:4;
                var secondary:Number=c.kind=="retreat"?4:0;
                check(rec.shots==primary && rec.sidearmShots==secondary,"complete bounded burst despite lane departure "+label);
                check(rec.offLaneShots==primary+secondary-c.beforeShots && rec.offLaneShots>0
                    && rec.minimumFireGap>u.soldierTuning.laneRange,"real projectiles emitted outside target lane "+label);
                check(rec.powerOk && rec.contractOk && rec.muzzleOk,"suppression preserves muzzle damage spread and bullet Z width "+label);
                check(u.长枪.value.shot==(c.kind=="retreat"?0:primary)
                    && u.手枪.value.shot==(c.kind=="retreat"?primary:0) && u.手枪2.value.shot==secondary,
                    "suppression commits only actual slot ammunition "+label);
                check(u.soldierAttackOwner==null && !c.owner.active && c.owner.completed
                    && u.eliteCompletedActions==1 && u.eliteInterruptedActions==0,"suppression ends naturally and releases owner "+label);
                check(c.owner.fireDeadline==c.deadline && u.soldierNextShootAt==c.nextShoot
                    && u.soldierClock<c.nextShoot,"lane departure cannot extend fire deadline or erase rest "+label);
                var gap:Number=Math.ceil(u[c.kind=="retreat"?"手枪属性":"长枪属性"].interval*30/1000);
                for(var j:Number=1;j<rec.shotTicks.length;j++)check(rec.shotTicks[j]-rec.shotTicks[j-1]>=gap,
                    "suppression respects standard primary cadence "+label);
                var otherGap:Number=Math.ceil(u.手枪2属性.interval*30/1000);
                for(var k:Number=1;k<rec.sidearmTicks.length;k++)check(rec.sidearmTicks[k]-rec.sidearmTicks[k-1]>=otherGap,
                    "suppression respects independent offhand cadence "+label);
                trace("[ELITE_LANE_AUDIT] "+label+" primary="+rec.shots+" sidearm="+rec.sidearmShots
                    +" offLane="+rec.offLaneShots+" minGap="+rec.minimumFireGap+" endedAt="+u.soldierClock+" restUntil="+c.nextShoot);
            }
            if(ticks==300){
                check(c.completed===true && rec.shots+rec.sidearmShots==c.endShots && rec.done==1
                    && u.soldierAttackOwner==null && u.keepshooting==undefined,"no late or endless suppression fire "+label);
                u.攻击目标=c.target._name;c.target.Z轴坐标=c.target._y=u.Z轴坐标+(c.side==0?96:-96);
                if(c.kind=="run")c.target._x=u._x+(c.side==0?430:-430);
                u.soldierClock=Math.max(u.soldierClock,Math.max(u.soldierNextShootAt,u.soldierReadyAt));
                check(u.soldierChooseAttack(Math.abs(c.target._x-u._x),96,0)=="none",
                    "rest expiry does not start another off-lane attack "+label);
                var beforeGap:Number=Math.abs(c.target.Z轴坐标-u.Z轴坐标);
                u.行走();
                check(Math.abs(c.target.Z轴坐标-u.Z轴坐标)<beforeGap && u.soldierAttackOwner==null,
                    "post-burst walking actively realigns with target "+label);
                check(rec.shots+rec.sidearmShots==c.endShots,"lane realignment does not spend ammunition "+label);
                u.攻击目标="无";u.soldierClearMovement();
            }
        }
    }
    private static function createPairCases():Void {
        var modes:Array=["empty","uneven","partial","mixed","slowOffhand","interruptBefore","interruptAfter","interruptBoth","identity"];
        for(var side:Number=0;side<2;side++)for(var m:Number=0;m<modes.length;m++){
            var rec:Object=record();rec.elite=true;
            var unit:MovieClip=library.attachMovie("敌人-CF6特种精英","pairCase"+pairs.length,
                library.getNextHighestDepth(),{fixtureRecord:rec,特种兵烟雾弹:false,长枪:"M4A1战术版",手枪:modes[m]=="mixed"?"短HK53":"FR506",手枪2:"FR506"});
            check(unit!=null,"attach paired reload "+modes[m]+" "+side);
            pairs.push({actor:unit,record:rec,mode:modes[m],side:side,seen:{},captureFrames:[]});
        }
    }
    private static function pairTick():Void {
        for(var i:Number=0;i<pairs.length;i++){
            var c:Object=pairs[i],u:MovieClip=c.actor,rec:Object=c.record;
            var label:String=c.mode+" side="+c.side;
            if(ticks==190){
                u.方向改变(c.side==0?"右":"左");u.eliteNextAction="retreat";
                var pairTarget:MovieClip=library.createEmptyMovieClip("pairTarget"+i,library.getNextHighestDepth());
                pairTarget.hp=1000;pairTarget._x=u._x+(c.side==0?180:-180);pairTarget.Z轴坐标=u.Z轴坐标;
                pairTarget.area=pairTarget.createEmptyMovieClip("area",1);u.攻击目标=pairTarget._name;
                u.长枪.value.shot=3;u.手枪.value.shot=u.手枪弹匣容量;u.手枪2.value.shot=u.手枪2弹匣容量;
                if(c.mode=="uneven")u.手枪2.value.shot=2;
                if(c.mode=="partial"){u.手枪.value.shot=4;u.手枪2.value.shot=2;}
                if(c.mode=="slowOffhand" || c.mode=="interruptBoth")u.手枪2属性.reloadPenalty=100;
                c.beforeMain=u.手枪.value.shot;c.beforeOff=u.手枪2.value.shot;
                c.main=u.手枪;c.off=u.手枪2;c.startClock=u.soldierClock;
                u.状态改变("长枪攻击");u.eliteBeginReload(u.man,"手枪");
            }
            var owner:Object=u.soldierAttackOwner;
            // The transaction fixture enters after AVM1 has installed the destination body.
            // Empty-magazine movement is tested independently by emptyEvade/blockedEvade.
            if(owner.elite && !owner.reload && !c.started){
                c.startClock=u.soldierClock;u.eliteBeginReload(u.man,"手枪");owner=u.soldierAttackOwner;
            }
            if(owner.reload && !c.started){
                c.started=true;c.owner=owner;
                check(owner.reloadPair===true && owner.reloadEndFrame==365,"paired reload selects one shared animation "+label);
            }
            if(owner.reloadPair){
                var frame:Number=u.man._currentframe;
                if(frame>=331 && u.soldierReloadCount==1 && !c.burdenChecked){
                    c.burdenChecked=true;c.burden=u.man.reloadBurden;
                    check(c.burden==((c.mode=="slowOffhand" || c.mode=="interruptBoth")?200:117),"paired reload waits for slower configured hand "+label);
                    check(u.man.perRoundReload===false && !u.man.reloadCanSelectTube,"paired full-cycle reload cannot loop a hand "+label);
                }
                var mainCommitted:Boolean=owner.reloadMainCommitted===true;
                var offCommitted:Boolean=owner.reloadOffCommitted===true;
                check(mainCommitted==offCommitted,"both hands commit atomically "+label);
                check(u.手枪.value.shot==(mainCommitted?0:c.beforeMain)
                    && u.手枪2.value.shot==(offCommitted?0:c.beforeOff),"each hand waits for its own commit anchor "+label);
                check((!mainCommitted || frame>=363) && (!offCommitted || frame>=363),"paired ammunition cannot commit before authored anchor "+label);
                // AVM1 runs the destination frame script after the current enterFrame handler returns.
                if(frame>363)check(mainCommitted,"main commit runs before leaving its anchor "+label);
                if(frame>363)check(offCommitted,"offhand commit runs before leaving its anchor "+label);
                if(mainCommitted)c.sawMainCommit=true;
                if(offCommitted)c.sawCommit=true;
                if((mainCommitted && !c.repeatedMain && owner.reloadSlot=="手枪") || (offCommitted && !c.repeatedOff)){
                    u.eliteReloadCommit(u.man);
                    check(u.手枪.value.shot==0 && u.手枪2.value.shot==(offCommitted?0:c.beforeOff),"repeated hand commit is inert "+label);
                    if(offCommitted)c.repeatedOff=true;else c.repeatedMain=true;
                }
                if(_root.soldierCaptureOnlyPairReload===true && c.mode=="empty" && frame>=331 && frame<365
                    && (c.side==0 || c.captureFrames.length==0 || frame==351 || frame==363 || frame==364)){
                    if(!c.seen[frame]){c.seen[frame]=true;c.captureFrames.push(frame);}
                    render(u,"elite-pair-motion-"+c.side+"-"+frame);
                }
                if(_root.soldierCaptureOnlyPairReload===true && frame==351 && c.mode=="mixed")render(u,"elite-pair-mixed-"+c.side);
                if((c.mode=="interruptBefore" && frame>=350) || (c.mode=="interruptAfter" && mainCommitted) || (c.mode=="interruptBoth" && offCommitted)){
                    c.interrupted=true;u.状态改变("被击");u.man.gotoAndPlay("a0");
                }
                if(c.mode=="identity" && frame>=355 && !c.replaced){
                    c.replaced=true;u.手枪2=new BaseItem(c.off.name,{level:c.off.value.level,shot:c.off.value.shot},c.off.lastUpdate);
                    check(!u.soldierCanAct(u.man),"paired reload rejects changed equipment identity "+label);
                }
            }
            if(c.started && !c.finished && u.soldierAttackOwner==null){
                c.finished=true;c.elapsed=u.soldierClock-c.startClock;
                if(_root.soldierCaptureOnlyPairReload===true && c.mode=="empty")
                    trace("[ELITE_PAIR_CAPTURE_SEQUENCE] side="+c.side+" frames="+c.captureFrames.join(","));
                trace("[ELITE_PAIR_RELOAD] "+label+" elapsed="+c.elapsed+" animations="+u.soldierReloadCount
                    +" burden="+c.burden+" ammo="+u.手枪.value.shot+"/"+u.手枪2.value.shot+" committed="+c.sawCommit);
            }
            if(ticks==300){
                check(c.finished===true && u.soldierReloadCount==1 && u.soldierAttackOwner==null,"one animation releases paired ownership "+label);
                var cancelled:Boolean=c.mode=="interruptBefore" || c.mode=="interruptAfter" || c.mode=="interruptBoth" || c.mode=="identity";
                check(u.手枪.value.shot==((c.mode=="interruptBefore" || c.mode=="identity")?c.beforeMain:0)
                    && u.手枪2.value.shot==((c.mode=="interruptBefore" || c.mode=="identity")?c.beforeOff:0),
                    "pair cancellation preserves exactly committed ammunition "+label);
                check(u.长枪.value.shot==3 && rec.shots==0 && rec.sidearmShots==0,"paired reload never fires or touches rifle ammunition "+label);
                if(c.mode.indexOf("interrupt")==0)check(c.interrupted===true,"requested cancellation actually executes "+label);
                if(c.mode!="interruptBefore" && c.mode!="identity")check(c.repeatedOff===true,"main duplicate commit probe executes "+label);
                if(c.mode=="slowOffhand" || c.mode=="interruptBoth")check(c.repeatedOff===true,"offhand duplicate commit probe executes "+label);
                if(!cancelled){
                    check(c.elapsed>=34*c.burden/100 && c.elapsed<=Math.ceil(34*c.burden/100)+7,
                        "one simultaneous gesture uses the slower configured hand "+label);
                    check(u.eliteCompletedActions==1 && u.eliteInterruptedActions==0,"paired reload completes naturally once "+label);
                }
            }
        }
    }
    private static function createRoleCases():Void {
        var modes:Array=["bash","charge","chargeReload","grenade","grenadeCancel","grenadeConfig","eliteGear","grenadeAsset"];
        for(var side:Number=0;side<2;side++)for(var m:Number=0;m<modes.length;m++){
            var mode:String=modes[m],rec:Object=record();rec.grenades=0;rec.bashes=0;rec.explosions=0;
            var elite:Boolean=mode=="charge" || mode=="chargeReload" || mode=="eliteGear";
            rec.elite=elite;
            var unit:MovieClip=library.attachMovie(elite?"敌人-CF6持盾特种精英":mode=="bash"?"敌人-CF6持盾特种兵":link,
                "roleCase"+roles.length,library.getNextHighestDepth(),{fixtureRecord:rec,长枪:"M4A1战术版"});
            check(unit!=null,"attach role "+mode+" "+side);
            roles.push({actor:unit,record:rec,mode:mode,side:side});
        }
    }
    private static function roleTick():Void {
        for(var i:Number=0;i<roles.length;i++){
            var c:Object=roles[i],u:MovieClip=c.actor,rec:Object=c.record,label:String=c.mode+"/"+c.side;
            if(ticks==189){
                var target:MovieClip=library.createEmptyMovieClip("roleTarget"+i,library.getNextHighestDepth());
                target.hp=1000;target._x=u._x+(c.side==0?400:-400);target.Z轴坐标=target._y=u.Z轴坐标;
                target.createEmptyMovieClip("area",1);c.target=target;u.攻击目标=target._name;
                u.soldierReadyAt=0;u.soldierNextGrenadeAt=0;u.soldierNextShootAt=0;u.soldierClock=200;
                u.soldierTargetName=target._name;u.方向改变(c.side==0?"右":"左");c.x=u._x;
                check(u.man.腰挂.投掷物._visible===true,"grenade waist follows combat role "+label);
                check(u.man.腿挂匕首._visible==!u.soldierIsElite,"leg knife follows combat role "+label);
                if(c.mode=="bash"){
                    check(u.soldierChooseAttack(50,0,0)=="knife" && u.soldierMeleeKind=="bash","close shield chooses bash "+label);
                    u.状态改变("近战");
                }else if(c.mode=="charge" || c.mode=="chargeReload"){
                    check(u.soldierChooseAttack(400,0,0)=="shoot" && u.soldierChooseAttack(50,0,0)=="shoot","elite shield can charge at short range "+label);
                    if(c.mode=="chargeReload")u.长枪.value.shot=u.长枪弹匣容量;
                    u.状态改变("长枪攻击");
                }else if(c.mode=="grenadeAsset"){
                    u.攻击目标="无";u.是否为敌人=c.side==0;
                    c.projectile=library.attachMovie("高爆手雷","r8ActualGrenade"+i,library.getNextHighestDepth(),
                        {_x:u._x+100,_y:u.Z轴坐标-100,Z轴坐标:u.Z轴坐标,发射者名:u._name,子弹威力:6000,子弹敌我属性值:u.是否为敌人});
                    check(c.projectile!=null,"real grenade RSL linkage "+label);
                }else if(c.mode=="eliteGear"){
                    u.状态改变("近战");check(u.状态=="长枪站立","elite rejects inherited knife state "+label);
                    u.状态改变("投掷手雷");check(u.状态=="长枪站立","elite rejects grenade state "+label);
                    check(!u.soldierCanGrenade(),"elite has no throw capability "+label);u.攻击目标="无";
                }else{
                    if(c.mode=="grenadeConfig")u.特种兵投掷物="普通手雷";
                    check(u.soldierCanGrenade(),"configured grenade item is valid "+label);
                    check(u.soldierChooseAttack(400,60,0)=="grenade","grenade can cover adjacent lane "+label);
                    u.状态改变("投掷手雷");
                }
            }
            if(ticks==195 && c.mode=="grenadeCancel"){c.oldBody=u.man;u.状态改变("被击");u.man.gotoAndPlay("a0");u.soldierThrowGrenade(c.oldBody);}
            if(ticks==201 && c.mode=="charge")c.target.Z轴坐标+=96;
            if(ticks>=190 && ticks<240 && (ticks%4)==0 && c.side==0 && c.mode!="grenadeCancel" && c.mode!="eliteGear")
                render(u,"r8-"+c.mode+"-"+ticks);
            if(ticks==270 && c.mode=="bash")u.hp=0;
            if(ticks==290 && c.mode=="bash")check(u.soldierDebrisStampCount==1,"broken shield stamps independently once "+label);
            if(ticks==250){
                u.攻击目标="无";u.soldierClearMovement();
                if(c.mode=="bash"){
                    check(rec.bashes==1 && rec.stabs==0 && rec.bashData.水平击退速度==24,"one stronger horizontal shield impulse "+label);
                    check(rec.bashData.子弹威力==60 && rec.bashData.暴击({})==1 && rec.bashData.斩杀==0,"bash has no knife crit or execution "+label);
                }else if(c.mode=="charge"){
                    check(rec.shots>=6 && rec.shots<=u.soldierTacticalConfig.chargeShots && u.soldierAttackOwner==null
                        && Math.abs(u._x-c.x)>0 && Math.abs(u._x-c.x)<=300,"charge maintains standard fire through its full active window "+label);
                    check(rec.muzzleOk && rec.powerOk,"charge uses standard live muzzle and weapon power "+label);
                    check(u.soldierChooseAttack(400,0,0)=="none","charge rest survives completion "+label);
                }else if(c.mode=="chargeReload"){
                    check(rec.shots==0 && u.soldierReloadCount==1 && u.长枪.value.shot==0,"charge reload uses standard ammunition commit "+label);
                }else if(c.mode=="grenadeAsset"){
                    check(rec.explosions==1 && c.projectile._name==undefined,"real grenade lands and explodes once "+label);
                    var explosion:Object=rec.explosionData;
                    check(explosion.发射者==u._name && explosion.shootZ==u.Z轴坐标 && explosion.子弹敌我属性==u.是否为敌人,
                        "real explosion preserves either faction and ground coordinate "+label);
                    check(explosion.子弹威力==6000 && explosion.Z轴攻击范围==80,"real high explosive payload needs no passive "+label);
                }else if(c.mode=="grenadeCancel"){
                    check(rec.grenades==0,"interrupted throw and stale callback emit nothing "+label);
                }else if(c.mode=="grenade" || c.mode=="grenadeConfig"){
                    var data:Object=rec.grenadeData;
                    check(rec.grenades==1 && u.soldierGrenadeCount==1 && u.soldierAttackOwner==null,"single completed throw "+label);
                    check(data.发射者==u._name && data.发射者名==u._name && data.shootZ==200 && data.ZY比例==undefined,"throw preserves owner and independent ground lane "+label);
                    check(data.子弹种类==_root.getItemData(u.特种兵投掷物).data.bullet && data.子弹威力==_root.getItemData(u.特种兵投掷物).data.power,"throw reads configured item properties "+label);
                    check(data.速度X*(c.side==0?1:-1)>0 && u.soldierClock<u.soldierNextGrenadeAt,"throw direction and independent cooldown "+label);
                }
            }
        }
    }
    private static function captureTacticalScene(c:Object,key:String):Void {
        var u:MovieClip=c.actor,bd:BitmapData=new BitmapData(_root.soldierMotionCapture===true?960:640,430,true,0xffe8e6e2);
        checkBodyPixels(u,key);
        var objects:Array=[u];
        if(_root.soldierChargeEvasionCapture===true || _root.soldierMotionCapture===true)objects.push(c.target);
        for(var child:String in library){
            var cloud:MovieClip=library[child];
            if(cloud instanceof MovieClip && cloud.sourceUnit===u)objects.push(cloud);
        }
        for(var i:Number=0;i<objects.length;i++){
            var clip:MovieClip=objects[i],matrix:Matrix=clip.transform.matrix;
            matrix.a*=1.1;matrix.b*=1.1;matrix.c*=1.1;matrix.d*=1.1;
            matrix.tx=(_root.soldierMotionCapture===true?480:160)+(clip._x-c.x)*1.1;matrix.ty=330+(clip._y-c.z)*1.1;
            bd.draw(clip,matrix,clip.transform.colorTransform);
        }
        trace("[CF6_SCENE_FRAME] key="+key+" x="+u._x+" z="+u.Z轴坐标+" bodyFrame="+u.man._currentframe
            +" smoke="+u.soldierTacticalStats.smokes+" exits="+u.soldierTacticalStats.slideExits
            +" kind="+u.soldierAttackOwner.kind+" rootFrame="+u._currentframe+" shots="+u.soldierShotCount+" face="+(u.方向=="左"?-1:1)
            +" bashes="+u.soldierBashCount+" stabs="+u.soldierStabCount+" turns="+u.soldierTacticalStats.chargeTurns);
        var nativePixels:Number=0;
        for(var py:Number=0;py<bd.height;py+=3)for(var px:Number=0;px<bd.width;px+=3)
            if(bd.getPixel(px,py)!=0xe8e6e2)nativePixels++;
        trace("[SOLDIER_NATIVE_PIXELS] "+key+" "+nativePixels);
        writeNativeCapture(bd,key);bd.dispose();
    }
    private static function createTacticalCases():Void {
        var modes:Array=["smoke","smokeCancel","chargeNear","chargeBlocked","modernLine",
            "instructorLine","instructorMobile","instructorAdaptive","overrides","noSmoke",
            "evasion","evasionDisabled","evasionStale","evasionBlocked","instructorBareLine",
            "run","retreatBlocked","smokeTargetGone","smokeNoRifle","smokeOutside",
            "chargeTurn","instructorShieldClose","instructorShieldMobile",
            "instructorChargeClose","instructorChargeGone","instructorChargeOfflane"];
        for(var side:Number=0;side<2;side++)for(var m:Number=0;m<modes.length;m++){
            var mode:String=modes[m],rec:Object=record();rec.elite=mode!="modernLine";
            var init:Object={fixtureRecord:rec,fixtureTacticalModern:true,长枪:"M4A1战术版",手枪:"FR506",手枪2:"FR506"};
            var name:String=mode=="modernLine"?link:mode.indexOf("charge")==0?"敌人-CF6持盾特种精英":
                (mode=="instructorLine" || mode.indexOf("instructorShield")==0 || mode.indexOf("instructorCharge")==0)?"敌人-CF6持盾特种教官":mode.indexOf("instructor")==0?"敌人-CF6特种教官":"敌人-CF6特种精英";
            if(mode=="instructorLine" || mode=="instructorBareLine")init.特种兵策略="line";
            if(mode=="instructorMobile" || mode=="instructorShieldMobile" || mode.indexOf("instructorCharge")==0)init.特种兵策略="mobile";
            if(mode=="chargeTurn")init.特种兵战术_chargeMaxTurns=1;
            if(mode=="overrides"){
                init.特种兵策略="line";init.特种兵战术_eliteStandShots=2;init.特种兵战术_chargeSpeed=99;init.特种兵战术_chargePower=1.1;
            }
            if(mode=="noSmoke")init.特种兵烟雾弹=false;
            if(mode=="evasionDisabled")init.特种兵避弹=false;
            var unit:MovieClip=library.attachMovie(name,"tacticalCase"+tactics.length,library.getNextHighestDepth(),init);
            check(unit!=null,"attach R9 "+mode+" "+side);
            tactics.push({actor:unit,record:rec,mode:mode,side:side});
        }
    }
    private static function setupInstructorCloseCase(c:Object):Void {
        var u:MovieClip=c.actor,target:MovieClip=c.target,label:String=c.mode+"/"+c.side;
        // Keep the fixture target through two completed attacks, as the real
        // targeting service does. Do not force any follow-up attack state.
        u.动画完毕=function():Void {
            this.fixtureRecord.done++;this.倒地=false;
            if(this.fixtureRecord.done>=2)this.攻击目标="无";
            this.状态改变(this.hp>0?"长枪站立":"血腥死");
        };
        check(u.soldierTacticalConfig.chargeMaxTurns==0,"instructor defaults to a committed straight charge "+label);
        if(c.mode.indexOf("instructorShield")==0){
            check(u.soldierSelectStrategy(40,0)=="mobile","close defence also works under mobile strategy "+label);
            u.soldierNextShootAt=99999;
            check(u.soldierChooseAttack(40,25,0)=="none" && u.soldierChooseAttack(40,0,86)=="none",
                "close priority does not bypass lane or target height "+label);
            u.soldierNextMeleeAt=u.soldierClock+18;
            check(u.soldierChooseAttack(40,0,0)=="none","melee cooldown cannot fall through into another charge "+label);
            u.soldierNextMeleeAt=0;
            check(u.soldierChooseAttack(40,0,0)=="knife" && u.soldierMeleeKind=="bash",
                "ready shield bash takes priority despite ranged recovery "+label);
            // Another fixture toggles the global pause at ticks 207-210 without
            // stopping these independent art timelines. Start after that window.
            u.soldierReadyAt=u.soldierClock+24;
        }else{
            check(u.soldierChooseAttack(150,0,0)=="shoot" && !u.soldierShieldCoverFire,"mobile instructor starts a real charge "+label);
            u.状态改变("长枪攻击");c.chargeOwner=u.soldierAttackOwner;
        }
    }
    private static function instructorCloseTick(c:Object):Void {
        var u:MovieClip=c.actor,owner:Object=u.soldierAttackOwner,rec:Object=c.record;
        var label:String=c.mode+"/"+c.side,sign:Number=c.side==0?1:-1,config:Object=u.soldierTacticalConfig;
        var afterCharge:Boolean=c.mode.indexOf("instructorCharge")==0;
        if(afterCharge && owner.charge && owner.age>=config.chargeWindupFrames+config.chargeActiveFrames && !c.closePrepared){
            c.closePrepared=true;c.target._x=u._x+sign*40;
            c.target._y=c.target.Z轴坐标=u.Z轴坐标;
            if(c.mode=="instructorChargeGone")c.target.hp=0;
            if(c.mode=="instructorChargeOfflane"){
                c.target._y=c.target.Z轴坐标=u.Z轴坐标+80;
                u.移动=function():Void {};
            }
        }
        if(afterCharge && rec.done>0 && c.chargeDoneClock==undefined)c.chargeDoneClock=u.soldierClock;
        if(owner.action=="knife" && c.firstMeleeClock==undefined){
            c.firstMeleeClock=u.soldierClock;
            check(owner.bash,"first close response uses shield push "+label);
            if(afterCharge){
                check(c.closePrepared && c.chargeOwner.age>=config.chargeWindupFrames+config.chargeActiveFrames+config.chargeRecoveryFrames
                    && !c.chargeOwner.active,"close follow-up preserves complete charge recovery "+label);
                check(c.chargeDoneClock!=undefined && u.soldierClock-c.chargeDoneClock<=4
                    && u.soldierClock<u.soldierNextShootAt,"first AI decision can melee during charge shooting cooldown "+label);
            }
        }
        if(ticks==320){
            if(c.mode.indexOf("instructorShield")==0){
                check(rec.bashes==1 && rec.stabs==1 && rec.done==2 && rec.shots==0,
                    "autonomous close sequence completes bash then knife while bash recharges "+label);
                check(rec.bashData.水平击退速度==24 && rec.bashData.子弹威力==60,
                    "close priority preserves the shield damage and knockback contract "+label);
            }else if(c.mode=="instructorChargeClose"){
                check(rec.done==2 && rec.bashes==1 && rec.stabs==0 && u.soldierChargeCount==1,
                    "charge followed by one close bash completes without another charge "+label);
            }else{
                check(c.closePrepared && rec.done==1 && rec.bashes==0 && rec.stabs==0,
                    "gone or off-lane target receives no forced follow-up melee "+label);
            }
        }
    }
    private static function tacticalTick():Void {
        for(var i:Number=0;i<tactics.length;i++){
            var c:Object=tactics[i],u:MovieClip=c.actor,rec:Object=c.record,label:String=c.mode+"/"+c.side;
            var sign:Number=c.side==0?1:-1;
            if(ticks==190){
                var target:MovieClip=library.createEmptyMovieClip("tacticalTarget"+i,library.getNextHighestDepth());
                target.hp=1000;target._x=u._x+sign*((c.mode=="chargeNear" || c.mode=="chargeTurn")?90:
                    c.mode.indexOf("instructorShield")==0?40:c.mode.indexOf("instructorCharge")==0?150:400);target._y=target.Z轴坐标=u.Z轴坐标;
                var area:MovieClip=target.createEmptyMovieClip("area",1);
                if((_root.soldierChargeEvasionCapture===true || _root.soldierMotionCapture===true) && c.side==0)area.lineStyle(2,0x25845f,100);
                area.beginFill(0,0);area.moveTo(-20,-80);area.lineTo(20,-80);area.lineTo(20,0);area.lineTo(-20,0);area.lineTo(-20,-80);area.endFill();
                u.攻击目标=target._name;u.soldierTargetName=target._name;c.target=target;
                u.soldierReadyAt=u.soldierNextShootAt=0;u.soldierNextGrenadeAt=99999;u.soldierClock=200;
                u.方向改变(sign>0?"右":"左");c.x=u._x;c.z=u.Z轴坐标;
                check(u.soldierTacticalConfigErrors==(c.mode=="overrides"?1:0),"spawn configuration validated "+label);
                check(u.soldierTacticalConfig.chargeSpeed==1.25,"invalid overrides cannot leak to other units "+label);
                if(c.mode=="overrides")check(u.soldierTacticalConfig.chargePower==1.1,"valid scalar override retained "+label);
                if(c.mode.indexOf("smoke")==0 || c.mode=="noSmoke"){
                    target.动作A=true;target.攻击模式="长枪";
                    check(u.soldierChooseAttack(400,0,0)=="shoot" && u.eliteNextAction=="run","regular run fire does not require smoke "+label);
                    u.手枪.value.shot=u.手枪弹匣容量;u.手枪2.value.shot=u.手枪2弹匣容量;
                    u.eliteNextAction="retreat";u.状态改变("长枪攻击");u.eliteBeginReload(u.man,"手枪");
                    c.slideZ=u.Z轴坐标;
                    if(c.mode=="smoke")c.target._y=c.target.Z轴坐标=u.Z轴坐标+sign*48;
                    if(c.mode=="smokeNoRifle")u.长枪.value.shot=u.长枪弹匣容量;
                }else if(c.mode=="retreatBlocked"){
                    u.eliteNextAction="retreat";u.状态改变("长枪攻击");
                }else if(c.mode.indexOf("instructorShield")==0 || c.mode.indexOf("instructorCharge")==0){
                    setupInstructorCloseCase(c);
                }else if(c.mode=="chargeNear" || c.mode=="chargeTurn" || c.mode=="chargeBlocked"){
                    check(u.soldierChooseAttack(c.mode=="chargeBlocked"?400:90,0,0)=="shoot","shield charge available in confined distance "+label);
                    if(c.mode=="chargeNear"){
                        check(!u.soldierChargeContact({target:target._name,sign:sign,lastChargeX:u._x,age:0}),
                            "edge touching cannot spend the charge contact before damage overlap "+label);
                    }
                    if(c.mode=="chargeBlocked")u.移动=function():Void {};
                    u.状态改变("长枪攻击");
                }else if(c.mode.indexOf("evasion")==0){
                    u._btFrame=_root.帧计时器.当前帧数-(c.mode=="evasionStale"?5:0);u._btCount=2;u._btMinETA=6;
                    var shouldEvade:Boolean=c.mode=="evasion" || c.mode=="evasionBlocked";
                    check(u.soldierChooseAttack(400,0,0)=="shoot" && u.eliteNextAction==(shouldEvade?"retreat":"run"),
                        "existing bullet warning selects only enabled fresh reactive withdrawal "+label);
                    if(c.mode=="evasionBlocked"){
                        u.soldierPendingEvasion.zSign=-1;u.fixtureOriginalMove=u.移动;
                        u.移动=function(direction:String,speed:Number):Void {
                            if(direction!="上")this.fixtureOriginalMove.call(this,direction,speed);
                        };
                    }
                    check(typeof u.soldierThreatApi.register=="function","shared runtime threat scanner is present "+label);
                    u.状态改变("长枪攻击");
                }else if(c.mode=="modernLine" || c.mode=="instructorLine" || c.mode=="instructorBareLine"){
                    check(u.soldierTacticalConfig.rifleShots==6,"positional fire default budget "+label);
                    check(u.soldierChooseAttack(400,0,0)=="shoot","positional fire selected "+label);
                    if(c.mode=="instructorLine")check(u.soldierShieldCoverFire,"instructor can brace and fire behind shield "+label);
                    u.状态改变("长枪攻击");
                }else if(c.mode=="instructorAdaptive"){
                    c.weapon=u.长枪;c.offhand=u.手枪2;c.version=u.version;u.长枪.value.shot=2;
                    u.soldierNextGrenadeAt=777;
                    check(u.soldierSelectStrategy(400,0)=="line","instructor selects stable firing lane "+label);
                    u.hp-=10;u.soldierTacticalObserve();u.soldierClock++;
                    check(u.soldierSelectStrategy(100,0)=="line","strategy commitment resists frame-to-frame oscillation "+label);
                    u.soldierClock+=u.soldierTacticalConfig.strategyHoldFrames;
                    check(u.soldierSelectStrategy(100,0)=="mobile","pressure and close range release mobile strategy "+label);
                    check(u.长枪===c.weapon && u.手枪2===c.offhand && u.长枪.value.shot==2
                        && u.version===c.version && u.soldierNextGrenadeAt==777,"strategy switch preserves equipment ammo and cooldown authority "+label);
                    target._x=u._x+sign*180;
                    u.soldierChooseAttack(180,0,0);u.状态改变("长枪攻击");
                }else{
                    if(c.mode=="instructorMobile")target._x=u._x+sign*180;
                    u.soldierChooseAttack(Math.abs(target._x-u._x),0,0);if(c.mode=="overrides")u.eliteNextAction="stand";u.状态改变("长枪攻击");
                }
                if(u.soldierIsInstructor){
                    check(u.man.腿挂匕首._visible && u.man.腰挂.投掷物._visible,"instructor carries both role tools "+label);
                    check(u.名字.indexOf("教官")>=0,"instructor identity survives phase initialization "+label);
                }
            }
            if(ticks>190 && (c.mode.indexOf("smoke")==0 || c.mode=="noSmoke") && !c.forcedReload
                && u.soldierAttackOwner.elite && !u.soldierAttackOwner.reload){
                c.forcedReload=true;u.eliteBeginReload(u.man,"手枪");
            }
            if(ticks>190 && ticks<250 && (c.mode=="chargeNear" || c.mode=="chargeTurn")){
                if(c.mode=="chargeNear"){
                    check((u._x-c.x)*sign>=((c.previousChargeX==undefined?c.x:c.previousChargeX)-c.x)*sign,
                        "default charge never reverses its travelled direction "+label);
                    c.previousChargeX=u._x;
                }
                c.furthest=Math.max(c.furthest==undefined?0:c.furthest,(u._x-c.x)*sign);
                if(ticks==205 && c.side==1){u.硬直中=true;u.状态改变("被击");}
                if(ticks==210 && c.side==1)u.硬直中=false;
            }
            if(ticks==200 && c.mode=="smokeTargetGone")c.target.hp=0;
            if(ticks==200 && c.mode=="smokeOutside")c.target._x=u._x+sign*1200;
            if(ticks==210 && c.mode=="retreatBlocked")u.移动=function():Void {};
            if(ticks==200 && c.mode=="smokeCancel"){
                c.oldBody=u.man;u.状态改变("被击");u.man.gotoAndPlay("a0");u.eliteReloadEnd(c.oldBody);
            }
            if(ticks>190 && rec.done>0 && c.doneTick==undefined)c.doneTick=ticks;
            var active:Object=u.soldierAttackOwner;
            if(active!=null && c.mode.indexOf("smoke")==0){
                if(active.reload){
                    check(u._x==c.x && u.Z轴坐标==c.z,"concealed reload uses a planted pose "+label);
                    c.reloadOwner=active;c.reloadFrame=ticks;
                }else if(c.mode=="smoke" && active.kind=="slide" && c.slideStart==undefined){
                    c.slideStart=ticks;
                    trace("[R12_SMOKE_TRANSITION] "+label+" tick="+ticks+" reloadTick="+c.reloadFrame
                        +" start="+active.startedAt+" complete="+c.reloadOwner.completedAt+" first="+active.first+" actual="+u.man._currentframe);
                    check(active!==c.reloadOwner && c.reloadOwner.completed && !c.reloadOwner.active,
                        "smoke hands ownership directly to a fresh slide token "+label);
                    check(active.startedAt==c.reloadOwner.completedAt && active.first==212 && u.man._currentframe>=212 && u.man._currentframe<=214,
                        "smoke enters low slide without run frame or idle gap "+label);
                    check(c.reloadOwner.smokeCloud.sourceOwner===active && c.reloadOwner.smokeCloud.coverSlideFrames==6,
                        "same smoke cloud covers the slide windup handoff "+label);
                    check(u.手枪.value.shot==0 && u.手枪2.value.shot==0 && u.soldierReloadCount==1,
                        "both pistol commits finish before immediate slide "+label);
                }
            }
            if(active!=null && !active.reload && (active.kind=="retreat" || active.kind=="run")){
                if(c.motionOwner===active && c.motionFrame!=active.logicalFrame && !_root.暂停
                    && active.logicalFrame>9 && active.logicalFrame!=166 && ticks!=210){
                    check(Math.abs(u._x-c.motionX)+Math.abs(u.Z轴坐标-c.motionZ)>0.1,
                        "advancing running frames have real displacement "+label+"/"+active.logicalFrame);
                    check(u.方向==(active.faceSign>0?"右":"左"),"committed motion preserves its facing "+label);
                }
                c.motionOwner=active;c.motionFrame=active.logicalFrame;c.motionX=u._x;c.motionZ=u.Z轴坐标;
            }
            if(c.mode=="smoke" && c.slideStart!=undefined && ticks==c.slideStart+15){
                c.frozenZ=u.Z轴坐标;c.target._y=c.target.Z轴坐标=u.Z轴坐标-sign*96;
            }
            if(ticks==260){
                if(c.mode=="smoke" || c.mode=="noSmoke"){
                    check(u.手枪.value.shot==0 && u.手枪2.value.shot==0 && u.soldierReloadCount==1,
                        "smoke movement retains one standard dual reload commit "+label);
                    check(u.soldierTacticalStats.smokes==(c.mode=="smoke"?1:0)
                        && u.soldierTacticalStats.smokeReloads==(c.mode=="smoke"?1:0),"configured smoke capability is respected "+label);
                    if(c.mode=="smoke")check(c.slideStart!=undefined && u.soldierTacticalStats.slideExits==1
                        && u.soldierSlidePermit==null && Math.abs(u._x-c.x)>0,"successful reload immediately slides "+label);
                    else check(u.soldierSlidePermit==null && u._x==c.x && u.soldierTacticalStats.slideExits==0,"disabled smoke grants no exit "+label);
                }else if(c.mode=="smokeCancel"){
                    check(u.手枪.value.shot==6 && u.手枪2.value.shot==6 && u.soldierSlidePermit==null
                        && u.soldierTacticalStats.smokeReloads==0,"interrupted reload cannot refill or grant exit "+label);
                }else if(c.mode=="chargeNear" || c.mode=="chargeTurn"){
                    check(rec.contacts==1 && u.soldierTacticalStats.chargeContacts==1,"one real collision payload per close charge "+label);
                    check(rec.contactData.水平击退速度==10 && rec.contactData.子弹威力==125 && rec.contactData.斩杀==0,
                        "charge has configured knockback without knife execution "+label);
                    check(rec.contactAreaWasLive && rec.contactData.发射者==u._name,"charge emits a world-fixed live area and shooter "+label);
                    check(c.furthest>150 && c.doneTick>=235 && rec.shots>=6,
                        "contact does not stop passage or consume the remaining firing window "+label);
                    check(u.soldierTacticalStats.chargeTurns==(c.mode=="chargeTurn"?1:0),"turning requires an explicit external override "+label);
                    if(c.mode=="chargeNear")check((u._x-c.target._x)*sign>u.soldierTuning.knifeRange
                        && Math.abs((u._x-c.x)*sign-c.furthest)<0.01,"straight charge leaves usable firing distance "+label);
                }else if(c.mode=="chargeBlocked"){
                    check(u._x==c.x && rec.contacts==0 && u.soldierTacticalStats.blockedMoves==1
                        && c.doneTick<230,"wall blockage ends charge early without phantom contact "+label);
                }else if(c.mode.indexOf("instructorShield")==0 || c.mode.indexOf("instructorCharge")==0){
                    // These cases continue through their real melee timelines to tick 320.
                }else if(c.mode=="modernLine" || c.mode=="instructorLine" || c.mode=="instructorBareLine"){
                    check(rec.shots==6 && rec.powerOk && rec.muzzleOk,"six standard positional shots with unchanged weapon power "+label);
                    if(c.mode=="instructorLine")check(u._x==c.x && u.soldierChargeCount==0,"instructor line policy does not masquerade as a charge "+label);
                }else if(c.mode.indexOf("evasion")==0){
                    var evaded:Boolean=c.mode=="evasion" || c.mode=="evasionBlocked";
                    check(u.soldierTacticalStats.evasions==(evaded?1:0),"reactive evade action is counted once "+label);
                    if(evaded){
                        check(Math.abs(u.Z轴坐标-c.z)>24 && Math.abs(u.Z轴坐标-c.z)<=u.soldierTacticalConfig.retreatZBudget+0.01
                            && Math.abs(u._x-c.x)>24 && Math.abs(u._x-c.x)<=u.soldierTacticalConfig.retreatDistance+0.051
                            && rec.sidearmShots>0,"dual firing withdrawal reaches a different bounded lane "+label);
                        u._btFrame=_root.帧计时器.当前帧数;u.soldierNextShootAt=0;
                        check(!u.soldierTryEvasion(400,0),"fresh bullets cannot bypass evasion recovery "+label);
                    }else check(u.Z轴坐标==c.z,"disabled or stale threat cannot cause drift "+label);
                }else if(c.mode=="overrides")check(rec.shots==2,"external tactical override changes real emission budget "+label);
                else if(c.mode=="run")check(rec.shots>0 && u.eliteMoveDistance>0 && u.soldierTacticalStats.smokes==0,"ordinary selection executes moving rifle fire "+label);
                else if(c.mode=="retreatBlocked")check(c.doneTick<=212 && u.soldierAttackOwner==null,"blocked backstep exits moving pose immediately "+label);
                else if(c.mode.indexOf("smoke")==0)check(u.soldierTacticalStats.slideExits==0 && u.soldierSlidePermit==null
                    && u.手枪.value.shot==0 && u.手枪2.value.shot==0,"invalid exit target or empty rifle cannot start a slide "+label);
                else check(rec.sidearmShots>0 && rec.powerOk && rec.muzzleOk,"instructor mobile strategy uses standard independent pistols "+label);
            }

            if(ticks>=190 && (c.mode.indexOf("instructorShield")==0 || c.mode.indexOf("instructorCharge")==0))instructorCloseTick(c);
            if(_root.soldierCloseCombatCapture===true && c.side==0 && ticks>=190 && ticks%2==0
                && ((c.mode=="chargeNear" && ticks<=250)
                    || ((c.mode=="instructorShieldClose" || c.mode=="instructorChargeClose") && ticks<=320)))
                captureTacticalScene(c,"r13scene-"+c.mode+"-"+ticks);
            if(_root.soldierTacticalCapture===true && _root.soldierTacticalSceneCapture!==false && c.mode=="smoke" && c.side==0 && ticks>=190 && ticks<=360 && ticks%2==0)
                captureTacticalScene(c,"r9scene-smoke-"+ticks);
            if(_root.soldierChargeEvasionCapture===true && c.side==0 && (c.mode=="chargeNear" || c.mode=="evasion") && ticks>=190 && ticks<=270 && ticks%2==0)
                captureTacticalScene(c,"r10scene-"+c.mode+"-"+ticks);
            if(_root.soldierMotionCapture===true && _root.soldierCloseCombatCapture!==true && c.side==0 && ticks>=190 && ticks<=278 && ticks%2==0
                && (c.mode=="smoke" || c.mode=="instructorLine" || c.mode=="instructorBareLine" || c.mode=="run" || c.mode=="evasion" || c.mode=="retreatBlocked"))
                captureTacticalScene(c,"r12scene-"+c.mode+"-"+ticks);
            if(ticks==400 && c.mode=="smoke"){
                check(u.soldierTacticalStats.slideExits==1 && u.soldierSlidePermit==null,"smoke exit cannot repeat itself "+label);
                check((c.frozenZ-c.slideZ)*sign>0 && Math.abs(c.frozenZ-c.slideZ)<=u.soldierTacticalConfig.slideZBudget,
                    "slide front segment tracks Z within its total budget "+label);
                check(u.Z轴坐标==c.frozenZ,"late target reversal cannot bend the slide "+label);
                u.攻击目标=c.target._name;u.soldierNextShootAt=0;u.soldierReadyAt=0;
                check(u.soldierChooseAttack(400,0,0)=="shoot" && u.eliteNextAction=="run",
                    "running fire remains available without another smoke reload "+label);
                u.攻击目标="无";
            }
        }
    }

    private static function phaseTick():Void {
        for(var i:Number=0;i<phases.length;i++){
            var c:Object=phases[i],u:MovieClip=c.actor;
            if(u.buffManager!=null)u.buffManager.update(1);
            if(ticks==184){
                check(u.soldierPhase==(c.move=="override"?c.expectedPhase:1),"spawn linkage and explicit phase override "+i);
                check(u.刚体==(u.soldierPhase==1) && !u.免疫击退,"shield armor does not suppress displacement "+i);
                check(u.击中效果==(u.soldierPhase==1?"击中金属":"飙血"),"spawn phase selects metal sparks or blood "+i);
                var expectedReduction:Number=c.overrideReduction==undefined?u.soldierTuning.shieldDamageReductionPercent:c.overrideReduction;
                check(Math.abs(u.damageTakenMultiplier-(u.soldierPhase==1?1-expectedReduction/100:1))<0.0001,"phase and reduction overrides apply correct Buff "+i);
                if(c.move=="breakReload"){
                    _root.技能函数.霸体减伤(u,30,0,"fixture-survivor");u.buffManager.update(0);
                }
                u.方向改变(c.side==0?"右":"左");
                if(c.move=="shoot" || c.move=="break" || c.move=="breakReload"){
                    if(c.move=="breakReload")u.长枪.value.shot=u.长枪弹匣容量-1;
                    u.状态改变("长枪攻击");
                } else if(c.move=="knife")u.状态改变("近战");
                else if(c.move=="hit"){
                    u.攻击目标="phaseHitTarget";u.soldierShieldGuardActive=true;
                    u.状态改变("被击");u.man.gotoAndPlay(c.side==0?"a0":"a1");
                }
            }
            if(ticks==185 && c.move=="hit")u.man.gotoAndPlay(c.side==0?"a0":"a1");
            if(ticks==225 && c.move=="hit"){
                check(u.状态=="被击" && c.record.done==0 && u.man._currentframe>(c.side==0?30:92),
                    "shield guard hit plays full 62-frame crouch-guard without early truncation under active target "+i);
            }
            if(ticks==186 && c.move=="stand")render(u,"shield-stand-"+c.side);
            if(ticks==188 && c.move=="stand")shieldDamageContract(u);
            if(ticks==196 && c.move=="shoot")render(u,"shield-shoot-"+c.side);
            if(ticks==197 && c.move=="knife")render(u,"shield-knife-"+c.side);
            if(c.move=="break" || c.move=="breakReload"){
                if(ticks==205){
                    c.weapon=u.长枪;c.version=u.version;c.ammo=u.长枪.value.shot;
                    c.next=u.soldierNextShootAt;c.oldBody=u.man;c.owner=u.soldierAttackOwner;
                    c.shots=c.record.shots;
                    if(c.move=="breakReload")check(u.man.换弹标签===true,"break interrupts actual reload "+i);
                    u.hp=-1000;
                    check(u.hp==1 && u.soldierPhase==0 && u.无敌,"first lethal write enters protected transition "+i);
                    check(u.击中效果=="击中金属","shield-breaking hit retains metal impact "+i);
                    u.dispatcher.publish1("kill",u);u.dispatcher.publish1("kill",u);u.死亡检测();
                    u.hp=0;u.状态改变("血腥死");
                    check(c.record.deaths==0 && c.record.deathChecks==0 && !u._killed && u.soldierPhaseChanges==1,
                        "first life cannot settle death or repeat transition "+i);
                    if(c.owner)check(c.owner.active===false,"transition invalidates attack token "+i);
                }
                if(ticks==207){c.pauseFrame=u.man._currentframe;c.pauseClock=u.soldierClock;}
                if(ticks==211){
                    check(u.man._currentframe==c.pauseFrame && u.soldierClock==c.pauseClock,"real paused break timeline remains frozen "+i);
                    render(u,"shield-break-"+c.side+"-"+c.move);
                }
                if(ticks==214 && c.move=="breakReload"){u.刚体=true;u.无敌=true;}
                if(ticks==230){
                    check(u.soldierPhase==2 && u.hp==350 && u.soldierPhaseChanges==1,"same actor completes second life once "+i);
                    check(u.击中效果=="飙血","second life restores ordinary blood impact "+i);
                    check(u.buffManager.getBuffById("霸体减伤_CF6特种兵持盾")==null,"break removes only owned shield Buff "+i);
                    check(Math.abs(u.damageTakenMultiplier-(c.move=="breakReload"?0.7:1))<0.0001,"external reduction survives shield break "+i);
                    check(u.长枪===c.weapon && u.version==c.version && u.长枪.value.shot==c.ammo,
                        "phase switch preserves equipment version and ammunition "+i);
                    check(u.soldierNextShootAt==c.next && c.record.shots==c.shots,"phase switch preserves ceasefire and blocks late shots "+i);
                    if(c.move=="breakReload"){
                        check(u.刚体 && u.无敌,"phase switch preserves external rigid and invincible writes "+i);
                        u.刚体=false;u.无敌=false;
                    }
                    check(!u.刚体 && !u.无敌 && !u.浮空 && !u.倒地,"phase two restores ordinary reaction "+i);
                    var hp:Number=u.hp;u.soldierFinishBreak(c.oldBody);check(u.hp==hp,"stale body cannot finish phase twice "+i);
                    u.dispatcher.publish1("kill",u);
                    check(u.hp==hp && !u._killed && c.record.deaths==0,"late first-life kill cannot kill live phase two "+i);
                    trace("[SOLDIER_PHASE] case="+i+" phase="+u.soldierPhase+" hp="+u.hp+" changes="+u.soldierPhaseChanges+" ammo="+u.长枪.value.shot);
                    u.状态改变("击倒");
                }
                if(ticks==231){check(c.record.physics==1,"phase two actual airborne delegate "+i);u.浮空=false;u.状态改变("倒地");}
                if(ticks==232){
                    check(c.record.landings==1,"phase two actual down delegate "+i);
                }
                if(ticks==234){
                    u.hp=0;u.dispatcher.publish1("kill",u);u.dispatcher.publish1("kill",u);
                    check(c.record.deaths==1 && u._killed,"only final life delegates standard kill once "+i);
                    u.man.gotoAndPlay("a0");
                }
            }
            if(ticks==310){
                if(c.move=="break" || c.move=="breakReload")check(c.record.removed && c.record.deathChecks==1,"final death settles once "+i);
                else if(c.move=="shoot" || c.move=="knife"){
                    check(c.record.shots==(c.move=="shoot"?3:0) && c.record.stabs==(c.move=="knife"?1:0),"shield exact attack emission "+i);
                    check(c.record.done==1 && c.record.powerOk && c.record.contractOk && c.record.areaOk && c.record.muzzleOk,"shield standard attack contract "+i);
                } else if(c.move=="hit")check(c.record.done==1 && u.soldierPhase==1 && u.刚体,"shield hit recovery "+i);
            }
        }
        if(ticks==207)_root.暂停=true;
        if(ticks==211)_root.暂停=false;
        if(ticks==410)finish();
    }
    private static function beginReview():Void {
        // Behavior has finished. Only two actors remain alive while capturing
        // the published poses; this avoids 180 invisible animated fixtures.
        var groups:Array=[cases,phases,elites,lanes,pairs,roles,tactics,probes];
        for(var g:Number=0;g<groups.length;g++)for(var i:Number=0;i<groups[g].length;i++)groups[g][i].actor.removeMovieClip();
        for(var d:Number=0;d<defaults.length;d++)defaults[d].removeMovieClip();
        reviewUnits=[];
        for(var side:Number=0;side<(_root.soldierTacticalCapture===true?3:2);side++){
            var u:MovieClip=library.attachMovie(side==0?link:side==1?"敌人-CF6特种精英":"敌人-CF6特种教官","reviewActor"+side,library.getNextHighestDepth(),
                {fixtureRecord:record(),长枪:"M4A1战术版"});
            reviewUnits.push(u);
        }
        reviewQueue=[];
        var specs:Array=[
            ["ordinary-run",0,20,1,24,2],["elite-run",1,20,1,24,2],
            ["ordinary-throw",0,121,1,36,2],["ordinary-bash",0,191,35,68,1],
            ["ordinary-stab",0,191,1,34,1],["shield-cover",0,195,1,20,1],
            ["elite-charge",1,181,1,46,1],["elite-pair",1,42,331,365,2],
            ["death-new",0,105,105,139,2],["shield-break",0,203,1,11,0]];
        if(_root.soldierTacticalCapture===true)specs=[
            ["ordinary-run",0,20,1,24,2],["ordinary-throw",0,121,1,36,2],
            ["ordinary-bash",0,191,35,68,1],["ordinary-stab",0,191,1,34,1],["shield-cover",0,195,1,20,1],
            ["elite-charge",1,181,1,46,1],["elite-reload",1,42,331,365,2],
            ["elite-retreat",1,42,2,44,2],["elite-slide",1,42,166,248,2],
            ["instructor-run",2,20,1,24,2],["instructor-throw",2,121,1,36,2],
            ["instructor-bash",2,191,35,68,1],["instructor-charge",2,181,1,46,1],
            ["instructor-retreat",2,42,2,44,2]];
        for(var j:Number=0;j<specs.length;j++){
            var spec:Array=specs[j];
            for(var f:Number=spec[3];f<=spec[4];f++)reviewQueue.push({key:spec[0],actor:spec[1],rootFrame:spec[2],frame:f,phase:spec[5]});
        }
        var requestedStart:Number=Number(_root.soldierReviewStartIndex);
        reviewIndex=isFinite(requestedStart) && requestedStart>=0 && requestedStart<reviewQueue.length?Math.floor(requestedStart):0;
        reviewStage=0;_root.soldierCapture=true;
        trace("[SOLDIER_CAPTURE_PROTOCOL] region-rle-v2");
        trace((_root.soldierTacticalCapture===true?"[R9_REVIEW_EXPECTED] ":"[R8_REVIEW_EXPECTED] ")+reviewQueue.length);
        var selected:String=String(_root.soldierReviewKeys);
        if(selected!="undefined" && selected!=""){
            var filtered:Array=[];
            for(var k:Number=0;k<reviewQueue.length;k++){
                var candidate:Object=reviewQueue[k];
                if((","+selected+",").indexOf(","+candidate.key+"-"+candidate.frame+",")>=0)filtered.push(candidate);
            }
            reviewQueue=filtered;reviewIndex=0;trace("[R9_DIAGNOSTIC_KEYS] "+selected);
        }
        driver.onEnterFrame=function():Void {Cf6SoldierAssetTest.reviewTick();};
    }
    private static function reviewTick():Void {
        if(reviewIndex>=reviewQueue.length){reviewDone=true;finish();return;}
        var row:Object=reviewQueue[reviewIndex],u:MovieClip=reviewUnits[row.actor];
        if(reviewStage==0){
            u.soldierDriver.removeMovieClip();
            var noop:Function=function():Void {};
            u.soldierTick=noop;u.行走=noop;u.动画完毕=noop;u.死亡检测=noop;
            u.soldierBeginAttack=noop;u.soldierBeginMelee=noop;u.soldierBeginGrenade=noop;u.soldierThrowGrenade=noop;
            u.soldierBeginCharge=noop;u.soldierFinishAttack=noop;u.soldierReloadStart=noop;u.soldierReloadEnd=noop;
            u.soldierMeleeHit=noop;u.soldierStab=noop;u.eliteBeginAttack=noop;u.eliteReloadStart=noop;
            u.eliteReloadGate=noop;u.eliteReloadCommit=noop;u.eliteReloadEnd=noop;
            u.soldierPhase=row.phase;u.状态="长枪攻击";u.攻击目标="无";
            u.soldierAttackOwner=(row.key=="elite-pair" || row.key=="elite-reload")?{elite:true,active:true,reload:true,smokePrepared:true,reloadPair:true,reloadSlot:"手枪"}:null;
            u.gotoAndStop(row.rootFrame);reviewStage=1;return;
        }
        if(reviewStage==1){u.man.gotoAndStop(row.frame);reviewStage=2;return;}
        u.man.腰挂.syncHolsters();
        render(u,(_root.soldierTacticalCapture===true?"r9review-":"r8review-")+row.key+"-"+row.frame);
        reviewIndex++;reviewStage=0;
    }
    private static function createCompletionCases():Void {
        var links:Array=["敌人-CF6特种兵","敌人-CF6持盾特种兵","敌人-CF6特种精英","敌人-CF6持盾特种精英","敌人-CF6特种教官","敌人-CF6持盾特种教官"];
        var guns:Array=["M4A1改","AK74战术版","M4A1战术版","DD MK18战术版"];
        for(var a:Number=0;a<links.length;a++)for(var g:Number=0;g<guns.length;g++)for(var side:Number=0;side<2;side++){
            addCompletionCase("default",links[a],guns[g],side);
        }
        var modes:Array=["disabled","interrupt","dead","stale","replaced","lane","close","guard","cooldown","noSub",
            "reloadLinked","reloadCancel","pistolReload","emptyEvade","blockedEvade","stationary","handoff","slidePass","slideBlocked","slideClose","slideDry","slideStalled","slideBlockedHard","slideTrapped","instructorClose","instructorAmmo"];
        for(var m:Number=0;m<modes.length;m++)for(var side2:Number=0;side2<2;side2++){
            var mode:String=modes[m];
            addCompletionCase(mode,mode=="instructorClose" || mode=="instructorAmmo"?"敌人-CF6特种教官":
                mode=="pistolReload" || mode=="emptyEvade" || mode=="blockedEvade" || mode=="stationary" || mode=="handoff" || mode.indexOf("slide")==0?"敌人-CF6特种精英":"敌人-CF6特种兵",
                mode=="noSub"?"AK47":"M4A1战术版",side2);
        }
    }
    private static function addCompletionCase(mode:String,linkage:String,gun:String,side:Number):Void {
        var rec:Object=record();rec.subshots=0;rec.elite=linkage.indexOf("精英")>=0 || linkage.indexOf("教官")>=0;
        var init:Object={fixtureRecord:rec,fixtureCompletion:true,fixtureTacticalModern:true,特种兵烟雾弹:false,
            长枪:gun,手枪:"FR506",手枪2:"FR506"};
        if(mode=="disabled")init.特种兵副武器=false;
        if(mode=="stationary")init.特种兵精英消融="stationary";
        var unit:MovieClip=library.attachMovie(linkage,"completion"+completionCases.length,library.getNextHighestDepth(),init);
        completionCases.push({actor:unit,record:rec,mode:mode,side:side,gun:gun,linkage:linkage});
    }
    private static function completionTick():Void {
        for(var i:Number=0;i<completionCases.length;i++){
            var c:Object=completionCases[i],u:MovieClip=c.actor,mode:String=c.mode,rec:Object=c.record;
            var label:String=mode+"/"+c.linkage+"/"+c.gun+"/"+c.side,sign:Number=c.side==0?1:-1;
            if(ticks==190){
                var target:MovieClip=library.createEmptyMovieClip("completionTarget"+i,library.getNextHighestDepth());
                target.hp=1000;target._x=u._x+sign*240;target._y=target.Z轴坐标=u.Z轴坐标;
                target.area=target.createEmptyMovieClip("area",1);u.攻击目标=target._name;u.soldierTargetName=target._name;
                c.target=target;c.startX=u._x;c.startZ=u.Z轴坐标;u.方向改变(sign>0?"右":"左");
                u.soldierReadyAt=u.soldierNextShootAt=0;u.soldierNextGrenadeAt=99999;u.soldierClock=200;
                c.loaded=LongGunSubWeaponCore.getLoadedCount(u);c.rifle=u.长枪;c.state=u.长枪副武器状态;
                if(mode=="lane")target._y=target.Z轴坐标=u.Z轴坐标+80;
                if(mode=="close")target._x=u._x+sign*60;
                if(mode=="guard")u.长枪副武器状态.fireGuard=function():Boolean {return false;};
                if(mode=="cooldown")u.长枪副武器状态.nextFireTime=getTimer()+600000;
                if(mode=="stationary" || mode=="emptyEvade" || mode=="blockedEvade"){
                    target._x=u._x+sign*180;u._btFrame=_root.帧计时器.当前帧数;u._btCount=2;u._btMinETA=5;
                    if(mode!="stationary"){u.手枪.value.shot=u.手枪弹匣容量;u.手枪2.value.shot=u.手枪2弹匣容量;}
                    if(mode=="blockedEvade")u.移动=function():Void {};
                    check(u.soldierChooseAttack(180,0,0)=="shoot","completion threat selects attack "+label);
                    check(u.eliteNextAction==(mode=="stationary"?"stand":"retreat"),"stationary ablation preserves real stand fire "+label);
                }else if(mode=="handoff"){
                    target._x=u._x+sign*400;check(u.soldierChooseAttack(400,0,0)=="shoot" && u.eliteNextAction=="run","far band starts run "+label);
                }else if(mode.indexOf("slide")==0){
                    target._x=u._x+sign*(mode=="slideClose"?40:430);
                    check(u.soldierCanSlideExit(target),"smoke slide remains available at its real entry distance "+label);
                    u.eliteNextAction="slide";u.soldierPendingSlide=true;
                    if(mode=="slideDry")u.长枪.value.shot=u.长枪弹匣容量-1;
                    if(mode=="slideBlocked" || mode=="slideBlockedHard"){
                        u.fixtureOriginalMove=u.移动;
                        u.移动=function(direction:String,speed:Number):Void {
                            if(direction=="上" || direction=="下")this.fixtureOriginalMove.call(this,direction,speed);
                        };
                        u.动画完毕=function():Void {
                            this.fixtureRecord.done++;this.倒地=false;
                            if(this.soldierTacticalStats.wallEscapes>0)this.攻击目标="无";
                            this.状态改变("长枪站立");
                        };
                        u.soldierNextEvasionAt=999;
                        if(mode=="slideBlockedHard")u.硬直中=true;
                    }
                    if(mode=="slideTrapped")u.移动=function():Void {};
                }else if(mode=="instructorClose"){
                    u.soldierStrategy="mobile";u.soldierStrategyUntil=9999;target._x=u._x+sign*60;
                    check(u.soldierChooseAttack(60,0,0)=="knife","mobile instructor retains point blank knife "+label);
                }else if(mode=="instructorAmmo"){
                    u.手枪.value.shot=u.手枪弹匣容量;u.手枪2.value.shot=u.手枪2弹匣容量;u.soldierStrategyUntil=0;
                    check(u.soldierSelectStrategy(160,0)=="line","loaded rifle wins over empty pistols at medium-close range "+label);
                    u.eliteNextAction="line";
                }else u.eliteNextAction="stand";
                if(mode=="reloadLinked" || mode=="reloadCancel" || mode=="pistolReload"){
                    LongGunSubWeaponCore.setFiredCount(u,1);
                    if(mode=="pistolReload")u.eliteNextAction="retreat";
                    else u.长枪.value.shot=u.长枪弹匣容量;
                }
                u.状态改变(mode=="instructorClose"?"近战":"长枪攻击");
                if(mode=="pistolReload"){u.手枪.value.shot=6;u.eliteBeginReload(u.man,"手枪");}
                if(mode=="emptyEvade" || mode=="blockedEvade"){
                    check(!u.soldierAttackOwner.reload && u.soldierTacticalStats.evasions==0
                        && u.soldierNextEvasionAt==0,"empty withdrawal waits for real movement before cooldown "+label);
                }
            }
            if(ticks==195){
                if(mode=="interrupt" || mode=="stale" || mode=="reloadCancel"){
                    c.oldOwner=u.soldierAttackOwner;c.oldBody=u.man;c.oldToken=u.man.soldierToken;
                    u.状态改变("被击");u.man.gotoAndPlay("a0");
                    if(mode=="stale"){
                        u.soldierSubweaponCall={body:c.oldBody,owner:c.oldOwner,token:c.oldToken,state:c.state,weapon:u.长枪副武器};
                        check(!u.soldierSubweaponFire(c.oldBody.枪.枪.装扮.枪口位置,{}),"late NPC callback rejected "+label);
                        u.soldierSubweaponCall=null;
                    }
                    if(mode=="reloadCancel")u.soldierSubweaponReloadCommitted(c.oldBody);
                }
                if(mode=="dead")u.hp=0;
                if(mode=="replaced")u.长枪=new BaseItem(c.rifle.name,{shot:c.rifle.value.shot,level:1},c.rifle.lastUpdate);
            }
            var owner:Object=u.soldierAttackOwner;
            if(owner.runHandoff){
                c.handoff=true;
                check(owner.kind=="stand" && u.standardShotMoving!==true,"stopped motion uses stationary controller "+label);
            }
            if((mode=="slidePass" || mode=="slideClose" || mode=="slideDry") && owner.kind=="slide" && owner.logicalFrame>212
                && owner.logicalFrame<=228 && c.motionFrame!=undefined && owner.logicalFrame!=c.motionFrame && !_root.暂停){
                check(Math.abs(u._x-c.motionX)+Math.abs(u.Z轴坐标-c.motionZ)>0.1,"every advancing slide pose has actual movement "+label);
            }
            if(mode.indexOf("slide")==0 && owner.kind=="slide"){
                check(u.方向==(sign>0?"右":"左"),"sliding body holds entry facing until it stops "+label);
                if((u._x-c.target._x)*sign>0)c.crossed=true;
                if(mode=="slideDry" && u.长枪.value.shot>=u.长枪弹匣容量){
                    check(!owner.reload,"empty rifle cannot freeze the active slide into reload "+label);
                    c.dryMotion=true;
                }
            }
            if(mode=="slideDry" && owner.reload && !c.slideReloadObserved){
                c.slideReloadObserved=true;
                check(c.crossed && Math.abs(u._x-c.startX)>500,"slide completes traversal before rifle reload "+label);
            }
            if(mode=="slideStalled" && ticks>=194 && ticks<=198 && owner.kind=="slide")u._x=c.startX;
            if(mode=="slideStalled" && u.soldierPendingEvasion.reason=="slide_stalled")c.stallQueued=true;
            if(mode=="slideTrapped" && ticks==195){
                u.攻击目标=c.target._name;
                check(u.soldierTryEvasion(430,0),"blocked slide queues a bounded movement-only escape "+label);
                u.状态改变("长枪攻击");
            }
            c.motionFrame=owner.logicalFrame;c.motionX=u._x;c.motionZ=u.Z轴坐标;
            if(mode=="emptyEvade" && owner.reload && !c.reloadObserved){
                c.reloadObserved=true;c.travelBeforeReload=Math.abs(u._x-c.startX)+Math.abs(u.Z轴坐标-c.startZ);
                check(c.travelBeforeReload>100 && u.soldierTacticalStats.evasions==1,"both empty hands withdraw before reload "+label);
            }
            if(ticks==400){
                if(mode=="default"){
                    check(rec.subshots==1 && u.soldierSubweaponShots==1,"default rifle fires exactly one secondary "+label+" got="+rec.subshots);
                    check(LongGunSubWeaponCore.getLoadedCount(u)==c.loaded-1 && u.长枪.value.subweaponShot==1,"NPC secondary consumes its own magazine "+label);
                    check(rec.shots>0 && rec.powerOk && rec.muzzleOk,"secondary preserves primary weapon contract "+label);
                }else if(mode=="reloadLinked")check(u.长枪.value.shot==0 && u.soldierSubweaponReloads==1
                    && LongGunSubWeaponCore.getFiredCount(u)==0,"real primary commit refills secondary once "+label);
                else if(mode=="reloadCancel" || mode=="pistolReload")check(LongGunSubWeaponCore.getFiredCount(u)==1
                    && u.soldierSubweaponReloads==0,"cancel or pistol reload cannot refill secondary "+label);
                else if(mode=="emptyEvade")check(c.reloadObserved && u.手枪.value.shot==0 && u.手枪2.value.shot==0
                    && u.soldierReloadCount==1,"empty withdrawal completes one real dual reload "+label);
                else if(mode=="blockedEvade")check(u._x==c.startX && u.Z轴坐标==c.startZ && u.soldierTacticalStats.evasions==0
                    && u.soldierNextEvasionAt==0 && u.soldierNextEvasionAttemptAt>200,"blocked attempt spends only retry delay "+label);
                else if(mode=="stationary")check(u.eliteMoveDistance==0 && rec.shots>0 && u.soldierTacticalStats.evasions==0,"stationary baseline retains fire "+label);
                else if(mode=="handoff")check(c.handoff && rec.shots>0 && rec.shots<=8
                    && Math.abs(Math.abs(c.target._x-u._x)-280)<0.2,"run hands same shot budget to stand at 280px "+label);
                else if(mode=="slidePass" || mode=="slideClose")check(c.handoff && c.crossed && rec.shots>0 && rec.shots<=5
                    && (u._x-c.target._x)*sign>130 && (u._x-c.target._x)*sign<150,
                    "slide crosses target and ends beyond it without extra fire budget "+label);
                else if(mode=="slideBlocked" || mode=="slideBlockedHard")check(u._x==c.startX
                    && Math.abs(u.Z轴坐标-c.startZ)>24 && u.soldierTacticalStats.wallEscapes==1
                    && rec.shots==0 && rec.sidearmShots==0 && u.soldierAttackOwner==null,
                    "wall blockage releases slide and leaves the lane without bonus shots "+label);
                else if(mode=="slideDry")check(c.dryMotion && c.crossed && c.slideReloadObserved && u.soldierReloadCount==1
                    && u.长枪.value.shot==0,"mid-slide empty rifle defers exactly one reload until safe traversal "+label);
                else if(mode=="slideStalled")check(c.stallQueued && u.soldierTacticalStats.slideStalls==1 && u.soldierAttackOwner==null,
                    "opposing displacement cannot hold an advancing slide pose indefinitely "+label);
                else if(mode=="slideTrapped")check(u._x==c.startX && u.Z轴坐标==c.startZ && u.soldierTacticalStats.wallEscapes==0
                    && u.soldierNextEvasionAt==0 && rec.shots==0 && rec.sidearmShots==0 && u.soldierAttackOwner==null,
                    "fully trapped escape respects collision and spends no full evasion cooldown "+label);
                else if(mode=="instructorClose")check(rec.stabs==1,"mobile instructor executes native knife "+label);
                else if(mode=="instructorAmmo")check(rec.shots>0 && rec.sidearmShots==0,"ammo-aware instructor fires loaded rifle "+label);
                else check(rec.subshots==0,"secondary rejects invalid or disabled context "+label+" got="+rec.subshots);
                trace("[CF6_COMPLETION] "+label+" primary="+rec.shots+" sub="+rec.subshots+" moved="+Math.abs(u._x-c.startX)
                    +" evasions="+u.soldierTacticalStats.evasions+" reload="+u.soldierReloadCount);
            }
        }
        if(ticks==400)check(_root.cf6InventoryReads==0 && _root.cf6InventoryWrites==0,"NPC fixture has zero player inventory reads/writes");
    }
    private static function finish():Void {
        if(_root.soldierReviewCapture===true && !reviewDone){beginReview();return;}
        if(_root.cf6CapturePending>0){
            _root.cf6CaptureWait++;
            if(_root.cf6CaptureWait<150)return;
            check(false,"native image collector acknowledgement timed out");
        }
        if(finished)return;finished=true;delete driver.onEnterFrame;
        if(typeof _root.cf6CaptureEndpoint=="string")check(_root.cf6CaptureErrors==0,"all native images acknowledged by owned loopback collector");
        trace("Cf6SoldierAssetTest: "+passed+" passed, "+failed+" failed; "+(cases.length+phases.length+elites.length+lanes.length+pairs.length+roles.length+tactics.length+completionCases.length)+" actual timeline cases");
        if(failed>0)trace("[TEST_FAIL] Cf6SoldierAssetTest suite failed");
        if(_root.cf6SoldierAssetComplete!=undefined)_root.cf6SoldierAssetComplete();
    }
}
