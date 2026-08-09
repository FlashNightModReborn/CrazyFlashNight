/**
 * 文件：org/flashNight/arki/audio/AudioBridge.as
 * 说明：Audio Platform v2 的 AS2 严格协议桥。
 *
 * BGM 通过 ServerManager.sendTaskToNode("audio", ...) 与 FastJSON 发送；
 * ServerManager 只对 audio task 将 payload own fields 展平为顶层 exact wire。
 * SFX 使用 S2|session|readyGeneration|batchSequence|id... 帧末合批。
 * connectionGeneration 属于 XMLSocket transport，禁止进入本类 wire/state。
 */

import org.flashNight.neur.Server.ServerManager;

class org.flashNight.arki.audio.AudioBridge {
    private static var _sm:Object;

    private static var _status:String = "disconnected";
    private static var _audioSessionId:String = null;
    private static var _audioReadyGeneration:String = null;
    private static var _deviceGeneration:String = null;

    private static var _sfxBuf:Array = [];
    private static var _sfxBatchSequence:String = "0";
    private static var _sequenceSessionId:String = null;
    private static var _sequenceReadyGeneration:String = null;
    private static var _hasEnteredReady:Boolean = false;

    private static var _sfxPreReadyDrops:Number = 0;
    private static var _sfxRecoveryDrops:Number = 0;
    private static var _sfxStaleGenerationDrops:Number = 0;
    private static var _sfxUnknownIdCount:Number = 0;
    private static var _sfxThrottledCount:Number = 0;
    private static var _sfxStartFailureCount:Number = 0;
    private static var _sfxPlayedCount:Number = 0;

    private static var _bgmRequestSequence:String = "0";
    private static var _requestSequenceSessionId:String = null;
    private static var _pendingBgm:Object = {};
    private static var _latestBgmRequestId:String = null;

    private static var MAX_SFX_IDS:Number = 64;
    private static var MAX_SFX_ID_CHARS:Number = 255;
    private static var MAX_SFX_MESSAGE_BYTES:Number = 8192;
    private static var MAX_REQUEST_ID_CHARS:Number = 128;
    private static var UINT64_MAX:String = "18446744073709551615";

    private static var RESULT_KEYS:Array = [
        "wireRevision", "requestId", "audioSessionId",
        "audioReadyGeneration", "deviceGeneration", "operation",
        "completionState", "category", "stage", "nativeCode", "hresult",
        "decoderBackend", "messageKey"
    ];
    private static var READY_KEYS:Array = [
        "task", "wireRevision", "audioSessionId", "audioReadyGeneration",
        "deviceGeneration", "loaded", "failed", "overrides",
        "capabilityDigest"
    ];
    private static var UNAVAILABLE_KEYS:Array = [
        "task", "wireRevision", "audioSessionId", "audioReadyGeneration",
        "deviceGeneration", "category", "messageKey"
    ];
    private static var OPERATIONS:Array = [
        "play", "stop", "pause", "resume", "seek", "set_loop", "set_gain"
    ];
    private static var COMPLETION_STATES:Array = [
        "accepted_deferred", "started", "stopped", "superseded", "failed"
    ];
    private static var RESULT_CATEGORIES:Array = [
        "ok", "missing", "unsupported_container", "unsupported_codec",
        "malformed", "truncated", "io_error", "abi_mismatch", "not_ready",
        "stale_generation", "unknown_id", "throttled", "start_failed",
        "seek_failed", "device_unavailable", "device_lost", "superseded",
        "internal_error"
    ];
    private static var RESULT_STAGES:Array = [
        "none", "validate_abi", "validate_capacity", "validate_session",
        "validate_path", "admission", "context_initialize",
        "device_initialize", "device_start", "decoder_initialize",
        "source_initialize", "native_start", "seek", "probe_input",
        "probe_decode", "shutdown"
    ];
    private static var DECODER_BACKENDS:Array = [
        "none", "builtin", "libvorbis", "media_foundation", "libopus"
    ];

    public static function init():Void {
        _sm = ServerManager.getInstance();
        if (_sm != null && _sm.isSocketConnected === true) {
            onTransportConnected();
        }
    }

    /** 新 socket 只表示 transport 可用；必须等待同连接的 audio_ready。 */
    public static function onTransportConnected():Void {
        resetAvailability("initializing", true);
    }

