/**
 * LinkageCoverageChart — D3 v7 stacked horizontal bar of AS-linkage coverage
 * by library item type ("exported" vs "missing"). Mirrors the cf7-packer
 * pattern: a ResizeObserver-driven SVG, an imperative d3 render in a layout
 * effect, and an HTML tooltip overlay positioned within the wrapper.
 *
 * CEP/Chromium-88: only SVG + transitions; no foreignObject, no WAAPI.
 */
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import * as d3 from 'd3';

export interface CoverageRow {
  /** Library item type, e.g. "movie clip". */
  type: string;
  /** Items of this type that already export for ActionScript. */
  exported: number;
  /** Linkable items of this type still missing linkage. */
  missing: number;
}

interface Size {
  w: number;
  h: number;
}

interface TooltipState {
  x: number;
  y: number;
  lines: string[];
}

const COLOR_EXPORTED = '#5cb85c';
const COLOR_MISSING = '#e0a040';
const ROW_H = 24;
const ROW_GAP = 6;
const TOP_PAD = 6;
const BOTTOM_PAD = 18;
const LABEL_W = 92;
const RIGHT_PAD = 8;

function sameSize(a: Size, b: Size): boolean {
  return Math.abs(a.w - b.w) < 0.5 && Math.abs(a.h - b.h) < 0.5;
}

