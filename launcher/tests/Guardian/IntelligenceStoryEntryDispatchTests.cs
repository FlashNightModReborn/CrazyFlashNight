using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.CompilerServices;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class IntelligenceStoryEntryDispatchTests
    {
        private static void Set(object target, string field, object value) =>
            target.GetType().GetField(field, BindingFlags.Instance | BindingFlags.NonPublic).SetValue(target, value);

        private sealed class Harness : IDisposable
        {
            internal readonly Queue<Action> Queue = new();
            internal readonly List<string> Sent = new(), Replies = new();
            internal readonly PanelHostController Host;
            internal readonly CompositionHelpSurface Surface;
            internal readonly WebOverlayForm Overlay;
            internal readonly IntelligenceTask Task;
            internal readonly BookshelfTask Bookshelf;
            internal readonly string Instance;

            internal Harness()
            {
                Host = new PanelHostController(a => Queue.Enqueue(a), a => a());
                Host.OpenPanel("intelligence", "{}");
                Pump();
                Instance = Host.ActivePanelInstanceId;
                // Exercise the production ingress and Host dispatcher without creating
                // HWNDs, browser controllers, hooks or a game/save session.
                Surface = (CompositionHelpSurface)RuntimeHelpers.GetUninitializedObject(typeof(CompositionHelpSurface));
                Overlay = (WebOverlayForm)RuntimeHelpers.GetUninitializedObject(typeof(WebOverlayForm));
                GC.SuppressFinalize(Surface); GC.SuppressFinalize(Overlay);
                Set(Surface, "_profile", CompositionPanelProfile.Intelligence);
                Set(Surface, "_ready", true); Set(Surface, "_active", true);
                Set(Surface, "_panelInstance", Instance);
                Set(Overlay, "_webReady", true); Set(Overlay, "_panelHost", Host);
                Task = new IntelligenceTask(System.IO.Path.GetTempPath(), () => true, Sent.Add);
                Task.SetPostToWeb(Replies.Add);
                Set(Overlay, "_intelligenceTask", Task);
                Bookshelf = new BookshelfTask(() => true, text => { Sent.Add(text); return true; }, 10000, () => new JArray(),
                    _ => CF7Launcher.Save.SolResolveResult.NewSnapshot(new JObject(), "fixture"));
                Set(Overlay, "_bookshelfTask", Bookshelf);
                Set(Overlay, "_leeResponseLeaseProvider", (Func<Action<string>>)(() => Replies.Add));
                Surface.InboundPanelMessage += m => Overlay.HandleCompositionIntelligenceMessage(m.ToString());
            }
            internal JObject Request(string instance) => new JObject {
                ["type"]="panel", ["panel"]="intelligence", ["cmd"]="open_lee_story",
                ["panelInstanceId"]=instance, ["itemName"]="黑龙令", ["pageKey"]="5", ["callId"]="lee.entry.1"
            };
            internal void Pump() { int limit=50; while(Queue.Count>0) { Assert.True(limit-->0); Queue.Dequeue()(); } }
            public void Dispose() { Bookshelf.Dispose(); Task.Dispose(); Host.Dispose(); }
        }

        private static JObject LeeRequest(string instance, string kind="play", string target="lee-trial") => new JObject {
            ["type"]="panel", ["panel"]="intelligence", ["domain"]="bookshelf", ["cmd"]="commit", ["callId"]="lee.start.1",
            ["panelInstanceId"]=instance, ["payload"]=new JObject { ["v"]=1, ["token"]="bookshelf.lee.1", ["kind"]=kind, ["target"]=target }
        };
        [Fact]
        public void DirectStartUsesSharedSaveTaskAndFrozenReaderResponse()
        {
            using var h = new Harness();
            h.Surface.DispatchEnvelopeForRecheck(LeeRequest(h.Instance));
            var wire = JObject.Parse(Assert.Single(h.Sent).TrimEnd('\0'));
            Assert.Equal("bookshelfCommit", wire.Value<string>("action"));
            Assert.Equal("lee-trial", wire.Value<string>("target"));
            Assert.StartsWith("bookrun_", wire.Value<string>("runSlot"));
            var later = new List<string>();
            Set(h.Overlay, "_leeResponseLeaseProvider", (Func<Action<string>>)(() => later.Add));
            h.Bookshelf.HandleFlashResponse(new JObject { ["callId"]=wire["callId"], ["v"]=1, ["operation"]="commit",
                ["token"]=wire["token"], ["success"]=false, ["error"]="locked" }, null);
            var reply = JObject.Parse(Assert.Single(h.Replies));
            Assert.Equal("intelligence", reply.Value<string>("panel"));
            Assert.Equal(h.Instance, reply.Value<string>("panelInstanceId"));
            Assert.Equal("bookshelf", reply.Value<string>("domain"));
            Assert.Empty(later);
        }
        [Fact]
        public void ReaderCanSettleInterruptedBookRunBeforeDirectStart()
        {
            using var h = new Harness();
            h.Surface.DispatchEnvelopeForRecheck(LeeRequest(h.Instance, "settle", "bookrun_leftover_1"));
            var wire = JObject.Parse(Assert.Single(h.Sent).TrimEnd('\0'));
            Assert.Equal("bookshelfCommit", wire.Value<string>("action"));
            Assert.Equal("settle", wire.Value<string>("kind"));
            Assert.Equal("bookrun_leftover_1", wire.Value<string>("target"));
        }
        [Theory]
        [InlineData("switch","slot_b")][InlineData("return","slot_b")][InlineData("play","repair-campus")][InlineData("settle","slot_b")]
        public void ReaderCannotUseOtherSharedSaveActions(string kind,string target)
        {
            using var h = new Harness();
            h.Surface.DispatchEnvelopeForRecheck(LeeRequest(h.Instance,kind,target));
            h.Surface.DispatchEnvelopeForRecheck(LeeRequest("foreign.reader"));
            var forged=LeeRequest(h.Instance); forged["payload"]["runSlot"]="bookrun_forged";
            h.Surface.DispatchEnvelopeForRecheck(forged);
            Assert.Empty(h.Sent);
        }
        [Fact]
        public void CurrentReaderReachesFlashCommandAndKeepsFlashDenial()
        {
            using var h = new Harness();
            var request = h.Request(h.Instance);
            request["decryptLevel"]=999; request["unlocked"]=true;
            h.Surface.DispatchEnvelopeForRecheck(request);
            var command = JObject.Parse(Assert.Single(h.Sent).TrimEnd('\0'));
            Assert.Equal("intelligenceLeeStory", command.Value<string>("action"));
            Assert.Equal("黑龙令", command.Value<string>("itemName"));
            Assert.Equal("5", command.Value<string>("pageKey"));
            Assert.Null(command["decryptLevel"]); Assert.Null(command["unlocked"]);
            h.Task.HandleFlashResponse(new JObject { ["callId"]=command["callId"], ["success"]=false, ["error"]="locked" }, null);
            var reply=JObject.Parse(Assert.Single(h.Replies));
            Assert.Equal("lee.entry.1", reply.Value<string>("callId"));
            Assert.False(reply.Value<bool>("success")); Assert.Equal("locked", reply.Value<string>("error"));
            Assert.Equal(h.Instance, h.Host.ActivePanelInstanceId);
        }

        [Theory]
        [InlineData(null)] [InlineData("")] [InlineData("retired.reader")]
        public void ForeignReaderCannotForwardStoryIntent(string instance)
        {
            using var h = new Harness();
            h.Surface.DispatchEnvelopeForRecheck(h.Request(instance));
            Assert.Empty(h.Sent);
        }

        [Fact]
        public void RetiredSurfaceAndUnrelatedCommandsCannotForward()
        {
            using var h = new Harness();
            var request=h.Request(h.Instance); request["cmd"]="bookshelfCommit";
            h.Surface.DispatchEnvelopeForRecheck(request);
            request=h.Request(h.Instance); request["nativeCause"]="page_close";
            h.Surface.DispatchEnvelopeForRecheck(request);
            Set(h.Surface,"_active",false);
            h.Surface.DispatchEnvelopeForRecheck(h.Request(h.Instance));
            Assert.Empty(h.Sent);
        }
    }
}