    /** 断线清空 tuple、pending 与 SFX；旧请求/音效永不重放。 */
    public static function onTransportDisconnected():Void {
        resetAvailability("disconnected", true);
    }

    /** 接受 exact audio_ready；ready generation/device generation 必须非零。 */
    public static function handleAudioReady(message:Object):Boolean {
        if (!hasExactOwnKeys(message, READY_KEYS)
                || message.task !== "audio_ready"
                || message.wireRevision !== 2
                || !isCanonicalSessionId(message.audioSessionId)
                || !isCanonicalNonZeroDecimal(message.audioReadyGeneration)
                || !isCanonicalNonZeroDecimal(message.deviceGeneration)
                || !isNonNegativeInteger(message.loaded)
                || !isNonNegativeInteger(message.failed)
                || !isNonNegativeInteger(message.overrides)
                || !isSha256Hex(message.capabilityDigest)) {
            return false;
        }

        var sameTuple:Boolean = _status == "ready"
            && _audioSessionId === message.audioSessionId
            && _audioReadyGeneration === message.audioReadyGeneration
            && _deviceGeneration === message.deviceGeneration;

        if (!sameTuple) {
            _sfxStaleGenerationDrops += _sfxBuf.length;
            _sfxBuf = [];
            clearPendingBgm();
            notifyAvailabilityReset("ready_reset");
        }

        if (_sequenceSessionId !== message.audioSessionId
                || _sequenceReadyGeneration !== message.audioReadyGeneration) {
            _sfxBatchSequence = "0";
            _sequenceSessionId = message.audioSessionId;
            _sequenceReadyGeneration = message.audioReadyGeneration;
        }
        if (_requestSequenceSessionId !== message.audioSessionId) {
            _bgmRequestSequence = "0";
            _requestSequenceSessionId = message.audioSessionId;
        }

        _status = "ready";
        _hasEnteredReady = true;
        _audioSessionId = message.audioSessionId;
        _audioReadyGeneration = message.audioReadyGeneration;
        _deviceGeneration = message.deviceGeneration;
        return true;
    }

    /** unavailable/recovery 都撤销 admission，且不保留待发送音频。 */
    public static function handleAudioUnavailable(message:Object):Boolean {
        if (!hasExactOwnKeys(message, UNAVAILABLE_KEYS)
                || message.task !== "audio_unavailable"
                || message.wireRevision !== 2
                || !isCanonicalSessionId(message.audioSessionId)
                || !isCanonicalDecimal(message.audioReadyGeneration)
                || !isCanonicalDecimal(message.deviceGeneration)
                || !contains(RESULT_CATEGORIES, message.category)
                || message.category == "ok"
                || !isMessageKey(message.messageKey)) {
            return false;
        }

        countUnavailableSfxDrops(_sfxBuf.length);
        _status = "unavailable";
        _audioSessionId = message.audioSessionId;
        _audioReadyGeneration = message.audioReadyGeneration;
        _deviceGeneration = message.deviceGeneration;
        _sfxBuf = [];
        clearPendingBgm();
        notifyAvailabilityReset("audio_unavailable");
        return true;
    }

    public static function isReady():Boolean {
        return _status == "ready"
            && _sm != null
            && _sm.isSocketConnected === true;
    }

    /** 本地诊断快照；不扩展冻结 S2 wire，也不提供逐枪往返确认。 */
    public static function getSfxCountersSnapshot():Object {
        return {
            preReadyDrops: _sfxPreReadyDrops,
            recoveryDrops: _sfxRecoveryDrops,
            staleGenerationDrops: _sfxStaleGenerationDrops,
            unknownIdCount: _sfxUnknownIdCount,
            throttledCount: _sfxThrottledCount,
            startFailureCount: _sfxStartFailureCount,
            playedCount: _sfxPlayedCount
        };
    }

