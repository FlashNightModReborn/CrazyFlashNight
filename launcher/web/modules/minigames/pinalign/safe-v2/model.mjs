import * as THREE from '../vendor/three.module.js';
import {clamp01, DIGIT_STEP, DOOR_RADIANS, DOG_PHASE, DOG_WIDTH, auditPose, validateCode} from './kinematics.mjs';

/** All dimensions below are editable model units in an illustrative scale.
 * X: screen-right; Y: up; Z: outward from the CLOSED front. No imported black box.
 */
export const SAFE_DIMENSIONS = Object.freeze({width:2.6,height:2.75,depth:1.45,hinge:[1.18,0,.80],doorFront:.88,doorBack:.27,doorAngle:DOOR_RADIANS});
export const PORT_POSITIONS = Object.freeze({a:[-.68,-.43,.94],b:[-.68,-.86,.94]});
export const SERVICE_VIEW = Object.freeze({center:[-.58,-.645,.85],width:1.16,height:1.09,direction:[-.15,.12,1],fov:36,margin:1.15});
const DIAL=[-.43,.40], HANDLE=[.30,-.20], PI=Math.PI;
const v3=(p)=>new THREE.Vector3(...p);

function roundedRect(w,h,r=.03) {
  const s=new THREE.Shape(),x=-w/2,y=-h/2;
  s.moveTo(x+r,y);s.lineTo(x+w-r,y);s.quadraticCurveTo(x+w,y,x+w,y+r);
  s.lineTo(x+w,y+h-r);s.quadraticCurveTo(x+w,y+h,x+w-r,y+h);
  s.lineTo(x+r,y+h);s.quadraticCurveTo(x,y+h,x,y+h-r);
  s.lineTo(x,y+r);s.quadraticCurveTo(x,y,x+r,y);s.userData={roundedRectangle:true};return s;
}
function rectHole(x,y,w,h) {
  const p=new THREE.Path();p.moveTo(x-w/2,y-h/2);p.lineTo(x-w/2,y+h/2);p.lineTo(x+w/2,y+h/2);p.lineTo(x+w/2,y-h/2);p.closePath();return p;
}
function circleHole(x,y,r){const p=new THREE.Path();p.absarc(x,y,r,0,PI*2,true);return p;}
function serviceOpening(){
  const p=new THREE.Path();
  // One continuous service cavity. The step avoids the original left handle arm.
  p.moveTo(-.974,-1.068);p.lineTo(-.974,-.127);p.lineTo(-.386,-.127);
  p.lineTo(-.386,-.349);p.lineTo(-.170,-.349);p.lineTo(-.170,-1.068);p.closePath();return p;
}
function extruded(shape,d,bevel=.008){return new THREE.ExtrudeGeometry(shape,{depth:d,bevelEnabled:bevel>0,bevelSize:bevel,bevelThickness:bevel,bevelSegments:1,curveSegments:shape.userData?.roundedRectangle?5:24,steps:1});}
function gateWheelGeometry(r=.335,depth=.058){
  const s=new THREE.Shape(),d=.185;
  s.absarc(0,0,r,PI/2-d,PI/2+d,true);
  s.lineTo(-Math.sin(d)*r,r-.105);s.lineTo(Math.sin(d)*r,r-.105);s.closePath();
  s.holes.push(circleHole(0,0,.057));
  // Three open sectors keep the keyed hub and far wheels inspectable in section.
  for(let i=0;i<3;i++){
    const a=(i*2*PI/3)+.35,p=new THREE.Path(),ri=.106,ro=.23,span=.46;
    p.moveTo(Math.cos(a-span)*ri,Math.sin(a-span)*ri);
    p.absarc(0,0,ri,a-span,a+span,false);
    p.lineTo(Math.cos(a+span)*ro,Math.sin(a+span)*ro);
    p.absarc(0,0,ro,a+span,a-span,true);p.closePath();s.holes.push(p);
  }
  return extruded(s,depth,.003);
}

