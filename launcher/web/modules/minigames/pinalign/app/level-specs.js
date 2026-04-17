(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.PinAlignLevels = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var SPECS = {
        "mvp-3pin-v1": {
            id: "mvp-3pin-v1",
            rows: 8,
            cols: 8,
            colorCount: 5,
            pinCount: 3,
            pinTargetHeightMin: 2,
            pinTargetHeightMax: 3,
            pins: [
                { id: "pin-a", centerCol: 1, targetHeight: null },
                { id: "pin-b", centerCol: 3, targetHeight: null },
                { id: "pin-c", centerCol: 6, targetHeight: null }
            ],
            lane: {
                weightsByDistance: [2, 1, 0],
                threshold: 4,
                margin: 0
            },
            alert: {
                initial: 16
            },
            obstacles: {
                debris: 3,
                clip: 3
            },
            clamp: {
                initialCharge: 44,
                maxCharge: 100,
                cost: 100,
                chargePerEvent: 4,
                chargePerSignal: 10,
                chargePerSpecial: 14
            },
            pity: {
                hintAfter: 4,
                biasAfter: 6,
                helperAfter: 8
            },
            generation: {
                maxInitAttempts: 120,
                maxReshuffleAttempts: 56,
                minProductiveMoves: 2,
                minLaneWeight: 2
            },
            simulation: {
                iterations: 100,
                maxTurns: 24,
                badSeedLimit: 30
            }
        }
    };

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    return {
        getSpec: function(id) {
            return clone(SPECS[id || "mvp-3pin-v1"]);
        },
        listSpecs: function() {
            return Object.keys(SPECS);
        }
    };
});
