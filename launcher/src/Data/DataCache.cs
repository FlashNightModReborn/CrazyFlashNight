using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Data
{
    /// <summary>
    /// 线程安全的延迟加载缓存。
    /// DataQueryTask.HandleAsync 在 ThreadPool 中执行，并发请求可能同时 miss 缓存。
    /// 使用 double-checked locking 确保并发 miss 只触发一次 XML 解析。
    ///
    /// 失败处理：加载失败会缓存错误信息（不重试），调用方检查 error 后返回 success:false，
    /// Flash 端走 fallback legacy 路径。匹配 AS2 端 Promise.all 的全挂全回退语义。
    /// </summary>
    public class DataCache
    {
        private readonly string _projectRoot;

        private readonly object _npcLock = new object();
        private bool _npcAttempted;
        private Dictionary<string, List<DialogueGroup>> _npcDialogues;
        private string _npcError;   // non-null = 加载失败（永久缓存，不重试）

        private readonly object _mercLock = new object();
        private bool _mercAttempted;
        private JObject _mercBundle;
        private string _mercError;

        public DataCache(string projectRoot)
        {
            _projectRoot = projectRoot;
        }

        /// <summary>
        /// 获取 NPC 对话索引。首次调用同步解析所有 XML 并缓存。
        /// 加载失败时返回 null，错误信息通过 GetNpcError() 获取。
        /// 失败后不重试（缓存失败状态），Flash 端走 legacy fallback。
        /// </summary>
        public Dictionary<string, List<DialogueGroup>> GetNpcDialogues()
        {
            if (_npcAttempted) return _npcDialogues;
            lock (_npcLock)
            {
                if (_npcAttempted) return _npcDialogues;
                try
                {
                    _npcDialogues = XmlDataLoader.LoadNpcDialogues(_projectRoot);
                }
                catch (Exception ex)
                {
                    _npcError = ex.Message;
                    _npcDialogues = null;
                    LogManager.Log("[DataCache] NPC dialogue load FAILED: " + _npcError);
                }
                _npcAttempted = true;
                return _npcDialogues;
            }
        }

        public string GetNpcError() { return _npcError; }

        /// <summary>
        /// 获取佣兵 bundle。首次调用同步解析并缓存。
        /// 加载失败时返回 null，错误信息通过 GetMercError() 获取。
        /// </summary>
        public JObject GetMercBundle()
        {
            if (_mercAttempted) return _mercBundle;
            lock (_mercLock)
            {
                if (_mercAttempted) return _mercBundle;
                try
                {
                    _mercBundle = XmlDataLoader.LoadMercBundle(_projectRoot);
                }
                catch (Exception ex)
                {
                    _mercError = ex.Message;
                    _mercBundle = null;
                    LogManager.Log("[DataCache] Merc bundle load FAILED: " + _mercError);
                }
                _mercAttempted = true;
                return _mercBundle;
            }
        }

        public string GetMercError() { return _mercError; }
    }
}
