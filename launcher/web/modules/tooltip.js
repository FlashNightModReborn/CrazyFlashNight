/**
 * PanelTooltip — 通用面板内 tooltip 模块
 *
 * 提供两种展示模式:
 *   1. hover 模式: showAtMouse / followMouse / hideHover — 跟随鼠标，触发物与浮层组成复合 hover 区
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
    // tooltip 本身必须可悬停，长说明才能用滚轮读取。当前展示 owner 通过这一条全局
    // interaction bridge 接收 enter/leave，避免给每个物品格都向同一 tooltip DOM 挂监听器。
    var _interactionOwner = null;
    var _interactionHandlers = null;
    // 兼容仍手工调用 showAtMouse() 的旧面板：mouseleave 不能立即 hide，否则鼠标永远
    // 进不了可滚动浮层。hideHover() 提供短暂过桥时间，进入 tooltip 后暂停，离开再收起。
    var _hoverHideTimer = null;
    var _hoverHidePending = false;
    var _hoverHideOwner = null;
    var _tooltipHovered = false;
    // mouseenter 不足以证明用户主动进入浮层：tooltip 因异步内容重排、缩放或换 owner
    // 移到静止指针下时，Chromium 也可能迟到派发 enter。只有真实 move 的命中目标是
    // 当前 tooltip，才授予复合 hover 资格；延迟关闭时再用 elementFromPoint 复核。
    var _lastHoverPointer = null;

    function clearHoverHide() {
        if (_hoverHideTimer) clearTimeout(_hoverHideTimer);
        _hoverHideTimer = null;
        _hoverHidePending = false;
        _hoverHideOwner = null;
    }

    function pauseHoverHide() {
        if (_hoverHideTimer) clearTimeout(_hoverHideTimer);
        _hoverHideTimer = null;
    }

    function pointerTargetsTooltip() {
        if (!_el || !_visible || !_tooltipHovered || !_lastHoverPointer
                || _lastHoverPointer.showGen !== _showGen) return false;
        var hit = null;
        if (document && typeof document.elementFromPoint === 'function') {
            hit = document.elementFromPoint(_lastHoverPointer.clientX, _lastHoverPointer.clientY);
        }
        return !!(hit && (hit === _el || _el.contains(hit)));
    }

    function resetTooltipHover(notifyInteraction) {
        var wasHovered = _tooltipHovered;
        _tooltipHovered = false;
        _lastHoverPointer = null;
        if (!wasHovered || !notifyInteraction) return;
        var interaction = activeInteraction();
        if (interaction && interaction.leave) interaction.leave(null);
    }

    function confirmTooltipHover(event) {
        if (!_el || !_visible || !event || !isFinite(Number(event.clientX))
                || !isFinite(Number(event.clientY))) return false;
        var target = event.target;
        if (!target || (target !== _el && !_el.contains(target))) return false;
        var clientX = Number(event.clientX);
        var clientY = Number(event.clientY);
        // Chromium 的真实 mouse 会依次派发 pointermove 与兼容 mousemove。pointermove
        // 已完成同一坐标的 hit-test 后，兼容事件只需复用结论，避免重复触发几何查询；
        // interaction.enter 仍由下面的 _tooltipHovered 守卫保证每轮只调用一次。
        if (event.type === 'mousemove' && _tooltipHovered && _lastHoverPointer
                && _lastHoverPointer.input === 'pointer'
                && _lastHoverPointer.showGen === _showGen
                && _lastHoverPointer.clientX === clientX
                && _lastHoverPointer.clientY === clientY) return true;
        var hit = document.elementFromPoint(clientX, clientY);
        if (!hit || (hit !== _el && !_el.contains(hit))) return false;
        _lastHoverPointer = {
            clientX:clientX,
            clientY:clientY,
            showGen:_showGen,
            input:event.type === 'pointermove' ? 'pointer' : 'mouse'
        };
        if (_tooltipHovered) return true;
        var interaction = activeInteraction();
        if (interaction && interaction.enter && interaction.enter(event) === false) {
            _lastHoverPointer = null;
            return false;
        }
        _tooltipHovered = true;
        // 不取消过桥计时：140ms 到点仍做一次最终 hit-test。实际仍在浮层上时
        // 计时回调只保留 pending，之后 mouseleave 会重新安排收起。
        return true;
    }

    function trackHoverPointer(event) {
        if (!_visible || !event || !isFinite(Number(event.clientX)) || !isFinite(Number(event.clientY))) return;
        if (event.pointerType && event.pointerType !== 'mouse' && event.pointerType !== 'pen') return;
        var target = event.target;
        var targetsTooltip = !!(_el && target && (target === _el || _el.contains(target)));
        if (targetsTooltip) return;
        _lastHoverPointer = {
            clientX:Number(event.clientX),
            clientY:Number(event.clientY),
            showGen:_showGen
        };
        if (!_tooltipHovered) return;
        _tooltipHovered = false;
        var interaction = activeInteraction();
        if (interaction && interaction.leave) interaction.leave(event);
        scheduleHoverHide();
    }

    function scheduleHoverHide() {
        pauseHoverHide();
        if (!_hoverHidePending) return;
        _hoverHideTimer = setTimeout(function() {
            _hoverHideTimer = null;
            if (!_hoverHidePending) return;
            if (pointerTargetsTooltip()) return;
            resetTooltipHover(true);
            var owner = _hoverHideOwner;
            _hoverHidePending = false;
            _hoverHideOwner = null;
            hide(owner);
        }, 140);
    }

    function setInteraction(owner, handlers) {
        _interactionOwner = owner;
        _interactionHandlers = handlers || null;
    }

    function clearInteraction(owner) {
        if (owner != null && _interactionOwner !== owner) return;
        _interactionOwner = null;
        _interactionHandlers = null;
    }

    function activeInteraction() {
        return _interactionOwner != null && _interactionOwner === _owner ? _interactionHandlers : null;
    }

    function scrollableDescription() {
        if (!_el) return null;
        var desc = _el.querySelector('.flash-tt-desc, .kshop-tt-desc');
        return desc && desc.scrollHeight > desc.clientHeight + 1 ? desc : null;
    }

    function refreshScrollableState() {
        if (!_el) return false;
        var desc = _el.querySelector('.flash-tt-desc, .kshop-tt-desc');
        var scrollable = !!(desc && desc.scrollHeight > desc.clientHeight + 1);
        _el.classList.toggle('panel-tooltip-scrollable', scrollable);
        if (desc) {
            desc.classList.toggle('flash-tt-desc--scrollable', scrollable);
            if (scrollable) desc.setAttribute('aria-label', '完整物品说明，可用滚轮或 PageUp、PageDown 滚动');
            else desc.removeAttribute('aria-label');
        }
        return scrollable;
    }

    function init() {
        _el = document.getElementById('panel-tooltip');
        if (_el) {
            _el.setAttribute('role', 'tooltip');
            _el.setAttribute('aria-hidden', _visible ? 'false' : 'true');
            // enter 只能表示几何命中发生变化；必须等 move 真正落在浮层上才确认交互。
            // PointerEvent 环境直接消费 pointermove，让 pen 不依赖 UA 是否派发
            // 兼容 mousemove；同时保留 mousemove 给旧浏览器与现有调用方。
            if (typeof window !== 'undefined' && typeof window.PointerEvent === 'function') {
                _el.addEventListener('pointermove', confirmTooltipHover);
            }
            _el.addEventListener('mousemove', confirmTooltipHover);
            _el.addEventListener('mouseleave', function(event) {
                if (!_tooltipHovered) return;
                _tooltipHovered = false;
                _lastHoverPointer = null;
                var interaction = activeInteraction();
                if (interaction && interaction.leave) interaction.leave(event);
                scheduleHoverHide();
            });
            _el.addEventListener('wheel', function(event) {
                var desc = scrollableDescription();
                if (!desc || !isFinite(Number(event.deltaY)) || Number(event.deltaY) === 0) return;
                var before = desc.scrollTop;
                desc.scrollTop += Number(event.deltaY);
                if (desc.scrollTop !== before) {
                    event.preventDefault();
                    event.stopPropagation();
                }
            }, {passive:false});
            if (typeof window !== 'undefined' && typeof window.PointerEvent === 'function') {
                document.addEventListener('pointermove', trackHoverPointer, true);
                document.addEventListener('pointerdown', notePointerInput, true);
            } else {
                document.addEventListener('mousemove', trackHoverPointer, true);
                document.addEventListener('mousedown', notePointerInput, true);
            }
            document.addEventListener('keydown', noteKeyboardInput, true);
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
        clearHoverHide();
        resetTooltipHover(true);
        clearInteraction();
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
        refreshScrollableState();
        if (e) {
            _lastEvt = {
                clientX: e.clientX,
                clientY: e.clientY,
                anchor: e.currentTarget || e.target || null
            };
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
        _lastEvt = {
            clientX: e.clientX,
            clientY: e.clientY,
            anchor: e.currentTarget || (_lastEvt && _lastEvt.anchor) || e.target || null
        };
        positionAtMouse(_lastEvt);
    }

    // Web tooltip 的几何契约与 AS2 视觉契约分离：内容仍复用 TooltipComposer，
    // 但浮层作为一个整体围绕触发元素放置。初始位置不得覆盖触发元素或当前鼠标热点；
    // 空间不足时按 left -> right -> top -> bottom 选择最小碰撞候选，再夹紧视口。
    var POINTER_EXCLUSION = 16;
    var ANCHOR_GAP = 10;
    var VIEWPORT_INSET = 8;
    var _lastPlacement = null;

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(value, maximum));
    }

    function overlapArea(a, b) {
        var width = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
        var height = Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top));
        return width * height;
    }

    function rectAt(x, y, width, height) {
        return {left:x, top:y, right:x + width, bottom:y + height, width:width, height:height};
    }

    function anchorRectOf(anchor, pointer) {
        if (anchor && anchor.isConnected !== false && typeof anchor.getBoundingClientRect === 'function') {
            return anchor.getBoundingClientRect();
        }
        var x = Number(pointer && pointer.clientX) || 0;
        var y = Number(pointer && pointer.clientY) || 0;
        return {left:x, right:x, top:y, bottom:y, width:0, height:0};
    }

    function candidateScore(candidate, anchorRect, pointerRect, vw, vh, priority) {
        var rect = rectAt(candidate.x, candidate.y, candidate.width, candidate.height);
        var overflow = Math.max(0, VIEWPORT_INSET - rect.left)
            + Math.max(0, VIEWPORT_INSET - rect.top)
            + Math.max(0, rect.right - (vw - VIEWPORT_INSET))
            + Math.max(0, rect.bottom - (vh - VIEWPORT_INSET));
        return overflow * 1000000
            + overlapArea(rect, pointerRect) * 10000
            + overlapArea(rect, anchorRect) * 100
            + Number(candidate.shift || 0) * 10
            + priority;
    }

    function positionFloating(pointer, anchor, anchored) {
        var vw = window.innerWidth, vh = window.innerHeight;
        var rich = _el.querySelector('.flash-tt-rich');
        if (rich) {
            var descPanel = rich.querySelector('.flash-tt-desc');
            if (descPanel) {
                descPanel.style.marginTop = '';
                descPanel.style.height = '';
            }
            rich.classList.remove('flash-tt-rich--stacked');
            var wideRect = _el.getBoundingClientRect();
            if (wideRect.width > vw - VIEWPORT_INSET * 2) {
                rich.classList.add('flash-tt-rich--stacked');
            }
        }
        var tooltipRect = _el.getBoundingClientRect();
        var tw = tooltipRect.width || 1;
        var th = tooltipRect.height || 1;
        var anchorRect = anchorRectOf(anchor, pointer);
        var pointerX = Number(pointer && pointer.clientX);
        var pointerY = Number(pointer && pointer.clientY);
        if (!isFinite(pointerX)) pointerX = (anchorRect.left + anchorRect.right) / 2;
        if (!isFinite(pointerY)) pointerY = (anchorRect.top + anchorRect.bottom) / 2;
        var pointerRadius = anchored ? 0 : POINTER_EXCLUSION;
        var pointerRect = {
            left:pointerX - pointerRadius, right:pointerX + pointerRadius,
            top:pointerY - pointerRadius, bottom:pointerY + pointerRadius
        };
        var candidates = [
            {name:'left', x:anchorRect.left - tw - ANCHOR_GAP, y:anchorRect.top, width:tw, height:th},
            {name:'right', x:anchorRect.right + ANCHOR_GAP, y:anchorRect.top, width:tw, height:th},
            {name:'top', x:anchorRect.left, y:anchorRect.top - th - ANCHOR_GAP, width:tw, height:th},
            {name:'bottom', x:anchorRect.left, y:anchorRect.bottom + ANCHOR_GAP, width:tw, height:th}
        ];
        var best = null;
        for (var i = 0; i < candidates.length; i++) {
            var candidate = candidates[i];
            var rawX = candidate.x, rawY = candidate.y;
            candidate.x = clamp(rawX, VIEWPORT_INSET, Math.max(VIEWPORT_INSET, vw - tw - VIEWPORT_INSET));
            candidate.y = clamp(rawY, VIEWPORT_INSET, Math.max(VIEWPORT_INSET, vh - th - VIEWPORT_INSET));
            candidate.shift = Math.abs(candidate.x - rawX) + Math.abs(candidate.y - rawY);
            candidate.score = candidateScore(candidate, anchorRect, pointerRect, vw, vh, i);
            if (!best || candidate.score < best.score) best = candidate;
        }
        var x = clamp(best.x, VIEWPORT_INSET, Math.max(VIEWPORT_INSET, vw - tw - VIEWPORT_INSET));
        var y = clamp(best.y, VIEWPORT_INSET, Math.max(VIEWPORT_INSET, vh - th - VIEWPORT_INSET));
        _el.style.left = x + 'px';
        _el.style.top = y + 'px';
        _el.setAttribute('data-placement', best.name);
        var finalRect = rectAt(x, y, tw, th);
        _lastPlacement = {
            placement:best.name,
            pointerOverlap:anchored ? 0 : overlapArea(finalRect, pointerRect),
            anchorOverlap:overlapArea(finalRect, anchorRect),
            insideViewport:finalRect.left >= VIEWPORT_INSET - 1 && finalRect.top >= VIEWPORT_INSET - 1
                && finalRect.right <= vw - VIEWPORT_INSET + 1 && finalRect.bottom <= vh - VIEWPORT_INSET + 1
        };
    }

    function positionAtMouse(e) {
        if (!_el || !e) return;
        positionFloating(e, e.anchor || null, false);
    }

    // anchor rect 和 getBoundingClientRect() 都在 transform 后的 viewport CSS px 域。
    function positionAnchored(anchorEl) {
        if (!_el || !anchorEl || typeof anchorEl.getBoundingClientRect !== 'function') return;
        positionFloating(null, anchorEl, true);
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
        clearHoverHide();
        resetTooltipHover(true);
        clearInteraction();
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
        refreshScrollableState();

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
        refreshScrollableState();
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
        // 无 owner 的调用是面板/业务层的确定性 dismiss。除关闭视觉层外还要撤销
        // bindAsync 的两个输入 owner，避免 selection、drag 或 inspector 关闭后旧 owner
        // 被下一次 pointer leave 恢复。bindAsync 内部始终携带私有 owner token。
        if (owner == null) releaseAllAsyncOwners();
        cleanupHandlers();
        clearHoverHide();
        // display:none 时浏览器不保证再派发 mouseleave；显式归零避免下一次手工
        // hideHover() 把已经消失的旧浮层误判为仍在 hover。
        resetTooltipHover(true);
        clearInteraction(owner);
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

    /**
     * hover 模式的延迟隐藏。给指针 140ms 从触发物跨入 tooltip；进入后保持展示，
     * 离开 tooltip 才继续收起。面板关闭/重渲染等确定性生命周期仍应调用 hide()。
     */
    function hideHover(owner) {
        if (!_visible || (owner != null && _owner !== owner)) return false;
        clearHoverHide();
        _hoverHidePending = true;
        _hoverHideOwner = owner == null ? null : owner;
        scheduleHoverHide();
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

    // 异步 tooltip 只有两个可恢复来源：当前物理指针 owner 与当前键盘焦点 owner。
    // DOM 同时只有一个 activeElement，桌面 hover 也只有一个当前 owner；保留任意长度
    // 的“最近活跃栈”会让鼠标点击产生的旧焦点在空白处复活，且没有真实输入状态依据。
    var _pointerAsyncBinding = null;
    var _keyboardAsyncBinding = null;
    var _inputModality = 'keyboard';
    var _allAsyncBindings = [];
    var _tooltipScopes = [];
    var _scopeSequence = 0;

    function removeFromArray(array, value) {
        var index = array.indexOf(value);
        if (index >= 0) array.splice(index, 1);
    }

    function noBinding() {
        return {
            destroy: function() { return false; },
            refresh: function() {},
            canRestorePointer: function() { return false; },
            canRestoreKeyboard: function() { return false; }
        };
    }

    function isNodeConnected(node) {
        if (!node) return false;
        if (typeof node.isConnected === 'boolean') return node.isConnected;
        var root = document && document.documentElement;
        return !!(root && (node === root || root.contains(node)));
    }

    /**
     * Panel 级 tooltip 所有权域。面板关闭时只需 dispose 一次，域内所有 tile 的
     * listener、异步回包和可恢复状态都会同时失效，避免调用方手工逐节点清理。
     */
    function createScope(label) {
        var scope = {
            id: 'tooltip-scope-' + (++_scopeSequence),
            label: String(label || 'panel'),
            disposed: false,
            bindings: [],
            isActive: function() { return !scope.disposed; },
            bindAsync: function(node, options) {
                if (scope.disposed) return noBinding();
                var scopedOptions = {};
                options = options || {};
                for (var key in options) {
                    if (Object.prototype.hasOwnProperty.call(options, key)) scopedOptions[key] = options[key];
                }
                scopedOptions.scope = scope;
                return bindAsync(node, scopedOptions);
            },
            bindAsyncHover: function(node, options) {
                return scope.bindAsync(node, options);
            },
            releaseTree: function(root) {
                return releaseTree(root, scope);
            },
            dispose: function() {
                if (scope.disposed) return false;
                scope.disposed = true;
                if (_pointerAsyncBinding && _pointerAsyncBinding.scope === scope) _pointerAsyncBinding = null;
                if (_keyboardAsyncBinding && _keyboardAsyncBinding.scope === scope) _keyboardAsyncBinding = null;
                var bindings = scope.bindings.slice();
                for (var i = bindings.length - 1; i >= 0; i--) bindings[i].destroy();
                scope.bindings = [];
                removeFromArray(_tooltipScopes, scope);
                return true;
            }
        };
        _tooltipScopes.push(scope);
        return scope;
    }

    /** 在 DOM subtree 被替换前释放绑定；scope 可选，用于避免误伤别的面板。 */
    function releaseTree(root, scope) {
        if (!root) return 0;
        var released = 0;
        function releaseNode(node) {
            var binding = node && node.__panelTooltipBinding;
            if (!binding || (scope && binding.scope !== scope)) return;
            if (binding.destroy()) released++;
        }
        releaseNode(root);
        if (root.querySelectorAll) {
            var descendants = root.querySelectorAll('*');
            for (var i = 0; i < descendants.length; i++) releaseNode(descendants[i]);
        }
        return released;
    }

    function debugState() {
        var detached = 0;
        for (var i = 0; i < _allAsyncBindings.length; i++) {
            if (!_allAsyncBindings[i].isConnected()) detached++;
        }
        var activeCount = 0;
        if (_pointerAsyncBinding) activeCount++;
        if (_keyboardAsyncBinding && _keyboardAsyncBinding !== _pointerAsyncBinding) activeCount++;
        return {
            activeBindingCount: activeCount,
            pointerOwnerActive: !!_pointerAsyncBinding,
            keyboardOwnerActive: !!_keyboardAsyncBinding,
            inputModality: _inputModality,
            bindingCount: _allAsyncBindings.length,
            detachedBindingCount: detached,
            activeScopeCount: _tooltipScopes.length,
            lastPlacement: _lastPlacement
        };
    }

    function claimPointerBinding(binding) {
        _pointerAsyncBinding = binding || null;
    }

    function releasePointerBinding(binding) {
        if (_pointerAsyncBinding === binding) _pointerAsyncBinding = null;
    }

    function claimKeyboardBinding(binding) {
        if (_keyboardAsyncBinding && _keyboardAsyncBinding !== binding
                && _keyboardAsyncBinding.suspendDescription) {
            _keyboardAsyncBinding.suspendDescription();
        }
        _keyboardAsyncBinding = binding || null;
    }

    function releaseKeyboardBinding(binding) {
        if (_keyboardAsyncBinding === binding) _keyboardAsyncBinding = null;
    }

    function restoreOwnedBinding(excluded) {
        var pointer = _pointerAsyncBinding;
        if (pointer && pointer !== excluded) {
            if (pointer.canRestorePointer()) {
                if (pointer.restorePointer()) return true;
            } else {
                _pointerAsyncBinding = null;
            }
        }
        var keyboard = _keyboardAsyncBinding;
        if (keyboard && keyboard !== excluded) {
            if (keyboard.canRestoreKeyboard()) {
                if (keyboard.restoreKeyboard()) return true;
            } else {
                if (keyboard.suspendDescription) keyboard.suspendDescription();
                _keyboardAsyncBinding = null;
            }
        }
        return false;
    }

    function noteKeyboardInput(event) {
        var key = event && event.key;
        if (key === 'Shift' || key === 'Control' || key === 'Alt' || key === 'Meta'
                || key === 'CapsLock' || key === 'NumLock' || key === 'ScrollLock') return;
        _inputModality = 'keyboard';
    }

    function notePointerInput() {
        _inputModality = 'pointer';
        var keyboard = _keyboardAsyncBinding;
        if (keyboard && keyboard.revokeKeyboardFromPointer) {
            keyboard.revokeKeyboardFromPointer();
        }
    }

    function releaseAllAsyncOwners() {
        var pointer = _pointerAsyncBinding;
        var keyboard = _keyboardAsyncBinding;
        _pointerAsyncBinding = null;
        _keyboardAsyncBinding = null;
        if (pointer && pointer.abandonInputOwners) pointer.abandonInputOwners();
        if (keyboard && keyboard !== pointer && keyboard.abandonInputOwners) {
            keyboard.abandonInputOwners();
        }
    }

    /**
     * 异步 entity tooltip 通用绑定。
     *
     * pointer 与键盘焦点是两个并行输入源：pointer 活跃时跟随鼠标；pointer 离开后
     * 只允许恢复仍匹配 document.activeElement 的 keyboard owner。鼠标/笔点击形成的
     * DOM focus 不会取得 keyboard owner。每个绑定持有独立 owner，迟到回包、
     * Icons.load 回调和 teardown 都不能覆盖其他 tile。
     *
     * options:
     *   - key: string | function(event, node) -> string   缓存键
     *   - resolveItem: function(event, node) -> item      可选，解析对应的 item
     *   - item: any                                       静态 item（resolveItem 的替代）
     *   - cache: Object                                   可选外部缓存对象（按 key 存 fetch 结果）
     *   - renderBasic: function(item) -> html             未缓存/加载中显示的内容
     *   - renderRich: function(item, data) -> html        fetch 成功后显示的内容
     *   - renderFailure: function(item, response) -> html 可选，读取失败但仍可重试
     *   - fetch: function(item, callback(response))       发起异步请求，成功后调 callback
     *   - isSuppressed: function(event) -> boolean        可选，拖拽等场景抑制 tooltip
     *   - events: 'pointer' | 'mouse'                     默认 pointer；mouse 兼容旧代码
     */
    function bindAsync(node, options) {
        if (!node || !options) return noBinding();
        var scope = options.scope || null;
        if (scope && scope.disposed) return noBinding();
        if (node.__panelTooltipBinding && typeof node.__panelTooltipBinding.destroy === 'function') {
            node.__panelTooltipBinding.destroy();
        }
        var cache = options.cache || {};
        var owner = {};
        var binding = null;
        var activePointers = {};
        var tooltipHovered = false;
        var leaveTimer = null;
        var keyboardDismissed = false;
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

        // 嵌套绑定纪律：事件目标落在拥有自己 bindAsync 绑定的后代内时，祖先绑定不接手。
        // pointermove 会冒泡——卡级 tip（如 merc 名册卡）内的装备/技能格（格级 tip）若不
        // 拦截，卡级 onMove 每帧抢回 pointer owner 把格级 tooltip 顶掉（Phase K-A 根因，
        // 已用 tmp/probe-merc-tooltip.js 实证）。pointerenter 的 target 恒为 node 本身，
        // 不会命中此守卫；后代格子的 enter 随后正常接管。
        function nestedBindingOwns(e) {
            var target = e && e.target;
            if (!target || target === node || !node.contains(target)) return false;
            var cur = target;
            while (cur && cur !== node) {
                if (cur.__panelTooltipBinding) return true;
                cur = cur.parentNode;
            }
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

        function clearLeaveTimer() {
            if (!leaveTimer) return;
            clearTimeout(leaveTimer);
            leaveTimer = null;
        }

        function hasDocumentFocus() {
            var activeElement = document && document.activeElement;
            return !!(activeElement && (activeElement === node || node.contains(activeElement)));
        }

        function baseLive() {
            return !disposed && !(scope && scope.disposed) && isNodeConnected(node);
        }

        function canOwnPointer(e, includeGrace) {
            if (!baseLive() || _pointerAsyncBinding !== binding) return false;
            if (!hasActivePointer() && !tooltipHovered && !(includeGrace && leaveTimer)) return false;
            return !suppressed(e || lastPointerEvent);
        }

        function canOwnKeyboard(e) {
            return baseLive() && _keyboardAsyncBinding === binding && !keyboardDismissed
                && hasDocumentFocus() && !suppressed(e);
        }

        function isLive() {
            if (!baseLive()) {
                releasePointerBinding(binding);
                releaseKeyboardBinding(binding);
                removeTooltipDescription();
                return false;
            }
            // DOM 替换不会可靠地产生 focusout。恢复前只信任真实 activeElement，
            // 不维护另一份 focusWithin 布尔状态。
            if (_keyboardAsyncBinding === binding && !hasDocumentFocus()) {
                releaseKeyboardBinding(binding);
                removeTooltipDescription();
            }
            return canOwnPointer(lastPointerEvent, true)
                || canOwnKeyboard({target:node, currentTarget:node});
        }

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
            if (!isLive() || activeKey !== key || !isVisible(owner)
                    || typeof options.renderRich !== 'function') return;
            updateContent(options.renderRich(activeItem, response), owner);
        }

        function renderFailureIfCurrent(key, response) {
            if (!isLive() || activeKey !== key || !isVisible(owner)
                    || typeof options.renderFailure !== 'function') return;
            updateContent(options.renderFailure(activeItem, response), owner);
        }

        function requestRich(key, item) {
            if (cache[key] || pending[key] || typeof options.fetch !== 'function') return;
            var requestId = ++requestSequence;
            pending[key] = requestId;
            try {
                options.fetch(item, function(response) {
                    if (disposed || pending[key] !== requestId) return;
                    delete pending[key];
                    if (!response || response.success !== true) {
                        renderFailureIfCurrent(key, response);
                        return;
                    }
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

        function suspendOtherKeyboardDescription() {
            var keyboard = _keyboardAsyncBinding;
            if (keyboard && keyboard !== binding && keyboard.suspendDescription) {
                keyboard.suspendDescription();
            }
        }

        function showCurrent(event, source) {
            var pointerSource = source === 'pointer';
            if (pointerSource) {
                if (!canOwnPointer(event, false)) return false;
                suspendOtherKeyboardDescription();
            } else {
                var pointer = _pointerAsyncBinding;
                if (pointer && pointer.canRestorePointer && pointer.canRestorePointer()) return false;
                if (pointer) _pointerAsyncBinding = null;
                if (!canOwnKeyboard(event)) return false;
                addTooltipDescription();
            }
            var key = resolveKey(event);
            var item = resolveItem(event);
            activeKey = key;
            activeItem = item;
            var html = cache[key] && typeof options.renderRich === 'function'
                ? options.renderRich(item, cache[key])
                : (typeof options.renderBasic === 'function' ? options.renderBasic(item) : '');
            if (pointerSource) showAtMouse(html, lastPointerEvent || event, owner);
            else showAnchored(html, node, { autoClose: 0, outsideClick: false, owner: owner });
            setInteraction(owner, {enter:onTooltipEnter, leave:onTooltipLeave});
            requestRich(key, item);
            return true;
        }

        function hideOwnedTooltip() {
            clearInteraction(owner);
            return hide(owner);
        }

        function clearPointerState() {
            clearLeaveTimer();
            activePointers = {};
            tooltipHovered = false;
            lastPointerEvent = null;
            releasePointerBinding(binding);
        }

        function clearCurrentAndRestore() {
            activeKey = null;
            activeItem = null;
            if (hideOwnedTooltip()) restoreOwnedBinding(null);
        }

        function finishPointerLeave() {
            leaveTimer = null;
            // enter 事件可能来自浮层重排到静止指针之下；只有同一 show generation
            // 内由真实 move 确认、且最终 hit-test 仍落在 tooltip，才保留复合 hover。
            if (tooltipHovered && !pointerTargetsTooltip()) {
                tooltipHovered = false;
                resetTooltipHover(false);
            }
            if (hasActivePointer() || tooltipHovered) return;
            // 迟到的 A timer 不能在 pointer B 已接管后隐藏 B 或把 keyboard A
            // 提前覆盖回来；A 仍保留为 keyboard owner，等 B 的真实终态统一恢复。
            if (_pointerAsyncBinding !== binding) {
                lastPointerEvent = null;
                return;
            }
            releasePointerBinding(binding);
            lastPointerEvent = null;
            if (_keyboardAsyncBinding === binding
                    && showCurrent({target:node, currentTarget:node}, 'keyboard')) return;
            clearCurrentAndRestore();
        }

        function schedulePointerLeave() {
            clearLeaveTimer();
            leaveTimer = setTimeout(finishPointerLeave, 140);
        }

        function onTooltipEnter() {
            if (disposed || !isVisible(owner) || _pointerAsyncBinding !== binding
                    || !isLive()) return false;
            clearLeaveTimer();
            tooltipHovered = true;
            claimPointerBinding(binding);
            return true;
        }

        function onTooltipLeave() {
            if (disposed) return;
            tooltipHovered = false;
            if (!hasActivePointer()) schedulePointerLeave();
        }

        function onEnter(e) {
            if (disposed) return;
            if (suppressed(e)) {
                clearPointerState();
                clearCurrentAndRestore();
                return;
            }
            clearLeaveTimer();
            keyboardDismissed = false;
            var pointerId = pointerIdOf(e);
            activePointers[pointerId] = true;
            claimPointerBinding(binding);
            lastPointerEvent = pointerSnapshot(e);
            showCurrent(e, 'pointer');
        }

        function onMove(e) {
            if (disposed) return;
            if (nestedBindingOwns(e)) return;   // 冒泡自嵌套绑定后代：不抢 owner
            var pointerId = pointerIdOf(e);
            if (!activePointers[pointerId]) return;
            lastPointerEvent = pointerSnapshot(e);
            if (suppressed(e)) {
                clearPointerState();
                clearCurrentAndRestore();
                return;
            }
            claimPointerBinding(binding);
            if (!isVisible(owner)) showCurrent(e, 'pointer');
            else followMouse(e, owner);
        }

        function onLeave(e) {
            var pointerId = pointerIdOf(e);
            if (!activePointers[pointerId]) return;
            delete activePointers[pointerId];
            if (hasActivePointer()) return;
            schedulePointerLeave();
        }

        function onPointerCancel(e) {
            var pointerId = pointerIdOf(e);
            delete activePointers[pointerId];
            if (hasActivePointer()) return;
            clearPointerState();
            clearCurrentAndRestore();
        }

        function onFocusIn(e) {
            if (disposed || (e.relatedTarget && node.contains(e.relatedTarget))) return;
            if (nestedBindingOwns(e)) return;   // 焦点落在嵌套绑定后代：由后代自己处理
            if (_inputModality !== 'keyboard') {
                releaseKeyboardBinding(binding);
                removeTooltipDescription();
                return;
            }
            if (suppressed(e)) {
                clearPointerState();
                releaseKeyboardBinding(binding);
                removeTooltipDescription();
                clearCurrentAndRestore();
                return;
            }
            keyboardDismissed = false;
            claimKeyboardBinding(binding);
            var pointer = _pointerAsyncBinding;
            if (pointer && pointer.canRestorePointer && pointer.canRestorePointer()) {
                if (pointer === binding) addTooltipDescription();
                else removeTooltipDescription();
                return;
            }
            if (pointer) _pointerAsyncBinding = null;
            showCurrent(e, 'keyboard');
        }

        function onFocusOut(e) {
            if (e.relatedTarget && node.contains(e.relatedTarget)) return;
            keyboardDismissed = false;
            releaseKeyboardBinding(binding);
            removeTooltipDescription();
            if (canOwnPointer(lastPointerEvent, false)) {
                showCurrent(lastPointerEvent || e, 'pointer');
                return;
            }
            clearCurrentAndRestore();
        }

        function onKeyDown(e) {
            if (e.key === 'Escape') {
                // 只消费当前由本 binding 展示的 tooltip。DOM focus 可能由鼠标点击
                // 留在一个已隐藏 owner，或 keyboard A 正被 pointer B 覆盖；这两种
                // 情况必须把 Escape 交给面板/模态层，不能截断上层关闭语义。
                if (!isVisible(owner)) return;
                keyboardDismissed = true;
                clearPointerState();
                releaseKeyboardBinding(binding);
                removeTooltipDescription();
                clearCurrentAndRestore();
                e.preventDefault();
                e.stopPropagation();
                return;
            }
            if (suppressed(e)) {
                clearPointerState();
                releaseKeyboardBinding(binding);
                removeTooltipDescription();
                clearCurrentAndRestore();
                return;
            }
            if (!keyboardDismissed && _inputModality === 'keyboard'
                    && hasDocumentFocus()) {
                claimKeyboardBinding(binding);
                var pointer = _pointerAsyncBinding;
                if (!pointer || !(pointer.canRestorePointer && pointer.canRestorePointer())) {
                    var switchingFromPointer = !!pointer;
                    if (pointer) _pointerAsyncBinding = null;
                    if (switchingFromPointer || !isVisible(owner)) showCurrent(e, 'keyboard');
                    else addTooltipDescription();
                } else if (pointer === binding) {
                    addTooltipDescription();
                }
            }
            if (!isVisible(owner)) return;
            var desc = scrollableDescription();
            if (!desc) return;
            var handled = true;
            var page = Math.max(40, Math.floor(desc.clientHeight * 0.8));
            if (e.key === 'PageDown') desc.scrollTop += page;
            else if (e.key === 'PageUp') desc.scrollTop -= page;
            else if (e.altKey && e.key === 'ArrowDown') desc.scrollTop += 40;
            else if (e.altKey && e.key === 'ArrowUp') desc.scrollTop -= 40;
            else handled = false;
            if (handled) {
                e.preventDefault();
                e.stopPropagation();
            }
        }

        var hasPointerEvent = typeof window !== 'undefined' && typeof window.PointerEvent === 'function';
        var useMouse = options.events === 'mouse' || (!hasPointerEvent && options.events !== 'pointer');
        var enterEvent = useMouse ? 'mouseenter' : 'pointerenter';
        var moveEvent = useMouse ? 'mousemove' : 'pointermove';
        var leaveEvent = useMouse ? 'mouseleave' : 'pointerleave';
        var cancelEvent = useMouse ? null : 'pointercancel';
        node.addEventListener(enterEvent, onEnter);
        node.addEventListener(moveEvent, onMove);
        node.addEventListener(leaveEvent, onLeave);
        if (cancelEvent) node.addEventListener(cancelEvent, onPointerCancel);
        node.addEventListener('focusin', onFocusIn);
        node.addEventListener('focusout', onFocusOut);
        node.addEventListener('keydown', onKeyDown);

        binding = {
            scope: scope,
            canRestorePointer: function() {
                return !!lastPointerEvent && canOwnPointer(lastPointerEvent, false);
            },
            restorePointer: function() {
                return showCurrent(lastPointerEvent, 'pointer');
            },
            canRestoreKeyboard: function() {
                return canOwnKeyboard({target:node, currentTarget:node});
            },
            restoreKeyboard: function() {
                return showCurrent({target:node, currentTarget:node}, 'keyboard');
            },
            suspendDescription: function() {
                removeTooltipDescription();
            },
            revokeKeyboardFromPointer: function() {
                releaseKeyboardBinding(binding);
                removeTooltipDescription();
                if (canOwnPointer(lastPointerEvent, false)) return;
                clearCurrentAndRestore();
            },
            abandonInputOwners: function() {
                keyboardDismissed = true;
                clearPointerState();
                releaseKeyboardBinding(binding);
                removeTooltipDescription();
                clearInteraction(owner);
            },
            destroy: function() {
                if (disposed) return false;
                disposed = true;
                requestSequence++;
                pending = {};
                clearLeaveTimer();
                tooltipHovered = false;
                clearInteraction(owner);
                node.removeEventListener(enterEvent, onEnter);
                node.removeEventListener(moveEvent, onMove);
                node.removeEventListener(leaveEvent, onLeave);
                if (cancelEvent) node.removeEventListener(cancelEvent, onPointerCancel);
                node.removeEventListener('focusin', onFocusIn);
                node.removeEventListener('focusout', onFocusOut);
                node.removeEventListener('keydown', onKeyDown);
                activePointers = {};
                releasePointerBinding(binding);
                releaseKeyboardBinding(binding);
                activeKey = null;
                activeItem = null;
                removeTooltipDescription();
                removeFromArray(_allAsyncBindings, binding);
                if (scope) removeFromArray(scope.bindings, binding);
                if (hideOwnedTooltip()) restoreOwnedBinding(binding);
                if (node.__panelTooltipBinding === binding) node.__panelTooltipBinding = null;
                return true;
            },
            refresh: function() {
                if (canOwnPointer(lastPointerEvent, false)) showCurrent(lastPointerEvent, 'pointer');
                else if (canOwnKeyboard({target:node, currentTarget:node})) {
                    showCurrent({target:node, currentTarget:node}, 'keyboard');
                }
            },
            isConnected: function() { return isNodeConnected(node); }
        };
        node.__panelTooltipBinding = binding;
        _allAsyncBindings.push(binding);
        if (scope) scope.bindings.push(binding);
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
        hideHover: hideHover,
        createScope: createScope,
        releaseTree: releaseTree,
        debugState: debugState,
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