    /** SFX 在非 ready、非法 id 或 batch 满时直接 drop；从不排队等待恢复。 */
    public static function playSound(id:String):Void {
        if (!isReady()) {
            countUnavailableSfxDrops(1);
            return;
        }
        if (typeof id == "string" && id.length > MAX_SFX_ID_CHARS) {
            _sfxThrottledCount++;
            return;
        }
        if (!isValidLinkageId(id)) {
            _sfxUnknownIdCount++;
            return;
        }
        if (_sfxBuf.length >= MAX_SFX_IDS) {
            _sfxThrottledCount++;
            return;
        }

        var nextSequence:String = incrementDecimal(_sfxBatchSequence);
        if (nextSequence == null) {
            countUnavailableSfxDrops(1);
            resetAvailability("unavailable", true);
            return;
        }
        var projected:String = buildSfxMessage(
            _audioSessionId,
            _audioReadyGeneration,
            nextSequence,
            _sfxBuf,
            id);
        if (projected == null
                || utf8Length(projected) > MAX_SFX_MESSAGE_BYTES) {
            _sfxThrottledCount++;
            return;
        }
        _sfxBuf.push(id);
    }

    /** 帧末发送一次 S2。send 失败也不重放；下一帧只收新请求。 */
    public static function flush():Void {
        if (_sfxBuf.length == 0) return;
        var ids:Array = _sfxBuf;
        _sfxBuf = [];

        if (!isReady()) {
            countUnavailableSfxDrops(ids.length);
            return;
        }
        var nextSequence:String = incrementDecimal(_sfxBatchSequence);
        if (nextSequence == null) {
            countUnavailableSfxDrops(ids.length);
            resetAvailability("unavailable", true);
            return;
        }

        var message:String = buildSfxMessage(
            _audioSessionId,
            _audioReadyGeneration,
            nextSequence,
            ids,
            null);
        if (message == null || utf8Length(message) > MAX_SFX_MESSAGE_BYTES) {
            _sfxThrottledCount += ids.length;
            return;
        }

        _sfxBatchSequence = nextSequence;
        if (_sm.sendSocketMessage(message) !== true) {
            countUnavailableSfxDrops(ids.length);
        }
    }

    /** 场景切换只清本帧 SFX；不得重置 audio tuple 或 request sequence。 */
    public static function reset():Void {
        _sfxBuf = [];
    }

    public static function playBGM(
            url:String,
            loop:Boolean,
            vol:Number,
            fade:Number,
            callback:Function):String {
        if (!isValidPath(url)
                || !isBoundedNumber(vol, 0, 1)
                || !isBoundedNumber(fade, 0, 60)) return null;
        return sendBgm("play", {
            path: url,
            loop: loop === true,
            volume: vol,
            fadeSeconds: fade
        }, callback);
    }

    public static function stopBGM(fade:Number, callback:Function):String {
        if (!isBoundedNumber(fade, 0, 60)) return null;
        return sendBgm("stop", {fadeSeconds: fade}, callback);
    }

    public static function pauseBGM(callback:Function):String {
        return sendBgm("pause", null, callback);
    }

    public static function resumeBGM(callback:Function):String {
        return sendBgm("resume", null, callback);
    }

    public static function seekBGM(seconds:Number, callback:Function):String {
        if (!isBoundedNumber(seconds, 0, 86400)) return null;
        return sendBgm("seek", {seekSeconds: seconds}, callback);
    }

    public static function setBGMLooping(loop:Boolean, callback:Function):String {
        return sendBgm("set_loop", {loop: loop === true}, callback);
    }

    public static function setBGMVolume(vol:Number, callback:Function):String {
        if (!isBoundedNumber(vol, 0, 1)) return null;
        return sendBgm("set_gain", {volume: vol}, callback);
    }

    /** H1 没有裸全局音量 wire；保留调用名但走唯一 set_gain v2 operation。 */
    public static function setMasterVolume(vol:Number, callback:Function):String {
        return setBGMVolume(vol, callback);
    }

    /**
     * C# result 无 task 字段。只接受 exact 13-key typed result，并按 requestId
     * 关联到本进程已发送的 pending。未知、重复、近似或 operation 漂移全部拒绝。
     */
    public static function handleBgmResult(message:Object):Boolean {
        if (!isValidBgmResult(message)) return false;

        var pending:Object = _pendingBgm[message.requestId];
        if (pending == undefined
                || pending.operation !== message.operation) return false;

        if (message.category != "stale_generation"
                && (message.audioSessionId !== pending.audioSessionId
                    || message.audioReadyGeneration !== pending.audioReadyGeneration
                    || message.deviceGeneration !== _deviceGeneration)) {
            return false;
        }

        // play/stop 是可取代的播放意图；seek/gain/loop/pause/resume 是独立控制。
        // 控制请求不能把已 accepted_deferred 的 play 变成“非 latest”。
        var isLatest:Boolean = pending.affectsIntent === true
            ? message.requestId === _latestBgmRequestId
            : true;
        if (message.completionState == "accepted_deferred") {
            if (pending.accepted === true) return false;
            pending.accepted = true;
            invokeResultCallback(pending.callback, message, isLatest);
            return true;
        }

        delete _pendingBgm[message.requestId];
        if (pending.affectsIntent === true && isLatest) {
            _latestBgmRequestId = null;
        }
        invokeResultCallback(pending.callback, message, isLatest);
        return true;
    }

