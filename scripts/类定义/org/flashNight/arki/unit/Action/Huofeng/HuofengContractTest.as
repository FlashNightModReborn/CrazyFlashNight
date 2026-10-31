import org.flashNight.arki.unit.Action.Huofeng.*;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.hud.PlayerHudBuffProjection;
import org.flashNight.arki.spatial.move.Mover;

/** 真实 HP getter、治疗和伤害结算的内存夹具；不读写存档，不代签原生动作。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengContractTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var pulses:Array;
    private static var cancelFrames:Array;
    private static var moved:Number;
    private static var held:Boolean;
    private static function check(ok:Boolean,label:String):Void {
        if(ok === true) passed++; else { failed++;trace("[TEST_FAIL] HuofengContractTest: "+label); }
    }
    private static function near(a:Number,b:Number):Boolean { return Math.abs(a-b)<0.001; }
    private static function legacyProjection():Void {
        // A missing blade must still select the original unarmed fallback.
        // Coercing undefined to zero here silently changes unrelated skills.
        var u:Object={攻击模式:"空手",空手攻击力:321,内力:87,mp攻击加成:13};
        check(HuofengRules.bladePower(u)==undefined,"ordinary unarmed keeps missing blade undefined");
        check(HuofengRules.unarmedTerm(u)==321,"ordinary punch term remains intact");
        check(HuofengNative.force(u)==87 && HuofengNative.mpPower(u)==13,"ordinary force and MP terms remain intact");
        u.刀属性={power:0};check(HuofengRules.bladePower(u)===0,"real zero blade remains distinguishable from missing blade");
        u.刀属性.power=901;u.攻击模式="兵器";
        check(HuofengRules.bladePower(u)==901,"ordinary blade uses its original effective power");
        delete u.内力;delete u.mp攻击加成;
        check(HuofengNative.force(u)==undefined && HuofengNative.mpPower(u)==undefined,"uninitialized ordinary terms preserve original semantics");
    }
    private static function hpContract():Void {
        var u:Object={hp:1000,hp满血值:1000};
        var m:BuffManager=new BuffManager(u);
        var owner:Object={},stranger:Object={};
        check(!m.setHuofengHpContract(owner,0.35),"reject compounded 35 percent");
        check(m.setHuofengHpContract(owner,0.7),"first contract");
        check(near(u.hp满血值,700) && near(u.hp,700),"first clamp");
        check(near(m.getHuofengNormalMaxHp(),1000),"H0 unaffected");
        check(!m.setHuofengHpContract(stranger,0.5),"another owner cannot replace");
        m.clearHuofengHpContract(stranger);
        check(near(u.hp满血值,700),"stale owner cannot clear");
        u.hp=300;
        check(m.setHuofengHpContract(owner,0.5),"second replaces first");
        check(near(u.hp满血值,500) && u.hp==300,"second no heal");
        check(near(HealApplier.applyHpCapped(u,9999,1000),200) && u.hp==500,"potions honor contract cap");
        u.hp=450;
        check(near(HealApplier.applyHpOverflow(u,1000,1000,2),50) && u.hp==500,"overflow cannot erase one hit line");
        m.setBaseValue("hp满血值",2000);
        check(near(u.hp满血值,1000) && u.hp==500,"base change no free heal");
        m.recordCrumbleCeilingLoss(100);
        check(near(u.hp满血值,900),"crumble retains actual final point loss");
        check(near(m.getHuofengNormalMaxHp(),1800),"crumble H0 domain");
        m.clearHuofengHpContract(owner);
        check(near(u.hp满血值,1800) && u.hp==500,"unequip removes cost without healing");
        m.setHuofengHpContract(owner,0.5);
        check(near(u.hp满血值,900) && u.hp==500,"reequip retains deficit");
        m.clearHuofengHpContract(owner);
        u.hp=1800;
        check(HealApplier.applyHpOverflow(u,100,1800,2)>0,"ordinary overflow restored");
        m.destroy();
        check(u.__huofengHpContract==undefined,"destroy clears owned projection");
    }
    private static function paidRevives():Void {
        var previous=_root.控制目标;
        _root.控制目标="hf-fixture";
        var u:Object={_name:"hf-fixture",hp:100,__huofeng:{isActive:function():Boolean { return true; }}};
        for(var i:Number=0;i<HuofengRules.SLOTS.length;i++) {
            u[HuofengRules.SLOTS[i]]={name:"fixture"};
            u[HuofengRules.SLOTS[i]+"数据"]={setId:"huofeng"};
        }
        var run:Object={runId:"one"};
        check(HuofengRunState.commitPaidRevive(run,u,false,1)==0,"free respawn excluded");
        u.hp=0;
        check(HuofengRunState.commitPaidRevive(run,u,true,1)==0,"failed respawn excluded");
        u.hp=100;
        check(HuofengRunState.commitPaidRevive(run,u,true,1)==1,"first paid revive");
        check(HuofengRunState.commitPaidRevive(run,u,true,1)==0 && run.huofeng.tier==1,"duplicate sequence excluded");
        u.上装装备数据.setId="other";
        check(HuofengRunState.commitPaidRevive(run,u,true,2)==0,"full set required after respawn");
        u.上装装备数据.setId="huofeng";
        check(HuofengRunState.commitPaidRevive(run,u,true,3)==2,"second paid revive");
        check(HuofengRunState.commitPaidRevive(run,u,true,4)==2 && run.huofeng.tier==2 && run.huofeng.pendingReviveSequence==4,"third replays full animation without raising tier");
        check(HuofengRunState.commitPaidRevive({runId:"two"},u,true,1)==1,"new sortie has fresh tier");
        delete u.__huofeng;
        check(HuofengRunState.commitPaidRevive(run,u,true,5)==2,"committed eligibility survives temporary presentation teardown");
        check(HuofengRunState.commitPaidRevive(run,u,true,5)==0,"repeated paid receipt does not replay");
        _root.控制目标=previous;
    }
    private static function unequipContract():Void {
        var u:Object={_name:"hf-unequip-fixture",hp:100,version:1};
        for(var i:Number=0;i<HuofengRules.SLOTS.length;i++) {
            u[HuofengRules.SLOTS[i]]={name:"fixture",value:{level:1}};
            u[HuofengRules.SLOTS[i]+"数据"]={setId:"huofeng"};
        }
        HuofengRunState.reconcileEquipment(u);
        var state:Object=HuofengRunState.forUnit(u);
        state.tier=2;state.lastPaidSequence=9;state.spinReadyFrame=500;
        state.runReadyFrame=300;state.primaryReadyFrame=100;state.actionSequence=20;
        u.刀={name:"other blade"};u.攻击模式="兵器";u.version++;
        HuofengRunState.reconcileEquipment(u);
        check(state.tier==2 && state.equipmentEpoch==0,"weapon change and version refresh preserve Nirvana");
        u.攻击模式="长枪";HuofengRunState.reconcileEquipment(u);
        check(state.tier==2,"gun mode preserves Nirvana");
        var previous:Object=u.头部装备;
        u.头部装备={name:"second Huofeng head",value:{level:1}};
        HuofengRunState.reconcileEquipment(u);
        check(state.tier==0 && state.equipmentEpoch==1,"replacing one Huofeng piece with another clears the old contract");
        u.头部装备=previous;HuofengRunState.reconcileEquipment(u);
        state.equipmentEpoch=0;

        for(i=0;i<HuofengRules.SLOTS.length;i++) {
            var slot:String=HuofengRules.SLOTS[i];var item:Object=u[slot];
            state.tier=2;state.pendingNirvanaTier=2;state.pendingReviveSequence=9;state.presentedReviveSequence=8;
            delete u[slot];HuofengRunState.reconcileEquipment(u);
            check(state.tier==0 && state.equipmentEpoch==i+1,"removing armor clears tier and invalidates old eligibility "+slot);
            check(state.pendingNirvanaTier==0 && state.pendingReviveSequence==0 && state.presentedReviveSequence==0,
                "removing armor discards pending resurrection presentation "+slot);
            check(state.lastPaidSequence==9 && state.spinReadyFrame==500 && state.runReadyFrame==300
                && state.primaryReadyFrame==100 && state.actionSequence==20,"unequip preserves dedupe and cooldown ownership "+slot);
            HuofengRunState.reconcileEquipment(u);
            check(state.equipmentEpoch==i+1,"repeated incomplete initialization resets only once "+slot);
            u[slot]=item;HuofengRunState.reconcileEquipment(u);
            check(state.tier==0 && state.setEquipped===true,"re-equipping cannot restore old tier "+slot);
        }
    }
    private static function nativeContacts():Void {
        var unit:Object={攻击模式:"空手",man:{}};
        var owner:Object={isActive:function():Boolean{return true;},getUnit:function():Object{return unit;}};
        unit.__huofeng=owner;
        var token:Object={owner:owner,cancelled:false,requiresProfile:true};
        unit.man.__huofengColdSnapshot={owner:owner,token:token,damage:17,attributes:{伤害类型:"破击",魔法伤害属性:"热"}};
        var bullet:Object={};HuofengNative.prepareBullet(unit,bullet);
        var target:Object={__battleRecord:{unitId:"multi",life:1}};
        for(var window:Number=0;window<4;window++)
            check(HuofengCombat.claimPulse(bullet,target),"native projectile keeps independent window "+window);
        for(var blade:Number=0;blade<3;blade++) {
            var copy:Object={__huofengPulse:bullet.__huofengPulse};
            check(HuofengCombat.claimPulse(copy,target),"shared blade attributes do not merge node "+blade);
        }
        check(bullet.__huofengDamageSnapshot==17 && bullet.魔法伤害属性=="热","native repeated hits retain one frozen damage projection");
        token.cancelled=true;
        check(!HuofengCombat.claimPulse(bullet,target),"native multi-hit retains cancellation protection");
        token.cancelled=false;unit.攻击模式="兵器";
        check(!HuofengCombat.claimPulse(bullet,target),"native projectile cannot outlive its meteor hammer profile");
    }
    private static function contactAndHeat():Void {
        var action:Object={cancelled:false,owner:{isActive:function():Boolean { return true; }}};
        var token:Object={action:action,seen:{}};
        var b1:Object={__huofengPulse:token}, b2:Object={__huofengPulse:token};
        var enemy:Object={__battleRecord:{unitId:"enemy.1",life:0}};
        check(HuofengCombat.claimPulse(b1,enemy),"first spatial sample");
        check(!HuofengCombat.claimPulse(b2,enemy),"same pulse dedupes another sample");
        enemy.__battleRecord.life=1;
        check(HuofengCombat.claimPulse(b2,enemy),"new life is a new target");
        enemy.__battleRecord.unitId="enemy.2";
        check(HuofengCombat.claimPulse(b1,enemy),"other target can be hit");
        action.cancelled=true;
        check(!HuofengCombat.claimPulse({__huofengPulse:{action:action,seen:{}}},enemy),"cancel invalidates pending contacts");
        check(HuofengCombat.claimPulse({},enemy),"ordinary bullets unchanged");
        var blast:Object={__huofengPulse:{action:{cancelled:false,owner:{isActive:function():Boolean{return true;}}},seen:{}},__huofengBlast:{x:0,z:0,radius:75}};
        enemy._x=74;enemy.Z轴坐标=24;
        check(!HuofengCombat.claimPulse(blast,enemy),"revive rectangle corner outside radial limit rejected");
        enemy._x=70;
        check(HuofengCombat.claimPulse(blast,enemy),"revive radial interior accepted");
    }
    private static function conversion():Void {
        var owner:Object={tier:0,isActive:function():Boolean{return true;},getTier:function():Number{return this.tier;}};
        var unit:Object={__huofeng:owner,攻击模式:"空手",基础伤害类型:"物理",内力:0,
            手部装备:{value:{level:1}},装备刀锋利度加成:0};
        var b:Object={};HuofengCombat.primaryAttributes(unit,b);
        check(b.伤害类型=="物理","before revival remains physical");
        owner.tier=1;HuofengCombat.primaryAttributes(unit,b);
        check(b.伤害类型=="破击" && b.魔法伤害属性=="热","first revival selects native heat crush");
        b.破坏力=1000;
        var target:Object={防御力:900,等级:28,魔法抗性:{热:20}};
        var result:DamageResult=new DamageResult();
        var handler:UniversalDamageHandle=UniversalDamageHandle.getInstance();
        handler.handleBulletDamage(b,unit,target,null,result);
        check(near(target.损伤值,330),"native first tier is physical 250 plus heat 80");
        check((result._efFlags&16)!=0 && (result._efFlags&8)==0 && result._efEmoji=="✨" && result._efText=="热",
            "first tier carries the standard blue sparkle heat label");
        target.魔法抗性.热=0;handler.handleBulletDamage(b,unit,target,null,result);
        check(near(target.损伤值,350),"zero heat resistance preserves the native ten percent bonus");
        target.魔法抗性.热=100;handler.handleBulletDamage(b,unit,target,null,result);
        check(near(target.损伤值,250),"heat immunity retains first-tier physical damage");
        target.魔法抗性.热=-100;handler.handleBulletDamage(b,unit,target,null,result);
        check(near(target.损伤值,450),"heat weakness follows standard crush calculation");
        owner.tier=2;HuofengCombat.primaryAttributes(unit,b);result.reset();
        check(b.伤害类型=="魔法" && b.魔法伤害属性=="热","second revival selects native pure heat");
        target.魔法抗性.热=20;handler.handleBulletDamage(b,unit,target,null,result);
        check(near(target.损伤值,800),"converted primary uses heat resistance and bypasses armor");
        check((result._efFlags&8)!=0 && (result._efFlags&16)==0 && result._efText=="热",
            "second tier uses the standard magic label without a second crush copy");
        target.防御力=0;handler.handleBulletDamage(b,unit,target,null,result);
        check(near(target.损伤值,800),"changing armor cannot change converted primary");
        target.魔法抗性.热=90;handler.handleBulletDamage(b,unit,target,null,result);
        check(near(target.损伤值,100),"high heat resistance remains a real counter");
        var modes:Array=["兵器","长枪","手枪","双枪","手枪兵器"];
        var types:Array=["物理","魔法","真伤"];
        for(var tier:Number=1;tier<=2;tier++) for(var m:Number=0;m<modes.length;m++) for(var t:Number=0;t<types.length;t++) {
            owner.tier=tier;unit.攻击模式=modes[m];
            var weapon:Object={伤害类型:types[t],魔法伤害属性:"冰",毒:7,吸血:3};
            HuofengCombat.decorateCold(unit,weapon);
            check(weapon.伤害类型===types[t] && weapon.魔法伤害属性==="冰" && weapon.毒===7 && weapon.吸血===3,
                "real weapon keeps its attributes tier="+tier+" mode="+modes[m]+" type="+types[t]);
        }
        unit.攻击模式="长枪";HuofengCombat.primaryAttributes(unit,b);
        check(b.伤害类型=="物理","firearm mode does not acquire heat conversion");
    }
    private static function calculator():Void {
        var noise:Object=org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine.getInstance();
        var previousNoise:Function=noise.randomFluctuation;
        var previousRed:Function=_root.受击变红;
        noise.randomFluctuation=function():Number{return 1;};
        _root.受击变红=function():Void {};
        var owner:Object={tier:1,isActive:function():Boolean{return true;},getTier:function():Number{return this.tier;}};
        var shooter:Object={hp:1000,hp满血值:1000,伤害加成:100,__huofeng:owner,攻击模式:"空手",
            基础伤害类型:"物理",基础命中率:100};
        var shield:Object={calls:0,capacity:0,last:0,getStrength:function():Number{return 0;},
            absorbDamage:function(d:Number):Number{this.calls++;this.last=d;return Math.max(0,d-this.capacity);}};
        var target:Object={hp:100000,hp满血值:100000,防御力:300,等级:28,魔法抗性:{热:0},shield:shield};
        var b:Object={flags:0,子弹威力:1000,固伤:0,百分比伤害:0,霰弹值:1,__huofengFinalPower:true};
        var factory:DamageManagerFactory;
        var ownsFactory:Boolean=false;
        // Native hosts already initialize Basic. Standalone suites may own it locally.
        try { factory=DamageManagerFactory.getFactory("Basic"); }
        catch(unregistered) { factory=DamageManagerFactory.createBasic();ownsFactory=true; }
        try {
            HuofengCombat.primaryAttributes(shooter,b);b.damageManager=factory.getDamageManager(b);
            var result:DamageResult=DamageCalculator.calculateDamage(b,shooter,target,1,"未躲闪");
            check(target.hp==99400 && target.损伤值==600 && result.totalDamageList[0]==600,
                "native pipeline settles and displays physical 500 plus heat 100 exactly once");
            check(shield.calls==1 && shield.last==600,"combined native damage crosses the shield once");
            check(result._efText=="热" && result._efEmoji=="✨" && (result._efFlags&16)!=0,
                "actual calculator preserves standard sparkle heat metadata");
            target.hp=100000;shield.calls=0;shield.capacity=550;
            result=DamageCalculator.calculateDamage(b,shooter,target,1,"未躲闪");
            check(target.hp==99950 && shield.calls==1 && result._efShieldAbsorb==550,
                "a shield covering the physical part still receives the heat in the same transaction");
            target.hp=100000;shield.capacity=1000;shield.calls=0;
            DamageCalculator.calculateDamage(b,shooter,target,1,"未躲闪");
            check(target.hp==100000 && shield.calls==1,"full shield absorption cannot leak a second heat hit");
            target.hp=100000;shield.capacity=0;
            result=DamageCalculator.calculateDamage(b,shooter,target,1,"躲闪");
            check(target.hp==100000 && result.dodgeStatus=="MISS","native MISS cancels both damage portions");
            b.暴击=function():Number{return 2;};b.damageManager=factory.getDamageManager(b);target.hp=100000;
            result=DamageCalculator.calculateDamage(b,shooter,target,1,"未躲闪");
            check(target.hp==98800 && result.totalDamageList[0]==1200,"one native critical multiplier applies to both portions");
            delete b.暴击;b.damageManager=factory.getDamageManager(b);target.hp=100000;target.魔法抗性.热=100;
            DamageCalculator.calculateDamage(b,shooter,target,1,"未躲闪");
            check(target.hp==99500,"first-tier heat immunity still allows native physical damage");
            target.魔法抗性.热=20;target.hp=100000;owner.tier=2;
            HuofengCombat.primaryAttributes(shooter,b);b.damageManager=factory.getDamageManager(b);
            result=DamageCalculator.calculateDamage(b,shooter,target,1,"未躲闪");
            check(target.hp==99200 && result.totalDamageList[0]==800 && (result._efFlags&16)==0,
                "second tier has exactly one standard magic damage result");
            owner.tier=1;shooter.攻击模式="兵器";target.hp=100000;b.伤害类型="物理";delete b.魔法伤害属性;
            HuofengCombat.decorateCold(shooter,b);b.damageManager=factory.getDamageManager(b);
            result=DamageCalculator.calculateDamage(b,shooter,target,1,"未躲闪");
            check(target.hp==99500 && (result._efFlags&24)==0,"carried blade remains ordinary physical damage and display");
        } finally {
            if(ownsFactory)DamageManagerFactory.removeFactory("Basic");
            noise.randomFluctuation=previousNoise;
            _root.受击变红=previousRed;
        }
    }
    private static function lifecycle():Void {
        var clock=_root.帧计时器,paused=_root.暂停;
        var fx:Function=EffectSystem.Effect;EffectSystem.Effect=function():Void {};
        _root.帧计时器={当前帧数:0};_root.暂停=false;
        var u:MovieClip=_root.createEmptyMovieClip("hfLifecycleFixture",_root.getNextHighestDepth());
        u.version=1;u.hp=1001;u.hp满血值=1001;u.mp=100;u.攻击模式="空手";u.状态="空手站立";
        u.主动战技={空手:{名字:"previous"}};
        u.装载主动战技=function(info:Object,mode:String):Void {this.主动战技[mode]={名字:info.skillname};};
        for(var i:Number=0;i<HuofengRules.SLOTS.length;i++) {
            u[HuofengRules.SLOTS[i]]={name:"fixture",value:{level:1}};
            u[HuofengRules.SLOTS[i]+"数据"]={setId:"huofeng"};
        }
        u.buffManager=new BuffManager(u);
        var projection:PlayerHudBuffProjection=new PlayerHudBuffProjection();
        projection.setDetailsEnabled(true);projection.initialize(u.buffManager);
        var group:Object={status:"preparing",id:"hf-fixture",rollbackPlan:{resourceStack:[]},teardownPlan:{resourceStack:[]}};
        var effect:Object={group:group};
        var runtime:HuofengSetRuntime=HuofengSetRuntime(HuofengSetRuntime.prepare(effect,u));
        check(runtime!=null,"five-piece preparation");
        var chest:Object;
        for(i=0;i<HuofengRules.SLOTS.length;i++) {
            var ref:Object={自机:u,装备类型:HuofengRules.SLOTS[i],套装效果记录:effect,套装事务:group};
            var status:String=runtime.initializeComponent(ref,{});
            check(status===(i==1 ? "ready_cycle" : "ready_static"),"component readiness "+i);
            if(i==1)chest=ref;
        }
        check(!runtime.isActive(),"prepared group grants no ability");
        check(projection.snapshot().length==0,"uncommitted set grants no HUD status");
        group.status="committed";
        check(runtime.isActive() && HuofengRules.profileActive(u),"committed group grants profile");
        check(group.teardownPlan.resourceStack.length==1,"single owned cleanup");
        check(u.主动战技.空手.名字==="焰链回旋","hand component installs skill");
        u.version++;
        check(runtime.isActive(),"weapon-only version change retains committed armor runtime");
        runtime.tick(chest);
        var initial:Array=projection.snapshot();
        check(initial.length==1 && initial[0].info.name=="火凤链锤" && initial[0].info.description.indexOf("30击")>=0,
            "committed set exposes its existing abilities through the normal Buff bar");
        check(initial[0].activation.active===true && initial[0].activation.activeLabel=="流星锤模式",
            "base status reports the actual weapon profile");
        check(u.buffManager.getAllMetaBuffs().length==1 && initial[0].mods==undefined,
            "status registration does not manufacture numeric modifiers");
        var baseId:String=initial[0].id;
        var state:Object=runtime.getState();state.tier=1;
        _root.帧计时器.当前帧数=1;runtime.tick(chest);
        check(u.hp满血值==700 && u.hp==700,"fractional H0 is floored and clamped");
        var first:Array=projection.snapshot();
        check(first.length==2 && first[0].id==baseId && first[1].info.name=="初次涅槃",
            "first paid tier adds one named Nirvana status without replacing the set status");
        check(first[1].info.description.indexOf("70%")>=0 && first[1].info.description.indexOf("3%")>=0
            && first[1].info.description.indexOf("10%")>=0,"first tooltip exposes real ceiling, healing and native heat bonus");
        check(initial.length==1,"later registration leaves the previous HUD snapshot immutable");
        u.buffManager.update(30);
        check(projection.snapshot().length==2 && u.hp==700,"condition-owned zero-Pod statuses survive normal maintenance without healing");
        u.攻击模式="长枪";
        var gun:Array=projection.snapshot();
        check(gun[0].activation.active===false && gun[0].activation.inactiveLabel=="切换空手启用"
            && gun[1].info.name=="初次涅槃" && state.tier==1,"weapon switch suspends only the hammer profile display");
        u.攻击模式="空手";
        var stable:Array=projection.snapshot();
        for(var readIndex:Number=0;readIndex<30;readIndex++)check(projection.snapshot()===stable,"unchanged tooltip read reuses snapshot "+readIndex);
        check(u.hp==700 && u.mp==100 && state.tier==1 && u.buffManager.getAllMetaBuffs().length==2,
            "HUD reads never heal, spend, restack or recreate the contract");
        u.hp=100;
        for(i=2;i<=15;i++){_root.帧计时器.当前帧数=i;runtime.tick(chest);}
        check(near(u.hp,115.015),"tier one half-second uses H0");
        var before:Number=u.hp;_root.暂停=true;
        for(i=16;i<116;i++){_root.帧计时器.当前帧数=i;runtime.tick(chest);}
        check(near(u.hp,before),"paused maintenance does not heal");
        _root.暂停=false;_root.帧计时器.当前帧数=116;runtime.tick(chest);
        check(near(u.hp,before),"resume does not catch up missed healing");
        state.tier=2;_root.帧计时器.当前帧数=117;runtime.tick(chest);
        check(u.hp满血值==500 && near(u.hp,before),"second projection replaces rather than multiplies");
        // Buff removals are deferred; simulate the normal manager tick, never a HUD-driven flush.
        u.buffManager.update(0);
        var second:Array=projection.snapshot();
        check(second.length==2 && second[0].id==baseId && second[1].info.name=="涅槃复苏",
            "second tier replaces first status instead of stacking another benefit");
        check(second[1].info.description.indexOf("50%")>=0 && second[1].info.description.indexOf("6%")>=0
            && second[1].info.description.indexOf("纯热")>=0,"second tooltip describes its actual cost and conversion");
        check(first[1].info.name=="初次涅槃","tier replacement preserves older immutable snapshots");
        state.tier=0;runtime.tick(chest);u.buffManager.update(0);
        check(projection.snapshot().length==1 && u.hp满血值==1001 && near(u.hp,before),
            "contract reset retires the Nirvana card without granting HP");
        state.tier=2;runtime.tick(chest);u.buffManager.update(0);
        check(projection.snapshot().length==2 && u.hp满血值==500,"subsequent tier projection has exactly one current card");
        u.mp=Number.NaN;
        check(!runtime.canSpin(),"invalid MP cannot enter spin");
        u.mp=35;check(!runtime.canSpin(),"first loop total cost preflight");
        u.mp=36;check(runtime.canSpin(),"36 MP permits first loop");
        state.spinReadyFrame=500;check(!runtime.canSpin(),"run-owned cooldown gate");
        var unrelated:MetaBuff=new MetaBuff([new PodBuff("fixturePower",BuffCalculationType.ADD,5)],[],0);
        unrelated.hudInfo={name:"other owner",description:"fixture",polarity:"benefit",stacks:0};
        u.buffManager.addBuff(unrelated,"hf-unrelated-fixture");
        var foreign:Object={名字:"another owner"};u.主动战技.空手=foreign;
        runtime.dispose();
        u.buffManager.update(0);
        check(u.主动战技.空手===foreign,"cleanup preserves another skill owner");
        check(u.__huofeng==undefined && u.__huofengHpContract==undefined,"cleanup removes only owned projection");
        check(u.hp满血值==1001 && near(u.hp,before),"unequip does not refill HP");
        check(HuofengRunState.forUnit(u)===state && state.tier==2 && state.spinReadyFrame==500,"neutral lifecycle teardown retains tier and cooldown");
        check(projection.snapshot().length==1 && projection.snapshot()[0].info.name=="other owner",
            "unequip removes only its own status registrations");
        runtime.dispose();check(near(u.hp,before),"cleanup is idempotent");
        projection.deinitialize();
        u.buffManager.destroy();u.removeMovieClip();
        _root.帧计时器=clock;_root.暂停=paused;EffectSystem.Effect=fx;
    }
    private static function controlledAction(kind:String,tier:Number):Object {
        var unit:MovieClip=_root.createEmptyMovieClip("hfActionFixture",_root.getNextHighestDepth());
        unit.hp=1000;unit.mp=76;unit.攻击模式="空手";unit.方向="右";
        unit.动作A=true;unit.动作B=false;
        unit.行走X速度=8;unit.跑X速度=16;unit.左行=unit.右行=unit.上行=unit.下行=false;
        unit.动画完毕=function():Void {this.recovered=true;};
        var runtime:Object={getUnit:function():MovieClip{return this.unit;},unit:unit,
            isActive:function():Boolean{return this.active;},active:true,
            state:{},getState:function():Object{return this.state;},
            clearAction:function(a:Object):Void{this.cleared=a;}};
        unit.__huofeng=runtime;
        var a:Object={kind:kind,tier:tier,serial:1,cancelled:false,frame:0,stage:0,localFrame:0,
            lastTick:-1,recovery:0,cycle:0,firstHit:false,direction:"右",owner:runtime};
        unit.createEmptyMovieClip("man",0);unit.man.__huofengAction=a;
        unit.man.gotoAndStop=function(f:Number):Void{this.shown=f;};
        return {unit:unit,action:a,runtime:runtime};
    }
    private static function actionClocks():Void {
        var clock=_root.帧计时器,paused=_root.暂停;
        var emit:Function=HuofengCombat.emit,blast:Function=HuofengCombat.blast,cancel:Function=HuofengInput.tryCancel;
        var move:Function=Mover.move2D,key:Function=HuofengInput.weaponSkillHeld;
        var cancelQueue:Object=org.flashNight.arki.bullet.BulletComponent.Queue.BulletCancelQueueProcessor;
        var originalEnqueue:Function=cancelQueue.enqueue;
        cancelQueue.enqueue=function(request:Object):Void{HuofengContractTest.cancelFrames.push(-_root.帧计时器.当前帧数);};
        HuofengCombat.emit=function(u:MovieClip,a:Object,b:Number,f:Number,d:Number,push:Number):Void{HuofengContractTest.pulses.push({frame:a.frame,b:b,f:f,push:push});};
        HuofengCombat.blast=function(u:MovieClip,a:Object):Void{HuofengContractTest.pulses.push({frame:a.frame});};
        HuofengInput.tryCancel=function(u:MovieClip,a:Object):Boolean{HuofengContractTest.cancelFrames.push(a.frame);return false;};
        Mover.move2D=function(u:MovieClip,d:String,s:Number):Void{HuofengContractTest.moved+=s;};
        HuofengInput.weaponSkillHeld=function():Boolean{return HuofengContractTest.held;};
        _root.帧计时器={当前帧数:0};_root.暂停=false;
        var cases:Array=[{kind:"normal",tier:0,end:95,hits:30},{kind:"run",tier:0,end:48,hits:12},
            {kind:"spin",tier:0,end:72,hits:24},{kind:"spin",tier:0,end:126,hits:48},
            {kind:"nirvana",tier:1,end:92,hits:3},{kind:"nirvana",tier:2,end:113,hits:6}];
        for(var k:Number=0;k<cases.length;k++){
            var c:Object=cases[k];var fixture:Object=controlledAction(c.kind,c.tier);
            pulses=[];cancelFrames=[];moved=0;held=k==3;
            for(var i:Number=1;i<=c.end;i++){
                _root.帧计时器.当前帧数=i;
                if(k==0 && i==70) fixture.unit.动作A=false;
                HuofengAction.tick(fixture.unit.man);
                if(i==c.end-1)check(!fixture.action.cancelled,"action remains active before final frame "+k);
            }
            check(pulses.length==c.hits,"action pulse count "+k);
            check(fixture.action.cancelled && fixture.unit.recovered,"action releases control on exact final frame "+k);
            if(k==0){
                var sum:Number=0;for(i=0;i<pulses.length;i++)sum+=pulses[i].b;
                check(near(sum,21.75),"normal chain raw coefficient 21.75B across thirty small contacts");
                var pushed:Number=0,sameFrameCancel:Number=0;
                for(i=0;i<pulses.length;i++){
                    if(pulses[i].push==8){pushed++;check(i==29,"only the actual final contact has finisher push");}
                    else check(pulses[i].push==2,"all preceding contacts retain light push");
                    for(var j:Number=0;j<cancelFrames.length;j++)if(cancelFrames[j]==pulses[i].frame)sameFrameCancel++;
                }
                check(pushed==1,"one finisher push across the full thirty-contact chain");
                check(sameFrameCancel==0,"cancel windows cannot invalidate a just-emitted final contact");
                var starts:Array=[13,22,36,60,71];
                for(i=0;i<starts.length;i++){
                    var found:Boolean=false;for(j=0;j<cancelFrames.length;j++)if(cancelFrames[j]==starts[i])found=true;
                    check(found,"cancel opens exactly one frame after the stage final contact "+i);
                }
                check(fixture.runtime.state.primaryReadyFrame==95,"fifth-stage recovery remains run-owned through cancellation");
                check(fixture.unit.动作A===false,"release before the loop window retains the complete authored stop");
            }
            if(k==1) {
                check(near(moved,422.4),"run uses 24 collision-aware 17.6-pixel movement requests");
                sum=0;for(i=0;i<pulses.length;i++)sum+=pulses[i].b;
                check(near(sum,10.2),"run distributes 10.2B across twelve contacts");
            }
            if(k==2) {
                sum=0;var force:Number=0;
                for(i=0;i<pulses.length;i++){sum+=pulses[i].b;force+=pulses[i].f;}
                check(near(sum,18) && near(force,6),"first spin loop distributes 18B plus 6F across twenty-four contacts");
            }
            if(k==2 || k==3) {
                check(fixture.unit.mp==(k==2?64:52),"spin loop cost excludes accepted 24 MP already paid "+k);
                check(cancelFrames.length==(k==2?141:282),"spin cancels on every active frame, three coverage bands per frame");
                var safeWindow:Boolean=true;
                for(i=0;i<cancelFrames.length;i++) {
                    var cf:Number=-cancelFrames[i];
                    if(!((cf>=14 && cf<=60) || (k==3 && cf>=68 && cf<=114))) safeWindow=false;
                }
                check(safeWindow,"windup, loop transition and recovery have no cancellation");
            }
            fixture.unit.removeMovieClip();
        }
        fixture=controlledAction("normal",0);pulses=[];
        _root.暂停=true;_root.帧计时器.当前帧数=1000;HuofengAction.tick(fixture.unit.man);
        check(fixture.action.frame==0,"paused action clock does not advance");
        _root.暂停=false;HuofengAction.tick(fixture.unit.man);HuofengAction.tick(fixture.unit.man);
        check(fixture.action.frame==1,"same-frame callback deduplicated");
        fixture.unit.攻击模式="长枪";_root.帧计时器.当前帧数++;HuofengAction.tick(fixture.unit.man);
        check(fixture.action.cancelled && pulses.length==0,"mode change cancels pending own contacts");
        fixture.unit.removeMovieClip();
        HuofengPressureTest.repeatContract(controlledAction,check);
        cancelQueue.enqueue=originalEnqueue;
        HuofengCombat.emit=emit;HuofengCombat.blast=blast;HuofengInput.tryCancel=cancel;Mover.move2D=move;HuofengInput.weaponSkillHeld=key;
        _root.帧计时器=clock;_root.暂停=paused;
    }
    private static function hairOwnership():Void {
        var u:MovieClip=_root.createEmptyMovieClip("hfHairFixture",30001);
        u.面具="HF8/Hair/Front";u.syncRefs={};
        u.dispatcher={subscribe:function():Boolean{return true;},unsubscribe:function():Void{}};
        var config:Object=HuofengHairProfile.hair();
        var rig:HuofengHairRig=new HuofengHairRig(u,config,"HF8/Hair/Front");
        check(!rig.isDisposed() && rig.bindCount==0 && u.__hf8HairOwner.controller===rig,"R9 constructor establishes ownership before reference placement");
        var replacement:HuofengHairRig=new HuofengHairRig(u,config,"HF8/Hair/Front");
        check(rig.isDisposed() && !replacement.isDisposed(),"R9 reinitialization releases previous owner");
        rig.dispose();check(u.__hf8HairOwner.controller===replacement,"old R9 cleanup preserves new owner");
        u.面具="other";replacement.update();
        check(replacement.isDisposed() && u.__hf8HairOwner==undefined,"unequip releases R9 ownership");
        u.removeMovieClip();
    }
    public static function runAllTests():Void {
        passed=failed=0;
        var phase:String="start";
        try {
            phase="legacyProjection";trace("HuofengContractTest Phase: "+phase);legacyProjection();
            phase="hpContract";trace("HuofengContractTest Phase: "+phase);hpContract();
            phase="paidRevives";trace("HuofengContractTest Phase: "+phase);paidRevives();
            phase="unequipContract";trace("HuofengContractTest Phase: "+phase);unequipContract();
            phase="nativeContacts";trace("HuofengContractTest Phase: "+phase);nativeContacts();
            phase="contactAndHeat";trace("HuofengContractTest Phase: "+phase);contactAndHeat();
            phase="conversion";trace("HuofengContractTest Phase: "+phase);conversion();
            phase="calculator";trace("HuofengContractTest Phase: "+phase);calculator();
            phase="lifecycle";trace("HuofengContractTest Phase: "+phase);lifecycle();
            phase="actionClocks";trace("HuofengContractTest Phase: "+phase);actionClocks();
            phase="hairOwnership";trace("HuofengContractTest Phase: "+phase);hairOwnership();
        } catch(error) {
            check(false,"phase "+phase+" threw "+error);
        }
        trace("[HuofengContractTest] "+passed+" passed, "+failed+" failed");
        trace("HuofengContractTest Complete");
    }
}
