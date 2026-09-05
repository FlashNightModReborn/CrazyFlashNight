// PM19 质数幻方 WebGL2 背景渲染器（Launcher 启动引导背景层）
// 移植自 tmp/prime-magic-eval/prime-magic-visual-demo/web/renderer.ts（TS → JS），改动点：
//   - 配色换血：基础数字 DLS 蓝（#3dd5ff 调暗一档）、行/列/对角高亮骨白-琥珀（#c8b28a）、故障锈红（#b83a2e）
//   - 整体亮度较参考实现压暗约 35%（FRAG_DIM = 0.65）：参考实现是主角，本层是背景
//   - 构造参数 maxDevicePixelRatio 默认 1.0（背景层不需要高分渲染）
// 契约：361 instances 单 draw call；数字在 fragment shader 整数拆位；digitSlots = 8。

const VERTEX_SHADER = `#version 300 es
layout(location = 0) in vec2 aCorner;
layout(location = 1) in uvec2 aCell;
layout(location = 2) in uint aValue;

uniform float uGridSize;
uniform float uTime;
uniform int uPhase;
uniform float uPhaseProgress;
uniform float uFaultIntensity;
uniform float uSwapPulse;
uniform float uSpin;
uniform float uMirror;
uniform bool uEffects;

out vec2 vLocal;
flat out uvec2 vCell;
flat out uint vValue;
flat out float vHash;
flat out float vPulse;

float hash11(float value) {
  return fract(sin(value * 127.1) * 43758.5453123);
}

float hash21(vec2 value) {
  return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
  vec2 grid = vec2(aCell) + aCorner;
  float phaseFault = (uPhase == 0 || uPhase == 5 || uPhase == 6) ? uFaultIntensity : 0.0;
  if (uEffects && phaseFault > 0.001) {
    float tick = floor(uTime * 21.0);
    float rowGate = step(0.72, hash11(float(aCell.y) * 19.7 + tick * 3.1));
    float rowShift = (hash11(float(aCell.y) * 7.3 + tick) - 0.5) * 0.22 * rowGate;
    grid.x += rowShift * phaseFault;
  }

  // 换盘转场脉冲：瞬时微细故障位移（峰值 0.045 格，远低于 FAULT 相位的 0.22）
  if (uEffects && uSwapPulse > 0.001) {
    float pulseTick = floor(uTime * 30.0);
    grid.x += (hash11(float(aCell.y) * 13.7 + float(aCell.x) * 5.1 + pulseTick) - 0.5) * 0.09 * uSwapPulse;
  }

  // 二面体变轨：绕棋盘中心（size/2，保证 90° 整倍角下精确落回原位）旋转 / 水平镜像。
  // 动画结束瞬间 CPU 侧把棋盘数据替换为对应变换并归零 uSpin / uMirror，视觉无缝。
  if (uSpin != 0.0 || uMirror != 1.0) {
    vec2 centered = grid - vec2(uGridSize * 0.5);
    centered.x *= uMirror;
    float spinSin = sin(uSpin);
    float spinCos = cos(uSpin);
    grid = vec2(
      spinCos * centered.x - spinSin * centered.y,
      spinSin * centered.x + spinCos * centered.y
    ) + vec2(uGridSize * 0.5);
  }

  vec2 clip = grid / uGridSize * 2.0 - 1.0;
  clip.y = -clip.y;
  gl_Position = vec4(clip, 0.0, 1.0);

  vLocal = aCorner;
  vCell = aCell;
  vValue = aValue;
  vHash = hash21(vec2(aCell));
  vPulse = 0.91 + 0.09 * sin(uTime * 2.4 + float(aCell.x * 3u + aCell.y * 5u) * 0.17);
}`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;
precision highp int;

uniform sampler2D uGlyphAtlas;
uniform float uTime;
uniform float uGridSize;
uniform int uDigitSlots;
uniform bool uEffects;
uniform int uPhase;
uniform float uPhaseProgress;
uniform int uActiveRow;
uniform int uActiveColumn;
uniform float uFaultIntensity;
uniform float uSwapPulse;
uniform float uSignalIntensity;

in vec2 vLocal;
flat in uvec2 vCell;
flat in uint vValue;
flat in float vHash;
flat in float vPulse;
out vec4 outColor;

