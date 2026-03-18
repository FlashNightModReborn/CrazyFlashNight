export interface TreemapSize {
  w: number;
  h: number;
}

export interface TreemapTooltipPlacement {
  left: number;
  top: number;
}

export interface TreemapResizeStateInput {
  currentSize: TreemapSize;
  pendingSize: TreemapSize;
  observedSize: TreemapSize | null;
  isLayoutResizing: boolean;
}

export interface TreemapResizeStateResult {
  size: TreemapSize;
  pendingSize: TreemapSize;
  shouldCommit: boolean;
}

export function sanitizeTreemapSize(width: number, height: number): TreemapSize | null {
  if (!(width > 0 && height > 0)) return null;
  return { w: width, h: height };
}

export function sameTreemapSize(a: TreemapSize, b: TreemapSize): boolean {
  return Math.abs(a.w - b.w) < 0.5 && Math.abs(a.h - b.h) < 0.5;
}

export function resolveTreemapResizeState(input: TreemapResizeStateInput): TreemapResizeStateResult {
  const nextPending = input.observedSize ?? input.pendingSize;

  if (input.isLayoutResizing) {
    return {
      size: input.currentSize,
      pendingSize: nextPending,
      shouldCommit: false
    };
  }

  const candidate = input.observedSize ?? input.pendingSize;
  const shouldCommit = !sameTreemapSize(input.currentSize, candidate);

  return {
    size: shouldCommit ? candidate : input.currentSize,
    pendingSize: candidate,
    shouldCommit
  };
}

export function resolveTooltipPlacement(
  pointer: { x: number; y: number },
  tooltipBox: { width: number; height: number },
  wrapperBox: { width: number; height: number },
  options?: { margin?: number; offsetX?: number; offsetY?: number }
): TreemapTooltipPlacement {
  const margin = options?.margin ?? 8;
  const offsetX = options?.offsetX ?? 14;
  const offsetY = options?.offsetY ?? 14;
  const maxLeft = Math.max(margin, wrapperBox.width - tooltipBox.width - margin);
  const maxTop = Math.max(margin, wrapperBox.height - tooltipBox.height - margin);

  return {
    left: clamp(pointer.x + offsetX, margin, maxLeft),
    top: clamp(pointer.y - offsetY, margin, maxTop)
  };
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
