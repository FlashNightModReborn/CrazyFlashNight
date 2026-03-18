interface ControlPanelProps {
  sourceMode: "worktree" | "git-tag";
  onSourceModeChange: (mode: "worktree" | "git-tag") => void;
  selectedTag: string;
  onSelectedTagChange: (tag: string) => void;
  tags: string[];
  outputDir: string;
  onOutputDirChange: (dir: string) => void;
  onPickDir: () => void;
  buildSfxAfterPack: boolean;
  onBuildSfxChange: (checked: boolean) => void;
  sfxVersion: string;
  onSfxVersionChange: (version: string) => void;
  unityDataDir: string;
  onUnityDataDirChange: (dir: string) => void;
  isRunning: boolean;
  controlSplit: number;
}

export default function ControlPanel({
  sourceMode, onSourceModeChange,
  selectedTag, onSelectedTagChange,
  tags,
  outputDir, onOutputDirChange, onPickDir,
  buildSfxAfterPack, onBuildSfxChange,
  sfxVersion, onSfxVersionChange,
  unityDataDir, onUnityDataDirChange,
  isRunning, controlSplit
}: ControlPanelProps) {
  return (
    <section
      className="section source-section control-pane motion-surface motion-split-pane"
      style={{ flexBasis: `${controlSplit * 100}%`, flexGrow: 0, flexShrink: 0 }}
    >
      <div className="panel-title-row">
        <h2>打包来源与输出</h2>
        <span className="panel-hint">选择要打包哪些文件、输出到哪里</span>
      </div>
      <div className="source-toggle">
        <label title="直接打包你电脑上当前的文件（最常用）">
          <input type="radio" name="source" checked={sourceMode === "worktree"}
            onChange={() => onSourceModeChange("worktree")} disabled={isRunning} />
          工作区
        </label>
        <label title="打包某个已发布版本的文件，需选择对应标签">
          <input type="radio" name="source" checked={sourceMode === "git-tag"}
            onChange={() => onSourceModeChange("git-tag")} disabled={isRunning} />
          Git 标签
        </label>
        {sourceMode === "git-tag" && (
          <select value={selectedTag} onChange={(e) => onSelectedTagChange(e.target.value)} disabled={isRunning}>
            {tags.map((tag) => <option key={tag} value={tag}>{tag}</option>)}
          </select>
        )}
      </div>
      <div className="output-row">
        <label title="打包好的文件会放到这个目录">输出:</label>
        <input type="text" value={outputDir} onChange={(e) => onOutputDirChange(e.target.value)}
          placeholder="./output/{version}" disabled={isRunning}
          title="可用 {version} 占位符，打包时会替换为版本号" />
        <button onClick={onPickDir} disabled={isRunning} className="btn-small">浏览</button>
      </div>
      <div className="sfx-options-row">
        <label className="sfx-label" title="打包完成后额外生成一个双击即可安装的 .exe 文件">
          <input type="checkbox" checked={buildSfxAfterPack} onChange={(e) => onBuildSfxChange(e.target.checked)} disabled={isRunning} />
          打包后自动构建安装包
        </label>
        {buildSfxAfterPack && <>
          <input type="text" value={sfxVersion} onChange={(e) => onSfxVersionChange(e.target.value)}
            placeholder="版本号 (如 2.72)" className="sfx-input" disabled={isRunning}
            title="安装包文件名中的版本号" />
          <input type="text" value={unityDataDir} onChange={(e) => onUnityDataDirChange(e.target.value)}
            placeholder="Unity _Data 目录 (可选)" className="sfx-input sfx-input-wide" disabled={isRunning}
            title="如果项目包含 Unity 资源，指定 _Data 目录路径" />
        </>}
      </div>
    </section>
  );
}
