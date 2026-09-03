var BlackMarketPanel = (function() {
    "use strict";

    var _el = null;
    var _root = null;
    var _scaleShell = null;
    var _scaleHandle = null;
    var _session = null;
    var _snapshot = null;
    var _init = null;
    var _selectedPairId = null;
    var _selectedOfferId = null;
    var _payment = "tp";
    var _preview = null;
    var _busy = false;
    var _error = null;
    var _drawer = null;
    var _drawerOpenerKey = null;
    var _panelOpen = false;
    var _closePending = false;
    var _closeTimer = null;
    var _openGeneration = 0;
    var _callSequence = 0;
    // O1 软锁观测：默认关闭，只在 Host 明确下发 softlockObservation=true 时启动。
    // 这条低频 timer 只上报脱敏只读 tuple，不包含 timeout/repair/retry/close 行为。
    var _softlockObservationTimer = null;
    var _softlockObservationSequence = 0;
    var _surfaceRenderer = null;
    var _surfaceMetrics = {};
    var _surfaceSnapshotKey = null;
    var _surfaceGeneration = 0;
    var _surfaceMasters = {};
    var _inspection = null;
    var _inspectionCamera = null;
    // P2 编舞状态：_fxRevealKey 记录已播过揭晓 FX 的 pending 键（防重放），
    // _fxBoot 只在本轮打开的首次 render 输出通电过场。FX 全部 pointer-events:none，
    // 不拦截任何操作，逻辑时序不变。
    var _fxRevealKey = null;
    var _fxBoot = false;
    var _fxActiveRevealKey = null;
    // 撤回闸门动画门禁：innerHTML 每次渲染都会重建 DOM，不设门禁就会随无关操作重放。
    // 按页记录已播过的舱位，同页同舱只播一次。
    var _fxShutterPage = null;
    var _fxShutterPlayed = {};

    // 与主 SWF / FlashCoordinateMapper / 既有 Web Panel 共用同一逻辑画布；
    // 物理窗口只由 PanelScale 整体等比缩放，禁止在本面板内按 viewport 重排。
    var DESIGN_WIDTH = 1024;
    var DESIGN_HEIGHT = 576;
    var SURFACE_MASTER_WIDTH = 512;
    var SURFACE_MASTER_HEIGHT = 768;
    var INSPECTION_MAX_ZOOM = 4;

    var DEFAULT_INIT = {
        mode: "",
        source: "",
        shadowOnly: false,
        debug: false,
        softlockObservation: false
    };

    if (typeof Panels !== "undefined") {
        Panels.register("blackmarket", {
            create: createDOM,
            onOpen: onOpen,
            onRebind: onRebind,
            onRequestClose: closePanel,
            onClose: cleanup,
            onForceClose: cleanup
        });
    }
    if (typeof window !== "undefined" && window.addEventListener) {
        window.addEventListener("pagehide", clearSoftlockObservation);
    }

    function createDOM() {
        _scaleShell = document.createElement("div");
        _scaleShell.className = "panel-scale-shell blackmarket-scale-shell";
        _el = document.createElement("div");
        _el.className = "minigame-panel blackmarket-panel";
        _el.innerHTML = '<div class="blackmarket-boot" data-bm-root>黑市检货台正在接入匿名影子夹具…</div>';
        _scaleShell.appendChild(_el);
        _root = _el.querySelector("[data-bm-root]");
        _el.addEventListener("click", handleClick);
        _el.addEventListener("keydown", handleKeydown);
        _el.addEventListener("mouseover", handleTipOver);
        _el.addEventListener("mouseout", handleTipOut);
        // 备注：tooltip 本体是全局面板组件 PanelTooltip（#panel-tooltip），不在本面板 DOM 内
        return _scaleShell;
    }

    function onOpen(el, initData) {
        clearCloseTimer();
        var generation = ++_openGeneration;
        _panelOpen = true;
        _closePending = false;
        _init = sanitizeInit(initData);
        _session = null;
        _snapshot = null;
        _selectedPairId = null;
        _selectedOfferId = null;
        _payment = "tp";
        _preview = null;
        _drawer = null;
        _drawerOpenerKey = null;
        _busy = false;
        _error = null;
        _surfaceMetrics = {};
        _surfaceMasters = {};
        _surfaceSnapshotKey = null;
        _inspection = null;
        _fxRevealKey = null;
        _fxBoot = true;
        _fxActiveRevealKey = null;
        _fxShutterPage = null;
        _fxShutterPlayed = {};
        _poolByUri = null;
        _tipRequests = {};
        destroyInspectionCamera();
        _surfaceGeneration += 1;
        _callSequence = 0;
        _softlockObservationSequence = 0;
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== "undefined" && PanelScale.attach
            ? PanelScale.attach(_scaleShell, DESIGN_WIDTH, DESIGN_HEIGHT) : null;
        if (_init.shadowOnly !== true || _init.mode !== "dev") {
            failBoot("黑市首版只接受 dev + shadowOnly 测试入口。");
            return;
        }
        ensureSurfaceRenderer();
        try {
            _session = BlackMarketCore.createShadowSession({ decryptLevel: 3 });
            _snapshot = _session.product.open();
            _busy = false;
            render();
            notifyHost("open", sessionTelemetry());
            notifyHost("ready", sessionTelemetry());
            startSoftlockObservation();
            notifyFx("fx-poweron");
        } catch (error) {
            if (!_panelOpen || generation !== _openGeneration) return;
            _busy = false;
            failBoot(error && error.message ? error.message : String(error));
        }
    }

    function onRebind(el, initData) {
        cleanup();
        onOpen(el, initData);
        return true;
    }

    function resolveUrl(path) {
        if (typeof MinigameHostBridge !== "undefined" && MinigameHostBridge.resolveUrl) {
            return MinigameHostBridge.resolveUrl(path);
        }
        return path;
    }

    // 表面渲染可能发生在 worker 内（fetch 以 worker 脚本为 base 解析相对路径），
    // 非 data: 的资产 URL 一律转成页面绝对 URL 再交给渲染器。
    function resolveAssetUrl(url) {
        if (typeof url !== "string" || url.indexOf("data:") === 0) return url;
        var resolved = resolveUrl(url);
        if (typeof location !== "undefined" && typeof URL === "function") {
            try { return new URL(resolved, location.href).href; } catch (error) { return resolved; }
        }
        return resolved;
    }

    function render() {
        if (!_root) return;
        var focusKey = currentFocusKey();
        destroyInspectionCamera();
        if (!_snapshot) {
            _root.className = "blackmarket-boot";
            _root.innerHTML = _error
                ? '<div class="blackmarket-boot-error"><b>接入失败</b><span>' + escapeHtml(_error)
                    + '</span><button type="button" data-bm-action="close" data-focus-key="boot-close">关闭测试</button></div>'
                : '<span class="blackmarket-loader"></span><b>黑市检货台正在接入匿名影子夹具…</b>';
            return;
        }
        _root.className = "blackmarket-machine decrypt-" + _snapshot.decryptLevel;
        var surfaceKey = _snapshot.page.id + "|" + _snapshot.decryptLevel + "|" + _snapshot.revision;
        if (_surfaceSnapshotKey !== surfaceKey) {
            _surfaceSnapshotKey = surfaceKey;
            _surfaceMetrics = {};
            _surfaceMasters = {};
            _inspection = null;
        }
        if (_fxShutterPage !== _snapshot.page.id) {
            _fxShutterPage = _snapshot.page.id;
            _fxShutterPlayed = {};
        }
        var pendingFxKey = _snapshot.pending
            ? _snapshot.pending.pairId + "|" + _snapshot.revision : null;
        _fxActiveRevealKey = pendingFxKey && pendingFxKey !== _fxRevealKey ? pendingFxKey : null;
        _root.innerHTML = [
            renderHeader(),
            '<main class="blackmarket-deck">',
                '<canvas class="blackmarket-bubbles" data-bm-bubbles aria-hidden="true"></canvas>',
                _snapshot.pairs.map(renderPair).join(""),
            '</main>',
            renderBottomRail(),
            _error ? '<div class="blackmarket-error" role="alert"><b>操作被拒绝</b><span>'
                + escapeHtml(_error) + '</span><button type="button" data-bm-action="dismiss-error" data-focus-key="dismiss-error">×</button></div>' : "",
            renderDrawer(),
            renderInspection(),
            _fxBoot ? '<div class="blackmarket-poweron" aria-hidden="true"><i></i><i></i></div>' : ""
        ].join("");
        hideOfferTip();
        if (pendingFxKey) _fxRevealKey = pendingFxKey;
        _fxActiveRevealKey = null;
        _fxBoot = false;
        restoreFocus(focusKey);
        mountInspection();
        scheduleSurfaceHydration();
        ensureBubbles();
    }

    function renderHeader() {
        var stats = _snapshot.catalog;
        return [
            '<header class="blackmarket-header">',
                '<div class="blackmarket-brand">',
                    '<span>TERMINATOR SYNTHESIZER / APPRAISAL UNIT</span>',
                    '<h1>终结者合成台 · 匿名鉴定舱</h1>',
                '</div>',
                '<div class="blackmarket-ledger">',
                    ledgerCell("TP", formatNumber(_snapshot.balances.tradePoints), "vial-green",
                        logFill(_snapshot.balances.tradePoints, 7), !!_selectedOfferId && _payment === "tp"),
                    ledgerCell("K", formatNumber(_snapshot.balances.kPoints), "vial-cyan",
                        logFill(_snapshot.balances.kPoints, 5), !!_selectedOfferId && _payment === "k"),
                    ledgerCell("解密", "Lv." + _snapshot.decryptLevel, "vial-purple",
                        Math.min(1, _snapshot.decryptLevel / 5), false),
                    ledgerCell("夹具", stats.mechanicallyRenderable + " / " + stats.totalItems, "vial-red",
                        stats.totalItems ? stats.mechanicallyRenderable / stats.totalItems : 0, false),
                '</div>',
                '<div class="blackmarket-head-actions">',
                    '<button type="button" data-bm-action="open-debug" data-focus-key="debug">调试</button>',
                    '<button type="button" data-bm-action="open-help" data-focus-key="help">说明</button>',
                    '<button class="danger" type="button" data-bm-action="close" data-focus-key="close" aria-label="关闭黑市测试">×</button>',
                '</div>',
                '<div class="blackmarket-shadow-banner"><b>SHADOW</b><span>仅匿名合成货物；Web 不加载真实目录；零正式库存、货币与主存档写入</span>',
                    '<code>' + escapeHtml(shortDigest(stats.digest)) + '</code></div>',
            '</header>'
        ].join("");
    }

    // 货币类无硬上限，液面用对数刻度（decades=满管数量级）；解密/夹具用真实比例
    function logFill(value, decades) {
        var numeric = Math.max(1, Number(value) || 0);
        return Math.max(0.08, Math.min(1, Math.log(numeric) / Math.LN10 / decades));
    }

    function ledgerCell(label, value, vial, fill, armed) {
        var pct = Math.round(Math.max(0, Math.min(1, Number(fill) || 0)) * 100);
        return '<div class="blackmarket-ledger-cell ' + vial + (armed ? ' is-armed' : '') + '">'
            + '<span class="blackmarket-vial-tube" aria-hidden="true"><i style="height:' + pct + '%"></i></span>'
            + '<div class="blackmarket-ledger-text"><span>' + escapeHtml(label)
            + '</span><strong>' + escapeHtml(value) + '</strong></div></div>';
    }

    function renderPair(pair) {
        var suppressed = _snapshot.pending && _snapshot.pending.pairId !== pair.pairId;
        var pairResult = pair.offers.filter(function(offer) { return offer.revealed; })[0];
        var tone = pairResult && pairResult.revealed ? pairResult.revealed.direction : "";
        return [
            '<section class="blackmarket-bay ', suppressed ? "is-suppressed " : "", tone ? "tone-" + tone : "",
                '" data-pair-id="', escapeAttr(pair.pairId), '">',
                '<i class="blackmarket-rivet r1"></i><i class="blackmarket-rivet r2"></i>',
                '<i class="blackmarket-rivet r3"></i><i class="blackmarket-rivet r4"></i>',
                '<header class="blackmarket-bay-header"><span>0', pair.index, '</span><h2>',
                    escapeHtml(categoryLabel(pair.category)), '</h2><em>', escapeHtml(pair.subclass), '</em></header>',
                '<div class="blackmarket-offers">',
                    renderOffer(pair, pair.offers[0]),
                    '<div class="blackmarket-divider"><i></i></div>',
                    renderOffer(pair, pair.offers[1]),
                '</div>',
                '<footer class="blackmarket-bay-footer">',
                    '<div class="blackmarket-price-tag"><span>同舱标价</span><b>', formatNumber(pair.counterPriceTp), ' TP</b><i>/</i><b class="tech">', pair.kCost, ' K</b></div>',
                    pair.status === "open"
                        ? '<button type="button" data-bm-action="skip" data-pair-id="' + escapeAttr(pair.pairId)
                            + '" data-focus-key="skip-' + escapeAttr(pair.pairId) + '" ' + disabledAttr() + '>整舱放过 <kbd>S</kbd></button>'
                        : '<strong class="blackmarket-terminal">' + escapeHtml(terminalLabel(pair.status)) + '</strong>',
                '</footer>',
            '</section>'
        ].join("");
    }

    function renderOffer(pair, offer) {
        var selected = _selectedOfferId === offer.offerId && pair.status === "open";
        var disabled = _busy || pair.status !== "open" || _snapshot.pending !== null;
        var revealed = offer.revealed;
        var name = revealed ? revealed.displayName : offer.label;
        var direction = offer.direction ? '<span class="blackmarket-direction ' + offer.direction + '">'
            + (offer.direction === "profit" ? "回售盈利" : "回售亏损") + '</span>' : "";
        var terminal = "";
        if (offer.visualState === "withdrawn") {
            var shutterFresh = !_fxShutterPlayed[pair.pairId];
            _fxShutterPlayed[pair.pairId] = true;
            terminal = '<span class="blackmarket-shutter' + (shutterFresh ? ' is-fresh' : '')
                + '"><b></b><b></b><b></b><em>同舱撤回</em></span>';
        }
        if (offer.visualState === "sealed") terminal = '<span class="blackmarket-sealed">整舱封签</span>';
        // 揭晓三段式 FX（爪落→扫描→盈/亏闪光）：纯装饰覆盖层，只在 pending 首次渲染出现一次
        var revealFx = "";
        if (offer.revealed && _fxActiveRevealKey && _snapshot.pending
                && _snapshot.pending.pairId === pair.pairId) {
            revealFx = '<span class="bm-fx-reveal tone-' + escapeAttr(offer.revealed.direction || "loss")
                + '" aria-hidden="true"><i class="bm-fx-claw"></i><i class="bm-fx-scan"></i><i class="bm-fx-flash"></i></span>';
        }
        return [
            '<button type="button" class="blackmarket-offer ', selected ? "is-selected " : "", 'state-', offer.visualState,
                '" data-bm-action="select" data-pair-id="', escapeAttr(pair.pairId), '" data-offer-id="', escapeAttr(offer.offerId),
                '" data-focus-key="offer-', escapeAttr(offer.offerId), '" ', disabled ? "disabled" : "",
                ' aria-pressed="', selected ? "true" : "false", '" aria-label="', escapeAttr(buildOfferAria(offer)), '">',
                '<span class="blackmarket-side">', offer.side === "A" ? "左 / A" : "右 / B", '</span>',
                '<span class="blackmarket-asset ', escapeAttr(offer.presentationKind), '">',
                    '<canvas class="blackmarket-item-surface" data-bm-surface="', escapeAttr(offer.offerId),
                        '" data-surface-state="loading" width="1" height="1" aria-hidden="true"></canvas>',
                    '<span class="blackmarket-surface-guard" aria-hidden="true"><b>表面封存</b></span>',
                    '<span class="blackmarket-surface-readout" data-bm-surface-readout="', escapeAttr(offer.offerId), '"></span>',
                    terminal,
                    revealFx,
                '</span>',
                direction,
                '<strong class="blackmarket-offer-name">', escapeHtml(name), '</strong>',
                '<small>', revealed
                    ? (revealed.realInfo
                        ? '目录价 ' + formatNumber(revealed.realInfo.catalogPrice)
                            + ' TP · 回售 ' + formatNumber(revealed.realInfo.saleValue) + ' TP'
                        : '基础价 ' + formatNumber(revealed.basePrice) + ' · 回售 ' + formatNumber(revealed.resellValue))
                    : (offer.hint ? escapeHtml(offer.hint) : "身份封存 · 安全表面"), '</small>',
            '</button>'
        ].join("");
    }

    function ensureSurfaceRenderer() {
        if (_surfaceRenderer || typeof BlackMarketItemSurface === "undefined") return _surfaceRenderer;
        _surfaceRenderer = BlackMarketItemSurface.createRenderer({
            workerUrl: resolveUrl("modules/minigames/blackmarket/visual/item-surface-worker.js"),
            cacheLimit: 42
        });
        return _surfaceRenderer;
    }

    function scheduleSurfaceHydration() {
        if (!_panelOpen || !_snapshot || !_root) return;
        var generation = ++_surfaceGeneration;
        var run = function() {
            if (!_panelOpen || generation !== _surfaceGeneration) return;
            hydrateSurfaces(generation);
        };
        if (typeof requestAnimationFrame === "function") requestAnimationFrame(run);
        else setTimeout(run, 0);
    }

    function hydrateSurfaces(generation) {
        var renderer = ensureSurfaceRenderer();
        if (!renderer || !_root || !_snapshot || !_session || !_session.surface) return;
        var canvases = _root.querySelectorAll("[data-bm-surface]");
        for (var i = 0; i < canvases.length; i += 1) {
            (function(canvas) {
                var offerId = canvas.getAttribute("data-bm-surface");
                var located = findSnapshotOffer(offerId);
                if (!located) return;
                var offer = located.offer;
                var surface = offer.surface || {};
                var source;
                try {
                    source = _session.surface.resolveSurface(offer.visualHandle);
                } catch (error) {
                    failSurfaceClosed(canvas, error, generation);
                    return;
                }
                Promise.resolve(source).then(function(visual) {
                    if (!_panelOpen || generation !== _surfaceGeneration || !_root
                            || !_root.contains(canvas)) return null;
                    var surfaceSeed = visual.seed;
                    return renderer.render(canvas, {
                        offerId: offer.offerId,
                        assetUrl: resolveAssetUrl(visual.assetUrl),
                        sourceKey: visual.sourceKey,
                        sourceKind: visual.sourceKind,
                        sourceComposition: visual.sourceComposition || null,
                        focusFitFieldCount: 0,
                        focusDrawFieldCount: 0,
                        previewGender: visual.previewGender,
                        seed: surfaceSeed,
                        coverage: Number(surface.targetCoverage === undefined ? _snapshot.mudCoverage : surface.targetCoverage),
                        mud: offer.visualState === "available",
                        hiddenColorMode: offer.visualState === "available"
                            ? (visual.hiddenColorMode || "source") : "source",
                        autoRotate: visual.autoRotate,
                        paddingRatio: 0.065,
                        renderWidth: SURFACE_MASTER_WIDTH,
                        renderHeight: SURFACE_MASTER_HEIGHT,
                        // 揭晓后的干净展示：保留源半透边缘（不修边锯齿），且不再叠加低清锐化
                        preserveSourceAlpha: offer.visualState === "revealed",
                        sharpenSource: offer.visualState === "revealed" ? false : visual.sharpenSource === true,
                        sharpenStrength: 0.18,
                        debug: false,
                        onComplete: function(metrics, completedCanvas) {
                            if (!_panelOpen || generation !== _surfaceGeneration || !_root
                                    || !_root.contains(completedCanvas)) return;
                            metrics.surfaceSeed = surfaceSeed;
                            _surfaceMetrics[offer.offerId] = metrics;
                            rememberSurfaceMaster(offer.offerId, completedCanvas, metrics);
                            var completedAsset = completedCanvas.closest(".blackmarket-asset");
                            if (completedAsset) completedAsset.classList.add("is-surface-ready");
                            paintSurfaceReadout(offer.offerId, metrics);
                            paintParityMetric();
                            paintInspectionAvailability();
                        }
                    });
                }).catch(function(error) {
                    failSurfaceClosed(canvas, error, generation);
                });
            })(canvases[i]);
        }
    }

    function failSurfaceClosed(canvas, error, generation) {
        if (!_panelOpen || generation !== _surfaceGeneration || !_root || !_root.contains(canvas)) return;
        var asset = canvas.closest(".blackmarket-asset");
        if (asset) asset.classList.add("is-surface-fallback");
        canvas.setAttribute("data-surface-state", "error");
        canvas.setAttribute("title", "安全表面生成失败");
    }

    function findSnapshotOffer(offerId) {
        if (!_snapshot || !offerId) return null;
        for (var i = 0; i < _snapshot.pairs.length; i += 1) {
            var pair = _snapshot.pairs[i];
            for (var j = 0; j < pair.offers.length; j += 1) {
                if (pair.offers[j].offerId === offerId) return { pair: pair, offer: pair.offers[j] };
            }
        }
        return null;
    }

    function rememberSurfaceMaster(offerId, canvas, metrics) {
        if (!offerId || !canvas || !canvas.width || !canvas.height || typeof document === "undefined") return;
        var copy = document.createElement("canvas");
        copy.width = canvas.width;
        copy.height = canvas.height;
        var context = copy.getContext("2d");
        context.clearRect(0, 0, copy.width, copy.height);
        context.drawImage(canvas, 0, 0);
        _surfaceMasters[offerId] = {
            canvas: copy,
            metrics: JSON.parse(JSON.stringify(metrics || {})),
            snapshotKey: _surfaceSnapshotKey
        };
    }

    function surfaceMaster(offerId) {
        var master = _surfaceMasters[offerId];
        return master && master.snapshotKey === _surfaceSnapshotKey ? master : null;
    }

    function paintInspectionAvailability() {
        if (!_root || !_selectedOfferId) return;
        var button = _root.querySelector('[data-bm-action="inspect-selected"]');
        if (!button) return;
        var ready = !!surfaceMaster(_selectedOfferId);
        button.disabled = _busy || !ready;
        button.innerHTML = ready ? "放大检视 <kbd>V</kbd>" : "检视生成中";
    }

    function paintSurfaceReadout(offerId, metrics) {
        if (!_root) return;
        var nodes = _root.querySelectorAll("[data-bm-surface-readout]");
        for (var i = 0; i < nodes.length; i += 1) {
            if (nodes[i].getAttribute("data-bm-surface-readout") !== offerId) continue;
            nodes[i].textContent = "";
            nodes[i].setAttribute("title", "SDF " + metrics.sdfMaxInsidePx + "px · "
                + metrics.maskSource + " · " + metrics.materialProfile + " · " + metrics.backend
                + " · 匿名安全表面");
        }
    }

    function parityMetricText() {
        if (!_snapshot) return "实测覆盖待计算";
        var maximum = 0;
        var readyPairs = 0;
        for (var i = 0; i < _snapshot.pairs.length; i += 1) {
            var offers = _snapshot.pairs[i].offers;
            var left = _surfaceMetrics[offers[0].offerId];
            var right = _surfaceMetrics[offers[1].offerId];
            if (!left || !right) continue;
            maximum = Math.max(maximum, Math.abs(left.actualCoverage - right.actualCoverage));
            readyPairs += 1;
        }
        return readyPairs ? "实测左右差 ≤ " + formatPercent(maximum) + " · " + readyPairs + "/3 舱" : "实测覆盖待计算";
    }

    function paintParityMetric() {
        if (!_root) return;
        var node = _root.querySelector("[data-bm-parity]");
        if (node) node.textContent = parityMetricText();
    }

    function signedDegrees(value) {
        var numeric = Number(value) || 0;
        return (numeric > 0 ? "+" : "") + numeric + "°";
    }

    function formatPercent(value) {
        return (Number(value || 0) * 100).toFixed(1) + "%";
    }

    function formatConfidence(value) {
        return Number(value || 0).toFixed(2);
    }

    function renderBottomRail() {
        var pending = _snapshot.pending;
        if (pending) {
            var pair = findPair(pending.pairId);
            var offer = pair && findOffer(pair, pending.offerId);
            var revealed = offer && offer.revealed;
            if (revealed) {
                var breakdown = revealed.payment === "k"
                    ? "+" + formatNumber(revealed.resellValue) + " TP / -"
                        + formatNumber(revealed.paidAmount) + " K"
                    : "+" + formatNumber(revealed.resellValue) + " TP / -"
                        + formatNumber(revealed.paidAmount) + " TP";
                return '<footer class="blackmarket-rail reveal ' + revealed.direction + '"><div><span>货物揭晓</span><h2>'
                    + escapeHtml(revealed.displayName) + '</h2><p>回售净价值 <b>'
                    + (revealed.deltaV > 0 ? "+" : "") + formatNumber(revealed.deltaV)
                    + ' TP 等值</b><small>结算构成 ' + escapeHtml(breakdown) + '</small></p></div>'
                    + '<div class="blackmarket-rail-actions"><button type="button" data-bm-action="settle" data-settle="extract" data-focus-key="settle-extract" '
                    + disabledAttr() + '>提取到影子收藏</button><button class="primary" type="button" data-bm-action="settle" data-settle="resell" '
                    + 'data-focus-key="settle-resell" ' + disabledAttr() + '>当场回售 +' + formatNumber(revealed.resellValue) + ' TP</button></div></footer>';
            }
        }
        if (_snapshot.page.complete) {
            return '<footer class="blackmarket-rail complete"><div><span>本页封单</span><h2>三组货舱均已进入终态</h2><p>继续生成会消耗 1 个影子补货信用，不触及正式存档。</p></div>'
                + '<div class="blackmarket-rail-actions"><button class="primary" type="button" data-bm-action="next-page" data-focus-key="next-page" '
                + (_snapshot.balances.supplyCredits <= 0 || _busy ? "disabled" : "") + '>整理下一批</button></div></footer>';
        }
        var pair = findPair(_selectedPairId);
        var offer = pair && findOffer(pair, _selectedOfferId);
        if (pair && offer && pair.status === "open") {
            return '<footer class="blackmarket-rail purchase"><div><span>影子购买预览</span><h2>' + pair.index + ' 号舱 · '
                + (offer.side === "A" ? "左侧" : "右侧") + '</h2><p>成交后另一侧撤回；必须先提取或回售。</p></div>'
                + '<div class="blackmarket-payment" role="group" aria-label="影子支付方式">'
                + paymentButton("tp", pair.counterPriceTp + " TP") + paymentButton("k", pair.kCost + " K") + '</div>'
                + '<div class="blackmarket-rail-actions"><button type="button" data-bm-action="inspect-selected" data-pair-id="'
                + escapeAttr(pair.pairId) + '" data-offer-id="' + escapeAttr(offer.offerId)
                + '" data-focus-key="inspect" ' + (_busy || !surfaceMaster(offer.offerId) ? "disabled" : "")
                + '>' + (surfaceMaster(offer.offerId) ? '放大检视 <kbd>V</kbd>' : '检视生成中') + '</button>'
                + '<button type="button" data-bm-action="cancel" data-focus-key="cancel">取消</button>'
                + '<button class="primary" type="button" data-bm-action="confirm" data-focus-key="confirm" '
                + (!_preview || _busy ? "disabled" : "") + '>确认影子成交</button></div></footer>';
        }
        return '<footer class="blackmarket-rail idle"><div><span>算法实验待命</span><h2>从任一货舱选择左侧或右侧</h2><p>自动正交旋转、Alpha/SDF、自动锚点与休眠纳米蜂群污泥；防具局部纸娃娃及其他代理素材仍需生产视觉复核。</p></div>'
            + '<div class="blackmarket-metrics"><b>物品 Alpha 覆盖目标 ' + Math.round(_snapshot.mudCoverage * 100)
            + '%</b><span data-bm-parity>' + escapeHtml(parityMetricText()) + '</span></div></footer>';
    }

    function paymentButton(kind, label) {
        return '<button type="button" class="' + (_payment === kind ? "active" : "") + '" data-bm-action="payment" data-payment="'
            + kind + '" data-focus-key="payment-' + kind + '"><span>' + (kind === "tp" ? "交易点" : "K 点")
            + '</span><b>' + escapeHtml(label) + '</b></button>';
    }

    function renderDrawer() {
        if (!_drawer) return "";
        if (_drawer === "debug") return renderDebugDrawer();
        var body = '<h2>匿名影子入口边界</h2><ol>'
            + '<li>普通面板只生成与真实目录无关的六件匿名合成货物，不加载物品名、ID、资源地址或回售价目录。</li>'
            + '<li>影子购买、回售和余额只存在于当前 Web 会话；所有揭晓名称与数值均为合成夹具。</li>'
            + '<li>六件货物只消费同一身份无关安全表面；放大检视复制覆泥母版，不请求真实物品资源。</li>'
            + '<li>全目录机械盘点与纸娃娃/武器素材验证属于独立开发测试模块，不能从本面板提权进入。</li></ol>'
            + '<p>键盘：Tab 遍历；左右键切换同舱；Enter 选择；V 放大检视；S 放过当前舱；Esc 关闭浮层。</p>';
        return '<div class="blackmarket-overlay"><aside class="blackmarket-drawer" role="dialog" aria-modal="true" aria-label="黑市实验说明">'
            + '<header><span>BLACK MARKET SHADOW</span><button type="button" data-bm-action="close-drawer" data-focus-key="close-drawer" aria-label="关闭">×</button></header>'
            + body + '</aside></div>';
    }

    // 调试抽屉：只调整匿名影子会话的四个白名单数值参数（core validateOptions 只允许
    // tradePoints/kPoints/supplyCredits/decryptLevel/seed），不碰目录、身份或视觉池；
    // 面板本身就锁定在 dev + shadowOnly，此抽屉是给测试员覆盖覆盖率/经济分支的工具。
    function renderDebugDrawer() {
        var b = _snapshot.balances;
        var levels = [0, 3, 5, 10].map(function(level) {
            return '<option value="' + level + '"'
                + (_snapshot.decryptLevel === level ? ' selected' : '') + '>Lv.' + level
                + '（覆盖 ' + Math.round((({ 0: 0.97, 3: 0.84, 5: 0.54, 10: 0.18 })[level]) * 100) + '%）</option>';
        }).join("");
        return '<div class="blackmarket-overlay"><aside class="blackmarket-drawer" role="dialog" aria-modal="true" aria-label="黑市调试抽屉">'
            + '<header><span>SHADOW DEBUG</span><button type="button" data-bm-action="close-drawer" data-focus-key="close-drawer" aria-label="关闭">×</button></header>'
            + '<h2>会话参数（影子重开）</h2>'
            + '<div class="blackmarket-debug-grid">'
            + '<label>解密等级<select data-bm-field="decryptLevel">' + levels + '</select></label>'
            + '<label>TP 余额<input type="number" min="0" step="1000" data-bm-field="tradePoints" value="' + b.tradePoints + '"></label>'
            + '<label>K 余额<input type="number" min="0" step="100" data-bm-field="kPoints" value="' + b.kPoints + '"></label>'
            + '<label>补货信用<input type="number" min="0" step="1" data-bm-field="supplyCredits" value="' + b.supplyCredits + '"></label>'
            + '</div>'
            + '<p class="blackmarket-debug-note">应用 = 以新参数重开匿名影子会话（当前页进度丢弃）。'
            + '只影响本测试会话，不写正式存档；目录/身份/视觉池不在可调范围。</p>'
            + '<div class="blackmarket-drawer-actions">'
            + '<button type="button" data-bm-action="debug-apply" data-focus-key="debug-apply">应用并重开</button>'
            + '<button type="button" data-bm-action="debug-reset" data-focus-key="debug-reset">恢复默认</button>'
            + '</div></aside></div>';
    }

    function readDebugOptions(defaults) {
        var options = defaults || {};
        var fields = _root.querySelectorAll("[data-bm-field]");
        for (var index = 0; index < fields.length; index += 1) {
            var field = fields[index];
            var key = field.getAttribute("data-bm-field");
            var value = Number(field.value);
            if (!isFinite(value) || value < 0) throw new Error("调试参数非法：" + key);
            if (key === "decryptLevel" && [0, 3, 5, 10].indexOf(value) < 0) {
                throw new Error("解密等级非法");
            }
            options[key] = Math.floor(value);
        }
        return options;
    }

    function restartSession(options) {
        _session = BlackMarketCore.createShadowSession(options);
        _snapshot = _session.product.open();
        _selectedPairId = null;
        _selectedOfferId = null;
        _payment = "tp";
        _preview = null;
        _busy = false;
        _error = null;
        _fxRevealKey = null;
        _fxShutterPlayed = {};
        notifyHost("debug-restart", sessionTelemetry());
        render();
    }

    function applyDebugOptions(options) {
        try {
            restartSession(readDebugOptions(options || {}));
        } catch (error) {
            _error = error && error.message ? error.message : String(error);
            render();
        }
    }

    function renderInspection() {
        if (!_inspection) return "";
        var pair = findPair(_inspection.pairId);
        var offer = pair && findOffer(pair, _inspection.offerId);
        var master = offer && surfaceMaster(offer.offerId);
        if (!pair || !offer || !master) return "";
        var sideButtons = pair.offers.map(function(candidate) {
            var ready = !!surfaceMaster(candidate.offerId) && candidate.visualState === "available";
            return '<button type="button" data-bm-action="inspection-side" data-pair-id="'
                + escapeAttr(pair.pairId) + '" data-offer-id="' + escapeAttr(candidate.offerId)
                + '" data-focus-key="inspection-side-' + escapeAttr(candidate.offerId) + '" '
                + (ready ? "" : "disabled") + ' aria-pressed="'
                + (candidate.offerId === offer.offerId ? "true" : "false") + '">'
                + (candidate.side === "A" ? "左侧 / A" : "右侧 / B") + '</button>';
        }).join("");
        var sourceLabel = inspectionSourceLabel(master.metrics);
        var title = "0" + pair.index + "号舱 · " + (offer.side === "A" ? "左侧" : "右侧")
            + " · " + pair.subclass;
        return '<div class="blackmarket-inspection-overlay"><section class="blackmarket-inspection-dialog" '
            + 'role="dialog" aria-modal="true" aria-labelledby="blackmarket-inspection-title">'
            + '<header><div><span>SEALED EVIDENCE / MAGNIFIED</span><h2 id="blackmarket-inspection-title">'
            + escapeHtml(title) + '</h2></div><button type="button" data-bm-action="close-inspection" '
            + 'data-focus-key="close-inspection" aria-label="关闭放大检视">×</button></header>'
            + '<div class="blackmarket-inspection-switch" role="group" aria-label="切换同舱检视侧">'
            + sideButtons + '</div>'
            + '<div class="blackmarket-inspection-viewport" data-bm-inspection-viewport tabindex="0" '
            + 'aria-label="' + escapeAttr(title + "覆泥证据，可拖拽与滚轮缩放") + '">'
            + '<div class="blackmarket-inspection-stage" data-bm-inspection-stage>'
            + '<canvas data-bm-inspection-canvas width="1" height="1" aria-hidden="true"></canvas></div>'
            + '<span class="bm-scan-hud" aria-hidden="true"><i class="bm-hud-v"></i><i class="bm-hud-h"></i>'
            + '<i class="bm-hud-corners"></i><i class="bm-hud-sweep"></i></span></div>'
            + '<footer><div class="blackmarket-inspection-evidence"><b>' + escapeHtml(sourceLabel)
            + '</b><span>只放大同一份覆泥证据；不会降低覆盖或重新生成破局点。</span></div>'
            + '<div class="blackmarket-inspection-toolbar"><div data-bm-inspection-controls></div>'
            + '<button type="button" data-bm-action="inspection-rotate" data-focus-key="inspection-rotate">旋转 90°</button>'
            + '<output data-bm-inspection-rotation aria-live="polite">当前旋转 '
            + escapeHtml(String(_inspection.rotation || 0)) + '°</output></div></footer>'
            + '</section></div>';
    }

    function inspectionSourceLabel(metrics) {
        metrics = metrics || {};
        if (metrics.sourceKind === "dressup-weapon") return "完整武器覆泥母版";
        if (metrics.sourceKind === "dressup-paperdoll") return "局部防具覆泥母版";
        if (metrics.sourceSharpening === "alpha-safe-unsharp") return "保边锐化图标代理";
        return "图标覆泥母版";
    }

    function mountInspection() {
        if (!_inspection || !_root) return;
        var master = surfaceMaster(_inspection.offerId);
        var viewport = _root.querySelector("[data-bm-inspection-viewport]");
        var stage = _root.querySelector("[data-bm-inspection-stage]");
        var canvas = _root.querySelector("[data-bm-inspection-canvas]");
        var controlsHost = _root.querySelector("[data-bm-inspection-controls]");
        if (!master || !viewport || !stage || !canvas || !controlsHost) return;
        paintInspectionCanvas(canvas, master.canvas, _inspection.rotation || 0);
        if (typeof WorkbenchInspectionViewport === "undefined" || !WorkbenchInspectionViewport.create
                || typeof BlackMarketInspectionFocus === "undefined" || !BlackMarketInspectionFocus.plan) return;
        var focus = BlackMarketInspectionFocus.plan({
            sourceWidth:master.canvas.width,
            sourceHeight:master.canvas.height,
            objectBounds:master.metrics && master.metrics.objectBounds,
            envelopeRadiusPx:master.metrics && master.metrics.envelopeRadiusPx,
            rotation:_inspection.rotation || 0,
            viewportWidth:viewport.clientWidth,
            viewportHeight:viewport.clientHeight,
            canvasRatio:0.92,
            fillRatio:0.72,
            maxZoom:INSPECTION_MAX_ZOOM
        });
        _inspection.focus = focus;
        _inspectionCamera = WorkbenchInspectionViewport.create({
            document: document,
            viewport: viewport,
            target: stage,
            controlsHost: controlsHost,
            controlsClass: "blackmarket-inspection-camera-controls",
            panControlsClass: "blackmarket-inspection-pan-controls",
            zoomControlsClass: "blackmarket-inspection-zoom-controls",
            controlClass: "blackmarket-inspection-camera-control",
            statusClass: "blackmarket-inspection-camera-status",
            controlsAriaLabel: "黑市覆泥证据视角控制",
            ariaLabel: viewport.getAttribute("aria-label"),
            minZoom: 1,
            maxZoom: INSPECTION_MAX_ZOOM,
            fitZoom: focus.fitZoom,
            defaultZoom: focus.zoom,
            zoomStep: 0.2,
            panStep: 38,
            fitLabel: "全貌",
            resetLabel: "聚焦",
            resetOffset: function(zoom) {
                if (Math.abs(zoom - focus.fitZoom) < 0.001) return { panX:0, panY:0 };
                return { panX:focus.offsetX * zoom, panY:focus.offsetY * zoom };
            },
            panBounds: function(state) {
                return {
                    x:Math.abs(focus.offsetX) * state.zoom + viewport.clientWidth * 0.5,
                    y:Math.abs(focus.offsetY) * state.zoom + viewport.clientHeight * 0.5
                };
            },
            active: true
        });
        viewport.setAttribute("data-bm-auto-focus", focus.version);
        setTimeout(function() {
            if (_inspection && viewport && _root && _root.contains(viewport)) viewport.focus();
        }, 0);
    }

    function paintInspectionCanvas(target, source, rotation) {
        if (!target || !source) return;
        rotation = ((Number(rotation) || 0) % 360 + 360) % 360;
        var swap = rotation === 90 || rotation === 270;
        target.width = swap ? source.height : source.width;
        target.height = swap ? source.width : source.height;
        var context = target.getContext("2d");
        context.clearRect(0, 0, target.width, target.height);
        context.save();
        if (rotation === 90) {
            context.translate(target.width, 0);
            context.rotate(Math.PI / 2);
        } else if (rotation === 180) {
            context.translate(target.width, target.height);
            context.rotate(Math.PI);
        } else if (rotation === 270) {
            context.translate(0, target.height);
            context.rotate(-Math.PI / 2);
        }
        context.drawImage(source, 0, 0);
        context.restore();
        target.setAttribute("data-inspection-rotation", String(rotation));
    }

    function mergeTelemetry(base, extra) {
        var merged = {};
        var source = base || {};
        var patch = extra || {};
        for (var key in source) {
            if (Object.prototype.hasOwnProperty.call(source, key)) merged[key] = source[key];
        }
        for (var extraKey in patch) {
            if (Object.prototype.hasOwnProperty.call(patch, extraKey)) merged[extraKey] = patch[extraKey];
        }
        return merged;
    }

    function openInspection(pairId, offerId, opener) {
        var pair = findPair(pairId);
        var offer = pair && findOffer(pair, offerId);
        if (!pair || !offer || pair.status !== "open" || offer.visualState !== "available"
                || !surfaceMaster(offerId)) return false;
        _drawer = null;
        _drawerOpenerKey = null;
        _inspection = {
            pairId: pairId,
            offerId: offerId,
            rotation: 0,
            openerKey: opener && opener.getAttribute ? opener.getAttribute("data-focus-key") : null
        };
        notifyFx("fx-scan-open");
        notifyHost("inspection-open", mergeTelemetry(sessionTelemetry(), {
            pairIndex: pair.index,
            side: offer.side,
            sourceKind: surfaceMaster(offerId).metrics.sourceKind || "icon"
        }));
        render();
        return true;
    }

    function closeInspection() {
        if (!_inspection) return;
        var openerKey = _inspection.openerKey;
        notifyHost("inspection-close", sessionTelemetry());
        _inspection = null;
        destroyInspectionCamera();
        render();
        restoreFocus(openerKey);
    }

    function switchInspection(pairId, offerId) {
        if (!_inspection || _inspection.pairId !== pairId || !surfaceMaster(offerId)) return;
        _inspection.offerId = offerId;
        _inspection.rotation = 0;
        render();
    }

    function rotateInspection() {
        if (!_inspection || !_root) return;
        var master = surfaceMaster(_inspection.offerId);
        var canvas = _root.querySelector("[data-bm-inspection-canvas]");
        if (!master || !canvas) return;
        _inspection.rotation = ((_inspection.rotation || 0) + 90) % 360;
        notifyFx("fx-scan-rotate");
        destroyInspectionCamera();
        mountInspection();
        // 机械卡位顿挫：重启动画类（移除→强制 reflow→加回）
        var viewport = _root.querySelector("[data-bm-inspection-viewport]");
        if (viewport) {
            viewport.classList.remove("is-detent");
            void viewport.offsetWidth;
            viewport.classList.add("is-detent");
        }
        var output = _root.querySelector("[data-bm-inspection-rotation]");
        if (output) output.textContent = "当前旋转 " + _inspection.rotation + "°";
    }

    function destroyInspectionCamera() {
        if (_inspectionCamera && _inspectionCamera.destroy) _inspectionCamera.destroy();
        _inspectionCamera = null;
    }

    // ── P3 舱液气泡环境层 ────────────────────────────────────────
    // 极轻 canvas 循环：只画圆形 alpha 点；复用全局 perf-frame-limiter 接管后的 rAF；
    // reduced-motion / 隐藏标签页 / 面板关闭时完全停止；innerHTML 重建后自动重挂。
    var _bubbles = null;

    function ensureBubbles() {
        if (_bubbles && _bubbles.canvas && _bubbles.canvas.isConnected) return;
        startBubbles();
    }

    function startBubbles() {
        stopBubbles();
        if (typeof document === "undefined") return;
        if (typeof matchMedia === "function"
                && matchMedia("(prefers-reduced-motion: reduce)").matches) return;
        var canvas = _root && _root.querySelector("[data-bm-bubbles]");
        if (!canvas || !canvas.getContext) return;
        var deck = canvas.parentElement;
        var width = deck.clientWidth || 0;
        var height = deck.clientHeight || 0;
        if (!width || !height) return;
        var dpr = Math.min(1.5, (typeof devicePixelRatio === "number" && devicePixelRatio) || 1);
        canvas.width = Math.max(1, Math.round(width * dpr));
        canvas.height = Math.max(1, Math.round(height * dpr));
        var context = canvas.getContext("2d");
        if (!context) return;
        context.scale(dpr, dpr);
        // 本地确定性 LCG：环境粒子不需要密码学熵，也不消费会话私有熵流
        var rngState = 0x9e3779b9;
        var rand = function() {
            rngState = (Math.imul(rngState, 1664525) + 1013904223) >>> 0;
            return rngState / 4294967296;
        };
        var bubbles = [];
        var count = Math.max(14, Math.min(30, Math.round(width / 34)));
        for (var index = 0; index < count; index += 1) {
            bubbles.push({
                x: rand() * width,
                y: rand() * height,
                r: 1.2 + rand() * 3.4,
                speed: 9 + rand() * 20,
                phase: rand() * 6.2832,
                wobble: 0.4 + rand() * 1.2
            });
        }
        var running = true;
        var last = 0;
        var frame = function(now) {
            if (!running) return;
            if (document.hidden) { last = now; schedule(); return; }
            var dt = Math.min(0.1, last ? (now - last) / 1000 : 0.016);
            last = now;
            context.clearRect(0, 0, width, height);
            for (var b = 0; b < bubbles.length; b += 1) {
                var bubble = bubbles[b];
                bubble.y -= bubble.speed * dt;
                bubble.phase += bubble.wobble * dt;
                if (bubble.y < -8) { bubble.y = height + 8; bubble.x = rand() * width; }
                var x = bubble.x + Math.sin(bubble.phase) * 3;
                context.beginPath();
                context.arc(x, bubble.y, bubble.r, 0, 6.2832);
                context.fillStyle = "rgba(178, 240, 232, 0.10)";
                context.fill();
                context.beginPath();
                context.arc(x - bubble.r * 0.35, bubble.y - bubble.r * 0.35, bubble.r * 0.32, 0, 6.2832);
                context.fillStyle = "rgba(255, 255, 255, 0.22)";
                context.fill();
            }
            schedule();
        };
        var schedule = function() {
            if (running && typeof requestAnimationFrame === "function") requestAnimationFrame(frame);
        };
        _bubbles = { canvas: canvas, stop: function() { running = false; } };
        schedule();
    }

    function stopBubbles() {
        if (_bubbles) { _bubbles.stop(); _bubbles = null; }
    }

    // ── hover 属性预览（注释释放）────────────────────────────────
    // 允许物品（e!=="banned"）揭晓后悬停给出完整真实属性；未揭晓时只给同组分类注释，
    // 不泄名称/价格（盲盒猜测层保留）。tooltip 纯展示、pointer-events:none。

    var _poolByUri = null;

    function poolEntryByUri() {
        if (_poolByUri) return _poolByUri;
        _poolByUri = {};
        var manifest = typeof globalThis !== "undefined" ? globalThis.BlackMarketVisualPool : null;
        var entries = manifest && Array.isArray(manifest.entries) ? manifest.entries : [];
        for (var index = 0; index < entries.length; index += 1) {
            if (entries[index] && entries[index].u) _poolByUri[entries[index].u] = entries[index];
        }
        return _poolByUri;
    }

    function tipEntryForOffer(offer) {
        if (!_session || !_session.surface || !offer) return null;
        try {
            var visual = _session.surface.resolveSurface(offer.visualHandle);
            return poolEntryByUri()[visual.assetUrl] || null;
        } catch (error) {
            return null;
        }
    }

    // 注释层统一走全局 PanelTooltip + buildItemRichHtml（与商店/装备等面板同一套）；
    // 注释全文运行时经 Host → AS2 blackmarketTooltip 问游戏权威数据源（零派生副本，
    // 平衡性调整改 data/items XML 即生效）；Host/AS2 缺席（harness）时降级为基础卡。
    var TIP_OWNER = "blackmarket-offer-tip";
    var _tipOfferId = null;
    var _tipReqSeq = 0;
    var _tipRequests = {};
    var _tipBridgeBound = false;

    function buildAnonTipHtml(entry) {
        return '<div class="bm-ann bm-ann-anon"><b>未鉴定货物</b><br>'
            + (entry ? '<span class="bm-ann-tax">特征分类 · ' + escapeHtml((entry.t || "物品")
                + (entry.sc ? " / " + entry.sc : "")) + '</span><br>' : "")
            + '<span class="bm-ann-note">覆泥下可见特征点；成交后释放完整注释</span></div>';
    }

    function buildRevealTipHtml(entry, info, rich) {
        var metaHTML = '<div class="bm-ann-name">' + escapeHtml(info.name) + '</div>'
            + '<div class="bm-ann-tax">' + escapeHtml((info.type || "物品")
                + (info.subclass ? " · " + info.subclass : "")) + '</div>'
            + '<div class="bm-ann-price">目录价 ' + formatNumber(info.catalogPrice)
            + ' TP · 回售 ' + formatNumber(info.saleValue) + ' TP</div>';
        var introWebHTML = "";
        var descHTML = "";
        if (rich) {
            // AS2 权威注释：introHTML/descHTML 直接走 buildItemRichHtml 的 AS2 转换链
            introWebHTML = typeof rich.introWebHTML === "string" ? rich.introWebHTML : "";
            descHTML = typeof rich.descHTML === "string" ? rich.descHTML : "";
        }
        var richOpts = {
            iconUrl: resolveAssetUrl(entry.u),
            metaHTML: metaHTML,
            introWebHTML: introWebHTML,
            descHTML: descHTML
        };
        if (rich && typeof rich.introHTML === "string") richOpts.introHTML = rich.introHTML;
        return PanelTooltip.buildItemRichHtml(richOpts);
    }

    // 面板→Host→AS2 注释请求；harness/无 webview 环境 Bridge.send 返回 false，静默降级
    function requestAs2Annotation(entry, offer) {
        if (typeof Bridge === "undefined" || !Bridge.send) return;
        if (typeof Bridge.on === "function") bindTipBridge();
        var panelInstanceId = _init && _init.panelInstanceId;
        var callId = "bm-tip-" + (++_tipReqSeq);
        _tipRequests[callId] = { offerId: offer.offerId, entry: entry, info: offer.revealed.realInfo };
        var sent = Bridge.send({
            type: "panel",
            panel: "blackmarket",
            cmd: "tooltip",
            callId: callId,
            panelInstanceId: panelInstanceId || "",
            itemName: entry.k || entry.n
        });
        if (sent !== true) delete _tipRequests[callId];
    }

    function bindTipBridge() {
        if (_tipBridgeBound || typeof Bridge === "undefined" || !Bridge.on) return;
        _tipBridgeBound = true;
        Bridge.on("panel_resp", function(data) {
            if (!data || data.panel !== "blackmarket" || data.cmd !== "tooltip") return;
            var pending = _tipRequests[data.callId];
            if (!pending) return;
            delete _tipRequests[data.callId];
            if (!_panelOpen || _tipOfferId !== pending.offerId) return;
            if (!data.success || typeof PanelTooltip === "undefined"
                    || !PanelTooltip.isVisible(TIP_OWNER)) return;
            PanelTooltip.updateContent(buildRevealTipHtml(pending.entry, pending.info, {
                introHTML: typeof data.introHTML === "string" ? data.introHTML : "",
                descHTML: typeof data.descHTML === "string" ? data.descHTML : ""
            }), TIP_OWNER);
        });
    }

    function showOfferTip(offerEl) {
        if (typeof PanelTooltip === "undefined" || !_snapshot || !_session) return;
        var located = findSnapshotOffer(offerEl.getAttribute("data-offer-id"));
        if (!located) return;
        var offer = located.offer;
        var entry = tipEntryForOffer(offer);
        var revealed = offer.revealed;
        _tipOfferId = offer.offerId;
        var anchorOpts = { owner: TIP_OWNER, autoClose: 0, outsideClick: false, placement: "right" };
        if (revealed && revealed.realInfo && entry) {
            PanelTooltip.showAnchored(buildRevealTipHtml(entry, revealed.realInfo, null), offerEl, anchorOpts);
            requestAs2Annotation(entry, offer);
        } else if (revealed) {
            PanelTooltip.showAnchored('<div class="bm-ann bm-ann-anon"><b>未收录黑货</b><br>'
                + '<span class="bm-ann-note">该货物不在允许清单，注释不予释放</span></div>',
                offerEl, anchorOpts);
        } else {
            PanelTooltip.showAnchored(buildAnonTipHtml(entry), offerEl, anchorOpts);
        }
    }

    function hideOfferTip() {
        _tipOfferId = null;
        if (typeof PanelTooltip !== "undefined" && PanelTooltip.hide) PanelTooltip.hide(TIP_OWNER);
    }

    function handleTipOver(event) {
        var offerEl = event.target.closest ? event.target.closest(".blackmarket-offer") : null;
        if (!offerEl || !_el.contains(offerEl)) return;
        showOfferTip(offerEl);
    }

    function handleTipOut(event) {
        var offerEl = event.target.closest ? event.target.closest(".blackmarket-offer") : null;
        if (!offerEl) return;
        var related = event.relatedTarget;
        if (related && offerEl.contains(related)) return;
        if (typeof PanelTooltip !== "undefined" && PanelTooltip.hideHover) PanelTooltip.hideHover(TIP_OWNER);
    }

    function handleClick(event) {
        var actionEl = event.target.closest("[data-bm-action]");
        if (!actionEl || !_el.contains(actionEl)) return;
        var action = actionEl.getAttribute("data-bm-action");
        if (action === "close") { closePanel(); return; }
        if (action === "open-help") { openDrawer("help", actionEl); return; }
        if (action === "open-debug") { openDrawer("debug", actionEl); return; }
        if (action === "debug-apply") { applyDebugOptions(); return; }
        if (action === "debug-reset") {
            try { restartSession({}); } catch (error) {
                _error = error && error.message ? error.message : String(error);
                render();
            }
            return;
        }
        if (action === "close-drawer") { closeDrawer(); return; }
        if (action === "close-inspection") { closeInspection(); return; }
        if (action === "inspection-rotate") { rotateInspection(); return; }
        if (action === "inspection-side") {
            switchInspection(actionEl.getAttribute("data-pair-id"), actionEl.getAttribute("data-offer-id"));
            return;
        }
        if (action === "dismiss-error") { _error = null; render(); return; }
        if (!_session || !_snapshot || _busy) return;
        if (action === "inspect-selected") {
            openInspection(actionEl.getAttribute("data-pair-id"), actionEl.getAttribute("data-offer-id"), actionEl);
            return;
        }
        if (action === "select") {
            _selectedPairId = actionEl.getAttribute("data-pair-id");
            _selectedOfferId = actionEl.getAttribute("data-offer-id");
            _payment = "tp";
            notifyFx("fx-select");
            refreshPreview();
            return;
        }
        if (action === "payment") {
            _payment = actionEl.getAttribute("data-payment") === "k" ? "k" : "tp";
            refreshPreview();
            return;
        }
        if (action === "cancel") { clearSelection(); render(); return; }
        if (action === "confirm") { confirmPurchase(); return; }
        if (action === "settle") { runProduct(function() {
            return _session.product.settle(actionEl.getAttribute("data-settle"), nextCallId("settle"));
        }, true, "settle"); return; }
        if (action === "skip") { runProduct(function() {
            return _session.product.skip(actionEl.getAttribute("data-pair-id"), nextCallId("skip"));
        }, true, "skip"); return; }
        if (action === "next-page") { runProduct(function() {
            return _session.product.nextPage(nextCallId("next-page"));
        }, true, "next-page"); return; }
    }

    function refreshPreview() {
        var pairId = _selectedPairId;
        var offerId = _selectedOfferId;
        if (!pairId || !offerId) return;
        try {
            _preview = _session.product.purchasePreview({ pairId: pairId, offerId: offerId, payment: _payment });
            _error = null;
        } catch (error) {
            _preview = null;
            _error = error && error.message ? error.message : String(error);
        }
        render();
    }

    function confirmPurchase() {
        if (!_preview) return;
        var preview = _preview;
        runProduct(function() {
            return _session.product.purchaseCommit(preview.token, nextCallId("purchase"));
        }, true, "purchase");
    }

    function runProduct(operation, clear, eventKind) {
        if (_busy) return;
        _busy = true;
        render();
        Promise.resolve().then(operation).then(function(snapshot) {
            _snapshot = snapshot;
            _error = null;
            if (clear) clearSelection();
            notifyHost(eventKind, sessionTelemetry());
            if (eventKind === "purchase" && snapshot.pending) {
                var pendingPair = findPair(snapshot.pending.pairId);
                var pendingOffer = pendingPair && findOffer(pendingPair, snapshot.pending.offerId);
                notifyFx("fx-reveal-" + (pendingOffer && pendingOffer.revealed
                    ? pendingOffer.revealed.direction : "loss"));
            }
            if (eventKind === "skip") notifyFx("fx-drain");
        }).catch(function(error) {
            _error = error && error.message ? error.message : String(error);
            notifyFx("fx-error");
            if (_session) _snapshot = _session.product.open();
        }).then(function() {
            _busy = false;
            render();
        });
    }

    function handleKeydown(event) {
        if (!_snapshot) return;
        if (event.key === "Escape" && _inspection) {
            event.preventDefault();
            closeInspection();
            return;
        }
        if (_inspection) {
            if (event.key === "Tab") trapInspectionTab(event);
            return;
        }
        if (event.key === "Escape" && _drawer) {
            event.preventDefault();
            closeDrawer();
            return;
        }
        if (_drawer) {
            if (event.key === "Tab") trapDrawerTab(event);
            return;
        }
        var activeOffer = event.target.closest && event.target.closest("[data-offer-id]");
        if (!activeOffer) return;
        if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
            event.preventDefault();
            var pairId = activeOffer.getAttribute("data-pair-id");
            var offers = _el.querySelectorAll('[data-pair-id="' + pairId + '"][data-offer-id]');
            var index = Array.prototype.indexOf.call(offers, activeOffer);
            var next = event.key === "ArrowLeft" ? Math.max(0, index - 1) : Math.min(offers.length - 1, index + 1);
            if (offers[next]) offers[next].focus();
        } else if (event.key.toLowerCase() === "s") {
            event.preventDefault();
            runProduct(function() {
                return _session.product.skip(activeOffer.getAttribute("data-pair-id"), nextCallId("skip-key"));
            }, true, "skip");
        } else if (event.key.toLowerCase() === "v") {
            event.preventDefault();
            openInspection(activeOffer.getAttribute("data-pair-id"),
                activeOffer.getAttribute("data-offer-id"), activeOffer);
        }
    }

    function closePanel() {
        if (_scaleShell) _scaleShell.classList.add("is-powering-off");
        if (_closePending) return true;
        var panelInstanceId = _init && _init.panelInstanceId;
        if (!panelInstanceId || typeof Bridge === "undefined" || !Bridge.send) {
            _error = "测试面板实例已失效，关闭请求未发送。";
            render();
            return false;
        }
        var generation = _openGeneration;
        _closePending = true;
        _busy = true;
        _error = "正在等待 Launcher 确认关闭当前测试实例…";
        render();
        var accepted = false;
        try {
            accepted = Bridge.send({ type: "panel", cmd: "close", panel: "blackmarket",
                panelInstanceId: panelInstanceId }) === true;
        } catch (error) {
            accepted = false;
        }
        if (!accepted) {
            if (_panelOpen && _openGeneration === generation
                    && _init && _init.panelInstanceId === panelInstanceId) {
                _closePending = false;
                _busy = false;
                _error = "Launcher 连接不可用，测试面板保持打开。";
                render();
            }
            return false;
        }
        if (_panelOpen && _closePending && _openGeneration === generation
                && _init && _init.panelInstanceId === panelInstanceId) {
            _closeTimer = setTimeout(function() {
                _closeTimer = null;
                if (!_panelOpen || !_closePending
                        || _openGeneration !== generation
                        || !_init || _init.panelInstanceId !== panelInstanceId) return;
                _closePending = false;
                _busy = false;
                _error = "Launcher 尚未确认关闭，可再次尝试。";
                render();
            }, closeAckTimeoutMs());
        }
        return true;
    }

    function cleanup() {
        clearCloseTimer();
        clearSoftlockObservation();
        _openGeneration += 1;
        _surfaceGeneration += 1;
        _panelOpen = false;
        _closePending = false;
        _session = null;
        _snapshot = null;
        _selectedPairId = null;
        _selectedOfferId = null;
        _preview = null;
        _drawer = null;
        _drawerOpenerKey = null;
        _surfaceMetrics = {};
        _surfaceMasters = {};
        _surfaceSnapshotKey = null;
        _inspection = null;
        destroyInspectionCamera();
        hideOfferTip();
        stopBubbles();
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = null;
        if (_surfaceRenderer) _surfaceRenderer.destroy();
        _surfaceRenderer = null;
        _busy = false;
        _error = null;
    }

    function closeAckTimeoutMs() {
        var configured = Number(window.__CF7_PANEL_CLOSE_ACK_TIMEOUT_MS__);
        return isFinite(configured) && configured >= 50
            ? Math.min(configured, 3000) : 3000;
    }

    function clearCloseTimer() {
        if (_closeTimer !== null) clearTimeout(_closeTimer);
        _closeTimer = null;
    }

    function startSoftlockObservation() {
        clearSoftlockObservation();
        if (!_panelOpen || !_init || _init.softlockObservation !== true) return;
        sendSoftlockObservation();
        _softlockObservationTimer = setInterval(sendSoftlockObservation, 10000);
    }

    function clearSoftlockObservation() {
        if (_softlockObservationTimer !== null) {
            clearInterval(_softlockObservationTimer);
        }
        _softlockObservationTimer = null;
    }

    function sendSoftlockObservation() {
        if (!_panelOpen || !_init || _init.softlockObservation !== true) return false;
        _softlockObservationSequence += 1;
        return notifyHost("heartbeat", {
            panelInstanceId: _init.panelInstanceId || "",
            documentGeneration: _openGeneration,
            sequence: _softlockObservationSequence,
            snapshotRevision: _snapshot && Number.isFinite(Number(_snapshot.revision))
                ? Number(_snapshot.revision) : 0,
            pending: _busy || _closePending || Object.keys(_tipRequests).length > 0
        });
    }

    function notifyHost(kind, data) {
        if (!_panelOpen && kind !== "close") return false;
        if (typeof MinigameHostBridge !== "undefined" && MinigameHostBridge.sendSession) {
            return MinigameHostBridge.sendSession("blackmarket", kind, data || {});
        }
        return false;
    }

    // P2 演出钩子：给 Host/未来的音效系统暴露机器演出时刻。纯通知、无状态依赖，
    // Host 缺席时静默为 no-op。kind 全集：fx-select / fx-reveal-profit / fx-reveal-loss /
    // fx-error / fx-scan-open / fx-scan-rotate / fx-drain / fx-poweron。
    function notifyFx(name) {
        if (!_panelOpen) return false;
        if (typeof MinigameHostBridge !== "undefined" && MinigameHostBridge.sendSession) {
            return MinigameHostBridge.sendSession("blackmarket", "fx", { fx: name });
        }
        return false;
    }

    function sessionTelemetry() {
        if (!_snapshot) return { shadowOnly: true, phase: _error ? "error" : "loading" };
        return {
            shadowOnly: true,
            productionWrites: false,
            catalogDigest: _snapshot.catalog.digest,
            totalItems: _snapshot.catalog.totalItems,
            mechanicallyRenderable: _snapshot.catalog.mechanicallyRenderable,
            pageNumber: _snapshot.page.number,
            revision: _snapshot.revision,
            decryptLevel: _snapshot.decryptLevel,
            pending: !!_snapshot.pending
        };
    }

    function clearSelection() {
        _selectedPairId = null;
        _selectedOfferId = null;
        _payment = "tp";
        _preview = null;
        _inspection = null;
        destroyInspectionCamera();
    }

    function findPair(pairId) {
        if (!_snapshot || !pairId) return null;
        return _snapshot.pairs.filter(function(pair) { return pair.pairId === pairId; })[0] || null;
    }

    function findOffer(pair, offerId) {
        if (!pair || !offerId) return null;
        return pair.offers.filter(function(offer) { return offer.offerId === offerId; })[0] || null;
    }

    function categoryLabel(category) {
        return category === "anonymous" ? "匿名货物"
            : (category === "equipment" ? "装备" : category === "material" ? "材料" : "消耗品");
    }

    function terminalLabel(status) {
        if (status === "skipped") return "整舱封签";
        if (status === "extracted") return "已提取";
        if (status === "resold") return "已回售";
        return "待结算";
    }

    function buildOfferAria(offer) {
        if (offer.revealed) return offer.revealed.displayName + "，" + (offer.revealed.direction === "profit" ? "盈利" : "亏损");
        return offer.label + "，" + (offer.hint || "身份未明");
    }

    function disabledAttr() { return _busy ? "disabled" : ""; }
    function finite(value) { return Number.isFinite(Number(value)) ? String(Number(value)) : "0"; }
    function formatNumber(value) { return new Intl.NumberFormat("zh-CN").format(Number(value) || 0); }
    function shortDigest(value) { return String(value || "").slice(0, 12); }
    function nextCallId(operation) {
        _callSequence += 1;
        return "bm-shadow-" + operation + "-" + _callSequence + "-" + (Date.now() >>> 0);
    }
    function sanitizeInit(value) {
        var input = value && typeof value === "object" ? value : {};
        return {
            mode: typeof input.mode === "string" ? input.mode : DEFAULT_INIT.mode,
            source: typeof input.source === "string" ? input.source : DEFAULT_INIT.source,
            shadowOnly: input.shadowOnly === true,
            debug: input.debug === true,
            softlockObservation: input.softlockObservation === true,
            panelInstanceId: typeof input.panelInstanceId === "string"
                ? input.panelInstanceId : ""
        };
    }
    function escapeHtml(value) {
        return String(value === null || value === undefined ? "" : value)
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;").replace(/'/g, "&#039;");
    }
    function escapeAttr(value) { return escapeHtml(value); }
    function currentFocusKey() {
        var active = document.activeElement;
        return active && active.getAttribute ? active.getAttribute("data-focus-key") : null;
    }
    function restoreFocus(key) {
        if (!key || !_root) return;
        var nodes = _root.querySelectorAll("[data-focus-key]");
        var i;
        for (i = 0; i < nodes.length; i += 1) {
            if (nodes[i].getAttribute("data-focus-key") === key && !nodes[i].disabled) {
                nodes[i].focus();
                return;
            }
        }
    }
    function focusDrawer() {
        setTimeout(function() {
            var close = _root && _root.querySelector('[data-bm-action="close-drawer"]');
            if (close) close.focus();
        }, 0);
    }
    function openDrawer(kind, opener) {
        _inspection = null;
        destroyInspectionCamera();
        _drawer = kind;
        _drawerOpenerKey = opener && opener.getAttribute ? opener.getAttribute("data-focus-key") : null;
        render();
        focusDrawer();
    }
    function closeDrawer() {
        var openerKey = _drawerOpenerKey;
        _drawer = null;
        _drawerOpenerKey = null;
        render();
        restoreFocus(openerKey);
    }
    function trapDrawerTab(event) {
        var drawer = _root && _root.querySelector(".blackmarket-drawer");
        if (!drawer) return;
        var nodes = drawer.querySelectorAll('button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])');
        if (!nodes.length) return;
        var first = nodes[0];
        var last = nodes[nodes.length - 1];
        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first.focus();
        }
    }
    function trapInspectionTab(event) {
        var dialog = _root && _root.querySelector(".blackmarket-inspection-dialog");
        if (!dialog) return;
        var nodes = dialog.querySelectorAll('button:not([disabled]), [tabindex]:not([tabindex="-1"])');
        if (!nodes.length) return;
        var first = nodes[0];
        var last = nodes[nodes.length - 1];
        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first.focus();
        }
    }
    function failBoot(message) {
        _error = message;
        _snapshot = null;
        render();
    }

    return {};
})();
