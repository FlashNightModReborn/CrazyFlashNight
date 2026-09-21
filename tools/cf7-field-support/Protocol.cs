using System.Buffers.Binary;
using System.Net.Security;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Cf7.FieldSupport;

internal static class Wire
{
    public const int MaxFrame = 1024 * 1024;
    public const int Chunk = 192 * 1024;
    public const int HeartbeatSeconds = 5;
    public const int LostSeconds = 90;
    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };
    public static JsonElement Data(object? data) => JsonSerializer.SerializeToElement(data, Json);
    public static string Id() => Guid.NewGuid().ToString("N");
    public static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    public static string FileHash(string path) { using var f = File.OpenRead(path); return Convert.ToHexString(SHA256.HashData(f)); }
    public static async Task Send(Stream stream, Packet packet, SemaphoreSlim gate, CancellationToken ct)
    {
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(packet, Json);
        if (bytes.Length > MaxFrame) throw new InvalidDataException("消息超过上限");
        await gate.WaitAsync(ct);
        try
        {
            byte[] size = new byte[4]; BinaryPrimitives.WriteInt32BigEndian(size, bytes.Length);
            await stream.WriteAsync(size, ct); await stream.WriteAsync(bytes, ct); await stream.FlushAsync(ct);
        }
        finally { gate.Release(); }
    }
    public static async Task<Packet> Read(Stream stream, CancellationToken ct)
    {
        byte[] size = new byte[4]; await stream.ReadExactlyAsync(size, ct);
        int n = BinaryPrimitives.ReadInt32BigEndian(size);
        if (n is < 2 or > MaxFrame) throw new InvalidDataException("消息长度无效");
        byte[] bytes = new byte[n]; await stream.ReadExactlyAsync(bytes, ct);
        using var parsed=JsonDocument.Parse(bytes);UniqueFields(parsed.RootElement);
        return parsed.RootElement.Deserialize<Packet>(Json) ?? throw new InvalidDataException("空消息");
    }
    public static void UniqueFields(JsonElement value)
    {
        if(value.ValueKind==JsonValueKind.Object)
        {
            var names=new HashSet<string>(StringComparer.Ordinal);
            foreach(var item in value.EnumerateObject()){if(!names.Add(item.Name))throw new InvalidDataException("JSON 包含重复字段");UniqueFields(item.Value);}
        }
        else if(value.ValueKind==JsonValueKind.Array)foreach(var item in value.EnumerateArray())UniqueFields(item);
    }
    public static X509Certificate2 Certificate()
    {
        using var rsa = RSA.Create(3072);
        var req = new CertificateRequest("CN=CF7 Field Support", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        req.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
        req.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection {new("1.3.6.1.5.5.7.3.1"),new("1.3.6.1.5.5.7.3.2")},false));
        using var cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddDays(1));
        // Schannel needs an OS key container. UserKeySet without PersistKeySet
        // creates a temporary user-protected container removed on Dispose.
        return X509CertificateLoader.LoadPkcs12(cert.Export(X509ContentType.Pfx), null, X509KeyStorageFlags.UserKeySet);
    }
    public static string Fingerprint(X509Certificate cert) => Hash(cert.GetRawCertData());
    public static string ShortFingerprint(string hex) => string.Join("-", Enumerable.Range(0, 8).Select(i => hex.Substring(i * 4, 4)));
}
internal sealed record Packet(string Id, string Method, JsonElement Data, bool Ok = true, string? Error = null);
internal sealed record Ticket(int Version, string SessionId, string Host, int Port, string CertificateSha256, string Secret, DateTimeOffset ExpiresAt, string Machine);
internal static class Fields
{
    public static string Text(this JsonElement e, string key) => e.TryGetProperty(key, out var x) && x.ValueKind == JsonValueKind.String ? x.GetString()! : throw new InvalidDataException("缺少字段：" + key);
    public static string Optional(this JsonElement e, string key, string fallback = "") => e.TryGetProperty(key, out var x) && x.ValueKind == JsonValueKind.String ? x.GetString()! : fallback;
    public static long Number(this JsonElement e, string key) => e.TryGetProperty(key, out var x) && x.TryGetInt64(out long n) ? n : throw new InvalidDataException("无效数字：" + key);
}
internal static class LocalState
{
    public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CF7FieldSupport");
    public static string PipeName => "cf7-field-" + Wire.Hash(Encoding.UTF8.GetBytes(WindowsIdentity.GetCurrent().User!.Value + ":" + System.Diagnostics.Process.GetCurrentProcess().SessionId))[..24];
    public static void PrivateDirectory(string path)
    {
        Directory.CreateDirectory(path);
        var acl = new DirectorySecurity(); acl.SetAccessRuleProtection(true, false);
        var inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
        acl.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User!, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
        acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
        new DirectoryInfo(path).SetAccessControl(acl);
    }
    public static void Save(string path, object data)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temp = path + "." + Wire.Id() + ".tmp";
        using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        { JsonSerializer.Serialize(stream, data, Wire.Json); stream.Flush(true); }
        File.Move(temp, path, true);
    }
    public static T Read<T>(string path)
    {
        using var parsed=JsonDocument.Parse(File.ReadAllText(path));Wire.UniqueFields(parsed.RootElement);
        return parsed.RootElement.Deserialize<T>(Wire.Json)??throw new InvalidDataException("无效文件");
    }
    public static string Under(string root, string relative)
    {
        if (string.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative) || relative.Contains(':')) throw new InvalidDataException("需要安全相对路径");
        foreach (string part in relative.Replace('\\', '/').Split('/'))
            if (part is "" or "." or ".." || part.EndsWith('.') || part.EndsWith(' ') || part.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || System.Text.RegularExpressions.Regex.IsMatch(part, @"^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                throw new InvalidDataException("路径片段无效");
        string full = Path.GetFullPath(Path.Combine(root, relative));
        if (!full.StartsWith(Path.GetFullPath(root).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("路径越界");
        Plain(full); return full;
    }
    public static void Plain(string path)
    {
        for (string? p = Path.GetFullPath(path); p != null; p = Path.GetDirectoryName(p))
            if ((File.Exists(p) || Directory.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("不支持符号链接或目录联接：" + p);
    }
}
