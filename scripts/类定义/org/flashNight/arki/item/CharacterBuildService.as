/**
 * 角色构筑会话、投影与窄原子写服务。
 *
 * Web domain 暴露 snapshot/candidates、四个显式装备/药剂 mutation、flushLive、
 * statsSnapshot/finalize。另有 characterBuildRecoverDetach 仅供 Host 在 Web 文档或
 * socket 丢失后查询并结算 exact orphan authority，不属于 Web 业务命令。服务建立 exact
 * generation，观察 loadout/drug 漂移，投影 11+4 槽与人物信息，并在正常关闭/断线时
 * 守住 captured pause lease。
 */
class org.flashNight.arki.item.CharacterBuildService {
    private static var SLOT_KEYS:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"
    ];
    private static var SLOT_LABELS:Array = [
        "头部", "上装", "下装", "手部", "脚部", "颈部",
        "长枪", "主手手枪", "副手手枪", "刀", "手雷"
    ];
    private static var SLOT_ALLOWLIST:Object = {
        头部装备:true, 上装装备:true, 下装装备:true, 手部装备:true,
        脚部装备:true, 颈部装备:true, 长枪:true, 手枪:true,
        手枪2:true, 刀:true, 手雷:true
    };
    private static var SLOT_DATA_KEYS:Array = [
        "头部装备数据", "上装装备数据", "下装装备数据", "手部装备数据",
        "脚部装备数据", "颈部装备数据", "长枪数据", "手枪数据",
        "手枪2数据", "刀数据", "手雷数据"
    ];
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _testRoot:Object = null;
    private static var _callbacks:Object = null;
    private static var _generationCounter:Number = 0;
    private static var _sessionGeneration:Number = 0;
    private static var _panelInstanceId:String = "";
    private static var _active:Boolean = false;
    private static var _stale:Boolean = false;
    private static var _staleError:String = "";
    private static var _equipmentInventory:Object = null;
    private static var _drugInventory:Object = null;
    private static var _backpackInventory:Object = null;
    private static var _slotRefs:Array = null;
    private static var _signature:String = null;
    private static var _liveSignature:String = null;
    private static var _loadoutRevision:Number = 0;
    private static var _liveRevision:Number = 0;
    private static var _drugRevision:Number = 0;
    // DrugInventory 原始 revision 与领域 revision 分离；clean rollback 只推进前者。
    private static var _drugRawRevision:Number = 0;
    private static var _liveRefreshDirty:Boolean = false;
    private static var _writeInProgress:Boolean = false;
    private static var _writeAuthorityTouched:Boolean = false;
    private static var _capturedPauseLease = undefined;
    // 只有 Host-only exact recoverDetach 成功后才置 true；finalize 不能替代 pause proof。
    private static var _hostPauseReleaseProven:Boolean = false;
    private static var _testFailNextWornPostcondition:Boolean = false;
    // 最近一次成功终态；失败不覆盖，下一次成功 open 使其失效。
    private static var _finalizeReceipt:Object = null;
    private static function root():Object {
        return _testRoot == null ? _root : _testRoot;
    }

    /**
     * 安装角色构筑业务命令与一个 Host-only orphan recovery。
     */
    public static function install():Void {
        if (_inited) return;
        var r:Object = root();
        if (r.gameCommands == undefined) r.gameCommands = {};
        _json = new LiteJSON();
        r.gameCommands["characterBuildSnapshot"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("snapshot", params);
        };
        r.gameCommands["characterBuildCandidates"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("candidates", params);
        };
        r.gameCommands["characterBuildEquipEquipment"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("equipEquipment", params);
        };
        r.gameCommands["characterBuildUnequipEquipment"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("unequipEquipment", params);
        };
        r.gameCommands["characterBuildEquipDrug"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("equipDrug", params);
        };
        r.gameCommands["characterBuildUnequipDrug"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("unequipDrug", params);
        };
        r.gameCommands["characterBuildFlushLive"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("flushLive", params);
        };
        r.gameCommands["characterBuildStatsSnapshot"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("statsSnapshot", params);
        };
        r.gameCommands["characterBuildFinalize"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handle("finalize", params);
        };
        r.gameCommands["characterBuildRecoverDetach"] = function(params) {
            org.flashNight.arki.item.CharacterBuildService.handleRecoverDetach(params);
        };
        _inited = true;
    }

    private static function handle(commandName:String, params:Object):Void {
        var response:Object = execute(commandName, params);
        response.task = "loadout_response";
        sendResponse(response);
    }

    /**
     * Host-only orphan recovery endpoint. Web command normalization never routes here.
     */
    private static function handleRecoverDetach(params:Object):Void {
        var response:Object = recoverDetach(params);
        response.task = "loadout_response";
        sendResponse(response);
    }

    /**
     * 同步生产协议入口，同时供 focused TestLoader 验证 envelope。
     */
    public static function execute(commandName:String, params:Object):Object {
        var result:Object;
        if (params == undefined || Number(params.v) != 1) {
            result = fail("unsupported_version");
        } else if (commandName == "snapshot") {
            result = executeSnapshot(params);
        } else if (commandName == "candidates") {
            result = executeCandidates(params);
        } else if (commandName == "equipEquipment") {
            result = executeMutation(commandName, params);
        } else if (commandName == "unequipEquipment") {
            result = executeMutation(commandName, params);
        } else if (commandName == "equipDrug") {
            result = executeMutation(commandName, params);
        } else if (commandName == "unequipDrug") {
            result = executeMutation(commandName, params);
        } else if (commandName == "flushLive") {
            result = _writeInProgress
                ? fail("write_busy") : executeFlushLive(params);
        } else if (commandName == "statsSnapshot") {
            result = executeStatsSnapshot(params);
        } else if (commandName == "finalize") {
            result = _writeInProgress
                ? fail("write_busy") : executeFinalize(params);
        } else {
            result = fail("unsupported_cmd");
        }
        return commonResponse(commandName, params, result);
    }

    /**
     * Web build 入口的只读 readiness probe。
     *
     * 这里只验证容器、loadout 扫描与 live context；Host 尚未建立的 pause lease
     * 不属于准入前置。不得在这里铸造 generation、建立 session 或捕获 authority。
     */
    public static function canOpenPanel():Boolean {
        var resolved:Object = resolveContainers();
        if (!resolved.success || readRevision(resolved.drugs) < 0) {
            return false;
        }
        var scan:Object = scanLoadout(resolved.equipment);
        if (!scan.success) return false;
        try {
            return liveContext(root(), scan.refs) != null;
        } catch (error) {
            return false;
        }
    }

    /**
     * 建立新的观察基线。重复 open 必须铸造新 generation，旧命令立即失效。
     */
    public static function open():Object {
        var resolved:Object = resolveContainers();
        if (!resolved.success) return rejectOpen(resolved.error);
        var pauseLease = root()._webPanelPauseLease;
        if (pauseLease == undefined || pauseLease == null
                || typeof pauseLease != "string"
                || String(pauseLease) == "") {
            return rejectOpen("pause_lease_missing");
        }
        var drugRevision:Number = readRevision(resolved.drugs);
        if (drugRevision < 0) return rejectOpen("invalid_drug_revision");
        var scan:Object = scanLoadout(resolved.equipment);
        if (!scan.success) return rejectOpen(scan.error);
        var live:Object = null;
        try {
            live = liveContext(root(), scan.refs);
        } catch (liveError) {
            live = null;
        }
        if (live == null) return rejectOpen("live_unavailable");
        _generationCounter++;
        _sessionGeneration = _generationCounter;
        _finalizeReceipt = null;
        _active = true;
        _stale = false;
        _staleError = "";
        _equipmentInventory = resolved.equipment;
        _drugInventory = resolved.drugs;
        _backpackInventory = resolved.backpack;
        _slotRefs = scan.refs;
        _signature = scan.signature;
        _liveSignature = scan.liveSignature;
        var liveAligned:Boolean = liveBaselineAligned(root(), scan.refs);
        _loadoutRevision = liveAligned ? 0 : 1;
        _liveRevision = 0;
        _drugRevision = drugRevision;
        _drugRawRevision = drugRevision;
        _liveRefreshDirty = !liveAligned;
        _capturedPauseLease = pauseLease;
        _hostPauseReleaseProven = false;
        return state(true, false, false);
    }

    /**
     * 只读同步：exact item ref 或装配语义签名变化只推进一次 loadoutRevision。
     * DrugInventory 只采用自身单调 revision，不参与 live dirty。
     */
    public static function synchronize(expectedGeneration:Number):Object {
        var gate:Object = sessionGate(expectedGeneration);
        if (!gate.success) return gate;
        var resolved:Object = resolveContainers();
        if (!resolved.success) return poison("stale_container");
        if (resolved.equipment !== _equipmentInventory
                || resolved.drugs !== _drugInventory
                || resolved.backpack !== _backpackInventory) {
            return poison("stale_container");
        }
        var currentDrugRevision:Number = readRevision(_drugInventory);
        if (currentDrugRevision < 0) return poison("invalid_drug_revision");
        if (currentDrugRevision < _drugRawRevision) {
            return poison("stale_drug_revision");
        }
        var scan:Object = scanLoadout(_equipmentInventory);
        if (!scan.success) return poison(scan.error);
        var refsChanged:Boolean = !sameRefs(_slotRefs, scan.refs);
        var loadoutChanged:Boolean = _signature != scan.signature
            || refsChanged;
        var liveChanged:Boolean = _liveSignature != scan.liveSignature
            || refsChanged;
        var drugChanged:Boolean = currentDrugRevision != _drugRawRevision;
        if (loadoutChanged) {
            _loadoutRevision++;
            _signature = scan.signature;
            _liveSignature = scan.liveSignature;
            _slotRefs = scan.refs;
            if (liveChanged) {
                _liveRefreshDirty = true;
            } else if (!_liveRefreshDirty) {
                _liveRevision = _loadoutRevision;
            }
        }
        if (drugChanged) {
            _drugRevision += currentDrugRevision - _drugRawRevision;
            _drugRawRevision = currentDrugRevision;
        }
        return state(true, loadoutChanged, drugChanged);
    }
    public static function snapshot(expectedGeneration:Number):Object {
        return synchronize(expectedGeneration);
    }

    /**
     * EquipmentTuningService 的只读 worn source adapter。
     *
     * 只返回当前 active generation、当前 loadout revision、11 槽白名单中的现役
     * item/inventory 引用；它不写 value，也不签发任何通用容器能力。
     */
    public static function resolveWornTuningSource(
        expectedGeneration:Number,
        slotKey:String,
        expectedLoadoutRevision:Number):Object {
        if (SLOT_ALLOWLIST[slotKey] !== true) return fail("invalid_slot");
        var current:Object = synchronize(expectedGeneration);
        if (!current.success) return current;
        if (!wholeNumber(expectedLoadoutRevision)
                || expectedLoadoutRevision != _loadoutRevision) {
            return fail("stale_state");
        }
        var item:Object = null;
        try {
            item = _equipmentInventory.getItem(slotKey);
        } catch (slotReadError) {
            return fail("stale_state");
        }
        return {
            success:true,
            sessionGeneration:_sessionGeneration,
            loadoutRevision:_loadoutRevision,
            slotKey:slotKey,
            inventory:_equipmentInventory,
            item:item
        };
    }

    /**
     * worn value + 材料 raw transaction 完成后的唯一内部同步 hook。
     *
     * 调用方必须仍持有 resolveWornTuningSource 的 exact generation/revision/item。
     * 本函数只允许一次真实 loadout signature 前进，并保持 live dirty；它不刷新英雄，
     * 因为英雄共享 item 引用不等价于派生属性已经重建。
     */
    public static function commitWornTuningSynchronization(
        expectedGeneration:Number,
        slotKey:String,
        expectedLoadoutRevision:Number,
        expectedItem:Object):Object {
        if (_writeInProgress) return fail("write_busy");
        var gate:Object = sessionGate(expectedGeneration);
        if (!gate.success) return gate;
        if (SLOT_ALLOWLIST[slotKey] !== true) return fail("invalid_slot");
        if (!wholeNumber(expectedLoadoutRevision)
                || expectedLoadoutRevision != _loadoutRevision) {
            return fail("stale_state");
        }
        var resolved:Object = resolveContainers();
        if (!resolved.success
                || resolved.equipment !== _equipmentInventory) {
            return poison("stale_container");
        }
        try {
            if (_equipmentInventory.getItem(slotKey) !== expectedItem) {
                return fail("stale_state");
            }
        } catch (slotReadError) {
            return fail("stale_state");
        }

        var beforeRevision:Number = _loadoutRevision;
        var synced:Object = synchronize(expectedGeneration);
        if (!synced.success) return synced;
        synced.authorityObserved = true;
        if (_testFailNextWornPostcondition) {
            _testFailNextWornPostcondition = false;
            var injected:Object = poison("needs_reconcile");
            injected.authorityObserved = true;
            return injected;
        }
        if (synced.loadoutChanged !== true
                || _loadoutRevision != beforeRevision + 1
                || !_liveRefreshDirty) {
            var inconsistent:Object = poison("needs_reconcile");
            inconsistent.authorityObserved = true;
            return inconsistent;
        }
        return synced;
    }

    /**
     * 同步 live barrier：只有刷新后的可观测不变量全部成立才清 dirty。
     */
    public static function flushLive(expectedGeneration:Number,
                                     expectedLoadoutRevision:Number):Object {
        var sync:Object = synchronize(expectedGeneration);
        if (!sync.success) return sync;
        if (Number(expectedLoadoutRevision) != _loadoutRevision) {
            return fail("stale_state");
        }
        if (!_liveRefreshDirty && _liveRevision == _loadoutRevision) {
            return liveResult(false);
        }
        if (!_liveRefreshDirty) return liveFailure();
        var context:Object = null;
        try {
            context = liveContext(root(), _slotRefs);
        } catch (preError) {
            return liveFailure();
        }
        if (context == null) return liveFailure();
        var postValid:Boolean = false;
        try {
            context.root.刷新人物装扮(context.controlTarget);
            postValid = livePostcondition(context);
        } catch (error) {
            return liveFailure();
        }
        if (!postValid) return liveFailure();
        _liveRevision = _loadoutRevision;
        _liveRefreshDirty = false;
        return liveResult(true);
    }

    /**
     * 生产默认读取 SaveManager.hasPendingChanges()/flushNow()；focused fixture
     * 可注入同形 Boolean port。false 是明确失败，非 Boolean/throw 是 unknown。
     * 成功后只保存最近一次 exact generation/revision proof 供丢包重试。
     */
    public static function finalize(expectedGeneration:Number,
                                    expectedLoadoutRevision:Number):Object {
        var replay:Object = replayFinalizeReceipt(
            expectedGeneration, expectedLoadoutRevision);
        if (replay != null) return replay;

        var live:Object = flushLive(expectedGeneration, expectedLoadoutRevision);
        if (!live.success) return finalizeFailure(live, false);
        var globalDirty:Object = invokeBoolean("isGlobalDirty");
        if (!globalDirty.known) {
            return finalizeFailure(fail("needs_reconcile"), live.changed);
        }
        var persistenceChanged:Boolean = false;
        if (globalDirty.value) {
            var saveResult:Object = invokeBoolean("flushNow");
            if (!saveResult.known) {
                return finalizeFailure(fail("needs_reconcile"), live.changed);
            }
            if (!saveResult.value) {
                return finalizeFailure(fail("flush_failed"), live.changed);
            }
            persistenceChanged = true;
        }
        _active = false;
        return rememberFinalizeSuccess(expectedGeneration,
            expectedLoadoutRevision, live.changed, persistenceChanged);
    }

    /**
     * legacy 查询入口保留为 fail-closed fence。generic webPanelUnpause 不得再调用本函数，
     * 更不得凭一次无响应 socket write 替 Host 消费 CharacterBuild pause authority。
     */
    public static function releasePauseForClose():Object {
        if (!blocksGenericPauseRelease()) {
            return {handled:false, success:true};
        }
        return {
            handled:true,
            success:false,
            error:"host_recovery_required",
            pauseRetained:true
        };
    }

    /**
     * generic close 只做纯查询。只要 AS2 仍保有尚未被 Host exact recovery 消费的
     * CharacterBuild authority，就必须保留全局 pause。
     */
    public static function blocksGenericPauseRelease():Boolean {
        return hasCharacterAuthority()
            && !_hostPauseReleaseProven;
    }

    /**
     * socket detach 只能完成 finalize/persist 并保留 captured lease。此时 AS2 不知道
     * Host visual 是否已经退场；真正释放必须等待重连后的 Host-only recoverDetach。
     */
    public static function reconcileSocketDetach():Object {
        if (!blocksGenericPauseRelease()) {
            return {handled:false, success:true};
        }
        return retainCapturedPause("socket_detach");
    }

    /**
     * Host-only orphan recovery。knownGeneration 缺省时，Host 表示首次 snapshot 的响应
     * 可能丢失；AS2 仍只按 exact panelInstanceId 查询。只有 CharacterBuild 确实从未
     * 建立任何 authority 时才返回 authority_absent，并在同一 Host admission fence
     * 下释放遗留的全局 web pause lease。
     */
    public static function recoverDetach(params:Object):Object {
        if (params == undefined || Number(params.v) != 1) {
            return commonRecoveryResponse(params,
                recoveryFailure("invalid_payload"));
        }
        var requestedPanel:String = params.panelInstanceId == undefined
            ? "" : String(params.panelInstanceId);
        if (requestedPanel == "" || requestedPanel == "undefined") {
            return commonRecoveryResponse(params,
                recoveryFailure("invalid_payload"));
        }

        var hasKnownGeneration:Boolean =
            params.knownGeneration != undefined
            && params.knownGeneration != null
            && String(params.knownGeneration) != "";
        var knownGeneration:Number = hasKnownGeneration
            ? Number(params.knownGeneration) : 0;
        if (hasKnownGeneration
                && (!wholeNumber(knownGeneration)
                    || knownGeneration <= 0)) {
            return commonRecoveryResponse(params,
                recoveryFailure("invalid_payload"));
        }

        var exactPanel:Boolean = _panelInstanceId != ""
            && requestedPanel == _panelInstanceId;
        var authorityPresent:Boolean = hasCharacterAuthority();

        if (exactPanel && authorityPresent) {
            if (hasKnownGeneration
                    && knownGeneration != _sessionGeneration) {
                return commonRecoveryResponse(params,
                    recoveryFailure("stale_session"));
            }
            return commonRecoveryResponse(params,
                recoverExactAuthority());
        }

        if (authorityPresent) {
            return commonRecoveryResponse(params,
                recoveryFailure("authority_conflict"));
        }
        if (hasKnownGeneration) {
            return commonRecoveryResponse(params,
                recoveryFailure("stale_session"));
        }
        return commonRecoveryResponse(params,
            recoverAbsentAuthority());
    }

    private static function recoverExactAuthority():Object {
        var settle:Object = null;
        if (_capturedPauseLease !== undefined) {
            settle = settleCapturedPause("host_recover_detach");
            if (settle == null || settle.success !== true) {
                return recoveryFailure(settle == null
                    || settle.error == undefined
                    ? "finalize_failed" : String(settle.error));
            }
        }

        if (_active || _finalizeReceipt == null) {
            return recoveryFailure("session_not_active");
        }
        var proof:Object = replayFinalizeReceipt(
            _finalizeReceipt.generation,
            _finalizeReceipt.expectedLoadoutRevision);
        if (proof == null || proof.success !== true
                || proof.closed !== true || proof.active !== false
                || proof.persistence == null
                || proof.persistence.success !== true
                || proof.liveRefreshDirty === true
                || proof.liveRevision != proof.loadoutRevision) {
            return recoveryFailure("finalize_failed");
        }

        var r:Object = root();
        if (r._webPanelPauseLease != undefined
                && r._webPanelPauseLease != null) {
            return recoveryFailure("stale_pause_lease");
        }
        _hostPauseReleaseProven = true;
        return {
            success:true,
            recoveryState:"settled",
            closed:true,
            pauseReleased:true,
            persistence:{
                success:true,
                changed:proof.persistence.changed === true
            },
            active:false,
            sessionGeneration:proof.sessionGeneration,
            loadoutRevision:proof.loadoutRevision,
            liveRevision:proof.liveRevision,
            liveRefreshDirty:false,
            drugRevision:proof.drugRevision
        };
    }

    private static function recoverAbsentAuthority():Object {
        // authority_absent 是正向证明，不是“没查到 exact panel”这一弱条件。
        if (hasCharacterAuthority()) {
            return recoveryFailure("authority_conflict");
        }

        var r:Object = root();
        var lease = r == null ? undefined : r._webPanelPauseLease;
        if (lease != undefined && lease != null) {
            if (typeof lease != "string" || String(lease) == "") {
                return recoveryFailure("stale_pause_lease");
            }
            if (r._webPanelPauseLease !== lease
                    || !releaseCapturedPauseLease(lease)
                    || r._webPanelPauseLease !== lease) {
                return recoveryFailure("pause_release_failed");
            }
            r._webPanelPauseLease = undefined;
        }
        return {
            success:true,
            recoveryState:"authority_absent",
            closed:true,
            pauseReleased:true,
            persistence:{success:true, changed:false},
            active:false,
            sessionGeneration:0,
            loadoutRevision:0,
            liveRevision:0,
            liveRefreshDirty:false,
            drugRevision:0
        };
    }

    private static function recoveryFailure(errorCode:String):Object {
        return {
            success:false,
            error:errorCode,
            recoveryState:"unsettled",
            closed:false,
            pauseReleased:false,
            persistence:{success:false, changed:false},
            active:_active,
            sessionGeneration:_sessionGeneration,
            loadoutRevision:_loadoutRevision,
            liveRevision:_liveRevision,
            liveRefreshDirty:_liveRefreshDirty,
            drugRevision:_drugRevision
        };
    }

    private static function commonRecoveryResponse(params:Object,
                                                    result:Object):Object {
        var response:Object = commonResponse(
            "recoverDetach", params, result);
        response.recoveryState = result.recoveryState;
        response.closed = result.closed === true;
        response.pauseReleased = result.pauseReleased === true;
        response.persistence = {
            success:result.persistence != null
                && result.persistence.success === true,
            changed:result.persistence != null
                && result.persistence.changed === true
        };
        return response;
    }

    private static function settleCapturedPause(reason:String):Object {
        var r:Object = root();
        var captured = _capturedPauseLease;
        if (r._webPanelPauseLease !== captured) {
            return {
                handled:true,
                success:false,
                error:"stale_pause_lease",
                reason:reason
            };
        }

        var resolved:Object = resolvePauseFinalizeProof(reason);
        if (!resolved.success) return resolved;
        var proof:Object = resolved.proof;
        if (r._webPanelPauseLease !== captured) {
            return {
                handled:true,
                success:false,
                error:"stale_pause_lease",
                reason:reason
            };
        }
        if (!releaseCapturedPauseLease(captured)) {
            return {
                handled:true,
                success:false,
                error:"pause_release_failed",
                reason:reason
            };
        }
        if (r._webPanelPauseLease === captured) {
            r._webPanelPauseLease = undefined;
        }
        _capturedPauseLease = undefined;
        return {
            handled:true,
            success:true,
            reason:reason,
            sessionGeneration:proof.sessionGeneration,
            loadoutRevision:proof.loadoutRevision
        };
    }

    private static function retainCapturedPause(reason:String):Object {
        var r:Object = root();
        var captured = _capturedPauseLease;
        if (captured === undefined
                || r._webPanelPauseLease !== captured) {
            return {
                handled:true,
                success:false,
                error:"stale_pause_lease",
                reason:reason,
                pauseRetained:true
            };
        }

        var resolved:Object = resolvePauseFinalizeProof(reason);
        if (!resolved.success) {
            resolved.pauseRetained = true;
            return resolved;
        }
        if (r._webPanelPauseLease !== captured) {
            return {
                handled:true,
                success:false,
                error:"stale_pause_lease",
                reason:reason,
                pauseRetained:true
            };
        }
        return {
            handled:true,
            success:true,
            reason:reason,
            pauseRetained:true,
            sessionGeneration:resolved.proof.sessionGeneration,
            loadoutRevision:resolved.proof.loadoutRevision
        };
    }

    private static function resolvePauseFinalizeProof(
        reason:String):Object {
        var proof:Object;
        if (_active) {
            var sync:Object = synchronize(_sessionGeneration);
            if (!sync.success) {
                return {
                    handled:true,
                    success:false,
                    error:sync.error,
                    reason:reason
                };
            }
            proof = finalize(
                _sessionGeneration, sync.loadoutRevision);
        } else if (_finalizeReceipt != null) {
            proof = replayFinalizeReceipt(
                _finalizeReceipt.generation,
                _finalizeReceipt.expectedLoadoutRevision);
        } else {
            return {
                handled:true,
                success:false,
                error:"session_not_active",
                reason:reason
            };
        }
        if (proof == null || !proof.success || !proof.closed
                || proof.persistence == null
                || proof.persistence.success !== true) {
            return {
                handled:true,
                success:false,
                error:proof == null || proof.error == undefined
                    ? "finalize_failed" : proof.error,
                reason:reason
            };
        }
        return {success:true, proof:proof};
    }

    private static function hasCharacterAuthority():Boolean {
        return _active || _sessionGeneration > 0
            || _capturedPauseLease !== undefined
            || _finalizeReceipt != null
            || _panelInstanceId != "";
    }

    private static function releaseCapturedPauseLease(leaseId):Boolean {
        try {
            var callback:Function = _callbacks == null
                ? null : _callbacks.releasePauseLease;
            if (typeof callback == "function") {
                return callback(leaseId) === true;
            }
            if (_testRoot != null) return true;
            org.flashNight.arki.pause.PauseManager.releaseLease(
                String(leaseId));
            return true;
        } catch (releaseError) {
            return false;
        }
    }

    private static function executeSnapshot(params:Object):Object {
        var panelInstanceId:String = params.panelInstanceId == undefined
            ? "" : String(params.panelInstanceId);
        if (panelInstanceId == "") return fail("invalid_payload");
        var hasReconcileWatermark:Boolean =
            params.reconcileAfterCallId != undefined
            && params.reconcileAfterCallId != null;
        if (hasReconcileWatermark
                && (!validAsciiToken(
                        params.reconcileAfterCallId, 96, false)
                    || typeof params.panelInstanceId != "string"
                    || typeof params.sessionGeneration != "number")) {
            return fail("invalid_payload");
        }
        var generationMissing:Boolean = params.sessionGeneration == undefined
            || params.sessionGeneration == null
            || String(params.sessionGeneration) == "";
        if (generationMissing) {
            if (hasReconcileWatermark) return fail("invalid_payload");
            if (_sessionGeneration > 0 && panelInstanceId == _panelInstanceId) {
                if (!_active) return fail("session_not_active");
                var repeated:Object = snapshot(_sessionGeneration);
                if (!repeated.success) return repeated;
                return attachSnapshotRequestExtras(
                    params, repeated, false);
            }
            if (_active) return fail("session_active");
            var opened:Object = open();
            if (!opened.success) return opened;
            _panelInstanceId = panelInstanceId;
            return attachSnapshotRequestExtras(params, opened, false);
        }
        var identity:Object = panelGate(panelInstanceId);
        if (!identity.success) return identity;
        var recoveringNeedsReconcile:Boolean = hasReconcileWatermark
            && _stale && _staleError == "needs_reconcile";
        var current:Object = recoveringNeedsReconcile
            ? synchronizeNeedsReconcile(
                Number(params.sessionGeneration))
            : snapshot(Number(params.sessionGeneration));
        if (!current.success) return current;
        return attachSnapshotRequestExtras(
            params, current, recoveringNeedsReconcile);
    }

    private static function attachSnapshotRequestExtras(params:Object,
                                                        current:Object,
                                                        clearNeedsReconcile:Boolean):Object {
        attachSnapshotProjection(current);
        if (params.reconcileAfterCallId == undefined
                || params.reconcileAfterCallId == null) {
            return current;
        }
        if (typeof params.reconcileAfterCallId != "string"
                || String(params.reconcileAfterCallId) == "") {
            return fail("invalid_payload");
        }
        var backpackSnapshot:Object = buildBackpackSnapshot();
        if (!validBackpackSnapshot(backpackSnapshot)) {
            return fail("projection_failed");
        }
        current.reconcileAfterCallId =
            String(params.reconcileAfterCallId);
        current.inventorySnapshots = [backpackSnapshot];
        if (clearNeedsReconcile) {
            _stale = false;
            _staleError = "";
        }
        return current;
    }

    /**
     * 只允许显式 unknown-write reconcile 暂时穿过 needs_reconcile。
     * 在 full projection + backpack snapshot 完成前保持 poison；其他 stale 原因不解封。
     */
    private static function synchronizeNeedsReconcile(
        expectedGeneration:Number):Object {
        if (!_active) return fail("session_not_active");
        if (!_stale || _staleError != "needs_reconcile") {
            return synchronize(expectedGeneration);
        }
        if (!wholeNumber(expectedGeneration)
                || expectedGeneration != _sessionGeneration) {
            return fail("stale_session");
        }

        _stale = false;
        _staleError = "";
        var current:Object = synchronize(expectedGeneration);
        if (!current.success) {
            if (!_stale) {
                _stale = true;
                _staleError = "needs_reconcile";
            }
            return current;
        }
        _stale = true;
        _staleError = "needs_reconcile";
        return current;
    }

    private static function executeCandidates(params:Object):Object {
        var identity:Object = panelGate(String(params.panelInstanceId));
        if (!identity.success) return identity;
        var current:Object = synchronize(Number(params.sessionGeneration));
        if (!current.success) return current;
        if (!expectedRevisionMatches(params.expectedLoadoutRevision,
                _loadoutRevision)
                || !expectedRevisionMatches(params.expectedDrugRevision,
                    _drugRevision)) {
            return fail("stale_state");
        }

        var hasEquipment:Boolean = params.slotKey != undefined
            && params.slotKey != null && String(params.slotKey) != "";
        var hasDrug:Boolean = params.drugSlot != undefined
            && params.drugSlot != null && String(params.drugSlot) != "";
        if (hasEquipment == hasDrug) return fail("invalid_payload");

        var slotKey:String = "";
        var drugSlot:Number = -1;
        if (hasEquipment) {
            slotKey = String(params.slotKey);
            if (SLOT_ALLOWLIST[slotKey] !== true) return fail("invalid_slot");
        } else {
            drugSlot = Number(params.drugSlot);
            if (!wholeInRange(drugSlot, 0,
                    org.flashNight.arki.unit.Action.Skill.DrugInputService.SLOT_COUNT - 1)) {
                return fail("invalid_slot");
            }
        }

        var backpackSnapshot:Object = buildBackpackSnapshot();
        if (backpackSnapshot == null
                || !(backpackSnapshot.slots instanceof Array)) {
            return fail("projection_failed");
        }

        var candidates:Array = [];
        var diagnostics:Array = [];
        var playerLevel = hasEquipment ? root().等级 : undefined;
        var drugCooldownKnown:Boolean = true;
        var drugReady:Boolean = true;
        if (hasDrug) {
            var cooldownKey:String =
                org.flashNight.arki.unit.Action.Skill.ManualCooldownService
                    .drugKey(drugSlot);
            try {
                var cooldownCallback:Function = _callbacks == null
                    ? null : _callbacks.drugCooldownReady;
                var cooldownValue = typeof cooldownCallback == "function"
                    ? cooldownCallback(cooldownKey)
                    : org.flashNight.arki.unit.Action.Skill
                        .ManualCooldownService.isReady(cooldownKey);
                if (cooldownValue !== true && cooldownValue !== false) {
                    drugCooldownKnown = false;
                    drugReady = false;
                } else {
                    drugReady = cooldownValue === true;
                }
            } catch (cooldownError) {
                drugCooldownKnown = false;
                drugReady = false;
            }
            if (!drugCooldownKnown) {
                diagnostics.push("drug_cooldown_unavailable:" + drugSlot);
            }
        }
        for (var i:Number = 0; i < backpackSnapshot.slots.length; i++) {
            var row:Object = backpackSnapshot.slots[i];
            if (row == null || row.occupied !== true
                    || !wholeNumber(row.physicalSlot)) continue;
            var physicalSlot:Number = Number(row.physicalSlot);
            var lease:String = row.slotLease == undefined
                ? "" : String(row.slotLease);
            if (physicalSlot < 0
                    || physicalSlot >= Number(_backpackInventory.capacity)
                    || lease == "") {
                diagnostics.push("backpack_lease_invalid:" + physicalSlot);
                continue;
            }
            var item:Object;
            try {
                item = _backpackInventory.getItem(String(physicalSlot));
            } catch (readError) {
                diagnostics.push("backpack_read_failed:" + physicalSlot);
                continue;
            }
            if (item == null || typeof item.name != "string") {
                diagnostics.push("backpack_item_invalid:" + physicalSlot);
                continue;
            }
            var itemData:Object = getCandidateItemData(item);
            if (itemData == null || typeof itemData != "object"
                    || typeof itemData.use != "string") {
                diagnostics.push("candidate_catalog_invalid:" + physicalSlot);
                continue;
            }
            var useName:String = String(itemData.use);
            var useMatches:Boolean = hasEquipment
                ? (useName == slotKey
                    || (slotKey == "手枪2" && useName == "手枪"))
                : useName == "药剂";
            // 背包中属于其他目标的正常物品只是被筛掉，不把常态异构背包误报为 degraded。
            if (!useMatches) continue;

            var disabled:Boolean = false;
            var blockedReason:String = "";
            if (hasEquipment && slotKey != "手雷") {
                if (typeof itemData.type != "string"
                        || (itemData.type != "武器"
                            && itemData.type != "防具")) {
                    diagnostics.push(
                        "candidate_type_incompatible:" + physicalSlot);
                    continue;
                }
                if (typeof item.value != "object" || item.value == null) {
                    diagnostics.push(
                        "candidate_value_incompatible:" + physicalSlot);
                    continue;
                }
            } else if (!finiteNumber(item.value) || Number(item.value) <= 0) {
                diagnostics.push(
                    "candidate_value_incompatible:" + physicalSlot);
                continue;
            }

            if (hasEquipment) {
                if (itemData.data == null
                        || typeof itemData.data != "object"
                        || !finiteNumber(itemData.data.level)
                        || !finiteNumber(playerLevel)) {
                    diagnostics.push(
                        "candidate_level_invalid:" + physicalSlot);
                    continue;
                }
                // 与现役 ItemUtil.moveItemToEquipment 一致：只读 catalog 等级，
                // 绝不把实例 value.level（强化度）当角色等级门。
                if (itemData.data.level > playerLevel) {
                    disabled = true;
                    blockedReason = "level_locked";
                }
            } else if (!drugCooldownKnown) {
                disabled = true;
                blockedReason = "cooldown_unavailable";
            } else if (!drugReady) {
                disabled = true;
                blockedReason = "cooldown_active";
            }

            var projection:Object = buildSafeItemProjection(
                item, diagnostics, "candidate:" + physicalSlot);
            // 候选展示里的分类字段也钉回同一次 catalog 读取，避免 item.getData
            // 与资格判定使用不同来源时让 Host/Web 看见自相矛盾的 use/type。
            projection.use = useName;
            if (typeof itemData.type == "string") {
                projection.majorType = String(itemData.type);
            }
            candidates.push({
                physicalSlot:physicalSlot,
                disabled:disabled,
                blockedReason:blockedReason,
                item:projection,
                source:{
                    containerId:"背包",
                    slot:physicalSlot,
                    expectedLease:lease
                }
            });
        }

        current.payload = {
            target:hasEquipment
                ? {kind:"equipment", slotKey:slotKey}
                : {kind:"drug", drugSlot:drugSlot},
            candidates:candidates,
            backpackVersion:Number(backpackSnapshot.containerVersion),
            stateHealth:diagnostics.length == 0 ? "ok" : "degraded",
            diagnostics:diagnostics
        };
        return current;
    }

    /**
     * 四个显式 mutation 共用一把同步重入闸。闸覆盖预检、双写、领域水位、
     * publish 与响应快照，因此 dispatcher 回调只能读到最终两端，不能再入写。
     */
    private static function executeMutation(commandName:String,
                                             params:Object):Object {
        if (_writeInProgress) return fail("write_busy");
        _writeInProgress = true;
        _writeAuthorityTouched = false;
        var result:Object;
        try {
            result = executeMutationCore(commandName, params);
        } catch (unexpectedMutationError) {
            result = _writeAuthorityTouched
                ? poison("needs_reconcile") : fail("internal_error");
        } finally {
            _writeAuthorityTouched = false;
            _writeInProgress = false;
        }
        return result;
    }

    private static function executeMutationCore(commandName:String,
                                                 params:Object):Object {
        if (!validMutationEnvelope(commandName, params)) {
            return fail("invalid_payload");
        }
        var identity:Object = panelGate(String(params.panelInstanceId));
        if (!identity.success) return identity;
        var current:Object = synchronize(Number(params.sessionGeneration));
        if (!current.success) return current;
        var r:Object = root();
        if (r.存档系统 == null) return fail("service_not_ready");

        if (commandName == "equipEquipment") {
            return mutateEquipEquipment(params);
        }
        if (commandName == "unequipEquipment") {
            return mutateUnequipEquipment(params);
        }
        if (commandName == "equipDrug") {
            return mutateEquipDrug(params);
        }
        return mutateUnequipDrug(params);
    }

    private static function mutateEquipEquipment(params:Object):Object {
        if (!expectedRevisionMatches(params.expectedLoadoutRevision,
                _loadoutRevision)) return fail("stale_state");
        var slotKey:String = String(params.slotKey);
        if (SLOT_ALLOWLIST[slotKey] !== true) return fail("invalid_slot");

        var sourceCheck:Object = validateBackpackSource(
            params.source, slotKey == "手雷");
        if (!sourceCheck.success) return sourceCheck;
        var sourceItem:Object = sourceCheck.item;
        var eligible:Object = validateEquipmentItem(sourceItem, slotKey);
        if (!eligible.success) return eligible;

        // lease/catalog callbacks are module boundaries; recheck target authority afterwards.
        var fresh:Object = synchronize(Number(params.sessionGeneration));
        if (!fresh.success) return fresh;
        if (!expectedRevisionMatches(params.expectedLoadoutRevision,
                _loadoutRevision)
                || !sourceStillExact(sourceCheck)) {
            return fail("stale_state");
        }
        if (!transactionEndpointsReady(_backpackInventory,
                _equipmentInventory)) return fail("service_not_ready");

        var targetIndex:Number = slotIndex(slotKey);
        if (targetIndex < 0) return fail("invalid_slot");
        var targetBefore:Object = _equipmentInventory.getItem(slotKey);
        if (targetBefore !== _slotRefs[targetIndex]
                || sourceItem === targetBefore) return fail("stale_state");

        var plan:Object = {
            source:_backpackInventory,
            sourceSlot:Number(sourceCheck.slot),
            sourceBefore:sourceItem,
            sourceAfter:targetBefore,
            target:_equipmentInventory,
            targetSlot:slotKey,
            targetBefore:targetBefore,
            targetAfter:sourceItem,
            sourceChange:targetBefore == null ? "removed" : "replaced",
            targetChange:targetBefore == null ? "added" : "replaced",
            drugTarget:false
        };
        var transaction:Object = executeTwoSlotTransaction(plan);
        if (!transaction.success) return transaction.result;
        return commitEquipmentMutation(
            "equipEquipment", Number(sourceCheck.slot), plan);
    }

    private static function mutateUnequipEquipment(params:Object):Object {
        if (!expectedRevisionMatches(params.expectedLoadoutRevision,
                _loadoutRevision)) return fail("stale_state");
        var slotKey:String = String(params.slotKey);
        if (SLOT_ALLOWLIST[slotKey] !== true) return fail("invalid_slot");
        var targetIndex:Number = slotIndex(slotKey);
        var sourceItem:Object = _equipmentInventory.getItem(slotKey);
        if (targetIndex < 0 || sourceItem == null
                || sourceItem !== _slotRefs[targetIndex]) {
            return fail("invalid_slot");
        }
        var backpackSlot:Number = firstBackpackVacancy();
        if (backpackSlot < 0) return fail("backpack_full");
        if (!transactionEndpointsReady(_equipmentInventory,
                _backpackInventory)) return fail("service_not_ready");

        var plan:Object = {
            source:_equipmentInventory,
            sourceSlot:slotKey,
            sourceBefore:sourceItem,
            sourceAfter:null,
            target:_backpackInventory,
            targetSlot:backpackSlot,
            targetBefore:null,
            targetAfter:sourceItem,
            sourceChange:"removed",
            targetChange:"added",
            drugTarget:false
        };
        var transaction:Object = executeTwoSlotTransaction(plan);
        if (!transaction.success) return transaction.result;
        return commitEquipmentMutation(
            "unequipEquipment", backpackSlot, plan);
    }

    private static function mutateEquipDrug(params:Object):Object {
        if (!expectedRevisionMatches(params.expectedDrugRevision,
                _drugRevision)) return fail("stale_state");
        var drugSlot:Number = Number(params.drugSlot);
        if (!validDrugSlot(drugSlot)) return fail("invalid_slot");
        var cooldown:Object = readDrugCooldown(drugSlot);
        if (!cooldown.success) return cooldown;

        var sourceCheck:Object = validateBackpackSource(params.source, true);
        if (!sourceCheck.success) return sourceCheck;
        var sourceItem:Object = sourceCheck.item;
        var sourceEligibility:Object = validateDrugItem(sourceItem);
        if (!sourceEligibility.success) return sourceEligibility;

        var fresh:Object = synchronize(Number(params.sessionGeneration));
        if (!fresh.success) return fresh;
        if (!expectedRevisionMatches(params.expectedDrugRevision,
                _drugRevision)
                || !sourceStillExact(sourceCheck)) {
            return fail("stale_state");
        }
        if (!transactionEndpointsReady(_backpackInventory,
                _drugInventory)) return fail("service_not_ready");

        var targetBefore:Object = _drugInventory.getItem(String(drugSlot));
        if (sourceItem === targetBefore) return fail("stale_state");
        var targetBeforeSignature:String =
            transactionItemSignature(targetBefore);
        var targetEligibility:Object = {success:true};
        if (targetBefore != null) {
            targetEligibility = validateDrugItem(targetBefore);
        }
        // target catalog lookup is another module boundary. Recheck both
        // containers and the exact target before deriving merge/swap.
        var targetFresh:Object = synchronize(
            Number(params.sessionGeneration));
        if (!targetFresh.success) return targetFresh;
        if (!expectedRevisionMatches(params.expectedDrugRevision,
                _drugRevision)
                || !sourceStillExact(sourceCheck)
                || _drugInventory.getItem(String(drugSlot))
                    !== targetBefore
                || transactionItemSignature(targetBefore)
                    != targetBeforeSignature) {
            return fail("stale_state");
        }
        if (!targetEligibility.success) return targetEligibility;

        var sourceAfter:Object = targetBefore;
        var targetAfter:Object = sourceItem;
        var sourceChange:String = targetBefore == null
            ? "removed" : "replaced";
        var targetChange:String = targetBefore == null
            ? "added" : "replaced";
        var stackMerge:Boolean = false;
        var mergedValue:Number = 0;
        if (targetBefore != null) {
            if (String(targetBefore.name) == String(sourceItem.name)) {
                mergedValue = Number(targetBefore.value)
                    + Number(sourceItem.value);
                if (!finiteNumber(mergedValue) || mergedValue <= 0) {
                    return fail("incompatible_item");
                }
                stackMerge = true;
                sourceAfter = null;
                targetAfter = targetBefore;
                sourceChange = "removed";
                targetChange = "value";
            }
        }

        var plan:Object = {
            source:_backpackInventory,
            sourceSlot:Number(sourceCheck.slot),
            sourceBefore:sourceItem,
            sourceAfter:sourceAfter,
            target:_drugInventory,
            targetSlot:drugSlot,
            targetBefore:targetBefore,
            targetAfter:targetAfter,
            sourceChange:sourceChange,
            targetChange:targetChange,
            drugTarget:true,
            stackMerge:stackMerge,
            stackTarget:targetBefore,
            stackBefore:stackMerge ? Number(targetBefore.value) : 0,
            stackAfter:stackMerge ? mergedValue : 0
        };
        var transaction:Object = executeTwoSlotTransaction(plan);
        if (!transaction.success) return transaction.result;
        return commitDrugMutation(
            "equipDrug", Number(sourceCheck.slot), plan);
    }

    private static function mutateUnequipDrug(params:Object):Object {
        if (!expectedRevisionMatches(params.expectedDrugRevision,
                _drugRevision)) return fail("stale_state");
        var drugSlot:Number = Number(params.drugSlot);
        if (!validDrugSlot(drugSlot)) return fail("invalid_slot");
        var cooldown:Object = readDrugCooldown(drugSlot);
        if (!cooldown.success) return cooldown;
        var fresh:Object = synchronize(Number(params.sessionGeneration));
        if (!fresh.success) return fresh;
        if (!expectedRevisionMatches(params.expectedDrugRevision,
                _drugRevision)) return fail("stale_state");

        var sourceItem:Object = _drugInventory.getItem(String(drugSlot));
        if (sourceItem == null) return fail("invalid_slot");
        var sourceSignature:String =
            transactionItemSignature(sourceItem);
        var sourceEligibility:Object = validateDrugItem(sourceItem);
        // Catalog authority may cross a module boundary. Do not let an old
        // source ref or quantity pass after that lookup.
        var catalogFresh:Object = synchronize(
            Number(params.sessionGeneration));
        if (!catalogFresh.success) return catalogFresh;
        if (!expectedRevisionMatches(params.expectedDrugRevision,
                _drugRevision)
                || _drugInventory.getItem(String(drugSlot)) !== sourceItem
                || transactionItemSignature(sourceItem)
                    != sourceSignature) {
            return fail("stale_state");
        }
        if (!sourceEligibility.success) return sourceEligibility;
        var backpackSlot:Number = firstBackpackVacancy();
        if (backpackSlot < 0) return fail("backpack_full");
        if (!transactionEndpointsReady(_drugInventory,
                _backpackInventory)) return fail("service_not_ready");

        var plan:Object = {
            source:_drugInventory,
            sourceSlot:drugSlot,
            sourceBefore:sourceItem,
            sourceAfter:null,
            target:_backpackInventory,
            targetSlot:backpackSlot,
            targetBefore:null,
            targetAfter:sourceItem,
            sourceChange:"removed",
            targetChange:"added",
            drugTarget:true
        };
        var transaction:Object = executeTwoSlotTransaction(plan);
        if (!transaction.success) return transaction.result;
        return commitDrugMutation(
            "unequipDrug", backpackSlot, plan);
    }

    /**
     * 两个容器共用的窄提交叶：exact before → 两次无事件写 → exact after。
     * 它不拥有领域 revision、dirty、publish 或 projection。
     */
    private static function executeTwoSlotTransaction(plan:Object):Object {
        plan.sourceBeforeSignature =
            transactionItemSignature(plan.sourceBefore);
        plan.targetBeforeSignature =
            transactionItemSignature(plan.targetBefore);
        if (!slotMatches(plan.source, plan.sourceSlot,
                plan.sourceBefore, plan.sourceBeforeSignature)
                || !slotMatches(plan.target, plan.targetSlot,
                    plan.targetBefore, plan.targetBeforeSignature)) {
            return {success:false, result:fail("stale_state")};
        }
        if (plan.stackMerge === true) {
            // 同名 merge 在 transactionWrite 前已经原位触碰 target ref。
            _writeAuthorityTouched = true;
            plan.stackTarget.value = Number(plan.stackAfter);
        }
        plan.sourceAfterSignature =
            transactionItemSignature(plan.sourceAfter);
        plan.targetAfterSignature =
            transactionItemSignature(plan.targetAfter);
        if (plan.stackMerge !== true) _writeAuthorityTouched = true;

        var first:Object = attemptTransactionWrite(
            plan.source, plan.sourceSlot, plan.sourceAfter);
        var firstExact:Boolean = slotMatches(plan.source, plan.sourceSlot,
            plan.sourceAfter, plan.sourceAfterSignature);
        if (!first.returned || first.threw || !firstExact) {
            return transactionFailure(plan);
        }

        var second:Object = attemptTransactionWrite(
            plan.target, plan.targetSlot, plan.targetAfter);
        var exactAfter:Boolean = slotMatches(plan.source, plan.sourceSlot,
                plan.sourceAfter, plan.sourceAfterSignature)
            && slotMatches(plan.target, plan.targetSlot,
                plan.targetAfter, plan.targetAfterSignature);
        if (!second.returned || second.threw || !exactAfter) {
            return transactionFailure(plan);
        }
        return {success:true};
    }

    private static function transactionFailure(plan:Object):Object {
        if (plan.stackMerge === true && plan.stackTarget != null) {
            plan.stackTarget.value = Number(plan.stackBefore);
        }
        var targetRollback:Object = attemptTransactionWrite(
            plan.target, plan.targetSlot, plan.targetBefore);
        var sourceRollback:Object = attemptTransactionWrite(
            plan.source, plan.sourceSlot, plan.sourceBefore);
        var exactBefore:Boolean = slotMatches(plan.source, plan.sourceSlot,
                plan.sourceBefore, plan.sourceBeforeSignature)
            && slotMatches(plan.target, plan.targetSlot,
                plan.targetBefore, plan.targetBeforeSignature);
        var rollbackTrusted:Boolean = targetRollback.returned
            && !targetRollback.threw && sourceRollback.returned
            && !sourceRollback.threw && exactBefore;

        // clean rollback 的 raw revision 只用来失效 lease，不推进 drug domain。
        if (rollbackTrusted && (plan.source === _drugInventory
                || plan.target === _drugInventory)) {
            var rollbackDrugRevision:Number =
                readRevision(_drugInventory);
            if (rollbackDrugRevision < 0) {
                rollbackTrusted = false;
            } else {
                _drugRawRevision = rollbackDrugRevision;
            }
        }
        if (!rollbackTrusted) {
            return {success:false, result:poison("needs_reconcile")};
        }
        var failed:Object = fail("write_failed");
        failed.rolledBack = true;
        return {success:false, result:failed};
    }

    private static function attemptTransactionWrite(container:Object,
                                                    slot,
                                                    item:Object):Object {
        var returned:Boolean = false;
        var threw:Boolean = false;
        try {
            returned = container.transactionWrite(slot, item) === true;
        } catch (writeError) {
            threw = true;
            returned = false;
        }
        return {returned:returned, threw:threw};
    }

    private static function slotMatches(container:Object, slot,
                                        expectedRef:Object,
                                        expectedSignature:String):Boolean {
        try {
            var current:Object = container.getItem(String(slot));
            return current === expectedRef
                && transactionItemSignature(current) == expectedSignature;
        } catch (slotReadError) {
            return false;
        }
    }

    private static function commitEquipmentMutation(commandName:String,
                                                     backpackSlot:Number,
                                                     plan:Object):Object {
        var scan:Object = scanLoadout(_equipmentInventory);
        if (!scan.success) {
            return transactionFailure(plan).result;
        }
        _slotRefs = scan.refs;
        _signature = scan.signature;
        _liveSignature = scan.liveSignature;
        _loadoutRevision++;
        _liveRefreshDirty = true;
        markSaveDirty();
        invalidateBackpackSlot(backpackSlot);
        publishCommittedPlan(plan);
        return buildMutationSuccess(commandName, backpackSlot, true, false);
    }

    private static function commitDrugMutation(commandName:String,
                                                backpackSlot:Number,
                                                plan:Object):Object {
        var rawAfter:Number = readRevision(_drugInventory);
        if (rawAfter <= _drugRawRevision) {
            return poison("needs_reconcile");
        }
        _drugRawRevision = rawAfter;
        _drugRevision++;
        markSaveDirty();
        invalidateBackpackSlot(backpackSlot);
        publishCommittedPlan(plan);
        return buildMutationSuccess(commandName, backpackSlot, false, true);
    }

    private static function publishCommittedPlan(plan:Object):Void {
        try {
            plan.target.publishTransactionChange(
                plan.targetSlot, String(plan.targetChange));
        } catch (targetPublishError) {
            // authority 已提交；旧 UI dispatcher 失败不能反向伪装成未写。
        }
        try {
            plan.source.publishTransactionChange(
                plan.sourceSlot, String(plan.sourceChange));
        } catch (sourcePublishError) {
            // 同上。下一份权威 snapshot 仍以容器最终态为准。
        }
    }

    private static function buildMutationSuccess(commandName:String,
                                                  backpackSlot:Number,
                                                  loadoutChanged:Boolean,
                                                  drugChanged:Boolean):Object {
        var backpackSnapshot:Object = buildBackpackSnapshot();
        if (!validBackpackSnapshot(backpackSnapshot)) {
            return poison("needs_reconcile");
        }
        var result:Object = state(true, loadoutChanged, drugChanged);
        attachSnapshotProjection(result);
        if (result.payload == null
                || result.payload.stateHealth != "ok") {
            return poison("needs_reconcile");
        }
        result.changed = true;
        result.operation = commandName;
        result.affectedBackpackSlot = backpackSlot;
        result.inventorySnapshots = [backpackSnapshot];
        return result;
    }

    private static function validateBackpackSource(source:Object,
                                                   checkCount:Boolean):Object {
        if (!validSourceShape(source)) return fail("invalid_payload");
        var slot:Number = Number(source.slot);
        if (!wholeInRange(slot, 0, 49)) return fail("invalid_slot");
        var checked:Object;
        try {
            var callback:Function = _callbacks == null
                ? null : _callbacks.validateExternalSlotRef;
            checked = typeof callback == "function"
                ? callback(source, checkCount)
                : org.flashNight.arki.item.InventoryPanelService
                    .validateExternalSlotRef(source, checkCount);
        } catch (leaseError) {
            checked = null;
        }
        if (checked == null || checked.success !== true) {
            return fail(checked != null && checked.error != undefined
                ? String(checked.error) : "stale_state");
        }
        if (checked.containerId != "背包"
                || checked.inventory !== _backpackInventory
                || Number(checked.slot) != slot || checked.item == null) {
            return fail("stale_state");
        }
        checked.sourceRevision = readRevision(_backpackInventory);
        checked.sourceSignature =
            transactionItemSignature(checked.item);
        if (checked.sourceRevision < 0) return fail("stale_state");
        return checked;
    }

    private static function sourceStillExact(sourceCheck:Object):Boolean {
        return readRevision(_backpackInventory)
                == Number(sourceCheck.sourceRevision)
            && _backpackInventory.getItem(String(sourceCheck.slot))
                === sourceCheck.item
            && transactionItemSignature(sourceCheck.item)
                == String(sourceCheck.sourceSignature);
    }

    private static function validateEquipmentItem(item:Object,
                                                  slotKey:String):Object {
        if (item == null || typeof item.name != "string"
                || String(item.name) == "") return fail("incompatible_item");
        var itemData:Object = getCandidateItemData(item);
        if (itemData == null || typeof itemData.use != "string") {
            return fail("incompatible_item");
        }
        var useName:String = String(itemData.use);
        if (useName != slotKey
                && !(slotKey == "手枪2" && useName == "手枪")) {
            return fail("incompatible_item");
        }
        if (slotKey == "手雷") {
            if (!finiteNumber(item.value) || Number(item.value) <= 0) {
                return fail("incompatible_item");
            }
        } else {
            if (typeof itemData.type != "string"
                    || (itemData.type != "武器" && itemData.type != "防具")
                    || typeof item.value != "object" || item.value == null) {
                return fail("incompatible_item");
            }
        }
        if (itemData.data == null || typeof itemData.data != "object"
                || !finiteNumber(itemData.data.level)
                || !finiteNumber(root().等级)) {
            return fail("incompatible_item");
        }
        if (Number(itemData.data.level) > Number(root().等级)) {
            return fail("level_locked");
        }
        return {success:true};
    }

    private static function validateDrugItem(item:Object):Object {
        if (item == null || typeof item.name != "string"
                || String(item.name) == ""
                || !finiteNumber(item.value) || Number(item.value) <= 0) {
            return fail("incompatible_item");
        }
        var itemData:Object = getCandidateItemData(item);
        if (itemData == null || typeof itemData.use != "string"
                || String(itemData.use) != "药剂") {
            return fail("incompatible_item");
        }
        return {success:true};
    }

    private static function readDrugCooldown(drugSlot:Number):Object {
        var cooldownKey:String =
            org.flashNight.arki.unit.Action.Skill.ManualCooldownService
                .drugKey(drugSlot);
        var value;
        try {
            var callback:Function = _callbacks == null
                ? null : _callbacks.drugCooldownReady;
            value = typeof callback == "function"
                ? callback(cooldownKey)
                : org.flashNight.arki.unit.Action.Skill
                    .ManualCooldownService.isReady(cooldownKey);
        } catch (cooldownError) {
            return fail("cooldown_unavailable");
        }
        if (value !== true && value !== false) {
            return fail("cooldown_unavailable");
        }
        return value === true ? {success:true} : fail("cooldown_active");
    }

    private static function validDrugSlot(value:Number):Boolean {
        return wholeInRange(value, 0,
            org.flashNight.arki.unit.Action.Skill.DrugInputService
                .SLOT_COUNT - 1);
    }

    private static function firstBackpackVacancy():Number {
        var capacity:Number = Math.min(50,
            Math.floor(Number(_backpackInventory.capacity)));
        for (var slot:Number = 0; slot < capacity; slot++) {
            if (_backpackInventory.getItem(String(slot)) == null) return slot;
        }
        return -1;
    }

    private static function transactionEndpointsReady(source:Object,
                                                      target:Object):Boolean {
        return source != null && target != null
            && typeof source.transactionWrite == "function"
            && typeof source.publishTransactionChange == "function"
            && typeof target.transactionWrite == "function"
            && typeof target.publishTransactionChange == "function";
    }

    private static function invalidateBackpackSlot(slot:Number):Void {
        try {
            var callback:Function = _callbacks == null
                ? null : _callbacks.invalidateExternalSlot;
            if (typeof callback == "function") {
                callback("背包", slot);
            } else {
                org.flashNight.arki.item.InventoryPanelService
                    .invalidateExternalSlot("背包", slot);
            }
        } catch (invalidateError) {
            // raw mutation revision 已使旧 lease fail-closed；显式清理只是缩短寿命。
        }
    }

    private static function markSaveDirty():Void {
        root().存档系统.dirtyMark = true;
    }

    private static function slotIndex(slotKey:String):Number {
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            if (String(SLOT_KEYS[i]) == slotKey) return i;
        }
        return -1;
    }

    private static function validMutationEnvelope(commandName:String,
                                                  params:Object):Boolean {
        if (params == null || typeof params != "object") return false;
        var expectedAction:String =
            mutationActionName(commandName);
        if (expectedAction == ""
                || typeof params.v != "number" || params.v !== 1
                || typeof params.task != "string"
                || params.task != "cmd"
                || typeof params.action != "string"
                || params.action != expectedAction
                || typeof params.callId != "number"
                || !wholeInRange(Number(params.callId),
                    1, 2147483647)
                || !validAsciiToken(params.requestCallId, 96, false)
                || !validAsciiToken(params.panelInstanceId, 128, true)
                || typeof params.writeEpoch != "number"
                || !wholeInRange(Number(params.writeEpoch),
                    1, 2147483647)
                || typeof params.sessionGeneration != "number"
                || !wholeInRange(Number(params.sessionGeneration),
                    1, 2147483647)) {
            return false;
        }
        var allowed:Object = {
            task:true, action:true, v:true, callId:true,
            requestCallId:true, panelInstanceId:true,
            writeEpoch:true, sessionGeneration:true
        };
        if (commandName == "equipEquipment") {
            allowed.expectedLoadoutRevision = true;
            allowed.slotKey = true;
            allowed.source = true;
            if (typeof params.expectedLoadoutRevision != "number"
                    || !wholeInRange(
                        Number(params.expectedLoadoutRevision),
                        0, 2147483647)
                    || typeof params.slotKey != "string"
                    || !validSourceShape(params.source)) return false;
        } else if (commandName == "unequipEquipment") {
            allowed.expectedLoadoutRevision = true;
            allowed.slotKey = true;
            if (typeof params.expectedLoadoutRevision != "number"
                    || !wholeInRange(
                        Number(params.expectedLoadoutRevision),
                        0, 2147483647)
                    || typeof params.slotKey != "string") return false;
        } else if (commandName == "equipDrug") {
            allowed.expectedDrugRevision = true;
            allowed.drugSlot = true;
            allowed.source = true;
            if (typeof params.expectedDrugRevision != "number"
                    || !wholeInRange(Number(params.expectedDrugRevision),
                        0, 2147483647)
                    || typeof params.drugSlot != "number"
                    || !wholeNumber(params.drugSlot)
                    || !validSourceShape(params.source)) return false;
        } else if (commandName == "unequipDrug") {
            allowed.expectedDrugRevision = true;
            allowed.drugSlot = true;
            if (typeof params.expectedDrugRevision != "number"
                    || !wholeInRange(Number(params.expectedDrugRevision),
                        0, 2147483647)
                    || typeof params.drugSlot != "number"
                    || !wholeNumber(params.drugSlot)) return false;
        } else {
            return false;
        }
        for (var key:String in params) {
            if (allowed[key] !== true) return false;
        }
        return true;
    }

    private static function mutationActionName(commandName:String):String {
        if (commandName == "equipEquipment") {
            return "characterBuildEquipEquipment";
        }
        if (commandName == "unequipEquipment") {
            return "characterBuildUnequipEquipment";
        }
        if (commandName == "equipDrug") {
            return "characterBuildEquipDrug";
        }
        if (commandName == "unequipDrug") {
            return "characterBuildUnequipDrug";
        }
        return "";
    }

    private static function validAsciiToken(value, maximum:Number,
                                            allowTilde:Boolean):Boolean {
        if (typeof value != "string"
                || value.length < 1 || value.length > maximum) {
            return false;
        }
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            var allowed:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 90)
                || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 95
                || (allowTilde && code == 126);
            if (!allowed) return false;
        }
        return true;
    }

    private static function validSourceShape(source:Object):Boolean {
        if (source == null || typeof source != "object"
                || typeof source.containerId != "string"
                || String(source.containerId) != "背包"
                || !wholeNumber(source.slot)
                || typeof source.expectedLease != "string"
                || String(source.expectedLease) == "") return false;
        var allowed:Object = {
            containerId:true, slot:true, expectedLease:true
        };
        for (var key:String in source) {
            if (allowed[key] !== true) return false;
        }
        return true;
    }

    private static function validBackpackSnapshot(value:Object):Boolean {
        return value != null && typeof value == "object"
            && String(value.containerId) == "背包"
            && value.slots instanceof Array;
    }

    private static function transactionItemSignature(item:Object):String {
        if (item == null) return "empty";
        if (typeof item != "object" || typeof item.name != "string") {
            return "invalid";
        }
        var value = item.value;
        if (typeof value == "number") {
            return "stack|" + stringToken(String(item.name))
                + "|" + valueToken(value)
                + "|" + valueToken(item.lastUpdate);
        }
        if (typeof value == "object" && value != null) {
            return "equipment|" + stringToken(String(item.name))
                + "|" + valueToken(value.level)
                + "|" + valueToken(value.tier)
                + "|" + modifierToken(value.mods)
                + "|" + valueToken(item.lastUpdate);
        }
        return "invalid|" + stringToken(String(item.name));
    }

    private static function executeStatsSnapshot(params:Object):Object {
        var identity:Object = panelGate(String(params.panelInstanceId));
        if (!identity.success) return identity;
        var current:Object = synchronize(Number(params.sessionGeneration));
        if (!current.success) return current;
        if (!expectedRevisionMatches(params.expectedLoadoutRevision,
                _loadoutRevision)
                || !expectedRevisionMatches(params.expectedLiveRevision,
                    _liveRevision)) {
            return fail("stale_state");
        }
        if (_liveRefreshDirty || _liveRevision != _loadoutRevision) {
            return fail("live_not_clean");
        }

        var stats:Object = null;
        try {
            var callback:Function = _callbacks == null
                ? null : _callbacks.statsSnapshot;
            stats = typeof callback == "function"
                ? callback()
                : org.flashNight.arki.unit.PlayerInfoProvider
                    .getPlayerInfoSnapshot();
        } catch (statsError) {
            return fail("stats_failed");
        }
        if (stats == null || Number(stats.v) != 1
                || typeof stats.stateHealth != "string"
                || !(stats.diagnostics instanceof Array)
                || !(stats.groups instanceof Array)) {
            return fail("stats_failed");
        }
        if (stats.stateHealth != "ok") return fail("stats_unavailable");
        current.payload = stats;
        return current;
    }

    private static function executeFlushLive(params:Object):Object {
        var identity:Object = panelGate(String(params.panelInstanceId));
        if (!identity.success) return identity;
        return flushLive(Number(params.sessionGeneration),
            Number(params.expectedLoadoutRevision));
    }

    private static function executeFinalize(params:Object):Object {
        var identity:Object = panelGate(String(params.panelInstanceId));
        if (!identity.success) return identity;
        return finalize(Number(params.sessionGeneration),
            Number(params.expectedLoadoutRevision));
    }

    private static function attachSnapshotProjection(current:Object):Object {
        var diagnostics:Array = [];
        var equipment:Array = buildEquipmentProjection(diagnostics);
        var drugs:Array = buildDrugProjection(diagnostics);
        var portrait:Object = buildPortraitProjection(diagnostics);
        current.payload = {
            equipment:equipment,
            drugs:drugs,
            portrait:portrait,
            stateHealth:diagnostics.length == 0 ? "ok" : "degraded",
            diagnostics:diagnostics
        };
        return current;
    }

    private static function buildEquipmentProjection(
        diagnostics:Array):Array {
        var rows:Array = [];
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            var item:Object = _slotRefs[i];
            var row:Object = {
                slotKey:String(SLOT_KEYS[i]),
                label:String(SLOT_LABELS[i]),
                occupied:item != null
            };
            if (item != null) {
                row.item = buildSafeItemProjection(
                    item, diagnostics, "equipment:" + SLOT_KEYS[i]);
            }
            rows.push(row);
        }
        return rows;
    }

    private static function buildDrugProjection(diagnostics:Array):Array {
        var rows:Array = [];
        var r:Object = root();
        var count:Number =
            org.flashNight.arki.unit.Action.Skill.DrugInputService.SLOT_COUNT;
        for (var slot:Number = 0; slot < count; slot++) {
            var item:Object = null;
            try {
                item = _drugInventory.getItem(String(slot));
            } catch (drugReadError) {
                diagnostics.push("drug_read_failed:" + slot);
            }
            var cooldown:Object = null;
            var cooldownFailed:Boolean = false;
            try {
                var cooldownCallback:Function = _callbacks == null
                    ? null : _callbacks.cooldownSnapshot;
                if (typeof cooldownCallback == "function") {
                    cooldown = cooldownCallback(slot);
                } else {
                    var cooldownKey:String =
                        org.flashNight.arki.unit.Action.Skill
                            .ManualCooldownService.drugKey(slot);
                    cooldown =
                        org.flashNight.arki.unit.Action.Skill
                            .ManualCooldownService.getSnapshot(cooldownKey);
                }
            } catch (cooldownError) {
                cooldownFailed = true;
            }
            if (cooldown == null || typeof cooldown != "object") {
                cooldownFailed = true;
            }
            if (cooldownFailed) {
                diagnostics.push("drug_cooldown_unavailable:" + slot);
                cooldown = {
                    ready:false,
                    totalSteps:0,
                    currentStep:0,
                    progressPercent:0,
                    animationFrame:1
                };
            }
            var ready:Boolean = cooldown.ready === true;
            var totalSteps:Number = safeWhole(cooldown.totalSteps);
            var currentStep:Number = safeWhole(cooldown.currentStep);
            var remainingSteps:Number = Math.max(0,
                totalSteps - currentStep);
            var remainingMs:Number = ready ? 0 : remainingSteps
                * org.flashNight.arki.unit.Action.Skill.ManualCooldownService
                    .FRAME_MS;
            var keyName:String =
                org.flashNight.arki.unit.Action.Skill.DrugInputService
                    .getKeyName(slot);
            var keyLabel:String = "";
            try {
                var keyCode:Number = Number(r[keyName]);
                if (!isNaN(keyCode) && typeof r.keyshow == "function") {
                    var resolvedLabel = r.keyshow(keyCode);
                    if (resolvedLabel != undefined && resolvedLabel != null
                            && String(resolvedLabel) != "") {
                        keyLabel = String(resolvedLabel);
                    } else {
                        diagnostics.push("drug_key_unavailable:" + slot);
                    }
                } else {
                    diagnostics.push("drug_key_unavailable:" + slot);
                }
            } catch (keyError) {
                diagnostics.push("drug_key_unavailable:" + slot);
            }

            var quantity:Number = 0;
            if (item != null) {
                quantity = Number(item.value);
                if (isNaN(quantity)) {
                    quantity = 0;
                    diagnostics.push("drug_quantity_invalid:" + slot);
                }
            }
            var row:Object = {
                slot:slot,
                keyLabel:keyLabel,
                ready:ready,
                totalSteps:totalSteps,
                currentStep:currentStep,
                progressPercent:safeWhole(cooldown.progressPercent),
                animationFrame:safeWhole(cooldown.animationFrame),
                remainingMs:remainingMs,
                occupied:item != null,
                quantity:quantity
            };
            if (item != null) {
                row.item = buildSafeItemProjection(
                    item, diagnostics, "drug:" + slot);
            }
            rows.push(row);
        }
        return rows;
    }

    private static function buildPortraitProjection(
        diagnostics:Array):Object {
        var r:Object = root();
        var hero:Object = null;
        if (r.gameworld != null && r.控制目标 != undefined) {
            hero = r.gameworld[r.控制目标];
        }
        var genderValue = hero != null && hero.性别 != undefined
            ? hero.性别 : r.性别;
        var gender:String = String(genderValue);
        if (gender != "男" && gender != "女") {
            diagnostics.push("unknown_gender");
            gender = "男";
        }

        var equipment:Object = {};
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            var item:Object = _slotRefs[i];
            if (item != null && typeof item.name == "string") {
                equipment[String(SLOT_KEYS[i])] = String(item.name);
            }
        }
        var appearance:Object = {};
        var face = hero != null && hero.脸型 != undefined
            ? hero.脸型 : r.脸型;
        var hair = hero != null && hero.发型 != undefined
            ? hero.发型 : r.发型;
        if (face != undefined && face != null && String(face) != "") {
            appearance["脸型"] = String(face);
        }
        if (hair != undefined && hair != null && String(hair) != "") {
            appearance["发型"] = String(hair);
        }
        return {gender:gender, equipment:equipment, appearance:appearance};
    }

    private static function buildSafeItemProjection(
        item:Object, diagnostics:Array, context:String):Object {
        var projection:Object = null;
        try {
            var callback:Function = _callbacks == null
                ? null : _callbacks.projectItem;
            projection = typeof callback == "function"
                ? callback(item)
                : org.flashNight.arki.item.InventoryPanelService
                    .buildItemProjection(item);
        } catch (projectionError) {
        }
        if (projection == null || typeof projection != "object") {
            diagnostics.push("item_projection_failed:" + context);
            projection = {};
        }
        return normalizeItemProjection(item, projection);
    }

    /**
     * loadout wire 固定复用 inventory 的 22 字段投影。测试 callback 或异常 fallback
     * 也必须产出同形状，Host 无需为测试替身或降级分支放宽协议。
     */
    private static function normalizeItemProjection(
        item:Object, projection:Object):Object {
        var equipmentLike:Boolean = item != null
            && typeof item.value == "object" && item.value != null;
        var quantity:Number = equipmentLike ? 1 : Number(item.value);
        if (!finiteNumber(quantity)) quantity = 0;
        var enhancementLevel:Number = equipmentLike
            ? safeWhole(item.value.level) : 0;
        var setOrder:Number = finiteNumber(projection.setOrder)
            ? Math.max(0, Math.floor(Number(projection.setOrder))) : 0;
        var maxEnhancementLevel:Number =
            finiteNumber(projection.maxEnhancementLevel)
                ? Math.max(0, Math.floor(
                    Number(projection.maxEnhancementLevel)))
                : (equipmentLike
                    ? org.flashNight.arki.item.EquipmentUtil.getMaxLevel()
                    : 0);
        var modSlotCapacity:Number = finiteNumber(projection.modSlotCapacity)
            ? Math.max(0, Math.floor(Number(projection.modSlotCapacity))) : 0;
        var modSlotUsed:Number = finiteNumber(projection.modSlotUsed)
            ? Math.max(0, Math.floor(Number(projection.modSlotUsed))) : 0;
        var modSlots:Array = equipmentLike
                && projection.modSlots instanceof Array
            ? projection.modSlots.slice(0, 3) : [];
        if (modSlotUsed < modSlots.length) modSlotUsed = modSlots.length;
        var tierSlotUsed:Boolean = equipmentLike
            && projection.tierSlotUsed === true;
        var tierSlotAvailable:Boolean = equipmentLike
            && (projection.tierSlotAvailable === true || tierSlotUsed);
        if (!equipmentLike) {
            modSlotCapacity = 0;
            modSlotUsed = 0;
        }
        var result:Object = {
            name:item == null ? "" : String(item.name),
            displayName:projection.displayName == undefined
                || projection.displayName == null
                || String(projection.displayName) == ""
                    ? (item == null ? "" : String(item.name))
                    : String(projection.displayName),
            icon:projection.icon == undefined || projection.icon == null
                    || String(projection.icon) == ""
                ? (item == null ? "" : String(item.name))
                : String(projection.icon),
            majorType:projection.majorType == undefined
                || projection.majorType == null
                    ? "" : String(projection.majorType),
            use:projection.use == undefined || projection.use == null
                ? "" : String(projection.use),
            actionType:projection.actionType == undefined
                || projection.actionType == null
                    ? "" : String(projection.actionType),
            weaponType:projection.weaponType == undefined
                || projection.weaponType == null
                    ? "" : String(projection.weaponType),
            setId:projection.setId == undefined || projection.setId == null
                ? "" : String(projection.setId),
            setName:projection.setName == undefined
                || projection.setName == null
                    ? "" : String(projection.setName),
            setOrder:setOrder,
            itemKind:equipmentLike ? "equipment" : "stack",
            quantity:quantity,
            enhancementLevel:enhancementLevel,
            maxEnhancementLevel:maxEnhancementLevel,
            isMaxEnhancement:equipmentLike
                && enhancementLevel >= maxEnhancementLevel,
            tierSlotAvailable:tierSlotAvailable,
            tierSlotUsed:tierSlotUsed,
            modSlotCapacity:modSlotCapacity,
            modSlotUsed:modSlotUsed,
            modSlots:modSlots,
            modMeta:projection.modMeta != null
                && typeof projection.modMeta == "object"
                    ? projection.modMeta : null,
            rarity:projection.rarity == undefined
                || projection.rarity == null
                    ? "" : String(projection.rarity)
        };
        if (projection.balanceSummary != null
                && typeof projection.balanceSummary == "object") {
            result.balanceSummary = projection.balanceSummary;
        }
        return result;
    }

    private static function buildBackpackSnapshot():Object {
        try {
            var callback:Function = _callbacks == null
                ? null : _callbacks.buildBackpackSnapshot;
            if (typeof callback == "function") return callback();
            return org.flashNight.arki.item.InventoryPanelService
                .buildExternalSnapshot("背包", 0, 50);
        } catch (snapshotError) {
            return null;
        }
    }

    /**
     * 候选资格只读取 getItemData(item.name)，不信 item 实例上的 use/type/level。
     * 返回 null 交给调用方记录 diagnostics 并排除，禁止猜测兼容性。
     */
    private static function getCandidateItemData(item:Object):Object {
        try {
            var r:Object = root();
            var data:Object = typeof r.getItemData == "function"
                ? r.getItemData(item.name)
                : org.flashNight.arki.item.ItemUtil.getItemData(item.name);
            return data == null || typeof data != "object" ? null : data;
        } catch (itemDataError) {
            return null;
        }
    }

    private static function expectedRevisionMatches(value,
                                                     current:Number):Boolean {
        if (value == undefined || value == null || String(value) == "") {
            return false;
        }
        var numeric:Number = Number(value);
        return wholeNumber(numeric) && numeric == current;
    }

    private static function commonResponse(commandName:String,
                                            params:Object,
                                            result:Object):Object {
        if (result == null) result = fail("internal_error");
        var response:Object = {
            task:"loadout_response",
            v:1,
            success:result.success === true,
            callId:params == undefined ? undefined : params.callId,
            requestCallId:params == undefined
                ? undefined : params.requestCallId,
            command:commandName,
            panelInstanceId:params == undefined
                ? undefined : params.panelInstanceId,
            writeEpoch:params == undefined ? undefined : params.writeEpoch,
            sessionGeneration:result.sessionGeneration == undefined
                ? _sessionGeneration : result.sessionGeneration,
            loadoutRevision:result.loadoutRevision == undefined
                ? _loadoutRevision : result.loadoutRevision,
            liveRevision:result.liveRevision == undefined
                ? _liveRevision : result.liveRevision,
            drugRevision:result.drugRevision == undefined
                ? _drugRevision : result.drugRevision,
            liveRefreshDirty:result.liveRefreshDirty == undefined
                ? _liveRefreshDirty : result.liveRefreshDirty,
            active:result.active == undefined ? _active : result.active
        };
        if (result.error != undefined) response.error = result.error;
        if (commandName == "snapshot" || commandName == "candidates"
                || commandName == "statsSnapshot"
                || commandName == "equipEquipment"
                || commandName == "unequipEquipment"
                || commandName == "equipDrug"
                || commandName == "unequipDrug") {
            if (result.payload != undefined) response.payload = result.payload;
        }
        if (result.reconcileAfterCallId != undefined) {
            response.reconcileAfterCallId = result.reconcileAfterCallId;
        }
        if (result.inventorySnapshots != undefined) {
            response.inventorySnapshots = result.inventorySnapshots;
        }
        if (commandName == "equipEquipment"
                || commandName == "unequipEquipment"
                || commandName == "equipDrug"
                || commandName == "unequipDrug") {
            if (result.success === true) {
                response.changed = result.changed === true;
                if (result.operation != undefined) {
                    response.operation = result.operation;
                }
                if (result.affectedBackpackSlot != undefined) {
                    response.affectedBackpackSlot =
                        result.affectedBackpackSlot;
                }
            }
        }
        if (commandName == "flushLive") {
            response.changed = result.changed === true;
        }
        if (commandName == "finalize") {
            response.closed = result.closed === true;
            response.liveChanged = result.liveChanged === true;
            response.persistence = result.persistence == null
                ? {success:false, changed:false}
                : {
                    success:result.persistence.success === true,
                    changed:result.persistence.changed === true
                };
        }
        return response;
    }

    private static function sendResponse(response:Object):Void {
        var r:Object = root();
        if (r.server == undefined
                || typeof r.server.sendSocketMessage != "function") return;
        if (_json == undefined) _json = new LiteJSON();
        r.server.sendSocketMessage(_json.stringify(response));
    }

    private static function resolveContainers():Object {
        var r:Object = root();
        if (r == null || r.物品栏 == null) {
            return {success:false, error:"service_not_ready"};
        }
        var equipment:Object = r.物品栏.装备栏;
        var drugs:Object = r.物品栏.药剂栏;
        var backpack:Object = r.物品栏.背包;
        if (equipment == null || typeof equipment.getItem != "function"
                || drugs == null || typeof drugs.getMutationRevision != "function"
                || typeof drugs.getItem != "function"
                || backpack == null || typeof backpack.getItem != "function"
                || typeof backpack.getMutationRevision != "function"
                || isNaN(Number(backpack.capacity))
                || Number(backpack.capacity) < 0
                || Math.floor(Number(backpack.capacity))
                    != Number(backpack.capacity)) {
            return {success:false, error:"service_not_ready"};
        }
        return {success:true, equipment:equipment, drugs:drugs,
            backpack:backpack};
    }
    private static function readRevision(container:Object):Number {
        try {
            var value:Number = Number(container.getMutationRevision());
            if (isNaN(value) || Math.floor(value) != value || value < 0) return -1;
            return value;
        } catch (error) {
            return -1;
        }
    }
    private static function sessionGate(expectedGeneration:Number):Object {
        if (!_active) return fail("session_not_active");
        if (_stale) return fail(_staleError);
        if (isNaN(expectedGeneration)
                || Math.floor(expectedGeneration) != expectedGeneration
                || expectedGeneration != _sessionGeneration) {
            return fail("stale_session");
        }
        return {success:true};
    }
    private static function panelGate(panelInstanceId:String):Object {
        if (panelInstanceId == null || panelInstanceId == ""
                || panelInstanceId == "undefined") {
            return fail("invalid_payload");
        }
        if (_panelInstanceId == "" || panelInstanceId != _panelInstanceId) {
            return fail("stale_panel_instance");
        }
        return {success:true};
    }
    private static function poison(errorCode:String):Object {
        _stale = true;
        _staleError = errorCode;
        return fail(errorCode);
    }
    private static function state(success:Boolean,
                                  loadoutChanged:Boolean,
                                  drugChanged:Boolean):Object {
        return {
            success:success,
            v:1,
            active:_active,
            sessionGeneration:_sessionGeneration,
            loadoutRevision:_loadoutRevision,
            liveRevision:_liveRevision,
            liveRefreshDirty:_liveRefreshDirty,
            drugRevision:_drugRevision,
            loadoutChanged:loadoutChanged,
            drugChanged:drugChanged,
            slotKeys:SLOT_KEYS.concat()
        };
    }
    private static function fail(errorCode:String):Object {
        var result:Object = state(false, false, false);
        result.error = errorCode;
        return result;
    }
    private static function inactiveFail(errorCode:String):Object {
        return {
            success:false,
            v:1,
            active:false,
            sessionGeneration:0,
            error:errorCode
        };
    }
    private static function rejectOpen(errorCode:String):Object {
        clearSession();
        _panelInstanceId = "";
        _finalizeReceipt = null;
        return inactiveFail(errorCode);
    }
    private static function invokeBoolean(name:String):Object {
        var callback:Function = _callbacks == null ? null : _callbacks[name];
        try {
            var value;
            if (typeof callback == "function") {
                value = callback();
            } else {
                var saveManager:Object =
                    org.flashNight.neur.Server.SaveManager.getInstance();
                if (saveManager == null) return {known:false};
                if (name == "isGlobalDirty") {
                    value = saveManager.hasPendingChanges();
                } else if (name == "flushNow") {
                    value = saveManager.flushNow();
                } else {
                    return {known:false};
                }
            }
            if (value === true) return {known:true, value:true};
            if (value === false) return {known:true, value:false};
            return {known:false};
        } catch (error) {
            return {known:false};
        }
    }
    private static function replayFinalizeReceipt(
        expectedGeneration:Number,
        expectedLoadoutRevision:Number):Object {
        if (_active || _finalizeReceipt == null) return null;
        if (expectedGeneration !== _finalizeReceipt.generation
                || expectedLoadoutRevision
                    !== _finalizeReceipt.expectedLoadoutRevision) {
            return null;
        }
        return copyFinalizeReceipt(_finalizeReceipt);
    }
    private static function rememberFinalizeSuccess(
        expectedGeneration:Number,
        expectedLoadoutRevision:Number,
        liveChanged:Boolean,
        persistenceChanged:Boolean):Object {
        var proof:Object = state(true, false, false);
        proof.operation = "finalize";
        proof.closed = true;
        proof.liveChanged = liveChanged;
        proof.persistence = {success:true, changed:persistenceChanged};
        _finalizeReceipt = {
            generation:expectedGeneration,
            expectedLoadoutRevision:expectedLoadoutRevision,
            proof:proof
        };
        return copyFinalizeReceipt(_finalizeReceipt);
    }
    private static function copyFinalizeReceipt(receipt:Object):Object {
        var proof:Object = receipt.proof;
        return {
            success:proof.success,
            v:proof.v,
            active:proof.active,
            sessionGeneration:proof.sessionGeneration,
            loadoutRevision:proof.loadoutRevision,
            liveRevision:proof.liveRevision,
            liveRefreshDirty:proof.liveRefreshDirty,
            drugRevision:proof.drugRevision,
            loadoutChanged:proof.loadoutChanged,
            drugChanged:proof.drugChanged,
            slotKeys:proof.slotKeys.concat(),
            operation:proof.operation,
            closed:proof.closed,
            liveChanged:proof.liveChanged,
            persistence:{
                success:proof.persistence.success,
                changed:proof.persistence.changed
            }
        };
    }
    private static function finalizeFailure(result:Object,
                                            liveChanged:Boolean):Object {
        result.operation = "finalize";
        result.closed = false;
        result.active = _active;
        result.liveChanged = liveChanged;
        result.persistence = {success:false, changed:false};
        return result;
    }
    private static function liveResult(changed:Boolean):Object {
        var result:Object = state(true, false, false);
        result.operation = "flushLive";
        result.changed = changed;
        return result;
    }
    private static function liveFailure():Object {
        var result:Object = fail("flush_failed");
        result.operation = "flushLive";
        result.changed = false;
        return result;
    }
    private static function liveBaselineAligned(r:Object, refs:Array):Boolean {
        try {
            if (r == null || typeof r.控制目标 != "string" || r.gameworld == null) {
                return false;
            }
            var hero:Object = r.gameworld[r.控制目标];
            if (hero == null || hero._name !== r.控制目标
                    || hero._parent !== r.gameworld
                    || !validDispatcher(hero.dispatcher)
                    || !validBuffManager(hero.buffManager)
                    || !validLiveTail(hero)) return false;
            for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
                if (hero[SLOT_KEYS[i]] !== refs[i]
                        || !validDerived(hero[SLOT_DATA_KEYS[i]], refs[i])) return false;
            }
            return true;
        } catch (error) {
            return false;
        }
    }
    /**
     * B0 spike 的同步刷新前置证明器，不是生产完成声明。
     * 真实 MovieClip/装扮生命周期仍须新鲜 Flash smoke 验证。
     */
    private static function liveContext(r:Object, refs:Array):Object {
        if (r == null || typeof r.控制目标 != "string" || r.控制目标.length == 0
                || r.gameworld == null || typeof r.刷新人物装扮 != "function"
                || refs == null || refs.length != SLOT_KEYS.length) {
            return null;
        }
        var hero:Object = r.gameworld[r.控制目标];
        if (hero == null || hero._name !== r.控制目标 || hero._parent !== r.gameworld
                || hero.aabbCollider == null
                || !validDispatcher(hero.dispatcher)
                || !validBuffManager(hero.buffManager)
                || (hero.新版人物文字信息 == null && hero.人物文字信息 == null)
                || typeof hero.读取基础被动效果 != "function"
                || hero.buff == null || typeof hero.buff.初始 != "function"
                || typeof hero.buff.更新 != "function"
                || typeof hero.gotoAndStop != "function"
                || typeof hero.根据模式重新读取武器加成 != "function"
                || typeof hero.装载主动战技 != "function"
                || typeof hero.装载生命周期函数 != "function"
                || typeof hero.完成生命周期函数装载 != "function"
                || (hero.dressupRegistry != null && hero.syncRefs == null)
                || hero.dressupRefreshing === true) return null;
        if (r.装备引用配置 == null
                || typeof r.装备引用配置.刷新所有装扮 != "function"
                || typeof r.根据等级计算值 != "function"
                || r.主角函数 == null
                || typeof r.主角函数.创建主动战技槽位表 != "function"
                || typeof r.主角函数.获取装备主动战技种类 != "function"
                || r.敌人函数 == null
                || !(r.敌人函数.魔法伤害种类 instanceof Array)
                || r.玩家信息界面 == null
                || typeof r.玩家信息界面.刷新攻击模式 != "function"
                || r.UI系统 == null || r.UI系统.iconBar == null
                || typeof r.UI系统.iconBar.initialize != "function") return null;
        var oldDataRefs:Array = [];
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            var item:Object = refs[i];
            if (item != null && typeof item.getData != "function") return null;
            oldDataRefs[i] = hero[SLOT_DATA_KEYS[i]];
        }
        return {root:r, controlTarget:r.控制目标, gameworld:r.gameworld, hero:hero,
            oldDispatcher:hero.dispatcher, oldBuffManager:hero.buffManager,
            oldDataRefs:oldDataRefs};
    }
    /**
     * B0 spike 的刷新后置证明器；真实后置门必须保留。
     * 该反例集合不能替代真实 Flash 中的 dispatcher/buff/装扮 smoke。
     */
    private static function livePostcondition(context:Object):Boolean {
        var r:Object = context.root;
        if (r.控制目标 !== context.controlTarget || r.gameworld !== context.gameworld
                || r.物品栏 == null
                || r.物品栏.装备栏 !== _equipmentInventory) return false;
        var hero:Object = r.gameworld[context.controlTarget];
        if (hero !== context.hero || hero._parent !== context.gameworld
                || hero.dispatcher === context.oldDispatcher
                || hero.buffManager === context.oldBuffManager
                || !validDispatcher(hero.dispatcher)
                || !validBuffManager(hero.buffManager)) return false;
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            if (_equipmentInventory.getItem(SLOT_KEYS[i]) !== _slotRefs[i]) return false;
            if (hero[SLOT_KEYS[i]] !== _slotRefs[i]) return false;
            var data:Object = hero[SLOT_DATA_KEYS[i]];
            if (_slotRefs[i] == null) {
                if (data != null) return false;
            } else if (data === context.oldDataRefs[i]
                    || !validDerived(data, _slotRefs[i])) {
                return false;
            }
        }
        return validLiveTail(hero);
    }
    private static function validDerived(data:Object, item:Object):Boolean {
        if (item == null) return data == null;
        return data != null && typeof data == "object"
            && data.data != null && typeof data.data == "object"
            && typeof data.use == "string";
    }
    private static function validDispatcher(value:Object):Boolean {
        return value != null && typeof value.publish == "function"
            && typeof value.subscribe == "function" && typeof value.destroy == "function";
    }
    private static function validBuffManager(value:Object):Boolean {
        return value != null && typeof value.update == "function"
            && typeof value.addBuff == "function" && typeof value.removeBuff == "function"
            && typeof value.destroy == "function";
    }
    private static function validLiveTail(hero:Object):Boolean {
        return finiteNumber(hero.重量) && finiteNumber(hero.行走X速度)
            && finiteNumber(hero.hp满血值) && finiteNumber(hero.mp满血值)
            && finiteNumber(hero.防御力)
            && hero.魔法抗性 != null && typeof hero.魔法抗性 == "object"
            && hero.主动战技 != null && typeof hero.主动战技 == "object"
            && (hero.生命周期函数列表 instanceof Array)
            && hero.格斗架势 === false && hero.dressupRefreshing !== true;
    }
    private static function finiteNumber(value):Boolean {
        return typeof value == "number" && !isNaN(value)
            && value != Number.POSITIVE_INFINITY && value != Number.NEGATIVE_INFINITY;
    }
    private static function wholeNumber(value):Boolean {
        return typeof value == "number" && !isNaN(value)
            && Math.floor(value) == value;
    }
    private static function wholeInRange(value:Number,
                                         minimum:Number,
                                         maximum:Number):Boolean {
        return wholeNumber(value) && value >= minimum && value <= maximum;
    }
    private static function safeWhole(value):Number {
        var numeric:Number = Number(value);
        return isNaN(numeric) ? 0 : Math.max(0, Math.floor(numeric));
    }
    private static function scanLoadout(inventory:Object):Object {
        var refs:Array = [];
        var parts:Array = ["slots", SLOT_KEYS.length];
        var liveParts:Array = ["slots", SLOT_KEYS.length];
        try {
            for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
                var key:String = String(SLOT_KEYS[i]);
                var item:Object = inventory.getItem(key);
                refs[i] = item;
                parts.push("k", stringToken(key));
                liveParts.push("k", stringToken(key));
                if (item == null) {
                    parts.push("empty");
                    liveParts.push("empty");
                    continue;
                }
                if (typeof item != "object" || typeof item.name != "string") {
                    return {success:false, error:"invalid_loadout"};
                }
                parts.push("item", valueToken(item.name));
                liveParts.push("item", valueToken(item.name));
                var value = item.value;
                if (typeof value == "number") {
                    parts.push("stack", valueToken(value));
                    liveParts.push("stack");
                } else if (typeof value == "object" && value != null) {
                    var mods:String = modifierToken(value.mods);
                    parts.push("equipment", valueToken(value.level), valueToken(value.tier),
                        mods, valueToken(item.lastUpdate));
                    liveParts.push("equipment", valueToken(value.level),
                        valueToken(value.tier), mods);
                } else {
                    return {success:false, error:"invalid_loadout"};
                }
            }
        } catch (error) {
            return {success:false, error:"invalid_loadout"};
        }
        return {success:true, refs:refs, signature:parts.join("|"),
            liveSignature:liveParts.join("|")};
    }
    private static function sameRefs(left:Array, right:Array):Boolean {
        if (left == null || right == null || left.length != SLOT_KEYS.length
                || right.length != SLOT_KEYS.length) return false;
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            if (left[i] !== right[i]) return false;
        }
        return true;
    }
    private static function modifierToken(mods):String {
        var values:Array = [];
        var i:Number;
        if (mods instanceof Array) {
            values.push("array", mods.length);
            for (i = 0; i < mods.length; i++) values.push(valueToken(mods[i]));
            return values.join(",");
        }
        if (typeof mods == "object" && mods != null) {
            var keys:Array = [];
            for (var key:String in mods) keys.push(String(key));
            keys.sort();
            values.push("object", keys.length);
            for (i = 0; i < keys.length; i++) {
                var sortedKey:String = String(keys[i]);
                values.push(stringToken(sortedKey), valueToken(mods[sortedKey]));
            }
            return values.join(",");
        }
        return "other," + valueToken(mods);
    }
    private static function valueToken(value):String {
        if (value == undefined) return "u";
        if (value == null) return "z";
        var typeName:String = typeof value;
        if (typeName == "string") return "s" + stringToken(String(value));
        if (typeName == "number") {
            if (isNaN(value)) return "n:NaN";
            if (value == Number.POSITIVE_INFINITY) return "n:+Inf";
            if (value == Number.NEGATIVE_INFINITY) return "n:-Inf";
            return "n:" + String(value);
        }
        if (typeName == "boolean") return value ? "b:1" : "b:0";
        return typeName + ":" + stringToken(String(value));
    }
    private static function stringToken(value:String):String {
        return value.length + ":" + value;
    }

    private static function clearSession():Void {
        _sessionGeneration = 0;
        _active = false;
        _stale = false;
        _staleError = "";
        _equipmentInventory = null;
        _drugInventory = null;
        _backpackInventory = null;
        _slotRefs = null;
        _signature = null;
        _liveSignature = null;
        _loadoutRevision = 0;
        _liveRevision = 0;
        _drugRevision = 0;
        _drugRawRevision = 0;
        _liveRefreshDirty = false;
        _writeInProgress = false;
        _writeAuthorityTouched = false;
        _capturedPauseLease = undefined;
        _hostPauseReleaseProven = false;
    }

    public static function testOnlyUseRoot(value:Object):Void {
        _testRoot = value;
        _callbacks = null;
        _inited = false;
        _json = null;
        _generationCounter = 0;
        _panelInstanceId = "";
        _finalizeReceipt = null;
        _testFailNextWornPostcondition = false;
        clearSession();
    }
    public static function testOnlyUseCallbacks(value:Object):Void {
        _callbacks = value;
    }

    public static function testOnlyFailNextWornPostcondition():Void {
        _testFailNextWornPostcondition = true;
    }

    public static function testOnlyReset():Void {
        _testRoot = null;
        _callbacks = null;
        _inited = false;
        _json = null;
        _generationCounter = 0;
        _panelInstanceId = "";
        _finalizeReceipt = null;
        _testFailNextWornPostcondition = false;
        clearSession();
    }
}
