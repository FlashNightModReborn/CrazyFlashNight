(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.ArenaCustomMatchCode = factory();
    }
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
    'use strict';

    var MAGIC = 'CF7ARENA';
    var VERSION = 'v1';
    var DEFAULT_TIMEOUT_FRAMES = 3600;
    var DEFAULT_REPEAT = 1;
    var MAX_SIDE_COUNT = 20;
    var ECONOMY_KEYS = {
        money: true,
        cash: true,
        gold: true,
        coin: true,
        coins: true,
        kpoint: true,
        kpoints: true,
        reward: true,
        rewards: true,
        drop: true,
        drops: true,
        loot: true,
        item: true,
        items: true,
        equipment: true,
        equip: true,
        exp: true,
        xp: true
    };
    var ALLOWED_FIELDS = {
        mode: true,
        seed: true,
        blue: true,
        red: true,
        enemy: true,
        player: true,
        timeout: true,
        rules: true,
        arena: true,
        difficulty: true
    };

    function ParseError(message, details) {
        this.name = 'ArenaCustomMatchCodeError';
        this.message = message;
        this.details = details || [];
    }
    ParseError.prototype = Object.create(Error.prototype);
    ParseError.prototype.constructor = ParseError;

    function fail(message, details) {
        throw new ParseError(message, details);
    }

    function pushError(errors, field, message) {
        errors.push({ field: field || '', message: message });
    }

    function parsePositiveInteger(value, field, errors) {
        if (!/^[0-9]+$/.test(String(value || ''))) {
            pushError(errors, field, 'must be an integer');
            return 0;
        }
        var n = Number(value);
        if (!isFinite(n) || n <= 0 || Math.floor(n) !== n) {
            pushError(errors, field, 'must be a positive integer');
            return 0;
        }
        return n;
    }

    function parseNonNegativeInteger(value, field, errors) {
        if (!/^[0-9]+$/.test(String(value || ''))) {
            pushError(errors, field, 'must be a non-negative integer');
            return 0;
        }
        var n = Number(value);
        if (!isFinite(n) || n < 0 || Math.floor(n) !== n) {
            pushError(errors, field, 'must be a non-negative integer');
            return 0;
        }
        return n;
    }

    function normalizeCatalog(catalog) {
        if (!catalog) return null;
        var out = {};
        var i, id, entry;
        if (Array.isArray(catalog)) {
            for (i = 0; i < catalog.length; i++) {
                entry = catalog[i];
                if (entry == null) continue;
                id = typeof entry === 'object' ? (entry.id != null ? entry.id : entry.type) : entry;
                id = normalizeUnitId(id);
                if (id != null) out[id] = typeof entry === 'object' ? entry : { id: id };
            }
            return out;
        }
        if (typeof catalog === 'object') {
            for (var key in catalog) {
                if (!Object.prototype.hasOwnProperty.call(catalog, key)) continue;
                entry = catalog[key];
                id = normalizeUnitId(entry && typeof entry === 'object' && entry.id != null ? entry.id : key);
                if (id != null) out[id] = entry && typeof entry === 'object' ? entry : { id: id };
            }
            return out;
        }
        return null;
    }

    function normalizeUnitId(value) {
        if (value == null) return null;
        var text = String(value).trim();
        var m = text.match(/^u([0-9]+)$/i) || text.match(/^兵种([0-9]+)$/);
        if (m) return Number(m[1]);
        if (/^[0-9]+$/.test(text)) return Number(text);
        return null;
    }

    function unitLabel(id, catalog) {
        var entry = catalog && catalog[id];
        if (!entry) return '兵种' + id;
        var name = entry.name || entry.displayName || ('兵种' + id);
        var sprite = entry.spritename ? (' · ' + entry.spritename) : '';
        return '兵种' + id + ' ' + name + sprite;
    }

    function parseRosterToken(token, field, index, catalog, errors) {
        var text = String(token || '').trim();
        var m = text.match(/^(u[0-9]+|兵种[0-9]+)@([0-9]+)(?:x([0-9]+))?$/i);
        if (!m) {
            pushError(errors, field + '[' + index + ']', 'must use u<ID>@<level>x<count>');
            return null;
        }
        var id = normalizeUnitId(m[1]);
        var level = parsePositiveInteger(m[2], field + '[' + index + '].level', errors);
        var count = m[3] == null ? 1 : parsePositiveInteger(m[3], field + '[' + index + '].count', errors);
        if (catalog && !catalog[id]) {
            pushError(errors, field + '[' + index + '].unit', 'unknown unit u' + id);
        }
        if (count > MAX_SIDE_COUNT) {
            pushError(errors, field + '[' + index + '].count', 'count exceeds ' + MAX_SIDE_COUNT);
        }
        return {
            id: id,
            token: 'u' + id,
            type: '兵种' + id,
            level: level,
            count: count,
            label: unitLabel(id, catalog)
        };
    }

    function parseRoster(value, field, catalog, errors) {
        if (typeof value !== 'string' || value.trim() === '') {
            pushError(errors, field, 'must be a non-empty roster');
            return [];
        }
        var parts = value.split(',');
        var out = [];
        var total = 0;
        for (var i = 0; i < parts.length; i++) {
            if (!parts[i].trim()) {
                pushError(errors, field + '[' + i + ']', 'empty roster token');
                continue;
            }
            var entry = parseRosterToken(parts[i], field, i, catalog, errors);
            if (entry) {
                out.push(entry);
                total += entry.count;
            }
        }
        if (total <= 0) {
            pushError(errors, field, 'must contain at least one unit');
        } else if (total > MAX_SIDE_COUNT) {
            pushError(errors, field, 'total unit count exceeds ' + MAX_SIDE_COUNT);
        }
        return out;
    }

    function parseMatchCode(code, options) {
        options = options || {};
        var errors = [];
        var source = String(code == null ? '' : code).trim();
        if (!source) fail('empty arena custom match code', [{ field: 'code', message: 'empty code' }]);

        var parts = source.split(';').map(function(part) { return part.trim(); }).filter(Boolean);
        if (parts.length === 0 || parts[0] !== MAGIC + ':' + VERSION) {
            fail('invalid arena custom match code', [{ field: 'magic', message: 'expected ' + MAGIC + ':' + VERSION }]);
        }

        var fields = {};
        for (var i = 1; i < parts.length; i++) {
            var eq = parts[i].indexOf('=');
            if (eq <= 0) {
                pushError(errors, 'field[' + i + ']', 'must use key=value');
                continue;
            }
            var key = parts[i].slice(0, eq).trim();
            var value = parts[i].slice(eq + 1).trim();
            var lower = key.toLowerCase();
            if (ECONOMY_KEYS[lower]) {
                pushError(errors, key, 'economy field is not allowed in match codes');
                continue;
            }
            if (!ALLOWED_FIELDS[lower]) {
                pushError(errors, key, 'unknown field');
                continue;
            }
            if (fields[lower] !== undefined) {
                pushError(errors, key, 'duplicate field');
                continue;
            }
            fields[lower] = value;
        }

        var mode = fields.mode || '';
        if (mode !== 'mvm' && mode !== 'pve') {
            pushError(errors, 'mode', 'must be mvm or pve');
        }
        var seed = fields.seed == null ? 0 : parseNonNegativeInteger(fields.seed, 'seed', errors);
        var timeoutFrames = fields.timeout == null
            ? DEFAULT_TIMEOUT_FRAMES
            : parsePositiveInteger(fields.timeout, 'timeout', errors);
        var catalog = normalizeCatalog(options.unitCatalog || options.units || null);
        var blueRoster = [];
        var redRoster = [];
        var enemyRoster = [];
        var player = fields.player || '';

        if (mode === 'pve') {
            if (fields.blue != null) pushError(errors, 'blue', 'blue is only valid in mode=mvm');
            if (fields.red != null) pushError(errors, 'red', 'red is only valid in mode=mvm');
            if (player !== 'current') pushError(errors, 'player', 'must be current');
            enemyRoster = parseRoster(fields.enemy, 'enemy', catalog, errors);
        } else {
            if (fields.enemy != null) pushError(errors, 'enemy', 'enemy is only valid in mode=pve');
            if (fields.player != null) pushError(errors, 'player', 'player is only valid in mode=pve');
            blueRoster = parseRoster(fields.blue, 'blue', catalog, errors);
            redRoster = parseRoster(fields.red, 'red', catalog, errors);
        }

        if (errors.length > 0) {
            fail('invalid arena custom match code', errors);
        }

        var parsed = {
            schema: 'arena-custom-match-code.v1',
            format: MAGIC + ':' + VERSION,
            raw: source,
            mode: mode,
            seed: seed,
            timeoutFrames: timeoutFrames,
            arena: fields.arena || '',
            rules: fields.rules || 'no_drop,no_exp,original_death_flow',
            difficulty: fields.difficulty || '',
            blueRoster: blueRoster,
            redRoster: redRoster,
            enemyRoster: enemyRoster,
            player: mode === 'pve' ? 'current' : ''
        };
        parsed.canonical = serializeMatchCode(parsed);
        parsed.venueFeeEstimate = estimateVenueFee(parsed);
        if (mode === 'pve') parsed.enterPayload = buildEnterPayload(parsed, options);
        else parsed.calibrationCase = buildCalibrationCase(parsed, options);
        return parsed;
    }

    function serializeRoster(roster) {
        return (roster || []).map(function(entry) {
            var id = entry.id != null ? entry.id : normalizeUnitId(entry.type || entry.token);
            return 'u' + id + '@' + entry.level + 'x' + entry.count;
        }).join(',');
    }

    function serializeMatchCode(value) {
        if (!value) return '';
        var mode = value.mode || 'mvm';
        var seed = value.seed == null ? 0 : value.seed;
        var fields = [
            MAGIC + ':' + VERSION,
            'mode=' + mode,
            'seed=' + seed
        ];
        if (mode === 'pve') {
            fields.push('enemy=' + serializeRoster(value.enemyRoster));
            fields.push('player=' + (value.player || 'current'));
        } else {
            fields.push('blue=' + serializeRoster(value.blueRoster));
            fields.push('red=' + serializeRoster(value.redRoster));
        }
        if (value.timeoutFrames && value.timeoutFrames !== DEFAULT_TIMEOUT_FRAMES) {
            fields.push('timeout=' + value.timeoutFrames);
        }
        return fields.join(';');
    }

    function expandRoster(roster) {
        var out = [];
        for (var i = 0; i < roster.length; i++) {
            for (var c = 0; c < roster[i].count; c++) {
                out.push({ type: roster[i].type, level: roster[i].level });
            }
        }
        return out;
    }

    function buildCalibrationCase(parsed, options) {
        options = options || {};
        if (!parsed || parsed.mode !== 'mvm') return null;
        var seed = parsed.seed == null ? 0 : parsed.seed;
        return {
            caseId: options.caseId || ('custom-mvm-' + seed),
            blueRoster: expandRoster(parsed.blueRoster || []),
            redRoster: expandRoster(parsed.redRoster || []),
            repeat: options.repeat || DEFAULT_REPEAT,
            timeoutFrames: parsed.timeoutFrames || DEFAULT_TIMEOUT_FRAMES,
            tags: ['arena-custom-p1', 'mvm'],
            plannerReason: 'generated from arena custom match code P1'
        };
    }

    function buildCalibrationManifest(parsed, options) {
        options = options || {};
        if (!parsed || parsed.mode !== 'mvm') {
            fail('invalid arena calibration manifest source', [{ field: 'mode', message: 'mode must be mvm' }]);
        }
        return {
            schema: 'arena-calibration.case-manifest.v1',
            batchId: options.batchId || ('custom-' + (parsed.seed == null ? 0 : parsed.seed)),
            arenaMode: 'calibration',
            createdAt: options.createdAt || new Date().toISOString(),
            buildCommit: options.buildCommit || 'web',
            repeat: options.repeat || DEFAULT_REPEAT,
            timeoutFrames: parsed.timeoutFrames || DEFAULT_TIMEOUT_FRAMES,
            cases: [buildCalibrationCase(parsed, options)]
        };
    }

    function buildEnterPayload(parsed, options) {
        options = options || {};
        if (!parsed || parsed.mode !== 'pve') return null;
        return {
            cmd: 'enter',
            mode: 'custom_pve',
            expr: options.expr || 'custom-pve',
            deposit: 0,
            reward: 0,
            difficulty: parsed.difficulty || '',
            player: 'current',
            matchCode: parsed.canonical || serializeMatchCode(parsed),
            roster: expandRoster(parsed.enemyRoster || [])
        };
    }

    function estimateVenueFee(parsed) {
        if (parsed && parsed.mode === 'pve') return 0;
        var total = 0;
        function addSide(roster) {
            for (var i = 0; i < roster.length; i++) {
                total += roster[i].level * roster[i].count;
            }
        }
        addSide(parsed.blueRoster || []);
        addSide(parsed.redRoster || []);
        return Math.max(1000, Math.round(total * 100 / 500) * 500);
    }

    return {
        MAGIC: MAGIC,
        VERSION: VERSION,
        DEFAULT_TIMEOUT_FRAMES: DEFAULT_TIMEOUT_FRAMES,
        ParseError: ParseError,
        buildCalibrationCase: buildCalibrationCase,
        buildCalibrationManifest: buildCalibrationManifest,
        buildEnterPayload: buildEnterPayload,
        estimateVenueFee: estimateVenueFee,
        normalizeUnitId: normalizeUnitId,
        parseMatchCode: parseMatchCode,
        serializeMatchCode: serializeMatchCode
    };
});
