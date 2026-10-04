(function() {
    'use strict';
    var R = window.BookshelfRuntime;
    var shell, host, scale, mux, originalMux, token, instance, state, recovery, slotSignature, reader, original, catalogRequest;
    var selected = 'dust', busy = false, generation = 0, autoReturnAttempted = false, readFailed = false;
    var playingOriginal = false, statusAttention = false;
    var selectedChapter = 1, languages = {};
    function el(id) { return host.querySelector('#bookshelf-' + id); }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell bookshelf-shell'; return shell; }
    function onOpen(element, data) {
        host = element; token = data.token; instance = data.panelInstanceId;
        state = null; recovery = ''; slotSignature = ''; busy = false; autoReturnAttempted = false; readFailed = false; generation++;
        playingOriginal = false; statusAttention = false;
        selectedChapter = 1; languages = {};
        if (selected === 'repair-campus') selected = 'crazy-flasher';
        host.innerHTML = '<section class="bookshelf-panel"><header><div><span class="bookshelf-eyebrow">基地藏书室</span>'
            + '<h1 id="bookshelf-title">基地藏书室</h1></div><div id="bookshelf-reader-tools" class="bookshelf-reader-tools" hidden></div>'
            + '<div id="bookshelf-original-tools" class="bookshelf-original-tools" hidden></div>'
            + '<button id="bookshelf-close" aria-label="关闭书架">×</button></header>'
            + '<div class="bookshelf-body"><nav aria-label="书架目录"><h2>藏书</h2><div id="bookshelf-books"></div>'
            + '<h2>角色档案</h2><div id="bookshelf-slots"></div><p id="bookshelf-role" class="bookshelf-muted"></p></nav>'
            + '<main><div id="bookshelf-reader"></div><div id="bookshelf-original" hidden></div>'
            + '<article id="bookshelf-detail" hidden></article></main></div>'
            + '<footer><p id="bookshelf-status" role="status" aria-live="polite">正在读取书架…</p><button id="bookshelf-recover" hidden>核对结果</button></footer></section>';
        reader = new window.BookshelfReader(el('reader'), {toolbar:el('reader-tools'), focus:function(focused) {
            var panel = host.querySelector('.bookshelf-panel');
            panel.classList.toggle('reading-focus', focused);
            if (focused) { panel.classList.remove('library-open'); reader.get('library').setAttribute('aria-expanded', 'false'); }
        }, library:function() {
            var panel = host.querySelector('.bookshelf-panel');
            panel.classList.toggle('library-open');
            reader.get('library').setAttribute('aria-expanded', String(panel.classList.contains('library-open')));
        }});
        originalMux = new R.RequestMux({domain:'bookshelf-original', panelInstanceId:instance, send:function(message) { return Bridge.send(message); }});
        original = new window.BookshelfOriginal(el('original'), el('original-tools'), {prepare:function(definition, done) {
            originalMux.request('prepare', {v:1, token:token, chapter:definition.chapter, language:definition.language}, done);
        }, release:function(session) {
            if (originalMux) originalMux.request('release', {v:1, session:session}, function() {});
        }, back:function() {
            playingOriginal = false; render();
            el('detail').querySelector('[data-action="original"]').focus();
        }});
        renderBooks();
        el('close').onclick = close;
        el('recover').onclick = function() { if (recovery) reconcile(); else read(); };
        scale = PanelScale.attach(shell, 1024, 576);
        mux = new R.RequestMux({panelInstanceId:instance, send:function(message) { return Bridge.send(message); }});
        render(); read();
        var g = generation; catalogRequest = new AbortController();
        fetch('assets/bookshelf/catalog.json', {signal:catalogRequest.signal}).then(function(response) {
            if (!response.ok) throw new Error('catalog_unavailable'); return response.json();
        }).then(function(catalog) {
            if (g !== generation) return;
            R.adoptCatalog(catalog); renderBooks(); render(); catalogRequest = null;
        }).catch(function(error) {
            if (g === generation && error.name !== 'AbortError') status('新增藏书目录未能载入，请重新打开书架。');
        });
    }
    function renderBooks() {
        var focused = document.activeElement && document.activeElement.dataset.book;
        el('books').textContent = '';
        R.books.forEach(function(book) {
            var b = document.createElement('button'); b.className = 'bookshelf-entry'; b.dataset.book = book.id;
            var title = document.createElement('strong'), subtitle = document.createElement('small');
            title.textContent = book.title; subtitle.textContent = book.subtitle; b.append(title, subtitle);
            b.onclick = function() {
                selected = book.id;
                host.querySelector('.bookshelf-panel').classList.remove('library-open');
                reader.get('library').setAttribute('aria-expanded', 'false'); render();
            };
            el('books').appendChild(b); if (focused === book.id) b.focus({preventScroll:true});
        });
    }
    function status(text, attention) {
        statusAttention = attention !== false;
        if (host) {
            el('status').textContent = text;
            host.querySelector('.bookshelf-panel').classList.toggle('needs-attention', statusAttention || busy || !!recovery || readFailed || !state);
        }
    }
    function request(cmd, payload) {
        if (!mux || busy) return;
        busy = true; var g = generation; render();
        mux.request(cmd, payload, function(result) { if (g !== generation) return; busy = false; receive(cmd, result); });
    }
    function read() { request('snapshot', {v:1, token:token}); }
    function reconcile() { if (recovery) request('query', {v:1, token:recovery}); }
    function commit(kind, target) { request('commit', {v:1, token:token, kind:kind, target:target}); }
    function receive(cmd, result) {
        if (cmd === 'snapshot') readFailed = !result.success;
        if (result.nextToken && /^(bookshelf\.)[A-Za-z0-9._~-]+$/.test(result.nextToken)
                && (result.phase === 'applied' || result.phase === 'expired') && !result.requiresReconcile) {
            token = result.nextToken; recovery = ''; read(); return;
        }
        if (result.requiresReconcile) recovery = result.recoveryToken || recovery || token;
        else if (cmd === 'query' && (result.phase === 'applied' || result.phase === 'expired')) recovery = '';
        if (cmd === 'query' && !recovery && result.phase) { read(); return; }
        if (result.outcomePending) recovery = token;
        else if (cmd === 'query' && result.phase === 'editing' && !result.requiresReconcile) recovery = '';
        if (result.phase) {
            if (!state && (result.inRun || result.pendingRun)) { selected = 'crazy-flasher'; selectedChapter = 1; }
            state = result;
        }
        if (result.phase === 'switching') { status('正在翻开另一段人生…'); close(true); return; }
        if (result.requiresReconcile && cmd === 'snapshot') { reconcile(); return; }
        if (result.phase === 'save_pending') status('正在确认保存结果。核对完成前，请保留当前角色。');
        else if (result.phase === 'applied') { status('已完成。', false); recovery = ''; }
        else if (result.success) status(result.inRun ? '书中装备和成长只属于本次旅程。' : result.lastReward > 0 ? '上次重制版旅程获得 ' + result.lastReward + ' SP。' : '翻阅藏书，或走进另一段人生。', false);
        else {
            var messages = {busy:'仍有操作尚未完成，请稍后重试。', locked:'请先完成地铁站主线，或处理上一次旅程。',
                config_unavailable:'关卡配置未能载入。请检查配置，稍后重新打开书架。', slot_corrupt:'这个档案需要在启动入口修复。', slot_needs_migration:'请先从启动入口读取一次这个旧档案。',
                slot_repairable:'这个档案需要在启动入口确认修复。', invalid_target:'档案状态已变化，请重新打开书架。',
                client_timeout:'暂未收到结果，请核对原操作。', not_sent:'请求未能发送，请稍后重试。', timeout:'暂未收到结果，请核对原操作。', disconnected:'游戏连接暂时不可用。', save_unavailable:'档案暂时不可读取。'};
            status(messages[result.error] || '操作未完成，请重新读取或核对结果。');
        }
        render();
        if (cmd === 'snapshot' && result.success && result.phase === 'editing'
                && result.exitRequired && result.inRun && result.canSwitch && !recovery && !autoReturnAttempted) {
            autoReturnAttempted = true;
            status('正在结束旅程，恢复原角色…');
            commit('return', result.originSlot);
        }
    }
    function render() {
        if (!host) return;
        el('close').disabled = busy || !!(state && state.exitRequired && state.inRun);
        var book = R.books.find(function(b) { return b.id === selected; });
        host.querySelectorAll('[data-book]').forEach(function(b) { b.setAttribute('aria-current', String(b.dataset.book === selected)); });
        var reading = book && book.pages > 0;
        if (selected !== 'crazy-flasher' || !state || state.inRun || state.pendingRun || recovery || readFailed) playingOriginal = false;
        var chapter = book && book.format === 'playable' && book.chapters[selectedChapter - 1];
        var panel = host.querySelector('.bookshelf-panel');
        el('reader').hidden = !reading; el('reader-tools').hidden = !reading;
        el('detail').hidden = reading || playingOriginal;
        el('original').hidden = el('original-tools').hidden = !playingOriginal;
        panel.classList.toggle('is-reading', !!reading); panel.classList.toggle('is-original', playingOriginal);
        panel.classList.toggle('needs-attention', statusAttention || busy || !!recovery || readFailed || !state);
        el('title').textContent = playingOriginal ? '闪客快打 ' + selectedChapter : book ? book.title : '角色档案';
        if (playingOriginal && chapter) original.show({chapter:selectedChapter, language:languages[selectedChapter] || 'cn'}); else original.hide();
        if (reading) {
            reader.show(book);
        } else if (playingOriginal) {
            reader.hide();
        } else {
            reader.hide();
            var detail = el('detail');
            var detailKey = selected + (chapter ? ':' + selectedChapter : '');
            if (detail.dataset.view !== detailKey) {
                detail.textContent = ''; detail.dataset.view = detailKey;
                if (chapter) {
                    detail.innerHTML = '<div class="bookshelf-chapters" role="group" aria-label="闪客快打章节"></div>'
                        + '<h2></h2><p class="bookshelf-campus-intro">翻开系列中的一章，选择原版或重制版。</p>'
                        + '<div class="bookshelf-editions"><section><span class="bookshelf-edition-tag">原版</span><h3></h3>'
                        + '<p data-edition="original-description"></p><label class="bookshelf-language">语言 <select data-action="language" aria-label="原版语言"></select></label>'
                        + '<p class="bookshelf-edition-note">独立游玩 · 不提供配给与 SP 奖励</p><button data-action="original">游玩原版</button></section>'
                        + '<section><span class="bookshelf-edition-tag">重制版</span><h3></h3>'
                        + '<p data-edition="remake-description"></p><p class="bookshelf-edition-note" data-edition="remake-note"></p>'
                        + '<button class="bookshelf-primary" data-action="remake"></button></section></div>';
                    book.chapters.forEach(function(c, i) {
                        var button = document.createElement('button'); button.dataset.chapter = i + 1;
                        button.textContent = '第 ' + (i + 1) + ' 章'; button.setAttribute('aria-label', '第 ' + (i + 1) + ' 章 ' + c.title);
                        button.setAttribute('aria-pressed', String(i + 1 === selectedChapter));
                        button.onclick = function() { selectedChapter = i + 1; render();
                            detail.querySelector('[data-chapter="' + selectedChapter + '"]').focus({preventScroll:true}); };
                        detail.querySelector('.bookshelf-chapters').appendChild(button);
                    });
                    detail.querySelector('h2').textContent = '第 ' + selectedChapter + ' 章 · ' + chapter.title;
                    var titles = detail.querySelectorAll('.bookshelf-editions h3');
                    titles[0].textContent = '闪客快打 ' + selectedChapter;
                    titles[1].textContent = chapter.remake.available ? '修理大学 · 七图历险' : '尚未制作';
                    detail.querySelector('[data-edition="original-description"]').textContent = selectedChapter === 1
                        ? '重温 Andy 的校园往事。随时返回章节，重新载入会从头开始。'
                        : '读取本机正版合集中的游戏，体验原有剧情与战斗。' + (selectedChapter >= 3 ? '存档与当前角色独立。' : '');
                    detail.querySelector('[data-edition="remake-description"]').textContent = chapter.remake.available
                        ? '从 1 级 Andy Law 开始，挑选配给，学习技能，挑战修理大学。本次旅程不支持中途续玩。'
                        : '这一章的重制历险尚未制作。';
                    detail.querySelector('[data-edition="remake-note"]').textContent = chapter.remake.available
                        ? '首次通关或刷新个人纪录：45 SP；其他通关：5 SP。未通关或中途离开不发奖励。计时包含暂停、商店和过场。'
                        : '原版不提供闪客快打 7 的奖励。';
                    var language = detail.querySelector('[data-action="language"]');
                    chapter.original.languages.forEach(function(code) { var option = document.createElement('option');
                        option.value = code; option.textContent = code === 'cn' ? '中文' : 'English'; language.appendChild(option); });
                    language.value = languages[selectedChapter] || 'cn'; language.parentElement.hidden = selectedChapter === 1;
                    language.onchange = function() { languages[selectedChapter] = language.value; };
                } else detail.append(document.createElement('h2'), document.createElement('p'), document.createElement('button'));
            }
            var heading = detail.children[0], text = detail.children[1];
            var action = chapter ? detail.querySelector('[data-action="remake"]') : detail.children[2];
            action.className = 'bookshelf-primary';
            if (selected.indexOf('slot:') === 0) {
                var slot = selected.slice(5), entry = state && (state.slots || []).find(function(s) { return s.slot === slot; });
                heading.textContent = entry ? entry.name : '角色档案';
                text.textContent = '保存当前角色，经过场切换至这个档案。两位角色的装备、技能与任务进度各自保留。';
                action.textContent = state && state.activeSlot === slot ? '当前角色' : '切换角色';
                action.disabled = !state || state.activeSlot === slot || !state.canSwitch || state.inRun || !!state.pendingRun;
                action.onclick = function() { commit('switch', slot); };
            } else if (chapter) {
                var originalAction = detail.querySelector('[data-action="original"]');
                originalAction.disabled = !state || !state.canSwitch || state.inRun || !!state.pendingRun || busy || !!recovery || readFailed;
                originalAction.textContent = state && (state.inRun || state.pendingRun) ? '结束重制版旅程后游玩' : '游玩原版';
                originalAction.onclick = function() { playingOriginal = true; render(); };
                if (!chapter.remake.available) {
                    action.textContent = '尚未制作'; action.onclick = null; action.disabled = true;
                } else if (state && state.inRun) {
                    action.textContent = '结束旅程，返回原角色'; action.onclick = function() { commit('return', state.originSlot); };
                } else if (state && state.pendingRun) {
                    action.textContent = '核对上次旅程'; action.onclick = function() { commit('settle', state.pendingRun); };
                } else {
                    action.textContent = state && state.unlocked ? '进入重制版' : '完成地铁站主线后开放';
                    action.onclick = function() { commit('play', 'repair-campus'); };
                }
                action.disabled = !chapter.remake.available || !state || !state.canSwitch || (!state.inRun && !state.pendingRun && !state.unlocked);
            }
            action.disabled = action.disabled || busy || !!recovery || readFailed;
        }
        el('recover').textContent = recovery ? '核对结果' : '重新读取';
        el('recover').hidden = !recovery && !readFailed && !!state; el('recover').disabled = busy;
        el('role').textContent = state ? '当前：' + state.role : '';
        var slots = el('slots'), entries = state && state.slots || [];
        var signature = JSON.stringify(entries);
        if (signature !== slotSignature) {
            var focused = document.activeElement && document.activeElement.dataset.slot;
            var scroll = slots.parentElement.scrollTop;
            slots.textContent = ''; slotSignature = signature;
            entries.forEach(function(slot) {
                var b = document.createElement('button'); b.className = 'bookshelf-slot'; b.dataset.slot = slot.slot;
                b.onclick = function() { selected = 'slot:' + slot.slot; render(); }; slots.appendChild(b);
                if (focused === slot.slot) b.focus({preventScroll:true});
            });
            slots.parentElement.scrollTop = scroll;
        }
        Array.from(slots.children).forEach(function(b, i) {
            b.textContent = (entries[i].slot === state.activeSlot ? '● ' : '') + entries[i].name;
            b.setAttribute('aria-current', String(selected === 'slot:' + entries[i].slot));
        });
    }
    function close(transitionAccepted) {
        if (!host || busy || (transitionAccepted !== true && state && state.exitRequired && state.inRun)) return false;
        if (Bridge.send({type:'panel', panel:'bookshelf', cmd:'close', panelInstanceId:instance}) === false) return false;
        Panels.close(); return true;
    }
    function cleanup() {
        generation++; if (mux) mux.destroy(); if (scale) scale.detach();
        if (catalogRequest) catalogRequest.abort(); catalogRequest = null;
        if (reader) reader.destroy(); reader = null;
        if (original) original.destroy(); original = null; playingOriginal = false;
        if (originalMux) originalMux.destroy(); originalMux = null;
        host = mux = scale = state = null; recovery = ''; slotSignature = ''; busy = false;
        if (shell) shell.textContent = '';
    }
    Panels.register('bookshelf', {create:create, onOpen:onOpen, onRebind:function(element,data) { cleanup(); onOpen(element,data); }, onClose:cleanup, onRequestClose:close, onForceClose:cleanup});
})();
