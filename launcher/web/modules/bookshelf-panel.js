(function() {
    'use strict';
    var R = window.BookshelfRuntime;
    var scriptBase = new URL('./', document.currentScript ? document.currentScript.src : location.href);
    var shell, host, scale, mux, originalMux, token, instance, state, recovery, slotSignature, reader, original, catalogRequest;
    var selected = null, busy = false, generation = 0, autoReturnAttempted = false, readFailed = false;
    var playingOriginal = false, statusAttention = false;
    var shelfScene = null, shelfLoading = null, shelfFailed = false, panelScale = 1, shelfAbort = null;
    var selectedChapter = 1, languages = {};
    var returning = false, transition = null, returnPoll = 0, transitionAck = '';
    var transitionEpoch = -1, transitionSequence = -1, transitionRevision = 0, transitionRetired = false;
    function el(id) { return host.querySelector('#bookshelf-' + id); }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell bookshelf-shell'; return shell; }
    function onOpen(element, data) {
        host = element; token = data.token; instance = data.panelInstanceId;
        state = null; recovery = ''; slotSignature = ''; busy = false; autoReturnAttempted = false; readFailed = false; generation++;
        playingOriginal = false; statusAttention = false;
        selected = null; shelfScene = null; shelfLoading = null; shelfFailed = false;
        returning = false; transition = null; transitionAck = '';
        transitionEpoch = -1; transitionSequence = -1; transitionRevision = 0; transitionRetired = false;
        selectedChapter = 1; languages = {};
        if (selected === 'repair-campus') selected = 'crazy-flasher';
        host.innerHTML = '<section class="bookshelf-panel"><header><div><span class="bookshelf-eyebrow">基地收藏室</span>'
            + '<h1 id="bookshelf-title">基地收藏室</h1></div><div id="bookshelf-reader-tools" class="bookshelf-reader-tools" hidden></div>'
            + '<div id="bookshelf-original-tools" class="bookshelf-original-tools" hidden></div>'
            + '<button id="bookshelf-toggle-nav" aria-expanded="true" aria-controls="bookshelf-directory">目录</button>'
            + '<button id="bookshelf-close" aria-label="关闭书架">×</button></header>'
            + '<div class="bookshelf-body"><nav id="bookshelf-directory" aria-label="书架目录"><button id="bookshelf-nav-overview" class="bookshelf-entry" type="button"><strong>置物架总览</strong><small>3D 书架与合集</small></button>'
            + '<h2>藏书</h2><div id="bookshelf-books"></div>'
            + '<h2>角色档案</h2><div id="bookshelf-slots"></div><p id="bookshelf-role" class="bookshelf-muted"></p></nav>'
            + '<main><div id="bookshelf-overview" hidden></div><div id="bookshelf-reader"></div><div id="bookshelf-original" hidden></div>'
            + '<article id="bookshelf-detail" hidden></article></main></div>'
            + '<footer><p id="bookshelf-status" role="status" aria-live="polite">正在读取书架…</p>'
            + '<button id="bookshelf-transition-retry" hidden>重试返回</button><button id="bookshelf-recover" hidden>核对结果</button></footer></section>';
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
        el('toggle-nav').onclick = function() {
            if (shelfScene) shelfScene.lockLayout();
            var collapsed = host.querySelector('.bookshelf-panel').classList.toggle('bookshelf-nav-collapsed');
            this.setAttribute('aria-expanded', String(!collapsed));
            if (selected === null) renderOverview();
        };
        el('nav-overview').onclick = function() {
            if (busy || returning) return;
            selected = null;
            if (shelfScene) shelfScene.home();
            host.querySelector('.bookshelf-panel').classList.remove('library-open');
            reader.get('library').setAttribute('aria-expanded', 'false'); render();
        };
        el('recover').onclick = function() { if (recovery) reconcile(); else read(); };
        el('transition-retry').onclick = function() { sendTransition('transitionAction', 'verb', 'retry'); };
        scale = PanelScale.attach(shell, 1024, 576, {onUpdate:function(value) {
            panelScale = value;
            if (shelfScene && host && selected === null) renderOverview();
        }});
        mux = new R.RequestMux({panelInstanceId:instance, send:function(message) { return Bridge.send(message); }});
        window.__bookshelfShelfQa = {
            state:function() { return shelfScene ? 'ready' : shelfFailed ? 'failed' : shelfLoading ? 'loading' : 'none'; },
            stats:function() { return shelfScene ? shelfScene.stats() : null; },
            targets:function() { return shelfScene ? shelfScene.targets() : null; }
        };
        render(); read(); ensureShelf();
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
    function selectFromShelf(id, disc) {
        if (!host || busy || returning) return;
        if (id === 'crazy-flasher' && /^cf[1-6]$/.test(disc)) selectedChapter = Number(disc.slice(2));
        if (id === 'slot:__more__') {
            status('更多档案在左侧角色档案列表。', false);
            var firstSlot = el('slots').querySelector('[data-slot]');
            if (firstSlot) firstSlot.focus();
            return;
        }
        if (id.indexOf('slot:') === 0) {
            var slotId = id.slice(5);
            if (!state || !(state.slots || []).some(function(s) { return s.slot === slotId; })) return;
            selected = id;
            host.querySelector('.bookshelf-panel').classList.remove('library-open');
            reader.get('library').setAttribute('aria-expanded', 'false'); render();
            var slotButton = el('slots').querySelector('[data-slot="' + slotId + '"]');
            if (slotButton) slotButton.focus({preventScroll:true});
            return;
        }
        if (!R.books.some(function(b) { return b.id === id; })) return;
        selected = id;
        host.querySelector('.bookshelf-panel').classList.remove('library-open');
        reader.get('library').setAttribute('aria-expanded', 'false'); render();
        var button = el('books').querySelector('[data-book="' + id + '"]');
        if (button) button.focus({preventScroll:true});
    }
    function ensureShelf() {
        if (shelfScene || shelfLoading || shelfFailed || !host) return;
        var g = generation;
        shelfAbort = new AbortController(); var loadSignal = shelfAbort.signal;
        shelfLoading = import(new URL('bookshelf-shelf-scene.js', scriptBase).href).then(function(module) {
            if (g !== generation || !host || loadSignal.aborted) return null;
            return module.createScene({width:el('overview').clientWidth || 802, height:el('overview').clientHeight || 481}, function() {
                if (g !== generation) return;
                shelfFailed = true;
                if (shelfScene) { shelfScene.dispose(); shelfScene = null; }
                if (host) render();
            }, selectFromShelf, loadSignal);
        }).then(function(scene) {
            if (g === generation) shelfLoading = null;
            if (!scene) return;
            if (g !== generation || shelfFailed) { scene.dispose(); return; }
            shelfScene = scene;
            if (host) render();
        }).catch(function(error) {
            if (g !== generation) return;
            shelfLoading = null;
            shelfFailed = true;
            if (typeof console !== 'undefined' && console.error) console.error(error);
            if (host) render();
        });
    }
    function renderOverview() {
        var ov = el('overview');
        if (shelfFailed) {
            if (!ov.querySelector('.bookshelf-shelf-fallback')) {
                ov.textContent = '';
                var box = document.createElement('div'); box.className = 'bookshelf-shelf-fallback';
                var text = document.createElement('p');
                text.textContent = '3D 置物架暂时不可用，请从左侧目录选择。';
                var retry = document.createElement('button'); retry.id = 'bookshelf-shelf-retry';
                retry.type = 'button'; retry.textContent = '重试';
                retry.onclick = function() { shelfFailed = false; ov.textContent = ''; ensureShelf(); render(); };
                box.append(text, retry); ov.appendChild(box);
            }
            return;
        }
        if (!shelfScene) {
            if (!ov.firstChild) {
                var loading = document.createElement('p'); loading.className = 'bookshelf-shelf-fallback';
                loading.textContent = '正在载入置物架…'; ov.appendChild(loading);
            }
            return;
        }
        if (shelfScene.canvas.parentElement !== ov) {
            ov.textContent = ''; ov.appendChild(shelfScene.canvas); ov.appendChild(shelfScene.ui);
        }
        var w = ov.clientWidth, h = ov.clientHeight;
        if (w && h) {
            // Render at the actual display density: the panel shell is upscaled by a
            // CSS transform (PanelScale), so layout pixels alone blur text textures.
            var eff = Math.min(2, Math.max(0.5, panelScale * (window.devicePixelRatio || 1)));
            var rw = Math.round(w * eff), rh = Math.round(h * eff);
            if (shelfScene.canvas.width !== rw || shelfScene.canvas.height !== rh) shelfScene.view.resize(rw, rh);
        }
        shelfScene.render();
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
    function pollReturn(delay) {
        clearTimeout(returnPoll);
        var g = generation;
        returnPoll = setTimeout(function() {
            if (g === generation && returning && !busy) request('query', {v:1, token:recovery || token});
        }, delay || 400);
    }
    function sendTransition(cmd, key, value) {
        if (!host || !transition || !returning) return false;
        var payload = {type:cmd === 'transitionAction' ? 'scene_transition_action' : 'scene_transition_presented',
            requestId:transition.requestId, revision:transition.revision, generation:transition.generation};
        payload[key] = value;
        return Bridge.send({type:'panel', panel:'bookshelf', domain:'bookshelf', cmd:cmd, panelInstanceId:instance, payload:payload}) !== false;
    }
    function acknowledgeTransition() {
        var current = transition, g = generation;
        if (!current || !host || !returning || document.hidden || current.connected === false) return;
        var kind = current.phase === 'reveal' ? current.revealAllowed ? 'revealed' : ''
            : current.phase === 'cover' || current.phase === 'loading' ? 'covered' : '';
        var key = current.requestId + ':' + current.revision + ':' + current.generation + ':' + kind;
        if (!kind || transitionAck === key) return;
        requestAnimationFrame(function() { requestAnimationFrame(function() {
            if (g !== generation || current !== transition || !host || document.hidden) return;
            if (sendTransition('transitionPresented', 'kind', kind)) transitionAck = key;
        }); });
    }
    Bridge.on('bookshelf_transition', function(data) {
        if (!host || data.panelInstanceId !== instance) return;
        var sequence = /^tr:[1-9][0-9]*$/.test(data.requestId) ? Number(data.requestId.slice(3)) : NaN;
        if (!Number.isSafeInteger(sequence) || !Number.isSafeInteger(data.generation) || !Number.isSafeInteger(data.revision)
                || data.revision < 1 || data.generation < transitionEpoch
                || data.generation === transitionEpoch && (sequence < transitionSequence
                    || sequence === transitionSequence && (data.revision < transitionRevision || transitionRetired))) return;
        transitionEpoch = data.generation; transitionSequence = sequence; transitionRevision = data.revision; transitionRetired = false;
        // A transport send is not Host acceptance. Each valid re-projection gets a fresh painted receipt.
        returning = true; transition = data; transitionAck = '';
        if (data.phase === 'error') status('返回场景暂时未能载入。可重试返回，奖励不会重复领取。');
        else status('正在恢复原角色。可以查看本局结果，请稍候…', false);
        render(); acknowledgeTransition();
    });
    Bridge.on('bookshelf_transition_complete', function(data) {
        if (!host || data.panelInstanceId !== instance || !transition || data.requestId !== transition.requestId
                || data.generation !== transition.generation || data.revision !== transition.revision) return;
        transitionRetired = true;
        transition = null; transitionAck = ''; render(); if (returning) pollReturn();
    });
    document.addEventListener('visibilitychange', acknowledgeTransition);
    function receive(cmd, result) {
        if (cmd === 'snapshot') readFailed = !result.success;
        if (result.nextToken && /^(bookshelf\.)[A-Za-z0-9._~-]+$/.test(result.nextToken)
                && (result.phase === 'applied' || result.phase === 'expired') && !result.requiresReconcile) {
            returning = false; clearTimeout(returnPoll);
            token = result.nextToken; recovery = ''; read(); return;
        }
        if (result.requiresReconcile) recovery = result.recoveryToken || recovery || token;
        else if (cmd === 'query' && (result.phase === 'applied' || result.phase === 'expired')) recovery = '';
        if (cmd === 'query' && !recovery && result.phase && !returning) { read(); return; }
        if (result.outcomePending) recovery = token;
        else if (cmd === 'query' && result.phase === 'editing' && !result.requiresReconcile) recovery = '';
        if (result.phase) {
            if (!state && (result.inRun || result.pendingRun)) { selected = 'crazy-flasher'; selectedChapter = 1; }
            state = result;
        }
        if (result.phase === 'switching') {
            if (result.kind === 'return') {
                returning = true; selected = 'crazy-flasher'; selectedChapter = 1;
                status('正在恢复原角色。可以查看本局结果，请稍候…', false); render(); pollReturn();
            } else { status('正在翻开另一段人生…'); close(true); }
            return;
        }
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
        if (returning && cmd === 'query') pollReturn(result.success ? 400 : 2000);
        if (cmd === 'snapshot' && result.success && result.phase === 'editing'
                && result.exitRequired && result.inRun && result.canSwitch && !recovery && !autoReturnAttempted) {
            autoReturnAttempted = true;
            status('正在结束旅程，恢复原角色…');
            commit('return', result.originSlot);
        }
    }
    function render() {
        if (!host) return;
        el('close').disabled = busy || returning || !!transition || !!(state && state.exitRequired && state.inRun);
        el('transition-retry').hidden = !transition || transition.phase !== 'error';
        el('transition-retry').disabled = !!transition && (transition.actionPending || transition.connected === false);
        var overview = selected === null;
        var book = overview ? null : R.books.find(function(b) { return b.id === selected; });
        host.querySelectorAll('[data-book]').forEach(function(b) { b.setAttribute('aria-current', String(b.dataset.book === selected)); });
        el('nav-overview').setAttribute('aria-current', String(overview));
        var reading = book && book.pages > 0;
        if (selected !== 'crazy-flasher' || !state || state.inRun || state.pendingRun || recovery || readFailed) playingOriginal = false;
        var chapter = book && book.format === 'playable' && book.chapters[selectedChapter - 1];
        var panel = host.querySelector('.bookshelf-panel');
        el('reader').hidden = !reading; el('reader-tools').hidden = !reading;
        el('overview').hidden = !overview;
        el('detail').hidden = overview || reading || playingOriginal;
        el('original').hidden = el('original-tools').hidden = !playingOriginal;
        panel.classList.toggle('is-overview', overview);
        panel.classList.toggle('is-reading', !!reading); panel.classList.toggle('is-original', playingOriginal);
        panel.classList.toggle('needs-attention', statusAttention || busy || !!recovery || readFailed || !state);
        el('title').textContent = overview ? '基地收藏室' : playingOriginal ? '闪客快打 ' + selectedChapter : book ? book.title : '角色档案';
        if (shelfScene) {
            var archiveSlots = state && state.slots || [];
            var ordered = archiveSlots.slice().sort(function(a, b) {
                return (b.slot === state.activeSlot ? 1 : 0) - (a.slot === state.activeSlot ? 1 : 0);
            });
            var items = ordered.map(function(s) {
                return {id: 'slot:' + s.slot, name: s.name, active: !!state && state.activeSlot === s.slot};
            });
            shelfScene.setArchives(items);
        }
        if (playingOriginal && chapter) original.show({chapter:selectedChapter, language:languages[selectedChapter] || 'cn'}); else original.hide();
        if (reading) {
            reader.show(book);
        } else if (playingOriginal) {
            reader.hide();
        } else if (overview) {
            reader.hide();
            renderOverview();
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
                    if (chapter.remake.available) {
                        var records = document.createElement('section'); records.className = 'bookshelf-run-records';
                        records.setAttribute('aria-label', '修理大学挑战记录');
                        detail.appendChild(records);
                    }
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
                        ? '首次通关或刷新个人纪录：45 SP；其他通关：5 SP。未通关或中途离开不发奖励。按未暂停的游戏时间计时；剧情、商店和暂停不计入成绩。'
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
            action.disabled = action.disabled || busy || !!recovery || readFailed || returning || !!transition;
            if (chapter && chapter.remake.available) renderRecords(detail.querySelector('.bookshelf-run-records'));
        }
        el('recover').textContent = recovery ? '核对结果' : '重新读取';
        el('recover').hidden = returning && state && state.phase === 'switching' && !readFailed && !statusAttention
            || !recovery && !readFailed && !!state; el('recover').disabled = busy;
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
    function runTime(value) {
        if (!(value > 0 && value < 86400000)) return '未记录';
        return Math.floor(value / 60000) + ':' + String(Math.floor(value / 1000) % 60).padStart(2, '0')
            + '.' + String(Math.floor(value / 10) % 100).padStart(2, '0');
    }
    function renderRecords(node) {
        if (!node) return;
        var records = state && state.records || {}, history = Array.isArray(records.history) ? records.history : [];
        var pending = state && state.returningResult;
        var last = history[0] || null;
        if (pending && (!last || pending.runId !== last.runId)) last = pending;
        var signature = JSON.stringify([records, last]);
        if (node.dataset.records === signature) return;
        node.dataset.records = signature;
        var expanded = node.querySelector('details') && node.querySelector('details').open;
        node.textContent = '';
        function line(tag, text, cls, parent) {
            var n = document.createElement(tag); n.textContent = text; if (cls) n.className = cls;
            (parent || node).appendChild(n); return n;
        }
        var labels = {victory:'通关', failure:'挑战失败', defeat:'挑战失败', retreat:'主动撤退', abandoned:'中途结束'};
        var reasons = {first_clear:'首次通关', personal_best:'刷新个人纪录', clear:'通关奖励', debug:'调试局，不计成绩', incomplete:'未通关，无奖励', pending:'奖励确认中'};
        line('p', '个人最佳 ' + runTime(records.bestMs) + '　·　累计通关 ' + (records.clears || 0) + ' 次', 'bookshelf-record-summary');
        if (last) {
            var card = line('div', '', 'bookshelf-last-run');
            line('strong', (last.reason === 'pending' ? '本局' : '上一局') + ' · ' + (labels[last.outcome] || '中途结束'), '', card);
            line('span', '有效用时 ' + runTime(last.elapsedMs), '', card);
            var reason = last.debug ? reasons.debug : reasons[last.reason] || '';
            line('b', last.sp > 0 ? '+' + last.sp + ' SP · 已入账' : last.reason === 'pending' ? reasons.pending : '本局无 SP 奖励', 'bookshelf-record-reward', card);
            line('small', reason, 'bookshelf-muted', card);
        } else line('p', '尚无详细战绩。旧档最佳用时继续保留，新挑战将在这里记录。', 'bookshelf-muted');
        if (history.length) {
            var details = line('details', '', 'bookshelf-history'); details.open = expanded;
            line('summary', '最近挑战记录 · ' + history.length + ' 局（最多保留 20 局）', '', details);
            var table = line('table', '', '', details), head = line('tr', '', '', line('thead', '', '', table));
            ['结果', '有效用时', '奖励', '完成时间'].forEach(function(title) { line('th', title, '', head); });
            var body = line('tbody', '', '', table);
            history.forEach(function(record) {
                var row = line('tr', '', '', body);
                line('td', (labels[record.outcome] || '中途结束') + (record.debug ? ' · 调试' : ''), '', row);
                line('td', runTime(record.elapsedMs), '', row);
                line('td', record.sp > 0 ? '+' + record.sp + ' SP' : '—', '', row);
                line('td', record.completedAt > 0 ? new Date(record.completedAt).toLocaleString('zh-CN',
                    {month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', hour12:false}) : '未记录', '', row);
            });
        }
    }
    function close(transitionAccepted) {
        if (transitionAccepted === 'escape' && selected === null && shelfScene
            && shelfScene.stats().mode !== 'overview') {
            shelfScene.returnToOverview(); return false;
        }
        if (!host || busy || returning || transition || (transitionAccepted !== true && state && state.exitRequired && state.inRun)) return false;
        if (Bridge.send({type:'panel', panel:'bookshelf', cmd:'close', panelInstanceId:instance}) === false) return false;
        Panels.close(); return true;
    }
    function cleanup() {
        if (shelfAbort) { shelfAbort.abort(); shelfAbort = null; }
        clearTimeout(returnPoll); returning = false; transition = null; transitionAck = '';
        generation++; if (mux) mux.destroy(); if (scale) scale.detach();
        if (catalogRequest) catalogRequest.abort(); catalogRequest = null;
        if (shelfScene) shelfScene.dispose(); shelfScene = null; shelfLoading = null; shelfFailed = false;
        if (window.__bookshelfShelfQa) delete window.__bookshelfShelfQa;
        if (reader) reader.destroy(); reader = null;
        if (original) original.destroy(); original = null; playingOriginal = false;
        if (originalMux) originalMux.destroy(); originalMux = null;
        host = mux = scale = state = null; recovery = ''; slotSignature = ''; busy = false;
        if (shell) shell.textContent = '';
    }
    Panels.register('bookshelf', {create:create, onOpen:onOpen, onRebind:function(element,data) { cleanup(); onOpen(element,data); }, onClose:cleanup, onRequestClose:close, onForceClose:cleanup});
})();
