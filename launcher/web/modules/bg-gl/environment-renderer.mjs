// PM19 V2 — cached, full-page Canvas2D environment. No business authority.
// The committed integer board is never interpolated. A sweep is light, not data.
const N = 19;
const TAU = Math.PI * 2;

export class EnvironmentRenderer {
  constructor(canvas, { scale = 1, cache = true } = {}) {
    const ctx = canvas.getContext('2d', { alpha: true });
    if (!ctx) throw new Error('background Canvas2D unavailable');
    this.canvas = canvas;
    this.ctx = ctx;
    this.scale = scale;
    this.useCache = cache;
    this.values = new Uint32Array(N * N);
    this.points = new Float32Array(N * N * 2);
    this.width = this.height = 0;
    this.dirty = true;
    this.masks = [];
    this.disposed = false;
    this.renders = this.rebuilds = 0;
    this.surfaces = [];
    // A failed cache allocation falls back to direct drawing on the SAME live
    // 2D canvas. No GL acquisition, hence no GL-poisoned-canvas retry hazard.
    try {
      for (let i = 0; i < 2; i++) {
        const c = document.createElement('canvas');
        const context = c.getContext('2d', { alpha: true });
        if (!context) throw new Error('cache Canvas2D unavailable');
        this.surfaces.push({ canvas: c, ctx: context });
      }
    } catch (_) {
      this.surfaces.forEach(s => { s.canvas.width = s.canvas.height = 1; });
      this.surfaces.length = 0;
      this.useCache = false;
    }
  }

  resize(width, height, masks = []) {
    if (this.disposed) return;
    const ratio = Math.min(window.devicePixelRatio || 1, 1) * this.scale;
    const w = Math.max(1, Math.round(width * ratio));
    const h = Math.max(1, Math.round(height * ratio));
    this.masks = masks.map(r => ({ x: r.x * ratio, y: r.y * ratio,
      w: r.width * ratio, h: r.height * ratio, fade: r.fade * ratio }));
    // Build feather gradients only when the layout changes, never per frame.
    for (const r of this.masks) {
      const {x,y,w,h,fade:f} = r;
      r.strips = [];
      for (const [a,b,c,d,fx,fy,fw,fh,reverse] of [
        [x-f,0,x,0,x-f,y,f,h,false], [x+w,0,x+w+f,0,x+w,y,f,h,true],
        [0,y-f,0,y,x-f,y-f,w+2*f,f,false], [0,y+h,0,y+h+f,x-f,y+h,w+2*f,f,true]
      ]) {
        const g = this.ctx.createLinearGradient(a,b,c,d);
        g.addColorStop(0, reverse ? '#000' : 'transparent');
        g.addColorStop(1, reverse ? 'transparent' : '#000');
        r.strips.push({ g, x:fx, y:fy, w:fw, h:fh });
      }
    }
    if (w === this.width && h === this.height) return;
    this.width = this.canvas.width = w;
    this.height = this.canvas.height = h;
    for (const s of this.surfaces) { s.canvas.width = w; s.canvas.height = h; }
    this.font = Math.max(4.2 * ratio, Math.min(12 * ratio, w / 19 * .151));
    for (let r = 0; r < N; r++) {
      const t = (r + .5) / N;
      // 两端留出完整数字宽度，避免中间几行的首尾质数被视口切半。
      const span = w * (.92 + .06 * Math.sin(t * Math.PI));
      const y = 17 * ratio + (h - 32 * ratio) * t;
      for (let c = 0; c < N; c++) {
        const i = (r * N + c) * 2;
        this.points[i] = w / 2 + ((c + .5) / N - .5) * span;
        this.points[i + 1] = y;
      }
    }
    this.dirty = true;
  }

  updateValues(board) {
    if (board.length !== N * N) throw new RangeError('expected 361 integers');
    this.values.set(board);
    this.dirty = true;
  }

