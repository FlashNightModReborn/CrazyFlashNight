using System.Collections.Generic;
using System;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class BookshelfReturnPresentationTests
    {
        private static JObject Receipt(string phase) => new JObject { ["kind"] = "return", ["phase"] = phase };
        private static JObject Cover() => new JObject { ["requestId"] = "tr:8", ["revision"] = 2, ["generation"] = 0, ["phase"] = "cover" };
        [Fact]
        public void FailedPostAndForegroundRejectedAckAreRetriedUntilExactConfirmation()
        {
            var now = DateTime.UtcNow; bool visible = false, delivered = false; int posts = 0;
            var p = new BookshelfReturnPresentation(i => i == "book.1", () => true, () => true,
                _ => { posts++; return delivered; }, () => visible, now: () => now);
            p.Observe("book.1", Receipt("switching"));
            Assert.False(p.Post(Cover())); Assert.Equal(0, posts);
            visible = true; Assert.False(p.Post(Cover()));
            delivered = true; Assert.True(p.Post(Cover())); Assert.Equal(2, posts);
            // Web sent a receipt, but Host lost foreground before accepting it.
            visible = false; now = now.AddSeconds(1); Assert.False(p.Post(Cover()));
            visible = true; Assert.True(p.Post(Cover())); Assert.Equal(3, posts);
            Assert.False(p.Post(Cover())); // bounded retry rate
            var receipt = Cover(); receipt["kind"] = "covered"; receipt["revision"] = 1;
            p.Confirm(receipt); now = now.AddSeconds(1); Assert.True(p.Post(Cover()));
            receipt["revision"] = 2; p.Confirm(receipt);
            now = now.AddSeconds(1); Assert.False(p.Post(Cover())); Assert.Equal(4, posts);
            var reveal = Cover(); reveal["revision"] = 3; reveal["phase"] = "reveal";
            Assert.True(p.Post(reveal)); // a new phase still needs presentation
        }
        [Fact]
        public void FailedCompletionPostRetriesWithoutTakingPauseTwice()
        {
            bool deliver = true; int pauses = 0;
            var p = new BookshelfReturnPresentation(i => i == "book.1", () => true,
                () => { pauses++; return true; }, _ => deliver, () => true);
            p.Observe("book.1", Receipt("switching")); p.Post(Cover());
            deliver = false; p.CompleteScene(); p.Observe("book.1", Receipt("applied"));
            Assert.True(p.Active); Assert.Equal(1, pauses);
            deliver = true; p.RetryPauseRestore();
            Assert.False(p.Active); Assert.Equal(1, pauses);
        }
        [Fact]
        public void LoadingReleasesOnlyItsWebPauseAndRestoresAfterSceneRetires()
        {
            var events = new List<string>();
            var p = new BookshelfReturnPresentation(i => i == "book.1", () => { events.Add("unpause"); return true; },
                () => { events.Add("pause"); return true; }, text => { events.Add(JObject.Parse(text).Value<string>("type")); return true; }, () => true);
            p.Observe("book.1", Receipt("switching")); p.Observe("book.1", Receipt("switching"));
            Assert.True(p.Loading);
            Assert.Equal(new[] { "unpause" }, events);
            p.Post(new JObject { ["requestId"] = "tr:2", ["revision"] = 3, ["generation"] = 0 });
            p.CompleteScene(); p.CompleteScene(); p.Observe("book.1", Receipt("switching"));
            Assert.False(p.Loading); Assert.True(p.Active);
            Assert.Equal(new[] { "unpause", "bookshelf_transition", "pause", "bookshelf_transition_complete" }, events);
            p.Observe("book.1", Receipt("applied")); Assert.False(p.Active);
        }
        [Fact]
        public void ReplacementAndLateCompletionCannotPauseAnotherPanel()
        {
            string active = "book.1"; int pauses = 0, posts = 0;
            var p = new BookshelfReturnPresentation(i => i == active, () => true, () => { pauses++; return true; }, _ => { posts++; return true; }, () => true);
            p.Observe(active, Receipt("switching")); active = "settings.2";
            p.Post(new JObject()); p.CompleteScene(); p.Observe("book.1", Receipt("applied"));
            Assert.False(p.Active); Assert.False(p.Loading); Assert.Equal(0, pauses); Assert.Equal(0, posts);
        }
        [Fact]
        public void PauseDeliveryFailureIsRetriedWithoutReleasingTwice()
        {
            int release = 0, restore = 0;
            var p = new BookshelfReturnPresentation(i => i == "book.1", () => ++release > 1,
                () => ++restore > 2, _ => true, () => true);
            p.Observe("book.1", Receipt("switching")); p.Observe("book.1", Receipt("switching"));
            p.RetryPauseRestore(); Assert.Equal(0, restore);
            p.CompleteScene();
            // The Web may already have its terminal result and stop querying;
            // the scene controller keeps retrying pause delivery independently.
            p.Observe("book.1", Receipt("applied")); p.RetryPauseRestore();
            Assert.Equal(2, release); Assert.Equal(3, restore); Assert.False(p.Active);
        }
        [Fact]
        public void CompleteCarriesTheExactPaintedTransitionIdentity()
        {
            var posts = new List<JObject>();
            var p = new BookshelfReturnPresentation(i => i == "book.1", () => true, () => true,
                text => { posts.Add(JObject.Parse(text)); return true; }, () => true);
            p.Observe("book.1", Receipt("switching"));
            p.Post(new JObject { ["requestId"] = "tr:9", ["revision"] = 5, ["generation"] = 2 }); p.CompleteScene();
            Assert.Equal("book.1", posts[1].Value<string>("panelInstanceId"));
            foreach (string key in new[] { "requestId", "revision", "generation" }) Assert.Equal(posts[0][key], posts[1][key]);
        }
        [Fact]
        public void NonReturnAndUnacceptedWritesDoNotStartLoadingPresentation()
        {
            int effects = 0;
            var p = new BookshelfReturnPresentation(i => i == "book.1", () => { effects++; return true; }, () => true, _ => true, () => true);
            p.Observe("book.1", Receipt("save_pending")); p.Observe("foreign", Receipt("switching"));
            p.Observe("book.1", new JObject { ["kind"] = "switch", ["phase"] = "switching" });
            Assert.False(p.Active); Assert.Equal(0, effects);
        }
        [Fact]
        public void EarlyFailureKeepsFallbackLoadingUntilSceneRetires()
        {
            int pauses = 0;
            var p = new BookshelfReturnPresentation(i => i == "book.1", () => true,
                () => { pauses++; return true; }, _ => true, () => true);
            p.Observe("book.1", Receipt("switching")); p.Observe("book.1", Receipt("expired"));
            Assert.True(p.Loading); Assert.Equal(0, pauses);
            p.CompleteScene();
            Assert.False(p.Active); Assert.False(p.Loading); Assert.Equal(1, pauses);
        }
        [Fact]
        public void HiddenOrReplacedBookshelfCannotRepairWindowOrder()
        {
            string owner = "book.1"; bool visible = true; int repairs = 0;
            var p = new BookshelfReturnPresentation(i => i == owner, () => true,
                () => true, _ => true, () => visible, () => repairs++);
            p.RestoreOrder(); Assert.Equal(0, repairs);
            p.Observe(owner, Receipt("switching")); p.RestoreOrder(); Assert.Equal(1, repairs);
            visible = false; p.RestoreOrder(); Assert.Equal(1, repairs);
            visible = true; owner = "replacement.2"; p.RestoreOrder(); Assert.Equal(1, repairs);
        }
    }
}
