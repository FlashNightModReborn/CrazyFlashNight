import type { SharedOrbitViews } from "./types.js";

export const SHARED_CONTROL_WORDS = 3;
const CONTROL_BYTES = SHARED_CONTROL_WORDS * Int32Array.BYTES_PER_ELEMENT;

export function sharedOrbitByteLength(cellCount: number): number {
  if (!Number.isInteger(cellCount) || cellCount < 1) {
    throw new RangeError("cellCount must be a positive integer");
  }
  return CONTROL_BYTES + 2 * cellCount * Uint32Array.BYTES_PER_ELEMENT;
}

/** Constructor/initialization helper; not part of the per-board hot path. */
export function createSharedOrbitViews(cellCount: number): SharedOrbitViews {
  const storage = new SharedArrayBuffer(sharedOrbitByteLength(cellCount));
  const control = new Int32Array(storage, 0, SHARED_CONTROL_WORDS);
  const first = new Uint32Array(storage, CONTROL_BYTES, cellCount);
  const second = new Uint32Array(
    storage,
    CONTROL_BYTES + cellCount * Uint32Array.BYTES_PER_ELEMENT,
    cellCount,
  );
  return { storage, control, boards: [first, second] };
}

export function mapSharedOrbitViews(storage: SharedArrayBuffer, cellCount: number): SharedOrbitViews {
  if (storage.byteLength !== sharedOrbitByteLength(cellCount)) {
    throw new RangeError("SharedArrayBuffer has the wrong byte length");
  }
  const control = new Int32Array(storage, 0, SHARED_CONTROL_WORDS);
  const first = new Uint32Array(storage, CONTROL_BYTES, cellCount);
  const second = new Uint32Array(
    storage,
    CONTROL_BYTES + cellCount * Uint32Array.BYTES_PER_ELEMENT,
    cellCount,
  );
  return { storage, control, boards: [first, second] };
}

/**
 * Pin the current front buffer so the worker will not recycle it. The returned
 * view already exists; caller must release it after the synchronous upload.
 */
export function acquireSharedFront(views: SharedOrbitViews): Uint32Array {
  for (;;) {
    const front = Atomics.load(views.control, 0);
    Atomics.store(views.control, 2, front + 1);
    if (Atomics.load(views.control, 0) === front) {
      return views.boards[front]!;
    }
    Atomics.store(views.control, 2, 0);
  }
}

export function releaseSharedFront(views: SharedOrbitViews): void {
  Atomics.store(views.control, 2, 0);
}
