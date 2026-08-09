using System;
using System.Linq;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Audio;

namespace CF7Launcher.Tests.Audio
{
    public class AudioWireV2Tests
    {
        private const string SessionId =
            "01234567-89ab-4cde-8f01-23456789abcd";

        [Theory]
        [InlineData(AudioWireV2.BgmPlay)]
        [InlineData(AudioWireV2.BgmStop)]
        [InlineData(AudioWireV2.BgmPause)]
        [InlineData(AudioWireV2.BgmResume)]
        [InlineData(AudioWireV2.BgmSeek)]
        [InlineData(AudioWireV2.BgmSetLoop)]
        [InlineData(AudioWireV2.BgmSetGain)]
        public void BgmParser_AcceptsEveryFrozenOperationWithOnlyItsPayload(
            string operation)
        {
            JObject message = Request(operation);

            AudioBgmRequestV2 parsed;
            string error;
            Assert.True(
                AudioWireV2.TryParseBgmRequest(
                    message, out parsed, out error),
                error);
            Assert.Null(error);
            Assert.Equal(AudioWireV2.WireRevision, parsed.WireRevision);
            Assert.Equal("bgm.request.1", parsed.RequestId);
            Assert.Equal(SessionId, parsed.AudioSessionId);
            Assert.Equal(42UL, parsed.AudioReadyGeneration);
            Assert.Equal(operation, parsed.Operation);
        }

        [Fact]
        public void BgmRawParser_RejectsDuplicatePropertiesBeforeCollapse()
        {
            const string raw =
                "{\"wireRevision\":2,"
                + "\"requestId\":\"bgm.request.1\","
                + "\"requestId\":\"bgm.request.2\","
                + "\"audioSessionId\":\"" + SessionId + "\","
                + "\"audioReadyGeneration\":\"42\","
                + "\"operation\":\"pause\"}";

            AudioBgmRequestV2 parsed;
            string error;
            Assert.False(
                AudioWireV2.TryParseBgmRequest(raw, out parsed, out error));
            Assert.Null(parsed);
            Assert.Equal("bgm.json_invalid", error);
        }

        [Theory]
        [InlineData("wireRevision")]
        [InlineData("requestId")]
        [InlineData("audioSessionId")]
        [InlineData("audioReadyGeneration")]
        [InlineData("operation")]
        [InlineData("path")]
        [InlineData("loop")]
        [InlineData("volume")]
        [InlineData("fadeSeconds")]
        public void BgmParser_RejectsEveryMissingPlayField(string field)
        {
            JObject message = Request(AudioWireV2.BgmPlay);
            Assert.True(message.Remove(field));
            AssertRejected(message);
        }

        [Theory]
        [InlineData("generation")]
        [InlineData("connectionGeneration")]
        [InlineData("task")]
        [InlineData("seekSeconds")]
        public void BgmParser_RejectsExtraAndForeignDomainKeys(string field)
        {
            JObject message = Request(AudioWireV2.BgmPlay);
            message[field] = field == "task" ? "audio" : "1";
            AssertRejected(message, "bgm.keys");
        }

        [Fact]
        public void BgmParser_RejectsWrongWireRevisionTypeAndValue()
        {
            JObject message = Request(AudioWireV2.BgmPause);

            message["wireRevision"] = "2";
            AssertRejected(message, "bgm.wire_revision");

            message["wireRevision"] = new JValue(2.0d);
            AssertRejected(message, "bgm.wire_revision");

            message["wireRevision"] = 1;
            AssertRejected(message, "bgm.wire_revision");

            message["wireRevision"] = 3;
            AssertRejected(message, "bgm.wire_revision");
        }

