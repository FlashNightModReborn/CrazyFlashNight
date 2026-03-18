import { useState, useCallback, useEffect, useRef } from "react";
import type { MotionProfile } from "../components/motion-utils.js";
import { clamp } from "../utils/helpers.js";

export const DEFAULT_LAYOUT = {
  controlSplit: 0.68,
  overviewSplit: 0.36,
  layerSplit: 0.23,
  detailSplit: 0.79
} as const;

export function useLayoutResize(motionProfile: MotionProfile) {
  const [isLayoutResizing, setIsLayoutResizing] = useState(false);
  const [isLayoutSettling, setIsLayoutSettling] = useState(false);
  const [activeResizeHandle, setActiveResizeHandle] = useState<string | null>(null);

  const activeResizeCleanupRef = useRef<(() => void) | null>(null);
  const settleTimeoutRef = useRef<number | null>(null);

  const controlShellRef = useRef<HTMLDivElement>(null);
  const mainContentRef = useRef<HTMLDivElement>(null);
  const overviewRef = useRef<HTMLDivElement>(null);
  const bottomSplitRef = useRef<HTMLDivElement>(null);

  // Cleanup on unmount
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

  // If motion is disabled mid-settle, cancel it
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
      container: React.RefObject<HTMLElement | null>;
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
    controlShellRef,
    mainContentRef,
    overviewRef,
    bottomSplitRef,
    beginResize,
    startLayoutSettle
  };
}
