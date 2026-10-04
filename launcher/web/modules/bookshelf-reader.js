/** Reading presentation and local reading preferences; no player/save authority. */
(function(root) {
    'use strict';
    var R = root.BookshelfRuntime, KEY = 'cf7.bookshelf.reading.v1';
    function Reader(host, options) {
        this.host = host; this.options = options; this.toolbar = options.toolbar; this.media = new root.BookshelfMedia();
        this.book = null; this.index = null; this.page = 1; this.generation = 0; this.pending = null;
        this.positions = {}; this.scrollFrame = null; this.restoring = false;
        try { var stored = JSON.parse(localStorage.getItem(KEY) || '{}');
            if (stored.v === 1 && stored.positions && typeof stored.positions === 'object') this.positions = stored.positions;
        } catch (error) { /* Unavailable preferences must never block reading. */ }
        this.toolbar.innerHTML = '<button data-reader="library" aria-label="藏书与角色" aria-expanded="false">藏书</button>'
            + '<select class="bookshelf-chapter-select" data-reader="chapter" aria-label="章节目录"></select>'
            + '<div class="bookshelf-paging"><button data-reader="prev" id="bookshelf-prev" aria-label="上一页" title="上一页">‹</button>'
            + '<form data-reader="jump"><input data-reader="page" aria-label="阅读位置" type="number" min="1" step="1">'
            + '<span data-reader="total" id="bookshelf-page-number"></span><button type="submit">跳转</button></form>'
            + '<button data-reader="next" id="bookshelf-next" aria-label="下一页" title="下一页">›</button></div>'
            + '<details class="bookshelf-reading-settings" data-reader="settings"><summary>设置</summary><div>'
            + '<label data-reader="zoom-label">画面 <select data-reader="zoom" aria-label="漫画缩放">'
            + '<option value="page">整页</option><option value="width">适合宽度</option><option value="1">原始大小</option>'
            + '<option value="1.5">150%</option><option value="2">200%</option><option value="3">300%</option></select></label>'
            + '<label data-reader="font-label" hidden>字号 <select data-reader="font" aria-label="小说字号">'
            + '<option>18</option><option>20</option><option>22</option><option>24</option><option>28</option><option>32</option></select></label>'
            + '<label>配色 <select data-reader="theme" aria-label="阅读配色"><option value="paper">暖纸</option><option value="night">夜读</option></select></label>'
            + '<p>左右方向键翻页；双击漫画切换整页与适合宽度。</p></div></details>'
            + '<button data-reader="focus">收起工具栏</button>';
        host.innerHTML = '<div class="bookshelf-reading-viewport" data-reader="viewport" tabindex="0" aria-label="阅读正文">'
            + '<div class="bookshelf-reading-content" data-reader="content"></div></div>'
            + '<button class="bookshelf-reader-reveal" data-reader="reveal" hidden>展开工具栏</button>';
        var self = this;
        this.viewport = this.get('viewport'); this.content = this.get('content');
        this.viewport.ondblclick = function(e) {
            if (!self.book || self.book.format === 'novel' || !e.target.closest('.bookshelf-page-media')) return;
            self.get('zoom').value = self.get('zoom').value === 'page' ? 'width' : 'page';
            self.applySettings(); self.restore({}); self.save();
        };
        this.get('library').onclick = options.library;
        this.get('focus').onclick = function() { self.setFocus(true); };
        this.get('reveal').onclick = function() { self.setFocus(false); self.get('focus').focus(); };
        this.get('prev').onclick = function() { self.go(self.page - 1); };
        this.get('next').onclick = function() { self.go(self.page + 1); };
        this.get('jump').onsubmit = function(e) { e.preventDefault(); self.go(Number(self.get('page').value)); };
        this.get('chapter').onchange = function() { self.go(Number(this.value)); };
        ['zoom','font','theme'].forEach(function(key) { self.get(key).onchange = function() {
            var position = self.capture(); self.applySettings(); self.restore(position); self.save();
        }; });
        this.viewport.onscroll = function() {
            if (self.restoring || self.scrollFrame != null) return;
            self.scrollFrame = requestAnimationFrame(function() { self.scrollFrame = null; self.save(); });
        };
        this.keydown = function(e) {
            if (!self.book || /INPUT|SELECT|TEXTAREA/.test(e.target.tagName) || e.altKey || e.ctrlKey || e.metaKey) return;
            if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
                e.preventDefault(); e.stopPropagation(); self.go(self.page + (e.key === 'ArrowRight' ? 1 : -1));
            }
        };
        host.addEventListener('keydown', this.keydown);
        this.toolbar.addEventListener('keydown', this.keydown);
        this.dismissSettings = function(e) {
            if (!self.get('settings').contains(e.target)) self.get('settings').open = false;
        };
        document.addEventListener('pointerdown', this.dismissSettings);
        this.resize = new ResizeObserver(function() { if (self.book) self.applySettings(); });
        this.resize.observe(this.viewport);
        var drag = null;
        this.viewport.onpointerdown = function(e) {
            if (e.button !== 0 || !self.book || self.book.format === 'novel' || !e.target.closest('.bookshelf-page-media')) return;
            self.viewport.focus({preventScroll:true});
            var ratio = self.viewport.getBoundingClientRect().width / self.viewport.clientWidth;
            drag = {x:e.clientX, y:e.clientY, left:self.viewport.scrollLeft, top:self.viewport.scrollTop, ratio:ratio};
            e.target.closest('.bookshelf-page-media').setPointerCapture(e.pointerId);
            self.viewport.classList.add('is-dragging'); e.preventDefault();
        };
        this.viewport.onpointermove = function(e) {
            if (!drag) return;
            self.viewport.scrollLeft = drag.left - (e.clientX - drag.x) / drag.ratio;
            self.viewport.scrollTop = drag.top - (e.clientY - drag.y) / drag.ratio;
        };
        this.viewport.onpointerup = this.viewport.onpointercancel = this.viewport.onlostpointercapture = function() {
            drag = null; self.viewport.classList.remove('is-dragging');
        };
    }
    Reader.prototype.get = function(name) {
        return this.toolbar.querySelector('[data-reader="' + name + '"]') || this.host.querySelector('[data-reader="' + name + '"]');
    };
    Reader.prototype.setFocus = function(focused) {
        this.get('settings').open = false; this.get('reveal').hidden = !focused;
        this.options.focus(focused);
        if (focused) this.viewport.focus({preventScroll:true});
    };
    Reader.prototype.capture = function() {
        var result = {scroll:this.viewport.scrollTop, left:this.viewport.scrollLeft};
        if (this.book && this.book.format === 'novel') {
            var paragraphs = this.content.querySelectorAll('[data-paragraph]');
            for (var i = 0; i < paragraphs.length; i++) {
                if (paragraphs[i].offsetTop > this.viewport.scrollTop + 24) break;
                result.paragraph = i; result.offset = this.viewport.scrollTop - paragraphs[i].offsetTop;
            }
        }
        return result;
    };
    Reader.prototype.save = function() {
        if (!this.book || !this.ready) return;
        var position = this.capture(); position.page = this.page;
        position.zoom = this.get('zoom').value; position.font = Number(this.get('font').value); position.theme = this.get('theme').value;
        this.positions[this.book.id] = position;
        // Catalog-owned keys only; stale or hand-edited preferences do not grow without bound.
        var clean = {}; R.books.forEach(function(book) { if (this.positions[book.id]) clean[book.id] = this.positions[book.id]; }, this);
        try { localStorage.setItem(KEY, JSON.stringify({v:1, positions:clean})); } catch (error) { /* best effort */ }
    };
    Reader.prototype.restore = function(position) {
        this.restoring = true;
        var paragraph = position && Number.isInteger(position.paragraph)
            && this.content.querySelector('[data-paragraph="' + position.paragraph + '"]');
        this.viewport.scrollTop = paragraph ? paragraph.offsetTop + (Number(position.offset) || 0) : Math.max(0, Number(position && position.scroll) || 0);
        this.viewport.scrollLeft = Math.max(0, Number(position && position.left) || 0);
        this.restoring = false;
    };
    Reader.prototype.applySettings = function() {
        this.host.dataset.theme = this.get('theme').value;
        this.host.dataset.zoom = this.get('zoom').value;
        this.content.style.setProperty('--reader-font-size', this.get('font').value + 'px');
        var node = this.content.querySelector('.bookshelf-page-media');
        if (!node) return;
        var width = Number(node.dataset.width), height = Number(node.dataset.height), zoom = this.get('zoom').value;
        var padding = getComputedStyle(this.content);
        var available = Math.max(1, this.viewport.clientWidth - parseFloat(padding.paddingLeft) - parseFloat(padding.paddingRight));
        var availableHeight = Math.max(1, this.viewport.clientHeight - parseFloat(padding.paddingTop) - parseFloat(padding.paddingBottom));
        var shown = zoom === 'width' ? available : zoom === 'page'
            ? Math.min(available, availableHeight * width / height) : width * Number(zoom);
        node.style.width = shown + 'px'; node.style.height = 'auto';
    };
    Reader.prototype.show = function(book) {
        if (this.book && this.book.id === book.id) return;
        this.save(); this.retire(); this.book = book; this.index = null;
        var position = this.positions[book.id] || {}, g = this.generation, self = this;
        this.page = Number.isInteger(position.page) ? Math.max(1, Math.min(book.pages, position.page)) : 1;
        this.get('zoom').value = ['page','width','1','1.5','2','3'].includes(position.zoom) ? position.zoom : 'page';
        this.get('font').value = [18,20,22,24,28,32].includes(position.font) ? position.font : 22;
        this.get('theme').value = position.theme === 'night' ? 'night' : 'paper';
        this.get('font-label').hidden = book.format !== 'novel'; this.get('zoom-label').hidden = book.format === 'novel';
        this.host.dataset.format = book.format;
        ['prev','next'].forEach(function(key, i) {
            var label = (i ? '下一' : '上一') + (book.format === 'novel' ? '章' : '页');
            self.get(key).setAttribute('aria-label', label); self.get(key).title = label;
        });
        if (book.format === 'facsimile') { this.buildContents(); this.render(position); return; }
        this.message('正在翻开' + book.title + '…');
        this.pending = new AbortController();
        fetch('assets/bookshelf/' + book.index, {signal:this.pending.signal}).then(function(response) {
            if (!response.ok) throw new Error('index_unavailable'); return response.json();
        }).then(function(index) {
            if (g !== self.generation) return;
            self.pending = null; self.index = R.validateIndex(book, index); self.buildContents(); self.render(position);
        }).catch(function(error) { if (g === self.generation && error.name !== 'AbortError') self.message('正文未能载入。', true); });
    };
    Reader.prototype.buildContents = function() {
        var list = this.get('chapter'); list.textContent = '';
        var chapters = !this.index ? [{title:'原版书页',page:1}] : this.book.format === 'novel'
            ? this.index.chapters.map(function(c, i) { return {title:c.title,page:i + 1}; }) : this.index.chapters;
        chapters.forEach(function(c) { var option = document.createElement('option'); option.value = c.page; option.textContent = c.title; list.appendChild(option); });
    };
    Reader.prototype.go = function(page) {
        if (!this.book || !Number.isInteger(page) || page < 1 || page > this.book.pages
                || (this.book.format !== 'facsimile' && !this.index)) return;
        this.save(); this.page = page; this.render({});
    };
    Reader.prototype.message = function(text, retry) {
        this.ready = false; this.content.textContent = '';
        var p = document.createElement('p'); p.className = 'bookshelf-reader-message'; p.setAttribute('role','status'); p.textContent = text;
        this.content.appendChild(p);
        if (retry) {
            var button = document.createElement('button'), self = this; button.textContent = '重新载入';
            button.onclick = function() { if (self.index || self.book.format === 'facsimile') self.render({});
                else { var book = self.book; self.book = null; self.show(book); } };
            p.appendChild(button);
        }
    };
    Reader.prototype.render = function(position) {
        this.media.stop(); var self = this, book = this.book, pageNumber = this.page, g = ++this.generation;
        this.get('page').value = pageNumber; this.get('page').max = book.pages;
        this.get('total').textContent = '/ ' + book.pages;
        this.get('prev').disabled = pageNumber <= 1;
        this.get('next').disabled = pageNumber >= book.pages;
        Array.from(this.get('chapter').options).forEach(function(option) { if (Number(option.value) <= pageNumber) self.get('chapter').value = option.value; });
        this.message('正在载入…'); this.applySettings();
        if (book.format === 'novel') {
            var chapter = this.index.chapters[pageNumber - 1], article = document.createElement('article');
            article.className = 'bookshelf-prose';
            var title = document.createElement('h2'); title.textContent = chapter.title; article.appendChild(title);
            var credit = document.createElement('p'); credit.className = 'bookshelf-author'; credit.textContent = this.index.author; article.appendChild(credit);
            chapter.paragraphs.forEach(function(text, i) { var p = document.createElement('p'); p.textContent = text; p.dataset.paragraph = i; article.appendChild(p); });
            var source = document.createElement('p'); source.className = 'bookshelf-source';
            source.textContent = '原文收录：AndyLaw 的闪客快打官网 · 保留作者原文'; article.appendChild(source);
            this.content.replaceChildren(article); this.ready = true; this.restore(position); this.save(); return;
        }
        var page = book.format === 'comic' ? this.index.pages[pageNumber - 1] : null;
        var url = page ? 'assets/bookshelf/' + book.id + '/' + page.file : R.pageUrl(book.id, pageNumber);
        this.media.load(book.id + ':' + pageNumber, url, page).then(function(node) {
            if (g !== self.generation || self.book !== book) return;
            node.id = 'bookshelf-page'; node.className = 'bookshelf-page-media';
            node.title = '双击切换整页与适合宽度；左右方向键翻页';
            node.setAttribute('role','img'); node.setAttribute('aria-label',book.title + '，第 ' + pageNumber + ' 页');
            if (node.tagName === 'IMG') node.alt = book.title + '，第 ' + pageNumber + ' 页';
            node.dataset.width = page ? page.width : 281; node.dataset.height = page ? page.height : 421;
            self.content.replaceChildren(node); self.applySettings(); self.ready = true; self.restore(position); self.save();
        }).catch(function(error) { if (g === self.generation && error.message !== 'cancelled') self.message('这一页未能显示，请重试。', true); });
    };
    Reader.prototype.retire = function() {
        this.generation++; this.ready = false; this.media.stop();
        if (this.pending) this.pending.abort(); this.pending = null;
        if (this.scrollFrame != null) cancelAnimationFrame(this.scrollFrame); this.scrollFrame = null;
    };
    Reader.prototype.hide = function() { this.save(); this.retire(); this.book = null; this.setFocus(false); };
    Reader.prototype.destroy = function() {
        this.hide(); this.resize.disconnect(); this.media.destroy(); this.host.removeEventListener('keydown', this.keydown);
        this.toolbar.removeEventListener('keydown', this.keydown); this.toolbar.textContent = '';
        document.removeEventListener('pointerdown', this.dismissSettings);
        this.host.textContent = ''; this.host = null;
    };
    root.BookshelfReader = Reader;
})(window);
