using System;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Observation
{
    public sealed class PixelContentHandleStoreTests
    {
        private const string SessionId =
            "session_pixels_AAAAAAAAAAAAAAAAAA";
        private const string TargetId =
            "target_pixels_AAAAAAAAAAAAAAAAAAA";
        private const string ObservationId =
            "observation_pixels_AAAAAAAAAAAAAA";
        private const string ClientId = "pixel-test-client";

        [Fact]
        public void SequentialChunksCarryOffsetFinalAndHashThenRejectReplay()
        {
            using Setup setup = CreateSetup();
            byte[] source = Enumerable.Range(
                    0,
                    AgentProtocolV1.MaximumBinaryChunkBytes + 3)
                .Select(index => (byte)(index % 251))
                .ToArray();
            byte originalFirst = source[0];
            Assert.True(setup.Store.TryCreate(
                setup.Binding,
                source,
                out PixelContentHandleDescriptor handle,
                out _));
            source[0] ^= 0xFF;

            PixelContentReadOutcome first = setup.Store.Read(
                Read(setup, handle, 0,
                    AgentProtocolV1.MaximumBinaryChunkBytes));
            PixelContentReadOutcome final = setup.Store.Read(
                Read(
                    setup,
                    handle,
                    AgentProtocolV1.MaximumBinaryChunkBytes,
                    AgentProtocolV1.MaximumBinaryChunkBytes));

            Assert.True(first.Success);
            Assert.Equal(0, first.Offset);
            Assert.False(first.Final);
            Assert.Equal(
                AgentProtocolV1.MaximumBinaryChunkBytes,
                first.Content.Length);
            Assert.Equal(originalFirst, first.Content[0]);
            Assert.True(final.Success);
            Assert.Equal(
                AgentProtocolV1.MaximumBinaryChunkBytes,
                final.Offset);
            Assert.True(final.Final);
            Assert.Equal(3, final.Content.Length);
            Assert.Equal(handle.ContentHash, first.ContentHash);
            Assert.Equal(handle.ContentHash, final.ContentHash);
            Assert.Equal(source.Length, final.TotalBytes);

            PixelContentReadOutcome replay = setup.Store.Read(
                Read(setup, handle, 0, 1));
            Assert.False(replay.Success);
            Assert.Equal(
                "content_handle_replayed",
                replay.ReasonCode);
            Assert.Equal(
                4,
                setup.Audit.Events.Count);
            Assert.All(
                setup.Audit.Events,
                audit => Assert.Equal(
                    ObservationId,
                    audit.ObservationId));
        }

        [Fact]
        public void CrossOwnerSessionGrantObservationAndOffsetAreRejected()
        {
            using Setup setup = CreateSetup();
            Assert.True(setup.Store.TryCreate(
                setup.Binding,
                new byte[] { 50, 60, 70, 255 },
                out PixelContentHandleDescriptor handle,
                out _));

            AssertRejected(
                setup,
                handle,
                ClientId: "other-client",
                reason: "content_handle_binding_mismatch");
            AssertRejected(
                setup,
                handle,
                principal: "other-principal",
                reason: "content_handle_binding_mismatch");
            AssertRejected(
                setup,
                handle,
                session: "other-session",
                reason: "content_handle_binding_mismatch");
            AssertRejected(
                setup,
                handle,
                grant: "other-grant",
                reason: "content_handle_binding_mismatch");
            AssertRejected(
                setup,
                handle,
                observation: "other-observation",
                reason: "content_handle_binding_mismatch");
            PixelContentReadOutcome wrongOffset = setup.Store.Read(
                Read(setup, handle, 1, 1));
            Assert.False(wrongOffset.Success);
            Assert.Equal(
                "content_handle_offset_mismatch",
                wrongOffset.ReasonCode);

            PixelContentReadOutcome correct = setup.Store.Read(
                Read(setup, handle, 0, 4));
            Assert.True(correct.Success);
            Assert.True(correct.Final);
            Assert.Equal(8, setup.Audit.Events.Count);
            Assert.Equal(
                6,
                setup.Audit.Events.Count(entry =>
                    !entry.Accepted));
        }

        [Fact]
        public void TtlExpiryAndGrantRevocationStopFutureReads()
        {
            using Setup expired = CreateSetup();
            Assert.True(expired.Store.TryCreate(
                expired.Binding,
                new byte[] { 50, 60, 70, 255 },
                out PixelContentHandleDescriptor expiredHandle,
                out _));
            Assert.Equal(
                expired.Clock.MonotonicMilliseconds
                    + AgentProtocolV1.MaximumContentHandleTtlMs,
                expiredHandle.ExpiresMonotonic);
            expired.Clock.Advance(TimeSpan.FromMilliseconds(
                AgentProtocolV1.MaximumContentHandleTtlMs + 1));

            PixelContentReadOutcome afterTtl = expired.Store.Read(
                Read(expired, expiredHandle, 0, 4));
            Assert.False(afterTtl.Success);
            Assert.Equal(
                "content_handle_expired",
                afterTtl.ReasonCode);

            using Setup revoked = CreateSetup();
            Assert.True(revoked.Store.TryCreate(
                revoked.Binding,
                new byte[] { 50, 60, 70, 255 },
                out PixelContentHandleDescriptor revokedHandle,
                out _));
            Assert.True(revoked.Grants.Revoke(
                revoked.Grant.ObservationGrantId,
                "human_override"));
            PixelContentReadOutcome afterRevoke = revoked.Store.Read(
                Read(revoked, revokedHandle, 0, 4));
            Assert.False(afterRevoke.Success);
            Assert.Equal("human_override", afterRevoke.ReasonCode);
        }

        [Fact]
        public void ObjectAndChunkCapsFailClosedAndAreAudited()
        {
            using Setup setup = CreateSetup();
            byte[] oversized =
                new byte[
                    AgentProtocolV1.MaximumBinaryObjectBytes + 1];
            Assert.False(setup.Store.TryCreate(
                setup.Binding,
                oversized,
                out _,
                out string objectReason));
            Assert.Equal(
                "capture_object_too_large",
                objectReason);

            Assert.True(setup.Store.TryCreate(
                setup.Binding,
                new byte[] { 50, 60, 70, 255 },
                out PixelContentHandleDescriptor handle,
                out _));
            PixelContentReadOutcome chunkTooLarge =
                setup.Store.Read(
                    Read(
                        setup,
                        handle,
                        0,
                        AgentProtocolV1.MaximumBinaryChunkBytes
                            + 1));
            Assert.False(chunkTooLarge.Success);
            Assert.Equal(
                "binary_chunk_too_large",
                chunkTooLarge.ReasonCode);
            Assert.Contains(
                setup.Audit.Events,
                entry => entry.ReasonCode
                    == "capture_object_too_large");
            Assert.Contains(
                setup.Audit.Events,
                entry => entry.ReasonCode
                    == "binary_chunk_too_large");
        }

        [Fact]
        public void ObservationRevocationDestroysOneShotObject()
        {
            using Setup setup = CreateSetup();
            Assert.True(setup.Store.TryCreate(
                setup.Binding,
                new byte[] { 50, 60, 70, 255 },
                out PixelContentHandleDescriptor handle,
                out _));

            Assert.Equal(
                1,
                setup.Store.RevokeObservation(
                    ObservationId,
                    "observation_consumed"));
            PixelContentReadOutcome read = setup.Store.Read(
                Read(setup, handle, 0, 4));

            Assert.False(read.Success);
            Assert.Equal(
                "observation_consumed",
                read.ReasonCode);
            Assert.Contains(
                setup.Audit.Events,
                entry => entry.EventType
                        == "pixel_handle_revoke"
                    && entry.Accepted);
        }

        [Fact]
        public void AuditFailureFailsClosedWithoutAdvancingReadOffset()
        {
            using Setup setup = CreateSetup();
            var audit = new ToggleThrowingAuditSink
            {
                Throw = true
            };
            using var openStore = new PixelContentHandleStore(
                setup.Clock,
                setup.Grants,
                audit);
            Assert.False(openStore.TryCreate(
                setup.Binding,
                new byte[] { 50, 60, 70, 255 },
                out _,
                out string openReason));
            Assert.Equal("audit_unavailable", openReason);

            audit.Throw = false;
            using var readStore = new PixelContentHandleStore(
                setup.Clock,
                setup.Grants,
                audit);
            Assert.True(readStore.TryCreate(
                setup.Binding,
                new byte[] { 50, 60, 70, 255 },
                out PixelContentHandleDescriptor handle,
                out _));
            audit.Throw = true;
            PixelContentReadOutcome failed = readStore.Read(
                Read(setup, handle, 0, 4));
            Assert.False(failed.Success);
            Assert.Equal("audit_unavailable", failed.ReasonCode);

            audit.Throw = false;
            PixelContentReadOutcome retried = readStore.Read(
                Read(setup, handle, 0, 4));
            Assert.True(retried.Success);
            Assert.True(retried.Final);
        }

        private static void AssertRejected(
            Setup setup,
            PixelContentHandleDescriptor handle,
            string ClientId = null,
            string principal = null,
            string session = null,
            string grant = null,
            string observation = null,
            string reason = null)
        {
            PixelContentReadRequest request =
                Read(setup, handle, 0, 1);
            request = new PixelContentReadRequest
            {
                Handle = request.Handle,
                ClientInstanceId =
                    ClientId ?? request.ClientInstanceId,
                SecurityPrincipalId =
                    principal ?? request.SecurityPrincipalId,
                SessionId = session ?? request.SessionId,
                ObservationGrantId =
                    grant ?? request.ObservationGrantId,
                ObservationId =
                    observation ?? request.ObservationId,
                Offset = request.Offset,
                MaximumBytes = request.MaximumBytes
            };
            PixelContentReadOutcome outcome =
                setup.Store.Read(request);
            Assert.False(outcome.Success);
            Assert.Equal(reason, outcome.ReasonCode);
        }

        private static PixelContentReadRequest Read(
            Setup setup,
            PixelContentHandleDescriptor handle,
            long offset,
            int maximumBytes)
        {
            return new PixelContentReadRequest
            {
                Handle = handle.Handle,
                ClientInstanceId = ClientId,
                SecurityPrincipalId =
                    setup.Credential.SecurityPrincipalId,
                SessionId = SessionId,
                ObservationGrantId =
                    setup.Grant.ObservationGrantId,
                ObservationId = ObservationId,
                Offset = offset,
                MaximumBytes = maximumBytes
            };
        }

        private static Setup CreateSetup()
        {
            var clock = new ManualObservationClock();
            var targets = new MutableObservationAuthority();
            targets.AddTarget(TargetId);
            var credentials = new PrincipalCredentialAuthority(
                clock,
                new ObservationEnrollmentVerifier());
            PrincipalCredential credential =
                credentials.IssueDeveloper(
                    new DeveloperEnrollmentEvidence
                    {
                        ClientInstanceId = ClientId,
                        EnrollmentReceipt =
                            "pixel-test-enrollment",
                        AllowedCapabilities =
                            new[] { "observe:pixels" },
                        AllowedTargets = new[] { TargetId }
                    });
            var grants = new ObservationGrantBroker(
                clock,
                credentials,
                targets);
            ObservationGrant grant = grants.Issue(
                new ObservationGrantRequest
                {
                    CredentialId = credential.CredentialId,
                    ClientInstanceId = ClientId,
                    SessionId = SessionId,
                    Targets = new[]
                    {
                        new ObservationTargetScope
                        {
                            TargetId = TargetId
                        }
                    },
                    DataScopes = new[] { "pixels" },
                    RequestedLifetime =
                        TimeSpan.FromMinutes(5)
                });
            var audit = new RecordingPixelAuditSink();
            var store = new PixelContentHandleStore(
                clock,
                grants,
                audit);
            return new Setup(
                clock,
                credential,
                grant,
                grants,
                audit,
                store,
                new PixelContentBinding
                {
                    ClientInstanceId = ClientId,
                    SecurityPrincipalId =
                        credential.SecurityPrincipalId,
                    SessionId = SessionId,
                    ObservationGrantId =
                        grant.ObservationGrantId,
                    ObservationId = ObservationId,
                    TargetId = TargetId,
                    DataScope = "pixels"
                });
        }

        private sealed class Setup : IDisposable
        {
            public Setup(
                ManualObservationClock clock,
                PrincipalCredential credential,
                ObservationGrant grant,
                ObservationGrantBroker grants,
                RecordingPixelAuditSink audit,
                PixelContentHandleStore store,
                PixelContentBinding binding)
            {
                Clock = clock;
                Credential = credential;
                Grant = grant;
                Grants = grants;
                Audit = audit;
                Store = store;
                Binding = binding;
            }

            public ManualObservationClock Clock { get; }
            public PrincipalCredential Credential { get; }
            public ObservationGrant Grant { get; }
            public ObservationGrantBroker Grants { get; }
            public RecordingPixelAuditSink Audit { get; }
            public PixelContentHandleStore Store { get; }
            public PixelContentBinding Binding { get; }

            public void Dispose()
            {
                Store.Dispose();
            }
        }

        private sealed class ToggleThrowingAuditSink
            : IPixelContentAuditSink
        {
            public bool Throw { get; set; }

            public void Record(PixelContentAuditEvent auditEvent)
            {
                if (Throw)
                    throw new InvalidOperationException(
                        "audit unavailable");
            }
        }
    }
}
