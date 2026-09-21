using System.Media;
using System.Runtime.InteropServices;

namespace Cf7.FieldSupport;

internal sealed class AttentionReminder : IDisposable
{
    private readonly Form owner;
    private readonly Action viewCurrent;
    private readonly AttentionPolicy policy=new();
    private readonly NotifyIcon tray;
    private NoticeWindow? notice;
    [StructLayout(LayoutKind.Sequential)] private struct FlashInfo {public uint Size;public IntPtr Window;public uint Flags;public uint Count;public uint Timeout;}
    [DllImport("user32.dll")] private static extern bool FlashWindowEx(ref FlashInfo info);
    [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
    public AttentionReminder(Form owner,Action viewCurrent)
    {
        this.owner=owner;this.viewCurrent=viewCurrent;
        tray=new NotifyIcon{Icon=SystemIcons.Information,Text="CF7 现场诊断助手",Visible=true};
        tray.DoubleClick+=(_,_)=>View();
        owner.Activated+=Activated;
    }
    public void Update(GuideView guide,bool sound,bool popup)
    {
        string? previous=policy.CurrentKey;
        var decision=policy.Next(guide.AttentionKey,owner.WindowState!=FormWindowState.Minimized&&GetForegroundWindow()==owner.Handle,sound,popup);
        if(previous!=guide.AttentionKey){CloseNotice();Flash(false);}
        if(!popup)CloseNotice();
        tray.Text=guide.AttentionKey==null?"CF7 现场诊断助手":"CF7：现在需要你协助";
        if(!decision.Fresh)return;
        if(decision.PlaySound)PlaySound();
        if(decision.FlashTaskbar)
        {
            Flash(true);
            if(decision.ShowPopup)
            {
                string key=guide.AttentionKey!;
                notice=new NoticeWindow(guide.Notice??"现在需要你协助",()=>{if(policy.IsCurrent(key))View();});
                notice.Show();
            }
        }
    }
    public static void PlaySound(){try{SystemSounds.Asterisk.Play();}catch{/* Visual guidance remains available even if audio is unavailable. */}}
    private void Activated(object? sender,EventArgs e){Flash(false);CloseNotice();}
    private void View()
    {
        CloseNotice();if(owner.IsDisposed)return;
        if(owner.WindowState==FormWindowState.Minimized)owner.WindowState=FormWindowState.Normal;
        owner.Show();owner.Activate();viewCurrent();
    }
    private void Flash(bool on)
    {
        if(!owner.IsHandleCreated)return;
        var info=new FlashInfo{Size=(uint)Marshal.SizeOf<FlashInfo>(),Window=owner.Handle,Flags=on?2u:0u,Count=on?5u:0u,Timeout=0};FlashWindowEx(ref info);
    }
    public void Reset(){policy.Reset();CloseNotice();Flash(false);}
    private void CloseNotice(){if(notice is {IsDisposed:false})notice.Close();notice?.Dispose();notice=null;}
    public void Dispose(){owner.Activated-=Activated;CloseNotice();Flash(false);tray.Visible=false;tray.Dispose();}
}

internal sealed class NoticeWindow : Form
{
    private readonly System.Windows.Forms.Timer timer=new(){Interval=12000};
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    protected override bool ShowWithoutActivation=>true;
    protected override CreateParams CreateParams {get{var p=base.CreateParams;p.ExStyle|=0x08000000|0x00000080;return p;}}
    protected override void SetVisibleCore(bool value)
    {
        // Form.TopMost makes SetVisibleCore focus a child even with ShowWithoutActivation.
        // Set native z-order after showing instead, with SWP_NOACTIVATE | NOMOVE | NOSIZE.
        base.SetVisibleCore(value);
        if(value)SetWindowPos(Handle,new IntPtr(-1),0,0,0,0,0x13);
    }
    public NoticeWindow(string message,Action view)
    {
        Text="CF7 需要你协助";Font=new("Microsoft YaHei UI",10);BackColor=Color.FromArgb(255,248,220);
        FormBorderStyle=FormBorderStyle.FixedToolWindow;ShowInTaskbar=false;StartPosition=FormStartPosition.Manual;
        ClientSize=new(370,150);var area=Screen.FromPoint(Cursor.Position).WorkingArea;
        Location=new(area.Right-Width-20,area.Bottom-Height-20);
        var layout=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new(14),ColumnCount=1,RowCount=3};
        layout.RowStyles.Add(new(SizeType.AutoSize));layout.RowStyles.Add(new(SizeType.Percent,100));layout.RowStyles.Add(new(SizeType.AutoSize));
        layout.Controls.Add(new Label{Text="现在需要你协助",AutoSize=true,Font=new(Font,FontStyle.Bold)},0,0);
        layout.Controls.Add(new Label{Text=message+"。稍后处理不会自动回答或授权。",Dock=DockStyle.Fill},0,1);
        var buttons=new FlowLayoutPanel{AutoSize=true,Dock=DockStyle.Fill};var open=new Button{Text="查看当前步骤",AutoSize=true};var later=new Button{Text="稍后",AutoSize=true};buttons.Controls.Add(open);buttons.Controls.Add(later);layout.Controls.Add(buttons,0,2);Controls.Add(layout);
        open.Click+=(_,_)=>view();later.Click+=(_,_)=>Close();timer.Tick+=(_,_)=>Close();Shown+=(_,_)=>timer.Start();
    }
    protected override void Dispose(bool disposing){if(disposing)timer.Dispose();base.Dispose(disposing);}
}
