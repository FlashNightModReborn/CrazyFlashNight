import org.flashNight.neur.Server.SettingsCanonical;
import org.flashNight.gesh.object.PersistedSnapshot;

/** Per save-owner authority. Preview is never a persistence projection. */
class org.flashNight.neur.Server.SettingsAuthority {
    private var _metadata:Object;
    private var _owner:Object;
    private var _slot:String;
    private var _epoch:String;
    private var _settings:Object;
    private var _keys:Array;
    private var _canonical:String;
    private var _stateToken:String;
    private var _revision:Number = 0;
    private var _ordinal:Number = 0;
    private var _preview:Object;
    private var _operation:Object;
    private var _rejected:Object = {};
    private var _rejectedOrder:Array = [];
    private var _mutationInProgress:Boolean = false;
    private var _authorityUnknown:Boolean = false;
    private var _confirmedToken:String;
    private var _confirmation:String = "none";
    private var _recoveryObserved:Boolean = false;
    private var _history:Object = {};
    private var _historyOrder:Array = [];
    private var _unknownPauseLease:String;
    private var _hostHold:Object;
    private var _attemptObservations:Object = {};
    public function hasHostHold():Boolean { return _hostHold != null; }
    public function authorityGate(request:Object):Boolean {
        if (!matches(request)) return false;
        if (request.admission == "hold") {
            _hostHold = PersistedSnapshot.cloneData(request);
            if (_unknownPauseLease == undefined) {
                try { _unknownPauseLease = org.flashNight.arki.pause.PauseManager.lease(true, "settings_recovery"); } catch (pauseError) {}
            }
            if (_operation == null || _operation.operationToken !== request.operationToken) {
                if (readRequestedOutcome(request) == null) rejectBeforeEffect(request, "operation_retired_before_effect");
            } else if (_operation.saveAttemptId !== request.saveAttemptId && _operation.applyState == "applied") {
                var notSent:Object = readOutcome();notSent.saveAttemptId = request.saveAttemptId;
                notSent.attemptState = "not_sent";notSent.error = "attempt_retired_before_effect";
                _attemptObservations["attempt." + request.operationToken + "." + request.saveAttemptId] = notSent;
            }
            return true;
        }
        if (request.admission != "release" || _hostHold == null || _authorityUnknown
                || _hostHold.operationToken !== request.operationToken || _hostHold.saveAttemptId !== request.saveAttemptId
                || _hostHold.originMutationRequestDigest !== request.originMutationRequestDigest) return false;
        if (_unknownPauseLease != undefined) {
            try { org.flashNight.arki.pause.PauseManager.releaseLease(_unknownPauseLease); }
            catch (pauseReleaseError) { return false; }
            _unknownPauseLease = undefined;
        }
        _hostHold = null;
        return true;
    }

