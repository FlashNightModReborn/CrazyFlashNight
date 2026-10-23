import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;

/** 稳定输入及实际新旧运行来源；原缺陷复现回执单独保留，不计入修复通过数。 */
class org.flashNight.arki.unit.PlayerStatProjectionTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var slots:Array = ["头部装备","上装装备","手部装备","下装装备","脚部装备","颈部装备","长枪","手枪","手枪2","刀","手雷"];

    public static function runAllTests():Void {
        _passed = _failed = 0;
        var keys:Array = ["控制目标","全局健身HP加成","全局健身MP加成","全局健身空攻加成","全局健身防御加成","全局健身内力加成","经脉HP加成","经脉MP加成","经脉防御加成","经脉内力加成","敌人函数"];
        var before:Object = {};
        for (var i:Number = 0; i < keys.length; i++) before[keys[i]] = _root[keys[i]];
        trace("PlayerStatProjectionTest Evidence: fixed-production-methods");
        try {
            _root.控制目标 = "stat-test";
            for (i = 1; i < 10; i++) _root[keys[i]] = 0;
            _root.敌人函数 = {魔法伤害种类:["基础","电","热","冷","波","蚀","毒","冲","人类"]};
            testRepeatAndLoner();
            testResources();
            testStableEquipmentInput();
            testPersistentProjection();
            testRuntimeSources();
            testWeaponModes();
        } catch (error) {
            check(false,"suite exception: " + error);
        } finally {
            for (i = 0; i < keys.length; i++) _root[keys[i]] = before[keys[i]];
        }
        trace("PlayerStatProjectionTest Tests Passed: " + _passed);
        trace("PlayerStatProjectionTest Tests Failed: " + _failed);
    }

    private static function check(value:Boolean, label:String):Void {
        if (value) { _passed++; trace("[PASS] " + label); }
        else { _failed++; trace("[FAIL] " + label); }
    }

    public static function fixture():Object {
        var t:Object = {_name:"stat-test",等级:20,hp:600,hp满血值:1000,hp基本满血值:1000,
            mp:200,mp满血值:500,mp基本满血值:500,基本空手攻击力:100,基本防御力:100,
            体重:50,基础命中率:10,基础韧性系数:1,基础躲闪率:10,label:{},攻击模式:"长枪",
            魔法抗性:{},area:{_height:136},_yscale:100,根据模式重新读取武器加成:function():Void {}};
        for (var i:Number = 0; i < slots.length; i++) t[slots[i] + "数据"] = {data:{}};
        t.头部装备数据.data.gunpower = 5;
        t.长枪数据.data.power = 100; t.长枪数据.data.capacity = 30;
        t.长枪属性 = t.长枪数据.data;
        t.手枪属性 = {}; t.手枪2属性 = {}; t.刀属性 = {}; t.手雷属性 = {};
        return t;
    }

    private static function testRepeatAndLoner():Void {
        var api = org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        var t:Object = persistentFixture();
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t)); var first:Number = t.长枪属性.power;
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t)); var second:Number = t.长枪属性.power;
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t)); var third:Number = t.长枪属性.power;
        check(first == 105 && second == 105 && third == 105,"same stable input remains 105");
        t = persistentFixture(); t.hp满血值 = 1150; t.被动技能 = {独行者:{等级:3,启用:true}};
        _root.全局健身HP加成 = 10;
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.hp满血值 == 1160,"gym preserves loner");
        _root.全局健身HP加成 = 0;
        var items:Object=org.flashNight.arki.item.ItemUtil;var oldSets:Object=items.itemSetConfigDict;
        var sets:Object=org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController;
        try {
            t=persistentFixture();t.生命周期函数列表=[];t.头部装备数据.setId="repeat-set";
            items.itemSetConfigDict={};
            items.itemSetConfigDict["repeat-set"]={effects:{effect_0:{id:"res",kind:"template",threshold:1,template:"resistance_entry",params:{attribute:"原体",calculation:"add",baseIfMissing:10,value:75}}}};
            api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));sets.prepare(t);sets.finalize(t);
            api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
            check(t.魔法抗性.原体==85,"committed static set source survives projection");
        } finally {items.itemSetConfigDict=oldSets;}
    }

    private static function testStableEquipmentInput():Void {
        var api:Object = org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        var projection:Object = org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
        var items:Object = org.flashNight.arki.item.ItemUtil;
        var beforeData:Object = items.itemDataDict;
        var beforeEquipment:Object = items.equipmentDict;
        try {
            items.itemDataDict = {statSource:{name:"statSource",use:"长枪",data:{power:137,capacity:20,hp:31,magicdefence:{热:7}}}};
            items.equipmentDict = {statSource:true};
            var item = new org.flashNight.arki.item.BaseItem("statSource",{level:3,mods:[]},1);
            var expected:Object = item.getData();
            var t:Object = fixture(); t.version=1;
            var load:Function = function(target:Object,key:String):Object { return key=="长枪" ? target.__testItem : null; };
            t.__testItem = item;
            for(var i:Number=0;i<slots.length;i++) api.loadEquipmentData(t,slots[i],load,1);
            projection.beginCanonical(t); projection.completeCanonical(t);
            var input:Object = api.readNumericSources(t);
            check(input.slots.长枪.data.power==expected.data.power && input.slots.长枪.data.hp==expected.data.hp,
                "stable source matches real BaseItem strengthened result");
            check(t.长枪属性!==t.长枪数据.data && input.slots.长枪.data!==t.长枪数据.data,
                "numeric source, canonical data and live output are distinct objects");
            t.长枪属性.power=9999; t.长枪数据.data.magicdefence.热=999;
            check(input.slots.长枪.data.power==expected.data.power && input.slots.长枪.data.magicdefence.热==7,
                "live power and nested resistance cannot mutate source");
            item.getData=function():Object { throw new Error("unexpected getData in STATS source read"); return null; };
            var valid:Boolean=true;
            for(i=0;i<100;i++) if(api.readNumericSources(t)==null) valid=false;
            check(valid,"100 cold source reads do not call getData");
            item.value.level=4;
            check(api.readNumericSources(t)==null,"same item value mutation expires source");
            item.value.level=3; item.value.mods=["changed"];
            check(api.readNumericSources(t)==null,"same item modifier mutation expires source");
        } finally { items.itemDataDict=beforeData; items.equipmentDict=beforeEquipment; }
    }

    private static function persistentFixture():Object {
        var t:Object = fixture(); t.version=1;
        var data:Object = {};
        for (var i:Number=0;i<slots.length;i++) data[slots[i]]=t[slots[i]+"数据"];
        t.__sourceFixture={};
        for (i=0;i<slots.length;i++) {
            var slot:String=slots[i];
            t.__sourceFixture[slot]={name:"source:"+slot,value:{level:1,mods:[]},data:data[slot],getData:function():Object { return this.data; }};
        }
        var load:Function=function(target:Object,key:String):Object { return target.__sourceFixture[key]; };
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        for(i=0;i<slots.length;i++) api.loadEquipmentData(t,slots[i],load,1);
        org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.beginCanonical(t);
        org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.completeCanonical(t);
        return t;
    }

    private static function testPersistentProjection():Void {
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        var t:Object=persistentFixture();
        t.被动技能={独行者:{等级:3,启用:true}}; _root.全局健身HP加成=10;
        for(var i:Number=0;i<10;i++) api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.hp满血值==1160 && t.长枪属性.power==105 && t.hp==600,"persistent loner/gym and weapon are idempotent without resource writes");
        t.被动技能.独行者.等级=4;
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.hp满血值==1210,"loner level replaces absolute contribution");
        t.被动技能.独行者.启用=false;
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.hp满血值==1010 && t.伤害加成==0 && t.防御力==100,"disabled loner removes all contributions");
        _root.全局健身HP加成=0;
        t=persistentFixture();
        t.__persistentEquipmentInputV1.slots.头部装备.data.damage=10;
        t.基本防御力=120;
        t.buffManager=new org.flashNight.arki.component.Buff.BuffManager(t);
        t.buffManager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("伤害加成","add",22),"projection.damage");
        t.buffManager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("防御力","add",-13),"projection.defense");
        t.buffManager.update(0); // 夹具先按真实 Buff 帧安装；被测 STATS 不调用 update。
        var manager:Object=t.buffManager;
        for(i=0;i<10;i++) api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.伤害加成==32 && t.防御力==107 && t.buffManager===manager,"managed bases do not recapture final values or replace manager");
        t.buff=new 主角模板数值buff(t);
        t.buff.buff加算.魔法抗性=50;
        t.buff.buff限时id.魔法抗性="keep-timer";
        t.buff.buff加算.长枪威力=20;
        t.buffManager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("魔法抗性.热","multiply",2),"projection.path");
        t.buffManager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("长枪属性.power","percent",0.1),"projection.weapon");
        t.buffManager.update(0);
        var oldBuff:Object=t.buff;
        for(i=0;i<10;i++) api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.魔法抗性.热==124 && t.buff.基础值.魔法抗性.热==12,"legacy plus path Buff each apply once across resistance table rebind");
        check(Math.abs(t.长枪属性.power-137.5)<0.00001 && t.buff===oldBuff && t.buff.buff限时id.魔法抗性=="keep-timer",
            "legacy weapon plus new percent Buff preserve object and timed records");
        var beforeHp:Number=t.hp满血值; var rejected:Boolean=false;
        t.__persistentEquipmentInputV1.slots.头部装备.data.hp=Number.POSITIVE_INFINITY;
        try { api.buildPersistentSnapshot(t); } catch(error) { rejected=true; }
        check(rejected && t.hp满血值==beforeHp,"invalid source fails before live writes");
        t.buffManager.destroy();
    }

    private static function testRuntimeSources():Void {
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        var sets:Object=org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController;
        var itemApi:Object=org.flashNight.arki.item.ItemUtil;
        var oldSets:Object=itemApi.itemSetConfigDict;
        try {
            var t:Object=persistentFixture();
            t.生命周期函数列表=[]; t.头部装备数据.setId="stat-set";
            itemApi.itemSetConfigDict={};
            itemApi.itemSetConfigDict["stat-set"]={effects:{effect_0:{id:"res",kind:"template",threshold:1,template:"resistance_entry",params:{attribute:"原体",calculation:"add",baseIfMissing:10,value:75}}}};
            api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
            sets.prepare(t); sets.finalize(t);
            var count:Number=t.生命周期函数列表.length;
            for(var i:Number=0;i<100;i++) api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
            check(t.魔法抗性.原体==85 && t.生命周期函数列表.length==count,"committed set resistance replays 100 times without lifecycle installation");
            sets.teardownGroup(t,"stat-set:res");
            api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
            check(t.魔法抗性.原体==undefined,"set teardown removes its numeric source");
        } finally { itemApi.itemSetConfigDict=oldSets; }
        t=persistentFixture();t.基本空手攻击力=500;t.刀属性.power=80;
        t.__persistentEquipmentInputV1.slots.刀.data.power=80;
        t.buffManager=new org.flashNight.arki.component.Buff.BuffManager(t);
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(api.beginBlackRhinoTransfer(t) && t.空手攻击力==100 && t.刀属性.power==480,"black rhino lends both sides through one paired source");
        for(i=0;i<10;i++) api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.空手攻击力==100 && t.刀属性.power==480,"STATS retains fixed black rhino transfer");
        _root.全局健身空攻加成=10;
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        api.endBlackRhinoTransfer(t);api.endBlackRhinoTransfer(t);
        check(t.空手攻击力==510 && t.刀属性.power==80 && t.转换的冷兵器加成==0,"paired removal restores new permanent base once");
        _root.全局健身空攻加成=0;t.buffManager.destroy();
        var noBlade:Object={空手攻击力:500,刀属性:null};noBlade.buffManager=new org.flashNight.arki.component.Buff.BuffManager(noBlade);
        check(!api.beginBlackRhinoTransfer(noBlade) && noBlade.空手攻击力==500 && noBlade.转换的冷兵器加成==undefined,
            "black rhino rejects a missing blade before installing either side of its paired source");noBlade.buffManager.destroy();
        noBlade={空手攻击力:500,刀属性:{power:Number.NaN}};noBlade.buffManager=new org.flashNight.arki.component.Buff.BuffManager(noBlade);
        check(!api.beginBlackRhinoTransfer(noBlade) && noBlade.空手攻击力==500 && noBlade.转换的冷兵器加成==undefined,
            "black rhino rejects an invalid blade power with zero punch or transfer write");noBlade.buffManager.destroy();
        t=persistentFixture();t.损伤值=0;
        t.buffManager=new org.flashNight.arki.component.Buff.BuffManager(t);
        t.buff=new 主角模板数值buff(t);t.buff.buff倍率.hp满血值=1.5;
        t.buffManager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("hp满血值","percent",0.2),"stat.hp.percent");t.buffManager.update(0);
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        var result=new org.flashNight.arki.component.Damage.DamageResult();
        var bullet:Object={击溃:10,子弹威力:100,additionalEffectDamage:0};
        org.flashNight.arki.component.Damage.CrumbleDamageHandle.getInstance().handleBulletDamage(bullet,{},t,null,result);
        check(t.hp满血值==1620 && t.__crumbleCeilingLoss==180 && result._crumbleDamage==180,"crumble records actual final loss with old and new HP Buffs");
        t.hp基本满血值=1200;
        for(i=0;i<10;i++) api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.hp满血值==1980,"permanent growth retains 180 final points without multiplying damage");
        t.buffManager.removeBuff("stat.hp.percent");t.buffManager.update(0);
        check(t.hp满血值==1620,"HP Buff expiration retains the same final loss");
        t.buffManager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("hp满血值","override",2500),"stat.hp.override");t.buffManager.update(0);
        api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
        check(t.hp满血值==2320,"crumble remains after ordinary Buff override boundary");
        result.dodgeStatus="MISS";
        org.flashNight.arki.component.Damage.CrumbleDamageHandle.getInstance().handleBulletDamage(bullet,{},t,null,result);
        check(t.__crumbleCeilingLoss==180,"MISS does not append runtime loss");
        t.buffManager.destroy();
    }

    private static function testWeaponModes():Void {
        var api:Object=org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
        var data:Object=org.flashNight.arki.unit.PlayerStatItemFixtures.read();
        var items:Object=org.flashNight.arki.item.ItemUtil;
        var oldData:Object=items.itemDataDict;var oldEquipment:Object=items.equipmentDict;
        try {
            items.itemDataDict={};items.equipmentDict={};
            for(var kind:String in data) { items.itemDataDict[data[kind].name]=data[kind];items.equipmentDict[data[kind].name]=true; }
            var t:Object=persistentFixture();
            t.__testItem=new org.flashNight.arki.item.BaseItem(data.longForm.name,{level:1,mods:[],长柄形态:true},1);
            var load:Function=function(owner:Object,slot:String):Object {return owner.__testItem;};
            api.loadEquipmentData(t,"刀",load,1);
            org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.beginCanonical(t);
            org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.completeCanonical(t);
            t.被动技能={独行者:{等级:3,启用:true}};_root.全局健身HP加成=200;
            for(var i:Number=0;i<10;i++) api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
            check(t.刀属性.power==565 && t.hp满血值==1550,"real XML morph same-mode x10 retains 565 and complete 1550 build");
            t.刀.value.长柄形态=false;api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
            check(t.刀属性.power==531 && t.hp满血值==1000+data.dualForm.data.hp+350,"dual morph uses its own absolute XML contribution");
            t.刀.value.长柄形态=true;api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
            check(t.刀属性.power==565 && t.hp满血值==1550,"morph round trip does not accumulate");
            _root.全局健身HP加成=0;
            t=persistentFixture();t.__playerStatBody={};
            t.__testItem=new org.flashNight.arki.item.BaseItem(data.guitar.name,{level:1,mods:[],weaponMode:"机枪",shot:9},1);
            api.loadEquipmentData(t,"长枪",load,1);
            org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.beginCanonical(t);
            org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.completeCanonical(t);
            var guitar:Object={自机:t,属性投影身体:t.__playerStatBody,初始化参数:data.guitar.params,weaponValue:t.长枪.value,
                weaponMode:"机枪",机枪威力系数:0.5,机枪击倒力:15,机枪速度倍率:6,机枪射击间隔除数:2,
                机枪散射度除数:1.5,机枪霰弹值倍率:2,机枪弹容倍率:3,机枪命中效果:"火花",机枪枪口焰:"枪火",
                机枪音效:"p90-1.wav",机枪子弹:"加强普通子弹",过热:true,增幅次数:{note:7}};
            t.__statGuitarRef=guitar;
            for(i=0;i<10;i++) {var snapshot:Object=api.buildPersistentSnapshot(t);api.applyPersistentSnapshot(t,snapshot);api.refreshKnownModeCaches(t,snapshot);}
            check(t.长枪属性.power==55 && t.长枪属性.capacity==240 && t.长枪属性.interval==55,"real guitar machine mode has deterministic power/capacity/interval");
            check(t.长枪.value.shot==9 && guitar.过热 && guitar.增幅次数.note==7,"ordinary mode projection does not convert ammo or consume heat/note state");
            t.长枪.value.weaponMode="喷火器";api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
            check(t.长枪属性.power==105 && t.长枪属性.capacity==80,"guitar return uses stable base rather than previous multiplied output");
            var kinds:Array=["vocal","keyboard"];
            for(i=0;i<kinds.length;i++) {
                kind=kinds[i];t=persistentFixture();t.__playerStatBody={};
                t.__testItem=new org.flashNight.arki.item.BaseItem(data[kind].name,{level:1,mods:[],weaponMode:kind=="vocal" ? "话筒支架" : "键盘"},1);
                api.loadEquipmentData(t,"刀",load,1);
                org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.beginCanonical(t);
                org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection.completeCanonical(t);
                var ref:Object={自机:t,属性投影身体:t.__playerStatBody,初始化参数:data[kind].params,weaponValue:t.刀.value,keyboardDamageMultiplier:0.8,增幅次数:{note:4}};
                t[kind=="vocal" ? "__statVocalRef" : "__statKeyboardRef"]=ref;
                for(var repeat:Number=0;repeat<10;repeat++) api.applyPersistentSnapshot(t,api.buildPersistentSnapshot(t));
                check(Math.abs(t.刀属性.power-data[kind].data.power*0.8)<0.00001 && ref.增幅次数.note==4,"real "+kind+" mode repeats without power or note accumulation");
            }
            var modes:Array=["麻醉模式","击杀模式","分解模式"];
            var coefficients:Array=[1,7,28];var extra:Array=[0,7,10];
            for(i=0;i<modes.length;i++) {
                var output:Object=api.calculateDominatorMode(data.dominator.data,modes[i],5,15);
                check(output.power==data.dominator.data.power*coefficients[i]+5+15*extra[i],"real dominator "+modes[i]+" pure numeric source");
            }
        } finally {items.itemDataDict=oldData;items.equipmentDict=oldEquipment;_root.全局健身HP加成=0;}
    }

    private static function testResources():Void {
        check(HealApplier.settleHpAfterMaxChange(900,1000,800) == 800,"ordinary HP does not gain overflow");
        check(HealApplier.settleHpAfterMaxChange(1300,1000,800) == 1200,"existing overflow keeps absolute amount within cap");
        check(HealApplier.settleHpAfterMaxChange(0,1000,800) == 0,"projection does not revive");
        check(HealApplier.settleMpAfterMaxChange(900,800) == 800,"MP clamps without overflow entitlement");
    }
}
