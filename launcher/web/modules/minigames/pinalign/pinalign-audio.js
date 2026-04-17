var PinAlignAudio = (function() {
    "use strict";

    function create() {
        var context = null;
        var muted = false;

        function ensure() {
            if (muted) return null;
            if (!context && typeof window !== "undefined") {
                var Ctor = window.AudioContext || window.webkitAudioContext;
                if (Ctor) context = new Ctor();
            }
            return context;
        }

        function chirp(freq, duration, gain) {
            var ctx = ensure();
            if (!ctx) return;
            var osc = ctx.createOscillator();
            var amp = ctx.createGain();
            osc.type = "triangle";
            osc.frequency.value = freq;
            amp.gain.value = gain;
            osc.connect(amp);
            amp.connect(ctx.destination);
            osc.start();
            amp.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + duration);
            osc.stop(ctx.currentTime + duration);
        }

        return {
            setMuted: function(nextMuted) {
                muted = !!nextMuted;
            },
            tick: function() { chirp(280, 0.07, 0.025); },
            settle: function() { chirp(420, 0.11, 0.03); },
            jam: function() { chirp(160, 0.22, 0.035); },
            win: function() { chirp(720, 0.18, 0.04); },
            fail: function() { chirp(120, 0.3, 0.04); }
        };
    }

    return {
        create: create
    };
})();