        [Fact]
        public void BgmParser_RejectsWrongCommonScalarTypes()
        {
            JObject message = Request(AudioWireV2.BgmPause);

            message["requestId"] = 1;
            AssertRejected(message, "bgm.request_id");

            message = Request(AudioWireV2.BgmPause);
            message["audioSessionId"] = new JObject();
            AssertRejected(message, "bgm.audio_session_id");

            message = Request(AudioWireV2.BgmPause);
            message["audioReadyGeneration"] = 42;
            AssertRejected(message, "bgm.audio_ready_generation");

            message = Request(AudioWireV2.BgmPause);
            message["operation"] = true;
            AssertRejected(message, "bgm.operation");
        }

        [Theory]
        [InlineData("0")]
        [InlineData("1")]
        [InlineData("18446744073709551615")]
        public void BgmParser_AcceptsCanonicalUint64DecimalStrings(string value)
        {
            JObject message = Request(AudioWireV2.BgmPause);
            message["audioReadyGeneration"] = value;

            AudioBgmRequestV2 parsed;
            string error;
            Assert.True(
                AudioWireV2.TryParseBgmRequest(
                    message, out parsed, out error),
                error);
            Assert.Equal(
                ulong.Parse(value, System.Globalization.CultureInfo.InvariantCulture),
                parsed.AudioReadyGeneration);
        }

        [Theory]
        [InlineData("")]
        [InlineData("+1")]
        [InlineData("-1")]
        [InlineData(" 1")]
        [InlineData("1 ")]
        [InlineData("01")]
        [InlineData("1.0")]
        [InlineData("１２")]
        [InlineData("18446744073709551616")]
        public void BgmParser_RejectsNonCanonicalOrOverflowGeneration(
            string value)
        {
            JObject message = Request(AudioWireV2.BgmPause);
            message["audioReadyGeneration"] = value;
            AssertRejected(message, "bgm.audio_ready_generation");
        }

        [Fact]
        public void BgmParser_RequiresLowercaseCanonicalUuidV4Session()
        {
            JObject message = Request(AudioWireV2.BgmPause);

            message["audioSessionId"] = SessionId.ToUpperInvariant();
            AssertRejected(message, "bgm.audio_session_id");

            message["audioSessionId"] =
                "01234567-89ab-1cde-8f01-23456789abcd";
            AssertRejected(message, "bgm.audio_session_id");

            message["audioSessionId"] =
                "01234567-89ab-4cde-7f01-23456789abcd";
            AssertRejected(message, "bgm.audio_session_id");

            message["audioSessionId"] = "{" + SessionId + "}";
            AssertRejected(message, "bgm.audio_session_id");
        }

        [Fact]
        public void BgmParser_RejectsUnknownOrWrongCaseOperation()
        {
            JObject message = Request(AudioWireV2.BgmPause);
            message["operation"] = "Pause";
            AssertRejected(message, "bgm.operation");

            message["operation"] = "crossfade";
            AssertRejected(message, "bgm.operation");
        }

        [Fact]
        public void BgmParser_RejectsUnusedOperationPayload()
        {
            JObject message = Request(AudioWireV2.BgmPause);
            message["fadeSeconds"] = 0.0d;
            AssertRejected(message, "bgm.keys");

            message = Request(AudioWireV2.BgmSeek);
            message["path"] = "sounds/test.mp3";
            AssertRejected(message, "bgm.keys");

            message = Request(AudioWireV2.BgmSetLoop);
            message["volume"] = 1.0d;
            AssertRejected(message, "bgm.keys");
        }

        [Fact]
        public void BgmParser_RejectsWrongPayloadTypesAndNonFiniteNumbers()
        {
            JObject message = Request(AudioWireV2.BgmPlay);
            message["loop"] = 1;
            AssertRejected(message, "bgm.loop");

            message = Request(AudioWireV2.BgmPlay);
            message["volume"] = "1";
            AssertRejected(message, "bgm.volume");

            message = Request(AudioWireV2.BgmPlay);
            message["volume"] = double.NaN;
            AssertRejected(message, "bgm.volume");

            message = Request(AudioWireV2.BgmPlay);
            message["volume"] = double.PositiveInfinity;
            AssertRejected(message, "bgm.volume");

            message = Request(AudioWireV2.BgmPlay);
            message["fadeSeconds"] = false;
            AssertRejected(message, "bgm.fade_seconds");

            message = Request(AudioWireV2.BgmSeek);
            message["seekSeconds"] = null;
            AssertRejected(message, "bgm.seek_seconds");
        }

