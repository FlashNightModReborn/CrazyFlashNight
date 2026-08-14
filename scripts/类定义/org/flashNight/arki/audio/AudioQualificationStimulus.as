/**
 * Audio Platform v2 isolated-candidate qualification stimulus surface.
 */

import org.flashNight.arki.audio.AudioBridge;

class org.flashNight.arki.audio.AudioQualificationStimulus {
    private static var ACTION:String = "audioV2QualificationStimulus";
    private static var PATH_PREFIX:String = "tmp/audio-v2-qualification/";

    private static var ARM_KEYS:Array = [
        "action", "operation", "runId", "task"
    ];
    private static var PLAY_KEYS:Array = [
        "action", "caseId", "fadeSeconds", "loop", "operation",
        "path", "runId", "task", "volume"
    ];
    private static var SEEK_KEYS:Array = [
        "action", "caseId", "operation", "runId", "seekSeconds", "task"
    ];
    private static var GAIN_KEYS:Array = [
        "action", "caseId", "operation", "runId", "task", "volume"
    ];
    private static var SFX_KEYS:Array = [
        "action", "caseId", "linkageIds", "operation", "runId", "task"
    ];

    private static var _armedRunId:String = null;
    private static var _caseSteps:Object = new Object();

    public static function handle(params:Object):Boolean {
        if (isExactArm(params)) return arm(params.runId);
        if (_armedRunId == null
                || !hasCommonCommandFields(params)
                || params.runId !== _armedRunId) return false;

        if (params.operation === "play") return handlePlay(params);
        if (params.operation === "seek") return handleSeek(params);
        if (params.operation === "set_gain") return handleGain(params);
        if (params.operation === "sfx") return handleSfx(params);
        return false;
    }

    private static function arm(runId:String):Boolean {
        if (_armedRunId == null) {
            _armedRunId = runId;
            _caseSteps = new Object();
            return true;
        }
        return _armedRunId === runId;
    }

    private static function handlePlay(params:Object):Boolean {
        if (!hasExactOwnKeys(params, PLAY_KEYS)
                || typeof params.caseId != "string"
                || typeof params.path != "string"
                || typeof params.loop != "boolean"
                || params.loop !== true
                || !isBoundedNumber(params.volume, 0, 1)
                || params.volume !== 1
                || !isBoundedNumber(params.fadeSeconds, 0, 60)
                || !isQualificationPath(params.path, params.runId)
                || caseStep(params.caseId) != 0) return false;

        var fadeValid:Boolean = false;
        if (params.caseId == "bgm_playback") {
            fadeValid = params.fadeSeconds === 0;
        } else if (params.caseId == "bgm_crossfade") {
            fadeValid = params.fadeSeconds > 0;
        } else if (params.caseId == "format_vorbis"
                || params.caseId == "format_aac_mp4"
                || params.caseId == "format_opus") {
            fadeValid = params.fadeSeconds === 0;
        }
        if (!fadeValid) return false;

        var requestId:String = AudioBridge.playBGM(
            params.path,
            params.loop,
            params.volume,
            params.fadeSeconds,
            null);
        if (requestId == null) return false;
        setCaseStep(params.caseId, 1);
        return true;
    }

    private static function handleSeek(params:Object):Boolean {
        if (!hasExactOwnKeys(params, SEEK_KEYS)
                || params.caseId !== "bgm_seek"
                || !isBoundedNumber(params.seekSeconds, 0, 86400)
                || params.seekSeconds === 0
                || caseStep(params.caseId) != 0) return false;
        var requestId:String = AudioBridge.seekBGM(params.seekSeconds, null);
        if (requestId == null) return false;
        setCaseStep(params.caseId, 1);
        return true;
    }

    private static function handleGain(params:Object):Boolean {
        if (!hasExactOwnKeys(params, GAIN_KEYS)
                || !isBoundedNumber(params.volume, 0, 1)) return false;
        if (params.caseId === "pre_sfx_bgm_mute") {
            if (params.volume !== 0
                    || caseStep("format_opus") != 1
                    || caseStep("sfx_playback") != 0
                    || caseStep(params.caseId) != 0) return false;
            var muteRequestId:String = AudioBridge.setBGMVolume(0, null);
            if (muteRequestId == null) return false;
            setCaseStep(params.caseId, 1);
            return true;
        }
        if (params.caseId === "pre_mix_bgm_restore") {
            if (params.volume !== 1
                    || caseStep("pre_sfx_bgm_mute") != 1
                    || caseStep("dense_overlap_throttle") != 1
                    || caseStep("bgm_sfx_mix") != 0
                    || caseStep(params.caseId) != 0) return false;
            var mixRestoreRequestId:String = AudioBridge.setBGMVolume(1, null);
            if (mixRestoreRequestId == null) return false;
            setCaseStep(params.caseId, 1);
            return true;
        }
        if (params.caseId === "post_gain_restore") {
            if (params.volume !== 1
                    || caseStep("gain_zero_and_default_max") != 2
                    || caseStep(params.caseId) != 0) return false;
            var restoreRequestId:String = AudioBridge.setBGMVolume(1, null);
            if (restoreRequestId == null) return false;
            setCaseStep(params.caseId, 1);
            return true;
        }
        if (params.caseId !== "gain_zero_and_default_max") return false;
        var step:Number = caseStep(params.caseId);
        if ((step == 0 && params.volume !== 1)
                || (step == 1 && params.volume !== 0)
                || step > 1) return false;
        var requestId:String = AudioBridge.setBGMVolume(params.volume, null);
        if (requestId == null) return false;
        setCaseStep(params.caseId, step + 1);
        return true;
    }

