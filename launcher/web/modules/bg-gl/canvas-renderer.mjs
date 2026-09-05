// PM19 质数幻方 Canvas2D 回退渲染器（WebGL2 不可用时启用）
// 移植自 tmp/prime-magic-eval/prime-magic-visual-demo/web/canvas-renderer.ts，改动点同 renderer.mjs：
// DLS 蓝数字 / 骨白-琥珀高亮 / 锈红故障，alpha 整体压暗约 35%，maxDevicePixelRatio 默认 1.0。

function hashCell(x, y) {
  let value = Math.imul(x + 1, 0x45d9f3b) ^ Math.imul(y + 11, 0x119de1f3);
  value = Math.imul(value ^ (value >>> 16), 0x45d9f3b);
  return ((value ^ (value >>> 16)) >>> 0) / 0x1_0000_0000;
}

export class PrimeMagicCanvasRenderer {
  constructor(canvas, size, _digitSlots = 8, maxDevicePixelRatio = 1.0, renderScale = 0.5) {
    const context = canvas.getContext("2d", { alpha: false });
    if (context === null) throw new Error("Canvas2D is unavailable");
    this.canvas = canvas;
    this.context = context;
    this.size = size;
    this.values = new Uint32Array(size * size);
    this.maxDevicePixelRatio = maxDevicePixelRatio;
    this.renderScale = renderScale; // 与 WebGL 渲染器一致的低分辨率渲染缩放
    this.effects = true;
    this.pulseAt = -1e9; // 换盘转场脉冲时刻（弱化版：仅整体亮度微脉冲，无位移）
    this.visualState = {
      phase: 0,
      progress: 0,
      activeRow: -1,
      activeColumn: -1,
      faultIntensity: 0,
      signalIntensity: 1,
    };
  }

  updateValues(values) {
    if (values.length !== this.values.length) throw new RangeError("board length mismatch");
    this.values.set(values);
    this.pulseAt = performance.now() / 1000;
  }

  setVisualState(state) {
    this.visualState = state;
  }

  setVisualEffects(enabled) {
    this.effects = enabled;
  }

  // 降级说明：Canvas2D 回退不实现 uSpin 旋转 / 镜像变换 —— 变轨间奏只换数据、不播动画；
  // main.mjs 仍会在动画结束瞬间把棋盘替换为旋转 / 镜像后的合法幻方，视觉为瞬时切换。
  setDihedralTransform(_spinRadians, _mirror) {}

  dispose() {
    this.canvas.width = 1;
    this.canvas.height = 1;
    this.values = new Uint32Array(0);
  }

  render(timeSeconds) {
    const pixelRatio = Math.min(window.devicePixelRatio || 1, this.maxDevicePixelRatio) * this.renderScale;
    const width = Math.max(1, Math.round(this.canvas.clientWidth * pixelRatio));
    const height = Math.max(1, Math.round(this.canvas.clientHeight * pixelRatio));
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }

    const context = this.context;
    const size = this.size;
    const cellWidth = width / size;
    const cellHeight = height / size;
    context.setTransform(1, 0, 0, 1, 0, 0);
    context.fillStyle = "#02090b";
    context.fillRect(0, 0, width, height);
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.font = `700 ${Math.max(5, cellWidth * 0.205)}px ui-monospace, Consolas, monospace`;

    const phase = this.visualState.phase;
    const progress = this.visualState.progress;
    const fault = this.effects ? this.visualState.faultIntensity : 0;
    const center = (size - 1) * 0.5;
    const tick = Math.floor(timeSeconds * 20);

    for (let row = 0; row < size; row += 1) {
      for (let column = 0; column < size; column += 1) {
        const index = row * size + column;
        const value = this.values[index];
        const x = column * cellWidth;
        const y = row * cellHeight;
        const hash = hashCell(column + tick, row);
        const mainDiag = row === column;
        const antiDiag = row + column === size - 1;
        let highlight = 0;
        let amber = 0;
        let danger = 0;

        if (phase === 0) {
          highlight = hash > 0.55 ? 0.35 : 0;
          danger = hash > 0.95 ? fault : 0;
        } else if (phase === 1) {
          highlight = row === this.visualState.activeRow ? 1 : row < progress * size ? 0.24 : 0;
          amber = row === this.visualState.activeRow ? 1 : 0;
        } else if (phase === 2) {
          highlight = column === this.visualState.activeColumn ? 1 : column < progress * size ? 0.24 : 0;
          amber = column === this.visualState.activeColumn ? 1 : 0;
        } else if (phase === 3) {
          const mainProgress = Math.min(1, progress * 2);
          const antiProgress = Math.max(0, progress * 2 - 1);
          if (mainDiag && (row + column + 1) / (2 * size) <= mainProgress) amber = 1;
          if (antiDiag && (column + (size - 1 - row) + 1) / (2 * size) <= antiProgress) amber = 1;
          highlight = amber;
        } else if (phase === 4) {
          const distance = Math.hypot(column - center, row - center) / center;
          highlight = Math.max(0, 1 - distance) * (0.28 + 0.18 * Math.cos(distance * 15 - timeSeconds * 6));
          amber = mainDiag || antiDiag ? 0.4 : 0;
        } else if (phase === 5) {
          danger = hash > 0.56 ? fault : fault * 0.22;
          highlight = hash > 0.82 ? 0.4 : 0;
        } else {
          danger = hash > 0.62 ? fault * 0.65 : 0;
        }

        // 单元底色：蓝底 + 骨白/锈红渍（背景层，保持低亮度）
        const backgroundR = 2 + Math.round(amber * 24 + danger * 30);
        const backgroundG = 10 + Math.round(highlight * 18 + amber * 20);
        const backgroundB = 13 + Math.round(highlight * 20 + amber * 10 + danger * 3);
        context.fillStyle = `rgb(${backgroundR},${backgroundG},${backgroundB})`;
        context.fillRect(x, y, cellWidth, cellHeight);

        context.strokeStyle = danger > 0.25
          ? `rgba(184,58,46,${0.12 + danger * 0.20})`
          : amber > 0.1
            ? `rgba(200,178,138,${0.14 + amber * 0.30})`
            : "rgba(61,213,255,0.12)";
        context.lineWidth = 1;
        context.strokeRect(x + 0.5, y + 0.5, cellWidth - 1, cellHeight - 1);

        if (danger > 0.3 && this.effects) {
          context.fillStyle = `rgba(184,58,46,${0.24 + danger * 0.32})`;
          context.fillText(String(value), x + cellWidth * 0.5 + 1.2 * fault, y + cellHeight * 0.52);
        }
        // alpha 较参考实现压暗约 35%（0.62+0.32h → 0.40+0.22h；0.78+0.2a → 0.50+0.14a）
        context.fillStyle = amber > 0.2
          ? `rgba(200,178,138,${0.50 + amber * 0.14})`
          : `rgba(61,213,255,${0.40 + highlight * 0.22})`;
        context.fillText(String(value), x + cellWidth * 0.5, y + cellHeight * 0.52);
      }
    }

    // 换盘转场脉冲（约 220ms 线性衰减；WebGL 版的微细位移在此回退中省略，避免喧宾夺主）
    const pulse = this.effects ? Math.max(0, 1 - (timeSeconds - this.pulseAt) / 0.22) : 0;
    if (pulse > 0) {
      context.fillStyle = `rgba(190,220,235,${0.05 * pulse})`;
      context.fillRect(0, 0, width, height);
    }

    if (this.effects) {
      context.fillStyle = "rgba(61,213,255,0.016)";
      for (let y = 0; y < height; y += 4) context.fillRect(0, y, width, 1);
    }
  }
}
