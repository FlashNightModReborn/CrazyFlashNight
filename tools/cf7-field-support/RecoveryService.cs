using System.Diagnostics;
using System.Text.Json;

namespace Cf7.FieldSupport;

internal sealed record RecoveryBatch(string Record,string RecordHash,string Game,FileChange[] Changes);
internal sealed record RecoveryInventory(RecoveryBatch[] Batches,string[] Errors)
{
    public int PendingCount=>Batches.Sum(x=>x.Changes.Count(c=>c.State!="restored"));
}
internal static class RecoveryService
{
    public static RecoveryInventory Discover(string? root=null)
    {
        root??=Path.Combine(LocalState.Root,"sessions");
        var batches=new List<RecoveryBatch>();var errors=new List<string>();
        if(!Directory.Exists(root))return new([],[]);
        string[] directories;
        try{LocalState.Plain(root);directories=Directory.GetDirectories(root);}
        catch(Exception ex){return new([],["无法读取恢复记录，请维护者核对："+ex.Message]);}
        foreach(string directory in directories)
        {
            string record=Path.Combine(directory,"changes.json");if(!File.Exists(record))continue;
            try
            {
                LocalState.Plain(record);
                if(new FileInfo(record).Length>1024*1024)throw new IOException("恢复记录过大");
                var changes=LocalState.Read<FileChange[]>(record);if(changes.All(x=>x.State=="restored"))continue;
                var handoff=LocalState.Read<JsonElement>(Path.Combine(directory,"handoff.json"));
                if(handoff.Text("state")!="ended")
                {
                    if(!handoff.TryGetProperty("ownerPid",out var pid)||!handoff.TryGetProperty("ownerStartUtc",out var start))throw new IOException("无法确认旧会话已退出，请维护者核对");
                    try
                    {
                        using var process=Process.GetProcessById(pid.GetInt32());
                        if(!process.HasExited&&process.StartTime.ToUniversalTime()==start.GetDateTime().ToUniversalTime())throw new IOException("该会话仍在运行，请先结束诊断");
                    }
                    catch(ArgumentException){/* owner has exited */}
                }
                string game=Path.GetFullPath(handoff.Text("game"));
                foreach(var change in changes)
                {
                    if(!Path.GetFullPath(change.Target).StartsWith(game.TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase)||
                       !Path.GetFullPath(change.Backup).StartsWith(Path.Combine(directory,"backups")+"\\",StringComparison.OrdinalIgnoreCase)||
                       !Artifacts.IsHash(change.OriginalHash)||!Artifacts.IsHash(change.InstalledHash))throw new IOException("恢复记录路径或哈希无效");
                }
                batches.Add(new(record,Wire.FileHash(record),game,changes));
            }
            catch(Exception ex){errors.Add(Path.GetFileName(directory)[..Math.Min(8,Path.GetFileName(directory).Length)]+"："+ex.Message);}
        }
        return new(batches.ToArray(),errors.ToArray());
    }
    public static string[] Recover(RecoveryInventory inventory)
    {
        var results=new List<string>();
        foreach(var batch in inventory.Batches)
        {
            try
            {
                if(Wire.FileHash(batch.Record)!=batch.RecordHash)throw new IOException("记录在确认后发生变化，请重新查看");
                Artifacts.RequireGameStopped(batch.Game);
                var current=batch.Changes.ToArray();
                for(int i=0;i<current.Length;i++)
                {
                    if(current[i].State=="restored")continue;
                    try
                    {
                        current[i]=Artifacts.RestoreRecord(current[i]);
                        LocalState.Save(batch.Record,current);
                        results.Add((current[i].State=="restored"?"已恢复：":"保留后续修改，请维护者核对：")+current[i].Target);
                    }
                    catch(Exception ex){results.Add("未完成："+current[i].Target+"；"+ex.Message);}
                }
            }
            catch(Exception ex){results.Add("此组文件暂未恢复："+ex.Message);}
        }
        results.AddRange(inventory.Errors.Select(x=>"记录需核对："+x));return results.ToArray();
    }
}

internal sealed record UiPreferences(string Game="",bool Sound=true,bool Popup=true)
{
    private static string FilePath=>Path.Combine(LocalState.Root,"ui-preferences.json");
    public static UiPreferences Load(){try{return File.Exists(FilePath)?LocalState.Read<UiPreferences>(FilePath):new();}catch{return new();}}
    public void Save(){LocalState.PrivateDirectory(LocalState.Root);LocalState.Save(FilePath,this);}
}
