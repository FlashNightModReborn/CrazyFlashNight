'use strict';

const UNIT = 'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as';
const ENGINE = 'scripts/引擎/引擎_lsy_技能系统.as';
const SKILL = 'scripts/类定义/org/flashNight/arki/skill/SkillLoadoutService.as';

module.exports = function run(source, report, fixtures) {
    if(source.read(ENGINE).text.includes('SkillLoadoutService.flushProjection()')) return require('./fixed-source-probes').skill(source,report,fixtures);
    const root = {限制系统:{limitLevel:0,DisableCompanion:false},难度等级:1,宠物信息:[],佣兵个数限制:0};
    const globals = {_root:root};
    const dress = source.methods('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as',
        ['lonerContribution','applyBasePassiveContribution','setPersistentBase'],globals);
    const basic = source.fn(UNIT, '_root.主角函数.读取基础被动效果 =', {_root:root,
        org:{flashNight:{arki:{unit:{UnitComponent:{Initializer:{DressupInitializer:dress}}}}}}});
    const normal = source.fn(UNIT, '_root.主角函数.读取被动效果 =', {_root:root});
    function hero() {
        return {hp:600,hp满血值:fixtures.loner.baseHp,mp:200,mp满血值:500,
            伤害加成:0,防御力:100,被动技能:{独行者:{等级:3,启用:true}},
            buff:{删除(){}},buffManager:{},man:{},读取被动效果:normal};
    }
    let current = hero();
    const project = source.fn(ENGINE, '_root.技能系统投影Hero =',
        {_root:root,TargetCacheManager:{findHero:() => current}});
    root.主角被动技能 = current.被动技能;
    basic.call(current);
    current.被动技能.独行者.等级 = fixtures.loner.newLevel;
    project();
    report('loner-upgrade', current.hp满血值, fixtures.loner.targetHp, 1150);
    basic.call(current);
    report('loner-naive-reapply', current.hp满血值, fixtures.loner.targetHp, 1350);
    basic.call(current);
    report('loner-repeat', current.hp满血值, fixtures.loner.targetHp, 1550);
    current = hero(); root.主角被动技能 = current.被动技能;
    basic.call(current); current.被动技能.独行者.启用 = false; project();
    report('loner-disable', current.hp满血值, fixtures.loner.baseHp, 1150);

    const api = source.methods(SKILL, ['domainNumber','buildCooldownPlan','applyCooldownPlan']);
    const state = {技能表对象:{移动射击:{CD:fixtures.moveCooldown.baseCD,MP:10}}};
    const originals = {};
    api.applyCooldownPlan(originals, api.buildCooldownPlan(state, originals, '移动射击', 10, 'move'));
    api.applyCooldownPlan(originals, api.buildCooldownPlan(state, originals, '移动射击', 1, 'move'));
    report('move-cooldown-revoke', state.技能表对象.移动射击.CD, fixtures.moveCooldown.baseCD, 1000);
};