    public function SettingsAuthority(metadata:Object, owner:Object, slot:String, epoch:String) {
        _metadata = PersistedSnapshot.clone(metadata);
        _owner = owner;
        _slot = slot;
        _epoch = epoch;
    }
    public function sameOwner(owner:Object, slot:String):Boolean { return _owner === owner && _slot === slot; }
    public function epoch():String { return _epoch; }
    public function ownerId():String { return String(_metadata.saveOwnerId); }
    public function contextId():String { return String(_metadata.contextId); }
    public function originDigest():String { return String(_metadata.originNamespaceDigest); }
    public function revision():Number { return _revision; }
    public function stateToken():String { return _stateToken; }
    public function operation():Object { return _operation == null ? null : PersistedSnapshot.clone(_operation); }
    public function hasPreview():Boolean { return _preview != null; }
    public function isUnknown():Boolean { return _authorityUnknown; }
    private function mint(kind:String):String {
        if (_ordinal >= 9007199254740991) throw new Error("settings_identity_exhausted");
        return kind + "." + _epoch + "." + (++_ordinal);
    }
    public function capture(settings:Object, keys:Array):Boolean {
        if (_mutationInProgress || _authorityUnknown) return false;
        var observed:Object = PersistedSnapshot.clone(settings);
        if (_preview != null) {
            observed.setGlobalVolume = _preview.globalVolume;
            observed.setBGMVolume = _preview.bgmVolume;
        }
        var encoded:String = SettingsCanonical.encode(observed, keys, true);
        if (encoded == null) return false;
        if (_canonical == undefined) {
            _settings = observed;
            _keys = PersistedSnapshot.cloneArrayData(keys);
            _canonical = encoded;
            _stateToken = mint("observe");
            return true;
        }
        if (encoded != _canonical) {
            if (_revision >= 9007199254740991) return false;
            _settings = observed;
            _keys = PersistedSnapshot.cloneArrayData(keys);
            _canonical = encoded;
            _stateToken = mint("observe");
            _revision++;
            _confirmedToken = undefined;
            _confirmation = "none";
        }
        return true;
    }
    public function installRecovery(source:String):Void {
        if (_recoveryObserved || _canonical == undefined) return;
        _recoveryObserved = true;
        var mapping:Object = _metadata.recoveryMapping;
        // Host 冷证据只关联真实 SOL 来源；迁移或 shadow 投影不制造匹配。
        if (source != "sol" || _metadata.rawCanonical !== _canonical) return;
        if (_metadata.recoveryConfirmation == "cold_read_exact" && mapping != null
                && mapping.contextId === contextId() && mapping.saveOwnerId === ownerId()
                && mapping.originNamespaceDigest === originDigest() && mapping.slot === _slot) {
            var receipt:Object = mapping.currentAttempt;
            _stateToken = mapping.targetStateToken;
            _operation = {operationToken:mapping.operationToken, sourceAuthorityEpoch:mapping.sourceAuthorityEpoch,
                originMutationRequestDigest:mapping.originMutationRequestDigest, settingsDigest:mapping.settingsDigest,
                targetStateToken:mapping.targetStateToken, targetRevision:mapping.targetRevision,
                saveAttemptId:receipt.saveAttemptId, canonical:_canonical, applyState:"applied", applied:true,
                attemptState:"confirmed", durable:true, confirmation:"cold_read_exact", error:null, resolution:"applied"};
            _confirmedToken = _stateToken;
            _confirmation = "cold_read_exact";
        } else if (_metadata.recoveryConfirmation == "cold_read_current") {
            _confirmedToken = _stateToken; _confirmation = "cold_read_current";
        }
    }
    public function writeAdmission():String {
        if (_metadata.writeAdmission != "allowed") return String(_metadata.writeAdmission);
        if (_mutationInProgress || _authorityUnknown || _hostHold != null) return "blocked_by_operation";
        if (_operation != null && _operation.applyState == "applied" && _operation.durable !== true
                && (_stateToken != _operation.targetStateToken || _canonical != _operation.canonical)) return "blocked_by_operation";
        return "allowed";
    }
    public function projection():Object {
        if (writeAdmission() != "allowed" || _canonical == undefined) throw new Error("settings_projection_blocked");
        return {settings:PersistedSnapshot.clone(_settings), keys:PersistedSnapshot.clone(_keys),
            canonical:_canonical, stateToken:_stateToken, revision:_revision, authorityEpoch:_epoch};
    }
    public function readCommitted():Object {
        return _canonical == undefined ? null : {settings:PersistedSnapshot.clone(_settings), keys:PersistedSnapshot.clone(_keys),
            canonical:_canonical, stateToken:_stateToken, revision:_revision};
    }
    public function beginPreview():Object {
        if (_canonical == undefined || _mutationInProgress || _authorityUnknown) return null;
        if (_preview != null) return _preview.lease;
        _preview = {lease:{id:mint("preview"), contextId:contextId(), authorityEpoch:_epoch, stateToken:_stateToken},
            globalVolume:_settings.setGlobalVolume, bgmVolume:_settings.setBGMVolume};
        return _preview.lease;
    }
    public function restorePreview(lease:Object, audio:Object):Boolean {
        if (lease == null || _preview == null || lease !== _preview.lease || audio == null) return false;
        var globalRestored:Boolean = false;
        var bgmRestored:Boolean = false;
        try { audio.setGlobalVolume(_preview.globalVolume); globalRestored = true; } catch (globalError) {}
        try { audio.setBGMVolume(_preview.bgmVolume); bgmRestored = true; } catch (bgmError) {}
        if (globalRestored && bgmRestored) { _preview = null; return true; }
        return false;
    }
    public function matches(request:Object):Boolean {
        return request.contextId === contextId() && request.saveOwnerId === ownerId()
            && request.authorityEpoch === _epoch;
    }
    public function beginMutation(request:Object, canonical:String):Boolean {
        if (!matches(request) || writeAdmission() != "allowed" || canonical == null
                || (_operation != null && _operation.durable !== true && _operation.applyState != "not_applied")
                || _rejected["operation." + request.operationToken] != null
                || request.expectedCanonical !== canonical || request.baseStateToken !== _stateToken
                || request.expectedRevision !== _revision || _revision >= 9007199254740991) return false;
        if (_operation != null) {
            var historicalKey:String = "operation." + _operation.operationToken;
            _history[historicalKey] = readOutcome(); _historyOrder.push(historicalKey);
            while (_historyOrder.length > 64) delete _history[_historyOrder.shift()];
        }
        _operation = {operationToken:request.operationToken, sourceAuthorityEpoch:_epoch,
            originMutationRequestDigest:request.originMutationRequestDigest, settingsDigest:request.settingsDigest,
            targetStateToken:request.operationToken, saveAttemptId:request.saveAttemptId,
            canonical:canonical, applyState:"unknown", applied:null, attemptState:"in_flight",
            durable:false, confirmation:"none", error:null, resolution:"unresolved"};
        _preview = null;
        _mutationInProgress = true;
        return true;
    }
    public function completeMutation(settings:Object, keys:Array):Boolean {
        if (!_mutationInProgress || _operation == null) return false;
        var encoded:String = SettingsCanonical.encode(settings, keys, true);
        if (encoded !== _operation.canonical) { failMutation(); return false; }
        _settings = PersistedSnapshot.clone(settings);
        _keys = PersistedSnapshot.cloneArrayData(keys);
        _canonical = encoded;
        _revision++;
        _stateToken = _operation.targetStateToken;
        _preview = null;
        _confirmedToken = undefined;
        _confirmation = "none";
        _operation.applyState = "applied";
        _operation.applied = true;
        _operation.resolution = "applied";
        _operation.targetRevision = _revision;
        _mutationInProgress = false;
        return true;
    }
    public function failMutation():Void {
        _mutationInProgress = false;
        _authorityUnknown = true;
        if (_unknownPauseLease == undefined) {
            try { _unknownPauseLease = org.flashNight.arki.pause.PauseManager.lease(true, "settings_recovery"); }
            catch (pauseError) { trace("[SettingsAuthority] pause projection failed; write admission remains closed"); }
        }
        _stateToken = mint("partial");
        _confirmedToken = undefined;
        _confirmation = "none";
        if (_operation != null) {
            _operation.applyState = "unknown";
            _operation.applied = null;
            _operation.attemptState = "unknown";
            _operation.error = "apply_ambiguous";
        }
    }
    public function beginSave(request:Object):Boolean {
        if (!matches(request) || _operation == null || _operation.durable === true || _operation.applyState != "applied"
                || _operation.operationToken !== request.operationToken || _operation.targetStateToken !== request.stateToken
                || _stateToken !== request.stateToken || _revision !== request.expectedRevision
                || _operation.originMutationRequestDigest !== request.originMutationRequestDigest
                || _attemptObservations["attempt." + request.operationToken + "." + request.saveAttemptId] != null
                || _operation.sourceAuthorityEpoch !== request.sourceAuthorityEpoch
                || _operation.settingsDigest !== request.settingsDigest
                || writeAdmission() != "allowed" || _canonical != _operation.canonical) return false;
        _operation.saveAttemptId = request.saveAttemptId;
        _operation.attemptState = "in_flight";
        _operation.error = null;
        return true;
    }
    public function finishSave(confirmed:Boolean):Void {
        if (_operation == null) return;
        if (_operation.durable === true) return;
        _operation.attemptState = confirmed ? "confirmed" : "returned_unconfirmed";
        _operation.error = confirmed ? null : "save_failed";
    }
    public function freezeReceipt(projection:Object):Object {
        if (_operation == null || _operation.applyState != "applied" || _operation.targetStateToken != projection.stateToken
                || _operation.canonical != projection.canonical || projection.authorityEpoch != _epoch) return null;
        return {schema:1, contextId:contextId(), saveOwnerId:ownerId(), originNamespaceDigest:originDigest(),
            sourceAuthorityEpoch:_operation.sourceAuthorityEpoch, stateToken:projection.stateToken,
            // A recovered operation belongs to its original epoch and revision, not this VM's observation revision.
            operationToken:_operation.operationToken, saveAttemptId:_operation.saveAttemptId, revision:_operation.targetRevision,
            originMutationRequestDigest:_operation.originMutationRequestDigest, settingsDigest:_operation.settingsDigest, digestSchema:1};
    }
    public function confirmPacked(projection:Object, receipt:Object):Boolean {
        if (projection == null || projection.authorityEpoch != _epoch || projection.stateToken != _stateToken
                || projection.canonical != _canonical) return false;
        _confirmedToken = _stateToken;
        _confirmation = "flush_true";
        if (_operation != null && _operation.targetStateToken == _stateToken && receipt != null
                && receipt.operationToken == _operation.operationToken && receipt.saveAttemptId == _operation.saveAttemptId) {
            _operation.durable = true;
            _operation.attemptState = "confirmed";
            _operation.confirmation = "flush_true";
            _operation.error = null;
        }
        return true;
    }
    public function state(migrationPending:Boolean):Object {
        var admission:String = writeAdmission();
        var confirmed:Boolean = _confirmedToken !== undefined && _confirmedToken == _stateToken;
        return {revision:_revision, stateToken:_stateToken, persistenceState:_authorityUnknown ? "unknown" : confirmed ? "confirmed" : "unconfirmed",
            durable:confirmed, confirmation:confirmed ? _confirmation : "none", needsSaveRetry:!confirmed && admission == "allowed"
                && _operation != null && _operation.applyState == "applied" && _operation.attemptState != "in_flight",
            migrationPending:migrationPending};
    }
    public function readOutcome():Object {
        if (_operation == null) return emptyOutcome();
        return {operationToken:_operation.operationToken, sourceAuthorityEpoch:_operation.sourceAuthorityEpoch,
            originMutationRequestDigest:_operation.originMutationRequestDigest, targetStateToken:_operation.targetStateToken,
            saveAttemptId:_operation.saveAttemptId, applyState:_operation.applyState, applied:_operation.applied,
            attemptState:_operation.attemptState, durable:_operation.durable === true, confirmation:_operation.confirmation,
            error:_operation.error, resolution:_operation.resolution};
    }
    public function emptyOutcome():Object {
        return {operationToken:null, sourceAuthorityEpoch:null, originMutationRequestDigest:null,
            targetStateToken:null, saveAttemptId:null, applyState:"none", applied:null, attemptState:"none",
            durable:false, confirmation:"none", error:null, resolution:"none"};
    }
    public function rejectBeforeEffect(request:Object, error:String):Object {
        if (_operation != null && _operation.operationToken === request.operationToken) return readOutcome();
        var existing:Object = _rejected["operation." + request.operationToken];
        if (existing != null) return PersistedSnapshot.clone(existing);
        var outcome:Object = {operationToken:request.operationToken, sourceAuthorityEpoch:_epoch,
            originMutationRequestDigest:request.originMutationRequestDigest, targetStateToken:request.operationToken,
            saveAttemptId:request.saveAttemptId, applyState:"not_applied", applied:false,
            attemptState:"not_sent", durable:false, confirmation:"none", error:error, resolution:"not_applied"};
        _rejected["operation." + request.operationToken] = PersistedSnapshot.clone(outcome);
        _rejectedOrder.push("operation." + request.operationToken);
        while (_rejectedOrder.length > 64) delete _rejected[_rejectedOrder.shift()];
        return outcome;
    }
    public function readRequestedOutcome(request:Object):Object {
        var attempt:Object = _attemptObservations["attempt." + request.operationToken + "." + request.saveAttemptId];
        if (attempt != null) return PersistedSnapshot.clone(attempt);
        if (_operation != null && _operation.operationToken === request.operationToken) return readOutcome();
        var rejected:Object = _rejected["operation." + request.operationToken];
        if (rejected == null) rejected = _history["operation." + request.operationToken];
        return rejected == null ? null : PersistedSnapshot.clone(rejected);
    }
}
