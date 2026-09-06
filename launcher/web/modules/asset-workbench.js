/* 人与 CLI 共用素材内核。面板仅负责选择、预览和显式操作。 */
(function() {
    'use strict';
    var root, shell, refs = {}, mux, scale, renderer, iconPreview, pollTimer, help;
    var iconAnimation = true, dollAnimation = false;
    var active = false, generation = 0, previewGeneration = 0, busy = false;
    var catalog = null, selected = null, job = null, view = null, current = null;
    var listRows = Object.create(null), selectedRows = [];
    var labels = {queued:'等待导出', running:'正在生成', ready:'可预览', applied:'已应用', reverted:'已撤回', failed:'生成失败', cancelled:'已取消'};
    function el(tag, cls, text) {
        var node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text !== undefined) node.textContent = text;
        return node;
    }
    function button(text, action, cls) {
        var node = el('button', cls || 'aw-button', text);
        node.type = 'button'; node.addEventListener('click', action); return node;
    }
    function select(label, options, action) {
        var node = el('select', 'aw-select'); node.setAttribute('aria-label', label);
        options.forEach(function(option) {
            var child = el('option', '', option[1]); child.value = option[0]; node.appendChild(child);
        });
        node.addEventListener('change', action); return node;
    }
    function request(cmd, payload, callback) {
        return mux.request(cmd, payload || {}, {singleFlight:true, write:['start','apply','undo','cancel','rescan'].indexOf(cmd) >= 0}, function(response) {
            if (!active) return;
            if (!response.success) {
                var text = response.clientSynthetic ? '尚未收到结果。请点击“刷新任务”，确认后台任务状态。' : response.error;
                showError(text || '操作失败');
            }
            if (callback) callback(response.success ? response.data : null, response);
        });
    }
    function showError(text) {
        refs.diagnostic.textContent = text;
        refs.details.hidden = !text;
        refs.details.open = !!text;
        if (text) shell.setStatus('需要处理', 'error');
    }
    function setBusy(value) { busy = value; updateActions(); }
    function updateActions() {
        var running = job && ['queued','running'].indexOf(job.state) >= 0;
        refs.generate.disabled = busy || running || !selected || !catalog || !catalog.environment.ready;
        refs.apply.disabled = busy || !job || job.state !== 'ready';
        refs.undo.disabled = busy || !job || job.state !== 'applied';
        refs.cancel.disabled = busy || !running;
        refs.rescan.disabled = busy || running;
        refs.refresh.disabled = busy;
        refs.jobs.disabled = busy;
        refs.kind.disabled = busy || running;
        refs.phase.textContent = job ? job.phase : '选择物品，生成一次预览';
        refs.jobInfo.textContent = job ? labels[job.state] + ' · ' + job.item : '尚未选择任务';
    }
    function stopPreview() {
        previewGeneration++;
        if (renderer) { renderer.destroy(); renderer = null; }
        if (iconPreview) { iconPreview.destroy(); iconPreview = null; }
        refs.canvas.getContext('2d').clearRect(0, 0, refs.canvas.width, refs.canvas.height);
        refs.picture.onerror = null;
        refs.picture.removeAttribute('src');
    }
    function filteredItems() {
        var search = refs.search.value.trim().toLowerCase(), filter = refs.filter.value;
        return (catalog ? catalog.items : []).filter(function(item) {
            return (!search || (item.name + item.displayName + item.use + item.libraries.join(' ')).toLowerCase().indexOf(search) >= 0)
                && (filter !== 'missing' || item.missingIcons.length || item.missingSkins.length)
                && (filter !== 'conflict' || item.conflicts.length)
                && (filter.indexOf('swf:') !== 0 || item.libraries.indexOf(filter.slice(4)) >= 0);
        });
    }
    function populateFilters() {
        var previous = refs.filter.value, libraries = {}, names = {};
        (catalog.items || []).forEach(function(item) {
            item.libraries.forEach(function(path) { libraries[path] = (libraries[path] || 0) + 1; });
        });
        Object.keys(libraries).forEach(function(path) {
            var name = path.split('/').pop(); names[name] = (names[name] || 0) + 1;
        });
        refs.filter.replaceChildren();
        [['all','全部物品'],['missing','待补图'],['conflict','冲突']].forEach(function(pair) {
            var option = el('option', '', pair[1]); option.value = pair[0]; refs.filter.appendChild(option);
        });
        var group = el('optgroup'); group.label = '按 SWF 素材库';
        Object.keys(libraries).sort(function(a, b) { return a.localeCompare(b, 'zh-CN', {numeric:true}); }).forEach(function(path) {
            var name = path.split('/').pop();
            var option = el('option', '', (names[name] > 1 ? path : name) + ' · ' + libraries[path] + ' 件');
            option.value = 'swf:' + path; option.title = path; group.appendChild(option);
        });
        if (group.children.length) refs.filter.appendChild(group);
        refs.filter.value = previous;
        if (!refs.filter.value) refs.filter.value = 'all';
    }
    function updateListSelection() {
        selectedRows.forEach(function(row) { row.setAttribute('aria-pressed', 'false'); });
        selectedRows = selected && listRows[selected.name] || [];
        selectedRows.forEach(function(row) { row.setAttribute('aria-pressed', 'true'); });
    }
    function renderList(resetScroll) {
        var items = filteredItems(), scrollTop = resetScroll ? 0 : refs.list.scrollTop;
        var fragment = document.createDocumentFragment();
        listRows = Object.create(null); selectedRows = [];
        items.forEach(function(item) {
            var row = button('', function() { choose(item); }, 'aw-item');
            row.setAttribute('aria-pressed', 'false');
            if (!listRows[item.name]) listRows[item.name] = [];
            listRows[item.name].push(row);
            var title = el('span', 'aw-item-title', item.displayName);
            title.appendChild(el('small', '', item.use || '物品'));
            row.appendChild(title);
            var missing = item.missingIcons.length + item.missingSkins.length;
            row.appendChild(el('span', 'aw-item-status' + (missing || item.conflicts.length ? ' is-missing' : ''),
                item.conflicts.length ? '来源冲突' : missing ? '待补 ' + missing + ' 项' : '已有图片'));
            fragment.appendChild(row);
        });
        if (!items.length) fragment.appendChild(el('p', 'aw-empty', '没有匹配的物品'));
        refs.list.replaceChildren(fragment); refs.list.scrollTop = scrollTop;
        updateListSelection(); refs.count.textContent = items.length + ' 件物品';
    }
    function choose(item) {
        if (busy) return;
        selected = item; job = null; view = null;
        mux.cancelKind('status');
        clearTimeout(pollTimer); stopPreview(); showError('');
        refs.title.textContent = item.displayName;
        refs.source.textContent = item.libraries.join('\n') || '未找到已发布的素材库';
        refs.source.title = item.sourceFile + '\n' + item.skinKeys.join('\n');
        refs.side.value = 'before'; refs.jobs.value = '';
        refs.pose.value = item.use === '长枪' ? '长枪站立' : item.use === '手枪' ? '手枪站立' : item.use === '刀' ? '兵器站立' : 'dialogue';
        updateListSelection(); updateActions(); renderPreview();
    }
    function populateJobs(jobs) {
        var value = job ? job.jobId : refs.jobs.value;
        refs.jobs.replaceChildren(el('option', '', '最近任务…'));
        refs.jobs.firstChild.value = '';
        (jobs || []).forEach(function(entry) {
            var option = el('option', '', entry.item + ' · ' + (labels[entry.state] || entry.state));
            option.value = entry.jobId; refs.jobs.appendChild(option);
        });
        refs.jobs.value = value;
    }
    function refreshCatalog(rescan) {
        if (busy) return;
        setBusy(true); showError(''); shell.setStatus(rescan ? '正在扫描来源' : '正在读取目录', 'loading');
        request(rescan ? 'rescan' : 'catalog', {}, function(data) {
            setBusy(false);
            if (!data) return;
            catalog = data; populateFilters(); populateJobs(data.jobs); renderList();
            refs.environment.textContent = data.environment.ready ? '导出环境就绪' : '导出环境尚未就绪';
            refs.environment.title = data.environment.problems.join('\n');
            refs.mapState.textContent = data.sourceMapPending ? '新来源已扫描，将随下一次应用写入项目' : '从已发布 SWF 提取；修改 FLA 后请先在 CS6 发布';
            if (!data.environment.ready) showError(data.environment.problems.join('\n'));
            else shell.setStatus('就绪', 'ready');
            if (!selected) {
                var items = filteredItems();
                if (items[0]) choose(items[0]);
                var recent = data.jobs.find(function(entry) { return ['ready','running','queued'].indexOf(entry.state) >= 0 && items.some(function(item) { return item.name === entry.item; }); });
                if (recent) loadJob(recent.jobId);
            }
            updateActions();
        });
    }
    function adoptJob(data) {
        if (!data) return;
        var previous = job, changedPreview = !previous || previous.jobId !== data.jobId || previous.state !== data.state;
        var changedItem = !selected || selected.name !== data.item;
        job = data;
        selected = catalog.items.find(function(item) { return item.name === data.item; }) || data.selection;
        refs.title.textContent = selected.displayName;
        refs.source.textContent = selected.libraries.join('\n');
        refs.source.title = selected.sourceFile + '\n' + selected.skinKeys.join('\n');
        if (changedItem) refs.pose.value = selected.use === '长枪' ? '长枪站立' : selected.use === '手枪' ? '手枪站立' : selected.use === '刀' ? '兵器站立' : 'dialogue';
        var option = Array.from(refs.jobs.options).find(function(entry) { return entry.value === data.jobId; });
        if (!option) { option = el('option'); option.value = data.jobId; refs.jobs.insertBefore(option, refs.jobs.options[1] || null); }
        option.textContent = data.item + ' · ' + (labels[data.state] || data.state);
        refs.jobs.value = data.jobId; updateListSelection(); updateActions();
        shell.setStatus(labels[data.state] || data.state, data.state === 'failed' ? 'error' : 'ready');
        showError(data.error || (data.warnings || []).join('\n'));
        clearTimeout(pollTimer);
        if (['queued','running'].indexOf(data.state) >= 0) {
            if (changedPreview) { view = null; renderPreview(); }
            pollTimer = setTimeout(function() { if (active) loadJob(data.jobId); }, 1200);
        } else if (data.previewRoot && changedPreview) {
            refs.side.value = 'after'; loadPreview();
        }
    }
    function loadJob(id) { mux.cancelKind('status'); request('status', {jobId:id}, adoptJob); }
    function newId() {
        var bytes = new Uint8Array(16); crypto.getRandomValues(bytes);
        return Array.from(bytes, function(b) { return b.toString(16).padStart(2, '0'); }).join('');
    }
    function generate() {
        if (!selected || busy) return;
        showError(''); setBusy(true);
        var id = newId();
        job = {jobId:id, item:selected.name, selection:selected, state:'queued', phase:'正在提交任务'};
        view = null; stopPreview(); updateActions();
        request('start', {item:selected.name, kind:refs.kind.value, jobId:id}, function(data, response) {
            setBusy(false);
            if (data) adoptJob(data);
            else {
                if (!response.clientSynthetic) { job.state = 'failed'; job.error = response.error; }
                job.phase = response.clientSynthetic ? '请刷新任务确认是否已开始' : '未开始生成，可修正后重试'; updateActions();
            }
        });
    }
    function mutate(cmd) {
        if (!job || busy) return;
        setBusy(true); showError('');
        request(cmd, {jobId:job.jobId}, function(data) {
            setBusy(false);
            if (data) {
                adoptJob(data);
                if (cmd === 'apply' || cmd === 'undo') { current = null; refreshCatalog(false); }
            }
        });
    }
    function getJson(url) {
        return fetch(url, {cache:'no-store'}).then(function(response) {
            if (!response.ok) throw new Error('读取预览失败：' + response.status);
            return response.json();
        });
    }
    function freshLocalUris(value, base, stamp) {
        if (!value || typeof value !== 'object') return;
        Object.keys(value).forEach(function(key) {
            var child = value[key];
            if (['uri','f1','f2'].indexOf(key) >= 0 && typeof child === 'string' && /\.(png|webp)$/.test(child)) {
                var url = new URL(child, new URL(base, document.baseURI));
                url.searchParams.set('workbench', stamp); value[key] = url.href;
            } else if (child && typeof child === 'object') freshLocalUris(child, base, stamp);
        });
    }
    function loadPreview() {
        var epoch = generation, selectedJob = job && job.jobId, side = refs.side.value;
        var pending = job && job.previewRoot ? getJson(job.previewRoot + side + '/view.json') :
            (current ? Promise.resolve(current) : Promise.all([getJson('icons/manifest.json'), getJson('assets/dressup/manifest.json')]).then(function(values) {
                var stamp = String(Date.now());
                freshLocalUris(values[0], 'icons/', stamp); freshLocalUris(values[1], 'assets/dressup/', stamp);
                values[1].__baseUrl = new URL('assets/dressup/manifest.json', document.baseURI).href;
                current = {icons:values[0], dressup:values[1]}; return current;
            }));
        var ticket = ++previewGeneration;
        pending.then(function(data) {
            if (!active || epoch !== generation || ticket !== previewGeneration || selectedJob !== (job && job.jobId) || side !== refs.side.value) return;
            view = data; renderPreview();
        }).catch(function(error) { if (active && epoch === generation) showError(error.message); });
    }
    function renderPreview() {
        stopPreview();
        if (help && help.isActive()) return;
        if (!selected) return;
        if (!view) { loadPreview(); return; }
        var mode = refs.mode.value, dress = mode === 'dressup' || mode === 'skin';
        refs.canvas.hidden = !dress; refs.picture.hidden = dress || mode === 'f1'; refs.iconHost.hidden = mode !== 'f1'; refs.empty.hidden = true;
        refs.gender.disabled = !dress; refs.pose.disabled = mode !== 'dressup'; refs.animate.disabled = !dress;
        refs.animate.checked = dress ? dollAnimation : false;
        refs.previewLabel.textContent = (job ? (refs.side.value === 'after' ? '候选预览' : '生成前的项目图片') : '当前项目图片') + ' · ' + selected.displayName;
        if (!dress) {
            var entry = view.icons[selected.iconNames[0]], uri = entry && entry[mode];
            if (mode === 'f1') {
                iconPreview = Icons.createPreview(refs.iconHost, entry, {className:'aw-icon-image', label:'所选物品的图标预览', animate:iconAnimation,
                    onError:function() { refs.iconHost.hidden = true; refs.empty.hidden = false; refs.empty.textContent = '图片文件不存在，请生成预览'; }});
                refs.animate.disabled = !iconPreview.animated; refs.animate.checked = iconPreview.animated && iconAnimation;
                if (!iconPreview.available) { refs.iconHost.hidden = true; refs.empty.hidden = false; refs.empty.textContent = '此项尚未生成图片'; }
                else refs.previewLabel.textContent += iconPreview.animated ? (iconAnimation ? ' · 动画播放中' : ' · 静态首帧') : ' · 静态图标';
                return;
            }
            if (!uri) { refs.picture.hidden = true; refs.empty.hidden = false; refs.empty.textContent = '此项尚未生成图片'; return; }
            refs.picture.className = 'aw-picture';
            refs.picture.src = /^(https?:|\/)/.test(uri) ? uri : 'icons/' + uri;
            refs.picture.onerror = function() { refs.picture.hidden = true; refs.empty.hidden = false; refs.empty.textContent = '图片文件不存在，请生成预览'; };
            return;
        }
        var manifest = view.dressup;
        if (!manifest.__baseUrl) manifest.__baseUrl = new URL('assets/dressup/manifest.json', document.baseURI).href;
        var equipment = {}; equipment[selected.use || 'item'] = selected.name;
        renderer = DressupDollRenderer.create(refs.canvas, {manifest:manifest, animate:dollAnimation, margin:24});
        var options = {gender:refs.gender.value, equipment:equipment,
            appearance:{'脸型':refs.gender.value === '女' ? '女变装-基本脸型' : '男变装-基本脸型'},
            rig:refs.pose.value === 'dialogue' ? 'dialogue' : 'battle', stateLabel:refs.pose.value};
        if (mode === 'skin') options.directSkinKey = selected.skinKeys.find(function(key) { return manifest.skinKeys[key] && manifest.skinKeys[key].frames; }) || selected.skinKeys[0];
        if (mode === 'skin' && !options.directSkinKey) { refs.empty.hidden = false; refs.empty.textContent = '这个物品没有人物装扮'; }
        renderer.render(DressupDollRenderer.buildStateFromEquipment(manifest, options));
    }
    function close() { if (active) request('close', {}); }
    function create() {
        root = el('section', 'asset-workbench-panel panel-scale-shell');
        shell = new Workbench.DualPaneShell({profile:'archive-reference', title:'物品素材工作台', status:'正在读取目录', leftLabel:'素材目录', rightLabel:'素材预览', flowLabel:'烘焙', slotMarkers:false});
        root.appendChild(shell.getRoot());
        refs.help = button('帮助', function() { stopPreview(); help.open(refs.help); }, 'aw-button');
        refs.help.setAttribute('aria-label', '素材工作台帮助');
        shell.addHeaderAction(refs.help);
        shell.addHeaderAction(button('关闭', close, 'workbench-close-btn'));
        var left = el('div', 'aw-library'), right = el('div', 'aw-inspector');
        shell.mountInitial({instanceKey:'asset-library', mount:function(host) { host.appendChild(left); }, unmount:function() {}},
            {instanceKey:'asset-preview', mount:function(host) { host.appendChild(right); }, unmount:function() {}});
        refs.search = el('input', 'aw-search'); refs.search.type = 'search'; refs.search.placeholder = '搜索物品、用途或素材库'; refs.search.setAttribute('aria-label','搜索素材');
        refs.search.addEventListener('input', function() { renderList(true); }); left.appendChild(refs.search);
        var filters = el('div', 'aw-toolbar');
        refs.filter = select('素材筛选', [['all','全部物品'],['missing','待补图'],['conflict','冲突']], function() { renderList(true); });
        refs.rescan = button('重新扫描来源', function() { refreshCatalog(true); });
        filters.append(refs.filter, refs.rescan); left.appendChild(filters);
        refs.list = el('div', 'aw-list'); refs.list.setAttribute('aria-label','物品列表'); refs.list.setAttribute('role','region'); refs.list.tabIndex = 0; left.appendChild(refs.list);
        var summary = el('div','aw-toolbar'); refs.count = el('span','aw-count');
        summary.appendChild(refs.count); left.appendChild(summary);
        refs.environment = el('small','aw-environment'); refs.mapState = el('p','aw-note'); left.append(refs.environment, refs.mapState);
        var heading = el('div','aw-heading'); refs.title = el('h2','','选择一个物品'); refs.source = el('p','aw-source'); heading.append(refs.title, refs.source); right.appendChild(heading);
        var generateBar = el('div','aw-toolbar');
        refs.kind = select('生成范围', [['all','图标 + 人物装扮'],['icons','仅图标'],['dressup','仅人物装扮']], function() {});
        refs.generate = button('生成预览', generate, 'aw-button aw-primary'); generateBar.append(refs.kind, refs.generate); right.appendChild(generateBar);
        var previewBar = el('div','aw-toolbar');
        refs.side = select('对比版本', [['before','当前 / 生成前'],['after','候选']], function() { view = null; loadPreview(); });
        refs.mode = select('预览内容', [['f1','物品图标'],['f2','完整展示'],['dressup','人物装扮'],['skin','单独装扮']], renderPreview);
        previewBar.append(refs.side, refs.mode); right.appendChild(previewBar);
        var stage = el('div','aw-stage'); refs.canvas = el('canvas','aw-canvas'); refs.picture = el('img','aw-picture'); refs.picture.alt = '所选物品的导出图片'; refs.iconHost = el('div','aw-icon-host');
        refs.empty = el('span','aw-empty','选择物品后在此预览'); refs.previewLabel = el('small','aw-preview-label');
        stage.append(refs.canvas, refs.picture, refs.iconHost, refs.empty, refs.previewLabel); right.appendChild(stage);
        var poseBar = el('div','aw-toolbar');
        refs.gender = select('预览性别',[['男','男'],['女','女']], renderPreview);
        refs.pose = select('预览姿态', [['dialogue','对话肖像']].concat(['空手站立','长枪站立','手枪站立','手枪2站立','双枪站立','兵器站立','手雷站立'].map(function(name) { return [name,name]; })), renderPreview);
        var animateLabel = el('label','aw-animate'); animateLabel.title = '关闭图标动画后显示静态首帧'; refs.animate = el('input'); refs.animate.type = 'checkbox';
        refs.animate.addEventListener('change', function() { if (refs.mode.value === 'f1') iconAnimation = refs.animate.checked; else dollAnimation = refs.animate.checked; renderPreview(); });
        animateLabel.append(refs.animate, document.createTextNode('播放动画'));
        poseBar.append(refs.gender, refs.pose, animateLabel); right.appendChild(poseBar);
        var jobsBar = el('div','aw-toolbar'); refs.jobs = select('最近素材任务', [['','最近任务…']], function() { if (refs.jobs.value) loadJob(refs.jobs.value); });
        refs.refresh = button('刷新任务', function() { if (job) loadJob(job.jobId); else refreshCatalog(false); });
        jobsBar.append(refs.jobs, refs.refresh); right.appendChild(jobsBar);
        var actions = el('div','aw-toolbar'); refs.apply = button('应用到项目', function() { mutate('apply'); }, 'aw-button aw-primary'); refs.undo = button('撤回本次应用', function() { mutate('undo'); }); refs.cancel = button('取消生成', function() { mutate('cancel'); });
        actions.append(refs.apply, refs.undo, refs.cancel); right.appendChild(actions);
        refs.jobInfo = el('small','aw-job-info'); refs.phase = el('span','aw-phase');
        var status = el('div','aw-status'); status.setAttribute('aria-live','polite'); status.append(refs.jobInfo, refs.phase); right.appendChild(status);
        refs.details = el('details','aw-diagnostics'); refs.details.hidden = true; refs.details.appendChild(el('summary','','诊断信息')); refs.diagnostic = el('pre'); refs.details.appendChild(refs.diagnostic); right.appendChild(refs.details);
        mux = new PanelRuntime.PanelRequestMux({send:function(message) { return Bridge.send(message); }, router:PanelRuntime.sharedResponseRouter, timeoutMs:125000, callPrefix:'asset',
            createMessage:function(ctx) { return {type:'panel',panel:'asset-workbench',domain:'asset_workbench',cmd:ctx.entry.cmd,callId:ctx.entry.callId,panelInstanceId:ctx.session.panelInstanceId,payload:ctx.payload}; },
            validateResponse:function(data, entry, session) { return data.type === 'panel_resp' && data.panel === 'asset-workbench' && data.domain === 'asset_workbench' && data.cmd === entry.cmd && data.callId === entry.callId && data.panelInstanceId === session.panelInstanceId; }});
        help = AssetWorkbenchHelp.create({host:shell.getRoot(), onClose:close,
            onReturn:function() { if (active) renderPreview(); },
            taskInfo:function() { return ['物品：' + (selected ? selected.displayName : '尚未选择'),
                '物品内部名：' + (selected ? selected.name : ''),
                'SWF 来源：' + (selected ? selected.libraries.join('；') : ''),
                '任务：' + (job ? job.jobId + '（' + (labels[job.state] || job.state) + '）' : '尚未生成'),
                '任务目录：' + (job ? 'tmp/asset-workbench/jobs/' + job.jobId + '/' : ''),
                '操作与问题现象（请补充）：', '期望结果（请补充）：'].join('\n'); }});
        return root;
    }
    Panels.register('asset-workbench', {create:create, onOpen:function(node, initData) {
        if (!initData || !initData.panelInstanceId) return false;
        active = true; generation++; current = null; view = null; busy = false; selected = null; job = null;
        mux.openSession({panelInstanceId:initData.panelInstanceId});
        scale = PanelScale.attach(root, 1024, 576); refreshCatalog(false); return true;
    }, onRequestClose:function() { if (help && help.isActive()) help.close('escape'); else close(); }, onClose:function() {
        active = false; generation++; clearTimeout(pollTimer); if (help) help.close('panel-close'); stopPreview(); mux.closeSession();
        if (scale) { scale.detach(); scale = null; }
        current = null; view = null;
    }});
})();
