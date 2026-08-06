/**
 * Read-only rich tooltip adapter for Character Build candidate tiles.
 *
 * The adapter owns an inventory-domain mux and a PanelTooltip scope only. It
 * never exposes candidate selection, equip, tune or mutation callbacks.
 */
(function(root, factory) {
    'use strict';
    var runtime = typeof module !== 'undefined' && module.exports
        ? require('../panel-runtime.js')
        : root && root.PanelRuntime;
    var api = factory(runtime, root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildCandidateTooltip = api;
        root.CharacterBuildCandidateTooltip = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(PanelRuntime, global) {
    'use strict';

    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) {
        throw new Error('character-build-candidate-tooltip.js requires PanelRuntime');
    }

    function ownKeys(value, expected) {
        if (!value || typeof value !== 'object'
                || Object.keys(value).length !== expected.length) return false;
        for (var i = 0; i < expected.length; i++) {
            if (!Object.prototype.hasOwnProperty.call(value, expected[i])) return false;
        }
        return true;
    }
    function positive(value) {
        value = Number(value);
        return isFinite(value) && Math.floor(value) === value
            && value >= 1 && value <= 2147483647 ? value : null;
    }
    function sourceOf(candidate) {
        var source = candidate && candidate.raw && candidate.raw.source;
        var slot = source && Number(source.slot);
        var lease = source && String(source.expectedLease || '');
        if (!source || !ownKeys(source, ['containerId', 'slot', 'expectedLease'])
                || source.containerId !== '背包'
                || !isFinite(slot) || Math.floor(slot) !== slot || slot < 0 || slot > 49
                || !/^[A-Za-z0-9._-]{1,128}$/.test(lease)) return null;
        return {containerId:'背包', slot:slot, expectedLease:lease};
    }
    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function noBinding() {
        return {destroy:function() { return false; }, refresh:function() {}};
    }
    function validResponse(data, entry, session) {
        if (!data || data.type !== 'panel_resp' || data.panel !== 'workbench'
                || data.domain !== 'inventory' || data.cmd !== 'tooltip'
                || data.callId !== entry.callId
                || String(data.panelInstanceId || '') !== session.panelInstanceId
                || typeof data.success !== 'boolean') return false;
        if (data.success !== true) {
            return ownKeys(data, [
                'type', 'domain', 'cmd', 'callId', 'success', 'error',
                'panel', 'panelInstanceId'
            ]) && typeof data.error === 'string';
        }
        return ownKeys(data, [
            'success', 'v', 'itemName', 'displayname', 'iconName', 'itemType',
            'descHTML', 'introHTML', 'type', 'domain', 'cmd', 'callId',
            'panel', 'panelInstanceId'
        ]) && data.v === 1 && typeof data.itemName === 'string'
            && typeof data.displayname === 'string'
            && typeof data.iconName === 'string'
            && typeof data.itemType === 'string'
            && typeof data.descHTML === 'string'
            && typeof data.introHTML === 'string';
    }

    function createTooltipMux(options) {
        options = options || {};
        return new PanelRuntime.PanelRequestMux({
            send:options.send,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            callPrefix:'character-candidate-tooltip',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return !!String(session.panelInstanceId || '')
                    && positive(session.sessionGeneration) !== null;
            },
            createMessage:function(context) {
                var source = sourceOf({raw:{source:context.payload.source}});
                if (!source) return null;
                return {
                    type:'panel',
                    panel:'workbench',
                    domain:'inventory',
                    cmd:'tooltip',
                    callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    payload:{
                        v:1,
                        source:source,
                        context:{
                            kind:'character_build_candidate',
                            sessionGeneration:context.session.sessionGeneration
                        }
                    }
                };
            },
            validateResponse:validResponse,
            createSynthetic:function(context) {
                return {
                    type:'panel_resp',
                    panel:'workbench',
                    domain:'inventory',
                    cmd:'tooltip',
                    callId:context.entry.callId,
                    panelInstanceId:context.session.panelInstanceId,
                    success:false,
                    error:context.error,
                    clientSynthetic:true
                };
            }
        });
    }

    function CandidateTooltip(options) {
        options = options || {};
        this._tooltip = options.tooltip || global && global.PanelTooltip || null;
        this._mux = options.mux || createTooltipMux(options);
        this._panelInstanceId = '';
        this._sessionGeneration = null;
        this._epoch = 0;
        this._cache = {};
        this._scope = null;
        this._destroyed = false;
    }
    CandidateTooltip.prototype._disposeScope = function() {
        if (this._scope && this._scope.dispose) this._scope.dispose();
        this._scope = null;
    };
    CandidateTooltip.prototype._newScope = function() {
        this._disposeScope();
        if (this._tooltip && this._tooltip.createScope) {
            this._scope = this._tooltip.createScope(
                'character-build-candidates-' + this._epoch);
        }
    };
    CandidateTooltip.prototype.reset = function(panelInstanceId, sessionGeneration) {
        if (this._destroyed || !panelInstanceId
                || positive(sessionGeneration) === null) return false;
        this._panelInstanceId = String(panelInstanceId);
        this._sessionGeneration = Number(sessionGeneration);
        this._epoch++;
        this._cache = {};
        this._newScope();
        return this._mux.openSession({
            panelInstanceId:this._panelInstanceId,
            sessionGeneration:this._sessionGeneration
        });
    };
    CandidateTooltip.prototype.invalidate = function() {
        if (this._destroyed) return false;
        this._epoch++;
        this._cache = {};
        this._newScope();
        this._mux.closeSession();
        if (this._panelInstanceId && positive(this._sessionGeneration) !== null) {
            this._mux.openSession({
                panelInstanceId:this._panelInstanceId,
                sessionGeneration:this._sessionGeneration
            });
        }
        return true;
    };
    CandidateTooltip.prototype.bind = function(node, candidate, isSuppressed) {
        var source = sourceOf(candidate);
        if (this._destroyed || !node || !source || !this._scope
                || !this._tooltip || !this._scope.bindAsync) return noBinding();
        var self = this;
        var epoch = this._epoch;
        var generation = this._sessionGeneration;
        var candidateKey = String(candidate && candidate.key || '');
        var cacheKey = generation + '\n' + candidateKey + '\n'
            + source.slot + '\n' + source.expectedLease;
        var item = candidate && candidate.presentation || {};
        return this._scope.bindAsync(node, {
            key:cacheKey,
            item:item,
            cache:this._cache,
            isSuppressed:typeof isSuppressed === 'function'
                ? isSuppressed : function() { return false; },
            renderBasic:function(projection) {
                var name = projection && projection.displayName
                    || candidate && candidate.name || '未知物品';
                var type = projection && (projection.majorType || projection.use
                    || projection.itemKind) || candidate && candidate.type || '背包候选';
                return '<div class="kshop-tt-header"><b>' + escapeHtml(name)
                    + '</b></div><div class="kshop-tt-divider"></div>'
                    + '<span class="kshop-tt-dim">类型</span> ' + escapeHtml(type)
                    + '<br><span class="kshop-tt-dim">用途</span> 角色构筑候选说明'
                    + '<div class="kshop-tt-loading">加载中…</div>';
            },
            renderRich:function(projection, data) {
                var iconKey = data.iconName
                    || projection && projection.icon || '';
                return self._tooltip.buildItemRichHtml({
                    iconHtml:self._tooltip.dynamicIconHtml(iconKey),
                    iconUrl:self._tooltip.staticIconUrl(iconKey),
                    introHTML:data.introHTML || '',
                    descHTML:data.descHTML || '',
                    rootClass:'kshop-tt-rich-context character-build-candidate-tt-context',
                    layoutType:self._tooltip.inferLayoutType(
                        data.itemType || projection && (
                            projection.majorType || projection.use))
                });
            },
            renderFailure:function(projection) {
                var name = projection && projection.displayName
                    || candidate && candidate.name || '未知物品';
                return '<div class="kshop-tt-header"><b>' + escapeHtml(name)
                    + '</b></div><div class="kshop-tt-divider"></div>'
                    + '<div class="kshop-tt-loading">完整说明暂时读取失败；移开后重新悬停即可重试。</div>';
            },
            fetch:function(_, callback) {
                var issuedEpoch = epoch;
                self._mux.request('tooltip', {source:source}, {
                    kind:'candidate-tooltip:' + cacheKey,
                    singleFlight:true
                }, function(response) {
                    if (!self._destroyed && self._epoch === issuedEpoch
                            && self._sessionGeneration === generation) {
                        callback(response);
                    }
                });
            }
        });
    };
    CandidateTooltip.prototype.suspend = function() {
        if (this._destroyed) return false;
        this._epoch++;
        this._disposeScope();
        this._cache = {};
        this._panelInstanceId = '';
        this._sessionGeneration = null;
        this._mux.closeSession();
        return true;
    };
    CandidateTooltip.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._disposeScope();
        this._cache = {};
        this._panelInstanceId = '';
        this._sessionGeneration = null;
        this._mux.destroy();
        return true;
    };
    CandidateTooltip.prototype.debugState = function() {
        return {
            active:!!this._scope,
            panelInstanceId:this._panelInstanceId,
            sessionGeneration:this._sessionGeneration,
            epoch:this._epoch,
            cacheCount:Object.keys(this._cache).length,
            mux:this._mux.debugState ? this._mux.debugState() : null
        };
    };

    return {
        CandidateTooltip:CandidateTooltip
    };
});
