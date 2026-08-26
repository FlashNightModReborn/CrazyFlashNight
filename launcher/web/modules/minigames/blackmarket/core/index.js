(function(root, factory) {
    "use strict";

    var commonJs = !!(typeof module === "object" && module.exports);

    function secureRandomBytes(length) {
        var bytes;
        var index;
        if (root.crypto && typeof root.crypto.getRandomValues === "function") {
            bytes = new Uint8Array(length);
            root.crypto.getRandomValues(bytes);
            return bytes;
        }
        if (commonJs) {
            var nodeBytes = require("crypto").randomBytes(length);
            bytes = new Uint8Array(length);
            for (index = 0; index < length; index += 1) bytes[index] = nodeBytes[index];
            return bytes;
        }
        throw new Error("secure session entropy unavailable");
    }

    var api = factory({ randomBytes: secureRandomBytes, commonJs: commonJs });
    if (commonJs) module.exports = api;
    else root.BlackMarketCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function(environment) {
    "use strict";

    var SNAPSHOT_SCHEMA = "black-market-anonymous-shadow.v2";
    var ALGORITHM_VERSION = "object-sdf-nanobot-sludge.v2";
    var IDENTITY_BOUNDARY = "anonymous-synthetic-no-catalog.v2";
    var FIXTURE_DIGEST = "anonymous-shadow-fixture-v2";
    var LEVELS = [0, 3, 5, 10];
    var COVERAGE_BY_LEVEL = { 0: 0.97, 3: 0.84, 5: 0.54, 10: 0.18 };
    var PRICE_POINTS = [5000, 7500, 10000, 15000, 20000, 30000];
    var MAX_RECEIPTS = 64;
    // 匿名视觉池：visual/visual-pool-manifest.js（tools/bake-black-market-visual-pool.js
    // 生成，--check 可复验）提供全目录渲染资格清单（仅 u/h 渲染字段，零身份字段）。
    // 覆泥像素允许被认出（设计意图：能猜、猜不准价）；清单缺失时回退固定安全 SVG。
    var SAFE_SURFACE_DATA_URL = "data:image/svg+xml;charset=utf-8," + encodeURIComponent([
        '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="192" viewBox="0 0 128 192">',
        '<path fill="#87908b" d="M25 35h78l13 25-9 98-43 22-43-22-9-98z"/>',
        '<path fill="#59635f" d="M25 35l39 20 39-20 13 25-52 25-52-25z"/>',
        '<path fill="#a7afa9" d="M58 55h12v113H58z"/>',
        '<path fill="#343b39" d="M32 94h64v12H32z"/>',
        '</svg>'
    ].join(""));

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
        var index;
        for (index = 0; index < source.length; index += 1) {
            hash ^= source.charCodeAt(index);
            hash = Math.imul(hash, 16777619) >>> 0;
        }
        return hash >>> 0;
    }

    // 同组配对分配：同一货舱左右两件来自同一分组（g 键），同页六件互不重复；
    // 分组不足三对时退化为全池不重复抽取（视觉多样性优先，约束让位）；空池返回 []。
    function shuffleInPlace(list, rng) {
        for (var cursor = list.length - 1; cursor > 0; cursor -= 1) {
            var target = rng.int(cursor + 1);
            var tmp = list[cursor];
            list[cursor] = list[target];
            list[target] = tmp;
        }
    }

    function planVisualAssignments(rng, entries) {
        if (!entries.length) return [];
        var groups = {};
        var groupOrder = [];
        var index;
        for (index = 0; index < entries.length; index += 1) {
            var key = String(entries[index].g || "?");
            if (!groups[key]) {
                groups[key] = [];
                groupOrder.push(key);
            }
            groups[key].push(index);
        }
        shuffleInPlace(groupOrder, rng);
        var picked = [];
        for (var groupCursor = 0; groupCursor < groupOrder.length && picked.length < 6; groupCursor += 1) {
            var members = groups[groupOrder[groupCursor]];
            if (members.length < 2) continue;
            shuffleInPlace(members, rng);
            picked.push(members[0], members[1]);
        }
        if (picked.length < 6) {
            var flat = [];
            for (index = 0; index < entries.length; index += 1) flat.push(index);
            shuffleInPlace(flat, rng);
            picked = flat.slice(0, 6);
        }
        return picked;
    }

    var visualPoolCache = null;

    // 读取生成的视觉池清单；浏览器走 UMD 全局，Node 走相对 require，双通道同一文件。
    function visualPoolEntries() {
        if (visualPoolCache) return visualPoolCache;
        var manifest = null;
        if (typeof globalThis !== "undefined" && globalThis.BlackMarketVisualPool) {
            manifest = globalThis.BlackMarketVisualPool;
        } else if (environment.commonJs) {
            try {
                manifest = require("../visual/visual-pool-manifest.js");
            } catch (error) {
                manifest = null;
            }
        }
        var entries = manifest && Array.isArray(manifest.entries) ? manifest.entries : [];
        visualPoolCache = entries.filter(function(entry) {
            return entry && typeof entry.u === "string" && /^icons\/[0-9a-f]+_\d+\.webp$/.test(entry.u);
        });
        return visualPoolCache;
    }

    function deterministicHex(label, sequence, byteLength) {
        var out = "";
        var block = 0;
        while (out.length < byteLength * 2) {
            out += (hash32(label + ":" + sequence + ":" + block) + 0x100000000)
                .toString(16).slice(-8);
            block += 1;
        }
        return out.slice(0, byteLength * 2);
    }

    function deterministicBytes(label) {
        var sequence = 0;
        return function(length) {
            sequence += 1;
            var hex = deterministicHex(label, sequence, length);
            var bytes = new Uint8Array(length);
            var index;
            for (index = 0; index < length; index += 1) {
                bytes[index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
            }
            return bytes;
        };
    }

    function randomHex(nextBytes, byteLength) {
        var bytes = nextBytes(byteLength);
        invariant(bytes && bytes.length === byteLength, "random byte source invalid");
        var out = "";
        var index;
        for (index = 0; index < bytes.length; index += 1) {
            out += (bytes[index] + 256).toString(16).slice(-2);
        }
        return out;
    }

    function createByteRng(nextBytes) {
        function nextUint32() {
            var bytes = nextBytes(4);
            invariant(bytes && bytes.length === 4, "random byte source invalid");
            return (((bytes[0] << 24) >>> 0) + (bytes[1] << 16)
                + (bytes[2] << 8) + bytes[3]) >>> 0;
        }
        return {
            next: function() {
                return nextUint32() / 4294967296;
            },
            int: function(max) {
                invariant(Number.isInteger(max) && max > 0 && max <= 4294967296,
                    "rng max must be a positive uint32 range");
                var limit = Math.floor(4294967296 / max) * max;
                var value;
                do { value = nextUint32(); } while (value >= limit);
                return value % max;
            }
        };
    }

    function validateOptions(options) {
        var input = options === undefined ? {} : options;
        invariant(isObject(input), "anonymous product options invalid");
        var allowed = { tradePoints: true, kPoints: true, supplyCredits: true, decryptLevel: true, seed: true };
        invariant(Object.keys(input).every(function(key) { return allowed[key] === true; }),
            "anonymous product does not accept an exact directory or unknown fields");
        var opts = {};
        if (input.tradePoints !== undefined) {
            invariant(isSafeNonNegativeInteger(input.tradePoints), "tradePoints invalid");
            opts.tradePoints = input.tradePoints;
        }
        if (input.kPoints !== undefined) {
            invariant(isSafeNonNegativeInteger(input.kPoints), "kPoints invalid");
            opts.kPoints = input.kPoints;
        }
        if (input.supplyCredits !== undefined) {
            invariant(isSafeNonNegativeInteger(input.supplyCredits), "supplyCredits invalid");
            opts.supplyCredits = input.supplyCredits;
        }
        if (input.decryptLevel !== undefined) {
            invariant(LEVELS.indexOf(input.decryptLevel) >= 0, "decryptLevel invalid");
            opts.decryptLevel = input.decryptLevel;
        }
        return opts;
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

    function createSessionInternal(options, nextBytes) {
        var opts = validateOptions(options);
        var pageNumber = 1;
        var revision = 1;
        var tradePoints = opts.tradePoints === undefined ? 500000 : opts.tradePoints;
        var kPoints = opts.kPoints === undefined ? 10000 : opts.kPoints;
        var supplyCredits = opts.supplyCredits === undefined ? 2 : opts.supplyCredits;
        var decryptLevel = opts.decryptLevel === undefined ? 3 : opts.decryptLevel;
        var page;
        var progress = {};
        var pending = null;
        var previews = {};
        var receipts = [];
        var history = [];
        var collectionCount = 0;

        function preparePage() {
            var rng = createByteRng(nextBytes);
            var pairs = [];
            var pairIndex;
            // 同组配对约束（对齐 exact oracle 的 same-subclass-price-strata）：同一货舱左右
            // 两件必为同组物品（subclass 粗分类），同页六件零撞车；视觉只是像素，分组键是
            // 粗分类法，不构成身份/价格泄漏。纯内部字段，不进公开快照。
            var poolEntries = visualPoolEntries();
            var visualPlan = planVisualAssignments(rng, poolEntries);
            var poolAssignCursor = 0;
            for (pairIndex = 1; pairIndex <= 3; pairIndex += 1) {
                var pairId = "P" + pageNumber + "-" + pairIndex;
                var counterPriceTp = PRICE_POINTS[rng.int(PRICE_POINTS.length)];
                var lowSettlementTp = Math.max(50, counterPriceTp - (1 + rng.int(12)) * 50);
                var highSettlementTp = counterPriceTp + (1 + rng.int(24)) * 50;
                var highOnA = rng.next() < 0.5;
                var handleA = "opaque-visual-" + randomHex(nextBytes, 20);
                var handleB = "opaque-visual-" + randomHex(nextBytes, 20);
                var seedA = randomHex(nextBytes, 16);
                var seedB = randomHex(nextBytes, 16);

                function makeOffer(side, high, handle, surfaceSeed) {
                    var settlementTp = high ? highSettlementTp : lowSettlementTp;
                    var offer = {
                        offerId: pairId + "-" + side,
                        side: side,
                        visualHandle: handle,
                        settlementTp: settlementTp,
                        syntheticTier: high ? "high" : "low",
                        surfaceSeed: surfaceSeed,
                        visualPool: visualPlan.length ? visualPlan[poolAssignCursor % visualPlan.length] : -1
                    };
                    poolAssignCursor += 1;
                    return offer;
                }

                pairs.push({
                    pairId: pairId,
                    index: pairIndex,
                    category: "anonymous",
                    subclass: "匿名影子货舱",
                    counterPriceTp: counterPriceTp,
                    kCost: Math.ceil(counterPriceTp / 50),
                    similarityMode: "anonymous-synthetic",
                    coverageParity: {
                        metric: "object-alpha-pixels",
                        anchorMode: "automatic-pca-skeleton",
                        orientationMode: "automatic-orthogonal",
                        maxCoverageDelta: 0.002
                    },
                    offers: [
                        makeOffer("A", highOnA, handleA, seedA),
                        makeOffer("B", !highOnA, handleB, seedB)
                    ]
                });
            }
            return {
                pageId: "opaque-page-" + randomHex(nextBytes, 16),
                pageNumber: pageNumber,
                pairs: pairs
            };
        }

        function resetProgress() {
            progress = {};
            page.pairs.forEach(function(pair) { progress[pair.pairId] = makeProgress(); });
            pending = null;
            previews = {};
        }

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

        function currentOfferByHandle(visualHandle) {
            invariant(isSafeString(visualHandle, 128), "visual handle invalid");
            var pairIndex;
            var offerIndex;
            for (pairIndex = 0; pairIndex < page.pairs.length; pairIndex += 1) {
                for (offerIndex = 0; offerIndex < page.pairs[pairIndex].offers.length; offerIndex += 1) {
                    if (page.pairs[pairIndex].offers[offerIndex].visualHandle === visualHandle) {
                        return page.pairs[pairIndex].offers[offerIndex];
                    }
                }
            }
            invariant(false, "visual handle is not on the current page");
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

        function record(operation, callId, request, value) {
            var key = callKey(operation, callId);
            receipts = receipts.filter(function(receipt) { return receipt.key !== key; });
            receipts.push({ key: key, requestDigest: requestDigest(request), snapshot: clone(value) });
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
                quantity: 1,
                category: pair.category,
                subclass: pair.subclass,
                visualHandle: offer.visualHandle,
                presentationKind: "sealed-abstract",
                label: "未鉴定匿名货物 " + offer.side,
                hint: decryptLevel >= 3 ? "匿名破局点 · 局部表面" : null,
                direction: decryptLevel >= 10 && state.status === "open"
                    ? (offer.settlementTp > pair.counterPriceTp ? "profit" : "loss") : null,
                visualState: visualState,
                surface: {
                    algorithmVersion: ALGORITHM_VERSION,
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
                identityBoundary: IDENTITY_BOUNDARY,
                algorithmVersion: ALGORITHM_VERSION,
                catalog: {
                    kind: "anonymous-synthetic",
                    digest: FIXTURE_DIGEST,
                    totalItems: 6,
                    mechanicallyRenderable: 6,
                    mechanicallyRejected: 0,
                    byCategory: { anonymous: 6 }
                },
                balances: { tradePoints: tradePoints, kPoints: kPoints, supplyCredits: supplyCredits },
                decryptLevel: decryptLevel,
                mudCoverage: COVERAGE_BY_LEVEL[decryptLevel],
                page: { id: page.pageId, number: pageNumber, complete: isComplete() },
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

        page = preparePage();
        resetProgress();

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
                var valueDelta = offer.settlementTp
                    - (preview.payment === "tp" ? preview.cost : preview.cost * 50);
                // 揭晓释放：允许物品（e !== "banned"）给出真实身份与目录参考价；
                // 购买前快照仍然零身份字段（bm22/bm-ui2 不变），释放只发生在成交之后。
                var poolEntries = visualPoolEntries();
                var poolEntry = (typeof offer.visualPool === "number" && offer.visualPool >= 0
                    && poolEntries.length)
                    ? poolEntries[offer.visualPool % poolEntries.length] : null;
                var releasable = poolEntry && poolEntry.e !== "banned";
                progress[pair.pairId] = {
                    status: "pending",
                    selectedOfferId: offer.offerId,
                    payment: preview.payment,
                    paidAmount: preview.cost,
                    revealed: {
                        displayName: releasable ? poolEntry.n
                            : "匿名影子货物 · " + (offer.syntheticTier === "high" ? "高值" : "低值"),
                        quantity: 1,
                        basePrice: offer.settlementTp * 4,
                        resellValue: offer.settlementTp,
                        payment: preview.payment,
                        paidAmount: preview.cost,
                        deltaTp: offer.settlementTp - (preview.payment === "tp" ? preview.cost : 0),
                        deltaK: preview.payment === "k" ? -preview.cost : 0,
                        deltaV: valueDelta,
                        direction: valueDelta > 0 ? "profit" : "loss",
                        wasWinner: valueDelta > 0,
                        realInfo: releasable ? {
                            name: poolEntry.n,
                            type: poolEntry.t,
                            subclass: poolEntry.sc,
                            catalogPrice: poolEntry.p,
                            saleValue: poolEntry.s,
                            actionType: poolEntry.at
                        } : null
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
                var deltaTp = state.payment === "tp" ? -state.paidAmount : 0;
                var deltaK = state.payment === "k" ? -state.paidAmount : 0;
                if (action === "resell") deltaTp += state.revealed.resellValue;
                history.push({
                    pageNumber: pageNumber,
                    pairId: pairId,
                    side: state.selectedOfferId.slice(-1),
                    wasWinner: state.revealed.wasWinner,
                    payment: state.payment,
                    deltaTp: deltaTp,
                    deltaK: deltaK,
                    deltaV: deltaTp + deltaK * 50,
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
                history.push({
                    pageNumber: pageNumber,
                    pairId: pairId,
                    side: null,
                    wasWinner: null,
                    payment: null,
                    deltaTp: 0,
                    deltaK: 0,
                    deltaV: 0,
                    terminal: "skipped"
                });
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
                page = preparePage();
                resetProgress();
                bump();
                var next = snapshot();
                record("nextPage", callId, request, next);
                return next;
            }
        };

        var surfacePort = {
            resolveSurface: function(visualHandle) {
                var offer = currentOfferByHandle(visualHandle);
                // 匿名视觉池：每页私有熵洗牌分配（preparePage 的 visualPool），指向
                // visual-pool-manifest.js 里全目录渲染资格清单的某一格。Web 层只拿到
                // 覆泥像素（图标文件名本是内容哈希），拿不到名称/价格/目录映射——
                // 认出物品是设计允许的玩法，价格答案钥匙始终留在 Web 根外。
                // 正式接入后由 Host 私有且不可逆的视觉字节端口替代（README「下一阶段」）。
                var poolEntries = visualPoolEntries();
                if (!poolEntries.length || typeof offer.visualPool !== "number" || offer.visualPool < 0) {
                    return {
                        kind: "sealed-abstract",
                        assetUrl: SAFE_SURFACE_DATA_URL,
                        sourceKey: "sealed-abstract-surface.v1",
                        sourceKind: "sealed-abstract",
                        sourceComposition: "identity-independent-safe-surface",
                        previewGender: "neutral",
                        seed: offer.surfaceSeed,
                        autoRotate: false,
                        sharpenSource: false,
                        hiddenColorMode: "source"
                    };
                }
                var poolEntry = poolEntries[offer.visualPool % poolEntries.length];
                return {
                    kind: "sealed-abstract",
                    assetUrl: poolEntry.u,
                    sourceKey: "anonymous-visual-pool.v2#" + (offer.visualPool % poolEntries.length),
                    sourceKind: "icon",
                    sourceComposition: "anonymous-visual-pool",
                    previewGender: "neutral",
                    seed: offer.surfaceSeed,
                    autoRotate: true,
                    sharpenSource: true,
                    hiddenColorMode: poolEntry.h || "proxy"
                };
            }
        };

        var auditPort = {
            exportAnonymous: function() {
                return {
                    schemaVersion: "black-market-anonymous-shadow-export.v2",
                    shadowOnly: true,
                    identityBoundary: IDENTITY_BOUNDARY,
                    pageNumber: pageNumber,
                    decryptLevel: decryptLevel,
                    balances: { tradePoints: tradePoints, kPoints: kPoints, supplyCredits: supplyCredits },
                    history: clone(history)
                };
            }
        };

        return { product: productPort, surface: surfacePort, audit: auditPort };
    }

    function createShadowSession(options) {
        return createSessionInternal(options, environment.randomBytes);
    }

    function createTestProductSession(options, entropyLabel) {
        invariant(environment.commonJs, "test entropy seam is not available in the browser product core");
        invariant(isSafeString(entropyLabel, 160), "test entropy label invalid");
        return createSessionInternal(options, deterministicBytes("test-private-" + entropyLabel));
    }

    var exports = {
        SNAPSHOT_SCHEMA: SNAPSHOT_SCHEMA,
        ALGORITHM_VERSION: ALGORITHM_VERSION,
        IDENTITY_BOUNDARY: IDENTITY_BOUNDARY,
        LEVELS: LEVELS.slice(),
        COVERAGE_BY_LEVEL: clone(COVERAGE_BY_LEVEL),
        createShadowSession: createShadowSession,
        hash32: hash32
    };
    if (environment.commonJs) exports.createTestProductSession = createTestProductSession;
    return exports;
});
