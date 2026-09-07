using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace CF7Launcher.Data
{
    /// <summary>固定工具、固定参数的有界适配；不接受浏览器命令行或脚本路径。</summary>
    public static class MapAssetTools
    {
        private static string Python()
        {
            string installed = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Python");
            if (Directory.Exists(installed)) foreach (var directory in Directory.GetDirectories(installed, "Python*").OrderByDescending(p => p, StringComparer.Ordinal))
            {
                string file = Path.Combine(directory, "python.exe"); if (File.Exists(file)) return file;
            }
            foreach (string directory in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
            {
                if (string.IsNullOrWhiteSpace(directory) || directory.Contains("WindowsApps", StringComparison.OrdinalIgnoreCase)) continue;
                string file = Path.Combine(directory.Trim('"'), "python.exe"); if (File.Exists(file)) return file;
            }
            throw new InvalidOperationException("该图片需要保留透明像素的原始颜色。请安装物品素材工作台已有的 Python / Pillow 依赖后重试。");
        }
        private static async Task<string> ReadBounded(StreamReader reader, CancellationToken token)
        {
            var text = new StringBuilder(); var buffer = new char[4096];
            while (true)
            {
                int read = await reader.ReadAsync(buffer.AsMemory(), token).ConfigureAwait(false); if (read == 0) return text.ToString();
                if (text.Length + read > 128 * 1024) throw new IOException("素材工具输出超过边界。");
                text.Append(buffer, 0, read);
            }
        }
        public static void Run(string executable, string[] arguments, string workingDirectory, int timeoutSeconds)
        {
            var info = new ProcessStartInfo(executable) { WorkingDirectory = workingDirectory, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
            foreach (var argument in arguments) info.ArgumentList.Add(argument);
            using var process = new Process { StartInfo = info };
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
            if (!process.Start()) throw new IOException("素材工具无法启动。");
            try
            {
                var stdout = ReadBounded(process.StandardOutput, timeout.Token); var stderr = ReadBounded(process.StandardError, timeout.Token);
                Task.WhenAll(stdout, stderr, process.WaitForExitAsync(timeout.Token)).GetAwaiter().GetResult();
                if (process.ExitCode != 0) throw new IOException("素材工具失败：" + (stderr.Result.Length > 1200 ? stderr.Result.Substring(0, 1200) : stderr.Result));
            }
            finally
            {
                if (!process.HasExited) { process.Kill(true); process.WaitForExit(5000); }
            }
        }
        public static byte[] EncodeExact(string root, byte[] source)
        {
            string directory = MapProjectFiles.Resolve(root, "tmp/map-workbench/image-codec/" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            string input = Path.Combine(directory, "input.image"), output = Path.Combine(directory, "output.webp");
            try
            {
                MapProjectFiles.Atomic(input, source);
                Run(Python(), new[] { MapProjectFiles.Resolve(root, "tools/convert-map-assets-webp.py"), "--pair", input, output, "--method", "6" }, root, 60);
                using var stream = new FileStream(output, FileMode.Open, FileAccess.Read, FileShare.Read);
                MapRuleEvaluator.Need(stream.Length > 0 && stream.Length <= MapAssetCodec.MaxBytes, "精确 WebP 产物大小不正确。");
                var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes); return bytes;
            }
            finally
            {
                foreach (string file in new[] { input, output }) if (File.Exists(file)) { MapProjectFiles.PlainPath(file); File.Delete(file); }
                if (!Directory.EnumerateFileSystemEntries(directory).Any()) Directory.Delete(directory);
            }
        }
    }
}
