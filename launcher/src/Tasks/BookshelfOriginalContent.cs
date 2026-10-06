using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using CF7Launcher.Config;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>Read-only, one-movie content lease. No Flash command, CF7 save or reward access.</summary>
    internal sealed class BookshelfOriginalContent : IDisposable
    {
        internal const string Domain = "bookshelf-original", VirtualHost = "cf7-originals.local";
        internal const string Origin = "https://" + VirtualHost;
        private static readonly Regex Id = new Regex("^[A-Za-z0-9._~-]{1,128}$");
        private static readonly Dictionary<string, string> MovieHashes = new Dictionary<string, string> {
            ["1-cn"] = "aa1cb17a60b9efaffe8e969bb33d77342657728af0203f8bb0b5fcf07b145a00",
            ["2-cn"] = "c3ff79788acaa84454211b2a4617d72854f7d47113c177d8cc681c648835f026",
            ["2-en"] = "031123f433e89590a5de88ff8df6f4b0dbe04cea0f582e6fba762ee11e7639ee",
            ["3-cn"] = "fc387f7786f5470867581b80a9ca2377ac41757aa53daa92b2cc69a0ef196119",
            ["3-en"] = "0fdd6beffd01a98fdedc81d146fa71b1fcd40ca2f8dfb60c88f59ca32f32147d",
            ["4-cn"] = "88bfe0f3931547a051f6f8b6711c9c552a30a9303cb5dc89cf0716054d165b02",
            ["4-en"] = "e6693ecb7af2b759a4bd695f4905f0288b40124499de53f94ba997aef46c1362",
            ["5-cn"] = "f36eaed723b45cbffbf2d6a769aae218dc524b45605374d5ed622cb89647da77",
            ["5-en"] = "40d15725719c1fda4cc6c54ebfd968b289dba604dbb34e34b7e8eeb753fd6c00",
            ["6-cn"] = "b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01",
            ["6-en"] = "eb9555a8f634b2e212a4aac0371bb0529ead4b270aa75693161e75250fe39f47"
        };
        internal static readonly string[] RuffleFiles = {
            "ruffle.js", "core.ruffle.8700c6b0144208de9d1b.js", "core.ruffle.99037c3e46986c91597b.js",
            "2ff4ebe4b64161970b9a.wasm", "a92f6442b0f55013a937.wasm"
        };
        private sealed class Lease
        {
            public string Session, Instance, Token, Language, DocumentPath;
            public int Chapter;
            public byte[] Movie;
            public CollectionAccess Account;
        }
        internal sealed class Resource
        {
            public int Status;
            public byte[] Bytes;
            public string Mime;
        }
        private readonly string _root;
        private readonly Func<string, string, bool> _admitted;
        private readonly Func<CollectionAccess> _access;
        private readonly Func<string, string, int, string, byte[]> _readMovie;
        private readonly object _gate = new object();
        private readonly HashSet<string> _calls = new HashSet<string>();
        private readonly Queue<string> _recent = new Queue<string>();
        private Lease _lease;
        private int _generation;
        private bool _preparing, _disposed;

        internal BookshelfOriginalContent(string root, Func<string, string, bool> admitted,
            Func<CollectionAccess> access = null, Func<string, string, int, string, byte[]> readMovie = null)
        { _root = Path.GetFullPath(root); _admitted = admitted; _access = access ?? SteamCollectionAccess.CreateReader(_root);
            _readMovie = readMovie ?? ReadMovie; }

        private static bool SameSource(CollectionAccess left, CollectionAccess right)
            => left.IsDevelopment == right.IsDevelopment && left.SteamId == right.SteamId
                && left.AccountNamespace == right.AccountNamespace
                && string.Equals(left.InstallDirectory, right.InstallDirectory, StringComparison.OrdinalIgnoreCase);

        internal static bool IsOverlaySource(string source) => Uri.TryCreate(source, UriKind.Absolute, out var uri)
            && uri.Scheme == "https" && uri.Host == "overlay.local" && uri.IsDefaultPort
            && uri.AbsolutePath == "/overlay.html" && uri.UserInfo == "";
        private static bool Exact(JObject value, params string[] keys) => value != null
            && value.Count == keys.Length && keys.All(k => value.Property(k) != null);
        private static string Text(JToken token) => token?.Type == JTokenType.String ? token.Value<string>() : null;
        private static JObject Failure(string error) => new JObject { ["success"] = false, ["error"] = error };

        internal async Task<JObject> ExecuteAsync(JObject request)
        {
            string instance = Text(request?["panelInstanceId"]), call = Text(request?["callId"]), cmd = Text(request?["cmd"]);
            if (!Exact(request, "type", "panel", "domain", "cmd", "callId", "panelInstanceId", "payload")
                || Text(request["type"]) != "panel" || Text(request["panel"]) != "bookshelf" || Text(request["domain"]) != Domain
                || instance == null || !Id.IsMatch(instance) || call == null || !Id.IsMatch(call)) return Failure("invalid_owner");
            var payload = request["payload"] as JObject;
            if (cmd != "prepare" && cmd != "release") return Failure("unsupported_cmd");
            if (!Exact(payload, cmd == "prepare" ? new[] { "v", "token", "chapter", "language" } : new[] { "v", "session" })
                || payload["v"]?.Type != JTokenType.Integer || payload["v"].ToString(Newtonsoft.Json.Formatting.None) != "1") return Failure("invalid_payload");
            lock (_gate)
            {
                if (_disposed) return Failure("panel_instance_expired");
                if (!_calls.Add(call)) return Failure("duplicate_request");
                _recent.Enqueue(call); if (_recent.Count > 128) _calls.Remove(_recent.Dequeue());
                if (cmd == "release")
                {
                    if (!Guid.TryParseExact(Text(payload["session"]), "D", out _)) return Failure("invalid_payload");
                    if (_lease?.Instance == instance && _lease.Session == Text(payload["session"])) Revoke();
                    return new JObject { ["success"] = true };
                }
            }
            string token = Text(payload["token"]), language = Text(payload["language"]);
            if (payload["chapter"]?.Type != JTokenType.Integer || !int.TryParse(payload["chapter"].ToString(), out int chapter)
                || token == null || !token.StartsWith("bookshelf.", StringComparison.Ordinal)
                || !Id.IsMatch(token) || !MovieHashes.ContainsKey(chapter + "-" + language)) return Failure("invalid_payload");
            int epoch;
            lock (_gate)
            {
                if (_preparing) return Failure("busy");
                _preparing = true; epoch = ++_generation; _lease = null;
            }
            try
            {
                if (_admitted == null || !_admitted(instance, token)) return Failure("context_unavailable");
                CollectionAccess account = null;
                if (chapter != 1)
                {
                    account = _access();
                    if (account == null || !account.Ready) return Failure(account?.Error ?? "steam_unavailable");
                }
                byte[] movie = await Task.Run(() => _readMovie(_root, account?.InstallDirectory, chapter, language));
                if (!_admitted(instance, token)) return Failure("context_unavailable");
                if (chapter != 1)
                {
                    var current = _access();
                    if (current == null || !current.Ready) return Failure(current?.Error ?? "steam_unavailable");
                    if (!SameSource(current, account))
                        return Failure("account_changed");
                    account = current;
                }
                lock (_gate)
                {
                    if (_disposed || epoch != _generation) return Failure("panel_instance_expired");
                    string session = Guid.NewGuid().ToString("D");
                    var lease = new Lease { Session = session, Instance = instance, Token = token, Movie = movie,
                        Chapter = chapter, Language = language, Account = account,
                        DocumentPath = "/player/" + (chapter == 1 ? "local" : account.AccountNamespace)
                            + "/cf" + chapter + "-" + language + "/player.html" };
                    _lease = lease;
                    return new JObject { ["success"] = true, ["session"] = session, ["origin"] = Origin,
                        ["playerUrl"] = Origin + lease.DocumentPath + "#" + session };
                }
            }
            catch (FileNotFoundException) { return Failure("content_missing"); }
            catch (DirectoryNotFoundException) { return Failure("content_missing"); }
            catch (InvalidDataException) { return Failure("content_changed"); }
            catch (Exception) { return Failure("content_unavailable"); }
            finally { lock (_gate) _preparing = false; }
        }

        internal void Revoke() { lock (_gate) { _generation++; _lease = null; } }
        public void Dispose() { lock (_gate) { _disposed = true; Revoke(); } }

        internal bool IsPlayerNavigation(string url)
        {
            lock (_gate) return !_disposed && _lease != null && Uri.TryCreate(url, UriKind.Absolute, out var uri)
                && uri.Scheme == "https" && uri.Host == VirtualHost && uri.IsDefaultPort && uri.UserInfo == ""
                && uri.Query == "" && uri.AbsolutePath == _lease.DocumentPath
                && uri.Fragment == "#" + _lease.Session;
        }

        internal Resource Resolve(string url, string method)
        {
            var denied = new Resource { Status = 404, Bytes = Array.Empty<byte>(), Mime = "text/plain" };
            if (method != "GET" || !Uri.TryCreate(url, UriKind.Absolute, out var uri)
                || uri.Scheme != "https" || uri.Host != VirtualHost || !uri.IsDefaultPort
                || uri.UserInfo != "" || uri.Query != "" || uri.Fragment != ""
                || uri.AbsolutePath.Contains('%') || uri.AbsolutePath.Contains('\\')) return denied;
            Lease lease;
            lock (_gate) lease = _lease;
            if (lease == null || !_admitted(lease.Instance, lease.Token)) return denied;
            if (lease.Chapter != 1)
            {
                var current = _access();
                if (current == null || !current.Ready || !SameSource(current, lease.Account)) { Revoke(); return denied; }
                // DLC/identity compatibility bytes always reflect the authenticated live client.
                lease.Account = current;
            }
            lock (_gate)
            {
                if (_disposed || !ReferenceEquals(lease, _lease)) return denied;
                string path = uri.AbsolutePath, session = "/session/" + lease.Session + "/";
                if (path == lease.DocumentPath) return FileResource("launcher/web/modules/bookshelf/original/player.html", "text/html; charset=utf-8");
                if (path == "/player.js") return FileResource("launcher/web/modules/bookshelf/original/player.js", "text/javascript; charset=utf-8");
                if (path == session + "manifest.json")
                    return Bytes(Encoding.UTF8.GetBytes(new JObject { ["chapter"] = lease.Chapter, ["language"] = lease.Language,
                        ["swfFileName"] = "cf" + lease.Chapter + "-" + lease.Language + ".swf",
                        ["movieUrl"] = Origin + session + "movie.swf", ["baseUrl"] = Origin + session + "exes/" }
                        .ToString(Newtonsoft.Json.Formatting.None)), "application/json");
                if (path == session + "movie.swf") return Bytes(lease.Movie, "application/x-shockwave-flash");
                if (path == session + "exes/SteamID.txt" && lease.Account != null && !lease.Account.IsDevelopment)
                    return Bytes(IdentityBytes(lease.Account), "text/plain; charset=utf-16le");
                if (path.StartsWith("/ruffle/", StringComparison.Ordinal) && RuffleFiles.Contains(path.Substring(8)))
                    return FileResource("flashswf/_ruffle/" + path.Substring(8), path.EndsWith(".wasm") ? "application/wasm" : "text/javascript");
                return denied;
            }
        }
        private Resource FileResource(string relative, string mime) => Bytes(File.ReadAllBytes(SafeFile(_root, relative)), mime);
        private static Resource Bytes(byte[] bytes, string mime) => new Resource { Status = 200, Bytes = bytes, Mime = mime };
        internal static byte[] IdentityBytes(CollectionAccess account)
        {
            if (account == null || account.IsDevelopment || account.SteamId == 0)
                throw new InvalidOperationException("Steam identity requires an authenticated account");
            string name = new string((account.PersonaName ?? "").Take(256).Select(c => c == ';' || c == '=' || char.IsControl(c) ? ' ' : c).ToArray());
            string value = "SteamID=" + account.SteamId + ";steamName=" + name + ";myDLC=" + (account.DlcInstalled ? "1" : "0");
            return Encoding.Unicode.GetPreamble().Concat(Encoding.Unicode.GetBytes(value)).ToArray();
        }
        internal static string SafeFile(string root, string relative)
        {
            string path = Path.GetFullPath(root);
            if (relative.Split('/').Any(p => string.IsNullOrEmpty(p) || p == "." || p == ".." || p.Contains('\\') || p.Contains(':')))
                throw new InvalidDataException("Unsafe content path");
            foreach (string part in relative.Split('/'))
            {
                path = Path.Combine(path, part);
                if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Content reparse point");
            }
            return path;
        }
        internal static byte[] ReadMovie(string root, string install, int chapter, string language)
        {
            if (!MovieHashes.TryGetValue(chapter + "-" + language, out var hash)) throw new InvalidDataException("Unknown chapter");
            string path = chapter == 1 ? SafeFile(root, "flashswf/originals/crazy-flasher-1.swf")
                : SafeFile(install, "exes/crazyflasher" + chapter + "-" + language + "_secure.exe");
            using var source = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            byte[] movie = chapter == 1 ? ReadRange(source, 0, checked((int)source.Length)) : ReadProjector(source);
            if (movie.Length < 8 || movie[0] != 'F' || movie[1] != 'W' || movie[2] != 'S'
                || movie[3] != (chapter == 1 ? 5 : 8) || BitConverter.ToUInt32(movie, 4) != movie.Length
                || !Convert.ToHexString(SHA256.HashData(movie)).Equals(hash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Unsupported movie version");
            return movie;
        }
        internal static byte[] ReadProjector(Stream source)
        {
            if (!source.CanSeek || source.Length < 16 || source.Length > 64 * 1024 * 1024) throw new InvalidDataException("Projector size");
            source.Position = 0;
            if (source.ReadByte() != 'M' || source.ReadByte() != 'Z') throw new InvalidDataException("Projector header");
            var footer = ReadRange(source, source.Length - 8, 8);
            uint size = BitConverter.ToUInt32(footer, 4);
            if (BitConverter.ToUInt32(footer, 0) != 0xfa123456 || size < 8 || size > 24 * 1024 * 1024
                || size >= source.Length - 8) throw new InvalidDataException("Projector footer");
            return ReadRange(source, source.Length - 8 - size, (int)size);
        }
        private static byte[] ReadRange(Stream source, long offset, int count)
        {
            if (count < 8 || count > 24 * 1024 * 1024 || offset < 0 || offset + count > source.Length)
                throw new InvalidDataException("Movie range");
            source.Position = offset; var data = new byte[count]; source.ReadExactly(data); return data;
        }
    }
}
