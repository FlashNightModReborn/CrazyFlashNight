import { describe, expect, it } from "vitest";
import {
  resolveTooltipPlacement,
  resolveTreemapResizeState,
  sameTreemapSize,
  sanitizeTreemapSize
} from "../src/renderer/components/treemap-utils.js";

describe("treemap-utils", () => {
  it("sanitizes invalid observed sizes", () => {
    expect(sanitizeTreemapSize(0, 200)).toBeNull();
    expect(sanitizeTreemapSize(320, 0)).toBeNull();
    expect(sanitizeTreemapSize(320, 180)).toEqual({ w: 320, h: 180 });
  });

  it("treats near-identical sizes as equal", () => {
    expect(sameTreemapSize({ w: 400, h: 240 }, { w: 400.2, h: 239.7 })).toBe(true);
    expect(sameTreemapSize({ w: 400, h: 240 }, { w: 401, h: 240 })).toBe(false);
  });

  it("defers treemap commits while layout is actively resizing", () => {
    const result = resolveTreemapResizeState({
      currentSize: { w: 640, h: 300 },
      pendingSize: { w: 640, h: 300 },
      observedSize: { w: 900, h: 300 },
      isLayoutResizing: true
    });

    expect(result.shouldCommit).toBe(false);
    expect(result.size).toEqual({ w: 640, h: 300 });
    expect(result.pendingSize).toEqual({ w: 900, h: 300 });
  });

  it("flushes the latest pending size after resizing stops", () => {
    const result = resolveTreemapResizeState({
      currentSize: { w: 640, h: 300 },
      pendingSize: { w: 900, h: 300 },
      observedSize: null,
      isLayoutResizing: false
    });

    expect(result.shouldCommit).toBe(true);
    expect(result.size).toEqual({ w: 900, h: 300 });
  });

  it("keeps tooltip within visible bounds", () => {
    const placement = resolveTooltipPlacement(
      { x: 290, y: 160 },
      { width: 120, height: 60 },
      { width: 320, height: 180 }
    );

    expect(placement.left).toBeLessThanOrEqual(320 - 120 - 8);
    expect(placement.top).toBeLessThanOrEqual(180 - 60 - 8);
    expect(placement.left).toBeGreaterThanOrEqual(8);
    expect(placement.top).toBeGreaterThanOrEqual(8);
  });
});