        [Fact]
        public void BgmParser_RejectsOutOfRangePayloadNumbers()
        {
            JObject message = Request(AudioWireV2.BgmPlay);
            message["volume"] = -0.001d;
            AssertRejected(message, "bgm.volume");

            message = Request(AudioWireV2.BgmPlay);
            message["volume"] = AudioWireV2.MaxVolume + 0.001d;
            AssertRejected(message, "bgm.volume");

            message = Request(AudioWireV2.BgmStop);
            message["fadeSeconds"] = -1.0d;
            AssertRejected(message, "bgm.fade_seconds");

            message["fadeSeconds"] = AudioWireV2.MaxFadeSeconds + 0.001d;
            AssertRejected(message, "bgm.fade_seconds");

            message = Request(AudioWireV2.BgmSeek);
            message["seekSeconds"] = -1.0d;
            AssertRejected(message, "bgm.seek_seconds");

            message["seekSeconds"] = AudioWireV2.MaxSeekSeconds + 0.001d;
            AssertRejected(message, "bgm.seek_seconds");
        }

        [Fact]
        public void BgmParser_RejectsEmptyControlOrInvalidUnicodePath()
        {
            JObject message = Request(AudioWireV2.BgmPlay);
            message["path"] = "   ";
            AssertRejected(message, "bgm.path");

            message["path"] = "sounds/a.mp3\nother";
            AssertRejected(message, "bgm.path");

            message["path"] = "sounds/" + '\ud800' + ".mp3";
            AssertRejected(message, "bgm.path");
        }

        [Fact]
        public void BgmSerializer_UsesCanonicalOrderTypesAndRoundTrips()
        {
            AudioBgmRequestV2 parsed;
            string error;
            Assert.True(
                AudioWireV2.TryParseBgmRequest(
                    Request(AudioWireV2.BgmPlay),
                    out parsed,
                    out error),
                error);

            JObject serialized = AudioWireV2.SerializeBgmRequest(parsed);
            Assert.Equal(
                new[]
                {
                    "wireRevision",
                    "requestId",
                    "audioSessionId",
                    "audioReadyGeneration",
                    "operation",
                    "path",
                    "loop",
                    "volume",
                    "fadeSeconds"
                },
                serialized.Properties().Select(p => p.Name).ToArray());
            Assert.Equal(JTokenType.Integer, serialized["wireRevision"].Type);
            Assert.Equal(
                JTokenType.String,
                serialized["audioReadyGeneration"].Type);
            Assert.Null(serialized["generation"]);
            Assert.Null(serialized["connectionGeneration"]);

            AudioBgmRequestV2 reparsed;
            Assert.True(
                AudioWireV2.TryParseBgmRequest(
                    serialized.ToString(Formatting.None),
                    out reparsed,
                    out error),
                error);
            Assert.Equal(parsed.RequestId, reparsed.RequestId);
            Assert.Equal(parsed.Operation, reparsed.Operation);
            Assert.Equal(parsed.Path, reparsed.Path);
        }

        [Fact]
        public void FrozenVocabularies_MatchH1Exactly()
        {
            Assert.Equal(
                new[]
                {
                    "ok", "missing", "unsupported_container",
                    "unsupported_codec", "malformed", "truncated",
                    "io_error", "abi_mismatch", "not_ready",
                    "stale_generation", "unknown_id", "throttled",
                    "start_failed", "seek_failed", "device_unavailable",
                    "device_lost", "superseded", "internal_error"
                },
                AudioWireV2.ResultCategories);
            Assert.Equal(
                new[]
                {
                    "accepted_deferred", "started", "stopped",
                    "superseded", "failed"
                },
                AudioWireV2.CompletionStates);
            Assert.Equal(
                new[]
                {
                    "preReadyDrops", "recoveryDrops",
                    "staleGenerationDrops", "unknownIdCount",
                    "throttledCount", "startFailureCount", "playedCount"
                },
                AudioWireV2.CounterNames);
        }

