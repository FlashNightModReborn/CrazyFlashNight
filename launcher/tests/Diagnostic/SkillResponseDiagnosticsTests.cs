using System;
using System.Collections.Generic;
using System.Linq;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Diagnostic
{
    public sealed class SkillResponseDiagnosticsTests
    {
        private static JObject Report(string call = "write.1", string stage = "dom_refresh_end") => new()
        {
            ["type"] = "skill_response_diag", ["panel"] = "skills", ["panelInstanceId"] = "panel.1",
            ["callId"] = call, ["cmd"] = "learnCommit", ["writeEpoch"] = 3, ["stage"] = stage, ["durationMs"] = 4.25
        };

        [Fact]
        public void CorrelatedStagesAreDeduplicatedRedactedAndTimedWithoutSharingClocks()
        {
            var lines = new List<string>(); double clock = 100;
            var trace = new SkillResponseDiagnostics(lines.Add, () => clock);
            var entry = trace.Begin("write.1", "panel.1", "learnCommit", 3);
            clock = 112; trace.Record(entry, "ui_dispatch_enter");
            clock = 120;
            Assert.True(trace.TryRecordWeb(Report(), "panel.1"));
            Assert.True(trace.TryRecordWeb(Report(), "panel.1"));
            Assert.Equal(3, lines.Count);
            Assert.Contains("hostElapsedMs=20.000 webDurationMs=4.250", lines.Last());
            Assert.DoesNotContain("write.1", string.Join("\n", lines));
            Assert.DoesNotContain("panel.1", string.Join("\n", lines));
        }

        [Theory]
        [InlineData("panelInstanceId", "foreign")]
        [InlineData("callId", "unknown")]
        [InlineData("cmd", "equip")]
        [InlineData("stage", "write_success")]
        [InlineData("type", "panel")]
        [InlineData("panel", "workbench")]
        public void UnknownOrForeignMetadataCannotClaimAResponseStage(string key, string value)
        {
            var lines = new List<string>(); var trace = new SkillResponseDiagnostics(lines.Add);
            trace.Begin("write.1", "panel.1", "learnCommit", 3);
            JObject report = Report(); report[key] = value;
            Assert.False(trace.TryRecordWeb(report, "panel.1"));
            Assert.Single(lines);
        }

        [Fact]
        public void StrictShapesAndInactiveOwnersDoNotLogPayloadOrAcknowledgeAnything()
        {
            var lines = new List<string>(); var trace = new SkillResponseDiagnostics(lines.Add);
            trace.Begin("write.1", "panel.1", "learnCommit", 3);
            foreach (JObject invalid in new[] {
                new JObject(Report()) { ["learnToken"] = "secret" },
                new JObject(Report()) { ["writeEpoch"] = 4 },
                new JObject(Report()) { ["durationMs"] = -1 },
                new JObject(Report()) { ["durationMs"] = double.NaN },
                new JObject(Report()) { ["durationMs"] = 600001 },
                new JObject(Report()) { ["type"] = new JObject() },
                new JObject(Report()) { ["callId"] = null } })
                Assert.False(trace.TryRecordWeb(invalid, "panel.1"));
            Assert.False(trace.TryRecordWeb(Report(), "replacement"));
            Assert.Single(lines);
        }

        [Fact]
        public void RetentionAndStageCardinalityAreBoundedAndOldEntriesCannotRevive()
        {
            var lines = new List<string>(); var trace = new SkillResponseDiagnostics(lines.Add);
            var oldest = trace.Begin("write.0", "panel.1", "learnCommit", 3);
            for (int i = 1; i <= 100; i++) trace.Begin("write." + i, "panel.1", "learnCommit", 3);
            Assert.Equal(64, trace.RetainedCount);
            Assert.False(trace.TryRecordWeb(Report("write.0"), "panel.1"));
            int count = lines.Count;
            trace.Record(oldest, "ui_dispatch_enter");
            trace.Record(oldest, "arbitrary_stage");
            Assert.Equal(count, lines.Count);
        }

        [Fact]
        public void BrokenLogSinkIsBestEffort()
        {
            var trace = new SkillResponseDiagnostics(_ => throw new InvalidOperationException("sink failed"));
            var entry = trace.Begin("write.1", "panel.1", "learnCommit", 3);
            trace.Record(entry, "web_post_begin");
            Assert.True(trace.TryRecordWeb(Report(), "panel.1"));
        }
    }
}
