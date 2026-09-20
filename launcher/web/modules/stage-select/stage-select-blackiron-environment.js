// E3: open old streets and block edges suggest enclosure; no painted religious diagram.
import * as THREE from '../../assets/stage-diorama/base-gate/vendor/three.module.js';
import {mergeGeometries} from '../../assets/stage-diorama/base-gate/vendor/BufferGeometryUtils.js';

export function createBlackironEnvironment(){
    const group=new THREE.Group();group.name='总部外围环境候选';
    const solid=[],glow=[],buildingBounds=[],roadBands=[],streetRecords=[],sun=new THREE.Vector3(-.45,.85,.3).normalize();let seed=72431,buildings=0,buildingFrame=null;
    function random(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;}
    function height(x,z){
        // Keep the campus, all side gate approaches, and the central rear inspection route clear.
        const outside=Math.max(Math.abs(x)-82,Math.abs(z)-81,0);
        const fade=Math.min(1,outside/24);
        const hills=z< -96 && Math.abs(x)>36 ? 9*Math.exp(-Math.pow((Math.abs(x)-112)/57,2)-Math.pow((z+155)/48,2)):0;
        return -.28+fade*(hills+.22*Math.sin(x*.12)*Math.cos(z*.09));
    }
    function add(geometry,color,matrix,light=false){
        const g=geometry.index?geometry.toNonIndexed():geometry.clone();geometry.dispose();
        if(matrix)g.applyMatrix4(matrix);if(buildingFrame)g.applyMatrix4(buildingFrame);g.deleteAttribute('uv');
        const rgb=new THREE.Color(color),colors=[],n=new THREE.Vector3();
        for(let i=0;i<g.attributes.position.count;i++){
            n.fromBufferAttribute(g.attributes.normal,i);
            const shade=light?1:.63+.32*Math.max(0,n.dot(sun));
            colors.push(rgb.r*shade,rgb.g*shade,rgb.b*shade);
        }
        g.setAttribute('color',new THREE.Float32BufferAttribute(colors,3));(light?glow:solid).push(g);
    }
    function box(x,y,z,w,h,d,color,light=false){
        add(new THREE.BoxGeometry(w,h,d),color,new THREE.Matrix4().makeTranslation(x,y+h/2,z),light);
    }
    function roof(x,y,z,w,d){
        const h=1.45,g=new THREE.BufferGeometry();
        g.setAttribute('position',new THREE.Float32BufferAttribute([-w/2,0,-d/2,w/2,0,-d/2,w/2,0,d/2,-w/2,0,d/2,-w*.32,h,0,w*.32,h,0],3));
        g.setIndex([0,4,5,0,5,1,1,5,2,2,5,4,2,4,3,3,4,0]);g.computeVertexNormals();
        add(g,0x554436,new THREE.Matrix4().makeTranslation(x,y,z));box(x,y-.3,z,w+.7,.3,d+.7,0x282624);
    }
    function available(x,z,w,d,angle=0){
        const ex=(Math.abs(Math.cos(angle))*(w+1)+Math.abs(Math.sin(angle))*(d+1))/2,ez=(Math.abs(Math.sin(angle))*(w+1)+Math.abs(Math.cos(angle))*(d+1))/2;
        const radius=Math.hypot(w+1,d+1)/2;
        if(Math.abs(x)<80+ex&&Math.abs(z)<79+ez)return false;
        if(Math.abs(x)<32+ex&&z+ez> -96&&z-ez< -77)return false;
        if(roadBands.some(r=>{const dx=r.bx-r.ax,dz=r.bz-r.az,t=THREE.MathUtils.clamp(((x-r.ax)*dx+(z-r.az)*dz)/(dx*dx+dz*dz),0,1);return Math.hypot(x-r.ax-t*dx,z-r.az-t*dz)<radius+r.width/2+1.2;}))return false;
        return !buildingBounds.some(b=>Math.abs(x-b.x)<ex+b.ex+2&&Math.abs(z-b.z)<ez+b.ez+2);
    }
    function house(x,z,w,d,h,angle=0){
        if(!available(x,z,w,d,angle))return false;
        const rotation=new THREE.Matrix4().makeRotationY(angle),corners=[];
        for(const a of [-1,1])for(const b of [-1,1]){const p=new THREE.Vector3(a*(w+1)/2,0,b*(d+1)/2).applyMatrix4(rotation);corners.push(height(x+p.x,z+p.z));}
        const low=Math.min(...corners),floor=Math.max(...corners)-low+.6;
        buildingFrame=rotation.setPosition(x,low,z);
        box(0,0,0,w+.6,floor,d+.6,0x51463b);box(0,floor,0,w,h,d,0x65513f);roof(0,floor+h,0,w+1,d+1);
        box(0,floor+.05,d/2+.04,1.7,2,.1,0x252420);
        for(const side of [-1,1])for(let k=0;k<(h>5?2:1);k++){
            const lit=random()>.72;
            box(side*w*.29,floor+.9+k*2.3,d/2+.08,1,.95,.12,lit?0x987349:0x302c29,lit);
        }
        buildingFrame=null;buildings++;
        buildingBounds.push({x,z,w,d,angle,ex:(Math.abs(Math.cos(angle))*(w+1)+Math.abs(Math.sin(angle))*(d+1))/2,ez:(Math.abs(Math.sin(angle))*(w+1)+Math.abs(Math.cos(angle))*(d+1))/2});return true;
    }
    function road(ax,az,bx,bz,width,color=0x332f2c){
        roadBands.push({ax,az,bx,bz,width});
        const dx=bx-ax,dz=bz-az,len=Math.hypot(dx,dz),nx=dz/len*width/2,nz=-dx/len*width/2,count=Math.ceil(len/7),points=[],indices=[];
        for(let i=0;i<=count;i++){const x=ax+dx*i/count,z=az+dz*i/count;for(const sign of [-1,1])points.push(x+nx*sign,height(x+nx*sign,z+nz*sign)+.035,z+nz*sign);if(i<count){const j=i*2;indices.push(j,j+2,j+1,j+1,j+2,j+3);}}
        const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(points,3));g.setIndex(indices);g.computeVertexNormals();add(g,color);
    }
    function curvedStreet(name,knots,startWidth,endWidth){
        const curve=new THREE.CatmullRomCurve3(knots.map(p=>new THREE.Vector3(p[0],0,p[1])),false,'centripetal'),points=curve.getPoints(90);
        for(let i=0;i<points.length-1;i++){const a=points[i],b=points[i+1],t=i/(points.length-1);road(a.x,a.z,b.x,b.z,THREE.MathUtils.lerp(startWidth,endWidth,t)+.35*Math.sin(t*Math.PI*3));}
        streetRecords.push({name,points:points.map(p=>[p.x,p.z]),widthRange:[startWidth,endWidth]});return curve;
    }
    function pointAtZ(curve,z){const points=curve.getPoints(800);let best=points[0];for(const p of points)if(Math.abs(p.z-z)<Math.abs(best.z-z))best=p;return best.x;}
    const ground=new THREE.PlaneGeometry(900,760,60,50);ground.rotateX(-Math.PI/2);
    const colors=[],tone=new THREE.Color(0x493c34),dark=new THREE.Color('#211e21');
    for(let i=0;i<ground.attributes.position.count;i++){
        const p=ground.attributes.position,x=p.getX(i),z=p.getZ(i);p.setY(i,height(x,z));
        const variation=.82+.1*Math.sin(x*.053+z*.067)+.05*Math.cos(x*.11-z*.041);
        const distance=Math.max(Math.abs(x),Math.abs(z)),fade=THREE.MathUtils.smoothstep(distance,195,365);
        const c=tone.clone().multiplyScalar(variation).lerp(dark,fade);colors.push(c.r,c.g,c.b);
    }
    ground.computeVertexNormals();ground.setAttribute('color',new THREE.Float32BufferAttribute(colors,3));
    group.add(new THREE.Mesh(ground,new THREE.MeshBasicMaterial({vertexColors:true})));
    // Front urban road and processional approach; they continue beyond the frame.
    road(-290,100,290,100,12);road(0,74,0,260,11);
    road(112,-235,112,240,10);
    road(72,-24,112,-24,5);road(0,-78,0,-190,6);
    const west=curvedStreet('西侧旧街',[[-109,-235],[-109,-135],[-119,-76],[-129,-10],[-128,42],[-117,100],[-109,160],[-109,230]],8,6.5);
    const front=curvedStreet('前街外侧支巷',[[-174,100],[-146,126],[-91,151],[-38,160],[18,158],[78,139],[112,100]],6.5,5);
    const rear=curvedStreet('坡脚检修支路',[[112,-90],[133,-121],[106,-151],[54,-169],[0,-175]],5,3.8);
    for(const z of [28,-10])road(-72,z,pointAtZ(west,z),z,4);
    // Reserve every main road before placing any housing.
    road(143,-8,143,71,46,0x4a4035);road(82,58,178,58,7);road(0,-94,115,-94,4,0x4c443b);
    for(let x=-235;x<=235;x+=16){if(Math.abs(x)<15)continue;box(x,height(x,100)+.05,100,6,.02,.15,0x746650);}
    // Staggered frontage follows the street, not a repeated ring of identical houses.
    for(const offset of [-18,-43])for(const t of [.25,.32,.39,.46,.54,.61,.68,.74]){
        if(offset===-43&&(t===.39||t===.61))continue;
        const p=west.getPoint(t),tangent=west.getTangent(t),normal=new THREE.Vector3(tangent.z,0,-tangent.x),setback=offset+(random()-.5)*3;
        house(p.x+normal.x*setback,p.z+normal.z*setback,9+random()*4,9+random()*4,3.5+random()*3,Math.atan2(normal.x,normal.z));
    }
    for(const [x,z] of [[-106,-63],[-113,-40],[-117,8],[-116,51],[-99,73]])house(x,z,8+random()*3,9+random()*3,3.8+random()*2,-Math.PI/2+.15);
    for(const t of [.10,.23,.37,.58,.73,.88]){
        const p=front.getPoint(t),tangent=front.getTangent(t),normal=new THREE.Vector3(tangent.z,0,-tangent.x);
        house(p.x-normal.x*18,p.z-normal.z*18,10+random()*5,10+random()*3,3.8+random()*2,Math.atan2(normal.x,normal.z));
    }
    // East receiving yard: broad hardstand, sheds and sparse stockpiles.
    house(158,-46,24,17,6.5);house(184,6,17,40,5);house(94,70,9,12,3.5);
    for(let i=0;i<10;i++){
        const x=130+(i%3)*11,z=8+Math.floor(i/3)*14,y=height(x,z);
        box(x,y+.08,z,5,1+random()*1.2,3,0x5c5140);box(x,y+.15,z,5.2,.13,3.2,0x292b28);
    }
    for(let i=0;i<5;i++){const x=129+i*10;box(x,height(x,70)+.06,70,.13,.03,10,0x77634b);}
    // Checkpoint shelters flank an open approach; no second mandatory gate is invented.
    house(-13,86,5,5,2.8);house(14,86,5,5,2.8);
    for(const x of [-18,19])box(x,height(x,88),88,.22,6,.22,0x44413a);
    // Partial retaining fragments follow the slope behind the service lane; the central route stays open.
    for(let i=7;i<29;i++){
        if(i%6===0)continue;const p=rear.getPoint(i/36),v=rear.getTangent(i/36),x=p.x+v.z*6,z=p.z-v.x*6;
        if(Math.abs(x)<36)continue;
        add(new THREE.BoxGeometry(5.2,1.2+(i%3)*.2,.8),0x51483d,new THREE.Matrix4().makeRotationY(Math.atan2(-v.z,v.x)).setPosition(x,height(x,z)+.6,z));
    }
    for(const side of [-1,1])house(side*68,-108,10,9,3.5);
    const drain=rear.getPoints(48).map((p,i,ps)=>{const v=ps[Math.min(ps.length-1,i+1)].clone().sub(ps[Math.max(0,i-1)]).normalize();return new THREE.Vector3(p.x+v.z*4,0,p.z-v.x*4);});
    for(let i=0;i<drain.length-1;i++)road(drain[i].x,drain[i].z,drain[i+1].x,drain[i+1].z,.65,0x302e2a);
    // Low pipes and supports connect the old utility edge; central inspection access stays open.
    for(let i=0;i<9;i++){const x=38+i*13,z=-98,y=height(x,z);box(x,y,z,.5,2.2,.5,0x534d40);box(x+6,y+1.8,z,12,.3,.35,0x625c4e);}
    for(let i=0;i<30;i++){
        const x=-90-random()*120,z=-92+random()*180,y=height(x,z);
        if(!available(x,z,2,2))continue;
        box(x,y,z,1+random()*2,.2+random()*.8,1+random()*2,0x51463c);
    }
    for(const [list,name] of [[solid,'外部街区与后勤'],[glow,'稀疏窗光']]){
        const merged=mergeGeometries(list,false);list.forEach(g=>g.dispose());
        const mesh=new THREE.Mesh(merged,new THREE.MeshBasicMaterial({vertexColors:true}));mesh.name=name;group.add(mesh);
    }
    let triangles=0;group.traverse(o=>{if(o.isMesh)triangles+=(o.geometry.index?.count||o.geometry.attributes.position.count)/3;});
    group.userData={revision:'E3',buildings,triangles,role:'noninteractive exterior context',streets:streetRecords,buildingBounds,urbanForm:'Three open curved streets and staggered frontage; no circle decal, taiji disk or new shrine.',preservedRearAccess:{x:[-32,32],z:[-96,-77]}};
    return group;
}
