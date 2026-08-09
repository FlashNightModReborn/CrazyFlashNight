using System;
using System.IO;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class ProgramAudioLifecycleTests
    {
        [Fact]
        public void AudioRoutes_AreInstalledBeforeSocketExposureAndReadyReplay()
        {
            string source = File.ReadAllText(FindProgramSource());

            AssertInOrder(
                source,
                "MessageRouter router = new MessageRouter();",
                "AudioTask audioTask = new CF7Launcher.Tasks.AudioTask(",
                "TaskRegistry.RegisterAudioV2(router, audioTask);",
                "XmlSocketServer socketServer = new XmlSocketServer(",
                "socketServer.Start(socketPort)",
                "new CF7Launcher.Audio.AudioSocketPublisherV2(");
        }

        [Theory]
        [InlineData(
            "if (socketPort < 0 || !socketStarted)",
            "StartupDiagnostics.Mark(\"socket.start_ok\"")]
        [InlineData(
            "if (httpPort < 0 || !httpStarted)",
            "StartupDiagnostics.Mark(\"http.start_ok\"")]
        public void NetworkStartFailure_ShutsDownScheduledAudioBeforeReturn(
            string startMarker,
            string endMarker)
        {
            string source = File.ReadAllText(FindProgramSource());
            string failureBranch = Slice(source, startMarker, endMarker);

            AssertInOrder(
                failureBranch,
                "AudioEngine.Shutdown()",
                "musicCatalog.Dispose()",
                "return 1;");
        }

        private static void AssertInOrder(
            string source,
            params string[] markers)
        {
            int previous = -1;
            foreach (string marker in markers)
            {
                int found = source.IndexOf(
                    marker,
                    previous + 1,
                    StringComparison.Ordinal);
                Assert.True(found > previous, "Missing or out-of-order marker: " + marker);
                previous = found;
            }
        }

        private static string Slice(
            string source,
            string startMarker,
            string endMarker)
        {
            int start = source.IndexOf(startMarker, StringComparison.Ordinal);
            Assert.True(start >= 0, "Missing start marker: " + startMarker);
            int end = source.IndexOf(endMarker, start, StringComparison.Ordinal);
            Assert.True(end > start, "Missing end marker: " + endMarker);
            return source.Substring(start, end - start);
        }

        private static string FindProgramSource()
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string fromRepository = Path.Combine(
                    current.FullName,
                    "launcher",
                    "src",
                    "Program.cs");
                if (File.Exists(fromRepository))
                    return fromRepository;

                string fromLauncher = Path.Combine(
                    current.FullName,
                    "src",
                    "Program.cs");
                if (File.Exists(fromLauncher))
                    return fromLauncher;

                current = current.Parent;
            }

            throw new FileNotFoundException(
                "Unable to locate launcher/src/Program.cs.");
        }
    }
}
