/** Shared, local-only confirmation preference and presentation projection for Equipment Tuning. */
(function(root, factory) {
    'use strict';
    var config = typeof module !== 'undefined' && module.exports
        ? require('./inventory-workbench-config.js')
        : root && root.InventoryWorkbenchConfig;
    var api = factory(config, root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EquipmentTuningConfirmation = api;
})(typeof window !== 'undefined' ? window : globalThis,
function(InventoryWorkbenchConfig, global) {
    'use strict';

    if (!InventoryWorkbenchConfig || !InventoryWorkbenchConfig.ConfirmationPreference) {
        throw new Error('EquipmentTuningConfirmation requires InventoryWorkbenchConfig');
    }

    var BOUNDARY_TEXT = '批量、连锁与卸下全部始终需要确认';
    var CHOICES = [
        {value:'safe', label:'逐次确认', ariaLabel:'逐次确认：每次操作都先查看预览再提交'},
        {value:'fast', label:'单件快捷', ariaLabel:'单件快捷：符合安全边界的单件配件操作可在预览后自动提交'}
    ];

    function normalize(mode) {
        return InventoryWorkbenchConfig.normalizeConfirmationMode(mode);
    }

    function disabledReason(state) {
        state = state || {};
        if (state.interaction && state.interaction.confirmation === false) {
            return String(state.interaction.reason || '当前调制状态不允许切换确认方式。');
        }
        if (state.detaching) return '正在结束调制会话，完成后才能切换确认方式。';
        if (state.loadoutBarrier) {
            return '正在核对调制结果，完成后才能切换确认方式。';
        }
        if (state.refreshRetryPending) return '正在重试同步背包，完成后才能切换确认方式。';
        if (state.refreshRetryRequired) return '背包同步失败，请先完成重试。';
        if (state.needsReconcile) {
            return '正在核对调制结果，完成后才能切换确认方式。';
        }
        if (state.busy || state.inventoryWritePending) {
            return '调制写入尚未完成，完成后才能切换确认方式。';
        }
        if (state.readPending || state.conversionLoading
                || state.mux && Number(state.mux.pendingCount) > 0) {
            return '正在读取调制状态，完成后才能切换确认方式。';
        }
        return '';
    }

    function project(mode, state) {
        var reason = disabledReason(state);
        return {
            value:normalize(mode),
            disabled:!!reason,
            reason:reason,
            boundaryText:BOUNDARY_TEXT
        };
    }

    function helpDetail() {
        return '确认方式\n'
            + '• “逐次确认”：所有操作都停在权威预览，确认材料与前后结果后再提交。\n'
            + '• “单件快捷”：只有无连带变化的单件安装、替换或卸下会在权威预览后自动提交。\n'
            + '• ' + BOUNDARY_TEXT + '；强化、交换与进阶也始终停在预览等待确认。';
    }

    function helpSpec() {
        return {
            kind:'equipment-tuning-help',
            title:'装备调制帮助',
            message:'当前装备调制\n• 左侧槽位切换当前调制装备；右侧按强化度、进阶与配件查看权威预览。\n• 打开或关闭本帮助只解释操作，不会解锁配件能力，也不会改变确认方式。',
            detail:helpDetail()
                + '\n\n浏览\n• “调制说明”随当前操作和聚焦候选更新；紧凑模式只改变候选密度。',
            actions:[{id:'close', label:'知道了', primary:true, audioCue:'confirm'}]
        };
    }

    function defaultStorage() {
        try { return global && global.localStorage || null; }
        catch (_) { return null; }
    }

    function ConfirmationPort(options) {
        options = options || {};
        this._preference = options.preference
            || new InventoryWorkbenchConfig.ConfirmationPreference(
                options.storage === undefined ? defaultStorage() : options.storage,
                options.key);
        this._mode = this._preference.read();
        this._listeners = [];
    }

    ConfirmationPort.prototype._notify = function(origin) {
        var snapshot = this._listeners.slice();
        for (var i = 0; i < snapshot.length; i++) {
            snapshot[i](this._mode, {origin:String(origin || 'set')});
        }
    };

    ConfirmationPort.prototype.read = function() {
        var stored = this._preference.read();
        if (stored !== this._mode) {
            this._mode = stored;
            this._notify('storage');
        }
        return this._mode;
    };

    ConfirmationPort.prototype.set = function(mode) {
        var next = this._preference.write(normalize(mode));
        if (next !== this._mode) {
            this._mode = next;
            this._notify('set');
        }
        return this._mode;
    };

    ConfirmationPort.prototype.subscribe = function(listener) {
        if (typeof listener !== 'function') return function() {};
        var self = this;
        var mode = this.read();
        this._listeners.push(listener);
        listener(mode, {origin:'subscribe'});
        var active = true;
        return function() {
            if (!active) return false;
            active = false;
            var index = self._listeners.indexOf(listener);
            if (index >= 0) self._listeners.splice(index, 1);
            return index >= 0;
        };
    };

    ConfirmationPort.prototype.debugState = function() {
        return {mode:this._mode, subscriberCount:this._listeners.length};
    };

    return {
        BOUNDARY_TEXT:BOUNDARY_TEXT,
        CHOICES:CHOICES,
        disabledReason:disabledReason,
        project:project,
        helpDetail:helpDetail,
        helpSpec:helpSpec,
        ConfirmationPort:ConfirmationPort,
        shared:new ConfirmationPort()
    };
});
