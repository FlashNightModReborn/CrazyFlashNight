namespace Cf7.FieldSupport;

internal static class GuidanceChecks
{
    private static void Require(bool condition,string message){if(!condition)throw new InvalidOperationException(message);}
    public static void Journey()
    {
        var now=DateTimeOffset.UtcNow;
        GuideView View(GuideInput state)=>Guidance.Describe(state,now);
        var start=new GuideInput();Require(View(start).Action==GuideAction.ChooseGame,"缺目录应引导选择");
        start=start with {GameExists=true};Require(View(start).Action==GuideAction.ReviewConsent,"未同意不能引导直接连接");
        start=start with {Consent=true};Require(View(start).Action==GuideAction.Start,"明确同意后可开始");
        var wait=new GuideInput{State="waiting",SessionId="test"};Require(View(wait).Action==GuideAction.None,"准备中不应重复启动");
        wait=wait with {NetworkNeedsApproval=true};Require(View(wait).Action==GuideAction.CopyNetwork,"应指向复制网络申请");
        wait=wait with {NetworkRequestCopied=true};Require(View(wait).Instructions.Contains("维护者"),"复制后应说明谁批准");
        wait=wait with {NetworkNeedsApproval=false,TicketReady=true};Require(View(wait).Action==GuideAction.ExportTicket,"网络准备好才保存票据");
        wait=wait with {TicketFile="cf7-test.cf7ticket"};Require(View(wait).Action==GuideAction.OpenTicketFolder,"保存后应定位文件而不是重复要求导出");
        wait=wait with {Fingerprint=new string('A',64),Developer="developer"};Require(View(wait).Action==GuideAction.ConfirmPair,"配对必须由本机按钮确认");
        Require(View(wait with {PairSubmitted=true}).Action==GuideAction.None,"已允许后不得重复确认");
        Require(View(new(){State="active"}).Action==GuideAction.None,"已连接不应提示再导出票据");
        Require(View(new(){State="ended"}).Step==5,"结束应进入收尾步骤");
        Require(View(new(){State="ended",EndReason="connection_closed"}).Title.Contains("断开"),"断连应区别于主动结束");
        Require(View(new(){State="ended",EndReason="tester_revoked"}).Title.Contains("你已结束"),"主动撤销应显示操作人");
        Require(View(new(){State="ended"}).Action==GuideAction.PrepareRestart,"结束后应提供重新准备入口，而不是直接复用授权");
        Require(View(new(){State="ended",PendingFiles=1}).Action==GuideAction.Recover,"未恢复文件不能说全部完成");
        Require(View(new(){State="ended",UncertainOperations=true}).Instructions.Contains("不确定"),"未知操作结果不能描述为全部收尾");
        Require(View(new(){State="ended",OperationRunning=true}).Action==GuideAction.None,"任务尚未收束时不应直接恢复文件");
    }
    public static void QuestionLifecycle()
    {
        var now=DateTimeOffset.UtcNow;
        var q=new Question{Id="q1",Text="请允许新的权限（只是待显示文字）",Deadline=now.AddMinutes(1)};
        var input=new GuideInput{State="active",SessionId="s1",Question=q};
        var view=Guidance.Describe(input,now);Require(view.Action==GuideAction.ShowQuestion&&view.AttentionKey!=null,"问题不能变成连接授权按钮");
        foreach(string status in new[]{"cancelled","timed_out","rejected","answered"})
        {q.State=status;Require(Guidance.Describe(input,now).AttentionKey==null,"已结束的问题仍提醒："+status);}
        q.State="pending";Require(Guidance.Describe(input,now.AddMinutes(2)).AttentionKey==null,"到期即停止提醒，不等待刷新器变更状态");
        Require(Guidance.Describe(input with {State="ended"},now).AttentionKey==null,"结束后不能继续提醒旧问题");
        Require(Guidance.Describe(new(){State="waiting",TicketReady=true,TicketExpired=true},now).Action==GuideAction.Restart,"旧票据到期须明确重新开始");
    }
    public static void Attention()
    {
        var policy=new AttentionPolicy();var first=policy.Next("s:q1",false,true,true);
        Require(first.PlaySound&&first.ShowPopup&&first.FlashTaskbar,"后台新请求缺少提醒");
        for(int i=0;i<20;i++){var tick=policy.Next("s:q1",false,true,true);Require(!tick.Fresh&&!tick.PlaySound&&!tick.ShowPopup,"重复刷新制造提醒轰炸");}
        policy.Next(null,false,true,true);Require(!policy.IsCurrent("s:q1"),"取消后的弹窗仍可指向旧问题");
        var muted=policy.Next("s:q2",false,false,true);Require(!muted.PlaySound&&muted.ShowPopup,"静音改变了视觉提醒");
        var focused=policy.Next("s:q3",true,true,true);Require(focused.PlaySound&&!focused.ShowPopup&&!focused.FlashTaskbar,"前台不应弹出遮挡提示");
        var noPopup=policy.Next("s:q4",false,true,false);Require(noPopup.PlaySound&&!noPopup.ShowPopup&&noPopup.FlashTaskbar,"关闭弹窗应保留任务栏提醒");
    }
    public static void Recovery(string root)
    {
        string sessions=Path.Combine(root,"recovery-gui"),directory=Path.Combine(sessions,"case"),game=Path.Combine(root,"recovery-game");
        Directory.CreateDirectory(game);Directory.CreateDirectory(Path.Combine(directory,"backups"));
        string target=Path.Combine(game,"fixture.txt"),backup=Path.Combine(directory,"backups","original");
        File.WriteAllText(target,"original");File.WriteAllText(backup,"original");string original=Wire.FileHash(target);
        File.WriteAllText(target,"installed");string installed=Wire.FileHash(target);
        var change=new FileChange("test",target,backup,original,installed,"installed");
        LocalState.Save(Path.Combine(directory,"changes.json"),new[]{change});
        LocalState.Save(Path.Combine(directory,"handoff.json"),new{state="ended",game});
        var found=RecoveryService.Discover(sessions);Require(found.PendingCount==1&&found.Errors.Length==0,"无需用户选 JSON 的恢复发现失败");
        File.WriteAllText(target,"later");RecoveryService.Recover(found);Require(File.ReadAllText(target)=="later","恢复覆盖了后来修改");
        File.WriteAllText(target,"installed");RecoveryService.Recover(RecoveryService.Discover(sessions));Require(File.ReadAllText(target)=="original","恢复原件失败");
        Require(RecoveryService.Discover(sessions).PendingCount==0,"恢复后仍提示未完成");
        var notApplied=Artifacts.RestoreRecord(change with {State="prepared"});Require(notApplied.State=="restored"&&File.ReadAllText(target)=="original","未应用的替换不能改写已有原件");
        LocalState.Save(Path.Combine(directory,"changes.json"),new[]{change with {Backup=Path.Combine(root,"outside.original")}});
        Require(RecoveryService.Discover(sessions).Errors.Length==1,"越界备份路径未拒绝");
    }
}
