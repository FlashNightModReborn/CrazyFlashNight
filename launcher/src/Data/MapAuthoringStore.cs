using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>单定义文件事务；CLI 和 Host 共用同一互斥、摘要与撤回实现。</summary>
    public sealed class MapAuthoringStore
    {
        private readonly string root, file, history;
        public MapAuthoringStore(string projectRoot)
        {
            root = Path.GetFullPath(projectRoot);
            file = Path.Combine(root, MapDefinition.RelativePath);
            history = Path.Combine(root, "tmp", "map-workbench", "changes");
        }
        private static void PlainPath(string path)
        {
            for (string p = Path.GetFullPath(path); p != null; p = Path.GetDirectoryName(p))
                if ((Directory.Exists(p) || File.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("地图写入路径不能经过链接目录。");
        }
        private static void Atomic(string target, byte[] bytes)
        {
            PlainPath(target);
            Directory.CreateDirectory(Path.GetDirectoryName(target));
            string temp = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes); stream.Flush(true); }
                if (File.Exists(target)) File.Replace(temp, target, null); else File.Move(temp, target);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        public JObject Read()
        {
            byte[] bytes = File.ReadAllBytes(file);
            var recent = new JArray();
            if (Directory.Exists(history)) foreach (var path in Directory.EnumerateFiles(history, "*.json").OrderByDescending(File.GetLastWriteTimeUtc).Take(12))
            {
                var receipt = JObject.Parse(File.ReadAllText(path));
                recent.Add(new JObject { ["operationId"] = receipt["operationId"], ["afterDigest"] = receipt["afterDigest"], ["createdAt"] = receipt["createdAt"] });
            }
            return new JObject { ["definition"] = MapDefinition.Parse(bytes), ["digest"] = MapDefinition.Hash(bytes), ["recent"] = recent };
        }
        public JObject Execute(JObject request)
        {
            string op = request.Value<string>("op");
            if (op == "read") return Read();
            if (op == "preview")
            {
                var current = Read();
                CheckDigest(current.Value<string>("digest"), request.Value<string>("expectedDigest"));
                current["definition"] = MapDefinition.Edit((JObject)current["definition"], request["changes"] as JArray);
                current["preview"] = true;
                return current;
            }
            string id = request.Value<string>("operationId");
            if (id == null || !Regex.IsMatch(id, "\\A[a-f0-9]{32}\\z")) throw new InvalidDataException("操作编号不合法。");
            string receiptPath = Path.Combine(history, id + ".json");
            if (op == "query") return Query(receiptPath);
            if (op != "apply" && op != "undo") throw new InvalidDataException("未知地图操作。");
            PlainPath(file); PlainPath(receiptPath);
            using var mutex = new Mutex(false, "Local\\CF7MapAuthoring-" + MapDefinition.Hash(MapDefinition.Utf8.GetBytes(root.ToUpperInvariant())));
            bool owned = false;
            try
            {
                try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
                if (!owned) throw new IOException("另一个地图操作正在保存，请稍后重试。");
                byte[] before = File.ReadAllBytes(file);
                if (op == "undo")
                {
                    var receipt = JObject.Parse(File.ReadAllText(receiptPath));
                    if (MapDefinition.Hash(before) == receipt.Value<string>("beforeDigest")) return Query(receiptPath);
                    CheckDigest(MapDefinition.Hash(before), receipt.Value<string>("afterDigest"));
                    byte[] restore = Convert.FromBase64String(receipt.Value<string>("beforeBytes"));
                    if (MapDefinition.Hash(restore) != receipt.Value<string>("beforeDigest")) throw new InvalidDataException("撤回备份摘要不匹配。");
                    MapDefinition.Parse(restore); Atomic(file, restore);
                    return Query(receiptPath);
                }
                var changes = request["changes"] as JArray;
                string binding = MapDefinition.Hash(MapDefinition.Bytes(new JObject { ["expectedDigest"] = request["expectedDigest"], ["changes"] = changes }));
                if (File.Exists(receiptPath))
                {
                    var previous = JObject.Parse(File.ReadAllText(receiptPath));
                    if (previous.Value<string>("binding") != binding) throw new InvalidDataException("同一操作编号不能用于不同修改。");
                    return Query(receiptPath);
                }
                CheckDigest(MapDefinition.Hash(before), request.Value<string>("expectedDigest"));
                byte[] after = MapDefinition.Bytes(MapDefinition.Edit(MapDefinition.Parse(before), changes));
                var record = new JObject { ["operationId"] = id, ["binding"] = binding, ["beforeDigest"] = MapDefinition.Hash(before), ["afterDigest"] = MapDefinition.Hash(after),
                    ["beforeBytes"] = Convert.ToBase64String(before), ["createdAt"] = DateTime.UtcNow.ToString("O") };
                // 备份先 durable；中断后的 query 直接对账文件内容，不猜测或自动重放。
                Atomic(receiptPath, MapDefinition.Bytes(record));
                CheckDigest(MapDefinition.Hash(File.ReadAllBytes(file)), record.Value<string>("beforeDigest"));
                Atomic(file, after);
                return Query(receiptPath);
            }
            finally { if (owned) mutex.ReleaseMutex(); }
        }
        private JObject Query(string receiptPath)
        {
            if (!File.Exists(receiptPath)) return new JObject { ["state"] = "not_found" };
            var receipt = JObject.Parse(File.ReadAllText(receiptPath));
            var current = Read(); string digest = current.Value<string>("digest");
            current["operationId"] = receipt["operationId"];
            current["state"] = digest == receipt.Value<string>("afterDigest") ? "applied" : digest == receipt.Value<string>("beforeDigest") ? "original" : "superseded";
            return current;
        }
        private static void CheckDigest(string actual, string expected)
        {
            if (string.IsNullOrEmpty(expected) || !string.Equals(actual, expected, StringComparison.Ordinal))
                throw new IOException("地图配置已被修改，请重新读取；当前草稿保留供对比。撤回不会覆盖后续修改。");
        }
    }
}
