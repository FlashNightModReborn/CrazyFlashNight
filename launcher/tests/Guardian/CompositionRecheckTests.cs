using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Runtime.ExceptionServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;
namespace CF7Launcher.Tests.Guardian {
 [ResourceCaseGuard] public class CompositionRecheckTests {
  static void Set(object o,string field,object data)=>o.GetType().GetField(field,BindingFlags.NonPublic|BindingFlags.Instance).SetValue(o,data);
  static void Call(object o,string method,params object[] args){try{o.GetType().GetMethod(method,BindingFlags.NonPublic|BindingFlags.Instance).Invoke(o,args);}catch(TargetInvocationException e){ExceptionDispatchInfo.Capture(e.InnerException).Throw();}}
  static JObject Close(string instance,string reason=null){var p=new JObject{["type"]="panel",["panel"]="intelligence",["cmd"]="close"};if(instance!=null)p["panelInstanceId"]=instance;if(reason!=null)p["reason"]=reason;return p;}
  static void Sta(Action a){Exception error=null;var t=new Thread(()=>{try{FixtureResourceGuard.Before("F02 owned STA");a();FixtureResourceGuard.Before("F02 STA terminal");}catch(Exception e){error=e;}}){IsBackground=true};t.SetApartmentState(ApartmentState.STA);t.Start();if(!t.Join(5000))throw new TimeoutException("Owned F02 thread timeout");if(error!=null)ExceptionDispatchInfo.Capture(error).Throw();}
  [Theory][InlineData(0,1017)][InlineData(180,837)]
  public void HiddenBootstrapAnchorTracksClientBeforeNativeResize(int logHeight,int expectedHeight)=>Sta(()=>{
   using var owner=new Form {ClientSize=new System.Drawing.Size(1920,1017)};
   using var panel=new Panel {Dock=DockStyle.Fill,Visible=false,Size=new System.Drawing.Size(200,100)};
   owner.Controls.Add(panel);
   Assert.True(GuardianForm.SyncRuntimeHostBounds(owner,panel,logHeight));
   Assert.Equal(new System.Drawing.Rectangle(0,0,1920,expectedHeight),panel.Bounds);
   Assert.False(panel.Visible);Assert.False(owner.Visible);
   Assert.False(GuardianForm.SyncRuntimeHostBounds(owner,panel,logHeight));
   owner.ClientSize=new System.Drawing.Size(960,540);
   GuardianForm.SyncRuntimeHostBounds(owner,panel,logHeight);
   Assert.Equal(new System.Drawing.Size(960,540-logHeight),panel.Size);
  });
  [Fact] public void InvalidOrRetiredViewportCannotCollapseAnchor()=>Sta(()=>{
   using var owner=new Form {ClientSize=new System.Drawing.Size(800,450)};
   using var panel=new Panel {Visible=false,Size=new System.Drawing.Size(800,450)};
   Assert.False(GuardianForm.SyncRuntimeHostBounds(owner,panel,450));
   Assert.Equal(new System.Drawing.Size(800,450),panel.Size);
   owner.WindowState=FormWindowState.Minimized;
   Assert.False(GuardianForm.SyncRuntimeHostBounds(owner,panel,0));
   panel.Dispose();Assert.False(GuardianForm.SyncRuntimeHostBounds(owner,panel,0));
  });
  [Theory][InlineData(null)][InlineData("old")][InlineData("wrong")]
  public void StaleCloseMustNotFallThroughGenericInbound(string instance)=>Sta(()=>{
   using var owner=new Form();using var s=new CompositionHelpSurface(owner,"owned","owned",CompositionPanelProfile.Intelligence);
   Set(s,"_ready",true);Set(s,"_active",true);Set(s,"_panelInstance","current");var received=new List<JObject>();s.InboundPanelMessage+=received.Add;
   s.DispatchEnvelopeForRecheck(Close(instance));Assert.Empty(received);
  });
  [Theory][InlineData("esc")][InlineData("deactivated")][InlineData("capture_lost")][InlineData("process_failed")]
  public void HostCloseReasonMustReachFinalEnvelope(string reason)=>Sta(()=>{
   using var owner=new Form();using var s=new CompositionHelpSurface(owner,"owned","owned",CompositionPanelProfile.Intelligence);
   Set(s,"_ready",true);Set(s,"_active",true);Set(s,"_panelInstance","current");HostCloseContext delivered=null;s.HostCloseRequested+=x=>delivered=x;
   IntPtr own=s.Handle;Call(s,"RequestClose",reason,null);Call(s,"TryDeliverClose");
   Assert.NotNull(delivered);Assert.Equal("current",delivered.Endpoint.Instance);
   var cause=reason switch { "esc"=>NativeCloseCause.Escape,"deactivated"=>NativeCloseCause.Deactivated,
       "capture_lost"=>NativeCloseCause.CaptureLost,_=>NativeCloseCause.ProcessFailed };
   Assert.Equal(cause,delivered.Cause);Assert.Null(delivered.Envelope["reason"]);
  });
  [Fact] public void PendingCloseCannotBeRelabeledAsReplacementInstance()=>Sta(()=>{
   using var owner=new Form();using var s=new CompositionHelpSurface(owner,"owned","owned",CompositionPanelProfile.Intelligence);
   Set(s,"_ready",true);Set(s,"_active",true);Set(s,"_panelInstance","A");IntPtr own=s.Handle;HostCloseContext delivered=null;s.HostCloseRequested+=x=>delivered=x;
   Call(s,"RequestClose","esc",null);Set(s,"_panelInstance","B");Call(s,"TryDeliverClose");
   Assert.True(delivered==null||delivered.Endpoint.Instance=="A","Old callback relabeled as new instance");
  });
  [Fact] public void UnrelatedOwnedWindowMustNotQualifyForGameRestore()=>Sta(()=>{
   using var owner=new Form();using var unrelated=new Form();using var s=new CompositionHelpSurface(owner,"owned","owned",CompositionPanelProfile.Help);
   s.ForegroundReaderForRecheck=()=>unrelated.Handle;
   Assert.False(s.CanRestoreGameFocus,"A different same-process owner has taken foreground");
  });
  [Theory][InlineData("help")][InlineData("intelligence")]
  public void ApplicationSwitchMustPreserveReadingPanel(string panel)=>Sta(()=>{
   using var owner=new Form();using var s=new CompositionHelpSurface(owner,"owned","owned",
    panel=="help"?CompositionPanelProfile.Help:CompositionPanelProfile.Intelligence);
   IntPtr ownerHandle=owner.Handle,surfaceHandle=s.Handle;
   Set(s,"_ready",true);Set(s,"_active",true);Set(s,"_panelInstance","reading.current");
   var committed=new System.Drawing.Rectangle(20,30,800,450);Set(s,"_committed",committed);
   var lease=s.CaptureEndpointLease();int generation=s.SessionGeneration;
   var closes=new List<HostCloseContext>();s.HostCloseRequested+=closes.Add;
   // 前台迁移的空窗不能转成关闭，也不授予抢回游戏的许可。
   s.ForegroundReaderForRecheck=()=>IntPtr.Zero;
   Call(s,"OnDeactivate",EventArgs.Empty);Application.DoEvents();Application.DoEvents();
   Assert.Empty(closes);Assert.True(s.Active);Assert.True(s.IsLeaseCurrent(lease));
   Assert.False(s.CanRestoreGameFocus);Assert.Equal(generation,s.SessionGeneration);
   Assert.Equal(committed,(System.Drawing.Rectangle)s.GetType().GetField("_committed",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(s));
   s.ForegroundReaderForRecheck=()=>ownerHandle;Call(s,"OnActivated",EventArgs.Empty);
   Assert.True(s.Active);Assert.True(s.IsLeaseCurrent(lease));Assert.Equal(generation,s.SessionGeneration);
  });
  [Fact] public void TransitionBackingMustRemainAnExactPresentationOwner()=>Sta(()=>{
   using var owner=new Form();using var unrelated=new Form();
   using var controller=new SceneTransitionController(owner,owner,System.IO.Path.GetTempPath(),
    a=>a(),_=>true,()=>true,_=>false,_=>false,Array.Empty<OverlayBase>(),_=>{},
    presentationPolicy:SceneTransitionPresentationPolicy.ArenaWorker);
   var surface=controller.SettlementSurface;
   var backing=(Form)controller.GetType().GetField("_fallback",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(controller);
   backing.Show();Assert.True(backing.Visible);
   surface.ForegroundReaderForRecheck=()=>backing.Handle;
   Assert.True(surface.CanRestoreGameFocus,"The controller's visible backing must not block its own surface");
   surface.ForegroundReaderForRecheck=()=>unrelated.Handle;
   Assert.False(surface.CanRestoreGameFocus,"Unrelated same-process windows remain excluded");
   surface.ForegroundReaderForRecheck=()=>backing.Handle;
   backing.Hide();Assert.False(surface.CanRestoreGameFocus,"Hidden backing grants no presentation ownership");
   backing.Owner=unrelated;backing.Show();Assert.False(surface.CanRestoreGameFocus,"Reowned backing is no longer this controller's source");
   backing.Owner=owner;Assert.True(surface.CanRestoreGameFocus);
   var retiredHandle=backing.Handle;backing.Dispose();surface.ForegroundReaderForRecheck=()=>retiredHandle;
   Assert.False(surface.CanRestoreGameFocus,"Disposed backing grants no presentation ownership");
   surface.ForegroundReaderForRecheck=()=>IntPtr.Zero;Assert.False(surface.CanRestoreGameFocus);
  });
  [Fact] public void CapturedOldTimerCannotDeliverOrClearNewClose()=>Sta(()=>{
   using var owner=new Form();using var s=new CompositionHelpSurface(owner,"owned","owned",CompositionPanelProfile.Intelligence);
   Set(s,"_ready",true);Set(s,"_active",true);Set(s,"_panelInstance","A");IntPtr own=s.Handle;
   Call(s,"RequestClose","esc",null);
   var oldTick=(EventHandler)s.GetType().GetField("_pendingCloseTick",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(s);
   Call(s,"BindEndpointSession","B");Set(s,"_closePending",false);Call(s,"RequestClose","esc",null);
   var current=s.GetType().GetField("_pendingHostClose",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(s);
   oldTick(null,EventArgs.Empty);
   Assert.Same(current,s.GetType().GetField("_pendingHostClose",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(s));
  });
  [Fact] public void LegalRetirementTailDoesNotRequireOldSurfaceActive()=>Sta(()=>{
   using var owner=new Form();using var s=new CompositionHelpSurface(owner,"owned","owned");Set(s,"_ready",true);Set(s,"_active",true);IntPtr h=owner.Handle;s.ForegroundReaderForRecheck=()=>h;
   s.Retire();Assert.False(s.Active);Assert.True(s.CanRestoreGameFocus);
  });
  [Theory][InlineData(null)][InlineData("stale")][InlineData("wrong")]
  public void HostDirectStaleCloseMustLeaveCurrentInstanceAlive(string instance){
   var pumps=new Queue<Action>();using var host=new PanelHostController(a=>pumps.Enqueue(a),a=>a());host.OpenPanel("intelligence","{}");while(pumps.Count>0)pumps.Dequeue()();
   string current=host.ActivePanelInstanceId;var form=(WebOverlayForm)RuntimeHelpers.GetUninitializedObject(typeof(WebOverlayForm));GC.SuppressFinalize(form);Set(form,"_webReady",true);Set(form,"_panelHost",host);
   form.HandleCompositionIntelligenceMessage(Close(instance).ToString());while(pumps.Count>0)pumps.Dequeue()();Assert.Equal(current,host.ActivePanelInstanceId);
  }
  [Fact] public void QueuedOrdinaryCloseMustNotRetireNewExactInstance(){
   var pumps=new Queue<Action>();using var host=new PanelHostController(a=>pumps.Enqueue(a),a=>a());host.OpenPanel("intelligence","{}");while(pumps.Count>0)pumps.Dequeue()();
   string current=host.ActivePanelInstanceId;var form=(WebOverlayForm)RuntimeHelpers.GetUninitializedObject(typeof(WebOverlayForm));GC.SuppressFinalize(form);Set(form,"_webReady",true);Set(form,"_panelHost",host);
   form.HandleCompositionIntelligenceMessage(Close(current).ToString());Set(host,"_activePanelInstanceId","replacement.B");while(pumps.Count>0)pumps.Dequeue()();Assert.Equal("replacement.B",host.ActivePanelInstanceId);
  }
  [Fact] public void ExactCloseExecutionControlRejectsAReplacement(){
   var pumps=new Queue<Action>();using var host=new PanelHostController(a=>pumps.Enqueue(a),a=>a());host.OpenPanel("intelligence","{}");while(pumps.Count>0)pumps.Dequeue()();
   string current=host.ActivePanelInstanceId;host.TryClosePanelExact("intelligence",current,null);Set(host,"_activePanelInstanceId","replacement.B");while(pumps.Count>0)pumps.Dequeue()();Assert.Equal("replacement.B",host.ActivePanelInstanceId);
  }
 }
}
