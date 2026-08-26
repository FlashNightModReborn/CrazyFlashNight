(function(root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.BlackMarketQA = factory();
    }
})(typeof globalThis !== "undefined" ? globalThis : this, function() {
    "use strict";

    var ExactCore = typeof require === "function"
        ? require("../../../../../../tools/fixtures/blackmarket/exact-oracle-core.js") : null;

    function ok(detail) { return { pass: true, detail: detail || "" }; }
    function fail(detail) { return { pass: false, detail: detail || "" }; }

    function expectThrow(fn, includes) {
        try {
            fn();
        } catch (error) {
            var message = error && error.message ? error.message : String(error);
            return !includes || message.indexOf(includes) >= 0;
        }
        return false;
    }

    function containsCatalogIdentity(value, catalog, key) {
        var forbiddenKeys = {
            seed: true, surfaceSeed: true, itemId: true, itemName: true,
            iconKey: true, iconName: true, assetUri: true, iconUri: true
        };
        if (forbiddenKeys[key]) return true;
        if (typeof value === "string") {
            for (var entryIndex = 0; entryIndex < catalog.entries.length; entryIndex += 1) {
                var entry = catalog.entries[entryIndex];
                if (value === entry.id || value === entry.name || value === entry.displayName
                        || value === entry.source || value === entry.iconKey || value === entry.iconUri) return true;
            }
            return /^icons\/[A-Za-z0-9._-]+$/.test(value) || /^data\/items\//.test(value);
        }
        if (!value || typeof value !== "object") return false;
        var keys = Object.keys(value);
        for (var index = 0; index < keys.length; index += 1) {
            if (containsCatalogIdentity(value[keys[index]], catalog, keys[index])) return true;
        }
        return false;
    }

    function bm1_catalogClosesOverAllItems(Core, catalog) {
        var checked = Core.validateCatalog(catalog);
        if (checked.stats.totalItems !== checked.entries.length) return fail("total item count drift");
        if (checked.stats.totalItems < 1000) return fail("catalog is not full-scale: " + checked.stats.totalItems);
        if (checked.stats.mechanicallyRenderable < 1000) return fail("renderable pool too small");
        var accounted = checked.stats.mechanicallyRenderable + checked.stats.mechanicallyRejected;
        if (accounted !== checked.stats.totalItems) return fail("catalog accounting mismatch");
        var backgroundLeaks = checked.entries.filter(function(entry) {
            if (!entry.mechanicallyRenderable || entry.category === "equipment") return false;
            return !((entry.iconFrameRole === "drop-item-frame" && entry.backgroundNeutral === true
                    && entry.hiddenColorMode === "source")
                || (entry.iconFrameRole === "neutralized-single-frame" && entry.backgroundNeutral === false
                    && entry.hiddenColorMode === "monochrome"));
        });
        if (backgroundLeaks.length) return fail("material/consumable quality background lacks a safe hidden presentation");
        var steel = checked.entries.filter(function(entry) { return entry.displayName === "可塑式钢板"; })[0];
        if (!steel || steel.iconFrame !== "f2" || steel.iconFrameRole !== "drop-item-frame") {
            return fail("可塑式钢板 did not select the background-neutral drop frame");
        }
        var shield = checked.entries.filter(function(entry) { return entry.displayName === "能量干扰盾"; })[0];
        if (!shield || !shield.mechanicallyRenderable || shield.iconFrameRole !== "drop-item-frame"
                || shield.iconFrame !== "f2" || shield.hiddenColorMode !== "source") {
            return fail("能量干扰盾 did not adopt the newly baked semantic f2");
        }
        var dropFrames = checked.entries.filter(function(entry) {
            return entry.mechanicallyRenderable && entry.iconFrameRole === "drop-item-frame";
        }).length;
        var neutralizedFallbacks = checked.entries.filter(function(entry) {
            return entry.mechanicallyRenderable && entry.iconFrameRole === "neutralized-single-frame";
        }).length;
        return ok("total=" + checked.stats.totalItems + ", renderable=" + checked.stats.mechanicallyRenderable
            + ", dropFrames=" + dropFrames + ", neutralizedFallbacks=" + neutralizedFallbacks);
    }

    function bm2_catalogRejectsMalformedEntries(Core, catalog) {
        var broken = JSON.parse(JSON.stringify(catalog));
        var candidate = broken.entries.filter(function(entry) { return entry.mechanicallyRenderable; })[0];
        candidate.price = -1;
        if (!expectThrow(function() { Core.validateCatalog(broken); }, "price")) {
            return fail("negative price was accepted");
        }
        broken = JSON.parse(JSON.stringify(catalog));
        broken.entries[1].id = broken.entries[0].id;
        if (!expectThrow(function() { Core.validateCatalog(broken); }, "duplicated")) {
            return fail("duplicate id was accepted");
        }
        broken = JSON.parse(JSON.stringify(catalog));
        broken.stats.mechanicallyRenderableByCategory.equipment += 1;
        broken.stats.mechanicallyRenderableByCategory.material -= 1;
        if (!expectThrow(function() { Core.validateCatalog(broken); }, "equipment count drift")) {
            return fail("drifted category stats were accepted");
        }
        broken = JSON.parse(JSON.stringify(catalog));
        candidate = broken.entries.filter(function(entry) {
            return entry.mechanicallyRenderable && entry.category === "material"
                && entry.iconFrameRole === "drop-item-frame";
        })[0];
        candidate.backgroundNeutral = false;
        if (!expectThrow(function() { Core.validateCatalog(broken); }, "frame contract")) {
            return fail("background-revealing material icon was accepted");
        }
        return ok("negative price, duplicate id, drifted stats and unsafe icon frame fail closed");
    }

    function bm3_pageIsDeterministic(Core, catalog) {
        var left = Core.buildPage(catalog, "qa-deterministic", 1);
        var right = Core.buildPage(catalog, "qa-deterministic", 1);
        if (JSON.stringify(left) !== JSON.stringify(right)) return fail("same seed produced different pages");
        var other = Core.buildPage(catalog, "qa-deterministic-other", 1);
        if (JSON.stringify(left) === JSON.stringify(other)) return fail("different seed produced identical page");
        return ok("same seed stable, different seed diverges");
    }

    function bm4_pageContract(Core, catalog) {
        var page = Core.buildPage(catalog, "qa-contract", 1);
        if (page.pairs.length !== 3) return fail("expected 3 pairs");
        var itemIds = {};
        for (var i = 0; i < page.pairs.length; i += 1) {
            var pair = page.pairs[i];
            if (pair.offers.length !== 2) return fail("pair does not contain two offers");
            if (pair.offers[0].item.category !== pair.offers[1].item.category
                    || pair.offers[0].item.subclass !== pair.offers[1].item.subclass) {
                return fail("pair category/subclass mismatch");
            }
            for (var j = 0; j < pair.offers.length; j += 1) {
                var id = pair.offers[j].item.id;
                if (itemIds[id]) return fail("item reused in page");
                itemIds[id] = true;
            }
        }
        return ok("3 pairs / 6 unique items / same-subclass pairing");
    }

    function bm5_economyInvariant(Core, catalog) {
        for (var seedIndex = 0; seedIndex < 120; seedIndex += 1) {
            var page = Core.buildPage(catalog, "qa-economy-" + seedIndex, 1);
            for (var i = 0; i < page.pairs.length; i += 1) {
                var pair = page.pairs[i];
                var margins = pair.offers.map(function(offer) { return offer.marginTp; }).sort(function(a, b) { return a - b; });
                if (!(margins[0] <= -1 && margins[1] >= 50)) {
                    return fail("TP margin invariant failed at seed " + seedIndex + ": " + margins.join("/"));
                }
                var kEquivalent = pair.kCost * 50;
                var winner = pair.offers.filter(function(offer) { return offer.marginTp > 0; })[0];
                if (winner.resellTp - kEquivalent < 50) return fail("K margin invariant failed");
            }
        }
        return ok("120 pages satisfy TP/K one-win-one-loss invariants");
    }

    function bm6_coverageParityAndSideBias(Core, catalog) {
        var winnerA = 0;
        var total = 240;
        for (var i = 0; i < total; i += 1) {
            var page = Core.buildPage(catalog, "qa-side-" + i, 1);
            for (var j = 0; j < page.pairs.length; j += 1) {
                if (/\-A$/.test(page.pairs[j].winnerOfferId)) winnerA += 1;
                var parity = page.pairs[j].coverageParity;
                if (!parity || parity.metric !== "object-alpha-pixels" || parity.maxCoverageDelta > 0.002) {
                    return fail("object-alpha coverage budget drift");
                }
                if (page.pairs[j].offers[0].surface.seed === page.pairs[j].offers[1].surface.seed) {
                    return fail("pair sides reused the same surface seed");
                }
            }
        }
        var samples = total * 3;
        var ratio = winnerA / samples;
        if (ratio < 0.42 || ratio > 0.58) return fail("winner-side ratio outside smoke bound: " + ratio);
        return ok("winnerA=" + winnerA + "/" + samples + ", object-alpha budget tolerance<=0.2%");
    }

    function bm7_publicSnapshotHidesIdentity(Core, catalog) {
        var session = Core.createShadowSession({ seed: "qa-secrets" });
        var snapshot = session.product.open();
        if (containsCatalogIdentity(snapshot, catalog, "")) return fail("pre-purchase snapshot contains item identity");
        if (JSON.stringify(snapshot).indexOf("data/items/") >= 0) return fail("pre-purchase snapshot contains source path");
        var text = JSON.stringify(snapshot);
        if (/"(?:seed|surfaceSeed|assetUri|iconUri|itemId|iconKey)"\s*:/.test(text)) {
            return fail("pre-purchase snapshot contains forbidden identity/replay field");
        }
        var handles = [];
        snapshot.pairs.forEach(function(pair) {
            pair.offers.forEach(function(offer) {
                if (!/^opaque-visual-[a-f0-9]{40}$/.test(offer.visualHandle)) {
                    throw new Error("visual handle is not opaque");
                }
                handles.push(offer.visualHandle);
            });
        });
        if (handles.filter(function(value, index) { return handles.indexOf(value) === index; }).length !== 6) {
            return fail("visual handles are not unique");
        }
        return ok("pre-purchase snapshot omits seed/URI/ID/icon keys and exposes six opaque handles");
    }

    function bm8_transactionLifecycle(Core, catalog) {
        var session = Core.createShadowSession({ seed: "qa-lifecycle" });
        var opened = session.product.open();
        var pair = opened.pairs[0];
        var offer = pair.offers[0];
        var preview = session.product.purchasePreview({ pairId: pair.pairId, offerId: offer.offerId, payment: "tp" });
        var otherPreview = session.product.purchasePreview({
            pairId: pair.pairId,
            offerId: pair.offers[1].offerId,
            payment: "tp"
        });
        var committed = session.product.purchaseCommit(preview.token, "qa-purchase");
        if (!committed.pending || committed.pending.offerId !== offer.offerId) return fail("purchase did not create pending state");
        var replay = session.product.purchaseCommit(preview.token, "qa-purchase");
        if (JSON.stringify(replay) !== JSON.stringify(committed)) return fail("purchase replay changed receipt");
        if (!expectThrow(function() {
            session.product.purchaseCommit(otherPreview.token, "qa-purchase");
        }, "callId reused")) return fail("purchase callId accepted a different request");
        var settled = session.product.settle("resell", "qa-settle");
        if (settled.pending !== null || settled.pairs[0].status !== "resold") return fail("resell did not settle pair");
        if (!expectThrow(function() {
            session.product.settle("extract", "qa-settle");
        }, "callId reused")) return fail("settle callId accepted a different request");
        return ok("preview -> request-bound idempotent commit -> resell completed");
    }

    function bm9_insufficientFundsDoNotMutate(Core, catalog) {
        var session = Core.createShadowSession({ seed: "qa-poor", tradePoints: 0, kPoints: 0 });
        var before = session.product.open();
        var pair = before.pairs[0];
        if (!expectThrow(function() {
            session.product.purchasePreview({ pairId: pair.pairId, offerId: pair.offers[0].offerId, payment: "tp" });
        }, "不足")) return fail("insufficient TP was accepted");
        if (!expectThrow(function() {
            session.product.purchasePreview({ pairId: pair.pairId, offerId: pair.offers[0].offerId, payment: "k" });
        }, "不足")) return fail("insufficient K was accepted");
        var after = session.product.open();
        if (JSON.stringify(before) !== JSON.stringify(after)) return fail("failed preview mutated state");
        return ok("TP/K failures leave state unchanged");
    }

    function bm10_productAndLabPortsStaySplit(Core, catalog) {
        var regular = Core.createShadowSession({ seed: "ignored-runtime-seed" });
        if (regular.lab || regular.visual || regular.debug || typeof regular.surface.resolveSurface !== "function") {
            return fail("regular product session exposes exact identity capability");
        }
        if (!ExactCore || typeof ExactCore.createDevelopmentSession !== "function") {
            return fail("independent exact lab core missing");
        }
        var session = ExactCore.createDevelopmentSession(catalog, { seed: "qa-port-split" });
        if (typeof session.product.setDecryptLevel !== "undefined") return fail("lab method leaked into product port");
        if (typeof session.product.reroll !== "undefined") return fail("reroll leaked into product port");
        if (typeof session.product.listCatalog !== "undefined" || typeof session.product.focusItem !== "undefined") {
            return fail("catalog lab method leaked into product port");
        }
        if (typeof session.lab.setDecryptLevel !== "function" || typeof session.lab.reroll !== "function"
                || typeof session.lab.listCatalog !== "function" || typeof session.lab.focusItem !== "function") {
            return fail("lab port missing controls");
        }
        var changed = session.lab.setDecryptLevel(10);
        if (changed.decryptLevel !== 10) return fail("lab level control failed");
        var listed = session.lab.listCatalog({ query: "", offset: 0, limit: 24 });
        if (listed.total !== catalog.stats.mechanicallyRenderable || listed.items.length !== 24) {
            return fail("lab catalog does not cover the renderable pool");
        }
        var all = [];
        for (var offset = 0; offset < listed.total; offset += 24) {
            var pageOfItems = session.lab.listCatalog({ query: "", offset: offset, limit: 24 });
            if (pageOfItems.total !== listed.total) return fail("lab catalog total drifted across pages");
            all = all.concat(pageOfItems.items);
        }
        if (all.length !== listed.total) return fail("lab catalog pagination lost entries");
        var ids = {};
        for (var itemIndex = 0; itemIndex < all.length; itemIndex += 1) {
            if (ids[all[itemIndex].id]) return fail("lab catalog pagination duplicated an item");
            ids[all[itemIndex].id] = true;
        }
        var focusedCount = 0;
        for (var sampleIndex = 0; sampleIndex < 12; sampleIndex += 1) {
            var target = all[Math.floor(sampleIndex * (all.length - 1) / 11)];
            var focused = session.lab.focusItem(target.id);
            var page = session.debug.page();
            var present = page.pairs.some(function(pair) {
                return pair.offers.some(function(offer) { return offer.item.id === target.id; });
            });
            if (!present || focused.focus.itemId !== target.id) return fail("lab focus did not place requested item");
            if (ExactCore.publicSnapshotContainsIdentity(focused.snapshot, catalog)) return fail("focused public snapshot leaked identity");
            focusedCount += 1;
        }
        return ok("product/lab split + " + all.length + " indexed / " + focusedCount + " focused samples");
    }

    function bm20_kLedgerUsesExplicitUnits(Core, catalog) {
        function settle(action, suffix) {
            var session = typeof Core.createTestProductSession === "function"
                ? Core.createTestProductSession({
                seed: "qa-k-ledger-" + suffix, tradePoints: 500000, kPoints: 10000
                }, "qa-k-ledger-" + suffix)
                : Core.createShadowSession({ tradePoints: 500000, kPoints: 10000 });
            var opened = session.product.open();
            var pair = opened.pairs[0];
            var offer = pair.offers[0];
            var before = opened.balances;
            var preview = session.product.purchasePreview({
                pairId: pair.pairId, offerId: offer.offerId, payment: "k"
            });
            var committed = session.product.purchaseCommit(preview.token, "qa-k-purchase-" + suffix);
            var revealed = committed.pairs[0].offers.filter(function(candidate) {
                return candidate.offerId === offer.offerId;
            })[0].revealed;
            if (revealed.payment !== "k" || revealed.paidAmount !== pair.kCost
                    || revealed.deltaTp !== revealed.resellValue || revealed.deltaK !== -pair.kCost
                    || revealed.deltaV !== revealed.deltaTp + revealed.deltaK * 50) {
                throw new Error(action + " reveal ledger breakdown drifted");
            }
            var settled = session.product.settle(action, "qa-k-settle-" + suffix);
            var row = session.audit.exportAnonymous().history[0];
            var expectedTp = action === "resell" ? revealed.resellValue : 0;
            var expectedK = -pair.kCost;
            if (row.deltaTp !== expectedTp || row.deltaK !== expectedK
                    || row.deltaV !== expectedTp + expectedK * 50) {
                throw new Error(action + " ledger unit mismatch: " + JSON.stringify(row));
            }
            if (settled.balances.tradePoints - before.tradePoints !== expectedTp
                    || settled.balances.kPoints - before.kPoints !== expectedK) {
                throw new Error(action + " balance delta does not match ledger");
            }
            return row;
        }
        var extracted = settle("extract", "extract");
        var resold = settle("resell", "resell");
        if (extracted.deltaTp !== 0 || extracted.deltaK >= 0 || resold.deltaK >= 0) {
            return fail("K settlement was recorded in the TP column");
        }
        return ok("K extract/resell record explicit deltaTp/deltaK and ΔV=deltaTp+50*deltaK");
    }

    function bm21_publicInputsCannotReplayIdentity(Core, catalog) {
        if (typeof Core.createTestProductSession !== "function") {
            return ok("browser product core correctly omits the deterministic entropy injection seam; Node gate owns replay proof");
        }
        function inspect(entropyLabel, callerSeed, suffix) {
            var session = Core.createTestProductSession({ seed: callerSeed }, entropyLabel);
            if (session.lab || session.visual || session.debug) return fail("regular session exposes exact port");
            var opened = session.product.open();
            var allHandles = [];
            opened.pairs.forEach(function(candidatePair) {
                candidatePair.offers.forEach(function(candidateOffer) {
                    allHandles.push(candidateOffer.visualHandle);
                });
            });
            if (allHandles.filter(function(value, index) { return allHandles.indexOf(value) === index; }).length !== 6) {
                throw new Error("injected entropy did not produce six unique opaque handles");
            }
            var pair = opened.pairs[0];
            var offer = pair.offers[0];
            var safeSurface = session.surface.resolveSurface(offer.visualHandle);
            // 视觉池时代（2026-08-26 设计确认：覆泥像素允许被认出，价格目录才是答案钥匙）：
            // 公开表面只允许两种形态——清单内图标路径（内容哈希文件名，零身份）或固定安全 SVG
            // 回退；URL 不得携带任何名称/ID 类身份字段（iconUri 即资产本体，不再视为泄漏）。
            var poolSurface = /^icons\/[0-9a-f]+_\d+\.webp$/.test(safeSurface.assetUrl);
            if (!poolSurface && !/^data:image\/svg\+xml/.test(safeSurface.assetUrl)) {
                throw new Error("public surface requested a catalog URI");
            }
            for (var entryIndex = 0; entryIndex < catalog.entries.length; entryIndex += 1) {
                var catalogEntry = catalog.entries[entryIndex];
                var identityFields = [catalogEntry.iconKey,
                    catalogEntry.name, catalogEntry.displayName, catalogEntry.id];
                for (var fieldIndex = 0; fieldIndex < identityFields.length; fieldIndex += 1) {
                    var identityValue = identityFields[fieldIndex];
                    if (typeof identityValue === "string" && identityValue
                            && safeSurface.assetUrl.indexOf(identityValue) >= 0) {
                        throw new Error("safe surface embeds a catalog identity field");
                    }
                }
            }
            var preview = session.product.purchasePreview({
                pairId: pair.pairId, offerId: offer.offerId, payment: "tp"
            });
            var committed = session.product.purchaseCommit(preview.token, "qa-entropy-purchase-" + suffix);
            var revealed = committed.pairs[0].offers.filter(function(candidate) {
                return candidate.offerId === offer.offerId;
            })[0].revealed;
            return { opened: opened, revealedName: revealed.displayName,
                safeSurfaceSeed: safeSurface.seed };
        }

        var first = inspect("fixed-private-entropy", "caller-seed-A", "same-a");
        var second = inspect("fixed-private-entropy", "caller-seed-B", "same-b");
        if (first.opened.page.id !== second.opened.page.id
                || first.opened.pairs[0].offers[0].visualHandle !== second.opened.pairs[0].offers[0].visualHandle
                || first.revealedName !== second.revealedName
                || first.safeSurfaceSeed !== second.safeSurfaceSeed) {
            return fail("caller-controlled seed changed a session driven by identical injected private entropy");
        }
        var different = null;
        for (var i = 0; i < 32 && !different; i += 1) {
            var candidate = inspect("different-private-entropy-" + i, "caller-seed-A", "different-" + i);
            if (candidate.opened.page.id !== first.opened.page.id
                    && candidate.opened.pairs[0].offers[0].visualHandle
                        !== first.opened.pairs[0].offers[0].visualHandle
                    && candidate.revealedName !== first.revealedName
                    && candidate.safeSurfaceSeed !== first.safeSurfaceSeed) different = candidate;
        }
        if (!different) return fail("different injected private entropy did not change hidden identity/handles");
        return ok("deterministic test entropy proves caller seed ignored; independent private streams control identity/handles/surface");
    }

    function bm22_productRejectsExactDirectoryAndInference(Core, catalog) {
        if (!expectThrow(function() { Core.createShadowSession(catalog); }, "does not accept an exact directory")) {
            return fail("product core accepted the exact catalog object");
        }
        if (typeof Core.createDevelopmentSession === "function" || typeof Core.validateCatalog === "function"
                || typeof Core.buildPage === "function") {
            return fail("product core still exports an exact catalog or Lab capability");
        }
        var snapshot = Core.createShadowSession({ decryptLevel: 3 }).product.open();
        if (snapshot.catalog.kind !== "anonymous-synthetic"
                || snapshot.identityBoundary !== "anonymous-synthetic-no-catalog.v2") {
            return fail("product snapshot is not bound to the anonymous fixture contract");
        }
        for (var pairIndex = 0; pairIndex < snapshot.pairs.length; pairIndex += 1) {
            var pair = snapshot.pairs[pairIndex];
            var possible = catalog.entries.filter(function(entry) {
                return entry.mechanicallyRenderable && entry.category === pair.category
                    && entry.subclass === pair.subclass
                    && (entry.saleValue < pair.counterPriceTp
                        || entry.saleValue >= pair.counterPriceTp + 50);
            });
            if (possible.length !== 0) {
                return fail("public category/subclass/price tuple still maps into the exact catalog");
            }
        }
        return ok("product rejects exact input; anonymous taxonomy/price tuples map to zero real catalog entries");
    }

    // 同舱同组配对约束（对齐 exact oracle 的 same-subclass-price-strata 设计）：
    // 同一货舱左右两件视觉必须同组且不同件，同页六件零撞车。
    function bm23_pairVisualsStayInSameSubclassGroup(Core, catalog) {
        if (typeof Core.createTestProductSession !== "function") {
            return ok("browser product core correctly omits the deterministic entropy injection seam; Node gate owns pair grouping proof");
        }
        var manifest;
        try {
            manifest = require("../visual/visual-pool-manifest.js");
        } catch (error) {
            return fail("visual pool manifest unreadable: " + error.message);
        }
        if (!manifest || !Array.isArray(manifest.entries) || manifest.entries.length < 6) {
            return fail("visual pool manifest missing or too small");
        }
        var groupByUri = {};
        manifest.entries.forEach(function(entry) { groupByUri[entry.u] = String(entry.g || "?"); });
        var session = Core.createTestProductSession({ decryptLevel: 3 }, "pair-group-proof");
        var opened = session.product.open();
        var seen = {};
        for (var pairIndex = 0; pairIndex < opened.pairs.length; pairIndex += 1) {
            var pair = opened.pairs[pairIndex];
            var urlA = session.surface.resolveSurface(pair.offers[0].visualHandle).assetUrl;
            var urlB = session.surface.resolveSurface(pair.offers[1].visualHandle).assetUrl;
            if (urlA === urlB) return fail("pair shares the same visual asset " + urlA);
            if (groupByUri[urlA] === undefined || groupByUri[urlB] === undefined) {
                return fail("pair visual escaped the pool manifest");
            }
            if (groupByUri[urlA] !== groupByUri[urlB]) {
                return fail("pair visuals escaped the same-group constraint: "
                    + groupByUri[urlA] + " vs " + groupByUri[urlB]);
            }
            [urlA, urlB].forEach(function(url) {
                if (seen[url]) throw new Error("page visual collides across pairs: " + url);
                seen[url] = true;
            });
        }
        return ok("same-group pairs / six distinct page visuals from " + manifest.entries.length + " entries");
    }

    // 揭晓注释释放（2026-08-26 产品决策）：允许物品（e!=="banned"）成交后给出真实身份与
    // 目录参考价；购买前快照与 offer 投影仍然零身份字段（盲盒猜测层不破）。
    function bm24_revealReleasesRealInfoOnlyAfterPurchase(Core, catalog) {
        if (typeof Core.createTestProductSession !== "function") {
            return ok("browser product core correctly omits the deterministic entropy injection seam; Node gate owns reveal-release proof");
        }
        var manifest = require("../visual/visual-pool-manifest.js");
        var byUri = {};
        manifest.entries.forEach(function(entry) { byUri[entry.u] = entry; });
        var session = Core.createTestProductSession({ decryptLevel: 3 }, "reveal-release-proof");
        var opened = session.product.open();
        // 购买前：投影与快照序列化不得含任何清单身份字段
        var preJson = JSON.stringify(opened);
        for (var nameIndex = 0; nameIndex < manifest.entries.length; nameIndex += 1) {
            var sampleName = manifest.entries[nameIndex].n;
            if (sampleName && sampleName.length >= 2 && preJson.indexOf(sampleName) >= 0) {
                return fail("pre-purchase snapshot leaks identity: " + sampleName);
            }
        }
        // 成交后：揭示载荷必须带与视觉一致的真实信息
        var pair = opened.pairs[0];
        var offer = pair.offers[0];
        var assetUri = session.surface.resolveSurface(offer.visualHandle).assetUrl;
        var entry = byUri[assetUri];
        if (!entry) return fail("offer visual escaped the pool manifest");
        var preview = session.product.purchasePreview({ pairId: pair.pairId, offerId: offer.offerId, payment: "tp" });
        var committed = session.product.purchaseCommit(preview.token, "qa-reveal-release");
        var revealed = committed.pairs[0].offers[0].revealed;
        if (!revealed || !revealed.realInfo) return fail("revealed payload missing realInfo for releasable entry");
        if (revealed.realInfo.name !== entry.n || revealed.displayName !== entry.n) {
            return fail("revealed identity mismatches the visual pool entry");
        }
        if (revealed.realInfo.catalogPrice !== entry.p || revealed.realInfo.saleValue !== entry.s) {
            return fail("revealed reference prices mismatch the catalog annotation");
        }
        return ok("pre-purchase anonymous / post-purchase real annotation released ("
            + entry.n + " " + entry.p + "TP)");
    }

    // 调试抽屉白名单：只允许 tradePoints/kPoints/supplyCredits/decryptLevel/seed 五个数值域，
    // 任意参数下快照仍保持匿名边界（类目三元组零命中真实目录），覆盖率随解密等级联动。
    function bm25_debugSessionParamsStayWhitelistedAndAnonymous(Core, catalog) {
        var session = Core.createShadowSession({
            decryptLevel: 10, tradePoints: 123456, kPoints: 789, supplyCredits: 9
        });
        var snap = session.product.open();
        if (snap.decryptLevel !== 10 || snap.mudCoverage !== 0.18) {
            return fail("decrypt level 10 did not drive mud coverage 0.18");
        }
        if (snap.balances.tradePoints !== 123456 || snap.balances.kPoints !== 789
                || snap.balances.supplyCredits !== 9) {
            return fail("session economic options not honored");
        }
        for (var pairIndex = 0; pairIndex < snap.pairs.length; pairIndex += 1) {
            var pair = snap.pairs[pairIndex];
            var possible = catalog.entries.filter(function(entry) {
                return entry.mechanicallyRenderable && entry.category === pair.category
                    && entry.subclass === pair.subclass
                    && (entry.saleValue < pair.counterPriceTp
                        || entry.saleValue >= pair.counterPriceTp + 50);
            });
            if (possible.length !== 0) {
                return fail("custom session params broke the anonymous taxonomy boundary");
            }
        }
        if (typeof Core.createTestProductSession !== "function") {
            return ok("whitelist honored; replay-seam proof stays on the Node gate");
        }
        var rejected = false;
        try {
            Core.createShadowSession({ catalog: catalog });
        } catch (error) {
            rejected = /exact directory|unknown fields/.test(error.message);
        }
        if (!rejected) return fail("non-whitelisted option accepted");
        return ok("four whitelisted params honored (Lv.10->18% coverage); catalog injection still rejected");
    }

    function makeSynthetic(width, height, painter, opaqueBackground) {
        var data = new Uint8ClampedArray(width * height * 4);
        var x;
        var y;
        for (y = 0; y < height; y += 1) {
            for (x = 0; x < width; x += 1) {
                var offset = (y * width + x) * 4;
                if (opaqueBackground) {
                    data[offset] = 18;
                    data[offset + 1] = 65;
                    data[offset + 2] = 59;
                    data[offset + 3] = 255;
                }
                if (painter(x, y)) {
                    data[offset] = 92;
                    data[offset + 1] = 96;
                    data[offset + 2] = 101;
                    data[offset + 3] = 255;
                }
            }
        }
        return { width: width, height: height, data: data };
    }

    function syntheticRifle(opaqueBackground) {
        return makeSynthetic(72, 64, function(x, y) {
            return (x >= 9 && x <= 63 && y >= 25 && y <= 34)
                || (x >= 9 && x <= 23 && y >= 17 && y <= 42)
                || (x >= 34 && x <= 41 && y >= 33 && y <= 51);
        }, opaqueBackground);
    }

    function bm11_autoOrientationAndAnchor(Core, catalog, Surface) {
        if (!Surface || Surface.VERSION !== "object-sdf-nanobot-sludge.v2") return fail("surface module missing");
        var plan = Surface.planOrientation(syntheticRifle(false), 180, 340, { seed: "qa-rifle" });
        if (Math.abs(plan.degrees) !== 90) return fail("horizontal rifle was not rotated into portrait well");
        if (plan.anchor.normalizedX >= 0.45) return fail("broad stock was not selected as automatic breakpoint");
        if (plan.outputAnchor.y >= 150) return fail("selected stock did not rotate toward the top breakout zone");
        if (plan.anchor.method !== "pca-pruned-skeleton" || plan.anchor.confidence <= 0.2) {
            return fail("automatic anchor lacks method/confidence evidence");
        }
        return ok("rotation=" + plan.degrees + "°, stock=" + plan.anchor.normalizedX + "/"
            + plan.anchor.normalizedY + ", confidence=" + plan.anchor.confidence);
    }

    function bm12_alphaSegmentationAndSdf(Core, catalog, Surface) {
        var image = syntheticRifle(true);
        var extraction = Surface.extractObjectMask(image);
        if (extraction.source !== "edge-segmented-alpha") return fail("opaque icon did not use edge segmentation");
        if (extraction.bounds.count < 350 || extraction.bounds.count > 1700) {
            return fail("opaque background leaked into object alpha: " + extraction.bounds.count);
        }
        var sdf = Surface.signedDistance(extraction.mask, image.width, image.height);
        var objectIndex = 28 * image.width + 16;
        var backgroundIndex = 2 * image.width + 2;
        if (!(sdf[objectIndex] > 0 && sdf[backgroundIndex] < 0)) return fail("SDF sign convention drift");
        var unresolvedCrop = makeSynthetic(48, 48, function() { return true; }, true);
        var cropExtraction = Surface.extractObjectMask(unresolvedCrop);
        if (cropExtraction.source !== "opaque-alpha-fallback" || cropExtraction.bounds.count !== 48 * 48
                || cropExtraction.confidence >= 0.2) {
            return fail("unsegmentable close-up did not fail visible with low-confidence evidence");
        }
        return ok(extraction.source + ", alpha=" + extraction.bounds.count
            + ", signed SDF stable; close-up fallback remains visible/low-confidence");
    }

    function bm13_exactObjectCoverage(Core, catalog, Surface) {
        var rifle = syntheticRifle(false);
        var compact = makeSynthetic(72, 64, function(x, y) {
            var dx = x - 35;
            var dy = y - 32;
            return dx * dx / 420 + dy * dy / 260 <= 1 || (x > 45 && x < 59 && y > 26 && y < 38);
        }, false);
        var left = Surface.renderSurfaceImageData(rifle, { seed: "coverage-left", coverage: 0.84 });
        var right = Surface.renderSurfaceImageData(compact, { seed: "coverage-right", coverage: 0.84 });
        var leftTolerance = 1 / left.metrics.objectPixels + 1e-6;
        var rightTolerance = 1 / right.metrics.objectPixels + 1e-6;
        if (Math.abs(left.metrics.coverageDelta) > leftTolerance
                || Math.abs(right.metrics.coverageDelta) > rightTolerance) {
            return fail("actual object coverage missed exact pixel budget");
        }
        if (Math.abs(left.metrics.actualCoverage - right.metrics.actualCoverage) > 0.002) {
            return fail("shape-dependent coverage parity drift");
        }
        return ok("rifle=" + left.metrics.actualCoverage + ", compact=" + right.metrics.actualCoverage);
    }

    function bm14_surfaceDeterminism(Core, catalog, Surface) {
        var image = syntheticRifle(false);
        var first = Surface.renderSurfaceImageData(image, { seed: "surface-repeat", coverage: 0.54, debug: true });
        var second = Surface.renderSurfaceImageData(image, { seed: "surface-repeat", coverage: 0.54, debug: true });
        var different = Surface.renderSurfaceImageData(image, { seed: "surface-other", coverage: 0.54, debug: true });
        var same = true;
        var diverged = false;
        for (var i = 0; i < first.imageData.data.length; i += 1) {
            if (first.imageData.data[i] !== second.imageData.data[i]) same = false;
            if (first.imageData.data[i] !== different.imageData.data[i]) diverged = true;
        }
        if (!same) return fail("same seed produced different surface pixels");
        if (!diverged) return fail("different seed did not vary the heightfield");
        return ok("same-seed byte stable; different seed varies attached nanobot sludge");
    }

    function bm17_dormantNanobotMaterial(Core, catalog, Surface) {
        var image = syntheticRifle(false);
        var rendered = Surface.renderSurfaceImageData(image, { seed: "dormant-material", coverage: 0.84 });
        var metrics = rendered.metrics;
        var snapshot = Core.createShadowSession({ seed: "dormant-material-contract" }).product.open();
        if (snapshot.algorithmVersion !== Surface.VERSION
                || snapshot.pairs[0].offers[0].surface.algorithmVersion !== Surface.VERSION) {
            return fail("core/surface nanobot algorithm version drift");
        }
        if (metrics.materialProfile !== "dormant-military-nanobots.v1"
                || metrics.materialMotion !== "static-dormant") {
            return fail("surface did not report the dormant military nanobot material");
        }
        if (metrics.nanoCellPitchPx < 4 || metrics.nanoCellPitchPx > 36
                || metrics.swarmSeamPixels <= 0 || metrics.dormantNodePixels <= 0
                || metrics.metallicFleckPixels <= 0) {
            return fail("nanobot seams/nodes/metal flecks were not materially present");
        }
        var tolerance = 1 / metrics.objectPixels + 1e-6;
        if (Math.abs(metrics.coverageDelta) > tolerance) {
            return fail("nanobot material changed the exact object coverage budget");
        }
        return ok("static dormant material; seams=" + metrics.swarmSeamPixels
            + ", nodes=" + metrics.dormantNodePixels + ", flecks=" + metrics.metallicFleckPixels);
    }

    function bm15_armorUsesPrivatePaperDollPort(Core, catalog, Surface, EquipmentPreview) {
        if (!EquipmentPreview || EquipmentPreview.VERSION !== "equipment-focus-preview.v3") {
            return fail("equipment preview module missing");
        }
        var target = catalog.entries.filter(function(entry) {
            return entry.displayName === "黄金骑士牙狼胸甲";
        })[0];
        if (!target) return fail("牙狼胸甲 catalog entry missing");
        var session = Core.createDevelopmentSession(catalog, { seed: "qa-paperdoll-source" });
        var focused = session.lab.focusItem(target.id);
        var source = session.visual.resolveOfferSource(focused.focus.visualHandle);
        if (source.kind !== "dressup-paperdoll" || source.slot !== "body"
                || source.itemName !== target.name) {
            return fail("牙狼胸甲 did not resolve to its private paper-doll source");
        }
        var plan = EquipmentPreview.resolvePlan(source, { gender: "女" });
        if (plan.kind !== "dressup-paperdoll" || plan.autoRotate !== false
                || plan.itemName !== target.name || plan.slot !== "body"
                || plan.use !== "上装装备" || plan.gender !== "女") {
            return fail("paper-doll render plan drifted");
        }
        if (Core.publicSnapshotContainsIdentity(focused.snapshot, catalog)) {
            return fail("private paper-doll identity leaked into public snapshot");
        }
        var pair = focused.snapshot.pairs.filter(function(candidate) {
            return candidate.pairId === focused.focus.pairId;
        })[0];
        var pairSources = pair && pair.offers.map(function(offer) {
            return session.visual.resolveOfferSource(offer.visualHandle);
        });
        if (!pairSources || pairSources[0].previewGender !== pairSources[1].previewGender) {
            return fail("paired armor previews did not share one deterministic gender branch");
        }
        return ok("牙狼胸甲 -> equipment-inspector focused paper doll; identity remains outside public snapshot");
    }

    function bm16_armorDressupCoverage(Core, catalog, Surface, EquipmentPreview, DressupManifest) {
        if (!EquipmentPreview || !DressupManifest) return fail("dressup coverage inputs missing");
        var coverage = EquipmentPreview.validateArmorCoverage(catalog, DressupManifest);
        if (coverage.candidates < 450 || coverage.covered !== coverage.candidates || coverage.missing.length) {
            return fail("renderable non-neck armor lacks complete paper-doll coverage: "
                + coverage.covered + "/" + coverage.candidates);
        }
        if (coverage.partialGender.length !== 16 || coverage.maleOnly !== 2
                || coverage.femaleOnly !== 14) {
            return fail("gender-specific equipment-focus closure drifted");
        }
        var expected = ["黄金骑士牙狼胸甲", "黄金骑士牙狼腿甲", "TheGirl下装"];
        for (var i = 0; i < expected.length; i += 1) {
            var item = DressupManifest.items && DressupManifest.items[expected[i]];
            if (!item || !item.fieldsByGender || !item.fieldsByGender["男"] || !item.fieldsByGender["女"]
                    || Object.keys(item.fieldsByGender["男"]).length < 4
                    || Object.keys(item.fieldsByGender["女"]).length < 4) {
                return fail(expected[i] + " is not a multi-part dressup item");
            }
        }
        return ok("non-neck armor focused paper-doll coverage=" + coverage.covered + "/" + coverage.candidates
            + "; gender-specific=16; 牙狼胸/腿与 TheGirl 下装均为多部件局部");
    }

    function bm18_alphaSafeProxySharpening(Core, catalog, Surface) {
        if (!Surface || typeof Surface.sharpenSourceImageData !== "function") {
            return fail("alpha-safe sharpening API missing");
        }
        var width = 7;
        var height = 5;
        var data = new Uint8ClampedArray(width * height * 4);
        for (var y = 0; y < height; y += 1) {
            for (var x = 0; x < width; x += 1) {
                var offset = (y * width + x) * 4;
                var value = x < 3 ? 48 : 184;
                data[offset] = value;
                data[offset + 1] = value;
                data[offset + 2] = value;
                data[offset + 3] = x === 0 && y === 0 ? 0 : 255;
            }
        }
        var source = { width: width, height: height, data: data };
        var sharpened = Surface.sharpenSourceImageData(source, 0.18);
        for (var index = 3; index < data.length; index += 4) {
            if (sharpened.data[index] !== data[index]) return fail("sharpening changed Alpha coverage");
        }
        var left = (2 * width + 2) * 4;
        var right = (2 * width + 3) * 4;
        if (sharpened.data[right] - sharpened.data[left] <= data[right] - data[left]) {
            return fail("proxy edge contrast did not increase");
        }
        return ok("RGB edge contrast increased while Alpha bytes remained identical");
    }

    function bm19_weaponUsesPrivateDressupPort(Core, catalog, Surface, EquipmentPreview) {
        var target = catalog.entries.filter(function(entry) {
            return entry.displayName === "剧毒蛇矛";
        })[0];
        if (!target) return fail("剧毒蛇矛 catalog entry missing");
        var session = Core.createDevelopmentSession(catalog, { seed: "qa-weapon-source" });
        var focused = session.lab.focusItem(target.id);
        var source = session.visual.resolveOfferSource(focused.focus.visualHandle);
        if (source.kind !== "dressup-weapon" || source.itemName !== target.name
                || source.actionType !== target.actionType) {
            return fail("weapon did not resolve to its private dressup source");
        }
        var plan = EquipmentPreview.resolvePlan(source, { gender: "男" });
        if (plan.kind !== "dressup-weapon" || plan.autoRotate !== true
                || plan.itemName !== target.name || plan.itemType !== "武器") {
            return fail("weapon dressup render plan drifted");
        }
        if (Core.publicSnapshotContainsIdentity(focused.snapshot, catalog)) {
            return fail("private weapon identity leaked into public snapshot");
        }
        return ok("剧毒蛇矛 -> equipment-inspector weapon source; public snapshot remains sealed");
    }

    var SUITE = [
        { id: "bm1", title: "全量物品目录闭包", run: bm1_catalogClosesOverAllItems },
        { id: "bm2", title: "目录畸形输入 fail-closed", run: bm2_catalogRejectsMalformedEntries },
        { id: "bm3", title: "相同种子确定性", run: bm3_pageIsDeterministic },
        { id: "bm4", title: "三组六件与同类配对", run: bm4_pageContract },
        { id: "bm5", title: "TP/K 一赚一赔经济不变量", run: bm5_economyInvariant },
        { id: "bm6", title: "左右赢家与物品 Alpha 覆盖预算", run: bm6_coverageParityAndSideBias },
        { id: "bm7", title: "购买前公开快照不含身份", run: bm7_publicSnapshotHidesIdentity },
        { id: "bm8", title: "影子交易幂等生命周期", run: bm8_transactionLifecycle },
        { id: "bm9", title: "余额不足零写", run: bm9_insufficientFundsDoNotMutate },
        { id: "bm10", title: "生产形状端口与实验端口隔离", run: bm10_productAndLabPortsStaySplit },
        { id: "bm11", title: "长物品自动旋转与破局锚点", run: bm11_autoOrientationAndAnchor },
        { id: "bm12", title: "不透明背景 Alpha 分割与有符号距离场", run: bm12_alphaSegmentationAndSdf },
        { id: "bm13", title: "异形物品实际覆盖率像素预算", run: bm13_exactObjectCoverage },
        { id: "bm14", title: "纳米污泥材质确定性", run: bm14_surfaceDeterminism },
        { id: "bm15", title: "防具私有纸娃娃视觉端口", run: bm15_armorUsesPrivatePaperDollPort },
        { id: "bm16", title: "非颈部防具局部纸娃娃闭包", run: bm16_armorDressupCoverage },
        { id: "bm17", title: "休眠军用纳米污泥材质", run: bm17_dormantNanobotMaterial },
        { id: "bm18", title: "低清代理保 Alpha 锐化", run: bm18_alphaSafeProxySharpening },
        { id: "bm19", title: "武器私有完整素材端口", run: bm19_weaponUsesPrivateDressupPort },
        { id: "bm20", title: "K 点结算账本显式单位与价值守恒", run: bm20_kLedgerUsesExplicitUnits },
        { id: "bm21", title: "公开输入不能离线重放精确身份", run: bm21_publicInputsCannotReplayIdentity },
        { id: "bm22", title: "产品 core 拒绝精确目录与三元组反查", run: bm22_productRejectsExactDirectoryAndInference },
        { id: "bm23", title: "同舱视觉同组配对且同页零撞车", run: bm23_pairVisualsStayInSameSubclassGroup },
        { id: "bm24", title: "揭晓后才释放真实注释且购买前零身份", run: bm24_revealReleasesRealInfoOnlyAfterPurchase },
        { id: "bm25", title: "调试参数白名单且任意参数不破匿名边界", run: bm25_debugSessionParamsStayWhitelistedAndAnonymous }
    ];

    function runOne(Core, catalog, Surface, EquipmentPreview, DressupManifest, id) {
        var item = SUITE.filter(function(candidate) { return candidate.id === id; })[0];
        if (!item) return { id: id, title: "unknown", pass: false, detail: "case not found" };
        try {
            var exactCases = { bm1: true, bm2: true, bm3: true, bm4: true, bm5: true, bm6: true,
                bm15: true, bm16: true, bm19: true };
            var selectedCore = exactCases[id] ? ExactCore : Core;
            if (!selectedCore) throw new Error("required core module missing for " + id);
            var result = item.run(selectedCore, catalog, Surface, EquipmentPreview, DressupManifest);
            return { id: item.id, title: item.title, pass: !!result.pass, detail: result.detail || "" };
        } catch (error) {
            return { id: item.id, title: item.title, pass: false,
                detail: error && error.stack ? error.stack : String(error) };
        }
    }

    function runAll(Core, catalog, Surface, EquipmentPreview, DressupManifest) {
        var results = SUITE.map(function(item) {
            return runOne(Core, catalog, Surface, EquipmentPreview, DressupManifest, item.id);
        });
        return {
            results: results,
            passed: results.filter(function(item) { return item.pass; }).length,
            failed: results.filter(function(item) { return !item.pass; }).length,
            total: results.length
        };
    }

    return { cases: SUITE.slice(), runOne: runOne, runAll: runAll };
});
