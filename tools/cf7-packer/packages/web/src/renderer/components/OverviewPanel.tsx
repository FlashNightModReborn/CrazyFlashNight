import type { FileEntry, LayerSummary } from "../../shared/ipc-types.js";
import type { MotionLevel } from "./motion-utils.js";
import TreemapChart from "./TreemapChart.js";
import ResizeHandle from "./ResizeHandle.js";
import { formatSize } from "../utils/helpers.js";

interface OverviewPanelProps {
  layers: LayerSummary[];
  previewFiles: FileEntry[];
  hasPreview: boolean;
  expandedLayer: string | null;
  overviewSplit: number;
  layerSplit: number;
  selectedScopeLayer: string | null;
  selectedScopePath: string | null;
  hasActiveScope: boolean;
  isLayoutResizing: boolean;
  isLayoutSettling: boolean;
  motionLevel: MotionLevel;
  motionSettleMs: number;
  activeResizeHandle: string | null;
  overviewRef: React.RefObject<HTMLDivElement | null>;
  loadPreview: () => void;
  onLayerScopeChange: (layer: string | null) => void;
  onTreemapScopeChange: (path: string | null, layer: string | null) => void;
  onScopeNavigate: (path: string | null, layer: string | null) => void;
  onNavigateUp: () => void;
  onResetScope: () => void;
  onBeginResize: (clientX: number, clientY: number, options: {
    handleId: string;
    container: React.RefObject<HTMLElement | null>;
    axis: "x" | "y";
    min: number;
    max: number;
    setValue: (value: number) => void;
  }) => void;
  setLayerSplit: (value: number) => void;
}

export default function OverviewPanel({
  layers, previewFiles, hasPreview, expandedLayer,
  overviewSplit, layerSplit,
  selectedScopeLayer, selectedScopePath, hasActiveScope,
  isLayoutResizing, isLayoutSettling, motionLevel, motionSettleMs,
  activeResizeHandle, overviewRef,
  loadPreview, onLayerScopeChange, onTreemapScopeChange,
  onScopeNavigate, onNavigateUp, onResetScope,
  onBeginResize, setLayerSplit
}: OverviewPanelProps) {
  const layerNames = layers.map((l) => l.name);

  return (
    <div
      className="layer-sunburst-split motion-split-pane"
      ref={overviewRef}
      style={{ flexBasis: `${overviewSplit * 100}%`, flexGrow: 0, flexShrink: 0 }}
    >
      <section
        className="section layer-section motion-surface motion-split-pane"
        style={{ flexBasis: `${layerSplit * 100}%`, flexGrow: 0, flexShrink: 0 }}
      >
        <h2>层级统计 {hasPreview && <span className="layer-hint">（点击行可筛选文件树和图表）</span>}</h2>
        <div className="layer-table-wrapper">
          <table className="layer-table">
            <thead><tr>
              <th title="配置中定义的文件分组">层级</th>
              <th title="该层包含的文件数量">文件数</th>
              <th title="被排除规则过滤掉的文件数量">排除</th>
              <th title="所有文件大小的总和（预估值）">估算大小</th>
            </tr></thead>
            <tbody>
              {layers.map((l) => (
                <tr key={l.name}
                  className={`${hasPreview ? "layer-clickable" : ""} ${expandedLayer === l.name ? "layer-active" : ""}`}
                  onClick={() => {
                    if (!hasPreview) return;
                    onLayerScopeChange(expandedLayer === l.name ? null : l.name);
                  }}>
                  <td>{l.name}</td>
                  <td className="num">{l.includedCount}</td>
                  <td className="num excluded">{l.excludedCount > 0 ? l.excludedCount : ""}</td>
                  <td className="num">{typeof l.estimatedSize === "number" ? formatSize(l.estimatedSize) : ""}</td>
                </tr>
              ))}
              <tr className={`total-row ${hasPreview ? "layer-clickable" : ""} ${expandedLayer === null && hasPreview ? "layer-active" : ""}`}
                onClick={() => { if (hasPreview) onLayerScopeChange(null); }}>
                <td>合计</td>
                <td className="num">{layers.reduce((s, l) => s + l.includedCount, 0)}</td>
                <td className="num excluded">{layers.reduce((s, l) => s + l.excludedCount, 0)}</td>
                <td className="num">{formatSize(layers.reduce((s, l) => s + (l.estimatedSize ?? 0), 0))}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      {hasPreview && (
        <>
          <ResizeHandle
            orientation="vertical"
            title="拖动调整层级统计与图表宽度"
            isActive={activeResizeHandle === "layer"}
            onStartResize={(clientX, clientY) => onBeginResize(clientX, clientY, {
              handleId: "layer",
              container: overviewRef,
              axis: "x",
              min: 0.18,
              max: 0.42,
              setValue: setLayerSplit
            })}
          />
          <section className="section treemap-inline-section motion-surface">
            <TreemapChart
              files={previewFiles}
              layers={layerNames}
              onExcluded={loadPreview}
              isLayoutResizing={isLayoutResizing}
              isLayoutSettling={isLayoutSettling}
              motionLevel={motionLevel}
              motionDurationMs={motionSettleMs}
              focusPath={selectedScopePath}
              activeLayer={selectedScopeLayer}
              canNavigateUp={hasActiveScope}
              onFocusPathChange={onTreemapScopeChange}
              onNavigate={onScopeNavigate}
              onNavigateUp={onNavigateUp}
              onResetScope={onResetScope}
            />
          </section>
        </>
      )}
    </div>
  );
}
