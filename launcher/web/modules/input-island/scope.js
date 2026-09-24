(function () {
    'use strict';
    var gate = window.C1IslandGate;
    Panels.init();
    var readinessSerial = 0, pendingRestore = null;
    function watchReadiness() {
        var serial = ++readinessSerial, generation = gate.generation, instance = gate.instance, polls = 0;
        if (typeof setTimeout !== 'function') return;
        (function ready() {
            if (serial !== readinessSerial || generation !== gate.generation || instance !== gate.instance || !Panels.isOpen()) return;
            if (PlasticSurgeryPanel.debugState().phase === 'editing') {
                if (pendingRestore && !PlasticSurgeryPanel.restoreInputDraft(pendingRestore)) { receipt('prepare_failed'); return; }
                pendingRestore = null;
                var round = gate.round;
                requestAnimationFrame(function () { requestAnimationFrame(function () {
                    if (serial === readinessSerial && generation === gate.generation && instance === gate.instance
                        && round === gate.round && Panels.isOpen() && PlasticSurgeryPanel.debugState().phase === 'editing') receipt('page_ready');
                }); });
                return;
            }
            if (++polls < 500) setTimeout(ready, 20);
            else receipt('prepare_failed');
        })();
    }
    function receipt(kind, extra) {
        Bridge.send(Object.assign({type:'c1_scope', kind:kind, instance:gate.instance,
            generation:gate.generation, round:gate.round, gateClosed:!gate.granted}, extra || {}));
    }
    function closeGate() {
        gate.granted = false; gate.prepared = false; gate.pointerGesture = 0; document.body.inert = true;
        if (gate.cancelEvents) gate.cancelEvents();
        if (window.PlasticSurgeryPanel && PlasticSurgeryPanel.cancelInputComposition) PlasticSurgeryPanel.cancelInputComposition();
        var focused = document.activeElement;
        if (focused && typeof focused.blur === 'function') focused.blur();
    }
    Bridge.on('c1_control', function (message) {
        if (!message || typeof message.instance !== 'string' || !message.instance || !Number.isSafeInteger(message.generation)) return;
        if (gate.round && (!message.round || message.round.session !== gate.round.session || message.round.coverage !== gate.round.coverage
            || message.round.epoch < gate.round.epoch || message.round.ticket < gate.round.ticket || message.round.geometry < gate.round.geometry)) return;
        if (message.op === 'prepare') {
            if (gate.instance && (message.generation < gate.generation || (message.generation === gate.generation && Panels.isOpen()))) return;
            closeGate(); Panels.close(); gate.instance = message.instance;
            gate.generation = message.generation; gate.round = message.round;
            Panels.open('surgery', {panelInstanceId:gate.instance, source:'world_plastic_surgery', mode:'runtime'});
            gate.prepared = true; receipt('preparing');
            pendingRestore = message.restoreDraft || null; watchReadiness();
            return;
        }
        // The cold page may acknowledge cancellation before opening any panel.
        if (!gate.instance && message.op === 'cancel') {
            gate.instance = message.instance; gate.generation = message.generation; gate.round = message.round;
        }
        if (message.instance !== gate.instance || message.generation !== gate.generation) return;
        var old = gate.round, next = message.round;
        if (!old || !next || next.session !== old.session || next.coverage !== old.coverage
            || next.epoch < old.epoch || next.ticket < old.ticket || next.geometry < old.geometry) return;
        if (message.op === 'freeze_view') {
            closeGate(); readinessSerial++;
            return; // display-only hold; never an ACK or a new input grant
        }
        if (message.op === 'arm') {
            if (next.ticket <= old.ticket || (Panels.isOpen() && PlasticSurgeryPanel.debugState().phase !== 'editing')) return;
            closeGate(); gate.round = next; gate.prepared = true;
            receipt('prepared', {prefix:message.prefix}); return;
        }
        if (message.op === 'cancel') {
            closeGate(); gate.round = message.round;
            // Input suspension (e.g. foreground loss) preserves the local draft.
            // Whole-page retirement is a distinct explicit operation.
            if (message.retire !== true) { receipt('suspended'); watchReadiness(); return; }
            readinessSerial++; pendingRestore = null;
            var retainedDraft = PlasticSurgeryPanel.debugState().draft;
            Panels.close();
            var generation = gate.generation, cancelledRound = gate.round;
            // These receipts cover this exact page's production cleanup only.
            // The Host must also fence queued messages/retire the controller.
            Promise.resolve().then(function () {
                if (generation !== gate.generation || gate.round !== cancelledRound || gate.granted || Panels.isOpen() || PlasticSurgeryPanel.debugState().phase !== 'closed') return;
                receipt('cancelled', {pendingPanel:false, draft:retainedDraft || null});
            });
        } else if (message.op === 'grant' && gate.sameRound(message.round, gate.round)) {
            if (!gate.prepared || PlasticSurgeryPanel.debugState().phase !== 'editing') return;
            gate.prepared = false; gate.granted = true; document.body.inert = false; receipt('granted');
        }
    });
    receipt('boot');
})();
