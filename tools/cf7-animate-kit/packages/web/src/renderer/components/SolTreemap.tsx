import { useRef, useEffect, useLayoutEffect, useMemo, useState, useCallback } from "react";
import * as d3 from "d3";
import type { SolTreeNode } from "../../shared/ipc-types.js";
import {
  buildSolHierarchy, FAMILY_PALETTE, type SolHierNode, type BadgeFamily
} from "./sol-tree-utils.js";
import type { MotionLevel } from "./motion-utils.js";

interface Props {
  tree: SolTreeNode[];
  /** Highlighted path (kept in sync with the selected leaf in the tree). */
  focusPath?: string | null;
  /** Fired when a tile is clicked — lets the parent scroll/expand the tree. */
  onPick?: (path: string) => void;
  motionLevel?: MotionLevel;
  motionDurationMs?: number;
}

interface Size { w: number; h: number; }
type HNode = d3.HierarchyRectangularNode<SolHierNode>;

const FAMILY_ORDER: BadgeFamily[] = [
  "object", "array", "number", "string", "boolean", "date", "xml", "null", "other"
];
const FAMILY_LABEL: Record<BadgeFamily, string> = {
  object: "对象", array: "数组", number: "数值", string: "字符串",
  boolean: "布尔", date: "日期", xml: "XML", null: "空值", other: "其他"
};

function sameSize(a: Size, b: Size): boolean {
  return Math.abs(a.w - b.w) < 0.5 && Math.abs(a.h - b.h) < 0.5;
}

function truncText(text: string, maxWidth: number, fontSize: number): string {
  const charWidth = fontSize * 0.62;
  const maxChars = Math.floor(maxWidth / charWidth);
  if (text.length <= maxChars) return text;
  return text.slice(0, Math.max(1, maxChars - 1)) + "…";
}

/**
 * Read-only D3 treemap of the SOL body, every leaf weighted equally (value=1) so
 * tile area reflects how many editable values live under each subtree. It
 * complements the tree view rather than replacing it: clicking a tile reports
 * the path back up so the parent can reveal it.
 */
