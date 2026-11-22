// PM19 V4.2 — cached, full-page Canvas2D environment with mathematical symmetry choreography.
// The committed integer board is never interpolated. Light, focus, and wavefronts reveal true invariants.
const N = 19;
const TAU = Math.PI * 2;
const KNOWN_KINDS = new Set(['quiet', 'arrival', 'exchange', 'exchange-pair',
  'confirm', 'slots-pick', 'loading', 'sync', 'return', 'error', 'unfreeze']);

function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
function easeOutCubic(t) { t = clamp01(t); return 1 - (1 - t) * (1 - t) * (1 - t); }
function easeInOutSine(t) { t = clamp01(t); return 0.5 - 0.5 * Math.cos(Math.PI * t); }

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
    this.warnedKinds = new Set();
    this.surfaces = [];
    // 3 cached surfaces: [0] crisp base lattice, [1] crisp illuminated layer, [2] soft defocused layer.
    try {
      for (let i = 0; i < 3; i++) {
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
      w: r.width * ratio, h: r.height * ratio, fade: r.fade * ratio, erase: r.erase }));
    for (const r of this.masks) {
      const { x, y, w: rw, h: rh, fade: f } = r;
      r.strips = [];
      for (const [a, b, c, d, fx, fy, fw, fh, reverse] of [
        [x - f, 0, x, 0, x - f, y, f, rh, false],
        [x + rw, 0, x + rw + f, 0, x + rw, y, f, rh, true],
        [0, y - f, 0, y, x - f, y - f, rw + 2 * f, f, false],
        [0, y + rh, 0, y + rh + f, x - f, y + rh, rw + 2 * f, f, true]
      ]) {
        const g = this.ctx.createLinearGradient(a, b, c, d);
        g.addColorStop(0, reverse ? '#000' : 'transparent');
        g.addColorStop(1, reverse ? 'transparent' : '#000');
        r.strips.push({ g, x: fx, y: fy, w: fw, h: fh });
      }
    }
    if (w === this.width && h === this.height) return;
    this.width = this.canvas.width = w;
    this.height = this.canvas.height = h;
    for (const s of this.surfaces) { s.canvas.width = w; s.canvas.height = h; }
    this.font = Math.max(4.4 * ratio, Math.min(12 * ratio, w / 19 * .154));
    for (let r = 0; r < N; r++) {
      const t = (r + .5) / N;
      const span = w * (.92 + .055 * Math.sin(t * Math.PI));
      const y = 17 * ratio + (h - 32 * ratio) * t;
      for (let c = 0; c < N; c++) {
        const i = (r * N + c) * 2;
        this.points[i] = Math.round((w / 2 + ((c + .5) / N - .5) * span) * 2) / 2;
        this.points[i + 1] = Math.round(y * 2) / 2;
      }
    }
    this.dirty = true;
  }

  updateValues(board) {
    if (board.length !== N * N) throw new RangeError('expected 361 integers');
    this.values.set(board);
    this.dirty = true;
  }

  cellPt(r, c) {
    const i = (r * N + c) * 2;
    return [this.points[i], this.points[i + 1]];
  }

  drawBoard(ctx, mode = 0) {
    // mode: 0 = crisp ambient base, 1 = crisp bright/illuminated, 2 = soft defocused atmospheric
    const bright = mode === 1;
    const soft = mode === 2;
    const w = this.width, h = this.height, pts = this.points;
    ctx.save();
    if (soft && 'filter' in ctx) ctx.filter = 'blur(1.5px)';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = `500 ${this.font}px "JetBrains Mono", Consolas, monospace`;

    if (!bright) {
      // Base 19x19 lattice hairlines
      ctx.lineWidth = .6;
      ctx.strokeStyle = soft ? 'rgba(61,213,255,.14)' : 'rgba(84,158,172,.17)';
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

      // Central invariant axes (row 9 & col 9) crossing at fixed point (9,9)
      if (!soft) {
        const [cx, cy] = this.cellPt(9, 9);
        ctx.strokeStyle = 'rgba(61,213,255,.16)';
        ctx.lineWidth = .8;
        ctx.beginPath();
        ctx.moveTo(pts[9 * N * 2] - w / 42, cy);
        ctx.lineTo(pts[(9 * N + N - 1) * 2] + w / 42, cy);
        ctx.moveTo(cx, pts[9 * 2 + 1]);
        ctx.lineTo(cx, pts[(18 * N + 9) * 2 + 1]);
        ctx.stroke();
      }

      // Both REAL diagonals crossing at the single fixed-point cell (9,9)
      ctx.strokeStyle = soft ? 'rgba(207,186,141,.18)' : 'rgba(186,166,124,.24)';
      ctx.lineWidth = .75;
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
        const center = r === 9 && c === 9;
        const diagonal = r === c || r + c === 18;
        if (bright) {
          ctx.fillStyle = this.errorAccent
            ? (diagonal ? '#ff8b73' : '#e86852')
            : center ? '#8be8ff' : diagonal ? '#f0deb0' : '#d6c192';
        } else if (soft) {
          ctx.fillStyle = diagonal ? '#7b8a82' : '#3d7484';
        } else {
          ctx.fillStyle = center ? '#7bd6eb' : diagonal ? '#738075' : '#3a6c78';
        }
        ctx.fillText(String(this.values[index]), pts[i], pts[i + 1] - this.font * .82);
        if (!bright && !soft) {
          ctx.fillStyle = center ? '#3dd5ff' : diagonal ? '#8c7e5f' : '#2a5561';
          const dot = center ? 2 : 1.2;
          ctx.fillRect(pts[i] - dot / 2, pts[i + 1] - dot / 2, dot, dot);
        }
      }
    }
    ctx.restore();
  }

  rebuild() {
    if (!this.dirty || !this.useCache) return;
    for (let i = 0; i < this.surfaces.length; i++) {
      const s = this.surfaces[i];
      s.ctx.clearRect(0, 0, this.width, this.height);
      this.drawBoard(s.ctx, i);
    }
    this.dirty = false;
    this.rebuilds++;
  }

  eraseForeground(ctx) {
    ctx.globalCompositeOperation = 'destination-out';
    for (const r of this.masks) {
      const x = r.x, y = r.y, w = r.w, h = r.h, f = r.fade;
      const a = r.erase == null ? 1 : r.erase;
      ctx.globalAlpha = a;
      ctx.fillStyle = '#000';
      ctx.fillRect(x, y, w, h);
      if (!f) continue;
      for (const s of r.strips) {
        ctx.fillStyle = s.g;
        ctx.fillRect(s.x, s.y, s.w, s.h);
      }
    }
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
  }

  drawBrightClipped(ctx, rects, alpha) {
    if (!rects.length || alpha <= .002) return;
    ctx.save();
    ctx.beginPath();
    for (const rc of rects) ctx.rect(rc[0], rc[1], rc[2], rc[3]);
    ctx.clip();
    ctx.globalAlpha = clamp01(alpha);
    if (this.useCache) ctx.drawImage(this.surfaces[1].canvas, 0, 0);
    else this.drawBoard(ctx, 1);
    ctx.restore();
  }

  drawChebyshevRingFrame(ctx, d, strokeStyle, lineWidth, alpha) {
    if (d < 1 || d > 9 || alpha <= .005) return;
    const lo = 9 - d, hi = 9 + d;
    const [x1, y1] = this.cellPt(lo, lo);
    const [x2, y2] = this.cellPt(lo, hi);
    const [x3, y3] = this.cellPt(hi, hi);
    const [x4, y4] = this.cellPt(hi, lo);
    ctx.save();
    ctx.globalAlpha = clamp01(alpha);
    ctx.strokeStyle = strokeStyle;
    ctx.lineWidth = lineWidth;
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.lineTo(x3, y3);
    ctx.lineTo(x4, y4);
    ctx.closePath();
    ctx.stroke();
    // Subtle corner lock vertices
    ctx.fillStyle = strokeStyle;
    for (const [vx, vy] of [[x1, y1], [x2, y2], [x3, y3], [x4, y4]]) {
      ctx.fillRect(vx - 1.5, vy - 1.5, 3, 3);
    }
    ctx.restore();
  }

  drawDiagonalOpening(ctx, loadingAge) {
    // 0 -> 820ms: 4 beams race from corners (0,0), (0,18), (18,0), (18,18) to fixed point (9,9)
    const [cx, cy] = this.cellPt(9, 9);
    const beamT = easeOutCubic(loadingAge / 760);
    const fadeOut = 1 - clamp01((loadingAge - 680) / 560);
    if (fadeOut > .01) {
      const corners = [this.cellPt(0, 0), this.cellPt(0, 18), this.cellPt(18, 0), this.cellPt(18, 18)];
      ctx.save();
      for (const [sx, sy] of corners) {
        const hx = sx + (cx - sx) * beamT;
        const hy = sy + (cy - sy) * beamT;
        const tailT = Math.max(0, beamT - .34);
        const tx = sx + (cx - sx) * tailT;
        const ty = sy + (cy - sy) * tailT;
        const g = ctx.createLinearGradient(tx, ty, hx, hy);
        g.addColorStop(0, 'rgba(61,213,255,0)');
        g.addColorStop(0.65, `rgba(61,213,255,${(.42 * fadeOut).toFixed(3)})`);
        g.addColorStop(1, `rgba(235,213,162,${(.85 * fadeOut).toFixed(3)})`);
        ctx.strokeStyle = g;
        ctx.lineWidth = 1.4;
        ctx.beginPath();
        ctx.moveTo(tx, ty);
        ctx.lineTo(hx, hy);
        ctx.stroke();
        ctx.fillStyle = `rgba(180,242,255,${(.9 * fadeOut).toFixed(3)})`;
        ctx.fillRect(hx - 1.5, hy - 1.5, 3, 3);
      }
      ctx.restore();
    }
    // 640 -> 1500ms: Fixed point (9,9) lock ripple expanding across inner Chebyshev rings
    if (loadingAge >= 620 && loadingAge <= 1560) {
      const rp = (loadingAge - 620) / 940;
      const ringFloat = 1 + easeOutCubic(rp) * 4.5;
      const ringAlpha = Math.sin(Math.PI * clamp01(rp)) * .48;
      const d = Math.min(9, Math.max(1, Math.round(ringFloat)));
      this.drawChebyshevRingFrame(ctx, d, '#3dd5ff', 1, ringAlpha);
      if (d > 1) this.drawChebyshevRingFrame(ctx, d - 1, '#ebd5a2', .8, ringAlpha * .45);
    }
  }

  drawSlotLine(ctx, line, time, still, error) {
    if (!(line >= 0 && line < 2 * N + 2)) return;
    ctx.save();
    const pulse = still ? .22 : .16 + .08 * Math.sin(time * TAU / 3.6);
    ctx.strokeStyle = error ? `rgba(224,104,82,${pulse})` : `rgba(61,213,255,${pulse})`;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let i = 0; i < N; i++) {
      let r, c;
      if (line < N) { r = line; c = i; }
      else if (line < 2 * N) { r = i; c = line - N; }
      else if (line === 2 * N) { r = i; c = i; }
      else { r = i; c = N - 1 - i; }
      const [x, y] = this.cellPt(r, c);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.restore();
  }

  drawReversalHarmonic(ctx, time, still, error) {
    // Continuous reversal-partner harmonic: symmetric pairs (r, 18-r) and (c, 18-c)
    // gliding smoothly around the unique invariant center (9,9).
    if (still) return;
    const w = this.width, h = this.height, font = this.font;
    const cycle = (time % 5.2) / 5.2;
    const radius = 1 + 8 * (0.5 - 0.5 * Math.cos(cycle * TAU)); // smooth oscillation d = 1..9..1
    const lo = Math.max(0, Math.min(8, Math.floor(9 - radius)));
    const hi = 18 - lo;
    const yLo = this.points[lo * N * 2 + 1];
    const yHi = this.points[hi * N * 2 + 1];
    const [xLo] = this.cellPt(9, lo);
    const [xHi] = this.cellPt(9, hi);
    const colTint = error ? '224,104,82' : '61,213,255';
    const goldTint = error ? '237,106,85' : '228,205,152';

    ctx.save();
    // Subtle luminous partner rails
    ctx.strokeStyle = `rgba(${colTint},.14)`;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, yLo); ctx.lineTo(w, yLo);
    ctx.moveTo(0, yHi); ctx.lineTo(w, yHi);
    ctx.moveTo(xLo, 14); ctx.lineTo(xLo, h - 14);
    ctx.moveTo(xHi, 14); ctx.lineTo(xHi, h - 14);
    ctx.stroke();

    // 4 symmetric reflection vertices (lo,lo), (lo,hi), (hi,lo), (hi,hi)
    const verts = [
      this.cellPt(lo, lo), this.cellPt(lo, hi),
      this.cellPt(hi, lo), this.cellPt(hi, hi)
    ];
    for (const [vx, vy] of verts) {
      const grad = ctx.createRadialGradient(vx, vy - font * .6, 1, vx, vy - font * .6, 26);
      grad.addColorStop(0, `rgba(${goldTint},.34)`);
      grad.addColorStop(0.5, `rgba(${colTint},.12)`);
      grad.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = grad;
      ctx.fillRect(vx - 28, vy - font * .6 - 28, 56, 56);
      ctx.fillStyle = `rgba(${goldTint},.82)`;
      ctx.fillRect(vx - 1.5, vy - 1.5, 3, 3);
    }

    // Smoothly illuminate the 4 symmetric corner cells + soft partner strip
    const cellRect = (r, c) => {
      const i = (r * N + c) * 2;
      return [this.points[i] - w / 38, this.points[i + 1] - font * 1.7, w / 19, font * 1.8];
    };
    this.drawBrightClipped(ctx, [
      cellRect(lo, lo), cellRect(lo, hi), cellRect(hi, lo), cellRect(hi, hi)
    ], .52);
    ctx.restore();
  }

  drawResonancePulses(ctx, pulses, still, error) {
    if (still || error || !pulses || !pulses.length) return;
    const w = this.width, h = this.height;
    const [cx, cy] = this.cellPt(9, 9);
    for (const pulse of pulses) {
      const p = clamp01(pulse.age / 900);
      if (p >= 1) continue;
      const env = Math.sin(Math.PI * p);
      const isGold = pulse.kind === 'prime' || pulse.kind === 'sigma';
      const stroke = isGold ? '#ebd5a2' : '#3dd5ff';
      const d = Math.min(9, Math.max(1, Math.round(1 + easeOutCubic(p) * (pulse.kind === 'orbit' ? 5 : 7.5))));
      this.drawChebyshevRingFrame(ctx, d, stroke, isGold ? 1.15 : .95, env * (isGold ? .52 : .4));
      // Brief luminous flash along central invariant axes (row 9 / col 9) crossing fixed point (9,9)
      if (pulse.kind === 'prime' || pulse.kind === 'orbit') {
        ctx.save();
        ctx.globalAlpha = env * (pulse.kind === 'prime' ? .36 : .24);
        ctx.strokeStyle = stroke;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(0, cy); ctx.lineTo(w, cy);
        ctx.moveTo(cx, 12); ctx.lineTo(cx, h - 12);
        ctx.stroke();
        ctx.restore();
      }
    }
  }

  drawFootprints(ctx, footprints, still, error) {
    if (!footprints.length) return;
    const w = this.width, font = this.font;
    const SWEEP_MS = 680;
    for (const fp of footprints) {
      if (!(fp.row >= 0 && fp.row < N)) continue;
      const reach = still ? 1 : easeOutCubic(fp.age / SWEEP_MS);
      const y = this.points[fp.row * N * 2 + 1];
      const [xStart] = this.cellPt(fp.row, 0);
      const [xEnd] = this.cellPt(fp.row, N - 1);
      const leftX = Math.max(0, xStart - w / 38);
      const fullSpan = Math.min(w, xEnd + w / 38) - leftX;
      const headX = leftX + fullSpan * reach;

      // Illuminated cells along the verified magic line
      const settleAlpha = error ? .22 : (still ? .48 : fp.age < SWEEP_MS + 420
        ? .84 - .34 * clamp01((fp.age - SWEEP_MS) / 420) : .50);
      this.drawBrightClipped(ctx, [[leftX, y - font * 1.75, fullSpan * reach, font * 1.9]], settleAlpha);

      // Clean architectural golden hairline along completed portion
      ctx.save();
      ctx.globalAlpha = error ? .18 : (reach < 1 ? .62 : .32);
      ctx.fillStyle = error ? '#e86852' : '#d8c394';
      ctx.fillRect(leftX, y + font * .28, fullSpan * reach, 1);

      // Leading wavefront comet glow while sweeping cell-by-cell
      if (!still && reach < 1) {
        const g = ctx.createRadialGradient(headX, y - font * .5, 1, headX, y - font * .5, 42);
        g.addColorStop(0, error ? 'rgba(240,120,96,.52)' : 'rgba(139,232,255,.55)');
        g.addColorStop(0.45, error ? 'rgba(224,93,70,.22)' : 'rgba(235,213,162,.24)');
        g.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.globalAlpha = 1;
        ctx.fillStyle = g;
        ctx.fillRect(headX - 44, y - font * .5 - 24, 88, 48);
        ctx.fillStyle = '#d8f6ff';
        ctx.fillRect(headX - 1.5, y - font * .8, 3, font * 1.2);
      } else {
        // Subtle twin end-cap lock pips (replaces cluttered repeated Σ text on right margin)
        ctx.globalAlpha = error ? .25 : .58;
        ctx.fillStyle = error ? '#e86852' : '#ebd5a2';
        ctx.fillRect(leftX, y + font * .28 - 2, 2, 5);
        ctx.fillRect(leftX + fullSpan - 2, y + font * .28 - 2, 2, 5);
      }
      ctx.restore();
    }
  }

  render(time, state = {}) {
    if (this.disposed) return;
    const error = state.kind === 'error';
    if (this.errorAccent !== error) { this.errorAccent = error; this.dirty = true; }
    this.rebuild();
    const ctx = this.ctx, w = this.width, h = this.height;
    const p = clamp01(state.progress || 0);
    const still = !!state.still;
    const loading = state.kind === 'loading';
    const bright = state.kind && state.kind !== 'quiet';
    const loadingAge = state.loadingAge || 0;
    const isTransformCue = state.kind === 'exchange' || state.kind === 'exchange-pair' || state.kind === 'unfreeze';

    ctx.clearRect(0, 0, w, h);

    // Optical defocus -> crisp anchor mix during opening of confirm/loading or board transform cues
    let blurMix = 0;
    const isOpening = loading || state.kind === 'confirm';
    if (!still && isOpening && loadingAge < 760) {
      blurMix = (1 - easeOutCubic(loadingAge / 760)) * .72;
    } else if (!still && isTransformCue) {
      blurMix = Math.sin(Math.PI * p) * .55;
    }

    const baseAlpha = still ? .82 : (loading ? .84 : .78) + .06 * Math.sin(time * TAU / 8);
    if (blurMix > .02 && this.useCache && this.surfaces[2]) {
      ctx.globalAlpha = baseAlpha * blurMix;
      ctx.drawImage(this.surfaces[2].canvas, 0, 0);
      ctx.globalAlpha = baseAlpha * (1 - blurMix * .68);
      ctx.drawImage(this.surfaces[0].canvas, 0, 0);
    } else {
      ctx.globalAlpha = baseAlpha;
      if (this.useCache) ctx.drawImage(this.surfaces[0].canvas, 0, 0);
      else this.drawBoard(ctx, 0);
    }

    if (error) this.drawFault(time, still);
    ctx.globalAlpha = 1;

    // Player save slot's real magic line filament during loading
    if ((loading || state.kind === 'sync') && state.slotLine != null) {
      this.drawSlotLine(ctx, state.slotLine, time, still, error);
    }

    const phase = error ? .5 : loading ? (time % 3.2) / 3.2 : bright ? p : (time % 8) / 8;
    const position = Math.min(9, phase * 10);
    const envelope = error ? (still ? .5 : .5 + .1 * Math.sin(time * TAU / 4))
      : loading ? (still ? .2 : .76)
      : state.kind === 'sync' ? (still ? .2 : Math.min(1, p * 4))
      : state.kind === 'unfreeze' ? Math.sin(Math.PI * p) * .56
      : bright ? Math.sin(Math.PI * p) : still ? .12 : .11;

    if (envelope > .001) {
      for (const g of this.cueGroups(state, p, phase, position, still)) {
        if (!g.rects.length) continue;
        this.drawBrightClipped(ctx, g.rects, envelope * g.alphaScale * (error ? .4 : .74));
      }
    }

    // Loading mathematical choreography: opening diagonal convergence + continuous reversal harmonic
    if (isOpening && !still && !error) {
      if (loadingAge < 1560) this.drawDiagonalOpening(ctx, loadingAge);
      else this.drawReversalHarmonic(ctx, time, still, error);
    }

    // Sync (Ready -> Reveal): contracting Chebyshev square shell frames collapsing to fixed point (9,9)
    if (state.kind === 'sync' && !still) {
      const collapseD = Math.max(1, Math.min(9, Math.round(9 - easeInOutSine(Math.min(1, p / .82)) * 8)));
      this.drawChebyshevRingFrame(ctx, collapseD, '#3dd5ff', 1.3, .65);
      if (collapseD < 9) this.drawChebyshevRingFrame(ctx, collapseD + 1, '#ebd5a2', .9, .32);
    }

    // Field-instrument resonance pulses fired when foreground orbit / fixed-point / Σ lock
    this.drawResonancePulses(ctx, state.pulses, still, error);

    // Real boot footprints: cell-by-cell wavefront + clean end-cap lock ticks
    this.drawFootprints(ctx, state.footprints || [], still, error);

    // Peripheral symmetric guide ticks anchored around (9,9)
    const r = Math.min(9, Math.floor(position));
    for (const row of r === 9 ? [9] : [r, 18 - r]) {
      const y = this.points[row * N * 2 + 1];
      ctx.strokeStyle = error ? 'rgba(184,78,60,.68)' : `rgba(184,166,124,${.16 + envelope * .44})`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, y); ctx.lineTo(w * .065, y);
      ctx.moveTo(w, y); ctx.lineTo(w * .935, y);
      ctx.stroke();
      ctx.fillStyle = error ? '#b56754' : '#7cb8c7';
      ctx.globalAlpha = .30 + envelope * .42;
      ctx.fillRect(w * .022, y - 1.5, 3, 3);
      ctx.fillRect(w * .978 - 3, y - 1.5, 3, 3);
    }

    this.eraseForeground(ctx);
    ctx.globalAlpha = 1;
    this.renders++;
  }

  cueGroups(state, p, phase, position, still) {
    const w = this.width, h = this.height, pts = this.points, font = this.font;
    const bar = r => [0, pts[r * N * 2 + 1] - font * 1.75, w, font * 1.9];
    const cell = (r, c) => {
      const i = (r * N + c) * 2;
      return [pts[i] - w / 39, pts[i + 1] - font * 1.65, w / 19.5, font * 1.7];
    };
    const colCell = (r, c) => {
      const i = (r * N + c) * 2;
      return [pts[i] - w / 76, pts[i + 1] - font * .85, w / 38, font * 1.7];
    };
    const column = c => {
      const rects = [];
      for (let r = 0; r < N; r++) rects.push(colCell(r, c));
      return rects;
    };
    const band = (k, make) => {
      const groups = [];
      for (const [d, a] of [[0, 1], [1, .46], [2, .20], [3, .08]]) {
        const q = k - d;
        if (q < 0 || q >= N) continue;
        groups.push({ rects: make(q), alphaScale: a });
      }
      return groups;
    };
    const pair = r => (r === 9 ? [9] : [r, 18 - r]);
    const ringD = (r, c) => Math.max(Math.abs(r - 9), Math.abs(c - 9));

    switch (state.kind) {
      case 'confirm': {
        const rects = [];
        for (let r = 0; r < N; r++) for (const c of [r, 18 - r]) rects.push(cell(r, c));
        const groups = [{ rects, alphaScale: 1 }];
        if (p > .72) groups.push({ rects: [cell(0, 0), cell(0, 18), cell(18, 0), cell(18, 18), cell(9, 9)], alphaScale: 1 });
        return groups;
      }
      case 'loading': {
        // Smooth Gaussian-feathered dual-diagonal sweep crossing at fixed point (9,9)
        if (still) {
          const rects = [];
          for (let r = 0; r < N; r++) for (const c of [r, 18 - r]) rects.push(cell(r, c));
          return [{ rects, alphaScale: 1 }];
        }
        const head = phase * 24 - 2.5;
        const tiers = [[], []];
        for (let r = 0; r < N; r++) {
          const dist = Math.abs(r - head);
          const tier = dist <= 1.15 ? 0 : dist <= 2.9 ? 1 : -1;
          if (tier < 0) continue;
          for (const c of [r, 18 - r]) tiers[tier].push(cell(r, c));
        }
        return [
          { rects: tiers[0], alphaScale: 1 },
          { rects: tiers[1], alphaScale: .36 }
        ];
      }
      case 'arrival': {
        if (p < .5) return band(Math.min(18, Math.floor(p * 2 * N)), r => [bar(r)]);
        return band(Math.min(18, Math.floor((p - .5) * 2 * N)), column);
      }
      case 'sync': {
        if (p >= .82) return [{ rects: [[0, 0, w, h]], alphaScale: 1 }];
        const lead = 9 - (p / .82) * 9;
        const core = [], trail = [];
        for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
          const d = ringD(r, c);
          if (d >= lead) {
            if (d - lead < 1.35) core.push(cell(r, c));
            else trail.push(cell(r, c));
          }
        }
        return [{ rects: core, alphaScale: 1 }, { rects: trail, alphaScale: .52 }];
      }
      case 'return': {
        const lit = Math.ceil(9 * (1 - p)), rects = [];
        for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
          const d = ringD(r, c);
          if (d >= 1 && d <= lit) rects.push(cell(r, c));
        }
        return [{ rects, alphaScale: 1 }];
      }
      case 'exchange-pair': {
        const r = Math.min(9, Math.floor(position)), rects = [];
        for (const row of pair(r)) rects.push(bar(row));
        for (const c of pair(r)) for (let row = 0; row < N; row++) rects.push(colCell(row, c));
        return [{ rects, alphaScale: 1 }];
      }
      case 'slots-pick':
        return band(Math.min(18, Math.floor(p * N)), column);
      default: {
        if (state.kind && !KNOWN_KINDS.has(state.kind) && !this.warnedKinds.has(state.kind)) {
          this.warnedKinds.add(state.kind);
          console.warn('unknown cue kind:', state.kind);
        }
        const r = Math.min(9, Math.floor(position)), rects = [];
        for (const row of pair(r)) rects.push(bar(row));
        return [{ rects, alphaScale: 1 }];
      }
    }
  }

  drawFault(time, still) {
    const ctx = this.ctx, w = this.width, h = this.height;
    const phase = still ? .5 : (time % 4) / 4;
    ctx.globalAlpha = still ? .75 : .65 + .12 * Math.sin(phase * TAU);
    if (this.useCache) ctx.drawImage(this.surfaces[1].canvas, 0, 0);
    else this.drawBoard(ctx, 1);
    ctx.globalAlpha = 1;
    ctx.lineWidth = 2;
    ctx.strokeStyle = 'rgba(224,93,70,.65)';
    for (let k = 0; k < 2; k++) {
      const radius = .24 + ((phase + k * .5) % 1) * .42;
      ctx.beginPath(); ctx.ellipse(w / 2, h / 2, w * radius, h * radius, 0, 0, TAU); ctx.stroke();
    }
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
