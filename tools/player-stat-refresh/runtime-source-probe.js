'use strict';

const DRESS = 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as';
const HEAL = 'scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/HealApplier.as';
const CONTAINER = 'scripts/类定义/org/flashNight/arki/component/Buff/PropertyContainer.as';
const SLOTS = ['头部装备','上装装备','下装装备','手部装备','脚部装备','颈部装备','长枪','手枪','手枪2','刀','手雷'];

function fixture(source) {
    const keys = Object.fromEntries(SLOTS.map(key => [key, key + '数据']));
    const weapons = {长枪:'长枪属性',手枪:'手枪属性',手枪2:'手枪2属性',刀:'刀属性',手雷:'手雷属性'};
    const root = {控制目标:'hero',全局健身HP加成:0,全局健身MP加成:0,全局健身空攻加成:0,
        全局健身防御加成:0,全局健身内力加成:0,经脉HP加成:0,经脉MP加成:0,经脉防御加成:0,经脉内力加成:0,
        根据等级计算值:min => min,敌人函数:{魔法伤害种类:['基础','电','热','冷','波','蚀','毒','冲','人类']}};
    const globals = {_root:root,equipmentKeys:keys,weaponKeys:weapons,
        weaponPrefixKeys:{长枪:'长枪',手枪:'手枪',手枪2:'手枪2',刀:'兵器',手部装备:'空手',手雷:'手雷'},
        removePropertyFunc:{},DodgeHandler:{HIT_RATE_LIMIT:0.01,applyDodgeBonus:(base,bonus) => base + bonus},
        LongGunSubWeaponCore:{refreshRuntimeStats(){}},
        org:{flashNight:{arki:{unit:{Action:{Shoot:{WeaponAmmoRuntime:{ensure(){}}}},PlayerInfoProvider:{invalidateDpsCache(){}}}}}}};
    const names = ['resolveStableBaseStat','resolveTemplateMagicResistance','readGlobalBonus','updateProperty',
        'removePrimaryProperty','removeSecondary1Property','removeSecondary2Property','removeMeleeProperty',
        'removeHandProperty','removeGrenadeProperty','updateProperties','loadEquipmentData'];
    if (source.read(DRESS).text.includes('function computeEquipmentProperties(')) names.push('computeEquipmentProperties');
    const api = source.methods(DRESS, names, globals);
    const t = {_name:'hero',等级:20,hp:600,hp满血值:1000,hp基本满血值:1000,mp:200,mp满血值:500,mp基本满血值:500,
        基本空手攻击力:100,基本防御力:100,体重:50,基础命中率:10,基础韧性系数:1,基础躲闪率:10,
        label:{},area:{_height:136},_yscale:100,攻击模式:'长枪',魔法抗性:{},根据模式重新读取武器加成(){}};
    for (const slot of SLOTS) t[slot + '数据'] = {data:{}};
    for (const key of Object.values(weapons)) t[key] = {};
    t.长枪数据.data.power = 100;
    t.长枪数据.data.capacity = 30;
    t.长枪属性 = t.长枪数据.data;
    t.头部装备数据.data.gunpower = 5;
    return {api, target:t, root, globals};
}

module.exports = function run(source, report, fixtures) {
    if(source.read(DRESS).text.includes('function buildPersistentSnapshot(')) return require('./fixed-source-probes').runtime(source,report,fixtures);
    const f = fixture(source), powers = [];
    for (let i = 0; i < 3; i++) { f.api.updateProperties(f.target); powers.push(f.target.长枪属性.power); }
    report('weapon-power-idempotent', powers, [105,105,105], [105,110,115]);

    const withLoner = fixture(source);
    withLoner.target.hp满血值 = 1150;
    withLoner.target.被动技能 = {独行者:{等级:3,启用:true}};
    withLoner.root.全局健身HP加成 = 10;
    withLoner.api.updateProperties(withLoner.target);
    report('gym-preserves-loner', withLoner.target.hp满血值, 1160, 1010);

    const set = fixture(source);
    set.target.魔法抗性.原体 = 85;
    set.api.updateProperties(set.target);
    report('set-static-resistance', set.target.魔法抗性.原体, 85, undefined);

    const getter = source.fn(CONTAINER, 'function _createComputeFunction(');
    const setter = source.fn(CONTAINER, 'function _createSetterFunction(');
    const compute = source.fn(CONTAINER, 'function _computeFinalValue(');
    const box = {_baseValue:10,_isDirty:true,_cachedFinalValue:NaN,_buffs:[],
        _calculator:{reset(){},calculate:base => base + 22},
        _computeFinalValue:compute,_markDirtyAndInvalidate(){this._isDirty = true;}};
    const managed = fixture(source), live = managed.target;
    Object.defineProperty(live, '伤害加成', {get:getter.call(box),set:setter.call(box),configurable:true});
    live.头部装备数据.data.damage = 10;
    live.buffManager = {syncAllPathBindings(){},getBaseValue:() => box._baseValue,
        setBaseValue:(key,value) => {if (key === '伤害加成') {box._baseValue = value;box._isDirty = true;}}};
    managed.api.updateProperties(live);
    report('managed-compound-write', live.伤害加成, fixtures.managed.damageTarget, 54);

    const defense = fixture(source);
    const defenseBox = {...box,_baseValue:120,_isDirty:true,_cachedFinalValue:NaN,
        _calculator:{reset(){},calculate:base => base - 13}};
    defense.target.基本防御力 = 120;
    Object.defineProperty(defense.target,'防御力',{get:getter.call(defenseBox),set:setter.call(defenseBox),configurable:true});
    defense.target.buffManager = {syncAllPathBindings(){},getBaseValue:() => defenseBox._baseValue,
        setBaseValue:(key,value) => {if (key === '防御力') {defenseBox._baseValue = value;defenseBox._isDirty = true;}}};
    defense.api.updateProperties(defense.target);
    report('managed-defense-zero-add',defense.target.防御力,107,94);

    const legacy = fixture(source);
    legacy.api.updateProperties(legacy.target);legacy.target.man = {};
    const old = {自机:legacy.target,buff倍率:{},buff加算:{魔法抗性:50},buff限时倍率:{},buff限时加算:{},buff限时id:{}};
    const oldGlobals = {_root:legacy.root,桥接属性:{空手攻击力:true,伤害加成:true,防御力:true,韧性系数:true,内力:true,速度:true},
        org:legacy.globals.org};
    const oldFile = 'scripts/类定义/主角模板数值buff.as';
    source.fn(oldFile,'function 初始(',oldGlobals).call(old);
    old.更新 = source.fn(oldFile,'function 更新(',oldGlobals);
    old.更新('魔法抗性');legacy.target.buff = old;
    legacy.api.updateProperties(legacy.target);
    report('legacy-resistance-buff',legacy.target.魔法抗性.热,62,12);

    const settle = source.fn(HEAL, 'function settleHpAfterMaxChange(', {OVERFLOW_CAP_RATIO:0.5});
    report('resource-ordinary', settle(900,1000,800), 800);
    report('resource-existing-overflow', settle(1300,1000,800), 1200);
    report('resource-half-write-recapture-is-unsafe', settle(900,800,800), 900);
};
module.exports.fixture = fixture;