export function createSafeModel() {
  const root=new THREE.Group();root.name='CF7_Field_Safe_Procedural';
  const parts={},ownedTextures=new Set(),allMaterials=new Set(),cutPanels=[],normalOnly=[];
  const mat=(name,color,metalness=.6,roughness=.55)=>{const m=new THREE.MeshStandardMaterial({color,metalness,roughness});m.name=name;allMaterials.add(m);return m;};
  const M={
    paint:mat('灰蓝烤漆',0x29323e,.35,.77),face:mat('门面灰蓝漆',0x343f4d,.38,.69),
    edge:mat('切削钢边',0x667784,.78,.40),steel:mat('机构钢',0x7a8b96,.79,.37),
    dark:mat('氧化钢',0x242d33,.65,.62),black:mat('门封橡胶',0x111820,.06,.90),
    inside:mat('内壁',0x29343e,.36,.76),brass:mat('低光黄铜',0x9e9069,.70,.46),
    bronze:mat('烧结铜',0x786b50,.66,.53),cream:mat('象牙刻度',0xd9d4bd,.18,.68),
    orange:mat('楔具防滑柄',0xb16d36,.12,.75),blue:mat('钩具防滑柄',0x4d7b8a,.15,.68),
    cable:mat('钢索',0x59676c,.80,.51),deep:mat('暗孔内衬',0x10191f,.3,.85)
  };
  function mesh(g,m,parent=root,name){const o=new THREE.Mesh(g,m);o.castShadow=true;o.receiveShadow=true;if(name){o.name=name;parts[name]=o;}parent.add(o);return o;}
  function group(name,parent=root){const o=new THREE.Group();o.name=name;parts[name]=o;parent.add(o);return o;}
  function box(w,h,d,x,y,z,m=M.steel,parent=root,name,r=.015){const o=mesh(extruded(roundedRect(w,h,Math.min(r,w/3,h/3)),d,Math.min(.006,d*.12)),m,parent,name);o.position.set(x,y,z-d/2);return o;}
  function cyl(r,d,x,y,z,m=M.steel,parent=root,name,axis='z',segments=40){const o=mesh(new THREE.CylinderGeometry(r,r,d,segments,1,false),m,parent,name);if(axis==='z')o.rotation.x=PI/2;else if(axis==='x')o.rotation.z=PI/2;o.position.set(x,y,z);return o;}
  function ring(ro,ri,d,x,y,z,m=M.steel,parent=root,name){const s=new THREE.Shape();s.absarc(0,0,ro,0,PI*2,false);s.holes.push(circleHole(0,0,ri));const g=extruded(s,d,.002);g.translate(0,0,-d/2);const o=mesh(g,m,parent,name);o.position.set(x,y,z);return o;}
  function stud(x,y,z,parent=root,r=.023){cyl(r,.023,x,y,z,M.dark,parent,null,'z',8);const sl=box(r*1.05,.005,.004,x,y,z+.014,M.edge,parent,null,.001);sl.rotation.z=.5;}
  function rod(a,b,r=.019,m=M.steel,parent=root,name){const o=mesh(new THREE.CylinderGeometry(r,r,1,12),m,parent,name);setRod(o,a,b);return o;}
  function setRod(o,a,b){const av=v3(a),bv=v3(b),dv=bv.sub(av);o.position.copy(av).addScaledVector(dv,.5);o.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),dv.clone().normalize());o.scale.set(1,dv.length(),1);}
  function textPlane(text,w,h,x,y,z,parent,color='#ded9c6',size=80){
    if(typeof document==='undefined')return null;
    const c=document.createElement('canvas');c.width=Math.ceil(w/h*128);c.height=128;const cx=c.getContext('2d');
    cx.clearRect(0,0,c.width,c.height);cx.fillStyle=color;cx.textAlign='center';cx.textBaseline='middle';cx.font=`600 ${size}px ui-monospace, monospace`;cx.fillText(text,c.width/2,65);
    const t=new THREE.CanvasTexture(c);t.colorSpace=THREE.SRGBColorSpace;ownedTextures.add(t);
    const m=new THREE.MeshBasicMaterial({map:t,transparent:true,depthWrite:false,side:THREE.DoubleSide});allMaterials.add(m);
    const o=mesh(new THREE.PlaneGeometry(w,h),m,parent);o.position.set(x,y,z);o.castShadow=false;o.userData.ownedLabel=true;return o;
  }
  function outlineRect(w,h,x,y,z,parent,m=M.edge){
    box(w,.014,.012,x,y+h/2,z,m,parent);box(w,.014,.012,x,y-h/2,z,m,parent);
    box(.014,h,.012,x-w/2,y,z,m,parent);box(.014,h,.012,x+w/2,y,z,m,parent);
  }
  const staticMergeStats=[];
  function mergeRigidAnonymous(parent,label){
    // Only anonymous siblings in an explicitly whitelisted rigid group. Named
    // mechanical nodes, moving subgroups, cutaway switches and labels stay live.
    const buckets=new Map();
    for(const o of parent.children){
      if(!o.isMesh||o.name||o.userData.ownedLabel||cutPanels.includes(o)||normalOnly.includes(o)||Array.isArray(o.material))continue;
      const keys=Object.keys(o.geometry.attributes).sort();
      if(keys.join(',')!=='normal,position,uv')continue;
      if(!buckets.has(o.material))buckets.set(o.material,[]);buckets.get(o.material).push(o);
    }
    let before=0,after=0;
    for(const [material,pieces] of buckets){
      if(pieces.length<2)continue;
      const baked=pieces.map(o=>{o.updateMatrix();const g=o.geometry.index?o.geometry.toNonIndexed():o.geometry.clone();g.applyMatrix4(o.matrix);return g;});
      const combined=new THREE.BufferGeometry();
      for(const name of ['position','normal','uv']){
        const itemSize=baked[0].attributes[name].itemSize,total=baked.reduce((n,g)=>n+g.attributes[name].array.length,0),data=new Float32Array(total);let at=0;
        for(const g of baked){data.set(g.attributes[name].array,at);at+=g.attributes[name].array.length;}
        combined.setAttribute(name,new THREE.BufferAttribute(data,itemSize));
      }
      combined.computeBoundingBox();combined.computeBoundingSphere();
      const merged=mesh(combined,material,parent,label+'_'+material.name);merged.userData.rigidSourcePieces=pieces.length;
      for(const o of pieces){o.removeFromParent();o.geometry.dispose();}for(const g of baked)g.dispose();
      before+=pieces.length;after++;
    }
    staticMergeStats.push({group:parent.name,sourceMeshes:before,mergedMeshes:after});
  }

  // A hollow cabinet, with an actual jamb and a separate right-hinged leaf.
  const body=group('箱体空心壳');
  // Split the bolt-receiving wall into solids around two blind pockets.
  box(.18,2.73,1.06,-1.21,0,-.195,M.paint,body,'左后侧壁');
  box(.18,2.73,.165,-1.21,0,.6425,M.paint,body,'左前侧壁');
  box(.18,1.70,.225,-1.21,0,.4475,M.paint,body,'左侧中腹');
  for(const y of [-1.2175,1.2175])box(.18,.295,.225,-1.21,y,.4475,M.paint,body);
  for(const y of [-.96,.96])box(.043,.225,.225,-1.2785,y,.4475,M.paint,body,'门闩盲孔外盖_'+y);
  box(.18,2.73,1.45,1.21,0,0,M.paint,body,'右侧壁');
  box(2.28,.16,1.45,0,1.285,0,M.paint,body,'顶板');
  box(2.28,.18,1.45,0,-1.285,0,M.paint,body,'底板');
  box(2.28,2.40,.14,0,0,-.65,M.paint,body,'后壁');
  box(2.16,.055,1.13,0,-1.158,-.025,M.inside,body,'内底衬');
  // Weld seams and longitudinal edges supply scale without a mirror environment.
  for(const x of [-1.304,1.304])for(const z of [-.70,.69])box(.016,2.58,.018,x,0,z,M.dark,body);
  box(2.45,.018,.016,0,1.371,.63,M.edge,body);
  for(const x of [-.94,.94])for(const z of [-.47,.48]){
    const foot=box(.34,.20,.35,x,-1.465,z,M.dark,body,null,.022);foot.rotation.z=x>0?.035:-.035;
    box(.33,.045,.34,x,-1.565,z,M.black,body);
  }
  const frame=group('承力门框');
  box(.18,2.61,.20,-1.18,0,.68,M.paint,frame);box(.18,2.61,.20,1.18,0,.68,M.paint,frame);
  box(2.19,.18,.20,0,1.22,.68,M.paint,frame);box(2.19,.18,.20,0,-1.22,.68,M.paint,frame);
  outlineRect(2.17,2.34,0,0,.793,frame,M.black);
  // Steel receiving pockets for the upper/lower bolts are genuine cavities.
  for(const y of [.96,-.96]){
    box(.085,.070,.19,-1.105,y+.145,.455,M.steel,frame);
    box(.085,.070,.19,-1.105,y-.145,.455,M.steel,frame);
    box(.085,.28,.045,-1.105,y,.34,M.steel,frame);
  }

  const pivot=group('右侧门铰轴');pivot.position.fromArray(SAFE_DIMENSIONS.hinge);
  const door=group('可开门总成',pivot);door.position.set(-1.18,0,-.80);
  parts.door=door;parts.doorPivot=pivot;
  // Front skin holes are actual geometry; access does not rely on section mode.
  const faceShape=roundedRect(2.15,2.30,.037);
  faceShape.userData.roundedRectangle=false; // Its circular spindle holes retain 24 segments.
  faceShape.holes.push(circleHole(...DIAL,.104),circleHole(...HANDLE,.086));
  faceShape.holes.push(serviceOpening());
  const face=mesh(extruded(faceShape,.085,.01),M.face,door,'门外装甲');face.position.z=.787;cutPanels.push(face);
  const back=box(2.14,2.28,.035,0,0,.286,M.dark,door,'机构背盖');cutPanels.push(back);
  for(const x of [-1.035,1.035])box(.075,2.28,.51,x,0,.55,M.paint,door,'门侧厚度_'+x);
  for(const y of [-1.115,1.115])box(2.05,.07,.51,0,y,.55,M.paint,door);
  outlineRect(2.085,2.24,0,0,.893,door,M.edge);
  for(const x of [-.99,.99])for(const y of [-1.06,1.06])stud(x,y,.91,door,.023);
  // Interior load-bearing ribs remain visible when the skins are sectioned out.
  box(.08,2.03,.09,.82,0,.348,M.inside,door,'内侧承力肋');
  box(1.90,.07,.085,0,1.005,.35,M.inside,door);box(1.90,.07,.085,0,-1.005,.35,M.inside,door);
  // Both hinges share the door pivot's vertical axis, in alternating knuckles.
  for(const y of [.83,-.83]){
    for(const dy of [-.16,.16]){box(.16,.13,.15,1.105,y+dy,.76,M.dark,frame);cyl(.094,.14,1.18,y+dy,.80,M.edge,frame,null,'y');}
    box(.21,.17,.10,1.065,y,.806,M.face,door);cyl(.097,.17,1.18,y,.80,M.paint,door,null,'y');
    cyl(.052,.46,1.18,y,.80,M.dark,frame,null,'y');cyl(.09,.026,1.18,y+.235,.80,M.edge,frame,null,'y');
  }

  // Original visual identity: a large upper-left dial and lower-right three spokes.
  const dial=group('外密码盘',door);dial.position.set(...DIAL,0);
  const bezel=ring(.428,.313,.066,0,0,.93,M.dark,dial,'密码盘外边圈');
  ring(.403,.365,.018,0,0,.975,M.edge,dial);
  const dialRotor=group('拨盘转子',dial);
  const rotorFace=cyl(.354,.050,0,0,.973,M.paint,dialRotor);normalOnly.push(rotorFace);
  normalOnly.push(ring(.341,.294,.025,0,0,1.012,M.edge,dialRotor));
  const rotorCore=cyl(.246,.055,0,0,1.008,M.dark,dialRotor);normalOnly.push(rotorCore);
  normalOnly.push(cyl(.095,.12,0,0,1.058,M.paint,dialRotor));
  for(let i=0;i<10;i++){
    const a=PI/2-i*DIGIT_STEP;
    const tick=box(.016,.042,.012,Math.cos(a)*.305,Math.sin(a)*.305,1.031,M.cream,dialRotor);tick.rotation.z=a-PI/2;normalOnly.push(tick);
    const num=textPlane(String(i),.067,.067,Math.cos(a)*.261,Math.sin(a)*.261,1.047,dialRotor,'#dedac6',100);
    if(num)normalOnly.push(num);
  }
  // Stationary crown witness is separate from the rotating figures.
  const witnessShape=new THREE.Shape();witnessShape.moveTo(-.035,0);witnessShape.lineTo(.035,0);witnessShape.lineTo(0,-.043);witnessShape.closePath();
  const witness=mesh(extruded(witnessShape,.012,0),M.cream,dial);witness.position.set(0,.46,.954);
  const badge=box(.41,.13,.016,.64,.84,.905,M.dark,door,'铭牌');
  const badgeText=textPlane('CF—07',.34,.065,.64,.86,.917,door,'#c9c8b8',78);if(badgeText)normalOnly.push(badgeText);normalOnly.push(badge);
  const badgeText2=textPlane('FIELD SAFE',.32,.029,.64,.805,.918,door,'#98a5a8',58);if(badgeText2)normalOnly.push(badgeText2);

  const handleAxle=cyl(.063,.76,...HANDLE,.725,M.steel,door,'独立把手主轴');
  ring(.225,.134,.060,...HANDLE,.927,M.dark,door);
  const handle=group('三辐把手转子',door);handle.position.set(...HANDLE,.98);
  for(let i=0;i<3;i++){
    const arm=group('把手辐_'+i,handle);arm.rotation.z=(-30+i*120)*PI/180;
    box(.105,.32,.11,0,.315,.07,M.edge,arm,null,.027);
    box(.054,.265,.018,0,.315,.132,M.steel,arm,null,.007);
    cyl(.055,.105,0,.48,.07,M.edge,arm,null,'z',8);
  }
  ring(.207,.151,.082,0,0,.087,M.dark,handle);cyl(.15,.075,0,0,.102,M.paint,handle);
  ring(.147,.139,.008,0,0,.147,M.edge,handle);

  // Password lock: one shaft, drive cam, 3 coaxial wheels, guides, one fence.
  const lock=group('三轮锁机构',door);
  box(.085,.76,.075,-.86,.44,.32,M.dark,lock,'锁盒左导轨');box(.085,.76,.075,.005,.44,.32,M.dark,lock,'锁盒右导轨');
  box(.96,.09,.46,-.43,.90,.525,M.dark,lock,'锁盒上支承');box(.94,.065,.46,-.43,-.025,.525,M.dark,lock,'锁盒下支承');
  for(const x of [-.865,.005])for(const y of [.83,.055])stud(x,y,.773,lock);
  cyl(.048,.75,...DIAL,.664,M.steel,lock,'拨盘连续主轴');
  ring(.107,.053,.063,...DIAL,.314,M.bronze,lock,'后主轴衬套');
  ring(.112,.054,.039,...DIAL,.763,M.bronze,lock,'前主轴衬套');
  // Bearing support spider leaves the wheel gates exposed at 12 o'clock.
  for(const a of [PI/6,PI,PI*1.5]){
    const spider=box(.053,.34,.043,DIAL[0]+Math.cos(a)*.226,DIAL[1]+Math.sin(a)*.226,.749,M.dark,lock);spider.rotation.z=a-PI/2;
  }
  const wheelRotors=[],wheelRims=[];
  for(let i=0;i<3;i++){
    const z=.366+i*.118;
    const rotor=group(['百位轮毂','十位轮毂','个位轮毂'][i],lock);rotor.position.set(...DIAL,z);
    const rim=mesh(gateWheelGeometry(),i===1?M.bronze:M.brass,rotor,['百位有槽密码轮','十位有槽密码轮','个位有槽密码轮'][i]);rim.position.z=-.029;
    wheelRims.push(rim);wheelRotors.push(rotor);
    ring(.102,.053,.071,0,0,.006,M.steel,rotor);
    ring(.067,.05,.031,0,0,.054,M.dark,rotor);
    // Inter-wheel pickup dogs sit in the actual axial gaps; no perimeter teeth.
    const inAngle=DOG_PHASE+PI;
    const incoming=cyl(.0108,.074,Math.cos(inAngle)*.24,Math.sin(inAngle)*.24,.059,M.edge,rotor,'搭接入销_'+i,'z',10);
    if(i>0)cyl(.0108,.073,.24,0,-.059,M.edge,rotor,'搭接出销_'+i,'z',10);
    for(let q=0;q<3;q++){const a=q*2*PI/3+.25;cyl(.015,.077,Math.cos(a)*.080,Math.sin(a)*.080,0,M.dark,rotor,null,'z',8);}
  }
  const cam=group('主轴驱动凸轮',lock);cam.position.set(...DIAL,.72);
  const camFace=mesh(gateWheelGeometry(.318,.040),M.steel,cam,'驱动凸轮槽');camFace.position.z=-.020;
  cyl(.0108,.070,.24,0,-.054,M.edge,cam,'主轴驱动销','z',10);
  ring(.113,.052,.052,0,0,0,M.dark,cam);
  // Gate/fence bar bridges all axial wheel planes as a single rigid part.
  const fence=group('整体栅杆',lock);
  box(.078,.067,.502,-.43,.79,.541,M.steel,fence,'跨三轮栅杆');
  box(.343,.052,.067,-.30,.828,.73,M.edge,fence,'栅杆至杠杆桥');
  box(.049,.441,.049,-.13,.590,.72,M.steel,fence,'栅杆垂直拉杆');
  for(const z of [.316,.762]){
    for(const x of [-.494,-.366])box(.021,.24,.055,x,.805,z,M.dark,lock);
    box(.15,.030,.055,-.43,.925,z,M.dark,lock);
  }
  const rocker=group('栅杆杠杆',lock);rocker.position.set(.03,.37,.617);
  box(.525,.051,.045,.095,0,0,M.steel,rocker);cyl(.047,.071,0,0,0,M.bronze,rocker);
  box(.12,.18,.047,.03,.37,.56,M.dark,lock,'杠杆轴承座');cyl(.018,.12,.03,.37,.60,M.edge,lock);
  const smallLatch=group('共用小锁舌',door);
  box(.095,.195,.098,.34,.105,.582,M.steel,smallLatch,'小锁舌本体');
  cyl(.028,.195,.34,.203,.668,M.brass,smallLatch,'锁舌牵引横销');
  // A real lost-motion slot: B's cable pin can stay while the password lifts it.
  for(const x of [.313,.367])box(.014,.177,.021,x,.123,.758,M.steel,smallLatch);
  for(const y of [.0345,.2115])box(.068,.014,.021,.34,y,.758,M.steel,smallLatch);
  const cablePin=cyl(.018,.040,.34,.203,.758,M.brass,door,'钢索失动槽牵引销');
  box(.052,.166,.043,.34,.289,.622,M.steel,smallLatch,'杠杆输出连杆');
  for(const y of [.207,.339]){
    const sleeve=group('小锁舌导向套_'+y,door);
    for(const x of [.259,.421])box(.042,.063,.177,x,y,.582,M.dark,sleeve);
    for(const z of [.506,.658])box(.12,.063,.025,.34,y,z,M.dark,sleeve);
  }

  // Coarse bolts: a crank + fixed-length connecting rod + guided crosshead.
  const crank=group('把手内侧凸轮',door);crank.position.set(...HANDLE,.485);
  cyl(.218,.066,0,0,0,M.dark,crank);ring(.224,.197,.012,0,0,.041,M.edge,crank);
  box(.104,.062,.080,.04,.202,.009,M.dark,crank,'小锁舌阻挡凸台');
  cyl(.033,.070,-.18,0,.062,M.brass,crank,'门闩曲柄销');
  const carriage=group('粗门闩滑架',door);
  box(.085,2.00,.084,-.72,0,.443,M.steel,carriage,'门闩联动立柱');
  for(const y of [.96,-.96]){
    cyl(.077,.49,-.975,y,.447,M.steel,carriage,'粗门闩_'+y,'x',24);
    cyl(.078,.035,-1.215,y,.447,M.edge,carriage,null,'x',24);
    // Actual guide sleeves, with clear central bore along X.
    const sleeve=ring(.113,.082,.18,-.973,y,.447,M.dark,door);sleeve.rotation.y=PI/2;
    box(.18,.038,.22,-.973,y-.127,.43,M.dark,door);
  }
  const boltLink=rod([-.72,-.20,.547],[.12,-.20,.547],.025,M.steel,door,'定长门闩连杆');
  ring(.046,.026,.024,-.72,-.20,.565,M.brass,carriage);

  // V2: a loosened, still captive maintenance cover hides a continuous cassette.
  // The surviving hinges and broken spring catch explain access; no new lock step.
  const serviceHousing=group('贯通维护腔支承',door);
  const housingShape=new THREE.Shape();
  housingShape.moveTo(-.994,-1.088);housingShape.lineTo(-.994,-.109);housingShape.lineTo(-.366,-.109);
  housingShape.lineTo(-.366,-.329);housingShape.lineTo(-.150,-.329);housingShape.lineTo(-.150,-1.088);housingShape.closePath();
  const housingBack=mesh(extruded(housingShape,.024,.003),M.deep,serviceHousing,'维护腔封闭后衬');housingBack.position.z=.624;
  box(.038,1.001,.260,-.994,-.5985,.782,M.dark,serviceHousing);
  box(.648,.035,.260,-.680,-.110,.782,M.dark,serviceHousing);
  box(.037,.239,.260,-.368,-.2235,.782,M.dark,serviceHousing);
  box(.216,.035,.260,-.260,-.331,.782,M.dark,serviceHousing);
  box(.037,.758,.260,-.151,-.711,.782,M.dark,serviceHousing);
  box(.883,.037,.260,-.573,-1.087,.782,M.dark,serviceHousing);
  // Front reveal edges stay outside the input seats and expose the interlock.
  box(.018,1.014,.014,-1.015,-.5875,.923,M.edge,serviceHousing);
  box(.671,.018,.014,-.686,-.091,.923,M.edge,serviceHousing);
  box(.018,.237,.014,-.350,-.2025,.923,M.edge,serviceHousing);
  box(.228,.018,.014,-.235,-.314,.923,M.edge,serviceHousing);
  box(.018,.798,.014,-.128,-.709,.923,M.edge,serviceHousing);
  box(.905,.018,.014,-.574,-1.107,.923,M.edge,serviceHousing);
  for(const [x,y] of [[-.970,-.260],[-.397,-.260],[-.182,-.373],[-.182,-1.054],[-.964,-1.054]])stud(x,y,.938,serviceHousing,.014);
  // Four stand-offs join the cassette rear to the inner door skin. They avoid
  // the coarse bolt's swept line; the cavity is sealed from the storage volume.
  for(const [x,y] of [[-.947,-.231],[-.188,-.397],[-.188,-1.049],[-.947,-1.083]]){
    cyl(.022,.325,x,y,.4685,M.dark,door,null,'z',12);
    cyl(.035,.030,x,y,.316,M.steel,door,null,'z',12);
  }
  const serviceRear=group('维护盒门背封板',door);cutPanels.push(serviceRear);
  const rearFace=mesh(extruded(housingShape,.028,.004),M.inside,serviceRear,'维护盒后封板实体');rearFace.position.z=.234;
  for(const [x,y] of [[-.947,-.231],[-.188,-.397],[-.188,-1.049],[-.947,-1.083]]){
    cyl(.027,.018,x,y,.229,M.edge,serviceRear,null,'z',8);
    box(.027,.006,.004,x,y,.217,M.dark,serviceRear,null,.001);
  }
  const coverFixed=group('维护盖固定铰座',door),coverPivot=group('维护盖铰轴',door);
  coverPivot.position.set(-1.028,-.650,.981);
  const coverLeaf=group('松脱维护盖',coverPivot);cutPanels.push(coverLeaf);
  const coverShape=new THREE.Shape();
  coverShape.moveTo(.019,-.477);coverShape.lineTo(.910,-.477);coverShape.lineTo(.918,-.469);
  coverShape.lineTo(.918,-.052);coverShape.lineTo(.882,-.042);coverShape.lineTo(.887,.010);coverShape.lineTo(.918,.031);
  coverShape.lineTo(.918,.333);coverShape.lineTo(.700,.333);coverShape.lineTo(.700,.570);
  coverShape.lineTo(.692,.578);coverShape.lineTo(.019,.578);coverShape.closePath();
  const coverFace=mesh(extruded(coverShape,.024,.004),M.face,coverLeaf,'维护盖折角钢皮');coverFace.position.z=-.012;
  // Rear folded hems and shallow stiffeners are real thickness, visible open.
  box(.016,1.046,.026,.026,.0505,-.025,M.dark,coverLeaf);
  box(.875,.016,.026,.464,-.468,-.025,M.dark,coverLeaf);
  box(.666,.016,.026,.359,.567,-.025,M.dark,coverLeaf);
  box(.015,.768,.026,.906,-.074,-.025,M.dark,coverLeaf);
  box(.014,.229,.026,.689,.4505,-.025,M.dark,coverLeaf);
  box(.212,.015,.026,.801,.337,-.025,M.dark,coverLeaf);
  for(const y of [-.285,.225])box(.608,.026,.019,.358,y,-.028,M.inside,coverLeaf);
  // The catch is visibly incomplete: an empty rivet socket, split spring tongue,
  // and exposed rubbed steel at the notch, rather than a decorative closed lock.
  box(.076,.122,.021,-.099,-.657,.940,M.dark,coverFixed,'断裂扣耳底座');
  for(const y of [-.698,-.616])stud(-.094,y,.957,coverFixed,.012);
  box(.026,.031,.024,-.117,-.625,.970,M.edge,coverFixed,'残留扣耳上段');
  const tornTongue=box(.027,.025,.026,-.113,-.682,.972,M.bronze,coverFixed,'折断弹簧扣舌');tornTongue.rotation.z=-.28;
  ring(.018,.010,.010,.857,-.016,.020,M.dark,coverLeaf,'盖板空铆孔');
  const rubbed=box(.047,.009,.005,.895,.024,.017,M.edge,coverLeaf,'扣口磨亮端面');rubbed.rotation.z=.25;
  box(.070,.018,.016,.778,-.030,.012,M.dark,coverLeaf,'松盖抓边');
  for(const dy of [-.329,.313]){
    for(const off of [-.059,.059]){
      box(.080,.045,.095,-1.002,-.650+dy+off,.935,M.dark,coverFixed);
      cyl(.027,.042,-1.028,-.650+dy+off,.981,M.edge,coverFixed,null,'y',16);
    }
    cyl(.012,.183,-1.028,-.650+dy,.981,M.dark,coverFixed,'维护盖贯通销_'+dy,'y',12);
    box(.076,.071,.042,.025,dy,-.007,M.face,coverLeaf);
    cyl(.029,.068,0,dy,0,M.paint,coverLeaf,null,'y',16);
  }
  // Accessible inserts sit in the same uninterrupted cassette as their output.
  const targets={},ports={},variantNodes={a:null,b:null};let variants={a:0,b:0,aDir:1,bDir:1};
  for(const key of ['a','b']){
    const [x,y]=PORT_POSITIONS[key];
    const ph=key==='a'?.29:.40;
    const p=group('工具作用口_'+key,door);p.position.set(x,y,0);ports[key]=p;
    // Low rear cross-members support the interchangeable input units without
    // erecting V1's opaque right wall across the A-to-B common linkage.
    box(.515,.035,.044,0,-ph/2+.009,.674,M.dark,p,'结构安装横座_'+key);
    for(const xx of [-.237,.208])stud(xx,-ph/2+.013,.704,p,.013);
    // Position-only target is always where an inserted tool actually meets metal.
    targets[key]=new THREE.Object3D();targets[key].name='交互命中点_'+key;p.add(targets[key]);targets[key].position.set(0,0,.947);
  }
  const anchor=(name,parent,position)=>{const o=new THREE.Object3D();o.name=name;o.position.fromArray(position);parent.add(o);return o;};
  const serviceAnchors={overview:anchor('双机构稳定近景锚点',door,SERVICE_VIEW.center)};
  const rotationAnchors={};
  for(const key of ['a','b']){
    serviceAnchors[key]=anchor('机构近景锚点_'+key,ports[key],[0,0,.85]);
    rotationAnchors[key]={axis:anchor('真实轴线在作用面上的中心_'+key,ports[key],[0,0,.947]),bearing:anchor('旋转件实体支承中心_'+key,ports[key],[0,0,.835]),handle:targets[key]};
  }
  // Common A pressure catch and B output crosshead are distinct parts.
  const pressure=group('A承压联锁输出',door);
  box(.17,.047,.048,-.31,-.655,.718,M.brass,pressure,'承压横肩');
  box(.028,.105,.048,-.294,-.720,.718,M.brass,pressure,'联锁下舌');
  box(.048,.266,.052,-.43,-.548,.718,M.steel,pressure,'A抬升导杆');
  box(.215,.055,.066,-.35,-.415,.718,M.steel,pressure);
  box(.277,.043,.052,-.557,-.337,.744,M.steel,pressure,'A滚头桥');
  box(.048,.090,.05,-.43,-.380,.744,M.steel,pressure,'A桥至导杆');
  const aFollower=cyl(.035,.078,-.69,-.372,.866,M.edge,pressure,'A承压滚头');
  const aFollowerAxle=cyl(.013,.174,-.69,-.372,.800,M.dark,pressure,'A滚头贯通轴');
  const aFollowerHolder=box(.06,.08,.028,-.69,-.350,.690,M.steel,pressure,'A滚头轴承座');
  box(.105,.055,.09,-.43,-.494,.695,M.dark,door,'A导杆下套');
  const output=group('B横向输出滑架',door);
  box(.30,.050,.048,-.51,-.747,.751,M.steel,output,'B滑架连杆');
  ring(.04,.021,.043,-.51,-.747,.775,M.brass,output,'B钢索系点');
  box(.048,.085,.052,-.24,-.756,.744,M.steel,output,'B联锁挡肩');
  for(const x of [-.49,-.27])box(.051,.136,.111,x,-.754,.72,M.dark,door);
  // The same fixed-length cable lifts the same latch for every B variant.
  const cableZ=.758;
  const cableEnd=rod([-.51,-.747,cableZ],[-.16,-.747,cableZ],.009,M.cable,door,'钢索输入段');
  rod([-.096,-.683,cableZ],[-.096,.426,cableZ],.009,M.cable,door,'钢索上行段');
  rod([-.032,.49,cableZ],[.276,.49,cableZ],.009,M.cable,door,'钢索上横段');
  const cableLatch=rod([.34,.426,cableZ],[.34,.203,cableZ],.009,M.cable,door,'钢索锁舌段');
  const pulleys=[[-.16,-.683,-PI/2,0],[-.032,.426,PI,PI/2],[.276,.426,PI/2,0]];
  for(const [x,y,a0,a1] of pulleys){
    box(.15,.15,.035,x,y,.705,M.dark,door);ring(.055,.024,.026,x,y,.758,M.bronze,door);cyl(.021,.075,x,y,.732,M.edge,door);
    for(const z of [.742,.774])ring(.073,.024,.003,x,y,z,M.dark,door);
    // Cable wraps the working pitch radius, with tangent straight segments.
    const points=[];for(let i=0;i<=14;i++){const a=a0+(a1-a0)*i/14;points.push(v3([x+.064*Math.cos(a),y+.064*Math.sin(a),cableZ]));}
    mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(points),24,.009,8,false),M.cable,door,'钢索导轮包角_'+x+'_'+y);
  }

  function clearVariant(key){const n=variantNodes[key];if(!n)return;n.traverse(o=>{if(o.geometry)o.geometry.dispose();if(o.userData.ownedLabel){const m=o.material;if(m.map){m.map.dispose();ownedTextures.delete(m.map);}m.dispose();allMaterials.delete(m);}if(parts[o.name]===o)delete parts[o.name];});n.removeFromParent();}
  function makeVariant(key,index,dir=1){
    clearVariant(key);const base=group(`${key.toUpperCase()}${index}_可更换机构`,ports[key]);variantNodes[key]=base;
    const moving=group(`${key.toUpperCase()}${index}_运动件`,base);base.userData.moving=moving;base.userData.dir=dir;
    if(key==='a'){
      if(index===0){
        box(.42,.035,.078,0,-.090,.811,M.steel,base);box(.42,.025,.032,0,.087,.675,M.dark,base);
        // Brass stopper block & red-brass limit pin on the blocked (-dir) side; open groove on +dir side.
        box(.028,.088,.046,-.178*dir,0,.912,M.brass,base,'A0黄铜止挡座');cyl(.013,.058,-.178*dir,0,.922,M.orange,base,'A止挡销');
        box(.155,.016,.014,.065*dir,-.048,.908,M.dark,base,'A0导槽敞口');
        const s=new THREE.Shape();s.moveTo(-.14*dir,-.055);s.lineTo(.07*dir,-.055);s.lineTo(.07*dir,-.045);s.lineTo(-.14*dir,.1314);s.closePath();
        const w=mesh(extruded(s,.155,.003),M.brass,moving);w.position.z=.70;
        box(.042,.082,.031,-.134*dir,.0,.903,M.edge,moving);box(.071,.038,.026,-.114*dir,.0,.925,M.dark,moving,'A0卸载键作用座');
        cyl(.018,.075,-.114*dir,0,.879,M.steel,moving);
      }else if(index===1){
        for(const x of [-.115,.115])box(.029,.232,.063,x,0,.817,M.steel,base);
        const sy=dir===1?-.118:.082,y0=dir===1?-.072:.033;
        box(.088,.024,.046,0,sy,.912,M.brass,base,'A1黄铜止挡座');cyl(.013,.058,0,sy,.922,M.orange,base,'A止挡销');
        const s=new THREE.Shape();s.moveTo(-.087,-.123);s.lineTo(.087,-.123);s.lineTo(.022,.023);s.lineTo(-.010,.023);s.closePath();
        const w=mesh(extruded(s,.155,.003),M.brass,moving);w.position.z=.70;
        box(.065,.039,.034,0,y0,.911,M.dark,moving,'A1卸载键作用座');
        cyl(.018,.070,0,y0,.881,M.steel,moving);
      }else{
        ring(.137,.119,.049,0,0,.840,M.steel,base);cyl(.031,.090,0,0,.835,M.dark,base);
        box(.026,.036,.044,-.058*dir,.088,.922,M.brass,base,'A2黄铜止挡座');cyl(.012,.056,-.058*dir,.088,.930,M.orange,base,'A止挡销');
        cyl(.12,.037,-.10*dir,0,.739,M.brass,moving);cyl(.025,.17,0,0,.805,M.dark,moving);
        cyl(.020,.19,0,.093,.827,M.steel,moving);box(.074,.046,.030,0,.093,.921,M.edge,moving);box(.047,.024,.014,0,.093,.944,M.dark,moving,'A2卸载键作用座');
      }
    }else{
      if(index===0){
        for(const x of [.05*dir,.14*dir]){box(.029,.128,.062,x,0,.747,M.steel,base);box(.035,.063,.049,x,0,.781,M.dark,base);}
        box(.024,.072,.044,.058*dir,0,.920,M.brass,base,'B0黄铜止挡座');cyl(.012,.056,.058*dir,0,.928,M.orange,base,'B止挡销');
        box(.45,.050,.039,.13*dir,-.002,.738,M.brass,moving);ring(.067,.038,.035,0,0,.923,M.steel,moving,'B0牵引圆眼');cyl(.022,.185,0,0,.833,M.brass,moving);
        rod([.10*dir,0,.738],[.10*dir,.113,.751],.019,M.steel,moving,'直滑杆贯通连接叉');
        rod([.10*dir,.113,.751],[.17,.113,.751],.019,M.steel,moving);
        box(.10,.07,.035,.196*dir,0,.811,M.dark,base);
      }else if(index===1){
        moving.position.set(.096,.035,0);base.userData.pivot=[.096,.035];
        const sy=dir===1?.046:-.056;
        box(.044,.024,.044,-.195,sy,.920,M.brass,base,'B1黄铜止挡座');cyl(.012,.056,-.195,sy,.928,M.orange,base,'B止挡销');
        box(.249,.052,.045,-.093,0,.875,M.brass,moving);box(.045,.139,.045,.014,.033,.875,M.brass,moving);
        ring(.046,.025,.034,-.20,-.005,.923,M.steel,moving,'B1牵引圆眼');cyl(.026,.190,.096,.035,.803,M.dark,base);
        rod([0,0,.715],[0,.18,.715],.017,M.brass,moving,'折臂后曲柄');cyl(.013,.055,0,.18,.743,M.edge,moving,'折臂槽内销');
      }else{
        ring(.139,.119,.049,0,0,.841,M.steel,base);cyl(.030,.089,0,0,.836,M.dark,base);
        box(.026,.036,.044,.056*dir,.082,.922,M.brass,base,'B2黄铜止挡座');cyl(.012,.056,.056*dir,.082,.930,M.orange,base,'B止挡销');
        const s=new THREE.Shape();for(let j=0;j<=90;j++){const a=j*PI*2/90,r=.087+.036*Math.cos(3*(a-PI/2));if(j===0)s.moveTo(r*Math.cos(a),r*Math.sin(a));else s.lineTo(r*Math.cos(a),r*Math.sin(a));}s.closePath();s.holes.push(circleHole(0,0,.034));
        const tri=mesh(extruded(s,.043,.004),M.brass,moving,'三叶转盘');tri.position.z=.863;
        cyl(.024,.197,0,0,.806,M.dark,moving);rod([0,0,.715],[0,.18,.715],.017,M.brass,moving,'三叶盘后曲柄');cyl(.013,.055,0,.18,.743,M.edge,moving,'三叶盘槽内销');
        ring(.04,.022,.028,0,.086,.929,M.steel,moving,'B2牵引圆眼');
      }
      if(index>0){
        const c=group('B槽形连杆_'+index,base),xx=index===1?.096:0,yy=index===1?.167:.133;base.userData.coupler=c;
        for(const dx of [-.026,.026])box(.014,.143,.025,xx+dx,yy,.745,M.steel,c);
        for(const dy of [-.0785,.0785])box(.066,.014,.025,xx,yy+dy,.745,M.steel,c);
        rod([xx,.113,.747],[.17,.113,.747],.018,M.steel,c,'槽连杆接输出滑架_'+index);
      }
    }
    return base;
  }

  // Inserts only exist visually while the player's drag holds them at contact.
  const wedge=group('楔具',door),hook=group('钩具',door);
  box(.036,.035,.32,0,0,.148,M.steel,wedge);box(.076,.067,.22,0,0,.411,M.orange,wedge,null,.022);
  box(.071,.020,.073,0,0,-.027,M.edge,wedge,null,.002);
  for(let z=.35;z<.49;z+=.036)ring(.044,.031,.013,0,0,z,M.dark,wedge);
  const hookCurve=new THREE.CatmullRomCurve3([v3([0,0,0]),v3([.047,.005,.008]),v3([.060,.043,.025]),v3([.027,.083,.060]),v3([0,.09,.17]),v3([0,.09,.33])]);
  mesh(new THREE.TubeGeometry(hookCurve,24,.012,8,false),M.steel,hook);
  box(.076,.067,.21,0,.09,.43,M.blue,hook,null,.022);for(let z=.365;z<.51;z+=.036)ring(.043,.031,.014,0,.09,z,M.dark,hook);
  wedge.visible=false;hook.visible=false;

  let code='538',lastPose={a:0,b:0,wheelAngles:[0,0,0],dialAngle:0,fence:0,latch:0,handle:0,bolts:0,door:0},section=false;
  let serviceOpen=false,serviceStage=null;
  const latchStroke=.159375;
  function aCamAngle(progress){const r=.155,e=.10,y=Math.sqrt(r*r-e*e)+.105*progress;return Math.asin(Math.max(-1,Math.min(1,(e*e+y*y-r*r)/(2*e*y))));}
  const bCrankAngle=progress=>Math.asin(Math.max(-1,Math.min(1,latchStroke*progress/.18)));
  function setCode(value){code=validateCode(value);apply({...lastPose,code});}
  function setVariants(a,b,aDir=1,bDir=1){
    if(a&&typeof a==='object'){b=a.b;aDir=a.aDir??1;bDir=a.bDir??1;a=a.a;}
    const aa=typeof a==='string'?Number(a.replace(/^A/i,'')):a,bb=typeof b==='string'?Number(b.replace(/^B/i,'')):b;
    const ad=aDir===-1?-1:1,bd=bDir===-1?-1:1;
    if(![aa,bb].every(v=>Number.isInteger(v)&&v>=0&&v<3))throw new RangeError('结构变体编号须为0、1、2');
    variants={a:aa,b:bb,aDir:ad,bDir:bd};makeVariant('a',aa,ad);makeVariant('b',bb,bd);apply(lastPose);
  }
  function contact(key,p){
    const ad=variants.aDir||1,bd=variants.bDir||1;
    if(key==='a'){
      if(variants.a===0)return [ad*(-.114+.125*p),0,.938];
      if(variants.a===1)return [0,(ad===1?-.072:.033)+ad*.105*p,.938];
      const a=-ad*aCamAngle(p);return [-Math.sin(a)*.093,Math.cos(a)*.093,.947];
    }
    if(variants.b===0)return [-bd*latchStroke*p,0,.947];
    if(variants.b===1){const a=bd*bCrankAngle(p);return [.096-.20*Math.cos(a)+.005*Math.sin(a),.035-.20*Math.sin(a)-.005*Math.cos(a),.947];}
    const a=bd*bCrankAngle(p);return [-.086*Math.sin(a),.086*Math.cos(a),.947];
  }
  function apply(p={}){
    lastPose={...lastPose,...p};if(p.code!=null){code=validateCode(p.code);root.userData.code=code;}
    const ad=variants.aDir||1,bd=variants.bDir||1;
    const a=clamp01(lastPose.a),b=a>=.999?clamp01(lastPose.b):0;
    const jamA=Number(lastPose.jamA)||0,jamB=Number(lastPose.jamB)||0,jamShudder=Number(lastPose.jamShudder)||0,bTwitch=Number(lastPose.bTwitch)||0;
    const aVis=Math.max(-.06,Math.min(1,a+jamA))+(jamA?jamShudder:0);
    const bVis=(a>=.999?Math.max(-.06,Math.min(1,b+jamB))+bTwitch:Math.max(-.06,Math.min(.12,jamB)))+(jamB?jamShudder:0);
    const f=clamp01(lastPose.fence),l=Math.max(clamp01(lastPose.latch),b),h=clamp01(lastPose.handle),d=clamp01(lastPose.door);
    pivot.rotation.y=d*DOOR_RADIANS;
    const dialA=Number(lastPose.dialAngle)||0;dialRotor.rotation.z=dialA;cam.rotation.z=dialA;
    wheelRotors.forEach((o,i)=>{o.rotation.z=Number(lastPose.wheelAngles?.[i])||0;wheelRims[i].rotation.z=Number(code[i])*DIGIT_STEP;});
    fence.position.y=-.075*f;smallLatch.position.y=.159375*l;rocker.rotation.z=Math.asin(.075/.16*l);
    handle.rotation.z=h*2.05;crank.rotation.z=h*2.05;
    const ang=PI+h*2.05,pin=[HANDLE[0]+.18*Math.cos(ang),HANDLE[1]+.18*Math.sin(ang),.547];
    const slider=pin[0]-Math.sqrt(.84*.84-(pin[1]-HANDLE[1])**2),stroke=slider+.72;
    carriage.position.x=stroke;setRod(boltLink,[slider,HANDLE[1],.547],pin);
    pressure.position.y=.105*a;output.position.x=-.159375*Math.max(0,bVis);
    const fy=variants.a===2?PORT_POSITIONS.a[1]+Math.sqrt(.155*.155-.1*.1):variants.a===0?PORT_POSITIONS.a[1]+.0222+.035*Math.hypot(1,.84):-.372;
    const fx=variants.a===2?-.68:variants.a===1?-.674:-.69;
    aFollower.position.set(fx,fy,.733);aFollower.scale.y=.70;
    aFollowerAxle.position.set(fx,fy,.711);aFollowerAxle.scale.y=.45;
    aFollowerHolder.position.x=fx;aFollowerHolder.position.y=fy+.020;
    cablePin.position.y=.203+.159375*b;
    setRod(cableEnd,[-.51-.159375*b,-.747,cableZ],[-.16,-.747,cableZ]);
    // Lost-motion eye lets the password lever lift the same latch without towing B.
    setRod(cableLatch,[.34,.426,cableZ],[.34,.203+.159375*b,cableZ]);
    const am=variantNodes.a?.userData.moving,bm=variantNodes.b?.userData.moving;
    if(am){am.position.x=0;am.position.y=0;am.rotation.z=0;if(variants.a===0)am.position.x=ad*.125*aVis;else if(variants.a===1)am.position.y=ad*.105*aVis;else am.rotation.z=-ad*aCamAngle(Math.max(0,aVis));}
    if(bm){bm.position.x=variants.b===1?.096:0;bm.position.y=variants.b===1?.035:0;bm.rotation.z=0;if(variants.b===0)bm.position.x=-bd*.159375*bVis;else bm.rotation.z=bd*bCrankAngle(bVis);}
    if(variantNodes.b?.userData.coupler)variantNodes.b.userData.coupler.position.x=-.159375*Math.max(0,bVis);
    for(const key of ['a','b'])targets[key].position.fromArray(contact(key,key==='a'?Math.max(0,aVis):Math.max(0,bVis)));
    rotationAnchors.a.axis.position.set(0,0,.947);rotationAnchors.a.bearing.position.set(0,0,.835);
    rotationAnchors.b.axis.position.set(variants.b===1?.096:0,variants.b===1?.035:0,.947);
    rotationAnchors.b.bearing.position.set(variants.b===1?.096:0,variants.b===1?.035:0,variants.b===1?.803:.836);
    const stage=lastPose.activeStage,tool=lastPose.tool;
    wedge.visible=tool==='wedge'&&(stage==='a'||stage==='b');hook.visible=tool==='hook'&&(stage==='a'||stage==='b');
    if(stage==='a'||stage==='b'){
      const c=contact(stage,stage==='a'?Math.max(0,aVis):Math.max(0,bVis)),o=tool==='wedge'?wedge:hook;
      o.position.set(PORT_POSITIONS[stage][0]+c[0],PORT_POSITIONS[stage][1]+c[1],c[2]);
      const swivel=stage==='a'?(variants.a===1?PI/2:variants.a===2?-ad*aCamAngle(Math.max(0,aVis)):0):(variants.b>0?bd*bCrankAngle(bVis):0);
      o.rotation.set(0,.43,swivel);
    }
    root.updateMatrixWorld(true);
  }
  function setServiceAccess(open,stage=null){
    if(stage!==null&&stage!=='a'&&stage!=='b')throw new RangeError('维护作用段须为a、b或null');
    serviceOpen=!!open;serviceStage=stage;
    coverPivot.rotation.y=serviceOpen?-165*PI/180:0;
    root.userData.serviceAccess={open:serviceOpen,stage:serviceStage,coverAngle:coverPivot.rotation.y};
    root.updateMatrixWorld(true);
  }
  function sampleServicePath(stage,steps=16){
    if(stage!=='a'&&stage!=='b')throw new RangeError('作用段须为a或b');
    if(!Number.isInteger(steps)||steps<1||steps>256)throw new RangeError('路径采样段数须为1–256整数');
    root.updateMatrixWorld(true);
    return Array.from({length:steps+1},(_,i)=>{
      const p=i/steps,position=v3(contact(stage,p)).applyMatrix4(ports[stage].matrixWorld).toArray();return {p,position};
    });
  }
  function getServiceGesture(stage){
    if(stage!=='a'&&stage!=='b')throw new RangeError('作用段须为a或b');
    const variant=variants[stage],arc=variant===2,dir=stage==='a'?(variants.aDir||1):(variants.bDir||1);
    const direction=stage==='a'?(dir===1?['right','up','clockwise'][variant]:['left','down','counterclockwise'][variant]):(dir===1?['left','down','counterclockwise'][variant]:['right','up','clockwise'][variant]);
    const startAngle=arc?PI/2:null,endAngle=arc?(stage==='a'?PI/2-dir*aCamAngle(1):PI/2+dir*bCrankAngle(1)):null;
    return {stage,variant,polarity:dir,kind:arc?'arc':'linear',direction,axis:rotationAnchors[stage].axis,handle:targets[stage],
      progress:stage==='a'?clamp01(lastPose.a):clamp01(lastPose.a)>=.999?clamp01(lastPose.b):0,
      startAngle,endAngle,path:sampleServicePath(stage)};
  }
  function setCutaway(on){section=!!on;for(const o of cutPanels)o.visible=!section;for(const o of normalOnly)o.visible=!section;root.userData.cutaway=section;}
  function getAuditState(){
    const aa=auditPose({...lastPose,a:clamp01(lastPose.a),b:clamp01(lastPose.b)},code);
    const h=clamp01(lastPose.handle),ang=PI+h*2.05,px=.30+.18*Math.cos(ang),py=-.20+.18*Math.sin(ang),sx=px-Math.sqrt(.84*.84-(py+.20)**2);
    return {...aa,code,variants:{...variants},section,serviceAccess:{open:serviceOpen,stage:serviceStage,coverAngle:coverPivot.rotation.y},staticMergeStats,hinge:[1.18,0,.80],doorAngle:pivot.rotation.y,boltStroke:sx+.72,connectingRodLength:Math.hypot(px-sx,py+.20),cableVariableTotal:(.35+.159375*clamp01(lastPose.b))+(.223-.159375*clamp01(lastPose.b)),wheelGateWorldAngles:wheelRotors.map((o,i)=>o.rotation.z+Number(code[i])*DIGIT_STEP),resourceCounts:{materials:allMaterials.size,textures:ownedTextures.size},meshCount:(()=>{let n=0;root.traverse(o=>{if(o.isMesh)n++;});return n;})()};
  }
  function dispose(){const geometries=new Set();root.traverse(o=>{if(o.geometry)geometries.add(o.geometry);});for(const g of geometries)g.dispose();for(const t of ownedTextures)t.dispose();for(const m of allMaterials)m.dispose();root.removeFromParent();}
  setVariants(0,0,1,1);setCode(code);apply(lastPose);
  for(const [parent,label] of [[body,'静态箱体附件'],[frame,'静态门框附件'],[serviceHousing,'静态维护腔附件'],[coverFixed,'静态维护盖铰座'],[coverLeaf,'盖上刚性附件'],[serviceRear,'背封板刚性附件']])mergeRigidAnonymous(parent,label);
  root.userData={sourceCommit:'3dd6ca8a1afef1f2479beb7a5b94c08c9a1289c7',source:'原生XFL静态参考；新增内部机构、损坏扣耳维护盖与服务腔',code,dimensions:SAFE_DIMENSIONS,serviceView:SERVICE_VIEW};
  setServiceAccess(false);
  return {root,parts,targets,serviceAnchors,rotationAnchors,apply,setVariants,setCode,setCutaway,setServiceAccess,sampleServicePath,getServiceGesture,getAuditState,dispose,dimensions:SAFE_DIMENSIONS,serviceView:SERVICE_VIEW};
}
