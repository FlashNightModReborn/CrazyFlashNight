import * as THREE from '../vendor/three.module.js';
import { OrbitControls } from '../vendor/OrbitControls.js';
import { RoomEnvironment } from '../vendor/RoomEnvironment.js';
import { createSafeModel } from './model.mjs';
import { sampleUnlock, auditPose } from './kinematics.mjs';
import { CONFIG, resolveStructureSpec } from './config.mjs';
import { captureGesture, projectGesture, separateHitRadii } from './gestures.mjs';

const V = THREE.Vector3;
const CAMERAS = {
  default: { eye: [-3.0, 1.75, 6.9], target: [0, -.03, 0] },
  front: { eye: [0, .18, 8.5], target: [0, 0, 0] },
  left: { eye: [-5.5, 2.9, 6], target: [0, 0, 0] },
  right: { eye: [4.8, 2.4, 6.5], target: [0, 0, 0] },
  rear: { eye: [-3.8, 2.5, -6.5], target: [0, 0, 0] },
  mechanism: { eye: [-1.65, .65, 3.7], target: [-.22, -.12, .7] },
};

function shapeDetentProgress(raw) {
  const p = Math.max(0, Math.min(1, Number(raw) || 0));
  const snapStart = CONFIG.interaction.detentSnapStart || 0.88;
  const threshold = CONFIG.interaction.completionThreshold || 0.94;
  if (p >= threshold) return 1;
  if (p < snapStart) return p * (0.86 / snapStart);
  const t = (p - snapStart) / (threshold - snapStart);
  return 0.86 + 0.14 * (t * t * (3 - 2 * t));
}

