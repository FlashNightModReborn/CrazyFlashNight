import { useRef, useEffect, useLayoutEffect, useMemo, useState, useCallback } from "react";
import * as d3 from "d3";
import type { FileEntry, ExcludeRequest } from "../../shared/ipc-types.js";
import { buildSunburstData, formatSize, type SunburstNode } from "./tree-utils.js";
import {
  buildScopeBreadcrumbs,
} from "./scope-utils.js";
import {
  resolveTooltipPlacement,
  resolveTreemapResizeState,
  sameTreemapSize,
  sanitizeTreemapSize,
  type TreemapSize
} from "./treemap-utils.js";
import type { MotionLevel } from "./motion-utils.js";

interface Props {
  files: FileEntry[];
  layers: string[];
  onExcluded?: () => void;
  isLayoutResizing?: boolean;
  isLayoutSettling?: boolean;
  motionLevel?: MotionLevel;
  motionDurationMs?: number;
  focusPath?: string | null;
  activeLayer?: string | null;
  canNavigateUp?: boolean;
  onFocusPathChange?: (path: string | null, layer: string | null) => void;
  onNavigate?: (path: string | null, layer: string | null) => void;
  onNavigateUp?: () => void;
  onResetScope?: () => void;
}

interface CtxMenuState {
  x: number;
  y: number;
  path: string;
  isDir: boolean;
  layer?: string | undefined;
}

const LAYER_PALETTE: Record<string, string> = {
  data: "#3498db",
  scripts: "#2ecc71",
  flashswf: "#e67e22",
  sounds: "#9b59b6",
  config: "#1abc9c",
  "root-files": "#e74c3c",
  "root-dirs": "#f39c12"
};

type HNode = d3.HierarchyRectangularNode<SunburstNode>;