    private static function sendBgm(
            operation:String,
            operationPayload:Object,
            callback:Function):String {
        if (!isReady() || !contains(OPERATIONS, operation)) return null;
        var requestId:String = nextRequestId();
        if (requestId == null) return null;

        var request:Object = new Object();
        request.wireRevision = 2;
        request.requestId = requestId;
        request.audioSessionId = _audioSessionId;
        request.audioReadyGeneration = _audioReadyGeneration;
        request.operation = operation;
        if (operationPayload != null) {
            for (var key:String in operationPayload) {
                if (owns(operationPayload, key)) {
                    request[key] = operationPayload[key];
                }
            }
        }

        var affectsIntent:Boolean = operation == "play" || operation == "stop";
        _pendingBgm[requestId] = {
            operation: operation,
            audioSessionId: _audioSessionId,
            audioReadyGeneration: _audioReadyGeneration,
            callback: callback,
            accepted: false,
            affectsIntent: affectsIntent
        };
        var previousLatestRequestId:String = _latestBgmRequestId;
        if (affectsIntent) _latestBgmRequestId = requestId;
        if (_sm.sendTaskToNode("audio", request, null) !== true) {
            delete _pendingBgm[requestId];
            if (affectsIntent && _latestBgmRequestId === requestId) {
                _latestBgmRequestId = previousLatestRequestId;
            }
            return null;
        }
        return requestId;
    }

    private static function nextRequestId():String {
        var next:String = incrementDecimal(_bgmRequestSequence);
        if (next == null) {
            resetAvailability("unavailable", true);
            return null;
        }
        var requestId:String = "bgm.as2." + _audioSessionId + "." + next;
        if (requestId.length > MAX_REQUEST_ID_CHARS) return null;
        _bgmRequestSequence = next;
        return requestId;
    }

    private static function resetAvailability(status:String, notify:Boolean):Void {
        countUnavailableSfxDrops(_sfxBuf.length);
        _status = status;
        _audioSessionId = null;
        _audioReadyGeneration = null;
        _deviceGeneration = null;
        _sfxBuf = [];
        clearPendingBgm();
        if (notify) notifyAvailabilityReset(status);
    }

    private static function countUnavailableSfxDrops(count:Number):Void {
        if (!(count > 0)) return;
        if (_hasEnteredReady) {
            _sfxRecoveryDrops += count;
        } else {
            _sfxPreReadyDrops += count;
        }
    }

    private static function clearPendingBgm():Void {
        _pendingBgm = {};
        _latestBgmRequestId = null;
    }

    private static function notifyAvailabilityReset(reason:String):Void {
        if (_root.soundEffectManager != undefined
                && typeof _root.soundEffectManager.onAudioBridgeReset == "function") {
            _root.soundEffectManager.onAudioBridgeReset(reason);
        }
    }

    private static function invokeResultCallback(
            callback:Function,
            result:Object,
            isLatest:Boolean):Void {
        if (typeof callback == "function") callback(result, isLatest);
    }

    private static function buildSfxMessage(
            sessionId:String,
            readyGeneration:String,
            batchSequence:String,
            ids:Array,
            appendedId:String):String {
        if (batchSequence == null) return null;
        var message:String = "S2|" + sessionId + "|" + readyGeneration
            + "|" + batchSequence;
        for (var i:Number = 0; i < ids.length; i++) {
            message += "|" + ids[i];
        }
        if (appendedId != null) message += "|" + appendedId;
        return message;
    }

