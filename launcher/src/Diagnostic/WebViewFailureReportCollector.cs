// CF7:ME WebView 故障取证采集器
// 从 logs/webview-failures.jsonl（worker01 WebViewFailureRecorder 写入）读取有界尾部，
// 提取 failureReportFolderPath 指向的 Crashpad 报告目录，按严格上界把真实崩溃报告
// 文件并入诊断包。所有来源路径必须规范落在 launcher WebView2 UDF 的 Crashpad 根内；
// 拒绝穿越 / junction / 任意绝对路径，单文件失败只记省略原因，绝不拖垮主包。
// 哈希口径与现有 file-hashes.json 一致：SHA256 大写十六进制。

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Diagnostic
{
    internal static class WebViewFailureReportCollector
    {
        // ---- 上界（全部写入 manifest，审阅者可复核实际收紧量） ----
        internal const long MaxLogTailBytes = 256 * 1024;
        internal const int MaxLogEntriesParsed = 200;
        internal const int MaxReferencedFolders = 6;
        internal const int MaxEnumeratePerFolder = 512;
        internal const int MaxFilesPerFolder = 8;
        internal const int MaxFilesTotal = 16;
        internal const long MaxFileBytes = 8 * 1024 * 1024;
        internal const long MaxTotalBytes = 24 * 1024 * 1024;
        internal const int MaxOmissionsRecorded = 32;
        internal const int MaxWarnings = 10;
        internal static readonly TimeSpan MaxReportAge = TimeSpan.FromDays(14);
        internal static readonly string[] AllowedExtensions = { ".dmp", ".log", ".txt", ".json" };

        internal const string LogLogicalPath = "logs/webview-failures.jsonl";
        internal const string ManifestLogicalPath = "webview-failures/manifest.json";
        internal const string ReportLogicalPrefix = "webview-failures/reports/";

        // UDF 相对项目根位置；Crashpad 根是允许取文件的唯一根。
        private static readonly string[] UserDataRelativeDirs =
        {
            Path.Combine("launcher", "webview2_overlay_userdata"),
            Path.Combine("launcher", "webview2_userdata")
        };

        // jsonl 中可接受的报告目录字段名（主名按共享契约，别名兜底）。
        private static readonly string[] ReportPathFields =
            { "failureReportFolderPath", "reportFolderPath", "reportFolder" };
        private static readonly string[] TimestampFields =
            { "atUtc", "timestamp", "time", "ts", "utc" };

        /// <summary>输出端：logicalPath 用 '/' 分隔，返回实际落位名（zip entry / 扁平文件名）。</summary>
        internal interface IWebViewFailureSink
        {
            string Write(string logicalPath, byte[] content);
        }

        internal sealed class ZipSink : IWebViewFailureSink
        {
            private readonly ZipArchive _zip;
            internal ZipSink(ZipArchive zip) { _zip = zip; }

            public string Write(string logicalPath, byte[] content)
            {
                ZipArchiveEntry entry = _zip.CreateEntry(logicalPath, CompressionLevel.Optimal);
                using (Stream s = entry.Open()) s.Write(content, 0, content.Length);
                return logicalPath;
            }
        }

        // 退出快照目录只收顶层文件（采集脚本仅对顶层文件做哈希清单），全部压平命名。
        internal sealed class DirectorySink : IWebViewFailureSink
        {
            private readonly string _directory;
            internal DirectorySink(string directory) { _directory = directory; }

            internal static string Flatten(string logicalPath)
            {
                if (logicalPath.StartsWith("logs/", StringComparison.Ordinal))
                    return SanitizeName(Path.GetFileName(logicalPath));
                if (string.Equals(logicalPath, ManifestLogicalPath, StringComparison.Ordinal))
                    return "webview-failures-manifest.json";
                if (logicalPath.StartsWith(ReportLogicalPrefix, StringComparison.Ordinal))
                    return "wvf-" + SanitizeName(logicalPath.Substring(ReportLogicalPrefix.Length)
                        .Replace('/', '-'));
                return "wvf-" + SanitizeName(logicalPath.Replace('/', '-'));
            }

            public string Write(string logicalPath, byte[] content)
            {
                string name = Flatten(logicalPath);
                File.WriteAllBytes(Path.Combine(_directory, name), content);
                return name;
            }
        }

        internal sealed class Result
        {
            internal bool LogIncluded;
            internal long LogBytes;
            internal bool LogTruncated;
            internal string LogOmittedReason;
            internal bool RotatedIncluded;
            internal long RotatedBytes;
            internal string RotatedOmittedReason;
            internal int FilesIncluded;
            internal long BytesIncluded;
            internal int OmissionsRecorded;
            internal readonly List<string> Warnings = new List<string>();
            internal JObject Manifest;

            internal JObject Summary()
            {
                return new JObject
                {
                    ["logIncluded"] = LogIncluded,
                    ["logBytes"] = LogBytes,
                    ["logTruncated"] = LogTruncated,
                    ["rotatedIncluded"] = RotatedIncluded,
                    ["filesIncluded"] = FilesIncluded,
                    ["bytesIncluded"] = BytesIncluded,
                    ["omissions"] = OmissionsRecorded
                };
            }
        }

        // 引用日志行的携带元数据，落进 included 条目便于 dump ↔ 故障事件对照。
        private sealed class Referrer
        {
            internal string Session;
            internal string Kind;
            internal string Reason;
            internal string AtUtc;
            internal string BrowserVersion;
            internal string Classification;
            internal long? ExitCode;
            internal long? DocumentGeneration;
        }

        private sealed class FolderCandidate
        {
            internal string Raw;          // 日志原始值 / null=根扫描
            internal string FullPath;     // 规范化后
            internal string Origin;       // log | reports_scan
            internal Referrer Ref;
        }

        internal static Result Collect(string projectRoot, IWebViewFailureSink sink)
        {
            Result result = new Result();
            JArray included = new JArray();
            JArray omitted = new JArray();
            int omittedOverflow = 0;
            HashSet<string> seenFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            long totalBytes = 0;
            int filesTotal = 0;

            string rootFull = Path.GetFullPath(projectRoot).TrimEnd('\\', '/');
            List<string> allowedRoots = new List<string>();
            foreach (string udf in UserDataRelativeDirs)
            {
                allowedRoots.Add(Path.GetFullPath(Path.Combine(rootFull, udf, "EBWebView", "Crashpad"))
                    .TrimEnd('\\', '/'));
            }

            // ---- 1) 有界读取并落位 webview-failures.jsonl(+ .1 轮转份) 尾部 ----
            // 先当前文件后轮转份；解析顺序同此（新→旧）。
            List<string> logLines = new List<string>();
            string logPath = Path.Combine(rootFull, "logs", "webview-failures.jsonl");
            for (int li = 0; li < 2; li++)
            {
                string path = li == 0 ? logPath : logPath + ".1";
                byte[] tail = ReadSharedTail(path, MaxLogTailBytes, out bool truncated,
                    out string logError);
                if (tail != null)
                {
                    try
                    {
                        sink.Write(LogLogicalPath + (li == 0 ? "" : ".1"), tail);
                        if (li == 0)
                        {
                            result.LogIncluded = true;
                            result.LogBytes = tail.LongLength;
                            result.LogTruncated = truncated;
                        }
                        else
                        {
                            result.RotatedIncluded = true;
                            result.RotatedBytes = tail.LongLength;
                        }
                    }
                    catch (Exception ex)
                    {
                        if (li == 0) result.LogOmittedReason = "write_failed";
                        else result.RotatedOmittedReason = "write_failed";
                        AddWarning(result, "webview-failures.jsonl" + (li == 0 ? "" : ".1")
                            + " sink write failed: " + ex.Message);
                    }
                    string text = Encoding.UTF8.GetString(tail);
                    string[] lines = text.Split(new[] { '\r', '\n' },
                        StringSplitOptions.RemoveEmptyEntries);
                    for (int i = lines.Length - 1; i >= 0; i--) logLines.Add(lines[i]);
                }
                else
                {
                    if (li == 0)
                    {
                        result.LogOmittedReason = logError; // log_missing | log_unreadable
                        if (logError == "log_unreadable")
                            AddWarning(result, "webview-failures.jsonl unreadable; tail omitted");
                    }
                    else result.RotatedOmittedReason = logError;
                }
            }

            // ---- 2) 解析尾部（新→旧），提取引用的报告目录 ----
            List<FolderCandidate> folders = new List<FolderCandidate>();
            HashSet<string> seenDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            int folderCapDropped = 0;
            {
                int parsed = 0;
                for (int i = 0; i < logLines.Count && parsed < MaxLogEntriesParsed; i++, parsed++)
                {
                    JObject entry;
                    try { entry = JObject.Parse(logLines[i]); }
                    catch { continue; }
                    string candidate = null;
                    foreach (string field in ReportPathFields)
                    {
                        JToken v = entry[field];
                        if (v != null && v.Type == JTokenType.String && !string.IsNullOrWhiteSpace((string)v))
                        {
                            candidate = (string)v;
                            break;
                        }
                    }
                    if (candidate == null) continue;
                    Referrer referrer = new Referrer
                    {
                        Session = StringProp(entry, "session"),
                        Kind = StringProp(entry, "kind"),
                        Reason = StringProp(entry, "reason"),
                        AtUtc = TimestampProp(entry),
                        BrowserVersion = StringProp(entry, "browserVersion"),
                        Classification = StringProp(entry, "classification"),
                        ExitCode = IntProp(entry, "exitCode"),
                        DocumentGeneration = IntProp(entry, "documentGeneration")
                    };
                    string normalized = NormalizeCandidate(candidate, allowedRoots, out string reject);
                    if (normalized == null)
                    {
                        AddOmission(omitted, ref omittedOverflow, new JObject
                        {
                            ["candidate"] = candidate, ["reason"] = reject
                        });
                        continue;
                    }
                    if (!seenDirs.Add(normalized)) continue;
                    if (folders.Count >= MaxReferencedFolders) { folderCapDropped++; continue; }
                    folders.Add(new FolderCandidate
                    {
                        Raw = candidate, FullPath = normalized, Origin = "log", Ref = referrer
                    });
                }
            }
            // Crashpad 待上报目录直接扫描：日志缺失或条目未携带路径时仍能拿到本轮崩溃文件。
            foreach (string allowedRoot in allowedRoots)
            {
                string reports = Path.Combine(allowedRoot, "reports");
                if (seenDirs.Add(reports))
                    folders.Add(new FolderCandidate { FullPath = reports, Origin = "reports_scan" });
            }
            if (folderCapDropped > 0)
            {
                AddOmission(omitted, ref omittedOverflow, new JObject
                {
                    ["reason"] = "folder_cap",
                    ["detail"] = folderCapDropped + " referenced folder(s) beyond cap " + MaxReferencedFolders
                });
            }

            // ---- 3) 逐目录按上界收集文件 ----
            DateTime utcNow = DateTime.UtcNow;
            int folderIndex = 0;
            foreach (FolderCandidate folder in folders)
            {
                string tag = "r" + folderIndex.ToString("D2", CultureInfo.InvariantCulture);
                folderIndex++;
                if (ChainHasReparsePoint(folder.FullPath, rootFull))
                {
                    AddOmission(omitted, ref omittedOverflow, new JObject
                    {
                        ["path"] = RelativeOrLeaf(rootFull, folder.FullPath),
                        ["candidate"] = folder.Raw, ["reason"] = "reparse_point"
                    });
                    continue;
                }
                if (!Directory.Exists(folder.FullPath))
                {
                    if (folder.Origin == "log")
                    {
                        AddOmission(omitted, ref omittedOverflow, new JObject
                        {
                            ["path"] = RelativeOrLeaf(rootFull, folder.FullPath),
                            ["candidate"] = folder.Raw, ["reason"] = "not_found"
                        });
                    }
                    continue; // reports_scan 目录缺失是常态，不算省略
                }
                List<FileInfo> files;
                bool enumCapped = false;
                try
                {
                    files = new DirectoryInfo(folder.FullPath).EnumerateFiles()
                        .Take(MaxEnumeratePerFolder + 1)
                        .OrderByDescending(f => f.LastWriteTimeUtc).ToList();
                    if (files.Count > MaxEnumeratePerFolder)
                    {
                        files.RemoveRange(MaxEnumeratePerFolder, files.Count - MaxEnumeratePerFolder);
                        enumCapped = true;
                    }
                    // 注意：Take 先于排序生效；超过上限时评估的是枚举子集中的最新项。
                }
                catch (Exception ex)
                {
                    AddOmission(omitted, ref omittedOverflow, new JObject
                    {
                        ["path"] = RelativeOrLeaf(rootFull, folder.FullPath),
                        ["candidate"] = folder.Raw, ["reason"] = "enumerate_failed",
                        ["detail"] = ex.GetType().Name
                    });
                    continue;
                }
                if (enumCapped)
                {
                    AddOmission(omitted, ref omittedOverflow, new JObject
                    {
                        ["path"] = RelativeOrLeaf(rootFull, folder.FullPath),
                        ["reason"] = "enumerate_cap",
                        ["detail"] = "folder holds more than " + MaxEnumeratePerFolder
                            + " entries; only an enumerated subset was evaluated"
                    });
                }
                int perFolder = 0;
                for (int fi = 0; fi < files.Count; fi++)
                {
                    FileInfo file = files[fi];
                    if (filesTotal >= MaxFilesTotal || perFolder >= MaxFilesPerFolder)
                    {
                        // 容量用尽后按目录聚合记一条，不再逐文件刷省略。
                        AddOmission(omitted, ref omittedOverflow, new JObject
                        {
                            ["path"] = RelativeOrLeaf(rootFull, folder.FullPath),
                            ["reason"] = "file_count_cap",
                            ["detail"] = (files.Count - fi) + " remaining file(s) skipped"
                        });
                        break;
                    }
                    OmittedFile(file, rootFull, utcNow, omitted, ref omittedOverflow, out string skip);
                    if (skip != null) continue;
                    if (!seenFiles.Add(file.FullName)) continue;
                    byte[] content = ReadSharedFile(file.FullName, MaxFileBytes, out string readError);
                    if (content == null)
                    {
                        AddOmission(omitted, ref omittedOverflow, new JObject
                        {
                            ["path"] = RelativeOrLeaf(rootFull, file.FullName),
                            ["reason"] = readError ?? "read_failed"
                        });
                        continue;
                    }
                    if (totalBytes + content.LongLength > MaxTotalBytes)
                    {
                        AddOmission(omitted, ref omittedOverflow, new JObject
                        {
                            ["path"] = RelativeOrLeaf(rootFull, file.FullName),
                            ["reason"] = "total_bytes_cap",
                            ["detail"] = "cap " + MaxTotalBytes + " bytes"
                        });
                        continue;
                    }
                    string logical = ReportLogicalPrefix + tag + "/" + SanitizeName(file.Name);
                    string placed;
                    try { placed = sink.Write(logical, content); }
                    catch (Exception ex)
                    {
                        AddOmission(omitted, ref omittedOverflow, new JObject
                        {
                            ["path"] = RelativeOrLeaf(rootFull, file.FullName),
                            ["reason"] = "write_failed", ["detail"] = ex.GetType().Name
                        });
                        continue;
                    }
                    string sha = Convert.ToHexString(SHA256.HashData(content));
                    totalBytes += content.LongLength;
                    filesTotal++;
                    perFolder++;
                    included.Add(new JObject
                    {
                        ["file"] = placed,
                        ["sha256"] = sha,
                        ["bytes"] = content.LongLength,
                        ["lastWriteUtc"] = file.LastWriteTimeUtc.ToString("O"),
                        ["origin"] = folder.Origin,
                        ["sourcePath"] = RelativeOrLeaf(rootFull, file.FullName),
                        ["session"] = folder.Ref != null ? folder.Ref.Session : null,
                        ["kind"] = folder.Ref != null ? folder.Ref.Kind : null,
                        ["failureReason"] = folder.Ref != null ? folder.Ref.Reason : null,
                        ["classification"] = folder.Ref != null ? folder.Ref.Classification : null,
                        ["exitCode"] = NumOrNull(folder.Ref != null ? folder.Ref.ExitCode : null),
                        ["documentGeneration"] = NumOrNull(
                            folder.Ref != null ? folder.Ref.DocumentGeneration : null),
                        ["browserVersion"] = folder.Ref != null ? folder.Ref.BrowserVersion : null,
                        ["recordedAtUtc"] = folder.Ref != null ? folder.Ref.AtUtc : null
                    });
                }
            }

            result.FilesIncluded = filesTotal;
            result.BytesIncluded = totalBytes;
            result.OmissionsRecorded = omitted.Count + omittedOverflow;

            // ---- 4) manifest：省略原因显式，哈希口径与 file-hashes.json 一致 ----
            JObject manifest = new JObject
            {
                ["version"] = 1,
                ["generatedAtUtc"] = utcNow.ToString("O"),
                ["sourceLog"] = "logs/webview-failures.jsonl",
                ["reportPathFields"] = new JArray(ReportPathFields),
                ["allowedRoots"] = new JArray(allowedRoots.Select(r2 => RelativeOrLeaf(rootFull, r2))),
                ["bounds"] = new JObject
                {
                    ["logTailBytes"] = MaxLogTailBytes,
                    ["logEntriesParsed"] = MaxLogEntriesParsed,
                    ["referencedFolders"] = MaxReferencedFolders,
                    ["enumeratePerFolder"] = MaxEnumeratePerFolder,
                    ["filesPerFolder"] = MaxFilesPerFolder,
                    ["filesTotal"] = MaxFilesTotal,
                    ["fileBytes"] = MaxFileBytes,
                    ["totalBytes"] = MaxTotalBytes,
                    ["maxAgeDays"] = MaxReportAge.TotalDays,
                    ["extensions"] = new JArray(AllowedExtensions)
                },
                ["failuresLog"] = new JObject
                {
                    ["included"] = result.LogIncluded,
                    ["bytes"] = result.LogBytes,
                    ["truncated"] = result.LogTruncated,
                    ["omittedReason"] = result.LogOmittedReason,
                    ["rotated"] = new JObject
                    {
                        ["file"] = "webview-failures.jsonl.1",
                        ["included"] = result.RotatedIncluded,
                        ["bytes"] = result.RotatedBytes,
                        ["omittedReason"] = result.RotatedOmittedReason
                    }
                },
                ["included"] = included,
                ["omitted"] = omitted
            };
            if (omittedOverflow > 0) manifest["omittedOverflow"] = omittedOverflow;
            byte[] manifestBytes = Encoding.UTF8.GetBytes(
                manifest.ToString(Newtonsoft.Json.Formatting.Indented));
            try { sink.Write(ManifestLogicalPath, manifestBytes); }
            catch (Exception ex) { AddWarning(result, "webview manifest write failed: " + ex.Message); }
            result.Manifest = manifest;

            // 摘要级 warnings（逐条已在 manifest 内）
            int shown = 0;
            foreach (JObject o in omitted.OfType<JObject>())
            {
                if (shown >= MaxWarnings) break;
                string reason = (string)o["reason"];
                string where = (string)o["path"] ?? (string)o["candidate"] ?? "?";
                AddWarning(result, "webview report omitted (" + reason + "): " + where);
                shown++;
            }
            if (omitted.Count > shown || omittedOverflow > 0)
            {
                AddWarning(result, "webview report omissions total="
                    + (omitted.Count + omittedOverflow) + " (see webview-failures manifest)");
            }
            return result;
        }

        // ---- 候选校验：必须规范化落在允许根内；不做任何 junction 跟随 ----

        private static string NormalizeCandidate(string raw, List<string> allowedRoots, out string reject)
        {
            reject = null;
            if (string.IsNullOrWhiteSpace(raw)) { reject = "invalid_path"; return null; }
            string full;
            try
            {
                if (!Path.IsPathRooted(raw)) { reject = "invalid_path"; return null; }
                full = Path.GetFullPath(raw).TrimEnd('\\', '/');
            }
            catch { reject = "invalid_path"; return null; }
            foreach (string allowed in allowedRoots)
            {
                if (string.Equals(full, allowed, StringComparison.OrdinalIgnoreCase) ||
                    full.StartsWith(allowed + "\\", StringComparison.OrdinalIgnoreCase))
                    return full;
            }
            reject = "outside_allowed_root";
            return null;
        }

        // 从候选目录向上逐级检查到项目根（含），任一环节为 reparse point 即拒收。
        // 边界必须贯穿允许根上方的已知 UDF/launcher/项目根祖先：这些目录被做成
        // junction 时字符串路径仍落在允许根内，但真实字节已越界，须记省略而非跟随。
        private static bool ChainHasReparsePoint(string dirPath, string projectRoot)
        {
            string current = dirPath;
            for (int i = 0; i < 64 && current != null; i++)
            {
                FileAttributes attrs;
                try { attrs = File.GetAttributes(current); }
                catch { return false; } // 不存在由后续 not_found 处理
                if ((attrs & FileAttributes.ReparsePoint) != 0) return true;
                if (string.Equals(current, projectRoot, StringComparison.OrdinalIgnoreCase))
                    return false;
                current = Path.GetDirectoryName(current);
            }
            return false;
        }

        // 文件级前置过滤；通过则 skip=null。
        private static void OmittedFile(FileInfo file, string rootFull, DateTime utcNow,
            JArray omitted, ref int omittedOverflow, out string skip)
        {
            skip = null;
            try
            {
                if ((file.Attributes & FileAttributes.ReparsePoint) != 0)
                {
                    skip = Record(file, rootFull, "reparse_point", null, omitted, ref omittedOverflow);
                    return;
                }
                string ext = file.Extension.ToLowerInvariant();
                if (Array.IndexOf(AllowedExtensions, ext) < 0)
                {
                    skip = Record(file, rootFull, "unsupported_extension", ext, omitted, ref omittedOverflow);
                    return;
                }
                if (utcNow - file.LastWriteTimeUtc > MaxReportAge)
                {
                    skip = Record(file, rootFull, "too_old", null, omitted, ref omittedOverflow);
                    return;
                }
                if (file.Length > MaxFileBytes)
                {
                    skip = Record(file, rootFull, "too_large",
                        file.Length + " > " + MaxFileBytes, omitted, ref omittedOverflow);
                    return;
                }
            }
            catch (Exception ex)
            {
                skip = Record(file, rootFull, "inspect_failed", ex.GetType().Name,
                    omitted, ref omittedOverflow);
            }
        }

        private static string Record(FileInfo file, string rootFull, string reason, string detail,
            JArray omitted, ref int omittedOverflow)
        {
            JObject o = new JObject
            {
                ["path"] = RelativeOrLeaf(rootFull, file.FullName),
                ["reason"] = reason
            };
            if (detail != null) o["detail"] = detail;
            AddOmission(omitted, ref omittedOverflow, o);
            return reason;
        }

        private static void AddOmission(JArray omitted, ref int overflow, JObject entry)
        {
            if (omitted.Count < MaxOmissionsRecorded) omitted.Add(entry);
            else overflow++;
        }

        private static void AddWarning(Result result, string warning)
        {
            if (result.Warnings.Count < MaxWarnings * 2) result.Warnings.Add(warning);
        }

        // ---- IO：全部共享读，容忍被占用/不完整 ----

        private static byte[] ReadSharedTail(string path, long maxBytes, out bool truncated, out string error)
        {
            truncated = false;
            error = null;
            try
            {
                if (!File.Exists(path)) { error = "log_missing"; return null; }
                using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete))
                {
                    long length = fs.Length;
                    long start = Math.Max(0, length - maxBytes);
                    fs.Seek(start, SeekOrigin.Begin);
                    if (start > 0)
                    {
                        truncated = true;
                        int b;
                        while ((b = fs.ReadByte()) >= 0 && b != '\n') { }
                    }
                    // 读循环累计上限：共享读期间文件仍可能被追加，绝不因增长超界。
                    using (MemoryStream ms = new MemoryStream())
                    {
                        byte[] buf = new byte[64 * 1024];
                        int n;
                        while (ms.Length < maxBytes &&
                            (n = fs.Read(buf, 0, (int)Math.Min(buf.Length, maxBytes - ms.Length))) > 0)
                            ms.Write(buf, 0, n);
                        // 仅当容量截停且仍有未读字节才算截断；恰好读满不算。
                        if (ms.Length >= maxBytes && fs.Position < fs.Length) truncated = true;
                        return ms.ToArray();
                    }
                }
            }
            catch { error = "log_unreadable"; return null; }
        }

        private static byte[] ReadSharedFile(string path, long maxBytes, out string error)
        {
            error = null;
            try
            {
                using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete))
                {
                    if (fs.Length > maxBytes) { error = "too_large"; return null; }
                    return ReadCapped(fs, maxBytes, out error);
                }
            }
            catch (FileNotFoundException) { error = "not_found"; return null; }
            catch (IOException) { error = "locked_or_unreadable"; return null; }
            catch (UnauthorizedAccessException) { error = "access_denied"; return null; }
            catch { error = "read_failed"; return null; }
        }

        // 读循环累计上限：打开时 Length 合法但共享读期间被追加仍按 too_large 省略。
        internal static byte[] ReadCapped(Stream fs, long maxBytes, out string error)
        {
            error = null;
            using (MemoryStream ms = new MemoryStream())
            {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = fs.Read(buf, 0, buf.Length)) > 0)
                {
                    if (ms.Length + n > maxBytes) { error = "too_large"; return null; }
                    ms.Write(buf, 0, n);
                }
                return ms.ToArray();
            }
        }

        private static string StringProp(JObject entry, string name)
        {
            JToken v = entry[name];
            return v != null && v.Type == JTokenType.String ? (string)v : null;
        }

        private static long? IntProp(JObject entry, string name)
        {
            JToken v = entry[name];
            return v != null && v.Type == JTokenType.Integer ? (long?)v.Value<long>() : null;
        }

        private static JToken NumOrNull(long? v)
        {
            return v.HasValue ? (JToken)new JValue(v.Value) : JValue.CreateNull();
        }

        private static string TimestampProp(JObject entry)
        {
            foreach (string field in TimestampFields)
            {
                string v = StringProp(entry, field);
                if (v != null) return v;
            }
            return null;
        }

        private static string RelativeOrLeaf(string rootFull, string fullPath)
        {
            try
            {
                if (fullPath.StartsWith(rootFull + "\\", StringComparison.OrdinalIgnoreCase) ||
                    fullPath.StartsWith(rootFull + "/", StringComparison.OrdinalIgnoreCase))
                    return fullPath.Substring(rootFull.Length + 1).Replace('\\', '/');
                if (string.Equals(fullPath, rootFull, StringComparison.OrdinalIgnoreCase)) return ".";
            }
            catch { }
            return Path.GetFileName(fullPath.TrimEnd('\\', '/')) ?? fullPath;
        }

        private static string SanitizeName(string name)
        {
            return System.Text.RegularExpressions.Regex.Replace(name ?? "", @"[^a-zA-Z0-9._\-]", "_");
        }
    }
}
