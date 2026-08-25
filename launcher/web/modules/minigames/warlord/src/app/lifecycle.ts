export class GenerationFence {
  private generation = 0;
  private disposed = false;

  public next(): number {
    if (this.disposed) return this.generation;
    this.generation += 1;
    return this.generation;
  }

  public current(): number {
    return this.generation;
  }

  public isCurrent(candidate: number): boolean {
    return !this.disposed && candidate === this.generation;
  }

  public invalidate(): void {
    if (!this.disposed) this.generation += 1;
  }

  public dispose(): void {
    this.generation += 1;
    this.disposed = true;
  }
}

export class DisposableBag {
  private callbacks: Array<() => void> = [];
  private disposed = false;

  public add(callback: () => void): void {
    if (this.disposed) {
      callback();
      return;
    }
    this.callbacks.push(callback);
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    for (const callback of this.callbacks.splice(0).reverse()) {
      try { callback(); } catch { /* teardown is best-effort and idempotent */ }
    }
  }
}

export function isEditableKeyboardTarget(target: unknown): boolean {
  if (!target || typeof target !== 'object') return false;
  const element = target as {
    tagName?: unknown;
    isContentEditable?: boolean;
    getAttribute?: (name: string) => string | null;
    closest?: (selector: string) => unknown;
  };
  const tagName = typeof element.tagName === 'string' ? element.tagName.toUpperCase() : '';
  if (tagName === 'INPUT' || tagName === 'TEXTAREA' || tagName === 'SELECT'
    || tagName === 'BUTTON' || tagName === 'OPTION') return true;
  if (element.isContentEditable === true) return true;
  const contentEditable = element.getAttribute?.('contenteditable');
  if (contentEditable !== undefined && contentEditable !== null && contentEditable !== 'false') return true;
  return Boolean(element.closest?.('input, textarea, select, button, [contenteditable]:not([contenteditable="false"])'));
}
