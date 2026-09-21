using System.Diagnostics;

namespace Cf7.FieldSupport;

internal sealed class MainForm : Form
{
    private SupportSession? session;
    private readonly bool preview;
    private GuideInput? previewInput;
    private GuideView currentGuide=Guidance.Describe(new(),DateTimeOffset.Now);
    private AttentionReminder? reminder;
    private readonly TextBox game=new(){Dock=DockStyle.Fill,AccessibleName="游戏文件夹"};
    private readonly Label state=new(){AutoSize=true,Font=new("Microsoft YaHei UI",14,FontStyle.Bold),ForeColor=Color.FromArgb(25,90,150)};
    private readonly Label detail=new(){AutoSize=true};
    private readonly Label guideText=new(){AutoSize=true,Dock=DockStyle.Top};
    private readonly Label feedback=new(){AutoSize=true,Dock=DockStyle.Top,ForeColor=Color.FromArgb(35,110,65)};
    private readonly Button next=Button("选择游戏文件夹",220);
    private readonly TableLayoutPanel guideCard=new(){Dock=DockStyle.Top,AutoSize=true,ColumnCount=1,RowCount=3,Padding=new(12),BackColor=Color.FromArgb(235,244,252)};
    private readonly CheckBox consent=new(){AutoSize=true,Text="我已阅读说明，同意开启本次诊断"};
    private readonly Label permissionText=new(){AutoSize=true,Dock=DockStyle.Top,Padding=new(16,4,0,4),Text="维护者可用当前用户权限执行命令、传输诊断资料，并临时更换测试文件。必要资料可能交给模型服务分析。结束访问不会撤回已传出的资料，也不会自动恢复已修改的文件；恢复冲突会保留现场，等待核对。"};
    private readonly NumericUpDown minutes=new(){Minimum=10,Maximum=120,Value=45,Width=70};
    private readonly Button start=Button("开启本次诊断",150),stop=Button("立即结束诊断",155);
    private readonly Button networkRequest=Button("再次复制连接申请",185),export=Button("重新保存配对文件",185);
    private readonly Button browse=Button("选择…",85);
    private readonly TableLayoutPanel consentArea=new(){Dock=DockStyle.Top,AutoSize=true,ColumnCount=1,RowCount=2};
    private readonly FlowLayoutPanel actions=new(){AutoSize=true,Dock=DockStyle.Top,Padding=new(0,6,0,6)};
    private readonly FlowLayoutPanel connection=new(){AutoSize=true,Dock=DockStyle.Top};
    private readonly Panel scroll=new(){Dock=DockStyle.Fill,AutoScroll=true};
    private readonly GroupBox questionBox=new(){Text="需要你协助的事项",Dock=DockStyle.Top,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,Padding=new(12)};
    private readonly TextBox prompt=new(){Multiline=true,ReadOnly=true,Dock=DockStyle.Top,ScrollBars=ScrollBars.Vertical,BackColor=Color.White,Height=130,MinimumSize=new(0,130),AccessibleName="问题正文"};
    private readonly FlowLayoutPanel options=new(){Dock=DockStyle.Top,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,WrapContents=true};
    private readonly TextBox answer=new(){Multiline=true,Dock=DockStyle.Top,Height=62,MinimumSize=new(0,62),MaxLength=4000,ScrollBars=ScrollBars.Vertical,PlaceholderText="在这里填写结果或补充说明；无需提供密码",AccessibleName="文字回复"};
    private readonly Label replyFeedback=new(){AutoSize=true,Dock=DockStyle.Top,ForeColor=Color.FromArgb(35,110,65)};
    private readonly Button submit=Button("提交答复",125),reject=Button("拒绝 / 暂不方便",160);
    private readonly GroupBox records=new(){Text="操作与恢复结果",Dock=DockStyle.Top,Height=165,Padding=new(12)};
    private readonly TextBox log=new(){Multiline=true,ReadOnly=true,Dock=DockStyle.Fill,ScrollBars=ScrollBars.Vertical,BackColor=Color.FromArgb(246,248,251)};
    private readonly CheckBox sound=new(){AutoSize=true,Text="提示音"},popup=new(){AutoSize=true,Text="后台提醒窗口"};
    private RecoveryInventory history=new([],[]);
    private string? questionId;
    private string exportedTicket="";
    private string? lastRecordRoot;
    private bool networkCopied,pairSubmitted,closing,rendering,busy;
    private string lastState="idle";
    private string? lastAttention;
    private string? lastPairFingerprint;
    private int queuedRefresh;
    private static string Version=>typeof(MainForm).Assembly.GetName().Version!.ToString(3);

