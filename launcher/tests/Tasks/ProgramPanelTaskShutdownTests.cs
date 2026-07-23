using System;
using System.IO;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class ProgramPanelTaskShutdownTests
    {
        [Fact]
        public void TransactionPanelTrackers_AreDisposedOnEveryShutdownPath()
        {
            string source = File.ReadAllText(FindProgramSource());
            string early = Slice(
                source,
                "form.OnShutdownEarly = delegate",
                "// 写端口文件");
            string busOnly = Slice(
                source,
                "// === bus-only 模式：仅运行通信总线，不启动 Flash Player ===",
                "// === 正常模式：启动 Flash Player 并嵌入 ===");
            string normal = Slice(
                source,
                "Application.Run(ctx);",
                "StartupDiagnostics.Mark(\"guardian.shutdown_complete\");");

            AssertShutdownOrder(early);
            AssertShutdownOrder(busOnly);
            AssertShutdownOrder(normal);
            Assert.Equal(3, CountOccurrences(source, "npcShopTask.Dispose();"));
            Assert.Equal(3, CountOccurrences(source, "craftingTask.Dispose();"));
            Assert.Equal(3, CountOccurrences(source, "hairdresserTask.Dispose();"));
        }

        [Fact]
        public void HairdresserTrackedClose_ClearsPendingAtPanelHostObserver()
        {
            string source = File.ReadAllText(FindProgramSource());
            string observer = Slice(
                source,
                "panelHost.SetPanelCloseObserver(delegate",
                "skillTask.SetCoordinatorSettled");

            const string clear =
                "if (panelName == \"hairdresser\") hairdresserTask.ClearPending();";
            Assert.Contains(clear, observer);
            Assert.Equal(1, CountOccurrences(observer, "hairdresserTask.ClearPending();"));
        }

        private static void AssertShutdownOrder(string block)
        {
            const string npcShopDispose = "npcShopTask.Dispose();";
            const string craftingDispose = "craftingTask.Dispose();";
            const string hairdresserDispose = "hairdresserTask.Dispose();";
            int npcShopIndex = block.IndexOf(npcShopDispose, StringComparison.Ordinal);
            int craftingIndex = block.IndexOf(craftingDispose, StringComparison.Ordinal);
            int hairdresserIndex = block.IndexOf(hairdresserDispose, StringComparison.Ordinal);

            Assert.True(npcShopIndex >= 0, "NpcShopTask must be disposed in this shutdown path.");
            Assert.True(craftingIndex >= 0, "CraftingTask must be disposed in this shutdown path.");
            Assert.True(hairdresserIndex >= 0, "HairdresserTask must be disposed in this shutdown path.");
            Assert.True(
                npcShopIndex < craftingIndex && craftingIndex < hairdresserIndex,
                "Transaction panel tasks must keep their declared shutdown order.");
            Assert.Equal(1, CountOccurrences(block, npcShopDispose));
            Assert.Equal(1, CountOccurrences(block, craftingDispose));
            Assert.Equal(1, CountOccurrences(block, hairdresserDispose));
        }

        private static string Slice(string source, string startMarker, string endMarker)
        {
            int start = source.IndexOf(startMarker, StringComparison.Ordinal);
            Assert.True(start >= 0, "Missing Program.cs start marker: " + startMarker);
            int end = source.IndexOf(endMarker, start, StringComparison.Ordinal);
            Assert.True(end > start, "Missing Program.cs end marker: " + endMarker);
            return source.Substring(start, end - start);
        }

        private static int CountOccurrences(string source, string value)
        {
            int count = 0;
            int offset = 0;
            while ((offset = source.IndexOf(value, offset, StringComparison.Ordinal)) >= 0)
            {
                count++;
                offset += value.Length;
            }
            return count;
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

                string fromLauncher = Path.Combine(current.FullName, "src", "Program.cs");
                if (File.Exists(fromLauncher))
                    return fromLauncher;

                current = current.Parent;
            }

            throw new FileNotFoundException("Unable to locate launcher/src/Program.cs.");
        }
    }
}
