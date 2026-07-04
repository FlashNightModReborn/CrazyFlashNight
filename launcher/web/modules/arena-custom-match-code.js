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
    var DEFAULT_SPAWN_DISTANCE = 650;
    var MIN_SPAWN_DISTANCE = 360;
    var MAX_SPAWN_DISTANCE = 1040;
    var DEFAULT_FORMATION = 'line';
    var DEFAULT_FORMATION_SPACING = 54;
    var MIN_FORMATION_SPACING = 36;
    var MAX_FORMATION_SPACING = 96;
    var DEFAULT_REPEAT = 1;
    var MAX_SIDE_COUNT = 20;
    var FORMATIONS = {
        column: { id: 'column', label: '纵队' },
        line: { id: 'line', label: '横列' },
        wedge: { id: 'wedge', label: '楔形' },
        shield: { id: 'shield', label: '前盾后排' },
        grid: { id: 'grid', label: '网格散点' }
    };
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
        spawndistance: true,
        blueformation: true,
        redformation: true,
        formationspacing: true,
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

    function parseBoundedInteger(value, field, min, max, errors) {
        var n = parsePositiveInteger(value, field, errors);
        if (n < min || n > max) {
            pushError(errors, field, 'must be between ' + min + ' and ' + max);
            return min;
        }
        return n;
    }

    function parseFormation(value, field, errors) {
        var id = String(value == null ? '' : value).trim().toLowerCase();
        if (!id) return DEFAULT_FORMATION;
        if (!FORMATIONS[id]) {
            pushError(errors, field, 'must be one of column,line,wedge,shield,grid');
            return DEFAULT_FORMATION;
        }
        return id;
    }

    function formationLabel(id) {
        return (FORMATIONS[id] && FORMATIONS[id].label) || id || DEFAULT_FORMATION;
    }

    function clonePlain(value) {
        if (value == null || typeof value !== 'object') return value;
        if (Array.isArray(value)) {
            var arr = [];
            for (var i = 0; i < value.length; i++) arr.push(clonePlain(value[i]));
            return arr;
        }
        var out = {};
        for (var key in value) {
            if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
            if (value[key] === undefined || typeof value[key] === 'function') continue;
            out[key] = clonePlain(value[key]);
        }
        return out;
    }

    function stableNormalize(value) {
        if (value == null || typeof value !== 'object') return value;
        if (Array.isArray(value)) {
            var arr = [];
            for (var i = 0; i < value.length; i++) arr.push(stableNormalize(value[i]));
            return arr;
        }
        var keys = Object.keys(value).sort();
        var out = {};
        for (var k = 0; k < keys.length; k++) {
            var key = keys[k];
            if (value[key] === undefined || typeof value[key] === 'function') continue;
            out[key] = stableNormalize(value[key]);
        }
        return out;
    }

    function stableStringify(value) {
        return JSON.stringify(stableNormalize(value));
    }

    function hasParameters(value) {
        if (value == null) return false;
        if (typeof value !== 'object' || Array.isArray(value)) return false;
        return Object.keys(value).length > 0;
    }

    function utf8ToBase64(text) {
        if (typeof Buffer !== 'undefined') {
            return Buffer.from(text, 'utf8').toString('base64');
        }
        if (typeof TextEncoder !== 'undefined') {
            var bytes = new TextEncoder().encode(text);
            var binary = '';
            for (var i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
            return btoa(binary);
        }
        return btoa(unescape(encodeURIComponent(text)));
    }

    function base64ToUtf8(text) {
        if (typeof Buffer !== 'undefined') {
            return Buffer.from(text, 'base64').toString('utf8');
        }
        var binary = atob(text);
        if (typeof TextDecoder !== 'undefined') {
            var bytes = new Uint8Array(binary.length);
            for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            return new TextDecoder('utf-8').decode(bytes);
        }
        return decodeURIComponent(escape(binary));
    }

    function encodeParameters(parameters) {
        if (!hasParameters(parameters)) return '';
        return utf8ToBase64(stableStringify(parameters))
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/g, '');
    }

    function decodeParameters(encoded) {
        var text = String(encoded || '').replace(/-/g, '+').replace(/_/g, '/');
        while (text.length % 4) text += '=';
        var value = JSON.parse(base64ToUtf8(text));
        if (!hasParameters(value)) {
            throw new Error('parameters must be a non-empty object');
        }
        return clonePlain(value);
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
        var m = text.match(/^(u[0-9]+|兵种[0-9]+)@([0-9]+)(?:x([0-9]+))?(?:~([A-Za-z0-9_-]+))?$/i);
        if (!m) {
            pushError(errors, field + '[' + index + ']', 'must use u<ID>@<level>x<count> or u<ID>@<level>x<count>~<params>');
            return null;
        }
        var id = normalizeUnitId(m[1]);
        var level = parsePositiveInteger(m[2], field + '[' + index + '].level', errors);
        var count = m[3] == null ? 1 : parsePositiveInteger(m[3], field + '[' + index + '].count', errors);
        var parameters = null;
        if (m[4]) {
            try {
                parameters = decodeParameters(m[4]);
            } catch (err) {
                pushError(errors, field + '[' + index + '].parameters', 'invalid parameters payload');
            }
        }
        if (catalog && !catalog[id]) {
            pushError(errors, field + '[' + index + '].unit', 'unknown unit u' + id);
        }
        if (count > MAX_SIDE_COUNT) {
            pushError(errors, field + '[' + index + '].count', 'count exceeds ' + MAX_SIDE_COUNT);
        }
        var entry = {
            id: id,
            token: 'u' + id,
            type: '兵种' + id,
            level: level,
            count: count,
            label: unitLabel(id, catalog)
        };
        if (parameters) entry.parameters = parameters;
        return entry;
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
        var spawnDistance = fields.spawndistance == null
            ? DEFAULT_SPAWN_DISTANCE
            : parseBoundedInteger(fields.spawndistance, 'spawnDistance', MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE, errors);
        var blueFormation = fields.blueformation == null
            ? DEFAULT_FORMATION
            : parseFormation(fields.blueformation, 'blueFormation', errors);
        var redFormation = fields.redformation == null
            ? DEFAULT_FORMATION
            : parseFormation(fields.redformation, 'redFormation', errors);
        var formationSpacing = fields.formationspacing == null
            ? DEFAULT_FORMATION_SPACING
            : parseBoundedInteger(fields.formationspacing, 'formationSpacing', MIN_FORMATION_SPACING, MAX_FORMATION_SPACING, errors);
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
            spawnDistance: spawnDistance,
            blueFormation: blueFormation,
            redFormation: redFormation,
            formationSpacing: formationSpacing,
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
            var token = 'u' + id + '@' + entry.level + 'x' + entry.count;
            var encodedParameters = encodeParameters(entry.parameters || entry.Parameters || entry['参数']);
            return encodedParameters ? (token + '~' + encodedParameters) : token;
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
        if (value.spawnDistance && value.spawnDistance !== DEFAULT_SPAWN_DISTANCE) {
            fields.push('spawnDistance=' + value.spawnDistance);
        }
        if (value.blueFormation && value.blueFormation !== DEFAULT_FORMATION) {
            fields.push('blueFormation=' + value.blueFormation);
        }
        if (value.redFormation && value.redFormation !== DEFAULT_FORMATION) {
            fields.push('redFormation=' + value.redFormation);
        }
        if (value.formationSpacing && value.formationSpacing !== DEFAULT_FORMATION_SPACING) {
            fields.push('formationSpacing=' + value.formationSpacing);
        }
        return fields.join(';');
    }

    function expandRoster(roster) {
        var out = [];
        for (var i = 0; i < roster.length; i++) {
            for (var c = 0; c < roster[i].count; c++) {
                var unit = { type: roster[i].type, level: roster[i].level };
                if (hasParameters(roster[i].parameters)) unit.parameters = clonePlain(roster[i].parameters);
                out.push(unit);
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
            spawnDistance: parsed.spawnDistance || DEFAULT_SPAWN_DISTANCE,
            blueFormation: parsed.blueFormation || DEFAULT_FORMATION,
            redFormation: parsed.redFormation || DEFAULT_FORMATION,
            formationSpacing: parsed.formationSpacing || DEFAULT_FORMATION_SPACING,
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
            spawnDistance: parsed.spawnDistance || DEFAULT_SPAWN_DISTANCE,
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
            spawnDistance: parsed.spawnDistance || DEFAULT_SPAWN_DISTANCE,
            blueFormation: parsed.blueFormation || DEFAULT_FORMATION,
            redFormation: parsed.redFormation || DEFAULT_FORMATION,
            formationSpacing: parsed.formationSpacing || DEFAULT_FORMATION_SPACING,
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
        DEFAULT_SPAWN_DISTANCE: DEFAULT_SPAWN_DISTANCE,
        MIN_SPAWN_DISTANCE: MIN_SPAWN_DISTANCE,
        MAX_SPAWN_DISTANCE: MAX_SPAWN_DISTANCE,
        DEFAULT_FORMATION: DEFAULT_FORMATION,
        DEFAULT_FORMATION_SPACING: DEFAULT_FORMATION_SPACING,
        MIN_FORMATION_SPACING: MIN_FORMATION_SPACING,
        MAX_FORMATION_SPACING: MAX_FORMATION_SPACING,
        FORMATIONS: FORMATIONS,
        ParseError: ParseError,
        buildCalibrationCase: buildCalibrationCase,
        buildCalibrationManifest: buildCalibrationManifest,
        buildEnterPayload: buildEnterPayload,
        estimateVenueFee: estimateVenueFee,
        cloneParameters: clonePlain,
        decodeParameters: decodeParameters,
        encodeParameters: encodeParameters,
        hasParameters: hasParameters,
        formationLabel: formationLabel,
        normalizeUnitId: normalizeUnitId,
        parseMatchCode: parseMatchCode,
        serializeMatchCode: serializeMatchCode,
        stableStringify: stableStringify
    };
});
