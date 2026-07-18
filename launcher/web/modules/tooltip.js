/**
 * PanelTooltip — 通用面板内 tooltip 模块
 *
 * 提供两种展示模式:
 *   1. hover 模式: showAtMouse / followMouse / hide — 跟随鼠标，鼠标离开即隐藏
 *   2. anchored 模式: showAnchored — 锚定到指定元素，支持 outside-click 关闭 + 自动超时
 *
 * 内容由调用方负责生成 HTML 字符串，本模块只管 DOM、定位和生命周期。
 * 包含 AS2 TextField HTML → 浏览器 HTML 转换工具函数 convertAS2Html()。
 */
var PanelTooltip = (function() {
    'use strict';

    var _el = null;
    var _visible = false;
    // Optional ownership token used by async/focus bindings. It prevents a
    // stale callback from one tile from replacing another tile's tooltip.
    var _owner = null;

    // anchored 模式的生命周期句柄
    var _outsideListener = null;
    var _autoTimer = null;

    // 最近一次定位上下文：用于 updateContent 异步数据到达后重新测量。
    // pointer 不直接存原 event 引用——浏览器复用 event 对象、跨帧不安全；anchored
    // 则保留稳定的 DOM anchor，内容/字体/图片尺寸变化后仍可重新夹紧到视口。
    var _lastEvt = null;
    var _lastAnchor = null;

    // ── show generation counter ──
    // 每次 show* / hide 单调自增。scheduleReposition 注册的延迟回调（fonts.ready /
    // raf×2 / img.onload / setTimeout）闭包捕获 gen 值，fire 时 alive() 比对当前 gen
    // 才执行。防止"前一次 show 注册的回调在 hide+下一次 show 之间 fire，把新 tooltip
    // 拉到旧坐标"。img.onload 即便元素已脱离 DOM 也会触发，所以仅靠 _visible 不够。
    var _showGen = 0;
    // 显式追踪 80ms 兜底定时器，hide() 时主动清掉避免空转
    var _repositionTimer = null;

    function init() {
        _el = document.getElementById('panel-tooltip');
        if (_el) {
            _el.setAttribute('role', 'tooltip');
            _el.setAttribute('aria-hidden', _visible ? 'false' : 'true');
        }
    }

    /** 获取 tooltip DOM 元素 */
    function getElement() { return _el; }

    /** 是否正在显示 */
    function isVisible(owner) {
        return _visible && (arguments.length === 0 || owner == null || _owner === owner);
    }

    // ── 内部清理 ──
    function cleanupHandlers() {
        if (_outsideListener) {
            document.removeEventListener('click', _outsideListener);
            _outsideListener = null;
        }
        if (_autoTimer) {
            clearTimeout(_autoTimer);
            _autoTimer = null;
        }
    }

    // ── hover 模式 ──

    /** hover 模式：在鼠标位置显示 tooltip，设置内容 */
    function showAtMouse(html, e, owner) {
        if (!_el) return;
        cleanupHandlers();
        _showGen++;                  // 让上一次 show 注册的延迟 reposition 全部失效
        _owner = owner == null ? null : owner;
        _el.innerHTML = html;
        _el.style.display = 'block';
        _el.setAttribute('aria-hidden', 'false');
        _visible = true;
        _lastAnchor = null;
        // 双面板模式：给 desc 写 inline width（port AS2 estimateMainWidth）。
        // 内容只在 setText 时变，鼠标移动不需要重算 → 放 showAtMouse 阶段。
        applyDescWidth();
        if (e) {
            _lastEvt = { clientX: e.clientX, clientY: e.clientY };
            positionAtMouse(_lastEvt);
            // Safety net：覆盖 async 加载源（字体 swap / icon 图加载 / 外部资源）
            var pointerPosition = _lastEvt;
            scheduleReposition(function() { positionAtMouse(pointerPosition); }, _showGen);
        }
    }

    // 多 tier 重新定位：每层覆盖不同 async 源。
    //   Tier 0: document.fonts.ready —— 字体 swap 是首次悬浮错位的主因；
    //           subsequent hover 时这个 Promise 已 resolved，几乎零成本。
    //   Tier 1: 双 raf —— 覆盖 layout/paint 两帧，处理 transform/CSSOM 稳定
    //   Tier 2: img.onload —— icon 图首次加载完成后再 reposition
    //   Tier 3: 80ms setTimeout —— 极端外部资源延迟兜底
    //
    // alive(gen) 守卫：每个回调必须同时满足 _visible && _showGen === gen 才 fire。
    // _visible 单独不够——hide()+showAtMouse() 之间，旧回调会把新 tooltip 错位到旧坐标。
    // img.onload 即使 img 已被 innerHTML 替换、脱离 DOM，仍可能触发，所以 gen 守卫是
    // 唯一可靠的"哪个 show 注册的"标识。
    function scheduleReposition(reposition, gen) {
        function alive() { return _visible && _showGen === gen; }
        function run() {
            if (alive()) reposition();
        }
        // Tier 0: 字体 ready
        if (document.fonts && document.fonts.ready && typeof document.fonts.ready.then === 'function') {
            document.fonts.ready.then(run);
        }
        // Tier 1: 双 raf
        requestAnimationFrame(function() {
            if (!alive()) return;
            requestAnimationFrame(run);
        });
        // Tier 2: img.onload —— icon 异步加载
        var imgs = _el.querySelectorAll('img');
        for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            if (img.complete) continue;
            img.addEventListener('load', run, { once: true });
            img.addEventListener('error', run, { once: true });
        }
        // Tier 3: 80ms 兜底
        // updateContent 时会再次调用，覆盖前一次的 timer 避免叠加。hide() 也会清掉。
        if (_repositionTimer) clearTimeout(_repositionTimer);
        _repositionTimer = setTimeout(function() {
            _repositionTimer = null;
            run();
        }, 80);
    }

    // ── AS2 TooltipLayout port — desc 宽度估算 ──
    //
    // 公式 / 常量来自：scripts/类定义/org/flashNight/gesh/tooltip/TooltipLayout.as
    //   + scripts/类定义/org/flashNight/gesh/tooltip/TooltipConstants.as
    //
    // 1) htmlScoresBoth — 字符权重扫描得 {total, maxLine, lineCount}
    //    ASCII=1, CJK=2, Space=0.5, <BR>/换行 flushLine
    // 2) estimateMainWidth — sqrt 公式：W = √(r × total × PIX_PER_UNIT × LINE_HEIGHT)
    //    r 由 totalScore smoothstep 在 [0.618, 1.5] 插值；maxLine 约束 + clamp [150, 650]
    //
    // 不实现 AS2 balanceWidth modeA 二分（依赖 Flash TextField 实测）— 实测 Playwright
    // fixture (launcher/perf/tooltip-regression/) 显示 ppu=6.0 即可让 mainW 偏差 p50=9，
    // mainBgH 偏差 p50=42（box-model 系统偏移 12 + 字号渲染偏差），比改前 mainW=+381 巨大改善。
    // 后续如需精细，可在 fixture 跑 --sweep-ppu 重新调 ppu 常量。
    //
    // ⚠️ 跨语言常量同步：以下数值与 TooltipConstants.as 一一对应，AS2 端改了 web 端必须同步：
    //   TT_PIX_PER_UNIT     ↔ TooltipConstants.PIX_PER_UNIT          (6.0)
    //   TT_LINE_HEIGHT      ↔ TooltipConstants.LINE_HEIGHT            (15)
    //   TT_RATIO_MIN/MAX    ↔ RATIO_MIN / RATIO_MAX                  (0.618 / 1.5)
    //   TT_RATIO_SCORE_CAP  ↔ RATIO_SCORE_CAP                         (300)
    //   TT_MAX_LINES        ↔ MAX_RENDERED_LINES                      (32)
    //   TT_LINE_GUTTER      ↔ LINE_GUTTER                             (20)
    //   TT_MIN_W / MAX_W    ↔ MIN_W / MAX_W                           (150 / 650)
    var TT_PIX_PER_UNIT = 6.0;
    var TT_LINE_HEIGHT = 15;
    var TT_RATIO_MIN = 0.618, TT_RATIO_MAX = 1.5, TT_RATIO_SCORE_CAP = 300;
    var TT_MAX_LINES = 32, TT_LINE_GUTTER = 20, TT_MIN_W = 150, TT_MAX_W = 650;

    function htmlScoresBoth(s) {
        if (!s) return { total: 0, maxLine: 0, lineCount: 1 };
        var i = 0, n = s.length;
        var total = 0, lineScore = 0, maxLine = 0, lineCount = 1;
        while (i < n) {
            var c = s.charCodeAt(i);
            if (c === 60) {  // '<'
                var c1 = s.charCodeAt(i + 1);
                var c2 = s.charCodeAt(i + 2);
                if ((c1 === 66 || c1 === 98) && (c2 === 82 || c2 === 114)) {
                    // <BR ...> / <br ...>
                    if (lineScore > maxLine) maxLine = lineScore;
                    lineScore = 0; lineCount++;
                }
                while (i < n && s.charCodeAt(i) !== 62) i++;
                i++;
                continue;
            }
            if (c === 10 || c === 13) {
                if (lineScore > maxLine) maxLine = lineScore;
                lineScore = 0; lineCount++;
                i++; continue;
            }
            var w;
            if (c === 32 || c === 9) w = 0.5;
            else if (c < 128) w = 1;
            else if (c >= 0x4E00 && c <= 0x9FFF) w = 2;
            else if (c >= 0x3000 && c <= 0x33FF) w = 2;
            else if (c >= 0xFF00 && c <= 0xFFEF) w = 2;
            else if (c < 256) w = 1;
            else w = 2;
            total += w;
            lineScore += w;
            i++;
        }
        if (lineScore > maxLine) maxLine = lineScore;
        return { total: total, maxLine: maxLine, lineCount: lineCount };
    }

    function estimateMainWidth(scores) {
        if (scores.total <= 0) return TT_MIN_W;
        var t = scores.total / TT_RATIO_SCORE_CAP;
        if (t > 1) t = 1;
        var ss = t * t * (3 - 2 * t);
        var r = TT_RATIO_MIN + ss * (TT_RATIO_MAX - TT_RATIO_MIN);
        var sqrtW = Math.sqrt(r * scores.total * TT_PIX_PER_UNIT * TT_LINE_HEIGHT);
        var wFloor = scores.total * TT_PIX_PER_UNIT / TT_MAX_LINES;
        if (sqrtW < wFloor) sqrtW = wFloor;
        if (scores.maxLine > 0) {
            var maxLineW = scores.maxLine * TT_PIX_PER_UNIT + TT_LINE_GUTTER;
            if (sqrtW > maxLineW) sqrtW = maxLineW;
        }
        return Math.max(TT_MIN_W, Math.min(sqrtW, TT_MAX_W));
    }

    // 给 desc 写 inline width；非 split 模式 / 无 desc 时无操作
    function applyDescWidth() {
        var rich = _el.querySelector('.flash-tt-rich');
        if (!rich || rich.classList.contains('flash-tt-rich--merge')) return;
        var descPanel = rich.querySelector('.flash-tt-desc');
        if (!descPanel) return;
        var scores = htmlScoresBoth(descPanel.innerHTML);
        var w = estimateMainWidth(scores);
        descPanel.style.width = w + 'px';
    }

    /** hover 模式：跟随鼠标移动 */
    function followMouse(e, owner) {
        if (!_el || !_visible || (owner != null && _owner !== owner)) return;
        _lastEvt = { clientX: e.clientX, clientY: e.clientY };
        positionAtMouse(_lastEvt);
    }

    // AS2 TooltipLayout.positionTooltip 端口（CSS 像素域）：
    //
    // ground truth 来源：scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipGroundTruthDump.as 跑出 862 物品
    // × 9 个 mouseY 采样，落到 launcher/perf/tooltip-regression/tooltip-truth.json（dev-only
    // 中间产物，不进 runtime 包；需要重采就跑 parse-gt.py）。统计：
    //   - mouseY 接近屏顶时：ELSE 分支主导（desc 紧贴顶，膨胀到 max(textH, iconH)+10 下限）
    //   - mouseY 接近屏底时：IF 分支主导（desc 整块下移让底部与 intro 底部对齐）
    //   - 同一物品在不同 mouseY 下 desc 位置/高度都变化——这就是"侧边栏根据鼠标位置自由排版"
    //
    // 公式（在 pre-scale 域跑）：
    //   tipsH   = max(introBgH, mainBgH)         # mainBgH 是 base = mainText.textHeight + 10
    //   tipsY   = clamp(0, stageH - tipsH, mouseY - tipsH - MOUSE_OFFSET)
    //   offset  = mouseY - (tipsY + mainBgH) - MOUSE_OFFSET
    //   if offset > 0:  desc marginTop = offset, height = mainBgH
    //   else:           desc marginTop = 0,      height = max(mainTH, iconH) + HEIGHT_ADJUST
    //
    // 关键测量约定（坐标域）：
    //   - #panel-tooltip 通过 `transform: scale(var(--cf7-overlay-scale))` 缩放（panels.css），
    //     transform 不影响 layout：introPanel/descPanel.offsetHeight 是 pre-scale CSS px。
    //   - e.clientX/Y、window.innerHeight 是 post-scale 视口 CSS px。
    //   - AS2 positionTooltip 原本在单一 stage 坐标系中跑，所以这里要把 mouseY/vh 折算到
    //     pre-scale 域（除以 scale）后再代入公式；输出的 rightBgY/rightBgH 写到 descPanel
    //     的 inline style（pre-scale），外层 transform 自动把视觉缩到对应比例。
    //   - _el 的 left/top 是 pre-transform 的位置；视觉边界比较用 getBoundingClientRect（post-scale）。
    //
    // 没 .flash-tt-rich 根（spark-tooltip / 旧调用方）退化为传统 +14/+14。
    var MOUSE_OFFSET = 20;
    var HEIGHT_ADJUST = 10;

    // 读当前 overlay scale。
    // 优先用 bridge.js 的 window.OverlayScale.get()——它在 resize/visualViewport.resize
    // 时已 cache，零成本调用；hover 模式 mousemove 60Hz 触发 positionAtMouse，避免
    // 每帧 getComputedStyle 触发 style 引擎多余工作。
    // fallback：OverlayScale 未加载（理论上 bridge.js 先于 tooltip.js）时读 CSS var。
    function getOverlayScale() {
        if (typeof window !== 'undefined' && window.OverlayScale
            && typeof window.OverlayScale.get === 'function') {
            var cached = window.OverlayScale.get();
            if (isFinite(cached) && cached > 0) return cached;
        }
        if (!document.documentElement) return 1;
        var v = getComputedStyle(document.documentElement)
            .getPropertyValue('--cf7-overlay-scale');
        var s = parseFloat(v);
        return (isFinite(s) && s > 0) ? s : 1;
    }

    // descPanel chrome（padding 上下 + border 上下）缓存。
    // 在 hover 模式 mousemove 60Hz 路径里，每帧 getComputedStyle 会让 style 引擎多做
    // 一次解析。chrome 只取决于 CSS（不随内容变），所以可以按 _showGen 缓存——一次
    // show 期间 CSS 不变就复用；showAtMouse / showAnchored / updateContent 换 innerHTML
    // 时 _descChromeGen 会跟新 _showGen 错位，自动失效。
    // 主题切换（[data-tooltip-theme]）会改 padding/border 但极罕见；切换后下一次 show
    // 自动重读。
    var _descChromeV = -1;
    var _descChromeGen = -1;
    function getDescChromeV(el) {
        if (_descChromeGen === _showGen && _descChromeV >= 0) return _descChromeV;
        var cs = getComputedStyle(el);
        _descChromeV = (parseFloat(cs.paddingTop) || 0)
                     + (parseFloat(cs.paddingBottom) || 0)
                     + (parseFloat(cs.borderTopWidth) || 0)
                     + (parseFloat(cs.borderBottomWidth) || 0);
        _descChromeGen = _showGen;
        return _descChromeV;
    }

    function positionAtMouse(e) {
        var vw = window.innerWidth, vh = window.innerHeight;
        var rich = _el.querySelector('.flash-tt-rich');
        var x, y;

        if (rich) {
            var isSplit = !rich.classList.contains('flash-tt-rich--merge')
                && !!rich.querySelector('.flash-tt-desc');
            var introPanel = rich.querySelector('.flash-tt-intro-panel');
            var descPanel = rich.querySelector('.flash-tt-desc');

            // 双面板：跑 AS2 positionTooltip 公式算 desc 的 marginTop + height
            if (isSplit && introPanel && descPanel) {
                // 清掉上一帧 inline style 才能拿自然态高度
                descPanel.style.marginTop = '';
                descPanel.style.height = '';

                var scale = getOverlayScale();
                var introBgH = introPanel.offsetHeight;       // pre-scale
                var mainBgH = descPanel.offsetHeight;          // pre-scale，自然态 = padding + text + border
                var iconEl = introPanel.querySelector('.flash-tt-icon');
                var iconH = iconEl ? iconEl.offsetHeight : 0;
                // mainTH = desc 文字内容高度，从 offsetHeight 减 chrome；
                // getComputedStyle 现读 padding/border，跟 CSS 实际值同步。
                var mainTH = Math.max(0, mainBgH - getDescChromeV(descPanel));

                // mouseY / stageH 折算到 pre-scale，跟 introBgH/mainBgH 同域
                var mouseY = e.clientY / scale;
                var stageH = vh / scale;

                var tipsH = Math.max(introBgH, mainBgH);
                var tipsY = Math.min(stageH - tipsH, Math.max(0, mouseY - tipsH - MOUSE_OFFSET));
                var rightBottomH = tipsY + mainBgH;
                var offset = mouseY - rightBottomH - MOUSE_OFFSET;

                var rightBgY, rightBgH;
                if (offset > 0) {
                    rightBgY = offset;
                    rightBgH = mainBgH;
                } else {
                    rightBgY = 0;
                    rightBgH = Math.max(mainTH, iconH) + HEIGHT_ADJUST;
                }
                descPanel.style.marginTop = rightBgY + 'px';
                descPanel.style.height = rightBgH + 'px';
            }

            // 物理尺寸（含 transform: scale）用于和鼠标位置比对
            var rect = _el.getBoundingClientRect();
            var tw = rect.width, th = rect.height;

            // AS2 TooltipLayout.positionTooltip 严格 clamp 复刻（无翻转分支）：
            //   tips._x = clamp(introBg._width, mouseX - rightBg._width, stageW - rightBg._width)
            //   tips._y = clamp(0, mouseY - tipsH - MOUSE_OFFSET, stageH - tipsH)
            // 旧实现有 `if (y < 8) y = e.clientY + MOUSE_OFFSET`——即鼠标靠近屏顶时
            // 把 tooltip 翻到鼠标 *下方* MOUSE_OFFSET 处。这跟 AS2 行为不一致：
            // AS2 会把 tooltip 贴屏顶（y=0），允许鼠标落进 tooltip 内部，但不引入额外 gap。
            // 翻转分支会让用户感到"鼠标和 tooltip 离得远"——已删除。
            x = e.clientX - tw;
            if (x < 0) x = 0;
            if (x + tw > vw) x = vw - tw;

            y = e.clientY - th - MOUSE_OFFSET;
            if (y < 0) y = 0;
            if (y + th > vh) y = vh - th;
        } else {
            // 普通 tooltip 同样受 overlay transform 影响；只把可视尺寸用于 viewport
            // 碰撞检测，正常的 +14 pointer gap 保持不变。
            var fallbackRect = _el.getBoundingClientRect();
            var fw = fallbackRect.width, fh = fallbackRect.height;
            x = e.clientX + 14; y = e.clientY + 14;
            if (x + fw > vw - 8) x = e.clientX - fw - 8;
            if (y + fh > vh - 8) y = vh - fh - 8;
        }

        _el.style.left = x + 'px';
        _el.style.top = y + 'px';
    }

    var ANCHOR_GAP = 8;
    var VIEWPORT_INSET = 8;

    // anchor rect 和 getBoundingClientRect() 都在 transform 后的 viewport CSS px 域。
    // tooltip 的 offsetWidth/offsetHeight 则是 transform 前尺寸，不能与前者混算。
    function positionAnchored(anchorEl) {
        if (!_el || !anchorEl || typeof anchorEl.getBoundingClientRect !== 'function') return;
        var anchorRect = anchorEl.getBoundingClientRect();
        var tooltipRect = _el.getBoundingClientRect();
        var scale = getOverlayScale();
        var tw = tooltipRect.width || (_el.offsetWidth || 300) * scale;
        var th = tooltipRect.height || (_el.offsetHeight || 200) * scale;
        var vw = window.innerWidth, vh = window.innerHeight;

        // 优先左侧；左侧放不下时选右侧。两侧都不足则选择空间更大的一侧，
        // 最后统一夹紧，避免异步富内容把 tooltip 推出 viewport。
        var leftSpace = anchorRect.left - VIEWPORT_INSET;
        var rightSpace = vw - VIEWPORT_INSET - anchorRect.right;
        var x = anchorRect.left - tw - ANCHOR_GAP;
        if (leftSpace < tw + ANCHOR_GAP && rightSpace > leftSpace) {
            x = anchorRect.right + ANCHOR_GAP;
        }
        var maxX = Math.max(VIEWPORT_INSET, vw - tw - VIEWPORT_INSET);
        x = Math.max(VIEWPORT_INSET, Math.min(x, maxX));

        var y = anchorRect.top;
        var maxY = Math.max(VIEWPORT_INSET, vh - th - VIEWPORT_INSET);
        y = Math.max(VIEWPORT_INSET, Math.min(y, maxY));

        _el.style.left = x + 'px';
        _el.style.top = y + 'px';
    }

    // ── anchored 模式 ──

    /**
     * anchored 模式：锚定到指定元素旁显示 tooltip
     * @param {string} html - 内容 HTML
     * @param {Element} anchorEl - 锚定元素
     * @param {Object} [opts] - 选项
     * @param {number} [opts.autoClose=8000] - 自动关闭延迟 ms，0 禁用
     * @param {boolean} [opts.outsideClick=true] - 点击外部关闭
     */
    function showAnchored(html, anchorEl, opts) {
        if (!_el) return;
        opts = opts || {};
        var autoClose = opts.autoClose !== undefined ? opts.autoClose : 8000;
        var outsideClick = opts.outsideClick !== false;
        var owner = opts.owner == null ? null : opts.owner;

        cleanupHandlers();
        _showGen++;                  // anchored 也是新一轮 show，失效上一次的延迟回调
        _owner = owner;
        _el.innerHTML = html;
        _el.style.display = 'block';
        _el.setAttribute('aria-hidden', 'false');
        _visible = true;
        _lastEvt = null;
        _lastAnchor = anchorEl || null;
        // contract 跟 showAtMouse 对齐：split-mode rich tooltip 也写 inline width，避免
        // anchored 调用方传 rich html 时 desc 退回 CSS max-width:650 横铺。
        // 注意：anchored 不跑 positionAtMouse 的 desc marginTop/height 公式（依赖 mouseY），
        // desc 高度由内容自然撑开。
        applyDescWidth();

        // 定位：使用 transform 后的物理尺寸，并覆盖字体/图片迟到导致的尺寸变化。
        if (_lastAnchor) {
            var anchoredElement = _lastAnchor;
            positionAnchored(anchoredElement);
            scheduleReposition(function() { positionAnchored(anchoredElement); }, _showGen);
        }

        // outside-click 关闭
        if (outsideClick) {
            _outsideListener = function(ev) {
                if (_el.contains(ev.target) || (anchorEl && anchorEl.contains(ev.target))) return;
                hide(owner);
            };
            setTimeout(function() {
                if (_outsideListener) document.addEventListener('click', _outsideListener);
            }, 0);
        }

        // 自动关闭
        if (autoClose > 0) {
            _autoTimer = setTimeout(function() { hide(owner); }, autoClose);
        }
    }

    /**
     * 更新已显示的 tooltip 内容（用于异步数据到达后刷新）。
     *
     * 关键：除了换 innerHTML，还要重跑 applyDescWidth + positionAtMouse +
     * scheduleReposition。否则新换的 .flash-tt-desc 没有 inline width，
     * 退回 CSS max-width: 650 兜底，desc 横向被撑宽到 ~680px，desc 高度变矮，
     * 排版会错位（K商城首次悬浮表现：先 placeholder，async 数据回来后 desc 宽错）。
     *
     * hover 模式下用 _lastEvt 复定位；anchored 模式保留 anchor，并在 basic→rich
     * 更新后重新测量物理尺寸、夹紧视口。
     */
    function updateContent(html, owner) {
        if (!_el || !_visible || (owner != null && _owner !== owner)) return false;
        _el.innerHTML = html;
        applyDescWidth();
        if (_lastEvt) {
            // 沿用当前 _showGen——updateContent 是同一次 show 的内容刷新，不是新 show。
            // 旧 scheduleReposition 注册的延迟回调依然 alive，新 schedule 添加针对新
            // DOM 的额外回调；都用同一个 _lastEvt 跑 positionAtMouse，幂等。
            var pointerPosition = _lastEvt;
            positionAtMouse(pointerPosition);
            scheduleReposition(function() { positionAtMouse(pointerPosition); }, _showGen);
        } else if (_lastAnchor) {
            var anchoredElement = _lastAnchor;
            positionAnchored(anchoredElement);
            scheduleReposition(function() { positionAnchored(anchoredElement); }, _showGen);
        }
        return true;
    }

    /** 隐藏 tooltip 并清理所有句柄 */
    function hide(owner) {
        if (owner != null && _owner !== owner) return false;
        cleanupHandlers();
        _visible = false;
        _owner = null;
        _showGen++;                  // 让所有未 fire 的 reposition 回调失效
        _lastEvt = null;
        _lastAnchor = null;
        if (_repositionTimer) {
            clearTimeout(_repositionTimer);
            _repositionTimer = null;
        }
        if (_el) {
            _el.style.display = 'none';
            _el.setAttribute('aria-hidden', 'true');
        }
        return true;
    }

    // ── AS2 HTML 转换 ──

    /**
     * 将 AS2 TextField HTML 标记转为浏览器兼容 HTML（真·标签+属性白名单，防 XSS）。
     * 覆盖 AS2 htmlText 常用子集：<FONT COLOR/SIZE/FACE>、<B>/<I>/<U>、<BR>、<P ALIGN>。
     *   - COLOR：仅 #RGB/#RRGGBB 十六进制；SIZE：1~96 的整数 px；FACE：白名单字符的 font-family。
     *   - P ALIGN：left/right/center/justify → text-align。
     * 实现（2026-06-09 安全加固）：用浏览器解析器把输入解析成【惰性】DOM（不加载资源/不执行脚本），
     *   再按白名单逐节点重建——未列入白名单的标签（<IMG>/<A>/<SCRIPT>…）只保留纯文本，事件属性
     *   （onerror/onclick…）与未知属性一律丢弃，文本节点全转义。
     *   起因：旧版只做正则标签替换，未知标签原样进 innerHTML；而对话/物品文本含 $PC→存档角色名等
     *   玩家可控输入，`<img src=x onerror=...>` 可在 WebView 执行脚本。真白名单从结构上杜绝注入。
     * 刻意【不】支持（留待对话框整体迁 web 的富文本阶段）：
     *   <A HREF>（asfunction: 无法在 web 执行 + 安全面）、<IMG>（外链/立绘）、<TEXTFORMAT>、<LI>。
     */
    function convertAS2Html(s) {
        if (!s) return '';
        s = String(s);
        if (typeof DOMParser === 'undefined') return escapeAS2Text(s);   // 无解析器退路：纯文本转义（不渲染但安全）
        var doc;
        try { doc = new DOMParser().parseFromString(s, 'text/html'); }
        catch (e) { return escapeAS2Text(s); }
        return (doc && doc.body) ? sanitizeAS2Children(doc.body) : '';
    }

    // 文本节点转义（进 innerHTML 前防破坏结构 / 实体注入）
    function escapeAS2Text(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function sanitizeAS2Children(node) {
        var out = '', kids = node.childNodes;
        for (var i = 0; i < kids.length; i++) out += sanitizeAS2Node(kids[i]);
        return out;
    }
    function sanitizeAS2Node(node) {
        if (node.nodeType === 3) return escapeAS2Text(node.nodeValue);   // 文本节点 → 转义
        if (node.nodeType !== 1) return '';                              // 注释/CDATA/其他 → 丢
        var tag = node.tagName ? node.tagName.toLowerCase() : '';
        var inner = sanitizeAS2Children(node);
        switch (tag) {
            case 'b': case 'strong': return '<b>' + inner + '</b>';
            case 'i': case 'em':     return '<i>' + inner + '</i>';
            case 'u':                return '<u>' + inner + '</u>';
            case 'br':               return '<br>';
            case 'p': {
                var al = as2AlignStyle(node.getAttribute('align'));
                return al ? '<p style="text-align:' + al + '">' + inner + '</p>' : '<p>' + inner + '</p>';
            }
            case 'font': case 'span': {
                var style = as2FontStyle(node);
                return style ? '<span style="' + style + '">' + inner + '</span>' : '<span>' + inner + '</span>';
            }
            default: return inner;   // 未知/危险标签：丢标签、留已 sanitize 的内容
        }
    }
    // FONT 属性白名单 + 严格校验（DOM getAttribute 返回值已解码实体；仅校验通过的安全值进 style）
    function as2FontStyle(node) {
        var style = [];
        var color = node.getAttribute('color');
        if (color && /^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$/.test(color)) style.push('color:' + color);
        var size = node.getAttribute('size');
        if (size != null && size !== '') {
            var px = parseInt(size, 10);
            if (!isNaN(px) && px > 0 && px <= 96) style.push('font-size:' + px + 'px');
        }
        var face = node.getAttribute('face');
        if (face) {
            var f = face.replace(/[^\w一-龥 \-]/g, '').replace(/\s+/g, ' ');   // 仅字母/数字/中文/空格/连字符
            if (f) style.push("font-family:'" + f + "'");
        }
        return style.join(';');
    }
    function as2AlignStyle(v) {
        v = (v || '').toLowerCase();
        return (v === 'left' || v === 'right' || v === 'center' || v === 'justify') ? v : '';
    }

    // ── HTML score 估算（对齐 AS2 StringUtils.htmlScoresBoth.total）──
    //
    // 用于 split/merge 决策。简化复刻 AS2 的字符权重：
    //   ASCII=1, CJK=2, Space=0.5, Newline=0；HTML 标签剥离，HTML 实体粗略当 1 字符。
    // 不追像素精度——目的是让 web split 决策跟 AS2 ≥95% 一致。
    function htmlTextScore(html) {
        if (!html) return 0;
        var s = String(html)
            .replace(/<[^>]+>/g, '')   // 剥 HTML 标签
            .replace(/&(?:#\d+|[a-zA-Z]+);/g, ' ');  // HTML 实体粗略当 1 字符
        var score = 0;
        for (var i = 0; i < s.length; i++) {
            var c = s.charCodeAt(i);
            if (c === 10 || c === 13) continue;                  // \r\n
            else if (c === 32 || c === 9) score += 0.5;          // space/tab
            else if (c < 128) score += 1;                         // ASCII
            else if (c >= 0x4E00 && c <= 0x9FFF) score += 2;      // CJK Unified
            else if (c >= 0x3000 && c <= 0x33FF) score += 2;      // CJK 标点/符号
            else if (c >= 0xFF00 && c <= 0xFFEF) score += 2;      // Fullwidth
            else if (c < 256) score += 1;                         // Latin-1
            else score += 2;                                       // 其他双宽
        }
        return score;
    }

    // 对齐 AS2 TooltipLayout.shouldSplitSmart + TooltipComposer.renderItemTooltipSmart
    // 后置 MERGE_MAX_INTRO_LINES 检查。常量同源 scripts/类定义/org/flashNight/gesh/tooltip/
    // TooltipConstants.as：SPLIT_THRESHOLD=96, SMART_TOTAL_MULTIPLIER=2, SMART_DESC_DIVISOR=2,
    // MERGE_MAX_INTRO_LINES=20。常量任一端改了要两边同步。
    //
    // 两段决策：
    //   1) AS2 shouldSplitSmart —— 总量 + desc 量同时过线 → split
    //   2) merge 二次兜底 —— 即便 shouldSplitSmart 选择 merge，合并行数 > 20 仍强制
    //      split。AS2 端用 measureRenderedLines 实测；web 无 Flash TextField，用
    //      "合并 total score / 单格 charsPerLine" 估算 wrapped 行数。merge 模式
    //      panel 宽度锁 BASE_NUM=200px，PIX_PER_UNIT=6 → 单行约 33 score。
    var SPLIT_THRESHOLD = 96;
    var SMART_TOTAL_MULT = 2;
    var SMART_DESC_DIV = 2;
    var MERGE_MAX_INTRO_LINES = 20;
    // BASE_NUM(200) / PIX_PER_UNIT(6) ≈ 33 score 单元/行（200px 宽下的近似容量）
    var MERGE_CHARS_PER_LINE = 33;
    function shouldSplitWeb(descHtml, introHtml) {
        var descScore = htmlTextScore(descHtml);
        var introScore = htmlTextScore(introHtml);
        var smartSplit = (descScore + introScore > SPLIT_THRESHOLD * SMART_TOTAL_MULT)
            && (descScore > SPLIT_THRESHOLD / SMART_DESC_DIV);
        if (smartSplit) return true;
        // merge 二次兜底：估算合并后 wrapped 行数；> 20 行强制 split，避免 200px
        // 窄面板被拉成长条遮挡视线。
        var mergedLines = (descScore + introScore) / MERGE_CHARS_PER_LINE;
        if (mergedLines > MERGE_MAX_INTRO_LINES) return true;
        return false;
    }

    // ── 共享物品 tooltip 渲染器 ──
    //
    // kshop / intelligence / arena 三家都用 TooltipComposer 的 introHTML + descHTML 双段输出。
    // 结构对齐 AS2 端 TooltipLayout：
    //   - split 模式（默认 auto）：左 intro-panel（icon 在上 + 属性文字）+ 右 desc
    //   - merge 模式（短注释自动触发）：仅 intro-panel，desc 拼到 intro 末尾（对齐 AS2
    //     setVisibility("main", false) + desc 通过 <BR> 拼入 intro）
    //
    //   <div class="flash-tt-rich kshop-tt-rich [flash-tt-rich--merge] {rootClass}">
    //     <div class="flash-tt-intro-panel">
    //       {iconBlock}
    //       <div class="flash-tt-intro">{intro}{metaHTML}[merged desc]</div>
    //     </div>
    //     [<div class="flash-tt-desc">{desc}</div>]   ← merge 模式时无此栏
    //   </div>
    //   {suffix}
    //
    // opts:
    //   iconHtml       - 可选，已渲染的可信图标 HTML（如 Icons.html），用于动态图标
    //   iconUrl        - 已 resolved 的 URL；为空且 iconPlaceholder 未提供则不渲图标
    //   iconPlaceholder- iconUrl 缺失时的占位 HTML（如 '?' 字符 span）
    //   introHTML      - AS2 原始 HTML（自动 convertAS2Html）
    //   introWebHTML   - 可选，调用方已转义动态值的可信 Web HTML；用于保留 Web 专用 class
    //   descHTML       - 同上
    //   metaHTML       - 可选附加到 intro 段末尾的 HTML（如"已发现 X/Y 页"）
    //   rootClass      - 附加到 .flash-tt-rich 的额外类（per-panel 视觉 override）
    //   suffix         - 在根 div 之后追加（kshop 的 lock banner 走这里）
    //   splitMode      - 'auto'(默认) / 'split'(强制双栏) / 'merge'(强制单栏)
    //   layoutType     - 'wide'(默认) / 'narrow' — 对齐 AS2 TooltipLayout.applyIntroLayout 的两条分支：
    //                    'wide'   = 武器/护甲/技能/药水分支 (introBg=BASE_NUM=200, icon~185)
    //                    'narrow' = default 分支 (introBg=BASE_NUM*RATE=120, icon~111)
    //                    在 .flash-tt-rich 上写 data-layout="narrow"，CSS 局部覆盖 token。
    //                    判断规则参考 ItemUseTypes.TYPE_WEAPON/TYPE_ARMOR/TYPE_SKILL/POTION，
    //                    其他类型物品 (消耗品/材料/收集品/情报/…) 由 caller 显式传 'narrow'。
    function buildItemRichHtml(opts) {
        opts = opts || {};
        var iconBlock = '';
        if (opts.iconHtml) {
            iconBlock = '<div class="flash-tt-icon kshop-tt-icon">' + opts.iconHtml + '</div>';
        } else if (opts.iconUrl) {
            iconBlock = '<div class="flash-tt-icon kshop-tt-icon"><img src="' + opts.iconUrl +
                '" onerror="this.parentNode.style.display=\'none\'"></div>';
        } else if (opts.iconPlaceholder) {
            iconBlock = '<div class="flash-tt-icon kshop-tt-icon">' + opts.iconPlaceholder + '</div>';
        }
        var meta  = opts.metaHTML || '';
        var rootClass = opts.rootClass ? ' ' + opts.rootClass : '';

        // 决策 split / merge：auto 模式按 AS2 shouldSplitSmart 规则
        var splitMode = opts.splitMode || 'auto';
        var doSplit;
        if (splitMode === 'split') doSplit = true;
        else if (splitMode === 'merge') doSplit = false;
        else doSplit = shouldSplitWeb(opts.descHTML, opts.introWebHTML || opts.introHTML);

        var intro = opts.introWebHTML != null
            ? String(opts.introWebHTML)
            : (opts.introHTML ? convertAS2Html(opts.introHTML) : '');
        var desc  = opts.descHTML  ? convertAS2Html(opts.descHTML)  : '';

        // desc 是空时也无所谓 split 不 split；强制走 merge
        if (!desc) doSplit = false;

        var introContent;
        if (doSplit) {
            introContent = intro + meta;
        } else {
            // merge 模式：把 desc 拼到 intro 末尾，对齐 AS2 用 <BR> 分隔的合并方式
            var sep = (intro || meta) && desc ? '<br><br>' : '';
            introContent = intro + meta + sep + desc;
        }

        var introInner = introContent
            ? '<div class="flash-tt-intro kshop-tt-intro">' + introContent + '</div>'
            : '';
        var introPanel = (iconBlock || introInner)
            ? '<div class="flash-tt-intro-panel kshop-tt-intro-panel">' + iconBlock + introInner + '</div>'
            : '';

        var mergeClass = doSplit ? '' : ' flash-tt-rich--merge';
        // layoutType 写到 data-layout 上，CSS 局部覆盖 --tt-intro-w / --tt-icon-size 等 token。
        // 默认 'wide' 不输出 attr（沿用 .flash-tt-rich 基础 token）。
        var layoutAttr = (opts.layoutType === 'narrow') ? ' data-layout="narrow"' : '';
        var html = '<div class="flash-tt-rich kshop-tt-rich' + mergeClass + rootClass + '"' + layoutAttr + '>' +
            introPanel +
            (doSplit && desc ? '<div class="flash-tt-desc kshop-tt-desc">' + desc + '</div>' : '') +
        '</div>';
        if (opts.suffix) html += opts.suffix;
        return html;
    }

    function dynamicIconHtml(iconKey, className, attrs) {
        if (!iconKey || typeof Icons === 'undefined' || !Icons || !Icons.html) return '';
        try {
            return Icons.html(iconKey, className || '', attrs || ' onerror="this.style.display=\'none\'"');
        } catch (e) {
            return '';
        }
    }

    // 当前仍有 pointer/focus 活性的异步绑定，按最近激活顺序排列。全局 tooltip 被
    // 临时 hover owner 覆盖后，该 owner 离开时从栈顶恢复仍聚焦的 binding。
    var _activeAsyncBindings = [];

    function removeActiveBinding(binding) {
        var index = _activeAsyncBindings.indexOf(binding);
        if (index >= 0) _activeAsyncBindings.splice(index, 1);
    }

    function markActiveBinding(binding) {
        removeActiveBinding(binding);
        _activeAsyncBindings.push(binding);
    }

    function restoreActiveBinding(excluded) {
        for (var i = _activeAsyncBindings.length - 1; i >= 0; i--) {
            var candidate = _activeAsyncBindings[i];
            if (!candidate || candidate === excluded || !candidate.canRestore()) {
                if (!candidate || !candidate.canRestore()) _activeAsyncBindings.splice(i, 1);
                continue;
            }
            if (candidate.restore()) return true;
        }
        return false;
    }

    /**
     * 异步 entity tooltip 通用绑定。
     *
     * pointer 与键盘焦点是两个并行输入源：pointer 活跃时跟随鼠标；pointer 离开但
     * 焦点仍在 tile 内时退回 anchored 展示；两个输入源都离开才隐藏。每个绑定持有
     * 独立 owner，迟到回包、Icons.load 回调和 teardown 都不能覆盖其他 tile。
     *
     * options:
     *   - key: string | function(event, node) -> string   缓存键
     *   - resolveItem: function(event, node) -> item      可选，解析对应的 item
     *   - item: any                                       静态 item（resolveItem 的替代）
     *   - cache: Object                                   可选外部缓存对象（按 key 存 fetch 结果）
     *   - renderBasic: function(item) -> html             未缓存/加载中显示的内容
     *   - renderRich: function(item, data) -> html        fetch 成功后显示的内容
     *   - fetch: function(item, callback(response))       发起异步请求，成功后调 callback
     *   - isSuppressed: function(event) -> boolean        可选，拖拽等场景抑制 tooltip
     *   - events: 'pointer' | 'mouse'                     默认 pointer；mouse 兼容旧代码
     */
    function bindAsync(node, options) {
        if (!node || !options) return { destroy: function() {} };
        if (node.__panelTooltipBinding && typeof node.__panelTooltipBinding.destroy === 'function') {
            node.__panelTooltipBinding.destroy();
        }
        var cache = options.cache || {};
        var owner = {};
        var activePointers = {};
        var focusWithin = false;
        var disposed = false;
        var activeKey = null;
        var activeItem = null;
        var lastPointerEvent = null;
        var pending = {};
        var requestSequence = 0;
        var tooltipElement = getElement();
        var tooltipId = tooltipElement && tooltipElement.id ? tooltipElement.id : 'panel-tooltip';
        var describedByAtBind = node.getAttribute('aria-describedby');
        var describedByHadTooltip = describedByAtBind
            ? describedByAtBind.split(/\s+/).indexOf(tooltipId) >= 0 : false;

        function resolveKey(e) {
            if (typeof options.key === 'function') return String(options.key(e, node) || '');
            return String(options.key);
        }

        function resolveItem(e) {
            if (typeof options.resolveItem === 'function') return options.resolveItem(e, node);
            return options.item;
        }

        function suppressed(e) {
            if (typeof options.isSuppressed === 'function') return !!options.isSuppressed(e);
            return false;
        }

        function pointerIdOf(e) {
            return (e && typeof e.pointerId === 'number') ? e.pointerId : 'mouse';
        }

        function pointerSnapshot(e) {
            return {
                clientX: e && Number(e.clientX) || 0,
                clientY: e && Number(e.clientY) || 0,
                pointerId: e && typeof e.pointerId === 'number' ? e.pointerId : undefined,
                pointerType: e && e.pointerType || 'mouse',
                target: e && e.target || node,
                currentTarget: node
            };
        }

        function hasActivePointer() {
            for (var key in activePointers) {
                if (activePointers[key]) return true;
            }
            return false;
        }

        function isActive() { return focusWithin || hasActivePointer(); }

        function addTooltipDescription() {
            var tokens = (node.getAttribute('aria-describedby') || '').split(/\s+/).filter(Boolean);
            if (tokens.indexOf(tooltipId) < 0) tokens.push(tooltipId);
            node.setAttribute('aria-describedby', tokens.join(' '));
        }

        function removeTooltipDescription() {
            if (describedByHadTooltip) return;
            var tokens = (node.getAttribute('aria-describedby') || '').split(/\s+/).filter(function(token) {
                return token && token !== tooltipId;
            });
            if (tokens.length) node.setAttribute('aria-describedby', tokens.join(' '));
            else node.removeAttribute('aria-describedby');
        }

        function renderRichIfCurrent(key, response) {
            if (disposed || activeKey !== key || !isActive() || !isVisible(owner)
                    || typeof options.renderRich !== 'function') return;
            updateContent(options.renderRich(activeItem, response), owner);
        }

        function requestRich(key, item) {
            if (cache[key] || pending[key] || typeof options.fetch !== 'function') return;
            var requestId = ++requestSequence;
            pending[key] = requestId;
            try {
                options.fetch(item, function(response) {
                    if (disposed || pending[key] !== requestId) return;
                    delete pending[key];
                    if (!response || response.success !== true) return;
                    cache[key] = response;
                    if (typeof Icons === 'undefined' || !Icons || !Icons.load) {
                        renderRichIfCurrent(key, response);
                        return;
                    }
                    Icons.load(function() { renderRichIfCurrent(key, response); });
                });
            } catch (error) {
                if (pending[key] === requestId) delete pending[key];
                throw error;
            }
        }

        function showCurrent(event) {
            if (disposed || !isActive()) return false;
            if (suppressed(event)) {
                hide(owner);
                return false;
            }
            var key = resolveKey(event);
            var item = resolveItem(event);
            activeKey = key;
            activeItem = item;
            var html = cache[key] && typeof options.renderRich === 'function'
                ? options.renderRich(item, cache[key])
                : (typeof options.renderBasic === 'function' ? options.renderBasic(item) : '');
            if (hasActivePointer() && lastPointerEvent) showAtMouse(html, lastPointerEvent, owner);
            else showAnchored(html, node, { autoClose: 0, outsideClick: false, owner: owner });
            requestRich(key, item);
            return true;
        }

        function clearIfInactive() {
            if (isActive()) return;
            removeActiveBinding(binding);
            activeKey = null;
            activeItem = null;
            lastPointerEvent = null;
            if (hide(owner)) restoreActiveBinding(binding);
        }

        function onEnter(e) {
            if (disposed || suppressed(e)) return;
            var pointerId = pointerIdOf(e);
            if (activePointers[pointerId]) return;
            activePointers[pointerId] = true;
            markActiveBinding(binding);
            lastPointerEvent = pointerSnapshot(e);
            showCurrent(e);
        }

        function onMove(e) {
            if (disposed) return;
            lastPointerEvent = pointerSnapshot(e);
            if (suppressed(e)) {
                hide(owner);
                return;
            }
            if (!isVisible(owner)) showCurrent(e);
            else followMouse(e, owner);
        }

        function onLeave(e) {
            var pointerId = pointerIdOf(e);
            if (!activePointers[pointerId]) return;
            delete activePointers[pointerId];
            if (hasActivePointer()) return;
            lastPointerEvent = null;
            if (focusWithin) showCurrent(e);
            else clearIfInactive();
        }

        function onFocusIn(e) {
            if (disposed || (e.relatedTarget && node.contains(e.relatedTarget))) return;
            focusWithin = true;
            markActiveBinding(binding);
            addTooltipDescription();
            if (!hasActivePointer()) showCurrent(e);
        }

        function onFocusOut(e) {
            if (e.relatedTarget && node.contains(e.relatedTarget)) return;
            focusWithin = false;
            removeTooltipDescription();
            if (hasActivePointer()) showCurrent(lastPointerEvent || e);
            else clearIfInactive();
        }

        var hasPointerEvent = typeof window !== 'undefined' && typeof window.PointerEvent === 'function';
        var useMouse = options.events === 'mouse' || (!hasPointerEvent && options.events !== 'pointer');
        var enterEvent = useMouse ? 'mouseenter' : 'pointerenter';
        var moveEvent = useMouse ? 'mousemove' : 'pointermove';
        var leaveEvent = useMouse ? 'mouseleave' : 'pointerleave';
        node.addEventListener(enterEvent, onEnter);
        node.addEventListener(moveEvent, onMove);
        node.addEventListener(leaveEvent, onLeave);
        node.addEventListener('focusin', onFocusIn);
        node.addEventListener('focusout', onFocusOut);

        var binding = {
            canRestore: function() {
                return !disposed && isActive();
            },
            restore: function() {
                return !disposed && isActive()
                    ? showCurrent(lastPointerEvent || { target: node, currentTarget: node })
                    : false;
            },
            destroy: function() {
                if (disposed) return false;
                disposed = true;
                requestSequence++;
                pending = {};
                node.removeEventListener(enterEvent, onEnter);
                node.removeEventListener(moveEvent, onMove);
                node.removeEventListener(leaveEvent, onLeave);
                node.removeEventListener('focusin', onFocusIn);
                node.removeEventListener('focusout', onFocusOut);
                focusWithin = false;
                activePointers = {};
                removeActiveBinding(binding);
                activeKey = null;
                activeItem = null;
                removeTooltipDescription();
                if (hide(owner)) restoreActiveBinding(binding);
                if (node.__panelTooltipBinding === binding) node.__panelTooltipBinding = null;
                return true;
            },
            refresh: function() {
                if (!disposed && isActive()) showCurrent(lastPointerEvent || { target: node });
            }
        };
        node.__panelTooltipBinding = binding;
        return binding;
    }

    // Compatibility alias retained for existing panel modules while the name
    // migrates from a pointer-only description to the neutral input contract.
    function bindAsyncHover(node, options) { return bindAsync(node, options); }

    function staticIconUrl(iconKey) {
        if (!iconKey || typeof Icons === 'undefined' || !Icons || !Icons.resolve) return null;
        try {
            return Icons.resolve(iconKey);
        } catch (e) {
            return null;
        }
    }

    // 根据 AS2 端 TooltipLayout.applyIntroLayout 的 case 判断布局类型。
    // - wide  分支匹配 TYPE_WEAPON='武器' / TYPE_ARMOR='防具' / TYPE_SKILL='技能' / POTION='药剂'
    // - narrow 分支是 default fallthrough，覆盖一切其他类型（消耗品/材料/收集品/情报/...）
    // AS2 端 K商城 / 情报 / 竞技场 layoutType 推导：
    //   (data.type == TYPE_CONSUMABLE) ? data.use : data.type
    // web 这里 caller 传过来的 type 字段语义对齐 AS2 data.type（消耗品时传 use）。
    //
    // typeField 为 null/undefined/空串时说明 caller 的 item 数据缺字段——会静默走
    // 'narrow' 让 icon 突然变小。dev 模式下一次性 warn 帮助排查，行为不变（保持 AS2
    // fallthrough 对齐）。同一个未识别 type 只 warn 一次，避免 hover 刷屏。
    var _layoutTypeWarnSeen = {};
    function inferLayoutType(typeField) {
        if (typeField === '武器' || typeField === '防具' ||
            typeField === '技能' || typeField === '药剂') {
            return 'wide';
        }
        if ((typeField == null || typeField === '')
            && typeof console !== 'undefined' && !_layoutTypeWarnSeen['__empty__']) {
            _layoutTypeWarnSeen['__empty__'] = 1;
            console.warn('[PanelTooltip] inferLayoutType: typeField 为空，fallback narrow');
        }
        return 'narrow';
    }

    if (document.readyState === 'loading') window.addEventListener('load', init);
    else init();

    return {
        getElement: getElement,
        isVisible: isVisible,
        showAtMouse: showAtMouse,
        followMouse: followMouse,
        showAnchored: showAnchored,
        updateContent: updateContent,
        hide: hide,
        bindAsync: bindAsync,
        bindAsyncHover: bindAsyncHover,
        convertAS2Html: convertAS2Html,
        buildItemRichHtml: buildItemRichHtml,
        dynamicIconHtml: dynamicIconHtml,
        staticIconUrl: staticIconUrl,
        // 决策辅助（暴露给调用方在请求 AS2 注释前/后预判 split/merge / layout）
        htmlTextScore: htmlTextScore,
        shouldSplitWeb: shouldSplitWeb,
        inferLayoutType: inferLayoutType
    };
})();
