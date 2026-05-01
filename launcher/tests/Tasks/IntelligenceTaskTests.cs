using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class IntelligenceTaskTests : IDisposable
    {
        private readonly string _root;

        public IntelligenceTaskTests()
        {
            _root = Path.Combine(Path.GetTempPath(), "cf7-intel-task-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(_root, "data", "dictionaries"));
            Directory.CreateDirectory(Path.Combine(_root, "data", "intelligence"));
            Directory.CreateDirectory(Path.Combine(_root, "data", "items"));
        }

        public void Dispose()
        {
            try { if (Directory.Exists(_root)) Directory.Delete(_root, true); } catch { }
        }

        [Fact]
        public void CatalogAndSnapshot_ParseDictionaryTextAndUnlocks()
        {
            WriteDictionary(
                "<root>" +
                "  <Item>" +
                "    <Name>资料</Name><Index>0</Index>" +
                "    <EncryptReplace><A兵团>██</A兵团></EncryptReplace>" +
                "    <EncryptCut><秘密>--</秘密></EncryptCut>" +
                "    <Information Value=\"1\" PageKey=\"1\"/>" +
                "    <Information Value=\"5\" PageKey=\"5\" EncryptLevel=\"2\"/>" +
                "  </Item>" +
                "</root>");
            WriteText("资料", "@@@1@@@\n第一页\n@@@5@@@\nA兵团秘密文本");

            var posted = new List<string>();
            var task = new IntelligenceTask(_root);
            task.SetPostToWeb(delegate(string json) { posted.Add(json); });

            task.HandleWebRequest("catalog", JObject.Parse("{\"callId\":\"cat-1\"}"));
            JObject catalog = JObject.Parse(posted[0]);
            Assert.True((bool)catalog["success"]);
            Assert.Equal("资料", (string)catalog["items"][0]["name"]);
            Assert.Equal("资料", (string)catalog["items"][0]["iconName"]);
            Assert.Equal(5, (int)catalog["items"][0]["maxValue"]);
            Assert.Equal(2, (int)catalog["items"][0]["pageCount"]);

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"snap-1\",\"itemName\":\"资料\",\"value\":1,\"decryptLevel\":0,\"pcName\":\"测试\"}"));
            JObject snap = JObject.Parse(posted[1]);
            Assert.True((bool)snap["success"]);
            Assert.Equal("资料", (string)snap["name"]);
            Assert.True((bool)snap["pages"][0]["unlocked"]);
            Assert.False((bool)snap["pages"][1]["unlocked"]);
            Assert.Equal("第一页", (string)snap["pages"][0]["text"]);
            Assert.Equal("", (string)snap["pages"][1]["text"]);
            Assert.Equal("██", (string)snap["encryptRules"]["replace"]["A兵团"]);
            Assert.Equal("--", (string)snap["encryptRules"]["cut"]["秘密"]);
        }

        [Fact]
        public void Snapshot_UnknownAndTraversalItemNames_AreRejected()
        {
            WriteDictionary("<root><Item><Name>资料</Name><Index>0</Index><Information Value=\"1\" PageKey=\"1\"/></Item></root>");
            WriteText("资料", "@@@1@@@\n正文");

            var posted = new List<string>();
            var task = new IntelligenceTask(_root);
            task.SetPostToWeb(delegate(string json) { posted.Add(json); });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"bad-1\",\"itemName\":\"不存在\",\"value\":1}"));
            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"bad-2\",\"itemName\":\"../资料\",\"value\":1}"));

            Assert.Equal("unknown_item", (string)JObject.Parse(posted[0])["error"]);
            Assert.Equal("unknown_item", (string)JObject.Parse(posted[1])["error"]);
        }

        [Fact]
        public void Snapshot_MissingTextFile_ReturnsExplicitError()
        {
            WriteDictionary("<root><Item><Name>缺失文本</Name><Index>2</Index><Information Value=\"1\" PageKey=\"1\"/></Item></root>");

            string posted = null;
            var task = new IntelligenceTask(_root);
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"miss-1\",\"itemName\":\"缺失文本\",\"value\":1}"));

            JObject resp = JObject.Parse(posted);
            Assert.False((bool)resp["success"]);
            Assert.Equal("text_missing", (string)resp["error"]);
        }

        [Fact]
        public void Bundle_LoadsAllItemsWithTextAndMissingItemState()
        {
            WriteDictionary(
                "<root>" +
                "  <Item><Name>资料</Name><Index>0</Index><Information Value=\"1\" PageKey=\"1\"/><Information Value=\"5\" PageKey=\"5\"/></Item>" +
                "  <Item><Name>缺失文本</Name><Index>2</Index><Information Value=\"1\" PageKey=\"1\"/></Item>" +
                "</root>");
            WriteItemIcons("<root><item><name>资料</name><icon>资料图标</icon></item></root>");
            WriteText("资料", "@@@1@@@\n第一页\n@@@5@@@\n锁定页正文");

            string posted = null;
            var task = new IntelligenceTask(_root);
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("bundle", JObject.Parse("{\"callId\":\"bundle-1\",\"value\":1,\"decryptLevel\":0,\"pcName\":\"测试\"}"));

            JObject resp = JObject.Parse(posted);
            Assert.True((bool)resp["success"]);
            Assert.Equal("bundle", (string)resp["cmd"]);
            Assert.Equal(2, resp["items"].Count());

            JObject item = (JObject)resp["items"][0];
            Assert.Equal("资料", (string)item["name"]);
            Assert.Equal("资料图标", (string)item["iconName"]);
            Assert.True((bool)item["pages"][0]["unlocked"]);
            Assert.False((bool)item["pages"][1]["unlocked"]);
            Assert.Equal("第一页", (string)item["pages"][0]["text"]);
            Assert.Equal("锁定页正文", (string)item["pages"][1]["text"]);

            JObject missing = (JObject)resp["items"][1];
            Assert.Equal("缺失文本", (string)missing["name"]);
            Assert.Equal("text_missing", (string)missing["textError"]);
            Assert.Equal("", (string)missing["pages"][0]["text"]);
        }

        private void WriteDictionary(string xml)
        {
            File.WriteAllText(Path.Combine(_root, "data", "dictionaries", "information_dictionary.xml"), xml, Encoding.UTF8);
        }

        private void WriteText(string itemName, string content)
        {
            File.WriteAllText(Path.Combine(_root, "data", "intelligence", itemName + ".txt"), content, Encoding.UTF8);
        }

        private void WriteItemIcons(string xml)
        {
            File.WriteAllText(Path.Combine(_root, "data", "items", "收集品_情报.xml"), xml, Encoding.UTF8);
        }
    }
}