  drawBoard(ctx, bright = false) {
    const w = this.width, h = this.height, pts = this.points;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = `500 ${this.font}px "JetBrains Mono", Consolas, monospace`;
    if (!bright) {
      // One path per family; no per-cell strokeRect or background fill.
      ctx.lineWidth = .6;
      ctx.strokeStyle = 'rgba(88,153,165,.19)';
      ctx.beginPath();
      for (let r = 0; r < N; r++) {
        const i = r * N * 2;
        ctx.moveTo(pts[i] - w / 42, pts[i + 1]);
        ctx.lineTo(pts[i + (N - 1) * 2] + w / 42, pts[i + 1]);
      }
      for (let c = 0; c < N; c++) {
        for (let r = 0; r < N; r++) {
          const i = (r * N + c) * 2;
          if (r === 0) ctx.moveTo(pts[i], pts[i + 1]);
          else ctx.lineTo(pts[i], pts[i + 1]);
        }
      }
      ctx.stroke();
      // Both REAL diagonals cross at the single center cell (9,9).
      ctx.strokeStyle = 'rgba(171,153,114,.23)';
      ctx.beginPath();
      for (let k = 0; k < 2; k++) {
        for (let r = 0; r < N; r++) {
          const i = (r * N + (k ? N - 1 - r : r)) * 2;
          if (!r) ctx.moveTo(pts[i], pts[i + 1]);
          else ctx.lineTo(pts[i], pts[i + 1]);
        }
      }
      ctx.stroke();
    }
    for (let r = 0; r < N; r++) {
      for (let c = 0; c < N; c++) {
        const index = r * N + c, i = index * 2;
        const diagonal = r === c || r + c === 18;
        ctx.fillStyle = bright ? (this.errorAccent ? '#ed6a55' : '#cfba8d') : diagonal ? '#647067' : '#34636e';
        // Position is discrete (r,c); all eight digits of the real integer are
        // drawn once into the cache. No fabricated checksum/ready readout.
        ctx.fillText(String(this.values[index]), pts[i], pts[i + 1] - this.font * .82);
        if (!bright) {
          ctx.fillStyle = diagonal ? '#7e745a' : '#28505b';
          ctx.fillRect(pts[i] - .6, pts[i + 1] - .6, 1.2, 1.2);
        }
      }
    }
  }

  rebuild() {
    if (!this.dirty || !this.useCache) return;
    for (let i = 0; i < this.surfaces.length; i++) {
      const s = this.surfaces[i];
      s.ctx.clearRect(0, 0, this.width, this.height);
      this.drawBoard(s.ctx, i === 1);
    }
    this.dirty = false;
    this.rebuilds++;
  }

  eraseForeground(ctx) {
    // Geometry is sampled only on layout/view/font changes, not every frame.
    // Feathered silence under foreground; no scan can cross a button or copy.
    ctx.globalCompositeOperation = 'destination-out';
    ctx.globalAlpha = 1;
    for (const r of this.masks) {
      const x = r.x, y = r.y, w = r.w, h = r.h, f = r.fade;
      ctx.fillStyle = '#000'; ctx.fillRect(x, y, w, h);
      if (!f) continue;
      for (const s of r.strips) {
        ctx.fillStyle = s.g; ctx.fillRect(s.x, s.y, s.w, s.h);
      }
    }
    ctx.globalCompositeOperation = 'source-over';
  }

