import { useEffect, useState } from "react";
import type { AnkitApi, AnimateInstall, OpResult } from "../../shared/ipc-types.js";
import OpResultView from "./OpResultView.js";

interface Props {
  api: AnkitApi;
  installIndex: number;
  install: AnimateInstall;
  latestInstall: OpResult | null;
}

export default function PluginRemovalCard({ api, installIndex, install, latestInstall }: Props) {
  const [files, setFiles] = useState<string[] | null>(null);
  const [selection, setSelection] = useState("");
  const [result, setResult] = useState<{ name: string; value: OpResult } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let current = true;
    setError("");
    setResult(null);
    setSelection("");
    setFiles(null);
    api.listPluginSwfs({ installIndex, windowSwfDir: install.windowSwfDir }).then(names => {
      if (current) setFiles(names);
    }, err => {
      if (current) setError(String(err));
    });
    return () => { current = false; };
  }, [api, installIndex, install, latestInstall]);

  async function remove(apply: boolean) {
    setBusy(true);
    setError("");
    try {
      const target = { installIndex, windowSwfDir: install.windowSwfDir };
      const next = await api.deleteSwf({ ...target, name: selection, apply });
      setResult({ name: selection, value: next });
      if (next.ok && next.applied) {
        setFiles(await api.listPluginSwfs(target));
        setSelection("");
      }
    } catch (err) {
      setError(String(err));
      setResult(null);
    } finally {
      setBusy(false);
    }
  }

  const planned = Boolean(selection && result?.name === selection && result.value.ok &&
    !result.value.applied && result.value.changes.length);
  return (
    <section className="card motion-surface">
      <div className="card-head"><h2>删除插件 .swf</h2></div>
      {files?.length ? (
        <select className="text-input" aria-label="已安装的插件" value={selection} disabled={busy}
          onChange={e => { setSelection(e.target.value); setResult(null); }}>
          <option value="">选择已安装的插件…</option>
          {files.map(name => <option key={name} value={name}>{name}</option>)}
        </select>
      ) : files && <div className="empty-hint">此目录没有已安装的 .swf 插件。</div>}
      {error && <div className="error-bar">{error}</div>}
      <div className="btn-row">
        <button className="btn btn-primary" disabled={busy || !selection} onClick={() => void remove(false)}>生成计划</button>
        <button className="btn btn-apply" disabled={busy || !planned} onClick={() => void remove(true)}>应用 / Apply</button>
        {planned && <button className="btn btn-ghost" disabled={busy} onClick={() => setResult(null)}>取消计划</button>}
      </div>
      <OpResultView result={result?.value ?? null} />
    </section>
  );
}
