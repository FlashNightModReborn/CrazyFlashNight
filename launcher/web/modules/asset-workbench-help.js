/* 工作台与 Agent 共读版本化 Markdown；本页只提供阅读和主动复制。 */
var AssetWorkbenchHelp = (function() {
    'use strict';
    var GUIDE = 'help/asset-workbench.md';
    function element(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = text;
        return node;
    }
    function create(options) {
        var root = element('section', 'aw-help-page'), loaded = false, loading = false, epoch = 0, controller;
        var header = element('header', 'aw-help-header'), back = element('button', 'aw-button', '← 返回工作台');
        var title = element('h2', '', '素材工作台帮助'), close = element('button', 'aw-button', '关闭工作台');
        header.append(back, title, close);
        var layout = element('div', 'aw-help-layout'), nav = element('nav', 'aw-help-nav'), content = element('div', 'aw-help-doc');
        nav.setAttribute('aria-label', '帮助主题');
        content.tabIndex = 0; content.setAttribute('role', 'region'); content.setAttribute('aria-label', '帮助正文');
        layout.append(nav, content);
        var footer = element('footer', 'aw-help-footer'), copy = element('button', 'aw-button', '复制当前任务信息');
        var message = element('span', 'aw-help-message'); message.setAttribute('role', 'status');
        var fallback = element('textarea', 'aw-help-copy-fallback'); fallback.readOnly = true; fallback.hidden = true;
        fallback.setAttribute('aria-label', '待复制的内容');
        footer.append(copy, message, fallback); root.append(header, layout, footer);
        var page = new WorkbenchComponents.SecondaryPage({root:root, role:'dialog', ariaLabel:'素材工作台帮助', onClose:function(reason) {
            epoch++; loading = false;
            if (controller) { controller.abort(); controller = null; }
            message.textContent = '';
            fallback.hidden = true;
            if (options.onReturn) options.onReturn(reason);
        }});
        page.bindBack(back); page.bindClose(close, options.onClose); page.mount(options.host);
        function copyText(text) {
            var ticket = epoch; fallback.hidden = true;
            function selectText() {
                fallback.value = text; fallback.hidden = false; fallback.focus(); fallback.select();
                message.textContent = '自动复制不可用，内容已选中，请按 Ctrl+C。';
            }
            if (!navigator.clipboard || !navigator.clipboard.writeText) {
                selectText(); return;
            }
            navigator.clipboard.writeText(text).then(function() {
                if (page.isActive() && ticket === epoch) message.textContent = '已复制，可粘贴给 Agent 或维护者。';
            }).catch(function() {
                if (page.isActive() && ticket === epoch) selectText();
            });
        }
        copy.addEventListener('click', function() { copyText(options.taskInfo()); });
        function render(source) {
            // 仅解析固定路径的仓库帮助文档，与现有游戏 HelpPanel 使用相同 Markdown 库。
            var documentBody = element('div'); documentBody.innerHTML = marked.parse(source);
            var sections = [], section;
            Array.from(documentBody.children).forEach(function(node) {
                if (node.tagName === 'H2') {
                    section = element('article'); section.hidden = true;
                    sections.push({title:node.textContent, body:section});
                }
                if (section) section.appendChild(node);
            });
            if (!sections.length) throw new Error('帮助文档缺少主题');
            nav.replaceChildren(); content.replaceChildren();
            sections.forEach(function(entry, index) {
                var button = element('button', 'aw-button', entry.title); button.type = 'button';
                entry.button = button; nav.appendChild(button); content.appendChild(entry.body);
                button.addEventListener('click', function() { show(index); });
                entry.body.querySelectorAll('pre').forEach(function(pre) {
                    var copyCommand = element('button', 'aw-button aw-help-copy', '复制命令'); copyCommand.type = 'button';
                    copyCommand.addEventListener('click', function() { copyText(pre.textContent); });
                    pre.before(copyCommand);
                });
            });
            function show(index) {
                sections.forEach(function(entry, n) { entry.body.hidden = n !== index; entry.button.setAttribute('aria-pressed', String(n === index)); });
                content.scrollTop = 0; message.textContent = '';
            }
            show(0); loaded = true;
        }
        function load() {
            if (loaded || loading) return;
            loading = true; var ticket = ++epoch;
            controller = new AbortController();
            content.replaceChildren(element('p', '', '正在读取帮助…'));
            fetch(GUIDE, {signal:controller.signal}).then(function(response) {
                if (!response.ok) throw new Error('HTTP ' + response.status);
                return response.text();
            }).then(function(source) {
                if (ticket === epoch && page.isActive()) render(source);
            }).catch(function(error) {
                if (ticket !== epoch || error.name === 'AbortError') return;
                var retry = element('button', 'aw-button', '重新读取帮助'); retry.type = 'button';
                retry.addEventListener('click', load);
                content.replaceChildren(element('p', '', '帮助暂时无法读取，可重试；仓库文档位于 launcher/web/help/asset-workbench.md。'), retry);
            }).finally(function() { if (ticket === epoch) { loading = false; controller = null; } });
        }
        return {
            open:function(opener) { page.open({opener:opener, initialFocus:back}); load(); },
            close:function(reason) { page.close(reason || 'return'); },
            isActive:function() { return page.isActive(); }
        };
    }
    return {create:create};
})();