uint decimalDivisor(int power) {
  if (power == 9) return 1000000000u;
  if (power == 8) return 100000000u;
  if (power == 7) return 10000000u;
  if (power == 6) return 1000000u;
  if (power == 5) return 100000u;
  if (power == 4) return 10000u;
  if (power == 3) return 1000u;
  if (power == 2) return 100u;
  if (power == 1) return 10u;
  return 1u;
}

float hash21(vec2 value) {
  return fract(sin(dot(value, vec2(41.7, 289.1))) * 951.135664);
}

void main() {
  int slot = clamp(int(floor(vLocal.x * float(uDigitSlots))), 0, uDigitSlots - 1);
  uint divisor = decimalDivisor(uDigitSlots - 1 - slot);
  uint digit = (vValue / divisor) % 10u;
  bool visibleDigit = slot == uDigitSlots - 1 || vValue >= divisor;

  vec2 glyphUv = vec2(
    (float(digit) + fract(vLocal.x * float(uDigitSlots))) * 0.1,
    vLocal.y
  );

  float fault = uEffects ? uFaultIntensity : 0.0;
  float split = 0.0035 * fault;
  // iGPU 优化：色差分离只在高故障相位（FAULT / RESCRAMBLE / 启动扰动）采样，
  // 环境态 fault 0.18 不触发，省每像素 2 次纹理采样（分支条件为 uniform，全屏一致）
  bool splitOn = fault > 0.3;
  float glyphBase = visibleDigit ? texture(uGlyphAtlas, glyphUv).a : 0.0;
  float glyphR = (visibleDigit && splitOn) ? texture(uGlyphAtlas, glyphUv + vec2(split, 0.0)).a : 0.0;
  float glyphB = (visibleDigit && splitOn) ? texture(uGlyphAtlas, glyphUv - vec2(split, 0.0)).a : 0.0;

  vec2 cell = vec2(vCell);
  float rowMask = 1.0 - step(0.1, abs(float(vCell.y) - float(uActiveRow)));
  float columnMask = 1.0 - step(0.1, abs(float(vCell.x) - float(uActiveColumn)));
  float mainDiag = 1.0 - step(0.1, abs(cell.x - cell.y));
  float antiDiag = 1.0 - step(0.1, abs(cell.x + cell.y - (uGridSize - 1.0)));
  float center = (uGridSize - 1.0) * 0.5;
  float centerDistance = length(cell - vec2(center)) / max(center, 1.0);

  float highlight = 0.0;
  float locked = 0.0;
  float amber = 0.0;
  float danger = 0.0;

  if (uPhase == 0) {
    float tick = floor(uTime * 18.0);
    float gate = step(0.48, hash21(cell + vec2(tick, tick * 0.31)));
    highlight = gate * (0.18 + 0.34 * fault);
    danger = step(0.92, hash21(cell + vec2(tick * 2.3, 7.0))) * fault;
  } else if (uPhase == 1) {
    highlight = rowMask;
    locked = step(cell.y + 0.5, uPhaseProgress * uGridSize) * 0.42;
    amber = rowMask;
  } else if (uPhase == 2) {
    highlight = columnMask;
    locked = step(cell.x + 0.5, uPhaseProgress * uGridSize) * 0.42;
    amber = columnMask;
  } else if (uPhase == 3) {
    float mainProgress = clamp(uPhaseProgress * 2.0, 0.0, 1.0);
    float antiProgress = clamp(uPhaseProgress * 2.0 - 1.0, 0.0, 1.0);
    float mainTravel = step((cell.x + cell.y + 1.0) / (2.0 * uGridSize), mainProgress);
    float antiTravel = step((cell.x + (uGridSize - 1.0 - cell.y) + 1.0) / (2.0 * uGridSize), antiProgress);
    highlight = mainDiag * mainTravel + antiDiag * antiTravel;
    amber = highlight;
    locked = 0.18 * (mainDiag + antiDiag);
    // 锁定保持期循环动效：双对角行波脉冲，等待 Ready / flash_ready 期间画面不死
    if (uPhaseProgress >= 0.999) {
      float waveMain = 0.5 + 0.5 * sin(uTime * 3.2 - (cell.x + cell.y) * 0.55);
      float waveAnti = 0.5 + 0.5 * sin(uTime * 3.2 - (cell.x + (uGridSize - 1.0 - cell.y)) * 0.55 + 1.9);
      highlight = mainDiag * waveMain * 0.85 + antiDiag * waveAnti * 0.85;
      amber = highlight;
      locked = 0.26 * (mainDiag + antiDiag);
    }
  } else if (uPhase == 4) {
    float wave = 0.5 + 0.5 * cos(centerDistance * 18.0 - uTime * 7.0);
    highlight = (1.0 - smoothstep(0.0, 1.25, centerDistance)) * wave * 0.55;
    locked = 0.34 + 0.17 * (mainDiag + antiDiag);
    amber = (1.0 - smoothstep(0.0, 0.16, centerDistance)) * 0.85;
    // 破门冲击波：进入同步的前 ~0.9s（progress 0→1）一道亮环从中心炸开扩散到全阵
    if (uPhaseProgress < 1.0) {
      float burstRadius = uPhaseProgress * 1.5;
      float burst = (1.0 - smoothstep(0.0, 0.14, abs(centerDistance - burstRadius))) * (1.0 - uPhaseProgress);
      highlight += burst * 1.25;
      amber += burst * 0.55;
    }
  } else if (uPhase == 5) {
    danger = 0.45 + 0.55 * step(0.68, hash21(cell + floor(uTime * 24.0)));
    highlight = step(0.76, vHash) * 0.35;
  } else {
    highlight = (1.0 - uPhaseProgress) * step(0.53, hash21(cell + floor(uTime * 30.0)));
    danger = fault * 0.75;
  }

  float edge = min(min(vLocal.x, 1.0 - vLocal.x), min(vLocal.y, 1.0 - vLocal.y));
  float border = 1.0 - smoothstep(0.018, 0.048, edge);
  float inset = smoothstep(0.0, 0.07, edge);
  float fineScan = uEffects ? 0.91 + 0.09 * sin((gl_FragCoord.y + uTime * 92.0) * 0.58) : 1.0;
  float coarseScan = uEffects ? 0.93 + 0.07 * sin((gl_FragCoord.y * 0.08) - uTime * 2.7) : 1.0;
  float noise = uEffects ? (hash21(gl_FragCoord.xy + floor(uTime * 24.0)) - 0.5) * (0.035 + fault * 0.09) : 0.0;
  float digitPulse = uEffects ? vPulse : 1.0;

  // 底色：深蓝黑（与参考一致，本就偏 DLS 色系）
  vec3 background = vec3(0.0025, 0.011, 0.015);
  background += vec3(0.0, 0.022, 0.027) * (0.4 + vHash * 0.6);
  background += vec3(0.006, 0.025, 0.028) * locked;
  background += vec3(0.048, 0.040, 0.026) * amber * 0.42;   // 骨白-琥珀渍
  background += vec3(0.058, 0.018, 0.014) * danger * 0.45;  // 锈红渍

  // DLS 蓝系数字（#3dd5ff ≈ vec3(0.24,0.84,1.0)，基础档调暗一档）
  vec3 baseBlue = vec3(0.16, 0.66, 0.80);
  vec3 hotBlue = vec3(0.45, 0.90, 1.0);
  // 骨白-琥珀高亮（#c8b28a）
  vec3 hotBone = vec3(0.78, 0.70, 0.54);
  // 锈红危险/故障（#b83a2e）
  vec3 hotRust = vec3(0.72, 0.23, 0.18);

  vec3 digitColor = mix(baseBlue, hotBlue, clamp(highlight + locked, 0.0, 1.0));
  digitColor = mix(digitColor, hotBone, clamp(amber, 0.0, 1.0));
  digitColor = mix(digitColor, hotRust, clamp(danger, 0.0, 1.0));

  vec3 glyphColor = digitColor * glyphBase;
  if (fault > 0.01) {
    glyphColor.r += glyphR * fault * 0.62;
    glyphColor.b += glyphB * fault * 0.30;
  }

  float glow = glyphBase * (0.12 + 0.28 * highlight + 0.14 * locked) * inset;
  vec3 gridColor = mix(vec3(0.015, 0.10, 0.125), hotBone, amber * 0.65) * border;
  gridColor = mix(gridColor, hotRust, danger * 0.6);

  vec3 color = background + gridColor + glyphColor * fineScan * coarseScan * digitPulse * (0.72 + 0.28 * uSignalIntensity);
  color += digitColor * glow;
  color += noise;
  color *= 0.92 + 0.08 * uSignalIntensity;
  // 换盘转场脉冲：轻微整体亮度脉冲（≤+12%，降级模式随 uEffects 一并关闭）
  color *= 1.0 + (uEffects ? 0.12 : 0.0) * uSwapPulse;

  float rescrambleFade = uPhase == 6 ? 0.58 + 0.42 * sin(uPhaseProgress * 3.14159265) : 1.0;
  // 背景层整体压暗约 35%：参考实现是演示主角，本层只做氛围底
  const float FRAG_DIM = 0.65;
  outColor = vec4(max(color * rescrambleFade * FRAG_DIM, vec3(0.0)), 1.0);
}`;

// 换盘转场脉冲衰减时长（updateValues 置 1，render 中按帧间隔线性衰到 0）
const SWAP_PULSE_DECAY_SECONDS = 0.22;

function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  if (shader === null) throw new Error("WebGL2 shader allocation failed");
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(shader) ?? "unknown shader compile error";
    gl.deleteShader(shader);
    throw new Error(log);
  }
  return shader;
}

function createProgram(gl) {
  const vertex = compileShader(gl, gl.VERTEX_SHADER, VERTEX_SHADER);
  const fragment = compileShader(gl, gl.FRAGMENT_SHADER, FRAGMENT_SHADER);
  const program = gl.createProgram();
  if (program === null) throw new Error("WebGL2 program allocation failed");
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const log = gl.getProgramInfoLog(program) ?? "unknown program link error";
    gl.deleteProgram(program);
    throw new Error(log);
  }
  return program;
}

function requireUniform(gl, program, name) {
  const location = gl.getUniformLocation(program, name);
  if (location === null) throw new Error(`required uniform ${name} was optimized away`);
  return location;
}

function createGlyphAtlas(gl) {
  const glyphWidth = 48;
  const glyphHeight = 72;
  const atlas = document.createElement("canvas");
  atlas.width = glyphWidth * 10;
  atlas.height = glyphHeight;
  const context = atlas.getContext("2d", { alpha: true });
  if (context === null) throw new Error("Canvas2D is required once to build the glyph atlas");
  context.clearRect(0, 0, atlas.width, atlas.height);
  context.fillStyle = "white";
  context.font = "700 58px 'Arial Narrow', 'Roboto Mono', ui-monospace, Consolas, monospace";
  context.textAlign = "center";
  context.textBaseline = "middle";
  for (let digit = 0; digit < 10; digit += 1) {
    context.fillText(String(digit), digit * glyphWidth + glyphWidth / 2, glyphHeight / 2 + 2);
  }

  const texture = gl.createTexture();
  if (texture === null) throw new Error("glyph texture allocation failed");
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, atlas);
  return texture;
}

/**
 * 视觉状态契约（与 canvas-renderer.mjs 共享）：
 * { phase, progress, activeRow, activeColumn, faultIntensity, signalIntensity }
 * phase: 0 SCRAMBLE / 1 ROW / 2 COLUMN / 3 DIAGONAL / 4 SYNCHRONIZED / 5 FAULT / 6 RESCRAMBLE
 */
export class PrimeMagicGridRenderer {
  constructor(canvas, size, digitSlots = 8, maxDevicePixelRatio = 1.0, renderScale = 0.5) {
    if (!Number.isInteger(size) || size < 1 || size > 255) {
      throw new RangeError("WebGL demo supports grid sizes in [1, 255]");
    }
    if (!Number.isInteger(digitSlots) || digitSlots < 1 || digitSlots > 10) {
      throw new RangeError("digitSlots must be an integer in [1, 10]");
    }
    if (!(maxDevicePixelRatio >= 0.5) || maxDevicePixelRatio > 2) {
      throw new RangeError("maxDevicePixelRatio must be in [0.5, 2]");
    }
    if (!(renderScale >= 0.25) || renderScale > 1) {
      throw new RangeError("renderScale must be in [0.25, 1]");
    }

    const gl = canvas.getContext("webgl2", {
      alpha: false,
      antialias: false,
      depth: false,
      stencil: false,
      powerPreference: "high-performance",
      preserveDrawingBuffer: false,
    });
    if (gl === null) throw new Error("WebGL2 is unavailable");

    this.gl = gl;
    this.size = size;
    this.cellCount = size * size;
    this.maxDevicePixelRatio = maxDevicePixelRatio;
    this.renderScale = renderScale; // 渲染分辨率缩放（<1 时低分辨率渲染 + CSS 放大，iGPU 省填充率）
    this.visualState = {
      phase: 0,
      progress: 0,
      activeRow: -1,
      activeColumn: -1,
      faultIntensity: 0,
      signalIntensity: 1,
    };
    this.swapPulse = 0;          // 换盘转场脉冲（updateValues 置 1，render 中衰减）
    this.lastRenderSeconds = -1; // 上一帧渲染时刻（脉冲衰减用）
    this.dihedralSpin = 0;       // 二面体变轨旋转角（弧度）
    this.dihedralMirror = 1;     // 二面体变轨水平镜像系数（1 / -1，动画中连续插值）
    this.program = createProgram(gl);
    this.timeUniform = requireUniform(gl, this.program, "uTime");
    this.sizeUniform = requireUniform(gl, this.program, "uGridSize");
    this.digitSlotsUniform = requireUniform(gl, this.program, "uDigitSlots");
    this.effectsUniform = requireUniform(gl, this.program, "uEffects");
    this.phaseUniform = requireUniform(gl, this.program, "uPhase");
    this.phaseProgressUniform = requireUniform(gl, this.program, "uPhaseProgress");
    this.activeRowUniform = requireUniform(gl, this.program, "uActiveRow");
    this.activeColumnUniform = requireUniform(gl, this.program, "uActiveColumn");
    this.faultIntensityUniform = requireUniform(gl, this.program, "uFaultIntensity");
    this.signalIntensityUniform = requireUniform(gl, this.program, "uSignalIntensity");
    this.swapPulseUniform = requireUniform(gl, this.program, "uSwapPulse");
    this.spinUniform = requireUniform(gl, this.program, "uSpin");
    this.mirrorUniform = requireUniform(gl, this.program, "uMirror");
    this.glyphAtlas = createGlyphAtlas(gl);

    const vertexArray = gl.createVertexArray();
    const cornerBuffer = gl.createBuffer();
    const cellBuffer = gl.createBuffer();
    const valueBuffer0 = gl.createBuffer();
    const valueBuffer1 = gl.createBuffer();
    if (
      vertexArray === null ||
      cornerBuffer === null ||
      cellBuffer === null ||
      valueBuffer0 === null ||
      valueBuffer1 === null
    ) {
      throw new Error("WebGL2 buffer/VAO allocation failed");
    }
    this.vertexArray = vertexArray;
    this.cornerBuffer = cornerBuffer;
    this.cellBuffer = cellBuffer;
    this.valueBuffers = [valueBuffer0, valueBuffer1];
    this.activeValueBuffer = 0;
    this.disposed = false;

    gl.bindVertexArray(vertexArray);
    gl.bindBuffer(gl.ARRAY_BUFFER, cornerBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

    const cells = new Uint8Array(this.cellCount * 2);
    for (let row = 0; row < size; row += 1) {
      for (let column = 0; column < size; column += 1) {
        const offset = (row * size + column) * 2;
        cells[offset] = column;
        cells[offset + 1] = row;
      }
    }
    gl.bindBuffer(gl.ARRAY_BUFFER, cellBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, cells, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribIPointer(1, 2, gl.UNSIGNED_BYTE, 2, 0);
    gl.vertexAttribDivisor(1, 1);

    const byteSize = this.cellCount * Uint32Array.BYTES_PER_ELEMENT;
    for (const valueBuffer of this.valueBuffers) {
      gl.bindBuffer(gl.ARRAY_BUFFER, valueBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, byteSize, gl.DYNAMIC_DRAW);
    }
    gl.bindBuffer(gl.ARRAY_BUFFER, this.valueBuffers[0]);
    gl.enableVertexAttribArray(2);
    gl.vertexAttribIPointer(2, 1, gl.UNSIGNED_INT, Uint32Array.BYTES_PER_ELEMENT, 0);
    gl.vertexAttribDivisor(2, 1);

    gl.useProgram(this.program);
    gl.uniform1f(this.sizeUniform, size);
    gl.uniform1i(this.digitSlotsUniform, digitSlots);
    gl.uniform1i(this.effectsUniform, 1);
    gl.uniform1i(requireUniform(gl, this.program, "uGlyphAtlas"), 0);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.glyphAtlas);
  }

  /** 写入空闲 GPU 缓冲后原子切换 attribute 来源（双缓冲，无撕裂）。 */
  updateValues(values) {
    if (values.length !== this.cellCount) throw new RangeError("board length mismatch");
    const gl = this.gl;
    const nextIndex = this.activeValueBuffer ^ 1;
    const nextBuffer = this.valueBuffers[nextIndex];
    gl.bindVertexArray(this.vertexArray);
    gl.bindBuffer(gl.ARRAY_BUFFER, nextBuffer);
    gl.bufferSubData(gl.ARRAY_BUFFER, 0, values);
    gl.vertexAttribIPointer(2, 1, gl.UNSIGNED_INT, Uint32Array.BYTES_PER_ELEMENT, 0);
    gl.vertexAttribDivisor(2, 1);
    this.activeValueBuffer = nextIndex;
    this.swapPulse = 1; // 换盘转场脉冲，render 中按帧间隔衰减
  }

  setVisualState(state) {
    this.visualState = state;
  }

  // 二面体变轨变换（弧度 + 水平镜像系数）；动画结束瞬间由 main 归零并同步换数据
  setDihedralTransform(spinRadians, mirror) {
    this.dihedralSpin = spinRadians;
    this.dihedralMirror = mirror;
  }

  render(timeSeconds) {
    const gl = this.gl;
    const canvas = gl.canvas;
    const pixelRatio = Math.min(window.devicePixelRatio || 1, this.maxDevicePixelRatio) * this.renderScale;
    const width = Math.max(1, Math.round(canvas.clientWidth * pixelRatio));
    const height = Math.max(1, Math.round(canvas.clientHeight * pixelRatio));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }

    // 换盘转场脉冲：按帧间隔线性衰减（首帧无间隔，跳过）
    if (this.lastRenderSeconds >= 0 && this.swapPulse > 0) {
      this.swapPulse = Math.max(0, this.swapPulse - (timeSeconds - this.lastRenderSeconds) / SWAP_PULSE_DECAY_SECONDS);
    }
    this.lastRenderSeconds = timeSeconds;

    gl.viewport(0, 0, width, height);
    gl.useProgram(this.program);
    gl.uniform1f(this.timeUniform, timeSeconds);
    gl.uniform1i(this.phaseUniform, this.visualState.phase);
    gl.uniform1f(this.phaseProgressUniform, this.visualState.progress);
    gl.uniform1i(this.activeRowUniform, this.visualState.activeRow);
    gl.uniform1i(this.activeColumnUniform, this.visualState.activeColumn);
    gl.uniform1f(this.faultIntensityUniform, this.visualState.faultIntensity);
    gl.uniform1f(this.signalIntensityUniform, this.visualState.signalIntensity);
    gl.uniform1f(this.swapPulseUniform, this.swapPulse);
    gl.uniform1f(this.spinUniform, this.dihedralSpin);
    gl.uniform1f(this.mirrorUniform, this.dihedralMirror);
    gl.bindVertexArray(this.vertexArray);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.glyphAtlas);
    gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, this.cellCount);
  }

  setVisualEffects(enabled) {
    this.gl.useProgram(this.program);
    this.gl.uniform1i(this.effectsUniform, enabled ? 1 : 0);
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    const gl = this.gl;
    gl.deleteTexture(this.glyphAtlas);
    gl.deleteBuffer(this.cornerBuffer);
    gl.deleteBuffer(this.cellBuffer);
    for (const buffer of this.valueBuffers) gl.deleteBuffer(buffer);
    gl.deleteVertexArray(this.vertexArray);
    gl.deleteProgram(this.program);
    const loseContext = gl.getExtension("WEBGL_lose_context");
    if (loseContext) loseContext.loseContext();
  }
}