        [Fact]
        public void BgmResultSerializer_IsCanonicalAndPreservesRawCodes()
        {
            JObject result = AudioWireV2.SerializeBgmResult(
                "bgm.request.1",
                SessionId,
                ulong.MaxValue,
                9,
                AudioWireV2.BgmPlay,
                "started",
                "ok",
                "native_start",
                -25,
                unchecked((int)0x80004005),
                "builtin",
                "audio.bgm.started");

            Assert.Equal(
                new[]
                {
                    "wireRevision", "requestId", "audioSessionId",
                    "audioReadyGeneration", "deviceGeneration", "operation",
                    "completionState", "category", "stage", "nativeCode",
                    "hresult", "decoderBackend", "messageKey"
                },
                result.Properties().Select(p => p.Name).ToArray());
            Assert.Equal(
                "18446744073709551615",
                (string)result["audioReadyGeneration"]);
            Assert.Equal("9", (string)result["deviceGeneration"]);
            Assert.Equal(-25, (int)result["nativeCode"]);
            Assert.Equal(
                unchecked((int)0x80004005),
                (int)result["hresult"]);
            Assert.Null(result["generation"]);
            Assert.Null(result["connectionGeneration"]);
        }

        [Fact]
        public void BgmResultSerializer_RejectsVocabularyAndSemanticDrift()
        {
            Assert.Throws<ArgumentException>(() => AudioWireV2.SerializeBgmResult(
                "bgm.request.1", SessionId, 1, 1, AudioWireV2.BgmPlay,
                "playing", "ok", "native_start", 0, 0, "builtin",
                "audio.bgm.started"));

            Assert.Throws<ArgumentException>(() => AudioWireV2.SerializeBgmResult(
                "bgm.request.1", SessionId, 1, 1, AudioWireV2.BgmPlay,
                "failed", "ok", "native_start", -1, 0, "builtin",
                "audio.bgm.failed"));

            Assert.Throws<ArgumentException>(() => AudioWireV2.SerializeBgmResult(
                "bgm.request.1", SessionId, 1, 1, AudioWireV2.BgmPlay,
                "superseded", "internal_error", "admission", 0, 0, "none",
                "audio.bgm.superseded"));

            Assert.Throws<ArgumentException>(() => AudioWireV2.SerializeBgmResult(
                "bgm.request.1", SessionId, 1, 1, AudioWireV2.BgmPlay,
                "failed", "made_up", "native_start", -1, 0, "builtin",
                "audio.bgm.failed"));
        }

        [Fact]
        public void SfxParser_PreservesOrderAndDuplicatePlaySemantics()
        {
            string message = "S2|" + SessionId
                + "|42|7|枪声.wav|枪声.wav|impact.mp3";

            AudioSfxBatchV2 batch;
            string error;
            Assert.True(
                AudioWireV2.TryParseSfxBatch(message, out batch, out error),
                error);
            Assert.Null(error);
            Assert.Equal(42UL, batch.AudioReadyGeneration);
            Assert.Equal(7UL, batch.BatchSequence);
            Assert.Equal(
                new[] { "枪声.wav", "枪声.wav", "impact.mp3" },
                batch.LinkageIds);
            Assert.Equal(message, AudioWireV2.SerializeSfxBatch(batch));
        }

        [Theory]
        [InlineData("")]
        [InlineData("S2")]
        [InlineData("S2|x|1|1|a.wav")]
        [InlineData("S|01234567-89ab-4cde-8f01-23456789abcd|1|1|a.wav")]
        [InlineData("S3|01234567-89ab-4cde-8f01-23456789abcd|1|1|a.wav")]
        [InlineData("s2|01234567-89ab-4cde-8f01-23456789abcd|1|1|a.wav")]
        public void SfxParser_RejectsMissingFieldsOrWrongRevision(string message)
        {
            AudioSfxBatchV2 batch;
            string error;
            Assert.False(
                AudioWireV2.TryParseSfxBatch(message, out batch, out error));
            Assert.Null(batch);
            Assert.NotNull(error);
        }

