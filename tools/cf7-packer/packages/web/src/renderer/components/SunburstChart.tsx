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

export default function SunburstChart({ files, layers }: Props) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const [tooltip, setTooltip] = useState<{ x: number; y: number; lines: string[] } | null>(null);
  const [currentRoot, setCurrentRoot] = useState<HNode | null>(null);
  const [hoveredNode, setHoveredNode] = useState<HNode | null>(null);
  const [size, setSize] = useState({ w: 600, h: 500 });

  const data = useMemo(() => buildSunburstData(files), [files]);

  const hierarchy = useMemo(() => {
    const root = d3.hierarchy(data)
      .sum((d) => d.value ?? 0)
      .sort((a, b) => (b.value ?? 0) - (a.value ?? 0));
    return d3.partition<SunburstNode>().size([2 * Math.PI, 1])(root);
  }, [data]);

  useEffect(() => { setCurrentRoot(hierarchy); }, [hierarchy]);

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
    if (!svg || !currentRoot) return;

    const { w, h } = size;
    const radius = Math.min(w, h) / 2 * 0.72; // 留出标注空间

    const sel = d3.select(svg);
    sel.selectAll("*").remove();
    sel.attr("viewBox", `${-w / 2} ${-h / 2} ${w} ${h}`);

    const g = sel.append("g");

    const x0 = currentRoot.x0;
    const xSpan = currentRoot.x1 - currentRoot.x0 || 1;
    const y0 = currentRoot.y0;
    const ySpan = 1 - y0 || 1;

    function mapAngle(d: HNode): [number, number] {
      return [
        ((d.x0 - x0) / xSpan) * 2 * Math.PI,
        ((d.x1 - x0) / xSpan) * 2 * Math.PI
      ];
    }
    function mapRadius(d: HNode): [number, number] {
      const inner = Math.sqrt(Math.max(0, (d.y0 - y0) / ySpan));
      const outer = Math.sqrt(Math.max(0, (d.y1 - y0) / ySpan));
      return [inner * radius, outer * radius - 1];
    }

    const arc = d3.arc<HNode>()
      .startAngle((d) => mapAngle(d)[0])
      .endAngle((d) => mapAngle(d)[1])
      .padAngle(0.003)
      .padRadius(radius / 3)
      .innerRadius((d) => mapRadius(d)[0])
      .outerRadius((d) => mapRadius(d)[1]);

    function getColor(d: HNode): string {
      let node: HNode | null = d;
      while (node && node.depth > 1) node = node.parent;
      const layerName = node?.data.name ?? "";
      for (const [name, color] of Object.entries(LAYER_PALETTE)) {
        if (layerName === name || layerName.startsWith(name)) return color;
      }
      if (d.data.layer && LAYER_PALETTE[d.data.layer]) return LAYER_PALETTE[d.data.layer]!;
      return "#557";
    }

    const nodes = currentRoot.descendants().filter((d) =>
      d !== currentRoot && (mapAngle(d)[1] - mapAngle(d)[0]) > 0.002
    );

    // 绘制弧段
    const paths = g.selectAll<SVGPathElement, HNode>("path.arc")
      .data(nodes, (d) => d.data.name + d.depth)
      .join("path")
      .attr("class", "arc")
      .attr("d", arc as any)
      .attr("fill", (d) => {
        const base = d3.color(getColor(d));
        if (!base) return "#557";
        const depthFromRoot = d.depth - currentRoot.depth;
        return base.brighter(Math.min(depthFromRoot * 0.1, 0.5)).toString();
      })
      .attr("stroke", "#1a1a2e")
      .attr("stroke-width", 0.5)
      .style("cursor", (d) => d.children ? "pointer" : "default");

    // hover 高亮 + 祖先链
    paths
      .on("mouseenter", function (event, d) {
        // 高亮祖先链
        const ancestors = new Set<HNode>();
        let a: HNode | null = d;
        while (a && a !== currentRoot) { ancestors.add(a); a = a.parent; }

        paths.attr("opacity", (n) => ancestors.has(n) || n === d ? 1 : 0.3);

        setHoveredNode(d);
        const sz = formatSize(d.value ?? 0);
        const pct = currentRoot.value ? ((d.value ?? 0) / currentRoot.value * 100).toFixed(1) + "%" : "";
        const cnt = d.children ? `${d.descendants().length - 1} 文件` : "";
        setTooltip({
          x: event.offsetX,
          y: event.offsetY,
          lines: [getPath(d), `${sz} (${pct})`, cnt].filter(Boolean)
        });
      })
      .on("mousemove", (event) => {
        setTooltip((prev) => prev ? { ...prev, x: event.offsetX, y: event.offsetY } : null);
      })
      .on("mouseleave", function () {
        paths.attr("opacity", 1);
        setHoveredNode(null);
        setTooltip(null);
      })
      .on("click", (_event, d) => { if (d.children) setCurrentRoot(d); });

    // ── 外部标注线（限数 + 碰撞检测 + 可用高度约束）──
    const labelGroup = g.append("g").attr("class", "labels");
    const topChildren = currentRoot.children ?? [];
    const labelRadius = radius * 1.06;
    const elbowRadius = radius * 1.18;
    const LABEL_H = 28;
    const MAX_LABELS_PER_SIDE = Math.max(3, Math.floor(h / 2 / LABEL_H) - 1);

    // 1) 按大小排序，取 top N，其余合并为"其他"
    type LabelEntry = { name: string; value: number; midAngle: number; color: string; };
    const candidates: LabelEntry[] = [];
    for (const child of topChildren) {
      const [a0, a1] = mapAngle(child);
      if (a1 - a0 < 0.02) continue;
      candidates.push({
        name: child.data.name,
        value: child.value ?? 0,
        midAngle: (a0 + a1) / 2,
        color: getColor(child)
      });
    }
    candidates.sort((a, b) => b.value - a.value);

    const maxTotal = MAX_LABELS_PER_SIDE * 2;
    let displayLabels: LabelEntry[];
    if (candidates.length <= maxTotal) {
      displayLabels = candidates;
    } else {
      const kept = candidates.slice(0, maxTotal - 1);
      const rest = candidates.slice(maxTotal - 1);
      const otherValue = rest.reduce((s, e) => s + e.value, 0);
      // "其他"标注放在剩余项的角度中心
      const otherAngles = rest.map((e) => e.midAngle);
      const otherMid = otherAngles.reduce((s, a) => s + a, 0) / otherAngles.length;
      kept.push({ name: `其他 (${rest.length}项)`, value: otherValue, midAngle: otherMid, color: "#556" });
      displayLabels = kept;
    }

    // 2) 计算位置 + 左右分组
    type LabelPos = LabelEntry & { naturalY: number; isRight: boolean; arcX: number; arcY: number; };
    const positioned: LabelPos[] = displayLabels.map((e) => {
      const ax = Math.sin(e.midAngle) * labelRadius;
      const ay = -Math.cos(e.midAngle) * labelRadius;
      const ey = -Math.cos(e.midAngle) * elbowRadius;
      return { ...e, naturalY: ey, isRight: ax >= 0, arcX: ax, arcY: ay };
    });

    // 3) 碰撞检测：约束在可用高度内
    const halfH = h / 2 - 20;
    function resolveCollisions(group: LabelPos[]): Map<string, number> {
      group.sort((a, b) => a.naturalY - b.naturalY);
      const resolved = new Map<string, number>();
      // 先往下推
      let lastY = -halfH;
      for (const item of group) {
        let y = item.naturalY;
        if (y < lastY + LABEL_H) y = lastY + LABEL_H;
        resolved.set(item.name, y);
        lastY = y;
      }
      // 如果底部溢出，整体上移
      const overflow = lastY - halfH;
      if (overflow > 0) {
        for (const [k, v] of resolved) resolved.set(k, v - overflow);
      }
      return resolved;
    }

    const leftGroup = positioned.filter((l) => !l.isRight);
    const rightGroup = positioned.filter((l) => l.isRight);
    const leftY = resolveCollisions(leftGroup);
    const rightY = resolveCollisions(rightGroup);

    // 4) 绘制
    const edgeX = w / 2 - 8; // 文字不超出 viewBox
    for (const item of positioned) {
      const resolvedY = (item.isRight ? rightY : leftY).get(item.name) ?? item.naturalY;
      const elbowX = Math.sin(item.midAngle) * elbowRadius;
      const tailX = item.isRight
        ? Math.min(elbowX + 35, edgeX - 100)
        : Math.max(elbowX - 35, -edgeX + 100);

      labelGroup.append("path")
        .attr("d", `M${item.arcX},${item.arcY} L${elbowX},${resolvedY} L${tailX},${resolvedY}`)
        .attr("fill", "none")
        .attr("stroke", item.color)
        .attr("stroke-width", 1)
        .attr("opacity", 0.5);

      const textX = tailX + (item.isRight ? 5 : -5);
      const anchor = item.isRight ? "start" : "end";
      const totalVal = currentRoot.value ?? 1;
      const pct = (item.value / totalVal * 100).toFixed(0) + "%";
      const sz = formatSize(item.value);

      labelGroup.append("text")
        .attr("x", textX).attr("y", resolvedY).attr("dy", "-0.2em")
        .attr("text-anchor", anchor).attr("fill", "#e0e0e0")
        .attr("font-size", "11px").attr("font-weight", "500")
        .text(item.name).style("pointer-events", "none");

      labelGroup.append("text")
        .attr("x", textX).attr("y", resolvedY).attr("dy", "1em")
        .attr("text-anchor", anchor).attr("fill", "#888")
        .attr("font-size", "10px")
        .text(`${sz} · ${pct}`).style("pointer-events", "none");
    }

    // ── 中心圆 ──
    const centerR = radius * 0.16;
    g.append("circle")
      .attr("r", centerR)
      .attr("fill", "#1a1a2e")
      .attr("stroke", "#334")
      .style("cursor", currentRoot.parent ? "pointer" : "default")
      .on("click", () => { if (currentRoot.parent) setCurrentRoot(currentRoot.parent); });

    const centerName = currentRoot.data.name === "root" ? "全部" : currentRoot.data.name;
    g.append("text")
      .attr("text-anchor", "middle").attr("dy", "-0.3em")
      .attr("fill", "#e0e0e0").attr("font-size", "14px").attr("font-weight", "600")
      .text(centerName).style("pointer-events", "none");
    g.append("text")
      .attr("text-anchor", "middle").attr("dy", "1.1em")
      .attr("fill", "#888").attr("font-size", "12px")
      .text(formatSize(currentRoot.value ?? 0)).style("pointer-events", "none");
    if (currentRoot.parent) {
      g.append("text")
        .attr("text-anchor", "middle").attr("dy", "2.4em")
        .attr("fill", "#556").attr("font-size", "10px")
        .text("点击返回上层").style("pointer-events", "none");
    }

  }, [currentRoot, size]);

  return (
    <div className="sunburst-container">
      <div className="sunburst-toolbar">
        {currentRoot?.parent && (
          <button className="btn-small" onClick={() => setCurrentRoot(currentRoot.parent!)}>
            ← 返回上层
          </button>
        )}
        <div className="sunburst-legend">
          {layers.map((l) => (
            <span key={l} className="sunburst-legend-item">
              <span className="sunburst-legend-dot" style={{ background: LAYER_PALETTE[l] ?? "#557" }} />
              {l}
            </span>
          ))}
        </div>
      </div>
      <div className="sunburst-svg-wrapper" ref={wrapperRef}>
        <svg ref={svgRef} className="sunburst-svg" preserveAspectRatio="xMidYMid meet" />
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

function getPath(d: HNode): string {
  const parts: string[] = [];
  let node: HNode | null = d;
  while (node && node.depth > 0) {
    parts.unshift(node.data.name);
    node = node.parent;
  }
  return parts.join("/");
}
