using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using Xunit;

namespace CF7Launcher.Tests.Infrastructure
{
    public sealed class XunitRunnerPolicyTests
    {
        [Fact]
        public void OutputPolicyDisablesTestCollectionParallelism()
        {
            string path = Path.Combine(
                AppContext.BaseDirectory,
                "xunit.runner.json");
            Assert.True(
                File.Exists(path),
                "The canonical xUnit runner policy was not copied to the test output.");

            using JsonDocument document =
                JsonDocument.Parse(File.ReadAllText(path));
            Assert.Equal(
                3,
                document.RootElement
                    .EnumerateObject()
                    .Count());

            Assert.True(
                document.RootElement.TryGetProperty(
                    "$schema",
                    out JsonElement schema));
            Assert.Equal(
                JsonValueKind.String,
                schema.ValueKind);
            Assert.Equal(
                "https://xunit.net/schema/v2.8/xunit.runner.schema.json",
                schema.GetString());

            Assert.True(
                document.RootElement.TryGetProperty(
                    "diagnosticMessages",
                    out JsonElement diagnostics));
            Assert.Equal(
                JsonValueKind.True,
                diagnostics.ValueKind);

            Assert.True(
                document.RootElement.TryGetProperty(
                    "parallelizeTestCollections",
                    out JsonElement parallelize));
            Assert.Equal(
                JsonValueKind.False,
                parallelize.ValueKind);
        }
    }
}
