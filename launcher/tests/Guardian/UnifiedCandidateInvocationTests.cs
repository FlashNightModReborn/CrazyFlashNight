using System;
using CF7Launcher.Guardian.UnifiedHost;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class UnifiedCandidateInvocationTests
{
    private static string[] Args(string profile = "c1") => new[] {
        "--project-root", @"C:\cf7", UnifiedCandidateInvocation.Flag, profile, "--evidence", @"C:\cf7\tmp\run"
    };
    [Fact] public void FormalOrUnverifiedRuntimeCannotEnterUnifiedCandidate() =>
        Assert.Throws<InvalidOperationException>(() => UnifiedCandidateInvocation.Parse(Args(), false));
    [Fact] public void UnimplementedBaseProfileCannotMasqueradeAsReady() =>
        Assert.Throws<ArgumentException>(() => UnifiedCandidateInvocation.Parse(Args("b1"), true));
    [Fact] public void DiagnosticInjectionIsClosedUnlessExplicitlySelected()
    {
        Assert.False(UnifiedCandidateInvocation.Parse(Args(), true).DiagnosticCommands);
        var args = new System.Collections.Generic.List<string>(Args()) { "--diagnostic-input" };
        Assert.True(UnifiedCandidateInvocation.Parse(args.ToArray(), true).DiagnosticCommands);
    }
    [Theory] [InlineData("--unified-input-candidate=wrong")] [InlineData("--UNIFIED-INPUT-CANDIDATE")]
    public void MalformedFlagIsRejectedInsteadOfFallingThroughToNormalGame(string flag)
    {
        Assert.True(UnifiedCandidateInvocation.IsRequested(new[] { flag }));
        Assert.Throws<ArgumentException>(() => UnifiedCandidateInvocation.Parse(new[] { flag }, true));
    }
    [Fact] public void MixedNormalGameAndDuplicateArgumentsAreRejected()
    {
        var args = new System.Collections.Generic.List<string>(Args()) { "--bus-only" };
        Assert.Throws<ArgumentException>(() => UnifiedCandidateInvocation.Parse(args.ToArray(), true));
        args.RemoveAt(args.Count - 1); args.Add("--project-root"); args.Add(@"C:\another");
        Assert.Throws<ArgumentException>(() => UnifiedCandidateInvocation.Parse(args.ToArray(), true));
    }
}
