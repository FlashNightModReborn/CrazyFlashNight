/* 版本化作者指南：只读帮助、上下文定位，复用共享二级页和焦点栈。 */
var MapWorkbenchHelp = (function() {
    'use strict';
    var guidePath = 'help/map-workbench.md';
    var topics = {page:'创建地图和地点', location:'创建地图和地点', hotspot:'创建地图和地点',
        scene:'素材与清晰度', avatar:'人物身份与驻点', npc:'人物身份与驻点', placement:'人物身份与驻点',
        rule:'剧情条件与双方案', task:'任务端点', filter:'认识这些对象'};
    function create(options) {
        var U = MapAuthoringControls;
        var root = U.node('section', 'mw-guide'), header = U.node('header', 'mw-guide-header');
        var back = U.button('← 返回编辑', function() {}), title = U.node('h2', '', '地图工作台操作指南');
        var close = U.button('关闭工作台', function() {});
        header.append(back, title, close);
        var context = U.node('p', 'mw-guide-context');
        var layout = U.node('div', 'mw-guide-layout'), sidebar = U.node('div', 'mw-guide-sidebar');
        var label = U.node('label', 'mw-field', '搜索帮助主题'), search = U.node('input');
        search.type = 'search'; search.placeholder = '例如：看不见、NPC、应用'; search.setAttribute('aria-label', '搜索帮助主题');
        label.appendChild(search);
        var count = U.node('p', 'mw-guide-results'); count.setAttribute('role', 'status');
        var nav = U.node('nav', 'mw-guide-nav'); nav.setAttribute('aria-label', '地图工作台帮助主题');
        var content = U.node('div', 'mw-guide-content'); content.tabIndex = 0;
        content.setAttribute('role', 'region'); content.setAttribute('aria-label', '操作步骤与说明');
        var read = U.button('阅读当前主题 →', function() { content.focus(); });
        sidebar.append(label, count, nav, read); layout.append(sidebar, content);
        root.append(header, context, layout, U.node('p', 'mw-guide-footer', '帮助只读。返回后保留对象选择、画布、模拟方案和未应用草稿。'));
        var sections = [], selected = '', desired = '', loaded = false, loading = false, epoch = 0, controller;
        var page = new WorkbenchComponents.SecondaryPage({root:root, role:'dialog', ariaLabel:'地图工作台操作指南', onClose:function() {
            epoch++; loading = false;
            if (controller) { controller.abort(); controller = null; }
        }});
        page.bindBack(back); page.bindClose(close, options.onClose); page.mount(options.host);
        function show(entry) {
            if (!entry) return;
            selected = entry.title;
            sections.forEach(function(item) {
                item.body.hidden = item !== entry;
                item.button.setAttribute('aria-current', item === entry ? 'page' : 'false');
            });
            content.scrollTop = 0;
        }
        function filter() {
            var terms = search.value.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
            var matches = sections.filter(function(entry) { return terms.every(function(term) { return entry.text.includes(term); }); });
            sections.forEach(function(entry) { entry.button.hidden = !matches.includes(entry); });
            count.textContent = matches.length ? (terms.length ? '找到 ' + matches.length + ' 个相关主题' : '共 ' + matches.length + ' 个主题；建议从入门练习开始') : '没有匹配主题。试试“条件”“重启”或“人物”。';
            if (matches.length) show(matches.find(function(entry) { return entry.title === selected; }) || matches[0]);
            else sections.forEach(function(entry) { entry.body.hidden = true; });
        }
        search.addEventListener('input', filter);
        function render(source) {
            if (source.length > 128 * 1024) throw new Error('帮助文档过大');
            var renderer = new marked.Renderer(); renderer.html = function() { return ''; };
            var body = U.node('div'); body.innerHTML = marked.parse(source, {renderer:renderer});
            // 此页只读固定指南，不把 Markdown 链接变成外部导航或业务按钮。
            body.querySelectorAll('a').forEach(function(link) { link.replaceWith(document.createTextNode(link.textContent)); });
            var next = [], entry;
            Array.from(body.children).forEach(function(node) {
                if (node.tagName === 'H2') {
                    entry = {title:node.textContent, body:U.node('article')}; entry.body.hidden = true; next.push(entry);
                }
                if (entry) entry.body.appendChild(node);
            });
            if (!next.length || !next.some(function(item) { return item.title === '入门练习'; })) throw new Error('帮助主题不完整');
            sections = next; nav.replaceChildren(); content.replaceChildren();
            sections.forEach(function(item) {
                item.text = item.body.textContent.toLocaleLowerCase();
                item.button = U.button(item.title, function() { show(item); });
                item.button.dataset.guideTopic = item.title;
                nav.appendChild(item.button); content.appendChild(item.body);
            });
            selected = desired || selected || '入门练习'; filter(); loaded = true;
        }
        function load() {
            if (loaded || loading) return;
            loading = true; var ticket = ++epoch; controller = new AbortController();
            content.replaceChildren(U.node('p', '', '正在读取操作指南…'));
            fetch(guidePath, {signal:controller.signal}).then(function(response) {
                if (!response.ok) throw new Error('HTTP ' + response.status); return response.text();
            }).then(function(source) {
                if (ticket === epoch && page.isActive()) render(source);
            }).catch(function(error) {
                if (ticket !== epoch || error.name === 'AbortError') return;
                content.replaceChildren(U.node('p', '', '帮助暂时无法读取。可重试，或阅读仓库中的 launcher/web/help/map-workbench.md。'),
                    U.button('重新读取帮助', load));
            }).finally(function() { if (ticket === epoch) { loading = false; controller = null; } });
        }
        return {
            open:function(opener, topic) {
                var info = options.context();
                context.textContent = '当前编辑：' + info.label + ' · 未应用修改 ' + info.changes + ' 步。';
                desired = topic || ''; if (desired) { search.value = ''; selected = desired; }
                page.open({opener:opener, initialFocus:back});
                if (loaded) filter(); else load();
            },
            openFor:function(opener, kind) { this.open(opener, topics[kind] || '入门练习'); },
            close:function(reason) { return page.close(reason || 'return'); },
            isActive:function() { return page.isActive(); }
        };
    }
    return {create:create, topics:topics};
})();
