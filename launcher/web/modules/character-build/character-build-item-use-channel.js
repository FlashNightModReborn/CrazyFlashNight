/** Character-build integration for explicit backpack use and RewardInbox entry. */
(function(root, factory) {
    'use strict';
    var cooldown = typeof module !== 'undefined' && module.exports
        ? require('./character-build-cooldown-channel.js')
        : root && root.CharacterBuildCooldownChannel;
    var api = factory(cooldown);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildItemUseChannel = api;
})(typeof window !== 'undefined' ? window : globalThis, function(Cooldown) {
    'use strict';

    function finiteWhole(value) {
        value = Number(value);
        return isFinite(value) && value >= 0 && Math.floor(value) === value
            ? value : null;
    }
    function resultMessage(response, receipt, pending) {
        response = response || {};
        receipt = receipt || {};
        pending = pending || {};
        var candidate = pending.candidate || {};
        var itemName = String(candidate.name || '').trim();
        var subject = itemName ? '「' + itemName + '」' : '所选物品';
        if (pending.command === 'open') {
            var summary = response.inboxSummary || receipt.inboxSummary || {};
            var inboxRemaining = finiteWhole(summary.remainingCount);
            return '已打开' + subject + '；奖励已转入待领取'
                + (inboxRemaining !== null ? '（当前 ' + inboxRemaining + ' 件）' : '') + '。';
        }
        var lane = finiteWhole(response.selectedLane != null
            ? response.selectedLane : receipt.selectedLane);
        var remaining = finiteWhole(response.remaining != null
            ? response.remaining : receipt.remaining);
        return '已服用' + subject
            + (lane !== null ? '；通道 ' + String(lane + 1) + ' 进入冷却' : '')
            + (remaining !== null ? '（背包剩余 ' + remaining + '）' : '') + '。';
    }
    function resumeSelection(candidate, view) {
        var raw = candidate && candidate.raw || {};
        var action = candidate && candidate.useAction || raw.useAction || {};
        var source = raw.useAction && raw.useAction.source || {};
        var item = raw.item || candidate && candidate.presentation || {};
        var physicalSlot = finiteWhole(raw.physicalSlot != null
            ? raw.physicalSlot : candidate && candidate.physicalSlot);
        var itemName = String(source.itemName || item.name || '').trim();
        if (String(action.command || '') !== 'consume'
                || physicalSlot === null || !itemName) return null;
        return {
            physicalSlot:physicalSlot,
            itemName:itemName,
            focusMode:view && typeof view.captureItemUseFocus === 'function'
                ? view.captureItemUseFocus() : '',
            requestKey:''
        };
    }
    function readyCount(lanes) {
        if (!Array.isArray(lanes) || lanes.length !== 4) return -1;
        var count = 0;
        for (var lane = 0; lane < lanes.length; lane++) {
            if (!lanes[lane] || typeof lanes[lane].ready !== 'boolean') return -1;
            if (lanes[lane].ready) count++;
        }
        return count;
    }
    function blockedByFullCooldown(candidate) {
        var raw = candidate && candidate.raw || {};
        var action = candidate && candidate.useAction || raw.useAction || {};
        return String(action.command || '') === 'consume'
            && String(raw.useBlockedReason || '') === 'no_available_lane';
    }

    function install(controller) {
        if (!controller) throw new Error('CharacterBuildItemUseChannel requires a controller');

        controller._itemUseStateChanged = function(_, reason) {
            this._stateChanged(this._session.getState(),
                'item_use_' + String(reason || 'state'),
                this._session.debugState());
        };
        controller._itemUseInboxChanged = function(inbox) {
            this._rewardAuthority = inbox && inbox.authority || null;
            if (this._view) this._view.setInboxSummary(inbox && inbox.summary);
        };
        controller._itemUseCooldownChanged = function(lanes) {
            var previousReady = readyCount(this._itemUseCooldownLanes);
            if (!Cooldown.render(this, lanes)) return false;
            if (previousReady === 0
                    && readyCount(this._itemUseCooldownLanes) > 0) {
                this._refreshItemUseCandidatesForReadyLane();
            }
            return true;
        };
        controller._refreshItemUseCandidatesForReadyLane = function() {
            if (!this._view || !this._session || !this._itemUse
                    || this._session.getState() !== 'idle'
                    || this._itemUse.debugState().state !== 'idle') return false;
            var viewState = this._view.debugState
                ? this._view.debugState() : null;
            if (!viewState || viewState.candidateScope !== 'backpack'
                    || viewState.selectedSlotKey) return false;
            var candidates = this._view.getCandidates
                ? this._view.getCandidates() : [];
            var needsRefresh = false;
            for (var index = 0; index < candidates.length; index++) {
                if (blockedByFullCooldown(candidates[index])) {
                    needsRefresh = true;
                    break;
                }
            }
            if (!needsRefresh) return false;
            var resume = blockedByFullCooldown(this._selectedCandidate)
                ? resumeSelection(this._selectedCandidate, this._view) : null;
            this._itemUseResumeSelection = resume;
            this._candidateCache = null;
            var refreshed = !!(this._view.showBackpackOverview
                && this._view.showBackpackOverview());
            if (!refreshed) this._itemUseResumeSelection = null;
            return refreshed;
        };
        controller._itemUseCooldownFromSnapshot = function(snapshot) {
            return Cooldown.fromSnapshot(this, snapshot);
        };
        controller._noteItemUseCooldownLane = function(lane) {
            return Cooldown.note(this, lane);
        };
        controller._startItemUseCooldownPolling = function() {
            return Cooldown.start(this);
        };
        controller._stopItemUseCooldownPolling = function() {
            return Cooldown.stop(this);
        };
        controller._bindItemUse = function() {
            var generation = this._session.getSessionGeneration();
            if (!this._panelInstanceId || !generation) return false;
            var key = this._panelInstanceId + ':' + String(generation);
            var fresh = key !== this._itemUseBindKey;
            if (!this._itemUse.bind(this._panelInstanceId, generation)) return false;
            this._itemUseBindKey = key;
            if (this._view) this._view.setItemUseState(
                this._itemUse.debugState().state);
            if (fresh) {
                this._itemUse.refreshInbox();
                this._startItemUseCooldownPolling();
            }
            return true;
        };
        controller._useCandidate = function(candidate) {
            if (!candidate || this._session.getState() !== 'idle') return false;
            var resume = resumeSelection(candidate, this._view);
            this._itemUseResumeSelection = resume;
            var callId = this._itemUse.invoke(candidate);
            if (!callId) this._itemUseResumeSelection = null;
            return !!callId;
        };
        controller._openRewardInbox = function() {
            var self = this;
            function transition() {
                var inbox = self._itemUse.inbox();
                var remaining = Number(inbox && inbox.summary
                    && inbox.summary.remainingCount) || 0;
                if (remaining < 1) {
                    if (self._ports.toast) self._ports.toast('当前没有待领取物品。');
                    return false;
                }
                if (!inbox.authority) {
                    if (self._ports.toast) {
                        self._ports.toast('待领取界面暂时不可用，请稍后重试。');
                    }
                    return false;
                }
                self._rewardAuthority = inbox.authority;
                return self._ports.requestClose
                    ? self._ports.requestClose('navigate_reward_inbox') : false;
            }
            var inbox = this._itemUse.inbox();
            if (inbox && Number(inbox.summary && inbox.summary.remainingCount) > 0
                    && inbox.authority) {
                return transition();
            }
            return !!this._itemUse.refreshInbox(function(_, accepted) {
                if (accepted) transition();
                else if (self._ports.toast) {
                    self._ports.toast('待领取物品同步失败，请重试。');
                }
            });
        };
        controller._itemUseSettled = function(response, committed, pending) {
            var self = this;
            if (!committed) {
                this._itemUseResumeSelection = null;
                if (this._ports.toast) this._ports.toast(
                    response && response.error === 'not_committed'
                        ? '刚才的使用未执行，可重新点击。'
                        : response && response.error === 'invalid_source'
                            ? '物品来源已变化，请刷新后重试。'
                            : '物品使用失败，请重试。');
                return;
            }
            var receipt = response && response.receipt || response || {};
            if (!pending || pending.command !== 'consume') {
                this._itemUseResumeSelection = null;
            }
            var selectedLane = finiteWhole(response && response.selectedLane != null
                ? response.selectedLane : receipt.selectedLane);
            if (pending && pending.command === 'consume' && selectedLane !== null) {
                this._noteItemUseCooldownLane(selectedLane);
                this._startItemUseCooldownPolling();
            }
            if (response && response.inboxSummary) {
                this._itemUseInboxChanged({
                    summary:response.inboxSummary,
                    authority:response.rewardAuthority || this._rewardAuthority
                });
            }
            if (response && response.rewardAuthority) {
                this._rewardAuthority = response.rewardAuthority;
            }
            this._candidateCache = null;
            var transitionToInbox = pending && pending.command === 'open'
                && (response.rewardReady === true || receipt.rewardReady === true);
            var refreshCallId = this._session.refreshSnapshot(function(snapshot, accepted) {
                if (accepted && self._view) self._applySnapshot(snapshot.payload, false);
                else self._itemUseResumeSelection = null;
                var message = resultMessage(response, receipt, pending);
                if (self._view && self._view.showItemUseResult) {
                    self._view.showItemUseResult(message);
                }
                if (transitionToInbox) self._openRewardInbox();
                else if (self._ports.toast) {
                    self._ports.toast(message);
                }
            });
            if (!refreshCallId) {
                this._itemUseResumeSelection = null;
                var fallbackMessage = resultMessage(response, receipt, pending);
                if (this._view && this._view.showItemUseResult) {
                    this._view.showItemUseResult(fallbackMessage);
                }
                if (transitionToInbox) this._openRewardInbox();
                else if (this._ports.toast) {
                    this._ports.toast(fallbackMessage
                        + ' 背包将在下次同步时刷新。');
                }
            }
        };
        return controller;
    }

    return {install:install, resultMessage:resultMessage};
});
