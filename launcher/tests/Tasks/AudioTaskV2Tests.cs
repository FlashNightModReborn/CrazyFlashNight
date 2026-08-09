using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Audio;
using CF7Launcher.Bus;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class AudioTaskV2Tests
    {
        private const string SessionId =
            "01234567-89ab-4cde-8f01-23456789abcd";

        [Fact]
        public void ValidBgmEnvelope_DispatchesTypedRequestAndCanonicalResult()
        {
            var facade = new RecordingFacade();
            var task = new AudioTask(facade);
            var responses = new List<string>();

            task.HandleAsync(PlayEnvelope(), responses.Add);

            AudioBgmRequestV2 request = Assert.Single(facade.BgmRequests);
            Assert.Equal("bgm.request.1", request.RequestId);
            Assert.Equal(SessionId, request.AudioSessionId);
            Assert.Equal(42UL, request.AudioReadyGeneration);
            Assert.Equal(AudioWireV2.BgmPlay, request.Operation);
            Assert.Equal("sounds/music/test.mp3", request.Path);
            Assert.True(request.Loop.Value);
            Assert.Equal(0.75d, request.Volume.Value);

            JObject response = JObject.Parse(Assert.Single(responses));
            Assert.Equal(
                new[]
                {
                    "wireRevision", "requestId", "audioSessionId",
                    "audioReadyGeneration", "deviceGeneration", "operation",
                    "completionState", "category", "stage", "nativeCode",
                    "hresult", "decoderBackend", "messageKey"
                },
                response.Properties().Select(p => p.Name).ToArray());
            Assert.Equal("started", (string)response["completionState"]);
            Assert.Equal("ok", (string)response["category"]);
            Assert.Null(response["generation"]);
            Assert.Null(response["connectionGeneration"]);
        }

        [Theory]
        [InlineData("generation")]
        [InlineData("connectionGeneration")]
        [InlineData("callId")]
        [InlineData("cmd")]
        public void ExtraTransportOrLegacyKey_IsRejectedBeforeFacadeDispatch(
            string key)
        {
            var facade = new RecordingFacade();
            var task = new AudioTask(facade);
            JObject envelope = PlayEnvelope();
            envelope[key] = key == "callId" ? "legacy-call" : "1";

            task.HandleAsync(envelope, delegate(string ignored) { });

            Assert.Empty(facade.BgmRequests);
            Assert.Equal("bgm.keys", Assert.Single(facade.BgmRejections));
        }

        [Fact]
        public void MissingOrWrongTaskEnvelope_IsRejected()
        {
            var facade = new RecordingFacade();
            var task = new AudioTask(facade);
            JObject envelope = PlayEnvelope();
            envelope.Remove("task");
            task.HandleAsync(envelope, null);

            envelope = PlayEnvelope();
            envelope["task"] = "Audio";
            task.HandleAsync(envelope, null);

            Assert.Empty(facade.BgmRequests);
            Assert.Equal(
                new[] { "bgm.envelope", "bgm.envelope" },
                facade.BgmRejections);
        }

        [Fact]
        public void FacadeMayEmitDeferredThenStartedForOneRequest()
        {
            var facade = new RecordingFacade { AutoRespond = false };
            var task = new AudioTask(facade);
            var responses = new List<string>();

            task.HandleAsync(PlayEnvelope(), responses.Add);
            AudioBgmRequestV2 request = Assert.Single(facade.BgmRequests);

            facade.Respond(new AudioBgmResultV2(
                request.RequestId, request.AudioSessionId,
                request.AudioReadyGeneration, 5, request.Operation,
                "accepted_deferred", "ok", "admission", 0, 0, "none",
                "audio.bgm.accepted_deferred"));
            facade.Respond(new AudioBgmResultV2(
                request.RequestId, request.AudioSessionId,
                request.AudioReadyGeneration, 5, request.Operation,
                "started", "ok", "native_start", 0, 0, "builtin",
                "audio.bgm.started"));

            Assert.Equal(2, responses.Count);
            Assert.Equal(
                "accepted_deferred",
                (string)JObject.Parse(responses[0])["completionState"]);
            Assert.Equal(
                "started",
                (string)JObject.Parse(responses[1])["completionState"]);
        }

        [Fact]
        public void InvalidFacadeResult_IsDroppedInsteadOfLeakingArbitraryJson()
        {
            var facade = new RecordingFacade { AutoRespond = false };
            var task = new AudioTask(facade);
            var responses = new List<string>();

            task.HandleAsync(PlayEnvelope(), responses.Add);
            AudioBgmRequestV2 request = Assert.Single(facade.BgmRequests);
            facade.Respond(new AudioBgmResultV2(
                request.RequestId, request.AudioSessionId,
                request.AudioReadyGeneration, 5, request.Operation,
                "started", "internal_error", "native_start", -1, 0,
                "builtin", "audio.bgm.invalid"));

            Assert.Empty(responses);
        }

        [Fact]
        public void ValidS2Batch_DispatchesToSameFacadeWithoutReplayOrDedup()
        {
            var facade = new RecordingFacade();
            var task = new AudioTask(facade);

            Assert.True(task.HandleSfxFastLane(
                "S2|" + SessionId + "|42|7|gun.wav|gun.wav"));

            AudioSfxBatchV2 batch = Assert.Single(facade.SfxBatches);
            Assert.Equal(42UL, batch.AudioReadyGeneration);
            Assert.Equal(7UL, batch.BatchSequence);
            Assert.Equal(new[] { "gun.wav", "gun.wav" }, batch.LinkageIds);
            Assert.Empty(facade.SfxRejections);
        }

        [Fact]
        public void LegacyOrMalformedSfx_IsRejectedWithoutDispatch()
        {
            var facade = new RecordingFacade();
            var task = new AudioTask(facade);

            Assert.False(task.HandleSfxFastLane("Sgun.wav"));
            Assert.False(task.HandleSfxFastLane(
                "S2|" + SessionId + "|+1|1|gun.wav"));

            Assert.Empty(facade.SfxBatches);
            Assert.Equal(2, facade.SfxRejections.Count);
            Assert.Equal("sfx.fields_missing", facade.SfxRejections[0]);
            Assert.Equal(
                "sfx.audio_ready_generation",
                facade.SfxRejections[1]);
        }

        [Fact]
        public void TaskRegistry_RegistersAsyncSocketOnlyAudioMetadata()
        {
            JObject status = JObject.Parse(
                TaskRegistry.ToStatusJson(true, 3000, 3001));
            JObject audio = ((JArray)status["tasks"])
                .Children<JObject>()
                .Single(x => (string)x["name"] == "audio");

            Assert.Equal("json_async", (string)audio["transport"]);
            Assert.Equal("AS2<->C#", (string)audio["direction"]);
            Assert.False((bool)audio["httpCallable"]);
            Assert.False(TaskRegistry.IsHttpCallable("audio"));
        }

        [Fact]
        public void TaskRegistry_BindsBgmSfxAndBootstrapToOneFacade()
        {
            var facade = new RecordingFacade();
            var audio = new AudioTask(facade);
            var router = new MessageRouter();
            try
            {
                TaskRegistry.RegisterAudioV2(router, audio);

                var responses = new List<string>();
                Assert.Null(router.ProcessMessage(
                    PlayEnvelope().ToString(Formatting.None),
                    responses.Add));
                Assert.True(TaskRegistry.TryDispatchAudioSfxV2(
                    router,
                    "S2|" + SessionId + "|42|1|gun.wav"));
                AudioTask.ArmBootstrapBgmGate();
                AudioTask.ReleaseBootstrapBgmGate();
                AudioTask.CancelBootstrapBgmGate();

                Assert.Single(facade.BgmRequests);
                Assert.Single(responses);
                Assert.Single(facade.SfxBatches);
                Assert.Equal(1, facade.ArmCount);
                Assert.Equal(1, facade.ReleaseCount);
                Assert.Equal(1, facade.CancelCount);
            }
            finally
            {
                AudioTask.ResetProcessFacadeForTests();
            }
        }

        private static JObject PlayEnvelope()
        {
            return new JObject
            {
                ["task"] = "audio",
                ["wireRevision"] = AudioWireV2.WireRevision,
                ["requestId"] = "bgm.request.1",
                ["audioSessionId"] = SessionId,
                ["audioReadyGeneration"] = "42",
                ["operation"] = AudioWireV2.BgmPlay,
                ["path"] = "sounds/music/test.mp3",
                ["loop"] = true,
                ["volume"] = 0.75d,
                ["fadeSeconds"] = 1.25d
            };
        }

        private sealed class RecordingFacade : IAudioCommandFacadeV2
        {
            private Action<AudioBgmResultV2> _respond;

            public readonly List<AudioBgmRequestV2> BgmRequests =
                new List<AudioBgmRequestV2>();
            public readonly List<string> BgmRejections = new List<string>();
            public readonly List<AudioSfxBatchV2> SfxBatches =
                new List<AudioSfxBatchV2>();
            public readonly List<string> SfxRejections = new List<string>();

            public bool AutoRespond = true;
            public int ArmCount;
            public int CancelCount;
            public int ReleaseCount;

            public void DispatchBgm(
                AudioBgmRequestV2 request,
                Action<AudioBgmResultV2> respond)
            {
                BgmRequests.Add(request);
                _respond = respond;
                if (AutoRespond)
                {
                    respond(new AudioBgmResultV2(
                        request.RequestId,
                        request.AudioSessionId,
                        request.AudioReadyGeneration,
                        5,
                        request.Operation,
                        "started",
                        "ok",
                        "native_start",
                        0,
                        0,
                        "builtin",
                        "audio.bgm.started"));
                }
            }

            public void Respond(AudioBgmResultV2 result)
            {
                Assert.NotNull(_respond);
                _respond(result);
            }

            public void RejectBgm(string protocolError)
            {
                BgmRejections.Add(protocolError);
            }

            public void DispatchSfx(AudioSfxBatchV2 batch)
            {
                SfxBatches.Add(batch);
            }

            public void RejectSfx(string protocolError)
            {
                SfxRejections.Add(protocolError);
            }

            public void ArmBootstrapBgmGate()
            {
                ArmCount++;
            }

            public void CancelBootstrapBgmGate()
            {
                CancelCount++;
            }

            public void ReleaseBootstrapBgmGate()
            {
                ReleaseCount++;
            }
        }
    }
}
