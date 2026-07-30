/** Stable, in-place projection for Equipment Tuning draft and preview controls. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.EquipmentTuningDecisionPresenter = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function setIntrinsicDisabled(node, disabled) {
        if (!node || !node.setAttribute) return node;
        node.setAttribute(
            'data-tuning-intrinsic-disabled',
            disabled ? 'true' : 'false'
        );
        return node;
    }

    function install(TuningView, Model) {
        if (!TuningView || !TuningView.prototype) {
            throw new Error('EquipmentTuningDecisionPresenter requires a view constructor.');
        }
        if (!Model) {
            throw new Error('EquipmentTuningDecisionPresenter requires EquipmentTuningModel.');
        }

        TuningView.prototype._syncEnhancementDraft = function(level) {
            if (!this._root || this._operation !== 'enhance' || !this._snapshot) return false;
            var enhance = this._snapshot.enhance || {};
            var current = Number(enhance.currentLevel || 0);
            var max = Math.min(
                Model.enhancementAvailableMax(this._snapshot),
                Model.enhancementHardMax(this._snapshot)
            );
            level = Math.max(current + 1, Math.min(max, Math.floor(Number(level))));
            if (!isFinite(level) || current >= max) return false;
            var active = this._root.ownerDocument.activeElement;
            var input = this._root.querySelector('.equipment-tuning-level-input');
            var range = this._root.querySelector('.equipment-tuning-level-slider');
            if (input && active !== input) input.value = String(level);
            if (range && active !== range) range.value = String(level);
            var heading = this._root.querySelector('.equipment-tuning-level-heading b');
            if (heading) heading.textContent = '+' + level;
            var readout = this._root.querySelector('.equipment-tuning-reactor-readout b');
            if (readout) readout.innerHTML = '+' + current + '<i>→</i>+' + level;
            var minus = this._root.querySelector('[data-enhance-step="minus"]');
            var plus = this._root.querySelector('[data-enhance-step="plus"]');
            var cap = this._root.querySelector('.equipment-tuning-level-cap');
            if (minus) setIntrinsicDisabled(minus, level <= current + 1);
            if (plus) setIntrinsicDisabled(plus, level >= max);
            if (cap) setIntrinsicDisabled(cap, level >= max);
            var marks = this._root.querySelectorAll('.equipment-tuning-level-mark');
            for (var i = 0; i < marks.length; i++) {
                marks[i].classList.toggle(
                    'active',
                    Number(marks[i].getAttribute('data-enhance-level')) === level
                );
            }
            return true;
        };

        TuningView.prototype._syncEnhancementPreview = function() {
            if (!this._root || this._operation !== 'enhance' || !this._snapshot) return false;
            var balance = this._root.querySelector('.equipment-tuning-reactor-balance');
            if (!balance) return false;
            var ownedStones = Model.materialCount(this._snapshot.materials, '强化石');
            var stoneDelta = this._preview && this._preview.operation === 'enhance'
                ? Model.materialDeltaFor(this._preview.materials, '强化石') : null;
            balance.innerHTML = '<span>持有 <strong>'
                + Model.exactQuantity(ownedStones) + '</strong></span>';
            if (stoneDelta) {
                balance.innerHTML += '<em class="equipment-tuning-reactor-spend">消耗 <b>'
                    + Model.exactQuantity(Math.max(0, -Number(stoneDelta.delta || 0)))
                    + '</b> · 强化后剩余 <b>'
                    + Model.exactQuantity(stoneDelta.after) + '</b></em>';
            } else if (this._readPending && this._previewPendingOperation === 'enhance') {
                balance.innerHTML += '<em class="equipment-tuning-reactor-pending">'
                    + '正在计算消耗…</em>';
            }
            return true;
        };

        TuningView.prototype._selectEmptyModSlot = function(slotIndex) {
            var equipment = this._snapshot && this._snapshot.equipment;
            var installed = equipment && equipment.mods instanceof Array
                ? equipment.mods : [];
            var capacity =
                Model.modSlotCapacityProjection(equipment, installed.length);
            slotIndex = Number(slotIndex);
            if (capacity.state !== 'known'
                    || Math.floor(slotIndex) !== slotIndex
                    || slotIndex < installed.length
                    || slotIndex >= capacity.value
                    || !Model.tuningSourceSupports(this._source, 'install_mod')
                    || !this._allowInteraction('slot')
                    || !this._allowInteraction('tabs')) return false;
            var previousReplaceCandidateKey = this._replaceCandidateKey;
            var previousReplaceCandidateName = this._replaceCandidateName;
            var previousStatus = this._status;
            this._replaceCandidateKey = '';
            this._replaceCandidateName = '';
            this._status = '插件槽 ' + (slotIndex + 1)
                + ' 为空，请选择要安装的配件';
            if (!this.setOperation('install_mod')) {
                this._replaceCandidateKey = previousReplaceCandidateKey;
                this._replaceCandidateName = previousReplaceCandidateName;
                this._status = previousStatus;
                return false;
            }
            var root = this._root
                && this._root.querySelector('.equipment-tuning-view');
            var target = root && root.querySelector(
                '.equipment-tuning-candidate.available:not(:disabled)'
            );
            if (!target && root) {
                target = root.querySelector(
                    '.equipment-tuning-installed-empty[data-mod-slot-index="'
                        + slotIndex + '"]'
                );
            }
            if (target) {
                try { target.focus(); }
                catch (_) {}
            }
            return true;
        };

        return TuningView;
    }

    return {install:install};
});
