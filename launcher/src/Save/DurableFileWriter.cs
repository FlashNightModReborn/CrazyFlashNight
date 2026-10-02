using System;
using System.IO;
using System.Text;
using CF7Launcher.Guardian;

namespace CF7Launcher.Save
{
    internal sealed class FileCommitUnconfirmedException : IOException
    {
        internal FileCommitUnconfirmedException(string message, Exception error) : base(message, error) { }
    }

    /// <summary>同目录提交；替换前保留已刷盘的旧字节。调用方仍负责领域锁及结果裁决。</summary>
    internal static class DurableFileWriter
    {
        internal static void WriteAllText(string path, string text, Encoding encoding,
            Action<string, string> commitForTests = null)
        {
            path = Path.GetFullPath(path);
            byte[] bytes = encoding.GetBytes(text);
            string suffix = Guid.NewGuid().ToString("N");
            string temporary = path + ".tmp-" + suffix;
            string previous = path + ".previous-" + suffix;
            bool committed = false;
            bool hasPrevious = false;
            bool commitAttempted = false;
            try
            {
                WriteNew(temporary, bytes);
                if (File.Exists(path))
                {
                    // 独立副本先于 Replace：包括其部分失败状态，旧数据仍有恢复来源。
                    using (var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                    using (var output = new FileStream(previous, FileMode.CreateNew, FileAccess.Write,
                        FileShare.None, 4096, FileOptions.WriteThrough))
                    {
                        input.CopyTo(output);
                        output.Flush(true);
                    }
                    hasPrevious = true;
                    commitAttempted = true;
                    if (commitForTests != null) commitForTests(temporary, path);
                    else File.Replace(temporary, path, null, true);
                }
                else
                {
                    commitAttempted = true;
                    if (commitForTests != null) commitForTests(temporary, path);
                    else File.Move(temporary, path);
                }
                if (ReadMatch(path, bytes) != MatchResult.Match)
                    throw new IOException("Committed file readback not confirmed: " + path);
                committed = true;
            }
            catch (Exception error)
            {
                // 提交抛错可能已完成；先对账，避免把已提交事实报成未提交并诱发重放。
                MatchResult observed = ReadMatch(path, bytes);
                if (commitAttempted && observed == MatchResult.Match) committed = true;
                else
                {
                    // 读不出不等于未提交，也不能因 File.Exists 折叠访问错误而覆盖目标。
                    if (commitAttempted && observed == MatchResult.Unreadable)
                        throw new FileCommitUnconfirmedException("File commit unconfirmed: " + path
                            + (hasPrevious ? "; recovery copy=" + previous : ""), error);
                    if (hasPrevious && observed == MatchResult.Missing)
                    {
                        try { File.Move(previous, path); hasPrevious = false; }
                        catch (Exception restoreError)
                        {
                            LogManager.Log("[DurableFileWriter] recovery retained: " + previous
                                + " restore=" + restoreError.Message);
                        }
                    }
                    throw new IOException("File commit failed; prior data "
                        + (hasPrevious ? "retained at " + previous : "preserved at " + path), error);
                }
            }
            finally
            {
                DeleteOwned(temporary);
                if (committed || !hasPrevious) DeleteOwned(previous);
            }
        }

        private static void WriteNew(string path, byte[] bytes)
        {
            using (var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush(true);
            }
        }

        private enum MatchResult { Match, Different, Missing, Unreadable }

        private static MatchResult ReadMatch(string path, byte[] expected)
        {
            try
            {
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    if (stream.Length != expected.Length) return MatchResult.Different;
                    for (int i = 0; i < expected.Length; i++)
                        if (stream.ReadByte() != expected[i]) return MatchResult.Different;
                    return MatchResult.Match;
                }
            }
            catch (FileNotFoundException) { return MatchResult.Missing; }
            catch (DirectoryNotFoundException) { return MatchResult.Missing; }
            catch { return MatchResult.Unreadable; }
        }

        private static void DeleteOwned(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); }
            catch (Exception ex) { LogManager.Log("[DurableFileWriter] cleanup retained " + path + ": " + ex.Message); }
        }
    }
}