    private static function handleSfx(params:Object):Boolean {
        if (!hasExactOwnKeys(params, SFX_KEYS)
                || typeof params.caseId != "string"
                || !(params.linkageIds instanceof Array)
                || caseStep(params.caseId) != 0) return false;

        var minimum:Number;
        var maximum:Number;
        var allowRecoveryTuple:Boolean = false;
        if (params.caseId == "sfx_playback") {
            minimum = 1;
            maximum = 1;
        } else if (params.caseId == "dense_overlap_throttle") {
            minimum = 6;
            maximum = 6;
        } else if (params.caseId == "bgm_sfx_mix") {
            minimum = 1;
            maximum = 1;
        } else if (params.caseId == "no_stale_sfx_after_recovery") {
            minimum = 1;
            maximum = 1;
            allowRecoveryTuple = true;
        } else {
            return false;
        }
        if (params.linkageIds.length < minimum
                || params.linkageIds.length > maximum) return false;
        for (var i:Number = 0; i < params.linkageIds.length; i++) {
            if (!isPrintableLinkageId(params.linkageIds[i])) return false;
        }
        if (params.caseId == "dense_overlap_throttle"
                && !hasIdenticalStrings(params.linkageIds)) return false;

        if (!AudioBridge.flushQualificationSfxBatch(
                params.linkageIds, allowRecoveryTuple)) return false;
        setCaseStep(params.caseId, 1);
        return true;
    }

    private static function isExactArm(params:Object):Boolean {
        return hasExactOwnKeys(params, ARM_KEYS)
            && params.task === "cmd"
            && params.action === ACTION
            && params.operation === "arm"
            && isRunId(params.runId);
    }

    private static function hasCommonCommandFields(params:Object):Boolean {
        return params != null
            && typeof params == "object"
            && params.task === "cmd"
            && params.action === ACTION
            && isRunId(params.runId)
            && typeof params.operation == "string";
    }

    private static function isRunId(value):Boolean {
        if (typeof value != "string" || value.length != 32) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (!((code >= 48 && code <= 57)
                    || (code >= 97 && code <= 102))) return false;
        }
        return true;
    }

    private static function isQualificationPath(path:String, runId:String):Boolean {
        if (path.length == 0 || path.length > 1024) return false;
        var expectedPrefix:String = PATH_PREFIX + runId + "/";
        if (path.indexOf(expectedPrefix) != 0) return false;
        for (var i:Number = 0; i < path.length; i++) {
            var code:Number = path.charCodeAt(i);
            var allowed:Boolean = (code >= 48 && code <= 57)
                || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 47 || code == 95;
            if (!allowed) return false;
        }
        var segments:Array = path.split("/");
        for (var j:Number = 0; j < segments.length; j++) {
            if (segments[j] == "" || segments[j] == "." || segments[j] == "..") {
                return false;
            }
        }
        return true;
    }

    private static function isPrintableLinkageId(value):Boolean {
        if (typeof value != "string" || value.length == 0 || value.length > 255
                || value == "." || value == ".."
                || value.indexOf("|") >= 0
                || value.indexOf("/") >= 0
                || value.indexOf("\\") >= 0) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || code == 127) return false;
        }
        return true;
    }

    private static function isBoundedNumber(
            value, minimum:Number, maximum:Number):Boolean {
        return typeof value == "number" && (value - value) == 0
            && !(value < minimum) && !(value > maximum);
    }

    private static function caseStep(caseId:String):Number {
        return owns(_caseSteps, caseId) ? Number(_caseSteps[caseId]) : 0;
    }

    private static function setCaseStep(caseId:String, step:Number):Void {
        _caseSteps[caseId] = step;
    }

    private static function hasExactOwnKeys(value:Object, expected:Array):Boolean {
        if (value == null || typeof value != "object") return false;
        var count:Number = 0;
        for (var key:String in value) {
            if (!owns(value, key)) continue;
            if (!contains(expected, key)) return false;
            count++;
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

    private static function hasIdenticalStrings(values:Array):Boolean {
        if (values.length == 0) return false;
        for (var i:Number = 1; i < values.length; i++) {
            if (values[i] !== values[0]) return false;
        }
        return true;
    }

    // Focused TestLoader hooks only.
    public static function _resetForTests():Void {
        _armedRunId = null;
        _caseSteps = new Object();
    }

    public static function _snapshotForTests():Object {
        return {
            armedRunId: _armedRunId,
            gainStep: caseStep("gain_zero_and_default_max"),
            preSfxBgmMuteStep: caseStep("pre_sfx_bgm_mute"),
            preMixBgmRestoreStep: caseStep("pre_mix_bgm_restore"),
            postGainRestoreStep: caseStep("post_gain_restore")
        };
    }
}
