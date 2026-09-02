/** Bootstrap character-create snapshot normalization and draft validation. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.BootstrapCharacterCreateRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var GENDERS = ['male', 'female'];
    var PHASES = {
        starting:true, submitting:true, durable:true, scene_ready:true,
        rejected:true, unknown:true, durable_scene_error:true
    };
    var graphemeSegmenter = null;
    try {
        if (typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function') {
            graphemeSegmenter = new Intl.Segmenter('zh-CN', {granularity:'grapheme'});
        }
    } catch (e) {}

    function object(value) {
        return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
    }

    function text(value, min, max, allowEmpty) {
        if (typeof value !== 'string') return null;
        if (value.length > max || (!allowEmpty && value.length < min)) return null;
        if (hasControl(value)) return null;
        return value;
    }

    function visibleText(value, min, max) {
        if (typeof value !== 'string') return null;
        var length = unicodeLength(value);
        if (length < min || length > max || hasControl(value)) return null;
        return value;
    }

    function richText(value, max) {
        if (typeof value !== 'string' || value.length < 1 || value.length > max) return null;
        for (var i = 0; i < value.length; i++) {
            var code = value.charCodeAt(i);
            if ((code < 32 && code !== 9 && code !== 10 && code !== 13)
                    || (code >= 127 && code <= 159)) return null;
        }
        return value;
    }

    function hasControl(value) {
        for (var i = 0; i < value.length; i++) {
            var code = value.charCodeAt(i);
            if (code < 32 || (code >= 127 && code <= 159)) return true;
        }
        return false;
    }

    function unicodeLength(value) {
        if (graphemeSegmenter) {
            var segments = graphemeSegmenter.segment(value);
            var count = 0;
            for (var iterator = segments[Symbol.iterator](), next = iterator.next(); !next.done; next = iterator.next()) count++;
            return count;
        }
        return fallbackGraphemeLength(value);
    }

    function codePointAt(value, index) {
        var first = value.charCodeAt(index);
        if (first >= 55296 && first <= 56319 && index + 1 < value.length) {
            var second = value.charCodeAt(index + 1);
            if (second >= 56320 && second <= 57343) {
                return {value:(first - 55296) * 1024 + second - 56320 + 65536, width:2};
            }
        }
        return {value:first, width:1};
    }

    function isExtend(code) {
        return (code >= 768 && code <= 879)
            || (code >= 1155 && code <= 1161)
            || (code >= 6832 && code <= 6911)
            || (code >= 7616 && code <= 7679)
            || (code >= 8400 && code <= 8447)
            || (code >= 65024 && code <= 65039)
            || (code >= 127995 && code <= 127999)
            || (code >= 917536 && code <= 917631);
    }

    function isRegionalIndicator(code) {
        return code >= 127462 && code <= 127487;
    }

    function fallbackGraphemeLength(value) {
        var length = 0;
        for (var i = 0; i < value.length; length++) {
            var first = codePointAt(value, i);
            i += first.width;
            if (isRegionalIndicator(first.value) && i < value.length) {
                var regionalPair = codePointAt(value, i);
                if (isRegionalIndicator(regionalPair.value)) i += regionalPair.width;
            }
            while (i < value.length) {
                var extension = codePointAt(value, i);
                if (isExtend(extension.value)) {
                    i += extension.width;
                    continue;
                }
                if (extension.value === 8205 && i + extension.width < value.length) {
                    i += extension.width;
                    var joined = codePointAt(value, i);
                    i += joined.width;
                    continue;
                }
                break;
            }
        }
        return length;
    }

    function integer(value, min, max) {
        return typeof value === 'number' && isFinite(value) && Math.floor(value) === value
            && value >= min && value <= max ? value : null;
    }

    function rows(value, limit) {
        if (!Array.isArray(value) || !value.length || value.length > limit) return null;
        var result = [];
        for (var i = 0; i < value.length; i++) {
            var row = object(value[i]);
            var identifier = row && text(row.identifier, 1, 160, false);
            var name = row && text(row.name, 1, 160, false);
            if (identifier === null || name === null) return null;
            result.push({identifier:identifier, name:name, sourceIndex:i});
        }
        return result;
    }

    function appearanceRows(value, limit) {
        if (!Array.isArray(value) || !value.length || value.length > limit) return null;
        var result = [];
        for (var i = 0; i < value.length; i++) {
            var row = object(value[i]);
            var identifier = row && text(row.identifier, 1, 160, false);
            var name = row && text(row.name, 1, 160, false);
            var iconName = row && text(row.iconName, 1, 160, false);
            var itemType = row && text(row.itemType, 1, 160, false);
            var introHTML = row && richText(row.introHTML, 131072);
            var descHTML = row && richText(row.descHTML, 131072);
            if (identifier === null || name === null || iconName === null
                    || itemType === null || introHTML === null || descHTML === null) return null;
            result.push({
                identifier:identifier,
                name:name,
                iconName:iconName,
                itemType:itemType,
                introHTML:introHTML,
                descHTML:descHTML,
                sourceIndex:i
            });
        }
        return result;
    }

    function difficultyRows(value) {
        if (!Array.isArray(value) || value.length !== 3) return null;
        var result = [];
        for (var i = 0; i < value.length; i++) {
            var row = object(value[i]);
            var identifier = row && text(row.identifier, 1, 160, false);
            var name = row && text(row.name, 1, 160, false);
            var description = row && text(row.description, 0, 1000, true);
            if (identifier === null || name === null || description === null) return null;
            result.push({
                identifier:identifier,
                name:name,
                description:description,
                recommended:row.recommended === true,
                sourceIndex:i
            });
        }
        return result;
    }

    function contains(catalog, identifier) {
        if (!catalog) return false;
        for (var i = 0; i < catalog.length; i++) {
            if (catalog[i].identifier === identifier) return true;
        }
        return false;
    }

    function normalizeGenderCatalog(source, limit) {
        source = object(source);
        if (!source) return null;
        var result = {};
        for (var i = 0; i < GENDERS.length; i++) {
            var gender = GENDERS[i];
            result[gender] = rows(source[gender], limit);
            if (!result[gender]) return null;
        }
        return result;
    }

    function normalizeAppearanceGenderCatalog(source, limit) {
        source = object(source);
        if (!source) return null;
        var result = {};
        for (var i = 0; i < GENDERS.length; i++) {
            var gender = GENDERS[i];
            result[gender] = appearanceRows(source[gender], limit);
            if (!result[gender]) return null;
        }
        return result;
    }

    function normalizeConstraints(value) {
        value = object(value);
        if (!value) return null;
        var expected = {
            displayNameMin:1, displayNameMax:32,
            characterNameMin:1, characterNameMax:15,
            heightMin:150, heightMax:200
        };
        var keys = Object.keys(expected);
        for (var i = 0; i < keys.length; i++) {
            if (value[keys[i]] !== expected[keys[i]]) return null;
        }
        return expected;
    }

    function normalizeSnapshot(message) {
        message = object(message);
        if (!message || message.cmd !== 'character_create_snapshot') return null;
        var openRequestId = text(message.openRequestId, 1, 128, false);
        var attemptId = text(message.attemptId, 1, 128, false);
        var slotKey = text(message.slotKey, 1, 128, false);
        var constraints = normalizeConstraints(message.constraints);
        var hairCatalog = rows(message.hairCatalog, 512);
        var appearance = object(message.appearanceCatalog);
        var faces = appearance && object(appearance.faces);
        var upper = appearance && normalizeAppearanceGenderCatalog(appearance.upper, 128);
        var lower = appearance && normalizeAppearanceGenderCatalog(appearance.lower, 128);
        var footwear = appearance && normalizeAppearanceGenderCatalog(appearance.footwear, 128);
        var difficulties = difficultyRows(message.difficulties);
        var defaults = object(message.defaults);
        if (openRequestId === null || attemptId === null || slotKey === null || !constraints || !hairCatalog
                || !faces || !upper || !lower || !footwear || !difficulties || !defaults) return null;

        var normalizedFaces = {};
        var normalizedDefaults = {};
        for (var i = 0; i < GENDERS.length; i++) {
            var gender = GENDERS[i];
            var faceRow = object(faces[gender]);
            var faceIdentifier = faceRow && text(faceRow.identifier, 1, 160, false);
            var faceName = faceRow && text(faceRow.name, 1, 160, false);
            var source = object(defaults[gender]);
            if (faceIdentifier === null || faceName === null || !source) return null;
            var height = integer(source.height, constraints.heightMin, constraints.heightMax);
            var defaultFaceIdentifier = text(source.faceIdentifier, 1, 160, false);
            var hairIdentifier = text(source.hairIdentifier, 1, 160, false);
            var upperIdentifier = text(source.upperIdentifier, 1, 160, false);
            var lowerIdentifier = text(source.lowerIdentifier, 1, 160, false);
            var footwearIdentifier = text(source.footwearIdentifier, 1, 160, false);
            var difficulty = text(source.difficulty, 1, 160, false);
            if (height === null || defaultFaceIdentifier !== faceIdentifier || hairIdentifier === null
                    || upperIdentifier === null || lowerIdentifier === null
                    || footwearIdentifier === null || difficulty === null
                    || !contains(hairCatalog, hairIdentifier)
                    || !contains(upper[gender], upperIdentifier)
                    || !contains(lower[gender], lowerIdentifier)
                    || !contains(footwear[gender], footwearIdentifier)
                    || !contains(difficulties, difficulty)) return null;
            normalizedFaces[gender] = {
                identifier:faceIdentifier,
                name:faceName
            };
            normalizedDefaults[gender] = {
                height:height, faceIdentifier:defaultFaceIdentifier, hairIdentifier:hairIdentifier,
                upperIdentifier:upperIdentifier, lowerIdentifier:lowerIdentifier,
                footwearIdentifier:footwearIdentifier, difficulty:difficulty
            };
        }
        return {
            openRequestId:openRequestId, attemptId:attemptId, slotKey:slotKey, constraints:constraints,
            defaults:normalizedDefaults, hairCatalog:hairCatalog,
            appearanceCatalog:{faces:normalizedFaces, upper:upper, lower:lower, footwear:footwear},
            difficulties:difficulties
        };
    }

    function initialDraft(snapshot) {
        var source = snapshot.defaults.male;
        return {
            displayName:'', displayNameCustomized:false,
            hairIndex:firstIndex(snapshot.hairCatalog, source.hairIdentifier),
            draft:{
                characterName:'', gender:'male', height:source.height,
                faceIdentifier:source.faceIdentifier, hairIdentifier:source.hairIdentifier,
                upperIdentifier:source.upperIdentifier, lowerIdentifier:source.lowerIdentifier,
                footwearIdentifier:source.footwearIdentifier, difficulty:source.difficulty
            }
        };
    }

    function applyGender(snapshot, model, gender) {
        if (GENDERS.indexOf(gender) < 0) return false;
        var source = snapshot.defaults[gender];
        var preservedDifficulty = contains(snapshot.difficulties, model.draft.difficulty)
            ? model.draft.difficulty : source.difficulty;
        model.draft.gender = gender;
        model.draft.height = source.height;
        model.draft.faceIdentifier = source.faceIdentifier;
        model.draft.hairIdentifier = source.hairIdentifier;
        model.draft.upperIdentifier = source.upperIdentifier;
        model.draft.lowerIdentifier = source.lowerIdentifier;
        model.draft.footwearIdentifier = source.footwearIdentifier;
        model.draft.difficulty = preservedDifficulty;
        model.hairIndex = firstIndex(snapshot.hairCatalog, source.hairIdentifier);
        return true;
    }

    function firstIndex(catalog, identifier) {
        for (var i = 0; i < catalog.length; i++) {
            if (catalog[i].identifier === identifier) return i;
        }
        return -1;
    }

    function trimmed(value) {
        return typeof value === 'string' ? value.replace(/^\s+|\s+$/g, '') : '';
    }

    function normalizeDisplayName(value) {
        var normalized = trimmed(value);
        return visibleText(normalized, 1, 32);
    }

    function validateSubmission(snapshot, model) {
        var errors = {};
        var draft = model && object(model.draft);
        if (!draft) return {valid:false, errors:{form:'角色资料不可用。'}};
        var constraints = snapshot.constraints;
        var characterName = trimmed(draft.characterName);
        var validCharacterName = text(
            characterName,
            constraints.characterNameMin,
            constraints.characterNameMax,
            false) !== null;
        if (!validCharacterName)
            errors.characterName = '角色名需为 1–15 个字符，且不能包含控制字符。';
        var displayNameCustomized = !!(model && model.displayNameCustomized);
        var rawDisplayName = trimmed(model && model.displayName);
        var displayName = displayNameCustomized
            ? normalizeDisplayName(rawDisplayName)
            : null;
        if (displayNameCustomized && displayName === null)
            errors.displayName = '存档显示名需为 1–32 个可见 Unicode 文本元素，且不能包含控制字符。';
        var gender = GENDERS.indexOf(draft.gender) >= 0 ? draft.gender : null;
        if (!gender) errors.gender = '请选择角色性别。';
        var height = integer(draft.height, constraints.heightMin, constraints.heightMax);
        if (height === null) errors.height = '身高必须在 150–200 厘米之间。';
        if (gender) {
            if (draft.faceIdentifier !== snapshot.appearanceCatalog.faces[gender].identifier)
                errors.faceIdentifier = '脸型与当前性别的固定目录不一致。';
            if (!contains(snapshot.appearanceCatalog.upper[gender], draft.upperIdentifier))
                errors.upperIdentifier = '上装不在当前权威目录中。';
            if (!contains(snapshot.appearanceCatalog.lower[gender], draft.lowerIdentifier))
                errors.lowerIdentifier = '下装不在当前权威目录中。';
            if (!contains(snapshot.appearanceCatalog.footwear[gender], draft.footwearIdentifier))
                errors.footwearIdentifier = '鞋子不在当前权威目录中。';
        }
        if (!contains(snapshot.hairCatalog, draft.hairIdentifier))
            errors.hairIdentifier = '发型不在当前权威目录中。';
        if (!contains(snapshot.difficulties, draft.difficulty))
            errors.difficulty = '请选择有效难度。';
        if (Object.keys(errors).length) return {valid:false, errors:errors};
        return {
            valid:true,
            displayName:displayName,
            displayNameCustomized:displayNameCustomized,
            draft:{
                characterName:characterName, gender:gender, height:height,
                faceIdentifier:draft.faceIdentifier, hairIdentifier:draft.hairIdentifier,
                upperIdentifier:draft.upperIdentifier, lowerIdentifier:draft.lowerIdentifier,
                footwearIdentifier:draft.footwearIdentifier, difficulty:draft.difficulty
            }, errors:{}
        };
    }

    function normalizeState(message) {
        message = object(message);
        if (!message || message.cmd !== 'character_create_state' || !PHASES[message.phase]) return null;
        var openRequestId = text(message.openRequestId, 1, 128, false);
        var attemptId = text(message.attemptId, 1, 128, false);
        var slotKey = text(message.slotKey, 1, 128, false);
        if (openRequestId === null || attemptId === null || slotKey === null) return null;
        var detail = typeof message.message === 'string' && message.message.length <= 500
            ? message.message : (typeof message.detail === 'string' && message.detail.length <= 500
                ? message.detail : (typeof message.error === 'string' && message.error.length <= 160
                    ? message.error : ''));
        return {
            openRequestId:openRequestId,
            attemptId:attemptId,
            slotKey:slotKey,
            phase:message.phase,
            detail:detail
        };
    }

    function matchesIdentity(snapshot, message) {
        return !!snapshot && !!message
            && snapshot.openRequestId === message.openRequestId
            && snapshot.attemptId === message.attemptId
            && snapshot.slotKey === message.slotKey;
    }

    return {
        genders:GENDERS.slice(0), normalizeSnapshot:normalizeSnapshot,
        initialDraft:initialDraft, applyGender:applyGender,
        normalizeDisplayName:normalizeDisplayName,
        validateSubmission:validateSubmission, normalizeState:normalizeState,
        matchesIdentity:matchesIdentity, firstIndex:firstIndex, contains:contains
    };
});
