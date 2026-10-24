using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using CF7Launcher.Data;
using Newtonsoft.Json;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class MapTaskCatalogOptionalSourceTests : IDisposable
    {
        private const string AgentTasks = "data/task/agent_tasks.json";
        private const string AgentText = "data/task/text/agent_text.json";
        private readonly string root = Path.Combine(Path.GetTempPath(), "cf7-map-optional-test-" + Guid.NewGuid().ToString("N"));

        public MapTaskCatalogOptionalSourceTests()
        {
            Put("data/infrastructure/infrastructure.xml", "<root><Infrastructure><Name>自行车</Name><Level/><Level/></Infrastructure></root>");
            Put("data/task/list.xml", "<root><task>required.json</task><task>agent_tasks.json</task></root>");
            Put("data/task/text/list.xml", "<root><text>required.json</text><text>agent_text.json</text></root>");
            Put("data/task/required.json", "{\"tasks\":[{\"id\":1,\"title\":\"基础任务\"}]}");
            Put("data/task/text/required.json", "{\"$BASE\":\"基础文本\"}");
        }

        private string PathFor(string file) => Path.Combine(root, file.Replace('/', Path.DirectorySeparatorChar));
        private void Put(string file, string text)
        {
            string path = PathFor(file);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, text, new UTF8Encoding(false));
        }
        private static string ValidContent(string file) => file == AgentTasks
            ? "{\"tasks\":[{\"id\":200001,\"title\":\"委托\"}]}" : "{\"$AGENT\":\"委托文本\"}";

        [Theory]
        [InlineData(false, false)]
        [InlineData(true, false)]
        [InlineData(false, true)]
        public void RegisteredLegacyFilesMayBeAbsentWithoutInventingSourceBytes(bool tasksPresent, bool textPresent)
        {
            if (tasksPresent) Put(AgentTasks, ValidContent(AgentTasks));
            if (textPresent) Put(AgentText, ValidContent(AgentText));
            var catalog = MapTaskCatalog.Load(root);
            Assert.Equal("基础任务", (string)catalog.Tasks["1"]["title"]);
            Assert.Equal("基础文本", (string)catalog.Texts["$BASE"]);
            Assert.Equal(tasksPresent, catalog.SourceBytes.ContainsKey(AgentTasks));
            Assert.Equal(textPresent, catalog.SourceBytes.ContainsKey(AgentText));
            Assert.Equal(tasksPresent, File.Exists(PathFor(AgentTasks)));
            Assert.Equal(textPresent, File.Exists(PathFor(AgentText)));
        }

        [Theory]
        [InlineData("data/task/required.json")]
        [InlineData("data/task/text/required.json")]
        public void MissingSharedSourceStillFails(string file)
        {
            File.Delete(PathFor(file));
            Assert.Throws<FileNotFoundException>(() => MapTaskCatalog.Load(root));
        }

        [Theory]
        [InlineData(AgentTasks)]
        [InlineData(AgentText)]
        public void ExistingMalformedLegacySourceStillFails(string file)
        {
            Put(file, "{\"broken\":");
            Assert.ThrowsAny<JsonException>(() => MapTaskCatalog.Load(root));
        }

        [Theory]
        [InlineData(AgentTasks)]
        [InlineData(AgentText)]
        public void ASourceCreatedLaterChangesDigestAndAppearsInChangedSources(string file)
        {
            var before = MapTaskCatalog.Load(root);
            Put(file, ValidContent(file));
            var after = MapTaskCatalog.Load(root);
            Assert.NotEqual(before.Digest, after.Digest);
            Assert.Equal(new[] { file }, MapTaskCatalog.ChangedSources(before, after));
            Assert.Equal(File.ReadAllBytes(PathFor(file)), after.SourceBytes[file]);
            if (file == AgentTasks) Assert.Equal(file, after.TaskFiles["200001"]);
            else Assert.Equal("委托文本", (string)after.Texts["$AGENT"]);
        }

        [Theory]
        [InlineData(AgentTasks)]
        [InlineData(AgentText)]
        public void LockedExistingLegacySourceIsNotTreatedAsMissing(string file)
        {
            Put(file, ValidContent(file));
            using var held = new FileStream(PathFor(file), FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            Assert.ThrowsAny<IOException>(() => MapTaskCatalog.Load(root));
        }

        [Theory]
        [InlineData(AgentTasks)]
        [InlineData(AgentText)]
        public void ExplicitOverrideIsLoadedEvenWhenDiskSourceIsAbsent(string file)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(ValidContent(file));
            var catalog = MapTaskCatalog.Load(root, new Dictionary<string, byte[]> { [file] = bytes });
            Assert.Equal(bytes, catalog.SourceBytes[file]);
            Assert.False(File.Exists(PathFor(file)));
        }

        [Fact]
        public void DuplicateMissingLegacyEntryStillFails()
        {
            Put("data/task/list.xml", "<root><task>agent_tasks.json</task><task>agent_tasks.json</task></root>");
            Assert.Throws<InvalidDataException>(() => MapTaskCatalog.Load(root));
        }

        public void Dispose() { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}
