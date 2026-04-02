/**
 * jukebox.js — BGM 可视化面板
 * 折叠态：仅标题行，切歌时闪烁通知
 * 展开态：标题 + 滚动波形 + 进度条
 */
(function() {
    'use strict';

    var panel     = document.getElementById('jukebox-panel');
    var toggleBtn = document.getElementById('jukebox-toggle');
    var titleEl   = document.getElementById('jukebox-title');
    var timeEl    = document.getElementById('jukebox-time');
    var canvas    = document.getElementById('jukebox-wave');
    var progFill  = document.getElementById('jukebox-prog-fill');

    if (!panel || !canvas) return;

    var ctx       = canvas.getContext('2d');
    var dpr       = window.devicePixelRatio || 1;
    var cssW      = 168; // 170 - 2px border
    var cssH      = 32;

    // 波形历史 ring buffer
    var HISTORY   = 100;
    var histL     = new Float32Array(HISTORY);
    var histR     = new Float32Array(HISTORY);
    var histIdx   = 0;
    var histLen   = 0;

    // 状态
    var playing   = false;
    var bgmTitle  = '';
    var isExpanded = false;

    // DPR 感知 canvas
    function resizeCanvas() {
        dpr = window.devicePixelRatio || 1;
        canvas.width  = cssW * dpr;
        canvas.height = cssH * dpr;
        canvas.style.width  = cssW + 'px';
        canvas.style.height = cssH + 'px';
    }
    resizeCanvas();
    if (window.matchMedia) {
        var mq = window.matchMedia('(resolution: ' + dpr + 'dppx)');
        if (mq.addEventListener) mq.addEventListener('change', resizeCanvas);
    }

    // 格式化时间 mm:ss
    function fmtTime(sec) {
        if (!sec || sec <= 0) return '--:--';
        var m = Math.floor(sec / 60);
        var s = Math.floor(sec % 60);
        return (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
    }

    // ── 折叠/展开 ──
    toggleBtn.addEventListener('click', function() {
        isExpanded = !isExpanded;
        panel.classList.toggle('expanded', isExpanded);
        // 交互区域几何变化 → 通知 InputShield 更新 hitRect
        // notch.js 的 reportRect 会读取 jukebox-panel 的 boundingRect
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 300); // 等 CSS transition 完成
    });

    // ── 接收音频数据 ──
    function onAudioData(data) {
        var peakL = data.l || 0;
        var peakR = data.r || 0;
        playing   = data.p === 1;
        var cursor   = data.c || 0;
        var duration = data.d || 0;

        // 写入历史
        histL[histIdx] = peakL;
        histR[histIdx] = peakR;
        histIdx = (histIdx + 1) % HISTORY;
        if (histLen < HISTORY) histLen++;

        // 更新进度（无 BGM 时忽略残留数据）
        if (duration > 0 && bgmTitle) {
            var pct = Math.min(cursor / duration, 1) * 100;
            progFill.style.width = pct + '%';
            timeEl.textContent = fmtTime(cursor) + '/' + fmtTime(duration);
        } else {
            progFill.style.width = '0%';
            timeEl.textContent = '';
        }

        // 展开态才绘制波形（节省 CPU）
        if (isExpanded) render();
    }

    // ── 设置标题 ──
    function setTitle(title) {
        var oldTitle = bgmTitle;
        bgmTitle = title || '';
        titleEl.textContent = bgmTitle || '未播放';
        titleEl.title = bgmTitle;

        // 标记是否有 BGM（控制标题亮度、是否可展开波形）
        panel.classList.toggle('has-bgm', !!bgmTitle);

        // 切歌通知（折叠态 + 有新标题）
        if (bgmTitle && !isExpanded && bgmTitle !== oldTitle) {
            panel.classList.remove('notify');
            void panel.offsetHeight;
            panel.classList.add('notify');
        }

        // 切歌时清空波形历史
        if (bgmTitle !== oldTitle) {
            histLen = 0;
            histIdx = 0;
        }

        // 无 BGM 时自动折叠 + 清空进度
        if (!bgmTitle) {
            timeEl.textContent = '';
            progFill.style.width = '0%';
            if (isExpanded) {
                isExpanded = false;
                panel.classList.remove('expanded');
                // 几何变化 → 同步 InputShield hitRect（等 CSS transition 完成）
                setTimeout(function() {
                    if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
                }, 300);
            }
        }
    }

    // ── 渲染滚动波形 ──
    function render() {
        var w = canvas.width;
        var h = canvas.height;
        var midY = h / 2;

        ctx.clearRect(0, 0, w, h);
        if (histLen === 0) return;

        var barW = w / HISTORY;
        var maxH = midY - 1 * dpr;

        for (var i = 0; i < histLen; i++) {
            var idx = (histIdx - histLen + i + HISTORY) % HISTORY;
            var lv = histL[idx];
            var rv = histR[idx];
            var x = i * barW;

            var age = (histLen - 1 - i) / Math.max(histLen - 1, 1);
            var alpha = playing ? (0.3 + 0.7 * (1 - age)) : 0.15;

            // L channel (上半)
            var hL = Math.max(1 * dpr, lv * maxH);
            ctx.fillStyle = 'rgba(102,204,255,' + alpha + ')';
            ctx.fillRect(x, midY - hL, Math.max(barW - 0.5, 1), hL);

            // R channel (下半)
            var hR = Math.max(1 * dpr, rv * maxH);
            ctx.fillStyle = 'rgba(150,220,255,' + (alpha * 0.8) + ')';
            ctx.fillRect(x, midY, Math.max(barW - 0.5, 1), hR);
        }

        // 中线
        ctx.fillStyle = 'rgba(255,255,255,0.15)';
        ctx.fillRect(0, midY - 0.5 * dpr, w, 1 * dpr);
    }

    // ── 注册消息 ──
    Bridge.on('audio', onAudioData);

    if (typeof UiData !== 'undefined') {
        UiData.on('bgm', function(val) {
            setTitle(val);
        });
    }

    // 通知动画结束清理
    panel.addEventListener('animationend', function(e) {
        if (e.animationName === 'jukebox-notify') {
            panel.classList.remove('notify');
        }
    });

    window.Jukebox = {
        onAudioData: onAudioData,
        setTitle: setTitle
    };
})();
