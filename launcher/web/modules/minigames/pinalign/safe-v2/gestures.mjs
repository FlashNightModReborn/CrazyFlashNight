/** Screen-space gesture projection. Progress depends only on displacement.
 * A captured path/camera is immutable during a drag. Arc paths come from the
 * real mechanism's contact trajectory, not a random button sequence. */
const clamp=x=>Math.max(0,Math.min(1,x));
const finitePoint=p=>p&&Number.isFinite(p.x)&&Number.isFinite(p.y)&&Number.isFinite(p.p);
export function captureGesture({kind='linear',direction='right',path=[],x,y,distance=52,tolerance=28}){
 if(!Number.isFinite(x)||!Number.isFinite(y))throw new TypeError('Invalid pointer origin');
 if(!Number.isFinite(tolerance)||tolerance<0)throw new TypeError('Invalid gesture tolerance');
 if(kind==='arc'){
  if(path.length<2||!path.every(finitePoint)||path[0].p!==0||path.at(-1).p!==1)throw new TypeError('Arc requires a finite full contact path');
  let length=0;
  for(let i=1;i<path.length;i++){if(path[i].p<=path[i-1].p)throw new RangeError('Arc progress must increase');const segment=Math.hypot(path[i].x-path[i-1].x,path[i].y-path[i-1].y);if(!Number.isFinite(segment)||segment===0)throw new RangeError('Arc segments must have finite nonzero length');length+=segment;}
  if(length<8)throw new RangeError('Arc is too small to manipulate');
  return {kind,x,y,path:path.map(p=>({...p})),length,tolerance:Math.max(tolerance,Math.min(56,length*.65))};
 }
 const vectors={right:[1,0],up:[0,-1],left:[-1,0],down:[0,1]};
 if(!vectors[direction]||!Number.isFinite(distance)||!(distance>0))throw new TypeError('Invalid linear gesture');
 return {kind:'linear',x,y,vector:vectors[direction],distance,tolerance};
}
export function projectGesture(gesture,x,y){
 if(!Number.isFinite(x)||!Number.isFinite(y))return {progress:0,valid:false,reason:'nonfinite'};
 const dx=x-gesture.x,dy=y-gesture.y;
 if(gesture.kind==='linear'){
  const [vx,vy]=gesture.vector,along=dx*vx+dy*vy,across=Math.abs(dx*vy-dy*vx);
  if(along<-10)return {progress:0,valid:false,reason:'direction',along,across};
  const offLine=across>gesture.tolerance&&across>Math.abs(along)*1.25;
  const valid=!offLine;
  return {progress:valid?clamp(along/gesture.distance):0,valid,reason:valid?'displacement':'off_line',along,across};
 }
 const path=gesture.path,origin=path[0],px=origin.x+dx,py=origin.y+dy;
 const first=path[1],tx=first.x-origin.x,ty=first.y-origin.y,len=Math.hypot(tx,ty);
 const tangent=(dx*tx+dy*ty)/len;
 if(tangent < -Math.min(12,gesture.length*.32))return {progress:0,valid:false,reason:'direction',tangent};
 let closest=Infinity,progress=0;
 for(let i=1;i<path.length;i++){
  const a=path[i-1],b=path[i],sx=b.x-a.x,sy=b.y-a.y,l2=sx*sx+sy*sy;
  const t=l2?clamp(((px-a.x)*sx+(py-a.y)*sy)/l2):0;
  const distance=Math.hypot(px-a.x-t*sx,py-a.y-t*sy);
  if(distance<closest){closest=distance;progress=a.p+(b.p-a.p)*t;}
 }
 const effectiveTolerance=(progress>=.85&&tangent>=0)?gesture.tolerance*2.8:gesture.tolerance;
 const valid=closest<=effectiveTolerance;
 return {progress:valid?clamp(progress):0,valid,reason:valid?'contact_arc':'off_arc',distance:closest,tangent};
}

/** Disjoint target circles: nearby structures never share a forgiving region.
 * The gap is deliberate; selected-tool identity must not redirect a wrong hit. */
export function separateHitRadii(a,b,maxRadius=38,gap=8){
 const radius=Math.min(maxRadius,Math.max(0,(Math.hypot(a.x-b.x,a.y-b.y)-gap)/2));
 return {a:radius,b:radius,gap};
}