    public MainForm(bool preview=false)
    {
        this.preview=preview;
        AutoScaleMode=AutoScaleMode.Dpi;AutoScaleDimensions=new(96,96);
        Text=$"CF7 现场诊断助手 {Version} · 候选版";Width=960;Height=900;MinimumSize=new(780,700);
        Font=new("Microsoft YaHei UI",10);BackColor=Color.White;StartPosition=FormStartPosition.CenterScreen;
        var shell=Table(3);shell.Dock=DockStyle.Fill;shell.AutoSize=false;shell.Padding=new(16);
        shell.RowStyles.Clear();shell.RowStyles.Add(new(SizeType.AutoSize));shell.RowStyles.Add(new(SizeType.Percent,100));shell.RowStyles.Add(new(SizeType.AutoSize));Controls.Add(shell);
        var header=new TableLayoutPanel{Dock=DockStyle.Top,AutoSize=true,ColumnCount=2,RowCount=3,Padding=new(0,0,0,8)};
        header.ColumnStyles.Add(new(SizeType.Percent,100));header.ColumnStyles.Add(new(SizeType.AutoSize));
        for(int i=0;i<3;i++)header.RowStyles.Add(new(SizeType.AutoSize));
        header.Controls.Add(state,0,0);header.Controls.Add(detail,0,1);header.Controls.Add(stop,1,0);header.SetRowSpan(stop,2);
        stop.BackColor=Color.FromArgb(178,44,44);stop.ForeColor=Color.White;stop.Anchor=AnchorStyles.Top|AnchorStyles.Right;
        guideCard.ColumnStyles.Add(new(SizeType.Percent,100));for(int i=0;i<3;i++)guideCard.RowStyles.Add(new(SizeType.AutoSize));
        guideCard.Controls.Add(guideText,0,0);guideCard.Controls.Add(next,0,1);guideCard.Controls.Add(feedback,0,2);
        next.Anchor=AnchorStyles.Left;next.BackColor=Color.FromArgb(25,95,160);next.ForeColor=Color.White;
        header.Controls.Add(guideCard,0,2);header.SetColumnSpan(guideCard,2);shell.Controls.Add(header,0,0);
        shell.Controls.Add(scroll,0,1);
        var layout=Table(6);layout.Padding=new(4,0,12,12);scroll.Controls.Add(layout);
        void Wrap()
        {
            int width=Math.Max(240,layout.ClientSize.Width-layout.Padding.Horizontal-12);
            state.MaximumSize=new(Math.Max(200,header.ClientSize.Width-stop.Width-24),0);
            detail.MaximumSize=state.MaximumSize;guideText.MaximumSize=new(Math.Max(250,guideCard.ClientSize.Width-30),0);feedback.MaximumSize=guideText.MaximumSize;
            consent.MaximumSize=new(width,0);permissionText.MaximumSize=new(width,0);replyFeedback.MaximumSize=new(Math.Max(180,width-32),0);
            foreach(Control option in options.Controls)option.MaximumSize=new(Math.Max(180,width-40),0);
        }
        layout.SizeChanged+=(_,_)=>Wrap();header.SizeChanged+=(_,_)=>Wrap();
        var pathRow=new TableLayoutPanel{Dock=DockStyle.Top,AutoSize=true,ColumnCount=3,Padding=new(0,8,0,6)};
        pathRow.ColumnStyles.Add(new(SizeType.AutoSize));pathRow.ColumnStyles.Add(new(SizeType.Percent,100));pathRow.ColumnStyles.Add(new(SizeType.AutoSize));
        pathRow.Controls.Add(new Label{Text="游戏文件夹",AutoSize=true,Margin=new(0,7,12,0)},0,0);pathRow.Controls.Add(game,1,0);pathRow.Controls.Add(browse,2,0);layout.Controls.Add(pathRow,0,0);
        consentArea.ColumnStyles.Add(new(SizeType.Percent,100));consentArea.RowStyles.Add(new(SizeType.AutoSize));consentArea.RowStyles.Add(new(SizeType.AutoSize));
        consentArea.Controls.Add(consent,0,0);consentArea.Controls.Add(permissionText,0,1);layout.Controls.Add(consentArea,0,1);
        actions.Controls.Add(new Label{Text="本次有效期（分钟）",AutoSize=true,Margin=new(0,8,6,0)});actions.Controls.Add(minutes);actions.Controls.Add(start);layout.Controls.Add(actions,0,2);
        connection.Controls.Add(networkRequest);connection.Controls.Add(export);layout.Controls.Add(connection,0,3);
        var questionLayout=Table(5);questionLayout.Controls.Add(prompt,0,0);questionLayout.Controls.Add(options,0,1);questionLayout.Controls.Add(answer,0,2);
        var replies=new FlowLayoutPanel{Dock=DockStyle.Top,AutoSize=true};replies.Controls.Add(submit);replies.Controls.Add(reject);questionLayout.Controls.Add(replies,0,3);questionLayout.Controls.Add(replyFeedback,0,4);
        questionBox.Controls.Add(questionLayout);layout.Controls.Add(questionBox,0,4);records.Controls.Add(log);layout.Controls.Add(records,0,5);
        var footer=new FlowLayoutPanel{Dock=DockStyle.Top,AutoSize=true,Padding=new(0,6,0,0)};
        var testSound=Button("试听提示音",120);var open=Button("查看实验记录",145);var restore=Button("查看待恢复文件",165);
        footer.Controls.Add(sound);footer.Controls.Add(popup);footer.Controls.Add(testSound);footer.Controls.Add(open);footer.Controls.Add(restore);shell.Controls.Add(footer,0,2);
        var preferences=preview?new UiPreferences():UiPreferences.Load();sound.Checked=preferences.Sound;popup.Checked=preferences.Popup;
        if(Directory.Exists(preferences.Game))game.Text=preferences.Game;
        if(game.Text.Length==0)for(DirectoryInfo? dir=new(AppContext.BaseDirectory);dir!=null;dir=dir.Parent)if(File.Exists(Path.Combine(dir.FullName,"crossdomain.xml"))){game.Text=dir.FullName;break;}
        if(game.Text.Length==0&&File.Exists(Path.Combine(Environment.CurrentDirectory,"crossdomain.xml")))game.Text=Environment.CurrentDirectory;
        browse.Click+=(_,_)=>ChooseGame();start.Click+=async(_,_)=>await Begin();next.Click+=async(_,_)=>await RunNext();
        stop.Click+=(_,_)=>session?.Stop("tester_revoked");networkRequest.Click+=(_,_)=>CopyNetwork();export.Click+=(_,_)=>Export();
        reject.Click+=(_,_)=>{if(session?.PairFingerprint!=null){session.DecidePair(false);feedback.Text="已拒绝这次连接申请。";RefreshState();}else Reply(true);};
        submit.Click+=(_,_)=>Reply(false);open.Click+=(_,_)=>OpenRecords();restore.Click+=async(_,_)=>await RestoreHistory();
        game.TextChanged+=(_,_)=>RefreshState();consent.CheckedChanged+=(_,_)=>RefreshState();
        sound.CheckedChanged+=(_,_)=>SavePreferences();popup.CheckedChanged+=(_,_)=>{SavePreferences();RefreshState();};
        testSound.Click+=(_,_)=>{AttentionReminder.PlaySound();feedback.Text="已试播一次系统提示音。实际声音受系统音量与静音设置影响；工具不修改系统音量。";};
        Shown+=(_,_)=>{if(!preview)reminder=new(this,GoToCurrentStep);RefreshState();};
        FormClosing+=(_,_)=>{closing=true;reminder?.Dispose();session?.Dispose();};
        if(!preview)history=RecoveryService.Discover();RefreshState();
    }
    private static TableLayoutPanel Table(int rows)
    {
        var table=new TableLayoutPanel{Dock=DockStyle.Top,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,ColumnCount=1,RowCount=rows};
        table.ColumnStyles.Add(new(SizeType.Percent,100));for(int i=0;i<rows;i++)table.RowStyles.Add(new(SizeType.AutoSize));return table;
    }
    private static Button Button(string text,int width)=>new(){Text=text,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,MinimumSize=new(width,36),FlatStyle=FlatStyle.Flat,Margin=new(4),UseVisualStyleBackColor=true};
    private void SavePreferences(){if(preview)return;try{new UiPreferences(game.Text,sound.Checked,popup.Checked).Save();}catch(Exception ex){feedback.Text="偏好未保存，当前设置仍可使用："+ex.Message;}}
    private void ChooseGame(){using var dialog=new FolderBrowserDialog{Description="选择要检查的游戏文件夹；只测试工具时可选专用测试目录"};if(dialog.ShowDialog(this)==DialogResult.OK){game.Text=dialog.SelectedPath;SavePreferences();RefreshState();}}
    private GuideInput GuideInputNow()
    {
        if(previewInput!=null)return previewInput;
        bool ended=session?.State=="ended";
        return new(){State=session?.State??"idle",SessionId=session?.Id??"",GameExists=Directory.Exists(game.Text),Consent=consent.Checked,
            NetworkNeedsApproval=session?.Network?.AuthorizationUrl!=null&&!ended,NetworkRequestCopied=networkCopied,
            TicketReady=session?.Ticket!=null,TicketExpired=session?.Ticket?.ExpiresAt<=DateTimeOffset.UtcNow,TicketFile=exportedTicket,
            Fingerprint=ended?null:session?.PairFingerprint,Developer=session?.Developer??"",PairSubmitted=pairSubmitted,
            Question=session?.Question,OperationRunning=session?.Operations.Values.Any(x=>x.State=="running")==true,
            UncertainOperations=session?.Operations.Values.Any(x=>x.State is "failed_or_unknown" or "cancelled_or_unknown")==true,
            PendingFiles=history.PendingCount+history.Errors.Length,EndReason=session?.EndReason??"",Error=session?.LastConnectionError??""};
    }
    private async Task RunNext()
    {
        if(preview||busy)return;
        var action=Guidance.Describe(GuideInputNow(),DateTimeOffset.UtcNow).Action;
        try
        {
            switch(action)
            {
                case GuideAction.ChooseGame:ChooseGame();break;
                case GuideAction.ReviewConsent:scroll.ScrollControlIntoView(consentArea);consent.Focus();break;
                case GuideAction.Start:await Begin();break;
                case GuideAction.Restart:session?.Stop("tester_restarted");await Begin();break;
                case GuideAction.PrepareRestart:
                    if(session!=null){lastRecordRoot=session.Root;session.Changed-=QueueRefresh;session.Dispose();session=null;}
                    consent.Checked=false;feedback.Text="";scroll.AutoScrollPosition=Point.Empty;RefreshState();break;
                case GuideAction.CopyNetwork:CopyNetwork();break;
                case GuideAction.ExportTicket:Export();break;
                case GuideAction.OpenTicketFolder:OpenFolder(Path.GetDirectoryName(exportedTicket)!);break;
                case GuideAction.ConfirmPair:pairSubmitted=true;session?.DecidePair(true);RefreshState();break;
                case GuideAction.ShowQuestion:GoToCurrentStep();break;
                case GuideAction.ShowRecords:OpenRecords();break;
                case GuideAction.Recover:await RestoreHistory();break;
            }
        }
        catch(Exception ex){feedback.Text="这一步未完成："+ex.Message;}
    }
    private void GoToCurrentStep()
    {
        if(questionBox.Visible){scroll.ScrollControlIntoView(questionBox);if(answer.Visible&&!answer.ReadOnly)answer.Focus();}
        else if(!consent.Checked&&consentArea.Visible){scroll.ScrollControlIntoView(consentArea);consent.Focus();}
        else next.Focus();
    }
    private async Task Begin()
    {
        if(preview||busy)return;
        if(!consent.Checked){feedback.Text="请先阅读并勾选本次诊断授权。";scroll.ScrollControlIntoView(consentArea);return;}
        if(!Directory.Exists(game.Text)){feedback.Text="先点击选择，找到游戏文件夹或专用测试目录。";return;}
        try
        {
            SavePreferences();session?.Dispose();exportedTicket="";networkCopied=false;pairSubmitted=false;questionId=null;lastAttention=null;feedback.Text="";reminder?.Reset();
            session=new(game.Text,(int)minutes.Value);session.Changed+=QueueRefresh;
            RefreshState();await session.Start(true);RefreshState();
        }
        catch(Exception ex){session?.Stop("network_setup_failed");feedback.Text="网络准备未完成："+ex.Message;RefreshState();}
    }
    private void QueueRefresh()
    {
        if(closing||!IsHandleCreated||Interlocked.Exchange(ref queuedRefresh,1)!=0)return;
        try{BeginInvoke(()=>{Interlocked.Exchange(ref queuedRefresh,0);RefreshState();});}catch{Interlocked.Exchange(ref queuedRefresh,0);}
    }
    private void CopyNetwork()
    {
        try{if(session?.Network?.AuthorizationUrl is not {} url||session.State=="ended")return;Clipboard.SetText(url);networkCopied=true;feedback.Text="已复制。请到聊天软件粘贴并私下发给维护者，由维护者批准。";RefreshState();}
        catch(Exception ex){feedback.Text="未能复制，可稍后再点一次："+ex.Message;}
    }
    private void Export()
    {
        if(session?.Ticket is not {} ticket||session.State!="waiting")return;
        using var dialog=new SaveFileDialog{Title="保存配对文件，然后把这个文件发给维护者（无需打开）",Filter="CF7 配对文件|*.cf7ticket",FileName="cf7-"+session.Id[..8]+".cf7ticket",InitialDirectory=Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)};
        if(dialog.ShowDialog(this)!=DialogResult.OK)return;
        try
        {
            if(session?.Id!=ticket.SessionId||session.State!="waiting"||DateTimeOffset.UtcNow>ticket.ExpiresAt)throw new IOException("本次配对状态已改变，请按最新步骤继续");
            LocalState.Save(dialog.FileName,ticket);exportedTicket=dialog.FileName;feedback.Text="已保存。请发送文件本身，不用打开或粘贴内容；不要发到公开群。";RefreshState();
        }
        catch(Exception ex){feedback.Text="配对文件未保存："+ex.Message;}
    }
    private void Reply(bool refuse)
    {
        if(session==null||questionId==null)return;
        string selected=options.Controls.OfType<RadioButton>().FirstOrDefault(x=>x.Checked)?.Text??"";
        string text=string.Join("；",new[]{selected,answer.Text.Trim()}.Where(x=>x.Length>0));
        if(!refuse&&text.Length==0){feedback.Text="请选择一个结果或在文字框填写说明，然后提交。";GoToCurrentStep();return;}
        try{session.Answer(questionId,text,refuse);feedback.Text=refuse?"已提交拒绝，等待维护者调整。":"答复已提交，等待维护者继续。";RefreshState();}
        catch(Exception ex){feedback.Text="答复未提交："+ex.Message;RefreshState();}
    }
    private void RefreshState()
    {
        if(closing||rendering)return;rendering=true;
        try
        {
            string observedState=previewInput?.State??session?.State??"idle";
            bool justEnded=observedState=="ended"&&lastState!="ended";
            if(justEnded){if(!preview)history=RecoveryService.Discover();consent.Checked=false;feedback.Text="";scroll.AutoScrollPosition=Point.Empty;}
            lastState=observedState;
            if(lastPairFingerprint!=session?.PairFingerprint){lastPairFingerprint=session?.PairFingerprint;pairSubmitted=false;}
            var input=GuideInputNow();currentGuide=Guidance.Describe(input,DateTimeOffset.UtcNow);
            if(lastAttention!=currentGuide.AttentionKey&&currentGuide.AttentionKey!=null)feedback.Text="";
            lastAttention=currentGuide.AttentionKey;
            bool running=input.State is not ("idle" or "ended");bool pairing=input.Fingerprint!=null;
            state.Text=$"第 {currentGuide.Step}/5 步 · {currentGuide.Title}";
            detail.Text=session==null?$"候选 {Version} · 跟随当前步骤即可，无需打开说明文件":$"候选 {Version} · 本次 {session.Id[..8]} · "+(input.State=="ended"?"已结束访问":$"剩余 {Math.Max(0,(int)(session.ExpiresAt-DateTimeOffset.UtcNow).TotalMinutes)} 分钟 · {StateLabel(input.State)}");
            guideText.Text=currentGuide.Instructions;next.Text=currentGuide.Button;next.Enabled=currentGuide.Action!=GuideAction.None&&!preview&&!busy;
            guideCard.BackColor=currentGuide.AttentionKey==null?Color.FromArgb(235,244,252):Color.FromArgb(255,242,204);
            start.Enabled=!running&&!busy&&!preview;stop.Enabled=running&&!preview;game.Enabled=!running;minutes.Enabled=!running;consent.Enabled=!running&&!preview;browse.Enabled=!running;
            consentArea.Visible=!running;actions.Visible=!running;
            connection.Visible=running&&!pairing&&input.State!="active";
            networkRequest.Visible=input.NetworkNeedsApproval&&input.NetworkRequestCopied;export.Visible=input.TicketReady&&input.TicketFile.Length>0&&!input.TicketExpired;
            questionBox.Visible=pairing||input.Question!=null;
            bool pending=input.State=="active"&&input.Question?.State=="pending"&&input.Question.Deadline>DateTimeOffset.UtcNow;
            submit.Visible=!pairing;options.Visible=!pairing;answer.Visible=!pairing;replyFeedback.Visible=!pairing;
            submit.Enabled=pending&&!preview;reject.Enabled=(pairing||pending)&&!preview;options.Enabled=pending;answer.ReadOnly=!pending;
            if(pairing)SetPrompt("维护者："+input.Developer.Replace('\n',' ').Replace('\r',' ')+"\r\n指纹："+Wire.ShortFingerprint(input.Fingerprint!)+"\r\n一致后，请点击上方蓝色允许按钮；不一致请选择拒绝。");
            else DisplayQuestion(input.Question);
            var lines=new List<string>();
            if(session!=null)
            {
                foreach(var operation in session.Operations.Values.OrderBy(x=>x.StartedAt))lines.Add($"{operation.StartedAt.ToLocalTime():HH:mm:ss}  {(operation.Kind=="exec"?"运行检查":"启动候选")}  {StateLabel(operation.State)}");
                FileChange[] changes=(FileChange[])session.Artifacts.Changes;
                if(session.State=="ended")try{string path=Path.Combine(session.Root,"changes.json");if(File.Exists(path))changes=LocalState.Read<FileChange[]>(path);}catch{lines.Add("恢复记录需维护者核对。");}
                foreach(var change in changes)lines.Add("文件："+StateLabel(change.State)+"  "+change.Target);
                if(session.LastConnectionError.Length>0)lines.Add("连接提示："+session.LastConnectionError);
            }
            lines.AddRange(history.Errors.Select(x=>"恢复提示："+x));
            if(history.PendingCount>0)lines.Add($"尚有 {history.PendingCount} 个登记文件需核对，可点击下方查看待恢复文件。");
            records.Visible=lines.Count>0;string nextLog=string.Join("\r\n",lines);if(log.Text!=nextLog)log.Text=nextLog;
            if(!preview)reminder?.Update(currentGuide,sound.Checked,popup.Checked);
            if(justEnded&&IsHandleCreated)BeginInvoke(()=>{if(!closing){scroll.AutoScrollPosition=Point.Empty;scroll.PerformLayout();}});
        }
        finally{rendering=false;}
    }
    private void SetPrompt(string text){if(prompt.Text!=text)prompt.Text=text;}
    private void DisplayQuestion(Question? q)
    {
        if(questionId!=q?.Id)
        {
            questionId=q?.Id;options.SuspendLayout();options.Controls.Clear();answer.Clear();
            foreach(string option in q?.Options??[])options.Controls.Add(new RadioButton{Text=option,AutoSize=true,MaximumSize=new(Math.Max(180,options.ClientSize.Width-24),0),Margin=new(6)});
            options.ResumeLayout(true);
        }
        SetPrompt(q==null?"收到新问题时会在这里显示，并按你的设置提醒。":q.Text+"\r\n状态："+StateLabel(q.State)+"　截止："+q.Deadline.ToLocalTime().ToString("HH:mm:ss"));
        replyFeedback.Text=q?.State is "answered" or "rejected"?"已提交："+(q.Answer.Length>240?q.Answer[..240]+"…":q.Answer):"";
    }
    private static void OpenFolder(string path){Directory.CreateDirectory(path);var info=new ProcessStartInfo("explorer.exe"){UseShellExecute=false};info.ArgumentList.Add(path);Process.Start(info);}
    private void OpenRecords(){try{OpenFolder(session?.Root??lastRecordRoot??LocalState.Root);}catch(Exception ex){feedback.Text="暂时无法打开记录："+ex.Message;}}
    private async Task RestoreHistory()
    {
        if(preview||busy)return;
        if(session is {State:not "ended"}){feedback.Text="请先用右上角结束本次诊断，再核对和恢复文件。";return;}
        if(session?.Operations.Values.Any(x=>x.State=="running")==true){feedback.Text="本轮任务仍在收束，请稍候再恢复文件。";return;}
        history=RecoveryService.Discover();
        if(history.PendingCount==0){feedback.Text=history.Errors.Length==0?"没有待恢复的登记文件。":"有恢复记录需要维护者核对，详情见下方结果。";RefreshState();return;}
        string list=string.Join("\r\n",history.Batches.SelectMany(x=>x.Changes).Where(x=>x.State!="restored").Take(10).Select(x=>x.Target));
        if(MessageBox.Show(this,$"核对并恢复以下登记文件？\r\n{list}\r\n\r\n当前内容有其他修改时会保留，并提示交给维护者核对。", "确认恢复范围",MessageBoxButtons.OKCancel,MessageBoxIcon.Information)!=DialogResult.OK)return;
        busy=true;feedback.Text="正在核对原件与当前文件，请稍候…";RefreshState();
        try
        {
            string[] results=await Task.Run(()=>RecoveryService.Recover(history));
            history=RecoveryService.Discover();feedback.Text=history.PendingCount==0&&history.Errors.Length==0?"登记文件已恢复。现在可以关闭窗口或重新开启诊断。":"部分文件仍需维护者核对，已保留现场与备份。";
            MessageBox.Show(this,string.Join("\r\n",results),"恢复结果",MessageBoxButtons.OK,MessageBoxIcon.Information);
        }
        catch(Exception ex){feedback.Text="恢复未完成："+ex.Message;}
        finally{busy=false;RefreshState();}
    }
    private static string StateLabel(string value)=>value switch
    {
        "idle"=>"未开启","waiting"=>"准备/配对中","active"=>"诊断进行中","ended"=>"已结束访问",
        "pending"=>"等待答复","answered"=>"已答复","rejected"=>"已拒绝","cancelled"=>"已取消","timed_out"=>"已超时",
        "running"=>"运行中","completed"=>"已完成","failed"=>"失败","failed_or_unknown"=>"失败或结果待核对","cancelled_or_unknown"=>"已停止，结果待核对",
        "prepared"=>"已备份，替换结果待核对","installed"=>"已替换，尚未恢复","restored"=>"已恢复","conflict"=>"存在其他修改，保留现场",_=>value
    };
    internal void ShowLayoutPreview(string scenario="question")
    {
        Text=$"CF7 现场诊断助手 {Version} · 离线界面预览";
        var q=new Question{Id="preview-question",Text="这是无需阅读说明文件的问答测试。请确认正文、选项和输入框完整可见；完成所要求的操作后再回复。没有回复不会当作同意。",Options=["完整显示且可操作","文字被截断或控件有问题","较长选项：用于检查窄窗口和字体放大时能够换行，而且不会挤掉上方的问题正文。"],Deadline=DateTimeOffset.Now.AddMinutes(10)};
        previewInput=scenario switch
        {
            "idle"=>new(){GameExists=false},
            "consent"=>new(){GameExists=true},
            "network"=>new(){State="waiting",SessionId="preview",NetworkNeedsApproval=true},
            "ticket"=>new(){State="waiting",SessionId="preview",TicketReady=true},
            "pair"=>new(){State="waiting",SessionId="preview",Fingerprint=new string('A',64),Developer="维护者身份核对示例"},
            "ended"=>new(){State="ended",PendingFiles=2},
            _=>new(){State="active",SessionId="preview",Question=q}
        };
        RefreshState();
    }
    internal object LayoutEvidence()
    {
        int expectedPermission=permissionText.GetPreferredSize(new(permissionText.Width,0)).Height;
        int expectedGuide=guideText.GetPreferredSize(new(guideText.Width,0)).Height;
        return new{dpi=DeviceDpi,clientWidth=ClientSize.Width,clientHeight=ClientSize.Height,promptHeight=prompt.ClientSize.Height,fontHeight=prompt.Font.Height,promptFits=!questionBox.Visible||prompt.ClientSize.Height>=4*prompt.Font.Height,permissionFits=!permissionText.Visible||permissionText.Height>=expectedPermission,guideFits=guideText.Height>=expectedGuide,stopInClient=ClientRectangle.Contains(RectangleToClient(stop.RectangleToScreen(stop.ClientRectangle))),primaryInClient=ClientRectangle.Contains(RectangleToClient(next.RectangleToScreen(next.ClientRectangle))),optionCount=options.Controls.Count,step=currentGuide.Step,action=currentGuide.Action.ToString()};
    }
    internal bool DraftSurvivesRefresh()
    {
        ShowLayoutPreview();answer.Text="尚未提交的文字";var option=options.Controls.OfType<RadioButton>().First();option.Checked=true;
        RefreshState();RefreshState();return answer.Text=="尚未提交的文字"&&option.Checked;
    }
    internal object MinimizedEndTransition()
    {
        ShowLayoutPreview();feedback.Text="答复已提交，等待维护者继续。";scroll.AutoScrollPosition=new(0,1000);
        WindowState=FormWindowState.Minimized;
        previewInput=new(){State="ended",EndReason="connection_closed"};RefreshState();
        WindowState=FormWindowState.Normal;PerformLayout();Application.DoEvents();
        return new{passed=feedback.Text.Length==0&&scroll.AutoScrollPosition.Y==0&&currentGuide.Action==GuideAction.PrepareRestart&&!consent.Checked,feedbackCleared=feedback.Text.Length==0,scrollY=scroll.AutoScrollPosition.Y,title=state.Text,action=currentGuide.Action.ToString(),consent=consent.Checked};
    }
}
