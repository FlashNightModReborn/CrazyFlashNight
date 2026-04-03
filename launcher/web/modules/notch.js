var Notch = (function() {
    'use strict';
    var notchEl, pillEl, fpsEl, sparkCanvas;
    var clockCanvas, clockCtx, toolbarEl, infoContainer, expandBtn;
    var perfBadgeEl, statsEl, expandedPanel, expandedCanvas;
    var expanded = false, fpsValue = 0, fpsPoints = [], gameHour = 6;
    var perfLevel = 0;
    var autoHideTimer = null;
    var rows = [], TRANSIENT_MS = 4000, MAX_ROWS = 4;
    var lightLevels = null, MAX_LIGHT = 9;
    var expandCooldown = false;
    var _reportRect = null; // init() 后赋值，供外部调用

    // SparklineRenderer 实例
    var sparkRenderer = null;

    // 全量历史（客户端累积，用于展开大图）
    var fullHistory = [];
    var MAX_HISTORY = 300;

    // 展开图状态
    var chartVisible = false;

    // tooltip 元素
    var tooltipEl = null;

    // 动态主题
    var currentThemeClass = '';

    // perfLevel 描述
    var PERF_DESCS = [
        'L0: 正常 — 全特效',
        'L1: 轻度降级 — 减少粒子',
        'L2: 中度降级 — 跳过贝塞尔曲线',
        'L3: 高压 — 最小化渲染'
    ];

    // ── FPS 抖动检测 ──
    var prevFpsGood = true; // 上次是否 ≥18fps

    function init() {
        notchEl = document.getElementById('notch');
        pillEl = document.getElementById('notch-pill');
        fpsEl = document.getElementById('notch-fps');
        sparkCanvas = document.getElementById('notch-sparkline');
        clockCanvas = document.getElementById('notch-clock');
        toolbarEl = document.getElementById('notch-toolbar');
        infoContainer = document.getElementById('notch-info');
        expandBtn = document.getElementById('notch-expand');
        perfBadgeEl = document.getElementById('notch-perf-badge');
        statsEl = document.getElementById('notch-stats');
        expandedPanel = document.getElementById('notch-expanded-panel');
        expandedCanvas = document.getElementById('notch-expanded-canvas');

        // 创建 SparklineRenderer（处理 DPR + 离屏缓存 + 动画）
        sparkRenderer = SparklineRenderer.create(sparkCanvas, 70, 16);

        // 时钟 canvas DPR
        clockCtx = SparklineRenderer.setupHiDpi(clockCanvas, 16, 16);

        // DPR 变化时重建时钟 canvas
        (function watchClockDpr() {
            var mql = window.matchMedia('(resolution: ' + SparklineRenderer.currentDpr() + 'dppx)');
            var handler = function() {
                clockCtx = SparklineRenderer.setupHiDpi(clockCanvas, 16, 16);
                drawClock();
                watchClockDpr();
            };
            if (mql.addEventListener) mql.addEventListener('change', handler, { once: true });
            else if (mql.addListener) mql.addListener(function f() { mql.removeListener(f); handler(); });
        })();

        // 创建 tooltip 元素
        tooltipEl = document.createElement('div');
        tooltipEl.className = 'spark-tooltip';
        tooltipEl.style.display = 'none';
        document.body.appendChild(tooltipEl);

        // 冷启动 ghost baseline：预填标称帧率（后续 merge 而非替换）
        fpsPoints = [];
        for (var fi = 0; fi < 24; fi++) fpsPoints.push(30);

        pillEl.addEventListener('mouseenter', doExpand);
        notchEl.addEventListener('mouseleave', startAutoHide);
        notchEl.addEventListener('mouseenter', cancelAutoHide);
        expandBtn.addEventListener('click', function() {
            if (expanded) doCollapse(); else doExpand();
        });

        // 绑定所有 data-key 按钮
        var buttons = document.querySelectorAll('#notch button[data-key], #top-right-tools button[data-key]');
        for (var i = 0; i < buttons.length; i++) {
            (function(btn) {
                btn.addEventListener('click', function() {
                    Bridge.send({ type: 'click', key: btn.getAttribute('data-key') });
                });
            })(buttons[i]);
        }

        // submenu hover → 更新 hitRect
        var submenuWraps = document.querySelectorAll('.notch-submenu-wrap');
        for (var si = 0; si < submenuWraps.length; si++) {
            (function(wrap) {
                wrap.addEventListener('mouseenter', function() {
                    cancelAutoHide();
                    setTimeout(reportRect, 50);
                });
                wrap.addEventListener('mouseleave', function() {
                    setTimeout(reportRect, 50);
                });
            })(submenuWraps[si]);
        }

        // sparkline 悬停 tooltip
        sparkCanvas.addEventListener('mousemove', onSparkMouseMove);
        sparkCanvas.addEventListener('mouseleave', onSparkMouseLeave);

        // sparkline 点击 → 展开/收起详细图
        sparkCanvas.addEventListener('click', toggleExpandedChart);

        // 展开图点击关闭
        if (expandedPanel) {
            expandedPanel.addEventListener('click', function() {
                hideExpandedChart();
            });
        }

        // 暂停状态
        UiData.on('p', function(val) {
            var pb = document.getElementById('notch-pause');
            if (!pb) return;
            var paused = (val === '1');
            pb.textContent = paused ? '\u25B6' : '\u23F8';
            if (paused) pb.classList.add('paused');
            else pb.classList.remove('paused');
        });

        // 主线任务进度
        UiData.on('q', function(val) {
            var progress = parseInt(val, 10) || 0;
            var btn = document.querySelector('[data-key="WAREHOUSE"]');
            if (btn) btn.style.display = progress > 13 ? '' : 'none';
        });

        // 游戏状态：s:0=未加载 s:1=已进入
        // 用 CSS class 控制，比 inline style 更可靠
        UiData.on('s', function(val) {
            if (val === '1') notchEl.classList.add('game-ready');
            else notchEl.classList.remove('game-ready');
            // 可交互区域几何形状已变（toolbar/center/pause 显隐），重报 hitRect
            setTimeout(reportRect, 50);
        });
        // 初始态：未加载（无 .game-ready → CSS 隐藏 toolbar + pause）

        Bridge.on('fps', onFpsData);
        Bridge.on('lightLevels', function(data) {
            if (data.levels) lightLevels = data.levels;
        });
        window.addEventListener('resize', reportRect);
        reportRect();

        // 初始渲染
        sparkRenderer.startAnim(fpsPoints, perfLevel, gameHour, lightLevels);
        drawClock();
    }

    // ── FPS 文本更新 ──
    function updateFpsText() {
        if (fpsEl) fpsEl.textContent = expanded ? fpsValue.toFixed(1) : Math.round(fpsValue);
    }

    // ── 展开/收起 ──
    var row1Right = null; // 缓存引用
    function getRow1Right() {
        if (!row1Right) row1Right = document.getElementById('notch-row1-right');
        return row1Right;
    }
    function doExpand() {
        if (expandCooldown) return;
        expanded = true;
        notchEl.classList.add('expanded');
        cancelAutoHide();
        updateFpsText();
        // 展开过渡结束后解除 overflow:hidden，让子菜单下拉可见
        var r1r = getRow1Right();
        if (r1r) setTimeout(function() { if (expanded) r1r.style.overflow = 'visible'; }, 320);
        setTimeout(reportRect, 180);
    }
    function doCollapse() {
        expanded = false;
        expandCooldown = true;
        setTimeout(function() { expandCooldown = false; }, 600);
        // 立即恢复 overflow:hidden，让收起动画正确裁剪
        var r1r = getRow1Right();
        if (r1r) r1r.style.overflow = '';
        notchEl.classList.remove('expanded');
        updateFpsText();
        hideExpandedChart();
        setTimeout(reportRect, 180);
    }
    function startAutoHide() {
        cancelAutoHide();
        autoHideTimer = setTimeout(doCollapse, 500);
    }
    function cancelAutoHide() {
        if (autoHideTimer) { clearTimeout(autoHideTimer); autoHideTimer = null; }
    }

    // ── hitRect 上报 ──
    function reportRect() {
        var rects = [];
        function pushRect(el) {
            var r = el.getBoundingClientRect();
            if (r.width > 0 && r.height > 0)
                rects.push(Math.round(r.left), Math.round(r.top),
                           Math.round(r.width), Math.round(r.height));
        }
        pushRect(expanded ? notchEl : pillEl);
        var trt = document.getElementById('top-right-tools');
        if (trt && trt.offsetParent !== null) pushRect(trt);
        var jbp = document.getElementById('jukebox-panel');
        if (jbp && jbp.offsetParent !== null) pushRect(jbp);
        var subs = document.querySelectorAll('.notch-submenu');
        for (var si = 0; si < subs.length; si++) {
            if (subs[si].offsetParent !== null) pushRect(subs[si]);
        }
        if (chartVisible && expandedPanel) pushRect(expandedPanel);
        Bridge.send({ type: 'interactiveRect', r: rects });
    }
    _reportRect = reportRect;

    // ── FPS 数据接收 ──
    function onFpsData(data) {
        fpsValue = data.value || 0;
        gameHour = (typeof data.hour === 'number') ? data.hour : 6;

        // ★ 修复 cold-start：merge 而非替换
        if (data.points) {
            var incoming = data.points;
            if (fpsPoints.length === 24 && incoming.length < 24) {
                // 用真实数据从尾部覆盖 ghost baseline
                var padded = fpsPoints.slice();
                var offset = 24 - incoming.length;
                for (var pi = 0; pi < incoming.length; pi++) {
                    padded[offset + pi] = incoming[pi];
                }
                fpsPoints = padded;
            } else {
                fpsPoints = incoming;
            }
        }

        if (typeof data.level === 'number') {
            var oldLevel = perfLevel;
            perfLevel = data.level;
            if (oldLevel !== perfLevel) onPerfLevelChange(oldLevel, perfLevel);
        }

        // 累积全量历史：首次收到 data.points 时回填，避免展开图启动空窗
        if (data.points && fullHistory.length === 0) {
            for (var hi = 0; hi < data.points.length; hi++) {
                fullHistory.push(data.points[hi]);
            }
        }
        fullHistory.push(fpsValue);
        if (fullHistory.length > MAX_HISTORY) fullHistory.shift();

        updateFpsText();

        // FPS 跌破阈值抖动（必须在 className= 之前检测，之后补回）
        var fpsGood = (fpsValue >= 18);
        var shouldShake = (prevFpsGood && !fpsGood);
        prevFpsGood = fpsGood;

        // 颜色 class
        fpsEl.className = 'notch-fps ' + (
            fpsValue >= 25 ? 'fps-good' : fpsValue >= 18 ? 'fps-warn' : 'fps-bad');

        if (shouldShake) {
            fpsEl.classList.add('fps-shake');
            setTimeout(function() { fpsEl.classList.remove('fps-shake'); }, 400);
        }

        updatePerfBadge();
        updateStats();
        updateTheme();

        // 渲染（带动画过渡）
        sparkRenderer.startAnim(fpsPoints, perfLevel, gameHour, lightLevels);
        drawClock();

        // 如果展开图可见，同步更新
        if (chartVisible && expandedCanvas) {
            sparkRenderer.renderExpanded(expandedCanvas, fullHistory, gameHour, lightLevels, perfLevel);
        }
    }

    // ── 性能等级变化 → badge pulse ──
    var lastBadgeLevel = -1;
    function onPerfLevelChange(oldLevel, newLevel) {
        if (!perfBadgeEl) return;
        perfBadgeEl.classList.remove('badge-pulse');
        void perfBadgeEl.offsetWidth; // 强制 reflow 重启动画
        perfBadgeEl.classList.add('badge-pulse');

        // sparkline 边框闪光：升级=绿, 降级=黄
        if (sparkCanvas) {
            var isUpgrade = newLevel < oldLevel;
            var glowColor = isUpgrade ? '#66ff66' : '#ffcc00';
            sparkCanvas.style.boxShadow = '0 0 6px 2px ' + glowColor;
            sparkCanvas.style.transition = 'box-shadow 0.15s ease-in';
            clearTimeout(sparkCanvas._glowTimer);
            sparkCanvas._glowTimer = setTimeout(function() {
                sparkCanvas.style.transition = 'box-shadow 1.2s ease-out';
                sparkCanvas.style.boxShadow = 'none';
            }, 300);
        }
    }

    function updatePerfBadge() {
        if (!perfBadgeEl) return;
        perfBadgeEl.textContent = 'L' + perfLevel;
        // 只在等级变化时更新颜色 class，避免 className= 清掉 badge-pulse
        if (lastBadgeLevel !== perfLevel) {
            var hasPulse = perfBadgeEl.classList.contains('badge-pulse');
            perfBadgeEl.className = 'perf-badge perf-L' + perfLevel;
            if (hasPulse) perfBadgeEl.classList.add('badge-pulse');
            lastBadgeLevel = perfLevel;
        }
        perfBadgeEl.title = PERF_DESCS[perfLevel] || ('L' + perfLevel);
    }

    // 缓存统计结果供 tooltip 使用
    var cachedStats = null;
    var cachedFullStats = null;

    function updateStats() {
        if (!statsEl || fpsPoints.length < 2) return;
        cachedStats = SparklineRenderer.computeStats(fpsPoints);
        if (fullHistory.length >= 10) {
            cachedFullStats = SparklineRenderer.computeStats(fullHistory);
        }
        // 一级展示：时钟旁显示游戏时间（与时钟图标语义一致）
        var h = Math.floor(gameHour);
        var m = Math.floor((gameHour - h) * 60);
        statsEl.textContent = (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
    }

    // ── 动态主题：根据光照等级调整 notch 透明度 ──
    function updateTheme() {
        if (!lightLevels || lightLevels.length < 24) return;
        var hr = Math.floor(gameHour) % 24;
        var level = lightLevels[hr] || 0;
        // level 0-9: 0=最暗(夜), 9=最亮(日)
        var theme;
        if (level >= 7) theme = 'theme-day';
        else if (level >= 4) theme = 'theme-dusk';
        else theme = 'theme-night';

        if (theme !== currentThemeClass) {
            notchEl.classList.remove('theme-day', 'theme-dusk', 'theme-night');
            notchEl.classList.add(theme);
            currentThemeClass = theme;
        }
    }

    // ── Sparkline tooltip（向下展开，含详细统计） ──
    function buildTooltipHTML(fps, idx) {
        var ft = fps > 0 ? (1000 / fps).toFixed(1) : '∞';
        // 第一行：当前点
        var lines = [
            '<b>' + fps.toFixed(1) + ' fps</b>  ' + ft + 'ms  [' + (idx + 1) + '/' + fpsPoints.length + ']'
        ];
        // 第二行：窗口统计
        if (cachedStats) {
            lines.push(
                '<span class="tip-dim">lo:</span>' + cachedStats.lo.toFixed(1) +
                ' <span class="tip-dim">hi:</span>' + cachedStats.hi.toFixed(1) +
                ' <span class="tip-dim">avg:</span>' + cachedStats.avg.toFixed(1)
            );
        }
        // 第三行：全量 frametime 百分位
        if (cachedFullStats) {
            var ftP95 = cachedFullStats.p5Low > 0 ? (1000 / cachedFullStats.p5Low).toFixed(1) : '∞';
            var ftP99 = cachedFullStats.p1Low > 0 ? (1000 / cachedFullStats.p1Low).toFixed(1) : '∞';
            lines.push(
                '<span class="tip-dim">ft P95:</span>' + ftP95 +
                'ms <span class="tip-dim">P99:</span>' + ftP99 + 'ms' +
                ' <span class="tip-dim">(' + fullHistory.length + ' samples)</span>'
            );
        }
        return lines.join('<br>');
    }

    function onSparkMouseMove(e) {
        var rect = sparkCanvas.getBoundingClientRect();
        var mouseX = e.clientX - rect.left;
        var idx = sparkRenderer.hitTest(mouseX);
        if (idx < 0 || idx >= fpsPoints.length) {
            onSparkMouseLeave();
            return;
        }
        sparkRenderer.setTooltipIdx(idx);
        sparkRenderer.render(fpsPoints, perfLevel, gameHour, lightLevels);

        var fps = fpsPoints[idx];
        tooltipEl.innerHTML = buildTooltipHTML(fps, idx);
        tooltipEl.style.display = 'block';

        // 定位：canvas 下方（向下展开）
        var tipW = tooltipEl.offsetWidth;
        var tipX = rect.left + mouseX - tipW / 2;
        if (tipX < 2) tipX = 2;
        if (tipX + tipW > window.innerWidth - 2) tipX = window.innerWidth - tipW - 2;
        tooltipEl.style.left = tipX + 'px';
        tooltipEl.style.top = (rect.bottom + 4) + 'px';
    }

    function onSparkMouseLeave() {
        sparkRenderer.setTooltipIdx(-1);
        sparkRenderer.render(fpsPoints, perfLevel, gameHour, lightLevels);
        tooltipEl.style.display = 'none';
    }

    // ── 展开图 ──
    function toggleExpandedChart() {
        if (chartVisible) hideExpandedChart();
        else showExpandedChart();
    }
    function showExpandedChart() {
        if (!expandedPanel || !expandedCanvas) return;
        chartVisible = true;
        expandedPanel.style.display = 'block';
        requestAnimationFrame(function() {
            expandedPanel.classList.add('visible');
            sparkRenderer.renderExpanded(expandedCanvas, fullHistory, gameHour, lightLevels, perfLevel);
            reportRect();
        });
    }
    function hideExpandedChart() {
        if (!expandedPanel) return;
        chartVisible = false;
        expandedPanel.classList.remove('visible');
        setTimeout(function() {
            expandedPanel.style.display = 'none';
            reportRect();
        }, 250);
    }

    // ── 时钟绘制（含扇形高亮） ──
    function drawClock() {
        var w = 16, h = 16;
        var cx = w / 2, cy = h / 2, r = Math.min(cx, cy) - 1;
        clockCtx.clearRect(0, 0, w, h);

        var hr = Math.floor(gameHour) % 24;
        var faceColor, rimColor, handColor;
        if (hr >= 5 && hr <= 17) {
            faceColor = 'rgba(180,170,100,0.2)';
            rimColor = 'rgba(200,190,120,0.7)';
            handColor = 'rgba(240,230,160,0.86)';
        } else if ((hr >= 3 && hr <= 4) || (hr >= 18 && hr <= 20)) {
            faceColor = 'rgba(200,140,60,0.2)';
            rimColor = 'rgba(220,160,80,0.63)';
            handColor = 'rgba(240,180,100,0.78)';
        } else {
            faceColor = 'rgba(100,120,180,0.16)';
            rimColor = 'rgba(130,150,200,0.55)';
            handColor = 'rgba(160,180,220,0.7)';
        }

        // 表盘填充
        clockCtx.beginPath();
        clockCtx.arc(cx, cy, r, 0, Math.PI * 2);
        clockCtx.fillStyle = faceColor;
        clockCtx.fill();

        // 扇形高亮：当前小时在 24h 表盘上的 1h 扇区
        var sectorStart = (gameHour / 24) * Math.PI * 2 - Math.PI / 2;
        var sectorEnd = sectorStart + (1 / 24) * Math.PI * 2;
        clockCtx.beginPath();
        clockCtx.moveTo(cx, cy);
        clockCtx.arc(cx, cy, r * 0.85, sectorStart, sectorEnd);
        clockCtx.closePath();
        clockCtx.fillStyle = 'rgba(255,255,200,0.18)';
        clockCtx.fill();

        // 外圈
        clockCtx.beginPath();
        clockCtx.arc(cx, cy, r, 0, Math.PI * 2);
        clockCtx.strokeStyle = rimColor;
        clockCtx.lineWidth = 1.2;
        clockCtx.stroke();

        // 时针
        var hour12 = gameHour % 12;
        var ha = (hour12 / 12) * Math.PI * 2 - Math.PI / 2;
        clockCtx.beginPath();
        clockCtx.moveTo(cx, cy);
        clockCtx.lineTo(cx + Math.cos(ha) * r * 0.5, cy + Math.sin(ha) * r * 0.5);
        clockCtx.strokeStyle = handColor;
        clockCtx.lineWidth = 2;
        clockCtx.lineCap = 'round';
        clockCtx.stroke();

        // 分针
        var minFrac = gameHour - Math.floor(gameHour);
        var ma = minFrac * Math.PI * 2 - Math.PI / 2;
        clockCtx.beginPath();
        clockCtx.moveTo(cx, cy);
        clockCtx.lineTo(cx + Math.cos(ma) * r * 0.8, cy + Math.sin(ma) * r * 0.8);
        clockCtx.strokeStyle = handColor;
        clockCtx.lineWidth = 1;
        clockCtx.stroke();
    }

    // === 游戏通知防洪 ===
    var GAME_CAT = 'game';
    var GAME_TRANSIENT_MS = 3000;
    var gameQueue = [];
    var gameThrottleTimer = null;
    var GAME_THROTTLE_MS = 350;

    function addNotice(category, text, color) {
        if (category === GAME_CAT) {
            addGameNotice(text, color);
            return;
        }
        upsertRow(category, text, color, false);
    }

    function addGameNotice(text, color) {
        for (var i = 0; i < gameQueue.length; i++) {
            if (gameQueue[i].text === text) {
                gameQueue[i].count++;
                return;
            }
        }
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].baseText === text && rows[i].isGame) {
                var row = rows[i];
                row.count = (row.count || 1) + 1;
                row.el.textContent = text + ' x' + row.count;
                pulseCount(row.el);
                if (row.rt) clearTimeout(row.rt);
                var rowId = row.id;
                row.rt = setTimeout(function(){ removeRow(rowId); }, GAME_TRANSIENT_MS);
                return;
            }
        }
        gameQueue.push({ text: text, color: color, count: 1 });
        drainGameQueue();
    }

    function drainGameQueue() {
        if (gameThrottleTimer || gameQueue.length === 0) return;
        var item = gameQueue.shift();
        var displayText = item.count > 1 ? item.text + ' x' + item.count : item.text;
        var uid = GAME_CAT + '_' + Date.now();
        upsertGameRow(uid, displayText, item.text, item.color, item.count);
        if (gameQueue.length > 0) {
            gameThrottleTimer = setTimeout(function() {
                gameThrottleTimer = null;
                drainGameQueue();
            }, GAME_THROTTLE_MS);
        }
    }

    // 强制浏览器在初始态渲染一帧后再加 .visible，确保 transition 触发
    function animateIn(el) {
        void el.offsetHeight; // 强制 reflow：让浏览器记录 max-height:0 初始态
        el.classList.add('visible');
    }

    function upsertGameRow(id, displayText, baseText, color, count) {
        var el = document.createElement('div');
        el.className = 'notch-info-row game-notify';
        el.textContent = displayText;
        el.style.color = color;
        var row = {id:id, text:displayText, baseText:baseText, color:color,
                   persistent:false, el:el, rt:null, isGame:true, count:count};
        row.rt = setTimeout(function(){ removeRow(id); }, GAME_TRANSIENT_MS);
        rows.push(row);
        infoContainer.appendChild(el);
        var gameRows = 0;
        for (var j = 0; j < rows.length; j++) { if (rows[j].isGame) gameRows++; }
        while (gameRows > 4) {
            for (var j = 0; j < rows.length; j++) {
                if (rows[j].isGame) { collapseRow(rows[j]); rows.splice(j,1); gameRows--; break; }
            }
        }
        animateIn(el);
    }

    function setStatus(id, text, color) { upsertRow(id, text, color, true); }
    function clearStatus(id) {
        for (var i = rows.length-1; i >= 0; i--) {
            if (rows[i].id === id) { collapseRow(rows[i]); rows.splice(i,1); break; }
        }
    }

    function upsertRow(id, text, color, persistent) {
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === id) {
                if (rows[i].text !== text) {
                    rows[i].text = text;
                    rows[i].el.textContent = text;
                }
                rows[i].el.style.color = color;
                // 同步 accent 左边条颜色（状态行模式切换时 color 会变）
                if (persistent) rows[i].el.style.setProperty('--accent', color);
                if (!persistent && rows[i].rt) {
                    clearTimeout(rows[i].rt);
                    rows[i].rt = setTimeout(function(){removeRow(id);}, TRANSIENT_MS);
                }
                return;
            }
        }
        var el = document.createElement('div');
        // 状态行（持久）加 accent 左边条 + 区分样式
        if (persistent) {
            el.className = 'notch-info-row status-row';
            el.style.setProperty('--accent', color);
        } else {
            el.className = 'notch-info-row';
        }
        el.textContent = text;
        el.style.color = color;
        var row = {id:id, text:text, color:color, persistent:persistent, el:el, rt:null};
        if (!persistent) row.rt = setTimeout(function(){removeRow(id);}, TRANSIENT_MS);
        rows.push(row);
        infoContainer.appendChild(el);
        while (rows.length > MAX_ROWS) {
            var v = null;
            for (var j = rows.length-1; j >= 0; j--) { if (!rows[j].persistent) {v=j; break;} }
            if (v === null) break;
            collapseRow(rows[v]); rows.splice(v,1);
        }
        animateIn(el);
    }

    function removeRow(id) {
        for (var i = rows.length-1; i >= 0; i--) {
            if (rows[i].id === id) { collapseRow(rows[i]); rows.splice(i,1); break; }
        }
    }

    // 两阶段退场：fade(180ms) → collapse(220ms) → DOM remove
    function collapseRow(row) {
        if (row.rt) clearTimeout(row.rt);
        var el = row.el;
        el.classList.remove('visible');
        el.classList.add('fading');
        setTimeout(function() {
            el.classList.remove('fading');
            el.classList.add('collapsing');
            setTimeout(function() {
                if (el.parentNode) el.parentNode.removeChild(el);
            }, 230); // ≥ collapsing transition 220ms
        }, 190); // ≥ fading transition 180ms
    }

    // 计数更新脉冲
    function pulseCount(el) {
        el.classList.remove('count-pulse');
        void el.offsetWidth;
        el.classList.add('count-pulse');
    }

    window.addEventListener('load', init);
    return { addNotice:addNotice, setStatus:setStatus, clearStatus:clearStatus, reportRect:function(){ if(_reportRect) _reportRect(); } };
})();
