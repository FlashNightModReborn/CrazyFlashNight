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
using CF7Launcher.Fonts;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 字体包按需下载。由 fonts.xml 生成的兼容投影列出 group → files，
    /// 每个 file 带 SHA256 + 镜像 url 列表。下载只落盘到 fonts/temporary/cache；
    /// WebView2 只通过 RuntimeFontCatalog exact-set handler 读取。
    ///
    /// 协议（async via MessageRouter）：
    ///   { task:"font_pack", payload:{ op:"status" } }
    ///       → { success, task:"font_pack", op:"status", fontsDir, groups:[ { name, label, allInstalled, files:[ {name,bytes,installed,verificationState} ] } ] }
    ///   { task:"font_pack", payload:{ op:"download_group", group:"essential" } }
    ///       → 启动后台下载，progress 通过 notch + 完成 toast 报告，end 回 success/failed 列表
    ///   { task:"font_pack", payload:{ op:"download_file", name:"xxx.ttf" } }
    ///       → 单文件重试入口
    /// </summary>
    public class FontPackTask
    {
        private readonly string _projectRoot;
        private readonly string _cacheFontsDir;
        private readonly string _permanentFontsDir;
        private readonly string _catalogPath;
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
        private const int MAX_REDIRECTS = 5;

        public string CacheFontsDir { get { return _cacheFontsDir; } }

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
            _manifestPath = Path.Combine(projectRoot, "launcher", "web", "assets", "fonts", "font-pack-manifest.json");
            _catalogPath = Path.Combine(projectRoot, "fonts", "fonts.xml");
            _cacheFontsDir = Path.Combine(projectRoot, "fonts", "temporary", "cache");
            _permanentFontsDir = Path.Combine(projectRoot, "fonts", "permanent", "runtime");
            try { Directory.CreateDirectory(_cacheFontsDir); }
            catch (Exception ex) { LogManager.Log("[FontPack] Failed to create cache dir: " + ex.Message); }

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
            LogManager.Log("[FontPack] status entry: cache=" + _cacheFontsDir
                + " permanent=" + _permanentFontsDir);
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
                            string verificationState;
                            bool installed = TryResolveExisting(f, out resolvedPath, out verificationState);
                            LogManager.Log("[FontPack] status check " + name
                                + ": installed=" + installed
                                + " verification=" + verificationState
                                + " path=" + (resolvedPath ?? "(none)"));
                            JObject fileEntry = new JObject();
                            fileEntry["name"] = name;
                            fileEntry["label"] = f.Value<string>("label");
                            fileEntry["bytes"] = bytes;
                            fileEntry["installed"] = installed;
                            fileEntry["verificationState"] = verificationState;
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
            resp["fontsDir"] = _cacheFontsDir;
            resp["cacheDir"] = _cacheFontsDir;
            resp["permanentDir"] = _permanentFontsDir;
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
                + " cache=" + _cacheFontsDir);
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
                    string verificationState;
                    bool exists = TryResolveExisting(f, out resolved, out verificationState);
                    LogManager.Log("[FontPack] resolve " + name + ": exists=" + exists
                        + " verification=" + verificationState
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
                    string verificationState;
                    bool ok = DownloadFile(f, ctx, out fileErr, out verificationState);
                    if (IsCancelled()) { cancelled = true; }

                    if (ok)
                    {
                        JObject okEntry = new JObject();
                        okEntry["name"] = name;
                        okEntry["verificationState"] = verificationState;
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
        // 单文件下载：urls 顺序尝试 → SHA256 + runtime probe → atomic move
        // ================================================================

        private bool DownloadFile(
            JObject fileEntry,
            DownloadCtx ctx,
            out string err,
            out string verificationState)
        {
            err = null;
            verificationState = "not-verified";
            string name = fileEntry.Value<string>("name");
            string expectedSha = (fileEntry.Value<string>("sha256") ?? "").ToLowerInvariant();
            long expectedBytes = fileEntry.Value<long?>("bytes") ?? 0L;
            JArray urls = fileEntry.Value<JArray>("urls");
            if (!IsSafeFontFileName(name))
            {
                err = "unsafe_file_name";
                return false;
            }
            if (!IsSha256(expectedSha) || expectedBytes < 1 || expectedBytes > RuntimeFontCatalog.MaxFontBytes)
            {
                err = "invalid_integrity_contract";
                return false;
            }
            try { Directory.CreateDirectory(_cacheFontsDir); }
            catch (Exception ex)
            {
                err = "cannot_create_fonts_dir: " + ex.Message;
                return false;
            }

            string targetPath = Path.Combine(_cacheFontsDir, name);

            // 已存在且校验通过：跳过
            if (VerifyFile(targetPath, name, expectedSha, expectedBytes, out verificationState))
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

                    string tmpPath = Path.Combine(_cacheFontsDir,
                        "." + name + ".download." + Guid.NewGuid().ToString("N") + ".tmp");
                    string downloadErr;
                    if (TryDownloadUrl(url, tmpPath, expectedBytes, ctx, out downloadErr))
                    {
                        if (IsCancelled()) { err = "cancelled"; try { File.Delete(tmpPath); } catch { } return false; }
                        if (!VerifyFile(tmpPath, name, expectedSha, expectedBytes, out verificationState))
                        {
                            attemptedErrors.Add(url + " :: verification_failed:" + verificationState);
                            try { File.Delete(tmpPath); } catch { }
                            continue;
                        }
                        if (TryMoveAtomic(tmpPath, targetPath, out downloadErr))
                            return true;
                        attemptedErrors.Add(url + " :: move_failed: " + downloadErr);
                    }
                    else
                    {
                        try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { }
                        if (downloadErr == "cancelled") { err = "cancelled"; return false; }
                        attemptedErrors.Add(url + " :: " + downloadErr);
                    }
                }
            }

            err = "all_sources_failed: " + string.Join(" | ", attemptedErrors.ToArray());
            return false;
        }

        /// <summary>
        /// 流式下载：HttpWebRequest + 64KB buffer + 每 chunk 检查 cancel + 节流推进度。
        /// 返回 false / err="cancelled" 时上层应判断为用户取消，不再做后续 url 重试。
        /// </summary>
        private bool TryDownloadUrl(string url, string destPath, long expectedBytes, DownloadCtx ctx, out string err)
        {
            err = null;
            LogManager.Log("[FontPack] HTTP GET " + url + " → " + destPath);
            HttpWebResponse resp = null;
            Stream src = null;
            FileStream dst = null;
            try
            {
                Uri current;
                if (!TryValidateDownloadUri(url, out current, out err)) return false;
                for (int redirect = 0; ; redirect++)
                {
                    HttpWebRequest req = (HttpWebRequest)WebRequest.Create(current);
                    req.UserAgent = "CF7Launcher-FontPack/2.0";
                    req.Timeout = 30000;
                    req.ReadWriteTimeout = 30000;
                    req.AllowAutoRedirect = false;
                    resp = (HttpWebResponse)req.GetResponse();
                    int status = (int)resp.StatusCode;
                    if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308)
                    {
                        if (redirect >= MAX_REDIRECTS) { err = "redirect_limit"; return false; }
                        string location = resp.Headers[HttpResponseHeader.Location];
                        Uri validatedNext;
                        if (!TryResolveRedirect(current, location, out validatedNext, out err))
                            return false;
                        resp.Close();
                        resp = null;
                        current = validatedNext;
                        continue;
                    }
                    if (status != 200) { err = "http_" + status; return false; }
                    break;
                }

                long contentLength = resp.ContentLength;  // -1 if unknown
                LogManager.Log("[FontPack] HTTP " + (int)resp.StatusCode + " content-length="
                    + contentLength + " final-uri=" + resp.ResponseUri);
                if (contentLength > 0 && contentLength != expectedBytes)
                {
                    err = "content_length_mismatch:" + contentLength;
                    return false;
                }
                long fileBytesTotalForUi = expectedBytes;
                if (ctx != null && fileBytesTotalForUi > 0)
                    ctx.FileBytesTotal = fileBytesTotalForUi;

                src = resp.GetResponseStream();
                dst = new FileStream(destPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, DOWNLOAD_BUFFER);

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
                    if (downloaded > expectedBytes || downloaded > RuntimeFontCatalog.MaxFontBytes)
                    {
                        err = "response_too_large";
                        return false;
                    }
                    if (ctx != null) EmitProgress(ctx, downloaded, false);
                }
                if (downloaded != expectedBytes)
                {
                    err = "response_bytes_mismatch:" + downloaded;
                    return false;
                }
                dst.Flush(true);
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
            string backup = dstPath + "." + Guid.NewGuid().ToString("N") + ".bak";
            bool movedExisting = false;
            try
            {
                if (File.Exists(dstPath))
                {
                    File.Move(dstPath, backup);
                    movedExisting = true;
                }
                File.Move(srcPath, dstPath);
                if (movedExisting) File.Delete(backup);
                return true;
            }
            catch (Exception ex)
            {
                try { if (File.Exists(srcPath)) File.Delete(srcPath); } catch { }
                if (movedExisting && !File.Exists(dstPath) && File.Exists(backup))
                    try { File.Move(backup, dstPath); } catch { }
                err = ex.Message;
                return false;
            }
        }

        private static bool VerifyBytes(
            string assetName,
            byte[] bytes,
            string expectedHex,
            long expectedBytes,
            out string validationState)
        {
            validationState = "invalid-integrity-contract";
            if (!IsSha256(expectedHex) || expectedBytes < 1 || expectedBytes > RuntimeFontCatalog.MaxFontBytes)
                return false;
            if (bytes == null || bytes.LongLength != expectedBytes)
            {
                validationState = "length-mismatch";
                return false;
            }
            try
            {
                using (SHA256 sha = SHA256.Create())
                {
                    byte[] hash = sha.ComputeHash(bytes);
                    StringBuilder sb = new StringBuilder(hash.Length * 2);
                    for (int i = 0; i < hash.Length; i++) sb.Append(hash[i].ToString("x2"));
                    if (!string.Equals(sb.ToString(), expectedHex, StringComparison.OrdinalIgnoreCase))
                    {
                        validationState = "hash-mismatch";
                        return false;
                    }
                }
                return RuntimeFontCatalog.ValidatePackCandidate(assetName, bytes, out validationState);
            }
            catch
            {
                validationState = "verification-exception";
                return false;
            }
        }

        private static bool VerifyFile(
            string filePath,
            string assetName,
            string expectedHex,
            long expectedBytes,
            out string validationState)
        {
            validationState = "read-failed";
            if (!IsSha256(expectedHex) || expectedBytes < 1
                || expectedBytes > RuntimeFontCatalog.MaxFontBytes
                || expectedBytes > int.MaxValue)
            {
                validationState = "invalid-integrity-contract";
                return false;
            }
            try
            {
                byte[] bytes = new byte[(int)expectedBytes];
                using (FileStream stream = new FileStream(
                    filePath, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    if (stream.Length != expectedBytes)
                    {
                        validationState = "length-mismatch";
                        return false;
                    }
                    int readTotal = 0;
                    while (readTotal < bytes.Length)
                    {
                        int read = stream.Read(bytes, readTotal, bytes.Length - readTotal);
                        if (read == 0) break;
                        readTotal += read;
                    }
                    if (readTotal != bytes.Length || stream.ReadByte() != -1)
                    {
                        validationState = "length-mismatch";
                        return false;
                    }
                }
                return VerifyBytes(assetName, bytes, expectedHex, expectedBytes, out validationState);
            }
            catch
            {
                validationState = "read-failed";
                return false;
            }
        }

        private static bool IsSha256(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
            }
            return true;
        }

        private static bool TryValidateDownloadUri(string value, out Uri uri, out string err)
        {
            err = null;
            if (!Uri.TryCreate(value, UriKind.Absolute, out uri)
                || !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            {
                err = "url_scheme";
                return false;
            }
            if (!string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Fragment))
            {
                err = "url_unsafe";
                return false;
            }
            if (!uri.IsDefaultPort)
            {
                err = "url_port";
                return false;
            }
            string host = uri.Host.ToLowerInvariant();
            if (!RuntimeFontCatalog.IsAllowedDownloadHost(host))
            {
                err = "host_not_allowed:" + host;
                return false;
            }
            return true;
        }

        private static bool TryResolveRedirect(
            Uri current,
            string location,
            out Uri validatedNext,
            out string err)
        {
            validatedNext = null;
            err = null;
            Uri next;
            if (current == null || string.IsNullOrEmpty(location)
                || !Uri.TryCreate(current, location, out next))
            {
                err = "redirect_location";
                return false;
            }
            return TryValidateDownloadUri(next.AbsoluteUri, out validatedNext, out err);
        }

        // ================================================================
        // helpers
        // ================================================================

        /// <summary>
        /// 解析字体文件实际位置。与 Web/native 共用 catalog 来源优先级和完整性判断。
        /// </summary>
        private bool TryResolveExisting(
            JObject fileEntry,
            out string resolved,
            out string verificationState)
        {
            resolved = null;
            verificationState = "not-installed";
            if (fileEntry == null) return false;
            string name = fileEntry.Value<string>("name");
            if (string.IsNullOrEmpty(name)) return false;
            if (!IsSafeFontFileName(name))
            {
                LogManager.Log("[FontPack] unsafe font file name ignored: " + name);
                return false;
            }
            string expectedSha = (fileEntry.Value<string>("sha256") ?? "").ToLowerInvariant();
            long expectedBytes = fileEntry.Value<long?>("bytes") ?? 0L;

            RuntimeFontCatalog.ResolvedAsset catalogResolved = RuntimeFontCatalog.ResolveFile(name);
            if (catalogResolved != null)
            {
                if (string.Equals(catalogResolved.Source, "temporary/custom", StringComparison.Ordinal))
                {
                    resolved = catalogResolved.Path;
                    verificationState = "custom-runtime-parser-verified";
                    return true;
                }
                if (VerifyBytes(
                    name,
                    catalogResolved.Bytes,
                    expectedSha,
                    expectedBytes,
                    out verificationState))
                {
                    resolved = catalogResolved.Path;
                    return true;
                }
            }

            string cachePath = Path.Combine(_cacheFontsDir, name);
            if (File.Exists(cachePath))
            {
                if (VerifyFile(
                    cachePath,
                    name,
                    expectedSha,
                    expectedBytes,
                    out verificationState))
                {
                    resolved = cachePath;
                    return true;
                }
                LogManager.Log("[FontPack] existing cache font sha mismatch: " + cachePath);
            }
            return false;
        }

        internal static bool VerifyDownloadedFileForTest(
            string filePath,
            string assetName,
            string expectedHex,
            long expectedBytes,
            out string validationState)
        {
            return VerifyFile(
                filePath,
                assetName,
                expectedHex,
                expectedBytes,
                out validationState);
        }

        internal static bool TryResolveRedirectForTest(
            string currentValue,
            string location,
            out string resolved,
            out string err)
        {
            resolved = null;
            Uri current;
            if (!TryValidateDownloadUri(currentValue, out current, out err)) return false;
            Uri validatedNext;
            if (!TryResolveRedirect(current, location, out validatedNext, out err)) return false;
            resolved = validatedNext.AbsoluteUri;
            return true;
        }

        private static bool IsSafeFontFileName(string name)
        {
            if (string.IsNullOrEmpty(name) || name.Length > 128) return false;
            if (name == "." || name == "..") return false;
            if (name.IndexOf('/') >= 0 || name.IndexOf('\\') >= 0 || name.IndexOf(':') >= 0) return false;
            if (!string.Equals(name, Path.GetFileName(name), StringComparison.Ordinal)) return false;
            if (name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return false;
            string ext = Path.GetExtension(name);
            return string.Equals(ext, ".ttf", StringComparison.OrdinalIgnoreCase)
                || string.Equals(ext, ".otf", StringComparison.OrdinalIgnoreCase)
                || string.Equals(ext, ".woff", StringComparison.OrdinalIgnoreCase)
                || string.Equals(ext, ".woff2", StringComparison.OrdinalIgnoreCase);
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
                if (manifest.Value<int?>("schemaVersion") != 1
                    || !string.Equals(manifest.Value<string>("generatedBy"), "tools/fontctl", StringComparison.Ordinal)
                    || !string.Equals(manifest.Value<string>("gate"), "E", StringComparison.Ordinal)
                    || manifest.Value<JObject>("groups") == null
                    || !File.Exists(_catalogPath))
                {
                    err = "manifest_shape_or_source_invalid";
                    manifest = null;
                    return false;
                }
                string expectedSourceHash;
                using (FileStream stream = File.OpenRead(_catalogPath))
                using (SHA256 sha = SHA256.Create())
                {
                    byte[] hash = sha.ComputeHash(stream);
                    StringBuilder builder = new StringBuilder(hash.Length * 2);
                    for (int i = 0; i < hash.Length; i++) builder.Append(hash[i].ToString("x2"));
                    expectedSourceHash = builder.ToString();
                }
                if (!string.Equals(manifest.Value<string>("sourceSha256"), expectedSourceHash, StringComparison.Ordinal))
                {
                    err = "manifest_source_sha256_mismatch";
                    manifest = null;
                    return false;
                }
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