export default function TreemapChart({
  files,
  layers,
  onExcluded,
  isLayoutResizing = false,
  isLayoutSettling = false,
  motionLevel = "light",
  motionDurationMs = 140,
  focusPath = null,
  activeLayer = null,
  canNavigateUp = false,
  onFocusPathChange,
  onNavigate,
  onNavigateUp,
  onResetScope
}: Props) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const [tooltip, setTooltip] = useState<{ x: number; y: number; lines: string[] } | null>(null);
  const [tooltipPosition, setTooltipPosition] = useState<{ left: number; top: number } | null>(null);
  const [ctxMenu, setCtxMenu] = useState<CtxMenuState | null>(null);
  const [currentRoot, setCurrentRoot] = useState<HNode | null>(null);
  // 追踪下钻路径：copy() 会重置 depth/parent，所以需要独立维护完整路径前缀
  const [zoomPrefix, setZoomPrefix] = useState("");
  const [size, setSize] = useState<TreemapSize>({ w: 600, h: 300 });
  const sizeRef = useRef<TreemapSize>({ w: 600, h: 300 });
  const pendingSizeRef = useRef<TreemapSize>({ w: 600, h: 300 });
  const isLayoutResizingRef = useRef(false);
  const resizeFrameRef = useRef<number | null>(null);
  const tooltipFrameRef = useRef<number | null>(null);
  const chartMotionTimerRef = useRef<number | null>(null);
  const hasAnimatedOnceRef = useRef(false);
  const [isChartRefreshing, setIsChartRefreshing] = useState(false);

  useEffect(() => {
    sizeRef.current = size;
  }, [size]);

  useEffect(() => {
    isLayoutResizingRef.current = isLayoutResizing ?? false;
  }, [isLayoutResizing]);

  const data = useMemo(() => buildSunburstData(files), [files]);

  const hierarchy = useMemo(() => {
    return d3.hierarchy(data)
      .sum((d) => d.value ?? 0)
      .sort((a, b) => (b.value ?? 0) - (a.value ?? 0));
  }, [data]);

  useEffect(() => {
    if (!focusPath) {
      setCurrentRoot(null);
      setZoomPrefix("");
      return;
    }

    const node = findHierarchyNodeByPath(hierarchy, focusPath);
    if (!node || !node.children) return;

    setCurrentRoot(node as HNode);
    setZoomPrefix(focusPath);
  }, [focusPath, hierarchy]);

  // hierarchy 变化时（数据刷新），尝试恢复下钻位置
  useEffect(() => {
    if (!zoomPrefix) {
      setCurrentRoot(null);
      return;
    }
    // 沿 zoomPrefix 路径在新 hierarchy 中重新定位
    const segments = zoomPrefix.split("/");
    let node: d3.HierarchyNode<SunburstNode> = hierarchy;
    for (const seg of segments) {
      const child = node.children?.find((c) => c.data.name === seg);
      if (!child) {
        // 路径不存在了（被删除的目录等），回退到顶层
        setCurrentRoot(null);
        setZoomPrefix("");
        return;
      }
      node = child;
    }
    setCurrentRoot(node as any);
  }, [hierarchy]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    const commitObservedSize = (width: number, height: number) => {
      const observed = sanitizeTreemapSize(width, height);
      if (!observed) return;

      const nextState = resolveTreemapResizeState({
        currentSize: sizeRef.current,
        pendingSize: pendingSizeRef.current,
        observedSize: observed,
        isLayoutResizing: isLayoutResizingRef.current
      });

      pendingSizeRef.current = nextState.pendingSize;
      if (nextState.shouldCommit) {
        sizeRef.current = nextState.size;
        setSize((prev) => sameTreemapSize(prev, nextState.size) ? prev : nextState.size);
      }
    };

    const ro = new ResizeObserver((entries) => {
      const { width, height } = entries[0]!.contentRect;
      if (resizeFrameRef.current !== null) {
        cancelAnimationFrame(resizeFrameRef.current);
      }
      resizeFrameRef.current = requestAnimationFrame(() => {
        resizeFrameRef.current = null;
        commitObservedSize(width, height);
      });
    });
    ro.observe(el);
    const rect = el.getBoundingClientRect();
    commitObservedSize(rect.width, rect.height);
    return () => {
      ro.disconnect();
      if (resizeFrameRef.current !== null) {
        cancelAnimationFrame(resizeFrameRef.current);
        resizeFrameRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    const nextState = resolveTreemapResizeState({
      currentSize: sizeRef.current,
      pendingSize: pendingSizeRef.current,
      observedSize: null,
      isLayoutResizing: isLayoutResizing ?? false
    });
    pendingSizeRef.current = nextState.pendingSize;
    if (nextState.shouldCommit) {
      sizeRef.current = nextState.size;
      setSize((prev) => sameTreemapSize(prev, nextState.size) ? prev : nextState.size);
    }
  }, [isLayoutResizing]);

  const updateTooltipPlacement = useCallback(() => {
    if (!tooltip || !tooltipRef.current || !wrapperRef.current) {
      setTooltipPosition(null);
      return;
    }

    const wrapperRect = wrapperRef.current.getBoundingClientRect();
    const tooltipRect = tooltipRef.current.getBoundingClientRect();
    setTooltipPosition(resolveTooltipPlacement(
      { x: tooltip.x, y: tooltip.y },
      { width: tooltipRect.width, height: tooltipRect.height },
      { width: wrapperRect.width, height: wrapperRect.height }
    ));
  }, [tooltip]);

  useLayoutEffect(() => {
    updateTooltipPlacement();
  }, [size, tooltip, updateTooltipPlacement]);

  useEffect(() => {
    if (!tooltip || !tooltipRef.current) return;

    const observer = new ResizeObserver(() => {
      if (tooltipFrameRef.current !== null) {
        cancelAnimationFrame(tooltipFrameRef.current);
      }
      tooltipFrameRef.current = requestAnimationFrame(() => {
        tooltipFrameRef.current = null;
        updateTooltipPlacement();
      });
    });

    observer.observe(tooltipRef.current);
    return () => {
      observer.disconnect();
      if (tooltipFrameRef.current !== null) {
        cancelAnimationFrame(tooltipFrameRef.current);
        tooltipFrameRef.current = null;
      }
    };
  }, [tooltip, updateTooltipPlacement]);

  useEffect(() => {
    if (motionDurationMs <= 0) {
      setIsChartRefreshing(false);
      hasAnimatedOnceRef.current = true;
      return;
    }

    if (!hasAnimatedOnceRef.current) {
      hasAnimatedOnceRef.current = true;
      return;
    }

    if (chartMotionTimerRef.current !== null) {
      window.clearTimeout(chartMotionTimerRef.current);
    }

    setIsChartRefreshing(true);
    chartMotionTimerRef.current = window.setTimeout(() => {
      chartMotionTimerRef.current = null;
      setIsChartRefreshing(false);
    }, motionDurationMs);
  }, [currentRoot, hierarchy, motionDurationMs, size, zoomPrefix]);

  useEffect(() => {
    return () => {
      if (chartMotionTimerRef.current !== null) {
        window.clearTimeout(chartMotionTimerRef.current);
        chartMotionTimerRef.current = null;
      }
      if (tooltipFrameRef.current !== null) {
        cancelAnimationFrame(tooltipFrameRef.current);
        tooltipFrameRef.current = null;
      }
    };
  }, []);

  // 右键菜单：点击外部关闭
  useEffect(() => {
    if (!ctxMenu) return;
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setCtxMenu(null);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [ctxMenu]);

  const handleCtxOpen = useCallback(() => {
    if (!ctxMenu) return;
    const api = window.cf7Packer;
    if (api) void api.openFile(ctxMenu.path);
    setCtxMenu(null);
  }, [ctxMenu]);

  const handleCtxReveal = useCallback(() => {
    if (!ctxMenu) return;
    const api = window.cf7Packer;
    if (api) void api.revealFile(ctxMenu.path);
    setCtxMenu(null);
  }, [ctxMenu]);

  const doCtxExclude = useCallback(async (deleteFromDisk: boolean) => {
    if (!ctxMenu) return;
    const api = window.cf7Packer;
    if (!api) return;
    // 删除操作需要二次确认
    if (deleteFromDisk) {
      const confirmed = await api.confirmDelete(ctxMenu.path, ctxMenu.isDir);
      if (!confirmed) { setCtxMenu(null); return; }
    }
    const req: ExcludeRequest = {
      filePath: ctxMenu.path,
      isDir: ctxMenu.isDir,
      layer: ctxMenu.layer,
      deleteFromDisk
    };
    setCtxMenu(null);
    const result = await api.excludeFile(req);
    if (result.success) onExcluded?.();
  }, [ctxMenu, onExcluded]);

  const handleCtxExclude = useCallback(() => { void doCtxExclude(false); }, [doCtxExclude]);
  const handleCtxDeleteExclude = useCallback(() => { void doCtxExclude(true); }, [doCtxExclude]);

  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;

    const root = currentRoot ?? hierarchy;
    const { w, h } = size;
    // 当前下钻前缀，用于拼接 layout copy 节点的完整路径
    const prefix = zoomPrefix;

    /**
     * 从 layout copy 节点构建完整路径。
     * copy() 会重置 depth=0 并断开 parent 链，所以用 prefix 补全祖先路径。
     * localPath: 从 copy root 向下到目标节点（排除 copy root 自身，因为它已包含在 prefix 中）。
     */
    function fullPath(d: d3.HierarchyNode<SunburstNode>): string {
      const parts: string[] = [];
      let node: d3.HierarchyNode<SunburstNode> | null = d;
      // 收集到 copy root 之前的所有节点名（copy root 的 parent 为 null）
      while (node && node.parent) {
        parts.unshift(node.data.name);
        node = node.parent;
      }
      // node 现在是 copy root
      if (node && node.data.name !== "root") {
        parts.unshift(node.data.name);
      }
      const local = parts.join("/");
      // 如果有 prefix 且 local 不以 prefix 开头（多级下钻时），拼接
      if (prefix && !local.startsWith(prefix)) {
        return prefix + "/" + local;
      }
      return local || prefix;
    }

    function getNodeLayer(d: d3.HierarchyNode<SunburstNode>): string | undefined {
      if (d.data.layer) return d.data.layer;
      let leaf: d3.HierarchyNode<SunburstNode> = d;
      while (leaf.children && leaf.children.length > 0) leaf = leaf.children[0]!;
      return leaf.data.layer;
    }

    function openCtxMenu(event: MouseEvent, d: d3.HierarchyNode<SunburstNode>) {
      event.preventDefault();
      event.stopPropagation();
      const wrapperRect = wrapperRef.current?.getBoundingClientRect();
      const x = (wrapperRect?.left ?? 0) + event.offsetX;
      const y = (wrapperRect?.top ?? 0) + event.offsetY;
      setCtxMenu({
        x, y,
        path: fullPath(d),
        isDir: !!d.children,
        layer: getNodeLayer(d)
      });
      setTooltip(null);
    }

    function handleZoomIn(node: d3.HierarchyNode<SunburstNode>) {
      // 先计算该节点的完整路径，再设为下钻前缀
      const nodePath = fullPath(node);
      const nodeLayer = getNodeLayer(node) ?? null;
      setCurrentRoot(node as any);
      setZoomPrefix(nodePath);
      onFocusPathChange?.(nodePath, nodeLayer);
    }

    function handleNodeSelection(node: d3.HierarchyNode<SunburstNode>) {
      onFocusPathChange?.(fullPath(node), getNodeLayer(node) ?? null);
    }

    // treemap 布局
    const treemapLayout = d3.treemap<SunburstNode>()
      .size([w, h])
      .paddingTop(18)
      .paddingRight(2)
      .paddingBottom(2)
      .paddingLeft(2)
      .paddingInner(1)
      .round(true);

    const layoutRoot = root.copy();
    layoutRoot.sum((d) => d.value ?? 0);
    treemapLayout(layoutRoot as any);
    const lRoot = layoutRoot as unknown as HNode;

    const sel = d3.select(svg);
    sel.selectAll("*").remove();
    sel.attr("viewBox", `0 0 ${w} ${h}`);

    function getColor(d: d3.HierarchyNode<SunburstNode>): string {
      let node: d3.HierarchyNode<SunburstNode> | null = d;
      while (node && node.depth > 1) node = node.parent;
      const layerName = node?.data.name ?? "";
      for (const [name, color] of Object.entries(LAYER_PALETTE)) {
        if (layerName === name || layerName.startsWith(name)) return color;
      }
      if (d.data.layer && LAYER_PALETTE[d.data.layer]) return LAYER_PALETTE[d.data.layer]!;
      return "#557";
    }

    const displayNodes = lRoot.children ?? [];
    const defs = sel.append("defs");

    for (const child of displayNodes) {
      const c = child as HNode;
      const gw = c.x1 - c.x0;
      const gh = c.y1 - c.y0;
      if (gw < 2 || gh < 2) continue;

      const clipId = `clip-g-${c.data.name}-${Math.round(c.x0)}-${Math.round(c.y0)}`;
      defs.append("clipPath").attr("id", clipId)
        .append("rect").attr("x", c.x0).attr("y", c.y0).attr("width", gw).attr("height", gh);

      const group = sel.append("g").attr("clip-path", `url(#${clipId})`);
      const baseColor = getColor(c);
      const layerMatch = !activeLayer || getNodeLayer(c) === activeLayer;
      if (!zoomPrefix) {
        group.attr("opacity", layerMatch ? 1 : 0.32);
      }

      group.append("rect")
        .attr("x", c.x0).attr("y", c.y0)
        .attr("width", gw).attr("height", gh)
        .attr("fill", d3.color(baseColor)?.darker(0.5).toString() ?? "#223")
        .attr("stroke", "#1a1a2e")
        .attr("stroke-width", 1)
        .attr("rx", 2)
        .style("cursor", c.children ? "pointer" : "default")
        .on("click", () => {
          if (c.children) {
            handleZoomIn(c);
            return;
          }
          handleNodeSelection(c);
        })
        .on("contextmenu", (event) => openCtxMenu(event, c))
        .on("mouseenter", (event) => {
          const sz = formatSize(c.value ?? 0);
          const total = lRoot.value ?? 1;
          const pct = ((c.value ?? 0) / total * 100).toFixed(1) + "%";
          const cnt = c.children ? `${(c as any).descendants().length - 1} 文件` : "";
          setTooltip({ x: event.offsetX, y: event.offsetY, lines: [fullPath(c), `${sz} (${pct})`, cnt].filter(Boolean) });
        })
        .on("mousemove", (event) => setTooltip((p) => p ? { ...p, x: event.offsetX, y: event.offsetY } : null))
        .on("mouseleave", () => setTooltip(null));

      if (gw > 30 && gh > 16) {
        group.append("text")
          .attr("x", c.x0 + 4).attr("y", c.y0 + 13)
          .attr("fill", "#fff").attr("font-size", "11px").attr("font-weight", "600")
          .text(truncText(c.data.name, gw - 8, 11))
          .style("pointer-events", "none");
      }

      if (c.children) {
        for (const leaf of c.children) {
          const l = leaf as HNode;
          const lw = l.x1 - l.x0;
          const lh = l.y1 - l.y0;
          if (lw < 1 || lh < 1) continue;

          const leafClipId = `clip-l-${Math.round(l.x0)}-${Math.round(l.y0)}`;
          defs.append("clipPath").attr("id", leafClipId)
            .append("rect").attr("x", l.x0).attr("y", l.y0).attr("width", lw).attr("height", lh);

          const leafGroup = group.append("g").attr("clip-path", `url(#${leafClipId})`);

          leafGroup.append("rect")
            .attr("x", l.x0).attr("y", l.y0)
            .attr("width", lw).attr("height", lh)
            .attr("fill", () => {
              const base = d3.color(baseColor);
              return base ? base.brighter(0.3).toString() : "#557";
            })
            .attr("stroke", d3.color(baseColor)?.darker(0.3).toString() ?? "#223")
            .attr("stroke-width", 0.5)
            .attr("rx", 1)
            .style("cursor", leaf.children ? "pointer" : "default")
            .on("click", () => {
              if (leaf.children) {
                handleZoomIn(leaf);
                return;
              }
              handleNodeSelection(leaf);
            })
            .on("contextmenu", (event) => openCtxMenu(event, leaf))
            .on("mouseenter", (event) => {
              const sz = formatSize(l.value ?? 0);
              const total = lRoot.value ?? 1;
              const pct = ((l.value ?? 0) / total * 100).toFixed(1) + "%";
              setTooltip({ x: event.offsetX, y: event.offsetY, lines: [fullPath(l), sz + " (" + pct + ")"] });
            })
            .on("mousemove", (event) => setTooltip((p) => p ? { ...p, x: event.offsetX, y: event.offsetY } : null))
            .on("mouseleave", () => setTooltip(null));

          if (lw > 40 && lh > 14) {
            leafGroup.append("text")
              .attr("x", l.x0 + 3).attr("y", l.y0 + 11)
              .attr("fill", "#e0e0e0").attr("font-size", "9px")
              .text(truncText(l.data.name, lw - 6, 9))
              .style("pointer-events", "none");
          }
          if (lw > 40 && lh > 26) {
            leafGroup.append("text")
              .attr("x", l.x0 + 3).attr("y", l.y0 + 22)
              .attr("fill", "#999").attr("font-size", "8px")
              .text(formatSize(l.value ?? 0))
              .style("pointer-events", "none");
          }
        }
      }
    }

  }, [activeLayer, currentRoot, hierarchy, onFocusPathChange, size, zoomPrefix]);

  const root = currentRoot ?? hierarchy;
  const breadcrumbs = useMemo(() => buildScopeBreadcrumbs(focusPath, activeLayer), [activeLayer, focusPath]);
  const treemapWrapperClassName = [
    "treemap-svg-wrapper",
    `treemap-motion-${motionLevel}`,
    isLayoutResizing ? "treemap-state-resizing" : "",
    isLayoutSettling ? "treemap-state-settling" : "",
    isChartRefreshing ? "treemap-state-refreshing" : ""
  ].filter(Boolean).join(" ");

  return (
    <div className="treemap-container">
      <div className="treemap-toolbar">
        <div className="treemap-toolbar-nav">
          <div className="scope-actions treemap-scope-actions">
            <button type="button" className="btn-small" onClick={onNavigateUp} disabled={!canNavigateUp}>上一级</button>
            <button
              type="button"
              className="btn-small"
              onClick={() => {
                setCurrentRoot(null);
                setZoomPrefix("");
                if (onResetScope) {
                  onResetScope();
                } else {
                  onFocusPathChange?.(null, null);
                }
              }}
              disabled={!canNavigateUp}
            >
              返回顶层
            </button>
          </div>
          <div className="scope-breadcrumbs treemap-breadcrumbs" aria-label="当前浏览范围">
            {breadcrumbs.map((crumb, index) => (
              <div key={`${crumb.label}-${crumb.path ?? "root"}-${index}`} className="scope-crumb-group">
                {index > 0 && <span className="scope-separator">/</span>}
                <button
                  type="button"
                  className={`scope-crumb ${crumb.active ? "active" : ""}`}
                  onClick={() => {
                    if (onNavigate) {
                      onNavigate(crumb.path, crumb.layer);
                    } else {
                      onFocusPathChange?.(crumb.path, crumb.layer);
                    }
                    if (!crumb.path) {
                      setCurrentRoot(null);
                      setZoomPrefix("");
                    }
                  }}
                  disabled={crumb.active}
                  title={crumb.label}
                >
                  {crumb.label}
                </button>
              </div>
            ))}
          </div>
        </div>
        <div className="sunburst-legend">
          {layers.map((l) => (
            <span key={l} className="sunburst-legend-item">
              <span className="sunburst-legend-dot" style={{ background: LAYER_PALETTE[l] ?? "#557" }} />
              {l}
            </span>
          ))}
        </div>
        <span className="treemap-total">{formatSize(root.value ?? 0)}</span>
      </div>
      <div className={treemapWrapperClassName} ref={wrapperRef}>
        <svg ref={svgRef} className="treemap-svg" preserveAspectRatio="none" />
        {tooltip && !ctxMenu && (
          <div
            ref={tooltipRef}
            className="sunburst-tooltip"
            style={{
              left: tooltipPosition?.left ?? tooltip.x + 14,
              top: tooltipPosition?.top ?? tooltip.y - 14
            }}
          >
            {tooltip.lines.map((line, i) => (
              <div key={i} className={i === 0 ? "sunburst-tooltip-path" : ""}>{line}</div>
            ))}
          </div>
        )}
      </div>

      {ctxMenu && (
        <div ref={menuRef} className="ctx-menu" style={{ left: ctxMenu.x, top: ctxMenu.y, position: "fixed" }}>
          <div className="ctx-menu-item" onClick={handleCtxOpen}>
            {ctxMenu.isDir ? "📂 打开文件夹" : "📄 打开文件"}
          </div>
          <div className="ctx-menu-item" onClick={handleCtxReveal}>
            📁 在资源管理器中显示
          </div>
          <div className="ctx-menu-divider" />
          <div className="ctx-menu-item" onClick={handleCtxExclude}>
            🚫 {ctxMenu.isDir ? "排除此文件夹" : "排除此文件"}
          </div>
          <div className="ctx-menu-item ctx-menu-danger" onClick={handleCtxDeleteExclude}>
            🗑️ 删除并排除
          </div>
          <div className="ctx-menu-divider" />
          <div className="ctx-menu-item ctx-menu-path">{ctxMenu.path}</div>
        </div>
      )}
    </div>
  );
}

function truncText(text: string, maxWidth: number, fontSize: number): string {
  const charWidth = fontSize * 0.6;
  const maxChars = Math.floor(maxWidth / charWidth);
  if (text.length <= maxChars) return text;
  return text.slice(0, Math.max(1, maxChars - 1)) + "…";
}

function findHierarchyNodeByPath(
  hierarchy: d3.HierarchyNode<SunburstNode>,
  path: string
): d3.HierarchyNode<SunburstNode> | null {
  if (!path) return hierarchy;

  let node: d3.HierarchyNode<SunburstNode> = hierarchy;
  for (const segment of path.split("/")) {
    const child = node.children?.find((candidate) => candidate.data.name === segment);
    if (!child) return null;
    node = child;
  }
  return node;
}
