var Notch = (function() {
    'use strict';
    var notchEl, pillEl, fpsEl, sparkCanvas, sparkCtx;
    var clockCanvas, clockCtx, toolbarEl, infoContainer, expandBtn;
    var expanded = false, fpsValue = 0, fpsPoints = [], gameHour = 6; // 对齐 WeatherSystem.currentTime 初始值
    var autoHideTimer = null;
    var rows = [], TRANSIENT_MS = 4000, MAX_ROWS = 4;
    var lightLevels = null, MAX_LIGHT = 9;
    var expandCooldown = false; // 收起后冷却期，防止振荡

    function init() {
        notchEl = document.getElementById('notch');
        pillEl = document.getElementById('notch-pill');
        fpsEl = document.getElementById('notch-fps');
        sparkCanvas = document.getElementById('notch-sparkline');
        sparkCtx = sparkCanvas.getContext('2d');
        clockCanvas = document.getElementById('notch-clock');
        clockCtx = clockCanvas.getContext('2d');
        toolbarEl = document.getElementById('notch-toolbar');
        infoContainer = document.getElementById('notch-info');
        expandBtn = document.getElementById('notch-expand');

        pillEl.addEventListener('mouseenter', doExpand);
        notchEl.addEventListener('mouseleave', startAutoHide);
        notchEl.addEventListener('mouseenter', cancelAutoHide);
        expandBtn.addEventListener('click', function() {
            if (expanded) doCollapse(); else doExpand();
        });

        // 绑定所有 data-key 按钮（notch 内部 + body 级暂停按钮）
        var buttons = document.querySelectorAll('#notch button[data-key], #notch-pause[data-key]');
        for (var i = 0; i < buttons.length; i++) {
            (function(btn) {
                btn.addEventListener('click', function() {
                    Bridge.send({ type: 'click', key: btn.getAttribute('data-key') });
                });
            })(buttons[i]);
        }

        // 所有 submenu hover → 更新 hitRect 以覆盖下拉区域
        var submenuWraps = document.querySelectorAll('.notch-submenu-wrap');
        for (var si = 0; si < submenuWraps.length; si++) {
            (function(wrap) {
                wrap.addEventListener('mouseenter', function() {
                    cancelAutoHide(); // 防止 submenu 展开时 notch 收起
                    setTimeout(reportRect, 50);
                });
                wrap.addEventListener('mouseleave', function() {
                    setTimeout(reportRect, 50);
                });
            })(submenuWraps[si]);
        }

        // 暂停按钮已通过上方 notchEl.querySelectorAll('button[data-key]') 统一绑定

        // 暂停状态（帧数据 p:0/1）
        UiData.on('p', function(val) {
            var pb = document.getElementById('notch-pause');
            if (!pb) return;
            var paused = (val === '1');
            pb.textContent = paused ? '\u25B6' : '\u23F8'; // ▶ or ⏸
            if (paused) pb.classList.add('paused');
            else pb.classList.remove('paused');
        });

        // 主线任务进度（帧数据 q:N）→ 控制按钮可见性
        UiData.on('q', function(val) {
            var progress = parseInt(val, 10) || 0;
            var btn = document.querySelector('[data-key="WAREHOUSE"]');
            if (btn) btn.style.display = progress > 13 ? '' : 'none';
        });

        Bridge.on('fps', onFpsData);
        Bridge.on('lightLevels', function(data) {
            if (data.levels) lightLevels = data.levels;
        });
        window.addEventListener('resize', reportRect);
        reportRect();
        drawSparkline();
        drawClock();
    }

    function updateFpsText() {
        if (fpsEl) fpsEl.textContent = expanded ? fpsValue.toFixed(1) : Math.round(fpsValue);
    }
    function doExpand() {
        if (expandCooldown) return;
        expanded = true;
        notchEl.classList.add('expanded');
        cancelAutoHide();
        updateFpsText();
        setTimeout(reportRect, 180);
    }
    function doCollapse() {
        expanded = false;
        expandCooldown = true;
        setTimeout(function() { expandCooldown = false; }, 600);
        notchEl.classList.remove('expanded');
        updateFpsText();
        setTimeout(reportRect, 180);
    }
    function startAutoHide() {
        cancelAutoHide();
        autoHideTimer = setTimeout(doCollapse, 500);
    }
    function cancelAutoHide() {
        if (autoHideTimer) { clearTimeout(autoHideTimer); autoHideTimer = null; }
    }
    function reportRect() {
        // 基础 rect：展开时整个 notch，收起时 pill
        var target = expanded ? notchEl : pillEl;
        var r = target.getBoundingClientRect();
        var x1 = r.left, y1 = r.top, x2 = r.right, y2 = r.bottom;

        // 暂停按钮独立于 notch，但需要纳入 hitRect 才能接收点击
        var pb = document.getElementById('notch-pause');
        if (pb) {
            var pr = pb.getBoundingClientRect();
            if (pr.width > 0) {
                x1 = Math.min(x1, pr.left);
                y1 = Math.min(y1, pr.top);
                x2 = Math.max(x2, pr.right);
                y2 = Math.max(y2, pr.bottom);
            }
        }

        // 所有可见 submenu 下拉区域
        var subs = document.querySelectorAll('.notch-submenu');
        for (var si = 0; si < subs.length; si++) {
            if (subs[si].offsetParent !== null) {
                var sr = subs[si].getBoundingClientRect();
                if (sr.width > 0) {
                    x1 = Math.min(x1, sr.left);
                    y1 = Math.min(y1, sr.top);
                    x2 = Math.max(x2, sr.right);
                    y2 = Math.max(y2, sr.bottom);
                }
            }
        }

        Bridge.send({
            type: 'interactiveRect',
            x: Math.round(x1), y: Math.round(y1),
            w: Math.round(x2 - x1), h: Math.round(y2 - y1)
        });
    }

    function onFpsData(data) {
        fpsValue = data.value || 0;
        gameHour = (typeof data.hour === 'number') ? data.hour : 6;
        if (data.points) fpsPoints = data.points;
        fpsEl.textContent = expanded ? fpsValue.toFixed(1) : Math.round(fpsValue);
        fpsEl.className = 'notch-fps ' + (
            fpsValue >= 25 ? 'fps-good' : fpsValue >= 18 ? 'fps-warn' : 'fps-bad');
        drawSparkline();
        drawClock();
    }

    // FPS 颜色插值：≥25 绿, 18~25 绿→黄渐变, <18 黄→红渐变
    function fpsColor(fps, alpha) {
        var r, g, b;
        if (fps >= 25) { r = 100; g = 255; b = 100; }
        else if (fps >= 18) {
            var t = (fps - 18) / 7; // 0=18fps, 1=25fps
            r = Math.round(255 - 155 * t); g = Math.round(200 + 55 * t); b = Math.round(0 + 100 * t);
        } else {
            var t2 = Math.max(0, fps / 18); // 0=0fps, 1=18fps
            r = 255; g = Math.round(200 * t2); b = 0;
        }
        return 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
    }

    function drawSparkline() {
        var w = sparkCanvas.width, h = sparkCanvas.height;
        var ctx = sparkCtx;
        ctx.clearRect(0, 0, w, h);

        // === 光照等级背景（昼夜渐变） ===
        if (lightLevels && lightLevels.length >= 24) {
            var startHour = Math.floor(gameHour);
            var lightPts = 30;
            var stepX = w / lightPts;
            var stepH = h / MAX_LIGHT;

            // 填充区域
            ctx.beginPath();
            ctx.moveTo(0, h);
            for (var i = 0; i < lightPts; i++) {
                var hourIdx = (startHour + i) % 24;
                var ly = h - lightLevels[hourIdx] * stepH;
                ctx.lineTo(i * stepX, ly);
            }
            ctx.lineTo((lightPts - 1) * stepX, h);
            ctx.closePath();
            ctx.fillStyle = 'rgba(180,160,60,0.35)';
            ctx.fill();

            // 轮廓线
            ctx.beginPath();
            for (var i = 0; i < lightPts; i++) {
                var hourIdx2 = (startHour + i) % 24;
                var ly2 = h - lightLevels[hourIdx2] * stepH;
                if (i === 0) ctx.moveTo(0, ly2); else ctx.lineTo(i * stepX, ly2);
            }
            ctx.strokeStyle = 'rgba(200,180,70,0.5)';
            ctx.lineWidth = 0.8;
            ctx.stroke();
        }

        // === FPS 曲线 ===
        if (fpsPoints.length < 2) return;
        var pts = fpsPoints;
        var n = pts.length;

        // 自适应 Y 轴（对齐 AS2 FPSVisualization 的 min/max + minDiff 策略）
        var minV = pts[0], maxV = pts[0];
        for (var i = 1; i < n; i++) {
            if (pts[i] < minV) minV = pts[i];
            if (pts[i] > maxV) maxV = pts[i];
        }
        var MIN_DIFF = 5;
        if (maxV - minV < MIN_DIFF) {
            var delta = (MIN_DIFF - (maxV - minV)) / 2;
            minV -= delta;
            maxV += delta;
        }
        var range = maxV - minV;
        if (range < 1) range = 1;

        // Y 坐标映射
        function yOf(fps) { return h - ((fps - minV) / range) * h; }

        // 危险区域底色（18fps 以下区域半透明红色）
        var dangerY = yOf(18);
        if (dangerY < h) {
            ctx.fillStyle = 'rgba(255,50,50,0.12)';
            ctx.fillRect(0, dangerY, w, h - dangerY);
            // 18fps 分界线
            ctx.strokeStyle = 'rgba(255,80,80,0.3)';
            ctx.lineWidth = 0.5;
            ctx.setLineDash([2, 3]);
            ctx.beginPath();
            ctx.moveTo(0, dangerY);
            ctx.lineTo(w, dangerY);
            ctx.stroke();
            ctx.setLineDash([]);
        }

        // 计算所有点坐标
        var xs = [], ys = [];
        for (var i = 0; i < n; i++) {
            xs.push((i / (n - 1)) * w);
            ys.push(yOf(pts[i]));
        }

        // 渐变填充（曲线下方，颜色跟随平均帧率）
        var avgFps = 0;
        for (var i = 0; i < n; i++) avgFps += pts[i];
        avgFps /= n;

        ctx.beginPath();
        ctx.moveTo(xs[0], ys[0]);
        for (var i = 1; i < n; i++) {
            // 平滑曲线：用中点作为控制点
            var cpx = (xs[i - 1] + xs[i]) / 2;
            var cpy = (ys[i - 1] + ys[i]) / 2;
            ctx.quadraticCurveTo(xs[i - 1], ys[i - 1], cpx, cpy);
        }
        ctx.lineTo(xs[n - 1], ys[n - 1]);

        // 填充到底部
        var fillGrad = ctx.createLinearGradient(0, 0, 0, h);
        fillGrad.addColorStop(0, fpsColor(avgFps, 0.3));
        fillGrad.addColorStop(1, fpsColor(avgFps, 0.02));
        ctx.lineTo(xs[n - 1], h);
        ctx.lineTo(xs[0], h);
        ctx.closePath();
        ctx.fillStyle = fillGrad;
        ctx.fill();

        // 主曲线：分段着色
        for (var i = 1; i < n; i++) {
            ctx.beginPath();
            ctx.moveTo(xs[i - 1], ys[i - 1]);
            var cpx2 = (xs[i - 1] + xs[i]) / 2;
            var cpy2 = (ys[i - 1] + ys[i]) / 2;
            ctx.quadraticCurveTo(xs[i - 1], ys[i - 1], cpx2, cpy2);
            ctx.lineTo(xs[i], ys[i]);
            ctx.strokeStyle = fpsColor((pts[i - 1] + pts[i]) / 2, 0.9);
            ctx.lineWidth = 1.5;
            ctx.stroke();
        }

        // 当前值指示器：末端圆点 + 脉冲光晕
        var lastX = xs[n - 1], lastY = ys[n - 1], lastFps = pts[n - 1];
        var dotColor = fpsColor(lastFps, 1);
        // 光晕
        var glow = ctx.createRadialGradient(lastX, lastY, 0, lastX, lastY, 4);
        glow.addColorStop(0, fpsColor(lastFps, 0.6));
        glow.addColorStop(1, fpsColor(lastFps, 0));
        ctx.fillStyle = glow;
        ctx.fillRect(lastX - 4, lastY - 4, 8, 8);
        // 实心圆点
        ctx.beginPath();
        ctx.arc(lastX, lastY, 1.5, 0, Math.PI * 2);
        ctx.fillStyle = dotColor;
        ctx.fill();
    }

    function drawClock() {
        var w = clockCanvas.width, h = clockCanvas.height;
        var cx = w/2, cy = h/2, r = Math.min(cx,cy) - 1;
        clockCtx.clearRect(0, 0, w, h);

        // 对齐 GDI+ NotchOverlay 三档配色：白天/黄昏/夜晚
        var hr = Math.floor(gameHour) % 24;
        var faceColor, rimColor, handColor;
        if (hr >= 5 && hr <= 17) {
            // 白天：暖黄
            faceColor = 'rgba(180,170,100,0.2)';
            rimColor = 'rgba(200,190,120,0.7)';
            handColor = 'rgba(240,230,160,0.86)';
        } else if ((hr >= 3 && hr <= 4) || (hr >= 18 && hr <= 20)) {
            // 黄昏/黎明：橙
            faceColor = 'rgba(200,140,60,0.2)';
            rimColor = 'rgba(220,160,80,0.63)';
            handColor = 'rgba(240,180,100,0.78)';
        } else {
            // 夜晚：蓝
            faceColor = 'rgba(100,120,180,0.16)';
            rimColor = 'rgba(130,150,200,0.55)';
            handColor = 'rgba(160,180,220,0.7)';
        }

        // 表盘填充
        clockCtx.beginPath();
        clockCtx.arc(cx, cy, r, 0, Math.PI*2);
        clockCtx.fillStyle = faceColor;
        clockCtx.fill();

        // 外圈
        clockCtx.beginPath();
        clockCtx.arc(cx, cy, r, 0, Math.PI*2);
        clockCtx.strokeStyle = rimColor;
        clockCtx.lineWidth = 1.2;
        clockCtx.stroke();

        // 时针（短粗）：hour%12 映射到 360°
        var hour12 = gameHour % 12;
        var ha = (hour12/12)*Math.PI*2 - Math.PI/2;
        clockCtx.beginPath();
        clockCtx.moveTo(cx, cy);
        clockCtx.lineTo(cx + Math.cos(ha)*r*0.5, cy + Math.sin(ha)*r*0.5);
        clockCtx.strokeStyle = handColor;
        clockCtx.lineWidth = 2;
        clockCtx.lineCap = 'round';
        clockCtx.stroke();

        // 分针（长细）：小数部分映射 360°
        var minFrac = gameHour - Math.floor(gameHour);
        var ma = minFrac*Math.PI*2 - Math.PI/2;
        clockCtx.beginPath();
        clockCtx.moveTo(cx, cy);
        clockCtx.lineTo(cx + Math.cos(ma)*r*0.8, cy + Math.sin(ma)*r*0.8);
        clockCtx.strokeStyle = handColor;
        clockCtx.lineWidth = 1;
        clockCtx.stroke();
    }

    // === 游戏通知防洪 ===
    var GAME_CAT = 'game';
    var GAME_TRANSIENT_MS = 3000;
    var gameQueue = [];       // 待显示队列
    var gameThrottleTimer = null;
    var GAME_THROTTLE_MS = 350; // 最少间隔

    function addNotice(category, text, color) {
        if (category === GAME_CAT) {
            addGameNotice(text, color);
            return;
        }
        upsertRow(category, text, color, false);
    }

    function addGameNotice(text, color) {
        // 合并相同消息：队列中已有则计数+1
        for (var i = 0; i < gameQueue.length; i++) {
            if (gameQueue[i].text === text) {
                gameQueue[i].count++;
                return;
            }
        }
        // 检查当前显示中的 rows 是否有相同文本
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].baseText === text && rows[i].isGame) {
                var row = rows[i]; // 捕获稳定引用，不用可变索引
                row.count = (row.count || 1) + 1;
                row.el.textContent = text + ' x' + row.count;
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
        // 节流：下一条至少等 GAME_THROTTLE_MS
        if (gameQueue.length > 0) {
            gameThrottleTimer = setTimeout(function() {
                gameThrottleTimer = null;
                drainGameQueue();
            }, GAME_THROTTLE_MS);
        }
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
        // 游戏通知最多显示 4 条，超出挤掉最旧的游戏通知
        var gameRows = 0;
        for (var j = 0; j < rows.length; j++) { if (rows[j].isGame) gameRows++; }
        while (gameRows > 4) {
            for (var j = 0; j < rows.length; j++) {
                if (rows[j].isGame) { fadeOutRow(rows[j]); rows.splice(j,1); gameRows--; break; }
            }
        }
        requestAnimationFrame(function(){ el.classList.add('visible'); });
    }

    function setStatus(id, text, color) { upsertRow(id, text, color, true); }
    function clearStatus(id) {
        for (var i = rows.length-1; i >= 0; i--) {
            if (rows[i].id === id) { fadeOutRow(rows[i]); rows.splice(i,1); break; }
        }
    }

    function upsertRow(id, text, color, persistent) {
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].id === id) {
                rows[i].el.textContent = text;
                rows[i].el.style.color = color;
                if (!persistent && rows[i].rt) {
                    clearTimeout(rows[i].rt);
                    rows[i].rt = setTimeout(function(){removeRow(id);}, TRANSIENT_MS);
                }
                return;
            }
        }
        var el = document.createElement('div');
        el.className = 'notch-info-row';
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
            fadeOutRow(rows[v]); rows.splice(v,1);
        }
        requestAnimationFrame(function(){ el.classList.add('visible'); });
    }

    function removeRow(id) {
        for (var i = rows.length-1; i >= 0; i--) {
            if (rows[i].id === id) { fadeOutRow(rows[i]); rows.splice(i,1); break; }
        }
    }
    function fadeOutRow(row) {
        if (row.rt) clearTimeout(row.rt);
        row.el.classList.remove('visible');
        row.el.classList.add('fading');
        setTimeout(function(){ if(row.el.parentNode) row.el.parentNode.removeChild(row.el); }, 500);
    }

    window.addEventListener('load', init);
    return { addNotice:addNotice, setStatus:setStatus, clearStatus:clearStatus };
})();
