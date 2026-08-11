using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Audio;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class AudioQualificationStimulusV1Tests
    {
        private static readonly string[] OrderedCases =
        {
            "bgm_playback",
            "bgm_seek",
            "bgm_crossfade",
            "format_vorbis",
            "format_aac_mp4",
            "format_opus",
            "sfx_playback",
            "dense_overlap_throttle",
            "bgm_sfx_mix",
            "gain_zero_and_default_max",
            "default_device_switch",
            "physical_route_bluetooth_or_hdmi",
            "sleep_resume",
            "no_stale_sfx_after_recovery"
        };

        [Fact]
        public async Task Dispatch_BindsActiveCaseCandidateAndExactFlashShape()
        {
            const string runId = "11111111111111111111111111111112";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(diagnostics, runId, "bgm_playback");
                var transport = new FakeTransport { ReadyGeneration = 17 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                using (var client = new PipeClient(host.PipeName))
                {
                    Assert.True(host.UsesCurrentUserOnly);
                    Assert.Equal(
                        AudioQualificationStimulusHostV1.BuildPipeName(
                            Environment.ProcessId,
                            runId),
                        host.PipeName);
                    Assert.Equal(
                        "{\"action\":\"audioV2QualificationStimulus\",\"operation\":\"arm\",\"runId\":\"" +
                            runId + "\",\"task\":\"cmd\"}\0",
                        Assert.Single(transport.Messages).Payload);

                    string path = QualificationPath(runId, "baseline-a.mp3");
                    byte[] request = Request(
                        runId,
                        "dispatch",
                        1,
                        "bgm_playback",
                        "play",
                        path: path,
                        fadeSeconds: 0,
                        loop: true,
                        volume: 1);
                    using (JsonDocument response =
                        await client.ExchangeAsync(request))
                    {
                        JsonElement root = response.RootElement;
                        Assert.Equal("ok", root.GetProperty("result").GetString());
                        Assert.True(root.GetProperty("sent").GetBoolean());
                        Assert.Equal(
                            AudioQualificationStimulusHostV1.ResponseSchema,
                            root.GetProperty("schema").GetString());
                        Assert.Equal(Environment.ProcessId, root
                            .GetProperty("candidate")
                            .GetProperty("pid")
                            .GetInt32());
                    }

                    Assert.Equal(3, transport.Messages.Count);
                    Assert.Equal(17, transport.Messages[1].Generation);
                    Assert.Contains(
                        "\"operation\":\"arm\"",
                        transport.Messages[1].Payload,
                        StringComparison.Ordinal);
                    Assert.Equal(17, transport.Messages[2].Generation);
                    Assert.Equal(
                        "{\"action\":\"audioV2QualificationStimulus\",\"caseId\":\"bgm_playback\",\"fadeSeconds\":0,\"loop\":true,\"operation\":\"play\",\"path\":\"" +
                            path + "\",\"runId\":\"" + runId +
                            "\",\"task\":\"cmd\",\"volume\":1}\0",
                        transport.Messages[2].Payload);

                    Assert.Null(await client.ExchangeOrClosedAsync(request));
                    Assert.Equal(3, transport.Messages.Count);
                }
            }
        }

        [Fact]
        public async Task InvalidPathAndWrongCase_FailClosedThenNewClientCanRetry()
        {
            const string runId = "22222222222222222222222222222223";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(diagnostics, runId, "bgm_playback");
                var transport = new FakeTransport { ReadyGeneration = 3 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    byte[] invalidPath = Request(
                        runId,
                        "dispatch",
                        1,
                        "bgm_playback",
                        "play",
                        path: "sounds/not-qualified.mp3",
                        fadeSeconds: 0,
                        loop: true,
                        volume: 1);
                    using (var first = new PipeClient(host.PipeName))
                        Assert.Null(await first.ExchangeOrClosedAsync(invalidPath));
                    Assert.Single(transport.Messages);

                    byte[] wrongCase = Request(
                        runId,
                        "dispatch",
                        2,
                        "format_vorbis",
                        "play",
                        path: QualificationPath(runId, "vorbis.ogg"),
                        fadeSeconds: 0,
                        loop: true,
                        volume: 1);
                    using (var second = new PipeClient(host.PipeName))
                        Assert.Null(await second.ExchangeOrClosedAsync(wrongCase));
                    Assert.Single(transport.Messages);

                    byte[] valid = Request(
                        runId,
                        "dispatch",
                        3,
                        "bgm_playback",
                        "play",
                        path: QualificationPath(runId, "baseline-a.mp3"),
                        fadeSeconds: 0,
                        loop: true,
                        volume: 1);
                    using (var third = new PipeClient(host.PipeName))
                    using (JsonDocument response =
                        await third.ExchangeAsync(valid))
                    {
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                    Assert.Equal(3, transport.Messages.Count);
                }
            }
        }

        [Fact]
        public async Task Pipe_RejectsWrongRunNonCanonicalAndOversizeFrames()
        {
            const string runId = "28282828282828282828282828282829";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(diagnostics, runId, "bgm_playback");
                var transport = new FakeTransport { ReadyGeneration = 4 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    byte[] wrongRun = Request(
                        "2929292929292929292929292929292a",
                        "dispatch",
                        1,
                        "bgm_playback",
                        "play",
                        path: QualificationPath(
                            "2929292929292929292929292929292a",
                            "baseline-a.mp3"),
                        fadeSeconds: 0,
                        loop: true,
                        volume: 1);
                    using (var first = new PipeClient(host.PipeName))
                        Assert.Null(await first.ExchangeOrClosedAsync(wrongRun));

                    byte[] canonical = Request(
                        runId,
                        "dispatch",
                        2,
                        "bgm_playback",
                        "play",
                        path: QualificationPath(runId, "baseline-a.mp3"),
                        fadeSeconds: 0,
                        loop: true,
                        volume: 1);
                    byte[] nonCanonical = Encoding.UTF8.GetBytes(
                        Encoding.UTF8.GetString(canonical).Replace(
                            "{",
                            "{ ",
                            StringComparison.Ordinal));
                    using (var second = new PipeClient(host.PipeName))
                        Assert.Null(await second.ExchangeOrClosedAsync(
                            nonCanonical));

                    byte[] oversized = Enumerable.Repeat(
                        (byte)'a',
                        AudioQualificationStimulusHostV1.MaxRequestBytes + 1)
                        .ToArray();
                    using (var third = new PipeClient(host.PipeName))
                        Assert.Null(await third.ExchangeOrClosedAsync(oversized));

                    Assert.Single(transport.Messages);
                }
            }
        }

        [Fact]
        public void ReadyDisconnectReconnect_AutomaticallyArmsEachGenerationOnce()
        {
            const string runId = "33333333333333333333333333333334";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                var transport = new FakeTransport { ReadyGeneration = 5 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    Assert.Single(transport.Messages);
                    host.NotifyClientReadyForTests(5);
                    Assert.Single(transport.Messages);

                    host.NotifyClientDisconnectedForTests(5);
                    transport.ReadyGeneration = 6;
                    host.NotifyClientReadyForTests(6);
                    host.NotifyClientReadyForTests(6);

                    Assert.Equal(2, transport.Messages.Count);
                    Assert.Equal(new[] { 5, 6 }, transport.Messages
                        .Select(entry => entry.Generation)
                        .ToArray());
                    Assert.All(transport.Messages, entry =>
                        Assert.Contains(
                            "\"operation\":\"arm\"",
                            entry.Payload,
                            StringComparison.Ordinal));
                }
            }
        }

        [Fact]
        public async Task Dispatch_RearmsAfterInitialArmWasLostBeforeLateHandler()
        {
            const string runId = "90909090909090909090909090909091";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(diagnostics, runId, "bgm_playback");
                bool handlerReady = false;
                var received = new List<string>();
                var transport = new FakeTransport
                {
                    ReadyGeneration = 51,
                    OnSend = delegate(string payload)
                    {
                        if (handlerReady) received.Add(FlashOperation(payload));
                    }
                };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    Assert.Equal(
                        new[] { "arm" },
                        transport.Messages.Select(entry =>
                            FlashOperation(entry.Payload)).ToArray());
                    Assert.Empty(received);

                    handlerReady = true;
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            1,
                            "bgm_playback",
                            "play",
                            path: QualificationPath(runId, "baseline-a.mp3"),
                            fadeSeconds: 0,
                            loop: true,
                            volume: 1)))
                    {
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }

                    Assert.Equal(new[] { "arm", "play" }, received.ToArray());
                    Assert.Equal(
                        new[] { "arm", "arm", "play" },
                        transport.Messages.Select(entry =>
                            FlashOperation(entry.Payload)).ToArray());
                    Assert.All(
                        transport.Messages,
                        entry => Assert.Equal(51, entry.Generation));
                }
            }
        }

        [Fact]
        public async Task RepeatedDispatches_RearmBeforeEachStimulus()
        {
            const string runId = "91919191919191919191919191919192";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(
                    diagnostics,
                    runId,
                    "gain_zero_and_default_max");
                var transport = new FakeTransport { ReadyGeneration = 52 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            1,
                            "gain_zero_and_default_max",
                            "set_gain",
                            volume: 1)))
                    {
                    }
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            2,
                            "gain_zero_and_default_max",
                            "set_gain",
                            volume: 0)))
                    {
                    }

                    Assert.Equal(
                        new[] { "arm", "arm", "set_gain", "arm", "set_gain" },
                        transport.Messages.Select(entry =>
                            FlashOperation(entry.Payload)).ToArray());
                    Assert.All(
                        transport.Messages,
                        entry => Assert.Equal(52, entry.Generation));
                }
            }
        }

        [Fact]
        public async Task ReconnectedDispatch_RearmsOnTheNewGeneration()
        {
            const string runId = "92929292929292929292929292929293";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(diagnostics, runId, "bgm_playback");
                var transport = new FakeTransport { ReadyGeneration = 53 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    host.NotifyClientDisconnectedForTests(53);
                    transport.ReadyGeneration = 54;
                    host.NotifyClientReadyForTests(54);

                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            1,
                            "bgm_playback",
                            "play",
                            path: QualificationPath(runId, "baseline-a.mp3"),
                            fadeSeconds: 0,
                            loop: true,
                            volume: 1)))
                    {
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }

                    Assert.Equal(
                        new[] { "arm", "arm", "arm", "play" },
                        transport.Messages.Select(entry =>
                            FlashOperation(entry.Payload)).ToArray());
                    Assert.Equal(
                        new[] { 53, 54, 54, 54 },
                        transport.Messages.Select(entry => entry.Generation)
                            .ToArray());
                }
            }
        }

        [Fact]
        public async Task FailedRearm_DoesNotSendOrAdvanceAndCanRetry()
        {
            const string runId = "93939393939393939393939393939394";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(diagnostics, runId, "bgm_playback");
                var transport = new FakeTransport { ReadyGeneration = 55 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    transport.FailNextArmSend = true;
                    using (var failed = new PipeClient(host.PipeName))
                        Assert.Null(await failed.ExchangeOrClosedAsync(Request(
                            runId,
                            "dispatch",
                            1,
                            "bgm_playback",
                            "play",
                            path: QualificationPath(runId, "baseline-a.mp3"),
                            fadeSeconds: 0,
                            loop: true,
                            volume: 1)));
                    Assert.Equal(
                        new[] { "arm" },
                        transport.Messages.Select(entry =>
                            FlashOperation(entry.Payload)).ToArray());

                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            2,
                            "bgm_playback",
                            "play",
                            path: QualificationPath(runId, "baseline-a.mp3"),
                            fadeSeconds: 0,
                            loop: true,
                            volume: 1)))
                    {
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                    Assert.Equal(
                        new[] { "arm", "arm", "play" },
                        transport.Messages.Select(entry =>
                            FlashOperation(entry.Payload)).ToArray());
                }
            }
        }

        [Fact]
        public async Task DisconnectedDispatch_DoesNotAdvanceAndCanRetryAfterReadyArm()
        {
            const string runId = "38383838383838383838383838383839";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(diagnostics, runId, "bgm_playback");
                var transport = new FakeTransport { ReadyGeneration = 0 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    byte[] firstRequest = Request(
                        runId,
                        "dispatch",
                        1,
                        "bgm_playback",
                        "play",
                        path: QualificationPath(runId, "baseline-a.mp3"),
                        fadeSeconds: 0,
                        loop: true,
                        volume: 1);
                    using (var first = new PipeClient(host.PipeName))
                        Assert.Null(await first.ExchangeOrClosedAsync(
                            firstRequest));
                    Assert.Empty(transport.Messages);

                    transport.ReadyGeneration = 12;
                    host.NotifyClientReadyForTests(12);
                    Assert.Single(transport.Messages);
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            2,
                            "bgm_playback",
                            "play",
                            path: QualificationPath(
                                runId,
                                "baseline-a.mp3"),
                            fadeSeconds: 0,
                            loop: true,
                            volume: 1)))
                    {
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                    Assert.Equal(3, transport.Messages.Count);
                }
            }
        }

        [Fact]
        public async Task GainAndDenseGrammar_AreOrderedAndBounded()
        {
            const string runId = "44444444444444444444444444444445";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(
                    diagnostics,
                    runId,
                    "dense_overlap_throttle");
                var transport = new FakeTransport { ReadyGeneration = 8 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    using (var uniqueIds = new PipeClient(host.PipeName))
                        Assert.Null(await uniqueIds.ExchangeOrClosedAsync(Request(
                            runId,
                            "dispatch",
                            1,
                            "dense_overlap_throttle",
                            "sfx",
                            linkageIds: new[] { "a", "b", "c", "d", "e", "f" })));

                    string[] ids = { "a", "a", "a", "a", "a", "a" };
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            2,
                            "dense_overlap_throttle",
                            "sfx",
                            linkageIds: ids)))
                    {
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                    Assert.Contains(
                        "\"linkageIds\":[\"a\",\"a\",\"a\",\"a\",\"a\",\"a\"]",
                        transport.Messages[2].Payload,
                        StringComparison.Ordinal);

                    using (var retry = new PipeClient(host.PipeName))
                        Assert.Null(await retry.ExchangeOrClosedAsync(Request(
                            runId,
                            "dispatch",
                            3,
                            "dense_overlap_throttle",
                            "sfx",
                            linkageIds: ids)));
                }
            }

            const string gainRunId = "55555555555555555555555555555556";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(gainRunId))
            {
                await ActivateCaseAsync(
                    diagnostics,
                    gainRunId,
                    "gain_zero_and_default_max");
                var transport = new FakeTransport { ReadyGeneration = 9 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    gainRunId,
                    diagnostics,
                    transport))
                {
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            gainRunId,
                            "dispatch",
                            1,
                            "gain_zero_and_default_max",
                            "set_gain",
                            volume: 1)))
                    {
                    }
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            gainRunId,
                            "dispatch",
                            2,
                            "gain_zero_and_default_max",
                            "set_gain",
                            volume: 0)))
                    {
                    }
                    using (var third = new PipeClient(host.PipeName))
                        Assert.Null(await third.ExchangeOrClosedAsync(Request(
                            gainRunId,
                            "dispatch",
                            3,
                            "gain_zero_and_default_max",
                            "set_gain",
                            volume: 0)));
                    Assert.Equal(5, transport.Messages.Count);

                    using (var earlyRestore = new PipeClient(host.PipeName))
                        Assert.Null(await earlyRestore.ExchangeOrClosedAsync(
                            Request(
                                gainRunId,
                                "post_gain_restore",
                                4,
                                "post_gain_restore",
                                "set_gain",
                                volume: 1)));
                    Assert.Equal(5, transport.Messages.Count);

                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            gainRunId,
                            "end_case",
                            900,
                            "gain_zero_and_default_max")))
                    {
                    }
                    Assert.True(diagnostics.IsBetweenCases(
                        "gain_zero_and_default_max",
                        "default_device_switch"));
                    using (JsonDocument restored = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            gainRunId,
                            "post_gain_restore",
                            5,
                            "post_gain_restore",
                            "set_gain",
                            volume: 1)))
                    {
                        Assert.True(restored.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                    Assert.Equal(7, transport.Messages.Count);
                    Assert.Contains(
                        "\"caseId\":\"post_gain_restore\"",
                        transport.Messages[6].Payload,
                        StringComparison.Ordinal);
                    using (var duplicateRestore = new PipeClient(host.PipeName))
                        Assert.Null(await duplicateRestore.ExchangeOrClosedAsync(
                            Request(
                                gainRunId,
                                "post_gain_restore",
                                6,
                                "post_gain_restore",
                                "set_gain",
                                volume: 1)));
                    Assert.Equal(7, transport.Messages.Count);
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            gainRunId,
                            "begin_case",
                            901,
                            "default_device_switch")))
                    {
                    }
                    Assert.False(diagnostics.IsBetweenCases(
                        "gain_zero_and_default_max",
                        "default_device_switch"));
                }
            }
        }

        [Fact]
        public async Task BetweenCaseGainControls_AreExactOneShotAndOrdered()
        {
            const string runId = "56565656565656565656565656565657";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(diagnostics, runId, "format_opus");
                var transport = new FakeTransport { ReadyGeneration = 10 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    using (var beforeMute = new PipeClient(host.PipeName))
                        Assert.Null(await beforeMute.ExchangeOrClosedAsync(
                            Request(
                                runId,
                                "pre_sfx_bgm_mute",
                                1,
                                "pre_sfx_bgm_mute",
                                "set_gain",
                                volume: 0)));

                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            2,
                            "format_opus",
                            "play",
                            path: QualificationPath(runId, "format-opus.opus"),
                            fadeSeconds: 0,
                            loop: true,
                            volume: 1)))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(runId, "end_case", 700, "format_opus")))
                    {
                    }
                    Assert.True(diagnostics.IsBetweenCases(
                        "format_opus",
                        "sfx_playback"));

                    using (var wrongMute = new PipeClient(host.PipeName))
                        Assert.Null(await wrongMute.ExchangeOrClosedAsync(
                            Request(
                                runId,
                                "pre_sfx_bgm_mute",
                                3,
                                "pre_sfx_bgm_mute",
                                "set_gain",
                                volume: 1)));
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "pre_sfx_bgm_mute",
                            4,
                            "pre_sfx_bgm_mute",
                            "set_gain",
                            volume: 0)))
                    {
                        Assert.Equal("pre_sfx_bgm_mute", response.RootElement
                            .GetProperty("command").GetString());
                        Assert.Equal("pre_sfx_bgm_mute", response.RootElement
                            .GetProperty("caseId").GetString());
                        Assert.Equal("ok", response.RootElement
                            .GetProperty("result").GetString());
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                        Assert.Equal(Environment.ProcessId, response.RootElement
                            .GetProperty("candidate")
                            .GetProperty("pid")
                            .GetInt32());
                    }
                    Assert.Equal(
                        "{\"action\":\"audioV2QualificationStimulus\",\"caseId\":\"pre_sfx_bgm_mute\",\"operation\":\"set_gain\",\"runId\":\"" +
                            runId +
                            "\",\"task\":\"cmd\",\"volume\":0}\0",
                        transport.Messages[4].Payload);

                    using (var duplicateMute = new PipeClient(host.PipeName))
                        Assert.Null(await duplicateMute.ExchangeOrClosedAsync(
                            Request(
                                runId,
                                "pre_sfx_bgm_mute",
                                5,
                                "pre_sfx_bgm_mute",
                                "set_gain",
                                volume: 0)));
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(runId, "begin_case", 701, "sfx_playback")))
                    {
                    }
                    using (var afterMute = new PipeClient(host.PipeName))
                        Assert.Null(await afterMute.ExchangeOrClosedAsync(
                            Request(
                                runId,
                                "pre_sfx_bgm_mute",
                                6,
                                "pre_sfx_bgm_mute",
                                "set_gain",
                                volume: 0)));

                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(runId, "end_case", 702, "sfx_playback")))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            runId,
                            "begin_case",
                            703,
                            "dense_overlap_throttle")))
                    {
                    }
                    using (var beforeRestore = new PipeClient(host.PipeName))
                        Assert.Null(await beforeRestore.ExchangeOrClosedAsync(
                            Request(
                                runId,
                                "pre_mix_bgm_restore",
                                7,
                                "pre_mix_bgm_restore",
                                "set_gain",
                                volume: 1)));
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "dispatch",
                            8,
                            "dense_overlap_throttle",
                            "sfx",
                            linkageIds: new[] { "a", "a", "a", "a", "a", "a" })))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            runId,
                            "end_case",
                            704,
                            "dense_overlap_throttle")))
                    {
                    }
                    Assert.True(diagnostics.IsBetweenCases(
                        "dense_overlap_throttle",
                        "bgm_sfx_mix"));

                    using (var wrongRestore = new PipeClient(host.PipeName))
                        Assert.Null(await wrongRestore.ExchangeOrClosedAsync(
                            Request(
                                runId,
                                "pre_mix_bgm_restore",
                                9,
                                "pre_mix_bgm_restore",
                                "set_gain",
                                volume: 0)));
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "pre_mix_bgm_restore",
                            10,
                            "pre_mix_bgm_restore",
                            "set_gain",
                            volume: 1)))
                    {
                        Assert.Equal("pre_mix_bgm_restore", response.RootElement
                            .GetProperty("command").GetString());
                        Assert.Equal("pre_mix_bgm_restore", response.RootElement
                            .GetProperty("caseId").GetString());
                        Assert.Equal("ok", response.RootElement
                            .GetProperty("result").GetString());
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                    Assert.Equal(
                        "{\"action\":\"audioV2QualificationStimulus\",\"caseId\":\"pre_mix_bgm_restore\",\"operation\":\"set_gain\",\"runId\":\"" +
                            runId +
                            "\",\"task\":\"cmd\",\"volume\":1}\0",
                        transport.Messages[8].Payload);

                    using (var duplicateRestore = new PipeClient(host.PipeName))
                        Assert.Null(await duplicateRestore.ExchangeOrClosedAsync(
                            Request(
                                runId,
                                "pre_mix_bgm_restore",
                                11,
                                "pre_mix_bgm_restore",
                                "set_gain",
                                volume: 1)));
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(runId, "begin_case", 705, "bgm_sfx_mix")))
                    {
                    }
                    using (var afterRestore = new PipeClient(host.PipeName))
                        Assert.Null(await afterRestore.ExchangeOrClosedAsync(
                            Request(
                                runId,
                                "pre_mix_bgm_restore",
                                12,
                                "pre_mix_bgm_restore",
                                "set_gain",
                                volume: 1)));
                    Assert.Equal(9, transport.Messages.Count);
                }
            }
        }

        [Fact]
        public async Task BetweenCaseGainControls_RequireRecordedPrerequisites()
        {
            const string muteRunId = "57575757575757575757575757575758";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(muteRunId))
            {
                await ActivateCaseAsync(diagnostics, muteRunId, "format_opus");
                var transport = new FakeTransport { ReadyGeneration = 11 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    muteRunId,
                    diagnostics,
                    transport))
                {
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            muteRunId,
                            "end_case",
                            710,
                            "format_opus")))
                    {
                    }
                    using (var client = new PipeClient(host.PipeName))
                        Assert.Null(await client.ExchangeOrClosedAsync(Request(
                            muteRunId,
                            "pre_sfx_bgm_mute",
                            1,
                            "pre_sfx_bgm_mute",
                            "set_gain",
                            volume: 0)));
                    Assert.Single(transport.Messages);
                }
            }

            const string restoreRunId = "58585858585858585858585858585859";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(restoreRunId))
            {
                await ActivateCaseAsync(
                    diagnostics,
                    restoreRunId,
                    "dense_overlap_throttle");
                var transport = new FakeTransport { ReadyGeneration = 12 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    restoreRunId,
                    diagnostics,
                    transport))
                {
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            restoreRunId,
                            "dispatch",
                            1,
                            "dense_overlap_throttle",
                            "sfx",
                            linkageIds: new[] { "a", "a", "a", "a", "a", "a" })))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            restoreRunId,
                            "end_case",
                            711,
                            "dense_overlap_throttle")))
                    {
                    }
                    using (var client = new PipeClient(host.PipeName))
                        Assert.Null(await client.ExchangeOrClosedAsync(Request(
                            restoreRunId,
                            "pre_mix_bgm_restore",
                            2,
                            "pre_mix_bgm_restore",
                            "set_gain",
                            volume: 1)));
                    Assert.Equal(3, transport.Messages.Count);
                }
            }
        }

        [Fact]
        public async Task RecoveryArm_SendsOneOldTupleStimulusOnlyAfterRecoveryIsJournaled()
        {
            const string runId = "66666666666666666666666666666667";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                await ActivateCaseAsync(
                    diagnostics,
                    runId,
                    "no_stale_sfx_after_recovery");
                var order = new List<string>();
                var transport = new FakeTransport
                {
                    ReadyGeneration = 21,
                    OnSend = delegate(string payload)
                    {
                        if (payload.Contains(
                            "\"operation\":\"sfx\"",
                            StringComparison.Ordinal))
                        {
                            order.Add("stimulus");
                        }
                    }
                };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport))
                {
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            runId,
                            "arm_recovery_sfx",
                            1,
                            "no_stale_sfx_after_recovery",
                            "sfx",
                            linkageIds: new[] { "stale" })))
                    {
                        Assert.Equal("armed", response.RootElement
                            .GetProperty("result").GetString());
                        Assert.False(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }

                    AudioCoordinatorSnapshotV2 recovering = Snapshot(
                        AudioCoordinatorStatusV2.Recovering);
                    diagnostics.RecordCoordinatorSnapshot(recovering);
                    order.Add("diagnostics");
                    host.RecordCoordinatorSnapshot(recovering);
                    host.RecordCoordinatorSnapshot(recovering);

                    Assert.Equal(
                        new[] { "diagnostics", "stimulus" },
                        order.ToArray());
                    Assert.Equal(2, transport.Messages.Count);
                    Assert.Equal(
                        new[] { "arm", "sfx" },
                        transport.Messages.Select(entry =>
                            FlashOperation(entry.Payload)).ToArray());

                    using (JsonDocument journal = await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            runId,
                            "journal",
                            100)))
                    {
                        Assert.Contains(
                            journal.RootElement.GetProperty("journal")
                                .GetProperty("events")
                                .EnumerateArray(),
                            entry => entry.GetProperty("kind").GetString() ==
                                "coordinator_recovery");
                    }
                }
            }
        }

        [Fact]
        public async Task SingleClientAndDispose_AreBoundedAndStopFurtherSends()
        {
            const string runId = "77777777777777777777777777777778";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(runId))
            {
                var transport = new FakeTransport { ReadyGeneration = 31 };
                AudioQualificationStimulusHostV1 host = Stimulus(
                    runId,
                    diagnostics,
                    transport);
                using (var first = new PipeClient(host.PipeName))
                using (var second = new NamedPipeClientStream(
                    ".",
                    host.PipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous))
                {
                    Task pending = second.ConnectAsync(5000);
                    await Task.Delay(100);
                    Assert.False(pending.IsCompleted);
                    first.Dispose();
                    await pending;
                    Assert.True(second.IsConnected);
                }

                var elapsed = Stopwatch.StartNew();
                host.Dispose();
                host.Dispose();
                elapsed.Stop();
                Assert.True(elapsed.Elapsed < TimeSpan.FromSeconds(6));
                int count = transport.Messages.Count;
                transport.ReadyGeneration = 32;
                host.NotifyClientReadyForTests(32);
                host.RecordCoordinatorSnapshot(Snapshot(
                    AudioCoordinatorStatusV2.Recovering));
                Assert.Equal(count, transport.Messages.Count);
            }
        }

        [Fact]
        public void Program_ComposesRecoverySubscribersInRequiredOrder()
        {
            string program = File.ReadAllText(Path.Combine(
                FindRepositoryRoot(),
                "launcher",
                "src",
                "Program.cs"));
            int diagnostics = program.IndexOf(
                "AudioQualificationDiagnosticsHostV1\n                    .StartProduction",
                StringComparison.Ordinal);
            if (diagnostics < 0)
            {
                diagnostics = program.IndexOf(
                    "AudioQualificationDiagnosticsHostV1\r\n                    .StartProduction",
                    StringComparison.Ordinal);
            }
            int stimulus = program.IndexOf(
                "AudioQualificationStimulusHostV1",
                diagnostics + 1,
                StringComparison.Ordinal);
            int publisher = program.IndexOf(
                "new CF7Launcher.Audio.AudioSocketPublisherV2",
                stimulus + 1,
                StringComparison.Ordinal);
            Assert.True(diagnostics >= 0);
            Assert.True(stimulus > diagnostics);
            Assert.True(publisher > stimulus);
        }

        [Fact]
        public async Task NodeOperatorCanonicalStimuli_RoundTripHost()
        {
            const string playRunId = "81818181818181818181818181818182";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(playRunId))
            {
                await ActivateCaseAsync(
                    diagnostics,
                    playRunId,
                    "bgm_playback");
                var transport = new FakeTransport { ReadyGeneration = 41 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    playRunId,
                    diagnostics,
                    transport))
                {
                    string path = QualificationPath(
                        playRunId,
                        "baseline-a.mp3");
                    byte[] request = await BuildOperatorRequestAsync(
                        playRunId,
                        "bgm_playback",
                        "play",
                        new
                        {
                            fadeSeconds = 0,
                            loop = true,
                            path,
                            volume = 1
                        },
                        1);
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        request))
                    {
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                }
            }

            const string restoreRunId = "82828282828282828282828282828283";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(restoreRunId))
            {
                await ActivateCaseAsync(
                    diagnostics,
                    restoreRunId,
                    "gain_zero_and_default_max");
                var transport = new FakeTransport { ReadyGeneration = 42 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    restoreRunId,
                    diagnostics,
                    transport))
                {
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            restoreRunId,
                            "dispatch",
                            1,
                            "gain_zero_and_default_max",
                            "set_gain",
                            volume: 1)))
                    {
                    }
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            restoreRunId,
                            "dispatch",
                            2,
                            "gain_zero_and_default_max",
                            "set_gain",
                            volume: 0)))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            restoreRunId,
                            "end_case",
                            990,
                            "gain_zero_and_default_max")))
                    {
                    }

                    byte[] request = await BuildOperatorRequestAsync(
                        restoreRunId,
                        "post_gain_restore",
                        "set_gain",
                        new { volume = 1 },
                        3);
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        request))
                    {
                        Assert.Equal("post_gain_restore", response.RootElement
                            .GetProperty("command").GetString());
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                }
            }

            const string betweenRunId = "83838383838383838383838383838384";
            using (AudioQualificationDiagnosticsHostV1 diagnostics =
                Diagnostics(betweenRunId))
            {
                await ActivateCaseAsync(
                    diagnostics,
                    betweenRunId,
                    "format_opus");
                var transport = new FakeTransport { ReadyGeneration = 43 };
                using (AudioQualificationStimulusHostV1 host = Stimulus(
                    betweenRunId,
                    diagnostics,
                    transport))
                {
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            betweenRunId,
                            "dispatch",
                            1,
                            "format_opus",
                            "play",
                            path: QualificationPath(
                                betweenRunId,
                                "format-opus.opus"),
                            fadeSeconds: 0,
                            loop: true,
                            volume: 1)))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            betweenRunId,
                            "end_case",
                            991,
                            "format_opus")))
                    {
                    }

                    byte[] muteRequest = await BuildOperatorRequestAsync(
                        betweenRunId,
                        "pre_sfx_bgm_mute",
                        "set_gain",
                        new { volume = 0 },
                        2);
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        muteRequest))
                    {
                        Assert.Equal("pre_sfx_bgm_mute", response.RootElement
                            .GetProperty("command").GetString());
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }

                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            betweenRunId,
                            "begin_case",
                            992,
                            "sfx_playback")))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            betweenRunId,
                            "end_case",
                            993,
                            "sfx_playback")))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            betweenRunId,
                            "begin_case",
                            994,
                            "dense_overlap_throttle")))
                    {
                    }
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        Request(
                            betweenRunId,
                            "dispatch",
                            3,
                            "dense_overlap_throttle",
                            "sfx",
                            linkageIds: new[] { "a", "a", "a", "a", "a", "a" })))
                    {
                    }
                    using (await ExchangeObserverOnceAsync(
                        diagnostics.PipeName,
                        ObserverRequest(
                            betweenRunId,
                            "end_case",
                            995,
                            "dense_overlap_throttle")))
                    {
                    }

                    byte[] restoreRequest = await BuildOperatorRequestAsync(
                        betweenRunId,
                        "pre_mix_bgm_restore",
                        "set_gain",
                        new { volume = 1 },
                        4);
                    using (JsonDocument response = await ExchangeOnceAsync(
                        host.PipeName,
                        restoreRequest))
                    {
                        Assert.Equal("pre_mix_bgm_restore", response.RootElement
                            .GetProperty("command").GetString());
                        Assert.True(response.RootElement
                            .GetProperty("sent").GetBoolean());
                    }
                }
            }
        }

        private static AudioQualificationDiagnosticsHostV1 Diagnostics(
            string runId)
        {
            return AudioQualificationDiagnosticsHostV1.StartForTests(
                runId,
                Candidate(),
                delegate { return Snapshot(AudioCoordinatorStatusV2.Ready); });
        }

        private static AudioQualificationStimulusHostV1 Stimulus(
            string runId,
            AudioQualificationDiagnosticsHostV1 diagnostics,
            FakeTransport transport)
        {
            return AudioQualificationStimulusHostV1.StartForTests(
                runId,
                Candidate(),
                diagnostics,
                delegate { return transport.ReadyGeneration; },
                transport.Send);
        }

        private static AudioQualificationCandidateIdentityV1 Candidate()
        {
            return new AudioQualificationCandidateIdentityV1(
                new string('A', 64),
                Environment.ProcessPath,
                new string('B', 64),
                new string('C', 64),
                Environment.ProcessId,
                DateTimeOffset.UtcNow);
        }

        private static AudioCoordinatorSnapshotV2 Snapshot(
            AudioCoordinatorStatusV2 status)
        {
            return new AudioCoordinatorSnapshotV2(
                status,
                "01234567-89ab-4cde-8f01-23456789abcd",
                7,
                9,
                Path.GetPathRoot(Environment.ProcessPath),
                new string('D', 64),
                0,
                0,
                0,
                AudioNativeV2.ResultOk,
                "audio.test",
                0,
                0,
                0,
                0,
                false,
                "none",
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                new Dictionary<string, int>());
        }

        private static async Task ActivateCaseAsync(
            AudioQualificationDiagnosticsHostV1 diagnostics,
            string runId,
            string target)
        {
            int request = 500;
            foreach (string caseId in OrderedCases)
            {
                using (await ExchangeObserverOnceAsync(
                    diagnostics.PipeName,
                    ObserverRequest(
                        runId,
                        "begin_case",
                        request++,
                        caseId)))
                {
                }
                if (string.Equals(caseId, target, StringComparison.Ordinal))
                    return;
                using (await ExchangeObserverOnceAsync(
                    diagnostics.PipeName,
                    ObserverRequest(
                        runId,
                        "end_case",
                        request++,
                        caseId)))
                {
                }
            }
            throw new InvalidOperationException("Unknown qualification case.");
        }

        private static byte[] ObserverRequest(
            string runId,
            string command,
            int requestId,
            string caseId = null)
        {
            return AudioQualificationDiagnosticsHostV1.CanonicalRequestForTests(
                command,
                Id(requestId),
                runId,
                caseId,
                string.Equals(
                        command,
                        "begin_case",
                        StringComparison.Ordinal) &&
                    string.Equals(
                        caseId,
                        "physical_route_bluetooth_or_hdmi",
                        StringComparison.Ordinal)
                    ? "bluetooth"
                    : null);
        }

        private static byte[] Request(
            string runId,
            string command,
            int requestId,
            string caseId,
            string operation,
            string path = null,
            double? fadeSeconds = null,
            bool? loop = null,
            double? seekSeconds = null,
            double? volume = null,
            IReadOnlyList<string> linkageIds = null)
        {
            return AudioQualificationStimulusHostV1.CanonicalRequestForTests(
                command,
                Id(requestId),
                runId,
                caseId,
                operation,
                path,
                fadeSeconds,
                loop,
                seekSeconds,
                volume,
                linkageIds);
        }

        private static string QualificationPath(string runId, string fileName)
        {
            return "tmp/audio-v2-qualification/" + runId +
                "/fixtures/" + fileName;
        }

        private static string Id(int value)
        {
            return value.ToString("x32");
        }

        private static string FlashOperation(string payload)
        {
            using (JsonDocument document = JsonDocument.Parse(
                payload.TrimEnd('\0')))
            {
                return document.RootElement.GetProperty("operation").GetString();
            }
        }

        private static async Task<JsonDocument> ExchangeOnceAsync(
            string pipeName,
            byte[] request)
        {
            using (var client = new PipeClient(pipeName))
                return await client.ExchangeAsync(request);
        }

        private static async Task<JsonDocument> ExchangeObserverOnceAsync(
            string pipeName,
            byte[] request)
        {
            using (var client = new PipeClient(pipeName))
                return await client.ExchangeAsync(request);
        }

        private static string FindRepositoryRoot()
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                if (File.Exists(Path.Combine(
                        current.FullName,
                        "automation",
                        "start.ps1")) &&
                    File.Exists(Path.Combine(
                        current.FullName,
                        "launcher",
                        "src",
                        "Program.cs")))
                {
                    return current.FullName;
                }
                current = current.Parent;
            }
            throw new DirectoryNotFoundException(
                "Repository root was not found.");
        }

        private static async Task<byte[]> BuildOperatorRequestAsync(
            string runId,
            string caseId,
            string operation,
            object fields,
            int requestId)
        {
            string operatorPath = Path.Combine(
                FindRepositoryRoot(),
                "tools",
                "audio-v2",
                "qualification-operator.js");
            var startInfo = new ProcessStartInfo(
                AudioQualificationNodeExecutable.ResolveFromEnvironment())
            {
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false
            };
            startInfo.ArgumentList.Add("-e");
            startInfo.ArgumentList.Add(
                "const o=require(process.argv[1]);" +
                "const f=JSON.parse(process.argv[5]);" +
                "process.stdout.write(o.canonicalBytes(" +
                "o.buildStimulusRequest(process.argv[2],process.argv[3]," +
                "process.argv[4],f,process.argv[6])));");
            startInfo.ArgumentList.Add(operatorPath);
            startInfo.ArgumentList.Add(runId);
            startInfo.ArgumentList.Add(caseId);
            startInfo.ArgumentList.Add(operation);
            startInfo.ArgumentList.Add(JsonSerializer.Serialize(fields));
            startInfo.ArgumentList.Add(Id(requestId));
            using (Process process = Process.Start(startInfo))
            {
                Task<string> stdout = process.StandardOutput.ReadToEndAsync();
                Task<string> stderr = process.StandardError.ReadToEndAsync();
                using (var timeout = new CancellationTokenSource(10000))
                    await process.WaitForExitAsync(timeout.Token);
                string error = await stderr;
                Assert.True(
                    process.ExitCode == 0,
                    "qualification operator request builder failed: " + error);
                return Encoding.UTF8.GetBytes(await stdout);
            }
        }

        private sealed class FakeTransport
        {
            private readonly object _sync = new object();
            private readonly List<SentMessage> _messages =
                new List<SentMessage>();

            internal int ReadyGeneration;
            internal Action<string> OnSend;
            internal bool FailNextArmSend;
            internal IReadOnlyList<SentMessage> Messages
            {
                get
                {
                    lock (_sync) return _messages.ToArray();
                }
            }

            internal bool Send(string payload, int generation)
            {
                lock (_sync)
                {
                    if (generation != ReadyGeneration) return false;
                    if (FailNextArmSend && string.Equals(
                            FlashOperation(payload),
                            "arm",
                            StringComparison.Ordinal))
                    {
                        FailNextArmSend = false;
                        return false;
                    }
                    _messages.Add(new SentMessage(payload, generation));
                }
                OnSend?.Invoke(payload);
                return true;
            }
        }

        private sealed class SentMessage
        {
            internal SentMessage(string payload, int generation)
            {
                Payload = payload;
                Generation = generation;
            }

            internal string Payload { get; private set; }
            internal int Generation { get; private set; }
        }

        private sealed class PipeClient : IDisposable
        {
            private readonly NamedPipeClientStream _stream;

            internal PipeClient(string pipeName)
            {
                _stream = new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
                _stream.Connect(5000);
            }

            internal async Task<JsonDocument> ExchangeAsync(byte[] request)
            {
                JsonDocument value = await ExchangeOrClosedAsync(request);
                Assert.NotNull(value);
                return value;
            }

            internal async Task<JsonDocument> ExchangeOrClosedAsync(
                byte[] request)
            {
                try
                {
                    await _stream.WriteAsync(request, 0, request.Length);
                    await _stream.WriteAsync(new[] { (byte)'\n' }, 0, 1);
                    await _stream.FlushAsync();
                    using (var timeout = new CancellationTokenSource(7000))
                    using (var buffer = new MemoryStream())
                    {
                        byte[] one = new byte[1];
                        while (true)
                        {
                            int read = await _stream.ReadAsync(
                                one,
                                0,
                                1,
                                timeout.Token);
                            if (read == 0) return null;
                            if (one[0] == (byte)'\n')
                                return JsonDocument.Parse(buffer.ToArray());
                            buffer.WriteByte(one[0]);
                        }
                    }
                }
                catch (IOException)
                {
                    return null;
                }
            }

            public void Dispose()
            {
                _stream.Dispose();
            }
        }
    }
}
