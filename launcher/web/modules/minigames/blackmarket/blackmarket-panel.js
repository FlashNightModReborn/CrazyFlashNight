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
    var _openGeneration = 0;
    var _callSequence = 0;
    var _surfaceRenderer = null;
    var _surfaceMetrics = {};
    var _surfaceSnapshotKey = null;
    var _surfaceGeneration = 0;
    var _surfaceMasters = {};
    var _inspection = null;
    var _inspectionCamera = null;

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
        debug: false
    };

    if (typeof Panels !== "undefined") {
        Panels.register("blackmarket", {
            create: createDOM,
            onOpen: onOpen,
            onRequestClose: closePanel,
            onClose: cleanup,
            onForceClose: cleanup
        });
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
        return _scaleShell;
    }

    function onOpen(el, initData) {
        var generation = ++_openGeneration;
        _panelOpen = true;
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
        destroyInspectionCamera();
        _surfaceGeneration += 1;
        _callSequence = 0;
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
        } catch (error) {
            if (!_panelOpen || generation !== _openGeneration) return;
            _busy = false;
            failBoot(error && error.message ? error.message : String(error));
        }
    }

    function resolveUrl(path) {
        if (typeof MinigameHostBridge !== "undefined" && MinigameHostBridge.resolveUrl) {
            return MinigameHostBridge.resolveUrl(path);
        }
        return path;
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
        _root.innerHTML = [
            renderHeader(),
            '<main class="blackmarket-deck">',
                _snapshot.pairs.map(renderPair).join(""),
            '</main>',
            renderBottomRail(),
            _error ? '<div class="blackmarket-error" role="alert"><b>操作被拒绝</b><span>'
                + escapeHtml(_error) + '</span><button type="button" data-bm-action="dismiss-error" data-focus-key="dismiss-error">×</button></div>' : "",
            renderDrawer(),
            renderInspection()
        ].join("");
        restoreFocus(focusKey);
        mountInspection();
        scheduleSurfaceHydration();
    }

    function renderHeader() {
        var stats = _snapshot.catalog;
        return [
            '<header class="blackmarket-header">',
                '<div class="blackmarket-brand">',
                    '<span>FALLEN CITY / ILLEGAL APPRAISAL</span>',
                    '<h1>盗贼黑市 · 匿名影子检货台</h1>',
                '</div>',
                '<div class="blackmarket-ledger">',
                    ledgerCell("TP", formatNumber(_snapshot.balances.tradePoints), "commerce"),
                    ledgerCell("K", formatNumber(_snapshot.balances.kPoints), "tech"),
                    ledgerCell("解密", "Lv." + _snapshot.decryptLevel, "tech"),
                    ledgerCell("夹具", stats.mechanicallyRenderable + " / " + stats.totalItems, ""),
                '</div>',
                '<div class="blackmarket-head-actions">',
                    '<button type="button" data-bm-action="open-help" data-focus-key="help">说明</button>',
                    '<button class="danger" type="button" data-bm-action="close" data-focus-key="close" aria-label="关闭黑市测试">×</button>',
                '</div>',
                '<div class="blackmarket-shadow-banner"><b>SHADOW</b><span>仅匿名合成货物；Web 不加载真实目录；零正式库存、货币与主存档写入</span>',
                    '<code>' + escapeHtml(shortDigest(stats.digest)) + '</code></div>',
            '</header>'
        ].join("");
    }

    function ledgerCell(label, value, tone) {
        return '<div class="blackmarket-ledger-cell ' + tone + '"><span>' + escapeHtml(label)
            + '</span><strong>' + escapeHtml(value) + '</strong></div>';
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
        if (offer.visualState === "withdrawn") terminal = '<span class="blackmarket-shutter"><b></b><b></b><b></b><em>同舱撤回</em></span>';
        if (offer.visualState === "sealed") terminal = '<span class="blackmarket-sealed">整舱封签</span>';
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
                '</span>',
                direction,
                '<strong class="blackmarket-offer-name">', escapeHtml(name), '</strong>',
                '<small>', revealed
                    ? '基础价 ' + formatNumber(revealed.basePrice) + ' · 回售 ' + formatNumber(revealed.resellValue)
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
                        assetUrl: visual.assetUrl,
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
                        sharpenSource: visual.sharpenSource === true,
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
            + '<canvas data-bm-inspection-canvas width="1" height="1" aria-hidden="true"></canvas></div></div>'
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
        notifyHost("inspection-open", merge(sessionTelemetry(), {
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
        destroyInspectionCamera();
        mountInspection();
        var output = _root.querySelector("[data-bm-inspection-rotation]");
        if (output) output.textContent = "当前旋转 " + _inspection.rotation + "°";
    }

    function destroyInspectionCamera() {
        if (_inspectionCamera && _inspectionCamera.destroy) _inspectionCamera.destroy();
        _inspectionCamera = null;
    }

    function handleClick(event) {
        var actionEl = event.target.closest("[data-bm-action]");
        if (!actionEl || !_el.contains(actionEl)) return;
        var action = actionEl.getAttribute("data-bm-action");
        if (action === "close") { closePanel(); return; }
        if (action === "open-help") { openDrawer("help", actionEl); return; }
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
        }).catch(function(error) {
            _error = error && error.message ? error.message : String(error);
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
        notifyHost("close", sessionTelemetry());
        cleanup();
        if (typeof Panels !== "undefined" && Panels.close) Panels.close();
        if (typeof Bridge !== "undefined" && Bridge.send) {
            Bridge.send({ type: "panel", cmd: "close", panel: "blackmarket" });
        }
    }

    function cleanup() {
        _openGeneration += 1;
        _surfaceGeneration += 1;
        _panelOpen = false;
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
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = null;
        if (_surfaceRenderer) _surfaceRenderer.destroy();
        _surfaceRenderer = null;
        _busy = false;
        _error = null;
    }

    function notifyHost(kind, data) {
        if (!_panelOpen && kind !== "close") return false;
        if (typeof MinigameHostBridge !== "undefined" && MinigameHostBridge.sendSession) {
            return MinigameHostBridge.sendSession("blackmarket", kind, data || {});
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
            debug: input.debug === true
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