        [Fact]
        public void SfxParser_RequiresLowercaseCanonicalUuidV4Session()
        {
            string message = "S2|" + SessionId.ToUpperInvariant()
                + "|1|1|a.wav";
            AssertSfxRejected(message, "sfx.audio_session_id");

            message = "S2|01234567-89ab-1cde-8f01-23456789abcd"
                + "|1|1|a.wav";
            AssertSfxRejected(message, "sfx.audio_session_id");
        }

        [Theory]
        [InlineData("")]
        [InlineData("+1")]
        [InlineData("-1")]
        [InlineData("01")]
        [InlineData("1.0")]
        [InlineData("18446744073709551616")]
        public void SfxParser_RejectsInvalidOrOverflowReadyGeneration(
            string value)
        {
            AssertSfxRejected(
                "S2|" + SessionId + "|" + value + "|1|a.wav",
                "sfx.audio_ready_generation");
        }

        [Theory]
        [InlineData("")]
        [InlineData("+1")]
        [InlineData("-1")]
        [InlineData("01")]
        [InlineData("1.0")]
        [InlineData("18446744073709551616")]
        public void SfxParser_RejectsInvalidOrOverflowBatchSequence(
            string value)
        {
            AssertSfxRejected(
                "S2|" + SessionId + "|1|" + value + "|a.wav",
                "sfx.batch_sequence");
        }

        [Theory]
        [InlineData("")]
        [InlineData(".")]
        [InlineData("..")]
        [InlineData("pack/a.wav")]
        [InlineData("pack\\a.wav")]
        public void SfxParser_RejectsEmptyOrPathLikeLinkageId(string linkageId)
        {
            AssertSfxRejected(
                "S2|" + SessionId + "|1|1|" + linkageId,
                "sfx.linkage_id");
        }

        [Fact]
        public void SfxParser_RejectsTrailingEmptyIdAndControlCharacters()
        {
            AssertSfxRejected(
                "S2|" + SessionId + "|1|1|a.wav|",
                "sfx.linkage_id");
            AssertSfxRejected(
                "S2|" + SessionId + "|1|1|a.wav\n",
                "sfx.control_character");
        }

        [Fact]
        public void SfxParser_RejectsInvalidUnicode()
        {
            string message = "S2|" + SessionId + "|1|1|" + '\ud800';
            AssertSfxRejected(message, "sfx.invalid_unicode");
        }

        [Fact]
        public void SfxParser_RejectsMoreThanFixedIdCount()
        {
            string message = "S2|" + SessionId + "|1|1|"
                + string.Join(
                    "|",
                    Enumerable.Range(0, AudioWireV2.MaxSfxBatchIds + 1)
                        .Select(i => "id" + i + ".wav"));
            AssertSfxRejected(message, "sfx.too_many_ids");
        }

        [Fact]
        public void SfxParser_AcceptsExactIdCountBound()
        {
            string message = "S2|" + SessionId + "|0|0|"
                + string.Join(
                    "|",
                    Enumerable.Range(0, AudioWireV2.MaxSfxBatchIds)
                        .Select(i => "id" + i + ".wav"));

            AudioSfxBatchV2 batch;
            string error;
            Assert.True(
                AudioWireV2.TryParseSfxBatch(message, out batch, out error),
                error);
            Assert.Equal(AudioWireV2.MaxSfxBatchIds, batch.LinkageIds.Count);
        }

