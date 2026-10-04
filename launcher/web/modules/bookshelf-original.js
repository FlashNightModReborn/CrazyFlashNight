/** The original CF1 player has no access to the bookshelf save/reward protocol. */
(function(root) {
    'use strict';
    var CHANNEL = 'bookshelf-original.v1';
    function Original(host, toolbar, options) {
        this.host = host; this.toolbar = toolbar; this.options = options;
        this.frame = null; this.session = ''; this.paused = false; this.timer = null;
        this.receive = this.onMessage.bind(this);
        window.addEventListener('message', this.receive);
    }
    Original.prototype.show = function() {
        if (this.frame) return;
        var self = this;
        this.toolbar.innerHTML = '<button data-original="back">返回修理大学</button>'
            + '<span class="bookshelf-original-label">原版 · 无 SP 奖励</span>'
            + '<span class="bookshelf-original-keys">方向键移动 · E 重击 · R 轻击</span>'
            + '<button data-original="pause" disabled>暂停</button><button data-original="restart">重新开始</button>';
        this.get('back').onclick = this.options.back;
        this.get('pause').onclick = function() {
            if (!self.frame || !self.ready) return;
            self.frame.contentWindow.postMessage({channel:CHANNEL, session:self.session,
                action:self.paused ? 'play' : 'pause'}, '*');
        };
        this.get('restart').onclick = function() { self.hide(); self.show(); };
        this.session = crypto.randomUUID(); this.ready = false; this.paused = false;
        var frame = document.createElement('iframe'), message = document.createElement('p');
        frame.title = '闪客快打 1 原版';
        // No same-origin, popups, forms, storage access, top navigation or Host bridge.
        frame.setAttribute('sandbox', 'allow-scripts'); frame.setAttribute('allow', 'autoplay');
        frame.src = 'modules/bookshelf/original/player.html#' + this.session;
        message.className = 'bookshelf-original-status'; message.setAttribute('role', 'status');
        message.textContent = '正在翻开原版…';
        this.frame = frame; this.message = message; this.host.replaceChildren(frame, message);
        this.timer = setTimeout(function() {
            self.timer = null;
            if (!self.ready) { self.message.hidden = false; self.message.textContent = '原版载入较慢，可重新开始或返回修理大学。'; }
        }, 20000);
    };
    Original.prototype.get = function(name) { return this.toolbar.querySelector('[data-original="' + name + '"]'); };
    Original.prototype.onMessage = function(event) {
        var data = event.data;
        if (!this.frame || event.source !== this.frame.contentWindow || event.origin !== 'null'
                || !data || data.channel !== CHANNEL || data.session !== this.session) return;
        if (data.state === 'playing' || data.state === 'paused') {
            clearTimeout(this.timer); this.timer = null; this.ready = true;
            this.paused = data.state === 'paused';
            this.get('pause').disabled = false; this.get('pause').textContent = this.paused ? '继续' : '暂停';
            this.message.hidden = !this.paused; this.message.textContent = '原版已暂停';
            if (!this.paused) this.frame.focus();
        } else if (data.state === 'error') {
            clearTimeout(this.timer); this.timer = null; this.ready = false;
            this.get('pause').disabled = true; this.message.hidden = false;
            this.message.textContent = '原版未能载入，请重新开始。';
        }
    };
    Original.prototype.hide = function() {
        clearTimeout(this.timer); this.timer = null;
        this.session = ''; this.ready = false;
        if (this.frame) this.frame.remove(); this.frame = null;
        this.host.textContent = ''; this.toolbar.textContent = '';
    };
    Original.prototype.destroy = function() { this.hide(); window.removeEventListener('message', this.receive); };
    root.BookshelfOriginal = Original;
})(window);