    private static function isValidBgmResult(message:Object):Boolean {
        if (!hasExactOwnKeys(message, RESULT_KEYS)
                || message.wireRevision !== 2
                || !isCanonicalRequestId(message.requestId)
                || !isCanonicalSessionId(message.audioSessionId)
                || !isCanonicalDecimal(message.audioReadyGeneration)
                || !isCanonicalDecimal(message.deviceGeneration)
                || !contains(OPERATIONS, message.operation)
                || !contains(COMPLETION_STATES, message.completionState)
                || !contains(RESULT_CATEGORIES, message.category)
                || !contains(RESULT_STAGES, message.stage)
                || !isInt32(message.nativeCode)
                || !isInt32(message.hresult)
                || !contains(DECODER_BACKENDS, message.decoderBackend)
                || !isMessageKey(message.messageKey)) return false;

        if (message.completionState == "failed") {
            return message.category != "ok" && message.category != "superseded";
        }
        if (message.completionState == "superseded") {
            return message.category == "superseded";
        }
        return message.category == "ok";
    }

    private static function hasExactOwnKeys(value:Object, expected:Array):Boolean {
        if (value == null || typeof value != "object") return false;
        var count:Number = 0;
        for (var key:String in value) {
            if (owns(value, key)) {
                if (!contains(expected, key)) return false;
                count++;
            }
        }
        if (count != expected.length) return false;
        for (var i:Number = 0; i < expected.length; i++) {
            if (!owns(value, expected[i])) return false;
        }
        return true;
    }

    private static function owns(value:Object, key:String):Boolean {
        return value != null
            && Object.prototype.hasOwnProperty.call(value, key);
    }

