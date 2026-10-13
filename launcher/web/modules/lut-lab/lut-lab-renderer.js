/**
 * LUT 实验室 · WebGL2 3D LUT 渲染器
 *
 * 单个离屏 WebGL2 画布服务整个面板：setSource 上传图像，32^3 RGBA8 3D 纹理
 *（硬件三线性，LINEAR + CLAMP_TO_EDGE），render 后 drawImage 到各对比格。
 * 采样坐标映射 c*(31/32)+0.5/32 使硬件三线性精确等价于体素空间 c*31 的三线性插值。
 * WebGL2 不可用或初始化失败时 create 抛错，由面板显示明确错误（不静默回退 CPU）。
 *
 * v2：双集合双档采样。setDualLut(A0,A1,B0,B1) 上传「集合 A/B × 等级 floor/ceil」四张 3D 纹理，
 * setLevelMix(t) 在相邻档间 mix（生产 350ms 过渡的语义预览），setView 切换
 * 单图(A/B)/差值 |A-B|×4/分屏(uSplitX)。旧 setLut(lut) ≡ setDualLut(lut,lut,null,null)
 * + 单图 A，QA 基线（identity 逐像素恒等）不受影响。
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.LutLabRenderer = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var LUT_SIZE = 32;

    var VERT = '#version 300 es\n'
        + 'layout(location=0) in vec2 aPos;\n'
        + 'out vec2 vUv;\n'
        + 'void main() { vUv = vec2(aPos.x * 0.5 + 0.5, 0.5 - aPos.y * 0.5); gl_Position = vec4(aPos, 0.0, 1.0); }';

    // uView：0=单图（uViewB 选 A/B），1=差值 |A-B|x4，2=分屏（vUv.x < uSplitX 显 A 否则显 B）
    var FRAG = '#version 300 es\n'
        + 'precision highp float;\n'
        + 'precision highp sampler3D;\n'
        + 'uniform sampler2D uImage;\n'
        + 'uniform sampler3D uLutA0;\n'
        + 'uniform sampler3D uLutA1;\n'
        + 'uniform sampler3D uLutB0;\n'
        + 'uniform sampler3D uLutB1;\n'
        + 'uniform vec3 uDomainMin;\n'
        + 'uniform vec3 uDomainRange;\n'
        + 'uniform float uMixT;\n'
        + 'uniform int uView;\n'
        + 'uniform float uViewB;\n'
        + 'uniform float uSplitX;\n'
        + "uniform sampler2D uEdge, uHalo, uGuide;\n"
        + "uniform vec2 uPixel;\n"
        + "uniform float uFluorescent, uStrength, uWidth, uHaloStrength, uHaloRadius, uRetention, uOnly, uOriginalBase;\n"
        + "uniform float uDenoise, uSuppression;\n"
        + "uniform float uScanStrength, uScanPhase;\n"
        + "// SHARED_NV_UNDERLAY\n"
        + "// SHARED_NV_INSTRUMENT\n"
        + "uniform vec3 uContourColor;\n"
        + 'in vec2 vUv;\n'
        + 'out vec4 outColor;\n'
        + "float hi(vec3 c){return max(c.r,max(c.g,c.b));}\n"
        + "float lo(vec3 c){return min(c.r,min(c.g,c.b));}\n"
        + "vec3 fluorescent(vec3 raw, vec3 base){\n"
        + "  vec2 stroke=uPixel*max(0.,uWidth-1.)*.7;\n"
        + "  float core=texture(uEdge,vUv).r;\n"
        + "  core=max(core,texture(uEdge,vUv+vec2(stroke.x,0.)).r);\n"
        + "  core=max(core,texture(uEdge,vUv-vec2(stroke.x,0.)).r);\n"
        + "  core=max(core,texture(uEdge,vUv+vec2(0.,stroke.y)).r);\n"
        + "  core=max(core,texture(uEdge,vUv-vec2(0.,stroke.y)).r);\n"
        + "  vec2 d=vec2(0.,uPixel.y*max(.5,uHaloRadius*.65));\n"
        + "  float halo=texture(uHalo,vUv).r*.227027;\n"
        + "  halo+=(texture(uHalo,vUv+d*1.384615).r+texture(uHalo,vUv-d*1.384615).r)*.316216;\n"
        + "  halo+=(texture(uHalo,vUv+d*3.230769).r+texture(uHalo,vUv-d*3.230769).r)*.070270;\n"
        + "  float protect=smoothstep(.15,.5,(hi(raw)-lo(raw))/(hi(raw)+.02));\n"
        + "  vec3 ink=mix(uContourColor,raw/max(hi(raw),.001),protect*.38*step(.04,hi(uContourColor)-lo(uContourColor)));\n"
        + "  vec3 floorColor=mix(vec3(.02),vec3(.016,.032,.029),step(.04,hi(uContourColor)-lo(uContourColor)));\n"
        + "  vec3 scene=mix(floorColor,mix(base,raw,uOriginalBase),uOnly>.5?0.:uRetention);\n"
        + "  scene+=ink*halo*uHaloStrength*uStrength*.55*(1.-scene);\n"
        + "  return clamp(mix(scene,ink,clamp(core*uStrength*min(1.,uWidth),0.,.94)),0.,1.);\n"
        + "}\n"
        + 'void main() {\n'
        + '    vec4 c = texture(uImage, vUv);\n'
        + '    vec3 t = clamp((c.rgb - uDomainMin) / uDomainRange, 0.0, 1.0);\n'
        + '    vec3 coord = t * (' + (LUT_SIZE - 1) + '.0 / ' + LUT_SIZE + '.0) + vec3(0.5 / ' + LUT_SIZE + '.0);\n'
        + '    vec3 a = mix(texture(uLutA0, coord).rgb, texture(uLutA1, coord).rgb, uMixT);\n'
        + '    vec3 filtered=c.rgb;\n'
        + '    if(uDenoise>.5)filtered=nvUnderlayBlend(c.rgb,texture(uGuide,vUv).rgb,uSuppression);\n'
        + '    vec3 bt=clamp((filtered-uDomainMin)/uDomainRange,0.,1.);\n'
        + '    vec3 bc=bt*(31./32.)+vec3(.5/32.);\n'
        + '    vec3 b=mix(texture(uLutB0,bc).rgb,texture(uLutB1,bc).rgb,uMixT);\n'
        + '    if (uFluorescent > 0.5) b = fluorescent(filtered, b);\n'
        + '    b=clamp(nvInstrument(b,vUv,uScanStrength,uScanPhase),0.,1.);\n'
        + '    vec3 single = uViewB > 0.5 ? b : a;\n'
        + '    vec3 diffv = clamp(abs(a - b) * 4.0, 0.0, 1.0);\n'
        + '    vec3 splitv = vUv.x < uSplitX ? a : b;\n'
        + '    vec3 outRgb = uView == 1 ? diffv : (uView == 2 ? splitv : single);\n'
        + '    outColor = vec4(outRgb, c.a);\n'
        + '}';


    // BEGIN GENERATED NV_STRUCTURE (tools/generate-night-vision-structure.mjs)
    var PASS_VERT = "#version 300 es\nlayout(location=0) in vec2 aPos;\nout vec2 uv;\nflat out vec4 gaussian0,gaussian1;\nuniform float suppression;\nvoid main(){\n    uv=aPos*.5+.5;gl_Position=vec4(aPos,0.,1.);\n    // Uniform weights are evaluated for three vertices, not every pixel.\n    // Keep raw coefficients and the original summation order for parity.\n    float radius=1.8+2.2*suppression;\n    vec4 k0=exp(-.5*vec4(0,1,4,9)/(radius*radius));\n    vec4 k1=vec4(exp(-.5*vec3(16,25,36)/(radius*radius)),0);\n    float total=0.0;\n    total+=k1.z;total+=k1.y;total+=k1.x;\n    total+=k0.w;total+=k0.z;total+=k0.y;total+=k0.x;\n    total+=k0.y;total+=k0.z;total+=k0.w;\n    total+=k1.x;total+=k1.y;total+=k1.z;\n    k1.w=total;\n    \n    gaussian0=k0;gaussian1=k1;\n}";
    var STRUCTURE_SOURCE = [
        "#version 300 es",
        "precision highp float;",
        "in vec2 uv;",
        "flat in vec4 gaussian0,gaussian1;",
        "out vec4 outColor;",
        "uniform sampler2D source,guide,features;",
        "uniform vec2 edgeStep;",
        "uniform float suppression;",
        "struct NvVertex {vec2 uv;vec4 gaussian0;vec4 gaussian1;};",
        "float saturate(float x){return clamp(x,0.,1.);}",
        "vec3 nvRaw(vec2 p){return texture(source,clamp(p,0.,1.)).rgb;}",
        "vec3 nvUnderlayBlend(vec3 raw,vec3 guide,float suppression) {",
        "    // Smooth fine texture in the underlay itself. Strong material/actor",
        "    // boundaries retain original coverage instead of becoming soft halos.",
        "    vec3 difference=abs(raw-guide);",
        "    float protect=smoothstep(.18,.45,max(difference.r,max(difference.g,difference.b)));",
        "    return mix(raw,guide,smoothstep(0.0,.65,suppression)*(1.0-.75*protect));",
        "}",
        "vec3 nvAt(vec2 uv,bool structure) {",
        "    return structure?texture(guide,uv).rgb:nvRaw(uv);",
        "}",
        "vec3 nvGradient(vec2 uv,bool structure) {",
        "    vec2 d=edgeStep;",
        "    vec3 a=nvAt(uv-d,structure),b=nvAt(uv+vec2(0,-d.y),structure),c=nvAt(uv+vec2(d.x,-d.y),structure);",
        "    vec3 f=nvAt(uv+vec2(-d.x,0),structure),g=nvAt(uv+vec2(d.x,0),structure);",
        "    vec3 h=nvAt(uv+vec2(-d.x,d.y),structure),i=nvAt(uv+vec2(0,d.y),structure),j=nvAt(uv+d,structure);",
        "    vec3 gx=(c+2.0*g+j-a-2.0*f-h)*.25,gy=(h+2.0*i+j-a-2.0*b-c)*.25;",
        "    vec3 power=gx*gx+gy*gy;",
        "    // Keep chromatic boundaries as well as luminance boundaries. A single",
        "    // winning channel provides a consistent direction for the local tensor.",
        "    vec2 slope=power.r>=power.g && power.r>=power.b?vec2(gx.r,gy.r)",
        "        :(power.g>=power.b?vec2(gx.g,gy.g):vec2(gx.b,gy.b));",
        "    return vec3(slope,length(slope));",
        "}",
        "vec4 NAPS(NvVertex v) {",
        "    vec3 g=nvGradient(v.uv,false);",
        "    return vec4(g.xy*.5+.5,min(g.z,1.0),1.0);",
        "}",
        "vec3 nvGaussian(NvVertex v,vec2 direction,bool horizontal) {",
        "    vec3 sum=vec3(0,0,0);",
        "     for(int n=-6;n<=6;n++) {",
        "        int index=abs(n);",
        "        float weight=index==0?v.gaussian0.x:(index==1?v.gaussian0.y:(index==2?v.gaussian0.z",
        "            :(index==3?v.gaussian0.w:(index==4?v.gaussian1.x:(index==5?v.gaussian1.y:v.gaussian1.z)))));",
        "        vec2 p=v.uv+direction*float(n);",
        "        sum+=(horizontal?nvRaw(p):texture(guide,p).rgb)*weight;",
        "    }",
        "    return sum/v.gaussian1.w;",
        "}",
        "vec4 NHPS(NvVertex v) {return vec4(nvGaussian(v,vec2(edgeStep.x,0),true),1.0);}",
        "vec4 NVPS(NvVertex v) {return vec4(nvGaussian(v,vec2(0,edgeStep.y),false),1.0);}",
        "vec4 NJPS(NvVertex v) {",
        "    // Two rolling joint-bilateral iterations reconstruct large boundaries from",
        "    // the original image using the smoothed guide, shared by edges and underlay.",
        "    vec3 center=texture(guide,v.uv).rgb,sum=vec3(0,0,0);",
        "    float total=0.0,radius=1.8+2.2*suppression;",
        "     for(int y=-2;y<=2;y++)  for(int x=-2;x<=2;x++) {",
        "        vec2 offset=vec2(x,y)*2.0;",
        "        vec2 p=v.uv+offset*edgeStep;",
        "        vec3 delta=center-texture(guide,p).rgb;",
        "        float weight=exp(-dot(offset,offset)/(2.0*radius*radius)-dot(delta,delta)/(.16*.16*2.0));",
        "        sum+=nvRaw(p)*weight;total+=weight;",
        "    }",
        "    return vec4(sum/max(total,.00001),1.0);",
        "}",
        "vec4 NEPS(NvVertex v) {",
        "    float edge;",
        "     if(suppression<=0.0) {",
        "        float magnitude=nvGradient(v.uv,false).z;",
        "        edge=smoothstep(.018*.65,.018*2.2,magnitude);",
        "    } else {",
        "        vec3 f=texture(features,v.uv).rgb;",
        "        vec2 fine=f.xy*2.0-1.0;",
        "        vec3 structure=nvGradient(v.uv,true);",
        "        float xx=0.0,yy=0.0,xy=0.0,density=0.0;",
        "         for(int y=-1;y<=1;y++)  for(int x=-1;x<=1;x++) {",
        "            float weight=float((x==0?2:1)*(y==0?2:1))/16.;",
        "            vec3 feature=texture(features,v.uv+vec2(x,y)*edgeStep*3.0).rgb;",
        "            vec2 slope=feature.xy*2.0-1.0;",
        "            xx+=slope.x*slope.x*weight;yy+=slope.y*slope.y*weight;xy+=slope.x*slope.y*weight;",
        "            float relativeDensity=smoothstep(max(.008,f.z*.25),max(.025,f.z*.8),feature.z);",
        "            density+=max(smoothstep(.025,.085,feature.z),relativeDensity)*weight;",
        "        }",
        "        float coherence=sqrt((xx-yy)*(xx-yy)+4.0*xy*xy)/(xx+yy+.00001);",
        "        // Sparse, coherent thin strokes survive even if the scale filter loses",
        "        // them. Dense isotropic gravel/mesh does not get this detail bypass.",
        "        vec2 tangent=vec2(-fine.y,fine.x)/max(length(fine),.00001);",
        "        float along=0.0;",
        "         for(int n=0;n<4;n++) {",
        "            float distance=n<2?1.5:3.0;",
        "            float side=n==0 || n==2?1.0:-1.0;",
        "            vec3 neighbor=texture(features,v.uv+tangent*edgeStep*distance*side).rgb;",
        "            float agreement=max(0.0,dot(fine,neighbor.xy*2.0-1.0))/(f.z*neighbor.z+.00001);",
        "            along+=smoothstep(.35,.8,agreement)*smoothstep(.025,.085,neighbor.z)*.25;",
        "        }",
        "        float thin=max(smoothstep(.45,.85,coherence),smoothstep(.35,.8,along))",
        "            *(1.0-smoothstep(.45,.82,density));",
        "        float threshold=.018+.055*suppression;",
        "        float raw=smoothstep(threshold*.65,threshold*2.2,f.z);",
        "        float agreement=abs(dot(fine,structure.xy))/(f.z*structure.z+.00001);",
        "        float persistence=smoothstep(.14,.50,structure.z/max(f.z,.04));",
        "        // The structure scale decides eligibility, not stroke position or",
        "        // brightness. Draw the original gradient so narrow real boundaries",
        "        // are not dimmed or displaced by the low-frequency guide.",
        "        // Only sustained structures and sparse coherent strokes receive strong",
        "        // emphasis. Actor silhouettes are protected by the semantic Flash rim,",
        "        // rather than by brightening every discarded environmental detail.",
        "        float textureEvidence=smoothstep(.55,.9,density)*(1.0-smoothstep(.65,.95,coherence));",
        "        float detailFloor=mix(.025,.002,textureEvidence);",
        "        float keep=raw*max(detailFloor,max((.6+.4*smoothstep(.2,.8,agreement))*persistence,thin*.95));",
        "        // Do not restore contrast to low-confidence residual texture: the old",
        "        // soft boost made dense ground shimmer even after successful filtering.",
        "        edge=mix(raw,keep,smoothstep(0.0,.65,suppression));",
        "    }",
        "    vec2 d=edgeStep;",
        "    // Quiet the viewport border; clamped sampling must not invent a frame.",
        "    vec2 border=min(v.uv,1.0-v.uv)/d;",
        "    edge*=saturate(min(border.x,border.y)-.5);",
        "    return vec4(edge,0,0,1);",
        "}"
    ].join('\n');
    function structureFragment(entry) {return STRUCTURE_SOURCE+'\nvoid main(){NvVertex v;v.uv=uv;v.gaussian0=gaussian0;v.gaussian1=gaussian1;outColor='+entry+'(v);}';}
    var EDGE_FRAGMENT=structureFragment('NEPS');
    var FEATURE_FRAGMENT=structureFragment('NAPS');
    var HORIZONTAL_FRAGMENT=structureFragment('NHPS');
    var VERTICAL_FRAGMENT=structureFragment('NVPS');
    var JOINT_FRAGMENT=structureFragment('NJPS');
    var UNDERLAY_SOURCE="vec3 nvUnderlayBlend(vec3 raw,vec3 guide,float suppression) {\n    // Smooth fine texture in the underlay itself. Strong material/actor\n    // boundaries retain original coverage instead of becoming soft halos.\n    vec3 difference=abs(raw-guide);\n    float protect=smoothstep(.18,.45,max(difference.r,max(difference.g,difference.b)));\n    return mix(raw,guide,smoothstep(0.0,.65,suppression)*(1.0-.75*protect));\n}";
    var INSTRUMENT_SOURCE="vec3 nvInstrument(vec3 color,vec2 uv,float strength,float phase) {\n    if(strength<=0.0)return color;\n    // Eight-logical-pixel rows drift by one row per cycle, with analytic pixel\n    // coverage. Never feed instrument texture back into structure detection.\n    float y=uv.y*576.0;\n    float footprint=max(fwidth(y),0.001);\n    float aperture=3.14159265*footprint/8.0;\n    float coverage=(sin(aperture)/aperture)*(1.0-smoothstep(2.0,4.0,footprint));\n    float rows=sin(y*0.785398163-phase*6.28318531)*coverage;\n    // A distinct descending front, followed by a longer fading trail. Both\n    // enter/exit outside the viewport, so the cycle has no brightness jump.\n    float offset=y-(phase*696.0-24.0);\n    float frontWidth=max(1.5,footprint*0.5);\n    float front=1.0-smoothstep(frontWidth,frontWidth+3.0,abs(offset));\n    float trail=(1.0-smoothstep(0.0,96.0,max(-offset,0.0)))\n        *(1.0-smoothstep(-2.0,4.0,offset));\n    // Multiplicative modulation preserves ink and material colors. The stronger\n    // front stays local; the rest of the camera retains the existing fine rows.\n    return color*(1.0+strength*(0.5*rows+2.0*front+0.85*trail));\n}";
    var INSTRUMENT_CYCLE_MS=7000;
    // END GENERATED NV_STRUCTURE
    var BLUR_FRAGMENT = [
        "#version 300 es",
        "",
        "precision highp float;",
        "in vec2 uv;",
        "out vec4 outColor;",
        "uniform sampler2D source;",
        "uniform vec2 direction;",
        "void main(){",
        "  float a=texture(source,uv).r*.227027;",
        "  a+=(texture(source,uv+direction*1.384615).r+texture(source,uv-direction*1.384615).r)*.316216;",
        "  a+=(texture(source,uv+direction*3.230769).r+texture(source,uv-direction*3.230769).r)*.070270;",
        "  outColor=vec4(a,a,a,1.);",
        "}"
    ].join('\n');
    function normalizeFluorescent(value) {
        value = value || {};
        var out = {
            enabled: value.enabled === true,
            strength: 2, width: 2.2, halo: 1, radius: 1,
            suppression: 1, retention: .15, scanStrength: 0, color: '#75ff7e',
            base: 'lut', only: value.only === true, denoise: value.denoise === true
        };
        var ranges = {
            strength: [0, 2], width: [.7, 3], halo: [0, 1],
            radius: [1, 6], suppression: [0, 1], retention: [0, 1], scanStrength: [0, .08]
        };
        Object.keys(ranges).forEach(function(key) {
            if (typeof value[key] === 'number' && Number.isFinite(value[key])) {
                out[key] = Math.max(ranges[key][0], Math.min(ranges[key][1], value[key]));
            }
        });
        if (/^#[0-9a-f]{6}$/i.test(value.color || '')) out.color = value.color;
        if (value.base === 'original') out.base = 'original';
        return out;
    }

    function compile(gl, type, source) {
        var shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
            var log = gl.getShaderInfoLog(shader);
            gl.deleteShader(shader);
            throw new Error('LUT shader 编译失败: ' + log);
        }
        return shader;
    }

    function create(options) {
        options = options || {};
        if (typeof document === 'undefined') throw new Error('LUT 渲染器需要浏览器环境');
        var canvas = options.canvas || document.createElement('canvas');
        var gl = canvas.getContext('webgl2', { preserveDrawingBuffer: true, premultipliedAlpha: false });
        if (!gl) throw new Error('当前环境不支持 WebGL2（需要 3D 纹理做硬件三线性 LUT 采样）');

        var program = gl.createProgram();
        gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, VERT));
        gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, FRAG.replace('// SHARED_NV_UNDERLAY', UNDERLAY_SOURCE).replace('// SHARED_NV_INSTRUMENT', INSTRUMENT_SOURCE)));
        gl.linkProgram(program);
        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
            throw new Error('LUT shader 链接失败: ' + gl.getProgramInfoLog(program));
        }
        gl.useProgram(program);

        var quad = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, quad);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

        var imageTex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, imageTex);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        function makeLutTexture() {
            var tex = gl.createTexture();
            gl.bindTexture(gl.TEXTURE_3D, tex);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
            return tex;
        }
        var lutTexA0 = makeLutTexture();
        var lutTexA1 = makeLutTexture();
        var lutTexB0 = makeLutTexture();
        var lutTexB1 = makeLutTexture();

        gl.uniform1i(gl.getUniformLocation(program, 'uImage'), 0);
        gl.uniform1i(gl.getUniformLocation(program, 'uLutA0'), 1);
        gl.uniform1i(gl.getUniformLocation(program, 'uLutA1'), 2);
        gl.uniform1i(gl.getUniformLocation(program, 'uLutB0'), 3);
        gl.uniform1i(gl.getUniformLocation(program, 'uLutB1'), 4);
        var uDomainMin = gl.getUniformLocation(program, 'uDomainMin');
        var uDomainRange = gl.getUniformLocation(program, 'uDomainRange');
        gl.uniform3f(uDomainMin, 0, 0, 0);
        gl.uniform3f(uDomainRange, 1, 1, 1);
        var uMixT = gl.getUniformLocation(program, 'uMixT');
        var uView = gl.getUniformLocation(program, 'uView');
        var uViewB = gl.getUniformLocation(program, 'uViewB');
        var uSplitX = gl.getUniformLocation(program, 'uSplitX');
        gl.uniform1f(uMixT, 0);
        gl.uniform1i(uView, 0);
        gl.uniform1f(uViewB, 0);
        gl.uniform1f(uSplitX, 0.5);


        var fxUniforms = {};
        ['uEdge', 'uHalo', 'uPixel', 'uFluorescent', 'uStrength', 'uWidth',
            'uHaloStrength', 'uHaloRadius', 'uRetention', 'uOnly',
            'uOriginalBase', 'uContourColor', 'uGuide', 'uDenoise', 'uSuppression', 'uScanStrength', 'uScanPhase'].forEach(function(name) {
            fxUniforms[name] = gl.getUniformLocation(program, name);
        });
        gl.uniform1i(fxUniforms.uEdge, 5);
        gl.uniform1i(fxUniforms.uGuide, 7);
        gl.uniform1i(fxUniforms.uHalo, 6);
        var effect = normalizeFluorescent(), viewValue = 'A', scanPhase = 0;
        var sourceRevision = 0, sourceObject = null, sourceStamp;
        var targets = [], targetSize = '', contourKey = '', maskWidth = 0, maskHeight = 0;
        var floatTargets = gl.getExtension('EXT_color_buffer_float');
        function makePass(fragment, names) {
            var p = gl.createProgram();
            var v = compile(gl, gl.VERTEX_SHADER, PASS_VERT);
            var f = compile(gl, gl.FRAGMENT_SHADER, fragment);
            gl.attachShader(p, v);
            gl.attachShader(p, f);
            gl.linkProgram(p);
            gl.deleteShader(v);
            gl.deleteShader(f);
            if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
            var uniforms = {};
            names.forEach(function(name) { uniforms[name] = gl.getUniformLocation(p, name); });
            return { program: p, u: uniforms };
        }
        var structureUniforms = ['source', 'guide', 'features', 'edgeStep', 'suppression'];
        var edgePass = makePass(EDGE_FRAGMENT, structureUniforms);
        var featurePass = makePass(FEATURE_FRAGMENT, structureUniforms);
        var horizontalPass = makePass(HORIZONTAL_FRAGMENT, structureUniforms);
        var verticalPass = makePass(VERTICAL_FRAGMENT, structureUniforms);
        var jointPass = makePass(JOINT_FRAGMENT, structureUniforms);
        var blurPass = makePass(BLUR_FRAGMENT, ['source', 'direction']);
        // A sampler override keeps the original image texture NEAREST for the
        // exact LUT baseline, while the contour pass uses smooth neighbouring samples.
        var edgeSampler = gl.createSampler();
        gl.samplerParameteri(edgeSampler, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.samplerParameteri(edgeSampler, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.samplerParameteri(edgeSampler, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.samplerParameteri(edgeSampler, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        var width = 0, height = 0;

        function setSource(source, sourceWidth, sourceHeight, revision) {
            // Explicit revisions let the main view, inspector and ten film tiles
            // share one upload. Callers without a revision retain the old semantics.
            if (revision != null && sourceObject === source && sourceStamp === revision
                && width === (sourceWidth || source.width) && height === (sourceHeight || source.height)) return;
            sourceObject = source;
            sourceStamp = revision;
            sourceRevision++;
            width = sourceWidth || source.width;
            height = sourceHeight || source.height;
            if (!width || !height) throw new Error('源图像尺寸非法');
            canvas.width = width;
            canvas.height = height;
            gl.viewport(0, 0, width, height);
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, imageTex);
            gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, source);
        }

        // lut: {rgba:Uint8Array(32^3*4), domainMin?, domainMax?}（R 分量变化最快）
        function checkLut(lut) {
            if (!lut || !lut.rgba || lut.rgba.length !== LUT_SIZE * LUT_SIZE * LUT_SIZE * 4) {
                throw new Error('LUT 必须是 32^3 RGBA8（' + LUT_SIZE * LUT_SIZE * LUT_SIZE * 4 + ' 字节）');
            }
        }
        var identity = null; // 懒建：B 侧缺省/单 LUT 兼容路径用
        function identityLut() {
            if (!identity) identity = { rgba: identityRgba8(), domainMin: [0, 0, 0], domainMax: [1, 1, 1] };
            return identity;
        }
        function uploadLut(unit, tex, lut) {
            gl.activeTexture(gl.TEXTURE0 + unit);
            gl.bindTexture(gl.TEXTURE_3D, tex);
            gl.texImage3D(gl.TEXTURE_3D, 0, gl.RGBA8, LUT_SIZE, LUT_SIZE, LUT_SIZE, 0,
                gl.RGBA, gl.UNSIGNED_BYTE, lut.rgba);
        }
        function applyDomain(lut) {
            var min = lut.domainMin || [0, 0, 0];
            var max = lut.domainMax || [1, 1, 1];
            gl.uniform3f(uDomainMin, min[0], min[1], min[2]);
            gl.uniform3f(uDomainRange, max[0] - min[0], max[1] - min[1], max[2] - min[2]);
        }
        // v2 主 API：A/B 集合 x 等级 floor/ceil。null 侧回退恒等；domain 取 a0（集合内应同域）。
        function setDualLut(a0, a1, b0, b1) {
            a0 = a0 || identityLut(); a1 = a1 || a0;
            b0 = b0 || identityLut(); b1 = b1 || b0;
            checkLut(a0); checkLut(a1); checkLut(b0); checkLut(b1);
            uploadLut(1, lutTexA0, a0);
            uploadLut(2, lutTexA1, a1);
            uploadLut(3, lutTexB0, b0);
            uploadLut(4, lutTexB1, b1);
            applyDomain(a0);
        }
        // 旧单 LUT 路径（QA 基线/胶片条整档）：A0=A1=lut，B 侧恒等，mix=0。
        function setLut(lut) {
            checkLut(lut);
            setDualLut(lut, lut, null, null);
            gl.uniform1f(uMixT, 0);
        }
        // 等级小数部分 0..1（相邻档 mix）
        function setLevelMix(t) {
            gl.uniform1f(uMixT, Math.max(0, Math.min(1, t)));
        }
        // view: 'A' | 'B' | 'diff' | 'split'；splitX 仅 split 用（0..1）
        function setView(view, splitX) {
            viewValue = view;
            gl.uniform1i(uView, view === 'diff' ? 1 : (view === 'split' ? 2 : 0));
            gl.uniform1f(uViewB, view === 'B' ? 1 : 0);
            gl.uniform1f(uSplitX, typeof splitX === 'number' ? Math.max(0, Math.min(1, splitX)) : 0.5);
        }


        function setFluorescent(value) { effect = normalizeFluorescent(value); }
        function setScanPhase(value) { scanPhase = Number.isFinite(value) ? ((value % 1) + 1) % 1 : 0; }
        function disposeTargets() {
            targets.forEach(function(t) {
                gl.deleteTexture(t.texture);
                gl.deleteFramebuffer(t.framebuffer);
            });
            targets = [];
            targetSize = '';
            contourKey = '';
        }
        function contourPasses() {
            var key = [width, height, sourceRevision, effect.suppression, effect.radius, effect.strength > 0].join(':');
            if (key === contourKey) return;
            if (targetSize !== width + 'x' + height) {
                disposeTargets();
                maskWidth = Math.min(1024, width);
                maskHeight = Math.min(576, height);
                gl.activeTexture(gl.TEXTURE5);
                for (var i = 0; i < 5; i++) {
                    var texture = gl.createTexture(), framebuffer = gl.createFramebuffer();
                    gl.bindTexture(gl.TEXTURE_2D, texture);
                    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
                    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
                    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
                    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
                    var floating = i === 4 && floatTargets;
                    gl.texImage2D(gl.TEXTURE_2D, 0, floating ? gl.RGBA16F : gl.RGBA8,
                        maskWidth, maskHeight, 0, gl.RGBA, floating ? gl.HALF_FLOAT : gl.UNSIGNED_BYTE, null);
                    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
                    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
                    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE)
                        throw new Error('荧光预览缓冲区未能建立');
                    targets.push({ texture: texture, framebuffer: framebuffer });
                }
                targetSize = width + 'x' + height;
            }
            gl.viewport(0, 0, maskWidth, maskHeight);
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, imageTex);
            gl.bindSampler(0, edgeSampler);
            gl.bindSampler(1, edgeSampler);
            gl.bindSampler(2, edgeSampler);
            function drawStructure(pass, target, guide, features) {
                gl.useProgram(pass.program);
                gl.bindFramebuffer(gl.FRAMEBUFFER, targets[target].framebuffer);
                gl.uniform1i(pass.u.source, 0);
                gl.uniform1i(pass.u.guide, 1);
                gl.uniform1i(pass.u.features, 2);
                gl.uniform2f(pass.u.edgeStep, 1 / maskWidth, 1 / maskHeight);
                gl.uniform1f(pass.u.suppression, effect.suppression);
                gl.activeTexture(gl.TEXTURE1);
                gl.bindTexture(gl.TEXTURE_2D, guide == null ? imageTex : targets[guide].texture);
                gl.activeTexture(gl.TEXTURE2);
                gl.bindTexture(gl.TEXTURE_2D, features == null ? imageTex : targets[features].texture);
                gl.drawArrays(gl.TRIANGLES, 0, 3);
            }
            if (effect.suppression > 0) {
                if (effect.strength > 0) drawStructure(featurePass, 4, null, null);
                drawStructure(horizontalPass, 2, null, null);
                drawStructure(verticalPass, 3, 2, null);
                drawStructure(jointPass, 2, 3, null);
                drawStructure(jointPass, 3, 2, null);
            }
            if (effect.strength > 0) drawStructure(edgePass, 0, effect.suppression > 0 ? 3 : null, effect.suppression > 0 ? 4 : null);
            else {gl.bindFramebuffer(gl.FRAMEBUFFER, targets[0].framebuffer);gl.clearColor(0,0,0,1);gl.clear(gl.COLOR_BUFFER_BIT);}
            gl.useProgram(blurPass.program);
            gl.bindFramebuffer(gl.FRAMEBUFFER, targets[1].framebuffer);
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, targets[0].texture);
            gl.uniform1i(blurPass.u.source, 0);
            gl.uniform2f(blurPass.u.direction, Math.max(.5, effect.radius * .65) / maskWidth, 0);
            gl.drawArrays(gl.TRIANGLES, 0, 3);
            gl.bindSampler(0, null);
            gl.bindSampler(1, null);
            gl.bindSampler(2, null);
            gl.bindFramebuffer(gl.FRAMEBUFFER, null);
            gl.useProgram(program);
            contourKey = key;
        }
        function dispose() {
            disposeTargets();
            gl.deleteProgram(edgePass.program);
            gl.deleteProgram(featurePass.program);
            gl.deleteProgram(horizontalPass.program);
            gl.deleteProgram(verticalPass.program);
            gl.deleteProgram(jointPass.program);
            gl.deleteProgram(blurPass.program);
            gl.deleteSampler(edgeSampler);
            var ext = gl.getExtension('WEBGL_lose_context');
            if (ext) ext.loseContext();
        }

        function render() {
            if (!width || !height) throw new Error('尚未设置源图像');
            var active = effect.enabled && (effect.strength > 0 || effect.denoise) && viewValue !== 'A';
            var denoise = active && effect.denoise && !effect.only && effect.retention < 1 && effect.suppression > 0;
            if (active) contourPasses();
            gl.bindFramebuffer(gl.FRAMEBUFFER, null);
            gl.viewport(0, 0, width, height);
            gl.useProgram(program);
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, imageTex);
            gl.activeTexture(gl.TEXTURE5);
            gl.bindTexture(gl.TEXTURE_2D, active ? targets[0].texture : imageTex);
            gl.activeTexture(gl.TEXTURE6);
            gl.bindTexture(gl.TEXTURE_2D, active ? targets[1].texture : imageTex);
            gl.activeTexture(gl.TEXTURE7);
            gl.bindTexture(gl.TEXTURE_2D, denoise ? targets[3].texture : imageTex);
            gl.uniform1f(fxUniforms.uDenoise, denoise ? 1 : 0);
            gl.uniform1f(fxUniforms.uSuppression, effect.suppression);
            gl.uniform1f(fxUniforms.uScanStrength, effect.enabled ? effect.scanStrength : 0);
            gl.uniform1f(fxUniforms.uScanPhase, scanPhase);
            gl.uniform2f(fxUniforms.uPixel, 1 / (maskWidth || width), 1 / (maskHeight || height));
            gl.uniform1f(fxUniforms.uFluorescent, active ? 1 : 0);
            gl.uniform1f(fxUniforms.uStrength, effect.strength);
            gl.uniform1f(fxUniforms.uWidth, effect.width);
            gl.uniform1f(fxUniforms.uHaloStrength, effect.halo);
            gl.uniform1f(fxUniforms.uHaloRadius, effect.radius);
            gl.uniform1f(fxUniforms.uRetention, effect.retention);
            gl.uniform1f(fxUniforms.uOnly, effect.only ? 1 : 0);
            gl.uniform1f(fxUniforms.uOriginalBase, effect.base === 'original' ? 1 : 0);
            var channels = [1, 3, 5].map(function(i) { return parseInt(effect.color.slice(i, i + 2), 16) / 255; });
            gl.uniform3f(fxUniforms.uContourColor, channels[0], channels[1], channels[2]);

            gl.drawArrays(gl.TRIANGLES, 0, 3);
            return canvas;
        }

        // 顶行在前（readPixels 原始结果为底行在前，此处翻回图像坐标系）
        function readPixels() {
            var raw = new Uint8Array(width * height * 4);
            gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, raw);
            var out = new Uint8Array(raw.length);
            var stride = width * 4;
            for (var y = 0; y < height; y++) {
                out.set(raw.subarray((height - 1 - y) * stride, (height - y) * stride), y * stride);
            }
            return out;
        }

        return {
            canvas: canvas,
            gl: gl,
            setSource: setSource,
            setLut: setLut,
            setDualLut: setDualLut,
            setLevelMix: setLevelMix,
            setView: setView,
            render: render,
            setFluorescent: setFluorescent,
            setScanPhase: setScanPhase,
            dispose: dispose,
            readPixels: readPixels,
            size: function() { return { width: width, height: height }; }
        };
    }

    // 32^3 恒等 LUT（RGBA8，R 最快）：identity 输出 == 输入的 QA 基线也用它。
    function identityRgba8() {
        var rgba = new Uint8Array(LUT_SIZE * LUT_SIZE * LUT_SIZE * 4);
        var i = 0;
        for (var b = 0; b < LUT_SIZE; b++) for (var g = 0; g < LUT_SIZE; g++) for (var r = 0; r < LUT_SIZE; r++) {
            rgba[i++] = Math.round(r / (LUT_SIZE - 1) * 255);
            rgba[i++] = Math.round(g / (LUT_SIZE - 1) * 255);
            rgba[i++] = Math.round(b / (LUT_SIZE - 1) * 255);
            rgba[i++] = 255;
        }
        return rgba;
    }

    return { create: create, LUT_SIZE: LUT_SIZE, identityRgba8: identityRgba8, normalizeFluorescent: normalizeFluorescent, scanCycleMs: INSTRUMENT_CYCLE_MS };
});