  render(time, state = {}) {
    if (this.disposed) return;
    const error = state.kind === 'error';
    // 仅进出故障态时重建强调色缓存，持续演出仍复用两张位图。
    if (this.errorAccent !== error) { this.errorAccent = error; this.dirty = true; }
    this.rebuild();
    const ctx = this.ctx, w = this.width, h = this.height;
    const p = Math.max(0, Math.min(1, state.progress || 0));
    const still = !!state.still;
    const loading = state.kind === 'loading';
    const bright = state.kind && state.kind !== 'quiet';
    ctx.clearRect(0, 0, w, h);
    ctx.globalAlpha = still ? .82 : .79 + .07 * Math.sin(time * TAU / 8);
    if (this.useCache) ctx.drawImage(this.surfaces[0].canvas, 0, 0);
    else this.drawBoard(ctx);
    if (error) this.drawFault(time, still);
    ctx.globalAlpha = 1;
    // Reversal partners r and 18-r travel together. Their center is invariant.
    // On confirmation, use the actual two diagonals instead of fictitious progress.
    const phase = error ? .5 : loading ? (time % 3) / 3 : bright ? p : (time % 8) / 8;
    const position = Math.min(9, phase * 10);
    const envelope = error ? (still ? .5 : .5 + .1 * Math.sin(time * TAU / 4))
      : loading ? (still ? .2 : .8) : bright ? Math.sin(Math.PI * p) : still ? .12 : .10;
    if (envelope > .001) {
      ctx.save(); ctx.beginPath();
      if (state.kind === 'confirm' || loading) {
        for (let r = 0; r < N; r++) {
          // 沿真实双对角循环扫光，只表示仍在等待，不冒充启动百分比。
          if (loading && !still && Math.abs(r - (phase * 24 - 3)) > 2) continue;
          for (const c of [r, 18 - r]) {
            const i = (r * N + c) * 2;
            ctx.rect(this.points[i] - w / 40, this.points[i + 1] - this.font * 1.65, w / 20, this.font * 1.6);
          }
        }
      } else {
        const r = Math.min(9, Math.floor(position));
        for (const row of r === 9 ? [9] : [r, 18 - r]) {
          const y = this.points[row * N * 2 + 1];
          ctx.rect(0, y - this.font * 1.75, w, this.font * 1.85);
        }
      }
      ctx.clip(); ctx.globalAlpha = envelope * (state.kind === 'error' ? .4 : .72);
      if (this.useCache) ctx.drawImage(this.surfaces[1].canvas, 0, 0);
      else this.drawBoard(ctx, true);
      ctx.restore();
    }
    // Peripheral guide lights, symmetric about (9,9); they never enter the UI.
    const r = Math.min(9, Math.floor(position));
    for (const row of r === 9 ? [9] : [r, 18 - r]) {
      const y = this.points[row * N * 2 + 1];
      ctx.strokeStyle = state.kind === 'error' ? 'rgba(163,80,64,.64)' : `rgba(178,162,122,${.16 + envelope * .48})`;
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w * .085, y);
      ctx.moveTo(w, y); ctx.lineTo(w * .915, y); ctx.stroke();
      ctx.fillStyle = state.kind === 'error' ? '#976653' : '#86988d';
      ctx.globalAlpha = .28 + envelope * .4;
      ctx.fillRect(w * .028, y - 1.5, 3, 3); ctx.fillRect(w * .972 - 3, y - 1.5, 3, 3);
    }
    this.eraseForeground(ctx);
    ctx.globalAlpha = 1;
    this.renders++;
  }

  drawFault(time, still) {
    const ctx = this.ctx, w = this.width, h = this.height;
    const phase = still ? .5 : (time % 4) / 4;
    // 整张合法幻方转为锈红；不再只点亮容易被前景吃掉的两条细线。
    ctx.globalAlpha = still ? .75 : .65 + .12 * Math.sin(phase * TAU);
    if (this.useCache) ctx.drawImage(this.surfaces[1].canvas, 0, 0);
    else this.drawBoard(ctx, true);
    ctx.globalAlpha = 1;
    ctx.lineWidth = 2;
    ctx.strokeStyle = 'rgba(224,93,70,.65)';
    // 对称断链环在前景后方扩散，随后由同一文字遮罩裁掉。
    for (let k = 0; k < 2; k++) {
      const radius = .24 + ((phase + k * .5) % 1) * .42;
      ctx.beginPath(); ctx.ellipse(w / 2, h / 2, w * radius, h * radius, 0, 0, TAU); ctx.stroke();
    }
    // 屏边有持续可见的红色轨道，中央诊断弹窗不遮掉全部反馈。
    const top = h * .18, bottom = h * .82, sweep = top + (bottom - top) * phase;
    ctx.beginPath(); ctx.moveTo(8, top); ctx.lineTo(8, bottom);
    ctx.moveTo(w - 8, top); ctx.lineTo(w - 8, bottom); ctx.stroke();
    ctx.fillStyle = '#ed785e';
    ctx.fillRect(5, sweep - 12, 6, 24);
    ctx.fillRect(w - 11, h - sweep - 12, 6, 24);
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.surfaces.forEach(s => { s.canvas.width = s.canvas.height = 1; });
    this.surfaces.length = 0;
    this.canvas.width = this.canvas.height = 1;
    this.values = new Uint32Array(0);
    this.points = new Float32Array(0);
    this.masks.length = 0;
  }
}
