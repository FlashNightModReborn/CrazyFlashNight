/** Presentation-only controls for an isolated, Host-authorized original movie. */
(function(root) {
    'use strict';
    var CHANNEL = 'bookshelf-original.v1', ORIGIN = 'https://cf7-originals.local';
    var errors = {
        not_owned:'当前 Steam 账号未拥有闪客快打合集。购买后可以在这里游玩。',
        not_installed:'请先在 Steam 安装闪客快打合集，再重新载入。',
        steam_unavailable:'暂时无法确认 Steam 许可。请登录 Steam，并从 Steam 启动游戏后重试。',
        sdk_unavailable:'当前启动环境无法读取 Steam 许可。请使用完整的游戏启动环境后重试。',
        development_content_missing:'未找到本机闪客快打合集，请安装合集后重新载入。开发环境无需启动 Steam。',
        account_changed:'Steam 账号已变化，请重新载入原版。',
        context_unavailable:'当前角色正在切换或处理旅程，请返回章节后重新读取书架。',
        content_missing:'合集游戏文件不完整，请在 Steam 验证文件后重试。',
        content_changed:'合集文件版本尚不受支持，请验证文件或等待兼容更新。',
        busy:'上一份原版仍在载入，请稍后重新载入。',
        client_timeout:'暂未收到载入结果，可以重新载入或返回章节。'
    };
    function validPlayer(result, definition) {
        if (!result || result.success !== true || result.origin !== ORIGIN
                || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(result.session)) return false;
        try {
            var uri = new URL(result.playerUrl), namespace = definition.chapter === 1 ? 'local' : '[0-9a-f]{64}';
            return uri.origin === ORIGIN && !uri.username && !uri.password && !uri.search
                && new RegExp('^/player/' + namespace + '/cf' + definition.chapter + '-' + definition.language + '/player\\.html$').test(uri.pathname)
                && uri.hash === '#' + result.session;
        } catch (error) { return false; }
    }
    function Original(host, toolbar, options) {
        this.host = host; this.toolbar = toolbar; this.options = options;
        this.frame = null; this.session = ''; this.timer = null; this.epoch = 0; this.key = '';
        this.receive = this.onMessage.bind(this);
        window.addEventListener('message', this.receive);
    }
    Original.prototype.show = function(definition) {
        var key = definition.chapter + ':' + definition.language;
        if (this.key === key) return;
        this.hide(); this.key = key; this.definition = definition;
        var self = this, epoch = this.epoch;
        this.toolbar.innerHTML = '<button data-original="back">返回章节</button>'
            + '<span class="bookshelf-original-label">原版 · 无奖励</span>'
            + '<span class="bookshelf-original-keys"></span>'
            + '<button data-original="pause" disabled>暂停</button><button data-original="restart" disabled>重新载入</button>';
        this.get('back').onclick = this.options.back;
        this.toolbar.querySelector('.bookshelf-original-keys').textContent = definition.chapter === 1
            ? '方向键移动 · E 重击 · R 轻击' : definition.chapter >= 5 ? '操作见游戏内说明 · 支持右键菜单' : '操作见游戏内说明';
        this.get('pause').onclick = function() {
            if (self.frame && self.ready) self.frame.contentWindow.postMessage({channel:CHANNEL, session:self.session,
                action:self.paused ? 'play' : 'pause'}, ORIGIN);
        };
        this.get('restart').onclick = function() { var selected = self.definition; self.hide(); self.show(selected); };
        var message = document.createElement('p');
        message.className = 'bookshelf-original-status'; message.setAttribute('role', 'status');
        message.textContent = definition.chapter === 1 ? '正在翻开原版…' : '正在确认合集许可并翻开原版…';
        this.message = message; this.host.replaceChildren(message);
        this.options.prepare(definition, function(result) {
            if (self.epoch !== epoch || !self.key) {
                if (result && result.session) self.options.release(result.session);
                return;
            }
            self.get('restart').disabled = false;
            if (!validPlayer(result, definition)) {
                if (result && result.session) self.options.release(result.session);
                self.message.textContent = errors[result && result.error] || '原版未能载入，可以重新载入或返回章节。';
                return;
            }
            self.session = result.session;
            var frame = document.createElement('iframe'); frame.name = 'bookshelf-original';
            frame.title = '闪客快打 ' + definition.chapter + ' 原版';
            // The separate origin owns SharedObject storage. No popups, downloads,
            // top navigation, forms or native Host objects are granted to this frame.
            frame.setAttribute('sandbox', 'allow-scripts allow-same-origin'); frame.setAttribute('allow', 'autoplay');
            frame.src = result.playerUrl; self.frame = frame; self.host.replaceChildren(frame, message);
            self.timer = setTimeout(function() {
                self.timer = null;
                if (!self.ready) { self.message.hidden = false; self.message.textContent = '原版载入较慢，可重新载入或返回章节。'; }
            }, 20000);
        });
    };
    Original.prototype.get = function(name) { return this.toolbar.querySelector('[data-original="' + name + '"]'); };
    Original.prototype.onMessage = function(event) {
        var data = event.data;
        if (!this.frame || event.source !== this.frame.contentWindow || event.origin !== ORIGIN
                || !data || data.channel !== CHANNEL || data.session !== this.session) return;
        if (data.state === 'playing' || data.state === 'paused') {
            clearTimeout(this.timer); this.timer = null; this.ready = true; this.paused = data.state === 'paused';
            this.get('pause').disabled = false; this.get('pause').textContent = this.paused ? '继续' : '暂停';
            this.message.hidden = !this.paused; this.message.textContent = '原版已暂停';
            if (!this.paused) this.frame.focus();
        } else if (data.state === 'error') {
            clearTimeout(this.timer); this.timer = null; this.ready = false;
            this.get('pause').disabled = true; this.message.hidden = false;
            this.message.textContent = '原版未能载入，可以重新载入或返回章节。';
        }
    };
    Original.prototype.hide = function() {
        this.epoch++; clearTimeout(this.timer); this.timer = null;
        var session = this.session; this.session = ''; this.ready = false; this.paused = false; this.key = '';
        if (this.frame) this.frame.remove(); this.frame = null;
        this.host.textContent = ''; this.toolbar.textContent = '';
        if (session) this.options.release(session);
    };
    Original.prototype.destroy = function() { this.hide(); window.removeEventListener('message', this.receive); };
    root.BookshelfOriginal = Original;
})(window);
