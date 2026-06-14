import { useCallback, useState } from "react";
import type { AnkitApi, Diagnostics, OpResult, JvmOpResult, AnimateInstall } from "../../shared/ipc-types.js";
import type { MotionLevel } from "./motion-utils.js";
import type { LayoutController } from "../hooks/useLayoutResize.js";
import OpResultView from "./OpResultView.js";

interface Props {
  api: AnkitApi;
  motionLevel: MotionLevel;
  layout: LayoutController;
}

type PlanKey = "install" | "cache" | "jvm" | "sidebar";

/**
 * Tab A — "AN 维护". Every mutating action is plan-first: clicking the action
 * runs the op with apply:false, shows the OpResult plan, and only an explicit
 * "应用 / Apply" click re-runs it with apply:true. Discovered installs are shown
 * as selectable cards; the per-install actions target the selected one.
 */
export default function MaintenancePanel({ api }: Props) {
  const [diag, setDiag] = useState<Diagnostics | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [installIndex, setInstallIndex] = useState(0);

  const [swfPath, setSwfPath] = useState("");
  const [datPath, setDatPath] = useState("");
  const [xmxMb, setXmxMb] = useState(2048);

  const [plans, setPlans] = useState<Record<PlanKey, OpResult | null>>({
    install: null, cache: null, jvm: null, sidebar: null
  });

  const setPlan = useCallback((key: PlanKey, value: OpResult | null) => {
    setPlans((prev) => ({ ...prev, [key]: value }));
  }, []);

  const runDoctor = useCallback(async () => {
    setBusy(true);
    setError(null);
    try {
      const d = await api.doctor();
      setDiag(d);
      if (d.installs.length > 0 && installIndex >= d.installs.length) setInstallIndex(0);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }, [api, installIndex]);

  const installs = diag?.installs ?? [];
  const hasInstalls = installs.length > 0;

  const pickSwf = useCallback(async () => {
    const r = await api.pickSwf();
    if (!r.canceled && r.path) setSwfPath(r.path);
  }, [api]);
  const pickDat = useCallback(async () => {
    const r = await api.pickDat();
    if (!r.canceled && r.path) setDatPath(r.path);
  }, [api]);

  const runOp = useCallback(
    async (key: PlanKey, fn: () => Promise<OpResult | JvmOpResult>) => {
      setBusy(true);
      setError(null);
      try {
        const r = await fn();
        setPlan(key, r);
      } catch (e) {
        setError(String(e));
      } finally {
        setBusy(false);
      }
    },
    [setPlan]
  );

  const planInstall = useCallback(
    () => runOp("install", () => api.installSwf({ installIndex, srcSwf: swfPath, apply: false })),
    [api, installIndex, swfPath, runOp]
  );
  const applyInstall = useCallback(
    () => runOp("install", () => api.installSwf({ installIndex, srcSwf: swfPath, apply: true })),
    [api, installIndex, swfPath, runOp]
  );
  const planCache = useCallback(
    () => runOp("cache", () => api.clearCache({ installIndex, apply: false })),
    [api, installIndex, runOp]
  );
  const applyCache = useCallback(
    () => runOp("cache", () => api.clearCache({ installIndex, apply: true })),
    [api, installIndex, runOp]
  );
  const planJvm = useCallback(
    () => runOp("jvm", () => api.setJvmMemory({ installIndex, xmxMb, apply: false })),
    [api, installIndex, xmxMb, runOp]
  );
  const applyJvm = useCallback(
    () => runOp("jvm", () => api.setJvmMemory({ installIndex, xmxMb, apply: true })),
    [api, installIndex, xmxMb, runOp]
  );
  const planSidebar = useCallback(
    () => runOp("sidebar", () => api.tightenSidebar({ datPath, apply: false })),
    [api, datPath, runOp]
  );
  const applySidebar = useCallback(
    () => runOp("sidebar", () => api.tightenSidebar({ datPath, apply: true })),
    [api, datPath, runOp]
  );

  const openFolder = useCallback(
    async (kind: "windowSwf" | "commands" | "configuration" | "cache") => {
      try {
        await api.openFolder({ installIndex, kind });
      } catch (e) {
        setError(String(e));
      }
    },
    [api, installIndex]
  );

  const planReady = (key: PlanKey): boolean =>
    Boolean(plans[key] && plans[key]!.ok && !plans[key]!.applied);

  return (
    <div className="tab-body maintenance">
      {/* Doctor */}
      <section className="card motion-surface">
        <div className="card-head">
          <h2>AN 体检</h2>
          <button className="btn btn-primary" onClick={() => void runDoctor()} disabled={busy}>
            {busy ? "扫描中…" : "运行体检"}
          </button>
        </div>
        {error && <div className="error-bar">⚠ {error}</div>}

        {diag && (
          <div className="diag">
            <div className="diag-machine">
              <span className="chip">{diag.machine.platform}</span>
              <span className="chip">OS {diag.machine.osRelease}</span>
              <span className="chip">Node {diag.machine.nodeVersion}</span>
              <span className={`chip ${diag.sharedObjectsExists ? "chip-ok" : "chip-warn"}`} title={diag.sharedObjectsBase ?? ""}>
                SharedObjects {diag.sharedObjectsBase ? (diag.sharedObjectsExists ? "✓" : "缺失") : "未找到"}
              </span>
            </div>

            {hasInstalls ? (
              <div className="install-grid">
                {installs.map((inst, i) => (
                  <InstallCard
                    key={inst.windowSwfDir}
                    install={inst}
                    index={i}
                    active={i === installIndex}
                    onSelect={() => setInstallIndex(i)}
                  />
                ))}
              </div>
            ) : (
              <div className="empty-hint">未发现 Adobe Animate 安装（WindowSWF 目录）。</div>
            )}
          </div>
        )}

        {!diag && <div className="empty-hint">运行体检以发现 Adobe Animate 安装并启用维护操作。</div>}
      </section>

      {hasInstalls && (
        <>
          <section className="card motion-surface">
            <div className="card-head"><h2>打开文件夹</h2></div>
            <div className="btn-row">
              <button className="btn btn-ghost" onClick={() => void openFolder("windowSwf")}>WindowSWF</button>
              <button className="btn btn-ghost" onClick={() => void openFolder("commands")}>Commands</button>
              <button className="btn btn-ghost" onClick={() => void openFolder("configuration")}>Configuration</button>
              <button className="btn btn-ghost" onClick={() => void openFolder("cache")}>Cache (tmp)</button>
            </div>
          </section>

          <div className="card-grid">
            <section className="card motion-surface">
              <div className="card-head"><h2>安装插件 .swf</h2></div>
              <div className="field-row">
                <input
                  className="text-input" type="text" placeholder="选择 .swf 源文件…"
                  value={swfPath} onChange={(e) => setSwfPath(e.target.value)}
                />
                <button className="btn btn-browse" onClick={() => void pickSwf()}>浏览…</button>
              </div>
              <div className="btn-row">
                <button className="btn btn-primary" onClick={() => void planInstall()} disabled={busy || !swfPath}>生成计划</button>
                <button className="btn btn-apply" onClick={() => void applyInstall()} disabled={busy || !planReady("install")}>应用 / Apply</button>
              </div>
              <OpResultView result={plans.install} />
            </section>

            <section className="card motion-surface">
              <div className="card-head"><h2>JVM 内存 (-Xmx)</h2></div>
              <div className="field-row">
                <label className="field-label">-Xmx (MB)</label>
                <input
                  className="num-input" type="number" min={256} step={256}
                  value={xmxMb} onChange={(e) => setXmxMb(Number(e.target.value))}
                />
              </div>
              <div className="btn-row">
                <button className="btn btn-primary" onClick={() => void planJvm()} disabled={busy || xmxMb < 256}>生成计划</button>
                <button className="btn btn-apply" onClick={() => void applyJvm()} disabled={busy || !planReady("jvm")}>应用 / Apply</button>
              </div>
              <OpResultView result={plans.jvm} />
            </section>

            <section className="card motion-surface">
              <div className="card-head"><h2>清理缓存 (tmp)</h2></div>
              <div className="btn-row">
                <button className="btn btn-primary" onClick={() => void planCache()} disabled={busy}>生成计划</button>
                <button className="btn btn-apply" onClick={() => void applyCache()} disabled={busy || !planReady("cache")}>应用 / Apply</button>
              </div>
              <OpResultView result={plans.cache} />
            </section>
          </div>
        </>
      )}

      {/* Tighten sidebar — file based, independent of install list */}
      <section className="card motion-surface">
        <div className="card-head"><h2>收紧侧边栏字典 (.dat)</h2></div>
        <div className="field-row">
          <input
            className="text-input" type="text" placeholder="选择侧边栏 .dat 文件…"
            value={datPath} onChange={(e) => setDatPath(e.target.value)}
          />
          <button className="btn btn-browse" onClick={() => void pickDat()}>浏览…</button>
        </div>
        <div className="btn-row">
          <button className="btn btn-primary" onClick={() => void planSidebar()} disabled={busy || !datPath}>生成计划</button>
          <button className="btn btn-apply" onClick={() => void applySidebar()} disabled={busy || !planReady("sidebar")}>应用 / Apply</button>
        </div>
        <OpResultView result={plans.sidebar} />
      </section>
    </div>
  );
}

function InstallCard({
  install, index, active, onSelect
}: {
  install: AnimateInstall;
  index: number;
  active: boolean;
  onSelect: () => void;
}) {
  const flag = (ok: boolean) => (
    <span className={`flag ${ok ? "flag-ok" : "flag-bad"}`}>{ok ? "✓" : "✗"}</span>
  );
  return (
    <button
      type="button"
      className={`install-card ${active ? "install-card-active" : ""}`}
      onClick={onSelect}
      aria-pressed={active}
    >
      <div className="install-card-head">
        <span className="install-card-index">#{index + 1}</span>
        {active && <span className="install-card-tag">已选</span>}
      </div>
      <div className="install-card-path" title={install.windowSwfDir}>{install.windowSwfDir}</div>
      <div className="install-card-flags">
        <span>{flag(install.windowSwfExists)} WindowSWF</span>
        <span>{flag(install.jvmIniExists)} jvm.ini</span>
        <span>{flag(install.commandsExists)} Commands</span>
      </div>
    </button>
  );
}
