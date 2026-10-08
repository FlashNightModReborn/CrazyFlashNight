// Screen composition is independent of geographic anchors and model proportions.
export const GAME_FRAME = { width: 1024, height: 576, aspect: 16 / 9 };
const PRESETS = {
  region: { yaw: -12, pitch: 34, baseNdc: [0, -.10] },
  city: { yaw: 25, pitch: 46, baseNdc: [-.04, .06] },
  base: { yaw: 30, pitch: 42, baseNdc: [-.50, .08] },
};
const SAFE = { left: -.86, right: .86, bottom: -.78, top: .78 };
const CONTEXT_RADIUS = { forest: 7, waste: 3, fallen: 3, industry: 4, front: 2, commune: 2 };

export function gameFrame(THREE, model, data, mode, projection = 'orthographic') {
  const preset = PRESETS[mode], required = new Set(data.stageMapping.filter(n => n.place).map(n => n.place));
  const points = [], covered = [];
  for (const anchor of model.anchors) {
    if (['supplygroup','well','storage','eastjunction'].includes(anchor.id)) continue;
    // The snow landing/navigation node is mandatory. The full peak silhouette may extend beyond the frame.
    if (mode === 'region' && anchor.id === 'snow') continue;
    const box = new THREE.Box3().setFromObject(anchor.object);
    if (mode === 'region' && !required.has(anchor.id)) {
      const radius = CONTEXT_RADIUS[anchor.id] ?? 1.5;
      box.min.max(anchor.world.clone().add(new THREE.Vector3(-radius,-radius,-radius)));
      box.max.min(anchor.world.clone().add(new THREE.Vector3(radius,radius,radius)));
    }
    if (!box.isEmpty()) for (const x of [box.min.x,box.max.x]) for (const y of [box.min.y,box.max.y]) for (const z of [box.min.z,box.max.z]) points.push(new THREE.Vector3(x,y,z));
    points.push(anchor.world.clone()); covered.push(anchor.id);
  }
  if (mode === 'base') {
    // Preserve the civilian lane outside the training area, not only its scene-centre anchors.
    for (const xy of [[.57,-.24],[.85,-.24],[1.8,-.04],[2.9,.52]]) points.push(model.terrain.world(xy));
  }
  const yaw = THREE.MathUtils.degToRad(preset.yaw), pitch = THREE.MathUtils.degToRad(preset.pitch);
  const direction = new THREE.Vector3(Math.sin(yaw)*Math.cos(pitch),Math.sin(pitch),Math.cos(yaw)*Math.cos(pitch));
  const right = new THREE.Vector3(0,1,0).cross(direction).normalize(), up = direction.clone().cross(right);
  const base = model.anchors.find(a => a.id === 'base').world;
  let vertical = .1;
  for (const p of points) {
    const relative = p.clone().sub(base), x=relative.dot(right), y=relative.dot(up);
    vertical=Math.max(vertical,
      x >= 0 ? 2*x/(GAME_FRAME.aspect*(SAFE.right-preset.baseNdc[0])) : -2*x/(GAME_FRAME.aspect*(preset.baseNdc[0]-SAFE.left)),
      y >= 0 ? 2*y/(SAFE.top-preset.baseNdc[1]) : -2*y/(preset.baseNdc[1]-SAFE.bottom));
  }
  const horizontal=vertical*GAME_FRAME.aspect;
  const target=base.clone().addScaledVector(right,-preset.baseNdc[0]*horizontal/2).addScaledVector(up,-preset.baseNdc[1]*vertical/2);
  const fov=28, tan=Math.tan(THREE.MathUtils.degToRad(fov/2));
  let distance=projection==='perspective'?vertical/2/tan:Math.max(horizontal*3,10);
  if(projection==='perspective')for(const p of points){
    const r=p.clone().sub(target), x=r.dot(right),y=r.dot(up),depth=r.dot(direction);
    distance=Math.max(distance,depth+(x>=0?x/SAFE.right:-x/-SAFE.left)/(tan*GAME_FRAME.aspect),depth+(y>=0?y/SAFE.top:-y/-SAFE.bottom)/tan);
  }
  return { target,direction,position:target.clone().addScaledVector(direction,distance),horizontal,vertical,fov,
    near:Math.max(.0001,horizontal/100000),far:Math.max(horizontal*30,10),covered,points,
    safe:SAFE,logicalFrame:GAME_FRAME,baseNdc:preset.baseNdc };
}

// A separate presentation surround lets a rectangular shot continue beyond the work-area cut.
// Samples outside the authored heightfield are clamped by heightAt: this is not new surveyed geography.
export function createSurroundings(THREE, terrain) {
  const [x0,x1,y0,y1]=terrain.bounds,dx=x1-x0,dy=y1-y0,pad=Math.max(dx,dy)*.45;
  const positions=[],colors=[],sand=new THREE.Color('#a6a18e'),rock=new THREE.Color('#8e918c'),snow=new THREE.Color('#dce0db');
  const core=terrain.group.getObjectByName('shared-heightfield-surface').geometry.attributes.position;
  const seamX=new Set(),seamY=new Set();
  for(let i=0;i<core.count;i++){seamX.add(core.getX(i));seamY.add(-core.getZ(i));}
  const axis=(a,b,n,seams)=>[...new Set([a,b,...Array.from({length:n-1},(_,i)=>a+(b-a)*(i+1)/n),...seams].filter(v=>v>=a&&v<=b))].sort((p,q)=>p-q);
  function strip(a,b,c,d){
    const nx=Math.max(2,Math.ceil((b-a)/(dx/24))),ny=Math.max(2,Math.ceil((d-c)/(dy/24)));
    // Match all work-area boundary samples, otherwise coarse triangles expose the cut-earth sidewalls.
    const xs=axis(a,b,nx,seamX),ys=axis(c,d,ny,seamY);
    for(let iy=0;iy<ys.length-1;iy++)for(let ix=0;ix<xs.length-1;ix++){
      const p=[[xs[ix],ys[iy]],[xs[ix+1],ys[iy]],[xs[ix+1],ys[iy+1]],[xs[ix],ys[iy+1]]];
      for(const k of [0,1,2,0,2,3]){
        const h=terrain.heightAt(...p[k]),v=terrain.world(p[k]);positions.push(v.x,v.y,v.z);
        const color=sand.clone().lerp(rock,Math.min(1,Math.max(0,(h-160)/1740)));
        if(h>2600)color.lerp(snow,Math.min(1,(h-2600)/1400));colors.push(color.r,color.g,color.b);
      }
    }
  }
  strip(x0-pad,x1+pad,y0-pad,y0);strip(x0-pad,x1+pad,y1,y1+pad);
  strip(x0-pad,x0,y0,y1);strip(x1,x1+pad,y0,y1);
  const geometry=new THREE.BufferGeometry();geometry.setAttribute('position',new THREE.Float32BufferAttribute(positions,3));geometry.setAttribute('color',new THREE.Float32BufferAttribute(colors,3));geometry.computeVertexNormals();
  const group=new THREE.Group();group.name='PRESENTATION_SURROUND';
  group.userData={role:'Surrounding terrain for rectangular composition only; no new locations or traversable geography',sampling:'Shared heightAt, clamped outside authored domain',defaultVisible:false};
  const mesh=new THREE.Mesh(geometry,new THREE.MeshStandardMaterial({vertexColors:true,roughness:1,flatShading:true}));mesh.name='unlocated-context-terrain';group.add(mesh);group.visible=false;
  return group;
}
