/** 暂存协议复用物品使用控制器的单一请求通道、待决命令与恢复状态。 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildStashTransport = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';
    function install(Controller) {
        Controller.prototype._acceptInbox = function(response) {
            var hasAuthority = response && Object.prototype.hasOwnProperty.call(
                response, 'rewardAuthority');
            var authority = hasAuthority ? response.rewardAuthority : undefined;
            var accepted = response && response.success === true
                && response.inboxSummary
                && typeof response.rewardReady === 'boolean'
                && hasAuthority
                && (authority === null || authority && typeof authority === 'object'
                    && !Array.isArray(authority));
            if (!accepted || response.rewardReady === false && authority !== null) {
                return false;
            }
            this._inbox = {
                summary:response.inboxSummary,
                authority:authority || null
            };
            this._onInbox(this._inbox, response);
            return true;
        };
        Controller.prototype.refreshInbox = function(callback) {
            if (this._destroyed || this._state === 'closed') return null;
            var self = this;
            return this._mux.request('inboxSnapshot', this._base(), {
                kind:'inbox_snapshot', latestWins:true
            }, function(response) {
                var accepted = self._acceptInbox(response);
                if (callback) callback(response, !!accepted);
            });
        };
        Controller.prototype.requestStashPage = function(offset, callback, filterSpec) {
            if (this._destroyed || this._state === 'closed') return null;
            if (filterSpec !== undefined && (!filterSpec
                    || typeof filterSpec !== 'object' || Array.isArray(filterSpec))) return null;
            var payload = this._base(); payload.v = 2; payload.offset = offset;
            if (filterSpec !== undefined) payload.filterSpec = filterSpec;
            return this._mux.request('stashPage', payload,
                {kind:'stash_page', latestWins:true}, function(response) {
                    if (callback) callback(response && response.success === true
                        ? response.data : null, response);
                });
        };
        Controller.prototype.requestStashTooltip = function(storeId, entry, callback) {
            if (this._destroyed || this._state === 'closed') return null;
            var payload = this._base(); payload.v = 2;
            payload.storeId = storeId; payload.entryId = entry.entryId; payload.revision = entry.revision;
            return this._mux.request('stashTooltip', payload, {kind:'stash_tooltip', latestWins:true}, function(response) {
                callback(response && response.success === true ? response.data : null);
            });
        };
        Controller.prototype.resumeStash = function(operationId, callback) {
            if (this._destroyed || this._state !== 'idle') return null;
            var payload = this._base(); payload.v = 2; payload.operationId = operationId;
            return this._mux.request('stashResume', payload, {kind:'stash_resume', singleFlight:true}, callback);
        };
        Controller.prototype.openLegacyInbox = function(callback) {
            var self = this;
            return this._mux.request('legacyInboxOpen', this._base(), {kind:'legacy_inbox_open', singleFlight:true}, function(response) {
                var accepted = self._acceptInbox(response);
                if (callback) callback(response, !!accepted);
            });
        };
        Controller.prototype.invokeStash = function(command, fields, callback, candidate) {
            if (this._destroyed || this._state !== 'idle') return null;
            var payload = this._base(); payload.v = 2;
            Object.keys(fields || {}).forEach(function(key) { if (fields[key] !== undefined) payload[key] = fields[key]; });
            payload.operationId = 'stash.' + this._operationNonce + '.' + (++this._operationSequence).toString(36);
            this._pending = {operationId:payload.operationId, command:command === 'stashOpen' ? 'open'
                : command === 'stashOpenMany' ? 'openMany' : command, wireCommand:command,
                storeId:payload.storeId || '', expectedRevision:payload.expectedRevision || 0,
                candidate:candidate, stashCallback:callback, v:2};
            this._state = 'write_pending'; this._emit('write_issued');
            var self = this;
            return this._mux.request(command, payload, {kind:'write', singleFlight:true, write:true}, function(response) { self._settleWrite(response); });
        };
        Controller.prototype._finishStash = function(response, data, committed, pending) {
            this._pending = null; this._state = 'idle';
            this._emit(committed ? 'write_committed' : 'write_rejected');
            this.refreshInbox();
            var settled = committed ? data : response || {success:false, error:'malformed_response'};
            if (pending.stashCallback) pending.stashCallback(settled, committed);
            else this._onSettled(settled, committed, pending);
        };
        Controller.prototype._invokeStashPack = function(candidate, action, source) {
            var summary = this._inbox && this._inbox.summary;
            if (!summary) {
                var retrySelf = this;
                return this.refreshInbox(function(_, ok) { if (ok) retrySelf.invoke(candidate); });
            }
            return this.invokeStash(action.command === 'open' ? 'stashOpen' : 'stashOpenMany', {
                source:source, count:action.count,
                storeId:summary.v === 2 ? summary.storeId : '',
                expectedRevision:summary.v === 2 ? summary.authorityRevision : 0
            }, null, candidate);
        };
        Controller.prototype._reconcileStash = function() {
            var pending = this._pending;
            var payload = this._base();
            payload.v = 2;
            payload.operationId = pending.operationId;
            payload.storeId = pending.storeId;
            payload.expectedRevision = pending.expectedRevision;
            this._state = 'query_pending';
            this._emit('query_issued');
            var self = this;
            return this._mux.request('stashQuery', payload, {
                kind:'query', singleFlight:true
            }, function(response) {
                if (!self._pending || self._pending.operationId !== pending.operationId) return;
                var result = response && response.success === true && response.data;
                if (!result || ['committed','not_committed','stale'].indexOf(result.state) < 0) {
                    self._state = 'needs_reconcile'; self._emit('query_failed'); return;
                }
                self._finishStash({success:false, error:result.state === 'stale' ? 'stale_stash' : 'not_committed'},
                    result.result, result.state === 'committed', pending);
            });
        };
    }
    return {install:install};
});
