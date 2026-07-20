(function() {
    'use strict';

    var params = new URLSearchParams(window.location.search);
    var dataUrl = params.get('data') || '/tmp/equipment-inspector-review/review-data.json';
    var dataset = null;
    var decisions = {};
    var storageKey = '';
    var liveController = null;
    var liveModal = null;
    var list = document.getElementById('review-list');
    var summary = document.getElementById('summary');
    var progress = document.getElementById('progress');
    var progressLabel = document.getElementById('progress-label');
    var kindFilter = document.getElementById('kind-filter');
    var statusFilter = document.getElementById('status-filter');
    var search = document.getElementById('search');
    var previewDialog = document.getElementById('preview-dialog');
    var previewTitle = document.getElementById('dialog-title');
    var previewImage = document.getElementById('dialog-image');
    var previewCaption = document.getElementById('dialog-caption');
    var validStatuses = {pass:true, 'live-pass':true, adjustment:true, source:true};
    var iconsReady = new Promise(function(resolve) {
        if (typeof Icons === 'undefined' || !Icons || !Icons.load) resolve();
        else Icons.load(resolve);
    });

    function escapeHtml(value) {
        return String(value === undefined || value === null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function itemById(id) {
        return dataset && dataset.items.find(function(item) { return item.id === id; });
    }

    function branchById(item, id) {
        return item && item.requiredBranches.find(function(branch) { return branch.id === id; });
    }

    function itemDecision(item) {
        return decisions[item.id] || {};
    }

    function branchDecision(item, branch) {
        var branches = itemDecision(item).branches || {};
        return branches[branch.id] || {};
    }

    function branchReviewed(item, branch) {
        return !!validStatuses[branchDecision(item, branch).status];
    }

    function itemReviewed(item) {
        return item.requiredBranches.every(function(branch) { return branchReviewed(item, branch); });
    }

    function itemHasWarnings(item) {
        return !!(item.warnings && item.warnings.length) || item.requiredBranches.some(function(branch) {
            return branch.warnings && branch.warnings.length;
        });
    }

    function compatibleDecisions(value) {
        var source = value && typeof value === 'object' ? value : {};
        var result = {};
        dataset.items.forEach(function(item) {
            var previous = source[item.id];
            if (!previous || typeof previous !== 'object') return;
            var nextBranches = {};
            item.requiredBranches.forEach(function(branch) {
                var previousBranch = previous.branches && previous.branches[branch.id];
                if (!previousBranch || typeof previousBranch !== 'object') return;
                var next = {};
                if (previousBranch.motionReviewed === true && branch.approval.requiresLiveReview) {
                    next.motionReviewed = true;
                }
                if (validStatuses[previousBranch.status]) {
                    if (previousBranch.status === 'pass' && !branch.approval.staticSignable) return;
                    if (previousBranch.status === 'live-pass') {
                        // live-pass 只有同时带有显式 motionReviewed 证据才可恢复。
                        // 单独伪造 status 会被降级成待验收。
                        if (branch.approval.liveSignable && next.motionReviewed === true) {
                            next.status = previousBranch.status;
                        }
                    } else next.status = previousBranch.status;
                }
                if (previousBranch.note) next.note = String(previousBranch.note);
                if (Object.keys(next).length) nextBranches[branch.id] = next;
            });
            if (Object.keys(nextBranches).length) result[item.id] = {branches:nextBranches};
        });
        return result;
    }

    function loadStoredDecisions() {
        var value = localStorage.getItem(storageKey);
        if (!value) return {};
        return compatibleDecisions(JSON.parse(value));
    }

    function save() {
        localStorage.setItem(storageKey, JSON.stringify(decisions));
        updateProgress();
    }

    function updateProgress() {
        var branches = dataset.items.reduce(function(all, item) {
            return all.concat(item.requiredBranches.map(function(branch) { return {item:item, branch:branch}; }));
        }, []);
        var reviewed = branches.filter(function(pair) { return branchReviewed(pair.item, pair.branch); }).length;
        progress.max = Math.max(1, branches.length);
        progress.value = reviewed;
        progressLabel.textContent = reviewed + ' / ' + branches.length + ' required 分支已处置';
    }

    function filteredItems() {
        var needle = search.value.trim().toLowerCase();
        return dataset.items.filter(function(item) {
            if (kindFilter.value !== 'all' && item.kind !== kindFilter.value) return false;
            if (statusFilter.value === 'pending' && itemReviewed(item)) return false;
            if (statusFilter.value === 'reviewed' && !itemReviewed(item)) return false;
            if (statusFilter.value === 'warning' && !itemHasWarnings(item)) return false;
            if (statusFilter.value === 'live' && !item.requiredBranches.some(function(branch) {
                return branch.approval.requiresLiveReview;
            })) return false;
            if (statusFilter.value === 'duplicate' && !item.duplicateName) return false;
            if (needle) {
                var haystack = [item.name, item.displayName, item.iconName, item.sourceFile, item.sourceRef,
                    item.use, item.actionType, item.majorType].join(' ').toLowerCase();
                if (haystack.indexOf(needle) < 0) return false;
            }
            return true;
        });
    }

    function statusOptions(branch, decision) {
        var status = decision.status || '';
        function option(value, label, disabled) {
            return '<option value="' + value + '"' + (status === value ? ' selected' : '') +
                (disabled ? ' disabled' : '') + '>' + label + '</option>';
        }
        return option('', '待验收', false) +
            option('pass', '静态构图通过', !branch.approval.staticSignable) +
            option('live-pass', 'live 动效通过' + (decision.motionReviewed ? '（已查看）' : '（先完成查看确认）'),
                !branch.approval.liveSignable || decision.motionReviewed !== true) +
            option('adjustment', '需要调构图', false) +
            option('source', '缺少合适素材', false);
    }

    function branchMetrics(branch) {
        var bbox = branch.metrics && branch.metrics.bbox || {};
        var parts = [];
        if (bbox.width) parts.push('内容 ' + bbox.width + '×' + bbox.height);
        if (branch.specialization && branch.specialization.gain !== null) {
            parts.push('185% 特写 ' + branch.specialization.gain.toFixed(2) + '×');
        }
        if (branch.render) parts.push('holder ' + (branch.render.holders || 0) + '/' + branch.expectedHolders);
        return parts.join(' · ');
    }

    function branchHtml(item, branch) {
        var decision = branchDecision(item, branch);
        var reviewed = branchReviewed(item, branch);
        var blocking = branch.approval.blockingGates || [];
        var warningTags = (branch.warnings || []).map(function(value) {
            return '<span class="tag warning">' + escapeHtml(value) + '</span>';
        }).join('');
        var gateTags = blocking.map(function(value) {
            return '<span class="tag ' + (value === 'live_animation' ? 'live' : 'bad') + '">' + escapeHtml(value) + '</span>';
        }).join('');
        if (decision.motionReviewed) gateTags += '<span class="tag live">motionReviewed</span>';
        return '<section class="review-branch" data-branch-id="' + escapeHtml(branch.id) + '" data-reviewed="' + reviewed +
            '" data-blocked="' + String(!branch.approval.staticSignable && !branch.approval.liveSignable) + '">' +
            '<button class="branch-image-button" type="button" data-preview-item="' + escapeHtml(item.id) + '" data-preview-branch="' +
                escapeHtml(branch.id) + '" aria-label="放大静态首帧 ' + escapeHtml(branch.label) + '">' +
                '<img loading="lazy" src="' + escapeHtml(branch.uri) + '" alt="' + escapeHtml(item.displayName + ' ' + branch.label) + '">' +
            '</button>' +
            '<div class="branch-body">' +
                '<h3>' + escapeHtml(branch.label) + '</h3>' +
                '<p>' + escapeHtml(branch.gender + ' · ' + branch.route + ' · ' + branchMetrics(branch)) + '</p>' +
                '<div class="branch-tags">' + gateTags + warningTags + '</div>' +
                '<label class="branch-status">分支结论<select data-branch-status>' + statusOptions(branch, decision) + '</select></label>' +
                '<button class="live-preview" type="button" data-live-item="' + escapeHtml(item.id) + '" data-live-branch="' +
                    escapeHtml(branch.id) + '">' + (branch.approval.requiresLiveReview ? '打开 live 动效（必验）' : '打开 185% 交互检视') + '</button>' +
                '<textarea class="branch-note" data-branch-note placeholder="该分支备注">' + escapeHtml(decision.note || '') + '</textarea>' +
            '</div>' +
        '</section>';
    }

    function rowHtml(item) {
        var warnings = (item.warnings || []).map(function(value) {
            return '<span class="tag warning">' + escapeHtml(value) + '</span>';
        }).join('');
        var duplicate = item.duplicateName
            ? '<span class="tag bad">重名 ' + item.duplicateName.occurrence + '/' + item.duplicateName.total + '</span>' : '';
        var canPassRow = item.requiredBranches.every(function(branch) { return branch.approval.staticSignable; });
        return '<article class="review-row" data-item-id="' + escapeHtml(item.id) + '" data-dom-key="' + escapeHtml(item.domKey) +
            '" data-reviewed="' + itemReviewed(item) +
            '" data-warning="' + itemHasWarnings(item) + '">' +
            '<section class="item-meta">' +
                '<h2>' + escapeHtml(item.displayName || item.name || '(未命名定义)') + '</h2>' +
                (item.displayName !== item.name ? '<p>物品键 ' + escapeHtml(item.name) + '</p>' : '') +
                (item.iconName !== item.name ? '<p>图标键 ' + escapeHtml(item.iconName) + '</p>' : '') +
                '<p>' + escapeHtml(item.majorType + ' · ' + (item.use || '未分类') + (item.actionType ? ' · ' + item.actionType : '')) + '</p>' +
                '<p class="source-ref">' + escapeHtml(item.sourceRef) + '</p>' +
                '<div class="baseline-reference"><img loading="lazy" src="' + escapeHtml(item.baseline.uri) +
                    '" alt="' + escapeHtml((item.displayName || item.name) + ' 当前图标基线') + '"><span>当前图标基线（仅对照）</span></div>' +
                '<div class="item-tags">' + duplicate + warnings + '</div>' +
                '<button class="row-pass primary" type="button" data-pass-row="' + escapeHtml(item.id) + '"' +
                    (canPassRow ? '' : ' disabled title="含 live 或自动阻断分支，不能批量签署"') + '>整行 required 分支全通过</button>' +
            '</section>' +
            '<section class="branch-grid">' + item.requiredBranches.map(function(branch) { return branchHtml(item, branch); }).join('') + '</section>' +
        '</article>';
    }

    function render() {
        var items = filteredItems();
        list.innerHTML = items.length ? items.map(rowHtml).join('') : '<div class="empty">当前筛选没有装备定义</div>';
        updateProgress();
    }

    function updateBranch(item, branch, patch) {
        var nextItem = Object.assign({}, itemDecision(item));
        nextItem.branches = Object.assign({}, nextItem.branches || {});
        nextItem.branches[branch.id] = Object.assign({}, nextItem.branches[branch.id] || {}, patch);
        decisions[item.id] = nextItem;
        save();
    }

    function openStaticPreview(item, branch) {
        previewTitle.textContent = (item.displayName || item.name) + ' · ' + branch.label;
        previewImage.src = branch.uri;
        previewImage.alt = previewTitle.textContent;
        previewCaption.textContent = '这是 256px 静态首帧；动效分支不能据此签署。' +
            (branch.specialization.gain === null ? '' : ' 默认 185% 特写增益 ' + branch.specialization.gain.toFixed(2) + '×。');
        previewDialog.showModal();
    }

    function closeLiveModal(reason) {
        if (!liveModal) return false;
        var current = liveModal;
        liveModal = null;
        liveController = null;
        if (current.layer.parentNode) current.layer.parentNode.removeChild(current.layer);
        if (typeof current.options.onClose === 'function') current.options.onClose(reason || 'close');
        return true;
    }

    var liveShell = {
        openModal: function(options) {
            closeLiveModal('replace');
            var layer = document.createElement('div');
            layer.className = 'review-live-layer workbench-shell';
            var dialog = document.createElement('section');
            dialog.className = 'workbench-modal';
            dialog.setAttribute('data-modal-kind', options.kind || 'equipment-inspector');
            dialog.setAttribute('role', 'dialog');
            dialog.setAttribute('aria-modal', 'true');
            var kicker = document.createElement('div');
            kicker.className = 'workbench-modal-kicker';
            kicker.textContent = options.kicker || '装备检视';
            var title = document.createElement('h2');
            title.className = 'workbench-modal-title';
            title.textContent = options.title || '装备检视';
            var actions = document.createElement('div');
            actions.className = 'workbench-modal-actions';
            (options.actions || []).forEach(function(action) {
                var button = document.createElement('button');
                button.type = 'button';
                button.className = 'workbench-modal-action' + (action.primary ? ' primary' : '');
                button.textContent = action.label || '关闭';
                button.addEventListener('click', function() { closeLiveModal(action.id || 'action'); });
                actions.appendChild(button);
            });
            dialog.appendChild(kicker);
            dialog.appendChild(title);
            dialog.appendChild(actions);
            layer.appendChild(dialog);
            layer.addEventListener('click', function(event) {
                if (event.target === layer) closeLiveModal('backdrop');
            });
            document.body.appendChild(layer);
            liveModal = {layer:layer, dialog:dialog, options:options};
            return {dialog:dialog};
        },
        closeModal: function() { return closeLiveModal('close'); },
        hasModal: function() { return !!liveModal; }
    };

    function openLivePreview(item, branch) {
        return iconsReady.then(function() {
            closeLiveModal('replace');
            liveController = EquipmentInspector.open({
                shell: liveShell,
                item: {
                    name: item.name,
                    displayName: item.displayName,
                    icon: item.iconName,
                    majorType: item.majorType,
                    type: item.type,
                    use: item.use,
                    actionType: item.actionType
                },
                gender: branch.liveGender || branch.gender || '男',
                kind: 'equipment-inspector',
                kicker: branch.approval.requiresLiveReview ? 'live 动效硬门验收' : '装备检视复核',
                closeLabel: '返回全量验收',
                context: 'equipment-inspector-review',
                manifestUrl: '/launcher/web/assets/dressup/manifest.json',
                onClose: function() { liveController = null; }
            });
            if (liveController && branch.approval.requiresLiveReview) {
                var controllerAtOpen = liveController;
                var actions = document.querySelector('.review-live-layer .workbench-modal-actions');
                var confirm = document.createElement('button');
                confirm.type = 'button';
                confirm.className = 'workbench-modal-action motion-review-confirm';
                confirm.setAttribute('data-motion-review-confirm', branch.id);
                confirm.disabled = true;
                confirm.textContent = '等待 live 动效加载…';
                confirm.addEventListener('click', function() {
                    if (confirm.disabled) return;
                    updateBranch(item, branch, {motionReviewed:true});
                    // 立即刷新底层 required 分支，使 live-pass 在本次 modal 生命周期内
                    // 就解锁；render 只替换审图列表，不触碰独立的 live modal/renderer。
                    render();
                    confirm.disabled = true;
                    confirm.textContent = '已记录：完成动效查看';
                });
                if (actions) actions.insertBefore(confirm, actions.firstChild);
                (function waitForActualLiveRender() {
                    if (!liveModal || liveController !== controllerAtOpen) return;
                    var state = controllerAtOpen.debugState ? controllerAtOpen.debugState() : null;
                    var ready = state && state.source === 'icon'
                        ? true : !!(state && state.render && state.render.animated);
                    if (ready) {
                        var alreadyReviewed = branchDecision(item, branch).motionReviewed === true;
                        confirm.disabled = alreadyReviewed;
                        confirm.textContent = alreadyReviewed ? '已记录：完成动效查看' : '确认：已完成动效查看';
                    } else window.setTimeout(waitForActualLiveRender, 100);
                })();
            }
            return liveController;
        });
    }

    function exportReview() {
        // 导出前重新过兼容门，缺 motionReviewed 的伪 live-pass 不得进入文件。
        decisions = compatibleDecisions(decisions);
        save();
        var payload = {
            schema: 'cf7-equipment-inspector-review-decisions-v1',
            sourceDigest: dataset.sourceDigest,
            reviewDigest: dataset.reviewDigest,
            exportedAt: new Date().toISOString(),
            decisions: decisions
        };
        var blob = new Blob([JSON.stringify(payload, null, 2) + '\n'], {type:'application/json'});
        var link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = 'equipment-inspector-review-decisions.json';
        link.click();
        setTimeout(function() { URL.revokeObjectURL(link.href); }, 1000);
    }

    function importReview(file) {
        var reader = new FileReader();
        reader.onload = function() {
            try {
                var payload = JSON.parse(String(reader.result || '{}'));
                if (payload.schema !== 'cf7-equipment-inspector-review-decisions-v1') throw new Error('不支持的验收文件格式');
                if (payload.sourceDigest !== dataset.sourceDigest) {
                    throw new Error('sourceDigest 不一致：本工具拒绝跨素材集合迁移验收状态');
                }
                if (!payload.reviewDigest || payload.reviewDigest !== dataset.reviewDigest) {
                    throw new Error('reviewDigest 不一致：同一素材源的渲染结果/合同证据不同，拒绝迁移验收状态');
                }
                decisions = compatibleDecisions(payload.decisions || {});
                save();
                render();
            } catch (error) {
                window.alert(String(error && error.message || error));
            }
        };
        reader.readAsText(file, 'utf-8');
    }

    list.addEventListener('click', function(event) {
        var preview = event.target.closest('[data-preview-item]');
        if (preview) {
            event.preventDefault();
            var previewItem = itemById(preview.getAttribute('data-preview-item'));
            var previewBranch = branchById(previewItem, preview.getAttribute('data-preview-branch'));
            if (previewItem && previewBranch) openStaticPreview(previewItem, previewBranch);
            return;
        }
        var live = event.target.closest('[data-live-item]');
        if (live) {
            var liveItem = itemById(live.getAttribute('data-live-item'));
            var liveBranch = branchById(liveItem, live.getAttribute('data-live-branch'));
            if (liveItem && liveBranch) openLivePreview(liveItem, liveBranch);
            return;
        }
        var passRow = event.target.closest('[data-pass-row]');
        if (passRow && !passRow.disabled) {
            var item = itemById(passRow.getAttribute('data-pass-row'));
            if (!item) return;
            var next = {branches:{}};
            item.requiredBranches.forEach(function(branch) {
                var previous = branchDecision(item, branch);
                next.branches[branch.id] = {status:'pass', note:previous.note || ''};
            });
            decisions[item.id] = next;
            save();
            render();
        }
    });

    list.addEventListener('change', function(event) {
        if (!event.target.hasAttribute('data-branch-status')) return;
        var row = event.target.closest('.review-row');
        var branchNode = event.target.closest('.review-branch');
        var item = row && itemById(row.getAttribute('data-item-id'));
        var branch = item && branchById(item, branchNode.getAttribute('data-branch-id'));
        if (!item || !branch) return;
        var status = event.target.value;
        if (status === 'live-pass' && branchDecision(item, branch).motionReviewed !== true) {
            event.target.value = '';
            return;
        }
        updateBranch(item, branch, {status:status});
        render();
    });

    list.addEventListener('input', function(event) {
        if (!event.target.hasAttribute('data-branch-note')) return;
        var row = event.target.closest('.review-row');
        var branchNode = event.target.closest('.review-branch');
        var item = row && itemById(row.getAttribute('data-item-id'));
        var branch = item && branchById(item, branchNode.getAttribute('data-branch-id'));
        if (!item || !branch) return;
        updateBranch(item, branch, {note:event.target.value});
    });

    [kindFilter, statusFilter].forEach(function(control) { control.addEventListener('change', render); });
    search.addEventListener('input', render);
    document.getElementById('export-button').addEventListener('click', exportReview);
    document.getElementById('import-button').addEventListener('click', function() {
        document.getElementById('import-file').click();
    });
    document.getElementById('import-file').addEventListener('change', function() {
        if (this.files && this.files[0]) importReview(this.files[0]);
        this.value = '';
    });
    window.addEventListener('keydown', function(event) {
        if (event.key === 'Escape' && liveModal) closeLiveModal('escape');
    });
    window.addEventListener('review-export-saved', function(event) {
        summary.textContent = '验收结果已保存：' + String(event.detail || 'equipment-inspector-review-decisions.json');
    });

    fetch(dataUrl).then(function(response) {
        if (!response.ok) throw new Error('评审数据加载失败：HTTP ' + response.status);
        return response.json();
    }).then(function(data) {
        dataset = data;
        if (dataset.schema !== 'cf7-equipment-inspector-review-v1') throw new Error('评审数据 schema 不匹配');
        if (!dataset.reviewDigest) throw new Error('评审数据缺少 reviewDigest，必须重新全量生成');
        storageKey = 'cf7-equipment-inspector-review:' + dataset.reviewDigest;
        try { decisions = loadStoredDecisions(); } catch (ignore) { decisions = {}; }
        var counts = dataset.counts;
        summary.textContent = counts.definitionCount + ' 条原始定义 · ' + counts.candidateCount + ' 张候选（含基线） · ' +
            counts.requiredBranchCount + ' 个 required 决定 · ' +
            counts.duplicateNameGroupCount + ' 组重名 · ' + counts.fallbackBranchCount + ' 个回退 · ' +
            counts.liveReviewGateCount + ' 个 live 硬门' + (dataset.partial ? ' · 非正式 partial 数据' : '');
        render();
    }).catch(function(error) {
        summary.textContent = String(error && error.message || error);
        list.innerHTML = '<div class="empty">请先运行 node tools/build-equipment-inspector-review.js 生成全量数据。</div>';
    });
})();
