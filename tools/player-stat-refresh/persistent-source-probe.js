'use strict';
const {fixture} = require('./runtime-source-probe');
const DRESS = 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as';
const PROJECTION = 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/RuntimeEquipmentProjection.as';
const SET = 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/SetEffectController.as';
function persistentFixture(source) {
    const f = fixture(source), text = source.read(DRESS).text;
    for (const name of ['numericInputKeys','persistentNumberKeys','persistentValueKeys','persistentInputKeys','weaponValueSuffixes']) {
        f.globals[name] = JSON.parse(text.match(new RegExp('var ' + name + ':Array = (\\[[\\s\\S]*?\\]);'))[1]);
    }
    const projection = source.methods(PROJECTION,['numericSourceRef','numericSourceSignature','readState','slotIndex','valueToken','modifierToken','stringToken'],
        {STATE_KEY:'__runtimeEquipmentProjectionV1',STATE_VERSION:1,SLOT_KEYS:Object.keys(f.globals.equipmentKeys)});
    f.globals.RuntimeEquipmentProjection = projection;
    f.globals.SetEffectController = source.methods(SET,['projectStaticResistance','calculateAdditiveResistance','isFiniteNumber']);
    f.globals.projectionFaultForTests = undefined;
    const names = ['copyNumericInput','recordNumericSource','readNumericSources','lonerContribution','buildPersistentSnapshot',
        'projectKnownModeInputs','calculateMusicMode','calculateDominatorMode',
        'validateNumericInput','validatePersistentSnapshot','setPersistentBase','previewPersistentBase','previewPersistentSnapshot','applyPersistentSnapshot',
        'resolveStableBaseStat','resolveTemplateMagicResistance','readGlobalBonus','updateProperty','computeEquipmentProperties',
        'removePrimaryProperty','removeSecondary1Property','removeSecondary2Property','removeMeleeProperty','removeHandProperty','removeGrenadeProperty'];
    f.api = source.methods(DRESS,names,f.globals);
    const t = f.target;
    Object.assign(f.root,{限制系统:{},宠物信息:[],佣兵个数限制:0});
    t.buff = {};t.buffManager = {};
    // AS2 permits an absent contract's property read; the JS extraction needs an explicit empty port.
    t.__huofengHpContract = {};
    t.被动技能 = {};t.__pileBunkerM7 = {};
    t.__persistentEquipmentInputV1 = {slots:{}};
    for (const slot of Object.keys(f.globals.equipmentKeys)) {
        const item = {name:'source:'+slot,value:{level:1,mods:[]}};t[slot]=item;
        f.api.recordNumericSource(t,slot,item,t[slot+'数据']);
    }
    return f;
}
module.exports = function run(source,report) {
    const f = persistentFixture(source), t = f.target, powers = [];
    t.被动技能 = {独行者:{等级:3,启用:true}};
    f.root.全局健身HP加成=10;
    for (let i=0;i<10;i++) { f.api.applyPersistentSnapshot(t,f.api.buildPersistentSnapshot(t));powers.push(t.长枪属性.power); }
    report('persistent-weapon-repeat',powers,Array(10).fill(105));
    report('persistent-loner-gym',t.hp满血值,1160);
    t.被动技能.独行者.启用=false;
    f.api.applyPersistentSnapshot(t,f.api.buildPersistentSnapshot(t));
    report('persistent-loner-disabled',[t.hp满血值,t.伤害加成,t.防御力],[1010,0,100]);
    const hp=t.hp满血值;
    t.__persistentEquipmentInputV1.slots.头部装备.data.hp=Infinity;
    let rejected=false;try { f.api.buildPersistentSnapshot(t); } catch(error) { rejected=/stat_input_invalid/.test(error.message); }
    report('persistent-invalid-zero-write',[rejected,t.hp满血值],[true,hp]);

    const capped = persistentFixture(source), h = capped.target;
    h.被动技能 = {独行者:{等级:0,启用:false}};
    h.__persistentEquipmentInputV1.slots.刀.data.hp = -1127;
    for (let i=0;i<3;i++) capped.api.applyPersistentSnapshot(h,capped.api.buildPersistentSnapshot(h));
    report('persistent-negative-hp-floor',[h.hp满血值,h.hp满血值装备加层,h.hp,h.mp],[1,-1127,600,200]);
    h.被动技能.独行者={等级:3,启用:true};capped.root.全局健身HP加成=10;capped.root.经脉HP加成=20;
    capped.api.applyPersistentSnapshot(h,capped.api.buildPersistentSnapshot(h));
    report('persistent-hp-floor-after-all-contributions',h.hp满血值,53);
    delete h.__persistentEquipmentInputV1.slots.刀.data.hp;
    capped.api.applyPersistentSnapshot(h,capped.api.buildPersistentSnapshot(h));
    report('persistent-hp-source-restored-without-healing',[h.hp满血值,h.hp,h.mp],[1180,600,200]);

    // A legitimate flat punch penalty (e.g. 指骨撑架) must not poison the
    // mercenary-only square-root weight or reject the player's entire build.
    const penalty = persistentFixture(source), p = penalty.target;
    p.被动技能 = {独行者:{等级:0,启用:false}};
    p.__persistentEquipmentInputV1.slots.手部装备.data.punch = -5;
    penalty.api.applyPersistentSnapshot(p,penalty.api.buildPersistentSnapshot(p));
    report('persistent-negative-punch',[p.空手攻击力,p.佣兵技能概率抑制基数,p.hp,p.mp],[95,0,600,200]);
    p.__persistentEquipmentInputV1.slots.头部装备.data.punch = 16;
    for (let i=0;i<3;i++) penalty.api.applyPersistentSnapshot(p,penalty.api.buildPersistentSnapshot(p));
    report('persistent-mixed-punch-repeat',[p.空手攻击力,p.佣兵技能概率抑制基数],[111,4]);
    p.__persistentEquipmentInputV1.slots.手部装备.data.punch = 0;
    penalty.api.applyPersistentSnapshot(p,penalty.api.buildPersistentSnapshot(p));
    report('persistent-zero-punch',[p.空手攻击力,p.佣兵技能概率抑制基数],[116,4]);
    p.__persistentEquipmentInputV1.slots.手部装备.data.punch = NaN;
    let invalidPunch=false;
    try { penalty.api.buildPersistentSnapshot(p); } catch(error) { invalidPunch=/stat_input_invalid:punch/.test(error.message); }
    report('persistent-invalid-punch-still-rejected',[invalidPunch,p.空手攻击力,p.佣兵技能概率抑制基数],[true,116,4]);
};
module.exports.fixture = persistentFixture;
