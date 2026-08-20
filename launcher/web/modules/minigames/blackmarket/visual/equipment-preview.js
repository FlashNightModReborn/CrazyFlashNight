(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.BlackMarketEquipmentPreview = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var VERSION = "equipment-focus-preview.v3";
    var DEFAULT_SIZE = 384;
    var DEFAULT_CACHE_LIMIT = 18;

    function clampInteger(value, fallback, minimum, maximum) {
        value = Number(value);
        if (!Number.isFinite(value)) value = fallback;
        return Math.max(minimum, Math.min(maximum, Math.round(value)));
    }

    function normalizeGender(value) {
        return value === "女" ? "女" : "男";
    }

    function resolvePlan(source, options) {
        source = source || {};
        options = options || {};
        var gender = normalizeGender(options.gender);
        if (source.kind !== "dressup-paperdoll" && source.kind !== "dressup-weapon") {
            return {
                kind: "icon",
                assetUrl: source.assetUri || "",
                sourceKey: "icon:" + String(source.assetUri || ""),
                sourceKind: "icon",
                autoRotate: true,
                previewGender: null,
                sharpenSource: source.sharpenFallback === true || source.assetKind === "icon-proxy",
                fallbackReason: "direct-icon"
            };
        }
        if (!source.itemName) throw new Error("dressup source is incomplete");
        if (!source.use) throw new Error("dressup equipment use is missing");
        if (source.kind === "dressup-paperdoll" && !source.slot) {
            throw new Error("paper-doll source is incomplete");
        }
        return {
            kind: source.kind,
            itemId: String(source.itemId || ""),
            itemName: String(source.itemName),
            itemType: source.kind === "dressup-weapon" ? "武器" : "防具",
            slot: String(source.slot || ""),
            use: String(source.use),
            actionType: String(source.actionType || ""),
            iconName: String(source.iconName || ""),
            assetUrl: String(source.assetUri || ""),
            assetKind: String(source.assetKind || ""),
            gender: gender,
            sourceKey: [VERSION, source.kind, source.itemId || source.itemName, source.use,
                source.actionType || "", gender].join(":"),
            sourceKind: source.kind,
            autoRotate: source.kind === "dressup-weapon",
            previewGender: gender
        };
    }

    function defaultPortraitApi() {
        if (typeof globalThis !== "undefined" && globalThis.MercPortraits) return globalThis.MercPortraits;
        return null;
    }

    function defaultInspectorApi() {
        if (typeof globalThis !== "undefined" && globalThis.EquipmentInspector) {
            return globalThis.EquipmentInspector;
        }
        return null;
    }

    function create(options) {
        options = options || {};
        var cacheLimit = clampInteger(options.cacheLimit, DEFAULT_CACHE_LIMIT, 2, 48);
        var renderSize = clampInteger(options.size, DEFAULT_SIZE, 192, 1024);
        var cache = {};
        var order = [];
        var pending = {};
        var destroyed = false;

        function touch(key) {
            order = order.filter(function(candidate) { return candidate !== key; });
            order.push(key);
            while (order.length > cacheLimit) delete cache[order.shift()];
        }

        function remember(key, value) {
            if (destroyed) return value;
            cache[key] = value;
            touch(key);
            return value;
        }

        function portraitApi() {
            return options.portraitApi || defaultPortraitApi();
        }

        function inspectorApi() {
            return options.equipmentInspectorApi || defaultInspectorApi();
        }

        function focusSourceFor(plan, gender, manifest, inspector) {
            return inspector.resolveProductSource({
                name: plan.itemName,
                icon: plan.iconName,
                majorType: plan.itemType,
                type: plan.itemType,
                use: plan.use,
                actionType: plan.actionType
            }, gender, manifest);
        }

        function resolvePairGender(sources, renderOptions) {
            if (destroyed) return Promise.reject(new Error("equipment preview renderer destroyed"));
            sources = sources || [];
            var preferred = normalizeGender(renderOptions && renderOptions.gender);
            var plans;
            try {
                plans = sources.map(function(source) {
                    return resolvePlan(source, { gender: preferred });
                }).filter(function(plan) { return plan.kind === "dressup-paperdoll"; });
            } catch (error) {
                return Promise.reject(error);
            }
            if (!plans.length) return Promise.resolve(preferred);
            var portraits = portraitApi();
            var inspector = inspectorApi();
            if (!portraits || typeof portraits.loadManifest !== "function"
                    || !inspector || typeof inspector.resolveProductSource !== "function") {
                return Promise.reject(new Error("equipment focus resolver unavailable"));
            }
            return Promise.resolve(portraits.loadManifest()).then(function(manifest) {
                var genders = [preferred, preferred === "男" ? "女" : "男"];
                for (var genderIndex = 0; genderIndex < genders.length; genderIndex += 1) {
                    var gender = genders[genderIndex];
                    var allRenderable = plans.every(function(plan) {
                        var focused = focusSourceFor(plan, gender, manifest, inspector);
                        return !!(focused && focused.kind === "armor");
                    });
                    if (allRenderable) return gender;
                }
                throw new Error("paired armor has no common equipment-focus gender");
            });
        }

        function resolve(source, renderOptions) {
            if (destroyed) return Promise.reject(new Error("equipment preview renderer destroyed"));
            var plan;
            try {
                plan = resolvePlan(source, renderOptions);
            } catch (error) {
                return Promise.reject(error);
            }
            if (plan.kind === "icon") return Promise.resolve(plan);
            if (cache[plan.sourceKey]) {
                touch(plan.sourceKey);
                return Promise.resolve(cache[plan.sourceKey]);
            }
            if (pending[plan.sourceKey]) return pending[plan.sourceKey];
            var portraits = portraitApi();
            var inspector = inspectorApi();
            if (!portraits || typeof portraits.loadManifest !== "function"
                    || typeof portraits.renderStateDataUrl !== "function") {
                return Promise.reject(new Error("paper-doll portrait renderer unavailable"));
            }
            if (!inspector || typeof inspector.resolveProductSource !== "function"
                    || typeof inspector.buildStateForSource !== "function") {
                return Promise.reject(new Error("equipment focus resolver unavailable"));
            }
            var promise = Promise.resolve(portraits.loadManifest()).then(function(manifest) {
                var focusSource = focusSourceFor(plan, plan.gender, manifest, inspector);
                if (plan.kind === "dressup-weapon" && focusSource && focusSource.kind === "icon") {
                    return remember(plan.sourceKey, {
                        kind: "icon",
                        assetUrl: plan.assetUrl,
                        sourceKey: plan.sourceKey + ":fallback:" + String(focusSource.reason || "unresolved"),
                        sourceKind: "icon",
                        sourceComposition: "sharpened-icon-fallback",
                        focusFitFields: [],
                        focusDrawFields: [],
                        autoRotate: true,
                        previewGender: null,
                        renderSize: 0,
                        sharpenSource: true,
                        fallbackReason: String(focusSource.reason || "unresolved")
                    });
                }
                var expectedKind = plan.kind === "dressup-weapon" ? "weapon" : "armor";
                if (!focusSource || focusSource.kind !== expectedKind) {
                    throw new Error("equipment focus unavailable: "
                        + String(focusSource && focusSource.reason || "unresolved"));
                }
                var focusState = inspector.buildStateForSource(focusSource, manifest);
                if (!focusState || (focusSource.kind === "armor"
                        && (!focusState.fitFields || !focusState.fitFields.length
                            || !focusState.drawFields || !focusState.drawFields.length))) {
                    throw new Error("equipment focus state is incomplete");
                }
                var focusFitFields = focusState.fitFields && focusState.fitFields.length
                    ? focusState.fitFields.slice(0) : (focusSource.field ? [focusSource.field] : []);
                var focusDrawFields = focusState.drawFields && focusState.drawFields.length
                    ? focusState.drawFields.slice(0) : focusFitFields.slice(0);
                return Promise.resolve(portraits.renderStateDataUrl(focusState, {
                    size: renderSize
                })).then(function(assetUrl) {
                    if (!assetUrl || !/^data:image\/png;base64,/.test(assetUrl)) {
                        throw new Error("paper-doll focus returned no PNG");
                    }
                    return remember(plan.sourceKey, {
                        kind: plan.kind,
                        assetUrl: assetUrl,
                        sourceKey: plan.sourceKey + ":" + assetUrl.length,
                        sourceKind: plan.sourceKind,
                        sourceComposition: focusSource.kind === "weapon"
                            ? "equipment-inspector-" + String(focusSource.composition || "single")
                            : "equipment-inspector-focus",
                        focusFitFields: focusFitFields,
                        focusDrawFields: focusDrawFields,
                        autoRotate: plan.autoRotate,
                        previewGender: plan.previewGender,
                        renderSize: renderSize,
                        sharpenSource: false,
                        fallbackReason: ""
                    });
                });
            }).finally(function() {
                delete pending[plan.sourceKey];
            });
            pending[plan.sourceKey] = promise;
            return promise;
        }

        return {
            resolve: resolve,
            resolvePairGender: resolvePairGender,
            destroy: function() {
                destroyed = true;
                cache = {};
                order = [];
                pending = {};
            },
            debugState: function() {
                return {
                    version: VERSION,
                    cached: Object.keys(cache).length,
                    pending: Object.keys(pending).length,
                    size: renderSize,
                    destroyed: destroyed
                };
            }
        };
    }

    function validateArmorCoverage(catalog, manifest) {
        var slotByUse = {
            "头部装备": "head",
            "上装装备": "body",
            "手部装备": "hand",
            "下装装备": "leg",
            "脚部装备": "foot"
        };
        var candidates = (catalog && catalog.entries || []).filter(function(entry) {
            return entry.mechanicallyRenderable && entry.type === "防具" && !!slotByUse[entry.use];
        });
        function branchRenderable(item, gender) {
            var fields = item && item.fieldsByGender && item.fieldsByGender[gender];
            if (!fields || Object.keys(fields).length === 0) return false;
            return Object.keys(fields).some(function(field) {
                var skinKey = fields[field];
                var skin = skinKey && manifest.skinKeys && manifest.skinKeys[skinKey];
                return !!(skin && skin.export);
            });
        }
        var availability = candidates.map(function(entry) {
            var item = manifest && manifest.items && manifest.items[entry.name];
            return {
                name: entry.name,
                male: branchRenderable(item, "男"),
                female: branchRenderable(item, "女")
            };
        });
        var missing = availability.filter(function(item) { return !item.male && !item.female; });
        var partialGender = availability.filter(function(item) { return item.male !== item.female; });
        return {
            candidates: candidates.length,
            covered: candidates.length - missing.length,
            missing: missing.map(function(entry) { return entry.name; }),
            partialGender: partialGender.map(function(entry) { return entry.name; }),
            maleOnly: partialGender.filter(function(entry) { return entry.male; }).length,
            femaleOnly: partialGender.filter(function(entry) { return entry.female; }).length
        };
    }

    return {
        VERSION: VERSION,
        DEFAULT_SIZE: DEFAULT_SIZE,
        normalizeGender: normalizeGender,
        resolvePlan: resolvePlan,
        validateArmorCoverage: validateArmorCoverage,
        create: create
    };
});
