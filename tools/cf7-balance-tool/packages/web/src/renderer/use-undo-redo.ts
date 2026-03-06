import { useCallback, useRef, useState } from "react";

const MAX_HISTORY = 50;

export interface UndoRedoControls<T> {
  state: T;
  set: (next: T) => void;
  update: (fn: (prev: T) => T) => void;
  undo: () => void;
  redo: () => void;
  canUndo: boolean;
  canRedo: boolean;
  reset: (initial: T) => void;
}

export function useUndoRedo<T>(initial: T): UndoRedoControls<T> {
  const [state, setState] = useState(initial);
  const past = useRef<T[]>([]);
  const future = useRef<T[]>([]);

  const set = useCallback((next: T) => {
    setState((prev) => {
      past.current = trimHistory([...past.current, prev]);
      future.current = [];
      return next;
    });
  }, []);

  const update = useCallback((fn: (prev: T) => T) => {
    setState((prev) => {
      const next = fn(prev);
      if (next === prev) return prev;
      past.current = trimHistory([...past.current, prev]);
      future.current = [];
      return next;
    });
  }, []);

  const undo = useCallback(() => {
    setState((current) => {
      if (past.current.length === 0) return current;
      const prev = past.current[past.current.length - 1]!;
      past.current = past.current.slice(0, -1);
      future.current = [current, ...future.current];
      return prev;
    });
  }, []);

  const redo = useCallback(() => {
    setState((current) => {
      if (future.current.length === 0) return current;
      const next = future.current[0]!;
      future.current = future.current.slice(1);
      past.current = [...past.current, current];
      return next;
    });
  }, []);

  const reset = useCallback((newInitial: T) => {
    past.current = [];
    future.current = [];
    setState(newInitial);
  }, []);

  return {
    state,
    set,
    update,
    undo,
    redo,
    canUndo: past.current.length > 0,
    canRedo: future.current.length > 0,
    reset
  };
}

function trimHistory<T>(arr: T[]): T[] {
  if (arr.length <= MAX_HISTORY) return arr;
  return arr.slice(arr.length - MAX_HISTORY);
}