        [Fact]
        public void SfxParser_RejectsUtf8MessageBeyondFixedBoundBeforeSplit()
        {
            string largeId = new string('界', 200);
            string message = "S2|" + SessionId + "|1|1|"
                + string.Join(
                    "|",
                    Enumerable.Repeat(
                        largeId,
                        AudioWireV2.MaxSfxBatchIds));
            Assert.True(
                new UTF8Encoding(false, true).GetByteCount(message)
                    > AudioWireV2.MaxSfxMessageUtf8Bytes);
            AssertSfxRejected(message, "sfx.message_too_large");
        }

        [Fact]
        public void SfxCounterSerializer_UsesExactNamesAndDecimalStrings()
        {
            var counters = new AudioSfxCountersV2(
                SessionId,
                ulong.MaxValue,
                3,
                1,
                2,
                3,
                4,
                5,
                6,
                ulong.MaxValue);

            JObject result = AudioWireV2.SerializeSfxCounters(counters);
            Assert.Equal(
                new[]
                {
                    "wireRevision", "audioSessionId", "audioReadyGeneration",
                    "deviceGeneration", "preReadyDrops", "recoveryDrops",
                    "staleGenerationDrops", "unknownIdCount", "throttledCount",
                    "startFailureCount", "playedCount"
                },
                result.Properties().Select(p => p.Name).ToArray());
            Assert.Equal(
                "18446744073709551615",
                (string)result["audioReadyGeneration"]);
            Assert.Equal(
                "18446744073709551615",
                (string)result["playedCount"]);
            foreach (string name in AudioWireV2.CounterNames)
                Assert.Equal(JTokenType.String, result[name].Type);
            Assert.Null(result["generation"]);
            Assert.Null(result["connectionGeneration"]);
        }

        [Fact]
        public void VocabularyMembership_IsOrdinalAndClosed()
        {
            Assert.True(AudioWireV2.IsResultCategory("stale_generation"));
            Assert.False(AudioWireV2.IsResultCategory("Stale_Generation"));
            Assert.False(AudioWireV2.IsResultCategory("made_up"));
            Assert.True(AudioWireV2.IsCompletionState("accepted_deferred"));
            Assert.False(AudioWireV2.IsCompletionState("accepted"));
            Assert.True(AudioWireV2.IsCounterName("preReadyDrops"));
            Assert.False(AudioWireV2.IsCounterName("prereadydrops"));
        }

        private static JObject Request(string operation)
        {
            var result = new JObject
            {
                ["wireRevision"] = AudioWireV2.WireRevision,
                ["requestId"] = "bgm.request.1",
                ["audioSessionId"] = SessionId,
                ["audioReadyGeneration"] = "42",
                ["operation"] = operation
            };

            if (operation == AudioWireV2.BgmPlay)
            {
                result["path"] = "sounds/music/test.mp3";
                result["loop"] = true;
                result["volume"] = 0.75d;
                result["fadeSeconds"] = 1.25d;
            }
            else if (operation == AudioWireV2.BgmStop)
            {
                result["fadeSeconds"] = 1.0d;
            }
            else if (operation == AudioWireV2.BgmSeek)
            {
                result["seekSeconds"] = 12.5d;
            }
            else if (operation == AudioWireV2.BgmSetLoop)
            {
                result["loop"] = false;
            }
            else if (operation == AudioWireV2.BgmSetGain)
            {
                result["volume"] = 0.5d;
            }
            return result;
        }

        private static void AssertRejected(
            JObject message,
            string expectedError = null)
        {
            AudioBgmRequestV2 parsed;
            string error;
            Assert.False(
                AudioWireV2.TryParseBgmRequest(
                    message, out parsed, out error));
            Assert.Null(parsed);
            Assert.NotNull(error);
            if (expectedError != null) Assert.Equal(expectedError, error);
        }

        private static void AssertSfxRejected(
            string message,
            string expectedError)
        {
            AudioSfxBatchV2 batch;
            string error;
            Assert.False(
                AudioWireV2.TryParseSfxBatch(message, out batch, out error));
            Assert.Null(batch);
            Assert.Equal(expectedError, error);
        }
    }
}