/** The renderer owns continuous pose; SafeSession owns the discrete interaction. */
export class SafeView {
  constructor(container, { onFinish, onAction, onCancel, onUIEvent, onFeedback, onPose } = {}) {
    this.container = container;
    this.callbacks = { onFinish, onAction, onCancel, onUIEvent, onFeedback, onPose };
    this.disposed = false;
    this.paused = false;
    this.hidden = false;
    this.pending = 0;
    this.frames = 0;
    this.state = null;
    this.pose = null;
    this.animation = null;
    this.demo = null;
    this.drag = null;
    this.jamVisual = { jamA: 0, jamB: 0, jamShudder: 0, bTwitch: 0 };
    this.cutaway = false;
    this.cameraName = 'default';
    this.inspection = false;
    this.lastRun = null;
    this.serviceOpen = false;
    this.positioning = false;
    this.lastFrame = null;
    this.abort = new AbortController();
    this.listenerCount = 0;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: false, powerPreference: 'low-power' });
    const gl = this.renderer.getContext(), info = gl.getExtension('WEBGL_debug_renderer_info');
    this.webglRenderer = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
    const software = /swiftshader|llvmpipe|softpipe|software rasterizer/i.test(this.webglRenderer);
    this.renderQuality = { profile: software ? 'software-light' : 'standard', realtimeShadows: !software, pixelRatio: Math.min(window.devicePixelRatio || 1, software ? 1 : 1.5) };
    this.renderer.setPixelRatio(this.renderQuality.pixelRatio);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = .87;
    this.renderer.shadowMap.enabled = this.renderQuality.realtimeShadows;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.setClearColor(0x17232d, 0);
    this.renderer.domElement.setAttribute('aria-label', '保险柜三维操作面');
    this.container.prepend(this.renderer.domElement);
    this.scene = new THREE.Scene();
    this.scene.fog = new THREE.Fog(0x1b2933, 11, 30);
    this.camera = new THREE.PerspectiveCamera(35, 1, .08, 80);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = false;
    this.controls.enablePan = false;
    this.controls.minDistance = .85;
    this.controls.maxDistance = 12;
    this.controls.maxPolarAngle = Math.PI * .72;
    this.controls.minPolarAngle = .35;
    this.controls.mouseButtons = { LEFT: null, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.ROTATE };
    this.controls.touches = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_PAN };
    this.controlChange = () => { if (!this.positioning) this.inspection = true; this.invalidate(); };
    this.controls.addEventListener('change', this.controlChange);
    const pmrem = new THREE.PMREMGenerator(this.renderer), room = new RoomEnvironment();
    this.environment = pmrem.fromScene(room, .055);
    this.scene.environment = this.environment.texture;
    room.dispose();
    pmrem.dispose();
    this.scene.add(new THREE.HemisphereLight(0xeaf3fa, 0x172027, .65));
    this.key = new THREE.DirectionalLight(0xffe6c1, 2.5);
    this.key.position.set(-3.3, 6, 5);
    this.key.castShadow = this.renderQuality.realtimeShadows;
    this.key.shadow.mapSize.set(1536, 1536);
    Object.assign(this.key.shadow.camera, { left: -4, right: 4, top: 4, bottom: -4, near: .1, far: 18 });
    this.key.shadow.bias = -.0002;
    this.key.shadow.normalBias = .03;
    this.scene.add(this.key);
    const rim = new THREE.DirectionalLight(0xa1c9e8, 1.5);
    rim.position.set(5, 2, -2);
    this.scene.add(rim);
    const fill = new THREE.DirectionalLight(0xd0dfef, .8);
    fill.position.set(1, 1, 5);
    this.scene.add(fill);
    this.floor = new THREE.Mesh(new THREE.PlaneGeometry(200, 200), new THREE.MeshStandardMaterial({ color: 0x0c141b, roughness: 1, metalness: 0 }));
    this.floor.rotation.x = -Math.PI / 2;
    this.floor.position.y = -1.595;
    this.floor.receiveShadow = true;
    this.scene.add(this.floor);
    const shadowCanvas = document.createElement('canvas');
    shadowCanvas.width = shadowCanvas.height = 128;
    const ctx = shadowCanvas.getContext('2d'), gradient = ctx.createRadialGradient(64, 64, 8, 64, 64, 63);
    gradient.addColorStop(0, 'rgba(0,0,0,.72)');
    gradient.addColorStop(.35, 'rgba(0,0,0,.52)');
    gradient.addColorStop(.75, 'rgba(0,0,0,.16)');
    gradient.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, 128, 128);
    this.contactTexture = new THREE.CanvasTexture(shadowCanvas);
    this.contactShadow = new THREE.Mesh(new THREE.PlaneGeometry(4.1, 2.8), new THREE.MeshBasicMaterial({ map: this.contactTexture, transparent: true, depthWrite: false, opacity: software ? .8 : .35 }));
    this.contactShadow.rotation.x = -Math.PI / 2;
    this.contactShadow.position.set(0, -1.592, 0);
    this.scene.add(this.contactShadow);
    this.model = createSafeModel();
    this.scene.add(this.model.root);
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(container);
    this.setCamera('default');
    this.resize();
    const listen = (node, name, fn, opts = {}) => { node.addEventListener(name, fn, { ...opts, signal: this.abort.signal }); this.listenerCount++; };
    listen(this.renderer.domElement, 'pointerdown', e => this.pointerDown(e), { capture: true });
    listen(window, 'pointermove', e => this.pointerMove(e));
    listen(window, 'pointerup', e => this.pointerUp(e));
    listen(window, 'pointercancel', e => { if (this.drag && e.pointerId === this.drag.id) this.cancelDrag('pointer_cancel'); });
    listen(this.renderer.domElement, 'lostpointercapture', e => { if (this.drag && e.pointerId === this.drag.id) this.cancelDrag('lost_pointer_capture'); });
    listen(window, 'blur', () => this.cancelDrag('window_blur'));
    listen(this.renderer.domElement, 'contextmenu', e => e.preventDefault());
    listen(this.renderer.domElement, 'webglcontextlost', e => { e.preventDefault(); if (this.disposed) return; this.pause(true); this.callbacks.onFeedback?.('三维上下文丢失。请重新装载。', 'error'); this.callbacks.onUIEvent?.('webgl_context_lost'); });
  }

  async ready() {
    this.renderNow();
    await new Promise(resolve => {
      let done = false;
      const finish = () => { if (!done) { done = true; resolve(); } };
      if (typeof requestAnimationFrame === 'function') requestAnimationFrame(finish);
      setTimeout(finish, 16);
    });
    this.renderNow();
  }

  resize() {
    if (this.disposed) return;
    const rect = this.container.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) return;
    const changed = this.renderWidth !== rect.width || this.renderHeight !== rect.height;
    if (changed && this.drag) this.cancelDrag('viewport_resize');
    this.renderWidth = rect.width;
    this.renderHeight = rect.height;
    this.renderer.setSize(rect.width, rect.height, false);
    this.camera.aspect = rect.width / rect.height;
    this.camera.updateProjectionMatrix();
    if (this.cameraName === 'operation' && !this.inspection) this.setCamera('operation');
    this.invalidate();
  }

  setCamera(name = 'default') {
    if (this.drag) return false;
    this.positioning = true;
    if (name === 'operation') {
      this.syncModelPose();
      const c = CONFIG.operationView, anchor = this.model.serviceAnchors.overview.getWorldPosition(new V());
      const distance = Math.max(c.height, c.width / this.camera.aspect) * c.padding / (2 * Math.tan(THREE.MathUtils.degToRad(c.fov / 2)));
      this.camera.fov = c.fov;
      this.controls.target.copy(anchor);
      this.camera.position.copy(anchor).add(new V(...c.direction).normalize().multiplyScalar(distance));
    } else {
      const p = CAMERAS[name] || CAMERAS.default;
      this.camera.fov = 35;
      this.camera.position.fromArray(p.eye);
      this.controls.target.fromArray(p.target);
    }
    this.camera.updateProjectionMatrix();
    this.controls.update();
    this.camera.updateMatrixWorld(true);
    this.positioning = false;
    this.cameraName = name;
    this.inspection = !['default', 'operation'].includes(name);
    this.invalidate();
    return true;
  }

  setCutaway(value) { this.cutaway = !!value; this.model.setCutaway(this.cutaway); this.invalidate(); }

  prepareTool() {
    if (this.drag || this.disposed) return false;
    const changed = this.cameraName !== 'operation' || this.inspection;
    const coverChanged = !this.serviceOpen;
    this.serviceOpen = true;
    this.model.setServiceAccess(true);
    if (changed) this.setCamera('operation');
    this.renderNow();
    if (changed || coverChanged) this.callbacks.onUIEvent?.('camera_for_tool', { name: 'operation', instant: true, coverOpened: coverChanged });
    return true;
  }

  preparePassword() {
    if (this.drag) this.cancelDrag('password_focus');
    if (this.cameraName !== 'default' || this.inspection) this.setCamera('default');
  }

  setState(state, reason) {
    if (this.disposed) return;
    this.state = state;
    if (this.drag && !state.drag && !this.drag.jammed) this.cancelDrag('authority_cancelled', false);
    if (state.run !== this.lastRun) {
      this.lastRun = state.run;
      this.animation = null;
      this.demo = null;
      this.jamVisual = { jamA: 0, jamB: 0, jamShudder: 0, bTwitch: 0 };
      this.cancelDrag('run_changed', false);
      this.model.setVariants(state.variants);
      this.model.setCode?.(state.puzzle.answer);
      this.serviceOpen = false;
      this.model.setServiceAccess(false);
      this.setCamera('default');
    }
    if (state.door === 'opening' && this.animation?.token !== state.unlock.token) {
      this.animation = { token: state.unlock.token, route: state.unlock.route, elapsed: 0, last: state.suspended ? null : performance.now() };
      this.setCamera('default');
    }
    if (state.door === 'locked') this.animation = null;
    this.pause(state.suspended);
    this.invalidate();
  }

  advanceTimeline(now) {
    const anim = this.demo || this.animation;
    if (anim && (this.demo || this.state?.door === 'opening')) {
      if (anim.last !== null) anim.elapsed += Math.max(0, now - anim.last);
      anim.last = now;
    }
  }

  setActivity(paused, hidden) {
    const wasActive = !this.paused && !this.hidden, active = !paused && !hidden;
    if (wasActive === active) { this.paused = paused; this.hidden = hidden; return; }
    const now = performance.now();
    if (wasActive) this.advanceTimeline(now);
    this.paused = paused;
    this.hidden = hidden;
    for (const anim of [this.animation, this.demo]) if (anim) anim.last = active ? now : null;
    if (!active) {
      if (this.pending) cancelAnimationFrame(this.pending);
      this.pending = 0;
      this.cancelDrag('suspended', false);
    } else this.invalidate();
  }

  pause(value) { this.setActivity(!!value, this.hidden); }
  setHidden(value) { this.setActivity(this.paused, !!value); }

  invalidate() {
    if (this.disposed || this.paused || this.hidden || this.pending) return;
    this.pending = requestAnimationFrame(now => { this.pending = 0; this.tick(now); });
  }

  basePose() {
    const s = this.state;
    const a = s?.mechanics.a.progress || 0, b = s?.mechanics.b.progress || 0;
    const activeStage = this.drag?.stage || s?.drag?.stage || null;
    const tool = (this.drag || s?.drag) ? s?.selectedTool : null;
    return {
      code: s?.puzzle.answer || '700',
      a, b,
      jamA: this.jamVisual.jamA,
      jamB: this.jamVisual.jamB,
      jamShudder: this.jamVisual.jamShudder,
      bTwitch: this.jamVisual.bTwitch,
      dialAngle: 0,
      wheelAngles: [0, 0, 0],
      fence: 0,
      latch: b,
      handle: 0,
      bolts: 0,
      door: 0,
      tool,
      activeStage,
      toolProgress: activeStage ? (s?.mechanics[activeStage]?.progress || 0) : 0,
      label: '承压联锁保持',
    };
  }

  tick(rafTimestamp) {
    if (this.disposed || this.paused || this.hidden) return;
    const now = performance.now();
    this.lastFrame = { rafTimestamp, callbackAtMs: now, queueLagMs: Math.max(0, now - rafTimestamp) };
    this.advanceTimeline(now);
    this.renderNow();
    if (this.demo) {
      if (this.demo.elapsed >= this.demo.duration) { this.stopDemo(); return; }
      this.invalidate();
    } else if (this.animation && this.state?.door === 'opening') {
      if (this.animation.elapsed >= CONFIG.timing.unlockMs) {
        const token = this.animation.token;
        this.callbacks.onFinish?.(token);
      } else this.invalidate();
    }
  }

  presentationPose() {
    let p = this.basePose();
    if (this.demo) {
      p = sampleUnlock('password', this.state?.puzzle.answer || '700', Math.min(1, this.demo.elapsed / this.demo.duration));
    } else if (this.animation && this.state?.door !== 'locked') {
      const t = this.state?.door === 'open' ? 1 : Math.min(1, this.animation.elapsed / CONFIG.timing.unlockMs);
      p = { ...sampleUnlock(this.animation.route, this.state.puzzle.answer, t), a: p.a, b: p.b };
    }
    return p;
  }

  syncModelPose(p = this.presentationPose()) {
    this.pose = p;
    this.model.apply(p);
    this.model.root.updateMatrixWorld(true);
    return p;
  }

  renderNow() {
    if (this.disposed) return;
    const p = this.presentationPose();
    if (this.cameraName === 'default' && !this.inspection) {
      const d = p.door, h = Math.sin(Math.PI * d), c = CONFIG.openingView, q = Math.max(0, Math.min(1, (d - .5) / .5)), late = q * q * (3 - 2 * q);
      const endFov = Math.max(35, THREE.MathUtils.radToDeg(2 * Math.atan(Math.tan(THREE.MathUtils.degToRad(c.fittedFovDegrees / 2)) * c.referenceAspect / this.camera.aspect)) + c.marginDegrees);
      const fov = Math.max(35 + (this.serviceOpen ? 4.8 : 0) * h, 35 + (endFov - 35) * late);
      this.controls.target.set((this.serviceOpen ? 1 : .6) * d, -.03 - .07 * d - (this.serviceOpen ? .30 : .10) * h, (this.serviceOpen ? 1.2 : .7) * d);
      this.camera.lookAt(this.controls.target);
      this.camera.updateMatrixWorld(true);
      if (this.camera.fov !== fov) { this.camera.fov = fov; this.camera.updateProjectionMatrix(); }
    }
    this.syncModelPose(p);
    this.renderer.render(this.scene, this.camera);
    this.frames++;
    this.projectTargets();
    this.callbacks.onPose?.(p, this.demo ? true : false);
  }

  projectWorld(world) {
    const point = world.clone().project(this.camera);
    const r = this.container.getBoundingClientRect();
    return { x: (point.x * .5 + .5) * r.width, y: (-.5 * point.y + .5) * r.height, z: point.z, clientX: r.left + (point.x * .5 + .5) * r.width, clientY: r.top + (-.5 * point.y + .5) * r.height };
  }

  projectPoint(obj) { return this.projectWorld(obj.getWorldPosition(new V())); }
  projectTargets() { this.targets = { a: this.projectPoint(this.model.targets.a), b: this.projectPoint(this.model.targets.b) }; }

  operationGesture(stage) {
    this.syncModelPose();
    const g = this.model.getServiceGesture(stage);
    return { ...g, axis: this.projectPoint(g.axis), handle: this.projectPoint(g.handle), path: g.path.map(q => ({ p: q.p, ...this.projectWorld(new V(...q.position)) })) };
  }

  hit(clientX, clientY) {
    if (!this.serviceOpen || this.inspection || this.cameraName !== 'operation') return null;
    this.syncModelPose();
    this.projectTargets();
    this.hitRadii = separateHitRadii(this.targets.a, this.targets.b, CONFIG.interaction.hitRadiusPixels, CONFIG.interaction.hitGapPixels);
    for (const stage of ['a', 'b']) {
      const p = this.targets[stage];
      if (Math.hypot(clientX - p.clientX, clientY - p.clientY) <= this.hitRadii[stage] && p.z < 1 && p.x >= 0 && p.y >= 0 && p.x <= this.renderWidth && p.y <= this.renderHeight) return stage;
    }
    return null;
  }

  stageSpec(stage) {
    const dir = stage === 'a' ? (this.state?.variants.aDir ?? 1) : (this.state?.variants.bDir ?? 1);
    return resolveStructureSpec(stage, this.state?.variants[stage] ?? 0, dir);
  }

  pointerDown(e) {
    if (this.drag) { e.stopImmediatePropagation(); return; }
    if (e.isPrimary === false || e.button !== 0 || this.disposed || this.paused || this.hidden || this.demo || !this.state || this.state.door !== 'locked') return;
    if (this.inspection || this.cameraName !== 'operation') {
      if (this.state.selectedTool) this.callbacks.onFeedback?.('当前为全貌或检查视角；取工具即回到稳定操作近景。');
      return;
    }
    const stage = this.hit(e.clientX, e.clientY);
    if (!stage) return;
    e.preventDefault();
    e.stopPropagation();
    e.stopImmediatePropagation();
    const spec = this.stageSpec(stage);
    const result = this.callbacks.onAction?.(stage, { direction: spec.direction, progress: 0, commit: false });
    const interlockJammed = !result?.ok && result?.code === 'prerequisite' && stage === 'b' && this.state.selectedTool === 'hook';
    if (!result?.ok && !interlockJammed) {
      if (result?.message) this.callbacks.onFeedback?.(result.message, 'error');
      return;
    }
    const operation = this.operationGesture(stage), path = operation.path.map(q => ({ p: q.p, x: q.clientX, y: q.clientY }));
    let gesture;
    try {
      gesture = captureGesture({ kind: operation.kind, direction: spec.direction, path, x: e.clientX, y: e.clientY, distance: CONFIG.interaction.dragPixels, tolerance: CONFIG.interaction.arcTolerancePixels });
      if (gesture.kind === 'linear') {
        const first = path[0], end = path.at(-1), dx = end.x - first.x, dy = end.y - first.y, l = Math.hypot(dx, dy);
        if (l >= 8) gesture.vector = [dx / l, dy / l];
        else throw new Error('当前检查角度几乎看不到运动方向，请重新取工具回到近景。');
      }
    } catch (error) {
      this.callbacks.onCancel?.('projection_degenerate');
      this.callbacks.onFeedback?.(error.message, 'error');
      return;
    }
    this.controls.enabled = false;
    this.drag = { stage, id: e.pointerId, x: e.clientX, y: e.clientY, progress: 0, wrong: false, jammed: interlockJammed, snapped: false, spec, gesture, operation };
    this.renderer.domElement.setPointerCapture(e.pointerId);
    if (interlockJammed) {
      this.callbacks.onFeedback?.('牵引受阻：B联锁挡肩走了 ~12% 空程后撞上结构Ⅰ的黄铜联锁下舌！请先换卸载键完成结构Ⅰ。', 'error');
    }
    this.callbacks.onUIEvent?.('pointer_action_start', { stage, jammed: interlockJammed, polarity: spec.dir, x: e.clientX, y: e.clientY, kind: gesture.kind, contactPath: operation.path.map(({ p, x, y }) => ({ p, x, y })) });
    this.invalidate();
  }

  pointerMove(e) {
    const d = this.drag;
    if (!d || e.pointerId !== d.id) return;
    const projected = projectGesture(d.gesture, e.clientX, e.clientY);
    if (d.jammed) {
      // T1 physical jammed micro-travel: B moves up to 12% across backlash before colliding with A's interlock tongue.
      const raw = projected.valid ? projected.progress : 0;
      const jamB = Math.min(CONFIG.interaction.jammedMaxProgress || 0.12, raw * 0.28);
      const hittingTongue = raw > 0.25;
      this.jamVisual.jamB = jamB;
      this.jamVisual.jamShudder = hittingTongue ? Math.sin(performance.now() * 0.14) * 0.006 : 0;
      this.renderNow();
      return;
    }
    if (!projected.valid) {
      if (projected.reason !== 'direction' && d.progress >= CONFIG.interaction.completionThreshold) {
        // Already reached the mechanical stop; over-pulling slightly outside the arc corridor holds at 1.0
        d.progress = 1;
        this.callbacks.onAction?.(d.stage, { direction: d.spec.direction, progress: 1, commit: false });
        this.renderNow();
        return;
      }
      if (projected.reason === 'direction') {
        const stopperNudge = CONFIG.interaction.stopperNudgeProgress || -0.045;
        if (d.stage === 'a') this.jamVisual.jamA = stopperNudge;
        else this.jamVisual.jamB = stopperNudge;
        this.jamVisual.jamShudder = Math.sin(performance.now() * 0.14) * 0.004;
        if (!d.wrong) {
          this.callbacks.onAction?.(d.stage, { direction: 'invalid', progress: 0, commit: false });
          this.callbacks.onFeedback?.('撞击黄铜止挡销！请认准止挡销位置，向对侧导槽敞口方向拖动。', 'error');
          d.wrong = true;
        }
        d.progress = 0;
        this.renderNow();
        return;
      }
      if (!d.wrong) {
        this.callbacks.onFeedback?.('请顺着接触点轨迹方向拖动。');
        d.wrong = true;
      }
      this.renderNow();
      return;
    }
    this.jamVisual.jamA = 0;
    this.jamVisual.jamB = 0;
    this.jamVisual.jamShudder = 0;
    if (d.wrong) this.callbacks.onFeedback?.('已回到有效行程；拖到止点咔哒啮合后松手。');
    d.wrong = false;
    d.progress = projected.progress;
    const shaped = shapeDetentProgress(d.progress);
    if (d.progress >= CONFIG.interaction.completionThreshold && !d.snapped) {
      d.snapped = true;
      if (d.stage === 'a') {
        this.jamVisual.bTwitch = 0.024;
        this.callbacks.onFeedback?.('咔哒！承压联锁舌已顶起脱扣，松手即可保持止点。', 'success');
      } else {
        this.callbacks.onFeedback?.('咔哒！释放机构已拉到位并收回小锁舌，松手即可开门！', 'success');
      }
    } else if (d.progress < CONFIG.interaction.completionThreshold) {
      d.snapped = false;
      this.jamVisual.bTwitch = 0;
    }
    this.callbacks.onAction?.(d.stage, { direction: d.spec.direction, progress: shaped, commit: false });
  }

  pointerUp(e) {
    const d = this.drag;
    if (!d || e.pointerId !== d.id) return;
    this.pointerMove(e);
    this.drag = null;
    this.jamVisual = { jamA: 0, jamB: 0, jamShudder: 0, bTwitch: 0 };
    this.controls.enabled = true;
    try { this.renderer.domElement.releasePointerCapture(d.id); } catch {}
    if (d.jammed) {
      this.callbacks.onUIEvent?.('pointer_action_end', { stage: d.stage, jammed: true, progress: 0, accepted: false, code: 'prerequisite' });
      this.renderNow();
      this.invalidate();
      return;
    }
    let result;
    if (d.wrong) {
      result = this.callbacks.onCancel?.('wrong_release');
    } else {
      result = this.callbacks.onAction?.(d.stage, { direction: d.spec.direction, progress: d.progress, commit: true });
    }
    if (result?.code === 'incomplete') this.callbacks.onFeedback?.('还未越过啮合止点（88%–94%），当前结构已回弹复位；已完成的前级保持。');
    if (result?.code === 'complete') this.callbacks.onFeedback?.('卸荷止点已咔哒锁定！黄铜联锁下舌已让位，请换牵引钩处理结构Ⅱ。', 'success');
    if (result?.code === 'opening') this.callbacks.onFeedback?.('牵引到位，小锁舌收回，正在开门。', 'success');
    this.callbacks.onUIEvent?.('pointer_action_end', { stage: d.stage, progress: d.progress, accepted: !!result?.ok, code: result?.code });
    if (this.state?.door === 'locked') this.renderNow();
    this.invalidate();
  }

  cancelDrag(reason = 'cancel', notify = true) {
    const d = this.drag;
    this.drag = null;
    this.jamVisual = { jamA: 0, jamB: 0, jamShudder: 0, bTwitch: 0 };
    if (this.controls) this.controls.enabled = true;
    if (d) {
      try { this.renderer.domElement.releasePointerCapture(d.id); } catch {}
      if (notify && !d.jammed) {
        this.callbacks.onCancel?.(reason);
      }
      if (!this.disposed && !this.paused && !this.hidden) this.renderNow();
    }
  }

  startDemo() {
    if (this.disposed || !this.state?.panelOpen || this.state.door === 'opening') return false;
    this.cancelDrag('demo');
    this.demo = { elapsed: 0, last: null, duration: CONFIG.timing.demoMs, previousCutaway: this.cutaway, previousCamera: this.cameraName };
    this.setCutaway(true);
    this.setCamera('default');
    this.callbacks.onUIEvent?.('demo_start', { durationMs: CONFIG.timing.demoMs });
    this.invalidate();
    return true;
  }

  stopDemo() {
    if (!this.demo) return;
    const saved = this.demo;
    this.demo = null;
    this.setCutaway(saved.previousCutaway);
    this.setCamera(saved.previousCamera);
    this.callbacks.onUIEvent?.('demo_end');
    this.renderNow();
    this.invalidate();
  }

  stats() {
    return {
      disposed: this.disposed,
      frames: this.frames,
      rafPending: !!this.pending,
      listeners: this.listenerCount,
      resizeObserverConnected: !this.disposed,
      geometries: this.renderer.info.memory.geometries,
      textures: this.renderer.info.memory.textures,
      drawCalls: this.renderer.info.render.calls,
      triangles: this.renderer.info.render.triangles,
      webglRenderer: this.webglRenderer,
      renderQuality: { ...this.renderQuality },
      poseAudit: this.pose ? auditPose(this.pose) : null,
      modelAudit: this.model.getAuditState?.(),
    };
  }

  dispose() {
    if (this.disposed) return;
    this.cancelDrag('dispose');
    this.disposed = true;
    if (this.pending) cancelAnimationFrame(this.pending);
    this.pending = 0;
    this.abort.abort();
    this.listenerCount = 0;
    this.resizeObserver.disconnect();
    this.controls.removeEventListener('change', this.controlChange);
    this.controls.dispose();
    this.model.dispose();
    this.floor.geometry.dispose();
    this.floor.material.dispose();
    this.contactShadow.geometry.dispose();
    this.contactShadow.material.dispose();
    this.contactTexture.dispose();
    this.environment.dispose();
    this.key.shadow.map?.dispose();
    this.renderer.renderLists.dispose();
    this.renderer.dispose();
    this.renderer.forceContextLoss();
    this.renderer.domElement.remove();
    this.scene.clear();
    this.animation = null;
    this.demo = null;
  }
}
