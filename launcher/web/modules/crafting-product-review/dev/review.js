(function() {
    'use strict';

    var params = new URLSearchParams(window.location.search);
    var dataUrl = params.get('data') || '/tmp/crafting-product-review/review-data.json';
    var dataset = null;
    var decisions = {};
    var storageKey = '';
    var list = document.getElementById('review-list');
    var summary = document.getElementById('summary');
    var progress = document.getElementById('progress');
    var progressLabel = document.getElementById('progress-label');
    var kindFilter = document.getElementById('kind-filter');
    var statusFilter = document.getElementById('status-filter');
    var search = document.getElementById('search');
    var dialog = document.getElementById('preview-dialog');
    var dialogTitle = document.getElementById('dialog-title');
    var dialogCandidates = document.getElementById('dialog-candidates');

    function escapeHtml(value) {
        return String(value === undefined || value === null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function decisionFor(item) {
        return decisions[item.name] || {};
    }

    function isReviewed(decision) {
        return !!(decision.candidateId || decision.needsAdjustment || decision.needsSource);
    }

    function candidateSelectable(candidate) {
        return !!candidate && candidate.reviewRole !== 'nonqualifying' &&
            !(candidate.animation && candidate.animation.contractPass === false);
    }

    function compatibleDecisions(value, previousSourceDigest) {
        var source = value && typeof value === 'object' ? value : {};
        var result = {};
        var sameSource = previousSourceDigest === dataset.sourceDigest;
        dataset.items.forEach(function(item) {
            var previous = source[item.name];
            if (!previous || typeof previous !== 'object') return;
            var next = {};
            if (sameSource && previous.candidateId && item.candidates.some(function(candidate) {
                return candidate.id === previous.candidateId && candidateSelectable(candidate);
            })) {
                next.candidateId = previous.candidateId;
            }
            if (previous.needsAdjustment) next.needsAdjustment = true;
            if (previous.needsSource) next.needsSource = true;
            if (previous.note) next.note = String(previous.note);
            if (Object.keys(next).length) result[item.name] = next;
        });
        return result;
    }

    function loadStoredDecisions() {
        var current = localStorage.getItem(storageKey);
        if (current) return { decisions: compatibleDecisions(JSON.parse(current), dataset.sourceDigest), migrated: 0 };
        var prefix = 'cf7-crafting-product-review:';
        var best = {};
        var bestScore = 0;
        for (var index = 0; index < localStorage.length; index += 1) {
            var key = localStorage.key(index);
            if (!key || key === storageKey || key.indexOf(prefix) !== 0) continue;
            try {
                var previousDigest = key.slice(prefix.length);
                var candidate = compatibleDecisions(JSON.parse(localStorage.getItem(key) || '{}'), previousDigest);
                // 跨候选集只迁移问题标志与备注，绝不迁移候选通过决定。
                var score = Object.keys(candidate).length;
                if (score > bestScore) {
                    best = candidate;
                    bestScore = score;
                }
            } catch (ignore) {}
        }
        if (bestScore) localStorage.setItem(storageKey, JSON.stringify(best));
        return { decisions: best, migrated: bestScore };
    }

    function itemHasWarnings(item) {
        return !!(item.warnings && item.warnings.length) || item.candidates.some(function(candidate) {
            return candidate.warnings && candidate.warnings.length;
        });
    }

    function filteredItems() {
        var needle = search.value.trim().toLowerCase();
        return dataset.items.filter(function(item) {
            var decision = decisionFor(item);
            if (kindFilter.value !== 'all' && item.kind !== kindFilter.value) return false;
            if (statusFilter.value === 'unreviewed' && isReviewed(decision)) return false;
            if (statusFilter.value === 'reviewed' && !isReviewed(decision)) return false;
            if (statusFilter.value === 'warning' && !itemHasWarnings(item)) return false;
            if (statusFilter.value === 'needs_adjustment' && !decision.needsAdjustment) return false;
            if (statusFilter.value === 'needs_source' && !decision.needsSource) return false;
            if (needle) {
                var haystack = [item.name, item.displayName, item.use, item.kind, item.actionType]
                    .concat(item.categories || []).join(' ').toLowerCase();
                if (haystack.indexOf(needle) < 0) return false;
            }
            return true;
        });
    }

    function candidateMetrics(candidate) {
        var metrics = candidate.metrics || {};
        var bbox = metrics.bbox || {};
        var parts = [];
        if (bbox.width) parts.push('内容 ' + bbox.width + '×' + bbox.height);
        if (metrics.alphaRatio !== undefined) parts.push('实占 ' + Math.round(metrics.alphaRatio * 100) + '%');
        if (candidate.sourceWidth) parts.push('源 ' + candidate.sourceWidth + 'px');
        if (candidate.specialization && candidate.specialization.gain !== null) {
            parts.push('特写 ' + candidate.specialization.gain.toFixed(2) + '×');
        }
        return parts.join(' · ');
    }

    function candidateHtml(item, candidate, decision) {
        var id = 'pick-' + item.id + '-' + candidate.id;
        var roleClass = candidate.reviewRole === 'recommended' ? ' candidate-recommended' :
            (candidate.reviewRole === 'reference' ? ' candidate-reference' :
                (candidate.reviewRole === 'nonqualifying' ? ' candidate-nonqualifying' : ''));
        var roleTag = candidate.reviewRole === 'recommended' ? '<span class="tag recommended">优先审</span>' :
            (candidate.reviewRole === 'reference' ? '<span class="tag reference">构型参考</span>' :
                (candidate.reviewRole === 'nonqualifying' ? '<span class="tag nonqualifying">未达特写门</span>' : ''));
        var warnings = (candidate.warnings || []).map(function(value) {
            return '<span class="tag warning">' + escapeHtml(value) + '</span>';
        }).join('');
        var selectable = candidateSelectable(candidate);
        return '<label class="candidate' + roleClass + '">' +
            '<button class="candidate-image-button" type="button" data-preview-item="' + escapeHtml(item.id) + '" aria-label="放大 ' + escapeHtml(candidate.label) + '">' +
                '<img loading="lazy" src="' + escapeHtml(candidate.uri) + '" alt="' + escapeHtml(item.name + ' ' + candidate.label) + '">' +
            '</button>' +
            '<span class="candidate-title"><input id="' + id + '" type="radio" name="pick-' + escapeHtml(item.id) + '" value="' + escapeHtml(candidate.id) + '"' +
                (decision.candidateId === candidate.id ? ' checked' : '') + (selectable ? '' : ' disabled') + '><span>' + escapeHtml(candidate.label) + '</span></span>' +
            '<span class="candidate-metrics">' + escapeHtml(candidateMetrics(candidate)) + roleTag + warnings + '</span>' +
        '</label>';
    }

    function rowHtml(item) {
        var decision = decisionFor(item);
        var displayName = item.displayName || item.name;
        var identity = '';
        if (displayName !== item.name) identity += '<p>物品键 ' + escapeHtml(item.name) + '</p>';
        if (item.iconName && item.iconName !== item.name) identity += '<p>图标键 ' + escapeHtml(item.iconName) + '</p>';
        var warningTags = (item.warnings || []).map(function(value) {
            return '<span class="tag warning">' + escapeHtml(value) + '</span>';
        }).join('');
        return '<article class="review-row" data-item-id="' + escapeHtml(item.id) + '" data-reviewed="' + String(isReviewed(decision)) + '" data-warning="' + String(itemHasWarnings(item)) + '">' +
            '<section class="item-meta">' +
                '<h2>' + escapeHtml(displayName) + '</h2>' + identity +
                '<p>' + escapeHtml(item.use || '未分类') + (item.actionType ? ' · ' + escapeHtml(item.actionType) : '') + ' · ' + escapeHtml(item.kindLabel) + '</p>' +
                '<p>覆盖 ' + escapeHtml((item.recipeRefs || []).length) + ' 条配方</p>' +
                '<div class="item-tags">' + (item.categories || []).map(function(value) { return '<span class="tag">' + escapeHtml(value) + '</span>'; }).join('') + warningTags + '</div>' +
            '</section>' +
            '<section class="candidate-grid">' + item.candidates.map(function(candidate) { return candidateHtml(item, candidate, decision); }).join('') +
                '<div class="decision-tools">' +
                    '<label><input type="checkbox" data-decision="needsAdjustment"' + (decision.needsAdjustment ? ' checked' : '') + '>需要调构图</label>' +
                    '<label><input type="checkbox" data-decision="needsSource"' + (decision.needsSource ? ' checked' : '') + '>缺少合适素材</label>' +
                    '<textarea data-decision="note" placeholder="可选备注">' + escapeHtml(decision.note || '') + '</textarea>' +
                '</div>' +
            '</section>' +
        '</article>';
    }

    function render() {
        var items = filteredItems();
        list.innerHTML = items.length ? items.map(rowHtml).join('') : '<div class="empty">当前筛选没有物品</div>';
        updateProgress();
    }

    function save() {
        localStorage.setItem(storageKey, JSON.stringify(decisions));
        updateProgress();
    }

    function updateProgress() {
        var reviewed = dataset.items.filter(function(item) { return isReviewed(decisionFor(item)); }).length;
        progress.max = Math.max(1, dataset.items.length);
        progress.value = reviewed;
        progressLabel.textContent = reviewed + ' / ' + dataset.items.length + ' 已验收';
    }

    function itemById(id) {
        return dataset.items.find(function(item) { return item.id === id; });
    }

    function openPreview(item) {
        dialogTitle.textContent = item.name;
        dialogCandidates.innerHTML = item.candidates.map(function(candidate) {
            return '<div class="dialog-candidate"><img src="' + escapeHtml(candidate.uri) + '" alt="' + escapeHtml(item.name + ' ' + candidate.label) + '"><span>' + escapeHtml(candidate.label) + '</span></div>';
        }).join('');
        dialog.showModal();
    }

    function exportReview() {
        var payload = {
            schema: 'cf7-crafting-product-review-decisions-v1',
            sourceDigest: dataset.sourceDigest,
            exportedAt: new Date().toISOString(),
            decisions: decisions
        };
        var blob = new Blob([JSON.stringify(payload, null, 2) + '\n'], {type: 'application/json'});
        var link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = 'crafting-product-review-decisions.json';
        link.click();
        setTimeout(function() { URL.revokeObjectURL(link.href); }, 1000);
    }

    function importReview(file) {
        var reader = new FileReader();
        reader.onload = function() {
            try {
                var payload = JSON.parse(String(reader.result || '{}'));
                if (payload.schema !== 'cf7-crafting-product-review-decisions-v1') throw new Error('不支持的验收文件格式');
                if (payload.sourceDigest !== dataset.sourceDigest &&
                    !window.confirm('验收文件来自不同的候选集。只迁移问题标志和备注，不迁移候选通过决定，继续？')) return;
                decisions = compatibleDecisions(payload.decisions || {}, payload.sourceDigest);
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
            var item = itemById(preview.getAttribute('data-preview-item'));
            if (item) openPreview(item);
        }
    });
    list.addEventListener('change', function(event) {
        var row = event.target.closest('.review-row');
        if (!row) return;
        var item = itemById(row.getAttribute('data-item-id'));
        if (!item) return;
        var decision = Object.assign({}, decisionFor(item));
        if (event.target.type === 'radio') decision.candidateId = event.target.value;
        if (event.target.getAttribute('data-decision') === 'needsAdjustment') decision.needsAdjustment = event.target.checked;
        if (event.target.getAttribute('data-decision') === 'needsSource') decision.needsSource = event.target.checked;
        decisions[item.name] = decision;
        row.setAttribute('data-reviewed', String(isReviewed(decision)));
        save();
    });
    list.addEventListener('input', function(event) {
        var key = event.target.getAttribute('data-decision');
        if (key !== 'note') return;
        var row = event.target.closest('.review-row');
        var item = row && itemById(row.getAttribute('data-item-id'));
        if (!item) return;
        var decision = Object.assign({}, decisionFor(item));
        decision.note = event.target.value;
        decisions[item.name] = decision;
        save();
    });
    [kindFilter, statusFilter].forEach(function(control) { control.addEventListener('change', render); });
    search.addEventListener('input', render);
    document.getElementById('export-button').addEventListener('click', exportReview);
    document.getElementById('import-button').addEventListener('click', function() { document.getElementById('import-file').click(); });
    document.getElementById('import-file').addEventListener('change', function() {
        if (this.files && this.files[0]) importReview(this.files[0]);
        this.value = '';
    });
    window.addEventListener('review-export-saved', function(event) {
        summary.textContent = '验收结果已保存：' + String(event.detail || 'crafting-product-review-decisions.json');
    });

    fetch(dataUrl).then(function(response) {
        if (!response.ok) throw new Error('评审数据加载失败：HTTP ' + response.status);
        return response.json();
    }).then(function(data) {
        dataset = data;
        storageKey = 'cf7-crafting-product-review:' + dataset.sourceDigest;
        var stored = { decisions: {}, migrated: 0 };
        try { stored = loadStoredDecisions(); } catch (ignore) {}
        decisions = stored.decisions;
        summary.textContent = dataset.counts.recipeCount + ' 条配方 · ' + dataset.counts.uniqueItemCount + ' 个唯一产物 · ' + dataset.counts.candidateCount + ' 张候选' +
            (stored.migrated ? ' · 已迁移 ' + stored.migrated + ' 条旧问题/备注（未迁移通过决定）' : '');
        render();
    }).catch(function(error) {
        summary.textContent = String(error && error.message || error);
        list.innerHTML = '<div class="empty">请先运行全量候选生成命令。</div>';
    });
})();
