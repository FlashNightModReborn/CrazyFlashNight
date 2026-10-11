// DOM/WebGL-independent state, camera and gesture rules used by the scene.
export const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
export const initialState=()=>({mode:'overview',selected:null,disc:null,drawer:false,yaw:0,pitch:.23,zoom:1,objectYaw:0,objectPitch:0,epoch:0});
export function reduce(s,a){
 switch(a.type){
 case 'HOME':return {...initialState(),epoch:s.epoch+1};
 case 'SELECT':return {...s,mode:a.id==='crazy-flasher'?'collection':'inspecting',selected:a.id,disc:null,drawer:false,objectYaw:0,objectPitch:0,epoch:s.epoch+1};
 case 'DISC':return s.selected==='crazy-flasher'&&/^cf[1-6]$/.test(a.id)?{...s,mode:'inspecting',disc:a.id,objectYaw:0,objectPitch:0,epoch:s.epoch+1}:s;
 case 'RETURN':return {...s,mode:'overview',selected:null,disc:null,drawer:false,objectYaw:0,objectPitch:0,epoch:s.epoch+1};
 case 'DRAWER':return {...s,mode:a.open?'drawer':'overview',drawer:!!a.open,selected:null,disc:null,objectYaw:0,objectPitch:0,epoch:s.epoch+1};
 case 'ORBIT':return {...s,yaw:clamp(s.yaw+a.dx,-.48,.48),pitch:clamp(s.pitch+a.dy,.06,.48)};
 case 'ROTATE':return {...s,objectYaw:s.objectYaw+a.dx,objectPitch:clamp(s.objectPitch+a.dy,-.8,.8)};
 case 'ZOOM':return {...s,zoom:clamp(s.zoom*a.factor,.75,2.5)};
 default:return s;
 }
}
export function fitSpan(points,aspect,padding=1.14){if(!points.length||!(aspect>0))return 1;const xs=points.map(p=>p.x),ys=points.map(p=>p.y);return Math.max(Math.max(...ys)-Math.min(...ys),(Math.max(...xs)-Math.min(...xs))/aspect,.01)*padding;}
export function gestureMoved(start,p,threshold=6){return Math.hypot(p.x-start.x,p.y-start.y)>threshold;}
export const ease=t=>1-Math.pow(1-clamp(t,0,1),3);
export function validCompletion(currentEpoch,startedEpoch,disposed){return !disposed&&currentEpoch===startedEpoch;}
