/**
 * useLayoutResize — generic split-pane drag controller (mirrors cf7-packer).
 *
 * A single hook instance can drive multiple handles: each `beginResize` call
 * carries its own container ref, axis, clamp range, and setter. The hook owns
 * the window-level mouse listeners, the "is-resizing" body class/cursor, and a
 * brief "settle" flag (so panes can animate back into place once the drag ends
 * — but only when motion is enabled).
 *
 * CEP/Chromium-88: plain mouse events only (no Pointer Events capture quirks).
 */
import { useState, useCallback, useEffect, useRef } from 'react';
import type { MotionProfile } from '../components/motion-utils.js';

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export interface BeginResizeOptions {
  handleId: string;
  container: React.RefObject<HTMLElement | null>;
  axis: 'x' | 'y';
  min: number;
  max: number;
  setValue: (value: number) => void;
}

export function useLayoutResize(motionProfile: MotionProfile) {
  const [isLayoutResizing, setIsLayoutResizing] = useState(false);
  const [isLayoutSettling, setIsLayoutSettling] = useState(false);
  const [activeResizeHandle, setActiveResizeHandle] = useState<string | null>(null);

  const activeCleanupRef = useRef<(() => void) | null>(null);
  const settleTimeoutRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      activeCleanupRef.current?.();
      activeCleanupRef.current = null;
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

  useEffect(() => {
    if (motionProfile.settleMs > 0) return;
    clearSettle();
    setIsLayoutSettling(false);
  }, [clearSettle, motionProfile.settleMs]);

  const beginResize = useCallback(
    (clientX: number, clientY: number, options: BeginResizeOptions) => {
      const container = options.container.current;
      if (!container) return;
      activeCleanupRef.current?.();

      const rect = container.getBoundingClientRect();
      const size = options.axis === 'x' ? rect.width : rect.height;
      if (size <= 0) return;

      const updateValue = (nextClientX: number, nextClientY: number) => {
        const raw =
          options.axis === 'x'
            ? (nextClientX - rect.left) / size
            : (nextClientY - rect.top) / size;
        options.setValue(clamp(raw, options.min, options.max));
      };

      const onMouseMove = (moveEvent: MouseEvent) => {
        updateValue(moveEvent.clientX, moveEvent.clientY);
      };

      const stop = () => {
        window.removeEventListener('mousemove', onMouseMove);
        window.removeEventListener('mouseup', stop);
        window.removeEventListener('blur', stop);
        document.body.classList.remove('is-resizing');
        document.body.style.cursor = '';
        setIsLayoutResizing(false);
        setActiveResizeHandle(null);
        startLayoutSettle();
        activeCleanupRef.current = null;
      };

      clearSettle();
      setIsLayoutSettling(false);
      setIsLayoutResizing(true);
      setActiveResizeHandle(options.handleId);
      document.body.classList.add('is-resizing');
      document.body.style.cursor = options.axis === 'x' ? 'col-resize' : 'row-resize';
      updateValue(clientX, clientY);
      activeCleanupRef.current = stop;
      window.addEventListener('mousemove', onMouseMove);
      window.addEventListener('mouseup', stop);
      window.addEventListener('blur', stop);
    },
    [clearSettle, startLayoutSettle],
  );

  return {
    isLayoutResizing,
    isLayoutSettling,
    activeResizeHandle,
    beginResize,
    startLayoutSettle,
  };
}