export default function LinkageCoverageChart({
  rows,
  motionDurationMs = 140,
  onSelectType,
  activeType = null,
}: {
  rows: CoverageRow[];
  motionDurationMs?: number;
  onSelectType?: (type: string | null) => void;
  activeType?: string | null;
}) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const [width, setWidth] = useState(280);
  const widthRef = useRef(280);
  const frameRef = useRef<number | null>(null);
  const [tooltip, setTooltip] = useState<TooltipState | null>(null);

  // Only types that actually have linkable items are worth charting.
  const data = useMemo(
    () => rows.filter((r) => r.exported + r.missing > 0),
    [rows],
  );

  const height = useMemo(
    () => TOP_PAD + BOTTOM_PAD + Math.max(1, data.length) * (ROW_H + ROW_GAP),
    [data.length],
  );

  // Responsive width via ResizeObserver (rAF-coalesced like the template).
  useEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    const commit = (w: number) => {
      if (!(w > 0)) return;
      if (Math.abs(widthRef.current - w) < 0.5) return;
      widthRef.current = w;
      setWidth(w);
    };
    const ro = new ResizeObserver((entries) => {
      const cr = entries[0]?.contentRect;
      if (!cr) return;
      const w = cr.width;
      if (frameRef.current !== null) cancelAnimationFrame(frameRef.current);
      frameRef.current = requestAnimationFrame(() => {
        frameRef.current = null;
        commit(w);
      });
    });
    ro.observe(el);
    commit(el.getBoundingClientRect().width);
    return () => {
      ro.disconnect();
      if (frameRef.current !== null) {
        cancelAnimationFrame(frameRef.current);
        frameRef.current = null;
      }
    };
  }, []);

  useLayoutEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;
    const sel = d3.select(svg);
    sel.selectAll('*').remove();
    sel.attr('viewBox', `0 0 ${width} ${height}`).attr('width', width).attr('height', height);

    if (data.length === 0) {
      sel
        .append('text')
        .attr('x', width / 2)
        .attr('y', height / 2)
        .attr('text-anchor', 'middle')
        .attr('fill', '#9a9a9a')
        .attr('font-size', '11px')
        .text('No linkable items');
      return;
    }

    const maxTotal = d3.max(data, (d) => d.exported + d.missing) ?? 1;
    const plotW = Math.max(20, width - LABEL_W - RIGHT_PAD);
    const x = d3.scaleLinear().domain([0, maxTotal]).range([0, plotW]);
    const animate = motionDurationMs > 0;

    const showTip = (event: MouseEvent, lines: string[]) => {
      const wrapRect = wrapperRef.current?.getBoundingClientRect();
      const sx = (wrapRect ? event.clientX - wrapRect.left : event.offsetX) + 10;
      const sy = (wrapRect ? event.clientY - wrapRect.top : event.offsetY) + 10;
      setTooltip({ x: sx, y: sy, lines });
    };

    data.forEach((d, i) => {
      const y = TOP_PAD + i * (ROW_H + ROW_GAP);
      const total = d.exported + d.missing;
      const dim = activeType != null && activeType !== d.type;

      const g = sel.append('g').attr('opacity', dim ? 0.4 : 1).style('cursor', 'pointer');

      // Row label (item type).
      g.append('text')
        .attr('x', 0)
        .attr('y', y + ROW_H / 2 + 4)
        .attr('fill', '#cfcfcf')
        .attr('font-size', '11px')
        .text(d.type.length > 13 ? d.type.slice(0, 12) + '…' : d.type)
        .append('title')
        .text(d.type);

      const trackX = LABEL_W;
      // Track background.
      g.append('rect')
        .attr('x', trackX)
        .attr('y', y)
        .attr('width', plotW)
        .attr('height', ROW_H)
        .attr('rx', 3)
        .attr('fill', '#272727')
        .attr('stroke', '#1f1f1f');

      const exportedW = x(d.exported);
      const missingW = x(d.missing);

      // Exported segment.
      const expRect = g
        .append('rect')
        .attr('x', trackX)
        .attr('y', y)
        .attr('height', ROW_H)
        .attr('rx', 3)
        .attr('fill', COLOR_EXPORTED)
        .attr('width', animate ? 0 : exportedW);
      expRect
        .on('mousemove', (e: MouseEvent) =>
          showTip(e, [d.type, `${d.exported} exported (${pct(d.exported, total)})`]),
        )
        .on('mouseleave', () => setTooltip(null))
        .on('click', () => onSelectType?.(activeType === d.type ? null : d.type));
      if (animate) expRect.transition().duration(motionDurationMs).attr('width', exportedW);

      // Missing segment (stacked after exported).
      const misRect = g
        .append('rect')
        .attr('x', trackX + exportedW)
        .attr('y', y)
        .attr('height', ROW_H)
        .attr('rx', 3)
        .attr('fill', COLOR_MISSING)
        .attr('width', animate ? 0 : missingW);
      misRect
        .on('mousemove', (e: MouseEvent) =>
          showTip(e, [d.type, `${d.missing} missing (${pct(d.missing, total)})`]),
        )
        .on('mouseleave', () => setTooltip(null))
        .on('click', () => onSelectType?.(activeType === d.type ? null : d.type));
      if (animate) misRect.transition().duration(motionDurationMs).attr('width', missingW);

      // Count label at the end of the row.
      g.append('text')
        .attr('x', trackX + plotW)
        .attr('y', y + ROW_H / 2 + 4)
        .attr('text-anchor', 'end')
        .attr('fill', '#e6e6e6')
        .attr('font-size', '10px')
        .attr('font-weight', '600')
        .style('pointer-events', 'none')
        .text(`${d.exported}/${total}`);

      // Whole-row click target overlay (so the label/track also toggles).
      g.append('rect')
        .attr('x', 0)
        .attr('y', y)
        .attr('width', width)
        .attr('height', ROW_H)
        .attr('fill', 'transparent')
        .on('click', () => onSelectType?.(activeType === d.type ? null : d.type))
        .on('mousemove', (e: MouseEvent) =>
          showTip(e, [d.type, `${d.exported} exported · ${d.missing} missing`]),
        )
        .on('mouseleave', () => setTooltip(null));
    });

    // Legend at the bottom.
    const legendY = height - 10;
    const legend = sel.append('g').style('pointer-events', 'none');
    legend.append('rect').attr('x', LABEL_W).attr('y', legendY - 8).attr('width', 9).attr('height', 9).attr('rx', 2).attr('fill', COLOR_EXPORTED);
    legend.append('text').attr('x', LABEL_W + 13).attr('y', legendY).attr('fill', '#9a9a9a').attr('font-size', '10px').text('exported');
    legend.append('rect').attr('x', LABEL_W + 74).attr('y', legendY - 8).attr('width', 9).attr('height', 9).attr('rx', 2).attr('fill', COLOR_MISSING);
    legend.append('text').attr('x', LABEL_W + 87).attr('y', legendY).attr('fill', '#9a9a9a').attr('font-size', '10px').text('missing');
  }, [data, width, height, motionDurationMs, activeType, onSelectType]);

  return (
    <div className="coverage-chart" ref={wrapperRef}>
      <svg ref={svgRef} className="coverage-svg" preserveAspectRatio="xMinYMin meet" />
      {tooltip && (
        <div className="coverage-tooltip" style={{ left: tooltip.x, top: tooltip.y }}>
          {tooltip.lines.map((line, i) => (
            <div key={i} className={i === 0 ? 'coverage-tooltip-head' : ''}>
              {line}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function pct(n: number, total: number): string {
  if (total <= 0) return '0%';
  return ((n / total) * 100).toFixed(0) + '%';
}
