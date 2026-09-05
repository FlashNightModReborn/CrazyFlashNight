using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using CF7Launcher.Bus;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class WarlordRuntimeHostContractTests
    {
        [Fact]
        public void Prepare_AcceptsEnvelopeGeneratedFromTheCurrentDemo2Runtime()
        {
            string projectRoot = FindProjectRoot();
            JObject envelope = ExportRuntimeEnvelope(projectRoot);
            var task = new WarlordBattleTask(
                (XmlSocketServer)null,
                projectRoot);

            WarlordBattleTask.PreparedBattle prepared;
            JObject result = task.Prepare(
                envelope,
                envelope.Value<string>("panelInstanceId"),
                "run.demo2.live-contract",
                out prepared);

            Assert.True(
                result.Value<bool>("success"),
                result.Value<string>("error") + ": "
                    + result.Value<string>("message"));
            Assert.NotNull(prepared);
            Assert.Equal(
                "warlord.action-encounter-control.v2",
                prepared.ActionEncounterControl.Value<string>("schema"));
            Assert.True(task.CancelPrepared(prepared, "test_complete"));
        }

        private static JObject ExportRuntimeEnvelope(string projectRoot)
        {
            string script = Path.Combine(
                projectRoot,
                "launcher",
                "web",
                "modules",
                "minigames",
                "warlord",
                "tools",
                "export-demo2-host-contract.mjs");
            var start = new ProcessStartInfo
            {
                FileName = ResolveNodeExecutable(),
                WorkingDirectory = projectRoot,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            start.ArgumentList.Add(script);
            using Process process = Process.Start(start)
                ?? throw new InvalidOperationException("Unable to start Node contract exporter.");
            string output = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();
            Assert.True(
                process.WaitForExit(15_000),
                "Demo2 runtime contract exporter timed out.");
            Assert.Equal(0, process.ExitCode);
            Assert.True(
                string.IsNullOrWhiteSpace(error),
                "Demo2 runtime contract exporter stderr: " + error);
            return JObject.Parse(output);
        }

        private static string ResolveNodeExecutable()
        {
            string configured = Environment.GetEnvironmentVariable("CF7_NODE_EXE");
            return string.IsNullOrWhiteSpace(configured) ? "node.exe" : configured;
        }

        private static string FindProjectRoot()
        {
            foreach (string start in new[]
            {
                Environment.CurrentDirectory,
                AppContext.BaseDirectory
            })
            {
                DirectoryInfo directory = new DirectoryInfo(start);
                while (directory != null)
                {
                    if (File.Exists(Path.Combine(
                            directory.FullName,
                            "data",
                            "merc",
                            "pets.xml"))
                        && File.Exists(Path.Combine(
                            directory.FullName,
                            "launcher",
                            "CRAZYFLASHER7MercenaryEmpire.csproj")))
                    {
                        return directory.FullName;
                    }
                    directory = directory.Parent;
                }
            }
            throw new DirectoryNotFoundException(
                "Cannot locate the CF7 project root for the Warlord runtime contract test.");
        }
    }
}
