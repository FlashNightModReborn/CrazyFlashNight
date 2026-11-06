'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {createSource}=require('../player-stat-refresh/source');
const root=path.resolve(__dirname,'../..'),source=createSource(root);
const baseline=process.argv.includes('--baseline');
const corePath='scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootCore.as';
const firePath='scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponFireCore.as';
const results=[];
function fixture(marker){
    const counts={shots:0,events:0,removed:0,ammoChecks:0,projectiles:0};
    const params={shootingStateName:'主手射击中',actionFlagName:'动作A',prefix:'',bulletAttrKeys:['子弹属性'],
        shootBulletAttrKey:'子弹属性',taskName:'keepshooting',playerBulletField:'子弹数',gunPath:'枪.枪.装扮.枪口位置'};
    const unit={_name:'hero',攻击模式:'长枪',动作A:true,主手射击中:true,keepshooting:7,
        长枪:{name:'fixture-gun',value:{shot:0}},长枪弹匣容量:30,长枪属性:{interval:50},__pendingFireInterval:0};
    unit.man={射击许可标签:true,是否单发:false,子弹属性:{ammoCost:1},枪:{枪:{装扮:{枪口位置:{}}}},gotoAndPlay(){}};
    unit.dispatcher={publish(name){counts.events++;if(name==='processShot')unit.长枪.value.shot++;}};
    unit.长枪射击=()=>{counts.shots++;unit.长枪.value.shot++;return true;};
    if(marker)unit[marker]={};
    const rootPort={控制目标:'hero',暂停:false,子弹区域shoot传递(){counts.projectiles++;}};
    const corePort={_paramsCache:{1:{...params,gunPathArray:params.gunPath.split('.'),baseShootFrame:'射击'}},setLaneRecoil(){},armRateLimit(){},scheduleRecoil(){},
        removeStoredTask(core,key){counts.removed++;delete core[key];},
        cleanupLane(core,p){counts.removed++;delete core[p.taskName];core[p.shootingStateName]=false;}};
    if(source.read(corePath).text.includes('function isPresentationControlled('))
        corePort.isPresentationControlled=source.fn(corePath,'function isPresentationControlled(');
    const globals={_root:rootPort,ShootCore:corePort,_paramsCache:corePort._paramsCache,Dictionary:{getStaticUID:()=>1},
        TargetCacheManager:{findHero:()=>unit},WeaponAmmoRuntime:{ensure(){counts.ammoChecks++;},ghostMultiplier:()=>1},
        WeaponSpreadRuntime:{applyShot(){}},RayVisualBridge:{captureShot(){}}};
    return {counts,params,unit,globals};
}
const markers=[undefined,'__cf6VehicleOwner','__cf6TraversalOwner','__cf6ElevatorPoseOwner'];
for(const marker of markers){
    const f=fixture(marker),run=source.fn(corePath,'function continuousShoot(',f.globals);
    const value=run(f.unit,'长枪',50,f.params,50),denied=!!marker&&!baseline;
    assert.equal(value,!denied);assert.equal(f.counts.shots,denied?0:1);
    if(denied){assert.equal(f.unit.keepshooting,undefined);assert.equal(f.unit.主手射击中,false);}
    results.push({path:'continuousShoot',marker:marker||'none',shots:f.counts.shots,
        result:marker&&baseline?'ownership-leak-observed':'expected'});
    if(marker&&baseline){
        f.unit.动作A=false;run(f.unit,'长枪',50,f.params,50);
        assert.equal(f.counts.shots,1);assert.equal(f.unit.keepshooting,undefined);
    }
}
for(const marker of markers){
    const f=fixture(marker),run=source.fn(firePath,'function executeShot(',f.globals);
    const value=run(f.unit,'长枪',null,{子弹散射度:1,站立子弹散射度:1},null),denied=!!marker&&!baseline;
    assert.equal(value,!denied);assert.equal(f.counts.projectiles,denied?0:1);
    assert.equal(f.unit.长枪.value.shot,denied?0:1);
    assert.equal(f.counts.ammoChecks,denied?0:1);
    results.push({path:'executeShot',marker:marker||'none',projectiles:f.counts.projectiles,
        result:marker&&baseline?'ownership-leak-observed':'expected'});
}
const report={schema:'cf6-hero-fire-isolation-source.v1',mode:baseline?'baseline':'fixed',
    evidenceTier:'node-source-extraction',cases:results.length,results,sourceEvidence:source.evidence,
    limits:'Dictionary, dispatcher, shot and task-removal ports are explicit memory substitutes. This isolates the missing firing ownership check, not the live producer of a stale flag; native scheduling and car phase coverage are separate.'};
const index=process.argv.indexOf('--output');
if(index>=0)fs.writeFileSync(path.resolve(process.argv[index+1]),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({mode:report.mode,cases:results.length,ownershipLeaksObserved:results.filter(r=>r.result==='ownership-leak-observed').length}));
