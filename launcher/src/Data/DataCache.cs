using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>
    /// 线程安全的延迟加载缓存。
    /// DataQueryTask.HandleAsync 在 ThreadPool 中执行，并发请求可能同时 miss 缓存。
    /// 使用 double-checked locking 确保并发 miss 只触发一次 XML 解析。
    /// </summary>
    public class DataCache
    {
        private readonly string _projectRoot;
        private readonly object _npcLock = new object();
        private readonly object _mercLock = new object();
        private Dictionary<string, List<DialogueGroup>> _npcDialogues;  // null = 未加载
        private JObject _mercBundle;                                     // null = 未加载

        public DataCache(string projectRoot)
        {
            _projectRoot = projectRoot;
        }

        /// <summary>
        /// 获取 NPC 对话索引（按 NPC 名分组）。首次调用同步解析所有 XML 并缓存。
        /// </summary>
        public Dictionary<string, List<DialogueGroup>> GetNpcDialogues()
        {
            if (_npcDialogues != null) return _npcDialogues;
            lock (_npcLock)
            {
                if (_npcDialogues != null) return _npcDialogues;
                _npcDialogues = XmlDataLoader.LoadNpcDialogues(_projectRoot);
                return _npcDialogues;
            }
        }

        /// <summary>
        /// 获取佣兵 bundle。首次调用同步解析并缓存。
        /// </summary>
        public JObject GetMercBundle()
        {
            if (_mercBundle != null) return _mercBundle;
            lock (_mercLock)
            {
                if (_mercBundle != null) return _mercBundle;
                _mercBundle = XmlDataLoader.LoadMercBundle(_projectRoot);
                return _mercBundle;
            }
        }
    }
}
