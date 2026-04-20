(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.LockboxCore = factory();
    }
})(typeof self !== 'undefined' ? self : this, function() {
    'use strict';

    var TOKEN_SPECS = [
        { id: 0, code: 'SYS', shape: 'hex', color: '#5cf0ff', fill: '#091a24', accent: '#c9fbff', motif: 'bus' },
        { id: 1, code: 'PWR', shape: 'square', color: '#ffc857', fill: '#261b08', accent: '#ffe7ad', motif: 'bars' },
        { id: 2, code: 'LNK', shape: 'diamond', color: '#7dffa2', fill: '#0a2212', accent: '#d8ffe3', motif: 'chain' },
        { id: 3, code: 'CRC', shape: 'oct', color: '#ff6f91', fill: '#2a0c16', accent: '#ffd3dc', motif: 'ring' },
        { id: 4, code: 'MUX', shape: 'round', color: '#b68cff', fill: '#1c0f2d', accent: '#eadcff', motif: 'switch' }
    ];

    var DOT_GLYPHS = {
        C: ['111', '100', '100', '100', '111'],
        K: ['101', '101', '110', '101', '101'],
        L: ['100', '100', '100', '100', '111'],
        M: ['101', '111', '111', '101', '101'],
        N: ['101', '111', '111', '111', '101'],
        P: ['110', '101', '110', '100', '100'],
        R: ['110', '101', '110', '101', '101'],
        S: ['111', '100', '111', '001', '111'],
        U: ['101', '101', '101', '101', '111'],
        W: ['101', '101', '101', '111', '101'],
        X: ['101', '101', '010', '101', '101'],
        Y: ['101', '101', '010', '010', '010']
    };

    var PROFILE_DEFS = {
        standard: {
            id: 'standard',
            title: '普通高安箱',
            size: 4,
            alphabetSize: 4,
            bufferCap: 5,
            lenA: 3,
            lenB: 3,
            lenC: 3,
            overlapAB: 2,
            mainMinLen: 4,
            traceFullMs: 10000,
            tracePulse: 0.12,
            illegalGrace: 1,
            bonusLockPct: 0.70,
            targetFullSolutions: [1, 3],
            targetMainMinSolutions: [1, 6],
            targetEntryStarts: [1, 4],
            targetBonusShare: [0.20, 0.80]
        },
        elite7: {
            id: 'elite7',
            title: '顶级高安箱',
            size: 5,
            alphabetSize: 5,
            bufferCap: 7,
            lenA: 4,
            lenB: 4,
            lenC: 3,
            overlapAB: 2,
            mainMinLen: 6,
            traceFullMs: 8000,
            tracePulse: 0.18,
            illegalGrace: 0,
            bonusLockPct: 0.70,
            targetFullSolutions: [1, 3],
            targetMainMinSolutions: [1, 4],
            targetEntryStarts: [1, 3],
            targetBonusShare: [0.15, 0.55]
        },
        elite6: {
            id: 'elite6',
            title: '顶级高安箱(6步对照)',
            size: 5,
            alphabetSize: 5,
            bufferCap: 6,
            lenA: 4,
            lenB: 4,
            lenC: 3,
            overlapAB: 2,
            mainMinLen: 6,
            traceFullMs: 8000,
            tracePulse: 0.18,
            illegalGrace: 0,
            bonusLockPct: 0.70,
            targetFullSolutions: [1, 3],
            targetMainMinSolutions: [1, 4],
            targetEntryStarts: [1, 3],
            targetBonusShare: [1.00, 1.00]
        }
    };

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function mixSeed(a, b) {
        var x = (a | 0) ^ ((b | 0) + 0x9e3779b9);
        x = Math.imul(x ^ (x >>> 16), 0x85ebca6b);
        x = Math.imul(x ^ (x >>> 13), 0xc2b2ae35);
        x ^= x >>> 16;
        return x >>> 0;
    }

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function uniq(values) {
        var out = [];
        var seen = {};
        for (var i = 0; i < values.length; i++) {
            var key = String(values[i]);
            if (!seen[key]) {
                seen[key] = true;
                out.push(values[i]);
            }
        }
        return out;
    }

    function arrayEquals(a, b) {
        if (!a || !b || a.length !== b.length) return false;
        for (var i = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false;
        }
        return true;
    }

    function cellKey(cell) {
        return cell.r + ':' + cell.c;
    }

    function getProfile(id) {
        return clone(PROFILE_DEFS[id] || PROFILE_DEFS.standard);
    }

    function nextAxisAfterPickCount(pickCount) {
        return (pickCount % 2 === 1) ? 'COL' : 'ROW';
    }

    function getLegalCells(size, cell, nextAxis) {
        var cells = [];
        var i;
        if (!cell) {
            for (i = 0; i < size; i++) cells.push({ r: 0, c: i });
            return cells;
        }
        if (nextAxis === 'COL') {
            for (i = 0; i < size; i++) {
                if (i !== cell.r) cells.push({ r: i, c: cell.c });
            }
        } else {
            for (i = 0; i < size; i++) {
                if (i !== cell.c) cells.push({ r: cell.r, c: i });
            }
        }
        return cells;
    }

    function bufferContainsSequence(buffer, seq) {
        if (!buffer || !seq || seq.length === 0 || buffer.length < seq.length) return false;
        for (var start = 0; start <= buffer.length - seq.length; start++) {
            var ok = true;
            for (var i = 0; i < seq.length; i++) {
                if (buffer[start + i] !== seq[i]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    function evaluateBuffer(buffer, seqA, seqB, seqC) {
        return {
            a: bufferContainsSequence(buffer, seqA),
            b: bufferContainsSequence(buffer, seqB),
            c: bufferContainsSequence(buffer, seqC)
        };
    }

    function deriveSequencesFromF(config, fullString) {
        var startB = config.lenA - config.overlapAB;
        var seqA = fullString.slice(0, config.lenA);
        var seqB = fullString.slice(startB, startB + config.lenB);
        var startC = Math.max(0, fullString.length - config.lenC);
        var seqC = fullString.slice(startC, startC + config.lenC);
        return {
            seqA: seqA,
            seqB: seqB,
            seqC: seqC,
            mainLen: config.lenA + config.lenB - config.overlapAB
        };
    }

    function createMatrix(size, fillValue) {
        var matrix = [];
        for (var r = 0; r < size; r++) {
            var row = [];
            for (var c = 0; c < size; c++) row.push(fillValue);
            matrix.push(row);
        }
        return matrix;
    }

    function countFrequencies(values) {
        var map = {};
        for (var i = 0; i < values.length; i++) {
            map[values[i]] = (map[values[i]] || 0) + 1;
        }
        return map;
    }

    function RNG(seed) {
        this._state = (seed >>> 0) || 1;
    }

    RNG.prototype.next = function() {
        var x = this._state;
        x ^= x << 13;
        x ^= x >>> 17;
        x ^= x << 5;
        this._state = x >>> 0;
        return this._state / 4294967296;
    };

    RNG.prototype.int = function(min, max) {
        return min + Math.floor(this.next() * (max - min + 1));
    };

    RNG.prototype.pick = function(items) {
        if (!items || !items.length) return null;
        return items[this.int(0, items.length - 1)];
    };

    RNG.prototype.shuffle = function(items) {
        var out = items.slice();
        for (var i = out.length - 1; i > 0; i--) {
            var j = this.int(0, i);
            var tmp = out[i];
            out[i] = out[j];
            out[j] = tmp;
        }
        return out;
    };

    function createGlyphRects(code, fill) {
        var glyphs = [];
        var x = 13;
        for (var i = 0; i < code.length; i++) {
            var pattern = DOT_GLYPHS[code.charAt(i)] || DOT_GLYPHS.S;
            for (var r = 0; r < pattern.length; r++) {
                for (var c = 0; c < pattern[r].length; c++) {
                    if (pattern[r].charAt(c) === '1') {
                        glyphs.push('<rect x="' + (x + c * 2) + '" y="' + (45 + r * 2) + '" width="1.5" height="1.5" rx="0.3" fill="' + fill + '" />');
                    }
                }
            }
            x += 8;
        }
        return glyphs.join('');
    }

    function renderTokenSvg(tokenId, options) {
        options = options || {};
        var spec = TOKEN_SPECS[tokenId] || TOKEN_SPECS[0];
        var size = options.size || 64;
        var body = '';
        var motif = '';

        if (spec.shape === 'hex') {
            body = '<polygon points="20,8 44,8 56,24 44,40 20,40 8,24" />';
            motif = '<path d="M18 18h28M18 24h28M18 30h18" />';
        } else if (spec.shape === 'square') {
            body = '<path d="M14 10h36l4 4v24l-4 4H14l-4-4V14z" />';
            motif = '<path d="M22 16v18M30 16v14M38 16v18M18 34h24" />';
        } else if (spec.shape === 'diamond') {
            body = '<polygon points="32,8 56,24 32,40 8,24" />';
            motif = '<path d="M19 24h26M25 18l7 6-7 6M39 18l-7 6 7 6" />';
        } else if (spec.shape === 'oct') {
            body = '<path d="M20 8h24l12 12v8L44 40H20L8 28v-8z" />';
            motif = '<circle cx="32" cy="24" r="8" /><path d="M32 16v3M32 29v3M24 24h3M37 24h3" />';
        } else {
            body = '<path d="M18 10h28c6 0 10 4 10 10v10c0 6-4 10-10 10H18C12 40 8 36 8 30V20c0-6 4-10 10-10z" />';
            motif = '<path d="M18 18h10l4 6 8-12h6M18 30h28" />';
        }

        return [
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="' + size + '" height="' + size + '" aria-hidden="true">',
            '<defs><linearGradient id="lb-g' + spec.id + '" x1="0%" x2="100%" y1="0%" y2="100%"><stop offset="0%" stop-color="' + spec.fill + '" /><stop offset="100%" stop-color="#05070b" /></linearGradient></defs>',
            '<g fill="url(#lb-g' + spec.id + ')" stroke="' + spec.color + '" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round">',
            body,
            '</g>',
            '<g fill="none" stroke="' + spec.accent + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">',
            motif,
            '</g>',
            '<rect x="12" y="42" width="40" height="14" rx="4" fill="rgba(0,0,0,0.55)" stroke="' + spec.color + '" stroke-width="1" />',
            createGlyphRects(spec.code, spec.accent),
            '</svg>'
        ].join('');
    }

    function buildSessionExport(config, puzzleInstance, solveReport, extra) {
        return {
            PuzzleConfig: clone(config),
            PuzzleInstance: clone(puzzleInstance),
            SolveReport: clone(solveReport),
            Meta: clone(extra || {})
        };
    }

    return {
        TOKEN_SPECS: TOKEN_SPECS,
        PROFILE_DEFS: PROFILE_DEFS,
        RNG: RNG,
        clamp: clamp,
        mixSeed: mixSeed,
        clone: clone,
        uniq: uniq,
        arrayEquals: arrayEquals,
        cellKey: cellKey,
        getProfile: getProfile,
        nextAxisAfterPickCount: nextAxisAfterPickCount,
        getLegalCells: getLegalCells,
        bufferContainsSequence: bufferContainsSequence,
        evaluateBuffer: evaluateBuffer,
        deriveSequencesFromF: deriveSequencesFromF,
        createMatrix: createMatrix,
        countFrequencies: countFrequencies,
        renderTokenSvg: renderTokenSvg,
        buildSessionExport: buildSessionExport
    };
});
