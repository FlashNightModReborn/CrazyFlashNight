import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

// The native shader is the authored algorithm. Translate only its deliberately
// small shared subset; a new native construct must be supported here explicitly.
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const shader=readFileSync(resolve(root,'launcher/native/world-compositor/NightVisionShader.h'),'utf8');
const target=resolve(root,'launcher/web/modules/lut-lab/lut-lab-renderer.js');
const stage=readFileSync(resolve(root,'launcher/native/world-compositor/NightVisionStage.h'),'utf8');
const scanCycle=Number(stage.match(/constexpr double NightVisionScanCycleSeconds=([0-9.]+);/)?.[1]);
if(!Number.isFinite(scanCycle) || scanCycle<=0)throw new Error('Missing native instrument cycle');
let body=shader.split('// BEGIN NV_STRUCTURE:')[1]?.split('\n').slice(1).join('\n').split('// END NV_STRUCTURE')[0];
if(!body)throw new Error('Missing native structure shader boundaries');
for(const [resource,replacement] of [['nvGuide','guide'],['nvFeatures','features']]) {
  const start=resource+'.SampleLevel(';
  while(body.includes(start)) {
    const at=body.indexOf(start),open=at+start.length-1;
    let depth=1,end=open+1;
    for(;depth && end<body.length;end++){if(body[end]=='(')depth++;else if(body[end]==')')depth--;}
    const args=body.slice(open+1,end-1);
    if(!args.startsWith('nvLinear,')||!args.endsWith(',0'))throw new Error('Unsupported SampleLevel: '+args);
    body=body.slice(0,at)+'texture('+replacement+','+args.slice(9,-2)+')'+body.slice(end);
  }
}
body=body.replace(/\bfloat([234])\b/g,(_,n)=>'vec'+n)
  .replace(/:SV_TARGET/g,'').replace(/\[(?:unroll|branch)\]/g,'')
  .replace(/nvA\.w/g,'suppression').replace(/nvE\.xy/g,'edgeStep')
  .replace(/nvE\.x\b/g,'edgeStep.x').replace(/nvE\.y\b/g,'edgeStep.y')
  .replace(/\blerp\(/g,'mix(');
if(/SampleLevel|SV_|\bnv[AE]\.|\[unroll\]/.test(body))throw new Error('Unsupported HLSL construct in shared shader');
const blend=body.match(/vec3 nvUnderlayBlend\([^]*?\n\}/)?.[0];
if(!blend)throw new Error('Missing shared underlay blend');
let instrument=shader.split('// BEGIN NV_INSTRUMENT:')[1]?.split('\n').slice(1).join('\n').split('// END NV_INSTRUMENT')[0];
if(!instrument)throw new Error('Missing native instrument shader boundaries');
instrument=instrument.replace(/\bfloat([234])\b/g,(_,n)=>'vec'+n);
let kernel=shader.split('// BEGIN NV_KERNEL:')[1]?.split('\n').slice(1).join('\n').split('// END NV_KERNEL')[0];
if(!kernel)throw new Error('Missing native vertex kernel boundaries');
kernel=kernel.replace(/\bfloat([234])\b/g,(_,n)=>'vec'+n).replace(/\[unroll\]/g,'').replace(/nvA\.w/g,'suppression');
const vertex=`#version 300 es
layout(location=0) in vec2 aPos;
out vec2 uv;
flat out vec4 gaussian0,gaussian1;
uniform float suppression;
void main(){
    uv=aPos*.5+.5;gl_Position=vec4(aPos,0.,1.);
${kernel}
    gaussian0=k0;gaussian1=k1;
}`;
const prefix=`#version 300 es
precision highp float;
in vec2 uv;
flat in vec4 gaussian0,gaussian1;
out vec4 outColor;
uniform sampler2D source,guide,features;
uniform vec2 edgeStep;
uniform float suppression;
struct NvVertex {vec2 uv;vec4 gaussian0;vec4 gaussian1;};
float saturate(float x){return clamp(x,0.,1.);}
vec3 nvRaw(vec2 p){return texture(source,clamp(p,0.,1.)).rgb;}
`;
const generated=`    // BEGIN GENERATED NV_STRUCTURE (tools/generate-night-vision-structure.mjs)
    var PASS_VERT = ${JSON.stringify(vertex)};
    var STRUCTURE_SOURCE = [
${(prefix+body).trimEnd().split('\n').map(line=>'        '+JSON.stringify(line)).join(',\n')}
    ].join('\\n');
    function structureFragment(entry) {return STRUCTURE_SOURCE+'\\nvoid main(){NvVertex v;v.uv=uv;v.gaussian0=gaussian0;v.gaussian1=gaussian1;outColor='+entry+'(v);}';}
    var EDGE_FRAGMENT=structureFragment('NEPS');
    var FEATURE_FRAGMENT=structureFragment('NAPS');
    var HORIZONTAL_FRAGMENT=structureFragment('NHPS');
    var VERTICAL_FRAGMENT=structureFragment('NVPS');
    var JOINT_FRAGMENT=structureFragment('NJPS');
    var UNDERLAY_SOURCE=${JSON.stringify(blend)};
    var INSTRUMENT_SOURCE=${JSON.stringify(instrument.trim())};
    var INSTRUMENT_CYCLE_MS=${scanCycle*1000};
    // END GENERATED NV_STRUCTURE
`;
const original=readFileSync(target,'utf8');
const pattern=original.includes('// BEGIN GENERATED NV_STRUCTURE')
  ?/    \/\/ BEGIN GENERATED NV_STRUCTURE[\s\S]*?    \/\/ END GENERATED NV_STRUCTURE\r?\n/
  :/    \/\/ Same contour recipe[\s\S]*?(?=    var BLUR_FRAGMENT)/;
if(!pattern.test(original))throw new Error('Missing renderer generated block boundaries');
const next=original.replace(pattern,generated.replace(/\n/g,original.includes('\r\n')?'\r\n':'\n'));
if(process.argv.includes('--check')){
  if(original!==next)throw new Error('LUT laboratory structure shaders are stale');
  console.log('Night vision structure shaders match the native source');
}else{
  writeFileSync(target,next);console.log('Generated LUT laboratory structure shaders from native source');
}
