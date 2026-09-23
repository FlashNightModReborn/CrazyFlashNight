/**
 * Replays the three extracted gym loops with the active AS2 portrait.
 * Motion assets stay in the normal Web asset tree; no XFL sampling runs here.
 */
(function(root) {
    'use strict';

    var MOTION_SCHEMAS = {
        dummy:'cf7-wood-dummy-motion-v1',
        dumbbell:'cf7-gym-station-motion-v1',
        squat:'cf7-gym-station-motion-v1'
    };
    var MANIFEST_SCHEMA = 'cf7-gym-motion-manifest-v1';
    var BODY_PREFIX = '主角肢体素材/';
    var FRAME_RATE = 30;
    var REQUIRED_BODY_FIELDS = [
        '身体','上臂','左下臂','右下臂','左手','右手','屁股',
        '左大腿','右大腿','小腿','脚','脸型','发型'
    ];
    var WEAPON_FIELDS = {
        '长枪_装扮':true,
        '手枪_装扮':true,
        '手枪2_装扮':true,
        '刀_装扮':true,
        '刀1_装扮':true,
        '刀2_装扮':true,
        '刀3_装扮':true,
        '手雷_装扮':true
    };
    var STOWED_WEAPON_SLOTS = {
        '长枪':true,'手枪':true,'手枪2':true,'刀':true,'手雷':true
    };

    var assetRoot = normalizeAssetRoot(root && root.__GYM_MOTION_ASSET_ROOT__);
    var packagePromise = null;
    var packageData = null;
    var preparedPortraits = Object.create(null);
    var portraitPromises = Object.create(null);
    var imagePromises = Object.create(null);
    var activeInstances = 0;
    var createdInstances = 0;
    var destroyedInstances = 0;
    var ownedObjectUrls = [];

    function normalizeAssetRoot(value) {
        var path = typeof value === 'string' && value.trim() ? value.trim() : 'assets/gym/';
        if (path.charAt(path.length - 1) !== '/') path += '/';
        return path;
    }

    function assetUrl(relativePath, base) {
        var url = new URL(relativePath, base || new URL(assetRoot, document.baseURI));
        if (url.origin !== window.location.origin) throw new Error('cross_origin_asset');
        return url.href;
    }

    function sha256Hex(bytes) {
        if (!window.crypto || !window.crypto.subtle || typeof window.crypto.subtle.digest !== 'function') {
            return Promise.reject(new Error('integrity_api_unavailable'));
        }
        return window.crypto.subtle.digest('SHA-256', bytes).then(function(digest) {
            return Array.prototype.map.call(new Uint8Array(digest), function(value) {
                return value.toString(16).padStart(2, '0');
            }).join('');
        });
    }

    function fetchBytes(url, label) {
        return fetch(url, { cache:'force-cache' }).then(function(response) {
            if (!response.ok) throw new Error((label || 'asset') + '_http_' + response.status);
            return response.arrayBuffer();
        });
    }

    function readVerifiedBytes(url, expectedHash, label) {
        if (typeof expectedHash !== 'string' || !/^[0-9a-f]{64}$/i.test(expectedHash)) {
            return Promise.reject(new Error((label || 'asset') + '_hash_missing'));
        }
        return fetchBytes(url, label).then(function(bytes) {
            return sha256Hex(bytes).then(function(actualHash) {
                if (actualHash.toLowerCase() !== expectedHash.toLowerCase()) {
                    throw new Error((label || 'asset') + '_hash_mismatch');
                }
                return bytes;
            });
        });
    }

    function parseJsonBytes(bytes, label) {
        try {
            return JSON.parse(new TextDecoder('utf-8').decode(bytes));
        } catch (error) {
            throw new Error((label || 'json') + '_invalid_json');
        }
    }

    function loadImage(url) {
        if (imagePromises[url]) return imagePromises[url].promise;
        var record = { image:null, promise:null };
        record.promise = new Promise(function(resolve, reject) {
            var image = new Image();
            image.decoding = 'async';
            image.onload = function() {
                if (image.naturalWidth > 0 && image.naturalHeight > 0) {
                    record.image = image;
                    resolve(image);
                }
                else reject(new Error('image_empty'));
            };
            image.onerror = function() { reject(new Error('image_load_failed')); };
            image.src = url;
            if (image.complete && image.naturalWidth > 0) {
                record.image = image;
                resolve(image);
            }
        }).catch(function(error) {
            delete imagePromises[url];
            throw error;
        });
        imagePromises[url] = record;
        return record.promise;
    }

    function loadVerifiedSvg(relativeUri, expectedHash, base, label) {
        var url = assetUrl(relativeUri, base);
        return readVerifiedBytes(url, expectedHash, label).then(function(bytes) {
            var blob = new Blob([bytes], { type:'image/svg+xml' });
            var objectUrl = URL.createObjectURL(blob);
            ownedObjectUrls.push(objectUrl);
            function releaseObjectUrl() {
                URL.revokeObjectURL(objectUrl);
                var index = ownedObjectUrls.indexOf(objectUrl);
                if (index >= 0) ownedObjectUrls.splice(index, 1);
            }
            return loadImage(objectUrl).then(function(image) {
                releaseObjectUrl();
                return image;
            }, function(error) {
                releaseObjectUrl();
                throw error;
            });
        });
    }

    function loadPackage() {
        var manifestUrl = assetUrl('manifest.json');
        return fetchBytes(manifestUrl, 'gym_manifest').then(function(manifestBytes) {
            var motionManifest = parseJsonBytes(manifestBytes, 'gym_manifest');
            if (motionManifest.schema !== MANIFEST_SCHEMA
                    || motionManifest.motionUri !== 'wood-dummy-loop.json'
                    || !motionManifest.stations
                    || Object.keys(motionManifest.stations).sort().join(',') !== 'dumbbell,dummy,squat') {
                throw new Error('gym_manifest_contract');
            }
            return Promise.all(Object.keys(MOTION_SCHEMAS).map(function(stationId) {
                var station = motionManifest.stations[stationId];
                if (!station || !Number.isInteger(station.frameCount) || station.frameCount < 1
                        || station.frameRate !== FRAME_RATE
                        || station.timelineEndExclusive - station.timelineStart !== station.frameCount
                        || typeof station.motionUri !== 'string') {
                    throw new Error('gym_station_contract:' + stationId);
                }
                var loopUrl = assetUrl(station.motionUri, manifestUrl);
                var loopHash = motionManifest.outputs && motionManifest.outputs[station.motionUri];
                return readVerifiedBytes(loopUrl, loopHash, 'gym_loop_' + stationId)
                    .then(function(loopBytes) {
                        var motion = parseJsonBytes(loopBytes, 'gym_loop_' + stationId);
                        if (motion.schema !== MOTION_SCHEMAS[stationId]
                                || (stationId !== 'dummy' && motion.stationId !== stationId)
                                || !motion.source || motion.source.frameCount !== station.frameCount
                                || motion.source.frameRate !== station.frameRate
                                || motion.source.timelineIndices[0] !== station.timelineStart
                                || motion.source.timelineIndices[1] !== station.timelineEndExclusive - 1
                                || !Array.isArray(motion.layers)
                                || motion.layers.length !== station.layerCount
                                || !motion.componentBindings || !motion.vectors) {
                            throw new Error('gym_loop_contract:' + stationId);
                        }
                        validateMotion(motion, station.frameCount);
                        return { id:stationId, entry:station, motion:motion };
                    });
            })).then(function(stationMotions) {
                var vectorNames = Object.keys(motionManifest.vectors || {});
                if (!vectorNames.length) throw new Error('gym_vectors_missing');
                return Promise.all(vectorNames.map(function(name) {
                    var vector = motionManifest.vectors[name];
                    var expectedHash = vector.sha256
                        || (motionManifest.outputs && motionManifest.outputs[vector.uri]);
                    return loadVerifiedSvg(vector.uri, expectedHash, manifestUrl, 'gym_vector')
                        .then(function(image) {
                            return { name:name, image:image, bounds:vector.bounds };
                        });
                })).then(function(vectors) {
                    var vectorMap = Object.create(null);
                    vectors.forEach(function(vector) { vectorMap[vector.name] = vector; });
                    var dressupUrl = assetUrl(
                        motionManifest.dressupManifestUri || '../dressup/manifest.json',
                        manifestUrl);
                    if (!root.DressupDollRenderer
                            || typeof root.DressupDollRenderer.loadManifest !== 'function') {
                        throw new Error('dressup_renderer_unavailable');
                    }
                    return root.DressupDollRenderer.loadManifest(dressupUrl).then(function(dressupManifest) {
                        if (!dressupManifest || !dressupManifest.skinKeys
                                || !dressupManifest.items || !dressupManifest.rigs
                                || !dressupManifest.rigs.battle) {
                            throw new Error('dressup_manifest_contract');
                        }
                        var stationPackages = Object.create(null);
                        stationMotions.forEach(function(record) {
                            Object.keys(record.motion.vectors).forEach(function(name) {
                                if (!vectorMap[name] || record.motion.vectors[name].sha256
                                        !== motionManifest.vectors[name].sha256) {
                                    throw new Error('gym_station_vector_mismatch:' + record.id);
                                }
                            });
                            stationPackages[record.id] = {
                                motion:record.motion,
                                frames:compileFrames(record.motion, record.entry.frameCount),
                                frameCount:record.entry.frameCount,
                                frameRate:record.entry.frameRate,
                                label:record.entry.label,
                                vectorMap:vectorMap,
                                dressup:dressupManifest
                            };
                        });
                        packageData = {
                            manifestUrl:manifestUrl,
                            manifestBaseUrl:new URL('.', manifestUrl).href,
                            motionManifest:motionManifest,
                            dressup:dressupManifest,
                            vectorMap:vectorMap,
                            stations:stationPackages
                        };
                        return packageData;
                    });
                });
            });
        });
    }

    function validateMotion(motion, frameCount) {
        var componentBindings = motion.componentBindings;
        var vectorNames = motion.vectors;
        for (var layerIndex = 0; layerIndex < motion.layers.length; layerIndex++) {
            var layer = motion.layers[layerIndex];
            if (!Array.isArray(layer.keyframes)) throw new Error('motion_keyframes_missing');
            layer.keyframes.forEach(function(keyframe) {
                if (!Number.isInteger(keyframe.loopStart) || !Number.isInteger(keyframe.loopEndExclusive)
                        || keyframe.loopStart < 0 || keyframe.loopEndExclusive > frameCount
                        || keyframe.loopStart >= keyframe.loopEndExclusive
                        || !Array.isArray(keyframe.elements)) {
                    throw new Error('motion_keyframe_range');
                }
                keyframe.elements.forEach(function(element) {
                    if (!element || typeof element.libraryItemName !== 'string'
                            || !matrixOf(element.matrix)) throw new Error('motion_element_invalid');
                    var name = element.libraryItemName;
                    var isComponent = name.indexOf(BODY_PREFIX) === 0
                        && Object.prototype.hasOwnProperty.call(componentBindings, name.slice(BODY_PREFIX.length));
                    var isVector = Object.prototype.hasOwnProperty.call(vectorNames, name);
                    if (!isComponent && !isVector) throw new Error('motion_symbol_unresolved:' + name);
                });
            });
        }
        var vectorKeys = Object.keys(vectorNames);
        if (!vectorKeys.length) throw new Error('motion_vectors_empty');
        vectorKeys.forEach(function(name) {
            var bounds = vectorNames[name] && vectorNames[name].bounds;
            if (!Array.isArray(bounds) || bounds.length !== 4
                    || !bounds.every(Number.isFinite)
                    || !(bounds[2] > bounds[0]) || !(bounds[3] > bounds[1])) {
                throw new Error('motion_vector_bounds:' + name);
            }
        });
    }

    function compileFrames(motion, frameCount) {
        var frames = [];
        for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
            var frameLayers = [];
            motion.layers.forEach(function(layer) {
                if (layer.visible === false) return;
                var keyframe = null;
                for (var i = 0; i < layer.keyframes.length; i++) {
                    var candidate = layer.keyframes[i];
                    if (frameIndex >= candidate.loopStart && frameIndex < candidate.loopEndExclusive) {
                        keyframe = candidate;
                        break;
                    }
                }
                if (!keyframe || !keyframe.elements || !keyframe.elements.length) return;
                frameLayers.push({
                    index:Number(layer.index),
                    name:String(layer.name || ''),
                    elements:keyframe.elements.filter(function(element) { return element.sourceVisible !== false; })
                });
            });
            frames.push(frameLayers);
        }
        return frames;
    }

    function matrixOf(value) {
        var m = value && value.values ? value.values : value;
        if (Array.isArray(m) && m.length >= 6) {
            var arrayValues = m.slice(0, 6).map(Number);
            return arrayValues.every(Number.isFinite) ? arrayValues : null;
        }
        if (m && typeof m === 'object') {
            var values = ['a','b','c','d','tx','ty'].map(function(key, index) {
                if (m[key] !== undefined) return Number(m[key]);
                return [1,0,0,1,0,0][index];
            });
            return values.every(Number.isFinite) ? values : null;
        }
        if (!value || value.explicit === false) return [1,0,0,1,0,0];
        return null;
    }

    function identityMatrix() { return [1,0,0,1,0,0]; }

    function multiplyMatrix(left, right) {
        return [
            left[0] * right[0] + left[2] * right[1],
            left[1] * right[0] + left[3] * right[1],
            left[0] * right[2] + left[2] * right[3],
            left[1] * right[2] + left[3] * right[3],
            left[0] * right[4] + left[2] * right[5] + left[4],
            left[1] * right[4] + left[3] * right[5] + left[5]
        ];
    }

    function transformPoint(matrix, x, y) {
        return [matrix[0] * x + matrix[2] * y + matrix[4], matrix[1] * x + matrix[3] * y + matrix[5]];
    }

    function finiteBounds(bounds) {
        return bounds && bounds.length === 4 && bounds.every(Number.isFinite)
            && bounds[2] > bounds[0] && bounds[3] > bounds[1];
    }

    function expandBounds(target, bounds, matrix) {
        if (!finiteBounds(bounds)) return;
        [[bounds[0],bounds[1]],[bounds[2],bounds[1]],[bounds[0],bounds[3]],[bounds[2],bounds[3]]]
            .forEach(function(point) {
                var transformed = transformPoint(matrix, point[0], point[1]);
                target.minX = Math.min(target.minX, transformed[0]);
                target.minY = Math.min(target.minY, transformed[1]);
                target.maxX = Math.max(target.maxX, transformed[0]);
                target.maxY = Math.max(target.maxY, transformed[1]);
            });
    }

    function readPortrait(portrait) {
        if (!portrait || typeof portrait !== 'object' || Array.isArray(portrait)
                || (portrait.gender !== 'male' && portrait.gender !== 'female')
                || typeof portrait.hair !== 'string' || !portrait.hair.trim()
                || typeof portrait.face !== 'string' || !portrait.face.trim()
                || !portrait.equipment || typeof portrait.equipment !== 'object'
                || Array.isArray(portrait.equipment)) return null;
        var equipment = {};
        Object.keys(portrait.equipment).sort().forEach(function(slot) {
            var itemName = portrait.equipment[slot];
            if (typeof itemName === 'string' && itemName.trim()) equipment[slot] = itemName.trim();
        });
        return {
            gender:portrait.gender,
            hair:portrait.hair.trim(),
            face:portrait.face.trim(),
            equipment:equipment
        };
    }

    function portraitKey(portrait) {
        var normalized = readPortrait(portrait);
        if (!normalized) return '';
        return JSON.stringify([
            normalized.gender,
            normalized.face,
            normalized.hair,
            Object.keys(normalized.equipment).sort().map(function(slot) {
                return [slot, normalized.equipment[slot]];
            })
        ]);
    }

    function allFieldsUsed(motionPackage) {
        var fields = Object.create(null);
        Object.keys(motionPackage.motion.componentBindings).forEach(function(component) {
            var binding = motionPackage.motion.componentBindings[component];
            (binding.fields || []).forEach(function(field) { fields[field] = true; });
            (binding.bindings || []).forEach(function(value) { if (value && value.field) fields[value.field] = true; });
        });
        return fields;
    }

    function runtimeVariant(entry, attackMode) {
        if (!entry || !entry.runtimeVariants || !entry.conditionalVisibility) return entry;
        var condition = entry.conditionalVisibility;
        if (condition.property !== '攻击模式') return entry;
        var visible = condition.visibleWhen || [];
        if (visible.indexOf(attackMode) >= 0) return entry;
        var variant = entry.runtimeVariants[condition.hiddenVariant || 'neutral'];
        return variant && variant.export ? variant : entry;
    }

    function extractAssetEntry(entry, key, matrix) {
        var chosen = runtimeVariant(entry, '空手');
        if (!chosen || !chosen.export) return null;
        var frames = root.AssetTimeline && root.AssetTimeline.playbackFrames
            ? root.AssetTimeline.playbackFrames(chosen)
            : (chosen.frames || []);
        if (!frames.length && chosen.export.uri) {
            frames = [{
                uri:chosen.export.uri,
                width:chosen.export.width,
                height:chosen.export.height,
                originX:0,
                originY:0
            }];
        }
        if (!frames.length || !frames.some(function(frame) { return frame && typeof frame.uri === 'string'; })) return null;
        return {
            key:key,
            entry:chosen,
            matrix:matrix || identityMatrix(),
            zoom:Number(chosen.export.zoom) > 0 ? Number(chosen.export.zoom) : 1,
            frames:frames
        };
    }

    function findBasicHolder(dressup, gender, field) {
        var rigGender = dressup.rigs && dressup.rigs.battle
            && dressup.rigs.battle.genders && dressup.rigs.battle.genders[gender];
        var pose = rigGender && rigGender.states && rigGender.states['空手站立'];
        var holders = pose && pose.holders;
        if (!Array.isArray(holders)) return null;
        for (var i = 0; i < holders.length; i++) {
            if (holders[i] && holders[i].field === field) return holders[i];
        }
        return null;
    }

    function buildPortraitAssets(portrait, motionPackage) {
        if (!root.CharacterAppearancePreview
                || typeof root.CharacterAppearancePreview.buildStateFromEquipment !== 'function') return null;
        var gender = portrait.gender === 'female' ? '女' : '男';
        var appearance = { '脸型':portrait.face, '发型':portrait.hair };
        var state = root.CharacterAppearancePreview.buildStateFromEquipment(
            motionPackage.dressup,
            { gender:gender, equipment:portrait.equipment, appearance:appearance, rig:'battle', stateLabel:'空手站立' });
        if (!state || !state.keyMap || state.keyMap['脸型'] !== portrait.face || !state.keyMap['发型']) return null;

        var usedFields = allFieldsUsed(motionPackage);
        var equipmentSlots = Object.keys(portrait.equipment);
        for (var equipmentIndex = 0; equipmentIndex < equipmentSlots.length; equipmentIndex++) {
            var slot = equipmentSlots[equipmentIndex];
            var itemName = portrait.equipment[slot];
            var item = motionPackage.dressup.items[itemName];
            if (!item || item.use !== slot) return null;
            // 健身动作按空手姿态绘制；已装备武器收起。
            if (STOWED_WEAPON_SLOTS[slot]) continue;
            var genderFields = item && item.fieldsByGender && item.fieldsByGender[gender];
            if (!genderFields || !Object.keys(genderFields).length) {
                // 目录明确无 dressup 的装备本来就没有可画分件，例如新手军牌。
                if (item.dressup === '' && (!item.fieldsByGender
                        || Object.keys(item.fieldsByGender).length === 0)) continue;
                return null;
            }
            var itemFields = Object.keys(genderFields);
            for (var itemFieldIndex = 0; itemFieldIndex < itemFields.length; itemFieldIndex++) {
                if (!usedFields[itemFields[itemFieldIndex]]) return null;
            }
        }

        var assetsByField = Object.create(null);
        var requiredFields = Object.create(null);
        Object.keys(motionPackage.motion.componentBindings).forEach(function(component) {
            var binding = motionPackage.motion.componentBindings[component];
            var fields = binding.fields || [];
            fields.forEach(function(field) { requiredFields[field] = true; });
            (binding.bindings || []).forEach(function(reference) {
                if (reference && reference.field) requiredFields[reference.field] = true;
            });
        });

        var rigGender = gender;
        Object.keys(requiredFields).forEach(function(field) {
            if (assetsByField[field]) return;
            if (WEAPON_FIELDS[field]) {
                assetsByField[field] = null;
                return;
            }
            var skinKey = state.keyMap[field];
            if (skinKey) {
                assetsByField[field] = extractAssetEntry(
                    motionPackage.dressup.skinKeys[skinKey], skinKey, null);
                if (!assetsByField[field]) assetsByField[field] = null;
                return;
            }
            if (WEAPON_FIELDS[field] || field === '面具') {
                assetsByField[field] = null;
                return;
            }
            var holder = findBasicHolder(motionPackage.dressup, rigGender, field);
            assetsByField[field] = holder && holder.basic
                ? extractAssetEntry(holder.basic, 'basic:' + holder.basic.linkageId, matrixOf(holder.basic.matrix))
                : null;
        });

        for (var requiredIndex = 0; requiredIndex < REQUIRED_BODY_FIELDS.length; requiredIndex++) {
            var requiredField = REQUIRED_BODY_FIELDS[requiredIndex];
            if (!assetsByField[requiredField]) return null;
        }
        if (state.hairHidden !== true && !assetsByField['发型']) return null;
        var usedKeys = Object.create(null);
        Object.keys(assetsByField).forEach(function(field) {
            var record = assetsByField[field];
            if (record) usedKeys[record.key] = true;
        });
        return {
            key:portraitKey(portrait),
            gender:gender,
            portrait:portrait,
            state:state,
            assetsByField:assetsByField,
            usedRecords:Object.keys(usedKeys).map(function(key) {
                for (var field in assetsByField) {
                    if (Object.prototype.hasOwnProperty.call(assetsByField, field)
                            && assetsByField[field] && assetsByField[field].key === key) return assetsByField[field];
                }
                return null;
            }).filter(Boolean),
            bounds:{ minX:Infinity, minY:Infinity, maxX:-Infinity, maxY:-Infinity }
        };
    }

    function collectEntryUris(entry, urls, visited) {
        if (!entry || typeof entry !== 'object' || visited.indexOf(entry) >= 0) return;
        visited.push(entry);
        var frames = root.AssetTimeline && root.AssetTimeline.playbackFrames
            ? root.AssetTimeline.playbackFrames(entry)
            : (entry.frames || []);
        frames.forEach(function(frame) { if (frame && frame.uri) urls[frame.uri] = true; });
        if (entry.export && entry.export.uri) urls[entry.export.uri] = true;
        var nested = entry.export && entry.export.nestedAnimation;
        (nested && nested.layers ? nested.layers : []).forEach(function(layer) {
            collectEntryUris(layer, urls, visited);
        });
    }

    function frameBounds(entry, frame, zoom) {
        var exportData = entry && entry.export || {};
        var scale = Number(zoom) > 0 ? Number(zoom) : (Number(exportData.zoom) > 0 ? Number(exportData.zoom) : 1);
        var width = Number(frame && frame.width || exportData.width || 0) / scale;
        var height = Number(frame && frame.height || exportData.height || 0) / scale;
        var originX = Number(frame && frame.originX || 0) / scale;
        var originY = Number(frame && frame.originY || 0) / scale;
        if (!(width > 0) || !(height > 0)) return null;
        return [-originX, -originY, width - originX, height - originY];
    }

    function recordBounds(record, bounds, parentMatrix, visited) {
        if (!record || !record.entry) return;
        visited = visited || [];
        if (visited.indexOf(record.entry) >= 0) return;
        visited.push(record.entry);
        var matrix = multiplyMatrix(parentMatrix, record.matrix || identityMatrix());
        var frames = record.frames || [];
        frames.forEach(function(frame) { expandBounds(bounds, frameBounds(record.entry, frame, record.zoom), matrix); });
        var nested = record.entry.export && record.entry.export.nestedAnimation;
        (nested && nested.layers ? nested.layers : []).forEach(function(layer) {
            var layerMatrix = matrixOf(layer.matrix) || identityMatrix();
            var nestedRecord = extractAssetEntry(layer, record.key + ':nested', null);
            if (nestedRecord) recordBounds(nestedRecord, bounds, multiplyMatrix(matrix, layerMatrix), visited.slice());
        });
    }

    function measurePortrait(motionPackage, portraitAssets) {
        var bounds = portraitAssets.bounds;
        var vectorMap = motionPackage.vectorMap;
        var bindings = motionPackage.motion.componentBindings;
        motionPackage.frames.forEach(function(frameLayers) {
            frameLayers.forEach(function(layer) {
                layer.elements.forEach(function(element) {
                    var elementMatrix = matrixOf(element.matrix) || identityMatrix();
                    var name = element.libraryItemName;
                    var vector = vectorMap[name];
                    if (vector) {
                        expandBounds(bounds, vector.bounds, elementMatrix);
                        return;
                    }
                    if (name.indexOf(BODY_PREFIX) !== 0) return;
                    var binding = bindings[name.slice(BODY_PREFIX.length)];
                    if (!binding) return;
                    var wrapperMatrix = matrixOf(binding.wrapperMatrix) || identityMatrix();
                    (binding.fields || []).forEach(function(field) {
                        var record = portraitAssets.assetsByField[field];
                        if (record) recordBounds(record, bounds,
                            multiplyMatrix(elementMatrix, wrapperMatrix), []);
                    });
                });
            });
        });
        if (!Number.isFinite(bounds.minX) || !Number.isFinite(bounds.minY)
                || !Number.isFinite(bounds.maxX) || !Number.isFinite(bounds.maxY)
                || !(bounds.maxX > bounds.minX) || !(bounds.maxY > bounds.minY)) return null;
        var paddingX = (bounds.maxX - bounds.minX) * 0.025;
        var paddingY = (bounds.maxY - bounds.minY) * 0.025;
        bounds.minX -= paddingX;
        bounds.minY -= paddingY;
        bounds.maxX += paddingX;
        bounds.maxY += paddingY;
        return bounds;
    }

    function preloadPortrait(portraitAssets, motionPackage) {
        var urls = Object.create(null);
        portraitAssets.usedRecords.forEach(function(record) {
            collectEntryUris(record.entry, urls, []);
        });
        var promises = Object.keys(urls).map(function(uri) {
            return loadImage(assetUrl(uri, motionPackage.dressup.__baseUrl));
        });
        return Promise.all(promises).then(function() {
            var bounds = measurePortrait(motionPackage, portraitAssets);
            if (!bounds) return false;
            portraitAssets.bounds = bounds;
            return true;
        });
    }

    function ready() {
        if (packageData) return Promise.resolve(packageData);
        if (!packagePromise) {
            packagePromise = loadPackage().catch(function(error) {
                packagePromise = null;
                throw error;
            });
        }
        return packagePromise;
    }

    function preparePortrait(portrait, stationId) {
        stationId = stationId || 'dummy';
        var baseKey = portraitKey(portrait);
        if (!baseKey || !Object.prototype.hasOwnProperty.call(MOTION_SCHEMAS, stationId)) {
            return Promise.resolve(false);
        }
        var key = stationId + ':' + baseKey;
        if (preparedPortraits[key]) return Promise.resolve(preparedPortraits[key].ready === true);
        if (portraitPromises[key]) return portraitPromises[key];
        var normalized = readPortrait(portrait);
        portraitPromises[key] = ready().then(function(currentPackage) {
            var stationPackage = currentPackage.stations[stationId];
            if (!stationPackage) return false;
            var resolved = buildPortraitAssets(normalized, stationPackage);
            if (!resolved) return false;
            return preloadPortrait(resolved, stationPackage).then(function(success) {
                if (success) {
                    resolved.ready = true;
                    preparedPortraits[key] = resolved;
                    return true;
                }
                return false;
            });
        }).catch(function() { return false; }).then(function(success) {
            if (!success) delete preparedPortraits[key];
            delete portraitPromises[key];
            return success;
        });
        return portraitPromises[key];
    }

    function canRenderPortrait(portrait, stationId) {
        stationId = stationId || 'dummy';
        var baseKey = portraitKey(portrait);
        var key = stationId + ':' + baseKey;
        var stationPackage = packageData && packageData.stations[stationId];
        return !!(key && preparedPortraits[key] && preparedPortraits[key].ready === true
            && stationPackage && stationPackage.frames
            && stationPackage.frames.length === stationPackage.frameCount);
    }

    function urlForFrame(frame, entry) {
        if (!frame || typeof frame.uri !== 'string') return '';
        return assetUrl(frame.uri, packageData.dressup.__baseUrl);
    }

    function selectedAssetFrame(record, elapsedMs) {
        var entry = record.entry;
        if (root.AssetTimeline && typeof root.AssetTimeline.select === 'function') {
            var selection = root.AssetTimeline.select(entry, elapsedMs, { defaultFps:24, fallbackFps:24 });
            return selection.frame || record.frames[0] || null;
        }
        return record.frames[0] || null;
    }

    function drawAssetEntry(ctx, entry, elapsedMs) {
        var nested = entry.export && entry.export.nestedAnimation;
        var layers = nested && Array.isArray(nested.layers) ? nested.layers : [];
        layers.forEach(function(layer) {
            if (layer.drawOrder !== 'under') return;
            ctx.save();
            var matrix = matrixOf(layer.matrix) || identityMatrix();
            ctx.transform(matrix[0],matrix[1],matrix[2],matrix[3],matrix[4],matrix[5]);
            drawAssetEntry(ctx, layer, elapsedMs);
            ctx.restore();
        });
        var frames = root.AssetTimeline && root.AssetTimeline.playbackFrames
            ? root.AssetTimeline.playbackFrames(entry)
            : (entry.frames || []);
        var selected = root.AssetTimeline && root.AssetTimeline.select
            ? root.AssetTimeline.select(entry, elapsedMs, { defaultFps:24, fallbackFps:24 }).frame
            : (frames[0] || null);
        if (selected && selected.uri) {
            var url = assetUrl(selected.uri, packageData.dressup.__baseUrl);
            var image = imagePromises[url] && imagePromises[url].image;
            if (!image) {
                // The Image object is retained on the fulfilled preload promise by ensureImageEntry.
                image = loadedImageFor(url);
            }
            if (image && image.complete && image.naturalWidth > 0) {
                var exportData = entry.export || {};
                var zoom = Number(exportData.zoom) > 0 ? Number(exportData.zoom) : 1;
                var width = Number(selected.width || exportData.width || image.naturalWidth) / zoom;
                var height = Number(selected.height || exportData.height || image.naturalHeight) / zoom;
                var originX = Number(selected.originX || 0) / zoom;
                var originY = Number(selected.originY || 0) / zoom;
                ctx.drawImage(image, -originX, -originY, width, height);
            }
        }
        layers.forEach(function(layer) {
            if (layer.drawOrder !== 'over') return;
            ctx.save();
            var matrix = matrixOf(layer.matrix) || identityMatrix();
            ctx.transform(matrix[0],matrix[1],matrix[2],matrix[3],matrix[4],matrix[5]);
            drawAssetEntry(ctx, layer, elapsedMs);
            ctx.restore();
        });
    }

    function imageFor(url) {
        var promise = imagePromises[url];
        if (!promise) return null;
        return promise.image || null;
    }

    function loadedImageFor(url) {
        return imageFor(url);
    }

    function drawPortraitField(ctx, record, elementMatrix, wrapperMatrix, elapsedMs) {
        if (!record || !record.entry) return;
        ctx.save();
        var composed = multiplyMatrix(elementMatrix, wrapperMatrix || identityMatrix());
        composed = multiplyMatrix(composed, record.matrix || identityMatrix());
        ctx.transform(composed[0],composed[1],composed[2],composed[3],composed[4],composed[5]);
        drawAssetEntry(ctx, record.entry, elapsedMs);
        ctx.restore();
    }

    function drawVector(ctx, vector, matrix) {
        if (!vector || !vector.image || !finiteBounds(vector.bounds)) return;
        var bounds = vector.bounds;
        ctx.save();
        ctx.transform(matrix[0],matrix[1],matrix[2],matrix[3],matrix[4],matrix[5]);
        ctx.drawImage(vector.image, bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1]);
        ctx.restore();
    }

    function renderTimelineFrame(ctx, stationPackage, frameIndex, portraitAssets, elapsedMs) {
        var frameLayers = stationPackage.frames[frameIndex];
        for (var layerIndex = frameLayers.length - 1; layerIndex >= 0; layerIndex--) {
            var layer = frameLayers[layerIndex];
            for (var elementIndex = 0; elementIndex < layer.elements.length; elementIndex++) {
                var element = layer.elements[elementIndex];
                var name = element.libraryItemName;
                var elementMatrix = matrixOf(element.matrix) || identityMatrix();
                var vector = stationPackage.vectorMap[name];
                if (vector) {
                    drawVector(ctx, vector, elementMatrix);
                    continue;
                }
                if (name.indexOf(BODY_PREFIX) !== 0) continue;
                var componentName = name.slice(BODY_PREFIX.length);
                var binding = stationPackage.motion.componentBindings[componentName];
                if (!binding) continue;
                var fields = Array.isArray(binding.fields) ? binding.fields : [];
                var uniqueFields = Object.create(null);
                var wrapperMatrix = matrixOf(binding.wrapperMatrix) || identityMatrix();
                fields.forEach(function(field) {
                    if (uniqueFields[field]) return;
                    uniqueFields[field] = true;
                    drawPortraitField(ctx, portraitAssets.assetsByField[field], elementMatrix, wrapperMatrix, elapsedMs);
                });
                if (!fields.length && stationPackage.vectorMap[name]) drawVector(ctx, stationPackage.vectorMap[name], elementMatrix);
            }
        }
    }

    function create(container, options) {
        options = options || {};
        var portrait = options.portrait;
        var stationId = options.stationId || 'dummy';
        var key = stationId + ':' + portraitKey(portrait);
        var portraitAssets = key && preparedPortraits[key];
        var stationPackage = packageData && packageData.stations[stationId];
        if (!stationPackage || !canRenderPortrait(portrait, stationId) || !portraitAssets) {
            throw new Error('gym_portrait_not_prepared');
        }
        var canvas = document.createElement('canvas');
        canvas.className = 'gym-motion-canvas';
        canvas.setAttribute('aria-label', stationPackage.label + '训练动作循环');
        container.appendChild(canvas);
        var context = canvas.getContext('2d');
        if (!context) {
            container.removeChild(canvas);
            throw new Error('canvas_unavailable');
        }

        var destroyed = false;
        var failed = false;
        var documentVisible = document.visibilityState !== 'hidden';
        var windowFocused = typeof document.hasFocus === 'function' ? document.hasFocus() : true;
        var paused = !(documentVisible && windowFocused);
        var frameRequest = null;
        var resizeObserver = null;
        var segmentStartedAt = 0;
        var elapsedBeforePause = 0;
        var playbackRate = 1;
        var currentFrame = -1;
        var renderedFrameCount = 0;
        var lastWidth = 0;
        var lastHeight = 0;
        var lastDpr = 0;
        var reduceMotion = !!(window.matchMedia
            && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
        if (reduceMotion) paused = true;

        function active() { return !destroyed && documentVisible && windowFocused && !reduceMotion; }

        function resizeCanvas() {
            if (destroyed) return false;
            var rect = container.getBoundingClientRect();
            var width = Math.max(1, Math.round(rect.width));
            var height = Math.max(1, Math.round(rect.height));
            var dpr = Math.max(1, Number(window.devicePixelRatio) || 1);
            if (width !== lastWidth || height !== lastHeight || dpr !== lastDpr) {
                lastWidth = width;
                lastHeight = height;
                lastDpr = dpr;
                canvas.width = Math.max(1, Math.round(width * dpr));
                canvas.height = Math.max(1, Math.round(height * dpr));
                canvas.style.width = '100%';
                canvas.style.height = '100%';
            }
            return true;
        }

        function renderFrame(frameIndex, elapsedMs) {
            if (destroyed || !resizeCanvas()) return;
            var width = lastWidth;
            var height = lastHeight;
            var dpr = lastDpr;
            context.setTransform(dpr,0,0,dpr,0,0);
            context.clearRect(0,0,width,height);
            var bounds = portraitAssets.bounds;
            var contentWidth = bounds.maxX - bounds.minX;
            var contentHeight = bounds.maxY - bounds.minY;
            var scale = Math.min((width - 20) / contentWidth, (height - 20) / contentHeight);
            if (!(scale > 0) || !Number.isFinite(scale)) scale = 1;
            var translateX = (width - contentWidth * scale) / 2 - bounds.minX * scale;
            var translateY = (height - contentHeight * scale) / 2 - bounds.minY * scale;
            context.save();
            context.translate(translateX, translateY);
            context.scale(scale, scale);
            renderTimelineFrame(context, stationPackage, frameIndex, portraitAssets, elapsedMs);
            context.restore();
            currentFrame = frameIndex;
            renderedFrameCount++;
        }

        function currentElapsed(timestamp) {
            return elapsedBeforePause + Math.max(0, timestamp - segmentStartedAt) * playbackRate;
        }

        function setPlaybackRate(rate) {
            var next = Number(rate);
            if (!Number.isFinite(next) || next <= 0) return false;
            next = Math.min(3, Math.max(0.2, next));
            if (destroyed) return false;
            if (frameRequest !== null) {
                var now = performance.now();
                elapsedBeforePause = currentElapsed(now);
                segmentStartedAt = now;
            }
            playbackRate = next;
            return true;
        }

        function stopLoop(preserveTime) {
            if (frameRequest !== null) {
                if (preserveTime) elapsedBeforePause = currentElapsed(performance.now());
                window.cancelAnimationFrame(frameRequest);
                frameRequest = null;
            }
            paused = true;
        }

        function tick(timestamp) {
            frameRequest = null;
            if (!active()) {
                paused = true;
                return;
            }
            try {
                var elapsed = currentElapsed(timestamp);
                var nextFrame = Math.floor(elapsed * stationPackage.frameRate / 1000)
                    % stationPackage.frameCount;
                if (nextFrame !== currentFrame) renderFrame(nextFrame, elapsed);
                frameRequest = window.requestAnimationFrame(tick);
            } catch (error) {
                fail(error);
            }
        }

        function startLoop() {
            if (destroyed || frameRequest !== null || !active()) return;
            segmentStartedAt = performance.now();
            paused = false;
            frameRequest = window.requestAnimationFrame(tick);
        }

        function refreshActivity() {
            if (active()) startLoop();
            else stopLoop(true);
        }

        function onVisibilityChange() {
            documentVisible = document.visibilityState !== 'hidden';
            refreshActivity();
        }
        function onBlur() {
            windowFocused = false;
            refreshActivity();
        }
        function onFocus() {
            windowFocused = true;
            refreshActivity();
        }
        function onResize() {
            if (destroyed) return;
            try { renderFrame(Math.max(0,currentFrame), elapsedBeforePause); }
            catch (error) { fail(error); }
        }

        window.addEventListener('blur', onBlur);
        window.addEventListener('focus', onFocus);
        document.addEventListener('visibilitychange', onVisibilityChange);
        if (typeof ResizeObserver !== 'undefined') {
            resizeObserver = new ResizeObserver(onResize);
            resizeObserver.observe(container);
        } else {
            window.addEventListener('resize', onResize);
        }

        activeInstances++;
        createdInstances++;
        try {
            renderFrame(0, 0);
            if (!reduceMotion) startLoop();
        } catch (error) {
            fail(error);
            throw error;
        }

        function destroyInstance() {
            if (destroyed) return;
            destroyed = true;
            if (frameRequest !== null) window.cancelAnimationFrame(frameRequest);
            frameRequest = null;
            if (resizeObserver) resizeObserver.disconnect();
            window.removeEventListener('blur', onBlur);
            window.removeEventListener('focus', onFocus);
            document.removeEventListener('visibilitychange', onVisibilityChange);
            window.removeEventListener('resize', onResize);
            if (canvas.parentNode) canvas.parentNode.removeChild(canvas);
            context.clearRect(0,0,canvas.width,canvas.height);
            activeInstances = Math.max(0, activeInstances - 1);
            destroyedInstances++;
        }

        function fail(error) {
            if (destroyed) return;
            failed = true;
            destroyInstance();
            if (typeof options.onFailure === 'function') {
                try { options.onFailure(error); }
                catch (callbackError) { console.error('[GymMotionRenderer] failure callback failed:', callbackError); }
            }
        }

        return {
            destroy:destroyInstance,
            setPlaybackRate:setPlaybackRate,
            debugState:function() {
                return {
                    frameIndex:currentFrame,
                    frameCount:stationPackage.frameCount,
                    frameRate:stationPackage.frameRate,
                    renderedFrameCount:renderedFrameCount,
                    playbackRate:playbackRate,
                    paused:paused,
                    focused:windowFocused,
                    visible:documentVisible,
                    failed:failed,
                    destroyed:destroyed
                };
            }
        };
    }

    var api = {
        ready:ready,
        preparePortrait:preparePortrait,
        canRenderPortrait:canRenderPortrait,
        create:create,
        getDebugStats:function() {
            return {
                ready:!!packageData,
                activeInstances:activeInstances,
                createdInstances:createdInstances,
                destroyedInstances:destroyedInstances,
                preparedPortraitCount:Object.keys(preparedPortraits).length
            };
        },
        _setAssetRootForTests:function(value) {
            if (packageData || packagePromise) throw new Error('gym_asset_root_already_loaded');
            assetRoot = normalizeAssetRoot(value);
        }
    };
    if (root) root.GymMotionRenderer = api;
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
