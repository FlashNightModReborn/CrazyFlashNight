using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Audio;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class AudioQualificationDiagnosticsV1Tests
    {
        private const string RunId =
            "0123456789abcdef0123456789abcdef";
        private const string SessionId =
            "01234567-89ab-4cde-8f01-23456789abcd";

        [Fact]
        public void Invocation_IsCandidateOnlyStrictAndAbsentByDefault()
        {
            Assert.Null(AudioQualificationInvocationV1.ResolveRunId(
                Array.Empty<string>(),
                false));
            Assert.Equal(
                RunId,
                AudioQualificationInvocationV1.ResolveRunId(
                    new[]
                    {
                        AudioQualificationInvocationV1.Flag,
                        RunId
                    },
                    true));
            Assert.Throws<InvalidOperationException>(() =>
                AudioQualificationInvocationV1.ResolveRunId(
                    new[]
                    {
                        AudioQualificationInvocationV1.Flag,
                        RunId
                    },
                    false));
            Assert.Throws<ArgumentException>(() =>
                AudioQualificationInvocationV1.ResolveRunId(
                    new[]
                    {
                        "--Audio-V2-Qualification-Run-Id",
                        RunId
                    },
                    true));
            Assert.Throws<ArgumentException>(() =>
                AudioQualificationInvocationV1.ResolveRunId(
                    new[]
                    {
                        AudioQualificationInvocationV1.Flag,
                        RunId.ToUpperInvariant()
                    },
                    true));
            Assert.Throws<InvalidOperationException>(() =>
                AudioQualificationInvocationV1.ResolveRunId(
                    new[]
                    {
                        AudioQualificationInvocationV1.Flag,
                        RunId,
                        "--agent-unattended-runner"
                    },
                    true));

            string root = FindRepositoryRoot();
            string program = File.ReadAllText(Path.Combine(
                root,
                "launcher",
                "src",
                "Program.cs"));
            string start = File.ReadAllText(Path.Combine(
                root,
                "automation",
                "start.ps1"));
            Assert.Contains(
                "if (audioQualificationRunId != null)",
                program,
                StringComparison.Ordinal);
            Assert.Contains(
                ".StartProduction(audioQualificationRunId)",
                program,
                StringComparison.Ordinal);
            Assert.Contains(
                "$PSBoundParameters.ContainsKey('AudioV2QualificationRunId')",
                start,
                StringComparison.Ordinal);
            Assert.Contains(
                "available only with an explicit -CandidateRoot",
                start,
                StringComparison.Ordinal);
            Assert.Contains(
                "$unattendedArgumentsSpecified",
                start,
                StringComparison.Ordinal);
        }

        [Fact]
        public async Task PipeRoundTrip_BindsCandidateSnapshotAndHashJournal()
        {
            int snapshotCalls = 0;
            ulong workingState100ns = 1000000UL;
            using (AudioQualificationDiagnosticsHostV1 host =
                AudioQualificationDiagnosticsHostV1.StartForTests(
                    RunId,
                    Candidate(),
                    delegate
                    {
                        Interlocked.Increment(ref snapshotCalls);
                        return Snapshot();
                    },
                    workingStateClock: delegate
                    {
                        workingState100ns += 25UL;
                        return workingState100ns;
                    }))
            using (var client = new PipeClient(host.PipeName))
            {
                Assert.True(host.UsesCurrentUserOnly);
                Assert.Equal(
                    AudioQualificationDiagnosticsHostV1.BuildPipeName(
                        Environment.ProcessId,
                        RunId),
                    host.PipeName);

                JsonDocument begin = await client.ExchangeAsync(
                    Request("begin_case", 1, "bgm_playback"));
                Assert.Equal("ok", begin.RootElement
                    .GetProperty("result").GetString());
                Assert.Equal(Environment.ProcessId, begin.RootElement
                    .GetProperty("candidate").GetProperty("pid").GetInt32());
                Assert.Equal(Path.GetFullPath(Environment.ProcessPath),
                    begin.RootElement.GetProperty("candidate")
                        .GetProperty("executablePath").GetString());
                begin.Dispose();

                JsonDocument observed = await client.ExchangeAsync(
                    Request("snapshot", 2, "bgm_playback"));
                Assert.Equal(1, snapshotCalls);
                JsonElement snapshot = observed.RootElement
                    .GetProperty("snapshot");
                Assert.Equal("wasapi", snapshot.GetProperty("runtime")
                    .GetProperty("backend").GetString());
                Assert.Equal("f32", snapshot.GetProperty("runtime")
                    .GetProperty("sampleFormat").GetString());
                Assert.Equal(48000UL, snapshot.GetProperty("source")
                    .GetProperty("cursorFrames").GetUInt64());
                Assert.Equal(200UL, snapshot.GetProperty("bgmMeter")
                    .GetProperty("frameCount").GetUInt64());
                Assert.Equal(400UL, snapshot.GetProperty("sfxMeter")
                    .GetProperty("frameCount").GetUInt64());
                Assert.Equal(7UL, snapshot.GetProperty("counters")
                    .GetProperty("playedCount").GetUInt64());
                observed.Dispose();

                JsonDocument journalResponse = await client.ExchangeAsync(
                    Request("journal", 3));
                JsonElement journal = journalResponse.RootElement
                    .GetProperty("journal");
                JsonElement events = journal.GetProperty("events");
                Assert.Equal(2, events.GetArrayLength());
                Assert.Equal(1L, events[0].GetProperty("sequence").GetInt64());
                Assert.Equal(2L, events[1].GetProperty("sequence").GetInt64());
                Assert.Equal(events[0].GetProperty("sha256").GetString(),
                    events[1].GetProperty("previousSha256").GetString());
                Assert.Equal(25L, events[0]
                    .GetProperty("workingStateElapsed100ns").GetInt64());
                Assert.Equal(50L, events[1]
                    .GetProperty("workingStateElapsed100ns").GetInt64());
                Assert.Equal(Hash(Encoding.UTF8.GetBytes(events.GetRawText())),
                    journal.GetProperty("sha256").GetString());
                for (int index = 0; index < events.GetArrayLength(); index++)
                {
                    Assert.Equal(
                        HashEventWithoutSha(events[index]),
                        events[index].GetProperty("sha256").GetString());
                    Assert.Equal("bgm_playback",
                        events[index].GetProperty("caseId").GetString());
                }
                journalResponse.Dispose();
            }
        }

        [Fact]
        public void WorkingStateClock_UsesExactVoidWindowsApi()
        {
            MethodInfo method = typeof(AudioQualificationWorkingStateClockV2)
                .GetMethod(
                    "QueryUnbiasedInterruptTimePrecise",
                    BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);
            Assert.Equal(typeof(void), method.ReturnType);
            ParameterInfo parameter = Assert.Single(method.GetParameters());
            Assert.True(parameter.IsOut);
            Assert.Equal(typeof(ulong).MakeByRefType(), parameter.ParameterType);
            DllImportAttribute import = method.GetCustomAttribute<
                DllImportAttribute>();
            Assert.NotNull(import);
            Assert.Equal(
                "api-ms-win-core-realtime-l1-1-1.dll",
                import.Value);
            Assert.True(import.ExactSpelling);
            Assert.True(AudioQualificationWorkingStateClockV2.Read100ns() > 0);
        }

        [Fact]
        public async Task WorkingStateClock_FaultLatchesWithoutEscapingAudioCallback()
        {
            foreach (ulong invalidValue in new[]
            {
                999UL,
                AudioQualificationWorkingStateClockV2.MaximumJsonSafeInteger +
                    1001UL
            })
            {
                int calls = 0;
                using (AudioQualificationDiagnosticsHostV1 host =
                    AudioQualificationDiagnosticsHostV1.StartForTests(
                        RunId,
                        Candidate(),
                        Snapshot,
                        workingStateClock: delegate
                        {
                            return Interlocked.Increment(ref calls) == 1
                                ? 1000UL
                                : invalidValue;
                        }))
                using (var client = new PipeClient(host.PipeName))
                {
                    Assert.Null(await client.ExchangeOrClosedAsync(
                        Request("begin_case", calls + 100, "bgm_playback")));
                    Assert.False(host.IsActiveCase("bgm_playback"));
                    host.RecordCoordinatorSnapshot(Snapshot());
                    using (var rejected = new PipeClient(host.PipeName))
                        Assert.Null(await rejected.ExchangeOrClosedAsync(
                            Request("journal", calls + 200)));
                }
            }

            Assert.Throws<InvalidOperationException>(() =>
                AudioQualificationDiagnosticsHostV1.StartForTests(
                    RunId,
                    Candidate(),
                    Snapshot,
                    workingStateClock: delegate
                    {
                        throw new InvalidOperationException("clock unavailable");
                    }));
        }

        [Fact]
        public async Task WorkingStateClock_CallbackFaultDoesNotEscapeAndRejectsJournal()
        {
            const string runId = "acacacacacacacacacacacacacacacac";
            int calls = 0;
            using (AudioQualificationDiagnosticsHostV1 host =
                AudioQualificationDiagnosticsHostV1.StartForTests(
                    runId,
                    Candidate(),
                    Snapshot,
                    workingStateClock: delegate
                    {
                        int call = Interlocked.Increment(ref calls);
                        if (call == 3)
                            throw new InvalidOperationException(
                                "callback clock failure");
                        return 1000UL + (ulong)call;
                    }))
            {
                using (await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(runId, "begin_case", 401, "bgm_playback")))
                {
                }
                Exception callbackError = Record.Exception(() =>
                    host.RecordCoordinatorSnapshot(Snapshot()));
                Assert.Null(callbackError);
                Assert.False(host.IsActiveCase("bgm_playback"));
                using (var rejected = new PipeClient(host.PipeName))
                {
                    Assert.Null(await rejected.ExchangeOrClosedAsync(
                        RequestFor(runId, "journal", 402, null)));
                }
            }
        }

        [Fact]
        public async Task RecoverySfxArm_IsHashBoundAndRejectsInvalidValues()
        {
            const string runId = "edededededededededededededededed";
            using (AudioQualificationDiagnosticsHostV1 host = Host(runId))
            {
                int request = 1;
                foreach (string caseId in new[]
                {
                    "bgm_playback", "bgm_seek", "bgm_crossfade",
                    "format_vorbis", "format_aac_mp4", "format_opus",
                    "sfx_playback", "dense_overlap_throttle", "bgm_sfx_mix",
                    "gain_zero_and_default_max", "default_device_switch",
                    "physical_route_bluetooth_or_hdmi", "sleep_resume"
                })
                {
                    request = await CompleteCaseAsync(
                        host.PipeName, runId, caseId, request);
                }
                using (await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(
                        runId,
                        "begin_case",
                        request++,
                        "no_stale_sfx_after_recovery")))
                {
                }

                Assert.Throws<InvalidDataException>(() =>
                    host.RecordRecoverySfxArm(Id(700), "ok", false));
                Assert.Throws<InvalidDataException>(() =>
                    host.RecordRecoverySfxArm(Id(701), "armed", true));
                host.RecordRecoverySfxArm(Id(702), "armed", false);

                using (JsonDocument response = await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(runId, "journal", request++, null)))
                {
                    JsonElement arm = Assert.Single(response.RootElement
                        .GetProperty("journal")
                        .GetProperty("events")
                        .EnumerateArray()
                        .Where(value => value.GetProperty("kind").GetString() ==
                            "recovery_sfx_armed"));
                    Assert.Equal(Id(702), arm.GetProperty("payload")
                        .GetProperty("requestId").GetString());
                    Assert.Equal("armed", arm.GetProperty("payload")
                        .GetProperty("result").GetString());
                    Assert.False(arm.GetProperty("payload")
                        .GetProperty("sent").GetBoolean());
                    Assert.Equal(
                        HashEventWithoutSha(arm),
                        arm.GetProperty("sha256").GetString());
                }
            }

            using (AudioQualificationDiagnosticsHostV1 host = Host(
                "fefefefefefefefefefefefefefefefe"))
            {
                Assert.Throws<InvalidDataException>(() =>
                    host.RecordRecoverySfxArm(Id(703), "armed", false));
            }
        }

        [Fact]
        public async Task ObserverSnapshotBytes_RoundTripAndRejectCaseMismatch()
        {
            int snapshotCalls = 0;
            using (AudioQualificationDiagnosticsHostV1 host =
                AudioQualificationDiagnosticsHostV1.StartForTests(
                    RunId,
                    Candidate(),
                    delegate
                    {
                        Interlocked.Increment(ref snapshotCalls);
                        return Snapshot();
                    }))
            {
                using (JsonDocument begin = await ExchangeOnceAsync(
                    host.PipeName,
                    Request("begin_case", 20, "bgm_playback")))
                {
                    Assert.Equal("bgm_playback", begin.RootElement
                        .GetProperty("event")
                        .GetProperty("caseId")
                        .GetString());
                }

                byte[] observerRequest = await BuildObserverSnapshotRequestAsync(
                    "bgm_playback",
                    Id(21));
                Assert.Equal(
                    Encoding.UTF8.GetString(
                        Request("snapshot", 21, "bgm_playback")),
                    Encoding.UTF8.GetString(observerRequest));
                using (JsonDocument observed = await ExchangeOnceAsync(
                    host.PipeName,
                    observerRequest))
                {
                    Assert.Equal("bgm_playback", observed.RootElement
                        .GetProperty("event")
                        .GetProperty("caseId")
                        .GetString());
                }
                Assert.Equal(1, snapshotCalls);

                byte[] mismatched = await BuildObserverSnapshotRequestAsync(
                    "sfx_playback",
                    Id(22));
                using (var client = new PipeClient(host.PipeName))
                {
                    Assert.Null(await client.ExchangeOrClosedAsync(mismatched));
                }
                Assert.Equal(1, snapshotCalls);

                using (JsonDocument journal = await ExchangeOnceAsync(
                    host.PipeName,
                    Request("journal", 23)))
                {
                    Assert.Equal("ok", journal.RootElement
                        .GetProperty("result")
                        .GetString());
                }
            }
        }

        [Fact]
        public async Task RawJournal_IsNodeCanonicalForSmallDecimalsAndHashes()
        {
            using (AudioQualificationDiagnosticsHostV1 host = Host(RunId))
            {
                using (await ExchangeOnceAsync(
                    host.PipeName,
                    Request("begin_case", 30, "bgm_playback")))
                {
                }
                host.RecordBgmRequest(new AudioBgmRequestV2(
                    "bgm.request.small-decimals",
                    SessionId,
                    7,
                    "seek",
                    null,
                    null,
                    0.1,
                    0.00001,
                    0.000089));
                using (await ExchangeOnceAsync(
                    host.PipeName,
                    Request("snapshot", 31, "bgm_playback")))
                {
                }

                byte[] rawJournal;
                using (var client = new PipeClient(host.PipeName))
                {
                    rawJournal = await client.ExchangeRawAsync(
                        Request("journal", 32));
                }
                string raw = Encoding.UTF8.GetString(rawJournal);
                Assert.Contains("\"fadeSeconds\":0.00001", raw,
                    StringComparison.Ordinal);
                Assert.Contains("\"seekSeconds\":0.000089", raw,
                    StringComparison.Ordinal);
                Assert.Contains("\"volume\":0.1", raw,
                    StringComparison.Ordinal);
                Assert.Contains("\"peakLeft\":0.00001", raw,
                    StringComparison.Ordinal);
                Assert.Contains("\"peakRight\":0.000089", raw,
                    StringComparison.Ordinal);
                Assert.Contains("\"rmsLeft\":0.1", raw,
                    StringComparison.Ordinal);
                Assert.Contains("\"rmsRight\":0", raw,
                    StringComparison.Ordinal);
                await ValidateRawJournalWithNodeAsync(
                    rawJournal,
                    Id(32));
            }
        }

        [Fact]
        public async Task Pipe_RejectsNonCanonicalWrongRunAndOversizeFrames()
        {
            using (AudioQualificationDiagnosticsHostV1 host = Host(
                "11111111111111111111111111111111"))
            {
                using (var client = new PipeClient(host.PipeName))
                {
                    byte[] nonCanonical = Encoding.UTF8.GetBytes(
                        "{\"protocol\":\"" +
                        AudioQualificationDiagnosticsHostV1.Protocol +
                        "\",\"command\":\"journal\",\"requestId\":\"" +
                        Id(1) + "\",\"runId\":\"" +
                        "11111111111111111111111111111111\"}");
                    Assert.Null(await client.ExchangeOrClosedAsync(nonCanonical));
                }
                using (var recovered = new PipeClient(host.PipeName))
                using (JsonDocument response = await recovered.ExchangeAsync(
                    RequestFor(
                        "11111111111111111111111111111111",
                        "journal",
                        2,
                        null)))
                {
                    Assert.Equal("ok", response.RootElement
                        .GetProperty("result").GetString());
                }
                using (var malformedUtf8 = new PipeClient(host.PipeName))
                {
                    Assert.Null(await malformedUtf8.ExchangeOrClosedAsync(
                        new byte[] { 0xC3, 0x28 }));
                }
                using (var recovered = new PipeClient(host.PipeName))
                using (JsonDocument response = await recovered.ExchangeAsync(
                    RequestFor(
                        "11111111111111111111111111111111",
                        "journal",
                        3,
                        null)))
                {
                    Assert.Equal("ok", response.RootElement
                        .GetProperty("result").GetString());
                }
            }

            using (AudioQualificationDiagnosticsHostV1 host = Host(
                "22222222222222222222222222222222"))
            using (var client = new PipeClient(host.PipeName))
            {
                byte[] wrongRun =
                    AudioQualificationDiagnosticsHostV1
                        .CanonicalRequestForTests(
                            "journal",
                            Id(2),
                            "33333333333333333333333333333333",
                            null);
                Assert.Null(await client.ExchangeOrClosedAsync(wrongRun));
            }

            using (AudioQualificationDiagnosticsHostV1 host = Host(
                "44444444444444444444444444444444"))
            using (var client = new PipeClient(host.PipeName))
            {
                byte[] oversized = Enumerable.Repeat(
                    (byte)'a',
                    AudioQualificationDiagnosticsHostV1.MaxRequestBytes + 1)
                    .ToArray();
                Assert.Null(await client.ExchangeOrClosedAsync(oversized));
            }
        }

        [Fact]
        public async Task CaseMarkers_AreOrderedUniqueAndRouteAnnotationIsNarrow()
        {
            string runId = "55555555555555555555555555555555";
            string[] cases =
            {
                "bgm_playback", "bgm_seek", "bgm_crossfade",
                "format_vorbis", "format_aac_mp4", "format_opus",
                "sfx_playback", "dense_overlap_throttle", "bgm_sfx_mix",
                "gain_zero_and_default_max", "default_device_switch",
                "physical_route_bluetooth_or_hdmi", "sleep_resume",
                "no_stale_sfx_after_recovery"
            };
            using (AudioQualificationDiagnosticsHostV1 host = Host(runId))
            {
                int request = 1;
                foreach (string caseId in cases)
                {
                    byte[] beginRequest = string.Equals(
                        caseId,
                        "physical_route_bluetooth_or_hdmi",
                        StringComparison.Ordinal)
                        ? AudioQualificationDiagnosticsHostV1
                            .CanonicalRequestForTests(
                                "begin_case",
                                Id(request++),
                                runId,
                                caseId,
                                "hdmi")
                        : RequestFor(
                            runId,
                            "begin_case",
                            request++,
                            caseId);
                    using (JsonDocument begin = await ExchangeOnceAsync(
                        host.PipeName,
                        beginRequest))
                    {
                        JsonElement payload = begin.RootElement
                            .GetProperty("event").GetProperty("payload");
                        if (caseId == "physical_route_bluetooth_or_hdmi")
                        {
                            Assert.Equal("hdmi", payload
                                .GetProperty("routeKind").GetString());
                        }
                        else
                        {
                            Assert.Empty(payload.EnumerateObject());
                        }
                    }
                    using (await ExchangeOnceAsync(
                        host.PipeName,
                        RequestFor(
                            runId,
                            "end_case",
                            request++,
                            caseId)))
                    {
                    }
                }
                for (int replay = 0; replay < 9; replay++)
                {
                    using (JsonDocument journal = await ExchangeOnceAsync(
                        host.PipeName,
                        RequestFor(
                            runId,
                            "journal",
                            request++,
                            null)))
                    {
                        JsonElement events = journal.RootElement
                            .GetProperty("journal").GetProperty("events");
                        Assert.Equal(28, events.EnumerateArray().Count(
                            value => value.GetProperty("kind").GetString()
                                == "case_begin" ||
                                value.GetProperty("kind").GetString()
                                == "case_end"));
                    }
                }
            }

            string wrongRun = "66666666666666666666666666666666";
            using (AudioQualificationDiagnosticsHostV1 host = Host(wrongRun))
            using (var client = new PipeClient(host.PipeName))
            {
                Assert.Null(await client.ExchangeOrClosedAsync(
                    RequestFor(wrongRun, "begin_case", 1, "bgm_seek")));
            }
        }

        [Fact]
        public async Task CrossfadeSampler_IsPeriodicSingleFlightAndCaseFenced()
        {
            string runId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            int snapshotCalls = 0;
            using (AudioQualificationDiagnosticsHostV1 host =
                AudioQualificationDiagnosticsHostV1.StartForTests(
                    runId,
                    Candidate(),
                    delegate
                    {
                        Interlocked.Increment(ref snapshotCalls);
                        return Snapshot();
                    }))
            {
                int request = 1;
                request = await CompleteCaseAsync(
                    host.PipeName,
                    runId,
                    "bgm_playback",
                    request);
                request = await CompleteCaseAsync(
                    host.PipeName,
                    runId,
                    "bgm_seek",
                    request);

                using (await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(
                        runId,
                        "begin_case",
                        request++,
                        "bgm_crossfade")))
                {
                }
                await Task.Delay(700);
                using (await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(
                        runId,
                        "end_case",
                        request++,
                        "bgm_crossfade")))
                {
                }

                int callsAfterEnd = Volatile.Read(ref snapshotCalls);
                int firstEventCount;
                using (JsonDocument journal = await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(runId, "journal", request++, null)))
                {
                    JsonElement[] events = journal.RootElement
                        .GetProperty("journal")
                        .GetProperty("events")
                        .EnumerateArray()
                        .ToArray();
                    JsonElement[] samples = events.Where(value =>
                        value.GetProperty("kind").GetString() ==
                            "qualification_snapshot" &&
                        value.GetProperty("caseId").GetString() ==
                            "bgm_crossfade").ToArray();
                    Assert.True(
                        samples.Length >= 3,
                        "automatic crossfade samples=" + samples.Length);
                    for (int index = 1; index < samples.Length; index++)
                    {
                        DateTimeOffset prior = DateTimeOffset.Parse(
                            samples[index - 1]
                                .GetProperty("observedAtUtc").GetString(),
                            CultureInfo.InvariantCulture,
                            DateTimeStyles.RoundtripKind);
                        DateTimeOffset current = DateTimeOffset.Parse(
                            samples[index]
                                .GetProperty("observedAtUtc").GetString(),
                            CultureInfo.InvariantCulture,
                            DateTimeStyles.RoundtripKind);
                        Assert.True(
                            current - prior <= TimeSpan.FromMilliseconds(500),
                            "crossfade sample gap=" + (current - prior));
                    }
                    long endSequence = events.Single(value =>
                        value.GetProperty("kind").GetString() == "case_end" &&
                        value.GetProperty("caseId").GetString() ==
                            "bgm_crossfade")
                        .GetProperty("sequence").GetInt64();
                    Assert.All(samples, value => Assert.True(
                        value.GetProperty("sequence").GetInt64() <
                            endSequence));
                    firstEventCount = events.Length;
                }

                await Task.Delay(350);
                Assert.Equal(
                    callsAfterEnd,
                    Volatile.Read(ref snapshotCalls));
                using (JsonDocument journal = await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(runId, "journal", request++, null)))
                {
                    Assert.Equal(
                        firstEventCount,
                        journal.RootElement.GetProperty("journal")
                            .GetProperty("events").GetArrayLength());
                }
            }
        }

        [Fact]
        public async Task CrossfadeSampler_DisposeDropsInFlightSnapshotBoundedly()
        {
            string runId = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
            int snapshotCalls = 0;
            using (var entered = new ManualResetEventSlim(false))
            {
                AudioQualificationDiagnosticsHostV1 host =
                    AudioQualificationDiagnosticsHostV1.StartForTests(
                        runId,
                        Candidate(),
                        delegate
                        {
                            Interlocked.Increment(ref snapshotCalls);
                            entered.Set();
                            Thread.Sleep(250);
                            return Snapshot();
                        });
                int request = 1;
                request = await CompleteCaseAsync(
                    host.PipeName,
                    runId,
                    "bgm_playback",
                    request);
                request = await CompleteCaseAsync(
                    host.PipeName,
                    runId,
                    "bgm_seek",
                    request);
                using (await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(
                        runId,
                        "begin_case",
                        request++,
                        "bgm_crossfade")))
                {
                }
                Assert.True(entered.Wait(TimeSpan.FromSeconds(2)));
                var elapsed = Stopwatch.StartNew();
                host.Dispose();
                elapsed.Stop();
                Assert.True(
                    elapsed.Elapsed < TimeSpan.FromSeconds(6),
                    "active sampler dispose elapsed=" + elapsed.Elapsed);
                int callsAfterDispose = Volatile.Read(ref snapshotCalls);
                await Task.Delay(350);
                Assert.Equal(
                    callsAfterDispose,
                    Volatile.Read(ref snapshotCalls));
            }
        }

        [Fact]
        public async Task CrossfadeSampler_StopsAtProductionBoundedSampleCap()
        {
            Assert.Equal(
                150,
                AudioQualificationDiagnosticsHostV1
                    .MaxCrossfadeAutomaticSamples);
            Assert.Equal(
                15000,
                AudioQualificationDiagnosticsHostV1
                    .CrossfadeSamplerWindowMilliseconds);
            string runId = "cccccccccccccccccccccccccccccccc";
            int snapshotCalls = 0;
            using (AudioQualificationDiagnosticsHostV1 host =
                AudioQualificationDiagnosticsHostV1.StartForTests(
                    runId,
                    Candidate(),
                    delegate
                    {
                        Interlocked.Increment(ref snapshotCalls);
                        return Snapshot();
                    },
                    maxCrossfadeAutomaticSamples: 3,
                    crossfadeSampleIntervalMilliseconds: 10,
                    crossfadeSamplerWindowMilliseconds: 1000))
            {
                int request = 1;
                request = await CompleteCaseAsync(
                    host.PipeName,
                    runId,
                    "bgm_playback",
                    request);
                request = await CompleteCaseAsync(
                    host.PipeName,
                    runId,
                    "bgm_seek",
                    request);
                using (await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(
                        runId,
                        "begin_case",
                        request++,
                        "bgm_crossfade")))
                {
                }
                await Task.Delay(150);
                Assert.Equal(3, Volatile.Read(ref snapshotCalls));
                using (JsonDocument journal = await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(runId, "journal", request++, null)))
                {
                    Assert.Equal(
                        3,
                        journal.RootElement.GetProperty("journal")
                            .GetProperty("events")
                            .EnumerateArray()
                            .Count(value => value.GetProperty("kind")
                                .GetString() == "qualification_snapshot"));
                }
                await Task.Delay(100);
                Assert.Equal(3, Volatile.Read(ref snapshotCalls));
                using (await ExchangeOnceAsync(
                    host.PipeName,
                    RequestFor(
                        runId,
                        "end_case",
                        request++,
                        "bgm_crossfade")))
                {
                }
            }
        }

        [Fact]
        public async Task ConcurrentSecondClient_WaitsUntilSoleClientDisconnects()
        {
            string runId = "99999999999999999999999999999999";
            using (AudioQualificationDiagnosticsHostV1 host = Host(runId))
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
        }

        [Fact]
        public async Task AudioTask_RecordsTypedIngressAndFacadeResults()
        {
            string runId = "77777777777777777777777777777777";
            using (AudioQualificationDiagnosticsHostV1 host = Host(runId))
            using (var client = new PipeClient(host.PipeName))
            {
                using (await client.ExchangeAsync(
                    RequestFor(runId, "begin_case", 1, "bgm_playback")))
                {
                }
                var facade = new EchoFacade();
                var task = new AudioTask(facade, host);
                var envelope = new JObject
                {
                    ["task"] = "audio",
                    ["wireRevision"] = 2,
                    ["requestId"] = "bgm.request.qualification",
                    ["audioSessionId"] = SessionId,
                    ["audioReadyGeneration"] = "7",
                    ["operation"] = "play",
                    ["path"] = "sounds/music/test.mp3",
                    ["loop"] = true,
                    ["volume"] = 0.75,
                    ["fadeSeconds"] = 0.1
                };
                var responses = new List<string>();
                task.HandleAsync(envelope, responses.Add);
                Assert.True(task.HandleSfxFastLane(
                    "S2|" + SessionId + "|7|9|gun.wav|hit.wav"));
                Assert.Single(responses);

                using (JsonDocument journalResponse =
                    await client.ExchangeAsync(
                        RequestFor(runId, "journal", 2, null)))
                {
                    string[] kinds = journalResponse.RootElement
                        .GetProperty("journal").GetProperty("events")
                        .EnumerateArray()
                        .Select(value =>
                            value.GetProperty("kind").GetString())
                        .ToArray();
                    Assert.Contains("as2_bgm_request", kinds);
                    Assert.Contains("as2_bgm_result", kinds);
                    Assert.Contains("as2_sfx_batch", kinds);
                    JsonElement result = journalResponse.RootElement
                        .GetProperty("journal").GetProperty("events")
                        .EnumerateArray()
                        .Single(value => value.GetProperty("kind")
                            .GetString() == "as2_bgm_result");
                    Assert.Equal("bgm.request.qualification",
                        result.GetProperty("payload")
                            .GetProperty("requestId").GetString());
                    Assert.Equal("audio_coordinator",
                        result.GetProperty("source").GetString());
                }
            }
        }

        [Fact]
        public void ShutdownWithoutClient_IsBoundedAndIdempotent()
        {
            AudioQualificationDiagnosticsHostV1 host = Host(
                "88888888888888888888888888888888");
            var elapsed = Stopwatch.StartNew();
            host.Dispose();
            host.Dispose();
            elapsed.Stop();
            Assert.True(
                elapsed.Elapsed < TimeSpan.FromSeconds(6),
                "shutdown elapsed=" + elapsed.Elapsed);

            AudioQualificationDiagnosticsHostV1 readingHost = Host(
                "dddddddddddddddddddddddddddddddd");
            using (var idleClient = new PipeClient(readingHost.PipeName))
            {
                elapsed.Restart();
                readingHost.Dispose();
                elapsed.Stop();
                Assert.True(
                    elapsed.Elapsed < TimeSpan.FromSeconds(6),
                    "active read shutdown elapsed=" + elapsed.Elapsed);
            }
        }

        private static AudioQualificationDiagnosticsHostV1 Host(
            string runId)
        {
            return AudioQualificationDiagnosticsHostV1.StartForTests(
                runId,
                Candidate(),
                Snapshot);
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

        private static AudioCoordinatorSnapshotV2 Snapshot()
        {
            var bgm = new AudioNativeMeterObservationV2(
                0.00001f,
                0.000089f,
                0.1f,
                0.0000004f,
                1,
                200,
                2);
            var sfx = new AudioNativeMeterObservationV2(
                0.7f, 0.6f, 0.35f, 0.3f, 3, 400, 4);
            var counters = new AudioNativeSfxCountersV2(
                SessionId, 7, 1, 2, 3, 4, 5, 6, 7);
            var observation = new AudioNativeObservationV2(
                true,
                bgm,
                sfx,
                1f,
                2f,
                48000,
                96000,
                true,
                "builtin",
                "riff_wave",
                "pcm_or_ieee_float",
                AudioNativeV2.ResultOk,
                counters);
            var qualification = new AudioCoordinatorQualificationStateV2
            {
                Backend = AudioNativeV2.BackendWasapi,
                DeviceIdDigest = new string('D', 64),
                DeviceName = "Qualification speakers",
                SampleRate = 48000,
                Channels = 2,
                SampleFormat = AudioNativeV2.SampleFormatF32,
                SourceRequestId = "bgm.request.1",
                Observation = observation
            };
            return new AudioCoordinatorSnapshotV2(
                AudioCoordinatorStatusV2.Ready,
                SessionId,
                7,
                9,
                Path.GetPathRoot(Environment.ProcessPath),
                new string('E', 64),
                3,
                0,
                0,
                AudioNativeV2.ResultOk,
                "audio.ready",
                0.5f,
                0.4f,
                1f,
                2f,
                true,
                "builtin",
                1,
                2,
                3,
                4,
                5,
                6,
                7,
                new Dictionary<string, int>(),
                qualification);
        }

        private static byte[] Request(
            string command,
            int requestId,
            string caseId = null)
        {
            return RequestFor(RunId, command, requestId, caseId);
        }

        private static byte[] RequestFor(
            string runId,
            string command,
            int requestId,
            string caseId)
        {
            return AudioQualificationDiagnosticsHostV1
                .CanonicalRequestForTests(
                    command,
                    Id(requestId),
                    runId,
                    caseId);
        }

        private static async Task<int> CompleteCaseAsync(
            string pipeName,
            string runId,
            string caseId,
            int requestId)
        {
            byte[] beginRequest = string.Equals(
                caseId,
                "physical_route_bluetooth_or_hdmi",
                StringComparison.Ordinal)
                ? AudioQualificationDiagnosticsHostV1.CanonicalRequestForTests(
                    "begin_case",
                    Id(requestId++),
                    runId,
                    caseId,
                    "bluetooth")
                : RequestFor(
                    runId,
                    "begin_case",
                    requestId++,
                    caseId);
            using (await ExchangeOnceAsync(pipeName, beginRequest))
            {
            }
            using (await ExchangeOnceAsync(
                pipeName,
                RequestFor(
                    runId,
                    "end_case",
                    requestId++,
                    caseId)))
            {
            }
            return requestId;
        }

        private static string Id(int value)
        {
            return value.ToString("x32");
        }

        private static async Task<JsonDocument> ExchangeOnceAsync(
            string pipeName,
            byte[] request)
        {
            using (var client = new PipeClient(pipeName))
                return await client.ExchangeAsync(request);
        }

        private static string Hash(byte[] bytes)
        {
            using (SHA256 sha256 = SHA256.Create())
                return Convert.ToHexString(sha256.ComputeHash(bytes));
        }

        private static string HashEventWithoutSha(JsonElement value)
        {
            using (var buffer = new MemoryStream())
            {
                using (var writer = new Utf8JsonWriter(buffer))
                {
                    writer.WriteStartObject();
                    foreach (JsonProperty property in value.EnumerateObject())
                    {
                        if (property.NameEquals("sha256")) continue;
                        property.WriteTo(writer);
                    }
                    writer.WriteEndObject();
                    writer.Flush();
                }
                return Hash(buffer.ToArray());
            }
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

        private static async Task<byte[]> BuildObserverSnapshotRequestAsync(
            string caseId,
            string requestId)
        {
            string observerPath = Path.Combine(
                FindRepositoryRoot(),
                "tools",
                "audio-v2",
                "qualification-observer.js");
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
                "process.stdout.write(o.canonicalBytes(" +
                "o.buildRequest('snapshot',process.argv[2]," +
                "process.argv[3],process.argv[4])));");
            startInfo.ArgumentList.Add(observerPath);
            startInfo.ArgumentList.Add(RunId);
            startInfo.ArgumentList.Add(caseId);
            startInfo.ArgumentList.Add(requestId);
            using (Process process = Process.Start(startInfo))
            {
                Task<string> stdout = process.StandardOutput.ReadToEndAsync();
                Task<string> stderr = process.StandardError.ReadToEndAsync();
                using (var timeout = new CancellationTokenSource(10000))
                    await process.WaitForExitAsync(timeout.Token);
                string error = await stderr;
                Assert.True(
                    process.ExitCode == 0,
                    "qualification observer request builder failed: " + error);
                return Encoding.UTF8.GetBytes(await stdout);
            }
        }

        private static async Task ValidateRawJournalWithNodeAsync(
            byte[] response,
            string requestId)
        {
            string observerPath = Path.Combine(
                FindRepositoryRoot(),
                "tools",
                "audio-v2",
                "qualification-observer.js");
            var startInfo = new ProcessStartInfo(
                AudioQualificationNodeExecutable.ResolveFromEnvironment())
            {
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                UseShellExecute = false
            };
            startInfo.ArgumentList.Add("-e");
            startInfo.ArgumentList.Add(
                "const fs=require('fs');" +
                "const o=require(process.argv[1]);" +
                "const raw=fs.readFileSync(0);" +
                "const value=JSON.parse(raw);" +
                "const request=o.buildRequest('journal',process.argv[2]," +
                "null,process.argv[3]);" +
                "o.validateResponse(value,request,value.candidate);" +
                "if(!raw.equals(o.canonicalBytes(value)))" +
                "throw new Error('response is not Node-canonical');" +
                "process.stdout.write('ok');");
            startInfo.ArgumentList.Add(observerPath);
            startInfo.ArgumentList.Add(RunId);
            startInfo.ArgumentList.Add(requestId);
            using (Process process = Process.Start(startInfo))
            {
                Task<string> stdout = process.StandardOutput.ReadToEndAsync();
                Task<string> stderr = process.StandardError.ReadToEndAsync();
                await process.StandardInput.BaseStream.WriteAsync(
                    response,
                    0,
                    response.Length);
                process.StandardInput.Close();
                using (var timeout = new CancellationTokenSource(10000))
                    await process.WaitForExitAsync(timeout.Token);
                string error = await stderr;
                Assert.True(
                    process.ExitCode == 0,
                    "Node qualification validator failed: " + error);
                Assert.Equal("ok", await stdout);
            }
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
                return JsonDocument.Parse(await ExchangeRawAsync(request));
            }

            internal async Task<byte[]> ExchangeRawAsync(byte[] request)
            {
                byte[] response = await ExchangeOrClosedBytesAsync(request);
                Assert.NotNull(response);
                return response;
            }

            internal async Task<JsonDocument> ExchangeOrClosedAsync(
                byte[] request)
            {
                byte[] response = await ExchangeOrClosedBytesAsync(request);
                return response == null ? null : JsonDocument.Parse(response);
            }

            private async Task<byte[]> ExchangeOrClosedBytesAsync(
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
                                return buffer.ToArray();
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

        private sealed class EchoFacade : IAudioCommandFacadeV2
        {
            public void DispatchBgm(
                AudioBgmRequestV2 request,
                Action<AudioBgmResultV2> respond)
            {
                respond(new AudioBgmResultV2(
                    request.RequestId,
                    request.AudioSessionId,
                    request.AudioReadyGeneration,
                    9,
                    request.Operation,
                    "started",
                    "ok",
                    "native_start",
                    0,
                    0,
                    "builtin",
                    "audio.bgm.started"));
            }

            public void RejectBgm(string protocolError) { }
            public void DispatchSfx(AudioSfxBatchV2 batch) { }
            public void RejectSfx(string protocolError) { }
            public void ArmBootstrapBgmGate() { }
            public void CancelBootstrapBgmGate() { }
            public void ReleaseBootstrapBgmGate() { }
        }
    }
}
