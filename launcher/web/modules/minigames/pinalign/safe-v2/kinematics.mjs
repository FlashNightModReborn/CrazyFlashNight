/** Deterministic, cumulative-angle kinematics. No rendering or wall-clock state. */
export const TAU = Math.PI * 2;
export const DIGIT_STEP = TAU / 10;
// The two dog faces leave a finite 0.18-radian collision sector. Their mounting
// phase puts that sector BETWEEN the ten valid digit positions, including repeats.
export const DOG_WIDTH = 0.18;
export const DOG_PHASE = DIGIT_STEP / 2;
export const DOG_HALF_PLAY = (TAU - DOG_WIDTH) / 2;
export const DOG_LOW = DOG_PHASE - DOG_HALF_PLAY;
export const DOG_HIGH = DOG_PHASE + DOG_HALF_PLAY;
export const DOOR_RADIANS = 103 * Math.PI / 180;
export const clamp01 = (v) => Math.max(0, Math.min(1, Number(v) || 0));
export const smooth = (v) => { const t = clamp01(v); return t*t*(3-2*t); };
export const windowProgress = (t, lo, hi) => smooth((t-lo)/(hi-lo));
export function wrappedAngle(a) { return ((a + Math.PI) % TAU + TAU) % TAU - Math.PI; }
export function gateAligned(angle, digit, tolerance=0.055) {
  return Math.abs(wrappedAngle(angle + Number(digit) * DIGIT_STEP)) <= tolerance;
}
export function camAligned(angle, tolerance=0.055) { return Math.abs(wrappedAngle(angle)) <= tolerance; }
export function validateCode(code) {
  const s=String(code);
  if (s.length!==3 || !/^[1-9][0-9]{2}$/.test(s)) throw new RangeError('模型密码须为100–999的三个十进制数字');
  return s;
}

/** Advance one monotonic segment, spindle -> near -> middle -> far. */
export function followDogs(dialAngle, previousWheels) {
  const next=previousWheels.slice();
  let parent=dialAngle;
  for (let i=2;i>=0;i--) {
    const relative=parent-next[i];
    if (relative>DOG_HIGH) next[i]=parent-DOG_HIGH;
    else if (relative<DOG_LOW) next[i]=parent-DOG_LOW;
    parent=next[i];
  }
  return next;
}

/**
 * Construct the visible character-operated recipe, not an extra player puzzle.
 * Angular state is never reduced modulo one revolution. Gate offsets on the
 * keyed wheel rims encode hundreds/tens/units; each has ten possible positions.
 */
export function createDialProgram(code) {
  const s=validateCode(code), digits=[...s].map(Number);
  const target=digits.map(d => -d*DIGIT_STEP);
  const far=target[0] + 5*TAU;
  const middle=target[1] + Math.floor((far+DOG_HIGH-target[1])/TAU)*TAU;
  const near=target[2] + Math.ceil((middle+DOG_LOW-target[2])/TAU)*TAU;
  const cam=Math.floor((near+DOG_HIGH)/TAU)*TAU;
  const targets=[far+3*DOG_HIGH,middle+2*DOG_LOW,near+DOG_HIGH,cam];
  const labels=['主轴逐级带动三轮','反向搭接两轮','再次反向搭接末轮','回拨凸轮让出栅杆'];
  let state={dialAngle:0,wheelAngles:[0,0,0]}, total=0;
  const segments=[];
  targets.forEach((dialAngle,i)=>{
    const next={dialAngle,wheelAngles:followDogs(dialAngle,state.wheelAngles)};
    const distance=Math.abs(dialAngle-state.dialAngle);
    segments.push({from:state,to:next,distance,label:labels[i],direction:Math.sign(dialAngle-state.dialAngle),drivenWheels:3-i,start:total});
    total+=distance;
    state=next;
  });
  for(const seg of segments){seg.start/=total;seg.end=seg.start+seg.distance/total;}
  segments[segments.length-1].end=1;
  if (!state.wheelAngles.every((v,i)=>gateAligned(v,digits[i],1e-7)) || !camAligned(state.dialAngle,1e-7)) {
    throw new Error(`不可解拨轮程序: ${s}`);
  }
  return {code:s,digits,segments,initial:{dialAngle:0,wheelAngles:[0,0,0]},final:state,totalAngleTravel:total};
}

export function sampleDialProgram(program,t) {
  const u=clamp01(t);
  const seg=program.segments.find(s=>u<=s.end+1e-12) || program.segments.at(-1);
  const f=smooth((u-seg.start)/(seg.end-seg.start));
  const dialAngle=seg.from.dialAngle+(seg.to.dialAngle-seg.from.dialAngle)*f;
  const wheelAngles=followDogs(dialAngle,seg.from.wheelAngles);
  const gates=wheelAngles.map((v,i)=>gateAligned(v,program.digits[i]));
  return {dialAngle,wheelAngles,code:program.code,direction:seg.direction,drivenWheels:seg.drivenWheels,label:seg.label,gates,camGate:camAligned(dialAngle)};
}

const programCache=new Map();
function cachedProgram(code){const s=validateCode(code);if(!programCache.has(s))programCache.set(s,createDialProgram(s));return programCache.get(s);}
/** t is normalized; caller selects quick (<=1 s) or deliberate demonstration. */
export function sampleUnlock(route,code,t) {
  const u=clamp01(t), isTool=route==='tool'||route==='tools';
  const p=cachedProgram(code);
  const dial=isTool ? {dialAngle:0,wheelAngles:[0,0,0],code:p.code,label:'旁路牵引小锁舌'} : sampleDialProgram(p,clamp01(u/.51));
  const fence=isTool ? 0 : windowProgress(u,.515,.62);
  const latch=isTool ? 1 : fence;
  const handle=windowProgress(u,isTool?0:.685,isTool?.3:.815);
  const bolts=handle;
  const door=windowProgress(u,isTool?.3:.82,1);
  let label=dial.label;
  if(fence>0 && latch<.999)label='轮槽与凸轮让位，整体栅杆下落';
  if(handle>0 && door===0)label='小锁舌让位，把手收回粗门闩';
  if(door>0)label='门闩已收回，右侧铰链外开';
  if(u===1)label='柜门开启';
  return {...dial,a:isTool?1:0,b:isTool?1:0,fence,latch,handle,bolts,door,label,stage:label,route:isTool?'tool':'password',tool:null,activeStage:null};
}

/** Independent invariant checker for UI tests and exported trajectory reports. */
export function auditPose(pose,code=pose.code) {
  const digits=[...validateCode(code)].map(Number), issues=[];
  const gates=(pose.wheelAngles||[0,0,0]).map((v,i)=>gateAligned(v,digits[i]));
  if((pose.fence||0)>1e-6 && (!gates.every(Boolean)||!camAligned(pose.dialAngle||0)))issues.push('fence-without-aligned-gates');
  if((pose.b||0)>1e-6 && (pose.a||0)<.999)issues.push('b-without-a');
  if((pose.latch||0)>1e-6 && (pose.fence||0)<=0 && (pose.b||0)<=0)issues.push('latch-without-fence-or-bypass');
  if((pose.handle||0)>1e-6 && (pose.latch||0)<.999)issues.push('handle-before-latch');
  if((pose.door||0)>1e-6 && (pose.bolts||0)<.999)issues.push('door-before-bolts');
  for(const k of ['a','b','fence','latch','handle','bolts','door'])if(pose[k]!=null && (!Number.isFinite(pose[k])||pose[k]<0||pose[k]>1))issues.push(`${k}-out-of-range`);
  return {ok:issues.length===0,issues,gates,camGate:camAligned(pose.dialAngle||0)};
}
