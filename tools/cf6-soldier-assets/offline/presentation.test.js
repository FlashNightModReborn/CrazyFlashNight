'use strict';
// Production AS2 function bodies with explicit movement/display boundary ports.
// Actual MovieClip timelines, equipment and projectiles have separate native tests.
const assert=require('node:assert/strict');
const test=require('node:test');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {loadFunctions,eraseTypes}=require('./as2-source');
const root=path.resolve(__dirname,'../../..');
const sourceRoot=process.env.CF6_PRESENTATION_SOURCE||root;
const adapter=path.join(sourceRoot,'tools/cf6-soldier-assets/FixedActionAdapter.as');
const factory=path.join(sourceRoot,'scripts/类定义/org/flashNight/arki/bullet/Factory/BulletFactory.as');
function walk({targetX=100,goalX=1100,armed=false,blocked=false}={}) {
    const target={_x:targetX,Z轴坐标:300};
    const context=vm.createContext({Math,_root:{gameworld:{target},Xmin:0,Xmax:3000,Ymin:180,Ymax:520}});
    loadFunctions(context,adapter,['cf6FixedTrack','cf6FixedWalkPose']);
    loadFunctions(context,path.join(root,'tools/cf6-soldier-assets/TacticalAI.as'),['soldierTacticalMove']);
    const motions=[];
    const actor={_x:800,_y:300,Z轴坐标:300,攻击目标:'target',状态:'长枪站立',方向:'右',_xscale:100,myxscale:100,
        跑X速度:16,跑Y速度:8,行走X速度:8,行走Y速度:4,soldierPhase:2,cf6Closing:false,cf6NavStalls:0,
        cf6Observation:{targetValid:true,interrupted:false,controlled:false,visible:true},
        cf6Profile:{roleClass:'ordinary',program:{stopDistance:300,maxDistance:900,lane:24,trigger:'ordinary'}},
        man:{_x:25.6,_xscale:100,cf6Stride:{_totalframes:8,_currentframe:1,gotoAndStop(frame){this._currentframe=frame;}}},cf6StrideStep:0,
        soldierTacticalStats:{blockedMoves:0},soldierClock:100,
        新版人物文字信息:{_xscale:100},
        cf6NavWaypoint(){return {x:goalX,z:300};},soldierEvasionZSign(){return 1;},
        方向改变(direction){this.方向=direction;this._xscale=direction==='左'?-100:100;this.新版人物文字信息._xscale=this._xscale;},
        cf6LegacyState(state){this.状态=state;this.man._x=25.6;this.man._xscale=100;},
        移动(direction,amount){motions.push([direction,amount]);if(blocked && (direction==='左'||direction==='右'))return;
            if(direction==='左')this._x-=amount;else if(direction==='右')this._x+=amount;
            else if(direction==='上')this.Z轴坐标-=amount;else this.Z轴坐标+=amount;this._y=this.Z轴坐标;}
    };
    for(const key of ['cf6FixedTrack','cf6FixedWalkPose','soldierTacticalMove'])actor[key]=context[key];
    actor.cf6FixedTrack(armed);
    return {actor,motions};
}
test('running body follows detours while preserving AI facing and its root transform',()=>{
    for(const side of [-1,1]) {
        const {actor,motions}=walk({targetX:800-side*600,goalX:800+side*300});
        assert.equal(actor.方向,side<0?'右':'左');assert.equal(actor.状态,'长枪跑');
        assert.equal(actor._x,800+side*16);assert.deepEqual(motions,[[side<0?'左':'右',16]]);
        assert.equal(actor._xscale,-side*100);
        assert.equal(actor.新版人物文字信息._xscale,-side*100);
        assert.equal(Math.sign(actor._xscale*actor.man._xscale),side);
        assert.equal(actor.man._x,-25.6,'mirror the pivot with the body');
        actor.cf6NavWaypoint=()=>({x:800-side*300,z:300});
        actor.cf6FixedTrack(false);
        assert.equal(actor.man._xscale,100,'same run timeline restores forward body');
        assert.equal(actor.man._x,25.6);
    }
});
test('backward walking keeps its target-facing pose and original walk speed',()=>{
    for(const side of [-1,1]) {
        const {actor,motions}=walk({targetX:800-side*600,goalX:800+side*80});
        assert.equal(actor.方向,side<0?'右':'左');assert.equal(actor.状态,'长枪行走');
        assert.equal(actor._x,800+side*8);assert.deepEqual(motions,[[side<0?'左':'右',8]]);
        assert.equal(actor.man._xscale,100);assert.equal(actor.man._x,25.6);
    }
});
test('armed movement retains its body and muzzle pose while keeping walk speed',()=>{
    const {actor,motions}=walk({armed:true});
    assert.equal(actor._x,808);assert.equal(actor.状态,'长枪站立');assert.equal(actor.方向,'右');
    assert.deepEqual(motions,[['右',8]]);assert.equal(actor.man.cf6Stride._currentframe,3);
});
test('a blocked detour retains its existing lane escape and movement budgets',()=>{
    const {actor,motions}=walk({blocked:true});
    assert.equal(actor._x,800);assert.equal(actor.Z轴坐标,300);assert.equal(actor.cf6NavStalls,1);
    // A chosen waypoint does not use the independent local skirt fallback.
    assert.deepEqual(motions,[['右',16]]);assert.equal(actor.standardShotMoving,false);
});
function rotation(fields={}) {
    const text=fs.readFileSync(factory,'utf8');
    const start=text.indexOf('        Obj._rotation =');
    const end=text.indexOf('        // 创建子弹实例',start);
    assert(start>0 && end>start,'bounded production rotation block');
    const context={Math,isFinite,Obj:{cf6DamageGroup:{},子弹散射度:7,武器扩散倍率:1},
        zyRatio:undefined,speedX:30,speedY:0,scatteringAngle:13,
        isTransparent:false,isChain:false,isUnitBullet:false,...fields};
    if(fields.Obj)context.Obj={...fields.Obj};
    vm.runInNewContext(eraseTypes(text.slice(start,end)),context);
    return context;
}
test('fixed straight bullets face horizontal flight without changing scatter or velocity inputs',()=>{
    for(const sign of [-1,1]) {
        const c=rotation({speedX:30*sign,scatteringAngle:sign<0?193:13});
        assert.equal(c.Obj._rotation,sign<0?180:0);assert.equal(c.speedX,sign*30);assert.equal(c.speedY,0);
        assert.equal(c.Obj.子弹散射度,7);assert.equal(c.Obj.武器扩散倍率,1);
        assert.equal(c.scatteringAngle,sign<0?193:13);
    }
});
test('unowned, ray, chain, unit and non-horizontal bullets retain their current rotation contract',()=>{
    for(const fields of [{Obj:{}},{isTransparent:true},{isChain:true},{isUnitBullet:true},{speedY:3},{speedX:0}])
        assert.equal(rotation(fields).Obj._rotation,13);
    const c=rotation({zyRatio:1,speedY:3});
    assert.equal(c.Obj._rotation,(Math.atan2(3,30)*180/Math.PI+360)%360);
});
