using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Guardian.Hud.Guidance;
using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class NativeHudWorldInputTests
{
    private sealed class Rig : IDisposable
    {
        internal readonly Form Owner=new() {ClientSize=new Size(1024,576),FormBorderStyle=FormBorderStyle.None,AutoScaleMode=AutoScaleMode.None};
        internal readonly NativeHudOverlay Hud;
        internal readonly NativeHudOverlay.MainHudInput Input;
        internal readonly WorldHudPointerRouter Router;
        internal readonly Queue<Action> Work=new();
        internal bool Available=true;
        internal Rig()
        {
            _=Owner.Handle;Hud=new NativeHudOverlay(Owner,Owner);
            Input=new NativeHudOverlay.MainHudInput(Hud,Owner,()=>Available);
            Router=new WorldHudPointerRouter(a=>Work.Enqueue(a));Router.SetInput(Input);Drain();
        }
        internal void Edge(int message,Point p,uint data=0)=>Assert.True(Router.TryRoute(message,p,data,false));
        internal void Click(Point p) { Edge(0x201,p);Edge(0x202,p); }
        internal void Drain() {while(Work.TryDequeue(out var work))work();}
        public void Dispose() {Router.SetInput(null);Drain();Hud.Dispose();Owner.Dispose();}
    }
    private sealed class Widget : INativeHudWidget,INativeHudPointerSnapshot
    {
        internal Rectangle Bounds;
        internal int Revision,Clicks;
        public bool Visible=>true;
        public bool WantsAnimationTick=>false;
        public Rectangle ScreenBounds=>Bounds;
        public event EventHandler BoundsOrVisibilityChanged {add{} remove{}}
        public event EventHandler RepaintRequested {add{} remove{}}
        public event EventHandler AnimationStateChanged {add{} remove{}}
        public void Tick(int ms){}
        public void Paint(Graphics g,float dpr,Point origin){}
        public bool TryHitTest(Point p)=>Bounds.Contains(p);
        public object CapturePointerTarget(Point p)=>TryHitTest(p)?Revision:null;
        public void OnMouseEvent(MouseEventArgs e,MouseEventKind kind) {if(kind==MouseEventKind.Click)Clicks++;}
    }
    private sealed class BackInput : IWorldHudInput
    {
        internal int Edges;
        public object HitTest(Point p)=>this;
        public void Dispatch(int message,Point p,uint data,object target) {if(WorldHudPointerRouter.IsDown(message)||WorldHudPointerRouter.IsUp(message))Edges++;}
        public void Cancel(){}
    }
    [Theory]
    [InlineData("revision")][InlineData("viewport")][InlineData("generation")][InlineData("member")][InlineData("unavailable")]
    public void QueuedGestureCannotCrossAChangedInputBoundary(string change)=>Sta(()=>
    {
        using var rig=new Rig();
        var widget=new Widget {Bounds=new Rectangle(rig.Owner.PointToScreen(new Point(10,10)),new Size(80,50))};
        rig.Hud.AddWidget(widget);Point p=Center(widget.Bounds);rig.Click(p);
        if(change=="revision")widget.Revision++;
        if(change=="viewport")rig.Owner.ClientSize=new Size(1100,620);
        if(change=="generation")rig.Hud.CancelPointerGesture();
        if(change=="member")rig.Hud.RemoveWidget(widget);
        if(change=="unavailable")rig.Available=false;
        rig.Drain();Assert.Equal(0,widget.Clicks);
        rig.Available=true;if(change=="member")rig.Hud.AddWidget(widget);
        rig.Click(p);rig.Drain();Assert.Equal(1,widget.Clicks);
    });

    [Fact]
    public void ReleaseOverAnotherHudCannotLeaveAnOldMainPressArmed()=>Sta(()=>
    {
        using var rig=new Rig();var back=new BackInput();
        var widget=new Widget {Bounds=new Rectangle(rig.Owner.PointToScreen(new Point(10,10)),new Size(80,50))};rig.Hud.AddWidget(widget);
        rig.Router.SetInput(new WorldHudInputLayers(rig.Input,back));rig.Drain();
        Point p=Center(widget.Bounds),other=rig.Owner.PointToScreen(new Point(300,300));
        rig.Edge(0x201,p);rig.Edge(0x200,other);rig.Edge(0x202,other);rig.Drain();
        rig.Edge(0x202,p);rig.Drain();Assert.Equal(0,widget.Clicks);Assert.Equal(0,back.Edges);
        rig.Click(p);rig.Drain();Assert.Equal(1,widget.Clicks);
        rig.Edge(0x204,p);rig.Edge(0x201,p);rig.Edge(0x205,p);rig.Edge(0x202,p);rig.Drain();
        Assert.Equal(2,widget.Clicks);Assert.Equal(0,back.Edges);
    });

    [Fact]
    public void NpcReplacementRejectsQueuedOldSessionAndFreshChoiceRunsOnce()=>Sta(()=>
    {
        using var rig=new Rig();var npc=new NpcMenuWidget(rig.Owner);rig.Hud.AddWidget(npc);
        var actions=new List<string>();npc.ActionChosen=(request,scene,action)=>actions.Add(request+":"+action);
        NpcMenuWidget.MenuSession Session(string request)=>new() {RequestId=request,SceneId="scene",Title="菜单",AnchorFx=400,AnchorFy=250,
            Entries=new[]{new NpcMenuWidget.Entry {Id="shop",Label="商店",Enabled=true}}};
        npc.ShowSession(Session("old"));Point p=new(npc.ScreenBounds.Left+30,npc.ScreenBounds.Bottom-15);
        rig.Click(p);npc.ShowSession(Session("new"));rig.Drain();Assert.Empty(actions);
        rig.Click(p);rig.Drain();Assert.Equal(new[]{"new:shop"},actions);
        var mutable=Session("mutable");npc.ShowSession(mutable);rig.Click(p);mutable.Entries[0].Id="changed";rig.Drain();
        Assert.Single(actions);rig.Click(p);rig.Drain();Assert.Equal(new[]{"new:shop","mutable:changed"},actions);
    });

    [Fact]
    public void DialogueReplacementCannotAdvanceAndAQueuedDragRetainsItsOwner()=>Sta(()=>
    {
        using var rig=new Rig();using var dialogue=new NativeDialogueWidget(rig.Owner);
        rig.Hud.AddWidget(dialogue);int verbs=0;dialogue.InputRequested=(frame,verb)=>verbs++;
        var first=Frame(1);dialogue.ShowFrame(first);FinishTyping(dialogue);
        Rectangle viewport=rig.Owner.RectangleToScreen(rig.Owner.ClientRectangle);
        var layout=dialogue.ComputeLayoutForTest(viewport);Point next=Center(layout.Next);
        rig.Click(next);dialogue.ShowFrame(Frame(2));FinishTyping(dialogue);rig.Drain();Assert.Equal(0,verbs);
        rig.Click(next);rig.Drain();Assert.Equal(1,verbs);
        var back=new BackInput();rig.Router.SetInput(new WorldHudInputLayers(rig.Input,back));rig.Drain();
        layout=dialogue.ComputeLayoutForTest(viewport);Point drag=Center(layout.Drag);
        Assert.True(dialogue.TryHitTest(drag),"Drag hit missing: "+layout.Drag+" viewport="+viewport+" bounds="+dialogue.ScreenBounds);
        var dragTarget=((INativeHudPointerSnapshot)dialogue).CapturePointerTarget(drag);
        Assert.True(((INativeHudPointerSnapshot)dialogue).IsCapturedPointerCurrent(dragTarget),"Not a drag target: "+dragTarget);
        Point far=new(viewport.Left+40,viewport.Top+50);
        // All three events arrive before the first UI delivery. Capture must be
        // determined from the original drag target, not the later pointer hit.
        rig.Edge(0x201,drag);rig.Edge(0x200,far);rig.Edge(0x202,far);rig.Drain();
        Assert.Equal(0,back.Edges);Assert.Equal(1,verbs);
        Assert.NotEqual(layout.Panel.Location,dialogue.ComputeLayoutForTest(viewport).Panel.Location);
    });

    [Fact]
    public void DialogueWheelScrollsWithoutLeakingIntoAnotherLayer()=>Sta(()=>
    {
        using var rig=new Rig();using var dialogue=new NativeDialogueWidget(rig.Owner);
        rig.Hud.AddWidget(dialogue);var frame=Frame(1);frame.Text=string.Join("\n",Enumerable.Repeat("较长的对话历史用于检验滚轮。",100));
        dialogue.ShowFrame(frame);FinishTyping(dialogue);
        Point p=Center(dialogue.ComputeLayoutForTest(rig.Owner.RectangleToScreen(rig.Owner.ClientRectangle)).Panel);
        object target=rig.Input.HitTestWheel(p);Assert.NotNull(target);
        int verbs=0;dialogue.InputRequested=(f,v)=>verbs++;
        int first=dialogue.FirstVisibleLineForTest(int.MaxValue,4);
        rig.Edge(0x20A,p,120u<<16);rig.Drain();Assert.Equal(0,verbs);
        Assert.True(dialogue.FirstVisibleLineForTest(int.MaxValue,4)<first);
    });

    [Fact]
    public void PinnedTooltipKeepsRevisionAndClosesExactlyOnceEvenBeforeAcknowledgement()=>Sta(()=>
    {
        using var rig=new Rig();using var tooltip=new NativeTooltipWidget(rig.Owner,null,()=>1f);rig.Hud.AddWidget(tooltip);
        int closes=0;tooltip.DismissRequested+=_=>closes++;
        Assert.True(tooltip.Show(Tooltip(1)));
        Point close=Center(tooltip.ActivePlan.CloseRect);close.Offset(tooltip.ScreenBounds.Location);
        rig.Click(close);Assert.True(tooltip.Show(Tooltip(2)));rig.Drain();Assert.Equal(0,closes);
        close=Center(tooltip.ActivePlan.CloseRect);close.Offset(tooltip.ScreenBounds.Location);
        rig.Click(close);rig.Drain();Assert.Equal(1,closes);
        Point body=Center(tooltip.ScreenBounds);
        Assert.NotNull(rig.Input.HitTestWheel(body));
        int before=tooltip.ScrollLineOffset;rig.Edge(0x20A,body,unchecked((uint)(-120<<16)));rig.Drain();
        Assert.True(tooltip.ScrollLineOffset>before);
        var floating=Tooltip(3);floating["document"]["profile"]="dense";Assert.True(tooltip.Show(floating));
        Assert.Null(((INativeHudPointerSnapshot)tooltip).CaptureWheelTarget(body));
    });

    [Fact]
    public void GuidanceQueuedOldRevisionCannotAdvanceANewPage()=>Sta(()=>
    {
        using var rig=new Rig();
        var catalog=GuidanceCatalog.FromJson("{\"version\":1,\"guides\":[{\"id\":\"start\",\"title\":\"开始\",\"kind\":\"tutorial\",\"pages\":[{\"title\":\"一\",\"text\":\"操作\"},{\"title\":\"二\",\"text\":\"完成\"}]}]}");
        using var guide=new NativeGuidanceWidget(rig.Owner,catalog);rig.Hud.AddWidget(guide);
        guide.Show("request","scene",1,"start",1,new Dictionary<string,string>());
        rig.Click(Center(guide.NextButtonBounds));guide.Show("request","scene",2,"start",1,new Dictionary<string,string>());
        rig.Drain();Assert.Equal(0,guide.CurrentPage);
        rig.Click(Center(guide.NextButtonBounds));rig.Drain();Assert.Equal(1,guide.CurrentPage);
        int closed=0;guide.CloseRequested=(r,s,v)=>closed++;
        rig.Click(Center(guide.CloseButtonBounds));rig.Drain();Assert.Equal(1,closed);
    });

    [Fact]
    public void SaveConfirmationQueuedBeforeAnotherSaveCycleCannotExit()=>Sta(()=>
    {
        using var rig=new Rig();int exits=0;
        var router=new LauncherCommandRouter(null,_=>{},()=>{},()=>{},()=>exits++,_=>{});
        var safe=new SafeExitPanelWidget(rig.Owner,router);safe.ForceGameReady(true);rig.Hud.AddWidget(safe);
        safe.BoundsOrVisibilityChanged+=(_,__)=>NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(null,safe);
        router.TryConsumeSafeExitConfirm=safe.TryAuthorizeExitConfirm;
        safe.Arm();SaveStatus(safe,1);SaveStatus(safe,2);
        Rectangle r=safe.ScreenBounds;Assert.False(r.IsEmpty);
        Point exit=new(r.Left+(int)(r.Width*.85),r.Top+r.Height/2);
        rig.Click(exit);SaveStatus(safe,1);SaveStatus(safe,2);rig.Drain();Assert.Equal(0,exits);
        rig.Click(exit);rig.Drain();Assert.Equal(1,exits);
    });

    [Fact]
    public void NotchClosedMenuRejectsQueuedExitCommandAndFreshCommandRunsOnce()=>Sta(()=>
    {
        using var rig=new Rig();int exits=0;
        using var notch=new NotchWidget(rig.Owner,new FpsRingBuffer(300),"",()=>{},()=>{},()=>exits++,_=>{});
        rig.Hud.AddWidget(notch);notch.ForceGameReadyForTest(true);notch.BeginExpandForTest();notch.Tick(300);notch.OpenOtherMenuForTest(0);Paint(notch);
        Point p=Center(notch.ButtonScreenBoundsForTest("Q"));rig.Click(p);
        notch.BeginCollapseForTest();notch.Tick(300);Paint(notch);rig.Drain();Assert.Equal(0,exits);
        notch.BeginExpandForTest();notch.Tick(300);notch.OpenOtherMenuForTest(0);Paint(notch);
        p=Center(notch.ButtonScreenBoundsForTest("Q"));rig.Click(p);rig.Drain();Assert.Equal(1,exits);
    });

    [Fact]
    public void StageDecisionDoesNotReinterpretQueuedPressAsANewRevision()=>Sta(()=>
    {
        using var rig=new Rig();var router=new LauncherCommandRouter(null,_=>{},()=>{},()=>{},()=>{},_=>{});
        using var right=new RightContextWidget(rig.Owner,router,MapHudDataCatalog.FromPayload(new MapHudPayload {ProtocolVersion=1,Hotspots=new()}));
        right.ForceGameReady(true);right.SetReady();rig.Hud.AddWidget(right);
        var calls=new List<int>();right.IntentRequested+=(intent,run,revision)=>calls.Add(revision);
        right.ApplyState(Stage(1));NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right,null);
        Point p=Center(right.StageActionBoundsForTest(0));rig.Click(p);
        right.ApplyState(Stage(2));NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(right,null);rig.Drain();Assert.Empty(calls);
        rig.Click(Center(right.StageActionBoundsForTest(0)));rig.Drain();Assert.Equal(new[]{2},calls);
    });

    private static Point Center(Rectangle r) {Assert.True(r.Width>0&&r.Height>0);return new(r.X+r.Width/2,r.Y+r.Height/2);}
    private static void Paint(INativeHudWidget widget)
    {Rectangle r=widget.ScreenBounds;using var bmp=new Bitmap(Math.Max(1,r.Width),Math.Max(1,r.Height));using var g=Graphics.FromImage(bmp);widget.Paint(g,1,r.Location);}
    private static NativeDialogueFrame Frame(int revision)=>new() {RequestId="dialogue",SceneId="scene",Revision=revision,Text="测试文本",Name="角色",LineIndex=0,LineCount=2,PortraitKey="",Expression="普通",ImageAction="clear"};
    private static void FinishTyping(NativeDialogueWidget widget)
    {widget.TypingIntervalMs=1;for(int i=0;i<300&&!widget.TypingCompleteForTest;i++)widget.Tick(50);Assert.True(widget.TypingCompleteForTest);}
    private static JObject Tooltip(int revision)=>new() {["version"]=1,["requestId"]="tooltip",["sceneId"]="scene",["owner"]="item",["revision"]=revision,["x"]=500,["y"]=250,
        ["document"]=new JObject {["version"]=1,["title"]="注释",["profile"]="pinned",["sections"]=new JArray(new JObject {["role"]="description",["runs"]=new JArray(new JObject {["text"]=string.Join("\n",Enumerable.Repeat("逐行滚动的长注释。",100))})})}};
    private static void SaveStatus(SafeExitPanelWidget widget,int value)=>widget.OnUiDataChanged(new Dictionary<string,string>{{"sv","sv:"+value}},new HashSet<string>{"sv"});
    private static StageOutcomeState Stage(int revision)
    {
        var message=new JObject {["task"]="stage_outcome",["payload"]=new JObject {["v"]=3,["runId"]="run",["revision"]=revision,["stageName"]="关卡",["difficulty"]="普通",["outcome"]="victory",["life"]="alive",["activeFrames"]=100,["reviveCoins"]=0,["reviveAllowed"]=false,["reviveBlockedReason"]="",["canReturnBase"]=true,["canSelectReturn"]=false,["returnFailure"]="",["settlement"]="none",["remainingRewards"]=0}};
        Assert.True(StageOutcomeState.TryParseMessage(message,out var state,out var error),error);return state;
    }
    private static void Sta(Action action)
    {
        Exception failure=null;var thread=new Thread(()=>{try{action();}catch(Exception error){failure=error;}});
        thread.SetApartmentState(ApartmentState.STA);thread.Start();Assert.True(thread.Join(20000));
        if(failure!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
