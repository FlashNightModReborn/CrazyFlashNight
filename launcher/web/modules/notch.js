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

        // 绑定所有 data-key 按钮（toolbar + row1-right + 任何位置）
        var buttons = notchEl.querySelectorAll('button[data-key]');
        for (var i = 0; i < buttons.length; i++) {
            (function(btn) {
                btn.addEventListener('click', function() {
                    Bridge.send({ type: 'click', key: btn.getAttribute('data-key') });
                });
            })(buttons[i]);
        }

        // submenu hover → 更新 hitRect 以覆盖下拉区域
        var submenuWrap = document.querySelector('.notch-submenu-wrap');
        if (submenuWrap) {
            submenuWrap.addEventListener('mouseenter', function() {
                setTimeout(reportRect, 50); // 等 CSS :hover 展开后上报
            });
            submenuWrap.addEventListener('mouseleave', function() {
                setTimeout(reportRect, 50);
            });
        }

        // 暂停按钮（常驻）
        var pauseBtn = document.getElementById('notch-pause');
        if (pauseBtn) {
            pauseBtn.addEventListener('click', function() {
                Bridge.send({ type: 'click', key: 'PAUSE' });
            });
        }

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

    function doExpand() {
        if (expandCooldown) return;
        expanded = true;
        notchEl.classList.add('expanded');
        cancelAutoHide();
        // toolbar 的 max-width 过渡驱动 pill 宽度变化，150ms 后上报最终 rect
        setTimeout(reportRect, 180);
    }
    function doCollapse() {
        expanded = false;
        expandCooldown = true;
        setTimeout(function() { expandCooldown = false; }, 600);
        notchEl.classList.remove('expanded');
        // 过渡完成后上报收起态 rect
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
        // 展开时上报整个 #notch rect（包含 submenu 下拉区域），收起时只报 pill
        var target = expanded ? notchEl : pillEl;
        var rect = target.getBoundingClientRect();
        // submenu 可能超出 notch 边界，取并集
        if (expanded) {
            var sub = document.querySelector('.notch-submenu');
            if (sub && sub.offsetParent !== null) {
                var sr = sub.getBoundingClientRect();
                var x1 = Math.min(rect.left, sr.left);
                var y1 = Math.min(rect.top, sr.top);
                var x2 = Math.max(rect.right, sr.right);
                var y2 = Math.max(rect.bottom, sr.bottom);
                rect = { left: x1, top: y1, width: x2 - x1, height: y2 - y1 };
            }
        }
        Bridge.send({
            type: 'interactiveRect',
            x: Math.round(rect.left), y: Math.round(rect.top),
            w: Math.round(rect.width), h: Math.round(rect.height)
        });
    }

    function onFpsData(data) {
        fpsValue = data.value || 0;
        gameHour = (typeof data.hour === 'number') ? data.hour : 6;
        if (data.points) fpsPoints = data.points;
        fpsEl.textContent = Math.round(fpsValue);
        fpsEl.className = 'notch-fps ' + (
            fpsValue >= 25 ? 'fps-good' : fpsValue >= 18 ? 'fps-warn' : 'fps-bad');
        drawSparkline();
        drawClock();
    }

    function drawSparkline() {
        var w = sparkCanvas.width, h = sparkCanvas.height;
        sparkCtx.clearRect(0, 0, w, h);

        // 光照等级背景（暖黄色填充区域图，固定 30 小时窗口，不跟随 FPS 数据量）
        if (lightLevels && lightLevels.length >= 24) {
            var startHour = Math.floor(gameHour);
            var lightPts = 30; // 与 GDI+ SparklinePoints 对齐，始终完整绘制
            var stepX = w / lightPts;
            var stepH = h / MAX_LIGHT;

            sparkCtx.beginPath();
            sparkCtx.moveTo(0, h); // 左下角
            for (var i = 0; i < lightPts; i++) {
                var hourIdx = (startHour + i) % 24;
                var ly = h - lightLevels[hourIdx] * stepH;
                sparkCtx.lineTo(i * stepX, ly);
            }
            sparkCtx.lineTo((lightPts - 1) * stepX, h); // 右下角
            sparkCtx.closePath();
            sparkCtx.fillStyle = 'rgba(180,160,60,0.39)';
            sparkCtx.fill();

            // 顶部轮廓线
            sparkCtx.beginPath();
            for (var i = 0; i < lightPts; i++) {
                var hourIdx = (startHour + i) % 24;
                var ly = h - lightLevels[hourIdx] * stepH;
                if (i === 0) sparkCtx.moveTo(0, ly);
                else sparkCtx.lineTo(i * stepX, ly);
            }
            sparkCtx.strokeStyle = 'rgba(200,180,70,0.55)';
            sparkCtx.lineWidth = 1;
            sparkCtx.stroke();
        }

        // FPS 曲线
        if (fpsPoints.length < 2) return;
        var pts = fpsPoints, maxV = 60;
        for (var i = 0; i < pts.length; i++) { if (pts[i] > maxV) maxV = pts[i]; }
        maxV = Math.max(maxV, 10);
        sparkCtx.strokeStyle = 'rgba(100,255,100,0.8)';
        sparkCtx.lineWidth = 1.5;
        sparkCtx.beginPath();
        for (var i = 0; i < pts.length; i++) {
            var x = (i / (pts.length - 1)) * w;
            var y = h - (pts[i] / maxV) * h;
            if (i === 0) sparkCtx.moveTo(x, y); else sparkCtx.lineTo(x, y);
        }
        sparkCtx.stroke();
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
