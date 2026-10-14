using CF7Launcher.Tests.Guardian;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;
namespace CF7Launcher.Tests.Guardian {
 [ResourceCaseGuard]
 public sealed class SolIndependentWindowsTraceTests {
  const int Down=0x0201,Activate=0x0021;
  [StructLayout(LayoutKind.Sequential)] struct Source { public uint DeviceType,OriginId; }
  [DllImport("user32.dll")] static extern bool InSendMessage();
  [DllImport("user32.dll")] static extern int GetMessageTime();
  [DllImport("user32.dll")] static extern bool GetCurrentInputMessageSource(out Source source);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr h,int msg,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
  static IntPtr SendMessage(IntPtr h,int msg,IntPtr w,IntPtr l){
   FixtureResourceGuard.Before("owned SendMessageTimeout",h);
   IntPtr ok=SendMessageTimeout(h,msg,w,l,0x22,500,out IntPtr result);
   FixtureResourceGuard.Before("owned SendMessageTimeout completed",h);
   if(ok==IntPtr.Zero)throw new TimeoutException("Owned send failed/timeout error="+Marshal.GetLastWin32Error());
   return result;
  }
  sealed class Hud:NativeHudOverlay {
   public int ForcedSource, BusinessDowns; public bool InSend,SourceOk,Queued; public uint Device,Origin;
   public Action Reenter; private bool nested;
   public Hud(Form owner,Control anchor):base(owner,anchor,false){}
   public void DispatchDown(){FixtureResourceGuard.Before("direct own WndProc",Handle);var m=Message.Create(Handle,Down,(IntPtr)1,(IntPtr)((10<<16)|10));base.WndProc(ref m);}

