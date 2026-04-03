/**
 * jukebox.js — BGM 可视化面板 + 专辑浏览 + 选曲 + 进度拖拽
 * 折叠态：仅标题行，切歌时闪烁通知
 * 展开态：标题 + 滚动波形 + 进度条 + 专辑浏览器
 */
(function() {
    'use strict';

    var panel     = document.getElementById('jukebox-panel');
    var toggleBtn = document.getElementById('jukebox-toggle');
    var titleEl   = document.getElementById('jukebox-title');
    var timeEl    = document.getElementById('jukebox-time');
    var canvas    = document.getElementById('jukebox-wave');
    var progFill  = document.getElementById('jukebox-prog-fill');
    var progBar   = document.getElementById('jukebox-progress');

    // 浏览器元素
    var albumDropdown = document.getElementById('jukebox-album-dropdown');
    var albumTrigger  = document.getElementById('jukebox-album-trigger');
    var albumLabel    = document.getElementById('jukebox-album-label');
    var albumOptions  = document.getElementById('jukebox-album-options');
    var trackList     = document.getElementById('jukebox-track-list');

    // 设置菜单
    var settingsWrap   = document.getElementById('jukebox-settings');
    var settingsToggle = document.getElementById('jukebox-settings-toggle');
    var settingsMenu   = document.getElementById('jukebox-settings-menu');

    var miniCanvas = document.getElementById('jukebox-mini-wave');

    if (!panel || !canvas) return;

    var ctx       = canvas.getContext('2d');
    var miniCtx   = miniCanvas ? miniCanvas.getContext('2d') : null;
    var dpr       = window.devicePixelRatio || 1;
    var cssW      = 168;
    var cssH      = 32;
    var miniW     = 120;
    var miniH     = 20;

    // 波形历史 ring buffer
    var HISTORY   = 100;
    var histL     = new Float32Array(HISTORY);
    var histR     = new Float32Array(HISTORY);
    var histIdx   = 0;
    var histLen   = 0;

    // 状态
    var playing        = false;
    var bgmTitle       = '';
    var isExpanded     = false;
    var currentDuration = 0;

    // 目录数据
    var albums    = {};      // albumName -> [{title, weight}, ...]
    var allTracks = [];      // flat list
    var currentAlbumFilter = '';

    // DPR 感知 canvas
    function resizeCanvas() {
        dpr = window.devicePixelRatio || 1;
        // 主波形（body 中，固定尺寸）
        cssW = 168; cssH = 32;
        canvas.width  = cssW * dpr;
        canvas.height = cssH * dpr;
        canvas.style.width  = cssW + 'px';
        canvas.style.height = cssH + 'px';
        // mini 波形（header 标题区背景）
        if (miniCanvas && miniCanvas.parentElement) {
            var mr = miniCanvas.parentElement.getBoundingClientRect();
            miniW = Math.round(mr.width) || 120;
            miniH = Math.round(mr.height) || 20;
            miniCanvas.width  = miniW * dpr;
            miniCanvas.height = miniH * dpr;
        }
    }
    resizeCanvas();
    if (window.matchMedia) {
        var mq = window.matchMedia('(resolution: ' + dpr + 'dppx)');
        if (mq.addEventListener) mq.addEventListener('change', resizeCanvas);
    }

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
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 300);
    });

    // ── 接收音频数据 ──
    function onAudioData(data) {
        var peakL = data.l || 0;
        var peakR = data.r || 0;
        var wasPlaying = playing;
        playing   = data.p === 1;
        if (playing && !wasPlaying) syncPauseState(true);
        var cursor   = data.c || 0;
        var duration = data.d || 0;
        currentDuration = duration;

        histL[histIdx] = peakL;
        histR[histIdx] = peakR;
        histIdx = (histIdx + 1) % HISTORY;
        if (histLen < HISTORY) histLen++;

        if (duration > 0 && bgmTitle) {
            var pct = Math.min(cursor / duration, 1) * 100;
            progFill.style.width = pct + '%';
            timeEl.textContent = fmtTime(cursor) + '/' + fmtTime(duration);
        } else {
            progFill.style.width = '0%';
            timeEl.textContent = '';
        }

        // mini 波形始终渲染（header 底色），主波形仅展开时
        renderMini();
        if (isExpanded) render();
    }

    // ── 设置标题 ──
    function setTitle(title) {
        var oldTitle = bgmTitle;
        bgmTitle = title || '';
        titleEl.textContent = bgmTitle || '未播放';
        titleEl.title = bgmTitle;

        var hadBgm = panel.classList.contains('has-bgm');
        panel.classList.toggle('has-bgm', !!bgmTitle);
        // 波形显隐改变面板高度 → 更新 hitRect
        if (hadBgm !== !!bgmTitle) {
            setTimeout(function() {
                if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
            }, 50);
        }

        if (bgmTitle && !isExpanded && bgmTitle !== oldTitle) {
            panel.classList.remove('notify');
            void panel.offsetHeight;
            panel.classList.add('notify');
        }

        if (bgmTitle !== oldTitle) {
            histLen = 0;
            histIdx = 0;
        }

        if (!bgmTitle) {
            timeEl.textContent = '';
            progFill.style.width = '0%';
            // 不再自动折叠：无 BGM 时仍允许浏览和选曲
        }

        // 高亮当前播放曲目
        updateActiveTrack();
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

            var hL = Math.max(1 * dpr, lv * maxH);
            ctx.fillStyle = 'rgba(102,204,255,' + alpha + ')';
            ctx.fillRect(x, midY - hL, Math.max(barW - 0.5, 1), hL);

            var hR = Math.max(1 * dpr, rv * maxH);
            ctx.fillStyle = 'rgba(150,220,255,' + (alpha * 0.8) + ')';
            ctx.fillRect(x, midY, Math.max(barW - 0.5, 1), hR);
        }

        ctx.fillStyle = 'rgba(255,255,255,0.15)';
        ctx.fillRect(0, midY - 0.5 * dpr, w, 1 * dpr);
    }

    // ── mini 波形（header 标题区底色）──
    function renderMini() {
        if (!miniCtx) return;
        var w = miniCanvas.width;
        var h = miniCanvas.height;
        var midY = h / 2;

        miniCtx.clearRect(0, 0, w, h);
        if (histLen === 0) return;

        var barW = w / HISTORY;
        var maxH = midY - 1 * dpr;

        for (var i = 0; i < histLen; i++) {
            var idx = (histIdx - histLen + i + HISTORY) % HISTORY;
            var lv = histL[idx];
            var rv = histR[idx];
            var x = i * barW;
            var age = (histLen - 1 - i) / Math.max(histLen - 1, 1);
            var alpha = playing ? (0.2 + 0.5 * (1 - age)) : 0.1;

            var hL = Math.max(1 * dpr, lv * maxH);
            miniCtx.fillStyle = 'rgba(102,204,255,' + alpha + ')';
            miniCtx.fillRect(x, midY - hL, Math.max(barW - 0.5, 1), hL);

            var hR = Math.max(1 * dpr, rv * maxH);
            miniCtx.fillStyle = 'rgba(150,220,255,' + (alpha * 0.7) + ')';
            miniCtx.fillRect(x, midY, Math.max(barW - 0.5, 1), hR);
        }
    }

    // ══════════════════════════════════════════════
    // ██  目录接收
    // ══════════════════════════════════════════════

    Bridge.on('catalog', function(data) {
        albums = {};
        allTracks = [];
        var tracks = data.tracks || [];
        for (var i = 0; i < tracks.length; i++) {
            var t = tracks[i];
            if (!albums[t.album]) albums[t.album] = [];
            albums[t.album].push(t);
            allTracks.push(t);
        }
        renderAlbumSelect();
        renderTrackList(currentAlbumFilter);
    });

    Bridge.on('catalogUpdate', function(data) {
        var added = data.added || [];
        var removed = data.removed || [];
        for (var r = 0; r < removed.length; r++) {
            removeTrackByTitle(removed[r]);
        }
        for (var a = 0; a < added.length; a++) {
            var t = added[a];
            if (!albums[t.album]) albums[t.album] = [];
            albums[t.album].push(t);
            allTracks.push(t);
        }
        renderAlbumSelect();
        renderTrackList(currentAlbumFilter);
    });

    function removeTrackByTitle(title) {
        for (var alb in albums) {
            var arr = albums[alb];
            for (var i = arr.length - 1; i >= 0; i--) {
                if (arr[i].title === title) arr.splice(i, 1);
            }
            if (arr.length === 0) delete albums[alb];
        }
        for (var j = allTracks.length - 1; j >= 0; j--) {
            if (allTracks[j].title === title) allTracks.splice(j, 1);
        }
    }

    // ══════════════════════════════════════════════
    // ██  专辑/曲目渲染
    // ══════════════════════════════════════════════

    function renderAlbumSelect() {
        if (!albumOptions) return;
        albumOptions.innerHTML = '';
        // "全部" 选项
        var allOpt = document.createElement('div');
        allOpt.className = 'jb-album-option' + (currentAlbumFilter === '' ? ' active' : '');
        allOpt.textContent = '全部';
        allOpt.setAttribute('data-album', '');
        albumOptions.appendChild(allOpt);

        var names = [];
        for (var alb in albums) names.push(alb);
        names.sort();
        for (var i = 0; i < names.length; i++) {
            var opt = document.createElement('div');
            opt.className = 'jb-album-option' + (names[i] === currentAlbumFilter ? ' active' : '');
            opt.textContent = names[i] + ' (' + albums[names[i]].length + ')';
            opt.setAttribute('data-album', names[i]);
            albumOptions.appendChild(opt);
        }
        // 更新触发器文本
        if (albumLabel) {
            albumLabel.textContent = currentAlbumFilter
                ? currentAlbumFilter + ' (' + (albums[currentAlbumFilter] || []).length + ')'
                : '全部';
        }
    }

    // 自定义下拉交互
    if (albumTrigger) {
        albumTrigger.addEventListener('click', function() {
            albumDropdown.classList.toggle('open');
            setTimeout(function() {
                if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
            }, 50);
        });
    }
    if (albumOptions) {
        albumOptions.addEventListener('click', function(e) {
            var opt = e.target;
            while (opt && !opt.classList.contains('jb-album-option')) opt = opt.parentElement;
            if (!opt) return;
            currentAlbumFilter = opt.getAttribute('data-album') || '';
            albumDropdown.classList.remove('open');
            renderAlbumSelect(); // 更新 active 标记和触发器文本
            renderTrackList(currentAlbumFilter);
            setTimeout(function() {
                if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
            }, 50);
        });
    }
    // 点击外部关闭下拉
    document.addEventListener('click', function(e) {
        if (albumDropdown && !albumDropdown.contains(e.target)) {
            albumDropdown.classList.remove('open');
        }
    });

    function renderTrackList(albumFilter) {
        if (!trackList) return;
        trackList.innerHTML = '';
        var source = albumFilter ? (albums[albumFilter] || []) : allTracks;
        for (var i = 0; i < source.length; i++) {
            var div = document.createElement('div');
            div.className = 'track-item';
            div.textContent = source[i].title;
            div.setAttribute('data-title', source[i].title);
            if (source[i].title === bgmTitle) div.classList.add('active');
            div.addEventListener('click', onTrackClick);
            trackList.appendChild(div);
        }
    }

    function onTrackClick(e) {
        var title = e.target.getAttribute('data-title');
        if (title) {
            Bridge.send({type: 'jukebox', cmd: 'play', title: title});
        }
    }

    function updateActiveTrack() {
        if (!trackList) return;
        var items = trackList.children;
        for (var i = 0; i < items.length; i++) {
            var t = items[i].getAttribute('data-title');
            if (t === bgmTitle) {
                items[i].classList.add('active');
            } else {
                items[i].classList.remove('active');
            }
        }
    }

    // ══════════════════════════════════════════════
    // ██  暂停/继续
    // ══════════════════════════════════════════════

    var pauseBtn = document.getElementById('jukebox-pause-btn');
    var isPaused = false;

    if (pauseBtn) {
        pauseBtn.addEventListener('click', function() {
            isPaused = !isPaused;
            pauseBtn.classList.toggle('paused', isPaused);
            pauseBtn.textContent = isPaused ? '\u25B6' : '\u2016'; // ▶ or ‖
            Bridge.send({type: 'jukebox', cmd: isPaused ? 'pause' : 'resume'});
        });
    }

    // 播放状态变化时自动重置暂停按钮
    function syncPauseState(isPlaying) {
        if (isPlaying && isPaused) {
            // 外部触发了新曲播放，重置暂停状态
            isPaused = false;
            if (pauseBtn) {
                pauseBtn.classList.remove('paused');
                pauseBtn.textContent = '\u2016';
            }
        }
    }

    // ══════════════════════════════════════════════
    // ██  进度条拖拽 seek
    // ══════════════════════════════════════════════

    var seeking = false;
    if (progBar) {
        progBar.addEventListener('mousedown', function(e) {
            seeking = true;
            doSeek(e);
        });
    }
    document.addEventListener('mousemove', function(e) {
        if (seeking) doSeek(e);
    });
    document.addEventListener('mouseup', function() {
        seeking = false;
    });

    function doSeek(e) {
        if (currentDuration <= 0 || !progBar) return;
        var rect = progBar.getBoundingClientRect();
        var pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        Bridge.send({type: 'jukebox', cmd: 'seek', sec: pct * currentDuration});
    }

    // ══════════════════════════════════════════════
    // ██  设置菜单
    // ══════════════════════════════════════════════

    var settingsState = {
        override: false,
        trueRandom: false,
        playMode: 'singleLoop'  // singleLoop | albumLoop | playOnce
    };

    if (settingsToggle) {
        settingsToggle.addEventListener('click', function(e) {
            e.stopPropagation();
            settingsWrap.classList.toggle('open');
            setTimeout(function() {
                if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
            }, 50);
        });
    }
    // 点击外部关闭设置
    document.addEventListener('click', function(e) {
        if (settingsWrap && !settingsWrap.contains(e.target)) {
            settingsWrap.classList.remove('open');
        }
    });

    if (settingsMenu) {
        settingsMenu.addEventListener('click', function(e) {
            var item = e.target;
            while (item && !item.classList.contains('jb-setting-item')) {
                item = item.parentElement;
            }
            if (!item) return;
            var key = item.getAttribute('data-key');
            if (!key) return;

            if (item.classList.contains('jb-radio')) {
                // 单选组：同 key 的其他 item 取消 active
                var val = item.getAttribute('data-value');
                settingsState[key] = val;
                var siblings = settingsMenu.querySelectorAll('.jb-radio[data-key="' + key + '"]');
                for (var s = 0; s < siblings.length; s++) {
                    siblings[s].classList.toggle('active', siblings[s].getAttribute('data-value') === val);
                }
                Bridge.send({type: 'jukebox', cmd: 'playMode', value: val});
                return;
            }

            // 切换开关
            settingsState[key] = !settingsState[key];
            item.classList.toggle('active', settingsState[key]);

            if (key === 'override') {
                Bridge.send({type: 'jukebox', cmd: 'override', value: settingsState.override});
            } else if (key === 'trueRandom') {
                Bridge.send({type: 'jukebox', cmd: 'trueRandom', value: settingsState.trueRandom});
            }
        });
    }

    // ── 注册消息 ──
    Bridge.on('audio', onAudioData);

    if (typeof UiData !== 'undefined') {
        UiData.on('bgm', function(val) {
            setTitle(val);
        });
        // 从 Flash 同步设置状态（存档恢复 / 手动切换）
        UiData.on('jbo', function(val) {
            settingsState.override = (val === '1');
            syncSettingUI('override', settingsState.override);
        });
        UiData.on('jbr', function(val) {
            settingsState.trueRandom = (val === '1');
            syncSettingUI('trueRandom', settingsState.trueRandom);
        });
        UiData.on('jbm', function(val) {
            syncPlayModeUI(val);
        });
    }

    function syncSettingUI(key, active) {
        if (!settingsMenu) return;
        var items = settingsMenu.querySelectorAll('.jb-setting-item[data-key="' + key + '"]');
        for (var i = 0; i < items.length; i++) {
            items[i].classList.toggle('active', active);
        }
    }

    function syncPlayModeUI(mode) {
        if (!settingsMenu) return;
        settingsState.playMode = mode;
        var radios = settingsMenu.querySelectorAll('.jb-radio[data-key="playMode"]');
        for (var i = 0; i < radios.length; i++) {
            radios[i].classList.toggle('active', radios[i].getAttribute('data-value') === mode);
        }
    }

    // 初始化默认选中状态
    syncPlayModeUI('singleLoop');

    // ══════════════════════════════════════════════
    // ██  帮助按钮
    // ══════════════════════════════════════════════

    var helpBtn   = document.getElementById('jukebox-help-btn');
    var helpModal = document.getElementById('jukebox-help-modal');
    var helpContent = document.getElementById('jukebox-help-content');
    var helpClose = document.getElementById('jukebox-help-close');
    var helpLoaded = false;

    if (helpBtn && helpModal) {
        helpBtn.addEventListener('click', function() {
            if (!helpLoaded) {
                // 加载 sounds/README.md（WebView 的 base URL 是 launcher/web/）
                // 通过 Bridge 请求 Launcher 读取文件
                helpContent.textContent = '加载中...';
                Bridge.send({type: 'jukebox', cmd: 'loadHelp'});
            }
            helpModal.classList.toggle('visible');
            setTimeout(function() {
                if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
            }, 50);
        });
        helpClose.addEventListener('click', function() {
            helpModal.classList.remove('visible');
            setTimeout(function() {
                if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
            }, 50);
        });

        // 接收帮助文本
        Bridge.on('helpText', function(data) {
            helpLoaded = true;
            if (typeof marked !== 'undefined' && marked.parse) {
                helpContent.innerHTML = marked.parse(data.text || '');
            } else {
                helpContent.innerHTML = renderMiniMd(data.text || '');
            }
        });
    }

    // ══════════════════════════════════════════════
    // ██  轻量 Markdown → HTML（仅支持使用的子集）
    // ══════════════════════════════════════════════

    function esc(s) {
        return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }

    function renderMiniMd(src) {
        var lines = src.split('\n');
        var html = [];
        var inCode = false;
        var inTable = false;

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];

            // 代码块
            if (line.indexOf('```') === 0) {
                if (inCode) {
                    html.push('</code></pre>');
                    inCode = false;
                } else {
                    inCode = true;
                    html.push('<pre class="md-code"><code>');
                }
                continue;
            }
            if (inCode) {
                html.push(esc(line) + '\n');
                continue;
            }

            // 空行
            if (line.replace(/\s/g, '') === '') {
                if (inTable) { html.push('</table>'); inTable = false; }
                html.push('<div class="md-spacer"></div>');
                continue;
            }

            // 表格分隔行
            if (/^\|[\s\-:]+\|/.test(line)) continue;

            // 表格行
            if (line.charAt(0) === '|') {
                var cells = line.split('|');
                var row = '<tr>';
                for (var c = 1; c < cells.length - 1; c++) {
                    var tag = !inTable ? 'th' : 'td';
                    row += '<' + tag + '>' + esc(cells[c].replace(/^\s+|\s+$/g, '')) + '</' + tag + '>';
                }
                row += '</tr>';
                if (!inTable) { html.push('<table class="md-table">'); inTable = true; }
                html.push(row);
                continue;
            }
            if (inTable) { html.push('</table>'); inTable = false; }

            // 标题
            var hm = line.match(/^(#{1,3})\s+(.*)/);
            if (hm) {
                var lvl = hm[1].length;
                html.push('<h' + (lvl + 2) + ' class="md-h">' + esc(hm[2]) + '</h' + (lvl + 2) + '>');
                continue;
            }

            // 有序列表
            var olm = line.match(/^(\d+)\.\s+(.*)/);
            if (olm) {
                html.push('<div class="md-li"><span class="md-num">' + olm[1] + '.</span> ' + inlineFormat(olm[2]) + '</div>');
                continue;
            }

            // 无序列表
            if (line.charAt(0) === '-' && line.charAt(1) === ' ') {
                html.push('<div class="md-li"><span class="md-bullet">-</span> ' + inlineFormat(line.substring(2)) + '</div>');
                continue;
            }

            // 普通段落
            html.push('<p class="md-p">' + inlineFormat(line) + '</p>');
        }
        if (inCode) html.push('</code></pre>');
        if (inTable) html.push('</table>');
        return html.join('');
    }

    function inlineFormat(s) {
        s = esc(s);
        // **粗体**
        s = s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
        // `行内代码`
        s = s.replace(/`([^`]+)`/g, '<code class="md-inline-code">$1</code>');
        return s;
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
