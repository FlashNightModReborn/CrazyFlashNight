var Notch = (function() {
    'use strict';
    var notchEl, pillEl, fpsEl, sparkCanvas, sparkCtx;
    var clockCanvas, clockCtx, toolbarEl, infoContainer, expandBtn;
    var expanded = false, fpsValue = 0, fpsPoints = [], gameHour = 12;
    var autoHideTimer = null;
    var rows = [], TRANSIENT_MS = 4000, MAX_ROWS = 4;
    var lightLevels = null, MAX_LIGHT = 9;

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

        var buttons = toolbarEl.querySelectorAll('button[data-key]');
        for (var i = 0; i < buttons.length; i++) {
            (function(btn) {
                btn.addEventListener('click', function() {
                    Bridge.send({ type: 'click', key: btn.getAttribute('data-key') });
                });
            })(buttons[i]);
        }

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
        expanded = true;
        var vw = document.documentElement.clientWidth;
        // pill 宽度从当前值渐变到视口宽度（px→px，CSS transition 可插值）
        pillEl.style.width = Math.max(200, vw) + 'px';
        notchEl.classList.add('expanded');
        cancelAutoHide();
        setTimeout(reportRect, 20);
    }
    function doCollapse() {
        expanded = false;
        // 先设到收起宽度（px→px 可过渡），过渡结束后清除固定宽度
        var collapsedW = notchEl.querySelector('#notch-left').offsetWidth + 16;
        pillEl.style.width = collapsedW + 'px';
        notchEl.classList.remove('expanded');
        setTimeout(function() {
            pillEl.style.width = '';
            reportRect();
        }, 180);
    }
    function startAutoHide() {
        cancelAutoHide();
        autoHideTimer = setTimeout(doCollapse, 500);
    }
    function cancelAutoHide() {
        if (autoHideTimer) { clearTimeout(autoHideTimer); autoHideTimer = null; }
    }
    function reportRect() {
        var rect = notchEl.getBoundingClientRect();
        Bridge.send({
            type: 'interactiveRect',
            x: Math.round(rect.left), y: Math.round(rect.top),
            w: Math.round(rect.width), h: Math.round(rect.height)
        });
    }

    function onFpsData(data) {
        fpsValue = data.value || 0;
        gameHour = data.hour || 12;
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

        // 光照等级背景（暖黄色填充区域图）
        if (lightLevels && lightLevels.length >= 24) {
            var startHour = Math.floor(gameHour);
            var points = fpsPoints.length > 2 ? fpsPoints.length : 30;
            var stepX = w / points;
            var stepH = h / MAX_LIGHT;

            sparkCtx.beginPath();
            sparkCtx.moveTo(0, h); // 左下角
            for (var i = 0; i < points; i++) {
                var hourIdx = (startHour + i) % 24;
                var ly = h - lightLevels[hourIdx] * stepH;
                sparkCtx.lineTo(i * stepX, ly);
            }
            sparkCtx.lineTo((points - 1) * stepX, h); // 右下角
            sparkCtx.closePath();
            sparkCtx.fillStyle = 'rgba(180,160,60,0.39)';
            sparkCtx.fill();

            // 顶部轮廓线
            sparkCtx.beginPath();
            for (var i = 0; i < points; i++) {
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
        clockCtx.beginPath();
        clockCtx.arc(cx, cy, r, 0, Math.PI*2);
        clockCtx.strokeStyle = 'rgba(255,255,255,0.5)';
        clockCtx.lineWidth = 1;
        clockCtx.stroke();
        var ha = ((gameHour%12)/12)*Math.PI*2 - Math.PI/2;
        clockCtx.beginPath();
        clockCtx.moveTo(cx, cy);
        clockCtx.lineTo(cx + Math.cos(ha)*r*0.5, cy + Math.sin(ha)*r*0.5);
        clockCtx.strokeStyle = '#ffd700';
        clockCtx.lineWidth = 2;
        clockCtx.stroke();
        clockCtx.beginPath();
        clockCtx.moveTo(cx, cy);
        clockCtx.lineTo(cx, cy - r*0.7);
        clockCtx.strokeStyle = 'rgba(255,255,255,0.4)';
        clockCtx.lineWidth = 1;
        clockCtx.stroke();
    }

    function addNotice(category, text, color) { upsertRow(category, text, color, false); }
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
