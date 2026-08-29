// Bootstrap 首页“其他”：项目说明、Markdown 作者名单 / 版本记录与音频设置。
// 作者与版本正文是受版本控制的 content/*.md；本模块只负责受限渲染和页签生命周期。
(function () {
  'use strict';

  var _container = null;
  var _requests = [];
  var _cache = {};
  var _activeTab = 'document';
  var MARKDOWN_FILES = {
    credits: 'content/about-authors.md',
    versions: 'content/version-history.md'
  };

  function escapeHtml(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // marked 支持的语法面很宽；这里收窄为介绍页真正需要的排版元素。
  // 即便未来 Markdown 被误写入原始 HTML，也不会获得脚本、事件属性或任意协议链接。
  function sanitizeMarkdownHtml(html) {
    var template = document.createElement('template');
    template.innerHTML = html;
    var allowed = {
      H1:true, H2:true, H3:true, H4:true, H5:true, H6:true, P:true, UL:true, OL:true, LI:true,
      STRONG:true, EM:true, CODE:true, PRE:true, BLOCKQUOTE:true, HR:true, BR:true, A:true,
      SPAN:true
    };
    var dangerous = {SCRIPT:true, STYLE:true, IFRAME:true, OBJECT:true, EMBED:true, SVG:true, MATH:true};
    Array.prototype.slice.call(template.content.querySelectorAll('*')).forEach(function (node) {
      var tag = node.tagName;
      if (/^H[1-6]$/.test(tag)) {
        var level = Math.min(6, Number(tag.charAt(1)) + 2);
        var heading = document.createElement('h' + level);
        while (node.firstChild) heading.appendChild(node.firstChild);
        node.parentNode.replaceChild(heading, node);
        node = heading;
        tag = node.tagName;
      }
      if (!allowed[tag]) {
        if (dangerous[tag]) node.remove();
        else node.replaceWith.apply(node, Array.prototype.slice.call(node.childNodes));
        return;
      }
      var rawHref = tag === 'A' ? (node.getAttribute('href') || '') : '';
      var rawCredit = tag === 'SPAN' ? (node.getAttribute('data-credit') || '') : '';
      Array.prototype.slice.call(node.attributes).forEach(function (attr) {
        node.removeAttribute(attr.name);
      });
      if (tag === 'A') {
        if (!/^https:\/\//i.test(rawHref)) {
          node.replaceWith.apply(node, Array.prototype.slice.call(node.childNodes));
          return;
        }
        node.setAttribute('href', rawHref);
        node.setAttribute('target', '_blank');
        node.setAttribute('rel', 'noopener noreferrer');
      }
      if (tag === 'SPAN') {
        // Markdown 只允许三种有历史 Flash 依据的署名色标；FFDec 色号来自旧启动提示。
        if (!/^(?:andylaw|andylaw-games|ffdec)$/.test(rawCredit)) {
          node.replaceWith.apply(node, Array.prototype.slice.call(node.childNodes));
          return;
        }
        node.setAttribute('data-credit', rawCredit);
      }
    });
    return template.innerHTML;
  }

  function renderMarkdown(markdown) {
    if (typeof markdown !== 'string' || markdown.length > 131072) {
      throw new Error('markdown_invalid');
    }
    if (typeof marked === 'undefined' || !marked.parse) {
      return '<pre>' + escapeHtml(markdown) + '</pre>';
    }
    return sanitizeMarkdownHtml(marked.parse(markdown));
  }

  function setMarkdownState(tab, state, copy) {
    if (!_container || _activeTab !== tab) return;
    var host = document.getElementById('about-' + tab + '-content');
    if (!host) return;
    host.setAttribute('data-state', state);
    if (state === 'ready') {
      host.removeAttribute('role');
      host.removeAttribute('aria-live');
      host.innerHTML = copy;
      if (tab === 'versions') enhanceVersionBrowser(host);
    } else {
      host.setAttribute('role', 'status');
      host.setAttribute('aria-live', 'polite');
      host.textContent = copy;
    }
  }

  function versionHeading(node) {
    if (!node || !/^H[1-6]$/.test(node.tagName)) return null;
    var text = node.textContent.replace(/\s+/g, ' ').trim();
    var match = text.match(/^v?(\d+(?:\.\d+)+)(?:\s*[·|｜—-]\s*(.+))?$/i);
    return match ? {version:match[1], label:text} : null;
  }

  function enhanceVersionBrowser(host) {
    var nodes = Array.prototype.slice.call(host.children);
    var starts = [];
    nodes.forEach(function (node, index) {
      var heading = versionHeading(node);
      if (heading) starts.push({index:index, heading:heading});
    });
    if (!starts.length) {
      host.classList.add('about-version-unstructured');
      return;
    }

    var intro = document.createElement('div');
    intro.className = 'about-version-intro';
    nodes.slice(0, starts[0].index).forEach(function (node) { intro.appendChild(node); });

    var browser = document.createElement('div');
    browser.className = 'about-version-browser';
    var navigator = document.createElement('aside');
    navigator.className = 'about-version-nav';
    navigator.setAttribute('aria-label', '版本节点');
    var navLabel = document.createElement('strong');
    navLabel.className = 'about-version-nav-label';
    navLabel.textContent = '版本节点';
    var options = document.createElement('div');
    options.className = 'about-version-options';
    var controls = document.createElement('div');
    controls.className = 'about-version-controls';
    var previous = document.createElement('button');
    previous.type = 'button';
    previous.className = 'term-btn about-version-prev';
    previous.textContent = '较新';
    var next = document.createElement('button');
    next.type = 'button';
    next.className = 'term-btn about-version-next';
    next.textContent = '较早';
    controls.appendChild(previous);
    controls.appendChild(next);
    navigator.appendChild(navLabel);
    navigator.appendChild(options);
    navigator.appendChild(controls);

    var stage = document.createElement('section');
    stage.className = 'about-version-stage';
    var stageHeader = document.createElement('header');
    stageHeader.className = 'about-version-stage-header';
    var stageKicker = document.createElement('span');
    stageKicker.textContent = 'VERSION';
    var stageTitle = document.createElement('strong');
    stageHeader.appendChild(stageKicker);
    stageHeader.appendChild(stageTitle);
    var articles = document.createElement('div');
    articles.className = 'about-version-articles';
    stage.appendChild(stageHeader);
    stage.appendChild(articles);

    var entries = starts.map(function (start, entryIndex) {
      var end = entryIndex + 1 < starts.length ? starts[entryIndex + 1].index : nodes.length;
      var article = document.createElement('article');
      article.className = 'about-version-entry';
      article.setAttribute('aria-label', start.heading.label);
      nodes.slice(start.index, end).forEach(function (node) { article.appendChild(node); });
      articles.appendChild(article);

      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'about-version-option';
      button.setAttribute('data-version-index', String(entryIndex));
      button.setAttribute('aria-pressed', 'false');
      button.textContent = start.heading.version;
      options.appendChild(button);
      return {button:button, article:article, heading:start.heading};
    });

    function selectVersion(index, focus) {
      index = Math.max(0, Math.min(entries.length - 1, index));
      entries.forEach(function (entry, entryIndex) {
        var selected = entryIndex === index;
        entry.button.setAttribute('aria-pressed', selected ? 'true' : 'false');
        entry.article.hidden = !selected;
      });
      stageTitle.textContent = entries[index].heading.label;
      articles.scrollTop = 0;
      previous.disabled = index <= 0;
      next.disabled = index >= entries.length - 1;
      if (focus) entries[index].button.focus();
      entries[index].button.scrollIntoView({block:'nearest'});
    }

    entries.forEach(function (entry, index) {
      entry.button.onclick = function () { selectVersion(index, false); };
      entry.button.onkeydown = function (event) {
        var target = index;
        if (event.key === 'ArrowDown' || event.key === 'ArrowRight') target = Math.min(entries.length - 1, index + 1);
        else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') target = Math.max(0, index - 1);
        else if (event.key === 'Home') target = 0;
        else if (event.key === 'End') target = entries.length - 1;
        else return;
        event.preventDefault();
        selectVersion(target, true);
      };
    });
    previous.onclick = function () {
      var current = entries.findIndex(function (entry) { return entry.button.getAttribute('aria-pressed') === 'true'; });
      selectVersion(current - 1, true);
    };
    next.onclick = function () {
      var current = entries.findIndex(function (entry) { return entry.button.getAttribute('aria-pressed') === 'true'; });
      selectVersion(current + 1, true);
    };

    host.innerHTML = '';
    if (intro.textContent.trim()) host.appendChild(intro);
    browser.appendChild(navigator);
    browser.appendChild(stage);
    host.appendChild(browser);
    var configured = String((window.APP_META && window.APP_META.version) || '').replace(/^v/i, '');
    var initial = entries.findIndex(function (entry) { return entry.heading.version === configured; });
    selectVersion(initial >= 0 ? initial : 0, false);
  }

  function loadMarkdown(tab) {
    if (_cache[tab]) {
      setMarkdownState(tab, 'ready', _cache[tab]);
      return;
    }
    var url = MARKDOWN_FILES[tab];
    if (!url) return;
    setMarkdownState(tab, 'loading', '正在读取本地文档...');
    var xhr = new XMLHttpRequest();
    _requests.push(xhr);
    xhr.open('GET', url, true);
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      var index = _requests.indexOf(xhr);
      if (index >= 0) _requests.splice(index, 1);
      if (!_container) return;
      if (xhr.status !== 200 && xhr.status !== 0) {
        setMarkdownState(tab, 'error', '本地文档读取失败。');
        return;
      }
      try {
        _cache[tab] = renderMarkdown(xhr.responseText);
        setMarkdownState(tab, 'ready', _cache[tab]);
      } catch (e) {
        setMarkdownState(tab, 'error', '本地文档格式无效。');
      }
    };
    xhr.send();
  }

  function switchTab(tab) {
    if (!_container || ['document', 'credits', 'versions'].indexOf(tab) < 0) return;
    _activeTab = tab;
    _container.querySelectorAll('[role="tab"]').forEach(function (button) {
      var selected = button.getAttribute('data-about-tab') === tab;
      button.classList.toggle('active', selected);
      button.setAttribute('aria-selected', selected ? 'true' : 'false');
      button.tabIndex = selected ? 0 : -1;
    });
    _container.querySelectorAll('[data-about-pane]').forEach(function (pane) {
      pane.hidden = pane.getAttribute('data-about-pane') !== tab;
    });
    var modal = _container.closest('.modal-content');
    if (modal) modal.scrollTop = 0;
    if (MARKDOWN_FILES[tab]) loadMarkdown(tab);
  }

  function bindTabs() {
    var tabs = Array.prototype.slice.call(_container.querySelectorAll('[role="tab"]'));
    tabs.forEach(function (button, index) {
      button.onclick = function () { switchTab(button.getAttribute('data-about-tab')); };
      button.onkeydown = function (event) {
        var next = index;
        if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
        else if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = tabs.length - 1;
        else return;
        event.preventDefault();
        switchTab(tabs[next].getAttribute('data-about-tab'));
        tabs[next].focus();
      };
    });
  }

  function mount(containerEl) {
    _container = containerEl;
    _container.classList.add('about-surface');
    _activeTab = 'document';
    var sfxOn = !!(window.BootstrapAudio && window.BootstrapAudio.isSfxEnabled && window.BootstrapAudio.isSfxEnabled());
    if (!window.BootstrapAudio) sfxOn = true;
    var ambOn = !!(window.BootstrapAudio && window.BootstrapAudio.isAmbientEnabled && window.BootstrapAudio.isAmbientEnabled());
    var meta = window.APP_META || {};
    _container.innerHTML =
      '<div class="modal-header term-heading-rule">' +
        '<h2>ABOUT · 关于与版本</h2>' +
        '<button class="modal-close" id="about-close" aria-label="关闭">×</button>' +
      '</div>' +
      '<div class="about-modal">' +
        '<div class="mode-tabs about-tabs" role="tablist" aria-label="关于与版本">' +
          '<button type="button" id="about-tab-document" role="tab" data-about-tab="document" aria-controls="about-pane-document" aria-selected="true" class="active">项目说明</button>' +
          '<button type="button" id="about-tab-credits" role="tab" data-about-tab="credits" aria-controls="about-pane-credits" aria-selected="false" tabindex="-1">作者与致谢</button>' +
          '<button type="button" id="about-tab-versions" role="tab" data-about-tab="versions" aria-controls="about-pane-versions" aria-selected="false" tabindex="-1">版本记录</button>' +
        '</div>' +
        '<section id="about-pane-document" role="tabpanel" aria-labelledby="about-tab-document" data-about-pane="document">' +
          '<h3>DOCUMENT</h3>' +
          '<p>1. 本游戏游戏过程中将存储数据在本地，请勿设置禁止储存数据。</p>' +
          '<p>2. 本游戏为无网单机版。无充值系统，无与网络相关的功能。如果要体验完整联机功能，请选择《闪客快打 7 佣兵帝国》网络版。</p>' +
          '<p>3. 然而网络版已经停服，你现在玩到的是玩家重置的单机版 MOD。</p>' +
          '<p>4. 请首先在 Steam 平台购买正版游戏，按照指南覆盖 MOD 文件包。本 MOD 为免费开源项目，如果您不慎支付购买，请保留交易证据并联系我们。</p>' +
          '<p>5. 加入我们的 QQ 群：<span class="qq">562130873</span><span class="b">（将满）</span>、<span class="qq">149188029</span><span class="b">（将满）</span>、<span class="qq">307710279</span> 参与讨论，关注 B 站账号 <span class="qq">黑月雾人</span> / <span class="qq">无名的低谷</span> / <span class="qq">crazyfs</span> 获取最新信息。</p>' +
          '<h3>AUDIO</h3>' +
          '<div class="audio-toggles">' +
            '<label class="audio-toggle"><input type="checkbox" id="about-sfx"' + (sfxOn ? ' checked' : '') + '> <span>UI 音效 · hover / click / confirm / error</span></label>' +
            '<label class="audio-toggle"><input type="checkbox" id="about-ambient"' + (ambOn ? ' checked' : '') + '> <span>环境 hum · θ-FLOOD 背景低频</span></label>' +
          '</div>' +
          '<p class="foot">本 MOD 版权归原游戏开发者 <span class="b">AndyLaw</span> 及社区共同所有。作者名单和版本记录已迁移为首页可读的 Markdown 文档。</p>' +
        '</section>' +
        '<section id="about-pane-credits" role="tabpanel" aria-labelledby="about-tab-credits" data-about-pane="credits" hidden>' +
          '<div id="about-credits-content" class="about-markdown"></div>' +
        '</section>' +
        '<section id="about-pane-versions" role="tabpanel" aria-labelledby="about-tab-versions" data-about-pane="versions" hidden>' +
          '<p class="about-current-version">当前启动器 <strong>v' + escapeHtml(meta.version || '—') + '</strong> · ' + escapeHtml(meta.channel || '—') + ' · ' + escapeHtml(meta.tail || '—') + '</p>' +
          '<div id="about-versions-content" class="about-markdown"></div>' +
        '</section>' +
      '</div>';

    document.getElementById('about-close').onclick = function () {
      window.BootstrapApp.tryCloseModal();
    };
    bindTabs();

    function applySfxState(v) {
      if (typeof v !== 'boolean') return;
      var el = document.getElementById('about-sfx');
      if (el) el.checked = v;
      if (window.BootstrapAudio) window.BootstrapAudio.setSfxEnabled(v);
    }
    function applyAmbientState(v) {
      if (typeof v !== 'boolean') return;
      var el = document.getElementById('about-ambient');
      if (el) el.checked = v;
      if (window.BootstrapAudio) window.BootstrapAudio.setAmbientEnabled(v);
    }
    var sfxChk = document.getElementById('about-sfx');
    sfxChk.onchange = function () {
      var desired = sfxChk.checked;
      if (window.BootstrapAudio) window.BootstrapAudio.setSfxEnabled(desired);
      window.BootstrapApp.sendConfigSet('sfxEnabled', desired, applySfxState);
    };
    var ambChk = document.getElementById('about-ambient');
    ambChk.onchange = function () {
      var desired = ambChk.checked;
      if (window.BootstrapAudio) window.BootstrapAudio.setAmbientEnabled(desired);
      window.BootstrapApp.sendConfigSet('ambientEnabled', desired, applyAmbientState);
    };
  }

  function unmount() {
    var pending = _requests.slice();
    _requests = [];
    if (_container) _container.classList.remove('about-surface');
    _container = null;
    pending.forEach(function (xhr) {
      try {
        xhr.onreadystatechange = null;
        xhr.abort();
      } catch (e) {}
    });
  }

  window.BootstrapApp.registerModule('about', {mount: mount, unmount: unmount});
})();
