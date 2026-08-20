(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.BlackMarketCore = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var CATALOG_SCHEMA = "black-market-shadow-catalog.v1";
    var SNAPSHOT_SCHEMA = "black-market-shadow-public.v1";
    var ALGORITHM_VERSION = "object-sdf-nanobot-sludge.v2";
    var LEVELS = [0, 3, 5, 10];
    // 覆盖率现在按“物品有效 Alpha 像素”计量；旧版全卡几何覆盖率不可直接换算。
    var COVERAGE_BY_LEVEL = { 0: 0.97, 3: 0.84, 5: 0.54, 10: 0.18 };
    var CATEGORY_LABEL = { equipment: "装备", material: "材料", consumable: "消耗品" };
    var PAPER_DOLL_SLOT_BY_USE = {
        "头部装备": "head",
        "上装装备": "body",
        "手部装备": "hand",
        "下装装备": "leg",
        "脚部装备": "foot"
    };
    var MAX_CATALOG_ITEMS = 5000;
    var MAX_RECEIPTS = 64;

    function invariant(condition, message) {
        if (!condition) throw new Error(message);
    }

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function isObject(value) {
        return !!value && typeof value === "object" && !Array.isArray(value);
    }

    function isSafeNonNegativeInteger(value) {
        return Number.isSafeInteger(value) && value >= 0;
    }

    function isSafePositiveInteger(value) {
        return Number.isSafeInteger(value) && value > 0;
    }

    function isSafeString(value, max) {
        return typeof value === "string" && value.length > 0 && value.length <= max;
    }

    function hash32(text) {
        var hash = 2166136261 >>> 0;
        var source = String(text || "");
        var i;
        for (i = 0; i < source.length; i += 1) {
            hash ^= source.charCodeAt(i);
            hash = Math.imul(hash, 16777619) >>> 0;
        }
        return hash >>> 0;
    }

    function createRng(seed) {
        var state = hash32(seed) || 0x9e3779b9;
        return {
            next: function() {
                state ^= state << 13;
                state ^= state >>> 17;
                state ^= state << 5;
                state >>>= 0;
                return state / 4294967296;
            },
            int: function(max) {
                invariant(Number.isInteger(max) && max > 0, "rng max must be positive");
                return Math.floor(this.next() * max);
            }
        };
    }

    function shuffle(values, rng) {
        var out = values.slice();
        var i;
        for (i = out.length - 1; i > 0; i -= 1) {
            var j = rng.int(i + 1);
            var tmp = out[i];
            out[i] = out[j];
            out[j] = tmp;
        }
        return out;
    }

    function validateCatalog(input) {
        invariant(isObject(input), "catalog must be an object");
        invariant(input.schemaVersion === CATALOG_SCHEMA, "catalog schema mismatch");
        invariant(input.shadowOnly === true, "catalog must be shadow-only");
        invariant(input.containsPrivateIdentity === true, "catalog identity boundary missing");
        invariant(input.productionEligibilityDefault === "review", "catalog must default to review");
        invariant(/^[a-f0-9]{64}$/.test(String(input.catalogDigest || "")), "catalog digest invalid");
        invariant(Array.isArray(input.entries) && input.entries.length > 0 && input.entries.length <= MAX_CATALOG_ITEMS,
            "catalog entries out of bounds");
        invariant(isObject(input.stats), "catalog stats missing");
        invariant(isObject(input.source), "catalog source missing");
        invariant(input.source.itemList === "data/items/list.xml", "catalog item-list source invalid");
        invariant(input.source.iconManifest === "launcher/web/icons/manifest.json", "catalog icon source invalid");
        invariant(/^[a-f0-9]{64}$/.test(String(input.source.itemListSha256 || "")), "catalog item-list digest invalid");
        invariant(/^[a-f0-9]{64}$/.test(String(input.source.iconManifestSha256 || "")), "catalog icon digest invalid");
        invariant(isObject(input.stats.mechanicallyRenderableByCategory), "catalog category stats missing");
        invariant(Object.keys(input.stats.mechanicallyRenderableByCategory).sort().join(",")
            === "consumable,equipment,material", "catalog category stats keys invalid");

        var ids = {};
        var mechanicallyRenderable = 0;
        var mechanicallyRenderableByCategory = { equipment: 0, material: 0, consumable: 0 };
        var i;
        for (i = 0; i < input.entries.length; i += 1) {
            var entry = input.entries[i];
            invariant(isObject(entry), "catalog entry must be object");
            invariant(isSafeString(entry.id, 64) && !ids[entry.id], "catalog entry id invalid or duplicated");
            ids[entry.id] = true;
            invariant(isSafeString(entry.name, 256), "catalog name invalid");
            invariant(isSafeString(entry.displayName, 256), "catalog display name invalid");
            invariant(isSafeString(entry.source, 512) && /^data\/items\//.test(entry.source), "catalog source invalid");
            invariant(typeof entry.actionType === "string" && entry.actionType.length <= 128,
                "catalog action type invalid");
            invariant(entry.productionEligibility === "review", "production eligibility must remain review");
            invariant(typeof entry.mechanicallyRenderable === "boolean", "mechanical status missing");
            if (entry.mechanicallyRenderable) {
                invariant(entry.category === "equipment" || entry.category === "material" || entry.category === "consumable",
                    "renderable category invalid");
                invariant(isSafeString(entry.subclass, 128), "renderable subclass invalid");
                invariant(isSafePositiveInteger(entry.price), "renderable price invalid");
                invariant(entry.saleValue === Math.floor(entry.price * 0.25), "sale value drift");
                invariant(isSafeString(entry.iconUri, 256) && /^icons\/[A-Za-z0-9._-]+$/.test(entry.iconUri),
                    "renderable icon uri invalid");
                invariant(entry.assetKind === "icon-proxy" || entry.assetKind === "canonical-icon",
                    "renderable asset kind invalid");
                invariant(entry.iconFrame === "f1" || entry.iconFrame === "f2", "renderable icon frame invalid");
                invariant(typeof entry.backgroundNeutral === "boolean", "renderable background-neutral status missing");
                if (entry.category === "equipment") {
                    invariant(entry.assetKind === "icon-proxy" && entry.iconFrame === "f1"
                        && entry.iconFrameRole === "inventory-icon-proxy" && entry.backgroundNeutral === false
                        && entry.hiddenColorMode === "proxy",
                    "equipment icon proxy contract invalid");
                } else {
                    invariant(entry.assetKind === "canonical-icon", "material/consumable asset kind invalid");
                    invariant((entry.iconFrame === "f2" && entry.iconFrameRole === "drop-item-frame"
                            && entry.backgroundNeutral === true && entry.hiddenColorMode === "source")
                        || (entry.iconFrame === "f1" && entry.iconFrameRole === "neutralized-single-frame"
                            && entry.backgroundNeutral === false && entry.hiddenColorMode === "monochrome"),
                    "material/consumable icon frame contract invalid");
                }
                invariant(entry.mechanicalRejectReason === null, "renderable entry has reject reason");
                mechanicallyRenderable += 1;
                mechanicallyRenderableByCategory[entry.category] += 1;
            } else {
                invariant(isSafeString(entry.mechanicalRejectReason, 128), "rejected entry lacks reason");
            }
        }
        invariant(input.stats.totalItems === input.entries.length, "catalog total count drift");
        invariant(input.stats.mechanicallyRenderable === mechanicallyRenderable, "catalog renderable count drift");
        invariant(input.stats.mechanicallyRejected === input.entries.length - mechanicallyRenderable,
            "catalog rejected count drift");
        var categoryCount = 0;
        ["equipment", "material", "consumable"].forEach(function(category) {
            var count = input.stats.mechanicallyRenderableByCategory[category];
            invariant(isSafeNonNegativeInteger(count), "catalog category count invalid");
            invariant(count === mechanicallyRenderableByCategory[category], "catalog " + category + " count drift");
            categoryCount += count;
        });
        invariant(categoryCount === mechanicallyRenderable, "catalog category count drift");
        return input;
    }

    function groupCandidates(catalog) {
        var groups = {};
        catalog.entries.forEach(function(entry) {
            if (!entry.mechanicallyRenderable) return;
            var key = entry.category + "\u0000" + entry.subclass;
            if (!groups[key]) groups[key] = [];
            groups[key].push(entry);
        });
        Object.keys(groups).forEach(function(key) {
            groups[key].sort(function(a, b) {
                if (a.saleValue !== b.saleValue) return a.saleValue - b.saleValue;
                return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
            });
        });
        return groups;
    }

    function priceBounds(low, high) {
        var lower = Math.ceil((low.saleValue + 1) / 50) * 50;
        var upper = Math.floor((high.saleValue - 50) / 50) * 50;
        return lower > upper || lower <= 0 ? null : { lower: lower, upper: upper };
    }

    function priceForPair(low, high, rng) {
        var bounds = priceBounds(low, high);
        if (!bounds) return null;
        var slots = Math.floor((bounds.upper - bounds.lower) / 50) + 1;
        return bounds.lower + rng.int(slots) * 50;
    }

    function selectPair(first, second, rng) {
        if (!first || !second || first.id === second.id) return null;
        var low = first.saleValue <= second.saleValue ? first : second;
        var high = low === first ? second : first;
        var counterPriceTp = priceForPair(low, high, rng);
        if (counterPriceTp === null) return null;
        return { low: low, high: high, counterPriceTp: counterPriceTp };
    }

    function choosePair(entries, used, rng) {
        if (!entries || entries.length < 2) return null;
        var attempts;
        for (attempts = 0; attempts < Math.min(800, entries.length * 12); attempts += 1) {
            var first = entries[rng.int(entries.length)];
            var second = entries[rng.int(entries.length)];
            if (first.id === second.id || used[first.id] || used[second.id]) continue;
            var selected = selectPair(first, second, rng);
            if (selected) return selected;
        }
        return null;
    }

    function round(value) {
        return Math.round(value * 1000) / 1000;
    }

    function buildSurfacePair(seed) {
        var digest = hash32(seed + ":object-surface").toString(16);
        var previewGender = (hash32(seed + ":paper-doll-gender") & 1) === 0 ? "男" : "女";
        return {
            targetCoverage: COVERAGE_BY_LEVEL[3],
            metric: "object-alpha-pixels",
            anchorMode: "automatic-pca-skeleton",
            orientationMode: "automatic-orthogonal",
            A: { seed: digest + "-A", previewGender: previewGender },
            B: { seed: digest + "-B", previewGender: previewGender }
        };
    }

    function makeOffer(item, pairId, side, counterPriceTp, surface) {
        var margin = item.saleValue - counterPriceTp;
        return {
            offerId: pairId + "-" + side,
            side: side,
            quantity: 1,
            assetUri: item.iconUri,
            assetKind: item.assetKind,
            iconFrameRole: item.iconFrameRole,
            hiddenColorMode: item.hiddenColorMode,
            item: item,
            resellTp: item.saleValue,
            marginTp: margin,
            surface: surface
        };
    }

    function buildPage(catalogInput, seed, pageNumber) {
        return buildPageInternal(catalogInput, seed, pageNumber, null);
    }

    function buildPageInternal(catalogInput, seed, pageNumber, requiredItemId) {
        var catalog = validateCatalog(catalogInput);
        invariant(isSafeString(seed, 160), "page seed invalid");
        invariant(isSafePositiveInteger(pageNumber), "page number invalid");
        var rng = createRng(seed + ":" + catalog.catalogDigest + ":page:" + pageNumber);
        var groups = groupCandidates(catalog);
        var groupKeys = Object.keys(groups).filter(function(key) { return groups[key].length >= 2; });
        invariant(groupKeys.length > 0, "catalog has no pairable groups");
        var used = {};
        var pairs = [];

        function appendPair(selected) {
            used[selected.low.id] = true;
            used[selected.high.id] = true;
            var pairIndex = pairs.length + 1;
            var pairId = "P" + pageNumber + "-" + pairIndex;
            var highOnA = rng.next() < 0.5;
            var surfaces = buildSurfacePair(seed + ":" + pairId);
            var itemA = highOnA ? selected.high : selected.low;
            var itemB = highOnA ? selected.low : selected.high;
            pairs.push({
                pairId: pairId,
                index: pairIndex,
                category: selected.low.category,
                subclass: selected.low.subclass,
                counterPriceTp: selected.counterPriceTp,
                kCost: Math.ceil(selected.counterPriceTp / 50),
                winnerOfferId: pairId + "-" + (highOnA ? "A" : "B"),
                similarityMode: "same-subclass-price-strata",
                coverageParity: {
                    metric: surfaces.metric,
                    anchorMode: surfaces.anchorMode,
                    orientationMode: surfaces.orientationMode,
                    maxCoverageDelta: 0.002
                },
                offers: [
                    makeOffer(itemA, pairId, "A", selected.counterPriceTp, surfaces.A),
                    makeOffer(itemB, pairId, "B", selected.counterPriceTp, surfaces.B)
                ]
            });
        }

        if (requiredItemId !== null) {
            invariant(isSafeString(requiredItemId, 64), "lab focus item id invalid");
            var requiredItem = catalog.entries.filter(function(entry) { return entry.id === requiredItemId; })[0];
            invariant(!!requiredItem && requiredItem.mechanicallyRenderable, "lab focus item is not renderable");
            var requiredGroup = groups[requiredItem.category + "\u0000" + requiredItem.subclass] || [];
            var partners = shuffle(requiredGroup.filter(function(candidate) {
                if (candidate.id === requiredItem.id) return false;
                var low = requiredItem.saleValue <= candidate.saleValue ? requiredItem : candidate;
                var high = low === requiredItem ? candidate : requiredItem;
                return priceBounds(low, high) !== null;
            }), rng);
            invariant(partners.length > 0, "lab focus item has no valid partner");
            appendPair(selectPair(requiredItem, partners[0], rng));
        }

        var attempts;
        for (attempts = 0; attempts < 2400 && pairs.length < 3; attempts += 1) {
            var key = groupKeys[rng.int(groupKeys.length)];
            var selected = choosePair(groups[key], used, rng);
            if (!selected) continue;
            appendPair(selected);
        }
        invariant(pairs.length === 3, "catalog cannot produce three valid pairs");
        return {
            pageId: "shadow-" + hash32(seed + ":" + pageNumber).toString(16),
            pageNumber: pageNumber,
            seed: seed,
            catalogDigest: catalog.catalogDigest,
            pairs: pairs
        };
    }

    function makeProgress() {
        return {
            status: "open",
            selectedOfferId: null,
            payment: null,
            paidAmount: 0,
            revealed: null,
            settlement: null
        };
    }

    function createShadowSession(catalogInput, options) {
        var catalog = validateCatalog(catalogInput);
        var opts = options || {};
        var rootSeed = isSafeString(opts.seed, 160) ? opts.seed : "blackmarket-shadow-default";
        var pageNumber = 1;
        var page = buildPage(catalog, rootSeed, pageNumber);
        var revision = 1;
        var tradePoints = isSafeNonNegativeInteger(opts.tradePoints) ? opts.tradePoints : 500000;
        var kPoints = isSafeNonNegativeInteger(opts.kPoints) ? opts.kPoints : 10000;
        var supplyCredits = isSafeNonNegativeInteger(opts.supplyCredits) ? opts.supplyCredits : 2;
        var decryptLevel = LEVELS.indexOf(opts.decryptLevel) >= 0 ? opts.decryptLevel : 3;
        var progress = {};
        var pending = null;
        var previews = {};
        var receipts = [];
        var history = [];
        var collectionCount = 0;

        function resetProgress() {
            progress = {};
            page.pairs.forEach(function(pair) { progress[pair.pairId] = makeProgress(); });
            pending = null;
            previews = {};
        }
        resetProgress();

        function bump() {
            revision += 1;
            previews = {};
        }

        function currentPair(pairId) {
            var pair = page.pairs.filter(function(candidate) { return candidate.pairId === pairId; })[0];
            invariant(!!pair, "pair is not on the current page");
            return pair;
        }

        function currentOffer(pair, offerId) {
            var offer = pair.offers.filter(function(candidate) { return candidate.offerId === offerId; })[0];
            invariant(!!offer, "offer is not in the selected pair");
            return offer;
        }

        function currentOfferById(offerId) {
            invariant(isSafeString(offerId, 128), "offerId invalid");
            for (var pairIndex = 0; pairIndex < page.pairs.length; pairIndex += 1) {
                var offers = page.pairs[pairIndex].offers;
                for (var offerIndex = 0; offerIndex < offers.length; offerIndex += 1) {
                    if (offers[offerIndex].offerId === offerId) return offers[offerIndex];
                }
            }
            invariant(false, "offer is not on the current page");
            return null;
        }

        function callKey(operation, callId) {
            invariant(isSafeString(callId, 128), "callId invalid");
            return operation + ":" + callId;
        }

        function requestDigest(request) {
            return JSON.stringify(request || {});
        }

        function replay(operation, callId, request) {
            var key = callKey(operation, callId);
            var found = receipts.filter(function(receipt) { return receipt.key === key; })[0];
            if (found) {
                invariant(found.requestDigest === requestDigest(request), "callId reused with different request");
            }
            return found ? clone(found.snapshot) : null;
        }

        function record(operation, callId, request, snapshot) {
            var key = callKey(operation, callId);
            receipts = receipts.filter(function(receipt) { return receipt.key !== key; });
            receipts.push({ key: key, requestDigest: requestDigest(request), snapshot: clone(snapshot) });
            if (receipts.length > MAX_RECEIPTS) receipts.splice(0, receipts.length - MAX_RECEIPTS);
        }

        function isComplete() {
            return page.pairs.every(function(pair) {
                var status = progress[pair.pairId].status;
                return status !== "open" && status !== "pending";
            });
        }

        function projectOffer(pair, offer) {
            var state = progress[pair.pairId];
            var chosen = state.selectedOfferId === offer.offerId;
            var terminal = state.status === "extracted" || state.status === "resold";
            var visualState = "available";
            if (state.status === "skipped") visualState = "sealed";
            else if ((state.status === "pending" || terminal) && chosen) visualState = "revealed";
            else if ((state.status === "pending" || terminal) && !chosen) visualState = "withdrawn";
            return {
                offerId: offer.offerId,
                side: offer.side,
                quantity: offer.quantity,
                category: pair.category,
                subclass: pair.subclass,
                assetUri: offer.assetUri,
                assetKind: offer.assetKind,
                iconFrameRole: offer.iconFrameRole,
                hiddenColorMode: offer.hiddenColorMode,
                label: "未鉴定" + (CATEGORY_LABEL[pair.category] || "货物") + " " + offer.side,
                hint: decryptLevel >= 3 ? "自动破局点 · 局部表面" : null,
                direction: decryptLevel >= 10 && state.status === "open"
                    ? (offer.marginTp > 0 ? "profit" : "loss") : null,
                visualState: visualState,
                surface: {
                    algorithmVersion: ALGORITHM_VERSION,
                    seed: offer.surface.seed,
                    previewGender: offer.surface.previewGender,
                    targetCoverage: COVERAGE_BY_LEVEL[decryptLevel],
                    coverageMetric: "object-alpha-pixels",
                    anchorMode: "automatic-pca-skeleton",
                    orientationMode: "automatic-orthogonal"
                },
                revealed: chosen && state.revealed ? clone(state.revealed) : null
            };
        }

        function snapshot() {
            return {
                schemaVersion: SNAPSHOT_SCHEMA,
                revision: revision,
                shadowOnly: true,
                fixtureOnly: true,
                productionWrites: false,
                identityBoundary: "lab-web-memory",
                algorithmVersion: ALGORITHM_VERSION,
                catalog: {
                    digest: catalog.catalogDigest,
                    totalItems: catalog.stats.totalItems,
                    mechanicallyRenderable: catalog.stats.mechanicallyRenderable,
                    mechanicallyRejected: catalog.stats.mechanicallyRejected,
                    byCategory: clone(catalog.stats.mechanicallyRenderableByCategory)
                },
                balances: { tradePoints: tradePoints, kPoints: kPoints, supplyCredits: supplyCredits },
                decryptLevel: decryptLevel,
                mudCoverage: COVERAGE_BY_LEVEL[decryptLevel],
                page: {
                    id: page.pageId,
                    number: pageNumber,
                    seed: rootSeed,
                    complete: isComplete()
                },
                pairs: page.pairs.map(function(pair) {
                    return {
                        pairId: pair.pairId,
                        index: pair.index,
                        category: pair.category,
                        subclass: pair.subclass,
                        counterPriceTp: pair.counterPriceTp,
                        kCost: pair.kCost,
                        status: progress[pair.pairId].status,
                        similarityMode: pair.similarityMode,
                        coverageParity: {
                            metric: pair.coverageParity.metric,
                            anchorMode: pair.coverageParity.anchorMode,
                            orientationMode: pair.coverageParity.orientationMode,
                            maxCoverageDelta: pair.coverageParity.maxCoverageDelta,
                            targetCoverage: COVERAGE_BY_LEVEL[decryptLevel]
                        },
                        offers: pair.offers.map(function(offer) { return projectOffer(pair, offer); })
                    };
                }),
                pending: pending ? clone(pending) : null,
                collectionCount: collectionCount,
                historyCount: history.length
            };
        }

        var productPort = {
            open: function() { return snapshot(); },
            purchasePreview: function(intent) {
                invariant(isObject(intent), "purchase intent invalid");
                invariant(pending === null, "先结清已揭晓的货物");
                invariant(intent.payment === "tp" || intent.payment === "k", "payment invalid");
                var pair = currentPair(intent.pairId);
                invariant(progress[pair.pairId].status === "open", "pair is already terminal");
                currentOffer(pair, intent.offerId);
                var cost = intent.payment === "tp" ? pair.counterPriceTp : pair.kCost;
                invariant(intent.payment !== "tp" || tradePoints >= cost, "交易点不足");
                invariant(intent.payment !== "k" || kPoints >= cost, "K 点不足");
                var token = "pv-" + revision + "-" + pair.pairId + "-" + intent.offerId + "-" + intent.payment;
                var result = {
                    token: token,
                    revision: revision,
                    pairId: pair.pairId,
                    offerId: intent.offerId,
                    payment: intent.payment,
                    cost: cost
                };
                previews[token] = result;
                return clone(result);
            },
            purchaseCommit: function(token, callId) {
                var request = { token: token };
                var prior = replay("purchaseCommit", callId, request);
                if (prior) return prior;
                invariant(pending === null, "先结清已揭晓的货物");
                var preview = previews[token];
                invariant(!!preview && preview.revision === revision, "preview is stale");
                var pair = currentPair(preview.pairId);
                var offer = currentOffer(pair, preview.offerId);
                invariant(progress[pair.pairId].status === "open", "pair is already terminal");
                if (preview.payment === "tp") {
                    invariant(tradePoints >= preview.cost, "交易点不足");
                    tradePoints -= preview.cost;
                } else {
                    invariant(kPoints >= preview.cost, "K 点不足");
                    kPoints -= preview.cost;
                }
                progress[pair.pairId] = {
                    status: "pending",
                    selectedOfferId: offer.offerId,
                    payment: preview.payment,
                    paidAmount: preview.cost,
                    revealed: {
                        displayName: offer.item.displayName,
                        quantity: offer.quantity,
                        basePrice: offer.item.price,
                        resellValue: offer.resellTp,
                        deltaTp: offer.marginTp,
                        direction: offer.marginTp > 0 ? "profit" : "loss",
                        wasWinner: pair.winnerOfferId === offer.offerId
                    },
                    settlement: null
                };
                pending = { pairId: pair.pairId, offerId: offer.offerId, commitCallId: callId };
                bump();
                var committed = snapshot();
                record("purchaseCommit", callId, request, committed);
                return committed;
            },
            settle: function(action, callId) {
                var request = { action: action };
                var prior = replay("settle", callId, request);
                if (prior) return prior;
                invariant(action === "extract" || action === "resell", "settle action invalid");
                invariant(!!pending, "no pending offer");
                var pairId = pending.pairId;
                var state = progress[pairId];
                invariant(state.status === "pending" && !!state.revealed, "pending state invalid");
                if (action === "resell") tradePoints += state.revealed.resellValue;
                else collectionCount += 1;
                state.status = action === "resell" ? "resold" : "extracted";
                state.settlement = action;
                history.push({
                    pageNumber: pageNumber,
                    pairId: pairId,
                    side: state.selectedOfferId.slice(-1),
                    wasWinner: state.revealed.wasWinner,
                    payment: state.payment,
                    deltaTp: action === "resell" ? state.revealed.deltaTp : -state.paidAmount,
                    terminal: state.status
                });
                pending = null;
                bump();
                var settled = snapshot();
                record("settle", callId, request, settled);
                return settled;
            },
            skip: function(pairId, callId) {
                var request = { pairId: pairId };
                var prior = replay("skip", callId, request);
                if (prior) return prior;
                invariant(pending === null, "先结清已揭晓的货物");
                var pair = currentPair(pairId);
                invariant(progress[pair.pairId].status === "open", "pair is already terminal");
                progress[pair.pairId].status = "skipped";
                history.push({ pageNumber: pageNumber, pairId: pairId, side: null, wasWinner: null,
                    payment: null, deltaTp: 0, terminal: "skipped" });
                bump();
                var skipped = snapshot();
                record("skip", callId, request, skipped);
                return skipped;
            },
            nextPage: function(callId) {
                var request = {};
                var prior = replay("nextPage", callId, request);
                if (prior) return prior;
                invariant(pending === null, "先结清已揭晓的货物");
                invariant(isComplete(), "current page is not complete");
                invariant(supplyCredits > 0, "补货信用不足");
                supplyCredits -= 1;
                pageNumber += 1;
                page = buildPage(catalog, rootSeed, pageNumber);
                resetProgress();
                bump();
                var next = snapshot();
                record("nextPage", callId, request, next);
                return next;
            }
        };

        // 视觉源端口与公开 snapshot 分离：防具纸娃娃合成需要 exact 物品名，
        // 但该身份不得在购买前进入可序列化公开状态或 DOM 文本。
        var visualPort = {
            resolveOfferSource: function(offerId) {
                var offer = currentOfferById(offerId);
                var item = offer.item;
                var paperDollSlot = item.type === "防具" ? PAPER_DOLL_SLOT_BY_USE[item.use] : null;
                var fullWeapon = item.type === "武器";
                return {
                    kind: paperDollSlot ? "dressup-paperdoll" : (fullWeapon ? "dressup-weapon" : "icon"),
                    itemId: item.id,
                    itemName: paperDollSlot || fullWeapon ? item.name : null,
                    iconName: paperDollSlot || fullWeapon ? item.iconKey : null,
                    itemType: item.type,
                    use: item.use,
                    actionType: fullWeapon ? item.actionType : "",
                    slot: paperDollSlot || null,
                    assetUri: item.iconUri,
                    assetKind: item.assetKind,
                    sharpenFallback: item.assetKind === "icon-proxy"
                };
            }
        };

        var labPort = {
            listCatalog: function(request) {
                var query = request || {};
                invariant(isObject(query), "catalog query invalid");
                invariant(Object.keys(query).every(function(key) {
                    return key === "query" || key === "category" || key === "offset" || key === "limit";
                }), "catalog query has unknown fields");
                invariant(query.query === undefined || typeof query.query === "string", "catalog query text invalid");
                invariant(query.category === undefined || typeof query.category === "string", "catalog query category invalid");
                var text = query.query === undefined ? "" : query.query.trim();
                invariant(text.length <= 80, "catalog query is too long");
                var category = query.category === undefined ? "" : query.category;
                invariant(category === "" || category === "equipment" || category === "material" || category === "consumable",
                    "catalog query category invalid");
                var offset = query.offset === undefined ? 0 : query.offset;
                var limit = query.limit === undefined ? 12 : query.limit;
                invariant(isSafeNonNegativeInteger(offset) && offset <= MAX_CATALOG_ITEMS, "catalog query offset invalid");
                invariant(isSafePositiveInteger(limit) && limit <= 24, "catalog query limit invalid");
                var needle = text.toLocaleLowerCase("zh-CN");
                var matches = catalog.entries.filter(function(entry) {
                    if (!entry.mechanicallyRenderable) return false;
                    if (category && entry.category !== category) return false;
                    if (!needle) return true;
                    return [entry.name, entry.displayName, entry.type, entry.use, entry.subclass]
                        .some(function(value) { return String(value || "").toLocaleLowerCase("zh-CN").indexOf(needle) >= 0; });
                });
                return {
                    shadowOnly: true,
                    identityVisibleInLab: true,
                    total: matches.length,
                    offset: offset,
                    items: matches.slice(offset, offset + limit).map(function(entry) {
                        return {
                            id: entry.id,
                            displayName: entry.displayName,
                            category: entry.category,
                            subclass: entry.subclass,
                            price: entry.price,
                            saleValue: entry.saleValue,
                            assetKind: entry.assetKind,
                            iconUri: entry.iconUri,
                            iconFrame: entry.iconFrame,
                            iconFrameRole: entry.iconFrameRole,
                            backgroundNeutral: entry.backgroundNeutral,
                            hiddenColorMode: entry.hiddenColorMode
                        };
                    })
                };
            },
            focusItem: function(itemId) {
                invariant(pending === null, "pending offer blocks lab focus");
                var item = catalog.entries.filter(function(entry) { return entry.id === itemId; })[0];
                invariant(!!item && item.mechanicallyRenderable, "lab focus item is not renderable");
                rootSeed = "bm-focus-" + item.id;
                pageNumber = 1;
                page = buildPageInternal(catalog, rootSeed, pageNumber, item.id);
                history = [];
                collectionCount = 0;
                resetProgress();
                bump();
                var location = null;
                page.pairs.forEach(function(pair) {
                    pair.offers.forEach(function(offer) {
                        if (offer.item.id === item.id) {
                            location = { pairId: pair.pairId, offerId: offer.offerId, side: offer.side };
                        }
                    });
                });
                invariant(!!location, "lab focus item was not placed on page");
                return {
                    snapshot: snapshot(),
                    focus: {
                        itemId: item.id,
                        displayName: item.displayName,
                        category: item.category,
                        subclass: item.subclass,
                        pairId: location.pairId,
                        offerId: location.offerId,
                        side: location.side
                    }
                };
            },
            setDecryptLevel: function(level) {
                invariant(LEVELS.indexOf(level) >= 0, "decrypt level invalid");
                decryptLevel = level;
                bump();
                return snapshot();
            },
            reroll: function(seed) {
                invariant(pending === null, "pending offer blocks reroll");
                rootSeed = isSafeString(seed, 160) ? seed : rootSeed + ":next";
                pageNumber = 1;
                page = buildPage(catalog, rootSeed, pageNumber);
                history = [];
                collectionCount = 0;
                resetProgress();
                bump();
                return snapshot();
            },
            exportAnonymous: function() {
                return {
                    schemaVersion: "black-market-shadow-export.v1",
                    shadowOnly: true,
                    catalogDigest: catalog.catalogDigest,
                    algorithmVersion: ALGORITHM_VERSION,
                    seed: rootSeed,
                    pageNumber: pageNumber,
                    decryptLevel: decryptLevel,
                    balances: { tradePoints: tradePoints, kPoints: kPoints, supplyCredits: supplyCredits },
                    history: clone(history)
                };
            }
        };

        return {
            product: productPort,
            lab: labPort,
            visual: visualPort,
            debug: {
                page: function() { return clone(page); },
                catalog: function() { return catalog; }
            }
        };
    }

    function publicSnapshotContainsIdentity(snapshot, catalog) {
        var text = JSON.stringify(snapshot);
        var entries = catalog && catalog.entries || [];
        var i;
        for (i = 0; i < entries.length; i += 1) {
            if (text.indexOf('"' + entries[i].name + '"') >= 0
                    || text.indexOf('"' + entries[i].displayName + '"') >= 0
                    || text.indexOf('"' + entries[i].source + '"') >= 0) return true;
        }
        return false;
    }

    return {
        CATALOG_SCHEMA: CATALOG_SCHEMA,
        SNAPSHOT_SCHEMA: SNAPSHOT_SCHEMA,
        LEVELS: LEVELS.slice(),
        COVERAGE_BY_LEVEL: clone(COVERAGE_BY_LEVEL),
        PAPER_DOLL_SLOT_BY_USE: clone(PAPER_DOLL_SLOT_BY_USE),
        validateCatalog: validateCatalog,
        buildPage: buildPage,
        buildSurfacePair: buildSurfacePair,
        createShadowSession: createShadowSession,
        publicSnapshotContainsIdentity: publicSnapshotContainsIdentity,
        hash32: hash32
    };
});
