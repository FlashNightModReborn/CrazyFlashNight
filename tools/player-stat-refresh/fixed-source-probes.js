'use strict';
// Current source functions plus explicit in-memory boundary ports. These probes
// are not AVM1, a BuffManager implementation, a lifecycle or a Host journey.
const DRESS='scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as';
const OLD='scripts/类定义/主角模板数值buff.as';
const HEAL='scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/HealApplier.as';
function fixture(source) {
    const f=require('./persistent-source-probe').fixture(source);
    f.target.被动技能={独行者:{等级:0,启用:false}};return f;
}
function project(f,passive) {
    const record=f.api.buildPersistentSnapshot(f.target,passive);
    f.api.applyPersistentSnapshot(f.target,record);return record;
}
function setLive(t,key,value) {
    const dot=key.indexOf('.');
    if(dot<0)t[key]=value;else t[key.slice(0,dot)][key.slice(dot+1)]=value;
}
function managedPort(t) {
    const base={},effects=new Map();
    function recalculate(key) {
        if(base[key]===undefined)return;
        let value=base[key];for(const b of effects.values())if(b.key===key)value+=b.value;
        setLive(t,key,value);
    }
    return {setBaseValue(key,value){base[key]=value;recalculate(key);},getBaseValue:key=>base[key],
        syncAllPathBindings(){},addBuff(buff,id){effects.set(id,buff);},removeBuff(id){effects.delete(id);},
        update(){for(const key of Object.keys(base))recalculate(key);},base,effects};
}
exports.runtime=function(source,report) {
    const f=fixture(source),values=[];
    for(let i=0;i<3;i++){project(f);values.push(f.target.长枪属性.power);}
    report('weapon-power-idempotent',values,[105,105,105]);
    f.target.被动技能={独行者:{等级:3,启用:true}};f.root.全局健身HP加成=10;project(f);
    report('gym-preserves-loner',f.target.hp满血值,1160);
    const set=fixture(source);
    set.target.__setEffectController={staticContributions:[{group:{status:'committed'},contribution:{attribute:'原体',baseIfMissing:10,value:75}}]};
    project(set);report('set-static-resistance',set.target.魔法抗性.原体,85);
    const managed=fixture(source),t=managed.target,m=managedPort(t);t.buffManager=m;
    t.__persistentEquipmentInputV1.slots.头部装备.data.damage=10;
    m.addBuff({key:'伤害加成',value:22},'damage');m.addBuff({key:'防御力',value:-13},'defense');
    t.基本防御力=120;
    for(let i=0;i<3;i++)project(managed);
    report('managed-compound-write-port',t.伤害加成,32);
    report('managed-defense-zero-add-port',t.防御力,107);
    const old=fixture(source);old.target.buff={buff倍率:{},buff加算:{魔法抗性:50},buff限时倍率:{},buff限时加算:{}};
    const api=source.methods(OLD,['buildPersistentRebase','acceptPersistentRebase']);
    Object.assign(old.target.buff,api);project(old);
    report('legacy-resistance-buff',old.target.魔法抗性.热,62);
    const settle=source.fn(HEAL,'function settleHpAfterMaxChange(',{OVERFLOW_CAP_RATIO:0.5});
    report('resource-ordinary',settle(900,1000,800),800);
    report('resource-existing-overflow',settle(1300,1000,800),1200);
    report('resource-half-write-recapture-is-unsafe',settle(900,800,800),900);
};
exports.skill=function(source,report,fixtures) {
    const f=fixture(source),t=f.target;
    t.被动技能=f.root.主角被动技能={独行者:{等级:3,启用:true},枪械师:{等级:0,启用:false},移动射击:{启用:false}};
    t.buff.buff加算={};
    project(f);let mask=0;
    const port={contextToken:()=>port,invalidate(value){mask|=value;},flush(){project(f,(mask&2)?f.root.主角被动技能:undefined);mask=0;return {status:'applied',reason:''};}};
    const globals={_testRoot:null,_testProjection:undefined,_projectionStatus:null,
        org:{flashNight:{arki:{unit:{PlayerStatRefreshCoordinator:{production:()=>port}}}}}};
    const skills=source.methods('scripts/类定义/org/flashNight/arki/skill/SkillLoadoutService.as',['projectSkills'],globals);
    const bridge=source.fn('scripts/引擎/引擎_lsy_技能系统.as','_root.技能系统投影Hero =',
        {SkillLoadoutService:{flushProjection:()=>skills.projectSkills(0)}});
    t.被动技能.独行者.等级=4;
    const committed=skills.projectSkills(2);if(committed.status!=='applied')throw new Error(JSON.stringify(committed));bridge();
    report('loner-upgrade',t.hp满血值,fixtures.loner.targetHp);
    const basic=source.fn('scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as','_root.主角函数.读取基础被动效果 =',
        {org:{flashNight:{arki:{unit:{UnitComponent:{Initializer:{DressupInitializer:f.api}}}}}}});
    const passive=source.methods(DRESS,['applyBasePassiveContribution','lonerContribution','setPersistentBase'],f.globals);
    f.api.applyBasePassiveContribution=passive.applyBasePassiveContribution;
    basic.call(t);report('loner-naive-reapply',t.hp满血值,1200);
    basic.call(t);report('loner-repeat',t.hp满血值,1200);
    t.被动技能.独行者.启用=false;skills.projectSkills(2);report('loner-disable',t.hp满血值,1000);
    const cooldown=source.methods('scripts/类定义/org/flashNight/arki/skill/SkillLoadoutService.as',['domainNumber','buildCooldownPlan','applyCooldownPlan']);
    const state={技能表对象:{移动射击:{CD:fixtures.moveCooldown.baseCD,MP:10}}},originals={};
    cooldown.applyCooldownPlan(originals,cooldown.buildCooldownPlan(state,originals,'移动射击',10,'move'));
    cooldown.applyCooldownPlan(originals,cooldown.buildCooldownPlan(state,originals,'移动射击',1,'move'));
    report('move-cooldown-revoke',state.技能表对象.移动射击.CD,fixtures.moveCooldown.baseCD);
};
exports.morph=function(source,report,item) {
    const long=item(source,'data/items/武器_刀_长柄.xml','烬灭裁决');
    const dual=item(source,'data/items/武器_刀_双刀.xml','烬灭裁决双刀');
    const f=fixture(source),t=f.target;
    t.__playerStatBody={};t.刀.name='烬灭裁决';t.刀.value.长柄形态=true;
    const record=t.__persistentEquipmentInputV1.slots.刀;
    record.signature=f.globals.RuntimeEquipmentProjection.numericSourceSignature(t.刀);record.data=long;
    record.forms={'烬灭裁决':long,'烬灭裁决双刀':dual};
    t.被动技能={独行者:{等级:3,启用:true}};f.root.全局健身HP加成=200;
    t.装载主动战技=()=>{};f.root.装备引用配置={刷新所有装扮(){}};
    const dress={requestPersistentRefresh:()=>project(f)};
    const apply=source.fn('scripts/逻辑/装备函数/烬灭裁决.as','_root.装备生命周期函数.烬灭裁决_应用形态 =',
        {_root:f.root,org:{flashNight:{arki:{unit:{UnitComponent:{Initializer:{DressupInitializer:dress}}}}}}});
    project(f);const powers=[t.刀属性.power],ref={自机:t,装备类型:'刀',是否为主角:false};
    apply(ref,false);powers.push(t.刀属性.power);apply(ref,false);powers.push(t.刀属性.power);
    report('morph-same-mode',powers,[565,565,565]);report('morph-build-contribution',t.hp满血值,1550);
    const rhino=fixture(source),unit=rhino.target;unit.基本空手攻击力=500;
    unit.__persistentEquipmentInputV1.slots.刀.data.power=80;project(rhino);
    const manager=managedPort(unit);unit.buffManager=manager;project(rhino);
    const helpers=source.methods(DRESS,['beginBlackRhinoTransfer','endBlackRhinoTransfer'],rhino.globals);
    rhino.globals.org.flashNight.arki.component={Buff:{PodBuff:function(key,type,value){this.key=key;this.value=value;}}};
    const names={头部装备:'黑犀头甲',上装装备:'黑犀胸甲',手部装备:'黑犀手甲',下装装备:'黑犀腿甲',脚部装备:'黑犀鞋'};
    rhino.root.控制目标=unit._name;rhino.root.物品栏={装备栏:{getNameString:key=>names[key]}};
    rhino.root.发布消息=()=>{};rhino.root.战技路由={战技标签跳转_旧(){}};
    const global={_root:rhino.root,EffectSystem:{Effect(){}},org:{flashNight:{arki:{unit:{UnitComponent:{Initializer:{DressupInitializer:helpers}}}}}}};
    const path='scripts/逻辑/单位函数/单位函数_雾人_aka_fs_主动战技.as';
    const begin=source.fn(path,['_root.主动战技函数.兵器.狂瀑扎 =','释放: function'],global,true);
    const end=source.fn(path,['_root.主动战技函数.空手.狂瀑顶 =','释放: function'],global,true);
    begin(unit);project(rhino);report('rhino-active-pair-port',[unit.空手攻击力,unit.刀属性.power],[100,480]);
    end(unit);report('rhino-paired-transfer',[unit.空手攻击力,unit.刀属性.power],[500,80]);
};
