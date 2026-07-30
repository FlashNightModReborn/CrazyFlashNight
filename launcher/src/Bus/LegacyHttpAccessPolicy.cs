using System;
using System.IO;
using System.Net;
using System.Globalization;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Bus
{
    /// <summary>
    /// Process-lifecycle credential for the legacy localhost HTTP compatibility
    /// surface. This is deliberately separate from Agent Runtime rendezvous:
    /// it prevents browser-origin/ambient localhost calls from bypassing the
    /// new principal boundary while existing trusted automation migrates.
    /// </summary>
    public sealed class LegacyHttpAccessPolicy : IDisposable
    {
        public const string HeaderName = "X-CF7-Automation-Token";

        private const int TokenBytes = 32;
        private readonly byte[] _token;
        private readonly string _credentialFilePath;
        private readonly string _credentialFileIdentity;
        private bool _disposed;

        private LegacyHttpAccessPolicy(
            byte[] token,
            string credentialFilePath,
            string credentialFileIdentity)
        {
            _token = token;
            _credentialFilePath = credentialFilePath;
            _credentialFileIdentity = credentialFileIdentity;
        }

        public string CredentialFilePath
        {
            get { return _credentialFilePath; }
        }

        public static LegacyHttpAccessPolicy DenyAll()
        {
            return new LegacyHttpAccessPolicy(null, null, null);
        }

        public static LegacyHttpAccessPolicy Create(string projectRoot)
        {
            if (string.IsNullOrWhiteSpace(projectRoot))
                throw new ArgumentException("projectRoot is required", "projectRoot");

            byte[] token = RandomNumberGenerator.GetBytes(TokenBytes);
            string tokenText = ToBase64Url(token);
            string lifecycleId = ToBase64Url(RandomNumberGenerator.GetBytes(16));
            string rootHash = ComputeProjectRootHash(projectRoot);
            string localAppData = Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData))
                throw new InvalidOperationException("LOCALAPPDATA is unavailable");

            string directory = Path.Combine(
                localAppData,
                "CF7FlashNight",
                "agent-runtime",
                "v1",
                rootHash);
            EnsureCurrentUserOnlyDirectory(directory);

            int pid = Environment.ProcessId;
            long processStartUtcTicks = System.Diagnostics.Process
                .GetCurrentProcess()
                .StartTime
                .ToUniversalTime()
                .Ticks;
            var document = new JObject
            {
                ["v"] = 1,
                ["kind"] = "legacy_http_automation",
                ["pid"] = pid,
                ["processStartUtcTicks"] = processStartUtcTicks.ToString(
                    CultureInfo.InvariantCulture),
                ["lifecycleId"] = lifecycleId,
                ["header"] = HeaderName,
                ["token"] = tokenText,
                ["capabilities"] = new JArray
                {
                    "legacy.console",
                    "legacy.status",
                    "legacy.task",
                    "legacy.shutdown",
                    "legacy.save_push",
                    "legacy.logs",
                    "legacy.diagnostic"
                }
            };
            string body = document.ToString(Formatting.None);
            string path = Path.Combine(directory, "legacy-http-credential.json");
            AtomicWrite(path, body);
            return new LegacyHttpAccessPolicy(token, path, body);
        }

        public bool IsBrowserOriginRequest(HttpListenerRequest request)
        {
            if (request == null) return true;
            return !string.IsNullOrWhiteSpace(request.Headers["Origin"]);
        }

        public bool IsAuthorized(HttpListenerRequest request)
        {
            if (_disposed || request == null || _token == null)
                return false;
            if (IsBrowserOriginRequest(request))
                return false;

            string presented = request.Headers[HeaderName];
            byte[] candidate;
            if (!TryDecodeBase64Url(presented, out candidate))
                return false;
            try
            {
                return candidate.Length == _token.Length
                    && CryptographicOperations.FixedTimeEquals(candidate, _token);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(candidate);
            }
        }

        public static bool IsPrivilegedPath(string path)
        {
            return string.Equals(path, "/console", StringComparison.Ordinal)
                || string.Equals(path, "/status", StringComparison.Ordinal)
                || string.Equals(path, "/task", StringComparison.Ordinal)
                || string.Equals(path, "/shutdown", StringComparison.Ordinal)
                || string.Equals(path, "/save-push", StringComparison.Ordinal)
                || string.Equals(path, "/logs", StringComparison.Ordinal)
                || string.Equals(path, "/diagnostic", StringComparison.Ordinal);
        }

        internal static string ComputeProjectRootHash(string projectRoot)
        {
            string canonical = Path.GetFullPath(projectRoot)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                .ToUpperInvariant();
            byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
            var value = new StringBuilder(32);
            for (int i = 0; i < 16; i++)
                value.Append(hash[i].ToString("x2"));
            return value.ToString();
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            if (_token != null)
                CryptographicOperations.ZeroMemory(_token);
            if (string.IsNullOrWhiteSpace(_credentialFilePath)
                || string.IsNullOrEmpty(_credentialFileIdentity))
            {
                return;
            }

            try
            {
                if (!File.Exists(_credentialFilePath)) return;
                string current = File.ReadAllText(_credentialFilePath, Encoding.UTF8);
                if (string.Equals(
                    current,
                    _credentialFileIdentity,
                    StringComparison.Ordinal))
                {
                    File.Delete(_credentialFilePath);
                }
            }
            catch
            {
                // Shutdown must continue. A stale credential is still bound to
                // the old PID/start time and becomes invalid with that process.
            }
        }

        private static void EnsureCurrentUserOnlyDirectory(string path)
        {
            Directory.CreateDirectory(path);
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                SecurityIdentifier sid = identity.User;
                if (sid == null)
                    throw new InvalidOperationException("Current Windows SID is unavailable");

                var security = new DirectorySecurity();
                security.SetOwner(sid);
                security.SetAccessRuleProtection(true, false);
                security.AddAccessRule(
                    new FileSystemAccessRule(
                        sid,
                        FileSystemRights.FullControl,
                        InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                        PropagationFlags.None,
                        AccessControlType.Allow));
                new DirectoryInfo(path).SetAccessControl(security);
            }
        }

        private static void AtomicWrite(string path, string body)
        {
            string directory = Path.GetDirectoryName(path);
            string temp = Path.Combine(
                directory,
                "." + Path.GetFileName(path) + "." + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                File.WriteAllText(temp, body, new UTF8Encoding(false));
                File.Move(temp, path, true);
            }
            finally
            {
                try
                {
                    if (File.Exists(temp)) File.Delete(temp);
                }
                catch { }
            }
        }

        private static string ToBase64Url(byte[] value)
        {
            return Convert.ToBase64String(value)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }

        private static bool TryDecodeBase64Url(string value, out byte[] bytes)
        {
            bytes = null;
            if (string.IsNullOrWhiteSpace(value) || value.Length > 128)
                return false;
            string normalized = value.Replace('-', '+').Replace('_', '/');
            int remainder = normalized.Length % 4;
            if (remainder == 1) return false;
            if (remainder == 2) normalized += "==";
            else if (remainder == 3) normalized += "=";
            try
            {
                bytes = Convert.FromBase64String(normalized);
                return true;
            }
            catch (FormatException)
            {
                return false;
            }
        }
    }
}
