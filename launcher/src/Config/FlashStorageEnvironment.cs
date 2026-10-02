using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Config
{
    internal static class FlashStorageEnvironment
    {
        private static readonly object Gate = new object();
        private static string lastPreparedTemp;

        internal static string Prepare(ProcessStartInfo start, string roamingAppData = null)
        {
            string roaming = ResolveRoaming(roamingAppData);
            string directory = Path.Combine(roaming, "CF7FlashNight", "flash-temp");
            Directory.CreateDirectory(directory);
            string probe = Path.Combine(directory, ".write-probe-" + Guid.NewGuid().ToString("N"));
            string renamed = probe + ".committed";
            try
            {
                using (var stream = new FileStream(probe, FileMode.CreateNew, FileAccess.Write,
                    FileShare.None, 4096, FileOptions.WriteThrough))
                {
                    stream.WriteByte(0x37);
                    stream.Flush(true);
                }
                File.Move(probe, renamed);
                byte[] readback = File.ReadAllBytes(renamed);
                if (readback.Length != 1 || readback[0] != 0x37)
                    throw new IOException("Flash temporary directory readback failed.");
            }
            finally
            {
                CleanupProbe(probe);
                CleanupProbe(renamed);
            }
            // 同时覆盖两项，不依赖 Steam/启动 shell 的旧环境快照；不修改父进程或注册表。
            start.Environment["TEMP"] = directory;
            start.Environment["TMP"] = directory;
            lock (Gate) lastPreparedTemp = directory;
            return directory;
        }

        internal static JObject Snapshot(string roamingAppData = null)
        {
            var result = new JObject
            {
                ["processTemp"] = Environment.GetEnvironmentVariable("TEMP"),
                ["processTmp"] = Environment.GetEnvironmentVariable("TMP")
            };
            try { result["effectiveHostTemp"] = Path.GetTempPath(); }
            catch (Exception ex) { result["hostTempError"] = ex.GetType().Name; }
            try
            {
                string roaming = ResolveRoaming(roamingAppData);
                string root = Path.GetPathRoot(roaming);
                result["roamingAppData"] = roaming;
                result["sharedObjectsRoot"] = Path.Combine(roaming, "Macromedia", "Flash Player", "#SharedObjects");
                result["plannedFlashTemp"] = Path.Combine(roaming, "CF7FlashNight", "flash-temp");
                result["storagePathRoot"] = root;
                result["networkPath"] = roaming.StartsWith(@"\\", StringComparison.Ordinal);
                try { result["storageAvailableBytes"] = new DriveInfo(root).AvailableFreeSpace; }
                catch (Exception ex) { result["spaceQueryError"] = ex.GetType().Name; }
                lock (Gate) result["preparedFlashTemp"] = lastPreparedTemp;
            }
            catch (Exception ex) { result["pathError"] = ex.GetType().Name; }
            return result;
        }

        private static string ResolveRoaming(string supplied)
        {
            string value = supplied ?? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            if (string.IsNullOrWhiteSpace(value) || !Path.IsPathRooted(value))
                throw new IOException("Roaming AppData must resolve to an absolute path for Flash storage.");
            return Path.GetFullPath(value);
        }

        private static void CleanupProbe(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); }
            catch (Exception ex) { CF7Launcher.Guardian.LogManager.Log("[FlashStorage] probe cleanup retained: "
                + path + " error=" + ex.Message); }
        }
    }
}
