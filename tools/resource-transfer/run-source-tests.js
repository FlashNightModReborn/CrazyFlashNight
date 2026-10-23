'use strict';
// 执行提取的生产函数；Node 证据不代签 AVM1、完整模板或游戏旅程。
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {createSource}=require('../player-stat-refresh/source');
const root=path.resolve(__dirname,'../..'), source=createSource(root), results=[];
const rootObject={服务器:{},控制目标:'hero',玩家信息界面:{},技能点数:10};
const numberPath='scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/ResourceNumber.as';
const number=source.methods(numberPath,['finite','nonnegative','positive','reject','canPayMp','payMp'],{_root:rootObject,trace(){}});
const globals={_root:rootObject,trace(){},ResourceNumber:number};
const healPath='scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/HealApplier.as';
const heal=source.methods(healPath,['requestHeroHpDisplayRefresh','applyHpCapped','applyHpOverflow','applyMpCapped','applyMpOverflow'],
    {...globals,OVERFLOW_CAP_RATIO:0.5,OVERFLOW_INITIAL_EFFICIENCY:1});
const transferPath='scripts/类定义/org/flashNight/arki/scene/PlayerResourceTransfer.as';
const names=['PlayerResourceTransfer','status','sourceRun','sourceContext','fail','retire','identity','pair','capture','commit','abort','bind','matches','project','consume'];
const fields=[...source.read(transferPath).text.matchAll(/(?:private|public) var (\w+):/g)].map(m=>m[1]);
const factory=vm.runInNewContext('(function(){var '+fields.join(',')+';'+
    names.map(n=>'var '+n+'='+source.extract(transferPath,'function '+n+'(')+';').join('\n')+
    'PlayerResourceTransfer();return {'+names.filter(n=>n!=='PlayerResourceTransfer').map(n=>n+':'+n).join(',')+'};})',globals);
function check(name,fn){fn();results.push({name,status:'passed'});}
function identity(stage=0){return {context:{},run:{},world:{},actor:{},slot:'fixture',name:'hero',kind:'player',stage};}
function next(i){return {...i,world:{},actor:{},stage:i.stage+1};}
function actor(i,hp=1000,mp=500,hpMax=1000,mpMax=500){return {_name:'hero',hp,mp,hp满血值:hpMax,mp满血值:mpMax,__resourceActorIdentity:i.actor};}
function ready(value={hp:900,mp:0,hpMax:1000,mpMax:500},src=identity()){
    const t=factory(),ticket={frame:'wuxianguotu_1'};assert.equal(t.capture(ticket,src,value,src.stage+1),true);assert.equal(t.commit(ticket),true);
    const dest=next(src),token=t.bind(dest);assert(token);return {t,ticket,src,dest,token};
}
for(const [label,hp,mp,oldHp,oldMp,newHp,newMp,caps,expectedHp,expectedMp] of [
    ['mp_zero',2700,0,3000,1000,3000,1000,{},2700,0],
    ['overflow',3600,1800,3000,1000,3000,1000,{},3600,1800],
    ['growth',2700,500,3000,1000,4000,2000,{},2700,500],
    ['ordinary_shrink',2700,500,3000,1000,2000,400,{},2000,400],
    ['overflow_no_cap',3600,1800,3000,1000,2000,400,{},3600,1800],
    ['overflow_explicit_cap',3600,1800,3000,1000,2000,400,{hp:2500,mp:900},2500,900],
    ['invalid_caps',3600,1800,3000,1000,2000,400,{hp:NaN,mp:'900'},3600,1800],
    ['cap_below_max',3600,1800,3000,1000,2000,400,{hp:100,mp:100},3600,1800]
]) check(label,()=>{const {t,dest,token}=ready({hp,mp,hpMax:oldHp,mpMax:oldMp}),u=actor(dest,newHp,newMp,newHp,newMp);
    assert.equal(t.consume(token,u,dest,caps),true);assert.deepEqual([u.hp,u.mp],[expectedHp,expectedMp]);
    assert.equal(t.consume(token,u,dest,caps),false);assert.deepEqual([u.hp,u.mp],[expectedHp,expectedMp]);});
