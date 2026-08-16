/** Fixed navigation transaction for InventoryWorkbench's build/storage/tuning views. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchNavigation = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function valueKey(node, attribute, prefix) {
        var value = node && node.getAttribute && node.getAttribute(attribute);
        return value ? prefix + value : '';
    }

    function focusKey(node) {
        return valueKey(node, 'data-header-action', 'header:')
            || valueKey(node, 'data-roving-key', 'roving:')
            || valueKey(node, 'data-workbench-key', 'workbench:');
    }

    function findTarget(root, attribute, value) {
        if (!root || !value) return null;
        var nodes = root.querySelectorAll('[' + attribute + ']');
        for (var i = 0; i < nodes.length; i++) {
            if (nodes[i].getAttribute(attribute) === value) return nodes[i];
        }
        return null;
    }

    function Navigation(options) {
        options = options || {};
        if (!options.stack || !options.document || !options.getRoot) {
            throw new Error('Inventory workbench navigation requires stack, document and root');
        }
        this._stack = options.stack;
        this._document = options.document;
        this._getRoot = options.getRoot;
        this._ports = options.ports || {};
        this._view = String(options.view || '');
        this._pending = null;
        this._sequence = 0;
        this._generation = 0;
        this._destroyed = false;
        this._setTimer = options.setTimer || function(callback, delay) {
            return setTimeout(callback, delay);
        };
        this._clearTimer = options.clearTimer || function(timer) {
            clearTimeout(timer);
        };
        this._pendingTimeoutMs = Math.max(
            1000, Number(options.pendingTimeoutMs) || 30000);
    }

    Navigation.prototype._restoreFocus = function(key) {
        if (this._destroyed) return false;
        key = String(key || '');
        var split = key.indexOf(':');
        var kind = split > 0 ? key.slice(0, split) : '';
        var value = split > 0 ? key.slice(split + 1) : '';
        var root = this._getRoot();
        var target = kind === 'header' ? findTarget(root, 'data-header-action', value)
            : kind === 'roving' ? findTarget(root, 'data-roving-key', value)
                : kind === 'workbench' ? findTarget(root, 'data-workbench-key', value) : null;
        if (!target || target.hidden || target.disabled
                || target.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
        target.focus();
        return this._document.activeElement === target;
    };

    Navigation.prototype._begin = function(next, options) {
        options = options || {};
        if (this._destroyed || this._pending || next === this._view) return null;
        var opener = options.opener || this._document.activeElement;
        var plan = options.plan || this._stack.plan(
            next, options.origin || 'local-switch', focusKey(opener));
        if (!plan || plan.entry.viewId !== next) return null;
        var generation = ++this._generation;
        var transaction = {
            id:++this._sequence,
            generation:generation,
            fromView:this._view,
            next:next,
            plan:plan,
            failureFocusKey:focusKey(opener),
            reportedView:'',
            preparing:false,
            timeoutHandle:null,
            status:'pending'
        };
        this._pending = transaction;
        this._armPendingTimeout(transaction);
        return transaction;
    };

    Navigation.prototype._isLiveTransaction = function(transaction, generation) {
        return !this._destroyed
            && !!transaction
            && transaction === this._pending
            && transaction.status === 'pending'
            && transaction.generation === generation
            && this._generation === generation;
    };

    Navigation.prototype._clearPendingTimeout = function(transaction) {
        if (!transaction || transaction.timeoutHandle === null) return;
        this._clearTimer(transaction.timeoutHandle);
        transaction.timeoutHandle = null;
    };

    Navigation.prototype._armPendingTimeout = function(transaction) {
        var self = this, generation = transaction.generation;
        transaction.timeoutHandle = this._setTimer(function() {
            if (!self._isLiveTransaction(transaction, generation)) return;
            if (transaction.next === 'build' && self._ports.discardBuild) {
                self._ports.discardBuild();
            } else if (transaction.next !== 'build' && self._ports.discardStorage) {
                self._ports.discardStorage();
            }
            if (self._ports.onTimeout) self._ports.onTimeout(transaction.next);
            self._abort(transaction);
        }, this._pendingTimeoutMs);
        if (transaction.timeoutHandle
                && typeof transaction.timeoutHandle.unref === 'function') {
            transaction.timeoutHandle.unref();
        }
    };

    Navigation.prototype._supersede = function(transaction, reportedView) {
        if (!this._isLiveTransaction(transaction, transaction && transaction.generation)) {
            return false;
        }
        this._clearPendingTimeout(transaction);
        transaction.status = 'superseded';
        this._pending = null;
        this._generation++;
        if (transaction.next === 'build' && this._ports.discardBuild) {
            this._ports.discardBuild();
        }
        if (this._ports.onSupersede) {
            this._ports.onSupersede(transaction.next, reportedView);
        }
        return true;
    };

    Navigation.prototype._finish = function(transaction, next) {
        if (!this._isLiveTransaction(transaction, transaction && transaction.generation)
                || transaction.next !== next) return false;
        if (!this._stack.commit(transaction.plan)) return this._abort(transaction);
        this._clearPendingTimeout(transaction);
        transaction.status = 'committed';
        this._pending = null;
        this._view = next;
        if (this._ports.onCommit) {
            this._ports.onCommit(next, transaction.fromView, transaction.plan);
        }
        if (transaction.plan.restoreFocusKey) {
            this._restoreFocus(transaction.plan.restoreFocusKey);
        }
        return true;
    };

    Navigation.prototype._abort = function(transaction) {
        if (!this._isLiveTransaction(transaction, transaction && transaction.generation)) return false;
        this._clearPendingTimeout(transaction);
        transaction.status = 'aborted';
        this._pending = null;
        if (this._ports.onAbort) this._ports.onAbort(transaction.fromView);
        this._restoreFocus(transaction.failureFocusKey);
        return false;
    };

    Navigation.prototype._reconcileReported = function(next, reason) {
        if (this._destroyed) return false;
        if (next !== 'storage' && next !== 'tuning' && next !== 'build') return false;
        if (next === this._view) return true;
        var previous = this._view;
        var entry = this._stack.reset({
            viewId:next,
            origin:'controller-resync',
            returnTarget:'game',
            focusKey:focusKey(this._document.activeElement)
        });
        this._view = next;
        if (this._ports.onDesync) this._ports.onDesync(next, previous, reason);
        if (this._ports.onCommit) {
            this._ports.onCommit(next, previous, {
                mode:'reset',
                entry:entry,
                reason:String(reason || 'controller-report')
            });
        }
        return true;
    };

    Navigation.prototype._activateBuild = function(transaction) {
        var generation = transaction && transaction.generation;
        if (!this._isLiveTransaction(transaction, generation)) return false;
        var activated = false;
        try {
            activated = this._ports.activateBuild();
        } catch (error) {
            if (!this._isLiveTransaction(transaction, generation)) return false;
            if (this._ports.discardBuild) this._ports.discardBuild();
            this._abort(transaction);
            if (this._ports.onError) this._ports.onError('build');
            return false;
        }
        if (!this._isLiveTransaction(transaction, generation)) return false;
        if (!activated && transaction.status === 'pending') {
            if (this._ports.discardBuild) this._ports.discardBuild();
            this._abort(transaction);
        }
        return !!activated && transaction.status !== 'aborted';
    };

    Navigation.prototype._prepareStorage = function(transaction, next) {
        var generation = transaction && transaction.generation;
        if (!this._isLiveTransaction(transaction, generation)) return false;
        next = next === 'tuning' ? 'tuning' : 'storage';
        var started = false;
        transaction.preparing = true;
        try {
            started = this._ports.ensureStorage(next);
        } catch (error) {
            transaction.preparing = false;
            if (!this._isLiveTransaction(transaction, generation)) return false;
            if (this._ports.discardStorage) this._ports.discardStorage();
            this._abort(transaction);
            if (this._ports.onError) this._ports.onError(next);
            return false;
        }
        transaction.preparing = false;
        if (!this._isLiveTransaction(transaction, generation)) return false;
        if (!started) return this._abort(transaction);
        var reported = transaction.reportedView
            || (this._ports.getStorageView ? this._ports.getStorageView() : '');
        return reported === next ? this._finish(transaction, next) : true;
    };

    Navigation.prototype.request = function(next, options) {
        if (this._destroyed) return false;
        if (next !== 'build' && next !== 'storage' && next !== 'tuning') return false;
        if (this.rejectIfPending()) return false;
        var transaction = this._begin(next, options);
        if (!transaction) return false;
        var self = this, generation = transaction.generation, started = false;
        if (next === 'build') {
            if (!this._ports.canEnterBuild || !this._ports.canEnterBuild()) {
                return this._abort(transaction);
            }
            started = this._ports.prepareStorageLeave(function(ready) {
                if (!self._isLiveTransaction(transaction, generation)) return;
                if (ready) self._activateBuild(transaction);
                else self._abort(transaction);
            });
        } else if (this._view === 'build') {
            started = this._ports.prepareBuildLeave(function(ready) {
                if (!self._isLiveTransaction(transaction, generation)) return;
                if (ready) self._prepareStorage(transaction, next);
                else self._abort(transaction);
            });
        } else {
            try { started = this._ports.switchStorage(next); }
            catch (error) {
                this._abort(transaction);
                if (this._ports.onError) this._ports.onError('switch');
                return false;
            }
        }
        if (!started && transaction.status === 'pending') this._abort(transaction);
        return !!started;
    };

    Navigation.prototype.storageChanged = function(next) {
        if (this._destroyed) return false;
        if (next !== 'storage' && next !== 'tuning' && next !== 'build') {
            if (typeof console !== 'undefined' && console.warn) {
                console.warn('[InventoryWorkbenchNavigation] invalid controller view report', next);
            }
            return false;
        }
        if (this._pending && this._pending.next === next) {
            var transaction = this._pending;
            transaction.reportedView = next;
            if (transaction.preparing) return true;
            if (this._finish(transaction, next)) return true;
            return this._reconcileReported(next, 'pending-commit-rejected');
        }
        if (this._pending) this._supersede(this._pending, next);
        if (next === this._view) return true;
        var plan = this._stack.plan(
            next, 'storage-controller', focusKey(this._document.activeElement));
        if (!plan || !this._stack.commit(plan)) {
            return this._reconcileReported(next, 'controller-plan-rejected');
        }
        var previous = this._view;
        this._view = next;
        if (this._ports.onCommit) this._ports.onCommit(next, previous, plan);
        return true;
    };

    Navigation.prototype.buildReady = function() {
        return !!(this._pending && this._pending.next === 'build'
            && this._finish(this._pending, 'build'));
    };
    Navigation.prototype.buildFailed = function() {
        var transaction = this._pending;
        if (!this._isLiveTransaction(transaction, transaction && transaction.generation)
                || transaction.next !== 'build') return false;
        if (this._ports.discardBuild) this._ports.discardBuild();
        this._abort(transaction);
        return true;
    };
    Navigation.prototype.storageFailed = function(next) {
        var transaction = this._pending;
        if (!this._isLiveTransaction(transaction, transaction && transaction.generation)
                || transaction.next !== next) return false;
        this._abort(transaction);
        return true;
    };
    Navigation.prototype.returnPlan = function(origin) {
        return this._destroyed ? null : this._stack.returnPlan(origin || 'escape');
    };
    Navigation.prototype.canReturnTo = function(viewId) {
        return !this._destroyed && this._stack.canReturnTo(viewId);
    };
    Navigation.prototype.rejectIfPending = function() {
        if (this._destroyed) return false;
        if (!this._pending) return false;
        if (this._ports.onPending) this._ports.onPending(this._pending.next);
        return true;
    };
    Navigation.prototype.isPending = function() { return !!this._pending; };
    Navigation.prototype.snapshot = function() { return this._stack.snapshot(); };
    Navigation.prototype.debugState = function() {
        return this._pending ? {
            id:this._pending.id,
            fromView:this._pending.fromView,
            next:this._pending.next,
            status:this._pending.status
        } : null;
    };
    Navigation.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._generation++;
        if (this._pending && this._pending.status === 'pending') {
            this._clearPendingTimeout(this._pending);
            this._pending.status = 'destroyed';
        }
        this._pending = null;
        this._ports = {};
        this._document = null;
        this._getRoot = function() { return null; };
        return true;
    };

    function create(options) {
        options = options || {};
        var storage = options.storage;
        if (!storage || !options.ensureBuild || !options.ensureStorage) {
            throw new Error('Inventory workbench navigation requires fixed build/storage ports');
        }
        var navigation = new Navigation({
            document:options.document,
            getRoot:options.getRoot,
            stack:options.stack,
            view:options.view,
            pendingTimeoutMs:options.pendingTimeoutMs,
            ports:{
                canEnterBuild:function() {
                    var build = options.getBuild();
                    return !!(build && options.storageReady() && build.canLeave());
                },
                prepareStorageLeave:function(callback) {
                    return storage.prepareLeave('build', callback);
                },
                activateBuild:function() {
                    return options.ensureBuild().activate(
                        options.buildHost, options.panelInstanceId);
                },
                discardBuild:function() {
                    var build = options.getBuild();
                    if (build) build.suspend();
                },
                prepareBuildLeave:function(callback) {
                    return options.getBuild().prepareLeave(callback);
                },
                ensureStorage:function(next) {
                    if (next !== 'storage' && next !== 'tuning') return false;
                    if (!options.storageReady()) return options.ensureStorage(next);
                    return storage.switchView(next, null, function(success) {
                        if (!success) navigation.storageFailed(next);
                    });
                },
                getStorageView:function() {
                    return options.storageReady() ? storage.getView() : '';
                },
                discardStorage:function() {
                    if (!options.storageReady()) {
                        try { storage.deactivate(); } catch (_) {}
                    }
                },
                switchStorage:function(next) {
                    return options.storageReady()
                        ? storage.switchView(next, null, function(success) {
                            if (!success) navigation.storageFailed(next);
                        }) : options.ensureStorage(next);
                },
                onCommit:function(next, previous) {
                    var build = options.getBuild();
                    if (next === 'build') {
                        options.body.hidden = true;
                        options.buildHost.hidden = false;
                    } else {
                        if (previous === 'build' && build) build.suspend();
                        options.buildHost.hidden = true;
                        options.body.hidden = false;
                    }
                    options.onView(next);
                    if (next === 'build' && build && build.syncViewport) build.syncViewport();
                },
                onAbort:function() {
                    var buildView = options.getView() === 'build';
                    options.buildHost.hidden = !buildView;
                    options.body.hidden = buildView;
                    options.onView(options.getView());
                },
                onDesync:function(next, previous, reason) {
                    if (typeof console !== 'undefined' && console.warn) {
                        console.warn('[InventoryWorkbenchNavigation] view stack reset after controller report', {
                            previous:previous, next:next, reason:reason
                        });
                    }
                    if (options.toast) {
                        options.toast('视图历史已重新同步；返回时将退出当前工作台。');
                    }
                },
                onPending:function() {
                    // 切换进行中再次请求属于本地拦截, 命令式播 illegal; 无音频层时静默。
                    if (typeof BootstrapAudio !== 'undefined' && BootstrapAudio
                            && typeof BootstrapAudio.cue === 'function') BootstrapAudio.cue('illegal');
                    if (options.toast) options.toast('正在切换视图，请稍候。');
                },
                onTimeout:function() {
                    if (options.toast) {
                        options.toast('视图切换超时，已恢复操作；请重试。');
                    }
                },
                onSupersede:function(expected, reported) {
                    if (typeof console !== 'undefined' && console.warn) {
                        console.warn('[InventoryWorkbenchNavigation] controller report superseded pending view', {
                            expected:expected, reported:reported
                        });
                    }
                },
                onError:options.onError || function(target) {
                    if (options.toast) options.toast(target === 'build'
                        ? '角色构筑挂载失败，请重试。'
                        : target === 'storage' ? '收纳视图挂载失败，请重试。'
                            : '工作台视图切换失败，请重试。');
                }
            }
        });
        navigation.mountInitialBuild = function() {
            options.body.hidden = true;
            options.buildHost.hidden = false;
            options.onView('build');
            try {
                var mounted = options.ensureBuild().activate(
                    options.buildHost, options.panelInstanceId);
                return mounted;
            } catch (error) {
                var build = options.getBuild();
                if (build) build.suspend();
                options.body.hidden = false;
                options.buildHost.hidden = true;
                if (options.toast) options.toast('角色构筑挂载失败，请重试。');
                return false;
            }
        };
        return navigation;
    }

    return {Navigation:Navigation, create:create, focusKey:focusKey};
});
