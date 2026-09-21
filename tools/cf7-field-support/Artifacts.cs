using System.IO.Compression;
using System.Text;
using System.Text.Json;

namespace Cf7.FieldSupport;

internal sealed record FileChange(string Id, string Target, string Backup, string OriginalHash, string InstalledHash, string State);
internal sealed record Upload(string Id, string Name, long Size, string Sha256);
internal sealed class Artifacts
{
    private readonly string root;
    private readonly string game;
    private readonly Dictionary<string,Upload> uploads=new();
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string,FileChange> changes=new();
    private readonly CancellationToken cancellation;
    public Artifacts(string root,string game,CancellationToken cancellation=default) {this.root=root;this.game=Path.GetFullPath(game);this.cancellation=cancellation;}
    public object Changes => changes.Values.ToArray();
    public object Begin(JsonElement data)
    {
        string id=data.Text("id"),name=data.Text("name"),hash=data.Text("sha256"); long size=data.Number("size");
        if(!System.Text.RegularExpressions.Regex.IsMatch(id,"^[a-f0-9]{32}$") || !IsHash(hash) || size is < 0 or > 2147483648) throw new InvalidDataException("上传身份或大小无效");
        string path=LocalState.Under(Path.Combine(root,"uploads"),id+"/"+name);
        if(Path.GetFileName(name)!=name) throw new InvalidDataException("上传名称必须是单个文件名");
        var entry=new Upload(id,name,size,hash.ToUpperInvariant());
        if(uploads.TryGetValue(id,out var old) && old!=entry) throw new InvalidDataException("上传 ID 已用于其他内容");
        uploads[id]=entry; Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        return new {id,offset=File.Exists(path+".partial")?new FileInfo(path+".partial").Length:0};
    }
    public object Chunk(JsonElement data)
    {
        var up=uploads[data.Text("id")]; var path=Path.Combine(root,"uploads",up.Id,up.Name)+".partial";
        var bytes=Convert.FromBase64String(data.Text("bytes")); long offset=data.Number("offset");
        if(bytes.Length>Wire.Chunk || offset<0 || offset+bytes.Length>up.Size) throw new InvalidDataException("分块范围无效");
        using var file=new FileStream(path,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
        if(file.Length!=offset) throw new InvalidDataException("偏移不匹配，请先查询上传状态");
        file.Position=offset;file.Write(bytes);file.Flush(true);return new {offset=file.Length};
    }
    public object Complete(JsonElement data)
    {
        var up=uploads[data.Text("id")];var path=Path.Combine(root,"uploads",up.Id,up.Name);
        if(File.Exists(path)) return new {id=up.Id,path,sha256=Wire.FileHash(path)};
        if(up.Size==0 && !File.Exists(path+".partial")) File.WriteAllBytes(path+".partial",[]);
        if(new FileInfo(path+".partial").Length!=up.Size || Wire.FileHash(path+".partial")!=up.Sha256) throw new InvalidDataException("上传不完整或哈希不符，未发布文件");
        cancellation.ThrowIfCancellationRequested();File.Move(path+".partial",path);return new {id=up.Id,path,sha256=up.Sha256};
    }
    public string Uploaded(string id)
    {
        var up=uploads[id];string path=Path.Combine(root,"uploads",id,up.Name);
        if(!File.Exists(path) || Wire.FileHash(path)!=up.Sha256) throw new InvalidDataException("上传尚未完成或内容改变");
        return path;
    }
    public object Replace(JsonElement data)
    {
        RequireGameStopped(game);
        string source=Uploaded(data.Text("uploadId")),relative=data.Text("target").Replace('\\','/');
        // This wrapper is intentionally narrower than the explicitly authorized shell.
        if(relative.Split('/').Any(p=>p.Equals("saves",StringComparison.OrdinalIgnoreCase) || p.Equals("#SharedObjects",StringComparison.OrdinalIgnoreCase) || p.Equals(".git",StringComparison.OrdinalIgnoreCase)) ||
           relative.StartsWith("runtime/",StringComparison.OrdinalIgnoreCase) || relative.EndsWith(".sol",StringComparison.OrdinalIgnoreCase) || relative.Equals("CRAZYFLASHER7MercenaryEmpire.exe",StringComparison.OrdinalIgnoreCase) || relative.Equals("config/build/runtime-release-consensus.json",StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("通用替换不允许存档、正式 runtime 或发布权威文件");
        string target=LocalState.Under(game,relative),expected=data.Text("expectedSha256").ToUpperInvariant();
        if(!File.Exists(target) || Wire.FileHash(target)!=expected) throw new InvalidDataException("目标已漂移或不存在，拒绝替换");
        if(changes.Values.Any(x=>x.Target==target && x.State!="restored")) throw new InvalidOperationException("该目标有尚未恢复的替换");
        string id=Wire.Id(),backup=Path.Combine(root,"backups",id+".original");Directory.CreateDirectory(Path.GetDirectoryName(backup)!);
        File.Copy(target,backup);if(Wire.FileHash(backup)!=expected) throw new IOException("备份校验失败");
        var change=new FileChange(id,target,backup,expected,Wire.FileHash(source),"prepared");changes[id]=change;SaveChanges();
        using(var original=new FileStream(target,FileMode.Open,FileAccess.Read,FileShare.Read|FileShare.Delete))
        {
            if(Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(original))!=expected) throw new IOException("替换前目标再次改变");
            string staged=target+".cf7-"+id;File.Copy(source,staged);cancellation.ThrowIfCancellationRequested();File.Replace(staged,target,null);
        }
        changes[id]=change with {State="installed"};SaveChanges();return changes[id];
    }
    public object Restore(string id)
    {
        RequireGameStopped(game);
        if(!changes.TryGetValue(id,out var change)) throw new InvalidOperationException("没有本会话登记的变更");
        cancellation.ThrowIfCancellationRequested();var result=RestoreRecord(change);changes[id]=result;SaveChanges();return result;
    }
    public static FileChange RestoreRecord(FileChange change)
    {
        LocalState.Plain(change.Target);LocalState.Plain(change.Backup);
        if(change.State=="restored") return change;
        if(!File.Exists(change.Backup) || Wire.FileHash(change.Backup)!=change.OriginalHash) throw new IOException("原件备份缺失或已改变");
        if(!File.Exists(change.Target))return change with {State="conflict"};
        string currentHash=Wire.FileHash(change.Target);
        // A prepared replacement may never have been applied. Matching original bytes
        // reconcile that exact file without writing or overwriting a later difference.
        if(currentHash==change.OriginalHash)return change with {State="restored"};
        if(currentHash!=change.InstalledHash) return change with {State="conflict"};
        using var current=new FileStream(change.Target,FileMode.Open,FileAccess.Read,FileShare.Read|FileShare.Delete);
        if(Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(current))!=change.InstalledHash) return change with {State="conflict"};
        string staged=change.Target+".cf7-restore-"+Wire.Id();File.Copy(change.Backup,staged);File.Replace(staged,change.Target,null);
        return change with {State="restored"};
    }
    private void SaveChanges()=>LocalState.Save(Path.Combine(root,"changes.json"),changes.Values.ToArray());
    public static void RequireGameStopped(string game)
    {
        foreach(var process in System.Diagnostics.Process.GetProcesses())
        {
            using(process)
            {
                string name;try{name=process.ProcessName;}catch{continue;}
                if(!name.StartsWith("CRAZYFLASHER7",StringComparison.OrdinalIgnoreCase)&&!name.Equals("Flash",StringComparison.OrdinalIgnoreCase)&&!name.Equals("SAFlashPlayer",StringComparison.OrdinalIgnoreCase))continue;
                string? path;try{path=process.MainModule?.FileName;}catch{throw new IOException("无法核对游戏进程归属，请先关闭游戏");}
                if(path==null||Path.GetFullPath(path).StartsWith(Path.GetFullPath(game).TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase))throw new IOException("请先正常关闭目标游戏，再切换或恢复文件（PID "+process.Id+"）");
            }
        }
    }
    public static bool IsHash(string hash)=>System.Text.RegularExpressions.Regex.IsMatch(hash,"^[A-Fa-f0-9]{64}$");
    public string ImportCandidate(string uploadId)
    {
        string zip=Uploaded(uploadId),stage=Path.Combine(root,"candidate-import",Wire.Id());Directory.CreateDirectory(stage);
        Extract(zip,stage);
        var info=Candidate.Validate(stage);
        foreach(string sentinel in new[]{"crossdomain.xml","launcher/web/bootstrap.html","automation/start.ps1","tools/dotnet-runtime-detect.ps1"})
            if(!File.Exists(LocalState.Under(game,sentinel))) throw new IOException("游戏安装不完整，缺少："+sentinel);
        string name="c-"+info.Build[..12].ToLowerInvariant()+"-"+Wire.Hash(Encoding.UTF8.GetBytes("field-import"))[..10].ToLowerInvariant()+"-"+Wire.Id()[..16];
        string dest=LocalState.Under(game,"tmp/runtime-candidates/v2/"+name);
        if(Directory.GetFiles(stage,"*",SearchOption.AllDirectories).Any(file=>Path.Combine(dest,Path.GetRelativePath(stage,file)).Length>259))throw new IOException("目标候选路径超过现有 native 路径预算，请使用更短的游戏安装目录");
        Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
        // Same-volume staging makes publication one directory rename. Never replace an existing candidate.
        string moving=dest+"-staging";
        LocalState.Save(Path.Combine(root,"candidate-"+uploadId+".json"),new{path=dest,staging=moving,info.Build,info.Closure,state="copying_result_unknown"});
        Directory.CreateDirectory(moving);
        foreach(string file in Directory.GetFiles(stage,"*",SearchOption.AllDirectories))
        {cancellation.ThrowIfCancellationRequested();string copy=LocalState.Under(moving,Path.GetRelativePath(stage,file));Directory.CreateDirectory(Path.GetDirectoryName(copy)!);File.Copy(file,copy);}
        Candidate.Validate(moving);cancellation.ThrowIfCancellationRequested();Directory.Move(moving,dest);
        LocalState.Save(Path.Combine(root,"candidate-"+uploadId+".json"),new{path=dest,info.Build,info.Closure,state="imported_not_executed"});return dest;
    }
    public static void Extract(string zip,string directory)
    {
        using var archive=ZipFile.OpenRead(zip);long total=0;var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if(archive.Entries.Count>1024) throw new InvalidDataException("候选包文件过多");
        foreach(var entry in archive.Entries)
        {
            if(entry.FullName.EndsWith('/')) continue;
            if(!names.Add(entry.FullName.Replace('\\','/')) || (entry.ExternalAttributes>>16 & 0xF000)==0xA000) throw new InvalidDataException("候选包含重复路径或链接");
            total+=entry.Length;if(total>2L*1024*1024*1024 || entry.Length>1024L*1024*1024) throw new InvalidDataException("候选解压体积超过上限");
            string path=LocalState.Under(directory,entry.FullName);Directory.CreateDirectory(Path.GetDirectoryName(path)!);entry.ExtractToFile(path,false);
        }
    }
}
internal sealed record CandidateIdentity(string Build,string Closure,string CoreSha256);
internal static class Candidate
{
    public static CandidateIdentity Validate(string root,bool exactPackage=true)
    {
        LocalState.Plain(root);
        string manifest=LocalState.Under(root,"runtime/cf7-runtime-manifest.tsv");
        string[] lines=File.ReadAllLines(manifest);if(lines.Length<9 || lines[0]!="cf7-runtime-manifest-v2") throw new InvalidDataException("不支持的 runtime manifest");
        var values=new Dictionary<string,string>();var files=new SortedDictionary<string,(long size,string hash)>(StringComparer.Ordinal);
        var insensitive=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(string line in lines.Skip(1).Where(x=>x.Length>0))
        {
            string[] p=line.Split('\t');
            if(p.Length==4 && p[0]=="file")
            {
                if(p[1]!="CRAZYFLASHER7MercenaryEmpire.exe" && !p[1].StartsWith("runtime/",StringComparison.Ordinal)) throw new InvalidDataException("manifest 文件范围错误");
                if(p[1].Contains('\\') || !insensitive.Add(p[1]) || !Artifacts.IsHash(p[3]) || !long.TryParse(p[2],out long size) || size<0) throw new InvalidDataException("manifest 文件行无效");
                string path=LocalState.Under(root,p[1]);if(new FileInfo(path).Length!=size || Wire.FileHash(path)!=p[3].ToUpperInvariant()) throw new IOException("候选文件校验失败："+p[1]);
                files.Add(p[1],(size,p[3].ToUpperInvariant()));
            }
            else if(p.Length==2 && new[]{"publishMode","artifactSourceHash","producerRecipeHash","toolchainLockHash","toolchainBaseline","buildIdentityHash","payloadClosureHash"}.Contains(p[0])) values.Add(p[0],p[1]);
            else throw new InvalidDataException("manifest 未知行");
        }
        foreach(string field in new[]{"artifactSourceHash","producerRecipeHash","toolchainLockHash","buildIdentityHash","payloadClosureHash"})
            if(!values.TryGetValue(field,out var h)||!Artifacts.IsHash(h)) throw new InvalidDataException("缺少身份字段："+field);
        if(values.GetValueOrDefault("publishMode")!="framework-dependent" || !values.ContainsKey("toolchainBaseline")) throw new InvalidDataException("候选发布模式无效");
        string closure=Wire.Hash(Encoding.UTF8.GetBytes(string.Join("\n",files.Select(x=>$"{x.Key}\t{x.Value.size}\t{x.Value.hash}"))+"\n"));
        string build=Wire.Hash(Encoding.UTF8.GetBytes(string.Concat(new[]{"artifactSourceHash","producerRecipeHash","toolchainLockHash"}.Select(k=>$"{k}\t{values[k].ToUpperInvariant()}\n"))));
        if(build!=values["buildIdentityHash"].ToUpperInvariant() || closure!=values["payloadClosureHash"].ToUpperInvariant()) throw new InvalidDataException("候选 identity/closure 不匹配");
        using var meta=JsonDocument.Parse(File.ReadAllText(LocalState.Under(root,"runtime-build-metadata.v2.json")));
        var m=meta.RootElement;
        if(m.EnumerateObject().GroupBy(x=>x.Name).Any(x=>x.Count()>1) || m.Text("schema")!="cf7-runtime-candidate-metadata.v2" || m.Text("buildIdentityHash").ToUpperInvariant()!=build || m.Text("payloadClosureHash").ToUpperInvariant()!=closure) throw new InvalidDataException("候选 metadata 不匹配");
        foreach(string key in new[]{"artifactSourceHash","producerRecipeHash","toolchainLockHash"}) if(m.Text(key).ToUpperInvariant()!=values[key].ToUpperInvariant()) throw new InvalidDataException("候选 metadata 域不匹配");
        var allowed=new HashSet<string>(files.Keys,StringComparer.OrdinalIgnoreCase){"runtime/cf7-runtime-manifest.tsv","runtime-build-metadata.v2.json"};
        foreach(string path in Directory.GetFiles(root,"*",SearchOption.AllDirectories))
        {
            string relative=Path.GetRelativePath(root,path).Replace('\\','/');
            if(!allowed.Contains(relative)&&(exactPackage||relative.StartsWith("runtime/",StringComparison.OrdinalIgnoreCase))) throw new InvalidDataException("候选包有未声明文件："+path);
        }
        foreach(string required in new[]{"CRAZYFLASHER7MercenaryEmpire.exe","runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe","runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll"}) if(!files.ContainsKey(required)) throw new InvalidDataException("候选缺少入口");
        return new(build,closure,files["runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll"].hash);
    }
    public static CandidateIdentity Pack(string root,string output)
    {
        var identity=Validate(root,false);
        var paths=File.ReadAllLines(Path.Combine(root,"runtime","cf7-runtime-manifest.tsv"))
            .Where(x=>x.StartsWith("file\t",StringComparison.Ordinal)).Select(x=>x.Split('\t')[1])
            .Concat(new[]{"runtime/cf7-runtime-manifest.tsv","runtime-build-metadata.v2.json"});
        using var zip=ZipFile.Open(output,ZipArchiveMode.Create);
        foreach(string relative in paths)zip.CreateEntryFromFile(LocalState.Under(root,relative),relative,CompressionLevel.Fastest);
        return identity;
    }
}