    private static function contains(values:Array, value):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (values[i] === value) return true;
        }
        return false;
    }

    private static function isCanonicalRequestId(value):Boolean {
        if (typeof value != "string" || value.length == 0
                || value.length > MAX_REQUEST_ID_CHARS
                || !isAsciiAlphaNumeric(value.charAt(0))) return false;
        for (var i:Number = 1; i < value.length; i++) {
            var c:String = value.charAt(i);
            if (!isAsciiAlphaNumeric(c)
                    && c != "." && c != "_" && c != ":" && c != "-") return false;
        }
        return true;
    }

    private static function isAsciiAlphaNumeric(c:String):Boolean {
        var code:Number = c.charCodeAt(0);
        return (code >= 48 && code <= 57)
            || (code >= 65 && code <= 90)
            || (code >= 97 && code <= 122);
    }

    private static function isCanonicalSessionId(value):Boolean {
        if (typeof value != "string" || value.length != 36
                || value.charAt(8) != "-" || value.charAt(13) != "-"
                || value.charAt(18) != "-" || value.charAt(23) != "-"
                || value.charAt(14) != "4") return false;
        var variant:String = value.charAt(19);
        if (variant != "8" && variant != "9" && variant != "a" && variant != "b") return false;
        for (var i:Number = 0; i < value.length; i++) {
            if (i == 8 || i == 13 || i == 18 || i == 23) continue;
            var code:Number = value.charCodeAt(i);
            if (!((code >= 48 && code <= 57) || (code >= 97 && code <= 102))) return false;
        }
        return true;
    }

    private static function isCanonicalNonZeroDecimal(value):Boolean {
        return isCanonicalDecimal(value) && value != "0";
    }

    private static function isCanonicalDecimal(value):Boolean {
        if (typeof value != "string" || value.length == 0 || value.length > 20) return false;
        if (value.length > 1 && value.charAt(0) == "0") return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 48 || code > 57) return false;
        }
        if (value.length == 20 && compareDecimalText(value, UINT64_MAX) > 0) return false;
        return true;
    }

    private static function incrementDecimal(value:String):String {
        if (!isCanonicalDecimal(value) || value == UINT64_MAX) return null;
        var carry:Number = 1;
        var output:String = "";
        for (var i:Number = value.length - 1; i >= 0; i--) {
            var digit:Number = Number(value.charAt(i)) + carry;
            if (digit >= 10) {
                digit -= 10;
                carry = 1;
            } else {
                carry = 0;
            }
            output = String(digit) + output;
        }
        if (carry == 1) output = "1" + output;
        return isCanonicalDecimal(output) ? output : null;
    }

    private static function compareDecimalText(left:String, right:String):Number {
        if (left.length < right.length) return -1;
        if (left.length > right.length) return 1;
        for (var i:Number = 0; i < left.length; i++) {
            var l:Number = left.charCodeAt(i);
            var r:Number = right.charCodeAt(i);
            if (l < r) return -1;
            if (l > r) return 1;
        }
        return 0;
    }

    private static function isValidPath(value):Boolean {
        return typeof value == "string" && value.length > 0
            && value.length <= 32767
            && !containsNul(value)
            && value.indexOf("\r") < 0
            && value.indexOf("\n") < 0
            && utf8Length(value) >= 0;
    }

    private static function isValidLinkageId(value):Boolean {
        return typeof value == "string" && value.length > 0
            && value.length <= MAX_SFX_ID_CHARS
            && value != "." && value != ".."
            && value.indexOf("|") < 0
            && !containsNul(value)
            && value.indexOf("\r") < 0
            && value.indexOf("\n") < 0
            && value.indexOf("/") < 0
            && value.indexOf("\\") < 0
            && utf8Length(value) >= 0;
    }

    private static function isBoundedNumber(value, minimum:Number, maximum:Number):Boolean {
        return typeof value == "number" && (value - value) == 0
            && !(value < minimum) && !(value > maximum);
    }

    private static function containsNul(value:String):Boolean {
        for (var i:Number = 0; i < value.length; i++) {
            if (value.charCodeAt(i) == 0) return true;
        }
        return false;
    }

    private static function isNonNegativeInteger(value):Boolean {
        return typeof value == "number" && (value - value) == 0
            && !(value < 0) && !(value > 2147483647)
            && Math.floor(value) == value;
    }

    private static function isInt32(value):Boolean {
        return typeof value == "number" && (value - value) == 0
            && !(value < -2147483648) && !(value > 2147483647)
            && Math.floor(value) == value;
    }

    private static function isMessageKey(value):Boolean {
        if (typeof value != "string" || value.length == 0 || value.length > 128) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (!((code >= 97 && code <= 122)
                    || (code >= 48 && code <= 57)
                    || code == 46 || code == 95 || code == 45)) return false;
        }
        return true;
    }

    private static function isSha256Hex(value):Boolean {
        if (typeof value != "string" || value.length != 64) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (!((code >= 48 && code <= 57)
                    || (code >= 65 && code <= 70)
                    || (code >= 97 && code <= 102))) return false;
        }
        return true;
    }

    /** 精确 UTF-8 byte count；孤立 surrogate 返回 -1。 */
    private static function utf8Length(value:String):Number {
        var bytes:Number = 0;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code <= 127) {
                bytes++;
            } else if (code <= 2047) {
                bytes += 2;
            } else if (code >= 55296 && code <= 56319) {
                if (i + 1 >= value.length) return -1;
                var low:Number = value.charCodeAt(i + 1);
                if (low < 56320 || low > 57343) return -1;
                bytes += 4;
                i++;
            } else if (code >= 56320 && code <= 57343) {
                return -1;
            } else {
                bytes += 3;
            }
        }
        return bytes;
    }

    // ==================== Focused TestLoader hooks ====================

    public static function _setTransportForTests(transport:Object):Void {
        _sm = transport;
    }

    public static function _resetForTests():Void {
        _status = "disconnected";
        _audioSessionId = null;
        _audioReadyGeneration = null;
        _deviceGeneration = null;
        _sfxBuf = [];
        _sfxBatchSequence = "0";
        _sequenceSessionId = null;
        _sequenceReadyGeneration = null;
        _hasEnteredReady = false;
        _sfxPreReadyDrops = 0;
        _sfxRecoveryDrops = 0;
        _sfxStaleGenerationDrops = 0;
        _sfxUnknownIdCount = 0;
        _sfxThrottledCount = 0;
        _sfxStartFailureCount = 0;
        _sfxPlayedCount = 0;
        _bgmRequestSequence = "0";
        _requestSequenceSessionId = null;
        clearPendingBgm();
    }

    public static function _snapshotForTests():Object {
        return {
            status: _status,
            audioSessionId: _audioSessionId,
            audioReadyGeneration: _audioReadyGeneration,
            deviceGeneration: _deviceGeneration,
            sfxBuffered: _sfxBuf.length,
            sfxBatchSequence: _sfxBatchSequence,
            sfxCounters: getSfxCountersSnapshot(),
            latestBgmRequestId: _latestBgmRequestId
        };
    }

    public static function _setSfxBatchSequenceForTests(value:String):Void {
        _sfxBatchSequence = value;
    }

    public static function _setBgmRequestSequenceForTests(value:String):Void {
        _bgmRequestSequence = value;
    }
}
