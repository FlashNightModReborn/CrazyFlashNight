const VERTEX_SHADER = `#version 300 es
layout(location = 0) in vec2 aCorner;
layout(location = 1) in uvec2 aCell;
layout(location = 2) in uint aValue;

uniform float uGridSize;
uniform float uTime;
out vec2 vLocal;
flat out uint vValue;
flat out float vPulse;
flat out float vNoise;

float hash21(vec2 value) {
  return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
  vec2 grid = vec2(aCell) + aCorner;
  vec2 clip = grid / uGridSize * 2.0 - 1.0;
  clip.y = -clip.y;
  gl_Position = vec4(clip, 0.0, 1.0);
  vLocal = aCorner;
  vValue = aValue;
  vPulse = 0.93 + 0.07 * sin(uTime * 2.1 + float(aCell.x + aCell.y) * 0.31);
  vNoise = fract(hash21(vec2(aCell)) + floor(uTime * 12.0) * 0.6180339887) * 0.06;
}`;

const FRAGMENT_SHADER = `#version 300 es
precision highp float;
precision highp int;

uniform sampler2D uGlyphAtlas;
uniform float uTime;
uniform float uGridSize;
uniform int uDigitSlots;
uniform bool uEffects;
in vec2 vLocal;
flat in uint vValue;
flat in float vPulse;
flat in float vNoise;
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

void main() {
  int slot = clamp(int(floor(vLocal.x * float(uDigitSlots))), 0, uDigitSlots - 1);
  uint divisor = decimalDivisor(uDigitSlots - 1 - slot);
  uint digit = (vValue / divisor) % 10u;
  bool visibleDigit = slot == uDigitSlots - 1 || vValue >= divisor;
  vec2 glyphUv = vec2(
    (float(digit) + fract(vLocal.x * float(uDigitSlots))) * 0.1,
    vLocal.y
  );
  float glyph = visibleDigit ? texture(uGlyphAtlas, glyphUv).a : 0.0;

  float border = 1.0 - step(0.035, min(min(vLocal.x, 1.0 - vLocal.x), min(vLocal.y, 1.0 - vLocal.y)));
  float scanline = uEffects ? 0.90 + 0.10 * sin((gl_FragCoord.y + uTime * 85.0) * 0.45) : 1.0;
  float pulse = uEffects ? vPulse : 1.0;
  float noise = uEffects ? vNoise : 0.0;
  vec3 background = vec3(0.004, 0.018, 0.024) + vec3(0.0, 0.018, 0.022) * noise;
  vec3 cyan = vec3(0.10, 0.94, 0.83) * glyph * scanline * pulse;
  vec3 grid = vec3(0.01, 0.18, 0.19) * border;
  outColor = vec4(background + cyan + grid, 1.0);
}`;

