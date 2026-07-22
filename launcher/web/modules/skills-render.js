/** Skills workbench DOM presenter. Authority state and writes stay in skills.js. */
(function(root, factory) {
    'use strict';
    var trainer = typeof module !== 'undefined' && module.exports
        ? require('./skills-trainer.js') : root && root.SkillsTrainer;
    var api = factory(trainer);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.SkillsRender = api;
})(typeof window !== 'undefined' ? window : globalThis, function(Trainer) {
    'use strict';
    if (!Trainer) throw new Error('SkillsRender requires SkillsTrainer.');

    function create(ports) {
        if (!ports || typeof ports.getState !== 'function') {
            throw new Error('SkillsRender requires explicit state and intent ports.');
        }

        function state() { return ports.getState(); }

        function clearElement(element) {
            if (typeof ports.clearElement === 'function') {
                ports.clearElement(element);
                return;
            }
            while (element && element.firstChild) element.removeChild(element.firstChild);
        }

        function renderList(list, renderOptions) {
            if (!list) return;
            renderOptions = renderOptions || {};
            var preserveScroll = renderOptions.preserveScroll !== false;
            var previousScrollTop = preserveScroll ? list.scrollTop : 0;
            var previousScrollLeft = preserveScroll ? list.scrollLeft : 0;
            var current = state();
            var focusKey = ports.focusKeyOf(document.activeElement);
            function finishListRender() {
                list.scrollTop = previousScrollTop;
                list.scrollLeft = previousScrollLeft;
                ports.restoreFocusKey(focusKey);
            }
            clearElement(list);
            if (current.schemaError) {
                list.appendChild(ports.empty('技能数据暂时无法读取，请重试。', 'error'));
                finishListRender();
                return;
            }
            var entries = ports.visibleEntries();
            if (!entries.length) {
                list.appendChild(ports.empty(current.snapshot ? '没有符合条件的技能' : '正在读取技能状态…'));
                finishListRender();
                return;
            }
            entries.forEach(function(entry) {
                var row = document.createElement('div'); row.className = 'skills-library-row'; row.tabIndex = 0;
                row.setAttribute('role', 'option'); row.setAttribute('data-skill-key', entry.skillKey);
                row.setAttribute('data-focus-key', 'skill:' + entry.skillKey);
                row.setAttribute('aria-selected', entry.skillKey === current.selectedKey ? 'true' : 'false');
                if (entry.skillKey === current.selectedKey) row.classList.add('selected');
                if (entry.writeBlocked || entry.stateHealth !== 'ok') row.classList.add('corrupt');
                var icon = ports.iconNode(entry.iconKey, 'skills-row-icon');
                var copy = document.createElement('span'); copy.className = 'skills-row-copy';
                var name = document.createElement('b'); name.textContent = entry.skillKey;
                var meta = document.createElement('span');
                meta.textContent = entry.currentLevel != null
                    ? '当前 Lv.' + ports.safeNumber(entry.currentLevel) + ' / ' + ports.safeNumber(entry.maxLevel)
                    : 'Lv.' + ports.safeNumber(entry.level) + ' / ' + ports.safeNumber(entry.maxLevel);
                var type = document.createElement('small'); type.textContent = entry.type || '未知类型';
                copy.appendChild(name); copy.appendChild(meta); copy.appendChild(type);
                var badge = document.createElement('span'); badge.className = 'skills-row-badge';
                badge.textContent = ports.healthLabel(entry);
                var tileLevel = document.createElement('span'); tileLevel.className = 'skills-tile-level';
                tileLevel.textContent = 'Lv.' + ports.safeNumber(entry.currentLevel != null ? entry.currentLevel : entry.level);
                var tileState = document.createElement('span'); tileState.className = 'skills-tile-state';
                tileState.textContent = ports.compactStateLabel(entry);
                row.appendChild(icon); row.appendChild(copy); row.appendChild(badge); row.appendChild(tileLevel); row.appendChild(tileState);
                row.setAttribute('aria-label', ports.skillAriaLabel(entry));
                ports.bindSkillTooltip(row, entry);
                row.addEventListener('click', function() {
                    if (ports.consumeDragClick()) return;
                    ports.selectSkill(entry.skillKey);
                });
                row.addEventListener('keydown', function(event) {
                    if (current.view === 'manage' && event.altKey && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
                        event.preventDefault();
                        ports.reorderTo(entry, ports.adjacentVisibleEntry(entry, event.key === 'ArrowDown' ? 1 : -1));
                    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                        event.preventDefault(); ports.focusSibling(row, event.key === 'ArrowDown' ? 1 : -1);
                    } else if (event.key === 'Enter' || event.key === ' ') {
                        event.preventDefault(); ports.selectSkill(entry.skillKey);
                    }
                });
                list.appendChild(row);
            });
            finishListRender();
        }

        function renderDetail(root) {
            if (!root) return;
            var current = state();
            var focusKey = current.pendingFocusKey || ports.focusKeyOf(document.activeElement);
            clearElement(root);
            if (current.trainerExpired) {
                root.appendChild(renderTrainerExpired());
                ports.restoreFocusKey(focusKey);
                return;
            }
            if (current.schemaError) {
                root.appendChild(ports.empty('技能数据暂时无法读取，请重试。', 'error'));
                return;
            }
            var entry = ports.selectedEntry();
            if (current.view === 'trainer') {
                if (!entry) root.appendChild(ports.empty(current.snapshot ? '从左侧选择研习目标' : '正在读取技能…'));
                else {
                    root.appendChild(renderTrainerSummary(entry));
                    root.appendChild(renderTrainerActions(entry));
                }
            } else {
                root.appendChild(renderManageActions(entry));
                if (current.snapshot) root.appendChild(renderLoadout(false));
                else root.appendChild(ports.empty('正在读取技能…'));
            }
            ports.restoreFocusKey(focusKey);
            if (current.pendingFocusKey && current.coordinatorState === 'idle') ports.clearPendingFocus();
        }

        function renderTrainerSummary(entry) {
            var summary = document.createElement('section'); summary.className = 'skills-trainer-summary';
            summary.appendChild(ports.iconNode(entry.iconKey || entry.skillKey, 'skills-trainer-summary-icon'));
            var copy = document.createElement('div'); copy.className = 'skills-trainer-summary-copy';
            var kicker = document.createElement('span'); kicker.className = 'skills-trainer-kicker'; kicker.textContent = '研习目标';
            var title = document.createElement('h2'); title.textContent = entry.skillKey;
            var meta = document.createElement('div'); meta.className = 'skills-detail-meta';
            meta.textContent = (entry.type || '未知类型') + ' · 当前 Lv.' + ports.safeNumber(entry.currentLevel) + '/'
                + ports.safeNumber(entry.maxLevel) + ' · MP ' + ports.safeNumber(entry.mp)
                + ' · CD ' + ports.cooldownText(entry.cooldownMs);
            copy.appendChild(kicker); copy.appendChild(title); copy.appendChild(meta); summary.appendChild(copy);
            var description = document.createElement('div'); description.className = 'skills-trainer-description';
            var rawDescription = entry.description || '暂无技能说明。';
            if (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.convertAS2Html) {
                description.innerHTML = PanelTooltip.convertAS2Html(ports.normalizeAS2Description(rawDescription));
            } else description.textContent = rawDescription;
            summary.appendChild(description);
            if (entry.writeBlocked || entry.stateHealth !== 'ok') {
                var warning = document.createElement('div'); warning.className = 'skills-corrupt-warning';
                var warningText = document.createElement('span'); warningText.textContent = '技能数据异常，暂时无法研习。';
                var diagnostic = ports.button('复制诊断信息', 'skills-inline-diagnostic skills-diagnostic-btn', function() {
                    ports.copyDiagnostic('skill_data_error', entry);
                });
                warning.appendChild(warningText); warning.appendChild(diagnostic); summary.appendChild(warning);
            }
            ports.bindSkillTooltip(summary, entry);
            return summary;
        }

        function renderTrainerExpired() {
            var expired = document.createElement('section'); expired.className = 'skills-trainer-expired';
            var marker = document.createElement('div'); marker.className = 'skills-trainer-expired-mark'; marker.textContent = '!';
            var title = document.createElement('h2'); title.textContent = '教师连接已失效';
            var message = document.createElement('p');
            message.textContent = '本次研习权限已经结束。为避免误操作，页面已停止计算和研习；请返回游戏后重新与教师对话。';
            var hint = document.createElement('small'); hint.textContent = '已选择的技能和筛选仍保留在当前画面中，未扣除技能点。';
            var actions = document.createElement('div'); actions.className = 'skills-trainer-expired-actions';
            var diagnostic = ports.button('复制诊断信息', 'skills-action-btn skills-close-allowed', function() {
                ports.copyDiagnostic('trainer_session_expired', ports.selectedEntry());
            });
            var close = ports.button('返回游戏并重新对话', 'skills-action-btn primary skills-close-allowed', ports.requestClose);
            close.setAttribute('data-focus-key', 'trainer:expired-close');
            actions.appendChild(diagnostic); actions.appendChild(close);
            expired.appendChild(marker); expired.appendChild(title); expired.appendChild(message);
            expired.appendChild(hint); expired.appendChild(actions);
            return expired;
        }

        function renderSelectionContext(entry, label) {
            var context = document.createElement('div'); context.className = 'skills-selection-context';
            var kicker = document.createElement('span'); kicker.textContent = label || '当前技能';
            var title = document.createElement('b'); title.textContent = entry.skillKey;
            var meta = document.createElement('small'); meta.className = 'skills-detail-meta';
            var level = entry.currentLevel != null ? entry.currentLevel : entry.level;
            meta.textContent = (entry.type || '未知类型') + ' · Lv.' + ports.safeNumber(level) + '/'
                + ports.safeNumber(entry.maxLevel) + ' · MP ' + ports.safeNumber(entry.mp)
                + ' · CD ' + ports.cooldownText(entry.cooldownMs);
            context.appendChild(kicker); context.appendChild(title); context.appendChild(meta);
            if (entry.writeBlocked || entry.stateHealth !== 'ok') {
                var warning = document.createElement('div'); warning.className = 'skills-corrupt-warning';
                var warningText = document.createElement('span'); warningText.textContent = '技能数据异常，暂时无法修改。';
                var diagnostic = ports.button('复制诊断信息', 'skills-inline-diagnostic skills-diagnostic-btn', function(event) {
                    event.stopPropagation(); ports.copyDiagnostic('skill_data_error', entry);
                });
                warning.appendChild(warningText); warning.appendChild(diagnostic); context.appendChild(warning);
            }
            ports.bindSkillTooltip(context, entry);
            return context;
        }

        function renderManageActions(entry) {
            var current = state();
            var actions = document.createElement('section'); actions.className = 'skills-detail-actions';
            if (!entry) {
                var hint = document.createElement('div'); hint.className = 'skills-action-hint';
                hint.textContent = '技能格可拖到快捷栏；快捷槽之间可直接拖动调整按键布局。';
                actions.appendChild(hint);
                return actions;
            }
            actions.appendChild(renderSelectionContext(entry, '已选择'));
            if (entry.passive && !entry.equippable) {
                var passive = ports.button(entry.enabled ? '停用被动' : '启用被动', 'skills-action-btn primary', function() {
                    ports.writeCommand('setPassive', {skillKey:entry.skillKey, enabled:!entry.enabled,
                        expectedRevision:Number(current.snapshot.revision)});
                });
                passive.disabled = ports.writesDisabled(entry);
                passive.setAttribute('data-focus-key', 'action:passive'); actions.appendChild(passive);
            } else {
                var actionHint = document.createElement('div'); actionHint.className = 'skills-action-hint';
                actionHint.textContent = entry.equippable
                    ? '拖到技能格可交换顺序；拖到快捷槽可装备，快捷槽之间可移动或交换。'
                    : '可拖到其他技能格交换顺序；该技能不可装备到快捷栏。';
                actions.appendChild(actionHint);
            }
            return actions;
        }

        function renderTrainerActions(entry) {
            var current = state();
            var desiredLevel = current.desiredLevel;
            var currentLevel = Number(entry.currentLevel || 0), max = Number(entry.maxLevel || 1);
            var section = document.createElement('section'); section.className = 'skills-trainer-actions';
            var matchingPreview = Trainer.previewMatches(current.preview, entry, desiredLevel) ? current.preview : null;
            var target = document.createElement('div'); target.className = 'skills-trainer-target';
            var heading = document.createElement('div'); heading.className = 'skills-trainer-section-heading';
            heading.textContent = currentLevel >= max ? '技能等级' : '目标等级'; target.appendChild(heading);
            var stepper = document.createElement('div'); stepper.className = 'skills-level-stepper';
            var rangeShell = null;
            var label = document.createElement('span');
            label.textContent = currentLevel >= max ? 'Lv.' + currentLevel + '（已满级）' : 'Lv.' + currentLevel + ' →';
            stepper.appendChild(label);
            if (currentLevel >= max) {
                var full = document.createElement('output'); full.textContent = 'Lv.' + max; stepper.appendChild(full);
            } else if (currentLevel <= 0) {
                var fixed = document.createElement('output'); fixed.textContent = 'Lv.1（初学固定）'; stepper.appendChild(fixed);
                ports.setDesiredLevelState(1);
                desiredLevel = 1;
            } else {
                var minus = ports.button('−', 'skills-level-btn', function() {
                    ports.setDesiredLevel(state().desiredLevel - 1);
                });
                var value = document.createElement('input'); value.type = 'number'; value.className = 'skills-level-value';
                value.min = String(currentLevel + 1); value.max = String(max); value.step = '1'; value.value = String(desiredLevel);
                value.inputMode = 'numeric'; value.setAttribute('aria-label', '目标等级');
                value.setAttribute('data-focus-key', 'trainer:level-value'); value.disabled = ports.writesDisabled(entry);
                var plus = ports.button('+', 'skills-level-btn', function() {
                    ports.setDesiredLevel(state().desiredLevel + 1);
                });
                minus.setAttribute('data-focus-key', 'trainer:level-minus');
                plus.setAttribute('data-focus-key', 'trainer:level-plus');
                minus.disabled = ports.writesDisabled(entry) || desiredLevel <= currentLevel + 1;
                plus.disabled = ports.writesDisabled(entry) || desiredLevel >= max;
                stepper.appendChild(minus); stepper.appendChild(value); stepper.appendChild(plus);
                rangeShell = document.createElement('div'); rangeShell.className = 'skills-level-range-shell';
                var range = document.createElement('input'); range.type = 'range'; range.className = 'skills-level-range';
                range.min = String(currentLevel + 1); range.max = String(max); range.step = '1'; range.value = String(desiredLevel);
                range.setAttribute('aria-label', '选择目标等级');
                range.setAttribute('aria-valuetext', '目标等级 ' + desiredLevel);
                range.setAttribute('data-focus-key', 'trainer:level-range'); range.disabled = ports.writesDisabled(entry);
                range.addEventListener('input', function() { ports.stageDesiredLevel(range.value, entry, target); });
                range.addEventListener('change', function() { ports.setDesiredLevel(range.value, true); });
                value.addEventListener('input', function() {
                    var typed = Number(value.value);
                    if (isFinite(typed) && Math.floor(typed) === typed && typed >= currentLevel + 1 && typed <= max) {
                        ports.stageDesiredLevel(typed, entry, target);
                    }
                });
                value.addEventListener('change', function() { ports.setDesiredLevel(value.value, true); });
                value.addEventListener('keydown', function(event) {
                    if (event.key === 'Enter') { event.preventDefault(); ports.setDesiredLevel(value.value, true); }
                    else if (event.key === 'Escape') { event.preventDefault(); value.value = String(state().desiredLevel); }
                });
                rangeShell.appendChild(range);
                var marks = document.createElement('div'); marks.className = 'skills-level-marks';
                Trainer.targetMarkLevels(currentLevel + 1, max).forEach(function(level) {
                    var mark = ports.button(String(level), 'skills-level-mark', function() { ports.setDesiredLevel(level, true); });
                    var position = max === currentLevel + 1 ? 100 : (level - currentLevel - 1) * 100 / (max - currentLevel - 1);
                    mark.style.setProperty('--skills-level-mark-position', position + '%');
                    mark.setAttribute('data-level', String(level)); mark.setAttribute('tabindex', '-1');
                    mark.setAttribute('aria-label', '目标等级 ' + level); mark.disabled = ports.writesDisabled(entry);
                    marks.appendChild(mark);
                });
                rangeShell.appendChild(marks);
            }
            target.appendChild(stepper);
            if (rangeShell) { target.appendChild(rangeShell); syncTargetSelector(target, entry); }
            if (currentLevel > 0 && currentLevel < max) {
                var presets = document.createElement('div'); presets.className = 'skills-target-presets';
                var toMax = ports.button('升至满级', 'skills-target-preset', function() { ports.setDesiredLevel(max, true); });
                toMax.setAttribute('data-focus-key', 'trainer:level-max');
                toMax.disabled = ports.writesDisabled(entry) || desiredLevel === max;
                presets.appendChild(toMax); target.appendChild(presets);
            }
            section.appendChild(target);

            var gate = document.createElement('div'); gate.className = 'skills-trainer-gate';
            if (matchingPreview && !matchingPreview.canCommit && matchingPreview.blockingError) gate.classList.add('blocked');
            gate.textContent = '解锁 Lv.' + ports.safeNumber(entry.unlockLevel) + ' · 初学 '
                + ports.safeNumber(entry.unlockSP) + ' 点 · 升级 ' + ports.safeNumber(entry.upgradeSP) + ' 点/级';
            section.appendChild(gate);

            var result = document.createElement('div'); result.className = 'skills-preview-result skills-cost-card';
            var previousPreview = current.preview && current.preview.skillKey === entry.skillKey ? current.preview : null;
            if (currentLevel >= max) {
                result.classList.add('ok'); appendCostRow(result, '研习状态', '技能已达到最高等级');
            } else if (matchingPreview) {
                appendPreviewSummary(result, matchingPreview, entry, false);
                if (current.previewLoading) {
                    result.classList.add('updating');
                    appendPreviewUpdateStatus(result, '正在刷新 Lv.' + desiredLevel + ' 的权威消耗…', false);
                } else if (current.previewError) {
                    appendPreviewUpdateStatus(result, '消耗刷新失败：' + ports.errorMessage(current.previewError), true);
                    appendPreviewRetry(result, entry);
                }
            } else if (previousPreview) {
                result.classList.add('stale'); appendPreviewSummary(result, previousPreview, entry, true);
                if (current.previewLoading) appendPreviewUpdateStatus(result, '正在更新目标 Lv.' + desiredLevel + ' 的消耗…', false);
                else if (current.previewError) {
                    appendPreviewUpdateStatus(result, 'Lv.' + desiredLevel + ' 更新失败：' + ports.errorMessage(current.previewError), true);
                    appendPreviewRetry(result, entry);
                }
            } else if (current.previewLoading) {
                result.classList.add('loading'); appendCostRow(result, '本次消耗', '正在计算 Lv.' + desiredLevel + '…');
            } else if (current.previewError) {
                result.classList.add('blocked');
                var error = document.createElement('div'); error.className = 'skills-preview-message';
                error.textContent = '暂时无法计算研习消耗：' + ports.errorMessage(current.previewError);
                result.appendChild(error); appendPreviewRetry(result, entry);
            } else appendCostRow(result, '本次消耗', '准备计算…');
            section.appendChild(result);

            var footer = document.createElement('div'); footer.className = 'skills-trainer-footer';
            var commitText = '正在准备研习…', commitEnabled = false;
            if (currentLevel >= max) commitText = '该技能已满级';
            else if (current.previewLoading) commitText = '正在更新 Lv.' + ports.safeNumber(desiredLevel) + ' 的消耗…';
            else if (current.previewError) commitText = '暂时无法研习';
            else if (matchingPreview && matchingPreview.canCommit && matchingPreview.learnToken) {
                commitText = '研习至 Lv.' + ports.safeNumber(desiredLevel) + ' · ' + ports.safeNumber(matchingPreview.cost) + ' 点';
                commitEnabled = !ports.writesDisabled(entry);
            } else if (matchingPreview) commitText = ports.errorMessage(matchingPreview.blockingError);
            var commit = ports.button(commitText, 'skills-action-btn primary skills-trainer-commit', function() {
                ports.prepareLearnConfirmation(entry);
            });
            commit.disabled = !commitEnabled; commit.setAttribute('data-focus-key', 'trainer:commit');
            footer.appendChild(commit); section.appendChild(footer);
            return section;
        }

        function syncTargetSelector(target, entry) {
            if (!target || !entry) return;
            var desiredLevel = state().desiredLevel;
            var currentLevel = Number(entry.currentLevel || 0), max = Number(entry.maxLevel || 1), min = currentLevel + 1;
            var range = target.querySelector('.skills-level-range'), value = target.querySelector('.skills-level-value');
            if (value && document.activeElement !== value) value.value = String(desiredLevel);
            if (range) {
                range.value = String(desiredLevel);
                var progress = max <= min ? 100 : (desiredLevel - min) * 100 / (max - min);
                range.style.setProperty('--skills-level-progress', progress + '%');
                range.setAttribute('aria-valuenow', String(desiredLevel));
                range.setAttribute('aria-valuetext', '目标等级 ' + desiredLevel);
            }
            var marks = target.querySelectorAll('.skills-level-mark');
            for (var i = 0; i < marks.length; i++) {
                marks[i].classList.toggle('selected', Number(marks[i].getAttribute('data-level')) === desiredLevel);
            }
        }

        function appendCostRow(parent, label, value, strong) {
            var row = document.createElement('div'); row.className = 'skills-cost-row';
            var name = document.createElement('span'); name.textContent = label;
            var amount = document.createElement(strong ? 'strong' : 'b'); amount.textContent = value;
            row.appendChild(name); row.appendChild(amount); parent.appendChild(row);
        }

        function appendRequirement(parent, label, passed) {
            var item = document.createElement('span'); item.className = passed ? 'ok' : 'blocked';
            item.textContent = (passed ? '✓ ' : '× ') + label; parent.appendChild(item);
        }

        function appendPreviewSummary(parent, preview, entry, stale) {
            var snapshot = state().snapshot || {};
            var player = snapshot.player || {};
            var skillPoints = Number(player.skillPoints || 0);
            var cost = Number(preview.cost || 0), remaining = skillPoints - cost;
            parent.classList.add(stale ? 'stale' : (preview.canCommit ? 'ok' : 'blocked'));
            appendCostRow(parent, stale ? '上次消耗 · Lv.' + ports.safeNumber(preview.desiredLevel) : '本次消耗',
                ports.safeNumber(cost) + ' 技能点', true);
            appendCostRow(parent, stale ? '上次研习后余额' : '研习后余额', remaining >= 0
                ? ports.safeNumber(skillPoints) + ' → ' + ports.safeNumber(remaining)
                : '还差 ' + ports.safeNumber(-remaining) + ' 技能点');
            if (stale) return;
            var requirements = document.createElement('div'); requirements.className = 'skills-trainer-requirements';
            appendRequirement(requirements, '等级要求 Lv.' + ports.safeNumber(entry.unlockLevel),
                Number(player.level) >= Number(entry.unlockLevel));
            appendRequirement(requirements, '教师可教', true);
            appendRequirement(requirements, '技能点充足', skillPoints >= cost);
            parent.appendChild(requirements);
            if (!preview.canCommit) {
                var blocked = document.createElement('div'); blocked.className = 'skills-preview-message';
                blocked.textContent = ports.errorMessage(preview.blockingError); parent.appendChild(blocked);
            }
        }

        function appendPreviewUpdateStatus(parent, message, failed) {
            var status = document.createElement('div');
            status.className = 'skills-preview-update-status' + (failed ? ' error' : '');
            status.textContent = message; parent.appendChild(status);
        }

        function appendPreviewRetry(parent, entry) {
            var retry = ports.button('重新计算', 'skills-action-btn skills-preview-retry', function() {
                ports.scheduleLearnPreview(entry, true);
            });
            retry.disabled = ports.writesDisabled(entry);
            retry.setAttribute('data-focus-key', 'trainer:preview-retry');
            parent.appendChild(retry);
        }

        function renderLoadout(readOnly) {
            var current = state();
            var section = document.createElement('section'); section.className = 'skills-loadout-section';
            var heading = document.createElement('div'); heading.className = 'skills-section-title';
            heading.textContent = readOnly ? '当前快捷栏' : '快捷技能'; section.appendChild(heading);
            var grid = document.createElement('div'); grid.className = 'skills-loadout-grid';
            var slots = current.snapshot && current.snapshot.loadout || [];
            slots.forEach(function(slot) {
                var card = document.createElement('div'); card.className = 'skills-slot';
                card.setAttribute('data-slot', String(slot.slot));
                card.setAttribute('data-state-health', slot.stateHealth || 'invalid');
                if (!slot.skillKey) card.classList.add('empty');
                if (!readOnly && slot.skillKey && slot.stateHealth === 'ok' && !slot.writeBlocked) card.classList.add('movable');
                if (slot.skillKey && slot.skillKey === current.selectedKey) card.classList.add('selected');
                if (slot.writeBlocked || slot.stateHealth === 'duplicate') card.classList.add('corrupt');
                var main = ports.button('', 'skills-slot-main', function() { ports.onSlotClick(slot, readOnly); });
                main.setAttribute('data-focus-key', 'slot:' + slot.slot);
                main.title = '槽位 ' + slot.slot + ' · ' + (slot.keyLabel || '无按键') + ' · ' + (slot.skillKey || '空槽')
                    + (!readOnly && slot.skillKey && slot.stateHealth === 'ok' ? ' · 可拖动调整，Alt+←/→ 与相邻槽交换' : '');
                var number = document.createElement('span'); number.className = 'skills-slot-number'; number.textContent = String(slot.slot);
                var key = document.createElement('span'); key.className = 'skills-slot-key'; key.textContent = slot.keyLabel || '';
                var icon = ports.iconNode(slot.iconKey, 'skills-slot-icon');
                var level = document.createElement('span'); level.className = 'skills-slot-level';
                level.textContent = slot.skillKey && Number(slot.level) > 0 ? 'Lv.' + String(slot.level) : '';
                var name = document.createElement('span'); name.className = 'skills-slot-name'; name.textContent = slot.skillKey || '空槽';
                main.appendChild(number); main.appendChild(key); main.appendChild(icon); main.appendChild(level); main.appendChild(name);
                main.setAttribute('aria-label', '槽位 ' + slot.slot + '，按键 ' + (slot.keyLabel || '未设置') + '，'
                    + (slot.skillKey || '空槽') + (!readOnly && slot.skillKey && slot.stateHealth === 'ok'
                        ? '；可拖动调整，Alt 加左右方向键与相邻槽交换' : ''));
                main.disabled = !readOnly && (current.writeBlocked || slot.writeBlocked);
                if (!readOnly) main.addEventListener('keydown', function(event) { ports.onSlotKeyDown(event, slot); });
                card.appendChild(main);
                if (!readOnly && slot.skillKey) {
                    var clear = ports.button('×', 'skills-slot-clear', function(event) {
                        event.stopPropagation(); ports.proposeUnequip(slot);
                    });
                    clear.setAttribute('aria-label', '卸载槽位 ' + slot.slot + ' 的 ' + slot.skillKey);
                    clear.disabled = current.writeBlocked || slot.writeBlocked; card.appendChild(clear);
                }
                if (slot.skillKey) ports.bindSkillTooltip(card, ports.entryByKey(slot.skillKey), slot);
                grid.appendChild(card);
            });
            section.appendChild(grid);
            return section;
        }

        function buildSkillTooltipHtml(entry) {
            if (!entry) return '';
            var level = entry.currentLevel != null ? entry.currentLevel : entry.level;
            var meta = (entry.type || '未知类型') + ' · Lv.' + ports.safeNumber(level) + '/'
                + ports.safeNumber(entry.maxLevel) + ' · MP ' + ports.safeNumber(entry.mp)
                + ' · CD ' + ports.cooldownText(entry.cooldownMs);
            var intro = '<div class="skills-tt-title"><b>' + ports.escapeHtml(entry.skillKey || '未知技能') + '</b></div>'
                + '<div class="skills-tt-meta">' + ports.escapeHtml(meta) + '</div>'
                + '<div class="skills-tt-state">' + ports.escapeHtml(ports.healthLabel(entry)) + '</div>';
            return PanelTooltip.buildItemRichHtml({
                iconHtml:PanelTooltip.dynamicIconHtml(entry.iconKey || entry.skillKey, 'skills-tt-icon'),
                introWebHTML:intro,
                descHTML:ports.normalizeAS2Description(entry.description || '暂无技能说明。'),
                rootClass:'skills-tooltip', layoutType:'wide', splitMode:'auto'
            });
        }

        return {
            renderList:renderList,
            renderDetail:renderDetail,
            renderLoadout:renderLoadout,
            syncTargetSelector:syncTargetSelector,
            buildSkillTooltipHtml:buildSkillTooltipHtml
        };
    }

    return {create:create};
});
