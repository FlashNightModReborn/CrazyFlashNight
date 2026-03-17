import { useRef, useEffect, useMemo, useState } from "react";
import * as d3 from "d3";
import type { FileEntry } from "../../shared/ipc-types.js";
import { buildSunburstData, formatSize, type SunburstNode } from "./tree-utils.js";

interface Props {
  files: FileEntry[];
  layers: string[];
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

export default function TreemapChart({ files, layers }: Props) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const [tooltip, setTooltip] = useState<{ x: number; y: number; lines: string[] } | null>(null);
  const [currentRoot, setCurrentRoot] = useState<HNode | null>(null);
  const [size, setSize] = useState({ w: 600, h: 300 });

  const data = useMemo(() => buildSunburstData(files), [files]);

  const hierarchy = useMemo(() => {
    return d3.hierarchy(data)
      .sum((d) => d.value ?? 0)
      .sort((a, b) => (b.value ?? 0) - (a.value ?? 0));
  }, [data]);

  useEffect(() => { setCurrentRoot(null); }, [hierarchy]);

  useEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const { width, height } = entries[0]!.contentRect;
      if (width > 0 && height > 0) setSize({ w: width, h: height });
    });
    ro.observe(el);
    const rect = el.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0) setSize({ w: rect.width, h: rect.height });
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;

    const root = currentRoot ?? hierarchy;
    const { w, h } = size;

    // 重新计算 treemap 布局
    const treemapLayout = d3.treemap<SunburstNode>()
      .size([w, h])
      .paddingTop(18)
      .paddingRight(2)
      .paddingBottom(2)
      .paddingLeft(2)
      .paddingInner(1)
      .round(true);

    // 需要用 copy 防止修改原始层级
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

    // 只渲染 depth 1 和 2（不递归太深）
    const displayNodes = lRoot.children ?? [];

    for (const child of displayNodes) {
      const c = child as HNode;
      const gw = c.x1 - c.x0;
      const gh = c.y1 - c.y0;
      if (gw < 2 || gh < 2) continue;

      const group = sel.append("g");
      const baseColor = getColor(c);

      // 背景矩形
      group.append("rect")
        .attr("x", c.x0).attr("y", c.y0)
        .attr("width", gw).attr("height", gh)
        .attr("fill", d3.color(baseColor)?.darker(0.5).toString() ?? "#223")
        .attr("stroke", "#1a1a2e")
        .attr("stroke-width", 1)
        .attr("rx", 2)
        .style("cursor", c.children ? "pointer" : "default")
        .on("click", () => { if (c.children) setCurrentRoot(c as any); })
        .on("mouseenter", (event) => {
          const sz = formatSize(c.value ?? 0);
          const total = lRoot.value ?? 1;
          const pct = ((c.value ?? 0) / total * 100).toFixed(1) + "%";
          const cnt = c.children ? `${(c as any).descendants().length - 1} 文件` : "";
          setTooltip({ x: event.offsetX, y: event.offsetY, lines: [getPath(c), `${sz} (${pct})`, cnt].filter(Boolean) });
        })
        .on("mousemove", (event) => setTooltip((p) => p ? { ...p, x: event.offsetX, y: event.offsetY } : null))
        .on("mouseleave", () => setTooltip(null));

      // 目录名标签
      if (gw > 30 && gh > 16) {
        group.append("text")
          .attr("x", c.x0 + 4).attr("y", c.y0 + 13)
          .attr("fill", "#fff").attr("font-size", "11px").attr("font-weight", "600")
          .text(truncText(c.data.name, gw - 8, 11))
          .style("pointer-events", "none");
      }

      // 子矩形
      if (c.children) {
        for (const leaf of c.children) {
          const l = leaf as HNode;
          const lw = l.x1 - l.x0;
          const lh = l.y1 - l.y0;
          if (lw < 1 || lh < 1) continue;

          group.append("rect")
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
            .on("click", () => { if (leaf.children) setCurrentRoot(leaf as any); })
            .on("mouseenter", (event) => {
              const sz = formatSize(l.value ?? 0);
              const total = lRoot.value ?? 1;
              const pct = ((l.value ?? 0) / total * 100).toFixed(1) + "%";
              setTooltip({ x: event.offsetX, y: event.offsetY, lines: [getPath(l), sz + " (" + pct + ")"] });
            })
            .on("mousemove", (event) => setTooltip((p) => p ? { ...p, x: event.offsetX, y: event.offsetY } : null))
            .on("mouseleave", () => setTooltip(null));

          // 子标签
          if (lw > 40 && lh > 14) {
            group.append("text")
              .attr("x", l.x0 + 3).attr("y", l.y0 + 11)
              .attr("fill", "#e0e0e0").attr("font-size", "9px")
              .text(truncText(l.data.name, lw - 6, 9))
              .style("pointer-events", "none");
          }
          if (lw > 40 && lh > 26) {
            group.append("text")
              .attr("x", l.x0 + 3).attr("y", l.y0 + 22)
              .attr("fill", "#999").attr("font-size", "8px")
              .text(formatSize(l.value ?? 0))
              .style("pointer-events", "none");
          }
        }
      }
    }

  }, [currentRoot, hierarchy, size]);

  const root = currentRoot ?? hierarchy;
  const isZoomed = currentRoot !== null;

  return (
    <div className="treemap-container">
      <div className="treemap-toolbar">
        {isZoomed && (
          <button className="btn-small" onClick={() => {
            const parent = currentRoot?.parent;
            setCurrentRoot(parent === hierarchy ? null : (parent as any) ?? null);
          }}>← 返回上层</button>
        )}
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
      <div className="treemap-svg-wrapper" ref={wrapperRef}>
        <svg ref={svgRef} className="treemap-svg" preserveAspectRatio="none" />
        {tooltip && (
          <div className="sunburst-tooltip" style={{ left: tooltip.x + 14, top: tooltip.y - 14 }}>
            {tooltip.lines.map((line, i) => (
              <div key={i} className={i === 0 ? "sunburst-tooltip-path" : ""}>{line}</div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function getPath(d: d3.HierarchyNode<SunburstNode>): string {
  const parts: string[] = [];
  let node: d3.HierarchyNode<SunburstNode> | null = d;
  while (node && node.depth > 0) { parts.unshift(node.data.name); node = node.parent; }
  return parts.join("/");
}

function truncText(text: string, maxWidth: number, fontSize: number): string {
  const charWidth = fontSize * 0.6;
  const maxChars = Math.floor(maxWidth / charWidth);
  if (text.length <= maxChars) return text;
  return text.slice(0, Math.max(1, maxChars - 1)) + "…";
}
