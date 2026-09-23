/** AS2-owned gym catalog and Host-owned active training clock. */
(function() {
    'use strict';

    var STATIONS = {
        dummy: { label:'木人桩', action:'木人桩训练' },
        dumbbell: { label:'哑铃', action:'哑铃训练' },
        squat: { label:'深蹲杠铃', action:'深蹲训练' }
    };
    var EQUIPMENT_SLOTS = {
        '头部装备':true,'上装装备':true,'下装装备':true,'手部装备':true,'脚部装备':true,
        '颈部装备':true,'长枪':true,'手枪':true,'手枪2':true,'刀':true,'手雷':true
    };
    var MAX_SAFE_INTEGER = 9007199254740991;
    var PANEL_ID = 'gym';
    var shell = null;
    var root = null;
    var panelInstanceId = '';
    var panelScale = null;
    var motionHandle = null;
    var motionPlaceholder = null;
    var keyHandler = null;
    var snapshot = null;
    var projectNodes = [];
    var selectedIndex = 0;
    var closePending = false;
    var motionGeneration = 0;
    var callSequence = 0;
    var pendingCall = null;
    var session = null;
    var progressNode = null;
    var startButton = null;
    var noticeNode = null;
    var balanceNodes = null;
    var responseHandler = null;
    var eventHandler = null;
    var debugState = { stationId:'', selectedProjectId:'', motionMounted:false };

    function isRecord(value) {
        return !!value && typeof value === 'object' && !Array.isArray(value);
    }

    function hasExactKeys(value, expected) {
        if (!isRecord(value)) return false;
        var actual = Object.keys(value).sort();
        var keys = expected.slice().sort();
        if (actual.length !== keys.length) return false;
        for (var i = 0; i < keys.length; i++) {
            if (actual[i] !== keys[i]) return false;
        }
        return true;
    }

    function readText(value, maxLength, allowEmpty) {
        if (typeof value !== 'string' || value.length > maxLength) return null;
        if (!allowEmpty && !value.trim()) return null;
        if (/[\u0000-\u001f\u007f]/.test(value)) return null;
        return value;
    }

    function readCount(value, allowNull, minimum, maximum) {
        if (allowNull && value === null) return null;
        minimum = minimum == null ? 0 : minimum;
        maximum = maximum == null ? MAX_SAFE_INTEGER : maximum;
        if (typeof value !== 'number' || !Number.isSafeInteger(value)
                || value < minimum || value > maximum) return undefined;
        return value;
    }

    function normalizePortrait(value) {
        if (!hasExactKeys(value, ['gender','equipment','hair','face'])) return null;
        var gender = readText(value.gender, 6, false);
        var hair = readText(value.hair, 160, true);
        var face = readText(value.face, 160, true);
        if ((gender !== 'male' && gender !== 'female') || hair === null || face === null
                || !isRecord(value.equipment) || Object.keys(value.equipment).length > 11) return null;

        var equipment = {};
        var slots = Object.keys(value.equipment);
        for (var i = 0; i < slots.length; i++) {
            var slot = readText(slots[i], 48, false);
            var item = readText(value.equipment[slots[i]], 160, false);
            if (slot === null || !EQUIPMENT_SLOTS[slot] || item === null) return null;
            equipment[slot] = item;
        }
        return { gender:gender, equipment:equipment, hair:hair, face:face };
    }

    function normalizeProject(value, stationId, seenIds, seenIndexes) {
        var keys = ['id','index','rewardLabel','rewardAmount','currency','cost','durationMs','current','cap',
            'baseExperience','capExperience'];
        if (!hasExactKeys(value, keys)) return null;
        var id = readText(value.id, 32, false);
        var index = readCount(value.index, false, 0, 12);
        var rewardLabel = readText(value.rewardLabel, 32, false);
        var rewardAmount = readCount(value.rewardAmount, false, 1, MAX_SAFE_INTEGER);
        var currency = value.currency;
        var cost = readCount(value.cost, false, 1, MAX_SAFE_INTEGER);
        var durationMs = readCount(value.durationMs, false, 1, 3600000);
        var current = readCount(value.current, false, 0, MAX_SAFE_INTEGER);
        var cap = readCount(value.cap, true, 1, MAX_SAFE_INTEGER);
        var baseExperience = readCount(value.baseExperience, false, 0, 1000000);
        var capExperience = readCount(value.capExperience, false, 0, 1000000);
        if (id === null || index === undefined || id !== stationId + '.' + index || rewardLabel === null
                || rewardAmount === undefined || (currency !== 'money' && currency !== 'kpoint')
                || cost === undefined || durationMs === undefined || current === undefined || cap === undefined
                || baseExperience === undefined || capExperience === undefined
                || (cap === null && (baseExperience !== 0 || capExperience !== 0))
                || (cap !== null && (baseExperience !== 10000 || capExperience !== 50000))
                || seenIds[id] || seenIndexes[index]) return null;
        seenIds[id] = true;
        seenIndexes[index] = true;
        return {
            id:id,
            index:index,
            rewardLabel:rewardLabel,
            rewardAmount:rewardAmount,
            currency:currency,
            cost:cost,
            durationMs:durationMs,
            current:current,
            cap:cap,
            baseExperience:baseExperience,
            capExperience:capExperience
        };
    }

    function normalizeOpenData(data) {
        if (!hasExactKeys(data, ['mode','source','stationId','snapshot','panelInstanceId'])
                || data.mode !== 'preview' || data.source !== 'world_gym'
                || typeof data.stationId !== 'string'
                || !Object.prototype.hasOwnProperty.call(STATIONS, data.stationId)) return null;
        var instance = readText(data.panelInstanceId, 160, false);
        var input = data.snapshot;
        if (instance === null || !hasExactKeys(input, ['v','stationId','openToken','pendingSession',
                'balances','portrait','projects'])
                || input.v !== 2 || input.stationId !== data.stationId
                || !/^gym\.open\.[A-Za-z0-9._~-]{1,119}$/.test(input.openToken)
                || !hasExactKeys(input.balances, ['money','kpoint'])) return null;

        var money = readCount(input.balances.money, false, 0, MAX_SAFE_INTEGER);
        var kpoint = readCount(input.balances.kpoint, false, 0, MAX_SAFE_INTEGER);
        var portrait = normalizePortrait(input.portrait);
        if (money === undefined || kpoint === undefined || !portrait
                || !Array.isArray(input.projects) || input.projects.length < 1 || input.projects.length > 13) return null;

        var seenIds = Object.create(null);
        var seenIndexes = Object.create(null);
        var projects = [];
        for (var i = 0; i < input.projects.length; i++) {
            var project = normalizeProject(input.projects[i], data.stationId, seenIds, seenIndexes);
            if (!project) return null;
            projects.push(project);
        }
        projects.sort(function(a, b) { return a.index - b.index; });
        var pendingSession = null;
        if (input.pendingSession !== null) {
            var pending = input.pendingSession;
            if (!hasExactKeys(pending, ['sessionToken','stationId','projectId','phase'])
                    || !/^gym\.session\.[A-Za-z0-9._~-]{1,116}$/.test(pending.sessionToken)
                    || pending.stationId !== data.stationId
                    || pending.phase !== 'save_pending'
                    || !projects.some(function(project) { return project.id === pending.projectId; })) return null;
            pendingSession = {
                sessionToken:pending.sessionToken,
                stationId:pending.stationId,
                projectId:pending.projectId,
                phase:'save_pending'
            };
        }
        return {
            panelInstanceId:instance,
            stationId:data.stationId,
            station:STATIONS[data.stationId],
            snapshot:{
                v:2,
                stationId:data.stationId,
                openToken:input.openToken,
                pendingSession:pendingSession,
                balances:{ money:money, kpoint:kpoint },
                portrait:portrait,
                projects:projects
            }
        };
    }

    function element(tag, className, text) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (text != null) node.textContent = String(text);
        return node;
    }

    function slotView(key, node) {
        return {
            instanceKey:key,
            viewKind:'gym',
            mount:function(host) { host.appendChild(node); },
            unmount:function() { if (node.parentNode) node.parentNode.removeChild(node); }
        };
    }

    function formatCount(value) {
        try { return new Intl.NumberFormat('zh-CN').format(value); }
        catch (_) { return String(value); }
    }

    function currencyLabel(currency) {
        return currency === 'kpoint' ? 'K 点' : '金币';
    }

    function durationLabel(durationMs) {
        if (durationMs < 1000) return durationMs + ' 毫秒';
        var seconds = durationMs / 1000;
        return (Number.isInteger(seconds) ? String(seconds) : seconds.toFixed(1)) + ' 秒';
    }

    function projectAccessibleLabel(project) {
        return project.rewardLabel + ' +' + formatCount(project.rewardAmount)
            + '，' + currencyLabel(project.currency) + ' ' + formatCount(project.cost)
            + '，' + durationLabel(project.durationMs);
    }

    function selectedProject() {
        return snapshot.projects[selectedIndex] || null;
    }

    function findProject(projectId) {
        if (!snapshot) return null;
        for (var i = 0; i < snapshot.projects.length; i++) {
            if (snapshot.projects[i].id === projectId) return snapshot.projects[i];
        }
        return null;
    }

    function canAfford(project) {
        return !!project && snapshot.balances[project.currency] >= project.cost;
    }

    function updateShellStatus() {
        if (!shell) return;
        if (pendingCall) {
            shell.setStatus('正在确认', 'loading');
            return;
        }
        var phase = session && session.phase;
        if (phase === 'running') shell.setStatus(session.paused ? '计时已暂停' : '训练中', 'ready');
        else if (phase === 'settling') shell.setStatus('正在结算', 'pending');
        else if (phase === 'save_pending') shell.setStatus('等待保存', 'warning');
        else if (phase === 'needs_reconcile') shell.setStatus('结果待核实', 'warning');
        else if (phase === 'outcome_unavailable') shell.setStatus('请重新打开', 'error');
        else if (phase === 'applied') shell.setStatus('训练完成', 'ready');
        else if (selectedProject() && !canAfford(selectedProject()))
            shell.setStatus('余额不足', 'warning');
        else shell.setStatus('', 'idle');
    }

    function expectedOutcome(project) {
        if (project.cap === null) return '完成后技能点 +' + formatCount(project.rewardAmount);
        var remaining = Math.max(0, project.cap - project.current);
        if (remaining === 0) return '已达属性上限；完成后转为经验 +'
            + formatCount(project.baseExperience + project.capExperience);
        return '完成后永久加成 +' + formatCount(Math.min(project.rewardAmount, remaining))
            + '，经验 +' + formatCount(project.baseExperience);
    }

    function updateStartButton() {
        if (!startButton) return;
        var project = selectedProject();
        var state = session && session.phase;
        if (pendingCall || closePending) {
            startButton.disabled = true;
            startButton.textContent = '正在确认…';
        } else if (state === 'running' || state === 'settling') {
            startButton.disabled = true;
            startButton.textContent = '训练进行中';
        } else if (state === 'needs_reconcile') {
            startButton.disabled = false;
            startButton.textContent = '核实结算';
        } else if (state === 'save_pending') {
            startButton.disabled = false;
            startButton.textContent = '重试保存';
        } else if (state === 'outcome_unavailable') {
            startButton.disabled = true;
            startButton.textContent = '请重新打开核对';
        } else {
            startButton.disabled = !canAfford(project);
            startButton.textContent = canAfford(project) ? '开始训练' : '余额不足';
        }
        updateShellStatus();
    }

    function setNotice(message, kind) {
        if (!noticeNode) return;
        noticeNode.textContent = message || '';
        noticeNode.dataset.kind = kind || 'info';
        noticeNode.hidden = !message;
    }

    function renderDetails(detail) {
        var project = selectedProject();
        detail.replaceChildren();
        if (!project) {
            detail.appendChild(element('p', 'gym-empty-detail', '该器材当前没有可展示的训练项目。'));
            debugState.selectedProjectId = '';
            if (shell) shell.setStatus('暂无训练项目', 'warning');
            return;
        }
        var heading = element('h3', 'gym-detail-title', project.rewardLabel);
        var reward = element('p', 'gym-detail-reward', expectedOutcome(project));
        var cost = element('p', 'gym-detail-cost', currencyLabel(project.currency) + ' ' + formatCount(project.cost));
        var duration = element('p', 'gym-detail-duration', '训练时长 ' + durationLabel(project.durationMs));
        var pendingSave = !!snapshot.pendingSession || session && session.phase === 'save_pending';
        var currentText = project.cap === null
            ? (pendingSave ? '当前技能点（含待保存结果） ' : '当前可用技能点 ')
                + formatCount(project.current) + ' · 无上限，可继续训练'
            : (pendingSave ? '当前加成（含待保存结果） ' : '已练得永久加成 ')
                + formatCount(project.current);
        if (project.cap !== null) {
            currentText += ' / 上限 ' + formatCount(project.cap)
                + ' · 可再增加 ' + formatCount(Math.max(0, project.cap - project.current));
            if (project.current > project.cap) currentText += ' · 历史数值高于上限';
            else if (project.current === project.cap) currentText += ' · 可继续练经验';
            else currentText += ' · 可继续练属性';
        }
        if (!canAfford(project)) currentText += ' · 当前余额不足';
        var current = element('p', 'gym-detail-current', currentText);
        detail.append(heading, reward, cost, duration, current);
        debugState.selectedProjectId = project.id;
        updateStartButton();
    }

    function formatSeconds(ms) {
        return (Math.round(ms / 100) / 10).toFixed(1);
    }

    function renderProgress() {
        if (!progressNode) return;
        var status = progressNode.querySelector('.gym-progress-status');
        var amount = progressNode.querySelector('.gym-progress-amount');
        var bar = progressNode.querySelector('.gym-progress-bar');
        var project = session && findProject(session.projectId) || selectedProject();
        if (!session || session.phase === 'preview' || session.phase === 'cancelled') {
            status.textContent = '尚未开始训练';
            amount.textContent = project ? '选择项目后开始；完成时一次结算。' : '';
            bar.value = 0;
            bar.max = 100;
            return;
        }
        var duration = Number.isSafeInteger(session.durationMs) ? session.durationMs
            : project && project.durationMs || 0;
        var elapsed = Number.isSafeInteger(session.elapsedMs)
            ? Math.max(0, Math.min(duration, session.elapsedMs)) : 0;
        var remaining = Math.max(0, duration - elapsed);
        var percent = duration > 0 ? Math.floor(elapsed * 100 / duration) : 0;
        bar.value = percent;
        bar.max = 100;
        if (session.phase === 'running') {
            status.textContent = '已进行 ' + formatSeconds(elapsed) + ' / ' + formatSeconds(duration)
                + ' 秒 · ' + percent + '% · 剩余 ' + formatSeconds(remaining) + ' 秒'
                + (session.paused ? ' · 已暂停计时' : '');
            amount.textContent = '本次收益待完成 · ' + (project ? expectedOutcome(project) : '完成后结算。');
        } else if (session.phase === 'settling') {
            status.textContent = '训练时间已到，等待结算';
            amount.textContent = '本次收益待确认；正在核实奖励与扣费。';
        } else if (session.phase === 'needs_reconcile') {
            status.textContent = '结算结果待核实';
            amount.textContent = '请核实本次结果；不会重复提交训练。';
        } else if (session.phase === 'save_pending') {
            status.textContent = '奖励已应用，正在等待保存';
            amount.textContent = '只会重试保存，不会再次扣费或发奖。';
        } else if (session.phase === 'outcome_unavailable') {
            status.textContent = '无法核实旧训练结果';
            amount.textContent = '请关闭后重新打开，核对余额和永久加成。';
        } else if (session.phase === 'applied') {
            status.textContent = '训练完成 · 已结算并保存';
            var award = session.award;
            if (award && award.kind === 'stat') {
                amount.textContent = '本次永久加成 +' + formatCount(award.amount)
                    + '，经验 +' + formatCount(award.baseExperience || 0);
            } else if (award && award.kind === 'experience') {
                amount.textContent = '属性已达上限，本次经验 +'
                    + formatCount((award.amount || 0) + (award.baseExperience || 0));
            } else if (award && award.kind === 'skillPoints') {
                amount.textContent = '本次技能点 +' + formatCount(award.amount);
            } else amount.textContent = '本次收益已由游戏确认。';
        } else {
            status.textContent = '训练状态待核实';
            amount.textContent = '当前不显示未确认的奖励。';
        }
    }

    function requestGym(cmd, payload, extra) {
        if (pendingCall || closePending || !panelInstanceId || !Bridge || !Bridge.send) return false;
        var callId = 'gym.web.' + Date.now().toString(36) + '.' + (++callSequence);
        pendingCall = {cmd:cmd, callId:callId, extra:extra || null};
        var sent = false;
        try {
            sent = Bridge.send({
                type:'panel', panel:PANEL_ID, domain:'gym', cmd:cmd,
                panelInstanceId:panelInstanceId, callId:callId, payload:payload || {v:1}
            }) !== false;
        } catch (error) {
            console.error('[GymPanel] request failed:', error);
        }
        if (!sent) {
            pendingCall = null;
            setNotice('请求未送达，请重试。', 'error');
        }
        updateStartButton();
        return sent;
    }

    function updateBalances(value) {
        if (!hasExactKeys(value, ['money','kpoint'])) return;
        var money = readCount(value.money, false, 0, MAX_SAFE_INTEGER);
        var kpoint = readCount(value.kpoint, false, 0, MAX_SAFE_INTEGER);
        if (money === undefined || kpoint === undefined) return;
        snapshot.balances.money = money;
        snapshot.balances.kpoint = kpoint;
        if (balanceNodes) {
            balanceNodes.money.textContent = formatCount(money);
            balanceNodes.kpoint.textContent = formatCount(kpoint);
        }
        updateStartButton();
    }

    function adoptSession(data) {
        var token = readText(data.sessionToken, 128, false);
        var projectId = readText(data.projectId, 32, false);
        var project = findProject(projectId);
        if (!token || !project) return false;
        if (session && session.sessionToken && session.sessionToken !== token
                && session.phase !== 'preview' && session.phase !== 'cancelled'
                && session.phase !== 'applied') return false;
        var duration = readCount(data.durationMs, false, 1, 3600000);
        var elapsed = readCount(data.elapsedMs, false, 0, 3600000);
        if (duration === undefined) return false;
        session = {
            sessionToken:token, projectId:projectId, phase:data.phase,
            durationMs:duration, elapsedMs:elapsed === undefined ? 0 : elapsed,
            paused:data.paused === true, award:data.award || null
        };
        renderProgress();
        updateStartButton();
        return true;
    }

    function applySettled(data) {
        if (!data || !session || data.sessionToken !== session.sessionToken) return false;
        if (data.queryRequired === true) {
            session.phase = 'needs_reconcile';
            setNotice('请先核实上次结算，再决定是否重试保存。', 'warning');
        } else if (data.phase === 'needs_reconcile') {
            session.phase = 'needs_reconcile';
            setNotice('结算回执不确定，请核实本次结果。', 'warning');
        } else if (data.phase === 'save_pending') {
            session.phase = 'save_pending';
            setNotice('奖励已应用但尚未保存；请重试保存，退出游戏可能丢失本次结果。', 'warning');
            renderDetails(root.querySelector('.gym-project-detail'));
        } else if (data.phase === 'outcome_unavailable') {
            session.phase = 'outcome_unavailable';
            setNotice('无法核实旧训练，请关闭后重新打开核对余额与属性。', 'warning');
        } else if (data.phase === 'applied' && data.saved === true) {
            session.phase = 'applied';
            snapshot.pendingSession = null;
            session.award = data.award || null;
            updateBalances(data.balances);
            var project = findProject(session.projectId);
            var current = readCount(data.current, false, 0, MAX_SAFE_INTEGER);
            if (project && current !== undefined) {
                snapshot.projects.forEach(function(item) {
                    if (item.rewardLabel === project.rewardLabel) item.current = current;
                });
                renderDetails(root.querySelector('.gym-project-detail'));
            }
            setNotice('', 'success');
        } else if (data.phase === 'cancelled') {
            session = null;
            snapshot.pendingSession = null;
            setNotice('本次训练未结算：' + (data.error ? errorLabel(data.error)
                : '已取消；没有扣费或奖励'), 'warning');
        } else if (data.success === false) {
            session = null;
            setNotice('本次训练未结算：' + errorLabel(data.error), 'error');
        } else return false;
        renderProgress();
        updateStartButton();
        return true;
    }

    function errorLabel(code) {
        var labels = {
            insufficient_funds:'余额不足', stale_state:'角色或训练资料已变化',
            context_changed:'角色或存档已切换', catalog_unavailable:'训练目录暂不可用',
            save_unavailable:'存档暂不可用', disconnected:'连接中断',
            panel_instance_expired:'面板已过期', reconcile_required:'需要先核实上次结算',
            busy:'正在处理上一项操作'
        };
        return labels[code] || '请稍后重试或重新打开面板';
    }

    function handleResponse(data) {
        if (!data || data.type !== 'panel_resp' || data.panel !== PANEL_ID
                || data.domain !== 'gym' || data.panelInstanceId !== panelInstanceId
                || !pendingCall || data.callId !== pendingCall.callId
                || data.cmd !== pendingCall.cmd) return;
        var call = pendingCall;
        pendingCall = null;
        if (call.cmd === 'start') {
            if (data.success === true && data.phase === 'running'
                    && data.projectId === call.extra && adoptSession(data)) {
                setNotice('', 'info');
            } else setNotice('训练未开始：' + errorLabel(data.error), 'error');
        } else if (call.cmd === 'cancel') {
            if (data.success === true && data.phase === 'cancelled') {
                session = null;
                selectedIndex = call.extra;
                projectNodes.forEach(function(node, index) {
                    node.setAttribute('aria-checked', String(index === selectedIndex));
                    node.tabIndex = index === selectedIndex ? 0 : -1;
                });
                renderDetails(root.querySelector('.gym-project-detail'));
                setNotice('', 'info');
            } else {
                setNotice('切换尚未确认：' + errorLabel(data.error), 'warning');
            }
        } else if (call.cmd === 'status') {
            if (data.phase === 'preview' || data.phase === 'cancelled') {
                if (snapshot.pendingSession) {
                    session.phase = 'needs_reconcile';
                    setNotice('上次训练仍待核实，当前面板不会开始新的训练。', 'warning');
                } else session = null;
            }
            else if (data.phase === 'running' || data.phase === 'settling'
                    || data.phase === 'save_pending' || data.phase === 'needs_reconcile'
                    || data.phase === 'outcome_unavailable'
                    || data.phase === 'applied') {
                if (adoptSession(data) && data.phase !== 'running') applySettled(data);
            }
        } else if (call.cmd === 'query' || call.cmd === 'retrySave') {
            if (!applySettled(data)) setNotice('尚未取得可核实的结算结果。', 'warning');
        }
        renderProgress();
        updateStartButton();
    }

    function handleEvent(data) {
        if (!data || data.type !== 'panel_event' || data.panel !== PANEL_ID
                || data.domain !== 'gym' || data.panelInstanceId !== panelInstanceId
                || !session || data.sessionToken !== session.sessionToken) return;
        if (data.event === 'progress' && (session.phase === 'running'
                || data.phase === 'settling')) {
            var elapsed = readCount(data.elapsedMs, false, 0, session.durationMs);
            if (elapsed === undefined) return;
            session.elapsedMs = elapsed;
            session.paused = data.paused === true;
            if (data.phase === 'settling') session.phase = 'settling';
            renderProgress();
            updateStartButton();
        } else if (data.event === 'settled') applySettled(data);
    }

    function onStartClick() {
        if (session && session.phase === 'needs_reconcile') {
            requestGym('query', {v:1});
            return;
        }
        if (session && session.phase === 'save_pending') {
            requestGym('retrySave', {v:1});
            return;
        }
        var project = selectedProject();
        if (!project || !canAfford(project) || session && session.phase === 'running') return;
        requestGym('start', {v:1, projectId:project.id}, project.id);
    }

    function selectProject(index, focus) {
        if (!snapshot || index < 0 || index >= snapshot.projects.length) return false;
        if (pendingCall && pendingCall.cmd === 'start') {
            setNotice('正在确认训练开始，请稍候切换。', 'info');
            return false;
        }
        if (session && (session.phase === 'settling' || session.phase === 'needs_reconcile'
                || session.phase === 'save_pending' || session.phase === 'outcome_unavailable')) {
            setNotice('本次结算尚未确认，请先核实或保存。', 'warning');
            return false;
        }
        if (session && session.phase === 'running' && index !== selectedIndex) {
            return requestGym('cancel', {v:1}, index);
        }
        selectedIndex = index;
        projectNodes.forEach(function(node, itemIndex) {
            var selected = itemIndex === selectedIndex;
            node.setAttribute('aria-checked', String(selected));
            node.tabIndex = selected ? 0 : -1;
        });
        renderDetails(root.querySelector('.gym-project-detail'));
        renderProgress();
        if (focus && projectNodes[selectedIndex]) projectNodes[selectedIndex].focus();
        return true;
    }

    function moveSelection(event, index) {
        if (!snapshot.projects.length) return;
        var next = index;
        if (event.key === 'ArrowDown' || event.key === 'ArrowRight') next = (index + 1) % snapshot.projects.length;
        else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') next = (index + snapshot.projects.length - 1) % snapshot.projects.length;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = snapshot.projects.length - 1;
        else return;
        event.preventDefault();
        event.stopPropagation();
        selectProject(next, true);
    }

    function buildProjectList() {
        var list = element('div', 'gym-project-list');
        list.setAttribute('role', 'radiogroup');
        list.setAttribute('aria-label', '可查看的训练项目');
        projectNodes = [];
        snapshot.projects.forEach(function(project, index) {
            var option = element('button', 'gym-project-option');
            option.type = 'button';
            option.setAttribute('role', 'radio');
            option.setAttribute('aria-checked', String(index === selectedIndex));
            option.setAttribute('aria-label', projectAccessibleLabel(project));
            option.dataset.projectId = project.id;
            option.tabIndex = index === selectedIndex ? 0 : -1;

            var name = element('span', 'gym-project-name', project.rewardLabel);
            var summary = element('span', 'gym-project-summary', '+' + formatCount(project.rewardAmount)
                + ' · ' + currencyLabel(project.currency) + ' ' + formatCount(project.cost));
            option.append(name, summary);
            option.addEventListener('click', function() { selectProject(index, false); });
            option.addEventListener('keydown', function(event) { moveSelection(event, index); });
            list.appendChild(option);
            projectNodes.push(option);
        });
        return list;
    }

    function buildBalance(currency, amount) {
        var card = element('div', 'gym-balance-card');
        card.append(element('span', 'gym-balance-label', currencyLabel(currency)));
        card.append(element('strong', 'gym-balance-value', formatCount(amount)));
        return card;
    }

    function mountMotion(stage) {
        var renderer = typeof window !== 'undefined' ? window.GymMotionRenderer : null;
        var generation = ++motionGeneration;
        var stationId = snapshot.stationId;
        var portrait = snapshot.portrait;
        function isCurrent() {
            return generation === motionGeneration && root !== null
                && document.documentElement.contains(stage) && snapshot !== null;
        }
        function fail(message) {
            if (!isCurrent()) return;
            clearMotionOutput(stage);
            debugState.motionMounted = false;
            setMotionFallback(message);
        }
        if (!portrait.hair || !portrait.face) {
            var missing = [];
            if (!portrait.face) missing.push('脸型');
            if (!portrait.hair) missing.push('发型');
            setMotionFallback('当前角色' + missing.join('、') + '资料缺失，暂不显示角色模型。');
            return;
        }
        if (!renderer || typeof renderer.ready !== 'function'
                || typeof renderer.preparePortrait !== 'function'
                || typeof renderer.canRenderPortrait !== 'function'
                || typeof renderer.create !== 'function') {
            setMotionFallback('人物皮肤资源尚未核验，暂不显示角色模型。');
            return;
        }
        setMotionFallback('正在核验人物动作与皮肤资源…');
        Promise.resolve().then(function() { return renderer.ready(); })
            .then(function() { return renderer.preparePortrait(portrait, stationId); })
            .then(function(prepared) {
                if (!isCurrent()) return;
                if (prepared !== true || renderer.canRenderPortrait(portrait, stationId) !== true) {
                    fail('当前角色外观资源不完整，暂不显示人物模型。');
                    return;
                }
                var handle = null;
                handle = renderer.create(stage, {
                    stationId:stationId,
                    portrait:portrait,
                    onFailure:function() {
                        if (!isCurrent()) return;
                        if (motionHandle === handle) motionHandle = null;
                        clearMotionOutput(stage);
                        debugState.motionMounted = false;
                        setMotionFallback('人物动作样片播放失败，已停止显示角色模型。');
                    }
                });
                var hasCanvas = !!stage.querySelector('.gym-motion-canvas');
                if (!handle || typeof handle.destroy !== 'function' || !hasCanvas) {
                    if (handle && typeof handle.destroy === 'function') handle.destroy();
                    fail('人物动作样片未能安全显示，暂不显示角色模型。');
                    return;
                }
                motionHandle = handle;
                if (motionPlaceholder && motionPlaceholder.parentNode) {
                    motionPlaceholder.parentNode.removeChild(motionPlaceholder);
                }
                debugState.motionMounted = true;
            }).catch(function(error) {
                console.error('[GymPanel] motion renderer failed:', error);
                fail('人物动作样片资源加载失败，暂不显示角色模型。');
            });
    }

    function clearMotionOutput(stage) {
        Array.prototype.slice.call(stage.children).forEach(function(child) {
            if (child !== motionPlaceholder) stage.removeChild(child);
        });
    }

    function setMotionFallback(message) {
        var stage = root && root.querySelector('.gym-motion-stage');
        if (stage && motionPlaceholder && !stage.contains(motionPlaceholder)) {
            stage.replaceChildren(motionPlaceholder);
        }
        var copy = motionPlaceholder && motionPlaceholder.querySelector('.gym-motion-message');
        if (copy) copy.textContent = message;
    }

    function requestClose() {
        if (!panelInstanceId || typeof Bridge === 'undefined' || !Bridge || !Bridge.send) return false;
        if (session && (session.phase === 'settling' || session.phase === 'needs_reconcile'
                || session.phase === 'save_pending')) {
            setNotice('本次结算尚未确认，请先核实或保存。', 'warning');
            return false;
        }
        var sent = false;
        try {
            sent = Bridge.send({
                type:'panel',
                cmd:'close',
                panel:PANEL_ID,
                panelInstanceId:panelInstanceId
            }) !== false;
        } catch (error) {
            console.error('[GymPanel] close request failed:', error);
        }
        if (sent) closePending = true;
        return sent;
    }

    function onClose() {
        motionGeneration++;
        if (responseHandler) Bridge.off('panel_resp', responseHandler);
        if (eventHandler) Bridge.off('panel_event', eventHandler);
        responseHandler = null;
        eventHandler = null;
        if (keyHandler && root) root.removeEventListener('keydown', keyHandler);
        keyHandler = null;
        if (motionHandle) {
            try { motionHandle.destroy(); }
            catch (error) { console.error('[GymPanel] motion cleanup failed:', error); }
        }
        motionHandle = null;
        if (panelScale) panelScale.detach();
        panelScale = null;
        if (shell) shell.destroy();
        shell = null;
        if (root) root.replaceChildren();
        root = null;
        panelInstanceId = '';
        snapshot = null;
        projectNodes = [];
        selectedIndex = 0;
        motionPlaceholder = null;
        closePending = false;
        pendingCall = null;
        session = null;
        progressNode = null;
        startButton = null;
        noticeNode = null;
        balanceNodes = null;
        debugState = { stationId:'', selectedProjectId:'', motionMounted:false };
    }

    function create() {
        var host = element('section', 'panel-scale-shell gym-panel-host');
        host.setAttribute('aria-label', '健身训练');
        return host;
    }

    function onOpen(host, data) {
        onClose();
        var normalized = normalizeOpenData(data);
        if (!normalized) return false;
        root = host;
        panelInstanceId = normalized.panelInstanceId;
        snapshot = normalized.snapshot;
        debugState = { stationId:normalized.stationId, selectedProjectId:'', motionMounted:false };
        selectedIndex = 0;
        if (snapshot.pendingSession) {
            for (var index = 0; index < snapshot.projects.length; index++) {
                if (snapshot.projects[index].id === snapshot.pendingSession.projectId) {
                    selectedIndex = index;
                    break;
                }
            }
            session = {
                sessionToken:snapshot.pendingSession.sessionToken,
                projectId:snapshot.pendingSession.projectId,
                phase:'needs_reconcile',
                durationMs:snapshot.projects[selectedIndex].durationMs,
                elapsedMs:snapshot.projects[selectedIndex].durationMs,
                paused:true,
                award:null
            };
        }

        shell = new Workbench.DualPaneShell({
            profile:'stage-focus',
            eyebrow:'基地 · 健身房',
            title:'健身训练',
            subtitle:'训练项目与进度',
            status:'',
            leftLabel:'训练动作',
            rightLabel:'训练项目',
            slotMarkers:false
        });
        var shellRoot = shell.getRoot();
        shellRoot.classList.add('gym-workbench');
        var close = element('button', 'gym-close-button', '关闭');
        close.type = 'button';
        close.setAttribute('aria-label', '关闭健身训练面板');
        close.addEventListener('click', requestClose);
        shell.addHeaderAction(close);

        var scene = element('section', 'gym-scene');
        scene.setAttribute('aria-label', normalized.station.label + '训练动作');
        var sceneToolbar = element('div', 'gym-scene-toolbar');
        sceneToolbar.appendChild(element('strong', 'gym-station-pill', normalized.station.label));
        var motionStage = element('div', 'gym-motion-stage');
        motionStage.setAttribute('role', 'img');
        motionStage.setAttribute('aria-label', normalized.station.action + '画面');
        motionPlaceholder = element('div', 'gym-motion-placeholder');
        motionPlaceholder.append(
            element('strong', 'gym-motion-title', normalized.station.action),
            element('span', 'gym-motion-message', '正在准备动作样片…')
        );
        motionStage.appendChild(motionPlaceholder);
        progressNode = element('div', 'gym-progress');
        progressNode.setAttribute('aria-live', 'polite');
        progressNode.append(
            element('strong', 'gym-progress-status', '尚未开始训练'),
            element('span', 'gym-progress-amount', '完成后才会扣费与结算奖励。')
        );
        var progressBar = element('progress', 'gym-progress-bar');
        progressBar.max = 100;
        progressBar.value = 0;
        progressBar.setAttribute('aria-label', '训练进度');
        progressNode.appendChild(progressBar);
        scene.append(sceneToolbar, motionStage, progressNode);

        var catalog = element('section', 'gym-catalog');
        catalog.setAttribute('aria-label', normalized.station.label + '训练目录');
        noticeNode = element('div', 'gym-preview-note');
        noticeNode.hidden = true;
        var balances = element('div', 'gym-balances');
        var moneyCard = buildBalance('money', snapshot.balances.money);
        var kpointCard = buildBalance('kpoint', snapshot.balances.kpoint);
        balances.append(moneyCard, kpointCard);
        balanceNodes = {
            money:moneyCard.querySelector('.gym-balance-value'),
            kpoint:kpointCard.querySelector('.gym-balance-value')
        };
        var list = buildProjectList();
        var detail = element('section', 'gym-project-detail');
        detail.setAttribute('aria-live', 'polite');
        var actions = element('div', 'gym-preview-actions');
        actions.appendChild(element('span', 'gym-rule-note', '完成才扣费 · 中途退出不计'));
        startButton = element('button', 'gym-start-button', '开始训练');
        startButton.type = 'button';
        startButton.addEventListener('click', onStartClick);
        actions.appendChild(startButton);
        catalog.append(noticeNode, balances, list, detail, actions);

        shell.mountInitial(slotView('gym-motion', scene), slotView('gym-catalog', catalog));
        host.replaceChildren(shellRoot);
        panelScale = PanelScale.attach(host, 1024, 576);
        keyHandler = function(event) {
            if (event.key === 'Escape') {
                event.preventDefault();
                requestClose();
            }
        };
        host.addEventListener('keydown', keyHandler);
        responseHandler = handleResponse;
        eventHandler = handleEvent;
        Bridge.on('panel_resp', responseHandler);
        Bridge.on('panel_event', eventHandler);
        renderDetails(detail);
        renderProgress();
        if (snapshot.pendingSession)
            setNotice('正在恢复上次训练的保存结果；请先核实，不会重复扣费。', 'warning');
        mountMotion(motionStage);
        requestGym('status', {v:1});
        return true;
    }

    Panels.register(PANEL_ID, {
        create:create,
        onOpen:onOpen,
        onRebind:onOpen,
        onClose:onClose,
        onRequestClose:requestClose,
        onForceClose:onClose
    });

    window.GymPanel = {
        normalizeOpenData:normalizeOpenData,
        debugState:function() {
            return {
                stationId:debugState.stationId,
                selectedProjectId:debugState.selectedProjectId,
                motionMounted:debugState.motionMounted,
                closePending:closePending,
                phase:session && session.phase || 'preview',
                sessionToken:session && session.sessionToken || '',
                elapsedMs:session && session.elapsedMs || 0,
                motion:motionHandle && typeof motionHandle.debugState === 'function'
                    ? motionHandle.debugState() : null
            };
        }
    };
})();
