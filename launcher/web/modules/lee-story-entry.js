(function() {
    'use strict';
    // This view owns no save data. The shared BookshelfTask owns the write fence,
    // generated run slot and settings admission; AS2 checks the real reader twice.
    function Entry(options) {
        this.options = options; this.busy = false; this.recovery = ''; this.token = ''; this.settling = false;
        this.dead = false; this.serial = 0; this.timer = 0; this.button = null;
        this.mux = new BookshelfRuntime.RequestMux({panel:'intelligence', panelInstanceId:options.instance,
            send:function(message) { return Bridge.send(message); }});
    }
    Entry.prototype.mount = function(parent) {
        var card = document.createElement('section'); card.className = 'intel-lee-story';
        card.setAttribute('aria-label', 'Lee · 攻入黑龙堂');
        card.innerHTML = '<p class="intel-lee-kicker">尘封往事</p><h2>Lee · 攻入黑龙堂</h2>'
            + '<p>孤身闯入，闸门在身后落下。扮演 Lee，突破守卫与机关，走到黑龙堂主面前。</p>'
            + '<p class="intel-lee-notes">从 35 级 Lee 开始。本篇的装备与成长独立，结束后回到原角色；途中离开将结束本次挑战。</p>'
            + '<p class="intel-lee-notes">沿用当前按键设置。可从「装备 → 技能」拖动调整招式快捷栏，下次挑战沿用你的配置。</p>'
            + '<button type="button" class="intel-toggle-btn intel-story-entry">开始挑战</button>';
        parent.appendChild(card); this.button = card.querySelector('button');
        var self = this; this.button.onclick = function() { self.start(); }; this.paint();
    };
    Entry.prototype.paint = function() {
        if (!this.button) return;
        this.button.disabled = this.busy;
        this.button.textContent = this.busy ? '正在准备…' : this.recovery ? '核对出发结果' : '开始挑战';
    };
    Entry.prototype.say = function(text) { if (!this.dead) this.options.status(text); };
    Entry.prototype.blocked = function() { return this.busy || !!this.recovery; };
    Entry.prototype.start = function() {
        if (this.dead || this.busy) return;
        if (this.recovery) { this.request('query', {v:1, token:this.recovery}); return; }
        var self = this, serial = ++this.serial;
        this.busy = true; this.paint(); this.say('正在准备挑战…');
        // Preparation only grants a read capability. Its timeout may retry;
        // the later save command has a separate durable unknown-write fence.
        this.timer = setTimeout(function() {
            if (self.dead || serial !== self.serial) return;
            self.serial++; self.busy = false; self.paint(); self.say('暂时未能读取挑战，请重试。');
        }, 12000);
        this.options.prepare(function(result) {
            if (self.dead || serial !== self.serial) return;
            clearTimeout(self.timer); self.busy = false;
            if (!result.success || typeof result.token !== 'string' || !/^bookshelf\.[A-Za-z0-9._~-]+$/.test(result.token)) {
                self.paint(); self.say(result.error === 'locked' ? '请先集齐黑龙令，并启用满级解密。'
                    : result.error === 'other_run_active' ? '请先完成或结束当前正在进行的另一段挑战。'
                    : '暂时无法准备挑战，请稍后重试。'); return;
            }
            self.token = result.token; self.settling = false;
            self.request('snapshot', {v:1, token:self.token}, true);
        });
    };
    Entry.prototype.request = function(cmd, payload, startAfterRead) {
        var self = this;
        this.busy = true; this.paint();
        this.mux.request(cmd, payload, function(result) {
            if (self.dead) return;
            self.busy = false;
            // Close only on an admitted Lee play, never merely on send=true.
            if (result.success && result.kind === 'play' && result.target === 'lee-trial'
                    && (result.phase === 'switching' || result.phase === 'applied')) {
                self.settling = false; self.recovery = ''; self.say('正在进入黑龙堂…'); self.paint(); self.options.close(); return;
            }
            if (result.success && result.kind === 'settle' && result.phase === 'applied'
                    && typeof result.nextToken === 'string' && /^bookshelf\.[A-Za-z0-9._~-]+$/.test(result.nextToken)
                    && (startAfterRead || self.settling) && self.button && self.button.isConnected) {
                self.settling = false; self.recovery = ''; self.token = result.nextToken;
                self.request('snapshot', {v:1, token:self.token}, true); return;
            }
            if (result.requiresReconcile || result.phase === 'save_pending') {
                self.recovery = result.recoveryToken || self.recovery || self.token;
                self.say(self.settling ? '正在整理上次挑战记录并准备出发…' : '正在核对出发结果。请核对后继续，避免重复开始。');
                self.paint();
                // Poll only the accepted save receipt. Never replay the mutation.
                // A normal pending save continues to the first room without a second click.
                if (result.phase === 'save_pending' || cmd === 'snapshot') {
                    clearTimeout(self.timer);
                    self.timer = setTimeout(function() {
                        if (!self.dead && !self.busy && self.recovery)
                            self.request('query', {v:1,token:self.recovery});
                    }, 400);
                }
                return;
            }
            if (cmd === 'query') {
                self.settling = false;
                if (result.phase === 'expired' || result.phase === 'applied') {
                    self.recovery = ''; self.token = result.nextToken || '';
                    self.say('出发未完成，可以重新开始挑战。');
                } else self.say('结果尚未确认，请稍后再次核对。');
                self.paint(); return;
            }
            if (cmd === 'snapshot' && startAfterRead && result.success && result.phase === 'editing'
                    && result.leeEntry === true && result.canSwitch === true && !result.inRun
                    && self.button && self.button.isConnected) {
                if (!result.pendingRun) {
                    self.settling = false;
                    self.say('正在保存当前角色并准备出发…');
                    self.request('commit', {v:1, token:self.token, kind:'play', target:'lee-trial'}); return;
                }
                if (result.pendingBookId === 'lee-trial' && /^bookrun_[A-Za-z0-9._~-]{1,120}$/.test(result.pendingRun)) {
                    self.settling = true;
                    self.say('正在整理上次挑战记录并准备出发…');
                    self.request('commit', {v:1, token:self.token, kind:'settle', target:result.pendingRun}, true); return;
                }
            }
            self.settling = false;
            self.paint();
            self.say(result.error === 'locked' ? '挑战条件已变化，请重新阅读黑龙令。'
                : '暂时无法出发，请完成当前操作后重试。');
        });
    };
    Entry.prototype.destroy = function() {
        this.dead = true; this.serial++; clearTimeout(this.timer); this.mux.destroy(); this.button = null;
    };
    window.LeeStoryEntry = Entry;
})();
