using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Xml.Linq;
using CF7Launcher.Audio;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class MusicCatalogV2Tests
    {
        private const string CapabilityA =
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        private const string CapabilityB =
            "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";

        [Fact]
        public void DiscoveryHintsAndProductionBounds_AreFrozen()
        {
            Assert.Equal(
                new[]
                {
                    ".wav", ".mp3", ".flac", ".ogg", ".m4a",
                    ".mp4", ".aac", ".adts", ".opus"
                },
                MusicCatalog.GetAudioHintExtensionsForTests());
            Assert.Equal(
                TimeSpan.FromMilliseconds(1000),
                MusicCatalogProbePolicyV2.Production.StabilityInterval);
            Assert.Equal(
                TimeSpan.FromMilliseconds(2000),
                MusicCatalogProbePolicyV2.Production.ProbeMaxWall);
            Assert.Equal(
                TimeSpan.FromMilliseconds(2250),
                MusicCatalogProbePolicyV2.Production.ManagedAwaitTimeout);
            Assert.Equal(536870912L, MusicCatalogProbePolicyV2.Production.MaxFileBytes);
            Assert.Equal(65536, MusicCatalogProbePolicyV2.Production.FirstHashBytes);
            Assert.Equal(8388608UL, MusicCatalogProbePolicyV2.Production.MaxInputBytes);
            Assert.Equal(96000UL, MusicCatalogProbePolicyV2.Production.MaxDecodedFrames);
            Assert.Equal(1, MusicCatalogProbePolicyV2.Production.MaxConcurrentProbes);
            Assert.Equal(1u, MusicCatalogProbePolicyV2.Production.ContractRevision);
        }

        [Fact]
        public async Task Discovery_UsesEveryHintExtension()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("hint-album");
                string[] extensions = MusicCatalog.GetAudioHintExtensionsForTests();
                for (int index = 0; index < extensions.Length; index++)
                    WriteBytes(Path.Combine(album, "hint-" + index + extensions[index]), index + 1);

                var port = FakeProbePort.CompatiblePresent();
                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JArray tracks = Tracks(catalog.GetFullCatalogJson());
                    Assert.Equal(extensions.Length, tracks.Count);
                    Assert.All(
                        tracks.Children<JObject>(),
                        track =>
                        {
                            Assert.Equal(
                                MusicCatalog.AvailabilityAvailable,
                                (string)track["availability"]);
                            Assert.Equal(
                                MusicCatalog.ReasonCompatibleSignalPresent,
                                (string)track["reason"]);
                        });
                    Assert.Equal(extensions.Length, port.ProbeCount);
                    Assert.All(
                        port.Inputs,
                        input =>
                        {
                            Assert.False(input.ExtensionMismatch);
                            Assert.False(string.IsNullOrEmpty(input.DetectedDecoder));
                            Assert.False(string.IsNullOrEmpty(input.DetectedContainer));
                            Assert.False(string.IsNullOrEmpty(input.DetectedCodec));
                            Assert.Equal(
                                input.First64kSha256.ToUpperInvariant(),
                                input.First64kSha256);
                            Assert.Equal(
                                input.CapabilityDigest.ToUpperInvariant(),
                                input.CapabilityDigest);
                            Assert.Equal(2u, input.StableObservationCount);
                            Assert.Equal(10u, input.StableIntervalMilliseconds);
                            Assert.Equal(536870912UL, input.MaxFileBytes);
                            Assert.Equal(65536u, input.FirstHashBytes);
                            Assert.Equal(200, input.MaxWallMilliseconds);
                            Assert.Equal(8388608UL, input.MaxInputBytes);
                            Assert.Equal(96000UL, input.MaxDecodedFrames);
                            Assert.Equal(1u, input.ProbeContractRevision);
                        });
                    Assert.True(port.AllCacheKeysValid);
                }
            }
        }

        [Fact]
        public async Task JukeboxAdmission_RequiresExactAvailableQualifiedTrack()
        {
            using (var availableTree = new TempTree())
            {
                string album = availableTree.CreateAlbum("jukebox-admission");
                WriteBytes(Path.Combine(album, "Qualified Track.wav"), 41);
                using (var catalog = CreateCatalog(
                    availableTree.Root,
                    FakeProbePort.CompatiblePresent()))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    string title = (string)Tracks(
                        catalog.GetFullCatalogJson())[0]["title"];

                    Assert.True(catalog.IsTrackAvailableForPlayback(title));
                    Assert.False(catalog.IsTrackAvailableForPlayback(
                        title.ToLowerInvariant()));
                    Assert.False(catalog.IsTrackAvailableForPlayback("missing"));
                }
            }

            using (var unavailableTree = new TempTree())
            {
                string album = unavailableTree.CreateAlbum("jukebox-rejected");
                WriteBytes(Path.Combine(album, "Rejected Track.wav"), 43);
                var unavailablePort = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => Task.FromResult(
                        new MusicCatalogProbeResultV2(
                            MusicCatalogProbeOutcomeV2.UnsupportedCodec,
                            input.CacheKey,
                            input.CapabilityDigest,
                            true)));
                using (var catalog = CreateCatalog(
                    unavailableTree.Root,
                    unavailablePort))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    string title = (string)Tracks(
                        catalog.GetFullCatalogJson())[0]["title"];
                    Assert.False(catalog.IsTrackAvailableForPlayback(title));
                }
            }
        }

        [Fact]
        public async Task RegisteredMissing_RemainsUnavailableAndIsNeverProbed()
        {
            using (var tree = new TempTree())
            {
                WriteBgmList(
                    tree.Root,
                    new RegisteredTrack(
                        "missing-title",
                        "sounds/missing-album/not-there.ogg",
                        "missing-album"));
                var port = FakeProbePort.CompatiblePresent();

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(catalog.GetFullCatalogJson(), "missing-title");
                    Assert.Equal(
                        new[]
                        {
                            "title", "url", "album", "fade", "vol", "weight",
                            "availability", "reason"
                        },
                        track.Properties().Select(property => property.Name).ToArray());
                    Assert.Equal(
                        MusicCatalog.AvailabilityUnavailable,
                        (string)track["availability"]);
                    Assert.Equal(MusicCatalog.ReasonMissing, (string)track["reason"]);
                    Assert.Equal(0, port.ProbeCount);
                }
            }
        }

        [Fact]
        public async Task CompatibleExtensionMismatch_IsAvailableWithExplicitReason()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("mismatch");
                WriteMpegBytes(Path.Combine(album, "container-lies.wav"), 37);
                var port = FakeProbePort.CompatiblePresent();

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(
                        catalog.GetFullCatalogJson(),
                        "container-lies");
                    Assert.Equal(
                        MusicCatalog.AvailabilityAvailable,
                        (string)track["availability"]);
                    Assert.Equal(
                        MusicCatalog.ReasonExtensionMismatch,
                        (string)track["reason"]);
                    MusicCatalogProbeInputV2 input = Assert.Single(port.Inputs);
                    Assert.Equal(MusicCatalog.DecoderBuiltin, input.DetectedDecoder);
                    Assert.Equal(
                        MusicCatalog.ContainerMpegAudio,
                        input.DetectedContainer);
                    Assert.Equal(
                        MusicCatalog.CodecMpegAudioLayerIII,
                        input.DetectedCodec);
                    Assert.True(input.ExtensionMismatch);
                    Assert.True(port.AllCacheKeysValid);
                }
            }
        }

        [Fact]
        public async Task ChangingFileDuringStabilityWindow_RemainsProbing()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("unstable");
                string path = Path.Combine(album, "changing.mp3");
                WriteBytes(path, 16);
                var port = FakeProbePort.CompatiblePresent();
                using (var writerCancellation = new CancellationTokenSource())
                {
                    Task writer = ContinuallyAppendAsync(path, writerCancellation.Token);
                    try
                    {
                        using (var catalog = CreateCatalog(
                            tree.Root,
                            port,
                            Policy(80, 250)))
                        {
                            await catalog.WaitForIdleForTestsAsync();
                            JObject track = Track(
                                catalog.GetFullCatalogJson(),
                                "changing");
                            Assert.Equal(
                                MusicCatalog.AvailabilityProbing,
                                (string)track["availability"]);
                            Assert.Equal(
                                MusicCatalog.ReasonUnstableInput,
                                (string)track["reason"]);
                            Assert.Equal(0, port.ProbeCount);
                        }
                    }
                    finally
                    {
                        writerCancellation.Cancel();
                        await IgnoreCancellationAsync(writer);
                    }
                }
            }
        }

        [Fact]
        public async Task ProbeTimeout_RemainsProbingAndIsNotCached()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("timeout");
                WriteBytes(Path.Combine(album, "slow.flac"), 23);
                var never = new TaskCompletionSource<MusicCatalogProbeResultV2>(
                    TaskCreationOptions.RunContinuationsAsynchronously);
                var port = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => never.Task);

                using (var catalog = CreateCatalog(
                    tree.Root,
                    port,
                    Policy(5, 30)))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(catalog.GetFullCatalogJson(), "slow");
                    Assert.Equal(
                        MusicCatalog.AvailabilityProbing,
                        (string)track["availability"]);
                    Assert.Equal(
                        MusicCatalog.ReasonInconclusiveTimeout,
                        (string)track["reason"]);
                    Assert.Equal(1, port.ProbeCount);

                    await catalog.RefreshForTestsAsync();
                    Assert.Equal(2, port.ProbeCount);
                    Assert.True(port.AllCacheKeysValid);
                }
            }
        }

        [Fact]
        public async Task SingleProbeSlot_DoesNotStartASecondOwnerCallEarly()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("serialized-probes");
                WriteBytes(Path.Combine(album, "first.wav"), 40);
                WriteBytes(Path.Combine(album, "second.wav"), 41);
                var firstStarted = new TaskCompletionSource<bool>(
                    TaskCreationOptions.RunContinuationsAsynchronously);
                var releaseFirst = new TaskCompletionSource<bool>(
                    TaskCreationOptions.RunContinuationsAsynchronously);
                int handlerCalls = 0;
                var port = new FakeProbePort(
                    CapabilityA,
                    async (input, cancellationToken) =>
                    {
                        if (Interlocked.Increment(ref handlerCalls) == 1)
                        {
                            firstStarted.TrySetResult(true);
                            await releaseFirst.Task.ConfigureAwait(false);
                        }
                        return MusicCatalogProbeResultV2
                            .CompatibleSignalPresent(input);
                    });

                using (var catalog = CreateCatalog(
                    tree.Root,
                    port,
                    Policy(5, 500, 1)))
                {
                    try
                    {
                        await firstStarted.Task;
                        await Task.Delay(50);
                        Assert.Equal(1, port.ProbeCount);
                    }
                    finally
                    {
                        releaseFirst.TrySetResult(true);
                    }
                    await catalog.WaitForIdleForTestsAsync();
                    Assert.Equal(2, port.ProbeCount);
                }
            }
        }

        [Fact]
        public async Task NativeInconclusiveTimeout_RemainsProbingAndIsNotCached()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("native-timeout");
                WriteBytes(Path.Combine(album, "native-slow.ogg"), 34);
                var port = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => Task.FromResult(
                        MusicCatalogProbeResultV2.InconclusiveTimeout(input)));

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(
                        catalog.GetFullCatalogJson(),
                        "native-slow");
                    Assert.Equal(
                        MusicCatalog.AvailabilityProbing,
                        (string)track["availability"]);
                    Assert.Equal(
                        MusicCatalog.ReasonInconclusiveTimeout,
                        (string)track["reason"]);
                    Assert.Equal(1, port.ProbeCount);

                    await catalog.RefreshForTestsAsync();
                    Assert.Equal(2, port.ProbeCount);
                }
            }
        }

        [Fact]
        public async Task ManagedGrace_AllowsNativeDeadlineOutcomeToWin()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("native-deadline-race");
                WriteBytes(Path.Combine(album, "deadline.flac"), 35);
                int nativeOutcomeReturned = 0;
                var port = new FakeProbePort(
                    CapabilityA,
                    async (input, cancellationToken) =>
                    {
                        await Task.Delay(40, cancellationToken)
                            .ConfigureAwait(false);
                        Interlocked.Exchange(ref nativeOutcomeReturned, 1);
                        return MusicCatalogProbeResultV2
                            .InconclusiveTimeout(input);
                    });

                using (var catalog = CreateCatalog(
                    tree.Root,
                    port,
                    Policy(5, 30, 1, 80)))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(
                        catalog.GetFullCatalogJson(),
                        "deadline");
                    Assert.Equal(
                        MusicCatalog.AvailabilityProbing,
                        (string)track["availability"]);
                    Assert.Equal(
                        MusicCatalog.ReasonInconclusiveTimeout,
                        (string)track["reason"]);
                    Assert.Equal(1, Volatile.Read(ref nativeOutcomeReturned));
                }
            }
        }

        [Fact]
        public async Task CompatibleAllZeroSignal_IsAvailableButUnknown()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("silence");
                WriteBytes(Path.Combine(album, "intentional-silence.opus"), 48);
                var port = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => Task.FromResult(
                        MusicCatalogProbeResultV2.CompatibleSignalUnknown(input)));

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(
                        catalog.GetFullCatalogJson(),
                        "intentional-silence");
                    Assert.Equal(
                        MusicCatalog.AvailabilityAvailable,
                        (string)track["availability"]);
                    Assert.Equal(
                        MusicCatalog.ReasonCompatibleSignalUnknown,
                        (string)track["reason"]);
                }
            }
        }

        [Fact]
        public async Task ClosedProbeOutcome_IsUnavailableWithTypedReason()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("unsupported");
                WriteBytes(Path.Combine(album, "unsupported.aac"), 31);
                var port = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => Task.FromResult(
                        new MusicCatalogProbeResultV2(
                            MusicCatalogProbeOutcomeV2.UnsupportedCodec,
                            input.CacheKey,
                            input.CapabilityDigest,
                            false)));

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(
                        catalog.GetFullCatalogJson(),
                        "unsupported");
                    Assert.Equal(
                        MusicCatalog.AvailabilityUnavailable,
                        (string)track["availability"]);
                    Assert.Equal("unsupported_codec", (string)track["reason"]);
                }
            }
        }

        [Fact]
        public async Task MissingCapabilityDigest_DoesNotFakeLegacyTrackAvailability()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("legacy");
                WriteBytes(Path.Combine(album, "old-entry.wav"), 29);
                var port = new FakeProbePort(
                    null,
                    (input, cancellationToken) => Task.FromResult(
                        MusicCatalogProbeResultV2.CompatibleSignalPresent(input)));

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(
                        catalog.GetFullCatalogJson(),
                        "old-entry");
                    Assert.Equal(
                        MusicCatalog.AvailabilityUnavailable,
                        (string)track["availability"]);
                    Assert.Equal("probe_unavailable", (string)track["reason"]);
                    Assert.Equal(0, port.ProbeCount);
                }
            }
        }

        [Fact]
        public async Task UnknownContentCannotBePromotedByCompatiblePort()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("unknown-content");
                string path = Path.Combine(album, "extension-only.mp3");
                File.WriteAllBytes(path, new byte[64]);
                var port = FakeProbePort.CompatiblePresent();

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(
                        catalog.GetFullCatalogJson(),
                        "extension-only");
                    Assert.Equal(
                        MusicCatalog.AvailabilityUnavailable,
                        (string)track["availability"]);
                    Assert.Equal("unsupported_container", (string)track["reason"]);
                    Assert.Equal(0, port.ProbeCount);
                }
            }
        }

        [Fact]
        public async Task ForgedProbeBindingCannotPromoteRecognizedContent()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("forged-binding");
                WriteBytes(Path.Combine(album, "forged.mp3"), 64);
                var port = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => Task.FromResult(
                        new MusicCatalogProbeResultV2(
                            MusicCatalogProbeOutcomeV2.CompatibleSignalPresent,
                            new string('0', 64),
                            input.CapabilityDigest,
                            true)));

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(catalog.GetFullCatalogJson(), "forged");
                    Assert.Equal(
                        MusicCatalog.AvailabilityUnavailable,
                        (string)track["availability"]);
                    Assert.Equal(
                        "probe_evidence_invalid",
                        (string)track["reason"]);
                }
            }
        }

        [Fact]
        public async Task NonCanonicalCapabilityEchoCannotPromoteRecognizedContent()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("noncanonical-capability");
                WriteBytes(Path.Combine(album, "lowercase.mp3"), 64);
                var port = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => Task.FromResult(
                        new MusicCatalogProbeResultV2(
                            MusicCatalogProbeOutcomeV2.CompatibleSignalPresent,
                            input.CacheKey,
                            input.CapabilityDigest.ToLowerInvariant(),
                            true)));

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(
                        catalog.GetFullCatalogJson(),
                        "lowercase");
                    Assert.Equal(
                        MusicCatalog.AvailabilityUnavailable,
                        (string)track["availability"]);
                    Assert.Equal(
                        "probe_evidence_invalid",
                        (string)track["reason"]);
                }
            }
        }

        [Fact]
        public async Task CapabilityMismatchCannotPromoteRecognizedContent()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("capability-mismatch");
                WriteBytes(Path.Combine(album, "mismatch.flac"), 64);
                var port = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => Task.FromResult(
                        new MusicCatalogProbeResultV2(
                            MusicCatalogProbeOutcomeV2.CompatibleSignalPresent,
                            input.CacheKey,
                            input.CapabilityDigest,
                            false)));

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject track = Track(catalog.GetFullCatalogJson(), "mismatch");
                    Assert.Equal(
                        MusicCatalog.AvailabilityUnavailable,
                        (string)track["availability"]);
                    Assert.Equal(
                        "capability_mismatch",
                        (string)track["reason"]);
                }
            }
        }

        [Fact]
        public async Task QualificationPass_FreezesDigestAndPublishesTypedBoundary()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("digest-freeze");
                WriteBytes(Path.Combine(album, "first.mp3"), 70);
                WriteBytes(Path.Combine(album, "second.opus"), 71);
                FakeProbePort port = null;
                int firstPassCalls = 0;
                port = new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) =>
                    {
                        if (Interlocked.Increment(ref firstPassCalls) == 1)
                            port.CapabilityDigest = CapabilityB;
                        return Task.FromResult(
                            MusicCatalogProbeResultV2.CompatibleSignalPresent(input));
                    });

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForCurrentQualificationAsync();
                    MusicCatalogQualificationSnapshotV2 first =
                        catalog.QualificationSnapshotV2;
                    Assert.True(first.IsCompleteForCapability(CapabilityA));
                    Assert.False(first.IsCompleteForCapability(CapabilityB));
                    Assert.Equal(2, first.Available);
                    MusicCatalogProjectionV2 firstProjection =
                        catalog.GetProjectionV2();
                    Assert.Equal(
                        first.Revision,
                        firstProjection.Qualification.Revision);
                    Assert.True(
                        firstProjection.Qualification
                            .IsCompleteForCapability(CapabilityA));
                    Assert.Equal(
                        2,
                        Tracks(firstProjection.CatalogJson).Count);
                    Assert.All(
                        port.Inputs,
                        input => Assert.Equal(CapabilityA, input.CapabilityDigest));

                    var states = new List<MusicCatalogQualificationSnapshotV2>();
                    object stateSync = new object();
                    catalog.QualificationChangedV2 += state =>
                    {
                        lock (stateSync) states.Add(state);
                    };
                    await catalog.RequalifyForCapabilityChangeAsync();

                    MusicCatalogQualificationSnapshotV2[] captured;
                    lock (stateSync) captured = states.ToArray();
                    Assert.Equal(2, captured.Length);
                    Assert.False(captured[0].IsComplete);
                    Assert.True(captured[1].IsComplete);
                    Assert.Equal(captured[0].Revision, captured[1].Revision);
                    Assert.Equal(CapabilityB, captured[0].CapabilityDigest);
                    Assert.True(captured[1].IsCompleteForCapability(CapabilityB));
                    MusicCatalogProjectionV2 secondProjection =
                        catalog.GetProjectionV2();
                    Assert.Equal(
                        captured[1].Revision,
                        secondProjection.Qualification.Revision);
                    Assert.True(
                        secondProjection.Qualification
                            .IsCompleteForCapability(CapabilityB));
                    Assert.All(
                        port.Inputs.Skip(2),
                        input => Assert.Equal(CapabilityB, input.CapabilityDigest));
                }
            }
        }

        [Fact]
        public async Task HotRefresh_EmitsOneReadyBarrierAroundPublishedCompleteRevision()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("ready-barrier");
                WriteBytes(Path.Combine(album, "track.mp3"), 72);
                var port = FakeProbePort.CompatiblePresent();

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForCurrentQualificationAsync();
                    var changes = new List<MusicCatalogReadyBarrierChangeV2>();
                    bool completeWasPublishedBeforeTerminal = false;
                    catalog.ReadyBarrierChangedV2 += change =>
                    {
                        changes.Add(change);
                        if (change.Phase ==
                            MusicCatalogReadyBarrierPhaseV2.Completed)
                        {
                            MusicCatalogProjectionV2 projection =
                                catalog.GetProjectionV2();
                            completeWasPublishedBeforeTerminal =
                                projection.Qualification.Revision ==
                                    change.Revision &&
                                projection.Qualification.IsCompleteForCapability(
                                    change.CapabilityDigest);
                        }
                    };

                    await catalog.RefreshForTestsAsync();

                    Assert.Equal(2, changes.Count);
                    Assert.Equal(
                        MusicCatalogReadyBarrierPhaseV2.Started,
                        changes[0].Phase);
                    Assert.Equal(
                        MusicCatalogReadyBarrierPhaseV2.Completed,
                        changes[1].Phase);
                    Assert.Equal(changes[0].Revision, changes[1].Revision);
                    Assert.Equal(CapabilityA, changes[0].CapabilityDigest);
                    Assert.Equal(CapabilityA, changes[1].CapabilityDigest);
                    Assert.True(completeWasPublishedBeforeTerminal);

                    changes.Clear();
                    await catalog.RequalifyForCapabilityChangeAsync();
                    Assert.Empty(changes);
                }
            }
        }

        [Fact]
        public async Task CacheIdentity_InvalidatesOnFileAndCapabilityChanges()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("cache");
                string path = Path.Combine(album, "cached.m4a");
                WriteBytes(path, 67);
                var port = FakeProbePort.CompatiblePresent();

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    Assert.Equal(1, port.ProbeCount);

                    await catalog.RefreshForTestsAsync();
                    Assert.Equal(1, port.ProbeCount);

                    DateTime originalMtime = File.GetLastWriteTimeUtc(path);
                    using (var stream = new FileStream(
                        path,
                        FileMode.Open,
                        FileAccess.Write,
                        FileShare.ReadWrite | FileShare.Delete))
                    {
                        stream.Position = 20;
                        stream.WriteByte(0xa5);
                    }
                    File.SetLastWriteTimeUtc(path, originalMtime);
                    await catalog.RefreshForTestsAsync();
                    Assert.Equal(2, port.ProbeCount);

                    using (var stream = new FileStream(
                        path,
                        FileMode.Append,
                        FileAccess.Write,
                        FileShare.ReadWrite | FileShare.Delete))
                    {
                        stream.WriteByte(0x5a);
                    }
                    await catalog.RefreshForTestsAsync();
                    Assert.Equal(3, port.ProbeCount);

                    port.CapabilityDigest = CapabilityB;
                    await catalog.RefreshForTestsAsync();
                    Assert.Equal(4, port.ProbeCount);

                    MusicCatalogProbeInputV2[] inputs = port.Inputs;
                    Assert.Equal(4, inputs.Length);
                    Assert.Equal(CapabilityA, inputs[0].CapabilityDigest);
                    Assert.Equal(CapabilityA, inputs[1].CapabilityDigest);
                    Assert.Equal(CapabilityA, inputs[2].CapabilityDigest);
                    Assert.Equal(CapabilityB, inputs[3].CapabilityDigest);
                    Assert.Equal(inputs[0].FileSizeBytes, inputs[1].FileSizeBytes);
                    Assert.Equal(
                        inputs[0].ModifiedTimeUtcTicks,
                        inputs[1].ModifiedTimeUtcTicks);
                    Assert.NotEqual(
                        inputs[0].First64kSha256,
                        inputs[1].First64kSha256);
                    Assert.Equal(4, inputs.Select(input => input.CacheKey).Distinct().Count());
                    Assert.True(port.AllCacheKeysValid);
                }
            }
        }

        [Fact]
        public async Task Refresh_ReplacesWholeSnapshotAndUpdatesCarryProjection()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("replacement");
                string removedPath = Path.Combine(album, "removed.mp3");
                WriteBytes(removedPath, 11);
                WriteBytes(Path.Combine(album, "retained.ogg"), 12);
                var port = FakeProbePort.CompatiblePresent();

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    var updates = new List<string>();
                    object updateSync = new object();
                    catalog.CatalogChanged += json =>
                    {
                        lock (updateSync) updates.Add(json);
                    };

                    File.Delete(removedPath);
                    WriteBytes(Path.Combine(album, "added.mp4"), 13);
                    await catalog.RefreshForTestsAsync();

                    string[] finalTitles = Tracks(catalog.GetFullCatalogJson())
                        .Children<JObject>()
                        .Select(track => (string)track["title"])
                        .ToArray();
                    Assert.Equal(new[] { "added", "retained" }, finalTitles);

                    string[] captured;
                    lock (updateSync) captured = updates.ToArray();
                    JObject replacement = captured
                        .Select(JObject.Parse)
                        .FirstOrDefault(update =>
                            update["removed"].Values<string>().Contains("removed") &&
                            update["added"].Children<JObject>().Any(
                                track => (string)track["title"] == "added"));
                    Assert.NotNull(replacement);
                    Assert.All(
                        captured.Select(JObject.Parse)
                            .SelectMany(update => update["added"].Children<JObject>()),
                        track =>
                        {
                            Assert.NotNull(track.Property("availability"));
                            Assert.NotNull(track.Property("reason"));
                        });
                    Assert.Contains(
                        captured.Select(JObject.Parse)
                            .SelectMany(update => update["added"].Children<JObject>()),
                        track =>
                            (string)track["title"] == "added" &&
                            (string)track["availability"] ==
                                MusicCatalog.AvailabilityProbing &&
                            (string)track["reason"] ==
                                MusicCatalog.ReasonPendingProbe);
                }
            }
        }

        [Fact]
        public async Task CatalogJson_RoundTripsEscapedRegisteredFields()
        {
            using (var tree = new TempTree())
            {
                string albumDirectory = tree.CreateAlbum("escaped-files");
                WriteBytes(Path.Combine(albumDirectory, "source.mp3"), 19);
                string title = "A \"quoted\" \\ track" +
                    Environment.NewLine + "next";
                string album = "Album \"quoted\" \\ row" +
                    Environment.NewLine + "next";
                WriteBgmList(
                    tree.Root,
                    new RegisteredTrack(
                        title,
                        "sounds/escaped-files/source.mp3",
                        album));
                var port = FakeProbePort.CompatiblePresent();

                using (var catalog = CreateCatalog(tree.Root, port))
                {
                    await catalog.WaitForIdleForTestsAsync();
                    JObject root = JObject.Parse(catalog.GetFullCatalogJson());
                    JObject track = root["tracks"].Children<JObject>().Single();
                    Assert.Equal(title, (string)track["title"]);
                    Assert.Equal(album, (string)track["album"]);
                    Assert.Equal(
                        new[] { title },
                        root["albums"][album].Values<string>().ToArray());
                    Assert.Equal(
                        MusicCatalog.AvailabilityAvailable,
                        (string)track["availability"]);
                    Assert.NotNull(track.Property("reason"));
                }
            }
        }

        [Fact]
        public void Dispose_CancelsAndJoinsPendingRefresh()
        {
            using (var tree = new TempTree())
            {
                string album = tree.CreateAlbum("dispose");
                WriteBytes(Path.Combine(album, "pending.wav"), 25);
                var port = FakeProbePort.CompatiblePresent();
                var catalog = CreateCatalog(
                    tree.Root,
                    port,
                    Policy(5000, 5000));
                var timer = Stopwatch.StartNew();
                catalog.Dispose();
                timer.Stop();
                Assert.True(
                    timer.Elapsed < TimeSpan.FromSeconds(2),
                    "Dispose did not cancel and join the pending refresh promptly.");
            }
        }

        private static MusicCatalog CreateCatalog(
            string root,
            IMusicCatalogRuntimeProbePortV2 port,
            MusicCatalogProbePolicyV2 policy = null)
        {
            return new MusicCatalog(
                root,
                port,
                policy ?? Policy(10, 200),
                false);
        }

        private static MusicCatalogProbePolicyV2 Policy(
            int stabilityMilliseconds,
            int timeoutMilliseconds,
            int maxConcurrentProbes = 4,
            int managedAwaitMilliseconds = -1)
        {
            int managedAwait = managedAwaitMilliseconds < 0
                ? timeoutMilliseconds
                : managedAwaitMilliseconds;
            return new MusicCatalogProbePolicyV2(
                TimeSpan.FromMilliseconds(stabilityMilliseconds),
                TimeSpan.FromMilliseconds(timeoutMilliseconds),
                TimeSpan.FromMilliseconds(managedAwait),
                536870912L,
                65536,
                8388608UL,
                96000UL,
                maxConcurrentProbes,
                MusicCatalogProbePolicyV2.ProductionContractRevision);
        }

        private static JArray Tracks(string json)
        {
            return (JArray)JObject.Parse(json)["tracks"];
        }

        private static JObject Track(string json, string title)
        {
            return Tracks(json)
                .Children<JObject>()
                .Single(track => (string)track["title"] == title);
        }

        private static void WriteBytes(string path, int count)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            byte[] bytes = Enumerable.Range(0, Math.Max(count, 32))
                .Select(value => (byte)(value % 251))
                .ToArray();
            string extension = Path.GetExtension(path).ToLowerInvariant();
            if (extension == ".wav")
            {
                PutAscii(bytes, 0, "RIFF");
                PutAscii(bytes, 8, "WAVE");
            }
            else if (extension == ".mp3")
            {
                PutAscii(bytes, 0, "ID3");
            }
            else if (extension == ".flac")
            {
                PutAscii(bytes, 0, "fLaC");
            }
            else if (extension == ".ogg")
            {
                PutAscii(bytes, 0, "OggS");
                PutAscii(bytes, 8, "vorbis");
            }
            else if (extension == ".opus")
            {
                PutAscii(bytes, 0, "OggS");
                PutAscii(bytes, 8, "OpusHead");
            }
            else if (extension == ".m4a" || extension == ".mp4")
            {
                PutAscii(bytes, 4, "ftyp");
            }
            else if (extension == ".aac" || extension == ".adts")
            {
                bytes[0] = 0xff;
                bytes[1] = 0xf1;
            }
            File.WriteAllBytes(path, bytes);
        }

        private static void WriteMpegBytes(string path, int count)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            byte[] bytes = Enumerable.Range(0, Math.Max(count, 32))
                .Select(value => (byte)(value % 251))
                .ToArray();
            PutAscii(bytes, 0, "ID3");
            File.WriteAllBytes(path, bytes);
        }

        private static void PutAscii(byte[] bytes, int offset, string value)
        {
            for (int index = 0; index < value.Length; index++)
                bytes[offset + index] = (byte)value[index];
        }

        private static void WriteBgmList(
            string root,
            params RegisteredTrack[] tracks)
        {
            var data = new XElement("data");
            for (int index = 0; index < tracks.Length; index++)
            {
                RegisteredTrack track = tracks[index];
                data.Add(
                    new XElement(
                        "music",
                        new XElement("title", track.Title),
                        new XElement("url", track.Url),
                        new XElement("album", track.Album),
                        new XElement("fadeDuration", "20"),
                        new XElement("baseVolume", "100"),
                        new XElement("weight", "100")));
            }
            var document = new XDocument(data);
            document.Save(Path.Combine(root, "sounds", "bgm_list.xml"));
        }

        private static async Task ContinuallyAppendAsync(
            string path,
            CancellationToken cancellationToken)
        {
            try
            {
                while (true)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    using (var stream = new FileStream(
                        path,
                        FileMode.Append,
                        FileAccess.Write,
                        FileShare.ReadWrite | FileShare.Delete))
                    {
                        stream.WriteByte(0x7f);
                    }
                    await Task.Delay(3, cancellationToken);
                }
            }
            catch (OperationCanceledException) { }
        }

        private static async Task IgnoreCancellationAsync(Task task)
        {
            try { await task; }
            catch (OperationCanceledException) { }
        }

        private sealed class RegisteredTrack
        {
            internal RegisteredTrack(string title, string url, string album)
            {
                Title = title;
                Url = url;
                Album = album;
            }

            internal string Title { get; private set; }
            internal string Url { get; private set; }
            internal string Album { get; private set; }
        }

        private sealed class FakeProbePort : IMusicCatalogRuntimeProbePortV2
        {
            private readonly object _sync = new object();
            private readonly List<MusicCatalogProbeInputV2> _inputs =
                new List<MusicCatalogProbeInputV2>();
            private readonly Func<
                MusicCatalogProbeInputV2,
                CancellationToken,
                Task<MusicCatalogProbeResultV2>> _handler;
            private int _probeCount;
            private int _invalidCacheKey;

            internal FakeProbePort(
                string capabilityDigest,
                Func<
                    MusicCatalogProbeInputV2,
                    CancellationToken,
                    Task<MusicCatalogProbeResultV2>> handler)
            {
                CapabilityDigest = capabilityDigest;
                _handler = handler;
            }

            public string CapabilityDigest { get; set; }

            internal int ProbeCount { get { return Volatile.Read(ref _probeCount); } }

            internal bool AllCacheKeysValid
            {
                get { return Volatile.Read(ref _invalidCacheKey) == 0; }
            }

            internal MusicCatalogProbeInputV2[] Inputs
            {
                get
                {
                    lock (_sync) return _inputs.ToArray();
                }
            }

            internal static FakeProbePort CompatiblePresent()
            {
                return new FakeProbePort(
                    CapabilityA,
                    (input, cancellationToken) => Task.FromResult(
                        MusicCatalogProbeResultV2.CompatibleSignalPresent(input)));
            }

            public Task<MusicCatalogProbeResultV2> ProbeAsync(
                MusicCatalogProbeInputV2 input,
                CancellationToken cancellationToken)
            {
                Interlocked.Increment(ref _probeCount);
                lock (_sync) _inputs.Add(input);
                string recomputed = MusicCatalog.BuildProbeCacheKey(
                    input.NormalizedPath,
                    checked((long)input.FileSizeBytes),
                    input.ModifiedTimeUtcTicks,
                    input.First64kSha256,
                    input.CapabilityDigest,
                    input.ProbeContractRevision);
                if (!string.Equals(
                    input.CacheKey,
                    recomputed,
                    StringComparison.Ordinal))
                {
                    Volatile.Write(ref _invalidCacheKey, 1);
                }
                return _handler(input, cancellationToken);
            }
        }

        private sealed class TempTree : IDisposable
        {
            internal TempTree()
            {
                Root = Path.Combine(
                    Path.GetTempPath(),
                    "cf7-music-catalog-v2-tests",
                    Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(Path.Combine(Root, "sounds"));
            }

            internal string Root { get; private set; }

            internal string CreateAlbum(string name)
            {
                string path = Path.Combine(Root, "sounds", name);
                Directory.CreateDirectory(path);
                return path;
            }

            public void Dispose()
            {
                if (!Directory.Exists(Root)) return;
                try { Directory.Delete(Root, true); }
                catch (IOException)
                {
                    Thread.Sleep(20);
                    if (Directory.Exists(Root)) Directory.Delete(Root, true);
                }
                catch (UnauthorizedAccessException)
                {
                    Thread.Sleep(20);
                    if (Directory.Exists(Root)) Directory.Delete(Root, true);
                }
            }
        }
    }
}
