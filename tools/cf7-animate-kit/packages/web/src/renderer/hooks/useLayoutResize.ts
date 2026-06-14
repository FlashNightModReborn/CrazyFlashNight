import { useState, useCallback, useEffect, useRef } from "react";
import type { RefObject } from "react";
import type { MotionProfile } from "../components/motion-utils.js";
import { clamp } from "../components/motion-utils.js";

/**
 * Drag-to-resize plumbing shared by every split pane, mirroring the cf7-packer
 * pattern: a single `beginResize` attaches window-level mouse listeners, clamps
 * the fractional split to [min, max], and emits resize/settle phase flags so the
 * surfaces can animate. Persistence is suppressed while `isLayoutResizing`.
 */
export function useLayoutResize(motionProfile: MotionProfile) {
  const [isLayoutResizing, setIsLayoutResizing] = useState(false);
  const [isLayoutSettling, setIsLayoutSettling] = useState(false);
  const [activeResizeHandle, setActiveResizeHandle] = useState<string | null>(null);

  const activeResizeCleanupRef = useRef<(() => void) | null>(null);
  const settleTimeoutRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      activeResizeCleanupRef.current?.();
      activeResizeCleanupRef.current = null;
      if (settleTimeoutRef.current !== null) {
        window.clearTimeout(settleTimeoutRef.current);
        settleTimeoutRef.current = null;
      }
    };
  }, []);

  const clearSettle = useCallback(() => {
    if (settleTimeoutRef.current !== null) {
      window.clearTimeout(settleTimeoutRef.current);
      settleTimeoutRef.current = null;
    }
  }, []);

  const startLayoutSettle = useCallback(() => {
    clearSettle();
    if (motionProfile.settleMs <= 0) {
      setIsLayoutSettling(false);
      return;
    }
    setIsLayoutSettling(true);
    settleTimeoutRef.current = window.setTimeout(() => {
      settleTimeoutRef.current = null;
      setIsLayoutSettling(false);
    }, motionProfile.settleMs);
  }, [clearSettle, motionProfile.settleMs]);

  // If motion gets disabled mid-settle, cancel the lingering animation flag.
  useEffect(() => {
    if (motionProfile.settleMs > 0) return;
    clearSettle();
    setIsLayoutSettling(false);
  }, [clearSettle, motionProfile.settleMs]);

  const beginResize = useCallback((
    clientX: number,
    clientY: number,
    options: {
      handleId: string;
      container: RefObject<HTMLElement | null>;
      axis: "x" | "y";
      min: number;
      max: number;
      setValue: (value: number) => void;
    }
  ) => {
    const container = options.container.current;
    if (!container) return;
    activeResizeCleanupRef.current?.();

    const rect = container.getBoundingClientRect();
    const size = options.axis === "x" ? rect.width : rect.height;
    if (size <= 0) return;

    const updateValue = (nextClientX: number, nextClientY: number) => {
      const raw = options.axis === "x"
        ? (nextClientX - rect.left) / size
        : (nextClientY - rect.top) / size;
      options.setValue(clamp(raw, options.min, options.max));
    };

    const onMouseMove = (moveEvent: MouseEvent) => {
      updateValue(moveEvent.clientX, moveEvent.clientY);
    };

    const stop = () => {
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", stop);
      window.removeEventListener("blur", stop);
      document.body.classList.remove("is-resizing");
      document.body.style.cursor = "";
      setIsLayoutResizing(false);
      setActiveResizeHandle(null);
      startLayoutSettle();
      activeResizeCleanupRef.current = null;
    };

    clearSettle();
    setIsLayoutSettling(false);
    setIsLayoutResizing(true);
    setActiveResizeHandle(options.handleId);
    document.body.classList.add("is-resizing");
    document.body.style.cursor = options.axis === "x" ? "col-resize" : "row-resize";
    updateValue(clientX, clientY);
    activeResizeCleanupRef.current = stop;
    window.addEventListener("mousemove", onMouseMove);
    window.addEventListener("mouseup", stop);
    window.addEventListener("blur", stop);
  }, [clearSettle, startLayoutSettle]);

  return {
    isLayoutResizing,
    isLayoutSettling,
    activeResizeHandle,
    beginResize,
    startLayoutSettle
  };
}

export type LayoutController = ReturnType<typeof useLayoutResize>;

/** Subscribes a panel to the global "reset layout" broadcast from the header. */
export function useResetLayoutSignal(onReset: () => void) {
  useEffect(() => {
    const handler = () => onReset();
    window.addEventListener("ankit:reset-layout", handler);
    return () => window.removeEventListener("ankit:reset-layout", handler);
  }, [onReset]);
}