export default function SolTreemap({
  tree, focusPath = null, onPick, motionLevel = "light", motionDurationMs = 140
}: Props) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);

  const [tooltip, setTooltip] = useState<{ x: number; y: number; lines: string[] } | null>(null);
  const [tooltipPos, setTooltipPos] = useState<{ left: number; top: number } | null>(null);
  const [size, setSize] = useState<Size>({ w: 600, h: 320 });

  const sizeRef = useRef<Size>({ w: 600, h: 320 });
  const resizeFrameRef = useRef<number | null>(null);
  const motionTimerRef = useRef<number | null>(null);
  const hasAnimatedRef = useRef(false);
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => { sizeRef.current = size; }, [size]);

  const data = useMemo(() => buildSolHierarchy(tree), [tree]);

  const hierarchy = useMemo(() => {
    return d3.hierarchy(data)
      .sum((d) => d.value ?? 0)
      .sort((a, b) => (b.value ?? 0) - (a.value ?? 0));
  }, [data]);

  const families = useMemo(() => {
    const seen = new Set<BadgeFamily>();
    const walk = (n: SolHierNode) => {
      if (!n.children || n.children.length === 0) seen.add(n.family);
      else n.children.forEach(walk);
    };
    walk(data);
    return FAMILY_ORDER.filter((f) => seen.has(f));
  }, [data]);

  // ResizeObserver-driven sizing (rAF-coalesced).
  useEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    const commit = (width: number, height: number) => {
      if (!(width > 0 && height > 0)) return;
      const next = { w: width, h: height };
      if (sameSize(sizeRef.current, next)) return;
      sizeRef.current = next;
      setSize((prev) => (sameSize(prev, next) ? prev : next));
    };

    const ro = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (!entry) return;
      const { width, height } = entry.contentRect;
      if (resizeFrameRef.current !== null) cancelAnimationFrame(resizeFrameRef.current);
      resizeFrameRef.current = requestAnimationFrame(() => {
        resizeFrameRef.current = null;
        commit(width, height);
      });
    });
    ro.observe(el);
    const rect = el.getBoundingClientRect();
    commit(rect.width, rect.height);
    return () => {
      ro.disconnect();
      if (resizeFrameRef.current !== null) {
        cancelAnimationFrame(resizeFrameRef.current);
        resizeFrameRef.current = null;
      }
    };
  }, []);

  const updateTooltipPlacement = useCallback(() => {
    if (!tooltip || !tooltipRef.current || !wrapperRef.current) {
      setTooltipPos(null);
      return;
    }
    const wrapperRect = wrapperRef.current.getBoundingClientRect();
    const tipRect = tooltipRef.current.getBoundingClientRect();
    const margin = 8;
    const maxLeft = Math.max(margin, wrapperRect.width - tipRect.width - margin);
    const maxTop = Math.max(margin, wrapperRect.height - tipRect.height - margin);
    setTooltipPos({
      left: Math.min(maxLeft, Math.max(margin, tooltip.x + 14)),
      top: Math.min(maxTop, Math.max(margin, tooltip.y - 14))
    });
  }, [tooltip]);

  useLayoutEffect(() => { updateTooltipPlacement(); }, [size, tooltip, updateTooltipPlacement]);

  // Brief "refreshing" pulse on data/size change (skips the very first paint).
  useEffect(() => {
    if (motionDurationMs <= 0) {
      setIsRefreshing(false);
      hasAnimatedRef.current = true;
      return;
    }
    if (!hasAnimatedRef.current) {
      hasAnimatedRef.current = true;
      return;
    }
    if (motionTimerRef.current !== null) window.clearTimeout(motionTimerRef.current);
    setIsRefreshing(true);
    motionTimerRef.current = window.setTimeout(() => {
      motionTimerRef.current = null;
      setIsRefreshing(false);
    }, motionDurationMs);
  }, [hierarchy, motionDurationMs, size]);

  useEffect(() => {
    return () => {
      if (motionTimerRef.current !== null) window.clearTimeout(motionTimerRef.current);
    };
  }, []);

  // Draw.
  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;
    const { w, h } = size;

    const layout = d3.treemap<SolHierNode>()
      .size([w, h])
      .paddingTop(16)
      .paddingRight(2)
      .paddingBottom(2)
      .paddingLeft(2)
      .paddingInner(1)
      .round(true);

    const layoutRoot = hierarchy.copy();
    layout(layoutRoot);
    const lRoot = layoutRoot as unknown as HNode;

    const sel = d3.select(svg);
    sel.selectAll("*").remove();
    sel.attr("viewBox", `0 0 ${w} ${h}`);

    const total = lRoot.value ?? 1;
    const focus = focusPath ?? "";

    const draw = (node: HNode, depth: number) => {
      const gw = node.x1 - node.x0;
      const gh = node.y1 - node.y0;
      if (gw < 2 || gh < 2) return;

      const base = d3.color(FAMILY_PALETTE[node.data.family] ?? "#557");
      const isLeaf = !node.children || node.children.length === 0;
      const isFocus = focus !== "" && node.data.path === focus;

      const fill = isLeaf
        ? (base?.brighter(0.25).toString() ?? "#557")
        : (base?.darker(0.6 + depth * 0.18).toString() ?? "#223");

      const rect = sel.append("rect")
        .attr("x", node.x0).attr("y", node.y0)
        .attr("width", gw).attr("height", gh)
        .attr("fill", fill)
        .attr("stroke", isFocus ? "#e8d5b8" : "#13161f")
        .attr("stroke-width", isFocus ? 2 : 0.8)
        .attr("rx", 2)
        .style("cursor", "pointer");

      rect
        .on("click", () => { if (node.data.path) onPick?.(node.data.path); })
        .on("mouseenter", (event: MouseEvent) => {
          const pct = (((node.value ?? 0) / total) * 100).toFixed(1) + "%";
          const count = `${node.value ?? 0} 叶子 (${pct})`;
          setTooltip({
            x: event.offsetX, y: event.offsetY,
            lines: [node.data.path || "(root)", node.data.kind, count].filter(Boolean)
          });
        })
        .on("mousemove", (event: MouseEvent) =>
          setTooltip((p) => (p ? { ...p, x: event.offsetX, y: event.offsetY } : null)))
        .on("mouseleave", () => setTooltip(null));

      // Container label inside the top padding band.
      if (!isLeaf && gw > 28 && gh > 16) {
        sel.append("text")
          .attr("x", node.x0 + 4).attr("y", node.y0 + 12)
          .attr("fill", "#cfe0ff").attr("font-size", "10px").attr("font-weight", "600")
          .text(truncText(node.data.name, gw - 8, 10))
          .style("pointer-events", "none");
      }
      // Leaf label.
      if (isLeaf && gw > 34 && gh > 14) {
        sel.append("text")
          .attr("x", node.x0 + 3).attr("y", node.y0 + 11)
          .attr("fill", "#1a1a2e").attr("font-size", "9px")
          .text(truncText(node.data.name, gw - 6, 9))
          .style("pointer-events", "none");
      }

      if (node.children) {
        for (const child of node.children) draw(child as HNode, depth + 1);
      }
    };

    for (const child of lRoot.children ?? []) draw(child as HNode, 1);
  }, [hierarchy, size, focusPath, onPick]);

  const wrapperClassName = [
    "treemap-svg-wrapper",
    `treemap-motion-${motionLevel}`,
    isRefreshing ? "treemap-state-refreshing" : ""
  ].filter(Boolean).join(" ");

  const leafTotal = hierarchy.value ?? 0;

  return (
    <div className="treemap-container">
      <div className="treemap-toolbar">
        <span className="treemap-caption">结构概览 · 面积 = 子树叶子数</span>
        <div className="sunburst-legend">
          {families.map((f) => (
            <span key={f} className="sunburst-legend-item">
              <span className="sunburst-legend-dot" style={{ background: FAMILY_PALETTE[f] }} />
              {FAMILY_LABEL[f]}
            </span>
          ))}
        </div>
        <span className="treemap-total">{leafTotal} 叶子</span>
      </div>
      <div className={wrapperClassName} ref={wrapperRef}>
        <svg ref={svgRef} className="treemap-svg" preserveAspectRatio="none" />
        {tooltip && (
          <div
            ref={tooltipRef}
            className="sunburst-tooltip"
            style={{
              left: tooltipPos?.left ?? tooltip.x + 14,
              top: tooltipPos?.top ?? tooltip.y - 14
            }}
          >
            {tooltip.lines.map((line, i) => (
              <div key={i} className={i === 0 ? "sunburst-tooltip-path" : ""}>{line}</div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
