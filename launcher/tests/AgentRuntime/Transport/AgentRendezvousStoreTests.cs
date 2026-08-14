using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Transport;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Transport
{
    public sealed class AgentRendezvousStoreTests : IDisposable
    {
        private readonly string _temporaryRoot = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "cf7-agent-rendezvous-tests",
            Guid.NewGuid().ToString("N"));
        private readonly FakeClock _clock = new FakeClock(
            DateTimeOffset.Parse("2026-07-30T08:00:00Z"));
        private readonly FakeProcessProbe _processProbe =
            new FakeProcessProbe();
        private readonly RecordingProtection _protection =
            new RecordingProtection();

        [Fact]
        public void Path_IsFixedAndPartitionedByNormalizedProjectRootHash()
        {
            string first = AgentRendezvousPath.Resolve(
                @"C:\Games\CrazyFlashNight\",
                _temporaryRoot);
            string second = AgentRendezvousPath.Resolve(
                @"c:\games\crazyflashnight",
                _temporaryRoot);

            Assert.Equal(first, second);
            Assert.EndsWith(
                System.IO.Path.Combine("rendezvous.json"),
                first,
                StringComparison.OrdinalIgnoreCase);
            string projectHash = new DirectoryInfo(
                System.IO.Path.GetDirectoryName(first)).Name;
            Assert.Equal(64, projectHash.Length);
            Assert.All(
                projectHash,
                character => Assert.True(
                    (character >= '0' && character <= '9')
                    || (character >= 'a' && character <= 'f')));
            Assert.Contains(
                System.IO.Path.Combine(
                    "CF7FlashNight",
                    "agent-runtime",
                    "v1"),
                first,
                StringComparison.OrdinalIgnoreCase);
        }

        [Fact]
        public void Publish_WritesOnlyFrozenFields_AtomicallyAndProtected()
        {
            using AgentRendezvousStore store = CreateStore();
            AgentRendezvousOwner owner = CreateOwner("a");

            AgentRendezvousDocument published = store.Publish(
                owner,
                TimeSpan.FromSeconds(30));

            Assert.True(File.Exists(store.Path));
            Assert.Equal(
                _clock.UtcNow.AddSeconds(30),
                published.TicketExpiresUtc);
            Assert.Equal(43, published.ConnectionTicket.Length);
            using JsonDocument json =
                JsonDocument.Parse(File.ReadAllBytes(store.Path));
            string[] properties = json.RootElement
                .EnumerateObject()
                .Select(property => property.Name)
                .OrderBy(name => name, StringComparer.Ordinal)
                .ToArray();
            Assert.Equal(
                new[]
                {
                    "connectionTicket",
                    "launcherProcessId",
                    "launcherStartTimeUtc",
                    "lifecycleId",
                    "pipeId",
                    "protocolMaxMajor",
                    "protocolMinMajor",
                    "runtimeQualificationState",
                    "ticketExpiresUtc"
                },
                properties);
            Assert.Contains(
                System.IO.Path.GetDirectoryName(store.Path),
                _protection.ProtectedDirectories);
            Assert.Contains(store.Path, _protection.ProtectedFiles);
            Assert.DoesNotContain(
                Directory.EnumerateFiles(
                    System.IO.Path.GetDirectoryName(store.Path)),
                path => path.EndsWith(
                    ".tmp",
                    StringComparison.OrdinalIgnoreCase));
        }

        [Fact]
        public void Ticket_IsSingleUse_AndSuccessfulConsumeAtomicallyRotates()
        {
            using AgentRendezvousStore store = CreateStore();
            AgentRendezvousOwner owner = CreateOwner("b");
            AgentRendezvousDocument first = store.Publish(
                owner,
                TimeSpan.FromSeconds(30));

            Assert.True(
                store.TryConsumeAndRotate(
                    first.ConnectionTicket,
                    owner.LifecycleId,
                    out AgentRendezvousDocument rotated,
                    out string reason));
            Assert.Equal("accepted", reason);
            Assert.NotEqual(
                first.ConnectionTicket,
                rotated.ConnectionTicket);
            Assert.Equal(
                _clock.UtcNow.AddSeconds(30),
                rotated.TicketExpiresUtc);

            Assert.False(
                store.TryConsumeAndRotate(
                    first.ConnectionTicket,
                    owner.LifecycleId,
                    out AgentRendezvousDocument replay,
                    out string replayReason));
            Assert.Null(replay);
            Assert.Equal("ticket_mismatch", replayReason);

            Assert.True(
                store.TryConsumeAndRotate(
                    rotated.ConnectionTicket,
                    owner.LifecycleId,
                    out AgentRendezvousDocument next,
                    out string nextReason));
            Assert.Equal("accepted", nextReason);
            Assert.NotEqual(
                rotated.ConnectionTicket,
                next.ConnectionTicket);
        }

        [Fact]
        public void WrongTicket_DoesNotRotate()
        {
            using AgentRendezvousStore store = CreateStore();
            AgentRendezvousOwner owner = CreateOwner("c");
            AgentRendezvousDocument first = store.Publish(
                owner,
                TimeSpan.FromSeconds(30));

            Assert.False(
                store.TryConsumeAndRotate(
                    AgentRendezvousStore.GenerateOpaqueId(),
                    owner.LifecycleId,
                    out AgentRendezvousDocument ignored,
                    out string reason));
            Assert.Equal("ticket_mismatch", reason);

            Assert.True(
                store.TryConsumeAndRotate(
                    first.ConnectionTicket,
                    owner.LifecycleId,
                    out AgentRendezvousDocument rotated,
                    out string acceptedReason));
            Assert.Equal("accepted", acceptedReason);
            Assert.NotNull(rotated);
        }

        [Fact]
        public void ExpiredTicket_FailsClosed()
        {
            using AgentRendezvousStore store = CreateStore();
            AgentRendezvousOwner owner = CreateOwner("d");
            AgentRendezvousDocument first = store.Publish(
                owner,
                TimeSpan.FromSeconds(1));
            _clock.UtcNow = _clock.UtcNow.AddSeconds(1);

            Assert.False(
                store.TryConsumeAndRotate(
                    first.ConnectionTicket,
                    owner.LifecycleId,
                    out AgentRendezvousDocument ignored,
                    out string reason));
            Assert.Equal("ticket_expired", reason);
        }

        [Fact]
        public void ExactOwnerCanReplaceExpiredTicketWithoutAcceptingIt()
        {
            using AgentRendezvousStore store = CreateStore();
            AgentRendezvousOwner owner = CreateOwner("refresh");
            AgentRendezvousDocument expired = store.Publish(
                owner,
                TimeSpan.FromSeconds(1));
            _clock.UtcNow = _clock.UtcNow.AddSeconds(1);

            Assert.True(
                store.TryRotateOwnedTicket(
                    TimeSpan.FromSeconds(30),
                    out AgentRendezvousDocument refreshed,
                    out string refreshReason));
            Assert.Equal("refreshed", refreshReason);
            Assert.NotEqual(
                expired.ConnectionTicket,
                refreshed.ConnectionTicket);
            Assert.Equal(
                _clock.UtcNow.AddSeconds(30),
                refreshed.TicketExpiresUtc);

            Assert.False(
                store.TryConsumeAndRotate(
                    expired.ConnectionTicket,
                    owner.LifecycleId,
                    out _,
                    out string expiredReason));
            Assert.Equal("ticket_mismatch", expiredReason);
            Assert.True(
                store.TryConsumeAndRotate(
                    refreshed.ConnectionTicket,
                    owner.LifecycleId,
                    out _,
                    out string acceptedReason));
            Assert.Equal("accepted", acceptedReason);
        }

        [Fact]
        public void OwnedTicketRefreshRejectsForeignOrStaleState()
        {
            using AgentRendezvousStore store = CreateStore();
            AgentRendezvousOwner owner = CreateOwner("refresh-guard");
            store.Publish(owner, TimeSpan.FromSeconds(30));

            string original = File.ReadAllText(store.Path);
            using JsonDocument parsed = JsonDocument.Parse(original);
            var fields = parsed.RootElement
                .EnumerateObject()
                .ToDictionary(
                    property => property.Name,
                    property => property.Value.Clone(),
                    StringComparer.Ordinal);
            fields["pipeId"] = JsonDocument.Parse(
                "\"" + AgentRendezvousStore.GenerateOpaqueId() + "\"")
                .RootElement.Clone();
            File.WriteAllText(
                store.Path,
                JsonSerializer.Serialize(fields));

            Assert.False(
                store.TryRotateOwnedTicket(
                    TimeSpan.FromSeconds(30),
                    out _,
                    out string mismatchReason));
            Assert.Equal(
                "owned_rendezvous_mismatch",
                mismatchReason);
            Assert.Equal(
                File.ReadAllText(store.Path),
                JsonSerializer.Serialize(fields));

            File.WriteAllText(store.Path, original);
            _processProbe.Alive = false;
            Assert.False(
                store.TryRotateOwnedTicket(
                    TimeSpan.FromSeconds(30),
                    out _,
                    out string staleReason));
            Assert.Equal("owned_process_stale", staleReason);
        }

        [Fact]
        public void PidStartTimeAndLifecycleStaleness_FailClosed()
        {
            using AgentRendezvousStore store = CreateStore();
            AgentRendezvousOwner owner = CreateOwner("e");
            store.Publish(owner, TimeSpan.FromSeconds(30));

            Assert.False(
                store.TryReadFresh(
                    Opaque("other"),
                    out AgentRendezvousDocument wrongLifecycle,
                    out string lifecycleReason));
            Assert.Null(wrongLifecycle);
            Assert.Equal("lifecycle_stale", lifecycleReason);

            _processProbe.Alive = false;
            Assert.False(
                store.TryReadFresh(
                    owner.LifecycleId,
                    out AgentRendezvousDocument staleProcess,
                    out string processReason));
            Assert.Null(staleProcess);
            Assert.Equal("process_stale", processReason);
        }

        [Fact]
        public void MalformedOrExpandedDocument_FailsClosed()
        {
            using AgentRendezvousStore store = CreateStore();
            AgentRendezvousOwner owner = CreateOwner("f");
            store.Publish(owner, TimeSpan.FromSeconds(30));
            string expanded = File.ReadAllText(store.Path)
                .TrimEnd('}')
                + ",\"slot\":\"forbidden\"}";
            File.WriteAllText(store.Path, expanded);

            Assert.False(
                store.TryReadFresh(
                    owner.LifecycleId,
                    out AgentRendezvousDocument document,
                    out string reason));
            Assert.Null(document);
            Assert.Equal("rendezvous_malformed", reason);
        }

        [Fact]
        public void TicketTtlCannotExceedThirtySeconds()
        {
            using AgentRendezvousStore store = CreateStore();

            Assert.Throws<ArgumentOutOfRangeException>(
                () => store.Publish(
                    CreateOwner("g"),
                    TimeSpan.FromSeconds(30.001)));
            Assert.Throws<ArgumentOutOfRangeException>(
                () => store.Publish(
                    CreateOwner("g"),
                    TimeSpan.Zero));
            Assert.Throws<ArgumentOutOfRangeException>(
                () => store.TryRotateOwnedTicket(
                    TimeSpan.FromSeconds(30.001),
                    out _,
                    out _));
        }

        [Fact]
        public void Dispose_DeletesOnlyTheOwnedLifecycle()
        {
            AgentRendezvousStore first = CreateStore();
            AgentRendezvousOwner firstOwner = CreateOwner("h");
            first.Publish(firstOwner, TimeSpan.FromSeconds(30));
            Assert.True(File.Exists(first.Path));
            first.Dispose();
            Assert.False(File.Exists(first.Path));

            AgentRendezvousStore older = CreateStore();
            AgentRendezvousStore replacement = CreateStore();
            older.Publish(CreateOwner("i"), TimeSpan.FromSeconds(30));
            replacement.Publish(CreateOwner("j"), TimeSpan.FromSeconds(30));
            older.Dispose();
            Assert.True(File.Exists(replacement.Path));
            replacement.Dispose();
            Assert.False(File.Exists(replacement.Path));
        }

        [Fact]
        public void DefaultProtection_RestrictsFileToCurrentLogonSid()
        {
            using Process process = Process.GetCurrentProcess();
            var owner = new AgentRendezvousOwner(
                AgentRendezvousStore.GenerateOpaqueId(),
                process.Id,
                new DateTimeOffset(process.StartTime.ToUniversalTime()),
                AgentRendezvousStore.GenerateOpaqueId(),
                "unqualified_dev");
            using var store = new AgentRendezvousStore(
                @"C:\CF7\default-protection-test",
                _temporaryRoot,
                _clock,
                new SystemAgentRendezvousProcessProbe(),
                new WindowsCurrentUserRendezvousFileProtection());

            store.Publish(owner, TimeSpan.FromSeconds(5));

            FileSecurity security =
                new FileInfo(store.Path).GetAccessControl();
            AuthorizationRuleCollection rules = security.GetAccessRules(
                true,
                true,
                typeof(SecurityIdentifier));
            using WindowsIdentity currentIdentity = WindowsIdentity.GetCurrent();
            string currentSid = currentIdentity.User.Value;
            Assert.NotEmpty(rules.Cast<FileSystemAccessRule>());
            Assert.All(
                rules.Cast<FileSystemAccessRule>(),
                rule =>
                {
                    Assert.Equal(
                        AccessControlType.Allow,
                        rule.AccessControlType);
                    Assert.Equal(
                        currentSid,
                        rule.IdentityReference.Value);
                });
        }

        public void Dispose()
        {
            if (Directory.Exists(_temporaryRoot))
                Directory.Delete(_temporaryRoot, true);
        }

        private AgentRendezvousStore CreateStore()
        {
            return new AgentRendezvousStore(
                @"C:\Games\CrazyFlashNight",
                _temporaryRoot,
                _clock,
                _processProbe,
                _protection);
        }

        private static AgentRendezvousOwner CreateOwner(string marker)
        {
            return new AgentRendezvousOwner(
                Opaque("pipe-" + marker),
                4242,
                DateTimeOffset.Parse("2026-07-30T07:00:00Z"),
                Opaque("lifecycle-" + marker),
                "formal_runtime");
        }

        private static string Opaque(string prefix)
        {
            string sanitized = prefix.Replace("-", string.Empty);
            return (sanitized + new string('x', 43)).Substring(0, 43);
        }

        private sealed class FakeClock : IAgentRendezvousClock
        {
            public DateTimeOffset UtcNow { get; set; }

            public FakeClock(DateTimeOffset utcNow)
            {
                UtcNow = utcNow;
            }
        }

        private sealed class FakeProcessProbe : IAgentRendezvousProcessProbe
        {
            public bool Alive { get; set; } = true;

            public bool IsExactProcessAlive(
                int processId,
                DateTimeOffset expectedStartTimeUtc)
            {
                return Alive;
            }
        }

        private sealed class RecordingProtection
            : IAgentRendezvousFileProtection
        {
            public List<string> ProtectedDirectories { get; } =
                new List<string>();
            public List<string> ProtectedFiles { get; } =
                new List<string>();

            public void ProtectDirectory(string path)
            {
                ProtectedDirectories.Add(path);
            }

            public void ProtectFile(string path)
            {
                ProtectedFiles.Add(path);
            }
        }
    }
}