   protected override bool TryReadCurrentPointerSource(out uint device,out uint origin){
    if(ForcedSource==2)throw new InvalidOperationException("owned source API exception");
    if(ForcedSource==1){device=0;origin=0;return false;}
    return base.TryReadCurrentPointerSource(out device,out origin);
   }
   public void Rebuild(){FixtureResourceGuard.Before("owned HWND rebuild before",Handle);RecreateHandle();FixtureResourceGuard.Before("owned HWND rebuild after",Handle);}
   protected override void OnMouseDown(MouseEventArgs e){
    BusinessDowns++;
    if(!nested&&Reenter!=null){nested=true;try{Reenter();}finally{nested=false;}}
    base.OnMouseDown(e);
   }
   protected override void WndProc(ref Message m){
    if(m.Msg==SolIndependentWindowsTraceTests.Down||m.Msg==SolIndependentWindowsTraceTests.Activate){
     InSend=InSendMessage();SourceOk=GetCurrentInputMessageSource(out Source s);Device=s.DeviceType;Origin=s.OriginId;Queued=HasQueuedPointerTimestamp();
    }
    base.WndProc(ref m);
   }
  }
  static JObject[] Rows(List<string> batches){
   FocusTrace.Flush();
   return batches.SelectMany(x=>x.Split(new[]{Environment.NewLine},StringSplitOptions.RemoveEmptyEntries))
    .Select(x=>JObject.Parse(x.Substring("[FocusTrace] ".Length))).ToArray();
  }
  static void Sta(Action action){
   Exception error=null;
   FixtureResourceGuard.Before("STA fixture creation");
   var t=new Thread(()=>{try{FixtureResourceGuard.Before("STA fixture entry");action();FixtureResourceGuard.Before("STA fixture final");}catch(Exception e){error=e;}}){IsBackground=true};
   t.SetApartmentState(ApartmentState.STA);t.Start();
   if(!t.Join(5000))throw new TimeoutException("Owned fixture STA exceeded bounded deadline");
   if(error!=null)ExceptionDispatchInfo.Capture(error).Throw();
  }
  [Fact] public void UserTakeoverGuardRejectsBeforeAnyOwnedWindowOperation(){
   string old=Environment.GetEnvironmentVariable("CF7_TEST_INPUT_TICK");int effects=0;
   try{Environment.SetEnvironmentVariable("CF7_TEST_INPUT_TICK",(uint.Parse(old)^1u).ToString());
    Assert.Throws<OperationCanceledException>(()=>{FixtureResourceGuard.Before("simulated takeover no window effect");effects++;});Assert.Equal(0,effects);
   }finally{Environment.SetEnvironmentVariable("CF7_TEST_INPUT_TICK",old);}
  }
  [Fact] public void ExpiredResourceGuardRejectsBeforeFinalSideEffect(){
   string old=Environment.GetEnvironmentVariable("CF7_TEST_WINDOW_END");int effects=0;
   try{Environment.SetEnvironmentVariable("CF7_TEST_WINDOW_END",DateTimeOffset.UtcNow.AddSeconds(-1).ToString("O"));
    Assert.Throws<OperationCanceledException>(()=>{FixtureResourceGuard.Before("simulated expiry no effect");effects++;});Assert.Equal(0,effects);
   }finally{Environment.SetEnvironmentVariable("CF7_TEST_WINDOW_END",old);}
  }
  [Fact] public void CrossThreadOwnedTimeoutStopsSenderAndUnwindsWindowResources()=>Sta(()=>{
   using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();
   hud.Reenter=()=>Thread.Sleep(650);Exception error=null;using var done=new ManualResetEventSlim();
   var sender=new Thread(()=>{try{SendMessage(h,Down,(IntPtr)1,(IntPtr)((10<<16)|10));}catch(Exception e){error=e;}finally{done.Set();}}){IsBackground=true};sender.Start();var clock=System.Diagnostics.Stopwatch.StartNew();
   while(!done.IsSet&&clock.ElapsedMilliseconds<2000){Application.DoEvents();Thread.Sleep(1);}Assert.True(sender.Join(600));Assert.IsType<TimeoutException>(error);Assert.Equal(fg,GetForegroundWindow());
   Console.WriteLine("Owned timeout: sender joined; receiver dispatch may have happened; only this fixture is disposed");
  });
  [Theory][InlineData(1)][InlineData(2)] public void SourceApiFailureCannotChangeBusinessInputOrPublishQueueAge(int failure)=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();hud.ForcedSource=failure;
    Assert.Null(Record.Exception(()=>hud.DispatchDown()));Assert.Equal(1,hud.BusinessDowns);Assert.Equal(fg,GetForegroundWindow());
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").Select(x=>x["data"]).ToArray();Assert.Equal(2,rows.Length);
    Assert.All(rows,x=>Assert.True(x["messageAgeMs"]==null||x["messageAgeMs"].Type==JTokenType.Null));
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void RingResetDuringDispatchCannotPairExitWithAnotherTraceSession()=>Sta(()=>{
   var batches=new List<string>();Action<string> sink=x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);};FocusTrace.Start(sink,false);
   try{using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();string old=FocusTrace.Session;
    hud.Reenter=()=>{FocusTrace.Stop();FocusTrace.Start(sink,false);};hud.DispatchDown();
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").ToArray();Assert.Equal(fg,GetForegroundWindow());Assert.Single(rows);Assert.Equal(old,(string)rows[0]["session"]);Assert.Equal("enter",(string)rows[0]["data"]["phase"]);
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void OwnedWindowRebuildKeepsReceiverIdentityCapturedAtEntry()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();hud.Reenter=hud.Rebuild;hud.DispatchDown();
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").Select(x=>x["data"]).ToArray();Assert.Equal(fg,GetForegroundWindow());Assert.Equal(2,rows.Length);Assert.All(rows,x=>Assert.Equal(h.ToInt64(),(long)x["receiver"]));Assert.Equal(1,hud.BusinessDowns);
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void CrossThreadMouseActivateUsesUnavailableQueueTimestamp()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);IntPtr oh=owner.Handle;using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();Exception error=null;using var done=new ManualResetEventSlim();
    var sender=new Thread(()=>{try{SendMessage(h,Activate,oh,(IntPtr)((Down<<16)|1));}catch(Exception e){error=e;}finally{done.Set();}}){IsBackground=true};sender.Start();var clock=System.Diagnostics.Stopwatch.StartNew();while(!done.IsSet&&clock.ElapsedMilliseconds<2000){Application.DoEvents();Thread.Sleep(1);}Assert.True(sender.Join(600));if(error!=null)throw error;
    var row=Rows(batches).Single(x=>(string)x["event"]=="hud.native_mouse_activate")["data"];Assert.Equal(fg,GetForegroundWindow());Assert.Equal("observed",(string)row["correlation"]["delaySource"]);Assert.False((bool)row["messageTimeAvailable"]);
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void TraceStoppedDuringDispatchDoesNotCreateAnUnmatchedExit()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{
    using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);IntPtr ownerH=owner.Handle;
    using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();
    hud.Reenter=()=>{FocusTrace.Flush();FocusTrace.Stop();};hud.DispatchDown();
    Assert.Equal(fg,GetForegroundWindow());
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").Select(x=>x["data"]).ToArray();
    Assert.Single(rows);Assert.Equal("enter",(string)rows[0]["phase"]);
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void TraceStartedDuringUntracedDispatchDoesNotInventEntryOrExit()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Stop();
   try{
    using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);IntPtr ownerH=owner.Handle;
    using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();
    hud.Reenter=()=>FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);hud.DispatchDown();
    Assert.Equal(fg,GetForegroundWindow());Assert.Empty(Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse"));
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void ExceptionUnwindingRetainsTheEntrySample()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{
    using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);IntPtr ownerH=owner.Handle;
    using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();
    Point p=hud.PointToScreen(new Point(10,10));FocusTrace.SetTarget(new Rectangle(p.X-2,p.Y-2,5,5));int tm=GetMessageTime();
    string a=FocusTrace.PhysicalEdge(Down,p,1,unchecked((uint)(tm-30)),7);FocusTrace.PhysicalEdge(0x0202,p,1,unchecked((uint)(tm-25)),7);
    FocusTrace.PhysicalEdge(Down,p,1,unchecked((uint)(tm-20)),7);
    hud.Reenter=()=>throw new InvalidOperationException("owned fixture exception");
    Assert.Throws<InvalidOperationException>(()=>hud.DispatchDown());
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").Select(x=>x["data"]).ToArray();
    Assert.Equal(fg,GetForegroundWindow());Assert.Equal(2,rows.Length);Assert.Equal(a,(string)rows[0]["mouseId"]);Assert.Equal(a,(string)rows[1]["mouseId"]);
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void CrossThreadSentMouseMustNotPublishTrustedQueueAge()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{
    using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);IntPtr ownerH=owner.Handle;
    using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();
    using var done=new ManualResetEventSlim();Exception sendError=null;
    var sender=new Thread(()=>{try{SendMessage(h,Down,(IntPtr)1,(IntPtr)((10<<16)|10));}catch(Exception e){sendError=e;}finally{done.Set();}}){IsBackground=true};
    sender.Start();var clock=System.Diagnostics.Stopwatch.StartNew();
    while(!done.IsSet&&clock.ElapsedMilliseconds<2500){Application.DoEvents();Thread.Sleep(1);}
    Assert.True(done.IsSet,"Owned cross-thread sender did not complete");Assert.True(sender.Join(100),"Owned sender still running");if(sendError!=null)ExceptionDispatchInfo.Capture(sendError).Throw();
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").Select(x=>x["data"]).ToArray();
    Assert.Equal(fg,GetForegroundWindow());Assert.Equal(2,rows.Length);Assert.True(hud.InSend);Assert.False(hud.Queued);
    Console.WriteLine("cross-thread own-HWND receiver="+h.ToInt64()+" pid="+Environment.ProcessId+" inSend="+hud.InSend+" reportedAge="+rows[0]["messageAgeMs"]);
    Assert.True(rows.All(x=>x["messageAgeMs"]==null||x["messageAgeMs"].Type==JTokenType.Null));
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void NestedWndProcMustKeepEachEntrySample()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{
    using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);IntPtr ownerH=owner.Handle;
    using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();
    Point p=hud.PointToScreen(new Point(10,10)),q=hud.PointToScreen(new Point(20,20));
    FocusTrace.SetTarget(new Rectangle(Math.Min(p.X,q.X)-2,Math.Min(p.Y,q.Y)-2,30,30));int tm=GetMessageTime();
    string a=FocusTrace.PhysicalEdge(Down,p,1,unchecked((uint)(tm-40)),7);
    FocusTrace.PhysicalEdge(0x0202,p,1,unchecked((uint)(tm-35)),7);
    FocusTrace.PhysicalEdge(Down,p,1,unchecked((uint)(tm-30)),7);
    FocusTrace.PhysicalEdge(0x0202,p,1,unchecked((uint)(tm-25)),7);
    string c=FocusTrace.PhysicalEdge(Down,q,1,unchecked((uint)(tm-20)),7);
    FocusTrace.PhysicalEdge(0x0202,q,1,unchecked((uint)(tm-15)),7);
    FocusTrace.PhysicalEdge(Down,q,1,unchecked((uint)(tm-10)),7);
    hud.Reenter=()=>SendMessage(h,Down,(IntPtr)1,(IntPtr)((20<<16)|20));
    SendMessage(h,Down,(IntPtr)1,(IntPtr)((10<<16)|10));
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").Select(x=>x["data"]).ToArray();
    Assert.Equal(fg,GetForegroundWindow());Assert.Equal(4,rows.Length);
    Console.WriteLine("nested own-HWND receiver="+h.ToInt64()+" pid="+Environment.ProcessId+" correlations="+string.Join(",",rows.Select(x=>(string)x["mouseId"])));
    Assert.Equal(a,(string)rows[0]["mouseId"]);Assert.Equal(c,(string)rows[1]["mouseId"]);
    Assert.Equal(c,(string)rows[2]["mouseId"]);Assert.Equal(a,(string)rows[3]["mouseId"]);
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void ActualHudWndProcExitMustKeepItsEntryCorrelation()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{
    using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);
    IntPtr ownerH=owner.Handle;
    using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle;
    Point client=new Point(10,10),point=hud.PointToScreen(client);
    FocusTrace.SetTarget(new Rectangle(point.X-2,point.Y-2,5,5));
    int tm=GetMessageTime();
    string a=FocusTrace.PhysicalEdge(Down,point,1,unchecked((uint)(tm-30)),7);
    FocusTrace.PhysicalEdge(0x0202,point,1,unchecked((uint)(tm-25)),7);
    string b=FocusTrace.PhysicalEdge(Down,point,1,unchecked((uint)(tm-20)),7);
    IntPtr foreground=GetForegroundWindow();
    SendMessage(h,Down,(IntPtr)1,(IntPtr)((10<<16)|10));
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").Select(x=>x["data"]).ToArray();
    Assert.Equal(foreground,GetForegroundWindow());
    Assert.Equal(2,rows.Length);
    string enter=(string)rows.Single(x=>(string)x["phase"]=="enter")["mouseId"];
    string exit=(string)rows.Single(x=>(string)x["phase"]=="exit")["mouseId"];
    Console.WriteLine("actual own-HWND SendMessage; manually seeded ring A="+a+" B="+b+" enter="+enter+" exit="+exit+" sourceDevice="+hud.Device+" inSend="+hud.InSend);
    Assert.Equal(a,enter);Assert.Equal(enter,exit);
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void SameThreadSentMouseMustNotPublishTrustedQueueAge()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{
    using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);IntPtr ownerH=owner.Handle;
    using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();
    SendMessage(h,Down,(IntPtr)1,(IntPtr)((10<<16)|10));
    var rows=Rows(batches).Where(x=>(string)x["event"]=="hud.native_mouse").Select(x=>x["data"]).ToArray();
    Assert.Equal(fg,GetForegroundWindow());Assert.Equal(2,rows.Length);
    Console.WriteLine("same-thread own-HWND source: apiOk="+hud.SourceOk+" device="+hud.Device+" origin="+hud.Origin+" inSend="+hud.InSend+" businessQueued="+hud.Queued+" reportedAge="+rows[0]["messageAgeMs"]);
    Assert.False(hud.InSend);Assert.Equal(0u,hud.Device);Assert.False(hud.Queued);
    Assert.True(rows.All(x=>x["messageAgeMs"]==null||x["messageAgeMs"].Type==JTokenType.Null),"Unknown/sent source must not publish a precise queued age");
   }finally{FocusTrace.Stop();}
  });
  [Fact] public void SameThreadMouseActivateMustUseObservedCorrelationDomain()=>Sta(()=>{
   var batches=new List<string>();FocusTrace.Start(x=>{batches.Add(x);FixtureResourceGuard.SaveTrace(x);},false);
   try{
    using var owner=new Form();using var anchor=new Panel();owner.Controls.Add(anchor);IntPtr ownerH=owner.Handle;
    using var hud=new Hud(owner,anchor);IntPtr h=hud.Handle,fg=GetForegroundWindow();
    SendMessage(h,Activate,ownerH,(IntPtr)((Down<<16)|1));
    var data=Rows(batches).Single(x=>(string)x["event"]=="hud.native_mouse_activate")["data"];
    Assert.Equal(fg,GetForegroundWindow());
    Console.WriteLine("same-thread WM_MOUSEACTIVATE source: apiOk="+hud.SourceOk+" device="+hud.Device+" inSend="+hud.InSend+" delaySource="+data["correlation"]["delaySource"]);
    Assert.False(hud.InSend);Assert.Equal(0u,hud.Device);Assert.False(hud.Queued);
    Assert.Equal("observed",(string)data["correlation"]["delaySource"]);
   }finally{FocusTrace.Stop();}
  });
 }
}
