namespace Cf7.FieldSupport;

internal enum GuideAction { None, ChooseGame, ReviewConsent, Start, CopyNetwork, ExportTicket, OpenTicketFolder, ConfirmPair, ShowQuestion, ShowRecords, Recover, Restart, PrepareRestart }
internal sealed record GuideInput
{
    public string State {get;init;}="idle";
    public string SessionId {get;init;}="";
    public bool GameExists {get;init;}
    public bool Consent {get;init;}
    public bool NetworkNeedsApproval {get;init;}
    public bool NetworkRequestCopied {get;init;}
    public bool TicketReady {get;init;}
    public bool TicketExpired {get;init;}
    public string TicketFile {get;init;}="";
    public string? Fingerprint {get;init;}
    public string Developer {get;init;}="";
    public bool PairSubmitted {get;init;}
    public Question? Question {get;init;}
    public bool OperationRunning {get;init;}
    public bool UncertainOperations {get;init;}
    public int PendingFiles {get;init;}
    public string EndReason {get;init;}="";
    public string Error {get;init;}="";
}
internal sealed record GuideView(int Step,string Title,string Instructions,string Button,GuideAction Action,string? AttentionKey=null,string? Notice=null);
internal static class Guidance
{
    public static GuideView Describe(GuideInput input,DateTimeOffset now)
    {
        string key=input.SessionId;
        if(input.State=="ended")
        {
            if(input.OperationRunning)return new(5,"访问已结束，正在收束本轮任务","已拒绝新操作，正在停止本轮任务并记录结果。请稍候再核对文件恢复情况。","正在收束…",GuideAction.None);
            if(input.PendingFiles>0)return new(5,"访问已结束，还有文件需要核对",$"维护者已不能继续操作。还有 {input.PendingFiles} 个文件替换未收尾；请查看恢复结果。发生后续修改的文件会保留，交给维护者核对。","查看待恢复文件",GuideAction.Recover);
            if(input.UncertainOperations)return new(5,"访问已结束，有操作结果需要核对","有任务被中断或执行结果不确定。请把本次记录交给维护者核对，不要直接重复之前的修改操作。登记的文件恢复结果可在下方查看。","查看本次记录",GuideAction.ShowRecords);
            if(input.EndReason=="network_setup_failed")return new(2,"连接准备没有完成","请确认电脑能联网，把下方错误提示交给维护者。准备好后可以重新开始；不需要安装网络软件或修改路由器。","重新准备连接",GuideAction.Restart);
            string reason=input.EndReason switch
            {
                "connection_closed"=>"连接已断开，本次访问已结束",
                "heartbeat_timeout"=>"连接长时间无响应，本次访问已结束",
                "expired"=>"授权时间已到，本次诊断已结束",
                "tester_revoked"=>"你已结束本次诊断",
                "developer_finished"=>"维护者已结束本次诊断",
                _=>"本次诊断已结束"
            };
            return new(5,reason,"本次登记的文件替换已收尾，诊断记录和取回的资料仍会保留。需要继续时，点击下方重新准备并明确授权，发送新的配对文件；旧连接不会自动恢复。也可以查看记录或关闭窗口。","重新准备诊断",GuideAction.PrepareRestart);
        }
        if(input.State=="idle")
        {
            if(input.PendingFiles>0)return new(1,"上次诊断还有文件需要核对","先查看尚未恢复的文件。恢复不会覆盖后来产生的修改；拿不准时，把结果交给维护者。","查看待恢复文件",GuideAction.Recover);
            if(!input.GameExists)return new(1,"先选择要检查的游戏","点击下面的按钮，选择游戏所在文件夹。首次只测试工具时，也可以选择一个专用测试目录。","选择游戏文件夹",GuideAction.ChooseGame);
            if(!input.Consent)return new(1,"阅读说明，决定是否开启诊断","游戏目录已选好。请阅读下方权限与资料使用说明，然后勾选同意；勾选前不会建立诊断连接。","查看授权说明",GuideAction.ReviewConsent);
            return new(1,"准备好了，可以开始","开启后由工具准备网络。接下来每一步会在这里提示；无需阅读说明文件、安装 Tailscale 或配置端口。","开启本次诊断",GuideAction.Start);
        }
        if(input.Fingerprint!=null)
        {
            if(input.PairSubmitted)return new(3,"已提交允许，正在完成连接","请稍候，窗口会自动进入诊断状态。只有本机这次允许生效后，维护者才能执行操作。","正在建立会话…",GuideAction.None);
            string name=input.Developer.Replace('\r',' ').Replace('\n',' ');
            return new(3,"现在需要你核对连接身份",$"申请者：{name}\n指纹：{Wire.ShortFingerprint(input.Fingerprint)}\n与维护者发来的指纹一致后，点击允许；不一致请选择拒绝。聊天里的回复不会替代本机按钮。","核对一致，允许连接",GuideAction.ConfirmPair,key+":pair:"+input.Fingerprint,"维护者申请连接，请核对身份");
        }
        if(input.State=="active")
        {
            var q=input.Question;
            if(q?.State=="pending"&&q.Deadline>now)return new(4,"现在需要你协助",$"请阅读下面的问题，完成所要求的操作，再选择结果或填写文字并提交。也可以拒绝或结束诊断。\n本问题等待到 {q.Deadline.ToLocalTime():HH:mm:ss}；没有回复不会当作同意。","查看问题并回复",GuideAction.ShowQuestion,key+":question:"+q.Id,"收到新问题，点击查看并回复");
            if(q?.State=="answered")return new(4,"答复已提交，等待维护者继续","你的答复已记录在下方，不用再次提交。下一个问题到达时会有新的提醒。","查看已提交答复",GuideAction.ShowQuestion);
            if(q!=null&&(q.State is "rejected" or "cancelled" or "timed_out" || q.Deadline<=now))
                return new(4,"本问题已结束，无需继续填写",q.State=="rejected"?"已记录你的拒绝。维护者可调整实验，新的问题会另行提醒。":"问题已取消或到期，旧答复不会用于后续实验。等待维护者的新问题即可。","查看问题状态",GuideAction.ShowQuestion);
            return new(4,input.OperationRunning?"维护者正在运行检查":"已连接，暂时不需要你操作",input.OperationRunning?"检查正在后台执行。需要你协助时会提醒；右上角始终可以结束诊断。":"接下来由维护者检查。你可以将窗口最小化，新问题会用声音、任务栏和提醒窗口提示。右上角可随时结束诊断。","等待维护者…",GuideAction.None);
        }
        if(input.NetworkNeedsApproval)
            return new(2,input.NetworkRequestCopied?"连接申请已复制，等待维护者批准":"请把连接申请交给维护者",input.NetworkRequestCopied?"到 QQ 等双方惯用的聊天软件粘贴并发送。由维护者打开链接批准，你不需要登录账号。批准后这里会自动进入下一步。":"点击复制，把申请粘贴到 QQ 等双方惯用的聊天软件，私下发给维护者。由维护者批准，你不需要自己打开链接、登录账号或配置网络。",input.NetworkRequestCopied?"再次复制连接申请":"复制连接申请",GuideAction.CopyNetwork,key+":network","网络申请准备好了，请交给维护者");
        if(input.TicketExpired)return new(3,"配对文件已到期","尚未建立诊断连接。点击重新准备，生成新的配对文件交给维护者；旧文件无法继续使用。","重新准备连接",GuideAction.Restart);
        if(input.TicketReady)
        {
            if(input.TicketFile.Length>0)return new(3,"配对文件已保存，请发送这个文件",$"文件：{Path.GetFileName(input.TicketFile)}\n打开文件夹，把该文件作为附件私下发给维护者。无需双击打开，也不用粘贴文件内容。发送后等待连接申请，工具会提醒你核对身份。","打开票据文件夹",GuideAction.OpenTicketFolder);
            return new(3,"网络已准备好，接下来发送配对文件","点击保存，选择桌面等容易找到的位置，再把保存的文件私下发给维护者。文件无需打开；它只用于本次短期配对。","保存配对文件",GuideAction.ExportTicket,key+":ticket","网络已准备好，请保存配对文件");
        }
        return new(2,"正在准备网络，请稍候","工具正在建立跨网通道，不需要手动配置。需要转交申请时会提醒你；如果长时间没有进展，可以结束本次准备并把提示交给维护者。","正在准备…",GuideAction.None);
    }
}

internal sealed class AttentionPolicy
{
    private readonly HashSet<string> seen=new(StringComparer.Ordinal);
    public string? CurrentKey {get;private set;}
    public bool Update(string? key)
    {
        CurrentKey=key;
        return key!=null&&seen.Add(key);
    }
    public bool IsCurrent(string key)=>CurrentKey==key;
    public void Reset(){seen.Clear();CurrentKey=null;}
    public AttentionDecision Next(string? key,bool foreground,bool sound,bool popup)
    {
        bool fresh=Update(key);return new(fresh,fresh&&sound,fresh&&!foreground&&popup,fresh&&!foreground);
    }
}
internal sealed record AttentionDecision(bool Fresh,bool PlaySound,bool ShowPopup,bool FlashTaskbar);
