/**
 * Audio Platform v2 AS2 wire/state focused tests.
 */

import org.flashNight.arki.audio.AudioBridge;
import org.flashNight.arki.audio.SoundEffectManager;
import org.flashNight.neur.Server.ServerManager;
import FastJSON;

class org.flashNight.arki.audio.test.AudioBridgeV2Test {
    private static var SESSION:String = "01234567-89ab-4cde-8f01-23456789abcd";
    private static var SESSION_2:String = "fedcba98-7654-4abc-9def-0123456789ab";
    private static var DIGEST:String =
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;

        testTaskEnvelopeShape();
        testExactInboundEnvelopes();
        testJukeboxQualificationGuard();
        testReadyBgmCorrelationAndLatestWins();
        testSfxDropAndNoReplay();

        trace("AudioBridgeV2Test Tests Passed: " + passed);
        trace("AudioBridgeV2Test Tests Failed: " + failed);
    }

    private static function testTaskEnvelopeShape():Void {
        var payload:Object = {
            wireRevision: 2,
            requestId: "bgm.request.1",
            audioSessionId: SESSION,
            audioReadyGeneration: "42",
            operation: "pause"
        };
        var flat:Object = ServerManager._buildTaskEnvelopeForTest(
            "audio", payload, null);
        assertTrue("audio envelope built", flat != null);
        assertEqual("audio task top-level", "audio", flat.task);
        assertTrue("audio has no nested payload", !flat.hasOwnProperty("payload"));
        assertEqual("audio requestId flattened", "bgm.request.1", flat.requestId);
        assertTrue("audio has no connection generation",
            !flat.hasOwnProperty("connectionGeneration"));

        var ordinary:Object = ServerManager._buildTaskEnvelopeForTest(
            "data_query", {op: "read"}, {source: "test"});
        assertEqual("ordinary payload remains nested", "read", ordinary.payload.op);
        assertEqual("ordinary extra remains nested", "test", ordinary.extra.source);
        assertTrue("audio rejects extra", ServerManager._buildTaskEnvelopeForTest(
            "audio", payload, {x: 1}) == null);
        assertTrue("audio rejects task injection", ServerManager._buildTaskEnvelopeForTest(
            "audio", {task: "other", wireRevision: 2}, null) == null);
    }

    private static function testExactInboundEnvelopes():Void {
        var ready:Object = makeReady(SESSION, "42", "9");
        assertTrue("ready exact keys accepted by ServerManager",
            ServerManager._isExactAudioReadyEnvelopeForTest(ready));

        var readyExtra:Object = copyObject(ready);
        readyExtra.connectionGeneration = 7;
        assertFalse("ready rejects transport generation",
            ServerManager._isExactAudioReadyEnvelopeForTest(readyExtra));

        var readyMissing:Object = copyObject(ready);
        delete readyMissing.loaded;
        assertFalse("ready rejects missing required field",
            ServerManager._isExactAudioReadyEnvelopeForTest(readyMissing));

        var unavailable:Object = makeUnavailable(SESSION, "43", "10");
        assertTrue("unavailable exact keys accepted by ServerManager",
            ServerManager._isExactAudioUnavailableEnvelopeForTest(unavailable));

        var unavailableExtra:Object = copyObject(unavailable);
        unavailableExtra.generation = "43";
        assertFalse("unavailable rejects bare generation",
            ServerManager._isExactAudioUnavailableEnvelopeForTest(unavailableExtra));

        var result:Object = makeResult(
            "bgm.request.1", "pause", "started", "ok", SESSION, "42");
        assertTrue("BGM result exact keys accepted by ServerManager",
            ServerManager._isExactAudioBgmResultEnvelopeForTest(result));

        var missing:Object = copyObject(result);
        delete missing.messageKey;
        assertFalse("BGM result rejects missing field",
            ServerManager._isExactAudioBgmResultEnvelopeForTest(missing));

        var extra:Object = copyObject(result);
        extra.task = "audio";
        assertFalse("BGM result rejects extra task",
            ServerManager._isExactAudioBgmResultEnvelopeForTest(extra));

        var wrongType:Object = copyObject(result);
        wrongType.audioReadyGeneration = 42;
        assertFalse("BGM result rejects numeric ready generation",
            ServerManager._isExactAudioBgmResultEnvelopeForTest(wrongType));

        var shadowedOwnCheck:Object = copyObject(result);
        shadowedOwnCheck["hasOwnProperty"] = false;
        assertFalse("BGM result rejects hasOwnProperty shadow without throwing",
            ServerManager._isExactAudioBgmResultEnvelopeForTest(shadowedOwnCheck));
    }

    private static function testJukeboxQualificationGuard():Void {
        var command:Object = {
            task: "cmd",
            action: "jukeboxPlay",
            title: "Qualified Track"
        };
        assertTrue("jukebox play exact command accepted",
            ServerManager._isExactJukeboxPlayCommandForTest(command));

        var extra:Object = copyObject(command);
        extra.availability = "available";
        assertFalse("jukebox play rejects extra field",
            ServerManager._isExactJukeboxPlayCommandForTest(extra));

        var wrongType:Object = copyObject(command);
        wrongType.title = 7;
        assertFalse("jukebox play rejects non-string title",
            ServerManager._isExactJukeboxPlayCommandForTest(wrongType));

        assertTrue("available catalog track is playable",
            SoundEffectManager._isCatalogTrackAvailableForTest(
                {availability: "available"}));
        assertFalse("probing catalog track fails closed",
            SoundEffectManager._isCatalogTrackAvailableForTest(
                {availability: "probing"}));
        assertFalse("missing catalog qualification fails closed",
            SoundEffectManager._isCatalogTrackAvailableForTest({}));

        var track:Object = {title: "Qualified Track", url: "sounds/test.wav"};
        SoundEffectManager._projectCatalogQualificationForTest(
            track,
            {availability: "unavailable", reason: "unsupported_codec"});
        assertEqual("catalog projection updates availability",
            "unavailable", track.availability);
        assertEqual("catalog projection keeps reason",
            "unsupported_codec", track.reason);
        assertFalse("projected unavailable track is blocked",
            SoundEffectManager._isCatalogTrackAvailableForTest(track));

        SoundEffectManager._projectCatalogQualificationForTest(
            track,
            {availability: "forged", reason: "forged"});
        assertEqual("unknown availability fails closed",
            "unavailable", track.availability);

        SoundEffectManager._projectCatalogQualificationForTest(
            track,
            {availability: "available", reason: "compatible_signal_present"});
        assertTrue("updated available projection becomes playable",
            SoundEffectManager._isCatalogTrackAvailableForTest(track));
    }

    private static function testReadyBgmCorrelationAndLatestWins():Void {
        var transport:Object = makeTransport();
        AudioBridge._resetForTests();
        AudioBridge._setTransportForTests(transport);

        assertTrue("pre-ready BGM fails closed",
            AudioBridge.pauseBGM(null) == null);
        assertTrue("lowercase UUID ready accepted",
            AudioBridge.handleAudioReady(makeReady(SESSION, "42", "9")));
        assertEqual("ready status", "ready", AudioBridge._snapshotForTests().status);
        assertTrue("CR path is rejected before send",
            AudioBridge.playBGM(
                "sounds/\rbad.mp3",
                false, 0.5, 0, null) == null);

        var stages:Array = [];
        var firstId:String = AudioBridge.playBGM(
            "sounds/music/test.mp3", true, 0.75, 1.25,
            function(result:Object, isLatest:Boolean):Void {
                stages.push(result.completionState + "|" + (isLatest ? "1" : "0"));
            });
        assertTrue("play returns correlated requestId", firstId != null);
        assertEqual("one FastJSON task sent", 1, transport.tasks.length);
        var sent:Object = transport.tasks[0];
        assertTrue("sent request is flat", !sent.hasOwnProperty("payload"));
        assertEqual("sent wire revision number", 2, sent.wireRevision);
        assertEqual("sent lowercase session", SESSION, sent.audioSessionId);
        assertEqual("sent generation decimal string", "42", sent.audioReadyGeneration);
        assertEqual("sent operation", "play", sent.operation);
        assertTrue("sent loop boolean", sent.loop === true);
        assertTrue("serialized request excludes transport generation",
            transport.serialized[0].indexOf("connectionGeneration") < 0);

        var wrongDevice:Object = makeResult(
            firstId, "play", "accepted_deferred", "ok", SESSION, "42");
        wrongDevice.deviceGeneration = "10";
        assertFalse("non-stale result rejects wrong device generation",
            AudioBridge.handleBgmResult(wrongDevice));
        assertTrue("accepted_deferred correlates",
            AudioBridge.handleBgmResult(makeResult(
                firstId, "play", "accepted_deferred", "ok", SESSION, "42")));
        assertEqual("accepted callback marks latest",
            "accepted_deferred|1", stages[0]);

        var controlStages:Array = [];
        var gainId:String = AudioBridge.setBGMVolume(
            0.4,
            function(result:Object, isLatest:Boolean):Void {
                controlStages.push(result.completionState + "|"
                    + (isLatest ? "1" : "0"));
            });
        assertTrue("set_gain has its own correlated request", gainId != null);
        assertEqual("control request does not replace pending play intent",
            firstId, AudioBridge._snapshotForTests().latestBgmRequestId);
        assertTrue("set_gain terminal correlates independently",
            AudioBridge.handleBgmResult(makeResult(
                gainId, "set_gain", "started", "ok", SESSION, "42")));
        assertEqual("set_gain callback remains current control",
            "started|1", controlStages[0]);

        transport.rejectNext = true;
        var rejectedId:String = AudioBridge.playBGM(
            "sounds/music/send-failed.mp3", false, 0.5, 0, null);
        assertTrue("failed socket send returns no requestId", rejectedId == null);
        assertEqual("failed newer send restores prior latest intent",
            firstId, AudioBridge._snapshotForTests().latestBgmRequestId);

        var secondId:String = AudioBridge.playBGM(
            "sounds/music/next.mp3", false, 0.5, 0,
            function(result:Object, isLatest:Boolean):Void {
                stages.push(result.completionState + "|" + (isLatest ? "1" : "0"));
            });
        assertTrue("new latest request has a new id",
            secondId != null && secondId != firstId);

        assertTrue("prior request accepts superseded terminal",
            AudioBridge.handleBgmResult(makeResult(
                firstId, "play", "superseded", "superseded", SESSION, "42")));
        assertEqual("superseded callback is not latest", "superseded|0", stages[1]);

        assertTrue("latest request accepts started terminal",
            AudioBridge.handleBgmResult(makeResult(
                secondId, "play", "started", "ok", SESSION, "42")));
        assertEqual("started callback is latest", "started|1", stages[2]);
        assertFalse("duplicate terminal is rejected",
            AudioBridge.handleBgmResult(makeResult(
                secondId, "play", "started", "ok", SESSION, "42")));

        assertEqual("manager treats accepted_deferred as admission only",
            "deferred",
            SoundEffectManager._classifyBgmPlayResultForTest(
                {requestId: firstId, completionState: "accepted_deferred"},
                true, firstId, firstId));
        assertEqual("manager publishes only correlated latest started",
            "started",
            SoundEffectManager._classifyBgmPlayResultForTest(
                {requestId: secondId, completionState: "started"},
                true, secondId, secondId));
        assertEqual("manager ignores stale request terminal",
            "ignore",
            SoundEffectManager._classifyBgmPlayResultForTest(
                {requestId: firstId, completionState: "superseded"},
                false, secondId, firstId));
        assertEqual("manager classifies correlated failure without started UI",
            "terminal",
            SoundEffectManager._classifyBgmPlayResultForTest(
                {requestId: secondId, completionState: "failed"},
                true, secondId, secondId));

        var uncorrelated:Object = makeResult(
            "bgm.unknown.999", "play", "started", "ok", SESSION, "42");
        assertFalse("unknown requestId rejected", AudioBridge.handleBgmResult(uncorrelated));
    }

    private static function testSfxDropAndNoReplay():Void {
        var transport:Object = makeTransport();
        AudioBridge._resetForTests();
        AudioBridge._setTransportForTests(transport);

        AudioBridge.playSound("before-ready.wav");
        AudioBridge.flush();
        assertEqual("pre-ready SFX dropped", 0, transport.frames.length);
        assertEqual("pre-ready counter counts events", 1,
            AudioBridge._snapshotForTests().sfxCounters.preReadyDrops);
        assertEqual("recovery counter starts at zero", 0,
            AudioBridge._snapshotForTests().sfxCounters.recoveryDrops);

        assertTrue("ready for SFX", AudioBridge.handleAudioReady(
            makeReady(SESSION, "42", "9")));
        AudioBridge.playSound("gun|bad.wav");
        assertEqual("pipe linkage id is dropped", 0,
            AudioBridge._snapshotForTests().sfxBuffered);
        AudioBridge.playSound("gun.wav");
        AudioBridge.playSound("gun.wav");
        AudioBridge.playSound("bad/path.wav");
        AudioBridge.flush();
        assertEqual("one S2 batch sent", 1, transport.frames.length);
        assertEqual("S2 preserves duplicate shot semantics",
            "S2|" + SESSION + "|42|1|gun.wav|gun.wav", transport.frames[0]);
        assertEqual("invalid linkage ids count as unknown events", 2,
            AudioBridge._snapshotForTests().sfxCounters.unknownIdCount);

        AudioBridge.playSound("queued-before-recovery.wav");
        assertTrue("unavailable exact state accepted",
            AudioBridge.handleAudioUnavailable(makeUnavailable(SESSION, "43", "10")));
        assertEqual("unavailable state", "unavailable",
            AudioBridge._snapshotForTests().status);
        AudioBridge.playSound("during-recovery.wav");
        AudioBridge.flush();
        assertEqual("recovery drops and never replays", 1, transport.frames.length);
        assertEqual("recovery counter includes buffered and new events", 2,
            AudioBridge._snapshotForTests().sfxCounters.recoveryDrops);

        assertTrue("new ready generation accepted",
            AudioBridge.handleAudioReady(makeReady(SESSION, "43", "10")));
        AudioBridge.playSound("fresh.wav");
        AudioBridge.flush();
        assertEqual("fresh generation sends one new batch", 2, transport.frames.length);
        assertEqual("new generation resets batch sequence and contains only fresh id",
            "S2|" + SESSION + "|43|1|fresh.wav", transport.frames[1]);

        for (var idIndex:Number = 0; idIndex < 65; idIndex++) {
            AudioBridge.playSound("bounded-" + idIndex);
        }
        AudioBridge.flush();
        assertEqual("id-count bound emits one batch", 3, transport.frames.length);
        assertEqual("id-count bound keeps exactly 64 semantic ids",
            68, transport.frames[2].split("|").length);
        assertEqual("65th event counts as throttled", 1,
            AudioBridge._snapshotForTests().sfxCounters.throttledCount);

        var overlongId:String = "";
        for (var charIndex:Number = 0; charIndex < 256; charIndex++) {
            overlongId += "x";
        }
        AudioBridge.playSound(overlongId);
        AudioBridge.flush();
        assertEqual("256-code-unit linkage id is dropped",
            3, transport.frames.length);
        assertEqual("linkage length rejection counts as throttled", 2,
            AudioBridge._snapshotForTests().sfxCounters.throttledCount);

        var wideId:String = "";
        for (var wideIndex:Number = 0; wideIndex < 255; wideIndex++) {
            wideId += "音";
        }
        for (var messageIndex:Number = 0; messageIndex < 64; messageIndex++) {
            AudioBridge.playSound(wideId);
        }
        AudioBridge.flush();
        assertEqual("UTF-8 message bound still emits accepted prefix",
            4, transport.frames.length);
        assertEqual("UTF-8 message bound admits ten 765-byte ids",
            14, transport.frames[3].split("|").length);
        assertEqual("8KiB rejections count every dropped event", 56,
            AudioBridge._snapshotForTests().sfxCounters.throttledCount);

        AudioBridge.playSound("queued-before-new-ready.wav");
        assertTrue("tuple replacement is accepted",
            AudioBridge.handleAudioReady(makeReady(SESSION, "44", "11")));
        assertEqual("tuple replacement counts buffered stale event", 1,
            AudioBridge._snapshotForTests().sfxCounters.staleGenerationDrops);
        AudioBridge.flush();
        assertEqual("stale buffered event never replays", 4, transport.frames.length);

        transport.rejectFrameNext = true;
        AudioBridge.playSound("send-failed-a.wav");
        AudioBridge.playSound("send-failed-b.wav");
        AudioBridge.flush();
        assertEqual("failed S2 send never queues replay", 4, transport.frames.length);
        assertEqual("failed S2 send counts both recovery drops", 4,
            AudioBridge._snapshotForTests().sfxCounters.recoveryDrops);

        AudioBridge.playSound("queued-before-disconnect.wav");
        AudioBridge.onTransportDisconnected();
        assertEqual("disconnect resets state", "disconnected",
            AudioBridge._snapshotForTests().status);
        AudioBridge.flush();
        assertEqual("disconnect queue never replays", 4, transport.frames.length);
        assertEqual("disconnect counts queued event as recovery drop", 5,
            AudioBridge._snapshotForTests().sfxCounters.recoveryDrops);

        var uppercase:Object = makeReady(SESSION.toUpperCase(), "44", "11");
        assertFalse("uppercase UUID rejected", AudioBridge.handleAudioReady(uppercase));
        var leadingZero:Object = makeReady(SESSION_2, "044", "11");
        assertFalse("non-canonical decimal generation rejected",
            AudioBridge.handleAudioReady(leadingZero));
        var signed:Object = makeReady(SESSION_2, "+44", "11");
        assertFalse("signed decimal generation rejected",
            AudioBridge.handleAudioReady(signed));
        var overflow:Object = makeReady(
            SESSION_2, "18446744073709551616", "11");
        assertFalse("uint64 overflow generation rejected",
            AudioBridge.handleAudioReady(overflow));

        assertTrue("ready restored before sequence-overflow mutation",
            AudioBridge.handleAudioReady(makeReady(SESSION_2, "44", "11")));
        AudioBridge._setSfxBatchSequenceForTests("18446744073709551615");
        AudioBridge.playSound("overflow-must-not-linger.wav");
        assertEqual("batch sequence overflow revokes ready admission",
            "unavailable", AudioBridge._snapshotForTests().status);

        assertTrue("same session can announce recovery before request overflow",
            AudioBridge.handleAudioReady(makeReady(SESSION_2, "45", "12")));
        AudioBridge._setBgmRequestSequenceForTests("18446744073709551615");
        assertTrue("BGM request sequence overflow fails closed",
            AudioBridge.pauseBGM(null) == null);
        assertEqual("BGM request overflow revokes ready admission",
            "unavailable", AudioBridge._snapshotForTests().status);
        assertTrue("same session ready remains syntactically valid after overflow",
            AudioBridge.handleAudioReady(makeReady(SESSION_2, "46", "13")));
        assertTrue("same session cannot reuse an exhausted request sequence",
            AudioBridge.pauseBGM(null) == null);
        assertTrue("new audio session resets request sequence",
            AudioBridge.handleAudioReady(makeReady(SESSION, "47", "14")));
        var recoveredRequestId:String = AudioBridge.pauseBGM(null);
        assertTrue("new audio session resumes request ids from one",
            recoveredRequestId != null
                && recoveredRequestId.indexOf("." + SESSION + ".1") > 0);
        var counters:Object = AudioBridge.getSfxCountersSnapshot();
        assertEqual("local SFX diagnostic has exact seven fields", 7,
            ownKeyCount(counters));
        assertEqual("AS2 never fabricates native start failures", 0,
            counters.startFailureCount);
        assertEqual("AS2 never fabricates native played events", 0,
            counters.playedCount);
    }

    private static function makeTransport():Object {
        var transport:Object = {
            isSocketConnected: true,
            rejectNext: false,
            rejectFrameNext: false,
            tasks: [],
            serialized: [],
            frames: []
        };
        transport.sendTaskToNode = function(
                taskType:String,
                payload:Object,
                extra:Object):Boolean {
            // AS2 does not preserve a dynamic object's receiver reliably when the
            // function crosses a typed class boundary. Capture the fixture object so
            // the test exercises AudioBridge rather than an incidental `this` rule.
            if (transport.rejectNext === true) {
                transport.rejectNext = false;
                return false;
            }
            var envelope:Object = ServerManager._buildTaskEnvelopeForTest(
                taskType, payload, extra);
            if (envelope == null) return false;
            transport.tasks.push(envelope);
            var parser:FastJSON = new FastJSON();
            transport.serialized.push(parser.stringify(envelope));
            return true;
        };
        transport.sendSocketMessage = function(message:String):Boolean {
            if (transport.rejectFrameNext === true) {
                transport.rejectFrameNext = false;
                return false;
            }
            transport.frames.push(message);
            return true;
        };
        return transport;
    }

    private static function makeReady(
            sessionId:String,
            readyGeneration:String,
            deviceGeneration:String):Object {
        return {
            task: "audio_ready",
            wireRevision: 2,
            audioSessionId: sessionId,
            audioReadyGeneration: readyGeneration,
            deviceGeneration: deviceGeneration,
            loaded: 12,
            failed: 0,
            overrides: 1,
            capabilityDigest: DIGEST
        };
    }

    private static function makeUnavailable(
            sessionId:String,
            readyGeneration:String,
            deviceGeneration:String):Object {
        return {
            task: "audio_unavailable",
            wireRevision: 2,
            audioSessionId: sessionId,
            audioReadyGeneration: readyGeneration,
            deviceGeneration: deviceGeneration,
            category: "device_unavailable",
            messageKey: "audio.device_unavailable"
        };
    }

    private static function makeResult(
            requestId:String,
            operation:String,
            completionState:String,
            category:String,
            sessionId:String,
            readyGeneration:String):Object {
        return {
            wireRevision: 2,
            requestId: requestId,
            audioSessionId: sessionId,
            audioReadyGeneration: readyGeneration,
            deviceGeneration: "9",
            operation: operation,
            completionState: completionState,
            category: category,
            stage: completionState == "accepted_deferred" ? "admission" : "native_start",
            nativeCode: 0,
            hresult: 0,
            decoderBackend: completionState == "accepted_deferred" ? "none" : "builtin",
            messageKey: completionState == "superseded"
                ? "audio.bgm.superseded" : "audio.bgm.result"
        };
    }

    private static function copyObject(source:Object):Object {
        var result:Object = new Object();
        for (var key:String in source) {
            if (source.hasOwnProperty(key)) result[key] = source[key];
        }
        return result;
    }

    private static function ownKeyCount(value:Object):Number {
        var count:Number = 0;
        for (var key:String in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) count++;
        }
        return count;
    }

    private static function assertTrue(name:String, condition:Boolean):Void {
        if (condition) {
            passed++;
            trace("[PASS] " + name);
        } else {
            failed++;
            trace("[TEST_FAIL] " + name);
        }
    }

    private static function assertFalse(name:String, condition:Boolean):Void {
        if (!condition) {
            passed++;
            trace("[PASS] " + name);
        } else {
            failed++;
            trace("[TEST_FAIL] " + name);
        }
    }

    private static function assertEqual(name:String, expected, actual):Void {
        var detail:String = name + " expected=" + expected + " actual=" + actual;
        if (expected === actual) {
            passed++;
            trace("[PASS] " + detail);
        } else {
            failed++;
            trace("[TEST_FAIL] " + detail);
        }
    }
}
