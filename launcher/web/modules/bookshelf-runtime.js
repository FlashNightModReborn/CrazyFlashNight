(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports ? require('./panel-runtime.js') : root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.BookshelfRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';
    var books = [
        {id:'dust', title:'尘都诡谈', subtitle:'原版藏书 · 15 页', format:'facsimile', pages:15, spine:'shelf/textures/spine-dust.png'},
        {id:'babylon', title:'光明巴比伦', subtitle:'原版藏书 · 15 页', format:'facsimile', pages:15, spine:'shelf/textures/spine-babylon.png'},
        {id:'crazy-flasher', title:'闪客快打', subtitle:'系列藏书 · 6 个章节', format:'playable', pages:0, boxArt:'shelf/textures/box-crazy-flasher.png',
            chapters:[1,2,3,4,5,6].map(function(n) { return {id:'cf' + n, title:n === 1 ? '修理大学' : '闪客快打 ' + n,
                cover:'shelf/textures/disc-cf' + n + '.png',
                original:{chapter:n, languages:n === 1 ? ['cn'] : ['cn','en']},
                remake:{id:n === 1 ? 'repair-campus' : null, available:n === 1}}; })}
    ];
    function pageUrl(id, page) {
        var book = books.find(function(b) { return b.id === id; });
        return book && book.format === 'facsimile' && Number.isInteger(page) && page >= 1 && page <= book.pages
            ? 'assets/bookshelf/' + id + '/' + String(page).padStart(2, '0') + '.svg' : null;
    }
    function safeAsset(path) {
        return typeof path === 'string' && /^[A-Za-z0-9_./-]+$/.test(path)
            && path.split('/').every(function(p) { return p && p !== '.' && p !== '..'; });
    }
    function adoptCatalog(data) {
        if (!data || data.schema !== 'bookshelf-catalog.v1' || !Array.isArray(data.books)
                || !data.books.length || data.books.length > 32) throw new Error('invalid_catalog');
        var ids = new Set();
        data.books.forEach(function(b) {
            if (!b || !/^[a-z0-9-]+$/.test(b.id) || ids.has(b.id) || typeof b.title !== 'string'
                    || typeof b.subtitle !== 'string' || !Number.isInteger(b.pages) || b.pages < 0 || b.pages > 10000
                    || !['facsimile','comic','novel','playable'].includes(b.format)
                    || (b.format === 'playable') !== (b.pages === 0)
                    || (b.format === 'playable' ? !safeAsset(b.boxArt) : !safeAsset(b.spine))
                    || (['comic','novel'].includes(b.format) && !safeAsset(b.index))) throw new Error('invalid_book');
            ids.add(b.id);
            if (b.format === 'playable' && (b.id !== 'crazy-flasher' || !Array.isArray(b.chapters) || b.chapters.length !== 6
                || !b.chapters.every(function(c, i) { return c && c.id === 'cf' + (i + 1) && typeof c.title === 'string'
                    && safeAsset(c.cover)
                    && c.original && c.original.chapter === i + 1
                    && JSON.stringify(c.original.languages) === JSON.stringify(i === 0 ? ['cn'] : ['cn','en'])
                    && c.remake && c.remake.available === (i === 0) && c.remake.id === (i === 0 ? 'repair-campus' : null);
                }))) throw new Error('invalid_series');
        });
        books.splice.apply(books, [0, books.length].concat(data.books));
        return books;
    }
    function validateIndex(book, index) {
        if (book.format === 'novel') {
            if (!index || index.schema !== 'bookshelf-novel.v1' || !Array.isArray(index.chapters)
                    || index.chapters.length !== book.pages || !index.chapters.every(function(c) {
                        return c && typeof c.title === 'string' && Array.isArray(c.paragraphs)
                            && c.paragraphs.length > 0 && c.paragraphs.every(function(p) { return typeof p === 'string'; });
                    })) throw new Error('invalid_novel');
        } else {
            if (!index || index.schema !== 'bookshelf-comic.v1' || !Array.isArray(index.pages)
                    || index.pages.length !== book.pages || !Array.isArray(index.chapters)) throw new Error('invalid_comic');
            index.pages.forEach(function(p, i) {
                if (!p || p.page !== i + 1 || !safeAsset(p.file) || !Number.isInteger(p.width)
                        || !Number.isInteger(p.height) || p.width < 1 || p.height < 1 || p.width > 8192 || p.height > 8192
                        || !['image','video-frame'].includes(p.storage)) throw new Error('invalid_page');
                if (p.storage === 'video-frame' && (!Number.isInteger(p.frame) || p.frame < 0 || p.frame > 63
                        || p.time_seconds !== p.frame || !Array.isArray(p.crop) || p.crop.length !== 4
                        || p.crop.some(function(n) { return !Number.isInteger(n) || n < 0; })
                        || p.crop[2] !== p.width || p.crop[3] !== p.height)) throw new Error('invalid_frame');
            });
            if (!index.chapters.every(function(c) { return c && typeof c.title === 'string'
                && Number.isInteger(c.page) && c.page >= 1 && c.page <= book.pages; })) throw new Error('invalid_chapter');
        }
        return index;
    }
    function RequestMux(options) {
        var instance = options.panelInstanceId, domain = options.domain || 'bookshelf';
        if (!['bookshelf','bookshelf-original'].includes(domain)) throw new Error('unsupported_domain');
        this.domain = domain;
        this.mux = new PanelRuntime.PanelRequestMux({
            send:options.send, timeoutMs:options.timeoutMs || 18000, callPrefix:'bookshelf',
            router:options.router || PanelRuntime.sharedResponseRouter,
            createMessage:function(c) { return {type:'panel', panel:'bookshelf', domain:domain, cmd:c.entry.cmd,
                callId:c.entry.callId, panelInstanceId:instance, payload:c.payload}; },
            validateResponse:function(d, e) { return d && d.type === 'panel_resp' && d.panel === 'bookshelf'
                && d.domain === domain && d.cmd === e.cmd && d.callId === e.callId && d.panelInstanceId === instance; },
            createSynthetic:function(c) { return {success:false, error:c.error, clientSynthetic:true,
                requiresReconcile:c.entry.write && c.error === 'client_timeout'}; }
        });
        this.mux.openSession({});
    }
    RequestMux.prototype.request = function(cmd, payload, done) {
        var original = this.domain === 'bookshelf-original';
        if (!(original ? /^(prepare|release)$/ : /^(snapshot|commit|query)$/).test(cmd)) return null;
        return this.mux.request(cmd, payload, {kind:cmd,
            singleFlight:!original, write:!original && cmd === 'commit', sendError:'not_sent'}, done);
    };
    RequestMux.prototype.destroy = function() { this.mux.destroy(); };
    return {books:books, pageUrl:pageUrl, safeAsset:safeAsset, adoptCatalog:adoptCatalog, validateIndex:validateIndex, RequestMux:RequestMux};
});
