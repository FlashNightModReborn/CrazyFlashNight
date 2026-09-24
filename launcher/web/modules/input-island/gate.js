/* Dedicated cold entry; no normal app/bootstrap or business mock is loaded. */
(function () {
    'use strict';
    var gate = { granted:false, instance:'', generation:0, round:null, pointerGesture:0, prepared:false };
    var send = Bridge.send;
    window.C1IslandGate = gate;
    gate.events = Object.create(null);
    gate.sameRound = function(a,b) {
        return !!a && !!b && ['session','coverage','epoch','ticket','geometry'].every(function(key) { return a[key] === b[key]; });
    };
    var keys = Object.create(null), compositionRound = null, activation = null;
    gate.cancelEvents = function() { keys = Object.create(null); compositionRound = null; activation = null; };
    gate.activateKey = function(key, gesture, round) {
        if (!gate.granted || !activation || activation.key !== key || !gate.sameRound(activation.round, round)
            || activation.element !== document.activeElement || !gate.sameRound(gate.round, round)) return false;
        var element = activation.element; activation = null; gate.pointerGesture = gesture;
        if (key === 27) return PlasticSurgeryPanel.requestClose();
        if (element && element.tagName === 'BUTTON') { element.click(); return true; }
        return false;
    };
    Bridge.send = function (message) {
        if (message && message.type === 'panel') {
            if (message.panel !== 'surgery' || !gate.instance || message.panelInstanceId !== gate.instance) return false;
            // Snapshot/query prepare presentation; they do not grant input.
            if (message.cmd !== 'snapshot' && message.cmd !== 'query' && !gate.granted) return false;
            message = Object.assign({}, message, { inputRound:gate.round, inputGeneration:gate.generation, inputGesture:gate.pointerGesture });
        }
        return send(message);
    };
    ['pointerdown','pointerup','mousedown','mouseup','click','dblclick','contextmenu','wheel',
     'keydown','keyup','beforeinput','input','compositionstart','compositionupdate','compositionend'].forEach(function (type) {
        window.addEventListener(type, function (event) {
            gate.events[type] = (gate.events[type] || 0) + 1;
            var blocked = !gate.granted;
            if (!blocked && type === 'keydown') {
                if (event.repeat && !keys[event.code]) blocked = true;
                else {
                    keys[event.code] = true;
                    var logical = event.key === 'Escape' ? 27 : event.key === 'Enter' ? 13 : event.key === ' ' ? 32 : 0;
                    if (logical && !event.isComposing && event.keyCode !== 229 && !compositionRound) {
                        activation = {key:logical, element:document.activeElement, round:gate.round};
                        if (logical === 27 || (document.activeElement && document.activeElement.tagName === 'BUTTON')) blocked = true;
                    }
                }
            }
            if (!blocked && type === 'keyup') {
                if (!keys[event.code]) blocked = true;
                delete keys[event.code];
                if (activation && (activation.key === 27 || (activation.element && activation.element.tagName === 'BUTTON'))) blocked = true;
            }
            if (!blocked && type === 'compositionstart') compositionRound = gate.round;
            if (!blocked && (type === 'compositionend' || type === 'compositionupdate')) {
                if (!gate.sameRound(compositionRound, gate.round)) blocked = true;
                if (type === 'compositionend') compositionRound = null;
            }
            if (!blocked && type === 'beforeinput' && event.isComposing && !gate.sameRound(compositionRound, gate.round)) blocked = true;
            if (blocked) { event.preventDefault(); event.stopImmediatePropagation(); }
        }, { capture:true, passive:false });
    });
})();
