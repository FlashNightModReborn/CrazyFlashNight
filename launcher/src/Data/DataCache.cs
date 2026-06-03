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

        // ===================== 非人形佣兵对话 =====================

        private readonly object _enemyDlgLock = new object();
        private bool _enemyDlgAttempted;
        private JObject _enemyDialogues;
        private string _enemyDlgError;

        public JObject GetEnemyDialogues()
        {
            if (_enemyDlgAttempted) return _enemyDialogues;
            lock (_enemyDlgLock)
            {
                if (_enemyDlgAttempted) return _enemyDialogues;
                try
                {
                    string path = System.IO.Path.Combine(_projectRoot, "data", "dialogues", "enemy_dialogues.xml");
                    _enemyDialogues = XmlDataLoader.LoadEnemyDialogues(path);
                }
                catch (Exception ex)
                {
                    _enemyDlgError = ex.Message;
                    _enemyDialogues = null;
                    LogManager.Log("[DataCache] Enemy dialogues load FAILED: " + _enemyDlgError);
                }
                _enemyDlgAttempted = true;
                return _enemyDialogues;
            }
        }

        public string GetEnemyDlgError() { return _enemyDlgError; }

        // ===================== 地图任务 NPC 注册表 =====================
        // SOT = launcher/web/modules/map-panel-data.js（build.ps1 Step 1b 派生）
        // 输出文件: data/map/task_npc_registry.json
        // AS2 端 MapTaskNpcRegistry.applyFromQuery 消费。

        private readonly object _taskNpcLock = new object();
        private bool _taskNpcAttempted;
        private JObject _taskNpcRegistry;
        private string _taskNpcError;

        public JObject GetTaskNpcRegistry()
        {
            if (_taskNpcAttempted) return _taskNpcRegistry;
            lock (_taskNpcLock)
            {
                if (_taskNpcAttempted) return _taskNpcRegistry;
                try
                {
                    _taskNpcRegistry = XmlDataLoader.LoadTaskNpcRegistry(_projectRoot);
                }
                catch (Exception ex)
                {
                    _taskNpcError = ex.Message;
                    _taskNpcRegistry = null;
                    LogManager.Log("[DataCache] task_npc_registry load FAILED: " + _taskNpcError);
                }
                _taskNpcAttempted = true;
                return _taskNpcRegistry;
            }
        }

        public string GetTaskNpcError() { return _taskNpcError; }

        // ===================== 地图 hotspot 拓扑目录 =====================
        // SOT = launcher/web/modules/map-panel-data.js（build.ps1 Step 1c 派生）
        // 输出文件: data/map/map_catalog.json
        // AS2 端 MapPanelCatalog.applyFromCatalogJson 消费（导航权威；失败不可静默降级）。

        private readonly object _mapCatalogLock = new object();
        private bool _mapCatalogAttempted;
        private JObject _mapCatalog;
        private string _mapCatalogError;

        public JObject GetMapCatalog()
        {
            if (_mapCatalogAttempted) return _mapCatalog;
            lock (_mapCatalogLock)
            {
                if (_mapCatalogAttempted) return _mapCatalog;
                try
                {
                    _mapCatalog = XmlDataLoader.LoadMapCatalog(_projectRoot);
                }
                catch (Exception ex)
                {
                    _mapCatalogError = ex.Message;
                    _mapCatalog = null;
                    LogManager.Log("[DataCache] map_catalog load FAILED: " + _mapCatalogError);
                }
                _mapCatalogAttempted = true;
                return _mapCatalog;
            }
        }

        public string GetMapCatalogError() { return _mapCatalogError; }
    }
}