function compileShader(gl: WebGL2RenderingContext, type: number, source: string): WebGLShader {
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

function createProgram(gl: WebGL2RenderingContext): WebGLProgram {
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

function requireUniform(gl: WebGL2RenderingContext, program: WebGLProgram, name: string): WebGLUniformLocation {
  const location = gl.getUniformLocation(program, name);
  if (location === null) throw new Error(`required uniform ${name} was optimized away`);
  return location;
}

function createGlyphAtlas(gl: WebGL2RenderingContext): WebGLTexture {
  const glyphWidth = 40;
  const glyphHeight = 64;
  const atlas = document.createElement("canvas");
  atlas.width = glyphWidth * 10;
  atlas.height = glyphHeight;
  const context = atlas.getContext("2d", { alpha: true });
  if (context === null) throw new Error("Canvas2D is required once to build the glyph atlas");
  context.clearRect(0, 0, atlas.width, atlas.height);
  context.fillStyle = "white";
  context.font = "600 52px ui-monospace, SFMono-Regular, Consolas, monospace";
  context.textAlign = "center";
  context.textBaseline = "middle";
  for (let digit = 0; digit < 10; digit += 1) {
    // Only ten startup strings. Board updates use integer division in shader.
    context.fillText(String(digit), digit * glyphWidth + glyphWidth / 2, glyphHeight / 2 + 1);
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

export class PrimeMagicGridRenderer {
  private readonly gl: WebGL2RenderingContext;
  private readonly size: number;
  private readonly cellCount: number;
  private readonly program: WebGLProgram;
  private readonly vertexArray: WebGLVertexArrayObject;
  private readonly valueBuffer: WebGLBuffer;
  private readonly glyphAtlas: WebGLTexture;
  private readonly timeUniform: WebGLUniformLocation;
  private readonly sizeUniform: WebGLUniformLocation;
  private readonly digitSlotsUniform: WebGLUniformLocation;
  private readonly effectsUniform: WebGLUniformLocation;
  private readonly maxDevicePixelRatio: number;

  public constructor(
    canvas: HTMLCanvasElement,
    size: number,
    digitSlots = 8,
    maxDevicePixelRatio = 1.5,
  ) {
    if (!Number.isInteger(size) || size < 1 || size > 255) {
      throw new RangeError("WebGL demo supports grid sizes in [1, 255]");
    }
    if (!Number.isInteger(digitSlots) || digitSlots < 1 || digitSlots > 10) {
      throw new RangeError("digitSlots must be an integer in [1, 10]");
    }
    if (!(maxDevicePixelRatio >= 0.5) || maxDevicePixelRatio > 2) {
      throw new RangeError("maxDevicePixelRatio must be in [0.5, 2]");
    }
    const gl = canvas.getContext("webgl2", {
      alpha: false,
      antialias: false,
      depth: false,
      stencil: false,
      powerPreference: "high-performance",
    });
    if (gl === null) throw new Error("WebGL2 is unavailable");
    this.gl = gl;
    this.size = size;
    this.cellCount = size * size;
    this.maxDevicePixelRatio = maxDevicePixelRatio;
    this.program = createProgram(gl);
    this.timeUniform = requireUniform(gl, this.program, "uTime");
    this.sizeUniform = requireUniform(gl, this.program, "uGridSize");
    this.digitSlotsUniform = requireUniform(gl, this.program, "uDigitSlots");
    this.effectsUniform = requireUniform(gl, this.program, "uEffects");
    this.glyphAtlas = createGlyphAtlas(gl);

    const vertexArray = gl.createVertexArray();
    const cornerBuffer = gl.createBuffer();
    const cellBuffer = gl.createBuffer();
    const valueBuffer = gl.createBuffer();
    if (vertexArray === null || cornerBuffer === null || cellBuffer === null || valueBuffer === null) {
      throw new Error("WebGL2 buffer/VAO allocation failed");
    }
    this.vertexArray = vertexArray;
    this.valueBuffer = valueBuffer;

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

    gl.bindBuffer(gl.ARRAY_BUFFER, valueBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.cellCount * Uint32Array.BYTES_PER_ELEMENT, gl.DYNAMIC_DRAW);
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

  /** One 1444-byte upload for n=19; values are never converted to strings. */
  public updateValues(values: Uint32Array): void {
    if (values.length !== this.cellCount) throw new RangeError("board length mismatch");
    const gl = this.gl;
    gl.bindBuffer(gl.ARRAY_BUFFER, this.valueBuffer);
    gl.bufferSubData(gl.ARRAY_BUFFER, 0, values);
  }

  public render(timeSeconds: number): void {
    const gl = this.gl;
    const canvas = gl.canvas as HTMLCanvasElement;
    const pixelRatio = Math.min(window.devicePixelRatio || 1, this.maxDevicePixelRatio);
    const width = Math.max(1, Math.round(canvas.clientWidth * pixelRatio));
    const height = Math.max(1, Math.round(canvas.clientHeight * pixelRatio));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    gl.viewport(0, 0, width, height);
    gl.useProgram(this.program);
    gl.uniform1f(this.timeUniform, timeSeconds);
    gl.bindVertexArray(this.vertexArray);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.glyphAtlas);
    gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, this.cellCount);
  }

  public setVisualEffects(enabled: boolean): void {
    this.gl.useProgram(this.program);
    this.gl.uniform1i(this.effectsUniform, enabled ? 1 : 0);
  }

  /** Forces GPU completion; use only in the explicit benchmark, never in gameplay. */
  public finishForBenchmark(): void {
    this.gl.finish();
  }
}