const bad=[undefined,null,NaN,Infinity,-Infinity,'5',true,-1];
for(const [index,value] of bad.entries()){
    check('bad_sample_pair_'+index,()=>{const t=factory(),i=identity();assert.equal(t.capture({},i,{hp:500,mp:value,hpMax:1000,mpMax:500},1),false);});
    check('bad_destination_atomic_'+index,()=>{const {t,dest,token}=ready(),u=actor(dest);u.mp=value;assert.equal(t.consume(token,u,dest,{}),false);assert.equal(u.hp,1000);});
    check('bad_heal_amount_'+index,()=>{const u={hp:100,mp:60};assert.equal(heal.applyMpCapped(u,value,100),0);assert.equal(u.mp,60);});
    check('bad_cost_'+index,()=>{const u={hp:100,mp:60};assert.equal(number.payMp(u,value),false);assert.equal(u.mp,60);});
}
for(const key of ['context','run','world','actor','slot','name','kind','stage']) check('consume_identity_'+key,()=>{
    const {t,dest,token}=ready(),u=actor(dest);dest[key]={};assert.equal(t.consume(token,u,dest,{}),false);assert.equal(u.hp,1000);assert.equal(u.mp,500);});
for(const key of ['context','run','slot','name','kind','stage']) check('bind_identity_'+key,()=>{
    const t=factory(),i=identity(),ticket={};t.capture(ticket,i,{hp:500,mp:0,hpMax:1000,mpMax:500},1);t.commit(ticket);
    const d=next(i);d[key]={};assert.equal(t.bind(d),null);});
check('duplicate_cannot_replace',()=>{const t=factory(),i=identity(),tk={frame:'same'},v={hp:500,mp:0,hpMax:1000,mpMax:500};
    assert(t.capture(tk,i,v,1));v.hp=999;assert.equal(t.capture({},identity(),v,1),false);assert.equal(t.commit({frame:'same'}),false);assert(t.commit(tk));
    const d=next(i),token=t.bind(d),u=actor(d);assert.equal(t.consume({},u,d,{}),false);assert(t.consume(token,u,d,{}));assert.equal(u.hp,500);});
check('failed_teardown',()=>{const t=factory(),i=identity(),tk={};t.capture(tk,i,{hp:500,mp:0,hpMax:1000,mpMax:500},1);t.abort(tk,'failed');assert.equal(t.commit(tk),false);assert.equal(t.bind(next(i)),null);});
check('terminal_ticket_not_replayed',()=>{const t=factory(),i=identity(),tk={};const v={hp:500,mp:NaN,hpMax:1000,mpMax:500};assert.equal(t.capture(tk,i,v,1),false);v.mp=0;assert.equal(t.capture(tk,i,v,1),false);assert.equal(t.commit(tk),false);assert.equal(t.capture({},i,v,1),true);});
check('old_abort_cannot_clear_new_candidate',()=>{const t=factory(),i=identity(),first={},second={},v={hp:500,mp:0,hpMax:1000,mpMax:500};assert(t.capture(first,i,v,1));assert(t.abort(first,'cancelled'));assert(t.capture(second,i,v,1));assert.equal(t.abort(first,'late'),false);assert.equal(t.commit(first),false);assert(t.commit(second));const d=next(i),tok=t.bind(d),u=actor(d);assert(t.consume(tok,u,d,{}));assert.equal(u.hp,500);});
check('negative_zero_mp',()=>{const {t,dest,token}=ready({hp:1,mp:-0,hpMax:1000,mpMax:500}),u=actor(dest);assert(t.consume(token,u,dest,{}));assert.equal(u.hp,1);assert(Object.is(u.mp,-0));});
check('lee_zero_max',()=>{const i=identity();i.kind='lee';const {t,dest,token}=ready({hp:333,mp:0,hpMax:500,mpMax:0},i),u=actor(dest,500,0,500,0);assert(t.consume(token,u,dest,{}));assert.deepEqual([u.hp,u.mp],[333,0]);});
check('numeric_healing',()=>{const u={hp:100,mp:60};assert.equal(heal.applyMpCapped(u,5,100),5);assert.equal(u.mp,65);assert.equal(number.payMp(u,0),true);assert.equal(u.mp,65);});
check('dead_healing_is_quiet',()=>{const u={hp:0,mp:60};assert.equal(heal.applyMpCapped(u,5,100),0);assert.equal(u.__resourceFirstFault,undefined);});

