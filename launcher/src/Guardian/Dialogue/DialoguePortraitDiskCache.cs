using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace CF7Launcher.Guardian.Dialogue
{
    /// <summary>
    /// 纸娃娃立绘 PNG 磁盘缓存：&lt;root&gt;/launcher/data/dialogue-portraits/&lt;64hex&gt;.png。
    /// 文件名即 DollKey（绑定完整归一外观+表情+rig/尺寸代数+清单与渲染器版本），
    /// 跨进程/内存逐出后可免去 Web 重合成。
    /// 边界：最多 128 张 / 64MiB，超界按最后写入时间逐出最旧；
    /// 只枚举/删除 64hex.png 形态的文件，目录内其余文件一律不碰。
    /// 线程模型：内部自带锁，读写由调用方放后台线程执行，永不阻塞 UI。
    /// </summary>
    internal sealed class DialoguePortraitDiskCache
    {
        internal const int MaxFiles = 128;
        internal const long MaxBytes = 64L * 1024 * 1024;
        internal const int MaxPngBytes = 8 * 1024 * 1024;

        private static readonly Regex KeyPattern =
            new Regex("^[0-9a-f]{64}$", RegexOptions.Compiled);
        private static readonly byte[] PngMagic = { 137, 80, 78, 71, 13, 10, 26, 10 };

        private readonly string _dir;
        private readonly object _gate = new object();

        internal DialoguePortraitDiskCache(string root)
        {
            _dir = Path.Combine(Path.GetFullPath(root), "launcher", "data", "dialogue-portraits");
        }

        internal string DirectoryPath { get { return _dir; } }

        /// <summary>仅接受 64 位小写 hex 的 DollKey 文件名；其余 key 一律 null。</summary>
        internal static bool IsValidKey(string key)
        {
            return key != null && KeyPattern.IsMatch(key);
        }

        private string PathFor(string key)
        {
            return IsValidKey(key) ? Path.Combine(_dir, key + ".png") : null;
        }

        /// <summary>命中返回新 Bitmap（调用方持所有权）；任何损坏/校验失败按 miss 返回 null。</summary>
        internal Bitmap TryLoad(string key, int renderSize)
        {
            string path = PathFor(key);
            if (path == null) return null;
            byte[] bytes;
            lock (_gate)
            {
                try {
                    if (new FileInfo(path).Length > MaxPngBytes) return null;
                    bytes = File.ReadAllBytes(path);
                }
                catch { return null; }
            }
            return DecodePng(bytes, renderSize);
        }

        /// <summary>真实位图校验：PNG 魔数 + IHDR 宽高 + GDI+ 全量解码复核尺寸与格式。</summary>
        internal static Bitmap DecodePng(byte[] bytes, int renderSize)
        {
            try
            {
                if (bytes == null || bytes.Length < 33 || bytes.Length > MaxPngBytes) return null;
                if (!bytes.Take(8).SequenceEqual(PngMagic)) return null;
                if (ReadBigEndian(bytes, 16) != renderSize || ReadBigEndian(bytes, 20) != renderSize) return null;
                using (var stream = new MemoryStream(bytes, false))
                using (var image = Image.FromStream(stream, true, true))
                {
                    if (image.Width != renderSize || image.Height != renderSize
                        || image.RawFormat.Guid != ImageFormat.Png.Guid) return null;
                    var bitmap = new Bitmap(image);
                    try { if (HasVisiblePixel(bitmap)) return bitmap; }
                    catch { bitmap.Dispose(); throw; }
                    bitmap.Dispose();
                    return null;
                }
            }
            catch { return null; }
        }

        private static bool HasVisiblePixel(Bitmap bitmap)
        {
            var data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                // 作者取景可能有大片透明留白；逐像素 GDI 调用会拖慢每次磁盘命中。
                var row = new byte[bitmap.Width * 4];
                for (int y = 0; y < bitmap.Height; y++)
                {
                    Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), row, 0, row.Length);
                    for (int alpha = 3; alpha < row.Length; alpha += 4)
                        if (row[alpha] > 8) return true;
                }
                return false;
            }
            finally { bitmap.UnlockBits(data); }
        }

        /// <summary>写入合法 key 的 PNG 字节（原子 tmp+move），随后执行边界回收；
        /// 任何失败静默返回 false，调用方仍走原 Web 路径。</summary>
        internal bool Store(string key, byte[] pngBytes, int renderSize)
        {
            string path = PathFor(key);
            if (path == null) return false;
            // 落盘前轻量复核：魔数+IHDR 尺寸，坏字节不进缓存目录。
            if (pngBytes == null || pngBytes.Length < 33 || pngBytes.Length > MaxPngBytes
                || !pngBytes.Take(8).SequenceEqual(PngMagic)
                || ReadBigEndian(pngBytes, 16) != renderSize
                || ReadBigEndian(pngBytes, 20) != renderSize) return false;
            lock (_gate)
            {
                try
                {
                    Directory.CreateDirectory(_dir);
                    string tmp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
                    try {
                        File.WriteAllBytes(tmp, pngBytes);
                        File.Move(tmp, path, true);
                    }
                    finally { if (File.Exists(tmp)) File.Delete(tmp); }
                    EnforceBounds();
                    return true;
                }
                catch { return false; }
            }
        }

        /// <summary>只枚举/删除本缓存形态（64hex.png）；非缓存文件与 .tmp 残留一律不动。</summary>
        private void EnforceBounds()
        {
            try
            {
                var files = new DirectoryInfo(_dir).EnumerateFiles("*.png")
                    .Where(f => KeyPattern.IsMatch(Path.GetFileNameWithoutExtension(f.Name)))
                    .OrderBy(f => f.LastWriteTimeUtc).ToList();
                long total = files.Sum(f => f.Length);
                int index = 0;
                int remaining = files.Count;
                while (index < files.Count
                    && (remaining > MaxFiles || total > MaxBytes))
                {
                    try {
                        long bytes = files[index].Length;
                        files[index].Delete();
                        total -= bytes;
                        remaining--;
                    } catch { }
                    index++;
                }
            }
            catch { }
        }

        private static int ReadBigEndian(byte[] b, int offset)
        {
            return (b[offset] << 24) | (b[offset + 1] << 16) | (b[offset + 2] << 8) | b[offset + 3];
        }
    }
}
