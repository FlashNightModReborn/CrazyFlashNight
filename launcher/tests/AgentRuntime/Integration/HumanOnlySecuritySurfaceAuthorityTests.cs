using System;
using System.Collections.Generic;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Integration;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class
        HumanOnlySecuritySurfaceAuthorityTests
    {
        [Fact]
        public void NestedScopesPublishOneLatchAndOneClear()
        {
            var changes =
                new List<BlockingModalKind>();
            using var authority =
                new HumanOnlySecuritySurfaceAuthority(
                    changes.Add);

            IDisposable first = authority.Enter();
            IDisposable second = authority.Enter();
            first.Dispose();
            Assert.Equal(
                new[]
                {
                    BlockingModalKind
                        .HumanOnlySecurity
                },
                changes);

            second.Dispose();
            second.Dispose();
            Assert.Equal(
                new[]
                {
                    BlockingModalKind
                        .HumanOnlySecurity,
                    BlockingModalKind.None
                },
                changes);
        }

        [Fact]
        public void AuthorityDisposeClearsAnOpenScopeOnce()
        {
            var changes =
                new List<BlockingModalKind>();
            var authority =
                new HumanOnlySecuritySurfaceAuthority(
                    changes.Add);
            IDisposable scope = authority.Enter();

            authority.Dispose();
            scope.Dispose();

            Assert.Equal(
                new[]
                {
                    BlockingModalKind
                        .HumanOnlySecurity,
                    BlockingModalKind.None
                },
                changes);
            Assert.Throws<ObjectDisposedException>(
                authority.Enter);
        }
    }
}