// 直接提取真实释放入口，检查许可回调之后的最终写入边界。
const skillPath='scripts/类定义/org/flashNight/arki/unit/Action/Skill/SkillReleaseGuard.as';
const skill=source.methods(skillPath,['normalizeSkillName','resolve','isEquippedSlot'],{ResourceNumber:number,SkillLoadoutService:{root:()=>rootObject,isReleaseAllowed:()=>true}});
rootObject.根据技能名查找主角技能等级=()=>1;rootObject.根据技能名查找全部属性=()=>({});
let effects=0;rootObject.技能函数={释放条件:{默认:()=>true},释放行为:{默认:()=>{effects++;}}};
const org={flashNight:{arki:{
    unit:{Action:{Regeneration:{ResourceNumber:number}}},
    skill:{SkillResourceService:{reject:()=>false}}
}}};
const frame='scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as';
const release=source.fn(frame,'_root.主角函数.释放技能 =',{_root:rootObject,org,SkillReleaseGuard:skill});
const weapon=source.fn(frame,'_root.主角函数.释放主动战技 =',{_root:rootObject,org});
check('skill_permission_poisoned_balance',()=>{effects=0;rootObject.技能函数.释放条件.默认=function(){this.mp=NaN;return true;};const u={hp:100,mp:60};assert.equal(release.call(u,'skill',5,'K'),false);assert.equal(effects,0);assert(Number.isNaN(u.mp));});
check('skill_typed_balance',()=>{effects=0;rootObject.技能函数.释放条件.默认=()=>true;const u={hp:100,mp:'60'};assert.equal(release.call(u,'skill',5,'K'),false);assert.equal(effects,0);assert.equal(u.mp,'60');});
check('skill_normal_payment',()=>{effects=0;const u={hp:100,mp:60};assert.equal(release.call(u,'skill',5,'K'),true);assert.equal(u.mp,55);assert.equal(effects,1);});
check('weapon_permission_poisoned_cost',()=>{effects=0;const slot={消耗hp:0,消耗mp:5,消耗sp:0};slot.战技函数={释放许可判定:()=>{slot.消耗mp=NaN;return true;},释放:()=>effects++};const u={hp:100,mp:60,攻击模式:'兵器',主动战技:{兵器:slot}};
    assert.equal(weapon.call(u),false);assert.deepEqual([u.hp,u.mp,effects],[100,60,0]);});
// AVM1 Key.isDown 不能替换；用明确的 Node 输入端口测试生产门回调的按键映射和受理行为。
const stagePath='scripts/类定义/org/flashNight/arki/scene/StageManager.as';
function exitFixture(){
    const exitRoot={控制目标:'hero',全鼠标控制:false,上键:38,下键:40,左键:37,右键:39,鼠标:{gotoAndPlay(){}}};
    const state={key:null,pressed:false,advanced:0,stopped:0};
    const world={允许通行:true,__identity:{},hero:{hp:4092,area:{},localToGlobal(){}}};
    const door={_parent:world,hitTest:()=>true,gotoAndStop(){state.stopped++;},被点击:false};world.门1=door;exitRoot.gameworld=world;
    const methods=source.methods(stagePath,['bindStageExit'],{_root:exitRoot,Key:{isDown(code){state.key=code;return state.pressed;}},StageReturnFlow:{worldIdentity:w=>w.__identity}});
    const manager={gameworld:world,nextStage(){state.advanced++;return true;}};
    methods.bindStageExit.call(manager,world);
    return {root:exitRoot,world,door,state,manager,call:(direction='右',frame='wuxianguotu_1')=>door.切换场景('出生地',frame,'',direction)};
}
for(const [direction,code] of [['上',38],['下',40],['左',37],['右',39]])for(const pressed of [true,false])
    check('stage_exit_key_'+direction+'_'+pressed,()=>{const f=exitFixture();f.state.pressed=pressed;f.call(direction);assert.equal(f.state.key,code);assert.equal(f.state.advanced,pressed?1:0);assert.equal(f.state.stopped,pressed?1:0);});
check('stage_exit_mouse_requires_click',()=>{const f=exitFixture();f.root.全鼠标控制=true;f.call();assert.equal(f.state.advanced,0);f.door.被点击=true;f.call();assert.equal(f.state.advanced,1);assert.equal(f.state.key,null);});
check('stage_exit_closed_rejected',()=>{const f=exitFixture();f.state.pressed=true;f.world.允许通行=false;f.call();assert.equal(f.state.advanced,0);});
check('stage_exit_replacement_identity_rejected',()=>{const f=exitFixture();f.state.pressed=true;f.world.__identity={};f.call();assert.equal(f.state.advanced,0);});
check('stage_exit_rejected_admission_does_not_stop',()=>{const f=exitFixture();f.state.pressed=true;f.manager.nextStage=()=>{f.state.advanced++;return false;};f.call();assert.equal(f.state.advanced,1);assert.equal(f.state.stopped,0);});
const report={schema:'cf7.resource-transfer.source-tests.v1',evidenceTier:'node-source-extraction',
    boundary:'Production function extraction with memory ports. Not AVM1, native template readiness, compile or game E2E evidence.',
    cases:results.length,passed:results.length,results,sourceEvidence:source.evidence};
const output=process.argv[2];if(output) fs.writeFileSync(path.resolve(output),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({evidenceTier:report.evidenceTier,cases:report.cases,passed:report.passed,output}));
