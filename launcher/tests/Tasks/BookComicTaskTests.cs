using System;using System.Collections.Generic;using Newtonsoft.Json.Linq;using Xunit;using CF7Launcher.Tasks;
namespace CF7Launcher.Tests.Tasks {
 public class BookComicTaskTests {
  static JObject Data(string id="bookcomic:1")=>new JObject{["v"]=1,["presentationId"]=id,["slot"]="bookrun_test",["sceneId"]="scene:1",["pageId"]="prologue"};
  static JObject Web(string cmd,string call,JObject data,string instance="panel:1")=>new JObject{["panel"]="book-comic",["domain"]="book-comic",["cmd"]=cmd,["callId"]=call,["panelInstanceId"]=instance,["payload"]=data};
  static JObject Reply(JObject sent,string phase,string op){var r=(JObject)sent.DeepClone();r["operation"]=op;r["success"]=true;r["phase"]=phase;r["error"]="";return r;}
  static void FinishCf6(BookComicTask task,List<JObject> sent,JObject data,string reason="continue",string phase="finished"){
   Assert.True(task.Reserve(data));Assert.True(task.Bind("panel:1",data.ToString()));
   task.HandleWebRequest(reason,Web(reason,"finish",data));
   task.HandleFlashResponse(Reply(sent[sent.Count-1],phase,"finish"),null);
  }
  [Theory][InlineData("cf6-s4","cf6-s5","continue")][InlineData("cf6-s4","cf6-s5","skip")]
  [InlineData("cf6-s7","cf6-end","continue")][InlineData("cf6-s7","cf6-end","skip")]
  public void AuthoredSuccessorWaitsForExactCloseThenUsesOriginalReservation(string first,string second,string reason){
   var sent=new List<JObject>();var closes=new List<string>();var opens=0;
   using var task=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});
   task.SetPostToWeb(s=>{},null,closes.Add);var before=Data();before["pageId"]=first;
   FinishCf6(task,sent,before,reason);Assert.Equal("panel:1",Assert.Single(closes));
   var next=Data("bookcomic:2");next["pageId"]=second;
   Assert.False(task.Reserve(next)); // The old native/Web surface still owns admission.
   Assert.True(task.TryQueueSuccessor(next,"book-comic","panel:1",d=>{
    opens++;Assert.True(task.Reserve(d));Assert.True(task.Bind("panel:2",d.ToString()));return true;
   }));
   Assert.Equal(0,opens);Assert.False(task.CanOpen(next.ToString()));
   Assert.False(task.TryQueueSuccessor(next,"book-comic","panel:1",d=>{opens++;return true;}));
   task.OnHostClosed("panel:1"); // Close observer runs before exact completion.
   Assert.Equal(0,opens);task.OnPresentationClosed("foreign",true);Assert.Equal(0,opens);
   task.OnPresentationClosed("panel:1",true);Assert.Equal(1,opens);Assert.True(task.CanOpen(next.ToString()));
   task.OnPresentationClosed("panel:1",true);Assert.Equal(1,opens);
   task.HandleFlashResponse(Reply(sent[0],"finished","finish"),null);Assert.Equal(1,opens);
  }
  [Theory][InlineData("panel")][InlineData("instance")][InlineData("slot")][InlineData("scene")]
  [InlineData("page")][InlineData("presentation")]
  public void ClosingHandoffRejectsForeignOrUnauthoredSuccessor(string boundary){
   var sent=new List<JObject>();using var task=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});
   task.SetPostToWeb(s=>{},null,s=>{});var before=Data();before["pageId"]="cf6-s4";FinishCf6(task,sent,before);
   var next=Data("bookcomic:2");next["pageId"]="cf6-s5";var panel="book-comic";var instance="panel:1";
   if(boundary=="panel")panel="inventory";if(boundary=="instance")instance="foreign";
   if(boundary=="slot")next["slot"]="other";if(boundary=="scene")next["sceneId"]="other";
   if(boundary=="page")next["pageId"]="cf6-s4";if(boundary=="presentation")next["presentationId"]=before["presentationId"];
   Assert.False(task.TryQueueSuccessor(next,panel,instance,d=>throw new Exception("foreign open")));
   task.OnPresentationClosed("panel:1",true);
  }
  [Theory][InlineData("close_failed")][InlineData("disconnected")][InlineData("socket_not_ready")]
  [InlineData("successor_expired")][InlineData("predecessor_expired")][InlineData("disposed")]
  public void QueuedSuccessorCannotSurviveFailedOrRetiredHandoff(string boundary){
   var ready=true;var sent=new List<JObject>();var opens=0;
   using var task=new BookComicTask(()=>ready,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});
   task.SetPostToWeb(s=>{},null,s=>{});var before=Data();before["pageId"]="cf6-s4";FinishCf6(task,sent,before);
   var next=Data("bookcomic:2");next["pageId"]="cf6-s5";
   Assert.True(task.TryQueueSuccessor(next,"book-comic","panel:1",d=>{opens++;return true;}));
   if(boundary=="disconnected")task.OnDisconnected();if(boundary=="socket_not_ready")ready=false;
   if(boundary=="disposed")task.Dispose();
   if(boundary=="successor_expired"||boundary=="predecessor_expired"){
    var expired=Reply(boundary=="successor_expired"?next:before,"expired","finish");
    expired["callId"]=0;expired["panelInstanceId"]=boundary=="successor_expired"?"":"panel:1";
    task.HandleFlashResponse(expired,null);
   }
   task.OnPresentationClosed("panel:1",boundary!="close_failed");
   task.OnPresentationClosed("panel:1",true);Assert.Equal(0,opens);
  }
  [Theory][InlineData("failed","expired")][InlineData("continue","expired")]
  public void NonSuccessfulPredecessorNeverAuthorizesSuccessor(string reason,string phase){
   var sent=new List<JObject>();using var task=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});
   task.SetPostToWeb(s=>{},null,s=>{});var before=Data();before["pageId"]="cf6-s4";FinishCf6(task,sent,before,reason,phase);
   var next=Data("bookcomic:2");next["pageId"]="cf6-s5";
   Assert.False(task.TryQueueSuccessor(next,"book-comic","panel:1",d=>throw new Exception("invalid open")));
  }
  [Fact]public void PendingFinishAndHostClosedCannotAuthorizeSuccessor(){
   var sent=new List<JObject>();using var task=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});
   task.SetPostToWeb(s=>{},null,s=>{});var before=Data();before["pageId"]="cf6-s4";
   task.Reserve(before);task.Bind("panel:1",before.ToString());var next=Data("bookcomic:2");next["pageId"]="cf6-s5";
   task.HandleWebRequest("continue",Web("continue","finish",before));
   Assert.False(task.TryQueueSuccessor(next,"book-comic","panel:1",d=>true));
   task.OnHostClosed("panel:1");task.HandleFlashResponse(Reply(sent[sent.Count-1],"finished","finish"),null);
   Assert.False(task.TryQueueSuccessor(next,"book-comic","panel:1",d=>true));
  }
  [Fact]public void FailedSuccessorOpenIsAttemptedOnceAndNeverReopensPredecessor(){
   var sent=new List<JObject>();var pages=new List<string>();
   using var task=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});
   task.SetPostToWeb(s=>{},null,s=>{});var before=Data();before["pageId"]="cf6-s4";FinishCf6(task,sent,before);
   var next=Data("bookcomic:2");next["pageId"]="cf6-s5";
   Assert.True(task.TryQueueSuccessor(next,"book-comic","panel:1",d=>{pages.Add(d.Value<string>("pageId"));return false;}));
   task.OnPresentationClosed("panel:1",true);task.OnPresentationClosed("panel:1",true);
   Assert.Equal(new[]{"cf6-s5"},pages);Assert.False(task.Reserve(next));
  }
  [Fact]public void LeeCueIsBoundAndCannotUndoPendingFinish(){
   var sent=new List<JObject>();var closed=new List<string>();
   using var t=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});
   t.SetPostToWeb(s=>{},null,closed.Add);var d=Data();d["pageId"]="lee-breakout";t.Reserve(d);t.Bind("panel:1",d.ToString());
   var cue=(JObject)d.DeepClone();cue["cueIndex"]=3;
   t.HandleWebRequest("cue",Web("cue","foreign",cue,"foreign"));Assert.Empty(sent);
   var bad=(JObject)cue.DeepClone();bad["cueIndex"]=JToken.Parse("9999999999999999999999999999999999");
   t.HandleWebRequest("cue",Web("cue","bad",bad));Assert.Empty(sent);
   t.HandleWebRequest("cue",Web("cue","cue1",cue));Assert.Single(sent);
   Assert.Equal("bookComicCue",sent[0].Value<string>("action"));Assert.Equal(3,sent[0].Value<int>("cueIndex"));
   t.HandleWebRequest("skip",Web("skip","finish1",d));Assert.Equal(2,sent.Count);
   t.HandleFlashResponse(Reply(sent[0],"presenting","cue"),null);
   t.HandleWebRequest("continue",Web("continue","finish2",d));Assert.Equal(2,sent.Count);
   t.HandleFlashResponse(Reply(sent[1],"finished","finish"),null);Assert.Single(closed);
   t.HandleWebRequest("cue",Web("cue","late",cue));Assert.Equal(2,sent.Count);
  }
  [Fact]public void ExactPrepareFinishAndDuplicateAreBound(){var sent=new List<JObject>();var closed=new List<string>();using var t=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});t.SetPostToWeb(s=>{},null,closed.Add);var d=Data();Assert.True(t.Reserve(d));Assert.True(t.Bind("panel:1",d.ToString()));t.HandleWebRequest("prepared",Web("prepared","w1",d));Assert.Equal("bookComicPrepared",sent[0].Value<string>("action"));t.HandleFlashResponse(Reply(sent[0],"presenting","prepared"),null);t.HandleWebRequest("continue",Web("continue","w2",d));t.HandleWebRequest("continue",Web("continue","w2",d));Assert.Equal(2,sent.Count);t.HandleFlashResponse(Reply(sent[1],"finished","finish"),null);Assert.Single(closed);t.OnHostClosed("panel:1");Assert.Equal(2,sent.Count);Assert.False(t.Reserve(d));}
  [Fact]public void RealAs2TaskEnvelopeUnwrapsResponse(){var sent=new List<JObject>();var posts=new List<string>();using var t=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});t.SetPostToWeb(posts.Add,null,s=>{});var d=Data();t.Reserve(d);t.Bind("panel:1",d.ToString());t.HandleWebRequest("prepared",Web("prepared","w1",d));t.HandleFlashResponse(new JObject{["task"]="book_comic_response",["payload"]=Reply(sent[0],"presenting","prepared")},null);Assert.Single(posts);Assert.True(JObject.Parse(posts[0]).Value<bool>("success"));var expired=Reply(d,"expired","finish");expired["callId"]=0;expired["panelInstanceId"]="";t.HandleFlashResponse(new JObject{["task"]="book_comic_response",["payload"]=expired},null);Assert.False(t.CanOpen(d.ToString()));}
  [Fact]public void ExpiredBeforeOpenLeavesTombstone(){using var t=new BookComicTask(()=>true,s=>true);var d=Data();var r=Reply(d,"expired","finish");r["callId"]=0;r["panelInstanceId"]="";t.HandleFlashResponse(r,null);Assert.False(t.Reserve(d));}
  [Fact]public void ExpiredQueuedOpenCannotBind(){var closed=new List<string>();using var t=new BookComicTask(()=>true,s=>true);t.SetPostToWeb(s=>{},null,closed.Add);var d=Data();Assert.True(t.Reserve(d));var r=Reply(d,"expired","finish");r["callId"]=0;r["panelInstanceId"]="";t.HandleFlashResponse(r,null);Assert.False(t.CanOpen(d.ToString()));Assert.False(t.Bind("panel:1",d.ToString()));Assert.Empty(closed);}
  [Fact]public void ForeignInstanceAndStaleTerminalCannotCloseNewPage(){var sent=new List<JObject>();var closed=new List<string>();using var t=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});t.SetPostToWeb(s=>{},null,closed.Add);var d=Data();t.Reserve(d);t.Bind("panel:1",d.ToString());t.HandleWebRequest("skip",Web("skip","w1",d,"foreign"));Assert.Empty(sent);t.HandleWebRequest("skip",Web("skip","w2",d));var late=Reply(sent[0],"finished","finish");t.OnDisconnected();var d2=Data("bookcomic:2");Assert.True(t.Reserve(d2));Assert.True(t.Bind("panel:2",d2.ToString()));t.HandleFlashResponse(late,null);Assert.Single(closed);Assert.True(t.CanOpen(d2.ToString()));}
  [Fact]public void GenericWebTaskBridgeCannotForgeComicAuthority(){Assert.False(CF7Launcher.Guardian.WebOverlayForm.IsWebTaskRouterIngressAllowed("book_comic_response"));Assert.False(CF7Launcher.Guardian.WebOverlayForm.IsWebTaskRouterIngressAllowed("panel_request"));}
  [Theory][InlineData("lee-ambush")][InlineData("lee-breakout")][InlineData("lee-ending-normal")][InlineData("lee-ending-hidden")]
  public void LeePagesUseSameExactLifecycle(string page){var d=Data();d["pageId"]=page;Assert.NotNull(BookComicTask.BuildOpenData("book_chapter",d.ToString()));d["pageId"]=page+"-foreign";Assert.Null(BookComicTask.BuildOpenData("book_chapter",d.ToString()));}
  [Theory][InlineData("lee-entry-0")][InlineData("lee-clear-3")][InlineData("lee-awaken")]
  public void InRoomDialogueCannotOpenComic(string page){var d=Data();d["pageId"]=page;Assert.Null(BookComicTask.BuildOpenData("book_chapter",d.ToString()));}
  [Theory][InlineData("cf6-s1")][InlineData("cf6-s2")][InlineData("cf6-s3")][InlineData("cf6-s4")][InlineData("cf6-s5")][InlineData("cf6-s6")][InlineData("cf6-s7")][InlineData("cf6-end")]
  public void Cf6PagesUseSameExactLifecycle(string page){var d=Data();d["pageId"]=page;Assert.NotNull(BookComicTask.BuildOpenData("book_chapter",d.ToString()));d["pageId"]=page+"-foreign";Assert.Null(BookComicTask.BuildOpenData("book_chapter",d.ToString()));}
  [Fact]public void Cf6NarrationDoesNotUseLeeCueChannel(){var sent=new List<JObject>();using var t=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});var d=Data();d["pageId"]="cf6-s2";t.Reserve(d);t.Bind("panel:1",d.ToString());var cue=(JObject)d.DeepClone();cue["cueIndex"]=1;t.HandleWebRequest("cue",Web("cue","cue1",cue));Assert.Empty(sent);}
  [Fact]public void PreparedLeaseDegradationReachesCurrentWebCall(){var sent=new List<JObject>();var posts=new List<string>();using var t=new BookComicTask(()=>true,s=>{sent.Add(JObject.Parse(s.TrimEnd('\0')));return true;});t.SetPostToWeb(posts.Add,null,s=>{});var d=Data("bookcomic:lease");d["pageId"]="cf6-s1";t.Reserve(d);t.Bind("panel:1",d.ToString());t.HandleWebRequest("prepared",Web("prepared","lease-prepared",d));var reply=Reply(sent[0],"presenting","prepared");reply["error"]="bgm_lease_unavailable";t.HandleFlashResponse(reply,null);var response=JObject.Parse(Assert.Single(posts));Assert.True(response.Value<bool>("success"));Assert.Equal("prepared",response.Value<string>("cmd"));Assert.Equal("lease-prepared",response.Value<string>("callId"));Assert.Equal("bgm_lease_unavailable",response.Value<string>("error"));}
  [Fact]public void OpenDataRejectsUnknownPageAndFields(){var d=Data();Assert.NotNull(BookComicTask.BuildOpenData("book_chapter",d.ToString()));d["pageId"]="other";Assert.Null(BookComicTask.BuildOpenData("book_chapter",d.ToString()));d["pageId"]="boss";d["action"]="anything";Assert.Null(BookComicTask.BuildOpenData("book_chapter",d.ToString()));}
 }
}
