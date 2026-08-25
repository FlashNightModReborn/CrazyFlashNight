export class GenerationFence {
    generation = 0;
    disposed = false;
    next() {
        if (this.disposed)
            return this.generation;
        this.generation += 1;
        return this.generation;
    }
    current() {
        return this.generation;
    }
    isCurrent(candidate) {
        return !this.disposed && candidate === this.generation;
    }
    invalidate() {
        if (!this.disposed)
            this.generation += 1;
    }
    dispose() {
        this.generation += 1;
        this.disposed = true;
    }
}
export class DisposableBag {
    callbacks = [];
    disposed = false;
    add(callback) {
        if (this.disposed) {
            callback();
            return;
        }
        this.callbacks.push(callback);
    }
    dispose() {
        if (this.disposed)
            return;
        this.disposed = true;
        for (const callback of this.callbacks.splice(0).reverse()) {
            try {
                callback();
            }
            catch { /* teardown is best-effort and idempotent */ }
        }
    }
}
export function isEditableKeyboardTarget(target) {
    if (!target || typeof target !== 'object')
        return false;
    const element = target;
    const tagName = typeof element.tagName === 'string' ? element.tagName.toUpperCase() : '';
    if (tagName === 'INPUT' || tagName === 'TEXTAREA' || tagName === 'SELECT'
        || tagName === 'BUTTON' || tagName === 'OPTION')
        return true;
    if (element.isContentEditable === true)
        return true;
    const contentEditable = element.getAttribute?.('contenteditable');
    if (contentEditable !== undefined && contentEditable !== null && contentEditable !== 'false')
        return true;
    return Boolean(element.closest?.('input, textarea, select, button, [contenteditable]:not([contenteditable="false"])'));
}
//# sourceMappingURL=lifecycle.js.map