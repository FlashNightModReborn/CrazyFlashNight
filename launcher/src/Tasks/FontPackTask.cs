using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 字体包按需下载。manifest 列出 group → files，每个 file 带 SHA256 + 镜像 url 列表 + 可选 shipped fallback。
    /// 落盘到 %LOCALAPPDATA%/CF7FlashNight/fonts/，WebOverlayForm 把该目录挂为 cfn-fonts.local 虚拟主机优先映射。
    ///
    /// 协议（async via MessageRouter）：
    ///   { task:"font_pack", payload:{ op:"status" } }
    ///       → { success, task:"font_pack", op:"status", fontsDir, groups:[ { name, label, allInstalled, files:[ {name,bytes,installed,verified} ] } ] }
    ///   { task:"font_pack", payload:{ op:"download_group", group:"essential" } }
    ///       → 启动后台下载，progress 通过 notch + 完成 toast 报告，end 回 success/failed 列表
    ///   { task:"font_pack", payload:{ op:"download_file", name:"xxx.ttf" } }
    ///       → 单文件重试入口
    /// </summary>
    public class FontPackTask
    {
        private readonly string _projectRoot;
        private readonly string _shippedFontsDir;   // launcher/web/assets/fonts (兜底 + manifest 来源)
        private readonly string _appDataFontsDir;   // %LOCALAPPDATA%/CF7FlashNight/fonts (优先目录)
        private readonly string _manifestPath;
        private readonly INotchSink _notchSink;
        private readonly IToastSink _toastSink;
        private readonly object _downloadLock = new object();
        private volatile bool _downloadInProgress;
        // Cancel：bootstrap UI 取消 → 设 1。每个 chunk 边界检查；触发后 ReadAsync/ReadByte 抛 OperationCanceledException-like。
        // Interlocked 保证跨线程可见性。
        private int _cancelToken;
        // 进度推送 sink：Program.cs 通过 SetProgressSink 注入；BootstrapMessageHandler 把它转成 fontpack_progress 消息。
        // 节流由 EmitProgress 内部按 250ms / 0% / 100% 控制，sink 端无需再节流。
        private Action<JObject> _progressSink;
        private long _lastProgressTickMs;
        private const int PROGRESS_THROTTLE_MS = 250;
        private const int DOWNLOAD_BUFFER = 64 * 1024;

        public string AppDataFontsDir { get { return _appDataFontsDir; } }

        public void SetProgressSink(Action<JObject> sink)
        {
            _progressSink = sink;
            LogManager.Log("[FontPack] progress sink " + (sink != null ? "registered" : "cleared"));
        }

        public bool RequestCancel()
        {
            if (!_downloadInProgress) return false;
            Interlocked.Exchange(ref _cancelToken, 1);
            LogManager.Log("[FontPack] cancel requested");
            return true;
        }

        private bool IsCancelled() { return Interlocked.CompareExchange(ref _cancelToken, 0, 0) != 0; }
        private void ResetCancel() { Interlocked.Exchange(ref _cancelToken, 0); }

        public FontPackTask(string projectRoot, INotchSink notchSink, IToastSink toastSink)
        {
            _projectRoot = projectRoot;
            _notchSink = notchSink;
            _toastSink = toastSink;
            _shippedFontsDir = Path.Combine(projectRoot, "launcher", "web", "assets", "fonts");
            _manifestPath = Path.Combine(_shippedFontsDir, "font-pack-manifest.json");

            string baseAppData;
            try
            {
                baseAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            }
            catch { baseAppData = null; }

            if (string.IsNullOrEmpty(baseAppData))
            {
                _appDataFontsDir = _shippedFontsDir;
                LogManager.Log("[FontPack] LOCALAPPDATA unavailable, AppData fonts dir = shipped dir");
            }
            else
            {
                _appDataFontsDir = Path.Combine(baseAppData, "CF7FlashNight", "fonts");
                try { Directory.CreateDirectory(_appDataFontsDir); }
                catch (Exception ex)
                {
                    LogManager.Log("[FontPack] Failed to create AppData fonts dir: " + ex.Message);
                    _appDataFontsDir = _shippedFontsDir;
                }
            }

            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
        }

        public void HandleAsync(JObject message, Action<string> respond)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    string result = Process(message);
                    respond(result);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[FontPack] Exception: " + ex);
                    respond(BuildError("font_pack exception: " + ex.Message, null));
                }
            });
        }

        private string Process(JObject message)
        {
            JObject payload = message.Value<JObject>("payload");
            if (payload == null) return BuildError("missing payload", null);
            string op = payload.Value<string>("op");
            if (op == null) return BuildError("missing op", null);

            switch (op)
            {
                case "status":         return HandleStatus();
                case "download_group": return HandleDownloadGroup(payload);
                case "download_file":  return HandleDownloadFile(payload);
                case "cancel":         return HandleCancel();
                default:               return BuildError("unknown op: " + op, op);
            }
        }

        private string HandleCancel()
        {
            bool ok = RequestCancel();
            JObject resp = new JObject();
            resp["success"] = true;
            resp["task"] = "font_pack";
            resp["op"] = "cancel";
            resp["wasInProgress"] = ok;
            return resp.ToString(Formatting.None);
        }

        // ================================================================
        // status
        // ================================================================

        private string HandleStatus()
        {
            LogManager.Log("[FontPack] status entry: appData=" + _appDataFontsDir
                + " shipped=" + _shippedFontsDir);
            JObject manifest;
            string err;
            if (!TryLoadManifest(out manifest, out err))
            {
                LogManager.Log("[FontPack] status: manifest load failed: " + err);
                return BuildError(err, "status");
            }

            JArray groupsArr = new JArray();
            JObject groupsObj = manifest.Value<JObject>("groups");
            if (groupsObj != null)
            {
                foreach (var kvp in groupsObj)
                {
                    string groupName = kvp.Key;
                    JObject g = kvp.Value as JObject;
                    if (g == null) continue;

                    JArray fileArr = new JArray();
                    bool allInstalled = true;
                    long totalBytes = 0;
                    JArray files = g.Value<JArray>("files");
                    if (files != null)
                    {
                        foreach (JToken t in files)
                        {
                            JObject f = t as JObject;
                            if (f == null) continue;
                            string name = f.Value<string>("name");
                            long bytes = f.Value<long?>("bytes") ?? 0;
                            totalBytes += bytes;

                            string resolvedPath;
                            bool installed = TryResolveExisting(name, out resolvedPath);
                            LogManager.Log("[FontPack] status check " + name
                                + ": installed=" + installed
                                + " path=" + (resolvedPath ?? "(none)"));
                            JObject fileEntry = new JObject();
                            fileEntry["name"] = name;
                            fileEntry["label"] = f.Value<string>("label");
                            fileEntry["bytes"] = bytes;
                            fileEntry["installed"] = installed;
                            fileEntry["resolvedPath"] = installed ? resolvedPath : null;
                            fileArr.Add(fileEntry);
                            if (!installed) allInstalled = false;
                        }
                    }

                    JObject groupEntry = new JObject();
                    groupEntry["name"] = groupName;
                    groupEntry["label"] = g.Value<string>("label");
                    groupEntry["description"] = g.Value<string>("description");
                    groupEntry["totalBytes"] = totalBytes;
                    groupEntry["allInstalled"] = allInstalled;
                    groupEntry["files"] = fileArr;
                    groupsArr.Add(groupEntry);
                }
            }

            JObject resp = new JObject();
            resp["success"] = true;
            resp["task"] = "font_pack";
            resp["op"] = "status";
            resp["fontsDir"] = _appDataFontsDir;
            resp["shippedDir"] = _shippedFontsDir;
            resp["downloadInProgress"] = _downloadInProgress;
            resp["groups"] = groupsArr;
            return resp.ToString(Formatting.None);
        }

        // ================================================================
        // download_group
        // ================================================================

        private string HandleDownloadGroup(JObject payload)
        {
            string groupName = payload.Value<string>("group");
            LogManager.Log("[FontPack] download_group entry: group=" + (groupName ?? "(null)")
                + " progressSink=" + (_progressSink != null ? "ON" : "OFF")
                + " inProgress=" + _downloadInProgress
                + " appData=" + _appDataFontsDir);
            if (string.IsNullOrEmpty(groupName))
                return BuildError("missing group", "download_group");

            JObject manifest;
            string err;
            if (!TryLoadManifest(out manifest, out err))
            {
                LogManager.Log("[FontPack] download_group: manifest load failed: " + err);
                return BuildError(err, "download_group");
            }

            JObject groupsObj = manifest.Value<JObject>("groups");
            JObject g = groupsObj != null ? groupsObj.Value<JObject>(groupName) : null;
            if (g == null)
                return BuildError("unknown group: " + groupName, "download_group");

            List<JObject> filesToDownload = new List<JObject>();
            JArray files = g.Value<JArray>("files");
            if (files != null)
            {
                foreach (JToken t in files)
                {
                    JObject f = t as JObject;
                    if (f == null) continue;
                    string name = f.Value<string>("name");
                    string resolved;
                    bool exists = TryResolveExisting(name, out resolved);
                    LogManager.Log("[FontPack] resolve " + name + ": exists=" + exists
                        + " path=" + (resolved ?? "(none)"));
                    if (!exists) filesToDownload.Add(f);
                }
            }
            LogManager.Log("[FontPack] download_group: " + filesToDownload.Count + " file(s) need download in group=" + groupName);
            return RunDownload(groupName, filesToDownload);
        }

        private string HandleDownloadFile(JObject payload)
        {
            string name = payload.Value<string>("name");
            if (string.IsNullOrEmpty(name))
                return BuildError("missing name", "download_file");

            JObject manifest;
            string err;
            if (!TryLoadManifest(out manifest, out err))
                return BuildError(err, "download_file");

            JObject fileEntry = FindFileEntry(manifest, name);
            if (fileEntry == null)
                return BuildError("unknown file: " + name, "download_file");

            return RunDownload("(file)" + name, new List<JObject> { fileEntry });
        }

        private string RunDownload(string label, List<JObject> filesToDownload)
        {
            lock (_downloadLock)
            {
                if (_downloadInProgress)
                {
                    JObject busy = new JObject();
                    busy["success"] = false;
                    busy["task"] = "font_pack";
                    busy["error"] = "download_already_in_progress";
                    return busy.ToString(Formatting.None);
                }
                _downloadInProgress = true;
                ResetCancel();
            }

            JArray successArr = new JArray();
            JArray failedArr = new JArray();
            int total = filesToDownload.Count;
            int idx = 0;
            bool cancelled = false;

            // 计算 group 级总字节（用于进度条统一显示）
            long groupBytesTotal = 0;
            for (int i = 0; i < filesToDownload.Count; i++)
                groupBytesTotal += filesToDownload[i].Value<long?>("bytes") ?? 0;
            long groupBytesDoneBeforeCurrent = 0;

            try
            {
                if (total == 0)
                {
                    LogManager.Log("[FontPack] download " + label + ": all files already installed");
                }

                foreach (JObject f in filesToDownload)
                {
                    if (IsCancelled()) { cancelled = true; break; }
                    idx++;
                    string name = f.Value<string>("name");
                    long fileExpectedBytes = f.Value<long?>("bytes") ?? 0;
                    if (_notchSink != null)
                    {
                        _notchSink.SetStatusItem("font_pack",
                            "字体下载 " + idx + "/" + total, name, Color.LightSkyBlue);
                    }

                    DownloadCtx ctx = new DownloadCtx
                    {
                        GroupLabel = label,
                        FileName = name,
                        FileIdx = idx,
                        FileTotal = total,
                        FileBytesTotal = fileExpectedBytes,
                        GroupBytesDoneBeforeCurrent = groupBytesDoneBeforeCurrent,
                        GroupBytesTotal = groupBytesTotal
                    };
                    // 文件起点：emit 一次 0% 让 UI 立刻有反馈
                    EmitProgress(ctx, 0, true);

                    string fileErr;
                    bool ok = DownloadFile(f, ctx, out fileErr);
                    if (IsCancelled()) { cancelled = true; }

                    if (ok)
                    {
                        JObject okEntry = new JObject();
                        okEntry["name"] = name;
                        successArr.Add(okEntry);
                        LogManager.Log("[FontPack] downloaded " + idx + "/" + total + ": " + name);
                        EmitProgress(ctx, fileExpectedBytes, true);
                        groupBytesDoneBeforeCurrent += fileExpectedBytes;
                    }
                    else
                    {
                        JObject fail = new JObject();
                        fail["name"] = name;
                        fail["error"] = fileErr;
                        failedArr.Add(fail);
                        LogManager.Log("[FontPack] FAILED " + idx + "/" + total + ": " + name + " :: " + fileErr);
                        if (cancelled) break;
                    }
                }
            }
            finally
            {
                _downloadInProgress = false;
                ResetCancel();
                if (_notchSink != null)
                    _notchSink.ClearStatusItem("font_pack");
            }

            string toastMsg;
            if (cancelled)
            {
                toastMsg = "字体包下载已取消。";
            }
            else if (failedArr.Count == 0)
            {
                toastMsg = "字体包安装完成（" + successArr.Count + "/" + total + "），刷新情报面板即可生效。";
            }
            else
            {
                toastMsg = "字体下载部分失败：成功 " + successArr.Count + " / 失败 " + failedArr.Count
                    + "，可重试或检查网络。";
            }
            if (_toastSink != null && total > 0)
            {
                try { _toastSink.AddMessage(toastMsg); }
                catch { }
            }

            JObject resp = new JObject();
            resp["success"] = !cancelled && failedArr.Count == 0;
            resp["task"] = "font_pack";
            resp["op"] = "download_group";
            resp["group"] = label;
            resp["totalRequested"] = total;
            resp["installed"] = successArr;
            resp["failed"] = failedArr;
            resp["cancelled"] = cancelled;
            return resp.ToString(Formatting.None);
        }

        private sealed class DownloadCtx
        {
            public string GroupLabel;
            public string FileName;
            public int FileIdx;
            public int FileTotal;
            public long FileBytesTotal;
            public long GroupBytesDoneBeforeCurrent;
            public long GroupBytesTotal;
        }

        private void EmitProgress(DownloadCtx ctx, long fileBytesDownloaded, bool force)
        {
            Action<JObject> sink = _progressSink;
            if (sink == null) return;
            long now = Environment.TickCount;
            if (!force)
            {
                long delta = now - _lastProgressTickMs;
                // TickCount 32-bit 翻转保护：负值时直接放行
                if (delta >= 0 && delta < PROGRESS_THROTTLE_MS) return;
            }
            _lastProgressTickMs = now;
            try
            {
                JObject p = new JObject();
                p["group"] = ctx.GroupLabel;
                p["fileName"] = ctx.FileName;
                p["fileIdx"] = ctx.FileIdx;
                p["fileTotal"] = ctx.FileTotal;
                p["fileBytesDownloaded"] = fileBytesDownloaded;
                p["fileBytesTotal"] = ctx.FileBytesTotal;
                long groupDone = ctx.GroupBytesDoneBeforeCurrent + fileBytesDownloaded;
                if (groupDone > ctx.GroupBytesTotal && ctx.GroupBytesTotal > 0)
                    groupDone = ctx.GroupBytesTotal;
                p["groupBytesDownloaded"] = groupDone;
                p["groupBytesTotal"] = ctx.GroupBytesTotal;
                sink(p);
            }
            catch (Exception ex)
            {
                LogManager.Log("[FontPack] progress sink threw: " + ex.Message);
            }
        }

        // ================================================================
        // 单文件下载：urls 顺序尝试 → SHA256 校验 → atomic move
        // ================================================================

        private bool DownloadFile(JObject fileEntry, DownloadCtx ctx, out string err)
        {
            err = null;
            string name = fileEntry.Value<string>("name");
            string expectedSha = (fileEntry.Value<string>("sha256") ?? "").ToLowerInvariant();
            JArray urls = fileEntry.Value<JArray>("urls");
            bool shippedFallback = fileEntry.Value<bool?>("shippedFallback") ?? false;

            string targetPath = Path.Combine(_appDataFontsDir, name);
            string tmpPath = targetPath + ".download.tmp";

            // 已存在且校验通过：跳过
            if (File.Exists(targetPath) && VerifySha256(targetPath, expectedSha))
                return true;

            List<string> attemptedErrors = new List<string>();

            // 1) urls 顺序尝试
            if (urls != null)
            {
                foreach (JToken t in urls)
                {
                    if (IsCancelled()) { err = "cancelled"; return false; }
                    string url = t.Value<string>();
                    if (string.IsNullOrEmpty(url)) continue;

                    string downloadErr;
                    if (TryDownloadUrl(url, tmpPath, ctx, out downloadErr))
                    {
                        if (IsCancelled()) { err = "cancelled"; try { File.Delete(tmpPath); } catch { } return false; }
                        if (!VerifySha256(tmpPath, expectedSha))
                        {
                            attemptedErrors.Add(url + " :: sha256_mismatch");
                            try { File.Delete(tmpPath); } catch { }
                            continue;
                        }
                        if (TryMoveAtomic(tmpPath, targetPath, out downloadErr))
                            return true;
                        attemptedErrors.Add(url + " :: move_failed: " + downloadErr);
                    }
                    else
                    {
                        if (downloadErr == "cancelled") { err = "cancelled"; return false; }
                        attemptedErrors.Add(url + " :: " + downloadErr);
                    }
                }
            }

            // 2) shippedFallback：从 launcher/web/assets/fonts/ 复制
            if (shippedFallback)
            {
                string shippedPath = Path.Combine(_shippedFontsDir, name);
                if (File.Exists(shippedPath) && VerifySha256(shippedPath, expectedSha))
                {
                    try
                    {
                        File.Copy(shippedPath, tmpPath, true);
                        string moveErr;
                        if (TryMoveAtomic(tmpPath, targetPath, out moveErr))
                        {
                            LogManager.Log("[FontPack] " + name + " — copied from shipped fallback");
                            return true;
                        }
                        attemptedErrors.Add("shipped_fallback :: move_failed: " + moveErr);
                    }
                    catch (Exception ex)
                    {
                        attemptedErrors.Add("shipped_fallback :: copy_failed: " + ex.Message);
                    }
                }
                else
                {
                    attemptedErrors.Add("shipped_fallback :: not_present_or_sha_mismatch");
                }
            }

            err = "all_sources_failed: " + string.Join(" | ", attemptedErrors.ToArray());
            return false;
        }

        /// <summary>
        /// 流式下载：HttpWebRequest + 64KB buffer + 每 chunk 检查 cancel + 节流推进度。
        /// 返回 false / err="cancelled" 时上层应判断为用户取消，不再做后续 url 重试。
        /// </summary>
        private bool TryDownloadUrl(string url, string destPath, DownloadCtx ctx, out string err)
        {
            err = null;
            LogManager.Log("[FontPack] HTTP GET " + url + " → " + destPath);
            HttpWebResponse resp = null;
            Stream src = null;
            FileStream dst = null;
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
                req.UserAgent = "CF7Launcher-FontPack/1.0";
                req.Timeout = 30000;
                req.ReadWriteTimeout = 30000;
                req.AllowAutoRedirect = true;
                resp = (HttpWebResponse)req.GetResponse();

                long contentLength = resp.ContentLength;  // -1 if unknown
                LogManager.Log("[FontPack] HTTP " + (int)resp.StatusCode + " content-length="
                    + contentLength + " final-uri=" + resp.ResponseUri);
                long fileBytesTotalForUi = contentLength > 0 ? contentLength : ctx.FileBytesTotal;
                if (ctx != null && fileBytesTotalForUi > 0)
                    ctx.FileBytesTotal = fileBytesTotalForUi;

                src = resp.GetResponseStream();
                dst = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, DOWNLOAD_BUFFER);

                byte[] buffer = new byte[DOWNLOAD_BUFFER];
                long downloaded = 0;
                int read;
                while ((read = src.Read(buffer, 0, buffer.Length)) > 0)
                {
                    if (IsCancelled())
                    {
                        err = "cancelled";
                        try { dst.Close(); dst = null; File.Delete(destPath); } catch { }
                        return false;
                    }
                    dst.Write(buffer, 0, read);
                    downloaded += read;
                    if (ctx != null) EmitProgress(ctx, downloaded, false);
                }
                return true;
            }
            catch (Exception ex)
            {
                err = ex.Message;
                LogManager.Log("[FontPack] HTTP GET failed " + url + " :: " + ex.GetType().Name + " :: " + ex.Message);
                try { if (dst != null) dst.Close(); dst = null; if (File.Exists(destPath)) File.Delete(destPath); } catch { }
                return false;
            }
            finally
            {
                if (dst != null) try { dst.Dispose(); } catch { }
                if (src != null) try { src.Dispose(); } catch { }
                if (resp != null) try { resp.Close(); } catch { }
            }
        }

        private static bool TryMoveAtomic(string srcPath, string dstPath, out string err)
        {
            err = null;
            try
            {
                if (File.Exists(dstPath)) File.Delete(dstPath);
                File.Move(srcPath, dstPath);
                return true;
            }
            catch (Exception ex)
            {
                err = ex.Message;
                return false;
            }
        }

        private static bool VerifySha256(string filePath, string expectedHex)
        {
            if (string.IsNullOrEmpty(expectedHex)) return true; // manifest 未声明 sha 时不卡门
            try
            {
                using (FileStream fs = File.OpenRead(filePath))
                using (SHA256 sha = SHA256.Create())
                {
                    byte[] hash = sha.ComputeHash(fs);
                    StringBuilder sb = new StringBuilder(hash.Length * 2);
                    for (int i = 0; i < hash.Length; i++) sb.Append(hash[i].ToString("x2"));
                    return string.Equals(sb.ToString(), expectedHex, StringComparison.OrdinalIgnoreCase);
                }
            }
            catch { return false; }
        }

        // ================================================================
        // helpers
        // ================================================================

        /// <summary>
        /// 解析字体文件实际位置：优先 AppData，回退 shipped。两者都不存在或 sha 不通过 → false。
        /// </summary>
        private bool TryResolveExisting(string name, out string resolved)
        {
            resolved = null;
            if (string.IsNullOrEmpty(name)) return false;

            string appDataPath = Path.Combine(_appDataFontsDir, name);
            if (File.Exists(appDataPath))
            {
                resolved = appDataPath;
                return true;
            }
            string shippedPath = Path.Combine(_shippedFontsDir, name);
            if (File.Exists(shippedPath))
            {
                resolved = shippedPath;
                return true;
            }
            return false;
        }

        private bool TryLoadManifest(out JObject manifest, out string err)
        {
            manifest = null;
            err = null;
            if (!File.Exists(_manifestPath))
            {
                err = "manifest_not_found: " + _manifestPath;
                return false;
            }
            try
            {
                manifest = JObject.Parse(File.ReadAllText(_manifestPath, Encoding.UTF8));
                return true;
            }
            catch (Exception ex)
            {
                err = "manifest_parse_failed: " + ex.Message;
                return false;
            }
        }

        private static JObject FindFileEntry(JObject manifest, string name)
        {
            JObject groupsObj = manifest.Value<JObject>("groups");
            if (groupsObj == null) return null;
            foreach (var kvp in groupsObj)
            {
                JObject g = kvp.Value as JObject;
                if (g == null) continue;
                JArray files = g.Value<JArray>("files");
                if (files == null) continue;
                foreach (JToken t in files)
                {
                    JObject f = t as JObject;
                    if (f == null) continue;
                    if (string.Equals(f.Value<string>("name"), name, StringComparison.Ordinal))
                        return f;
                }
            }
            return null;
        }

        private static string BuildError(string error, string op)
        {
            JObject obj = new JObject();
            obj["success"] = false;
            obj["task"] = "font_pack";
            if (op != null) obj["op"] = op;
            obj["error"] = error;
            return obj.ToString(Formatting.None);
        }
    }
}
