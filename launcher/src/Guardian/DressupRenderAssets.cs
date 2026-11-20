using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace CF7Launcher.Guardian
{
    internal static class DressupRenderAssets
    {
        // 保持对白既有版本协议：每个文件以文件名和 LF 作前缀，随后是原始字节。
        internal static string Version(string webRoot, params string[] consumerModules)
        {
            using var sha = SHA256.Create();
            using var digest = new CryptoStream(Stream.Null, sha, CryptoStreamMode.Write);
            Append(digest, Path.Combine(webRoot, "assets", "dressup", "manifest.json"));
            var modules = Path.Combine(webRoot, "modules");
            Append(digest, Path.Combine(modules, "asset-timeline.js"));
            Append(digest, Path.Combine(modules, "dressup-doll-renderer.js"));
            foreach (string module in consumerModules)
                Append(digest, Path.Combine(modules, module));
            digest.FlushFinalBlock();
            return Convert.ToHexString(sha.Hash).ToLowerInvariant();
        }

        private static void Append(Stream digest, string path)
        {
            string name = Path.GetFileName(path);
            digest.Write(Encoding.UTF8.GetBytes(name + "\n"));
            if (!File.Exists(path))
            {
                digest.Write(Encoding.UTF8.GetBytes("missing:" + name));
                return;
            }

            try
            {
                using var file = File.OpenRead(path);
                file.CopyTo(digest);
            }
            catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
            {
                digest.Write(Encoding.UTF8.GetBytes("unreadable:" + name));
            }
        }

        // 线上 ref 仍只描述外观，派生的 256px PNG 只在相同的渲染输入之间复用。
        internal static string LootPortraitDirectory(string webRoot)
        {
            string version = Version(webRoot, "merc-data.js", "merc-portrait-renderer.js", "doll-bake.js");
            return Path.GetFullPath(Path.Combine(webRoot, "..", "data", "doll-portraits", version));
        }
    }
}
