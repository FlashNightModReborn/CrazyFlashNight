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

    // anchored 模式的生命周期句柄
    var _outsideListener = null;
    var _autoTimer = null;

    // 最近一次 hover mouse 位置缓存：用于 updateContent 异步数据到达后重新定位。
    // 不直接存原 event 引用——浏览器复用 event 对象、跨帧不安全。
    var _lastEvt = null;

    function init() {
        _el = document.getElementById('panel-tooltip');
    }

    /** 获取 tooltip DOM 元素 */
    function getElement() { return _el; }

    /** 是否正在显示 */
    function isVisible() { return _visible; }

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
    function showAtMouse(html, e) {
        if (!_el) return;
        cleanupHandlers();
        _el.innerHTML = html;
        _el.style.display = 'block';
        _visible = true;
        // 双面板模式：给 desc 写 inline width（port AS2 estimateMainWidth）。
        // 内容只在 setText 时变，鼠标移动不需要重算 → 放 showAtMouse 阶段。
        applyDescWidth();
        if (e) {
            _lastEvt = { clientX: e.clientX, clientY: e.clientY };
            positionAtMouse(_lastEvt);
            // Safety net：覆盖 async 加载源（字体 swap / icon 图加载 / 外部资源）
            scheduleReposition(_lastEvt);
        }
    }

    // 多 tier 重新定位：每层覆盖不同 async 源。
    //   Tier 0: document.fonts.ready —— 字体 swap 是首次悬浮错位的主因；
    //           subsequent hover 时这个 Promise 已 resolved，几乎零成本。
    //   Tier 1: 双 raf —— 覆盖 layout/paint 两帧，处理 transform/CSSOM 稳定
    //   Tier 2: img.onload —— icon 图首次加载完成后再 reposition
    //   Tier 3: 80ms setTimeout —— 极端外部资源延迟兜底
    function scheduleReposition(e) {
        // Tier 0: 字体 ready
        if (document.fonts && document.fonts.ready && typeof document.fonts.ready.then === 'function') {
            document.fonts.ready.then(function() {
                if (_visible) positionAtMouse(e);
            });
        }
        // Tier 1: 双 raf
        requestAnimationFrame(function() {
            if (!_visible) return;
            requestAnimationFrame(function() {
                if (_visible) positionAtMouse(e);
            });
        });
        // Tier 2: img.onload —— icon 异步加载
        var imgs = _el.querySelectorAll('img');
        for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            if (img.complete) continue;
            img.addEventListener('load', function() {
                if (_visible) positionAtMouse(e);
            }, { once: true });
            img.addEventListener('error', function() {
                if (_visible) positionAtMouse(e);
            }, { once: true });
        }
        // Tier 3: 80ms 兜底
        setTimeout(function() {
            if (_visible) positionAtMouse(e);
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
    function followMouse(e) {
        if (!_el || !_visible) return;
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

    // 读 #panel-tooltip 的 --cf7-overlay-scale；不存在则视为 1。
    // 由 bridge.js OverlayScale 在 resize/visualViewport.resize 时写到 documentElement。
    function getOverlayScale() {
        if (!document.documentElement) return 1;
        var v = getComputedStyle(document.documentElement)
            .getPropertyValue('--cf7-overlay-scale');
        var s = parseFloat(v);
        return (isFinite(s) && s > 0) ? s : 1;
    }

    // 计算 descPanel 的 chrome（padding 上下 + border 上下），用于把 offsetHeight 反推回 mainTH。
    // 直接 getComputedStyle 比硬编码常量稳：CSS padding 改了也跟得上。
    function getDescChromeV(el) {
        var cs = getComputedStyle(el);
        return (parseFloat(cs.paddingTop) || 0)
             + (parseFloat(cs.paddingBottom) || 0)
             + (parseFloat(cs.borderTopWidth) || 0)
             + (parseFloat(cs.borderBottomWidth) || 0);
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

            x = e.clientX - tw;
            if (x < 8) x = 8;
            if (x + tw > vw - 8) x = vw - tw - 8;

            y = e.clientY - th - MOUSE_OFFSET;
            if (y < 8) y = e.clientY + MOUSE_OFFSET;
            if (y + th > vh - 8) y = vh - th - 8;
        } else {
            var fw = _el.offsetWidth, fh = _el.offsetHeight;
            x = e.clientX + 14; y = e.clientY + 14;
            if (x + fw > vw - 8) x = e.clientX - fw - 8;
            if (y + fh > vh - 8) y = vh - fh - 8;
        }

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

        cleanupHandlers();
        _el.innerHTML = html;
        _el.style.display = 'block';
        _visible = true;
        _lastEvt = null;   // anchored 不依赖鼠标位置，清掉避免被 updateContent 误用
        // contract 跟 showAtMouse 对齐：split-mode rich tooltip 也写 inline width，避免
        // anchored 调用方传 rich html 时 desc 退回 CSS max-width:650 横铺。
        // 注意：anchored 不跑 positionAtMouse 的 desc marginTop/height 公式（依赖 mouseY），
        // desc 高度由内容自然撑开。
        applyDescWidth();

        // 定位：优先放在锚定元素左侧，放不下则右侧
        if (anchorEl) {
            var rect = anchorEl.getBoundingClientRect();
            var tw = _el.offsetWidth || 300;
            var th = _el.offsetHeight || 200;
            var vw = window.innerWidth, vh = window.innerHeight;
            var x = rect.left - tw - 8;
            if (x < 8) x = rect.right + 8;
            var y = rect.top;
            if (y + th > vh - 8) y = vh - th - 8;
            if (y < 8) y = 8;
            _el.style.left = x + 'px';
            _el.style.top = y + 'px';
        }

        // outside-click 关闭
        if (outsideClick) {
            _outsideListener = function(ev) {
                if (_el.contains(ev.target) || (anchorEl && anchorEl.contains(ev.target))) return;
                hide();
            };
            setTimeout(function() {
                if (_outsideListener) document.addEventListener('click', _outsideListener);
            }, 0);
        }

        // 自动关闭
        if (autoClose > 0) {
            _autoTimer = setTimeout(function() { hide(); }, autoClose);
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
     * hover 模式下用 _lastEvt 复定位；anchored 模式 _lastEvt=null，跳过定位环节
     * （anchored 现在 caller 不用 updateContent，但保留 fallback 健壮）。
     */
    function updateContent(html) {
        if (!_el || !_visible) return;
        _el.innerHTML = html;
        applyDescWidth();
        if (_lastEvt) {
            positionAtMouse(_lastEvt);
            scheduleReposition(_lastEvt);
        }
    }

    /** 隐藏 tooltip 并清理所有句柄 */
    function hide() {
        cleanupHandlers();
        _visible = false;
        _lastEvt = null;
        if (_el) _el.style.display = 'none';
    }

    // ── AS2 HTML 转换 ──

    /**
     * 将 AS2 TextField HTML 标记转为浏览器兼容 HTML
     * AS2 使用 <FONT COLOR='#FFCC00'> 等大写标签
     */
    function convertAS2Html(s) {
        if (!s) return '';
        return String(s)
            .replace(/<FONT\b([^>]*)>/gi, function(m, attrs) {
                attrs = attrs || '';
                var style = [];
                var color = /\bCOLOR\s*=\s*(['"])(.*?)\1/i.exec(attrs);
                if (color && /^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$/.test(color[2])) {
                    style.push('color:' + color[2]);
                }
                var size = /\bSIZE\s*=\s*(['"])(.*?)\1/i.exec(attrs);
                if (size) {
                    var px = parseInt(size[2], 10);
                    if (!isNaN(px) && px > 0 && px <= 96) style.push('font-size:' + px + 'px');
                }
                return style.length ? '<span style="' + style.join(';') + '">' : '<span>';
            })
            .replace(/<\/FONT>/gi, '</span>')
            .replace(/<B>/gi, '<b>').replace(/<\/B>/gi, '</b>')
            .replace(/<I>/gi, '<i>').replace(/<\/I>/gi, '</i>')
            .replace(/<U>/gi, '<u>').replace(/<\/U>/gi, '</u>')
            .replace(/<BR\s*\/?>/gi, '<br>');
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

    // 对齐 AS2 TooltipLayout.shouldSplitSmart：
    //   needSplit = (descTotal + introTotal > SPLIT_THRESHOLD * SMART_TOTAL_MULTIPLIER)
    //            && (descTotal > SPLIT_THRESHOLD / SMART_DESC_DIVISOR)
    // AS2 常量：SPLIT_THRESHOLD=96, SMART_TOTAL_MULTIPLIER=2, SMART_DESC_DIVISOR=2
    var SPLIT_THRESHOLD = 96;
    var SMART_TOTAL_MULT = 2;
    var SMART_DESC_DIV = 2;
    function shouldSplitWeb(descHtml, introHtml) {
        var descScore = htmlTextScore(descHtml);
        var introScore = htmlTextScore(introHtml);
        return (descScore + introScore > SPLIT_THRESHOLD * SMART_TOTAL_MULT)
            && (descScore > SPLIT_THRESHOLD / SMART_DESC_DIV);
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
    //   iconUrl        - 已 resolved 的 URL；为空且 iconPlaceholder 未提供则不渲图标
    //   iconPlaceholder- iconUrl 缺失时的占位 HTML（如 '?' 字符 span）
    //   introHTML      - AS2 原始 HTML（自动 convertAS2Html）
    //   descHTML       - 同上
    //   metaHTML       - 可选附加到 intro 段末尾的 HTML（如"已发现 X/Y 页"）
    //   rootClass      - 附加到 .flash-tt-rich 的额外类（per-panel 视觉 override）
    //   suffix         - 在根 div 之后追加（kshop 的 lock banner 走这里）
    //   splitMode      - 'auto'(默认) / 'split'(强制双栏) / 'merge'(强制单栏)
    function buildItemRichHtml(opts) {
        opts = opts || {};
        var iconBlock = '';
        if (opts.iconUrl) {
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
        else doSplit = shouldSplitWeb(opts.descHTML, opts.introHTML);

        var intro = opts.introHTML ? convertAS2Html(opts.introHTML) : '';
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
        var html = '<div class="flash-tt-rich kshop-tt-rich' + mergeClass + rootClass + '">' +
            introPanel +
            (doSplit && desc ? '<div class="flash-tt-desc kshop-tt-desc">' + desc + '</div>' : '') +
        '</div>';
        if (opts.suffix) html += opts.suffix;
        return html;
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
        convertAS2Html: convertAS2Html,
        buildItemRichHtml: buildItemRichHtml,
        // 决策辅助（暴露给调用方在请求 AS2 注释前/后预判 split/merge）
        htmlTextScore: htmlTextScore,
        shouldSplitWeb: shouldSplitWeb
    };
})();
