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
    var _notice = null;
    var _drawer = null;
    var _drawerOpenerKey = null;
    var _panelOpen = false;
    var _closePending = false;
    var _closeTimer = null;
    var _openGeneration = 0;
    var _callSequence = 0;
    var _softlockObservationTimer = null;
    var _softlockObservationSequence = 0;

    // 持久化画布与增量挂载状态：避免每次点选/切支付全量 innerHTML 重建导致气泡瞬移与画布闪烁
    var _mountedShellKey = null;
    var _surfaceRenderer = null;
    var _equipmentPreview = null;
    var _surfaceMetrics = {};
    var _surfaceSnapshotKey = null;
    var _surfaceGeneration = 0;
    var _offerSurfaceGen = {};
    var _pairGenderPromises = {};
    var _surfaceMasters = {};
    var _hydratedSurfaceState = {};

    var ARMOR_SLOT_BY_USE = {
        "头部装备": "head",
        "上装装备": "body",
        "手部装备": "hand",
        "下装装备": "leg",
        "脚部装备": "foot"
    };
    var WEAPON_USES = {
        "长枪": true,
        "手枪": true,
        "刀": true
    };

    // 检视台状态（支持单件聚焦 + A/B 并排对照）
    var _inspection = null;
    var _inspectionCamera = null;

    // 编舞与交互防护状态
    var _fxRevealKey = null;
    var _fxBoot = false;
    var _fxShutterPage = null;
    var _fxShutterPlayed = {};
    var _skipArmedPairId = null;
    var _skipArmTimer = null;
    var _siphonTimer = null;
    var _prevBalances = null;

    // T800 机械骷髅扩音头（假肢仙人“终结者崇拜者”工坊内线语音终端）状态
    var _t800Mood = "idle";
    var _t800Look = "center";
    var _t800Line = "";
    var _t800Tag = "假肢仙人 · 终结者扩音首";
    var _t800TalkTimer = null;
    var _t800QuipIndex = 0;

    // 轻量机台 Web Audio 合成器（消费全部 fx-* 演出时刻，静音可随时切换）
    var _audio = null;
    var _muted = false;

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

    var T800_LINES = {
        boot: [
            "后门插好了？别盯着这颗铁骷髅看，我本尊在后屋焊雷呢，有事冲它喊就行。",
            "欢迎光临终结者崇拜者工坊。三对刚从废城捞出来的纳米封件，挑对归你，剩的归我搓雷。"
        ],
        select: [
            "盯上这件了？挑中归你脱壳，同舱另一件可就归我引流炼雷了。",
            "同型毛坯里的纳米群品种最接近——通电一刺激，全往牺牲那件里钻。",
            "拿不准就按 V 或双击上扫描台，纳米壳睡死前可不会自己招供。"
        ],
        selectK: [
            "拿 K 点直付干脆利落，记住按五十比一向上取整，本工坊概不找零。",
            "直接掏 K 点开槽？行，反正炼出来的纳米雷够我再焊两副假肢。"
        ],
        inspect: [
            "使劲照吧，切 A/B 并排比轮廓最管用——认得出破局点算你本事。",
            "扫描台只放大同一份覆泥证据，想靠放大把纳米群照化是不可能的。"
        ],
        profit: [
            "啧，眼够毒啊……拿块破铁给我垫雷？算你赚到了，快选提取还是当场回售。",
            "好眼力！这回让我亏了半车原料，不过能省下我一条胳膊也值了。"
        ],
        loss: [
            "哈哈，谢了伙计！你把值钱那件喂了纳米群，这颗雷够抵半辆汽车炸弹了！",
            "可惜喽，看走眼了吧？别灰心，趁还没出工坊可以当场回售止损，或干脆提走自用。"
        ],
        extracted: [
            "货已装袋！离开工坊就不归黑市管喽，看一眼对面爆弹残片，下回眼更亮。"
        ],
        resold: [
            "交易点已打进绿管。记住——凑够五十就能单向换 K 点，随时能提。"
        ],
        skip: [
            "怕炸断手？行，这槽我封签留着自己慢慢拆。",
            "稳健派啊……看不准确实别硬赌，放过比乱买强。"
        ],
        rawbox: [
            "原装毛坯收下！固定工钱加补货信用已经进账——稳拿低保还是下台搏大，你自己定。"
        ],
        redeemK: [
            "五十交易点换一 K 点，童叟无欺。废城里最稳当的进项都在我这台子上。"
        ],
        complete: [
            "这批三槽全结清了！信用够就点“整理下一批”，不够先交几个毛坯换信用。"
        ],
        error: [
            "操之过急啦伙计，先看清兜里点数和台面状态再按。"
        ],
        poke: [
            "别敲我这颗 T800 脑壳，漆刮花了你赔得起吗？",
            "机械飞升才是出路啊……原生手掌拆纳米雷，炸一次就老实了。",
            "想要保底 K 点？把战斗捡的毛坯直接卖我就行，绝不亏本。",
            "解密等级越高，这台子能破译的纳米协议层越深——五级看轮廓，十级直接锁净值。"
        ]
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

    // ── 轻量工业机台 Web Audio 合成器 ────────────────────────────
    function createMachineAudio() {
        var ctx = null;
        function ensure() {
            if (_muted || typeof window === "undefined") return null;
            if (!ctx) {
                var Ctor = window.AudioContext || window.webkitAudioContext;
                if (!Ctor) return null;
                try { ctx = new Ctor(); } catch (error) { return null; }
            }
            if (ctx && ctx.state === "suspended" && ctx.resume) {
                try { ctx.resume(); } catch (error) {}
            }
            return ctx;
        }
        function tone(type, f0, f1, delay, dur, peak) {
            var ac = ensure();
            if (!ac) return;
            var now = ac.currentTime + (delay || 0);
            var osc = ac.createOscillator();
            var gain = ac.createGain();
            osc.type = type || "triangle";
            osc.frequency.setValueAtTime(Math.max(20, f0), now);
            if (f1 && f1 !== f0) {
                osc.frequency.exponentialRampToValueAtTime(Math.max(20, f1), now + dur);
            }
            gain.gain.setValueAtTime(0.0001, now);
            gain.gain.linearRampToValueAtTime(peak || 0.03, now + Math.min(0.015, dur * 0.25));
            gain.gain.exponentialRampToValueAtTime(0.0001, now + dur);
            osc.connect(gain);
            gain.connect(ac.destination);
            osc.start(now);
            osc.stop(now + dur + 0.02);
        }
        return {
            play: function(name) {
                if (_muted) return;
                if (name === "fx-poweron") {
                    tone("sawtooth", 72, 148, 0, 0.22, 0.022);
                    tone("sine", 320, 480, 0.14, 0.14, 0.018);
                } else if (name === "fx-select") {
                    tone("triangle", 520, 680, 0, 0.055, 0.022);
                } else if (name === "fx-scan-open") {
                    tone("sine", 260, 560, 0, 0.12, 0.022);
                } else if (name === "fx-scan-rotate") {
                    tone("square", 380, 220, 0, 0.045, 0.016);
                } else if (name === "fx-reveal-profit") {
                    // 纳米引流扫频 + 脱壳清脆双和弦
                    tone("sawtooth", 180, 420, 0, 0.18, 0.018);
                    tone("triangle", 523, 523, 0.18, 0.14, 0.03);
                    tone("triangle", 659, 784, 0.28, 0.22, 0.032);
                } else if (name === "fx-reveal-loss") {
                    // 纳米引流 + 防爆闸门沉闷重砸 + 机械笑声双脉冲
                    tone("sawtooth", 210, 92, 0, 0.2, 0.024);
                    tone("square", 110, 56, 0.18, 0.16, 0.034);
                    tone("sawtooth", 260, 190, 0.36, 0.07, 0.02);
                    tone("sawtooth", 240, 175, 0.45, 0.09, 0.02);
                } else if (name === "fx-drain") {
                    tone("sawtooth", 240, 95, 0, 0.18, 0.02);
                    tone("triangle", 140, 82, 0.15, 0.1, 0.022);
                } else if (name === "fx-rawbox") {
                    tone("triangle", 150, 110, 0, 0.08, 0.028);
                    tone("sine", 540, 720, 0.08, 0.12, 0.025);
                } else if (name === "fx-redeem-k") {
                    tone("sine", 660, 880, 0, 0.09, 0.024);
                    tone("sine", 990, 1320, 0.09, 0.14, 0.024);
                } else if (name === "fx-error") {
                    tone("square", 160, 130, 0, 0.08, 0.024);
                    tone("square", 130, 110, 0.11, 0.1, 0.024);
                } else if (name === "fx-talk") {
                    tone("square", 290, 340, 0, 0.035, 0.011);
                    tone("square", 240, 310, 0.06, 0.035, 0.01);
                    tone("square", 320, 260, 0.12, 0.04, 0.01);
                }
            },
            close: function() {
                if (ctx && ctx.close) {
                    try { ctx.close(); } catch (error) {}
                }
                ctx = null;
            }
        };
    }

    function ensureAudio() {
        if (!_audio) _audio = createMachineAudio();
        return _audio;
    }

    // ── T800 机械骷髅扩音头 SVG（呼应“终结者崇拜者”假肢工坊）──
    function renderT800Svg() {
        return [
            '<svg class="bm-t800-svg" viewBox="0 0 96 96" aria-hidden="true">',
                '<defs>',
                    '<linearGradient id="bm-chrome" x1="0" y1="0" x2="1" y2="1">',
                        '<stop offset="0%" stop-color="#9aa4ab"/>',
                        '<stop offset="45%" stop-color="#5d666c"/>',
                        '<stop offset="100%" stop-color="#2c3236"/>',
                    '</linearGradient>',
                    '<linearGradient id="bm-chrome-hi" x1="0" y1="0" x2="0" y2="1">',
                        '<stop offset="0%" stop-color="#c9d3d9"/>',
                        '<stop offset="100%" stop-color="#606a70"/>',
                    '</linearGradient>',
                    '<radialGradient id="bm-eye-glow" cx="50%" cy="50%" r="50%">',
                        '<stop offset="0%" stop-color="#fff0ee"/>',
                        '<stop offset="45%" stop-color="#ff3b30"/>',
                        '<stop offset="100%" stop-color="#ff3b30" stop-opacity="0"/>',
                    '</radialGradient>',
                '</defs>',
                // 底座红蓝外接线缆（呼应终结者合成台机身电线）
                '<path d="M18 89 C10 85, 8 76, 16 72" fill="none" stroke="#1859b8" stroke-width="3.2" stroke-linecap="round"/>',
                '<path d="M78 89 C86 85, 88 76, 80 72" fill="none" stroke="#c8352f" stroke-width="3.2" stroke-linecap="round"/>',
                // 工业底座法兰与机械颈柱
                '<path d="M16 82 L80 82 L84 93 L12 93 Z" fill="#1e2427" stroke="#070a0b" stroke-width="2.2"/>',
                '<rect x="34" y="69" width="28" height="15" rx="2" fill="#2f363a" stroke="#070a0b" stroke-width="2"/>',
                '<line x1="41" y1="71" x2="41" y2="82" stroke="#6c777e" stroke-width="2"/>',
                '<line x1="55" y1="71" x2="55" y2="82" stroke="#6c777e" stroke-width="2"/>',
                '<circle cx="24" cy="87.5" r="2.2" class="bm-t800-led"/>',
                '<rect x="36" y="85.5" width="24" height="4" rx="1" fill="#0b0f11"/>',
                '<line x1="40" y1="87.5" x2="56" y2="87.5" class="bm-t800-wave" stroke-width="1.8" stroke-dasharray="3 2"/>',
                // 头部可偏转组
                '<g class="bm-t800-head">',
                    // 机械下颌与下排铁齿（独立组：说话/大笑时张合动画）
                    '<g class="bm-t800-jaw">',
                        '<path d="M29 53 L33 72 L41 77 L55 77 L63 72 L67 53 L60 56 L57 67 L39 67 L36 56 Z" fill="url(#bm-chrome)" stroke="#070a0b" stroke-width="2.3" stroke-linejoin="round"/>',
                        '<path d="M38 61 L58 61 L56 68 L40 68 Z" fill="#dce3e7" stroke="#070a0b" stroke-width="1.6"/>',
                        '<path d="M43 61 L43 68 M48 61 L48 68 M53 61 L53 68" stroke="#181d20" stroke-width="1.4"/>',
                        '<path d="M36 70 L60 70" stroke="#111619" stroke-width="1.5"/>',
                    '</g>',
                    // 颅骨主体与颧骨装甲
                    '<path d="M23 37 C22 17, 34 8, 48 8 C62 8, 74 17, 73 37 L71 49 L64 56 L59 56 L57 59 L39 59 L37 56 L32 56 L25 49 Z" fill="url(#bm-chrome)" stroke="#070a0b" stroke-width="2.5" stroke-linejoin="round"/>',
                    // 额顶高光棱板与铆钉
                    '<path d="M32 16 C39 11, 57 11, 64 16 L60 28 L36 28 Z" fill="url(#bm-chrome-hi)" stroke="#070a0b" stroke-width="1.6"/>',
                    '<circle cx="29" cy="31" r="3.4" fill="#3a4247" stroke="#070a0b" stroke-width="1.6"/>',
                    '<circle cx="67" cy="31" r="3.4" fill="#3a4247" stroke="#070a0b" stroke-width="1.6"/>',
                    '<circle cx="57" cy="17" r="2" fill="#23282b" stroke="#070a0b" stroke-width="1.2"/>',
                    // 粗重眉脊
                    '<path d="M26 34 L43 37 L48 34 L53 37 L70 34 L67 29 L48 31 L29 29 Z" fill="#373f44" stroke="#070a0b" stroke-width="1.8" stroke-linejoin="round"/>',
                    // 深凹双目眼眶
                    '<path d="M29 37 L44 39 L43 47 L31 46 Z" fill="#240909" stroke="#070a0b" stroke-width="1.8"/>',
                    '<path d="M67 37 L52 39 L53 47 L65 46 Z" fill="#240909" stroke="#070a0b" stroke-width="1.8"/>',
                    // 发光眼球组（可随选舱左右移动盯货）
                    '<g class="bm-t800-eyes">',
                        '<circle cx="37" cy="42.5" r="5.5" fill="url(#bm-eye-glow)" class="bm-t800-eye-halo"/>',
                        '<circle cx="59" cy="42.5" r="5.5" fill="url(#bm-eye-glow)" class="bm-t800-eye-halo"/>',
                        '<circle cx="37" cy="42.5" r="2.5" class="bm-t800-eye-core"/>',
                        '<circle cx="59" cy="42.5" r="2.5" class="bm-t800-eye-core"/>',
                    '</g>',
                    // 鼻腔凹槽与上排金属铁齿
                    '<path d="M48 45 L44.5 52 L51.5 52 Z" fill="#0d1113" stroke="#070a0b" stroke-width="1.3"/>',
                    '<path d="M37 54 L59 54 L57 60 L39 60 Z" fill="#e6ecef" stroke="#070a0b" stroke-width="1.6"/>',
                    '<path d="M42 54 L42 60 M46 54 L46 60 M50 54 L50 60 M54 54 L54 60" stroke="#181d20" stroke-width="1.3"/>',
                '</g>',
            '</svg>'
        ].join("");
    }

    function createDOM() {
        _scaleShell = document.createElement("div");
        _scaleShell.className = "panel-scale-shell blackmarket-scale-shell";
        _el = document.createElement("div");
        _el.className = "minigame-panel blackmarket-panel";
        _el.innerHTML = '<div class="blackmarket-boot" data-bm-root>终结者合成台正在加压通电…</div>';
        _scaleShell.appendChild(_el);
        _root = _el.querySelector("[data-bm-root]");
        _el.addEventListener("click", handleClick);
        _el.addEventListener("dblclick", handleDblClick);
        _el.addEventListener("keydown", handleKeydown);
        _el.addEventListener("mouseover", handleTipOver);
        _el.addEventListener("mouseout", handleTipOut);
        _el.addEventListener("focusin", handleTipFocusIn);
        _el.addEventListener("focusout", handleTipFocusOut);
        return _scaleShell;
    }

    function onOpen(el, initData) {
        clearCloseTimer();
        clearSkipArmTimer();
        clearSiphonTimer();
        clearT800TalkTimer();
        var generation = ++_openGeneration;
        _panelOpen = true;
        _closePending = false;
        if (_scaleShell) _scaleShell.classList.remove("is-powering-off");
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
        _notice = null;
        _mountedShellKey = null;
        _surfaceMetrics = {};
        _surfaceMasters = {};
        _surfaceSnapshotKey = null;
        _hydratedSurfaceState = {};
        _offerSurfaceGen = {};
        _pairGenderPromises = {};
        _inspection = null;
        _fxRevealKey = null;
        _fxBoot = true;
        _fxShutterPage = null;
        _fxShutterPlayed = {};
        _prevBalances = null;
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
        ensureEquipmentPreview();
        try {
            _session = BlackMarketCore.createShadowSession({ decryptLevel: 3 });
            _snapshot = _session.product.open();
            _prevBalances = cloneBalances(_snapshot.balances);
            _busy = false;
            setT800State("boot", "center", pickLine("boot"), false);
            render({ full: true });
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

    function cloneBalances(b) {
        if (!b) return null;
        return {
            tradePoints: Number(b.tradePoints) || 0,
            kPoints: Number(b.kPoints) || 0,
            supplyCredits: Number(b.supplyCredits) || 0,
            rawBoxes: Number(b.rawBoxes) || 0
        };
    }

    function pickLine(category) {
        var list = T800_LINES[category];
        if (!list || !list.length) return "";
        _t800QuipIndex = (_t800QuipIndex + 1) % list.length;
        return list[_t800QuipIndex];
    }

    function setT800State(mood, look, line, playTalk) {
        _t800Mood = mood || "idle";
        if (look) _t800Look = look;
        if (typeof line === "string" && line) _t800Line = line;
        clearT800TalkTimer();
        var mount = _root && _root.querySelector(".bm-t800-mount");
        var caption = _root && _root.querySelector("[data-bm-t800-line]");
        if (mount) {
            mount.setAttribute("data-mood", _t800Mood);
            mount.setAttribute("data-look", _t800Look);
            mount.classList.remove("is-talking");
            void mount.offsetWidth;
            mount.classList.add("is-talking");
        }
        if (caption && _t800Line) {
            caption.textContent = _t800Line;
        }
        if (playTalk) ensureAudio().play("fx-talk");
        var duration = _t800Mood === "loss" ? 1150 : 880;
        _t800TalkTimer = setTimeout(function() {
            _t800TalkTimer = null;
            var node = _root && _root.querySelector(".bm-t800-mount");
            if (node) node.classList.remove("is-talking");
        }, duration);
    }

    function clearT800TalkTimer() {
        if (_t800TalkTimer !== null) clearTimeout(_t800TalkTimer);
        _t800TalkTimer = null;
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

    // ── 增量渲染引擎（零闪烁核心）──────────────────────────────────
    function render(options) {
        if (!_root) return;
        options = options || {};
        if (!_snapshot) {
            _mountedShellKey = null;
            destroyInspectionCamera();
            stopBubbles();
            _root.className = "blackmarket-boot";
            _root.innerHTML = _error
                ? '<div class="blackmarket-boot-error"><b>接入失败</b><span>' + escapeHtml(_error)
                    + '</span><button type="button" data-bm-action="close" data-focus-key="boot-close">关闭测试</button></div>'
                : '<span class="blackmarket-loader"></span><b>终结者合成台正在加压通电…</b>';
            return;
        }

        var shellKey = _snapshot.page.id + "|" + _snapshot.decryptLevel;
        var surfaceKey = _snapshot.page.id + "|" + _snapshot.decryptLevel + "|" + _snapshot.revision;
        var needFullMount = options.full === true || _mountedShellKey !== shellKey
            || !_root.querySelector(".blackmarket-deck");

        if (_fxShutterPage !== _snapshot.page.id) {
            _fxShutterPage = _snapshot.page.id;
            _fxShutterPlayed = {};
        }

        if (needFullMount) {
            var focusKey = options.focusKey || currentFocusKey();
            destroyInspectionCamera();
            _mountedShellKey = shellKey;
            _surfaceSnapshotKey = surfaceKey;
            _surfaceMetrics = {};
            _surfaceMasters = {};
            _hydratedSurfaceState = {};
            _offerSurfaceGen = {};
            _pairGenderPromises = {};
            _inspection = null;
            _root.className = "blackmarket-machine decrypt-" + _snapshot.decryptLevel;
            _root.innerHTML = [
                renderHeaderShell(),
                '<main class="blackmarket-deck">',
                    '<canvas class="blackmarket-bubbles" data-bm-bubbles aria-hidden="true"></canvas>',
                    _snapshot.pairs.map(renderPairShell).join(""),
                '</main>',
                renderBottomRailShell(),
                '<div class="blackmarket-toast-host" data-bm-toast-host></div>',
                '<div class="blackmarket-drawer-host" data-bm-drawer-host></div>',
                '<div class="blackmarket-inspection-host" data-bm-inspection-host></div>',
                '<div class="sr-only" data-bm-live aria-live="polite"></div>',
                _fxBoot ? '<div class="blackmarket-poweron" aria-hidden="true"><i></i><i></i></div>' : ""
            ].join("");
            _fxBoot = false;
            syncDynamicState(options);
            ensureBubbles();
            scheduleSurfaceHydration(true);
            restoreFocus(focusKey);
            return;
        }

        // 同页增量更新：保留 6 张画布与气泡动画，只刷新状态变化的部分
        _root.className = "blackmarket-machine decrypt-" + _snapshot.decryptLevel;
        _surfaceSnapshotKey = surfaceKey;
        syncDynamicState(options);
        if (options.rehydrateOfferId) {
            scheduleSingleOfferHydration(options.rehydrateOfferId);
        }
        if (options.focusKey) {
            restoreFocus(options.focusKey);
        }
    }

    function renderHeaderShell() {
        return [
            '<header class="blackmarket-header">',
                '<div class="blackmarket-brand">',
                    '<span>PROSTHETIC IMMORTAL · SYNTHESIZER</span>',
                    '<h1>终结者合成台 · 纳米脱壳工坊</h1>',
                '</div>',
                '<div class="blackmarket-ledger" data-bm-ledger>',
                    ledgerCellShell("tp", "交易点 TP", "vial-green", false),
                    ledgerCellShell("k", "K 点", "vial-cyan", true, "open-exchange", "点击按 50:1 兑换 K 点"),
                    ledgerCellShell("decrypt", "解密协议", "vial-purple", false),
                    ledgerCellShell("raw", "毛坯 / 信用", "vial-red", true, "redeem-rawbox", "上交 1 个未清洗毛坯换保底 TP 与补货信用"),
                '</div>',
                '<div class="blackmarket-head-actions">',
                    '<span class="blackmarket-shadow-chip" title="匿名影子测试模式：不写入正式存档与背包">SHADOW</span>',
                    '<button type="button" data-bm-action="toggle-mute" data-focus-key="mute" aria-label="切换机台音效">♪ 开</button>',
                    '<button type="button" data-bm-action="open-exchange" data-focus-key="exchange">兑K</button>',
                    '<button type="button" data-bm-action="open-debug" data-focus-key="debug">调试</button>',
                    '<button type="button" data-bm-action="open-help" data-focus-key="help">说明</button>',
                    '<button class="danger" type="button" data-bm-action="close" data-focus-key="close" aria-label="关闭黑市工坊">×</button>',
                '</div>',
            '</header>'
        ].join("");
    }

    function ledgerCellShell(key, label, vial, interactive, action, title) {
        var tag = interactive ? "button" : "div";
        var extra = interactive
            ? ' type="button" data-bm-action="' + action + '" data-focus-key="ledger-' + key + '" title="' + escapeAttr(title || "") + '"'
            : "";
        var ticks = key === "decrypt"
            ? '<em class="bm-vial-ticks" aria-hidden="true"><b style="bottom:30%"></b><b style="bottom:50%"></b><b style="bottom:70%"></b></em>'
            : "";
        return '<' + tag + ' class="blackmarket-ledger-cell ' + vial + (interactive ? " is-clickable" : "")
            + '" data-bm-vial="' + key + '"' + extra + '>'
            + '<span class="blackmarket-vial-tube" aria-hidden="true"><i data-bm-vial-fill="' + key + '"></i>' + ticks + '</span>'
            + '<div class="blackmarket-ledger-text"><span>' + escapeHtml(label)
            + '</span><strong data-bm-vial-val="' + key + '">—</strong></div>'
            + '<span class="bm-vial-delta" data-bm-vial-delta="' + key + '" aria-hidden="true"></span>'
            + '</' + tag + '>';
    }

    function renderPairShell(pair) {
        return [
            '<section class="blackmarket-bay" data-pair-id="', escapeAttr(pair.pairId), '" data-pair-index="', pair.index, '">',
                '<i class="blackmarket-rivet r1"></i><i class="blackmarket-rivet r2"></i>',
                '<i class="blackmarket-rivet r3"></i><i class="blackmarket-rivet r4"></i>',
                '<header class="blackmarket-bay-header">',
                    '<span class="bm-bay-no">0', pair.index, '</span>',
                    '<h2>同型配对槽</h2>',
                    '<em data-bm-pair-tag="', escapeAttr(pair.pairId), '">待检封件</em>',
                '</header>',
                '<div class="blackmarket-offers" role="radiogroup" aria-label="0', pair.index, ' 号配对槽二选一">',
                    renderOfferShell(pair, pair.offers[0]),
                    '<div class="blackmarket-divider" data-bm-bridge="', escapeAttr(pair.pairId), '" aria-hidden="true">',
                        '<i></i><b class="bm-bridge-beam"></b>',
                    '</div>',
                    renderOfferShell(pair, pair.offers[1]),
                '</div>',
                '<footer class="blackmarket-bay-footer" data-bm-bay-footer="', escapeAttr(pair.pairId), '">',
                    '<div class="blackmarket-price-tag"><span>脱壳标价</span><b>', formatNumber(pair.counterPriceTp),
                        ' TP</b><i>/</i><b class="tech">', pair.kCost, ' K</b></div>',
                    '<div class="blackmarket-bay-ctrl" data-bm-bay-ctrl="', escapeAttr(pair.pairId), '"></div>',
                '</footer>',
            '</section>'
        ].join("");
    }

    function renderOfferShell(pair, offer) {
        return [
            '<div class="blackmarket-offer-slot" data-slot-offer="', escapeAttr(offer.offerId), '">',
                '<button type="button" role="radio" class="blackmarket-offer state-available"',
                    ' data-bm-action="select" data-pair-id="', escapeAttr(pair.pairId), '" data-offer-id="', escapeAttr(offer.offerId), '"',
                    ' data-focus-key="offer-', escapeAttr(offer.offerId), '" aria-checked="false" aria-pressed="false">',
                    '<span class="blackmarket-side">', offer.side === "A" ? "左 / A" : "右 / B", '</span>',
                    '<span class="blackmarket-asset ', escapeAttr(offer.presentationKind), '">',
                        '<canvas class="blackmarket-item-surface" data-bm-surface="', escapeAttr(offer.offerId),
                            '" data-surface-state="loading" width="1" height="1" aria-hidden="true"></canvas>',
                        '<span class="blackmarket-surface-guard" aria-hidden="true"><b>纳米封壳读取中</b></span>',
                        '<span class="blackmarket-surface-readout" data-bm-surface-readout="', escapeAttr(offer.offerId), '"></span>',
                        '<span class="blackmarket-overlay-state" data-bm-offer-overlay="', escapeAttr(offer.offerId), '"></span>',
                        '<span class="blackmarket-fx-slot" data-bm-offer-fx="', escapeAttr(offer.offerId), '" aria-hidden="true"></span>',
                    '</span>',
                    '<span class="blackmarket-badge-slot" data-bm-offer-badge="', escapeAttr(offer.offerId), '"></span>',
                    '<strong class="blackmarket-offer-name" data-bm-offer-name="', escapeAttr(offer.offerId), '">', escapeHtml(offer.label), '</strong>',
                    '<small class="blackmarket-offer-sub" data-bm-offer-sub="', escapeAttr(offer.offerId), '"></small>',
                '</button>',
                '<button type="button" class="blackmarket-inspect-pin" data-bm-action="inspect-offer"',
                    ' data-pair-id="', escapeAttr(pair.pairId), '" data-offer-id="', escapeAttr(offer.offerId), '"',
                    ' title="放大检视 (双击货包或按 V)" aria-label="放大检视 ', offer.side, '" disabled>检视</button>',
            '</div>'
        ].join("");
    }

    function renderBottomRailShell() {
        return [
            '<footer class="blackmarket-rail idle" data-bm-rail>',
                '<div class="bm-t800-unit">',
                    '<button type="button" class="bm-t800-mount" data-bm-action="poke-t800" data-mood="', escapeAttr(_t800Mood),
                        '" data-look="', escapeAttr(_t800Look), '" title="假肢仙人 · 终结者扩音首（点击互动）" aria-label="假肢仙人终结者扩音首">',
                        renderT800Svg(),
                    '</button>',
                    '<div class="bm-t800-speech">',
                        '<span class="bm-t800-nameplate">', escapeHtml(_t800Tag), '</span>',
                        '<p class="bm-t800-caption" data-bm-t800-line>', escapeHtml(_t800Line), '</p>',
                    '</div>',
                '</div>',
                '<div class="blackmarket-rail-main" data-bm-rail-main></div>',
            '</footer>'
        ].join("");
    }

    // ── 局部精准同步状态 ─────────────────────────────────────────
    function syncDynamicState(options) {
        options = options || {};
        syncHeaderLedger();
        syncPairs();
        syncBottomRail();
        syncToasts();
        syncDrawerHost(options);
        syncInspectionHost(options);
        syncLiveRegion(options);
    }

    function logFill(value, decades) {
        var numeric = Math.max(1, Number(value) || 0);
        return Math.max(0.08, Math.min(1, Math.log(numeric) / Math.LN10 / decades));
    }

    function flashVialDelta(key, delta, suffix) {
        if (!delta || !_root) return;
        var el = _root.querySelector('[data-bm-vial-delta="' + key + '"]');
        if (!el) return;
        el.textContent = (delta > 0 ? "+" : "") + formatNumber(delta) + (suffix ? " " + suffix : "");
        el.className = "bm-vial-delta " + (delta > 0 ? "is-up" : "is-down");
        void el.offsetWidth;
        el.classList.add("is-pop");
    }

    function syncHeaderLedger() {
        if (!_root || !_snapshot) return;
        var b = _snapshot.balances;
        var muteBtn = _root.querySelector('[data-bm-action="toggle-mute"]');
        if (muteBtn) {
            muteBtn.textContent = _muted ? "♪ 静" : "♪ 开";
            muteBtn.classList.toggle("is-muted", _muted);
        }
        var tpCell = _root.querySelector('[data-bm-vial="tp"]');
        var kCell = _root.querySelector('[data-bm-vial="k"]');
        var decCell = _root.querySelector('[data-bm-vial="decrypt"]');
        var rawCell = _root.querySelector('[data-bm-vial="raw"]');

        updateVial(tpCell, "tp", formatNumber(b.tradePoints), logFill(b.tradePoints, 6), !!_selectedOfferId && _payment === "tp");
        updateVial(kCell, "k", formatNumber(b.kPoints), logFill(b.kPoints, 4), !!_selectedOfferId && _payment === "k");
        // 解密满级为 Lv.10（修复原 /5 导致 Lv.5 即满管的缺陷）
        updateVial(decCell, "decrypt", "Lv." + _snapshot.decryptLevel, Math.max(0.06, Math.min(1, _snapshot.decryptLevel / 10)), false);
        updateVial(rawCell, "raw", "毛坯 " + b.rawBoxes + " · 信用 " + b.supplyCredits,
            Math.max(0.08, Math.min(1, (b.rawBoxes + b.supplyCredits) / 6)), false);
        if (rawCell) rawCell.disabled = _busy || !!_snapshot.pending || b.rawBoxes <= 0;

        if (_prevBalances) {
            flashVialDelta("tp", b.tradePoints - _prevBalances.tradePoints, "TP");
            flashVialDelta("k", b.kPoints - _prevBalances.kPoints, "K");
            flashVialDelta("raw", b.supplyCredits - _prevBalances.supplyCredits, "信用");
        }
        _prevBalances = cloneBalances(b);
    }

    function updateVial(cell, key, text, fill, armed) {
        if (!cell) return;
        cell.classList.toggle("is-armed", !!armed);
        var val = cell.querySelector('[data-bm-vial-val="' + key + '"]');
        if (val) val.textContent = text;
        var bar = cell.querySelector('[data-bm-vial-fill="' + key + '"]');
        if (bar) bar.style.height = Math.round(Math.max(0, Math.min(1, fill)) * 100) + "%";
    }

    function syncPairs() {
        if (!_root || !_snapshot) return;
        var pendingFxKey = _snapshot.pending
            ? _snapshot.pending.pairId + "|" + _snapshot.revision : null;
        var freshReveal = pendingFxKey && pendingFxKey !== _fxRevealKey;
        if (pendingFxKey) _fxRevealKey = pendingFxKey;

        for (var i = 0; i < _snapshot.pairs.length; i += 1) {
            var pair = _snapshot.pairs[i];
            var bayEl = _root.querySelector('.blackmarket-bay[data-pair-id="' + pair.pairId + '"]');
            if (!bayEl) continue;
            var suppressed = _snapshot.pending && _snapshot.pending.pairId !== pair.pairId;
            var pairResult = pair.offers.filter(function(offer) { return offer.revealed; })[0];
            var tone = pairResult && pairResult.revealed ? pairResult.revealed.direction : "";

            bayEl.classList.toggle("is-suppressed", !!suppressed);
            bayEl.classList.toggle("tone-profit", tone === "profit");
            bayEl.classList.toggle("tone-loss", tone === "loss");
            bayEl.classList.toggle("is-terminal", pair.status !== "open" && pair.status !== "pending");

            var tagEl = bayEl.querySelector('[data-bm-pair-tag="' + pair.pairId + '"]');
            if (tagEl) {
                if (pair.status === "open") {
                    tagEl.textContent = pair.spreadBand
                        ? "波幅 · " + pair.spreadBand.label
                        : "批次 #" + _snapshot.page.number + " · 二选一";
                } else {
                    tagEl.textContent = terminalLabel(pair.status);
                }
            }

            // 中央纳米引流桥方向联动
            var bridgeEl = bayEl.querySelector('[data-bm-bridge="' + pair.pairId + '"]');
            if (bridgeEl) {
                if (freshReveal && _snapshot.pending && _snapshot.pending.pairId === pair.pairId) {
                    var chosenOffer = findOffer(pair, _snapshot.pending.offerId);
                    var dir = chosenOffer && chosenOffer.side === "A" ? "a-to-b" : "b-to-a";
                    bridgeEl.setAttribute("data-siphon", dir);
                    bridgeEl.classList.remove("is-firing");
                    void bridgeEl.offsetWidth;
                    bridgeEl.classList.add("is-firing");
                    clearSiphonTimer();
                    _siphonTimer = setTimeout(function() {
                        _siphonTimer = null;
                        var active = _root && _root.querySelector(".blackmarket-divider.is-firing");
                        if (active) active.classList.remove("is-firing");
                    }, 620);
                } else if (pair.status === "open") {
                    bridgeEl.removeAttribute("data-siphon");
                    bridgeEl.classList.remove("is-firing");
                }
            }

            // 同步左右两个货包
            for (var j = 0; j < pair.offers.length; j += 1) {
                syncOffer(bayEl, pair, pair.offers[j], freshReveal);
            }

            // 同步货舱底栏操作（含两段式防误触放过按钮）
            var ctrlEl = bayEl.querySelector('[data-bm-bay-ctrl="' + pair.pairId + '"]');
            if (ctrlEl) {
                if (pair.status === "open") {
                    var armed = _skipArmedPairId === pair.pairId;
                    ctrlEl.innerHTML = '<button type="button" class="' + (armed ? "is-skip-armed" : "")
                        + '" data-bm-action="skip" data-pair-id="' + escapeAttr(pair.pairId)
                        + '" data-focus-key="skip-' + escapeAttr(pair.pairId) + '" '
                        + ((_busy || !!_snapshot.pending) ? "disabled" : "") + '>'
                        + (armed ? '再按确认放过 <kbd>S</kbd>' : '整舱放过 <kbd>S</kbd>') + '</button>';
                } else {
                    ctrlEl.innerHTML = '<strong class="blackmarket-terminal status-' + escapeAttr(pair.status) + '">'
                        + escapeHtml(terminalLabel(pair.status)) + '</strong>';
                }
            }
        }
    }

    function syncOffer(bayEl, pair, offer, freshReveal) {
        var slotEl = bayEl.querySelector('[data-slot-offer="' + offer.offerId + '"]');
        if (!slotEl) return;
        var btn = slotEl.querySelector(".blackmarket-offer");
        var pin = slotEl.querySelector(".blackmarket-inspect-pin");
        if (!btn) return;

        var selected = _selectedOfferId === offer.offerId && pair.status === "open";
        var disabled = _busy || pair.status !== "open" || _snapshot.pending !== null;
        var revealed = offer.revealed;
        var name = revealed ? revealed.displayName : offer.label;

        btn.className = "blackmarket-offer" + (selected ? " is-selected" : "") + " state-" + offer.visualState;
        btn.disabled = disabled;
        btn.setAttribute("aria-checked", selected ? "true" : "false");
        btn.setAttribute("aria-pressed", selected ? "true" : "false");
        btn.setAttribute("aria-label", buildOfferAria(offer));

        if (pin) {
            var canInspect = pair.status === "open" && offer.visualState === "available"
                && !!surfaceMaster(offer.offerId) && !_busy && !_snapshot.pending;
            pin.disabled = !canInspect;
            pin.style.display = pair.status === "open" ? "" : "none";
        }

        // 覆盖层：牺牲成爆弹闸门（终局后附爆弹残片回执）或整舱封签
        var overlayEl = btn.querySelector('[data-bm-offer-overlay="' + offer.offerId + '"]');
        if (overlayEl) {
            if (offer.visualState === "withdrawn") {
                var shutterFresh = !_fxShutterPlayed[pair.pairId];
                _fxShutterPlayed[pair.pairId] = true;
                var residueHtml = "";
                if (pair.siblingResidue) {
                    var res = pair.siblingResidue;
                    residueHtml = '<span class="bm-bomb-residue" title="牺牲体残片读数">'
                        + '<b>残片：' + escapeHtml(res.displayName) + '</b>'
                        + '<i>回售 ' + formatNumber(res.saleValue) + ' TP'
                        + (res.wasWinner ? ' · 高值件' : ' · 低值件') + '</i></span>';
                }
                overlayEl.innerHTML = '<span class="blackmarket-shutter' + (shutterFresh ? " is-fresh" : "")
                    + '"><b></b><b></b><b></b><em>纳米聚团 · 封为爆弹</em>' + residueHtml + '</span>';
            } else if (offer.visualState === "sealed") {
                overlayEl.innerHTML = '<span class="blackmarket-sealed">整舱封签 · 未拆封</span>';
            } else {
                overlayEl.innerHTML = "";
            }
        }

        // 揭晓演出（爪落 + 纳米剥离扫光 + 盈亏脉冲，520ms 紧凑节奏，零阻塞）
        var fxEl = btn.querySelector('[data-bm-offer-fx="' + offer.offerId + '"]');
        if (fxEl) {
            if (revealed && freshReveal && _snapshot.pending && _snapshot.pending.pairId === pair.pairId) {
                fxEl.innerHTML = '<span class="bm-fx-reveal tone-' + escapeAttr(revealed.direction || "loss")
                    + '"><i class="bm-fx-claw"></i><i class="bm-fx-scan"></i><i class="bm-fx-flash"></i></span>';
            } else if (!revealed) {
                fxEl.innerHTML = "";
            }
        }

        // 徽章层：Lv.10 方向提示 / Lv.8–9 波幅提示 / 揭晓盈亏印章（图形+文字双载体）
        var badgeEl = btn.querySelector('[data-bm-offer-badge="' + offer.offerId + '"]');
        if (badgeEl) {
            if (revealed) {
                var isWin = revealed.direction === "profit";
                badgeEl.innerHTML = '<span class="blackmarket-direction is-revealed '
                    + (isWin ? "profit" : "loss") + '">'
                    + (isWin ? "▲ 脱壳盈利" : "▼ 脱壳亏损") + '</span>';
            } else if (offer.direction) {
                badgeEl.innerHTML = '<span class="blackmarket-direction ' + offer.direction + '">'
                    + (offer.direction === "profit" ? "▲ 回售盈利" : "▼ 回售亏损") + '</span>';
            } else if (offer.spreadBand) {
                badgeEl.innerHTML = '<span class="blackmarket-spread-tag tier-' + escapeAttr(offer.spreadBand.tier) + '">'
                    + '◈ ' + escapeHtml(offer.spreadBand.label) + '</span>';
            } else {
                badgeEl.innerHTML = "";
            }
        }

        var nameEl = btn.querySelector('[data-bm-offer-name="' + offer.offerId + '"]');
        if (nameEl) {
            nameEl.textContent = name;
            nameEl.setAttribute("title", name);
        }

        var subEl = btn.querySelector('[data-bm-offer-sub="' + offer.offerId + '"]');
        if (subEl) {
            if (revealed) {
                subEl.textContent = revealed.realInfo
                    ? "目录 " + formatNumber(revealed.realInfo.catalogPrice)
                        + " · 回售 " + formatNumber(revealed.resellValue) + " TP"
                    : "估值 " + formatNumber(revealed.basePrice)
                        + " · 回售 " + formatNumber(revealed.resellValue) + " TP";
            } else {
                subEl.textContent = offer.hint || "身份封存 · 安全表面";
            }
        }
    }

    function syncBottomRail() {
        if (!_root || !_snapshot) return;
        var rail = _root.querySelector("[data-bm-rail]");
        var main = _root.querySelector("[data-bm-rail-main]");
        if (!rail || !main) return;

        var pending = _snapshot.pending;
        if (pending) {
            var pair = findPair(pending.pairId);
            var offer = pair && findOffer(pair, pending.offerId);
            var revealed = offer && offer.revealed;
            if (revealed) {
                rail.className = "blackmarket-rail reveal " + revealed.direction;
                var breakdown = revealed.payment === "k"
                    ? "+" + formatNumber(revealed.resellValue) + " TP / -"
                        + formatNumber(revealed.paidAmount) + " K"
                    : "+" + formatNumber(revealed.resellValue) + " TP / -"
                        + formatNumber(revealed.paidAmount) + " TP";
                var catalogNote = revealed.realInfo
                    ? "目录 " + formatNumber(revealed.realInfo.catalogPrice)
                    : "估值 " + formatNumber(revealed.basePrice);
                main.innerHTML = [
                    '<div class="bm-rail-summary">',
                        '<div class="bm-rail-title-row">',
                            '<span class="bm-stamp ', revealed.direction, '">',
                                revealed.direction === "profit" ? "▲ 盈利" : "▼ 亏损",
                            '</span>',
                            '<h2>', escapeHtml(revealed.displayName), '</h2>',
                        '</div>',
                        '<p>回售净值 <b>', (revealed.deltaV > 0 ? "+" : ""), formatNumber(revealed.deltaV),
                            ' TP 等值</b> · <small>', escapeHtml(breakdown), ' · ', escapeHtml(catalogNote), '</small></p>',
                    '</div>',
                    '<div class="blackmarket-rail-actions">',
                        '<button type="button" data-bm-action="settle" data-settle="extract" data-focus-key="settle-extract" ',
                            disabledAttr(), '>提取自用<small>离开黑市域</small></button>',
                        '<button class="primary" type="button" data-bm-action="settle" data-settle="resell" data-focus-key="settle-resell" ',
                            disabledAttr(), '>当场回售 +', formatNumber(revealed.resellValue), ' TP<small>换回交易点</small></button>',
                    '</div>'
                ].join("");
                return;
            }
        }

        if (_snapshot.page.complete) {
            rail.className = "blackmarket-rail complete";
            var s = _snapshot.summary || { wins: 0, purchases: 0, skips: 0, pageDeltaV: 0 };
            var hasCredits = _snapshot.balances.supplyCredits > 0;
            var canRaw = _snapshot.balances.rawBoxes > 0;
            main.innerHTML = [
                '<div class="bm-rail-summary">',
                    '<h2>批次 #', _snapshot.page.number, ' 封单复盘 · 命中 ', s.wins, '/', s.purchases,
                        (s.skips ? '（放过 ' + s.skips + '）' : ''), '</h2>',
                    '<p>本批净流动价值 <b class="', s.pageDeltaV >= 0 ? "is-pos" : "is-neg", '">',
                        (s.pageDeltaV >= 0 ? "+" : ""), formatNumber(s.pageDeltaV), ' TP 等值</b> · ',
                        hasCredits
                            ? '剩余补货信用 ' + _snapshot.balances.supplyCredits + '，可整理下一批。'
                            : (canRaw ? '补货信用不足：先上交 1 个毛坯盲盒获取信用与保底 TP。' : '本局补货信用与毛坯已耗尽，可在调试抽屉重开。'),
                    '</p>',
                '</div>',
                '<div class="blackmarket-rail-actions">',
                    (!hasCredits && canRaw)
                        ? '<button type="button" data-bm-action="redeem-rawbox" data-focus-key="rail-rawbox" ' + disabledAttr()
                            + '>交毛坯 +' + formatNumber(BlackMarketCore.RAW_BOX_REDEEM_TP) + ' TP &amp; +1信用</button>'
                        : "",
                    '<button class="primary" type="button" data-bm-action="next-page" data-focus-key="next-page" ',
                        (!hasCredits || _busy ? "disabled" : ""), '>整理下一批（耗1信用）</button>',
                '</div>'
            ].join("");
            return;
        }

        var selectedPair = findPair(_selectedPairId);
        var selectedOffer = selectedPair && findOffer(selectedPair, _selectedOfferId);
        if (selectedPair && selectedOffer && selectedPair.status === "open") {
            rail.className = "blackmarket-rail purchase";
            var sideText = selectedOffer.side === "A" ? "左侧 A" : "右侧 B";
            var payText = _payment === "k"
                ? selectedPair.kCost + " K"
                : formatNumber(selectedPair.counterPriceTp) + " TP";
            var confirmLabel = "以 " + payText + " 脱壳" + (selectedOffer.side === "A" ? "左货" : "右货");
            main.innerHTML = [
                '<div class="blackmarket-payment" role="group" aria-label="支付方式">',
                    paymentButton("tp", formatNumber(selectedPair.counterPriceTp) + " TP", "余额可用"),
                    paymentButton("k", selectedPair.kCost + " K", "向上取整·不找零"),
                '</div>',
                '<div class="blackmarket-rail-actions">',
                    '<button type="button" data-bm-action="inspect-selected" data-pair-id="', escapeAttr(selectedPair.pairId),
                        '" data-offer-id="', escapeAttr(selectedOffer.offerId), '" data-focus-key="inspect" ',
                        (_busy || !surfaceMaster(selectedOffer.offerId) ? "disabled" : ""), '>',
                        (surfaceMaster(selectedOffer.offerId) ? '放大检视 <kbd>V</kbd>' : '扫描准备中'),
                    '</button>',
                    '<button type="button" data-bm-action="cancel" data-focus-key="cancel">取消</button>',
                    '<button class="primary" type="button" data-bm-action="confirm" data-focus-key="confirm" ',
                        (!_preview || _busy ? "disabled" : ""), '>', escapeHtml(confirmLabel),
                        '<small>0', selectedPair.index, '号槽·', sideText, '，另一侧炼雷</small></button>',
                '</div>'
            ].join("");
            return;
        }

        rail.className = "blackmarket-rail idle";
        var covPct = Math.round(_snapshot.mudCoverage * 100);
        var canHandRaw = _snapshot.balances.rawBoxes > 0 && !_busy;
        main.innerHTML = [
            '<div class="bm-rail-idle-meta">',
                '<span class="bm-chip">批次 #', _snapshot.page.number, ' · 余 ', _snapshot.page.openPairs, '/3 槽</span>',
                '<span class="bm-chip">纳米覆壳 ', covPct, '%</span>',
                '<span class="bm-chip">已收藏 ', _snapshot.collectionCount, ' 件</span>',
            '</div>',
            '<div class="blackmarket-rail-actions">',
                '<button type="button" data-bm-action="redeem-rawbox" data-focus-key="rail-rawbox" ',
                    (canHandRaw ? "" : "disabled"), '>交毛坯保底 +', formatNumber(BlackMarketCore.RAW_BOX_REDEEM_TP),
                    ' TP<small>剩余 ', _snapshot.balances.rawBoxes, ' 个·兼+1信用</small></button>',
            '</div>'
        ].join("");
    }

    function paymentButton(kind, label, note) {
        return '<button type="button" class="' + (_payment === kind ? "active" : "") + '" data-bm-action="payment" data-payment="'
            + kind + '" data-focus-key="payment-' + kind + '"><span>' + (kind === "tp" ? "交易点" : "K 点直付")
            + '</span><b>' + escapeHtml(label) + '</b><em>' + escapeHtml(note) + '</em></button>';
    }

    function syncToasts() {
        var host = _root && _root.querySelector("[data-bm-toast-host]");
        if (!host) return;
        if (_error) {
            host.innerHTML = '<div class="blackmarket-error" role="alert"><b>操作被拒绝</b><span>'
                + escapeHtml(_error) + '</span><button type="button" data-bm-action="dismiss-error" data-focus-key="dismiss-error" aria-label="关闭提示">×</button></div>';
        } else if (_notice) {
            host.innerHTML = '<div class="blackmarket-error is-info" role="status"><b>工坊通联</b><span>'
                + escapeHtml(_notice) + '</span></div>';
        } else {
            host.innerHTML = "";
        }
    }

    function syncLiveRegion(options) {
        var live = _root && _root.querySelector("[data-bm-live]");
        if (!live || !options || !options.announce) return;
        live.textContent = options.announce;
    }

    // ── 表面水合（支持实时装备纸娃娃/武器本体渲染 + 全量与单件精准重绘）──
    function ensureSurfaceRenderer() {
        if (_surfaceRenderer || typeof BlackMarketItemSurface === "undefined") return _surfaceRenderer;
        _surfaceRenderer = BlackMarketItemSurface.createRenderer({
            workerUrl: resolveUrl("modules/minigames/blackmarket/visual/item-surface-worker.js"),
            cacheLimit: 42
        });
        return _surfaceRenderer;
    }

    function ensureEquipmentPreview() {
        if (_equipmentPreview || typeof BlackMarketEquipmentPreview === "undefined") return _equipmentPreview;
        _equipmentPreview = BlackMarketEquipmentPreview.create({ cacheLimit: 24, size: 512 });
        return _equipmentPreview;
    }

    function hasLiveEquipmentRuntime() {
        return !!ensureEquipmentPreview()
            && typeof MercPortraits !== "undefined"
            && typeof MercPortraits.loadManifest === "function"
            && typeof MercPortraits.renderStateDataUrl === "function"
            && typeof EquipmentInspector !== "undefined"
            && typeof EquipmentInspector.resolveProductSource === "function"
            && typeof EquipmentInspector.buildStateForSource === "function";
    }

    // 武器与防具若回退到图标帧，优先采用透明底 _2（完整掉落本体）而非 _1（商店裁切特写）
    function preferredDropSurface(entry, visual) {
        var isEquip = entry && (entry.t === "武器" || entry.t === "防具");
        if (isEquip && entry.f && /_2\.(webp|png)$/.test(entry.f)) {
            return {
                assetUrl: entry.f,
                fallbackAssetUrl: visual.assetUrl,
                sourceMaskMode: "source",
                fallbackSourceMaskMode: visual.sourceMaskMode || "proxy",
                sharpenSource: false,
                sourceKind: "icon",
                sourceComposition: "drop-item-frame"
            };
        }
        return {
            assetUrl: visual.assetUrl,
            fallbackAssetUrl: visual.fallbackAssetUrl || null,
            sourceMaskMode: visual.sourceMaskMode || visual.hiddenColorMode || "proxy",
            fallbackSourceMaskMode: visual.fallbackSourceMaskMode || "monochrome",
            sharpenSource: visual.sharpenSource === true,
            sourceKind: visual.sourceKind || "icon",
            sourceComposition: visual.sourceComposition || null
        };
    }

    function buildEquipmentSource(entry, visual, drop) {
        if (!entry) return null;
        if (entry.t === "武器" && WEAPON_USES[entry.sc]) {
            return {
                kind: "dressup-weapon",
                itemId: visual.sourceKey,
                itemName: entry.k || entry.n,
                use: entry.sc,
                actionType: entry.at || "",
                assetUri: drop.assetUrl,
                assetKind: "dressup-weapon"
            };
        }
        if (entry.t === "防具" && ARMOR_SLOT_BY_USE[entry.sc]) {
            return {
                kind: "dressup-paperdoll",
                itemId: visual.sourceKey,
                itemName: entry.k || entry.n,
                slot: ARMOR_SLOT_BY_USE[entry.sc],
                use: entry.sc,
                actionType: entry.at || "",
                assetUri: drop.assetUrl,
                assetKind: "dressup-paperdoll"
            };
        }
        return null;
    }

    function buildIconRenderPlan(visual, drop) {
        return {
            assetUrl: resolveAssetUrl(drop.assetUrl),
            fallbackAssetUrl: drop.fallbackAssetUrl ? resolveAssetUrl(drop.fallbackAssetUrl) : null,
            fallbackHiddenColorMode: visual.fallbackHiddenColorMode || "monochrome",
            fallbackSourceMaskMode: drop.fallbackSourceMaskMode || "monochrome",
            sourceMaskMode: drop.sourceMaskMode,
            sourceKey: visual.sourceKey + (drop.assetUrl !== visual.assetUrl ? ":f2" : ""),
            sourceKind: drop.sourceKind,
            sourceComposition: drop.sourceComposition,
            focusFitFieldCount: 0,
            focusDrawFieldCount: 0,
            previewGender: visual.previewGender || "neutral",
            autoRotate: visual.autoRotate,
            paddingRatio: 0.065,
            sharpenSource: drop.sharpenSource
        };
    }

    function pairPreferredGender(pair) {
        var h = typeof BlackMarketCore !== "undefined" && typeof BlackMarketCore.hash32 === "function"
            ? BlackMarketCore.hash32(pair && pair.pairId ? pair.pairId : "") : 0;
        return (h & 1) ? "女" : "男";
    }

    function resolvePairGenderFor(pair, pairGenderPromises) {
        if (pairGenderPromises[pair.pairId]) return pairGenderPromises[pair.pairId];
        var preferred = pairPreferredGender(pair);
        if (!hasLiveEquipmentRuntime() || !pair || !Array.isArray(pair.offers)) {
            pairGenderPromises[pair.pairId] = Promise.resolve(preferred);
            return pairGenderPromises[pair.pairId];
        }
        var armorSources = [];
        for (var i = 0; i < pair.offers.length; i += 1) {
            try {
                var vis = _session.surface.resolveSurface(pair.offers[i].visualHandle);
                var ent = poolEntryByUri()[vis.assetUrl] || null;
                var src = buildEquipmentSource(ent, vis, preferredDropSurface(ent, vis));
                if (src && src.kind === "dressup-paperdoll") armorSources.push(src);
            } catch (ignored) {}
        }
        if (!armorSources.length) {
            pairGenderPromises[pair.pairId] = Promise.resolve(preferred);
            return pairGenderPromises[pair.pairId];
        }
        var preview = ensureEquipmentPreview();
        pairGenderPromises[pair.pairId] = preview.resolvePairGender(armorSources, { gender: preferred })
            .catch(function() { return preferred; });
        return pairGenderPromises[pair.pairId];
    }

    function resolveOfferVisualPlan(pair, visual, pairGenderPromises) {
        var entry = poolEntryByUri()[visual.assetUrl] || null;
        var drop = preferredDropSurface(entry, visual);
        var fallbackPlan = buildIconRenderPlan(visual, drop);
        var equipSource = buildEquipmentSource(entry, visual, drop);
        if (!equipSource || !hasLiveEquipmentRuntime()) {
            return Promise.resolve(fallbackPlan);
        }
        var preview = ensureEquipmentPreview();
        var genderPromise = equipSource.kind === "dressup-paperdoll"
            ? resolvePairGenderFor(pair, pairGenderPromises)
            : Promise.resolve("男");

        function tryResolve(gender) {
            return preview.resolve(equipSource, { gender: gender });
        }

        return genderPromise.then(function(gender) {
            return tryResolve(gender).catch(function(err) {
                if (equipSource.kind === "dressup-paperdoll") {
                    return tryResolve(gender === "男" ? "女" : "男");
                }
                throw err;
            });
        }).then(function(resolved) {
            if (!resolved || (resolved.kind !== "dressup-paperdoll" && resolved.kind !== "dressup-weapon")
                    || !resolved.assetUrl) {
                return fallbackPlan;
            }
            return {
                assetUrl: resolved.assetUrl,
                fallbackAssetUrl: resolveAssetUrl(drop.assetUrl),
                fallbackHiddenColorMode: "monochrome",
                fallbackSourceMaskMode: drop.sourceMaskMode || "proxy",
                sourceMaskMode: "source",
                sourceKey: resolved.sourceKey,
                sourceKind: resolved.sourceKind,
                sourceComposition: resolved.sourceComposition || null,
                focusFitFieldCount: Array.isArray(resolved.focusFitFields) ? resolved.focusFitFields.length : 0,
                focusDrawFieldCount: Array.isArray(resolved.focusDrawFields) ? resolved.focusDrawFields.length : 0,
                previewGender: resolved.previewGender || "neutral",
                autoRotate: resolved.autoRotate,
                paddingRatio: 0.035,
                sharpenSource: false
            };
        }).catch(function() {
            return fallbackPlan;
        });
    }

    function scheduleSurfaceHydration(forceAll) {
        if (!_panelOpen || !_snapshot || !_root) return;
        var pageGen = ++_surfaceGeneration;
        _offerSurfaceGen = {};
        var run = function() {
            if (!_panelOpen || pageGen !== _surfaceGeneration) return;
            hydrateSurfaces(pageGen, null, null, forceAll);
        };
        if (typeof requestAnimationFrame === "function") requestAnimationFrame(run);
        else setTimeout(run, 0);
    }

    // 单件揭晓重绘仅递增该 offer 的独立代数，不打断同批其他槽位正在进行的纸娃娃/污泥渲染
    function scheduleSingleOfferHydration(offerId) {
        if (!_panelOpen || !_snapshot || !_root || !offerId) return;
        var pageGen = _surfaceGeneration;
        var offerGen = (_offerSurfaceGen[offerId] || 0) + 1;
        _offerSurfaceGen[offerId] = offerGen;
        var run = function() {
            if (!_panelOpen || pageGen !== _surfaceGeneration
                    || offerGen !== _offerSurfaceGen[offerId]) return;
            hydrateSurfaces(pageGen, offerId, offerGen, true);
        };
        if (typeof requestAnimationFrame === "function") requestAnimationFrame(run);
        else setTimeout(run, 0);
    }

    function hydrateSurfaces(pageGen, targetOfferId, targetOfferGen, force) {
        var renderer = ensureSurfaceRenderer();
        if (!renderer || !_root || !_snapshot || !_session || !_session.surface) return;
        var selector = targetOfferId
            ? '[data-bm-surface="' + targetOfferId + '"]'
            : "[data-bm-surface]";
        var canvases = _root.querySelectorAll(selector);
        for (var i = 0; i < canvases.length; i += 1) {
            (function(canvas) {
                var offerId = canvas.getAttribute("data-bm-surface");
                var located = findSnapshotOffer(offerId);
                if (!located) return;
                // 若整页水合 rAF 触发前，某件已被单件揭晓抢先接管，则跳过该件，避免覆盖最新揭晓态
                if (!targetOfferId && _offerSurfaceGen[offerId]) return;
                var offerGen = targetOfferId ? targetOfferGen : 1;
                if (!targetOfferId) _offerSurfaceGen[offerId] = offerGen;
                var pair = located.pair;
                var offer = located.offer;
                var desiredStateKey = _snapshot.page.id + "|" + _snapshot.decryptLevel + "|" + offer.visualState;
                if (!force && _hydratedSurfaceState[offerId] === desiredStateKey) return;
                var surface = offer.surface || {};
                var isAlive = function() {
                    return _panelOpen
                        && pageGen === _surfaceGeneration
                        && offerGen === _offerSurfaceGen[offerId]
                        && !!_root
                        && _root.contains(canvas);
                };
                var source;
                try {
                    source = _session.surface.resolveSurface(offer.visualHandle);
                } catch (error) {
                    failSurfaceClosed(canvas, error, isAlive);
                    return;
                }
                Promise.resolve(source).then(function(visual) {
                    if (!isAlive()) return null;
                    var surfaceSeed = visual.seed;
                    return resolveOfferVisualPlan(pair, visual, _pairGenderPromises).then(function(plan) {
                        if (!isAlive()) return null;
                        var asset = canvas.closest(".blackmarket-asset");
                        if (asset) {
                            asset.classList.remove("source-dressup-paperdoll", "source-dressup-weapon", "is-sharpened-proxy");
                            if (plan.sourceKind === "dressup-paperdoll") asset.classList.add("source-dressup-paperdoll");
                            if (plan.sourceKind === "dressup-weapon") asset.classList.add("source-dressup-weapon");
                            if (plan.sharpenSource) asset.classList.add("is-sharpened-proxy");
                        }
                        return renderer.render(canvas, {
                            offerId: offer.offerId,
                            assetUrl: plan.assetUrl,
                            fallbackAssetUrl: plan.fallbackAssetUrl,
                            fallbackHiddenColorMode: plan.fallbackHiddenColorMode,
                            fallbackSourceMaskMode: plan.fallbackSourceMaskMode,
                            sourceMaskMode: plan.sourceMaskMode,
                            sourceKey: plan.sourceKey,
                            sourceKind: plan.sourceKind,
                            sourceComposition: plan.sourceComposition,
                            focusFitFieldCount: plan.focusFitFieldCount,
                            focusDrawFieldCount: plan.focusDrawFieldCount,
                            previewGender: plan.previewGender,
                            seed: surfaceSeed,
                            coverage: Number(surface.targetCoverage === undefined ? _snapshot.mudCoverage : surface.targetCoverage),
                            mud: offer.visualState === "available",
                            hiddenColorMode: offer.visualState === "revealed"
                                ? "source" : BlackMarketCore.HIDDEN_COLOR_MODE,
                            autoRotate: plan.autoRotate,
                            paddingRatio: plan.paddingRatio,
                            renderWidth: SURFACE_MASTER_WIDTH,
                            renderHeight: SURFACE_MASTER_HEIGHT,
                            // 揭晓后的干净展示：保留源半透边缘（不修边锯齿），且不再叠加低清锐化
                            preserveSourceAlpha: offer.visualState === "revealed",
                            sharpenSource: offer.visualState === "revealed" ? false : plan.sharpenSource === true,
                            sharpenStrength: 0.18,
                            debug: false,
                            onComplete: function(metrics, completedCanvas) {
                                if (!isAlive() || !_root.contains(completedCanvas)) return;
                                metrics.surfaceSeed = surfaceSeed;
                                _surfaceMetrics[offer.offerId] = metrics;
                                _hydratedSurfaceState[offer.offerId] = desiredStateKey;
                                rememberSurfaceMaster(offer.offerId, completedCanvas, metrics);
                                var completedAsset = completedCanvas.closest(".blackmarket-asset");
                                if (completedAsset) completedAsset.classList.add("is-surface-ready");
                                paintSurfaceReadout(offer.offerId, metrics);
                                paintParityMetric();
                                paintInspectionAvailability(offer.offerId);
                            }
                        });
                    });
                }).catch(function(error) {
                    failSurfaceClosed(canvas, error, isAlive);
                });
            })(canvases[i]);
        }
    }

    function failSurfaceClosed(canvas, error, isAlive) {
        if (error && error.name === "AbortError") return;
        if (typeof isAlive === "function" ? !isAlive() : (!_panelOpen || !_root || !_root.contains(canvas))) return;
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
            shellKey: _mountedShellKey
        };
    }

    function surfaceMaster(offerId) {
        var master = _surfaceMasters[offerId];
        return master && master.shellKey === _mountedShellKey ? master : null;
    }

    function paintInspectionAvailability(offerId) {
        if (!_root) return;
        if (offerId) {
            var pin = _root.querySelector('.blackmarket-inspect-pin[data-offer-id="' + offerId + '"]');
            var located = findSnapshotOffer(offerId);
            if (pin && located) {
                pin.disabled = _busy || !!_snapshot.pending || located.pair.status !== "open"
                    || located.offer.visualState !== "available" || !surfaceMaster(offerId);
            }
        }
        if (!_selectedOfferId) return;
        var button = _root.querySelector('[data-bm-action="inspect-selected"]');
        if (!button) return;
        var ready = !!surfaceMaster(_selectedOfferId);
        button.disabled = _busy || !ready;
        button.innerHTML = ready ? '放大检视 <kbd>V</kbd>' : "扫描准备中";
    }

    function paintSurfaceReadout(offerId, metrics) {
        if (!_root) return;
        var nodes = _root.querySelectorAll("[data-bm-surface-readout]");
        var sourceLabel = metrics.sourceKind === "dressup-paperdoll" ? "纸娃娃局部聚焦"
            : (metrics.sourceKind === "dressup-weapon" ? "完整武器本体"
                : (metrics.sourceComposition === "drop-item-frame" ? "掉落本体帧"
                    : (metrics.sourceSharpening === "alpha-safe-unsharp" ? "保边锐化代理" : "图标源")));
        for (var i = 0; i < nodes.length; i += 1) {
            if (nodes[i].getAttribute("data-bm-surface-readout") !== offerId) continue;
            nodes[i].textContent = "";
            nodes[i].setAttribute("title", "SDF " + metrics.sdfMaxInsidePx + "px · "
                + metrics.maskSource + " · " + metrics.materialProfile + " · " + metrics.backend
                + " · " + sourceLabel);
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
        return readyPairs ? "左右覆壳差 ≤ " + formatPercent(maximum) + " · " + readyPairs + "/3 槽" : "实测覆盖待计算";
    }

    function paintParityMetric() {
        if (!_root) return;
        var node = _root.querySelector("[data-bm-parity]");
        if (node) node.textContent = parityMetricText();
    }

    function formatPercent(value) {
        return (Number(value || 0) * 100).toFixed(1) + "%";
    }

    // ── 抽屉（说明 / 50:1 兑K / 调试参数与工程遥测）────────────────
    function syncDrawerHost(options) {
        var host = _root && _root.querySelector("[data-bm-drawer-host]");
        if (!host) return;
        if (!_drawer) {
            if (host.innerHTML) host.innerHTML = "";
            return;
        }
        if (options && options.keepDrawer && host.innerHTML) return;
        if (_drawer === "debug") host.innerHTML = renderDebugDrawer();
        else if (_drawer === "exchange") host.innerHTML = renderExchangeDrawer();
        else host.innerHTML = renderHelpDrawer();
    }

    function renderHelpDrawer() {
        return '<div class="blackmarket-overlay"><aside class="blackmarket-drawer" role="dialog" aria-modal="true" aria-label="工坊脱壳说明">'
            + '<header><span>PROSTHETIC IMMORTAL · MANUAL</span><button type="button" data-bm-action="close-drawer" data-focus-key="close-drawer" aria-label="关闭">×</button></header>'
            + '<h2>终结者合成台 · 脱壳作业说明</h2><ol>'
            + '<li><b>为什么二选一</b>：灰色事件残余纳米机器人在强化石能量源点蛰伏成封壳。合成台利用两件同型封件的纳米群共振，将纳米机器人全数引流到牺牲件内炼成爆弹，另一件则安全脱壳。</li>'
            + '<li><b>保底与博弈双轨</b>：未清洗毛坯可直接上交假肢仙人换取固定交易点（50:1 兑 K 点）与补货信用；进台配对脱壳可凭眼力与解密等级搏取更高差价或自用装备。</li>'
            + '<li><b>脱壳后二选一</b>：揭晓后必须立即选择“提取自用”或“当场回售”；结算后另一侧防爆闸门将显示牺牲体爆弹残片读数，便于复盘长眼力。</li>'
            + '<li><b>解密 0–10 级</b>：0–5 级逐步剥离纳米表层；6–7 级探查耦合信号；8–9 级显示价差波幅；10 级锁定脱壳盈亏方向。</li></ol>'
            + '<p class="blackmarket-help-keys"><b>快捷键</b>：方向键浏览货包 · 双击或 <kbd>V</kbd> 放大检视 · 检视台内 <kbd>R</kbd> 旋转 / <kbd>A</kbd><kbd>D</kbd> 切侧 · <kbd>S</kbd> 两击放过当前槽 · <kbd>Esc</kbd> 关闭浮层</p>'
            + '<p class="warning">当前为匿名影子测试渠道（shadowOnly）：不读写正式背包、正式货币与主存档。</p>'
            + '</aside></div>';
    }

    function renderExchangeDrawer() {
        var b = _snapshot.balances;
        var maxK = Math.floor(b.tradePoints / BlackMarketCore.TP_PER_K);
        var remainder = b.tradePoints % BlackMarketCore.TP_PER_K;
        var quick = [10, 50, 100, maxK].filter(function(val, idx, arr) {
            return val > 0 && val <= maxK && arr.indexOf(val) === idx;
        });
        var btns = quick.length
            ? quick.map(function(amt) {
                var label = amt === maxK ? "全部可兑 +" + formatNumber(amt) + " K" : "+" + formatNumber(amt) + " K";
                return '<button type="button" data-bm-action="redeem-k" data-k-amount="' + amt
                    + '" ' + (_busy || !!_snapshot.pending ? "disabled" : "") + '>'
                    + escapeHtml(label) + ' <small>耗 ' + formatNumber(amt * 50) + ' TP</small></button>';
            }).join("")
            : '<p class="blackmarket-lab-empty">当前交易点不足 50 TP，暂不可兑换整 K 点。可先上交毛坯或脱壳回售获取交易点。</p>';
        return '<div class="blackmarket-overlay"><aside class="blackmarket-drawer" role="dialog" aria-modal="true" aria-label="交易点兑换 K 点">'
            + '<header><span>50 TP → 1 K · ONE-WAY EXCHANGE</span><button type="button" data-bm-action="close-drawer" data-focus-key="close-drawer" aria-label="关闭">×</button></header>'
            + '<h2>交易点单向兑换 K 点</h2>'
            + '<dl><dt>当前交易点</dt><dd>' + formatNumber(b.tradePoints) + ' TP</dd>'
            + '<dt>当前 K 点</dt><dd>' + formatNumber(b.kPoints) + ' K</dd>'
            + '<dt>最多可兑</dt><dd>' + formatNumber(maxK) + ' K（余 ' + remainder + ' TP 保留不吞）</dd></dl>'
            + '<h3>快捷整额兑换（ΔV = 0）</h3>'
            + '<div class="blackmarket-exchange-grid">' + btns + '</div>'
            + '<p class="blackmarket-debug-note">单向兑换不可逆；普通背包物品与金币不可换取交易点。</p>'
            + '</aside></div>';
    }

    function renderDebugDrawer() {
        var b = _snapshot.balances;
        var stats = _snapshot.catalog;
        var levels = BlackMarketCore.LEVELS.map(function(level) {
            var cov = Math.round((BlackMarketCore.COVERAGE_BY_LEVEL[level] || 0) * 100);
            return '<option value="' + level + '"'
                + (_snapshot.decryptLevel === level ? " selected" : "") + '>Lv.' + level
                + '（纳米覆壳 ' + cov + '%）</option>';
        }).join("");
        return '<div class="blackmarket-overlay"><aside class="blackmarket-drawer" role="dialog" aria-modal="true" aria-label="黑市调试抽屉">'
            + '<header><span>SHADOW DEBUG &amp; TELEMETRY</span><button type="button" data-bm-action="close-drawer" data-focus-key="close-drawer" aria-label="关闭">×</button></header>'
            + '<h2>会话参数（影子重开）</h2>'
            + '<div class="blackmarket-debug-grid">'
            + '<label>解密等级（0–10 级全梯度）<select data-bm-field="decryptLevel">' + levels + '</select></label>'
            + '<label>TP 余额<input type="number" min="0" step="1000" data-bm-field="tradePoints" value="' + b.tradePoints + '"></label>'
            + '<label>K 余额<input type="number" min="0" step="100" data-bm-field="kPoints" value="' + b.kPoints + '"></label>'
            + '<label>补货信用<input type="number" min="0" step="1" data-bm-field="supplyCredits" value="' + b.supplyCredits + '"></label>'
            + '</div>'
            + '<div class="blackmarket-drawer-actions">'
            + '<button type="button" data-bm-action="debug-apply" data-focus-key="debug-apply">应用并重开</button>'
            + '<button type="button" data-bm-action="debug-reset" data-focus-key="debug-reset">恢复默认</button>'
            + '</div>'
            + '<h3>算法与覆盖率遥测（开发观测）</h3>'
            + '<dl class="blackmarket-visual-metrics">'
            + '<dt>算法版本</dt><dd>' + escapeHtml(_snapshot.algorithmVersion) + '</dd>'
            + '<dt>覆盖目标</dt><dd>' + Math.round(_snapshot.mudCoverage * 100) + '%</dd>'
            + '<dt>实测奇偶</dt><dd data-bm-parity>' + escapeHtml(parityMetricText()) + '</dd>'
            + '<dt>影子夹具</dt><dd>' + stats.mechanicallyRenderable + ' / ' + stats.totalItems + ' · ' + escapeHtml(shortDigest(stats.digest)) + '</dd>'
            + '</dl>'
            + '<p class="blackmarket-debug-note">应用 = 以新参数重开匿名影子会话（当前页进度丢弃）。不写正式存档；目录/身份/视觉池不在可调范围。</p>'
            + '</aside></div>';
    }

    function readDebugOptions(defaults) {
        var options = defaults || {};
        var fields = _root.querySelectorAll("[data-bm-field]");
        for (var index = 0; index < fields.length; index += 1) {
            var field = fields[index];
            var key = field.getAttribute("data-bm-field");
            var value = Number(field.value);
            if (!isFinite(value) || value < 0) throw new Error("调试参数非法：" + key);
            if (key === "decryptLevel" && BlackMarketCore.LEVELS.indexOf(value) < 0) {
                throw new Error("解密等级非法");
            }
            options[key] = Math.floor(value);
        }
        return options;
    }

    function restartSession(options) {
        _session = BlackMarketCore.createShadowSession(options);
        _snapshot = _session.product.open();
        _prevBalances = cloneBalances(_snapshot.balances);
        _selectedPairId = null;
        _selectedOfferId = null;
        _payment = "tp";
        _preview = null;
        _busy = false;
        _error = null;
        _notice = null;
        _fxRevealKey = null;
        _fxShutterPlayed = {};
        clearSkipArmTimer();
        setT800State("boot", "center", "台面参数已重载，解密协议 Lv." + _snapshot.decryptLevel + "，新一轮三槽就位。", true);
        notifyHost("debug-restart", sessionTelemetry());
        render({ full: true });
    }

    function applyDebugOptions(options) {
        try {
            restartSession(readDebugOptions(options || {}));
        } catch (error) {
            _error = error && error.message ? error.message : String(error);
            render();
        }
    }

    // ── 放大检视台（单件聚焦 + A/B 并排对照）───────────────────────
    function syncInspectionHost(options) {
        var host = _root && _root.querySelector("[data-bm-inspection-host]");
        if (!host) return;
        if (!_inspection) {
            destroyInspectionCamera();
            if (host.innerHTML) host.innerHTML = "";
            return;
        }
        if (options && options.keepInspection && host.innerHTML) return;
        destroyInspectionCamera();
        host.innerHTML = renderInspection();
        mountInspection();
    }

    function renderInspection() {
        if (!_inspection) return "";
        var pair = findPair(_inspection.pairId);
        var offer = pair && findOffer(pair, _inspection.offerId);
        var master = offer && surfaceMaster(offer.offerId);
        if (!pair || !offer || !master) return "";

        var compareMode = _inspection.mode === "compare";
        var bothReady = pair.offers.every(function(c) {
            return !!surfaceMaster(c.offerId) && c.visualState === "available";
        });
        var sideButtons = pair.offers.map(function(candidate) {
            var ready = !!surfaceMaster(candidate.offerId) && candidate.visualState === "available";
            return '<button type="button" data-bm-action="inspection-side" data-pair-id="'
                + escapeAttr(pair.pairId) + '" data-offer-id="' + escapeAttr(candidate.offerId)
                + '" data-focus-key="inspection-side-' + escapeAttr(candidate.offerId) + '" '
                + (ready ? "" : "disabled") + ' aria-pressed="'
                + (!compareMode && candidate.offerId === offer.offerId ? "true" : "false") + '">'
                + (candidate.side === "A" ? "左侧 / A" : "右侧 / B") + '</button>';
        }).join("");
        var compareBtn = '<button type="button" data-bm-action="inspection-compare" data-focus-key="inspection-compare" '
            + (bothReady ? "" : "disabled") + ' aria-pressed="' + (compareMode ? "true" : "false")
            + '">A | B 并排对照</button>';

        var sourceLabel = inspectionSourceLabel(master.metrics);
        var title = "0" + pair.index + "号槽 · " + (compareMode ? "A / B 并排对照" : (offer.side === "A" ? "左侧 A" : "右侧 B"))
            + " · 匿名安全检视";

        var bodyHtml = compareMode
            ? '<div class="blackmarket-inspection-compare" data-bm-inspection-compare>'
                + '<div class="bm-compare-pane"><span>左侧 / A</span><canvas data-bm-compare-canvas="A" width="1" height="1" aria-hidden="true"></canvas></div>'
                + '<div class="bm-compare-pane"><span>右侧 / B</span><canvas data-bm-compare-canvas="B" width="1" height="1" aria-hidden="true"></canvas></div>'
                + '<span class="bm-scan-hud" aria-hidden="true"><i class="bm-hud-corners"></i><i class="bm-hud-sweep"></i></span>'
                + '</div>'
            : '<div class="blackmarket-inspection-viewport" data-bm-inspection-viewport tabindex="0" '
                + 'aria-label="' + escapeAttr(title + "覆泥证据，可拖拽与滚轮缩放") + '">'
                + '<div class="blackmarket-inspection-stage" data-bm-inspection-stage>'
                + '<canvas data-bm-inspection-canvas width="1" height="1" aria-hidden="true"></canvas></div>'
                + '<span class="bm-scan-hud" aria-hidden="true"><i class="bm-hud-v"></i><i class="bm-hud-h"></i>'
                + '<i class="bm-hud-corners"></i><i class="bm-hud-sweep"></i></span></div>';

        return '<div class="blackmarket-inspection-overlay"><section class="blackmarket-inspection-dialog" '
            + 'role="dialog" aria-modal="true" aria-labelledby="blackmarket-inspection-title">'
            + '<header><div><span>SEALED EVIDENCE / APPRAISAL SCANNER</span><h2 id="blackmarket-inspection-title">'
            + escapeHtml(title) + '</h2></div><button type="button" data-bm-action="close-inspection" '
            + 'data-focus-key="close-inspection" aria-label="关闭放大检视">×</button></header>'
            + '<div class="blackmarket-inspection-switch" role="group" aria-label="切换同舱检视侧">'
            + sideButtons + compareBtn + '</div>'
            + bodyHtml
            + '<footer><div class="blackmarket-inspection-evidence"><b>' + escapeHtml(sourceLabel)
            + '</b><span>只放大同一份覆泥证据；不会降低覆盖或重新生成破局点。</span></div>'
            + '<div class="blackmarket-inspection-toolbar"><div data-bm-inspection-controls></div>'
            + '<button type="button" data-bm-action="inspection-rotate" data-focus-key="inspection-rotate">旋转 90° <kbd>R</kbd></button>'
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
        if (_inspection.mode === "compare") {
            var pair = findPair(_inspection.pairId);
            if (!pair) return;
            var canvasA = _root.querySelector('[data-bm-compare-canvas="A"]');
            var canvasB = _root.querySelector('[data-bm-compare-canvas="B"]');
            var masterA = surfaceMaster(pair.offers[0].offerId);
            var masterB = surfaceMaster(pair.offers[1].offerId);
            if (canvasA && masterA) paintInspectionCanvas(canvasA, masterA.canvas, _inspection.rotation || 0);
            if (canvasB && masterB) paintInspectionCanvas(canvasB, masterB.canvas, _inspection.rotation || 0);
            return;
        }
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
            sourceWidth: master.canvas.width,
            sourceHeight: master.canvas.height,
            objectBounds: master.metrics && master.metrics.objectBounds,
            envelopeRadiusPx: master.metrics && master.metrics.envelopeRadiusPx,
            rotation: _inspection.rotation || 0,
            viewportWidth: viewport.clientWidth,
            viewportHeight: viewport.clientHeight,
            canvasRatio: 0.88,
            fillRatio: 0.72,
            maxZoom: INSPECTION_MAX_ZOOM
        });
        _inspection.focus = focus;
        var initialZoom = _inspection.preservedZoom && _inspection.preservedZoom >= 1
            ? Math.min(INSPECTION_MAX_ZOOM, _inspection.preservedZoom) : focus.zoom;
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
            defaultZoom: initialZoom,
            zoomStep: 0.2,
            panStep: 38,
            fitLabel: "全貌",
            resetLabel: "聚焦",
            onChange: function(state) {
                if (_inspection && state && Number.isFinite(state.zoom)) {
                    _inspection.preservedZoom = state.zoom;
                }
            },
            resetOffset: function(zoom) {
                if (Math.abs(zoom - focus.fitZoom) < 0.001) return { panX: 0, panY: 0 };
                return { panX: focus.offsetX * zoom, panY: focus.offsetY * zoom };
            },
            panBounds: function(state) {
                return {
                    x: Math.abs(focus.offsetX) * state.zoom + viewport.clientWidth * 0.5,
                    y: Math.abs(focus.offsetY) * state.zoom + viewport.clientHeight * 0.5
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
        hideOfferTip();
        _drawer = null;
        _drawerOpenerKey = null;
        _inspection = {
            pairId: pairId,
            offerId: offerId,
            mode: "single",
            rotation: 0,
            preservedZoom: null,
            openerKey: opener && opener.getAttribute ? opener.getAttribute("data-focus-key") : null
        };
        setT800State("inspect", lookForPair(pair.index), pickLine("inspect"), true);
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
        render({ focusKey: openerKey });
    }

    function switchInspection(pairId, offerId) {
        if (!_inspection || _inspection.pairId !== pairId || !surfaceMaster(offerId)) return;
        _inspection.mode = "single";
        _inspection.offerId = offerId;
        notifyFx("fx-select");
        render();
    }

    function toggleInspectionCompare() {
        if (!_inspection) return;
        _inspection.mode = _inspection.mode === "compare" ? "single" : "compare";
        notifyFx("fx-select");
        render();
    }

    function rotateInspection() {
        if (!_inspection || !_root) return;
        _inspection.rotation = ((_inspection.rotation || 0) + 90) % 360;
        notifyFx("fx-scan-rotate");
        if (_inspection.mode === "compare") {
            mountInspection();
        } else {
            destroyInspectionCamera();
            mountInspection();
            var viewport = _root.querySelector("[data-bm-inspection-viewport]");
            if (viewport) {
                viewport.classList.remove("is-detent");
                void viewport.offsetWidth;
                viewport.classList.add("is-detent");
            }
        }
        var output = _root.querySelector("[data-bm-inspection-rotation]");
        if (output) output.textContent = "当前旋转 " + _inspection.rotation + "°";
    }

    function destroyInspectionCamera() {
        if (_inspectionCamera && _inspectionCamera.destroy) _inspectionCamera.destroy();
        _inspectionCamera = null;
    }

    // ── 舱液气泡环境层（唯一常驻低能耗环境循环）───────────────────
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
        var rngState = 0x9e3779b9;
        var rand = function() {
            rngState = (Math.imul(rngState, 1664525) + 1013904223) >>> 0;
            return rngState / 4294967296;
        };
        var bubbles = [];
        var count = Math.max(12, Math.min(24, Math.round(width / 42)));
        for (var index = 0; index < count; index += 1) {
            bubbles.push({
                x: rand() * width,
                y: rand() * height,
                r: 1.1 + rand() * 2.8,
                speed: 7 + rand() * 14,
                phase: rand() * 6.2832,
                wobble: 0.35 + rand() * 0.9
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
                var x = bubble.x + Math.sin(bubble.phase) * 2.5;
                context.beginPath();
                context.arc(x, bubble.y, bubble.r, 0, 6.2832);
                context.fillStyle = "rgba(178, 240, 232, 0.09)";
                context.fill();
                context.beginPath();
                context.arc(x - bubble.r * 0.35, bubble.y - bubble.r * 0.35, bubble.r * 0.32, 0, 6.2832);
                context.fillStyle = "rgba(255, 255, 255, 0.20)";
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

    // ── hover / 键盘聚焦属性预览（注释释放）───────────────────────
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

    var TIP_OWNER = "blackmarket-offer-tip";
    var _tipOfferId = null;
    var _tipReqSeq = 0;
    var _tipRequests = {};
    var _tipBridgeBound = false;

    function buildAnonTipHtml(entry) {
        return '<div class="bm-ann bm-ann-anon"><b>未鉴定货物</b><br>'
            + (entry ? '<span class="bm-ann-tax">特征分类 · ' + escapeHtml((entry.t || "物品")
                + (entry.sc ? " / " + entry.sc : "")) + '</span><br>' : "")
            + '<span class="bm-ann-note">覆泥下可见特征点；脱壳后释放完整注释（双击或 V 放大）</span></div>';
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
        if (rich && rich.document != null) richOpts.document = rich.document;
        return '<div class="bm-ann-rich-wrap">' + PanelTooltip.buildItemRichHtml(richOpts) + '</div>';
    }

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
                descHTML: typeof data.descHTML === "string" ? data.descHTML : "",
                document: data.document
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
        // 未揭晓时向下定位：既不挡同舱右侧 B 卡对比视野，也不顶盖顶栏主标题
        var anchorOpts = {
            owner: TIP_OWNER,
            autoClose: 0,
            outsideClick: false,
            placement: revealed ? "right" : "bottom"
        };
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

    function handleTipFocusIn(event) {
        var offerEl = event.target.closest ? event.target.closest(".blackmarket-offer") : null;
        if (!offerEl || !_el.contains(offerEl)) return;
        showOfferTip(offerEl);
    }

    function handleTipFocusOut(event) {
        var offerEl = event.target.closest ? event.target.closest(".blackmarket-offer") : null;
        if (!offerEl) return;
        hideOfferTip();
    }

    // ── 输入与业务交互 ───────────────────────────────────────────
    function lookForPair(pairIndex) {
        if (pairIndex === 1) return "left";
        if (pairIndex === 3) return "right";
        return "center";
    }

    function handleDblClick(event) {
        var offerEl = event.target.closest && event.target.closest(".blackmarket-offer");
        if (!offerEl || !_el.contains(offerEl) || !_snapshot || _busy || _snapshot.pending) return;
        openInspection(offerEl.getAttribute("data-pair-id"), offerEl.getAttribute("data-offer-id"), offerEl);
    }

    function handleClick(event) {
        var actionEl = event.target.closest("[data-bm-action]");
        if (!actionEl || !_el.contains(actionEl)) return;
        var action = actionEl.getAttribute("data-bm-action");
        if (action === "close") { closePanel(); return; }
        if (action === "toggle-mute") {
            _muted = !_muted;
            syncHeaderLedger();
            if (!_muted) ensureAudio().play("fx-select");
            return;
        }
        if (action === "poke-t800") {
            setT800State("idle", _t800Look, pickLine("poke"), true);
            return;
        }
        if (action === "open-help") { openDrawer("help", actionEl); return; }
        if (action === "open-exchange") { openDrawer("exchange", actionEl); return; }
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
        if (action === "inspection-compare") { toggleInspectionCompare(); return; }
        if (action === "inspection-side") {
            switchInspection(actionEl.getAttribute("data-pair-id"), actionEl.getAttribute("data-offer-id"));
            return;
        }
        if (action === "dismiss-error") { _error = null; render(); return; }
        if (!_session || !_snapshot || _busy) return;
        if (action === "inspect-selected" || action === "inspect-offer") {
            openInspection(actionEl.getAttribute("data-pair-id"), actionEl.getAttribute("data-offer-id"), actionEl);
            return;
        }
        if (action === "select") {
            clearSkipArmTimer();
            _selectedPairId = actionEl.getAttribute("data-pair-id");
            _selectedOfferId = actionEl.getAttribute("data-offer-id");
            // 保留玩家当前选择的支付方式（TP/K），不再每次选货强行重置回 TP
            var pair = findPair(_selectedPairId);
            setT800State("focus", lookForPair(pair ? pair.index : 2),
                _payment === "k" ? pickLine("selectK") : pickLine("select"), false);
            notifyFx("fx-select");
            refreshPreview();
            return;
        }
        if (action === "payment") {
            _payment = actionEl.getAttribute("data-payment") === "k" ? "k" : "tp";
            setT800State("focus", _t800Look,
                _payment === "k" ? pickLine("selectK") : pickLine("select"), false);
            notifyFx("fx-select");
            refreshPreview();
            return;
        }
        if (action === "cancel") { clearSelection(); render(); return; }
        if (action === "confirm") { confirmPurchase(); return; }
        if (action === "settle") {
            var settleKind = actionEl.getAttribute("data-settle");
            runProduct(function() {
                return _session.product.settle(settleKind, nextCallId("settle"));
            }, true, "settle", { settleKind: settleKind });
            return;
        }
        if (action === "skip") {
            requestSkipPair(actionEl.getAttribute("data-pair-id"), false);
            return;
        }
        if (action === "next-page") {
            runProduct(function() {
                return _session.product.nextPage(nextCallId("next-page"));
            }, true, "next-page");
            return;
        }
        if (action === "redeem-rawbox") {
            runProduct(function() {
                return _session.product.redeemRawBox(nextCallId("rawbox"));
            }, false, "rawbox");
            return;
        }
        if (action === "redeem-k") {
            var kAmt = Math.floor(Number(actionEl.getAttribute("data-k-amount")) || 0);
            runProduct(function() {
                return _session.product.redeemK(kAmt, nextCallId("redeem-k"));
            }, false, "redeem-k");
            return;
        }
    }

    // 不可逆“整舱放过”两段式防误触（首次点击/按 S 预武装，3 秒内再按生效）
    function requestSkipPair(pairId, fromKey) {
        if (!pairId || _busy || !_snapshot || _snapshot.pending) return;
        var pair = findPair(pairId);
        if (!pair || pair.status !== "open") return;
        if (_skipArmedPairId !== pairId) {
            clearSkipArmTimer();
            _skipArmedPairId = pairId;
            setT800State("idle", lookForPair(pair.index),
                "真要放过 0" + pair.index + " 号槽？封签后可就拆不了了——再按一次确认。", false);
            notifyFx("fx-select");
            render();
            _skipArmTimer = setTimeout(function() {
                _skipArmTimer = null;
                if (_skipArmedPairId === pairId) {
                    _skipArmedPairId = null;
                    render();
                }
            }, 3000);
            return;
        }
        clearSkipArmTimer();
        runProduct(function() {
            return _session.product.skip(pairId, nextCallId(fromKey ? "skip-key" : "skip"));
        }, true, "skip", { pairId: pairId });
    }

    function clearSkipArmTimer() {
        if (_skipArmTimer !== null) clearTimeout(_skipArmTimer);
        _skipArmTimer = null;
        _skipArmedPairId = null;
    }

    function clearSiphonTimer() {
        if (_siphonTimer !== null) clearTimeout(_siphonTimer);
        _siphonTimer = null;
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
            setT800State("error", _t800Look, _error, true);
            notifyFx("fx-error");
        }
        render();
    }

    function confirmPurchase() {
        if (!_preview) return;
        var preview = _preview;
        runProduct(function() {
            return _session.product.purchaseCommit(preview.token, nextCallId("purchase"));
        }, true, "purchase", { offerId: preview.offerId, pairId: preview.pairId });
    }

    function nextAvailableFocusKey(snapshot) {
        if (!snapshot) return null;
        if (snapshot.pending) return "settle-resell";
        if (snapshot.page.complete) return "next-page";
        for (var i = 0; i < snapshot.pairs.length; i += 1) {
            if (snapshot.pairs[i].status === "open") {
                return "offer-" + snapshot.pairs[i].offers[0].offerId;
            }
        }
        return null;
    }

    function runProduct(operation, clear, eventKind, meta) {
        if (_busy) return;
        meta = meta || {};
        _busy = true;
        syncBottomRail();
        Promise.resolve().then(operation).then(function(snapshot) {
            _snapshot = snapshot;
            _error = null;
            _notice = null;
            if (clear) clearSelection();
            notifyHost(eventKind, sessionTelemetry());
            var renderOpts = { focusKey: nextAvailableFocusKey(snapshot) };
            if (eventKind === "purchase" && snapshot.pending) {
                var pendingPair = findPair(snapshot.pending.pairId);
                var pendingOffer = pendingPair && findOffer(pendingPair, snapshot.pending.offerId);
                var isProfit = pendingOffer && pendingOffer.revealed && pendingOffer.revealed.direction === "profit";
                renderOpts.rehydrateOfferId = snapshot.pending.offerId;
                renderOpts.announce = pendingOffer && pendingOffer.revealed
                    ? "货物脱壳揭晓：" + pendingOffer.revealed.displayName + "，"
                        + (isProfit ? "盈利" : "亏损") + " " + Math.abs(pendingOffer.revealed.deltaV) + " 交易点等值。"
                    : "";
                setT800State(isProfit ? "profit" : "loss", lookForPair(pendingPair ? pendingPair.index : 2),
                    pickLine(isProfit ? "profit" : "loss"), true);
                notifyFx("fx-reveal-" + (isProfit ? "profit" : "loss"));
            } else if (eventKind === "settle") {
                if (snapshot.page.complete) {
                    setT800State("idle", "center", pickLine("complete"), true);
                } else {
                    setT800State("idle", "center", pickLine(meta.settleKind === "extract" ? "extracted" : "resold"), true);
                }
                notifyFx("fx-select");
            } else if (eventKind === "skip") {
                setT800State("skip", _t800Look, snapshot.page.complete ? pickLine("complete") : pickLine("skip"), true);
                notifyFx("fx-drain");
            } else if (eventKind === "next-page") {
                renderOpts.full = true;
                setT800State("boot", "center", "第 " + snapshot.page.number + " 批三组封件已送入培养槽。", true);
                notifyFx("fx-poweron");
            } else if (eventKind === "rawbox") {
                setT800State("profit", "center", pickLine("rawbox"), true);
                notifyFx("fx-rawbox");
            } else if (eventKind === "redeem-k") {
                setT800State("profit", "center", pickLine("redeemK"), true);
                notifyFx("fx-redeem-k");
                // 保持兑 K 抽屉刷新显示新余额
                if (_drawer === "exchange") renderOpts.keepDrawer = false;
            }
            _busy = false;
            render(renderOpts);
        }).catch(function(error) {
            _error = error && error.message ? error.message : String(error);
            setT800State("error", _t800Look, _error, true);
            notifyFx("fx-error");
            if (_session) _snapshot = _session.product.open();
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
            if (event.key === "Tab") { trapInspectionTab(event); return; }
            var keyLow = event.key.toLowerCase();
            if (keyLow === "r") {
                event.preventDefault();
                rotateInspection();
            } else if (keyLow === "a" || keyLow === "d") {
                var inspPair = findPair(_inspection.pairId);
                if (inspPair) {
                    event.preventDefault();
                    switchInspection(inspPair.pairId, inspPair.offers[keyLow === "a" ? 0 : 1].offerId);
                }
            }
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
        var lower = event.key.toLowerCase();
        var activeOffer = event.target.closest && event.target.closest("[data-offer-id]");
        var contextPairId = (activeOffer && activeOffer.getAttribute("data-pair-id")) || _selectedPairId;
        var contextOfferId = (activeOffer && activeOffer.getAttribute("data-offer-id")) || _selectedOfferId;

        if (lower === "v" && contextPairId && contextOfferId && !_snapshot.pending) {
            event.preventDefault();
            openInspection(contextPairId, contextOfferId, activeOffer || document.activeElement);
            return;
        }
        if (lower === "s" && contextPairId && !_snapshot.pending) {
            event.preventDefault();
            requestSkipPair(contextPairId, true);
            return;
        }
        if (!activeOffer) return;
        if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
            event.preventDefault();
            var allOffers = Array.prototype.slice.call(_el.querySelectorAll(".blackmarket-offer:not([disabled])"));
            var idx = allOffers.indexOf(activeOffer);
            if (idx >= 0) {
                var nextIdx = event.key === "ArrowLeft"
                    ? Math.max(0, idx - 1) : Math.min(allOffers.length - 1, idx + 1);
                if (allOffers[nextIdx]) allOffers[nextIdx].focus();
            }
        } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
            // 上下键跨舱跳转（每舱 2 件）
            event.preventDefault();
            var enabledOffers = Array.prototype.slice.call(_el.querySelectorAll(".blackmarket-offer:not([disabled])"));
            var pos = enabledOffers.indexOf(activeOffer);
            if (pos >= 0) {
                var step = event.key === "ArrowDown" ? 2 : -2;
                var target = Math.max(0, Math.min(enabledOffers.length - 1, pos + step));
                if (enabledOffers[target]) enabledOffers[target].focus();
            }
        }
    }

    // ── Host-owned exact close（修复失败/超时后永久变暗 Bug 与误报“操作被拒绝”）──
    function closePanel() {
        if (_closePending) return true;
        var panelInstanceId = _init && _init.panelInstanceId;
        if (!panelInstanceId || typeof Bridge === "undefined" || !Bridge.send) {
            _error = "测试面板实例已失效，关闭请求未发送。";
            _notice = null;
            render();
            return false;
        }
        var generation = _openGeneration;
        _closePending = true;
        _busy = true;
        _error = null;
        _notice = "正在等待 Launcher 确认关闭当前测试实例…";
        if (_scaleShell) _scaleShell.classList.add("is-powering-off");
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
                _notice = null;
                _error = "Launcher 连接不可用，测试面板保持打开。";
                if (_scaleShell) _scaleShell.classList.remove("is-powering-off");
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
                _notice = null;
                _error = "Launcher 尚未确认关闭，可再次尝试。";
                if (_scaleShell) _scaleShell.classList.remove("is-powering-off");
                render();
            }, closeAckTimeoutMs());
        }
        return true;
    }

    function cleanup() {
        clearCloseTimer();
        clearSkipArmTimer();
        clearSiphonTimer();
        clearT800TalkTimer();
        clearSoftlockObservation();
        _openGeneration += 1;
        _surfaceGeneration += 1;
        _panelOpen = false;
        _closePending = false;
        if (_scaleShell) _scaleShell.classList.remove("is-powering-off");
        _session = null;
        _snapshot = null;
        _selectedPairId = null;
        _selectedOfferId = null;
        _preview = null;
        _drawer = null;
        _drawerOpenerKey = null;
        _mountedShellKey = null;
        _surfaceMetrics = {};
        _surfaceMasters = {};
        _surfaceSnapshotKey = null;
        _hydratedSurfaceState = {};
        _offerSurfaceGen = {};
        _pairGenderPromises = {};
        _inspection = null;
        destroyInspectionCamera();
        hideOfferTip();
        stopBubbles();
        if (_audio) _audio.close();
        _audio = null;
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = null;
        if (_surfaceRenderer) _surfaceRenderer.destroy();
        _surfaceRenderer = null;
        if (_equipmentPreview) _equipmentPreview.destroy();
        _equipmentPreview = null;
        _busy = false;
        _error = null;
        _notice = null;
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

    function notifyFx(name) {
        if (!_panelOpen) return false;
        ensureAudio().play(name);
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

    function terminalLabel(status) {
        if (status === "skipped") return "已封签";
        if (status === "extracted") return "已提取";
        if (status === "resold") return "已回售";
        return "待结算";
    }

    function buildOfferAria(offer) {
        if (offer.revealed) return offer.revealed.displayName + "，" + (offer.revealed.direction === "profit" ? "盈利" : "亏损");
        return offer.label + "，" + (offer.hint || "身份未明");
    }

    function disabledAttr() { return _busy ? "disabled" : ""; }
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
        for (var i = 0; i < nodes.length; i += 1) {
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
        hideOfferTip();
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
        render({ focusKey: openerKey });
    }
    function trapDrawerTab(event) {
        var drawer = _root && _root.querySelector(".blackmarket-drawer");
        if (!drawer) return;
        var nodes = drawer.querySelectorAll('button:not([disabled]), select:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])');
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
